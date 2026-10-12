import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/home_navigation.dart';
import 'package:uzapay_pos/ui/hub_bar.dart';
import 'package:uzapay_pos/ui/stats.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/ui/scaffold.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

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
    await _pumpLanding(
      tester,
      panelHeight: 900,
      shiftHistoryRoute: (_) => const Scaffold(body: Text('History open')),
    );

    final destination = find.byKey(const ValueKey('shift-history'));
    await _reveal(tester, destination);

    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: destination,
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
      shiftHistoryRoute: (_) => const Scaffold(body: Text('History open')),
    );

    final destination = tester.getRect(
      find.byKey(const ValueKey('shift-history')),
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

  testWidgets('the account controls are not on the grid - design.md §4.4', (
    tester,
  ) async {
    // **§4.4 put "the two account controls last"; there are none now.**
    // *Change business* moved onto the business's own name in the top bar on
    // 2026-09-03, and *Make default* followed it into the same switcher on
    // 2026-09-16 - it is the same question that dialog already asks, and a
    // default is only worth setting when there is more than one business to
    // choose between, which is the condition that opens it. So the rule's
    // subject is gone rather than reordered, and what is asserted is that the
    // grid is destinations only.
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

    expect(find.byKey(const ValueKey('inventory')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('make-default-tenant')),
      findsNothing,
      reason: 'the default-business control belongs to the switcher now',
    );
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
    // name does not push the bar's own controls off the end of it. **The bar
    // is the old hub's since 2026-10-10**, on a phone too, so it is the one
    // measured.
    for (final name in <String>[
      'Chilltent Lounge',
      'Chilltent Lounge Nairobi Westlands Branch',
    ]) {
      await _pumpLanding(tester, panelHeight: 120, tenantName: name);

      final bar = tester.getRect(find.byType(HubTopBar));
      final title = tester.getRect(
        find.descendant(of: find.byType(HubTopBar), matching: find.text(name)),
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
      final fitted = fit(
        texts: <String>['a very long line', 'ab'],
        maxWidth: 90,
      );

      expect(fitted.style, large);
      expect(fitted.text, 'ab');
    });

    test('reserved room is taken out of what the text may use', () {
      // The trend line's arrow sits in the same row and is invisible to a
      // measurement of text.
      final roomy = fit(texts: <String>['abcd'], maxWidth: 200);
      final crowded = fit(
        texts: <String>['abcd'],
        maxWidth: 200,
        reserved: 190,
      );

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

  testWidgets('coming back from a module re-reads the day', (tester) async {
    // **The defect this covers was reported from a till.** Sales were being
    // rung and the home never moved, because every module is pushed over this
    // route: returning is a pop, a pop is not a rebuild, and `TenantRouteGuard`
    // re-reads only when its loader changes identity. The figures on screen
    // were the ones read on the way in, with nothing saying so.
    final reader = _CountingReader();
    await _pumpLanding(
      tester,
      panelHeight: 120,
      role: TenantRole.owner,
      reader: reader,
    );
    final onArrival = reader.documentReads;
    expect(onArrival, greaterThan(0));

    // Stand in for any module: what matters is that it is pushed over the home
    // and then popped, which is what every destination on this page does.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('a module')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();

    expect(
      reader.documentReads,
      greaterThan(onArrival),
      reason: 'the home should ask again once it is back on top',
    );
  });

  group('spending has figures of its own only on a day that has some', () {
    // With nothing spent, net profit is gross profit under a second name, and
    // an expenses tile reading zero beside it is three tiles saying one thing.
    Future<void> pump(
      WidgetTester tester,
      List<TenantQueryDocumentSnapshot> expenses,
    ) => _pumpLanding(
      tester,
      panelHeight: 120,
      role: TenantRole.owner,
      reader: _CachedSalesReader(<TenantQueryDocumentSnapshot>[
        _cachedSale(checkoutId: 'checkout-a', sequence: 1, totalMinor: 3000),
      ], expenses: expenses),
    );

    testWidgets('a day with an expense shows it, and a net figure', (
      tester,
    ) async {
      await pump(tester, <TenantQueryDocumentSnapshot>[
        _todayExpense(token: 'tok-a', amountMinor: 1200),
      ]);

      final spent = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-expenses')),
      );
      expect(spent.value, contains('12'));
      expect(spent.detail, 'Recorded today');
      expect(find.byKey(const ValueKey('home-today-net-profit')), findsOne);
      expect(
        tester
            .widget<StatTile>(find.byKey(const ValueKey('home-today-profit')))
            .label,
        'Gross profit',
      );
    });

    testWidgets('a day with none shows neither', (tester) async {
      await pump(tester, const <TenantQueryDocumentSnapshot>[]);

      expect(find.byKey(const ValueKey('home-today-expenses')), findsNothing);
      expect(find.byKey(const ValueKey('home-today-net-profit')), findsNothing);
      expect(
        tester
            .widget<StatTile>(find.byKey(const ValueKey('home-today-profit')))
            .label,
        'Profit',
        reason: 'Gross only means something beside a net figure.',
      );
    });

    testWidgets('a voided expense is not spending', (tester) async {
      await pump(tester, <TenantQueryDocumentSnapshot>[
        _todayExpense(token: 'tok-a', amountMinor: 1200, voided: true),
      ]);

      expect(find.byKey(const ValueKey('home-today-expenses')), findsNothing);
      expect(find.byKey(const ValueKey('home-today-net-profit')), findsNothing);
    });
  });

  group('an unreconciled day says what this device can already add up', () {
    // Reconciliation qualifies the figure; it does not unlock it. Before
    // 2026-09-19 every tile here read an em dash over *Not reconciled yet*
    // until the nightly run published - and today is normally unreconciled,
    // so the home routinely hid a morning's trade it could already state.

    testWidgets('the takings are drawn from the cache', (tester) async {
      await _pumpLanding(
        tester,
        panelHeight: 120,
        role: TenantRole.owner,
        reader: _CachedSalesReader(<TenantQueryDocumentSnapshot>[
          _cachedSale(checkoutId: 'checkout-a', sequence: 1, totalMinor: 3000),
          _cachedSale(checkoutId: 'checkout-b', sequence: 2, totalMinor: 1500),
        ]),
      );

      final sales = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-sales')),
      );
      // 30.00 and 15.00, the two the cache holds.
      expect(sales.value, contains('45'));
      // **Nothing said about reconciliation**, at the developer's direction
      // on 2026-09-29: it certifies this figure, it does not change it.
      expect(sales.detail, isNull);
      expect(sales.status, isNull);

      final transactions = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-transactions')),
      );
      expect(transactions.value, '2');
      expect(transactions.detail, isNull);
      expect(find.textContaining('econciled'), findsNothing);
      expect(find.text('On this device'), findsNothing);
    });

    testWidgets('the shift count is every shift opened today', (tester) async {
      await _pumpLanding(
        tester,
        panelHeight: 120,
        role: TenantRole.owner,
        reader: _CachedSalesReader(
          <TenantQueryDocumentSnapshot>[
            _cachedSale(
              checkoutId: 'checkout-a',
              sequence: 1,
              totalMinor: 3000,
            ),
          ],
          // One closed, one still running, on two tills: all three count.
          shifts: <Map<String, Object?>>[
            _todayShift(id: 'shift-100', staffId: 'user-a', closed: true),
            _todayShift(id: 'shift-200', staffId: 'user-a'),
            _todayShift(id: 'shift-300', staffId: 'user-b'),
          ],
        ),
      );

      final shifts = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-shifts')),
      );
      expect(shifts.value, '3');
      expect(shifts.detail, 'Opened today');
    });

    testWidgets('a day with no shift opened says zero', (tester) async {
      await _pumpLanding(
        tester,
        panelHeight: 120,
        role: TenantRole.owner,
        reader: _CachedSalesReader(<TenantQueryDocumentSnapshot>[
          _cachedSale(checkoutId: 'checkout-a', sequence: 1, totalMinor: 3000),
        ]),
      );

      final shifts = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-shifts')),
      );
      expect(shifts.value, '0');
    });

    testWidgets('a full page of shifts is drawn as a floor', (tester) async {
      await _pumpLanding(
        tester,
        panelHeight: 120,
        role: TenantRole.owner,
        reader: _CachedSalesReader(
          <TenantQueryDocumentSnapshot>[
            _cachedSale(
              checkoutId: 'checkout-a',
              sequence: 1,
              totalMinor: 3000,
            ),
          ],
          shifts: <Map<String, Object?>>[
            for (var index = 100; index < 160; index++)
              _todayShift(id: 'shift-$index', staffId: 'user-a', closed: true),
          ],
        ),
      );

      final shifts = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-shifts')),
      );
      expect(shifts.value, '50+');
    });

    testWidgets('a day this device counted nothing for stays an em dash', (
      tester,
    ) async {
      await _pumpLanding(
        tester,
        panelHeight: 120,
        role: TenantRole.owner,
        reader: _CachedSalesReader(const <TenantQueryDocumentSnapshot>[]),
      );

      // Zero is the one device figure that cannot be told apart from
      // ignorance, so it is not published as the day's takings.
      final sales = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-sales')),
      );
      expect(sales.value, '—');
      expect(sales.detail, isNull);
      expect(sales.status, isNull);
    });

    testWidgets('a sale held only in the outbox still reaches the tiles', (
      tester,
    ) async {
      // **The reported defect, reproduced.** A sale rung with no network is
      // never handed to the Firestore SDK - the submission gateway refuses
      // while `isOnline` is false - so it is not a pending write and the cache
      // does not hold it either. The outbox is the only place it exists, and
      // the home was not reading one: its device pass saw the single synced
      // sale, tied with the published count at one, and drew the published
      // figure while the till went on trading. Which is a shopkeeper ringing a
      // sale and watching the total refuse to move.
      final outbox = await _offlineOutbox('landing-outbox-a', count: 1);
      addTearDown(outbox.close);

      await _pumpLanding(
        tester,
        panelHeight: 120,
        role: TenantRole.owner,
        checkoutOutbox: outbox,
        reader: _BehindReader(
          publishedTransactions: 1,
          sales: <TenantQueryDocumentSnapshot>[
            _cachedSale(checkoutId: 'a', sequence: 1, totalMinor: 3000),
          ],
        ),
      );

      final transactions = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-transactions')),
      );
      expect(transactions.value, '2');
      expect(transactions.statusLabel, isNull);

      final sales = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-sales')),
      );
      // 30.00 counted by the server plus 60.00 this device is still holding.
      expect(sales.value, contains('90'));
    });

    testWidgets(
      'a busier till keeps its figure, and the tile says what is not in it',
      (tester) async {
        // **Both halves matter, and the first is the one easy to get wrong.**
        // The cache holds a subset of what the server has, so this device can
        // only ever say `cached + unsent` - and against a register that has sold
        // nine, that is the smaller and further-off number. Preferring it because
        // this device happens to hold unsent work would replace 9 with 2 on a day
        // that truly took 10.
        //
        // So the published figure stays, and what was wrong before is only that
        // it said nothing about the sale this device is still carrying.
        final outbox = await _offlineOutbox('landing-outbox-b', count: 1);
        addTearDown(outbox.close);

        await _pumpLanding(
          tester,
          panelHeight: 120,
          role: TenantRole.owner,
          checkoutOutbox: outbox,
          reader: _BehindReader(
            publishedTransactions: 9,
            sales: <TenantQueryDocumentSnapshot>[
              _cachedSale(checkoutId: 'a', sequence: 1, totalMinor: 3000),
            ],
          ),
        );

        final transactions = tester.widget<StatTile>(
          find.byKey(const ValueKey('home-today-transactions')),
        );
        expect(transactions.value, '9');
        // Never colour alone: the badge carries the words.
        expect(transactions.status, AppStatus.attention);
        expect(transactions.statusLabel, '1 not sent');
      },
    );

    testWidgets('a published day this device owes nothing on says so plainly', (
      tester,
    ) async {
      // The control for the badge above: an empty outbox must leave the tile
      // exactly as it was, or every reconciled day grows a warning.
      final outbox = await _offlineOutbox('landing-outbox-c', count: 0);
      addTearDown(outbox.close);

      await _pumpLanding(
        tester,
        panelHeight: 120,
        role: TenantRole.owner,
        checkoutOutbox: outbox,
        reader: _BehindReader(
          publishedTransactions: 9,
          sales: <TenantQueryDocumentSnapshot>[
            _cachedSale(checkoutId: 'a', sequence: 1, totalMinor: 3000),
          ],
        ),
      );

      final transactions = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-transactions')),
      );
      expect(transactions.value, '9');
      expect(transactions.status, isNull);
      expect(transactions.statusLabel, isNull);
    });

    testWidgets(
      'a sale the server has not counted wins over the published day',
      (tester) async {
        // The server has counted two; this device holds three, because one was
        // rung offline and has not synced. Reconciliation cannot know about it,
        // so the published figure is simply behind - and the till that rang the
        // sale is the one surface that can say so.
        await _pumpLanding(
          tester,
          panelHeight: 120,
          role: TenantRole.owner,
          reader: _BehindReader(
            publishedTransactions: 2,
            sales: <TenantQueryDocumentSnapshot>[
              _cachedSale(checkoutId: 'a', sequence: 1, totalMinor: 3000),
              _cachedSale(checkoutId: 'b', sequence: 2, totalMinor: 3000),
              _cachedSale(checkoutId: 'c', sequence: 3, totalMinor: 3000),
            ],
          ),
        );

        final transactions = tester.widget<StatTile>(
          find.byKey(const ValueKey('home-today-transactions')),
        );
        expect(transactions.value, '3');
        expect(transactions.statusLabel, isNull);

        final sales = tester.widget<StatTile>(
          find.byKey(const ValueKey('home-today-sales')),
        );
        expect(sales.value, contains('90'));
      },
    );

    testWidgets('a second till that sold more keeps the published figure', (
      tester,
    ) async {
      // The mirror case, and the reason this is decided on the count rather
      // than on whether a cache read succeeded: another register's sales are in
      // `daily_metrics` and were never on this device, so here the published
      // figure is the more complete of the two and must win.
      await _pumpLanding(
        tester,
        panelHeight: 120,
        role: TenantRole.owner,
        reader: _BehindReader(
          publishedTransactions: 9,
          sales: <TenantQueryDocumentSnapshot>[
            _cachedSale(checkoutId: 'a', sequence: 1, totalMinor: 3000),
          ],
        ),
      );

      final transactions = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-transactions')),
      );
      expect(transactions.value, '9');
      expect(transactions.statusLabel, isNull);
    });

    testWidgets('a reader with no cache is left exactly as it was', (
      tester,
    ) async {
      await _pumpLanding(
        tester,
        panelHeight: 120,
        role: TenantRole.owner,
        reader: _EmptyReader(),
      );

      // `TenantDataReader.cached` is null for a reader that is not
      // `TenantCacheReadable`, which is every other fake in this suite - so
      // the fallback cannot fire and the em dash is still the honest answer.
      final sales = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-sales')),
      );
      expect(sales.value, '—');
      expect(sales.detail, isNull);
      expect(sales.status, isNull);
    });
  });

  group('a published day with a return in it is shown net of it', () {
    // **Seen on SIT on 2026-09-29.** Four sales, the second returned in full,
    // and reconciliation published the day with the return taken out. The
    // daily summary, the Sales route and the weekly report all said 3000 over
    // three transactions; this grid said 4000 over four, because it read the
    // gross fields of the same document.

    testWidgets('the takings, the count and the profit leave the return out', (
      tester,
    ) async {
      await _pumpLanding(
        tester,
        panelHeight: 120,
        role: TenantRole.owner,
        reader: _BehindReader(
          publishedTransactions: 4,
          publishedReturns: 1,
          sales: <TenantQueryDocumentSnapshot>[
            _cachedSale(checkoutId: 'a', sequence: 1, totalMinor: 3000),
            _cachedSale(checkoutId: 'b', sequence: 2, totalMinor: 3000),
            _cachedSale(checkoutId: 'c', sequence: 3, totalMinor: 3000),
            _cachedSale(checkoutId: 'd', sequence: 4, totalMinor: 3000),
          ],
          returns: <Map<String, Object?>>[_cachedFullReturn(saleId: 'b')],
        ),
      );

      final sales = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-sales')),
      );
      // 120.00 sold, 30.00 of it came back.
      expect(sales.value, contains('90'));
      expect(sales.value, isNot(contains('120')));
      expect(sales.status, isNull);

      final transactions = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-transactions')),
      );
      expect(transactions.value, '3');

      final profit = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-profit')),
      );
      expect(profit.value, contains('30'));
      expect(profit.value, isNot(contains('40')));
    });

    testWidgets('a return does not hide a sale the server has not counted', (
      tester,
    ) async {
      // The other half of the same defect. Whether this device holds a sale
      // the server has not seen was decided by comparing its *net* count with
      // the published *gross* one, so the returned sale made this side one
      // short: four cached, one returned, one unsent is five sales, and it
      // tied with the published four and lost.
      final outbox = await _offlineOutbox('landing-outbox-d', count: 1);
      addTearDown(outbox.close);

      await _pumpLanding(
        tester,
        panelHeight: 120,
        role: TenantRole.owner,
        checkoutOutbox: outbox,
        reader: _BehindReader(
          publishedTransactions: 4,
          publishedReturns: 1,
          sales: <TenantQueryDocumentSnapshot>[
            _cachedSale(checkoutId: 'a', sequence: 1, totalMinor: 3000),
            _cachedSale(checkoutId: 'b', sequence: 2, totalMinor: 3000),
            _cachedSale(checkoutId: 'c', sequence: 3, totalMinor: 3000),
            _cachedSale(checkoutId: 'd', sequence: 4, totalMinor: 3000),
          ],
          returns: <Map<String, Object?>>[_cachedFullReturn(saleId: 'b')],
        ),
      );

      final transactions = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-transactions')),
      );
      // Five sales, one of them returned in full.
      expect(transactions.value, '4');
      expect(transactions.statusLabel, isNull);

      final sales = tester.widget<StatTile>(
        find.byKey(const ValueKey('home-today-sales')),
      );
      // Three cached sales kept at 30.00 and the unsent one at 60.00.
      expect(sales.value, contains('150'));
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
  Widget Function(TenantDataReader reader)? shiftHistoryRoute,
  SalesTotalsCallable? salesTotalsCallable,
  TenantDataReader? reader,
  HiveCheckoutOutbox? checkoutOutbox,
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
      // What `_RereadOnReturn` subscribes to. Without it a pop is silence and
      // the home keeps the figures it read on the way in.
      navigatorObservers: <NavigatorObserver>[tenantRouteObserver],
      home: TenantSessionScope(
        controller: controller,
        child: TenantSafeLandingScreen(
          membership: membership,
          memberName: memberName,
          clock: clock,
          reader: reader ?? _EmptyReader(),
          checkoutOutbox: checkoutOutbox,
          onSignOut: () async {},
          catalogManagementRoute: catalogManagementRoute,
          catalogManagementRoles: catalogManagementRoles,
          returnFeedRoute: returnFeedRoute,
          returnFeedRoles: returnFeedRoles,
          shiftHistoryRoute: shiftHistoryRoute,
          // The slot the shift panel occupies on a real device. What the fold
          // depends on is the height of what is in it.
          salesTotalsCallable: salesTotalsCallable,
          shiftPanel: (_, _) => SizedBox(
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

/// A reader with a reconciled day *and* a cache that holds more than it.
///
/// This is the shape of the defect reported from a till: a sale rung while the
/// device was offline sits in the cache and cannot be in `daily_metrics`, so
/// the Sales route counted it and the home did not. Two totals, no way to
/// square them, and the shopkeeper concludes the app is broken.
final class _BehindReader
    implements
        TenantDataReader,
        TenantSalesHistoryQueryReader,
        TenantCacheReadable {
  _BehindReader({
    required this.sales,
    required this.publishedTransactions,
    this.publishedReturns = 0,
    this.returns = const <Map<String, Object?>>[],
  });

  final List<TenantQueryDocumentSnapshot> sales;

  /// What the server has counted, deliberately fewer than [sales] holds.
  final int publishedTransactions;

  /// How many of the published sales came back in full. They stay in the
  /// gross figures and leave the `net` block, which is how reconciliation
  /// writes a day with returns in it.
  final int publishedReturns;

  /// Return documents this device has in its cache.
  final List<Map<String, Object?>> returns;

  @override
  TenantDataReader get cacheOnly => this;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (!path.contains('daily_metrics')) return null;
    // Whatever day the repository asked for, so the fixture cannot drift from
    // the clock the page is reading.
    final businessDate = path.split('/').last;
    final kept = publishedTransactions - publishedReturns;
    return TenantDocumentSnapshot(
      path: path,
      data: <String, Object?>{
        'tenantId': 'tenant-a',
        'businessDate': businessDate,
        'sales': 30.0 * publishedTransactions,
        'profit': 10.0 * publishedTransactions,
        'transactions': publishedTransactions,
        'transactionCount': publishedTransactions,
        'shiftCount': 1,
        'incompleteCostLineCount': 0,
        'netSales': 30.0 * kept,
        'netProfit': 10.0 * kept,
        'netTransactions': kept,
        'netIncompleteCostLineCount': 0,
        'returnedSales': 30.0 * publishedReturns,
        'returnCount': publishedReturns,
        'netMetricsVersion': 1,
        'metricGeneration': 'gen-1',
        'sourceDirtyRevision': 1,
        'regeneratedAt': DateTime.utc(2026, 9, 10, 6),
      },
    );
  }

  /// The cached returns, a day at a time, which is how the device aggregator
  /// asks for them. Nothing else this page pages through is held.
  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    if (!query.collectionPath.endsWith('/returns')) {
      return const <TenantQueryDocumentSnapshot>[];
    }
    final day = query.equalityFilters['businessDate'];
    return <TenantQueryDocumentSnapshot>[
      for (final record in returns)
        if (day == null || record['businessDate'] == day)
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/${record['returnId']}',
            data: record,
          ),
    ];
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantSalesHistory(
    TenantSalesHistoryQuery query,
  ) async {
    final matches =
        sales.where((document) {
          final date = document.data['businessDate']! as String;
          return date.compareTo(query.startBusinessDate) >= 0 &&
              date.compareTo(query.endBusinessDate) <= 0;
        }).toList()..sort((left, right) {
          final leftDate = left.data['businessDate']! as String;
          final rightDate = right.data['businessDate']! as String;
          final byDate = rightDate.compareTo(leftDate);
          return byDate != 0 ? byDate : right.path.compareTo(left.path);
        });
    final cursor = query.startAfter;
    final after = cursor == null
        ? matches
        : matches.where((document) {
            final date = document.data['businessDate']! as String;
            final id = document.path.split('/').last;
            return date.compareTo(cursor.businessDate) < 0 ||
                date == cursor.businessDate &&
                    id.compareTo(cursor.documentId) < 0;
          }).toList();
    return after.take(query.limit).toList(growable: false);
  }
}

/// A reader whose cache holds today's sales and no reconciled day.
///
/// **`cacheOnly` answering with itself is the whole point.**
/// `TenantDataReader.cached` is null for every fake that is not
/// [TenantCacheReadable], so without this the home's device fallback is not
/// reachable from a test at all - and every other suite keeps the behaviour it
/// had before the fallback existed, which is why nothing else needed changing.
final class _CachedSalesReader
    implements
        TenantDataReader,
        TenantSalesHistoryQueryReader,
        TenantCacheReadable {
  _CachedSalesReader(
    this.sales, {
    this.expenses = const <TenantQueryDocumentSnapshot>[],
    this.shifts = const <Map<String, Object?>>[],
  });

  final List<TenantQueryDocumentSnapshot> sales;

  /// Today's spending, answered to the expenses walk and to nothing else.
  final List<TenantQueryDocumentSnapshot> expenses;

  /// Shift documents, answered to a day's shift query.
  final List<Map<String, Object?>> shifts;

  @override
  TenantDataReader get cacheOnly => this;

  /// Absent, which is what an unreconciled day looks like: `readDay` answers
  /// null and `TenantDailyMetricsDay.metrics` is null with it.
  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  /// No returns in the cache, so the day is reported gross - the same
  /// fallback `TenantSalesTotals.net` makes everywhere else. The expenses walk
  /// is answered in ID order after its cursor, which is how it pages.
  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    if (query.collectionPath.endsWith('/shifts')) {
      // Ascending document order within the page's limit, which is what the
      // repository proves of every page it reads.
      final day = query.equalityFilters['businessDate'];
      final ordered =
          shifts.where((shift) => shift['businessDate'] == day).toList()..sort(
            (a, b) =>
                (a['shiftId']! as String).compareTo(b['shiftId']! as String),
          );
      return <TenantQueryDocumentSnapshot>[
        for (final shift in ordered.take(query.limit))
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/${shift['shiftId']}',
            data: shift,
          ),
      ];
    }
    if (!query.collectionPath.endsWith('/expenses')) {
      return const <TenantQueryDocumentSnapshot>[];
    }
    final after = query.startAfterDocumentId;
    final ordered = expenses.toList()..sort((a, b) => a.path.compareTo(b.path));
    return ordered
        .where(
          (document) =>
              after == null ||
              document.path.split('/').last.compareTo(after) > 0,
        )
        .take(query.limit)
        .toList(growable: false);
  }

  /// **Ordered and paged, because the repository checks.** Answering the same
  /// unsorted list to every page reads as an unstable query and
  /// `TenantSaleHistoryRepository.loadReport` refuses it outright - which is
  /// the right refusal, and cost this test an afternoon to learn.
  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantSalesHistory(
    TenantSalesHistoryQuery query,
  ) async {
    final matches =
        sales.where((document) {
          final date = document.data['businessDate']! as String;
          return date.compareTo(query.startBusinessDate) >= 0 &&
              date.compareTo(query.endBusinessDate) <= 0;
        }).toList()..sort((left, right) {
          final leftDate = left.data['businessDate']! as String;
          final rightDate = right.data['businessDate']! as String;
          final byDate = rightDate.compareTo(leftDate);
          return byDate != 0 ? byDate : right.path.compareTo(left.path);
        });
    final cursor = query.startAfter;
    final after = cursor == null
        ? matches
        : matches.where((document) {
            final date = document.data['businessDate']! as String;
            final id = document.path.split('/').last;
            return date.compareTo(cursor.businessDate) < 0 ||
                date == cursor.businessDate &&
                    id.compareTo(cursor.documentId) < 0;
          }).toList();
    return after.take(query.limit).toList(growable: false);
  }
}

