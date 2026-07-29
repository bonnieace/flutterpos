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
  }) {
    return TenantAccess._(
      tenantId: validateTenantId(tenantId),
      role: role,
      membershipStatus: membershipStatus,
      tenantStatus: tenantStatus,
      serverCanAccess: serverCanAccess,
      canonicalTenantExists: canonicalTenantExists,
      canonicalMembershipExists: canonicalMembershipExists,
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

  bool get hasActiveCanonicalMembership =>
      serverCanAccess &&
      canonicalTenantExists &&
      canonicalMembershipExists &&
      membershipStatus == MembershipStatus.active &&
      tenantStatus == TenantStatus.active;

  /// Checks canonical access first, then applies an optional operation role.
  ///
  /// A null [allowedRoles] means any active tenant member. An empty iterable
  /// denies every role. Owners satisfy an administrator role through
  /// [TenantRole.canAccess].
  bool canAccess({Iterable<TenantRole>? allowedRoles}) {
    if (!hasActiveCanonicalMembership) {
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
