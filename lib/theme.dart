import 'package:flutter/material.dart';

import 'ui/tokens.dart';

// Dark theme colors
const Color bgDark = Color(0xFF0D1F16);
const Color bgMid = Color(0xFF132A1F);
const Color accentGreen = Color(0xFF45F28D);
const Color mutedGreen = Color(0xFF1E3A2B);

/// Body text on either of the two grounds above.
///
/// Named because it is the [ColorScheme.onSurfaceVariant] as well as the
/// `bodyMedium` colour, and the two drifting apart is how a caption ends up a
/// different green from the paragraph beside it.
const Color _bodyGreen = Color(0xFFB8D6C5);

/// A refusal. Reserved, and never used for structure.
const Color _criticalRed = Color(0xFFFF5C6C);

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

/// The action tiers this file paints with, read once rather than per button
/// theme.
///
/// `AppTokens.dark` is a canonicalized `const` instance, so this reads the same
/// object every widget below the theme resolves. It is `final` rather than
/// `const` because a property access is not a constant expression, which is a
/// Dart rule about the expression and not about the value.
final AppActionRoles _action = AppTokens.dark.colors.action;

/// The surface roles, read once for the same reason [_action] is.
final AppSurfaceRoles _surface = AppTokens.dark.colors.surface;

/// One slot of the field outline every unmigrated `TextField` still reads.
///
/// `design.md` §2.3 v0.4: an input is a pill. `AppFieldWell` draws its own and
/// strips all six of these slots, so what this reaches is the sale path's two
/// fields and the legacy island - and they should not be the only rectangles
/// left in the app.
OutlineInputBorder _fieldBorder(Color colour, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.dark.radius.pill),
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
/// ~~**No `fontFamily` is named here, deliberately.**~~ **Named as of 2026-08-16,
/// and the fonts are bundled**, which is `design.md` **v0.7** and the close of the
/// oldest untrue sentence in this file.
///
/// The note this replaces was honest about the symptom and wrong about the
/// remedy: it said naming nothing was "the honest version of what already
/// happens", and left an app whose §2.2 claims - one family, and monospace for
/// record IDs - were true of no rendering anywhere. `fonts/` now holds Roboto at
/// four faces under its Apache 2.0 licence, `pubspec.yaml` declares them, and
/// this names the family.
///
/// **Every screenshot in `screenshots/` was already showing this.**
/// `tool/screenshots/harness.dart` injects Roboto itself, precisely because a
/// test face renders every glyph as a filled box - so the captures have always
/// been of a more branded app than the one that shipped. Naming the family here
/// makes the app match its own pictures rather than the other way round, and is
/// why this change moves almost no image.
///
/// **`mono` names Roboto Mono as of the same day**, and the file is bundled -
/// so `AppTypeRoles.mono` is the one role in the twelve that names a family,
/// and it is the only one whose family is load-bearing rather than inherited.
///
/// **What is still not delivered is a *reader*.** `AppTypeRoles.mono` has zero
/// call sites: the role is defined, has metrics, now has a face, and no screen
/// applies it - so §2.2's "record identifiers are monospace" is still true of
/// nothing. Bundling the font made the role possible rather than applied.
/// Recorded in `PLAN.md`; the sweep is a chunk of its own, because which
/// strings are identifiers is a judgement per screen rather than a grep.
final ThemeData spiritTheme = ThemeData(
  brightness: Brightness.dark,
  // §2.2's "one family". See the note above for why this was absent for so long
  // and what is still missing.
  fontFamily: 'Roboto',
  scaffoldBackgroundColor: bgDark,
  extensions: const <ThemeExtension<dynamic>>[AppTokens.dark],
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
    primary: accentGreen,
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
    primaryContainer: mutedGreen,
    onPrimaryContainer: accentGreen,
    secondary: accentGreen,
    // `secondary` is the same mint, so what sits on it is the same ink.
    onSecondary: _action.primary.label,
    secondaryContainer: mutedGreen,
    onSecondaryContainer: _bodyGreen,
    error: _criticalRed,
    onError: bgDark,
    // Cards, dialogs, and sheets paint on this rather than on the scaffold.
    surface: bgMid,
    onSurface: Colors.white,
    onSurfaceVariant: _bodyGreen,
    outline: mutedGreen,
    outlineVariant: mutedGreen,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    bodyMedium: TextStyle(fontSize: 16, color: _bodyGreen),
    // Every button label. Left without a colour or a family on purpose: it
    // merges onto the default style, so it inherits both and cannot drift
    // into a different face from the text beside it.
    labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: bgDark,
    foregroundColor: Colors.white,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
  ),
  cardTheme: CardThemeData(
    color: bgMid,
    elevation: 0,
    margin: const EdgeInsets.symmetric(vertical: 6),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: mutedGreen),
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
      shape: const StadiumBorder(),
    ).copyWith(overlayColor: _pressOverlay(_action.primary)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: _action.primary.container,
      foregroundColor: _action.primary.label,
      elevation: 0,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      shape: const StadiumBorder(),
    ).copyWith(overlayColor: _pressOverlay(_action.primary)),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: _action.secondary.label,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      side: BorderSide(color: _action.secondary.border!),
      shape: const StadiumBorder(),
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
    hintStyle: const TextStyle(color: _bodyGreen),
    labelStyle: const TextStyle(color: _bodyGreen),
    border: _fieldBorder(_surface.borderStrong),
    enabledBorder: _fieldBorder(_surface.borderStrong),
    focusedBorder: _fieldBorder(
      _action.focusRing.color,
      width: _action.focusRing.width,
    ),
    errorBorder: _fieldBorder(_criticalRed),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: bgMid,
    selectedColor: mutedGreen,
    side: const BorderSide(color: mutedGreen),
    labelStyle: const TextStyle(color: _bodyGreen),
    secondaryLabelStyle: const TextStyle(color: accentGreen),
    checkmarkColor: accentGreen,
    shape: const StadiumBorder(),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: bgMid,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  // Named now rather than by the till chunk that needs it, so the cart sheet
  // and every other sheet cannot disagree about what a sheet looks like.
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: bgMid,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
  ),
  dividerTheme: const DividerThemeData(color: mutedGreen, space: 1, thickness: 1),
  listTileTheme: const ListTileThemeData(
    iconColor: accentGreen,
    textColor: Colors.white,
    subtitleTextStyle: TextStyle(color: _bodyGreen, fontSize: 13),
  ),
  iconTheme: const IconThemeData(color: accentGreen),
  // The splash screen's spinner was stock Material purple on a green-black
  // ground, which is the whole problem this file now fixes in miniature.
  progressIndicatorTheme: const ProgressIndicatorThemeData(color: accentGreen),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: mutedGreen,
    contentTextStyle: const TextStyle(color: Colors.white),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      (states) => states.contains(WidgetState.selected) ? bgDark : null,
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected) ? accentGreen : null,
    ),
  ),
);
