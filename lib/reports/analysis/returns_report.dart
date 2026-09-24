/// The returns report: what it reads, and what it says about it.
///
/// **Two findings the screen cannot reach.** *Which lines come back* turns a
/// list of individual reversals into the three or four products a shop keeps
/// losing; *Waiting on verification* counts the stock that is physically back
/// on the shelf and still absent from the books, because the server restores it
/// only when a manager verifies. Everything else here is context for those two.
library;

import '../../returns/return_history.dart';
import '../../returns/return_offsets.dart';
import '../../sales/sale_history.dart';
import '../../tenancy/tenant_repository.dart';
import '../report_document.dart';
import '../report_identity.dart';
import '../report_people.dart';
import '../report_period.dart';
import '../report_scope.dart';
import '../report_table.dart';
import '../report_visual.dart';
import 'report_prose.dart';
import 'returns_analysis.dart';

/// Reads the returns a report covers, and prices them against their sales.
final class TenantReturnsReportSource {
  const TenantReturnsReportSource({
    required this.repository,
    required this.sales,
    this.pageSize = 50,
    this.maximumPages = 12,
    this.maximumPricedSales = 120,
  });

  final TenantReturnHistoryRepository repository;

  /// Reads the sale behind each return, which is the only place a price lives.
  ///
  /// A return line carries a product and a quantity and no money at all, so a
  /// value is always a joined figure. See `return_offsets.dart`.
  final TenantSaleHistoryRepository sales;

  final int pageSize;

  /// **A bound, and the report prints it when it is reached.** At 50 a page
  /// this is 600 returns, which is not a busy month - it is a fault.
  final int maximumPages;

  /// How many sales the valuation will read.
  ///
  /// **A separate bound, because this one costs a document each.** Paging
  /// returns is one read per fifty; pricing them is one read per *sale* they
  /// were filed against. A period past this keeps every unit it counted and
  /// states no money, which is the honest half of the answer rather than a
  /// wrong whole one.
  final int maximumPricedSales;

  /// Every return taken in [period], up to the page bound.
  Future<({List<TenantReturn> returns, bool truncated})> gather(
    TenantReportPeriod period,
  ) async {
    final records = <TenantReturn>[];
    TenantBusinessDateRangePosition? position;

    for (var page = 0; page < maximumPages; page++) {
      final read = await repository.loadRecordedRange(
        startRecordedOn: period.startDate,
        endRecordedOn: period.endDate,
        pageSize: pageSize,
        startAfter: position,
      );
      records.addAll(read.items);
      position = read.next;
      if (position == null) return (returns: records, truncated: false);
    }
    return (returns: records, truncated: true);
  }

  /// The same read over the preceding comparable window.
  ///
  /// Null where it could not be read at all, which the report says rather than
  /// drawing as a period in which nothing was returned.
  Future<List<TenantReturn>?> gatherPrevious(TenantReportPeriod period) async {
    try {
      final read = await gather(period.precedingComparable);
      return read.returns;
    } on Object {
      return null;
    }
  }

  /// Prices [records] by reading the sales they reverse.
  ///
  /// **Grouped by sale before anything is read.** Two returns filed against one
  /// sale are one read and one pro-rata calculation; doing it per return would
  /// pay twice and then double-count the money.
  Future<Map<String, TenantSaleReturnOffset>> value(
    List<TenantReturn> records,
  ) async {
    final unitsBySale = <String, Map<String, int>>{};
    for (final record in records) {
      final units = unitsBySale.putIfAbsent(
        record.saleId,
        () => <String, int>{},
      );
      for (final line in record.lines) {
        units[line.productId] = (units[line.productId] ?? 0) + line.quantity;
      }
    }
    if (unitsBySale.length > maximumPricedSales) {
      return const <String, TenantSaleReturnOffset>{};
    }

    final valued = <String, TenantSaleReturnOffset>{};
    for (final entry in unitsBySale.entries) {
      // **One unreadable sale does not cost the whole valuation.** A return
      // filed against a sale this device cannot read is one the report prices
      // in units alone; the others are still worth stating, and the scope
      // block says how many were priced.
      try {
        final sale = await sales.readSale(entry.key);
        if (sale == null) continue;
        valued[entry.key] = describeReturnOffset(sale, entry.value);
      } on Object {
        continue;
      }
    }
    return valued;
  }
}

