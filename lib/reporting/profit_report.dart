import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';

/// What a reported profit figure is actually worth.
///
/// Decided from the figures themselves rather than from where they came, so the
/// reconciled daily summary and the server-added period totals cannot disagree
/// about when a number may be believed.
enum TenantProfitBasis {
  /// Every sale line behind the figure carried a cost, so it is the profit.
  complete,

  /// At least one line carried none.
  ///
  /// The server counts a line with no cost as costing nothing, so the figure is
  /// an upper bound rather than a total - and how far above the truth it sits
  /// is not knowable from anything reported: neither surface is told how many
  /// lines there were altogether, only how many lacked a cost. An unmeasurable
  /// overstatement is not a smaller version of the truth, so nothing is shown.
  incomplete,

  /// The figure exceeds the takings it was computed from.
  ///
  /// That means a negative total cost, and nothing that writes either figure
  /// can produce one: profit is revenue minus a sum of non-negative line costs.
  /// A figure contradicting its own construction is refused rather than shown.
  inconsistent,
}

/// One period's profit, and whether it may be shown at all.
///
/// This is the single definition of that question. Both reporting surfaces hold
/// exactly the three figures it needs - takings, profit, and how many lines had
/// no cost - and neither may decide for itself what they add up to.
final class TenantProfitReport {
  const TenantProfitReport._({
    required this.sales,
    required this.profit,
    required this.incompleteCostLineCount,
    required this.basis,
    required this.marginPercent,
  });

  /// Reads one answer's figures, exactly as the server produced them.
  ///
  /// Nothing is recomputed here and nothing is corrected: a figure that cannot
  /// be trusted becomes a basis that says so, never a repaired number.
  factory TenantProfitReport.from({
    required double sales,
    required double profit,
    required int incompleteCostLineCount,
  }) {
    final salesMinor = reportingMinorUnits(sales);
    final profitMinor = reportingMinorUnits(profit);
    // What the server must have subtracted. Both figures are added up in whole
    // minor units on the server, so this is exact rather than approximate.
    final costMinor = salesMinor - profitMinor;
    // Ordered most-specific cause first, the way `stockComparisonOutcome`
    // orders its own: an impossible figure outranks an incomplete one, because
    // an incomplete figure is at least the arithmetic it claims to be.
    final basis = costMinor < 0
        ? TenantProfitBasis.inconsistent
        : incompleteCostLineCount > 0
        ? TenantProfitBasis.incomplete
        : TenantProfitBasis.complete;
    return TenantProfitReport._(
      sales: sales,
      profit: profit,
      incompleteCostLineCount: incompleteCostLineCount,
      basis: basis,
      // Withheld unless the figure it describes is shown at all. A percentage
      // is the most believed number on any report and it carries no units to
      // warn a reader, so it must never outlive the figure it was divided from.
      marginPercent: basis == TenantProfitBasis.complete && salesMinor > 0
          ? profitMinor / salesMinor * 100
          : null,
    );
  }

  /// The roles a profit figure is shown to.
  ///
  /// Deliberately narrower than the roles that may read the takings, and
  /// deliberately identical to `TenantCatalogManagementRepository.costRoles`
  /// and the server's `MONETARY_PRODUCT_FIELDS` tier: profit is cost, and the
  /// standing decision that put a buying price behind owner and administrator
  /// said in as many words that what it buys is that no manager is *shown* the
  /// margin.
  ///
  /// It is restated here rather than imported, because it is this domain's own
  /// decision about a different document: `daily_metrics` is readable by
  /// owner, administrator, and manager, so a manager's device already holds
  /// every figure below. This is a surface boundary, not a secrecy guarantee,
  /// exactly as recording a cost is - and it needs no Firestore rule to change.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  static bool canSeeInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// Major-unit takings the profit was computed from.
  final double sales;

  /// Major-unit profit, exactly as reported. Legitimately negative.
  final double profit;

  /// How many sale lines behind [profit] carried no cost.
  final int incompleteCostLineCount;

  final TenantProfitBasis basis;

  /// [profit] as a percentage of [sales], or `null` when it may not be shown.
  ///
  /// Also `null` for a period that took nothing: a margin on no takings is a
  /// division by zero, not a figure of zero.
  final double? marginPercent;

  /// Whether a figure may be put in front of somebody at all.
  bool get isShowable => basis == TenantProfitBasis.complete;
}

/// Whole minor units, rounded exactly as the server rounds.
///
/// Deliberately not `checkoutMinorUnitsFromMajor`: that one refuses an amount
/// the till could not price and exists to stop a bad price being recorded,
/// while these figures are already recorded, arrive from the server, and are
/// only ever compared with each other. Comparing in whole minor units is what
/// makes those comparisons exact instead of needing a tolerance that could hide
/// a genuine disagreement.
int reportingMinorUnits(double amount) => (amount * 100).round();
