import 'dart:async';

import 'package:flutter/material.dart';
import '../observability/app_telemetry.dart';

import '../ui/states.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';
import 'tenant_types.dart';

typedef TenantGuardedLoader<T> = Future<T> Function(TenantSession session);
typedef TenantGuardedBuilder<T> =
    Widget Function(BuildContext context, TenantSession session, T value);

/// Loads and renders a tenant route only while its captured session is live.
///
/// A UID/tenant/epoch or role change starts a fresh load. Results belonging to
/// the old session are discarded before they can update the widget tree.
final class TenantRouteGuard<T> extends StatefulWidget {
  const TenantRouteGuard({
    super.key,
    required this.load,
    required this.builder,
    this.allowedRoles,
    this.loadCached,
    this.loading,
    this.denied,
    this.failure,
  });

  /// The read this page is for.
  ///
  /// **Its identity is the question being asked, so memoise it.** The guard
  /// re-reads whenever this closure is not the one it saw last frame, which is
  /// what makes a filter change, a page turn and a post-write refresh work
  /// without a key. A panel that builds a fresh closure on every `build` would
  /// therefore re-read on every frame; the shape that avoids it is a
  /// `_composeLoaders(key)` that rebuilds the pair only when its key moves, as
  /// every paged panel in this app now has.
  ///
  /// **Do not put the filter in a `ValueKey` on this widget.** Until 2026-09-04
  /// every panel did, which destroyed this `State` and threw away the value on
  /// screen for a read that usually took a few hundred milliseconds - on the
  /// routes with no `loading` frame, a full-page spinner over figures the
  /// device was still holding. Keeping the key is right for one case only: a
  /// guard whose *subject* changes within one instance, like a receipt lookup
  /// where showing the previous receipt while the next one loads would be a
  /// lie rather than a delay.
  final TenantGuardedLoader<T> load;
  final TenantGuardedBuilder<T> builder;
  final Iterable<TenantRole>? allowedRoles;

  /// The same value, read from what this device already holds.
  ///
  /// **It runs beside [load] rather than before it, and it can never lose.**
  /// Firestore's cache has held this app's documents since `main.dart` turned
  /// persistence on; what was missing was anything willing to draw from it
  /// while the network was still deciding. A page that has a copy shows the
  /// copy now and corrects it when the server disagrees, instead of holding a
  /// spinner for a minute and then saying it could not be read.
  ///
  /// **A cache miss is silence.** This loader's failures are dropped whole -
  /// never shown, never logged as the page's error - because "not downloaded
  /// yet" is not something to put in front of a shopkeeper. Only [load] can
  /// fail this page.
  ///
  /// **The server always wins, whichever lands first.** A cached value that
  /// arrives after the server's is discarded rather than drawn over it.
  final TenantGuardedLoader<T>? loadCached;

  final Widget? loading;
  final Widget? denied;
  final Widget Function(BuildContext context, Object error)? failure;

  @override
  State<TenantRouteGuard<T>> createState() => _TenantRouteGuardState<T>();
}

enum _TenantGuardPhase { denied, loading, ready, failure }

final class _TenantRouteGuardState<T> extends State<TenantRouteGuard<T>> {
  TenantSessionController? _controller;
  TenantSession? _capturedSession;
  _TenantGuardPhase _phase = _TenantGuardPhase.denied;
  T? _value;
  Object? _error;
  int _generation = 0;

  /// Whether [_value] came from this device rather than from the server.
  bool _fromCache = false;

  /// Whether the server has since been asked and refused.
  ///
  /// Only ever true beside a value, and it is what separates *this is what we
  /// hold, the server has not answered yet* from *this is what we hold and the
  /// server cannot be reached*. The first is a moment; the second is worth
  /// saying out loud.
  bool _stale = false;

  /// Whether what is on screen is the answer to the *previous* question.
  ///
  /// Set while a retained value is being replaced - the next page is loading
  /// over this one, a filter has changed, a write asked for a re-read. It is
  /// not staleness: nothing has failed, and the figures shown were correct for
  /// what was asked a moment ago. It exists so a page can say *working* without
  /// taking its own contents away to say it.
  bool _rereading = false;

