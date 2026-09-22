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

  /// How far past the first and last day the plot extends, so their labels
  /// have somewhere to sit. Half a day either side, at most.
  static const double axisMargin = 0.5;

  /// The share of the plot that margin may take at each end.
  ///
  /// **Half a day is the wrong unit on a short period**, at the developer's
  /// direction on 2026-09-22, and the trim of the empty ends is what made it
  /// obvious: a month spends 1.6% of its width on each margin, while three days
  /// spend 17% each - so the line a person is actually reading was drawn across
  /// two thirds of the box with a sixth of it blank at either end. What the
  /// margin is for is a fixed thing - somewhere for the first and last date to
  /// sit - so it is bounded as a share of the plot rather than as a fraction of
  /// a slot whose width changes with the period.
  static const double axisMarginShare = 0.08;

  /// How far past the first and last of [points] days the plot extends.
  ///
  /// One day keeps the whole half-slot: there is no span to take a share of,
  /// and a lone dot belongs in the middle of its own box rather than against
  /// an edge. Past ten days the share exceeds half a slot and this is [axisMargin]
  /// again, so nothing about a month or a fortnight moves.
  static double axisMarginFor(int points) {
    if (points <= 1) return axisMargin;
    return ((points - 1) * axisMarginShare).clamp(0.0, axisMargin);
  }

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
    final drive = _sweep ??= SpringDrive(
      vsync: this,
      spring: tokens.motion.gentle,
    );
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

  /// The first and last day of [dates] that anything was spent on, or null
  /// where nothing was.
  ///
  /// **The empty run at each end is not data and is not drawn**, at the
  /// developer's direction on 2026-09-22. The period is the stretch of days a
  /// person asked for, not the stretch their spending fell in: one expense
  /// inside *Last 30 days* used to draw twenty-nine points of nothing and one
  /// spike, which reads as a month of activity that did not happen. Trimmed, one
  /// expense is one point - a dot, which is what the app this feature came from
  /// drew - and two expenses three days apart are the four days between them.
  ///
  /// **Only the ends are trimmed.** A day with no spending *between* two days
  /// with some is a real zero and stays: dropping it would put the two spends
  /// side by side and lose the gap, which is the distortion the empty days were
  /// kept for in the first place.
  ({int first, int last})? get _spent {
    var first = -1;
    var last = -1;
    for (var index = 0; index < totalsMinor.length; index++) {
      if (totalsMinor[index] <= 0) continue;
      if (first < 0) first = index;
      last = index;
    }
    return first < 0 ? null : (first: first, last: last);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final chart = tokens.colors.chart;
    // A period nothing was spent in has no run to trim, so it keeps the whole
    // window and draws the flat line it always did - which is the honest
    // picture of a type that took no money.
    final spent = _spent;
    final from = spent?.first ?? 0;
    final to = spent?.last ?? totalsMinor.length - 1;
    final charted = <int>[
      for (var index = from; index <= to; index++) totalsMinor[index],
    ];
    final peak = charted.fold<int>(0, (a, b) => a > b ? a : b);
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
            // **A single day is always dotted.** `fl_chart` draws a line
            // between points and there is no line through one, so a lone day
            // with its dots suppressed would render an empty box - which is the
            // one reading this chart must never give a type that has taken
            // money.
            final dotted =
                charted.length <= ExpenseChartMetrics.maximumDottedDays;
            final margin = ExpenseChartMetrics.axisMarginFor(charted.length);
            return LineChart(
              LineChartData(
                // **Half a slot of margin at each end**, which is what
                // `BarChartAlignment.spaceAround` used to give the bars for
                // free. Without it the first and last points sit exactly on
                // the plot's edges and their date labels - centred under them -
                // hang off the screen, which is what the first capture of this
                // line showed on the right.
                minX: -margin,
                maxX: (charted.length - 1).toDouble().clamp(0, 3650) + margin,
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
                      for (var index = 0; index < charted.length; index++)
                        FlSpot(index.toDouble(), charted[index] / 100),
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
                      // **One tick per day, pinned to whole days.** Extending
                      // the plot half a slot past each end let fl_chart pick
                      // its own interval, and a tick at 3.5 truncated to the
                      // same index as one at 3 - so a month drew the same date
                      // twelve times over.
                      interval: 1,
                      reservedSize: tokens.spacing.s20,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: EdgeInsets.only(top: tokens.spacing.s4),
                        child: Text(
                          // **Only the ends and the middle are labelled.** A month
                          // is thirty-one bars and a label under every one is a
                          // grey smear; the tooltip names the exact day on a tap.
                          _axisLabel(value),
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

  /// The dates actually plotted, which is [dates] without its empty ends.
  List<String> get _charted {
    final spent = _spent;
    if (spent == null) return dates;
    return dates.sublist(spent.first, spent.last + 1);
  }

  String _dayLabel(int index) {
    final charted = _charted;
    return index >= 0 && index < charted.length ? charted[index] : '';
  }

  String _axisLabel(num position) {
    // A tick that is not on a day names no day. Cheap insurance against the
    // interval above ever being relaxed again.
    if ((position - position.round()).abs() > 0.001) return '';
    final index = position.round();
    final charted = _charted;
    final middle = charted.length ~/ 2;
    if (charted.length > 1 &&
        index != 0 &&
        index != charted.length - 1 &&
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
    // The days the chart draws, not the days the period covers: a reader who
    // cannot see it is told what is there rather than what was asked for.
    final days = _charted.length;
    return 'Spending by day, ${currency.format(total)} across '
        '$days ${days == 1 ? 'day' : 'days'}. Each day and '
        'its amount is listed below.';
  }
}
