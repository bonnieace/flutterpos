import 'package:cloud_firestore/cloud_firestore.dart';

import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import 'shift_sales_ledger.dart';
import 'tenant_shift.dart';

/// The sale-derived summary a shift carries once it has closed.
///
/// The device that closed the shift computed these figures from the sales the
/// server had already acknowledged. Nightly reconciliation compares them
/// against its own aggregate, so the history surface reports them exactly as
/// recorded and never recomputes them locally.
final class ShiftClosingSummary {
  const ShiftClosingSummary._({
    required this.totalSalesMinor,
    required this.transactionCount,
  });

  final int totalSalesMinor;
  final int transactionCount;

  /// The major-unit mirror stored beside the authoritative minor units.
  double get totalSales => totalSalesMinor / 100;
}

/// The account a corrected shift carries of its own correction.
///
/// `functions/src/reconciliation/amendments.ts` writes these four fields in the
/// same transaction that rewrites the shift's totals, settles its expectation,
/// and removes the listed difference. It is the only writer that can:
/// `firestore.rules` limits a cashier's one close update to the seven closing
/// keys and denies every other client write, so a shift carrying them was
/// corrected by `amendShiftSummary` and by nothing else.
///
/// They matter on a history row because the totals a corrected shift reports
/// **are** the rewritten ones. A row that showed them without saying so would
/// present a figure the cashier never closed as the figure they closed.
final class ShiftSummaryAmendment {
  const ShiftSummaryAmendment._({
    required this.latestId,
    required this.generation,
    required this.count,
    required this.amendedAt,
  });

  /// The most recent `shift_amendments` record written for this shift.
  final String latestId;

  /// The `shift_expectations` generation the corrected figure was read from. The
  /// trail's own `expectationGeneration` names the same one, which is what makes
  /// a second correction of the same comparison impossible.
  final String generation;

  /// How many corrections this shift's summary has had. The server increments
  /// it, so it counts every one rather than only the latest.
  final int count;

  /// The server instant of the latest correction.
  final DateTime? amendedAt;
}

/// Strict read model for one closed `tenants/{tenantId}/shifts/{shiftId}`.
///
/// Identity, path, device, business date, and status are proved by
/// [TenantShift]; this model adds the close-only fields. A shift closed by an
/// earlier client carries no summary at all, which is reported as absent rather
/// than guessed: only the closing device could have computed it.
final class TenantShiftHistoryEntry {
  factory TenantShiftHistoryEntry.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final shift = TenantShift.fromDocument(path: path, data: data);
    if (shift.status != TenantShiftStatus.closed) {
      throw const TenantShiftException('shift_not_closed');
    }
    final closingCashMinor = shift.closingCashMinor;
    if (closingCashMinor == null) {
      throw const TenantShiftException('invalid_shift_document');
    }
    final summary = _closingSummary(data);
    final amendment = _summaryAmendment(data);
    // A correction is read from the sale-derived expectation and rewrites the
    // three summary fields, so a corrected shift always carries a summary. A
    // document claiming otherwise cannot account for the figures it reports, and
    // this surface would have to say both that no totals were recorded and that
    // the totals were corrected.
    if (amendment != null && summary == null) {
      throw const TenantShiftException('amended_shift_without_summary');
    }
    return TenantShiftHistoryEntry._(
      shift: shift,
      closingCashMinor: closingCashMinor,
      summary: summary,
      amendment: amendment,
    );
  }

  const TenantShiftHistoryEntry._({
    required this.shift,
    required this.closingCashMinor,
    required this.summary,
    required this.amendment,
  });

  final TenantShift shift;
  final int closingCashMinor;

  /// Absent only when the shift was closed without a sale-derived summary.
  final ShiftClosingSummary? summary;

  /// Absent for every shift whose summary still says what its close said.
  final ShiftSummaryAmendment? amendment;

  String get id => shift.id;
  String get tenantId => shift.tenantId;
  String get staffId => shift.staffId;
  String get deviceId => shift.deviceId;
  String get businessDate => shift.businessDate;
  DateTime? get startedAt => shift.startedAt;
  DateTime? get endedAt => shift.endedAt;

  /// Counted cash minus recorded sales, in minor units.
  ///
  /// This is a subtraction of two recorded figures. The device deliberately
  /// does not recompute either side from local evidence: only reconciliation
  /// can decide which one is wrong.
  int? get cashVarianceMinor {
    final recorded = summary;
    return recorded == null
        ? null
        : closingCashMinor - recorded.totalSalesMinor;
  }

  /// The three summary fields are written by one close, so a document either
  /// carries all of them or none. A partial or incoherent summary is refused:
  /// it would misstate the shift on a screen used to settle cash.
  static ShiftClosingSummary? _closingSummary(Map<String, Object?> data) {
    final totalSalesMinor = data['totalSalesMinor'];
    final totalSales = data['totalSales'];
    final transactionCount = data['transactionCount'];
    final present = <Object?>[
      totalSalesMinor,
      totalSales,
      transactionCount,
    ].where((value) => value != null).length;
    if (present == 0) return null;
    if (present != 3) {
      throw const TenantShiftException('incomplete_shift_summary');
    }
    if (totalSalesMinor is! int ||
        totalSalesMinor < 0 ||
        totalSalesMinor > maximumShiftSalesMinor ||
        transactionCount is! int ||
        transactionCount < 0 ||
        totalSales is! num ||
        totalSales < 0) {
      throw const TenantShiftException('invalid_shift_summary');
    }
    if ((totalSales * 100).round() != totalSalesMinor) {
      throw const TenantShiftException('invalid_shift_summary');
    }
    if (totalSalesMinor > 0 && transactionCount == 0) {
      throw const TenantShiftException('invalid_shift_summary');
    }
    return ShiftClosingSummary._(
      totalSalesMinor: totalSalesMinor,
      transactionCount: transactionCount,
    );
  }

  /// The three deterministic correction fields are written by one transaction, so
  /// a document carries all of them or none. A partial set is refused rather than
  /// read as an uncorrected shift: no client can write any of these fields at
  /// all, so a partial set is either a server that changed its contract without
  /// this client knowing or a document no server wrote - and reporting a
  /// rewritten total as an original one is the single outcome this surface must
  /// not produce.
  ///
  /// `summaryAmendedAt` is a server timestamp, and every instant in this read
  /// model is decoded as absent-or-valid for that reason. Its absence limits what
  /// a row can say about when the correction happened; it never puts the
  /// correction itself in doubt.
  static ShiftSummaryAmendment? _summaryAmendment(Map<String, Object?> data) {
    final latestId = data['summaryAmendmentId'];
    final generation = data['summaryAmendedGeneration'];
    final count = data['summaryAmendmentCount'];
    final present = <Object?>[
      latestId,
      generation,
      count,
    ].where((value) => value != null).length;
    if (present == 0) {
      // An instant on its own records a correction that nothing else accounts
      // for, which is exactly the shape this check exists to catch.
      if (data['summaryAmendedAt'] != null) {
        throw const TenantShiftException('incomplete_shift_amendment');
      }
      return null;
    }
    if (present != 3) {
      throw const TenantShiftException('incomplete_shift_amendment');
    }
    // The server writes the amendment ID and increments the count in the same
    // update, so a corrected shift has had at least one correction. A count below
    // that contradicts the record beside it.
    if (count is! int || count < 1) {
      throw const TenantShiftException('invalid_shift_amendment');
    }
    return ShiftSummaryAmendment._(
      latestId: _amendmentDocumentId(latestId),
      generation: _amendmentGeneration(generation),
      count: count,
      amendedAt: _amendmentInstant(data['summaryAmendedAt']),
    );
  }
}

