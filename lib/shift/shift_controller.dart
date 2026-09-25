import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../checkout/checkout_draft.dart';
import '../checkout/checkout_receipt.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_types.dart';
import 'shift_declaration.dart';
import 'shift_local_state.dart';
import 'shift_sales_ledger.dart';
import 'tenant_shift.dart';

/// What this device currently knows about the selected session's shift.
enum TenantShiftPhase {
  /// Nothing canonical has been established yet, or the device is offline.
  unknown,

  /// No shift is open for this identity in this business.
  none,

  /// A canonical open shift exists and no cash count has been started.
  open,

  /// A cash count or close is unfinished; tenant switching stays blocked.
  closing,

  /// This device closed the shift and the server has not confirmed it yet.
  ///
  /// **Distinct from [closing] because the count is over.** A shift being
  /// counted may still be sold against - the count can be abandoned - whereas
  /// this one's figures are fixed, and a sale recorded after them would
  /// guarantee a variance the shop would have to explain. So the till stops
  /// selling here, exactly as it does at [none], while the shift itself is
  /// still very much this device's to finish: the record survives, the tenant
  /// switch stays blocked, and the next restore sends the close.
  ///
  /// Reachable only offline, or after a close whose outcome was uncertain.
  closedPending,

  /// The shift has run past [TenantShiftController.maximumShiftDuration].
  ///
  /// **Selling stops and only a close may follow.** A shift is the unit a
  /// day's takings are reconciled in, so one left running for days makes its
  /// own summary meaningless. It is distinct from [closing] because nobody
  /// started a count here - the clock did - and distinct from [none] because a
  /// shift very much exists and still owns this device's unsettled sales.
  expired,

  /// Canonical shift state could not be read; the device fails closed.
  unavailable,
}

/// One immutable view of the shift surface for the selected session.
final class TenantShiftState {
  const TenantShiftState({
    required this.phase,
    this.shift,
    this.declaration,
    this.errorCode,
    this.otherTenantShiftOpen = false,
    this.otherDeviceShiftOpen = false,
    this.otherDeviceShiftId,
    this.sales,
    this.shiftExpired = false,
  });

  const TenantShiftState.unknown() : this(phase: TenantShiftPhase.unknown);

  final TenantShiftPhase phase;
  final TenantShift? shift;

  /// What the cashier declared the till held, once a close has recorded it.
  final ShiftTenderDeclaration? declaration;

  final String? errorCode;

  /// Whether another business still holds an open shift on this device.
  final bool otherTenantShiftOpen;

  /// Whether this cashier's open shift in this business lives on another
  /// device. Opening a second shift is refused so the two can never diverge.
  final bool otherDeviceShiftOpen;

  /// The canonical shift that refusal names, when there is exactly one.
  ///
  /// **It exists so the refusal is not a dead end.** The till cannot summarize
  /// a shift whose sales it never held, but it can close one - see
  /// [TenantShiftController.closeShiftWithoutEvidence] - and the surface
  /// offering that needs to know which shift it would be closing. Null where no
  /// such shift was found, or where more than one was: closing the wrong one is
  /// worse than offering nothing.
  final String? otherDeviceShiftId;

  /// What this device can prove about the sales recorded during the shift.
  final ShiftSalesSummary? sales;

  /// Whether this shift has outlived the cap, whatever [phase] happens to say.
  ///
  /// **Separate from `phase == expired` on purpose.** Starting a cash count
  /// moves the phase to `closing`, and without this flag that would hand an
  /// expired shift back its till - close the sheet, sell again, repeat. The
  /// phase describes what the shift is *doing*; this describes what it *is*.
  final bool shiftExpired;

  bool get blocksTenantSwitch =>
      phase == TenantShiftPhase.closing ||
      phase == TenantShiftPhase.closedPending ||
      phase == TenantShiftPhase.expired;
}

typedef TenantShiftIdFactory = String Function();
typedef TenantShiftClock = DateTime Function();

/// Owns exactly one shift for the selected tenant session.
///
/// Every operation captures the live session, is serialized by one local lock,
/// and re-checks UID, tenant, and epoch before publishing a result, so a tenant
/// switch during an in-flight write can never update the new session's UI.
///
/// The controller trusts only canonical server state. Durable local state names
/// the shift to re-read; it never decides that one is open.
final class TenantShiftController extends ChangeNotifier {
  TenantShiftController({
    required TenantSessionController sessionController,
    required HiveTenantShiftState localState,
    required TenantDataReader reader,
    required TenantShiftWriter writer,
    required ShiftSalesLedger salesLedger,
    required String deviceId,
    required TenantShiftOnlineCheck isOnline,
    TenantShiftIdFactory? shiftIdFactory,
    TenantShiftClock? clock,
    CheckoutBusinessDateResolver? businessDateResolver,
  }) : _sessionController = sessionController,
       _localState = localState,
       _reader = reader,
       _writer = writer,
       _salesLedger = salesLedger,
       _deviceId = validateCheckoutDeviceId(deviceId),
       _isOnline = isOnline,
       _shiftIdFactory = shiftIdFactory ?? _generateShiftId,
       _clock = clock ?? _utcNow,
       _businessDateResolver = businessDateResolver ?? checkoutBusinessDate;

  final TenantSessionController _sessionController;
  final HiveTenantShiftState _localState;
  final TenantDataReader _reader;
  final TenantShiftWriter _writer;
  final ShiftSalesLedger _salesLedger;
  final String _deviceId;
  final TenantShiftOnlineCheck _isOnline;
  final TenantShiftIdFactory _shiftIdFactory;
  final TenantShiftClock _clock;
  final CheckoutBusinessDateResolver _businessDateResolver;
  Future<void> _tail = Future<void>.value();
  TenantShiftState _state = const TenantShiftState.unknown();

  /// How long one shift may run before it must be closed.
  ///
  /// **Set by the product owner on 2026-08-26, and it is what bounds offline
  /// trading.** A device that has been away from the network for a day reaches
  /// this and stops selling. That is the intent rather than a side effect: it
  /// is what stops a till drifting indefinitely on remembered state.
  ///
  /// **It no longer bounds *closing*.** Until 2026-09-05 a close needed the
  /// server, so an expired shift on an offline device could neither sell nor
  /// be finished - the till was simply stuck. A close is recorded locally and
  /// replayed now, so the way out of this state is always available.
  static const maximumShiftDuration = Duration(hours: 24);

  TenantShiftState get state => _state;

  /// Whether this shift may no longer take sales, for either reason.
  ///
  /// Both land on [TenantShiftPhase.expired] because the till does the same
  /// thing in each case: it stops selling and offers only a close.
  bool _hasExpired(TenantShiftLocalRecord record) =>
      _outlivedItsDuration(record) || _isFutureDated(record);

  /// Whether this shift has outlived [maximumShiftDuration].
  bool _outlivedItsDuration(TenantShiftLocalRecord record) =>
      _clock().toUtc().difference(record.openedAt) >= maximumShiftDuration;

