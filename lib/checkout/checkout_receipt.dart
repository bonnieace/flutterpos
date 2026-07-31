import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../tenancy/tenant_id.dart';
import 'checkout_outbox.dart';

/// Frozen receipt prefix; every receipt reads `CT-A7F-20260729-0042`.
const String checkoutReceiptPrefix = 'CT';

/// Hexadecimal characters of the device code embedded in a receipt.
const int checkoutReceiptDeviceCodeLength = 3;

/// Minimum zero-padded width of the per-device daily sequence.
const int checkoutReceiptSequenceDigits = 4;

/// The largest sequence one device may issue for one business date.
///
/// The frozen shape pads to four digits; a busier device widens the field
/// rather than wrapping, because a wrapped counter would repeat a receipt.
const int maximumCheckoutReceiptSequence = 999999;

/// The exact frozen receipt shape, also enforced by Firestore Rules.
final RegExp checkoutReceiptNumberPattern = RegExp(
  r'^CT-[0-9A-F]{3}-\d{8}-\d{4,6}$',
);

final RegExp _businessDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _deviceIdPattern = RegExp(r'^dev-[0-9a-f]{32}$');

/// Raised when durable receipt state cannot be trusted for a new checkout.
final class CheckoutReceiptException implements Exception {
  const CheckoutReceiptException(this.code);

  final String code;

  @override
  String toString() => 'CheckoutReceiptException($code)';
}

/// Validates a `yyyy-MM-dd` business date and returns it unchanged.
String validateCheckoutBusinessDate(String value) {
  final match = _businessDatePattern.firstMatch(value);
  if (match == null) {
    throw ArgumentError.value(value, 'businessDate', 'Expected yyyy-MM-dd.');
  }
  final date = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  if (date.toIso8601String().substring(0, 10) != value) {
    throw ArgumentError.value(value, 'businessDate', 'Not a calendar date.');
  }
  return value;
}

/// Derives the stable three-character device code printed on a receipt.
///
/// The code is a deterministic digest of the durable installation identifier,
/// so it never exposes the identifier itself and never changes for a device.
String checkoutReceiptDeviceCode(String deviceId) {
  final digest = sha256.convert(utf8.encode(validateCheckoutDeviceId(deviceId)));
  return digest
      .toString()
      .substring(0, checkoutReceiptDeviceCodeLength)
      .toUpperCase();
}

/// Formats the frozen receipt for one device, business date, and sequence.
String formatCheckoutReceiptNumber({
  required String deviceId,
  required String businessDate,
  required int sequence,
}) {
  if (sequence < 1 || sequence > maximumCheckoutReceiptSequence) {
    throw ArgumentError.value(sequence, 'sequence');
  }
  final compactDate = validateCheckoutBusinessDate(
    businessDate,
  ).replaceAll('-', '');
  final padded = sequence.toString().padLeft(checkoutReceiptSequenceDigits, '0');
  return '$checkoutReceiptPrefix-${checkoutReceiptDeviceCode(deviceId)}'
      '-$compactDate-$padded';
}

/// The frozen device counter key.
///
/// It is deliberately not scoped by cashier UID: two cashiers sharing one
/// device must draw from the same sequence so they can never collide.
String checkoutReceiptCounterKey({
  required String tenantId,
  required String deviceId,
  required String businessDate,
}) {
  final safeTenantId = validateTenantId(tenantId);
  final safeDeviceId = validateCheckoutDeviceId(deviceId);
  final safeDate = validateCheckoutBusinessDate(businessDate);
  if (safeTenantId.contains(':')) {
    throw ArgumentError.value(tenantId, 'tenantId', 'Must not contain a colon.');
  }
  return '$safeTenantId:$safeDeviceId:$safeDate:receiptCounter';
}

/// Validates the durable installation identifier used by receipt numbering.
String validateCheckoutDeviceId(String deviceId) {
  if (!_deviceIdPattern.hasMatch(deviceId)) {
    throw ArgumentError.value(deviceId, 'deviceId', 'Invalid device ID.');
  }
  return validateTenantDocumentId(deviceId, fieldName: 'deviceId');
}

typedef CheckoutReceiptClock = DateTime Function();

/// Durable per-device receipt sequences and the installation identity.
///
/// The box shares the checkout outbox encryption key on purpose: a counter and
/// the sale evidence it numbers must share exactly one fate, so a key rotation
/// can never leave readable local sales beside a restarted counter.
///
/// Malformed durable state always fails closed. Restarting a counter would
/// reissue a receipt number that a committed sale already carries, which is
/// strictly worse than refusing the checkout.
final class HiveCheckoutReceiptCounters {
  HiveCheckoutReceiptCounters._(this._box, this._clock, this._random);

  static const boxName = 'checkout-receipt-counters-v1';
  static const schemaVersion = 1;
  static const encryptionKeyBytes = HiveCheckoutOutbox.encryptionKeyBytes;

  /// Reserved key of the installation identity.
  ///
  /// Counter keys always contain colons, so this name can never collide.
  static const deviceIdentityKey = 'device-identity';

  static final Map<String, Future<void>> _operationTails =
      <String, Future<void>>{};

