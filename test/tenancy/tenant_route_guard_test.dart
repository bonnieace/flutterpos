import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('missing session fails closed without loading', (tester) async {
    final controller = TenantSessionController();
    var loadCalls = 0;

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          load: (_) async {
            loadCalls++;
            return 'unexpected';
          },
          builder: (_, _, value) => Text(value),
        ),
      ),
    );

    expect(find.text('Tenant access unavailable.'), findsOneWidget);
    expect(loadCalls, 0);
  });

  testWidgets('wrong role fails closed without loading', (tester) async {
    final controller = TenantSessionController()
      ..open(
        uid: 'user-a',
        membership: _membership('tenant-a', role: TenantRole.cashier),
      );
    var loadCalls = 0;

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          allowedRoles: const [TenantRole.admin],
          load: (_) async {
            loadCalls++;
            return 'unexpected';
          },
          builder: (_, _, value) => Text(value),
        ),
      ),
    );

    expect(find.text('Tenant access unavailable.'), findsOneWidget);
    expect(loadCalls, 0);
  });

  testWidgets('tenant switch rejects a stale async completion', (tester) async {
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
    final loads = <String, Completer<String>>{};

    await tester.pumpWidget(
      _guardedApp(
        controller: controller,
        guard: TenantRouteGuard<String>(
          load: (session) {
            final completer = Completer<String>();
            loads[session.tenantId] = completer;
            return completer.future;
          },
          builder: (_, session, value) => Text('${session.tenantId}:$value'),
        ),
      ),
    );

    expect(loads.keys, contains('tenant-a'));
    controller.open(uid: 'user-a', membership: _membership('tenant-b'));
    await tester.pump();
    expect(loads.keys, contains('tenant-b'));

    loads['tenant-a']!.complete('stale');
    await tester.pump();
    expect(find.textContaining('stale'), findsNothing);

    loads['tenant-b']!.complete('current');
    await tester.pump();
    expect(find.text('tenant-b:current'), findsOneWidget);
  });
}

Widget _guardedApp({
  required TenantSessionController controller,
  required Widget guard,
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(body: guard),
  ),
);

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.admin,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
