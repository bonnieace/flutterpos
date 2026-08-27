/// `AppCard`: the bordered container every Stitch composition is built out of.
///
/// The export writes it the same way on every screen —
/// `bg-surface-card border border-surface-elevated rounded-xl p-…` — so it is
/// one widget here rather than a `BoxDecoration` copied into each panel. All
/// four values are roles: [AppSurfaceRoles.raised], [AppSurfaceRoles.borderSubtle],
/// `radius.md` and a spacing step.
///
/// It has no states of its own. A card that can be pressed is `PressSurface`
/// wrapping one of these, and a card that carries a status draws
/// `StatusBadge` inside it.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// A bordered surface at `surface.raised`.
final class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.bordered = true,
  });

  final Widget child;

  /// Defaults to `space.16`, which is the export's `p-margin-mobile` on a card.
  final EdgeInsetsGeometry? padding;

  /// Whether the hairline is painted. Off for a card sitting inside another
  /// bordered surface, where a second edge reads as a seam.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        border: bordered
            ? Border.all(color: tokens.colors.surface.borderSubtle)
            : null,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(tokens.spacing.s16),
        child: child,
      ),
    );
  }
}
