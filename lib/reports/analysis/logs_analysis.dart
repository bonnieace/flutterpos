/// What a period's audit trail says, beyond a page of rows.
///
/// **The screen admits its day filter is a sieve.** The audit collection is
/// keyed by the operation, request or delivery ID an event belongs to - a
/// digest for most writers - so document order carries no time information and
/// the existing panel filters one page rather than a period. Reading a real
/// span became possible only when the trail gained a `createdAt` ordering; see
/// `TenantAuditLogRepository.loadRecordedRange`.
///
/// **The finding is the critical alerts.** `severity: critical` is written by
/// the platform's own impact scan - a business left with no active
/// administrator, an owner who cannot be reached - and those are the events an
/// owner most needs to see and least likely to be scrolling the trail for.
///
/// **The second is who changed what.** A period can say that one member made
/// every stock correction, or that the platform acted on the business four
/// times, and neither of those is visible one row at a time.
///
/// Pure arithmetic, no I/O, no Flutter.
library;

import '../../audit/audit_log.dart';
import '../../checkout/checkout_draft.dart';
import '../report_period.dart';

/// One kind of event, and how often it happened.
final class TenantLoggedEvent {
  const TenantLoggedEvent({
    required this.eventType,
    required this.label,
    required this.count,
  });

  /// The raw wire value, kept so an unmodelled event is named as itself.
  final String eventType;

  /// What this client calls it, or the raw value where it knows no name.
  ///
  /// **An unmodelled event is listed rather than hidden.** A server deploy
  /// that starts recording a new kind of event is not evidence of anything
  /// wrong, and leaving it out of the business's own trail would be far worse
  /// than naming it plainly.
  final String label;

  final int count;

  /// Whether this client recognises the event at all.
  bool get isModelled => TenantAuditEventType.tryParse(eventType) != null;
}

/// One actor, and what they did.
final class TenantLogActor {
  const TenantLogActor({
    required this.actor,
    required this.isPlatform,
    required this.events,
    required this.kinds,
  });

  /// The member's UID, or the platform's own actor type.
  final String actor;

  /// Whether this was the platform acting on the business rather than a member
  /// of it.
  final bool isPlatform;

  final int events;

  /// How many distinct kinds of event this actor caused.
  final int kinds;
}

/// A period's audit trail.
final class TenantLogsAnalysis {
  const TenantLogsAnalysis._({
    required this.period,
    required this.recordCount,
    required this.criticalCount,
    required this.platformEvents,
    required this.memberEvents,
    required this.unmodelledEvents,
    required this.events,
    required this.actors,
    required this.critical,
    required this.dailyCount,
    required this.previousCount,
    required this.truncated,
  });

  /// How many rows a page lists before the rest is left to the workbook.
  static const int listed = 20;

  factory TenantLogsAnalysis.from({
    required TenantReportPeriod period,
    required List<TenantAuditRecord> records,
    List<TenantAuditRecord>? previous,
    bool truncated = false,
  }) {
    final byType = <String, int>{};
    final byActor = <String, ({int events, Set<String> kinds, bool platform})>{};
    final daily = <String, int>{
      for (final date in period.businessDates) date: 0,
    };
    final critical = <TenantAuditRecord>[];

    var criticalCount = 0;
    var platformEvents = 0;
    var memberEvents = 0;
    var unmodelled = 0;

    for (final record in records) {
      byType[record.eventType] = (byType[record.eventType] ?? 0) + 1;
      if (record.type == null) unmodelled++;
      if (record.isCritical) {
        criticalCount++;
        critical.add(record);
      }

      // Every record names one or the other - the read model refuses one that
      // names neither - so this is a partition rather than a guess.
      final actor = record.actorUid ?? record.actorType!;
      final running =
          byActor[actor] ??
          (events: 0, kinds: <String>{}, platform: record.isPlatformEvent);
      running.kinds.add(record.eventType);
      byActor[actor] = (
        events: running.events + 1,
        kinds: running.kinds,
        platform: running.platform,
      );
      if (record.isPlatformEvent) {
        platformEvents++;
      } else {
        memberEvents++;
      }

      if (record.recordedAt case final at?) {
        // **The trail records UTC instants; a business day is Nairobi's.** An
        // event at 22:30 UTC happened on the next trading morning, and filing
        // it under the previous day would put it on the wrong side of a
        // boundary a reader compares against the sales report. The shop's own
        // rule is `checkoutBusinessDate`, so it is called rather than
        // restated.
        final date = checkoutBusinessDate(at);
        if (daily.containsKey(date)) {
          daily[date] = daily[date]! + 1;
        }
      }
    }

    final events =
        <TenantLoggedEvent>[
          for (final entry in byType.entries)
            TenantLoggedEvent(
              eventType: entry.key,
              label:
                  TenantAuditEventType.tryParse(entry.key)?.label ?? entry.key,
              count: entry.value,
            ),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : a.label.compareTo(b.label);
        });

