/// One category of spending, on its own.
///
/// **Carried across from the project this feature came from**, where tapping a
/// category opened its own screen with a chart and its records beneath. The
/// reading is worth keeping: *where is the money going* is answered by the ring
/// on the route behind this one, and *when did it go* only by this.
///
/// **It is handed the records rather than reading them again.** The route
/// behind it has already read the whole period, and this is a slice of exactly
/// that - so a second read would spend a query to produce the same answer, and
/// could produce a different one if a write landed in between, which would make
/// two screens of the same period disagree. `TenantProductStockScreen` takes
/// its product the same way, for the same reason.
library;

import 'package:flutter/material.dart';

import '../reporting/reporting_currency.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'expense.dart';
import 'expense_charts.dart';
import 'expense_panel.dart';

/// One category's records across the period that was on screen behind this.
final class TenantExpenseCategoryScreen extends StatelessWidget {
  const TenantExpenseCategoryScreen({
    super.key,
    required this.category,
    required this.period,
    required this.currency,
    required this.periodLabel,
    this.onVoid,
  });

  final TenantExpenseCategory category;

  /// The whole period. Sliced to [category] here rather than by the caller, so
  /// the chart still spans every day the person chose and not only the days
  /// this category happened to fall on.
  final TenantExpensePeriod period;

  final TenantReportingCurrency currency;

  /// What the route behind this called the stretch of days - *Last 30 days*.
  final String periodLabel;

  /// Withdraws one of these records, answering whether it was withdrawn, or
  /// null on a build that cannot write.
  ///
  /// **This screen leaves on a true.** It holds the period it was handed, so a
  /// record withdrawn from here makes its own total and chart stale the instant
  /// the write lands. The route behind it re-reads, so going back is both the
  /// correction and the confirmation.
  final TenantExpenseVoidRequest? onVoid;

  @override
  Widget build(BuildContext context) {
    final scoped = period.forCategory(category);
    return AppScaffold(
      title: category.label,
      subtitle: 'Spending under one heading, $periodLabel.',
      contentWidth: AppContentWidth.records,
      body: _CategoryContents(
        category: category,
        period: scoped,
        whole: period,
        currency: currency,
        periodLabel: periodLabel,
        onVoid: onVoid,
      ),
    );
  }
}

final class _CategoryContents extends StatelessWidget {
  const _CategoryContents({
    required this.category,
    required this.period,
    required this.whole,
    required this.currency,
    required this.periodLabel,
    this.onVoid,
  });

  final TenantExpenseCategory category;

  /// This category only.
  final TenantExpensePeriod period;

  /// Every category, so this one's share can be stated.
  final TenantExpensePeriod whole;

  final TenantReportingCurrency currency;
  final String periodLabel;
  final TenantExpenseVoidRequest? onVoid;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final dates = period.businessDates;
    final share = whole.shareOf(category);
    final counted = period.records.where((record) => !record.isVoided).length;
    return ListView(
      key: const ValueKey('expense-category'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      children: <Widget>[
        // **The heading is the figure, not a tile holding one.** Three stat
        // cards over a chart is the arrangement the developer asked to be rid
        // of on 2026-08-27: what this screen is for is one number and its
        // shape over time, and the number goes at the top at the size that
        // says so.
        Text(
          currency.format(period.total),
          key: const ValueKey('expense-category-total'),
          textAlign: TextAlign.center,
          style: tokens.typography.numericHero.copyWith(
            color: tokens.colors.text.money,
          ),
        ),
        SizedBox(height: tokens.spacing.s12),
        Text(
          <String>[
            '$counted ${counted == 1 ? 'record' : 'records'}',
            // An em dash where there is no share to take, for the reason
            // `shareOf` returns null: a share of no spending is a division by
            // zero, not a share of nothing.
            if (share == null)
              '— of all spending'
            else
              '${(share * 100).toStringAsFixed(0)}% of all spending',
            periodLabel,
          ].join(', '),
          key: const ValueKey('expense-category-summary'),
          textAlign: TextAlign.center,
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        if (period.truncated) ...<Widget>[
          SizedBox(height: tokens.spacing.s20),
          const Callout(
            key: ValueKey('expense-category-truncated'),
            status: AppStatus.attention,
            title: 'This is not the whole period',
            message:
                'More expenses were recorded than one reading holds, so both '
                'the total and the chart below cover only part of it.',
          ),
        ],
        SizedBox(height: tokens.spacing.s32),
        if (period.records.isEmpty)
          EmptyState(
            key: const ValueKey('expense-category-empty'),
            title: 'Nothing under ${category.label.toLowerCase()}',
            hint: 'This heading had no spending in the days shown.',
            illustration: 'empty-wallet.svg',
          )
        else ...<Widget>[
          ExpenseDailyChart(
            key: const ValueKey('expense-category-chart'),
            dates: dates,
            totalsMinor: <int>[
              for (final date in dates) period.totalMinorOn(date),
            ],
            currency: currency,
          ),
          SizedBox(height: tokens.spacing.s32),
          // The reference titles the list under its chart, and the title is
          // what separates the two halves of the screen without a card around
          // either.
          Text(
            'Expense details',
            style: tokens.typography.titleMedium.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
          SizedBox(height: tokens.spacing.s8),
          for (final (index, record) in period.records.indexed)
            ExpenseRow(
              key: ValueKey('expense-category-${record.expenseId}'),
              record: record,
              currency: currency,
              first: index == 0,
              // Every row here is under the heading this screen is named for.
              showCategory: false,
              onVoid: onVoid == null || record.isVoided
                  ? null
                  : () => _withdraw(context, record),
            ),
        ],
      ],
    );
  }

  /// Asks for the void, and leaves if it happened.
  Future<void> _withdraw(BuildContext context, TenantExpense record) async {
    // Read before the await: this screen is about to be popped, and a
    // `Navigator.of` after the gap would be looking at a dead element.
    final navigator = Navigator.of(context);
    if (await onVoid!(record)) navigator.pop();
  }
}
