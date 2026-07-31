import 'tenant_bootstrap.dart';
import 'tenant_membership.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';

enum TenantSwitchStateArea { checkout, pendingWrites, cashClose, workflow }

enum TenantSwitchBlocker {
  unsynchronizedCheckout,
  submissionInFlight,
  pendingWrites,
  unfinishedCashCountOrShiftClose,
  unsavedTenantWorkflow,
  onlineTargetValidationUnavailable,
  stateInspectionUnavailable,
  targetAccessDenied,
  sessionChanged,
  persistenceFailed,
  switchInProgress,
}

/// An explicit, session-bound answer from one tenant-scoped state owner.
///
/// The coordinator validates the UID, tenant, epoch, area, and blocker. A
/// stale or internally inconsistent inspection is treated as unavailable.
final class TenantSwitchInspection {
  const TenantSwitchInspection._({
    required this.area,
    required this.uid,
    required this.tenantId,
    required this.sessionEpoch,
    required this.blocker,
    required this.hasServerConfirmedOpenShift,
  });

  factory TenantSwitchInspection.clean({
    required TenantSwitchStateArea area,
    required TenantSession session,
    bool hasServerConfirmedOpenShift = false,
  }) => TenantSwitchInspection._(
    area: area,
    uid: session.uid,
    tenantId: session.tenantId,
    sessionEpoch: session.epoch,
    blocker: null,
    hasServerConfirmedOpenShift: hasServerConfirmedOpenShift,
  );

  factory TenantSwitchInspection.blocked({
    required TenantSwitchStateArea area,
    required TenantSession session,
    required TenantSwitchBlocker blocker,
    bool hasServerConfirmedOpenShift = false,
  }) => TenantSwitchInspection._(
    area: area,
    uid: session.uid,
    tenantId: session.tenantId,
    sessionEpoch: session.epoch,
    blocker: blocker,
    hasServerConfirmedOpenShift: hasServerConfirmedOpenShift,
  );

  final TenantSwitchStateArea area;
  final String uid;
  final String tenantId;
  final int sessionEpoch;
  final TenantSwitchBlocker? blocker;
  final bool hasServerConfirmedOpenShift;
}

abstract interface class TenantSwitchStateSource {
  TenantSwitchStateArea get area;

  Future<TenantSwitchInspection?> inspect(TenantSession session);
}

typedef TenantSwitchOnlineCheck = Future<bool> Function();
typedef TenantSwitchSessionChanged = void Function(TenantMembership membership);

final class TenantSwitchResult {
  const TenantSwitchResult._({this.membership, this.blocker});

  const TenantSwitchResult.switched(TenantMembership membership)
    : this._(membership: membership);

  const TenantSwitchResult.blocked(TenantSwitchBlocker blocker)
    : this._(blocker: blocker);

  final TenantMembership? membership;
  final TenantSwitchBlocker? blocker;

  bool get switched => membership != null && blocker == null;
}

/// Coordinates one fail-closed switch away from the currently open session.
final class TenantSwitchCoordinator {
  TenantSwitchCoordinator({
    required TenantSessionController sessionController,
    required TenantBootstrapService bootstrapService,
    required Iterable<TenantSwitchStateSource> stateSources,
    required TenantSwitchOnlineCheck isOnline,
    TenantSwitchSessionChanged? onSessionChanged,
  }) : _sessionController = sessionController,
       _bootstrapService = bootstrapService,
       _stateSources = List<TenantSwitchStateSource>.unmodifiable(stateSources),
       _isOnline = isOnline,
       _onSessionChanged = onSessionChanged;

  final TenantSessionController _sessionController;
  final TenantBootstrapService _bootstrapService;
  final List<TenantSwitchStateSource> _stateSources;
  final TenantSwitchOnlineCheck _isOnline;
  final TenantSwitchSessionChanged? _onSessionChanged;
  bool _switching = false;

  bool get isSwitching => _switching;

