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
    this.countedCashMinor,
    this.errorCode,
    this.otherTenantShiftOpen = false,
    this.otherDeviceShiftOpen = false,
    this.sales,
    this.shiftExpired = false,
  });

  const TenantShiftState.unknown() : this(phase: TenantShiftPhase.unknown);

  final TenantShiftPhase phase;
  final TenantShift? shift;
  final int? countedCashMinor;
  final String? errorCode;

  /// Whether another business still holds an open shift on this device.
  final bool otherTenantShiftOpen;

  /// Whether this cashier's open shift in this business lives on another
  /// device. Opening a second shift is refused so the two can never diverge.
  final bool otherDeviceShiftOpen;

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
      phase == TenantShiftPhase.closing || phase == TenantShiftPhase.expired;
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
  /// **Set by the product owner on 2026-08-26, and it is also what bounds
  /// offline trading.** Closing needs canonical server data, so a device that
  /// has been away from the network for a day reaches this and can neither
  /// sell nor close until it reconnects. That is the intent rather than a side
  /// effect: it is what stops a till drifting indefinitely on remembered state.
  static const maximumShiftDuration = Duration(hours: 24);

  TenantShiftState get state => _state;

  /// Whether this shift has outlived [maximumShiftDuration].
  bool _hasExpired(TenantShiftLocalRecord record) =>
      _clock().toUtc().difference(record.openedAt) >= maximumShiftDuration;

  /// The phase a durable record implies, with no server involved.
  ///
  /// A record on disk *is* this device's belief that a shift is open - see
  /// [_otherTenantShiftOpen], which has always read it that way, because
  /// [_settle] deletes the record the moment the server says otherwise.
  TenantShiftPhase _phaseOf(TenantShiftLocalRecord? record) {
    if (record == null) return TenantShiftPhase.none;
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
              countedCashMinor: known.countedCashMinor,
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
  Future<TenantShiftState> openShift() =>
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
          );
          if (adopted != null) return adopted;
          if (!_owns(captured)) return _staleView();
        }

        final repository = TenantShiftRepository(
          session: captured,
          reader: _reader,
        );
        final intent = repository.buildOpenIntent(
          shiftId: _validatedShiftId(),
          deviceId: _deviceId,
          businessDate: _businessDate(),
        );
        if (!_owns(captured)) return _staleView();

        // The intent becomes durable before the write, so an unacknowledged
        // create is settled by a canonical read instead of being forgotten.
        final openedAt = _localState.now();
        await _localState.save(
          TenantShiftLocalRecord(
            uid: captured.uid,
            tenantId: captured.tenantId,
            shiftId: intent.shiftId,
            businessDate: intent.businessDate,
            deviceId: intent.deviceId,
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
            clearCountedCash: true,
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
            clearCountedCash: true,
            updatedAt: _localState.now(),
          ),
        );
        return _settle(captured);
      });

  /// Completes the cash count and closes the canonical shift.
  ///
  /// An unsettled close deliberately stays `closing`: the counted cash and the
  /// blocked tenant switch both survive until a canonical read proves the
  /// server accepted the close.
  Future<TenantShiftState> closeShift({required int countedCashMinor}) =>
      _run(_sessionController.session, (captured) async {
        if (countedCashMinor < 0 || countedCashMinor > maximumShiftCashMinor) {
          return _settle(captured, errorCode: 'invalid_closing_cash');
        }
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
        await _localState.save(
          record.copyWith(
            countedCashMinor: countedCashMinor,
            updatedAt: _localState.now(),
          ),
        );

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
        if (!await _online()) {
          // **Closing is the one shift action that genuinely needs the
          // server**, so it says that rather than reporting a general offline
          // note against a shift the till is otherwise still selling against.
          return _offlineView(captured, errorCode: 'close_needs_connection');
        }

        final repository = TenantShiftRepository(
          session: captured,
          reader: _reader,
        );
        final shift = await repository.readShift(record.shiftId);
        if (!_owns(captured)) return _staleView();
        if (shift == null || !shift.isOpen) {
          return _settle(captured, errorCode: 'shift_not_open');
        }
        final result = await _writer.closeShift(
          repository.buildCloseIntent(
            shift: shift,
            closingCashMinor: countedCashMinor,
            sales: sales,
          ),
        );
        if (!_owns(captured)) return _staleView();
        return _settle(
          captured,
          errorCode: result.kind == TenantShiftWriteKind.committed
              ? null
              : result.reasonCode ?? 'shift_close_unconfirmed',
        );
      });

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

    if (!record.serverConfirmedOpen) {
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
        countedCashMinor: record.countedCashMinor,
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
        );
    if (!_owns(captured)) return _staleView();
    final result = await _writer.openShift(intent);
    if (!_owns(captured)) return _staleView();
    if (result.kind != TenantShiftWriteKind.committed) {
      return _publish(
        captured,
        TenantShiftState(
          phase: _phaseOf(record),
          countedCashMinor: record.countedCashMinor,
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
        countedCashMinor: confirmed.countedCashMinor,
        shiftExpired: _hasExpired(confirmed),
        errorCode: errorCode,
        otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
        sales: await _displaySummary(captured, confirmed.shiftId),
      ),
    );
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
  }) async {
    final shifts = await TenantShiftRepository(
      session: captured,
      reader: _reader,
    ).findOpenShifts(collectionReader: _reader);
    if (!_owns(captured)) return _staleView();
    if (shifts.isEmpty) return null;

    final local = shifts
        .where((shift) => shift.deviceId == _deviceId)
        .toList(growable: false);
    if (local.isEmpty) {
      return _publish(
        captured,
        TenantShiftState(
          phase: TenantShiftPhase.none,
          errorCode: 'shift_open_on_other_device',
          otherDeviceShiftOpen: true,
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
        countedCashMinor: record?.countedCashMinor,
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
  /// the only way out was a `Cancel cash count` button inside a sheet. The
  /// counted figure is deliberately *not* discarded with it - reopening the
  /// sheet still shows what was typed - because losing a number costs a
  /// recount and a till stuck out of service costs the day.
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
/// The shift must already be server-confirmed. A shift the server has not
/// acknowledged might not exist, and a sale bound to it could never be
/// reconciled, so the checkout is refused instead. Unreadable local state
/// raises, which the draft service turns into a refusal.
final class TenantShiftCheckoutBinder implements CheckoutShiftBinder {
  const TenantShiftCheckoutBinder(this._state);

  final HiveTenantShiftState _state;

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
    if (!record.serverConfirmedOpen) {
      return const CheckoutShiftBinding.refused('shift_not_confirmed');
    }
    if (record.closeInProgress) {
      return const CheckoutShiftBinding.refused('shift_closing');
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

String _generateShiftId() {
  final random = Random.secure();
  final suffix = List<String>.generate(
    4,
    (_) => random.nextInt(0x10000).toRadixString(16).padLeft(4, '0'),
  ).join();
  return 'sh-${DateTime.now().toUtc().millisecondsSinceEpoch}-$suffix';
}

DateTime _utcNow() => DateTime.now().toUtc();
