import 'package:cloud_firestore/cloud_firestore.dart';

import '../checkout/checkout_receipt.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_types.dart';

/// Raised when a canonical return document cannot be trusted for display.
final class TenantReturnException implements Exception {
  const TenantReturnException(this.code);

  final String code;

  @override
  String toString() => 'TenantReturnException($code)';
}

/// Where a return stands in the server's own verification guard.
///
/// `verifyReturnAndRestoreStock` verifies a return exactly once and only from
/// `pending`. It writes `status`, `verified` and `stockRestored` in one
/// transaction and treats all three as terminal, so this surface reads the same
/// evidence rather than trusting one field - a partially written return is a
/// contradiction worth refusing, not a state worth guessing at.
///
/// The historical `restored` spelling is gone (#110).
enum TenantReturnStatus {
  pending('pending'),

  /// Stock has been restored.
  verified('verified');

  const TenantReturnStatus(this.wireValue);

  final String wireValue;
}

/// One returned product line, as `normalizeReturnStockLines` reads it.
///
/// **`itemId` is gone (#110).** It was the name `productId` had before it, and
/// no current writer emits one; SIT is reset rather than migrated, so a line
/// names its product under the current name or it is not a line this screen
/// accepts.
final class TenantReturnLine {
  const TenantReturnLine._({
    required this.productId,
    required this.quantity,
    required this.productName,
  });

  final String productId;
  final int quantity;

  /// The name the returning device recorded, when it recorded one. Stock is
  /// restored by product ID; a name is only ever a label here.
  final String? productName;
}

/// The server-written evidence a verified return carries.
///
/// Every field is written by `verifyReturnAndRestoreStock` inside one
/// transaction, so - unlike the client-written instants on a sale or a shift -
/// none of them is ever legitimately absent once the return is verified.
final class TenantReturnVerification {
  const TenantReturnVerification._({
    required this.verifiedBy,
    required this.verifiedAt,
    required this.stockRestorationId,
  });

  final String verifiedBy;
  final DateTime verifiedAt;

  /// The immutable `return_verifications` record that restored the stock.
  final String stockRestorationId;
}

