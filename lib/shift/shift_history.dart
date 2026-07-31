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
    return TenantShiftHistoryEntry._(
      shift: shift,
      closingCashMinor: closingCashMinor,
      summary: _closingSummary(data),
    );
  }

  const TenantShiftHistoryEntry._({
    required this.shift,
    required this.closingCashMinor,
    required this.summary,
  });

  final TenantShift shift;
  final int closingCashMinor;

  /// Absent only when the shift was closed without a sale-derived summary.
  final ShiftClosingSummary? summary;

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
    final present = <Object?>[totalSalesMinor, totalSales, transactionCount]
        .where((value) => value != null)
        .length;
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
