/// The shifts report: what it reads, and what it says about it.
///
/// **The section that justifies it is *Where the difference sits*.** The shift
/// screen puts a badge on each row of one day; a fortnight of badges is not a
/// pattern anybody can hold in their head. A period can say that of everything
/// short over these days most of it is on one person or one shift, and that is
/// a question somebody can go and ask.
///
/// **The second is *What could not be compared*.** A shift closed without its
/// sales has no variance at all, and a report that printed a clean fortnight
/// while three of its drawers were never counted would be worse than no report.
library;

import '../../shift/shift_history.dart';
import '../../tenancy/tenant_repository.dart';
import '../report_document.dart';
import '../report_identity.dart';
import '../report_people.dart';
import '../report_period.dart';
import '../report_scope.dart';
import '../report_table.dart';
import '../report_visual.dart';
import 'report_prose.dart';
import 'shifts_analysis.dart';

/// Reads the shifts a report covers.
final class TenantShiftsReportSource {
  const TenantShiftsReportSource({
    required this.repository,
    this.pageSize = 50,
    this.maximumPages = 12,
  });

  final TenantShiftHistoryRepository repository;

  final int pageSize;

  /// **A bound, and the report prints it when it is reached.** At 50 a page
  /// this is 600 shifts, which is nearly two years of a three-till shop.
  final int maximumPages;

  /// Every shift in [period], open ones included, up to the page bound.
  Future<({List<TenantShiftDaySlice> shifts, bool truncated})> gather(
    TenantReportPeriod period,
  ) async {
    final slices = <TenantShiftDaySlice>[];
    TenantBusinessDateRangePosition? position;

    for (var page = 0; page < maximumPages; page++) {
      final read = await repository.loadDateRange(
        startBusinessDate: period.startDate,
        endBusinessDate: period.endDate,
        pageSize: pageSize,
        startAfter: position,
      );
      slices.addAll(read.items);
      position = read.next;
      if (position == null) return (shifts: slices, truncated: false);
    }
    return (shifts: slices, truncated: true);
  }

  /// The same read over the preceding comparable window.
  Future<List<TenantShiftDaySlice>?> gatherPrevious(
    TenantReportPeriod period,
  ) async {
    try {
      final read = await gather(period.precedingComparable);
      return read.shifts;
    } on Object {
      return null;
    }
  }
}

/// Turns the analysis into the document both renderers draw.
TenantReportDocument describeShiftsReport({
  required TenantShiftsAnalysis analysis,
  required TenantReportIdentity identity,
  /// Names for the people in 'Per person'. Only management may open this
  /// report, and management may read the whole roster, so a UID here means the
  /// directory could not be reached rather than that it was withheld.
  TenantReportPeople people = const TenantReportPeople.none(),
}) {
  final money = identity.money;

  return TenantReportDocument(
    kind: TenantReportKind.shifts,
    identity: identity,
    scope: _scope(analysis, people),
    subtitle:
        'What ${analysis.shiftCount} shifts took over '
        '${analysis.period.days} days, and where the drawer did not agree.',
    headline: <TenantReportFigure>[
      TenantReportFigure(
        label: 'Taken on shift',
        value: money(analysis.takingsMinor),
        amount: analysis.takingsMinor / 100,
        comparison: analysis.previousTakingsMinor == null
            ? null
            : money(analysis.previousTakingsMinor!),
        amountComparison: analysis.previousTakingsMinor == null
            ? null
            : analysis.previousTakingsMinor! / 100,
        note: 'Across ${reportCount(analysis.closedCount, 'closed shift')}.',
      ),
      TenantReportFigure(
        label: 'Short',
        value: money(analysis.shortMinor),
        amount: analysis.shortMinor / 100,
        note: analysis.shortMinor == 0
            ? 'No drawer came up short in this period.'
            : 'Across the shifts that came up under their takings.',
      ),
      TenantReportFigure(
        label: 'Over',
        value: money(analysis.overMinor),
        amount: analysis.overMinor / 100,
        note: analysis.overMinor == 0
            ? 'No drawer came up over in this period.'
            : 'Kept apart from short: the two do not cancel.',
      ),
    ],
    sections: <TenantReportSection>[
      _difference(analysis, identity, people),
      if (!analysis.isFullyCompared || analysis.openCount > 0)
        _uncompared(analysis),
      if (analysis.people.isNotEmpty) _perPerson(analysis, identity, people),
      if (analysis.closedCount > 0) _byDay(analysis, identity),
    ],
  );
}

