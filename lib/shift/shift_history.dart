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

/// One shift of a single trading day, **open or closed**.
///
/// **Why this exists beside [TenantShiftHistoryEntry].** That model refuses a
/// shift that is not closed - deliberately, because it is the record a cash
/// settlement is read from and an open shift has no settlement. The sales
/// totals screen asks a different question when its period is one day: *who
/// took what today*, and today normally has a shift still running. Waiting for
/// the close would leave the current cashier out of the comparison.
///
/// So this is the permissive read: identity, staff, device and times are proved
/// the same way, and everything the close writes is optional. A shift still
/// open simply has no [summary] yet.
/// Counted cash minus recorded sales, in minor units, or null where nothing is
/// known.
///
/// **One copy, read by a row and by a report.** The rule this encodes is
/// load-bearing and easy to get subtly wrong - see
/// [TenantShiftHistoryEntry.cashVarianceMinor] for the whole argument - so a
/// period report computes it by calling this rather than by restating it. A
/// second spelling that drifted would have a report disagreeing with the
/// screen about the same shift.
///
/// Null where the shift closed without its sales, where it carries no
/// declaration, and while it is still running. Zero means counted and level;
/// null means nobody can say.
int? _cashVarianceMinor(TenantShift shift, ShiftClosingSummary? summary) {
  if (shift.closedWithoutEvidence) return null;
  final declared = shift.declaration;
  if (summary == null || declared == null) return null;
  final declaredTotalMinor =
      declared.cashMinor + declared.mpesaMinor + declared.cardMinor;
  return declaredTotalMinor - shift.openingFloatMinor - summary.totalSalesMinor;
}

final class TenantShiftDaySlice {
  const TenantShiftDaySlice._({required this.shift, required this.summary});

