import 'package:uzapay_pos/suppliers/suppliers.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a delivery form may send, and the pages it is sent in.
///
/// Every refusal mirrors one `receiveSupplierDelivery` makes. The stakes are
/// higher than for most forms: a refused page strands every later page of the
/// same delivery on the device that queued it.
void main() {
  group('building a delivery', () {
    test('each line carries its quantity, and a cost only where one was typed', () {
      final intent = _intent(<TenantDeliveryLineDraft>[
        TenantDeliveryLineDraft(product: _bread, quantity: '24', unitCost: '45.50'),
        TenantDeliveryLineDraft(product: _milk, quantity: ' 12 '),
      ]);

      expect(intent.deliveryId, startsWith('sd_'));
      expect(intent.reference, 'INV-48392');
      expect(intent.unitCount, 36);
      expect(intent.lines.first.quantityAfter, 64);
      expect(intent.lines.first.changesCost, isTrue);
      expect(intent.lines.last.changesCost, isFalse);
      expect(intent.pages().single.payload, <String, Object?>{
        'tenantId': 'tenant-a',
        'deliveryId': intent.deliveryId,
        'supplierId': 'sp_abc',
        'reference': 'INV-48392',
        'page': 0,
        'isFinalPage': true,
        'lines': <Map<String, Object?>>[
          <String, Object?>{
            'productId': 'prod-bread',
            'productName': 'White bread loaf',
            'quantity': 24,
            'unitCost': 45.5,
          },
          <String, Object?>{
            'productId': 'prod-milk',
            'productName': 'Milk 500ml',
            'quantity': 12,
          },
        ],
      });
    });

    test('a long delivery is cut into pages of sixteen, only the last final', () {
      final lines = <TenantDeliveryLineDraft>[
        for (var index = 0; index < 34; index++)
          TenantDeliveryLineDraft(product: _product('prod-$index'), quantity: '1'),
      ];

      final pages = _intent(lines).pages();

      expect(pages.map((page) => (page.payload['lines']! as List).length), <int>[
        16,
        16,
        2,
      ]);
      expect(pages.map((page) => page.payload['isFinalPage']), <bool>[
        false,
        false,
        true,
      ]);
      // Zero-padded, because the queue orders by operation ID as a string.
      expect(pages.map((page) => page.operationId.split('-').last), <String>[
        'p000',
        'p001',
        'p002',
      ]);
      expect(pages.map((page) => page.path).toSet(), hasLength(1));
    });

    test('what the server refuses is refused here, naming the product', () {
      final cases = <String, List<TenantDeliveryLineDraft>>{
        'invalid_quantity': <TenantDeliveryLineDraft>[
          TenantDeliveryLineDraft(product: _bread, quantity: '0'),
        ],
        'invalid_quantity ': <TenantDeliveryLineDraft>[
          TenantDeliveryLineDraft(product: _bread, quantity: '1.5'),
        ],
        // Zero would set the product's cost to nothing.
        'invalid_unit_cost': <TenantDeliveryLineDraft>[
          TenantDeliveryLineDraft(product: _bread, quantity: '1', unitCost: '0'),
        ],
        'invalid_unit_cost ': <TenantDeliveryLineDraft>[
          TenantDeliveryLineDraft(product: _bread, quantity: '1', unitCost: '1.005'),
        ],
        'duplicate_product': <TenantDeliveryLineDraft>[
          TenantDeliveryLineDraft(product: _bread, quantity: '1'),
          TenantDeliveryLineDraft(product: _bread, quantity: '2'),
        ],
        'retired_product': <TenantDeliveryLineDraft>[
          TenantDeliveryLineDraft(product: _product('prod-old', retired: true), quantity: '1'),
        ],
        'no_lines': <TenantDeliveryLineDraft>[],
      };
      for (final entry in cases.entries) {
        expect(
          () => _intent(entry.value),
          throwsA(
            isA<TenantSupplierDeliveryException>().having(
              (error) => error.code,
              'code',
              entry.key.trim(),
            ),
          ),
          reason: entry.key,
        );
      }
    });

    test('an inactive supplier receives nothing from this form', () {
      expect(
        () => _intent(
          <TenantDeliveryLineDraft>[
            TenantDeliveryLineDraft(product: _bread, quantity: '1'),
          ],
          supplier: _supplier(active: false),
        ),
        throwsA(isA<TenantSupplierDeliveryException>()),
      );
    });

    test('a blank reference is none at all', () {
      final intent = _intent(
        <TenantDeliveryLineDraft>[
          TenantDeliveryLineDraft(product: _bread, quantity: '1'),
        ],
        reference: '   ',
      );

      expect(intent.reference, isNull);
    });
  });

  group('reading a delivery back', () {
    test('its totals are the sum of its lines, and costless lines are counted', () {
      final delivery = TenantSupplierDelivery.fromDocument(
        path: 'tenants/tenant-a/supplier_deliveries/sd_one',
        data: <String, Object?>{
          'supplierId': 'sp_abc',
          'supplierName': 'ABC Distributors',
          'reference': 'INV-1',
          'complete': true,
          'lines': <Map<String, Object?>>[
            <String, Object?>{
              'productId': 'prod-bread',
              'productName': 'White bread loaf',
              'quantity': 24,
              'unitCostMinor': 4550,
            },
            <String, Object?>{
              'productId': 'prod-milk',
              'productName': 'Milk 500ml',
              'quantity': 12,
              'unitCostMinor': null,
            },
          ],
        },
      );

      expect(delivery.unitCount, 36);
      expect(delivery.valueMinor, 24 * 4550);
      expect(delivery.costlessLineCount, 1);
      expect(delivery.complete, isTrue);
    });
  });
}

final TenantProduct _bread = TenantProduct.fromDocument(
  path: 'tenants/tenant-a/products/prod-bread',
  data: const <String, Object?>{
    'name': 'White bread loaf',
    'SKU': 'BR-1',
    'price': 65,
    'cost': 40,
    'quantity': 40,
    'categoryId': 'ct_bakery',
  },
);

final TenantProduct _milk = TenantProduct.fromDocument(
  path: 'tenants/tenant-a/products/prod-milk',
  data: const <String, Object?>{
    'name': 'Milk 500ml',
    'SKU': 'MK-1',
    'price': 50,
    'cost': 30,
    'quantity': 5,
    'categoryId': 'ct_dairy',
  },
);

TenantProduct _product(String id, {bool retired = false}) =>
    TenantProduct.fromDocument(
      path: 'tenants/tenant-a/products/$id',
      data: <String, Object?>{
        'name': 'Product $id',
        'SKU': id,
        'price': 10,
        'quantity': 0,
        'categoryId': 'ct_a',
        if (retired) 'retired': true,
      },
    );

TenantSupplier _supplier({bool active = true}) => TenantSupplier.fromDocument(
  path: 'tenants/tenant-a/suppliers/sp_abc',
  data: <String, Object?>{'name': 'ABC Distributors', 'active': active},
);

TenantSupplierDeliveryIntent _intent(
  List<TenantDeliveryLineDraft> lines, {
  TenantSupplier? supplier,
  String reference = ' INV-48392 ',
}) => TenantSupplierDeliveryRepository(
  session: TenantSession.active(
    uid: 'user-a',
    tenantId: 'tenant-a',
    role: TenantRole.manager,
  ),
  reader: const _NoReader(),
).buildIntent(
  supplier: supplier ?? _supplier(),
  reference: reference,
  lines: lines,
  requestId: 'delivery-request-1',
);

final class _NoReader implements TenantDataReader {
  const _NoReader();

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
