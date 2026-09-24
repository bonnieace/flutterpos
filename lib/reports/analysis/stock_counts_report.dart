/// The stock counts report: what it reads, and what it says about it.
///
/// **The section that justifies it is *Counted and not corrected*.** A count
/// that landed complete and was never applied is a shelf somebody walked and a
/// correction nobody made - the shop knows its books are wrong and the books
/// are still wrong. The review screen shows one count with an *Apply* button;
/// only a period can say how many are sitting there.
///
/// **The second is *How well the books are kept*.** The share of counted lines
/// that disagreed means nothing from one count and something across six, and
/// nothing in the app has ever put six of them side by side.
library;

import '../../inventory/stock_take_review.dart';
import '../../tenancy/tenant_repository.dart';
import '../report_document.dart';
import '../report_identity.dart';
import '../report_people.dart';
import '../report_period.dart';
import '../report_scope.dart';
import '../report_table.dart';
import '../report_visual.dart';
import 'report_prose.dart';
import 'stock_counts_analysis.dart';

/// Reads the counts a report covers.
final class TenantStockCountsReportSource {
  const TenantStockCountsReportSource({
    required this.repository,
    required this.reader,
    this.pageSize = 50,
    this.maximumPages = 8,
  });

  final TenantStockTakeReviewRepository repository;

  /// The collection reader the repository pages through. It is passed rather
  /// than held because that is the shape `loadTakePage` already has.
  final TenantCollectionReader reader;

  final int pageSize;

  /// **A bound, and the report prints it when it is reached.** At 50 a page
  /// this is 400 counts, which is more than one a day for a year.
  final int maximumPages;

  /// Every count taken in [period], up to the page bound.
  Future<({List<TenantStockTakeRecord> takes, bool truncated})> gather(
    TenantReportPeriod period,
  ) async {
    final takes = <TenantStockTakeRecord>[];
    String? position;

    for (var page = 0; page < maximumPages; page++) {
      final read = await repository.loadDateRange(
        collectionReader: reader,
        startBusinessDate: period.startDate,
        endBusinessDate: period.endDate,
        pageSize: pageSize,
        startAfterDocumentId: position,
      );
      takes.addAll(read.items);
      position = read.nextDocumentId;
      if (position == null) return (takes: takes, truncated: false);
    }
    return (takes: takes, truncated: true);
  }

  /// The same read over the preceding comparable window.
  Future<List<TenantStockTakeRecord>?> gatherPrevious(
    TenantReportPeriod period,
  ) async {
    try {
      final read = await gather(period.precedingComparable);
      return read.takes;
    } on Object {
      return null;
    }
  }
}

/// Turns the analysis into the document both renderers draw.
TenantReportDocument describeStockCountsReport({
  required TenantStockCountsAnalysis analysis,
  required TenantReportIdentity identity,
  /// Names for the people in 'Who counted'. Management-only, as above.
  TenantReportPeople people = const TenantReportPeople.none(),
}) => TenantReportDocument(
  kind: TenantReportKind.stockCounts,
  identity: identity,
  scope: _scope(analysis, people),
  subtitle:
      '${analysis.counts} counts over ${analysis.period.days} days, what '
      'they found, and what has not been put right.',
  headline: <TenantReportFigure>[
    TenantReportFigure(
      label: 'Counts taken',
      value: analysis.counts.toString(),
      amount: analysis.counts,
      amountKind: TenantReportColumnKind.count,
      comparison: analysis.previousCounts?.toString(),
      amountComparison: analysis.previousCounts,
      note: analysis.scopedCounts == 0
          ? 'All of them over the whole catalog.'
          : '${analysis.scopedCounts} of them covered one category only.',
    ),
    TenantReportFigure(
      label: 'Lines disagreeing',
      value: analysis.varianceRate == null
          ? TenantReportAbsentCell.notRecorded
          : reportPercent(analysis.varianceRate!),
      amount: analysis.varianceRate,
      amountKind: TenantReportColumnKind.percent,
      note: analysis.countedLines == 0
          ? 'Nothing was counted in this period.'
          : '${analysis.varianceLines} of ${analysis.countedLines} counted '
                'lines, ${analysis.varianceUnits} units in all.',
    ),
    TenantReportFigure(
      label: 'Not applied',
      value: analysis.awaitingApply.toString(),
      amount: analysis.awaitingApply,
      amountKind: TenantReportColumnKind.count,
      note: analysis.awaitingApply == 0
          ? 'Every count that landed has been written to the books.'
          : '${reportCount(analysis.awaitingVarianceLines, 'line')} '
                '${reportVerb(analysis.awaitingVarianceLines, 'is', 'are')} '
                'known to be wrong and still uncorrected.',
    ),
  ],
  sections: <TenantReportSection>[
    _notCorrected(analysis),
    if (analysis.countedLines > 0) _accuracy(analysis),
    if (analysis.counters.isNotEmpty) _perCounter(analysis, people),
    if (analysis.records.isNotEmpty) _everyCount(analysis),
  ],
);

