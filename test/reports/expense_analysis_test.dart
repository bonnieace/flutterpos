/// The arithmetic an expenses report prints.
///
/// **This is where the report's correctness lives.** Everything the document
/// says about a month is a field on [TenantExpenseAnalysis], so every claim it
/// makes is checkable here in plain Dart rather than by reading a chart. The
/// cases that matter are the awkward ones: a heading that started, a heading
/// that stopped, a rise from nothing that is not a percentage, and a voided
/// item that must be counted without being totalled.
library;

import 'package:flutter_application_1/expenses/expense.dart';
import 'package:flutter_application_1/reports/analysis/expense_analysis.dart';
import 'package:flutter_application_1/reports/report_period.dart';
import 'package:flutter_test/flutter_test.dart';

TenantExpense _expense({
  required int amountMinor,
  String date = '2026-09-10',
  TenantExpenseCategory category = TenantExpenseCategory.rent,
  String description = 'Something the business paid for',
  bool voided = false,
  String token = 'a',
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
      'voidedAt': DateTime.utc(2026, 9, 10, 10),
      'voidedBy': 'owner-a',
      'voidReason': 'Recorded twice.',
    },
  },
);

TenantExpensePeriod _period(
  List<TenantExpense> records, {
  String start = '2026-09-01',
  String end = '2026-09-10',
  bool truncated = false,
}) => TenantExpensePeriod(
  startDate: start,
  endDate: end,
  records: records,
  truncated: truncated,
);

TenantReportPeriod _reportPeriod() =>
    TenantReportPeriod(startDate: '2026-09-01', endDate: '2026-09-10');

