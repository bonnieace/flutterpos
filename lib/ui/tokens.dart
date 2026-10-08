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

  // -------------------------------------------------------------------------
  // Paper - the ground a generated document sits on, which is not a screen.
  //
  // **These exist because a report is not a surface.** Every colour above was
  // chosen against a near-black ground, and the app is dark-only deliberately.
  // A PDF and a workbook are neither: they open on white and they get printed,
  // so the screen palette cannot simply be carried across. Darkening the screen
  // series to clear contrast on white collapses it - four of its eight members
  // are brand greens separated by *lightness*, and re-grounding them for paper
  // pushes all four to within dE 45 of each other, which is one colour with
  // four names.
  //
  // So paper separates by **hue** where the screen separates by lightness, and
  // these are the values that fall out of that. Every series member clears 3:1
  // against white (WCAG 1.4.11, non-text graphics) and no two are closer than
  // dE 30. `test/ui/report_palette_test.dart` measures both, so neither can rot.
  // -------------------------------------------------------------------------

  static const Color paperWhite = Color(0xFFFFFFFF);
  static const Color paperInk = Color(0xFF141A16);
  static const Color paperMutedInk = Color(0xFF4A554E);
  static const Color paperAxis = Color(0xFF5A665E);
  static const Color paperRule = Color(0xFFD4DCD7);
  static const Color paperGrid = Color(0xFFE3E8E5);
  static const Color paperWash = Color(0xFFF4F7F5);

  static const Color paperGreen = Color(0xFF25AB2E);
  static const Color paperTeal = Color(0xFF1DA39E);
  static const Color paperBlue = Color(0xFF398CF2);
  static const Color paperOlive = Color(0xFF899C42);
  static const Color paperSea = Color(0xFF45A66B);
  static const Color paperCyan = Color(0xFF279ED4);
  static const Color paperViolet = Color(0xFF763FF2);
  static const Color paperPlum = Color(0xFFDE67CB);
}

/// The raw values of **Profound Verdant**, the Stitch redesign's design system.
///
/// Quoted from the YAML frontmatter of
/// `docs/stitch/stitch_chilltent_pos_redesign_system/profound_verdant/DESIGN.md`
/// and corroborated against the token block inlined in all 76 exported
/// `code.html` files. `docs/stitch/EXPORT_MAP.md` records the occurrence counts.
///
/// **The frontmatter is the authority and its own prose is not.** That file's
/// prose names a background of `#0A1A14` and calls `#22C55E` the primary. Neither
/// survives contact with the screens: `#0A1A14` is not a token and renders in
/// zero of the 76, while `#4BE277` is `primary` in 75 and `#22C55E` is the
/// separate `primary-container` role in 75. `docs/stitch/OPEN_QUESTIONS.md`
/// item 1 records the resolution.
///
/// **Three of these already exist above under other names**, which is why the
/// repoint is smaller than it looks: [surfaceElevated] is [_Primitive.green850],
/// [surfaceCard] is [_Primitive.green900], and [currencyKes] is
/// [_Primitive.mint400]. The same hex, a different role.
///
/// **Four values are carried forward rather than quoted**, because Profound
/// Verdant does not define them and inventing one would be inventing a design
/// decision. Each is a recorded product decision in `OPEN_QUESTIONS.md`:
/// [amber400] and [blue300] are documented *additions* for the warning and info
/// tiers the design system has no colour for at all (items 10 and 11), and
/// [sageDisabled] and [green700] carry the disabled treatment forward (item 15).
final class _ProfoundVerdant {
  const _ProfoundVerdant._();

  // Surfaces, darkest to lightest.
  static const Color surfaceContainerLowest = Color(0xFF03110B);
  static const Color surface = Color(0xFF071610);
  static const Color surfaceCard = Color(0xFF0D1F16);
  static const Color surfaceElevated = Color(0xFF132A1F);
  static const Color surfaceContainerHighest = Color(0xFF283831);

  // Content on those surfaces.
  static const Color onSurface = Color(0xFFD4E7DD);
  static const Color onSurfaceVariant = Color(0xFFBCCBB9);

  // Outlines.
  static const Color outline = Color(0xFF869585);
  static const Color outlineVariant = Color(0xFF3D4A3D);

  // The action greens. `primaryFixed` is brighter than `primary` and
  // `primaryContainer` is darker, which is what makes them the hover and
  // pressed pair in `OPEN_QUESTIONS.md` item 16.
  static const Color primary = Color(0xFF4BE277);
  static const Color primaryFixed = Color(0xFF6BFF8F);
  static const Color primaryContainer = Color(0xFF22C55E);
  static const Color onPrimary = Color(0xFF003915);
  static const Color secondary = Color(0xFFB0CDBD);

  /// Destructive and problem **content** - a label, a border, a foreground.
  ///
  /// `OPEN_QUESTIONS.md` item 13 settled which of the design system's two reds
  /// this is. The screens decide it by composition rather than by prose:
  /// `text-status-critical` appears 467 times against `text-error`'s 205, and
  /// the pairing it appears in is this colour over an [errorContainer] tint.
  static const Color statusCritical = Color(0xFFEF4444);

  // -------------------------------------------------------------------------
  // Status tints.
  //
  // **A `const` cannot compute an alpha, so each is written as a composited
  // ARGB literal** - and because a literal can drift from the value it claims to
  // be, `test/ui/tokens_test.dart` asserts every one of these against its base
  // colour's RGB and its documented percentage. The arithmetic is checked by a
  // test rather than trusted in a comment, which is the same bargain the type
  // roles above make when they write a line height as a division.
  //
  // Percentages are the ones the exported screens measure, not the ones its
  // prose describes: `/10` on a background and `/30` on a border. Alpha bytes
  // are `0x1A` (10%), `0x33` (20%) and `0x4D` (30%).
  // -------------------------------------------------------------------------

  /// [primary] at 10% - the success chip background. `bg-primary/10`.
  static const Color primaryTint10 = Color(0x1A4BE277);

  /// [primary] at 30% - the success chip edge. `border-primary/30`.
  static const Color primaryTint30 = Color(0x4D4BE277);

  /// [amber400] at 10%, for the warning tier the design system has no colour for.
  static const Color amberTint10 = Color(0x1AF2C14E);

  /// [amber400] at 30%.
  static const Color amberTint30 = Color(0x4DF2C14E);

  /// [statusCritical] at 30% - the problem edge. `border-status-critical/30`,
  /// the single most common status border in the export at 122 uses.
  static const Color criticalTint30 = Color(0x4DEF4444);

  /// The problem **background**: the design system's companion `error-container`
  /// `#93000A` at 20%.
  ///
  /// **Not a tint of [statusCritical].** `OPEN_QUESTIONS.md` item 13 splits the
  /// two reds by job - critical is the content, `error-container` is what sits
  /// behind it - and the screens use `bg-error-container/20` in 128 places. The
  /// opaque `#93000A` is never painted, so it is recorded here only as this
  /// tint's base.
  static const Color errorContainerTint20 = Color(0x3393000A);

  /// [secondary] at 10% - the informational background.
  ///
  /// **The info tier stopped being blue on 2026-08-23.** Profound Verdant has
  /// no blue anywhere, and the export writes an informational notice as
  /// `bg-surface-container border border-outline-variant
  /// text-on-surface-variant` - a muted sage box, not a coloured one. The tier
  /// was carried from `dark` while nothing had been drawn from the design;
  /// once the compositions were the target, one blue callout on a green
  /// landing route was the loudest thing on it.
  static const Color secondaryTint10 = Color(0x1AB0CDBD);

  /// [secondary] at 30% - the informational edge.
  static const Color secondaryTint30 = Color(0x4DB0CDBD);

  /// Money. Profound Verdant gives currency its own role; 182 uses across the
  /// export.
  ///
  /// **It has a home as of 2026-08-22: [AppTextRoles.money].** It was quoted
  /// here and deliberately wired to nothing while the question of *which*
  /// surfaces set money apart was open. `OPEN_QUESTIONS.md` decision 23 answers
  /// it for the till and leaves the rest of the app open, which is why this is a
  /// role of its own rather than a value folded into [AppTextRoles.primary].
  static const Color currencyKes = Color(0xFF45F28D);

