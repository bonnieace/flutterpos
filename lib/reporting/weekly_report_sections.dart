/// The weekly report's body: the cards, the filters, the chart and the lists.
///
/// **Split from `weekly_report_panel.dart` so the route and the composition are
/// separately readable**, the way the totals page splits its choosers out. The
/// panel decides what to load and who may see it; everything here draws.
///
/// Every value is an `AppTokens` role. Where the old screen had a raw number -
/// a 200-tall chart, a 48-square item tile, a 32-wide bar - the figure is named
/// here as a composition constant with the reason it is not a token, exactly as
/// `sheet.dart` names its drag handle.
library;

import 'package:flutter/material.dart';

import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/status.dart';
import '../ui/skeleton.dart';
import '../ui/tokens.dart';
import 'reporting_currency.dart';
import 'sales_totals_session_context.dart';
import 'weekly_report.dart';
import 'weekly_report_charts.dart';
import 'weekly_report_panel.dart';

/// Figures this composition fixes, which `design.md` states no token for.
///
/// Named rather than inlined for the reason `AppSheetMasthead` gives: a literal
/// in a widget is a defect, and inventing `size.chartHeight` would be inventing
/// a token the design system never defined. These are the old screen's own
/// proportions, kept so the page reads as it did.
abstract final class WeeklyReportMetrics {
  /// The revenue chart's plot height. The old screen's `SizedBox(height: 200)`.
  static const double chartHeight = 200;

  /// One bar's width. The old screen's `width: 32`.
  static const double barWidth = 32;

  /// Room for the money labels down the left axis.
  static const double axisReserve = 60;

  /// How many gridlines sit behind the bars.
  static const int gridDivisions = 4;

  /// The heights a reading chart draws its seven bars at, as fractions of the
  /// plot.
  ///
  /// **Uneven on purpose.** Seven bars of one height is a placeholder that
  /// reads as a table; a week's takings are never level, and the shape of the
  /// thing being waited for is the only reason to draw bars rather than one
  /// grey slab.
  static const List<double> readingBarHeights = <double>[
    0.45,
    0.7,
    0.35,
    0.85,
    0.6,
    0.5,
    0.25,
  ];

  /// How wide a figure reads while it is still being read.
  ///
  /// A fraction rather than a width, so the placeholder scales with the
  /// card it sits in. Short of the full line because a money figure never
  /// fills one, and a placeholder that did would settle noticeably narrower
  /// than it started.
  static const double readingWidthFactor = 0.55;

  /// The floor the chart scales to, so an empty week still draws an axis
  /// rather than collapsing to a flat line at zero.
  static const double emptyWeekCeiling = 1000;

  /// Headroom above the tallest bar, so it never touches the top rule.
  static const double ceilingHeadroom = 1.2;

  /// The square holding a top item's glyph. The old screen's 48.
  static const double itemGlyph = 48;

  /// The square holding a transaction's payment glyph. The old screen's 40.
  static const double saleGlyph = 40;

  /// A metric card's own glyph, and the arrow beside its percentage. The old
  /// screen's 20 and 14.
  static const double cardGlyph = 20;
  static const double deltaGlyph = 14;
}

/// The whole page under the header.
final class WeeklyReportContents extends StatelessWidget {
  const WeeklyReportContents({
    super.key,
    required this.week,
    required this.report,
    required this.sessionContext,
    required this.soldById,
    required this.selfUid,
    required this.categoryId,
    required this.showProfit,
    this.reading = false,
    required this.onChooseWeek,
    required this.onChooseMember,
    required this.onChooseCategory,
    required this.onRetry,
    this.currency,
    this.failureMessage,
  });

  final TenantReportWeek week;

  /// Null while the week could not be read. The filters still draw, which is
  /// the point of keeping them out of the failure state.
  final TenantWeeklyReport? report;

  /// Whether [report] is null because the read is still running.
  ///
  /// **An em dash is a claim and a placeholder is not**, which is the whole
  /// reason this flag exists rather than the sections reading `report == null`
  /// and drawing the same thing either way. `—` in a figure card says *this
  /// week has no such figure* - the right thing to say about a week that could
  /// not be read, and a lie about one that has not answered yet. Before
  /// 2026-08-27 this page showed a centred spinner instead, which said nothing
  /// untrue but also replaced the week picker and the filters while it did it.
  final bool reading;

