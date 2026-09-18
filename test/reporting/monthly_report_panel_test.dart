/// The monthly report's own trust boundary, which it did not have.
///
/// **Why this file exists at all.** `TenantMonthlyReportScreen` was the only
/// routed report screen with neither a widget test nor a screenshot -
/// `monthly_report_test.dart` covers the month arithmetic and the loader, and
/// the harness in `tool/screenshots` rasterises the weekly report, the totals
/// page and the daily summary but never this one. That gap is the whole reason
/// the page could print a profit every other surface withholds: nothing here
/// would have noticed.
///
/// So what is under test is not the layout. It is the one question
/// `TenantProfitReport` exists to answer - may this figure be put in front of
/// somebody - asked of the surface that used to answer it differently.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a month whose cost data is complete states its profit', (
    tester,
  ) async {
    await _pumpMonth(tester, callable: _Callable(_response()));

    // No published currency in this harness, so the figure carries no code
    // and no separator - `TenantReportingCurrency` states that rather than
    // guessing one.
    expect(_profitValue(tester), '1200.00');
    expect(
      _noteText(tester),
      'Every sale line behind it carries a cost.',
      reason: 'The positive form is stated rather than left to silence.',
    );
  });

  testWidgets('a month with a costless line shows no profit figure', (
    tester,
  ) async {
    // **The defect.** This printed `totals.profit` and added a sentence saying
    // the number above was higher than the truth, while the totals page and
    // the weekly report withheld the same figure computed from the same sales.
    await _pumpMonth(
      tester,
      callable: _Callable(_response(incompleteCostLineCount: 4)),
    );

    expect(_profitValue(tester), '—');
    expect(
      _noteText(tester),
      startsWith('Profit and margin are not shown: 4 sale lines have'),
      reason: 'Word for word the sentence every other surface makes.',
    );
  });

  testWidgets('a profit larger than the takings is refused, not warned about', (
    tester,
  ) async {
    // Nothing a business does can produce this: it means the figure disagrees
    // with the takings it was derived from. The old page had no reading for it
    // and would have printed it.
    await _pumpMonth(
      tester,
      callable: _Callable(_response(sales: 900, profit: 1200)),
    );

    expect(_profitValue(tester), '—');
    expect(
      _noteText(tester),
      contains('larger than the takings it was computed from'),
    );
  });

  testWidgets('a withheld profit carries no comparison arrow either', (
    tester,
  ) async {
    // A percentage change is computed from this month's profit and last
    // month's. A basis that may not be shown may not be compared: the arrow
    // would be the withheld figure, restated as a trend.
    //
    // Three tiles carry a comparison when profit is showable - sales,
    // transactions and profit. *Average sale* never has one, and the
    // partial-month notice above them names July as well, so the totals are
    // four and three rather than three and two. The count is the assertion,
    // and the showable case below is its control.
    await _pumpMonth(
      tester,
      callable: _Callable(_response(incompleteCostLineCount: 4)),
    );

    expect(find.textContaining('July 2026'), findsNWidgets(3));
  });

  testWidgets('a shown profit keeps its comparison arrow', (tester) async {
    await _pumpMonth(tester, callable: _Callable(_response()));

    expect(find.textContaining('July 2026'), findsNWidgets(4));
  });

  testWidgets('a trustworthy month against an untrustworthy one shows no arrow', (
    tester,
  ) async {
    // **The denominator was never guarded.** The tile checked this month's
    // basis and the percentage divided by last month's, so a month whose
    // profit the app refuses to display still came out as a trend beside a
    // month whose profit it will.
    await _pumpMonth(
      tester,
      callable: _Callable(
        _response(),
        previous: _response(incompleteCostLineCount: 9),
      ),
    );

    expect(_profitValue(tester), '1200.00', reason: 'this month is complete');
    // Sales and transactions keep their arrows; only profit loses one.
    expect(find.textContaining('July 2026'), findsNWidgets(3));
  });

  testWidgets('a manager reads the month and is shown no profit at all', (
    tester,
  ) async {
    // Profit is cost, and cost is owner and administrator everywhere in this
    // app. A manager may read the month; the margin is not part of it.
    await _pumpMonth(
      tester,
      callable: _Callable(_response()),
      role: TenantRole.manager,
    );

    expect(find.byKey(const ValueKey('monthly-report-sales')), findsOne);
    expect(find.byKey(const ValueKey('monthly-report-profit')), findsNothing);
    expect(
      find.byKey(const ValueKey('monthly-report-profit-note')),
      findsNothing,
      reason: 'A note about a figure nobody is shown is a leak of that figure.',
    );
  });
}

String _profitValue(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('monthly-report-profit')))
    .data!;

String _noteText(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('monthly-report-profit-note')))
    .data!;

Future<void> _pumpMonth(
  WidgetTester tester, {
  required SalesTotalsCallable callable,
  TenantRole role = TenantRole.owner,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TenantSessionController()
    ..open(uid: 'user-a', membership: _membership(role: role));
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantMonthlyReportScreen(
          reader: const _EmptyReader(),
          callable: callable,
          // Mid-August, so the month is partial and July is the comparison.
          clock: () => DateTime.utc(2026, 8, 27, 12),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// One month's answer.
Map<String, Object?> _response({
  double sales = 5000,
  double profit = 1200,
  int transactions = 40,
  int incompleteCostLineCount = 0,
}) => <String, Object?>{
  'previous': <String, Object?>{
    'sales': sales,
    'profit': profit,
    'transactions': transactions,
    'incompleteCostLineCount': incompleteCostLineCount,
  },
  'scannedTransactions': transactions,
};

/// Answers the month itself with the response under test and the month before
/// it with a smaller one, so every figure has an arrow to keep or suppress.
///
/// The loader starts both reads together and asks for the month first, so the
/// order is the call order.
final class _Callable implements SalesTotalsCallable {
  _Callable(this._current, {Map<String, Object?>? previous})
    : _previous =
          previous ?? _response(sales: 4000, profit: 900, transactions: 32);

  final Map<String, Object?> _current;
  final Map<String, Object?> _previous;
  int _calls = 0;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    if (_calls++ == 0) return _current;
    return _previous;
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
