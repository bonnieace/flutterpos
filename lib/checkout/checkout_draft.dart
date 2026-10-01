import 'dart:async';
import 'dart:math';
import 'package:uzapay_pos/observability/app_telemetry.dart';

import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import 'checkout_catalog_cache.dart';
import 'checkout_catalog_local_sales.dart';
import 'checkout_outbox.dart';
import 'checkout_receipt.dart';
import 'checkout_sale.dart';
import 'checkout_tender.dart';

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

/// The canonical shift one draft is attributed to.
///
/// It repeats the identity the sale will carry so the draft service can prove
/// the recorded `shiftId` belongs to the same cashier, business, device, and
/// business date as the sale itself.
final class CheckoutShiftAttribution {
  const CheckoutShiftAttribution({
    required this.uid,
    required this.tenantId,
    required this.shiftId,
    required this.deviceId,
    required this.businessDate,
  });

  final String uid;
  final String tenantId;
  final String shiftId;
  final String deviceId;
  final String businessDate;
}

/// Either the shift a checkout may be attributed to, or the refusal code.
final class CheckoutShiftBinding {
  const CheckoutShiftBinding.bound(CheckoutShiftAttribution this.attribution)
    : refusalCode = null;

  const CheckoutShiftBinding.refused(String this.refusalCode)
    : attribution = null;

  final CheckoutShiftAttribution? attribution;
  final String? refusalCode;
}

/// The tenant-scoped policy consulted before any checkout may start.
///
/// The shift lifecycle implements this to supply the open shift every sale is
/// attributed to, and to enforce the frozen restriction that a cashier cannot
/// open checkout in a second business while another business still holds an
/// open shift on the same device.
abstract interface class CheckoutShiftBinder {
  Future<CheckoutShiftBinding> bindCheckoutShift(TenantSession session);
}

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

/// The total a customer and the till agreed on, and why.
///
/// **The total, not the discount, is what the cashier agreed**, so it is what
/// the request carries. The draft builder re-prices every line from the cache
/// and takes the difference from that, so a listed price that moved between
/// the cart and the save still leaves the sale recording exactly what the
/// customer was told they would pay.
final class CheckoutAgreedPrice {
  const CheckoutAgreedPrice({required this.totalMinor, required this.reason});

  /// What the customer pays, in minor units.
  final int totalMinor;

  /// Why, as typed. The draft builder trims it and holds it to
  /// [checkoutDiscountReason].
  final String reason;
}

/// The bounded input accepted by [CheckoutDraftService.createDraft].
///
/// The device identity is deliberately not a caller input: it is resolved once
/// per installation from durable local state so a receipt cannot be attributed
/// to a device that never issued it.
/// The shift is deliberately not a caller input either: it is taken from the
/// guarded shift lifecycle so a sale cannot name a shift the cashier does not
/// hold.
///
/// The tender *is* a caller input, and it may be absent. It is the one thing
/// here only the person at the till knows, and there is no default, because a
/// guessed payment method is indistinguishable from an observed one once it is
/// written. Absent means the question was not answered at the counter, which is
/// a fact about the sale rather than a gap in it: nothing is refused for it,
/// and the method can be set afterwards from the sale's own card.
final class CheckoutDraftRequest {
  CheckoutDraftRequest({
    required List<CheckoutDraftLineRequest> lines,
    this.tender,
    this.discountMinor = 0,
    this.agreedPrice,
    this.customer,
  }) : lines = List<CheckoutDraftLineRequest>.unmodifiable(lines);

  final List<CheckoutDraftLineRequest> lines;

  /// How the cashier says the customer paid, or null if they did not say.
  /// Nothing verifies the payment either way.
  final CheckoutTender? tender;

  final int discountMinor;

  /// The price agreed at the till, or null for a sale at the listed prices.
  ///
  /// **The one way the till takes money off a sale**, and exclusive of
  /// [discountMinor]: a request naming both is refused, since two ways of
  /// taking money off one sale could only disagree.
  final CheckoutAgreedPrice? agreedPrice;

