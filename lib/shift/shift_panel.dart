import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../checkout/checkout_tender.dart';
import '../inventory/catalog_management.dart';
import '../reporting/reporting_currency.dart';
import '../returns/return_actions.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/banner.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
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
    required this.currency,
    required this.controllerFactory,
    this.historyReader,
    this.returnActions,
  });

  /// What this business calls its money, so the shift states amounts the way
  /// every other surface in this app does rather than in raw minor units.
  final TenantReportingCurrency currency;

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

  /// Opens the shift sheet, and owns the cash count for as long as it is up.
  ///
  /// **Opening is what starts the count**, which is the whole of the product
  /// owner's 2026-08-23 change: the cashier's journey is one tap to the sheet
  /// and one tap to finish, rather than a tap to start a count, a card state
  /// nobody asked for, and a tap to open the sheet after it.
  ///
  /// The sheet refuses the scrim while a count is running, so the count cannot
  /// be lost to a stray swipe. A system back gesture can still pop it, so a
  /// dismissal that reports nothing cancels the count on the way out - which
  /// leaves the till in service rather than silently out of it.
  Future<void> _openShiftSheet(TenantSession session) async {
    final shifts = _shifts;
    if (shifts == null || _busy) return;
    // An expired shift needs the count started exactly as an open one does -
    // closing is the only thing left to do with it, and without this the sheet
    // would open on a shift with no count running and refuse the close.
    if (shifts.state.phase == TenantShiftPhase.open ||
        shifts.state.phase == TenantShiftPhase.expired) {
      await _dispatch((s) => s.startCashCount());
      if (!mounted) return;
    }
    final handled = await showAppSheet<bool>(
      // The `State`'s own context, so the `mounted` check above is the guard
      // that actually covers it across the await that starts the count.
      context,
      dismissible: shifts.state.phase != TenantShiftPhase.closing,
      builder: (sheetContext, controller) => ListenableBuilder(
        listenable: shifts,
        builder: (context, _) => ListView(
          controller: controller,
          padding: EdgeInsets.all(
            AppTokens.componentOf(sheetContext).spacing.s20,
          ),
          children: <Widget>[
            _ShiftSheet(
              state: shifts.state,
              busy: _busy,
              countedCash: _countedCash,
              currency: widget.currency,
              onClose: () {
                // **Typed as money, stored as minor units.** The field takes
                // what the drawer holds - `1250.50` - and this converts it
                // through the same function the till and the catalog use, so
                // an amount this surface accepts is one the close can record
                // exactly. A spelling that is not money at all becomes -1,
                // which the controller refuses as `invalid_closing_cash`
                // rather than closing a shift on a guess.
                _dispatch(
                  (s) => s.closeShift(countedCashMinor: _countedCashMinor()),
                );
              },
              onCancelCashCount: () => _dispatch((s) => s.cancelCashCount()),
              onRefresh: () => _dispatch((s) => s.restore(session)),
              onViewHistory: widget.historyReader == null
                  ? null
                  : () => _openHistory(context),
              sheetContext: sheetContext,
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (handled != true && shifts.state.phase == TenantShiftPhase.closing) {
      await _dispatch((s) => s.cancelCashCount());
    }
  }

  /// The counted drawer in minor units, or -1 where it is not an amount.
  int _countedCashMinor() {
    try {
      return tenantCatalogPriceMinorUnits(_countedCash.text);
    } on TenantCatalogManagementException {
      return -1;
    }
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
          currency: widget.currency,
          onOpenShift: () => _dispatch((shifts) => shifts.openShift()),
          onOpenSheet: () => _openShiftSheet(session),
        ),
      ),
    );
  }
}

final class _ShiftContents extends StatelessWidget {
  const _ShiftContents({
    required this.state,
    required this.busy,
    required this.currency,
    required this.onOpenShift,
    required this.onOpenSheet,
  });

  final TenantShiftState state;
  final bool busy;
  final TenantReportingCurrency currency;

  /// Opens the shift outright. Nothing is collected to open one.
  final VoidCallback onOpenShift;

  /// Opens the shift sheet, which is also what starts the cash count.
  final VoidCallback onOpenSheet;

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
    // `attention` rather than `problem`: a shift that ran long is owed a
    // close, which is something to do rather than something broken.
    TenantShiftPhase.expired => AppStatus.attention,
    TenantShiftPhase.unknown ||
    TenantShiftPhase.unavailable => AppStatus.attention,
  };

  /// The standing in words, which 9 requires beside the colour.
  String get _heading => switch (state.phase) {
    TenantShiftPhase.none => 'No shift open',
    TenantShiftPhase.open => 'Shift open',
    TenantShiftPhase.closing => 'Cash count unfinished',
    TenantShiftPhase.expired => 'Shift open too long',
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
    // **Louder than the takings, and readable mid-shift.** A shift holding
    // sales this device has not settled cannot be closed, and a cashier who
    // learns that only after pressing `Close shift` has already counted the
    // drawer. The sheet states it too, beside the control it blocks.
    final sales = state.sales;
    if (sales != null && !sales.isComplete) {
      return _unsynchronizedSalesLabel(sales);
    }
    return null;
  }

  /// What the banner says when there is nothing louder.
  String get _detail {
    final loud = _warning;
    if (loud != null) return loud;
    // **The running shift's takings, readable without starting a count.**
    // This briefly said nothing, back when the summary was only computed
    // during a count and there was genuinely nothing to draw. The controller
    // summarizes any open shift now, so the figure a cashier wants mid-shift
    // is on the home rather than behind a count they have to cancel out of.
    final sales = state.sales;
    if (sales != null) return _confirmedSalesLabel(sales, currency);
    return _statusLabel();
  }

  /// The shift's one control, and only that.
  ///
  /// **Two states, chosen by the product owner on 2026-08-23**: *Open shift*
  /// when there is none and *Close shift* when there is one. The third state
  /// this used to have - *Start cash count*, then a separate *Cash count
  /// unfinished* card offering *Close shift* - is gone: starting a count is
  /// not a step a cashier takes, it is what opening the sheet does.
  ///
  /// **Only closing opens the sheet.** Both did briefly, and opening a shift
  /// through a sheet that collected nothing was two taps for a one-tap action
  /// - the product owner called it on 2026-08-23 and was right. Closing keeps
  /// the sheet because the counted cash has to be typed somewhere.
  ///
  /// `closing` maps to the same control as `open`. It is unreachable from the
  /// card now, because the only thing that sets it is the sheet that covers
  /// the card, and a restart discards it - but a phase this file cannot draw
  /// is worse than one it draws the same as its neighbour.
  Widget? _action(BuildContext? context) => switch (state.phase) {
    TenantShiftPhase.none => AppButton(
      key: const ValueKey('open-shift'),
      label: 'Open shift',
      icon: Icons.lock_open,
      tier: AppButtonTier.secondary,
      expand: true,
      onPressed: busy ? null : onOpenShift,
    ),
    // An expired shift offers the same control, and it is the only one it
    // offers: closing is the single thing left to do with it.
    TenantShiftPhase.open ||
    TenantShiftPhase.closing ||
    TenantShiftPhase.expired => AppButton(
      key: const ValueKey('close-shift'),
      label: 'Close shift',
      icon: Icons.lock_outline,
      tier: AppButtonTier.secondary,
      expand: true,
      onPressed: busy ? null : onOpenSheet,
    ),
    TenantShiftPhase.unknown || TenantShiftPhase.unavailable => null,
  };

  /// Whether this shift has something to say beyond its own standing.
  ///
  /// **A card, or a button.** The design's dashboard draws the shift as one
  /// full-width control under the till - `[ Start New Sale ] [ Open Shift ]` -
  /// and says nothing else about it, because the *count* of open shifts is one
  /// of the figures in the grid above. That is right for the ordinary case and
  /// wrong for the ones this panel exists for: money unaccounted for, a shift
  /// open on another device, a cash count half done. Those are the [_warning]
  /// cases, and they keep the card.
  bool get _speaks =>
      _warning != null ||
      _status == AppStatus.attention ||
      _action(null) == null ||
      // **Takings are a reason to speak.** The rule this list encodes is that
      // a banner must not restate its own button - *SHIFT OPEN* over *Close
      // shift* is one fact twice. A figure is not that: what this shift has
      // taken so far is the thing a cashier opens the home to read, and it is
      // not derivable from the control beside it. A shift that has sold
      // nothing yet still has nothing to say, and keeps the bare button.
      (state.sales?.transactionCount ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final action = _action(context);
    return KeyedSubtree(
      key: const ValueKey('tenant-shift-panel'),
      // **A bare button when there is nothing to report**, which is the
      // product owner's direction of 2026-08-23 and the design's own shape. A
      // banner announcing *SHIFT OPEN — a shift is open in this business* over
      // a button that says `Start cash count` is the same fact three times.
      child: !_speaks && action != null
          // **The `Shift details` link is gone, on the product owner's call
          // of 2026-08-23.** It existed because the card's control did
          // something other than open the sheet, so the sheet needed a way in
          // of its own. Both controls open the sheet now, and a second link
          // to the surface the button beside it already opens is a choice
          // between two spellings of one thing.
          ? action
          : ShiftBanner(
              status: _status,
              heading: _heading,
              detail: _detail,
              action: action,
            ),
    );
  }

  String _statusLabel() => _shiftStatusLabel(state.phase);

  String _errorLabel() => shiftErrorMessage(state.errorCode);
}

