import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/checkout/checkout_receipt.dart';
import 'package:flutter_application_1/checkout/checkout_tender.dart';
import 'package:flutter_application_1/sales/sales.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';
const String _payloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  group('canonical sale read model', () {
    test('accepts the exact document the submission worker writes', () {
      final sale = TenantSale.fromDocument(
        path: 'tenants/tenant-a/sales/co-1',
        data: _sale(),
      );

      expect(sale.id, 'co-1');
      expect(sale.soldById, 'user-a');
      expect(sale.shiftId, 'shift-a');
      expect(sale.currency, 'KES');
      expect(sale.receiptNumber, _receipt(1));
      expect(sale.totalMinor, 900);
      expect(sale.subtotalMinor, 1000);
      expect(sale.discountMinor, 100);
      expect(sale.lines.single.name, 'Tusker');
      expect(sale.lines.single.quantity, 2);
      expect(sale.recordedAt, DateTime.utc(2026, 7, 31, 12));
    });

    test('refuses a document that disagrees with its own path or schema', () {
      expect(
        () => TenantSale.fromDocument(
          path: 'tenants/tenant-a/sales/co-2',
          data: _sale(),
        ),
        _code('sale_identity_mismatch'),
      );
      expect(
        () => TenantSale.fromDocument(
          path: 'tenants/tenant-a/sales/co-1',
          data: _sale(overrides: <String, Object?>{'tenantId': 'tenant-b'}),
        ),
        _code('sale_identity_mismatch'),
      );
      expect(
        () => TenantSale.fromDocument(
          path: 'tenants/tenant-a/shifts/co-1',
          data: _sale(),
        ),
        _code('invalid_sale_path'),
      );
      for (final version in <Object?>[3, 0, '2', 2.0]) {
        expect(
          () => TenantSale.fromDocument(
            path: 'tenants/tenant-a/sales/co-1',
            data: _sale(
              overrides: <String, Object?>{'payloadSchemaVersion': version},
            ),
          ),
          _code('unsupported_sale_schema'),
          reason: '$version',
        );
      }
      expect(
        () => TenantSale.fromDocument(
          path: 'tenants/tenant-a/sales/co-1',
          // The key is removed rather than nulled by the builder.
          data: _sale(
            overrides: <String, Object?>{'payloadSchemaVersion': null},
          ),
        ),
        _code('unsupported_sale_schema'),
      );
    });

    test('reads the tender exactly as its own schema version allows', () {
      final v1 = TenantSale.fromDocument(
        path: 'tenants/tenant-a/sales/co-1',
        data: _sale(),
      );
      expect(v1.schemaVersion, 1);
      // A sale recorded before the decision names no payment method. That is a
      // statement about the record, never about whether the customer paid.
      expect(v1.tender, isNull);

      for (final tender in CheckoutTender.values) {
        final sale = TenantSale.fromDocument(
          path: 'tenants/tenant-a/sales/co-1',
          data: _sale(
            overrides: <String, Object?>{
              'payloadSchemaVersion': 2,
              'tender': tender.wireValue,
            },
          ),
        );
        expect(sale.schemaVersion, 2);
        expect(sale.tender, tender, reason: tender.wireValue);
      }
    });

    test('reads a v2 sale with no tender as an unanswered question', () {
      // **Absent is not malformed.** The register does not preselect a payment
      // method, so a cashier who was never told how the customer paid saves a
      // sale that names none. Refusing it here would hide the very rows the
      // *Set payment method* action exists for. A tender that is present and
      // names something unmodelled is still refused, below.
      final sale = TenantSale.fromDocument(
        path: 'tenants/tenant-a/sales/co-1',
        data: _sale(overrides: <String, Object?>{'payloadSchemaVersion': 2}),
      );

      expect(sale.tender, isNull);
    });

    test('refuses a tender its schema version cannot carry', () {
      final refused = <String, Map<String, Object?>>{
        // A v1 sale that grew a tender did not come from this client.
        'v1-with-tender': <String, Object?>{'tender': 'cash'},
        'v2-empty': <String, Object?>{'payloadSchemaVersion': 2, 'tender': ''},
        'v2-capitalised': <String, Object?>{
          'payloadSchemaVersion': 2,
          'tender': 'Cash',
        },
        'v2-padded': <String, Object?>{
          'payloadSchemaVersion': 2,
          'tender': 'cash ',
        },
        'v2-unmodelled': <String, Object?>{
          'payloadSchemaVersion': 2,
          'tender': 'cheque',
        },
        'v2-numeric': <String, Object?>{'payloadSchemaVersion': 2, 'tender': 1},
        'v2-map': <String, Object?>{
          'payloadSchemaVersion': 2,
          'tender': <String, Object?>{'method': 'cash'},
        },
      };

      for (final entry in refused.entries) {
        expect(
          () => TenantSale.fromDocument(
            path: 'tenants/tenant-a/sales/co-1',
            data: _sale(overrides: entry.value),
          ),
          _code('invalid_sale_tender'),
          reason: entry.key,
        );
      }
    });

    test('refuses money that does not add up', () {
      final refused = <String, Map<String, Object?>>{
        'total-not-subtotal-minus-discount': <String, Object?>{
          'totalMinor': 950,
          'total': 9.5,
        },
        'discount-above-subtotal': <String, Object?>{
          'discountMinor': 2000,
          'discount': 20,
        },
        'lines-do-not-sum': <String, Object?>{
          'subtotalMinor': 900,
          'subtotal': 9,
          'totalMinor': 800,
          'total': 8,
        },
        'major-mirror-disagrees': <String, Object?>{'total': 90},
        'string-total': <String, Object?>{'totalMinor': '900'},
        'negative-total': <String, Object?>{'totalMinor': -1, 'total': -0.01},
      };

      for (final entry in refused.entries) {
        expect(
          () => TenantSale.fromDocument(
            path: 'tenants/tenant-a/sales/co-1',
            data: _sale(overrides: entry.value),
          ),
          throwsA(isA<TenantSaleException>()),
          reason: entry.key,
        );
      }
    });

    test('refuses a receipt that does not describe its own sale', () {
      expect(
        () => TenantSale.fromDocument(
          path: 'tenants/tenant-a/sales/co-1',
          data: _sale(
            overrides: <String, Object?>{'receiptNumber': _receipt(2)},
          ),
        ),
        _code('invalid_sale_receipt'),
      );
      expect(
        () => TenantSale.fromDocument(
          path: 'tenants/tenant-a/sales/co-1',
          data: _sale(
            overrides: <String, Object?>{'businessDate': '2026-07-30'},
          ),
        ),
        _code('invalid_sale_receipt'),
      );
      expect(
        () => TenantSale.fromDocument(
          path: 'tenants/tenant-a/sales/co-1',
          data: _sale(
            overrides: <String, Object?>{'receiptNumber': 'CT-000-x'},
          ),
        ),
        _code('invalid_sale_receipt'),
      );
    });

    test('refuses malformed, empty, or duplicated sale lines', () {
      final refused = <String, Object?>{
        'not-a-list': 'one item',
        'empty': <Object?>[],
        'not-maps': <Object?>['line'],
        'zero-quantity': <Object?>[
          {..._line(), 'quantity': 0},
        ],
        'line-total-disagrees': <Object?>[
          {..._line(), 'lineTotalMinor': 999},
        ],
        'duplicate-product': <Object?>[_line(), _line()],
      };

      for (final entry in refused.entries) {
        expect(
          () => TenantSale.fromDocument(
            path: 'tenants/tenant-a/sales/co-1',
            data: _sale(overrides: <String, Object?>{'items': entry.value}),
          ),
          throwsA(isA<TenantSaleException>()),
          reason: entry.key,
        );
      }
    });

    test('a pending server instant is accepted, a malformed one is not', () {
      final pending = TenantSale.fromDocument(
        path: 'tenants/tenant-a/sales/co-1',
        data: _sale(overrides: <String, Object?>{'createdAt': null}),
      );
      expect(pending.recordedAt, isNull);

      expect(
        () => TenantSale.fromDocument(
          path: 'tenants/tenant-a/sales/co-1',
          data: _sale(overrides: <String, Object?>{'createdAt': 'yesterday'}),
        ),
        _code('invalid_sale_document'),
      );
    });
  });

  group('sale history repository', () {
    test('pages one shift newest first and proves its attribution', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/sales/co-1': _sale(),
        'tenants/tenant-a/sales/co-2': _sale(saleId: 'co-2', sequence: 2),
        'tenants/tenant-a/sales/co-3': _sale(
          saleId: 'co-3',
          sequence: 3,
          overrides: <String, Object?>{'shiftId': 'shift-b'},
        ),
      });

      final page = await _repository(reader).loadShiftSales(shift: _scope());

      expect(page.items.map((sale) => sale.id), <String>['co-2', 'co-1']);
      final query = reader.queries.single;
      expect(query.collectionPath, 'tenants/tenant-a/sales');
      expect(query.equalityFilters, <String, Object?>{
        'shiftId': 'shift-a',
        'soldById': 'user-a',
      });
      expect(query.descending, isTrue);
      expect(query.limit, 21);
    });

    test('a sale that contradicts its shift fails the page closed', () async {
      final mismatches = <String, Map<String, Object?>>{
        'other-cashier': <String, Object?>{'soldById': 'user-b'},
        'other-device': <String, Object?>{
          'deviceId': 'dev-ffffffffffffffffffffffffffffffff',
        },
        'other-business-day': <String, Object?>{'businessDate': '2026-07-30'},
      };

      for (final entry in mismatches.entries) {
        // The receipt is regenerated so only the attribution disagrees.
        final reader = _Reader(<String, Map<String, Object?>>{
          'tenants/tenant-a/sales/co-1': _sale(
            deviceId: entry.value['deviceId'] as String? ?? _deviceA,
            businessDate:
                entry.value['businessDate'] as String? ?? _businessDate,
            overrides: <String, Object?>{
              if (entry.value['soldById'] != null)
                'soldById': entry.value['soldById'],
            },
          ),
        }, ignoreFilters: true);

        await expectLater(
          _repository(reader).loadShiftSales(shift: _scope()),
          throwsA(_saleCode('sale_shift_mismatch')),
          reason: entry.key,
        );
      }
    });

    test(
      'pages this cashier own recent sales and refuses a foreign one',
      () async {
        final reader = _Reader(<String, Map<String, Object?>>{
          'tenants/tenant-a/sales/co-1': _sale(),
          'tenants/tenant-a/sales/co-2': _sale(saleId: 'co-2', sequence: 2),
        });

        final page = await _repository(reader).loadOwnRecentSales(pageSize: 1);
        expect(page.items.single.id, 'co-2');
        expect(page.hasMore, isTrue);
        expect(page.nextCursor, 'co-2');
        expect(reader.queries.single.equalityFilters, <String, Object?>{
          'soldById': 'user-a',
        });

        final foreign = _Reader(<String, Map<String, Object?>>{
          'tenants/tenant-a/sales/co-1': _sale(
            overrides: <String, Object?>{'soldById': 'user-b'},
          ),
        }, ignoreFilters: true);
        await expectLater(
          _repository(foreign).loadOwnRecentSales(),
          throwsA(_saleCode('foreign_sale')),
        );
      },
    );

    test('resumes an own-sales page from its cursor', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/sales/co-1': _sale(),
        'tenants/tenant-a/sales/co-2': _sale(saleId: 'co-2', sequence: 2),
      });

      final second = await _repository(
        reader,
      ).loadOwnRecentSales(pageSize: 1, cursor: 'co-2');

      expect(second.items.single.id, 'co-1');
      expect(second.hasMore, isFalse);
      expect(second.nextCursor, isNull);
      expect(reader.queries.single.startAfterDocumentId, 'co-2');
    });

    test('a cross-tenant response fails closed', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/sales/co-1': _sale(),
      }, collectionResponsePath: 'tenants/tenant-b/sales/co-1');

      await expectLater(
        _repository(reader).loadOwnRecentSales(),
        throwsA(isA<TenantScopeViolation>()),
      );
    });
  });
}

