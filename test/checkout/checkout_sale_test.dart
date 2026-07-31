import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
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
    expect(fields['businessDate'], '2026-07-31');
    expect(payload.shiftId, 'shift-a');
    expect(fields['shiftId'], 'shift-a');
    expect(fields['currency'], 'KES');
    expect(fields.containsKey('createdAt'), isFalse);
    expect((fields['subtotalMinor'], fields['subtotal']), (65000, 650.0));
    expect((fields['discountMinor'], fields['discount']), (5000, 50.0));
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
      'version': _payload(overrides: {'schemaVersion': 2}),
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
      'fractional-quantity': <Object?>[_line(overrides: {'quantity': 1.5})],
      'string-quantity': <Object?>[_line(overrides: {'quantity': '1'})],
      'negative-price': <Object?>[_line(overrides: {'unitPriceMinor': -1})],
      'fractional-price': <Object?>[_line(overrides: {'unitPriceMinor': 1.5})],
      'missing-name': <Object?>[_line(overrides: {'name': null})],
      'path-product': <Object?>[_line(productId: 'products/product-a')],
      'unknown-line-field': <Object?>[_line(overrides: {'discount': 1})],
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

  test('rejects malformed envelope metadata', () async {
    final cases = <String, Map<String, Object?>>{
      'currency': _payload(overrides: {'currency': 'kes'}),
      'business-date-format': _payload(overrides: {'businessDate': '31-07-2026'}),
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

  test('accepts a receipt derived from this device, date, and sequence', () async {
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
  });

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
      'zero-sequence': _payload(sequence: 42, overrides: {'receiptSequence': 0}),
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
    'schemaVersion': checkoutSalePayloadSchemaVersion,
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
