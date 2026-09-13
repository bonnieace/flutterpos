import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the home menu puts three things, decided 2026-09-13.
///
/// **All three are menu-layer decisions and nothing else.** Every panel behind
/// them keeps its own guard and its own role list, so what anybody may *do* is
/// unchanged; these pin only what each role is offered, which is the part a
/// refactor of the menu can silently get wrong.
void main() {
  group('Printer keeps a tile of its own', () {
    testWidgets('an owner and an admin are offered it beside Settings', (
      tester,
    ) async {
      for (final role in <TenantRole>[TenantRole.owner, TenantRole.admin]) {
        await _pumpLanding(tester, role: role);
        expect(
          find.byKey(const ValueKey('printer-settings')),
          findsOneWidget,
          reason: role.name,
        );
        await _tearDown(tester);
      }
    });

    testWidgets('a manager and a cashier are not offered it', (tester) async {
      for (final role in <TenantRole>[TenantRole.manager, TenantRole.cashier]) {
        await _pumpLanding(tester, role: role);
        expect(
          find.byKey(const ValueKey('printer-settings')),
          findsNothing,
          reason: role.name,
        );
        await _tearDown(tester);
      }
    });

    testWidgets('it opens the one Settings screen at its printer tab', (
      tester,
    ) async {
      // **A second door onto one room.** If this ever opened a second printer
      // panel there would be two guards and two role lists to keep in step.
      await _pumpLanding(tester, role: TenantRole.owner);
      await tester.tap(find.byKey(const ValueKey('printer-settings')));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOne);
      expect(_openedTabKey, 'printer');
    });

    testWidgets('Settings itself still opens on its first tab', (tester) async {
      await _pumpLanding(tester, role: TenantRole.owner);
      await tester.tap(find.byKey(const ValueKey('settings')));
      await tester.pumpAndSettle();

      expect(_openedTabKey, isNull);
    });
  });

  group('Count stock is offered where a count cannot be started otherwise', () {
    testWidgets('a cashier keeps the tile, because it is their only door', (
      tester,
    ) async {
      // The feature's whole premise: a cashier counts. They reach no *Stock
      // counts* screen - its lines carry the expected figure a count is blind
      // to - so removing this tile from them would remove counting from them.
      await _pumpLanding(tester, role: TenantRole.cashier);

      expect(find.byKey(const ValueKey('stock-take')), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-take-review')), findsNothing);
    });

    testWidgets('anybody who can open Stock counts starts a count from there', (
      tester,
    ) async {
      for (final role in <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ]) {
        await _pumpLanding(tester, role: role);
        expect(
          find.byKey(const ValueKey('stock-take')),
          findsNothing,
          reason: '${role.name} starts one from the Stock counts screen',
        );
        expect(
          find.byKey(const ValueKey('stock-take-review')),
          findsOneWidget,
          reason: role.name,
        );
        await _tearDown(tester);
      }
    });
  });
}

/// Which tab the settings route was asked to open at, set by the fake route.
String? _openedTabKey;

Future<void> _tearDown(WidgetTester tester) async {
  _openedTabKey = null;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

/// The production landing route, wired the way the composition root wires it:
/// tenancy owns the menu and each domain decides its own roles.
Future<void> _pumpLanding(
  WidgetTester tester, {
  required TenantRole role,
}) async {
  _openedTabKey = null;
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: TenantSessionController()..open(
          uid: 'user-1',
          membership: _membership(role),
        ),
        child: TenantSafeLandingScreen(
          membership: _membership(role),
          reader: const _Reader(),
          onSignOut: () async {},
          settingsRoute: (reader, initialTabKey) {
            _openedTabKey = initialTabKey;
            return const _Settings();
          },
          settingsRoles: TenantCheckoutConfigurationPublisher.allowedRoles,
          printerSettingsRoles:
              TenantPrinterConfigurationPublisher.allowedRoles,
          stockTakeRoute: (reader) => const _Elsewhere(),
          stockTakeRoles: TenantStockTakeGateway.allowedRoles,
          stockTakeReviewRoute: (reader) => const _Elsewhere(),
          stockTakeReviewRoles: TenantStockTakeReviewRepository.allowedRoles,
        ),
      ),
    ),
  );
  await tester.pump();
}

TenantMembership _membership(TenantRole role) => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: 'tenant-a',
  tenantSlug: 'tenant-a',
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

/// Stands in for the settings screen: this group is about which tile opens what
/// and at which tab, not about the panels inside.
final class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Settings')));
}

final class _Elsewhere extends StatelessWidget {
  const _Elsewhere();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

final class _Reader implements TenantDataReader {
  const _Reader();

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
