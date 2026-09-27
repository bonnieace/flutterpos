import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uzapay_pos/checkout/checkout_receipt.dart';
import 'package:uzapay_pos/sales/sales.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';
const String _payloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  group('receipt query', () {
    test('parses the frozen receipt the issuing device produced', () {
      final receipt = _receipt(_deviceA, 42);
      final query = TenantReceiptQuery.parse(receipt);

      expect(query.receiptNumber, receipt);
      expect(query.deviceCode, checkoutReceiptDeviceCode(_deviceA));
      expect(query.businessDate, _businessDate);
      expect(query.sequence, 42);
    });

    test('normalizes surrounding space and case', () {
      final query = TenantReceiptQuery.parse(
        '  ${_receipt(_deviceA, 1).toLowerCase()} ',
      );

      expect(query.receiptNumber, _receipt(_deviceA, 1));
    });

    test('refuses anything that is not a receipt', () {
      for (final value in <String>[
        '',
        'CT',
        'CT-A7F-20260731',
        'XX-A7F-20260731-0042',
        'CT-A7-20260731-0042',
        'CT-AZF-20260731-0042',
        'CT-A7F-2026073-0042',
        'CT-A7F-20260731-042',
        // A well-shaped receipt naming a day that does not exist.
        'CT-A7F-20260231-0042',
        // The sequence starts at one; a zero sequence was never issued.
        'CT-A7F-20260731-0000',
      ]) {
        expect(
          () => TenantReceiptQuery.parse(value),
          _code('invalid_receipt_number'),
          reason: value,
        );
      }
    });
  });

  group('receipt ending query', () {
    test('accepts padded and unpadded daily sequences', () {
      for (final ending in <String>['42', '0042']) {
        final query = TenantReceiptEndingQuery.parse(
          businessDate: _businessDate,
          ending: ending,
          maximumBusinessDate: _businessDate,
        );

        expect(query.businessDate, _businessDate);
        expect(query.sequence, 42);
        expect(query.displayEnding, '0042');
      }
    });

    test('refuses invalid endings before a read can be built', () {
      for (final ending in <String>[
        '',
        'abc',
        '4a',
        '0',
        '000000',
        '1000000',
      ]) {
        expect(
          () => TenantReceiptEndingQuery.parse(
            businessDate: _businessDate,
            ending: ending,
          ),
          _code('invalid_receipt_ending'),
          reason: ending,
        );
      }
    });

    test('refuses malformed and future business dates', () {
      expect(
        () => TenantReceiptEndingQuery.parse(
          businessDate: '2026-02-31',
          ending: '42',
        ),
        _code('invalid_business_date'),
      );
      expect(
        () => TenantReceiptEndingQuery.parse(
          businessDate: '2026-08-01',
          ending: '42',
          maximumBusinessDate: _businessDate,
        ),
        _code('future_business_date'),
      );
    });
  });

  group('receipt lookup repository', () {
    test('finds the one sale that carries the receipt', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/sales/co-1': _sale(sequence: 1),
        'tenants/tenant-a/sales/co-2': _sale(saleId: 'co-2', sequence: 2),
      });

      final result = await _repository(
        reader,
      ).findByReceipt(_receipt(_deviceA, 2));

      expect(result.isFound, isTrue);
      expect(result.isMissing, isFalse);
      expect(result.isAmbiguous, isFalse);
      expect(result.sale.id, 'co-2');
      final query = reader.queries.single;
      expect(query.collectionPath, 'tenants/tenant-a/sales');
      expect(query.equalityFilters, <String, Object?>{
        'receiptNumber': _receipt(_deviceA, 2),
        'soldById': 'user-a',
      });
      expect(query.descending, isFalse);
    });

    test('a receipt with no sale is a first-class answer', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/sales/co-1': _sale(sequence: 1),
      });

      final result = await _repository(
        reader,
      ).findByReceipt(_receipt(_deviceA, 9));

      expect(result.isMissing, isTrue);
      expect(result.isFound, isFalse);
      expect(result.matches, isEmpty);
    });

    test(
      'two devices sharing a receipt code are reported, not resolved',
      () async {
        // The device code is a three-character digest, so a collision is real.
        // Picking one sale would attribute a return to the wrong till.
        final colliding = _collidingDeviceId();
        final reader = _Reader(<String, Map<String, Object?>>{
          'tenants/tenant-a/sales/co-1': _sale(sequence: 7),
          'tenants/tenant-a/sales/co-2': _sale(
            saleId: 'co-2',
            sequence: 7,
            deviceId: colliding,
          ),
        });

        final result = await _repository(
          reader,
        ).findByReceipt(_receipt(_deviceA, 7));

        expect(result.isAmbiguous, isTrue);
        expect(result.matches.length, 2);
        expect(() => result.sale, throwsStateError);
      },
    );

    test('a malformed receipt is refused before any read', () async {
      final reader = _Reader(const <String, Map<String, Object?>>{});

      await expectLater(
        _repository(reader).findByReceipt('not-a-receipt'),
        _code('invalid_receipt_number'),
      );
      expect(reader.queries, isEmpty);
    });

    test('every active role may look a receipt up', () async {
      for (final role in <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
        TenantRole.cashier,
      ]) {
        final reader = _Reader(<String, Map<String, Object?>>{
          'tenants/tenant-a/sales/co-1': _sale(sequence: 1),
        });
        final result = await _repository(
          reader,
          role: role,
        ).findByReceipt(_receipt(_deviceA, 1));
        expect(result.isFound, isTrue, reason: role.name);
      }
    });

    test('a sale whose receipt disagrees fails the lookup closed', () async {
      // The transport ignored the filter and answered with another sale.
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/sales/co-1': _sale(sequence: 1),
      }, ignoreFilters: true);

      await expectLater(
        _repository(reader).findByReceipt(_receipt(_deviceA, 5)),
        _code('receipt_mismatch'),
      );
    });

    test('a cross-tenant response fails closed', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/sales/co-1': _sale(sequence: 1),
      }, responsePath: 'tenants/tenant-b/sales/co-1');

      await expectLater(
        _repository(reader).findByReceipt(_receipt(_deviceA, 1)),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('daily ending lookup returns every matching till', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/sales/co-1': _sale(sequence: 42),
        'tenants/tenant-a/sales/co-2': _sale(
          saleId: 'co-2',
          sequence: 42,
          deviceId: 'dev-11111111111111111111111111111111',
        ),
      });

      final result = await _repository(
        reader,
        role: TenantRole.manager,
      ).findByEnding(businessDate: _businessDate, ending: '42');

      expect(result.isAmbiguous, isTrue);
      expect(result.query.displayEnding, '0042');
      expect(result.matches.map((sale) => sale.id), <String>['co-1', 'co-2']);
      expect(reader.queries.single.equalityFilters, <String, Object?>{
        'businessDate': _businessDate,
        'receiptSequence': 42,
      });
    });

    test(
      'a cashier ending lookup is always narrowed to its own sales',
      () async {
        final reader = _Reader(<String, Map<String, Object?>>{
          'tenants/tenant-a/sales/co-1': _sale(sequence: 42),
          'tenants/tenant-a/sales/co-2': _sale(
            saleId: 'co-2',
            sequence: 42,
            soldById: 'user-b',
          ),
        });

        final result = await _repository(reader).findByEnding(
          businessDate: _businessDate,
          ending: '0042',
          soldById: 'user-b',
        );

        expect(result.matches.map((sale) => sale.id), <String>['co-1']);
        expect(reader.queries.single.equalityFilters['soldById'], 'user-a');
      },
    );

    test('management may narrow an ending lookup to one member', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/sales/co-1': _sale(sequence: 42),
        'tenants/tenant-a/sales/co-2': _sale(
          saleId: 'co-2',
          sequence: 42,
          soldById: 'user-b',
        ),
      });

      final result = await _repository(reader, role: TenantRole.admin)
          .findByEnding(
            businessDate: _businessDate,
            ending: '0042',
            soldById: 'user-b',
          );

      expect(result.matches.map((sale) => sale.id), <String>['co-2']);
      expect(reader.queries.single.equalityFilters['soldById'], 'user-b');
    });

    test(
      'more than fifty ending collisions fail instead of truncating',
      () async {
        final reader = _Reader(<String, Map<String, Object?>>{
          for (var index = 0; index < 51; index++)
            'tenants/tenant-a/sales/co-$index': _sale(
              saleId: 'co-$index',
              sequence: 7,
              deviceId: 'dev-${index.toRadixString(16).padLeft(32, '0')}',
            ),
        });

        await expectLater(
          _repository(
            reader,
          ).findByEnding(businessDate: _businessDate, ending: '7'),
          _code('too_many_matches'),
        );
      },
    );
  });
}

