/// The design system's token layer: `design.md` §2, §3 and §6, as one
/// [ThemeExtension].
///
/// **Nothing reads this yet, and that is the point.** `design.md` §11 step 1 is
/// "changes no pixels", so this file defines every role the specification names
/// and repoints not one existing value. `lib/theme.dart` registers it and
/// otherwise renders exactly what it rendered before; the rewiring - the input
/// well moving to [AppSurfaceRoles.sunken], the secondary button label moving
/// off mint, the card radius dropping from 16 to 12 - belongs to steps 2 to 5,
/// where each image diff has one cause. See `DESIGN-AUDIT.md` §6 decision 1 for
/// why that split was chosen over correcting the claim.
///
/// **Two layers, and the split is enforced by visibility.** `design.md` §2.1's
/// primitives are the raw values and "are never referenced by a widget", so they
/// are private to this file. A widget reads a *role*: if the role it needs does
/// not exist, the answer is to add it to `design.md` first, not to reach for a
/// hex value. That order of operations is `design.md` §0 and it is the whole
/// difference between a design system and a folder of constants.
///
/// **Every value here is quoted from `design.md`, never derived.** Where the
/// document left something genuinely undecided - the family behind
/// [AppTypeRoles.mono], and light mode - this file carries the metrics it does
/// define and the open question is recorded in `PLAN.md` rather than answered
/// with a plausible-looking value.
library;

import 'dart:ui' show FontFeature, lerpDouble;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Primitives - design.md §2.1. Private: a widget must reach a role instead.
// ---------------------------------------------------------------------------

/// The raw values of `design.md` §2.1.
///
/// Fifteen of the document's sixteen, plus two the role tables state and the
/// primitive table omits ([ink] and [sageDisabled]). The sixteenth,
/// `sage.100` `#A0BCAC`, is **deliberately absent**: no role in §2.1 consumes
/// it, and a colour nothing can reach is a value waiting to be picked up by a
/// widget that needed a role instead. It goes in when a role wants it.
///
/// Seven of them already exist in
/// `lib/theme.dart` as `bgDark`, `bgMid`, `mutedGreen`, `accentGreen`, its two
/// private colours, and `Colors.white`; `test/ui/tokens_test.dart` measures the
/// overlap so the two cannot drift while both exist.
final class _Primitive {
  const _Primitive._();

  static const Color green950 = Color(0xFF08140E);
  static const Color green900 = Color(0xFF0D1F16);
  static const Color green850 = Color(0xFF132A1F);
  static const Color green800 = Color(0xFF1C3328);
  static const Color green700 = Color(0xFF1E3A2B);
  static const Color green600 = Color(0xFF2C5340);
  static const Color green400 = Color(0xFF34B169);
  static const Color green300 = Color(0xFF3DD47C);
  static const Color mint400 = Color(0xFF45F28D);
  static const Color sage200 = Color(0xFF849E8F);
  static const Color sage050 = Color(0xFFB8D6C5);
  static const Color white = Color(0xFFFFFFFF);
  static const Color red400 = Color(0xFFFF5C6C);
  static const Color amber400 = Color(0xFFF2C14E);
  static const Color blue300 = Color(0xFF6FB7F2);

  /// Dark ink for a label on [mint400], from §2.1's action table.
  ///
  /// Deliberately **not** `green900`: §2.1 names `#0A0F0C` here, which is
  /// darker than the page, and `lib/theme.dart` currently uses `bgDark`
  /// (`#0D1F16`) for the same job. The two are one of step 3's rewiring rows.
  static const Color ink = Color(0xFF0A0F0C);

  /// A disabled label, from §2.1's text and action tables. Not in the primitive
  /// table there either, and it is the one value the document permits to fail
  /// AA - WCAG exempts disabled controls.
  static const Color sageDisabled = Color(0xFF5D7468);
}

// ---------------------------------------------------------------------------
// Colour roles - design.md §2.1
// ---------------------------------------------------------------------------

/// Where a thing is painted. `design.md` §2.1, surface roles.
///
/// Depth is a surface step, never a drop shadow: on a near-black ground a
/// shadow is invisible and only costs raster time.
@immutable
final class AppSurfaceRoles {
  const AppSurfaceRoles({
    required this.base,
    required this.raised,
    required this.sunken,
    required this.overlay,
    required this.scrim,
    required this.borderSubtle,
    required this.borderStrong,
  });

  /// Page background.
  final Color base;

  /// Cards, rows, sheets.
  final Color raised;

  /// Input wells, table headers, code.
  final Color sunken;

  /// Dialogs, menus, bottom sheets.
  final Color overlay;

  /// Behind an overlay. Black at 60%.
  final Color scrim;

  /// Hairlines and card edges.
  final Color borderSubtle;

  /// Inputs, secondary buttons, focus targets.
  final Color borderStrong;

  static const AppSurfaceRoles dark = AppSurfaceRoles(
    base: _Primitive.green900,
    raised: _Primitive.green850,
    sunken: _Primitive.green950,
    overlay: _Primitive.green800,
    scrim: Color.fromRGBO(0, 0, 0, 0.6),
    borderSubtle: _Primitive.green700,
    borderStrong: _Primitive.green600,
  );

