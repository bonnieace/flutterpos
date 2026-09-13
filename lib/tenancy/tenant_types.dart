/// The roles supported by the tenant authorization contract.
///
/// Enum names and wire values intentionally match the lowercase values stored
/// by the backend. Decoding is strict: casing or unknown values are rejected.
enum TenantRole {
  owner('owner'),
  admin('admin'),
  manager('manager'),
  cashier('cashier');

  const TenantRole(this.wireValue);

  final String wireValue;

  static TenantRole fromJson(Object? value) {
    return switch (value) {
      'owner' => TenantRole.owner,
      'admin' => TenantRole.admin,
      'manager' => TenantRole.manager,
      'cashier' => TenantRole.cashier,
      _ => throw FormatException('Invalid tenant role: $value'),
    };
  }

  static TenantRole fromWire(Object? value) => fromJson(value);

  String toJson() => wireValue;

  bool get isOwner => this == TenantRole.owner;

  /// Owners deliberately inherit every permission granted to administrators.
  bool get isAdministrator =>
      this == TenantRole.owner || this == TenantRole.admin;

  /// Whether this role satisfies one of the roles accepted by an operation.
  ///
  /// This is not a general role hierarchy: manager-only and cashier-only
  /// operations remain exact matches. The sole inheritance rule frozen by the
  /// tenancy plan is that an owner satisfies an administrator permission.
  bool canAccess(Iterable<TenantRole> allowedRoles) {
    for (final allowedRole in allowedRoles) {
      if (allowedRole == this ||
          (this == TenantRole.owner && allowedRole == TenantRole.admin)) {
        return true;
      }
    }
    return false;
  }
}

/// The state of a user's canonical membership in one tenant.
enum MembershipStatus {
  pending('pending'),
  active('active'),
  inactive('inactive');

  const MembershipStatus(this.wireValue);

  final String wireValue;

  static MembershipStatus fromJson(Object? value) {
    return switch (value) {
      'pending' => MembershipStatus.pending,
      'active' => MembershipStatus.active,
      'inactive' => MembershipStatus.inactive,
      _ => throw FormatException('Invalid membership status: $value'),
    };
  }

  static MembershipStatus fromWire(Object? value) => fromJson(value);

  String toJson() => wireValue;
}

/// A tenant's lifecycle state.
enum TenantStatus {
  active('active'),
  suspended('suspended'),
  archived('archived');

  const TenantStatus(this.wireValue);

  final String wireValue;

  static TenantStatus fromJson(Object? value) {
    return switch (value) {
      'active' => TenantStatus.active,
      'suspended' => TenantStatus.suspended,
      'archived' => TenantStatus.archived,
      _ => throw FormatException('Invalid tenant status: $value'),
    };
  }

  static TenantStatus fromWire(Object? value) => fromJson(value);

  String toJson() => wireValue;
}

/// More explicit aliases for call sites that benefit from the longer names.
typedef TenantMembershipStatus = MembershipStatus;
typedef TenantLifecycleStatus = TenantStatus;
