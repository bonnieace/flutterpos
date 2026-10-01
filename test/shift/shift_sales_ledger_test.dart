import 'dart:io';

import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/shift/shift.dart';
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
      payload: _payload('checkout-legacy', totalMinor: 100)..remove('shiftId'),
    );

    await expectLater(
      ledger.summarize(uid: 'user-a', tenantId: 'tenant-a', shiftId: 'shift-a'),
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
      ledger.summarize(uid: 'user-a', tenantId: 'tenant-a', shiftId: 'shift-a'),
      throwsA(
        isA<ShiftSalesLedgerException>().having(
          (error) => error.code,
          'code',
          'malformed_local_sale',
        ),
      ),
    );
  });

  test(
    'splits confirmed takings across the recorded payment methods',
    () async {
      await _confirm(
        outbox,
        'checkout-cash-a',
        totalMinor: 25000,
        tender: 'cash',
      );
      await _confirm(
        outbox,
        'checkout-cash-b',
        totalMinor: 500,
        tender: 'cash',
      );
      await _confirm(
        outbox,
        'checkout-mpesa',
        totalMinor: 15500,
        tender: 'mpesa',
      );
      await _confirm(outbox, 'checkout-card', totalMinor: 9000, tender: 'card');

      final summary = await ledger.summarize(
        uid: 'user-a',
        tenantId: 'tenant-a',
        shiftId: 'shift-a',
      );
      final split = summary.tenders;

      expect(split.cash.totalMinor, 25500);
      expect(split.cash.transactionCount, 2);
      expect(split.bucket(CheckoutTender.mpesa).totalMinor, 15500);
      expect(split.bucket(CheckoutTender.mpesa).transactionCount, 1);
      expect(split.bucket(CheckoutTender.card).totalMinor, 9000);
      expect(split.unattributed.isEmpty, isTrue);
      expect(split.hasRecordedTenders, isTrue);
      // The buckets are filled from the same validated figure, in the same pass
      // that grows the total, so they add up by construction and not by two
      // implementations staying in step.
      expect(summary.tendersDescribeTakings, isTrue);
      expect(split.totalMinor, summary.totalMinor);
      expect(split.transactionCount, summary.transactionCount);
    },
  );

  test('an absent and a stored null tender are the same fact', () async {
    // A sale written before payment methods were captured. Both spellings of
    // "nothing was recorded" must reach the one bucket that says so, exactly as
    // the server's `saleTenderBucket` treats undefined and null alike.
    await _confirm(outbox, 'checkout-legacy', totalMinor: 4000);
    await _confirm(outbox, 'checkout-null', totalMinor: 1000, tender: null);

    final summary = await ledger.summarize(
      uid: 'user-a',
      tenantId: 'tenant-a',
      shiftId: 'shift-a',
    );

    expect(summary.tenders.unrecorded.totalMinor, 5000);
    expect(summary.tenders.unrecorded.transactionCount, 2);
    expect(summary.tenders.unrecognised.isEmpty, isTrue);
    expect(summary.tenders.cash.isEmpty, isTrue);
    expect(summary.tenders.hasRecordedTenders, isFalse);
    expect(summary.tendersDescribeTakings, isTrue);
  });

  test(
    'an unmodelled tender is bucketed rather than failing the close',
    () async {
      // The same near misses the server's bucketing is pinned against. None of
      // them may be coerced into `cash`, and none of them may deny a cashier the
      // close of a shift whose total is perfectly well known.
      const unmodelled = <Object?>[
        'Cash',
        ' cash',
        'CASH',
        'cheque',
        '',
        7,
        true,
        <String, Object?>{'kind': 'cash'},
        <Object?>['cash'],
      ];
      for (var index = 0; index < unmodelled.length; index++) {
        await _confirm(
          outbox,
          'checkout-odd-$index',
          totalMinor: 100,
          tender: unmodelled[index],
        );
      }
      await _confirm(outbox, 'checkout-cash', totalMinor: 2500, tender: 'cash');

      final summary = await ledger.summarize(
        uid: 'user-a',
        tenantId: 'tenant-a',
        shiftId: 'shift-a',
      );

      expect(summary.isComplete, isTrue);
      expect(summary.tenders.unrecognised.transactionCount, unmodelled.length);
      expect(summary.tenders.unrecognised.totalMinor, 100 * unmodelled.length);
      expect(summary.tenders.unrecorded.isEmpty, isTrue);
      expect(summary.tenders.cash.totalMinor, 2500);
      // Their money is still inside the shift total, which is the whole reason
      // bucketing them is safe.
      expect(summary.tendersDescribeTakings, isTrue);
    },
  );

  test('unattributed takings combine both unaccountable buckets', () async {
    await _confirm(outbox, 'checkout-legacy', totalMinor: 4000);
    await _confirm(outbox, 'checkout-odd', totalMinor: 600, tender: 'cheque');
    await _confirm(outbox, 'checkout-cash', totalMinor: 1000, tender: 'cash');

    final summary = await ledger.summarize(
      uid: 'user-a',
      tenantId: 'tenant-a',
      shiftId: 'shift-a',
    );

    expect(summary.tenders.unattributed.totalMinor, 4600);
    expect(summary.tenders.unattributed.transactionCount, 2);
    // Expected cash is only what was proved to be cash.
    expect(summary.tenders.cash.totalMinor, 1000);
  });

  test(
    'an unconfirmed sale is outside the split as well as the total',
    () async {
      await _confirm(outbox, 'checkout-cash', totalMinor: 2500, tender: 'cash');
      await _save(outbox, 'checkout-queued', totalMinor: 9999, tender: 'cash');

      final summary = await ledger.summarize(
        uid: 'user-a',
        tenantId: 'tenant-a',
        shiftId: 'shift-a',
      );

      expect(summary.isComplete, isFalse);
      expect(summary.tenders.cash.totalMinor, 2500);
      expect(summary.tenders.cash.transactionCount, 1);
      // The split describes exactly the sales the total covers, so an incomplete
      // shift has an incomplete split for the same reason - and still adds up.
      expect(summary.tendersDescribeTakings, isTrue);
    },
  );

  test('another shift and another business never reach the split', () async {
    await _confirm(outbox, 'checkout-cash', totalMinor: 2500, tender: 'cash');
    await _confirm(
      outbox,
      'checkout-other-shift',
      totalMinor: 90000,
      tender: 'cash',
      shiftId: 'shift-b',
    );
    await _confirm(
      outbox,
      'checkout-other-tenant',
      totalMinor: 90000,
      tender: 'cash',
      tenantId: 'tenant-b',
    );

    final summary = await ledger.summarize(
      uid: 'user-a',
      tenantId: 'tenant-a',
      shiftId: 'shift-a',
    );

    expect(summary.tenders.cash.totalMinor, 2500);
    expect(summary.tenders.cash.transactionCount, 1);
  });

  test('an empty shift reports an empty split that still adds up', () async {
    final summary = await ledger.summarize(
      uid: 'user-a',
      tenantId: 'tenant-a',
      shiftId: 'shift-a',
    );

    expect(summary.tenders.cash.isEmpty, isTrue);
    expect(summary.tenders.hasRecordedTenders, isFalse);
    expect(summary.tenders.unattributed.isEmpty, isTrue);
    expect(summary.tendersDescribeTakings, isTrue);
  });

  test('a missing bucket reads as nothing taken that way', () async {
    // Nothing the ledger builds omits a bucket, but a split is a public value
    // and the one screen that reads it closes a till. An absent entry must be
    // an empty bucket, never a crash.
    const split = ShiftTenderSplit(
      recorded: <CheckoutTender, ShiftTenderTotals>{
        CheckoutTender.mpesa: ShiftTenderTotals(
          totalMinor: 700,
          transactionCount: 1,
        ),
      },
    );

    expect(split.cash.isEmpty, isTrue);
    expect(split.cash.totalMinor, 0);
    expect(split.bucket(CheckoutTender.card).isEmpty, isTrue);
    expect(split.totalMinor, 700);
    expect(split.transactionCount, 1);
  });

  test('a split that does not add up is reported as such', () async {
    // The check exists for splits this ledger did not build. One that claims
    // less than the shift took would understate a drawer.
    const summary = ShiftSalesSummary(
      transactionCount: 2,
      totalMinor: 5000,
      unsettledCount: 0,
      tenders: ShiftTenderSplit(
        recorded: <CheckoutTender, ShiftTenderTotals>{
          CheckoutTender.cash: ShiftTenderTotals(
            totalMinor: 4000,
            transactionCount: 1,
          ),
        },
      ),
    );

    expect(summary.tendersDescribeTakings, isFalse);
  });

  test('a credit sale puts only what was paid in the drawer', () async {
    await _confirm(outbox, 'checkout-cash', totalMinor: 10000, tender: 'cash');
    await _confirm(
      outbox,
      'checkout-credit',
      totalMinor: 25000,
      tender: 'credit',
      extra: const <String, Object?>{
        'customerId': 'cu_0123456789abcdef0123456789abcdef01234567',
        'customerName': 'Jane',
        'creditOwedMinor': 15000,
        'creditPaidTender': 'mpesa',
      },
    );

    final summary = await ledger.summarize(
      uid: 'user-a',
      tenantId: 'tenant-a',
      shiftId: 'shift-a',
    );

    expect(summary.totalMinor, 35000);
    expect(summary.creditOwedMinor, 15000);
    expect(summary.drawerMinor, 20000);
    expect(summary.tenders.recorded[CheckoutTender.mpesa]!.totalMinor, 10000);
    expect(summary.tenders.unrecognised.totalMinor, 15000);
    // The split still describes exactly the takings the shift reports.
    expect(summary.tendersDescribeTakings, isTrue);
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

    final summary = await CheckoutOutboxShiftSalesLedger(
      reopened,
    ).summarize(uid: 'user-a', tenantId: 'tenant-a', shiftId: 'shift-a');
    expect(summary.transactionCount, 1);
    expect(summary.totalMinor, 25000);
  });
}

