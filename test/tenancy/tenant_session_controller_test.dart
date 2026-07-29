import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opening and clearing sessions advances epochs', () {
    final controller = TenantSessionController();
    final first = _membership('tenant-a');
    final second = _membership('tenant-b');

    controller.open(uid: 'user-a', membership: first);
    final firstEpoch = controller.requireSession().epoch;
    expect(controller.ownsEpoch(firstEpoch), isTrue);

    controller.open(uid: 'user-a', membership: second);
    expect(controller.requireSession().tenantId, 'tenant-b');
    expect(controller.ownsEpoch(firstEpoch), isFalse);
    final secondEpoch = controller.requireSession().epoch;

    controller.clear();
    expect(controller.hasSession, isFalse);
    expect(controller.ownsEpoch(secondEpoch), isFalse);
    expect(controller.requireSession, throwsStateError);
  });

  test('role checks are enforced at the session boundary', () {
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));

    expect(
      controller.requireSession(allowedRoles: const [TenantRole.admin]).role,
      TenantRole.admin,
    );
    expect(
      () => controller.requireSession(allowedRoles: const [TenantRole.cashier]),
      throwsStateError,
    );
  });

  test('failed tenant switch retains the current authorized session', () {
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    final original = controller.requireSession();

    expect(
      () => controller.open(
        uid: 'user-a',
        membership: _membership(
          'tenant-b',
          membershipStatus: MembershipStatus.inactive,
          canAccess: false,
        ),
      ),
      throwsStateError,
    );
    expect(controller.requireSession(), original);
  });

  testWidgets('scope exposes the shared controller', (tester) async {
    final controller = TenantSessionController();
    TenantSessionController? watched;
    TenantSessionController? read;

    await tester.pumpWidget(
      TenantSessionScope(
        controller: controller,
        child: Builder(
          builder: (context) {
            watched = TenantSessionScope.of(context);
            read = TenantSessionScope.read(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(watched, same(controller));
    expect(read, same(controller));
  });
}

TenantMembership _membership(
  String tenantId, {
  MembershipStatus membershipStatus = MembershipStatus.active,
  bool canAccess = true,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: TenantRole.admin,
  membershipStatus: membershipStatus,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: canAccess,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
