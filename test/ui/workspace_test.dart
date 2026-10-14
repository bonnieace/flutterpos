import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/sheet.dart';
import 'package:uzapay_pos/ui/workspace.dart';

void main() {
  testWidgets('regions adapt to host width inside a large window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [1200.0, 400.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: const AppWorkspace(
                  leading: Text('Summary'),
                  trailing: Text('Editor'),
                ),
              ),
            ),
          ),
        ),
      );
      final summary = tester.getTopLeft(find.text('Summary'));
      final editor = tester.getTopLeft(find.text('Editor'));
      if (width > 1000) {
        expect(editor.dx, greaterThan(summary.dx));
        expect(editor.dy, summary.dy);
      } else {
        expect(editor.dx, summary.dx);
        expect(editor.dy, greaterThan(summary.dy));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'desktop sheet centers and preserves draft and dismissal policy',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final input = TextEditingController();
      addTearDown(input.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppSheet<void>(
                  context,
                  dismissible: false,
                  builder: (context, controller) => ListView(
                    controller: controller,
                    children: [TextField(controller: input)],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      await tester.enterText(find.byType(TextField), 'Unsaved name');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(input.text, 'Unsaved name');
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.getCenter(find.byType(TextField)).dx, closeTo(720, 1));
      await tester.tap(find.byKey(const ValueKey('app-sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
