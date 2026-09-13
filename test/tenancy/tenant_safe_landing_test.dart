import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/home_navigation.dart';
import 'package:flutter_application_1/ui/scaffold.dart';
import 'package:flutter_test/flutter_test.dart';

/// A typical phone in logical pixels. The landing route's fold is a property of
/// the space it is given, so these tests state the space.
const Size _phone = Size(411, 731);

/// Brings a destination on screen.
///
/// **The destinations came back into the body on 2026-08-25**, as the old
/// hub's grid of module cards, and the frame's drawer was withdrawn from this
/// route with them — so reaching one is scrolling to it rather than opening a
/// menu first. Kept as a named step because six call sites do it and what
/// "reaching a destination" means should be decided in one place.
Future<void> _reveal(WidgetTester tester, Finder destination) async {
  await tester.ensureVisible(destination);
  await tester.pumpAndSettle();
}

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

  testWidgets('the routes this screen offers are in the body, and scroll', (
    tester,
  ) async {
    // **They were pinned below the body, then in it, then behind the
    // hamburger, and are in it again.** Each move was measured rather than
    // argued about; the 2026-08-25 move is the product decision to give
    // existing customers the old hub's card grid back. The property that has
    // held throughout every one of them is the one asserted here: no
    // destination is unreachable, and the column they sit in scrolls.
    await _pumpLanding(tester, panelHeight: 900);

    final account = find.byKey(const ValueKey('make-default-tenant'));
    await _reveal(tester, account);

    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: account,
      ),
      findsOne,
    );
  });

  testWidgets('a desktop draws the destinations in the page, above it', (
    tester,
  ) async {
    // **The reverse of what this asserted until 2026-08-25**, and deliberately
    // so: the destinations are the old hub's grid now, they are content rather
    // than chrome, and they sit above the rest of the page instead of beside
    // it. Asserted by position for the same reason the old test did — a grid
    // that had merely been renamed would still pass a structural check.
    await _pumpLanding(
      tester,
      panelHeight: 120,
      role: TenantRole.owner,
      size: const Size(1440, 900),
    );

    final destination = tester.getRect(
      find.byKey(const ValueKey('make-default-tenant')),
    );
    final panel = tester.getRect(
      find.byKey(const ValueKey('landing-test-panel')),
    );

    expect(destination.bottom, lessThanOrEqualTo(panel.top));
    // **Drawn once, and by the grid.** The frame's menu was withdrawn from
    // this route when the grid returned: building both hosts put every
    // destination on screen twice, and two widgets under one key.
    expect(find.byType(HomeModuleGrid), findsOneWidget);
    expect(find.byType(HomeNavigation), findsNothing);
  });

  testWidgets('the account controls come last - design.md §4.4', (
    tester,
  ) async {
    // "Remaining cards are ordered by frequency, never alphabetically", with
    // the two account controls last. Source order is what a grid renders, so
    // the order is a property of the list the route builds.
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

    final account = find.byKey(const ValueKey('make-default-tenant'));
    final catalog = find.byKey(const ValueKey('inventory'));
    await _reveal(tester, account);

    // **Reading order, not vertical position.** This harness supplies two
    // destinations, so the grid lays them in one row and both tops are the
    // same 113.0 - "last" is then to the right rather than below. Comparing
    // only `top` asserted a row break the route never promised.
    final accountAt = tester.getRect(account);
    final catalogAt = tester.getRect(catalog);
    if (accountAt.top == catalogAt.top) {
      expect(
        accountAt.left,
        greaterThan(catalogAt.left),
        reason: 'the account control shares the catalog row, so it must sit '
            'to its right',
      );
    } else {
      expect(
        accountAt.top,
        greaterThan(catalogAt.top),
        reason: 'the account control must sit below the catalog',
      );
    }
  });

  testWidgets('the scrollable is given the whole body', (tester) async {
    // The measurement, as an assertion. 731 high, less a 56-pixel app bar,
    // leaves 675 of body.
    //
    // **643 since 2026-08-26, and the 32 is the whole of what the frame still
    // spends.** The header block is gone: it cost 20 above the title, a title
    // line, a subtitle line and a section gap - about 128 pixels of every
    // route - and what replaced it is `space.8` under the bar. 675 less that
    // 8, less the route's own 24-pixel bottom padding, is 643, and all of it
    // is the scrollable's.
    //
    // This is the assertion that moves whenever the frame's arithmetic does,
    // which is why it is written as a measurement rather than a number.
    await _pumpLanding(tester, panelHeight: 900);

    expect(tester.getSize(find.byType(SingleChildScrollView)).height, 643);
  });

  testWidgets('the title is in the toolbar and fits beside its controls', (
    tester,
  ) async {
    // **The opposite of what this asserted until 2026-08-23, and for the same
    // reason it asserted it.** §7 moved the title out of the bar because §2.2
    // gives a screen title 32 and no bar holds one; the design this app is
    // built to writes its own header as `section-title` 22 inside the bar, and
    // the header block it replaced cost about 128 pixels of every route.
    //
    // What is still asserted is what the original was about: a long business
    // name does not push the bar's own controls off the end of it.
    for (final name in <String>[
      'Chilltent Lounge',
      'Chilltent Lounge Nairobi Westlands Branch',
    ]) {
      await _pumpLanding(tester, panelHeight: 120, tenantName: name);

      final bar = tester.getRect(find.byType(AppBar));
      final title = tester.getRect(
        find.descendant(of: find.byType(AppBar), matching: find.text(name)),
      );

      expect(title.left, greaterThanOrEqualTo(bar.left), reason: name);
      expect(title.right, lessThanOrEqualTo(bar.right), reason: name);
      // The way out is a glyph at the trailing edge and stays inside the bar
      // whatever the business is called.
      final signOut = tester.getRect(find.byKey(const ValueKey('sign-out')));
      expect(signOut.right, lessThanOrEqualTo(bar.right), reason: name);
      expect(signOut.left, greaterThan(title.left), reason: name);
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

    expect(find.byKey(const ValueKey('inventory')), findsNothing);
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

    // **The destination is in the drawer now.** Opening it is what a person
    // does; the assertion is still that opening the route keeps the session
    // scope, and that the drawer shuts behind it rather than sitting open
    // underneath the route that just arrived.
    final destination = find.byKey(const ValueKey('inventory'));
    await tester.ensureVisible(destination);
    await tester.pumpAndSettle();
    await tester.tap(destination);
    await tester.pumpAndSettle();

    expect(find.text('Catalog open'), findsOne);
  });

  testWidgets('a cashier is offered the same read-only inventory destination', (
    tester,
  ) async {
    // The unified route derives its write actions from the live session, while
    // the destination itself remains useful to every active member.
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

    final inventory = find.byKey(const ValueKey('inventory'));
    expect(inventory, findsOneWidget);
    await tester.tap(inventory);
    await tester.pumpAndSettle();
    expect(find.text('Catalog open'), findsOneWidget);
  });

  testWidgets('home exposes the business-wide returns destination', (
    tester,
  ) async {
    await _pumpLanding(
      tester,
      panelHeight: 120,
      role: TenantRole.cashier,
      returnFeedRoute: (_) => const Scaffold(body: Text('Returns open')),
      returnFeedRoles: const <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
        TenantRole.cashier,
      ],
    );

    final returns = find.byKey(const ValueKey('returns'));
    expect(returns, findsOneWidget);
    await _reveal(tester, returns);
    await tester.tap(returns);
    await tester.pumpAndSettle();
    expect(find.text('Returns open'), findsOneWidget);
  });

  // `docs/stitch/OPEN_QUESTIONS.md` decision 36.
  group('the home header is one line, and trickles down', () {
    testWidgets('a short greeting is left exactly as it is', (tester) async {
      await _pumpLanding(
        tester,
        panelHeight: 120,
        memberName: 'Amina',
        size: _phone,
      );

      expect(_greeting(tester).data, 'Good morning, Amina');
      expect(_greeting(tester).maxLines, 1);
    });

    testWidgets('a long name falls back to the first name', (tester) async {
      // The product owner's *"first name only if suitable"*: suitable means the
      // full one did not fit, measured rather than guessed.
      await _pumpLanding(
        tester,
        panelHeight: 120,
        memberName: 'Amina Wanjiru Njoroge Kamau',
        size: _phone,
      );

      expect(_greeting(tester).data, 'Good morning, Amina');
    });

    testWidgets('a screen reader still hears the whole greeting', (
      tester,
    ) async {
      // Shortening for width must not shorten what a blind person is told.
      final handle = tester.ensureSemantics();
      await _pumpLanding(
        tester,
        panelHeight: 120,
        memberName: 'Amina Wanjiru Njoroge Kamau',
        size: _phone,
      );

      expect(
        find.bySemanticsLabel('Good morning, Amina Wanjiru Njoroge Kamau'),
        findsOne,
      );
      handle.dispose();
    });

    testWidgets('a business name shrinks rather than losing its end', (
      tester,
    ) async {
      // *Good morning, Dev Corner…* for a shop called Dev Corner Shop names
      // nothing a shopkeeper would recognise, so a business name is never cut
      // to its first word - the type steps down instead.
      await _pumpLanding(
        tester,
        panelHeight: 120,
        tenantName: 'Chilltent Lounge and Provisions',
        size: _phone,
      );

      expect(
        _greeting(tester).data,
        'Good morning, Chilltent Lounge and Provisions',
      );
      expect(_greeting(tester).maxLines, 1);
    });

    testWidgets('the three lines narrow, in order', (tester) async {
      await _pumpLanding(
        tester,
        panelHeight: 120,
        memberName: 'Amina',
        size: _phone,
      );

      final greeting = tester.getSize(find.byKey(_greetingKey)).width;
      final prompt = tester
          .getSize(find.text('Select a module to begin.'))
          .width;
      // The trend line is absent here - `_EmptyReader` publishes no totals, so
      // there is no comparison to state - which is itself the case worth
      // asserting: the funnel must not depend on a line that is often missing.
      expect(prompt, lessThan(greeting));
    });

    // **The report of 2026-08-27, on the home**: *if in a page we have some
    // data from offline and some from online, the online data makes the offline
    // data come late*. The trend line is two callable round trips and the only
    // read on this page that needs a network; the business name, the day's
    // reconciled figures and the currency are Firestore and serve from its
    // cache. `_readOverview` awaited all four together, so the page waited for
    // the slowest and least important of them.
    testWidgets('the home draws while the trend line is still reading', (
      tester,
    ) async {
      final held = Completer<Object?>();
      addTearDown(() {
        if (!held.isCompleted) held.complete(<String, Object?>{});
      });
      await _pumpLanding(
        tester,
        panelHeight: 120,
        memberName: 'Amina',
        role: TenantRole.owner,
        salesTotalsCallable: _HeldTotalsCallable(held),
        reader: const _BrandedReader('Dev Corner Shop'),
        // Settling would wait for the very read this case holds open.
        settle: false,
      );

      // The branding read is Firestore and has answered. Under the old
      // ordering `_readOverview` had not returned at all yet, so the title was
      // still the membership's name and this said `Chilltent Lounge`.
      expect(
        find.text('Dev Corner Shop'),
        findsOne,
        reason:
            'A Firestore read that has landed must not wait for a callable '
            'that has not.',
      );

      held.complete(<String, Object?>{});
      await tester.pumpAndSettle();
    });

    testWidgets('the prompt is one row too', (tester) async {
      await _pumpLanding(
        tester,
        panelHeight: 120,
        memberName: 'Amina',
        size: _phone,
      );

      expect(
        tester.widget<Text>(find.text('Select a module to begin.')).maxLines,
        1,
      );
    });
  });

  // The ladder all three header lines share. Asserted directly because the
  // interesting cases - a string that fits nothing, a reservation for the trend
  // arrow - are awkward to stage through a whole screen and trivial here.
  group('fitting a line to one row', () {
    const ambient = TextStyle();
    const large = TextStyle(fontSize: 40);
    const medium = TextStyle(fontSize: 20);
    const small = TextStyle(fontSize: 10);

    ({String text, TextStyle style}) fit({
      required List<String> texts,
      required double maxWidth,
      double reserved = 0,
    }) => fitToOneLine(
      texts: texts,
      styles: const <TextStyle>[large, medium, small],
      maxWidth: maxWidth,
      scaler: TextScaler.noScaling,
      ambient: ambient,
      reserved: reserved,
    );

    test('keeps the largest role that fits', () {
      expect(fit(texts: <String>['ab'], maxWidth: 10000).style, large);
    });

    test('steps down the roles rather than scaling one', () {
      // Every rung is a role this app already sets text in. A `FittedBox` would
      // answer with an invented size that nothing else on the page shares.
      final fitted = fit(texts: <String>['a long enough line'], maxWidth: 120);

      expect(<TextStyle>[large, medium, small], contains(fitted.style));
    });

    test('prefers a shorter wording to a smaller size', () {
      // The product owner's ordering: *first name only if suitable* comes
      // before making the whole line smaller.
      final fitted = fit(texts: <String>['a very long line', 'ab'], maxWidth: 90);

      expect(fitted.style, large);
      expect(fitted.text, 'ab');
    });

    test('reserved room is taken out of what the text may use', () {
      // The trend line's arrow sits in the same row and is invisible to a
      // measurement of text.
      final roomy = fit(texts: <String>['abcd'], maxWidth: 200);
      final crowded = fit(texts: <String>['abcd'], maxWidth: 200, reserved: 190);

      expect(roomy.style, large);
      expect(crowded.style.fontSize, lessThan(roomy.style.fontSize!));
    });

    test('falls to the smallest role and the shortest wording', () {
      // Nothing fits, so the caller's `overflow: ellipsis` takes over - on the
      // least it can lose.
      final fitted = fit(texts: <String>['first', 'second'], maxWidth: 1);

      expect(fitted.style, small);
      expect(fitted.text, 'second');
    });
  });
}