TenantReportScope _scope(
  TenantShiftsAnalysis analysis,
  TenantReportPeople people,
) => TenantReportScope(
  period: analysis.period,
  documentsRead: analysis.shiftCount,
  caveats: <TenantReportCaveat>[
    if (people.caveat(
      analysis.people
          .take(TenantShiftsAnalysis.listed)
          .map((person) => person.staffId),
      noun: 'worked a shift',
    ) case final caveat?)
      caveat,
    if (analysis.truncated)
      TenantReportCaveat.truncated(
        asked: analysis.period,
        reachedFrom: analysis.period.startDate,
        reachedTo: analysis.period.endDate,
        records: analysis.shiftCount,
      ),
    if (analysis.unevidencedShifts > 0)
      TenantReportCaveat.noEvidence(
        count: analysis.unevidencedShifts,
        of: 'shifts',
        ofOne: 'shift',
        because: 'were closed by something holding none of their sales',
        becauseOne: 'was closed by something holding none of its sales',
      ),
    if (analysis.uncomparedShifts > 0)
      TenantReportCaveat.noEvidence(
        count: analysis.uncomparedShifts,
        of: 'shifts',
        ofOne: 'shift',
        because: 'recorded no closing declaration to compare',
      ),
    if (analysis.openCount > 0)
      TenantReportCaveat(
        kind: TenantReportCaveatKind.noEvidence,
        sentence:
            '${analysis.openCount} '
            '${analysis.openCount == 1 ? 'shift was' : 'shifts were'} still '
            'running when this was taken. Their drawers have not been counted, '
            'so their takings are not in the figures above and nothing here '
            'settles them.',
      ),
    if (analysis.previousTakingsMinor == null)
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
TenantReportSection _difference(
  TenantShiftsAnalysis analysis,
  TenantReportIdentity identity,
  TenantReportPeople people,
) {
  final money = identity.money;
  final summary = StringBuffer();

  if (analysis.comparedShifts == 0) {
    summary.write(
      'No shift in this period could be compared against its takings, so '
      'nothing is said about the drawer.',
    );
  } else if (analysis.shortMinor == 0 && analysis.overMinor == 0) {
    summary.write(
      'Every one of the ${analysis.comparedShifts} shifts that could be '
      'compared came out level.',
    );
  } else {
    summary.write(
      'Across ${analysis.comparedShifts} shifts that could be compared, '
      '${money(analysis.shortMinor)} came up short and '
      '${money(analysis.overMinor)} came up over',
    );
    summary.write(
      ', a net of ${money(analysis.netVarianceMinor.abs())} '
      '${analysis.netVarianceMinor < 0 ? 'short' : 'over'}.',
    );
    final concentration = analysis.shortConcentration;
    if (concentration != null && concentration > 0.5) {
      summary.write(
        ' More than half of everything short is on one person, so this is a '
        'question about one drawer rather than about the shop.',
      );
    }
    if (analysis.worst case final worst?) {
      summary.write(
        ' The furthest out was ${TenantReportPeriod.day(worst.businessDate).spelled}, '
        'at ${money(worst.varianceMinor.abs())} '
        '${worst.varianceMinor < 0 ? 'short' : 'over'}.',
      );
    }
  }

  return TenantReportSection(
    heading: 'Where the difference sits',
    summary: summary.toString(),
    visual: analysis.shortMinor == 0 && analysis.overMinor == 0
        ? null
        : TenantReportVisual(
            kind: TenantReportVisualKind.variance,
            caption: 'Short by person',
            valueAxisLabel: 'Short',
            data: <TenantReportDatum>[
              for (final person in analysis.people
                  .where((p) => p.shortMinor > 0)
                  .take(8))
                TenantReportDatum(
                  // A chart axis is read before anything else on the page, so
                  // an identifier here is the worst place for one.
                  label: people.label(person.staffId),
                  value: person.shortMinor / 100,
                  formatted: money(person.shortMinor),
                ),
            ],
          ),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Standing', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Shifts', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Amount', kind: TenantReportColumnKind.money),
      ],
      rows: <List<TenantReportCell>>[
        <TenantReportCell>[
          const TenantReportTextCell('Short'),
          TenantReportCountCell(
            analysis.people.where((p) => p.shortMinor > 0).length,
          ),
          TenantReportMoneyCell(
            minor: analysis.shortMinor,
            formatted: money(analysis.shortMinor),
          ),
        ],
        <TenantReportCell>[
          const TenantReportTextCell('Over'),
          TenantReportCountCell(
            analysis.people.where((p) => p.overMinor > 0).length,
          ),
          TenantReportMoneyCell(
            minor: analysis.overMinor,
            formatted: money(analysis.overMinor),
          ),
        ],
      ],
      emphasisRow: analysis.shortMinor > 0 ? 0 : null,
    ),
  );
}

