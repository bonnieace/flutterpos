import 'dart:ui' show CheckedState, SemanticsFlags, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uzapay_pos/ui/choice.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Pace { slow, steady, fast }

const List<ChoiceCardOption<_Pace>> _options = <ChoiceCardOption<_Pace>>[
  ChoiceCardOption<_Pace>(
    key: ValueKey('pace-slow'),
    value: _Pace.slow,
    title: 'Slow',
    description: 'Nothing is rushed.',
  ),
  ChoiceCardOption<_Pace>(
    key: ValueKey('pace-steady'),
    value: _Pace.steady,
    title: 'Steady',
    description: 'The usual.',
    detailIcon: Icons.info_outline,
    detail: <ChoiceDetailRun>[
      ChoiceDetailRun('Shown as '),
      ChoiceDetailRun('Steady', emphasis: true),
    ],
  ),
  ChoiceCardOption<_Pace>(
    key: ValueKey('pace-fast'),
    value: _Pace.fast,
    title: 'Fast',
    description: 'Everything at once.',
  ),
];

void main() {
  group('ChoiceCardGroup', () {
    testWidgets('every option states what it does, chosen or not', (
      tester,
    ) async {
      await _pumpGroup(tester, selected: _Pace.steady);

      for (final option in _options) {
        expect(find.text(option.title), findsOneWidget);
        expect(find.text(option.description!), findsOneWidget);
      }
    });

    testWidgets('an option with no description is its title alone', (
      tester,
    ) async {
      await tester.pumpWidget(
        _frame(
          ChoiceCardGroup<_Pace>(
            semanticLabel: 'Pace',
            options: const <ChoiceCardOption<_Pace>>[
              ChoiceCardOption<_Pace>(
                key: ValueKey('pace-slow'),
                value: _Pace.slow,
                title: 'Slow',
              ),
              ChoiceCardOption<_Pace>(
                key: ValueKey('pace-fast'),
                value: _Pace.fast,
                title: 'Fast',
              ),
            ],
            selected: _Pace.slow,
            onSelected: (_) {},
          ),
        ),
      );

      final card = find.byKey(const ValueKey('pace-fast'));
      expect(
        find.descendant(of: card, matching: find.byType(Text)),
        findsOneWidget,
      );
      // Still a choice a screen reader can make, named by its title.
      expect(_flags(tester, 'pace-fast').isInMutuallyExclusiveGroup, isTrue);
    });

    testWidgets('the chosen card is checked in one exclusive group', (
      tester,
    ) async {
      await _pumpGroup(tester, selected: _Pace.steady);

      final steady = _flags(tester, 'pace-steady');
      expect(steady.isChecked, CheckedState.isTrue);
      expect(steady.isInMutuallyExclusiveGroup, isTrue);
      expect(_flags(tester, 'pace-fast').isChecked, CheckedState.isFalse);
    });

    testWidgets('a tap chooses', (tester) async {
      _Pace? chosen;
      await _pumpGroup(
        tester,
        selected: _Pace.slow,
        onSelected: (value) => chosen = value,
      );

      await tester.tap(find.byKey(const ValueKey('pace-fast')));
      await tester.pump();

      expect(chosen, _Pace.fast);
    });

    testWidgets('arrow keys move the choice and the focus with it', (
      tester,
    ) async {
      var selected = _Pace.slow;
      await tester.pumpWidget(
        _frame(
          StatefulBuilder(
            builder: (context, setState) => ChoiceCardGroup<_Pace>(
              semanticLabel: 'Pace',
              options: _options,
              selected: selected,
              onSelected: (value) => setState(() => selected = value),
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected, _Pace.steady);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected, _Pace.fast);

      // It wraps, as a radio group does.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected, _Pace.slow);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(selected, _Pace.fast);
    });

    testWidgets('read-only draws only the chosen card, and nothing to press', (
      tester,
    ) async {
      await _pumpGroup(tester, selected: _Pace.steady, readOnly: true);

      expect(find.text('Steady'), findsOneWidget);
      expect(find.text('Slow'), findsNothing);
      expect(find.text('Fast'), findsNothing);
      expect(_flags(tester, 'pace-steady').isButton, isFalse);
    });

    testWidgets('the selection edge does not move the text', (tester) async {
      await _pumpGroup(tester, selected: _Pace.slow);
      final before = tester.getTopLeft(find.text('Fast'));

      await tester.pumpWidget(
        _frame(
          ChoiceCardGroup<_Pace>(
            semanticLabel: 'Pace',
            options: _options,
            selected: _Pace.fast,
            onSelected: (_) {},
          ),
        ),
      );

      expect(tester.getTopLeft(find.text('Fast')), before);
    });

    testWidgets('flat, the rows are the same radio group, by tap and by key', (
      tester,
    ) async {
      var selected = _Pace.slow;
      await tester.pumpWidget(
        _frame(
          StatefulBuilder(
            builder: (context, setState) => ChoiceCardGroup<_Pace>(
              semanticLabel: 'Pace',
              options: _options,
              selected: selected,
              flat: true,
              onSelected: (value) => setState(() => selected = value),
            ),
          ),
        ),
      );

      final slow = _flags(tester, 'pace-slow');
      expect(slow.isChecked, CheckedState.isTrue);
      expect(slow.isInMutuallyExclusiveGroup, isTrue);
      expect(_flags(tester, 'pace-fast').isChecked, CheckedState.isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected, _Pace.steady);

      await tester.tap(find.byKey(const ValueKey('pace-fast')));
      await tester.pump();
      expect(selected, _Pace.fast);

      // Rows on the page: nothing between one and the next but the ring's
      // gutter each already stands in.
      expect(
        tester.getRect(find.byKey(const ValueKey('pace-steady'))).top,
        tester.getRect(find.byKey(const ValueKey('pace-slow'))).bottom,
      );
    });

    testWidgets('flat and read-only, the chosen row alone, nothing to press', (
      tester,
    ) async {
      await tester.pumpWidget(
        _frame(
          const ChoiceCardGroup<_Pace>(
            semanticLabel: 'Pace',
            options: _options,
            selected: _Pace.steady,
            flat: true,
            onSelected: null,
          ),
        ),
      );

      expect(find.text('Steady'), findsOneWidget);
      expect(find.text('Slow'), findsNothing);
      expect(_flags(tester, 'pace-steady').isButton, isFalse);
      // The current setting, in the page's ink: the disabled grey would say
      // it is not available, and does not meet text contrast.
      final ink = AppTokens.profoundVerdant.colors.text.primary;
      expect(
        tester.widget<Text>(find.text('Steady')).style?.color,
        ink,
      );
    });
  });

  group('AppToggleButton', () {
    testWidgets('on and off are said by a glyph and to a screen reader', (
      tester,
    ) async {
      await tester.pumpWidget(
        _frame(
          Row(
            children: <Widget>[
              Expanded(
                child: AppToggleButton(
                  key: const ValueKey('on'),
                  label: 'Mon',
                  semanticLabel: 'Monday',
                  selected: true,
                  onChanged: (_) {},
                ),
              ),
              Expanded(
                child: AppToggleButton(
                  key: const ValueKey('off'),
                  label: 'Tue',
                  selected: false,
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('on')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('off')),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
      expect(_flags(tester, 'on').isToggled, Tristate.isTrue);
      expect(_flags(tester, 'off').isToggled, Tristate.isFalse);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('on'))).label,
        'Monday',
      );
    });

    testWidgets('a tap reports the other position', (tester) async {
      bool? reported;
      await tester.pumpWidget(
        _frame(
          AppToggleButton(
            key: const ValueKey('toggle'),
            label: 'Mon',
            selected: false,
            onChanged: (value) => reported = value,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('toggle')));
      expect(reported, isTrue);
    });

    testWidgets('too narrow for a row, the glyph goes above the label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _frame(
          Center(
            child: SizedBox(
              width: 52,
              child: AppToggleButton(
                label: 'Wed',
                selected: true,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      final glyph = tester.getRect(find.byIcon(Icons.check));
      final label = tester.getRect(find.text('Wed'));
      expect(glyph.bottom, lessThanOrEqualTo(label.top));
    });

    testWidgets('with room, the glyph sits beside the label', (tester) async {
      await tester.pumpWidget(
        _frame(
          Center(
            child: SizedBox(
              width: 160,
              child: AppToggleButton(
                label: 'Wed',
                selected: true,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      final glyph = tester.getRect(find.byIcon(Icons.check));
      final label = tester.getRect(find.text('Wed'));
      expect(glyph.right, lessThanOrEqualTo(label.left));
    });

    testWidgets('it is a large button high, and disabled without a handler', (
      tester,
    ) async {
      await tester.pumpWidget(
        _frame(
          const AppToggleButton(
            key: ValueKey('toggle'),
            label: 'Mon',
            selected: false,
            onChanged: null,
          ),
        ),
      );

      final surface = tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('toggle')),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(surface.height, 48);
      expect(_flags(tester, 'toggle').isEnabled, Tristate.isFalse);
    });
  });

  group('AppSwitchRow', () {
    testWidgets('with words, the line under the label says the state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _frame(
          AppSwitchRow(
            label: 'Receipts',
            value: false,
            onChanged: (_) {},
            onText: 'On - sent',
            offText: 'Off - not sent',
          ),
        ),
      );

      expect(find.text('Off - not sent'), findsOneWidget);
      // The words carry it, so the thumb is left as Material draws it.
      expect(_thumbIcons(tester), isNull);
    });

    testWidgets('without words, the thumb says the state as a glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        _frame(
          AppSwitchRow(label: 'Receipts', value: false, onChanged: (_) {}),
        ),
      );

      // The label alone - no line under it - and a check or a cross on the
      // thumb, so on and off are not the track's hue alone.
      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.subtitle, isNull);
      final icons = _thumbIcons(tester)!;
      expect(
        icons.resolve(<WidgetState>{WidgetState.selected})?.icon,
        Icons.check,
      );
      expect(icons.resolve(<WidgetState>{})?.icon, Icons.close);
    });

    testWidgets('flat, the whole row toggles and says so to a screen reader', (
      tester,
    ) async {
      bool? reported;
      await tester.pumpWidget(
        _frame(
          AppSwitchRow(
            key: const ValueKey('switch'),
            label: 'Receipts',
            icon: Icons.chat_outlined,
            value: false,
            flat: true,
            onChanged: (value) => reported = value,
          ),
        ),
      );

      // The label, not the switch: the row is one target.
      await tester.tap(find.text('Receipts'));
      await tester.pump();
      expect(reported, isTrue);
      expect(_flags(tester, 'switch').isToggled, Tristate.isFalse);
      // One stop for a keyboard: the switch is a picture of the state.
      final picture = tester.widget<Switch>(find.byType(Switch));
      expect(
        find.ancestor(
          of: find.byWidget(picture),
          matching: find.byType(ExcludeFocus),
        ),
        findsOneWidget,
      );
      // On is a check in the thumb; off is the bare thumb.
      expect(
        picture.thumbIcon?.resolve(<WidgetState>{WidgetState.selected})?.icon,
        Icons.check,
      );
      expect(picture.thumbIcon?.resolve(<WidgetState>{}), isNull);
    });

    testWidgets('flat and without a handler, it is disabled and inert', (
      tester,
    ) async {
      await tester.pumpWidget(
        _frame(
          const AppSwitchRow(
            key: ValueKey('switch'),
            label: 'Receipts',
            value: true,
            flat: true,
            onChanged: null,
          ),
        ),
      );

      final flags = _flags(tester, 'switch');
      expect(flags.isToggled, Tristate.isTrue);
      expect(flags.isEnabled, Tristate.isFalse);
    });
  });
}

Widget _frame(Widget child) => MaterialApp(
  theme: ThemeData(
    extensions: const <ThemeExtension<dynamic>>[AppTokens.profoundVerdant],
  ),
  home: Scaffold(
    body: Padding(padding: EdgeInsets.all(AppSpacing.scale.s16), child: child),
  ),
);

Future<void> _pumpGroup(
  WidgetTester tester, {
  required _Pace selected,
  ValueChanged<_Pace>? onSelected,
  bool readOnly = false,
}) => tester.pumpWidget(
  _frame(
    ChoiceCardGroup<_Pace>(
      semanticLabel: 'Pace',
      options: _options,
      selected: selected,
      onSelected: readOnly ? null : (onSelected ?? (_) {}),
    ),
  ),
);

WidgetStateProperty<Icon?>? _thumbIcons(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).thumbIcon;

SemanticsFlags _flags(WidgetTester tester, String key) => tester
    .getSemantics(find.byKey(ValueKey(key)))
    .getSemanticsData()
    .flagsCollection;
