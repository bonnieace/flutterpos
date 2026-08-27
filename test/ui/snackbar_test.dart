import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/snackbar.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

final _tokens = spiritTheme.extension<AppTokens>()!;

/// Mounts a surface that can raise a snack bar, and hands back the opener.
///
/// A `ScaffoldMessenger` is what `showAppSnackBar` needs and a bare `pumpWidget`
/// of the component would not have one, so every test here goes through a real
/// one rather than pumping [AppSnackBar] on its own.
Future<void Function(AppNotice notice, {Widget? action})> _host(
  WidgetTester tester,
) async {
  late BuildContext hostContext;
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return (AppNotice notice, {Widget? action}) =>
      showAppSnackBar(hostContext, notice, action: action);
}

AppSnackBar _bar(WidgetTester tester) =>
    tester.widget<AppSnackBar>(find.byType(AppSnackBar));

BoxDecoration _statusDecorationOf(WidgetTester tester) {
  // Two nested `DecoratedBox`es: the opaque surface under the status
  // container. The status triple is the inner one.
  final boxes = tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(AppSnackBar),
          matching: find.byType(DecoratedBox),
        ),
      )
      .toList();
  return boxes[1].decoration as BoxDecoration;
}

void main() {
  group('the state matrix is the five statuses', () {
    // **A snack bar has no hover, no focus, no pressed and no disabled**: it is
    // a container that cannot be aimed at. What varies is the status it carries
    // and whether it holds an action, so that is the whole matrix.
    for (final status in AppStatus.values) {
      testWidgets('${status.name} takes its own triple and glyph', (
        tester,
      ) async {
        final show = await _host(tester);
        show(AppNotice(message: 'A sentence about ${status.name}.',
            status: status));
        await tester.pumpAndSettle();

        expect(find.text('A sentence about ${status.name}.'), findsOne);
        final role = status.role(_tokens);
        final decoration = _statusDecorationOf(tester);
        expect(decoration.color, role.bg);
        expect((decoration.border! as Border).top.color, role.border);
        // §2.1: the status is the container **and the icon**, never the colour
        // alone. §9 is pass/fail on exactly this.
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byType(AppSnackBar),
            matching: find.byType(Icon),
          ),
        );
        expect(icon.icon, status.defaultIcon);
        expect(icon.color, role.fg);
      });
    }

    testWidgets('it carries an action where one is given', (tester) async {
      final show = await _host(tester);
      show(
        const AppNotice.refused('That did not save.'),
        action: AppButton(label: 'Retry', onPressed: () {}),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppSnackBar),
          matching: find.text('Retry'),
        ),
        findsOne,
      );
    });

    testWidgets('and draws none where one is not', (tester) async {
      final show = await _host(tester);
      show(const AppNotice.confirmed('Saved.'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppSnackBar),
          matching: find.byType(AppButton),
        ),
        findsNothing,
      );
    });
  });

  group('the shape and the surface', () {
    testWidgets('radius.md, the same corner Callout has', (tester) async {
      // `OPEN_QUESTIONS.md` decision 26a lists the snack bar among the
      // components that deliberately do not take `radius.pill`, and names no
      // replacement. `md` is §2.3's row for "cards, rows, sheets" and is what
      // `Callout` reads, so the two notices carrying the same sentence are the
      // same shape rather than two shapes for one meaning.
      final show = await _host(tester);
      show(const AppNotice.confirmed('Saved.'));
      await tester.pumpAndSettle();

      expect(
        _statusDecorationOf(tester).borderRadius,
        BorderRadius.circular(_tokens.radius.md),
      );
    });

    testWidgets('it is opaque, so the page does not read through it', (
      tester,
    ) async {
      // §2.1's `bg` is translucent in Profound Verdant. A translucent block
      // floating over a scrolling list lets the words behind it show through
      // the words in front, so an opaque surface sits under the status one.
      final show = await _host(tester);
      show(const AppNotice.confirmed('Saved.'));
      await tester.pumpAndSettle();

      final outer =
          tester
                  .widgetList<DecoratedBox>(
                    find.descendant(
                      of: find.byType(AppSnackBar),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .first
                  .decoration
              as BoxDecoration;
      expect(outer.color, _tokens.colors.surface.overlay);
      expect(outer.color!.a, 1.0);
    });

    testWidgets('the prose is not tinted by the status', (tester) async {
      // §2.1's rule is that the status is the container plus the icon plus the
      // word, not that every word is coloured: a paragraph set in status red is
      // harder to read than a paragraph beside a red glyph.
      final show = await _host(tester);
      show(const AppNotice.refused('That did not save.'));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(AppSnackBar),
          matching: find.text('That did not save.'),
        ),
      );
      expect(text.style!.color, _tokens.colors.text.primary);
      expect(text.style!.color, isNot(AppStatus.problem.role(_tokens).fg));
    });
  });

  group('how long it stays', () {
    test('a refusal and an unknown outcome get longer than a confirmation', () {
      // These two are the sentences whose content is load-bearing, and the ones
      // a person has to do something about.
      expect(AppSnackBar.dwellFor(AppStatus.ok), AppSnackBar.dwell);
      expect(AppSnackBar.dwellFor(AppStatus.info), AppSnackBar.dwell);
      expect(AppSnackBar.dwellFor(AppStatus.neutral), AppSnackBar.dwell);
      expect(
        AppSnackBar.dwellFor(AppStatus.problem),
        AppSnackBar.actionableDwell,
      );
      expect(
        AppSnackBar.dwellFor(AppStatus.attention),
        AppSnackBar.actionableDwell,
      );
      expect(
        AppSnackBar.actionableDwell,
        greaterThan(AppSnackBar.dwell),
      );
    });

    testWidgets('it withdraws itself', (tester) async {
      final show = await _host(tester);
      show(const AppNotice.confirmed('Saved.'));
      await tester.pumpAndSettle();
      expect(find.byType(AppSnackBar), findsOne);

      await tester.pump(AppSnackBar.dwell);
      await tester.pumpAndSettle();
      expect(find.byType(AppSnackBar), findsNothing);
    });
  });

  group('one answer at a time', () {
    testWidgets('a second notice replaces the first rather than queueing', (
      tester,
    ) async {
      // **The decision this component makes that Material does not.** The
      // messenger queues, so two writes in quick succession would show the
      // first answer for its full dwell before the second appeared - which on a
      // till means reading a stale sentence about money.
      final show = await _host(tester);
      show(const AppNotice.confirmed('Stock changed from 10 to 7.'));
      await tester.pumpAndSettle();
      show(const AppNotice.refused('That was refused.'));
      await tester.pumpAndSettle();

      expect(find.byType(AppSnackBar), findsOne);
      expect(_bar(tester).notice.message, 'That was refused.');
      expect(find.text('Stock changed from 10 to 7.'), findsNothing);
    });
  });

  group('a screen reader', () {
    testWidgets('is told, because nobody asked for this sentence', (
      tester,
    ) async {
      // A sentence that appears unbidden over a surface the reader is already
      // on is exactly what a live region is for: without it the confirmation
      // for a write is never announced at all.
      final show = await _host(tester);
      show(const AppNotice.confirmed('Saved.'));
      await tester.pumpAndSettle();

      // Read off the widget rather than the semantics node's flag set, because
      // the flag API is mid-deprecation and this assertion should outlive it.
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(AppSnackBar),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.liveRegion, isTrue);
    });
  });

  group('where there is no messenger', () {
    testWidgets('it degrades to nothing rather than throwing', (tester) async {
      // A widget test pumping a component bare has no `ScaffoldMessenger`, and
      // that is not a state to design for - so it answers null instead of
      // taking the surface down with it.
      //
      // **No `MaterialApp` here, and that is the point of the test.**
      // `MaterialApp` installs a messenger of its own whether or not there is a
      // `Scaffold` under it, so a tree that merely lacks the `Scaffold` still
      // finds one and proves nothing.
      late BuildContext bare;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              bare = context;
              return const SizedBox.expand();
            },
          ),
        ),
      );

      expect(
        showAppSnackBar(bare, const AppNotice.confirmed('Saved.')),
        isNull,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppSnackBar), findsNothing);
    });
  });
}