  final SalesTotalsSessionContext sessionContext;
  final String? soldById;
  final String? selfUid;
  final String? categoryId;
  final bool showProfit;
  final TenantReportingCurrency? currency;
  final ValueChanged<int> onChooseWeek;
  final ValueChanged<String?> onChooseMember;
  final ValueChanged<String?> onChooseCategory;
  final VoidCallback onRetry;
  final String? failureMessage;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final wide = AppLayout.contract.isAtLeast(
      MediaQuery.sizeOf(context).width,
      AppBreakpoint.expanded,
    );
    final medium = AppLayout.contract.isAtLeast(
      MediaQuery.sizeOf(context).width,
      AppBreakpoint.medium,
    );
    return ListView(
      key: const ValueKey('weekly-report-body'),
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.s8),
      children: <Widget>[
        if (failureMessage case final message?) ...<Widget>[
          Callout(
            key: const ValueKey('weekly-report-failure'),
            status: AppStatus.problem,
            message: message,
            action: AppButton(
              label: 'Try again',
              tier: AppButtonTier.tertiary,
              size: AppButtonSize.sm,
              onPressed: onRetry,
            ),
          ),
          SizedBox(height: tokens.spacing.s24),
        ],
        _MetricGrid(
          report: report,
          reading: reading,
          currency: currency,
          showProfit: showProfit,
          week: week,
          wide: wide,
          medium: medium,
        ),
        SizedBox(height: tokens.spacing.s32),
        _FilterBar(
          week: week,
          sessionContext: sessionContext,
          soldById: soldById,
          selfUid: selfUid,
          categoryId: categoryId,
          onChooseWeek: onChooseWeek,
          onChooseMember: onChooseMember,
          onChooseCategory: onChooseCategory,
          stacked: !medium,
        ),
        SizedBox(height: tokens.spacing.s32),
        if (wide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: WeeklyRevenueChart(
                    week: week,
                    report: report,
                    reading: reading,
                    currency: currency,
                  ),
                ),
                SizedBox(width: tokens.spacing.s24),
                Expanded(
                  child: WeeklyTopItems(
                    report: report,
                    reading: reading,
                    currency: currency,
                  ),
                ),
              ],
            ),
          )
        else ...<Widget>[
          WeeklyRevenueChart(
            week: week,
            report: report,
            reading: reading,
            currency: currency,
          ),
          SizedBox(height: tokens.spacing.s24),
          WeeklyTopItems(report: report, reading: reading, currency: currency),
        ],
        SizedBox(height: tokens.spacing.s32),
        WeeklyRecentTransactions(
          report: report,
          currency: currency,
          onRefresh: onRetry,
        ),
      ],
    );
  }
}

/// The card every section of this page is drawn on. The old screen's
/// `bgMid` box with a `mutedGreen` edge at radius 12.
final class WeeklyReportCard extends StatelessWidget {
  const WeeklyReportCard({required this.child, this.padding, super.key});