  final Box<dynamic> _box;
  final CheckoutReceiptClock _clock;
  final Random _random;
  Future<String>? _deviceId;

  static Future<HiveCheckoutReceiptCounters> open({
    required CheckoutOutboxEncryptionKeyProvider keyProvider,
    HiveInterface? hive,
    CheckoutReceiptClock? clock,
    Random? random,
  }) async {
    final key = await keyProvider.loadOrCreateKey();
    if (key.length != encryptionKeyBytes) {
      throw const CheckoutReceiptException('invalid_encryption_key');
    }
    final box = await (hive ?? Hive).openBox<dynamic>(
      boxName,
      encryptionCipher: HiveAesCipher(List<int>.from(key)),
      crashRecovery: false,
    );
    return HiveCheckoutReceiptCounters._(
      box,
      clock ?? _utcNow,
      random ?? Random.secure(),
    );
  }

  /// Test and composition boundary for an already encrypted Hive box.
  factory HiveCheckoutReceiptCounters.fromBox(
    Box<dynamic> box, {
    CheckoutReceiptClock? clock,
    Random? random,
  }) => HiveCheckoutReceiptCounters._(
    box,
    clock ?? _utcNow,
    random ?? Random.secure(),
  );

  /// Resolves the installation identifier, creating it exactly once.
  ///
  /// The value is memoized per process and persisted durably, so the device
  /// code printed on a receipt is stable across restarts and tenants.
  Future<String> resolveDeviceId() async {
    // A failed resolution is not memoized, so a corrupt record can be fixed by
    // reinstalling without leaving a permanently poisoned in-memory future.
    final pending = _deviceId ??= _resolveDeviceId();
    try {
      return await pending;
    } catch (_) {
      if (identical(_deviceId, pending)) _deviceId = null;
      rethrow;
    }
  }

  Future<String> _resolveDeviceId() {
    return _serialized(deviceIdentityKey, () async {
      final raw = _box.get(deviceIdentityKey);
      if (raw != null) {
        if (raw is! Map) {
          throw const CheckoutReceiptException('malformed_device_identity');
        }
        final map = Map<Object?, Object?>.from(raw);
        final stored = map['deviceId'];
        if (map['schemaVersion'] != schemaVersion || stored is! String) {
          throw const CheckoutReceiptException('malformed_device_identity');
        }
        try {
          return validateCheckoutDeviceId(stored);
        } on ArgumentError {
          throw const CheckoutReceiptException('malformed_device_identity');
        }
      }
      final suffix = List<String>.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final deviceId = 'dev-$suffix';
      await _box.put(deviceIdentityKey, <String, Object?>{
        'schemaVersion': schemaVersion,
        'deviceId': validateCheckoutDeviceId(deviceId),
        'createdAtMs': _clock().toUtc().millisecondsSinceEpoch,
      });
      return deviceId;
    });
  }

  /// Atomically allocates the next sequence for one device and business date.
  ///
  /// The value is persisted before it is returned, so an interrupted checkout
  /// leaves an unused gap rather than a duplicate receipt.
  Future<int> allocateSequence({
    required String tenantId,
    required String deviceId,
    required String businessDate,
  }) {
    final key = checkoutReceiptCounterKey(
      tenantId: tenantId,
      deviceId: deviceId,
      businessDate: businessDate,
    );
    return _serialized(key, () async {
      final current = _readSequence(key, tenantId, deviceId, businessDate);
      if (current >= maximumCheckoutReceiptSequence) {
        throw const CheckoutReceiptException('receipt_sequence_exhausted');
      }
      final next = current + 1;
      await _box.put(key, <String, Object?>{
        'schemaVersion': schemaVersion,
        'tenantId': tenantId,
        'deviceId': deviceId,
        'businessDate': businessDate,
        'sequence': next,
        'updatedAtMs': _clock().toUtc().millisecondsSinceEpoch,
      });
      return next;
    });
  }

  /// Returns the last allocated sequence without consuming a new one.
  Future<int> lastSequence({
    required String tenantId,
    required String deviceId,
    required String businessDate,
  }) async {
    final key = checkoutReceiptCounterKey(
      tenantId: tenantId,
      deviceId: deviceId,
      businessDate: businessDate,
    );
    return _readSequence(key, tenantId, deviceId, businessDate);
  }

  Future<void> close() => _box.close();

  int _readSequence(
    String key,
    String tenantId,
    String deviceId,
    String businessDate,
  ) {
    final raw = _box.get(key);
    if (raw == null) return 0;
    if (raw is! Map) {
      throw const CheckoutReceiptException('malformed_receipt_counter');
    }
    final map = Map<Object?, Object?>.from(raw);
    final sequence = map['sequence'];
    if (map['schemaVersion'] != schemaVersion ||
        map['tenantId'] != tenantId ||
        map['deviceId'] != deviceId ||
        map['businessDate'] != businessDate ||
        sequence is! int ||
        sequence < 1 ||
        sequence > maximumCheckoutReceiptSequence) {
      throw const CheckoutReceiptException('malformed_receipt_counter');
    }
    return sequence;
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

DateTime _utcNow() => DateTime.now().toUtc();
