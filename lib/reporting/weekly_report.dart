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

  double get sales => totals?.sales ?? 0;
  int get transactions => totals?.transactions ?? 0;

  /// The week's takings divided by the sales that produced them.
  double get averageSale =>
      transactions == 0 ? 0 : (totals?.sales ?? 0) / transactions;

  double? get previousAverageSale {
    final previous = previousTotals;
    if (previous == null || previous.transactions == 0) return null;
    return previous.sales / previous.transactions;
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
       _clock = clock ?? _utcNow;

  final TenantSession _session;
  final TenantSalesTotalsGateway _gateway;
  final TenantSaleHistoryRepository _sales;
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
      for (final date in elapsed)
        _gateway.load(
          _gateway.createBusinessDateQuery(
            businessDate: date,
            soldById: soldById,
            categoryId: categoryId,
          ),
        ),
      // Its own failure is already swallowed into a null - a missing
      // comparison, not a missing page - so it can share this list safely.
      _previousWeekTotals(
        week,
        now: now,
        soldById: soldById,
        categoryId: categoryId,
      ),
      if (elapsed.isNotEmpty) _rollUpItems(week, now: now, soldById: soldById),
    ];
    final settled = await Future.wait(pending);
    final byDate = <String, TenantSalesTotals>{
      for (var index = 0; index < elapsed.length; index++)
        elapsed[index]: settled[index]! as TenantSalesTotals,
    };
    final previous = settled[elapsed.length] as TenantSalesTotals?;
    final roll = elapsed.isEmpty
        ? const _ItemRoll.empty()
        : settled[elapsed.length + 1]! as _ItemRoll;
    return TenantWeeklyReport(
      week: week,
      totals: byDate.isEmpty ? null : _sum(byDate.values),
      previousTotals: previous,
      revenueByWeekday: <double>[
        for (final date in week.businessDates) byDate[date]?.sales ?? 0,
      ],
      topItems: roll.top(topItemCount),
      recentSales: roll.recent.take(recentSaleCount).toList(growable: false),
      itemsSold: roll.itemsSold,
      scanWasTruncated: roll.truncated,
    );
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
          endBusinessDate: before.endBusinessDateAt(now),
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

  /// Sums the single-day answers into the week's own totals.
  TenantSalesTotals _sum(Iterable<TenantSalesTotals> days) {
    var sales = 0.0;
    var profit = 0.0;
    var transactions = 0;
    var incomplete = 0;
    for (final day in days) {
      sales += day.sales;
      profit += day.profit;
      transactions += day.transactions;
      incomplete += day.incompleteCostLineCount;
    }
    return TenantSalesTotals.summed(
      query: days.first.query,
      sales: sales,
      profit: profit,
      transactions: transactions,
      incompleteCostLineCount: incomplete,
    );
  }

  /// Pages the week's sales once, and gets both lists out of the one pass.
  Future<_ItemRoll> _rollUpItems(
    TenantReportWeek week, {
    required DateTime now,
    String? soldById,
  }) async {
    final quantities = <String, int>{};
    final revenue = <String, int>{};
    final names = <String, String>{};
    final recent = <TenantSale>[];
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
          if (recent.length < recentSaleCount) recent.add(sale);
          for (final line in sale.lines) {
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
    );
  }
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
  });

  const _ItemRoll.empty()
    : quantities = const <String, int>{},
      revenue = const <String, int>{},
      names = const <String, String>{},
      recent = const <TenantSale>[],
      itemsSold = 0,
      truncated = false;

  final Map<String, int> quantities;
  final Map<String, int> revenue;
  final Map<String, String> names;
  final List<TenantSale> recent;
  final int itemsSold;
  final bool truncated;

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
