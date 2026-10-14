/// `TopBarSurface`: what every top bar in the app stands on, since 2026-10-13
/// (`docs/design/topbar/`).
///
/// **At rest a bar is the page.** It is `surface.base`, the page's own, with no
/// edge, so the bar and what is under it read as one surface and the status
/// bar above it on a phone does too. **When something scrolls under it, it
/// lifts one step**, to `surface.raised` with a `borderSubtle` hairline. That
/// is `spiritTheme`'s rule for a bar - a surface step, never a drop shadow -
/// now said by the bar itself, where before the home drew a raised strip at
/// all times and every other route drew none at any time.
///
/// **The same signal `AppBar` uses, read the same way.** `Scaffold` wraps its
/// body in a [ScrollNotificationObserver], and a bar asks it whether the
/// page's primary scrollable is past its start. Nothing about the page changes:
/// a bar listens to scrolls that were already happening.
///
/// **A colour change, so a duration rather than a spring**: `motion.short`,
/// and a scroll that turns back mid-fade retargets from the colour it reached.
/// Under reduced motion it is instant.
///
/// **An inner screen's bar also says which module it is in, and whether the
/// device is offline** (`docs/design/topbar-inner/`): [TopBarModuleWell] and
/// [TopBarOfflineBadge], drawn by `AppScaffold`. The module comes from the
/// route (`AppPageRoute.module`) and the reading from [DeviceOnlineScope], so
/// no screen passes either.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'status.dart';
import 'tokens.dart';

/// A home module, as an inner screen's bar draws it: the home card's glyph in
/// the card's colour.
@immutable
final class TopBarModule {
  const TopBarModule({required this.icon, required this.label, this.accent});

  /// The glyph the module's card draws on a wider screen.
  final IconData icon;

  /// The module's name. Not drawn: the well is decorative, and it is the
  /// colour's seed when [accent] is null.
  final String label;

  /// The card's colour, or null for one picked from [label].
  final AppIdentityAccent? accent;
}

/// The module's glyph in a well, before an inner screen's title.
///
/// **The home card's well, smaller**: the same wash and the same solid glyph
/// in the same identity colour, so the screen reads as the card it was
/// opened from. Hidden from a screen reader - the title already says where
/// the person is - and never a control.
final class TopBarModuleWell extends StatelessWidget {
  const TopBarModuleWell({super.key, required this.module});

  final TopBarModule module;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final icons = tokens.icons;
    final accent = tokens.colors.accent;
    final slot = module.accent;
    return ExcludeSemantics(
      child: Container(
        key: const ValueKey('top-bar-module-well'),
        width: icons.barWell,
        height: icons.barWell,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.colors.surface.scrim.withValues(
            alpha: tokens.effects.cardWellWashOpacity,
          ),
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Icon(
          module.icon,
          size: icons.row,
          color: slot == null
              ? accent.identityFor(module.label)
              : accent.identityAt(slot),
          fill: icons.primaryFill,
          weight: icons.weight,
          grade: icons.grade,
          opticalSize: icons.opticalSizeFor(icons.row),
        ),
      ),
    );
  }
}

/// Whether this device has a network, for every route at once.
///
/// **Above the navigator**, beside the other app-wide scopes, because every
/// screen is its own root push and a bar cannot be handed a stream by each.
/// The reading is the platform's connectivity, the one `HubTopBar` and the
/// sale queue already use: it says the device has a network, not that the
/// server answered.
final class DeviceOnlineScope extends StatefulWidget {
  const DeviceOnlineScope({
    super.key,
    this.onlineCheck,
    this.onlineChanges,
    required this.child,
  });

  /// Asked once, for the first reading.
  final Future<bool> Function()? onlineCheck;

  /// Every later reading.
  final Stream<bool>? onlineChanges;

  final Widget child;

  /// The latest reading: null before the first one, or with no scope above.
  static bool? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DeviceOnline>()?.online;

  @override
  State<DeviceOnlineScope> createState() => _DeviceOnlineScopeState();
}

final class _DeviceOnlineScopeState extends State<DeviceOnlineScope> {
  bool? _online;
  StreamSubscription<bool>? _changes;

  @override
  void initState() {
    super.initState();
    _check();
    _listen();
  }