  Future<TenantSwitchResult> switchTenant(String targetTenantId) async {
    if (_switching) {
      return const TenantSwitchResult.blocked(
        TenantSwitchBlocker.switchInProgress,
      );
    }
    _switching = true;
    try {
      final current = _sessionController.session;
      final currentMembership = _sessionController.membership;
      if (current == null ||
          currentMembership == null ||
          !current.canAccess() ||
          currentMembership.tenantId != current.tenantId) {
        return const TenantSwitchResult.blocked(
          TenantSwitchBlocker.sessionChanged,
        );
      }
      if (targetTenantId.trim() == current.tenantId) {
        return const TenantSwitchResult.blocked(
          TenantSwitchBlocker.targetAccessDenied,
        );
      }

      final sourceByArea = <TenantSwitchStateArea, TenantSwitchStateSource>{};
      for (final source in _stateSources) {
        if (sourceByArea.containsKey(source.area)) {
          return const TenantSwitchResult.blocked(
            TenantSwitchBlocker.stateInspectionUnavailable,
          );
        }
        sourceByArea[source.area] = source;
      }
      if (sourceByArea.length != TenantSwitchStateArea.values.length) {
        return const TenantSwitchResult.blocked(
          TenantSwitchBlocker.stateInspectionUnavailable,
        );
      }

      for (final area in TenantSwitchStateArea.values) {
        final source = sourceByArea[area];
        if (source == null) {
          return const TenantSwitchResult.blocked(
            TenantSwitchBlocker.stateInspectionUnavailable,
          );
        }
        TenantSwitchInspection? inspection;
        try {
          inspection = await source.inspect(current);
        } catch (_) {
          return const TenantSwitchResult.blocked(
            TenantSwitchBlocker.stateInspectionUnavailable,
          );
        }
        if (!_isValidInspection(inspection, area, current)) {
          return const TenantSwitchResult.blocked(
            TenantSwitchBlocker.stateInspectionUnavailable,
          );
        }
        final blocker = inspection!.blocker;
        if (blocker != null) return TenantSwitchResult.blocked(blocker);
        if (!_owns(current)) {
          return const TenantSwitchResult.blocked(
            TenantSwitchBlocker.sessionChanged,
          );
        }
      }

      bool online;
      try {
        online = await _isOnline();
      } catch (_) {
        online = false;
      }
      if (!online) {
        return const TenantSwitchResult.blocked(
          TenantSwitchBlocker.onlineTargetValidationUnavailable,
        );
      }
      if (!_owns(current)) {
        return const TenantSwitchResult.blocked(
          TenantSwitchBlocker.sessionChanged,
        );
      }

      TenantMembership target;
      try {
        final match = await _bootstrapService.findAccessibleTenant(
          targetTenantId,
        );
        if (match == null) {
          return const TenantSwitchResult.blocked(
            TenantSwitchBlocker.targetAccessDenied,
          );
        }
        target = match;
      } catch (_) {
        return const TenantSwitchResult.blocked(
          TenantSwitchBlocker.onlineTargetValidationUnavailable,
        );
      }
      if (!_owns(current)) {
        return const TenantSwitchResult.blocked(
          TenantSwitchBlocker.sessionChanged,
        );
      }

      _sessionController.open(uid: current.uid, membership: target);
      final openedTarget = _sessionController.requireSession();
      _onSessionChanged?.call(target);
      try {
        await _bootstrapService.rememberOpenedTenant(
          uid: current.uid,
          tenantId: target.tenantId,
        );
      } catch (_) {
        if (!_owns(openedTarget)) {
          return const TenantSwitchResult.blocked(
            TenantSwitchBlocker.sessionChanged,
          );
        }
        _sessionController.open(
          uid: current.uid,
          membership: currentMembership,
        );
        _onSessionChanged?.call(currentMembership);
        return const TenantSwitchResult.blocked(
          TenantSwitchBlocker.persistenceFailed,
        );
      }
      if (!_owns(openedTarget)) {
        return const TenantSwitchResult.blocked(
          TenantSwitchBlocker.sessionChanged,
        );
      }
      return TenantSwitchResult.switched(target);
    } finally {
      _switching = false;
    }
  }

  bool _owns(TenantSession captured) {
    final current = _sessionController.session;
    return current != null &&
        current.uid == captured.uid &&
        current.tenantId == captured.tenantId &&
        current.epoch == captured.epoch;
  }

  bool _isValidInspection(
    TenantSwitchInspection? inspection,
    TenantSwitchStateArea area,
    TenantSession session,
  ) {
    if (inspection == null ||
        inspection.area != area ||
        inspection.uid != session.uid ||
        inspection.tenantId != session.tenantId ||
        inspection.sessionEpoch != session.epoch ||
        (inspection.hasServerConfirmedOpenShift &&
            area != TenantSwitchStateArea.cashClose)) {
      return false;
    }
    final blocker = inspection.blocker;
    if (blocker == null) return true;
    return switch (area) {
      TenantSwitchStateArea.checkout =>
        blocker == TenantSwitchBlocker.unsynchronizedCheckout ||
            blocker == TenantSwitchBlocker.submissionInFlight,
      TenantSwitchStateArea.pendingWrites =>
        blocker == TenantSwitchBlocker.pendingWrites,
      TenantSwitchStateArea.cashClose =>
        blocker == TenantSwitchBlocker.unfinishedCashCountOrShiftClose,
      TenantSwitchStateArea.workflow =>
        blocker == TenantSwitchBlocker.unsavedTenantWorkflow,
    };
  }
}

/// Explicit clean sources for the current safe landing route, which exposes no
/// checkout, mutation queue, cash-close, or editable tenant workflow.
List<TenantSwitchStateSource> safeLandingTenantSwitchStateSources({
  TenantSwitchStateSource? checkoutStateSource,
}) => <TenantSwitchStateSource>[
  checkoutStateSource ??
      const _ExplicitCleanTenantSwitchSource(TenantSwitchStateArea.checkout),
  _ExplicitCleanTenantSwitchSource(TenantSwitchStateArea.pendingWrites),
  _ExplicitCleanTenantSwitchSource(TenantSwitchStateArea.cashClose),
  _ExplicitCleanTenantSwitchSource(TenantSwitchStateArea.workflow),
];

final class _ExplicitCleanTenantSwitchSource
    implements TenantSwitchStateSource {
  const _ExplicitCleanTenantSwitchSource(this.area);

  @override
  final TenantSwitchStateArea area;

  @override
  Future<TenantSwitchInspection?> inspect(TenantSession session) async =>
      TenantSwitchInspection.clean(area: area, session: session);
}
