import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/measure.dart';
import 'package:uzapay_pos/ui/tabs.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tokens = spiritTheme.extension<AppTokens>()!;
  final colors = tokens.colors;

  group('AppTabs, two tabs: the switch', () {
    testWidgets('is 48 high, and so is every tab in it', (tester) async {
      // §9's touch-target row is pass/fail at 48. `TabBar` used to add its
      // indicator weight under a 48 tab, for a 50-high strip.
      await _pump(tester, const <String>['First', 'Second']);

      expect(AppTabs.height, AppDensity.comfortable.minimumTapTarget.height);
      expect(tester.getSize(find.byType(TabBar)).height, AppTabs.height);
      for (final label in const <String>['First', 'Second']) {
        expect(
          tester.getSize(_tab(label)).height,
          greaterThanOrEqualTo(48),
          reason: label,
        );
      }
    });

    testWidgets('says which half is selected with the thumb and the label', (
      tester,
    ) async {
      // §9: never hue alone. The thumb is a shape, and the label steps up.
      await _pump(tester, const <String>['First', 'Second']);

      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.isScrollable, isFalse);
      expect(bar.labelColor, colors.text.primary);
      expect(bar.unselectedLabelColor, colors.text.secondary);
      expect(_mark(tester), paints..rrect(color: colors.surface.selected));
    });

    testWidgets('fills the width on a phone, inside the inset it is given', (
      tester,
    ) async {
      await _pump(
        tester,
        const <String>['First', 'Second'],
        size: const Size(411, 800),
        inset: 16,
      );

      expect(tester.getSize(find.byType(TabBar)).width, 411 - 2 * 16);
      expect(tester.getTopLeft(find.byType(TabBar)).dx, 16);
    });

    testWidgets('is as wide as its labels need from the medium band up', (
      tester,
    ) async {
      // Each half is the wider label and `space.24` a side, so the two stay
      // equal and a thumb's width apart rather than a column's.
      await _pump(tester, const <String>[
        'Network',
        'Bluetooth',
      ], size: const Size(1024, 800));

      final widest = measureTextWidth('Bluetooth', _style(tokens));
      expect(
        tester.getSize(find.byType(TabBar)).width,
        closeTo(2 * (widest + 2 * tokens.spacing.s24), 0.01),
      );
      expect(tester.getTopLeft(find.byType(TabBar)).dx, 0);
    });

    testWidgets('wraps a long label onto two lines rather than cutting it', (
      tester,
    ) async {
      // The test font draws every glyph a full em wide, so at 200% these are
      // far wider than half a phone and have to wrap.
      await _pump(
        tester,
        const <String>['One two', 'Three four'],
        size: const Size(411, 800),
        textScaler: const TextScaler.linear(2),
      );

      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.isScrollable, isFalse);
      expect(tester.takeException(), isNull);
      // Two 40-high lines and `space.12` above and below.
      expect(tester.getSize(find.byType(TabBar)).height, 2 * 40 + 2 * 12);
    });

    testWidgets('gives way to a scrolling strip when a word cannot fit', (
      tester,
    ) async {
      await _pump(
        tester,
        const <String>['Settings', 'Acknowledgements'],
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
    });
  });

  group('AppTabs, three or more: icon tabs', () {
    const labels = <String>['Currency', 'Stock counts', 'Agreed prices'];
    const icons = <IconData>[
      Icons.payments_outlined,
      Icons.assignment_outlined,
      Icons.handshake_outlined,
    ];

    testWidgets(
      'packs the tabs from the start and scrolls where they overrun',
      (tester) async {
        await _pump(tester, labels, icons: icons, size: const Size(320, 640));

        final bar = tester.widget<TabBar>(find.byType(TabBar));
        expect(bar.isScrollable, isTrue);
        expect(bar.tabAlignment, TabAlignment.start);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('selects in the accent, and rests on the floor colour', (
      tester,
    ) async {
      await _pump(tester, labels, icons: icons);

      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.labelColor, colors.action.primary.container);
      expect(bar.unselectedLabelColor, colors.text.tertiary);
      expect(
        _mark(tester),
        paints..rrect(color: colors.action.primary.container),
      );
    });

    testWidgets('draws each tab its glyph, at the row size', (tester) async {
      await _pump(tester, labels, icons: icons);

      for (final icon in icons) {
        expect(tester.widget<Icon>(find.byIcon(icon)).size, tokens.icons.row);
      }
    });

    testWidgets('lines the first glyph up with the page it sits over', (
      tester,
    ) async {
      await _pump(tester, labels, icons: icons, inset: 20);

      expect(tester.getTopLeft(find.byIcon(icons.first)).dx, 20);
    });

    testWidgets('a strip without glyphs is labels alone', (tester) async {
      await _pump(tester, labels);

      expect(find.byType(Icon), findsNothing);
    });
  });

  group('AppTabs, either shape', () {
    testWidgets('a tap still selects, through TabBar', (tester) async {
      // Hard rule 1: the restyle moves no behaviour. `TabBar` still owns the
      // handshake with the controller.
      for (final labels in const <List<String>>[
        <String>['First', 'Second'],
        <String>['First', 'Second', 'Third'],
      ]) {
        await _pump(tester, labels);
        await tester.tap(find.text('Second'));
        await tester.pumpAndSettle();

        final controller = DefaultTabController.of(
          tester.element(find.byType(TabBar)),
        );
        expect(controller.index, 1, reason: '${labels.length} tabs');
      }
    });

    testWidgets('a retarget mid-flight settles, with nothing left running', (
      tester,
    ) async {
      // Two taps inside one spring: the second takes over from where the
      // first has got to, and the strip still comes to rest.
      await _pump(tester, const <String>['First', 'Second', 'Third']);
      await tester.tap(find.text('Third'));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();

      expect(
        DefaultTabController.of(tester.element(find.byType(TabBar))).index,
        1,
      );
    });

    testWidgets('draws the focus ring for a keyboard, and only for one', (
      tester,
    ) async {
      await _pump(tester, const <String>['First', 'Second']);
      expect(_rings(tester, colors), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(_rings(tester, colors), findsOneWidget);
    });

    testWidgets('sets its labels in label.md, with no tracking borrowed', (
      tester,
    ) async {
      // `TabBar` merges its style onto Material's own tab label, which is
      // tracked; the role names none, and none is what it means.
      await _pump(tester, const <String>['First', 'Second']);

      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.labelStyle, _style(tokens));
      expect(bar.unselectedLabelStyle, _style(tokens));
      expect(bar.labelStyle!.letterSpacing, 0);
    });
  });
}

