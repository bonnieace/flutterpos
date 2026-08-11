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
/// **[AppTokens] is registered here and read by nothing yet.** That is
/// `design.md` §11 step 1: the token layer is defined additively, so every
/// value below still decides what the app renders and an empty screenshot diff
/// is the proof. The rewiring - the input well moving to `surface.sunken`, the
/// outlined button's label off mint, the card radius from 16 to 12 - belongs to
/// steps 2 to 5, where each image diff has exactly one cause.
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
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: accentGreen,
      foregroundColor: bgDark,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      shape: const StadiumBorder(),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: accentGreen,
      foregroundColor: bgDark,
      elevation: 0,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      shape: const StadiumBorder(),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: accentGreen,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      side: const BorderSide(color: mutedGreen),
      shape: const StadiumBorder(),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: accentGreen,
    ),
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