TenantSaleHistoryRepository _repository(_Reader reader) =>
    TenantSaleHistoryRepository(
      session: TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.cashier,
      ),
      reader: reader,
    );

TenantSaleShiftScope _scope() => const TenantSaleShiftScope(
  shiftId: 'shift-a',
  staffId: 'user-a',
  deviceId: _deviceA,
  businessDate: _businessDate,
);

Matcher _saleCode(String code) =>
    isA<TenantSaleException>().having((error) => error.code, 'code', code);

Matcher _code(String code) => throwsA(_saleCode(code));

String _receipt(int sequence, {String? deviceId, String? businessDate}) =>
    formatCheckoutReceiptNumber(
      deviceId: deviceId ?? _deviceA,
      businessDate: businessDate ?? _businessDate,
      sequence: sequence,
    );

Map<String, Object?> _line() => <String, Object?>{
  'productId': 'product-1',
  'name': 'Tusker',
  'quantity': 2,
  'unitPriceMinor': 500,
  'unitPrice': 5.0,
  'lineTotalMinor': 1000,
  'lineTotal': 10.0,
  // Cost fields the draft may write are parsed away, never displayed.
  'unitCostMinor': 300,
  'costMinor': 600,
};

Map<String, Object?> _sale({
  String saleId = 'co-1',
  int sequence = 1,
  String deviceId = _deviceA,
  String businessDate = _businessDate,
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'checkoutId': saleId,
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'payloadHash': _payloadHash,
    'payloadSchemaVersion': 1,
    'currency': 'KES',
    'businessDate': businessDate,
    'clientCreatedAtMs': 1785484800000,
    'shiftId': 'shift-a',
    'deviceId': deviceId,
    'receiptNumber': _receipt(
      sequence,
      deviceId: deviceId,
      businessDate: businessDate,
    ),
    'receiptSequence': sequence,
    'items': <Object?>[_line()],
    'subtotalMinor': 1000,
    'subtotal': 10.0,
    'discountMinor': 100,
    'discount': 1.0,
    'totalMinor': 900,
    'total': 9.0,
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

final class _Reader implements TenantDataReader {
  _Reader(
    this._documents, {
    this.collectionResponsePath,
    this.ignoreFilters = false,
  });

  final Map<String, Map<String, Object?>> _documents;
  final String? collectionResponsePath;
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
    final paths = _documents.keys.toList()..sort();
    if (query.descending) {
      paths.sort((left, right) => right.compareTo(left));
    }
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final path in paths) {
      if (!path.startsWith('${query.collectionPath}/')) continue;
      final id = path.substring('${query.collectionPath}/'.length);
      final cursor = query.startAfterDocumentId;
      if (cursor != null && id.compareTo(cursor) >= 0) continue;
      final data = _documents[path]!;
      final matchesFilters =
          ignoreFilters ||
          query.equalityFilters.entries.every(
            (filter) => data[filter.key] == filter.value,
          );
      if (!matchesFilters) continue;
      matches.add(
        TenantQueryDocumentSnapshot(
          path: collectionResponsePath ?? path,
          data: data,
        ),
      );
      if (matches.length >= query.limit) break;
    }
    return matches;
  }
}
