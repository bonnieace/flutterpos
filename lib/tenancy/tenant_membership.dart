import 'tenant_access.dart';
import 'tenant_id.dart';
import 'tenant_types.dart';

/// The app-facing projection returned by `listMyTenants`.
///
/// It contains routing metadata, but access remains governed by the canonical
/// decision represented by [access]. No Firebase types leak into this model.
final class TenantMembership {
  factory TenantMembership({
    required String tenantId,
    required String tenantName,
    required String tenantSlug,
    required TenantRole role,
    required MembershipStatus membershipStatus,
    required TenantStatus tenantStatus,
    String? invitationStatus,
    required bool isOwner,
    required int mirrorVersion,
    required DateTime? createdAt,
    DateTime? joinedAt,
    required DateTime? updatedAt,
    required bool serverCanAccess,
    required bool canonicalTenantExists,
    required bool canonicalMembershipExists,
  }) {
    final normalizedTenantId = validateTenantId(tenantId);
    if (tenantName.trim().isEmpty) {
      throw ArgumentError.value(tenantName, 'tenantName', 'Cannot be empty.');
    }
    if (tenantSlug.trim().isEmpty) {
      throw ArgumentError.value(tenantSlug, 'tenantSlug', 'Cannot be empty.');
    }
    if (invitationStatus != null && invitationStatus.trim().isEmpty) {
      throw ArgumentError.value(
        invitationStatus,
        'invitationStatus',
        'Cannot be empty when present.',
      );
    }
    if (mirrorVersion < 0) {
      throw ArgumentError.value(
        mirrorVersion,
        'mirrorVersion',
        'Cannot be negative.',
      );
    }
    return TenantMembership._(
      tenantId: normalizedTenantId,
      tenantName: tenantName.trim(),
      tenantSlug: tenantSlug.trim(),
      role: role,
      membershipStatus: membershipStatus,
      tenantStatus: tenantStatus,
      invitationStatus: invitationStatus?.trim(),
      isOwner: isOwner,
      mirrorVersion: mirrorVersion,
      createdAt: createdAt?.toUtc(),
      joinedAt: joinedAt?.toUtc(),
      updatedAt: updatedAt?.toUtc(),
      serverCanAccess: serverCanAccess,
      canonicalTenantExists: canonicalTenantExists,
      canonicalMembershipExists: canonicalMembershipExists,
    );
  }

  const TenantMembership._({
    required this.tenantId,
    required this.tenantName,
    required this.tenantSlug,
    required this.role,
    required this.membershipStatus,
    required this.tenantStatus,
    required this.invitationStatus,
    required this.isOwner,
    required this.mirrorVersion,
    required this.createdAt,
    required this.joinedAt,
    required this.updatedAt,
    required this.serverCanAccess,
    required this.canonicalTenantExists,
    required this.canonicalMembershipExists,
  });

  factory TenantMembership.fromJson(Map<String, Object?> json) {
    try {
      return TenantMembership(
        tenantId: _requiredString(json, 'tenantId'),
        tenantName: _requiredString(json, 'tenantName'),
        tenantSlug: _requiredString(json, 'tenantSlug'),
        role: TenantRole.fromJson(json['role']),
        membershipStatus: MembershipStatus.fromJson(json['membershipStatus']),
        tenantStatus: TenantStatus.fromJson(json['tenantStatus']),
        invitationStatus: _optionalString(json, 'invitationStatus'),
        isOwner: _requiredBool(json, 'isOwner'),
        mirrorVersion: _requiredNonNegativeInt(json, 'mirrorVersion'),
        createdAt: _optionalDateTime(json, 'createdAt'),
        joinedAt: _optionalDateTime(json, 'joinedAt'),
        updatedAt: _optionalDateTime(json, 'updatedAt'),
        serverCanAccess: _requiredBool(json, 'canAccess'),
        canonicalTenantExists: _requiredBool(json, 'canonicalTenantExists'),
        canonicalMembershipExists: _requiredBool(
          json,
          'canonicalMembershipExists',
        ),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid tenant membership: ${error.message}');
    }
  }

  factory TenantMembership.fromMap(Map<String, Object?> map) =>
      TenantMembership.fromJson(map);

  final String tenantId;
  final String tenantName;
  final String tenantSlug;
  final TenantRole role;
  final MembershipStatus membershipStatus;
  final TenantStatus tenantStatus;
  final String? invitationStatus;
  final bool isOwner;
  final int mirrorVersion;
  final DateTime? createdAt;
  final DateTime? joinedAt;
  final DateTime? updatedAt;
  final bool serverCanAccess;
  final bool canonicalTenantExists;
  final bool canonicalMembershipExists;

  bool get ownerInvariantValid => isOwner == role.isOwner;

  TenantAccess get access => TenantAccess(
    tenantId: tenantId,
    role: role,
    membershipStatus: membershipStatus,
    tenantStatus: tenantStatus,
    serverCanAccess: serverCanAccess && ownerInvariantValid,
    canonicalTenantExists: canonicalTenantExists,
    canonicalMembershipExists: canonicalMembershipExists,
  );

  bool canAccess({Iterable<TenantRole>? allowedRoles}) =>
      access.canAccess(allowedRoles: allowedRoles);

  bool get isAdministrativePrincipal => access.isAdministrativePrincipal;

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'tenantName': tenantName,
    'tenantSlug': tenantSlug,
    'role': role.toJson(),
    'membershipStatus': membershipStatus.toJson(),
    'tenantStatus': tenantStatus.toJson(),
    if (invitationStatus != null) 'invitationStatus': invitationStatus,
    'isOwner': isOwner,
    'mirrorVersion': mirrorVersion,
    'createdAt': createdAt?.toIso8601String(),
    'joinedAt': joinedAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'canAccess': serverCanAccess,
    'canonicalTenantExists': canonicalTenantExists,
    'canonicalMembershipExists': canonicalMembershipExists,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TenantMembership &&
          tenantId == other.tenantId &&
          tenantName == other.tenantName &&
          tenantSlug == other.tenantSlug &&
          role == other.role &&
          membershipStatus == other.membershipStatus &&
          tenantStatus == other.tenantStatus &&
          invitationStatus == other.invitationStatus &&
          isOwner == other.isOwner &&
          mirrorVersion == other.mirrorVersion &&
          createdAt == other.createdAt &&
          joinedAt == other.joinedAt &&
          updatedAt == other.updatedAt &&
          serverCanAccess == other.serverCanAccess &&
          canonicalTenantExists == other.canonicalTenantExists &&
          canonicalMembershipExists == other.canonicalMembershipExists;

  @override
  int get hashCode => Object.hash(
    tenantId,
    tenantName,
    tenantSlug,
    role,
    membershipStatus,
    tenantStatus,
    invitationStatus,
    isOwner,
    mirrorVersion,
    createdAt,
    joinedAt,
    updatedAt,
    serverCanAccess,
    canonicalTenantExists,
    canonicalMembershipExists,
  );
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string when present.');
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

int _requiredNonNegativeInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! int || value < 0) {
    throw FormatException('$field must be a non-negative integer.');
  }
  return value;
}

DateTime? _optionalDateTime(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toUtc();
    }
  }
  throw FormatException('$field must be a nullable ISO-8601 string.');
}