final List<int> _encryptionKey = List<int>.generate(
  HiveCheckoutOutbox.encryptionKeyBytes,
  (index) => (index * 7) % 256,
);

/// Distinguishes "the payload carries no tender key" from "it stores null".
/// The ledger must treat them alike, which cannot be tested unless a fixture
/// can express both.
const Object _absentTender = Object();

Future<CheckoutOutboxRecord> _save(
  HiveCheckoutOutbox outbox,
  String checkoutId, {
  required int totalMinor,
  String uid = 'user-a',
  String tenantId = 'tenant-a',
  String shiftId = 'shift-a',
  Object? tender = _absentTender,
  Map<String, Object?> extra = const <String, Object?>{},
}) => outbox.saveOffline(
  uid: uid,
  tenantId: tenantId,
  checkoutId: checkoutId,
  payload: <String, Object?>{
    ..._payload(
      checkoutId,
      totalMinor: totalMinor,
      uid: uid,
      tenantId: tenantId,
      shiftId: shiftId,
      tender: tender,
    ),
    ...extra,
  },
);

/// Walks one checkout through the frozen state machine to `confirmed`.
Future<void> _confirm(
  HiveCheckoutOutbox outbox,
  String checkoutId, {
  required int totalMinor,
  String uid = 'user-a',
  String tenantId = 'tenant-a',
  String shiftId = 'shift-a',
  Object? tender = _absentTender,
  Map<String, Object?> extra = const <String, Object?>{},
}) async {
  final record = await _save(
    outbox,
    checkoutId,
    totalMinor: totalMinor,
    uid: uid,
    tenantId: tenantId,
    shiftId: shiftId,
    tender: tender,
    extra: extra,
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
  Object? tender = _absentTender,
}) => <String, Object?>{
  if (!identical(tender, _absentTender)) 'tender': tender,
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
