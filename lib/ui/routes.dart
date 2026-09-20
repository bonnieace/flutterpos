/// `AppPageRoute`: `design.md` §6.2's two route rows, on the substrate §2.4
/// demands.
///
/// **This is the last part of §11 step 2, and it was held back twice for a
/// reason that turned out to be right.** §2.4 makes anything spatial a spring,
/// and a route arriving is the largest spatial move in the app. The one
/// mechanism that reaches every `MaterialPageRoute` without touching a call
/// site - `ThemeData.pageTransitionsTheme` - **cannot produce a spring**: a
/// `PageTransitionsBuilder` only reshapes an animation the route already drives
/// on a duration, so anything written through it is a curve wearing a spring's
/// name.
///
/// **What the SDK turned out to provide, and what `PLAN.md` predicted it did
/// not.** This chunk was scoped around `AnimationController.animateWith` always
/// reporting direction *forward*, so a simulation driven to 0 would finish
/// `completed` rather than `dismissed` and `TransitionRoute._handleStatusChanged`
/// would never call `finalizeRoute` - leaking every popped route. On Flutter
/// 3.44 that hazard cannot be reached from here, because `TransitionRoute`
/// itself takes a simulation: [TransitionRoute.createSimulation] is called on
/// every push and pop, and the pop path hands it to
/// `AnimationController.animateBackWith`, which sets the reverse direction. The
/// leak is still the thing to verify rather than assume - see
/// `test/ui/routes_test.dart`, which pushes and pops a hundred times and waits
/// on `Route.completed` for every one of them.
///
/// **Interruptibility comes from the same ordering, and it is worth knowing why
/// it holds.** `createSimulation` is called *before* the controller is stopped,
/// so `controller.value` and `controller.velocity` inside it are the live
/// figures of the transition still in flight. A pop arriving mid-push therefore
/// leaves from where the page actually is, at the speed it is actually going,
/// which is §2.4's first rule and `claude.md`'s motion rule.
///
/// **Two rows, not one.** §6.2 gives compact a horizontal spring with the
/// covered surface parallaxing at [AppMotion.routeParallax], and expanded a
/// fade-through on `motion.medium` with no horizontal travel at all. The row is
/// chosen once, when the route is installed, and held for the life of the route:
/// a transition that changed identity half way through because a window was
/// resized would be worse than either row.
///
/// **§4.1's third breakpoint is not named by §6.2, and this is the reading
/// taken.** The table names `compact` and `expanded`; §4.1 defines `expanded` as
/// `>= 1024` and `medium` as the 768-1023 band in between. A tablet therefore
/// gets the compact row, which is the literal reading of "expanded" and also the
/// one §4.3 takes for the sale pane. Recorded in `PLAN.md` rather than decided
/// silently.
library;

import 'package:flutter/material.dart';

import 'spring.dart';
import 'tokens.dart';

/// Which of `design.md` §6.2's two route rows a transition runs.
enum AppRouteTransition {
  /// "Route push (compact)": horizontal, incoming full, outgoing parallax at
  /// [AppMotion.routeParallax], `spring.smooth`.
  slide,

  /// "Route change (expanded)": fade-through, no horizontal travel,
  /// `motion.medium`.
  ///
  /// **The only row in §2.4's duration half that moves a whole screen**, and it
  /// is not a contradiction: nothing here travels. An opacity takes a duration
  /// and a position takes a spring, so a transition that is purely opacity is
  /// correctly a duration.
  fade,
}

/// Whether a surface of this width is §4.1's `expanded`.
///
/// Read `tenantTableBreakpoint` when this was written, on the grounds that a
/// further declaration of 1024 would make the existing drift worse. Step 6 did
/// the unification §4.1 asks for, so this now asks [AppLayout] the question in
/// §4.1's own words, at the same number.
bool _isExpanded(double width) =>
    AppLayout.contract.isAtLeast(width, AppBreakpoint.expanded);

/// A route that arrives on a spring.
///
/// Swap for `MaterialPageRoute`: the constructor takes the same [builder] and
/// the same [settings], and the page it builds is wrapped in the same route
/// semantics scope.
final class AppPageRoute<T> extends PageRoute<T> {
  AppPageRoute({
    required this.builder,
    super.settings,
    super.fullscreenDialog,
    this.maintainState = true,
  });

  /// Builds the page. Called once per route, as `MaterialPageRoute`'s is.
  final WidgetBuilder builder;