  /// Who the sale is for, chosen at the till, or null for a walk-in.
  ///
  /// **Chosen before the sale, never asked for during it.** The selector sits
  /// above the cart and defaults to walk-in, so nothing stands between the
  /// cashier pressing save and the sale being written.
  final CheckoutSaleCustomer? customer;
}

/// Builds one frozen `CheckoutSalePayload` v2 draft from the offline cache.
///
/// New drafts are always v2 and may or may not record a tender. Version 1
/// drafts are never produced here; they only survive as already-persisted
/// evidence, which [CheckoutSalePayload] still parses and submits unchanged.
///
/// The service writes only through [HiveCheckoutOutbox.saveOffline]; it never
/// touches Firestore. Draft creation is serialized by one local lock and bound
/// to one captured session epoch, so two concurrent drafts can neither reuse a
/// checkout ID nor persist work for a tenant the device has already left. That
/// same lock guards receipt allocation, so two cashiers checking out on one
/// device cannot receive the same receipt number.
///
/// Every draft is attributed to the canonical open shift supplied by
/// [CheckoutShiftBinder]. The binder is required: a checkout with no proven
/// open shift is refused rather than recorded as an unreconcilable sale.
/// What a checkout surface learns once a draft is durable.
///
/// Deliberately not the outbox record: a screen needs the receipt to hand the
/// customer and nothing else. Keeping the record out of the UI means no surface
/// can read a lease, an attempt count, or a payload hash, and no surface can be
/// tempted to act on a state the sync and recovery workers own.
final class CheckoutSavedDraft {
  const CheckoutSavedDraft({
    required this.checkoutId,
    required this.receiptNumber,
    this.receiptPrintFailure,
  });

  /// The immutable checkout identity the sale will be written under.
  final String checkoutId;

  /// The customer-facing receipt, absent only if the payload somehow lacks one.
  final String? receiptNumber;

  /// Why the receipt did not reach the printer, or null.
  ///
  /// **A `PrinterTransportCode`, carried back rather than swallowed.** The sale
  /// is committed before the receipt is queued and a printer is never allowed
  /// to un-write it — but a receipt that silently did not print is exactly the
  /// failure `docs/printer_transport.md` §2 objects to, so the reason travels
  /// with the answer and the till states it. Null means the receipt was sent,
  /// **or** that this build queues no receipts at all.
  final String? receiptPrintFailure;
}

/// Queues a receipt for a draft that is already durable.
///
/// **Called after the sale is written, never before**, which is §6.3 applied to
/// printing: the sale is recorded first and the receipt is produced over
/// committed state. Returns a `PrinterTransportCode` when the receipt did not
/// reach the printer, or null when it did.
typedef CheckoutDraftReceiptHook =
    Future<String?> Function(
      CheckoutOutboxRecord record,
      TenantSession session,
    );

/// The single action a checkout surface may take: save one offline draft.
///
/// A cart depends on this rather than on [CheckoutDraftService] itself, so the
/// screen cannot reach the session controller, the outbox, or the receipt
/// counters the service composes - and cannot move a checkout through any state
/// the sync and recovery workers own.
abstract interface class CheckoutDraftSink {
  Future<CheckoutSavedDraft> saveDraft(CheckoutDraftRequest request);
}

final class CheckoutDraftService implements CheckoutDraftSink {
  CheckoutDraftService({
    required TenantSessionController sessionController,
    required HiveCheckoutCatalogCache cache,
    required HiveCheckoutOutbox outbox,
    required HiveCheckoutReceiptCounters receipts,
    required CheckoutShiftBinder shiftBinder,
    CheckoutIdFactory? checkoutIdFactory,
    CheckoutDraftClock? clock,
    CheckoutDraftReceiptHook? onSaved,
    CheckoutCatalogLocalSales? localSales,
  }) : _onSaved = onSaved,
       _localSales = localSales,
       _sessionController = sessionController,
       _cache = cache,
       _outbox = outbox,
       _receipts = receipts,
       _shiftBinder = shiftBinder,
       _checkoutIdFactory = checkoutIdFactory ?? _generateCheckoutId,
       _clock = clock ?? _utcNow;

