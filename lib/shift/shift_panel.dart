import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import 'shift_controller.dart';
import 'shift_history_panel.dart';

/// Builds the shift controller for the session controller owned by the shell.
typedef TenantShiftControllerFactory =
    TenantShiftController Function(TenantSessionController sessions);

/// The guarded shift surface rendered on the tenant-safe landing route.
///
/// The panel owns one [TenantShiftController] per session controller and
/// rebuilds the surface for every canonical state change. Authorization,
/// stale-epoch rejection, and canonical reads all stay in the controller and
/// the route guard; this widget renders and dispatches only.
final class TenantShiftPanel extends StatefulWidget {
  const TenantShiftPanel({
    super.key,
    required this.controllerFactory,
    this.historyReader,
  });

  final TenantShiftControllerFactory controllerFactory;

  /// Supplied by the composition root to reach the read-only shift history.
  /// The route stays unreachable while it is absent.
  final TenantDataReader? historyReader;

  @override
  State<TenantShiftPanel> createState() => _TenantShiftPanelState();
}

final class _TenantShiftPanelState extends State<TenantShiftPanel> {
  final TextEditingController _countedCash = TextEditingController();
  TenantSessionController? _sessions;
  TenantShiftController? _shifts;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sessions = TenantSessionScope.of(context);
    if (identical(sessions, _sessions) && _shifts != null) return;
    _sessions = sessions;
    _shifts?.dispose();
    _shifts = widget.controllerFactory(sessions);
  }

  @override
  void dispose() {
    _shifts?.dispose();
    _countedCash.dispose();
    super.dispose();
  }

  /// Opens the read-only history under the same session scope, so the guard on
  /// that route sees the exact controller this panel was authorized against.
  void _openHistory(BuildContext context) {
    final reader = widget.historyReader;
    final sessions = _sessions;
    if (reader == null || sessions == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: sessions,
          child: TenantShiftHistoryScreen(reader: reader),
        ),
      ),
    );
  }

  Future<void> _dispatch(
    Future<TenantShiftState> Function(TenantShiftController shifts) action,
  ) async {
    final shifts = _shifts;
    if (shifts == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action(shifts);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shifts = _shifts!;
    return TenantRouteGuard<TenantShiftState>(
      load: shifts.restore,
      loading: const SizedBox.shrink(),
      denied: const SizedBox.shrink(),
      failure: (context, error) =>
          const Text('Shift state is unavailable on this device.'),
      builder: (context, session, initial) => ListenableBuilder(
        listenable: shifts,
        builder: (context, _) => _ShiftContents(
          state: shifts.state.phase == TenantShiftPhase.unknown
              ? initial
              : shifts.state,
          busy: _busy,
          countedCash: _countedCash,
          onViewHistory: widget.historyReader == null
              ? null
              : () => _openHistory(context),
          onRefresh: () => _dispatch((shifts) => shifts.restore(session)),
          onOpen: () => _dispatch((shifts) => shifts.openShift()),
          onStartCashCount: () =>
              _dispatch((shifts) => shifts.startCashCount()),
          onCancelCashCount: () =>
              _dispatch((shifts) => shifts.cancelCashCount()),
          onClose: () {
            // A non-numeric or empty count is refused by the controller rather
            // than silently closing a shift with a guessed amount.
            final counted = int.tryParse(_countedCash.text.trim()) ?? -1;
            _dispatch((shifts) => shifts.closeShift(countedCashMinor: counted));
          },
        ),
      ),
    );
  }
}

final class _ShiftContents extends StatelessWidget {
  const _ShiftContents({
    required this.state,
    required this.busy,
    required this.countedCash,
    required this.onViewHistory,
    required this.onRefresh,
    required this.onOpen,
    required this.onStartCashCount,
    required this.onCancelCashCount,
    required this.onClose,
  });

  final TenantShiftState state;
  final bool busy;
  final TextEditingController countedCash;
  final VoidCallback? onViewHistory;
  final VoidCallback onRefresh;
  final VoidCallback onOpen;
  final VoidCallback onStartCashCount;
  final VoidCallback onCancelCashCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('tenant-shift-panel'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Shift', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      Text(key: const ValueKey('shift-status'), _statusLabel()),
      if (state.otherTenantShiftOpen)
        const Text(
          key: ValueKey('shift-other-tenant-open'),
          'Another business still has an open shift on this device.',
        ),
      if (state.otherDeviceShiftOpen)
        const Text(
          key: ValueKey('shift-other-device-open'),
          'Your shift in this business is open on another device. Close it '
          'there before opening a shift here.',
        ),
      if (state.sales != null)
        Text(
          key: const ValueKey('shift-sales-summary'),
          'Confirmed sales: ${state.sales!.transactionCount} transactions, '
          '${state.sales!.totalMinor} minor units.',
        ),
      if (state.errorCode != null)
        Text(key: const ValueKey('shift-error'), _errorLabel()),
      const SizedBox(height: 8),
      if (state.phase == TenantShiftPhase.closing) ...[
        TextField(
          key: const ValueKey('counted-cash'),
          controller: countedCash,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Counted cash (minor units)',
          ),
        ),
        const SizedBox(height: 8),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (state.phase == TenantShiftPhase.none)
            FilledButton(
              key: const ValueKey('open-shift'),
              onPressed: busy ? null : onOpen,
              child: const Text('Open shift'),
            ),
          if (state.phase == TenantShiftPhase.open)
            FilledButton(
              key: const ValueKey('start-cash-count'),
              onPressed: busy ? null : onStartCashCount,
              child: const Text('Start cash count'),
            ),
          if (state.phase == TenantShiftPhase.closing) ...[
            FilledButton(
              key: const ValueKey('close-shift'),
              onPressed: busy ? null : onClose,
              child: const Text('Close shift'),
            ),
            OutlinedButton(
              key: const ValueKey('cancel-cash-count'),
              onPressed: busy ? null : onCancelCashCount,
              child: const Text('Cancel cash count'),
            ),
          ],
          OutlinedButton(
            key: const ValueKey('refresh-shift'),
            onPressed: busy ? null : onRefresh,
            child: const Text('Refresh shift'),
          ),
          if (onViewHistory != null)
            OutlinedButton(
              key: const ValueKey('view-shift-history'),
              onPressed: busy ? null : onViewHistory,
              child: const Text('View shift history'),
            ),
        ],
      ),
    ],
  );

  String _statusLabel() => switch (state.phase) {
    TenantShiftPhase.unknown => 'Shift state has not been confirmed yet.',
    TenantShiftPhase.none => 'No shift is open in this business.',
    TenantShiftPhase.open => 'A shift is open in this business.',
    TenantShiftPhase.closing =>
      'A cash count is unfinished. Finish it before switching business.',
    TenantShiftPhase.unavailable => 'Shift state is unavailable.',
  };

  String _errorLabel() => switch (state.errorCode) {
    'offline' => 'This device is offline, so shift state was not confirmed.',
    'other_tenant_shift_open' =>
      'Close the open shift in the other business first.',
    'shift_open_on_other_device' =>
      'This shift is open on another device. Close it there first.',
    'unsynchronized_shift_sales' =>
      'Some sales in this shift are not synchronized yet. Wait for them '
          'before closing.',
    'shift_already_open' => 'A shift is already open on this device.',
    'no_open_shift' => 'No shift is open to count or close.',
    'cash_count_not_started' => 'Start the cash count before closing.',
    'invalid_closing_cash' => 'Enter the counted cash before closing.',
    'session_changed' => 'The selected business changed.',
    _ => 'The last shift action could not be confirmed.',
  };
}
