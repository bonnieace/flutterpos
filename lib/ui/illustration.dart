/// A sourced illustration drawn in the theme's colours rather than its own.
///
/// **The problem this solves is the one that killed the last sourced asset.**
/// `states.dart` records it: the candidate for §6.4's asset 6 "came back as
/// seven beiges and oranges on a near-black green page", was 252 colours, "so
/// it cannot be tinted at all", and the call on 2026-08-16 was to draw the mark
/// natively instead. `pubspec.yaml` states the same bar for the Lottie set -
/// "a multi-coloured file is refused, which is the whole of what makes an
/// authored asset survive a palette change."
///
/// **unDraw files are multi-colour and still pass that bar, because they are
/// not drawn in the colours they ship with.** [_UndrawPalette] replaces every
/// colour at render time through `flutter_svg`'s `ColorMapper` - the accent
/// with the theme's accent, and everything else with a theme tone chosen by
/// luminance. Nothing in `assets/` decides what anything looks like, so a
/// palette change still reaches the artwork and the same file is correct in
/// both themes.
///
/// **The value order inverts.** unDraw draws for a white page: its darks are
/// line work and its lights are the body of an object. On `surface.base` that
/// has to turn over or the artwork reads as a hole punched in the page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'tokens.dart';

/// An illustration from `assets/illustrations/`, tinted from the theme.
final class AppIllustration extends StatelessWidget {
  const AppIllustration({
    super.key,
    required this.asset,
    required this.size,
    this.semanticLabel,
  });

  /// File name inside `assets/illustrations/`, extension included.
  final String asset;

  /// The square the drawing fits inside, in logical pixels.
  ///
  /// Passed rather than defaulted: an illustration is sized by the state that
  /// hosts it, and this widget decides nothing about layout.
  final double size;

  /// Null where the surrounding copy already says what the picture says, which
  /// on an empty state it always does - the title is the statement and the
  /// drawing is decoration. Hard rule 4: never let a picture be the only
  /// carrier of a fact.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return SvgPicture.asset(
      'assets/illustrations/$asset',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      colorMapper: _UndrawPalette(tokens.colors),
    );
  }
}

/// unDraw's palette, remapped onto the theme's own value ramp.
///
/// **The first version of this matched five known hexes and was wrong.** An
/// audit of the thirteen files in `assets/illustrations/` found only one built
/// from unDraw's documented accent-plus-four-neutrals; the other twelve carry
/// skin tones, hair, clothing and extra greys - thirty-one distinct colours
/// across the set. A switch over known hexes would have dropped every one of
/// them onto a single fallback and flattened the drawings.
///
/// **So nothing is matched by hex except the accent.** Every other colour is
/// placed by its relative luminance onto [_ramp], which is the theme's own
/// tones ordered lightest to darkest. unDraw draws for a white page, so the
/// mapping inverts: near-black line work becomes the lightest tone and white
/// becomes the deepest. The drawing keeps its internal contrast order and
/// arrives monochrome in the page's own colours.
///
/// **The ramp sorts itself.** Its stops are token roles, and a role's value is
/// whatever the active theme says it is - so the order is computed rather than
/// assumed, and the same mapper is correct on a light theme, where the
/// inversion simply stops inverting.
@immutable
final class _UndrawPalette extends ColorMapper {
  const _UndrawPalette(this.colors);

  final AppColorRoles colors;

  /// unDraw's accent - the one colour the site's picker sets, and the only one
  /// that carries intent rather than form. It becomes the app's accent.
  ///
  /// Matched exactly. Widening this to "any saturated colour" was considered
  /// and rejected: unDraw's skin tones are saturated pinks, and they would have
  /// come through mint.
  static const int _accent = 0xFF6C63FF;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    if (color.a == 0) return color;
    if (color.toARGB32() == _accent) return colors.action.primary.container;
    final ramp = _ramp;
    // Inverted: luminance 0 takes the lightest stop. `clamp` guards the
    // luminance == 1 edge, which would otherwise index past the end.
    final index = (color.computeLuminance() * ramp.length).floor().clamp(
      0,
      ramp.length - 1,
    );
    return ramp[index].withValues(alpha: color.a);
  }

  /// The theme's tones, lightest first.
  ///
  /// Sorted at use rather than written in order, because these are roles and a
  /// role's value belongs to the theme. Seven stops: enough that a drawing's
  /// planes stay apart, few enough that each step is visible.
  List<Color> get _ramp {
    final stops = <Color>[
      colors.text.primary,
      colors.text.secondary,
      colors.text.tertiary,
      colors.surface.borderStrong,
      colors.surface.overlay,
      colors.surface.raised,
      colors.surface.sunken,
    ]..sort((a, b) => b.computeLuminance().compareTo(a.computeLuminance()));
    return stops;
  }

  @override
  bool operator ==(Object other) =>
      other is _UndrawPalette && other.colors == colors;

  @override
  int get hashCode => colors.hashCode;
}
