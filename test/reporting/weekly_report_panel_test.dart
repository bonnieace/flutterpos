/// The Reports route while it is still reading, which had no test at all.
///
/// **What is under test is what the page says before it knows anything.** Until
/// 2026-08-27 that was a centred spinner over the whole route, and the loader
/// beneath it awaited the totals callable once per elapsed day of the week -
/// up to nine round trips end to end. So opening Reports to look at *last*
/// week meant waiting for this one, and the week picker that would have taken
/// you there was behind the spinner.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the week picker and the filters draw before the figures do', (
    tester,
  ) async {
    final held = Completer<Object?>();
    addTearDown(() {
      if (!held.isCompleted) held.complete(<String, Object?>{});
    });
    await _pumpReports(tester, callable: _HeldTotalsCallable(held));

    // The controls a person came here to use, none of which show a figure.
    expect(find.byKey(const ValueKey('weekly-report-body')), findsOne);
    expect(find.byKey(const ValueKey('weekly-report-member')), findsOne);
    expect(find.byKey(const ValueKey('weekly-report-category')), findsOne);

    held.complete(<String, Object?>{});
    await tester.pumpAndSettle();
  });

  testWidgets('a figure still being read is a placeholder, not an em dash', (
    tester,
  ) async {
    // **The distinction this page did not have.** `—` in a figure card says
    // *this week has no such figure*, which is the right thing to say about a
    // week that could not be read and a lie about one that has not answered.
    final held = Completer<Object?>();
    addTearDown(() {
      if (!held.isCompleted) held.complete(<String, Object?>{});
    });
    await _pumpReports(tester, callable: _HeldTotalsCallable(held));

    final sales = find.byKey(const ValueKey('weekly-report-sales'));
    expect(sales, findsOne);
    expect(
      find.descendant(of: sales, matching: find.text('—')),
      findsNothing,
      reason: 'A read still running has not established that there is nothing.',
    );

    held.complete(<String, Object?>{});
    await tester.pumpAndSettle();
  });

  testWidgets('the top items say nothing about the week until they can', (
    tester,
  ) async {
    final held = Completer<Object?>();
    addTearDown(() {
      if (!held.isCompleted) held.complete(<String, Object?>{});
    });
    await _pumpReports(tester, callable: _HeldTotalsCallable(held));

    expect(
      find.byKey(const ValueKey('weekly-report-top-items-reading')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('weekly-report-top-items-empty')),
      findsNothing,
      reason: '"No sales this week" is an answer this section does not have.',
    );

    held.complete(<String, Object?>{});
    await tester.pumpAndSettle();
  });

  testWidgets('total sales stays on the page', (tester) async {
    // **Not a door since 2026-09-29.** It opened the sales totals page until
    // the product owner took the tap away; a tap on its bars reads a day's
    // figure out instead. Wired or not, nothing is pushed.
    var opened = 0;
    await _pumpReports(
      tester,
      callable: _held(),
      destinations: WeeklyReportDestinations(
        salesTotals: WeeklyReportDestination(
          build: () {
            opened++;
            return const Scaffold(key: ValueKey('totals-stub'));
          },
          roles: const <TenantRole>[TenantRole.owner],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('weekly-report-sales')));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(opened, 0);
    expect(find.byKey(const ValueKey('totals-stub')), findsNothing);
    expect(find.byKey(const ValueKey('weekly-report-body')), findsOneWidget);
  });

  testWidgets('a figure nothing elaborates is inert, not broken', (
    tester,
  ) async {
    // No destination is wired at all, so every card is a plain figure - the
    // state this page was in before the hub was retired, and the state the old
    // app's *Low stock* card was always in.
    await _pumpReports(tester, callable: _held());

    expect(find.byKey(const ValueKey('weekly-report-sales')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('weekly-report-sales')));
    // Frames, not a settle: the figures are still being read, and a skeleton
    // never settles.
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Nothing was pushed: the page is still the page.
    expect(find.byKey(const ValueKey('weekly-report-body')), findsOneWidget);
  });

  testWidgets('the page draws no tiles for the other reports', (tester) async {
    // **Removed by the product owner on 2026-09-29.** Daily summary, Monthly
    // report, Differences and Stock movements sat under a *More reports*
    // heading at the foot of this page; wired or not, none is drawn now.
    await _pumpReports(
      tester,
      callable: _held(),
      destinations: WeeklyReportDestinations(
        dailySummary: WeeklyReportDestination(
          build: () => const Scaffold(),
          roles: const <TenantRole>[TenantRole.owner],
        ),
        monthlyReport: WeeklyReportDestination(
          build: () => const Scaffold(),
          roles: const <TenantRole>[TenantRole.owner],
        ),
        differences: WeeklyReportDestination(
          build: () => const Scaffold(),
          roles: const <TenantRole>[TenantRole.owner],
        ),
        stockMovements: WeeklyReportDestination(
          build: () => const Scaffold(),
          roles: const <TenantRole>[TenantRole.owner],
        ),
        openDifferenceCount: (_) => 2,
      ),
    );

    for (final key in <String>[
      'weekly-report-links-heading',
      'weekly-report-daily-summary',
      'weekly-report-monthly',
      'weekly-report-differences',
      'weekly-report-stock-movements',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    expect(find.text('MORE REPORTS'), findsNothing);
  });
}

/// A callable that never answers, so the page stays on its figures-pending
/// state while the cards - which do not wait for a figure - are exercised.
_HeldTotalsCallable _held() => _HeldTotalsCallable(Completer<Object?>());

Future<void> _pumpReports(
  WidgetTester tester, {
  required SalesTotalsCallable callable,
  WeeklyReportDestinations destinations = const WeeklyReportDestinations(),
  TenantRole role = TenantRole.owner,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TenantSessionController()
    ..open(
      uid: 'user-a',
      membership: _membership(role: role),
    );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantWeeklyReportScreen(
          reader: const _EmptyReader(),
          callable: callable,
          clock: () => DateTime.utc(2026, 8, 27, 12),
          destinations: destinations,
        ),
      ),
    ),
  );
  // Frames, not a settle: settling would wait for the read being held open.
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A totals callable that answers only when the test says so.
final class _HeldTotalsCallable implements SalesTotalsCallable {
  _HeldTotalsCallable(this._gate);

  final Completer<Object?> _gate;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    await _gate.future;
    return <String, Object?>{
      'sales': 0,
      'profit': 0,
      'transactions': 0,
      'incompleteCostLineCount': 0,
    };
  }
}

final class _EmptyReader implements TenantDataReader {
  const _EmptyReader();

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}

TenantMembership _membership({TenantRole role = TenantRole.owner}) =>
    TenantMembership(
      tenantId: 'tenant-a',
      tenantName: 'Chilltent Lounge',
      tenantSlug: 'chilltent-lounge',
      role: role,
      membershipStatus: MembershipStatus.active,
      tenantStatus: TenantStatus.active,
      isOwner: role == TenantRole.owner,
      mirrorVersion: 1,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      serverCanAccess: true,
      canonicalTenantExists: true,
      canonicalMembershipExists: true,
    );
