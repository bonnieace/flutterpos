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
  });

  const TenantShiftState.unknown() : this(phase: TenantShiftPhase.unknown);

  final TenantShiftPhase phase;
  final TenantShift? shift;
  final int? countedCashMinor;
  final String? errorCode;

  /// Whether another business still holds an open shift on this device.
  final bool otherTenantShiftOpen;

  bool get blocksTenantSwitch => phase == TenantShiftPhase.closing;
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
    required TenantDocumentReader reader,
    required TenantShiftWriter writer,
    required String deviceId,
    required TenantShiftOnlineCheck isOnline,
    TenantShiftIdFactory? shiftIdFactory,
    TenantShiftClock? clock,
    CheckoutBusinessDateResolver? businessDateResolver,
  }) : _sessionController = sessionController,
       _localState = localState,
       _reader = reader,
       _writer = writer,
       _deviceId = validateCheckoutDeviceId(deviceId),
       _isOnline = isOnline,
       _shiftIdFactory = shiftIdFactory ?? _generateShiftId,
       _clock = clock ?? _utcNow,
       _businessDateResolver = businessDateResolver ?? checkoutBusinessDate;

  final TenantSessionController _sessionController;
  final HiveTenantShiftState _localState;
  final TenantDocumentReader _reader;
  final TenantShiftWriter _writer;
  final String _deviceId;
  final TenantShiftOnlineCheck _isOnline;
  final TenantShiftIdFactory _shiftIdFactory;
  final TenantShiftClock _clock;
  final CheckoutBusinessDateResolver _businessDateResolver;
  Future<void> _tail = Future<void>.value();
  TenantShiftState _state = const TenantShiftState.unknown();

  TenantShiftState get state => _state;

  /// The installation identity recorded on every shift this device opens.
  String get deviceId => _deviceId;

  /// Re-reads the canonical shift named by durable local state.
  ///
  /// The signature matches `TenantRouteGuard`, so the guard supplies the exact
  /// session it authorized.
  Future<TenantShiftState> restore(TenantSession session) =>
      _run(session, (captured) async {
        if (!await _online()) return _offlineView(captured);
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
        if (!await _online()) return _offlineView(captured);

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
        await _localState.save(
          TenantShiftLocalRecord(
            uid: captured.uid,
            tenantId: captured.tenantId,
            shiftId: intent.shiftId,
            businessDate: intent.businessDate,
            deviceId: intent.deviceId,
            serverConfirmedOpen: false,
            closeInProgress: false,
            updatedAt: _localState.now(),
          ),
        );
        final result = await _writer.openShift(intent);
        if (!_owns(captured)) return _staleView();
        return _settle(
          captured,
          errorCode: result.kind == TenantShiftWriteKind.committed
              ? null
              : result.reasonCode ?? 'shift_open_unconfirmed',
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
        if (!await _online()) {
          return _settle(captured, errorCode: 'offline');
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

    if (shift == null || !shift.isOpen) {
      // The server is authoritative: an absent or closed shift ends the local
      // record, including the counted cash that was blocking a switch.
      await _localState.clear(
        uid: captured.uid,
        tenantId: captured.tenantId,
      );
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
        phase: record.closeInProgress
            ? TenantShiftPhase.closing
            : TenantShiftPhase.open,
        shift: shift,
        countedCashMinor: record.countedCashMinor,
        errorCode: errorCode,
        otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
      ),
    );
  }

  /// The honest offline view: only local facts, never a canonical claim.
  Future<TenantShiftState> _offlineView(TenantSession captured) async {
    final record = await _localState.read(
      uid: captured.uid,
      tenantId: captured.tenantId,
    );
    return _publish(
      captured,
      TenantShiftState(
        phase: record != null && record.closeInProgress
            ? TenantShiftPhase.closing
            : TenantShiftPhase.unknown,
        countedCashMinor: record?.countedCashMinor,
        errorCode: 'offline',
        otherTenantShiftOpen: await _otherTenantShiftOpen(captured),
      ),
    );
  }

  Future<bool> _otherTenantShiftOpen(TenantSession captured) async {
    final records = await _localState.recordsForUid(captured.uid);
    return records.any(
      (record) =>
          record.tenantId != captured.tenantId &&
          (record.serverConfirmedOpen || record.closeInProgress),
    );
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
    notifyListeners();
    return next;
  }

  TenantShiftState _staleView() => const TenantShiftState(
    phase: TenantShiftPhase.unavailable,
    errorCode: 'session_changed',
  );

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

/// Enforces the frozen cashier restriction at the checkout entry point.
///
/// A cashier may not start a checkout in a second business while another
/// business still holds an open or unsettled shift on this device. Owners,
/// admins, and managers may still inspect another business.
///
/// Unreadable local state refuses the checkout rather than allowing it.
final class TenantShiftCheckoutGate implements CheckoutStartGuard {
  const TenantShiftCheckoutGate(this._state);

  final HiveTenantShiftState _state;

  @override
  Future<String?> refuseCheckoutStart(TenantSession session) async {
    if (session.role != TenantRole.cashier) return null;
    final records = await _state.recordsForUid(session.uid);
    final blocked = records.any(
      (record) =>
          record.tenantId != session.tenantId &&
          (record.serverConfirmedOpen || record.closeInProgress),
    );
    return blocked ? 'other_tenant_shift_open' : null;
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
