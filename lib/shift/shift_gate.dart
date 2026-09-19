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
/// **It asks for the opening float, and the figure now goes somewhere.** The
/// box is optional and empty means none, so a shop that keeps no change in the
/// drawer answers by not answering. What is typed is recorded on the shift and
/// added by nightly reconciliation to the cash it expects the drawer to hold -
/// so a float no longer reads as a surplus at close. The old dialog collected
/// this figure and only ever displayed it back; this one is compared against.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../inventory/catalog_management.dart';
import '../reporting/reporting_currency.dart';
import '../returns/return_actions.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/illustration.dart';
import '../ui/press.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'shift_controller.dart';
import 'shift_declaration.dart';
import 'shift_panel.dart';

/// What a person chose on the way out of the till.
enum _ShiftExitChoice {
  /// Keep the shift open and go back to the home. The old dialog's *Just
  /// Stepping Away*.
  stepAway,

  /// Count the cash and close out. The old dialog's *End My Shift*.
  endShift,
}

/// The two answers, with the words and the glyphs the old till used.
///
/// **Stepping away is first and it is the safe one**, which is both the old
/// dialog's order and the product owner's direction of 2026-09-03: a cashier
/// leaves the till far more often than they end a day, and the common answer
/// was drawn as the quiet outlined button beside a mint *End shift*.
extension on _ShiftExitChoice {
  ({String label, String detail, IconData icon, AppStatus status}) get card =>
      switch (this) {
        _ShiftExitChoice.stepAway => (
          label: 'Just stepping away',
          detail: 'Keep the shift open and go back to the menu',
          icon: Icons.pause_circle_outline,
          status: AppStatus.ok,
        ),
        _ShiftExitChoice.endShift => (
          label: 'Close shift',
          detail: 'Count the cash and close out',
          icon: Icons.stop_circle_outlined,
          status: AppStatus.problem,
        ),
      };
}

/// Wraps the till so that selling is only possible inside an open shift.
final class TenantShiftGate extends StatefulWidget {
  const TenantShiftGate({
    super.key,
    required this.controllerFactory,
    required this.currency,
    required this.child,
    this.returnActions,
  });

  /// Builds the controller against the live session, exactly as the close
  /// sheet does - the gate and the sheet must never hold two different
  /// controllers for one session.
  final TenantShiftControllerFactory controllerFactory;

  /// What this business calls its money, so the count states amounts the way
  /// every other surface in this app does rather than in raw minor units.
  final TenantReportingCurrency currency;

  /// Passed through the history and sales routes to the returns route.
  final TenantReturnActions? returnActions;

  /// The till.
  final Widget child;

  @override
  State<TenantShiftGate> createState() => _TenantShiftGateState();
}

