import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TenantSession', () {
    test('is immutable and retains the selected tenant epoch', () {
      final original = TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.manager,
        epoch: 4,
      );
      final copied = original.copyWith(epoch: 7);

      expect(original.tenantId, 'tenant-a');
      expect(original.epoch, 4);
      expect(original.ownsEpoch(4), isTrue);
      expect(original.ownsEpoch(7), isFalse);
      expect(copied.tenantId, 'tenant-a');
      expect(copied.epoch, 7);
      expect(copied, isNot(same(original)));
    });

    test('nextEpoch invalidates captured work and can switch tenants', () {
      final original = TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.admin,
        epoch: 9,
      );
      final switched = original.nextEpoch(
        access: _activeAccess('tenant-b', TenantRole.cashier),
      );

      expect(switched.tenantId, 'tenant-b');
      expect(switched.epoch, 10);
      expect(switched.ownsEpoch(original.epoch), isFalse);
      expect(original.tenantId, 'tenant-a');
      expect(original.epoch, 9);
    });

    test('owner sessions inherit administrator access', () {
      final session = TenantSession.active(
        uid: 'owner-a',
        tenantId: 'tenant-a',
        role: TenantRole.owner,
      );

      expect(session.canAccess(allowedRoles: const [TenantRole.admin]), isTrue);
    });

    test('cannot be created from stale or inaccessible routing state', () {
      final inactive = TenantAccess(
        tenantId: 'tenant-a',
        role: TenantRole.admin,
        membershipStatus: MembershipStatus.inactive,
        tenantStatus: TenantStatus.active,
        serverCanAccess: false,
        canonicalTenantExists: true,
        canonicalMembershipExists: true,
      );

      expect(
        () => TenantSession(uid: 'user-a', access: inactive),
        throwsStateError,
      );
      expect(
        () => TenantSession.active(
          uid: 'user-a',
          tenantId: 'tenant-a',
          role: TenantRole.admin,
          epoch: -1,
        ),
        throwsArgumentError,
      );
    });
  });
}

TenantAccess _activeAccess(String tenantId, TenantRole role) => TenantAccess(
  tenantId: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