  final TenantSessionController _sessionController;
  final HiveCheckoutCatalogCache _cache;
  final HiveCheckoutOutbox _outbox;
  final HiveCheckoutReceiptCounters _receipts;
  final CheckoutShiftBinder _shiftBinder;
  final CheckoutIdFactory _checkoutIdFactory;
  final CheckoutDraftClock _clock;

  /// Absent in every build that does not print, which is what keeps this
  /// service free of any dependency on the printing slice.
  final CheckoutDraftReceiptHook? _onSaved;

  /// Told what left the shelf, so the register can stop reporting a figure a
  /// refresh ago. Absent in a build that does not track it - see
  /// [CheckoutCatalogLocalSales].
  final CheckoutCatalogLocalSales? _localSales;

  Future<void> _tail = Future<void>.value();

  /// Saves one deterministic offline checkout for the selected session.
  ///
  /// The session is captured when the draft is requested, so a checkout queued
  /// behind another draft can never be persisted for a tenant or epoch the
  /// device has already left.
  /// Saves one draft and reports only what a surface may know about it.
  @override
  Future<CheckoutSavedDraft> saveDraft(CheckoutDraftRequest request) async {
    final session = _sessionController.session;
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'checkout.save',
      screen: 'checkout',
      context: {
        'user_id': session?.uid,
        'tenant_id': session?.tenantId,
        'line_count': request.lines.length,
      },
    );
    final CheckoutOutboxRecord record;
    try {
      record = await telemetry.trace(
        operation,
        'persist_checkout',
        () => createDraft(request),
      );
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'checkout.save',
        data: {
          'lines': request.lines
              .map(
                (line) => {
                  'product_id': line.productId,
                  'quantity': line.quantity,
                },
              )
              .toList(),
          'discount_minor': request.discountMinor,
          // The figure, never the reason: a reason is free text a cashier
          // typed and has no place in a diagnostic.
          'agreed_total_minor': request.agreedPrice?.totalMinor,
        },
      );
      rethrow;
    }
    telemetry.recordStep(
      operation,
      'saved_locally',
      data: {'checkout_id': record.checkoutId},
    );
    // **Told here, after the sale is durable and before anything can fail.**
    // A sale deliberately does not refresh the catalog, so without this the
    // register goes on reporting the stock the last refresh saw - and the
    // device has just proved it wrong. Read from the recorded payload rather
    // than the request, so what is subtracted is what was actually filed.
    _recordUnitsSold(record);
    final receiptNumber = record.payload['receiptNumber'];
    return CheckoutSavedDraft(
      checkoutId: record.checkoutId,
      receiptNumber: receiptNumber is String ? receiptNumber : null,
      receiptPrintFailure: await _queueReceipt(record),
    );
  }

  /// Subtracts one durable sale's units from what the register reports.
  ///
  /// **Nothing here may throw.** The sale is already written; a tally is a
  /// convenience over it, and a malformed line is a figure not subtracted
  /// rather than a sale undone. A line the payload does not describe as a
  /// whole number is skipped for the same reason.
  void _recordUnitsSold(CheckoutOutboxRecord record) {
    final sales = _localSales;
    if (sales == null) return;
    final items = record.payload['items'];
    if (items is! List) return;
    final units = <String, int>{};
    for (final item in items) {
      if (item is! Map) continue;
      final productId = item['productId'];
      final quantity = item['quantity'];
      if (productId is! String || quantity is! int) continue;
      units[productId] = (units[productId] ?? 0) + quantity;
    }
    sales.recordSale(
      uid: record.uid,
      tenantId: record.tenantId,
      unitsByProduct: units,
    );
  }

  /// Hands the committed draft to the receipt hook, if there is one.
  ///
  /// **The `catch` here is the one place in this slice where swallowing is
  /// right, and it is not silent.** `CheckoutPrintDispatcher` never throws for a
  /// printing reason by contract, so anything arriving here is a malformed
  /// durable print record or a programming error — and neither may un-write a
  /// sale that is already durable. The reason is carried back to the till
  /// instead of being dropped, which is the difference between this and the
  /// `catch (_)` `docs/printer_transport.md` §2 objects to.
  ///
  /// **A receipt not queued is not a receipt lost.** The job key is the receipt
  /// number the sale already carries, so queueing it later from the sale
  /// produces the same job rather than a second delivery.
  Future<String?> _queueReceipt(CheckoutOutboxRecord record) async {
    final hook = _onSaved;
    if (hook == null) return null;
    // The session is re-read rather than captured: a tenant switch between the
    // write and this line means the receipt belongs to a business this device
    // has left, and queueing it would be worse than not.
    final session = _sessionController.session;
    if (session == null || !session.canAccess()) return null;
    try {
      return await hook(record, session);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'printing.queue_receipt',
        data: {'checkout_id': record.checkoutId, 'tenant_id': record.tenantId},
      );
      return 'receipt_not_queued';
    }
  }

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
    final attribution = await _boundShift(captured);

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
      // What the business paid for this unit, frozen onto the line at the moment
      // of sale. This is the whole of the guarantee that correcting a buying
      // price never moves a profit figure that has already been reported: the
      // number is copied here, the payload is hashed, the sale document refuses
      // every update, and every profit figure is computed from this line rather
      // than from the product. Changing `cost` therefore prices the next sale
      // and cannot reach this one.
      //
      // An unrecorded cost stays unrecorded rather than defaulting to zero,
      // which would claim the business paid nothing and report a 100% margin.
      // The server counts those lines as `incompleteCostLineCount`, and a
      // missing cost never refuses a sale — that would stop a till trading over
      // a reporting field.
      final unitCostMinor = product.cost == null
          ? null
          : checkoutMinorUnitsFromMajor(product.cost!);
      if (product.cost != null && unitCostMinor == null) {
        throw const CheckoutDraftException('cost_not_representable');
      }
      // The code is frozen onto the line with the name, so a receipt can
      // print it and a reprint prints the one the item sold under.
      final sku = product.sku.trim();
      items.add(<String, Object?>{
        'productId': product.id,
        'name': product.name,
        if (sku.isNotEmpty) 'sku': sku,
        'categoryId': product.categoryId,
        'quantity': line.quantity,
        'unitPriceMinor': unitPriceMinor,
        if (unitCostMinor != null) 'unitCostMinor': unitCostMinor,
      });
    }
    var discountMinor = request.discountMinor;
    String? discountReason;
    final agreed = request.agreedPrice;
    if (agreed != null) {
      if (request.discountMinor != 0) {
        throw const CheckoutDraftException('invalid_discount');
      }
      // **Above nothing and below the listed total.** At the listed total
      // nothing was agreed, and above it is not a discount at all. Nothing is
      // the other edge: goods handed over for no money are not a haggle, and
      // recording them as one would put them in the discount figures.
      if (agreed.totalMinor <= 0 || agreed.totalMinor >= subtotalMinor) {
        throw const CheckoutDraftException('agreed_price_out_of_range');
      }
      discountReason = checkoutDiscountReason(agreed.reason);
      if (discountReason == null) {
        throw const CheckoutDraftException('agreed_price_reason_required');
      }
      discountMinor = subtotalMinor - agreed.totalMinor;
    }
    if (discountMinor < 0 || discountMinor > subtotalMinor) {
      throw const CheckoutDraftException('invalid_discount');
    }

    final checkoutId = _validatedCheckoutId();
    // **The shift names the business day; the clock does not.** A night's
    // trading starts one evening and can run past midnight, which is the whole
    // reason a shift carries a business date rather than reading one off the
    // calendar: the day ends when the drawer is counted off, not at 00:00.
    // Re-deriving it here refused every sale after midnight, and a sale dated
    // by the clock could not be filed against its shift anyway -
    // `validSaleShift` requires the two to agree. What bounds a shift left
    // running is its 24-hour cap, which refuses the sale on its own.
    final businessDate = _validatedShiftBusinessDate(attribution);
    final deviceId = await _resolvedDeviceId();
    if (!_owns(captured)) {
      throw const CheckoutDraftException('session_changed');
    }
    _assertShiftDescribesThisSale(
      attribution,
      captured: captured,
      deviceId: deviceId,
    );

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
      'shiftId': attribution.shiftId,
      'deviceId': deviceId,
      'receiptNumber': receiptNumber,
      'receiptSequence': receiptSequence,
      // Omitted rather than written empty, which is how a sale that names no
      // method has always been stored - see `_saleFields` and the `unrecorded`
      // bucket that reads it.
      if (request.tender != null) 'tender': request.tender!.wireValue,
      'items': items,
      'subtotalMinor': subtotalMinor,
      'discountMinor': discountMinor,
      if (discountReason != null) 'discountReason': discountReason,
      'totalMinor': subtotalMinor - discountMinor,
      ...?request.customer?.toFields(),
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

  /// Resolves the canonical open shift this checkout will be attributed to.
  ///
  /// A binder that cannot answer refuses the checkout: unreadable local shift
  /// state must never widen where a cashier may sell, and it must never produce
  /// a sale that names no shift.
  Future<CheckoutShiftAttribution> _boundShift(TenantSession captured) async {
    final CheckoutShiftBinding binding;
    try {
      binding = await _shiftBinder.bindCheckoutShift(captured);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'checkout.shift_binding',
      );
      throw const CheckoutDraftException('checkout_start_unavailable');
    }
    final refusal = binding.refusalCode;
    if (refusal != null) throw CheckoutDraftException(refusal);
    final attribution = binding.attribution;
    if (attribution == null) {
      throw const CheckoutDraftException('checkout_start_unavailable');
    }
    if (!_owns(captured)) {
      throw const CheckoutDraftException('session_changed');
    }
    return attribution;
  }

  /// Proves the bound shift describes this exact sale before it is recorded.
  ///
  /// **No business date comparison, deliberately.** The sale takes its date
  /// from this shift rather than from the clock, so the two cannot disagree -
  /// see [_validatedShiftBusinessDate]. Nightly reconciliation aggregates
  /// sales per shift and business date, and filing the sale under the shift's
  /// own day is exactly what makes that add up across midnight.
  void _assertShiftDescribesThisSale(
    CheckoutShiftAttribution attribution, {
    required TenantSession captured,
    required String deviceId,
  }) {
    try {
      validateTenantDocumentId(attribution.shiftId, fieldName: 'shiftId');
    } on ArgumentError {
      throw const CheckoutDraftException('invalid_shift_id');
    }
    if (attribution.uid != captured.uid ||
        attribution.tenantId != captured.tenantId ||
        attribution.deviceId != deviceId) {
      throw const CheckoutDraftException('shift_binding_mismatch');
    }
  }

  /// Resolves the durable installation identity for this device.
  Future<String> _resolvedDeviceId() async {
    try {
      return await _receipts.resolveDeviceId();
    } on CheckoutReceiptException catch (error) {
      throw CheckoutDraftException(error.code);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'checkout.device_identity',
      );
      throw const CheckoutDraftException('device_identity_unavailable');
    }
  }

  /// The business date this sale is filed under, taken from its own shift.
  ///
  /// Validated rather than trusted: it arrives from durable local state that a
  /// reinstall or an adopted shift can have written, and every later figure -
  /// the receipt number, the daily aggregate, the shift expectation - is keyed
  /// by it. A shift whose date is unreadable refuses the sale rather than
  /// filing it under a day nothing can reconcile.
  String _validatedShiftBusinessDate(CheckoutShiftAttribution attribution) {
    try {
      return validateCheckoutBusinessDate(attribution.businessDate);
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
