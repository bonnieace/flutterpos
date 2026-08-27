/// The two pictures the expense tracker draws.
///
/// **Carried across from the project this feature came from, and rebuilt.** That
/// app drew a `pie_chart` ring of spending by category with the total in its
/// centre, and an `fl_chart` line of one category over time. Both readings were
/// worth keeping; neither implementation was. This uses the `fl_chart` already
/// in the project rather than a second charting package, takes every colour
/// from `AppTokens`, and - the part that actually matters - never leaves a
/// colour carrying a fact on its own.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../reporting/reporting_currency.dart';
import '../ui/tokens.dart';
import 'expense.dart';

/// The measurements both charts are drawn at.
///
/// Named rather than inline for the reason `WeeklyReportMetrics` exists: a
/// chart is arithmetic, and arithmetic buried in a widget cannot be checked
/// without reading pixels out of a screenshot.
final class ExpenseChartMetrics {
  const ExpenseChartMetrics._();

  /// How tall the composition ring is drawn.
  static const double ringHeight = 220;

  /// The hole in the middle, which is where the total goes.
  static const double ringHoleRadius = 64;

  /// How thick the ring itself is.
  static const double ringThickness = 26;

  /// The gap between one slice and the next, so two adjacent slices of similar
  /// shade still read as two.
  static const double sliceGap = 2;

  /// How tall the per-day chart is drawn.
  static const double dailyHeight = 160;

  /// How much of the hole's diameter the total may use.
  ///
  /// The hole is a circle and the figure is a straight line across it, so the
  /// usable width is less than the diameter - a figure sized to the full 2r
  /// runs out through the ring on both sides, which is exactly what the first
  /// capture of this chart showed.
  static const double ringTextFraction = 0.82;

  /// The widest a bar is drawn.
  static const double barWidth = 14;

  /// The narrowest a bar may be squeezed to before it stops reading as a bar.
  static const double minimumBarWidth = 3;

  /// How much of each day's slot a bar fills, so bars never touch.
  static const double barSlotFill = 0.6;

  /// The width one bar gets when [dates] of them have to share [available].
  static double barWidthFor({required double available, required int days}) {
    if (days <= 0) return barWidth;
    final slot = available / days * barSlotFill;
    return slot.clamp(minimumBarWidth, barWidth);
  }

  /// What the vertical axis runs to when nothing was spent at all, so an empty
  /// chart is a flat floor rather than a division by zero.
  static const double emptyCeiling = 1;

  /// How much headroom the tallest bar leaves above it.
  static const double ceilingHeadroom = 1.15;
}

/// Spending split by category, as a ring with the total in the middle.
///
/// **The ring is never the whole statement.** It is drawn above the labelled
/// rows that carry each category's name, figure and share, and those rows are
/// the accessible reading of exactly the same data - so a person who cannot
/// separate two shades of green loses nothing (hard rule 4). This widget draws
/// nothing at all for a period that spent nothing: a ring of one grey slice
/// says a business had one expense, which is a different fact from none.
final class ExpenseCompositionRing extends StatelessWidget {
  const ExpenseCompositionRing({
    super.key,
    required this.period,
    required this.currency,
  });

  final TenantExpensePeriod period;
  final TenantReportingCurrency currency;