    final actors =
        <TenantLogActor>[
          for (final entry in byActor.entries)
            TenantLogActor(
              actor: entry.key,
              isPlatform: entry.value.platform,
              events: entry.value.events,
              kinds: entry.value.kinds.length,
            ),
        ]..sort((a, b) {
          final byEvents = b.events.compareTo(a.events);
          return byEvents != 0 ? byEvents : a.actor.compareTo(b.actor);
        });

    // Newest first: an alert is read from the most recent one backwards.
    final alerts = critical.toList()
      ..sort((a, b) {
        final left = a.recordedAt;
        final right = b.recordedAt;
        if (left == null || right == null) return a.id.compareTo(b.id);
        final byTime = right.compareTo(left);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

    return TenantLogsAnalysis._(
      period: period,
      recordCount: records.length,
      criticalCount: criticalCount,
      platformEvents: platformEvents,
      memberEvents: memberEvents,
      unmodelledEvents: unmodelled,
      events: List<TenantLoggedEvent>.unmodifiable(events),
      actors: List<TenantLogActor>.unmodifiable(actors),
      critical: List<TenantAuditRecord>.unmodifiable(alerts),
      dailyCount: Map<String, int>.unmodifiable(daily),
      previousCount: previous?.length,
      truncated: truncated,
    );
  }

  final TenantReportPeriod period;

  final int recordCount;

  /// Events the platform's impact scan marked critical.
  final int criticalCount;

  /// Events the platform caused, rather than a member of this business.
  final int platformEvents;

  /// Events a named member of this business caused.
  final int memberEvents;

  /// Events this client has no name for, which are still listed.
  final int unmodelledEvents;

  /// Every kind of event in the period, most frequent first.
  final List<TenantLoggedEvent> events;

  final List<TenantLogActor> actors;

  /// The critical alerts themselves, newest first.
  final List<TenantAuditRecord> critical;

  /// Events recorded on each day of the period, quiet days included.
  final Map<String, int> dailyCount;

  final int? previousCount;

  final bool truncated;

  /// Whether the period holds anything the platform flagged.
  bool get isClear => criticalCount == 0;

  /// How far the volume moved against the period before, as a fraction.
  double? get change {
    final before = previousCount;
    if (before == null || before == 0) return null;
    return (recordCount - before) / before;
  }

  /// The share of events caused by the busiest actor, or null where none were.
  double? get actorConcentration {
    if (recordCount == 0 || actors.isEmpty) return null;
    return actors.first.events / recordCount;
  }

  /// The day the most happened on, or null where nothing did.
  String? get busiestDate {
    String? busiest;
    var most = 0;
    for (final entry in dailyCount.entries) {
      if (entry.value > most) {
        most = entry.value;
        busiest = entry.key;
      }
    }
    return busiest;
  }

  /// Days in the period on which nothing was recorded.
  int get quietDays => dailyCount.values.where((count) => count == 0).length;
}
