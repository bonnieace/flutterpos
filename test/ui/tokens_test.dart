import 'dart:io' show Directory, File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/wcag.dart';

/// The token layer against `design.md`, value by value.
///
/// **Why this file exists rather than more of `theme_test.dart`.**
/// `test/theme_test.dart` enumerates `TextTheme`'s fifteen slots, and four of
/// §2.2's roles - `numeric.hero`, `numeric.body`, `mono` and `label.eyebrow` -
/// have no slot there to be enumerated in. Two of those four are the money
/// roles. So the one test that stops "a style nobody measured" would never have
/// seen them; `DESIGN-AUDIT.md` §4.8 is where that gap was found.
///
/// Every expected figure below is quoted from `design.md`, and where the
/// document publishes a contrast ratio the test asserts the *measurement*
/// matches the published figure rather than merely clearing a floor - so the
/// code and the document cannot make two different claims about the same
/// colour.
void main() {
  const tokens = AppTokens.dark;
  final colors = tokens.colors;
  final surface = colors.surface;
  final type = tokens.typography;

  /// The set `lib/theme.dart` actually registers, whichever palette that is.
  ///
  /// **Read this, not [AppTokens.dark], for anything compared against
  /// `spiritTheme`.** This file used to name `AppTokens.dark` for both jobs,
  /// which was correct only while they were the same object. The day the theme
  /// moved to Profound Verdant, every one of those assertions would have failed
  /// for the wrong reason - not because the theme had stopped reading the token
  /// layer, which is what they exist to check, but because it had started
  /// reading a different palette, which is not their business.
  final registered = spiritTheme.extension<AppTokens>()!;

  /// Every ground a widget paints text on.
  final grounds = <String, Color>{
    'surface.base': surface.base,
    'surface.raised': surface.raised,
    'surface.sunken': surface.sunken,
    'surface.overlay': surface.overlay,
  };

  group('colour roles - design.md §2.1', () {
    test('the surface roles are the specified values', () {
      expect(surface.base, const Color(0xFF0D1F16));
      expect(surface.raised, const Color(0xFF132A1F));
      expect(surface.sunken, const Color(0xFF08140E));
      expect(surface.field, const Color(0xFF1E3A2B));
      expect(surface.overlay, const Color(0xFF1C3328));
      expect(surface.borderSubtle, const Color(0xFF1E3A2B));
      expect(surface.borderStrong, const Color(0xFF2C5340));
    });

    test('surface.field is green.700, so v0.4 added a role and not a hex', () {
      // §2.1: "If you find yourself writing a hex value in a widget, the role
      // you need doesn't exist yet - add it here first." The product owner's
      // 2026-08-15 change wanted the original sign-in pill's colour, and that
      // colour was already a primitive. The collision with `border.subtle` is
      // deliberate and named in §2.1: they never meet, because a field well is
      // bounded by `border.strong`.
      expect(surface.field, surface.borderSubtle);
    });

    test('a field is the lightest surface, so a well is raised not recessed', () {
      // §2.1's ordering, which v0.4 states outright: sunken -> base -> raised ->
      // overlay -> field. A well sits *on* the page. `surface.sunken` keeps the
      // two uses that genuinely are recessed, a table header and a code block.
      double lightness(Color colour) => HSLColor.fromColor(colour).lightness;
      final ordered = <Color>[
        surface.sunken,
        surface.base,
        surface.raised,
        surface.overlay,
        surface.field,
      ];
      for (var i = 1; i < ordered.length; i++) {
        expect(
          lightness(ordered[i]),
          greaterThan(lightness(ordered[i - 1])),
          reason: 'surface step $i is not lighter than the one below it',
        );
      }
    });

    test('the scrim is black at 60%', () {
      expect(surface.scrim.r, 0);
      expect(surface.scrim.g, 0);
      expect(surface.scrim.b, 0);
      expect(surface.scrim.a, closeTo(0.6, 0.005));
    });

    test('depth is a surface step, so every surface is a different colour', () {
      // §2.1: depth is never a drop shadow. Two surfaces the same colour would
      // mean a card that cannot be told from the page it sits on.
      final distinct = <Color>{
        surface.base,
        surface.raised,
        surface.sunken,
        surface.field,
        surface.overlay,
      };
      expect(distinct, hasLength(5));
    });

    test('every readable text role clears AA on all four surfaces', () {
      final readable = <String, Color>{
        'text.primary': colors.text.primary,
        'text.secondary': colors.text.secondary,
        'text.tertiary': colors.text.tertiary,
      };
      for (final role in readable.entries) {
        for (final ground in grounds.entries) {
          expect(
            contrastRatio(role.value, ground.value),
            greaterThanOrEqualTo(bodyTextContrast),
            reason: '${role.key} is unreadable on ${ground.key}',
          );
        }
      }
    });

    test('text.money is currency-kes, and it is readable everywhere', () {
      // **`OPEN_QUESTIONS.md` decision 23, as a value rather than a prose
      // claim.** `currency-kes` `#45F28D` sat in `_ProfoundVerdant` wired to
      // nothing for as long as the question of which surfaces set money apart
      // was open; it is `AppTextRoles.money` now, and the till reads it. Both
      // palettes carry the same hex - the previous system's accent and Profound
      // Verdant's currency role are one colour - so this is the one row where a
      // repoint changed nothing.
      expect(colors.text.money, const Color(0xFF45F28D));
      expect(registered.colors.text.money, const Color(0xFF45F28D));
      // A figure a cashier reads aloud to a customer is text a person is
      // expected to read, so §9 applies to it exactly as it applies to body
      // copy. It is not exempted for being a number.
      for (final ground in grounds.entries) {
        expect(
          contrastRatio(colors.text.money, ground.value),
          greaterThanOrEqualTo(bodyTextContrast),
          reason: 'text.money is unreadable on ${ground.key}',
        );
      }
    });

    test('and each one measures what §2.1 publishes for it', () {
      // The document's own table, base then raised. A token that drifts from
      // the figure the specification advertises is the specification becoming
      // wrong about the code, which is the failure this whole audit found.
      //
      // `text.primary` reads 17.1 here because it measures 17.147 and the
      // document said 17.2. That cell was corrected in §2.1 rather than the
      // tolerance being widened to hide it - `DESIGN-AUDIT.md` §1.3 recomputed
      // 17.15 and called the figures correct, which is a rounding slip the
      // audit itself did not catch.
      final published = <String, (Color, double, double)>{
        'text.primary': (colors.text.primary, 17.1, 15.2),
        'text.secondary': (colors.text.secondary, 11.0, 9.8),
        'text.tertiary': (colors.text.tertiary, 5.9, 5.3),
        'text.disabled': (colors.text.disabled, 3.4, 3.0),
      };
      for (final entry in published.entries) {
        final (colour, onBase, onRaised) = entry.value;
        expect(
          contrastRatio(colour, surface.base),
          closeTo(onBase, 0.05),
          reason: '${entry.key} against surface.base',
        );
        expect(
          contrastRatio(colour, surface.raised),
          closeTo(onRaised, 0.05),
          reason: '${entry.key} against surface.raised',
        );
      }
    });

    test('text.tertiary is the floor for anything a person reads', () {
      // §2.1 says so in as many words, and it is the role a caption should
      // drop to. Nothing readable may be dimmer.
      expect(
        contrastRatio(colors.text.tertiary, surface.base),
        lessThan(contrastRatio(colors.text.secondary, surface.base)),
      );
      expect(
        contrastRatio(colors.text.tertiary, surface.overlay),
        greaterThanOrEqualTo(bodyTextContrast),
      );
    });

    test(
      'text.tertiary does not clear AA on surface.field, and §5.2 knows',
      () {
        // **The one place `text.tertiary` is not the floor**, found when v0.4
        // moved the input well off `surface.sunken` on 2026-08-15. It measures
        // 5.9 on the page and 4.29 on the new well, against §9's 4.5 - so a
        // placeholder inside a well is `text.secondary`, and §5.2 records the
        // figure rather than leaving the next person to rediscover it.
        //
        // Asserted as a *fact about the palette* rather than folded into the
        // all-surfaces sweep above, because hiding it there would mean either a
        // silent failure or a quietly widened tolerance.
        expect(
          contrastRatio(colors.text.tertiary, surface.field),
          closeTo(4.29, 0.05),
        );
        expect(
          contrastRatio(colors.text.tertiary, surface.field),
          lessThan(bodyTextContrast),
        );
        // What §5.2 uses instead, and what a typed value is, both clear it.
        expect(
          contrastRatio(colors.text.secondary, surface.field),
          greaterThanOrEqualTo(bodyTextContrast),
        );
        expect(
          contrastRatio(colors.text.primary, surface.field),
          greaterThanOrEqualTo(bodyTextContrast),
        );
      },
    );

    test('helper text is unaffected, because it sits outside the well', () {
      // §5.2 puts the helper and the counter under the field, on the page. The
      // placeholder is the only text v0.4 moved onto a new ground.
      expect(
        contrastRatio(colors.text.tertiary, surface.base),
        greaterThanOrEqualTo(bodyTextContrast),
      );
    });

    test('text.disabled cannot pass as body text', () {
      // It is below AA deliberately - WCAG exempts a disabled control - and
      // this assertion is what stops it being reached for as a third readable
      // tier. `text.tertiary` is that tier.
      expect(
        contrastRatio(colors.text.disabled, surface.base),
        lessThan(bodyTextContrast),
      );
    });
  });

  group('action roles - design.md §2.1', () {
    final action = colors.action;

    test('the four tiers carry the specified containers and labels', () {
      expect(action.primary.container, const Color(0xFF45F28D));
      expect(action.primary.label, const Color(0xFF0A0F0C));
      expect(action.primary.border, isNull);

      expect(action.secondary.container, Colors.transparent);
      expect(action.secondary.label, const Color(0xFFB8D6C5));
      expect(action.secondary.border, const Color(0xFF2C5340));

      expect(action.tertiary.container, Colors.transparent);
      expect(action.tertiary.label, const Color(0xFF45F28D));
      expect(action.tertiary.border, isNull);

      expect(action.destructive.container, Colors.transparent);
      expect(action.destructive.label, const Color(0xFFFF5C6C));
      expect(action.destructive.border, const Color(0xFFFF5C6C));
    });

    test('secondary is not mint, which is the point of the tier system', () {
      // §2.1 calls this the single biggest change in the document: four tiers
      // visually distinct at a glance, and secondary actions stop being mint.
      expect(action.secondary.label, isNot(action.primary.container));
      expect(action.secondary.label, isNot(action.tertiary.label));
    });

    test('a primary label clears 13.2:1 on its container, as published', () {
      expect(
        contrastRatio(action.primary.label, action.primary.container),
        closeTo(13.2, 0.05),
      );
    });

    test('a primary label stays readable while hovered and pressed', () {
      // §2.1 names the hover and pressed containers and says nothing about
      // their contrast. A state that fails AA is unreadable for as long as a
      // finger is down on it, which on a till is every sale.
      for (final state in <(String, Color)>[
        ('hover', action.primary.hoverFill()),
        ('pressed', action.primary.pressedFill()),
      ]) {
        expect(
          contrastRatio(action.primary.label, state.$2),
          greaterThanOrEqualTo(bodyTextContrast),
          reason: 'the primary label is unreadable while ${state.$1}',
        );
      }
      expect(action.primary.hoverFill(), const Color(0xFF3DD47C));
      expect(action.primary.pressedFill(), const Color(0xFF34B169));
    });

    test('every tier label clears AA on the base and raised surfaces', () {
      final labels = <String, Color>{
        'action.secondary': action.secondary.label,
        'action.tertiary': action.tertiary.label,
        'action.destructive': action.destructive.label,
      };
      for (final label in labels.entries) {
        for (final ground in <Color>[surface.base, surface.raised]) {
          expect(
            contrastRatio(label.value, ground),
            greaterThanOrEqualTo(bodyTextContrast),
            reason: '${label.key} is unreadable',
          );
        }
      }
    });

    test('the primary tier carries a container and a wash, and they differ', () {
      // **This test used to assert the primary tier carried *no* overlay
      // opacities**, on the reasoning that "a tier carrying both would let a
      // widget pick the wrong one and still render something plausible".
      // Amended 2026-08-27, because the separation caused the defect it was
      // meant to prevent rather than preventing it.
      //
      // §2.1's two rules are about two different surfaces, not two different
      // tiers. A *button* is its container, so pressing it swaps the container.
      // A *card* is composed content with an overlay laid over the top, and the
      // home's module cards had only `pressedFill` available - which for this
      // tier is opaque - so a pressed card became a green rectangle with the
      // card hidden underneath it.
      //
      // What disambiguates now is the method a widget asks for, which is a
      // compile-time choice with a name on it, rather than the absence of a
      // value - which was a silent one.
      final primary = action.primary;
      expect(primary.pressedContainer, isNotNull);
      expect(primary.hoverOverlayOpacity, 0.08);
      expect(primary.pressedOverlayOpacity, 0.12);
      expect(primary.pressedFill(), primary.pressedContainer);
      expect(primary.pressedWash(), primary.label.withValues(alpha: 0.12));
      expect(primary.hoverWash(), primary.label.withValues(alpha: 0.08));
      // The whole point: a wash must never be the opaque container.
      expect(primary.pressedWash(), isNot(primary.pressedFill()));
      expect(primary.pressedWash().a, lessThan(1));
    });

    test('the three overlay tiers state no container at all', () {
      for (final tier in <AppActionRole>[
        action.secondary,
        action.tertiary,
        action.destructive,
      ]) {
        expect(tier.hoverContainer, isNull);
        expect(tier.pressedContainer, isNull);
        expect(tier.hoverOverlayOpacity, 0.08);
        expect(tier.pressedOverlayOpacity, 0.12);
        expect(tier.hoverFill(), tier.label.withValues(alpha: 0.08));
        expect(tier.pressedFill(), tier.label.withValues(alpha: 0.12));
        // With no container to prefer, the two are the same colour here - which
        // is why the defect only ever showed on the primary tier.
        expect(tier.pressedWash(), tier.pressedFill());
      }
    });

    test('the disabled treatment is the specified pair', () {
      expect(action.disabledContainer, const Color(0xFF1E3A2B));
      expect(action.disabledLabel, const Color(0xFF5D7468));
      expect(action.disabledBorder, const Color(0xFF1E3A2B));
      expect(action.disabledLabel, colors.text.disabled);
    });

    test('the loading spinner has a size, so a width can be frozen', () {
      expect(action.loadingIndicatorSize, 16);
    });
  });

  group('the focus ring - design.md §9', () {
    final ring = colors.action.focusRing;

    test('is 2px mint at a 2px offset', () {
      expect(ring.color, const Color(0xFF45F28D));
      expect(ring.width, 2);
      expect(ring.offset, 2);
    });

    test('clears §9 on every surface it can be drawn against', () {
      // The one boundary in this system that carries information on its own,
      // and therefore the one §9's 3:1 boundary row has to hold for. It clears
      // it by a wide margin on all four.
      for (final ground in grounds.entries) {
        expect(
          contrastRatio(ring.color, ground.value),
          greaterThanOrEqualTo(largeTextContrast),
          reason: 'the focus ring is invisible on ${ground.key}',
        );
      }
    });
  });

  group('status roles - design.md §2.1', () {
    final status = colors.status;

    test('all five triples are the specified values', () {
      expect(status.ok.fg, const Color(0xFF45F28D));
      expect(status.ok.bg, const Color(0xFF143824));
      expect(status.ok.border, const Color(0xFF2C5340));

      expect(status.attention.fg, const Color(0xFFF2C14E));
      expect(status.attention.bg, const Color(0xFF28321D));
      expect(status.attention.border, const Color(0xFF5A4C24));

      expect(status.problem.fg, const Color(0xFFFF5C6C));
      expect(status.problem.bg, const Color(0xFF2A2620));
      expect(status.problem.border, const Color(0xFF6B3238));

      expect(status.info.fg, const Color(0xFF6FB7F2));
      expect(status.info.bg, const Color(0xFF193130));
      expect(status.info.border, const Color(0xFF2E4C60));

      expect(status.neutral.fg, const Color(0xFF849E8F));
      expect(status.neutral.bg, const Color(0xFF1C3328));
      expect(status.neutral.border, const Color(0xFF1E3A2B));
    });

    test('there are exactly five, each meaning one thing', () {
      expect(status.all, hasLength(5));
      expect(
        status.all.keys,
        containsAll(<String>['ok', 'attention', 'problem', 'info', 'neutral']),
      );
      // §1: "Colour carries meaning or it carries nothing." Five statuses
      // sharing a foreground would be the one-green-doing-seven-jobs problem
      // in a new costume.
      expect(status.all.values.map((role) => role.fg).toSet(), hasLength(5));
    });

    test('every foreground clears 5:1 on both grounds, as §2.1 claims', () {
      for (final role in status.all.entries) {
        for (final ground in <Color>[surface.base, surface.raised]) {
          expect(
            contrastRatio(role.value.fg, ground),
            greaterThanOrEqualTo(5.0),
            reason: 'status.${role.key} does not clear 5:1',
          );
        }
      }
    });

    test('and on its own container, which is where the label sits', () {
      // A badge paints its label on its own `bg`, not on the page. §2.1
      // measures against the page only, so this is the ratio nothing else
      // checks - and `status.neutral` is the tight one at 4.68.
      for (final role in status.all.entries) {
        expect(
          contrastRatio(role.value.fg, role.value.bg),
          greaterThanOrEqualTo(bodyTextContrast),
          reason: 'status.${role.key} is unreadable inside its own container',
        );
      }
    });

    test('status.ok and the brand accent are the same mint, deliberately', () {
      // §2.1 calls the collision out and explains why it is safe: a status
      // always appears in a bordered container and an action never does. This
      // pins the collision so nobody "fixes" it into a sixth colour.
      expect(status.ok.fg, colors.action.primary.container);
      expect(status.ok.bg, isNot(surface.base));
    });
  });

  group('type roles - design.md §2.2', () {
    test('all fifteen roles exist under their specification names', () {
      // Twelve until 2026-08-22, when `display.compact` was added for Profound
      // Verdant's `headline-lg-mobile` - the first breakpoint-aware type value
      // any source this app has had actually states. Thirteen until
      // 2026-08-23, when `numeric.compact` joined it as the second: the export
      // draws a headline figure at `text-4xl` on a reporting page and at
      // `section-title` on a card, and 30 is wide enough to force a phone's
      // grid of figures into one column. Fourteen until 2026-09-22, when
      // `mono.caption` put a SKU under a product name at `caption`'s size.
      expect(type.all, hasLength(15));
      expect(type.all.keys, <String>[
        'display',
        'display.compact',
        'title.lg',
        'title.md',
        'body.lg',
        'body.md',
        'label.lg',
        'label.md',
        'label.eyebrow',
        'caption',
        'numeric.hero',
        'numeric.compact',
        'numeric.body',
        'mono',
        'mono.caption',
      ]);
    });

    test('each carries the size, line height and weight §2.2 gives it', () {
      // size / line / weight. **Repointed to Profound Verdant on 2026-08-22**;
      // the §2.2 figures this replaces are in `OPEN_QUESTIONS.md` question 22.
      // The seven named roles are the design's served Tailwind config, which 75
      // of 76 screens carry identically. The five marked `derived` are the
      // stock Tailwind sizes those same screens use alongside the seven.
      final table = <String, (double, double, FontWeight)>{
        'display': (32, 38.4, FontWeight.w700), // headline-lg
        'display.compact': (28, 33.6, FontWeight.w700), // headline-lg-mobile
        'title.lg': (22, 30.8, FontWeight.w600), // section-title
        'title.md': (18, 28, FontWeight.w500), // derived, text-lg
        'body.lg': (16, 24, FontWeight.w400), // body-md
        'body.md': (14, 21, FontWeight.w400), // body-sm
        'label.lg': (14, 20, FontWeight.w700), // .btn-primary, measured
        'label.md': (14, 20, FontWeight.w600), // derived, text-sm
        'label.eyebrow': (12, 12, FontWeight.w700), // label-caps
        'caption': (12, 16, FontWeight.w400), // derived, text-xs
        'numeric.hero': (30, 36, FontWeight.w500), // derived, text-3xl
        // `section-title`'s size in `data-mono`'s face and weight.
        'numeric.compact': (22, 30.8, FontWeight.w500),
        'numeric.body': (14, 20, FontWeight.w500), // unchanged
        'mono': (14, 14, FontWeight.w500), // data-mono
        // `caption`'s size and leading in `data-mono`'s face and weight.
        'mono.caption': (12, 16, FontWeight.w500),
      };
      for (final entry in table.entries) {
        final style = type.all[entry.key]!;
        final (size, line, weight) = entry.value;
        expect(style.fontSize, size, reason: '${entry.key} size');
        expect(style.fontWeight, weight, reason: '${entry.key} weight');
        expect(
          style.fontSize! * style.height!,
          closeTo(line, 0.001),
          reason: '${entry.key} line height should resolve to $line',
        );
      }
    });

    test('tabular figures are on both numeric roles and nowhere else', () {
      // §2.2: mandatory anywhere numbers stack vertically, which is what the
      // numeric roles are for. Putting them on prose would widen every digit
      // in a sentence for no reason.
      const tabular = <FontFeature>[FontFeature.tabularFigures()];
      for (final entry in type.all.entries) {
        final expected = entry.key.startsWith('numeric.') ? tabular : null;
        expect(
          entry.value.fontFeatures,
          expected,
          reason: '${entry.key} font features',
        );
      }
    });

    test('the four tracked roles are the four the design tracks', () {
      // **Was "label.eyebrow is the only tracked role, at +0.8".** Profound
      // Verdant tracks three of its seven and measures a fourth on
      // `.btn-primary`, stating each in `em` where a
      // `TextStyle` has only logical pixels - so every figure here is the
      // design's `em` times the role's own size, and the arithmetic is the
      // assertion rather than a comment.
      const tracked = <String, (double, double)>{
        'display': (-0.02, 32), // headline-lg
        'label.lg': (0.05, 14), // .btn-primary, measured rather than named
        'label.eyebrow': (0.05, 12), // label-caps
        'mono': (-0.01, 14), // data-mono
      };
      for (final entry in type.all.entries) {
        final source = tracked[entry.key];
        expect(
          entry.value.letterSpacing,
          source == null ? isNull : closeTo(source.$1 * source.$2, 0.0001),
          reason: '${entry.key} letter spacing',
        );
      }
      // `headline-lg-mobile` states no tracking where `headline-lg` states
      // -0.02em. That asymmetry is the design's and is pinned here so it is not
      // "corrected" into consistency later.
      expect(type.all['display.compact']!.letterSpacing, isNull);
    });

    test('no type role carries a colour', () {
      // Colour is an `AppTextRoles` role and a widget pairs the two. A type
      // role holding a colour would be a second place a colour is decided,
      // and the second place is the one that drifts.
      for (final entry in type.all.entries) {
        expect(
          entry.value.color,
          isNull,
          reason: '${entry.key} names a colour',
        );
      }
    });

    test('every role names a family, and mono names the mono one', () {
      // **Third value this assertion has held, and each move is recorded.** It
      // began as "no type role names a family": §2.2's opening line said "One
      // family - Roboto" while its last row said "monospace", and the app
      // bundled no font at all. `design.md` v0.7 gave `mono` Roboto Mono on
      // 2026-08-16 and left the other eleven inheriting the theme.
      //
      // Profound Verdant names both families, and `OPEN_QUESTIONS.md` decision
      // 20 bundles them. The eleven stopped inheriting at the same time, and
      // that half is the load-bearing one: a **component** theme's text style
      // replaces the text theme's rather than merging onto it, so a role that
      // names nothing reaches the engine with nothing however `ThemeData`
      // is configured. Inheritance was never actually reaching `ListTile`.
      // **Three roles are mono as of 2026-08-23, not one.** The design's
      // typography section puts *every* figure in JetBrains Mono - "for
      // currency (KES) and numerical data (Stock counts, SKU numbers)" - and
      // the export draws headline amounts as `font-data-mono` throughout. So
      // the two numeric roles joined `mono`; everything a person reads as
      // prose is still the interface face.
      const monoRoles = <String>{
        'mono',
        'mono.caption',
        'numeric.hero',
        'numeric.compact',
        'numeric.body',
      };
      for (final entry in type.all.entries) {
        expect(
          entry.value.fontFamily,
          monoRoles.contains(entry.key)
              ? AppTypeRoles.monoFamily
              : AppTypeRoles.interfaceFamily,
          reason: '${entry.key} names the wrong family',
        );
      }
    });

    test('pubspec declares every family and weight the roles read', () {
      // A source scan, because the failure this catches is a *mismatch between
      // two files* and neither one is wrong on its own. A role repointed to a
      // weight nobody bundled does not throw: the engine picks the nearest
      // declared face and renders something plausible, so a 600 silently
      // becomes a 500 and only a person holding both files notices.
      //
      // `tool/screenshots/harness.dart` carries the same list a third time and
      // cannot read it from here - a test binary has no asset bundle - so its
      // own doc comment says the lists move together. This pins two of the
      // three; the harness is pinned by every screenshot going rectangular.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final declared = <String, Set<int>>{};
      String? family;
      for (final line in pubspec.split('\n')) {
        final familyMatch = RegExp(
          r'^\s*- family:\s*(.+?)\s*$',
        ).firstMatch(line);
        if (familyMatch != null) {
          family = familyMatch.group(1);
          declared[family!] = <int>{};
          continue;
        }
        final weightMatch = RegExp(r'^\s*weight:\s*(\d+)\s*$').firstMatch(line);
        if (weightMatch != null && family != null) {
          declared[family]!.add(int.parse(weightMatch.group(1)!));
        }
      }

      for (final entry in type.all.entries) {
        final wanted = entry.value.fontFamily!;
        final weight = entry.value.fontWeight!.value;
        expect(
          declared.keys,
          contains(wanted),
          reason:
              '${entry.key} is set in "$wanted", which pubspec.yaml does not '
              'declare. Bundle the family or repoint the role.',
        );
        expect(
          declared[wanted],
          contains(weight),
          reason:
              '${entry.key} asks "$wanted" for weight $weight, which '
              'pubspec.yaml does not declare. The engine will silently render '
              'the nearest weight it has instead of failing.',
        );
      }
    });
  });

  group('spacing and radius - design.md §2.3', () {
    test('the scale is exactly the ten permitted values', () {
      expect(tokens.spacing.all, <double>[
        4,
        8,
        12,
        16,
        20,
        24,
        32,
        40,
        48,
        64,
      ]);
    });

    test('every value is on a 4pt base and the scale ascends', () {
      var previous = 0.0;
      for (final value in tokens.spacing.all) {
        expect(value % 4, 0, reason: '$value is not a multiple of 4');
        expect(value, greaterThan(previous));
        previous = value;
      }
    });

    test('the radii are the four Profound Verdant measures', () {
      // Repointed 2026-08-22 from §2.3's 8/12/20 to what the export renders.
      // The design's config is `DEFAULT` 2, `lg` 4, `xl` 8, `full` 12, and its
      // own CSS puts buttons, inputs and cards all on `xl`.
      expect(tokens.radius.sm, 2, reason: 'chips and checkboxes: bare rounded');
      expect(tokens.radius.md, 8, reason: 'cards, buttons, wells: xl');
      expect(tokens.radius.lg, 12, reason: 'dialogs and sheets: full');
      expect(tokens.radius.pill, 999);
    });

    test('the panel radius is above the design scale, and says why', () {
      // **`xl` is this app's own, added 2026-09-20, and the one radius no
      // Profound Verdant value backs.** The product owner called the row shape
      // too rigid for a dashboard of cards; a panel with a figure in it is not
      // a row in a stack of like things, and at 8 a grid of them reads as a
      // table of cells. Recorded as the app's own rather than smuggled in as a
      // repoint of `md`, which would have restyled every button and field in
      // the product to soften four cards on one screen.
      expect(tokens.radius.xl, 16);
      expect(
        tokens.radius.xl,
        greaterThan(tokens.radius.lg),
        reason: 'a panel is softer than a dialog, or it would not be a role',
      );
      expect(
        tokens.radius.xl,
        lessThan(tokens.radius.pill),
        reason: 'a card is a corner, not a stadium',
      );
    });

    test('every radius the design states is inside its 4-8px claim', () {
      // `DESIGN_RULES.md`: "Corners are compact (generally 4-8 px in the Stitch
      // system)". The three surface radii bracket that, and the old scale did
      // not - `lg` was 20.
      expect(tokens.radius.sm, lessThan(4));
      expect(tokens.radius.md, inInclusiveRange(4, 8));
      expect(tokens.radius.lg, lessThanOrEqualTo(12));
    });

    test('pill is no longer a design value, and nothing large reads it', () {
      // **Kept, but demoted.** Profound Verdant has no pill: what its config
      // calls `full` is 12, and its rendered buttons and inputs are
      // square-cornered. What still reads `pill` is round on purpose - the
      // 32x4 sheet handle, the stepper's controls, the sync badge - and Flutter
      // clamps a radius to half the shorter side, so those stay capsules at any
      // value above about 2.
      expect(
        tokens.radius.pill,
        greaterThan(tokens.radius.lg * 10),
        reason: 'pill must be a stadium, not a large radius',
      );
      expect(
        tokens.radius.md,
        lessThan(tokens.radius.pill),
        reason: 'a button is a corner now, not a stadium',
      );
    });
  });

  group('motion - design.md §2.4', () {
    final motion = tokens.motion;

    /// The damping ratio, which is what "critically damped" means.
    double dampingRatio(SpringDescription spring) =>
        spring.damping / (2 * math.sqrt(spring.stiffness * spring.mass));

    test('the four springs are the specified triples', () {
      expect(motion.springs, hasLength(4));
      final table = <String, (double, double, double)>{
        'spring.snappy': (380, 32, 1),
        'spring.smooth': (220, 30, 1),
        'spring.gentle': (140, 24, 1),
        'spring.bouncy': (260, 18, 1),
      };
      for (final entry in table.entries) {
        final spring = motion.springs[entry.key]!;
        final (stiffness, damping, mass) = entry.value;
        expect(spring.stiffness, stiffness, reason: '${entry.key} stiffness');
        expect(spring.damping, damping, reason: '${entry.key} damping');
        expect(spring.mass, mass, reason: '${entry.key} mass');
      }
    });

    test('only spring.bouncy overshoots, because overshoot is a reward', () {
      // §2.4: on an operational surface overshoot reads as instability, and
      // §6.2 confines `bouncy` to the reward layer. Measured rather than
      // asserted in prose: `snappy` sits at 0.82, which costs about a 1%
      // overshoot and is what "near-critically damped" means.
      expect(dampingRatio(motion.bouncy), lessThan(0.7));
      for (final spring in <SpringDescription>[
        motion.snappy,
        motion.smooth,
        motion.gentle,
      ]) {
        expect(dampingRatio(spring), greaterThanOrEqualTo(0.8));
      }
    });

    test('the four durations are the specified pairs', () {
      expect(motion.durations, hasLength(4));
      final table = <String, (int, Curve)>{
        'motion.instant': (80, Curves.linear),
        'motion.short': (160, Curves.easeOutCubic),
        'motion.medium': (240, Curves.easeInOutCubic),
        'motion.long': (320, Curves.easeInOutCubic),
      };
      for (final entry in table.entries) {
        final token = motion.durations[entry.key]!;
        final (milliseconds, curve) = entry.value;
        expect(
          token.duration,
          Duration(milliseconds: milliseconds),
          reason: entry.key,
        );
        expect(token.curve, curve, reason: '${entry.key} curve');
      }
    });

    test('the two skeleton durations stay out of §2.4\'s map', () {
      // `docs/stitch/OPEN_QUESTIONS.md` decision 35. They are this app's own
      // rather than the specification's, and `durations` is what the
      // specification names - so the assertion above keeps meaning what it
      // says. This is the tripwire on that: a later hand folding them in
      // breaks a test whose name explains why not to.
      expect(motion.durations.containsKey('motion.skeletonSweep'), isFalse);
      expect(motion.durations.containsKey('motion.skeletonDelay'), isFalse);
    });

    test('a skeleton sweeps far slower than any transition', () {
      // The four above are transitions and anything past a third of a second
      // reads as lag; this is a loop on a surface a person is waiting at, and
      // at transition speed it strobes.
      expect(motion.skeletonSweep.duration, const Duration(milliseconds: 1200));
      expect(motion.skeletonSweep.curve, Curves.easeInOut);
      expect(
        motion.skeletonSweep.duration,
        greaterThan(motion.long.duration * 3),
      );
    });

    test('a skeleton is not drawn for a read that finishes promptly', () {
      // The threshold that stopped the till flashing: a Hive read resolves in a
      // frame or two, and a placeholder drawn and torn down inside that is the
      // jitter it was added to remove.
      expect(motion.skeletonDelay.duration, const Duration(milliseconds: 100));
      // A threshold rather than an animation, so nothing reads its curve.
      expect(motion.skeletonDelay.curve, Curves.linear);
    });

    test('a press scales rather than ripples', () {
      // §2.4's replacement for the ink ripple: opacity plus scale at
      // `spring.snappy`, and no expanding circle anywhere.
      expect(motion.pressScale, 0.97);
    });

    test('the covered surface parallaxes at §6.2\'s 30%', () {
      // "Route push (compact) | horizontal, incoming full / outgoing parallax
      // at 30%". It lives in the token layer for the same reason `pressScale`
      // does: it is a figure `design.md` states, and a widget that restated it
      // would be a second source of truth for it.
      expect(motion.routeParallax, 0.3);
    });
  });

  group('density - design.md §3', () {
    test('comfortable is the specified set', () {
      const density = AppDensity.comfortable;
      expect(density.minimumRowHeight, 64);
      expect(
        density.rowPadding,
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );
      expect(density.bodyRole, AppBodyRole.large);
      expect(density.minimumTapTarget, const Size(48, 48));
      expect(density.sectionGap, 24);
      expect(density.pointerOnly, isFalse);
    });

    test('compact is the specified set', () {
      const density = AppDensity.compact;
      expect(density.minimumRowHeight, 40);
      expect(
        density.rowPadding,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      );
      expect(density.bodyRole, AppBodyRole.medium);
      expect(density.minimumTapTarget, const Size(32, 32));
      expect(density.sectionGap, 16);
      expect(density.pointerOnly, isTrue);
    });

    test('nothing in lib/ applies the 32dp density, and that is the guard', () {
      // **The tripwire for the decision in `OPEN_QUESTIONS.md`, Finding 2 of
      // `audits/2026-08-22-wave-0-foundations.md`: a density resolver must take
      // the input kind, not just a width, and must refuse `compact` on touch.**
      //
      // That resolver does not exist yet, and `pointerOnly` is read nowhere in
      // `lib/` - so today the 48dp guarantee holds only because `compact` was
      // never wired up, which is luck rather than enforcement. This test turns
      // the luck into a tripwire: the moment production code reaches for the
      // 32dp density, it fails, and whoever is adding the first dense surface
      // has to answer the pointer question in the same change.
      //
      // A source scan rather than a widget test, because what is being asserted
      // is the *absence* of a call. There is no screen to pump.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        // `lib/pos/**` and `lib/screens/**` are legacy and read-only under
        // `claude.md` hard rule 3, and `tokens.dart` is where `compact` is
        // declared.
        if (path.contains('lib/pos/') ||
            path.contains('lib/screens/') ||
            path.endsWith('lib/ui/tokens.dart')) {
          continue;
        }
        // **Comments are stripped before the check, deliberately.** A doc
        // comment that explains why a surface does *not* take the dense density
        // is exactly the sort of note this codebase writes, and failing on it
        // would train the next reader to delete the explanation rather than
        // answer the question.
        final code = entity
            .readAsLinesSync()
            .map((line) {
              final comment = line.indexOf('//');
              return comment == -1 ? line : line.substring(0, comment);
            })
            .join('\n');
        if (code.contains('AppDensity.compact')) offenders.add(path);
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Production code now applies AppDensity.compact, whose targets are '
            '32x32. DESIGN_RULES.md makes 48dp pass/fail and AppDensity.compact '
            'carries pointerOnly: true, which nothing enforces. Before wiring '
            'this, give the resolver the pointer/touch kind - not just a width - '
            'and refuse compact on touch. Then replace this test with one that '
            'asserts the resolver refuses it.',
      );
    });

    test('comfortable honours §9\'s 48dp touch target', () {
      // Pass/fail under `claude.md` hard rule 6, and the reason the root
      // density is comfortable rather than resolved from width: a screen that
      // has not asked for compact must never get 32px targets.
      expect(AppDensity.comfortable.minimumTapTarget.width, 48);
      expect(AppDensity.comfortable.minimumTapTarget.height, 48);
      expect(AppTokens.dark.density, AppDensity.comfortable);
    });

    test('only compact is pointer-only, and it is the one below 48dp', () {
      // §3: a touch device never gets 32px targets, whatever its width. The
      // rule is data so the widget that resolves density cannot forget it.
      for (final density in <AppDensity>[
        AppDensity.comfortable,
        AppDensity.compact,
      ]) {
        final belowTouchFloor = density.minimumTapTarget.shortestSide < 48;
        expect(
          density.pointerOnly,
          belowTouchFloor,
          reason: 'a density below 48dp must be pointer-only, and only it',
        );
      }
    });

    test('each density resolves the body role §3 gives it', () {
      expect(AppDensity.comfortable.body(type), type.bodyLarge);
      expect(AppDensity.compact.body(type), type.bodyMedium);
    });

    test('a compact row fits its own body line inside its own height', () {
      // This is the arithmetic that decided which way round §3's "12 / 8"
      // reads, because the document never says. Vertical 8 leaves **37** of the
      // 40 minimum; vertical 12 would need 45 and could not fit at all.
      //
      // **Was 36 until 2026-08-22.** Profound Verdant's `body-sm` states a 1.5
      // line height where §2.2 gave 20/14, so a compact row's content grew by
      // one pixel and the headroom fell from 4 to 3. The reading it decided is
      // unchanged, and this is now the tighter of the two measurements that
      // keep it - worth knowing if a later type change moves `body.md` again.
      const density = AppDensity.compact;
      final line = density.body(type).fontSize! * density.body(type).height!;
      expect(
        density.rowPadding.vertical + line,
        lessThanOrEqualTo(density.minimumRowHeight),
      );
      expect(density.rowPadding.vertical + line, closeTo(37, 0.001));
      // The rejected reading, kept as a measurement rather than a comment.
      expect(24 + line, greaterThan(density.minimumRowHeight));
    });

    test('every density measurement is on the §2.3 spacing scale', () {
      final scale = tokens.spacing.all;
      for (final density in <AppDensity>[
        AppDensity.comfortable,
        AppDensity.compact,
      ]) {
        expect(scale, contains(density.sectionGap));
        expect(scale, contains(density.rowPadding.left));
        expect(scale, contains(density.rowPadding.top));
        expect(scale, contains(density.minimumRowHeight));
      }
    });
  });

  group('layout - design.md §4.1 and §4.2', () {
    const layout = AppLayout.contract;

    test('the breakpoint floors are §4.1\'s, unchanged by the rename', () {
      // §4.1: "These replace `tenantWideLayoutBreakpoint` (768) and
      // `tenantTableBreakpoint` (1024) with the same numbers under one name."
      // A rename that moved a figure would be a layout change wearing a
      // rename's clothes, so both numbers are asserted rather than described.
      expect(layout.mediumFloor, 768);
      expect(layout.expandedFloor, 1024);
      expect(layout.breakpointFloors, <String, double>{
        'breakpoint.medium': 768,
        'breakpoint.expanded': 1024,
      });
    });

    test('the content widths are §4.2\'s three rows', () {
      expect(layout.reading, 720);
      expect(layout.records, 1200);
      expect(layout.salePane, 420);
      expect(layout.contentWidths, <String, double>{
        'content.reading': 720,
        'content.records': 1200,
        'content.salePane': 420,
      });
    });

    test('every band boundary resolves on the floor, not above it', () {
      // §4.1 states its ranges closed at the bottom - `medium` is "768 - 1023"
      // and `expanded` is ">= 1024" - so the floor itself belongs to the wider
      // band. An off-by-one here is a screen that changes shape one pixel late.
      expect(layout.breakpointOf(0), AppBreakpoint.compact);
      expect(layout.breakpointOf(767.9), AppBreakpoint.compact);
      expect(layout.breakpointOf(768), AppBreakpoint.medium);
      expect(layout.breakpointOf(1023.9), AppBreakpoint.medium);
      expect(layout.breakpointOf(1024), AppBreakpoint.expanded);
      expect(layout.breakpointOf(4000), AppBreakpoint.expanded);
    });

    test('the three bands are contiguous and cover every width', () {
      // No gap and no overlap: every width answers exactly one band, so no
      // caller can find a width that is neither compact nor medium.
      for (final width in <double>[0, 1, 767, 768, 1023, 1024, 1440, 3840]) {
        expect(
          <AppBreakpoint>[
            AppBreakpoint.compact,
            AppBreakpoint.medium,
            AppBreakpoint.expanded,
          ].where((band) => layout.breakpointOf(width) == band),
          hasLength(1),
        );
      }
    });

    test('isAtLeast is a floor test rather than an equality', () {
      // The comparison every caller wants. `band == expanded` would silently
      // exclude a wider band the day a fourth is declared, and reading the
      // enum's own ordering is what stops that being written per call site.
      expect(layout.isAtLeast(1440, AppBreakpoint.compact), isTrue);
      expect(layout.isAtLeast(1440, AppBreakpoint.medium), isTrue);
      expect(layout.isAtLeast(1440, AppBreakpoint.expanded), isTrue);
      expect(layout.isAtLeast(800, AppBreakpoint.medium), isTrue);
      expect(layout.isAtLeast(800, AppBreakpoint.expanded), isFalse);
      expect(layout.isAtLeast(411, AppBreakpoint.medium), isFalse);
      expect(AppBreakpoint.compact.isAtLeast(AppBreakpoint.compact), isTrue);
      expect(AppBreakpoint.compact.isAtLeast(AppBreakpoint.medium), isFalse);
    });

    test('the content maxima ascend, and only the sale row has none', () {
      // §4.2 gives a form less room than a table, which is the whole reason
      // there are two rows rather than one. Reversing them would still compile.
      expect(
        layout.maxWidthOf(AppContentWidth.reading),
        lessThan(layout.maxWidthOf(AppContentWidth.records)!),
      );
      expect(layout.maxWidthOf(AppContentWidth.reading), 720);
      expect(layout.maxWidthOf(AppContentWidth.records), 1200);
      // Null rather than infinity, so a caller adds no widget at all.
      expect(layout.maxWidthOf(AppContentWidth.full), isNull);
    });

    test('§4.1\'s compact band is not §3\'s compact density', () {
      // The one collision `design.md` creates for itself, and they are close
      // to opposites: a phone is `AppBreakpoint.compact` and §3 gives it the
      // *comfortable* density, while `AppDensity.compact` is reachable only on
      // a pointer device at `expanded`. Two types, asserted so a future
      // refactor cannot merge them into one.
      expect(AppBreakpoint.compact, isNot(isA<AppDensity>()));
      expect(AppTokens.dark.density, AppDensity.comfortable);
      expect(AppDensity.compact.pointerOnly, isTrue);
    });

    test('the registered token set carries the contract itself', () {
      // The claim that lets `PageHeader`'s statics read `AppLayout.contract`
      // where they have no context to read a theme from. If these two could
      // differ, a widget and a test would be answering different questions.
      expect(AppTokens.dark.layout, same(AppLayout.contract));
      expect(spiritTheme.extension<AppTokens>()!.layout, AppLayout.contract);
    });

    test('the screenshot harness declares a viewport in every width region', () {
      // A source scan of `tool/screenshots/harness.dart`, for the same reason
      // the pubspec scan above is one: the failure this catches is a *mismatch
      // between two files* and neither is wrong on its own. A test binary has no
      // asset bundle and `tool/` is outside `lib/`, so the harness cannot be
      // imported from here - it can only be read.
      //
      // **What it asserts is that the width axis has no dark region.** §4.1's
      // two band floors and §4.2's two *page* maxima are four boundaries on one
      // axis and they interleave, so they cut it into five regions rather than
      // three: a width can cross a maximum without changing band, and change
      // band without crossing a maximum. `AppLayout.salePane` is excluded
      // deliberately - it is the fixed width of a pane inside a page rather
      // than a maximum applied to the page, so nothing about a screen changes
      // when the window crosses 420.
      //
      // The harness held three viewports for a long time, which is why this is
      // worth pinning: 1440 and 411 straddle every boundary at once and reading
      // "straddles" as "covers" is exactly the mistake that left 1024-1199
      // rendered by nothing while four behaviours flipped there.
      //
      // **What it does not prove**: that any *case* is captured at every
      // viewport, which is a per-matrix judgement and deliberately not uniform -
      // most screens are indifferent to width and photographing them five times
      // would be hundreds of images nobody reads.
      final harness = File('tool/screenshots/harness.dart').readAsStringSync();

      final widthOf = <String, double>{};
      for (final match in RegExp(
        r'const ScreenshotViewport (\w+) = ScreenshotViewport\(\s*'
        r"name: '[^']+',\s*size: Size\(\s*(\d+(?:\.\d+)?)\s*,",
      ).allMatches(harness)) {
        widthOf[match.group(1)!] = double.parse(match.group(2)!);
      }
      expect(
        widthOf,
        isNotEmpty,
        reason:
            'No `ScreenshotViewport` declaration was recognised in '
            'tool/screenshots/harness.dart. If its formatting changed, this '
            'scan needs updating - it has not stopped being true.',
      );

      final list = RegExp(
        r'const List<ScreenshotViewport> everyRegionViewports =\s*'
        r'<ScreenshotViewport>\[([^\]]*)\]',
      ).firstMatch(harness);
      expect(
        list,
        isNotNull,
        reason:
            'tool/screenshots/harness.dart no longer declares '
            '`everyRegionViewports`. It is the list a width matrix passes, and '
            'the regions below are what it exists to cover.',
      );
      final named = list!
          .group(1)!
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
      final covered = <double>[];
      for (final name in named) {
        expect(
          widthOf.keys,
          contains(name),
          reason:
              '`everyRegionViewports` names $name, which is not a '
              '`ScreenshotViewport` declared in the same file.',
        );
        covered.add(widthOf[name]!);
      }

      // Ascending, so a region is `[bound, nextBound)` and the last is open.
      final bounds = <double>{
        layout.reading,
        layout.mediumFloor,
        layout.expandedFloor,
        layout.records,
      }.toList()..sort();
      expect(bounds, <double>[720, 768, 1024, 1200]);

      for (var index = 0; index <= bounds.length; index++) {
        final from = index == 0 ? 0.0 : bounds[index - 1];
        final to = index == bounds.length ? double.infinity : bounds[index];
        expect(
          covered.where((width) => width >= from && width < to),
          isNotEmpty,
          reason:
              'No screenshot viewport falls in [$from, $to). Every width in '
              'that region renders the same arrangement of §4.1\'s bands and '
              '§4.2\'s maxima, and no picture in the harness shows it. Add one '
              'to `everyRegionViewports`, or move a boundary.',
        );
      }
    });

    test('a theme mid-animation never moves a breakpoint', () {
      // Interpolating a boundary would change a screen's shape *during a
      // fade*, for no reason a person could name. Snapping is the same
      // treatment the spacing and radius scales get, for a stronger reason.
      //
      // Not `const AppLayout()`: a const constructor canonicalizes, so the
      // two would be one object and the assertion below would hold whatever
      // `lerp` did with them.
      final other = AppLayout();
      expect(other, isNot(same(AppLayout.contract)));
      final early = AppTokens.dark.lerp(
        AppTokens.dark.copyWith(layout: other),
        0.25,
      );
      final late = AppTokens.dark.lerp(
        AppTokens.dark.copyWith(layout: other),
        0.75,
      );
      expect(early.layout, same(AppLayout.contract));
      expect(late.layout, same(other));
    });
  });

  group('the extension itself', () {
    test('spiritTheme registers it, and it is the only extension', () {
      // `same`, not `equals`: the point is that the theme hands every widget the
      // one canonicalised `const` instance rather than rebuilding it. *Which* of
      // the two it is belongs to `lib/theme.dart`, so this accepts either.
      expect(
        registered,
        anyOf(same(AppTokens.dark), same(AppTokens.profoundVerdant)),
      );
      expect(spiritTheme.extensions, hasLength(1));
    });

    test('the extension key is the class, not a field', () {
      // `ThemeExtension.type` is the key `ThemeData.extensions` is stored
      // under. A field named `type` overrides it - which is why the type roles
      // are reached as `typography` - and the lookup would then answer null
      // for ever without anything failing to compile.
      expect(AppTokens.dark.type, AppTokens);
      expect(spiritTheme.extensions.keys.single, AppTokens);
    });

    test('copyWith changes one thing and keeps the rest', () {
      final compact = AppTokens.dark.withDensity(AppDensity.compact);
      expect(compact.density, AppDensity.compact);
      expect(compact.colors, same(AppTokens.dark.colors));
      expect(compact.typography, same(AppTokens.dark.typography));
      expect(compact.motion, same(AppTokens.dark.motion));
      expect(AppTokens.dark.copyWith().density, AppTokens.dark.density);
    });

    test('lerp holds its endpoints and never invents a spring or a role', () {
      final compact = AppTokens.dark.withDensity(AppDensity.compact);
      expect(AppTokens.dark.lerp(null, 0.5), same(AppTokens.dark));
      expect(AppTokens.dark.lerp(compact, 0).density.minimumRowHeight, 64);
      expect(AppTokens.dark.lerp(compact, 1).density.minimumRowHeight, 40);
      expect(
        AppTokens.dark.lerp(compact, 0.5).density.minimumRowHeight,
        closeTo(52, 0.001),
      );
      // A body role, a curve and a spring are each one of a named few, and
      // half of one is none of them, so they snap instead.
      expect(
        AppTokens.dark.lerp(compact, 0.49).density.bodyRole,
        AppBodyRole.large,
      );
      expect(
        AppTokens.dark.lerp(compact, 0.5).density.bodyRole,
        AppBodyRole.medium,
      );
      expect(
        AppTokens.dark.lerp(compact, 0.5).motion.springs,
        AppMotion.standard.springs,
      );
      // A tap target caught mid-animation is still governed by the stricter
      // of the two rules.
      expect(AppTokens.dark.lerp(compact, 0.5).density.pointerOnly, isTrue);
    });

    testWidgets('a widget under the app theme reads the tokens', (
      tester,
    ) async {
      AppTokens? seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Builder(
            builder: (context) {
              seen = AppTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // What this proves is that a widget reaches the *registered* set through
      // `of`, not that the set is any particular palette - which is why it reads
      // `registered` rather than naming one.
      expect(seen, same(registered));
    });

    testWidgets('a screen can hold its own density for its own subtree', (
      tester,
    ) async {
      // The density decision, exercised: a nested `Theme` built from a
      // `copyWith` carries the compact token set and the swapped body role
      // down to a descendant, and none of the 756 bare `Text(` call sites in
      // the app has to be edited for it. The widget that does this arrives
      // with the first compact screen; this is the seam it will use.
      AppTokens? outside;
      AppTokens? inside;
      TextStyle? bodyInside;
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Builder(
            builder: (context) {
              outside = AppTokens.of(context);
              final tokens = outside!.withDensity(AppDensity.compact);
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: <ThemeExtension<dynamic>>[tokens],
                  textTheme: Theme.of(context).textTheme.copyWith(
                    bodyMedium: tokens.density.body(tokens.typography),
                  ),
                ),
                child: Builder(
                  builder: (context) {
                    inside = AppTokens.of(context);
                    bodyInside = Theme.of(context).textTheme.bodyMedium;
                    return const SizedBox.shrink();
                  },
                ),
              );
            },
          ),
        ),
      );
      expect(outside!.density, AppDensity.comfortable);
      expect(inside!.density, AppDensity.compact);
      expect(bodyInside!.fontSize, 14);
      expect(inside!.colors, same(outside!.colors));
    });

    testWidgets('and a theme built from scratch is refused, not guessed at', (
      tester,
    ) async {
      // A `Theme` given a fresh `ThemeData` drops every extension. Falling
      // back to the defaults would render a compact screen at comfortable
      // spacing, which looks like a layout bug rather than a wiring one.
      Object? thrown;
      await tester.pumpWidget(
        MaterialApp(
          theme: spiritTheme,
          home: Theme(
            data: ThemeData(brightness: Brightness.dark),
            child: Builder(
              builder: (context) {
                try {
                  AppTokens.of(context);
                } catch (error) {
                  thrown = error;
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(thrown, isA<FlutterError>());
      expect(thrown.toString(), contains('copyWith'));
    });
  });

  group('the roles map onto what the app already renders - §11 step 1', () {
    // The whole purpose of step 1: prove the roles land on what exists before
    // anything moves. Where they already agree, these assertions stop the two
    // drifting while both exist.
    test('the surfaces and the two wired text colours agree', () {
      // **The literals, not the live theme.** These four constants in
      // `lib/theme.dart` are no longer painted by anything - every slot that
      // read them reads a role now - so what they document is the palette this
      // app shipped, and this test is what keeps `AppColorRoles.dark` an honest
      // record of it. The live theme is checked against whatever it registers,
      // in the group at the end of this file.
      expect(surface.base, bgDark);
      expect(surface.raised, bgMid);
      expect(surface.borderSubtle, mutedGreen);
      expect(colors.action.primary.container, accentGreen);
    });

    test('the comfortable body role is the size the app renders today', () {
      // Which is why registering the token layer moves no pixel and why
      // comfortable is the root density: `bodyMedium` is already 16, and
      // `body.lg` is 16.
      expect(
        type.bodyLarge.fontSize,
        spiritTheme.textTheme.bodyMedium!.fontSize,
      );
      expect(AppDensity.comfortable.body(type), type.bodyLarge);
    });

    test('the two divergences step 3 closed are now agreements', () {
      // These were asserted as divergences from step 1 until 2026-08-11, and
      // the mechanism worked exactly as it was designed to: `AppButton` moved
      // both values in `lib/theme.dart`, this test failed, and the two rows
      // were rewritten here in the same change rather than the difference
      // going unnoticed for a release. They are kept as agreements rather than
      // deleted, because what stopped them drifting apart while both existed is
      // the same thing that stops them drifting back.
      final action = registered.colors.action;
      expect(
        action.primary.label,
        spiritTheme.colorScheme.onPrimary,
        reason: 'a label on the primary container is that tier\'s own ink',
      );
      expect(
        action.secondary.label,
        spiritTheme.outlinedButtonTheme.style!.foregroundColor!.resolve(
          <WidgetState>{},
        ),
        reason:
            'the ordinary action stopped being mint, which is §2.1\'s point',
      );
      expect(
        action.secondary.border,
        spiritTheme.outlinedButtonTheme.style!.side!
            .resolve(<WidgetState>{})!
            .color,
        reason:
            'the third repoint, taken with the two above so an unmigrated '
            'OutlinedButton and an AppButton in secondary cannot disagree',
      );
      expect(
        action.tertiary.label,
        spiritTheme.textButtonTheme.style!.foregroundColor!.resolve(
          <WidgetState>{},
        ),
      );
      expect(
        action.primary.container,
        spiritTheme.filledButtonTheme.style!.backgroundColor!.resolve(
          <WidgetState>{},
        ),
      );
    });

    test('what steps 4 and 5 still have to repoint', () {
      // The remaining rewiring rows from `DESIGN-AUDIT.md` §4.8. **They are
      // asserted as divergences on purpose**: when the step that closes one
      // lands, this test fails and the row moves into the agreement test above
      // in the same change.
      // **All three rows closed on 2026-08-22, so they are agreements now.**
      // This test spent months asserting divergences on purpose, so the step
      // that closed one would fail here rather than pass quietly. That is what
      // happened: the radius repoint made the card row an equality and this
      // test failed, in the same change.
      expect(
        spiritTheme.inputDecorationTheme.fillColor,
        registered.colors.surface.field,
        reason: 'the well is a role, not the bgMid literal it used to be',
      );
      final cardRadius =
          (spiritTheme.cardTheme.shape! as RoundedRectangleBorder).borderRadius
              as BorderRadius;
      expect(
        cardRadius.topLeft.x,
        registered.radius.md,
        reason: 'a card was 16 and is now the role, which is 8',
      );
      final inputRadius =
          (spiritTheme.inputDecorationTheme.border! as OutlineInputBorder)
              .borderRadius;
      expect(
        inputRadius.topLeft.x,
        registered.radius.md,
        reason:
            'an input was 14, then a pill, then the card corner, then the '
            'pill again, and is the card corner again now that the Stitch '
            'render is the target. The design writes it as CSS: '
            "input { border-radius: theme('borderRadius.xl') }.",
      );
    });

    test('and no button minimum shrank, which §9 makes pass/fail', () {
      // `claude.md` hard rule 6 and `DESIGN-AUDIT.md` §4.8's third
      // consequence: §5.2's `md` size is 40h, the theme's minimum is 48, and a
      // token layer is not allowed to touch a touch target.
      for (final style in <ButtonStyle?>[
        spiritTheme.filledButtonTheme.style,
        spiritTheme.elevatedButtonTheme.style,
        spiritTheme.outlinedButtonTheme.style,
      ]) {
        expect(style!.minimumSize!.resolve(<WidgetState>{})!.height, 48);
      }
    });
  });

  /// Profound Verdant, value by value, against the decisions that chose them.
  ///
  /// **Every expectation here has a decision number**, from
  /// `docs/stitch/OPEN_QUESTIONS.md`. Where the design system supplied a value
  /// the test quotes it; where it supplied none and a decision filled the gap,
  /// the test says which decision, so a later reader can tell a quotation from a
  /// choice without opening the design file.
  ///
  /// **The tint tests do the arithmetic the `const` could not.** A composited
  /// ARGB literal cannot be derived in a `const` context, so `tokens.dart` writes
  /// each one out and these tests check it against its base colour and its
  /// documented percentage. That is the only thing standing between a tint and a
  /// typo.
  group('Profound Verdant - docs/stitch/OPEN_QUESTIONS.md', () {
    const pv = AppColorRoles.profoundVerdant;

    /// The alpha byte the design system's `/10`, `/20` and `/30` suffixes mean.
    int alphaByte(double fraction) => (255 * fraction).round();

    void expectTint(
      Color tint,
      Color base,
      double fraction, {
      required String reason,
    }) {
      expect(
        (tint.r, tint.g, tint.b),
        (base.r, base.g, base.b),
        reason: 'the tint must be $reason with no hue shift',
      );
      expect(
        (tint.a * 255).round(),
        alphaByte(fraction),
        reason: 'the tint must be $reason at ${(fraction * 100).round()}%',
      );
    }

    test('AppTokens.dark is left alone, whatever the theme registers', () {
      // `dark` is the record of the shipped palette, so the swap must not have
      // been done by editing it.
      expect(AppTokens.dark.colors, same(AppColorRoles.dark));
      expect(AppTokens.dark.colors, isNot(same(pv)));
      expect(AppTokens.profoundVerdant.colors, same(pv));
    });

    test('the swap is colour only - every other field is dark\'s', () {
      // Items 19 and 20 are decided but land separately, so a roundness or type
      // regression cannot arrive inside the palette's screenshot diff.
      const swapped = AppTokens.profoundVerdant;
      expect(swapped.radius, same(AppTokens.dark.radius));
      expect(swapped.typography, same(AppTokens.dark.typography));
      expect(swapped.spacing, same(AppTokens.dark.spacing));
      expect(swapped.motion, same(AppTokens.dark.motion));
      expect(swapped.density, same(AppTokens.dark.density));
      expect(swapped.layout, same(AppTokens.dark.layout));
    });

    test('the surface ramp is the frontmatter, one tier down from dark', () {
      expect(pv.surface.base, const Color(0xFF071610));
      expect(pv.surface.raised, const Color(0xFF0D1F16));
      expect(pv.surface.sunken, const Color(0xFF03110B));
      // The move that every screenshot will show: `dark`'s base becomes
      // `raised`, and base drops to the darker value.
      expect(pv.surface.raised, AppColorRoles.dark.surface.base);
      // The design system assigns `#132A1F` to fields and to popovers both.
      expect(pv.surface.field, const Color(0xFF132A1F));
      expect(pv.surface.overlay, pv.surface.field);
      // **Both border roles moved down one tier on 2026-08-23.** The export
      // uses three border values and this set held the top two: a card edge
      // and a horizontal rule are `surface-elevated`, an input and a
      // secondary button are `outline-variant`, and `outline` is a muted text
      // colour rather than an edge.
      expect(pv.surface.borderSubtle, const Color(0xFF132A1F));
      expect(pv.surface.borderSubtle, pv.surface.field);
      expect(pv.surface.borderStrong, const Color(0xFF3D4A3D));
    });

    test('surface.selected is a role over a value the palette already had', () {
      // Added 2026-10-04 for the two-tab switch's thumb. It is
      // `surfaceContainerHighest`, which the card edge already paints, so the
      // role is new and the hex is not.
      expect(pv.surface.selected, const Color(0xFF283831));
      expect(pv.surface.selected, pv.surface.cardEdge);
      // A step above the track it sits on, which is `raised`.
      expect(
        pv.surface.selected.computeLuminance(),
        greaterThan(pv.surface.raised.computeLuminance()),
      );
    });

    test('decision 17: the scrim is carried, not taken from the prose', () {
      expect(pv.surface.scrim, AppColorRoles.dark.surface.scrim);
      expect(pv.surface.scrim.a, closeTo(0.6, 0.001));
    });

    test('text leaves pure white, and decision 15 carries disabled', () {
      expect(pv.text.primary, const Color(0xFFD4E7DD));
      expect(pv.text.primary, isNot(AppColorRoles.dark.text.primary));
      expect(pv.text.secondary, const Color(0xFFBCCBB9));
      // Derived, not quoted: no third text tier exists, so `outline` fills
      // it. It stopped being a border role on 2026-08-23 - see the surface
      // ramp - so this is the only role that reads the value now.
      expect(pv.text.tertiary, const Color(0xFF869585));
      expect(pv.text.disabled, AppColorRoles.dark.text.disabled);
    });

    test('the primary action is the frontmatter primary, not its prose', () {
      // `OPEN_QUESTIONS.md` item 1: the prose calls `#22C55E` the primary and
      // renders it in zero screens as one. It is `primary-container` here.
      expect(pv.action.primary.container, const Color(0xFF4BE277));
      expect(pv.action.primary.label, const Color(0xFF003915));
      expect(pv.action.primary.container, isNot(const Color(0xFF22C55E)));
    });

    test('decision 16: hover brightens, pressed darkens, nothing invented', () {
      final primary = pv.action.primary;
      expect(primary.hoverContainer, const Color(0xFF6BFF8F));
      expect(primary.pressedContainer, const Color(0xFF22C55E));
      // The direction is the decision. Both values are the design system's own,
      // so this asserts the ordering rather than a taste.
      expect(
        primary.hoverContainer!.computeLuminance(),
        greaterThan(primary.container.computeLuminance()),
        reason: 'hover must be brighter than rest',
      );
      expect(
        primary.pressedContainer!.computeLuminance(),
        lessThan(primary.container.computeLuminance()),
        reason: 'pressed must be darker than rest',
      );
    });

    test('decision 13: destructive is status-critical, not error', () {
      expect(pv.action.destructive.label, const Color(0xFFEF4444));
      expect(pv.action.destructive.border, pv.action.destructive.label);
      // The rejected candidate, asserted so a future edit cannot quietly swap
      // the two reds back.
      expect(pv.action.destructive.label, isNot(const Color(0xFFFFB4AB)));
      expect(pv.status.problem.fg, pv.action.destructive.label);
    });

    test('decision 15: the disabled trio is carried from dark', () {
      expect(
        pv.action.disabledContainer,
        AppColorRoles.dark.action.disabledContainer,
      );
      expect(pv.action.disabledLabel, AppColorRoles.dark.action.disabledLabel);
      expect(
        pv.action.disabledBorder,
        AppColorRoles.dark.action.disabledBorder,
      );
    });

    test('decision 18: the focus ring keeps its geometry, gains a colour', () {
      final ring = pv.action.focusRing;
      expect(ring.color, const Color(0xFF4BE277));
      // The prose's 1px is about field borders. §9 is pass/fail, so the ring
      // does not shrink.
      expect(ring.width, AppColorRoles.dark.action.focusRing.width);
      expect(ring.width, 2);
      expect(ring.offset, 2);
    });

    test('decision 14: ok is primary, and it matches the action green', () {
      expect(pv.status.ok.fg, const Color(0xFF4BE277));
      expect(pv.status.ok.fg, pv.action.primary.container);
      // The rejected candidate: `tertiary` `#2EE380`, 31 uses against 1,106.
      expect(pv.status.ok.fg, isNot(const Color(0xFF2EE380)));
    });

    test('decision 12: four of five statuses tint, and neutral does not', () {
      for (final role in <AppStatusRole>[
        pv.status.ok,
        pv.status.attention,
        pv.status.problem,
        pv.status.info,
      ]) {
        expect(role.bg.a, lessThan(1.0), reason: 'a status bg is a tint');
        expect(
          role.border.a,
          lessThan(1.0),
          reason: 'a status border is a tint',
        );
        expect(role.fg.a, 1.0, reason: 'the content is never translucent');
      }
      // Neutral's background is a surface tier, so there is no hue to be 10% of.
      expect(pv.status.neutral.bg.a, 1.0);
      expect(pv.status.neutral.bg, const Color(0xFF283831));
      expect(pv.status.neutral.border.a, 1.0);
    });

    test('every tint is its base at the percentage the export measures', () {
      expectTint(
        pv.status.ok.bg,
        pv.status.ok.fg,
        0.10,
        reason: 'bg-primary/10',
      );
      expectTint(
        pv.status.ok.border,
        pv.status.ok.fg,
        0.30,
        reason: 'border-primary/30',
      );
      expectTint(
        pv.status.attention.bg,
        pv.status.attention.fg,
        0.10,
        reason: 'the warning bg',
      );
      expectTint(
        pv.status.attention.border,
        pv.status.attention.fg,
        0.30,
        reason: 'the warning border',
      );
      expectTint(
        pv.status.info.bg,
        pv.status.info.fg,
        0.10,
        reason: 'the info bg',
      );
      expectTint(
        pv.status.info.border,
        pv.status.info.fg,
        0.30,
        reason: 'the info border',
      );
      expectTint(
        pv.status.problem.border,
        pv.status.problem.fg,
        0.30,
        reason: 'border-status-critical/30',
      );
    });

    test('decision 13: problem alone tints a colour other than its own fg', () {
      // `bg-error-container/20`, 128 uses. The one status whose background is
      // not a wash of its foreground, so it gets its own assertion.
      final bg = pv.status.problem.bg;
      expectTint(
        bg,
        const Color(0xFF93000A),
        0.20,
        reason: 'error-container/20',
      );
      expect(
        (bg.r, bg.g, bg.b),
        isNot((
          pv.status.problem.fg.r,
          pv.status.problem.fg.g,
          pv.status.problem.fg.b,
        )),
        reason: 'error-container is a different red from status-critical',
      );
    });

    test('decision 10: attention is carried, and 11 is withdrawn', () {
      // Profound Verdant has no amber, so `attention` still carries forward.
      // Asserting the identity keeps it honest as an *addition* rather than
      // letting a later edit pass off a new hex as design-system truth.
      expect(pv.status.attention.fg, AppColorRoles.dark.status.attention.fg);
      expect(pv.status.attention.fg, const Color(0xFFF2C14E));

      // **Decision 11 - carrying `dark`'s blue into `info` - was withdrawn on
      // 2026-08-23.** The palette has no blue at all, and the export writes an
      // informational notice in the muted sage it does have. One blue callout
      // on the landing route was the loudest thing on a green page.
      expect(pv.status.info.fg, const Color(0xFFB0CDBD));
      expect(pv.status.info.fg, isNot(AppColorRoles.dark.status.info.fg));
      expect(pv.status.info.fg, isNot(const Color(0xFF6FB7F2)));
    });

    test('the five statuses stay five distinct foregrounds', () {
      final foregrounds = <Color>{
        pv.status.ok.fg,
        pv.status.attention.fg,
        pv.status.problem.fg,
        pv.status.info.fg,
        pv.status.neutral.fg,
      };
      expect(
        foregrounds,
        hasLength(5),
        reason: 'status is never conveyed by a shared colour - DESIGN_RULES §9',
      );
    });

    test('every status foreground clears 4.5:1 on the new base surface', () {
      // The tints are translucent, so the surface a chip sits on is what the
      // content is actually read against. `base` moved a tier darker, which is
      // the reason to re-measure rather than assume the dark ratios carried.
      for (final entry in <String, Color>{
        'ok': pv.status.ok.fg,
        'attention': pv.status.attention.fg,
        'problem': pv.status.problem.fg,
        'info': pv.status.info.fg,
        'neutral': pv.status.neutral.fg,
      }.entries) {
        expect(
          contrastRatio(entry.value, pv.surface.base),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} on base',
        );
      }
    });

    test('body and muted text clear 4.5:1 on the new base surface', () {
      expect(
        contrastRatio(pv.text.primary, pv.surface.base),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(pv.text.secondary, pv.surface.base),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('the primary action label clears 4.5:1 on its own container', () {
      expect(
        contrastRatio(pv.action.primary.label, pv.action.primary.container),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  /// The theme reads roles, and no longer reads a literal.
  ///
  /// **These assertions name no colour**, which is the entire point: they hold
  /// whichever palette `lib/theme.dart` registers, so they prove the wiring
  /// rather than the values. Before 2026-08-22 two thirds of `spiritTheme` was
  /// painted from the four constants at the top of that file, which meant
  /// swapping the palette would have repainted the buttons and the input well
  /// while the scaffold, the cards, the app bar and every body-text colour stayed
  /// behind. Each expectation below is one slot that used to be a literal.
  group('spiritTheme paints from the registered palette', () {
    test('the page, the raised surface and the borders are roles', () {
      final surfaces = registered.colors.surface;
      expect(spiritTheme.scaffoldBackgroundColor, surfaces.base);
      expect(spiritTheme.colorScheme.surface, surfaces.raised);
      expect(spiritTheme.colorScheme.outline, surfaces.borderSubtle);
      expect(spiritTheme.colorScheme.outlineVariant, surfaces.borderSubtle);
      expect(spiritTheme.appBarTheme.backgroundColor, surfaces.base);
      expect(spiritTheme.cardTheme.color, surfaces.raised);
      expect(spiritTheme.dialogTheme.backgroundColor, surfaces.raised);
      expect(spiritTheme.bottomSheetTheme.backgroundColor, surfaces.raised);
      expect(spiritTheme.dividerTheme.color, surfaces.borderSubtle);
      expect(spiritTheme.inputDecorationTheme.fillColor, surfaces.field);
    });

    test('every text colour the theme names is a text role', () {
      final text = registered.colors.text;
      expect(spiritTheme.colorScheme.onSurface, text.primary);
      expect(spiritTheme.colorScheme.onSurfaceVariant, text.secondary);
      expect(spiritTheme.appBarTheme.foregroundColor, text.primary);
      expect(spiritTheme.textTheme.headlineLarge!.color, text.primary);
      expect(spiritTheme.textTheme.bodyMedium!.color, text.secondary);
      expect(spiritTheme.listTileTheme.textColor, text.primary);
      expect(
        spiritTheme.listTileTheme.subtitleTextStyle!.color,
        text.secondary,
      );
      expect(spiritTheme.inputDecorationTheme.hintStyle!.color, text.secondary);
      expect(spiritTheme.snackBarTheme.contentTextStyle!.color, text.primary);
    });

    test('the accent slots are the primary action container', () {
      final accent = registered.colors.action.primary.container;
      expect(spiritTheme.colorScheme.primary, accent);
      expect(spiritTheme.colorScheme.secondary, accent);
      expect(spiritTheme.iconTheme.color, accent);
      expect(spiritTheme.progressIndicatorTheme.color, accent);
      expect(spiritTheme.listTileTheme.iconColor, accent);
      expect(spiritTheme.chipTheme.checkmarkColor, accent);
    });

    test('the error slot is the problem status, not a spare red', () {
      expect(
        spiritTheme.colorScheme.error,
        registered.colors.status.problem.fg,
      );
      expect(
        (spiritTheme.inputDecorationTheme.errorBorder! as OutlineInputBorder)
            .borderSide
            .color,
        registered.colors.status.problem.fg,
      );
    });

    test('no slot is painted from the four legacy constants', () {
      // The constants still exist as the record of the shipped palette. What
      // this asserts is that the theme has stopped *reading* them - which, while
      // `dark` is registered, is only visible as the roles agreeing with them,
      // and after the swap becomes a real difference.
      final painted = <Color?>[
        spiritTheme.scaffoldBackgroundColor,
        spiritTheme.colorScheme.surface,
        spiritTheme.colorScheme.primary,
        spiritTheme.colorScheme.outline,
      ];
      final roles = <Color>[
        registered.colors.surface.base,
        registered.colors.surface.raised,
        registered.colors.action.primary.container,
        registered.colors.surface.borderSubtle,
      ];
      expect(painted, roles);
    });
  });
}
