import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/scaffold.dart';
import 'package:flutter_test/flutter_test.dart';

/// A typical phone in logical pixels. The landing route's fold is a property of
/// the space it is given, so these tests state the space.
const Size _phone = Size(411, 731);

void main() {
  testWidgets('a landing screen that fits says nothing about scrolling', (
    tester,
  ) async {
    // The centring this route has always had is deliberate and is kept: one
    // panel in the middle of a mostly-empty screen is what it is for. A
    // permanent "there is more" on a screen with nothing more would be worse
    // than the silence it replaced.
    await _pumpLanding(tester, panelHeight: 120);

    expect(find.byKey(const ValueKey('landing-more-below')), findsNothing);
  });

  testWidgets('a landing screen taller than the fold says there is more', (
    tester,
  ) async {
    // The reported defect: the content below the fold was reachable only by
    // scrolling, and nothing on screen said so. What a reader saw was a line of
    // text cut through mid-glyph at the bottom edge.
    await _pumpLanding(tester, panelHeight: 900);

    expect(find.byKey(const ValueKey('landing-more-below')), findsOne);
  });

  testWidgets('the fade goes once there is nothing left below', (tester) async {
    await _pumpLanding(tester, panelHeight: 900);
    expect(find.byKey(const ValueKey('landing-more-below')), findsOne);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -2000),
    );
    await tester.pump();
    await tester.pump();

    // It reports what is below the fold, not that the screen is a long one.
    expect(find.byKey(const ValueKey('landing-more-below')), findsNothing);
  });

  testWidgets('the fade never intercepts the drag it is drawn over', (
    tester,
  ) async {
    // It is decoration over the bottom edge of a scrollable, which is exactly
    // where a thumb lands. Swallowing that drag would make the content it points
    // at harder to reach than before it existed.
    await _pumpLanding(tester, panelHeight: 900);

    // Asserted by dragging from the fade itself rather than by looking for an
    // `IgnorePointer` above it: Material puts several of its own in this tree,
    // so the structure proves nothing and the behaviour proves everything.
    final panel = find.byKey(const ValueKey('landing-test-panel'));
    final before = tester.getTopLeft(panel).dy;

    await tester.dragFrom(
      tester.getCenter(find.byKey(const ValueKey('landing-more-below'))),
      const Offset(0, -200),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.getTopLeft(panel).dy, lessThan(before));
  });

  testWidgets('the routes this screen offers scroll with it', (tester) async {
    // They used to be pinned below the scrollable, and on a phone that was
    // measured rather than argued about: an owner is offered eight of them, they
    // do not pair up at 411 logical pixels wide, and the row took 288 of the 631
    // the body has - leaving a 339-pixel viewport with "Open shift" below the
    // fold. Nothing was pinned in their place.
    await _pumpLanding(tester, panelHeight: 900);

    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byKey(const ValueKey('make-default-tenant')),
      ),
      findsOne,
    );
  });

  testWidgets('the scrollable is given the whole body', (tester) async {
    // The measurement, as an assertion. 731 high, less a 56-pixel app bar,
    // leaves 675 of body.
    //
    // **§11 step 5b spends 72 of it on the page header and this test is where
    // that figure lands.** `AppScaffold` pads 20 above a `PageHeader` and then
    // a section gap below it, which `PLAN.md` recorded as "the frame costs a
    // route 72 logical pixels of body" when step 5a built it - measured on
    // every other route and, until this step, never on this one. 675 less 72
    // less the route's own 24-pixel bottom padding is 579, and all of it is the
    // scrollable's.
    await _pumpLanding(tester, panelHeight: 900);

    expect(tester.getSize(find.byType(SingleChildScrollView)).height, 579);
  });

  testWidgets('the title leaves the toolbar and the action stays in it', (
    tester,
  ) async {
    // Recorded because a previous handover in PLAN.md claimed the action was
    // clipped and it never was. Every rendering made while looking at this route
    // showed "Sign o" with the rest of the word missing - which is the **debug
    // banner** painted over the top-right corner, not the app bar clipping
    // anything. The banner is paint, so it does not appear in these
    // measurements and does not appear in a release build either.
    //
    // **§11 step 5b removed the collision this test was written about.** A
    // title and an action shared the toolbar, and a long business name was the
    // case that would have broken it. The title is `PageHeader`'s now - §7's
    // "title appears once", and §2.2's `display` role does not fit a 56-high
    // toolbar at all - so what is asserted is that it left, and that the one
    // thing still in the toolbar is inside it.
    for (final name in <String>[
      'Chilltent Lounge',
      'Chilltent Lounge Nairobi Westlands Branch',
    ]) {
      await _pumpLanding(tester, panelHeight: 120, tenantName: name);

      final bar = tester.getRect(find.byType(AppBar));
      final label = tester.getRect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Sign out'),
        ),
      );

      expect(label.right, lessThanOrEqualTo(bar.right), reason: name);
      expect(label.left, greaterThanOrEqualTo(bar.left), reason: name);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text(name)),
        findsNothing,
        reason: name,
      );
      expect(
        find.descendant(of: find.byType(PageHeader), matching: find.text(name)),
        findsOne,
        reason: name,
      );
    }
  });

  testWidgets('a screen that grows past the fold starts saying so', (
    tester,
  ) async {
    // The counts on this route are read again on every sync signal, so its
    // content changes height without anybody scrolling. The metrics have to be
    // observed rather than measured once when the route opens.
    await _pumpLanding(tester, panelHeight: 120);
    expect(find.byKey(const ValueKey('landing-more-below')), findsNothing);

    await _pumpLanding(tester, panelHeight: 900);
    expect(find.byKey(const ValueKey('landing-more-below')), findsOne);
  });

  testWidgets('catalog management is offered only when it was injected', (
    tester,
  ) async {
    // The one surface that can put a product in the catalog. Like the till, it
    // must never appear merely because the shell reached the landing route.
    // Asserted for an owner, so it is the missing injection that hides it and
    // not the role.
    await _pumpLanding(tester, panelHeight: 120, role: TenantRole.owner);

    expect(find.byKey(const ValueKey('manage-catalog')), findsNothing);
  });

  testWidgets('catalog management opens under the same session scope', (
    tester,
  ) async {
    await _pumpLanding(
      tester,
      panelHeight: 120,
      role: TenantRole.owner,
      catalogManagementRoute: (_) => const Scaffold(body: Text('Catalog open')),
      catalogManagementRoles: const <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ],
    );

    // **The destination is a card now, and a card is taller than the pill it
    // replaced**, so on a 120-pixel panel this one sits below the fold where the
    // pill did not. Scrolling to it is what a person does; the assertion is
    // still that opening it keeps the session scope.
    final destination = find.byKey(const ValueKey('manage-catalog'));
    await tester.ensureVisible(destination);
    await tester.pumpAndSettle();
    await tester.tap(destination);
    await tester.pumpAndSettle();

    expect(find.text('Catalog open'), findsOne);
  });

  testWidgets('a cashier is not offered catalog management at all', (
    tester,
  ) async {
    // The route guards itself, but a control a cashier can never use should not
    // be on the screen a cashier lands on.
    await _pumpLanding(
      tester,
      panelHeight: 120,
      role: TenantRole.cashier,
      catalogManagementRoute: (_) => const Scaffold(body: Text('Catalog open')),
      catalogManagementRoles: const <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ],
    );

    expect(find.byKey(const ValueKey('manage-catalog')), findsNothing);
  });
}

