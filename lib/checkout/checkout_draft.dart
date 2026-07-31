import 'dart:async';
import 'dart:math';

import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import 'checkout_catalog_cache.dart';
import 'checkout_outbox.dart';
import 'checkout_receipt.dart';
import 'checkout_sale.dart';

/// Raised when a draft cannot be built from trusted local state.
///
/// The draft is refused before anything durable is written, so a refusal never
/// leaves partial checkout evidence behind.
final class CheckoutDraftException implements Exception {
  const CheckoutDraftException(this.code);

  final String code;

  @override
  String toString() => 'CheckoutDraftException($code)';
}

typedef CheckoutIdFactory = String Function();
typedef CheckoutDraftClock = DateTime Function();

/// Resolves the business date recorded on a sale from the current UTC instant.
typedef CheckoutBusinessDateResolver = String Function(DateTime nowUtc);

/// Africa/Nairobi has no daylight saving, so a fixed offset stays deterministic.
const Duration checkoutBusinessDayOffset = Duration(hours: 3);

/// One requested sale line naming a tenant-local product and a quantity.
final class CheckoutDraftLineRequest {
  const CheckoutDraftLineRequest({
    required this.productId,
    required this.quantity,
  });

  final String productId;
  final int quantity;
}

/// The bounded input accepted by [CheckoutDraftService.createDraft].
///
/// The device identity is deliberately not a caller input: it is resolved once
/// per installation from durable local state so a receipt cannot be attributed
/// to a device that never issued it.
final class CheckoutDraftRequest {
  CheckoutDraftRequest({
    required List<CheckoutDraftLineRequest> lines,
    this.discountMinor = 0,
    this.shiftId,
  }) : lines = List<CheckoutDraftLineRequest>.unmodifiable(lines);

  final List<CheckoutDraftLineRequest> lines;
  final int discountMinor;
  final String? shiftId;
}

/// Builds one frozen `CheckoutSalePayload` v1 draft from the offline cache.
///
/// The service writes only through [HiveCheckoutOutbox.saveOffline]; it never
/// touches Firestore. Draft creation is serialized by one local lock and bound
/// to one captured session epoch, so two concurrent drafts can neither reuse a
/// checkout ID nor persist work for a tenant the device has already left. That
/// same lock guards receipt allocation, so two cashiers checking out on one
/// device cannot receive the same receipt number.
final class CheckoutDraftService {
  CheckoutDraftService({
    required TenantSessionController sessionController,
    required HiveCheckoutCatalogCache cache,
    required HiveCheckoutOutbox outbox,
    required HiveCheckoutReceiptCounters receipts,
    CheckoutIdFactory? checkoutIdFactory,
    CheckoutDraftClock? clock,
    CheckoutBusinessDateResolver? businessDateResolver,
  }) : _sessionController = sessionController,
       _cache = cache,
       _outbox = outbox,
       _receipts = receipts,
       _checkoutIdFactory = checkoutIdFactory ?? _generateCheckoutId,
       _clock = clock ?? _utcNow,
       _businessDateResolver = businessDateResolver ?? checkoutBusinessDate;

  final TenantSessionController _sessionController;
  final HiveCheckoutCatalogCache _cache;
  final HiveCheckoutOutbox _outbox;
  final HiveCheckoutReceiptCounters _receipts;
  final CheckoutIdFactory _checkoutIdFactory;
  final CheckoutDraftClock _clock;
  final CheckoutBusinessDateResolver _businessDateResolver;
  Future<void> _tail = Future<void>.value();

  /// Saves one deterministic offline checkout for the selected session.
  ///
  /// The session is captured when the draft is requested, so a checkout queued
  /// behind another draft can never be persisted for a tenant or epoch the
  /// device has already left.
  Future<CheckoutOutboxRecord> createDraft(CheckoutDraftRequest request) {
    final captured = _sessionController.session;
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return Future<CheckoutOutboxRecord>(() async {
      await previous;
      try {
        return await _createDraft(request, captured);
      } finally {
        release.complete();
      }
    });
  }

