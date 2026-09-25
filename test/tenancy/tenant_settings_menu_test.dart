import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/production/production.dart';
import 'package:flutter_application_1/suppliers/suppliers.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the home menu puts four things, decided 2026-09-13 and 2026-09-24.
///
/// **All three are menu-layer decisions and nothing else.** Every panel behind
/// them keeps its own guard and its own role list, so what anybody may *do* is
/// unchanged; these pin only what each role is offered, which is the part a
/// refactor of the menu can silently get wrong.
void main() {
  group('the printer lives inside Settings', () {
    testWidgets('no role is offered a Printer tile of its own', (tester) async {
      // **Removed 2026-09-24, at the developer's direction.** The tile opened
      // this same Settings screen at its printer tab, to exactly the roles
      // Settings is offered to, so nobody loses the printer by losing it.
      for (final role in TenantRole.values) {
        await _pumpLanding(tester, role: role);
        expect(
          find.byKey(const ValueKey('printer-settings')),
          findsNothing,
          reason: role.name,
        );
        await _tearDown(tester);
      }
    });

    testWidgets('Settings itself still opens on its first tab', (tester) async {
      await _pumpLanding(tester, role: TenantRole.owner);
      await tester.tap(find.byKey(const ValueKey('settings')));
      await tester.pumpAndSettle();

      expect(_openedTabKey, isNull);
    });
  });

  group('Suppliers and Production are offered to the roles that receive stock', () {
    testWidgets('an owner, an admin and a manager are offered both', (
      tester,
    ) async {
      for (final role in <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ]) {
        await _pumpLanding(tester, role: role);
        for (final tile in <String>['suppliers', 'production']) {
          expect(
            find.byKey(ValueKey(tile)),
            findsOneWidget,
            reason: '${role.name}: $tile',
          );
        }
        await _tearDown(tester);
      }
    });

    testWidgets('a cashier is offered neither', (tester) async {
      await _pumpLanding(tester, role: TenantRole.cashier);

      expect(find.byKey(const ValueKey('suppliers')), findsNothing);
      expect(find.byKey(const ValueKey('production')), findsNothing);
    });

    testWidgets('Production is offered before a single product is made here', (
      tester,
    ) async {
      // Decided 2026-09-24: shown by role, like every other tile, and never
      // by what the business happens to hold.
      await _pumpLanding(tester, role: TenantRole.manager);

      expect(find.byKey(const ValueKey('production')), findsOneWidget);
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
          suppliersRoute: (reader) => const _Elsewhere(),
          suppliersRoles: TenantSupplierRepository.allowedRoles,
          productionRoute: (reader) => const _Elsewhere(),
          productionRoles: TenantProductionRepository.allowedRoles,
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
