import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/home_navigation.dart';
import 'package:flutter_application_1/ui/press.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

final _tokens = spiritTheme.extension<AppTokens>()!;

/// Mounts [child] under the app's own theme, at a stated surface width.
///
/// The width is set on the view *and* the `MediaQuery`, because
/// [HomeNavigation] resolves its band from `MediaQuery.sizeOf` - §4.1's ranges
/// describe the surface a person is looking at, not the widget's own box.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 411,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 2400),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    ),
  );
}

HomeDestination _destination(
  String label, {
  bool isPrimary = false,
  bool enabled = true,
  String? status,
  String? group,
  String? description,
  int? badgeCount,
}) => HomeDestination(
  destinationKey: ValueKey(label),
  label: label,
  icon: Icons.inventory_2_outlined,
  status: status,
  isPrimary: isPrimary,
  group: group,
  description: description,
  badgeCount: badgeCount,
  onPressed: enabled ? () {} : null,
);

List<HomeDestination> _eight() => <HomeDestination>[
  _destination('New sale', isPrimary: true),
  for (var index = 1; index <= 7; index++) _destination('Destination $index'),
];

/// The **painted** row, not the slot it sits in.
///
/// `PressSurface` shrink-wraps unless told otherwise, so its own render box can
/// be the full width of its slot while the row inside it floats at its
/// intrinsic size. Measuring the key measured the slot and passed while the
/// primary was drawn at 40% of the row - the screenshot is what caught it.
/// Every dimension asserted here is the container that actually gets painted.
Rect _rectOf(WidgetTester tester, String label) => tester.getRect(
  find
      .descendant(
        of: find.byKey(ValueKey(label)),
        matching: find.byType(Container),
      )
      .first,
);

