/// The staff report: staff against each other, and what that is allowed to say.
///
/// **One sales read, grouped by who rang it up.** Not two server callables per
/// person: the sales for the period are read once with no staff filter, and the
/// grouping happens here. That is a single paged walk rather than 2N round
/// trips, it works with no callable wired at all, and it carries the line-level
/// cost data a margin needs - which a totals callable does not.
///
/// **And the whole roster, or no shares.** The staff screen removed four
/// counters because a figure assembled from the page currently on screen was a
/// lie. This report reads every page of the directory before it quotes a share
/// of anything; where it could not, every ranked figure still prints - those
/// are exact for the person named - and every share is withheld with a sentence
/// saying why.
library;

import '../../tenancy/tenant_staff_directory.dart';
import '../report_document.dart';
import '../report_identity.dart';
import '../report_scope.dart';
import '../report_table.dart';
import '../report_visual.dart';
import 'sales_report.dart';
import 'report_prose.dart';
import 'staff_analysis.dart';

/// Reads the roster and the trading a staff report compares.
final class TenantStaffReportSource {
  const TenantStaffReportSource({
    required this.directory,
    required this.sales,
    this.pageSize = 50,
    this.maximumPages = 8,
  });

  final TenantStaffDirectoryRepository directory;
  final TenantSalesReportSource sales;

  /// The repository's ceiling.
  final int pageSize;

  /// At 50 a page this is 400 people, which is far past the shops this app
  /// serves. Reaching it means the shares cannot be quoted, not that the
  /// report fails.
  final int maximumPages;

  /// Every member of the directory, and whether the walk actually finished.
  Future<({List<TenantStaffSummary> roster, bool complete})> gatherRoster() async {
    final roster = <TenantStaffSummary>[];
    String? cursor;
    var pages = 0;

    while (pages < maximumPages) {
      final page = await directory.loadPage(pageSize: pageSize, cursor: cursor);
      roster.addAll(page.items);
      pages++;
      if (!page.hasMore || page.nextCursor == null) {
        return (roster: roster, complete: true);
      }
      cursor = page.nextCursor;
    }
    return (roster: roster, complete: false);
  }
}

/// Turns the analysis into the document both renderers draw.
TenantReportDocument describeStaffReport({
  required TenantStaffAnalysis analysis,
  required TenantReportIdentity identity,
}) {
  final money = identity.money;
  final trading = analysis.trading;

  return TenantReportDocument(
    kind: TenantReportKind.staff,
    identity: identity,
    scope: _scope(analysis),
    subtitle:
        'Who took what over ${analysis.period.days} days, against the '
        '${analysis.period.days} days before it.',
    headline: <TenantReportFigure>[
      TenantReportFigure(
        label: 'On the roster',
        value: analysis.directoryCount.toString(),
        amount: analysis.directoryCount,
        amountKind: TenantReportColumnKind.count,
        note: analysis.idle.isEmpty
            ? null
            : '${analysis.idle.length} rang nothing up in this period.',
      ),
      TenantReportFigure(
        label: 'Takings',
        value: money(analysis.revenueMinor),
        amount: analysis.revenueMinor / 100,
        note: trading.isEmpty
            ? null
            : 'Across ${trading.length} '
                  '${trading.length == 1 ? 'person' : 'people'}.',
      ),
      TenantReportFigure(
        label: 'The middle sale',
        value: money(analysis.medianAverageSaleMinor),
        amount: analysis.medianAverageSaleMinor / 100,
        note: 'The median of each person\'s own average, so one very good '
            'fortnight does not move the line the others are read against.',
      ),
    ],
    sections: <TenantReportSection>[
      if (trading.isNotEmpty) _ranked(analysis, identity),
      if (trading.isNotEmpty) _againstTheMiddle(analysis, identity),
      if (analysis.concentration != null) _concentration(analysis, identity),
      _table(analysis, identity),
    ],
  );
}

