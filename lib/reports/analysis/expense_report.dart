/// The expenses report: what it reads, and what it says about it.
///
/// **The sentences are the product.** A section headed *Spending by category*
/// with a ring under it restates the screen. The same section saying "Wages and
/// rent are 71% of the month, and repairs have stopped since August" is why
/// somebody asked for a report. Every sentence here is assembled from figures
/// the analysis computed, so none of them can drift from the chart beside it.
library;

import '../../expenses/expense.dart';
import '../../expenses/expense_repository.dart';
import '../report_document.dart';
import '../report_identity.dart';
import '../report_period.dart';
import '../report_scope.dart';
import '../report_table.dart';
import '../report_visual.dart';
import 'report_prose.dart';
import 'expense_analysis.dart';

/// Reads the two periods an expenses report compares.
final class TenantExpenseReportSource {
  const TenantExpenseReportSource({required this.repository});

  final TenantExpenseRepository repository;

  /// The period asked for, and the equal window before it.
  ///
  /// **The earlier window is read second and allowed to fail.** It is the
  /// comparison, not the report: a business three weeks old has no previous
  /// month, and a read that could not reach one should still produce the
  /// figures for the period the person actually asked about.
  Future<({TenantExpensePeriod now, TenantExpensePeriod? before})> gather(
    TenantReportPeriod period,
  ) async {
    final now = await repository.readRange(
      startDate: period.startDate,
      endDate: period.endDate,
    );
    final earlier = period.precedingComparable;
    TenantExpensePeriod? before;
    try {
      before = await repository.readRange(
        startDate: earlier.startDate,
        endDate: earlier.endDate,
      );
    } on Object {
      before = null;
    }
    return (now: now, before: before);
  }
}

/// Turns the analysis into the document both renderers draw.
TenantReportDocument describeExpenseReport({
  required TenantExpenseAnalysis analysis,
  required TenantReportIdentity identity,
}) {
  final period = analysis.period;
  final money = identity.money;

  return TenantReportDocument(
    kind: TenantReportKind.expenses,
    identity: identity,
    scope: _scope(analysis),
    subtitle:
        'What the business spent beyond the cost of its stock, against the '
        '${period.days} days before it.',
    headline: <TenantReportFigure>[
      TenantReportFigure(
        label: 'Total spent',
        value: money(analysis.totalMinor),
        comparison: analysis.previousTotalMinor == null
            ? null
            : money(analysis.previousTotalMinor!),
        amount: analysis.totalMinor / 100,
        amountComparison: analysis.previousTotalMinor == null
            ? null
            : analysis.previousTotalMinor! / 100,
      ),
      TenantReportFigure(
        label: 'A day, on average',
        value: money(analysis.dailyMean.round()),
        amount: analysis.dailyMean / 100,
        note: analysis.quietDays == 0
            ? null
            : 'Across all ${analysis.dailyMinor.length} days, '
                  '${analysis.quietDays} of which had no spending at all.',
      ),
      TenantReportFigure(
        label: 'Items recorded',
        value: analysis.recordCount.toString(),
        amount: analysis.recordCount,
        amountKind: TenantReportColumnKind.count,
        note: analysis.voidedCount == 0
            ? null
            : '${analysis.voidedCount} '
                  '${analysis.voidedCount == 1 ? 'was' : 'were'} voided and '
                  '${analysis.voidedCount == 1 ? 'is' : 'are'} not in the '
                  'total.',
      ),
    ],
    sections: <TenantReportSection>[
      _byCategory(analysis, identity),
      _byDay(analysis, identity),
      if (analysis.spent.isNotEmpty) _movement(analysis, identity),
      if (analysis.largest != null) _items(analysis, identity),
    ],
  );
}

TenantReportScope _scope(TenantExpenseAnalysis analysis) {
  final caveats = <TenantReportCaveat>[
    if (analysis.truncated)
      TenantReportCaveat.truncated(
        asked: analysis.period,
        reachedFrom: analysis.period.startDate,
        reachedTo: analysis.period.endDate,
        records: TenantExpenseRepository.maximumRangeRecords,
      ),
    if (analysis.previousTotalMinor == null)
      const TenantReportCaveat(
        kind: TenantReportCaveatKind.noEvidence,
        sentence:
            'The period before this one could not be read, so nothing here is '
            'compared against it. The figures for the period asked for are '
            'complete.',
      ),
  ];

  return TenantReportScope(
    period: analysis.period,
    documentsRead: analysis.recordCount,
    // Expenses are read straight from Firestore, which serves them from its own
    // offline copy when there is one. The device is the reader either way.
    caveats: caveats,
  );
}

TenantReportSection _byCategory(
  TenantExpenseAnalysis analysis,
  TenantReportIdentity identity,
) {
  final spent = analysis.spent;
  final concentration = analysis.concentration;
  final few = analysis.headingsFor(0.75);

  final summary = StringBuffer();
  if (spent.isEmpty) {
    summary.write('Nothing was spent in this period under any heading.');
  } else {
    summary.write(
      '${spent.first.category.label} is the largest heading at '
      '${reportPercent(spent.first.share)} of the period',
    );
    if (few != null && few < spent.length) {
      summary.write(
        ', and $few of the ${spent.length} headings carry three quarters of '
        'it',
      );
    }
    summary.write('.');
    if (concentration != null && concentration > 0.5) {
      summary.write(
        ' Spending is concentrated: over half the money went under one '
        'heading, so a change there moves the whole month.',
      );
    }
  }

  return TenantReportSection(
    heading: 'Spending by category',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.composition,
      caption: 'Share of the period by heading',
      valueAxisLabel: 'Spend',
      data: <TenantReportDatum>[
        for (final heading in spent.isEmpty ? analysis.headings : spent)
          TenantReportDatum(
            label: heading.category.label,
            value: heading.minor / 100,
            formatted: identity.money(heading.minor),
          ),
      ],
    ),
  );
}

