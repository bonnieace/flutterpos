import 'package:flutter/material.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/buttons.dart';
import 'package:uzapay_pos/ui/dialogs.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDialog', () {
    testWidgets('keeps its two actions horizontal on a phone', (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpAppDialog(
        tester,
        title: 'Remove this image?',
        content: const Text('This cannot be undone.'),
        actions: <Widget>[
          AppButton(label: 'Cancel', onPressed: () {}),
          AppButton(
            label: 'Remove image',
            tier: AppButtonTier.destructive,
            onPressed: () {},
          ),
        ],
      );

      final cancel = tester.getRect(find.text('Cancel'));
      final remove = tester.getRect(find.text('Remove image'));
      expect(cancel.center.dy, remove.center.dy);
      expect(cancel.left, lessThan(remove.left));
    });

    testWidgets('holds a child, which is the whole of what it adds', (
      tester,
    ) async {
      // `ConfirmDialog` refuses children by design and three form-bearing
      // dialogs had nowhere to go. This is that component.
      await _pumpAppDialog(
        tester,
        title: 'Correct "Maize flour 2kg"',
        content: const TextField(key: ValueKey('a-field')),
        actions: <Widget>[
          AppButton(label: 'Cancel', onPressed: () {}),
          AppButton(
            label: 'Review correction',
            tier: AppButtonTier.primary,
            onPressed: () {},
          ),
        ],
      );

      expect(find.text('Correct "Maize flour 2kg"'), findsOne);
      expect(find.byKey(const ValueKey('a-field')), findsOne);
      expect(find.byType(AppButton), findsExactly(2));
    });

    testWidgets('takes §4.3s form maximum rather than a width of its own', (
      tester,
    ) async {
      // §4.3's `Form` row: "single column, 720 max", which is also §4.2's row
      // for reading and forms. It replaces a hardcoded `SizedBox(width: 440)`
      // that one call site chose for itself.
      expect(AppDialog.maximumWidth, AppLayout.contract.reading);

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpAppDialog(
        tester,
        title: 'Change business',
        content: const SizedBox(width: 2000, height: 40),
      );

      final width = tester
          .getSize(
            find.descendant(
              of: find.byType(AppDialog),
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .width;
      expect(width, AppDialog.maximumWidth);
    });

    testWidgets('draws no title row when there is no title', (tester) async {
      // §7's "title appears once": the set-default form carries its own
      // heading, so the dialog around it must not repeat the word.
      await _pumpAppDialog(
        tester,
        content: const Text('The form owns its own heading.'),
      );

      expect(find.byType(Text), findsOne);
    });

    testWidgets('draws no actions row when the child owns its controls', (
      tester,
    ) async {
      await _pumpAppDialog(tester, content: const Text('A form.'));

      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('scrolls the child itself, so a call site nests nothing', (
      tester,
    ) async {
      // Two scroll views inside each other is an unbounded-height error rather
      // than a cosmetic problem, and a form in a dialog on a phone is taller
      // than the window more often than not.
      await _pumpAppDialog(tester, content: const SizedBox(height: 4000));

      expect(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOne,
      );
    });

    testWidgets('is not dismissed by a tap on the scrim', (tester) async {
      // `ConfirmDialog`'s barrier is dismissible for a destructive question
      // because the stray tap lands on cancel, which is safe. A stray tap
      // outside a *form* throws away everything typed into it.
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => AppButton(
                label: 'Open',
                onPressed: () => showAppDialog<void>(
                  context,
                  builder: (_) => const AppDialog(
                    title: 'Correct this shift\'s totals?',
                    content: Text('A form.'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(AppDialog), findsOne);
    });

    testWidgets('opens behind §2.1s scrim rather than Materials', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => AppButton(
                label: 'Open',
                onPressed: () => showAppDialog<void>(
                  context,
                  builder: (_) => const AppDialog(content: Text('A form.')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final route = ModalRoute.of(tester.element(find.byType(AppDialog)))!;
      expect(route.barrierColor, AppTokens.dark.colors.surface.scrim);
    });
  });

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
      expect(
        find.byKey(const ValueKey('confirm-dialog-confirm')),
        findsNothing,
      );
    });

    testWidgets('is drawn on §2.1 and §2.3 rather than on Material', (
      tester,
    ) async {
      await _pump(tester);

      final tokens = spiritTheme.extension<AppTokens>()!;
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

  group('showAppNoticeDialog', () {
    testWidgets('a lone dismissal is the primary and the only control', (
      tester,
    ) async {
      await _openNotice(tester);

      expect(_tierOf(tester, 'notice-dialog-dismiss'), AppButtonTier.primary);
      expect(find.byKey(const ValueKey('notice-dialog-action')), findsNothing);
      expect(find.byKey(const ValueKey('notice-dialog-opt-out')), findsNothing);
    });

    testWidgets('an action takes the primary and the dismissal steps down', (
      tester,
    ) async {
      // §2.1 permits one primary per region, so the dismissal cannot keep it
      // beside the action that fixes the problem.
      await _openNotice(
        tester,
        actionLabel: 'Set up printer',
        optOutLabel: 'Don’t show again',
      );

      expect(_tierOf(tester, 'notice-dialog-action'), AppButtonTier.primary);
      expect(_tierOf(tester, 'notice-dialog-dismiss'), AppButtonTier.secondary);
      expect(_tierOf(tester, 'notice-dialog-opt-out'), AppButtonTier.tertiary);
    });

    testWidgets('all three fit a phone without leaving the action row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openNotice(
        tester,
        actionLabel: 'Set up printer',
        optOutLabel: 'Don’t show again',
      );

      expect(tester.takeException(), isNull);
      final close = tester.getRect(find.text('Close'));
      final setUp = tester.getRect(find.text('Set up printer'));
      expect(close.center.dy, setUp.center.dy);
      expect(close.right, lessThan(setUp.left));
      // The opt-out sits above the row rather than squeezing into it.
      expect(
        tester.getRect(find.text('Don’t show again')).bottom,
        lessThan(close.top),
      );
    });

    testWidgets('answers with the press it was given', (tester) async {
      for (final (key, choice) in <(String?, NoticeDialogChoice)>[
        ('notice-dialog-dismiss', NoticeDialogChoice.dismissed),
        ('notice-dialog-action', NoticeDialogChoice.action),
        ('notice-dialog-opt-out', NoticeDialogChoice.optedOut),
      ]) {
        final answer = await _openNotice(
          tester,
          actionLabel: 'Set up printer',
          optOutLabel: 'Don’t show again',
          press: key,
        );
        expect(await answer, choice, reason: key);
      }
    });

    testWidgets('is not dismissed by a tap on the scrim', (tester) async {
      await _openNotice(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(NoticeDialog), findsOne);
    });
  });
}

AppButtonTier _tierOf(WidgetTester tester, String key) =>
    tester.widget<AppButton>(find.byKey(ValueKey(key))).tier;

/// Opens a notice dialog, optionally presses one of its buttons, and hands
/// back what `showAppNoticeDialog` will answer.
Future<Future<NoticeDialogChoice>> _openNotice(
  WidgetTester tester, {
  String? actionLabel,
  String? optOutLabel,
  String? press,
}) async {
  late Future<NoticeDialogChoice> answer;
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: AppButton(
              label: 'Open',
              onPressed: () => answer = showAppNoticeDialog(
                context,
                title: 'Saved as CT-1',
                notice: const AppNotice.offline('No printer is set up.'),
                stillTrue: 'The sale itself is saved.',
                actionLabel: actionLabel,
                optOutLabel: optOutLabel,
              ),
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
    await tester.pumpAndSettle();
  }
  return answer;
}

AppButton _confirm(WidgetTester tester) => tester.widget<AppButton>(
  find.byKey(const ValueKey('confirm-dialog-confirm')),
);

AppButton _cancel(WidgetTester tester) => tester.widget<AppButton>(
  find.byKey(const ValueKey('confirm-dialog-cancel')),
);

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

Future<void> _pumpAppDialog(
  WidgetTester tester, {
  required Widget content,
  String? title,
  List<Widget> actions = const <Widget>[],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: AppDialog(title: title, actions: actions, content: content),
      ),
    ),
  );
  await tester.pump();
}
