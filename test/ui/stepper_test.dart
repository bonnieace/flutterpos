import 'package:flutter/material.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/stepper.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuantityStepper', () {
    testWidgets('offers the plus §5.1 named as missing', (tester) async {
      // §5.1's "Replaces" column for this component is four words long and is
      // the whole specification: "minus + delete, no plus". A cashier who rang
      // up one loaf and needs two had to leave the cart, find the tile in the
      // product grid, and press it again.
      final events = <String>[];
      await _pump(
        tester,
        onIncrement: () => events.add('+'),
        onDecrement: () => events.add('-'),
      );

      await tester.tap(find.byKey(const ValueKey('quantity-stepper-increment')));
      await tester.tap(find.byKey(const ValueKey('quantity-stepper-decrement')));
      await tester.pumpAndSettle();

      expect(events, <String>['+', '-']);
    });

    testWidgets('disables each side independently at its bound', (
      tester,
    ) async {
      // A line whose product the cached catalog no longer holds cannot be
      // incremented - there is nothing to add - and that is a different state
      // from the whole control being unavailable.
      await _pump(tester, onIncrement: null);

      expect(_pressable(tester, 'quantity-stepper-increment'), isFalse);
      expect(_pressable(tester, 'quantity-stepper-decrement'), isTrue);
    });

    testWidgets('disabling the stepper disables both sides', (tester) async {
      await _pump(tester, enabled: false);

      expect(_pressable(tester, 'quantity-stepper-increment'), isFalse);
      expect(_pressable(tester, 'quantity-stepper-decrement'), isFalse);
    });

    testWidgets('reports what is typed without parsing it', (tester) async {
      // Parsing and refusing a typed quantity is the cart's, not this
      // widget's: that rule is behaviour, and `claude.md` hard rule 1 keeps
      // behaviour out of the change that introduced this component.
      final typed = <String>[];
      await _pump(tester, onChanged: typed.add);

      await tester.enterText(
        find.byKey(const ValueKey('quantity-stepper-field')),
        '7',
      );
      await tester.pumpAndSettle();

      expect(typed, <String>['7']);
    });

    testWidgets('keeps what a person typed while it is unusable', (
      tester,
    ) async {
      // **The field belongs to the person, not to the cart.** Snapping a
      // rejected entry back to the last good value would leave a valid number
      // on screen beside a message saying the quantity is wrong, with nothing
      // to correct. This is the cart's own existing rule, preserved.
      await _pump(tester, quantity: 3);
      await tester.enterText(
        find.byKey(const ValueKey('quantity-stepper-field')),
        '99999',
      );
      await tester.pumpAndSettle();

      // The cart refused it, so its quantity is unchanged and it re-renders
      // with the same value and an error.
      await _pump(tester, quantity: 3, error: 'Enter 1 to 999.');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .controller
            .text,
        '99999',
      );
    });

    testWidgets('sizes its well for the ceiling, not the current value', (
      tester,
    ) async {
      // Sizing for what is on screen makes the row reflow when a quantity goes
      // from 9 to 10, which moves the two buttons under the finger reaching
      // for them.
      final tokens = spiritTheme.extension<AppTokens>()!;
      final narrow = QuantityStepper.wellWidth(tokens.spacing, maximum: 9);
      final wide = QuantityStepper.wellWidth(tokens.spacing, maximum: 9999);
      expect(wide, greaterThan(narrow));

      await _pump(tester, quantity: 1, maximum: 999);
      final atOne = tester.getSize(
        find.byKey(const ValueKey('quantity-stepper-field')),
      );
      await _pump(tester, quantity: 100, maximum: 999);
      final atHundred = tester.getSize(
        find.byKey(const ValueKey('quantity-stepper-field')),
      );
      expect(atOne.width, atHundred.width);
    });

    testWidgets('names itself without drawing a word', (tester) async {
      // A cart line draws no label: sixteen of them saying *Quantity* over a
      // control shaped like one cost enough height to push the save button off
      // a phone. §5.2's persistent-label rule is about a bare field, which this
      // is not - but a person who cannot see the shape still has to be told.
      await _pump(tester, label: null);

      expect(find.text('Quantity'), findsNothing);
      expect(find.bySemanticsLabel('Quantity'), findsOne);
    });

    testWidgets('gives each glyph-only control a semantic label', (
      tester,
    ) async {
      // §9: "Icon-only controls - required semantic label".
      await _pump(tester);

      expect(find.bySemanticsLabel('One fewer'), findsOne);
      expect(find.bySemanticsLabel('One more'), findsOne);
    });

    testWidgets('both controls clear §9s tap target', (tester) async {
      await _pump(tester);

      for (final key in const <String>[
        'quantity-stepper-decrement',
        'quantity-stepper-increment',
      ]) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.width, greaterThanOrEqualTo(48), reason: key);
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }
    });
  });
}

/// Whether the control at [key] can be pressed.
///
/// The key sits on the stepper's own wrapper rather than on the `IconButton`
/// inside it, so this descends - the wrapper is what a call site and a
/// screenshot address, and the button is an implementation detail of it.
bool _pressable(WidgetTester tester, String key) => tester
    .widget<IconButton>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(IconButton),
      ),
    )
    .onPressed != null;

Future<void> _pump(
  WidgetTester tester, {
  String? label = 'Quantity',
  int quantity = 1,
  int? maximum,
  String? error,
  bool enabled = true,
  ValueChanged<String>? onChanged,
  VoidCallback? onIncrement = _noop,
  VoidCallback? onDecrement = _noop,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: QuantityStepper(
          label: label,
          quantity: quantity,
          maximum: maximum,
          error: error,
          enabled: enabled,
          onChanged: onChanged ?? (_) {},
          onIncrement: onIncrement,
          onDecrement: onDecrement,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _noop() {}