  /// Whether this shift is filed under a day that has not arrived yet.
  ///
  /// **The clock moved backwards and the shift kept its day.** A shift owns the
  /// business date every sale rung through it is filed under - deliberately, so
  /// a till trading past midnight keeps one day's takings together, and
  /// `CheckoutDraft` takes the date from the shift rather than from the clock.
  /// The corollary is that a device whose clock was wrong when the shift opened
  /// goes on stamping sales with a date that has not happened once the clock is
  /// corrected. The takings land on a day the shop has not traded, and the
  /// home, the daily summary and reconciliation are all reading a different
  /// one - so the figures never move and nothing says why.
  ///
  /// **[_outlivedItsDuration] cannot catch this.** `Duration.difference` is
  /// signed, so a record opened in the future reads as a negative age and never
  /// reaches [maximumShiftDuration]: that shift would sell indefinitely.
  ///
  /// **Compared as business dates, not as instants**, because that is the harm.
  /// A shift opened minutes ahead files under the same day and is nobody's
  /// problem; one opened yesterday is still honestly yesterday's, and must keep
  /// selling. Only a date the shop has not reached is refused.
  bool _isFutureDated(TenantShiftLocalRecord record) =>
      record.businessDate.compareTo(checkoutBusinessDate(_clock().toUtc())) > 0;

  /// The phase a durable record implies, with no server involved.
  ///
  /// A record on disk *is* this device's belief that a shift is open - see
  /// [_otherTenantShiftOpen], which has always read it that way, because
  /// [_settle] deletes the record the moment the server says otherwise.
  TenantShiftPhase _phaseOf(TenantShiftLocalRecord? record) {
    if (record == null) return TenantShiftPhase.none;
    // First, and ahead of expiry: a shift that was closed here is closed,
    // whatever the clock has done to it since.
    if (record.closedAt != null) return TenantShiftPhase.closedPending;
    if (record.closeInProgress) return TenantShiftPhase.closing;
    if (_hasExpired(record)) return TenantShiftPhase.expired;
    return TenantShiftPhase.open;
  }

  /// The installation identity recorded on every shift this device opens.
  String get deviceId => _deviceId;

  /// Re-reads the canonical shift named by durable local state.
  ///
  /// The signature matches `TenantRouteGuard`, so the guard supplies the exact
  /// session it authorized.
  Future<TenantShiftState> restore(TenantSession session) =>
      _run(session, (captured) async {
        await _discardUnfinishedCashCount(captured);
        // **Draw what this device already knows, before asking the server.**
        // This is the other half of the "checking your shift" flash: the
        // controller starts at `unknown`, so the first entry of every run drew
        // a spinner over a till whose shift was sitting on disk the whole
        // time. Publishing the local view first means the canonical read
        // refreshes a till that is already on screen.
        //
        // **Only when a record exists.** With none, this device genuinely does
        // not know - the server may hold a shift for this cashier that
        // `_adoptDiscoveredShift` is about to recover - and guessing `none`
        // here would flash the *Start your shift* modal and then take it away.
        final known = await _localState.read(
          uid: captured.uid,
          tenantId: captured.tenantId,
        );
        if (known != null && _owns(captured)) {
          _publish(
            captured,
            TenantShiftState(
              phase: _phaseOf(known),
              declaration: known.declaration,
              shiftExpired: _hasExpired(known),
              otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
              sales: await _displaySummary(captured, known.shiftId),
            ),
          );
        }
        if (!await _online()) return _offlineView(captured);
        final record = await _localState.read(
          uid: captured.uid,
          tenantId: captured.tenantId,
        );
        if (record == null) {
          // Durable local state can be lost with a reinstall or a cleared
          // installation. Discovery restores the same canonical shift instead
          // of letting the next open create a duplicate.
          final adopted = await _adoptDiscoveredShift(captured);
          if (adopted != null) return adopted;
        }
        return _settle(captured);
      });

  /// Opens one shift for the selected session.
  ///
  /// [openingFloatMinor] is the change the cashier says the drawer starts
  /// with. It defaults to none, so a caller that does not ask for one opens a
  /// shift whose takings are compared against its sales alone.
  Future<TenantShiftState> openShift({int openingFloatMinor = 0}) =>
      _run(_sessionController.session, (captured) async {
        final existing = await _localState.read(
          uid: captured.uid,
          tenantId: captured.tenantId,
        );
        if (existing != null) {
          return _settle(captured, errorCode: 'shift_already_open');
        }
        if (captured.role == TenantRole.cashier &&
            await _otherTenantShiftOpen(captured)) {
          return _publish(
            captured,
            TenantShiftState(
              phase: TenantShiftPhase.none,
              errorCode: 'other_tenant_shift_open',
              otherTenantShiftOpen: true,
            ),
          );
        }
        // **The two guards above are what keep one device to one shift, and
        // both read only this device.** That is why opening offline is safe to
        // allow at all: the duplicate check does not depend on the network.
        final online = await _online();

        // A canonical open shift always wins over creating a new one - but only
        // the server can say that one exists, so this step is skipped rather
        // than failed when there is no network.
        if (online) {
          final adopted = await _adoptDiscoveredShift(
            captured,
            adoptedErrorCode: 'shift_already_open',
            // Adopting this device's own canonical shift still wins over
            // creating a duplicate. Only the refusal for somebody else's is
            // gone; `restore` still reports one so the surface can say so.
            refuseOnOtherDevice: false,
          );
          if (adopted != null) return adopted;
          if (!_owns(captured)) return _staleView();
        }

        final repository = TenantShiftRepository(
          session: captured,
          reader: _reader,
        );
        // One instant for the open: the record keeps it, the write sends it,
        // and a replay sends it again.
        final openedAt = _localState.now();
        final intent = repository.buildOpenIntent(
          shiftId: _validatedShiftId(),
          deviceId: _deviceId,
          businessDate: _businessDate(),
          openedAt: openedAt,
          openingFloatMinor: openingFloatMinor,
        );
        if (!_owns(captured)) return _staleView();

        // The intent becomes durable before the write, so an unacknowledged
        // create is settled by a canonical read instead of being forgotten.
        await _localState.save(
          TenantShiftLocalRecord(
            uid: captured.uid,
            tenantId: captured.tenantId,
            shiftId: intent.shiftId,
            businessDate: intent.businessDate,
            deviceId: intent.deviceId,
            openingFloatMinor: intent.openingFloatMinor,
            serverConfirmedOpen: false,
            closeInProgress: false,
            updatedAt: openedAt,
            openedAt: openedAt,
          ),
        );
        if (!online) {
          // **The shift is open and the till may sell.** The intent is already
          // durable, and `_settle` replays it on the first connected read - see
          // [_replayUnsentOpen], which is what stops this record being mistaken
          // later for a shift the server closed.
          return _publish(
            captured,
            TenantShiftState(
              phase: TenantShiftPhase.open,
              errorCode: 'offline',
              otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
              sales: await _displaySummary(captured, intent.shiftId),
            ),
          );
        }
        final result = await _writer.openShift(intent);
        if (!_owns(captured)) return _staleView();
        // **`allowReplay: false`, and the distinction matters.** A create that
        // just failed with the network up, against a shift the server has
        // never seen, is a shift that was never opened - no till was drawn and
        // no sale exists - so the canonical read is allowed to clear it,
        // exactly as before. The replay in [_replayUnsentOpen] is for the
        // other case: a record that has been sitting on this device selling.
        return _settle(
          captured,
          errorCode: result.kind == TenantShiftWriteKind.committed
              ? null
              : result.reasonCode ?? 'shift_open_unconfirmed',
          allowReplay: false,
        );
      });

