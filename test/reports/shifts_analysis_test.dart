/// The arithmetic behind the shifts report.
///
/// **The two rules under test are the ones easiest to get wrong and worst to
/// get wrong.** Short and over are never netted into a single figure, because
/// a day short and a day over is two days to look at rather than a level week;
/// and a shift with no comparison is counted apart rather than as balanced,
/// because a drawer nobody could check is not a drawer that balanced.
library;

import 'package:flutter_application_1/reports/analysis/shifts_analysis.dart';
import 'package:flutter_application_1/shift/shift_history.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shifts.dart';

void main() {
  group('where the difference sits', () {
    test('short and over are totalled apart, never netted away', () {
      final analysis = fixtureShiftsAnalysis();

      expect(analysis.shortMinor, 2000, reason: '500 and 1500.');
      expect(analysis.overMinor, 300);
      expect(
        analysis.netVarianceMinor,
        -1700,
        reason:
            'Offered beside the two, never instead of them. A week that '
            'netted to nought would report a shop with no cash problem.',
      );
    });

    test('the opening float comes back out of the comparison', () {
      // cashier-b counted 81300 into a drawer that started with 5000 of change
      // and took 76000. That is 300 over, not 5300.
      final analysis = fixtureShiftsAnalysis();

      final over = analysis.people.firstWhere((p) => p.overMinor > 0);
      expect(
        over.overMinor,
        300,
        reason:
            'Leaving the float in would have every floated till read as over '
            'by exactly that float, every day.',
      );
    });

    test('the worst shift is named, whichever way it went', () {
      final analysis = fixtureShiftsAnalysis();

      expect(analysis.worst?.shiftId, 'shift-3');
      expect(analysis.worst?.varianceMinor, -1500);
      expect(analysis.worst?.businessDate, '2026-09-03');
    });

    test('concentration is the largest short over everything short', () {
      final analysis = fixtureShiftsAnalysis();

      expect(
        analysis.shortConcentration,
        1.0,
        reason: 'One person carries all of it, which is the finding.',
      );
    });
  });

  group('what could not be compared', () {
    test('a shift closed without its sales has no variance at all', () {
      final analysis = fixtureShiftsAnalysis();

      expect(analysis.unevidencedShifts, 1);
      expect(
        analysis.comparedShifts,
        4,
        reason:
            'Five closed, one of them unevidenced. Counting that one as level '
            'would be the most confident possible statement about the one '
            'shift nobody can make any statement about.',
      );
      expect(analysis.isFullyCompared, isFalse);
    });

    test('an open shift is kept and counted apart', () {
      final analysis = fixtureShiftsAnalysis();

      expect(analysis.openCount, 1);
      expect(analysis.closedCount, 5);
      expect(analysis.shiftCount, 6);
      expect(
        analysis.uncomparedShifts,
        0,
        reason:
            'Still running is not the same as closed with nothing to compare. '
            'The report says different things about them.',
      );
    });

    test('a closed shift with no declaration is uncompared, not level', () {
      final analysis = TenantShiftsAnalysis.from(
        period: fixtureShiftsPeriod(),
        shifts: <TenantShiftDaySlice>[
          shiftRecord(
            id: 'shift-1',
            businessDate: '2026-09-01',
            staffId: 'cashier-a',
            takingsMinor: 50000,
          ),
        ],
      );

      expect(analysis.uncomparedShifts, 1);
      expect(analysis.comparedShifts, 0);
      expect(analysis.shortMinor, 0);
      expect(analysis.overMinor, 0);
    });

    test('a person whose every shift was unevidenced shows no variance', () {
      final analysis = fixtureShiftsAnalysis();

      final b = analysis.people.firstWhere((p) => p.staffId == 'cashier-b');
      expect(b.unevidencedShifts, 1);
      expect(
        b.comparedShifts,
        1,
        reason: 'One of their two shifts could be compared.',
      );
    });
  });

  group('takings', () {
    test('only closed shifts with a summary contribute', () {
      final analysis = fixtureShiftsAnalysis();

      expect(
        analysis.takingsMinor,
        404000,
        reason: '120000 + 98000 + 110000 + 76000. The open shift took nothing '
            'this report can see and the unevidenced one recorded nothing.',
      );
      expect(analysis.transactions, 48);
    });

    test('every day is drawn, including the ones nothing was taken on', () {
      final analysis = fixtureShiftsAnalysis();

      expect(analysis.dailyTakingsMinor, hasLength(7));
      expect(analysis.dailyTakingsMinor['2026-09-06'], 0);
      expect(analysis.quietDays, 3);
    });

    test('mean takings are per closed shift, not per day', () {
      final analysis = fixtureShiftsAnalysis();

      expect(analysis.takingsPerShiftMinor, closeTo(404000 / 5, 0.01));
    });

    test('movement against the period before is a fraction', () {
      final analysis = fixtureShiftsAnalysis(
        previous: <TenantShiftDaySlice>[
          shiftRecord(
            id: 'shift-0',
            businessDate: '2026-08-25',
            staffId: 'cashier-a',
            takingsMinor: 202000,
            declaredMinor: 202000,
          ),
        ],
      );

      expect(analysis.previousTakingsMinor, 202000);
      expect(analysis.change, closeTo(1.0, 0.001));
    });

    test('an unread earlier window is null, not empty', () {
      final analysis = fixtureShiftsAnalysis();

      expect(analysis.previousTakingsMinor, isNull);
      expect(analysis.change, isNull);
    });
  });

  group('per person', () {
    test('people are ranked by what is short, most first', () {
      final analysis = fixtureShiftsAnalysis();

      expect(analysis.people.first.staffId, 'cashier-a');
      expect(analysis.people.first.shortMinor, 2000);
      expect(analysis.people.first.shifts, 4);
    });

    test('takings per hour needs both instants', () {
      final analysis = fixtureShiftsAnalysis();

      final a = analysis.people.first;
      expect(
        a.minutesOnShift,
        greaterThan(0),
        reason: 'Three closed twelve-hour shifts, and one still running.',
      );
      expect(a.takingsPerHourMinor, isNotNull);
    });

    test('a person with no closed shift reports no rate', () {
      final analysis = TenantShiftsAnalysis.from(
        period: fixtureShiftsPeriod(),
        shifts: <TenantShiftDaySlice>[
          shiftRecord(
            id: 'shift-1',
            businessDate: '2026-09-01',
            staffId: 'cashier-a',
            open: true,
          ),
        ],
      );

      expect(analysis.people.single.takingsPerHourMinor, isNull);
    });
  });

  group('an empty period', () {
    test('claims nothing at all', () {
      final analysis = TenantShiftsAnalysis.from(
        period: fixtureShiftsPeriod(),
        shifts: const <TenantShiftDaySlice>[],
      );

      expect(analysis.shiftCount, 0);
      expect(analysis.people, isEmpty);
      expect(analysis.worst, isNull);
      expect(analysis.takingsPerShiftMinor, isNull);
      expect(analysis.shortConcentration, isNull);
      expect(
        analysis.isFullyCompared,
        isFalse,
        reason:
            'Nothing was compared, which is not the same as everything having '
            'been compared and agreed.',
      );
    });
  });
}