TenantReportScope _scope(
  TenantStockCountsAnalysis analysis,
  TenantReportPeople people,
) =>
    TenantReportScope(
      period: analysis.period,
      documentsRead: analysis.counts,
      caveats: <TenantReportCaveat>[
        if (people.caveat(
          analysis.counters
              .take(TenantStockCountsAnalysis.listed)
              .map((person) => person.staffId),
          noun: 'took a count',
        ) case final caveat?)
          caveat,
        if (analysis.truncated)
          TenantReportCaveat.truncated(
            asked: analysis.period,
            reachedFrom: analysis.period.startDate,
            reachedTo: analysis.period.endDate,
            records: analysis.counts,
          ),
        if (analysis.uncountedLines > 0)
          TenantReportCaveat(
            kind: TenantReportCaveatKind.noEvidence,
            sentence:
                '${reportCount(analysis.uncountedLines, 'product')} '
                '${reportVerb(analysis.uncountedLines, 'was', 'were')} in '
                'scope of a count and had no number written against '
                '${reportVerb(analysis.uncountedLines, 'it', 'them')}. '
                '${reportVerb(analysis.uncountedLines, 'It is', 'They are')} '
                'left out of every rate below rather than treated as '
                'agreeing: nobody looked at those shelves.',
          ),
        if (analysis.unmatchedLines > 0)
          TenantReportCaveat(
            kind: TenantReportCaveatKind.noEvidence,
            sentence:
                '${reportCount(analysis.unmatchedLines, 'counted line')} '
                '${reportVerb(analysis.unmatchedLines, 'names', 'name')} a '
                'product this business does not hold, usually one created on '
                'a device with no connection. '
                '${reportVerb(analysis.unmatchedLines, 'It records', 'They record')} '
                'what was counted and nothing else.',
          ),
        if (analysis.stillArriving > 0)
          TenantReportCaveat(
            kind: TenantReportCaveatKind.truncated,
            sentence:
                '${analysis.stillArriving} '
                '${analysis.stillArriving == 1 ? 'count has' : 'counts have'} '
                'not finished arriving, so what they found is incomplete and '
                'they cannot be applied at all.',
          ),
        if (analysis.previousCounts == null)
          const TenantReportCaveat(
            kind: TenantReportCaveatKind.noEvidence,
            sentence:
                'The period before this one could not be read, so nothing '
                'here is compared against it. The figures for the period '
                'asked for are complete.',
          ),
      ],
    );

/// The section the report exists for.
TenantReportSection _notCorrected(TenantStockCountsAnalysis analysis) {
  final summary = StringBuffer();
  if (analysis.counts == 0) {
    summary.write('No stock was counted in this period.');
  } else if (analysis.isSettled) {
    summary.write(
      'Every count taken in this period has been written to the books. '
      'Nothing is known to be wrong and left uncorrected.',
    );
  } else {
    if (analysis.awaitingApply > 0) {
      summary.write(
        '${analysis.awaitingApply} of ${analysis.counts} counts landed '
        'complete and were never applied. '
        '${analysis.awaitingVarianceLines} lines on them disagree with the '
        'books by ${analysis.awaitingVarianceUnits} units, and the books '
        'still say the old figure.',
      );
    }
    if (analysis.stillArriving > 0) {
      summary.write(
        ' ${analysis.stillArriving} more '
        '${analysis.stillArriving == 1 ? 'count has' : 'counts have'} not '
        'finished arriving and cannot be applied yet.',
      );
    }
  }

  return TenantReportSection(
    heading: 'Counted and not corrected',
    summary: summary.toString(),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Standing', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Counts', kind: TenantReportColumnKind.count),
        TenantReportColumn(
          heading: 'Lines wrong',
          kind: TenantReportColumnKind.count,
        ),
      ],
      rows: <List<TenantReportCell>>[
        <TenantReportCell>[
          const TenantReportTextCell('Applied to the books'),
          TenantReportCountCell(analysis.appliedCount),
          TenantReportCountCell(
            analysis.varianceLines - analysis.awaitingVarianceLines,
          ),
        ],
        <TenantReportCell>[
          const TenantReportTextCell('Waiting to be applied'),
          TenantReportCountCell(analysis.awaitingApply),
          TenantReportCountCell(analysis.awaitingVarianceLines),
        ],
        <TenantReportCell>[
          const TenantReportTextCell('Still arriving'),
          TenantReportCountCell(analysis.stillArriving),
          const TenantReportAbsentCell('not all pages have landed'),
        ],
      ],
      emphasisRow: analysis.awaitingApply > 0 ? 1 : null,
    ),
  );
}

