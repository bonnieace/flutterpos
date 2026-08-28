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
import '../ui/spring.dart';
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
  ///
  /// **These three are the reference's geometry, not a taste.** `bonnieace/
  /// Jengaapp` draws its ring in a 200 box at a 32 stroke, which puts the outer
  /// edge at 100 and the hole at 68. Reproducing the arrangement and then
  /// drawing the ring a different weight is how a replica ends up *nearly*
  /// right, which is the complaint this answers.
  static const double ringHeight = 200;

  /// The hole in the middle, which is where the total goes.
  static const double ringHoleRadius = 68;

  /// How thick the ring itself is. The reference's `ringStrokeWidth`.
  static const double ringThickness = 32;

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

  /// How thick the day line is drawn. The reference's `barWidth: 4`.
  static const double lineWidth = 4;

  /// The dot on each day, at the reference's radius and stroke.
  static const double dotRadius = 4;
  static const double dotStrokeWidth = 2;

  /// How many days may carry a dot before they stop being dots.
  ///
  /// **A month of them is a smear, not a set of points.** Thirty-one dots at
  /// radius 4 across a 320-wide phone leaves under six pixels between centres,
  /// so they merge into a thick line and the line stops being readable. Past
  /// this the line speaks for itself.
  static const int maximumDottedDays = 14;

  /// How far the shaded area under the line fades out.
  static const double areaTopOpacity = 0.22;
  static const double areaBottomOpacity = 0.02;

  /// How long the composition ring takes to sweep in.
  ///
  /// **A spring rather than a duration, because it is spatial** - `claude.md`'s
  /// motion rule - and it is driven through [SpringDrive] so a period changed
  /// mid-sweep retargets from where the arc actually is instead of snapping
  /// back to nothing and starting again.
  static const double sweptFully = 1;

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
final class ExpenseCompositionRing extends StatefulWidget {
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
  State<ExpenseCompositionRing> createState() => _ExpenseCompositionRingState();
}

class _ExpenseCompositionRingState extends State<ExpenseCompositionRing>
    with SingleTickerProviderStateMixin {
  SpringDrive? _sweep;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tokens = AppTokens.componentOf(context);
    final drive =
        _sweep ??= SpringDrive(vsync: this, spring: tokens.motion.gentle);
    // **`animateTo`, never `forward()`.** The reference's ring sweeps in from
    // nothing, and this reproduces that - but a period changed while it is
    // still sweeping retargets from where the arc is, which is the whole reason
    // this is a spring and not a curve.
    drive.animateTo(
      ExpenseChartMetrics.sweptFully,
      immediately: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
    );
  }

  @override
  void dispose() {
    _sweep?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final period = widget.period;
    final currency = widget.currency;
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
            AnimatedBuilder(
              animation: _sweep!.animation,
              builder: (context, _) {
                final swept = _sweep!.value.clamp(0.0, 1.0);
                final total = period.total.toDouble();
                return PieChart(
                  PieChartData(
                    sectionsSpace: ExpenseChartMetrics.sliceGap,
                    centerSpaceRadius: ExpenseChartMetrics.ringHoleRadius,
                    startDegreeOffset: -90,
                    sections: <PieChartSectionData>[
                      for (var index = 0; index < categories.length; index++)
                        PieChartSectionData(
                          value:
                              (period.totalByCategory[categories[index]] ?? 0)
                                  .toDouble() *
                              swept,
                          color: ExpenseCompositionRing.colorFor(tokens, index),
                          radius: ExpenseChartMetrics.ringThickness,
                          // **No titles on the slices.** A percentage printed
                          // on a thin arc is unreadable at a phone's width and
                          // it duplicates the rows below, which have room to
                          // say it properly.
                          showTitle: false,
                        ),
                      // **The remainder, drawn in nothing.** Scaling every
                      // slice by the same factor would change no angle at all -
                      // the arcs are proportions of whatever the values sum to.
                      // What makes the ring *sweep* is an invisible section
                      // holding the rest of the circle and giving it up.
                      if (swept < 1)
                        PieChartSectionData(
                          value: total * (1 - swept),
                          color: const Color(0x00000000),
                          radius: ExpenseChartMetrics.ringThickness,
                          showTitle: false,
                        ),
                    ],
                  ),
                );
              },
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // **The figure alone, with no caption over it.** The reference
                // puts the period's total in the hole and nothing else; a
                // `Spent` eyebrow above it spends a line of the hole saying
                // what the whole screen is already called.
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

/// One point per business date across a period, joined into a line.
///
/// **A line, as the reference draws it - but over dates rather than over a
/// list.** `bonnieace/Jengaapp` plots `FlSpot(index, amount)` where the index
/// is the position of a record in a filtered list, so two rents a fortnight
/// apart produce a slope across no time at all and a busy week compresses into
/// the same width as a quiet one. This keeps the reference's picture - curved,
/// dotted, shaded underneath - and puts the days back on the x axis, so the
/// distance between two points is the distance between two dates. A day with
/// nothing spent on it is a point on the floor, which is the honest reading of
/// a day nothing was spent.
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
        // **The dots come and go with the width of the period.** Seven days
        // apart on a phone are points; thirty-one are a smear, and past
        // `maximumDottedDays` the line carries the shape on its own.
        child: Builder(
          builder: (context) {
            final dotted =
                totalsMinor.length <= ExpenseChartMetrics.maximumDottedDays;
            return LineChart(
              LineChartData(
                minX: 0,
                maxX: (totalsMinor.length - 1).toDouble().clamp(0, 3650),
                minY: 0,
                maxY: ceiling,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => tokens.colors.surface.overlay,
                    getTooltipItems: (spots) => <LineTooltipItem?>[
                      for (final spot in spots)
                        LineTooltipItem(
                          '${_dayLabel(spot.x.toInt())}\n'
                          '${currency.format(spot.y)}',
                          tokens.typography.labelMedium.copyWith(
                            color: tokens.colors.text.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                lineBarsData: <LineChartBarData>[
                  LineChartBarData(
                    spots: <FlSpot>[
                      for (var index = 0; index < totalsMinor.length; index++)
                        FlSpot(index.toDouble(), totalsMinor[index] / 100),
                    ],
                    isCurved: true,
                    // A curve through daily spending can dip below a floor of
                    // nothing, and a shop cannot spend a negative amount.
                    preventCurveOverShooting: true,
                    color: chart.barEmphasis,
                    barWidth: ExpenseChartMetrics.lineWidth,
                    dotData: FlDotData(
                      show: dotted,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                            radius: ExpenseChartMetrics.dotRadius,
                            color: chart.barEmphasis,
                            strokeWidth: ExpenseChartMetrics.dotStrokeWidth,
                            // The ground the chart is drawn on, so each dot reads as a
                            // bead on the line rather than a blob in it.
                            strokeColor: tokens.colors.surface.base,
                          ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          chart.barEmphasis.withValues(
                            alpha: ExpenseChartMetrics.areaTopOpacity,
                          ),
                          chart.barEmphasis.withValues(
                            alpha: ExpenseChartMetrics.areaBottomOpacity,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
