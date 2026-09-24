/// What a period's spending says, beyond what it totals.
///
/// **This is the line between a report and an export.** The expenses screen
/// already shows a total and a ring of categories; printing the same two things
/// on paper would be a screenshot with a letterhead. What a person cannot get
/// from the screen is the comparison: which headings moved against the weeks
/// before, how concentrated the spending is, which days carried it, and whether
/// the biggest single item is an outlier or the normal shape of the month.
/// That is what this computes.
///
/// **Pure arithmetic, no I/O, no Flutter.** It takes two periods that have
/// already been read and returns figures. Every number the report prints is a
/// field here, so every number the report prints is checkable in a plain test
/// rather than by reading pixels off a chart.
library;

import '../../expenses/expense.dart';
import '../report_period.dart';

/// One heading's spend, against the same heading last period.
final class TenantExpenseHeading {
  const TenantExpenseHeading({
    required this.category,
    required this.minor,
    required this.previousMinor,
    required this.share,
  });

  final TenantExpenseCategory category;

  final int minor;

  /// The same heading over the preceding comparable period.
  final int previousMinor;

  /// This heading's share of the period's whole, as a fraction.
  final double share;

  /// How far it moved, as a fraction, or null where it is a rise from nothing.
  ///
  /// **Null rather than infinity.** A heading that went from no spend to some
  /// spend has not risen by a percentage; it has started. The report says
  /// "new this period" instead, which is the actual finding.
  double? get change {
    if (previousMinor == 0) return null;
    return (minor - previousMinor) / previousMinor.abs();
  }

  bool get isNew => previousMinor == 0 && minor > 0;

  bool get hasStopped => previousMinor > 0 && minor == 0;
}

/// A period's spending, with the period before it for company.
final class TenantExpenseAnalysis {
  const TenantExpenseAnalysis._({
    required this.period,
    required this.totalMinor,
    required this.previousTotalMinor,
    required this.headings,
    required this.dailyMinor,
    required this.largest,
    required this.biggest,
    required this.voidedCount,
    required this.voidedMinor,
    required this.recordCount,
    required this.truncated,
  });

  /// How many individual items a report lists before leaving the rest to the
  /// workbook.
  static const int listedItems = 20;

  /// Computes the analysis from two already-read periods.
  ///
  /// [previous] may be null where the earlier window was not read - a report
  /// then prints its figures without comparisons rather than inventing them.
  factory TenantExpenseAnalysis.from({
    required TenantReportPeriod period,
    required TenantExpensePeriod spending,
    TenantExpensePeriod? previous,
  }) {
    final total = spending.totalMinor;
    final headings = <TenantExpenseHeading>[
      for (final category in TenantExpenseCategory.values)
        TenantExpenseHeading(
          category: category,
          minor: spending.totalByCategory[category] ?? 0,
          previousMinor: previous?.totalByCategory[category] ?? 0,
          share: total == 0
              ? 0
              : (spending.totalByCategory[category] ?? 0) / total,
        ),
    ]..sort((a, b) => b.minor.compareTo(a.minor));

    final live = spending.records.where((r) => !r.isVoided).toList();
    final voided = spending.records.where((r) => r.isVoided).toList();

    return TenantExpenseAnalysis._(
      period: period,
      totalMinor: total,
      previousTotalMinor: previous?.totalMinor,
      headings: List<TenantExpenseHeading>.unmodifiable(headings),
      // Every day in the period, including the ones with no spending. A chart
      // drawn only over the days that had a record hides a quiet fortnight.
      dailyMinor: Map<String, int>.unmodifiable(<String, int>{
        for (final date in period.businessDates)
          date: spending.totalMinorOn(date),
      }),
      largest: live.isEmpty
          ? null
          : live.reduce((a, b) => b.amountMinor > a.amountMinor ? b : a),
      // Voided items are kept in this listing, marked, because the list is the
      // record of what was entered rather than a total. They are excluded from
      // every figure above.
      biggest: List<TenantExpense>.unmodifiable(
        (spending.records.toList()
              ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor)))
            .take(listedItems),
      ),
      voidedCount: voided.length,
      voidedMinor: voided.fold(0, (sum, r) => sum + r.amountMinor),
      recordCount: spending.records.length,
      truncated: spending.truncated,
    );
  }

  final TenantReportPeriod period;

  final int totalMinor;

  /// The preceding comparable period's total, or null where it was not read.
  final int? previousTotalMinor;

  /// Every category, largest first, including the ones with no spend.
  ///
  /// **The empty ones are kept deliberately.** A heading a business spent
  /// nothing under this period but did last period is a finding, and dropping
  /// it would make the report silent about a cost that stopped.
  final List<TenantExpenseHeading> headings;

  /// Spend per business date, gaps included.
  final Map<String, int> dailyMinor;

  /// The single biggest item, or null where nothing was spent.
  final TenantExpense? largest;

  /// The largest items of the period, biggest first, voided ones included and
  /// marked. At most [listedItems].
  final List<TenantExpense> biggest;

  final int voidedCount;

  /// What the voided records would have come to. Counted, never totalled in:
  /// it is money that did not leave the business.
  final int voidedMinor;

  final int recordCount;

  final bool truncated;

  /// The headings anything was actually spent under, largest first.
  List<TenantExpenseHeading> get spent =>
      headings.where((h) => h.minor > 0).toList();

  /// Headings that had spend last period and none this one.
  List<TenantExpenseHeading> get stopped =>
      headings.where((h) => h.hasStopped).toList();

  /// Headings with spend this period and none before it.
  List<TenantExpenseHeading> get started =>
      headings.where((h) => h.isNew).toList();

  /// How far the whole moved, or null where there is nothing to compare.
  double? get change {
    final was = previousTotalMinor;
    if (was == null || was == 0) return null;
    return (totalMinor - was) / was.abs();
  }

  /// The largest heading's share of the whole, or null where nothing was spent.
  double? get concentration {
    if (totalMinor <= 0) return null;
    return spent.first.share;
  }

  /// How many headings it takes to pass [fraction] of the whole.
  int? headingsFor(double fraction) {
    if (totalMinor <= 0) return null;
    var running = 0;
    for (final (index, heading) in spent.indexed) {
      running += heading.minor;
      if (running / totalMinor >= fraction) return index + 1;
    }
    return spent.length;
  }

  /// The mean spend across every day of the period, including empty ones.
  ///
  /// Across *every* day rather than only the days with spending, because the
  /// question a reader has is what the month costs to run, and the quiet days
  /// are part of the month.
  double get dailyMean =>
      dailyMinor.isEmpty ? 0 : totalMinor / dailyMinor.length;

  /// The business date the most was spent on, or null where nothing was.
  String? get heaviestDate {
    if (totalMinor <= 0) return null;
    var heaviest = dailyMinor.entries.first;
    for (final entry in dailyMinor.entries) {
      if (entry.value > heaviest.value) heaviest = entry;
    }
    return heaviest.value == 0 ? null : heaviest.key;
  }

  /// Days in the period on which nothing at all was spent.
  int get quietDays => dailyMinor.values.where((minor) => minor == 0).length;
}