TenantReportSection _accuracy(TenantStockCountsAnalysis analysis) {
  final rate = analysis.varianceRate!;
  final summary = StringBuffer(
    '${reportPercent(rate)} of the ${analysis.countedLines} lines counted in '
    'this period disagreed with the books, by '
    '${analysis.varianceUnits} units in all.',
  );
  if (analysis.accuracyTrend case final moved?) {
    if (moved.abs() < 0.01) {
      summary.write(' The rate held steady across the period.');
    } else {
      summary.write(
        ' It ${moved > 0 ? 'rose' : 'fell'} by '
        '${reportPercent(moved.abs())} between the first half of the period '
        'and the second.',
      );
    }
  }
  if (analysis.worst case final worst?) {
    summary.write(
      ' The count that found the most was '
      '${TenantReportPeriod.day(worst.businessDate).spelled}, with '
      '${worst.varianceLineCount} lines out.',
    );
  }

  return TenantReportSection(
    heading: 'How well the books are kept',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.trend,
      caption: 'Lines disagreeing, per count',
      valueAxisLabel: 'Lines out',
      data: <TenantReportDatum>[
        for (final take in analysis.records.take(12))
          TenantReportDatum(
            label: reportShortDate(take.businessDate),
            value: take.varianceLineCount.toDouble(),
            formatted: '${take.varianceLineCount}',
          ),
      ],
    ),
  );
}

TenantReportSection _perCounter(
  TenantStockCountsAnalysis analysis,
  TenantReportPeople people,
) {
  final busiest = analysis.counters.first;
  final summary = StringBuffer(
    analysis.counters.length == 1
        ? 'One person took every count in this period.'
        : '${analysis.counters.length} people counted in this period, and '
              '${people.label(busiest.staffId)} took the most at '
              '${busiest.counts}.',
  );
  summary.write(
    ' A high rate is not a mark against the counter: counting is blind, so '
    'what it measures is the shelf they were sent to.',
  );

  return TenantReportSection(
    heading: 'Who counted',
    summary: summary.toString(),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Counted by', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Counts', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Lines', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Out', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Rate', kind: TenantReportColumnKind.percent),
      ],
      rows: <List<TenantReportCell>>[
        for (final person
            in analysis.counters.take(TenantStockCountsAnalysis.listed))
          <TenantReportCell>[
            TenantReportTextCell(people.label(person.staffId)),
            TenantReportCountCell(person.counts),
            TenantReportCountCell(person.countedLines),
            TenantReportCountCell(person.varianceLines),
            if (person.varianceRate case final rate?)
              TenantReportPercentCell(rate)
            else
              const TenantReportAbsentCell('nothing was counted'),
          ],
      ],
    ),
  );
}

TenantReportSection _everyCount(TenantStockCountsAnalysis analysis) =>
    TenantReportSection(
      heading: 'Every count',
      summary:
          'Oldest first. *Not counted* is a product the count covered that '
          'nobody wrote a number against - unknown rather than agreed.',
      table: TenantReportTable(
        columns: const <TenantReportColumn>[
          TenantReportColumn(heading: 'Day', kind: TenantReportColumnKind.date),
          TenantReportColumn(heading: 'Scope', kind: TenantReportColumnKind.text),
          TenantReportColumn(heading: 'Standing', kind: TenantReportColumnKind.text),
          TenantReportColumn(heading: 'Counted', kind: TenantReportColumnKind.count),
          TenantReportColumn(heading: 'Out', kind: TenantReportColumnKind.count),
          TenantReportColumn(
            heading: 'Not counted',
            kind: TenantReportColumnKind.count,
          ),
        ],
        rows: <List<TenantReportCell>>[
          for (final take
              in analysis.records.take(TenantStockCountsAnalysis.listed))
            <TenantReportCell>[
              TenantReportDateCell(take.businessDate),
              TenantReportTextCell(
                take.categoryId == null ? 'Whole catalog' : 'One category',
              ),
              TenantReportTextCell(_standing(take.status)),
              TenantReportCountCell(take.countedLineCount),
              TenantReportCountCell(take.varianceLineCount),
              TenantReportCountCell(take.uncountedLineCount),
            ],
        ],
      ),
    );

String _standing(TenantStockTakeStatus status) => switch (status) {
  TenantStockTakeStatus.applied => 'Applied',
  TenantStockTakeStatus.submitted => 'Waiting to apply',
  TenantStockTakeStatus.submitting => 'Still arriving',
};
