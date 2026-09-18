/// The old app's weekly reports page, as data.
///
/// **What this migrates and what it could not.** `lib/pos/reports.dart` built
/// one screen out of five metric cards, a seven-bar revenue chart, a top-items
/// list, a recent-transactions list and three filters. Every figure there was
/// summed on the device out of raw sale documents; here the sums come from
/// `getSalesComparison`, which is the server-side total this product already
/// trusts everywhere else - so the same page is drawn from a read that a
/// business with a year of sales can actually afford.
///
/// **Two of the old cards had no reading to migrate.** *Low stock* needs a
/// reorder level, and `test/dev/reachable_lib_test.dart` records the reorder
/// model as unreachable - `DESIGN_RULES.md` forbids drawing a control the code
/// does not support, so inventing one here would be inventing the number too.
/// *Shifts today* is real but is a different question from the week this page
/// is about, and answering it needs a second query whose "today" would have to
/// be filtered on the device. Both slots carry figures the week already holds:
/// the average sale, and the units sold.
library;

import '../checkout/checkout_draft.dart';
import '../sales/sale_history.dart';
import '../tenancy/tenant_session.dart';
import '../expenses/expense.dart';
import '../expenses/expense_repository.dart';
import 'net_profit.dart';
import 'device_sales_totals.dart';
import 'sales_totals.dart';

/// One Monday-to-Sunday week, named by how many weeks back it is.
///
/// **Monday-based and in business time, not device time.** The old page took
/// `DateTime.now().weekday`, which is the handset's idea of the day; every
/// figure on this page is keyed by the Nairobi business date the till stamps on
/// a sale, so the week has to be cut on the same boundary or a Sunday-evening
/// sale lands in a different week from the report that counts it.
final class TenantReportWeek {
  const TenantReportWeek._(this.offset, this._monday);

  /// The week containing [nowUtc], and [offset] weeks before it.
  factory TenantReportWeek.at(DateTime nowUtc, {int offset = 0}) {
    final business = nowUtc.toUtc().add(checkoutBusinessDayOffset);
    final today = DateTime.utc(business.year, business.month, business.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return TenantReportWeek._(offset, monday.add(Duration(days: offset * 7)));
  }

  /// 0 is the week in progress, -1 the one before it. Never positive: the page
  /// refuses to page forward past the current week.
  final int offset;

  final DateTime _monday;

  DateTime get monday => _monday;
  DateTime get sunday => _monday.add(const Duration(days: 6));

  bool get isCurrent => offset == 0;

  TenantReportWeek get previous =>
      TenantReportWeek._(offset - 1, _monday.subtract(const Duration(days: 7)));

  TenantReportWeek get next =>
      TenantReportWeek._(offset + 1, _monday.add(const Duration(days: 7)));

  /// The seven business dates this week covers, Monday first.
  List<String> get businessDates => <String>[
    for (var day = 0; day < 7; day++) _dateOf(_monday.add(Duration(days: day))),
  ];

  String get startBusinessDate => _dateOf(_monday);
  String get endBusinessDate => _dateOf(sunday);

  /// The dates that have actually happened, given [nowUtc].
  ///
  /// The totals callable refuses a future business date rather than answering
  /// an empty report, so a week in progress asks only for the days it has.
  List<String> elapsedBusinessDates(DateTime nowUtc) {
    final today = checkoutBusinessDate(nowUtc);
    return <String>[
      for (final date in businessDates)
        if (date.compareTo(today) <= 0) date,
    ];
  }

  /// The last day this week may be asked about, clamped to today.
  String endBusinessDateAt(DateTime nowUtc) {
    final today = checkoutBusinessDate(nowUtc);
    final end = endBusinessDate;
    return end.compareTo(today) > 0 ? today : end;
  }

  static String _dateOf(DateTime day) {
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '${day.year.toString().padLeft(4, '0')}-$month-$date';
  }
}

/// One product's share of a week, summed from the sale lines this device read.
final class TenantReportItem {
  const TenantReportItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.revenueMinor,
  });

  final String productId;
  final String name;
  final int quantity;
  final int revenueMinor;
}

