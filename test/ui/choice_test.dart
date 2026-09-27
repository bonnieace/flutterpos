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
        expect(find.text(option.description), findsOneWidget);
      }
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

SemanticsFlags _flags(WidgetTester tester, String key) => tester
    .getSemantics(find.byKey(ValueKey(key)))
    .getSemanticsData()
    .flagsCollection;
