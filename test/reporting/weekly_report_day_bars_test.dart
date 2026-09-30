/// The Reports page's week strip and recent sales, as the product owner
/// reworked them on 2026-09-29.
///
/// - **A tapped day says what it took.** The *Total sales* card used to open
///   the sales totals page; that tap is gone and a tap on one of its bars reads
///   the day's figure out above the strip instead.
/// - **An unanswered payment method says nothing.** The recent-sales row
///   printed *Not recorded* for a sale whose method was never set; it prints
///   no badge now.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uzapay_pos/checkout/checkout_receipt.dart';
import 'package:uzapay_pos/checkout/checkout_tender.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/sales/sales.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Wednesday, so the week runs Monday 24 to Sunday 30 August.
final DateTime _now = DateTime.utc(2026, 8, 26, 12);
const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';

/// Monday to Sunday, in major units. Tuesday and Thursday took nothing.
const List<double> _takings = <double>[10, 0, 40, 0, 0, 0, 0];

void main() {
  for (final (name, size) in <(String, Size)>[
    ('a phone', const Size(390, 844)),
    // **The wide screen sets this card beside the chart under an
    // `IntrinsicHeight`**, which a `LayoutBuilder` cannot answer - the strip's
    // first version threw there. Asserted on both layouts for that reason.
    ('a wide screen', const Size(1200, 2400)),
  ]) {
    testWidgets('on $name a tapped day reads out what it took', (tester) async {
      await _pump(tester, size: size);
      expect(tester.takeException(), isNull);

      final readout = find.byKey(const ValueKey('weekly-report-day-value'));
      expect(tester.widget<Text>(readout).data, isEmpty);

      await _tapDay(tester, 2);
      expect(
        tester.widget<Text>(readout).data,
        'Wed 26 Aug · ${weeklyReportMoney(null, 40)}',
      );

      // Another day replaces it, a day that took nothing says so, and the
      // same day again puts it away.
      await _tapDay(tester, 0);
      expect(
        tester.widget<Text>(readout).data,
        'Mon 24 Aug · ${weeklyReportMoney(null, 10)}',
      );
      await _tapDay(tester, 1);
      expect(
        tester.widget<Text>(readout).data,
        'Tue 25 Aug · ${weeklyReportMoney(null, 0)}',
      );
      await _tapDay(tester, 1);
      expect(tester.widget<Text>(readout).data, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('choosing a day never moves the card under the finger', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 844));
    final bars = find.byKey(const ValueKey('weekly-report-day-bars'));
    final before = tester.getRect(bars);

    await _tapDay(tester, 2);

    expect(tester.getRect(bars), before);
  });

  testWidgets('a screen reader is told every day without pointing at one', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, size: const Size(390, 844));

    expect(find.bySemanticsLabel(RegExp(r'Wed 26 Aug · .*40')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a sale that names no payment method carries no badge', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 844));

    expect(find.text('Not recorded'), findsNothing);
    // The sale that did name one still says so.
    expect(find.text(CheckoutTender.cash.label), findsWidgets);
  });
}

Future<void> _tapDay(WidgetTester tester, int index) async {
  final rect = tester.getRect(
    find.byKey(const ValueKey('weekly-report-day-bars')),
  );
  await tester.tapAt(
    Offset(rect.left + rect.width * (index + 0.5) / 7, rect.bottom - 30),
  );
  await tester.pump();
}

Future<void> _pump(WidgetTester tester, {required Size size}) async {
  tester.view.physicalSize = size;
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
        child: Scaffold(
          body: TenantReadFreshness(
            fromCache: false,
            stale: false,
            child: WeeklyReportContents(
              week: TenantReportWeek.at(_now),
              report: _week(),
              sessionContext: SalesTotalsSessionContext.empty,
              soldById: null,
              selfUid: 'user-a',
              categoryId: null,
              showProfit: false,
              onChooseWeek: (_) {},
              onChooseMember: (_) {},
              onChooseCategory: (_) {},
              onRetry: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// A week with takings on Monday and Wednesday, and two recent sales: one paid
/// in cash and one whose method was never answered.
TenantWeeklyReport _week() => TenantWeeklyReport(
  week: TenantReportWeek.at(_now),
  totals: TenantSalesTotals.fromDevice(
    query: _query(),
    scannedTransactions: 2,
    salesMinor: 5000,
    costMinor: 0,
    transactions: 2,
    incompleteCostLineCount: 0,
    tenderSalesMinor: _buckets(<String, int>{
      'cash': 900,
      TenantSalesTenderBreakdown.unrecordedBucket: 4100,
    }),
    tenderTransactions: _buckets(<String, int>{
      'cash': 1,
      TenantSalesTenderBreakdown.unrecordedBucket: 1,
    }),
  ),
  previousTotals: null,
  revenueByWeekday: _takings,
  topItems: const <TenantReportItem>[],
  recentSales: <TenantReportSaleRow>[
    TenantReportSaleRow.whole(_sale('co-1', sequence: 1, tender: 'cash')),
    TenantReportSaleRow.whole(_sale('co-2', sequence: 2)),
  ],
  itemsSold: 4,
  scanWasTruncated: false,
);

TenantSale _sale(String id, {required int sequence, String? tender}) =>
    TenantSale.fromDocument(
      path: 'tenants/tenant-a/sales/$id',
      data: <String, Object?>{
        'checkoutId': id,
        'tenantId': 'tenant-a',
        'soldById': 'user-a',
        'payloadHash': '0123456789abcdef' * 4,
        'payloadSchemaVersion': 2,
        if (tender != null) 'tender': tender,
        'currency': 'KES',
        'businessDate': '2026-08-26',
        'clientCreatedAtMs': _now.millisecondsSinceEpoch,
        'shiftId': 'shift-a',
        'deviceId': _deviceA,
        'receiptNumber': formatCheckoutReceiptNumber(
          deviceId: _deviceA,
          businessDate: '2026-08-26',
          sequence: sequence,
        ),
        'receiptSequence': sequence,
        'items': <Object?>[
          <String, Object?>{
            'productId': 'product-1',
            'name': 'Tusker',
            'quantity': 2,
            'unitPriceMinor': 500,
            'unitPrice': 5.0,
            'lineTotalMinor': 1000,
            'lineTotal': 10.0,
          },
        ],
        'subtotalMinor': 1000,
        'subtotal': 10.0,
        'discountMinor': 100,
        'discount': 1.0,
        'totalMinor': 900,
        'total': 9.0,
        'createdAt': Timestamp.fromDate(_now),
      },
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