  static AppSurfaceRoles lerp(AppSurfaceRoles a, AppSurfaceRoles b, double t) =>
      AppSurfaceRoles(
        base: Color.lerp(a.base, b.base, t)!,
        raised: Color.lerp(a.raised, b.raised, t)!,
        sunken: Color.lerp(a.sunken, b.sunken, t)!,
        overlay: Color.lerp(a.overlay, b.overlay, t)!,
        scrim: Color.lerp(a.scrim, b.scrim, t)!,
        borderSubtle: Color.lerp(a.borderSubtle, b.borderSubtle, t)!,
        borderStrong: Color.lerp(a.borderStrong, b.borderStrong, t)!,
      );
}

/// What a person reads. `design.md` §2.1, text roles.
///
/// These are colours only. The *shape* of a piece of text is an
/// [AppTypeRoles] role, and a widget pairs the two - which is why no role in
/// either class carries the other's half.
@immutable
final class AppTextRoles {
  const AppTextRoles({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.disabled,
  });

  /// Headings, figures, record titles.
  final Color primary;

  /// Body copy, and the default label colour.
  final Color secondary;

  /// Metadata, timestamps, helper text. **The floor for anything a person is
  /// expected to read** - §2.1 says so in as many words.
  final Color tertiary;

  /// Disabled labels only. 3.40:1 on [AppSurfaceRoles.base] and 3.02:1 on
  /// [AppSurfaceRoles.raised], which is below AA on purpose: WCAG exempts a
  /// disabled control, and §2.1 permits this colour nowhere else.
  final Color disabled;

  static const AppTextRoles dark = AppTextRoles(
    primary: _Primitive.white,
    secondary: _Primitive.sage050,
    tertiary: _Primitive.sage200,
    disabled: _Primitive.sageDisabled,
  );

  static AppTextRoles lerp(AppTextRoles a, AppTextRoles b, double t) =>
      AppTextRoles(
        primary: Color.lerp(a.primary, b.primary, t)!,
        secondary: Color.lerp(a.secondary, b.secondary, t)!,
        tertiary: Color.lerp(a.tertiary, b.tertiary, t)!,
        disabled: Color.lerp(a.disabled, b.disabled, t)!,
      );
}

/// One action tier. `design.md` §2.1, action roles and the interaction-state
/// table beneath it.
///
/// The states are held as data rather than as a rule a widget remembers,
/// because §2.1 states two different rules: the primary tier moves its
/// *container* through named colours, and the other three overlay their own
/// *label* colour at 8% and 12%. A widget that hardcoded one of those would be
/// right about a quarter of the app.
@immutable
final class AppActionRole {
  const AppActionRole({
    required this.container,
    required this.label,
    this.border,
    this.hoverContainer,
    this.pressedContainer,
    this.hoverOverlayOpacity,
    this.pressedOverlayOpacity,
  });

  /// Transparent for every tier but primary.
  final Color container;

  final Color label;

  /// Null where the tier draws no border.
  final Color? border;

  /// The primary tier's hover container. Null on the overlay tiers.
  final Color? hoverContainer;

  /// The primary tier's pressed container. Null on the overlay tiers.
  final Color? pressedContainer;

  /// The overlay tiers' hover strength, applied to [label]. Null on primary.
  final double? hoverOverlayOpacity;

  /// The overlay tiers' pressed strength, applied to [label]. Null on primary.
  final double? pressedOverlayOpacity;

  /// The container this tier paints while hovered.
  ///
  /// Answers for both rules, so a caller does not have to know which kind of
  /// tier it holds.
  Color hoverFill() =>
      hoverContainer ?? label.withValues(alpha: hoverOverlayOpacity ?? 0);

  /// The container this tier paints while pressed.
  Color pressedFill() =>
      pressedContainer ?? label.withValues(alpha: pressedOverlayOpacity ?? 0);

  static AppActionRole lerp(AppActionRole a, AppActionRole b, double t) =>
      AppActionRole(
        container: Color.lerp(a.container, b.container, t)!,
        label: Color.lerp(a.label, b.label, t)!,
        border: Color.lerp(a.border, b.border, t),
        hoverContainer: Color.lerp(a.hoverContainer, b.hoverContainer, t),
        pressedContainer: Color.lerp(a.pressedContainer, b.pressedContainer, t),
        hoverOverlayOpacity: lerpDouble(
          a.hoverOverlayOpacity,
          b.hoverOverlayOpacity,
          t,
        ),
        pressedOverlayOpacity: lerpDouble(
          a.pressedOverlayOpacity,
          b.pressedOverlayOpacity,
          t,
        ),
      );
}

/// The focus indicator. `design.md` §9 makes it pass/fail: 2px, 2px offset,
/// visible on every interactive element.
///
/// It is the one boundary in the whole system that carries information on its
/// own, and it is the one that clears §9's 3:1 - 11.71:1 on
/// [AppSurfaceRoles.base]. The container borders in §2.1 do not; see the note
/// on [AppStatusRole].
@immutable
final class AppFocusRing {
  const AppFocusRing({
    required this.color,
    required this.width,
    required this.offset,
  });

  final Color color;
  final double width;
  final double offset;

  static const AppFocusRing dark = AppFocusRing(
    color: _Primitive.mint400,
    width: 2,
    offset: 2,
  );

  static AppFocusRing lerp(AppFocusRing a, AppFocusRing b, double t) =>
      AppFocusRing(
        color: Color.lerp(a.color, b.color, t)!,
        width: lerpDouble(a.width, b.width, t)!,
        offset: lerpDouble(a.offset, b.offset, t)!,
      );
}

/// The four action tiers, their shared disabled treatment, and the focus ring.
@immutable
final class AppActionRoles {
  const AppActionRoles({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.destructive,
    required this.disabledContainer,
    required this.disabledLabel,
    required this.disabledBorder,
    required this.focusRing,
    required this.loadingIndicatorSize,
  });

