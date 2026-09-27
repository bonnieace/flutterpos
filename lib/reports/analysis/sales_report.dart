/// The sales report: what it reads, and what it says about it.
///
/// **The section that justifies the whole feature is *What earned the most*.**
/// The sales screen ranks by takings; nothing in the app ranks by margin. Those
/// two orders disagree in most shops, and the disagreement is a decision a
/// shopkeeper can act on - which line to push, which to reprice, which is
/// busywork. Everything a report does that the screen already did is overhead
/// against that.
library;

import '../../returns/return_offsets.dart';
import '../../sales/sale_history.dart';
import '../report_document.dart';
import '../report_identity.dart';
import '../report_period.dart';
import '../report_scope.dart';
import '../report_table.dart';
import '../report_visual.dart';
import 'report_prose.dart';
import 'sales_analysis.dart';

/// Reads the sales a report covers.
final class TenantSalesReportSource {
  const TenantSalesReportSource({
    required this.repository,
    this.returnsLoader,
    this.pageSize = 50,
    this.maximumPages = 24,
  });

  final TenantSaleHistoryRepository repository;

  /// Required by [gatherAnalysis]. Raw sales readers may omit this loader.
  final TenantDayReturnsLoader? returnsLoader;

  /// The repository's own ceiling. Asking for more is a `RangeError`.
  final int pageSize;

  /// **A bound, and the report prints it when it is reached.** At 50 a page
  /// this is 1,200 sales, which is a busy month for the shops this app serves.
  /// A period past it is not silently shortened: the scope block says what was
  /// actually covered, and every total below it is a floor.
  final int maximumPages;

  /// Every sale in [period], up to the page bound.
  Future<({List<TenantSale> sales, bool truncated})> gather(
    TenantReportPeriod period, {
    String? staffId,
  }) async {
    final sales = <TenantSale>[];
    String? cursor;
    var pages = 0;

    while (pages < maximumPages) {
      final page = await repository.loadReport(
        startBusinessDate: period.startDate,
        endBusinessDate: period.endDate,
        selectedStaffId: staffId,
        pageSize: pageSize,
        cursor: cursor,
      );
      sales.addAll(page.items);
      pages++;
      if (!page.hasMore || page.nextCursor == null) {
        return (sales: sales, truncated: false);
      }
      cursor = page.nextCursor;
    }
    return (sales: sales, truncated: true);
  }

  /// The same read over the preceding comparable window.
  ///
  /// **Allowed to fail, but never compared when short.** It is the comparison, not
  /// the report: a business a month old has no earlier period, and a read that
  /// could not reach one must not stop the figures the person asked for.
  /// Null where the earlier window could not be read at all, which the report
  /// says out loud rather than showing as a period with no trading in it.
  Future<List<TenantSale>?> gatherPrevious(
    TenantReportPeriod period, {
    String? staffId,
  }) async {
    try {
      final read = await gather(period.precedingComparable, staffId: staffId);
      return read.truncated ? null : read.sales;
    } on Object {
      return null;
    }
  }

  /// Reads and nets both windows. A failed return read must never silently
  /// turn the requested period into gross takings. An unreadable comparison
  /// can be omitted without losing the requested report.
  Future<TenantSalesAnalysis> gatherAnalysis(TenantReportPeriod period) async {
    if (returnsLoader == null) {
      throw StateError('Sales reports require return offsets.');
    }
    final read = await gather(period);
    final offsets = await _returnOffsets(read.sales);
    var previous = await gatherPrevious(period);
    var previousOffsets = <String, TenantSaleReturnOffset>{};
    if (previous != null) {
      try {
        previousOffsets = await _returnOffsets(previous);
      } on Object {
        previous = null;
      }
    }
    return TenantSalesAnalysis.from(
      period: period,
      sales: read.sales,
      previous: previous,
      returnOffsets: offsets,
      previousReturnOffsets: previousOffsets,
      truncated: read.truncated,
      documentsRead: read.sales.length + (previous?.length ?? 0),
    );
  }