  @override
  final bool maintainState;

  /// Which of §6.2's two rows this route is running, decided in [install] and
  /// held.
  ///
  /// Visible for the tests that assert the breakpoint reading, and read by
  /// [delegatedTransition] so the surface being covered agrees with the surface
  /// covering it rather than resolving the question a second time.
  @visibleForTesting
  AppRouteTransition get transition => _transition;
  AppRouteTransition _transition = AppRouteTransition.slide;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  /// §6.2's `motion.medium`, which is the [AppRouteTransition.fade] row's own
  /// token and the only row this duration drives.
  ///
  /// **[AppRouteTransition.slide] ignores it entirely** - [createSimulation]
  /// returns a spring there and `TransitionRoute` documents that the duration is
  /// then unused. It is still not free to be wrong: `TransitionRoute` asserts it
  /// is non-negative on every push, and the controller is built from it before
  /// any simulation exists.
  ///
  /// Read from [AppMotion.standard] rather than through [AppTokens.of], because
  /// a route is not in the tree and has no context to read a theme from. That is
  /// the same token set `AppTokens.dark` carries, and §3's density - the one
  /// thing a screen may override - carries no motion.
  @override
  Duration get transitionDuration => AppMotion.standard.medium.duration;

  @override
  Duration get reverseTransitionDuration => AppMotion.standard.medium.duration;

  /// The [MediaQueryData] above the navigator, or null before this route is
  /// installed.
  ///
  /// **`getInheritedWidgetOfExactType`, deliberately, not `MediaQuery.of`.** A
  /// route is not a widget and the context it has is the *navigator's*, so
  /// depending on it would rebuild the navigator - and therefore consider every
  /// route in it - on every metrics change, the keyboard opening included. This
  /// reads the same value and registers nothing.
  MediaQueryData? get _mediaQuery => navigator?.context
      .getInheritedWidgetOfExactType<MediaQuery>()
      ?.data;

  /// §2.4's reduced-motion clause: "springs collapse to instant, durations to
  /// 0".
  ///
  /// Read fresh on every push and pop rather than latched with [transition],
  /// because a person can turn it on while the app is running and the next
  /// transition should honour it.
  bool get _reducedMotion => _mediaQuery?.disableAnimations ?? false;

  @override
  void install() {
    final width = _mediaQuery?.size.width;
    _transition = width != null && _isExpanded(width)
        ? AppRouteTransition.fade
        : AppRouteTransition.slide;
    super.install();
  }

  @override
  Simulation? createSimulation({required bool forward}) {
    final target = forward ? 1.0 : 0.0;
    if (_reducedMotion) return _InstantSimulation(target);
    // The fade row is a duration by specification, so it declines to provide a
    // simulation and `TransitionRoute` drives the controller with
    // `forward()` / `reverse()` over `transitionDuration` instead.
    if (_transition == AppRouteTransition.fade) return null;
    final controller = this.controller!;
    // **The live value and the live velocity.** `TransitionRoute` calls this
    // before it stops the controller, so a pop that interrupts a push leaves
    // from where the page is at the speed it is going. This is the one line the
    // whole file exists for.
    return SettlingSpringSimulation(
      AppMotion.standard.smooth,
      controller.value,
      target,
      controller.velocity,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // The same scope `MaterialPageRoute` puts around its content. Without it a
    // screen reader is not told the route changed, which §9 makes pass/fail.
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: builder(context),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_transition == AppRouteTransition.fade) {
      // §6.2: fade-through, no horizontal travel. **Only the incoming surface
      // fades.** Fading both at once crosses through the barrier behind them
      // and washes the whole screen toward black half way; the arriving page is
      // opaque, so fading it in over the page it is covering reads as the
      // fade-through the row asks for and never shows a gap.
      return FadeTransition(
        opacity: animation.drive(
          CurveTween(curve: AppMotion.standard.medium.curve),
        ),
        child: child,
      );
    }

    final motion = AppTokens.componentOf(context).motion;
    final rightwards = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;

    // No curve on either tween: the spring **is** the curve, and putting one in
    // front of it would reshape the physics into something that is no longer
    // interruptible from a velocity.
    final incoming = Tween<Offset>(
      begin: Offset(rightwards, 0),
      end: Offset.zero,
    );
    final outgoing = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(-rightwards * motion.routeParallax, 0),
    );