class _TenantShiftGateState extends State<TenantShiftGate>
    with WidgetsBindingObserver {
  TenantSessionController? _sessions;
  TenantShiftController? _shifts;

  /// Whether the blocking dialog is on screen, so a rebuild does not stack a
  /// second one on top of it.
  bool _gateUp = false;

  /// Whether the counting sheet is up.
  ///
  /// **The gate must not raise its modal over it.** A close that settles turns
  /// the phase to `none`, which is exactly what `_raiseGateIfNeeded` watches
  /// for - so *Start your shift* was landing on top of the sheet's own report
  /// of the close a person had just taken, and burying the control that
  /// dismisses it. The gate waits until the sheet is gone; the shift is closed
  /// either way, and nothing can be sold behind a modal sheet.
  bool _closingUp = false;

  /// The session the shift on screen was read for.
  ///
  /// **Because the controller object never changes and the session does.** The
  /// gate subscribes to one `TenantSessionController` for the life of the till,
  /// so `identical(sessions, _sessions)` is true on every notification - which
  /// meant a role change, a deactivation, or a business switch reached this
  /// widget and was thrown away. The till went on drawing a shift read for an
  /// access decision that no longer held. See [_sessionMoved].
  String? _readFor;

  /// What identifies a session for that purpose: who, which business, and which
  /// access decision. The epoch is the load-bearing third - `TenantSessionController.refresh`
  /// keeps it when the answer has not moved and bumps it when it has.
  static String? _identityOf(TenantSession? session) => session == null
      ? null
      : '${session.uid}:${session.tenantId}:${session.epoch}';

  @override
  void initState() {
    super.initState();
    // **So the till can be told a decision somebody else made.** A role change
    // or a deactivation reaches this device through no channel of its own; the
    // routing shell asks again when the app is picked back up, and the till has
    // to ask again with it. Without this the shell re-read, the session moved,
    // and the shift on screen stayed exactly as it was.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final shifts = _shifts;
    final session = _sessions?.session;
    if (shifts == null || session == null) return;
    // Cheap and non-blocking: `restore` publishes what this device already
    // knows first and corrects it underneath, so a resumed till never flashes
    // a spinner over a shift it is holding.
    unawaited(shifts.restore(session));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sessions = TenantSessionScope.of(context);
    if (identical(sessions, _sessions) && _shifts != null) {
      _sessionMoved(sessions);
      return;
    }
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
    _readFor = _identityOf(session);
    if (session != null) unawaited(shifts.restore(session));
  }

  /// Re-reads the shift when the *session* changed under an unchanged
  /// controller, and leaves the till when there is no longer a session to sell
  /// in.
  ///
  /// **The till fails closed at the write either way** - `CheckoutDraftService`
  /// refuses a draft whose session has moved - so what this fixes is not a
  /// security hole but a screen that lied: a deactivated cashier kept a till
  /// that looked ready to sell, and only found out when a sale was refused.
  void _sessionMoved(TenantSessionController sessions) {
    final session = sessions.session;
    final identity = _identityOf(session);
    if (identity == _readFor) return;
    _readFor = identity;
    if (session == null || !session.canAccess()) {
      // Nothing can be sold here any more, and the shift belongs to a session
      // this device has left. Leaving is the honest answer; the gate's own
      // modal would be a second question nobody can act on.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return;
    }
    unawaited(_shifts?.restore(session) ?? Future<void>.value());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (!mounted || shifts == null || _gateUp || _closingUp) return;
    if (shifts.state.phase != TenantShiftPhase.none) return;
    _gateUp = true;
    await showAppDialog<void>(
      context,
      builder: (dialogContext) => _ShiftGateDialog(
        shifts: shifts,
        // **The way out of a shift this device cannot adopt.** Without it the
        // refusal in this dialog is terminal: `Open shift` repeats it and names
        // a device the cashier may well be holding, and the only remedy left is
        // an edit to the database. The sheet already draws the declaration and
        // the recovery close - see `_ShiftCount` - so this is the door to it
        // rather than a second copy of it.
        onCloseOrphanShift: _closeShift,
      ),
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
        await _closeShift();
        if (!mounted) return;
        // Back at the till: a closed shift means there is nothing left to sell
        // against, so the till leaves too rather than raising its own gate.
        if (_shifts?.state.phase != TenantShiftPhase.open && mounted) {
          Navigator.of(context).pop();
        }
    }
  }

  /// Counts the cash and closes the shift, in one sheet over the till.
  ///
  /// **One tap from the choice above, and that is the 2026-09-03 change.**
  /// This used to push a page titled *Close shift* whose whole content was a
  /// button also labelled *Close shift*, which opened this sheet. Shared by
  /// the exit dialog's *Close shift* and by the expired screen, which has no
  /// other action.
  Future<void> _closeShift() async {
    final shifts = _shifts;
    final session = _sessions?.session;
    if (shifts == null || session == null || !mounted) return;
    _closingUp = true;
    try {
      await showShiftCloseSheet(
        context,
        shifts: shifts,
        session: session,
        currency: widget.currency,
        returnActions: widget.returnActions,
      );
    } finally {
      _closingUp = false;
    }
    if (!mounted) return;
    // The sheet is gone, so a shift it closed is now the gate's business
    // again: an expired shift counted off leaves this device with none, and
    // the modal asking for a new one is the next thing a cashier needs.
    unawaited(_raiseGateIfNeeded());
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
    // **A till is never drawn for a session that cannot sell.** Popping the
    // route is what takes the person somewhere useful, but a pop is a frame
    // away and a navigation can be refused; this is the guarantee, and it holds
    // in the frame the access ends. `CheckoutDraftService` refuses the write
    // regardless - what this removes is the window in which the screen says
    // otherwise. See [_sessionMoved].
    final live = _sessions?.session;
    if (live == null || !live.canAccess()) {
      return _surface(
        key: const ValueKey('shift-gate-no-session'),
        const LoadingState(
          key: ValueKey('shift-gate-leaving'),
          message: 'Closing this register.',
        ),
      );
    }
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
        TenantShiftPhase.expired => _surface(
          key: const ValueKey('shift-gate-expired'),
          ErrorState(
            status: AppStatus.attention,
            badgeLabel: 'Shift over',
            // **Two things reach this state and the copy must be true of
            // both.** One shift has been open past its day; the other is filed
            // under a day that has not arrived, because the device's clock was
            // wrong when it opened and has since been corrected. Naming the
            // duration was false for the second, and the second is the one
            // where a wrong figure had already been written - so this says the
            // part that always holds, and the count below is the way out of
            // either.
            statement: 'This shift can no longer take sales.',
            detail:
                'Count it off to finish it. That works with no connection: '
                'the count is saved here and reaches the server on its own.',
            stillTrue:
                'Every sale you have already recorded is saved and will be '
                'sent.',
            actions: <Widget>[
              AppButton(
                key: const ValueKey('shift-gate-close'),
                label: 'Close shift',
                tier: AppButtonTier.primary,
                onPressed: _closeShift,
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
            illustration: 'schedule.svg',
          ),
        ),
        // **Counted and closed here; the server has not been told yet.** The
        // till stops selling, exactly as it does at `none` - the figures for
        // this shift are fixed, and a sale after them would be a variance the
        // shop has to explain. What separates it from `none` is that there is
        // nothing to open: this shift is still this device's to finish, and
        // it finishes itself the moment there is a connection.
        TenantShiftPhase.closedPending => _surface(
          key: const ValueKey('shift-gate-closed-pending'),
          const EmptyState(
            title: 'Shift closed on this device',
            hint:
                'Its count is saved. It reaches the server on its own when '
                'this device is back online, and a new shift can be opened '
                'once it has.',
            illustration: 'schedule.svg',
          ),
        ),
        TenantShiftPhase.unavailable => _surface(
          key: const ValueKey('shift-gate-unavailable'),
          Callout(
            status: AppStatus.problem,
            message:
                'Shift state could not be read, so this register stays closed. '
                'Check the connection and open the register again.',
          ),
        ),
        TenantShiftPhase.open || TenantShiftPhase.closing => widget.child,
      },
    );
  }
}