  /// Starts an unfinished cash count, which blocks tenant switching at once.
  Future<TenantShiftState> startCashCount() =>
      _run(_sessionController.session, (captured) async {
        final record = await _localState.read(
          uid: captured.uid,
          tenantId: captured.tenantId,
        );
        if (record == null) {
          return _settle(captured, errorCode: 'no_open_shift');
        }
        if (record.closeInProgress) return _settle(captured);
        await _localState.save(
          record.copyWith(
            closeInProgress: true,
            clearDeclaration: true,
            updatedAt: _localState.now(),
          ),
        );
        return _settle(captured);
      });

  /// Abandons an unfinished cash count without closing the shift.
  Future<TenantShiftState> cancelCashCount() =>
      _run(_sessionController.session, (captured) async {
        final record = await _localState.read(
          uid: captured.uid,
          tenantId: captured.tenantId,
        );
        if (record == null || !record.closeInProgress) {
          return _settle(captured);
        }
        await _localState.save(
          record.copyWith(
            closeInProgress: false,
            clearDeclaration: true,
            updatedAt: _localState.now(),
          ),
        );
        return _settle(captured);
      });

  /// Completes the cash count and closes the canonical shift.
  ///
  /// An unsettled close becomes `closedPending` rather than staying `closing`:
  /// the declared figures and the blocked tenant switch both survive until a
  /// canonical read proves the server accepted it, and the till stops selling
  /// against a shift whose drawer has already been counted.
  ///
  /// **No figure here is compared with anything.** The declaration is what the
  /// cashier says the till holds, taken without showing them what is expected,
  /// and a difference is never a reason to refuse a close - the shop would be
  /// left holding an open shift over a discrepancy that closing is how you
  /// report. Reconciliation makes the comparison later, from the sales the
  /// server holds.
  /// [settlementId] names the one drawer count this close belongs to, so the
  /// shifts it sweeps up afterwards can be recognised as settled by it. See
  /// [newSettlementId]; null closes this shift alone, exactly as before.
  Future<TenantShiftState> closeShift({
    required ShiftTenderDeclaration declaration,
    String? settlementId,
  }) => _run(_sessionController.session, (captured) async {
    final record = await _localState.read(
      uid: captured.uid,
      tenantId: captured.tenantId,
    );
    if (record == null) {
      return _settle(captured, errorCode: 'no_open_shift');
    }
    if (!record.closeInProgress) {
      return _settle(captured, errorCode: 'cash_count_not_started');
    }
    // **Held, not just written.** Everything below works from this version:
    // `record` was read before the declaration was saved onto it, and an
    // unsent close built from that one would carry no figures - which
    // `_replayUnsentClose` would then have to refuse.
    final counted = record.copyWith(
      declaration: declaration,
      updatedAt: _localState.now(),
    );
    await _localState.save(counted);

    // The closing summary must describe every sale of the shift. While a
    // local sale is unconfirmed the device cannot prove the total, so the
    // close waits instead of publishing a figure reconciliation will
    // contradict.
    final sales = await _salesLedger.summarize(
      uid: captured.uid,
      tenantId: captured.tenantId,
      shiftId: record.shiftId,
    );
    if (!sales.isComplete) {
      return _settle(captured, errorCode: 'unsynchronized_shift_sales');
    }
    // **Closing no longer needs the server**, at the developer's direction
    // on 2026-09-05. It used to refuse outright with
    // `close_needs_connection`, which left a shop that had counted its cash
    // holding an open shift it could not finish - and the till still
    // selling against it, which is the state the refusal was trying to
    // avoid in the first place.
    //
    // **What made that safe to change is the check above, not the network.**
    // `sales.isComplete` is read from this device's own outbox: a shift
    // with any unsent sale still cannot close, offline or on. So reaching
    // this line offline means every sale of the shift is already on the
    // server and its closing figures are provable. The write is the only
    // thing missing, and a write is a thing this app knows how to carry.
    final online = await _online();
    final repository = TenantShiftRepository(
      session: captured,
      // Offline the canonical document is read from this device's copy.
      // `Source.serverAndCache` blocks on a network the SDK still believes
      // in, which on one bar of signal is a stall rather than a fallback.
      reader: online ? _reader : (_reader.cached ?? _reader),
    );
    final TenantShift? shift;
    try {
      shift = await repository.readShift(record.shiftId);
    } catch (_) {
      // A cache with no copy of the shift cannot prove it is open, and a
      // close must never be recorded against a shift this device cannot
      // describe.
      return _offlineView(captured, errorCode: 'close_needs_connection');
    }
    if (!_owns(captured)) return _staleView();
    if (shift == null || !shift.isOpen) {
      return online
          ? _settle(captured, errorCode: 'shift_not_open')
          : _offlineView(captured, errorCode: 'shift_not_open');
    }
    // One instant for the close, for the reason the open takes one: the write
    // sends it, and if the write cannot land the unsent record keeps it.
    final closedAt = _localState.now();
    final intent = repository.buildCloseIntent(
      shift: shift,
      closingCashMinor: declaration.cashMinor,
      sales: sales,
      closedAt: closedAt,
      declaration: declaration,
      settlementId: settlementId,
    );
    final result = online
        ? await _writer.closeShift(intent)
        : const TenantShiftWriteResult.unavailable();
    if (!_owns(captured)) return _staleView();
    if (result.kind == TenantShiftWriteKind.committed) {
      return _settle(captured);
    }
    if (result.kind == TenantShiftWriteKind.rejected) {
      // The server refused this close on its own terms - a foreign shift,
      // a shift already ended. Nothing was written and nothing should be
      // remembered as written; the canonical read settles what is true.
      return _settle(
        captured,
        errorCode: result.reasonCode ?? 'shift_close_unconfirmed',
      );
    }
    // Unavailable or ambiguous. Either way the close is now a fact about
    // this device: the count is over, the till stops selling against this
    // shift, and `_replayUnsentClose` sends it on the next restore.
    return _recordUnsentClose(captured, counted, closedAt: closedAt);
  });