  final Widget child;
  final double? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        border: Border.all(color: tokens.colors.surface.borderSubtle),
      ),
      child: Padding(
        padding: EdgeInsets.all(padding ?? tokens.spacing.s24),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metric cards
// ---------------------------------------------------------------------------

final class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.report,
    required this.reading,
    required this.currency,
    required this.showProfit,
    required this.week,
    required this.wide,
    required this.medium,
  });

  final TenantWeeklyReport? report;

  /// See `WeeklyReportContents.reading`. A card that is reading draws a
  /// placeholder where its figure will be, rather than an em dash saying the
  /// figure does not exist.
  final bool reading;
  final TenantReportingCurrency? currency;
  final bool showProfit;
  final TenantReportWeek week;
  final bool wide;
  final bool medium;

  /// The old screen's `vs last week` / `vs prior week`.
  String get _comparisonLabel =>
      week.isCurrent ? 'vs last week' : 'vs prior week';

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final data = report;
    final previous = data?.previousTotals;
    final profit = data?.totals?.profitReport;
    final net = data?.netProfitReport;
    final cards = <Widget>[
      _MetricCard(
        cardKey: const ValueKey('weekly-report-sales'),
        title: 'TOTAL SALES',
        reading: reading,
        value: data == null ? '—' : weeklyReportMoney(currency, data.sales),
        change: TenantWeeklyReport.change(data?.sales ?? 0, previous?.sales),
        comparisonLabel: _comparisonLabel,
        icon: Icons.attach_money,
        emphasis: true,
      ),
      // **Only where the session may see cost.** `TenantProfitReport` puts the
      // margin behind owner and administrator everywhere else in this app, and
      // a report page is not the place it stops being true.
      if (showProfit)
        _MetricCard(
          cardKey: const ValueKey('weekly-report-profit'),
          title: 'GROSS PROFIT',
          reading: reading,
          // An unshowable basis says so rather than printing a figure the
          // server computed out of lines that carried no cost.
          value: profit == null || !profit.isShowable
              ? '—'
              : weeklyReportMoney(currency, profit.profit),
          subtitle: profit != null && !profit.isShowable
              ? 'Some lines carry no cost'
              : null,
          change: profit != null && profit.isShowable
              ? TenantWeeklyReport.change(profit.profit, previous?.profit)
              : null,
          comparisonLabel: _comparisonLabel,
          icon: Icons.trending_up,
          emphasis: (profit?.profit ?? 0) >= 0,
        ),
      // **A card of its own rather than a changed GROSS PROFIT.** The two
      // answer different questions - what the stock earned, and what the
      // business kept - and a week where they diverge sharply is exactly the
      // week somebody needs to see both. It appears only where the spending
      // was read; a week with no expense reading shows gross alone, as this
      // page always did.
      if (showProfit && net != null)
        _MetricCard(
          cardKey: const ValueKey('weekly-report-net-profit'),
          title: 'NET PROFIT',
          reading: reading,
          value: net.isShowable
              ? weeklyReportMoney(currency, net.netProfit)
              : '—',
          subtitle: net.isShowable
              ? 'After expenses'
              : 'Some spending is not counted',
          // **No comparison arrow.** The week before was not read for
          // spending, so there is no prior net profit to compare against, and
          // an arrow drawn from the gross figures would describe a different
          // quantity than the one above it.
          comparisonLabel: _comparisonLabel,
          icon: Icons.account_balance_wallet_outlined,
          emphasis: !net.isLoss,
        ),
      _MetricCard(
        cardKey: const ValueKey('weekly-report-transactions'),
        title: 'TRANSACTIONS',
        reading: reading,
        value: data == null ? '—' : '${data.transactions}',
        change: TenantWeeklyReport.change(
          (data?.transactions ?? 0).toDouble(),
          previous?.transactions.toDouble(),
        ),
        comparisonLabel: _comparisonLabel,
        icon: Icons.receipt_long,
        emphasis: true,
      ),
      // **Where the old page's *Low stock* card was.** This product has no
      // reorder level to read - see `weekly_report.dart` - and a card is not
      // worth inventing a number for.
      _MetricCard(
        cardKey: const ValueKey('weekly-report-average'),
        title: 'AVERAGE SALE',
        reading: reading,
        value: data == null || data.transactions == 0
            ? '—'
            : weeklyReportMoney(currency, data.averageSale),
        change: data == null
            ? null
            : TenantWeeklyReport.change(
                data.averageSale,
                data.previousAverageSale,
              ),
        comparisonLabel: _comparisonLabel,
        icon: Icons.receipt,
        emphasis: true,
      ),
      // Where *Shifts today* was, for the reason given in `weekly_report.dart`.
      _MetricCard(
        cardKey: const ValueKey('weekly-report-items'),
        title: 'ITEMS SOLD',
        value: data == null ? '—' : '${data.itemsSold}',
        subtitle: data != null && data.scanWasTruncated
            ? 'Counted from the newest sales only'
            : null,
        icon: Icons.inventory_2_outlined,
        emphasis: true,
      ),
    ];

    if (!medium) {
      return Column(
        children: <Widget>[
          for (final card in cards) ...<Widget>[
            card,
            if (card != cards.last) SizedBox(height: tokens.spacing.s16),
          ],
        ],
      );
    }
    // Four across on a wide screen and two on a tablet, which is exactly the
    // old screen's grid; the trailing card fills the row it starts.
    final perRow = wide ? 4 : 2;
    final rows = <Widget>[];
    for (var start = 0; start < cards.length; start += perRow) {
      final row = cards.sublist(start, (start + perRow).clamp(0, cards.length));
      rows.add(
        // **`IntrinsicHeight` so the cards in a row match**, which is what the
        // old grid got for free from a `Row` inside a bounded column. Inside a
        // `ListView` the height is unbounded, and `CrossAxisAlignment.stretch`
        // against an unbounded height is an assertion rather than a layout.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var index = 0; index < perRow; index++) ...<Widget>[
                if (index > 0) SizedBox(width: tokens.spacing.s16),
                Expanded(
                  child: index < row.length ? row[index] : const SizedBox(),
                ),
              ],
            ],
          ),
        ),
      );
      if (start + perRow < cards.length) {
        rows.add(SizedBox(height: tokens.spacing.s16));
      }
    }
    return Column(children: rows);
  }
}

