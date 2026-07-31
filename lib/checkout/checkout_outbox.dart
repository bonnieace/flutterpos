import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_switch.dart';

enum CheckoutOutboxState {
  savedOffline,
  submitting,
  awaitingConfirmation,
  confirmed,
  needsAttention,
}

final class CheckoutOutboxException implements Exception {
  const CheckoutOutboxException(this.code);

  final String code;

  @override
  String toString() => 'CheckoutOutboxException($code)';
}

/// Evidence produced only after local writes have cleared and an exact server
/// sale lookup has proved the deterministic checkout document is absent.
final class CheckoutMissingSaleProof {
  CheckoutMissingSaleProof.confirmed({
    required String uid,
    required String tenantId,
    required String checkoutId,
    required String expectedPayloadHash,
    required DateTime checkedAt,
  }) : uid = _validateKeySegment(uid, 'uid'),
       tenantId = _validateOutboxTenantId(tenantId),
       checkoutId = validateTenantDocumentId(
         checkoutId,
         fieldName: 'checkoutId',
       ),
       expectedPayloadHash = _validateHash(
         expectedPayloadHash,
         'expectedPayloadHash',
       ),
       checkedAt = checkedAt.toUtc();

  final String uid;
  final String tenantId;
  final String checkoutId;
  final String expectedPayloadHash;
  final DateTime checkedAt;

  bool get localPendingWritesCleared => true;
  bool get serverSaleAbsent => true;
}

abstract interface class CheckoutOutboxEncryptionKeyProvider {
  Future<List<int>> loadOrCreateKey();
}

typedef CheckoutOutboxClock = DateTime Function();

final class CheckoutOutboxRecord {
  CheckoutOutboxRecord._({
    required this.uid,
    required this.tenantId,
    required this.checkoutId,
    required this.state,
    required Map<String, Object?> payload,
    required this.payloadHash,
    required this.attemptCount,
    required this.retryAt,
    required this.leaseOwner,
    required this.leaseExpiresAt,
    required this.createdAt,
    required this.updatedAt,
    required this.observedPayloadHash,
    required this.attentionReason,
  }) : payload = _freezeMap(payload);

  static const schemaVersion = 1;

  final String uid;
  final String tenantId;
  final String checkoutId;
  final CheckoutOutboxState state;
  final Map<String, Object?> payload;
  final String payloadHash;
  final int attemptCount;
  final DateTime? retryAt;
  final String? leaseOwner;
  final DateTime? leaseExpiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? observedPayloadHash;
  final String? attentionReason;

  String get storageKey => checkoutOutboxStorageKey(
    uid: uid,
    tenantId: tenantId,
    checkoutId: checkoutId,
  );

  Map<String, Object?> toStorage() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'uid': uid,
    'tenantId': tenantId,
    'checkoutId': checkoutId,
    'state': _stateName(state),
    'payload': _mutableJson(payload),
    'payloadHash': payloadHash,
    'attemptCount': attemptCount,
    'retryAtMs': retryAt?.millisecondsSinceEpoch,
    'leaseOwner': leaseOwner,
    'leaseExpiresAtMs': leaseExpiresAt?.millisecondsSinceEpoch,
    'createdAtMs': createdAt.millisecondsSinceEpoch,
    'updatedAtMs': updatedAt.millisecondsSinceEpoch,
    'observedPayloadHash': observedPayloadHash,
    'attentionReason': attentionReason,
  };

  CheckoutOutboxRecord copyWith({
    required CheckoutOutboxState state,
    required int attemptCount,
    required DateTime updatedAt,
    DateTime? retryAt,
    String? leaseOwner,
    DateTime? leaseExpiresAt,
    String? observedPayloadHash,
    String? attentionReason,
  }) => CheckoutOutboxRecord._(
    uid: uid,
    tenantId: tenantId,
    checkoutId: checkoutId,
    state: state,
    payload: payload,
    payloadHash: payloadHash,
    attemptCount: attemptCount,
    retryAt: retryAt,
    leaseOwner: leaseOwner,
    leaseExpiresAt: leaseExpiresAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
    observedPayloadHash: observedPayloadHash,
    attentionReason: attentionReason,
  );
}

