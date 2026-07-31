import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const String _deviceId = 'dev-0123456789abcdef0123456789abcdef';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveCheckoutOutbox outbox;
  late CheckoutOutboxShiftSalesLedger ledger;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shift-ledger-test-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>(
      HiveCheckoutOutbox.boxName,
      encryptionCipher: HiveAesCipher(_encryptionKey),
      crashRecovery: false,
    );
    outbox = HiveCheckoutOutbox.fromBox(
      box,
      clock: () => DateTime.utc(2026, 7, 31, 9),
    );
    ledger = CheckoutOutboxShiftSalesLedger(outbox);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('summarizes only confirmed sales of the requested shift', () async {
    await _confirm(outbox, 'checkout-a', totalMinor: 25000);
    await _confirm(outbox, 'checkout-b', totalMinor: 15500);
    await _confirm(
      outbox,
      'checkout-other-shift',
      totalMinor: 90000,
      shiftId: 'shift-b',
    );
    await _confirm(
      outbox,
      'checkout-other-tenant',
      totalMinor: 90000,
      tenantId: 'tenant-b',
    );

    final summary = await ledger.summarize(
      uid: 'user-a',
      tenantId: 'tenant-a',
      shiftId: 'shift-a',
    );

    expect(summary.transactionCount, 2);
    expect(summary.totalMinor, 40500);
    expect(summary.totalSales, 405.0);
    expect(summary.unsettledCount, 0);
    expect(summary.isComplete, isTrue);
  });

  test('counts every unconfirmed local sale as unsettled', () async {
    await _confirm(outbox, 'checkout-a', totalMinor: 25000);
    await _save(outbox, 'checkout-queued', totalMinor: 5000);
    final submitting = await _save(
      outbox,
      'checkout-submitting',
      totalMinor: 7000,
    );
    await outbox.beginSubmission(
      uid: submitting.uid,
      tenantId: submitting.tenantId,
      checkoutId: submitting.checkoutId,
      leaseOwner: 'worker-a',
      leaseDuration: const Duration(minutes: 2),
    );

    final summary = await ledger.summarize(
      uid: 'user-a',
      tenantId: 'tenant-a',
      shiftId: 'shift-a',
    );

    // The device cannot yet prove what the server holds for this shift.
    expect(summary.transactionCount, 1);
    expect(summary.totalMinor, 25000);
    expect(summary.unsettledCount, 2);
    expect(summary.isComplete, isFalse);
  });

  test('an empty shift is complete and reports nothing', () async {
    final summary = await ledger.summarize(
      uid: 'user-a',
      tenantId: 'tenant-a',
      shiftId: 'shift-a',
    );

    expect(summary.transactionCount, 0);
    expect(summary.totalMinor, 0);
    expect(summary.isComplete, isTrue);
  });

  test('an unattributed local sale fails closed', () async {
    // A sale that names no shift could never be aggregated into one, so it is
    // raised rather than silently omitted from the shift total.
    await outbox.saveOffline(
      uid: 'user-a',
      tenantId: 'tenant-a',
      checkoutId: 'checkout-legacy',
      payload: _payload('checkout-legacy', totalMinor: 100)
        ..remove('shiftId'),
    );

    await expectLater(
      ledger.summarize(
        uid: 'user-a',
        tenantId: 'tenant-a',
        shiftId: 'shift-a',
      ),
      throwsA(
        isA<ShiftSalesLedgerException>().having(
          (error) => error.code,
          'code',
          'unattributed_local_sale',
        ),
      ),
    );
  });

  test('a malformed confirmed total fails closed', () async {
    await _confirm(outbox, 'checkout-a', totalMinor: -5);

    await expectLater(
      ledger.summarize(
        uid: 'user-a',
        tenantId: 'tenant-a',
        shiftId: 'shift-a',
      ),
      throwsA(
        isA<ShiftSalesLedgerException>().having(
          (error) => error.code,
          'code',
          'malformed_local_sale',
        ),
      ),
    );
  });

  test('survives reopening the encrypted box', () async {
    await _confirm(outbox, 'checkout-a', totalMinor: 25000);
    await Hive.close();

    Hive.init(directory.path);
    final reopened = HiveCheckoutOutbox.fromBox(
      await Hive.openBox<dynamic>(
        HiveCheckoutOutbox.boxName,
        encryptionCipher: HiveAesCipher(_encryptionKey),
        crashRecovery: false,
      ),
    );

    final summary = await CheckoutOutboxShiftSalesLedger(reopened).summarize(
      uid: 'user-a',
      tenantId: 'tenant-a',
      shiftId: 'shift-a',
    );
    expect(summary.transactionCount, 1);
    expect(summary.totalMinor, 25000);
  });
}

final List<int> _encryptionKey = List<int>.generate(
  HiveCheckoutOutbox.encryptionKeyBytes,
  (index) => (index * 7) % 256,
);

Future<CheckoutOutboxRecord> _save(
  HiveCheckoutOutbox outbox,
  String checkoutId, {
  required int totalMinor,
  String uid = 'user-a',
  String tenantId = 'tenant-a',
  String shiftId = 'shift-a',
}) => outbox.saveOffline(
  uid: uid,
  tenantId: tenantId,
  checkoutId: checkoutId,
  payload: _payload(
    checkoutId,
    totalMinor: totalMinor,
    uid: uid,
    tenantId: tenantId,
    shiftId: shiftId,
  ),
);

/// Walks one checkout through the frozen state machine to `confirmed`.
Future<void> _confirm(
  HiveCheckoutOutbox outbox,
  String checkoutId, {
  required int totalMinor,
  String uid = 'user-a',
  String tenantId = 'tenant-a',
  String shiftId = 'shift-a',
}) async {
  final record = await _save(
    outbox,
    checkoutId,
    totalMinor: totalMinor,
    uid: uid,
    tenantId: tenantId,
    shiftId: shiftId,
  );
  await outbox.beginSubmission(
    uid: uid,
    tenantId: tenantId,
    checkoutId: checkoutId,
    leaseOwner: 'worker-a',
    leaseDuration: const Duration(minutes: 2),
  );
  await outbox.markAwaitingConfirmation(
    uid: uid,
    tenantId: tenantId,
    checkoutId: checkoutId,
    leaseOwner: 'worker-a',
  );
  await outbox.recordConfirmation(
    uid: uid,
    tenantId: tenantId,
    checkoutId: checkoutId,
    observedPayloadHash: record.payloadHash,
  );
}

Map<String, Object?> _payload(
  String checkoutId, {
  required int totalMinor,
  String uid = 'user-a',
  String tenantId = 'tenant-a',
  String shiftId = 'shift-a',
}) => <String, Object?>{
  'schemaVersion': checkoutSalePayloadSchemaVersion,
  'checkoutId': checkoutId,
  'tenantId': tenantId,
  'soldById': uid,
  'currency': 'KES',
  'businessDate': '2026-07-31',
  'createdAtMs': 1785484800000,
  'shiftId': shiftId,
  'deviceId': _deviceId,
  'receiptNumber': formatCheckoutReceiptNumber(
    deviceId: _deviceId,
    businessDate: '2026-07-31',
    sequence: 1,
  ),
  'receiptSequence': 1,
  'items': <Map<String, Object?>>[
    {
      'productId': 'product-a',
      'name': 'Coffee',
      'quantity': 1,
      'unitPriceMinor': totalMinor,
    },
  ],
  'subtotalMinor': totalMinor,
  'discountMinor': 0,
  'totalMinor': totalMinor,
};
