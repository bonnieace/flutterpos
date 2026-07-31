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
    directory = await Directory.systemTemp.createTemp('checkout-sync-test-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>(
      'checkout-sync-test',
      encryptionCipher: HiveAesCipher(_encryptionKey),
      crashRecovery: false,
    );
    clock = _Clock(DateTime.utc(2026, 7, 31, 12));
    outbox = HiveCheckoutOutbox.fromBox(box, clock: clock.call);
    sessions = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
  });

  tearDown(() async {
    sessions.dispose();
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('holds the lease across the one commit, then awaits confirmation', () async {
    await _save(outbox, 'checkout-a');
    final leaseStates = <(CheckoutOutboxState, String?)>[];
    final gateway = _FakeGateway((submission) async {
      final record = await outbox.read(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: submission.checkoutId,
      );
      leaseStates.add((record!.state, record.leaseOwner));
      return const CheckoutSubmissionResult.committed();
    });

    final result = await _worker(sessions, outbox, gateway, clock)
        .submitDueCheckouts();

    expect(result.kind, CheckoutSyncRunKind.completed);
    expect(result.submitted, 1);
    expect(leaseStates, [(CheckoutOutboxState.submitting, _workerId)]);
    expect(gateway.submissions.single.salePath, 'tenants/tenant-a/sales/checkout-a');
    final stored = await _read(outbox, 'checkout-a');
    expect(stored.state, CheckoutOutboxState.awaitingConfirmation);
    expect(stored.attemptCount, 1);
    expect(stored.leaseOwner, isNull);
  });

  test('submits only due records for this UID and tenant', () async {
    await _save(outbox, 'due');
    await _save(outbox, 'other-tenant', tenantId: 'tenant-b');
    await _save(outbox, 'other-user', uid: 'user-b');
    await _save(outbox, 'not-due');
    await outbox.beginSubmission(
      uid: 'user-a',
      tenantId: 'tenant-a',
      checkoutId: 'not-due',
      leaseOwner: 'worker-other',
      leaseDuration: const Duration(minutes: 1),
    );
    await outbox.markAwaitingConfirmation(
      uid: 'user-a',
      tenantId: 'tenant-a',
      checkoutId: 'not-due',
      leaseOwner: 'worker-other',
    );
    await outbox.markRetryableAfterMissingSale(
      proof: CheckoutMissingSaleProof.confirmed(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'not-due',
        expectedPayloadHash: (await _read(outbox, 'not-due')).payloadHash,
        checkedAt: clock.call(),
      ),
      backoff: const Duration(minutes: 10),
    );
    final gateway = _FakeGateway(
      (_) async => const CheckoutSubmissionResult.committed(),
    );

    final result = await _worker(sessions, outbox, gateway, clock)
        .submitDueCheckouts();

    expect(
      gateway.submissions.map((submission) => submission.checkoutId),
      ['due'],
    );
    expect((result.submitted, result.skipped), (1, 1));
    expect(
      (await _read(outbox, 'not-due')).state,
      CheckoutOutboxState.savedOffline,
    );
  });

  test('never writes or leases while offline', () async {
    await _save(outbox, 'offline');
    final gateway = _FakeGateway(
      (_) async => throw StateError('must not submit'),
    );

    final result = await _worker(
      sessions,
      outbox,
      gateway,
      clock,
      isOnline: () async => false,
    ).submitDueCheckouts();

    expect(result.kind, CheckoutSyncRunKind.offline);
    expect(gateway.submissions, isEmpty);
    expect(
      (await _read(outbox, 'offline')).state,
      CheckoutOutboxState.savedOffline,
    );
  });

  test('retains malformed payload evidence without leasing it', () async {
    await outbox.saveOffline(
      uid: 'user-a',
      tenantId: 'tenant-a',
      checkoutId: 'malformed',
      payload: const <String, Object?>{'schemaVersion': 1},
    );
    await _save(outbox, 'valid');
    final gateway = _FakeGateway(
      (_) async => const CheckoutSubmissionResult.committed(),
    );

    final result = await _worker(sessions, outbox, gateway, clock)
        .submitDueCheckouts();

    expect((result.malformed, result.submitted), (1, 1));
    expect(
      gateway.submissions.map((submission) => submission.checkoutId),
      ['valid'],
    );
    final malformed = await _read(outbox, 'malformed');
    expect(malformed.state, CheckoutOutboxState.savedOffline);
    expect(malformed.attemptCount, 0);
  });

  test('an ambiguous or refused commit stays submitting across a reopen', () async {
    await _save(outbox, 'ambiguous');
    await _save(outbox, 'rejected');
    final gateway = _FakeGateway(
      (submission) async => submission.checkoutId == 'ambiguous'
          ? const CheckoutSubmissionResult.ambiguous('commit_timeout')
          : const CheckoutSubmissionResult.rejected('permission-denied'),
    );

    final result = await _worker(sessions, outbox, gateway, clock)
        .submitDueCheckouts();

    expect((result.ambiguous, result.rejected, result.submitted), (1, 1, 0));
    await box.close();
    box = await Hive.openBox<dynamic>(
      'checkout-sync-test',
      encryptionCipher: HiveAesCipher(_encryptionKey),
      crashRecovery: false,
    );
    outbox = HiveCheckoutOutbox.fromBox(box, clock: clock.call);

    for (final checkoutId in ['ambiguous', 'rejected']) {
      final record = await _read(outbox, checkoutId);
      expect(record.state, CheckoutOutboxState.submitting, reason: checkoutId);
      expect(record.leaseOwner, _workerId);
      expect(record.attemptCount, 1);
    }
  });

  test('a lease lost during a slow commit is never confirmed locally', () async {
    await _save(outbox, 'slow');
    final gateway = _FakeGateway((_) async {
      clock.advance(const Duration(minutes: 5));
      return const CheckoutSubmissionResult.committed();
    });

    final result = await _worker(
      sessions,
      outbox,
      gateway,
      clock,
      leaseDuration: const Duration(minutes: 1),
    ).submitDueCheckouts();

    expect((result.submitted, result.ambiguous), (0, 1));
    expect((await _read(outbox, 'slow')).state, CheckoutOutboxState.submitting);
  });

  test('skips a checkout another worker already holds', () async {
    await _save(outbox, 'held');
    await outbox.beginSubmission(
      uid: 'user-a',
      tenantId: 'tenant-a',
      checkoutId: 'held',
      leaseOwner: 'worker-other',
      leaseDuration: const Duration(minutes: 1),
    );
    final gateway = _FakeGateway(
      (_) async => throw StateError('must not submit'),
    );

    final result = await _worker(sessions, outbox, gateway, clock)
        .submitDueCheckouts();

    expect((result.kind, result.skipped), (CheckoutSyncRunKind.completed, 1));
    expect(gateway.submissions, isEmpty);
    expect((await _read(outbox, 'held')).leaseOwner, 'worker-other');
  });

  test('coalesces duplicate triggers into one submission', () async {
    await _save(outbox, 'duplicate');
    final requested = Completer<void>();
    final completion = Completer<CheckoutSubmissionResult>();
    final gateway = _FakeGateway((_) {
      if (!requested.isCompleted) requested.complete();
      return completion.future;
    });
    final worker = _worker(sessions, outbox, gateway, clock);

    final first = worker.submitDueCheckouts();
    await requested.future;
    expect(
      (await worker.submitDueCheckouts()).kind,
      CheckoutSyncRunKind.alreadyRunning,
    );
    completion.complete(const CheckoutSubmissionResult.committed());
    expect((await first).submitted, 1);
    await _settle();

    expect(gateway.submissions.length, 1);
    expect(
      (await _read(outbox, 'duplicate')).state,
      CheckoutOutboxState.awaitingConfirmation,
    );
  });

  test('discards a commit result after the session epoch changes', () async {
    await _save(outbox, 'stale');
    final requested = Completer<void>();
    final completion = Completer<CheckoutSubmissionResult>();
    final gateway = _FakeGateway((_) {
      if (!requested.isCompleted) requested.complete();
      return completion.future;
    });
    final run = _worker(sessions, outbox, gateway, clock).submitDueCheckouts();
    await requested.future;
    sessions.open(uid: 'user-a', membership: _membership('tenant-b'));
    completion.complete(const CheckoutSubmissionResult.committed());

    expect((await run).kind, CheckoutSyncRunKind.sessionChanged);
    expect((await _read(outbox, 'stale')).state, CheckoutOutboxState.submitting);
  });

  test('stops leasing more checkouts when connectivity is lost', () async {
    await _save(outbox, 'a-first');
    await _save(outbox, 'b-second');
    final gateway = _FakeGateway(
      (_) async => const CheckoutSubmissionResult.unavailable(),
    );

    final result = await _worker(sessions, outbox, gateway, clock)
        .submitDueCheckouts();

    expect((result.ambiguous, result.skipped), (1, 1));
    expect(gateway.submissions.length, 1);
    expect(
      (await _read(outbox, 'b-second')).state,
      CheckoutOutboxState.savedOffline,
    );
  });

  test('requires a selected canonical session', () async {
    await _save(outbox, 'no-session');
    sessions.clear();
    final gateway = _FakeGateway(
      (_) async => throw StateError('must not submit'),
    );

    expect(
      (await _worker(sessions, outbox, gateway, clock).submitDueCheckouts()).kind,
      CheckoutSyncRunKind.noSelectedSession,
    );
    expect(gateway.submissions, isEmpty);
  });
}

const String _workerId = 'checkout-sync-test-worker';
final List<int> _encryptionKey = List<int>.generate(32, (index) => index);

CheckoutSubmissionWorker _worker(
  TenantSessionController sessions,
  HiveCheckoutOutbox outbox,
  CheckoutSubmissionGateway gateway,
  _Clock clock, {
  Future<bool> Function()? isOnline,
  Duration leaseDuration = const Duration(minutes: 2),
}) => CheckoutSubmissionWorker(
  sessionController: sessions,
  outbox: outbox,
  submissionGateway: gateway,
  isOnline: isOnline ?? () async => true,
  workerId: _workerId,
  leaseDuration: leaseDuration,
  clock: clock.call,
);

const String _deviceId = 'dev-0123456789abcdef0123456789abcdef';

Future<CheckoutOutboxRecord> _save(
  HiveCheckoutOutbox outbox,
  String checkoutId, {
  String uid = 'user-a',
  String tenantId = 'tenant-a',
}) => outbox.saveOffline(
  uid: uid,
  tenantId: tenantId,
  checkoutId: checkoutId,
  payload: <String, Object?>{
    'schemaVersion': checkoutSalePayloadSchemaVersion,
    'checkoutId': checkoutId,
    'tenantId': tenantId,
    'soldById': uid,
    'currency': 'KES',
    'businessDate': '2026-07-31',
    'createdAtMs': 1785484800000,
    'shiftId': 'shift-a',
    'deviceId': _deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: _deviceId,
      businessDate: '2026-07-31',
      sequence: 7,
    ),
    'receiptSequence': 7,
    'items': <Map<String, Object?>>[
      {
        'productId': 'product-a',
        'name': 'Coffee',
        'quantity': 2,
        'unitPriceMinor': 25000,
      },
    ],
    'subtotalMinor': 50000,
    'discountMinor': 0,
    'totalMinor': 50000,
  },
);

Future<CheckoutOutboxRecord> _read(
  HiveCheckoutOutbox outbox,
  String checkoutId, {
  String uid = 'user-a',
  String tenantId = 'tenant-a',
}) async =>
    (await outbox.read(uid: uid, tenantId: tenantId, checkoutId: checkoutId))!;

Future<void> _settle() async {
  for (var turn = 0; turn < 20; turn++) {
    await Future<void>.delayed(Duration.zero);
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

final class _FakeGateway implements CheckoutSubmissionGateway {
  _FakeGateway(this.handler);

  final Future<CheckoutSubmissionResult> Function(CheckoutSaleSubmission)
  handler;
  final List<CheckoutSaleSubmission> submissions = [];

  @override
  Future<CheckoutSubmissionResult> submit(CheckoutSaleSubmission submission) {
    submissions.add(submission);
    return handler(submission);
  }
}

final class _Clock {
  _Clock(this.value);

  DateTime value;

  DateTime call() => value;

  void advance(Duration duration) => value = value.add(duration);
}
