/// Six weeks of counting, for the stock counts report's tests and samples.
///
/// Shaped like a real small shop rather than like tidy test data: counting got
/// worse over the period, two counts landed and were never applied, one is
/// still arriving, and one covered a single category. Those are the cases the
/// report has something to say about.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/inventory/stock_take_review.dart';
import 'package:flutter_application_1/reports/analysis/stock_counts_analysis.dart';
import 'package:flutter_application_1/reports/report_period.dart';
import 'package:flutter_application_1/tenancy/tenant_repository.dart';

TenantStockTakeRecord countRecord({
  required String businessDate,
  required String counterUid,
  required TenantStockTakeStatus status,
  int productsInScope = 40,
  int countedLineCount = 40,
  int varianceLineCount = 0,
  int absoluteVarianceUnits = 0,
  int unmatchedLineCount = 0,
  String? categoryId,
  String token = 'aaa',
}) => TenantStockTakeRecord.fromSnapshot(
  TenantQueryDocumentSnapshot(
    path: 'tenants/tenant-a/stock_takes/st_${businessDate}_$token',
    data: <String, Object?>{
      'tenantId': 'tenant-a',
      'counterUid': counterUid,
      'businessDate': businessDate,
      'status': switch (status) {
        TenantStockTakeStatus.applied => 'applied',
        TenantStockTakeStatus.submitted => 'submitted',
        TenantStockTakeStatus.submitting => 'submitting',
      },
      'productsInScope': productsInScope,
      'countedLineCount': countedLineCount,
      'varianceLineCount': varianceLineCount,
      'absoluteVarianceUnits': absoluteVarianceUnits,
      'unmatchedLineCount': unmatchedLineCount,
      if (categoryId != null)
        'scope': <String, Object?>{'kind': 'category', 'categoryId': categoryId},
      'submittedAt': Timestamp.fromDate(
        DateTime.parse('${businessDate}T17:00:00Z'),
      ),
    },
  ),
);

/// Six weeks to 23 September.
TenantReportPeriod fixtureStockCountsPeriod() =>
    TenantReportPeriod(startDate: '2026-08-13', endDate: '2026-09-23');

List<TenantStockTakeRecord> fixtureStockCounts() => <TenantStockTakeRecord>[
  countRecord(
    businessDate: '2026-08-15',
    counterUid: 'cashier-a',
    status: TenantStockTakeStatus.applied,
    varianceLineCount: 2,
    absoluteVarianceUnits: 5,
    token: 'a1',
  ),
  countRecord(
    businessDate: '2026-08-22',
    counterUid: 'cashier-a',
    status: TenantStockTakeStatus.applied,
    varianceLineCount: 3,
    absoluteVarianceUnits: 9,
    token: 'a2',
  ),
  // A shelf nobody finished: ten of the forty in scope were left blank.
  countRecord(
    businessDate: '2026-09-02',
    counterUid: 'cashier-b',
    status: TenantStockTakeStatus.applied,
    countedLineCount: 30,
    varianceLineCount: 4,
    absoluteVarianceUnits: 12,
    token: 'b1',
  ),
  // Landed and never applied - the finding.
  countRecord(
    businessDate: '2026-09-12',
    counterUid: 'cashier-b',
    status: TenantStockTakeStatus.submitted,
    varianceLineCount: 6,
    absoluteVarianceUnits: 21,
    unmatchedLineCount: 1,
    token: 'b2',
  ),
  countRecord(
    businessDate: '2026-09-18',
    counterUid: 'cashier-a',
    status: TenantStockTakeStatus.submitted,
    productsInScope: 12,
    countedLineCount: 12,
    varianceLineCount: 3,
    absoluteVarianceUnits: 7,
    categoryId: 'drinks',
    token: 'a3',
  ),
  // Still in somebody's outbox.
  countRecord(
    businessDate: '2026-09-22',
    counterUid: 'cashier-b',
    status: TenantStockTakeStatus.submitting,
    countedLineCount: 18,
    varianceLineCount: 1,
    absoluteVarianceUnits: 2,
    token: 'b3',
  ),
];

TenantStockCountsAnalysis fixtureStockCountsAnalysis({
  List<TenantStockTakeRecord>? previous,
  bool truncated = false,
}) => TenantStockCountsAnalysis.from(
  period: fixtureStockCountsPeriod(),
  takes: fixtureStockCounts(),
  previous: previous,
  truncated: truncated,
);
