import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/home_navigation.dart';
import 'package:flutter_application_1/ui/press.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

const _tokens = AppTokens.dark;

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
}) => HomeDestination(
  destinationKey: ValueKey(label),
  label: label,
  icon: Icons.inventory_2_outlined,
  status: status,
  isPrimary: isPrimary,
  onPressed: enabled ? () {} : null,
);

List<HomeDestination> _eight() => <HomeDestination>[
  _destination('New sale', isPrimary: true),
  for (var index = 1; index <= 7; index++) _destination('Destination $index'),
];

/// The **painted** card, not the slot it sits in.
///
/// `PressSurface` shrink-wraps unless told otherwise, so its own render box can
/// be the full width of a `Row` slot while the card inside it floats in the
/// middle at its intrinsic size. Measuring the key measured the slot and passed
/// while the primary card was drawn at 40% of the row - the screenshot is what
/// caught it. Every dimension asserted here is the container that actually gets
/// painted.
Rect _rectOf(WidgetTester tester, String label) => tester.getRect(
  find
      .descendant(
        of: find.byKey(ValueKey(label)),
        matching: find.byType(Container),
      )
      .first,
);

void main() {
  group('§4.4 bands', () {
    test('a phone gets two columns and a tablet three', () {
      expect(HomeNavigation.columnsFor(AppBreakpoint.compact), 2);
      expect(HomeNavigation.columnsFor(AppBreakpoint.medium), 3);
    });

    test('the menu starts exactly at §4.1\'s expanded floor', () {
      expect(HomeNavigation.showsMenu(1023), isFalse);
      expect(HomeNavigation.showsMenu(1024), isTrue);
      // The same floor `AppLayout` declares, rather than a second opinion
      // about where a desktop starts.
      expect(HomeNavigation.showsMenu(AppLayout.contract.expandedFloor), isTrue);
    });

    testWidgets('a phone lays the ordinary cards two to a row', (tester) async {
      await _pump(tester, HomeNavigation.cards(destinations: _eight()));

      final first = _rectOf(tester, 'Destination 1');
      final second = _rectOf(tester, 'Destination 2');
      final third = _rectOf(tester, 'Destination 3');

      expect(first.top, second.top);
      expect(second.left, greaterThan(first.left));
      expect(third.top, greaterThan(first.top));
    });

    testWidgets('a tablet lays them three to a row', (tester) async {
      await _pump(tester, HomeNavigation.cards(destinations: _eight()), width: 834);

      expect(_rectOf(tester, 'Destination 1').top, _rectOf(tester, 'Destination 3').top);
      expect(
        _rectOf(tester, 'Destination 4').top,
        greaterThan(_rectOf(tester, 'Destination 1').top),
      );
    });

    testWidgets('a desktop draws the menu instead of the grid', (tester) async {
      await _pump(tester, HomeNavigation.menu(destinations: _eight()), width: 1440);

      // Every destination is still reachable - the menu's whole argument over a
      // bottom bar is that nothing goes into an overflow bucket.
      for (var index = 1; index <= 7; index++) {
        expect(find.byKey(ValueKey('Destination $index')), findsOne);
      }
      // One per row, which is what makes it a menu rather than a grid.
      expect(
        _rectOf(tester, 'Destination 2').top,
        greaterThan(_rectOf(tester, 'Destination 1').top),
      );
      expect(_rectOf(tester, 'Destination 1').left, _rectOf(tester, 'Destination 2').left);
    });
  });

  group('two hosts, and exactly one of them draws at any width', () {
    // §4.4 puts the menu in the frame and the cards in the page, so the two
    // constructors have to partition every width between them. Both halves are
    // asserted: a host that drew in the wrong band would put the destinations
    // on screen twice at 1024, and one that drew in neither would lose them.
    testWidgets('the page draws nothing at expanded', (tester) async {
      await _pump(
        tester,
        HomeNavigation.cards(destinations: _eight()),
        width: 1440,
      );

      expect(find.byType(PressSurface), findsNothing);
    });

    testWidgets('the frame draws nothing below expanded', (tester) async {
      for (final width in <double>[411, 834, 1023]) {
        await _pump(
          tester,
          HomeNavigation.menu(destinations: _eight()),
          width: width,
        );

        expect(
          find.byType(PressSurface),
          findsNothing,
          reason: 'the menu drew at $width',
        );
      }
    });

    testWidgets('every destination is drawn exactly once at every band', (
      tester,
    ) async {
      for (final width in <double>[411, 834, 1023, 1024, 1440]) {
        await _pump(
          tester,
          Column(
            children: <Widget>[
              HomeNavigation.cards(destinations: _eight()),
              HomeNavigation.menu(destinations: _eight()),
            ],
          ),
          width: width,
        );

        expect(
          find.byType(PressSurface),
          findsNWidgets(8),
          reason: 'both hosts mounted at $width',
        );
      }
    });
  });

  group('§4.4 hierarchy', () {
    testWidgets('the primary is first and spans the row', (tester) async {
      await _pump(tester, HomeNavigation.cards(destinations: _eight()));

      final primary = _rectOf(tester, 'New sale');
      final first = _rectOf(tester, 'Destination 1');
      final second = _rectOf(tester, 'Destination 2');

      expect(primary.top, lessThan(first.top));
      expect(primary.width, greaterThan(first.width));
      // Spanning means it covers both columns, not merely that it is wider.
      expect(primary.right, closeTo(second.right, 0.5));
    });

    testWidgets('the primary is hoisted even when it is listed last', (
      tester,
    ) async {
      await _pump(
        tester,
        HomeNavigation.cards(
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

    testWidgets('the primary carries §2.1\'s primary container', (tester) async {
      await _pump(tester, HomeNavigation.cards(destinations: _eight()));

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

      expect(decoration.color, _tokens.colors.action.primary.container);
    });

    testWidgets('cards in a row are the same width and the same height', (
      tester,
    ) async {
      await _pump(
        tester,
        HomeNavigation.cards(
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
      expect(short.height, closeTo(long.height, 0.5));
    });
  });

  group('state matrix', () {
    testWidgets('a destination with no callback is disabled, not hidden', (
      tester,
    ) async {
      await _pump(
        tester,
        HomeNavigation.cards(
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
        HomeNavigation.cards(
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
        HomeNavigation.cards(
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

    testWidgets('no destinations draws nothing at all', (tester) async {
      await _pump(tester, const HomeNavigation.cards(destinations: []));

      expect(find.byType(PressSurface), findsNothing);
    });
  });

  group('a card states its own condition', () {
    testWidgets('the status line is drawn under the label', (tester) async {
      await _pump(
        tester,
        HomeNavigation.cards(
          destinations: <HomeDestination>[
            _destination('Money', status: '3 unresolved differences'),
          ],
        ),
      );

      expect(find.text('3 unresolved differences'), findsOne);
      expect(
        tester.getTopLeft(find.text('3 unresolved differences')).dy,
        greaterThan(tester.getTopLeft(find.text('Money')).dy),
      );
    });

    testWidgets('a screen reader is given the label and the condition once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        HomeNavigation.cards(
          destinations: <HomeDestination>[
            _destination('Money', status: '3 unresolved differences'),
          ],
        ),
      );

      // One node carrying both, rather than the label and the status announced
      // as two unrelated strings - and the inner `Text`s excluded so the pair is
      // not read twice.
      expect(
        find.bySemanticsLabel('Money. 3 unresolved differences'),
        findsOne,
      );
      handle.dispose();
    });

    testWidgets('a destination with no condition announces only its label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        HomeNavigation.cards(
          destinations: <HomeDestination>[_destination('Stock')],
        ),
      );

      expect(find.bySemanticsLabel('Stock'), findsOne);
      handle.dispose();
    });
  });

  group('§9', () {
    testWidgets('every destination clears the 48dp target at every band', (
      tester,
    ) async {
      for (final width in <double>[411, 834, 1440]) {
        await _pump(
          tester,
          // Whichever host that band draws in. §9 is about what a finger can
          // hit, and a menu row is as much a target as a card is.
          HomeNavigation.showsMenu(width)
              ? HomeNavigation.menu(destinations: _eight())
              : HomeNavigation.cards(destinations: _eight()),
          width: width,
        );

        for (var index = 1; index <= 7; index++) {
          final rect = _rectOf(tester, 'Destination $index');
          expect(
            rect.height,
            greaterThanOrEqualTo(48),
            reason: 'Destination $index at $width',
          );
          expect(
            rect.width,
            greaterThanOrEqualTo(48),
            reason: 'Destination $index at $width',
          );
        }
      }
    });

    testWidgets('a card grows with the text rather than clipping it', (
      tester,
    ) async {
      await _pump(tester, HomeNavigation.cards(destinations: _eight()));
      final before = _rectOf(tester, 'Destination 1').height;

      await _pump(
        tester,
        HomeNavigation.cards(destinations: _eight()),
        textScale: 2,
      );

      expect(_rectOf(tester, 'Destination 1').height, greaterThan(before));
      expect(tester.takeException(), isNull);
    });
  });
}