  Future<Map<String, TenantSaleReturnOffset>> _returnOffsets(
    List<TenantSale> sales,
  ) async {
    final byDate = <String, List<TenantSale>>{};
    for (final sale in sales) {
      byDate.putIfAbsent(sale.businessDate, () => []).add(sale);
    }
    final offsets = <String, TenantSaleReturnOffset>{};
    for (final entry in byDate.entries) {
      final returns = await returnsLoader!.load(entry.key);
      for (final sale in entry.value) {
        if (returns.offsetFor(sale) case final offset?) {
          offsets[sale.id] = offset;
        }
      }
    }
    return offsets;
  }
}

/// Turns the analysis into the document both renderers draw.
TenantReportDocument describeSalesReport({
  required TenantSalesAnalysis analysis,
  required TenantReportIdentity identity,
}) {
  final money = identity.money;

  return TenantReportDocument(
    kind: TenantReportKind.sales,
    identity: identity,
    scope: _scope(analysis),
    subtitle:
        'What the business took, what it kept, and what moved against the '
        '${analysis.period.days} days before it.',
    headline: <TenantReportFigure>[
      TenantReportFigure(
        label: 'Takings',
        value: money(analysis.revenueMinor),
        comparison: analysis.previousRevenueMinor == null
            ? null
            : money(analysis.previousRevenueMinor!),
        amount: analysis.revenueMinor / 100,
        amountComparison: analysis.previousRevenueMinor == null
            ? null
            : analysis.previousRevenueMinor! / 100,
        note: analysis.returnedMinor == 0
            ? null
            : 'After ${money(analysis.returnedMinor)} in returns.',
      ),
      // The margin figure carries its own denominator rather than leaving the
      // qualification to a scope block somebody may not read.
      TenantReportFigure(
        label: 'Gross margin',
        value: analysis.lineCount == 0 ? money(0) : money(analysis.marginMinor),
        amount: analysis.marginMinor / 100,
        note: analysis.isCostComplete
            ? null
            : 'Over ${analysis.lineCount - analysis.linesWithoutCost} of '
                  '${analysis.lineCount} lines. The rest record no cost, so '
                  'this understates by whatever those cost.',
      ),
      TenantReportFigure(
        label: 'Transactions',
        value: analysis.transactions.toString(),
        comparison: analysis.previousTransactions?.toString(),
        amount: analysis.transactions,
        amountComparison: analysis.previousTransactions,
        amountKind: TenantReportColumnKind.count,
        note: analysis.transactions == 0
            ? null
            : 'A sale averaged ${money(analysis.averageSaleMinor)}.',
      ),
    ],
    sections: <TenantReportSection>[
      _byDay(analysis, identity),
      _byWeekday(analysis, identity),
      if (analysis.items.isNotEmpty) _earners(analysis, identity),
      if (analysis.tenders.isNotEmpty) _tenders(analysis, identity),
    ],
  );
}

TenantReportScope _scope(TenantSalesAnalysis analysis) {
  final caveats = <TenantReportCaveat>[
    if (analysis.truncated)
      TenantReportCaveat.truncated(
        asked: analysis.period,
        reachedFrom: analysis.period.startDate,
        reachedTo: analysis.period.endDate,
        records: analysis.transactions,
      ),
    if (!analysis.isCostComplete)
      TenantReportCaveat.missingCost(
        lines: analysis.linesWithoutCost,
        of: analysis.lineCount,
      ),
    if (analysis.previousRevenueMinor == null)
      const TenantReportCaveat(
        kind: TenantReportCaveatKind.noEvidence,
        sentence:
            'The period before this one could not be read completely, so '
            'nothing here is compared against it.',
      ),
  ];

  return TenantReportScope(
    period: analysis.period,
    documentsRead: analysis.documentsRead == 0
        ? analysis.transactions
        : analysis.documentsRead,
    caveats: caveats,
  );
}

