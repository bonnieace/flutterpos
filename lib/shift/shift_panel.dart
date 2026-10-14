/// The one surface that closes a shift: a sheet with the count in it.
///
/// **There used to be a route in front of this, and on 2026-09-03 there is
/// not.** Closing meant leaving the till, answering *End shift* in a dialog,
/// landing on a pushed page titled *Close shift*, pressing a button also
/// labelled *Close shift*, and only then meeting a sheet with a field in it -
/// four surfaces and two identically-worded controls before a number could be
/// typed. The product owner called it: one tap opens the sheet, the amount is
/// typed, and the server confirms it. The page in the middle held nothing the
/// sheet does not, so it is gone along with `TenantShiftPanel`.
///
/// **The close is awaited here rather than behind a closed sheet.** The old
/// arrangement popped the sheet and then dispatched, which put the refusal on
/// a card behind the surface a person had opened to act - and with the route
/// deleted there is no card at all. A refusal now lands in the sheet, above
/// the amount that is still in the field.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../checkout/checkout_receipt.dart' show checkoutDeviceHardwareDigest;
import '../checkout/checkout_tender.dart';
import '../inventory/catalog_management.dart';
import '../reporting/reporting_currency.dart';
import '../returns/return_actions.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/banner.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/illustration.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../ui/sheet.dart';
import 'shift_controller.dart';
import 'shift_declaration.dart';
import 'shift_sales_ledger.dart';

/// Supplies the shift controller belonging to the session controller owned by
/// the shell.
///
/// **The factory owns what it returns; a caller subscribes and never disposes.**
/// It reads as though it builds one, and since 2026-08-26 it does not: the
/// composition root caches one controller per session so that re-entering the
/// till does not restart from `TenantShiftPhase.unknown`. Two widgets are handed
/// the same instance - see `TenantShiftGate`, which says the two must never hold
/// different controllers for one session - and a screen that disposed it would
/// destroy the other's state along with every later till entry's. That is
/// exactly the crash of 2026-08-27, and it is why this is stated on the typedef
/// rather than left to whoever reads the composition root.
typedef TenantShiftControllerFactory =
    TenantShiftController Function(TenantSessionController sessions);

/// Counts the drawer and closes the shift, in one sheet.
///
/// **Opening it is what starts the count**, which has been true since
/// 2026-08-23 and is the reason there is no *Start cash count* control
/// anywhere: the count is not a step a cashier takes, it is the state of
/// having this surface open. Whoever opened it ends the count on the way out,
/// so a sheet dismissed without a decision leaves the till in service rather
/// than silently out of it.
///
/// The sheet refuses the scrim while a count is running, so a half-counted
/// drawer cannot be lost to a stray swipe.
Future<void> showShiftCloseSheet(
  BuildContext context, {
  required TenantShiftController shifts,
  required TenantSession session,
  required TenantReportingCurrency currency,
  TenantReturnActions? returnActions,
}) async {
  // An expired shift needs the count started exactly as an open one does -
  // closing is the only thing left to do with it, and without this the sheet
  // would open on a shift with no count running and refuse the close.
  if (shifts.state.phase == TenantShiftPhase.open ||
      shifts.state.phase == TenantShiftPhase.expired) {
    await shifts.startCashCount();
  }
  if (!context.mounted) return;
  final sessions = TenantSessionScope.read(context);
  final handled = await showAppSheet<bool>(
    context,
    // **`full`, like every other form sheet in the app.** This one opened at
    // `half` and was the only outlier; a form whose subject is a number being
    // typed wants the room, and the keyboard takes its share on top.
    initialDetent: AppSheetDetent.full,
    dismissible: shifts.state.phase != TenantShiftPhase.closing,
    builder: (sheetContext, controller) => _ShiftCloseSheet(
      shifts: shifts,
      sessions: sessions,
      session: session,
      currency: currency,
      scrollController: controller,
      returnActions: returnActions,
    ),
  );
  // A `null` result is a dismissal - a back gesture can still pop a sheet that
  // refuses the scrim - and is what the count is cancelled on.
  if (handled != true && shifts.state.phase == TenantShiftPhase.closing) {
    await shifts.cancelCashCount();
  }
}

