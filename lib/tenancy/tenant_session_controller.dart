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

  /// How this controller asks whoever owns bootstrapping to re-read the open
  /// session. Set once, by the routing shell.
  ///
  /// **A relay, not a capability.** The controller still cannot fetch anything;
  /// it holds the one object every guarded surface already has a handle on, so
  /// a surface that learns the session is stale has somewhere to say so without
  /// a callback threaded down through every screen that might need one.
  void Function()? onRevalidationRequested;

  /// Reports that the server refused something this session believed it could
  /// do.
  ///
  /// **The refusal is the notification.** A role change reaches this device
  /// through no channel of its own, but a stale button pressed against a server
  /// that re-reads the actor's membership on every call produces a refusal that
  /// is near-proof the session has moved. Acting on it is what turns *press it
  /// again and be refused again* into a screen that corrects itself.
  void requestRevalidation() => onRevalidationRequested?.call();

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

  /// Re-states the open session from a freshly read membership, and says
  /// whether the access decision actually moved.
  ///
  /// **The epoch survives a refresh that changed nothing**, which is the whole
  /// point of this existing beside [open]. Every refresh went through [open]
  /// until 2026-09-15, and [open] always advances the epoch - so a re-read that
  /// returned exactly what the session already held still told every guard on
  /// screen that its value belonged to a dead session, and every form mid-submit
  /// that its own result was no longer current. That was survivable only because
  /// refreshes were rare. It stops being survivable the moment anything refreshes
  /// on a schedule, which is exactly what noticing a remote role change requires.
  ///
  /// **[TenantAccess] is the comparison, not [TenantMembership].** What must
  /// invalidate work in flight is the authorization decision; a business that
  /// merely renamed itself has not changed what anybody may do, and hanging the
  /// epoch on `updatedAt` would churn it on every unrelated edit to the tenant.
  /// The membership is still replaced either way, so a new name reaches the
  /// screen without disturbing the reads under it.
  bool refresh({required String uid, required TenantMembership membership}) {
    final current = _session;
    if (current == null ||
        current.uid != uid ||
        current.access != membership.access) {
      open(uid: uid, membership: membership);
      return true;
    }
    final membershipMoved = _membership != membership;
    _membership = membership;
    if (membershipMoved) notifyListeners();
    return false;
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
