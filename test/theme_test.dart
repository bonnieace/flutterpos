import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/wcag.dart';

void main() {
  // The whole point of these: the app paints on a near-black scaffold, and a
  // theme that forgets to say so is a light theme whose text is near-black
  // too. That shipped, and a real run on an Android device was the first thing
  // to notice - the landing route's headings were there and unreadable.
  group('every text style is legible on the scaffold it is painted on', () {
    final styles = <String, TextStyle?>{
      'displayLarge': spiritTheme.textTheme.displayLarge,
      'displayMedium': spiritTheme.textTheme.displayMedium,
      'displaySmall': spiritTheme.textTheme.displaySmall,
      'headlineLarge': spiritTheme.textTheme.headlineLarge,
      'headlineMedium': spiritTheme.textTheme.headlineMedium,
      'headlineSmall': spiritTheme.textTheme.headlineSmall,
      'titleLarge': spiritTheme.textTheme.titleLarge,
      'titleMedium': spiritTheme.textTheme.titleMedium,
      'titleSmall': spiritTheme.textTheme.titleSmall,
      'bodyLarge': spiritTheme.textTheme.bodyLarge,
      'bodyMedium': spiritTheme.textTheme.bodyMedium,
      'bodySmall': spiritTheme.textTheme.bodySmall,
      'labelLarge': spiritTheme.textTheme.labelLarge,
      'labelMedium': spiritTheme.textTheme.labelMedium,
      'labelSmall': spiritTheme.textTheme.labelSmall,
    };

    test('the theme resolves a colour for every one of them', () {
      // A null colour is not a pass. It would mean the style falls through to
      // something this test never measured.
      for (final entry in styles.entries) {
        expect(entry.value, isNotNull, reason: '${entry.key} is missing');
        expect(
          entry.value!.color,
          isNotNull,
          reason: '${entry.key} resolves no colour',
        );
      }
    });

    test('each one clears WCAG AA against the scaffold', () {
      for (final entry in styles.entries) {
        final style = entry.value!;
        final required = requiredContrastFor(style);
        expect(
          contrastRatio(style.color!, spiritTheme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(required),
          reason:
              '${entry.key} is unreadable on the scaffold: it needs $required:1',
        );
      }
    });

    test('and against the raised surface as well', () {
      // Cards, dialogs, and sheets paint on this rather than the scaffold, so
      // a style that only clears the darker background is not enough.
      for (final entry in styles.entries) {
        expect(
          contrastRatio(entry.value!.color!, spiritTheme.colorScheme.surface),
          greaterThanOrEqualTo(requiredContrastFor(entry.value!)),
          reason: '${entry.key} is unreadable on a card or dialog',
        );
      }
    });
  });

  // `design.md` §11 step 2. A ripple exists only mid-press and an overscroll
  // glow only mid-drag, so neither can appear in a screenshot and neither is
  // proved by one. These are what stand in for that until a device run.
  group('no ink ripple survives, and a press is the overlay of its tier', () {
    // The palette the theme registers, not a named one: this group is about the
    // overlay *mechanism*, which is the same rule whichever palette is active.
    final AppActionRoles action =
        spiritTheme.extension<AppTokens>()!.colors.action;

    test('the ripple is killed at the theme, and Material 3 is stated', () {
      expect(spiritTheme.splashFactory, NoSplash.splashFactory);
      // Not decoration. `DESIGN-AUDIT.md` §6 decision 4 verified that
      // `InkResponse` falls back to `ThemeData.splashFactory` and the M3 button
      // defaults delegate to it - but the **M2** paths in `outlined_button.dart`
      // and `text_button.dart` hardcode `InkRipple.splashFactory`. So flipping
      // this flag would silently restore ripples on two of the four tiers, and
      // this is the assertion that would notice.
      expect(spiritTheme.useMaterial3, isTrue);
    });

    testWidgets('every button reaches the ink with no splash and the fills '
        'of its own tier', (tester) async {
      // Asserted at the `InkWell` rather than at the `ButtonStyle`, because
      // what could go wrong is the merge: a button resolves its widget style
      // over the theme's over the M3 defaults, and a theme-level property that
      // loses that race is invisible from the theme object alone.
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Scaffold(
            body: Column(
              children: <Widget>[
                FilledButton(onPressed: () {}, child: const Text('Filled')),
                ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
                OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
                TextButton(onPressed: () {}, child: const Text('Text')),
              ],
            ),
          ),
        ),
      );

      final tiers = <Type, AppActionRole>{
        FilledButton: action.primary,
        ElevatedButton: action.primary,
        OutlinedButton: action.secondary,
        TextButton: action.tertiary,
      };
      for (final entry in tiers.entries) {
        final ink = tester.widget<InkWell>(
          find.descendant(
            of: find.byType(entry.key),
            matching: find.byType(InkWell),
          ),
        );
        expect(
          ink.splashFactory,
          NoSplash.splashFactory,
          reason: '${entry.key} still has a ripple',
        );
        expect(
          ink.overlayColor!.resolve(<WidgetState>{WidgetState.pressed}),
          entry.value.pressedFill(),
          reason: '${entry.key} does not press to the fill of its tier',
        );
        expect(
          ink.overlayColor!.resolve(<WidgetState>{WidgetState.hovered}),
          entry.value.hoverFill(),
          reason: '${entry.key} does not hover to the fill of its tier',
        );
        // §2.1 gives focus a ring rather than an overlay, and the ring is
        // `AppButton`'s in step 3. What must not happen meanwhile is a focused
        // button resolving null and painting nothing at all.
        expect(
          ink.overlayColor!.resolve(<WidgetState>{WidgetState.focused}),
          entry.value.hoverFill(),
          reason: '${entry.key} gives a keyboard user no feedback',
        );
        expect(
          ink.overlayColor!.resolve(<WidgetState>{}),
          isNull,
          reason: '${entry.key} paints an overlay at rest',
        );
      }
    });

    test('the two rules in §2.1 are both honoured, and they differ', () {
      // The primary tier moves its *container* to a named colour; the other
      // three wash their own *label* over a transparent one. A press overlay
      // that knew only one of those would be right about a quarter of the app.
      // **Asserted as the rule, not as two hexes.** This used to name
      // `#34B169` and `#3DD47C`, which were `design.md` §2.1's pressed and
      // hovered greens, and it failed on the palette swap for the wrong reason:
      // the mechanism was intact and only the colours had moved. The values
      // themselves are pinned in `test/ui/tokens_test.dart`, against the
      // decision that chose them.
      expect(action.primary.pressedFill(), action.primary.pressedContainer);
      expect(action.primary.hoverFill(), action.primary.hoverContainer);
      // Opaque, because this tier replaces its container rather than washing
      // something over it - which is the half of §2.1 the loop below is not.
      expect(action.primary.pressedFill().a, 1.0);
      expect(action.primary.hoverFill().a, 1.0);
      for (final tier in <AppActionRole>[
        action.secondary,
        action.tertiary,
        action.destructive,
      ]) {
        expect(tier.hoverFill().a, closeTo(0.08, 0.001));
        expect(tier.pressedFill().a, closeTo(0.12, 0.001));
        expect(tier.pressedFill().r, tier.label.r);
      }
    });
  });

  group('scrolling bounces and never glows', () {
    Widget listApp({ScrollBehavior? behavior}) => MaterialApp(
      theme: spiritTheme,
      scrollBehavior: behavior,
      home: Scaffold(
        body: ListView(
          children: <Widget>[
            for (var index = 0; index < 40; index++) Text('Row $index'),
          ],
        ),
      ),
    );

    /// Whether the physics a position ended up with bounces anywhere in its
    /// chain.
    ///
    /// `ScrollView` prepends `AlwaysScrollableScrollPhysics` to whatever the
    /// behaviour supplied, so a position holds a chain rather than the type the
    /// behaviour named and `isA<BouncingScrollPhysics>()` over the outermost
    /// link is an assertion that can only fail. Found by writing it that way.
    bool bounces(ScrollPhysics? physics) {
      for (var link = physics; link != null; link = link.parent) {
        if (link is BouncingScrollPhysics) return true;
      }
      return false;
    }

    testWidgets('the app scrolls on bouncing physics with no indicator', (
      tester,
    ) async {
      await tester.pumpWidget(listApp(behavior: const SpiritScrollBehavior()));

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(bounces(position.physics), isTrue);
      expect(find.byType(GlowingOverscrollIndicator), findsNothing);
      expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    });

    testWidgets('and the same tree without it does neither', (tester) async {
      // The control. Without it the two assertions above would pass against a
      // change that did nothing, which is the failure mode a near-empty
      // screenshot diff already invites for this step.
      await tester.pumpWidget(listApp());

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(bounces(position.physics), isFalse);
      expect(
        find.byType(GlowingOverscrollIndicator).evaluate().length +
            find.byType(StretchingOverscrollIndicator).evaluate().length,
        greaterThan(0),
      );
    });
  });

  test('the theme is a dark one, because the scaffold is', () {
    // Stated directly as well as measured. The measurements above would also
    // pass if somebody hand-coloured fifteen styles; this is the reason they
    // do not have to.
    expect(spiritTheme.brightness, Brightness.dark);
    expect(spiritTheme.colorScheme.brightness, Brightness.dark);
    expect(spiritTheme.scaffoldBackgroundColor.computeLuminance(), lessThan(0.1));
  });
}
