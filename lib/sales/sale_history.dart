import 'package:cloud_firestore/cloud_firestore.dart';

import '../checkout/checkout_receipt.dart';
import '../checkout/checkout_sale.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';

/// Raised when a canonical sale document cannot be trusted for display.
final class TenantSaleException implements Exception {
  const TenantSaleException(this.code);

  final String code;

  @override
  String toString() => 'TenantSaleException($code)';
}

/// One immutable line of a canonical sale document.
///
/// The optional cost fields the draft may write are deliberately parsed away
/// rather than exposed: product cost and profit remain outside this surface.
final class TenantSaleLine {
  const TenantSaleLine._({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
  });

  final String productId;
  final String name;
  final int quantity;
  final int unitPriceMinor;
  final int lineTotalMinor;
}

/// Strict read model for `tenants/{tenantId}/sales/{saleId}`.
///
/// The document must repeat the identity encoded in its own path, describe the
/// frozen v1 payload contract, and carry a receipt that this exact device,
/// business date, and sequence would produce. A sale is immutable evidence, so
/// anything that disagrees with itself is refused rather than displayed.
final class TenantSale {
  factory TenantSale.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.sales.segment) {
      throw const TenantSaleException('invalid_sale_path');
    }
    final String tenantId;
    final String saleId;
    try {
      tenantId = validateTenantId(segments[1]);
      saleId = validateTenantDocumentId(segments[3], fieldName: 'saleId');
    } on ArgumentError {
      throw const TenantSaleException('invalid_sale_path');
    }
    // Rules bind the document ID to the immutable checkout ID at create.
    if (data['checkoutId'] != saleId || data['tenantId'] != tenantId) {
      throw const TenantSaleException('sale_identity_mismatch');
    }
    if (data['payloadSchemaVersion'] != checkoutSalePayloadSchemaVersion) {
      throw const TenantSaleException('unsupported_sale_schema');
    }

    final deviceId = _requiredDeviceId(data);
    final businessDate = _requiredBusinessDate(data);
    final receiptSequence = _requiredInt(
      data,
      'receiptSequence',
      minimum: 1,
      maximum: maximumCheckoutReceiptSequence,
    );
    final subtotalMinor = _requiredInt(data, 'subtotalMinor', minimum: 0);
    final discountMinor = _requiredInt(
      data,
      'discountMinor',
      minimum: 0,
      maximum: subtotalMinor,
    );
    final totalMinor = _requiredInt(data, 'totalMinor', minimum: 0);
    if (totalMinor != subtotalMinor - discountMinor) {
      throw const TenantSaleException('inconsistent_sale_total');
    }
    final lines = _parseLines(data['items']);
    var lineSum = 0;
    for (final line in lines) {
      lineSum += line.lineTotalMinor;
    }
    if (lineSum != subtotalMinor) {
      throw const TenantSaleException('inconsistent_sale_total');
    }
    _requireMajorMirror(data, 'subtotal', subtotalMinor);
    _requireMajorMirror(data, 'discount', discountMinor);
    _requireMajorMirror(data, 'total', totalMinor);

    return TenantSale._(
      id: saleId,
      tenantId: tenantId,
      soldById: _requiredDocumentId(data, 'soldById'),
      shiftId: _requiredDocumentId(data, 'shiftId'),
      deviceId: deviceId,
      businessDate: businessDate,
      currency: _requiredCurrency(data),
      receiptNumber: _requiredReceiptNumber(
        data,
        deviceId: deviceId,
        businessDate: businessDate,
        sequence: receiptSequence,
      ),
      receiptSequence: receiptSequence,
      payloadHash: _requiredPayloadHash(data),
      recordedAt: _optionalInstant(data, 'createdAt'),
      lines: lines,
      subtotalMinor: subtotalMinor,
      discountMinor: discountMinor,
      totalMinor: totalMinor,
    );
  }

  TenantSale._({
    required this.id,
    required this.tenantId,
    required this.soldById,
    required this.shiftId,
    required this.deviceId,
    required this.businessDate,
    required this.currency,
    required this.receiptNumber,
    required this.receiptSequence,
    required this.payloadHash,
    required this.recordedAt,
    required List<TenantSaleLine> lines,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.totalMinor,
  }) : lines = List<TenantSaleLine>.unmodifiable(lines);

  final String id;
  final String tenantId;
  final String soldById;
  final String shiftId;
  final String deviceId;
  final String businessDate;
  final String currency;
  final String receiptNumber;
  final int receiptSequence;
  final String payloadHash;

  /// The server instant, absent only while a local write is still pending.
  final DateTime? recordedAt;

  final List<TenantSaleLine> lines;
  final int subtotalMinor;
  final int discountMinor;
  final int totalMinor;
}