/// The blocking *Start your shift* modal.
final class _ShiftGateDialog extends StatefulWidget {
  const _ShiftGateDialog({
    required this.shifts,
    required this.onCloseOrphanShift,
  });

  final TenantShiftController shifts;

  /// Opens the close sheet against a shift this install cannot adopt.
  final Future<void> Function() onCloseOrphanShift;

  @override
  State<_ShiftGateDialog> createState() => _ShiftGateDialogState();
}

class _ShiftGateDialogState extends State<_ShiftGateDialog> {
  bool _busy = false;

  /// What the cashier says the drawer starts with, as typed.
  final TextEditingController _float = TextEditingController();

  /// Why the float box cannot be read, or null while it can.
  String? _floatError;

  @override
  void initState() {
    super.initState();
    // **The dialog follows the controller, since 2026-09-05.** It used to read
    // the state once and keep whatever it drew, so a refusal survived the thing
    // it was refusing: closing the orphaned shift from here left *This shift is
    // open on another device* on screen with `Open shift` still disabled, and
    // the only way on was to leave the till and come back.
    widget.shifts.addListener(_handleShiftChanged);
  }

  @override
  void dispose() {
    // Unsubscribed, never disposed: the controller is the session's and
    // outlives this dialog.
    widget.shifts.removeListener(_handleShiftChanged);
    _float.dispose();
    super.dispose();
  }

