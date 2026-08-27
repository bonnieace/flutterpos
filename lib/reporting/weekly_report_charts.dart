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
  });

  final TenantReportWeek week;
  final TenantWeeklyReport? report;
  final TenantReportingCurrency? currency;

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
          Text(
            'Total: ${weeklyReportMoney(currency, total)}',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
          SizedBox(height: tokens.spacing.s24),
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
final class WeeklyTopItems extends StatelessWidget {
  const WeeklyTopItems({
    super.key,
    required this.report,
    required this.currency,
  });

  final TenantWeeklyReport? report;
  final TenantReportingCurrency? currency;

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
          if (items.isEmpty)
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
