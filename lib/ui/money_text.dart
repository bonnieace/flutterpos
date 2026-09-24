/// Money as a person reads it on screen.
///
/// **No `.00` on a whole amount**, at the developer's direction on
/// 2026-09-23: `1250` rather than `1250.00`. An amount with cents keeps both
/// figures - `1250.50`, never `1250.5` - because a single decimal reads as a
/// different number.
///
/// **Screens only.** The printed receipt keeps its fixed two places, which is
/// what lines its columns up on the roll.
library;

import 'package:intl/intl.dart';

/// Exact minor units, ungrouped: `1250`, `1250.50`, `-3.05`.
String moneyTextOfMinor(int minorUnits) {
  if (minorUnits % 100 == 0) return '${minorUnits ~/ 100}';
  final sign = minorUnits < 0 ? '-' : '';
  final magnitude = minorUnits.abs();
  final cents = (magnitude % 100).toString().padLeft(2, '0');
  return '$sign${magnitude ~/ 100}.$cents';
}

/// A major-unit amount, ungrouped. Rounded to the cent first, so a double
/// that is a hair off a whole amount still reads as one.
String moneyText(num amount) => moneyTextOfMinor((amount * 100).round());

/// Exact minor units, grouped in thousands: `17,000`, `17,000.50`.
String moneyTextGroupedOfMinor(int minorUnits) => minorUnits % 100 == 0
    ? _whole.format(minorUnits ~/ 100)
    : _cents.format(minorUnits / 100);

/// A major-unit amount, grouped in thousands.
String moneyTextGrouped(num amount) =>
    moneyTextGroupedOfMinor((amount * 100).round());

final NumberFormat _whole = NumberFormat('#,##0');
final NumberFormat _cents = NumberFormat('#,##0.00');
