import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/sheet.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSheet', () {
    testWidgets('rests at more than one position, which is §2.4s point', (
      tester,
    ) async {
      // "A sheet that only opens and closes on tap is not the same product."
      // Two detents plus dismissal is what makes a drag worth performing, and
      // it is the half of §2.4 that survived v0.8.
      expect(AppSheetDetent.values, hasLength(2));
      expect(
        AppSheetDetent.full.fraction,
        greaterThan(AppSheetDetent.half.fraction),
      );
      // Deliberately short of the whole screen, so the scrim stays visible and
      // the sheet reads as a layer rather than as a route that replaced the
      // page.
      expect(AppSheetDetent.full.fraction, lessThan(1));
    });

    testWidgets('opens, draws its own handle, and closes', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Inside the sheet'), findsOne);
      // Material's own grey lozenge is off; the handle here is `border.strong`
      // at `radius.pill`, drawn by the component.
      expect(find.bySemanticsLabel('Drag to resize'), findsOne);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Inside the sheet'), findsNothing);
    });

    testWidgets('a sheet that may not be dismissed keeps its scrim inert', (
      tester,
    ) async {
      await _pump(tester, dismissible: false);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Inside the sheet'), findsOne);
    });

    testWidgets('gives the keyboard its space instead of hiding under it', (
      tester,
    ) async {
      // Reported on a device on 2026-09-02: a form in a sheet put the field
      // being typed into, and the button that submits it, underneath the keys.
      // A sheet is anchored to the bottom of the screen and every detent is a
      // fraction of a height that took no notice of the keyboard.
      await _pump(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final sheet = find.byType(DraggableScrollableSheet);
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(tester.getRect(sheet).bottom, moreOrLessEquals(screenHeight));

      // In physical pixels, which is what a view reports; a third of that is
      // the logical height the keyboard takes at the default 3.0 ratio.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      final keyboard = 300 / tester.view.devicePixelRatio;
      expect(
        tester.getRect(sheet).bottom,
        moreOrLessEquals(screenHeight - keyboard),
      );
    });

    testWidgets('spends the inset once, so nothing inside pads by it again', (
      tester,
    ) async {
      // `Scaffold` removes the bottom inset when `resizeToAvoidBottomInset`
      // consumes it, for the reason this does: a descendant that padded by the
      // same figure would leave a second keyboard's worth of empty space above
      // the real one.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);

      late double seen;
      await _pump(
        tester,
        content: (context) {
          seen = MediaQuery.viewInsetsOf(context).bottom;
          return const Text('Inside the sheet');
        },
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(seen, 0);
    });

    testWidgets('is drawn on §2.1 and §2.3 rather than on Material', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final tokens = spiritTheme.extension<AppTokens>()!;
      final surface = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.color == tokens.colors.surface.overlay);
      // §2.3's "dialogs, bottom sheets", on the top corners only: a sheet is
      // anchored to the bottom edge and rounding that edge shows the page
      // through the gap.
      expect(
        surface.borderRadius,
        BorderRadius.vertical(top: Radius.circular(tokens.radius.lg)),
      );
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  bool dismissible = true,
  WidgetBuilder? content,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                dismissible: dismissible,
                builder: (context, controller) => ListView(
                  controller: controller,
                  children: <Widget>[
                    content?.call(context) ?? const Text('Inside the sheet'),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
