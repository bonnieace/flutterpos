import 'package:flutter/material.dart';

import '../ui/stats.dart';
import '../ui/tokens.dart';
import 'profit_report.dart';
import 'reporting_currency.dart';

/// One surface's whole statement about profit: the figure, or why there is none.
///
/// Shared by the daily summary and the period totals so the two cannot word the
/// same fact differently, and so the rule that governs it is kept in one place:
/// **no profit figure is ever rendered without, in the same block, what is known
/// about the cost data behind it.** A complete figure says it is complete; an
/// incomplete one says how many lines are missing a cost and is not shown.
///
/// The caller decides whether this is rendered at all - it is management data,
/// see [TenantProfitReport.allowedRoles] - and this widget decides what it says.
final class TenantProfitStatement extends StatelessWidget {
  const TenantProfitStatement({
    super.key,
    required this.report,
    required this.currency,
    required this.keyPrefix,
  });

  final TenantProfitReport report;

  /// The code the business published, or nothing at all. A figure is the reason
  /// this exists; its label is not.
  final TenantReportingCurrency currency;

  /// Scopes this statement's own keys, so a surface listing several days does
  /// not give two of them the same one.
  final String keyPrefix;

  /// **The figure is a [StatLine] and the sentence around it is gone**, in
  /// `design.md` §11 step 8. It read "Profit: KES 430.25, a margin of 34.4%.",
  /// which put two figures inside one sentence at whatever weight the
  /// surrounding body text happened to be - so a column of days had its money in
  /// three different places on three lines, which is the raggedness §2.2 names
  /// this app's daily summary for. The two facts are two figures now, both at
  /// `numeric.body`, both aligned to the same right edge.
  ///
  /// **The note stays directly under them and is not folded.** It is the whole
  /// point of this widget - no profit figure is rendered without, in the same
  /// block, what is known about the cost data behind it - and a `Disclosure`
  /// would make the qualification optional to read, which is the one thing it
  /// may not be.
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final margin = report.marginPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.isShowable) ...[
          StatLine(
            label: 'Profit',
            value: currency.format(report.profit),
            valueKey: ValueKey('$keyPrefix-profit'),
          ),
          if (margin != null)
            StatLine(
              label: 'Margin',
              value: '${margin.toStringAsFixed(1)}%',
              valueKey: ValueKey('$keyPrefix-margin'),
            ),
        ],
        Padding(
          padding: EdgeInsets.only(top: tokens.spacing.s4),
          child: Text(
            key: ValueKey('$keyPrefix-profit-note'),
            _note(),
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ),
      ],
    );
  }

  String _note() => switch (report.basis) {
    // The positive form of the requirement, and the reason it is stated rather
    // than left to silence: a reader cannot tell a complete figure from an
    // overstated one by looking at it.
    TenantProfitBasis.complete => 'Every sale line behind it carries a cost.',
    TenantProfitBasis.incomplete =>
      'Profit and margin are not shown: '
          '${report.incompleteCostLineCount} sale '
          '${report.incompleteCostLineCount == 1 ? 'line has' : 'lines have'} '
          'no cost recorded, and counting '
          '${report.incompleteCostLineCount == 1 ? 'it' : 'them'} as free '
          'would overstate both.',
    // Deliberately not phrased as a data problem the reader caused. Nothing a
    // business does can produce this; it means the figure disagrees with the
    // takings it was derived from.
    TenantProfitBasis.inconsistent =>
      'Profit and margin are not shown: the reported profit is larger than the '
          'takings it was computed from, so the figure cannot be trusted.',
  };
}
