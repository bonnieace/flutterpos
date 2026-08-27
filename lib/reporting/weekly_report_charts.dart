/// The weekly report's chart and its two lists.
///
/// Split from `weekly_report_sections.dart` only for length; the composition is
/// continuous with it and every value is the same `AppTokens` role.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../checkout/checkout_tender.dart';
import '../sales/sale_history.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/skeleton.dart';
import '../ui/tokens.dart';
import 'reporting_currency.dart';
import 'weekly_report.dart';
import 'weekly_report_panel.dart';
import 'weekly_report_sections.dart';

/// The old screen's seven-bar week, with the best day picked out in the accent.
final class WeeklyRevenueChart extends StatelessWidget {
  const WeeklyRevenueChart({
    super.key,
    required this.week,
    required this.report,
    required this.currency,
    this.reading = false,
  });

  final TenantReportWeek week;
  final TenantWeeklyReport? report;
  final TenantReportingCurrency? currency;

  /// Whether the week is still being read. See `WeeklyReportContents.reading`.
  ///
  /// Without it a chart with nothing to draw yet renders `Total: 0` over a flat
  /// axis, which is what an empty week looks like - so the page states a week
  /// took nothing while it is still finding out.
  final bool reading;

  static const List<String> days = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  String get _title {
    if (week.offset == 0) return 'This week revenue';
    if (week.offset == -1) return 'Last week revenue';
    return '${weeklyReportDayFormat.format(week.monday)} – '
        '${weeklyReportDayFormat.format(week.sunday)} revenue';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final chart = tokens.colors.chart;
    final revenue =
        report?.revenueByWeekday ?? List<double>.filled(days.length, 0);
    final total = revenue.fold<double>(0, (sum, day) => sum + day);
    final peak = revenue.fold<double>(0, (a, b) => a > b ? a : b);
    final ceiling = peak <= 0
        ? WeeklyReportMetrics.emptyWeekCeiling
        : peak * WeeklyReportMetrics.ceilingHeadroom;
    // The one day the eye should land on, and only where something was taken.
    final best = peak <= 0 ? -1 : revenue.indexOf(peak);

    return WeeklyReportCard(
      key: const ValueKey('weekly-report-chart'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _title,
            style: tokens.typography.titleMedium.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
          SizedBox(height: tokens.spacing.s4),
          if (reading)
            SkeletonLine(
              widthFactor: WeeklyReportMetrics.readingWidthFactor,
              style: tokens.typography.caption,
              tone: SkeletonTone.onRaised,
            )
          else
            Text(
              'Total: ${weeklyReportMoney(currency, total)}',
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.tertiary,
              ),
            ),
          SizedBox(height: tokens.spacing.s24),
          if (reading)
            _ReadingBars(key: const ValueKey('weekly-report-chart-reading'))
          else
            SizedBox(
              height: WeeklyReportMetrics.chartHeight,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: ceiling,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => tokens.colors.surface.overlay,
                      getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                        weeklyReportMoney(currency, rod.toY),
                        tokens.typography.labelMedium.copyWith(
                          color: tokens.colors.text.primary,
                        ),
                      ),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          final index = value.toInt();
                          if (index < 0 || index >= days.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: EdgeInsets.only(top: tokens.spacing.s8),
                            child: Text(
                              days[index],
                              style: tokens.typography.caption.copyWith(
                                color: chart.axisLabel,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: WeeklyReportMetrics.axisReserve,
                        getTitlesWidget: (value, _) => Text(
                          weeklyReportAxisMoney(currency, value),
                          style: tokens.typography.caption.copyWith(
                            color: chart.axisLabel,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval:
                        ceiling / WeeklyReportMetrics.gridDivisions,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: chart.gridLine, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: <BarChartGroupData>[
                    for (var day = 0; day < days.length; day++)
                      BarChartGroupData(
                        x: day,
                        barRods: <BarChartRodData>[
                          BarChartRodData(
                            toY: revenue[day],
                            width: WeeklyReportMetrics.barWidth,
                            color: day == best ? chart.barEmphasis : chart.bar,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(tokens.radius.sm),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The week's best sellers by revenue.
/// Seven bars where a week's revenue will be, at the shape of a week rather
/// than at one flat height. The axis and the plot's height are real.
final class _ReadingBars extends StatelessWidget {
  const _ReadingBars({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return SkeletonGroup(
      semanticLabel: 'Reading this week revenue.',
      child: SizedBox(
        height: WeeklyReportMetrics.chartHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            for (final fraction in WeeklyReportMetrics.readingBarHeights)
              SkeletonBlock(
                width: WeeklyReportMetrics.barWidth,
                height: WeeklyReportMetrics.chartHeight * fraction,
                radius: tokens.radius.sm,
                tone: SkeletonTone.onRaised,
              ),
          ],
        ),
      ),
    );
  }
}

final class WeeklyTopItems extends StatelessWidget {
  const WeeklyTopItems({
    super.key,
    required this.report,
    required this.currency,
    this.reading = false,
  });

  final TenantWeeklyReport? report;
  final TenantReportingCurrency? currency;

  /// Whether the week is still being read. See `WeeklyReportContents.reading`.
  ///
  /// Without it a list with nothing in it yet draws *No sales this week*, which
  /// is an answer this section does not have.
  final bool reading;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final items = report?.topItems ?? const <TenantReportItem>[];
    return WeeklyReportCard(
      key: const ValueKey('weekly-report-top-items'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Top selling items',
            style: tokens.typography.titleMedium.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
          SizedBox(height: tokens.spacing.s20),
          if (reading)
            SkeletonGroup(
              key: const ValueKey('weekly-report-top-items-reading'),
              semanticLabel: 'Reading the top selling items.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (var row = 0; row < _readingRows; row++) ...<Widget>[
                    if (row > 0) SizedBox(height: tokens.spacing.s16),
                    const _ReadingItemRow(),
                  ],
                ],
              ),
            )
          else if (items.isEmpty)
            const EmptyState(
              key: ValueKey('weekly-report-top-items-empty'),
              title: 'No sales this week',
              hint: 'Items appear here once this week has takings.',
            )
          else
            for (final item in items) ...<Widget>[
              _TopItemRow(item: item, currency: currency),
              if (item != items.last) SizedBox(height: tokens.spacing.s16),
            ],
          if (report?.scanWasTruncated ?? false) ...<Widget>[
            SizedBox(height: tokens.spacing.s16),
            Text(
              'Counted from the newest sales of the week only.',
              key: const ValueKey('weekly-report-top-items-truncated'),
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

/// How many placeholder rows stand in for the top items.
///
/// Three rather than the ten this list can hold: a placeholder should not
/// promise a length it has no way to know, and three is enough to read as a
/// ranked list rather than as one more line.
const int _readingRows = 3;

/// One placeholder item row, shaped like [_TopItemRow]: a glyph square, a name
/// over its units, and the money against the trailing edge.
final class _ReadingItemRow extends StatelessWidget {
  const _ReadingItemRow();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Row(
      children: <Widget>[
        SkeletonBlock(
          width: WeeklyReportMetrics.itemGlyph,
          height: WeeklyReportMetrics.itemGlyph,
          radius: tokens.radius.md,
          tone: SkeletonTone.onRaised,
        ),
        SizedBox(width: tokens.spacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SkeletonLine(
                widthFactor: 0.62,
                style: tokens.typography.labelMedium,
                tone: SkeletonTone.onRaised,
              ),
              SizedBox(height: tokens.spacing.s4),
              SkeletonLine(
                widthFactor: 0.34,
                style: tokens.typography.caption,
                tone: SkeletonTone.onRaised,
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.spacing.s12),
        SizedBox(
          width: tokens.spacing.s64,
          child: SkeletonLine(
            style: tokens.typography.numericBody,
            tone: SkeletonTone.onRaised,
          ),
        ),
      ],
    );
  }
}

final class _TopItemRow extends StatelessWidget {
  const _TopItemRow({required this.item, required this.currency});

  final TenantReportItem item;
  final TenantReportingCurrency? currency;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Row(
      children: <Widget>[
        Container(
          width: WeeklyReportMetrics.itemGlyph,
          height: WeeklyReportMetrics.itemGlyph,
          decoration: BoxDecoration(
            color: tokens.colors.surface.field,
            borderRadius: BorderRadius.circular(tokens.radius.sm),
          ),
          child: Icon(
            Icons.inventory_2_outlined,
            color: tokens.colors.text.secondary,
          ),
        ),
        SizedBox(width: tokens.spacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.labelMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
              Text(
                // The old screen printed a category here too; a sale line
                // records no category, and reading one back per product would
                // be a read per row to fill in a subtitle.
                '${item.quantity} sold',
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.spacing.s8),
        Text(
          weeklyReportMoney(currency, item.revenueMinor / 100),
          style: tokens.typography.labelMedium.copyWith(
            color: tokens.colors.text.money,
          ),
        ),
      ],
    );
  }
}

/// The week's newest sales, newest first.
final class WeeklyRecentTransactions extends StatelessWidget {
  const WeeklyRecentTransactions({
    super.key,
    required this.report,
    required this.currency,
    required this.onRefresh,
  });

  final TenantWeeklyReport? report;
  final TenantReportingCurrency? currency;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final sales = report?.recentSales ?? const <TenantSale>[];
    return WeeklyReportCard(
      key: const ValueKey('weekly-report-transactions'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Recent transactions',
                  style: tokens.typography.titleMedium.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('weekly-report-refresh'),
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                color: tokens.colors.text.secondary,
                onPressed: onRefresh,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s16),
          if (sales.isEmpty)
            const EmptyState(
              key: ValueKey('weekly-report-transactions-empty'),
              title: 'No transactions this week',
              hint: 'Sales appear here as they are recorded.',
            )
          else
            for (final sale in sales) ...<Widget>[
              _SaleRow(sale: sale, currency: currency),
              if (sale != sales.last) ...<Widget>[
                SizedBox(height: tokens.spacing.s12),
                Divider(height: 1, color: tokens.colors.surface.borderSubtle),
                SizedBox(height: tokens.spacing.s12),
              ],
            ],
        ],
      ),
    );
  }
}

final class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.sale, required this.currency});

  final TenantSale sale;
  final TenantReportingCurrency? currency;

  /// The old screen's `Item +2 more`.
  String get _preview {
    if (sale.lines.isEmpty) return 'No items';
    final first = sale.lines.first.name;
    final rest = sale.lines.length - 1;
    return rest > 0 ? '$first +$rest more' : first;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final tender = sale.tender;
    final cash = tender == CheckoutTender.cash;
    final at = sale.recordedAt;
    return Row(
      children: <Widget>[
        Container(
          width: WeeklyReportMetrics.saleGlyph,
          height: WeeklyReportMetrics.saleGlyph,
          decoration: BoxDecoration(
            color: tokens.colors.surface.field,
            borderRadius: BorderRadius.circular(tokens.radius.sm),
          ),
          child: Icon(
            cash ? Icons.payments_outlined : Icons.credit_card,
            color: tokens.colors.status.ok.fg,
            size: WeeklyReportMetrics.cardGlyph,
          ),
        ),
        SizedBox(width: tokens.spacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.labelMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
              Text(
                at == null
                    ? 'Time not recorded'
                    : weeklyReportStampFormat.format(at.toLocal()),
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.spacing.s8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              weeklyReportMoney(currency, sale.totalMinor / 100),
              style: tokens.typography.labelMedium.copyWith(
                color: tokens.colors.text.money,
              ),
            ),
            SizedBox(height: tokens.spacing.s4),
            StatusBadge(
              status: cash ? AppStatus.ok : AppStatus.info,
              label: tender?.label ?? 'Not recorded',
            ),
          ],
        ),
      ],
    );
  }
}
