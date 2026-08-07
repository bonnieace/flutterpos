import 'dart:async';
import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late _Clock clock;
  late HiveCheckoutOutbox outbox;
  late TenantSessionController sessions;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('recovery-test-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>(
      'recovery-test',
      encryptionCipher: HiveAesCipher(_encryptionKey),
      crashRecovery: false,
    );
    clock = _Clock(DateTime.utc(2026, 7, 31, 11));
    outbox = HiveCheckoutOutbox.fromBox(box, clock: clock.call);
    sessions = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
  });

  tearDown(() async {
    sessions.dispose();
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'records matching, mismatching, and safely retryable outcomes',
    () async {
      final matching = await _awaiting(outbox, 'matching');
      final mismatching = await _awaiting(outbox, 'mismatching');
      await _awaiting(outbox, 'missing');
      final gateway = _FakeGateway((record) async {
        return switch (record.checkoutId) {
          'matching' => CheckoutConfirmationResult.matching(record.payloadHash),
          'mismatching' => CheckoutConfirmationResult.mismatching('b' * 64),
          _ => CheckoutConfirmationResult.missing(record, clock.call()),
        };
      });
      final coordinator = _coordinator(sessions, outbox, gateway, clock);

      final result = await coordinator.recoverSelectedSession();

      expect(result.kind, CheckoutRecoveryRunKind.completed);
      expect(
        (result.confirmed, result.needsAttention, result.retryable),
        (1, 1, 1),
      );
      expect(
        (await _read(outbox, matching)).state,
        CheckoutOutboxState.confirmed,
      );
      final attention = await _read(outbox, mismatching);
      expect(attention.state, CheckoutOutboxState.needsAttention);
      expect(attention.observedPayloadHash, 'b' * 64);
      final retry = (await outbox.read(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'missing',
      ))!;
      expect(retry.state, CheckoutOutboxState.savedOffline);
      expect(retry.attemptCount, 1);
      expect(retry.retryAt, clock.call().add(const Duration(seconds: 30)));
    },
  );

  test(
    'retains pending, unavailable, and malformed confirmation evidence',
    () async {
      await _awaiting(outbox, 'pending');
      await _awaiting(outbox, 'unavailable');
      await _awaiting(outbox, 'malformed');
      final gateway = _FakeGateway(
        (record) async => switch (record.checkoutId) {
          'pending' => const CheckoutConfirmationResult.pendingWrites(),
          'unavailable' => const CheckoutConfirmationResult.unavailable(),
          _ => const CheckoutConfirmationResult.malformed(),
        },
      );

      final result = await _coordinator(
        sessions,
        outbox,
        gateway,
        clock,
      ).recoverSelectedSession();

      expect(result.retained, 3);
      for (final id in ['pending', 'unavailable', 'malformed']) {
        expect(
          (await outbox.read(
            uid: 'user-a',
            tenantId: 'tenant-a',
            checkoutId: id,
          ))?.state,
          CheckoutOutboxState.awaitingConfirmation,
        );
      }
    },
  );

  test(
    'expired leases become confirmation-only while active leases remain',
    () async {
      final expired = await _submitting(outbox, 'expired');
      final active = await _submitting(
        outbox,
        'active',
        leaseDuration: const Duration(minutes: 3),
      );
      clock.advance(const Duration(minutes: 2));
      final gateway = _FakeGateway(
        (record) async =>
            CheckoutConfirmationResult.matching(record.payloadHash),
      );

      final result = await _coordinator(
        sessions,
        outbox,
        gateway,
        clock,
      ).recoverSelectedSession();

      expect(result.confirmed, 1);
      expect(result.retained, 1);
      expect(
        (await _read(outbox, expired)).state,
        CheckoutOutboxState.confirmed,
      );
      expect(
        (await _read(outbox, active)).state,
        CheckoutOutboxState.submitting,
      );
    },
  );

  test('lease expiry alone never authorizes retry or submission', () async {
    final record = await _submitting(outbox, 'uncertain');
    clock.advance(const Duration(minutes: 2));
    final result = await _coordinator(
      sessions,
      outbox,
      _FakeGateway((_) async => const CheckoutConfirmationResult.unavailable()),
      clock,
    ).recoverSelectedSession();

    expect(result.retained, 1);
    expect(
      (await _read(outbox, record)).state,
      CheckoutOutboxState.awaitingConfirmation,
    );
  });

  test(
    'discards a confirmation result after the session epoch changes',
    () async {
      final record = await _awaiting(outbox, 'stale');
      final completion = Completer<CheckoutConfirmationResult>();
      final coordinator = _coordinator(
        sessions,
        outbox,
        _FakeGateway((_) => completion.future),
        clock,
      );
      final recovery = coordinator.recoverSelectedSession();
      await Future<void>.delayed(Duration.zero);
      sessions.open(uid: 'user-a', membership: _membership('tenant-b'));
      completion.complete(
        CheckoutConfirmationResult.matching(record.payloadHash),
      );

      expect((await recovery).kind, CheckoutRecoveryRunKind.sessionChanged);
      expect(
        (await _read(outbox, record)).state,
        CheckoutOutboxState.awaitingConfirmation,
      );
    },
  );

  test('queues one fresh recovery when the selected session changes', () async {
    final tenantA = await _awaiting(outbox, 'tenant-a-checkout');
    final tenantB = await _awaiting(
      outbox,
      'tenant-b-checkout',
      tenantId: 'tenant-b',
    );
    final tenantACompletion = Completer<CheckoutConfirmationResult>();
    final tenantBRequested = Completer<void>();
    final tenantBCompletion = Completer<CheckoutConfirmationResult>();
    final coordinator = _coordinator(
      sessions,
      outbox,
      _FakeGateway((record) {
        if (record.tenantId == 'tenant-a') return tenantACompletion.future;
        tenantBRequested.complete();
        return tenantBCompletion.future;
      }),
      clock,
    );
    final first = coordinator.recoverSelectedSession();
    await Future<void>.delayed(Duration.zero);
    sessions.open(uid: 'user-a', membership: _membership('tenant-b'));

    expect(
      (await coordinator.recoverSelectedSession()).kind,
      CheckoutRecoveryRunKind.alreadyRunning,
    );
    tenantACompletion.complete(
      CheckoutConfirmationResult.matching(tenantA.payloadHash),
    );
    expect((await first).kind, CheckoutRecoveryRunKind.sessionChanged);
    await tenantBRequested.future;
    tenantBCompletion.complete(
      CheckoutConfirmationResult.matching(tenantB.payloadHash),
    );
    await _waitForState(outbox, tenantB, CheckoutOutboxState.confirmed);

    expect(
      (await _read(outbox, tenantA)).state,
      CheckoutOutboxState.awaitingConfirmation,
    );
  });

  test('coalesces duplicate recovery workers in one session', () async {
    await _awaiting(outbox, 'duplicate');
    final completion = Completer<CheckoutConfirmationResult>();
    final rerun = Completer<void>();
    final gateway = _FakeGateway((record) {
      if (!completion.isCompleted) return completion.future;
      rerun.complete();
      return Future.value(const CheckoutConfirmationResult.unavailable());
    });
    final coordinator = _coordinator(sessions, outbox, gateway, clock);
    final first = coordinator.recoverSelectedSession();
    await Future<void>.delayed(Duration.zero);

    expect(
      (await coordinator.recoverSelectedSession()).kind,
      CheckoutRecoveryRunKind.alreadyRunning,
    );
    completion.complete(const CheckoutConfirmationResult.unavailable());
    await first;
    await rerun.future;
    expect(gateway.calls, 2);
  });

  test('scans only the authenticated UID and selected tenant', () async {
    await _awaiting(outbox, 'selected');
    await _awaiting(outbox, 'other-tenant', tenantId: 'tenant-b');
    await _awaiting(outbox, 'other-user', uid: 'user-b');
    final gateway = _FakeGateway(
      (record) async => CheckoutConfirmationResult.matching(record.payloadHash),
    );

    await _coordinator(
      sessions,
      outbox,
      gateway,
      clock,
    ).recoverSelectedSession();

    expect(gateway.records.map((record) => record.checkoutId), ['selected']);
  });

  test('retry backoff and attempt count survive a Hive box reopen', () async {
    final awaiting = await _awaiting(outbox, 'reopen');
    await outbox.markRetryableAfterMissingSale(
      proof: CheckoutMissingSaleProof.confirmed(
        uid: awaiting.uid,
        tenantId: awaiting.tenantId,
        checkoutId: awaiting.checkoutId,
        expectedPayloadHash: awaiting.payloadHash,
        checkedAt: clock.call(),
      ),
      backoff: const Duration(minutes: 2),
    );
    await box.close();
    box = await Hive.openBox<dynamic>(
      'recovery-test',
      encryptionCipher: HiveAesCipher(_encryptionKey),
      crashRecovery: false,
    );
    outbox = HiveCheckoutOutbox.fromBox(box, clock: clock.call);

    await expectLater(
      outbox.beginSubmission(
        uid: awaiting.uid,
        tenantId: awaiting.tenantId,
        checkoutId: awaiting.checkoutId,
        leaseOwner: 'worker-b',
        leaseDuration: const Duration(minutes: 1),
      ),
      _throwsCode('retry_not_due'),
    );
    clock.advance(const Duration(minutes: 2));
    final submitting = await outbox.beginSubmission(
      uid: awaiting.uid,
      tenantId: awaiting.tenantId,
      checkoutId: awaiting.checkoutId,
      leaseOwner: 'worker-b',
      leaseDuration: const Duration(minutes: 1),
    );
    expect(submitting.attemptCount, 2);
  });

  test(
    'rejects stale or mismatching missing-sale proof without mutation',
    () async {
      final awaiting = await _awaiting(outbox, 'bad-proof');
      final proof = CheckoutMissingSaleProof.confirmed(
        uid: awaiting.uid,
        tenantId: awaiting.tenantId,
        checkoutId: awaiting.checkoutId,
        expectedPayloadHash: 'b' * 64,
        checkedAt: clock.call(),
      );

      await expectLater(
        outbox.markRetryableAfterMissingSale(
          proof: proof,
          backoff: const Duration(seconds: 30),
        ),
        _throwsCode('invalid_missing_sale_proof'),
      );
      expect(
        (await _read(outbox, awaiting)).state,
        CheckoutOutboxState.awaitingConfirmation,
      );
    },
  );

  test('malformed local evidence fails closed without deleting it', () async {
    final awaiting = await _awaiting(outbox, 'corrupt');
    final raw = Map<Object?, Object?>.from(box.get(awaiting.storageKey) as Map)
      ..['payloadHash'] = 'corrupt';
    await box.put(awaiting.storageKey, raw);

    final result = await _coordinator(
      sessions,
      outbox,
      _FakeGateway((_) async => throw StateError('must not reach gateway')),
      clock,
    ).recoverSelectedSession();

    expect(result.kind, CheckoutRecoveryRunKind.storageUnavailable);
    expect(box.get(awaiting.storageKey), raw);
  });
}

