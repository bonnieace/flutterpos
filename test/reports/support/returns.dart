/// A fortnight of returns, for the returns report's tests and samples.
///
/// Shaped like a real small shop rather than like tidy test data: one product
/// comes back far more than the rest, two returns are still waiting on a
/// manager, one reason is typed repeatedly and the others are one-offs, and
/// most days have nothing come back at all. Those are the cases the report has
/// something to say about.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uzapay_pos/reports/analysis/returns_analysis.dart';
import 'package:uzapay_pos/reports/report_period.dart';
import 'package:uzapay_pos/returns/return_history.dart';

TenantReturn returnRecord({
  required String id,
  required String recordedOn,
  required String saleId,
  required Map<String, int> units,
  String reason = 'Customer changed their mind',
  String createdBy = 'cashier-a',
  bool verified = false,
  DateTime? recordedAt,
  DateTime? verifiedAt,
  Map<String, String> names = const <String, String>{},
}) => TenantReturn.fromDocument(
  path: 'tenants/tenant-a/returns/$id',
  data: <String, Object?>{
    'returnId': id,
    'tenantId': 'tenant-a',
    'saleId': saleId,
    'businessDate': recordedOn,
    'recordedOn': recordedOn,
    'createdBy': createdBy,
    'reason': reason,
    'status': verified ? 'verified' : 'pending',
    if (verified) ...<String, Object?>{
      'verified': true,
      'stockRestored': true,
      'verifiedBy': 'owner-a',
      'verifiedAt': Timestamp.fromDate(
        verifiedAt ?? DateTime.utc(2026, 9, 12, 9),
      ),
      'stockRestorationId': 'rv_$id',
    },
    'itemsReturned': <Object?>[
      for (final entry in units.entries)
        <String, Object?>{
          'productId': entry.key,
          'quantity': entry.value,
          if (names[entry.key] case final name?) 'productName': name,
        },
    ],
    'createdAt': Timestamp.fromDate(
      recordedAt ?? DateTime.parse('${recordedOn}T10:00:00Z'),
    ),
  },
);

/// The first fortnight of September.
TenantReportPeriod fixtureReturnsPeriod() =>
    TenantReportPeriod(startDate: '2026-09-01', endDate: '2026-09-14');

List<TenantReturn> fixtureReturns() => <TenantReturn>[
  // Tusker keeps coming back: three separate returns over the fortnight.
  returnRecord(
    id: 'ret-1',
    recordedOn: '2026-09-02',
    saleId: 'co-1',
    units: <String, int>{'product-1': 4},
    names: const <String, String>{'product-1': 'Tusker 500ml'},
    reason: 'Bottles were flat',
    verified: true,
    recordedAt: DateTime.utc(2026, 9, 2, 10),
    verifiedAt: DateTime.utc(2026, 9, 2, 16),
  ),
  returnRecord(
    id: 'ret-2',
    recordedOn: '2026-09-05',
    saleId: 'co-2',
    units: <String, int>{'product-1': 6, 'product-2': 1},
    names: const <String, String>{
      'product-1': 'Tusker 500ml',
      'product-2': 'Bread',
    },
    reason: 'Bottles were flat',
    verified: true,
    recordedAt: DateTime.utc(2026, 9, 5, 11),
    verifiedAt: DateTime.utc(2026, 9, 7, 11),
  ),
  // Still waiting on a manager: the stock is on the shelf and off the books.
  returnRecord(
    id: 'ret-3',
    recordedOn: '2026-09-11',
    saleId: 'co-3',
    units: <String, int>{'product-1': 3},
    names: const <String, String>{'product-1': 'Tusker 500ml'},
    reason: 'Bottles were flat',
    createdBy: 'cashier-b',
  ),
  returnRecord(
    id: 'ret-4',
    recordedOn: '2026-09-13',
    saleId: 'co-4',
    units: <String, int>{'product-3': 2},
    names: const <String, String>{'product-3': 'Cooking oil 1L'},
    reason: 'Wrong size',
    createdBy: 'cashier-b',
  ),
];

TenantReturnsAnalysis fixtureReturnsAnalysis({
  List<TenantReturn>? previous,
  bool truncated = false,
}) => TenantReturnsAnalysis.from(
  period: fixtureReturnsPeriod(),
  returns: fixtureReturns(),
  previous: previous,
  truncated: truncated,
);
