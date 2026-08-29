import 'tenant_access.dart';
import 'tenant_id.dart';
import 'tenant_membership.dart';
import 'tenant_types.dart';

/// The immutable, selected tenant context for one app instance.
///
/// Async work should capture [epoch] and verify it with [ownsEpoch] before
/// applying results. [nextEpoch] creates a fresh session after revalidation or
/// switching, leaving the old instance untouched.
final class TenantSession {
  factory TenantSession({
    required String uid,
    required TenantAccess access,
    int epoch = 0,
  }) {
    if (uid.trim().isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Cannot be empty.');
    }
    // **`canRead`, not `canAccess`, since the provisional window landed.** A
    // request whose window has shut may still open its own business to look at
    // the week it traded; what it may not do is write, and that is `canAccess`'s
    // question rather than this one. A session it could not hold at all would
    // be a full lockout wearing read-only's name.
    if (!access.canRead()) {
      throw StateError('A tenant session requires canonical access.');
    }
    if (epoch < 0) {
      throw ArgumentError.value(epoch, 'epoch', 'Cannot be negative.');
    }
    return TenantSession._(uid: uid.trim(), access: access, epoch: epoch);
  }

  const TenantSession._({
    required this.uid,
    required this.access,
    required this.epoch,
  });

  factory TenantSession.fromMembership({
    required String uid,
    required TenantMembership membership,
    int epoch = 0,
  }) => TenantSession(uid: uid, access: membership.access, epoch: epoch);

  /// Convenience constructor for an already verified canonical access result.
  factory TenantSession.active({
    required String uid,
    required String tenantId,
    required TenantRole role,
    int epoch = 0,
  }) => TenantSession(
    uid: uid,
    access: TenantAccess(
      tenantId: validateTenantId(tenantId),
      role: role,
      membershipStatus: MembershipStatus.active,
      tenantStatus: TenantStatus.active,
      serverCanAccess: true,
      canonicalTenantExists: true,
      canonicalMembershipExists: true,
    ),
    epoch: epoch,
  );

  final String uid;
  final TenantAccess access;
  final int epoch;

  String get tenantId => access.tenantId;
  TenantRole get role => access.role;

  bool ownsEpoch(int capturedEpoch) => epoch == capturedEpoch;

  /// Whether this session may write. See [TenantAccess.canAccess].
  ///
  /// [now] is for a caller that holds its own clock - the checkout does, and a
  /// service that judged the window against the wall clock while stamping
  /// records from an injected one would disagree with itself.
  bool canAccess({Iterable<TenantRole>? allowedRoles, DateTime? now}) =>
      access.canAccess(allowedRoles: allowedRoles, now: now);

  /// Whether this session may read. See [TenantAccess.canRead].
  bool canRead({Iterable<TenantRole>? allowedRoles, DateTime? now}) =>
      access.canRead(allowedRoles: allowedRoles, now: now);

  /// Where this business stands right now.
  TenantStanding get standing => access.standingAt(DateTime.now().toUtc());

  /// Whether this business is trading on a deadline, and when it runs out.
  DateTime? get provisionalUntil => access.provisionalUntil;

  TenantSession copyWith({TenantAccess? access, int? epoch}) => TenantSession(
    uid: uid,
    access: access ?? this.access,
    epoch: epoch ?? this.epoch,
  );

  TenantSession nextEpoch({TenantAccess? access}) =>
      TenantSession(uid: uid, access: access ?? this.access, epoch: epoch + 1);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TenantSession &&
          uid == other.uid &&
          access == other.access &&
          epoch == other.epoch;

  @override
  int get hashCode => Object.hash(uid, access, epoch);
}