  @override
  void didUpdateWidget(DeviceOnlineScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.onlineChanges, widget.onlineChanges)) {
      unawaited(_changes?.cancel());
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  void _check() {
    final check = widget.onlineCheck;
    if (check == null) return;
    check().then(
      (online) {
        if (mounted) setState(() => _online = online);
      },
      // A reading that fails says nothing; the scope keeps what it had.
      onError: (Object _) {},
    );
  }

  void _listen() {
    _changes = widget.onlineChanges?.listen((online) {
      if (mounted) setState(() => _online = online);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) =>
      _DeviceOnline(online: _online, child: widget.child);
}

final class _DeviceOnline extends InheritedWidget {
  const _DeviceOnline({required this.online, required super.child});

  final bool? online;

  @override
  bool updateShouldNotify(_DeviceOnline oldWidget) =>
      online != oldWidget.online;
}

/// *Offline*, in an inner screen's bar.
///
/// **The home's badge, without the terminal**: the attention badge with the
/// `cloud_off` glyph and the word, so the state is never colour alone. From
/// 1024 up it says what that means for a sale. A live region, so a change of
/// network is news to someone who cannot see the bar. Online draws nothing,
/// which is the caller's to decide.
final class TopBarOfflineBadge extends StatelessWidget {
  const TopBarOfflineBadge({super.key, this.explained = false});

  /// Adds *sales save on this device*, where there is room for it.
  final bool explained;

  static const String word = 'Offline';
  static const String explanation = 'sales save on this device';

  @override
  Widget build(BuildContext context) {
    final full = '$word · $explanation';
    return Semantics(
      key: const ValueKey('top-bar-offline'),
      label: full,
      liveRegion: true,
      excludeSemantics: true,
      child: StatusBadge(
        status: AppStatus.attention,
        label: explained ? full : word,
        icon: Icons.cloud_off,
      ),
    );
  }
}

/// The bar's surface, lifted while content is scrolled under it.
///
/// [builder] receives the colour to paint at this moment, for a bar like
/// `AppBar` that paints its own [Material]; [child] is painted on it, for a
/// bar that does not. One of the two.
final class TopBarSurface extends StatefulWidget {
  const TopBarSurface({super.key, this.builder, this.child})
    : assert(
        (builder == null) != (child == null),
        'A surface paints a builder or a child, not both.',
      );

  /// A bar that paints its own background, given the colour to paint it.
  final Widget Function(BuildContext context, Color background)? builder;

  /// A bar drawn straight onto this surface.
  final Widget? child;

  @override
  State<TopBarSurface> createState() => _TopBarSurfaceState();
}

final class _TopBarSurfaceState extends State<TopBarSurface> {
  ScrollNotificationObserverState? _observer;
  bool _scrolledUnder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_onScroll);
    _observer = ScrollNotificationObserver.maybeOf(context);
    _observer?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    _observer = null;
    super.dispose();
  }

  /// `AppBar`'s own reading: the page's primary scrollable, and whether
  /// anything of it has gone past the bar's edge.
  void _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification ||
        !defaultScrollNotificationPredicate(notification)) {
      return;
    }
    final metrics = notification.metrics;
    final scrolledUnder = switch (metrics.axisDirection) {
      AxisDirection.down => metrics.extentBefore > 0,
      AxisDirection.up => metrics.extentAfter > 0,
      AxisDirection.left || AxisDirection.right => _scrolledUnder,
    };
    if (scrolledUnder != _scrolledUnder) {
      setState(() => _scrolledUnder = scrolledUnder);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final surface = tokens.colors.surface;
    final motion = tokens.motion.short;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : motion.duration;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _scrolledUnder ? 1 : 0),
      duration: duration,
      curve: motion.curve,
      builder: (context, lift, _) {
        final background = Color.lerp(surface.base, surface.raised, lift)!;
        final edge = Color.lerp(
          surface.borderSubtle.withValues(alpha: 0),
          surface.borderSubtle,
          lift,
        )!;
        final builder = widget.builder;
        return DecoratedBox(
          // In front of the bar, so it costs no height and lies on top of
          // whatever the bar paints as its own background.
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: edge)),
          ),
          child: builder != null
              ? builder(context, background)
              : ColoredBox(color: background, child: widget.child),
        );
      },
    );
  }
}
