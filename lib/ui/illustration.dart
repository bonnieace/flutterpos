/// Vector scenes painted with material colors and authored accent details.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'tokens.dart';

/// An illustration from `assets/illustrations/`, painted from theme tokens.
final class AppIllustration extends StatelessWidget {
  /// Shared scene size: large enough for artwork detail on a narrow screen.
  static const double sceneSize = 168;

  const AppIllustration({
    super.key,
    required this.asset,
    required this.size,
    this.semanticLabel,
  });

  /// File name inside `assets/illustrations/`, extension included.
  final String asset;

  /// The square the drawing fits inside, in logical pixels.
  final double size;

  /// Omit for decoration when surrounding copy already explains the scene.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return SizedBox.square(
      dimension: size,
      child: SvgPicture.asset(
        'assets/illustrations/$asset',
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticsLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
        colorMapper: _IllustrationPalette(tokens.colors.illustration, asset),
      ),
    );
  }
}

/// Source materials retain their character instead of falling into a surface
/// ramp. Authored `--paint-*` SVG IDs distinguish details with the same source
/// color: a plant, a sleeve and a document can receive different pigments.
@immutable
final class _IllustrationPalette extends ColorMapper {
  const _IllustrationPalette(this.palette, this.asset);

  final AppIllustrationRoles palette;
  final String asset;

  AppIllustrationPaint get _accent => switch (asset) {
    'calendar.svg' ||
    'schedule.svg' ||
    'file-search.svg' => AppIllustrationPaint.sky,
    'my-files.svg' => AppIllustrationPaint.violet,
    'empty-cart.svg' => AppIllustrationPaint.amber,
    _ => AppIllustrationPaint.jade,
  };

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    if (color.a == 0) return color;
    final marker = id?.split('--paint-');
    if (marker != null && marker.length > 1) {
      final name = marker.last;
      for (final paint in AppIllustrationPaint.values) {
        if (paint.name == name) {
          return palette[paint].withValues(alpha: color.a);
        }
      }
    }

    final paint = switch (color.withValues(alpha: 1).toARGB32()) {
      0xFF6C63FF => _accent,
      0xFF010102 || 0xFF090814 || 0xFF2F2E41 => AppIllustrationPaint.ink,
      0xFF33323D || 0xFF3F3D56 => AppIllustrationPaint.inkSoft,
      0xFF464353 ||
      0xFF504F60 ||
      0xFF514E7F ||
      0xFF65617D => AppIllustrationPaint.inkLight,
      0xFF9D616A ||
      0xFF9E616A ||
      0xFF9F616A ||
      0xFFA0616A => AppIllustrationPaint.skinDeep,
      0xFFED9DA0 || 0xFFEE8E9E => AppIllustrationPaint.skinWarm,
      0xFFFFB6B6 || 0xFFFFB8B8 => AppIllustrationPaint.skinLight,
      0xFFFFFFFF || 0xFFF0F0F0 || 0xFFF2F2F2 => AppIllustrationPaint.paper,
      0xFFE3E8F4 ||
      0xFFE5E5E5 ||
      0xFFE6E6E6 ||
      0xFFE6E8EC => AppIllustrationPaint.paperShade,
      0xFFCACACA || 0xFFCCCCCC || 0xFFD6D6E3 => AppIllustrationPaint.paperDeep,
      _ => null,
    };
    if (paint != null) return palette[paint].withValues(alpha: color.a);

    // New source colors retain hue and shading instead of silently becoming
    // green. The lightness floor keeps future artwork off the dark ground.
    final source = HSLColor.fromColor(color);
    return source
        .withLightness(source.lightness.clamp(0.52, 0.94))
        .toColor()
        .withValues(alpha: color.a);
  }

  @override
  bool operator ==(Object other) =>
      other is _IllustrationPalette &&
      other.palette == palette &&
      other.asset == asset;

  @override
  int get hashCode => Object.hash(palette, asset);
}
