/// What a period's shifts say about the drawer, beyond one day's badges.
///
/// **The finding is where the difference sits.** The shift screen shows one
/// day at a time and puts a badge on each row; a fortnight of badges is not a
/// pattern anybody can hold in their head. What a period can say is that of
/// everything short over these days, most of it is on one person, or one
/// weekday, or one shift - and that is a question somebody can actually go and
/// ask.
///
/// **Short and over are never netted.** A day a hundred short and a day a
/// hundred over is not a level fortnight; it is two days that need looking at.
/// Summing them to nought would report a business with no cash problem, so the
/// two run as separate totals and the net is offered beside them rather than
/// instead of them.
///
/// **Null is not nought.** A shift closed without its sales has no variance at
/// all - see `_cashVarianceMinor` - and counting it as balanced would be the
/// most confident possible statement about the one shift nobody can make any
/// statement about. Those are counted apart and excluded from every total.
///
/// Pure arithmetic, no I/O, no Flutter.
library;

import '../../shift/shift_history.dart';
import '../report_period.dart';

/// One person's shifts over the period.
final class TenantShiftPerson {
  const TenantShiftPerson({
    required this.staffId,
    required this.shifts,
    required this.takingsMinor,
    required this.transactions,
    required this.shortMinor,
    required this.overMinor,
    required this.comparedShifts,
    required this.unevidencedShifts,
    required this.minutesOnShift,
  });

  final String staffId;
  final int shifts;
  final int takingsMinor;
  final int transactions;

  /// What this person's drawers came up short, as a positive figure.
  final int shortMinor;

  /// What they came up over, as a positive figure.
  final int overMinor;

  /// How many of [shifts] could be compared at all.
  final int comparedShifts;

  /// Shifts closed by something holding none of their sales.
  final int unevidencedShifts;

  /// Time on shift, where both instants were recorded.
  final int minutesOnShift;

  /// Short minus over, which is the net position.
  int get netVarianceMinor => overMinor - shortMinor;

  /// Takings per hour, or null where no shift recorded both its instants.
  double? get takingsPerHourMinor {
    if (minutesOnShift <= 0) return null;
    return takingsMinor / (minutesOnShift / 60);
  }
}

/// One shift worth naming, because its drawer was the furthest out.
final class TenantShiftOutlier {
  const TenantShiftOutlier({
    required this.shiftId,
    required this.staffId,
    required this.businessDate,
    required this.varianceMinor,
  });

  final String shiftId;
  final String staffId;
  final String businessDate;

  /// Negative is short, positive is over.
  final int varianceMinor;
}

/// A period's shifts, with the period before it for company.
final class TenantShiftsAnalysis {
  const TenantShiftsAnalysis._({
    required this.period,
    required this.shiftCount,
    required this.closedCount,
    required this.openCount,
    required this.takingsMinor,
    required this.transactions,
    required this.shortMinor,
    required this.overMinor,
    required this.comparedShifts,
    required this.unevidencedShifts,
    required this.uncomparedShifts,
    required this.people,
    required this.dailyTakingsMinor,
    required this.worst,
    required this.previousTakingsMinor,
    required this.truncated,
  });

  /// How many rows a page lists before the rest is left to the workbook.
  static const int listed = 20;

