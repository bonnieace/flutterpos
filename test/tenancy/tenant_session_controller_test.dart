import 'package:flutter/material.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
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

  test('a refresh that confirms the session keeps its epoch', () {
    // **The change that makes refreshing safe to do often.** Every refresh went
    // through `open` until 2026-09-15, and `open` always advances the epoch - so
    // a re-read that returned exactly what the session already held still told
    // every guard on screen that its value was stale and every form mid-submit
    // that its own result no longer counted. Nothing can refresh on a schedule
    // while that is true.
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    final before = controller.session!;
    var notifications = 0;
    controller.addListener(() => notifications++);

    final moved = controller.refresh(
      uid: 'user-a',
      membership: _membership('tenant-a'),
    );

    expect(moved, isFalse);
    expect(controller.session, same(before));
    expect(controller.session!.epoch, before.epoch);
    expect(notifications, 0);
  });

  test('a refresh that changes the access decision advances the epoch', () {
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    final before = controller.session!;

    // Demoted by somebody else, which is the whole case this exists to notice.
    final moved = controller.refresh(
      uid: 'user-a',
      membership: _membership('tenant-a', role: TenantRole.cashier),
    );

    expect(moved, isTrue);
    expect(controller.session!.epoch, greaterThan(before.epoch));
    expect(controller.session!.role, TenantRole.cashier);
  });

  test('a renamed business reaches the screen without disturbing the epoch', () {
    // The reason the comparison is `TenantAccess` and not `TenantMembership`:
    // a business that renamed itself has not changed what anybody may do, and
    // hanging the epoch on `updatedAt` would churn it on every unrelated edit.
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    final before = controller.session!;
    var notifications = 0;
    controller.addListener(() => notifications++);

    final moved = controller.refresh(
      uid: 'user-a',
      membership: _membership('tenant-a', tenantName: 'New Name'),
    );

    expect(moved, isFalse);
    expect(controller.session!.epoch, before.epoch);
    expect(controller.membership!.tenantName, 'New Name');
    expect(notifications, 1);
  });

  test('a refresh for another identity opens a new session', () {
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    final before = controller.session!;

    final moved = controller.refresh(
      uid: 'user-b',
      membership: _membership('tenant-a'),
    );

    expect(moved, isTrue);
    expect(controller.session!.uid, 'user-b');
    expect(controller.session!.epoch, greaterThan(before.epoch));
  });

  test('a refusal is relayed to whoever owns bootstrapping', () {
    // The controller cannot fetch anything; it holds the handle every guarded
    // surface already has, so a screen the server refused has somewhere to say
    // so without a callback threaded through every screen that might need one.
    final controller = TenantSessionController();
    var asked = 0;
    controller.onRevalidationRequested = () => asked++;

    controller.requestRevalidation();

    expect(asked, 1);
  });

  test('a refusal with nobody listening is not an error', () {
    // Every widget test builds a controller with no shell above it.
    expect(TenantSessionController().requestRevalidation, returnsNormally);
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
  TenantRole role = TenantRole.admin,
  String? tenantName,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantName ?? tenantId,
  tenantSlug: tenantId,
  role: role,
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
