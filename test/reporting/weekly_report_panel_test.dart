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
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
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
}

Future<void> _pumpReports(
  WidgetTester tester, {
  required SalesTotalsCallable callable,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TenantSessionController()
    ..open(uid: 'user-a', membership: _membership());
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantWeeklyReportScreen(
          reader: const _EmptyReader(),
          callable: callable,
          clock: () => DateTime.utc(2026, 8, 27, 12),
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

TenantMembership _membership() => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: 'Chilltent Lounge',
  tenantSlug: 'chilltent-lounge',
  role: TenantRole.owner,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: true,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
