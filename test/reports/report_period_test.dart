/// What a report period covers, and what it calls itself.
///
/// The arithmetic here is load-bearing for all eight reports: a period decides
/// which days are read, which days are charted, and which earlier window every
/// comparison is drawn against. All of it is pure, so all of it is checked
/// here rather than inferred from a picture later.
library;

import 'package:flutter_application_1/reports/report_period.dart';
import 'package:flutter_test/flutter_test.dart';

/// Noon UTC on 22 September 2026, which is 15:00 in the business day.
DateTime _clock() => DateTime.utc(2026, 9, 22, 12);

/// Half past nine at night UTC, which is already the 23rd in Nairobi.
///
/// The business day runs three hours ahead of UTC, so this instant proves the
/// period follows the trading day rather than the clock the server keeps.
DateTime _lateEvening() => DateTime.utc(2026, 9, 22, 21, 30);

void main() {
  group('the days a period covers', () {
    test('a single day covers itself and nothing else', () {
      final period = TenantReportPeriod.day('2026-09-22');

      expect(
        period.businessDates,
        <String>['2026-09-22'],
        reason: 'A one-day report reads one day.',
      );
      expect(period.days, 1);
      expect(
        period.isSingleDay,
        isTrue,
        reason: 'The picker shows a day control rather than a range for this.',
      );
    });

    test('a span carries every day in it, including ones with no trading', () {
      final period = TenantReportPeriod(
        startDate: '2026-09-20',
        endDate: '2026-09-24',
      );

      expect(
        period.businessDates,
        <String>[
          '2026-09-20',
          '2026-09-21',
          '2026-09-22',
          '2026-09-23',
          '2026-09-24',
        ],
        reason:
            'A closed Sunday is a fact about the business. Charting only the '
            'days that had records would hide it.',
      );
      expect(period.days, 5);
    });

    test('a span crosses a month boundary without losing a day', () {
      final period = TenantReportPeriod(
        startDate: '2026-08-30',
        endDate: '2026-09-02',
      );

      expect(period.businessDates, <String>[
        '2026-08-30',
        '2026-08-31',
        '2026-09-01',
        '2026-09-02',
      ], reason: 'August has 31 days and the walk must know it.');
    });

    test('a span crosses a leap day', () {
      final period = TenantReportPeriod(
        startDate: '2028-02-27',
        endDate: '2028-03-01',
      );

      expect(
        period.businessDates,
        <String>['2028-02-27', '2028-02-28', '2028-02-29', '2028-03-01'],
        reason:
            '2028 is a leap year, and the arithmetic gets that from DateTime '
            'rather than from a table somebody has to maintain.',
      );
    });

    test('covers answers for the ends as well as the middle', () {
      final period = TenantReportPeriod(
        startDate: '2026-09-01',
        endDate: '2026-09-30',
      );

      expect(period.covers('2026-09-01'), isTrue, reason: 'Inclusive at both');
      expect(period.covers('2026-09-30'), isTrue, reason: 'ends, deliberately.');
      expect(period.covers('2026-08-31'), isFalse);
      expect(period.covers('2026-10-01'), isFalse);
    });

    test('a period that starts after it ends is refused', () {
      expect(
        () => TenantReportPeriod(
          startDate: '2026-09-22',
          endDate: '2026-09-01',
        ),
        throwsArgumentError,
        reason:
            'A backwards period would read nothing and report it as a total, '
            'which is the one failure a report must never have.',
      );
    });

    test('a date that is not a business date is refused', () {
      expect(
        () => TenantReportPeriod.day('22-09-2026'),
        throwsArgumentError,
        reason: 'Business dates are yyyy-MM-dd everywhere in this app.',
      );
    });
  });

  group('the business day, not the calendar day', () {
    test('today follows the trading day', () {
      expect(
        TenantReportPeriod.today(_clock()).startDate,
        '2026-09-22',
        reason: 'Noon UTC is mid-afternoon in the shop, still the 22nd.',
      );
    });

    test('late evening UTC is already the next trading day', () {
      expect(
        TenantReportPeriod.today(_lateEvening()).startDate,
        '2026-09-23',
        reason:
            'The business day runs three hours ahead. A report asked for at '
            'half nine at night belongs to the day the shop is now in.',
      );
    });
  });

  group('the preset periods', () {
    test('the last seven days includes today', () {
      final period = TenantReportPeriod.lastDays(7, _clock());

      expect(period.startDate, '2026-09-16');
      expect(period.endDate, '2026-09-22');
      expect(
        period.days,
        7,
        reason: 'Seven days means seven, with today as one of them.',
      );
    });

    test('a single-day preset is the same thing as today', () {
      expect(
        TenantReportPeriod.lastDays(1, _clock()),
        TenantReportPeriod.today(_clock()),
        reason: 'Two routes to the same period produce equal periods.',
      );
    });

    test('a preset of no days at all is refused', () {
      expect(() => TenantReportPeriod.lastDays(0, _clock()), throwsArgumentError);
    });

    test('this month runs to today, not to the end of the month', () {
      final period = TenantReportPeriod.monthOf(_clock());

      expect(period.startDate, '2026-09-01');
      expect(
        period.endDate,
        '2026-09-22',
        reason:
            'Running to the 30th would report eight days that have not '
            'happened as eight days with no takings.',
      );
    });
  });

  group('the comparison window', () {
    test('a month to date is compared against the same number of days before', () {
      final period = TenantReportPeriod.monthOf(_clock());
      final before = period.precedingComparable;

      expect(before.days, period.days, reason: 'Equal length, or it is not a');
      expect(before.endDate, '2026-08-31', reason: 'comparison.');
      expect(before.startDate, '2026-08-10');
    });

    test('a single day is compared against the day before it', () {
      final before = TenantReportPeriod.day('2026-09-01').precedingComparable;

      expect(
        before,
        TenantReportPeriod.day('2026-08-31'),
        reason: 'The window before the first of the month is the last of the '
            'month before, not the 31st of September.',
      );
    });

    test('a week is compared against the week before it', () {
      final period = TenantReportPeriod.lastDays(7, _clock());
      final before = period.precedingComparable;

      expect(before.startDate, '2026-09-09');
      expect(before.endDate, '2026-09-15');
      expect(
        before.endDate.compareTo(period.startDate) < 0,
        isTrue,
        reason: 'The windows must not overlap, or a day would be counted twice.',
      );
    });
  });

  group('what a period calls itself', () {
    test('the four shapes people pick have names', () {
      expect(TenantReportPeriod.today(_clock()).label(_clock()), 'Today');
      expect(
        TenantReportPeriod.day('2026-09-21').label(_clock()),
        'Yesterday',
      );
      expect(TenantReportPeriod.monthOf(_clock()).label(_clock()), 'This month');
      expect(
        TenantReportPeriod.lastDays(7, _clock()).label(_clock()),
        'Last 7 days',
      );
    });

    test('anything else is written as a plain span', () {
      expect(
        TenantReportPeriod(
          startDate: '2026-09-03',
          endDate: '2026-09-11',
        ).label(_clock()),
        '3 Sep - 11 Sep',
      );
    });

    test('an older single day is named rather than called yesterday', () {
      expect(
        TenantReportPeriod.day('2026-07-04').label(_clock()),
        '4 Jul 2026',
        reason: 'A day far enough back needs its year to be unambiguous.',
      );
    });

    test('paper spells the period out even when a control abbreviates it', () {
      final period = TenantReportPeriod.monthOf(_clock());

      expect(
        period.label(_clock()),
        'This month',
        reason: 'The person picking it knows which month they are in.',
      );
      expect(
        period.spelled,
        '1 Sep 2026 to 22 Sep 2026',
        reason:
            'The accountant opening the file six months later does not, so '
            'the document never says "this month".',
      );
    });

    test('a filename fragment sorts by date', () {
      expect(TenantReportPeriod.day('2026-09-22').slug, '2026-09-22');
      expect(
        TenantReportPeriod(
          startDate: '2026-09-01',
          endDate: '2026-09-22',
        ).slug,
        '2026-09-01-to-2026-09-22',
        reason:
            'Leading with the year means a folder of these sorts into order '
            'on its own.',
      );
    });
  });
}
