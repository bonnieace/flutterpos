/// What a period's stock counts say about how well the books are kept.
///
/// **The finding is the count that was taken and never applied.** A submitted
/// count with variances on it is a shelf somebody walked and a correction
/// nobody made: the shop knows its books are wrong and the books are still
/// wrong. The review screen shows one count at a time with an *Apply* button;
/// only a period can say how many are sitting there and what they add up to.
///
/// **The second is whether counting is getting better or worse.** The share of
/// counted lines that disagreed with the books is a measure of the whole
/// stock-keeping operation, and it means nothing from one count - it means
/// something across six.
///
/// **An uncounted line is not a variance.** Products in scope that nobody
/// wrote a number against are unknown, not agreed - see
/// [TenantStockTakeRecord.uncountedLineCount], which makes the same point. They
/// are counted apart and never fold into an accuracy figure.
///
/// Pure arithmetic, no I/O, no Flutter.
library;

import '../../inventory/stock_take_review.dart';
import '../report_period.dart';

/// One person's counting over the period.
final class TenantStockCounter {
  const TenantStockCounter({
    required this.staffId,
    required this.counts,
    required this.countedLines,
    required this.varianceLines,
    required this.varianceUnits,
    required this.uncountedLines,
  });

  final String staffId;
  final int counts;
  final int countedLines;
  final int varianceLines;
  final int varianceUnits;
  final int uncountedLines;

  /// The share of this person's counted lines that disagreed with the books.
  ///
  /// Null where they counted nothing - a rate over no lines is not a rate.
  double? get varianceRate {
    if (countedLines == 0) return null;
    return varianceLines / countedLines;
  }
}

/// A period's stock counts.
final class TenantStockCountsAnalysis {
  const TenantStockCountsAnalysis._({
    required this.period,
    required this.counts,
    required this.appliedCount,
    required this.awaitingApply,
    required this.stillArriving,
    required this.awaitingVarianceLines,
    required this.awaitingVarianceUnits,
    required this.countedLines,
    required this.varianceLines,
    required this.varianceUnits,
    required this.uncountedLines,
    required this.unmatchedLines,
    required this.counters,
    required this.records,
    required this.scopedCounts,
    required this.previousCounts,
    required this.truncated,
  });

  /// How many rows a page lists before the rest is left to the workbook.
  static const int listed = 20;

  factory TenantStockCountsAnalysis.from({
    required TenantReportPeriod period,
    required List<TenantStockTakeRecord> takes,
    List<TenantStockTakeRecord>? previous,
    bool truncated = false,
  }) {
    final counters = <String, _Running>{};

    var applied = 0;
    var awaiting = 0;
    var arriving = 0;
    var awaitingVarianceLines = 0;
    var awaitingVarianceUnits = 0;
    var countedLines = 0;
    var varianceLines = 0;
    var varianceUnits = 0;
    var uncounted = 0;
    var unmatched = 0;
    var scoped = 0;

    for (final take in takes) {
      final running = counters[take.counterUid] ?? _Running();
      counters[take.counterUid] = running;
      running.counts++;
      running.countedLines += take.countedLineCount;
      running.varianceLines += take.varianceLineCount;
      running.varianceUnits += take.absoluteVarianceUnits;
      running.uncounted += take.uncountedLineCount;

      countedLines += take.countedLineCount;
      varianceLines += take.varianceLineCount;
      varianceUnits += take.absoluteVarianceUnits;
      uncounted += take.uncountedLineCount;
      unmatched += take.unmatchedLineCount;
      if (take.categoryId != null) scoped++;

      switch (take.status) {
        case TenantStockTakeStatus.applied:
          applied++;
        case TenantStockTakeStatus.submitted:
          awaiting++;
          // Only a submitted count's variances are still outstanding: an
          // applied one has already been written to the ledger, and one still
          // arriving cannot be applied at all.
          awaitingVarianceLines += take.varianceLineCount;
          awaitingVarianceUnits += take.absoluteVarianceUnits;
        case TenantStockTakeStatus.submitting:
          arriving++;
      }
    }

    final ranked =
        <TenantStockCounter>[
          for (final entry in counters.entries)
            TenantStockCounter(
              staffId: entry.key,
              counts: entry.value.counts,
              countedLines: entry.value.countedLines,
              varianceLines: entry.value.varianceLines,
              varianceUnits: entry.value.varianceUnits,
              uncountedLines: entry.value.uncounted,
            ),
        ]..sort((a, b) {
          final byCounts = b.counts.compareTo(a.counts);
          if (byCounts != 0) return byCounts;
          final byLines = b.countedLines.compareTo(a.countedLines);
          return byLines != 0 ? byLines : a.staffId.compareTo(b.staffId);
        });

    // Oldest first, which is the order a trend reads in.
    final ordered = takes.toList()
      ..sort((a, b) {
        final byDate = a.businessDate.compareTo(b.businessDate);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });

    return TenantStockCountsAnalysis._(
      period: period,
      counts: takes.length,
      appliedCount: applied,
      awaitingApply: awaiting,
      stillArriving: arriving,
      awaitingVarianceLines: awaitingVarianceLines,
      awaitingVarianceUnits: awaitingVarianceUnits,
      countedLines: countedLines,
      varianceLines: varianceLines,
      varianceUnits: varianceUnits,
      uncountedLines: uncounted,
      unmatchedLines: unmatched,
      counters: List<TenantStockCounter>.unmodifiable(ranked),
      records: List<TenantStockTakeRecord>.unmodifiable(ordered),
      scopedCounts: scoped,
      previousCounts: previous?.length,
      truncated: truncated,
    );
  }

