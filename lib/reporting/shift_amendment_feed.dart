import 'package:cloud_firestore/cloud_firestore.dart';

import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import 'reconciliation_status.dart';

/// Strict read model for `tenants/{tenantId}/shift_amendments/{amendmentId}`.
///
/// `functions/src/reconciliation/amendments.ts` is the only writer and the only
/// authority on these field names. It appends one record inside the same
/// transaction that rewrites the shift, settles the expectation, and removes the
/// difference from the unresolved list - so this record is the only remaining
/// account of a correction that has already happened.
///
/// That is why it is decoded strictly. A closed shift is a record every other
/// part of this app treats as final, and this trail is what makes rewriting one
/// answerable. A row here that misstated the correction would be worse than no
/// row at all, so a record that cannot explain its own correction is refused
/// rather than listed - the same rule the differences read model and the stock
/// correction feed both apply.
final class TenantShiftAmendmentRecord {
  factory TenantShiftAmendmentRecord.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.shiftAmendments.segment) {
      throw const TenantReconciliationException('invalid_amendment_path');
    }
    final String tenantId;
    final String amendmentId;
    try {
      tenantId = validateTenantId(segments[1]);
      amendmentId = validateTenantDocumentId(
        segments[3],
        fieldName: 'amendmentId',
      );
    } on ArgumentError {
      throw const TenantReconciliationException('invalid_amendment_path');
    }
    // Unlike a stock adjustment, this record repeats its own ID, so both it and
    // the business it names must agree with the path it was read from.
    if (data['tenantId'] != tenantId || data['amendmentId'] != amendmentId) {
      throw const TenantReconciliationException('amendment_identity_mismatch');
    }

    // The one property that makes this collection safe to show at all. The
    // server writes it as a literal `false` and the whole amendment path was
    // designed around never touching a drawer count. A record claiming
    // otherwise is either a server that changed its guarantee without this
    // client knowing or a document that was never written by one, and neither
    // may be presented as an ordinary correction.
    if (data['mutatesCountedCash'] != false) {
      throw const TenantReconciliationException('amendment_mutates_cash');
    }

    final previousTotalSalesMinor = _requiredMinorUnits(
      data,
      'previousTotalSalesMinor',
    );
    final previousTransactionCount = _requiredCount(
      data,
      'previousTransactionCount',
    );
    final totalSalesMinor = _requiredMinorUnits(data, 'totalSalesMinor');
    final transactionCount = _requiredCount(data, 'transactionCount');
    final salesVarianceMinor = _requiredDifference(data, 'salesVarianceMinor');
    final transactionVariance = _requiredDifference(
      data,
      'transactionVariance',
    );
    final previousRepresentationsAgreed = _requiredBool(
      data,
      'previousRepresentationsAgreed',
    );

    // Whole counts from a single comparison, so this identity is exact and a
    // record that breaks it did not come from `amendShiftSummary`.
    if (transactionVariance != previousTransactionCount - transactionCount) {
      throw const TenantReconciliationException(
        'inconsistent_amendment_counts',
      );
    }
    // The money identity holds only when the record says the shift's two
    // representations of the same figure agreed. The recorded variance is
    // measured from the major-unit total the verifier compares, which may
    // legitimately differ from the stored minor units - and when it does, the
    // amendment says so through this very field and overwrites both. Asserting
    // the identity unconditionally would refuse exactly the internally
    // inconsistent shifts this correction exists to repair.
    if (previousRepresentationsAgreed &&
        salesVarianceMinor != previousTotalSalesMinor - totalSalesMinor) {
      throw const TenantReconciliationException('inconsistent_amendment_money');
    }

    return TenantShiftAmendmentRecord._(
      id: amendmentId,
      tenantId: tenantId,
      shiftId: _requiredDocumentId(data, 'shiftId'),
      staffId: _requiredDocumentId(data, 'staffId'),
      businessDate: _requiredBusinessDate(data),
      sourceType: _requiredString(data, 'sourceType'),
      expectationId: _requiredDocumentId(data, 'expectationId'),
      expectationGeneration: _requiredString(data, 'expectationGeneration'),
      previousTotalSalesMinor: previousTotalSalesMinor,
      previousTransactionCount: previousTransactionCount,
      previousRepresentationsAgreed: previousRepresentationsAgreed,
      totalSalesMinor: totalSalesMinor,
      transactionCount: transactionCount,
      salesVarianceMinor: salesVarianceMinor,
      transactionVariance: transactionVariance,
      // Null is a real answer: no difference was listed under this shift's
      // generation, or the record at that ID described something else and was
      // deliberately left alone.
      clearedAnomalyId: data['clearedAnomalyId'] == null
          ? null
          : _requiredDocumentId(data, 'clearedAnomalyId'),
      reason: _requiredReason(data),
      actorUid: _requiredDocumentId(data, 'actorUid'),
      requestId: _optionalString(data, 'requestId'),
      recordedAt: _optionalInstant(data, 'createdAt'),
    );
  }

  const TenantShiftAmendmentRecord._({
    required this.id,
    required this.tenantId,
    required this.shiftId,
    required this.staffId,
    required this.businessDate,
    required this.sourceType,
    required this.expectationId,
    required this.expectationGeneration,
    required this.previousTotalSalesMinor,
    required this.previousTransactionCount,
    required this.previousRepresentationsAgreed,
    required this.totalSalesMinor,
    required this.transactionCount,
    required this.salesVarianceMinor,
    required this.transactionVariance,
    required this.clearedAnomalyId,
    required this.reason,
    required this.actorUid,
    required this.requestId,
    required this.recordedAt,
  });

  final String id;
  final String tenantId;

  /// The closed shift that was corrected, and the cashier it belongs to. The
  /// staff member is named on the record so it stands on its own after the
  /// shift itself has scrolled out of any history page.
  final String shiftId;
  final String staffId;

  final String businessDate;

  /// Always `reconciliation_shift_variance` today. Decoded rather than required
  /// so a server that starts recording another kind of correction here is named
  /// honestly instead of taking the trail down.
  final String sourceType;

  /// The sale-derived expectation the corrected figure was read from, and the
  /// exact generation of it. Together they are what makes a second amendment of
  /// the same comparison impossible rather than merely pointless.
  final String expectationId;
  final String expectationGeneration;

  /// What the shift recorded before the correction.
  final int previousTotalSalesMinor;
  final int previousTransactionCount;

  /// Whether the shift's two representations of the same money agreed before
  /// the correction. When they did not, the shift was internally inconsistent -
  /// something nothing else in the app reports - and the amendment overwrote
  /// both rather than refusing and leaving it unfixable.
  final bool previousRepresentationsAgreed;

  /// What it records now, which is what its own sales prove.
  final int totalSalesMinor;
  final int transactionCount;

  /// The difference that was resolved, observed minus expected.
  final int salesVarianceMinor;
  final int transactionVariance;

  /// The listed difference this correction removed, if one was listed.
  final String? clearedAnomalyId;

  /// Why, in the words of whoever asked. Required by the server, so a record
  /// without one is not a record of a correction anybody answered for.
  final String reason;

  final String actorUid;

  /// The idempotency key the actor's attempt carried, when it is recorded.
  final String? requestId;

  /// The server instant the correction was committed.
  final DateTime? recordedAt;

  /// Whether the shift had recorded more than its sales prove.
  bool get overstatedSales => salesVarianceMinor > 0;

  /// Whether the correction changed the money at all. A correction may move
  /// only the transaction count, and saying so is more honest than implying a
  /// figure changed when it did not.
  bool get changedSales => previousTotalSalesMinor != totalSalesMinor;

  bool get changedTransactionCount =>
      previousTransactionCount != transactionCount;

  /// Whether a listed difference was removed from the unresolved list by this.
  bool get clearedListedDifference => clearedAnomalyId != null;
}

