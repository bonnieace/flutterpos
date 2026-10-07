/// `AppBrandIcon`: another app's own icon, for a destination that sends
/// through that app.
///
/// **The one surface whose colours are not `AppTokens`, at the developer's
/// direction on 2026-10-04.** The home's WhatsApp and Email tiles drew a chat
/// bubble and an envelope in this app's accents; a shopkeeper looks for the
/// icon they already tap on their phone. An app's icon redrawn in somebody
/// else's palette is not that app's icon, so the colours live in the asset and
/// nowhere in a widget. The shape around them - size and radius - is still a
/// token, so the mark sits in a tile exactly where a glyph's well would.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// An app whose icon this app may draw.
enum AppBrandIcon {
  whatsapp('assets/app_icons/whatsapp.svg'),
  gmail('assets/app_icons/gmail.svg');

  const AppBrandIcon(this.asset);

  /// A full-bleed square: the icon's own ground to every edge, so the caller's
  /// clip is the only corner it has.
  final String asset;
}

/// [icon] as a square of [size], with corners of [radius].
///
/// **Decorative to a screen reader.** Every host already names the
/// destination in words; announcing *WhatsApp* twice is noise.
final class AppBrandIconMark extends StatelessWidget {
  const AppBrandIconMark({
    super.key,
    required this.icon,
    required this.size,
    required this.radius,
  });

  final AppBrandIcon icon;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SvgPicture.asset(
      icon.asset,
      width: size,
      height: size,
      excludeFromSemantics: true,
    ),
  );
}
