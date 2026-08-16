import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/dialogs.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConfirmDialog', () {
    testWidgets('takes the tier of the action that opened it', (tester) async {
      // The one rule this component exists to hold. §8 rule 4 asks that the
      // verb persists from the button to the dialog to the confirmation, and a
      // confirm that changed *appearance* on the way would break it in shape
      // while keeping it in words.
      for (final tier in AppButtonTier.values) {
        await _pump(tester, tier: tier);
        expect(_confirm(tester).tier, tier, reason: tier.name);
        // The cancel never varies. All eight dialogs this replaces drew it
        // `tertiary`, and a cancel with an outline reads as a second action
        // rather than as the absence of one.
        expect(_cancel(tester).tier, AppButtonTier.tertiary, reason: tier.name);
      }
    });

    testWidgets('states the consequence and what is still true', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Clear this sale?'), findsOne);
      expect(find.text('3 items, KES 135.00 will be discarded.'), findsOne);
      // §8 rule 6, and the reassurance is optional so it has to be asserted
      // present rather than assumed.
      expect(find.text('Nothing has been saved yet.'), findsOne);
    });

    testWidgets('omits the reassurance when there is none to give', (
      tester,
    ) async {
      await _pump(tester, stillTrue: null);

      expect(find.text('Nothing has been saved yet.'), findsNothing);
      expect(find.text('3 items, KES 135.00 will be discarded.'), findsOne);
    });

    testWidgets('freezes the confirm and disables the cancel while it works', (
      tester,
    ) async {
      // §2.1's loading row on the confirm. The cancel goes with it because a
      // write already in flight cannot be called off from this dialog, and a
      // live Cancel beside a running confirm says otherwise.
      //
      // **Not settled**: §2.1's loading row is a spinner, which never reaches a
      // quiet frame, so `pumpAndSettle` here times out rather than failing an
      // assertion.
      await _pump(tester, loading: true, settle: false);

      expect(_confirm(tester).loading, isTrue);
      expect(_cancel(tester).onPressed, isNull);
    });

    testWidgets('a disabled confirm is a question with no answer yet', (
      tester,
    ) async {
      await _pump(tester, onConfirm: null);

      expect(_confirm(tester).onPressed, isNull);
      expect(_cancel(tester).onPressed, isNotNull);
    });

    testWidgets('carries the call site keys when it is given them', (
      tester,
    ) async {
      // Eight screens were keyed for themselves before this component existed
      // and their tests tap those keys; a component that renamed them would be
      // churn in the suite for no assertion gained.
      await _pump(
        tester,
        confirmKey: const ValueKey('product-stock-confirm'),
        cancelKey: const ValueKey('product-stock-cancel'),
      );

      expect(find.byKey(const ValueKey('product-stock-confirm')), findsOne);
      expect(find.byKey(const ValueKey('confirm-dialog-confirm')), findsNothing);
    });

    testWidgets('is drawn on §2.1 and §2.3 rather than on Material', (
      tester,
    ) async {
      await _pump(tester);

      const tokens = AppTokens.dark;
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      // §2.1's row for "dialogs, menus, bottom sheets", and §2.3's for
      // "dialogs, bottom sheets". A dialog is pushed onto a route with its own
      // context, which is exactly where a theme read can go missing.
      expect(dialog.backgroundColor, tokens.colors.surface.overlay);
      expect(
        dialog.shape,
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius.lg),
        ),
      );
    });
  });

  group('showConfirmDialog', () {
    testWidgets('answers true only when the confirm is pressed', (
      tester,
    ) async {
      expect(await _ask(tester, press: 'confirm-dialog-confirm'), isTrue);
      expect(await _ask(tester, press: 'confirm-dialog-cancel'), isFalse);
    });

    testWidgets('a dismissal is a no rather than a null', (tester) async {
      // **Not confirming and dismissing are the same outcome** - nothing
      // happens - and giving them two representations is how a null slips
      // through a call site as a yes.
      expect(await _ask(tester, press: null), isFalse);
    });

    testWidgets('only a destructive question can be escaped by its scrim', (
      tester,
    ) async {
      // A stray tap outside a destructive dialog lands on the safe answer, so
      // leaving by accident costs nothing. On any other tier the safe answer is
      // not obvious - a primary confirm sits at the end of something typed -
      // so it must be answered rather than escaped.
      //
      // **What is asserted is whether the dialog survived the tap**, not what
      // the call answered: the non-dismissible case has to be answered
      // afterwards to unwind its route, so both end up `false` and comparing
      // return values would prove nothing.
      expect(
        await _ask(tester, press: null, tier: AppButtonTier.destructive),
        isFalse,
      );
      await _ask(
        tester,
        press: null,
        tier: AppButtonTier.primary,
        expectDismissed: false,
      );
    });
  });
}

AppButton _confirm(WidgetTester tester) => tester.widget<AppButton>(
  find.byKey(const ValueKey('confirm-dialog-confirm')),
);

AppButton _cancel(WidgetTester tester) =>
    tester.widget<AppButton>(find.byKey(const ValueKey('confirm-dialog-cancel')));

Future<void> _pump(
  WidgetTester tester, {
  AppButtonTier tier = AppButtonTier.destructive,
  String? stillTrue = 'Nothing has been saved yet.',
  bool loading = false,
  VoidCallback? onConfirm = _noop,
  Key? confirmKey,
  Key? cancelKey,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: ConfirmDialog(
        title: 'Clear this sale?',
        consequence: '3 items, KES 135.00 will be discarded.',
        stillTrue: stillTrue,
        confirmLabel: 'Clear it',
        tier: tier,
        loading: loading,
        onConfirm: onConfirm,
        onCancel: _noop,
        confirmKey: confirmKey,
        cancelKey: cancelKey,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Opens the dialog, optionally presses one of its buttons, and answers what
/// `showConfirmDialog` returned.
///
/// [expectDismissed] false means the scrim tap is expected *not* to close it, so
/// the dialog is answered afterwards to let the route unwind - a test that left
/// a route on the stack would fail its own tear-down rather than its assertion.
Future<bool?> _ask(
  WidgetTester tester, {
  required String? press,
  AppButtonTier tier = AppButtonTier.destructive,
  bool expectDismissed = true,
}) async {
  bool? answer;
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: AppButton(
              label: 'Open',
              onPressed: () async {
                answer = await showConfirmDialog(
                  context,
                  title: 'Clear this sale?',
                  consequence: '3 items will be discarded.',
                  confirmLabel: 'Clear it',
                  tier: tier,
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  if (press != null) {
    await tester.tap(find.byKey(ValueKey(press)));
  } else {
    // The scrim: anything outside the dialog's own box.
    await tester.tapAt(const Offset(10, 10));
  }
  await tester.pumpAndSettle();

  if (!expectDismissed) {
    expect(find.byType(ConfirmDialog), findsOne);
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-cancel')));
    await tester.pumpAndSettle();
  }
  return answer;
}

void _noop() {}
