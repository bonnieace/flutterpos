/// Staff against each other, over a period of trading.
///
/// **The comparison is the report.** The staff screen is a directory: who is on
/// the roster, what role they hold, whether their invitation landed. It
/// deliberately carries no counters at all, because a figure assembled from the
/// page currently on screen was judged a lie. This does not fix that by
/// counting a page harder - it reads the whole roster and a whole period, and
/// then says what nobody can see today: who takes the most, who earns the most
/// per sale, who gives away the most in discounts, and how far the shop leans
/// on one person.
///
/// **The denominator rule is load-bearing here.** Every ranked figure below is
/// exact for the person it names whatever the read reached. Every *share* -
/// concentration, share of takings, "two of nine staff took 58%" - is withheld
/// unless the whole directory was read, because a share of an unknown whole is
/// not a measurement. [isComplete] is what decides, and the report reads it
/// rather than assuming.
library;

import '../../sales/sale_history.dart';
import '../../tenancy/tenant_staff_directory.dart';
import '../../tenancy/tenant_types.dart';
import '../report_period.dart';

/// One person's trading over the period.
final class TenantStaffPerformance {
  const TenantStaffPerformance({
    required this.uid,
    required this.name,
    required this.role,
    required this.status,
    required this.revenueMinor,
    required this.previousRevenueMinor,
    required this.costMinor,
    required this.discountMinor,
    required this.transactions,
    required this.itemsSold,
    required this.linesWithoutCost,
    required this.lineCount,
    required this.daysTraded,
  });

  final String uid;
  final String name;
  final TenantRole role;
  final MembershipStatus status;

  final int revenueMinor;
  final int previousRevenueMinor;
  final int costMinor;
  final int discountMinor;
  final int transactions;
  final int itemsSold;
  final int linesWithoutCost;
  final int lineCount;

  /// How many business dates this person rang anything up on.
  final int daysTraded;

  /// The mean sale.
  int get averageSaleMinor =>
      transactions == 0 ? 0 : (revenueMinor / transactions).round();

  /// Units per sale.
  double get averageBasket =>
      transactions == 0 ? 0 : itemsSold / transactions;

  /// Takings less cost, or null where not one line recorded a cost.
  ///
  /// Null rather than the full takings, for the reason the sales analysis
  /// gives: an unknown margin is not a large one, and treating it as pure
  /// profit would rank the worst record-keeping highest.
  int? get marginMinor =>
      lineCount > 0 && linesWithoutCost == lineCount
      ? null
      : revenueMinor - costMinor;

  /// What this person gave away, as a share of what they would otherwise have
  /// taken.
  ///
  /// **A control figure, not a sales one.** A discount rate well above the rest
  /// of the shop is a question worth asking, and it is invisible on every
  /// screen in the app.
  double? get discountRate {
    final gross = revenueMinor + discountMinor;
    return gross == 0 ? null : discountMinor / gross;
  }

  /// Takings per day actually worked, which is the fairer comparison between
  /// somebody on every shift and somebody on two.
  int get revenuePerDayMinor =>
      daysTraded == 0 ? 0 : (revenueMinor / daysTraded).round();

  /// How far this person's takings moved, or null where they took nothing
  /// before.
  double? get change {
    if (previousRevenueMinor == 0) return null;
    return (revenueMinor - previousRevenueMinor) / previousRevenueMinor.abs();
  }

  bool get soldNothing => transactions == 0;
}

/// A roster and a period, compared.
final class TenantStaffAnalysis {
  const TenantStaffAnalysis._({
    required this.period,
    required this.people,
    required this.isComplete,
    required this.directoryCount,
    required this.documentsRead,
    required this.truncated,
  });

  /// Computes the analysis from a roster and the sales of a period.
  ///
  /// [isComplete] must be false where the directory walk stopped early. It is
  /// not inferred, because only the loader knows whether it ran out of pages.
  factory TenantStaffAnalysis.from({
    required TenantReportPeriod period,
    required List<TenantStaffSummary> roster,
    required List<TenantSale> sales,
    List<TenantSale> previous = const <TenantSale>[],
    bool isComplete = true,
    bool truncated = false,
    int documentsRead = 0,
  }) {
    final byStaff = <String, _Tally>{};
    for (final member in roster) {
      byStaff[member.uid] = _Tally();
    }

    for (final sale in sales) {
      // A sale by somebody no longer on the roster still happened, and the
      // takings are the shop's. It gets a row rather than being dropped.
      final tally = byStaff.putIfAbsent(sale.soldById, _Tally.new);
      tally.revenue += sale.totalMinor;
      tally.discount += sale.discountMinor;
      tally.transactions++;
      tally.dates.add(sale.businessDate);
      for (final line in sale.lines) {
        tally.lineCount++;
        tally.items += line.quantity;
        final cost = line.lineCostMinor;
        if (cost == null) {
          tally.linesWithoutCost++;
        } else {
          tally.cost += cost;
        }
      }
    }

    final previousRevenue = <String, int>{};
    for (final sale in previous) {
      previousRevenue.update(
        sale.soldById,
        (held) => held + sale.totalMinor,
        ifAbsent: () => sale.totalMinor,
      );
    }

    final named = <String, TenantStaffSummary>{
      for (final member in roster) member.uid: member,
    };

    final people = <TenantStaffPerformance>[
      for (final entry in byStaff.entries)
        TenantStaffPerformance(
          uid: entry.key,
          name: named[entry.key]?.displayName ?? _departed,
          role: named[entry.key]?.role ?? TenantRole.cashier,
          status: named[entry.key]?.status ?? MembershipStatus.inactive,
          revenueMinor: entry.value.revenue,
          previousRevenueMinor: previousRevenue[entry.key] ?? 0,
          costMinor: entry.value.cost,
          discountMinor: entry.value.discount,
          transactions: entry.value.transactions,
          itemsSold: entry.value.items,
          linesWithoutCost: entry.value.linesWithoutCost,
          lineCount: entry.value.lineCount,
          daysTraded: entry.value.dates.length,
        ),
    ]..sort((a, b) => b.revenueMinor.compareTo(a.revenueMinor));

    return TenantStaffAnalysis._(
      period: period,
      people: List<TenantStaffPerformance>.unmodifiable(people),
      isComplete: isComplete,
      directoryCount: roster.length,
      documentsRead: documentsRead,
      truncated: truncated,
    );
  }