String checkoutOutboxStorageKey({
  required String uid,
  required String tenantId,
  required String checkoutId,
}) {
  final safeUid = _validateKeySegment(uid, 'uid');
  final safeTenantId = _validateOutboxTenantId(tenantId);
  final safeCheckoutId = validateTenantDocumentId(
    checkoutId,
    fieldName: 'checkoutId',
  );
  if (safeCheckoutId.contains(':')) {
    throw ArgumentError('Outbox key segments must not contain a colon.');
  }
  return '$safeUid:$safeTenantId:$safeCheckoutId';
}

String checkoutPayloadHash(Map<String, Object?> payload) {
  final canonical = _canonicalJson(payload);
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

/// Versioned encrypted persistence for checkout evidence only.
///
/// This box deliberately has a unique name and never opens legacy root POS
/// boxes. Every mutation is serialized per checkout within this isolate.
final class HiveCheckoutOutbox {
  HiveCheckoutOutbox._(this._box, this._clock);

  static const boxName = 'checkout-outbox-v1';
  static const encryptionKeyBytes = 32;
  static final Map<String, Future<void>> _operationTails =
      <String, Future<void>>{};

  final Box<dynamic> _box;
  final CheckoutOutboxClock _clock;

  static Future<HiveCheckoutOutbox> open({
    required CheckoutOutboxEncryptionKeyProvider keyProvider,
    HiveInterface? hive,
    CheckoutOutboxClock? clock,
  }) async {
    final key = await keyProvider.loadOrCreateKey();
    if (key.length != encryptionKeyBytes) {
      throw const CheckoutOutboxException('invalid_encryption_key');
    }
    final box = await (hive ?? Hive).openBox<dynamic>(
      boxName,
      encryptionCipher: HiveAesCipher(List<int>.from(key)),
      crashRecovery: false,
    );
    return HiveCheckoutOutbox._(box, clock ?? _utcNow);
  }

  /// Test and composition boundary for an already encrypted Hive box.
  factory HiveCheckoutOutbox.fromBox(
    Box<dynamic> box, {
    CheckoutOutboxClock? clock,
  }) => HiveCheckoutOutbox._(box, clock ?? _utcNow);

  Future<CheckoutOutboxRecord> saveOffline({
    required String uid,
    required String tenantId,
    required String checkoutId,
    required Map<String, Object?> payload,
    DateTime? retryAt,
  }) async {
    final key = checkoutOutboxStorageKey(
      uid: uid,
      tenantId: tenantId,
      checkoutId: checkoutId,
    );
    final frozenPayload = _freezeMap(payload);
    final hash = checkoutPayloadHash(frozenPayload);
    return _serialized(key, () async {
      final existing = _box.get(key);
      if (existing != null) {
        final record = _parseRecord(key, existing);
        if (record.state == CheckoutOutboxState.savedOffline &&
            record.payloadHash == hash) {
          return record;
        }
        throw const CheckoutOutboxException('checkout_already_exists');
      }
      final now = _clock().toUtc();
      final normalizedRetryAt = retryAt?.toUtc();
      final record = CheckoutOutboxRecord._(
        uid: uid,
        tenantId: tenantId,
        checkoutId: checkoutId,
        state: CheckoutOutboxState.savedOffline,
        payload: frozenPayload,
        payloadHash: hash,
        attemptCount: 0,
        retryAt: normalizedRetryAt,
        leaseOwner: null,
        leaseExpiresAt: null,
        createdAt: now,
        updatedAt: now,
        observedPayloadHash: null,
        attentionReason: null,
      );
      await _box.put(key, record.toStorage());
      return record;
    });
  }

  Future<CheckoutOutboxRecord?> read({
    required String uid,
    required String tenantId,
    required String checkoutId,
  }) async {
    final key = checkoutOutboxStorageKey(
      uid: uid,
      tenantId: tenantId,
      checkoutId: checkoutId,
    );
    final raw = _box.get(key);
    return raw == null ? null : _parseRecord(key, raw);
  }

  Future<CheckoutOutboxRecord> beginSubmission({
    required String uid,
    required String tenantId,
    required String checkoutId,
    required String leaseOwner,
    required Duration leaseDuration,
  }) {
    final owner = _validateKeySegment(leaseOwner, 'leaseOwner');
    if (leaseDuration <= Duration.zero ||
        leaseDuration > const Duration(hours: 1)) {
      throw ArgumentError.value(leaseDuration, 'leaseDuration');
    }
    return _mutate(uid, tenantId, checkoutId, (record, now) {
      if (record.state != CheckoutOutboxState.savedOffline) {
        throw const CheckoutOutboxException('invalid_transition');
      }
      if (record.retryAt != null && record.retryAt!.isAfter(now)) {
        throw const CheckoutOutboxException('retry_not_due');
      }
      return record.copyWith(
        state: CheckoutOutboxState.submitting,
        attemptCount: record.attemptCount + 1,
        updatedAt: now,
        retryAt: record.retryAt,
        leaseOwner: owner,
        leaseExpiresAt: now.add(leaseDuration),
      );
    });
  }

  Future<CheckoutOutboxRecord> markAwaitingConfirmation({
    required String uid,
    required String tenantId,
    required String checkoutId,
    required String leaseOwner,
  }) {
    final owner = _validateKeySegment(leaseOwner, 'leaseOwner');
    return _mutate(uid, tenantId, checkoutId, (record, now) {
      if (record.state != CheckoutOutboxState.submitting) {
        throw const CheckoutOutboxException('invalid_transition');
      }
      if (record.leaseOwner != owner) {
        throw const CheckoutOutboxException('lease_not_owned');
      }
      if (!record.leaseExpiresAt!.isAfter(now)) {
        throw const CheckoutOutboxException('lease_expired');
      }
      return record.copyWith(
        state: CheckoutOutboxState.awaitingConfirmation,
        attemptCount: record.attemptCount,
        updatedAt: now,
        retryAt: record.retryAt,
      );
    });
  }

  /// Converts an uncertain expired submission into confirmation-only work.
  /// It never returns the checkout to [CheckoutOutboxState.savedOffline].
  Future<CheckoutOutboxRecord> recoverExpiredSubmission({
    required String uid,
    required String tenantId,
    required String checkoutId,
  }) => _mutate(uid, tenantId, checkoutId, (record, now) {
    if (record.state != CheckoutOutboxState.submitting) {
      throw const CheckoutOutboxException('invalid_transition');
    }
    if (record.leaseExpiresAt!.isAfter(now)) {
      throw const CheckoutOutboxException('lease_still_active');
    }
    return record.copyWith(
      state: CheckoutOutboxState.awaitingConfirmation,
      attemptCount: record.attemptCount,
      updatedAt: now,
      retryAt: record.retryAt,
    );
  });

  /// Records a server-side confirmation check without changing the payload.
  /// A mismatching hash is retained as needs-attention evidence.
  Future<CheckoutOutboxRecord> recordConfirmation({
    required String uid,
    required String tenantId,
    required String checkoutId,
    required String observedPayloadHash,
  }) {
    final observed = _validateHash(observedPayloadHash, 'observedPayloadHash');
    return _mutate(uid, tenantId, checkoutId, (record, now) {
      if (record.state != CheckoutOutboxState.awaitingConfirmation) {
        throw const CheckoutOutboxException('invalid_transition');
      }
      final matches = observed == record.payloadHash;
      return record.copyWith(
        state: matches
            ? CheckoutOutboxState.confirmed
            : CheckoutOutboxState.needsAttention,
        attemptCount: record.attemptCount,
        updatedAt: now,
        retryAt: record.retryAt,
        observedPayloadHash: matches ? null : observed,
        attentionReason: matches ? null : 'payload_hash_mismatch',
      );
    });
  }

  /// Makes a confirmation-proven missing sale eligible for a later submit.
  ///
  /// An expired lease is deliberately insufficient: callers must supply
  /// evidence tied to this immutable checkout payload after pending writes
  /// cleared and the exact server document was found missing.
  Future<CheckoutOutboxRecord> markRetryableAfterMissingSale({
    required CheckoutMissingSaleProof proof,
    required Duration backoff,
  }) {
    if (backoff <= Duration.zero || backoff > const Duration(hours: 24)) {
      throw ArgumentError.value(backoff, 'backoff');
    }
    return _mutate(proof.uid, proof.tenantId, proof.checkoutId, (record, now) {
      if (record.state != CheckoutOutboxState.awaitingConfirmation) {
        throw const CheckoutOutboxException('invalid_transition');
      }
      if (proof.expectedPayloadHash != record.payloadHash ||
          proof.checkedAt.isBefore(record.updatedAt) ||
          proof.checkedAt.isAfter(now)) {
        throw const CheckoutOutboxException('invalid_missing_sale_proof');
      }
      return record.copyWith(
        state: CheckoutOutboxState.savedOffline,
        attemptCount: record.attemptCount,
        updatedAt: now,
        retryAt: now.add(backoff),
      );
    });
  }

  Future<List<CheckoutOutboxRecord>> recordsForSession({
    required String uid,
    required String tenantId,
  }) async {
    final prefix =
        '${_validateKeySegment(uid, 'uid')}:'
        '${_validateOutboxTenantId(tenantId)}:';
    final records = <CheckoutOutboxRecord>[];
    for (final dynamic rawKey in _box.keys) {
      if (rawKey is! String || !rawKey.startsWith(prefix)) continue;
      records.add(_parseRecord(rawKey, _box.get(rawKey)));
    }
    records.sort((a, b) => a.checkoutId.compareTo(b.checkoutId));
    return List<CheckoutOutboxRecord>.unmodifiable(records);
  }

  Future<void> close() => _box.close();

  Future<CheckoutOutboxRecord> _mutate(
    String uid,
    String tenantId,
    String checkoutId,
    CheckoutOutboxRecord Function(CheckoutOutboxRecord, DateTime) change,
  ) {
    final key = checkoutOutboxStorageKey(
      uid: uid,
      tenantId: tenantId,
      checkoutId: checkoutId,
    );
    return _serialized(key, () async {
      final raw = _box.get(key);
      if (raw == null) {
        throw const CheckoutOutboxException('checkout_not_found');
      }
      final updated = change(_parseRecord(key, raw), _clock().toUtc());
      await _box.put(key, updated.toStorage());
      return updated;
    });
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

final class CheckoutOutboxTenantSwitchStateSource
    implements TenantSwitchStateSource {
  const CheckoutOutboxTenantSwitchStateSource(this._outbox);

  final HiveCheckoutOutbox _outbox;

  @override
  TenantSwitchStateArea get area => TenantSwitchStateArea.checkout;

  @override
  Future<TenantSwitchInspection?> inspect(TenantSession session) async {
    final records = await _outbox.recordsForSession(
      uid: session.uid,
      tenantId: session.tenantId,
    );
    if (records.any(
      (record) => record.state == CheckoutOutboxState.submitting,
    )) {
      return TenantSwitchInspection.blocked(
        area: area,
        session: session,
        blocker: TenantSwitchBlocker.submissionInFlight,
      );
    }
    if (records.any(
      (record) => record.state != CheckoutOutboxState.confirmed,
    )) {
      return TenantSwitchInspection.blocked(
        area: area,
        session: session,
        blocker: TenantSwitchBlocker.unsynchronizedCheckout,
      );
    }
    return TenantSwitchInspection.clean(area: area, session: session);
  }
}

CheckoutOutboxRecord _parseRecord(String key, Object? raw) {
  try {
    if (raw is! Map) throw const FormatException();
    final map = Map<Object?, Object?>.from(raw);
    if (map['schemaVersion'] != CheckoutOutboxRecord.schemaVersion) {
      throw const FormatException();
    }
    final uid = _requiredString(map, 'uid');
    final tenantId = _requiredString(map, 'tenantId');
    final checkoutId = _requiredString(map, 'checkoutId');
    if (checkoutOutboxStorageKey(
          uid: uid,
          tenantId: tenantId,
          checkoutId: checkoutId,
        ) !=
        key) {
      throw const FormatException();
    }
    final payload = _requiredPayload(map['payload']);
    final payloadHash = _validateHash(
      _requiredString(map, 'payloadHash'),
      'payloadHash',
    );
    if (checkoutPayloadHash(payload) != payloadHash) {
      throw const FormatException();
    }
    final state = _parseState(_requiredString(map, 'state'));
    final attemptCount = map['attemptCount'];
    if (attemptCount is! int || attemptCount < 0) {
      throw const FormatException();
    }
    final retryAt = _optionalDate(map, 'retryAtMs');
    final leaseOwner = _optionalString(map, 'leaseOwner');
    final leaseExpiresAt = _optionalDate(map, 'leaseExpiresAtMs');
    final createdAt = _requiredDate(map, 'createdAtMs');
    final updatedAt = _requiredDate(map, 'updatedAtMs');
    final observedHash = _optionalString(map, 'observedPayloadHash');
    final attentionReason = _optionalString(map, 'attentionReason');
    if (updatedAt.isBefore(createdAt)) throw const FormatException();

    if (state == CheckoutOutboxState.submitting) {
      if (attemptCount < 1 || leaseOwner == null || leaseExpiresAt == null) {
        throw const FormatException();
      }
      _validateKeySegment(leaseOwner, 'leaseOwner');
    } else if (leaseOwner != null || leaseExpiresAt != null) {
      throw const FormatException();
    }
    if (state != CheckoutOutboxState.savedOffline && attemptCount < 1) {
      throw const FormatException();
    }
    if (state == CheckoutOutboxState.savedOffline &&
        attemptCount > 0 &&
        retryAt == null) {
      throw const FormatException();
    }
    if (state == CheckoutOutboxState.needsAttention) {
      if (attentionReason != 'payload_hash_mismatch' ||
          observedHash == null ||
          _validateHash(observedHash, 'observedPayloadHash') == payloadHash) {
        throw const FormatException();
      }
    } else if (observedHash != null || attentionReason != null) {
      throw const FormatException();
    }
    return CheckoutOutboxRecord._(
      uid: uid,
      tenantId: tenantId,
      checkoutId: checkoutId,
      state: state,
      payload: payload,
      payloadHash: payloadHash,
      attemptCount: attemptCount,
      retryAt: retryAt,
      leaseOwner: leaseOwner,
      leaseExpiresAt: leaseExpiresAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      observedPayloadHash: observedHash,
      attentionReason: attentionReason,
    );
  } catch (_) {
    throw const CheckoutOutboxException('malformed_record');
  }
}

CheckoutOutboxState _parseState(String value) => switch (value) {
  'saved_offline' => CheckoutOutboxState.savedOffline,
  'submitting' => CheckoutOutboxState.submitting,
  'awaiting_confirmation' => CheckoutOutboxState.awaitingConfirmation,
  'confirmed' => CheckoutOutboxState.confirmed,
  'needs_attention' => CheckoutOutboxState.needsAttention,
  _ => throw const FormatException(),
};

String _stateName(CheckoutOutboxState value) => switch (value) {
  CheckoutOutboxState.savedOffline => 'saved_offline',
  CheckoutOutboxState.submitting => 'submitting',
  CheckoutOutboxState.awaitingConfirmation => 'awaiting_confirmation',
  CheckoutOutboxState.confirmed => 'confirmed',
  CheckoutOutboxState.needsAttention => 'needs_attention',
};

String _requiredString(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) throw const FormatException();
  return value;
}

String? _optionalString(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) throw const FormatException();
  return value;
}

DateTime _requiredDate(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! int || value < 0) throw const FormatException();
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}

