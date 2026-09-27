/// What the Reports page says about where its figures came from, and when.
///
/// **The reported defect, 2026-09-20.** *"When Reports opens it races to
/// declare the page offline."* `TenantRouteGuard` runs the device read beside
/// the server read so the page draws immediately, and the device read usually
/// wins - a disk beats a network. The page keyed its `On this device` callout
/// off the basis of whatever figure had arrived, so every single open raised a
/// full-width banner announcing an outage it had no grounds for, reflowed the
/// page around it, and withdrew it half a second later when the server
/// answered.
///
/// The shell learned this in the same words - see `_worksFromSavedData`:
///
/// > a person who has been told twice that they are offline while they are not
/// > stops believing the notice on the day it is true.
///
/// This page was never brought into line with it. The guard already publishes
/// the distinction the fix needs: `fromCache` without `stale` is *the server
/// has not answered yet*, which is a moment, and `stale` is *the server was
/// asked and could not be reached*, which is the standing condition the
/// sentence was written for.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/checkout/checkout_tender.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 8, 26, 12);

void main() {
  testWidgets('a week still waiting on the server says nothing about it', (
    tester,
  ) async {
    await _pump(tester, fromCache: true, stale: false);

    expect(
      find.byKey(const ValueKey('weekly-report-device-basis')),
      findsNothing,
      reason:
          'The server has not answered yet, which is a moment rather than a '
          'condition. Announcing it and withdrawing it is what made the '
          'notice worthless on the day it is true.',
    );
  });

  testWidgets('a week the server could not answer for says so', (tester) async {
    await _pump(tester, fromCache: true, stale: true);

    expect(find.byKey(const ValueKey('weekly-report-device-basis')), findsOne);
  });

  testWidgets('a week the server answered says nothing either', (tester) async {
    // Belt and braces: server figures are not device-basis, so the callout
    // could not draw anyway - but the two conditions are now separate and a
    // future edit could reach this case through the other one.
    await _pump(tester, fromCache: false, stale: false);

    expect(
      find.byKey(const ValueKey('weekly-report-device-basis')),
      findsNothing,
    );
  });

  testWidgets('the labels on the cards keep step with the callout', (
    tester,
  ) async {
    // Three cards carried an amber `On this device` that appeared and vanished
    // with the banner. Saying the same thing twice in two weights means they
    // must answer the same question, or a figure keeps a provenance label the
    // page above it has already withdrawn.
    await _pump(tester, fromCache: true, stale: false);
    expect(find.text('On this device'), findsNothing);

    await _pump(tester, fromCache: true, stale: true);
    expect(find.text('On this device'), findsWidgets);
  });

  testWidgets('outside a guard the figures still say where they came from', (
    tester,
  ) async {
    // Nothing to ask, and these figures really were counted here.
    await _pump(tester, freshness: false);

    expect(find.byKey(const ValueKey('weekly-report-device-basis')), findsOne);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  bool fromCache = true,
  bool stale = false,
  bool freshness = true,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TenantSessionController()
    ..open(uid: 'user-a', membership: _membership());
  addTearDown(controller.dispose);

  final contents = WeeklyReportContents(
    week: TenantReportWeek.at(_now),
    report: _deviceWeek(),
    sessionContext: SalesTotalsSessionContext.empty,
    soldById: null,
    selfUid: 'user-a',
    categoryId: null,
    showProfit: false,
    onChooseWeek: (_) {},
    onChooseMember: (_) {},
    onChooseCategory: (_) {},
    onRetry: () {},
  );

  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: freshness
              ? TenantReadFreshness(
                  fromCache: fromCache,
                  stale: stale,
                  child: contents,
                )
              : contents,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// A week whose figures were counted on this device.
TenantWeeklyReport _deviceWeek() => TenantWeeklyReport(
  week: TenantReportWeek.at(_now),
  totals: TenantSalesTotals.fromDevice(
    query: _query(),
    scannedTransactions: 1,
    salesMinor: 1000,
    costMinor: 400,
    transactions: 1,
    incompleteCostLineCount: 0,
    // Every bucket, because a device breakdown that names only the ones it
    // used is refused - a split with a bucket missing cannot be checked
    // against the total above it.
    tenderSalesMinor: _buckets(<String, int>{'cash': 1000}),
    tenderTransactions: _buckets(<String, int>{'cash': 1}),
  ),
  previousTotals: null,
  revenueByWeekday: List<double>.filled(7, 0),
  topItems: const <TenantReportItem>[],
  recentSales: const <TenantReportSaleRow>[],
  itemsSold: 1,
  scanWasTruncated: false,
);

/// [used] over a zero for every bucket the device split must name.
Map<String, int> _buckets(Map<String, int> used) => <String, int>{
  for (final bucket in <String>[
    ...checkoutTenderWireValues,
    TenantSalesTenderBreakdown.unrecordedBucket,
    TenantSalesTenderBreakdown.unrecognisedBucket,
  ])
    bucket: used[bucket] ?? 0,
};

/// Queries are only constructable through a session-bound gateway, which is
/// the point of them: no caller may name a business of its own choosing.
TenantSalesTotalsQuery _query() => TenantSalesTotalsGateway(
  session: TenantSession.active(
    uid: 'user-a',
    tenantId: 'tenant-a',
    role: TenantRole.owner,
  ),
  callable: const _NeverCallable(),
  clock: () => _now,
).createBusinessDateQuery(businessDate: '2026-08-26');

/// Never called: composing a query asks nothing of the server.
final class _NeverCallable implements SalesTotalsCallable {
  const _NeverCallable();

  @override
  Future<Object?> call(Map<String, Object?> payload) =>
      throw StateError('no read was expected');
}

TenantMembership _membership() => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: 'tenant-a',
  tenantSlug: 'tenant-a',
  role: TenantRole.owner,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: true,
  mirrorVersion: 1,
  createdAt: _now,
  updatedAt: _now,
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