  // Carried forward. See the class doc: these are decisions, not quotations.
  // `blue300` was one of them and is gone: the info tier reads [secondary]
  // now, which is the design's own "Secondary / Muted Text" role.
  static const Color amber400 = _Primitive.amber400;
  static const Color sageDisabled = _Primitive.sageDisabled;
  static const Color green700 = _Primitive.green700;
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
    required this.field,
    required this.overlay,
    required this.scrim,
    required this.borderSubtle,
    required this.cardEdge,
    required this.borderStrong,
    required this.selected,
  });

  /// Page background.
  final Color base;

  /// Cards, rows, sheets.
  final Color raised;

  /// Table headers and code. **Not input wells** - see [field].
  final Color sunken;

  /// Input wells. §2.1, new in `design.md` v0.4.
  ///
  /// **The lightest surface in the set, deliberately.** The ordering runs
  /// [sunken] → [base] → [raised] → [overlay] → [field], so a field is not
  /// recessed: it sits *on* the page as a raised pill. That is the product
  /// owner's direction of 2026-08-15, and the shape this app's original sign-in
  /// always had. [sunken] keeps the two uses that genuinely are recessed.
  ///
  /// **It is `green.700`, the same primitive as [borderSubtle].** One primitive,
  /// two roles, and they never meet: a field well is bounded by [borderStrong]
  /// and never by a hairline.
  final Color field;

  /// Dialogs, menus, bottom sheets.
  final Color overlay;

  /// Behind an overlay. Black at 60%.
  final Color scrim;

  /// Hairlines and card edges.
  final Color borderSubtle;

  /// The edge of a card.
  ///
  /// **Split off [borderSubtle] on 2026-08-28, at the developer's direction.**
  /// That role was doing two jobs the export happens to give the same value:
  /// the edge around a card, and the horizontal rule inside one. They want
  /// different things. A rule divides content that is already known to belong
  /// together, so it should barely be there; a card edge is what tells a person
  /// the thing is a card at all, and at `surface-elevated` over
  /// `surface-card` - one small step - a column of them read as slabs merging
  /// into the page rather than as cards.
  ///
  /// Raising the shared value would have made every hairline in the app louder
  /// to fix the edges, so the edges got their own.
  final Color cardEdge;

  /// Inputs, secondary buttons, focus targets.
  final Color borderStrong;

  /// The chosen one of a set of options drawn side by side: the thumb of
  /// `AppTabs`' two-tab switch. **Added 2026-10-04.**
  ///
  /// **A step above [raised], because it sits on it.** The switch's track is
  /// [raised], and the thumb has to read as lifted off it the way the
  /// reference design's does. [overlay] and [field] are one step up in
  /// [dark] and none in [profoundVerdant], where they share [raised]'s
  /// neighbour; this is the next one.
  ///
  /// **No new hex.** Under Profound Verdant it is `surfaceContainerHighest`,
  /// which [cardEdge] and the neutral status already paint. Neither of those
  /// roles means *selected*, so borrowing either would tie a switch to a card
  /// edge for no reason a person could name.
  final Color selected;

  static const AppSurfaceRoles dark = AppSurfaceRoles(
    base: _Primitive.green900,
    raised: _Primitive.green850,
    sunken: _Primitive.green950,
    field: _Primitive.green700,
    overlay: _Primitive.green800,
    scrim: Color.fromRGBO(0, 0, 0, 0.6),
    borderSubtle: _Primitive.green700,
    cardEdge: _Primitive.green600,
    borderStrong: _Primitive.green600,
    selected: _Primitive.green700,
  );

  /// The same eight roles under Profound Verdant.
  ///
  /// **Every surface moves down one tier, and that is the largest single visual
  /// consequence of the repoint.** [dark] puts `#0D1F16` at [base]; here that
  /// value is [raised] and [base] becomes the darker `#071610`. Nothing is
  /// renamed and no widget changes - a widget asks for [base] either way.
  ///
  /// **[field] and [overlay] collapse to one value**, which is the design
  /// system's own decision rather than a loss of information here: it assigns
  /// `#132A1F` to input-field backgrounds ("recede into the UI") and to
  /// popovers and modals ("Level 2") both. [dark] distinguished them.
  ///
  /// **[scrim] is carried from [dark]**, at `OPEN_QUESTIONS.md` item 17.
  /// Profound Verdant states no scrim; the `0.5` in its prose is a drop shadow
  /// for a modal, which is a different job, so borrowing it would be borrowing
  /// a number written for something else.
  static const AppSurfaceRoles profoundVerdant = AppSurfaceRoles(
    base: _ProfoundVerdant.surface,
    raised: _ProfoundVerdant.surfaceCard,
    sunken: _ProfoundVerdant.surfaceContainerLowest,
    field: _ProfoundVerdant.surfaceElevated,
    overlay: _ProfoundVerdant.surfaceElevated,
    scrim: Color.fromRGBO(0, 0, 0, 0.6),
    // **The two border roles moved down one tier on 2026-08-23**, because the
    // exported screens use three border values and this set had the top two.
    // A card edge is `border-surface-elevated` (`#132A1F`) in every composition
    // that draws one, and a horizontal rule is the same value as a `bg` rather
    // than a border - so the hairline row is that, not `outline-variant`.
    // `outline-variant` (`#3D4A3D`) is what the design's own component CSS puts
    // on an input and a secondary button, which is exactly [borderStrong]'s
    // job. `outline` (`#869585`) is left to [AppTextRoles.tertiary], where the
    // design uses it: muted text and muted glyphs, not edges.
    borderSubtle: _ProfoundVerdant.surfaceElevated,
    cardEdge: _ProfoundVerdant.surfaceContainerHighest,
    borderStrong: _ProfoundVerdant.outlineVariant,
    selected: _ProfoundVerdant.surfaceContainerHighest,
  );

  static AppSurfaceRoles lerp(AppSurfaceRoles a, AppSurfaceRoles b, double t) =>
      AppSurfaceRoles(
        base: Color.lerp(a.base, b.base, t)!,
        raised: Color.lerp(a.raised, b.raised, t)!,
        sunken: Color.lerp(a.sunken, b.sunken, t)!,
        field: Color.lerp(a.field, b.field, t)!,
        overlay: Color.lerp(a.overlay, b.overlay, t)!,
        scrim: Color.lerp(a.scrim, b.scrim, t)!,
        borderSubtle: Color.lerp(a.borderSubtle, b.borderSubtle, t)!,
        cardEdge: Color.lerp(a.cardEdge, b.cardEdge, t)!,
        borderStrong: Color.lerp(a.borderStrong, b.borderStrong, t)!,
        selected: Color.lerp(a.selected, b.selected, t)!,
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
    required this.onAccent,
    required this.money,
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

  /// Ink on one of [AppAccentRoles.identity].
  ///
  /// **Its own role because those blocks are not a surface in this palette's
  /// ramp.** Every other text role is chosen against the near-black grounds; an
  /// identity block is a filled mid-tone, and [primary] - a pale sage meant for
  /// a dark ground - is the wrong ink on it. The old app put white on all six,
  /// which is what those 400 tones were picked to carry.
  final Color onAccent;

  /// An amount of money, on a surface that has decided to set money apart.
  ///
  /// **`currency-kes` `#45F28D`, and it is a role rather than a rule.** Profound
  /// Verdant gives currency a colour of its own and uses it 182 times across the
  /// export; 65 of those also carry `text-data-mono`, so the design's money is a
  /// *pair* — this colour and [AppTypeRoles.mono]. `OPEN_QUESTIONS.md` question
  /// 22 left that pair open on the ground that setting every price in the app in
  /// the mono face is a composition judgement per surface rather than a metric.
  ///
  /// **Decision 23 takes it for the till and for nothing else.** The till is the
  /// surface where a cashier reads a figure aloud to a customer while looking at
  /// four other figures, and it is the only surface in this app where money is
  /// the subject rather than a column. Every other price stays
  /// [primary]/[secondary] in [AppTypeRoles.numericBody] until its own phase
  /// decides otherwise — so this token existing is **not** permission to sweep
  /// it through the back office.
  ///
  /// **Not applied to a figure that is unavailable or unrecordable.** A price
  /// this till cannot state exactly is not money on this screen; those branches
  /// keep [AppStatusRoles.problem], because a colour that means *this is the
  /// amount* must not be worn by a thing that is not one.
  final Color money;

  static const AppTextRoles dark = AppTextRoles(
    primary: _Primitive.white,
    secondary: _Primitive.sage050,
    tertiary: _Primitive.sage200,
    disabled: _Primitive.sageDisabled,
    onAccent: Color(0xFFFFFFFF),
    // The same hex the Profound Verdant instance carries, which is the one
    // place the two palettes agree without being repointed: `currency-kes` is
    // `_Primitive.mint400`, and the previous system's accent was too.
    money: _Primitive.mint400,
  );

  /// The same four roles under Profound Verdant.
  ///
  /// **Body text stops being pure white.** [primary] moves from `#FFFFFF` to
  /// `on-surface` `#D4E7DD`, which is faintly green and is what all 76 exported
  /// screens render.
  ///
  /// **[tertiary] is derived, not quoted.** Profound Verdant names no third text
  /// tier, so this reuses `outline` - the same value [AppSurfaceRoles.borderStrong]
  /// carries. One value doing two jobs is worth noting; it is not a collision,
  /// because a muted metadata label and a strong border are never compared to
  /// one another.
  ///
  /// **[disabled] is carried from [dark]**, at `OPEN_QUESTIONS.md` item 15.
  /// Profound Verdant defines nothing for it, and WCAG exempts disabled controls
  /// from contrast, so there is no accessibility argument for deriving a new one.
  static const AppTextRoles profoundVerdant = AppTextRoles(
    primary: _ProfoundVerdant.onSurface,
    secondary: _ProfoundVerdant.onSurfaceVariant,
    tertiary: _ProfoundVerdant.outline,
    disabled: _ProfoundVerdant.sageDisabled,
    onAccent: Color(0xFFFFFFFF),
    money: _ProfoundVerdant.currencyKes,
  );

  static AppTextRoles lerp(AppTextRoles a, AppTextRoles b, double t) =>
      AppTextRoles(
        primary: Color.lerp(a.primary, b.primary, t)!,
        secondary: Color.lerp(a.secondary, b.secondary, t)!,
        tertiary: Color.lerp(a.tertiary, b.tertiary, t)!,
        disabled: Color.lerp(a.disabled, b.disabled, t)!,
        onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
        money: Color.lerp(a.money, b.money, t)!,
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

  /// A hover tint to lay **over** existing content, never a container.
  Color hoverWash() => label.withValues(alpha: hoverOverlayOpacity ?? 0);

  /// A press tint to lay **over** existing content, never a container.
  ///
  /// **The difference between this and [pressedFill] is where the colour goes,
  /// and getting it wrong is visible.** A button's whole body *is* its
  /// container, so pressing it swaps that container - which is what
  /// [pressedContainer] is, and why [pressedFill] prefers it. A card is a
  /// composed surface with a glyph and two lines of text on it, and an overlay
  /// there is stacked *on top*: a solid colour hides the card completely.
  ///
  /// **The home's module cards did exactly that.** They took [pressedFill],
  /// which for the primary tier is an opaque green, and `PressSurface` paints
  /// the overlay as a `Positioned.fill` - so a pressed card became a green
  /// rectangle with nothing on it. It went unnoticed for as long as it did
  /// because a tap normally navigates within a frame or two; a device with no
  /// network holds on the tap long enough to see it.
  Color pressedWash() => label.withValues(alpha: pressedOverlayOpacity ?? 0);

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
    required this.fieldColor,
    required this.fieldWidth,
  });

  final Color color;
  final double width;
  final double offset;

  /// The outline a focused input well or select takes in place of its resting
  /// border.
  ///
  /// **The accent, at one pixel.** On 2026-09-23 a 2px mint outline on every
  /// focused field read as a lit box, and the fix went to one neutral pixel.
  /// On 2026-09-24 the developer put the green back at that same single pixel:
  /// it is the weight that was wrong, not the colour, and a field keeps its
  /// thin look. Same value as [color], so a field and a button focus in one
  /// green.
  final Color fieldColor;
  final double fieldWidth;

  static const AppFocusRing dark = AppFocusRing(
    color: _Primitive.mint400,
    width: 2,
    offset: 2,
    fieldColor: _Primitive.mint400,
    fieldWidth: 1,
  );

  /// The same ring under Profound Verdant: a new colour, the same geometry.
  ///
  /// **The width deliberately does not follow the design system's prose**, at
  /// `OPEN_QUESTIONS.md` item 18. That prose says a `1px` border glows primary
  /// green on focus, but it says it about *input fields*, in a paragraph about
  /// field borders. `DESIGN_RULES.md` §9 makes focus visibility pass/fail, and
  /// halving the ring is the wrong direction to move a pass/fail requirement on
  /// the strength of a sentence written about something else.
  static const AppFocusRing profoundVerdant = AppFocusRing(
    color: _ProfoundVerdant.primary,
    width: 2,
    offset: 2,
    fieldColor: _ProfoundVerdant.primary,
    fieldWidth: 1,
  );

  static AppFocusRing lerp(AppFocusRing a, AppFocusRing b, double t) =>
      AppFocusRing(
        color: Color.lerp(a.color, b.color, t)!,
        width: lerpDouble(a.width, b.width, t)!,
        offset: lerpDouble(a.offset, b.offset, t)!,
        fieldColor: Color.lerp(a.fieldColor, b.fieldColor, t)!,
        fieldWidth: lerpDouble(a.fieldWidth, b.fieldWidth, t)!,
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
      // **The containers above and these two are for different surfaces, and
      // the tier needs both.** A primary *button* swaps its container; a
      // primary *card* is composed content that an overlay sits on top of, and
      // needs a wash. The figures are the same 0.08 / 0.12 the other three
      // tiers already state rather than a pair invented for this one.
      hoverOverlayOpacity: 0.08,
      pressedOverlayOpacity: 0.12,
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

  /// The same four action roles under Profound Verdant.
  ///
  /// **Hover and pressed use design-system values the design system never
  /// assigned to a state.** `OPEN_QUESTIONS.md` item 16: Profound Verdant defines
  /// `primary-fixed` `#6BFF8F` and `primary-container` `#22C55E` but never says
  /// what either is *for*. One is brighter than [_ProfoundVerdant.primary] and
  /// one is darker, so they become hover and pressed in the conventional
  /// direction. That is a decision, recorded as one - but it invents no hex.
  ///
  /// **[destructive] is `status-critical`, not `error`**, at item 13. The design
  /// system defines two reds and its prose names neither; the screens settle it,
  /// using `text-status-critical` 467 times against `text-error`'s 205.
  ///
  /// **The disabled trio is carried from [dark]**, at item 15, for the same
  /// reason [AppTextRoles.profoundVerdant] carries its disabled colour.
  ///
  /// The overlay opacities on the outlined roles are [dark]'s own mechanism and
  /// not a new value: Profound Verdant states no hover treatment for a
  /// transparent control either.
  static const AppActionRoles profoundVerdant = AppActionRoles(
    primary: AppActionRole(
      container: _ProfoundVerdant.primary,
      label: _ProfoundVerdant.onPrimary,
      hoverContainer: _ProfoundVerdant.primaryFixed,
      pressedContainer: _ProfoundVerdant.primaryContainer,
      // See the note on the dark set's primary tier: containers are for
      // buttons, these are for the wash a card takes.
      hoverOverlayOpacity: 0.08,
      pressedOverlayOpacity: 0.12,
    ),
    // **Filled, not transparent, since 2026-08-23.** Every secondary control in
    // the export is `bg-surface-elevated border border-outline-variant
    // text-on-surface` - the sign-in recovery button, the shift card's cash
    // count, the catalog's row actions - and a transparent one appears nowhere.
    // The tier keeps its overlay states, which now wash over a container rather
    // than over the page.
    secondary: AppActionRole(
      container: _ProfoundVerdant.surfaceElevated,
      label: _ProfoundVerdant.onSurface,
      border: _ProfoundVerdant.outlineVariant,
      hoverOverlayOpacity: 0.08,
      pressedOverlayOpacity: 0.12,
    ),
    tertiary: AppActionRole(
      container: Colors.transparent,
      label: _ProfoundVerdant.primary,
      hoverOverlayOpacity: 0.08,
      pressedOverlayOpacity: 0.12,
    ),
    destructive: AppActionRole(
      container: Colors.transparent,
      label: _ProfoundVerdant.statusCritical,
      border: _ProfoundVerdant.statusCritical,
      hoverOverlayOpacity: 0.08,
      pressedOverlayOpacity: 0.12,
    ),
    disabledContainer: _ProfoundVerdant.green700,
    disabledLabel: _ProfoundVerdant.sageDisabled,
    disabledBorder: _ProfoundVerdant.green700,
    focusRing: AppFocusRing.profoundVerdant,
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
/// [AppSurfaceRoles.base]. ~~That is a conflict between §2.1's values and §9's
/// boundary row, recorded in `PLAN.md` rather than resolved by inventing
/// lighter colours here.~~ **Answered 2026-08-12 and it is not a conflict:**
/// §9's 3:1 row applies to a boundary that carries meaning **on its own**, and
/// `design.md` §9 now carries that sentence. What carries the meaning here is
/// [fg], the icon and the word, and all five [fg] values clear 5:1 on both
/// grounds and 4.5:1 on their own [bg]. `StatusBadge` in `lib/ui/status.dart`
/// is the component that raised the question and the one that draws the
/// container.
/// **[bg] and [border] may carry alpha, and under Profound Verdant they do.**
///
/// `OPEN_QUESTIONS.md` item 12. The design system specifies a status chip as "a
/// low-opacity background of the status color with high-opacity text" rather than
/// as an opaque swatch, and the exported screens implement exactly that with
/// Tailwind's alpha suffixes - `/10` on a background, `/30` on a border.
///
/// A translucent [Color] expresses that natively: Flutter composites it over
/// whatever surface is behind, so the chip stays correct when a surface tier
/// moves, which is the whole reason not to bake the composite into a literal.
/// [AppStatusRoles.dark] keeps opaque values and is unaffected.
///
/// **This is only safe because every consumer is a flat decoration.** All three
/// - `StatusBadge` and `StatusBlock` in `lib/ui/status.dart`, and the selected
/// `FilterChip` in `lib/ui/chips.dart` - paint [bg] as a single
/// `BoxDecoration.color` with [border] as its `Border.all`, none of them nested
/// inside another status container. Stacking two translucent status boxes would
/// double the tint; nothing does, and a new consumer must not.
@immutable
final class AppStatusRole {
  const AppStatusRole({
    required this.fg,
    required this.bg,
    required this.border,
  });

  final Color fg;

  /// The container behind [fg]. Opaque in [AppStatusRoles.dark], translucent in
  /// [AppStatusRoles.profoundVerdant] - see this class's doc.
  final Color bg;

  /// The container's edge. Same alpha caveat as [bg].
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

  /// The same five statuses under Profound Verdant, as tints rather than swatches.
  ///
  /// **Backgrounds are the status colour at 10% and borders at 30%**, which is
  /// what the export measures rather than what its prose says: across the 76
  /// screens `bg-status-critical/10` appears 84 times and
  /// `border-status-critical/30` 122, with `bg-primary/10` and
  /// `border-primary/30` the same shape. `AppStatusRole`'s doc explains why a
  /// translucent [Color] is the right way to hold that. Alpha bytes are `0x1A`
  /// for 10% and `0x4D` for 30%.
  ///
  /// **[ok] is `primary`, not `tertiary`**, at `OPEN_QUESTIONS.md` item 14. Both
  /// greens exist and the design system assigns neither to a success state, so
  /// the screens decide: `text-primary` appears 1,106 times against
  /// `text-tertiary`'s 31, and the export's success chip is literally
  /// `text-primary bg-primary/10`. This means success and the primary action stay
  /// the same green, exactly as they are in [dark] - and `FilterChip`'s note that
  /// what disambiguates them is *the container* still holds.
  ///
  /// **[problem] is the one that does not tint its own foreground.** Item 13
  /// splits the design system's two reds by job: `status-critical` is the
  /// content, and `error-container` is the background beneath it. The screens use
  /// `bg-error-container/20` in 128 places, so that is the value and the alpha
  /// (`0x33`), rather than a 10% wash of the foreground red.
  ///
  /// **[attention] and [info] are additions, not quotations**, at items 10 and
  /// 11. Profound Verdant contains no amber, yellow, orange, or blue token at
  /// all; where the exported screens needed a warning they reached for raw
  /// Tailwind `yellow-400`, nine times across three Phase 00-era screens, none of
  /// them canonical. `DESIGN_RULES.md` still requires `reconciliation differs`
  /// and `printer unavailable` to be distinguishable, so the two tiers carry
  /// forward from [dark] and are tinted to match the others.
  ///
  /// **[neutral] alone stays opaque**, because its background is a surface tier
  /// (`surface-container-highest`) rather than a tint of a status colour. There is
  /// no status hue to be 10% of.
  static const AppStatusRoles profoundVerdant = AppStatusRoles(
    ok: AppStatusRole(
      fg: _ProfoundVerdant.primary,
      bg: _ProfoundVerdant.primaryTint10,
      border: _ProfoundVerdant.primaryTint30,
    ),
    attention: AppStatusRole(
      fg: _ProfoundVerdant.amber400,
      bg: _ProfoundVerdant.amberTint10,
      border: _ProfoundVerdant.amberTint30,
    ),
    problem: AppStatusRole(
      fg: _ProfoundVerdant.statusCritical,
      bg: _ProfoundVerdant.errorContainerTint20,
      border: _ProfoundVerdant.criticalTint30,
    ),
    info: AppStatusRole(
      fg: _ProfoundVerdant.secondary,
      bg: _ProfoundVerdant.secondaryTint10,
      border: _ProfoundVerdant.secondaryTint30,
    ),
    neutral: AppStatusRole(
      fg: _ProfoundVerdant.onSurfaceVariant,
      bg: _ProfoundVerdant.surfaceContainerHighest,
      border: _ProfoundVerdant.outlineVariant,
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

/// What a chart is painted with. **Added 2026-08-27.**
///
/// **A role set of its own, because a chart is not a surface and not a status.**
/// The weekly report draws bars, gridlines and axis labels, and until this
/// existed there was no honest token for any of them: the old screen reached
/// for `Colors.white10` and `Colors.white38` directly, which is exactly the
/// hardcoding hard rule 2 forbids. Mapping them onto text or border roles would
/// have been worse - a gridline is not a border and an axis label is not body
/// text, and the first time either role moved the chart would have moved with
/// it for no reason.
@immutable
final class AppChartRoles {
  const AppChartRoles({
    required this.bar,
    required this.barEmphasis,
    required this.gridLine,
    required this.axisLabel,
    required this.series,
  });

  /// An ordinary bar. The old screen's `mutedGreen`.
  final Color bar;

  /// The bar the eye is meant to land on - the week's best day. The old
  /// screen's `accentGreen`, and the same hex the accent role carries.
  final Color barEmphasis;

  /// The horizontal rules behind the bars: present enough to read a height
  /// against, faint enough not to compete with one.
  final Color gridLine;

  /// Day names and money along the two axes.
  final Color axisLabel;

  /// The ordered palette for a chart whose parts are *categories* rather than
  /// positions on an axis - the expense composition ring, and anything after
  /// it that has to tell one slice from another.
  ///
  /// **Neither status hue appears here, deliberately.** `red400` and `amber400`
  /// carry meaning everywhere else in this app; a red slice for *Transport*
  /// would read as a warning about transport. So this is the brand family plus
  /// the one neutral blue, ordered for separation rather than by shade, and the
  /// two nearest members sit at positions 4 and 7 - which only collide in a
  /// business that spends under seven different headings at once, and the
  /// largest headings take the earliest, most distinct colours.
  ///
  /// **A palette is never the only signal.** Every surface drawing from this
  /// also prints the label and the figure beside the swatch, per hard rule 4.
  final List<Color> series;

  static const AppChartRoles dark = AppChartRoles(
    bar: _Primitive.green700,
    barEmphasis: _Primitive.mint400,
    gridLine: _Primitive.green800,
    axisLabel: _Primitive.sage200,
    series: <Color>[
      _Primitive.mint400,
      _Primitive.blue300,
      _Primitive.sage050,
      _Primitive.green400,
      _Primitive.sage200,
      _Primitive.green600,
      _Primitive.green300,
      _Primitive.green800,
    ],
  );

  static const AppChartRoles profoundVerdant = dark;

  static AppChartRoles lerp(AppChartRoles a, AppChartRoles b, double t) =>
      AppChartRoles(
        bar: Color.lerp(a.bar, b.bar, t)!,
        barEmphasis: Color.lerp(a.barEmphasis, b.barEmphasis, t)!,
        gridLine: Color.lerp(a.gridLine, b.gridLine, t)!,
        axisLabel: Color.lerp(a.axisLabel, b.axisLabel, t)!,
        series: <Color>[
          for (var index = 0; index < a.series.length; index++)
            Color.lerp(a.series[index], b.series[index], t)!,
        ],
      );
}

/// The ground a generated document sits on, and the colours it draws with.
///
/// **A document is not a surface, for the same reason a chart is not a status.**
/// [AppChartRoles] was split out because a bar is not a panel and reusing the
/// surface roles for one would have coupled two things that move for different
/// reasons. This is that argument again, one step further out: a report leaves
/// the device. It opens on white in whatever viewer the person has, it gets
/// printed, and it gets photocopied. None of those is a dark near-black screen,
/// and a document drawn in [AppChartRoles] would arrive either invisible or as
/// a full-bleed black rectangle that empties a toner cartridge.
///
/// **Paper separates by hue; the screen separates by lightness.** That is the
/// whole difference, and it is measured rather than asserted. Four of
/// `chart.series`' eight members are brand greens that the eye tells apart by
/// how light they are against near-black. Darkening those four far enough to
/// clear contrast on white brings them within dE 45 of one another - one colour
/// with four names, which on an eight-category expense ring is useless. So the
/// series here holds hue constant against the brand and spreads *around* the
/// wheel instead, green-led, with the two hues furthest from the brand last
/// where only a business spending under eight separate headings at once reaches
/// them.
///
/// **Neither status hue appears here either**, and for the reason
/// [AppChartRoles] gives: red means problem and amber means attention
/// everywhere else in this app, so a red slice for *Transport* would read as a
/// warning about transport. The whole 0-60 band is excluded.
///
/// **A palette is still never the only signal.** `TenantReportVisual` cannot be
/// constructed without the labelled figures that accompany it, so hard rule 4
/// is kept by the type rather than by each report remembering it.
@immutable
final class AppReportRoles {
  const AppReportRoles({
    required this.paper,
    required this.wash,
    required this.ink,
    required this.mutedInk,
    required this.rule,
    required this.accent,
    required this.onAccent,
    required this.bar,
    required this.barEmphasis,
    required this.gridLine,
    required this.axisLabel,
    required this.series,
  });

  /// The page itself.
  final Color paper;

  /// A banded row - a table header, the branding lockup behind the business
  /// name. The substitute for a fill that would cost toner.
  final Color wash;

  /// Body text and figures. 17.7:1 on [paper].
  final Color ink;

  /// A caption, a note, a provenance line. 7.8:1 on [paper].
  final Color mutedInk;

  /// A hairline under a heading or between table rows.
  final Color rule;

  /// The one colour the document leads with - the title band, the emphasis bar.
  final Color accent;

  /// A label sitting on [accent].
  final Color onAccent;

  /// An ordinary bar.
  final Color bar;

  /// The bar the eye is meant to land on.
  final Color barEmphasis;

  /// The rules a height is read against, faint enough not to print heavy.
  final Color gridLine;

  /// Labels along the two axes. 6:1 on [paper], because an axis label is text.
  final Color axisLabel;

  /// The ordered categorical palette. Eight, because the expense categories are
  /// a closed enum of eight and a ring must tell all of them apart.
  final List<Color> series;

  static const AppReportRoles dark = AppReportRoles(
    paper: _Primitive.paperWhite,
    wash: _Primitive.paperWash,
    ink: _Primitive.paperInk,
    mutedInk: _Primitive.paperMutedInk,
    rule: _Primitive.paperRule,
    accent: _Primitive.green600,
    onAccent: _Primitive.paperWhite,
    bar: _Primitive.green600,
    barEmphasis: _Primitive.paperGreen,
    gridLine: _Primitive.paperGrid,
    axisLabel: _Primitive.paperAxis,
    series: <Color>[
      _Primitive.paperGreen,
      _Primitive.paperTeal,
      _Primitive.paperBlue,
      _Primitive.paperOlive,
      _Primitive.paperSea,
      _Primitive.paperCyan,
      _Primitive.paperViolet,
      _Primitive.paperPlum,
    ],
  );

  /// Paper does not change with the screen palette.
  ///
  /// Both instances are the same values, and that is the point rather than an
  /// oversight: white paper is white whichever palette the app is wearing. The
  /// second name exists only so [AppColorRoles.profoundVerdant] reads like its
  /// siblings and a future third palette has an obvious place to differ.
  static const AppReportRoles profoundVerdant = dark;

  static AppReportRoles lerp(AppReportRoles a, AppReportRoles b, double t) =>
      AppReportRoles(
        paper: Color.lerp(a.paper, b.paper, t)!,
        wash: Color.lerp(a.wash, b.wash, t)!,
        ink: Color.lerp(a.ink, b.ink, t)!,
        mutedInk: Color.lerp(a.mutedInk, b.mutedInk, t)!,
        rule: Color.lerp(a.rule, b.rule, t)!,
        accent: Color.lerp(a.accent, b.accent, t)!,
        onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
        bar: Color.lerp(a.bar, b.bar, t)!,
        barEmphasis: Color.lerp(a.barEmphasis, b.barEmphasis, t)!,
        gridLine: Color.lerp(a.gridLine, b.gridLine, t)!,
        axisLabel: Color.lerp(a.axisLabel, b.axisLabel, t)!,
        series: <Color>[
          for (var index = 0; index < a.series.length; index++)
            Color.lerp(a.series[index], b.series[index], t)!,
        ],
      );
}

/// One of [AppAccentRoles.identity]'s six, by name, in the list's own order.
enum AppIdentityAccent { blue, teal, orange, purple, pink, green }

/// Decorative identity colour, carried across from the app this one replaced.
///
/// **Distinct, never ranked, and never a status.** These say *this is a
/// different one* - one person from the next in a staff list, one module from
/// the next on the home. They say nothing about whether anything is good, bad,
/// urgent or late; [AppStatusRoles] is the only scale allowed to mean that. A
/// surface drawing from here always prints the name beside the colour, which is
/// hard rule 4's floor.
///
/// **Why it exists rather than the chart series being reused.** `chart.series`
/// is ordered for *separation between adjacent slices of one picture* and is
/// deliberately all brand-family greens plus one blue, because a red slice on a
/// spending ring would read as a warning. An avatar block is not a slice: it
/// wants to be told apart from five others at a glance across a scrolling list,
/// which wants a wider spread of hue than a ring does.
final class AppAccentRoles {
  const AppAccentRoles({required this.identity, required this.privileged});

  /// One colour per thing, picked by the thing's own identity rather than by
  /// its position in a list.
  ///
  /// **The old hub's six, which is where they came from and why there are six.**
  /// `MainHub` distinguished its modules with blue, teal, orange, purple, pink
  /// and green; these are the accessible 400 tones of that same set. They lived
  /// as a private list inside `home_navigation.dart` until the staff cards
  /// wanted the same six for their avatars.
  final List<Color> identity;

  /// What a privileged role wears - owner, administrator.
  ///
  /// **The one identity colour that does carry meaning**, and it is a rank
  /// rather than a state: the old app printed `Admin` in violet and every other
  /// role in the brand green, which is a distinction a person reads once and
  /// then recognises. It is deliberately not a status hue, because holding
  /// administrator rights is not a problem to be fixed.
  final Color privileged;

  /// The colour [seed] wears, chosen so the same person is the same colour on
  /// every screen and after every reload.
  ///
  /// **A hash of the identity, not an index into the list.** Colouring by
  /// position means a member's avatar changes the moment somebody above them is
  /// deactivated, or when a filter reorders the page - which is precisely when a
  /// person is scanning for a face they recognise.
  Color identityFor(String seed) {
    if (identity.isEmpty) return privileged;
    // **FNV-1a with a final avalanche, not `hash * 31`.** The seeds here are
    // ids from one business, so they share prefixes and differ late - and a
    // weak mix over six buckets put four of five test members on the same
    // colour, which is the one thing this is for.
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    hash ^= hash >> 16;
    hash = (hash * 0x7feb352d) & 0xffffffff;
    hash ^= hash >> 15;
    return identity[hash % identity.length];
  }

  /// The colour a named [slot] wears, for a surface that picks each thing's
  /// colour by hand rather than hashing it - the home's tiles.
  Color identityAt(AppIdentityAccent slot) {
    if (identity.isEmpty) return privileged;
    return identity[slot.index % identity.length];
  }

  static const AppAccentRoles dark = AppAccentRoles(
    identity: <Color>[
      Color(0xFF42A5F5),
      Color(0xFF26A69A),
      Color(0xFFFFA726),
      Color(0xFFAB47BC),
      Color(0xFFEC407A),
      Color(0xFF66BB6A),
    ],
    privileged: Color(0xFFA78BFA),
  );

  static const AppAccentRoles profoundVerdant = dark;

  static AppAccentRoles lerp(AppAccentRoles a, AppAccentRoles b, double t) =>
      AppAccentRoles(
        identity: <Color>[
          for (var index = 0; index < a.identity.length; index++)
            Color.lerp(a.identity[index], b.identity[index], t)!,
        ],
        privileged: Color.lerp(a.privileged, b.privileged, t)!,
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
    required this.chart,
    required this.accent,
    required this.report,
  });

  final AppSurfaceRoles surface;
  final AppTextRoles text;
  final AppActionRoles action;
  final AppStatusRoles status;
  final AppChartRoles chart;
  final AppAccentRoles accent;

  /// The paper a generated document is drawn on. See [AppReportRoles] for why
  /// it is not [chart].
  final AppReportRoles report;

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
    chart: AppChartRoles.dark,
    accent: AppAccentRoles.dark,
    report: AppReportRoles.dark,
  );

  /// The Profound Verdant palette - the second instance this class's doc above
  /// anticipated, arriving for the reason it names.
  ///
  /// **Nothing reads this yet, and that is deliberate.** [AppTokens.dark] still
  /// carries [dark], so registering this moves not one pixel. It exists so every
  /// value decided in `docs/stitch/OPEN_QUESTIONS.md` is written down in one
  /// place and checked by `test/ui/tokens_test.dart` *before* the swap that makes
  /// it visible. The swap is a one-line change in `lib/theme.dart` and its own
  /// reviewable commit, because it is the one that moves every surface, the body
  /// text, and the primary action at once.
  ///
  /// **This is colour only.** The radius repoint (item 19) and the typography
  /// families (item 20) are decided but land separately, so that a roundness
  /// regression and a palette regression cannot arrive in the same diff.
  /// `docs/stitch/TOKEN_RECONCILIATION.md` records the landing order.
  static const AppColorRoles profoundVerdant = AppColorRoles(
    surface: AppSurfaceRoles.profoundVerdant,
    text: AppTextRoles.profoundVerdant,
    action: AppActionRoles.profoundVerdant,
    status: AppStatusRoles.profoundVerdant,
    chart: AppChartRoles.profoundVerdant,
    accent: AppAccentRoles.profoundVerdant,
    report: AppReportRoles.profoundVerdant,
  );

  static AppColorRoles lerp(AppColorRoles a, AppColorRoles b, double t) =>
      AppColorRoles(
        surface: AppSurfaceRoles.lerp(a.surface, b.surface, t),
        text: AppTextRoles.lerp(a.text, b.text, t),
        action: AppActionRoles.lerp(a.action, b.action, t),
        status: AppStatusRoles.lerp(a.status, b.status, t),
        chart: AppChartRoles.lerp(a.chart, b.chart, t),
        accent: AppAccentRoles.lerp(a.accent, b.accent, t),
        report: AppReportRoles.lerp(a.report, b.report, t),
      );
}

// ---------------------------------------------------------------------------
// Type roles - design.md §2.2
// ---------------------------------------------------------------------------

/// The thirteen type roles: Profound Verdant's seven, five derived from the
/// stock sizes its screens use alongside them, and [numericBody].
///
/// **Three properties of this class are deliberate and each prevents a class of
/// defect.**
///
/// **No role carries a colour.** Colour is an [AppTextRoles] role and a widget
/// pairs the two. A type role that also held a colour would be a second place
/// for a colour to be decided, and the tests assert every one of these is
/// null.
///
/// ~~**No role names a family.**~~ **Every role names one as of 2026-08-22**,
/// and the two families are [interfaceFamily] and [monoFamily]. Profound
/// Verdant names Hanken Grotesk for interface text and JetBrains Mono for
/// figures and identifiers, and `docs/stitch/OPEN_QUESTIONS.md` decision 20
/// bundles both rather than fetching them, because the exported screens link
/// them from `fonts.googleapis.com` and a till is offline-first.
///
/// **The family belongs on the role, not only on `ThemeData.fontFamily`.** A
/// **component** theme's text style *replaces* the text theme's rather than
/// merging onto it - `ListTile` takes `listTileTheme.subtitleTextStyle`
/// outright when it is set - so a role that names no family reaches the engine
/// with none no matter what the theme's own `fontFamily` says. That is the
/// whole reason `tool/screenshots/harness.dart` used to re-apply a family to
/// nine component themes by hand. It no longer has to.
///
/// **Line height is written as the division `design.md` states it**, `40 / 32`
/// rather than `1.25`, because the document gives size and line height as a
/// pair and a reader should be able to check a token against the table without
/// arithmetic.
@immutable
final class AppTypeRoles {
  const AppTypeRoles({
    required this.display,
    required this.displayCompact,
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
    required this.numericCompact,
    required this.monoCaption,
  });

  /// `headline-lg` 32 / 1.2, 700, -0.64 tracking. Screen title, expanded only.
  ///
  /// **Repointed 2026-08-22 from `design.md` §2.2's 32 / 40 with no tracking.**
  /// Profound Verdant states 1.2 rather than 1.25 and -0.02em rather than
  /// nothing; -0.02em at 32 is -0.64 logical pixels, which is the conversion
  /// every tracked role below uses because a `TextStyle` has no `em`.
  final TextStyle display;

  /// `headline-lg-mobile` 28 / 1.2, 700. [display]'s compact sibling.
  ///
  /// **New on 2026-08-22, and the only structural addition the typography
  /// repoint made.** Profound Verdant is the first source this app has had that
  /// states a *breakpoint-aware* type value: 32 on desktop, 28 on mobile, and
  /// it bothers to name the second one separately in 42 places.
  ///
  /// **It is a sibling role, not a resolver.** The caller picks by
  /// [AppLayout] band the way every other compact/comfortable choice in this
  /// file is made. A single `display` whose size depended on the band would be
  /// one token silently meaning two things, which is the failure mode
  /// [AppSpacing]'s note argues against at length.
  ///
  /// Note it carries **no tracking** where [display] carries -0.64. That is the
  /// design's own asymmetry, not an oversight here - `headline-lg` states
  /// `letterSpacing: -0.02em` and `headline-lg-mobile` states none, in all 75
  /// screens that agree.
  final TextStyle displayCompact;

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
  /// string - which is why a surface that uppercases is a conformance item for
  /// the step that migrates it rather than for this one. There were two.
  /// `TenantRecordTable`'s headers closed on 2026-08-13, when `RecordList`
  /// replaced it and drew them in [labelMedium]; ~~`TenantStatCard`'s caption is
  /// the one left, and it is step 8's.~~ **`TenantStatCard`'s caption closed on
  /// 2026-08-14**, in step 8, when `StatTile` replaced it and drew the caption
  /// in [labelMedium] in the case the caller wrote. **No surface in `lib/`
  /// uppercases anything now**, and this role's only readers are the screenshot
  /// harness's own section headings - which is the honest position for a role
  /// §2.2 restricts to "field group labels only" in an app whose fields are
  /// labelled by `AppTextField`.
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
  /// **The family is [monoFamily] as of 2026-08-22**, repointed from Roboto
  /// Mono when Profound Verdant's `data-mono` row named JetBrains Mono. It was
  /// undecided until 2026-08-16 and Roboto Mono until this change; both earlier
  /// notes are kept in `docs/stitch/TOKEN_RECONCILIATION.md` rather than here.
  ///
  /// This role is no longer the only one that names a family - every role does
  /// now - but it is still the only one whose family is *load-bearing* rather
  /// than inherited. `rj_00OOO1` has to be unambiguous, and JetBrains Mono
  /// slashes its zero, which is the property the role exists for.
  ///
  /// **Now 14 / 1.0 / 500 with -0.14 tracking**, which is `data-mono` exactly.
  /// It was 13 / 400 until the metric repoint later the same day; both mono
  /// faces were already bundled, so the move cost no download.
  ///
  /// **The design sets money in this role**, not in [numericBody]: 65 of the
  /// places a `currency-kes` colour appears also carry `text-data-mono`.
  /// [numericBody] is deliberately left in the interface face with tabular
  /// figures, because moving every price in the app into the mono face is a
  /// composition decision rather than a metric one and nothing has taken it.
  final TextStyle mono;

  /// A headline figure on a surface too narrow for [numericHero].
  ///
  /// **The design measures this pairing directly.** A catalog card's stock and
  /// price are `text-section-title font-data-mono` - 22 in JetBrains Mono -
  /// where a reporting page's headline figure is `text-4xl`. Same job, two
  /// sizes, chosen by how much room the surface has; `StatTile` takes this one
  /// below `medium`, where [numericHero] at 30 is wide enough to force a grid
  /// of figures into one column on a phone.
  final TextStyle numericCompact;

  /// [mono] at [caption]'s size: an identifier printed under the name it
  /// belongs to, where it is read second.
  ///
  /// **New on 2026-09-22, for the stock count's rows**, where a product's SKU
  /// sits under its name. [mono] is 14, which is right for an ID that *is* the
  /// row's subject; under a 16 name it read as a second name. The stock count
  /// design draws it at 12, which is [caption]'s size and leading - so this is
  /// that pair in [mono]'s face and weight, and no size the scale did not
  /// already have.
  final TextStyle monoCaption;

  /// Hanken Grotesk, the interface face every role but [mono] is set in.
  ///
  /// Named here rather than only on `ThemeData.fontFamily` so that component
  /// themes carry it too - see the note on this class for why that distinction
  /// has teeth. Declared in `pubspec.yaml` at 400, 500, 600 and 700, which is
  /// exactly the set the roles below read.
  static const String interfaceFamily = 'Hanken Grotesk';

  /// JetBrains Mono, the face [mono] is set in.
  ///
  /// Declared at 400 and 500. The role reads 400; 500 is bundled because
  /// Profound Verdant's `data-mono` row asks for it and that repoint is a
  /// pending question rather than part of the family change.
  static const String monoFamily = 'JetBrains Mono';

  static const List<FontFeature> _tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  /// The scale as `design.md` §2.2 states it.
  /// The scale as Profound Verdant states it, repointed 2026-08-22.
  ///
  /// **Every value below is the design's served Tailwind config**, which 75 of
  /// the 76 exported screens carry byte-identically and which agrees with the
  /// `DESIGN.md` frontmatter. That agreement is why this repoint trusted the
  /// frontmatter where the radius repoint could not: there the served artifact
  /// contradicted it, here the two match. The one outlier screen states
  /// `data-mono` 13 / 1.2 and `section-title` 20, and is outvoted 75 to 1.
  ///
  /// Line heights are written as the division of the two numbers the design
  /// pairs, so a reader can check a token against the source without
  /// arithmetic. Tracking is stated in `em` there and in logical pixels here,
  /// because a `TextStyle` has no `em`; each conversion is the design's figure
  /// times the role's own size.
  static const AppTypeRoles standard = AppTypeRoles(
    // headline-lg: 32px / 1.2 / 700 / -0.02em
    display: TextStyle(
      fontFamily: interfaceFamily,
      fontSize: 32,
      height: 38.4 / 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.64,
    ),
    // headline-lg-mobile: 28px / 1.2 / 700, and no tracking - see the field.
    displayCompact: TextStyle(
      fontFamily: interfaceFamily,
      fontSize: 28,
      height: 33.6 / 28,
      fontWeight: FontWeight.w700,
    ),
    // section-title: 22px / 1.4 / 600. Mapped here rather than onto
    // [titleMedium] because 22 is this role's size exactly; see the note on
    // the class.
    titleLarge: TextStyle(
      fontFamily: interfaceFamily,
      fontSize: 22,
      height: 30.8 / 22,
      fontWeight: FontWeight.w600,
    ),
    // Derived: the design's `text-lg`, 18 / 28, which it uses 78 times for the
    // tier below a section title. Weight is the app's own - the design states
    // none for this size.
    titleMedium: TextStyle(
      fontFamily: interfaceFamily,
      fontSize: 18,
      height: 28 / 18,
      fontWeight: FontWeight.w500,
    ),
    // body-md: 16px / 1.5 / 400. The one role the two scales already agreed on.
    bodyLarge: TextStyle(
      fontFamily: interfaceFamily,
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w400,
    ),
    // body-sm: 14px / 1.5 / 400. Only the line height moved, 20 to 21.
    bodyMedium: TextStyle(
      fontFamily: interfaceFamily,
      fontSize: 14,
      height: 21 / 14,
      fontWeight: FontWeight.w400,
    ),
    // **The design measures this one directly.** `.btn-primary` is
    // `font-size: 14px; font-weight: 700; letter-spacing: 0.05em` at
    // `height: 48px` - which is also where §9's 48dp target turns up in the
    // design's own CSS rather than in this app's rules. No line height is
    // stated, so the app's own is kept rather than invented.
    labelLarge: TextStyle(
      fontFamily: interfaceFamily,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
    ),
    // Derived: the design's `text-sm`, 14 / 20, its most-used stock size at 475
    // occurrences. Sits at the same size as [labelLarge] and one weight below
    // it, which is the relationship the design draws between a button and a
    // chip.
    labelMedium: TextStyle(
      fontFamily: interfaceFamily,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w600,
    ),
    // label-caps: 12px / 1.0 / 700 / +0.05em. The design's own small-label
    // role, used 1,037 times and the most frequent of the seven.
    labelEyebrow: TextStyle(
      fontFamily: interfaceFamily,
      fontSize: 12,
      height: 12 / 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    ),
    // Derived: the design's `text-xs`, 12 / 16, 316 occurrences. Unchanged from
    // §2.2, which had already landed on the same pair.
    caption: TextStyle(
      fontFamily: interfaceFamily,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w400,
    ),
    // Derived: the design's `text-3xl`, 30 / 36, 44 occurrences and the size it
    // reaches for when a figure is the point of a card.
    //
    // **In [monoFamily] since 2026-08-23, and the design is explicit about
    // it.** Its typography section: "For currency (KES) and numerical data
    // (Stock counts, SKU numbers), JetBrains Mono is utilized to ensure
    // tabular alignment and distinct character recognition in high-pressure
    // environments." Every headline figure in the export is drawn that way -
    // `text-4xl font-data-mono text-currency-kes` on a reporting KPI,
    // `text-section-title font-data-mono` on a catalog card's stock and price.
    // The size and weight are unchanged; only the face is.
    //
    // **The weight went 700 to 500 with the face, and that is a bundling fact
    // rather than a taste.** `data-mono` states 500 and JetBrains Mono is
    // bundled at 400 and 500 - the two weights `pubspec.yaml` declares. A role
    // asking for 700 in a family bundled at 500 does not throw: the engine
    // picks the nearest declared face and renders a 500 that claims to be a
    // 700, which is exactly the silent mismatch
    // `test/ui/tokens_test.dart`'s pubspec scan exists to catch. Some exported
    // screens do pair this size with a 600; honouring that needs the face
    // bundled first, and is recorded in `docs/stitch/OPEN_QUESTIONS.md` rather
    // than asserted here.
    numericHero: TextStyle(
      fontFamily: monoFamily,
      fontSize: 30,
      height: 36 / 30,
      fontWeight: FontWeight.w500,
      fontFeatures: _tabular,
    ),
    // §2.2's 14 / 500 already matched `data-mono`'s size and weight, and it
    // takes the face too as of 2026-08-23, for the reason [numericHero] gives:
    // the design sets *every* figure in JetBrains Mono, not only the ones a
    // card is built around.
    //
    // **It is still not [mono], and the difference is the line box.** This
    // carries a 20 / 14 leading because it sits in flowing text beside a label;
    // `mono` is 14 / 14, which is `data-mono`'s own figure and is for a value
    // in a tight cell. Same face, same size, same weight, two leadings.
    numericBody: TextStyle(
      fontFamily: monoFamily,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
      fontFeatures: _tabular,
    ),
    // data-mono: 14px / 1.0 / 500 / -0.01em, in the one family that is not
    // Hanken Grotesk. See the field's own note.
    mono: TextStyle(
      fontFamily: monoFamily,
      fontSize: 14,
      height: 14 / 14,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.14,
    ),
    // `section-title`'s 22 / 1.4 in `data-mono`'s family and weight, which is
    // the pairing the export puts on a card's own figure.
    numericCompact: TextStyle(
      fontFamily: monoFamily,
      fontSize: 22,
      height: 30.8 / 22,
      fontWeight: FontWeight.w500,
      fontFeatures: _tabular,
    ),
    // `caption`'s 12 / 16 in `data-mono`'s family and weight, untracked: at 12
    // the -0.01em `mono` carries is a tenth of a pixel a glyph.
    monoCaption: TextStyle(
      fontFamily: monoFamily,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w500,
    ),
  );

  /// Every role by its `design.md` name, so a test can measure the set rather
  /// than the thirteen it was told about one at a time. `test/theme_test.dart`
  /// enumerates `TextTheme`'s fifteen slots the same way, and four of these -
  /// both numeric roles, [mono] and [labelEyebrow] - have no slot there to be
  /// enumerated in, which is the gap this map closes.
  Map<String, TextStyle> get all => <String, TextStyle>{
    'display': display,
    'display.compact': displayCompact,
    'title.lg': titleLarge,
    'title.md': titleMedium,
    'body.lg': bodyLarge,
    'body.md': bodyMedium,
    'label.lg': labelLarge,
    'label.md': labelMedium,
    'label.eyebrow': labelEyebrow,
    'caption': caption,
    'numeric.hero': numericHero,
    'numeric.compact': numericCompact,
    'numeric.body': numericBody,
    'mono': mono,
    'mono.caption': monoCaption,
  };

  static AppTypeRoles lerp(AppTypeRoles a, AppTypeRoles b, double t) =>
      AppTypeRoles(
        display: TextStyle.lerp(a.display, b.display, t)!,
        displayCompact: TextStyle.lerp(a.displayCompact, b.displayCompact, t)!,
        titleLarge: TextStyle.lerp(a.titleLarge, b.titleLarge, t)!,
        titleMedium: TextStyle.lerp(a.titleMedium, b.titleMedium, t)!,
        bodyLarge: TextStyle.lerp(a.bodyLarge, b.bodyLarge, t)!,
        bodyMedium: TextStyle.lerp(a.bodyMedium, b.bodyMedium, t)!,
        labelLarge: TextStyle.lerp(a.labelLarge, b.labelLarge, t)!,
        labelMedium: TextStyle.lerp(a.labelMedium, b.labelMedium, t)!,
        labelEyebrow: TextStyle.lerp(a.labelEyebrow, b.labelEyebrow, t)!,
        caption: TextStyle.lerp(a.caption, b.caption, t)!,
        numericHero: TextStyle.lerp(a.numericHero, b.numericHero, t)!,
        numericCompact: TextStyle.lerp(a.numericCompact, b.numericCompact, t)!,
        numericBody: TextStyle.lerp(a.numericBody, b.numericBody, t)!,
        mono: TextStyle.lerp(a.mono, b.mono, t)!,
        monoCaption: TextStyle.lerp(a.monoCaption, b.monoCaption, t)!,
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

  /// Chips, badges, small containers. **2 since 2026-08-22**, was 8.
  ///
  /// The design's status chips carry its bare `rounded` - `borderRadius.DEFAULT`,
  /// `0.125rem` - in 78 of the 82 places one appears, and its checkbox reads the
  /// same token. Nearly square, which is what "disciplined" means in the
  /// Profound Verdant shapes section.
  double get sm => 2;

  /// Cards, rows, sheets, **buttons and input wells**. **8 since 2026-08-22**,
  /// was 12.
  ///
  /// The one radius the design measures for anything substantial. Its cards are
  /// `rounded-xl`, and its own CSS gives `.btn-primary` and
  /// `input[type=...]` `border-radius: theme('borderRadius.xl')` - all three the
  /// same `0.5rem`. Buttons and fields moved onto this role from [pill] in the
  /// same change, which is where most of the visible difference is.
  double get md => 8;

  /// Dialogs, bottom sheets. **12 since 2026-08-22**, was 20.
  ///
  /// The largest radius Profound Verdant defines - its `full`, `0.75rem`. Note
  /// that is `full`, not a pill: at 12 a wide surface is a rounded rectangle and
  /// only something 24 or smaller comes out circular.
  double get lg => 12;

  /// Genuine capsules and circles: the sheet handle, the quantity stepper, the
  /// sync badge, the keypad keys.
  ///
  /// **Not buttons or fields any more, and no longer a design-system value.**
  /// Profound Verdant has no pill: what its config calls `full` is `0.75rem`,
  /// and the rendered screens show square-cornered buttons and inputs
  /// throughout. Its prose claims a "Pill-shaped" search bar and is contradicted
  /// by its own render, the same way its `#0A1A14` is contradicted by its own
  /// frontmatter.
  ///
  /// **This stays at 999 because the things still reading it are round on
  /// purpose**, and Flutter clamps a radius to half the shorter side - so the
  /// 32x4 sheet handle is a capsule at any value above 2, and the stepper's
  /// controls are circles. Where the design states a shape, the shape is a role
  /// above. Where it states none, this is the app's own and is recorded as such
  /// in `docs/stitch/OPEN_QUESTIONS.md`.
  /// Large panels: a reporting dashboard's cards, its hero figure, its tiles.
  /// **16, added 2026-09-20.**
  ///
  /// **A role above [lg] rather than a repoint of [md], and the difference is
  /// the point.** [md] is the shape of a *row* - a button, a field, a list
  /// item, a thing in a stack of like things - and Profound Verdant measures
  /// it at 8 in every one of those. A dashboard card is not one of those: it
  /// is a panel with a figure in it, several to a screen, and at 8 a grid of
  /// them reads as a table of cells rather than as cards. The product owner
  /// called the row shape too rigid for that grid on 2026-09-20.
  ///
  /// Nothing is taken off [md]; a surface that is a row keeps it. A surface
  /// that is a panel asks for this.
  double get xl => 16;

  double get pill => 999;
}

/// Backdrop-blur strength for a translucent elevated surface.
///
/// One value rather than a scale: the app draws depth as a surface step, not
/// a blur (see [AppSurfaceRoles]'s note), so this exists only for the one
/// screen that composites over its own on-screen keyboard rather than over
/// page content — the sign-in front door, restoring the glass pane its
/// original layout drew. A widget that wants depth anywhere else reaches for
/// a surface role instead of asking for a second one of these.
@immutable
final class AppEffects {
  const AppEffects();

  static const AppEffects standard = AppEffects();

  /// `ImageFilter.blur`'s sigma on both axes. 12, the sign-in pane's own
  /// figure before the token layer existed.
  double get glassBlurSigma => 12;

  /// The one other place depth is drawn rather than stepped: the floating
  /// bottom bar (`AppBottomNav`), which sits over scrolling content and has
  /// no surface beneath it to step from. A drop of 16 and a blur of 40 in
  /// `surface.sunken` at 70%, as the platform console design draws it.
  double get floatingShadowDrop => 16;

  double get floatingShadowBlur => 40;

  double get floatingShadowOpacity => 0.7;
}

// ---------------------------------------------------------------------------
// Iconography
// ---------------------------------------------------------------------------

/// The sizes a glyph is drawn at, and the Material Symbols axes it is drawn
/// with.
///
/// **Sizes and axes are one token because the font is variable.** Material
/// Symbols carries an optical-size axis, and a static 24 design drawn at 28 is
/// that design scaled up, strokes and all - heavier than anyone drew it to be.
/// [opticalSizeFor] answers the size a glyph is shown at, so each one is drawn
/// for it.
///
/// **The axes are harmless on a static font.** `Icon` hands them to the engine
/// as font variations, and a font without those axes ignores them, so an
/// `Icons.*` glyph passed through the same widget draws exactly as before.
@immutable
final class AppIconography {
  const AppIconography();

  static const AppIconography standard = AppIconography();

  /// A menu row's glyph, beside `body.lg`.
  double get row => 18;

  /// A module card's glyph, inside its own well.
  double get card => 24;

  /// The phone launcher's glyph.
  double get launcher => 28;

  /// The square well the launcher glyph sits centred in.
  double get launcherWell => 56;

  /// An empty list's glyph, the subject of the page it sits on.
  double get empty => 32;

  /// The ring an [empty] glyph sits centred in: one and a half of the 48 tap
  /// target, so it reads as the page's subject without looking pressable.
  double get emptyRing => 72;

  /// `wght`. 400 is Symbols' regular, the weight the static Material font was
  /// drawn at.
  double get weight => 400;

  /// `GRAD`. Material's own figure for a light glyph on a dark ground: light
  /// strokes on dark bloom, and -25 takes back what the bloom adds.
  double get grade => -25;

  /// `FILL` for an ordinary glyph, which is outlined.
  double get fill => 0;

  /// `FILL` for the one primary destination on a screen. The till's glyph was
  /// the only solid one on the old hub, and the axis says that in the same
  /// drawing as its neighbours rather than in a different one.
  double get primaryFill => 1;

  /// `opsz` for a glyph shown at [size], held to the font's 20 to 48 range.
  double opticalSizeFor(double size) => size.clamp(20, 48).toDouble();
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
    required this.skeletonSweep,
    required this.skeletonDelay,
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

  /// One pass of a skeleton's highlight across a block.
  ///
  /// **This app's own value, not §2.4's, and that is why it is not in
  /// [durations].** That map is the four pairs §2.4 specifies and
  /// `test/ui/tokens_test.dart` asserts its length against the specification;
  /// folding a fifth in would make an assertion about `design.md` quietly start
  /// meaning something else. This one postdates it - `docs/stitch/OPEN_QUESTIONS.md`
  /// decision 35, 2026-08-27 - and is recorded there instead.
  ///
  /// **1200ms, which is an order of magnitude slower than [long] on purpose.**
  /// The four above are transitions: a thing changing from one state to another,
  /// where anything past a third of a second reads as lag. This is a loop on a
  /// surface a person is *waiting* at, and at transition speed it strobes. It is
  /// the one place in this app where slower is calmer.
  final AppMotionDuration skeletonSweep;

  /// How long a read may take before a skeleton is drawn for it at all.
  ///
  /// **The whole reason the till stopped flashing.** The catalog comes from a
  /// Hive box on the device, so the common read resolves in a frame or two;
  /// drawing a skeleton for it and tearing it down again is the same jitter
  /// wearing a different coat. Nothing is painted until this elapses, so a warm
  /// read shows its content directly and only a genuinely slow one shows a
  /// skeleton.
  ///
  /// **100ms, which is the figure human-factors work has put on "instant" for
  /// forty years** and is also about six frames at 60Hz - long enough to cover a
  /// local read, short enough that a person waiting on a server is never left
  /// looking at nothing.
  ///
  /// A threshold rather than an animation, so its curve is [Curves.linear] and
  /// nothing reads it. It is an [AppMotionDuration] only so that every duration
  /// in the app has the same type and lerps the same way.
  final AppMotionDuration skeletonDelay;

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
    skeletonSweep: AppMotionDuration(
      duration: Duration(milliseconds: 1200),
      curve: Curves.easeInOut,
    ),
    skeletonDelay: AppMotionDuration(
      duration: Duration(milliseconds: 100),
      curve: Curves.linear,
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
  ///
  /// **Which is four, and is deliberately not every duration on this class.**
  /// [skeletonSweep] and [skeletonDelay] are this app's own and postdate §2.4;
  /// each says on itself why it stays out. Read this map as "what the
  /// specification names", which is what the test over it asserts.
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
      skeletonSweep: AppMotionDuration.lerp(
        a.skeletonSweep,
        b.skeletonSweep,
        t,
      ),
      skeletonDelay: AppMotionDuration.lerp(
        a.skeletonDelay,
        b.skeletonDelay,
        t,
      ),
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
  TextStyle of(AppTypeRoles type) => switch (this) {
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
// Layout - design.md §4.1 and §4.2
// ---------------------------------------------------------------------------

/// One of §4.1's three width bands.
///
/// **The word `compact` means something different here from what it means in
/// [AppDensity], and that collision is `design.md`'s own.** §3 calls a *density*
/// compact and §4.1 calls a *width band* compact, and they are close to
/// opposites: `AppBreakpoint.compact` is a phone, which §3 says always gets the
/// **comfortable** density, while `AppDensity.compact` is only ever reachable on
/// a pointer device at `AppBreakpoint.expanded`. Two enums keep them from being
/// passed to one another; the names are the document's and are not improved on
/// here.
enum AppBreakpoint {
  /// `< 768`. A phone.
  compact,

  /// `768 - 1023`. A tablet, or a split-screen window.
  medium,

  /// `>= 1024`. A desktop window.
  expanded;

  /// Whether this band is [other] or wider.
  ///
  /// The comparison every caller actually wants: a layout is switched on by a
  /// *floor*, not by an equality, and `band == expanded` silently excludes the
  /// wider bands the day a fourth is added.
  bool isAtLeast(AppBreakpoint other) => index >= other.index;
}

/// Which of §4.2's rows a screen's content is.
///
/// **A screen states which it is; it does not state a number.** §4.2 gives a max
/// width per *kind of surface*, so the kind is the thing a call site knows and
/// the width is the thing this file knows. A screen that passed 720 directly
/// would be a screen that has to be re-edited when §4.2 changes its mind.
enum AppContentWidth {
  /// Reading and forms: 720, centred.
  reading,

  /// Record lists and tables: 1200, centred.
  records,

  /// The sale's two-pane layout, which §4.2 gives no maximum at all - the
  /// products flex and the cart pane is fixed at [AppLayout.salePane].
  full,
}

/// §4.1's breakpoints and §4.2's content widths, as one contract.
///
/// **This is the "one variable" §4.1 asks for.** Before it, 768 was declared
/// twice - `tenantWideLayoutBreakpoint` in `lib/ui/records.dart` and
/// `wideTillBreakpoint` in `checkout_cart_panel.dart` - with a third mechanism
/// computing the same test inline in `login_screen.dart`, and 1024 was declared
/// once as `tenantTableBreakpoint` and read by three files. All four are gone
/// and every one of those callers reads this.
///
/// **The numbers did not change and that is the point of the step.** §4.1 says
/// its three names replace the two old constants "with the same numbers under
/// one name", so a rewiring that moved a figure would be a layout change wearing
/// a rename's clothes.
///
/// **Nothing overrides this per subtree, unlike [AppDensity].** §3 states
/// outright that density is "chosen by the screen"; §4.1 and §4.2 state ranges
/// and maxima as properties of the surface a person is looking at, which no
/// screen is entitled to disagree with. It still lives on [AppTokens] rather
/// than as a bare top-level constant, for the same reason [AppSpacing] does: a
/// widget that has a context reads one thing, and a second token set would carry
/// its own. The two ways in cannot drift - `test/ui/tokens_test.dart` asserts
/// [AppTokens.dark]'s layout is [contract] itself.
@immutable
final class AppLayout {
  const AppLayout();

  static const AppLayout contract = AppLayout();

  /// Where [AppBreakpoint.medium] starts. §4.1.
  double get mediumFloor => 768;

  /// Where [AppBreakpoint.expanded] starts. §4.1.
  double get expandedFloor => 1024;

  /// §4.2's maximum for reading surfaces and forms.
  double get reading => 720;

  /// §4.2's maximum for record lists and tables.
  double get records => 1200;

  /// The width of a credential column — sign-in, and the tenant-entry screens
  /// that are one card and nothing else.
  ///
  /// **Narrower than [reading], because the design draws it narrower.** The
  /// export's sign-in hero is `max-w-md` (448) on a desktop and a `390` column
  /// on a phone; 720 is the measure for a page of prose, and a two-field form
  /// laid out at it reads as a form that lost its container.
  double get credential => 448;

  /// The visual band of a small dashboard tile (`AppDashTile`): a sparkline, a
  /// segmented bar, two short lines. Fixed so every tile in a row is the same
  /// height without anyone placing them. The platform console's figure.
  double get dashVisualCompact => 56;

  /// The visual band of a tall dashboard tile: a chart, or four list lines of
  /// 46. The platform console's figure.
  double get dashVisualTall => 184;

  /// One line of a dashboard tile's list visual: a 32 glyph well with seven
  /// on either side. Four of them fill [dashVisualTall].
  double get dashListLine => 46;

  /// Chart geometry the dashboard tiles draw with: a gridline, the stub that
  /// stands for an empty week, the businesses line and its dots.
  double get chartHairline => 1;

  double get chartStub => 2;

  double get chartLine => 2;

  double get chartDot => 4;

  /// The fixed width of the sale's cart pane. §4.2's third row.
  ///
  /// Declared here with the other two because it is the same kind of figure and
  /// the same table states it. **Nothing reads it yet**: the sale path is §11
  /// step 7 and is not this step's to touch.
  double get salePane => 420;

  /// How tall a product image is drawn while somebody is choosing it.
  ///
  /// **350, which is the old catalog form's own figure** — `lib/pos/goods.dart`
  /// drew `height: 350` in both the add and the correct dialogs, and the
  /// 2026-08-25 reversal brings that presentation back. The Stitch form had
  /// shrunk it to a 64px square, and a thumbnail that small is a size at which
  /// a right photo and a wrong one look the same — which is the whole of what
  /// an operator opens this form to judge.
  ///
  /// A maximum rather than a fixed height: the well gives the image the lesser
  /// of this and a square of the width it was actually given, so a phone shows
  /// a square rather than a letterbox.
  double get productImagePreview => 350;

  /// How large a product photo is drawn in the add and edit forms, beside the
  /// words and buttons that go with it.
  ///
  /// **Twice the 64 the 2026-08-25 reversal undid**, at the developer's
  /// direction on 2026-10-08: [productImagePreview] above the fields put the
  /// first one past the middle of a phone, and it did so even with no photo.
  /// 128 is still large enough to tell a right photo from a wrong one, and the
  /// photo sheet draws it at full width for a closer look.
  double get productImageThumb => 128;

  /// Which band [width] falls in.
  ///
  /// [width] is a **screen** width in logical pixels. §4.1's ranges describe the
  /// surface a person is looking at, so resolving them against a padded box
  /// inside a page produces a boundary nobody declared - the argument
  /// `PageHeader.showsDisplayTitle` already makes for the same reason.
  AppBreakpoint breakpointOf(double width) {
    if (width >= expandedFloor) return AppBreakpoint.expanded;
    if (width >= mediumFloor) return AppBreakpoint.medium;
    return AppBreakpoint.compact;
  }

  /// Whether [width] reaches [band] or better.
  bool isAtLeast(double width, AppBreakpoint band) =>
      breakpointOf(width).isAtLeast(band);

  /// §4.2's maximum for [surface], or null where it states none.
  ///
  /// Null rather than [double.infinity] deliberately: a caller that gets null
  /// adds no constraining widget at all, where infinity would ask it to build a
  /// `ConstrainedBox` that constrains nothing.
  double? maxWidthOf(AppContentWidth surface) => switch (surface) {
    AppContentWidth.reading => reading,
    AppContentWidth.records => records,
    AppContentWidth.full => null,
  };

  /// Every content width by its `design.md` name, for a test that wants to
  /// assert the table rather than the fields.
  Map<String, double> get contentWidths => <String, double>{
    'content.reading': reading,
    'content.records': records,
    'content.salePane': salePane,
  };

  /// Every breakpoint floor by its `design.md` name.
  Map<String, double> get breakpointFloors => <String, double>{
    'breakpoint.medium': mediumFloor,
    'breakpoint.expanded': expandedFloor,
  };
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
    required this.layout,
    this.effects = AppEffects.standard,
    this.icons = AppIconography.standard,
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

  /// §4.1's breakpoints and §4.2's content widths.
  ///
  /// **Not overridden by anything, and [AppLayout] says why.** It is on the
  /// extension so a widget with a context reads one thing rather than importing
  /// a constant, which is the difference between a token layer and a folder of
  /// numbers.
  final AppLayout layout;

  /// See [AppEffects]. Defaulted rather than required so every existing
  /// call site — [dark], [profoundVerdant], and every test that builds an
  /// `AppTokens` directly — keeps compiling without naming a value it never
  /// varies.
  final AppEffects effects;

  /// See [AppIconography]. Defaulted for the same reason as [effects].
  final AppIconography icons;

  /// The one token set `design.md` defines.
  static const AppTokens dark = AppTokens(
    colors: AppColorRoles.dark,
    typography: AppTypeRoles.standard,
    spacing: AppSpacing.scale,
    radius: AppRadii.scale,
    motion: AppMotion.standard,
    density: AppDensity.comfortable,
    layout: AppLayout.contract,
  );

  /// The set `lib/theme.dart` actually registers: [dark] with the Profound
  /// Verdant palette in place of its own.
  ///
  /// **Colour only, and every other field is deliberately [dark]'s.** The
  /// radius repoint and the typography families are decided
  /// (`docs/stitch/OPEN_QUESTIONS.md` items 19 and 20) and land as their own
  /// commits, because a roundness regression and a palette regression arriving
  /// in one screenshot diff is a diff nobody can review.
  ///
  /// **[dark] is kept rather than replaced.** It is the palette this app shipped,
  /// `test/ui/tokens_test.dart` still measures its internal contrast and its
  /// agreement with the legacy constants in `lib/theme.dart`, and holding both
  /// means the swap is a one-word change here rather than an edit to every value.
  static const AppTokens profoundVerdant = AppTokens(
    colors: AppColorRoles.profoundVerdant,
    typography: AppTypeRoles.standard,
    spacing: AppSpacing.scale,
    radius: AppRadii.scale,
    motion: AppMotion.standard,
    density: AppDensity.comfortable,
    layout: AppLayout.contract,
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
  static AppTokens componentOf(BuildContext context) =>
      maybeOf(context) ?? dark;

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
    AppLayout? layout,
    AppEffects? effects,
    AppIconography? icons,
  }) => AppTokens(
    colors: colors ?? this.colors,
    typography: typography ?? this.typography,
    spacing: spacing ?? this.spacing,
    radius: radius ?? this.radius,
    motion: motion ?? this.motion,
    density: density ?? this.density,
    layout: layout ?? this.layout,
    effects: effects ?? this.effects,
    icons: icons ?? this.icons,
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
      // Same reason as the two scales above, and a stronger one: a breakpoint
      // half way between 768 and some other 768 is a boundary that would move
      // *while a theme animates*, so a screen could change shape mid-fade for
      // no reason a person could name.
      layout: t < 0.5 ? layout : other.layout,
      // A single value, same reasoning as spacing and radius above.
      effects: t < 0.5 ? effects : other.effects,
      icons: t < 0.5 ? icons : other.icons,
    );
  }
}
