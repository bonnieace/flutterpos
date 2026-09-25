/// A period of production batches, for the production report's samples.
library;

import 'package:flutter_application_1/production/production_batch.dart';
import 'package:flutter_application_1/reports/analysis/production_analysis.dart';

import 'documents.dart';

/// Bread baked through the period at a cost that crept up, and one product
/// made once.
List<TenantProductionBatch> fixtureProductionBatches() {
  TenantProductionBatch batch(
    String id, {
    required String productId,
    required String name,
    required int day,
    required int quantity,
    required List<(String, int)> expenses,
  }) {
    final total = expenses.fold(0, (sum, row) => sum + row.$2);
    return TenantProductionBatch.fromDocument(
      path: 'tenants/tenant-a/production_batches/$id',
      data: <String, Object?>{
        'batchNumber':
            'PB-202609${day.toString().padLeft(2, '0')}-${id.toUpperCase().padLeft(6, '0').substring(0, 6)}',
        'productId': productId,
        'productName': name,
        'quantity': quantity,
        'expenses': <Map<String, Object?>>[
          for (final (description, amount) in expenses)
            <String, Object?>{'description': description, 'amountMinor': amount},
        ],
        'totalCostMinor': total,
        'unitCostMinor': productionUnitCostMinor(total, quantity),
        'createdAt': DateTime.utc(2026, 9, day, 4),
      },
    );
  }

  return <TenantProductionBatch>[
    for (final (index, day) in <int>[2, 5, 9, 12, 16, 19].indexed)
      batch(
        'pb${index + 1}',
        productId: 'pd-bread',
        name: 'White bread loaf',
        day: day,
        quantity: 100,
        expenses: <(String, int)>[
          ('Flour', 200000 + index * 5000),
          ('Labour', 50000),
          ('Gas', 20000),
          ('Packaging', 30000),
        ],
      ),
    batch(
      'pbm',
      productId: 'pd-mandazi',
      name: 'Mandazi',
      day: 14,
      quantity: 240,
      expenses: const <(String, int)>[('Flour', 60000), ('Oil', 36000)],
    ),
  ];
}

TenantProductionAnalysis fixtureProductionAnalysis() =>
    TenantProductionAnalysis.from(
      period: fixturePeriod(),
      batches: fixtureProductionBatches(),
    );