TenantReportScope _scope(TenantStaffAnalysis analysis) {
  final caveats = <TenantReportCaveat>[
    if (!analysis.isComplete)
      TenantReportCaveat.partialDirectory(
        read: analysis.directoryCount,
        of: 'staff records',
      ),
    if (analysis.truncated)
      TenantReportCaveat.truncated(
        asked: analysis.period,
        reachedFrom: analysis.period.startDate,
        reachedTo: analysis.period.endDate,
        records: analysis.transactions,
      ),
  ];

  return TenantReportScope(
    period: analysis.period,
    documentsRead: analysis.documentsRead,
    caveats: caveats,
  );
}

/// Who took the most, and how that moved.
TenantReportSection _ranked(
  TenantStaffAnalysis analysis,
  TenantReportIdentity identity,
) {
  final trading = analysis.trading;
  final leader = trading.first;
  final summary = StringBuffer(
    '${leader.name} took the most at ${identity.money(leader.revenueMinor)}',
  );

  final share = analysis.shareOf(leader);
  if (share != null) {
    summary.write(', which is ${reportPercent(share)} of the period');
  }
  summary.write('.');

  final climber = _biggestClimb(analysis);
  if (climber != null) {
    final moved = analysis.rankChangeOf(climber)!;
    summary.write(
      ' ${climber.name} moved ${moved.abs()} '
      '${moved.abs() == 1 ? 'place' : 'places'} ${moved > 0 ? 'up' : 'down'} '
      'the order against the period before.',
    );
  }

  if (analysis.idle.isNotEmpty) {
    final idle = analysis.idle.length;
    summary.write(
      ' $idle on the roster rang nothing up at all, and '
      '${idle == 1 ? 'is' : 'are'} listed at the end rather than left out.',
    );
  }

  return TenantReportSection(
    heading: 'Who took the most',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.ranked,
      caption: 'Takings by person',
      valueAxisLabel: 'Takings',
      data: <TenantReportDatum>[
        for (final person in trading)
          TenantReportDatum(
            label: person.name,
            value: person.revenueMinor / 100,
            formatted: identity.money(person.revenueMinor),
            emphasis: person.uid == leader.uid,
          ),
      ],
    ),
  );
}

/// Each person's average sale against the shop's middle.
///
/// The comparison the developer asked for by name: not a list of people with
/// numbers beside them, but each person read against the rest.
TenantReportSection _againstTheMiddle(
  TenantStaffAnalysis analysis,
  TenantReportIdentity identity,
) {
  final middle = analysis.medianAverageSaleMinor;
  final trading = analysis.trading;
  final above = trading.where((p) => p.averageSaleMinor > middle).length;

  final summary = StringBuffer(
    'Each person\'s average sale against the shop\'s middle of '
    '${identity.money(middle)}. $above of ${trading.length} sit above it.',
  );

  final biggest = trading.reduce(
    (a, b) => b.averageBasket > a.averageBasket ? b : a,
  );
  summary.write(
    ' ${biggest.name} puts the most in a basket at '
    '${biggest.averageBasket.toStringAsFixed(1)} items a sale.',
  );

  if (analysis.discountOutlier case final outlier?) {
    summary.write(
      ' ${outlier.name} gives away ${reportPercent(outlier.discountRate!)} in '
      'discounts, well clear of the rest of the shop - which is a question '
      'rather than a fault.',
    );
  }

  return TenantReportSection(
    heading: 'Against the middle',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.comparison,
      caption: 'Average sale, against the shop median',
      valueAxisLabel: 'Average sale',
      comparisonLabel: 'The shop median',
      // A line to be read against, not an earlier period. Without this the
      // figures below would say a person whose average sits under the median
      // had *fallen* by that much, which is a trend nobody measured.
      comparisonKind: TenantReportComparisonKind.reference,
      data: <TenantReportDatum>[
        for (final person in trading)
          TenantReportDatum(
            label: person.name,
            value: person.averageSaleMinor / 100,
            formatted: identity.money(person.averageSaleMinor),
            comparison: middle / 100,
            comparisonFormatted: identity.money(middle),
            emphasis: person.averageSaleMinor > middle,
          ),
      ],
    ),
  );
}