final class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.cardKey,
    required this.title,
    required this.value,
    required this.icon,
    required this.emphasis,
    this.reading = false,
    this.change,
    this.comparisonLabel,
    this.subtitle,
  });

  final Key cardKey;
  final String title;
  final String value;

  /// Whether the figure is still being read. See `WeeklyReportContents`.
  final bool reading;
  final IconData icon;

  /// Whether the glyph is drawn in the accent or in the problem colour. The old
  /// screen turned the profit card's icon red on a loss.
  final bool emphasis;

  /// Percentage difference against the week before, or null where there is
  /// nothing to compare with.
  final double? change;

  final String? comparisonLabel;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final delta = change;
    final rising = (delta ?? 0) >= 0;
    final deltaColor = rising
        ? tokens.colors.status.ok.fg
        : tokens.colors.status.problem.fg;
    return WeeklyReportCard(
      key: cardKey,
      padding: tokens.spacing.s20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: tokens.typography.labelEyebrow.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
              ),
              Icon(
                icon,
                size: WeeklyReportMetrics.cardGlyph,
                color: emphasis
                    ? tokens.colors.status.ok.fg
                    : tokens.colors.status.problem.fg,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s12),
          // The title and the glyph above are the same whether or not the
          // figure has arrived, so they are drawn for real and only the figure
          // is a placeholder - decision 35, on one card.
          if (reading)
            SkeletonGroup(
              semanticLabel: 'Reading $title.',
              child: SkeletonLine(
                widthFactor: WeeklyReportMetrics.readingWidthFactor,
                style: tokens.typography.numericCompact,
                tone: SkeletonTone.onRaised,
              ),
            )
          else
            Text(
              value,
              style: tokens.typography.numericCompact.copyWith(
                color: tokens.colors.text.primary,
              ),
            ),
          if (delta != null && !reading) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            Row(
              children: <Widget>[
                // §9: never colour alone. The arrow states the direction and
                // the sign states it again in the figure.
                Icon(
                  rising ? Icons.arrow_upward : Icons.arrow_downward,
                  size: WeeklyReportMetrics.deltaGlyph,
                  color: deltaColor,
                ),
                SizedBox(width: tokens.spacing.s4),
                Text(
                  '${delta.abs().toStringAsFixed(1)}%',
                  style: tokens.typography.caption.copyWith(color: deltaColor),
                ),
                SizedBox(width: tokens.spacing.s4),
                Expanded(
                  child: Text(
                    comparisonLabel ?? '',
                    style: tokens.typography.caption.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (subtitle case final note?) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            Text(
              note,
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.status.attention.fg,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------

final class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.week,
    required this.sessionContext,
    required this.soldById,
    required this.selfUid,
    required this.categoryId,
    required this.onChooseWeek,
    required this.onChooseMember,
    required this.onChooseCategory,
    required this.stacked,
  });

  final TenantReportWeek week;
  final SalesTotalsSessionContext sessionContext;
  final String? soldById;
  final String? selfUid;
  final String? categoryId;
  final ValueChanged<int> onChooseWeek;
  final ValueChanged<String?> onChooseMember;
  final ValueChanged<String?> onChooseCategory;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final navigator = _WeekNavigator(week: week, onChoose: onChooseWeek);
    final category = AppSelect<String?>(
      key: const ValueKey('weekly-report-category'),
      label: 'Category',
      leading: Icons.category_outlined,
      value: sessionContext.categories.nameOf(categoryId ?? '') == null
          ? null
          : categoryId,
      enabled: sessionContext.categories.readable,
      onChanged: onChooseCategory,
      items: <AppSelectItem<String?>>[
        const AppSelectItem<String?>(
          key: ValueKey('weekly-report-category-all'),
          value: null,
          label: 'All categories',
        ),
        for (final option in sessionContext.categories.items)
          AppSelectItem<String?>(
            key: ValueKey('weekly-report-category-${option.id}'),
            value: option.id,
            label: option.name,
          ),
      ],
    );
    final member = AppSelect<String?>(
      key: const ValueKey('weekly-report-member'),
      label: 'Sold by',
      leading: Icons.person_outline,
      value: sessionContext.staff.contains(soldById ?? '') ? soldById : null,
      enabled: sessionContext.staff.readable,
      onChanged: onChooseMember,
      items: <AppSelectItem<String?>>[
        const AppSelectItem<String?>(
          key: ValueKey('weekly-report-member-all'),
          value: null,
          label: 'All staff',
        ),
        for (final uid in sessionContext.staff.uids)
          AppSelectItem<String?>(
            key: ValueKey('weekly-report-member-$uid'),
            value: uid,
            label: tenantStaffLabel(
              uid,
              names: sessionContext.staff.names,
              selfUid: selfUid,
            ),
          ),
      ],
    );

    if (stacked) {
      return WeeklyReportCard(
        padding: tokens.spacing.s16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(child: navigator),
            SizedBox(height: tokens.spacing.s16),
            category,
            SizedBox(height: tokens.spacing.s16),
            member,
          ],
        ),
      );
    }
    return WeeklyReportCard(
      padding: tokens.spacing.s20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          navigator,
          SizedBox(width: tokens.spacing.s16),
          Expanded(child: category),
          SizedBox(width: tokens.spacing.s16),
          Expanded(child: member),
        ],
      ),
    );
  }
}