  /// The colour category [index] of [TenantExpensePeriod.spentCategories] is
  /// drawn in, so the ring and its legend cannot disagree.
  static Color colorFor(AppTokens tokens, int index) {
    final series = tokens.colors.chart.series;
    return series[index % series.length];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final categories = period.spentCategories;
    if (categories.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      // The rows beneath state every figure. This says what the picture is and
      // sends a screen reader to the text rather than reading out geometry.
      label:
          'Spending by category as a ring. Every category and its amount is '
          'listed below.',
      excludeSemantics: true,
      child: SizedBox(
        height: ExpenseChartMetrics.ringHeight,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            PieChart(
              PieChartData(
                sectionsSpace: ExpenseChartMetrics.sliceGap,
                centerSpaceRadius: ExpenseChartMetrics.ringHoleRadius,
                startDegreeOffset: -90,
                sections: <PieChartSectionData>[
                  for (var index = 0; index < categories.length; index++)
                    PieChartSectionData(
                      value: (period.totalByCategory[categories[index]] ?? 0)
                          .toDouble(),
                      color: colorFor(tokens, index),
                      radius: ExpenseChartMetrics.ringThickness,
                      // **No titles on the slices.** A percentage printed on a
                      // thin arc is unreadable at a phone's width and it
                      // duplicates the rows below, which have room to say it
                      // properly.
                      showTitle: false,
                    ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Spent',
                  style: tokens.typography.labelEyebrow.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
                SizedBox(height: tokens.spacing.s4),
                // **Shrunk to fit rather than clipped.** A shop that spent six
                // figures this month has a longer total than one that spent
                // three, and the hole does not grow - so the figure gives way,
                // and it gives way by scaling rather than by losing digits.
                SizedBox(
                  width:
                      ExpenseChartMetrics.ringHoleRadius *
                      2 *
                      ExpenseChartMetrics.ringTextFraction,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      currency.format(period.total),
                      key: const ValueKey('expenses-ring-total'),
                      maxLines: 1,
                      style: tokens.typography.numericCompact.copyWith(
                        color: tokens.colors.text.money,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One bar per business date across a period.
///
/// **Bars rather than the line the old app drew.** Its line joined one expense
/// to the next by position in a list, so two rents a fortnight apart produced a
/// slope that meant nothing - the x axis was the index, not the date. Spending
/// is a set of separate events on separate days, and a bar per day is the shape
/// that is actually true of it. A day with nothing on it is a gap in the row
/// rather than a missing point, which is also the honest picture.
final class ExpenseDailyChart extends StatelessWidget {
  const ExpenseDailyChart({
    super.key,
    required this.dates,
    required this.totalsMinor,
    required this.currency,
  });

  /// Every business date in the period, ascending, including the empty ones.
  final List<String> dates;

  /// What was spent on each of [dates], in whole minor units.
  final List<int> totalsMinor;

  final TenantReportingCurrency currency;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final chart = tokens.colors.chart;
    final peak = totalsMinor.fold<int>(0, (a, b) => a > b ? a : b);
    final ceiling = peak <= 0
        ? ExpenseChartMetrics.emptyCeiling
        : peak / 100 * ExpenseChartMetrics.ceilingHeadroom;
    return Semantics(
      container: true,
      label: _summary(),
      excludeSemantics: true,
      child: SizedBox(
        height: ExpenseChartMetrics.dailyHeight,
        // **The bar width is measured, not assumed.** Seven days and thirty
        // days share this chart; a fixed 14 that reads well across a week
        // overlaps its neighbours across a month, and the overlap is invisible
        // until a business actually spends on consecutive days.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = ExpenseChartMetrics.barWidthFor(
              available: constraints.maxWidth,
              days: totalsMinor.length,
            );
            return BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: ceiling,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => tokens.colors.surface.overlay,
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                      '${_dayLabel(group.x)}\n'
                      '${currency.format(rod.toY)}',
                      tokens.typography.labelMedium.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: tokens.spacing.s20,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: EdgeInsets.only(top: tokens.spacing.s4),
                        child: Text(
                          // **Only the ends and the middle are labelled.** A month
                          // is thirty-one bars and a label under every one is a
                          // grey smear; the tooltip names the exact day on a tap.
                          _axisLabel(value.toInt()),
                          style: tokens.typography.caption.copyWith(
                            color: chart.axisLabel,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: chart.gridLine, strokeWidth: 1),
                ),
                barGroups: <BarChartGroupData>[
                  for (var index = 0; index < totalsMinor.length; index++)
                    BarChartGroupData(
                      x: index,
                      barRods: <BarChartRodData>[
                        BarChartRodData(
                          toY: totalsMinor[index] / 100,
                          width: barWidth,
                          borderRadius: BorderRadius.circular(tokens.radius.sm),
                          // The heaviest day of the period is the one the eye
                          // should land on, exactly as the weekly chart picks out
                          // the best day of the week.
                          color: peak > 0 && totalsMinor[index] == peak
                              ? chart.barEmphasis
                              : chart.bar,
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _dayLabel(int index) =>
      index >= 0 && index < dates.length ? dates[index] : '';

  String _axisLabel(int index) {
    final middle = dates.length ~/ 2;
    if (dates.length > 1 &&
        index != 0 &&
        index != dates.length - 1 &&
        index != middle) {
      return '';
    }
    // **The month is named, not just the day.** A thirty-day period crosses a
    // month end more often than not, and bare days then read `29 13 27` -
    // three numbers in no order at all, which is what the first capture of
    // this chart showed.
    final date = _dayLabel(index);
    if (date.length < 10) return date;
    return _axisFormat.format(DateTime.parse(date));
  }

  static final DateFormat _axisFormat = DateFormat('d MMM');

  String _summary() {
    final total = totalsMinor.fold<int>(0, (sum, value) => sum + value);
    if (total <= 0) return 'Nothing was spent on any day of this period.';
    return 'Spending by day, ${currency.format(total)} across '
        '${dates.length} ${dates.length == 1 ? 'day' : 'days'}. Each day and '
        'its amount is listed below.';
  }
}