  /// Exactly one per screen region.
  final AppActionRole primary;

  /// The ordinary case. **Not mint** - §2.1 calls this the single biggest
  /// change in the document, and `lib/theme.dart` still paints it
  /// `accentGreen`, which is step 3's row rather than this chunk's.
  final AppActionRole secondary;

  /// Inline, low-commitment.
  final AppActionRole tertiary;

  /// Removes or reverses. Has no counterpart in the app today at all.
  final AppActionRole destructive;

  /// The primary tier's disabled container. The overlay tiers show no fill.
  final Color disabledContainer;

  final Color disabledLabel;

  /// The overlay tiers' disabled border.
  final Color disabledBorder;

  final AppFocusRing focusRing;

  /// The spinner that replaces a label while an action is in flight. §2.1's
  /// loading row: the container is held and the measured width frozen, so a
  /// button does not resize mid-press.
  final double loadingIndicatorSize;

  static const AppActionRoles dark = AppActionRoles(
    primary: AppActionRole(
      container: _Primitive.mint400,
      label: _Primitive.ink,
      hoverContainer: _Primitive.green300,
      pressedContainer: _Primitive.green400,
    ),
    secondary: AppActionRole(
      container: Colors.transparent,
      label: _Primitive.sage050,
      border: _Primitive.green600,
      hoverOverlayOpacity: 0.08,
      pressedOverlayOpacity: 0.12,
    ),
    tertiary: AppActionRole(
      container: Colors.transparent,
      label: _Primitive.mint400,
      hoverOverlayOpacity: 0.08,
      pressedOverlayOpacity: 0.12,
    ),
    destructive: AppActionRole(
      container: Colors.transparent,
      label: _Primitive.red400,
      border: _Primitive.red400,
      hoverOverlayOpacity: 0.08,
      pressedOverlayOpacity: 0.12,
    ),
    disabledContainer: _Primitive.green700,
    disabledLabel: _Primitive.sageDisabled,
    disabledBorder: _Primitive.green700,
    focusRing: AppFocusRing.dark,
    loadingIndicatorSize: 16,
  );

  static AppActionRoles lerp(AppActionRoles a, AppActionRoles b, double t) =>
      AppActionRoles(
        primary: AppActionRole.lerp(a.primary, b.primary, t),
        secondary: AppActionRole.lerp(a.secondary, b.secondary, t),
        tertiary: AppActionRole.lerp(a.tertiary, b.tertiary, t),
        destructive: AppActionRole.lerp(a.destructive, b.destructive, t),
        disabledContainer: Color.lerp(
          a.disabledContainer,
          b.disabledContainer,
          t,
        )!,
        disabledLabel: Color.lerp(a.disabledLabel, b.disabledLabel, t)!,
        disabledBorder: Color.lerp(a.disabledBorder, b.disabledBorder, t)!,
        focusRing: AppFocusRing.lerp(a.focusRing, b.focusRing, t),
        loadingIndicatorSize: lerpDouble(
          a.loadingIndicatorSize,
          b.loadingIndicatorSize,
          t,
        )!,
      );
}

/// One status, as a triple. `design.md` §2.1, status roles.
///
/// **A status is a container plus a label plus a shape, never a colour alone** -
/// roughly one man in twelve cannot separate this red from this green, and this
/// app is about money. The container is also what disambiguates
/// [AppStatusRoles.ok] from the brand accent, which are deliberately the same
/// mint: an action never draws a container of this kind and a status always
/// does. Do not remove the container to tidy it up.
///
/// **[border] is decoration, not signal, and it does not clear §9's 3:1 for a
/// UI boundary** - the five sit between 1.38:1 and 2.04:1 on
/// [AppSurfaceRoles.base]. That is a conflict between §2.1's values and §9's
/// boundary row, recorded in `PLAN.md` rather than resolved by inventing
/// lighter colours here. What carries the meaning is [fg], the icon and the
/// word, and all five [fg] values clear 5:1 on both grounds and 4.5:1 on their
/// own [bg].
@immutable
final class AppStatusRole {
  const AppStatusRole({
    required this.fg,
    required this.bg,
    required this.border,
  });

  final Color fg;
  final Color bg;
  final Color border;

  static AppStatusRole lerp(AppStatusRole a, AppStatusRole b, double t) =>
      AppStatusRole(
        fg: Color.lerp(a.fg, b.fg, t)!,
        bg: Color.lerp(a.bg, b.bg, t)!,
        border: Color.lerp(a.border, b.border, t)!,
      );
}

/// The five statuses. Each has exactly one meaning; §1 of `design.md` is blunt
/// about the alternative, which is the one green this app currently uses for
/// seven jobs.
@immutable
final class AppStatusRoles {
  const AppStatusRoles({
    required this.ok,
    required this.attention,
    required this.problem,
    required this.info,
    required this.neutral,
  });

  /// Reconciled, confirmed, in stock.
  final AppStatusRole ok;

  /// Unreconciled, pending, awaiting.
  final AppStatusRole attention;

  /// Difference found, unreadable, out of stock.
  final AppStatusRole problem;

  /// Offline, read-only, informational.
  final AppStatusRole info;

  /// Archived, retired, closed.
  final AppStatusRole neutral;

