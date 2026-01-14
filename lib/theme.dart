import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Dark theme colors
const Color bgDark = Color(0xFF0D1F16);
const Color bgMid = Color(0xFF132A1F);
const Color accentGreen = Color(0xFF45F28D);
const Color mutedGreen = Color(0xFF1E3A2B);

final ThemeData spiritTheme = ThemeData(
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