TenantReceiptLookupRepository _repository(
  _Reader reader, {
  TenantRole role = TenantRole.cashier,
}) => TenantReceiptLookupRepository(
  session: TenantSession.active(
    uid: 'user-a',
    tenantId: 'tenant-a',
    role: role,
  ),
  reader: reader,
);

Matcher _code(String code) => throwsA(
  isA<TenantReceiptLookupException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

String _receipt(String deviceId, int sequence) => formatCheckoutReceiptNumber(
  deviceId: deviceId,
  businessDate: _businessDate,
  sequence: sequence,
);

/// Finds a second installation ID whose three-character code equals device A's.
///
/// The collision is a property of the frozen format, not a contrivance: three
/// hexadecimal characters leave 4096 codes for every device in the world.
String _collidingDeviceId() {
  final target = checkoutReceiptDeviceCode(_deviceA);
  for (var index = 0; index < 100000; index++) {
    final candidate = 'dev-${index.toRadixString(16).padLeft(32, '0')}';
    if (candidate != _deviceA &&
        checkoutReceiptDeviceCode(candidate) == target) {
      return candidate;
    }
  }
  throw StateError('No colliding device code was found.');
}

Map<String, Object?> _sale({
  String saleId = 'co-1',
  int sequence = 1,
  String deviceId = _deviceA,
  String soldById = 'user-a',
}) => <String, Object?>{
  'checkoutId': saleId,
  'tenantId': 'tenant-a',
  'soldById': soldById,
  'payloadHash': _payloadHash,
  'payloadSchemaVersion': 2,
  'currency': 'KES',
  'businessDate': _businessDate,
  'shiftId': 'shift-a',
  'deviceId': deviceId,
  'receiptNumber': _receipt(deviceId, sequence),
  'receiptSequence': sequence,
  'items': <Object?>[
    <String, Object?>{
      'productId': 'product-1',
      'name': 'Tusker',
      'quantity': 2,
      'unitPriceMinor': 500,
      'lineTotalMinor': 1000,
    },
  ],
  'subtotalMinor': 1000,
  'subtotal': 10.0,
  'discountMinor': 0,
  'discount': 0.0,
  'totalMinor': 1000,
  'total': 10.0,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
};

final class _Reader implements TenantDataReader {
  _Reader(this._documents, {this.responsePath, this.ignoreFilters = false});

  final Map<String, Map<String, Object?>> _documents;
  final String? responsePath;
  final bool ignoreFilters;
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final data = _documents[path];
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final path in _documents.keys.toList()..sort()) {
      if (!path.startsWith('${query.collectionPath}/')) continue;
      final data = _documents[path]!;
      final matchesFilters =
          ignoreFilters ||
          query.equalityFilters.entries.every(
            (filter) => data[filter.key] == filter.value,
          );
      if (!matchesFilters) continue;
      matches.add(
        TenantQueryDocumentSnapshot(path: responsePath ?? path, data: data),
      );
      if (matches.length >= query.limit) break;
    }
    return matches;
  }
}
