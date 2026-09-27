import 'package:flutter/material.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/banner.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShiftBanner', () {
    testWidgets('states the standing in words as well as in colour', (
      tester,
    ) async {
      // §9: never by hue alone. The word *is* the status here rather than a
      // label beside it, which is why this is the one place in the app where a
      // status colour carries text.
      await _pump(tester, status: AppStatus.attention);

      // **Uppercased since 2026-08-23**, because the export sets this line in
      // `label-caps` and §2.2 permits uppercase on `label.eyebrow` alone. The
      // words are unchanged; the role they are drawn in is not.
      expect(find.text('CASH COUNT UNFINISHED'), findsOne);
      expect(find.byIcon(AppStatus.attention.defaultIcon), findsOne);
      // Announced with the words, not left to the container.
      expect(
        find.bySemanticsLabel(
          RegExp('Cash count unfinished.*Expected KES 4,220.00'),
        ),
        findsOne,
      );
    });

    testWidgets('offers exactly one action, and only when there is one', (
      tester,
    ) async {
      await _pump(tester, action: const Text('Close shift'));
      expect(find.text('Close shift'), findsOne);

      // A shift somebody else opened on another device has no next thing for
      // this person to do, and a banner with a disabled control on it would
      // read as one that does.
      await _pump(tester, action: null);
      expect(find.text('Close shift'), findsNothing);
    });

    testWidgets('is inert rather than silently untappable', (tester) async {
      // §4.4: "never a destination". Tapping opens a sheet, which is not a
      // route - but a banner that is sometimes tappable and looks identical
      // either way is worse than one that never is.
      var opened = 0;
      await _pump(tester, onOpenDetails: () => opened++);
      await tester.tap(find.text('CASH COUNT UNFINISHED'));
      await tester.pumpAndSettle();
      expect(opened, 1);

      await _pump(tester, onOpenDetails: null);
      await tester.tap(find.text('CASH COUNT UNFINISHED'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  AppStatus status = AppStatus.attention,
  Widget? action = const Text('Close shift'),
  VoidCallback? onOpenDetails,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: ShiftBanner(
          status: status,
          heading: 'Cash count unfinished',
          detail: 'Expected KES 4,220.00 over 17 sales.',
          action: action,
          onOpenDetails: onOpenDetails,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