/// Strict read model for `tenants/{tenantId}/returns/{returnId}`.
///
/// The field names are taken from `functions/src/operations/returns.ts` and
/// `domain.ts`, which are the only authority on this document: the verification
/// callable reads `tenantId`, `saleId`, `itemsReturned`, and the terminal-state
/// flags, and writes the verification evidence back. Nothing here is invented.
final class TenantReturn {
  factory TenantReturn.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.returns.segment) {
      throw const TenantReturnException('invalid_return_path');
    }
    final String tenantId;
    final String returnId;
    try {
      tenantId = validateTenantId(segments[1]);
      returnId = validateTenantDocumentId(segments[3], fieldName: 'returnId');
    } on ArgumentError {
      throw const TenantReturnException('invalid_return_path');
    }
    // The document repeats the business and the ID its own path encodes,
    // exactly as the create rule binds them. The verification callable will not
    // restore stock from a document whose tenant disagrees either.
    if (data['tenantId'] != tenantId || data['returnId'] != returnId) {
      throw const TenantReturnException('return_identity_mismatch');
    }

    return TenantReturn._(
      id: returnId,
      tenantId: tenantId,
      saleId: _requiredDocumentId(data, 'saleId'),
      businessDate: _requiredBusinessDate(data, 'businessDate'),
      recordedOn: _requiredBusinessDate(data, 'recordedOn'),
      createdBy: _requiredDocumentId(data, 'createdBy'),
      reason: _requiredReason(data),
      status: _requiredStatus(data),
      lines: _parseLines(data['itemsReturned']),
      verification: _verification(data),
      recordedAt: _takenAt(data),
    );
  }

  TenantReturn._({
    required this.id,
    required this.tenantId,
    required this.saleId,
    required this.businessDate,
    required this.recordedOn,
    required this.createdBy,
    required this.reason,
    required this.status,
    required List<TenantReturnLine> lines,
    required this.verification,
    required this.recordedAt,
  }) : lines = List<TenantReturnLine>.unmodifiable(lines);

  final String id;
  final String tenantId;

  /// The immutable sale this return reverses.
  final String saleId;

  /// The day the reversal itself was taken, from the recording device.
  ///
  /// **Required (#110).** It was nullable while returns recorded before
  /// 2026-09-06 were still about; SIT holds none, so a return that cannot say
  /// when it was taken is not a return this surface accepts.
  final String recordedOn;

  /// The trading day of that sale, which the create rule binds to the sale's
  /// own field.
  ///
  /// **Required (#110).** See [recordedOn]: the same 2026-09-06 field, and the
  /// same reason it no longer needs to be optional.
  final String businessDate;

  /// The cashier who recorded the return. Rules bind it on create.
  final String createdBy;

  /// The audit reason the create rule requires. A return without a recorded
  /// reason is not auditable, so it is not a document this surface accepts.
  final String reason;
  final TenantReturnStatus status;
  final List<TenantReturnLine> lines;

  /// Present exactly when [status] is verified.
  final TenantReturnVerification? verification;

  /// When the return was taken, by the device that took it.
  ///
  /// **The device's `occurredAt`, held to the server's `createdAt`, since
  /// 2026-09-25.** A return taken offline on Monday reaches the server on
  /// Tuesday, and `createdAt` alone listed it on Tuesday. The device's clock is
  /// believed unless it claims a time after the return arrived. Absent only
  /// where neither is held.
  final DateTime? recordedAt;

  bool get isVerified => status == TenantReturnStatus.verified;

  /// Total units this return covers, across its lines.
  int get returnedUnits =>
      lines.fold(0, (total, line) => total + line.quantity);

  /// Reads the terminal state from every field the server's guard consults.
  ///
  /// The callable refuses to verify a return when `status`, `verified`, or
  /// `stockRestored` is terminal, and refuses a `status` that is neither absent
  /// nor `pending`. A document whose flags disagree is therefore one the server
  /// would never verify, so listing it as awaiting verification would invite an
  /// action that cannot succeed. It is refused instead.
  static TenantReturnStatus _requiredStatus(Map<String, Object?> data) {
    final status = data['status'];
    final terminalStatus = status == 'verified';
    if (status != null && status != 'pending' && !terminalStatus) {
      throw const TenantReturnException('invalid_return_document');
    }
    final verified = _optionalFlag(data, 'verified');
    final stockRestored = _optionalFlag(data, 'stockRestored');
    final terminal = <bool>[terminalStatus, verified, stockRestored];
    if (terminal.contains(true) && terminal.contains(false)) {
      throw const TenantReturnException('inconsistent_return_state');
    }
    return terminal.contains(true)
        ? TenantReturnStatus.verified
        : TenantReturnStatus.pending;
  }

  /// A pending return carries no verification evidence, and a verified one
  /// carries all of it: the callable writes those fields in one transaction and
  /// the client can never write them at all.
  static TenantReturnVerification? _verification(Map<String, Object?> data) {
    final verified = _requiredStatus(data) == TenantReturnStatus.verified;
    final verifiedBy = data['verifiedBy'];
    final restorationId = data['stockRestorationId'];
    if (!verified) {
      if (verifiedBy != null ||
          restorationId != null ||
          data['verifiedAt'] != null ||
          data['stockRestoredAt'] != null) {
        throw const TenantReturnException('inconsistent_return_state');
      }
      return null;
    }
    return TenantReturnVerification._(
      verifiedBy: _requiredDocumentId(data, 'verifiedBy'),
      verifiedAt: _requiredInstant(data, 'verifiedAt'),
      stockRestorationId: _requiredDocumentId(data, 'stockRestorationId'),
    );
  }
}

/// One bounded page of returns, newest document ID first.
final class TenantReturnPage {
  TenantReturnPage({
    required List<TenantReturn> items,
    required this.nextCursor,
    required this.hasMore,
  }) : items = List<TenantReturn>.unmodifiable(items);

  final List<TenantReturn> items;
  final String? nextCursor;
  final bool hasMore;

  Iterable<TenantReturn> get pending =>
      items.where((record) => !record.isVerified);
  Iterable<TenantReturn> get verified =>
      items.where((record) => record.isVerified);
}

