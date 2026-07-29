import 'tenant_membership.dart';

enum TenantSelectionSource {
  lastSelected,
  accountDefault,
  soleAccessible,
  selector,
  none,
}

/// Pure login-routing decision after every `listMyTenants` page is loaded.
final class TenantSelectionDecision {
  const TenantSelectionDecision._({
    required this.source,
    required this.selected,
    required this.accessible,
    required this.visible,
  });

  final TenantSelectionSource source;
  final TenantMembership? selected;
  final List<TenantMembership> accessible;

  /// Includes pending, inactive, rejected, suspended, and archived entries so
  /// the selector can explain why they cannot be opened.
  final List<TenantMembership> visible;

  bool get opensTenant => selected != null;
  bool get requiresSelector => source == TenantSelectionSource.selector;
}

/// Local selection is device-specific and deliberately names the Auth UID.
String lastSelectedTenantStorageKey(String uid) {
  final normalized = uid.trim();
  if (normalized.isEmpty || normalized.contains(':')) {
    throw ArgumentError.value(
      uid,
      'uid',
      'Must be non-empty and contain no colon.',
    );
  }
  return '$normalized:lastSelectedTenantId';
}

/// Applies the frozen login precedence without treating a routing mirror as
/// authority. Callers must pass the complete paginated result.
TenantSelectionDecision resolveTenantSelection({
  required Iterable<TenantMembership> memberships,
  String? lastSelectedTenantId,
  String? defaultTenantId,
}) {
  final visible = List<TenantMembership>.unmodifiable(memberships);
  final tenantIds = <String>{};
  for (final membership in visible) {
    if (!tenantIds.add(membership.tenantId)) {
      throw StateError('Duplicate tenant membership: ${membership.tenantId}');
    }
  }
  final accessible = List<TenantMembership>.unmodifiable(
    visible.where((membership) => membership.canAccess()),
  );

  TenantMembership? accessibleById(String? tenantId) {
    if (tenantId == null || tenantId.isEmpty) return null;
    for (final membership in accessible) {
      if (membership.tenantId == tenantId) return membership;
    }
    return null;
  }

  final lastSelected = accessibleById(lastSelectedTenantId);
  if (lastSelected != null) {
    return TenantSelectionDecision._(
      source: TenantSelectionSource.lastSelected,
      selected: lastSelected,
      accessible: accessible,
      visible: visible,
    );
  }
  final accountDefault = accessibleById(defaultTenantId);
  if (accountDefault != null) {
    return TenantSelectionDecision._(
      source: TenantSelectionSource.accountDefault,
      selected: accountDefault,
      accessible: accessible,
      visible: visible,
    );
  }
  if (accessible.length == 1) {
    return TenantSelectionDecision._(
      source: TenantSelectionSource.soleAccessible,
      selected: accessible.single,
      accessible: accessible,
      visible: visible,
    );
  }
  return TenantSelectionDecision._(
    source: accessible.isEmpty
        ? TenantSelectionSource.none
        : TenantSelectionSource.selector,
    selected: null,
    accessible: accessible,
    visible: visible,
  );
}
