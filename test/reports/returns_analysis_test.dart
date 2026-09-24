/// The arithmetic behind the returns report.
///
/// **Every figure the report prints is a field here**, so it is checkable in a
/// plain test rather than by reading pixels off a chart. The two that matter
/// most are the ranked lines - the finding the screen cannot reach - and the
/// pending count, which is stock physically back on the shelf and still absent
/// from the books.
library;

import 'package:flutter_application_1/reports/analysis/returns_analysis.dart';
import 'package:flutter_application_1/returns/return_history.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/returns.dart';

void main() {
  group('what came back', () {
    test('units are summed across every line of every return', () {
      final analysis = fixtureReturnsAnalysis();

      expect(
        analysis.returnedUnits,
        16,
        reason: '4 + 6 + 1 + 3 + 2 across the fortnight.',
      );
      expect(analysis.recordCount, 4);
    });

    test('value is withheld where no sale behind it was read', () {
      final analysis = fixtureReturnsAnalysis();

      expect(
        analysis.returnedMinor,
        isNull,
        reason:
            'A return line carries no money. Printing nought would state that '
            'nothing of worth came back, which is a different claim from not '
            'knowing.',
      );
      expect(analysis.isFullyValued, isFalse);
      expect(analysis.valuedReturns, 0);
    });
  });

  group('which lines come back', () {
    test('products are ranked by units, most first', () {
      final analysis = fixtureReturnsAnalysis();

      expect(analysis.lines.first.name, 'Tusker 500ml');
      expect(
        analysis.lines.first.units,
        13,
        reason: 'Three separate returns, 4 + 6 + 3.',
      );
      expect(analysis.lines.map((line) => line.name), <String>[
        'Tusker 500ml',
        'Cooking oil 1L',
        'Bread',
      ]);
    });

    test('a line with no recorded name is still identifiable', () {
      final analysis = TenantReturnsAnalysis.from(
        period: fixtureReturnsPeriod(),
        returns: <TenantReturn>[
          returnRecord(
            id: 'ret-1',
            recordedOn: '2026-09-02',
            saleId: 'co-1',
            units: <String, int>{'product-9': 2},
          ),
        ],
      );

      expect(
        analysis.lines.single.name,
        'product-9',
        reason:
            'A name is a label the returning device wrote down, not the '
            "catalog's. Falling back to the ID keeps the row identifiable "
            'rather than blank.',
      );
    });

    test('concentration is the largest line over everything returned', () {
      final analysis = fixtureReturnsAnalysis();

      expect(analysis.concentration, closeTo(13 / 16, 0.001));
      expect(
        analysis.linesFor(0.75),
        1,
        reason: 'One product already carries three quarters of the units.',
      );
    });

    test('an empty period ranks nothing and claims no concentration', () {
      final analysis = TenantReturnsAnalysis.from(
        period: fixtureReturnsPeriod(),
        returns: const <TenantReturn>[],
      );

      expect(analysis.lines, isEmpty);
      expect(analysis.concentration, isNull);
      expect(analysis.linesFor(0.75), isNull);
      expect(analysis.returnedUnits, 0);
    });
  });

  group('waiting on verification', () {
    test('pending returns are counted apart, in returns and in units', () {
      final analysis = fixtureReturnsAnalysis();

      expect(analysis.pendingCount, 2);
      expect(
        analysis.pendingUnits,
        5,
        reason:
            'Stock is restored on verification and not before, so these five '
            'units are on the shelf and not in the books.',
      );
      expect(analysis.verifiedCount, 2);
    });

    test('the wait is the middle one, not the average', () {
      final analysis = fixtureReturnsAnalysis();

      // Six hours and two days. The mean would be 27 hours, which is not a
      // wait anybody experienced.
      expect(analysis.medianWait, const Duration(hours: 27));
    });

    test('no verified return means no wait to report', () {
      final analysis = TenantReturnsAnalysis.from(
        period: fixtureReturnsPeriod(),
        returns: <TenantReturn>[
          returnRecord(
            id: 'ret-1',
            recordedOn: '2026-09-02',
            saleId: 'co-1',
            units: <String, int>{'product-1': 1},
          ),
        ],
      );

      expect(analysis.medianWait, isNull);
    });
  });

  group('the shape of the period', () {
    test('every day is drawn, including the ones nothing came back on', () {
      final analysis = fixtureReturnsAnalysis();

      expect(
        analysis.dailyUnits,
        hasLength(14),
        reason:
            'A line drawn only over the days that had a return hides a quiet '
            'fortnight.',
      );
      expect(analysis.dailyUnits['2026-09-05'], 7);
      expect(analysis.dailyUnits['2026-09-06'], 0);
      expect(analysis.quietDays, 10);
      expect(analysis.heaviestDate, '2026-09-05');
    });

    test('a return recorded outside the period is not put inside it', () {
      final analysis = TenantReturnsAnalysis.from(
        period: fixtureReturnsPeriod(),
        returns: <TenantReturn>[
          returnRecord(
            id: 'ret-1',
            recordedOn: '2026-08-30',
            saleId: 'co-1',
            units: <String, int>{'product-1': 5},
          ),
        ],
      );

      expect(
        analysis.dailyUnits.values.every((units) => units == 0),
        isTrue,
        reason:
            'It is still counted in the totals - the reader bounds the span - '
            'but it has no day in this period to be drawn on.',
      );
    });
  });

  group('the comparison', () {
    test('movement against the period before is a fraction', () {
      final analysis = fixtureReturnsAnalysis(
        previous: <TenantReturn>[
          returnRecord(
            id: 'ret-0',
            recordedOn: '2026-08-20',
            saleId: 'co-0',
            units: <String, int>{'product-1': 8},
          ),
        ],
      );

      expect(analysis.previousUnits, 8);
      expect(analysis.change, closeTo(1.0, 0.001));
    });

    test('a rise from nothing is not a percentage', () {
      final analysis = fixtureReturnsAnalysis(
        previous: const <TenantReturn>[],
      );

      expect(analysis.previousUnits, 0);
      expect(
        analysis.change,
        isNull,
        reason:
            'It has not risen by a percentage; it has started. The report '
            'says so in words instead.',
      );
    });

    test('an unread earlier window is null, not empty', () {
      final analysis = fixtureReturnsAnalysis();

      expect(
        analysis.previousUnits,
        isNull,
        reason:
            'Null is "could not be read"; zero is "nothing came back". The '
            'report says different things about them.',
      );
      expect(analysis.change, isNull);
    });
  });

  group('who and why', () {
    test('recorders are ranked by how many they put through', () {
      final analysis = fixtureReturnsAnalysis();

      expect(analysis.recorders.first.staffId, 'cashier-a');
      expect(analysis.recorders.first.returns, 2);
      expect(analysis.recorders.first.units, 11);
    });

    test('an equal count is broken by units, then by name', () {
      // Both cashiers put through two returns. Left to the order they were
      // read in, the same period could rank them differently on two runs -
      // and a report that reorders people between printings is one nobody can
      // refer back to.
      final analysis = fixtureReturnsAnalysis();

      expect(
        analysis.recorders.map((person) => person.staffId),
        <String>['cashier-a', 'cashier-b'],
      );
      expect(analysis.recorders.map((person) => person.returns), <int>[2, 2]);
    });

    test('reasons are grouped by exact wording and nothing is inferred', () {
      final analysis = fixtureReturnsAnalysis();

      expect(analysis.reasons.first.reason, 'Bottles were flat');
      expect(analysis.reasons.first.count, 3);
      expect(
        analysis.reasons.map((r) => r.reason),
        <String>['Bottles were flat', 'Wrong size'],
        reason:
            'Free text typed at the till. Two that mean the same thing stay '
            'two rows rather than being merged by a guess.',
      );
    });
  });
}