/// Everything the weekly page draws, for one week and one set of filters.
final class TenantWeeklyReport {
  const TenantWeeklyReport({
    required this.week,
    required this.totals,
    required this.previousTotals,
    required this.revenueByWeekday,
    required this.topItems,
    required this.recentSales,
    required this.itemsSold,
    required this.scanWasTruncated,
    this.expenses,
  });

  final TenantReportWeek week;

  /// The week's own totals, summed from its seven days so that the header and
  /// the chart can never disagree.
  final TenantSalesTotals? totals;

  /// The week before, for the percentage each card carries. Null where it
  /// could not be read - a comparison is dropped rather than guessed.
  final TenantSalesTotals? previousTotals;

  /// Monday..Sunday revenue in major units, seven entries, zero-filled.
  final List<double> revenueByWeekday;

  final List<TenantReportItem> topItems;
  final List<TenantSale> recentSales;

  /// Units sold across the week, from the same pass that built [topItems].
  final int itemsSold;

  /// Whether the sale scan hit its cap, so [topItems] and [itemsSold] describe
  /// part of the week rather than all of it.
  ///
  /// **Carried rather than hidden.** A truncated top-ten that presents itself
  /// as the whole week is the kind of plausible-but-wrong figure
  /// `DESIGN_RULES.md` is about.
  final bool scanWasTruncated;

  /// What the business spent over the same week, or null where it was not
  /// read - by role, by wiring, or because the read failed.
  final TenantExpensePeriod? expenses;

  /// This week after everything the business spent, or null where either half
  /// is missing.
  ///
  /// Composed here so the card and any test ask the same question of the same
  /// object, rather than each assembling its own.
  TenantNetProfitReport? get netProfitReport {
    // **The returns-net gross figure, not the raw one.** Subtracting the
    // week's spending from a profit that still counts returned goods as sold
    // would take the right expenses off the wrong base.
    final gross = totals?.netOrGrossProfitReport;
    if (gross == null || expenses == null) return null;
    return TenantNetProfitReport.from(gross: gross, expenses: expenses);
  }

  /// Whether the figures on this week have had their returns taken out.
  ///
  /// False means the server did not send them, which is not the same as a
  /// week nothing came back on - a surface saying "net" has to be able to
  /// tell those apart.
  bool get netsReturns => totals?.hasNet ?? false;

  /// What came back over the week, or null where that is not known.
  double? get returnedSales {
    final net = totals?.net;
    if (net == null) return null;
    return (totals!.sales * 100 - net.sales * 100).round() / 100;
  }

  /// Whether there is any basis at all for the takings cards.
  ///
  /// **Asked before the figures are drawn, because zero is a real answer.** A
  /// week with no server or device totals has takings of *unknown*, not of
  /// nought, and the two must not be printed the same way.
  bool get hasTakings => totals != null;

  // Net of returns wherever the server said so, and the gross figure where it
  // did not - which is what every surface showed before it did.
  double get sales => totals?.netOrGrossSales ?? 0;
  int get transactions => totals?.netOrGrossTransactions ?? 0;

  /// The week's takings divided by the sales that produced them.
  double get averageSale => transactions == 0 ? 0 : sales / transactions;

  double? get previousAverageSale {
    final previous = previousTotals;
    if (previous == null || previous.netOrGrossTransactions == 0) return null;
    return previous.netOrGrossSales / previous.netOrGrossTransactions;
  }

  /// The share of this week over the one before, or null where there is
  /// nothing to compare against.
  static double? change(double current, double? previous) {
    if (previous == null || previous == 0) return null;
    return (current - previous) / previous * 100;
  }
}