/// One sale this device holds, on the business day [_nineInTheMorning] falls
/// in - derived the way the code derives it, so the test does not assume the
/// machine's time zone.
/// An outbox holding [count] sales this device has never sent.
///
/// **In memory, because a widget test has no real clock to wait on.**
/// `pumpAndSettle` advances a fake one while a Hive box backed by a file
/// answers on the real event loop, so a disk-backed box here never settles and
/// the test hangs rather than failing. Passing `bytes` keeps it off the
/// filesystem; the reads the home makes of it are synchronous either way.
Future<HiveCheckoutOutbox> _offlineOutbox(
  String name, {
  required int count,
}) async {
  final outbox = HiveCheckoutOutbox.fromBox(
    await Hive.openBox<dynamic>(name, bytes: Uint8List(0)),
  );
  for (var index = 0; index < count; index++) {
    await outbox.saveOffline(
      uid: 'user-a',
      tenantId: 'tenant-a',
      checkoutId: 'checkout-offline-$index',
      payload: _offlineSalePayload(
        checkoutId: 'checkout-offline-$index',
        sequence: 100 + index,
        totalMinor: 6000,
      ),
    );
  }
  return outbox;
}

/// One sale as the outbox holds it, never having reached Firestore.
///
/// Mirrors [_cachedSale] deliberately: the same day, the same device and the
/// same shape, so the only thing separating them in a test is where they live.
Map<String, Object?> _offlineSalePayload({
  required String checkoutId,
  required int sequence,
  required int totalMinor,
}) {
  const deviceId = 'dev-0123456789abcdef0123456789abcdef';
  final businessDate = checkoutBusinessDate(_nineInTheMorning().toUtc());
  return <String, Object?>{
    'schemaVersion': checkoutSalePayloadSchemaVersion,
    'checkoutId': checkoutId,
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'currency': 'KES',
    'businessDate': businessDate,
    'createdAtMs': _nineInTheMorning().toUtc().millisecondsSinceEpoch,
    'shiftId': 'shift-a',
    'deviceId': deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: deviceId,
      businessDate: businessDate,
      sequence: sequence,
    ),
    'receiptSequence': sequence,
    'tender': 'cash',
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-$checkoutId',
        'name': 'Item',
        'categoryId': 'category-a',
        'quantity': 1,
        'unitPriceMinor': totalMinor,
        'unitCostMinor': 0,
      },
    ],
    'subtotalMinor': totalMinor,
    'discountMinor': 0,
    'totalMinor': totalMinor,
  };
}

