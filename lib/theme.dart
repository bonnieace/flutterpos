import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Dark theme colors
const Color bgDark = Color(0xFF0D1F16);
const Color bgMid = Color(0xFF132A1F);
const Color accentGreen = Color(0xFF45F28D);
const Color mutedGreen = Color(0xFF1E3A2B);

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
/// `test/theme_test.dart` measures every style in this theme against the
/// scaffold it is painted on, so the two cannot drift apart again.
final ThemeData spiritTheme = ThemeData(
  brightness: Brightness.dark,
  fontFamily: 'Inter',
  scaffoldBackgroundColor: bgDark,
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    bodyMedium: TextStyle(
      fontSize: 16,
      color: Color(0xFFB8D6C5),
    ),
  ),
);