  static const AppStatusRoles dark = AppStatusRoles(
    ok: AppStatusRole(
      fg: _Primitive.mint400,
      bg: Color(0xFF143824),
      border: _Primitive.green600,
    ),
    attention: AppStatusRole(
      fg: _Primitive.amber400,
      bg: Color(0xFF28321D),
      border: Color(0xFF5A4C24),
    ),
    problem: AppStatusRole(
      fg: _Primitive.red400,
      bg: Color(0xFF2A2620),
      border: Color(0xFF6B3238),
    ),
    info: AppStatusRole(
      fg: _Primitive.blue300,
      bg: Color(0xFF193130),
      border: Color(0xFF2E4C60),
    ),
    neutral: AppStatusRole(
      fg: _Primitive.sage200,
      bg: _Primitive.green800,
      border: _Primitive.green700,
    ),
  );

  /// Every status by its `design.md` name, for a caller that has to render all
  /// five - and for the tests, which measure the set rather than five colours
  /// they were told about one at a time.
  Map<String, AppStatusRole> get all => <String, AppStatusRole>{
    'ok': ok,
    'attention': attention,
    'problem': problem,
    'info': info,
    'neutral': neutral,
  };

  static AppStatusRoles lerp(AppStatusRoles a, AppStatusRoles b, double t) =>
      AppStatusRoles(
        ok: AppStatusRole.lerp(a.ok, b.ok, t),
        attention: AppStatusRole.lerp(a.attention, b.attention, t),
        problem: AppStatusRole.lerp(a.problem, b.problem, t),
        info: AppStatusRole.lerp(a.info, b.info, t),
        neutral: AppStatusRole.lerp(a.neutral, b.neutral, t),
      );
}

/// Every colour role in one place. `design.md` §2.1.
@immutable
final class AppColorRoles {
  const AppColorRoles({
    required this.surface,
    required this.text,
    required this.action,
    required this.status,
  });

  final AppSurfaceRoles surface;
  final AppTextRoles text;
  final AppActionRoles action;
  final AppStatusRoles status;

  /// The only palette `design.md` defines.
  ///
  /// §12 asks whether dark is the only theme and answers nothing, so there is
  /// no light palette to write down and none is invented here. If one is ever
  /// decided, it arrives as a second instance of this class and every widget
  /// that reads a role follows it without being edited - which is the reason
  /// the role layer exists.
  static const AppColorRoles dark = AppColorRoles(
    surface: AppSurfaceRoles.dark,
    text: AppTextRoles.dark,
    action: AppActionRoles.dark,
    status: AppStatusRoles.dark,
  );

  static AppColorRoles lerp(AppColorRoles a, AppColorRoles b, double t) =>
      AppColorRoles(
        surface: AppSurfaceRoles.lerp(a.surface, b.surface, t),
        text: AppTextRoles.lerp(a.text, b.text, t),
        action: AppActionRoles.lerp(a.action, b.action, t),
        status: AppStatusRoles.lerp(a.status, b.status, t),
      );
}

// ---------------------------------------------------------------------------
// Type roles - design.md §2.2
// ---------------------------------------------------------------------------

/// The twelve type roles of `design.md` §2.2.
///
/// **Three properties of this class are deliberate and each prevents a class of
/// defect.**
///
/// **No role carries a colour.** Colour is an [AppTextRoles] role and a widget
/// pairs the two. A type role that also held a colour would be a second place
/// for a colour to be decided, and the tests assert every one of these is
/// null.
///
/// **No role names a family.** `lib/theme.dart` names none either, and the note
/// there says why: this app asked for `Inter` for years and no `Inter` was ever
/// bundled. §2.2 says "One family - Roboto", which is currently true only in
/// the screenshot harness, which injects it. Naming nothing is the honest
/// version of what a device already does.
///
/// **Line height is written as the division `design.md` states it**, `40 / 32`
/// rather than `1.25`, because the document gives size and line height as a
/// pair and a reader should be able to check a token against the table without
/// arithmetic.
@immutable
final class AppTypeRoles {
  const AppTypeRoles({
    required this.display,
    required this.titleLarge,
    required this.titleMedium,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.labelLarge,
    required this.labelMedium,
    required this.labelEyebrow,
    required this.caption,
    required this.numericHero,
    required this.numericBody,
    required this.mono,
  });

  /// `display` 32 / 40, 700. Screen title, expanded only.
  final TextStyle display;

  /// `title.lg` 22 / 28, 500. Screen title on compact, section head.
  final TextStyle titleLarge;

  /// `title.md` 18 / 24, 500. Card title, record name.
  final TextStyle titleMedium;

  /// `body.lg` 16 / 24, 400. Primary body, till-facing copy. The body role at
  /// [AppDensity.comfortable].
  final TextStyle bodyLarge;

  /// `body.md` 14 / 20, 400. Back-office body, table cells. The body role at
  /// [AppDensity.compact].
  final TextStyle bodyMedium;

  /// `label.lg` 15 / 20, 600. Button labels.
  final TextStyle labelLarge;

  /// `label.md` 13 / 16, 600. Chips, tabs, table headers.
  final TextStyle labelMedium;

  /// `label.eyebrow` 11 / 16, 700, +0.8 tracking, uppercase.
  ///
  /// **The only role uppercase is permitted on** (§2.2, and §8 rule 7 for the
  /// copy). The case itself is the caller's - a `TextStyle` cannot uppercase a
  /// string - which is why the two surfaces that uppercase today,
  /// `TenantStatCard`'s caption and every `TenantRecordTable` header, are a
  /// conformance item for the step that migrates them rather than for this one.
  final TextStyle labelEyebrow;

  /// `caption` 12 / 16, 400. Timestamps, attribution.
  final TextStyle caption;

