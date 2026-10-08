import 'package:uzapay_pos/production/production.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a production form may send, and the arithmetic it shows while typing.
///
/// Every refusal mirrors one `completeProduction` makes, and the cost per unit
/// is the server's to the cent - the figure a person reads on the form is the
/// cost the product is given.
void main() {
  group('the arithmetic', () {
    test('cost per unit is rounded half up to the cent, as the server rounds', () {
      expect(productionUnitCostMinor(300000, 100), 3000);
      expect(productionUnitCostMinor(100000, 3), 33333);
      expect(productionUnitCostMinor(100, 8), 13);
      expect(productionUnitCostMinor(99, 8), 12);
    });

    test('a carried cost scales with the batch, half up, never to nothing', () {
      expect(productionScaledAmountMinor(200000, from: 100, to: 100), 200000);
      expect(productionScaledAmountMinor(200000, from: 100, to: 50), 100000);
      expect(productionScaledAmountMinor(200000, from: 100, to: 250), 500000);
      expect(productionScaledAmountMinor(100, from: 3, to: 1), 33);
      expect(productionScaledAmountMinor(100, from: 8, to: 1), 13);
      expect(productionScaledAmountMinor(1, from: 100, to: 1), 1);
    });

    test('the preview counts what is a figure so far, and waits for a quantity', () {
      final early = TenantProductionPreview.of(
        quantity: '',
        rows: const <TenantProductionRowDraft>[
          TenantProductionRowDraft(description: 'Flour', amount: '2000'),
          TenantProductionRowDraft(description: 'Labour', amount: '5'),
        ],
      );
      expect(early!.totalCostMinor, 200500);
      expect(early.unitCostMinor, isNull);

      final later = TenantProductionPreview.of(
        quantity: '100',
        rows: const <TenantProductionRowDraft>[
          TenantProductionRowDraft(description: 'Flour', amount: '2000'),
          TenantProductionRowDraft(description: 'Labour', amount: '1000'),
          // Not a figure yet, so not counted - never refused mid-typing.
          TenantProductionRowDraft(description: 'Gas', amount: '2.'),
        ],
      );
      expect(later!.totalCostMinor, 300000);
      expect(later.unitCostMinor, 3000);

      expect(
        TenantProductionPreview.of(
          quantity: '10',
          rows: const <TenantProductionRowDraft>[TenantProductionRowDraft()],
        ),
        isNull,
      );
    });
  });

  group('building a batch', () {
    test('writes the request the server reads, numbered by day and batch', () {
      final intent = _intent(const <TenantProductionRowDraft>[
        TenantProductionRowDraft(description: ' Flour ', amount: '2000'),
        TenantProductionRowDraft(description: 'Labour', amount: '500'),
        TenantProductionRowDraft(description: 'Gas', amount: '200'),
        TenantProductionRowDraft(description: 'Packaging', amount: '300'),
      ]);

      expect(intent.batchId, startsWith('pb_'));
      expect(intent.batchNumber, matches(RegExp(r'^PB-20260924-[0-9A-F]{6}$')));
      expect(intent.totalCostMinor, 300000);
      expect(intent.unitCostMinor, 3000);
      expect(intent.quantityAfter, 112);
      expect(intent.previousCostMinor, 2800);
      expect(intent.path, 'tenants/tenant-a/production_batches/${intent.batchId}');
      final payload = intent.payload();
      expect(payload['productId'], 'prod-bread');
      expect(payload['quantity'], 100);
      expect(
        (payload['expenses']! as List).first,
        <String, Object?>{'description': 'Flour', 'amount': 2000},
      );
    });

    test('a blank row is ignored, so an accidental Add cost blocks nothing', () {
      final intent = _intent(const <TenantProductionRowDraft>[
        TenantProductionRowDraft(description: 'Flour', amount: '3000'),
        TenantProductionRowDraft(),
      ]);

      expect(intent.expenses, hasLength(1));
    });

    test('a batch with no cost cannot be built', () {
      final cases = <String, List<TenantProductionRowDraft>>{
        'no_costs': const <TenantProductionRowDraft>[TenantProductionRowDraft()],
        'invalid_amount': const <TenantProductionRowDraft>[
          TenantProductionRowDraft(description: 'Flour', amount: '0'),
        ],
        'invalid_amount ': const <TenantProductionRowDraft>[
          TenantProductionRowDraft(description: 'Flour', amount: ''),
        ],
        'invalid_description': const <TenantProductionRowDraft>[
          TenantProductionRowDraft(description: '', amount: '10'),
        ],
      };
      for (final entry in cases.entries) {
        expect(
          () => _intent(entry.value),
          throwsA(_code(entry.key.trim())),
          reason: entry.key,
        );
      }
    });

    test('a cost per unit that rounds to nothing is refused', () {
      expect(
        () => _intent(
          const <TenantProductionRowDraft>[
            TenantProductionRowDraft(description: 'Flour', amount: '0.01'),
          ],
          quantity: '1000000',
        ),
        throwsA(_code('cost_rounds_to_nothing')),
      );
    });

    test('a retired product cannot be produced', () {
      const rows = <TenantProductionRowDraft>[
        TenantProductionRowDraft(description: 'Flour', amount: '10'),
      ];
      expect(
        () => _intent(rows, product: _product(retired: true)),
        throwsA(_code('retired_product')),
      );
    });

    test('the quantity is a whole number of units', () {
      const rows = <TenantProductionRowDraft>[
        TenantProductionRowDraft(description: 'Flour', amount: '10'),
      ];
      for (final quantity in <String>['0', '2.5', '', '1000001']) {
        expect(
          () => _intent(rows, quantity: quantity),
          throwsA(_code('invalid_quantity')),
          reason: quantity,
        );
      }
    });

    test('a cashier may not produce', () {
      expect(
        () => _intent(
          const <TenantProductionRowDraft>[
            TenantProductionRowDraft(description: 'Flour', amount: '10'),
          ],
          role: TenantRole.cashier,
        ),
        throwsA(_code('production_forbidden')),
      );
    });
  });

  test('a stored batch reads back with its rows and the cost it replaced', () {
    final batch = TenantProductionBatch.fromDocument(
      path: 'tenants/tenant-a/production_batches/pb_one',
      data: <String, Object?>{
        'batchNumber': 'PB-20260924-7F3A2C',
        'productId': 'prod-bread',
        'productName': 'White bread loaf',
        'quantity': 100,
        'expenses': <Map<String, Object?>>[
          <String, Object?>{'description': 'Flour', 'amountMinor': 200000},
        ],
        'totalCostMinor': 200000,
        'unitCostMinor': 2000,
        'previousCostMinor': 2800,
      },
    );

    expect(batch.expenses.single.description, 'Flour');
    expect(batch.previousCostMinor, 2800);
  });
}

TenantProduct _product({bool retired = false}) => TenantProduct.fromDocument(
  path: 'tenants/tenant-a/products/prod-bread',
  data: <String, Object?>{
    'name': 'White bread loaf',
    'SKU': 'BR-1',
    'price': 50,
    'cost': 28,
    'quantity': 12,
    'categoryId': 'ct_bakery',
    if (retired) 'retired': true,
  },
);

TenantProductionIntent _intent(
  List<TenantProductionRowDraft> rows, {
  String quantity = '100',
  TenantProduct? product,
  TenantRole role = TenantRole.manager,
}) => TenantProductionRepository(
  session: TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role),
  reader: const _NoReader(),
).buildIntent(
  product: product ?? _product(),
  quantity: quantity,
  rows: rows,
  requestId: 'production-request-1',
  businessDate: '2026-09-24',
);

Matcher _code(String code) => isA<TenantProductionException>().having(
  (error) => error.code,
  'code',
  code,
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
