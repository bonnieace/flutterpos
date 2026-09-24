/// The arithmetic behind the activity report.
///
/// **The rule under test is that an unrecognised event is still the business's
/// own event.** A server deploy that starts recording something new is not
/// evidence of anything wrong, and dropping it from the trail would be far
/// worse than naming it plainly under its raw wire value.
library;

import 'package:flutter_application_1/audit/audit_log.dart';
import 'package:flutter_application_1/reports/analysis/logs_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/logs.dart';

void main() {
  group('alerts', () {
    test('a critical event is counted and kept', () {
      final analysis = fixtureLogsAnalysis();

      expect(analysis.criticalCount, 1);
      expect(analysis.critical.single.eventType, 'no_active_administrator');
      expect(analysis.isClear, isFalse);
    });

    test('a quiet period is clear rather than empty', () {
      final analysis = TenantLogsAnalysis.from(
        period: fixtureLogsPeriod(),
        records: <TenantAuditRecord>[
          auditRecord(
            id: 'aud-1',
            eventType: 'staff_invited',
            at: DateTime.utc(2026, 9, 2, 9),
            actorUid: 'owner-a',
          ),
        ],
      );

      expect(analysis.isClear, isTrue);
      expect(analysis.critical, isEmpty);
    });
  });

  group('what happened', () {
    test('events are grouped by kind, most frequent first', () {
      final analysis = fixtureLogsAnalysis();

      expect(analysis.events.first.label, 'Stock corrected');
      expect(analysis.events.first.count, 3);
      // stock_adjusted, staff_invited, return_verified_stock_restored,
      // no_active_administrator, tenant_lifecycle_changed and the one this
      // client has no name for.
      expect(analysis.events, hasLength(6));
    });

    test('an unmodelled event is named by its own wire value', () {
      final analysis = fixtureLogsAnalysis();

      final unknown = analysis.events.firstWhere(
        (event) => event.eventType == 'price_list_published',
      );
      expect(unknown.label, 'price_list_published');
      expect(unknown.isModelled, isFalse);
      expect(
        analysis.unmodelledEvents,
        1,
        reason:
            'A server that began recording something new is not evidence of '
            'anything wrong. Leaving it out of the trail would be worse.',
      );
    });

    test('platform and member events are a partition, not a guess', () {
      final analysis = fixtureLogsAnalysis();

      expect(analysis.platformEvents, 2);
      expect(analysis.memberEvents, 6);
      expect(
        analysis.platformEvents + analysis.memberEvents,
        analysis.recordCount,
      );
    });
  });

  group('who made the changes', () {
    test('actors are ranked by how much they did', () {
      final analysis = fixtureLogsAnalysis();

      expect(analysis.actors.first.actor, 'manager-a');
      expect(analysis.actors.first.events, 4);
      expect(
        analysis.actors.first.kinds,
        2,
        reason: 'Stock corrections and one return verification.',
      );
      expect(analysis.actors.first.isPlatform, isFalse);
    });

    test('the platform is an actor under its own type', () {
      final analysis = fixtureLogsAnalysis();

      final platform = analysis.actors.where((a) => a.isPlatform).toList();
      expect(
        platform.map((a) => a.actor),
        containsAll(<String>['platform', 'platform_admin']),
        reason:
            'A platform event names no member, so its actor type is the only '
            'thing it can be attributed to.',
      );
    });

    test('concentration is the busiest actor over everything', () {
      final analysis = fixtureLogsAnalysis();

      expect(analysis.actorConcentration, closeTo(4 / 8, 0.001));
    });
  });

  group('when', () {
    test('a UTC instant is filed under the trading day it happened on', () {
      final analysis = fixtureLogsAnalysis();

      // 03:00 UTC on the 11th is 06:00 in Nairobi, so it belongs to the 11th's
      // morning rather than to the 10th's night.
      expect(analysis.dailyCount['2026-09-11'], 2);
      expect(analysis.dailyCount['2026-09-10'], 0);
    });

    test('every day is drawn, including the ones nothing happened on', () {
      final analysis = fixtureLogsAnalysis();

      expect(analysis.dailyCount, hasLength(14));
      expect(analysis.busiestDate, '2026-09-05');
    });

    test('movement against the period before is a fraction', () {
      final analysis = fixtureLogsAnalysis(
        previous: fixtureLogs().take(4).toList(),
      );

      expect(analysis.previousCount, 4);
      expect(analysis.change, closeTo(1.0, 0.001));
    });

    test('an unread earlier window is null, not empty', () {
      final analysis = fixtureLogsAnalysis();

      expect(analysis.previousCount, isNull);
      expect(analysis.change, isNull);
    });
  });
}
