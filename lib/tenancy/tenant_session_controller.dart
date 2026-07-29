import 'package:flutter/widgets.dart';

import 'tenant_membership.dart';
import 'tenant_session.dart';
import 'tenant_types.dart';

/// Owns the one selected tenant and invalidates stale asynchronous work by
/// advancing an epoch whenever selection or authentication state changes.
final class TenantSessionController extends ChangeNotifier {
  TenantSession? _session;
  TenantMembership? _membership;
  int _nextEpoch = 0;

  TenantSession? get session => _session;
  TenantMembership? get membership => _membership;
  bool get hasSession => _session != null;

  TenantSession requireSession({Iterable<TenantRole>? allowedRoles}) {
    final current = _session;
    if (current == null || !current.canAccess(allowedRoles: allowedRoles)) {
      throw StateError('An authorized tenant session is required.');
    }
    return current;
  }

  void open({required String uid, required TenantMembership membership}) {
    final next = TenantSession.fromMembership(
      uid: uid,
      membership: membership,
      epoch: _nextEpoch,
    );
    _nextEpoch++;
    _session = next;
    _membership = membership;
    notifyListeners();
  }

  void clear() {
    _nextEpoch++;
    final changed = _session != null || _membership != null;
    _session = null;
    _membership = null;
    if (changed) notifyListeners();
  }

  bool ownsEpoch(int epoch) => _session?.ownsEpoch(epoch) ?? false;
}

final class TenantSessionScope
    extends InheritedNotifier<TenantSessionController> {
  const TenantSessionScope({
    super.key,
    required TenantSessionController controller,
    required super.child,
  }) : super(notifier: controller);

  static TenantSessionController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TenantSessionScope>();
    if (scope == null || scope.notifier == null) {
      throw StateError('TenantSessionScope is missing above this context.');
    }
    return scope.notifier!;
  }

  static TenantSessionController read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<TenantSessionScope>();
    final scope = element?.widget as TenantSessionScope?;
    if (scope == null || scope.notifier == null) {
      throw StateError('TenantSessionScope is missing above this context.');
    }
    return scope.notifier!;
  }
}