/// Turns the analysis into the document both renderers draw.
TenantReportDocument describeReturnsReport({
  required TenantReturnsAnalysis analysis,
  required TenantReportIdentity identity,
  /// Names for the people in 'Who recorded them'. A caller with no directory
  /// read passes [TenantReportPeople.none] and the table prints UIDs.
  TenantReportPeople people = const TenantReportPeople.none(),
}) {
  final money = identity.money;

  return TenantReportDocument(
    kind: TenantReportKind.returns,
    identity: identity,
    scope: _scope(analysis, people),
    subtitle:
        'What came back over ${analysis.period.days} days, which lines it '
        'came back on, and what is still waiting to be put right.',
    headline: <TenantReportFigure>[
      TenantReportFigure(
        label: 'Units returned',
        value: analysis.returnedUnits.toString(),
        amount: analysis.returnedUnits,
        amountKind: TenantReportColumnKind.count,
        comparison: analysis.previousUnits?.toString(),
        amountComparison: analysis.previousUnits,
        note: 'Across ${reportCount(analysis.recordCount, 'return')}.',
      ),
      TenantReportFigure(
        label: 'Value returned',
        value: analysis.returnedMinor == null
            ? TenantReportAbsentCell.notRecorded
            : money(analysis.returnedMinor!),
        amount: analysis.returnedMinor == null
            ? null
            : analysis.returnedMinor! / 100,
        note: _valueNote(analysis),
      ),
      TenantReportFigure(
        label: 'Not yet verified',
        value: analysis.pendingCount.toString(),
        amount: analysis.pendingCount,
        amountKind: TenantReportColumnKind.count,
        note: analysis.pendingCount == 0
            ? 'Every return was verified, so every unit is back on the books.'
            : '${reportCount(analysis.pendingUnits, 'unit')} '
                  '${reportVerb(analysis.pendingUnits, 'is', 'are')} back on '
                  'the shelf and not yet back in stock.',
      ),
    ],
    sections: <TenantReportSection>[
      if (analysis.lines.isNotEmpty) _byLine(analysis, identity),
      _waiting(analysis),
      if (analysis.returnedUnits > 0) _byDay(analysis),
      if (analysis.recorders.isNotEmpty) _byRecorder(analysis, people),
      if (analysis.reasons.isNotEmpty) _byReason(analysis),
    ],
  );
}

String _valueNote(TenantReturnsAnalysis analysis) {
  if (analysis.recordCount == 0) return 'Nothing came back in this period.';
  if (analysis.returnedMinor == null) {
    return 'The sales behind these returns were not read, so no value is '
        'stated. The units above are complete.';
  }
  if (analysis.isFullyValued) {
    return 'Priced against the sales the goods went out on.';
  }
  return 'Covers ${analysis.valuedReturns} of ${analysis.recordCount} '
      'returns. The rest name a sale that could not be read.';
}

TenantReportScope _scope(
  TenantReturnsAnalysis analysis,
  TenantReportPeople people,
) => TenantReportScope(
  period: analysis.period,
  documentsRead: analysis.recordCount,
  caveats: <TenantReportCaveat>[
    // **The one report a cashier may generate**, and a cashier may read only
    // its own staff record, so this is the only place the fallback is reached
    // in ordinary use rather than in a fault.
    if (people.caveat(
      analysis.recorders
          .take(TenantReturnsAnalysis.listed)
          .map((person) => person.staffId),
      noun: 'recorded a return',
    ) case final caveat?)
      caveat,
    if (analysis.truncated)
      TenantReportCaveat.truncated(
        asked: analysis.period,
        reachedFrom: analysis.period.startDate,
        reachedTo: analysis.period.endDate,
        records: analysis.recordCount,
      ),
    if (analysis.recordCount > 0 && !analysis.isFullyValued)
      TenantReportCaveat(
        kind: TenantReportCaveatKind.noEvidence,
        sentence:
            '${analysis.recordCount - analysis.valuedReturns} of '
            '${analysis.recordCount} returns name a sale that could not be '
            'read, so no money is attributed to them. Every unit is counted; '
            'the value below is a floor.',
      ),
    if (analysis.previousUnits == null)
      const TenantReportCaveat(
        kind: TenantReportCaveatKind.noEvidence,
        sentence:
            'The period before this one could not be read, so nothing here is '
            'compared against it. The figures for the period asked for are '
            'complete.',
      ),
  ],
);