/// The count, the figures it is measured against, and the close.
final class _ShiftCloseSheet extends StatefulWidget {
  const _ShiftCloseSheet({
    required this.shifts,
    required this.sessions,
    required this.session,
    required this.currency,
    required this.scrollController,
    required this.returnActions,
  });

  final TenantShiftController shifts;
  final TenantSessionController sessions;
  final TenantSession session;

  /// What this business calls its money, so the shift states amounts the way
  /// every other surface in this app does rather than in raw minor units.
  final TenantReportingCurrency currency;

  /// The sheet's own scroll controller. `showAppSheet` requires the content to
  /// take it, or dragging the list scrolls the list and the sheet never moves.
  final ScrollController scrollController;

  /// Passed through to the returns route.
  /// Recording a return stays unavailable while it is absent.
  final TenantReturnActions? returnActions;

  @override
  State<_ShiftCloseSheet> createState() => _ShiftCloseSheetState();
}

final class _ShiftCloseSheetState extends State<_ShiftCloseSheet> {
  /// One controller per payment method, in the order they are asked for.
  ///
  /// **Three boxes rather than one, and no expected figure beside them.** The
  /// declaration is the only moment this app can learn what a shift actually
  /// took by method: a sale records what the till was told at the moment of
  /// payment, some payments settle afterwards, and nothing edits a sale's
  /// tender later. Showing what is expected here would turn the answer into a
  /// copy of the question - so the sheet asks, and reconciliation compares.
  final Map<CheckoutTender, TextEditingController> _declared = {
    for (final tender in CheckoutTender.values) tender: TextEditingController(),
  };

  /// Which boxes hold something that is not an amount, by method.
  ///
  /// Refused here rather than by the controller: `invalid_closing_cash` is a
  /// statement about a figure being out of range, and a misspelling is a
  /// statement about one box, which belongs beside that box.
  final Map<CheckoutTender, String> _fieldErrors = <CheckoutTender, String>{};

  bool _busy = false;

  /// What was declared, kept for the report a settled close draws.
  ///
  /// **The state cannot supply it.** A close the server accepts clears this
  /// device's durable record, declaration and all, so by the time there is
  /// something to report `state.declaration` is null. This is what the person
  /// entered, which is the only thing this surface may read back to them.
  ShiftTenderDeclaration? _counted;

  /// What became of a second shift this cashier still had open, if there was
  /// one. Null is the ordinary case: there was nothing else to close.
  ///
  /// It is reported rather than done quietly, because closing a shift is a
  /// bookkeeping act and the person whose name is on it should read that it
  /// happened - and, where it did not, that the other till still needs seeing
  /// to. See [_closeOtherOpenShift].
  ({int closed, int failed, String? errorCode})? _otherShift;

  /// The state a finished close settled on, or null while the count is still
  /// the subject of this sheet.
  ///
  /// **Set only when the count is over one way or the other.** A refusal that
  /// leaves the shift `closing` is not this - the drawer is still being
  /// counted, and the sheet stays a form with a notice on it.
  TenantShiftState? _outcome;

