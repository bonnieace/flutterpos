/// The activity report: what it reads, and what it says about it.
///
/// **This is the one the first phase deferred.** The trail is keyed by a
/// digest, so until it gained a `createdAt` ordering there was no way to ask it
/// for a period at all - the screen's day filter is a sieve over one page and
/// says so. `TenantAuditLogRepository.loadRecordedRange` is what changed.
///
/// **The section that justifies it is *Alerts*.** A `critical` record is
/// written by the platform's own impact scan - a business left with no active
/// administrator, an owner who cannot be reached - and it is exactly the event
/// an owner needs to see and would never be scrolling the trail to find.
library;

import '../../audit/audit_log.dart';
import '../../checkout/checkout_draft.dart';
import '../../tenancy/tenant_repository.dart';
import '../report_document.dart';
import '../report_identity.dart';
import '../report_people.dart';
import '../report_period.dart';
import '../report_scope.dart';
import '../report_table.dart';
import '../report_visual.dart';
import 'logs_analysis.dart';
import 'report_prose.dart';

/// Reads the trail a report covers.
final class TenantLogsReportSource {
  const TenantLogsReportSource({
    required this.repository,
    this.pageSize = 50,
    this.maximumPages = 12,
  });

  final TenantAuditLogRepository repository;

  final int pageSize;

  /// **A bound, and the report prints it when it is reached.** At 50 a page
  /// this is 600 events, which is a very busy month for a trail that records
  /// staff changes and stock corrections.
  final int maximumPages;

  /// Every event recorded in [period], up to the page bound.
  ///
  /// **The period's own boundaries, in business-day terms.** A trail records
  /// UTC instants, so the first day starts at its opening moment and the last
  /// ends at its closing one - reading calendar midnights would clip the
  /// evening of the last day off the report.
  Future<({List<TenantAuditRecord> records, bool truncated})> gather(
    TenantReportPeriod period,
  ) async {
    final records = <TenantAuditRecord>[];
    TenantInstantRangePosition? position;

    for (var page = 0; page < maximumPages; page++) {
      final read = await repository.loadRecordedRange(
        startAt: _startOf(period),
        endAt: _endOf(period),
        pageSize: pageSize,
        startAfter: position,
      );
      records.addAll(read.items);
      position = read.next;
      if (position == null) return (records: records, truncated: false);
    }
    return (records: records, truncated: true);
  }

  /// The same read over the preceding comparable window.
  Future<List<TenantAuditRecord>?> gatherPrevious(
    TenantReportPeriod period,
  ) async {
    try {
      final read = await gather(period.precedingComparable);
      return read.records;
    } on Object {
      return null;
    }
  }

  /// Midnight Nairobi on the period's first day, as a UTC instant.
  static DateTime _startOf(TenantReportPeriod period) =>
      DateTime.parse('${period.startDate}T00:00:00Z').subtract(
        checkoutBusinessDayOffset,
      );

  /// The last instant of the period's final day, as a UTC instant.
  static DateTime _endOf(TenantReportPeriod period) =>
      DateTime.parse('${period.endDate}T23:59:59.999Z').subtract(
        checkoutBusinessDayOffset,
      );
}

/// Turns the analysis into the document both renderers draw.
TenantReportDocument describeLogsReport({
  required TenantLogsAnalysis analysis,
  required TenantReportIdentity identity,
  /// Names for the members in 'Who made the changes' and 'Raised by'.
  ///
  /// **Only the members.** A platform actor is not a person and has no staff
  /// record; it is named by the actor type the server wrote, which is already
  /// a word rather than an identifier.
  TenantReportPeople people = const TenantReportPeople.none(),
}) => TenantReportDocument(
  kind: TenantReportKind.logs,
  identity: identity,
  scope: _scope(analysis, people),
  subtitle:
      'Every recorded change to this business over '
      '${analysis.period.days} days, who made it, and what needs answering.',
  headline: <TenantReportFigure>[
    TenantReportFigure(
      label: 'Events recorded',
      value: analysis.recordCount.toString(),
      amount: analysis.recordCount,
      amountKind: TenantReportColumnKind.count,
      comparison: analysis.previousCount?.toString(),
      amountComparison: analysis.previousCount,
      note: analysis.events.isEmpty
          ? 'Nothing was recorded in this period.'
          : 'Across ${reportCount(analysis.events.length, 'kind')} of event.',
    ),
    TenantReportFigure(
      label: 'Needing an answer',
      value: analysis.criticalCount.toString(),
      amount: analysis.criticalCount,
      amountKind: TenantReportColumnKind.count,
      note: analysis.isClear
          ? 'Nothing in this period was flagged.'
          : 'Flagged by the platform, not by this business.',
    ),
    TenantReportFigure(
      label: 'Done by the platform',
      value: analysis.platformEvents.toString(),
      amount: analysis.platformEvents,
      amountKind: TenantReportColumnKind.count,
      note: analysis.platformEvents == 0
          ? 'Every change was made by a member of this business.'
          : 'The rest, ${analysis.memberEvents}, were made by members of this '
                'business.',
    ),
  ],
  sections: <TenantReportSection>[
    _alerts(analysis, people),
    if (analysis.events.isNotEmpty) _whatHappened(analysis),
    if (analysis.actors.isNotEmpty) _whoDidIt(analysis, people),
    if (analysis.recordCount > 0) _byDay(analysis),
  ],
);