  /// Closes a canonical open shift this device holds none of the sales for.
  ///
  /// **The way out of a shift opened on an installation that no longer
  /// exists.** `_adoptDiscoveredShift` refuses such a shift and is right to:
  /// the closing summary is built from local sale evidence, which only the
  /// issuing install ever held. But refusing was all it did, so a cashier whose
  /// device had been wiped met a till that would not open a shift, would not
  /// close the old one, and named a device they were already holding. The only
  /// remedy was an edit to the database.
  ///
  /// **It does not invent the summary; it declines to give one.** The close
  /// writes zeros under `closedWithoutEvidence`, which reconciliation reads as
  /// *do not believe these figures* rather than as a shift that took nothing.
  /// The declaration is still asked for and still recorded - it needs no sale
  /// evidence, and the server derives the other side of the comparison itself -
  /// so this records more than the dead end it replaces.
  ///
  /// Online only. There is no durable record to replay from, and inventing one
  /// would tell the till it may sell against a shift whose device id will make
  /// the server refuse every sale.
  /// **[declaration] is null where the drawer was counted onto another shift.**
  /// Two open shifts for one cashier still mean one till and one count - see
  /// `TenantShiftRepository.buildRecoveryCloseIntent`. Asking twice would record
  /// the same money against both.
  /// [settlementId] is the count this shift is being settled by, where one
  /// exists - see [closeShift]. Null is a shift closed on its own terms, which
  /// is what the recovery controls on the close sheet do.
  Future<TenantShiftState> closeShiftWithoutEvidence({
    required String shiftId,
    ShiftTenderDeclaration? declaration,
    String? settlementId,
  }) => _run(_sessionController.session, (captured) async {
    if (!await _online()) {
      return _offlineView(captured, errorCode: 'orphan_close_needs_connection');
    }
    final repository = TenantShiftRepository(
      session: captured,
      reader: _reader,
    );
    final shifts = await repository.findOpenShifts(collectionReader: _reader);
    if (!_owns(captured)) return _staleView();
    // `findOpenShifts` already proves each shift belongs to this cashier in
    // this business. What is left to prove is that exactly one of them is the
    // one being closed, and that it is not this device's own - a shift with
    // local evidence must go through `closeShift`, which can summarize it.
    final matches = shifts
        .where((shift) => shift.id == shiftId && shift.deviceId != _deviceId)
        .toList(growable: false);
    if (matches.isEmpty) {
      return _settle(captured, errorCode: 'orphan_shift_not_found');
    }
    if (matches.length > 1) {
      return _settle(captured, errorCode: 'orphan_shift_ambiguous');
    }
    final TenantShiftWriteResult result;
    try {
      result = await _writer.closeShift(
        repository.buildRecoveryCloseIntent(
          shift: matches.single,
          closedAt: _localState.now(),
          declaration: declaration,
          settlementId: settlementId,
        ),
      );
    } on TenantShiftException catch (error) {
      return _settle(captured, errorCode: error.code);
    }
    if (!_owns(captured)) return _staleView();
    // **No local record either way.** A committed close leaves nothing to
    // remember, and a refused one must not leave the till believing it owns a
    // shift it cannot sell against. The canonical read decides what is true.
    return _settle(
      captured,
      errorCode: result.kind == TenantShiftWriteKind.committed
          ? null
          : result.reasonCode ?? 'shift_close_unconfirmed',
    );
  });

  /// A fresh name for one drawer count, to be worn by every shift it settles.
  ///
  /// **Minted before the count is sent, not after.** The counted shift is
  /// closed first and the swept ones follow, so the name has to exist before
  /// the first write or the two halves cannot be recognised as one settlement.
  ///
  /// It is a label for grouping and never an identifier anything is fetched by,
  /// so it needs to be unique among this cashier's closes and nothing more.
  String newSettlementId() => _generateSettlementId();

  /// Every open shift of this cashier's that this exact installation is not
  /// holding, so all of them can be closed onto one count.
  ///
  /// **Enumerated rather than singled out, which is what
  /// [_adoptDiscoveredShift] does and cannot stop doing.** That one names at
  /// most one shift and deliberately names none where more than one candidate
  /// exists, because closing the wrong one is worse than closing none. Closing
  /// *all* of them has no wrong one to pick, so what it needs is the list -
  /// and a caller reading `otherDeviceShiftId` was silently settling for the
  /// first of several.
  ///
  /// **Online only, and empty rather than throwing when it cannot ask.**
  /// [closeShiftWithoutEvidence] is online-only itself, and a list read off the
  /// cache would name shifts that have since been closed elsewhere. Failing to
  /// enumerate is not the same as there being none, but the caller's next
  /// restore asks again and each id is re-proved at the close in any case.
  Future<List<String>> otherOpenShiftIds() async {
    final captured = _sessionController.session;
    if (captured == null || !captured.canAccess()) return const <String>[];
    if (!await _online()) return const <String>[];
    final List<TenantShift> shifts;
    try {
      shifts = await TenantShiftRepository(
        session: captured,
        reader: _reader,
      ).findOpenShifts(collectionReader: _reader);
    } catch (_) {
      return const <String>[];
    }
    if (!_owns(captured)) return const <String>[];
    return List<String>.unmodifiable(
      shifts
          .where((shift) => shift.deviceId != _deviceId)
          .map((shift) => shift.id),
    );
  }

  /// Remembers a close this device made but could not confirm.
  ///
  /// Ambiguity is recorded the same way as being offline, and deliberately: a
  /// close whose outcome is unknown may have landed, and replaying it is a
  /// second `update` of the same fields on the same document, which changes
  /// nothing if it did.
  Future<TenantShiftState> _recordUnsentClose(
    TenantSession captured,
    TenantShiftLocalRecord record, {
    required DateTime closedAt,
  }) async {
    final closed = record.copyWith(
      closedAt: closedAt,
      updatedAt: _localState.now(),
    );
    await _localState.save(closed);
    if (!_owns(captured)) return _staleView();
    return _publish(
      captured,
      TenantShiftState(
        phase: _phaseOf(closed),
        declaration: closed.declaration,
        shiftExpired: _hasExpired(closed),
        otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
        sales: await _displaySummary(captured, closed.shiftId),
      ),
    );
  }

