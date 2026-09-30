import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// The count a person owes before they sell.
///
/// **The first three tests are about not blocking anybody**, and that ordering
/// is deliberate. The till is the one screen in this app that must always open:
/// a schedule that cannot be read, a day nobody was asked to count, and a count
/// already handed in all have to end with a working register. The enforcement
/// tests come after, because enforcement is the exception.
void main() {
  const till = ValueKey('the-till');
  // 2026-09-14 is a Monday.
  const monday = '2026-09-14';
  const tuesday = '2026-09-15';

  group('the till opens', () {
    testWidgets('when nothing is scheduled', (tester) async {
      await _pump(tester, schedule: TenantStockTakeSchedule.none);

      expect(find.byKey(till), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-take-gate-held')), findsNothing);
    });

    testWidgets('when the schedule cannot be read at all', (tester) async {
      // **Fail open.** Holding a shop out of its own register because a
      // configuration document would not load is a far worse failure than a
      // missed count.
      await _pump(tester, throwsOnLoad: true);

      expect(find.byKey(till), findsOneWidget);
    });

    testWidgets('on a day this person was not asked to count', (tester) async {
      await _pump(tester, businessDate: tuesday, schedule: _blocking());

      expect(find.byKey(till), findsOneWidget);
    });

    testWidgets('for somebody who is not on the rota', (tester) async {
      await _pump(
        tester,
        uid: 'user-other',
        schedule: _blocking(),
      );

      expect(find.byKey(till), findsOneWidget);
    });

    testWidgets('once the count has been handed in', (tester) async {
      // The obligation is discharged locally the moment the pages are queued,
      // not when they drain and not when a manager approves.
      final obligations = _Obligations(
        satisfied: <String>{const TenantStockTakeEverything().scopeKey},
      );
      await _pump(tester, schedule: _blocking(), obligations: obligations);

      expect(find.byKey(till), findsOneWidget);
    });
  });

  group('enforcement', () {
    testWidgets('a prompt can be waved away, and the till opens', (
      tester,
    ) async {
      await _pump(tester, schedule: _prompting());

      expect(find.byKey(const ValueKey('stock-take-gate-start')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stock-take-gate-later')));
      await tester.pumpAndSettle();

      expect(find.byKey(till), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-take-gate-start')), findsNothing);
    });

    testWidgets('a blocking count draws no till at all, not even behind it', (
      tester,
    ) async {
      // Drawing the register behind the modal would put a sellable screen one
      // dismissal away from the thing meant to be preventing the sale.
      await _pump(tester, schedule: _blocking());

      expect(find.byKey(till), findsNothing);
      expect(find.byKey(const ValueKey('stock-take-gate-held')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('stock-take-gate-later')),
        findsNothing,
        reason: 'there is no *Not now* on a blocking gate',
      );
    });

    testWidgets('counting from the gate opens the scope that is owed', (
      tester,
    ) async {
      final opened = <TenantStockTakeScope>[];
      await _pump(
        tester,
        schedule: _blocking(categoryId: 'cat-bakery'),
        onCountRoute: opened.add,
      );

      await tester.tap(find.byKey(const ValueKey('stock-take-gate-start')));
      await tester.pumpAndSettle();

      expect(opened, <TenantStockTakeScope>[
        const TenantStockTakeCategory('cat-bakery'),
      ]);
    });

    testWidgets('handing it in releases the till without a restart', (
      tester,
    ) async {
      // The gate re-reads the obligation when the counting screen pops, so
      // finishing a count is what opens the register.
      final obligations = _Obligations();
      await _pump(
        tester,
        schedule: _blocking(),
        obligations: obligations,
        onCountRoute: (scope) => obligations.satisfied.add(scope.scopeKey),
      );

      expect(find.byKey(till), findsNothing);
      await tester.tap(find.byKey(const ValueKey('stock-take-gate-start')));
      await tester.pumpAndSettle();

      expect(find.byKey(till), findsOneWidget);
    });
  });

  testWidgets('two counts owed are asked for one at a time', (tester) async {
    await _pump(
      tester,
      schedule: TenantStockTakeSchedule(
        enforcement: TenantStockTakeEnforcement.block,
        weekdays: const <int>{DateTime.monday},
        assignments: const <TenantStockTakeAssignment>[
          TenantStockTakeAssignment(uid: 'user-a', categoryId: 'cat-bakery'),
          TenantStockTakeAssignment(uid: 'user-a', categoryId: 'cat-drinks'),
        ],
      ),
      businessDate: monday,
    );

    expect(find.textContaining('2 counts to take'), findsOneWidget);
  });

  // **Found on two emulators on 2026-09-29**: the gate read this device's copy
  // alone, so a phone that had never opened *Stock counts* was never asked,
  // and one that had went on asking after the count was switched off.
  group('the server answer', () {
    testWidgets('reaches a phone that has never read the schedule', (
      tester,
    ) async {
      await _pump(
        tester,
        refreshSchedule: _answering(_prompting()),
      );

      expect(find.byKey(const ValueKey('stock-take-gate-start')), findsOneWidget);
    });

    testWidgets('takes back a question the count was switched off under', (
      tester,
    ) async {
      final server = Completer<TenantPublishedStockTakeSchedule>();
      await _pump(
        tester,
        schedule: _prompting(),
        refreshSchedule: (_) => server.future,
      );
      expect(find.byKey(const ValueKey('stock-take-gate-start')), findsOneWidget);

      server.complete(
        TenantPublishedStockTakeSchedule.published(TenantStockTakeSchedule.none),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('stock-take-gate-start')), findsNothing);
      expect(find.byKey(till), findsOneWidget);
    });

    testWidgets('opens a till held by a hold that has since been lifted', (
      tester,
    ) async {
      await _pump(
        tester,
        schedule: _blocking(),
        refreshSchedule: _answering(TenantStockTakeSchedule.none),
      );

      expect(find.byKey(till), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-take-gate-held')), findsNothing);
      expect(find.byKey(const ValueKey('stock-take-gate-start')), findsNothing);
    });

    testWidgets('asks again as a hold when a prompt became one', (
      tester,
    ) async {
      final server = Completer<TenantPublishedStockTakeSchedule>();
      await _pump(
        tester,
        schedule: _prompting(),
        refreshSchedule: (_) => server.future,
      );
      expect(find.byKey(const ValueKey('stock-take-gate-later')), findsOneWidget);

      server.complete(TenantPublishedStockTakeSchedule.published(_blocking()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('stock-take-gate-held')), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-take-gate-start')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('stock-take-gate-later')),
        findsNothing,
        reason: 'the question on screen is the hold, not the old prompt',
      );
    });

    testWidgets('leaves this device\'s answer standing when it cannot answer', (
      tester,
    ) async {
      // With no signal this read fails every time; that is a till's ordinary
      // day, and the copy it already holds is the answer.
      await _pump(
        tester,
        schedule: _blocking(),
        refreshSchedule: (_) async => throw StateError('offline'),
      );

      expect(find.byKey(const ValueKey('stock-take-gate-held')), findsOneWidget);
    });

    testWidgets('the same answer twice asks once', (tester) async {
      final server = Completer<TenantPublishedStockTakeSchedule>();
      await _pump(
        tester,
        schedule: _prompting(),
        refreshSchedule: (_) => server.future,
      );
      await tester.tap(find.byKey(const ValueKey('stock-take-gate-later')));
      await tester.pumpAndSettle();

      server.complete(TenantPublishedStockTakeSchedule.published(_prompting()));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('stock-take-gate-start')),
        findsNothing,
        reason: '*Not now* holds for the visit when nothing changed',
      );
      expect(find.byKey(till), findsOneWidget);
    });
  });
}

/// A server that answers at once with [schedule].
TenantStockTakeScheduleLoader _answering(TenantStockTakeSchedule schedule) =>
    (_) async => TenantPublishedStockTakeSchedule.published(schedule);

TenantStockTakeSchedule _blocking({String? categoryId}) =>
    TenantStockTakeSchedule(
      enforcement: TenantStockTakeEnforcement.block,
      weekdays: const <int>{DateTime.monday},
      assignments: <TenantStockTakeAssignment>[
        TenantStockTakeAssignment(uid: 'user-a', categoryId: categoryId),
      ],
    );

TenantStockTakeSchedule _prompting() => TenantStockTakeSchedule(
  enforcement: TenantStockTakeEnforcement.prompt,
  weekdays: const <int>{DateTime.monday},
  assignments: const <TenantStockTakeAssignment>[
    TenantStockTakeAssignment(uid: 'user-a'),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  TenantStockTakeSchedule? schedule,
  _Obligations? obligations,
  String uid = 'user-a',
  String businessDate = '2026-09-14',
  bool throwsOnLoad = false,
  void Function(TenantStockTakeScope scope)? onCountRoute,
  TenantStockTakeScheduleLoader? refreshSchedule,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: TenantSessionController()
          ..open(uid: uid, membership: _membership()),
        child: TenantStockTakeGate(
          businessDate: () => businessDate,
          loadSchedule: (session) async {
            if (throwsOnLoad) throw StateError('no configuration');
            return schedule == null
                ? const TenantPublishedStockTakeSchedule.absent()
                : TenantPublishedStockTakeSchedule.published(schedule);
          },
          refreshSchedule: refreshSchedule,
          obligations: obligations ?? _Obligations(),
          countRoute: (context, scope) {
            onCountRoute?.call(scope);
            return const _CountingScreen();
          },
          child: const Scaffold(
            key: ValueKey('the-till'),
            body: Text('Register'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Stands in for the counting screen, and pops itself the way one would.
final class _CountingScreen extends StatefulWidget {
  const _CountingScreen();

  @override
  State<_CountingScreen> createState() => _CountingScreenState();
}

class _CountingScreenState extends State<_CountingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('Counting'));
}

final class _Obligations implements TenantStockTakeObligationSource {
  _Obligations({Set<String>? satisfied})
    : satisfied = satisfied ?? <String>{};

  final Set<String> satisfied;

  @override
  Set<String> satisfiedScopes({
    required String uid,
    required String tenantId,
    required String businessDate,
  }) => satisfied;

  @override
  Future<void> markSatisfied({
    required String uid,
    required String tenantId,
    required String businessDate,
    required String scopeKey,
  }) async => satisfied.add(scopeKey);
}

TenantMembership _membership() => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: 'tenant-a',
  tenantSlug: 'tenant-a',
  role: TenantRole.cashier,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
