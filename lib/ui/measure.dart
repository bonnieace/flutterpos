/// One thing: how wide a string is when this app draws it.
///
/// **It exists because a column cannot be given the width its content needs
/// without asking how wide that content is.** `design.md` §4.3 specifies what a
/// record list *becomes* at each band and says nothing about how a table divides
/// its row, so until 2026-08-15 `RecordList` divided it with three constants
/// chosen against one screen - and `PLAN.md` carried four observations about
/// what those constants do to the other eleven. The answer that removes the
/// constants rather than retuning them is to measure, and measuring text is the
/// one primitive the three components involved all need.
///
/// **It is a measurement, not an estimate.** A character count is the obvious
/// cheap alternative and it is wrong in the one direction that matters: `WWW` and
/// `iii` are the same three characters and not the same width, and a column
/// sized from the count truncates exactly the values a person came to compare.
/// [TextPainter] lays the string out with the same font, weight and scale the
/// screen will use, so what comes back is the width the glyphs will occupy.
///
/// **The text scale is an argument rather than a default**, because it is the
/// half of this that §9 reaches: a person reading at 200% has strings twice as
/// wide, and a column measured at 100% would ellipsise every one of them. Every
/// caller passes `MediaQuery.textScalerOf(context)`.
library;

import 'package:flutter/widgets.dart';

/// How wide [text] is when painted in [style], on one unwrapped line.
///
/// **One line, deliberately.** The number a column wants is "the width at which
/// this value does not wrap", and a measurement that allowed wrapping would
/// answer with whatever width it was given. A caller that permits its text two
/// lines - an identity title is the only one in this app - halves the answer
/// itself, at the call site, where the permission lives.
///
/// **[ambient] is not optional decoration and leaving it out is a real error**,
/// which this file learned by shipping the mistake. A `Text` whose style has
/// `inherit: true` - every style in the token layer does - is painted in the
/// enclosing `DefaultTextStyle` **merged with** its own, and this app's
/// `ThemeData` carries Material's `letterSpacing: 0.25` on the roles the token
/// layer does not set one for. That is a quarter of a pixel per character,
/// which is nothing on a word and is 4.25 pixels on `Cancel invitation` - and a
/// set of four buttons measured without it was handed exactly the width its
/// labels needed and wrapped anyway. Pass `DefaultTextStyle.of(context).style`.
double measureTextWidth(
  String text,
  TextStyle style, {
  TextScaler textScaler = TextScaler.noScaling,
  TextStyle? ambient,
  TextDirection textDirection = TextDirection.ltr,
}) {
  if (text.isEmpty) return 0;
  final painter = TextPainter(
    // `merge` returns the argument untouched where it does not inherit, so this
    // is the same rule `Text` itself applies rather than a second one.
    text: TextSpan(text: text, style: ambient?.merge(style) ?? style),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  // A `TextPainter` holds an engine paragraph. Nothing here retains one, and
  // this runs once per column per build, so releasing it immediately is the
  // difference between a measurement and a leak.
  painter.dispose();
  return width;
}