  factory TenantShiftDaySlice.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final shift = TenantShift.fromDocument(path: path, data: data);
    return TenantShiftDaySlice._(
      shift: shift,
      // The three closing fields are written together or not at all, and
      // `_closingSummary` already refuses a partial set. An open shift has
      // none of them, which is not a defect.
      summary: TenantShiftHistoryEntry._closingSummary(data),
    );
  }

  final TenantShift shift;

  /// The sale-derived totals the close wrote, or null while the shift runs.
  final ShiftClosingSummary? summary;

  bool get isOpen => shift.status == TenantShiftStatus.open;

  /// What this shift took, or null while it is still running.
  double? get totalSales => summary?.totalSales;

  /// Counted against recorded, in minor units. See [_cashVarianceMinor].
  ///
  /// **Null for a shift still running**, as well as for every shift that
  /// closed without its sales: there is nothing to compare a drawer against
  /// until the drawer has been counted.
  int? get cashVarianceMinor => _cashVarianceMinor(shift, summary);

  String get id => shift.id;
  String get staffId => shift.staffId;
  String get businessDate => shift.businessDate;
  DateTime? get startedAt => shift.startedAt;
  DateTime? get endedAt => shift.endedAt;
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
  /// **Null for a shift closed without its sales, because nothing is known.**
  /// Such a close writes zero for the counted cash and zero for the takings -
  /// not as figures but as an admission that the closing device held none -
  /// and subtracting one from the other produced a variance of zero, which
  /// this surface drew as *Cash matches* with a positive badge. That is the
  /// most confident possible statement about the one shift nobody can make any
  /// statement about. `closedWithoutEvidence` is the marker that says so, and
  /// the server reads it the same way: see `compareShiftTenders` and
  /// `verifyShiftExpectation`, both of which decline to compare.
  /// **It compares the whole declaration against the whole takings, because
  /// those are the two figures that describe the same thing.** It used to be
  /// `closingCashMinor - totalSalesMinor`: counted *cash* against sales by
  /// *every* method. A shop taking half its money by M-Pesa therefore read as
  /// short by exactly that half, every day, on the surface a cashier is
  /// answerable from - and would go looking for money that was never missing.
  ///
  /// The server has always made the honest comparison and still does, per
  /// method, in `compareShiftTenders`. What the shift document lacks is a
  /// per-tender *sales* split, so this cannot repeat that work; what it has is
  /// the declared triple, and the sum of that is comparable to the sales total
  /// on its own terms.
  ///
  /// **Null where the declaration is absent**, which is every shift closed
  /// before the triple existed. Those carry a cash figure alone, and comparing
  /// one method against all of them is the defect this replaces.
  ///
  /// **The opening float is subtracted, for the same reason the server adds it
  /// to the other side.** The cashier counts the whole drawer, change included,
  /// so a declaration from a floated till is over its takings by exactly that
  /// float. Leaving it in would have this row read *Takings over* by the float
  /// every day - and disagree with the verification an owner sees for the same
  /// shift, which is worse than either figure being wrong alone.
  int? get cashVarianceMinor => _cashVarianceMinor(shift, summary);

  /// The change this drawer started with, in minor units.
  ///
  /// Zero for a shift opened with no float and for every shift opened before
  /// the field existed. Exposed so a surface showing a variance can also show
  /// the figure that was taken out of it.
  int get openingFloatMinor => shift.openingFloatMinor;

  /// Whether this shift was closed by something holding none of its sales.
  ///
  /// Separate from [cashVarianceMinor] being null, which a shift closed before
  /// summaries existed also is: the two read the same on a badge and need
  /// different words, because one is an old record and the other is a shift
  /// somebody had to end on a cashier's behalf.
  bool get closedWithoutEvidence => shift.closedWithoutEvidence;

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

  /// Every shift one trading day held, **open ones included**, oldest first.
  ///
  /// **The status filter is dropped rather than widened**, which is what makes
  /// this a different query from [loadPage] rather than a flag on it. A
  /// per-cashier comparison wants the shape of the day, and the shift still
  /// running is part of that shape; a history page wants settled records, and
  /// an open shift is not one. Two questions, two queries, two indexes.
  ///
  /// Needs (`businessDate`, `__name__`) and, for a cashier, (`staffId`,
  /// `businessDate`, `__name__`). Both are in `firestore.indexes.json`.
  Future<List<TenantShiftDaySlice>> loadDayShifts({
    required String businessDate,
    TenantShiftHistoryScope scope = TenantShiftHistoryScope.ownShifts,
    int pageSize = 20,
  }) async {
    final ownOnly = scope == TenantShiftHistoryScope.ownShifts;
    if (!ownOnly && !canReadEveryCashier(session)) {
      throw const TenantShiftException('shift_history_forbidden');
    }
    final page = await readCollectionPage(
      TenantCollection.shifts,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      // Oldest first: a day reads left to right, and the generated shift ID
      // embeds a fixed-width millisecond timestamp so ascending document order
      // is opening order. The recorded instants are still what is rendered.
      descending: false,
      equalityFilters: <String, Object?>{
        'businessDate': businessDate,
        if (ownOnly) 'staffId': session.uid,
      },
    );
    final slices = <TenantShiftDaySlice>[];
    for (final snapshot in page.items) {
      final slice = TenantShiftDaySlice.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (slice.shift.tenantId != session.tenantId) {
        throw const TenantShiftException('cross_tenant_shift');
      }
      // The query filters on both, and a transport that ignored either must
      // not put another cashier's or another day's takings under this heading.
      if (ownOnly && slice.staffId != session.uid) {
        throw const TenantShiftException('foreign_shift');
      }
      if (slice.businessDate != businessDate) {
        throw const TenantShiftException('foreign_business_date');
      }
      slices.add(slice);
    }
    return List<TenantShiftDaySlice>.unmodifiable(slices);
  }

  /// One trading day's **closed** shifts, oldest first, for everyone or for one
  /// member.
  ///
  /// **The history screen's read since 2026-09-22**, when its filters became a
  /// day and a person - the pair the sales report and the returns feed carry.
  /// It asks [loadDayShifts]'s question, so it rides the same two indexes:
  /// (`businessDate`, `__name__`) and, for one member, (`staffId`,
  /// `businessDate`, `__name__`). And it keeps what [loadPage] keeps: a shift
  /// still running is **left out rather than refused**, because this query has
  /// no status filter to exclude it with and it is not history yet.
  ///
  /// A null [staffId] is every member, and naming anyone but the session's own
  /// UID is the same reach; both are management's. A cashier reads their own
  /// shifts and nothing else, which is also what the rules allow.
  Future<TenantShiftHistoryPage> loadDayPage({
    required String businessDate,
    String? staffId,
    int pageSize = 20,
    String? cursor,
  }) async {
    final ownOnly = staffId == session.uid;
    if (!ownOnly && !canReadEveryCashier(session)) {
      throw const TenantShiftException('shift_history_forbidden');
    }
    final page = await readCollectionPage(
      TenantCollection.shifts,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      // Oldest first, as [loadDayShifts] reads a day: the generated shift ID
      // embeds a fixed-width millisecond, so ascending is opening order.
      descending: false,
      equalityFilters: <String, Object?>{
        'businessDate': businessDate,
        if (staffId != null) 'staffId': staffId,
      },
    );

    final items = <TenantShiftHistoryEntry>[];
    for (final snapshot in page.items) {
      final shift = TenantShift.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (shift.tenantId != session.tenantId) {
        throw const TenantShiftException('cross_tenant_shift');
      }
      // Proved before the status is read: a transport that ignored either
      // filter is a broken boundary whether or not the shift has closed.
      if (staffId != null && shift.staffId != staffId) {
        throw const TenantShiftException('foreign_shift');
      }
      if (shift.businessDate != businessDate) {
        throw const TenantShiftException('foreign_business_date');
      }
      if (shift.status != TenantShiftStatus.closed) continue;
      items.add(
        TenantShiftHistoryEntry.fromDocument(
          path: snapshot.path,
          data: snapshot.data,
        ),
      );
    }
    return TenantShiftHistoryPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      // The reach the read needed: anyone's but the session's own is the
      // every-cashier permission, whether the filter names one colleague or
      // none.
      scope: ownOnly
          ? TenantShiftHistoryScope.ownShifts
          : TenantShiftHistoryScope.everyCashier,
    );
  }

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

  /// Every shift over a span of trading days, oldest first, **open ones
  /// included**.
  ///
  /// **Open shifts come back because a report has to count them.** A period
  /// holding a shift nobody closed is a fact about that period: the drawer was
  /// never counted, so its takings were never settled, and a report that
  /// silently dropped it would show a day as reconciled that is not. The
  /// caller separates them; this read does not decide for it.
  ///
  /// **Management only, and no per-cashier narrowing.** A period report over
  /// the whole business is the every-cashier permission whichever way it is
  /// sliced, so there is no own-shifts mode here to be tempted by - a cashier
  /// gets no shifts report at all rather than one covering only themselves,
  /// which would read as the shop's and be one person's.
  ///
  /// Rides the automatic (`businessDate`, `__name__`) index: no equality joins
  /// the range, so nothing new is deployed for it.
  Future<
    ({List<TenantShiftDaySlice> items, TenantBusinessDateRangePosition? next})
  >
  loadDateRange({
    required String startBusinessDate,
    required String endBusinessDate,
    int pageSize = 50,
    TenantBusinessDateRangePosition? startAfter,
  }) async {
    if (!canReadEveryCashier(session)) {
      throw const TenantShiftException('shift_history_forbidden');
    }
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    if (startBusinessDate.compareTo(endBusinessDate) > 0) {
      throw const TenantShiftException('invalid_shift_range');
    }
    final reader = _collectionReader is TenantReportRangeReader
        ? _collectionReader as TenantReportRangeReader
        : null;
    if (reader == null) {
      throw StateError('This reader cannot read a shifts period.');
    }

    final requested = pageSize + 1;
    final snapshots = await reader.queryTenantBusinessDateRange(
      TenantBusinessDateRangeQuery.scoped(
        collectionPath: paths.collectionPath(TenantCollection.shifts),
        orderBy: TenantBusinessDateRangeField.businessDate,
        limit: requested,
        startBusinessDate: startBusinessDate,
        endBusinessDate: endBusinessDate,
        startAfter: startAfter,
      ),
    );
    if (snapshots.length > requested) {
      throw const TenantScopeViolation(
        'The shifts period returned more documents than requested.',
      );
    }

    final slices = <TenantShiftDaySlice>[];
    final seen = <String>{};
    for (final snapshot in snapshots) {
      final slice = TenantShiftDaySlice.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (!seen.add(slice.shift.id)) {
        throw const TenantScopeViolation(
          'The shifts period returned a duplicate document.',
        );
      }
      if (slice.shift.tenantId != session.tenantId) {
        throw const TenantShiftException('cross_tenant_shift');
      }
      // The query bounds the span; a transport that ignored either bound must
      // not put a shift under a period it did not trade in.
      if (slice.businessDate.compareTo(startBusinessDate) < 0 ||
          slice.businessDate.compareTo(endBusinessDate) > 0) {
        throw const TenantShiftException('foreign_business_date');
      }
      slices.add(slice);
    }

    final hasMore = slices.length > pageSize;
    final visible = hasMore
        ? slices.take(pageSize).toList(growable: false)
        : slices;
    return (
      items: visible,
      next: hasMore
          ? TenantBusinessDateRangePosition(
              businessDate: visible.last.businessDate,
              documentId: visible.last.shift.id,
            )
          : null,
    );
  }
}
