import 'package:flutter/material.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/buttons.dart';
import 'package:uzapay_pos/ui/states.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/ui/tokens.dart';
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

    testWidgets('settles rather than looping, per §6.4s budget', (
      tester,
    ) async {
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

    testWidgets('a glyph is drawn in its ring, in place of the mark', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: const Scaffold(
            body: EmptyState(
              title: 'No receipts sent yet',
              icon: Icons.chat_outlined,
            ),
          ),
        ),
      );
      await tester.pump();

      final glyph = find.byIcon(Icons.chat_outlined);
      expect(glyph, findsOne);
      // The ring, at its token.
      final ring = find.ancestor(of: glyph, matching: find.byType(Container));
      expect(
        tester.getSize(ring.first),
        Size.square(AppIconography.standard.emptyRing),
      );
      // In place of the painted box, not beside it: one mark.
      expect(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.painter != null,
          ),
        ),
        findsNothing,
      );
      expect(find.text('No receipts sent yet'), findsOne);
    });
  });

  group('LoadingState', () {
    testWidgets('says what is being read, which is §5.1s whole complaint', (
      tester,
    ) async {
      // §5.1's row is "bare `CircularProgressIndicator`" and the word doing the
      // work is *bare*. The message is required for that reason.
      await _pumpLoading(tester, message: 'Opening the business.');

      expect(find.text('Opening the business.'), findsOne);
      expect(find.byType(CircularProgressIndicator), findsOne);
    });

    testWidgets('sizes the indicator off §2.3s scale and paints the accent', (
      tester,
    ) async {
      await _pumpLoading(tester, message: 'Opening the business.');

      // 32 is on §2.3's permitted list; §2.1's 16 is the *button's* row.
      expect(LoadingState.indicatorSize, AppSpacing.scale.s32);
      final box = tester.getSize(
        find
            .ancestor(
              of: find.byType(CircularProgressIndicator),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(box, Size(AppSpacing.scale.s32, AppSpacing.scale.s32));

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(
        indicator.valueColor?.value,
        spiritTheme.extension<AppTokens>()!.colors.action.primary.container,
      );
    });
  });

  group('ErrorState', () {
    testWidgets('draws §7s four parts', (tester) async {
      // §7: "`status.problem` badge, the record's identifier in `mono`, a plain
      // statement of what could not be read, and - this matters - what is still
      // true despite it."
      await _pumpError(
        tester,
        badgeLabel: 'Not read',
        statement: '2 sale lines could not be read.',
        identifier: 'SALE-0042',
        stillTrue: 'They moved no stock.',
      );

      expect(find.byType(StatusBadge), findsOne);
      expect(find.text('Not read'), findsOne);
      expect(find.text('SALE-0042'), findsOne);
      expect(find.text('2 sale lines could not be read.'), findsOne);
      expect(find.text('They moved no stock.'), findsOne);
    });

    testWidgets('sets the identifier in the mono role, per §7', (tester) async {
      await _pumpError(
        tester,
        badgeLabel: 'Not read',
        statement: '2 sale lines could not be read.',
        identifier: 'SALE-0042',
      );

      final reference = tester.widget<Text>(find.text('SALE-0042'));
      expect(
        reference.style?.fontFamily,
        AppTypeRoles.standard.mono.fontFamily,
      );
      expect(reference.style?.fontFamily, isNotNull);
    });

    testWidgets('omits the identifier and the reassurance when there are none', (
      tester,
    ) async {
      // A failure that is not about one record has no identifier to print, and
      // printing a UID there would be §8 rule 1's own worked example.
      await _pumpError(
        tester,
        badgeLabel: 'Not opened',
        statement: 'We could not open your business account.',
      );

      expect(find.byType(Text), findsExactly(2));
    });

    testWidgets('carries no animated mark, per §6.4s banned list', (
      tester,
    ) async {
      // §6.4: "Animated illustrations on error and failed-to-read states. A
      // person looking at '2 sale lines could not be read' needs information,
      // not a sad mascot." Asserting that nothing is running is the strongest
      // form of that available to the harness, which cannot see motion.
      await _pumpError(
        tester,
        badgeLabel: 'Not read',
        statement: '2 sale lines could not be read.',
      );

      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('takes a status, so a dead end is not painted as a fault', (
      tester,
    ) async {
      // The platform route with no console reaches this: nothing failed, and
      // §2.1's `neutral` is "archived, retired, closed".
      await _pumpError(
        tester,
        badgeLabel: 'Unavailable',
        statement: 'Platform administrator access is not available.',
        status: AppStatus.neutral,
      );

      final badge = tester.widget<StatusBadge>(find.byType(StatusBadge));
      expect(badge.status, AppStatus.neutral);
    });

    testWidgets('wraps its actions rather than rowing them', (tester) async {
      // Two 48-high pills with verb phrases do not fit a phone beside each
      // other, which is the finding `ConfirmDialog`'s actions already record.
      await _pumpError(
        tester,
        badgeLabel: 'Not opened',
        statement: 'We could not open your business account.',
        actions: <Widget>[
          AppButton(
            label: 'Retry',
            tier: AppButtonTier.primary,
            onPressed: () {},
          ),
          AppButton(label: 'Sign out', onPressed: () {}),
        ],
      );

      expect(
        find.descendant(
          of: find.byType(ErrorState),
          matching: find.byType(Wrap),
        ),
        findsOne,
      );
      expect(find.byType(AppButton), findsExactly(2));
    });
  });

  group("a provenance line is §5.2's row, and nothing else is", () {
    const line = 'Recorded 2026-08-01 09:00 UTC by Amina';
    final tokens = spiritTheme.extension<AppTokens>()!;

    testWidgets('it draws caption on text.tertiary', (tester) async {
      await _pumpProvenance(tester);
      final style = _provenanceStyle(tester, line);
      expect(style.fontSize, tokens.typography.caption.fontSize);
      expect(style.fontWeight, tokens.typography.caption.fontWeight);
      expect(style.height, tokens.typography.caption.height);
      expect(style.color, tokens.colors.text.tertiary);
    });

    testWidgets("and it names one of the app's families", (tester) async {
      // The defect next door, asserted here too: a style that names no family
      // renders in whatever the platform falls back to, and in the harness in
      // nothing at all. This reads a role so it cannot - but the assertion costs
      // a line and the failure it catches sat in `screenshots/` for nine days.
      await _pumpProvenance(tester);
      expect(
        _provenanceStyle(tester, line).fontFamily,
        AppTypeRoles.interfaceFamily,
      );
    });

    test('styleOf is the style it draws, so a measurer cannot drift', () {
      // `RecordList`'s narrow-loss allocator measures provenance to decide the
      // identity column's width. Before this component the allocator named
      // `typography.caption` and the renderer named `typography.caption`, and
      // nothing tied them - a repoint of one would have allocated the table's
      // columns against a style nothing paints. This is that tie.
      final style = ProvenanceLine.styleOf(tokens);
      expect(style.fontSize, tokens.typography.caption.fontSize);
      expect(style.color, tokens.colors.text.tertiary);
      expect(style.fontFamily, AppTypeRoles.interfaceFamily);
    });

    test('density does not move it, though it moves the body', () {
      // §5.2 states `caption` flat, and `AppDensity` swaps only the body role.
      // So the two densities give provenance one size and the text above it two,
      // which is exactly what `96-provenance-*` photographs.
      double sizeAt(AppDensity density) =>
          ProvenanceLine.styleOf(tokens.withDensity(density)).fontSize!;

      expect(
        sizeAt(AppDensity.comfortable),
        sizeAt(AppDensity.compact),
        reason:
            'Provenance became density-aware. §5.2 states `caption` flat, so if '
            'that is wanted it is a design decision, and `96-provenance-*` stops '
            'being a pair of pictures of the same line.',
      );
      expect(
        AppDensity.comfortable.body(tokens.typography).fontSize,
        isNot(AppDensity.compact.body(tokens.typography).fontSize),
        reason:
            'The body role stopped moving with density, which is the half of '
            'this contrast that is supposed to move.',
      );
    });

    testWidgets('it is a bare line, not a semantics container', (tester) async {
      // A line inside a record, not a page speaking as one thing. `EmptyState`
      // wraps itself in `Semantics(container: true)` and this deliberately does
      // not: a container here would announce the provenance separately from the
      // record it belongs to.
      await _pumpProvenance(tester);
      expect(find.text(line), findsOne);
      expect(
        find.descendant(
          of: find.byType(ProvenanceLine),
          matching: find.byType(Semantics),
        ),
        findsNothing,
      );
    });
  });
}

Future<void> _pumpLoading(
  WidgetTester tester, {
  required String message,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(body: LoadingState(message: message)),
    ),
  );
  await tester.pump();
}

Future<void> _pumpError(
  WidgetTester tester, {
  required String badgeLabel,
  required String statement,
  String? identifier,
  String? detail,
  String? stillTrue,
  AppStatus status = AppStatus.problem,
  List<Widget> actions = const <Widget>[],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: ErrorState(
          badgeLabel: badgeLabel,
          statement: statement,
          identifier: identifier,
          detail: detail,
          stillTrue: stillTrue,
          status: status,
          actions: actions,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester, {
  required String title,
  String? hint,
  Widget? action,
}) async {
  await tester.pumpWidget(_Host(title: title, hint: hint, action: action));
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

/// One provenance line under the app's own theme.
///
/// **`theme: spiritTheme`, not a `const MaterialApp`**, which cost a failing run
/// to notice: without it `AppTokens.componentOf` falls back to the default token
/// set rather than the registered palette, and `text.tertiary` is a different
/// green in each. Every other pump in this file passes the theme for the same
/// reason.
Future<void> _pumpProvenance(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    theme: spiritTheme,
    home: const Scaffold(
      body: ProvenanceLine('Recorded 2026-08-01 09:00 UTC by Amina'),
    ),
  ),
);

/// The style [ProvenanceLine] sets for [label].
///
/// Read off the `Text` widget rather than the resolved `RichText`, because this
/// component sets the whole style itself instead of leaning on an ancestor -
/// which is the property being asserted.
TextStyle _provenanceStyle(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!;
