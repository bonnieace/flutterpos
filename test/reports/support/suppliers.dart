/// A period of supplier deliveries, for the supplier report's samples.
library;

import 'package:flutter_application_1/reports/analysis/supplier_analysis.dart';
import 'package:flutter_application_1/suppliers/supplier_delivery.dart';

import 'documents.dart';

/// Three suppliers over three weeks: a cost that rose, a line with no cost,
/// and a supplier that delivered once.
List<TenantSupplierDelivery> fixtureSupplierDeliveries() {
  TenantSupplierDelivery delivery(
    String id, {
    required String supplierId,
    required String supplierName,
    required int day,
    required List<(String, String, int, int?)> lines,
  }) => TenantSupplierDelivery.fromDocument(
    path: 'tenants/tenant-a/supplier_deliveries/$id',
    data: <String, Object?>{
      'supplierId': supplierId,
      'supplierName': supplierName,
      'reference': 'INV-${48300 + day}',
      'complete': true,
      'createdAt': DateTime.utc(2026, 9, day, 6),
      'lines': <Map<String, Object?>>[
        for (final (productId, name, quantity, cost) in lines)
          <String, Object?>{
            'productId': productId,
            'productName': name,
            'quantity': quantity,
            'unitCostMinor': cost,
          },
      ],
    },
  );

  return <TenantSupplierDelivery>[
    delivery(
      'sd_1',
      supplierId: 'sp_abc',
      supplierName: 'ABC Distributors',
      day: 2,
      lines: const <(String, String, int, int?)>[
        ('pd-soda', 'Soda 500ml', 48, 4500),
        ('pd-water', 'Water 1L', 24, 3000),
      ],
    ),
    delivery(
      'sd_2',
      supplierId: 'sp_mama',
      supplierName: 'Mama Njeri Flour',
      day: 6,
      lines: const <(String, String, int, int?)>[
        ('pd-flour', 'Flour 50kg', 6, 320000),
      ],
    ),
    delivery(
      'sd_3',
      supplierId: 'sp_abc',
      supplierName: 'ABC Distributors',
      day: 16,
      lines: const <(String, String, int, int?)>[
        ('pd-soda', 'Soda 500ml', 72, 5000),
        ('pd-soap', 'Bar soap - blue', 36, null),
      ],
    ),
    delivery(
      'sd_4',
      supplierId: 'sp_fresh',
      supplierName: 'Fresh Farms Dairy',
      day: 20,
      lines: const <(String, String, int, int?)>[
        ('pd-milk', 'Milk 500ml', 60, 5500),
      ],
    ),
  ];
}

TenantSupplierAnalysis fixtureSupplierAnalysis() => TenantSupplierAnalysis.from(
  period: fixturePeriod(),
  deliveries: fixtureSupplierDeliveries(),
  restocksWithoutSupplier: 4,
);
