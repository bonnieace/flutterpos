import 'package:flutter/material.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/fields.dart';
import 'package:uzapay_pos/ui/sheet.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

final TextEditingController _counted = TextEditingController();

void main() {
  tearDownAll(_counted.dispose);

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

    testWidgets('a drag down from full settles at half, it does not cancel', (
      tester,
    ) async {
      // **Opened full, because half is already the bottom of the travel.** An
      // earlier version of this opened at half, where a downward drag has
      // nowhere to go, and so passed against a build that dismissed on a
      // device. From full there is real distance to cover.
      await _pump(tester, initialDetent: AppSheetDetent.full);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // On the content, not the handle: the handle sits above the `ListView`
      // and a drag on it never reaches the sheet's scroll controller at all.
      await tester.fling(
        find.text('Inside the sheet'),
        const Offset(0, 900),
        2000,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Inside the sheet'),
        findsOne,
        reason:
            'The gesture may move the sheet between its detents and nothing '
            'else. Losing a half-filled form to a downward flick is the '
            'defect this closes.',
      );
    });

    testWidgets('scrolling the content up and back down keeps the sheet', (
      tester,
    ) async {
      await _pump(
        tester,
        content: (context) => const SizedBox(
          height: 2000,
          child: Align(
            alignment: Alignment.topCenter,
            child: Text('Inside the sheet'),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Up first, so the scrollable owns the gesture, then back down past
      // where it started. This is the sequence reported from a device: it
      // bypasses the route's own detector entirely, so switching that off
      // left it working.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 1200));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOne);
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

    testWidgets('keeps the field a person is typing into alive', (
      tester,
    ) async {
      // Reported on a device on 2026-09-03: nothing could be typed into a
      // sheet. The wrapper above the sheet returned two structurally different
      // trees, so crossing zero on `viewInsets.bottom` re-inflated the whole
      // subtree - and a field disposed the instant it takes focus drops its
      // `EditableText`'s platform input connection, which dismisses the very
      // keyboard whose arrival destroyed it.
      //
      // The two cases above pass either way: they assert the sheet's rect and
      // re-find `DraggableScrollableSheet` by type, which resolves the
      // freshly-inflated replacement just as happily as the survivor. This one
      // holds the `State` and the `FocusNode` across the change.
      await _pump(
        tester,
        content: (context) =>
            AppTextField(label: 'Counted cash', controller: _counted),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final before = tester.state(find.byType(DraggableScrollableSheet));
      await tester.tap(find.byType(EditableText));
      await tester.pumpAndSettle();
      final focus = tester.widget<EditableText>(find.byType(EditableText))
          .focusNode;
      expect(focus.hasFocus, isTrue);

      // The keyboard arriving is what used to take the field down with it.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(
        tester.state(find.byType(DraggableScrollableSheet)),
        same(before),
        reason: 'the sheet was re-inflated, taking every field with it',
      );
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).focusNode,
        same(focus),
      );
      expect(focus.hasFocus, isTrue);

      await tester.enterText(find.byType(EditableText), '1250.50');
      await tester.pump();
      expect(_counted.text, '1250.50');
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
  AppSheetDetent initialDetent = AppSheetDetent.half,
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
                initialDetent: initialDetent,
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
