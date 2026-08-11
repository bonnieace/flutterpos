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
/// styles itself through `PillInput` and `GlassCard` rather than through the
/// theme - rendered [accentGreen]. One app, two palettes, and the branded half
/// was the half that read from no theme at all.
///
/// The component themes below are the same argument continued: a `Card` or a
/// `FilledButton` that takes Material defaults is stock Material wearing this
/// app's colours, and the shapes are what make it look like one product.
///
/// `test/theme_test.dart` measures every style in this theme against both the
/// scaffold and the raised surface it is painted on, so the two cannot drift
/// apart again.
///
/// **[AppTokens] is registered here, and since `design.md` §11 step 2 exactly
/// one thing reads it: the press overlay on the four button themes.** Step 1
/// defined the layer additively and wired nothing, so every other value below
/// still decides what the app renders. The rewiring - the input well moving to
/// `surface.sunken`, the outlined button's label off mint, the card radius from
/// 16 to 12 - belongs to steps 3 to 5, where each image diff has exactly one
/// cause.
///
/// **Step 2 is the ripple kill, and it is theme-level on purpose.** §2.4 says
/// to replace `InkWell` with an opacity-and-scale overlay, but there is exactly
/// **one** `InkWell` in the migrated tree - every other ripple comes from
/// Material's own button, chip, and tile implementations. `DESIGN-AUDIT.md` §6
/// decision 4 therefore split the work: the ripple dies here, in one file and
/// zero call sites, and the scale-0.97 `spring.snappy` press arrives inside
/// `AppButton` in step 3, at the moment every call site is already being
/// rewritten. Doing it per call site now would touch ~40 sites twice.
///
/// **No `fontFamily` is named here, deliberately.** This theme asked for
/// `Inter` for a long time and no `Inter` was ever bundled - `pubspec.yaml`
/// declares no fonts and the repository holds no font file - so every screen
/// silently rendered in the platform's default face while the code claimed
/// otherwise. Naming nothing is the honest version of what already happens. To
/// actually get `Inter`, add the files under `assets/fonts/`, declare them in
/// `pubspec.yaml`, and name the family again here.
final ThemeData spiritTheme = ThemeData(
  brightness: Brightness.dark,
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
  colorScheme: const ColorScheme.dark(
    primary: accentGreen,
    // Dark ink on a bright accent, which is what the login screen's primary
    // button already does. White on `accentGreen` fails AA outright.
    onPrimary: bgDark,
    primaryContainer: mutedGreen,
    onPrimaryContainer: accentGreen,
    secondary: accentGreen,
    onSecondary: bgDark,
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
  // Each of the four carries the overlay of the §2.1 tier it stands for:
  // filled and elevated are `action.primary`, the outlined button is
  // `action.secondary`, and the text button is `action.tertiary`.
  // `action.destructive` has no Material theme to attach to and arrives with
  // `AppButton` in step 3, which is also where the outlined button's label
  // stops being mint - the overlay moved here, the label did not, and
  // `test/ui/tokens_test.dart` asserts that divergence until step 3 closes it.
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: accentGreen,
      foregroundColor: bgDark,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      shape: const StadiumBorder(),
    ).copyWith(overlayColor: _pressOverlay(_action.primary)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: accentGreen,
      foregroundColor: bgDark,
      elevation: 0,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      shape: const StadiumBorder(),
    ).copyWith(overlayColor: _pressOverlay(_action.primary)),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: accentGreen,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      side: const BorderSide(color: mutedGreen),
      shape: const StadiumBorder(),
    ).copyWith(overlayColor: _pressOverlay(_action.secondary)),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: accentGreen,
    ).copyWith(overlayColor: _pressOverlay(_action.tertiary)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: bgMid,
    hintStyle: const TextStyle(color: mutedGreen),
    labelStyle: const TextStyle(color: _bodyGreen),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: mutedGreen),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: mutedGreen),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: accentGreen, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _criticalRed),
    ),
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
  checkboxTheme: CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected) ? accentGreen : null,
    ),
    checkColor: const WidgetStatePropertyAll(bgDark),
    side: const BorderSide(color: mutedGreen, width: 2),
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
