import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A Thursday in the Nairobi business day, so the week in progress has four
  // days behind it and three still to come.
  final thursday = DateTime.utc(2026, 8, 27, 9);

  group('the report week', () {
    test('runs Monday to Sunday in business time', () {
      final week = TenantReportWeek.at(thursday);

      expect(week.startBusinessDate, '2026-08-24');
      expect(week.endBusinessDate, '2026-08-30');
      expect(week.businessDates.first, '2026-08-24');
      expect(week.businessDates.last, '2026-08-30');
      expect(week.businessDates, hasLength(7));
      expect(week.isCurrent, isTrue);
    });

    test('is cut on the business boundary, not the device clock', () {
      // 22:30 UTC on Sunday is already Monday in Nairobi, so it belongs to the
      // week that is starting rather than the one that just ended.
      final lateSunday = DateTime.utc(2026, 8, 23, 22, 30);

      expect(TenantReportWeek.at(lateSunday).startBusinessDate, '2026-08-24');
    });

    test('steps back a week at a time', () {
      final before = TenantReportWeek.at(thursday).previous;

      expect(before.offset, -1);
      expect(before.startBusinessDate, '2026-08-17');
      expect(before.endBusinessDate, '2026-08-23');
      expect(before.isCurrent, isFalse);
    });

    test('offers only the days that have happened', () {
      final week = TenantReportWeek.at(thursday);

      // Monday to Thursday. The totals callable refuses a future business date
      // outright, so asking for Friday would fail the whole page.
      expect(week.elapsedBusinessDates(thursday), <String>[
        '2026-08-24',
        '2026-08-25',
        '2026-08-26',
        '2026-08-27',
      ]);
      expect(week.endBusinessDateAt(thursday), '2026-08-27');
    });

    test('a finished week offers all seven days', () {
      final week = TenantReportWeek.at(thursday).previous;

      expect(week.elapsedBusinessDates(thursday), hasLength(7));
      expect(week.endBusinessDateAt(thursday), '2026-08-23');
    });
  });

  group('the comparison', () {
    test('reads as a percentage of the week before', () {
      expect(TenantWeeklyReport.change(120, 100), closeTo(20, 0.001));
      expect(TenantWeeklyReport.change(80, 100), closeTo(-20, 0.001));
    });

    test('is withheld where there is nothing to compare against', () {
      // A week that took nothing is not a 100% fall from one that did; it is a
      // division by zero, and the card drops its arrow rather than inventing
      // a figure.
      expect(TenantWeeklyReport.change(120, 0), isNull);
      expect(TenantWeeklyReport.change(120, null), isNull);
    });
  });

  group('the average sale', () {
    test('is the takings over the sales that produced them', () {
      final report = _report(sales: 900, transactions: 9);

      expect(report.averageSale, closeTo(100, 0.001));
    });

    test('is zero rather than a division by zero on an empty week', () {
      expect(_report(sales: 0, transactions: 0).averageSale, 0);
    });
  });
}

TenantWeeklyReport _report({required double sales, required int transactions}) {
  return TenantWeeklyReport(
    week: TenantReportWeek.at(DateTime.utc(2026, 8, 27, 9)),
    totals: TenantSalesTotals.summed(
      query: _query(),
      sales: sales,
      profit: sales / 4,
      transactions: transactions,
      incompleteCostLineCount: 0,
    ),
    previousTotals: null,
    revenueByWeekday: List<double>.filled(7, 0),
    topItems: const <TenantReportItem>[],
    recentSales: const [],
    itemsSold: 0,
    scanWasTruncated: false,
  );
}

TenantSalesTotalsQuery _query() => TenantSalesTotalsGateway(
  session: _session(),
  callable: _NullCallable(),
  clock: () => DateTime.utc(2026, 8, 27, 9),
).createBusinessDateQuery(businessDate: '2026-08-27');

TenantSession _session() => TenantSession.active(
  uid: 'user-a',
  tenantId: 'tenant-a',
  role: TenantRole.owner,
);

final class _NullCallable implements SalesTotalsCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async => null;
}