/// The exact shift a sale page is claimed to belong to.
///
/// Firestore Rules prove this agreement when the sale is created. Repeating it
/// on read means an imported or rule-bypassing document cannot be presented as
/// part of a shift it does not describe.
final class TenantSaleShiftScope {
  const TenantSaleShiftScope({
    required this.shiftId,
    required this.staffId,
    required this.deviceId,
    required this.businessDate,
  });

  final String shiftId;
  final String staffId;
  final String deviceId;
  final String businessDate;
}

/// One bounded page of canonical sales, newest document ID first.
final class TenantSalePage {
  TenantSalePage({
    required List<TenantSale> items,
    required this.nextCursor,
    required this.hasMore,
  }) : items = List<TenantSale>.unmodifiable(items);

  final List<TenantSale> items;
  final String? nextCursor;
  final bool hasMore;
}

/// Guarded read boundary over one tenant's immutable sales.
///
/// Every path is derived from the session's [TenantPaths] and the exact-child,
/// uniqueness, and ordering proofs of [TenantReadRepository] still apply. No
/// caller can supply a collection path, an ordering, or a raw filter.
final class TenantSaleHistoryRepository extends TenantReadRepository {
  TenantSaleHistoryRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;

  /// Pages the sales recorded during one canonical shift.
  ///
  /// Every returned sale must name that shift and agree with its cashier,
  /// device, and business day. A sale that disagrees fails the page closed: on
  /// a screen used to inspect a shift, contradicting evidence must be reported,
  /// never quietly listed as if it belonged.
  Future<TenantSalePage> loadShiftSales({
    required TenantSaleShiftScope shift,
    int pageSize = 20,
    String? cursor,
  }) => _load(
    pageSize: pageSize,
    cursor: cursor,
    filters: <String, Object?>{'shiftId': shift.shiftId},
    verify: (sale) {
      if (sale.shiftId != shift.shiftId ||
          sale.soldById != shift.staffId ||
          sale.deviceId != shift.deviceId ||
          sale.businessDate != shift.businessDate) {
        throw const TenantSaleException('sale_shift_mismatch');
      }
    },
  );

  /// Pages this cashier's own most recent sales, for receipt lookup.
  Future<TenantSalePage> loadOwnRecentSales({
    int pageSize = 20,
    String? cursor,
  }) => _load(
    pageSize: pageSize,
    cursor: cursor,
    filters: <String, Object?>{'soldById': session.uid},
    verify: (sale) {
      if (sale.soldById != session.uid) {
        throw const TenantSaleException('foreign_sale');
      }
    },
  );

  Future<TenantSalePage> _load({
    required int pageSize,
    required String? cursor,
    required Map<String, Object?> filters,
    required void Function(TenantSale sale) verify,
  }) async {
    final page = await readCollectionPage(
      TenantCollection.sales,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      // A checkout ID embeds a fixed-width millisecond timestamp, so descending
      // document order is newest first. The recorded instant is still shown.
      descending: true,
      equalityFilters: filters,
    );
    final items = <TenantSale>[];
    for (final snapshot in page.items) {
      final sale = TenantSale.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (sale.tenantId != session.tenantId) {
        throw const TenantSaleException('cross_tenant_sale');
      }
      verify(sale);
      items.add(sale);
    }
    return TenantSalePage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }
}

