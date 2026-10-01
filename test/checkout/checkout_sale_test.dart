import 'dart:io';

import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late HiveCheckoutOutbox outbox;
  late TenantSession session;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sale-payload-test-');
    Hive.init(directory.path);
    final box = await Hive.openBox<dynamic>('sale-payload-test');
    outbox = HiveCheckoutOutbox.fromBox(
      box,
      clock: () => DateTime.utc(2026, 7, 31, 9),
    );
    session = _session();
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('derives the exact tenant write set from a frozen payload', () async {
    final record = await _save(outbox, _payload(discountMinor: 5000));

    final payload = CheckoutSalePayload.fromOutboxRecord(
      record,
      session: session,
    );
    final submission = payload.toSubmission();

    expect(payload.totalMinor, 60000);
    expect(submission.salePath, 'tenants/tenant-a/sales/checkout-a');
    expect(submission.saleServerTimestampFields, <String>['createdAt']);
    expect(submission.stockServerTimestampFields, <String>['updatedAt']);
    expect(
      submission.stockDecrements
          .map((decrement) => (decrement.productPath, decrement.quantityDelta))
          .toList(),
      [
        ('tenants/tenant-a/products/product-a', -2),
        ('tenants/tenant-a/products/product-b', -1),
      ],
    );

    final fields = submission.saleFields;
    expect(fields['checkoutId'], 'checkout-a');
    expect(fields['tenantId'], 'tenant-a');
    expect(fields['soldById'], 'user-a');
    expect(fields['payloadHash'], record.payloadHash);
    expect(payload.schemaVersion, 2);
    expect(fields['payloadSchemaVersion'], 2);
    expect(payload.tender, CheckoutTender.cash);
    expect(fields['tender'], 'cash');
    expect(fields['businessDate'], '2026-07-31');
    expect(payload.shiftId, 'shift-a');
    expect(fields['shiftId'], 'shift-a');
    expect(fields['currency'], 'KES');
    expect(fields.containsKey('createdAt'), isFalse);
    expect((fields['subtotalMinor'], fields['subtotal']), (65000, 650.0));
    expect((fields['discountMinor'], fields['discount']), (5000, 50.0));
    // A discount with no reason predates the reason, and still commits.
    expect(payload.discountReason, isNull);
    expect(fields.containsKey('discountReason'), isFalse);
    expect((fields['totalMinor'], fields['total']), (60000, 600.0));

    final items = fields['items']! as List<Object?>;
    final first = items.first! as Map<String, Object?>;
    expect(first['productId'], 'product-a');
    expect(first['quantity'], 2);
    expect((first['unitPriceMinor'], first['unitPrice']), (25000, 250.0));
    expect((first['lineTotalMinor'], first['lineTotal']), (50000, 500.0));
    expect((first['unitCostMinor'], first['unitCost']), (12000, 120.0));
    expect((first['costMinor'], first['cost']), (24000, 240.0));
    expect((items[1]! as Map<String, Object?>).containsKey('cost'), isFalse);
  });

  test('accepts the maximum supported line count', () async {
    final record = await _save(
      outbox,
      _payload(
        items: [
          for (var index = 0; index < 16; index++)
            _line(productId: 'product-$index', quantity: index + 1),
        ],
      ),
    );

    final payload = CheckoutSalePayload.fromOutboxRecord(
      record,
      session: session,
    );

    expect(payload.lines.length, maximumCheckoutSaleLines);
    expect(payload.subtotalMinor, 100 * (16 * 17) ~/ 2);
  });

  test('rejects a payload that claims another identity', () async {
    final cases = <String, Map<String, Object?>>{
      'checkout': _payload(overrides: {'checkoutId': 'other-checkout'}),
      'tenant': _payload(overrides: {'tenantId': 'tenant-b'}),
      'cashier': _payload(overrides: {'soldById': 'user-b'}),
      'future-version': _payload(overrides: {'schemaVersion': 3}),
      'zero-version': _payload(overrides: {'schemaVersion': 0}),
      'string-version': _payload(overrides: {'schemaVersion': '2'}),
      'missing-version': _payload(overrides: {'schemaVersion': null}),
      'unknown-field': _payload(overrides: {'note': 'extra'}),
    };

    for (final entry in cases.entries) {
      final record = await _save(
        outbox,
        entry.value,
        checkoutId: 'checkout-${entry.key}',
      );
      expect(
        () => CheckoutSalePayload.fromOutboxRecord(record, session: session),
        _throwsSaleFormat,
        reason: entry.key,
      );
    }
  });

  test('rejects a session that does not own the stored checkout', () async {
    final record = await _save(outbox, _payload());

    expect(
      () => CheckoutSalePayload.fromOutboxRecord(
        record,
        session: _session(tenantId: 'tenant-b'),
      ),
      _throwsSaleFormat,
    );
    expect(
      () => CheckoutSalePayload.fromOutboxRecord(
        record,
        session: _session(uid: 'user-b'),
      ),
      _throwsSaleFormat,
    );
  });

  test('rejects malformed, duplicated, and unbounded sale lines', () async {
    final cases = <String, List<Object?>>{
      'empty': <Object?>[],
      'overflow': <Object?>[
        for (var index = 0; index < 17; index++)
          _line(productId: 'product-$index'),
      ],
      'duplicate': <Object?>[_line(), _line()],
      'not-a-map': <Object?>['product-a'],
      'zero-quantity': <Object?>[_line(quantity: 0)],
      'negative-quantity': <Object?>[_line(quantity: -1)],
      'fractional-quantity': <Object?>[
        _line(overrides: {'quantity': 1.5}),
      ],
      'string-quantity': <Object?>[
        _line(overrides: {'quantity': '1'}),
      ],
      'negative-price': <Object?>[
        _line(overrides: {'unitPriceMinor': -1}),
      ],
      'fractional-price': <Object?>[
        _line(overrides: {'unitPriceMinor': 1.5}),
      ],
      'missing-name': <Object?>[
        _line(overrides: {'name': null}),
      ],
      'path-product': <Object?>[_line(productId: 'products/product-a')],
      'unknown-line-field': <Object?>[
        _line(overrides: {'discount': 1}),
      ],
    };

    for (final entry in cases.entries) {
      final record = await _save(
        outbox,
        _payload(items: entry.value),
        checkoutId: 'checkout-${entry.key}',
      );
      expect(
        () => CheckoutSalePayload.fromOutboxRecord(record, session: session),
        _throwsSaleFormat,
        reason: entry.key,
      );
    }
  });

  test('rejects an inconsistent monetary snapshot', () async {
    final cases = <String, Map<String, Object?>>{
      'subtotal': _payload(overrides: {'subtotalMinor': 64000}),
      'total': _payload(overrides: {'totalMinor': 64000}),
      'negative-discount': _payload(overrides: {'discountMinor': -1}),
      'excess-discount': _payload(discountMinor: 65001),
      'missing-total': _payload(overrides: {'totalMinor': null}),
    };

    for (final entry in cases.entries) {
      final record = await _save(
        outbox,
        entry.value,
        checkoutId: 'checkout-${entry.key}',
      );
      expect(
        () => CheckoutSalePayload.fromOutboxRecord(record, session: session),
        _throwsSaleFormat,
        reason: entry.key,
      );
    }
  });

  test('carries each line\'s code onto the sale, and none where absent', () async {
    final record = await _save(
      outbox,
      _payload(
        items: <Object?>[
          _line(overrides: <String, Object?>{'sku': '6161100000019'}),
          _line(productId: 'product-b', name: 'Tea'),
        ],
      ),
    );

    final payload = CheckoutSalePayload.fromOutboxRecord(
      record,
      session: session,
    );
    final items = payload.toSubmission().saleFields['items']! as List<Object?>;

    expect(payload.lines.first.sku, '6161100000019');
    expect((items.first! as Map<String, Object?>)['sku'], '6161100000019');
    expect(payload.lines.last.sku, isNull);
    expect((items.last! as Map<String, Object?>).containsKey('sku'), isFalse);
  });

  test('refuses a code the till would never have written', () async {
    final cases = <String, Object?>{
      'empty': '',
      'padded': ' 6161100000019',
      'control-character': '6161\n100',
      'numeric': 6161100000019,
    };

    for (final entry in cases.entries) {
      final record = await _save(
        outbox,
        _payload(
          items: <Object?>[
            _line(overrides: <String, Object?>{'sku': entry.value}),
          ],
        ),
        checkoutId: 'checkout-sku-${entry.key}',
      );
      expect(
        () => CheckoutSalePayload.fromOutboxRecord(record, session: session),
        _throwsSaleFormat,
        reason: entry.key,
      );
    }
  });

  test('carries why a price was agreed onto the sale', () async {
    final record = await _save(
      outbox,
      _payload(
        discountMinor: 5000,
        overrides: {'discountReason': 'Bought two'},
      ),
    );

    final payload = CheckoutSalePayload.fromOutboxRecord(
      record,
      session: session,
    );

    expect(payload.discountReason, 'Bought two');
    expect(payload.toSubmission().saleFields['discountReason'], 'Bought two');
  });

  test('refuses a reason the till would never have written', () async {
    final cases = <String, Map<String, Object?>>{
      'nothing-off': _payload(overrides: {'discountReason': 'Bought two'}),
      'empty': _payload(
        discountMinor: 5000,
        overrides: {'discountReason': ''},
      ),
      'padded': _payload(
        discountMinor: 5000,
        overrides: {'discountReason': ' Bought two'},
      ),
      'too-short': _payload(
        discountMinor: 5000,
        overrides: {'discountReason': 'ok'},
      ),
      'too-long': _payload(
        discountMinor: 5000,
        overrides: {
          'discountReason': 'x' * (maximumCheckoutDiscountReasonLength + 1),
        },
      ),
      'control-character': _payload(
        discountMinor: 5000,
        overrides: {'discountReason': 'Bought\ntwo'},
      ),
      'numeric': _payload(
        discountMinor: 5000,
        overrides: {'discountReason': 7},
      ),
      'null': _payload(
        discountMinor: 5000,
        overrides: {'discountReason': null},
      ),
    };

    for (final entry in cases.entries) {
      final record = await _save(
        outbox,
        entry.value,
        checkoutId: 'checkout-${entry.key}',
      );
      expect(
        () => CheckoutSalePayload.fromOutboxRecord(record, session: session),
        _throwsSaleFormat,
        reason: entry.key,
      );
    }
  });

  group('the customer a sale was for', () {
    const customerId = 'cu_0123456789abcdef0123456789abcdef01234567';

    test('is frozen onto the sale, KRA PIN and all', () async {
      final record = await _save(
        outbox,
        _payload(
          overrides: {
            'customerId': customerId,
            'customerName': 'Jane Wanjiku',
            'customerKraPin': 'A012345678Z',
          },
        ),
      );

      final payload = CheckoutSalePayload.fromOutboxRecord(
        record,
        session: session,
      );
      final fields = payload.toSubmission().saleFields;

      expect(
        payload.customer,
        const CheckoutSaleCustomer(
          id: customerId,
          name: 'Jane Wanjiku',
          kraPin: 'A012345678Z',
        ),
      );
      expect(fields['customerId'], customerId);
      expect(fields['customerName'], 'Jane Wanjiku');
      expect(fields['customerKraPin'], 'A012345678Z');
    });

    // **What every earlier build writes.** A walk-in names nobody, so the sale
    // a 1.0.9 till sends and the walk-in sale this one sends are the same shape.
    test('is absent on a walk-in, which writes what older tills write', () async {
      final record = await _save(outbox, _payload());

      final payload = CheckoutSalePayload.fromOutboxRecord(
        record,
        session: session,
      );
      final fields = payload.toSubmission().saleFields;

      expect(payload.customer, isNull);
      for (final key in <String>['customerId', 'customerName', 'customerKraPin']) {
        expect(fields.containsKey(key), isFalse, reason: key);
      }
    });

    test('is refused when the till could not have chosen it', () async {
      final cases = <String, Map<String, Object?>>{
        'name-only': _payload(overrides: {'customerName': 'Jane'}),
        'id-only': _payload(overrides: {'customerId': customerId}),
        'foreign-id': _payload(
          overrides: {'customerId': 'sp_abc', 'customerName': 'Jane'},
        ),
        'bad-pin': _payload(
          overrides: {
            'customerId': customerId,
            'customerName': 'Jane',
            'customerKraPin': 'a0123',
          },
        ),
      };
      for (final entry in cases.entries) {
        final record = await _save(
          outbox,
          entry.value,
          checkoutId: 'checkout-customer-${entry.key}',
        );
        expect(
          () => CheckoutSalePayload.fromOutboxRecord(record, session: session),
          _throwsSaleFormat,
          reason: entry.key,
        );
      }
    });
  });

  test('rejects malformed envelope metadata', () async {
    final cases = <String, Map<String, Object?>>{
      'currency': _payload(overrides: {'currency': 'kes'}),
      'business-date-format': _payload(
        overrides: {'businessDate': '31-07-2026'},
      ),
      'business-date-calendar': _payload(
        overrides: {'businessDate': '2026-02-30'},
      ),
      'created-at': _payload(overrides: {'createdAtMs': 0}),
      'shift': _payload(overrides: {'shiftId': 'shifts/shift-a'}),
      // Every sale must name the shift reconciliation will aggregate it into.
      'missing-shift': _payload(overrides: {'shiftId': null}),
      'empty-shift': _payload(overrides: {'shiftId': ''}),
      'numeric-shift': _payload(overrides: {'shiftId': 7}),
      'device': _payload(overrides: {'deviceId': ''}),
      'missing-device': _payload(overrides: {'deviceId': null}),
      'foreign-device-id': _payload(overrides: {'deviceId': 'workstation-1'}),
    };

    for (final entry in cases.entries) {
      final record = await _save(
        outbox,
        entry.value,
        checkoutId: 'checkout-${entry.key}',
      );
      expect(
        () => CheckoutSalePayload.fromOutboxRecord(record, session: session),
        _throwsSaleFormat,
        reason: entry.key,
      );
    }
  });

  test(
    'records each modelled tender exactly as the cashier chose it',
    () async {
      for (final tender in CheckoutTender.values) {
        final record = await _save(
          outbox,
          _payload(tender: tender.wireValue),
          checkoutId: 'checkout-${tender.wireValue}',
        );

        final payload = CheckoutSalePayload.fromOutboxRecord(
          record,
          session: session,
        );

        expect(payload.tender, tender, reason: tender.wireValue);
        expect(
          payload.toSubmission().saleFields['tender'],
          tender.wireValue,
          reason: tender.wireValue,
        );
      }
    },
  );

  test('reads a v2 payload with no tender as an unanswered question', () async {
    // **Absent is not malformed.** A cashier may save without saying how the
    // customer paid, and the sale records that rather than guessing or
    // refusing. What is still refused is a tender key that is *present* and
    // names something unmodelled - see the case below, including an explicit
    // null, which is a corrupt value rather than a silence.
    final record = await _save(
      outbox,
      _payload(tender: null),
      checkoutId: 'checkout-tender-unanswered',
    );

    final payload = CheckoutSalePayload.fromOutboxRecord(
      record,
      session: session,
    );

    expect(payload.tender, isNull);
    expect(payload.schemaVersion, checkoutSalePayloadSchemaVersion);
  });

  test('refuses a v2 payload whose tender names no modelled method', () async {
    final cases = <String, Map<String, Object?>>{
      'empty': _payload(tender: ''),
      'null': _payload(overrides: {'tender': null}),
      'capitalised': _payload(tender: 'Cash'),
      'padded': _payload(tender: ' cash'),
      'unmodelled': _payload(tender: 'cheque'),
      // A tender integration would be a separate ticket, not a value nobody
      // agreed to arriving through the payload.
      'bank-transfer': _payload(tender: 'bank_transfer'),
      'numeric': _payload(overrides: {'tender': 1}),
      'boolean': _payload(overrides: {'tender': true}),
      'list': _payload(
        overrides: {
          'tender': <Object?>['cash'],
        },
      ),
      'map': _payload(
        overrides: {
          'tender': <String, Object?>{'method': 'cash'},
        },
      ),
    };

    for (final entry in cases.entries) {
      final record = await _save(
        outbox,
        entry.value,
        checkoutId: 'checkout-tender-${entry.key}',
      );
      expect(
        () => CheckoutSalePayload.fromOutboxRecord(record, session: session),
        _throwsSaleFormat,
        reason: entry.key,
      );
    }
  });

  // #105: v1 stayed supported so a device holding a draft saved before the
  // upgrade could still submit it - the hash covers the whole payload, so a
  // migrated draft would no longer match the server sale an
  // awaiting-confirmation record waits on. SIT clears app data instead, so
  // there is no such draft to strand and one contract to check against.
  test('refuses a v1 draft, with or without a tender', () async {
    for (final tender in <String?>[null, 'cash']) {
      final record = await _save(
        outbox,
        _payload(schemaVersion: 1, tender: tender),
        checkoutId: 'checkout-legacy-${tender ?? 'none'}',
      );

      expect(
        () => CheckoutSalePayload.fromOutboxRecord(record, session: session),
        _throwsSaleFormat,
        reason: 'schema v1 is no longer a contract this build accepts',
      );
    }
  });

  test(
    'accepts a receipt derived from this device, date, and sequence',
    () async {
      final record = await _save(outbox, _payload(sequence: 42));

      final payload = CheckoutSalePayload.fromOutboxRecord(
        record,
        session: session,
      );

      expect(payload.deviceId, _deviceId);
      expect(payload.receiptSequence, 42);
      expect(payload.receiptNumber, matches(checkoutReceiptNumberPattern));
      expect(payload.receiptNumber.split('-')[2], '20260731');
      expect(payload.receiptNumber.split('-')[3], '0042');

      final fields = payload.toSubmission().saleFields;
      expect(fields['receiptNumber'], payload.receiptNumber);
      expect(fields['receiptSequence'], 42);
      expect(fields['deviceId'], _deviceId);
    },
  );

  test('rejects a spoofed or missing receipt number', () async {
    final valid = formatCheckoutReceiptNumber(
      deviceId: _deviceId,
      businessDate: '2026-07-31',
      sequence: 42,
    );
    final cases = <String, Map<String, Object?>>{
      'missing': _payload(overrides: {'receiptNumber': null}),
      'missing-sequence': _payload(overrides: {'receiptSequence': null}),
      'shape': _payload(overrides: {'receiptNumber': 'CT-42'}),
      'lowercase-device-code': _payload(
        overrides: {'receiptNumber': valid.toLowerCase()},
      ),
      'other-device': _payload(
        overrides: {
          'receiptNumber': formatCheckoutReceiptNumber(
            deviceId: _otherDeviceId,
            businessDate: '2026-07-31',
            sequence: 42,
          ),
        },
      ),
      'other-date': _payload(
        overrides: {
          'receiptNumber': formatCheckoutReceiptNumber(
            deviceId: _deviceId,
            businessDate: '2026-07-30',
            sequence: 42,
          ),
        },
      ),
      'other-sequence': _payload(
        overrides: {
          'receiptNumber': formatCheckoutReceiptNumber(
            deviceId: _deviceId,
            businessDate: '2026-07-31',
            sequence: 43,
          ),
        },
      ),
      'zero-sequence': _payload(
        sequence: 42,
        overrides: {'receiptSequence': 0},
      ),
      'fractional-sequence': _payload(overrides: {'receiptSequence': 1.5}),
      'unbounded-sequence': _payload(
        overrides: {'receiptSequence': maximumCheckoutReceiptSequence + 1},
      ),
    };

    for (final entry in cases.entries) {
      final record = await _save(
        outbox,
        entry.value,
        checkoutId: 'checkout-${entry.key}',
      );
      expect(
        () => CheckoutSalePayload.fromOutboxRecord(record, session: session),
        _throwsSaleFormat,
        reason: entry.key,
      );
    }
  });
}

