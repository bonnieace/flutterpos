/// What a period of trading says, beyond what it took.
///
/// **The finding this report exists for is that the best seller is usually not
/// the best earner.** The sales screen ranks by takings, because that is what a
/// till knows. Nothing in the app ranks by margin, and the two orders are
/// routinely different: a sack of maize flour that moves forty times a week at
/// a few shillings a unit earns less than the cooking oil that moves twelve
/// times. A shopkeeper cannot see that anywhere today.
///
/// Everything else here - the weekday shape, the tender mix, the basket, the
/// discount rate - is the same kind of question: something derivable from the
/// records that no surface currently derives.
///
/// **Pure arithmetic, no I/O, no Flutter.** It takes sales that have already
/// been read. Every figure the report prints is a field here, so every figure
/// is checkable in a plain test.
library;

import '../../checkout/checkout_tender.dart';
import '../../returns/return_offsets.dart';
import '../../sales/sale_history.dart';
import '../../tenancy/tenant_catalog.dart';
import '../report_period.dart';

/// One product's contribution over the period.
final class TenantSalesItem {
  const TenantSalesItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.revenueMinor,
    required this.costMinor,
    required this.linesWithoutCost,
  });

  final String productId;
  final String name;
  final int quantity;
  final int revenueMinor;

  /// What the units sold cost, over the lines that recorded a cost.
  final int costMinor;

  /// How many of this product's lines carried no cost at all.
  final int linesWithoutCost;

  /// Takings less cost, or null where no line recorded a cost.
  ///
  /// **Null rather than the full takings.** A line with no recorded cost has an
  /// unknown margin, not a hundred per cent one, and treating it as pure profit
  /// would make the products with the worst record-keeping look like the best
  /// earners - which is precisely backwards.
  int? get marginMinor =>
      linesWithoutCost > 0 && costMinor == 0 ? null : revenueMinor - costMinor;

  /// Whether every line of this product recorded what it cost.
  bool get isCostComplete => linesWithoutCost == 0;
}

/// How a period was paid for.
final class TenantSalesTender {
  const TenantSalesTender({
    required this.tender,
    required this.minor,
    required this.transactions,
  });

  /// Null for sales recorded before the app stored a tender at all.
  final CheckoutTender? tender;

  final int minor;
  final int transactions;

  /// **Named, never dropped.** A sale whose tender was never recorded is a
  /// real sale, and leaving it out of the mix would make the percentages add
  /// up to something that is not the takings.
  String get label => tender?.label ?? 'Not recorded';
}

/// A period of trading, with the period before it for company.
final class TenantSalesAnalysis {
  const TenantSalesAnalysis._({
    required this.period,
    required this.revenueMinor,
    required this.previousRevenueMinor,
    required this.costMinor,
    required this.discountMinor,
    required this.transactions,
    required this.previousTransactions,
    required this.linesWithoutCost,
    required this.lineCount,
    required this.itemsSold,
    required this.dailyMinor,
    required this.previousDailyMinor,
    required this.weekdayMinor,
    required this.previousWeekdayMinor,
    required this.items,
    required this.tenders,
    required this.basketSizes,
    required this.returnedMinor,
    required this.fullyReturnedSales,
    required this.truncated,
    required this.documentsRead,
  });