/// One bounded page of the corrections recorded against this business.
final class TenantShiftAmendmentRecordPage {
  TenantShiftAmendmentRecordPage({
    required List<TenantShiftAmendmentRecord> items,
    required this.nextCursor,
    required this.hasMore,
    required this.shiftId,
  }) : items = List<TenantShiftAmendmentRecord>.unmodifiable(items);

  final List<TenantShiftAmendmentRecord> items;
  final String? nextCursor;
  final bool hasMore;

  /// The exact shift this page was narrowed to, or null for the whole business.
  /// A surface states which one it is showing rather than implying a filtered
  /// page is everything that was recorded.
  final String? shiftId;

  bool get isShiftScoped => shiftId != null;
}

/// Guarded read boundary over one tenant's shift correction trail.
///
/// Every path is derived from the session's [TenantPaths] and the exact-child,
/// uniqueness, page-size, and ordering proofs of [TenantReadRepository] still
/// apply. No caller can supply a collection path, an ordering, or a raw filter.
final class TenantShiftAmendmentFeedRepository extends TenantReadRepository {
  TenantShiftAmendmentFeedRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  /// The roles `firestore.rules` grants on `shift_amendments`, and the same set
  /// that reads the differences these corrections resolve.
  ///
  /// It is deliberately wider than the owner-and-administrator set that may
  /// *make* a correction. Rewriting a record every client treats as terminal is
  /// governance; seeing that it was rewritten, and why, is operational
  /// information a manager answering for a shift needs. The read surface and the
  /// write surface disagreeing about this is the point, not an oversight.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  final TenantCollectionReader _collectionReader;

