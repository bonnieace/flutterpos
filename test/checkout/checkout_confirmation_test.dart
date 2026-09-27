import 'dart:async';
import 'dart:io';

import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late HiveCheckoutOutbox outbox;
  late CheckoutOutboxRecord record;
  final now = DateTime.utc(2026, 7, 31, 10);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('confirmation-test-');
    Hive.init(directory.path);
    final box = await Hive.openBox<dynamic>('confirmation-test');
    outbox = HiveCheckoutOutbox.fromBox(box, clock: () => now);
    record = await _awaiting(outbox);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('waits for writes and reads only the exact canonical sale', () async {
    var waited = false;
    late String tenantId;
    late String checkoutId;
    final gateway = FirebaseCheckoutConfirmationGateway.forTesting(
      isOnline: () async => true,
      waitForPendingWrites: () async => waited = true,
      readServerSale: (tenant, checkout) async {
        tenantId = tenant;
        checkoutId = checkout;
        return CheckoutServerSaleSnapshot.found({
          'tenantId': tenant,
          'checkoutId': checkout,
          'payloadHash': record.payloadHash,
        });
      },
    );

    final result = await gateway.check(record);

    expect(result.kind, CheckoutConfirmationKind.matching);
    expect(result.observedPayloadHash, record.payloadHash);
    expect(waited, isTrue);
    expect((tenantId, checkoutId), ('tenant-a', 'checkout-a'));
  });

  test('returns missing evidence only after pending writes clear', () async {
    final gateway = FirebaseCheckoutConfirmationGateway.forTesting(
      isOnline: () async => true,
      waitForPendingWrites: () async {},
      readServerSale: (_, _) async =>
          const CheckoutServerSaleSnapshot.missing(),
      clock: () => now,
    );

    final result = await gateway.check(record);

    expect(result.kind, CheckoutConfirmationKind.missing);
    expect(result.missingSaleProof?.expectedPayloadHash, record.payloadHash);
    expect(result.missingSaleProof?.checkedAt, now);
  });

  test('classifies a different valid server hash as mismatching', () async {
    final differentHash = 'b' * 64;
    final result = await _gateway(
      record,
      CheckoutServerSaleSnapshot.found({
        'tenantId': record.tenantId,
        'checkoutId': record.checkoutId,
        'payloadHash': differentHash,
      }),
    ).check(record);

    expect(result.kind, CheckoutConfirmationKind.mismatching);
    expect(result.observedPayloadHash, differentHash);
  });

  test('fails closed on malformed server identity or hash', () async {
    final malformed = <Map<String, Object?>>[
      {
        'tenantId': 'tenant-b',
        'checkoutId': record.checkoutId,
        'payloadHash': record.payloadHash,
      },
      {
        'tenantId': record.tenantId,
        'checkoutId': 'other-checkout',
        'payloadHash': record.payloadHash,
      },
      {
        'tenantId': record.tenantId,
        'checkoutId': record.checkoutId,
        'payloadHash': 'not-a-sha256',
      },
    ];

    for (final data in malformed) {
      final result = await _gateway(
        record,
        CheckoutServerSaleSnapshot.found(data),
      ).check(record);
      expect(result.kind, CheckoutConfirmationKind.malformed);
    }
  });

  test('offline and transport failures remain unavailable', () async {
    var waitCalls = 0;
    final offline = FirebaseCheckoutConfirmationGateway.forTesting(
      isOnline: () async => false,
      waitForPendingWrites: () async => waitCalls++,
      readServerSale: (_, _) async => throw StateError('must not read'),
    );
    expect(
      (await offline.check(record)).kind,
      CheckoutConfirmationKind.unavailable,
    );
    expect(waitCalls, 0);

    final failedRead = FirebaseCheckoutConfirmationGateway.forTesting(
      isOnline: () async => true,
      waitForPendingWrites: () async {},
      readServerSale: (_, _) async => throw StateError('offline'),
    );
    expect(
      (await failedRead.check(record)).kind,
      CheckoutConfirmationKind.unavailable,
    );
  });

  test('a pending-write timeout never reads or reports missing', () async {
    var readCalls = 0;
    final pendingWrites = Completer<void>();
    final gateway = FirebaseCheckoutConfirmationGateway.forTesting(
      isOnline: () async => true,
      waitForPendingWrites: () => pendingWrites.future,
      readServerSale: (_, _) async {
        readCalls++;
        return const CheckoutServerSaleSnapshot.missing();
      },
      pendingWritesTimeout: const Duration(milliseconds: 5),
    );

    expect(
      (await gateway.check(record)).kind,
      CheckoutConfirmationKind.pendingWrites,
    );
    expect(readCalls, 0);
  });
}

FirebaseCheckoutConfirmationGateway _gateway(
  CheckoutOutboxRecord record,
  CheckoutServerSaleSnapshot snapshot,
) => FirebaseCheckoutConfirmationGateway.forTesting(
  isOnline: () async => true,
  waitForPendingWrites: () async {},
  readServerSale: (_, _) async => snapshot,
);

Future<CheckoutOutboxRecord> _awaiting(HiveCheckoutOutbox outbox) async {
  final saved = await outbox.saveOffline(
    uid: 'user-a',
    tenantId: 'tenant-a',
    checkoutId: 'checkout-a',
    payload: const <String, Object?>{'totalMinor': 100},
  );
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
