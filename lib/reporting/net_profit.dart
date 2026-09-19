import '../expenses/expense.dart';
import 'profit_report.dart';

/// What a reported *net* profit figure is worth.
///
/// The gross figure has its own three-way answer in [TenantProfitBasis], and
/// this does not replace it: net profit is gross profit minus what the business
/// spent, so it inherits every doubt the gross figure carries and adds one of
/// its own.
enum TenantNetProfitBasis {
  /// Gross profit may be shown and the period's expenses were read whole.
  complete,

  /// The gross figure itself may not be shown, so nothing derived from it may.
  ///
  /// **Deliberately first**, ahead of any expense problem. Subtracting real,
  /// completely-read expenses from an untrustworthy gross does not produce a
  /// partly-trustworthy net; it produces a figure that looks *more* considered
  /// than the one it came from, which is worse than showing nothing.
  grossWithheld,

  /// The expenses could not be read, or more of them exist than the read holds.
  ///
  /// Both are the same fact - some of what the business spent is missing - and
  /// both fail the same way. Missing expenses make net profit look *better*
  /// than it was, which is exactly the overstatement
  /// [TenantProfitBasis.incomplete] exists to refuse.
  expensesUnread,
}

/// One period's profit after everything the business spent, and whether it may
/// be shown at all.
///
/// **Why this exists rather than a change to the server's figure.** The
/// server's `profit` is revenue minus the cost of the goods sold, computed by
/// `aggregateSales` and stored on every reconciled day. Folding expenses into
/// it would silently change what every `daily_metrics` document already written
/// means, with nothing in the document to say which era it belongs to. So gross
/// stays exactly what it has always been, and net is composed here, from it.
final class TenantNetProfitReport {
  /// Reads a gross figure and a period's spending together.
  ///
  /// [expenses] is null where the read failed or was never made. Nothing is
  /// corrected and nothing is guessed: a figure that cannot be trusted becomes
  /// a basis that says so.
  factory TenantNetProfitReport.from({
    required TenantProfitReport gross,
    required TenantExpensePeriod? expenses,
  }) {
    // Most-specific cause first, the same ordering `TenantProfitReport.from`
    // uses on its own three.
    final basis = !gross.isShowable
        ? TenantNetProfitBasis.grossWithheld
        : expenses == null || expenses.truncated
        ? TenantNetProfitBasis.expensesUnread
        : TenantNetProfitBasis.complete;
    final expenseTotal = expenses?.total ?? 0;
    // Whole minor units, so this subtraction is exact rather than approximate -
    // the same reason `reportingMinorUnits` exists.
    final netMinor =
        reportingMinorUnits(gross.profit) - reportingMinorUnits(expenseTotal);
    final salesMinor = reportingMinorUnits(gross.sales);
    return TenantNetProfitReport._(
      gross: gross,
      expenses: expenseTotal,
      netProfit: netMinor / 100,
      basis: basis,
      // Withheld unless the figure it describes is shown, for the reason
      // `TenantProfitReport.marginPercent` is: a percentage is the most
      // believed number on any report and carries no units to warn a reader.
      //
      // A *negative* net margin is kept rather than withheld. A month that
      // spent more than it made is a fact about the business, not a defect in
      // the figure, and hiding it would be the one thing this whole feature
      // exists to stop.
      netMarginPercent: basis == TenantNetProfitBasis.complete && salesMinor > 0
          ? netMinor / salesMinor * 100
          : null,
    );
  }

  const TenantNetProfitReport._({
    required this.gross,
    required this.expenses,
    required this.netProfit,
    required this.basis,
    required this.netMarginPercent,
  });

  /// The gross figure this was derived from, and its own basis.
  final TenantProfitReport gross;

  /// Major-unit spending subtracted. Zero where none was read.
  final double expenses;

  /// Major-unit profit after cost of goods *and* expenses. Legitimately
  /// negative - that is the reading this feature exists to make possible.
  final double netProfit;

  final TenantNetProfitBasis basis;

  /// [netProfit] as a percentage of the period's takings, or `null` when it may
  /// not be shown.
  final double? netMarginPercent;

  /// Whether the figure is exact, and so may carry a margin or a comparison.
  bool get isShowable => basis == TenantNetProfitBasis.complete;

  /// Whether the figure may be drawn at all, captioned where it is not exact.
  ///
  /// **Follows the gross figure it was derived from.** An unread expense total
  /// makes net profit look better than it was, which is the same direction the
  /// gross overstates in - so both are ceilings and both say so. An impossible
  /// gross carries nothing derived from it.
  bool get isDrawable => gross.isDrawable;

  /// Whether the business spent more than it earned over this period.
  ///
  /// Only ever true of a showable figure: a loss is a serious thing to tell
  /// somebody, and an unread expense total can produce one out of nothing.
  bool get isLoss => isShowable && netProfit < 0;
}
