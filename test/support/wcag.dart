/// The contrast arithmetic behind `design.md` §9, in one place.
///
/// Two test files police the same accessibility contract - `theme_test.dart`
/// over the `TextTheme` the app renders today and `ui/tokens_test.dart` over
/// the token layer that will replace it - and a ratio computed two ways is a
/// ratio that eventually disagrees with itself about whether a colour passes.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
///
/// `Color.computeLuminance` is already the WCAG relative luminance, so this is
/// only the ratio around it. Both colours must be opaque: a translucent one
/// composites against whatever is behind it and its ratio is not a property of
/// the pair.
double contrastRatio(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// The WCAG AA threshold that applies to [style], per `design.md` §9.
///
/// Large text is allowed less contrast because it is easier to read at the same
/// ratio; everything else must reach 4.5:1.
double requiredContrastFor(TextStyle style) {
  final size = style.fontSize ?? 14;
  final bold =
      (style.fontWeight?.value ?? FontWeight.normal.value) >=
      FontWeight.w700.value;
  final isLarge = size >= 24 || (bold && size >= 18.67);
  return isLarge ? largeTextContrast : bodyTextContrast;
}

/// §9's body-text floor.
const double bodyTextContrast = 4.5;

/// §9's floor for large text and UI boundaries.
const double largeTextContrast = 3.0;