  final TenantReportPeriod period;

  /// Everybody with a row, by takings, largest first.
  final List<TenantStaffPerformance> people;

  /// Whether the whole directory was read.
  ///
  /// **The gate on every share in this report.** False means the figures for
  /// each named person are still exact, and no ranking across the whole is
  /// shown - the staff screen deleted four counters over precisely this.
  final bool isComplete;

  final int directoryCount;
  final int documentsRead;
  final bool truncated;

  /// The name given to takings by somebody no longer on the roster.
  static const String _departed = 'No longer on the roster';

  /// The people who actually rang something up.
  List<TenantStaffPerformance> get trading =>
      people.where((p) => !p.soldNothing).toList();

  /// Roster members who sold nothing in the period.
  ///
  /// Worth naming rather than omitting: a cashier with no sales for a fortnight
  /// is either not working or not using the till, and both are findings.
  List<TenantStaffPerformance> get idle =>
      people.where((p) => p.soldNothing).toList();

  int get revenueMinor =>
      people.fold(0, (sum, person) => sum + person.revenueMinor);

  int get transactions =>
      people.fold(0, (sum, person) => sum + person.transactions);

  /// The middle mean-sale across the people who traded.
  ///
  /// **A median rather than a mean of means.** One person having a very good
  /// fortnight should not move the line everybody else is measured against.
  int get medianAverageSaleMinor {
    final sales = trading.map((p) => p.averageSaleMinor).toList()..sort();
    if (sales.isEmpty) return 0;
    return sales[sales.length ~/ 2];
  }

  /// The largest share one person took, or null where a share cannot be quoted.
  double? get concentration {
    if (!isComplete || revenueMinor <= 0 || trading.isEmpty) return null;
    return trading.first.revenueMinor / revenueMinor;
  }

  /// How few people took [fraction] of the takings, or null where a share
  /// cannot be quoted.
  int? headCountFor(double fraction) {
    if (!isComplete || revenueMinor <= 0) return null;
    var running = 0;
    for (final (index, person) in trading.indexed) {
      running += person.revenueMinor;
      if (running / revenueMinor >= fraction) return index + 1;
    }
    return trading.length;
  }

  /// This person's share of the shop's takings, or null where one cannot be
  /// quoted.
  double? shareOf(TenantStaffPerformance person) {
    if (!isComplete || revenueMinor <= 0) return null;
    return person.revenueMinor / revenueMinor;
  }

  /// Where each person placed last period, by uid.
  ///
  /// A rank that moved is information no screen holds, and it survives a shop
  /// whose takings went up or down as a whole.
  Map<String, int> get previousRanks {
    final ordered = people.where((p) => p.previousRevenueMinor > 0).toList()
      ..sort((a, b) => b.previousRevenueMinor.compareTo(a.previousRevenueMinor));
    return <String, int>{
      for (final (index, person) in ordered.indexed) person.uid: index + 1,
    };
  }

  /// How far this person moved up the ranking, or null where they were not
  /// ranked before.
  ///
  /// Positive is a climb.
  int? rankChangeOf(TenantStaffPerformance person) {
    final was = previousRanks[person.uid];
    if (was == null) return null;
    final now = trading.indexWhere((p) => p.uid == person.uid);
    if (now < 0) return null;
    return was - (now + 1);
  }

  /// Whether anybody's discount rate stands well clear of the rest.
  ///
  /// Returns the person, or null when nothing stands out. The threshold is a
  /// multiple of the shop's own rate rather than an absolute, because a shop
  /// that discounts nothing and one that always does are different places.
  TenantStaffPerformance? get discountOutlier {
    final rates = trading
        .where((p) => p.discountRate != null)
        .toList(growable: false);
    if (rates.length < 3) return null;
    final shopGross = revenueMinor + people.fold(0, (s, p) => s + p.discountMinor);
    if (shopGross == 0) return null;
    final shopRate =
        people.fold(0, (s, p) => s + p.discountMinor) / shopGross;
    if (shopRate <= 0) return null;
    final worst = rates.reduce(
      (a, b) => (b.discountRate ?? 0) > (a.discountRate ?? 0) ? b : a,
    );
    return (worst.discountRate ?? 0) >= shopRate * _outlierMultiple
        ? worst
        : null;
  }

  static const double _outlierMultiple = 2;
}

final class _Tally {
  int revenue = 0;
  int cost = 0;
  int discount = 0;
  int transactions = 0;
  int items = 0;
  int lineCount = 0;
  int linesWithoutCost = 0;
  final Set<String> dates = <String>{};
}
