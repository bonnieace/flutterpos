import 'dart:io' show File;

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
    final AppActionRoles action = spiritTheme
        .extension<AppTokens>()!
        .colors
        .action;

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

  // **The half of the 2026-08-22 type repoint that was still open, and the one
  // no assertion could have caught.** `spiritTheme`'s own note said naming a
  // family on every `AppTypeRoles` role "is what reaches the component themes
  // below". It reaches the ones that *read a role*. Four of them did not: they
  // were written as `TextStyle(color: ...)` inline, and a component theme's text
  // style **replaces** the text theme's rather than merging onto it - so those
  // four arrived at the engine with a null family, a null size and a null
  // weight, whatever `ThemeData.fontFamily` said.
  //
  // Nothing in the repository would have said so. The type tests measure
  // `AppTypeRoles` and `TextTheme`, and all fifteen `TextTheme` slots were
  // correct; these four are neither. What said so was a picture:
  // `screenshots/web-full/18-manage-catalog.png` drew the `Categories` row as
  // filled boxes and the category picker four inches below it as words, because
  // the first is a raw Material `Chip` reading `chipTheme.labelStyle` and the
  // second is a `FilterChipBar` naming `typography.labelMedium` itself.
  //
  // **These resolve the component rather than reading the theme**, which is the
  // property that makes them worth having: a future `ChipThemeData` written
  // correctly and then wrapped by something that drops it would still fail here.
  // `SnackBar` is included because no capture in the harness drives one, so a
  // picture will never cover it.
  group('every component this theme restyles renders in one of its families', () {
    const families = <String>[
      AppTypeRoles.interfaceFamily,
      AppTypeRoles.monoFamily,
    ];

    /// The style the engine is actually handed for [label], after the component,
    /// its theme, and the text theme have all had their say.
    TextStyle resolvedStyle(WidgetTester tester, String label) {
      final rich = tester.widget<RichText>(
        find.descendant(of: find.text(label), matching: find.byType(RichText)),
      );
      return rich.text.style!;
    }

    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: spiritTheme,
        home: Scaffold(body: Center(child: child)),
      ),
    );

    void expectNamedFamily(TextStyle style, String what) {
      expect(
        style.fontFamily,
        isIn(families),
        reason:
            '$what reached the engine in "${style.fontFamily}". A component '
            'theme text style REPLACES the text theme\'s rather than merging '
            'onto it, so a `TextStyle(color: ...)` written inline in '
            '`lib/theme.dart` carries no family at all - and '
            '`ThemeData.fontFamily` does not rescue it. Point the style at an '
            '`AppTypeRoles` role and `copyWith` the colour onto it.',
      );
      expect(
        style.fontSize,
        isNotNull,
        reason:
            '$what has no size, so it takes a Material default rather '
            'than a §2.2 role.',
      );
    }

    testWidgets('a raw Chip label', (tester) async {
      // Two active sites: the category list in `catalog_management_panel.dart`
      // and the one in `tenant_catalog.dart`. Both are photographed, and both
      // were faceless.
      await pump(tester, const Chip(label: Text('Bakery')));
      expectNamedFamily(resolvedStyle(tester, 'Bakery'), 'Chip.label');
    });

    testWidgets('a ListTile subtitle, which is not its title', (tester) async {
      await pump(
        tester,
        const ListTile(title: Text('Milk 500ml'), subtitle: Text('Drinks')),
      );
      // Both, deliberately: the title was always right and the subtitle was
      // always wrong, which is exactly why one assertion over the component
      // would have passed.
      expectNamedFamily(resolvedStyle(tester, 'Milk 500ml'), 'ListTile.title');
      expectNamedFamily(resolvedStyle(tester, 'Drinks'), 'ListTile.subtitle');
    });

    testWidgets('an InputDecoration label', (tester) async {
      await pump(
        tester,
        const TextField(decoration: InputDecoration(labelText: 'Currency')),
      );
      // This one turned out already correct - `InputDecorator` merges onto the
      // text theme - and it is asserted anyway, because the note in
      // `lib/theme.dart` names it among the components the trap applies to and
      // an inline style here would be as invisible as the other four were.
      expectNamedFamily(
        resolvedStyle(tester, 'Currency'),
        'InputDecoration.labelStyle',
      );
    });

    testWidgets('a SnackBar sentence', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Details updated.')),
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      expectNamedFamily(
        resolvedStyle(tester, 'Details updated.'),
        'SnackBar.contentTextStyle',
      );
    });

    testWidgets('a bare Text, which is the fallback path', (tester) async {
      // `ThemeData.fontFamily` covers whatever is built from neither a role nor
      // a component theme, and `lib/theme.dart` says so. This is that claim.
      await pump(tester, const Text('Business: dev-corner-shop'));
      expectNamedFamily(
        resolvedStyle(tester, 'Business: dev-corner-shop'),
        'a bare Text under DefaultTextStyle',
      );
    });

    // **The raw Material controls Phase 04's screens press, measured rather
    // than assumed.** §9 makes 48dp pass/fail, and `test/ui/tokens_test.dart`
    // asserts it for `filledButtonTheme`, `elevatedButtonTheme` and
    // `outlinedButtonTheme` - the three that have a `minimumSize` to read. The
    // widget families below have no component theme in `lib/theme.dart` at all,
    // so there is no style to assert against and nothing that would stop one
    // being added later with a Material default under the floor. The only way
    // to check them is to draw one, which is what this does.
    //
    // Phase 04 opened this because the stock route's Add stock / Remove stock
    // control is a bare `SegmentedButton` and looked like a §9 defect. It is
    // not - it draws at 48 - and the measurement is worth keeping precisely
    // because the conclusion was the opposite of the guess.
    testWidgets('§9\'s 48dp floor holds for the unthemed Material controls', (
      tester,
    ) async {
      await pump(
        tester,
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: true, label: Text('Add stock')),
            ButtonSegment<bool>(value: false, label: Text('Remove stock')),
          ],
          selected: const <bool>{true},
          onSelectionChanged: (_) {},
        ),
      );
      expect(
        tester.getSize(find.byType(SegmentedButton<bool>)).height,
        greaterThanOrEqualTo(48),
        reason:
            'the stock route draws its direction chooser as a bare '
            'SegmentedButton, and three routes in this app do. §9 makes the '
            'touch target pass/fail.',
      );

      await pump(
        tester,
        Checkbox(value: true, onChanged: (_) {}),
      );
      expect(
        tester.getSize(find.byType(Checkbox)).shortestSide,
        greaterThanOrEqualTo(48),
        reason:
            'the correction form and the bulk selector both draw one, and '
            '`checkboxTheme` sets colours without a target size.',
      );
    });
  });

  // **The three `TextTheme` slots this theme sets by hand, and the rule that
  // keeps them honest.** The other twelve are Material's own metrics with this
  // theme's family and colour applied; these three were written out, and all
  // three carried a size §2.2 does not have - `headlineLarge` 40 where the
  // largest role is 32, `bodyMedium` 16 with Material's 20/14 leading where
  // §2.2 says 16 / 24, and `labelLarge` 15 / 600 where the design *measures*
  // `.btn-primary` at 14 / 700.
  //
  // The colour tests above would have passed on any of those, because a colour
  // is right or wrong independently of a size. So would the type tests in
  // `test/ui/tokens_test.dart`, which measure `AppTypeRoles` and never ask
  // whether the theme reads it.
  group('the theme names no type metric of its own - §2.2 and hard rule 2', () {
    final type = spiritTheme.extension<AppTokens>()!.typography;

    /// Everything about a style except its colour, which is the theme's to set.
    ({
      String? family,
      double? size,
      FontWeight? weight,
      double? height,
      double? tracking,
    })
    metricsOf(TextStyle style) => (
      family: style.fontFamily,
      size: style.fontSize,
      weight: style.fontWeight,
      height: style.height,
      tracking: style.letterSpacing,
    );

    test('headlineLarge is `display`, whatever reads it', () {
      // Zero readers in `lib/` today - no app widget names it and no stock
      // Material component resolves to it - so this is not about a rendering. It
      // is about the slot not being able to hand 40 to whatever reads it next.
      expect(
        metricsOf(spiritTheme.textTheme.headlineLarge!),
        metricsOf(type.display),
      );
    });

    test('bodyMedium is `body.lg`, which is the app\'s body text', () {
      // `AppDensity.comfortable` reads `AppBodyRole.large`, and every bare
      // `Text` in the app resolves here through `DefaultTextStyle`. The size was
      // already 16; the leading was Material's, not §2.2's.
      expect(
        metricsOf(spiritTheme.textTheme.bodyMedium!),
        metricsOf(type.bodyLarge),
      );
    });

    test('labelLarge is `label.lg`, the measured button role', () {
      expect(
        metricsOf(spiritTheme.textTheme.labelLarge!),
        metricsOf(type.labelLarge),
      );
      // The half of the original note worth keeping, stated as what is
      // observable rather than as what is authored. `ThemeData` applies its body
      // and display colours to every slot, so a style written with no colour does
      // not arrive with none - it arrives with the theme's. Which is the point:
      // a button label takes the same ink as the text beside it and cannot drift
      // into one of its own.
      expect(
        spiritTheme.textTheme.labelLarge!.color,
        spiritTheme.textTheme.bodyLarge!.color,
      );
    });

    test('and `lib/theme.dart` writes no size, weight, leading or tracking', () {
      // **A source scan, because the assertions above only cover the three slots
      // that exist today.** A fourth written next month with a literal in it
      // would pass every one of them. What hard rule 2 actually forbids is the
      // number, wherever it appears, so that is what this looks for.
      //
      // Comments are stripped first: this file explains the figures it removed,
      // and a scan that could not tell prose from code would forbid saying why.
      final source = File('lib/theme.dart').readAsStringSync();
      final offenders = <String>[];
      final lines = source.split(RegExp(r'\r?\n'));
      for (var index = 0; index < lines.length; index++) {
        final comment = lines[index].indexOf('//');
        final code = comment < 0
            ? lines[index]
            : lines[index].substring(0, comment);
        final match = RegExp(
          r'\b(fontSize|fontWeight|letterSpacing|height|wordSpacing):',
        ).firstMatch(code);
        if (match == null) continue;
        offenders.add('lib/theme.dart:${index + 1} names ${match.group(1)}');
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '${offenders.join('; ')}. Type metrics belong to §2.2 and reach the '
            'theme through an `AppTypeRoles` role, never as a number here. Point '
            'the style at the role and `copyWith` the colour onto it.',
      );
    });
  });

  test('the theme is a dark one, because the scaffold is', () {
    // Stated directly as well as measured. The measurements above would also
    // pass if somebody hand-coloured fifteen styles; this is the reason they
    // do not have to.
    expect(spiritTheme.brightness, Brightness.dark);
    expect(spiritTheme.colorScheme.brightness, Brightness.dark);
    expect(
      spiritTheme.scaffoldBackgroundColor.computeLuminance(),
      lessThan(0.1),
    );
  });
}