/// The section the report exists for.
TenantReportSection _byLine(
  TenantReturnsAnalysis analysis,
  TenantReportIdentity identity,
) {
  final top = analysis.lines.first;
  final few = analysis.linesFor(0.75);
  final concentration = analysis.concentration;

  final summary = StringBuffer(
    '${top.name} came back most, at ${top.units} of the '
    '${analysis.returnedUnits} units returned',
  );
  if (concentration != null) {
    summary.write(' - ${reportPercent(concentration)} of everything returned');
  }
  summary.write('.');
  if (few != null && few < analysis.lines.length) {
    summary.write(
      ' $few of the ${analysis.lines.length} products '
      '${reportVerb(few, 'carries', 'carry')} three quarters of it.',
    );
  }
  if (concentration != null && concentration > 0.5) {
    summary.write(
      ' More than half of what comes back is one product, which is a question '
      'about that product rather than about returns.',
    );
  }

  final listed = analysis.lines.take(TenantReturnsAnalysis.listed).toList();

  return TenantReportSection(
    heading: 'Which lines come back',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.ranked,
      caption: 'Units returned by product',
      valueAxisLabel: 'Units',
      data: <TenantReportDatum>[
        for (final line in listed.take(8))
          TenantReportDatum(
            label: line.name,
            value: line.units.toDouble(),
            formatted: '${line.units}',
          ),
      ],
    ),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Product', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Units', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Value', kind: TenantReportColumnKind.money),
      ],
      rows: <List<TenantReportCell>>[
        for (final line in listed)
          <TenantReportCell>[
            TenantReportTextCell(line.name),
            TenantReportCountCell(line.units),
            if (line.minor case final minor?)
              TenantReportMoneyCell(
                minor: minor,
                formatted: identity.money(minor),
              )
            else
              // Not nought: these units came back, and what they were worth is
              // unknown rather than nothing.
              const TenantReportAbsentCell('the sale could not be read'),
          ],
      ],
    ),
    notes: <String>[
      if (listed.length < analysis.lines.length)
        '${reportCount(analysis.lines.length - listed.length, 'product')} '
            'below these '
            '${reportVerb(analysis.lines.length - listed.length, 'is', 'are')} '
            'in the workbook.',
    ],
  );
}

/// The actionable section: stock off the books.
TenantReportSection _waiting(TenantReturnsAnalysis analysis) {
  final summary = StringBuffer();
  if (analysis.recordCount == 0) {
    summary.write('Nothing was returned in this period.');
  } else if (analysis.pendingCount == 0) {
    summary.write(
      'Every return in this period was verified, so every unit that came back '
      'is back in stock.',
    );
  } else {
    summary.write(
      '${analysis.pendingCount} of ${analysis.recordCount} returns have not '
      'been verified. Stock is restored on verification and not before, so '
      '${analysis.pendingUnits} units are on the shelf and not in the figures '
      'the books show.',
    );
  }
  if (analysis.medianWait case final wait?) {
    summary.write(
      ' The middle return waited ${reportDuration(wait)} to be verified.',
    );
  }

  return TenantReportSection(
    heading: 'Waiting on verification',
    summary: summary.toString(),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Standing', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Returns', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Units', kind: TenantReportColumnKind.count),
      ],
      rows: <List<TenantReportCell>>[
        <TenantReportCell>[
          const TenantReportTextCell('Verified, stock restored'),
          TenantReportCountCell(analysis.verifiedCount),
          TenantReportCountCell(analysis.returnedUnits - analysis.pendingUnits),
        ],
        <TenantReportCell>[
          const TenantReportTextCell('Awaiting verification'),
          TenantReportCountCell(analysis.pendingCount),
          TenantReportCountCell(analysis.pendingUnits),
        ],
      ],
      emphasisRow: analysis.pendingCount > 0 ? 1 : null,
    ),
  );
}