final List<int> _encryptionKey = List<int>.generate(32, (index) => index);

CheckoutRecoveryCoordinator _coordinator(
  TenantSessionController sessions,
  HiveCheckoutOutbox outbox,
  CheckoutConfirmationGateway gateway,
  _Clock clock,
) => CheckoutRecoveryCoordinator(
  sessionController: sessions,
  outbox: outbox,
  confirmationGateway: gateway,
  clock: clock.call,
);

Future<CheckoutOutboxRecord> _awaiting(
  HiveCheckoutOutbox outbox,
  String checkoutId, {
  String uid = 'user-a',
  String tenantId = 'tenant-a',
}) async {
  await outbox.saveOffline(
    uid: uid,
    tenantId: tenantId,
    checkoutId: checkoutId,
    payload: <String, Object?>{'checkoutId': checkoutId},
  );
  await outbox.beginSubmission(
    uid: uid,
    tenantId: tenantId,
    checkoutId: checkoutId,
    leaseOwner: 'worker-a',
    leaseDuration: const Duration(minutes: 1),
  );
  return outbox.markAwaitingConfirmation(
    uid: uid,
    tenantId: tenantId,
    checkoutId: checkoutId,
    leaseOwner: 'worker-a',
  );
}

Future<CheckoutOutboxRecord> _submitting(
  HiveCheckoutOutbox outbox,
  String checkoutId, {
  Duration leaseDuration = const Duration(minutes: 1),
}) async {
  await outbox.saveOffline(
    uid: 'user-a',
    tenantId: 'tenant-a',
    checkoutId: checkoutId,
    payload: <String, Object?>{'checkoutId': checkoutId},
  );
  return outbox.beginSubmission(
    uid: 'user-a',
    tenantId: 'tenant-a',
    checkoutId: checkoutId,
    leaseOwner: 'worker-a',
    leaseDuration: leaseDuration,
  );
}