  /// `numeric.hero` 28 / 32, 700, tabular. The one figure a stat tile exists
  /// for.
  final TextStyle numericHero;

  /// `numeric.body` 14 / 20, 500, tabular. Money and counts in flow.
  final TextStyle numericBody;

  /// `mono` 13 / 18, 400, monospace. Record IDs and SKUs - strings a person
  /// compares character by character, not prose.
  ///
  /// **The metrics are the document's; the family is not decided anywhere.**
  /// §2.2 says "One family - Roboto" in its opening line and "monospace" in
  /// this row, and the app bundles no font at all. So this role carries its
  /// size, height and weight and names no family, exactly like the eleven above
  /// it, and the question is recorded in `PLAN.md` rather than answered here
  /// with a family nobody chose. Until it is answered, this role renders in the
  /// platform's proportional default and is not yet fit for the job §2.2 gives
  /// it.
  final TextStyle mono;

  static const List<FontFeature> _tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  /// The scale as `design.md` §2.2 states it.
  static const AppTypeRoles standard = AppTypeRoles(
    display: TextStyle(
      fontSize: 32,
      height: 40 / 32,
      fontWeight: FontWeight.w700,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.w500,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      height: 24 / 18,
      fontWeight: FontWeight.w500,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
    ),
    labelLarge: TextStyle(
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: TextStyle(
      fontSize: 13,
      height: 16 / 13,
      fontWeight: FontWeight.w600,
    ),
    labelEyebrow: TextStyle(
      fontSize: 11,
      height: 16 / 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
    caption: TextStyle(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w400,
    ),
    numericHero: TextStyle(
      fontSize: 28,
      height: 32 / 28,
      fontWeight: FontWeight.w700,
      fontFeatures: _tabular,
    ),
    numericBody: TextStyle(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
      fontFeatures: _tabular,
    ),
    mono: TextStyle(
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w400,
    ),
  );

  /// Every role by its `design.md` name, so a test can measure the set rather
  /// than the twelve it was told about one at a time. `test/theme_test.dart`
  /// enumerates `TextTheme`'s fifteen slots the same way, and four of these -
  /// both numeric roles, [mono] and [labelEyebrow] - have no slot there to be
  /// enumerated in, which is the gap this map closes.
  Map<String, TextStyle> get all => <String, TextStyle>{
    'display': display,
    'title.lg': titleLarge,
    'title.md': titleMedium,
    'body.lg': bodyLarge,
    'body.md': bodyMedium,
    'label.lg': labelLarge,
    'label.md': labelMedium,
    'label.eyebrow': labelEyebrow,
    'caption': caption,
    'numeric.hero': numericHero,
    'numeric.body': numericBody,
    'mono': mono,
  };

  static AppTypeRoles lerp(AppTypeRoles a, AppTypeRoles b, double t) =>
      AppTypeRoles(
        display: TextStyle.lerp(a.display, b.display, t)!,
        titleLarge: TextStyle.lerp(a.titleLarge, b.titleLarge, t)!,
        titleMedium: TextStyle.lerp(a.titleMedium, b.titleMedium, t)!,
        bodyLarge: TextStyle.lerp(a.bodyLarge, b.bodyLarge, t)!,
        bodyMedium: TextStyle.lerp(a.bodyMedium, b.bodyMedium, t)!,
        labelLarge: TextStyle.lerp(a.labelLarge, b.labelLarge, t)!,
        labelMedium: TextStyle.lerp(a.labelMedium, b.labelMedium, t)!,
        labelEyebrow: TextStyle.lerp(a.labelEyebrow, b.labelEyebrow, t)!,
        caption: TextStyle.lerp(a.caption, b.caption, t)!,
        numericHero: TextStyle.lerp(a.numericHero, b.numericHero, t)!,
        numericBody: TextStyle.lerp(a.numericBody, b.numericBody, t)!,
        mono: TextStyle.lerp(a.mono, b.mono, t)!,
      );
}

// ---------------------------------------------------------------------------
// Spacing and radius - design.md §2.3
// ---------------------------------------------------------------------------

/// The spacing scale. `design.md` §2.3: a 4pt base, and **these ten values
/// only**.
///
/// **Named by value, which is a resolution rather than a preference.** §2.3
/// describes the scale as "`space.1` = 4 through `space.16` = 64", which names
/// tokens by index; §3 asks for a section gap of `space.24` and §5.2 for
/// horizontal padding of `space.20` and `space.16`, which names them by value.
/// The two collide on the name `space.16` - 64 under one reading and 16 under
/// the other - and only the value reading is coherent, because under the index
/// reading §3 gives the *compact* density a larger section gap (`space.16` =
/// 64) than the comfortable one (`space.24`, which is not on the scale at all).
/// `design.md` §2.3 now states the value naming; see the note there.
@immutable
final class AppSpacing {
  const AppSpacing();

  static const AppSpacing scale = AppSpacing();

  double get s4 => 4;
  double get s8 => 8;
  double get s12 => 12;
  double get s16 => 16;
  double get s20 => 20;
  double get s24 => 24;
  double get s32 => 32;
  double get s40 => 40;
  double get s48 => 48;
  double get s64 => 64;

  /// Every permitted value, ascending. A spacing that is not in this list is
  /// not a spacing, and the tests say so.
  List<double> get all => <double>[
    s4,
    s8,
    s12,
    s16,
    s20,
    s24,
    s32,
    s40,
    s48,
    s64,
  ];
}

/// The radius scale. `design.md` §2.3.
///
/// **[pill] is buttons only.** The shape is this app's signature and stays, but
/// when buttons, chips, filters, cards and inputs are all pills the shape stops
/// signifying - so chips and inputs drop to [sm]. Today's theme is stadium on
/// buttons *and* chips and 14 on inputs; moving them is step 3's diff, not this
/// one's.
@immutable
final class AppRadii {
  const AppRadii();

  static const AppRadii scale = AppRadii();

  /// Chips, badges, inputs.
  double get sm => 8;

  /// Cards, rows, sheets.
  double get md => 12;

  /// Dialogs, bottom sheets.
  double get lg => 20;

  /// Buttons only.
  double get pill => 999;
}

// ---------------------------------------------------------------------------
// Motion - design.md §2.4
// ---------------------------------------------------------------------------

/// A duration and its curve, for `design.md` §2.4's opacity-and-colour half.
///
/// The two travel together because the split they belong to is the point: a
/// duration is for something that changes opacity or colour, and anything that
/// moves in space takes a spring instead.
@immutable
final class AppMotionDuration {
  const AppMotionDuration({required this.duration, required this.curve});

  final Duration duration;
  final Curve curve;

  static AppMotionDuration lerp(
    AppMotionDuration a,
    AppMotionDuration b,
    double t,
  ) => AppMotionDuration(
    duration: Duration(
      microseconds: lerpDouble(
        a.duration.inMicroseconds,
        b.duration.inMicroseconds,
        t,
      )!.round(),
    ),
    // A curve is not a continuum. Snapping is honest where interpolating would
    // invent a third curve that is neither of them.
    curve: t < 0.5 ? a.curve : b.curve,
  );
}

/// The springs and durations of `design.md` §2.4.
///
/// **A spring is for anything spatial and a duration is for opacity and colour,
/// and that split is the single largest contributor to this app reading as iOS
/// rather than as Material.** A duration-and-curve animation cannot be
/// interrupted gracefully; a spring retargets from its current position and
/// velocity, never restarts from zero, and never has to finish. Which is also
/// `claude.md`'s motion rule: never `forward()` from zero on a retrigger.
@immutable
final class AppMotion {
  const AppMotion({
    required this.snappy,
    required this.smooth,
    required this.gentle,
    required this.bouncy,
    required this.instant,
    required this.short,
    required this.medium,
    required this.long,
    required this.pressScale,
    required this.routeParallax,
  });

  /// Press states, chips, toggles, stepper.
  final SpringDescription snappy;

  /// Sheets, panes, route transitions, expansion.
  final SpringDescription smooth;

  /// Large surfaces, hero figures.
  final SpringDescription gentle;

  /// **Reward layer only** (§6.2). Overshoot is a reward signal; on an
  /// operational surface it reads as instability, which is why the other three
  /// are critically or near-critically damped and this one is not.
  final SpringDescription bouncy;

  final AppMotionDuration instant;
  final AppMotionDuration short;
  final AppMotionDuration medium;
  final AppMotionDuration long;

  /// What a pressed surface scales to, from §2.4's replacement for the ink
  /// ripple: opacity plus scale at `spring.snappy`, and no expanding circle.
  final double pressScale;

  /// How far the surface being covered travels while the incoming one arrives,
  /// as a fraction of its own width.
  ///
  /// §6.2's "Route push (compact)" row: *incoming full / outgoing parallax at
  /// 30%*. It lives here rather than in the route because it is the same kind
  /// of value [pressScale] is - a figure `design.md` states, which a widget
  /// must not restate.
  ///
  /// **It has no counterpart on the expanded row**, which is a fade-through
  /// with no horizontal travel at all, so nothing reads this above
  /// `tenantTableBreakpoint`.
  final double routeParallax;

  static const AppMotion standard = AppMotion(
    snappy: SpringDescription(mass: 1, stiffness: 380, damping: 32),
    smooth: SpringDescription(mass: 1, stiffness: 220, damping: 30),
    gentle: SpringDescription(mass: 1, stiffness: 140, damping: 24),
    bouncy: SpringDescription(mass: 1, stiffness: 260, damping: 18),
    instant: AppMotionDuration(
      duration: Duration(milliseconds: 80),
      curve: Curves.linear,
    ),
    short: AppMotionDuration(
      duration: Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
    ),
    medium: AppMotionDuration(
      duration: Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
    ),
    long: AppMotionDuration(
      duration: Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    ),
    pressScale: 0.97,
    routeParallax: 0.3,
  );

  /// Every spring by its `design.md` name.
  Map<String, SpringDescription> get springs => <String, SpringDescription>{
    'spring.snappy': snappy,
    'spring.smooth': smooth,
    'spring.gentle': gentle,
    'spring.bouncy': bouncy,
  };

  /// Every duration by its `design.md` name.
  Map<String, AppMotionDuration> get durations => <String, AppMotionDuration>{
    'motion.instant': instant,
    'motion.short': short,
    'motion.medium': medium,
    'motion.long': long,
  };

  static AppMotion lerp(AppMotion a, AppMotion b, double t) {
    // A spring is a physical description rather than a value on a line: half
    // way between two of them is a fourth spring nobody specified, and a
    // surface mid-flight reads its spring once. Snapping keeps every spring in
    // the app one of the four.
    final springs = t < 0.5 ? a : b;
    return AppMotion(
      snappy: springs.snappy,
      smooth: springs.smooth,
      gentle: springs.gentle,
      bouncy: springs.bouncy,
      instant: AppMotionDuration.lerp(a.instant, b.instant, t),
      short: AppMotionDuration.lerp(a.short, b.short, t),
      medium: AppMotionDuration.lerp(a.medium, b.medium, t),
      long: AppMotionDuration.lerp(a.long, b.long, t),
      pressScale: lerpDouble(a.pressScale, b.pressScale, t)!,
      routeParallax: lerpDouble(a.routeParallax, b.routeParallax, t)!,
    );
  }
}

// ---------------------------------------------------------------------------
// Density - design.md §3
// ---------------------------------------------------------------------------

/// Which body role a density reads. `design.md` §3's "Body role" row.
///
/// An enum rather than a `TextStyle`, because a density describes *which* role
/// it uses and the roles themselves live in [AppTypeRoles]. Two copies of
/// `body.lg` is how the second one drifts.
enum AppBodyRole {
  /// `body.lg`, 16 / 24.
  large,

  /// `body.md`, 14 / 20.
  medium;

  /// This role, resolved against a type scale.
  TextStyle of(AppTypeRoles type) =>
      switch (this) {
        AppBodyRole.large => type.bodyLarge,
        AppBodyRole.medium => type.bodyMedium,
      };
}

/// One of the two densities of `design.md` §3.
///
/// **Density is a property of the surface, chosen by the screen, and it arrives
/// as a nested `Theme`.** That structure was decided with this chunk, over two
/// alternatives, and the reason is arithmetic rather than taste: `bodyMedium`
/// is a single global value and all 756 bare `Text(` call sites in the migrated
/// tree resolve to it through `DefaultTextStyle`, so one `ThemeData` cannot
/// hold two body sizes. A screen that wants compact wraps its subtree in a
/// `Theme` built from `Theme.of(context).copyWith(...)` carrying the compact
/// [AppTokens] and a `bodyMedium` swapped to [bodyRole] - which keeps §3's "by
/// the screen" literal and edits none of the 756 sites. Reading the role at
/// every call site would have been the other correct answer and it eventually
/// edits all of them.
///
/// **The widget that does the wrapping is not in this chunk**, because step 1
/// changes no pixels and no screen is compact yet. What is here is the half
/// that decides: the two value sets, and [bodyRole] as the seam a nested
/// `Theme` reads. The trap to know when it is built: a `Theme` given a fresh
/// `ThemeData(...)` rather than a `copyWith` drops every extension, and
/// [AppTokens.of] throws rather than silently answering with the defaults.
@immutable
final class AppDensity {
  const AppDensity({
    required this.minimumRowHeight,
    required this.rowPadding,
    required this.bodyRole,
    required this.minimumTapTarget,
    required this.sectionGap,
    required this.pointerOnly,
  });

  final double minimumRowHeight;

  /// **Horizontal then vertical, which is an inference where §3 is silent.**
  /// The document writes "16 / 16" and "12 / 8" and never says which is which.
  /// Comfortable is symmetric, so only compact carries the question, and the
  /// row height answers it: 8 above and below a 20-high `body.md` line is 36
  /// and fits the 40 minimum, while 12 above and below is 44 and cannot. Both
  /// figures are on the §2.3 scale either way.
  final EdgeInsets rowPadding;

  final AppBodyRole bodyRole;

  /// §9 makes this pass/fail at [comfortable]. At [compact] it is 32 x 32 and
  /// permitted only where [pointerOnly] is honoured.
  final Size minimumTapTarget;

  final double sectionGap;

  /// **Whether this density may only be given to a pointer device.** True for
  /// [compact]: §3 says a touch device never gets 32px targets whatever its
  /// width, so the rule is carried as data rather than left in prose for the
  /// widget that resolves density to remember.
  final bool pointerOnly;

  /// The sale, the shift, sign-in, and every compact-width screen.
  static const AppDensity comfortable = AppDensity(
    minimumRowHeight: 64,
    rowPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    bodyRole: AppBodyRole.large,
    minimumTapTarget: Size(48, 48),
    sectionGap: 24,
    pointerOnly: false,
  );

  /// The catalog, ledger, reconciliation, activity log and staff surfaces, at
  /// 1024 and above, on a pointer device.
  static const AppDensity compact = AppDensity(
    minimumRowHeight: 40,
    rowPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    bodyRole: AppBodyRole.medium,
    minimumTapTarget: Size(32, 32),
    sectionGap: 16,
    pointerOnly: true,
  );

  /// This density's body style, resolved against a type scale.
  TextStyle body(AppTypeRoles type) => bodyRole.of(type);

  static AppDensity lerp(AppDensity a, AppDensity b, double t) => AppDensity(
    minimumRowHeight: lerpDouble(a.minimumRowHeight, b.minimumRowHeight, t)!,
    rowPadding: EdgeInsets.lerp(a.rowPadding, b.rowPadding, t)!,
    // A body role is one of two named roles and half of one is neither.
    bodyRole: t < 0.5 ? a.bodyRole : b.bodyRole,
    minimumTapTarget: Size.lerp(a.minimumTapTarget, b.minimumTapTarget, t)!,
    sectionGap: lerpDouble(a.sectionGap, b.sectionGap, t)!,
    // A tap target that is 40px because a theme is mid-animation must still be
    // honoured by the stricter of the two rules.
    pointerOnly: a.pointerOnly || b.pointerOnly,
  );
}

// ---------------------------------------------------------------------------
// The extension itself
// ---------------------------------------------------------------------------

/// The design system, as a [ThemeExtension].
///
/// A `ThemeExtension` rather than a set of top-level constants for one reason
/// that matters: `Theme` already carries it down the tree, animates it, and -
/// the part the density decision rests on - lets a screen override it for its
/// own subtree with a `copyWith`.
///
/// Registered by `spiritTheme` in `lib/theme.dart`. Nothing reads it yet.
@immutable
final class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.colors,
    required this.typography,
    required this.spacing,
    required this.radius,
    required this.motion,
    required this.density,
  });

  final AppColorRoles colors;

  /// The type roles.
  ///
  /// **Named `typography` and not `type`, and that is not a style choice.**
  /// [ThemeExtension] declares `Object get type`, and it is the key
  /// `ThemeData.extensions` is stored and looked up under. A field called
  /// `type` overrides it, so the map would be keyed by an [AppTypeRoles]
  /// instance and `Theme.of(context).extension<AppTokens>()` would answer null
  /// forever - a lookup that fails silently rather than a compile error.
  final AppTypeRoles typography;

  final AppSpacing spacing;
  final AppRadii radius;
  final AppMotion motion;

  /// The density of the surface this token set was read on.
  ///
  /// [AppDensity.comfortable] at the root, because §3 gives it every
  /// compact-width screen and the sale path, and because a screen that has not
  /// asked for compact must not get 32px tap targets. A back-office screen
  /// overrides it for its own subtree; see [AppDensity].
  final AppDensity density;

  /// The one token set `design.md` defines.
  static const AppTokens dark = AppTokens(
    colors: AppColorRoles.dark,
    typography: AppTypeRoles.standard,
    spacing: AppSpacing.scale,
    radius: AppRadii.scale,
    motion: AppMotion.standard,
    density: AppDensity.comfortable,
  );

  /// The tokens in scope at [context], or null where none are registered.
  static AppTokens? maybeOf(BuildContext context) =>
      Theme.of(context).extension<AppTokens>();

  /// The tokens in scope at [context], for a surface that depends on **its
  /// screen's density**.
  ///
  /// **Throws rather than falling back.** A missing extension means a `Theme`
  /// was built from a fresh `ThemeData` instead of a `copyWith`, and answering
  /// with the defaults would render a compact screen at comfortable spacing and
  /// look like a layout bug rather than a wiring one. Use this from the widget
  /// that *resolves* density, and from anything whose geometry is meaningless
  /// at the wrong one.
  static AppTokens of(BuildContext context) {
    final tokens = maybeOf(context);
    if (tokens == null) {
      throw FlutterError(
        'No AppTokens in the theme at this point in the tree. `spiritTheme` '
        'registers it, so this is a nested `Theme` built from a fresh '
        '`ThemeData` rather than from `Theme.of(context).copyWith(...)`, which '
        'drops every extension. A leaf component should read '
        '`AppTokens.componentOf` instead, which falls back.',
      );
    }
    return tokens;
  }

  /// The tokens in scope at [context], falling back to [dark].
  ///
  /// **This exists because [of]'s refusal is right for a screen and wrong for a
  /// component, and step 3 is where that became a real decision rather than a
  /// hypothetical one.** `AppButton` is the first token-reading widget with
  /// call sites, and a call site is reached by things that are not this app's
  /// `MaterialApp`: 46 of the widget-test files build their own bare
  /// `ThemeData`, as does any preview, any `showDialog` given a fresh theme,
  /// and any future embedder. Under [of] every one of those is a crash, which
  /// would make "remember `theme: spiritTheme`" a rule that has to be
  /// remembered at ~50 sites and then at every new one - the same kind of rule
  /// `SpiritScrollBehavior` exists to avoid.
  ///
  /// **The fallback is safe in the one direction that matters, and that is why
  /// it is allowed rather than merely convenient.** [dark] carries
  /// [AppDensity.comfortable], which is the **stricter** density on every
  /// accessibility dimension §9 measures: 48 x 48 targets rather than 32 x 32,
  /// larger rows, larger body text. So a component that falls back can render a
  /// compact screen at comfortable size - a cosmetic fault - and can never
  /// shrink a tap target below §9's floor, which is the pass/fail one.
  ///
  /// **What it cannot catch is stated rather than left implied**: a nested
  /// `Theme` built from a fresh `ThemeData` loses its screen's density
  /// silently here. That is exactly the fault [of] was written to catch, which
  /// is why [of] still exists and why the widget that resolves density must use
  /// it.
  static AppTokens componentOf(BuildContext context) => maybeOf(context) ?? dark;

  /// The same tokens at another density, for the nested `Theme` a back-office
  /// screen wraps itself in.
  AppTokens withDensity(AppDensity density) => copyWith(density: density);

  @override
  AppTokens copyWith({
    AppColorRoles? colors,
    AppTypeRoles? typography,
    AppSpacing? spacing,
    AppRadii? radius,
    AppMotion? motion,
    AppDensity? density,
  }) => AppTokens(
    colors: colors ?? this.colors,
    typography: typography ?? this.typography,
    spacing: spacing ?? this.spacing,
    radius: radius ?? this.radius,
    motion: motion ?? this.motion,
    density: density ?? this.density,
  );

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      colors: AppColorRoles.lerp(colors, other.colors, t),
      typography: AppTypeRoles.lerp(typography, other.typography, t),
      // Neither scale holds a value that varies, so there is nothing to
      // interpolate between two of them.
      spacing: t < 0.5 ? spacing : other.spacing,
      radius: t < 0.5 ? radius : other.radius,
      motion: AppMotion.lerp(motion, other.motion, t),
      density: AppDensity.lerp(density, other.density, t),
    );
  }
}