/// Reads one week for one set of filters.
///
/// **Eight requests, and the shape is deliberate.** Seven single-day totals -
/// which is what the chart needs anyway - are summed into the week's own
/// figures, so the header can never contradict the bars behind it. The eighth
/// is one range query for the week before, which is the only thing the
/// comparison needs. The old page did all of this by downloading every sale.
final class TenantWeeklyReportLoader {
  TenantWeeklyReportLoader({
    required TenantSession session,
    required SalesTotalsCallable callable,
    required TenantSaleHistoryRepository sales,
    TenantExpenseRepository? expenses,
    DateTime Function()? clock,
    this.recentSaleCount = 8,
    this.topItemCount = 5,
    this.saleScanCap = 300,
  }) : _session = session,
       _gateway = TenantSalesTotalsGateway(
         session: session,
         callable: callable,
         clock: clock,
       ),
       _sales = sales,
       _expenses = expenses,
       _clock = clock ?? _utcNow;

  TenantWeeklyReportLoader.device({
    required TenantSession session,
    required TenantSaleHistoryRepository sales,
    TenantExpenseRepository? expenses,
    DateTime Function()? clock,
    this.recentSaleCount = 8,
    this.topItemCount = 5,
    this.saleScanCap = 300,
  }) : _session = session,
       _gateway = TenantSalesTotalsGateway(
         session: session,
         callable: const _NeverWeeklyTotalsCallable(),
         clock: clock,
       ),
       _sales = sales,
       _expenses = expenses,
       _clock = clock ?? _utcNow;

  final TenantSession _session;
  final TenantSalesTotalsGateway _gateway;
  final TenantSaleHistoryRepository _sales;

  /// Reads what the business spent over the same week, or null where this
  /// session may not be shown it.
  final TenantExpenseRepository? _expenses;

  final DateTime Function() _clock;

  final int recentSaleCount;
  final int topItemCount;

  /// How many sales the item roll-up will read before it stops.
  ///
  /// **A cap rather than a full scan, and the report says when it bites.** The
  /// old page held every sale of the period in memory; a busy week here can be
  /// thousands, and paging all of them to name five products would cost more
  /// reads than the rest of the screen put together.
  final int saleScanCap;

  bool get canRead =>
      TenantSalesTotalsGateway.canReadInSession(_session) &&
      _session.canAccess(allowedRoles: TenantSaleHistoryRepository.reportRoles);