  /// Reads canonical state and reconciles the durable local record with it.
  Future<TenantShiftState> _settle(
    TenantSession captured, {
    String? errorCode,
    bool allowReplay = true,
  }) async {
    final record = await _localState.read(
      uid: captured.uid,
      tenantId: captured.tenantId,
    );
    if (record == null) {
      return _publish(
        captured,
        TenantShiftState(
          phase: TenantShiftPhase.none,
          errorCode: errorCode,
          otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
        ),
      );
    }

    final shift = await TenantShiftRepository(
      session: captured,
      reader: _reader,
    ).readShift(record.shiftId);
    if (!_owns(captured)) return _staleView();

    if (shift == null && !record.serverConfirmedOpen && allowReplay) {
      // **An absent shift the server never acknowledged is unsent, not
      // closed, and deleting it here would destroy a trading day.**
      // `serverConfirmedOpen` is the whole distinction: without it this branch
      // cannot tell a shift the server ended from one it has never heard of.
      // The second kind is what opening offline produces, and every sale in
      // the outbox is stamped with its `shiftId` - clearing the record would
      // strand them all with no shift to be summarized into, counted cash
      // included.
      return _replayUnsentOpen(captured, record, errorCode: errorCode);
    }

    if (shift != null && shift.isOpen && record.closedAt != null) {
      // **Closed here, still open there.** The close was made with no network
      // or with an uncertain outcome; this is the reconnect that sends it.
      return _replayUnsentClose(captured, record, shift, errorCode: errorCode);
    }

    if (shift == null || !shift.isOpen) {
      // The server is authoritative: an absent or closed shift ends the local
      // record, including the counted cash that was blocking a switch.
      await _localState.clear(uid: captured.uid, tenantId: captured.tenantId);
      return _publish(
        captured,
        TenantShiftState(
          phase: TenantShiftPhase.none,
          shift: shift,
          errorCode: errorCode,
          otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
        ),
      );
    }

    // **Only the server may confirm a shift, and the read above is not proof it
    // did.** `_reader` asks for `Source.serverAndCache`, which falls back to
    // local storage whenever the server cannot be reached - and local storage
    // holds this device's own `set` from the moment it is made, before anything
    // has been sent. So a create that timed out reads back here as a perfectly
    // good open shift, and promoting on it records a confirmation that never
    // happened.
    //
    // **What that costs is a trading day.** `serverConfirmedOpen` is the only
    // thing separating *the server ended this shift* from *the server has never
    // heard of it*: with the flag wrongly set, a create the server later refuses
    // - a deactivated cashier is the ordinary way - sends the next settle down
    // the branch below that clears the record, instead of [_replayUnsentOpen].
    // Every sale in the outbox is stamped with that shift id, `validSaleShift`
    // requires the shift to exist, and a rejected sale is retried rather than
    // escalated - so the day is refused for ever, in silence.
    //
    // Confirmed on a device on 2026-09-15; see
    // `integration_test/shift_pending_write_test.dart`.
    //
    // **Failing to prove it is not a refusal.** The record simply stays
    // unconfirmed and the next settle asks again. Nothing else is held up by
    // that: the till sells against an unconfirmed shift by design since
    // 2026-09-05, and staying unconfirmed is the state that keeps the replay
    // available.
    if (!record.serverConfirmedOpen &&
        await _serverHoldsShift(captured, record.shiftId)) {
      await _localState.save(
        record.copyWith(
          serverConfirmedOpen: true,
          updatedAt: _localState.now(),
        ),
      );
    }
    return _publish(
      captured,
      TenantShiftState(
        // The clock applies to a canonically open shift exactly as it does to
        // a remembered one - a shift running past the cap is over either way.
        phase: _phaseOf(record),
        shift: shift,
        declaration: record.declaration,
        shiftExpired: _hasExpired(record),
        errorCode: errorCode,
        otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
        // **Summarized for any open shift, not only during a count.** It was
        // gated on `closeInProgress`, which made the running shift's takings
        // unreadable until a cashier started closing - and the home's figure
        // grid is no substitute: that reads `daily_metrics`, which is
        // reconciliation-derived, business-wide, and shows an em dash for a
        // day nobody has reconciled yet. This is the other number: what *this
        // device* can prove *this shift* has taken, right now.
        //
        // It costs one local outbox read and no network, which is what makes
        // it affordable on every settle.
        sales: await _displaySummary(captured, record.shiftId),
      ),
    );
  }

  /// Whether the **server** holds this shift, asked so the cache cannot answer.
  ///
  /// The question is deliberately narrower than [_settle]'s own read: not *what
  /// is this shift* but *has the create landed*, which only a server-backed read
  /// can say. Existence is the whole test - a shift the server has closed has
  /// still been acknowledged, and [_settle]'s earlier branches have already
  /// dealt with that case before this is reached.
  ///
  /// **Every failure answers no**, including a reader with no server-only mode
  /// at all. Being unable to prove a confirmation is not the same as
  /// disproving it, and the record stays unconfirmed either way - which is the
  /// state that keeps [_replayUnsentOpen] available and the shift's sales
  /// attached to something.
  Future<bool> _serverHoldsShift(TenantSession captured, String shiftId) async {
    final reader = _reader.serverBacked;
    if (reader == null) return false;
    try {
      final shift = await TenantShiftRepository(
        session: captured,
        reader: reader,
      ).readShift(shiftId);
      return shift != null;
    } catch (_) {
      return false;
    }
  }

  /// Sends a close that was recorded while this device had no network.
  ///
  /// **The figures are the ones that were counted, not new ones.** The cash is
  /// read from the durable record and the sales are re-summarized from the
  /// outbox, which cannot have changed: a shift that is closed here takes no
  /// further sales, and `sales.isComplete` was already true when the count was
  /// accepted. Re-summarizing rather than storing the totals keeps one source
  /// for them.
  ///
  /// A refusal leaves the record exactly as it is, on the same grounds as
  /// [_replayUnsentOpen]: the till is not selling against this shift either
  /// way, and the next restore tries again.
  Future<TenantShiftState> _replayUnsentClose(
    TenantSession captured,
    TenantShiftLocalRecord record,
    TenantShift shift, {
    String? errorCode,
  }) async {
    final declaration = record.declaration;
    final countedCashMinor = declaration?.cashMinor;
    if (countedCashMinor == null) {
      // A closed record with no figures at all cannot be turned into a close.
      // It should not exist - `closeShift` writes them with the close - so this
      // fails closed rather than inventing one.
      return _publish(
        captured,
        TenantShiftState(
          phase: _phaseOf(record),
          shift: shift,
          shiftExpired: _hasExpired(record),
          errorCode: errorCode ?? 'invalid_closing_cash',
          otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
          sales: await _displaySummary(captured, record.shiftId),
        ),
      );
    }
    final sales = await _salesLedger.summarize(
      uid: captured.uid,
      tenantId: captured.tenantId,
      shiftId: record.shiftId,
    );
    if (!_owns(captured)) return _staleView();
    final TenantShiftWriteResult result;
    try {
      result = await _writer.closeShift(
        TenantShiftRepository(
          session: captured,
          reader: _reader,
        ).buildCloseIntent(
          shift: shift,
          closingCashMinor: countedCashMinor,
          sales: sales,
          // The drawer was counted when the close was recorded here, however
          // much later it is sent.
          closedAt: record.closedAt ?? _localState.now(),
          declaration: declaration,
        ),
      );
    } on TenantShiftException catch (error) {
      return _publish(
        captured,
        TenantShiftState(
          phase: _phaseOf(record),
          shift: shift,
          declaration: declaration,
          shiftExpired: _hasExpired(record),
          errorCode: errorCode ?? error.code,
          otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
          sales: await _displaySummary(captured, record.shiftId),
        ),
      );
    }
    if (!_owns(captured)) return _staleView();
    if (result.kind == TenantShiftWriteKind.committed) {
      // Confirmed by the write rather than by another canonical read, for the
      // reason [_replayUnsentOpen] gives: a replica that has not caught up
      // must not be able to answer "still open" and undo this.
      await _localState.clear(uid: captured.uid, tenantId: captured.tenantId);
      return _publish(
        captured,
        TenantShiftState(
          phase: TenantShiftPhase.none,
          errorCode: errorCode,
          otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
        ),
      );
    }
    return _publish(
      captured,
      TenantShiftState(
        phase: _phaseOf(record),
        shift: shift,
        declaration: declaration,
        shiftExpired: _hasExpired(record),
        errorCode: errorCode ?? result.reasonCode ?? 'shift_close_unconfirmed',
        otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
        sales: await _displaySummary(captured, record.shiftId),
      ),
    );
  }