    return SlideTransition(
      position: animation.drive(incoming),
      child: SlideTransition(
        position: secondaryAnimation.drive(outgoing),
        child: child,
      ),
    );
  }

  // **`delegatedTransition` is deliberately not implemented, and it was
  // implemented once and taken out again.** It is the SDK's mechanism for
  // telling the route below how to leave, and it is the only way to parallax a
  // covered `MaterialPageRoute` - which is what `MaterialApp.home` makes the
  // landing route, and therefore what eight of this app's twenty-three pushes
  // cover. It worked, and it cost an extra Firestore read on every push and
  // every pop:
  //
  // `ModalRoute.didChangeNext` sets `receivedTransition` when the incoming
  // route offers one, and `_buildFlexibleTransitions` then wraps the covered
  // route's own transition in it. That changes the **shape** of the widget tree
  // above the page, so the page - which hangs off `route._subtreeKey`, a
  // `GlobalKey` - is re-parented rather than updated. A re-parented subtree
  // rebuilds, `TenantRouteGuard` is handed a fresh `load` closure, its
  // `didUpdateWidget` compares closures by identity, and it reloads. Measured:
  // `sales, returns, sales` where the same tap used to read `sales, returns`.
  //
  // `claude.md` hard rule 1 makes that disqualifying on its own - a UI change
  // never issues a repository call - so the parallax stops at the boundary
  // between the two route kinds. Fifteen of the twenty-three pushes cover
  // another `AppPageRoute` and parallax through `buildTransitions` above; the
  // eight that cover the landing route slide in over a surface that holds
  // still. See `PLAN.md` for the coupling and what would close it.
}

/// §2.4's reduced-motion clause, as a simulation: already at the end, already
/// done.
///
/// **Not `transitionDuration = Duration.zero`**, which would be the obvious
/// alternative and is not reachable - the duration is a getter with no context,
/// and whether motion is disabled is a property of the surface rather than of
/// the route class.
///
/// **Not the framework's own handling either.** `AnimationController` scales
/// every duration by 0.05 when `SemanticsBinding.instance.disableAnimations` is
/// set, which is 12ms here - under one frame, so it looks the same. It reads a
/// different flag from the one §2.4 names, is invisible to a widget test that
/// sets `MediaQueryData.disableAnimations`, and is a scale rather than a
/// collapse.
final class _InstantSimulation extends Simulation {
  _InstantSimulation(this._end);

  final double _end;

  @override
  double x(double time) => _end;

  @override
  double dx(double time) => 0;

  @override
  bool isDone(double time) => true;
}

/// Watches the navigator so a screen can be told when it is on top again.
///
/// **Registered in `main.dart`, and a test that omits it simply never
/// re-reads** - `RouteAware` is a subscription, so an absent observer is
/// silence rather than an error.
///
/// **It lives here rather than beside the home**, which is where it was first
/// written. Every screen that pushes another over itself has the same problem,
/// and a mechanism only the home could reach is one the next screen solves
/// again by hand - see [RereadOnReturn].
final RouteObserver<PageRoute<dynamic>> tenantRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// Re-reads a screen when a route pushed above it is popped.
///
/// **A screen that writes a record does not re-read it.** Pushing a module over
/// a page and coming back is a pop, not a rebuild, and a guard re-reads only
/// when its loader changes identity - which is what a rebuild produces. So a
/// list that sent somebody off to add a row showed the list without the row,
/// with nothing to say it was stale. The home fixed this for itself in
/// September 2026; the expenses list and the stock counts list each had the
/// same defect, and each would have had to fix it again.
///
/// **`didPopNext` is the exact moment**, rather than a timer or a listener on
/// every write: it fires when this route becomes the top one again, which is
/// when what is drawn here is about to be looked at.
///
/// A sheet is not a [PageRoute], so it does not reach this. A screen that
/// writes through a sheet re-reads when the sheet answers - see
/// `TenantExpensesPanel`.
mixin RereadOnReturn<T extends StatefulWidget> on State<T> implements RouteAware {
  /// Re-read whatever this screen shows. Usually a `setState` that changes the
  /// key its loader is composed from.
  void rereadAfterReturn();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      // Subscribing twice for the same route is a no-op in `RouteObserver`, so
      // this stays correct across the dependency changes that bring us here.
      tenantRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    tenantRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    if (mounted) rereadAfterReturn();
  }

  @override
  void didPush() {}

  @override
  void didPop() {}

  @override
  void didPushNext() {}
}