  final TenantReportPeriod period;

  /// How many counts the period holds.
  final int counts;

  /// Counts whose variances have been written to the ledger.
  final int appliedCount;

  /// **Counts that landed complete and were never applied.** The finding.
  final int awaitingApply;

  /// Counts whose pages have not all arrived, so they cannot be applied.
  final int stillArriving;

  /// Lines on unapplied counts that disagree with the books.
  final int awaitingVarianceLines;
  final int awaitingVarianceUnits;

  final int countedLines;
  final int varianceLines;
  final int varianceUnits;

  /// Products in scope that nobody wrote a number against. Not a variance.
  final int uncountedLines;

  /// Lines naming a product this business does not hold.
  final int unmatchedLines;

  final List<TenantStockCounter> counters;

  /// Every count in the period, oldest first.
  final List<TenantStockTakeRecord> records;

  /// Counts covering one category rather than the whole catalog.
  final int scopedCounts;

  /// How many counts the preceding comparable period held, or null where it
  /// could not be read.
  final int? previousCounts;

  final bool truncated;

  /// The share of counted lines that disagreed with the books.
  ///
  /// Null where nothing was counted. Over counted lines alone: an uncounted
  /// line is unknown, and folding it in would report a shop as accurate for
  /// shelves nobody looked at.
  double? get varianceRate {
    if (countedLines == 0) return null;
    return varianceLines / countedLines;
  }

  /// Whether the books are up to date with every count that was taken.
  bool get isSettled => awaitingApply == 0 && stillArriving == 0;

  /// How the rate moved between the first and second half of the period.
  ///
  /// **Null unless there are at least four counts**, because two counts either
  /// side is the fewest that can carry a direction at all. One count each way
  /// is a comparison of two afternoons.
  double? get accuracyTrend {
    final withLines = records.where((r) => r.countedLineCount > 0).toList();
    if (withLines.length < 4) return null;
    final half = withLines.length ~/ 2;
    final earlier = withLines.take(half);
    final later = withLines.skip(withLines.length - half);
    final earlierRate = _rateOf(earlier);
    final laterRate = _rateOf(later);
    if (earlierRate == null || laterRate == null) return null;
    return laterRate - earlierRate;
  }

  /// The count with the most lines disagreeing, or null where none did.
  TenantStockTakeRecord? get worst {
    TenantStockTakeRecord? found;
    for (final take in records) {
      if (take.varianceLineCount == 0) continue;
      if (found == null || take.varianceLineCount > found.varianceLineCount) {
        found = take;
      }
    }
    return found;
  }

  static double? _rateOf(Iterable<TenantStockTakeRecord> takes) {
    var counted = 0;
    var variance = 0;
    for (final take in takes) {
      counted += take.countedLineCount;
      variance += take.varianceLineCount;
    }
    if (counted == 0) return null;
    return variance / counted;
  }
}

/// Mutable running totals, so the loop above stays one pass.
final class _Running {
  int counts = 0;
  int countedLines = 0;
  int varianceLines = 0;
  int varianceUnits = 0;
  int uncounted = 0;
}