  /// Whether [load] has produced a value.
  ///
  /// **The one flag that keeps the cache from overwriting the server.** Both
  /// reads are in flight together and either can land first; without this, a
  /// slow cache read completing after a fast server read would replace a fresh
  /// figure with an old one.
  bool _hasServerValue = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = TenantSessionScope.of(context);
    _synchronize();
  }

  @override
  void didUpdateWidget(covariant TenantRouteGuard<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // **[TenantRouteGuard.loadCached] is deliberately not compared.** A panel
    // that memoised its server loader but built a fresh cached closure each
    // frame would re-read on every keystroke above it, and the cached read is
    // an optimisation - a stale closure of it asks for the same thing. What
    // would make it ask for something *else* is a filter change, and every
    // panel here re-keys the guard for those, which rebuilds this State whole.
    if (oldWidget.load != widget.load ||
        oldWidget.allowedRoles != widget.allowedRoles) {
      // The scope itself may have been replaced in the same frame. Re-read it
      // before synchronizing so a new loader cannot start against the prior
      // controller's still-authorized session.
      _controller = TenantSessionScope.of(context);
      final previous = _capturedSession;
      _capturedSession = null;
      // **A new loader for the same business keeps what is on screen.** This is
      // the same page asking a different question of it - the next page, another
      // filter, a re-read after a write - and until 2026-09-04 every one of
      // those blanked the value and dropped back to the loading state, which on
      // the nineteen routes that supply no frame meant a full-page spinner over
      // figures the device was still holding. A *different business* is the
      // opposite case and still blanks: none of the previous tenant's data may
      // survive the switch for even one frame.
      _synchronize(retain: previous != null && _sameSession(previous));
    }
  }

  /// Whether [previous] is the session the scope holds right now.
  bool _sameSession(TenantSession previous) {
    final current = _controller?.session;
    return current != null &&
        current.uid == previous.uid &&
        current.tenantId == previous.tenantId &&
        current.epoch == previous.epoch;
  }

  void _synchronize({bool retain = false}) {
    final controller = _controller!;
    TenantSession? next;
    try {
      next = controller.requireSession(allowedRoles: widget.allowedRoles);
    } on StateError {
      _generation++;
      _capturedSession = null;
      _value = null;
      _error = null;
      _rereading = false;
      _phase = _TenantGuardPhase.denied;
      return;
    }

    final previous = _capturedSession;
    if (previous != null &&
        previous.uid == next.uid &&
        previous.tenantId == next.tenantId &&
        previous.epoch == next.epoch) {
      return;
    }

    final generation = ++_generation;
    _capturedSession = next;
    // Retaining is only ever possible with something to retain; a first entry
    // has nothing and takes the loading state as it always did.
    final keeping = retain && _value != null;
    if (!keeping) _value = null;
    _error = null;
    _fromCache = keeping && _fromCache;
    _stale = false;
    _rereading = keeping;
    // **`_hasServerValue` is cleared either way**, which is what lets the new
    // read replace a retained value rather than lose the race to it.
    _hasServerValue = false;
    _phase = keeping ? _TenantGuardPhase.ready : _TenantGuardPhase.loading;
    unawaited(_load(next, generation));
    if (widget.loadCached != null) {
      unawaited(_loadFromCache(next, generation));
    }
  }

  Future<void> _load(TenantSession captured, int generation) async {
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'screen.load',
      screen: 'tenant_guard',
      context: {
        'user_id': captured.uid,
        'tenant_id': captured.tenantId,
        'view_type': '$T',
        'generation': generation,
      },
    );
    try {
      final value = await telemetry.trace(
        operation,
        'load_records',
        () => widget.load(captured),
      );
      telemetry.recordStep(operation, 'confirmed_on_server');
      if (!_isCurrent(captured, generation)) return;
      setState(() {
        _value = value;
        _hasServerValue = true;
        _fromCache = false;
        _stale = false;
        _rereading = false;
        _error = null;
        _phase = _TenantGuardPhase.ready;
      });
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'screen.load',
      );
      if (!_isCurrent(captured, generation)) return;
      setState(() {
        _error = error;
        // **A page that already has a copy keeps it.** The read failed; what is
        // on screen did not stop being what this device holds. Blanking it to
        // announce the failure would take away the figures *and* the controls
        // over a network that may be back in three seconds.
        // A retained value that the new read could not replace is stale in
        // exactly the sense this flag means, so the re-read ends here too.
        _rereading = false;
        if (_value != null) {
          _stale = true;
        } else {
          _phase = _TenantGuardPhase.failure;
        }
      });
    }
  }

  /// Draws what this device already holds, unless the server got there first.
  ///
  /// Every exit here is silent. A cache with nothing in it, a cache that
  /// refuses, a cache that answers too late - none of them is this page's
  /// error, and none of them may disturb what [load] has done.
  Future<void> _loadFromCache(TenantSession captured, int generation) async {
    final T value;
    try {
      value = await widget.loadCached!(captured);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'screen.cached_load',
      );
      return;
    }
    if (!_isCurrent(captured, generation)) return;
    if (_hasServerValue) return;
    setState(() {
      _value = value;
      _fromCache = true;
      _rereading = false;
      // **Adopted even after the server has already refused**, which is the
      // case worth spelling out: the two reads race, and a network that fails
      // fast can lose to a disk that is busy. Landing on a failure page is not
      // a reason to keep holding a copy back - it is the strongest reason to
      // show one.
      _stale = _error != null;
      _phase = _TenantGuardPhase.ready;
    });
  }

  bool _isCurrent(TenantSession captured, int generation) {
    if (!mounted || generation != _generation) return false;
    final current = _controller?.session;
    return current != null &&
        current.uid == captured.uid &&
        current.tenantId == captured.tenantId &&
        current.epoch == captured.epoch &&
        // A guarded route is a page to look at; whether its actions are
        // offered is each action's own question, asked with `canAccess`. So a
        // lapsed business opens its reports and finds no write controls on
        // them, rather than being told the page does not exist.
        current.canAccess(allowedRoles: widget.allowedRoles);
  }

  // The three defaults below are `design.md` §5.1's `LoadingState` and
  // `ErrorState`, and they are the reason those components close more surfaces
  // than the two they were queued against: **every guarded route in the app
  // renders one of them** unless it passes its own. Before this they were a
  // bare `CircularProgressIndicator` - §5.1's row, word for word - and two
  // sentences that named a *tenant* to a shopkeeper, which is §8 rule 1's own
  // complaint and which the step-11 copy pass could not see because it greps
  // screens rather than the frame under them.
  //
  // **The `??` stays and is not a formality.** Two panels deliberately pass
  // `SizedBox.shrink()` here - the shift panel and the checkout evidence strip -
  // because the guard's loading widget replaces the whole subtree, so a panel
  // that re-reads on a signal would blink a spinner over content it already
  // has. Do not "finish the migration" by taking those away.
  @override
  Widget build(BuildContext context) => switch (_phase) {
    _TenantGuardPhase.denied =>
      widget.denied ??
          const ErrorState(
            badgeLabel: 'No access',
            statement: 'You do not have access to this page.',
            stillTrue: 'Nothing on this page was changed.',
          ),
    _TenantGuardPhase.loading =>
      widget.loading ?? const LoadingState(message: 'Reading this page.'),
    _TenantGuardPhase.failure =>
      widget.failure?.call(context, _error!) ??
          const ErrorState(
            badgeLabel: 'Not read',
            statement: 'This page could not be read.',
            // §7's own template: what is still true despite it. A read that
            // failed wrote nothing, and saying so is what stops a person
            // going to look for damage.
            stillTrue: 'Nothing was changed.',
          ),
    _TenantGuardPhase.ready => TenantReadFreshness(
      fromCache: _fromCache,
      stale: _stale,
      rereading: _rereading,
      child: Builder(
        // A `Builder` so the page below reads the freshness this guard just
        // published rather than whatever was above the guard.
        builder: (inner) =>
            widget.builder(inner, _capturedSession!, _value as T),
      ),
    ),
  };
}