  @override
  void dispose() {
    for (final controller in _declared.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// One declared box in minor units, or null where it is not an amount.
  ///
  /// **Typed as money, stored as minor units.** The field takes what the drawer
  /// holds - `1250.50` - and this converts it through the same function the
  /// till and the catalog use, so an amount this surface accepts is one the
  /// close can record exactly.
  ///
  /// **An empty box is zero, not a refusal.** A shift that genuinely took no
  /// card should not need a typed `0`, and requiring one trains a cashier to
  /// fill boxes without reading them - which is the opposite of what asking
  /// three questions is for.
  int? _declaredMinor(CheckoutTender tender) {
    final text = _declared[tender]!.text.trim();
    if (text.isEmpty) return 0;
    try {
      return tenantCatalogPriceMinorUnits(text);
    } on TenantCatalogManagementException {
      return null;
    }
  }

  /// Reads all three boxes, or records which ones cannot be read.
  ShiftTenderDeclaration? _readDeclaration() {
    final errors = <CheckoutTender, String>{};
    final figures = <CheckoutTender, int>{};
    for (final tender in CheckoutTender.values) {
      final minor = _declaredMinor(tender);
      if (minor == null) {
        errors[tender] = 'Enter an amount, like 1250.50.';
      } else {
        figures[tender] = minor;
      }
    }
    final declaration = errors.isNotEmpty
        ? null
        : ShiftTenderDeclaration.tryParse(
            cash: figures[CheckoutTender.cash]!,
            mpesa: figures[CheckoutTender.mpesa]!,
            card: figures[CheckoutTender.card]!,
          );
    // A triple that parses but will not fit is one figure being too large or
    // the three together being so; either way it is the amounts that are wrong
    // rather than the spelling, so it is said on every box.
    if (errors.isEmpty && declaration == null) {
      for (final tender in CheckoutTender.values) {
        errors[tender] = 'This amount is too large to record.';
      }
    }
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(errors);
    });
    return declaration;
  }

