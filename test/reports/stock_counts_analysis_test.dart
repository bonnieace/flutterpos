/// The arithmetic behind the stock counts report.
///
/// **The rule under test is what an uncounted line means.** A product in scope
/// that nobody wrote a number against is unknown, not agreed - so it never
/// folds into an accuracy rate, which would otherwise report a shop as tidy
/// for shelves nobody looked at.
library;

import 'package:flutter_application_1/inventory/stock_take_review.dart';
import 'package:flutter_application_1/reports/analysis/stock_counts_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stock_counts.dart';

void main() {
  group('counted and not corrected', () {
    test('only a submitted count is still outstanding', () {
      final analysis = fixtureStockCountsAnalysis();

      expect(analysis.appliedCount, 3);
      expect(analysis.awaitingApply, 2);
      expect(analysis.stillArriving, 1);
      expect(analysis.isSettled, isFalse);
    });

    test('the outstanding variances are only the unapplied ones', () {
      final analysis = fixtureStockCountsAnalysis();

      expect(
        analysis.awaitingVarianceLines,
        9,
        reason:
            '6 and 3 on the two submitted counts. An applied count has '
            'already been written to the ledger, and one still arriving '
            'cannot be applied at all.',
      );
      expect(analysis.awaitingVarianceUnits, 28);
    });

    test('a settled period says so', () {
      final analysis = TenantStockCountsAnalysis.from(
        period: fixtureStockCountsPeriod(),
        takes: <TenantStockTakeRecord>[
          countRecord(
            businessDate: '2026-09-02',
            counterUid: 'cashier-a',
            status: TenantStockTakeStatus.applied,
            varianceLineCount: 1,
          ),
        ],
      );

      expect(analysis.isSettled, isTrue);
      expect(analysis.awaitingVarianceLines, 0);
    });
  });

  group('how well the books are kept', () {
    test('the rate is over counted lines, never over lines in scope', () {
      final analysis = fixtureStockCountsAnalysis();

      // 19 out of 180 counted. The 32 nobody wrote a number against are not
      // in the denominator.
      expect(analysis.countedLines, 180);
      expect(analysis.varianceLines, 19);
      expect(analysis.varianceRate, closeTo(19 / 180, 0.0001));
    });

    test('lines nobody counted are carried apart', () {
      final analysis = fixtureStockCountsAnalysis();

      expect(
        analysis.uncountedLines,
        32,
        reason:
            'Ten on the count somebody did not finish, and twenty-two on the '
            'one whose pages are still in an outbox. Nothing is known about '
            'any of them one way or the other.',
      );
    });

    test('a line naming an unheld product is counted and flagged', () {
      final analysis = fixtureStockCountsAnalysis();

      expect(analysis.unmatchedLines, 1);
    });

    test('nothing counted means no rate at all', () {
      final analysis = TenantStockCountsAnalysis.from(
        period: fixtureStockCountsPeriod(),
        takes: const <TenantStockTakeRecord>[],
      );

      expect(
        analysis.varianceRate,
        isNull,
        reason: 'A rate over no lines is not a rate.',
      );
    });

    test('a trend needs four counts before it claims a direction', () {
      final analysis = fixtureStockCountsAnalysis();
      expect(analysis.accuracyTrend, isNotNull);

      final thin = TenantStockCountsAnalysis.from(
        period: fixtureStockCountsPeriod(),
        takes: fixtureStockCounts().take(3).toList(),
      );
      expect(
        thin.accuracyTrend,
        isNull,
        reason:
            'One count each way is a comparison of two afternoons, not a '
            'direction.',
      );
    });

    test('the count that found the most is named', () {
      final analysis = fixtureStockCountsAnalysis();

      expect(analysis.worst?.businessDate, '2026-09-12');
      expect(analysis.worst?.varianceLineCount, 6);
    });
  });

  group('who counted', () {
    test('counters are ranked by how many counts they took', () {
      final analysis = fixtureStockCountsAnalysis();

      expect(analysis.counters.first.staffId, 'cashier-a');
      expect(analysis.counters.first.counts, 3);
    });

    test('a counter rate is over their own counted lines', () {
      final analysis = fixtureStockCountsAnalysis();

      final b = analysis.counters.firstWhere((c) => c.staffId == 'cashier-b');
      expect(b.countedLines, 88);
      expect(b.varianceLines, 11);
      expect(b.varianceRate, closeTo(11 / 88, 0.0001));
    });
  });

  group('the shape of the period', () {
    test('counts are ordered oldest first, which is how a trend reads', () {
      final analysis = fixtureStockCountsAnalysis();

      expect(analysis.records.first.businessDate, '2026-08-15');
      expect(analysis.records.last.businessDate, '2026-09-22');
    });

    test('a category-scoped count is counted as one', () {
      final analysis = fixtureStockCountsAnalysis();

      expect(analysis.scopedCounts, 1);
      expect(analysis.counts, 6);
    });

    test('an unread earlier window is null, not empty', () {
      final analysis = fixtureStockCountsAnalysis();

      expect(analysis.previousCounts, isNull);

      final compared = fixtureStockCountsAnalysis(
        previous: const <TenantStockTakeRecord>[],
      );
      expect(
        compared.previousCounts,
        0,
        reason:
            'Zero is "nothing was counted then"; null is "that window could '
            'not be read". The report says different things about them.',
      );
    });
  });
}
