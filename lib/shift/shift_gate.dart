/// The till's shift gate: a shift is opened on the way into the sale screen
/// and closed on the way out of it.
///
/// **This is where the old app put it, and 2026-08-25 puts it back.** The
/// pre-multitenancy till (`lib/pos/pos.dart`) asked `_checkAndInitializeShift`
/// on entry and, finding none open, showed `_showStartShiftDialog` with
/// `barrierDismissible: false`; leaving it offered *Just Stepping Away* or
/// *End My Shift*. The Stitch redesign moved both onto the home as a card the
/// cashier had to notice, which is a step a person can walk past - and walking
/// past it means ringing up sales against no shift.
///
/// **The gate is a modal and it cannot be dismissed.** `showAppDialog` already
/// refuses the scrim; a `PopScope` refuses the system back gesture as well,
/// which the old dialog did not and which is how that one was escapable on
/// Android. The only ways out are opening a shift or leaving the till.
///
/// **It asks for no opening float, and that is a gap rather than a decision.**
/// The old dialog collected opening cash; `TenantShiftController.openShift`
/// takes none and `TenantShift` carries no such field, so a float box here
/// would be a control writing to nothing. Recorded in
/// `docs/stitch/OPEN_QUESTIONS.md` rather than invented.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/routes.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'shift_controller.dart';
import 'shift_panel.dart';

/// What a person chose on the way out of the till.
enum _ShiftExitChoice {
  /// Keep the shift open and go back to the home. The old dialog's *Just
  /// Stepping Away*.
  stepAway,

  /// Count the cash and close out. The old dialog's *End My Shift*.
  endShift,
}

/// Wraps the till so that selling is only possible inside an open shift.
final class TenantShiftGate extends StatefulWidget {
  const TenantShiftGate({
    super.key,
    required this.controllerFactory,
    required this.shiftManagerBuilder,
    required this.child,
  });

  /// Builds the controller against the live session, exactly as
  /// [TenantShiftPanel] does - the gate and the panel must never hold two
  /// different controllers for one session.
  final TenantShiftControllerFactory controllerFactory;

  /// The surface that counts cash and closes the shift, opened by *End my
  /// shift*.
  ///
  /// **Injected rather than built here** so the gate does not have to know
  /// what a close needs - the composition root already assembles the shift
  /// panel for exactly this, and duplicating that assembly is how the two come
  /// to disagree about which reader or currency a close uses.
  final WidgetBuilder shiftManagerBuilder;

  /// The till.
  final Widget child;

  @override
  State<TenantShiftGate> createState() => _TenantShiftGateState();
}

class _TenantShiftGateState extends State<TenantShiftGate> {
  TenantSessionController? _sessions;
  TenantShiftController? _shifts;