  /// Computes the analysis from sales that have already been read.
  factory TenantSalesAnalysis.from({
    required TenantReportPeriod period,
    required List<TenantSale> sales,
    // **Null is "not read"; empty is "read, and nothing happened".** They are
    // different facts and the report says different things about them: one is
    // a gap in the evidence, the other is a quiet fortnight. Collapsing both
    // into an empty list made a shop with no trading last month look like a
    // shop whose last month could not be reached.
    List<TenantSale>? previous,
    Map<String, TenantSaleReturnOffset> returnOffsets = const {},
    Map<String, TenantSaleReturnOffset> previousReturnOffsets = const {},
    bool truncated = false,
    int documentsRead = 0,
  }) {
    var revenue = 0;
    var cost = 0;
    var discount = 0;
    var linesWithoutCost = 0;
    var lineCount = 0;
    var itemsSold = 0;
    var transactions = 0;
    var returnedMinor = 0;
    var fullyReturnedSales = 0;

    final daily = <String, int>{
      for (final date in period.businessDates) date: 0,
    };
    final weekday = List<int>.filled(DateTime.daysPerWeek, 0);
    final baskets = <int>[];
    final byProduct = <String, TenantSalesItem>{};
    final byTender = <CheckoutTender?, ({int minor, int count})>{};

    for (final sale in sales) {
      final offset = returnOffsets[sale.id];
      returnedMinor += offset?.returnedMinor ?? 0;
      if (offset?.isFullyReturned == true) {
        fullyReturnedSales++;
        continue;
      }
      transactions++;
      final net = sale.totalMinor - (offset?.returnedMinor ?? 0);
      revenue += net;
      final returnedGross = sale.lines.fold<int>(
        0,
        (sum, line) =>
            sum +
            (offset?.returnedUnitsInScope[line.productId] ?? 0) *
                line.unitPriceMinor,
      );
      discount +=
          sale.discountMinor - returnedGross + (offset?.returnedMinor ?? 0);
      if (daily.containsKey(sale.businessDate)) {
        daily[sale.businessDate] = daily[sale.businessDate]! + net;
      }
      weekday[_weekdayIndex(sale.businessDate)] += net;
      baskets.add(
        sale.lines.fold(
          0,
          (sum, line) =>
              sum +
              line.quantity -
              (offset?.returnedUnitsInScope[line.productId] ?? 0),
        ),
      );

      final tender = byTender[sale.tender];
      byTender[sale.tender] = (
        minor: (tender?.minor ?? 0) + net,
        count: (tender?.count ?? 0) + 1,
      );

      // Use the canonical discount allocation for the original sale as well
      // as its returns, so product revenue adds up to the net headline.
      final charged = describeReturnOffset(sale, {
        for (final line in sale.lines) line.productId: line.quantity,
      }).returnedMinorByProduct;
      for (final line in sale.lines) {
        final quantity =
            line.quantity - (offset?.returnedUnitsInScope[line.productId] ?? 0);
        if (quantity == 0) continue;
        lineCount++;
        itemsSold += quantity;
        final lineCost = line.unitCostMinor == null
            ? null
            : line.unitCostMinor! * quantity;
        if (lineCost == null) {
          linesWithoutCost++;
        } else {
          cost += lineCost;
        }

        final held = byProduct[line.productId];
        byProduct[line.productId] = TenantSalesItem(
          productId: line.productId,
          name: tenantProductLabel(line.name, line.sku),
          quantity: (held?.quantity ?? 0) + quantity,
          revenueMinor:
              (held?.revenueMinor ?? 0) +
              charged[line.productId]! -
              (offset?.returnedMinorByProduct[line.productId] ?? 0),
          costMinor: (held?.costMinor ?? 0) + (lineCost ?? 0),
          linesWithoutCost:
              (held?.linesWithoutCost ?? 0) + (lineCost == null ? 1 : 0),
        );
      }
    }

    final previousDaily = <String, int>{
      if (previous != null)
        for (final date in period.precedingComparable.businessDates) date: 0,
    };
    final previousWeekday = List<int>.filled(DateTime.daysPerWeek, 0);
    var previousRevenue = 0;
    var previousTransactions = 0;
    for (final sale in previous ?? const <TenantSale>[]) {
      final offset = previousReturnOffsets[sale.id];
      if (offset?.isFullyReturned == true) continue;
      previousTransactions++;
      final net = sale.totalMinor - (offset?.returnedMinor ?? 0);
      previousRevenue += net;
      previousDaily.update(
        sale.businessDate,
        (held) => held + net,
        ifAbsent: () => net,
      );
      previousWeekday[_weekdayIndex(sale.businessDate)] += net;
    }

    return TenantSalesAnalysis._(
      period: period,
      revenueMinor: revenue,
      previousRevenueMinor: previous == null ? null : previousRevenue,
      costMinor: cost,
      discountMinor: discount,
      transactions: transactions,
      previousTransactions: previous == null ? null : previousTransactions,
      linesWithoutCost: linesWithoutCost,
      lineCount: lineCount,
      itemsSold: itemsSold,
      dailyMinor: Map<String, int>.unmodifiable(daily),
      previousDailyMinor: Map<String, int>.unmodifiable(previousDaily),
      weekdayMinor: List<int>.unmodifiable(weekday),
      previousWeekdayMinor: List<int>.unmodifiable(previousWeekday),
      items: List<TenantSalesItem>.unmodifiable(
        byProduct.values.toList()
          ..sort((a, b) => b.revenueMinor.compareTo(a.revenueMinor)),
      ),
      tenders: List<TenantSalesTender>.unmodifiable(
        byTender.entries
            .map(
              (entry) => TenantSalesTender(
                tender: entry.key,
                minor: entry.value.minor,
                transactions: entry.value.count,
              ),
            )
            .toList()
          ..sort((a, b) => b.minor.compareTo(a.minor)),
      ),
      basketSizes: List<int>.unmodifiable(baskets..sort()),
      returnedMinor: returnedMinor,
      fullyReturnedSales: fullyReturnedSales,
      truncated: truncated,
      documentsRead: documentsRead,
    );
  }

  final TenantReportPeriod period;

  final int revenueMinor;

  /// The preceding comparable period's takings, or null where none was read.
  final int? previousRevenueMinor;

  /// What the goods cost, over the lines that recorded a cost.
  final int costMinor;

  final int discountMinor;
  final int transactions;
  final int? previousTransactions;

  /// How many sold lines carried no `unitCostMinor` at all.
  ///
  /// The `incompleteCostLineCount` discipline: the margin is printed, its
  /// denominator is stated, and the missing lines are counted rather than
  /// guessed at.
  final int linesWithoutCost;