void main() {
  group('home module grid', () {
    // ------------------------------------------------------------------
    // A tile's label, and the count on its glyph.
    //
    // **Both were reported off a handset rather than off a capture.** The
    // screenshot harness photographs a settled tree, so a word broken across
    // two lines with one letter on the second looked exactly like a word that
    // fitted.
    // ------------------------------------------------------------------

    testWidgets('a single word is scaled to fit rather than broken', (
      tester,
    ) async {
      await _pump(
        tester,
        HomeModuleGrid(
          destinations: <HomeDestination>[_destination('Inventory')],
        ),
        width: 360,
      );

      final label = tester.widget<Text>(find.text('Inventory'));
      expect(label.maxLines, 1, reason: 'A word has nowhere to break.');
      expect(label.softWrap, isFalse);
      expect(
        find.ancestor(
          of: find.text('Inventory'),
          matching: find.byType(FittedBox),
        ),
        findsWidgets,
        reason: 'A word scaled down is the same word; a word cut is not.',
      );
    });

    testWidgets('a phrase still takes its two lines', (tester) async {
      await _pump(
        tester,
        HomeModuleGrid(
          destinations: <HomeDestination>[_destination('Unprinted receipts')],
        ),
        width: 360,
      );

      final label = tester.widget<Text>(find.text('Unprinted receipts'));
      expect(label.maxLines, 2);
      expect(label.softWrap, isTrue);
    });

    testWidgets('a queue with something in it is counted and marked', (
      tester,
    ) async {
      await _pump(
        tester,
        HomeModuleGrid(
          destinations: <HomeDestination>[
            _destination('Unprinted receipts', badgeCount: 2),
          ],
        ),
        width: 360,
      );

      expect(find.text('2'), findsOneWidget);
      // The palette `spiritTheme` is built from, which is what this pumps.
      const tokens = AppTokens.profoundVerdant;
      final glyph = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('Unprinted receipts')),
          matching: find.byType(Icon),
        ),
      );
      expect(glyph.color, tokens.colors.status.problem.fg);
    });

    testWidgets('a queue with nothing in it is neither counted nor red', (
      tester,
    ) async {
      await _pump(
        tester,
        HomeModuleGrid(
          destinations: <HomeDestination>[
            _destination('Unprinted receipts', badgeCount: 0),
          ],
        ),
        width: 360,
      );

      // A permanent zero trains a person to stop looking at the one place that
      // tells them something is stuck, and red on a device with nothing wrong
      // says a problem that is not there.
      expect(find.text('0'), findsNothing);
      // The palette `spiritTheme` is built from, which is what this pumps.
      const tokens = AppTokens.profoundVerdant;
      final glyph = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('Unprinted receipts')),
          matching: find.byType(Icon),
        ),
      );
      expect(glyph.color, isNot(tokens.colors.status.problem.fg));
    });

    test('phones use a four-across launcher grid', () {
      expect(HomeModuleGrid.columnsFor(411), 4);
      expect(HomeModuleGrid.columnsFor(767), 4);
      expect(HomeModuleGrid.columnsFor(768), 2);
      expect(HomeModuleGrid.columnsFor(1024), 3);
    });

    testWidgets('phone modules are icon-and-title launchers only', (
      tester,
    ) async {
      final destinations = <HomeDestination>[
        _destination(
          'New sale',
          isPrimary: true,
          description: 'Process a transaction.',
          status: 'Ready',
        ),
        for (var index = 1; index <= 7; index++)
          _destination('Destination $index'),
      ];

      await _pump(
        tester,
        HomeModuleGrid(destinations: destinations),
        width: 411,
      );

      expect(find.text('Process a transaction.'), findsNothing);
      expect(find.text('Ready'), findsNothing);
      expect(
        find.byKey(const ValueKey('home-module-icon-New sale')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('New sale'))).dy,
        tester.getTopLeft(find.byKey(const ValueKey('Destination 3'))).dy,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('Destination 4'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('New sale'))).dy,
        ),
      );

      final firstIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('home-module-icon-New sale')),
          matching: find.byType(Icon),
        ),
      );
      final secondIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('home-module-icon-Destination 1')),
          matching: find.byType(Icon),
        ),
      );
      expect(firstIcon.color, isNot(secondIcon.color));
    });

    testWidgets('larger modules retain descriptions and shadowed card edges', (
      tester,
    ) async {
      await _pump(
        tester,
        HomeModuleGrid(
          destinations: <HomeDestination>[
            _destination(
              'New sale',
              isPrimary: true,
              description: 'Process a transaction.',
            ),
          ],
        ),
        width: 834,
      );

      expect(find.text('Process a transaction.'), findsOneWidget);
      final decorated = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(const ValueKey('New sale')),
              matching: find.byType(Container),
            ),
          )
          .map((container) => container.decoration)
          .whereType<BoxDecoration>();
      final card = decorated.firstWhere(
        (decoration) => decoration.boxShadow?.isNotEmpty ?? false,
      );
      expect(card.color, _tokens.colors.surface.raised);
      expect(card.border, isNotNull);
    });
  });

  group('two hosts, one set of rows', () {
    test('the menu column is the export\'s own width', () {
      // `w-72` in the sidebar the design draws. It was 256 while this
      // component had no picture to measure against.
      expect(HomeNavigation.menuWidth, 288);
    });

    test('the persistent column starts exactly at §4.1\'s expanded floor', () {
      expect(HomeNavigation.showsMenu(1023), isFalse);
      expect(HomeNavigation.showsMenu(1024), isTrue);
      // The same floor `AppLayout` declares, rather than a second opinion
      // about where a desktop starts.
      expect(
        HomeNavigation.showsMenu(AppLayout.contract.expandedFloor),
        isTrue,
      );
    });

    testWidgets('the drawer draws its rows at every width', (tester) async {
      // **Unlike the frame's column, this one is not gated.** `AppScaffold`
      // decides whether to build a drawer at all from the width it has; a
      // `Drawer` that rendered nothing would still be openable, and an empty
      // panel sliding in is worse than no hamburger.
      for (final width in <double>[411, 834, 1023, 1440]) {
        await _pump(
          tester,
          HomeNavigation.drawer(destinations: _eight()),
          width: width,
        );
        expect(
          find.byType(PressSurface),
          findsNWidgets(8),
          reason: 'the drawer drew nothing at $width',
        );
      }
    });

    testWidgets('the frame\'s column draws nothing below expanded', (
      tester,
    ) async {
      for (final width in <double>[411, 834, 1023]) {
        await _pump(
          tester,
          HomeNavigation.menu(destinations: _eight()),
          width: width,
        );

        expect(
          find.byType(PressSurface),
          findsNothing,
          reason: 'the column drew at $width',
        );
      }
    });

    testWidgets('and draws every destination at expanded', (tester) async {
      await _pump(
        tester,
        HomeNavigation.menu(destinations: _eight()),
        width: 1440,
      );

      // Every destination is still reachable - the whole argument for a menu
      // over the export's four-slot bottom bar is that nothing goes into an
      // overflow bucket.
      for (var index = 1; index <= 7; index++) {
        expect(find.byKey(ValueKey('Destination $index')), findsOne);
      }
      // One per row, which is what makes it a menu rather than a grid.
      expect(
        _rectOf(tester, 'Destination 2').top,
        greaterThan(_rectOf(tester, 'Destination 1').top),
      );
      expect(
        _rectOf(tester, 'Destination 1').left,
        _rectOf(tester, 'Destination 2').left,
      );
    });

    testWidgets('no destinations draws nothing at all', (tester) async {
      await _pump(tester, const HomeNavigation.drawer(destinations: []));

      expect(find.byType(PressSurface), findsNothing);
    });
  });

  group('hierarchy', () {
    testWidgets('the primary is first, however it was listed', (tester) async {
      await _pump(
        tester,
        HomeNavigation.drawer(
          destinations: <HomeDestination>[
            _destination('Destination 1'),
            _destination('New sale', isPrimary: true),
          ],
        ),
      );

      expect(
        _rectOf(tester, 'New sale').top,
        lessThan(_rectOf(tester, 'Destination 1').top),
      );
    });

    testWidgets('the primary is marked by a surface and an accent bar', (
      tester,
    ) async {
      // **Not a filled block.** The export's sidebar marks the current
      // destination with its own surface and a four-pixel accent edge, which
      // is also the design system's own words for a selection - "a sharp
      // vertical bar (4px wide) ... in Primary Green". A filled row would be
      // the accent container, and that is what a *button* is.
      await _pump(tester, HomeNavigation.drawer(destinations: _eight()));

      final decoration =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byKey(const ValueKey('New sale')),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;

      expect(decoration.color, _tokens.colors.surface.field);
      expect(
        (decoration.border! as BorderDirectional).end.color,
        _tokens.colors.action.primary.container,
      );
      expect(
        (decoration.border! as BorderDirectional).end.width,
        _tokens.spacing.s4,
      );
      // The label goes with it, so the mark is never hue alone.
      expect(
        tester.widget<Text>(find.text('New sale')).style!.color,
        _tokens.colors.action.primary.container,
      );
    });

    testWidgets('an ordinary row is unfilled and every row is one width', (
      tester,
    ) async {
      await _pump(
        tester,
        HomeNavigation.drawer(
          destinations: <HomeDestination>[
            _destination('Short'),
            _destination(
              'A destination with a considerably longer label than its neighbour',
            ),
          ],
        ),
      );

      final short = _rectOf(tester, 'Short');
      final long = _rectOf(
        tester,
        'A destination with a considerably longer label than its neighbour',
      );

      expect(short.width, closeTo(long.width, 0.5));
      expect(short.left, long.left);
    });
  });

  group('state matrix', () {
    testWidgets('a destination with no callback is disabled, not hidden', (
      tester,
    ) async {
      await _pump(
        tester,
        HomeNavigation.drawer(
          destinations: <HomeDestination>[
            _destination('Default business', enabled: false),
          ],
        ),
      );

      expect(find.text('Default business'), findsOne);
      final press = tester.widget<PressSurface>(
        find.byKey(const ValueKey('Default business')),
      );
      expect(press.onPressed, isNull);
    });

    testWidgets('a disabled label is §2.1\'s disabled colour', (tester) async {
      await _pump(
        tester,
        HomeNavigation.drawer(
          destinations: <HomeDestination>[
            _destination('Default business', enabled: false),
          ],
        ),
      );

      expect(
        tester.widget<Text>(find.text('Default business')).style!.color,
        _tokens.colors.text.disabled,
      );
    });

    testWidgets('an enabled destination reports its press', (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        HomeNavigation.drawer(
          destinations: <HomeDestination>[
            HomeDestination(
              destinationKey: const ValueKey('open'),
              label: 'Open',
              icon: Icons.inventory_2_outlined,
              onPressed: () => pressed++,
            ),
          ],
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();

      expect(pressed, 1);
    });

    testWidgets('every row clears §9\'s tap target', (tester) async {
      await _pump(tester, HomeNavigation.drawer(destinations: _eight()));

      for (var index = 1; index <= 7; index++) {
        expect(
          _rectOf(tester, 'Destination $index').height,
          greaterThanOrEqualTo(_tokens.density.minimumTapTarget.height),
          reason: 'Destination $index is under the target',
        );
      }
    });
  });

  group('a row states its own condition', () {
    testWidgets('the condition sits at the trailing edge of its row', (
      tester,
    ) async {
      await _pump(
        tester,
        HomeNavigation.drawer(
          destinations: <HomeDestination>[
            _destination('Money', status: '3 unresolved differences'),
          ],
        ),
      );

      expect(find.text('3 unresolved differences'), findsOne);
      expect(
        tester.getTopLeft(find.text('3 unresolved differences')).dx,
        greaterThan(tester.getTopLeft(find.text('Money')).dx),
      );
    });

    testWidgets('a screen reader is given the label and the condition once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        HomeNavigation.drawer(
          destinations: <HomeDestination>[
            _destination('Money', status: '3 unresolved differences'),
          ],
        ),
      );

      expect(
        find.bySemanticsLabel('Money. 3 unresolved differences'),
        findsOne,
      );
      handle.dispose();
    });
  });

  group('areas - the menu rather than the list', () {
    List<HomeDestination> owner() => <HomeDestination>[
      _destination('New sale', isPrimary: true),
      _destination('Find a receipt', group: 'Sales'),
      _destination('Receipts waiting', group: 'Sales'),
      _destination('Manage catalog', group: 'Inventory'),
      _destination('Checkout settings', group: 'Settings'),
      _destination('Printer', group: 'Settings'),
    ];

    testWidgets('an area is named once, however many rows it holds', (
      tester,
    ) async {
      await _pump(tester, HomeNavigation.drawer(destinations: owner()));

      // Two rows of Sales and two of Settings, one heading each.
      expect(find.text('SALES'), findsOne);
      expect(find.text('SETTINGS'), findsOne);
      expect(find.text('INVENTORY'), findsOne);
    });

    testWidgets('a heading sits above the first row that carries it', (
      tester,
    ) async {
      await _pump(tester, HomeNavigation.drawer(destinations: owner()));

      expect(
        tester.getTopLeft(find.text('SALES')).dy,
        lessThan(tester.getTopLeft(find.text('Find a receipt')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Find a receipt')).dy,
        lessThan(tester.getTopLeft(find.text('INVENTORY')).dy),
      );
    });

    testWidgets('the primary outranks every heading', (tester) async {
      await _pump(tester, HomeNavigation.drawer(destinations: owner()));

      expect(
        tester.getTopLeft(find.text('New sale')).dy,
        lessThan(tester.getTopLeft(find.text('SALES')).dy),
      );
    });

    // **The property the whole grouping rests on.** A cashier is not given the
    // settings rows, so a cashier must not be shown a Settings heading with
    // nothing under it - and no role list is consulted here to achieve it.
    testWidgets('an area nobody was given is not named at all', (tester) async {
      await _pump(
        tester,
        HomeNavigation.drawer(
          destinations: <HomeDestination>[
            _destination('New sale', isPrimary: true),
            _destination('Find a receipt', group: 'Sales'),
          ],
        ),
      );

      expect(find.text('SALES'), findsOne);
      expect(find.text('SETTINGS'), findsNothing);
      expect(find.text('INVENTORY'), findsNothing);
    });

    testWidgets('an ungrouped list draws no headings and still draws rows', (
      tester,
    ) async {
      await _pump(tester, HomeNavigation.drawer(destinations: _eight()));

      expect(find.text('Destination 1'), findsOne);
      expect(find.byType(PressSurface), findsNWidgets(8));
    });

    // §9: a heading is a landmark, not a stop. Six unreachable buttons in front
    // of *New sale* would be worse than no grouping at all.
    testWidgets('a heading announces as a header and not as a control', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, HomeNavigation.drawer(destinations: owner()));

      expect(
        tester.getSemantics(find.text('SALES')),
        matchesSemantics(label: 'SALES', isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('the persistent column groups exactly as the drawer does', (
      tester,
    ) async {
      await _pump(
        tester,
        HomeNavigation.menu(destinations: owner()),
        width: 1280,
      );

      expect(find.text('SALES'), findsOne);
      expect(find.text('SETTINGS'), findsOne);
      expect(
        tester.getTopLeft(find.text('SALES')).dy,
        lessThan(tester.getTopLeft(find.text('Find a receipt')).dy),
      );
    });
  });

  // `docs/stitch/OPEN_QUESTIONS.md` decision 37.
  group('pressing a module card tints it rather than covering it', () {
    testWidgets('the overlay is translucent on every tier', (tester) async {
      // **The defect this pins was invisible online.** A tap normally navigates
      // within a frame or two, so nobody saw the pressed state; a device with
      // no network holds on the tap, and the card became a solid green
      // rectangle with its glyph and its label hidden behind it.
      await _pump(
        tester,
        HomeModuleGrid(
          destinations: <HomeDestination>[
            _destination('New sale'),
            _destination('Sales'),
          ],
        ),
        width: 411,
      );

      for (final surface in tester.widgetList<PressSurface>(
        find.byType(PressSurface),
      )) {
        for (final overlay in <Color?>[
          surface.hoverOverlay,
          surface.pressedOverlay,
        ]) {
          expect(overlay, isNotNull);
          // Opaque means it hides whatever it is stacked on, which for a card
          // is the entire card.
          expect(overlay!.a, lessThan(1), reason: 'overlay must be a wash');
        }
      }
    });
  });
}