  /// Sends an open that was recorded while this device had no network.
  ///
  /// **The same `shiftId`, deliberately.** Sales already in the outbox name it,
  /// and the closing summary is built by matching them - so a fresh id would
  /// leave the shift's own takings attached to a shift that no longer exists.
  ///
  /// A refusal is not fatal here. The record stays exactly as it is and the
  /// till keeps selling against it; the next settle tries again, which is the
  /// same shape the outbox itself uses for a sale that has not landed yet.
  Future<TenantShiftState> _replayUnsentOpen(
    TenantSession captured,
    TenantShiftLocalRecord record, {
    String? errorCode,
  }) async {
    final intent = TenantShiftRepository(session: captured, reader: _reader)
        .buildOpenIntent(
          shiftId: record.shiftId,
          deviceId: record.deviceId,
          businessDate: record.businessDate,
          // When the cashier opened it, which the replay must not move to now.
          openedAt: record.openedAt,
          // From the record, never recomputed: this is the float the cashier
          // typed when they opened offline, and it is the one the shift has to
          // land with.
          openingFloatMinor: record.openingFloatMinor,
        );
    if (!_owns(captured)) return _staleView();
    final result = await _writer.openShift(intent);
    if (!_owns(captured)) return _staleView();
    if (result.kind != TenantShiftWriteKind.committed) {
      return _publish(
        captured,
        TenantShiftState(
          phase: _phaseOf(record),
          declaration: record.declaration,
          shiftExpired: _hasExpired(record),
          // The caller's reason wins where it has one: *a shift is already
          // open on this device* answers what the person just tried to do,
          // where the replay's own code only describes this housekeeping.
          errorCode: errorCode ?? result.reasonCode ?? 'shift_open_unconfirmed',
          otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
          sales: await _displaySummary(captured, record.shiftId),
        ),
      );
    }
    // **Confirmed here rather than by another canonical read.** The write
    // committed, so the server has it; re-reading would risk a replica that
    // has not caught up answering "absent" and clearing the very shift just
    // created. The next restore fills in the canonical document.
    final confirmed = record.copyWith(
      serverConfirmedOpen: true,
      updatedAt: _localState.now(),
    );
    await _localState.save(confirmed);
    return _publish(
      captured,
      TenantShiftState(
        phase: _phaseOf(confirmed),
        declaration: confirmed.declaration,
        shiftExpired: _hasExpired(confirmed),
        errorCode: errorCode,
        otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
        sales: await _displaySummary(captured, confirmed.shiftId),
      ),
    );
  }

  /// Whether [shift] was opened by an installation of this app on this till.
  ///
  /// Compares the durable half of the device IDs - see
  /// [checkoutDeviceHardwareDigest] - which is equal across a reinstall of the
  /// same till and unequal between two tills. A stored ID that predates that
  /// split, or one written by a device whose platform offered nothing durable,
  /// simply never matches, which is the answer this had before.
  bool _openedHere(TenantShift shift) {
    try {
      return checkoutDeviceHardwareDigest(shift.deviceId) ==
          checkoutDeviceHardwareDigest(_deviceId);
    } on ArgumentError {
      return false;
    }
  }

  /// Adopts this cashier's canonical open shift instead of opening a duplicate.
  ///
  /// Returns `null` only when no canonical open shift exists for this cashier
  /// in this business, so the caller may continue. A shift opened on another
  /// device is reported rather than adopted: the closing summary is derived
  /// from local sale evidence, which only the issuing device holds.
  Future<TenantShiftState?> _adoptDiscoveredShift(
    TenantSession captured, {
    String? adoptedErrorCode,
    bool refuseOnOtherDevice = true,
  }) async {
    final shifts = await TenantShiftRepository(
      session: captured,
      reader: _reader,
    ).findOpenShifts(collectionReader: _reader);
    if (!_owns(captured)) return _staleView();
    if (shifts.isEmpty) return null;

    // **Adoption needs the whole ID, and that is not pedantry.** The closing
    // summary is built from this installation's outbox, so only the install
    // that rang the sales can produce it - a match on the durable half alone
    // would adopt a shift whose evidence died with the app data it was wiped
    // with, and the till would then sell against a shift the server refuses
    // every sale for, because `validSaleShift` compares the two IDs in full.
    final local = shifts
        .where((shift) => shift.deviceId == _deviceId)
        .toList(growable: false);
    // The durable half is what answers the *other* question: not "can this
    // install settle the shift" but "is this the same physical till". That one
    // decides what the refusal says and which shift it offers to close.
    final mine = shifts.where(_openedHere).toList(growable: false);
    if (local.isEmpty) {
      // **A shift elsewhere no longer stops one being opened here.** The two
      // guards this used to stand beside read only this device, and this one
      // is skipped entirely with no network - so two open shifts for one
      // cashier is a state opening offline already produces by design. What
      // enforcing it online bought was not an invariant; it was a refusal with
      // a force-close hanging off it, and that close took a live till's
      // counted drawer away on 2026-09-17. Opening alongside is what the
      // offline path has always done, and the count that follows closes both.
      if (!refuseOnOtherDevice) return null;
      return _publish(
        captured,
        TenantShiftState(
          phase: TenantShiftPhase.none,
          // **Whether the other device is this one is worth saying.** A shift
          // opened before this app was reinstalled belongs to an identity that
          // no longer exists, so "close it there first" sends a cashier to a
          // device they are already holding. The refusal is the same - the
          // closing summary comes from local sale evidence, which that
          // installation took with it - but the sentence has to be true.
          errorCode: mine.isNotEmpty
              ? 'shift_open_on_earlier_install'
              : 'shift_open_on_other_device',
          otherDeviceShiftOpen: true,
          // **Only ever an earlier install of this same phone.** The durable
          // half is the whole test: a shift sharing it was left by a copy of
          // the app that no longer exists on this device, so closing it here
          // takes nothing away from anyone. A shift that does not share it
          // belongs to a phone that may simply be offline - which is what a
          // till mid-count looks like from the outside - and it used to be
          // offered here anyway whenever it happened to be the only one found.
          // That fallback closed a live till's counted drawer on 2026-09-17.
          //
          // Nothing is stranded by its absence. Opening no longer waits on this
          // shift, and the count that closes the one opened here closes every
          // other the cashier holds - see `otherOpenShiftIds`.
          otherDeviceShiftId: mine.length == 1 ? mine.single.id : null,
          otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
        ),
      );
    }
    if (local.length > 1) {
      // Two open shifts for one cashier on one device cannot both be settled.
      throw const TenantShiftException('ambiguous_open_shift');
    }

    final shift = local.single;
    await _localState.save(
      TenantShiftLocalRecord(
        uid: captured.uid,
        tenantId: captured.tenantId,
        shiftId: shift.id,
        businessDate: shift.businessDate,
        deviceId: shift.deviceId,
        serverConfirmedOpen: true,
        closeInProgress: false,
        updatedAt: _localState.now(),
        // **The canonical opening time, not now.** Adoption recovers a shift
        // this device lost track of, and dating it to the recovery would reset
        // its age - which is exactly how a shift would outlive the cap by
        // being adopted every day.
        openedAt: shift.startedAt ?? _localState.now(),
      ),
    );
    return _settle(captured, errorCode: adoptedErrorCode);
  }

