import 'package:flutter/material.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/chips.dart';
import 'package:uzapay_pos/ui/press.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FilterChipBar', () {
    testWidgets('changes form at §4.3s band and not at a width of its own', (
      tester,
    ) async {
      // §4.3: "horizontal scroll, one line" at compact, "wrap" at medium and
      // expanded. The boundary is §4.1's `medium` floor rather than a figure
      // this component picked.
      expect(FilterChipBar.scrollsInOneLine(767), isTrue);
      expect(FilterChipBar.scrollsInOneLine(768), isFalse);
      expect(FilterChipBar.scrollsInOneLine(1024), isFalse);

      await _pump(tester, size: const Size(411, 800));
      expect(find.byType(SingleChildScrollView), findsOne);
      expect(find.byType(Wrap), findsNothing);

      await _pump(tester, size: const Size(900, 800));
      expect(find.byType(Wrap), findsOne);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('marks the selection with a glyph and not only a fill', (
      tester,
    ) async {
      // §9: never by hue alone. Whether a list is filtered is the most
      // consequential thing this row says, and a reader who cannot separate the
      // mint from the ground would otherwise have nothing to read it by.
      await _pump(tester, selected: 'drinks');

      expect(find.byIcon(Icons.check), findsOne);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.check)).size,
        FilterChipBar.glyphSize,
      );
    });

    testWidgets('a bar with no "everything" chip can have nothing selected', (
      tester,
    ) async {
      // **The till's tender chooser, which is the case that proves the two
      // nulls are different.** A filter's null is "no filter" and is drawn as a
      // selected "Everything" chip; the tender's null means *nothing has been
      // observed yet*, deliberately, because a pre-selected payment method
      // would be indistinguishable from one somebody looked at. So this bar
      // offers no null option and shows no glyph until a person picks.
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: const Scaffold(
            body: FilterChipBar<String>(
              selected: null,
              onSelected: _ignore,
              options: <FilterChipOption<String>>[
                FilterChipOption<String>(value: 'cash', label: 'Cash'),
                FilterChipOption<String>(value: 'card', label: 'Card'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('an "everything" chip is selected when nothing is filtered', (
      tester,
    ) async {
      // The other null, and it is drawn rather than implied: a filter bar
      // showing no mark anywhere would leave "you are seeing all of it"
      // indistinguishable from "this control does nothing".
      await _pump(tester, selected: null);

      expect(find.byIcon(Icons.check), findsOne);
    });

    testWidgets('answers with the value it was given, including null', (
      tester,
    ) async {
      // A filter's null means "no filter" and the till's tender null means
      // "nothing observed yet". The component carries whichever the caller
      // meant rather than inventing a default for either.
      final answers = <String?>[];
      await _pump(tester, selected: 'drinks', onSelected: answers.add);

      await tester.tap(find.text('Everything'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bakery'));
      await tester.pumpAndSettle();

      expect(answers, <String?>[null, 'bakery']);
    });

    testWidgets('a disabled chip cannot be pressed', (tester) async {
      final answers = <String?>[];
      await _pump(tester, onSelected: answers.add, disable: 'bakery');

      await tester.tap(find.text('Bakery'));
      await tester.pumpAndSettle();

      expect(answers, isEmpty);
    });

    testWidgets('keeps §9s tap target however short the word is', (
      tester,
    ) async {
      // §5.2 gives this component 32 of painted height and §9 gives every
      // control 48 of hit area, exactly as `AppButton.sm` reconciles the two.
      await _pump(tester, size: const Size(900, 800));

      final surface = tester
          .widgetList<PressSurface>(find.byType(PressSurface))
          .first;
      expect(surface.onPressed, isNotNull);
      final size = tester.getSize(find.byType(PressSurface).first);
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets(
      'takes the design\'s rounded-full, which is 12 and not a pill',
      (tester) async {
        await _pump(tester, size: const Size(900, 800));

        final tokens = spiritTheme.extension<AppTokens>()!;
        final decorated = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .where((d) => d.borderRadius != null);
        // A selectable chip in the export is `px-3 py-1.5 rounded-full`, and
        // the served config resolves `full` to `0.75rem` - so 12 on a ~30-high
        // chip is a soft rectangle rather than a capsule. `radius.lg` is that
        // value. `StatusBadge` carried the bare `rounded` the export draws in
        // 78 of 82 places until 2026-08-26, when the product owner moved it to
        // `radius.md` - still not a capsule, and no longer sharper than the
        // card it sits inside.
        expect(
          decorated.first.borderRadius,
          BorderRadius.circular(tokens.radius.lg),
        );
        expect(
          decorated.first.borderRadius,
          isNot(BorderRadius.circular(tokens.radius.pill)),
        );
      },
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  String? selected,
  ValueChanged<String?>? onSelected,
  Size size = const Size(411, 800),
  String? disable,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: FilterChipBar<String>(
          semanticLabel: 'Filter by category',
          selected: selected,
          onSelected: onSelected ?? (_) {},
          options: <FilterChipOption<String>>[
            const FilterChipOption<String>(value: null, label: 'Everything'),
            const FilterChipOption<String>(value: 'drinks', label: 'Drinks'),
            FilterChipOption<String>(
              value: 'bakery',
              label: 'Bakery',
              enabled: disable != 'bakery',
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _ignore(String? _) {}