TenantReportSection _byDay(
  TenantSalesAnalysis analysis,
  TenantReportIdentity identity,
) {
  final summary = StringBuffer();
  final moved = analysis.change;
  if (moved == null) {
    // **Three different states, not two.** No earlier window read at all; an
    // earlier window that was read and took nothing; and a real comparison.
    // The middle one has no percentage - a rise from nothing is not one - but
    // it is still a finding, and calling it "no earlier window" would say the
    // records were missing when they were merely quiet.
    summary.write(
      analysis.previousRevenueMinor == null
          ? 'Takings across the period, with no earlier window to compare '
                'them against.'
          : 'Takings across the period. The ${analysis.period.days} days '
                'before it took nothing at all, so there is no percentage to '
                'put on the change.',
    );
  } else {
    summary.write(
      'Takings are ${reportDirection(moved)} on the ${analysis.period.days} days '
      'before this period.',
    );
  }
  if (analysis.bestDay case final best?) {
    summary.write(
      ' The best day was ${TenantReportPeriod.day(best).spelled}, at '
      '${identity.money(analysis.dailyMinor[best] ?? 0)}.',
    );
  }
  if (analysis.quietDays > 0) {
    summary.write(
      ' ${analysis.quietDays} of the days took nothing at all, and are drawn '
      'as the zeroes they were.',
    );
  }

  final previousByDate = analysis.previousDailyMinor.values.toList();

  return TenantReportSection(
    heading: 'Takings by day',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.trend,
      caption: 'What the shop took each day',
      valueAxisLabel: 'Takings',
      comparisonLabel: previousByDate.isEmpty ? null : 'The period before',
      data: <TenantReportDatum>[
        for (final (index, entry) in analysis.dailyMinor.entries.indexed)
          TenantReportDatum(
            label: reportShortDate(entry.key),
            value: entry.value / 100,
            formatted: identity.money(entry.value),
            // Lined up by position in the window rather than by date, which is
            // what makes the second series a comparison rather than a gap.
            comparison: index < previousByDate.length
                ? previousByDate[index] / 100
                : null,
            comparisonFormatted: index < previousByDate.length
                ? identity.money(previousByDate[index])
                : null,
          ),
      ],
    ),
  );
}

TenantReportSection _byWeekday(
  TenantSalesAnalysis analysis,
  TenantReportIdentity identity,
) {
  final weakest = analysis.weakestWeekday;
  final total = analysis.weekdayMinor.fold(0, (sum, minor) => sum + minor);
  final strongest = total == 0
      ? null
      : analysis.weekdayMinor.indexOf(
          analysis.weekdayMinor.reduce((a, b) => a > b ? a : b),
        );

  final summary = StringBuffer();
  if (strongest == null) {
    summary.write('Nothing was taken in this period.');
  } else {
    final share = analysis.weekdayMinor[strongest] / total;
    summary.write(
      '${TenantSalesAnalysis.weekdayNames[strongest]} is the strongest day of '
      'the week at ${reportPercent(share)} of takings',
    );
    if (weakest != null && weakest != strongest) {
      summary.write(
        ', and ${TenantSalesAnalysis.weekdayNames[weakest]} the weakest the '
        'shop actually traded on',
      );
    }
    summary.write('.');
  }

  return TenantReportSection(
    heading: 'By day of the week',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.comparison,
      caption: 'This period against the one before it',
      valueAxisLabel: 'Takings',
      comparisonLabel: 'The period before',
      data: <TenantReportDatum>[
        for (var day = 0; day < TenantSalesAnalysis.weekdayNames.length; day++)
          TenantReportDatum(
            label: TenantSalesAnalysis.weekdayNames[day],
            value: analysis.weekdayMinor[day] / 100,
            formatted: identity.money(analysis.weekdayMinor[day]),
            comparison: analysis.previousWeekdayMinor[day] / 100,
            comparisonFormatted: identity.money(
              analysis.previousWeekdayMinor[day],
            ),
            emphasis: day == strongest,
          ),
      ],
    ),
  );
}

