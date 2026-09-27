import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login selection follows local, default, sole, then selector order', () {
    final tenantA = _membership('tenant-a');
    final tenantB = _membership('tenant-b');

    final local = resolveTenantSelection(
      memberships: [tenantA, tenantB],
      lastSelectedTenantId: 'tenant-b',
      defaultTenantId: 'tenant-a',
    );
    expect(local.source, TenantSelectionSource.lastSelected);
    expect(local.selected, tenantB);

    final accountDefault = resolveTenantSelection(
      memberships: [tenantA, tenantB],
      lastSelectedTenantId: 'stale-tenant',
      defaultTenantId: 'tenant-a',
    );
    expect(accountDefault.source, TenantSelectionSource.accountDefault);
    expect(accountDefault.selected, tenantA);

    final sole = resolveTenantSelection(memberships: [tenantA]);
    expect(sole.source, TenantSelectionSource.soleAccessible);
    expect(sole.selected, tenantA);

    final selector = resolveTenantSelection(memberships: [tenantA, tenantB]);
    expect(selector.source, TenantSelectionSource.selector);
    expect(selector.selected, isNull);
    expect(selector.requiresSelector, isTrue);
  });

  test('stale preferred IDs never open inaccessible memberships', () {
    final pending = _membership(
      'tenant-pending',
      membershipStatus: MembershipStatus.pending,
      canAccess: false,
    );
    final suspended = _membership(
      'tenant-suspended',
      tenantStatus: TenantStatus.suspended,
      canAccess: false,
    );
    final active = _membership('tenant-active');

    final decision = resolveTenantSelection(
      memberships: [pending, suspended, active],
      lastSelectedTenantId: pending.tenantId,
      defaultTenantId: suspended.tenantId,
    );

    expect(decision.source, TenantSelectionSource.soleAccessible);
    expect(decision.selected, active);
    expect(decision.visible, [pending, suspended, active]);
  });

  test('non-accessible memberships remain visible when no tenant can open', () {
    final pending = _membership(
      'tenant-pending',
      membershipStatus: MembershipStatus.pending,
      canAccess: false,
    );
    final rejected = _membership(
      'tenant-rejected',
      tenantStatus: TenantStatus.suspended,
      canAccess: false,
    );

    final decision = resolveTenantSelection(
      memberships: [pending, rejected],
      lastSelectedTenantId: pending.tenantId,
    );

    expect(decision.source, TenantSelectionSource.none);
    expect(decision.opensTenant, isFalse);
    expect(decision.accessible, isEmpty);
    expect(decision.visible, [pending, rejected]);
  });

  test('duplicate tenant projections fail closed', () {
    expect(
      () => resolveTenantSelection(
        memberships: [_membership('tenant-a'), _membership('tenant-a')],
      ),
      throwsStateError,
    );
  });

  test('device-local key is scoped by UID', () {
    expect(
      lastSelectedTenantStorageKey('user-a'),
      'user-a:lastSelectedTenantId',
    );
    expect(() => lastSelectedTenantStorageKey(''), throwsArgumentError);
    expect(() => lastSelectedTenantStorageKey('bad:uid'), throwsArgumentError);
  });
}

TenantMembership _membership(
  String tenantId, {
  MembershipStatus membershipStatus = MembershipStatus.active,
  TenantStatus tenantStatus = TenantStatus.active,
  bool canAccess = true,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: TenantRole.admin,
  membershipStatus: membershipStatus,
  tenantStatus: tenantStatus,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: canAccess,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
