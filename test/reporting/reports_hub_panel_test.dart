import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/home_navigation.dart';
import 'package:flutter_application_1/ui/scaffold.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the reports hub', () {
    testWidgets('offers every report this role may read', (tester) async {
      await _pump(
        tester,
        _controller(TenantRole.owner),
        dailySummaryRoute: () => const _Destination('daily'),
        dailySummaryRoles: const <TenantRole>[
          TenantRole.owner,
          TenantRole.admin,
          TenantRole.manager,
        ],
        weeklyReportRoute: () => const _Destination('weekly'),
        weeklyReportRoles: const <TenantRole>[
          TenantRole.owner,
          TenantRole.admin,
          TenantRole.manager,
        ],
      );

      expect(find.text('Daily summary'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
    });

    testWidgets('a report this role may not read is not drawn at all', (
      tester,
    ) async {
      // Not disabled and not greyed: the home's own destination list omits a
      // row a role cannot use, and a hub that showed a card leading to a
      // refusal would be advertising a door that is locked.
      await _pump(
        tester,
        _controller(TenantRole.manager),
        dailySummaryRoute: () => const _Destination('daily'),
        dailySummaryRoles: const <TenantRole>[
          TenantRole.owner,
          TenantRole.admin,
          TenantRole.manager,
        ],
        weeklyReportRoute: () => const _Destination('weekly'),
        // Owner and administrator only, which a manager is neither of.
        weeklyReportRoles: const <TenantRole>[
          TenantRole.owner,
          TenantRole.admin,
        ],
      );

      expect(find.text('Daily summary'), findsOneWidget);
      expect(find.text('This week'), findsNothing);
    });

    testWidgets('a report with no builder is not drawn either', (tester) async {
      // The composition root decides which reports exist at all. A card for a
      // route nothing built would be an entry point to nowhere.
      await _pump(
        tester,
        _controller(TenantRole.owner),
        dailySummaryRoute: () => const _Destination('daily'),
        dailySummaryRoles: const <TenantRole>[TenantRole.owner],
        monthlyReportRoles: const <TenantRole>[TenantRole.owner],
      );

      expect(find.text('Daily summary'), findsOneWidget);
      expect(find.text('This month'), findsNothing);
    });

    testWidgets('a role with no reports at all is told so', (tester) async {
      await _pump(
        tester,
        _controller(TenantRole.cashier),
        dailySummaryRoute: () => const _Destination('daily'),
        dailySummaryRoles: const <TenantRole>[TenantRole.owner],
      );

      expect(find.byKey(const ValueKey('reports-hub-empty')), findsOneWidget);
      expect(find.byType(HomeModuleGrid), findsNothing);
    });

    testWidgets('a card opens its report under the same session', (
      tester,
    ) async {
      // The pushed route is a new subtree under the navigator rather than under
      // the hub, so the scope has to be re-established around it. Without that
      // the report would find no session above it and throw on its first read.
      final controller = _controller(TenantRole.owner);
      await _pump(
        tester,
        controller,
        dailySummaryRoute: () => const _Destination('daily'),
        dailySummaryRoles: const <TenantRole>[TenantRole.owner],
      );

      await tester.tap(find.text('Daily summary'));
      await tester.pumpAndSettle();

      expect(find.text('destination: daily'), findsOneWidget);
      expect(
        TenantSessionScope.of(
          tester.element(find.text('destination: daily')),
        ),
        same(controller),
      );
    });

    testWidgets('the hub empties when the session goes', (tester) async {
      // A business switch clears the session. The hub depends on the scope's
      // notifier, so it rebuilds rather than leaving cards that would open one
      // business's figures from another's session.
      final controller = _controller(TenantRole.owner);
      await _pump(
        tester,
        controller,
        dailySummaryRoute: () => const _Destination('daily'),
        dailySummaryRoles: const <TenantRole>[TenantRole.owner],
      );
      expect(find.text('Daily summary'), findsOneWidget);

      controller.clear();
      await tester.pump();

      expect(find.text('Daily summary'), findsNothing);
      expect(find.byKey(const ValueKey('reports-hub-empty')), findsOneWidget);
    });

    testWidgets('the title appears once, on the header', (tester) async {
      await _pump(
        tester,
        _controller(TenantRole.owner),
        dailySummaryRoute: () => const _Destination('daily'),
        dailySummaryRoles: const <TenantRole>[TenantRole.owner],
      );

      expect(
        tester.widget<AppScaffold>(find.byType(AppScaffold)).title,
        'Reports',
      );
    });
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller, {
  TenantReportRouteBuilder? dailySummaryRoute,
  List<TenantRole> dailySummaryRoles = const <TenantRole>[],
  TenantReportRouteBuilder? weeklyReportRoute,
  List<TenantRole> weeklyReportRoles = const <TenantRole>[],
  TenantReportRouteBuilder? monthlyReportRoute,
  List<TenantRole> monthlyReportRoles = const <TenantRole>[],
  TenantReportRouteBuilder? salesTotalsRoute,
  List<TenantRole> salesTotalsRoles = const <TenantRole>[],
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantReportsHubScreen(
          dailySummaryRoute: dailySummaryRoute,
          dailySummaryRoles: dailySummaryRoles,
          weeklyReportRoute: weeklyReportRoute,
          weeklyReportRoles: weeklyReportRoles,
          monthlyReportRoute: monthlyReportRoute,
          monthlyReportRoles: monthlyReportRoles,
          salesTotalsRoute: salesTotalsRoute,
          salesTotalsRoles: salesTotalsRoles,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A stand-in for a report, so the hub is tested without any of them.
final class _Destination extends StatelessWidget {
  const _Destination(this.name);

  final String name;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('destination: $name')));
}

TenantSessionController _controller(TenantRole role) =>
    TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a', role));

TenantMembership _membership(String tenantId, TenantRole role) =>
    TenantMembership(
      tenantId: tenantId,
      tenantName: tenantId,
      tenantSlug: tenantId,
      role: role,
      membershipStatus: MembershipStatus.active,
      tenantStatus: TenantStatus.active,
      isOwner: role == TenantRole.owner,
      mirrorVersion: 1,
      createdAt: DateTime.utc(2026, 7, 31),
      updatedAt: DateTime.utc(2026, 7, 31),
      serverCanAccess: true,
      canonicalTenantExists: true,
      canonicalMembershipExists: true,
    );