String _amendmentDocumentId(Object? value) {
  if (value is! String) {
    throw const TenantShiftException('invalid_shift_amendment');
  }
  try {
    return validateTenantDocumentId(value, fieldName: 'summaryAmendmentId');
  } on ArgumentError {
    throw const TenantShiftException('invalid_shift_amendment');
  }
}

/// A bounded printable identifier, held to the shape the corrections trail holds
/// its own copy of the same generation to.
String _amendmentGeneration(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 200 ||
      value != value.trim()) {
    throw const TenantShiftException('invalid_shift_amendment');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantShiftException('invalid_shift_amendment');
    }
  }
  return value;
}

DateTime? _amendmentInstant(Object? value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantShiftException('invalid_shift_amendment');
}

/// Whose closed shifts a history page covers.
enum TenantShiftHistoryScope {
  /// Only the authenticated cashier's own closed shifts.
  ownShifts,

  /// Every cashier's closed shifts, for management roles only.
  everyCashier,
}

/// One bounded page of closed shifts, newest document ID first.
final class TenantShiftHistoryPage {
  TenantShiftHistoryPage({
    required List<TenantShiftHistoryEntry> items,
    required this.nextCursor,
    required this.hasMore,
    required this.scope,
  }) : items = List<TenantShiftHistoryEntry>.unmodifiable(items);

  final List<TenantShiftHistoryEntry> items;
  final String? nextCursor;
  final bool hasMore;
  final TenantShiftHistoryScope scope;
}

/// Guarded read boundary over one tenant's closed shifts.
///
/// Every path is derived from the session's [TenantPaths]; the exact-child,
/// uniqueness, and ordering proofs of [TenantReadRepository] still apply. A
/// cashier may only page their own shifts, which is also what the Firestore
/// Rules allow, so the client and the server agree on the same boundary.
final class TenantShiftHistoryRepository extends TenantReadRepository {
  TenantShiftHistoryRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  /// The roles that may read another cashier's shift.
  static const List<TenantRole> managementRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  final TenantCollectionReader _collectionReader;

  /// Whether this session may page every cashier's closed shifts.
  static bool canReadEveryCashier(TenantSession session) =>
      session.canAccess(allowedRoles: managementRoles);

  Future<TenantShiftHistoryPage> loadPage({
    TenantShiftHistoryScope scope = TenantShiftHistoryScope.ownShifts,
    int pageSize = 20,
    String? cursor,
  }) async {
    final ownOnly = scope == TenantShiftHistoryScope.ownShifts;
    if (!ownOnly && !canReadEveryCashier(session)) {
      throw const TenantShiftException('shift_history_forbidden');
    }
    final page = await readCollectionPage(
      TenantCollection.shifts,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      // The generated shift ID embeds a fixed-width millisecond timestamp, so
      // descending document order is newest first. The recorded instants are
      // still rendered; the ordering is never presented as proof of time.
      descending: true,
      equalityFilters: <String, Object?>{
        'status': TenantShiftStatus.closed.wireValue,
        if (ownOnly) 'staffId': session.uid,
      },
    );

    final items = <TenantShiftHistoryEntry>[];
    for (final snapshot in page.items) {
      final entry = TenantShiftHistoryEntry.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (entry.tenantId != session.tenantId) {
        throw const TenantShiftException('cross_tenant_shift');
      }
      // The query filters by UID, but a transport that ignored the filter must
      // never widen what this cashier can see.
      if (ownOnly && entry.staffId != session.uid) {
        throw const TenantShiftException('foreign_shift');
      }
      items.add(entry);
    }
    return TenantShiftHistoryPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      scope: scope,
    );
  }
}
