import 'package:flutter/material.dart';

import 'ui/tokens.dart';

// Dark theme colors
const Color bgDark = Color(0xFF0D1F16);
const Color bgMid = Color(0xFF132A1F);
const Color accentGreen = Color(0xFF45F28D);
const Color mutedGreen = Color(0xFF1E3A2B);

// `_bodyGreen` (`#B8D6C5`) and `_criticalRed` (`#FF5C6C`) used to be declared
// here and are gone: every slot that read them now reads `text.secondary` and
// `status.problem.fg`, which hold those same two values. The four public
// constants above are kept because `test/ui/tokens_test.dart` measures the token
// roles against them - they are the record of what this app shipped, not live
// paint.

/// The interaction overlay one action tier paints, from `design.md` §2.1's
/// state table.
///
/// §2.1 states **two** rules and this reads whichever one the tier holds: the
/// primary tier moves its container through named colours (`#3DD47C` hovered,
/// `#34B169` pressed) and the other three wash their own label colour over a
/// transparent container at 8% and 12%. `AppActionRole.hoverFill` and
/// `pressedFill` answer for both, so this function does not have to know which
/// kind of tier it was handed.
///
/// **Focus resolves to the hover wash, and that is not §2.1's focus row.** §2.1
/// gives focus-visible a 2px ring at 2px offset, which is a border rather than
/// an overlay and belongs to `AppButton` in step 3 and to §9's audit in step
/// 12. What this must not do is answer `null` for a focused button: a
/// `WidgetStateProperty` that resolves to null paints no overlay at all, so a
/// keyboard user would lose the only feedback they currently have while
/// waiting for the ring.
WidgetStateProperty<Color?> _pressOverlay(AppActionRole role) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) return role.pressedFill();
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return role.hoverFill();
      }
      return null;
    });

/// **The one place this app names its palette.**
///
/// Before this existed, `AppTokens.dark` was written out in four places here -
/// twice for the roles below, once for the field radius, and once in
/// [spiritTheme]'s `extensions` - which meant a palette swap was four edits that
/// had to agree, and three-quarters of a swap renders a theme painting new
/// colours over old surfaces. Now it is one word.
///
/// **[AppTokens.profoundVerdant] since 2026-08-22.** The Stitch redesign's
/// palette, read out of the design system's own frontmatter, decided value by
/// value in `docs/stitch/OPEN_QUESTIONS.md` where it defined nothing, and
/// measured in `test/ui/tokens_test.dart` before it was wired to anything.
///
/// **The swap was one word only because two changes came first**: every slot in
/// [spiritTheme] moved off the four literals at the top of this file and onto a
/// role, and the palette stopped being named in four places. Before that,
/// flipping this would have repainted the buttons and the input well while the
/// scaffold, the cards and the text on them stayed behind.
///
/// [AppTokens.dark] is the palette this app shipped. It is kept, not deleted:
/// `test/ui/tokens_test.dart` still measures its contrast and its agreement with
/// those four constants, so what the app used to look like stays on the record.
const AppTokens _palette = AppTokens.profoundVerdant;

/// The action tiers this file paints with, read once rather than per button
/// theme.
///
/// [_palette] is a canonicalized `const` instance, so this reads the same object
/// every widget below the theme resolves. It is `final` rather than `const`
/// because a property access is not a constant expression, which is a Dart rule
/// about the expression and not about the value.
final AppActionRoles _action = _palette.colors.action;

/// The surface roles, read once for the same reason [_action] is.
final AppSurfaceRoles _surface = _palette.colors.surface;

/// The text roles, read once for the same reason [_action] is.
///
/// **The caption-versus-paragraph drift this file used to warn about is now
/// structural.** `_bodyGreen` was one constant serving both
/// [ColorScheme.onSurfaceVariant] and `bodyMedium`, and the comment on it said
/// the two coming apart is how a caption ends up a different green from the
/// paragraph beside it. Both now read [AppTextRoles.secondary], so they cannot.
final AppTextRoles _text = _palette.colors.text;