  final int lineCount;
  final int itemsSold;

  /// Takings per business date, gaps included.
  final Map<String, int> dailyMinor;

  final Map<String, int> previousDailyMinor;

  /// Takings by day of the week, Monday first.
  final List<int> weekdayMinor;

  final List<int> previousWeekdayMinor;

  /// Every product sold, by takings, largest first.
  final List<TenantSalesItem> items;

  final List<TenantSalesTender> tenders;

  /// Units per sale, ascending, for the basket percentiles.
  final List<int> basketSizes;

  final int returnedMinor;

  /// How many sales came back in full.
  ///
  /// **The figure a transaction count comes down by**, which is not the same as
  /// the number of returns: a partly returned sale is still a transaction that
  /// happened, and counting it out would understate how busy the shop was.
  final int fullyReturnedSales;

  final bool truncated;
  final int documentsRead;

  /// Takings less the cost of the goods, over the lines that recorded one.
  int get marginMinor => revenueMinor - costMinor;

  /// Whether every sold line recorded what it cost.
  bool get isCostComplete => linesWithoutCost == 0;

  /// The share of lines that can be costed, for a sentence that qualifies a
  /// margin figure honestly.
  double get costCoverage =>
      lineCount == 0 ? 1 : (lineCount - linesWithoutCost) / lineCount;

  /// Margin as a share of takings, or null where nothing was sold.
  double? get marginRate =>
      revenueMinor == 0 ? null : marginMinor / revenueMinor;

  /// What was discounted as a share of what would otherwise have been taken.
  ///
  /// A control figure rather than a sales one: a discount rate that moves is a
  /// question about who is giving them away.
  double? get discountRate {
    final gross = revenueMinor + discountMinor;
    return gross == 0 ? null : discountMinor / gross;
  }

  /// Takings are already net of returns throughout the analysis.
  int get netRevenueMinor => revenueMinor;

  /// How far takings moved, or null where there is nothing to compare.
  double? get change {
    final was = previousRevenueMinor;
    if (was == null || was == 0) return null;
    return (revenueMinor - was) / was.abs();
  }

  /// The mean sale.
  int get averageSaleMinor =>
      transactions == 0 ? 0 : (revenueMinor / transactions).round();

  /// The middle basket, in units.
  int get medianBasket {
    if (basketSizes.isEmpty) return 0;
    return basketSizes[basketSizes.length ~/ 2];
  }

  /// The products that earned the most, rather than the ones that sold the
  /// most.
  ///
  /// **The report's central finding.** Products whose cost was never recorded
  /// are left out rather than ranked at full takings: an unknown margin is not
  /// a large one, and including them would put the worst-kept records at the
  /// top of a list about profitability.
  List<TenantSalesItem> get byMargin =>
      items.where((item) => item.marginMinor != null).toList()
        ..sort((a, b) => b.marginMinor!.compareTo(a.marginMinor!));

  /// The best seller by takings, or null where nothing sold.
  TenantSalesItem? get bestSeller => items.isEmpty ? null : items.first;

  /// The best earner by margin, or null where nothing could be costed.
  TenantSalesItem? get bestEarner {
    final ranked = byMargin;
    return ranked.isEmpty ? null : ranked.first;
  }

  /// Whether the best seller and the best earner are different products.
  ///
  /// The sentence this supports is the reason the section exists, so the
  /// condition for printing it is a field rather than a comparison a renderer
  /// has to remember to make.
  bool get sellerEarnerDiffer {
    final seller = bestSeller;
    final earner = bestEarner;
    return seller != null &&
        earner != null &&
        seller.productId != earner.productId;
  }

  /// The busiest trading day, or null where nothing was taken.
  String? get bestDay {
    if (revenueMinor == 0) return null;
    var best = dailyMinor.entries.first;
    for (final entry in dailyMinor.entries) {
      if (entry.value > best.value) best = entry;
    }
    return best.value == 0 ? null : best.key;
  }

  /// The weakest weekday the business actually traded on, Monday first.
  int? get weakestWeekday {
    final traded = <int>[
      for (var i = 0; i < weekdayMinor.length; i++)
        if (weekdayMinor[i] > 0) i,
    ];
    if (traded.isEmpty) return null;
    return traded.reduce((a, b) => weekdayMinor[b] < weekdayMinor[a] ? b : a);
  }

  /// Days in the period on which nothing was sold.
  int get quietDays => dailyMinor.values.where((minor) => minor == 0).length;

  static const List<String> weekdayNames = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Monday is 0, matching [weekdayNames].
  static int _weekdayIndex(String businessDate) =>
      DateTime.utc(
        int.parse(businessDate.substring(0, 4)),
        int.parse(businessDate.substring(5, 7)),
        int.parse(businessDate.substring(8, 10)),
      ).weekday -
      1;
}