  static bool canReadInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// Pages every shift correction recorded across the business.
  Future<TenantShiftAmendmentRecordPage> loadAmendments({
    int pageSize = 20,
    String? cursor,
  }) => _load(pageSize: pageSize, cursor: cursor, shiftId: null);

  /// Pages the corrections recorded against one shift.
  ///
  /// The filter is an exact `shiftId ==` equality on the same ascending key
  /// order, so it is served by Firestore's automatic single-field index and
  /// needs no composite index of its own. Both shapes are already proved
  /// servable by `rules-tests/test/shift-amendments.test.js`.
  Future<TenantShiftAmendmentRecordPage> loadShiftAmendments({
    required String shiftId,
    int pageSize = 20,
    String? cursor,
  }) => _load(pageSize: pageSize, cursor: cursor, shiftId: shiftId);

  /// Reads one bounded page, optionally narrowed to one shift.
  ///
  /// The page is ordered by ascending document ID and is deliberately **not**
  /// presented as chronological: an amendment ID is a digest of the actor, the
  /// operation, the business, and the request, so document order carries no time
  /// information at all. Each record states its own recorded instant instead.
  Future<TenantShiftAmendmentRecordPage> _load({
    required int pageSize,
    required String? cursor,
    required String? shiftId,
  }) async {
    if (!canReadInSession(session)) {
      throw const TenantReconciliationException('shift_amendments_forbidden');
    }
    final String? filteredShiftId;
    try {
      filteredShiftId = shiftId == null
          ? null
          : validateTenantDocumentId(shiftId, fieldName: 'shiftId');
    } on ArgumentError {
      throw const TenantReconciliationException('invalid_shift_filter');
    }
    final page = await readCollectionPage(
      TenantCollection.shiftAmendments,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      equalityFilters: filteredShiftId == null
          ? const <String, Object?>{}
          : <String, Object?>{'shiftId': filteredShiftId},
    );
    final items = <TenantShiftAmendmentRecord>[];
    for (final snapshot in page.items) {
      final record = TenantShiftAmendmentRecord.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (record.tenantId != session.tenantId) {
        throw const TenantReconciliationException('cross_tenant_amendment');
      }
      // A page narrowed to one shift that answers with another one is a broken
      // boundary, not a row to quietly skip past.
      if (filteredShiftId != null && record.shiftId != filteredShiftId) {
        throw const TenantReconciliationException('foreign_shift_amendment');
      }
      items.add(record);
    }
    return TenantShiftAmendmentRecordPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      shiftId: filteredShiftId,
    );
  }
}

/// The same bound the shift history read model and the amendment callable both
/// enforce, repeated rather than imported so the reporting domain does not
/// depend on the shift domain for one number.
const int _maximumShiftSalesMinor = 1000000000000;

String _requiredString(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      value.length > 200) {
    throw const TenantReconciliationException('invalid_amendment_field');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantReconciliationException('invalid_amendment_field');
    }
  }
  return value;
}

String? _optionalString(Map<String, Object?> data, String field) =>
    data[field] == null ? null : _requiredString(data, field);

/// The reason is bounded at the 500 characters the server's `normalizeReason`
/// allows, rather than the 200 every other string here is held to.
String _requiredReason(Map<String, Object?> data) {
  final value = data['reason'];
  if (value is! String ||
      value.trim().length < 3 ||
      value != value.trim() ||
      value.length > 500) {
    throw const TenantReconciliationException('invalid_amendment_reason');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantReconciliationException('invalid_amendment_reason');
    }
  }
  return value;
}

String _requiredDocumentId(Map<String, Object?> data, String field) {
  final value = _requiredString(data, field);
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw const TenantReconciliationException('invalid_amendment_field');
  }
}

String _requiredBusinessDate(Map<String, Object?> data) {
  final value = data['businessDate'];
  if (value is! String || !_businessDatePattern.hasMatch(value)) {
    throw const TenantReconciliationException('invalid_amendment_field');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! bool) {
    throw const TenantReconciliationException('invalid_amendment_field');
  }
  return value;
}

/// A recorded shift total is never negative and is bounded the same way the
/// shift history surface bounds one.
int _requiredMinorUnits(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value < 0 || value > _maximumShiftSalesMinor) {
    throw const TenantReconciliationException('invalid_amendment_field');
  }
  return value;
}

int _requiredCount(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value < 0 || value > _maximumShiftSalesMinor) {
    throw const TenantReconciliationException('invalid_amendment_field');
  }
  return value;
}

/// A difference is signed: a shift may have recorded more or less than its
/// sales, and reporting the direction is the point.
int _requiredDifference(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value.abs() > _maximumShiftSalesMinor) {
    throw const TenantReconciliationException('invalid_amendment_field');
  }
  return value;
}

DateTime? _optionalInstant(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantReconciliationException('invalid_amendment_field');
}

final RegExp _businessDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