TextStyle _style(AppTokens tokens) {
  final role = tokens.typography.labelMedium;
  return role.copyWith(letterSpacing: role.letterSpacing ?? 0);
}

Finder _tab(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell));

RenderObject _mark(WidgetTester tester) => tester.renderObject(
  find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter.runtimeType.toString() == '_MarkPainter',
  ),
);

Finder _rings(WidgetTester tester, AppColorRoles colors) =>
    find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) return false;
      final decoration = widget.decoration;
      if (decoration is! ShapeDecoration) return false;
      final shape = decoration.shape;
      final side = switch (shape) {
        StadiumBorder(:final side) => side,
        RoundedRectangleBorder(:final side) => side,
        _ => BorderSide.none,
      };
      return side.color == colors.action.focusRing.color &&
          side.width == colors.action.focusRing.width;
    });

Future<void> _pump(
  WidgetTester tester,
  List<String> labels, {
  List<IconData>? icons,
  Size size = const Size(800, 600),
  double inset = 0,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: DefaultTabController(
            // A fresh controller per pump, for a test that pumps twice.
            key: ValueKey<int>(labels.length),
            length: labels.length,
            child: Scaffold(
              body: Column(
                children: <Widget>[
                  AppTabs(tabs: labels, icons: icons, inset: inset),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