  Future<TenantWeeklyReport> load(
    TenantReportWeek week, {
    String? soldById,
    String? categoryId,
  }) async {
    final now = _clock().toUtc();
    final elapsed = week.elapsedBusinessDates(now).toList(growable: false);
    // **Started together rather than one after another, since 2026-08-27.**
    // This was a `for` loop that awaited the callable once per elapsed day,
    // then the previous week, then the sale scan - up to nine round trips end
    // to end, with the page showing nothing until the last of them landed. A
    // week opened on a Sunday paid for all nine before it drew a figure. They
    // do not depend on each other and never did.
    //
    // **One `Future.wait` over the lot, and that is deliberate.** Awaiting
    // them one at a time after starting them all is what strands a rejection:
    // if an early day fails, the ones still outstanding have nobody left to
    // catch them and Dart reports them as unhandled. `Future.wait` attaches to
    // every future before any of them can complete.
    //
    // The failure it reports is the first by *completion* rather than the
    // first by date, where the loop reported the earliest day. Both take the
    // page, so what a person sees is unchanged; a log naming a different day
    // of the same broken week is the whole of the difference.
    final pending = <Future<Object?>>[
      // **Each day swallows its own refusal, since 2026-08-28.** These are
      // callables, and a callable has no offline answer; before this, one of
      // them failing threw out of `Future.wait` and took the whole page - the
      // chart, the best sellers, the recent sales and the expense range, every
      // one of which is a Firestore read that was sitting in this device's
      // cache the entire time. The two members of this batch that already
      // swallowed their own failures said as much; the days were simply never
      // brought into line with them.
      for (final date in elapsed)
        _dayTotals(date: date, soldById: soldById, categoryId: categoryId),
      // Its own failure is already swallowed into a null - a missing
      // comparison, not a missing page - so it can share this list safely.
      _previousWeekTotals(
        week,
        now: now,
        soldById: soldById,
        categoryId: categoryId,
      ),
      if (elapsed.isNotEmpty)
        _rollUpItems(
          week,
          now: now,
          soldById: soldById,
          categoryId: categoryId,
        ),
      // **In the same batch, and it is the only member of it that is not a
      // callable.** A Firestore range walk serves from the offline cache, so
      // joining the batch costs the week nothing and the net figure lands with
      // the gross one. Its failure is swallowed into a null, like the previous
      // week's, so it can share this list safely.
      _weekExpenses(
        week,
        now: now,
        soldById: soldById,
        categoryId: categoryId,
      ),
    ];
    final settled = await Future.wait(pending);
    final byDate = <String, TenantSalesTotals>{
      for (var index = 0; index < elapsed.length; index++)
        if (settled[index] case final TenantSalesTotals day)
          elapsed[index]: day,
    };
    final previous = settled[elapsed.length] as TenantSalesTotals?;
    final roll = elapsed.isEmpty
        ? const _ItemRoll.empty()
        : settled[elapsed.length + 1]! as _ItemRoll;
    final expenses = settled.last as TenantExpensePeriod?;
    // **The week's total is the server's only when every day of it answered.**
    // Summing the four days that landed and presenting it as the week would
    // understate the takings without saying so, which is the one failure this
    // page must not have. A partial answer is no answer; the separate device
    // loader remains visible until a complete authoritative result arrives.
    final complete = byDate.length == elapsed.length && byDate.isNotEmpty;
    return TenantWeeklyReport(
      week: week,
      totals: complete ? _sum(byDate.values) : null,
      previousTotals: previous,
      revenueByWeekday: <double>[
        for (final date in week.businessDates)
          byDate[date]?.netOrGrossSales ??
              (roll.truncated ? 0 : (roll.revenueByDate[date] ?? 0) / 100),
      ],
      topItems: roll.top(topItemCount),
      recentSales: roll.recent.take(recentSaleCount).toList(growable: false),
      itemsSold: roll.itemsSold,
      scanWasTruncated: roll.truncated,
      expenses: expenses,
    );
  }

  /// Reads the same week without starting a callable. Every totals query is
  /// answered by the cache/outbox aggregator; comparisons are intentionally
  /// absent until the authoritative branch arrives.
  Future<TenantWeeklyReport> loadDevice(
    TenantReportWeek week, {
    required TenantDeviceSalesAggregator aggregator,
    String? soldById,
    String? categoryId,
  }) async {
    final now = _clock().toUtc();
    final elapsed = week.elapsedBusinessDates(now).toList(growable: false);
    if (elapsed.isEmpty) {
      return TenantWeeklyReport(
        week: week,
        totals: null,
        previousTotals: null,
        revenueByWeekday: List<double>.filled(7, 0),
        topItems: const <TenantReportItem>[],
        recentSales: const <TenantSale>[],
        itemsSold: 0,
        scanWasTruncated: false,
      );
    }
    final totalsFuture = aggregator.load(
      aggregator.createRangeQuery(
        startBusinessDate: week.startBusinessDate,
        endBusinessDate: week.endBusinessDateAt(now),
        soldById: soldById,
        categoryId: categoryId,
      ),
    );
    final dayFutures = <Future<TenantDeviceSalesTotals>>[
      for (final date in elapsed)
        aggregator.load(
          aggregator.createBusinessDateQuery(
            businessDate: date,
            soldById: soldById,
            categoryId: categoryId,
          ),
        ),
    ];
    final settled = await Future.wait<Object?>(<Future<Object?>>[
      totalsFuture,
      Future.wait<TenantDeviceSalesTotals>(dayFutures),
      _rollUpItems(
        week,
        now: now,
        soldById: soldById,
        categoryId: categoryId,
      ),
      _weekExpenses(
        week,
        now: now,
        soldById: soldById,
        categoryId: categoryId,
      ),
    ]);
    final totalResult = settled[0]! as TenantDeviceSalesTotals;
    final totals = totalResult.totals;
    if (totals == null) {
      throw StateError(
        totalResult.truncated
            ? 'device_sales_truncated'
            : 'device_sales_conflicting_evidence',
      );
    }
    final dayResults = settled[1]! as List<TenantDeviceSalesTotals>;
    if (dayResults.any((result) => result.totals == null)) {
      throw StateError('device_sales_day_unavailable');
    }
    final byDate = <String, TenantSalesTotals>{
      for (var index = 0; index < elapsed.length; index++)
        elapsed[index]: dayResults[index].totals!,
    };
    final roll = settled[2]! as _ItemRoll;
    return TenantWeeklyReport(
      week: week,
      totals: totals,
      previousTotals: null,
      revenueByWeekday: <double>[
        for (final date in week.businessDates)
          byDate[date]?.netOrGrossSales ?? 0,
      ],
      topItems: roll.top(topItemCount),
      recentSales: roll.recent.take(recentSaleCount).toList(growable: false),
      itemsSold: roll.itemsSold,
      scanWasTruncated: roll.truncated,
      expenses: settled[3] as TenantExpensePeriod?,
    );
  }

