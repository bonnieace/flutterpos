import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveCheckoutOutbox outbox;
  late _Clock clock;
  final key = List<int>.generate(
    HiveCheckoutOutbox.encryptionKeyBytes,
    (index) => index,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('checkout-outbox-test-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>(
      HiveCheckoutOutbox.boxName,
      encryptionCipher: HiveAesCipher(key),
      crashRecovery: false,
    );
    clock = _Clock(DateTime.utc(2026, 7, 31, 9));
    outbox = HiveCheckoutOutbox.fromBox(box, clock: clock.call);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  group('identity and payload integrity', () {
    test('uses the exact UID, tenant, checkout key and canonical hash', () {
      expect(
        checkoutOutboxStorageKey(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
        ),
        'user-a:tenant-a:checkout-a',
      );
      expect(
        checkoutPayloadHash(<String, Object?>{
          'z': 1,
          'a': <String, Object?>{'b': true, 'a': 2},
        }),
        checkoutPayloadHash(<String, Object?>{
          'a': <String, Object?>{'a': 2, 'b': true},
          'z': 1,
        }),
      );
      expect(
        () => checkoutOutboxStorageKey(
          uid: 'user:a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
        ),
        throwsArgumentError,
      );
      expect(
        () => checkoutOutboxStorageKey(
          uid: 'user-a',
          tenantId: 'tenant:a',
          checkoutId: 'checkout-a',
        ),
        throwsArgumentError,
      );
      expect(
        () => checkoutPayloadHash(<String, Object?>{
          double.nan.toString(): double.nan,
        }),
        throwsFormatException,
      );
    });

    test('isolates records by both UID and tenant', () async {
      await _save(outbox, uid: 'user-a', tenantId: 'tenant-a');

      expect(
        await outbox.recordsForSession(uid: 'user-a', tenantId: 'tenant-a'),
        hasLength(1),
      );
      expect(
        await outbox.recordsForSession(uid: 'user-b', tenantId: 'tenant-a'),
        isEmpty,
      );
      expect(
        await outbox.recordsForSession(uid: 'user-a', tenantId: 'tenant-b'),
        isEmpty,
      );
    });

    test('freezes payload and rejects reuse with a different hash', () async {
      final payload = <String, Object?>{
        'saleId': 'sale-a',
        'lines': <Object?>[
          <String, Object?>{'quantity': 1},
        ],
      };
      final first = await outbox.saveOffline(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-a',
        payload: payload,
      );
      (payload['lines']! as List<Object?>).clear();

      final replay = await outbox.saveOffline(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-a',
        payload: _payload,
      );
      expect(replay.payloadHash, first.payloadHash);
      expect(replay.payload['lines'], hasLength(1));
      await expectLater(
        outbox.saveOffline(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
          payload: <String, Object?>{'saleId': 'different'},
        ),
        _throwsCode('checkout_already_exists'),
      );
    });
  });

  group('durable state machine', () {
    test('persists every successful transition across a box reopen', () async {
      final saved = await _save(outbox);
      expect(saved.state, CheckoutOutboxState.savedOffline);
      expect(saved.attemptCount, 0);

      final submitting = await outbox.beginSubmission(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-a',
        leaseOwner: 'worker-a',
        leaseDuration: const Duration(minutes: 2),
      );
      expect(submitting.state, CheckoutOutboxState.submitting);
      expect(submitting.attemptCount, 1);
      expect(submitting.leaseOwner, 'worker-a');

      final awaiting = await outbox.markAwaitingConfirmation(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-a',
        leaseOwner: 'worker-a',
      );
      expect(awaiting.state, CheckoutOutboxState.awaitingConfirmation);
      expect(awaiting.leaseOwner, isNull);

      final confirmed = await outbox.recordConfirmation(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-a',
        observedPayloadHash: saved.payloadHash,
      );
      expect(confirmed.state, CheckoutOutboxState.confirmed);

      await box.close();
      box = await Hive.openBox<dynamic>(
        HiveCheckoutOutbox.boxName,
        encryptionCipher: HiveAesCipher(key),
        crashRecovery: false,
      );
      outbox = HiveCheckoutOutbox.fromBox(box, clock: clock.call);
      final reopened = await outbox.read(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-a',
      );
      expect(reopened?.state, CheckoutOutboxState.confirmed);
      expect(reopened?.payloadHash, saved.payloadHash);
      expect(reopened?.attemptCount, 1);
    });

    test(
      'retains a confirmation hash mismatch as needs-attention evidence',
      () async {
        await _advanceToAwaiting(outbox);
        final mismatch = 'f' * 64;

        final result = await outbox.recordConfirmation(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
          observedPayloadHash: mismatch,
        );

        expect(result.state, CheckoutOutboxState.needsAttention);
        expect(result.observedPayloadHash, mismatch);
        expect(result.attentionReason, 'payload_hash_mismatch');
        expect(result.payload, _payload);
        await expectLater(
          outbox.recordConfirmation(
            uid: 'user-a',
            tenantId: 'tenant-a',
            checkoutId: 'checkout-a',
            observedPayloadHash: result.payloadHash,
          ),
          _throwsCode('invalid_transition'),
        );
      },
    );

    test('rejects invalid transitions and lease ownership', () async {
      final saved = await _save(outbox);
      await expectLater(
        outbox.markAwaitingConfirmation(
          uid: saved.uid,
          tenantId: saved.tenantId,
          checkoutId: saved.checkoutId,
          leaseOwner: 'worker-a',
        ),
        _throwsCode('invalid_transition'),
      );
      await expectLater(
        outbox.recordConfirmation(
          uid: saved.uid,
          tenantId: saved.tenantId,
          checkoutId: saved.checkoutId,
          observedPayloadHash: saved.payloadHash,
        ),
        _throwsCode('invalid_transition'),
      );
      await outbox.beginSubmission(
        uid: saved.uid,
        tenantId: saved.tenantId,
        checkoutId: saved.checkoutId,
        leaseOwner: 'worker-a',
        leaseDuration: const Duration(minutes: 1),
      );
      await expectLater(
        outbox.beginSubmission(
          uid: saved.uid,
          tenantId: saved.tenantId,
          checkoutId: saved.checkoutId,
          leaseOwner: 'worker-b',
          leaseDuration: const Duration(minutes: 1),
        ),
        _throwsCode('invalid_transition'),
      );
      await expectLater(
        outbox.markAwaitingConfirmation(
          uid: saved.uid,
          tenantId: saved.tenantId,
          checkoutId: saved.checkoutId,
          leaseOwner: 'worker-b',
        ),
        _throwsCode('lease_not_owned'),
      );
    });

    test('allows only one duplicate worker to acquire the lease', () async {
      await _save(outbox);

      final results = await Future.wait<Object>([
        _capture(
          outbox.beginSubmission(
            uid: 'user-a',
            tenantId: 'tenant-a',
            checkoutId: 'checkout-a',
            leaseOwner: 'worker-a',
            leaseDuration: const Duration(minutes: 1),
          ),
        ),
        _capture(
          outbox.beginSubmission(
            uid: 'user-a',
            tenantId: 'tenant-a',
            checkoutId: 'checkout-a',
            leaseOwner: 'worker-b',
            leaseDuration: const Duration(minutes: 1),
          ),
        ),
      ]);

      expect(results.whereType<CheckoutOutboxRecord>(), hasLength(1));
      expect(
        results.whereType<CheckoutOutboxException>().single.code,
        'invalid_transition',
      );
      expect(
        (await outbox.read(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
        ))?.attemptCount,
        1,
      );
    });

    test(
      'expired lease recovers only to confirmation and never resubmits',
      () async {
        await _save(outbox);
        await outbox.beginSubmission(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
          leaseOwner: 'worker-a',
          leaseDuration: const Duration(minutes: 1),
        );
        await expectLater(
          outbox.recoverExpiredSubmission(
            uid: 'user-a',
            tenantId: 'tenant-a',
            checkoutId: 'checkout-a',
          ),
          _throwsCode('lease_still_active'),
        );

        clock.advance(const Duration(minutes: 1));
        final recovered = await outbox.recoverExpiredSubmission(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
        );
        expect(recovered.state, CheckoutOutboxState.awaitingConfirmation);
        expect(recovered.attemptCount, 1);
        await expectLater(
          outbox.beginSubmission(
            uid: 'user-a',
            tenantId: 'tenant-a',
            checkoutId: 'checkout-a',
            leaseOwner: 'worker-b',
            leaseDuration: const Duration(minutes: 1),
          ),
          _throwsCode('invalid_transition'),
        );
      },
    );

    test('honors a persisted retry time before first submission', () async {
      await _save(outbox, retryAt: clock.value.add(const Duration(minutes: 5)));
      await expectLater(
        outbox.beginSubmission(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
          leaseOwner: 'worker-a',
          leaseDuration: const Duration(minutes: 1),
        ),
        _throwsCode('retry_not_due'),
      );
      clock.advance(const Duration(minutes: 5));
      expect(
        (await outbox.beginSubmission(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
          leaseOwner: 'worker-a',
          leaseDuration: const Duration(minutes: 1),
        )).state,
        CheckoutOutboxState.submitting,
      );
    });
  });

  group('corruption and encrypted reopen', () {
    test('requires an exact 32-byte encryption key', () async {
      await expectLater(
        HiveCheckoutOutbox.open(
          keyProvider: const _StaticKeyProvider(<int>[1, 2]),
          clock: clock.call,
        ),
        _throwsCode('invalid_encryption_key'),
      );
    });

    test('fails closed without deleting a malformed stored record', () async {
      const storageKey = 'user-a:tenant-a:checkout-a';
      await box.put(storageKey, <String, Object?>{'schemaVersion': 99});

      await expectLater(
        outbox.read(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
        ),
        _throwsCode('malformed_record'),
      );
      expect(box.containsKey(storageKey), isTrue);
      expect((box.get(storageKey) as Map)['schemaVersion'], 99);
    });

    test('detects payload tampering and preserves the raw evidence', () async {
      await _save(outbox);
      final raw = Map<Object?, Object?>.from(
        box.get('user-a:tenant-a:checkout-a') as Map,
      );
      raw['payload'] = <String, Object?>{'saleId': 'tampered'};
      await box.put('user-a:tenant-a:checkout-a', raw);

      await expectLater(
        outbox.recordsForSession(uid: 'user-a', tenantId: 'tenant-a'),
        _throwsCode('malformed_record'),
      );
      expect(box.containsKey('user-a:tenant-a:checkout-a'), isTrue);
    });

    test('stores no plaintext and reopens on the host', () async {
      await _save(outbox);
      await box.close();
      final boxBytes = await File(
        '${directory.path}${Platform.pathSeparator}'
        '${HiveCheckoutOutbox.boxName}.hive',
      ).readAsBytes();
      expect(String.fromCharCodes(boxBytes), isNot(contains('sale-a')));
      outbox = await HiveCheckoutOutbox.open(
        keyProvider: _StaticKeyProvider(key),
        clock: clock.call,
      );
      expect(
        await outbox.read(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
        ),
        isNotNull,
      );
    });
  });

  group('tenant-switch state source', () {
    final session = TenantSession.active(
      uid: 'user-a',
      tenantId: 'tenant-a',
      role: TenantRole.cashier,
      epoch: 4,
    );

    test('is clean with no checkout or only confirmed evidence', () async {
      final source = CheckoutOutboxTenantSwitchStateSource(outbox);
      expect((await source.inspect(session))?.blocker, isNull);
      final saved = await _advanceToAwaiting(outbox);
      await outbox.recordConfirmation(
        uid: saved.uid,
        tenantId: saved.tenantId,
        checkoutId: saved.checkoutId,
        observedPayloadHash: saved.payloadHash,
      );
      expect((await source.inspect(session))?.blocker, isNull);
    });

    test('maps saved and awaiting records to unsynchronized', () async {
      final source = CheckoutOutboxTenantSwitchStateSource(outbox);
      await _save(outbox);
      expect(
        (await source.inspect(session))?.blocker,
        TenantSwitchBlocker.unsynchronizedCheckout,
      );
      await outbox.beginSubmission(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-a',
        leaseOwner: 'worker-a',
        leaseDuration: const Duration(minutes: 1),
      );
      await outbox.markAwaitingConfirmation(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-a',
        leaseOwner: 'worker-a',
      );
      expect(
        (await source.inspect(session))?.blocker,
        TenantSwitchBlocker.unsynchronizedCheckout,
      );
    });

    test(
      'maps submitting to in-flight and needs-attention to unsynchronized',
      () async {
        final source = CheckoutOutboxTenantSwitchStateSource(outbox);
        await _save(outbox);
        await outbox.beginSubmission(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
          leaseOwner: 'worker-a',
          leaseDuration: const Duration(minutes: 1),
        );
        expect(
          (await source.inspect(session))?.blocker,
          TenantSwitchBlocker.submissionInFlight,
        );
        await outbox.markAwaitingConfirmation(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
          leaseOwner: 'worker-a',
        );
        await outbox.recordConfirmation(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: 'checkout-a',
          observedPayloadHash: 'f' * 64,
        );
        expect(
          (await source.inspect(session))?.blocker,
          TenantSwitchBlocker.unsynchronizedCheckout,
        );
      },
    );

    test(
      'propagates malformed state for coordinator fail-closed handling',
      () async {
        await box.put('user-a:tenant-a:bad', <String, Object?>{'bad': true});
        final source = CheckoutOutboxTenantSwitchStateSource(outbox);

        await expectLater(
          source.inspect(session),
          _throwsCode('malformed_record'),
        );
      },
    );
  });
}

