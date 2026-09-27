import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:uzapay_pos/checkout/checkout_outbox.dart';
import 'package:uzapay_pos/checkout/checkout_receipt.dart';
import 'package:uzapay_pos/checkout/checkout_sale.dart';
import 'package:uzapay_pos/checkout/checkout_stranded_drain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const String _deviceId = 'dev-0123456789abcdef0123456789abcdef';

/// Handing over sales a cashier rang up before their access ended.
///
/// **Why this exists.** A sale is durable in the device's own outbox before it
/// reaches the server. If the membership is deactivated while sales are still
/// sitting there, both workers stop and `allow create` refuses the write in any
/// case - so the money was taken and the only record is on a phone nobody can
/// act through. The device finds out it has been deactivated by asking, and
/// that ask is online, which is the window this uses.
void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveCheckoutOutbox outbox;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('stranded-drain-test-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>(
      'stranded-drain-test',
      encryptionCipher: HiveAesCipher(_encryptionKey),
      crashRecovery: false,
    );
    outbox = HiveCheckoutOutbox.fromBox(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('hands over every sale that never reached the server', () async {
    await _save(outbox, 'co-1');
    await _save(outbox, 'co-2');
    final callable = _FakeCallable(
      response: <String, Object?>{
        'drained': <String>['co-1', 'co-2'],
        'alreadyPresent': <String>[],
      },
    );

    final result = await _drainer(
      outbox,
      callable,
    ).drain(uid: 'user-a', tenantId: 'tenant-a');

    expect(result.handedOver, 2);
    expect(result.settledAnything, isTrue);
    expect(callable.payloads.single['tenantId'], 'tenant-a');
    final sales = callable.payloads.single['sales']! as List<Object?>;
    expect(sales, hasLength(2));
    // The server is handed the sale document the ordinary submission would
    // have written, so nothing about a drained sale is shaped differently from
    // one that went the usual way.
    final first = sales.first! as Map<String, Object?>;
    expect(first['checkoutId'], 'co-1');
    expect(first['soldById'], 'user-a');
    expect(first['payloadHash'], isA<String>());
    expect(first['clientCreatedAtMs'], isA<int>());
  });

  test('a sale already sent is left for the ordinary confirmation', () async {
    // **`submitting` may already be on the server.** Handing it over again
    // would be claiming to know something this device cannot; the confirmation
    // pass is what settles those, and it is unaffected by any of this.
    final record = await _save(outbox, 'co-1');
    await outbox.beginSubmission(
      uid: record.uid,
      tenantId: record.tenantId,
      checkoutId: record.checkoutId,
      leaseOwner: 'worker-a',
      leaseDuration: const Duration(minutes: 5),
    );
    final callable = _FakeCallable();

    final result = await _drainer(
      outbox,
      callable,
    ).drain(uid: 'user-a', tenantId: 'tenant-a');

    expect(result.attempted, isFalse);
    expect(callable.payloads, isEmpty);
  });

  test('nothing to hand over reaches the server not at all', () async {
    final callable = _FakeCallable();

    final result = await _drainer(
      outbox,
      callable,
    ).drain(uid: 'user-a', tenantId: 'tenant-a');

    expect(result.attempted, isFalse);
    expect(result.handedOver, 0);
    expect(callable.payloads, isEmpty);
  });

  test('a record this device cannot read is left where it is', () async {
    // It is still the only copy of that sale. A payload that will not parse is
    // a question for somebody holding the device, not something to push.
    await outbox.saveOffline(
      uid: 'user-a',
      tenantId: 'tenant-a',
      checkoutId: 'malformed',
      payload: const <String, Object?>{'schemaVersion': 1},
    );
    final callable = _FakeCallable();

    final result = await _drainer(
      outbox,
      callable,
    ).drain(uid: 'user-a', tenantId: 'tenant-a');

    expect(result.unreadable, 1);
    expect(result.handedOver, 0);
    expect(callable.payloads, isEmpty);
  });

  test('a refusal settles nothing and loses nothing', () async {
    await _save(outbox, 'co-1');
    final callable = _FakeCallable(
      failure: FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'too long ago',
      ),
    );

    final result = await _drainer(
      outbox,
      callable,
    ).drain(uid: 'user-a', tenantId: 'tenant-a');

    expect(result.attempted, isTrue);
    expect(result.handedOver, 0);
    expect(result.settledAnything, isFalse);
    // The record is untouched, so a later attempt - or a restored membership -
    // still finds it.
    final kept = await outbox.recordsForSession(
      uid: 'user-a',
      tenantId: 'tenant-a',
    );
    expect(kept, hasLength(1));
    expect(kept.single.state, CheckoutOutboxState.savedOffline);
  });

  test('sales the server already held are reported, not counted', () async {
    await _save(outbox, 'co-1');
    final callable = _FakeCallable(
      response: <String, Object?>{
        'drained': <String>[],
        'alreadyPresent': <String>['co-1'],
      },
    );

    final result = await _drainer(
      outbox,
      callable,
    ).drain(uid: 'user-a', tenantId: 'tenant-a');

    expect(result.handedOver, 0);
    expect(result.alreadyPresent, 1);
    expect(result.settledAnything, isFalse);
  });
}

CheckoutStrandedSalesDrainer _drainer(
  HiveCheckoutOutbox outbox,
  DrainStrandedSalesCallable callable,
) => CheckoutStrandedSalesDrainer(
  outbox: outbox,
  callable: callable,
  requestIdFactory: () => 'drain-stranded-fixed-value',
);

final class _FakeCallable implements DrainStrandedSalesCallable {
  _FakeCallable({this.response, this.failure});

  final Object? response;
  final Object? failure;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    final error = failure;
    if (error != null) throw error;
    return response;
  }
}

final List<int> _encryptionKey = List<int>.generate(
  HiveCheckoutOutbox.encryptionKeyBytes,
  (index) => (index * 7) % 256,
);

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
    'tender': 'cash',
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
