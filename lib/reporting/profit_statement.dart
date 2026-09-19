import 'package:flutter/material.dart';

import '../ui/stats.dart';
import '../ui/tokens.dart';
import 'net_profit.dart';
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
    this.net,
  });

  final TenantProfitReport report;

  /// The same period after what the business *spent*, or null on a surface that
  /// reads no expenses.
  ///
  /// **Null keeps this widget exactly what it was.** The server's profit is
  /// revenue minus the cost of the goods sold and nothing else; a surface that
  /// has not read the period's expenses has no business implying otherwise, so
  /// it passes nothing and the block says `Profit` as it always did. A surface
  /// that has read them gets the whole statement - gross, spending, and what
  /// was actually kept.
  final TenantNetProfitReport? net;

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
    final net = this.net;
    // The spending and what it leaves are shown only when the whole period's
    // expenses were read. A partial expense total subtracts too little, which
    // makes what the business kept look *better* than it was - the same
    // overstatement `TenantProfitBasis.incomplete` refuses a gross figure for.
    // Drawn as a ceiling where it is not exact, for the reason
    // `TenantProfitReport.isDrawable` gives. The long note below still states
    // the whole of it; this block is what a reader looks at first.
    final showsNet = net != null && net.isDrawable;
    final netMargin = net?.netMarginPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.isDrawable) ...[
          StatLine(
            // Renamed only where there is a second figure to tell it apart
            // from. On a surface reading no expenses this is the only profit
            // there is, and calling it gross would imply a net it never shows.
            label: net == null ? 'Profit' : 'Gross profit',
            money: true,
            value: currency.format(report.profit),
            valueKey: ValueKey('$keyPrefix-profit'),
            detail: !report.isShowable
                ? tenantProfitCeilingNote(report)
                : net == null
                ? null
                : 'After the cost of the goods sold',
          ),
          if (margin != null)
            StatLine(
              label: net == null ? 'Margin' : 'Gross margin',
              value: '${margin.toStringAsFixed(1)}%',
              valueKey: ValueKey('$keyPrefix-margin'),
            ),
          if (showsNet) ...[
            StatLine(
              label: 'Expenses',
              money: true,
              value: currency.format(net.expenses),
              valueKey: ValueKey('$keyPrefix-expenses'),
              detail: 'Rent, wages, transport and the rest',
            ),
            StatLine(
              // **The one the others add up to**, which is what `emphasis` is
              // for. It is also the only figure on this block that answers the
              // question a shopkeeper actually asks.
              label: 'Net profit',
              money: true,
              emphasis: true,
              value: currency.format(net.netProfit),
              valueKey: ValueKey('$keyPrefix-net-profit'),
              detail: net.isShowable
                  ? null
                  : net.basis == TenantNetProfitBasis.expensesUnread
                  ? 'At most: some spending is not counted'
                  : tenantProfitCeilingNote(net.gross),
            ),
            if (netMargin != null)
              StatLine(
                label: 'Net margin',
                value: '${netMargin.toStringAsFixed(1)}%',
                valueKey: ValueKey('$keyPrefix-net-margin'),
              ),
          ],
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
        if (_netNote() case final note?)
          Padding(
            padding: EdgeInsets.only(top: tokens.spacing.s4),
            child: Text(
              key: ValueKey('$keyPrefix-net-profit-note'),
              note,
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.tertiary,
              ),
            ),
          ),
      ],
    );
  }

  /// What is known about the spending behind the net figure, or `null` where
  /// there is no net figure to qualify.
  ///
  /// The same discipline [_note] enforces for the gross figure, applied to the
  /// new way this one can be wrong. A withheld gross needs no sentence of its
  /// own here - [_note] has already said nothing is being shown and why, and
  /// repeating it in different words would read as a second, separate problem.
  String? _netNote() => switch (net?.basis) {
    null || TenantNetProfitBasis.grossWithheld => null,
    TenantNetProfitBasis.complete =>
      'Net profit is what was left after the spending recorded for this '
          'period.',
    TenantNetProfitBasis.expensesUnread =>
      'Net profit is at most this figure: some of what this business spent '
          'could not be read, and leaving it out overstates what was kept.',
  };

  String _note() => tenantProfitNote(report);
}

/// What is known about the cost data behind one profit figure.
///
/// **Lifted out of [TenantProfitStatement] so a surface that draws its profit as
/// a tile rather than a [StatLine] can still say the same sentence.** The
/// monthly report is that surface: it had a warning of its own, worded
/// differently, which is how it came to print an overstated figure while every
/// other surface withheld one. A second wording is a second rule, and there is
/// only one rule.
/// The caption that must accompany a figure drawn under
/// [TenantProfitReport.isDrawable] but not [TenantProfitReport.isShowable].
///
/// Short enough for a tile, and it names the direction the figure is wrong in.
/// **One wording, for the reason [tenantProfitNote] gives**: a second wording
/// is a second rule, and there is only one rule.
String tenantProfitCeilingNote(TenantProfitReport report) =>
    switch (report.basis) {
      TenantProfitBasis.complete => 'After cost of goods',
      TenantProfitBasis.incomplete => 'At most: some lines carry no cost',
      TenantProfitBasis.inconsistent =>
        'The cost of these sales does not add up',
    };

String tenantProfitNote(TenantProfitReport report) => switch (report.basis) {
  // The positive form of the requirement, and the reason it is stated rather
  // than left to silence: a reader cannot tell a complete figure from an
  // overstated one by looking at it.
  TenantProfitBasis.complete => 'Every sale line behind it carries a cost.',
  TenantProfitBasis.incomplete =>
    'Profit is at most this figure: '
        '${report.incompleteCostLineCount} sale '
        '${report.incompleteCostLineCount == 1 ? 'line has' : 'lines have'} '
        'no cost recorded, and counting '
        '${report.incompleteCostLineCount == 1 ? 'it' : 'them'} as free '
        'overstates it. The margin is not shown.',
  // Deliberately not phrased as a data problem the reader caused. Nothing a
  // business does can produce this; it means the figure disagrees with the
  // takings it was derived from.
  TenantProfitBasis.inconsistent =>
    'Profit and margin are not shown: the reported profit is larger than the '
        'takings it was computed from, so the figure cannot be trusted.',
};
