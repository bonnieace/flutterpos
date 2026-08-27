import 'dart:io' show Directory, File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

final _tokens = spiritTheme.extension<AppTokens>()!;

/// Mounts [child] under the app's own theme, optionally at compact density.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  AppDensity density = AppDensity.comfortable,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Theme(
            data: Theme.of(context).copyWith(
              extensions: <ThemeExtension<dynamic>>[
                AppTokens.of(context).withDensity(density),
              ],
            ),
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ),
      ),
    ),
  );
}

BoxDecoration _decorationOf(WidgetTester tester, Type owner) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(of: find.byType(owner), matching: find.byType(DecoratedBox))
        .first,
  );
  return box.decoration as BoxDecoration;
}

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  group('every status is a container plus an icon plus a word', () {
    testWidgets('all five draw their own triple and none is bare text', (
      tester,
    ) async {
      // §2.1's rule, measured over the whole set rather than over one status
      // somebody remembered: the defect being replaced is one green doing seven
      // jobs, so the test that matters is that the five differ.
      for (final status in AppStatus.values) {
        await _pump(tester, StatusBadge(status: status, label: status.name));
        final decoration = _decorationOf(tester, StatusBadge);
        final role = status.role(_tokens);
        expect(decoration.color, role.bg, reason: '${status.name} background');
        expect(
          (decoration.border! as Border).top.color,
          role.border,
          reason: '${status.name} border',
        );
        expect(
          _styleOf(tester, status.name).color,
          role.fg,
          reason: '${status.name} foreground',
        );
      }
    });

    test('the five triples are five distinct colours', () {
      // The one assertion that would have caught the original defect. A palette
      // where two statuses share a foreground is a palette that cannot tell a
      // person which of the two they are looking at.
      final foregrounds = <Color>{
        for (final status in AppStatus.values) status.role(_tokens).fg,
      };
      expect(foregrounds.length, AppStatus.values.length);
    });

    testWidgets('an icon is drawn for every status, with no call site asked', (
      tester,
    ) async {
      // §5.2: "The icon is required - it is what makes the status legible
      // without colour." A default per status is what stops that requirement
      // from being a blank each call site fills differently.
      for (final status in AppStatus.values) {
        await _pump(tester, StatusBadge(status: status, label: 'Ready'));
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byType(StatusBadge),
            matching: find.byType(Icon),
          ),
        );
        expect(icon.icon, status.defaultIcon);
        expect(icon.size, StatusBadge.iconSize);
      }
    });

    test('no two statuses share a default glyph', () {
      // Same reasoning as the colour test, for the half that survives a
      // colourblind reader and a printed rota.
      final glyphs = <IconData>{
        for (final status in AppStatus.values) status.defaultIcon,
      };
      expect(glyphs.length, AppStatus.values.length);
    });

    testWidgets('a call site may override the glyph', (tester) async {
      await _pump(
        tester,
        const StatusBadge(
          status: AppStatus.attention,
          label: 'Invited',
          icon: Icons.mail_outline,
        ),
      );
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.mail_outline);
    });
  });

  group('a notice carries which answer it is', () {
    // Seven panels held a `String? _notice` and drew it as a bare `Text`, so the
    // one thing a person needs first — did the thing I pressed happen — was
    // carried entirely by reading the sentence. These four constructors are the
    // four outcomes this app's write boundaries already model, mapped once here
    // instead of at every call site.

    test('the four outcomes map to the four §2.1 rows that mean them', () {
      expect(const AppNotice.confirmed('a').status, AppStatus.ok);
      expect(const AppNotice.refused('a').status, AppStatus.problem);
      expect(const AppNotice.unknown('a').status, AppStatus.attention);
      expect(const AppNotice.offline('a').status, AppStatus.info);
    });

    test('an unknown outcome is awaiting rather than failed', () {
      // The distinction the sentences have always drawn and the colour never
      // did: an ambiguous write may well have landed, and every one of those
      // sentences tells a person to go and look. §2.1's `attention` is
      // "unreconciled, pending, awaiting" in its own words.
      expect(
        const AppNotice.unknown('The result is unknown.').status,
        isNot(AppStatus.problem),
      );
    });

    test('no constructor produces neutral, which belongs to a record', () {
      // §2.1 gives `neutral` "archived, retired, closed" — a standing a *record*
      // has. A page reporting on a write it just attempted never has one, and
      // the absence of that constructor is what stops a call site reaching for
      // it. The bulk report's unchanged *row* is neutral; a page saying there
      // was nothing to do is `info`, and one status meaning both at two scales
      // is the failure §2.1 exists to end.
      for (final notice in <AppNotice>[
        const AppNotice.confirmed('a'),
        const AppNotice.refused('a'),
        const AppNotice.unknown('a'),
        const AppNotice.offline('a'),
      ]) {
        expect(notice.status, isNot(AppStatus.neutral));
      }
    });

    test('two notices saying the same thing the same way are equal', () {
      // Value equality, so a test can assert a whole notice rather than picking
      // it apart, and so a `setState` with an identical answer is not a change.
      expect(
        const AppNotice.confirmed('Published.'),
        const AppNotice.confirmed('Published.'),
      );
      expect(
        const AppNotice.confirmed('Published.'),
        isNot(const AppNotice.refused('Published.')),
      );
      expect(
        const AppNotice.confirmed('Published.').hashCode,
        const AppNotice.confirmed('Published.').hashCode,
      );
    });

    test('the general constructor still allows a status by name', () {
      expect(
        const AppNotice(message: 'a', status: AppStatus.neutral).status,
        AppStatus.neutral,
      );
    });
  });

  group('the badge is §5.2\'s badge', () {
    testWidgets('radius.md, label.md, 24h, space.8 padding', (tester) async {
      await _pump(
        tester,
        const StatusBadge(status: AppStatus.ok, label: 'Confirmed'),
      );
      final decoration = _decorationOf(tester, StatusBadge);
      // **`md` since 2026-08-26, where §5.2 and decision 26a both say `sm`.**
      // The product owner's call: at 2 a badge was a hard rectangle inside a
      // card drawn at 8, so the smallest thing on a row was also the sharpest.
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        _tokens.radius.md,
      );
      expect(tester.getSize(find.byType(StatusBadge)).height, 24);

      final style = _styleOf(tester, 'Confirmed');
      expect(style.fontSize, _tokens.typography.labelMedium.fontSize);
      expect(style.fontWeight, _tokens.typography.labelMedium.fontWeight);

      final padding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(StatusBadge),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(
        padding.padding,
        EdgeInsets.symmetric(horizontal: _tokens.spacing.s8),
      );
    });

    testWidgets('it can say how wide it will be before it is built', (
      tester,
    ) async {
      // `RecordList`'s table sizes its status column to the widest badge in the
      // list rather than to a share of the row, which it can only do if this
      // figure is the one the badge then occupies. Measured against the
      // rendering for the same reason `AppButton`'s twin is: a formula that
      // agrees with §5.2 and disagrees with the widget is worse than none.
      for (final label in <String>[
        'Active',
        'Out of stock',
        'Awaiting verification',
      ]) {
        await _pump(tester, StatusBadge(status: AppStatus.ok, label: label));
        expect(
          tester.getSize(find.byType(StatusBadge)).width,
          closeTo(
            StatusBadge.measureWidth(
              _tokens,
              label,
              ambient: DefaultTextStyle.of(
                tester.element(find.byType(StatusBadge)),
              ).style,
            ),
            0.01,
          ),
          reason: label,
        );
      }
    });

    testWidgets('it does not uppercase its own label', (tester) async {
      // §2.2 permits uppercase on `label.eyebrow` and nowhere else, and a
      // widget that cased its own label would put it somewhere §2.2 forbids
      // without any call site being able to see that it had.
      await _pump(
        tester,
        const StatusBadge(status: AppStatus.neutral, label: 'Retired'),
      );
      expect(find.text('Retired'), findsOneWidget);
      expect(find.text('RETIRED'), findsNothing);
    });

    testWidgets('the badge announces one thing, not an icon and a word', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const StatusBadge(
          status: AppStatus.attention,
          label: 'Pending',
          semanticLabel: 'This membership is pending',
        ),
      );
      expect(
        find.bySemanticsLabel('This membership is pending'),
        findsOneWidget,
      );
      // The visible word is still the visible word; only what is read aloud
      // gains the sentence around it.
      expect(find.text('Pending'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('without a semantic label it announces the word', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const StatusBadge(status: AppStatus.ok, label: 'In stock'),
      );
      expect(find.bySemanticsLabel('In stock'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('in a box narrower than its word it shortens, not overflows', (
      tester,
    ) async {
      // **A defect found 2026-08-13 by `RecordList`, whose table gives the
      // status a share of the row rather than whatever the word wants.** The
      // badge already declared `maxLines: 1` and `ellipsis`, and neither could
      // ever fire: its `Row` sits at `MainAxisSize.min` and offers its children
      // unbounded width, so a constrained badge painted the yellow overflow
      // stripe instead of a shortened word. Every badge in the app before this
      // sat in a `Wrap` and was never constrained, which is why nothing caught
      // it.
      await _pump(
        tester,
        const SizedBox(
          width: 80,
          child: StatusBadge(
            status: AppStatus.problem,
            label: 'Awaiting verification',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(StatusBadge)).width,
        lessThanOrEqualTo(80),
      );
    });
  });

  group('a callout is a status at page scale', () {
    testWidgets('it takes the triple and radius.md', (tester) async {
      await _pump(
        tester,
        const Callout(
          status: AppStatus.problem,
          message: 'The takings and the counted cash disagree by KES 400.',
        ),
      );
      final decoration = _decorationOf(tester, Callout);
      expect(decoration.color, _tokens.colors.status.problem.bg);
      expect(
        (decoration.border! as Border).top.color,
        _tokens.colors.status.problem.border,
      );
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        _tokens.radius.md,
      );
    });

    testWidgets('the prose is body text, not status-coloured text', (
      tester,
    ) async {
      // §2.1's rule is container plus icon plus word. A whole paragraph set in
      // status red is harder to read and is not what the rule asks for.
      const message = 'This shift has not been reconciled.';
      await _pump(
        tester,
        const Callout(status: AppStatus.attention, message: message),
      );
      final style = _styleOf(tester, message);
      expect(style.color, _tokens.colors.text.secondary);
      expect(style.color, isNot(_tokens.colors.status.attention.fg));
      expect(style.fontSize, _tokens.typography.bodyLarge.fontSize);
    });

    testWidgets('the glyph carries the status colour', (tester) async {
      await _pump(
        tester,
        const Callout(status: AppStatus.info, message: 'Working offline.'),
      );
      final icon = tester.widget<Icon>(
        find.descendant(of: find.byType(Callout), matching: find.byType(Icon)),
      );
      expect(icon.color, _tokens.colors.status.info.fg);
      expect(icon.icon, AppStatus.info.defaultIcon);
      expect(icon.size, Callout.glyphSize);
    });

    testWidgets('a title is title.md above the message', (tester) async {
      await _pump(
        tester,
        const Callout(
          status: AppStatus.problem,
          title: 'Nothing was saved',
          message: 'The correction was refused and no product changed.',
        ),
      );
      final style = _styleOf(tester, 'Nothing was saved');
      expect(style.fontSize, _tokens.typography.titleMedium.fontSize);
      expect(style.color, _tokens.colors.text.primary);
      expect(
        tester.getTopLeft(find.text('Nothing was saved')).dy,
        lessThan(
          tester
              .getTopLeft(
                find.text('The correction was refused and no product changed.'),
              )
              .dy,
        ),
      );
    });

    testWidgets('an action renders under the message', (tester) async {
      await _pump(
        tester,
        Callout(
          status: AppStatus.problem,
          message: 'The catalog could not be read.',
          action: TextButton(onPressed: () {}, child: const Text('Try again')),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Try again')).dy,
        greaterThan(
          tester.getTopLeft(find.text('The catalog could not be read.')).dy,
        ),
      );
    });

    testWidgets('the message follows the density body role', (tester) async {
      const message = 'Stock was adjusted by a manager.';
      await _pump(
        tester,
        const Callout(status: AppStatus.neutral, message: message),
        density: AppDensity.compact,
      );
      expect(
        _styleOf(tester, message).fontSize,
        _tokens.typography.bodyMedium.fontSize,
      );
    });
  });

  group('a disclosure keeps the writing and returns the screen', () {
    const summary = 'How a correction reaches many products';
    const body =
        'One correction can be applied across many products, and a catalog '
        'that is wrong in one field is corrected in one pass.';

    /// The height of the whole component.
    ///
    /// **This rather than the height of the prose, and the difference is the
    /// point of the component.** The explanation keeps its own intrinsic size
    /// whatever the reveal is doing; what §5.2 promises is that the *screen*
    /// gets shorter, and that is this figure.
    double heightOf(WidgetTester tester) =>
        tester.getSize(find.byType(Disclosure)).height;

    testWidgets('collapsed shows one line and not the explanation', (
      tester,
    ) async {
      await _pump(
        tester,
        const Disclosure(summary: summary, child: Text(body)),
      );
      expect(find.text(summary), findsOneWidget);
      // Not merely clipped: a closed disclosure has nothing of its explanation
      // in the tree, so a screen reader does not read out prose a person cannot
      // see either.
      expect(find.text(body), findsNothing);
    });

    testWidgets('tapping the summary opens it, and the screen grows', (
      tester,
    ) async {
      await _pump(
        tester,
        const Disclosure(summary: summary, child: Text(body)),
      );
      final closed = heightOf(tester);
      await tester.tap(find.text(summary));
      await tester.pumpAndSettle();
      expect(find.text(body), findsOneWidget);
      expect(heightOf(tester), greaterThan(closed));
    });

    testWidgets('tapping it again closes it, and the screen returns', (
      tester,
    ) async {
      await _pump(
        tester,
        const Disclosure(
          summary: summary,
          initiallyExpanded: true,
          child: Text(body),
        ),
      );
      final open = heightOf(tester);
      await tester.tap(find.text(summary));
      await tester.pumpAndSettle();
      expect(find.text(body), findsNothing);
      expect(heightOf(tester), lessThan(open));
    });

    testWidgets('it reports the change to its caller', (tester) async {
      final reported = <bool>[];
      await _pump(
        tester,
        Disclosure(
          summary: summary,
          onExpansionChanged: reported.add,
          child: const Text(body),
        ),
      );
      await tester.tap(find.text(summary));
      await tester.pumpAndSettle();
      await tester.tap(find.text(summary));
      await tester.pumpAndSettle();
      expect(reported, <bool>[true, false]);
    });

    testWidgets('the reveal is a spring, and it is still moving mid-flight', (
      tester,
    ) async {
      // §2.4: anything spatial is a spring. The evidence that this is one
      // rather than a duration is that it is somewhere between its two ends one
      // frame after the tap and has not arrived.
      await _pump(
        tester,
        const Disclosure(summary: summary, child: Text(body)),
      );
      final closed = heightOf(tester);
      await tester.tap(find.text(summary));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final midFlight = heightOf(tester);
      await tester.pumpAndSettle();
      final settled = heightOf(tester);
      expect(midFlight, greaterThan(closed));
      expect(midFlight, lessThan(settled));
    });

    testWidgets('a second tap mid-flight retargets rather than restarting', (
      tester,
    ) async {
      // `claude.md`'s motion rule and §2.4's first one. A duration-and-curve
      // animation reversed mid-flight jumps to the mirror of where it was; a
      // spring carries its position across, so the frame after the second tap
      // is near where the frame before it was.
      await _pump(
        tester,
        const Disclosure(summary: summary, child: Text(body)),
      );
      final closed = heightOf(tester);
      await tester.tap(find.text(summary));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final beforeReverse = heightOf(tester);
      await tester.tap(find.text(summary));
      await tester.pump();
      final afterReverse = heightOf(tester);
      expect(beforeReverse, greaterThan(closed));
      // Continuous: one frame cannot move it far, and it certainly cannot land
      // back where it started.
      expect((afterReverse - beforeReverse).abs(), lessThan(4));
      await tester.pumpAndSettle();
      expect(find.text(body), findsNothing);
      expect(heightOf(tester), closed);
    });

    testWidgets('reduced motion collapses the spring to instant', (
      tester,
    ) async {
      // §2.4's reduced-motion clause, and §9's "motion fully disabled under
      // disableAnimations".
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Scaffold(
              body: Disclosure(summary: summary, child: Text(body)),
            ),
          ),
        ),
      );
      await tester.tap(find.text(summary));
      await tester.pump();
      expect(find.text(body), findsOneWidget);
      // Arrived in one frame, not merely started: the reveal is at its full
      // height rather than at the first sample of a spring.
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text(body),
                matching: find.byType(ClipRect),
              ),
            )
            .height,
        tester.getSize(find.text(body)).height +
            AppTokens.dark.spacing.s4 +
            AppTokens.dark.spacing.s8,
      );
      // Nothing is left running, which is the other half of "instant".
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('disabled does not open, and takes the disabled label', (
      tester,
    ) async {
      await _pump(
        tester,
        const Disclosure(summary: summary, enabled: false, child: Text(body)),
      );
      expect(
        _styleOf(tester, summary).color,
        _tokens.colors.action.disabledLabel,
      );
      await tester.tap(find.text(summary), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text(body), findsNothing);
    });

    testWidgets('the summary is body text and the glyph is status.info', (
      tester,
    ) async {
      // §5.2: "Collapsed: one line, `body.md`, with a leading info glyph and a
      // chevron."
      await _pump(
        tester,
        const Disclosure(summary: summary, child: Text(body)),
      );
      expect(
        _styleOf(tester, summary).fontSize,
        _tokens.typography.bodyLarge.fontSize,
      );
      final glyph = tester.widget<Icon>(find.byIcon(Icons.info_outline));
      expect(glyph.color, _tokens.colors.status.info.fg);
      expect(glyph.size, Disclosure.glyphSize);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('the expanded explanation is text.secondary', (tester) async {
      // §5.2: "Expanded: the full explanation, `body.md` / `text.secondary`."
      // Asserted through the inherited style, because the prose this replaces
      // arrives as a bare `Text` with no style of its own.
      await _pump(
        tester,
        const Disclosure(
          summary: summary,
          initiallyExpanded: true,
          child: Text(body),
        ),
      );
      final style = DefaultTextStyle.of(tester.element(find.text(body))).style;
      expect(style.color, _tokens.colors.text.secondary);
      expect(style.fontSize, _tokens.typography.bodyLarge.fontSize);
    });

    testWidgets('it announces itself as an expandable control', (tester) async {
      // §9: a control a keyboard or screen-reader user meets has to say what it
      // is and what state it is in. `expanded` is the property that makes an
      // opened disclosure distinguishable from a closed one without sight.
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const Disclosure(summary: summary, child: Text(body)),
      );
      expect(
        tester.getSemantics(find.text(summary)),
        matchesSemantics(
          label: summary,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      await tester.tap(find.text(summary));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text(summary)),
        matchesSemantics(
          label: summary,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasExpandedState: true,
          isExpanded: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('the summary follows the density body role', (tester) async {
      await _pump(
        tester,
        const Disclosure(summary: summary, child: Text(body)),
        density: AppDensity.compact,
      );
      expect(
        _styleOf(tester, summary).fontSize,
        _tokens.typography.bodyMedium.fontSize,
      );
    });
  });
  group('every read-only notice is an info callout - the §2.1 lookup', () {
    test('no surface says read-only as anything but a Callout', () {
      // **A source scan, because the defect it catches is not a type error.**
      // Six surfaces tell a person that something cannot be changed, and five of
      // them render an `info` [Callout]. The sixth,
      // `checkout-configuration-read-only`, was a bare `Text` until 2026-08-22:
      // no container, no glyph, no status role - the same fact as its four
      // siblings, under the same condition, in the same feature folder as one of
      // them. §9 requires that status never be carried by colour alone, and this
      // carried it by nothing.
      //
      // **Nothing typed could have caught it**, because a `String` in a `Text` and
      // a `String` in a `Callout.message` are the same `String`. And nothing
      // *did* catch it for a different reason worth recording: every capture that
      // reaches one of these branches injects a writer, so three of the six
      // notices had never appeared in a picture. `95-read-only-notices` fixes
      // that half; this fixes the half a picture cannot, which is the next site.
      //
      // **The pattern this pins is the one five sites already agreed on**, not a
      // new rule: an `info` [Callout], titled when it states the standing of a
      // whole page and untitled when it states that one control is unavailable
      // here. The six at the time of writing:
      //
      // - `catalog-read-only`, titled - `lib/tenancy/tenant_catalog.dart`
      // - `staff-directory-read-only`, titled - `lib/tenancy/tenant_staff_directory.dart`
      // - `catalog-management-read-only`, untitled
      // - `catalog-management-product-read-only`, untitled
      // - `printer-configuration-read-only`, untitled
      // - `checkout-configuration-read-only`, untitled - the one this scan exists for
      //
      // **What it deliberately does not reach.** `checkout_print_queue_panel`
      // renders *nothing at all* when no retry is injected - the decided
      // treatment, recorded in `37c-receipts-waiting-read-only`'s own caption as
      // "a statement of what is waiting, and no control that would fail". It
      // carries no `-read-only` key, so it is not matched, and it must not be
      // pushed into carrying a notice.
      //
      // Legacy is excluded: `lib/pos/**` and `lib/screens/**` are the previous
      // single-tenant app, read-only per `CLAUDE.md` hard rule 3.
      final offenders = <String>[];
      var found = 0;

      for (final file in _activeDartFiles()) {
        final lines = file.readAsStringSync().split(RegExp(r'\r?\n'));
        for (var index = 0; index < lines.length; index++) {
          if (!_readOnlyKey.hasMatch(lines[index])) continue;
          found++;
          final where = '${_shortPath(file)}:${index + 1}';

          // The constructor this key is an argument of opens on an earlier line.
          // `dart format` puts one argument per line here, so the opener is
          // within a couple of lines; six is slack, not a guess.
          var opener = '<none>';
          var openedAt = index;
          for (var back = index - 1; back >= 0 && back >= index - 6; back--) {
            final match = _constructorOpen.firstMatch(lines[back].trim());
            if (match != null) {
              opener = match.group(1)!;
              openedAt = back;
              break;
            }
          }
          if (opener != 'Callout') {
            offenders.add(
              '$where - the key sits on `$opener`, not `Callout`. A read-only '
              'statement is the state of a surface, so it takes §2.1\'s `info` '
              'container and glyph rather than being body prose.',
            );
            continue;
          }

          // `status:` follows `key:` at every current site, but the argument
          // order is the call site's business, so the whole call is searched.
          final window = lines
              .sublist(openedAt, math.min(lines.length, index + 10))
              .join('\n');
          if (!window.contains('AppStatus.info')) {
            offenders.add(
              '$where - a `Callout`, but not an `info` one. §2.1 gives `info` the '
              'meaning "offline, read-only, informational"; every other status '
              'would claim something else happened.',
            );
          }
        }
      }

      expect(
        found,
        greaterThan(0),
        reason:
            'No `-read-only` ValueKey was found anywhere in the active app. '
            'Either every read-only notice was deleted, or the keys were '
            'renamed and this scan is now checking nothing.',
      );
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}

/// `ValueKey('<anything>-read-only')`, with or without an explicit type
/// argument.
final RegExp _readOnlyKey = RegExp(
  r"ValueKey(?:<String>)?\('[^']*-read-only'\)",
);

/// A constructor call being opened on its own line: `Callout(`, `const Callout(`.
final RegExp _constructorOpen = RegExp(r'^(?:const\s+)?([A-Z]\w*)\($');

/// Every Dart file of the app that is not legacy.
Iterable<File> _activeDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .where((file) {
      final path = file.path.replaceAll(r'\', '/');
      return !path.contains('/pos/') && !path.contains('/screens/');
    });

String _shortPath(File file) => file.path.replaceAll(r'\', '/');
