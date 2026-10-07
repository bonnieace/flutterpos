/// A floating bottom navigation bar: a capsule of circles in which the current
/// destination grows into a pill holding a primary-filled circle and its name.
///
/// Drawn for the platform console on 2026-10-06, from the developer's
/// references (`docs/design/platform-console`). One bar at every width: the
/// circles are `icons.launcherWell` (56) at `medium` and up and the 48dp
/// minimum target below it.
library;

import 'package:flutter/material.dart';

import 'press.dart';
import 'spring.dart';
import 'tokens.dart';

/// One place the bar can take a person.
@immutable
final class AppBottomDestination {
  const AppBottomDestination({
    required this.label,
    required this.icon,
    this.badgeCount,
    this.destinationKey,
  });

  /// The name the current destination shows, and every destination announces.
  final String label;

  final IconData icon;

  /// A count drawn on the circle's corner and announced with the name, or
  /// nothing when null or zero.
  final int? badgeCount;

  final Key? destinationKey;
}

final class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
  }) : assert(destinations.length > 1);

  final List<AppBottomDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// Whether the bar draws its compact size at [width].
  static bool isCompact(AppTokens tokens, double width) =>
      width < tokens.layout.mediumFloor;

  /// The circle a destination sits in.
  static double circleOf(AppTokens tokens, {required bool compact}) => compact
      ? tokens.density.minimumTapTarget.height
      : tokens.icons.launcherWell;

  /// How far the bar floats above the bottom edge.
  static double liftOf(AppTokens tokens, {required bool compact}) =>
      compact ? tokens.spacing.s16 : tokens.spacing.s24;

  /// The space a scrolling body leaves under its last row so the bar never
  /// covers it: the bar, its lift, and one more lift of air.
  static double clearanceOf(AppTokens tokens, {required bool compact}) {
    final padding = compact ? tokens.spacing.s4 : tokens.spacing.s8;
    return circleOf(tokens, compact: compact) +
        padding * 2 +
        liftOf(tokens, compact: compact) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final compact = isCompact(tokens, MediaQuery.sizeOf(context).width);
    final padding = compact ? tokens.spacing.s4 : tokens.spacing.s8;
    final effects = tokens.effects;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          border: Border.all(color: tokens.colors.surface.cardEdge),
          borderRadius: BorderRadius.circular(tokens.radius.pill),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: tokens.colors.surface.sunken.withValues(
                alpha: effects.floatingShadowOpacity,
              ),
              blurRadius: effects.floatingShadowBlur,
              offset: Offset(0, effects.floatingShadowDrop),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var index = 0; index < destinations.length; index++) ...[
                if (index > 0) SizedBox(width: padding),
                _BottomNavItem(
                  key: destinations[index].destinationKey,
                  destination: destinations[index],
                  current: index == currentIndex,
                  compact: compact,
                  onPressed: () => onSelected(index),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Places one [AppBottomNav] over a set of pages: the bar centred near the
/// bottom, the pages fading into the background beneath it.
///
/// **One bar for every destination, outside the pages.** A bar drawn inside
/// each page is a different bar per page, and a page kept alive offstage has
/// its animations paused, so coming back to it showed its bar frozen wherever
/// it last stopped. Drawn once here, the same bar animates from where it is in
/// either direction. Each page still pads its last row by
/// [AppBottomNav.clearanceOf] so nothing ends under the bar.
final class AppBottomNavFrame extends StatelessWidget {
  const AppBottomNavFrame({super.key, required this.bar, required this.child});

  final AppBottomNav bar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final compact = AppBottomNav.isCompact(
      tokens,
      MediaQuery.sizeOf(context).width,
    );
    return Stack(
      children: <Widget>[
        Positioned.fill(child: child),
        // The page fades into the background under the bar, so a row passing
        // beneath it is not read through it.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: AppBottomNav.clearanceOf(tokens, compact: compact),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    tokens.colors.surface.base.withValues(alpha: 0),
                    tokens.colors.surface.base,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom:
              AppBottomNav.liftOf(tokens, compact: compact) +
              MediaQuery.paddingOf(context).bottom,
          // Outside every page's Scaffold, so it brings the Material its text
          // and ink need.
          child: Material(
            type: MaterialType.transparency,
            child: Center(child: bar),
          ),
        ),
      ],
    );
  }
}

