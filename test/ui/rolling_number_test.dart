import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/rolling_number.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RollingNumber', () {
    testWidgets('at rest it is the Text it replaced, key and all', (
      tester,
    ) async {
      // The reason `textKey` exists: seven surfaces find their figure by key and
      // read `Text.data` off it, and none of them had to change.
      await _pump(tester, 'KES 135.00');

      final text = tester.widget<Text>(find.byKey(const ValueKey('figure')));
      expect(text.data, 'KES 135.00');
      expect(find.text('KES 135.00'), findsOne);
    });

    testWidgets('moves only the positions that changed', (tester) async {
      // §6.2: "digits roll; **only changed digits move**". `KES 135.00` →
      // `KES 185.00` differs in exactly one position.
      await _pump(tester, 'KES 135.00');
      await _pump(tester, 'KES 185.00', reuse: true);
      await tester.pump(const Duration(milliseconds: 16));

      expect(_movingPositions, findsOne);
      // The one that changed carries both glyphs, the old sliding out and the
      // new sliding in, and both are inside that clip.
      expect(
        find.descendant(of: _movingPositions, matching: find.text('3')),
        findsOne,
      );
      expect(
        find.descendant(of: _movingPositions, matching: find.text('8')),
        findsOne,
      );
      // The nine that did not change are still, and sit outside it.
      expect(
        find.descendant(of: _movingPositions, matching: find.text('K')),
        findsNothing,
      );
      expect(find.text('K'), findsOne);
    });

    testWidgets('rolls every position when the figure changes length', (
      tester,
    ) async {
      // Right-aligned comparison, which is what keeps the minor units still
      // when the figure grows a digit.
      await _pump(tester, '99.00');
      await _pump(tester, '100.00', reuse: true);
      await tester.pump(const Duration(milliseconds: 16));

      // **Three, not six, and the three are the interesting part.** Padding
      // `99.00` on the left to ` 99.00` leaves `.00` sitting under `.00`, so
      // the minor units hold still and only the shillings move. That is the
      // rule doing better than the sentence above it predicted: right-aligned
      // comparison is what makes crossing 100 cost three glyphs rather than
      // the whole figure.
      expect(_movingPositions, findsExactly(3));
    });

    testWidgets('travels the way the figure did', (tester) async {
      // A total going up rolls up and one going down rolls down, so a person
      // watching a cart learns which happened without reading the number.
      expect(RollingNumberDirection.of('KES 135.00', 'KES 185.00'), 1);
      expect(RollingNumberDirection.of('KES 185.00', 'KES 135.00'), -1);
      // Neither string is a figure: nothing to be wrong about, so it rolls up.
      expect(RollingNumberDirection.of('KES', 'USD'), 1);
    });

    testWidgets('settles on the new figure', (tester) async {
      await _pump(tester, 'KES 135.00');
      await _pump(tester, 'KES 185.00', reuse: true);
      await tester.pumpAndSettle();

      expect(find.text('KES 185.00'), findsOne);
      expect(_movingPositions, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a second change mid-roll retargets rather than restarting', (
      tester,
    ) async {
      // §2.4, and `claude.md`'s motion rule in as many words: "never
      // `AnimationController.forward()` from zero on a retrigger". What is
      // observable here is that the drive is still running and that it arrives
      // at the *last* figure rather than at the one it was interrupted with.
      await _pump(tester, 'KES 135.00');
      await _pump(tester, 'KES 185.00', reuse: true);
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.hasRunningAnimations, isTrue);

      await _pump(tester, 'KES 235.00', reuse: true);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpAndSettle();
      expect(find.text('KES 235.00'), findsOne);
    });

    testWidgets('states the new figure from the first frame, per §6.3', (
      tester,
    ) async {
      // "No animation may sit between an input and its record." A screen reader
      // asking mid-roll is to be told the committed total, not the one that is
      // rolling away.
      final handle = tester.ensureSemantics();
      await _pump(tester, 'KES 135.00');
      await _pump(tester, 'KES 185.00', reuse: true);
      await tester.pump(const Duration(milliseconds: 16));

      // The committed figure is in the tree from the first frame of the roll,
      // painted or not, so nothing has to wait for the animation to be told the
      // truth.
      expect(find.bySemanticsLabel('KES 185.00'), findsOne);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('figure'))).data,
        'KES 185.00',
      );
      handle.dispose();
    });

    testWidgets('renders the new figure and nothing else under reduced motion', (
      tester,
    ) async {
      // §2.4: "springs collapse to instant".
      await _pump(tester, 'KES 135.00', reducedMotion: true);
      await _pump(tester, 'KES 185.00', reuse: true, reducedMotion: true);
      await tester.pump();

      expect(find.text('KES 185.00'), findsOne);
      expect(_movingPositions, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('refuses a style whose figures are not tabular', (tester) async {
      // With proportional figures every position shifts under the roll and the
      // eye reads every digit as changed, which is the one way this component
      // can look broken while working.
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: const Scaffold(
            body: RollingNumber(
              value: '135.00',
              style: TextStyle(fontSize: 28),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isA<AssertionError>());
    });
  });
}

/// The positions that are actually rolling.
///
/// Each is a `ClipRect` under the overlay's own `ClipRect`, which is the one
/// that keeps a roll between two different-length figures inside the box of the
/// figure it covers.
final Finder _movingPositions = find.descendant(
  of: find.byType(OverflowBox),
  matching: find.byType(ClipRect),
);

Future<void> _pump(
  WidgetTester tester,
  String value, {
  bool reuse = false,
  bool reducedMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(
          body: Center(
            child: RollingNumber(
              value: value,
              textKey: const ValueKey('figure'),
              style: AppTypeRoles.standard.numericHero,
            ),
          ),
        ),
      ),
    ),
  );
  if (!reuse) await tester.pump();
}
