import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
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
}

Future<void> _pumpLanding(
  WidgetTester tester, {
  required double panelHeight,
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = TenantSessionController()
    ..open(uid: 'user-a', membership: _membership());
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantSafeLandingScreen(
          membership: _membership(),
          reader: _EmptyReader(),
          onSignOut: () async {},
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

TenantMembership _membership() => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: 'Chilltent Lounge',
  tenantSlug: 'chilltent-lounge',
  role: TenantRole.cashier,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