/// Where the value under it came from, for a page that wants to say so.
///
/// **Published instead of widening [TenantGuardedBuilder].** Every guarded
/// route in the app takes that builder, and almost none of them has anything
/// to say about provenance - putting a third parameter on it would have edited
/// twenty-odd call sites to give them an argument they ignore. A page that
/// does care asks; the rest never know this exists.
final class TenantReadFreshness extends InheritedWidget {
  const TenantReadFreshness({
    super.key,
    required this.fromCache,
    required this.stale,
    this.rereading = false,
    required super.child,
  });

  /// Whether this came off this device rather than from the server.
  final bool fromCache;

  /// Whether the server has since been asked for it and could not be reached.
  ///
  /// Never true on its own: it only qualifies a value that is already here.
  final bool stale;

  /// Whether this is the answer to the question *before* the current one.
  ///
  /// True while a page that already had a value is loading its next one - the
  /// next page, another filter, a re-read after a write. It is the flag that
  /// lets a route say *working* without blanking itself to say it, which is
  /// what it used to do. Never true beside [stale]: one means a read is in
  /// flight, the other that one finished and failed.
  final bool rereading;

  /// The freshness of the nearest guarded value, or null outside one.
  static TenantReadFreshness? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TenantReadFreshness>();

  @override
  bool updateShouldNotify(TenantReadFreshness oldWidget) =>
      oldWidget.fromCache != fromCache ||
      oldWidget.stale != stale ||
      oldWidget.rereading != rereading;
}