/// Guarded read boundary over the returns recorded against one sale.
///
/// Every path is derived from the session's [TenantPaths], and the exact-child,
/// uniqueness, and ordering proofs of [TenantReadRepository] still apply. A
/// return that names a different sale fails the page closed: the remaining
/// returnable quantity of a sale is computed from exactly these records, so a
/// foreign one would misstate it.
final class TenantReturnHistoryRepository extends TenantReadRepository {
  TenantReturnHistoryRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;

  /// Every active business member may review returns. This matches the tenant
  /// rules and lets the home expose one complete returns record to the same
  /// people who can record a return from a sale.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
    TenantRole.cashier,
  ];

  /// Pages every return recorded by the selected business.
  ///
  /// [recordedOn] narrows to the day the reversal was taken and [status] to one
  /// standing; both are exact-value filters, which is all the read boundary
  /// offers and all these two controls need. Null means *every*.
  Future<TenantReturnPage> loadReturns({
    int pageSize = 20,
    String? cursor,
    String? recordedOn,
    TenantReturnStatus? status,
  }) async {
    String? safeRecordedOn;
    if (recordedOn != null) {
      try {
        safeRecordedOn = validateCheckoutBusinessDate(recordedOn);
      } on ArgumentError {
        throw const TenantReturnException('invalid_recorded_on');
      }
    }
    final page = await readCollectionPage(
      TenantCollection.returns,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      descending: true,
      // The generic boundary deliberately refuses an unrestricted descending
      // key scan. Returns repeat the tenant ID bound by their own path and
      // rules, so that same identity is the honest scope/index anchor here.
      equalityFilters: <String, Object?>{
        TenantReadRepository.tenantIdField: session.tenantId,
        if (safeRecordedOn != null) 'recordedOn': safeRecordedOn,
        if (status != null) 'status': status.wireValue,
      },
    );

    final items = <TenantReturn>[];
    for (final snapshot in page.items) {
      final record = TenantReturn.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (record.tenantId != session.tenantId) {
        throw const TenantReturnException('cross_tenant_return');
      }
      // The query filters, but a transport that ignored either filter must not
      // put a record under a day or a standing it does not have.
      if (safeRecordedOn != null && record.recordedOn != safeRecordedOn) {
        throw const TenantReturnException('return_recorded_on_mismatch');
      }
      if (status != null && record.status != status) {
        throw const TenantReturnException('return_status_mismatch');
      }
      items.add(record);
    }
    return TenantReturnPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  /// Pages every return filed against a sale that traded on [businessDate].
  ///
  /// **The day is the *sale's*, not the day the reversal was recorded**, which
  /// is what makes this the right read for netting a day's takings: a return
  /// taken the following morning belongs to the day whose money it comes back
  /// out of. See [TenantReturnCreateIntent.businessDate].
  Future<TenantReturnPage> loadDayReturns({
    required String businessDate,
    int pageSize = 20,
    String? cursor,
  }) async {
    final String safeBusinessDate;
    try {
      safeBusinessDate = validateCheckoutBusinessDate(businessDate);
    } on ArgumentError {
      throw const TenantReturnException('invalid_business_date');
    }
    final page = await readCollectionPage(
      TenantCollection.returns,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      descending: true,
      equalityFilters: <String, Object?>{'businessDate': safeBusinessDate},
    );

    final items = <TenantReturn>[];
    for (final snapshot in page.items) {
      final record = TenantReturn.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (record.tenantId != session.tenantId) {
        throw const TenantReturnException('cross_tenant_return');
      }
      // The query filters by day, but a transport that ignored the filter must
      // never net another day's takings down.
      if (record.businessDate != safeBusinessDate) {
        throw const TenantReturnException('return_business_date_mismatch');
      }
      items.add(record);
    }
    return TenantReturnPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  /// Pages the returns recorded against one immutable sale.
  Future<TenantReturnPage> loadSaleReturns({
    required String saleId,
    int pageSize = 20,
    String? cursor,
  }) async {
    final String safeSaleId;
    try {
      safeSaleId = validateTenantDocumentId(saleId, fieldName: 'saleId');
    } on ArgumentError {
      throw const TenantReturnException('invalid_sale_id');
    }
    final page = await readCollectionPage(
      TenantCollection.returns,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      descending: true,
      equalityFilters: <String, Object?>{'saleId': safeSaleId},
    );

    final items = <TenantReturn>[];
    for (final snapshot in page.items) {
      final record = TenantReturn.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (record.tenantId != session.tenantId) {
        throw const TenantReturnException('cross_tenant_return');
      }
      // The query filters by sale, but a transport that ignored the filter must
      // never attach another sale's reversal to this one.
      if (record.saleId != safeSaleId) {
        throw const TenantReturnException('return_sale_mismatch');
      }
      items.add(record);
    }
    return TenantReturnPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  /// Every return taken over a span of trading days, oldest first.
  ///
  /// **The read a report needs, and the one the screen's filters could not
  /// express.** [loadReturns] narrows to a single `recordedOn`; a report covers
  /// a period, and reading one by looping a day at a time would be one round
  /// trip per day for a month of days - most of them answering nothing.
  ///
  /// **Keyed to `recordedOn`**, the day the reversal was taken, rather than to
  /// the day of the sale being reversed. See
  /// [TenantBusinessDateRangeField.recordedOn] for why those are different
  /// questions.
  ///
  /// **The position is typed rather than an opaque string**, unlike every
  /// paginated screen here. A cursor is a string because it crosses into a
  /// widget and back; this paging is internal to one report's gather loop and
  /// never leaves it, so encoding the pair would be ceremony around a value
  /// nobody else can see.
  Future<
    ({List<TenantReturn> items, TenantBusinessDateRangePosition? next})
  >
  loadRecordedRange({
    required String startRecordedOn,
    required String endRecordedOn,
    int pageSize = 50,
    TenantBusinessDateRangePosition? startAfter,
  }) async {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantReturnException('returns_forbidden');
    }
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    final String start;
    final String end;
    try {
      start = validateCheckoutBusinessDate(startRecordedOn);
      end = validateCheckoutBusinessDate(endRecordedOn);
    } on ArgumentError {
      throw const TenantReturnException('invalid_recorded_on');
    }
    if (start.compareTo(end) > 0) {
      throw const TenantReturnException('invalid_return_range');
    }
    // The same shape `TenantSaleHistoryRepository.loadReport` uses: the range
    // transport is a separate interface from the collection reader, so it is
    // reached by a checked cast rather than by promotion.
    final reader = _collectionReader is TenantReportRangeReader
        ? _collectionReader as TenantReportRangeReader
        : null;
    if (reader == null) {
      throw StateError('This reader cannot read a returns period.');
    }

    final requested = pageSize + 1;
    final snapshots = await reader.queryTenantBusinessDateRange(
      TenantBusinessDateRangeQuery.scoped(
        collectionPath: paths.collectionPath(TenantCollection.returns),
        orderBy: TenantBusinessDateRangeField.recordedOn,
        limit: requested,
        startBusinessDate: start,
        endBusinessDate: end,
        startAfter: startAfter,
      ),
    );
    if (snapshots.length > requested) {
      throw const TenantScopeViolation(
        'The returns period returned more documents than requested.',
      );
    }

    final items = <TenantReturn>[];
    final seen = <String>{};
    for (final snapshot in snapshots) {
      final record = TenantReturn.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (!seen.add(record.id)) {
        throw const TenantScopeViolation(
          'The returns period returned a duplicate document.',
        );
      }
      if (record.tenantId != session.tenantId) {
        throw const TenantReturnException('cross_tenant_return');
      }
      // The query bounds the span, but a transport that ignored either bound
      // must not put a return inside a period it was not taken in - the
      // document states that period on its own first page.
      if (record.recordedOn.compareTo(start) < 0 ||
          record.recordedOn.compareTo(end) > 0) {
        throw const TenantReturnException('return_recorded_on_mismatch');
      }
      items.add(record);
    }

    final hasMore = items.length > pageSize;
    final visible = hasMore
        ? items.take(pageSize).toList(growable: false)
        : items;
    return (
      items: visible,
      next: hasMore
          ? TenantBusinessDateRangePosition(
              businessDate: visible.last.recordedOn,
              documentId: visible.last.id,
            )
          : null,
    );
  }
}

/// The sale's trading day, where the return records one.
///
/// Anything present but not a valid business date is a refusal rather than a
/// shrug: a malformed day would be filed against the wrong takings.
String _requiredBusinessDate(Map<String, Object?> data, String field) {
  final value = _optionalBusinessDate(data, field);
  if (value == null) {
    throw const TenantReturnException('invalid_return_business_date');
  }
  return value;
}

String? _optionalBusinessDate(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is! String) {
    throw const TenantReturnException('invalid_return_business_date');
  }
  try {
    return validateCheckoutBusinessDate(value);
  } on ArgumentError {
    throw const TenantReturnException('invalid_return_business_date');
  }
}