/// The truthfulness section: what the period could not say.
TenantReportSection _uncompared(TenantShiftsAnalysis analysis) {
  final summary = StringBuffer();
  final unknown = analysis.unevidencedShifts + analysis.uncomparedShifts;

  if (unknown > 0) {
    summary.write(
      '$unknown of ${analysis.closedCount} closed shifts '
      '${reportVerb(unknown, 'has', 'have')} no comparison at all. '
      '${reportVerb(unknown, 'It is', 'They are')} left out of every figure '
      'above rather than counted as level: a drawer nobody could check is not '
      'a drawer that balanced.',
    );
  }
  if (analysis.openCount > 0) {
    summary.write(
      ' ${analysis.openCount} '
      '${analysis.openCount == 1 ? 'shift was' : 'shifts were'} still running '
      'when this was taken.',
    );
  }

  return TenantReportSection(
    heading: 'What could not be compared',
    summary: summary.toString(),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Why', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Shifts', kind: TenantReportColumnKind.count),
      ],
      rows: <List<TenantReportCell>>[
        <TenantReportCell>[
          const TenantReportTextCell('Compared against takings'),
          TenantReportCountCell(analysis.comparedShifts),
        ],
        <TenantReportCell>[
          const TenantReportTextCell('Closed without their sales'),
          TenantReportCountCell(analysis.unevidencedShifts),
        ],
        <TenantReportCell>[
          const TenantReportTextCell('Closed with no declaration'),
          TenantReportCountCell(analysis.uncomparedShifts),
        ],
        <TenantReportCell>[
          const TenantReportTextCell('Still running'),
          TenantReportCountCell(analysis.openCount),
        ],
      ],
    ),
  );
}

TenantReportSection _perPerson(
  TenantShiftsAnalysis analysis,
  TenantReportIdentity identity,
  TenantReportPeople people,
) {
  final money = identity.money;
  final busiest = analysis.people.first;
  final summary = StringBuffer(
    analysis.people.length == 1
        ? 'One person worked every shift in this period.'
        : '${analysis.people.length} people worked shifts in this period.',
  );
  if (busiest.shortMinor > 0) {
    summary.write(
      ' ${people.label(busiest.staffId)} carries the most short, at '
      '${money(busiest.shortMinor)} over ${busiest.comparedShifts} compared '
      '${busiest.comparedShifts == 1 ? 'shift' : 'shifts'}.',
    );
  }

  return TenantReportSection(
    heading: 'Per person',
    summary: summary.toString(),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Person', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Shifts', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Taken', kind: TenantReportColumnKind.money),
        TenantReportColumn(heading: 'Short', kind: TenantReportColumnKind.money),
        TenantReportColumn(heading: 'Over', kind: TenantReportColumnKind.money),
      ],
      rows: <List<TenantReportCell>>[
        for (final person in analysis.people.take(TenantShiftsAnalysis.listed))
          <TenantReportCell>[
            TenantReportTextCell(people.label(person.staffId)),
            TenantReportCountCell(person.shifts),
            TenantReportMoneyCell(
              minor: person.takingsMinor,
              formatted: money(person.takingsMinor),
            ),
            if (person.comparedShifts == 0)
              // Nought would say this person's drawers balanced. None of them
              // could be checked.
              const TenantReportAbsentCell('no shift could be compared')
            else
              TenantReportMoneyCell(
                minor: person.shortMinor,
                formatted: money(person.shortMinor),
              ),
            if (person.comparedShifts == 0)
              const TenantReportAbsentCell('no shift could be compared')
            else
              TenantReportMoneyCell(
                minor: person.overMinor,
                formatted: money(person.overMinor),
              ),
          ],
      ],
    ),
  );
}

TenantReportSection _byDay(
  TenantShiftsAnalysis analysis,
  TenantReportIdentity identity,
) {
  final money = identity.money;
  final perShift = analysis.takingsPerShiftMinor;
  final summary = StringBuffer();
  if (perShift != null) {
    summary.write(
      'A closed shift took ${money(perShift.round())} on average across the '
      'period.',
    );
  }
  if (analysis.quietDays > 0) {
    summary.write(
      ' ${analysis.quietDays} of the ${analysis.dailyTakingsMinor.length} days '
      'took nothing on any shift, and are drawn as the zeroes they were.',
    );
  }
  if (analysis.change case final moved?) {
    summary.write(
      ' Takings are ${reportDirection(moved)} on the ${analysis.period.days} '
      'days before this period.',
    );
  }

  return TenantReportSection(
    heading: 'Taken by day',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.trend,
      caption: 'Taken on shift each day',
      valueAxisLabel: 'Taken',
      data: <TenantReportDatum>[
        for (final entry in analysis.dailyTakingsMinor.entries)
          TenantReportDatum(
            label: reportShortDate(entry.key),
            value: entry.value / 100,
            formatted: money(entry.value),
          ),
      ],
    ),
  );
}
