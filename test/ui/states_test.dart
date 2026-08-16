import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/states.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmptyState', () {
    testWidgets('draws §7s four rows and nothing else', (tester) async {
      // §7's Empty pattern: "Icon, one-line statement of what would be here,
      // one sentence on how to create one, and a `primary` action if the person
      // can. **Not a paragraph.**"
      await _pump(
        tester,
        title: 'No products yet',
        hint: 'Add one from Manage catalog.',
        action: AppButton(
          label: 'Add a product',
          tier: AppButtonTier.primary,
          onPressed: () {},
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('No products yet'), findsOne);
      expect(find.text('Add one from Manage catalog.'), findsOne);
      expect(find.text('Add a product'), findsOne);
    });

    testWidgets('omits the sentence and the action when there are none', (
      tester,
    ) async {
      // A screen a person cannot add to has no honest sentence to offer: a
      // cashier looking at an empty catalog cannot stock it, and telling them
      // how would be telling the wrong person.
      await _pump(tester, title: 'No products yet');

      expect(find.text('No products yet'), findsOne);
      expect(find.byType(AppButton), findsNothing);
      // The mark is always there - §7 opens the pattern with "Icon".
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('settles rather than looping, per §6.4s budget', (tester) async {
      // §6.4: "Idle loops on an operational screen: **0**". An empty state is a
      // screen somebody is reading, so the mark draws once and stops - which is
      // also what lets `pumpAndSettle` return at all. A looping asset would
      // time this test out, which makes the assertion the budget line itself.
      await _pump(tester, title: 'No products yet');

      await tester.pumpAndSettle();
      expect(find.text('No products yet'), findsOne);
    });

    testWidgets('renders its final frame under disableAnimations', (
      tester,
    ) async {
      // §2.4: "animated assets render their final frame as a static image".
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: _Host(title: 'No products yet'),
        ),
      );
      // One pump, not a settle: if the mark still animated under this flag the
      // frame here would be its first rather than its last.
      await tester.pump();

      expect(find.text('No products yet'), findsOne);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required String title,
  String? hint,
  Widget? action,
}) async {
  await tester.pumpWidget(
    _Host(title: title, hint: hint, action: action),
  );
  await tester.pump();
}

final class _Host extends StatelessWidget {
  const _Host({required this.title, this.hint, this.action});

  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: spiritTheme,
    home: Scaffold(
      body: EmptyState(title: title, hint: hint, action: action),
    ),
  );
}