  Future<CheckoutOutboxRecord> _createDraft(
    CheckoutDraftRequest request,
    TenantSession? captured,
  ) async {
    if (captured == null || !captured.canAccess()) {
      throw const CheckoutDraftException('no_selected_session');
    }
    if (!_owns(captured)) {
      throw const CheckoutDraftException('session_changed');
    }

    final lines = _validatedLines(request.lines);
    final snapshot = await _cache.read(
      uid: captured.uid,
      tenantId: captured.tenantId,
    );
    if (snapshot == null || !snapshot.ownsSession(captured)) {
      throw const CheckoutDraftException('catalog_cache_unavailable');
    }
    if (!_owns(captured)) {
      throw const CheckoutDraftException('session_changed');
    }

    var subtotalMinor = 0;
    final items = <Map<String, Object?>>[];
    for (final line in lines) {
      final product = snapshot.productById(line.productId);
      if (product == null) {
        throw const CheckoutDraftException('unknown_product');
      }
      final unitPriceMinor = checkoutMinorUnitsFromMajor(product.price);
      if (unitPriceMinor == null) {
        throw const CheckoutDraftException('price_not_representable');
      }
      subtotalMinor += unitPriceMinor * line.quantity;
      items.add(<String, Object?>{
        'productId': product.id,
        'name': product.name,
        'categoryId': product.categoryId,
        'quantity': line.quantity,
        'unitPriceMinor': unitPriceMinor,
      });
    }
    if (request.discountMinor < 0 || request.discountMinor > subtotalMinor) {
      throw const CheckoutDraftException('invalid_discount');
    }

    final checkoutId = _validatedCheckoutId();
    final businessDate = _validatedBusinessDate();
    final deviceId = await _resolvedDeviceId();
    if (!_owns(captured)) {
      throw const CheckoutDraftException('session_changed');
    }

    // The sequence is allocated last, after every refusable check, so a
    // rejected draft leaves an unused gap rather than a reused receipt.
    final int receiptSequence;
    try {
      receiptSequence = await _receipts.allocateSequence(
        tenantId: captured.tenantId,
        deviceId: deviceId,
        businessDate: businessDate,
      );
    } on CheckoutReceiptException catch (error) {
      throw CheckoutDraftException(error.code);
    }
    final receiptNumber = formatCheckoutReceiptNumber(
      deviceId: deviceId,
      businessDate: businessDate,
      sequence: receiptSequence,
    );

    final payload = <String, Object?>{
      'schemaVersion': checkoutSalePayloadSchemaVersion,
      'checkoutId': checkoutId,
      'tenantId': captured.tenantId,
      'soldById': captured.uid,
      'currency': snapshot.configuration.currency,
      'businessDate': businessDate,
      'createdAtMs': _clock().toUtc().millisecondsSinceEpoch,
      if (request.shiftId != null) 'shiftId': request.shiftId,
      'deviceId': deviceId,
      'receiptNumber': receiptNumber,
      'receiptSequence': receiptSequence,
      'items': items,
      'subtotalMinor': subtotalMinor,
      'discountMinor': request.discountMinor,
      'totalMinor': subtotalMinor - request.discountMinor,
    };

    // Prove the frozen submission contract before the draft becomes evidence.
    try {
      CheckoutSalePayload.fromLocalPayload(
        session: captured,
        checkoutId: checkoutId,
        payload: payload,
        payloadHash: checkoutPayloadHash(payload),
      );
    } on CheckoutSaleFormatException {
      throw const CheckoutDraftException('draft_contract_violation');
    }

    if (!_owns(captured)) {
      throw const CheckoutDraftException('session_changed');
    }
    return _outbox.saveOffline(
      uid: captured.uid,
      tenantId: captured.tenantId,
      checkoutId: checkoutId,
      payload: payload,
    );
  }

  List<CheckoutDraftLineRequest> _validatedLines(
    List<CheckoutDraftLineRequest> lines,
  ) {
    if (lines.isEmpty || lines.length > maximumCheckoutSaleLines) {
      throw const CheckoutDraftException('invalid_line_count');
    }
    final productIds = <String>{};
    for (final line in lines) {
      try {
        validateTenantDocumentId(line.productId, fieldName: 'productId');
      } on ArgumentError {
        throw const CheckoutDraftException('invalid_product_id');
      }
      if (!productIds.add(line.productId)) {
        throw const CheckoutDraftException('duplicate_product');
      }
      if (line.quantity < 1 || line.quantity > maximumCheckoutLineQuantity) {
        throw const CheckoutDraftException('invalid_quantity');
      }
    }
    return lines;
  }

  /// Resolves the durable installation identity for this device.
  Future<String> _resolvedDeviceId() async {
    try {
      return await _receipts.resolveDeviceId();
    } on CheckoutReceiptException catch (error) {
      throw CheckoutDraftException(error.code);
    } catch (_) {
      throw const CheckoutDraftException('device_identity_unavailable');
    }
  }

  String _validatedBusinessDate() {
    final businessDate = _businessDateResolver(_clock().toUtc());
    try {
      return validateCheckoutBusinessDate(businessDate);
    } on ArgumentError {
      throw const CheckoutDraftException('invalid_business_date');
    }
  }

  String _validatedCheckoutId() {
    final String checkoutId;
    try {
      checkoutId = _checkoutIdFactory();
    } catch (_) {
      throw const CheckoutDraftException('invalid_checkout_id');
    }
    try {
      checkoutOutboxStorageKey(
        uid: 'probe',
        tenantId: 'probe',
        checkoutId: checkoutId,
      );
    } on ArgumentError {
      throw const CheckoutDraftException('invalid_checkout_id');
    }
    return checkoutId;
  }

  bool _owns(TenantSession captured) {
    final current = _sessionController.session;
    return current != null &&
        current.uid == captured.uid &&
        current.tenantId == captured.tenantId &&
        current.epoch == captured.epoch;
  }
}

/// Converts a cached major-unit price into exact integer minor units.
///
/// A value that is not exactly representable in minor units is rejected rather
/// than silently rounded, so the recorded sale always matches the catalog.
int? checkoutMinorUnitsFromMajor(num value) {
  final major = value.toDouble();
  if (!major.isFinite || major < 0) return null;
  final scaled = major * 100;
  if (scaled > maximumCheckoutMinorAmount) return null;
  final rounded = scaled.roundToDouble();
  if ((scaled - rounded).abs() > 1e-6) return null;
  final minor = rounded.toInt();
  return minor < 0 || minor > maximumCheckoutMinorAmount ? null : minor;
}

/// Formats the Africa/Nairobi business date for a UTC instant.
String checkoutBusinessDate(DateTime nowUtc) {
  final local = nowUtc.toUtc().add(checkoutBusinessDayOffset);
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-$month-$day';
}

String _generateCheckoutId() {
  final random = Random.secure();
  final suffix = List<String>.generate(
    4,
    (_) => random.nextInt(0x10000).toRadixString(16).padLeft(4, '0'),
  ).join();
  return 'co-${DateTime.now().toUtc().millisecondsSinceEpoch}-$suffix';
}

DateTime _utcNow() => DateTime.now().toUtc();
