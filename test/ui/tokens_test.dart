import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/tokens.dart';
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
      expect(surface.overlay, const Color(0xFF1C3328));
      expect(surface.borderSubtle, const Color(0xFF1E3A2B));
      expect(surface.borderStrong, const Color(0xFF2C5340));
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
        surface.overlay,
      };
      expect(distinct, hasLength(4));
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

    test('the two interaction rules do not overlap', () {
      // §2.1 states one rule for the primary tier - named hover and pressed
      // containers - and another for the three overlay tiers, which tint their
      // own label at 8% and 12%. A tier carrying both would let a widget pick
      // the wrong one and still render something plausible.
      expect(action.primary.hoverOverlayOpacity, isNull);
      expect(action.primary.pressedOverlayOpacity, isNull);
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
    test('all twelve roles exist under their specification names', () {
      expect(type.all, hasLength(12));
      expect(type.all.keys, <String>[
        'display',
        'title.lg',
        'title.md',
        'body.lg',
        'body.md',
        'label.lg',
        'label.md',
        'label.eyebrow',
        'caption',
        'numeric.hero',
        'numeric.body',
        'mono',
      ]);
    });

    test('each carries the size, line height and weight §2.2 gives it', () {
      // size / line / weight, straight off the table.
      final table = <String, (double, double, FontWeight)>{
        'display': (32, 40, FontWeight.w700),
        'title.lg': (22, 28, FontWeight.w500),
        'title.md': (18, 24, FontWeight.w500),
        'body.lg': (16, 24, FontWeight.w400),
        'body.md': (14, 20, FontWeight.w400),
        'label.lg': (15, 20, FontWeight.w600),
        'label.md': (13, 16, FontWeight.w600),
        'label.eyebrow': (11, 16, FontWeight.w700),
        'caption': (12, 16, FontWeight.w400),
        'numeric.hero': (28, 32, FontWeight.w700),
        'numeric.body': (14, 20, FontWeight.w500),
        'mono': (13, 18, FontWeight.w400),
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

    test('label.eyebrow is the only tracked role, at +0.8', () {
      for (final entry in type.all.entries) {
        expect(
          entry.value.letterSpacing,
          entry.key == 'label.eyebrow' ? 0.8 : isNull,
          reason: '${entry.key} letter spacing',
        );
      }
    });

    test('no type role carries a colour', () {
      // Colour is an `AppTextRoles` role and a widget pairs the two. A type
      // role holding a colour would be a second place a colour is decided,
      // and the second place is the one that drifts.
      for (final entry in type.all.entries) {
        expect(entry.value.color, isNull, reason: '${entry.key} names a colour');
      }
    });

    test('no type role names a family, including mono', () {
      // `lib/theme.dart` names none either, and the note there says why: this
      // app asked for Inter for years and no Inter was ever bundled.
      //
      // **`mono` is the open question, not an oversight.** §2.2's opening line
      // says "One family - Roboto" and its last row says "monospace", and the
      // app bundles no font at all, so a monospace family here would be a
      // value nobody chose. Until that is decided, `mono` carries the metrics
      // and renders proportionally - which means it is not yet fit for the job
      // §2.2 gives it. When the family is settled this assertion is the one
      // that fails, deliberately.
      for (final entry in type.all.entries) {
        expect(
          entry.value.fontFamily,
          isNull,
          reason: '${entry.key} names a family',
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

    test('the radii are the specified four', () {
      expect(tokens.radius.sm, 8);
      expect(tokens.radius.md, 12);
      expect(tokens.radius.lg, 20);
      expect(tokens.radius.pill, 999);
    });

    test('pill is unmistakably a pill and nothing else is', () {
      // §2.3: the shape is the signature and stays, but when everything is a
      // pill the shape stops signifying. Chips and inputs drop to `sm`.
      expect(
        tokens.radius.pill,
        greaterThan(tokens.radius.lg * 10),
        reason: 'pill must be a stadium, not a large radius',
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

    test('a press scales rather than ripples', () {
      // §2.4's replacement for the ink ripple: opacity plus scale at
      // `spring.snappy`, and no expanding circle anywhere.
      expect(motion.pressScale, 0.97);
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
      // reads, because the document never says. Vertical 8 leaves 36 of the 40
      // minimum; vertical 12 would need 44 and could not fit at all.
      const density = AppDensity.compact;
      final line = density.body(type).fontSize! * density.body(type).height!;
      expect(
        density.rowPadding.vertical + line,
        lessThanOrEqualTo(density.minimumRowHeight),
      );
      expect(density.rowPadding.vertical + line, closeTo(36, 0.001));
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

  group('the extension itself', () {
    test('spiritTheme registers it, and it is the only extension', () {
      expect(spiritTheme.extension<AppTokens>(), same(AppTokens.dark));
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
      expect(seen, same(AppTokens.dark));
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
      expect(surface.base, spiritTheme.scaffoldBackgroundColor);
      expect(surface.base, bgDark);
      expect(surface.raised, spiritTheme.colorScheme.surface);
      expect(surface.raised, bgMid);
      expect(colors.text.primary, spiritTheme.colorScheme.onSurface);
      expect(colors.text.secondary, spiritTheme.colorScheme.onSurfaceVariant);
      expect(surface.borderSubtle, spiritTheme.colorScheme.outline);
      expect(surface.borderSubtle, mutedGreen);
      expect(colors.action.primary.container, spiritTheme.colorScheme.primary);
      expect(colors.action.primary.container, accentGreen);
    });

    test('the comfortable body role is the size the app renders today', () {
      // Which is why registering the token layer moves no pixel and why
      // comfortable is the root density: `bodyMedium` is already 16, and
      // `body.lg` is 16.
      expect(type.bodyLarge.fontSize, spiritTheme.textTheme.bodyMedium!.fontSize);
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
      expect(
        colors.action.primary.label,
        spiritTheme.colorScheme.onPrimary,
        reason: 'a label on the primary container is §2.1\'s #0A0F0C',
      );
      expect(
        colors.action.secondary.label,
        spiritTheme.outlinedButtonTheme.style!.foregroundColor!.resolve(
          <WidgetState>{},
        ),
        reason: 'the ordinary action stopped being mint, which is §2.1\'s point',
      );
      expect(
        colors.action.secondary.border,
        spiritTheme.outlinedButtonTheme.style!.side!
            .resolve(<WidgetState>{})!
            .color,
        reason:
            'the third repoint, taken with the two above so an unmigrated '
            'OutlinedButton and an AppButton in secondary cannot disagree',
      );
      expect(
        colors.action.tertiary.label,
        spiritTheme.textButtonTheme.style!.foregroundColor!.resolve(
          <WidgetState>{},
        ),
      );
      expect(
        colors.action.primary.container,
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
      expect(
        surface.sunken,
        isNot(spiritTheme.inputDecorationTheme.fillColor),
        reason: 'the input well is still bgMid; §2.1 wants surface.sunken',
      );
      final cardRadius =
          (spiritTheme.cardTheme.shape! as RoundedRectangleBorder).borderRadius
              as BorderRadius;
      expect(
        tokens.radius.md,
        isNot(cardRadius.topLeft.x),
        reason: 'cards are still 16; §2.3 wants 12',
      );
      final inputRadius =
          (spiritTheme.inputDecorationTheme.border! as OutlineInputBorder)
              .borderRadius;
      expect(
        tokens.radius.sm,
        isNot(inputRadius.topLeft.x),
        reason: 'inputs are still 14; §2.3 wants 8',
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
}