List<TenantSaleLine> _parseLines(Object? raw) {
  if (raw is! List || raw.isEmpty || raw.length > maximumCheckoutSaleLines) {
    throw const TenantSaleException('invalid_sale_lines');
  }
  final lines = <TenantSaleLine>[];
  final productIds = <String>{};
  for (final entry in raw) {
    if (entry is! Map) {
      throw const TenantSaleException('invalid_sale_lines');
    }
    final line = <String, Object?>{
      for (final key in entry.keys)
        if (key is String) key: entry[key],
    };
    final productId = _requiredDocumentId(line, 'productId');
    if (!productIds.add(productId)) {
      throw const TenantSaleException('duplicate_sale_line');
    }
    final quantity = _requiredInt(
      line,
      'quantity',
      minimum: 1,
      maximum: maximumCheckoutLineQuantity,
    );
    final unitPriceMinor = _requiredInt(line, 'unitPriceMinor', minimum: 0);
    final lineTotalMinor = _requiredInt(line, 'lineTotalMinor', minimum: 0);
    if (lineTotalMinor != unitPriceMinor * quantity) {
      throw const TenantSaleException('inconsistent_sale_line');
    }
    lines.add(
      TenantSaleLine._(
        productId: productId,
        name: _requiredString(line, 'name'),
        quantity: quantity,
        unitPriceMinor: unitPriceMinor,
        lineTotalMinor: lineTotalMinor,
      ),
    );
  }
  return lines;
}

String _requiredString(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw const TenantSaleException('invalid_sale_document');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantSaleException('invalid_sale_document');
    }
  }
  return value;
}

String _requiredDocumentId(Map<String, Object?> data, String field) {
  final value = _requiredString(data, field);
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw const TenantSaleException('invalid_sale_document');
  }
}

String _requiredDeviceId(Map<String, Object?> data) {
  final value = _requiredString(data, 'deviceId');
  try {
    return validateCheckoutDeviceId(value);
  } on ArgumentError {
    throw const TenantSaleException('invalid_sale_document');
  }
}

String _requiredBusinessDate(Map<String, Object?> data) {
  final value = _requiredString(data, 'businessDate');
  try {
    return validateCheckoutBusinessDate(value);
  } on ArgumentError {
    throw const TenantSaleException('invalid_sale_document');
  }
}

String _requiredCurrency(Map<String, Object?> data) {
  final value = _requiredString(data, 'currency');
  if (!_currencyPattern.hasMatch(value)) {
    throw const TenantSaleException('invalid_sale_document');
  }
  return value;
}

String _requiredPayloadHash(Map<String, Object?> data) {
  final value = _requiredString(data, 'payloadHash');
  if (!_sha256Pattern.hasMatch(value)) {
    throw const TenantSaleException('invalid_sale_document');
  }
  return value;
}

/// A receipt must describe this exact device, business date, and sequence.
///
/// The same proof the draft builder applies before submission and the Rules
/// apply on create; a receipt that disagrees with its own sale is refused
/// rather than shown to a customer.
String _requiredReceiptNumber(
  Map<String, Object?> data, {
  required String deviceId,
  required String businessDate,
  required int sequence,
}) {
  final value = _requiredString(data, 'receiptNumber');
  if (!checkoutReceiptNumberPattern.hasMatch(value) ||
      value !=
          formatCheckoutReceiptNumber(
            deviceId: deviceId,
            businessDate: businessDate,
            sequence: sequence,
          )) {
    throw const TenantSaleException('invalid_sale_receipt');
  }
  return value;
}

int _requiredInt(
  Map<String, Object?> data,
  String field, {
  required int minimum,
  int maximum = maximumCheckoutMinorAmount,
}) {
  final value = data[field];
  if (value is! int || value < minimum || value > maximum) {
    throw const TenantSaleException('invalid_sale_document');
  }
  return value;
}

/// The major-unit mirror must describe the authoritative minor units.
void _requireMajorMirror(
  Map<String, Object?> data,
  String field,
  int minorUnits,
) {
  final value = data[field];
  if (value is! num || (value * 100).round() != minorUnits) {
    throw const TenantSaleException('invalid_sale_document');
  }
}

DateTime? _optionalInstant(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantSaleException('invalid_sale_document');
}

final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');
final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