  /// The honest offline view: only local facts, and all of them.
  ///
  /// **This used to answer `unknown` for an open shift, and that was the bug.**
  /// A device holding a durable record of its own open shift *does* know
  /// something, and reporting `unknown` threw it away - which drew the gate's
  /// spinner over a till that had every right to sell, forever offline and for
  /// a frame on the first entry of every run. Worse, it downgraded a shift the
  /// server had already confirmed.
  ///
  /// Reading the record as belief-in-open is not a new liberty. It is what
  /// [_otherTenantShiftOpen] has always done, and it is sound for the reason
  /// given there: [_settle] clears the record as soon as the server says the
  /// shift is absent or closed, so anything still on disk is a shift this
  /// device believes is open.
  Future<TenantShiftState> _offlineView(
    TenantSession captured, {
    String? errorCode,
  }) async {
    final record = await _localState.read(
      uid: captured.uid,
      tenantId: captured.tenantId,
    );
    final phase = _phaseOf(record);
    return _publish(
      captured,
      TenantShiftState(
        phase: phase,
        declaration: record?.declaration,
        shiftExpired: record != null && _hasExpired(record),
        // The expiry is the more specific truth, and the one the person has to
        // act on: being offline is why they cannot close it, not why they must.
        errorCode: phase == TenantShiftPhase.expired
            ? 'shift_expired_offline'
            : errorCode ?? 'offline',
        otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
        sales: record == null
            ? null
            : await _displaySummary(captured, record.shiftId),
      ),
    );
  }

  /// The shift's takings for display, or null where they cannot be read.
  ///
  /// **Fails soft, and only here.** [ShiftSalesLedger.summarize] raises on
  /// malformed or unattributed local evidence rather than understating a
  /// total, which is right when the figure is about to be written into a
  /// close - and `closeShift` still summarizes for itself and still refuses.
  /// Letting that same failure through here would take a shift card down over
  /// a display line, so a device with one bad outbox record could not open a
  /// shift or sell at all. The line goes missing; the close still refuses.
  Future<ShiftSalesSummary?> _displaySummary(
    TenantSession captured,
    String shiftId,
  ) async {
    try {
      return await _salesLedger.summarize(
        uid: captured.uid,
        tenantId: captured.tenantId,
        shiftId: shiftId,
      );
    } on ShiftSalesLedgerException {
      return null;
    }
  }

  /// Ends a cash count left unfinished by a previous run of the app.
  ///
  /// **A count lives for as long as the sheet a cashier opened it in, chosen
  /// by the product owner on 2026-08-23.** It used to be durable so that an
  /// unfinished count kept blocking a tenant switch across a restart; the
  /// record itself now carries that, because [_settle] deletes it the moment
  /// the server says the shift is closed, so a record existing *is* a believed
  /// open shift and is what [_otherTenantShiftOpen] reads.
  ///
  /// What this buys is the state a durable flag could produce and nobody could
  /// see: an app killed mid-count came back with the till refusing sales, and
  /// the only way out was a `Cancel cash count` button inside a sheet.
  ///
  /// **A count in progress is not kept, and this used to claim it was.** The
  /// comment here said *reopening the sheet still shows what was typed*, which
  /// has never been true of any build that carries this line: nothing persists
  /// a figure while a drawer is being counted. [startCashCount] clears the
  /// declaration outright, [closeShift] is the only writer of one, and
  /// `_ShiftCloseSheetState` has no `initState` and seeds its three boxes from
  /// nothing. So an app killed mid-count loses the count, and the cashier
  /// counts again - which is the cost this deliberately accepts against a till
  /// left out of service, not a cost it avoids.
  Future<void> _discardUnfinishedCashCount(TenantSession captured) async {
    final record = await _localState.read(
      uid: captured.uid,
      tenantId: captured.tenantId,
    );
    if (record == null || !record.closeInProgress) return;
    await _localState.save(
      record.copyWith(closeInProgress: false, updatedAt: _localState.now()),
    );
  }

  /// Whether this cashier believes a shift is open in some other business.
  ///
  /// **The record's existence is the whole test.** It used to also require
  /// `serverConfirmedOpen || closeInProgress`, which quietly let an *open but
  /// not yet confirmed* shift elsewhere pass unless a cash count happened to
  /// be running on it. [_settle] clears the record as soon as the server says
  /// the shift is absent or closed, so anything still on disk is a shift this
  /// device believes is open - confirmed or not.
  Future<bool> _otherTenantShiftOpen(TenantSession captured) async {
    final records = await _localState.recordsForUid(captured.uid);
    return records.any((record) => record.tenantId != captured.tenantId);
  }

