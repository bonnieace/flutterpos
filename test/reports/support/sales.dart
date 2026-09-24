/// Sales fixtures for the sales report's tests and samples.
///
/// Built through `TenantSale.fromDocument`, so a fixture cannot describe a sale
/// the app could never have recorded.
library;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_application_1/checkout/checkout_receipt.dart';
import 'package:flutter_application_1/reports/analysis/sales_analysis.dart';
import 'package:flutter_application_1/reports/report_period.dart';
import 'package:flutter_application_1/sales/sale_history.dart';

const String fixtureDevice = 'dev-0123456789abcdef0123456789abcdef';
const String _payloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

/// One sold line.
///
/// [unitCostMinor] null is the ordinary case for a sale rung before the catalog
/// carried a cost, and the case every margin figure has to survive.
Map<String, Object?> saleLine({
  required String productId,
  required String name,
  required int quantity,
  required int unitPriceMinor,
  int? unitCostMinor,
  String categoryId = 'general',
}) => <String, Object?>{
  'productId': productId,
  'name': name,
  'categoryId': categoryId,
  'quantity': quantity,
  'unitPriceMinor': unitPriceMinor,
  'lineTotalMinor': unitPriceMinor * quantity,
  // **`costMinor`, not `lineCostMinor`.** The model's field is named
  // `lineCostMinor` but the stored key is `costMinor`, and writing the field
  // name here leaves the unit cost set with no line cost beside it - which
  // `_parseLines` refuses as `inconsistent_sale_line_cost`.
  if (unitCostMinor != null) ...<String, Object?>{
    'unitCostMinor': unitCostMinor,
    'costMinor': unitCostMinor * quantity,
  },
};

TenantSale fixtureSale({
  required String id,
  required String businessDate,
  required List<Map<String, Object?>> lines,
  String soldById = 'user-a',
  String? tender = 'cash',
  int discountMinor = 0,
  int sequence = 1,
}) {
  final subtotal = lines.fold<int>(
    0,
    (sum, line) => sum + (line['lineTotalMinor']! as int),
  );
  return TenantSale.fromDocument(
    path: 'tenants/tenant-a/sales/$id',
    data: <String, Object?>{
      'checkoutId': id,
      'tenantId': 'tenant-a',
      'soldById': soldById,
      'payloadHash': _payloadHash,
      'payloadSchemaVersion': 2,
      if (tender != null) 'tender': tender,
      'currency': 'KES',
      'businessDate': businessDate,
      'shiftId': 'shift-a',
      'deviceId': fixtureDevice,
      'receiptNumber': formatCheckoutReceiptNumber(
        deviceId: fixtureDevice,
        businessDate: businessDate,
        sequence: sequence,
      ),
      'receiptSequence': sequence,
      'items': lines,
      'subtotalMinor': subtotal,
      'subtotal': subtotal / 100,
      'discountMinor': discountMinor,
      'discount': discountMinor / 100,
      'totalMinor': subtotal - discountMinor,
      'total': (subtotal - discountMinor) / 100,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 10, 12)),
    },
  );
}

/// A fortnight of trading where the best seller is not the best earner.
///
/// Maize flour moves most units at a thin margin; cooking oil moves a third as
/// often and earns more. That disagreement is what the report exists to show,
/// so the fixture has to contain it.
TenantSalesAnalysis fixtureSalesAnalysis() {
  final period = TenantReportPeriod(
    startDate: '2026-09-09',
    endDate: '2026-09-22',
  );

  final sales = <TenantSale>[];
  var sequence = 0;
  for (final date in period.businessDates) {
    final day = int.parse(date.substring(8, 10));
    // One day the shop was shut, so the trend has a real zero in it.
    if (day == 14) continue;

    sequence++;
    sales.add(
      fixtureSale(
        id: 'co-$date-a',
        businessDate: date,
        sequence: sequence,
        tender: day.isEven ? 'mpesa' : 'cash',
        discountMinor: day == 19 ? 5000 : 0,
        lines: <Map<String, Object?>>[
          saleLine(
            productId: 'p-flour',
            name: 'Maize flour 2kg',
            quantity: 6,
            unitPriceMinor: 18000,
            unitCostMinor: 16200,
          ),
          saleLine(
            productId: 'p-oil',
            name: 'Cooking oil 1L',
            quantity: 2,
            unitPriceMinor: 42000,
            unitCostMinor: 29000,
          ),
        ],
      ),
    );

    sequence++;
    sales.add(
      fixtureSale(
        id: 'co-$date-b',
        businessDate: date,
        sequence: sequence,
        // A sale from before the app stored a tender. It is a real sale and
        // the mix has to name it rather than drop it.
        tender: day == 11 ? null : 'card',
        lines: <Map<String, Object?>>[
          saleLine(
            productId: 'p-soap',
            name: 'Soap bar',
            quantity: 3,
            unitPriceMinor: 9000,
            // No cost was ever recorded against soap, so it can carry no
            // margin and must not be ranked as though it were pure profit.
            unitCostMinor: null,
          ),
          saleLine(
            productId: 'p-sugar',
            name: 'Sugar 2kg',
            quantity: 2,
            unitPriceMinor: 26000,
            unitCostMinor: 21000,
          ),
        ],
      ),
    );
  }

  final earlier = period.precedingComparable;
  final previous = <TenantSale>[
    for (final (index, date) in earlier.businessDates.indexed)
      fixtureSale(
        id: 'co-prev-$date',
        businessDate: date,
        sequence: 500 + index,
        lines: <Map<String, Object?>>[
          saleLine(
            productId: 'p-flour',
            name: 'Maize flour 2kg',
            quantity: 5,
            unitPriceMinor: 18000,
            unitCostMinor: 16200,
          ),
        ],
      ),
  ];

  return TenantSalesAnalysis.from(
    period: period,
    sales: sales,
    previous: previous,
    documentsRead: sales.length + previous.length,
  );
}
