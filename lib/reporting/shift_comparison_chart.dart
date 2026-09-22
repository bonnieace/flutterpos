/// `ShiftComparisonChart`: one thick bar per cashier, so a day is read as a
/// comparison.
///
/// **A column chart rather than a row of meters, and the difference is what it
/// is for.** Horizontal bars answer *how much did this shift take* one row at a
/// time; the question here is *who took what*, and that is a comparison the eye
/// makes across a shared baseline. Equal widths, one baseline, height the only
/// variable.
///
/// **Every bar carries its own figure above it and its own name below.** Hard
/// rule 4: the chart is never the whole statement, and the labels under it are
/// the accessible reading of exactly the same data. Nothing here is told by
/// colour alone - the emphasis colour marks the tallest bar, which the figures
/// already say.
///
/// **It only ever draws one trading day.** A shift belongs to a business date,
/// and `ShiftClosingSummary` is a per-shift total rather than a per-cashier
/// one; summing shifts across a longer period would put one cashier in several
/// columns. The caller is responsible for asking only when its period is a
/// single day.
library;

import 'package:flutter/material.dart';

import '../shift/shift_history.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'reporting_currency.dart';

/// Whether this shift can be drawn as a bar with a height.
///
/// **Open is disqualifying even when the record carries a total.** A running
/// shift's figures are written by its close, so the value sitting on the
/// document mid-shift is a partial one - `_Bar` has always refused to give it
/// a height, and everything that reasons about the chart has to agree with
/// that or the three answers drift apart: the scale would be set by a figure
/// no bar is drawn to, and a day would plot as a comparison with one bar in
/// it.
bool _plottable(TenantShiftDaySlice shift) =>
    !shift.isOpen && shift.totalSales != null;

/// How many cashiers the chart will draw before it gives up and says so.
///
/// **Five, because a sixth column is about 60 logical pixels on a 390 phone** -
/// narrower than the figure printed above it. A day with more shifts than this
/// says how many it left out and sends the reader to shift history, which is a
/// list and has room.
const int maximumComparedShifts = 5;

/// The shifts a chart will draw, oldest first, capped at [maximumComparedShifts].
///
/// **Ordered by the instant the record holds, not by document ID.** The day
/// query returns ID order and the IDs embed a timestamp, but this chart
/// *prints* each start time - so reading the order off anything else is how a
/// chart comes to disagree with its own labels. `shift_history.dart` is
/// explicit that ID order is never presented as proof of time.
///
/// A shift with no recorded start sorts last rather than being dropped: it
/// still took money.
List<TenantShiftDaySlice> comparedShifts(List<TenantShiftDaySlice> shifts) {
  final ordered = shifts.toList()
    ..sort((a, b) {
      final left = a.startedAt;
      final right = b.startedAt;
      if (left == null && right == null) return a.id.compareTo(b.id);
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });
  return List<TenantShiftDaySlice>.unmodifiable(
    ordered.take(maximumComparedShifts),
  );
}

/// A compact figure for a bar's own label: no currency code, thousands folded.
///
/// The same arithmetic the weekly revenue chart's axis uses, restated here
/// rather than imported so a chart component does not depend on a screen.
String comparisonBarMoney(double amount) {
  final whole = amount.round();
  if (whole.abs() < 1000) return '$whole';
  final thousands = whole / 1000;
  return thousands.abs() < 100
      ? '${thousands.toStringAsFixed(1)}k'
      : '${thousands.round()}k';
}

/// The per-cashier comparison for one day.
final class ShiftComparisonChart extends StatelessWidget {
  const ShiftComparisonChart({
    super.key,
    required this.shifts,
    required this.currency,
    required this.nameFor,
  });

  /// Already ordered and capped by [comparedShifts], so the bars and the
  /// labels under them cannot be built from two different lists.
  final List<TenantShiftDaySlice> shifts;
  final TenantReportingCurrency currency;

  /// What to call one cashier. The caller resolves it, so the printed label and
  /// the spoken one cannot disagree.
  final String Function(TenantShiftDaySlice shift) nameFor;

  /// The tallest a bar is drawn.
  static const double plotHeight = 132;

  /// The height reserved above a bar for its own figure.
  static const double labelHeight = 20;