  Future<void> _dispatch(
    Future<TenantShiftState> Function(TenantShiftController shifts) action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(widget.shifts);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Counts the drawer off and waits for the server's answer here.
  Future<void> _close() async {
    if (_busy) return;
    // A box that is not an amount is answered here and nothing is dispatched:
    // the sheet stays a form with the fault named against the box that has it.
    final declaration = _readDeclaration();
    if (declaration == null) return;
    setState(() => _busy = true);
    // **Minted before the first write, because it names both halves.** The
    // counted shift closes first and the swept ones follow, so a name invented
    // afterwards could not reach the one already written.
    final settlementId = widget.shifts.newSettlementId();
    final state = await widget.shifts.closeShift(
      declaration: declaration,
      settlementId: settlementId,
    );
    final other =
        state.phase == TenantShiftPhase.none && state.errorCode == null
        ? await _closeOtherOpenShift(settlementId)
        : null;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _counted = declaration;
      _otherShift = other;
      // Still `closing` means the count is still running and the refusal is
      // about this attempt: the sheet stays a form, with the notice above the
      // amounts that are still typed into it.
      _outcome = state.phase == TenantShiftPhase.closing ? null : state;
    });
  }

  /// Closes every other shift this cashier has open, without counting again.
  ///
  /// **One till is counted once, so the others declare nothing.** Several open
  /// shifts for one cashier are possible - the check that prevents them reads
  /// only this device, and is skipped entirely with no network - and the
  /// cashier meets that as one drawer answering to more than one shift. Asking
  /// them to count again cannot produce a true answer: the money has already
  /// been declared onto the shift they just closed, and whatever they typed
  /// here would be that same money recorded twice or a guess at a split.
  ///
  /// **All of them, not the first one found.** This used to read
  /// `otherDeviceShiftId`, which names at most one and deliberately names none
  /// where more than one candidate exists - so a cashier holding three shifts
  /// had two of them quietly left open, and no surface offered to close them.
  /// `otherOpenShiftIds` answers the question this actually asks.
  ///
  /// **[settlementId] is what makes the reporting add up.** One cashier holds
  /// one register and counts one drawer, so every shift closed here is settled
  /// by that single count - and reconciliation builds its expectation per
  /// shift, so without the shared name it measured the whole drawer against the
  /// counted shift alone and called the rest unverifiable.
  ///
  /// A shift that has been closed elsewhere since it was listed is not a
  /// failure: `orphan_shift_not_found` is the server agreeing it is already
  /// done.
  ///
  /// Returns null where there was no other shift, which is the ordinary case.
  Future<({int closed, int failed, String? errorCode})?> _closeOtherOpenShift(
    String settlementId,
  ) async {
    final shiftIds = await widget.shifts.otherOpenShiftIds();
    if (!mounted || shiftIds.isEmpty) return null;
    var closed = 0;
    var failed = 0;
    String? errorCode;
    for (final shiftId in shiftIds) {
      final state = await widget.shifts.closeShiftWithoutEvidence(
        shiftId: shiftId,
        // The drawer is already counted. See the doc comment above.
        declaration: null,
        // The same count that closed the shift above, so reconciliation adds
        // these takings to that one declaration rather than reporting this
        // shift as unverifiable and that one as over by what this took.
        settlementId: settlementId,
      );
      if (!mounted) return null;
      if (state.errorCode == null ||
          state.errorCode == 'orphan_shift_not_found') {
        closed += 1;
      } else {
        failed += 1;
        errorCode ??= state.errorCode;
      }
    }
    return (closed: closed, failed: failed, errorCode: errorCode);
  }

  // **No recovery close on this sheet since 2026-09-29.** It closed a shift an
  // earlier install of this phone had left open, with or without a count,
  // because this phone could not adopt it. Discovery joins that shift now, so
  // it is closed by the ordinary count above like any other.

  /// What the banner says about a shift this phone joined rather than opened,
  /// or null where it opened it (or the canonical shift is not in hand yet,
  /// which is the same point the float reminder waits for).
  ///
  /// **Two sentences, because there are two ways to have joined.** The shift
  /// document keeps the opener's device id, and the durable half of it - see
  /// `checkoutDeviceHardwareDigest` - survives a reinstall. Where that half
  /// matches this phone's, the opener was this same phone before the app was
  /// reinstalled, and "another phone" would send the cashier looking for one.
  String? get _joinedNotice {
    final shift = widget.shifts.state.shift;
    final here = widget.shifts.deviceId;
    if (shift == null || shift.deviceId == here) return null;
    bool samePhone;
    try {
      samePhone =
          checkoutDeviceHardwareDigest(shift.deviceId) ==
          checkoutDeviceHardwareDigest(here);
    } on ArgumentError {
      samePhone = false;
    }
    return samePhone
        ? 'This shift was opened on this phone before the app was '
              'reinstalled, and it carries on here.'
        : 'This shift was opened on another phone. Sales from every phone '
              'you use count towards it.';
  }

  Future<void> _cancel() async {
    await _dispatch((shifts) => shifts.cancelCashCount());
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.shifts,
    builder: (context, _) {
      final tokens = AppTokens.componentOf(context);
      return ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.all(tokens.spacing.s20),
        children: <Widget>[
          if (_outcome case final settled?)
            _ShiftClosed(
              state: settled,
              counted: _counted,
              otherShift: _otherShift,
              currency: widget.currency,
              onDone: () => Navigator.of(context).pop(true),
            )
          else
            _ShiftCount(
              state: widget.shifts.state,
              currency: widget.currency,
              busy: _busy,
              declared: _declared,
              fieldErrors: _fieldErrors,
              onClose: _close,
              joinedNotice: _joinedNotice,
              onCancelCashCount: _cancel,
            ),
        ],
      );
    },
  );
}