  /// Whether the blocking dialog is on screen, so a rebuild does not stack a
  /// second one on top of it.
  bool _gateUp = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sessions = TenantSessionScope.of(context);
    if (identical(sessions, _sessions) && _shifts != null) return;
    _sessions = sessions;
    // **Unsubscribed, not disposed.** The controller is the session's and
    // outlives this gate - see `shiftControllerFactory` - so disposing it here
    // would tear down the state the next entry is meant to start from.
    _shifts?.removeListener(_handleShiftChanged);
    final shifts = _shifts = widget.controllerFactory(sessions);
    shifts.addListener(_handleShiftChanged);
    // The canonical state, before the till draws anything that could be sold
    // against it. A session that is not open yet leaves the gate at `unknown`,
    // which draws the loading state rather than a sellable till.
    //
    // **A re-entry does not go back to `unknown`.** `restore` publishes only
    // when it has an answer, so a controller that already knows its phase keeps
    // drawing it while this read refreshes underneath - the till opens into
    // what it last knew and corrects itself, rather than flashing a spinner
    // between every sale.
    final session = sessions.session;
    if (session != null) unawaited(shifts.restore(session));
  }

  @override
  void dispose() {
    // The listener is this gate's; the controller is not. Leaving the till
    // keeps the shift state warm for the next entry, which is the whole point
    // of caching it.
    _shifts?.removeListener(_handleShiftChanged);
    super.dispose();
  }

  void _handleShiftChanged() {
    if (!mounted) return;
    setState(() {});
    // Raised from a listener rather than from `build`, because showing a route
    // during a build is the one thing `Navigator` refuses outright.
    WidgetsBinding.instance.addPostFrameCallback((_) => _raiseGateIfNeeded());
  }

  /// Puts the blocking dialog up when this session has no open shift.
  Future<void> _raiseGateIfNeeded() async {
    final shifts = _shifts;
    if (!mounted || shifts == null || _gateUp) return;
    if (shifts.state.phase != TenantShiftPhase.none) return;
    _gateUp = true;
    await showAppDialog<void>(
      context,
      builder: (dialogContext) => _ShiftGateDialog(shifts: shifts),
    );
    if (!mounted) return;
    _gateUp = false;
    // Dismissed without a shift means the person chose to leave rather than
    // sell, so the till goes with them.
    if (shifts.state.phase != TenantShiftPhase.open && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  /// The old till's exit dialog: keep the shift, or close it out.
  Future<void> _handleExit() async {
    final shifts = _shifts;
    if (!mounted) return;
    // Nothing to decide where no shift is open - the gate above is what the
    // person is looking at, and leaving it is simply leaving.
    //
    // **`unknown` leaves the same way, and that is a correction.** The exit
    // dialog says "Your shift is still open", which this device has no grounds
    // to claim when it has not established a shift at all; offering *End my
    // shift* against nothing was worse still. `expired` also leaves directly:
    // its own screen already offers the only action there is.
    if (shifts == null ||
        shifts.state.phase == TenantShiftPhase.none ||
        shifts.state.phase == TenantShiftPhase.unknown ||
        shifts.state.phase == TenantShiftPhase.expired) {
      Navigator.of(context).pop();
      return;
    }
    final choice = await showAppDialog<_ShiftExitChoice>(
      context,
      builder: (dialogContext) => const _ShiftExitDialog(),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _ShiftExitChoice.stepAway:
        Navigator.of(context).pop();
      case _ShiftExitChoice.endShift:
        await _openShiftManager();
        if (!mounted) return;
        // Back at the till: a closed shift means there is nothing left to sell
        // against, so the till leaves too rather than raising its own gate.
        if (_shifts?.state.phase != TenantShiftPhase.open && mounted) {
          Navigator.of(context).pop();
        }
    }
  }

  /// Opens the surface that counts the cash and closes the shift.
  ///
  /// Shared by the exit dialog's *End my shift* and by the expired screen,
  /// which has no other action.
  Future<void> _openShiftManager() async {
    final sessions = _sessions;
    if (sessions == null || !mounted) return;
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (routeContext) => TenantSessionScope(
          controller: sessions,
          child: Builder(builder: widget.shiftManagerBuilder),
        ),
      ),
    );
  }

  /// A page for the gate's own states to be drawn on.
  ///
  /// **Every one of them needed this and none of them had it.** The till
  /// supplies its own `Scaffold`; the four states drawn *instead* of the till
  /// supplied nothing, so their text rendered with no `Material` ancestor -
  /// which Flutter paints as yellow-underlined glyphs on a bare surface. It
  /// went unnoticed because the only state anybody looked at was `none`, and
  /// the *Start your shift* modal covers it.
  Widget _surface(Widget child, {Key? key}) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      key: key,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.s20),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shifts = _shifts;
    // **The expiry outranks the phase.** Starting a cash count moves an
    // expired shift to `closing`, and `closing` draws the till - so without
    // this a cashier could reopen the sheet, cancel, and keep selling past the
    // cap indefinitely.
    final phase = shifts != null && shifts.state.shiftExpired
        ? TenantShiftPhase.expired
        : shifts?.state.phase ?? TenantShiftPhase.unknown;
    return PopScope(
      // Every way out of the till goes through the exit dialog, including the
      // system back gesture.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_handleExit());
      },
      child: switch (phase) {
        // Nothing canonical *and* nothing on disk: the till is not drawn at
        // all rather than drawn against a shift nobody has confirmed.
        //
        // **This is now a rare and genuinely momentary state.** It used to be
        // where every offline entry landed, which made the message a lie -
        // nothing was being checked and nothing ever would be. The controller
        // publishes its durable record before it reads the server, so a device
        // that knows anything shows that instead.
        TenantShiftPhase.unknown => _surface(
          const LoadingState(
            key: ValueKey('shift-gate-loading'),
            message: 'Checking your shift.',
          ),
        ),
        // **Past the cap: no sale, and only one way out.** The shift is real
        // and still owns this device's unsettled sales, so this is not the
        // *no shift* empty state - there is nothing to open, only something to
        // close. Closing needs the server, which is stated rather than left
        // for the person to discover on a dead button.
        TenantShiftPhase.expired => _surface(
          key: const ValueKey('shift-gate-expired'),
          ErrorState(
            status: AppStatus.attention,
            badgeLabel: 'Shift over',
            statement:
                'This shift has been open for more than a day, so it can no '
                'longer take sales.',
            detail:
                'Counting it off needs a connection, because the totals are '
                'settled on the server.',
            stillTrue:
                'Every sale you have already recorded is saved and will be '
                'sent.',
            actions: <Widget>[
              AppButton(
                label: 'Close shift',
                tier: AppButtonTier.primary,
                onPressed: _openShiftManager,
              ),
            ],
          ),
        ),
        // **An empty state, not a spinner.** Nothing is loading here - the
        // answer arrived and it was *no shift* - so a turning indicator would
        // be saying something untrue about what the till is doing. It also
        // never stops turning, which is what left the screenshot harness
        // waiting for a frame that would not come.
        TenantShiftPhase.none => _surface(
          key: const ValueKey('shift-gate-blocked'),
          const EmptyState(
            title: 'No shift is open',
            hint: 'Open one to start selling.',
          ),
        ),
        TenantShiftPhase.unavailable => _surface(
          key: const ValueKey('shift-gate-unavailable'),
          Callout(
            status: AppStatus.problem,
            message:
                'Shift state could not be read, so this till stays closed. '
                'Check the connection and open the till again.',
          ),
        ),
        TenantShiftPhase.open || TenantShiftPhase.closing => widget.child,
      },
    );
  }
}

