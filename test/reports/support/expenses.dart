/// A month of spending, for the expenses report's tests and samples.
///
/// Shaped like a real small business rather than like tidy test data: rent and
/// wages dominate, most days have nothing at all, one heading started this
/// month and one stopped, and there is a voided entry. Those are the cases the
/// report has something to say about.
library;

import 'package:flutter_application_1/expenses/expense.dart';
import 'package:flutter_application_1/reports/analysis/expense_analysis.dart';
import 'package:flutter_application_1/reports/report_period.dart';

TenantExpense expenseRecord({
  required int amountMinor,
  required String date,
  required TenantExpenseCategory category,
  required String description,
  required String token,
  bool voided = false,
}) => TenantExpense.fromDocument(
  path: 'tenants/tenant-a/expenses/$date-$token',
  data: <String, Object?>{
    'expenseId': '$date-$token',
    'tenantId': 'tenant-a',
    'businessDate': date,
    'category': category.wireValue,
    'description': description,
    'amountMinor': amountMinor,
    'amount': amountMinor / 100,
    'recordedBy': 'owner-a',
    'createdAt': DateTime.utc(2026, 9, 10, 9),
    if (voided) ...<String, Object?>{
      'voidedAt': DateTime.utc(2026, 9, 12, 10),
      'voidedBy': 'owner-a',
      'voidReason': 'Recorded twice.',
    },
  },
);

/// September to date.
TenantExpenseAnalysis fixtureExpenseAnalysis() {
  final period = TenantReportPeriod(
    startDate: '2026-09-01',
    endDate: '2026-09-22',
  );

  final now = TenantExpensePeriod(
    startDate: period.startDate,
    endDate: period.endDate,
    truncated: false,
    records: <TenantExpense>[
      expenseRecord(
        amountMinor: 4500000,
        date: '2026-09-01',
        category: TenantExpenseCategory.rent,
        description: 'Shop rent for September',
        token: 'a',
      ),
      expenseRecord(
        amountMinor: 1800000,
        date: '2026-09-05',
        category: TenantExpenseCategory.wages,
        description: 'Wages, first half',
        token: 'b',
      ),
      expenseRecord(
        amountMinor: 1750000,
        date: '2026-09-20',
        category: TenantExpenseCategory.wages,
        description: 'Wages, second half',
        token: 'c',
      ),
      expenseRecord(
        amountMinor: 620000,
        date: '2026-09-08',
        category: TenantExpenseCategory.utilities,
        description: 'Electricity',
        token: 'd',
      ),
      expenseRecord(
        amountMinor: 148000,
        date: '2026-09-11',
        category: TenantExpenseCategory.transport,
        description: 'Delivery from the depot',
        token: 'e',
      ),
      expenseRecord(
        amountMinor: 96000,
        date: '2026-09-16',
        category: TenantExpenseCategory.transport,
        description: 'Delivery from the depot',
        token: 'f',
      ),
      expenseRecord(
        amountMinor: 310000,
        date: '2026-09-14',
        category: TenantExpenseCategory.supplies,
        description: 'Bags and receipt rolls',
        token: 'g',
      ),
      // New this month, so the report should say it started rather than quote
      // a percentage rise from nothing.
      expenseRecord(
        amountMinor: 880000,
        date: '2026-09-18',
        category: TenantExpenseCategory.repairs,
        description: 'Fridge compressor',
        token: 'h',
      ),
      // Entered twice and withdrawn. Counted, listed, never totalled.
      expenseRecord(
        amountMinor: 620000,
        date: '2026-09-08',
        category: TenantExpenseCategory.utilities,
        description: 'Electricity',
        token: 'i',
        voided: true,
      ),
    ],
  );

  final earlier = period.precedingComparable;
  final before = TenantExpensePeriod(
    startDate: earlier.startDate,
    endDate: earlier.endDate,
    truncated: false,
    records: <TenantExpense>[
      expenseRecord(
        amountMinor: 4500000,
        date: earlier.startDate,
        category: TenantExpenseCategory.rent,
        description: 'Shop rent',
        token: 'a',
      ),
      expenseRecord(
        amountMinor: 1800000,
        date: earlier.startDate,
        category: TenantExpenseCategory.wages,
        description: 'Wages',
        token: 'b',
      ),
      expenseRecord(
        amountMinor: 540000,
        date: earlier.startDate,
        category: TenantExpenseCategory.utilities,
        description: 'Electricity',
        token: 'c',
      ),
      // Had spending last period and none in this one, so the report should
      // say it stopped.
      expenseRecord(
        amountMinor: 210000,
        date: earlier.startDate,
        category: TenantExpenseCategory.licences,
        description: 'Trading licence',
        token: 'd',
      ),
    ],
  );

  return TenantExpenseAnalysis.from(
    period: period,
    spending: now,
    previous: before,
  );
}