TenantReportSection _byDay(
  TenantExpenseAnalysis analysis,
  TenantReportIdentity identity,
) {
  final heaviest = analysis.heaviestDate;
  final summary = StringBuffer(
    'The period averages ${identity.money(analysis.dailyMean.round())} a day '
    'across all ${analysis.dailyMinor.length} of its days.',
  );
  if (heaviest != null) {
    summary.write(
      ' The most went out on ${TenantReportPeriod.day(heaviest).spelled}, at '
      '${identity.money(analysis.dailyMinor[heaviest] ?? 0)}.',
    );
  }
  if (analysis.quietDays > 0) {
    summary.write(
      ' ${analysis.quietDays} of the days had no spending recorded at all, '
      'and are drawn as the zeroes they were.',
    );
  }

  return TenantReportSection(
    heading: 'Spending by day',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.trend,
      caption: 'What went out each day',
      valueAxisLabel: 'Spend',
      data: <TenantReportDatum>[
        for (final entry in analysis.dailyMinor.entries)
          TenantReportDatum(
            label: reportShortDate(entry.key),
            value: entry.value / 100,
            formatted: identity.money(entry.value),
          ),
      ],
    ),
  );
}

TenantReportSection _movement(
  TenantExpenseAnalysis analysis,
  TenantReportIdentity identity,
) {
  final moved = analysis.change;
  final summary = StringBuffer();
  if (moved == null) {
    summary.write(
      'There is no earlier period to compare this one against, so the figures '
      'below stand on their own.',
    );
  } else {
    summary.write(
      'Spending is ${reportDirection(moved)} on the ${analysis.period.days} days '
      'before this period.',
    );
    final started = analysis.started;
    final stopped = analysis.stopped;
    if (started.isNotEmpty) {
      summary.write(
        ' ${reportList(started.map((h) => h.category.label))} '
        '${started.length == 1 ? 'is new' : 'are new'} this period.',
      );
    }
    if (stopped.isNotEmpty) {
      summary.write(
        ' ${reportList(stopped.map((h) => h.category.label))} had spending last '
        'period and none in this one.',
      );
    }
  }

  return TenantReportSection(
    heading: 'What moved',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.comparison,
      caption: 'This period against the one before it',
      valueAxisLabel: 'Spend',
      comparisonLabel: 'The period before',
      data: <TenantReportDatum>[
        for (final heading in analysis.headings.where(
          (h) => h.minor > 0 || h.previousMinor > 0,
        ))
          TenantReportDatum(
            label: heading.category.label,
            value: heading.minor / 100,
            formatted: identity.money(heading.minor),
            comparison: heading.previousMinor / 100,
            comparisonFormatted: identity.money(heading.previousMinor),
            emphasis: heading.category == analysis.spent.first.category,
          ),
      ],
    ),
  );
}

TenantReportSection _items(
  TenantExpenseAnalysis analysis,
  TenantReportIdentity identity,
) {
  final largest = analysis.largest!;
  final share = analysis.totalMinor == 0
      ? 0.0
      : largest.amountMinor / analysis.totalMinor;

  return TenantReportSection(
    heading: 'The largest items',
    summary:
        'The single biggest item was ${identity.money(largest.amountMinor)} '
        'under ${largest.category.label}, which is ${reportPercent(share)} of '
        'everything spent in the period.',
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Date', kind: TenantReportColumnKind.date),
        TenantReportColumn(
          heading: 'Heading',
          kind: TenantReportColumnKind.text,
        ),
        TenantReportColumn(
          heading: 'Description',
          kind: TenantReportColumnKind.text,
        ),
        TenantReportColumn(
          heading: 'Amount',
          kind: TenantReportColumnKind.money,
        ),
      ],
      rows: <List<TenantReportCell>>[
        for (final record in analysis.biggest)
          <TenantReportCell>[
            TenantReportDateCell(record.businessDate),
            TenantReportTextCell(record.category.label),
            TenantReportTextCell(record.description),
            // A voided item is listed so the record is complete, and marked so
            // nobody adds it in. It is money that did not leave the business.
            if (record.isVoided)
              const TenantReportAbsentCell(
                'voided after it was entered',
                shown: TenantReportAbsentCell.voided,
              )
            else
              TenantReportMoneyCell(
                minor: record.amountMinor,
                formatted: identity.money(record.amountMinor),
              ),
          ],
      ],
    ),
    notes: <String>[
      if (analysis.voidedCount > 0)
        '${analysis.voidedCount} voided '
            '${analysis.voidedCount == 1 ? 'item is' : 'items are'} listed for '
            'completeness and shown as voided rather than as an amount. '
            '${analysis.voidedCount == 1 ? 'It is' : 'They are'} money that '
            'did not leave the business, and '
            '${analysis.voidedCount == 1 ? 'it is' : 'they are'} in no total '
            'here.',
    ],
  );
}