/// The blocking *Start your shift* modal.
final class _ShiftGateDialog extends StatefulWidget {
  const _ShiftGateDialog({required this.shifts});

  final TenantShiftController shifts;

  @override
  State<_ShiftGateDialog> createState() => _ShiftGateDialogState();
}

class _ShiftGateDialogState extends State<_ShiftGateDialog> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final state = await widget.shifts.openShift();
    if (!mounted) return;
    setState(() => _busy = false);
    if (state.phase == TenantShiftPhase.open) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final error = widget.shifts.state.errorCode;
    return PopScope(
      // §9 and the product rule both: this is the one modal in the app that a
      // back gesture must not clear, because clearing it would leave a till on
      // screen with no shift behind it.
      canPop: false,
      child: AppDialog(
        title: 'Start your shift',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Every sale is recorded against a shift, so this till opens one '
              'before it can sell.',
              style: tokens.typography.bodyLarge.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
            if (error != null) ...<Widget>[
              SizedBox(height: tokens.spacing.s16),
              Callout(
                key: const ValueKey('shift-gate-error'),
                status: AppStatus.problem,
                message: shiftErrorMessage(error),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          AppButton(
            key: const ValueKey('shift-gate-leave'),
            label: 'Leave',
            tier: AppButtonTier.secondary,
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
          AppButton(
            key: const ValueKey('shift-gate-open'),
            label: 'Open shift',
            tier: AppButtonTier.primary,
            loading: _busy,
            onPressed: _open,
          ),
        ],
      ),
    );
  }
}

/// The old till's two ways out.
final class _ShiftExitDialog extends StatelessWidget {
  const _ShiftExitDialog();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppDialog(
      title: 'Leaving the till',
      content: Text(
        'Your shift is still open. Keep it open if you are coming back, or '
        'count the cash and close it now.',
        style: tokens.typography.bodyLarge.copyWith(
          color: tokens.colors.text.secondary,
        ),
      ),
      actions: <Widget>[
        AppButton(
          key: const ValueKey('shift-exit-step-away'),
          // Shortened from the old dialog's 'Just stepping away' on
          // 2026-08-26: two verb phrases do not fit a phone's dialog side by
          // side, and the pair was rendering ellipsised. The old till's own
          // shape - two short answers on one row - is what this keeps.
          label: 'Step away',
          tier: AppButtonTier.secondary,
          onPressed: () => Navigator.of(context).pop(_ShiftExitChoice.stepAway),
        ),
        AppButton(
          key: const ValueKey('shift-exit-end'),
          label: 'End shift',
          tier: AppButtonTier.primary,
          onPressed: () => Navigator.of(context).pop(_ShiftExitChoice.endShift),
        ),
      ],
    );
  }
}