/// How far the shop leans on one person.
TenantReportSection _concentration(
  TenantStaffAnalysis analysis,
  TenantReportIdentity identity,
) {
  final concentration = analysis.concentration!;
  final few = analysis.headCountFor(0.75);
  final trading = analysis.trading;

  final summary = StringBuffer(
    '${trading.first.name} alone is ${reportPercent(concentration)} of the '
    'period\'s takings.',
  );
  if (few != null && few < trading.length) {
    summary.write(
      ' $few of ${trading.length} take three quarters of everything, so the '
      'shop\'s week depends on a short list of people being there.',
    );
  }

  return TenantReportSection(
    heading: 'How the takings are spread',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.composition,
      caption: 'Share of takings by person',
      valueAxisLabel: 'Takings',
      data: <TenantReportDatum>[
        for (final person in trading)
          TenantReportDatum(
            label: person.name,
            value: person.revenueMinor / 100,
            formatted: identity.money(person.revenueMinor),
          ),
      ],
    ),
  );
}

TenantReportSection _table(
  TenantStaffAnalysis analysis,
  TenantReportIdentity identity,
) => TenantReportSection(
  heading: 'Everybody, in full',
  summary: analysis.isComplete
      ? 'Every person on the roster, whether or not they traded. The figures '
            'are exact for each one.'
      : 'The people whose records were read. The directory walk did not '
            'finish, so this is not the whole roster and no share of the '
            'whole is quoted anywhere in this report.',
  table: TenantReportTable(
    columns: const <TenantReportColumn>[
      TenantReportColumn(heading: 'Person', kind: TenantReportColumnKind.text),
      TenantReportColumn(heading: 'Role', kind: TenantReportColumnKind.text),
      TenantReportColumn(
        heading: 'Sales',
        kind: TenantReportColumnKind.count,
      ),
      TenantReportColumn(
        heading: 'Takings',
        kind: TenantReportColumnKind.money,
      ),
      TenantReportColumn(
        heading: 'Average sale',
        kind: TenantReportColumnKind.money,
      ),
      TenantReportColumn(
        heading: 'Margin',
        kind: TenantReportColumnKind.money,
      ),
    ],
    rows: <List<TenantReportCell>>[
      for (final person in analysis.people)
        <TenantReportCell>[
          TenantReportTextCell(person.name),
          TenantReportTextCell(person.role.name),
          TenantReportCountCell(person.transactions),
          TenantReportMoneyCell(
            minor: person.revenueMinor,
            formatted: identity.money(person.revenueMinor),
          ),
          if (person.soldNothing)
            const TenantReportAbsentCell('rang nothing up in this period')
          else
            TenantReportMoneyCell(
              minor: person.averageSaleMinor,
              formatted: identity.money(person.averageSaleMinor),
            ),
          // An unknown margin is not a large one, and on a page comparing
          // people it would be worse than useless - it would rank whoever's
          // lines record least at the top.
          if (person.marginMinor case final margin?)
            TenantReportMoneyCell(
              minor: margin,
              formatted: identity.money(margin),
            )
          else
            const TenantReportAbsentCell('no cost recorded on these lines'),
        ],
    ],
  ),
  notes: <String>[
    if (analysis.people.any((p) => p.name == 'No longer on the roster'))
      'Takings by somebody no longer on the roster are kept, because the sale '
          'still happened and the money is still the shop\'s.',
  ],
);

/// The person who moved furthest up the order, or null where nobody did.
TenantStaffPerformance? _biggestClimb(TenantStaffAnalysis analysis) {
  TenantStaffPerformance? best;
  var bestMove = 0;
  for (final person in analysis.trading) {
    final moved = analysis.rankChangeOf(person);
    if (moved == null || moved == 0) continue;
    if (moved.abs() > bestMove.abs()) {
      bestMove = moved;
      best = person;
    }
  }
  return best;
}

