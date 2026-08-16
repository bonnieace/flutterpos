import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../checkout/checkout_tender.dart';
import '../returns/return_actions.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/banner.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/routes.dart';
import '../ui/sheet.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
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

  /// Which of design.md 2.1's five this shift's standing is.
  ///
  /// **A shift is never `info`**, and it is `neutral` only when there is none -
  /// which is why this maps five phases onto three statuses rather than
  /// enumerating `AppStatus`. An unconfirmed or unavailable shift is
  /// `attention`: something is owed, and it is a reading rather than a failure.
  AppStatus get _status => switch (state.phase) {
    TenantShiftPhase.none => AppStatus.neutral,
    TenantShiftPhase.open =>
      _warning == null ? AppStatus.ok : AppStatus.attention,
    TenantShiftPhase.closing => AppStatus.attention,
    TenantShiftPhase.unknown ||
    TenantShiftPhase.unavailable => AppStatus.attention,
  };

  /// The standing in words, which 9 requires beside the colour.
  String get _heading => switch (state.phase) {
    TenantShiftPhase.none => 'No shift open',
    TenantShiftPhase.open => 'Shift open',
    TenantShiftPhase.closing => 'Cash count unfinished',
    TenantShiftPhase.unknown => 'Shift not confirmed',
    TenantShiftPhase.unavailable => 'Shift unavailable',
  };

  /// The one thing louder than the routine detail, or null.
  ///
  /// **A warning promotes the detail line**, which is the decision that keeps a
  /// one-line banner honest. `PLAN.md` records a real device run where this
  /// surface reported "Confirmed sales: 0" beside a drawer holding two
  /// unsynchronized sales, and said nothing about them until the cashier
  /// pressed Close - so a shift with money unaccounted for says *that* rather
  /// than its takings, and the status turns `attention` with it.
  String? get _warning {
    if (state.errorCode != null) return _errorLabel();
    if (state.otherTenantShiftOpen) {
      return 'Another business still has an open shift on this device.';
    }
    if (state.otherDeviceShiftOpen) {
      return 'Your shift in this business is open on another device. Close it '
          'there before opening a shift here.';
    }
    final sales = state.sales;
    if (sales != null && !sales.isComplete) {
      return '${sales.unsettledCount} '
          '${sales.unsettledCount == 1 ? 'sale' : 'sales'} on this device '
          '${sales.unsettledCount == 1 ? 'is' : 'are'} not synchronized yet '
          'and none of the figures here include '
          '${sales.unsettledCount == 1 ? 'it' : 'them'}. The shift cannot be '
          'closed until they are.';
    }
    return null;
  }

  /// What the banner says when there is nothing louder.
  String get _detail {
    final loud = _warning;
    if (loud != null) return loud;
    final sales = state.sales;
    if (sales != null) {
      return 'Confirmed sales: ${sales.transactionCount} '
          '${sales.transactionCount == 1 ? 'transaction' : 'transactions'}, '
          '${sales.totalMinor} minor '
          '${sales.totalMinor == 1 ? 'unit' : 'units'}.';
    }
    return _statusLabel();
  }

  /// The next step in the shift's lifecycle, and only that.
  ///
  /// **Exactly one action, chosen by the product owner on 2026-08-16**: the
  /// banner always offers the step forward - *Open shift*, *Start cash count*,
  /// *Close shift* - and the reversal, *Cancel cash count*, lives in the sheet.
  /// 1 argues for that separation: a reversal beside the thing it reverses is
  /// one mis-tap from undoing work somebody has just done.
  ///
  /// **In `closing` the action opens the sheet rather than closing outright**,
  /// which is the consequence of the counted-cash field living there. 8 rule 4
  /// makes it read correctly - the verb persists, so the banner says *Close
  /// shift* and so does the control inside the sheet that finishes it.
  Widget? _action(BuildContext context) => switch (state.phase) {
    TenantShiftPhase.none => AppButton(
      key: const ValueKey('open-shift'),
      label: 'Open shift',
      tier: AppButtonTier.primary,
      onPressed: busy ? null : onOpen,
    ),
    TenantShiftPhase.open => AppButton(
      key: const ValueKey('start-cash-count'),
      label: 'Start cash count',
      tier: AppButtonTier.primary,
      onPressed: busy ? null : onStartCashCount,
    ),
    TenantShiftPhase.closing => AppButton(
      key: const ValueKey('close-shift'),
      label: 'Close shift',
      tier: AppButtonTier.primary,
      onPressed: busy ? null : () => _openSheet(context),
    ),
    TenantShiftPhase.unknown || TenantShiftPhase.unavailable => null,
  };

  Future<void> _openSheet(BuildContext context) => showAppSheet<void>(
    context,
    builder: (sheetContext, controller) => ListView(
      controller: controller,
      padding: EdgeInsets.all(AppTokens.componentOf(sheetContext).spacing.s20),
      children: <Widget>[_ShiftSheet(panel: this, sheetContext: sheetContext)],
    ),
  );

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const ValueKey('tenant-shift-panel'),
    child: ShiftBanner(
      status: _status,
      heading: _heading,
      detail: _detail,
      action: _action(context),
      onOpenDetails: busy ? null : () => _openSheet(context),
    ),
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