const Map<String, Object?> _payload = <String, Object?>{
  'saleId': 'sale-a',
  'lines': <Object?>[
    <String, Object?>{'quantity': 1},
  ],
};

Future<CheckoutOutboxRecord> _save(
  HiveCheckoutOutbox outbox, {
  String uid = 'user-a',
  String tenantId = 'tenant-a',
  String checkoutId = 'checkout-a',
  DateTime? retryAt,
}) => outbox.saveOffline(
  uid: uid,
  tenantId: tenantId,
  checkoutId: checkoutId,
  payload: _payload,
  retryAt: retryAt,
);

Future<CheckoutOutboxRecord> _advanceToAwaiting(
  HiveCheckoutOutbox outbox,
) async {
  final saved = await _save(outbox);
  await outbox.beginSubmission(
    uid: saved.uid,
    tenantId: saved.tenantId,
    checkoutId: saved.checkoutId,
    leaseOwner: 'worker-a',
    leaseDuration: const Duration(minutes: 1),
  );
  return outbox.markAwaitingConfirmation(
    uid: saved.uid,
    tenantId: saved.tenantId,
    checkoutId: saved.checkoutId,
    leaseOwner: 'worker-a',
  );
}

Future<Object> _capture(Future<Object> future) async {
  try {
    return await future;
  } catch (error) {
    return error;
  }
}

Matcher _throwsCode(String code) => throwsA(
  isA<CheckoutOutboxException>().having((error) => error.code, 'code', code),
);

final class _Clock {
  _Clock(this.value);

  DateTime value;

  DateTime call() => value;

  void advance(Duration duration) => value = value.add(duration);
}

final class _StaticKeyProvider implements CheckoutOutboxEncryptionKeyProvider {
  const _StaticKeyProvider(this.key);

  final List<int> key;

  @override
  Future<List<int>> loadOrCreateKey() async => key;
}