/// The section the report exists for.
TenantReportSection _earners(
  TenantSalesAnalysis analysis,
  TenantReportIdentity identity,
) {
  final ranked = analysis.byMargin;
  final summary = StringBuffer();

  if (ranked.isEmpty) {
    summary.write(
      'No line in this period recorded what it cost, so nothing here can be '
      'ranked by what it earned. The listing below is by takings instead, '
      'which is a different question.',
    );
  } else if (analysis.sellerEarnerDiffer) {
    final seller = analysis.bestSeller!;
    final earner = analysis.bestEarner!;
    summary.write(
      'Ranked by what each line earned, not by what it took. '
      '${seller.name} sells the most; ${earner.name} earns the most, on '
      '${earner.quantity} units against ${seller.quantity}. The best seller '
      'and the best earner are not the same product, which is the thing this '
      'listing exists to show.',
    );
  } else {
    summary.write(
      'Ranked by what each line earned rather than by what it took. '
      '${analysis.bestEarner!.name} is both the best seller and the best '
      'earner this period.',
    );
  }

  if (!analysis.isCostComplete) {
    summary.write(
      ' ${analysis.linesWithoutCost} of ${analysis.lineCount} lines record no '
      'cost and are left out of this ranking rather than counted as pure '
      'profit.',
    );
  }

  final listed = ranked.isEmpty ? analysis.items : ranked;

  return TenantReportSection(
    heading: 'What earned the most',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.ranked,
      caption: ranked.isEmpty
          ? 'Top products by takings'
          : 'Top products by gross margin',
      valueAxisLabel: ranked.isEmpty ? 'Takings' : 'Margin',
      data: <TenantReportDatum>[
        for (final item in listed.take(_rankedProducts))
          TenantReportDatum(
            label: item.name,
            value: (item.marginMinor ?? item.revenueMinor) / 100,
            formatted: identity.money(item.marginMinor ?? item.revenueMinor),
            emphasis: item.productId == listed.first.productId,
          ),
      ],
    ),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(
          heading: 'Product',
          kind: TenantReportColumnKind.text,
        ),
        TenantReportColumn(
          heading: 'Units',
          kind: TenantReportColumnKind.count,
        ),
        TenantReportColumn(
          heading: 'Takings',
          kind: TenantReportColumnKind.money,
        ),
        TenantReportColumn(
          heading: 'Margin',
          kind: TenantReportColumnKind.money,
        ),
      ],
      rows: <List<TenantReportCell>>[
        for (final item in analysis.items.take(_listedProducts))
          <TenantReportCell>[
            TenantReportTextCell(item.name),
            TenantReportCountCell(item.quantity),
            TenantReportMoneyCell(
              minor: item.revenueMinor,
              formatted: identity.money(item.revenueMinor),
            ),
            // An unknown margin is not a large one. It says so rather than
            // printing the takings and letting a reader mistake them for
            // profit.
            if (item.marginMinor case final margin?)
              TenantReportMoneyCell(
                minor: margin,
                formatted: identity.money(margin),
              )
            else
              const TenantReportAbsentCell('no cost recorded on these lines'),
          ],
      ],
    ),
  );
}

TenantReportSection _tenders(
  TenantSalesAnalysis analysis,
  TenantReportIdentity identity,
) {
  final total = analysis.tenders.fold(0, (sum, t) => sum + t.minor);
  final leader = analysis.tenders.first;
  final unrecorded = analysis.tenders
      .where((t) => t.tender == null)
      .fold(0, (sum, t) => sum + t.minor);

  final summary = StringBuffer();
  if (total == 0) {
    summary.write('Nothing was taken in this period.');
  } else {
    summary.write(
      '${leader.label} is the largest at ${reportPercent(leader.minor / total)} of '
      'takings across ${leader.transactions} '
      '${leader.transactions == 1 ? 'sale' : 'sales'}.',
    );
    if (unrecorded > 0) {
      summary.write(
        ' ${identity.money(unrecorded)} was taken on sales recorded before '
        'this app stored how they were paid for. Those are listed as not '
        'recorded rather than left out, so the shares still add to the '
        'takings.',
      );
    }
  }

  final discount = analysis.discountRate;

  return TenantReportSection(
    heading: 'How it was paid for',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.composition,
      caption: 'Share of takings by payment method',
      valueAxisLabel: 'Takings',
      data: <TenantReportDatum>[
        for (final tender in analysis.tenders)
          TenantReportDatum(
            label: tender.label,
            value: tender.minor / 100,
            formatted: identity.money(tender.minor),
          ),
      ],
    ),
    notes: <String>[
      if (discount != null && analysis.discountMinor > 0)
        'Discounts came to ${identity.money(analysis.discountMinor)}, which is '
            '${reportPercent(discount)} of what would otherwise have been taken.',
      if (analysis.fullyReturnedSales > 0)
        '${analysis.fullyReturnedSales} '
            '${analysis.fullyReturnedSales == 1 ? 'sale was' : 'sales were'} '
            'returned in full. A partly returned sale is still a transaction '
            'that happened and is still counted as one.',
    ],
  );
}

/// How many bars a ranked chart draws before the rest go to the table.
const int _rankedProducts = 10;

/// How many rows the product table carries. The workbook has every one.
const int _listedProducts = 30;
