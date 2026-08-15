import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/routes.dart';
import '../checkout/checkout_tender.dart';
import '../returns/return_actions.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import 'shift_controller.dart';
import 'shift_history_panel.dart';
import 'shift_sales_ledger.dart';

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
    this.returnActions,
  });

  final TenantShiftControllerFactory controllerFactory;

  /// Supplied by the composition root to reach the read-only shift history.
  /// The route stays unreachable while it is absent.
  final TenantDataReader? historyReader;

  /// Supplied by the composition root and passed through the history and sales
  /// routes to the returns route. Recording a return stays unavailable while it
  /// is absent, so every one of those routes remains read-only.
  final TenantReturnActions? returnActions;

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
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: sessions,
          child: TenantShiftHistoryScreen(
            reader: reader,
            returnActions: widget.returnActions,
          ),
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
      if (state.sales case final sales?) ...[
        Text(
          key: const ValueKey('shift-sales-summary'),
          'Confirmed sales: ${sales.transactionCount} '
          '${sales.transactionCount == 1 ? 'transaction' : 'transactions'}, '
          '${sales.totalMinor} minor '
          '${sales.totalMinor == 1 ? 'unit' : 'units'}.',
        ),
        // Stated here rather than only after the close is refused. A real run
        // found this surface reporting "Confirmed sales: 0" beside a drawer
        // holding two unsynchronized sales, and saying nothing about them
        // until the cashier pressed Close and got a message back.
        if (!sales.isComplete)
          Text(
            key: const ValueKey('shift-unsettled-sales'),
            '${sales.unsettledCount} '
            '${sales.unsettledCount == 1 ? 'sale' : 'sales'} on this device '
            '${sales.unsettledCount == 1 ? 'is' : 'are'} not synchronized yet '
            'and none of the figures here include '
            '${sales.unsettledCount == 1 ? 'it' : 'them'}. The shift cannot be '
            'closed until they are.',
          ),
        // The expected cash waits for a complete shift. Until every sale is
        // accounted for the figure is not a smaller truth, it is a number the
        // drawer will not match - which is exactly what the run showed.
        //
        // A split that does not sum to the takings just stated is refused for
        // the same reason: the cash figure is what a drawer is measured
        // against, so a wrong one becomes an accusation about the person
        // counting it.
        if (sales.isComplete && sales.tendersDescribeTakings)
          _ExpectedCash(split: sales.tenders),
      ],
      if (state.errorCode != null)
        Text(key: const ValueKey('shift-error'), _errorLabel()),
      const SizedBox(height: 8),
      if (state.phase == TenantShiftPhase.closing) ...[
        AppTextField(
          key: const ValueKey('counted-cash'),
          controller: countedCash,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          label: 'Counted cash (minor units)',
          leading: Icons.payments_outlined,
        ),
        const SizedBox(height: 8),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (state.phase == TenantShiftPhase.none)
            AppButton(
              key: const ValueKey('open-shift'),
              label: 'Open shift',
              tier: AppButtonTier.primary,
              onPressed: busy ? null : onOpen,
            ),
          if (state.phase == TenantShiftPhase.open)
            AppButton(
              key: const ValueKey('start-cash-count'),
              label: 'Start cash count',
              tier: AppButtonTier.primary,
              onPressed: busy ? null : onStartCashCount,
            ),
          if (state.phase == TenantShiftPhase.closing) ...[
            AppButton(
              key: const ValueKey('close-shift'),
              label: 'Close shift',
              tier: AppButtonTier.primary,
              onPressed: busy ? null : onClose,
            ),
            AppButton(
              key: const ValueKey('cancel-cash-count'),
              label: 'Cancel cash count',
              onPressed: busy ? null : onCancelCashCount,
            ),
          ],
          AppButton(
            key: const ValueKey('refresh-shift'),
            label: 'Refresh shift',
            onPressed: busy ? null : onRefresh,
          ),
          if (onViewHistory != null)
            AppButton(
              key: const ValueKey('view-shift-history'),
              label: 'View shift history',
              onPressed: busy ? null : onViewHistory,
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

/// What the drawer should hold, beside the count the cashier is entering.
///
/// Only the cash bucket is shown. This is the surface for counting a drawer,
/// and no other payment method ever entered it; the confirmed-sales line above
/// already says what the whole shift came to. It appears with that line, which
/// is exactly while a cash count is unfinished.
///
/// A shift with no cash sales still shows the figure rather than hiding it: a
/// cashier counting a drawer needs to be told to expect nothing just as much as
/// to expect something, and an absent line reads as an unanswered question.
final class _ExpectedCash extends StatelessWidget {
  const _ExpectedCash({required this.split});

  final ShiftTenderSplit split;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        key: const ValueKey('shift-expected-cash'),
        'Expected cash: ${split.cash.totalMinor} minor '
        '${split.cash.totalMinor == 1 ? 'unit' : 'units'} over '
        '${split.cash.transactionCount} '
        '${split.cash.transactionCount == 1 ? 'sale' : 'sales'}.',
      ),
      // Money the device holds but cannot attribute is stated rather than
      // silently left out, because the figure above is the one a drawer is
      // measured against and a quiet exclusion would present as a shortfall.
      if (!split.unattributed.isEmpty)
        Text(
          key: const ValueKey('shift-unattributed-tender'),
          '${split.unattributed.transactionCount} '
          '${split.unattributed.transactionCount == 1 ? 'sale names' : 'sales name'} '
          'no recognised payment method, worth '
          '${split.unattributed.totalMinor} minor '
          '${split.unattributed.totalMinor == 1 ? 'unit' : 'units'}. '
          '${split.unattributed.transactionCount == 1 ? 'It is' : 'They are'} '
          'inside the confirmed sales above but not in the expected cash.',
        ),
      if (split.hasRecordedTenders)
        const Text(
          key: ValueKey('shift-tender-disclaimer'),
          checkoutTenderDisclaimer,
        ),
    ],
  );
}