  /// The float in minor units, or null where the box does not read as money.
  ///
  /// **An empty box is no float, not a refusal.** Most shops do not keep one,
  /// and requiring a typed `0` of all of them to open a till would teach every
  /// cashier to clear one more box without reading it.
  int? _floatMinor() {
    final text = _float.text.trim();
    if (text.isEmpty) return 0;
    try {
      final minor = tenantCatalogPriceMinorUnits(text);
      return minor > maximumShiftCashMinor ? null : minor;
    } on TenantCatalogManagementException {
      return null;
    }
  }

  void _handleShiftChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    if (_busy) return;
    final float = _floatMinor();
    // **Refused here rather than sent as a zero.** A float that cannot be read
    // is not a shift with no float: it is a figure the cashier meant to record,
    // and opening without it would silently bill them for it at close.
    if (float == null) {
      setState(() => _floatError = 'Enter an amount, like 2000 or 1500.50.');
      return;
    }
    setState(() {
      _busy = true;
      _floatError = null;
    });
    final state = await widget.shifts.openShift(openingFloatMinor: float);
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
            // The same drawing the gate's own *No shift is open* state uses,
            // at the mark's size rather than the scene's: a dialog is a
            // question, and a 168-tall picture above it pushes the answer off
            // a short phone.
            const Center(
              child: AppIllustration(
                asset: 'schedule.svg',
                size: EmptyState.markSize,
                semanticLabel: 'A shift waiting to be opened',
              ),
            ),
            SizedBox(height: tokens.spacing.s16),
            Text(
              'Every sale is recorded against a shift, so this register opens one '
              'before it can sell.',
              textAlign: TextAlign.center,
              style: tokens.typography.bodyLarge.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
            SizedBox(height: tokens.spacing.s16),
            AppTextField(
              key: const ValueKey('shift-gate-opening-float'),
              controller: _float,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              label: 'Opening float',
              leading: Icons.savings_outlined,
              enabled: !_busy,
              error: _floatError,
              // **Not autofocused, unlike the close sheet's boxes.** This
              // dialog's job is to open a shift and most shops will leave this
              // empty; raising the keyboard over the one button a cashier came
              // here to press would cost every one of them a tap to save the
              // few who type in it.
              textInputAction: TextInputAction.done,
              onSubmitted: _busy ? null : (_) => _open(),
            ),
            SizedBox(height: tokens.spacing.s8),
            Text(
              // Says what the figure is *for*, because that is what makes a
              // cashier bother with it: it is the reason their drawer balances
              // at the end of the day instead of reading over by the float.
              'The change in the drawer before any sale. Leave it empty if '
              'there is none — it is counted back at close, not taken as '
              'takings.',
              style: tokens.typography.caption.copyWith(
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
          // **Offered only for this phone's own earlier install.**
          // `otherDeviceShiftId` names one only where the durable half of the
          // device id matches, so a shift on another phone - which may simply
          // be offline - can no longer appear behind this button. Where two
          // installs of this phone both left one open it still says nothing,
          // because closing the wrong one is worse than closing none.
          //
          // It is no longer the way out of a terminal refusal: `Open shift`
          // beside it now succeeds, and counting off closes every other shift
          // this cashier holds. It remains the way to settle this phone's own
          // orphan *with* a count, which the sweep does not do.
          if (widget.shifts.state.otherDeviceShiftId != null)
            AppButton(
              key: const ValueKey('shift-gate-close-orphan'),
              label: 'Close that shift',
              tier: AppButtonTier.secondary,
              onPressed: _busy ? null : widget.onCloseOrphanShift,
            ),
          AppButton(
            key: const ValueKey('shift-gate-open'),
            label: 'Open shift',
            tier: AppButtonTier.primary,
            loading: _busy,
            // **Left enabled even while the refusal is up, deliberately.** It
            // re-runs the discovery query, so it is also the only way to
            // re-check a shift that has since been closed somewhere else -
            // disabling it would trap a cashier whose colleague had already
            // dealt with it. What was missing was never a way to ask again; it
            // was a way to act on the answer, which is the control beside it.
            onPressed: _open,
          ),
        ],
      ),
    );
  }
}