TenantReportScope _scope(
  TenantLogsAnalysis analysis,
  TenantReportPeople people,
) => TenantReportScope(
  period: analysis.period,
  documentsRead: analysis.recordCount,
  caveats: <TenantReportCaveat>[
    if (people.caveat(
      analysis.actors
          .take(TenantLogsAnalysis.listed)
          .where((actor) => !actor.isPlatform)
          .map((actor) => actor.actor),
      noun: 'made a change',
    ) case final caveat?)
      caveat,
    if (analysis.truncated)
      TenantReportCaveat.truncated(
        asked: analysis.period,
        reachedFrom: analysis.period.startDate,
        reachedTo: analysis.period.endDate,
        records: analysis.recordCount,
      ),
    // **The trail's own shape, stated once.** An event with no recorded
    // instant cannot appear in a period read at all, and a reader comparing
    // this against the screen's unfiltered page deserves to know why the two
    // can differ.
    const TenantReportCaveat(
      kind: TenantReportCaveatKind.missingTimestamps,
      sentence:
          'This period is read by the instant each event was recorded. An '
          'event written without one cannot be placed in a period and is not '
          'here; the trail on screen still lists it.',
    ),
    if (analysis.unmodelledEvents > 0)
      TenantReportCaveat(
        kind: TenantReportCaveatKind.noEvidence,
        sentence:
            '${reportCount(analysis.unmodelledEvents, 'event')} '
            '${reportVerb(analysis.unmodelledEvents, 'is', 'are')} of a kind '
            'this app has no name for yet, usually because the server began '
            'recording something new. '
            '${reportVerb(analysis.unmodelledEvents, 'It is', 'They are')} '
            'listed under a raw name rather than left out.',
      ),
    if (analysis.previousCount == null)
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
TenantReportSection _alerts(
  TenantLogsAnalysis analysis,
  TenantReportPeople people,
) {
  final summary = StringBuffer();
  if (analysis.isClear) {
    summary.write(
      'Nothing in this period was flagged. The platform raises these itself '
      'when a business is left without an active administrator or an owner it '
      'can reach, so an empty section here is the good outcome.',
    );
  } else {
    summary.write(
      '${analysis.criticalCount} '
      '${analysis.criticalCount == 1 ? 'event was' : 'events were'} flagged by '
      'the platform. These are raised by an automatic scan rather than by '
      'anybody in this business, and each one names a state somebody has to '
      'put right.',
    );
  }

  return TenantReportSection(
    heading: 'Alerts',
    summary: summary.toString(),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Event', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Raised by', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'When', kind: TenantReportColumnKind.text),
      ],
      rows: <List<TenantReportCell>>[
        if (analysis.critical.isEmpty)
          <TenantReportCell>[
            const TenantReportTextCell('Nothing was flagged'),
            const TenantReportAbsentCell('nothing to attribute'),
            const TenantReportAbsentCell('nothing to date'),
          ]
        else
          for (final record in analysis.critical.take(TenantLogsAnalysis.listed))
            <TenantReportCell>[
              TenantReportTextCell(record.type?.label ?? record.eventType),
              TenantReportTextCell(
                // The actor type first, because a platform actor is named by
                // what it is rather than by a person; a member is named.
                record.actorType ??
                    (record.actorUid == null
                        ? 'unattributed'
                        : people.label(record.actorUid!)),
              ),
              if (record.recordedAt case final at?)
                TenantReportTextCell(checkoutBusinessDate(at))
              else
                const TenantReportAbsentCell('no instant was recorded'),
            ],
      ],
      emphasisRow: analysis.critical.isEmpty ? null : 0,
    ),
  );
}

