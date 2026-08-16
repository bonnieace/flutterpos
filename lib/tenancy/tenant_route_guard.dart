import 'dart:async';

import 'package:flutter/material.dart';

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
    this.loading,
    this.denied,
    this.failure,
  });

  final TenantGuardedLoader<T> load;
  final TenantGuardedBuilder<T> builder;
  final Iterable<TenantRole>? allowedRoles;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = TenantSessionScope.of(context);
    _synchronize();
  }

  @override
  void didUpdateWidget(covariant TenantRouteGuard<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.load != widget.load ||
        oldWidget.allowedRoles != widget.allowedRoles) {
      // The scope itself may have been replaced in the same frame. Re-read it
      // before synchronizing so a new loader cannot start against the prior
      // controller's still-authorized session.
      _controller = TenantSessionScope.of(context);
      _capturedSession = null;
      _synchronize();
    }
  }

  void _synchronize() {
    final controller = _controller!;
    TenantSession? next;
    try {
      next = controller.requireSession(allowedRoles: widget.allowedRoles);
    } on StateError {
      _generation++;
      _capturedSession = null;
      _value = null;
      _error = null;
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
    _value = null;
    _error = null;
    _phase = _TenantGuardPhase.loading;
    unawaited(_load(next, generation));
  }

  Future<void> _load(TenantSession captured, int generation) async {
    try {
      final value = await widget.load(captured);
      if (!_isCurrent(captured, generation)) return;
      setState(() {
        _value = value;
        _phase = _TenantGuardPhase.ready;
      });
    } catch (error) {
      if (!_isCurrent(captured, generation)) return;
      setState(() {
        _error = error;
        _phase = _TenantGuardPhase.failure;
      });
    }
  }

  bool _isCurrent(TenantSession captured, int generation) {
    if (!mounted || generation != _generation) return false;
    final current = _controller?.session;
    return current != null &&
        current.uid == captured.uid &&
        current.tenantId == captured.tenantId &&
        current.epoch == captured.epoch &&
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
    _TenantGuardPhase.ready => widget.builder(
      context,
      _capturedSession!,
      _value as T,
    ),
  };
}