  /// One day's totals, or null where the server could not be asked.
  ///
  /// The same treatment [_previousWeekTotals] and [_weekExpenses] already give
  /// their own refusals: what goes missing is this day, not the page.
  Future<TenantSalesTotals?> _dayTotals({
    required String date,
    String? soldById,
    String? categoryId,
  }) async {
    try {
      return await _gateway.load(
        _gateway.createBusinessDateQuery(
          businessDate: date,
          soldById: soldById,
          categoryId: categoryId,
        ),
      );
    } on TenantSalesTotalsException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// What the business spent over this week, or null where it could not be
  /// read.
  ///
  /// **A failure here drops the net figure rather than the page**, exactly as
  /// [_previousWeekTotals] drops the comparison: every gross figure on the
  /// report still stands, and what goes missing is the one card that depends
  /// on this.
  Future<TenantExpensePeriod?> _weekExpenses(
    TenantReportWeek week, {
    required DateTime now,
    String? soldById,
    String? categoryId,
  }) async {
    final expenses = _expenses;
    if (expenses == null) return null;
    // **Never read for a filtered week, and that is a correctness rule rather
    // than a saving.** An expense belongs to the business and to a date; it
    // belongs to no colleague and to no product category. Subtracting the whole
    // shop's rent from one cashier's takings, or from the gross profit of one
    // category, produces a number that looks like net profit and is not one.
    // `SalesTotalsView.expenses` has refused this since the totals page learnt
    // to read spending; the week was simply never brought into line with it.
    if (soldById != null || categoryId != null) return null;
    try {
      return await expenses.readRange(
        startDate: week.startBusinessDate,
        endDate: week.endBusinessDateAt(now),
      );
    } catch (_) {
      return null;
    }
  }

  /// The week before, or null where it could not be read.
  ///
  /// **A failure here drops the comparison rather than the page.** Every card
  /// still has its own figure; what goes missing is the arrow beside it, which
  /// is exactly the part that depends on this.
  Future<TenantSalesTotals?> _previousWeekTotals(
    TenantReportWeek week, {
    required DateTime now,
    String? soldById,
    String? categoryId,
  }) async {
    final before = week.previous;
    try {
      return await _gateway.load(
        _gateway.createRangeQuery(
          startBusinessDate: before.startBusinessDate,
          endBusinessDate: _comparisonEnd(week, before, now: now),
          soldById: soldById,
          categoryId: categoryId,
        ),
      );
    } on TenantSalesTotalsException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// The last day of [before] this comparison may read.
  ///
  /// **A running week is compared against the same days of the week before it,
  /// not against the whole of it.** The current week totals only the business
  /// dates that have elapsed, and `endBusinessDateAt` does not clamp a week
  /// already finished - so on a Wednesday this page was putting Monday to
  /// Wednesday beside a full Monday to Sunday and labelling the result *vs last
  /// week*. Three days against seven reads as a collapse in trade to anybody
  /// who has not gone looking for the reason, and it is at its most wrong on a
  /// Monday, when one day is held up against seven.
  ///
  /// A week that has finished is compared whole against whole, as it always
  /// was: there is nothing partial about either side of that.
  String _comparisonEnd(
    TenantReportWeek week,
    TenantReportWeek before, {
    required DateTime now,
  }) {
    if (!week.isCurrent) return before.endBusinessDateAt(now);
    final elapsed = week.elapsedBusinessDates(now).length;
    // A week whose first day has not arrived has nothing to compare; the whole
    // previous week is the only honest answer and the caller draws no arrow
    // from an empty current side anyway.
    if (elapsed < 1 || elapsed > 7) return before.endBusinessDateAt(now);
    return before.businessDates[elapsed - 1];
  }

  /// Sums the single-day answers into the week's own totals.
  TenantSalesTotals _sum(Iterable<TenantSalesTotals> days) {
    var sales = 0.0;
    var profit = 0.0;
    var transactions = 0;
    var incomplete = 0;
    var netSales = 0.0;
    var netProfit = 0.0;
    var netTransactions = 0;
    var netIncomplete = 0;
    var returnsScanned = 0;
    // **The week nets returns only when every one of its days did.** A week
    // summed from six netted days and one gross one is neither figure, and it
    // would be wrong in the direction that flatters - so a single day from an
    // older server leaves the whole week reporting gross, and saying so.
    var netKnown = true;
    for (final day in days) {
      sales += day.sales;
      profit += day.profit;
      transactions += day.transactions;
      incomplete += day.incompleteCostLineCount;
      final net = day.net;
      if (net == null) {
        netKnown = false;
        continue;
      }
      netSales += net.sales;
      netProfit += net.profit;
      netTransactions += net.transactions;
      netIncomplete += net.incompleteCostLineCount;
      returnsScanned += net.returnsScanned;
    }
    return TenantSalesTotals.summed(
      query: days.first.query,
      sales: sales,
      profit: profit,
      transactions: transactions,
      incompleteCostLineCount: incomplete,
      net: netKnown
          ? TenantSalesNetTotals.summed(
              sales: netSales,
              profit: netProfit,
              transactions: netTransactions,
              incompleteCostLineCount: netIncomplete,
              returnsScanned: returnsScanned,
            )
          : null,
    );
  }

  /// Pages the week's sales once, and gets both lists out of the one pass.
  ///
  /// **[categoryId] is applied here rather than in the query, because there is
  /// no query that could apply it.** `loadReport` pages by business date and
  /// colleague; a category lives on the sale *line*, and a sale is not indexed
  /// by the categories it happens to contain. The lines are already in hand, so
  /// the filter costs a comparison per line and no extra read.
  ///
  /// The rule it applies is the server's own, in `saleContribution`: a sale
  /// with no line in the category did not happen as far as that category is
  /// concerned, and is left out of every list - not merely emptied of its
  /// lines. Before this, the totals and the chart honoured the filter while the
  /// best sellers, the item count and the recent sales quietly did not, so the
  /// page contradicted the filter printed at the top of it.
  Future<_ItemRoll> _rollUpItems(
    TenantReportWeek week, {
    required DateTime now,
    String? soldById,
    String? categoryId,
  }) async {
    final quantities = <String, int>{};
    final revenue = <String, int>{};
    final names = <String, String>{};
    final recent = <TenantSale>[];
    final revenueByDate = <String, int>{};
    var scanned = 0;
    var truncated = false;
    var itemsSold = 0;
    String? cursor;
    try {
      while (scanned < saleScanCap) {
        final page = await _sales.loadReport(
          startBusinessDate: week.startBusinessDate,
          endBusinessDate: week.endBusinessDateAt(now),
          selectedStaffId: soldById,
          pageSize: 50,
          cursor: cursor,
        );
        for (final sale in page.items) {
          scanned++;
          final lines = categoryId == null
              ? sale.lines
              : <TenantSaleLine>[
                  for (final line in sale.lines)
                    if (line.categoryId == categoryId) line,
                ];
          // Counted against the scan cap either way - the read happened - but
          // present on the page only if it held anything in the category.
          if (lines.isEmpty) continue;
          // **The filtered lines, not the sale's own total.** Under a category
          // the chart has to draw the same money the totals add up, and the
          // rest of the sale belongs to another category's day.
          revenueByDate[sale.businessDate] =
              (revenueByDate[sale.businessDate] ?? 0) +
              (categoryId == null
                  ? sale.totalMinor
                  : lines.fold<int>(
                      0,
                      (total, line) => total + line.lineTotalMinor,
                    ));
          if (recent.length < recentSaleCount) recent.add(sale);
          for (final line in lines) {
            quantities[line.productId] =
                (quantities[line.productId] ?? 0) + line.quantity;
            revenue[line.productId] =
                (revenue[line.productId] ?? 0) + line.lineTotalMinor;
            names[line.productId] = line.name;
            itemsSold += line.quantity;
          }
        }
        cursor = page.nextCursor;
        if (cursor == null) break;
        if (scanned >= saleScanCap) truncated = true;
      }
    } on TenantSaleException {
      // The lists go missing; the figures above them never depended on this.
      return const _ItemRoll.empty();
    } on StateError {
      // No sales-report reader is composed in. The same treatment.
      return const _ItemRoll.empty();
    }
    return _ItemRoll(
      quantities: quantities,
      revenue: revenue,
      names: names,
      recent: recent,
      itemsSold: itemsSold,
      truncated: truncated,
      revenueByDate: revenueByDate,
    );
  }
}

final class _NeverWeeklyTotalsCallable implements SalesTotalsCallable {
  const _NeverWeeklyTotalsCallable();

  @override
  Future<Object?> call(Map<String, Object?> payload) =>
      throw StateError('A device weekly report cannot invoke a callable.');
}

/// The one pass over a week's sales, before it is sorted into two lists.
final class _ItemRoll {
  const _ItemRoll({
    required this.quantities,
    required this.revenue,
    required this.names,
    required this.recent,
    required this.itemsSold,
    required this.truncated,
    this.revenueByDate = const <String, int>{},
  });

  const _ItemRoll.empty()
    : quantities = const <String, int>{},
      revenue = const <String, int>{},
      names = const <String, String>{},
      recent = const <TenantSale>[],
      itemsSold = 0,
      truncated = false,
      revenueByDate = const <String, int>{};

  final Map<String, int> quantities;
  final Map<String, int> revenue;
  final Map<String, String> names;
  final List<TenantSale> recent;
  final int itemsSold;
  final bool truncated;

  /// The same takings split by business date, so the chart has a bar per day
  /// without a second pass over the same records.
  final Map<String, int> revenueByDate;

  /// The best sellers by revenue, which is what the old page ordered by.
  List<TenantReportItem> top(int count) {
    final items = <TenantReportItem>[
      for (final entry in revenue.entries)
        TenantReportItem(
          productId: entry.key,
          name: names[entry.key] ?? entry.key,
          quantity: quantities[entry.key] ?? 0,
          revenueMinor: entry.value,
        ),
    ]..sort((a, b) => b.revenueMinor.compareTo(a.revenueMinor));
    return items.take(count).toList(growable: false);
  }
}

DateTime _utcNow() => DateTime.now().toUtc();