/// The old screen's week stepper: back a week, forward a week, never past the
/// week in progress.
final class _WeekNavigator extends StatelessWidget {
  const _WeekNavigator({required this.week, required this.onChoose});

  final TenantReportWeek week;
  final ValueChanged<int> onChoose;

  String get _label {
    if (week.offset == 0) return 'This week';
    if (week.offset == -1) return 'Last week';
    return '${weeklyReportDayFormat.format(week.monday)} – '
        '${weeklyReportDayFormat.format(week.sunday)}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.field,
        borderRadius: BorderRadius.circular(tokens.radius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            key: const ValueKey('weekly-report-previous-week'),
            tooltip: 'Previous week',
            icon: const Icon(Icons.chevron_left),
            color: tokens.colors.text.secondary,
            onPressed: () => onChoose(week.offset - 1),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _label,
                key: const ValueKey('weekly-report-week-label'),
                style: tokens.typography.labelMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
              Text(
                '${weeklyReportDayFormat.format(week.monday)} – '
                '${weeklyReportDayFormat.format(week.sunday)}',
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ],
          ),
          IconButton(
            key: const ValueKey('weekly-report-next-week'),
            tooltip: 'Next week',
            icon: const Icon(Icons.chevron_right),
            color: tokens.colors.text.secondary,
            // Disabled rather than hidden on the current week, so the control
            // does not move as a person steps through the weeks.
            onPressed: week.isCurrent ? null : () => onChoose(week.offset + 1),
          ),
        ],
      ),
    );
  }
}
