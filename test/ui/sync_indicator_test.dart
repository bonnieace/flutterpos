import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/sync_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncIndicator', () {
    testWidgets('draws no badge when the device is clear', (tester) async {
      // A zero is not a state worth drawing, and a permanent "0" trains a
      // person to stop looking at the one control that tells them something is
      // stuck.
      await _pumpButton(tester, waiting: 0);

      expect(find.text('0'), findsNothing);
      expect(
        find.bySemanticsLabel('Checkouts on this device: none waiting'),
        findsOne,
      );
    });

    testWidgets('counts what is waiting and says so to a screen reader', (
      tester,
    ) async {
      await _pumpButton(tester, waiting: 2);

      expect(find.text('2'), findsOne);
      expect(
        find.bySemanticsLabel('Checkouts on this device: 2 waiting'),
        findsOne,
      );
    });

    testWidgets('clears §9s tap target', (tester) async {
      await _pumpButton(tester, waiting: 2);
      final size = tester.getSize(find.byType(SyncIndicator));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('SyncQueuePanel', () {
    testWidgets('draws the row that is not zero as a status', (tester) async {
      // §7 sends these counts to a `StatRow` rather than a five-line list, and
      // the point of the panel is that one row is the news.
      await _pumpPanel(tester);

      expect(find.text('Saved offline'), findsOne);
      expect(find.text('Confirmed'), findsOne);
      // Exactly one container, so the panel has a signal in it.
      expect(find.byIcon(AppStatus.attention.defaultIcon), findsOne);
    });

    testWidgets('closes from its own header', (tester) async {
      var closed = 0;
      await _pumpPanel(tester, onClose: () => closed++);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(closed, 1);
    });
  });
}

Future<void> _pumpButton(WidgetTester tester, {required int waiting}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: Center(
          child: SyncIndicator(waiting: waiting, onOpen: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPanel(WidgetTester tester, {VoidCallback? onClose}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: SyncQueuePanel(
          title: 'Checkouts on this device',
          onClose: onClose ?? () {},
          entries: const <SyncQueueEntry>[
            SyncQueueEntry(
              label: 'Saved offline',
              count: 2,
              status: AppStatus.attention,
            ),
            SyncQueueEntry(label: 'Submitting', count: 0),
            SyncQueueEntry(label: 'Confirmed', count: 11),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