Future<CheckoutOutboxRecord> _read(
  HiveCheckoutOutbox outbox,
  CheckoutOutboxRecord record,
) async => (await outbox.read(
  uid: record.uid,
  tenantId: record.tenantId,
  checkoutId: record.checkoutId,
))!;

/// Waits for a rerun the coordinator schedules for itself, which is the one
/// thing in this file with no future to hold.
///
/// The turns are real milliseconds against a wall-clock deadline rather than
/// twenty `Duration.zero` turns, because what is being waited for is a
/// `recordConfirmation` write to a real encrypted Hive box, and a zero-duration
/// turn does not wait for a disk. Twenty of them proved too few about one run in
/// seven in `test/checkout/checkout_sync_signals_test.dart` - the same mechanism
/// over the same kind of box - and this helper had simply not been unlucky yet.
/// See `_settleUntil` there for the measurements.
Future<void> _waitForState(
  HiveCheckoutOutbox outbox,
  CheckoutOutboxRecord record,
  CheckoutOutboxState state,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while ((await _read(outbox, record)).state != state) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Checkout ${record.checkoutId} did not reach $state.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

TenantMembership _membership(String tenantId) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: TenantRole.cashier,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

Matcher _throwsCode(String code) => throwsA(
  isA<CheckoutOutboxException>().having((error) => error.code, 'code', code),
);

final class _FakeGateway implements CheckoutConfirmationGateway {
  _FakeGateway(this.handler);

  final Future<CheckoutConfirmationResult> Function(CheckoutOutboxRecord)
  handler;
  final List<CheckoutOutboxRecord> records = [];
  int calls = 0;

  @override
  Future<CheckoutConfirmationResult> check(CheckoutOutboxRecord record) {
    calls++;
    records.add(record);
    return handler(record);
  }
}

final class _Clock {
  _Clock(this.value);

  DateTime value;

  DateTime call() => value;

  void advance(Duration duration) => value = value.add(duration);
}