TenantReportSection _byDay(TenantReturnsAnalysis analysis) {
  final heaviest = analysis.heaviestDate;
  final summary = StringBuffer();
  if (heaviest != null) {
    summary.write(
      'The most came back on ${TenantReportPeriod.day(heaviest).spelled}, at '
      '${analysis.dailyUnits[heaviest]} units.',
    );
  }
  if (analysis.quietDays > 0) {
    summary.write(
      ' ${analysis.quietDays} of the ${analysis.dailyUnits.length} days had '
      'nothing come back at all, and are drawn as the zeroes they were.',
    );
  }
  if (analysis.change case final moved?) {
    summary.write(
      ' Units are ${reportDirection(moved)} on the ${analysis.period.days} '
      'days before this period.',
    );
  }

  return TenantReportSection(
    heading: 'When it came back',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.trend,
      caption: 'Units returned each day',
      valueAxisLabel: 'Units',
      data: <TenantReportDatum>[
        for (final entry in analysis.dailyUnits.entries)
          TenantReportDatum(
            label: reportShortDate(entry.key),
            value: entry.value.toDouble(),
            formatted: '${entry.value}',
          ),
      ],
    ),
  );
}

TenantReportSection _byRecorder(
  TenantReturnsAnalysis analysis,
  TenantReportPeople people,
) {
  final busiest = analysis.recorders.first;
  final summary = StringBuffer(
    analysis.recorders.length == 1
        ? 'Every return in this period was put through by one person.'
        : '${analysis.recorders.length} people recorded returns. The most was '
              '${busiest.returns} of ${analysis.recordCount}.',
  );
  summary.write(
    ' Whoever is at the till takes the return, so this is the shape of the '
    'shifts as much as of the people - it is here to be asked about, not to '
    'be read as a finding on its own.',
  );

  return TenantReportSection(
    heading: 'Who recorded them',
    summary: summary.toString(),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Recorded by', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Returns', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Units', kind: TenantReportColumnKind.count),
      ],
      rows: <List<TenantReportCell>>[
        for (final person
            in analysis.recorders.take(TenantReturnsAnalysis.listed))
          <TenantReportCell>[
            TenantReportTextCell(people.label(person.staffId)),
            TenantReportCountCell(person.returns),
            TenantReportCountCell(person.units),
          ],
      ],
    ),
  );
}

TenantReportSection _byReason(TenantReturnsAnalysis analysis) {
  final top = analysis.reasons.first;
  final repeated = analysis.reasons.where((r) => r.count > 1).length;

  final summary = StringBuffer();
  if (repeated == 0) {
    summary.write(
      'Every return was given its own reason, so there is no pattern in the '
      'wording to report.',
    );
  } else {
    summary.write(
      '"${top.reason}" was given ${top.count} times, and $repeated '
      '${repeated == 1 ? 'reason was' : 'reasons were'} used more than once.',
    );
  }
  summary.write(
    ' A reason is free text typed at the till, so these are grouped by exact '
    'wording and nothing is inferred from two that mean the same thing.',
  );

  return TenantReportSection(
    heading: 'Why',
    summary: summary.toString(),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Reason given', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Times', kind: TenantReportColumnKind.count),
      ],
      rows: <List<TenantReportCell>>[
        for (final reason in analysis.reasons.take(TenantReturnsAnalysis.listed))
          <TenantReportCell>[
            TenantReportTextCell(reason.reason),
            TenantReportCountCell(reason.count),
          ],
      ],
    ),
  );
}