/// Every line must name a product and a positive quantity, exactly as
/// `normalizeReturnStockLines` requires before it will restore anything.
List<TenantReturnLine> _parseLines(Object? raw) {
  if (raw is! List || raw.isEmpty || raw.length > maximumReturnLines) {
    throw const TenantReturnException('invalid_return_lines');
  }
  final lines = <TenantReturnLine>[];
  final productIds = <String>{};
  for (final entry in raw) {
    if (entry is! Map) {
      throw const TenantReturnException('invalid_return_lines');
    }
    final line = <String, Object?>{
      for (final key in entry.keys)
        if (key is String) key: entry[key],
    };
    final productId = _requiredDocumentId(line, 'productId');
    if (!productIds.add(productId)) {
      throw const TenantReturnException('duplicate_return_line');
    }
    final quantity = line['quantity'];
    if (quantity is! int ||
        quantity < 1 ||
        quantity > maximumReturnLineQuantity) {
      throw const TenantReturnException('invalid_return_lines');
    }
    lines.add(
      TenantReturnLine._(
        productId: productId,
        quantity: quantity,
        productName: _optionalName(line['productName']),
      ),
    );
  }
  return lines;
}

String? _optionalName(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const TenantReturnException('invalid_return_lines');
  }
  final name = value.trim();
  if (name.isEmpty || name.length > 200) return null;
  for (final codeUnit in name.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) return null;
  }
  return name;
}

