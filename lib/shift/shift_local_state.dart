import 'dart:async';

import 'package:hive/hive.dart';

import '../checkout/checkout_outbox.dart';
import '../checkout/checkout_receipt.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_switch.dart';

/// Raised when durable local shift state cannot be trusted.
final class TenantShiftStateException implements Exception {
  const TenantShiftStateException(this.code);

  final String code;

  @override
  String toString() => 'TenantShiftStateException($code)';
}

/// The durable local record of one session's believed shift.
///
/// It is evidence, not authority: only a canonical server read may decide that
/// a shift is open or closed. The record exists so an interrupted open or close
/// is never forgotten, and so an unfinished cash count keeps blocking a tenant
/// switch across a restart.
final class TenantShiftLocalRecord {
  const TenantShiftLocalRecord({
    required this.uid,
    required this.tenantId,
    required this.shiftId,
    required this.businessDate,
    required this.deviceId,
    required this.serverConfirmedOpen,
    required this.closeInProgress,
    required this.updatedAt,
    required this.openedAt,
    this.countedCashMinor,
  });

  final String uid;
  final String tenantId;
  final String shiftId;
  final String businessDate;
  final String deviceId;

  /// Whether a canonical read has confirmed this shift is open on the server.
  final bool serverConfirmedOpen;

  /// Whether a cash count or close attempt is unfinished on this device.
  final bool closeInProgress;

  final int? countedCashMinor;
  final DateTime updatedAt;

  /// When this shift was opened on this device.
  ///
  /// **Separate from [updatedAt], which cannot stand in for it.** `updatedAt`
  /// moves on every save - a cash count started, a count abandoned, a server
  /// confirmation arriving - so a long shift that anybody touched would keep
  /// looking new. The product rule is that a shift may not run past
  /// `TenantShiftController.maximumShiftDuration`, and that is a question about
  /// when it *started*.
  final DateTime openedAt;

  TenantShiftLocalRecord copyWith({
    bool? serverConfirmedOpen,
    bool? closeInProgress,
    int? countedCashMinor,
    bool clearCountedCash = false,
    DateTime? updatedAt,
  }) => TenantShiftLocalRecord(
    uid: uid,
    tenantId: tenantId,
    shiftId: shiftId,
    businessDate: businessDate,
    deviceId: deviceId,
    serverConfirmedOpen: serverConfirmedOpen ?? this.serverConfirmedOpen,
    closeInProgress: closeInProgress ?? this.closeInProgress,
    openedAt: openedAt,
    countedCashMinor: clearCountedCash
        ? null
        : countedCashMinor ?? this.countedCashMinor,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toStorage() => <String, Object?>{
    'schemaVersion': HiveTenantShiftState.schemaVersion,
    'uid': uid,
    'tenantId': tenantId,
    'shiftId': shiftId,
    'businessDate': businessDate,
    'deviceId': deviceId,
    'serverConfirmedOpen': serverConfirmedOpen,
    'closeInProgress': closeInProgress,
    if (countedCashMinor != null) 'countedCashMinor': countedCashMinor,
    'updatedAtMs': updatedAt.toUtc().millisecondsSinceEpoch,
    'openedAtMs': openedAt.toUtc().millisecondsSinceEpoch,
  };
}

/// The durable key of one identity's shift state in one business.
String tenantShiftStateKey({required String uid, required String tenantId}) {
  final safeUid = validateTenantDocumentId(uid, fieldName: 'uid');
  final safeTenantId = validateTenantId(tenantId);
  if (safeUid.contains(':')) {
    throw ArgumentError.value(uid, 'uid', 'Must not contain a colon.');
  }
  return '$safeUid:$safeTenantId';
}

typedef TenantShiftStateClock = DateTime Function();

/// Encrypted, versioned durable shift state for this installation.
///
/// The box shares the checkout **outbox** encryption key on purpose: a shift
/// and the sale evidence recorded during it must share one fate. A rotated or
/// lost key can never leave readable local sales beside a forgotten shift.
///
/// Malformed durable state always fails closed. Silently restarting from an
/// unreadable record could reopen a shift the server already closed, or hide an
/// unfinished cash count that must keep blocking a tenant switch.
final class HiveTenantShiftState {
  HiveTenantShiftState._(this._box, this._clock);