/// What the banner does not carry: the count itself, the reversal, and the two
/// controls that are available whatever the shift is doing.
///
/// **The counted-cash field lives here at the product owner's direction**, taken
/// on 2026-08-16 against the alternative of growing the banner a field in
/// `closing`. It makes closing a two-surface operation, which is the stated
/// cost; what it buys is a banner that is one row in every state.
final class _ShiftSheet extends StatelessWidget {
  const _ShiftSheet({required this.panel, required this.sheetContext});

  final _ShiftContents panel;
  final BuildContext sheetContext;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final state = panel.state;
    final sales = state.sales;
    return Column(
      key: const ValueKey('tenant-shift-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Shift',
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s4),
        Text(
          key: const ValueKey('shift-status'),
          panel._statusLabel(),
          style: tokens.density
              .body(tokens.typography)
              .copyWith(color: tokens.colors.text.secondary),
        ),
        // The expected cash waits for a complete shift. Until every sale is
        // accounted for the figure is not a smaller truth, it is a number the
        // drawer will not match.
        if (sales != null &&
            sales.isComplete &&
            sales.tendersDescribeTakings) ...[
          SizedBox(height: tokens.spacing.s12),
          _ExpectedCash(split: sales.tenders),
        ],
        if (state.phase == TenantShiftPhase.closing) ...[
          SizedBox(height: tokens.spacing.s16),
          AppTextField(
            key: const ValueKey('counted-cash'),
            controller: panel.countedCash,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            label: 'Counted cash (minor units)',
            leading: Icons.payments_outlined,
          ),
        ],
        SizedBox(height: tokens.spacing.s16),
        Wrap(
          spacing: tokens.spacing.s8,
          runSpacing: tokens.spacing.s8,
          children: [
            if (state.phase == TenantShiftPhase.closing) ...[
              // 8 rule 4: the verb persists from the banner to here.
              AppButton(
                key: const ValueKey('close-shift-confirm'),
                label: 'Close shift',
                tier: AppButtonTier.primary,
                onPressed: panel.busy ? null : _close,
              ),
              AppButton(
                key: const ValueKey('cancel-cash-count'),
                label: 'Cancel cash count',
                onPressed: panel.busy ? null : _cancel,
              ),
            ],
            AppButton(
              key: const ValueKey('refresh-shift'),
              label: 'Refresh shift',
              onPressed: panel.busy ? null : panel.onRefresh,
            ),
            if (panel.onViewHistory != null)
              AppButton(
                key: const ValueKey('view-shift-history'),
                label: 'View shift history',
                onPressed: panel.busy ? null : _history,
              ),
          ],
        ),
      ],
    );
  }

  /// Closes the sheet before acting, so the answer lands on the banner rather
  /// than behind the surface a person opened to get here.
  void _close() {
    panel.onClose();
    Navigator.of(sheetContext).pop();
  }

  void _cancel() {
    panel.onCancelCashCount();
    Navigator.of(sheetContext).pop();
  }

  void _history() {
    Navigator.of(sheetContext).pop();
    panel.onViewHistory!();
  }
}