Future<void> _pumpLanding(
  WidgetTester tester, {
  required double panelHeight,
  String tenantName = 'Chilltent Lounge',
  TenantRole role = TenantRole.cashier,
  Widget Function(TenantDataReader reader)? catalogManagementRoute,
  List<TenantRole> catalogManagementRoles = const <TenantRole>[],
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final membership = _membership(tenantName: tenantName, role: role);
  final controller = TenantSessionController()
    ..open(uid: 'user-a', membership: membership);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantSafeLandingScreen(
          membership: membership,
          reader: _EmptyReader(),
          onSignOut: () async {},
          catalogManagementRoute: catalogManagementRoute,
          catalogManagementRoles: catalogManagementRoles,
          // The slot the shift panel occupies on a real device. What the fold
          // depends on is the height of what is in it.
          shiftPanel: SizedBox(
            key: const ValueKey('landing-test-panel'),
            height: panelHeight,
            child: const Card(child: Center(child: Text('Shift'))),
          ),
        ),
      ),
    ),
  );
  // The first frame lays out and reports its metrics; the second renders the
  // answer, because the observation is deferred out of layout.
  await tester.pump();
  await tester.pump();
}

final class _EmptyReader implements TenantDataReader {
  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}

TenantMembership _membership({
  String tenantName = 'Chilltent Lounge',
  TenantRole role = TenantRole.cashier,
}) => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: tenantName,
  tenantSlug: 'chilltent-lounge',
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