  static const boxName = 'tenant-shift-state-v1';

  /// The shape this writes.
  ///
  /// **Reading still accepts [legacySchemaVersion], and must.** A version
  /// mismatch raises `malformed_shift_state`, which `TenantShiftController`
  /// turns into a till that refuses to open - so a bare bump would have shut
  /// every register that happened to hold an open shift at the moment it
  /// updated. See [_parse].
  static const schemaVersion = 2;

  /// The shape before `openedAtMs` existed.
  static const legacySchemaVersion = 1;
  static const encryptionKeyBytes = HiveCheckoutOutbox.encryptionKeyBytes;

  static final Map<String, Future<void>> _operationTails =
      <String, Future<void>>{};

  final Box<dynamic> _box;
  final TenantShiftStateClock _clock;

  static Future<HiveTenantShiftState> open({
    required CheckoutOutboxEncryptionKeyProvider keyProvider,
    HiveInterface? hive,
    TenantShiftStateClock? clock,
  }) async {
    final key = await keyProvider.loadOrCreateKey();
    if (key.length != encryptionKeyBytes) {
      throw const TenantShiftStateException('invalid_encryption_key');
    }
    final box = await (hive ?? Hive).openBox<dynamic>(
      boxName,
      encryptionCipher: HiveAesCipher(List<int>.from(key)),
      crashRecovery: false,
    );
    return HiveTenantShiftState._(box, clock ?? _utcNow);
  }

  /// Test and composition boundary for an already encrypted Hive box.
  factory HiveTenantShiftState.fromBox(
    Box<dynamic> box, {
    TenantShiftStateClock? clock,
  }) => HiveTenantShiftState._(box, clock ?? _utcNow);

  DateTime now() => _clock().toUtc();

  /// Reads the durable record for one exact identity and business.
  Future<TenantShiftLocalRecord?> read({
    required String uid,
    required String tenantId,
  }) async {
    final key = tenantShiftStateKey(uid: uid, tenantId: tenantId);
    final raw = _box.get(key);
    if (raw == null) return null;
    return _parse(key, raw);
  }

  /// Replaces the durable record for one exact identity and business.
  Future<TenantShiftLocalRecord> save(TenantShiftLocalRecord record) {
    final key = tenantShiftStateKey(uid: record.uid, tenantId: record.tenantId);
    return _serialized(key, () async {
      await _box.put(key, record.toStorage());
      return record;
    });
  }

  /// Removes the durable record once the server has settled the shift.
  Future<void> clear({required String uid, required String tenantId}) {
    final key = tenantShiftStateKey(uid: uid, tenantId: tenantId);
    return _serialized(key, () => _box.delete(key));
  }

  /// Every durable record belonging to one identity, across businesses.
  ///
  /// This is how the device answers whether another business still holds an
  /// open shift for this cashier. A malformed record for the same identity is
  /// raised rather than skipped, so the restriction can never fail open.
  Future<List<TenantShiftLocalRecord>> recordsForUid(String uid) async {
    final prefix = '${validateTenantDocumentId(uid, fieldName: 'uid')}:';
    final records = <TenantShiftLocalRecord>[];
    for (final key in _box.keys) {
      if (key is! String || !key.startsWith(prefix)) continue;
      final raw = _box.get(key);
      if (raw == null) continue;
      records.add(_parse(key, raw));
    }
    return records;
  }

  Future<void> close() => _box.close();