String _requiredReason(Map<String, Object?> data) {
  final value = data['reason'];
  if (value is! String) {
    throw const TenantReturnException('invalid_return_document');
  }
  final reason = value.trim();
  if (reason.length < 3 || reason.length > 500) {
    throw const TenantReturnException('invalid_return_document');
  }
  for (final codeUnit in reason.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantReturnException('invalid_return_document');
    }
  }
  return reason;
}

String _requiredDocumentId(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String) {
    throw const TenantReturnException('invalid_return_document');
  }
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw const TenantReturnException('invalid_return_document');
  }
}

bool _optionalFlag(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return false;
  if (value is! bool) {
    throw const TenantReturnException('invalid_return_document');
  }
  return value;
}

DateTime _requiredInstant(Map<String, Object?> data, String field) {
  final value = _optionalInstant(data, field);
  if (value == null) {
    throw const TenantReturnException('invalid_return_document');
  }
  return value;
}

/// [TenantReturn.recordedAt]: the earlier of the device's time and the
/// server's, or whichever one is held.
DateTime? _takenAt(Map<String, Object?> data) {
  final taken = _optionalInstant(data, 'occurredAt');
  final arrived = _optionalInstant(data, 'createdAt');
  if (taken == null) return arrived;
  if (arrived == null) return taken;
  return taken.isBefore(arrived) ? taken : arrived;
}

DateTime? _optionalInstant(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantReturnException('invalid_return_document');
}

/// `MAX_RETURN_LINES` in `functions/src/operations/domain.ts`: as many lines
/// as a sale may hold, so any sale can be returned in one return.
const int maximumReturnLines = 400;

/// `MAX_QUANTITY_DELTA` in `functions/src/operations/domain.ts`.
const int maximumReturnLineQuantity = 1000000;
