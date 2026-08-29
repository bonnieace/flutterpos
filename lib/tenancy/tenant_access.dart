import 'tenant_id.dart';
import 'tenant_types.dart';

/// A fail-closed access decision for one canonical tenant membership.
///
/// [serverCanAccess] is the backend's authorization projection. The canonical
/// existence flags and active statuses are retained so stale routing mirrors
/// can be displayed without accidentally becoming authorization inputs.
final class TenantAccess {
  factory TenantAccess({
    required String tenantId,
    required TenantRole role,
    required MembershipStatus membershipStatus,
    required TenantStatus tenantStatus,
    required bool serverCanAccess,
    required bool canonicalTenantExists,
    required bool canonicalMembershipExists,
    DateTime? provisionalUntil,
  }) {
    return TenantAccess._(
      tenantId: validateTenantId(tenantId),
      role: role,
      membershipStatus: membershipStatus,
      tenantStatus: tenantStatus,
      serverCanAccess: serverCanAccess,
      canonicalTenantExists: canonicalTenantExists,
      canonicalMembershipExists: canonicalMembershipExists,
      provisionalUntil: provisionalUntil?.toUtc(),
    );
  }

  const TenantAccess._({
    required this.tenantId,
    required this.role,
    required this.membershipStatus,
    required this.tenantStatus,
    required this.serverCanAccess,
    required this.canonicalTenantExists,
    required this.canonicalMembershipExists,
    this.provisionalUntil,
  });

  factory TenantAccess.fromJson(Map<String, Object?> json) {
    try {
      return TenantAccess(
        tenantId: _requiredString(json, 'tenantId'),
        role: TenantRole.fromJson(json['role']),
        membershipStatus: MembershipStatus.fromJson(json['membershipStatus']),
        tenantStatus: TenantStatus.fromJson(json['tenantStatus']),
        serverCanAccess: _requiredBool(json, 'canAccess'),
        canonicalTenantExists: _requiredBool(json, 'canonicalTenantExists'),
        canonicalMembershipExists: _requiredBool(
          json,
          'canonicalMembershipExists',
        ),
        provisionalUntil: _optionalInstant(json, 'provisionalUntil'),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid tenant access: ${error.message}');
    }
  }

  factory TenantAccess.fromMap(Map<String, Object?> map) =>
      TenantAccess.fromJson(map);

  final String tenantId;
  final TenantRole role;
  final MembershipStatus membershipStatus;
  final TenantStatus tenantStatus;
  final bool serverCanAccess;
  final bool canonicalTenantExists;
  final bool canonicalMembershipExists;

  /// When a self-serve request's provisional trading window shuts, in UTC.
  ///
  /// Only ever present on a `pending` tenant. Absent means there is no window -
  /// which is what every tenant requested before the window existed, and every
  /// tenant seeded by hand, looks like. Such a tenant reads as [lapsed] rather
  /// than as a window that never closes, exactly as `firestore.rules` treats it.
  final DateTime? provisionalUntil;

  /// The membership facts, before the tenant's own standing is considered.
  bool get _membershipIsCanonical =>
      serverCanAccess &&
      canonicalTenantExists &&
      canonicalMembershipExists &&
      membershipStatus == MembershipStatus.active;

  /// What this membership may do at [nowUtc]. See [TenantStanding].
  ///
  /// **Mirrors `firestore.rules` deliberately**, and cannot be the authority:
  /// the server decides, and this exists so the app does not offer an action it
  /// already knows will be refused. The two are written to agree - status first,
  /// so a stale window on a rejected business decides nothing.
  TenantStanding standingAt(DateTime nowUtc) {
    if (!_membershipIsCanonical) return TenantStanding.closed;
    if (tenantStatus == TenantStatus.active) return TenantStanding.approved;
    if (tenantStatus != TenantStatus.pending) return TenantStanding.closed;
    final until = provisionalUntil;
    if (until != null && nowUtc.toUtc().isBefore(until)) {
      return TenantStanding.provisional;
    }
    return TenantStanding.lapsed;
  }

  /// Whether this membership may trade right now.
  bool get hasActiveCanonicalMembership => canAccess();

  /// Checks canonical access first, then applies an optional operation role.
  ///
  /// A null [allowedRoles] means any active tenant member. An empty iterable
  /// denies every role. Owners satisfy an administrator role through
  /// [TenantRole.canAccess].
  /// Whether this membership may **write**: approved, or inside its window.
  ///
  /// **[now] defaults to the wall clock rather than being required.** A hundred
  /// call sites ask this question and none of them holds a clock; making it a
  /// parameter everywhere to serve one testable case would have been the change
  /// that broke them all. The rules read `request.time` for the same comparison.
  bool canAccess({Iterable<TenantRole>? allowedRoles, DateTime? now}) {
    final standing = standingAt(now ?? DateTime.now().toUtc());
    if (standing != TenantStanding.approved &&
        standing != TenantStanding.provisional) {
      return false;
    }
    return allowedRoles == null || role.canAccess(allowedRoles);
  }

  /// Whether this membership may **read**: everything [canAccess] allows, plus
  /// a request whose provisional window has shut.
  ///
  /// A lapsed request keeps sight of the week it traded - real cash counted at
  /// close, receipts customers are holding - and simply cannot add to it.
  bool canRead({Iterable<TenantRole>? allowedRoles, DateTime? now}) {
    if (standingAt(now ?? DateTime.now().toUtc()) == TenantStanding.closed) {
      return false;
    }
    return allowedRoles == null || role.canAccess(allowedRoles);
  }

  bool get isAdministrativePrincipal =>
      hasActiveCanonicalMembership && role.isAdministrator;

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'role': role.toJson(),
    'membershipStatus': membershipStatus.toJson(),
    'tenantStatus': tenantStatus.toJson(),
    'canAccess': serverCanAccess,
    'canonicalTenantExists': canonicalTenantExists,
    'canonicalMembershipExists': canonicalMembershipExists,
    if (provisionalUntil != null)
      'provisionalUntil': provisionalUntil!.toUtc().millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TenantAccess &&
          tenantId == other.tenantId &&
          role == other.role &&
          membershipStatus == other.membershipStatus &&
          tenantStatus == other.tenantStatus &&
          serverCanAccess == other.serverCanAccess &&
          canonicalTenantExists == other.canonicalTenantExists &&
          canonicalMembershipExists == other.canonicalMembershipExists;

  @override
  int get hashCode => Object.hash(
    tenantId,
    role,
    membershipStatus,
    tenantStatus,
    serverCanAccess,
    canonicalTenantExists,
    canonicalMembershipExists,
  );
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! bool) {
    throw FormatException('$field must be a boolean.');
  }
  return value;
}


/// Where a business stands, which decides what its members may do.
///
/// The four are ordered by how much they permit, and the gap between
/// [provisional] and [lapsed] is a deadline rather than a decision.
enum TenantStanding {
  /// Approved. Trades without qualification.
  approved,

  /// A self-serve request inside its provisional window. Trades exactly as
  /// [approved] does, except that it may not invite staff - provisioning an
  /// identity and mailing a stranger outlive a window that may never be
  /// approved.
  provisional,

  /// A self-serve request whose window has shut. Reads its own records and
  /// writes nothing, until somebody approves or rejects it.
  lapsed,

  /// Rejected, suspended, archived, or no longer a member. Nothing is offered.
  closed,
}

DateTime? _optionalInstant(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is! int) {
    throw ArgumentError.value(value, field, 'Expected epoch milliseconds.');
  }
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}