/// What a shift refusal says to the person who caused it.
///
/// **Public and shared since 2026-08-25**, when the till's shift gate began
/// reporting the same refusals this surface does. A second copy would be a
/// second set of words for one server answer, and the two would drift the first
/// time either was reworded.
String shiftErrorMessage(String? code) => switch (code) {
  'offline' =>
    'This device is offline, so this shift has not been re-confirmed with the '
        'server. You can keep selling.',
  // Reachable only where this device holds no copy of the shift document, so
  // it cannot describe what it would be closing. Closing itself no longer
  // needs a connection.
  'close_needs_connection' =>
    'This device has no copy of this shift yet, so it cannot be closed here. '
        'Connect once and it can be closed from then on, online or not.',
  'shift_expired_offline' =>
    "This shift's trading day is over, so it can no longer take sales. "
        'Count it off and it will be sent when this device is back online.',
  'shift_open_unconfirmed' =>
    'This shift has not reached the server yet. It and its sales are saved '
        'here and will be sent.',
  'other_tenant_shift_open' =>
    'Close the open shift in the other business first.',
  // `shift_open_on_other_device` and `shift_open_on_earlier_install` are gone
  // since 2026-09-29: a shift open on another phone, or left by an earlier
  // install of this one, is joined rather than refused.
  'orphan_shift_not_found' =>
    'That shift is no longer open, so there is nothing to close. Refresh to '
        'see where the register stands.',
  'orphan_shift_ambiguous' =>
    'More than one open shift matches, so this device cannot tell which to '
        'close. An owner or administrator must close it.',
  'orphan_close_needs_connection' =>
    'Closing a shift this device holds no sales for needs a connection, '
        'because the shift itself has to be read. Try again once online.',
  'declaration_disagrees_with_cash' =>
    'The cash figure did not reach the server intact. Enter it again.',
  'unsynchronized_shift_sales' =>
    'Some sales in this shift are not synchronized yet. Wait for them '
        'before closing.',
  'shift_already_open' => 'A shift is already open on this device.',
  'no_open_shift' => 'No shift is open to count or close.',
  'cash_count_not_started' => 'Start the cash count before closing.',
  'invalid_closing_cash' => 'Enter the counted cash before closing.',
  'session_changed' => 'The selected business changed.',
  'shift_not_open' =>
    'This shift was already closed somewhere else, so nothing was written '
        'here.',
  'shift_close_unconfirmed' =>
    'The close has not been confirmed by the server yet. Nothing was lost - '
        'try again when the connection is steadier.',
  _ => 'The last shift action could not be confirmed.',
};

/// The sales this device holds but has not yet settled with the server.
/// How many other shifts a close swept up, as a sentence fragment.
///
/// Spelled rather than numbered at one, because "a shift" is how a person says
/// it and "1 shift" is how a form does.
String _registerCount(int shifts) => shifts == 1 ? 'a shift' : '$shifts shifts';

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
  TenantShiftPhase.closedPending =>
    'A closed shift is waiting to reach the server. It goes on its own once '
        'this device is online.',
  TenantShiftPhase.expired =>
    'A shift has been open more than a day. Close it before switching '
        'business.',
  TenantShiftPhase.unavailable => 'Shift state is unavailable.',
};

/// The count itself: where the shift stands, what it took, and the drawer.
///
/// **Ordered the way the pre-multitenancy dialog was** - `lib/pos/pos.dart`'s
/// *Close Shift Summary*: the standing, then the figures the drawer is measured
/// against, then the field, then the controls. An upgrading cashier meets the
/// same sequence of questions in the same order.
final class _ShiftCount extends StatelessWidget {
  const _ShiftCount({
    required this.state,
    required this.currency,
    required this.busy,
    required this.declared,
    required this.fieldErrors,
    required this.onClose,
    required this.onCancelCashCount,
    this.joinedNotice,
  });

  final TenantShiftState state;

  /// What this business calls its money, so the opening float is named the way
  /// every other amount on this sheet is.
  final TenantReportingCurrency currency;
  final bool busy;
  final Map<CheckoutTender, TextEditingController> declared;
  final Map<CheckoutTender, String> fieldErrors;
  final VoidCallback onClose;

