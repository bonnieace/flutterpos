/// When a net profit figure may be shown, and when it must not be.
///
/// **Every case here is about a wrong number rather than a missing one.** Net
/// profit is gross profit minus what the business spent, and both halves can be
/// untrustworthy in ways that are invisible in the result: an unread expense
/// makes the figure too *high*, and a withheld gross makes it meaningless while
/// looking more considered than the figure it came from. So the interesting
/// assertions below are the ones that refuse to produce a number.
library;

import 'package:flutter_application_1/expenses/expense.dart';
import 'package:flutter_application_1/reporting/net_profit.dart';
import 'package:flutter_application_1/reporting/profit_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a complete gross and a complete reading give a net figure', () {
    final net = TenantNetProfitReport.from(
      gross: _gross(sales: 1000, profit: 400),
      expenses: _spent(<int>[15000, 5000]),
    );

    expect(net.basis, TenantNetProfitBasis.complete);
    expect(net.isShowable, isTrue);
    expect(net.expenses, 200);
    expect(net.netProfit, 200);
    // 200 of 1000 takings.
    expect(net.netMarginPercent, closeTo(20, 1e-9));
  });

  test('a period with no spending in it is still a complete answer', () {
    // Nothing recorded is a fact about the business, not a failed read.
    final net = TenantNetProfitReport.from(
      gross: _gross(sales: 1000, profit: 400),
      expenses: TenantExpensePeriod.empty(
        startDate: '2026-08-20',
        endDate: '2026-08-20',
      ),
    );

    expect(net.basis, TenantNetProfitBasis.complete);
    expect(net.netProfit, 400);
  });

  test('a withheld gross withholds the net, whatever the spending', () {
    // **Ordered ahead of any expense problem on purpose.** Subtracting real,
    // completely-read expenses from an untrustworthy gross produces a figure
    // that looks *more* considered than the one it came from.
    final net = TenantNetProfitReport.from(
      gross: _gross(sales: 1000, profit: 400, incompleteCostLineCount: 3),
      expenses: _spent(<int>[15000]),
    );

    expect(net.basis, TenantNetProfitBasis.grossWithheld);
    expect(net.isShowable, isFalse);
    expect(net.netMarginPercent, isNull);
  });

  test('an unread period withholds the net', () {
    final net = TenantNetProfitReport.from(
      gross: _gross(sales: 1000, profit: 400),
      expenses: null,
    );

    expect(net.basis, TenantNetProfitBasis.expensesUnread);
    expect(net.isShowable, isFalse);
  });

  test('a part-read period withholds the net, exactly like an unread one', () {
    // **The case that matters most.** A truncated read subtracts too little,
    // which makes what the business kept look better than it was - the same
    // overstatement `TenantProfitBasis.incomplete` refuses a gross figure for.
    final net = TenantNetProfitReport.from(
      gross: _gross(sales: 1000, profit: 400),
      expenses: _spent(<int>[15000], truncated: true),
    );

    expect(net.basis, TenantNetProfitBasis.expensesUnread);
    expect(net.isShowable, isFalse);
  });

  test('spending more than was earned is shown, not hidden', () {
    // The one reading this whole feature exists to make possible. A shop that
    // is losing money must be told so.
    final net = TenantNetProfitReport.from(
      gross: _gross(sales: 1000, profit: 400),
      expenses: _spent(<int>[60000]),
    );

    expect(net.isShowable, isTrue);
    expect(net.netProfit, -200);
    expect(net.isLoss, isTrue);
    expect(net.netMarginPercent, closeTo(-20, 1e-9));
  });

  test('a loss is never claimed from a figure that may not be shown', () {
    // An unread expense total cannot manufacture a loss out of nothing.
    final net = TenantNetProfitReport.from(
      gross: _gross(sales: 1000, profit: 400),
      expenses: _spent(<int>[60000], truncated: true),
    );

    expect(net.isLoss, isFalse);
  });

  test('a margin on no takings is withheld rather than divided by zero', () {
    final net = TenantNetProfitReport.from(
      gross: _gross(sales: 0, profit: 0),
      expenses: _spent(<int>[5000]),
    );

    expect(net.isShowable, isTrue);
    expect(net.netProfit, -50);
    expect(net.netMarginPercent, isNull);
  });

  test('the subtraction is exact in whole minor units', () {
    // Both figures are added up in whole minor units on the server, so this
    // must not drift the way a double subtraction would.
    final net = TenantNetProfitReport.from(
      gross: _gross(sales: 100.10, profit: 0.30),
      expenses: _spent(<int>[10]),
    );

    expect(net.netProfit, closeTo(0.20, 1e-9));
  });

  test('the gross report travels with the net one', () {
    final gross = _gross(sales: 1000, profit: 400);
    final net = TenantNetProfitReport.from(gross: gross, expenses: null);
    // The statement widget needs both to word what it shows.
    expect(net.gross, same(gross));
  });
}

TenantProfitReport _gross({
  required double sales,
  required double profit,
  int incompleteCostLineCount = 0,
}) => TenantProfitReport.from(
  sales: sales,
  profit: profit,
  incompleteCostLineCount: incompleteCostLineCount,
);

TenantExpensePeriod _spent(List<int> amountsMinor, {bool truncated = false}) =>
    TenantExpensePeriod(
      startDate: '2026-08-20',
      endDate: '2026-08-20',
      records: <TenantExpense>[
        for (var index = 0; index < amountsMinor.length; index++)
          TenantExpense.fromDocument(
            path: 'tenants/tenant-a/expenses/2026-08-20-tok$index',
            data: <String, Object?>{
              'expenseId': '2026-08-20-tok$index',
              'tenantId': 'tenant-a',
              'businessDate': '2026-08-20',
              'category': TenantExpenseCategory.rent.wireValue,
              'description': 'Something the business paid for',
              'amountMinor': amountsMinor[index],
              'amount': amountsMinor[index] / 100,
              'recordedBy': 'owner-a',
              'createdAt': DateTime.utc(2026, 8, 20, 9),
            },
          ),
      ],
      truncated: truncated,
    );