void main() {
  group('what the period totals', () {
    test('a voided item is counted but never totalled', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[
          _expense(amountMinor: 50000, token: 'a'),
          _expense(amountMinor: 30000, token: 'b', voided: true),
        ]),
      );

      expect(
        analysis.totalMinor,
        50000,
        reason: 'A voided record is money that did not leave the business.',
      );
      expect(analysis.voidedCount, 1);
      expect(
        analysis.voidedMinor,
        30000,
        reason:
            'Counted separately so the report can say what was voided without '
            'adding it in.',
      );
      expect(
        analysis.recordCount,
        2,
        reason: 'Both were read, and the scope block says how many.',
      );
    });

    test('every day of the period is charted, including the empty ones', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[
          _expense(amountMinor: 50000, date: '2026-09-03'),
        ]),
      );

      expect(
        analysis.dailyMinor.length,
        10,
        reason:
            'A chart drawn only over the days that had a record compresses a '
            'quiet week into a point.',
      );
      expect(analysis.dailyMinor['2026-09-03'], 50000);
      expect(analysis.dailyMinor['2026-09-04'], 0);
      expect(
        analysis.quietDays,
        9,
        reason: 'Nine of the ten days had nothing recorded at all.',
      );
    });

    test('the daily mean is across every day, not only the spending ones', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[
          _expense(amountMinor: 100000, date: '2026-09-03'),
        ]),
      );

      expect(
        analysis.dailyMean,
        10000,
        reason:
            'The question is what the month costs to run, and the quiet days '
            'are part of the month.',
      );
    });

    test('the heaviest day is named, and is null when nothing was spent', () {
      expect(
        TenantExpenseAnalysis.from(
          period: _reportPeriod(),
          spending: _period(<TenantExpense>[
            _expense(amountMinor: 1000, date: '2026-09-02'),
            _expense(amountMinor: 9000, date: '2026-09-07', token: 'b'),
          ]),
        ).heaviestDate,
        '2026-09-07',
      );

      expect(
        TenantExpenseAnalysis.from(
          period: _reportPeriod(),
          spending: _period(const <TenantExpense>[]),
        ).heaviestDate,
        isNull,
        reason: 'A period with no spending has no heaviest day to name.',
      );
    });
  });

  group('what the headings say', () {
    test('they are ordered largest first and keep the empty ones', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[
          _expense(
            amountMinor: 20000,
            category: TenantExpenseCategory.wages,
            token: 'a',
          ),
          _expense(
            amountMinor: 80000,
            category: TenantExpenseCategory.rent,
            token: 'b',
          ),
        ]),
      );

      expect(analysis.spent.first.category, TenantExpenseCategory.rent);
      expect(analysis.spent.length, 2);
      expect(
        analysis.headings.length,
        TenantExpenseCategory.values.length,
        reason:
            'Every heading is carried, so a cost that stopped can still be '
            'reported on.',
      );
    });

    test('a heading with spend and none before it reads as new', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[
          _expense(amountMinor: 40000, category: TenantExpenseCategory.repairs),
        ]),
        previous: _period(<TenantExpense>[
          _expense(amountMinor: 50000, category: TenantExpenseCategory.rent),
        ]),
      );

      final repairs = analysis.headings.firstWhere(
        (h) => h.category == TenantExpenseCategory.repairs,
      );

      expect(repairs.isNew, isTrue);
      expect(
        repairs.change,
        isNull,
        reason:
            'A rise from nothing is not a percentage. The report says "new '
            'this period" instead, which is the actual finding.',
      );
      expect(analysis.started.map((h) => h.category), <TenantExpenseCategory>[
        TenantExpenseCategory.repairs,
      ]);
    });

    test('a heading that had spend and now has none reads as stopped', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[
          _expense(amountMinor: 40000, category: TenantExpenseCategory.rent),
        ]),
        previous: _period(<TenantExpense>[
          _expense(amountMinor: 40000, category: TenantExpenseCategory.rent),
          _expense(
            amountMinor: 15000,
            category: TenantExpenseCategory.repairs,
            token: 'b',
          ),
        ]),
      );

      expect(
        analysis.stopped.map((h) => h.category),
        <TenantExpenseCategory>[TenantExpenseCategory.repairs],
        reason:
            'A cost that stopped is a finding, and dropping the empty heading '
            'would make the report silent about it.',
      );
    });

    test('a share is a fraction of the period, and zero when nothing was spent', () {
      final spent = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[
          _expense(
            amountMinor: 75000,
            category: TenantExpenseCategory.rent,
            token: 'a',
          ),
          _expense(
            amountMinor: 25000,
            category: TenantExpenseCategory.wages,
            token: 'b',
          ),
        ]),
      );

      expect(spent.spent.first.share, 0.75);
      expect(spent.concentration, 0.75);

      final nothing = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(const <TenantExpense>[]),
      );

      expect(
        nothing.concentration,
        isNull,
        reason:
            'A share of nothing is a division by zero, not a finding. The '
            'section says nothing was spent instead.',
      );
    });

    test('how few headings carry three quarters of the money', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[
          _expense(
            amountMinor: 60000,
            category: TenantExpenseCategory.rent,
            token: 'a',
          ),
          _expense(
            amountMinor: 20000,
            category: TenantExpenseCategory.wages,
            token: 'b',
          ),
          _expense(
            amountMinor: 10000,
            category: TenantExpenseCategory.transport,
            token: 'c',
          ),
          _expense(
            amountMinor: 10000,
            category: TenantExpenseCategory.supplies,
            token: 'd',
          ),
        ]),
      );

      expect(
        analysis.headingsFor(0.75),
        2,
        reason:
            'Rent and wages are 80% between them. "2 of 4 headings carry three '
            'quarters of it" is the sentence this supports.',
      );
    });
  });

  group('the comparison against the period before', () {
    test('a move is a fraction of what it was', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[_expense(amountMinor: 120000)]),
        previous: _period(<TenantExpense>[_expense(amountMinor: 100000)]),
      );

      expect(analysis.change, closeTo(0.2, 0.0001));
    });

    test('no earlier period read means no comparison invented', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[_expense(amountMinor: 120000)]),
      );

      expect(analysis.previousTotalMinor, isNull);
      expect(
        analysis.change,
        isNull,
        reason:
            'A business three weeks old has no previous month, and the report '
            'must print its figures rather than a comparison against nothing.',
      );
    });

    test('a period that spent nothing before does not divide by it', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[_expense(amountMinor: 120000)]),
        previous: _period(const <TenantExpense>[]),
      );

      expect(analysis.previousTotalMinor, 0);
      expect(analysis.change, isNull);
    });
  });

  group('the items it lists', () {
    test('biggest first, and voided ones kept so the list is the record', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[
          _expense(amountMinor: 1000, token: 'a'),
          _expense(amountMinor: 90000, token: 'b', voided: true),
          _expense(amountMinor: 50000, token: 'c'),
        ]),
      );

      expect(
        analysis.biggest.map((r) => r.amountMinor),
        <int>[90000, 50000, 1000],
        reason: 'The listing is what was entered, ordered by size.',
      );
      expect(
        analysis.largest?.amountMinor,
        50000,
        reason:
            'But the *largest item* figure skips the voided one, because that '
            'money never left the business.',
      );
    });

    test('the listing is bounded', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[
          for (var i = 0; i < 60; i++)
            _expense(amountMinor: 1000 + i, token: 'r$i'),
        ]),
      );

      expect(
        analysis.biggest.length,
        TenantExpenseAnalysis.listedItems,
        reason: 'A report is a summary; the workbook carries the lot.',
      );
    });
  });

  group('a capped read', () {
    test('carries the flag through to the analysis', () {
      final analysis = TenantExpenseAnalysis.from(
        period: _reportPeriod(),
        spending: _period(<TenantExpense>[
          _expense(amountMinor: 1000),
        ], truncated: true),
      );

      expect(
        analysis.truncated,
        isTrue,
        reason:
            'The repository caps at 250 records. A report that hit the cap '
            'must say so rather than print a floor as a total.',
      );
    });
  });
}