/// What a shift refusal says to the person who caused it.
///
/// **Public and shared since 2026-08-25**, when the till's shift gate began
/// reporting the same refusals this card does. A second copy would be a second
/// set of words for one server answer, and the two would drift the first time
/// either was reworded.
String shiftErrorMessage(String? code) => switch (code) {
  'offline' =>
    'This device is offline, so this shift has not been re-confirmed with the '
        'server. You can keep selling.',
  'close_needs_connection' =>
    'Closing a shift needs a connection, because its totals are settled on the '
        'server.',
  'shift_expired_offline' =>
    'This shift has been open more than a day and must be closed, which needs '
        'a connection.',
  'shift_open_unconfirmed' =>
    'This shift has not reached the server yet. It and its sales are saved '
        'here and will be sent.',
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
  const _ExpectedCash({required this.split, required this.currency});

  final ShiftTenderSplit split;
  final TenantReportingCurrency currency;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        key: const ValueKey('shift-expected-cash'),
        'Expected cash: ${currency.format(split.cash.totalMinor / 100)} over '
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
          '${currency.format(split.unattributed.totalMinor / 100)}. '
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
/// What this device can prove the shift took, worded once for both surfaces.
///
/// **Money, not minor units.** Every figure this panel drew was an integer
/// count of the smallest coin - `98750 minor units` where the rest of the app
/// writes `KES 987.50` - which is the app's own arithmetic leaking onto a
/// surface a cashier reads against a drawer.
String _confirmedSalesLabel(
  ShiftSalesSummary sales,
  TenantReportingCurrency currency,
) =>
    'Confirmed sales: ${sales.transactionCount} '
    '${sales.transactionCount == 1 ? 'transaction' : 'transactions'}, '
    '${currency.format(sales.totalMinor / 100)}.';

/// The sales this device holds but has not yet settled with the server.
String _unsynchronizedSalesLabel(ShiftSalesSummary sales) =>
    '${sales.unsettledCount} '
    '${sales.unsettledCount == 1 ? 'sale' : 'sales'} on this device '
    '${sales.unsettledCount == 1 ? 'is' : 'are'} not synchronized yet '
    'and none of the figures here include '
    '${sales.unsettledCount == 1 ? 'it' : 'them'}. The shift cannot be '
    'closed until they are.';

/// The one sentence describing where a shift stands.
String _shiftStatusLabel(TenantShiftPhase phase) => switch (phase) {
  TenantShiftPhase.unknown => 'Shift state has not been confirmed yet.',
  TenantShiftPhase.none => 'No shift is open in this business.',
  TenantShiftPhase.open => 'A shift is open in this business.',
  TenantShiftPhase.closing =>
    'A cash count is unfinished. Finish it before switching business.',
  TenantShiftPhase.expired =>
    'A shift has been open more than a day. Close it before switching '
        'business.',
  TenantShiftPhase.unavailable => 'Shift state is unavailable.',
};

/// Everything about a shift that is not its standing.
///
/// **The sheet owns the cash count for exactly as long as it is open.** It is
/// opened with the count already started, and whoever opened it ends the count
/// on the way out - see `_TenantShiftPanelState._openShiftSheet`. That is why
/// there is no `Start cash count` here or on the card: the count is not a step
/// a cashier takes, it is the state of having this surface open.
///
/// It takes its state directly rather than through the card, because the card
/// is a different element on a different route and does not rebuild this one.
final class _ShiftSheet extends StatelessWidget {
  const _ShiftSheet({
    required this.state,
    required this.busy,
    required this.countedCash,
    required this.currency,
    required this.onClose,
    required this.onCancelCashCount,
    required this.onRefresh,
    required this.onViewHistory,
    required this.sheetContext,
  });

  final TenantShiftState state;
  final bool busy;
  final TextEditingController countedCash;
  final TenantReportingCurrency currency;
  final VoidCallback onClose;
  final VoidCallback onCancelCashCount;
  final VoidCallback onRefresh;
  final VoidCallback? onViewHistory;
  final BuildContext sheetContext;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final sales = state.sales;
    final counting = state.phase == TenantShiftPhase.closing;
    return Column(
      key: const ValueKey('tenant-shift-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeading('Shift'),
        SizedBox(height: tokens.spacing.s4),
        Text(
          key: const ValueKey('shift-status'),
          _shiftStatusLabel(state.phase),
          style: tokens.density
              .body(tokens.typography)
              .copyWith(color: tokens.colors.text.secondary),
        ),
        // **The confirmed-sales line moved here on 2026-08-23**, with the
        // count itself. It used to be the card's detail while `closing`, and
        // the card no longer has that phase: the only time this is known is
        // while the sheet that asked for it is open.
        if (sales != null) ...[
          SizedBox(height: tokens.spacing.s4),
          Text(
            key: const ValueKey('shift-confirmed-sales'),
            _confirmedSalesLabel(sales, currency),
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.text.secondary),
          ),
        ],
        // **The blocker on closing, beside the control it blocks.** A real
        // device run found this surface silent about unsynchronized sales
        // until `Close shift` failed; it was the card's warning, and the card
        // is behind this sheet for the whole of a count.
        if (sales != null && !sales.isComplete) ...[
          SizedBox(height: tokens.spacing.s4),
          Text(
            key: const ValueKey('shift-unsynchronized-sales'),
            _unsynchronizedSalesLabel(sales),
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.status.attention.fg),
          ),
        ],
        // The expected cash waits for a complete shift. Until every sale is
        // accounted for the figure is not a smaller truth, it is a number the
        // drawer will not match.
        if (sales != null &&
            sales.isComplete &&
            sales.tendersDescribeTakings) ...[
          SizedBox(height: tokens.spacing.s12),
          _ExpectedCash(split: sales.tenders, currency: currency),
        ],
        if (counting) ...[
          SizedBox(height: tokens.spacing.s16),
          AppTextField(
            key: const ValueKey('counted-cash'),
            controller: countedCash,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            label: 'Counted cash',
            leading: Icons.payments_outlined,
          ),
        ],
        SizedBox(height: tokens.spacing.s16),
        Wrap(
          spacing: tokens.spacing.s8,
          runSpacing: tokens.spacing.s8,
          children: [
            if (counting) ...[
              // 8 rule 4: the verb persists from the card to here.
              AppButton(
                key: const ValueKey('close-shift-confirm'),
                label: 'Close shift',
                tier: AppButtonTier.primary,
                onPressed: busy ? null : _closeShift,
              ),
              // **The only way out while a count is running, and deliberately
              // so.** The sheet is not dismissible in this phase, because a
              // swipe that discarded a half-counted drawer and quietly put the
              // till back into service is exactly the mis-tap this panel has
              // always refused to allow.
              AppButton(
                key: const ValueKey('cancel-cash-count'),
                label: 'Cancel cash count',
                onPressed: busy ? null : _cancel,
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
                onPressed: busy ? null : _history,
              ),
          ],
        ),
      ],
    );
  }

  /// Closes the sheet before acting, so the answer lands on the card rather
  /// than behind the surface a person opened to get here.
  /// Every deliberate exit pops `true`, which tells the opener that the count
  /// has been dealt with. A `null` result is a dismissal - a back gesture can
  /// still pop a sheet that refuses the scrim - and is what the opener cancels
  /// the count on.
  void _closeShift() {
    Navigator.of(sheetContext).pop(true);
    onClose();
  }

  void _cancel() {
    Navigator.of(sheetContext).pop(true);
    onCancelCashCount();
  }

  void _history() {
    Navigator.of(sheetContext).pop(true);
    onViewHistory!();
  }
}