  TenantShiftLocalRecord _parse(String key, Object? raw) {
    if (raw is! Map) {
      throw const TenantShiftStateException('malformed_shift_state');
    }
    final map = Map<Object?, Object?>.from(raw);
    final uid = map['uid'];
    final tenantId = map['tenantId'];
    final shiftId = map['shiftId'];
    final businessDate = map['businessDate'];
    final deviceId = map['deviceId'];
    final serverConfirmedOpen = map['serverConfirmedOpen'];
    final closeInProgress = map['closeInProgress'];
    final countedCashMinor = map['countedCashMinor'];
    final updatedAtMs = map['updatedAtMs'];
    final openedAtMs = map['openedAtMs'];
    final version = map['schemaVersion'];
    // **Both versions are read; only the current one is written.** A record
    // saved before `openedAtMs` existed is still a real open shift, and
    // refusing it would close a till in the middle of a trading day purely
    // because the app updated. Such a record is migrated on its next save.
    if ((version != schemaVersion && version != legacySchemaVersion) ||
        (version == schemaVersion && openedAtMs is! int) ||
        uid is! String ||
        tenantId is! String ||
        shiftId is! String ||
        businessDate is! String ||
        deviceId is! String ||
        serverConfirmedOpen is! bool ||
        closeInProgress is! bool ||
        updatedAtMs is! int ||
        (countedCashMinor != null &&
            (countedCashMinor is! int || countedCashMinor < 0))) {
      throw const TenantShiftStateException('malformed_shift_state');
    }
    try {
      if (tenantShiftStateKey(uid: uid, tenantId: tenantId) != key) {
        throw const TenantShiftStateException('malformed_shift_state');
      }
      validateTenantDocumentId(shiftId, fieldName: 'shiftId');
      validateCheckoutDeviceId(deviceId);
      validateCheckoutBusinessDate(businessDate);
    } on ArgumentError {
      throw const TenantShiftStateException('malformed_shift_state');
    }
    return TenantShiftLocalRecord(
      uid: uid,
      tenantId: tenantId,
      shiftId: shiftId,
      businessDate: businessDate,
      deviceId: deviceId,
      serverConfirmedOpen: serverConfirmedOpen,
      closeInProgress: closeInProgress,
      countedCashMinor: countedCashMinor as int?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs, isUtc: true),
      // **A legacy record dates its opening to its last touch.** That is the
      // conservative reading: `updatedAt` is never earlier than the true
      // opening, so the age this yields is never an over-estimate and the
      // 24-hour rule can only ever be lenient towards a shift already running.
      openedAt: DateTime.fromMillisecondsSinceEpoch(
        openedAtMs is int ? openedAtMs : updatedAtMs,
        isUtc: true,
      ),
    );
  }

  Future<T> _serialized<T>(String key, Future<T> Function() action) async {
    final lockKey = '${_box.name}:$key';
    final previous = _operationTails[lockKey] ?? Future<void>.value();
    final release = Completer<void>();
    _operationTails[lockKey] = release.future;
    try {
      await previous;
      return await action();
    } finally {
      release.complete();
      if (identical(_operationTails[lockKey], release.future)) {
        _operationTails.remove(lockKey);
      }
    }
  }
}

/// The real cash-close and shift owner behind the tenant-switch coordinator.
///
/// A server-confirmed open shift by itself never blocks switching, exactly as
/// the frozen baseline requires. Only an unfinished cash count or an unsettled
/// close does. Unreadable local state raises, so the coordinator fails closed
/// instead of assuming the device is clean.
final class TenantShiftSwitchStateSource implements TenantSwitchStateSource {
  const TenantShiftSwitchStateSource(this._state);

  final HiveTenantShiftState _state;

  @override
  TenantSwitchStateArea get area => TenantSwitchStateArea.cashClose;

  @override
  Future<TenantSwitchInspection?> inspect(TenantSession session) async {
    final record = await _state.read(
      uid: session.uid,
      tenantId: session.tenantId,
    );
    final hasOpenShift = record?.serverConfirmedOpen ?? false;
    if (record != null && record.closeInProgress) {
      return TenantSwitchInspection.blocked(
        area: area,
        session: session,
        blocker: TenantSwitchBlocker.unfinishedCashCountOrShiftClose,
        hasServerConfirmedOpenShift: hasOpenShift,
      );
    }
    return TenantSwitchInspection.clean(
      area: area,
      session: session,
      hasServerConfirmedOpenShift: hasOpenShift,
    );
  }
}

DateTime _utcNow() => DateTime.now().toUtc();
