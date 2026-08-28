/// The two expense charts, and the arithmetic behind them.
///
/// **Every case here was written after looking at a capture.** The screenshot
/// harness photographs a settled tree, so it shows a defect but does not fail
/// on one - the first capture of the ring had its total clipped through both
/// sides of the hole, and the first capture of the day chart labelled a
/// month-crossing period `29 13 27`. Both looked fine to a passing test suite.
/// These are the assertions that would have caught them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/expenses/expense.dart';
import 'package:flutter_application_1/expenses/expense_charts.dart';
import 'package:flutter_application_1/reporting/reporting_currency.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the day line adapts to how many days it spans', () {
    // **The line replaced a set of bars on 2026-08-28**, to match the shape
    // `bonnieace/Jengaapp` draws. What the bars needed was a measured width so
    // thirty of them did not overlap; what the line needs is to know when its
    // points stop being points.
    test('a week of days carries its dots', () {
      expect(7, lessThanOrEqualTo(ExpenseChartMetrics.maximumDottedDays));
    });

    test('a month of days does not', () {
      // Thirty-one dots at radius 4 across a phone leaves under six pixels
      // between centres, so they merge into a thick line and the line stops
      // being readable at all.
      expect(31, greaterThan(ExpenseChartMetrics.maximumDottedDays));
    });

    test("the line is drawn at the reference's own weight", () {
      // Reproducing an arrangement and then drawing it a different weight is
      // how a replica ends up *nearly* right.
      expect(ExpenseChartMetrics.lineWidth, 4);
      expect(ExpenseChartMetrics.dotRadius, 4);
      expect(ExpenseChartMetrics.dotStrokeWidth, 2);
    });

    test('the area under the line fades rather than filling', () {
      // A solid fill under a curve reads as a second quantity. The reference
      // shades it; this keeps that and never lets it become a block.
      expect(ExpenseChartMetrics.areaTopOpacity, lessThan(0.5));
      expect(
        ExpenseChartMetrics.areaBottomOpacity,
        lessThan(ExpenseChartMetrics.areaTopOpacity),
      );
    });
  });

  group('the ring', () {
    testWidgets('a period that spent nothing draws no ring at all', (
      tester,
    ) async {
      // A ring of one grey slice says a business had one expense, which is a
      // different fact from none.
      await _pumpRing(
        tester,
        TenantExpensePeriod.empty(
          startDate: '2026-08-20',
          endDate: '2026-08-20',
        ),
      );
      expect(find.byKey(const ValueKey('expenses-ring-total')), findsNothing);
    });

    testWidgets('a long total is scaled down rather than clipped', (
      tester,
    ) async {
      // **The defect the first capture showed.** The hole does not grow with
      // the figure, so the figure has to give - and it has to give by scaling,
      // never by losing digits.
      await _pumpRing(tester, _period(<int>[999999999]));

      final total = find.byKey(const ValueKey('expenses-ring-total'));
      expect(total, findsOne);
      expect(
        tester.widget<Text>(total).data,
        '9999999.99',
        reason: 'Every digit is still there; only the size gave way.',
      );
      final box = tester.renderObject<RenderBox>(
        find.ancestor(of: total, matching: find.byType(FittedBox)).first,
      );
      expect(
        box.size.width,
        lessThanOrEqualTo(
          ExpenseChartMetrics.ringHoleRadius *
                  2 *
                  ExpenseChartMetrics.ringTextFraction +
              0.5,
        ),
        reason: 'The figure stays inside the hole it is drawn in.',
      );
    });

    test('the palette cycles rather than running out', () {
      final tokens = AppTokens.dark;
      final series = tokens.colors.chart.series;
      expect(series, isNotEmpty);
      expect(
        ExpenseCompositionRing.colorFor(tokens, series.length),
        ExpenseCompositionRing.colorFor(tokens, 0),
      );
    });

    test('no slice is painted in a status colour', () {
      // `red400` and `amber400` mean something everywhere else in this app. A
      // red slice for Transport would read as a warning about transport.
      final tokens = AppTokens.dark;
      final status = <Color>{
        tokens.colors.status.problem.fg,
        tokens.colors.status.attention.fg,
      };
      for (final color in tokens.colors.chart.series) {
        expect(status.contains(color), isFalse);
      }
    });
  });

  group('the day axis', () {
    testWidgets('a period crossing a month end names the month', (
      tester,
    ) async {
      // **The other defect the captures showed.** Bare days read `29 13 27` -
      // three numbers in no order at all.
      await _pumpDaily(tester, _dates('2026-07-29', 30));

      expect(find.text('29 Jul'), findsOne);
      expect(find.text('27 Aug'), findsOne);
      expect(
        find.text('29'),
        findsNothing,
        reason: 'A bare day number cannot be placed in a month.',
      );
    });

    testWidgets('a single day is still labelled', (tester) async {
      await _pumpDaily(tester, _dates('2026-08-20', 1));
      expect(find.text('20 Aug'), findsOne);
    });
  });
}

Future<void> _pumpRing(WidgetTester tester, TenantExpensePeriod period) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: ExpenseCompositionRing(period: period, currency: _currency),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDaily(WidgetTester tester, List<String> dates) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: ExpenseDailyChart(
              dates: dates,
              totalsMinor: <int>[
                for (var index = 0; index < dates.length; index++)
                  index == dates.length - 1 ? 1450 : 0,
              ],
              currency: _currency,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _dates(String start, int count) {
  final first = DateTime.parse(start);
  return <String>[
    for (var day = 0; day < count; day++)
      first.add(Duration(days: day)).toIso8601String().substring(0, 10),
  ];
}

/// The unlabelled currency, so a case asserting on a figure is asserting on the
/// figure. `TenantReportingCurrency` has no synthetic code by design.
const TenantReportingCurrency _currency = TenantReportingCurrency.unknown;

TenantExpensePeriod _period(List<int> amountsMinor) => TenantExpensePeriod(
  startDate: '2026-08-20',
  endDate: '2026-08-20',
  records: <TenantExpense>[
    for (var index = 0; index < amountsMinor.length; index++)
      TenantExpense.fromDocument(
        path: 'tenants/tenant-a/expenses/2026-08-20-tok$index',
        data: <String, Object?>{
          'expenseId': '2026-08-20-tok$index',
          'tenantId': 'tenant-a',
          'businessDate': '2026-08-20',
          'category': TenantExpenseCategory.rent.wireValue,
          'description': 'Something the business paid for',
          'amountMinor': amountsMinor[index],
          'amount': amountsMinor[index] / 100,
          'recordedBy': 'owner-a',
          'createdAt': DateTime.utc(2026, 8, 20, 9),
        },
      ),
  ],
  truncated: false,
);