/// The status roles. Only `problem` is reached from here - it is the `error`
/// slot and the error border - because a `ThemeData` has no slot for the other
/// four and `AppStatusBadge` carries them instead.
final AppStatusRoles _status = _palette.colors.status;

/// One slot of the field outline every unmigrated `TextField` still reads.
///
/// `design.md` §2.3 v0.4: an input is a pill. `AppFieldWell` draws its own and
/// strips all six of these slots, so what this reaches is the sale path's two
/// fields and the legacy island - and they should not be the only rectangles
/// left in the app.
OutlineInputBorder _fieldBorder(Color colour, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(_palette.radius.md),
      borderSide: BorderSide(color: colour, width: width),
    );

/// Bouncing everywhere, on both platforms, and no Material overscroll glow -
/// `design.md` §2.4's last two motion rules.
///
/// It is a `ScrollBehavior` rather than a physics argument at each scrollable
/// because §2.4 says *everywhere*: a per-call-site physics is a rule 300 list
/// views have to remember, and the one that forgets is the one that reads as
/// Material. `MaterialScrollBehavior` is extended rather than replaced so
/// desktop scrollbars and the drag-device set stay exactly as they are.
///
/// **Nothing in the test suite mounts the app's own `MaterialApp`**, so this
/// class is proved at the class level and its effect on the running app is a
/// device check. A glow, like a ripple, exists only mid-gesture and cannot
/// appear in a screenshot.
final class SpiritScrollBehavior extends MaterialScrollBehavior {
  const SpiritScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// The one theme the app is built on.
///
/// [Brightness.dark] is not decoration. A `ThemeData` that names no brightness
/// is a **light** theme, so every text style not overridden below - and only
/// two are - resolved to near-black on the near-black [bgDark] scaffold. More
/// than seventy uses of `titleMedium`, `headlineSmall`, `bodySmall`,
/// `titleSmall`, and `titleLarge` across the app take that default, which is
/// how the first real run of this app found whole headings invisible on the
/// landing route while the plain body text beside them read fine.
///
/// **The [ColorScheme] is the reason the rest of this file exists.** Before it,
/// this theme named four brand colours and wired none of them in, so every
/// screen built after the multitenant split rendered Material's stock purple
/// for buttons, icons, links, and spinners while the login screen - which
/// styled itself through `PillInput` and `GlassCard` rather than through the
/// theme - rendered [accentGreen]. One app, two palettes, and the branded half
/// was the half that read from no theme at all. **The second palette is gone as
/// of §11 step 9**: sign-in is an `AppTextField`, an `AppButton` and a
/// `PageHeader` now, and the three widgets that carried it - `pill_input.dart`,
/// `pill_button.dart` and `glass_card.dart` - have no importer left. They are
/// still on disk only because the session that emptied them could not delete a
/// file; see `PLAN.md`.
///
/// The component themes below are the same argument continued: a `Card` or a
/// `FilledButton` that takes Material defaults is stock Material wearing this
/// app's colours, and the shapes are what make it look like one product.
///
/// `test/theme_test.dart` measures every style in this theme against both the
/// scaffold and the raised surface it is painted on, so the two cannot drift
/// apart again.
///
/// **[AppTokens] is registered here, and since `design.md` §11 step 3 the four
/// button themes and the two mint-facing `ColorScheme` slots read it
/// outright** - containers, labels, borders and press overlays, not just the
/// overlays step 2 wired. Step 1 defined the layer additively and wired
/// nothing; step 2 took the overlays; step 3 took the colours under them. What
/// is still on the old values below is named rather than left to be
/// discovered: ~~the input well is `bgMid` where §2.1 wants `surface.sunken`,~~
/// the card radius is 16 where §2.3 wants 12, ~~the input radius is 14 where it
/// wants 8,~~ and chips are stadium where §2.3 restricts the pill to buttons.
/// Those are steps 4 and 5, where each image diff has exactly one cause, and
/// `test/ui/tokens_test.dart` asserts every one of them as a divergence so the
/// step that closes one fails a test rather than passing quietly.
///
/// **The two input rows closed on 2026-08-15 and not by conforming to what they
/// said.** `design.md` v0.4 moved the well to `surface.field` `#1E3A2B` and the
/// radius to `radius.pill`, so the specification came to the theme rather than
/// the other way around. The remaining readers of `inputDecorationTheme` are the
/// sale path's two fields and the legacy island; every field in the migrated
/// tree goes through `AppFieldWell`, which strips this theme entirely.
///
/// **Step 2 is the ripple kill, and it is theme-level on purpose.** §2.4 says
/// to replace `InkWell` with an opacity-and-scale overlay, but there is exactly
/// **one** `InkWell` in the migrated tree - every other ripple comes from
/// Material's own button, chip, and tile implementations. `DESIGN-AUDIT.md` §6
/// decision 4 therefore split the work: the ripple dies here, in one file and
/// zero call sites, and the scale-0.97 `spring.snappy` press arrives inside
/// `AppButton` in step 3, at the moment a call site is already being rewritten.
/// Doing it per call site would touch every site twice.
///
/// **What that leaves, and it is worth being plain about it.** A control that
/// has not been migrated to `AppButton` has no ripple, no scale and no focus
/// ring - it has the overlay wash and nothing else, because a `ButtonStyle`
/// cannot express either of the other two. The press *feel* §2.4 asks for
/// arrives at a call site when that call site is migrated, not before, and
/// until then the theme is holding the line rather than delivering the design.
///
/// **The families are Profound Verdant's as of 2026-08-22**: Hanken Grotesk for
/// interface text, JetBrains Mono for figures and identifiers, repointed from
/// Roboto and Roboto Mono under `docs/stitch/OPEN_QUESTIONS.md` decision 20.
/// Both are bundled at the weights the roles read, because the exported design
/// links them from `fonts.googleapis.com` and a till cannot depend on that.
///
/// **This line is the fallback, not the mechanism.** Every role in
/// [AppTypeRoles.standard] names its own family, which is what reaches the
/// component themes below - a component theme's text style *replaces* the text
/// theme's rather than merging onto it, so naming a family only here would
/// leave `ListTile`, `Chip`, `InputDecoration` and the rest with none. This
/// catches whatever is built from neither: a bare `Text` under
/// `DefaultTextStyle`, or a Material default this file does not restyle.
///
/// **Unlike the 2026-08-16 change, this one moves images.** That one named the
/// face the screenshot harness was already injecting, so almost nothing
/// shifted. This one changes the face itself, in the app *and* in the harness,
/// which no longer injects anything - so every string in `screenshots/` is
/// redrawn in a face the captures have never shown.
///
/// **What is still not delivered is a *reader* for `mono`.**
/// `AppTypeRoles.mono` has zero call sites: the role is defined, has metrics,
/// has a face, and no screen applies it - so §2.2's "record identifiers are
/// monospace" is still true of nothing. Recorded in `PLAN.md`; the sweep is a
/// chunk of its own, because which strings are identifiers is a judgement per
/// screen rather than a grep.
final ThemeData spiritTheme = ThemeData(
  brightness: Brightness.dark,
  // The fallback face. Every type role names this family itself; see the note
  // above for why naming it in both places is not redundant.
  fontFamily: AppTypeRoles.interfaceFamily,
  scaffoldBackgroundColor: _surface.base,
  extensions: const <ThemeExtension<dynamic>>[_palette],
  // `design.md` §2.4: no ink ripples. One line reaches every button,
  // `ListTile`, `ChoiceChip`, `IconButton` and `SegmentedButton` in the app,
  // because `InkResponse` falls back to `ThemeData.splashFactory` and the
  // Material 3 button defaults delegate to it explicitly.
  //
  // **This holds only while `useMaterial3` is true**, which is why the line
  // below states it rather than relying on the SDK default: the Material 2
  // paths in `outlined_button.dart` and `text_button.dart` hardcode
  // `InkRipple.splashFactory`, so flipping that flag would silently restore
  // ripples on two of the four tiers. A test asserts both.
  useMaterial3: true,
  splashFactory: NoSplash.splashFactory,
  colorScheme: ColorScheme.dark(
    primary: _action.primary.container,
    // Dark ink on a bright accent, which is what the login screen's primary
    // button already does. White on `accentGreen` fails AA outright.
    //
    // **`#0A0F0C` since step 3, and it used to be `bgDark`.** This is one of
    // the two divergences `test/ui/tokens_test.dart` asserted on purpose from
    // step 1 onwards: §2.1's action table names a label darker than the page
    // for the primary tier, and the theme had the page colour. The assertion
    // is now an agreement, in the same change, which is what those rows were
    // written for.
    onPrimary: _action.primary.label,
    primaryContainer: _surface.field,
    onPrimaryContainer: _action.primary.container,
    secondary: _action.primary.container,
    // `secondary` is the same mint, so what sits on it is the same ink.
    onSecondary: _action.primary.label,
    secondaryContainer: _surface.field,
    onSecondaryContainer: _text.secondary,
    error: _status.problem.fg,
    onError: _surface.base,
    // Cards, dialogs, and sheets paint on this rather than on the scaffold.
    surface: _surface.raised,
    onSurface: _text.primary,
    onSurfaceVariant: _text.secondary,
    outline: _surface.borderSubtle,
    outlineVariant: _surface.borderSubtle,
  ),
  textTheme: TextTheme(
    headlineLarge: TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      color: _text.primary,
    ),
    bodyMedium: TextStyle(fontSize: 16, color: _text.secondary),
    // Every button label. Left without a colour or a family on purpose: it
    // merges onto the default style, so it inherits both and cannot drift
    // into a different face from the text beside it.
    labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: _surface.base,
    foregroundColor: _text.primary,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
  ),
  cardTheme: CardThemeData(
    color: _surface.raised,
    elevation: 0,
    margin: const EdgeInsets.symmetric(vertical: 6),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_palette.radius.md),
      side: BorderSide(color: _surface.borderSubtle),
    ),
  ),
  // Stadium buttons throughout, because the login screen's are stadium and it
  // is the one screen nobody has asked to change.
  //
  // Each of the four carries the colours of the §2.1 tier it stands for:
  // filled and elevated are `action.primary`, the outlined button is
  // `action.secondary`, and the text button is `action.tertiary`.
  // `action.destructive` still has no Material theme to attach to and lives in
  // `AppButton` alone, which is correct rather than a gap: there is no stock
  // widget for it to be the theme of.
  //
  // **Step 3 repointed the labels these were still painting the old way**, so
  // an unmigrated `OutlinedButton` and an `AppButton` in `secondary` are the
  // same colour on the same screen while the migration runs. Two of the three
  // repoints are the divergences `test/ui/tokens_test.dart` was asserting on
  // purpose - the outlined label off mint, and the primary label to `#0A0F0C`
  // through `colorScheme.onPrimary` above. The third, the outlined border from
  // `mutedGreen` (`#1E3A2B`) to `action.secondary.border` (`#2C5340`), was not
  // on that list and is taken here deliberately: the two implementations
  // disagreeing about the border of the same tier is precisely the drift the
  // token layer exists to prevent, and it would have been invisible in review
  // because each half is individually defensible.
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: _action.primary.container,
      foregroundColor: _action.primary.label,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_palette.radius.md),
      ),
    ).copyWith(overlayColor: _pressOverlay(_action.primary)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: _action.primary.container,
      foregroundColor: _action.primary.label,
      elevation: 0,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_palette.radius.md),
      ),
    ).copyWith(overlayColor: _pressOverlay(_action.primary)),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: _action.secondary.label,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      side: BorderSide(color: _action.secondary.border!),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_palette.radius.md),
      ),
    ).copyWith(overlayColor: _pressOverlay(_action.secondary)),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: _action.tertiary.label,
    ).copyWith(overlayColor: _pressOverlay(_action.tertiary)),
  ),
  // **`design.md` v0.4, and this is the half `AppTextField` cannot reach.**
  // Every field in the migrated tree draws itself through `AppFieldWell`, which
  // strips this theme entirely; what still reads it is the sale path's two
  // unmigrated `TextField`s and the legacy island. Leaving it on `bgMid` at
  // radius 14 would have meant the one screen a cashier uses most keeping two
  // dark rectangles while every other field in the app became a pill - which is
  // the divergence the token layer exists to prevent, and the product owner
  // asked for *all* the input fields.
  //
  // **`hintStyle` had to move or it would have disappeared.** It was
  // `mutedGreen`, which is `#1E3A2B`, which is now the fill.
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: _surface.field,
    hintStyle: TextStyle(color: _text.secondary),
    labelStyle: TextStyle(color: _text.secondary),
    border: _fieldBorder(_surface.borderStrong),
    enabledBorder: _fieldBorder(_surface.borderStrong),
    focusedBorder: _fieldBorder(
      _action.focusRing.color,
      width: _action.focusRing.width,
    ),
    errorBorder: _fieldBorder(_status.problem.fg),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: _surface.raised,
    selectedColor: _surface.field,
    side: BorderSide(color: _surface.borderSubtle),
    labelStyle: TextStyle(color: _text.secondary),
    secondaryLabelStyle: TextStyle(color: _action.primary.container),
    checkmarkColor: _action.primary.container,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_palette.radius.sm),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: _surface.raised,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_palette.radius.lg),
    ),
  ),
  // Named now rather than by the till chunk that needs it, so the cart sheet
  // and every other sheet cannot disagree about what a sheet looks like.
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: _surface.raised,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(_palette.radius.lg),
      ),
    ),
  ),
  dividerTheme: DividerThemeData(
    color: _surface.borderSubtle,
    space: 1,
    thickness: 1,
  ),
  listTileTheme: ListTileThemeData(
    iconColor: _action.primary.container,
    textColor: _text.primary,
    subtitleTextStyle: TextStyle(color: _text.secondary, fontSize: 13),
  ),
  iconTheme: IconThemeData(color: _action.primary.container),
  // The splash screen's spinner was stock Material purple on a green-black
  // ground, which is the whole problem this file now fixes in miniature.
  progressIndicatorTheme: ProgressIndicatorThemeData(
    color: _action.primary.container,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: _surface.field,
    contentTextStyle: TextStyle(color: _text.primary),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_palette.radius.md),
    ),
  ),
  // **Step 9 pointed all three of these at §2.1 and none of them moved much**,
  // which is the point: a ticked box is the primary action tier's container with
  // the primary tier's label on it, and an unticked one is an input, which §2.1
  // gives `border.strong`. Before this the tick was `bgDark` - the *page*
  // colour, the same divergence `onPrimary` carried until step 3 - and the
  // outline was `border.subtle`, which is the hairline row.
  //
  // **What this does not fix is recorded rather than hidden.** `border.strong`
  // is 1.97:1 on `surface.base`, and an unticked box's outline is the only thing
  // saying there is a box - so under §9's own 2026-08-12 reading it carries
  // meaning and owes 3:1. No §2.1 border role clears that, and `claude.md`
  // forbids inventing one. It is an open decision in `PLAN.md`.
  checkboxTheme: CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? _action.primary.container
          : null,
    ),
    checkColor: WidgetStatePropertyAll(_action.primary.label),
    side: BorderSide(color: _action.secondary.border!, width: 2),
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected) ? _surface.base : null,
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? _action.primary.container
          : null,
    ),
  ),
);