/// The old till's two ways out, in the old till's own layout.
///
/// **Copied from `lib/pos/pos.dart`'s `_handleExitToHub`** at the product
/// owner's direction on 2026-09-03: *"we need it to feel like it did there for
/// old customers who will be upgrading."* A badge, a title, a question, two
/// tappable option cards and a way to change your mind - not two buttons on a
/// row.
///
/// **It is also what makes stepping away dominant.** As an
/// `AppActionRow` the pair had *End shift* as the mint primary on the right
/// and the far more common *Step away* as the quiet outline beside it; and the
/// two verb phrases did not fit a phone side by side, which is why the label
/// had already been cut from *Just stepping away* on 2026-08-26. Full-width
/// rows give the common answer the top of the dialog, its own colour, and its
/// whole sentence back.
final class _ShiftExitDialog extends StatelessWidget {
  const _ShiftExitDialog();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final leaving = AppStatus.attention.role(tokens);
    return AppDialog(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The old dialog's circular glyph badge. `radius.pill` is for
          // genuine circles, which this is.
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: leaving.bg,
                borderRadius: BorderRadius.circular(tokens.radius.pill),
              ),
              child: Padding(
                padding: EdgeInsets.all(tokens.spacing.s16),
                child: Icon(
                  Icons.exit_to_app_rounded,
                  size: AppButton.prominentIconSize,
                  color: leaving.fg,
                ),
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.s16),
          Text(
            'Leaving the register',
            textAlign: TextAlign.center,
            style: tokens.typography.titleLarge.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
          SizedBox(height: tokens.spacing.s8),
          Text(
            'Your shift is still open. What would you like to do?',
            textAlign: TextAlign.center,
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.text.secondary),
          ),
          SizedBox(height: tokens.spacing.s24),
          const _ShiftExitOption(
            key: ValueKey('shift-exit-step-away'),
            choice: _ShiftExitChoice.stepAway,
          ),
          SizedBox(height: tokens.spacing.s12),
          const _ShiftExitOption(
            key: ValueKey('shift-exit-end'),
            choice: _ShiftExitChoice.endShift,
          ),
        ],
      ),
      actions: <Widget>[
        // Answering nothing is an answer the old dialog offered and this one
        // has to as well: `_handleExit` reads a null result as staying.
        AppButton(
          key: const ValueKey('shift-exit-cancel'),
          label: 'Cancel',
          tier: AppButtonTier.tertiary,
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// One of the two answers, as the old dialog drew it: a glyph in a tinted
/// square, the answer, a line saying what it does, and a chevron.
final class _ShiftExitOption extends StatelessWidget {
  const _ShiftExitOption({super.key, required this.choice});

  final _ShiftExitChoice choice;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final card = choice.card;
    final role = card.status.role(tokens);
    final radius = BorderRadius.circular(tokens.radius.md);
    return Semantics(
      button: true,
      label: '${card.label}. ${card.detail}.',
      excludeSemantics: true,
      child: PressSurface(
        borderRadius: radius,
        fillWidth: true,
        onPressed: () => Navigator.of(context).pop(choice),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: role.bg,
            border: Border.all(color: role.border),
            borderRadius: radius,
          ),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.s16),
            child: Row(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: role.border,
                    borderRadius: radius,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(tokens.spacing.s8),
                    child: Icon(
                      card.icon,
                      size: AppButton.prominentIconSize,
                      color: role.fg,
                    ),
                  ),
                ),
                SizedBox(width: tokens.spacing.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        card.label,
                        style: tokens.typography.labelMedium.copyWith(
                          color: role.fg,
                        ),
                      ),
                      SizedBox(height: tokens.spacing.s4),
                      Text(
                        card.detail,
                        style: tokens.typography.caption.copyWith(
                          color: tokens.colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: tokens.spacing.s8),
                Icon(
                  Icons.chevron_right,
                  size: AppButton.iconSize,
                  color: role.fg,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