final Matcher _throwsSaleFormat = throwsA(isA<CheckoutSaleFormatException>());

Future<CheckoutOutboxRecord> _save(
  HiveCheckoutOutbox outbox,
  Map<String, Object?> payload, {
  String checkoutId = 'checkout-a',
  String uid = 'user-a',
  String tenantId = 'tenant-a',
}) => outbox.saveOffline(
  uid: uid,
  tenantId: tenantId,
  checkoutId: checkoutId,
  payload: <String, Object?>{
    ...payload,
    if (payload['checkoutId'] == 'checkout-a') 'checkoutId': checkoutId,
  },
);

Map<String, Object?> _line({
  String productId = 'product-a',
  String name = 'Coffee',
  String? categoryId,
  int quantity = 1,
  int unitPriceMinor = 100,
  int? unitCostMinor,
  Map<String, Object?> overrides = const <String, Object?>{},
}) => <String, Object?>{
  'productId': productId,
  'name': name,
  if (categoryId != null) 'categoryId': categoryId,
  'quantity': quantity,
  'unitPriceMinor': unitPriceMinor,
  if (unitCostMinor != null) 'unitCostMinor': unitCostMinor,
  ...overrides,
};

const String _deviceId = 'dev-0123456789abcdef0123456789abcdef';
const String _otherDeviceId = 'dev-fedcba9876543210fedcba9876543210';