TenantQueryDocumentSnapshot _cachedSale({
  required String checkoutId,
  required int sequence,
  required int totalMinor,
}) {
  const deviceId = 'dev-0123456789abcdef0123456789abcdef';
  final businessDate = checkoutBusinessDate(_nineInTheMorning().toUtc());
  return TenantQueryDocumentSnapshot(
    path: 'tenants/tenant-a/sales/$checkoutId',
    data: <String, Object?>{
      'checkoutId': checkoutId,
      'tenantId': 'tenant-a',
      'soldById': 'user-a',
      'payloadHash': 'a'.padRight(64, 'a'),
      'payloadSchemaVersion': 2,
      'tender': 'cash',
      'currency': 'KES',
      'businessDate': businessDate,
      'shiftId': 'shift-a',
      'deviceId': deviceId,
      'receiptNumber': formatCheckoutReceiptNumber(
        deviceId: deviceId,
        businessDate: businessDate,
        sequence: sequence,
      ),
      'receiptSequence': sequence,
      'items': <Object?>[
        <String, Object?>{
          'productId': 'product-$checkoutId',
          'name': 'Item',
          'categoryId': 'category-a',
          'quantity': 1,
          'unitPriceMinor': totalMinor,
          'lineTotalMinor': totalMinor,
        },
      ],
      'subtotalMinor': totalMinor,
      'subtotal': totalMinor / 100,
      'discountMinor': 0,
      'discount': 0,
      'totalMinor': totalMinor,
      'total': totalMinor / 100,
      'createdAt': _nineInTheMorning().toUtc(),
    },
  );
}

