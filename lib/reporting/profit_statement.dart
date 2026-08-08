import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (report.isShowable)
        Text(key: ValueKey('$keyPrefix-profit'), _figure()),
      Text(key: ValueKey('$keyPrefix-profit-note'), _note()),
    ],
  );

  /// The figure, and the margin only when there is one to divide by.
  String _figure() {
    final margin = report.marginPercent;
    final amount = 'Profit: ${currency.format(report.profit)}';
    return margin == null
        ? '$amount.'
        : '$amount, a margin of ${margin.toStringAsFixed(1)}%.';
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