DateTime? _optionalDate(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! int || value < 0) throw const FormatException();
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}

Map<String, Object?> _requiredPayload(Object? raw) {
  if (raw is! Map) throw const FormatException();
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) throw const FormatException();
    result[entry.key as String] = _canonicalJson(entry.value);
  }
  return _freezeMap(result);
}

Object? _canonicalJson(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) throw const FormatException();
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_canonicalJson));
  }
  if (value is Map) {
    final keys = <String>[];
    for (final key in value.keys) {
      if (key is! String) throw const FormatException();
      keys.add(key);
    }
    keys.sort();
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    });
  }
  throw const FormatException();
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) =>
    Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in value.entries) entry.key: _canonicalJson(entry.value),
    });

Object? _mutableJson(Object? value) {
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key: _mutableJson(entry.value),
    };
  }
  if (value is List) return value.map(_mutableJson).toList();
  return value;
}

String _validateKeySegment(String value, String fieldName) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.contains(':') ||
      value.length > 256) {
    throw ArgumentError.value(value, fieldName, 'Invalid outbox key segment.');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw ArgumentError.value(value, fieldName, 'Invalid control character.');
    }
  }
  return value;
}

String _validateOutboxTenantId(String value) {
  final tenantId = validateTenantId(value);
  if (tenantId.contains(':')) {
    throw ArgumentError.value(
      value,
      'tenantId',
      'Outbox key segments must not contain a colon.',
    );
  }
  return tenantId;
}

String _validateHash(String value, String fieldName) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw ArgumentError.value(value, fieldName, 'Expected a SHA-256 hash.');
  }
  return value;
}

DateTime _utcNow() => DateTime.now().toUtc();