final class _BottomNavItem extends StatefulWidget {
  const _BottomNavItem({
    super.key,
    required this.destination,
    required this.current,
    required this.compact,
    required this.onPressed,
  });

  final AppBottomDestination destination;
  final bool current;
  final bool compact;
  final VoidCallback onPressed;

  @override
  State<_BottomNavItem> createState() => _BottomNavItemState();
}

final class _BottomNavItemState extends State<_BottomNavItem>
    with SingleTickerProviderStateMixin {
  /// Below this the pill is drawn closed: a spring settles near its target,
  /// not on it.
  static const double _closed = 0.001;

  SpringDrive? _drive;

  SpringDrive _driveFor(AppTokens tokens) => _drive ??= SpringDrive(
    vsync: this,
    spring: tokens.motion.snappy,
    value: widget.current ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _BottomNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current == widget.current) return;
    // **From where it is, not from zero.** A second tap while the pill is
    // still growing reverses it from its current width and velocity.
    final disabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _drive?.animateTo(widget.current ? 1 : 0, immediately: disabled);
  }

  @override
  void dispose() {
    _drive?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final drive = _driveFor(tokens);
    final circle = AppBottomNav.circleOf(tokens, compact: widget.compact);
    final gap = widget.compact ? tokens.spacing.s8 : tokens.spacing.s12;
    final trailing = widget.compact ? tokens.spacing.s16 : tokens.spacing.s24;
    final count = widget.destination.badgeCount ?? 0;
    final radius = BorderRadius.circular(tokens.radius.pill);
    final semanticLabel = count > 0
        ? '${widget.destination.label}, $count'
        : widget.destination.label;

    final item = AnimatedBuilder(
      animation: drive.animation,
      builder: (context, _) {
        final t = drive.value.clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface.field,
            borderRadius: radius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox.square(
                dimension: circle,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            colors.surface.field,
                            colors.action.primary.container,
                            t,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            widget.destination.icon,
                            size: tokens.icons.card,
                            color: Color.lerp(
                              colors.text.secondary,
                              colors.action.primary.label,
                              t,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (count > 0)
                      PositionedDirectional(
                        top: 0,
                        end: 0,
                        child: _NavBadge(count: count, tokens: tokens),
                      ),
                  ],
                ),
              ),
              // The name is revealed rather than faded in alone: the pill
              // widens by exactly the width the label needs. At rest closed
              // it is not built at all, so nothing reads a hidden name.
              if (t > _closed)
                ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: t,
                    // Only the width is revealed; the height is the label's.
                    heightFactor: 1,
                    child: Opacity(
                      opacity: t,
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: gap,
                          end: trailing,
                        ),
                        child: Text(
                          widget.destination.label,
                          maxLines: 1,
                          style: tokens.typography.labelMedium.copyWith(
                            color: colors.text.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );

    final pressable = PressSurface(
      borderRadius: radius,
      onPressed: widget.current ? null : widget.onPressed,
      hoverOverlay: colors.action.tertiary.hoverWash(),
      pressedOverlay: colors.action.tertiary.pressedWash(),
      minimumTapTarget: Size.square(circle),
      reservesRingGutter: false,
      semanticLabel: semanticLabel,
      excludeSemantics: true,
      child: item,
    );
    final announced = Semantics(
      button: true,
      selected: widget.current,
      label: semanticLabel,
      onTap: widget.current ? null : widget.onPressed,
      child: ExcludeSemantics(child: pressable),
    );
    return widget.current
        ? announced
        : Tooltip(message: widget.destination.label, child: announced);
  }
}

final class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count, required this.tokens});

  final int count;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final colors = tokens.colors;
    // As `HomeModuleGrid`'s badge: the problem colour, edged in the page so it
    // reads as lifted off the circle, the figure in the page colour.
    return Container(
      constraints: BoxConstraints(minWidth: tokens.spacing.s20),
      height: tokens.spacing.s20,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.status.problem.fg,
        borderRadius: BorderRadius.circular(tokens.radius.pill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: tokens.typography.monoCaption.copyWith(
          color: colors.surface.base,
        ),
      ),
    );
  }
}