  Future<TenantShiftState> _run(
    TenantSession? captured,
    Future<TenantShiftState> Function(TenantSession session) body,
  ) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return Future<TenantShiftState>(() async {
      await previous;
      try {
        if (captured == null || !captured.canAccess()) {
          return const TenantShiftState(
            phase: TenantShiftPhase.unavailable,
            errorCode: 'no_selected_session',
          );
        }
        if (!_owns(captured)) return _staleView();
        return await body(captured);
      } on TenantShiftStateException catch (error) {
        return _publishIfCurrent(captured, error.code);
      } on TenantShiftException catch (error) {
        return _publishIfCurrent(captured, error.code);
      } on ShiftSalesLedgerException catch (error) {
        return _publishIfCurrent(captured, error.code);
      } on TenantScopeViolation {
        return _publishIfCurrent(captured, 'cross_tenant_shift');
      } catch (_) {
        return _publishIfCurrent(captured, 'shift_unavailable');
      } finally {
        release.complete();
      }
    });
  }

  TenantShiftState _publishIfCurrent(TenantSession? captured, String code) {
    final failure = TenantShiftState(
      phase: TenantShiftPhase.unavailable,
      errorCode: code,
    );
    if (captured == null || !_owns(captured)) return _staleView();
    return _publish(captured, failure);
  }

  TenantShiftState _publish(TenantSession captured, TenantShiftState next) {
    if (!_owns(captured)) return _staleView();
    _state = next;
    _publishedFor = captured;
    notifyListeners();
    return next;
  }

  /// The session the currently published state describes.
  ///
  /// Needed because [restore] now publishes this device's own view *before*
  /// the canonical read, so there is a window in which a published state can
  /// be overtaken by a tenant switch. See [_staleView].
  TenantSession? _publishedFor;

  TenantShiftState _staleView() {
    // **A state goes with the session it described.** Leaving the optimistic
    // local view standing after a switch would show one business's shift
    // underneath another business's session, which is the exact confusion
    // every `_owns` check in this file exists to prevent.
    final owner = _publishedFor;
    if (owner != null && !_owns(owner)) {
      _publishedFor = null;
      _state = const TenantShiftState.unknown();
      notifyListeners();
    }
    return const TenantShiftState(
      phase: TenantShiftPhase.unavailable,
      errorCode: 'session_changed',
    );
  }

  Future<bool> _online() async {
    try {
      return await _isOnline();
    } catch (_) {
      return false;
    }
  }

  String _businessDate() {
    try {
      return validateCheckoutBusinessDate(
        _businessDateResolver(_clock().toUtc()),
      );
    } on ArgumentError {
      throw const TenantShiftException('invalid_business_date');
    }
  }

  String _validatedShiftId() {
    final String shiftId;
    try {
      shiftId = _shiftIdFactory();
    } catch (_) {
      throw const TenantShiftException('invalid_shift_id');
    }
    try {
      return validateTenantDocumentId(shiftId, fieldName: 'shiftId');
    } on ArgumentError {
      throw const TenantShiftException('invalid_shift_id');
    }
  }

  bool _owns(TenantSession captured) {
    final current = _sessionController.session;
    return current != null &&
        current.uid == captured.uid &&
        current.tenantId == captured.tenantId &&
        current.epoch == captured.epoch;
  }
}

/// Binds every checkout to the canonical open shift of the selected session.
///
/// It also enforces the frozen cashier restriction: a cashier may not start a
/// checkout in a second business while another business still holds an open or
/// unsettled shift on this device. Owners, admins, and managers may still
/// inspect and transact in another business.
///
/// **A shift this device opened binds sales whether or not the server has
/// acknowledged it yet.** Until 2026-09-05 an unconfirmed shift refused every
/// checkout with `shift_not_confirmed`, which meant a till that opened its
/// shift with no network could not record a single sale - the one thing the
/// whole offline path exists to allow. A shopkeeper who lost signal before
/// opening was simply shut for the day.
///
/// **Nothing about reconciliation needed that refusal.** The shift ID is
/// generated on this device and kept for the life of the shift, and
/// `TenantShiftController._replayUnsentOpen` sends the open under that same ID
/// on the next restore - it says so itself: *"Sales already in the outbox name
/// it, and the closing summary is built by matching them."* So the sales and
/// the shift meet at the server under one ID whichever arrives first, and the
/// closing summary is built by matching them locally either way.
///
/// What still refuses is a shift that is *finished* on this device - closing,
/// or closed and waiting to send - because its figures are settled and a later
/// sale would contradict them.
///
/// Unreadable local state raises, which the draft service turns into a refusal.
final class TenantShiftCheckoutBinder implements CheckoutShiftBinder {
  const TenantShiftCheckoutBinder(this._state, {TenantShiftClock? clock})
    : _clock = clock;

  final HiveTenantShiftState _state;

  /// The clock the cap is measured against, injectable for the same reason
  /// [TenantShiftController]'s is: a test may not wait a day.
  final TenantShiftClock? _clock;

  @override
  Future<CheckoutShiftBinding> bindCheckoutShift(TenantSession session) async {
    final records = await _state.recordsForUid(session.uid);
    if (session.role == TenantRole.cashier &&
        records.any((record) => record.tenantId != session.tenantId)) {
      return const CheckoutShiftBinding.refused('other_tenant_shift_open');
    }

    final current = records
        .where((record) => record.tenantId == session.tenantId)
        .toList(growable: false);
    if (current.length != 1) {
      return const CheckoutShiftBinding.refused('no_open_shift');
    }
    final record = current.single;
    // Closed here and waiting to send: the count is over and its figures are
    // fixed, so this refuses ahead of `closeInProgress` and for a stronger
    // reason - a count in progress can still be abandoned, and this cannot.
    if (record.closedAt != null) {
      return const CheckoutShiftBinding.refused('shift_closed_pending');
    }
    if (record.closeInProgress) {
      return const CheckoutShiftBinding.refused('shift_closing');
    }
    // **The 24-hour cap, enforced where a sale is actually bound.** It was a
    // property of the screen and of nothing else: `TenantShiftPhase.expired`
    // stopped the gate drawing a till, and this - the one thing every sale goes
    // through - never asked. So an expired shift was refused by the picture and
    // accepted by the till, and since nothing recomputes expiry while a till is
    // open, a device left running simply kept selling past the cap it was
    // supposed to stop at.
    //
    // Refusing here is what makes the cap a rule rather than a drawing. The way
    // out is unchanged and still always available: a close needs no network.
    final clock = _clock ?? _utcNow;
    if (clock().toUtc().difference(record.openedAt) >=
        TenantShiftController.maximumShiftDuration) {
      return const CheckoutShiftBinding.refused('shift_expired');
    }
    return CheckoutShiftBinding.bound(
      CheckoutShiftAttribution(
        uid: record.uid,
        tenantId: record.tenantId,
        shiftId: record.shiftId,
        deviceId: record.deviceId,
        businessDate: record.businessDate,
      ),
    );
  }
}

String _generateSettlementId() {
  final random = Random.secure();
  final suffix = List<String>.generate(
    4,
    (_) => random.nextInt(0x10000).toRadixString(16).padLeft(4, '0'),
  ).join();
  return 'st-${DateTime.now().toUtc().millisecondsSinceEpoch}-$suffix';
}

String _generateShiftId() {
  final random = Random.secure();
  final suffix = List<String>.generate(
    4,
    (_) => random.nextInt(0x10000).toRadixString(16).padLeft(4, '0'),
  ).join();
  return 'sh-${DateTime.now().toUtc().millisecondsSinceEpoch}-$suffix';
}

DateTime _utcNow() => DateTime.now().toUtc();