  /// What to say about a shift this phone joined rather than opened, or null.
  ///
  /// **Said with the count, because that is where it matters.** The sheet
  /// starts a count as it opens, so this is the one surface a cashier reads
  /// about their shift - and it is where a float they did not type here, and
  /// a prompt asking about every phone, both need the reason.
  final String? joinedNotice;
  final VoidCallback onCancelCashCount;

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
    // `attention` rather than `ok`: the count is done, but the shift is not
    // finished until the server has it, and that is something still owed.
    TenantShiftPhase.closedPending => AppStatus.attention,
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
    TenantShiftPhase.closing => 'Counting the drawer',
    TenantShiftPhase.closedPending => 'Closed, waiting to send',
    TenantShiftPhase.expired => 'Shift open too long',
    TenantShiftPhase.unknown => 'Shift not confirmed',
    TenantShiftPhase.unavailable => 'Shift unavailable',
  };

  /// The one thing louder than the routine detail, or null.
  ///
  /// **A warning promotes the detail line**, which is the decision that keeps a
  /// one-line banner honest. A real device run once reported "Confirmed sales:
  /// 0" beside a drawer holding two unsynchronized sales, and said nothing
  /// about them until the cashier pressed Close - so a shift with money
  /// unaccounted for says *that* rather than its takings, and the status turns
  /// `attention` with it.
  String? get _warning {
    if (state.errorCode != null) return shiftErrorMessage(state.errorCode);
    if (state.otherTenantShiftOpen) {
      return 'Another business still has an open shift on this device.';
    }
    if (state.otherDeviceShiftOpen) return _otherShiftNotice;
    final sales = state.sales;
    if (sales != null && !sales.isComplete) {
      return _unsynchronizedSalesLabel(sales);
    }
    return null;
  }

  /// A second shift of this cashier's, opened by a phone that could not see
  /// the one joined here - usually one that was offline.
  static const String _otherShiftNotice =
      'You have a second shift open in this business, on another phone. It '
      'will be closed when you count off here.';

  /// What the banner says.
  ///
  /// **Never the takings and never the unsynchronized count**, both of which
  /// are printed in full directly underneath it. On the deleted home card this
  /// line was the only place either appeared; in the sheet it would be the
  /// same fact twice, one line apart, which is the duplication rule §7 states
  /// and the first thing the retargeted tests caught.
  ///
  /// A refusal is different: nothing else on this surface carries it.
  String get _detail {
    if (state.errorCode != null) return shiftErrorMessage(state.errorCode);
    if (state.otherTenantShiftOpen) {
      return 'Another business still has an open shift on this device.';
    }
    if (state.otherDeviceShiftOpen) return _otherShiftNotice;
    return _shiftStatusLabel(state.phase);
  }

  /// What the three boxes are asking for.
  ///
  /// **It says what to enter and never what is expected.** A cashier who is
  /// shown the figure to match writes the figure to match; the whole value of
  /// this surface is that it is answered from the drawer.
  ///
  /// **Worded by the product owner on 2026-09-29.** A shift belongs to its
  /// cashier and may span phones, and the declaration is their own account of
  /// all of it; the boxes name the methods and an empty one is read as none,
  /// so the prompt needs to say nothing else.
  static const String _declarationPrompt = 'Enter what you took today.';

  /// The reminder a floated till needs, because the count is marked against it.
  ///
  /// **The one way this feature makes things worse if it is not said.** A shop
  /// that floats a drawer commonly lifts the float back out before counting the
  /// takings - and a cashier who does that then declares the sales alone, while
  /// reconciliation is expecting the sales *plus* the float. They read as short
  /// by exactly the change they just put back in the safe, every single day.
  ///
  /// **It does not give the count away.** The blind declaration exists so that
  /// nobody is shown the figure they are meant to match; this is not that
  /// figure. It is a fact about the drawer they were handed, which they can see
  /// by looking in it, and it says nothing about what the shift sold.
  ///
  /// "This shift", not "this register": the float was typed when the shift was
  /// opened, which may have been on another phone.
  static String _floatNotice(String amount) =>
      'This shift started with $amount in change. Count it in — it is taken '
      'back out when your takings are worked out.';

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final sales = state.sales;
    final counting = state.phase == TenantShiftPhase.closing;
    // **Zero where the canonical shift is not in hand**, which is a till that
    // opened with no network and has not settled yet. The reminder is an aid
    // rather than a gate: the server adds the float whether or not this line
    // was drawn, so its absence costs a prompt and never a figure.
    final openingFloatMinor = state.shift?.openingFloatMinor ?? 0;
    return Column(
      key: const ValueKey('tenant-shift-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // **The shift's standing, in the component the home used to carry it
        // in.** The banner outlived the card it sat on: it is the one row that
        // says where a shift stands in words and in colour at once, and this is
        // now the only surface that has to.
        ShiftBanner(
          status: _status,
          heading: _heading,
          detail: _detail,
          icon: Icons.lock_outline,
        ),
        // **The blocker on closing, beside the control it blocks.** A real
        // device run found this surface silent about unsynchronized sales
        // until `Close shift` failed.
        //
        // It survives the removal of every other figure here because it is not
        // one: it counts *sales this device has not sent*, names no money, and
        // is the one thing on this sheet a cashier has to act on before the
        // close will go through.
        if (sales != null && !sales.isComplete) ...[
          SizedBox(height: tokens.spacing.s12),
          Text(
            key: const ValueKey('shift-unsynchronized-sales'),
            _unsynchronizedSalesLabel(sales),
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.status.attention.fg),
          ),
        ],
        if (counting) ...[
          SizedBox(height: tokens.spacing.s16),
          Text(
            key: const ValueKey('declared-tender-prompt'),
            _declarationPrompt,
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.text.secondary),
          ),
          if (joinedNotice case final notice?) ...[
            SizedBox(height: tokens.spacing.s8),
            Text(
              key: const ValueKey('shift-joined-notice'),
              notice,
              style: tokens.density
                  .body(tokens.typography)
                  .copyWith(color: tokens.colors.text.secondary),
            ),
          ],
          if (openingFloatMinor > 0) ...[
            SizedBox(height: tokens.spacing.s8),
            Text(
              key: const ValueKey('shift-opening-float-notice'),
              _floatNotice(currency.format(openingFloatMinor / 100)),
              style: tokens.density
                  .body(tokens.typography)
                  .copyWith(color: tokens.colors.status.attention.fg),
            ),
          ],
          for (final tender in CheckoutTender.values) ...[
            SizedBox(height: tokens.spacing.s8),
            AppTextField(
              key: ValueKey('declared-${tender.wireValue}'),
              controller: declared[tender]!,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              label: tender.label,
              leading: Icons.payments_outlined,
              enabled: !busy,
              error: fieldErrors[tender],
              // **The whole point of opening this sheet is to type these
              // numbers**, so the caret is in the first and the keyboard is up
              // before a finger moves. It is only safe now that `showAppSheet`
              // stops re-inflating its subtree when the keys arrive - see
              // `_AboveTheKeyboard`.
              autofocus: tender == CheckoutTender.values.first,
              textInputAction: tender == CheckoutTender.values.last
                  ? TextInputAction.done
                  : TextInputAction.next,
              onSubmitted: busy || tender != CheckoutTender.values.last
                  ? null
                  : (_) => onClose(),
            ),
          ],
          // **No tender disclaimer and no `Refresh shift` since 2026-09-29**,
          // both removed by the product owner: the sheet asks for the count and
          // offers the two ways out of it, and nothing else.
          SizedBox(height: tokens.spacing.s16),
          Wrap(
            spacing: tokens.spacing.s8,
            runSpacing: tokens.spacing.s8,
            children: [
              // 8 rule 4: the verb persists from the control that opened this.
              AppButton(
                key: const ValueKey('close-shift-confirm'),
                label: 'Close shift',
                tier: AppButtonTier.primary,
                loading: busy,
                onPressed: busy ? null : onClose,
              ),
              // **The only way out while a count is running, and deliberately
              // so.** The sheet is not dismissible in this phase, because a
              // swipe that discarded a half-counted drawer and quietly put the
              // till back into service is exactly the mis-tap this surface has
              // always refused to allow.
              AppButton(
                key: const ValueKey('cancel-cash-count'),
                label: 'Cancel cash count',
                onPressed: busy ? null : onCancelCashCount,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// What a finished close says, before the sheet goes.
///
/// **The old app's "Shift closed successfully!" was a snack bar over a screen
/// that had already changed.** A cashier who has just counted a drawer is owed
/// the figures they counted it against, on the surface they counted it on - so
/// the close reports here and is dismissed deliberately.
final class _ShiftClosed extends StatelessWidget {
  const _ShiftClosed({
    required this.state,
    required this.counted,
    required this.currency,
    required this.onDone,
    this.otherShift,
  });

  final TenantShiftState state;

  /// The figures that were entered, in minor units.
  final ShiftTenderDeclaration? counted;

  /// What became of a second shift this cashier had open, where there was one.
  final ({int closed, int failed, String? errorCode})? otherShift;

  final TenantReportingCurrency currency;
  final VoidCallback onDone;

  bool get _closed =>
      state.phase == TenantShiftPhase.none && state.errorCode == null;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      key: const ValueKey('shift-close-outcome'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Center(
          child: AppIllustration(
            asset: _closed ? 'closed-shift.svg' : 'access-denied.svg',
            size: EmptyState.illustrationSize,
            semanticLabel: _closed ? 'The shift is closed' : 'Nothing was sent',
          ),
        ),
        SizedBox(height: tokens.spacing.s16),
        Text(
          key: const ValueKey('shift-close-heading'),
          _closed ? 'Shift closed' : 'Shift not closed',
          textAlign: TextAlign.center,
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        // **Only what was typed, and nothing derived from it.** This used to
        // print the shift's confirmed sales here, which made the declaration
        // blind exactly once: a cashier who submits and is then shown the
        // figure they were being measured against knows what to write the next
        // time. What they entered is theirs to read back; what it is compared
        // with is not on this surface at all.
        if (_closed) ...<Widget>[
          if (counted case final declared?) ...<Widget>[
            for (final tender in CheckoutTender.values)
              Text(
                key: ValueKey('shift-close-declared-${tender.wireValue}'),
                '${tender.label}: '
                '${currency.format(declared.minorFor(tender) / 100)}.',
                textAlign: TextAlign.center,
                style: tokens.density
                    .body(tokens.typography)
                    .copyWith(color: tokens.colors.text.secondary),
              ),
          ],
        ] else
          Callout(
            key: const ValueKey('shift-close-refusal'),
            status: AppStatus.problem,
            message: shiftErrorMessage(state.errorCode),
          ),
        // **Another shift is said out loud either way.** It was closed on this
        // person's behalf without them counting for it, or it is still open and
        // somebody has to see to the other till - and both are facts about
        // their name on a day's books. Absent for the ordinary close, where
        // there was no other shift to say anything about.
        //
        // **Counted, because there can be more than one.** Saying "a shift"
        // over two of them would understate what was just done to the books in
        // this person's name.
        if (otherShift case final other?) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
          Callout(
            key: const ValueKey('shift-close-other-shift'),
            status: other.failed == 0 ? AppStatus.ok : AppStatus.problem,
            message: other.failed == 0
                ? 'You also had ${_registerCount(other.closed)} open on another '
                      'register. Closed with no separate count, because this '
                      'register was counted once.'
                : 'You also have ${_registerCount(other.closed + other.failed)} '
                      'open on another register, and '
                      '${other.failed == 1 ? 'one' : '${other.failed}'} could '
                      'not be closed from here. '
                      '${shiftErrorMessage(other.errorCode)}',
          ),
        ],
        SizedBox(height: tokens.spacing.s20),
        AppActionRow(
          actions: <Widget>[
            AppButton(
              key: const ValueKey('shift-close-done'),
              label: 'Done',
              tier: AppButtonTier.primary,
              onPressed: onDone,
            ),
          ],
        ),
      ],
    );
  }
}
