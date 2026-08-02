import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
///
/// `Color.computeLuminance` is already the WCAG relative luminance, so this is
/// only the ratio around it.
double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// The WCAG AA threshold that applies to [style].
///
/// Large text is allowed less contrast because it is easier to read at the
/// same ratio; everything else must reach 4.5:1.
double _requiredContrast(TextStyle style) {
  final size = style.fontSize ?? 14;
  final bold = (style.fontWeight?.value ?? FontWeight.normal.value) >=
      FontWeight.w700.value;
  final isLarge = size >= 24 || (bold && size >= 18.67);
  return isLarge ? 3.0 : 4.5;
}

void main() {
  // The whole point of these: the app paints on a near-black scaffold, and a
  // theme that forgets to say so is a light theme whose text is near-black
  // too. That shipped, and a real run on an Android device was the first thing
  // to notice - the landing route's headings were there and unreadable.
  group('every text style is legible on the scaffold it is painted on', () {
    final styles = <String, TextStyle?>{
      'displayLarge': spiritTheme.textTheme.displayLarge,
      'displayMedium': spiritTheme.textTheme.displayMedium,
      'displaySmall': spiritTheme.textTheme.displaySmall,
      'headlineLarge': spiritTheme.textTheme.headlineLarge,
      'headlineMedium': spiritTheme.textTheme.headlineMedium,
      'headlineSmall': spiritTheme.textTheme.headlineSmall,
      'titleLarge': spiritTheme.textTheme.titleLarge,
      'titleMedium': spiritTheme.textTheme.titleMedium,
      'titleSmall': spiritTheme.textTheme.titleSmall,
      'bodyLarge': spiritTheme.textTheme.bodyLarge,
      'bodyMedium': spiritTheme.textTheme.bodyMedium,
      'bodySmall': spiritTheme.textTheme.bodySmall,
      'labelLarge': spiritTheme.textTheme.labelLarge,
      'labelMedium': spiritTheme.textTheme.labelMedium,
      'labelSmall': spiritTheme.textTheme.labelSmall,
    };

    test('the theme resolves a colour for every one of them', () {
      // A null colour is not a pass. It would mean the style falls through to
      // something this test never measured.
      for (final entry in styles.entries) {
        expect(entry.value, isNotNull, reason: '${entry.key} is missing');
        expect(
          entry.value!.color,
          isNotNull,
          reason: '${entry.key} resolves no colour',
        );
      }
    });

    test('each one clears WCAG AA against the scaffold', () {
      for (final entry in styles.entries) {
        final style = entry.value!;
        final required = _requiredContrast(style);
        expect(
          _contrast(style.color!, spiritTheme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(required),
          reason:
              '${entry.key} is unreadable on the scaffold: it needs $required:1',
        );
      }
    });

    test('and against the raised surface as well', () {
      // Cards, dialogs, and sheets paint on this rather than the scaffold, so
      // a style that only clears the darker background is not enough.
      for (final entry in styles.entries) {
        expect(
          _contrast(entry.value!.color!, spiritTheme.colorScheme.surface),
          greaterThanOrEqualTo(_requiredContrast(entry.value!)),
          reason: '${entry.key} is unreadable on a card or dialog',
        );
      }
    });
  });

  test('the theme is a dark one, because the scaffold is', () {
    // Stated directly as well as measured. The measurements above would also
    // pass if somebody hand-coloured fifteen styles; this is the reason they
    // do not have to.
    expect(spiritTheme.brightness, Brightness.dark);
    expect(spiritTheme.colorScheme.brightness, Brightness.dark);
    expect(spiritTheme.scaffoldBackgroundColor.computeLuminance(), lessThan(0.1));
  });
}