  factory TenantShiftsAnalysis.from({
    required TenantReportPeriod period,
    required List<TenantShiftDaySlice> shifts,
    List<TenantShiftDaySlice>? previous,
    bool truncated = false,
  }) {
    final people = <String, _Running>{};
    final daily = <String, int>{
      for (final date in period.businessDates) date: 0,
    };

    var closedCount = 0;
    var openCount = 0;
    var takings = 0;
    var transactions = 0;
    var short = 0;
    var over = 0;
    var compared = 0;
    var unevidenced = 0;
    var uncompared = 0;
    TenantShiftOutlier? worst;

    for (final slice in shifts) {
      final running = people[slice.staffId] ?? _Running();
      people[slice.staffId] = running;
      running.shifts++;

      if (slice.isOpen) {
        openCount++;
      } else {
        closedCount++;
      }

      if (slice.summary case final summary?) {
        takings += summary.totalSalesMinor;
        transactions += summary.transactionCount;
        running.takings += summary.totalSalesMinor;
        running.transactions += summary.transactionCount;
        if (daily.containsKey(slice.businessDate)) {
          daily[slice.businessDate] =
              daily[slice.businessDate]! + summary.totalSalesMinor;
        }
      }

      final started = slice.startedAt;
      final ended = slice.endedAt;
      if (started != null && ended != null && ended.isAfter(started)) {
        running.minutes += ended.difference(started).inMinutes;
      }

      if (slice.shift.closedWithoutEvidence) {
        unevidenced++;
        running.unevidenced++;
        continue;
      }
      // An open shift has nothing to compare yet; that is not a shortfall in
      // the record, so it is counted apart from one that closed unevidenced.
      if (slice.isOpen) continue;

      final variance = slice.cashVarianceMinor;
      if (variance == null) {
        uncompared++;
        continue;
      }
      compared++;
      running.compared++;
      if (variance < 0) {
        short += -variance;
        running.short += -variance;
      } else if (variance > 0) {
        over += variance;
        running.over += variance;
      }
      if (worst == null || variance.abs() > worst.varianceMinor.abs()) {
        worst = TenantShiftOutlier(
          shiftId: slice.id,
          staffId: slice.staffId,
          businessDate: slice.businessDate,
          varianceMinor: variance,
        );
      }
    }

    final ranked =
        <TenantShiftPerson>[
          for (final entry in people.entries)
            TenantShiftPerson(
              staffId: entry.key,
              shifts: entry.value.shifts,
              takingsMinor: entry.value.takings,
              transactions: entry.value.transactions,
              shortMinor: entry.value.short,
              overMinor: entry.value.over,
              comparedShifts: entry.value.compared,
              unevidencedShifts: entry.value.unevidenced,
              minutesOnShift: entry.value.minutes,
            ),
        ]..sort((a, b) {
          // Most short first: this report is read to find the drawer that is
          // losing money, and ties fall back to takings and then to the name
          // so two people are never ordered by chance.
          final byShort = b.shortMinor.compareTo(a.shortMinor);
          if (byShort != 0) return byShort;
          final byTakings = b.takingsMinor.compareTo(a.takingsMinor);
          return byTakings != 0 ? byTakings : a.staffId.compareTo(b.staffId);
        });

    return TenantShiftsAnalysis._(
      period: period,
      shiftCount: shifts.length,
      closedCount: closedCount,
      openCount: openCount,
      takingsMinor: takings,
      transactions: transactions,
      shortMinor: short,
      overMinor: over,
      comparedShifts: compared,
      unevidencedShifts: unevidenced,
      uncomparedShifts: uncompared,
      people: List<TenantShiftPerson>.unmodifiable(ranked),
      dailyTakingsMinor: Map<String, int>.unmodifiable(daily),
      worst: worst,
      previousTakingsMinor: previous?.fold<int>(
        0,
        (sum, slice) => sum + (slice.summary?.totalSalesMinor ?? 0),
      ),
      truncated: truncated,
    );
  }

  final TenantReportPeriod period;

  final int shiftCount;
  final int closedCount;

  /// Shifts still running at the moment the report was taken.
  ///
  /// **A fact about the period, not a defect.** A drawer nobody has counted is
  /// money nobody has settled, and a report that quietly left these out would
  /// show the days as reconciled when one of them is not.
  final int openCount;

  final int takingsMinor;
  final int transactions;

  /// What the drawers came up short over the period, as a positive figure.
  final int shortMinor;

  /// What they came up over, as a positive figure.
  final int overMinor;

  /// How many shifts could be compared at all.
  final int comparedShifts;

  /// Shifts closed by something holding none of their sales.
  final int unevidencedShifts;

  /// Closed shifts with no comparison for another reason - no declaration, or
  /// a record written before the summary existed.
  final int uncomparedShifts;

  final List<TenantShiftPerson> people;

  /// Takings on each day of the period, empty days included.
  final Map<String, int> dailyTakingsMinor;

  /// The single shift whose drawer was furthest out, either way.
  final TenantShiftOutlier? worst;

  final int? previousTakingsMinor;

  final bool truncated;

  /// Short minus over. Offered beside the two, never instead of them.
  int get netVarianceMinor => overMinor - shortMinor;

  /// Whether every closed shift in the period could be compared.
  bool get isFullyCompared =>
      unevidencedShifts == 0 && uncomparedShifts == 0 && closedCount > 0;

  /// How far takings moved against the period before, as a fraction.
  double? get change {
    final before = previousTakingsMinor;
    if (before == null || before == 0) return null;
    return (takingsMinor - before) / before;
  }

  /// The share of everything short that sits on one person, or null where
  /// nothing was short.
  double? get shortConcentration {
    if (shortMinor == 0 || people.isEmpty) return null;
    return people.first.shortMinor / shortMinor;
  }

  /// Mean takings per closed shift, or null where none closed.
  double? get takingsPerShiftMinor {
    if (closedCount == 0) return null;
    return takingsMinor / closedCount;
  }

  /// Days in the period on which no shift took anything.
  int get quietDays =>
      dailyTakingsMinor.values.where((minor) => minor == 0).length;
}

/// Mutable running totals, so the loop above stays one pass.
final class _Running {
  int shifts = 0;
  int takings = 0;
  int transactions = 0;
  int short = 0;
  int over = 0;
  int compared = 0;
  int unevidenced = 0;
  int minutes = 0;
}
