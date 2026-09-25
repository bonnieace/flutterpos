import 'dart:async';

import 'package:hive/hive.dart';

import '../checkout/checkout_outbox.dart';
import '../checkout/checkout_receipt.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_switch.dart';
import 'shift_declaration.dart';

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
    this.openingFloatMinor = 0,
    this.declaration,
    this.closedAt,
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

  /// When this device closed the shift, while the server has not confirmed it.
  ///
  /// **The close's own `serverConfirmedOpen`.** It is what lets a shift be
  /// counted and closed with no network: the figures are fixed here, the till
  /// stops selling against the shift, and `TenantShiftController` replays the
  /// write on the next restore. Cleared by the record being cleared, which is
  /// what a confirmed close does.
  ///
  /// **It is the close's `closedAt`, and still not its `endTime`.** The
  /// server stamps `endTime` when the write lands, and reconciliation is built
  /// on that one. Since 2026-09-25 this instant is sent beside it, because a
  /// shift closed offline on Friday and synced on Monday ended on Friday - and
  /// every screen said Monday.
  final DateTime? closedAt;

  /// The change this drawer started with, in minor units.
  ///
  /// **Durable because the replay needs it.** A shift opened with no network
  /// is sent later by `TenantShiftController._replayUnsentOpen`, which rebuilds
  /// the intent from this record - so a float held only in the dialog that
  /// collected it would be silently dropped by exactly the shifts most likely
  /// to need it. Zero for every record written before the field existed, which
  /// is the same answer those shifts already gave.
  final int openingFloatMinor;

  /// The cash figure a close recorded before the tender declaration existed.
  ///
  /// **Read-only legacy, and never turned into a [declaration].** A record left
  /// by an earlier build holds one number; reading it as
  /// `{cash: n, mpesa: 0, card: 0}` would invent two zeros the cashier never
  /// typed and `TenantShiftController._replayUnsentClose` would then write them
  /// to the server as a declaration. The replay sends the legacy shape instead.

  /// What the cashier declared the till held, by payment method.
  ///
  /// Durable for the same reason the cash figure was: a close recorded with no
  /// network is replayed from this record, and the figures it carries are the
  /// ones that were counted rather than ones recomputed later.
  final ShiftTenderDeclaration? declaration;

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
    ShiftTenderDeclaration? declaration,
    bool clearDeclaration = false,
    DateTime? closedAt,
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
    // Fixed at open, like the shift document's own copy: no later edit to this
    // record may change what the drawer is said to have started with.
    openingFloatMinor: openingFloatMinor,
    declaration: clearDeclaration ? null : declaration ?? this.declaration,
    // Never cleared through `copyWith`: a close this device has recorded is
    // undone only by the record itself going, which is what a confirmed close
    // does. There is no *un-close*.
    closedAt: closedAt ?? this.closedAt,
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
    if (openingFloatMinor > 0) 'openingFloatMinor': openingFloatMinor,
    if (declaration case final declared?) ...<String, Object?>{
      'declaredCashMinor': declared.cashMinor,
      'declaredMpesaMinor': declared.mpesaMinor,
      'declaredCardMinor': declared.cardMinor,
    },
    if (closedAt != null)
      'closedAtMs': closedAt!.toUtc().millisecondsSinceEpoch,
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
  /// **One shape, read and written (#107).** Versions 1 and 2 were accepted so
  /// that a bump could not shut a register holding an open shift at the moment
  /// it updated - a mismatch raises `malformed_shift_state`, which
  /// `TenantShiftController` turns into a till that refuses to open. SIT clears
  /// local shift state instead of carrying it forward, so there is no earlier
  /// record to strand.
  static const schemaVersion = 3;

  /// Every shape [_parse] accepts.
  static const readableSchemaVersions = <int>{schemaVersion};
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

  /// Whether this device holds no believed shift for anybody.
  ///
  /// **Asked by the device identity, before it rebinds itself.** Rebinding
  /// changes the ID a sale carries, and the server requires a sale's ID to match
  /// the shift's - so it is safe only while there is no shift to disagree with.
  /// Keys are counted rather than parsed: a record too malformed to read is
  /// still a record, and it must still say no.
  Future<bool> get isEmpty async =>
      !_box.keys.any((key) => key is String && key.contains(':'));

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
    final openingFloatMinor = map['openingFloatMinor'];
    final updatedAtMs = map['updatedAtMs'];
    final openedAtMs = map['openedAtMs'];
    final closedAtMs = map['closedAtMs'];
    final version = map['schemaVersion'];
    if (!readableSchemaVersions.contains(version) ||
        openedAtMs is! int ||
        uid is! String ||
        tenantId is! String ||
        shiftId is! String ||
        businessDate is! String ||
        deviceId is! String ||
        serverConfirmedOpen is! bool ||
        closeInProgress is! bool ||
        updatedAtMs is! int ||
        (openingFloatMinor != null &&
            (openingFloatMinor is! int ||
                openingFloatMinor < 0 ||
                openingFloatMinor > maximumShiftCashMinor)) ||
        (closedAtMs != null && closedAtMs is! int)) {
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
      declaration: _parseDeclaration(map),
      uid: uid,
      tenantId: tenantId,
      shiftId: shiftId,
      businessDate: businessDate,
      deviceId: deviceId,
      serverConfirmedOpen: serverConfirmedOpen,
      closeInProgress: closeInProgress,
      // Absent reads as no float, which is what `toStorage` writes for a
      // drawer opened with nothing in it.
      openingFloatMinor: (openingFloatMinor as int?) ?? 0,
      // Absent on every record written before an offline close was possible,
      // which reads correctly as "this shift was not closed here".
      closedAt: closedAtMs is int
          ? DateTime.fromMillisecondsSinceEpoch(closedAtMs, isUtc: true)
          : null,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs, isUtc: true),
      openedAt: DateTime.fromMillisecondsSinceEpoch(openedAtMs, isUtc: true),
    );
  }

  /// Reads the declared tender triple, which is stored all together or not.
  ///
  /// A partial triple is `malformed_shift_state` rather than a declaration with
  /// zeros in it. This record is what an unsent close is replayed from, so a
  /// figure invented here would be written to the server as one the cashier
  /// declared.
  static ShiftTenderDeclaration? _parseDeclaration(Map<Object?, Object?> map) {
    const fields = <String>[
      'declaredCashMinor',
      'declaredMpesaMinor',
      'declaredCardMinor',
    ];
    final values = fields.map((field) => map[field]).toList(growable: false);
    if (values.every((value) => value == null)) return null;
    if (values.any((value) => value is! int)) {
      throw const TenantShiftStateException('malformed_shift_state');
    }
    final declaration = ShiftTenderDeclaration.tryParse(
      cash: values[0]! as int,
      mpesa: values[1]! as int,
      card: values[2]! as int,
    );
    if (declaration == null) {
      throw const TenantShiftStateException('malformed_shift_state');
    }
    return declaration;
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