  /// A shift that took nothing still gets a visible stub, because a column of
  /// zero height is indistinguishable from a cashier who was never there.
  static const double minimumBar = 4;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // Only drawn bars set the scale. A running shift's partial total is not
    // plotted, so letting it set the ceiling would shrink every real bar
    // against a figure that is nowhere on the chart.
    final largest = shifts
        .where(_plottable)
        .map((shift) => shift.totalSales!)
        .fold<double>(0, (a, b) => a > b ? a : b);
    // **One column is not a comparison, so it is not drawn as one.** A single
    // bar against an empty 132-pixel plot is a chart of itself: there is no
    // second bar to read it against, and the void above it reads as missing
    // data rather than as a scale. The facts are the same either way, so the
    // rows state them and the plot is not reserved.
    //
    // **What counts is bars that can have a height, not shifts.** An open
    // shift's takings are written by its close, so it is drawn as an outline
    // with no height - and one real bar beside one outline is the same chart
    // of itself, which is what a morning with a running till looks like for
    // most of the day.
    if (shifts.where(_plottable).length < 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final shift in shifts) ...<Widget>[
            if (shift != shifts.first) SizedBox(height: tokens.spacing.s12),
            _StatedShift(
              shift: shift,
              currency: currency,
              name: nameFor(shift),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: plotHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (final shift in shifts)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacing.s4,
                    ),
                    child: _Bar(
                      shift: shift,
                      largest: largest,
                      currency: currency,
                      name: nameFor(shift),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        // The baseline the bars are compared against, drawn rather than
        // implied, so a short bar reads as short and not as missing.
        Container(height: 1, color: tokens.colors.surface.cardEdge),
        SizedBox(height: tokens.spacing.s8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final shift in shifts)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s4),
                  child: Column(
                    children: <Widget>[
                      Text(
                        // The given name only: a full name ellipsises to
                        // nothing at five columns, and a shop calls the person
                        // by it anyway. The bar announces the whole name.
                        _given(nameFor(shift)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: tokens.typography.bodyMedium,
                      ),
                      Text(
                        clockAt(shift.startedAt),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: tokens.typography.caption.copyWith(
                          color: tokens.colors.text.tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _given(String name) {
    final first = name.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? name : first;
  }

  /// The instant the record holds, or a dash. Never inferred from the ID.
  static String clockAt(DateTime? at) {
    if (at == null) return '—';
    final local = at.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

final class _Bar extends StatelessWidget {
  const _Bar({
    required this.shift,
    required this.largest,
    required this.currency,
    required this.name,
  });

  final TenantShiftDaySlice shift;
  final double largest;
  final TenantReportingCurrency currency;
  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final total = shift.totalSales;
    final open = shift.isOpen;
    // Spelled out rather than read from [_plottable] so the null check
    // promotes `total` for the arithmetic below; the two must say the same
    // thing, and the test that one closed shift is not a chart is what holds
    // them together.
    final plotted = !open && total != null;
    final tallest = plotted && total > 0 && total >= largest;
    final ceiling =
        ShiftComparisonChart.plotHeight - ShiftComparisonChart.labelHeight;
    final height = !plotted || largest <= 0
        ? ShiftComparisonChart.minimumBar
        : (total / largest * ceiling).clamp(
            ShiftComparisonChart.minimumBar,
            ceiling,
          );
    return Semantics(
      container: true,
      label: open
          ? '$name, shift still open'
          : '$name, '
                '${total == null ? 'no total recorded' : currency.format(total)}',
      excludeSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Text(
            open
                ? 'Open'
                : total == null
                ? '—'
                : comparisonBarMoney(total),
            maxLines: 1,
            style: tokens.typography.caption.copyWith(
              color: open
                  ? tokens.colors.status.info.fg
                  : tokens.colors.text.secondary,
            ),
          ),
          SizedBox(height: tokens.spacing.s4),
          // **An open shift is an outline, not a fill.** Its takings are
          // written by the close, so there is no figure to give the column a
          // height - and a filled bar at any height would be inventing one.
          DecoratedBox(
            decoration: BoxDecoration(
              color: open
                  ? Colors.transparent
                  : tallest
                  ? tokens.colors.chart.barEmphasis
                  : tokens.colors.chart.bar,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(tokens.radius.md),
              ),
              border: open
                  ? Border.all(color: tokens.colors.status.info.border)
                  : null,
            ),
            // Keyed so a test can measure it: the scale a bar is drawn
            // against is not visible in any text on the chart.
            child: SizedBox(
              key: ValueKey<String>('shift-bar-${shift.id}'),
              height: height,
              width: double.infinity,
            ),
          ),
        ],
      ),
    );
  }
}

/// A shift stated rather than plotted, for a day with nothing to compare.
final class _StatedShift extends StatelessWidget {
  const _StatedShift({
    required this.shift,
    required this.currency,
    required this.name,
  });

  final TenantShiftDaySlice shift;
  final TenantReportingCurrency currency;
  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final total = shift.totalSales;
    final open = shift.isOpen;
    return Semantics(
      container: true,
      label: open
          ? '$name, shift still open'
          : '$name, '
                '${total == null ? 'no total recorded' : currency.format(total)}',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name, style: tokens.typography.bodyMedium),
                Text(
                  'From ${ShiftComparisonChart.clockAt(shift.startedAt)}',
                  style: tokens.typography.caption.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.s12),
          if (open)
            StatusBadge(
              status: AppStatus.info,
              icon: Icons.timelapse_outlined,
              label: 'Open',
            )
          else
            Text(
              total == null ? '—' : currency.format(total),
              style: tokens.typography.numericBody.copyWith(
                color: tokens.colors.text.primary,
              ),
            ),
        ],
      ),
    );
  }
}