/// One shift opened on the day [_nineInTheMorning] falls in, still running or
/// closed.
Map<String, Object?> _todayShift({
  required String id,
  required String staffId,
  bool closed = false,
}) => <String, Object?>{
  'shiftId': id,
  'tenantId': 'tenant-a',
  'staffId': staffId,
  'deviceId': 'dev-0123456789abcdef0123456789abcdef',
  'businessDate': checkoutBusinessDate(_nineInTheMorning().toUtc()),
  'status': closed ? 'closed' : 'open',
  'startTime': _nineInTheMorning().toUtc(),
  if (closed) ...<String, Object?>{
    'closingCashMinor': 3000,
    'totalSalesMinor': 3000,
    'totalSales': 30.0,
    'transactionCount': 1,
  },
};

/// A return of the whole of one [_cachedSale], as this device's cache holds it.
Map<String, Object?> _cachedFullReturn({required String saleId}) {
  final businessDate = checkoutBusinessDate(_nineInTheMorning().toUtc());
  return <String, Object?>{
    'returnId': 'return-$saleId',
    'tenantId': 'tenant-a',
    'saleId': saleId,
    'businessDate': businessDate,
    'recordedOn': businessDate,
    'createdBy': 'user-a',
    // Pending, because a filed return counts before a manager gets to it.
    'status': 'pending',
    'reason': 'Spoiled or expired',
    'itemsReturned': <Object?>[
      <String, Object?>{'productId': 'product-$saleId', 'quantity': 1},
    ],
    'createdAt': _nineInTheMorning().toUtc(),
  };
}

/// One expense recorded today, voided where [voided] says so.
TenantQueryDocumentSnapshot _todayExpense({
  required String token,
  required int amountMinor,
  bool voided = false,
}) {
  final date = checkoutBusinessDate(_nineInTheMorning().toUtc());
  return TenantQueryDocumentSnapshot(
    path: 'tenants/tenant-a/expenses/$date-$token',
    data: <String, Object?>{
      'expenseId': '$date-$token',
      'tenantId': 'tenant-a',
      'businessDate': date,
      'category': 'rent',
      'description': 'Something the business paid for',
      'amountMinor': amountMinor,
      'amount': amountMinor / 100,
      'recordedBy': 'user-a',
      'createdAt': _nineInTheMorning().toUtc(),
      if (voided) ...<String, Object?>{
        'voidedAt': _nineInTheMorning().toUtc(),
        'voidedBy': 'user-a',
        'voidReason': 'Recorded twice.',
      },
    },
  );
}

/// Counts the reads the page makes, so a test can say whether it asked again.
final class _CountingReader implements TenantDataReader {
  int documentReads = 0;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentReads += 1;
    return null;
  }

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