Map<String, Object?> _payload({
  List<Object?>? items,
  int discountMinor = 0,
  String deviceId = _deviceId,
  int sequence = 42,
  int schemaVersion = checkoutSalePayloadSchemaVersion,
  Object? tender = 'cash',
  Map<String, Object?> overrides = const <String, Object?>{},
}) {
  final lines =
      items ??
      <Object?>[
        _line(
          productId: 'product-a',
          categoryId: 'drinks',
          quantity: 2,
          unitPriceMinor: 25000,
          unitCostMinor: 12000,
        ),
        _line(productId: 'product-b', name: 'Tea', unitPriceMinor: 15000),
      ];
  var subtotalMinor = 0;
  for (final line in lines) {
    if (line is! Map) continue;
    final quantity = line['quantity'];
    final unitPriceMinor = line['unitPriceMinor'];
    if (quantity is int && unitPriceMinor is int && quantity > 0) {
      subtotalMinor += quantity * unitPriceMinor;
    }
  }
  return <String, Object?>{
    'schemaVersion': schemaVersion,
    'checkoutId': 'checkout-a',
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'currency': 'KES',
    'businessDate': '2026-07-31',
    'createdAtMs': DateTime.utc(2026, 7, 31, 8).millisecondsSinceEpoch,
    'shiftId': 'shift-a',
    'deviceId': deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: deviceId,
      businessDate: '2026-07-31',
      sequence: sequence,
    ),
    'receiptSequence': sequence,
    if (tender != null) 'tender': tender,
    'items': lines,
    'subtotalMinor': subtotalMinor,
    'discountMinor': discountMinor,
    'totalMinor': subtotalMinor - discountMinor,
    ...overrides,
  };
}

TenantSession _session({String uid = 'user-a', String tenantId = 'tenant-a'}) =>
    TenantSession.active(
      uid: uid,
      tenantId: tenantId,
      role: TenantRole.cashier,
    );
