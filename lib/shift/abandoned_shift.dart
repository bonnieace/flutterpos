/// Shifts nobody can close, found and ended from the business rather than the
/// till.
///
/// **The gap this closes was total.** `firestore.rules` lets a cashier close
/// only their own shift, and only while they are an active member. Deactivate
/// someone mid-shift and both halves fail at once: they cannot close it because
/// they are no longer active, and nobody else can close it because it is not
/// theirs. The shift stayed open for ever, its business date never reconciled
/// cleanly, and the only remedy was an edit to the database.
///
/// **The finding and the close both live on the server.** `closeAbandonedShift`
/// is a callable that re-checks the actor's role and the cashier's standing
/// inside one transaction, so nothing here can be talked into ending a shift
/// that is still somebody's to finish. This half only *finds* them, and it
/// finds them the way an owner would: every open shift in the business, and
/// then which of their cashiers can no longer act.
library;

import 'package:cloud_functions/cloud_functions.dart';

import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import 'tenant_shift.dart';

/// One open shift whose cashier can no longer close it.
final class AbandonedShift {
  const AbandonedShift({
    required this.shiftId,
    required this.staffId,
    required this.staffName,
    required this.businessDate,
  });

  final String shiftId;
  final String staffId;

  /// What to call the person on screen. Their stored name where the staff
  /// record still carries one, and never a bare UID: a shopkeeper does not
  /// know their colleagues by identifier.
  final String? staffName;

  final String businessDate;
}

/// Finds this business's shifts that nobody can close.
///
/// **Owner, administrator and manager only**, which is exactly who the Rules
/// let read another cashier's shift. A cashier reading this would get a
/// permission error for every shift but their own, so the surface simply does
/// not offer it to them.
final class TenantAbandonedShiftRepository extends TenantReadRepository {
  TenantAbandonedShiftRepository({
    required super.session,
    required super.reader,
  });

  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  static bool isVisibleTo(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// Every open shift in this business whose cashier is not an active member.
  ///
  /// **Bounded, because this is a notification and not a report.** A business
  /// with more abandoned shifts than this has a problem no list will fix, and
  /// an unbounded read on a surface that opens on a badge is how a page hangs.
  Future<List<AbandonedShift>> find({
    required TenantCollectionReader collectionReader,
    int limit = 10,
  }) async {
    final page = await readCollectionPage(
      TenantCollection.shifts,
      collectionReader: collectionReader,
      pageSize: limit,
      equalityFilters: <String, Object?>{
        'status': TenantShiftStatus.open.wireValue,
      },
    );
    final abandoned = <AbandonedShift>[];
    for (final item in page.items) {
      final TenantShift shift;
      try {
        shift = TenantShift.fromDocument(path: item.path, data: item.data);
      } on TenantShiftException {
        // One unreadable shift must not take the whole notification down. It
        // is reported by reconciliation on its own terms.
        continue;
      }
      if (shift.tenantId != session.tenantId) continue;
      final staff = await _staff(shift.staffId);
      if (staff == null) continue;
      if (staff.active) continue;
      abandoned.add(
        AbandonedShift(
          shiftId: shift.id,
          staffId: shift.staffId,
          staffName: staff.name,
          businessDate: shift.businessDate,
        ),
      );
    }
    return List<AbandonedShift>.unmodifiable(abandoned);
  }

  /// The two facts about a cashier this needs: can they still act, and what do
  /// we call them.
  ///
  /// A staff record that cannot be read at all is skipped rather than assumed
  /// abandoned: the server decides that, and guessing here would put a live
  /// cashier's shift on an owner's screen with a button to end it.
  Future<({bool active, String? name})?> _staff(String uid) async {
    try {
      final data = await readDocument(TenantCollection.staff, uid);
      if (data == null) return null;
      final status = data['status'];
      final name = data['displayName'] ?? data['name'];
      return (active: status == 'active', name: name is String ? name : null);
    } catch (_) {
      return null;
    }
  }
}

/// Why a shift could not be closed from the business.
enum AbandonedShiftCloseFailure {
  /// The session may not close shifts, or its membership ended.
  forbidden,

  /// The shift is gone, already closed, or its cashier is active again.
  notClosable,

  /// The request itself was malformed, which is a defect in this app rather
  /// than a fact about the shift.
  ///
  /// **Separated out because folding it into [notClosable] told a lie.** A
  /// missing `reason` field came back as `invalid-argument` and was reported as
  /// *that shift is no longer open* - so the one message that would have named
  /// the bug instead described a state that was not true, and the shift sat
  /// there refusing to close with no clue as to why.
  malformed,

  /// The device could not reach the server.
  unavailable,

  /// The outcome is unknown; re-reading the shift settles it.
  ambiguous,
}

final class AbandonedShiftCloseException implements Exception {
  const AbandonedShiftCloseException(this.failure);

  final AbandonedShiftCloseFailure failure;

  @override
  String toString() => 'AbandonedShiftCloseException($failure)';
}

/// Narrow callable boundary for `closeAbandonedShift`.
///
/// It is the only path in the app that can end a shift belonging to somebody
/// else, and it can state nothing about what the drawer held: the server writes
/// the close under `closedWithoutEvidence`, so reconciliation reports the shift
/// as unverifiable rather than as a shift that took nothing.
abstract interface class CloseAbandonedShiftCallable {
  Future<void> call(Map<String, Object?> payload);
}

final class FirebaseCloseAbandonedShiftCallable
    implements CloseAbandonedShiftCallable {
  FirebaseCloseAbandonedShiftCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<void> call(Map<String, Object?> payload) async {
    try {
      await _functions
          .httpsCallable('closeAbandonedShift')
          .call<Object?>(payload);
    } on FirebaseFunctionsException catch (error) {
      throw AbandonedShiftCloseException(_failureOf(error.code));
    } catch (_) {
      throw const AbandonedShiftCloseException(
        AbandonedShiftCloseFailure.ambiguous,
      );
    }
  }

  static AbandonedShiftCloseFailure _failureOf(String code) => switch (code) {
    'permission-denied' ||
    'unauthenticated' => AbandonedShiftCloseFailure.forbidden,
    'failed-precondition' ||
    'not-found' => AbandonedShiftCloseFailure.notClosable,
    'invalid-argument' => AbandonedShiftCloseFailure.malformed,
    'unavailable' ||
    'deadline-exceeded' => AbandonedShiftCloseFailure.unavailable,
    _ => AbandonedShiftCloseFailure.ambiguous,
  };
}

/// What a refusal says to the person who caused it.
String abandonedShiftCloseMessage(AbandonedShiftCloseFailure failure) =>
    switch (failure) {
      AbandonedShiftCloseFailure.forbidden =>
        'Only an owner or administrator can close a shift for somebody else.',
      AbandonedShiftCloseFailure.notClosable =>
        'That shift is no longer open, or its cashier can close it themselves '
            'again.',
      AbandonedShiftCloseFailure.unavailable =>
        'This device is offline, so the shift could not be closed. Try again '
            'once it is back on the network.',
      AbandonedShiftCloseFailure.malformed =>
        'This app sent a request the server could not read, so nothing was '
            'closed. That is a fault here rather than anything about the '
            'shift - please report it.',
      AbandonedShiftCloseFailure.ambiguous =>
        'It is not clear whether that shift was closed. Refresh to see where '
            'it stands.',
    };
