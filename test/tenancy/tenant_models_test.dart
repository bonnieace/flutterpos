import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lowercase wire enums', () {
    test('round-trip every frozen role and status', () {
      for (final role in TenantRole.values) {
        expect(TenantRole.fromJson(role.toJson()), role);
        expect(role.toJson(), role.name);
      }
      for (final status in MembershipStatus.values) {
        expect(MembershipStatus.fromJson(status.toJson()), status);
        expect(status.toJson(), status.name);
      }
      for (final status in TenantStatus.values) {
        expect(TenantStatus.fromJson(status.toJson()), status);
        expect(status.toJson(), status.name);
      }
    });

    test('reject uppercase, unknown, and non-string wire values', () {
      expect(() => TenantRole.fromJson('Owner'), throwsFormatException);
      expect(() => TenantRole.fromJson('super_admin'), throwsFormatException);
      expect(() => TenantRole.fromJson(1), throwsFormatException);
      expect(
        () => MembershipStatus.fromJson('disabled'),
        throwsFormatException,
      );
      expect(() => MembershipStatus.fromJson(null), throwsFormatException);
      expect(() => TenantStatus.fromJson('ACTIVE'), throwsFormatException);
      expect(() => TenantStatus.fromJson(true), throwsFormatException);
    });
  });

  group('TenantMembership strict decoding', () {
    test('decodes the listMyTenants contract without Firebase types', () {
      final membership = TenantMembership.fromJson(_validMembershipJson());

      expect(membership.tenantId, 'tenant-a');
      expect(membership.role, TenantRole.admin);
      expect(membership.membershipStatus, MembershipStatus.active);
      expect(membership.tenantStatus, TenantStatus.active);
      expect(membership.createdAt, DateTime.utc(2026, 7, 1));
      expect(membership.joinedAt, isNull);
      expect(membership.updatedAt, DateTime.utc(2026, 7, 29, 12, 30));
      expect(membership.canAccess(), isTrue);
      expect(TenantMembership.fromJson(membership.toJson()), membership);
    });

    test('allows nullable server timestamps', () {
      final json = _validMembershipJson()
        ..['createdAt'] = null
        ..['joinedAt'] = null
        ..['updatedAt'] = null;

      final membership = TenantMembership.fromJson(json);

      expect(membership.createdAt, isNull);
      expect(membership.joinedAt, isNull);
      expect(membership.updatedAt, isNull);
    });

    test('rejects wrong field types and malformed ISO timestamps', () {
      final wrongFlag = _validMembershipJson()..['canAccess'] = 1;
      final wrongVersion = _validMembershipJson()..['mirrorVersion'] = 1.0;
      final wrongDate = _validMembershipJson()..['updatedAt'] = 'yesterday';
      final wrongOptional = _validMembershipJson()
        ..['invitationStatus'] = false;

      expect(() => TenantMembership.fromJson(wrongFlag), throwsFormatException);
      expect(
        () => TenantMembership.fromJson(wrongVersion),
        throwsFormatException,
      );
      expect(() => TenantMembership.fromJson(wrongDate), throwsFormatException);
      expect(
        () => TenantMembership.fromJson(wrongOptional),
        throwsFormatException,
      );
    });

    test('shows inconsistent owner state but fails closed for access', () {
      final ownerFlagOnAdmin = _validMembershipJson()..['isOwner'] = true;
      final ownerRoleWithoutFlag = _validMembershipJson()
        ..['role'] = 'owner'
        ..['isOwner'] = false;

      final first = TenantMembership.fromJson(ownerFlagOnAdmin);
      final second = TenantMembership.fromJson(ownerRoleWithoutFlag);

      expect(first.ownerInvariantValid, isFalse);
      expect(second.ownerInvariantValid, isFalse);
      expect(first.canAccess(), isFalse);
      expect(second.canAccess(), isFalse);
      expect(second.isAdministrativePrincipal, isFalse);
    });

    test('rejects missing canonical evidence instead of defaulting it', () {
      final json = _validMembershipJson()..remove('canonicalMembershipExists');

      expect(() => TenantMembership.fromJson(json), throwsFormatException);
    });
  });

  group('TenantAccess', () {
    test('canAccess requires every canonical active condition', () {
      final baseline = _activeAccess();
      expect(baseline.canAccess(), isTrue);

      final denied = <TenantAccess>[
        _activeAccess(serverCanAccess: false),
        _activeAccess(canonicalTenantExists: false),
        _activeAccess(canonicalMembershipExists: false),
        _activeAccess(membershipStatus: MembershipStatus.pending),
        _activeAccess(membershipStatus: MembershipStatus.inactive),
        _activeAccess(tenantStatus: TenantStatus.suspended),
        _activeAccess(tenantStatus: TenantStatus.archived),
      ];

      for (final access in denied) {
        expect(access.canAccess(), isFalse);
      }
    });

    test('owners satisfy admin permissions and count as administrators', () {
      final owner = _activeAccess(role: TenantRole.owner);
      final admin = _activeAccess(role: TenantRole.admin);
      final manager = _activeAccess(role: TenantRole.manager);

      expect(TenantRole.owner.isAdministrator, isTrue);
      expect(TenantRole.admin.isAdministrator, isTrue);
      expect(TenantRole.manager.isAdministrator, isFalse);
      expect(owner.canAccess(allowedRoles: const [TenantRole.admin]), isTrue);
      expect(admin.canAccess(allowedRoles: const [TenantRole.owner]), isFalse);
      expect(
        manager.canAccess(allowedRoles: const [TenantRole.admin]),
        isFalse,
      );
      expect(owner.isAdministrativePrincipal, isTrue);
      expect(admin.isAdministrativePrincipal, isTrue);
      expect(manager.isAdministrativePrincipal, isFalse);
    });

    test('an empty allowed-role set denies access', () {
      expect(_activeAccess().canAccess(allowedRoles: const []), isFalse);
    });

    test('strict decoder rejects an invalid tenant identifier', () {
      final json = _activeAccess().toJson()..['tenantId'] = 'escape/path';

      expect(() => TenantAccess.fromJson(json), throwsFormatException);
    });
  });
}

Map<String, Object?> _validMembershipJson() => <String, Object?>{
  'tenantId': 'tenant-a',
  'tenantName': 'Acme Shop',
  'tenantSlug': 'acme-shop',
  'role': 'admin',
  'membershipStatus': 'active',
  'tenantStatus': 'active',
  'invitationStatus': null,
  'isOwner': false,
  'mirrorVersion': 3,
  'createdAt': '2026-07-01T00:00:00.000Z',
  'joinedAt': null,
  'updatedAt': '2026-07-29T12:30:00.000Z',
  'canAccess': true,
  'canonicalTenantExists': true,
  'canonicalMembershipExists': true,
};

TenantAccess _activeAccess({
  TenantRole role = TenantRole.cashier,
  MembershipStatus membershipStatus = MembershipStatus.active,
  TenantStatus tenantStatus = TenantStatus.active,
  bool serverCanAccess = true,
  bool canonicalTenantExists = true,
  bool canonicalMembershipExists = true,
}) => TenantAccess(
  tenantId: 'tenant-a',
  role: role,
  membershipStatus: membershipStatus,
  tenantStatus: tenantStatus,
  serverCanAccess: serverCanAccess,
  canonicalTenantExists: canonicalTenantExists,
  canonicalMembershipExists: canonicalMembershipExists,
);