TenantReportSection _whatHappened(TenantLogsAnalysis analysis) {
  final top = analysis.events.first;
  final summary = StringBuffer(
    '${top.label} was the commonest at ${top.count} of '
    '${analysis.recordCount}, across ${analysis.events.length} kinds of '
    'event.',
  );
  if (analysis.platformEvents > 0) {
    summary.write(
      ' ${analysis.platformEvents} of them were the platform acting on this '
      'business rather than a member of it.',
    );
  }

  return TenantReportSection(
    heading: 'What happened',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.ranked,
      caption: 'Events by kind',
      valueAxisLabel: 'Events',
      data: <TenantReportDatum>[
        for (final event in analysis.events.take(8))
          TenantReportDatum(
            label: event.label,
            value: event.count.toDouble(),
            formatted: '${event.count}',
          ),
      ],
    ),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Event', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Times', kind: TenantReportColumnKind.count),
      ],
      rows: <List<TenantReportCell>>[
        for (final event in analysis.events.take(TenantLogsAnalysis.listed))
          <TenantReportCell>[
            TenantReportTextCell(
              event.isModelled ? event.label : '${event.label} (unrecognised)',
            ),
            TenantReportCountCell(event.count),
          ],
      ],
    ),
  );
}

TenantReportSection _whoDidIt(
  TenantLogsAnalysis analysis,
  TenantReportPeople people,
) {
  final busiest = analysis.actors.first;
  final concentration = analysis.actorConcentration;

  final summary = StringBuffer(
    analysis.actors.length == 1
        ? 'Every recorded change was made by one actor.'
        : '${analysis.actors.length} actors made changes in this period.',
  );
  if (concentration != null && concentration > 0.5 && !busiest.isPlatform) {
    summary.write(
      ' More than half of them are one member, which is worth knowing whether '
      'or not anything is wrong with them.',
    );
  }

  return TenantReportSection(
    heading: 'Who made the changes',
    summary: summary.toString(),
    table: TenantReportTable(
      columns: const <TenantReportColumn>[
        TenantReportColumn(heading: 'Actor', kind: TenantReportColumnKind.text),
        TenantReportColumn(heading: 'Events', kind: TenantReportColumnKind.count),
        TenantReportColumn(heading: 'Kinds', kind: TenantReportColumnKind.count),
      ],
      rows: <List<TenantReportCell>>[
        for (final actor in analysis.actors.take(TenantLogsAnalysis.listed))
          <TenantReportCell>[
            TenantReportTextCell(
              actor.isPlatform
                  ? '${actor.actor} (platform)'
                  : people.label(actor.actor),
            ),
            TenantReportCountCell(actor.events),
            TenantReportCountCell(actor.kinds),
          ],
      ],
    ),
  );
}

TenantReportSection _byDay(TenantLogsAnalysis analysis) {
  final busiest = analysis.busiestDate;
  final summary = StringBuffer();
  if (busiest != null) {
    summary.write(
      'The most happened on ${TenantReportPeriod.day(busiest).spelled}, with '
      '${analysis.dailyCount[busiest]} events.',
    );
  }
  if (analysis.quietDays > 0) {
    summary.write(
      ' ${analysis.quietDays} of the ${analysis.dailyCount.length} days had '
      'nothing recorded at all.',
    );
  }
  if (analysis.change case final moved?) {
    summary.write(
      ' Activity is ${reportDirection(moved)} on the ${analysis.period.days} '
      'days before this period.',
    );
  }

  return TenantReportSection(
    heading: 'When',
    summary: summary.toString(),
    visual: TenantReportVisual(
      kind: TenantReportVisualKind.trend,
      caption: 'Events recorded each day',
      valueAxisLabel: 'Events',
      data: <TenantReportDatum>[
        for (final entry in analysis.dailyCount.entries)
          TenantReportDatum(
            label: reportShortDate(entry.key),
            value: entry.value.toDouble(),
            formatted: '${entry.value}',
          ),
      ],
    ),
  );
}