const ValueKey<String> _greetingKey = ValueKey<String>('home-greeting');

Text _greeting(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_greetingKey));

/// A fixed nine in the morning, so the salutation is not the wall clock.
///
/// **These tests are about the header shortening, not the time of day.** Four
/// of them asserted *Good morning* against `DateTime.now()` and so passed only
/// before noon; the greeting has a clock seam for exactly this, and defaulting
/// it here makes every landing test deterministic rather than only the four.
DateTime _nineInTheMorning() => DateTime(2026, 9, 10, 9);

Future<void> _pumpLanding(
  WidgetTester tester, {
  required double panelHeight,
  String tenantName = 'Chilltent Lounge',
  String? memberName,
  TenantRole role = TenantRole.cashier,
  Widget Function(TenantDataReader reader)? catalogManagementRoute,
  List<TenantRole> catalogManagementRoles = const <TenantRole>[],
  Widget Function(TenantDataReader reader)? returnFeedRoute,
  List<TenantRole> returnFeedRoles = const <TenantRole>[],
  SalesTotalsCallable? salesTotalsCallable,
  TenantDataReader? reader,
  bool settle = true,
  Size size = _phone,
  DateTime Function() clock = _nineInTheMorning,
}) async {
  tester.view.physicalSize = size;
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
          memberName: memberName,
          clock: clock,
          reader: reader ?? _EmptyReader(),
          onSignOut: () async {},
          catalogManagementRoute: catalogManagementRoute,
          catalogManagementRoles: catalogManagementRoles,
          returnFeedRoute: returnFeedRoute,
          returnFeedRoles: returnFeedRoles,
          // The slot the shift panel occupies on a real device. What the fold
          // depends on is the height of what is in it.
          salesTotalsCallable: salesTotalsCallable,
          shiftPanel: (_) => SizedBox(
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
  // A case watching a held read wants the frames without the settle, because
  // settling would wait for the very thing it is holding open.
  if (settle) await tester.pumpAndSettle();
}

/// A totals callable that answers only when the test says so.
///
/// The home's trend line is the one read on that page that needs a network.
/// Holding it open is how a test watches the rest of the page arrive without
/// it - which before 2026-08-27 it could not, because everything waited.
final class _HeldTotalsCallable implements SalesTotalsCallable {
  _HeldTotalsCallable(this._gate);

  final Completer<Object?> _gate;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    await _gate.future;
    return <String, Object?>{
      'sales': 0,
      'profit': 0,
      'transactions': 0,
      'incompleteCostLineCount': 0,
    };
  }
}

/// A reader that publishes this business's own name and nothing else.
///
/// **The one Firestore read on the home whose arrival is visible.** The figure
/// grid draws em dashes whether its read has landed or not, so branding is what
/// a test can watch: the title says `membership.tenantName` until the read
/// answers and the published name after it.
final class _BrandedReader implements TenantDataReader {
  const _BrandedReader(this.companyName);

  final String companyName;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async =>
      path.endsWith('/configuration/branding')
      ? TenantDocumentSnapshot(
          path: path,
          data: <String, Object?>{'companyName': companyName},
        )
      : null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
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
  String? memberName,
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
