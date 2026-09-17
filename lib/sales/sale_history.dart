import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../checkout/checkout_receipt.dart';
import '../checkout/checkout_sale.dart';
import '../checkout/checkout_tender.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_types.dart';

/// Raised when a canonical sale document cannot be trusted for display.
final class TenantSaleException implements Exception {
  const TenantSaleException(this.code);

  final String code;

  @override
  String toString() => 'TenantSaleException($code)';
}

/// One immutable line of a canonical sale document.
///
/// The immutable category and cost snapshot is retained for device reporting.
/// Whether profit may be displayed remains a role decision made by the report,
/// not by this read model.
final class TenantSaleLine implements CheckoutReceiptLine {
  const TenantSaleLine._({
    required this.productId,
    required this.name,
    required this.categoryId,
    required this.quantity,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    required this.unitCostMinor,
    required this.lineCostMinor,
  });

  final String productId;
  @override
  final String name;
  final String? categoryId;
  @override
  final int quantity;
  @override
  final int unitPriceMinor;
  @override
  final int lineTotalMinor;
  final int? unitCostMinor;
  final int? lineCostMinor;
}

/// Strict read model for `tenants/{tenantId}/sales/{saleId}`.
///
/// The document must repeat the identity encoded in its own path, describe a
/// supported payload contract, and carry a receipt that this exact device,
/// business date, and sequence would produce. A sale is immutable evidence, so
/// anything that disagrees with itself is refused rather than displayed.
final class TenantSale implements CheckoutReceiptSale {
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
    final schemaVersion = data['payloadSchemaVersion'];
    if (schemaVersion is! int ||
        !supportedCheckoutSalePayloadSchemaVersions.contains(schemaVersion)) {
      throw const TenantSaleException('unsupported_sale_schema');
    }
    final tender = _tender(data, schemaVersion);

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
      schemaVersion: schemaVersion,
      tender: tender,
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
    required this.schemaVersion,
    required this.tender,
    required this.recordedAt,
    required List<TenantSaleLine> lines,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.totalMinor,
  }) : lines = List<TenantSaleLine>.unmodifiable(lines);

  final String id;
  @override
  final String tenantId;
  final String soldById;
  final String shiftId;
  final String deviceId;
  @override
  final String businessDate;
  @override
  final String currency;
  @override
  final String receiptNumber;
  final int receiptSequence;
  final String payloadHash;

  /// The payload contract this exact sale was written under.
  final int schemaVersion;

  /// How the cashier said the customer paid, absent on a schema v1 sale.
  ///
  /// It is the cashier's assertion and never a verified payment; surfaces that
  /// show it must carry [checkoutTenderDisclaimer].
  @override
  final CheckoutTender? tender;

  /// The server instant, absent only while a local write is still pending.
  final DateTime? recordedAt;

  @override
  final List<TenantSaleLine> lines;
  @override
  final int subtotalMinor;
  @override
  final int discountMinor;
  @override
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
    TenantSalesHistoryQueryReader? reportReader,
  }) : _collectionReader = reader,
       _reportReader = reportReader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;
  final TenantSalesHistoryQueryReader? _reportReader;

  static const List<TenantRole> reportRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
    TenantRole.cashier,
  ];

  static const List<TenantRole> managementReportRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  /// Reads one sale by its immutable ID, or null where there is none.
  ///
  /// **A direct read, which the Rules make business-wide** - `allow get` on
  /// `sales` is `readingStaff`, unlike the `list` beside it that a cashier may
  /// only run over their own. That is what lets a returns screen label a
  /// colleague's sale without being shown that colleague's day.
  Future<TenantSale?> readSale(String saleId) async {
    final String safeSaleId;
    try {
      safeSaleId = validateTenantDocumentId(saleId, fieldName: 'saleId');
    } on ArgumentError {
      throw const TenantSaleException('invalid_sale_id');
    }
    final data = await readDocument(TenantCollection.sales, safeSaleId);
    if (data == null) return null;
    final sale = TenantSale.fromDocument(
      path: paths.sale(safeSaleId),
      data: data,
    );
    if (sale.tenantId != session.tenantId) {
      throw const TenantSaleException('cross_tenant_sale');
    }
    return sale;
  }

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
    // Carry the cashier attribution as well as the shift. Firestore permits a
    // cashier collection query only when its result set is provably their own;
    // management uses the same narrower and cheaper query shape.
    filters: <String, Object?>{
      'shiftId': shift.shiftId,
      'soldById': shift.staffId,
    },
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

  /// Pages the familiar period report without ever downloading a wider scope.
  ///
  /// Management may omit [selectedStaffId] for the whole business or name one
  /// canonical member. A cashier is always narrowed to the captured session's
  /// own UID here, even if a caller tries to request another member.
  Future<TenantSalePage> loadReport({
    required String startBusinessDate,
    required String endBusinessDate,
    String? selectedStaffId,
    int pageSize = 20,
    String? cursor,
  }) async {
    if (!session.canAccess(allowedRoles: reportRoles)) {
      throw const TenantSaleException('sale_report_forbidden');
    }
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    final start = _validatedReportDate(startBusinessDate);
    final end = _validatedReportDate(endBusinessDate);
    if (start.compareTo(end) > 0) {
      throw const TenantSaleException('invalid_sale_report_range');
    }
    final management = session.canAccess(allowedRoles: managementReportRoles);
    final selected = selectedStaffId == null
        ? null
        : _validatedReportStaffId(selectedStaffId);
    if (!management && selected != null && selected != session.uid) {
      throw const TenantSaleException('sale_report_forbidden');
    }
    final soldById = management ? selected : session.uid;
    final reportReader =
        _reportReader ??
        (_collectionReader is TenantSalesHistoryQueryReader
            ? _collectionReader as TenantSalesHistoryQueryReader
            : null);
    if (reportReader == null) {
      throw StateError('Backend sales report browsing is unavailable.');
    }
    final position = cursor == null
        ? null
        : _decodeSalesReportCursor(
            cursor,
            start: start,
            end: end,
            soldById: soldById,
          );
    final requestedLimit = pageSize + 1;
    final snapshots = await reportReader.queryTenantSalesHistory(
      TenantSalesHistoryQuery.scoped(
        collectionPath: paths.collectionPath(TenantCollection.sales),
        limit: requestedLimit,
        startBusinessDate: start,
        endBusinessDate: end,
        soldById: soldById,
        startAfter: position,
      ),
    );
    if (snapshots.length > requestedLimit) {
      throw const TenantScopeViolation(
        'The sales report returned more documents than requested.',
      );
    }
    final items = <TenantSale>[];
    final seen = <String>{};
    String? previousDate;
    String? previousId;
    for (final snapshot in snapshots) {
      final id = _saleDocumentId(snapshot.path, session.tenantId);
      if (!seen.add(id)) {
        throw const TenantScopeViolation(
          'The sales report returned a duplicate document.',
        );
      }
      final sale = TenantSale.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (sale.tenantId != session.tenantId ||
          sale.businessDate.compareTo(start) < 0 ||
          sale.businessDate.compareTo(end) > 0 ||
          soldById != null && sale.soldById != soldById) {
        throw const TenantSaleException('sale_report_scope_mismatch');
      }
      if (previousDate != null) {
        final dateOrder = previousDate.compareTo(sale.businessDate);
        if (dateOrder < 0 || dateOrder == 0 && previousId!.compareTo(id) <= 0) {
          throw const TenantScopeViolation(
            'Sales report results were not stably ordered.',
          );
        }
      }
      previousDate = sale.businessDate;
      previousId = id;
      items.add(sale);
    }
    final hasMore = items.length > pageSize;
    final visible = hasMore
        ? items.take(pageSize).toList(growable: false)
        : items;
    return TenantSalePage(
      items: visible,
      nextCursor: hasMore
          ? _encodeSalesReportCursor(
              TenantSalesHistoryPosition(
                businessDate: visible.last.businessDate,
                documentId: visible.last.id,
              ),
              start: start,
              end: end,
              soldById: soldById,
            )
          : null,
      hasMore: hasMore,
    );
  }

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
    final categoryId = _optionalDocumentId(line, 'categoryId');
    final unitCostMinor = _optionalInt(line, 'unitCostMinor', minimum: 0);
    final lineCostMinor = _optionalInt(line, 'costMinor', minimum: 0);
    if ((unitCostMinor == null) != (lineCostMinor == null) ||
        unitCostMinor != null && lineCostMinor != unitCostMinor * quantity) {
      throw const TenantSaleException('inconsistent_sale_line_cost');
    }
    lines.add(
      TenantSaleLine._(
        productId: productId,
        name: _requiredString(line, 'name'),
        categoryId: categoryId,
        quantity: quantity,
        unitPriceMinor: unitPriceMinor,
        lineTotalMinor: lineTotalMinor,
        unitCostMinor: unitCostMinor,
        lineCostMinor: lineCostMinor,
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

String? _optionalDocumentId(Map<String, Object?> data, String field) {
  if (data[field] == null) return null;
  return _requiredDocumentId(data, field);
}

int? _optionalInt(
  Map<String, Object?> data,
  String field, {
  required int minimum,
}) {
  if (data[field] == null) return null;
  return _requiredInt(data, field, minimum: minimum);
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

/// Reads the tender exactly as the sale's own payload version allows it.
///
/// The rule matches the one Firestore Rules apply on create, so a document that
/// slipped past them - an import, a rule rollback - is still refused here. A v2
/// sale that names an unmodelled method is not displayed as an unknown payment:
/// showing a payment method nothing recognises is worse than refusing the row.
///
/// **A v2 sale with no tender at all is a different thing and is read.** The
/// register does not preselect a method, so a cashier who was never told how
/// the customer paid saves a sale naming none - which this surface shows as
/// *Not recorded* and offers to complete. Refusing it here would hide the very
/// rows the completing action exists for.
CheckoutTender? _tender(Map<String, Object?> data, int schemaVersion) {
  if (schemaVersion < checkoutSaleTenderSchemaVersion) {
    if (data.containsKey('tender')) {
      throw const TenantSaleException('invalid_sale_tender');
    }
    return null;
  }
  if (!data.containsKey('tender')) return null;
  final tender = CheckoutTender.tryParse(data['tender']);
  if (tender == null) throw const TenantSaleException('invalid_sale_tender');
  return tender;
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

String _validatedReportDate(String value) {
  try {
    return validateCheckoutBusinessDate(value);
  } on ArgumentError {
    throw const TenantSaleException('invalid_sale_report_range');
  }
}

String _validatedReportStaffId(String value) {
  try {
    return validateTenantDocumentId(value, fieldName: 'soldById');
  } on ArgumentError {
    throw const TenantSaleException('invalid_sale_report_scope');
  }
}

String _saleDocumentId(String path, String tenantId) {
  final prefix = 'tenants/$tenantId/${TenantCollection.sales.segment}/';
  if (!path.startsWith(prefix)) {
    throw const TenantScopeViolation(
      'The sales report escaped its canonical tenant scope.',
    );
  }
  final id = path.substring(prefix.length);
  try {
    return validateTenantDocumentId(id, fieldName: 'saleId');
  } on ArgumentError {
    throw const TenantScopeViolation(
      'The sales report returned a non-canonical document path.',
    );
  }
}

String _encodeSalesReportCursor(
  TenantSalesHistoryPosition position, {
  required String start,
  required String end,
  required String? soldById,
}) => base64Url
    .encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'v': 1,
          'd': position.businessDate,
          'id': position.documentId,
          'from': start,
          'to': end,
          'staff': soldById,
        }),
      ),
    )
    .replaceAll('=', '');

TenantSalesHistoryPosition _decodeSalesReportCursor(
  String cursor, {
  required String start,
  required String end,
  required String? soldById,
}) {
  try {
    final padded = cursor.padRight((cursor.length + 3) ~/ 4 * 4, '=');
    final value = jsonDecode(utf8.decode(base64Url.decode(padded)));
    if (value is! Map<String, dynamic> ||
        value.length != 6 ||
        value['v'] != 1 ||
        value['from'] != start ||
        value['to'] != end ||
        value['staff'] != soldById ||
        value['d'] is! String ||
        value['id'] is! String) {
      throw const FormatException('Invalid sales report cursor.');
    }
    return TenantSalesHistoryPosition(
      businessDate: _validatedReportDate(value['d'] as String),
      documentId: validateTenantDocumentId(
        value['id'] as String,
        fieldName: 'cursor',
      ),
    );
  } catch (_) {
    throw const TenantSaleException('invalid_sale_report_cursor');
  }
}
