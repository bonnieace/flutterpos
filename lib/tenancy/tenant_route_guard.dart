import 'dart:async';

import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) => switch (_phase) {
    _TenantGuardPhase.denied =>
      widget.denied ?? const Center(child: Text('Tenant access unavailable.')),
    _TenantGuardPhase.loading =>
      widget.loading ?? const Center(child: CircularProgressIndicator()),
    _TenantGuardPhase.failure =>
      widget.failure?.call(context, _error!) ??
          const Center(child: Text('Tenant data unavailable.')),
    _TenantGuardPhase.ready => widget.builder(
      context,
      _capturedSession!,
      _value as T,
    ),
  };
}
