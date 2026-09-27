import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:flutter_test/flutter_test.dart';

/// When a count is due and who owes it.
///
/// **The defaults are the important part.** A business that has configured
/// nothing, or whose configuration cannot be parsed, must interrupt nobody - the
/// till is the one screen in this app that has to open, and a settings document
/// is not a good enough reason to stop a shop trading.
void main() {
  TenantStockTakeSchedule schedule({
    TenantStockTakeEnforcement enforcement = TenantStockTakeEnforcement.prompt,
    Set<int> weekdays = const <int>{DateTime.monday},
    List<TenantStockTakeAssignment> assignments = const <TenantStockTakeAssignment>[
      TenantStockTakeAssignment(uid: 'user-a'),
    ],
  }) => TenantStockTakeSchedule(
    enforcement: enforcement,
    weekdays: weekdays,
    assignments: assignments,
  );

  // 2026-09-14 is a Monday; 2026-09-15 a Tuesday.
  const monday = '2026-09-14';
  const tuesday = '2026-09-15';

  group('when nothing is configured', () {
    test('the empty schedule expects nothing of anybody', () {
      final none = TenantStockTakeSchedule.none;

      expect(none.enforcement, TenantStockTakeEnforcement.off);
      expect(none.fallsOn(monday), isFalse);
      expect(none.scopesFor(uid: 'user-a', businessDate: monday), isEmpty);
    });

    test('an absent or malformed document yields it, never a guess', () {
      for (final published in <TenantPublishedStockTakeSchedule>[
        const TenantPublishedStockTakeSchedule.absent(),
        const TenantPublishedStockTakeSchedule.malformed(),
      ]) {
        expect(published.schedule.enforcement, TenantStockTakeEnforcement.off);
        expect(published.published, isNull);
        expect(
          published.schedule.scopesFor(uid: 'user-a', businessDate: monday),
          isEmpty,
          reason: 'an unreadable setting must not hold a till shut',
        );
      }
      // And the state is still distinguishable, so the one person who can fix
      // a malformed document is told it is malformed.
      expect(
        const TenantPublishedStockTakeSchedule.malformed().state,
        TenantStockTakeScheduleState.malformed,
      );
    });
  });

  group('who owes what', () {
    test('only on the days named, and only for the person named', () {
      final rota = schedule(
        assignments: const <TenantStockTakeAssignment>[
          TenantStockTakeAssignment(uid: 'user-a', categoryId: 'cat-bakery'),
          TenantStockTakeAssignment(uid: 'user-b', categoryId: 'cat-drinks'),
        ],
      );

      expect(
        rota.scopesFor(uid: 'user-a', businessDate: monday),
        <TenantStockTakeScope>[const TenantStockTakeCategory('cat-bakery')],
      );
      expect(
        rota.scopesFor(uid: 'user-b', businessDate: monday),
        <TenantStockTakeScope>[const TenantStockTakeCategory('cat-drinks')],
      );
      expect(rota.scopesFor(uid: 'user-c', businessDate: monday), isEmpty);
      expect(rota.scopesFor(uid: 'user-a', businessDate: tuesday), isEmpty);
    });

    test('an assignment naming no category is the whole catalog', () {
      // The "one person counts everything" arrangement, which is the same field
      // as "this person counts bakery" because it is the same fact.
      expect(
        schedule().scopesFor(uid: 'user-a', businessDate: monday),
        <TenantStockTakeScope>[const TenantStockTakeEverything()],
      );
    });

    test('one person may be asked for two categories', () {
      final rota = schedule(
        assignments: const <TenantStockTakeAssignment>[
          TenantStockTakeAssignment(uid: 'user-a', categoryId: 'cat-bakery'),
          TenantStockTakeAssignment(uid: 'user-a', categoryId: 'cat-drinks'),
        ],
      );

      expect(rota.scopesFor(uid: 'user-a', businessDate: monday), hasLength(2));
    });

    test('enforcement off means nothing is owed, whatever else is set', () {
      final rota = schedule(enforcement: TenantStockTakeEnforcement.off);

      expect(rota.fallsOn(monday), isFalse);
      expect(rota.scopesFor(uid: 'user-a', businessDate: monday), isEmpty);
    });

    test('a business date nobody can parse owes nothing', () {
      // Fail open, for the third time in this file and the same reason.
      expect(schedule().fallsOn('not a date'), isFalse);
      expect(
        schedule().scopesFor(uid: 'user-a', businessDate: 'not a date'),
        isEmpty,
      );
    });
  });

  group('reading the document', () {
    Map<String, Object?> document({
      Object? enforcement = 'prompt',
      Object? weekdays = const <int>[1, 4],
      Object? assignments = const <Map<String, Object?>>[
        <String, Object?>{'uid': 'user-a', 'categoryId': 'cat-bakery'},
      ],
    }) => <String, Object?>{
      'enforcement': enforcement,
      'weekdays': weekdays,
      'assignments': assignments,
    };

    test('round-trips through the shape the server stores', () {
      final parsed = TenantStockTakeSchedule.fromMap(document());

      expect(parsed.enforcement, TenantStockTakeEnforcement.prompt);
      expect(parsed.weekdays, <int>{DateTime.monday, DateTime.thursday});
      expect(parsed.assignments.single.uid, 'user-a');
      expect(parsed.assignments.single.categoryId, 'cat-bakery');

      final written = parsed.documentData(updatedBy: 'owner-a');
      expect(written['enforcement'], 'prompt');
      expect(written['weekdays'], <int>[1, 4]);
      expect(written['updatedBy'], 'owner-a');
      expect(
        TenantStockTakeSchedule.fromMap(written),
        parsed,
        reason: 'what is written must read back as what was written',
      );
    });

    test('an unknown field is ignored, a known one must be right', () {
      // The asymmetry every configuration document here uses: a setting a later
      // build adds must not stop this one working.
      expect(
        TenantStockTakeSchedule.fromMap(<String, Object?>{
          ...document(),
          'somethingLaterAdded': 42,
        }).enforcement,
        TenantStockTakeEnforcement.prompt,
      );

      for (final broken in <Map<String, Object?>>[
        document(enforcement: 'sometimes'),
        document(enforcement: null),
        document(weekdays: 'monday'),
        document(weekdays: const <Object>['monday']),
        document(weekdays: const <int>[8]),
        document(assignments: 'user-a'),
        document(assignments: const <Object>['user-a']),
        document(
          assignments: const <Map<String, Object?>>[<String, Object?>{}],
        ),
      ]) {
        expect(
          () => TenantStockTakeSchedule.fromMap(broken),
          throwsA(isA<FormatException>()),
          reason: '$broken',
        );
      }
    });

    test('an unbounded assignment list is refused', () {
      // The document is read by every device on every till entry.
      expect(
        () => TenantStockTakeSchedule(
          enforcement: TenantStockTakeEnforcement.prompt,
          weekdays: const <int>{DateTime.monday},
          assignments: <TenantStockTakeAssignment>[
            for (var i = 0; i <= maximumStockTakeAssignments; i++)
              TenantStockTakeAssignment(uid: 'user-$i'),
          ],
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
