import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../checkout/checkout_draft.dart';
import '../checkout/checkout_receipt.dart';
import '../checkout/checkout_tender.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import 'profit_report.dart';
import '../observability/app_telemetry.dart';

/// Narrow callable boundary for the server's `getSalesComparison`.
///
/// The server name is historical. The handler answers for exactly one period -
/// its response carries a single `previous` block and nothing to compare it
/// with - so everything on this side calls it what it is: the totals for a
/// stretch of days. The wire field names stay as the server declared them.
abstract interface class SalesTotalsCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `getSalesComparison`.
final class FirebaseSalesTotalsCallable implements SalesTotalsCallable {
  FirebaseSalesTotalsCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// How long a shop waits for a figure before being told it cannot be had.
  ///
  /// **The plugin's own default is sixty seconds, and that is the wait this
  /// names.** Nothing in this app had ever passed [HttpsCallableOptions], so
  /// every callable inherited a minute - and a minute is not a timeout on a
  /// counter, it is a hang. The weekly report asks for one of these per elapsed
  /// day, so a week opened on a dead network spent that minute before it could
  /// say so.
  ///
  /// **Eight seconds because the alternative is already drawn.** Since the
  /// pages around this read from the device while the server is deciding, a
  /// deadline is not a choice between a figure and nothing - it is a choice
  /// between a figure and the copy already on screen. Long enough for a slow
  /// but working connection, short enough that a broken one is reported while
  /// somebody is still looking at the screen.
  ///
  /// [TenantSalesTotalsGateway.load] has always caught [TimeoutException] into
  /// `unavailable`. Until this, that catch could never fire.
  static const Duration deadline = Duration(seconds: 8);

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await traceServerCall(
      'getSalesComparison',
      () => _functions
          .httpsCallable(
            'getSalesComparison',
            options: HttpsCallableOptions(timeout: deadline),
          )
          .call<Object?>(payload),
    );
    return result.data;
  }
}

/// The stretches of business days this surface may ask for.
///
/// Fixed choices rather than free dates. The server accepts up to 366 days and
/// refuses a period holding more than [TenantSalesTotals.maximumTransactions]
/// sales, so an arbitrary range is a refusal waiting to happen; these four all
/// answer a question somebody actually asks at a counter.
enum TenantSalesPeriod {
  today(1, 'Today'),
  last7Days(7, 'Last 7 days'),
  last30Days(30, 'Last 30 days'),
  last90Days(90, 'Last 90 days');

  const TenantSalesPeriod(this.days, this.label);

  /// How many business days the period covers, today included.
  final int days;
  final String label;
}

/// Whose sales one request covers.
///
/// Derived from the query rather than chosen: a caller names a member, and the
/// scope is what naming that member turned out to mean.
enum TenantSalesScope {
  /// Every sale the business recorded in the period.
  everyone,

  /// Only sales the signed-in member recorded.
  mine,

  /// Only sales one named colleague recorded.
  oneMember,
}

/// Provenance of a totals figure currently shown to the user.
enum TenantSalesTotalsBasis { device, server }

/// Why the server did not answer.
///
/// Reading is repeatable, so unlike the reconciliation request there is no
/// ambiguous outcome to carry: a failed read left nothing behind and asking
/// again is always safe.
enum TenantSalesTotalsFailure {
  /// The session may not read business-wide revenue, or its membership ended.
  forbidden,

  /// The period holds more sales than the server will add up in one answer.
  periodTooLarge,

  /// The server rejected the request as malformed.
  invalidRequest,

  /// A stored sale amount was outside the range the server can total.
  unusableSaleData,

  /// The server could not be reached, or failed while answering.
  unavailable,

  /// Refused for a reason this client does not model.
  refused,
}

/// Raised when a period's totals could not be read.
final class TenantSalesTotalsException implements Exception {
  const TenantSalesTotalsException(this.failure);

  final TenantSalesTotalsFailure failure;

  /// The failure, as the code telemetry classifies by. Without it an offline
  /// read is filed under the class name as `unexpected`, and every till that
  /// opens its home with no signal reports an error.
  String get code => failure.name;

  @override
  String toString() => 'TenantSalesTotalsException(${failure.name})';
}

/// One validated request for one business, period, and scope.
///
/// The dates are resolved once, when the query is created, so the answer can be
/// reconciled against the exact range that was asked for rather than against a
/// range recomputed from a clock that has since moved.
final class TenantSalesTotalsQuery {
  const TenantSalesTotalsQuery._({
    required this.tenantId,
    required this.period,
    required this.scope,
    required this.startDate,
    required this.endDate,
    required this.soldById,
    required this.categoryId,
  });

  /// The business the query was created against. The gateway refuses a query
  /// naming another, so a session change cannot resend it elsewhere.
  final String tenantId;

  final TenantSalesPeriod period;
  final TenantSalesScope scope;

  /// Inclusive `yyyy-MM-dd` business dates, in the same Africa/Nairobi business
  /// day the checkout stamps on every sale.
  final String startDate;
  final String endDate;

  /// The member whose sales are counted, or `null` for the whole business.
  final String? soldById;

  /// The category whose lines are counted, or `null` for every line.
  ///
  /// A category changes what the figure *means*, not just how much of it there
  /// is: the handler sums the matching lines instead of the recorded sale
  /// totals, and skips a sale that holds no matching line at all.
  final String? categoryId;

  /// Whether this query asks for one category's lines rather than whole sales.
  bool get isCategoryFiltered => categoryId != null;

  Map<String, Object?> toPayload() => <String, Object?>{
    'tenantId': tenantId,
    'previousStartDate': startDate,
    'previousEndDate': endDate,
    if (soldById != null) 'soldById': soldById,
    if (categoryId != null) 'categoryId': categoryId,
  };
}

/// One bucket of a period's takings: what was taken, over how many sales.
final class TenantSalesTenderTotals {
  const TenantSalesTenderTotals({
    required this.sales,
    required this.transactions,
  });

  /// Major-unit takings in this bucket, on the same basis as
  /// [TenantSalesTotals.sales] - whole sales, or one category's lines.
  final double sales;

  final int transactions;

  bool get isEmpty => transactions == 0;
}

/// How a period's takings split across the ways they were paid for.
///
/// The split is checked against the total it claims to describe rather than
/// trusted: the counts must sum to the answer's own transaction count and the
/// amounts to its own takings, exactly, in whole minor units. A split that does
/// not add up is not a smaller version of the truth - it is a different figure
/// wearing the same label, on the one surface an owner reads takings from.
///
/// The bucket set is closed. An unknown bucket is refused rather than ignored,
/// because ignoring one would silently report less money than was taken.
final class TenantSalesTenderBreakdown {
  const TenantSalesTenderBreakdown._({
    required this.recorded,
    required this.unrecorded,
    required this.unrecognised,
  });

  /// Decodes the server's `byTender`, or returns `null` when it sent none.
  ///
  /// Absent is not a failure: a server that does not report a split is a server
  /// this surface simply shows no split for, and the figure the manager came
  /// for is unaffected. Present and wrong *is* a failure.
  static TenantSalesTenderBreakdown? tryDecode(
    Object? value, {
    required double sales,
    required int transactions,
  }) {
    if (value == null) return null;
    final data = _strictMap(value, 'byTender');
    final expected = <String>{
      ...checkoutTenderWireValues,
      unrecordedBucket,
      unrecognisedBucket,
    };
    if (data.keys.toSet().length != data.length ||
        !data.keys.toSet().containsAll(expected) ||
        data.length != expected.length) {
      throw const FormatException(
        'getSalesComparison returned an unexpected set of tender buckets.',
      );
    }
    final buckets = <String, TenantSalesTenderTotals>{
      for (final key in expected) key: _bucket(data[key], key),
    };
    var countedTransactions = 0;
    var countedMinor = 0;
    for (final bucket in buckets.values) {
      countedTransactions += bucket.transactions;
      // Compared in whole minor units, the way the server adds them: comparing
      // doubles would need a tolerance that could hide a real disagreement.
      countedMinor += reportingMinorUnits(bucket.sales);
    }
    if (countedTransactions != transactions ||
        countedMinor != reportingMinorUnits(sales)) {
      throw const FormatException(
        'getSalesComparison returned a tender split that does not add up to '
        'the totals it accompanies.',
      );
    }
    return TenantSalesTenderBreakdown._(
      recorded: <CheckoutTender, TenantSalesTenderTotals>{
        for (final tender in CheckoutTender.values)
          tender: buckets[tender.wireValue]!,
      },
      unrecorded: buckets[unrecordedBucket]!,
      unrecognised: buckets[unrecognisedBucket]!,
    );
  }

  /// Builds the same closed, reconciled bucket set from device-side minor
  /// units. It deliberately passes through [tryDecode], keeping one integrity
  /// check for server and local answers.
  static TenantSalesTenderBreakdown fromDeviceMinorUnits({
    required Map<String, int> salesMinor,
    required Map<String, int> transactions,
    required int totalSalesMinor,
    required int totalTransactions,
  }) {
    final expected = <String>{
      ...checkoutTenderWireValues,
      unrecordedBucket,
      unrecognisedBucket,
    };
    if (salesMinor.keys.toSet().length != expected.length ||
        transactions.keys.toSet().length != expected.length ||
        !salesMinor.keys.toSet().containsAll(expected) ||
        !transactions.keys.toSet().containsAll(expected)) {
      throw const FormatException('Device tender buckets are incomplete.');
    }
    return tryDecode(
      <String, Object?>{
        for (final bucket in expected)
          bucket: <String, Object?>{
            'sales': salesMinor[bucket]! / 100,
            'transactions': transactions[bucket]!,
          },
      },
      sales: totalSalesMinor / 100,
      transactions: totalTransactions,
    )!;
  }

  /// The server's bucket for a sale carrying no tender at all.
  static const String unrecordedBucket = 'unrecorded';

  /// The server's bucket for a sale carrying a tender nothing here models.
  static const String unrecognisedBucket = 'other';

  /// One entry per modelled payment method, always all three.
  final Map<CheckoutTender, TenantSalesTenderTotals> recorded;

  /// Sales written before payment methods were captured at all.
  ///
  /// A statement about the record rather than about the payment: these are
  /// schema v1 sales, and they are never presented as unpaid.
  final TenantSalesTenderTotals unrecorded;

  /// Sales naming a payment method this app does not model.
  ///
  /// Kept separate from [unrecorded] because it is a different fact: something
  /// wrote a tender nothing here recognises, which is a data problem rather
  /// than history. Their money is still inside the total, and the surface says
  /// so instead of quietly dropping it.
  final TenantSalesTenderTotals unrecognised;

  /// Whether any sale in the period named a payment method this app models.
  bool get hasRecordedTenders =>
      recorded.values.any((totals) => !totals.isEmpty);

  static TenantSalesTenderTotals _bucket(Object? value, String field) {
    final data = _strictMap(value, 'byTender.$field');
    return TenantSalesTenderTotals(
      sales: _requiredNonNegativeNumber(data, 'sales'),
      transactions: _requiredCount(data, 'transactions'),
    );
  }
}

/// Strictly decoded totals for one period.
///
/// The response is reconciled against the query it answers. Without a category
/// the server counts one transaction per sale it read, so the two counts must
/// agree exactly; with one it skips a sale holding no matching line, so it may
/// count fewer but can never count more than it read. Either way a count the
/// query cannot explain describes some other request, and it is refused rather
/// than shown - this is the surface an owner reads takings from.
/// One period's takings with its returns taken back out.
///
/// **Carried beside the gross figures rather than replacing them**, because
/// `TenantSalesTotals.fromCallable` refuses an unfiltered answer whose
/// `transactions` disagrees with `scannedTransactions`. Netting a fully
/// returned sale out of that count in place would break the identity on every
/// installed client and blank the report rather than merely date it. So the
/// server sends both and this holds the second.
///
/// Null on the outer object means the server did not send them - an older
/// deployment, which reported gross and is not wrong, only older.
final class TenantSalesNetTotals {
  const TenantSalesNetTotals._({
    required this.sales,
    required this.profit,
    required this.transactions,
    required this.incompleteCostLineCount,
    required this.returnsScanned,
    required this.tenderBreakdown,
  });

  /// Takings after returns.
  final double sales;

  /// Profit after both the cost of the goods sold and the returns.
  ///
  /// **Cost comes back with the revenue.** Netting takings alone would drive
  /// the cost this figure implies - takings minus profit - downward and, on a
  /// low-margin period with a large return, negative; `TenantProfitReport`
  /// reads that as impossible and withholds the margin.
  final double profit;

  /// Sales that still happened. A fully returned one no longer did.
  final int transactions;

  final int incompleteCostLineCount;

  /// How many return documents the period held.
  final int returnsScanned;

  final TenantSalesTenderBreakdown? tenderBreakdown;

  /// The same question `TenantSalesTotals.profitReport` answers, of the net
  /// figures - so a surface showing net profit applies the same trust rule.
  TenantProfitReport get profitReport => TenantProfitReport.from(
    sales: sales,
    profit: profit,
    incompleteCostLineCount: incompleteCostLineCount,
  );

  /// Adds several days' net figures into one period's.
  ///
  /// The tender split is dropped for the reason `TenantSalesTotals.summed`
  /// drops its own: two breakdowns do not add up without re-checking them
  /// against the sum, and nothing that sums days draws one.
  factory TenantSalesNetTotals.summed({
    required double sales,
    required double profit,
    required int transactions,
    required int incompleteCostLineCount,
    required int returnsScanned,
  }) => TenantSalesNetTotals._(
    sales: sales,
    profit: profit,
    transactions: transactions,
    incompleteCostLineCount: incompleteCostLineCount,
    returnsScanned: returnsScanned,
    tenderBreakdown: null,
  );

  /// The net figures a device aggregated from its own cache.
  ///
  /// **Carries its tender split, unlike [summed].** A period assembled day by
  /// day has no breakdown to carry, but one aggregated in a single pass does -
  /// and without it the totals page drew a net headline over gross payment
  /// rows that did not add up to it.
  factory TenantSalesNetTotals.fromDeviceMinorUnits({
    required int salesMinor,
    required int costMinor,
    required int transactions,
    required int incompleteCostLineCount,
    required int returnsScanned,
    required Map<String, int> tenderSalesMinor,
    required Map<String, int> tenderTransactions,
  }) => TenantSalesNetTotals._(
    sales: salesMinor / 100,
    profit: (salesMinor - costMinor) / 100,
    transactions: transactions,
    incompleteCostLineCount: incompleteCostLineCount,
    returnsScanned: returnsScanned,
    tenderBreakdown: TenantSalesTenderBreakdown.fromDeviceMinorUnits(
      salesMinor: tenderSalesMinor,
      transactions: tenderTransactions,
      totalSalesMinor: salesMinor,
      totalTransactions: transactions,
    ),
  );

  /// Reads the `net` block of one callable answer.
  ///
  /// **Required, because the current server always sends it.**
  /// `SalesComparison.net` is not optional in `reports.ts` and every answer
  /// carries it, so an answer without one is not an older deployment being
  /// tolerated - it is a malformed answer, and reading it as *no returns* would
  /// quietly overstate the period by every return in it. This is #103: the
  /// fallback existed to let a new app talk to an old deployment, which SIT
  /// does not need because it is redeployed whole.
  ///
  /// A `net` that contradicts the gross figures beside it is still a failure,
  /// for the reason it always was: it describes some other period.
  ///
  /// This is the callable path only. `TenantSalesTotals.net` stays nullable
  /// because the device path genuinely has no netting to report when the cache
  /// could not be read for returns.
  static TenantSalesNetTotals decode(
    Object? value,
    Object? byTender,
    Object? returnsScanned, {
    required double grossSales,
    required int grossTransactions,
  }) {
    if (value == null) {
      throw const FormatException('getSalesComparison sent no net block.');
    }
    if (value is! Map) {
      throw const FormatException(
        'getSalesComparison sent a malformed net block.',
      );
    }
    final net = _strictMap(value, 'net');
    final sales = _requiredNonNegativeNumber(net, 'sales');
    final transactions = _requiredCount(net, 'transactions');
    // Exact, in whole minor units, the way the tender split is checked.
    if (reportingMinorUnits(sales) > reportingMinorUnits(grossSales) ||
        transactions > grossTransactions) {
      throw const FormatException(
        'getSalesComparison netted a period to more than it took.',
      );
    }
    return TenantSalesNetTotals._(
      sales: sales,
      profit: _requiredFiniteNumber(net, 'profit'),
      transactions: transactions,
      incompleteCostLineCount: _requiredCount(net, 'incompleteCostLineCount'),
      returnsScanned: returnsScanned == null
          ? 0
          : _requiredCount(<String, Object?>{'v': returnsScanned}, 'v'),
      // Checked against the *net* figures, so the buckets-sum invariant holds
      // for both halves of the answer rather than only the gross one.
      tenderBreakdown: TenantSalesTenderBreakdown.tryDecode(
        byTender,
        sales: sales,
        transactions: transactions,
      ),
    );
  }
}

final class TenantSalesTotals {
  const TenantSalesTotals._({
    required this.query,
    required this.scannedTransactions,
    required this.sales,
    required this.profit,
    required this.transactions,
    required this.incompleteCostLineCount,
    required this.tenderBreakdown,
    required this.basis,
    required this.net,
  });

  factory TenantSalesTotals.fromCallable(
    Object? value, {
    required TenantSalesTotalsQuery query,
  }) {
    final data = _strictMap(value, 'response');
    final previous = _strictMap(data['previous'], 'previous');
    final scanned = _requiredCount(data, 'scannedTransactions');
    if (scanned > maximumTransactions && data['summaryVersion'] != 1) {
      throw const FormatException(
        'getSalesComparison scanned more sales than it may.',
      );
    }
    final transactions = _requiredCount(previous, 'transactions');
    final counted = query.isCategoryFiltered
        ? transactions <= scanned
        : transactions == scanned;
    if (!counted) {
      throw const FormatException(
        'getSalesComparison counted a different number of sales than it read.',
      );
    }
    final sales = _requiredNonNegativeNumber(previous, 'sales');
    return TenantSalesTotals._(
      query: query,
      scannedTransactions: scanned,
      sales: sales,
      // Validated here and judged by [profitReport], never by this decoder.
      // ~~Deliberately never displayed~~ - retracted: that reason was that no
      // product carried a cost, so profit always equalled revenue and showing
      // it would have reported a margin of 100%. Products carry costs now, and
      // that exact case is the one `TenantProfitBasis.incomplete` refuses.
      profit: _requiredFiniteNumber(previous, 'profit'),
      transactions: transactions,
      incompleteCostLineCount: _requiredCount(
        previous,
        'incompleteCostLineCount',
      ),
      // Deliberately read from the top level, beside `scannedTransactions`,
      // rather than from `previous`: it is a property of the whole answer, and
      // it is checked against the two figures above rather than trusted.
      tenderBreakdown: TenantSalesTenderBreakdown.tryDecode(
        data['byTender'],
        sales: sales,
        transactions: transactions,
      ),
      basis: TenantSalesTotalsBasis.server,
      net: TenantSalesNetTotals.decode(
        data['net'],
        data['netByTender'],
        data['returnsScanned'],
        grossSales: sales,
        grossTransactions: transactions,
      ),
    );
  }

  /// A strictly reconciled aggregate derived only from records held by this
  /// device. Monetary inputs stay in minor units until the public view model is
  /// built so grouping cannot introduce floating-point drift.
  factory TenantSalesTotals.fromDevice({
    required TenantSalesTotalsQuery query,
    required int scannedTransactions,
    required int salesMinor,
    required int costMinor,
    required int transactions,
    required int incompleteCostLineCount,
    required Map<String, int> tenderSalesMinor,
    required Map<String, int> tenderTransactions,
    TenantSalesNetTotals? net,
  }) {
    if (scannedTransactions < 0 ||
        scannedTransactions > maximumTransactions ||
        salesMinor < 0 ||
        costMinor < 0 ||
        transactions < 0 ||
        transactions > scannedTransactions ||
        incompleteCostLineCount < 0 ||
        !query.isCategoryFiltered && transactions != scannedTransactions) {
      throw const FormatException('Device sales totals are inconsistent.');
    }
    return TenantSalesTotals._(
      query: query,
      scannedTransactions: scannedTransactions,
      sales: salesMinor / 100,
      profit: (salesMinor - costMinor) / 100,
      transactions: transactions,
      incompleteCostLineCount: incompleteCostLineCount,
      tenderBreakdown: TenantSalesTenderBreakdown.fromDeviceMinorUnits(
        salesMinor: tenderSalesMinor,
        transactions: tenderTransactions,
        totalSalesMinor: salesMinor,
        totalTransactions: transactions,
      ),
      basis: TenantSalesTotalsBasis.device,
      // Filled by the device aggregator once it reads the cache's returns; a
      // caller that has not is reporting gross and says so rather than
      // implying nothing came back.
      net: net,
    );
  }

  /// Adds several answers into one, for a span assembled day by day.
  ///
  /// **Not a decode, and it does not pretend to be one.** Every field here is
  /// already a validated server figure; what this builds is their sum, which
  /// is why it skips the cross-checks `fromCallable` runs - there is no
  /// `scannedTransactions` for a total that was never one read, and asserting
  /// one would be asserting something no server said. [scannedTransactions]
  /// therefore reports the transactions counted, which is what it is.
  ///
  /// [tenderBreakdown] is deliberately dropped: two breakdowns do not add up
  /// without re-checking them against the sum, and nothing that calls this
  /// draws one.
  factory TenantSalesTotals.summed({
    required TenantSalesTotalsQuery query,
    required double sales,
    required double profit,
    required int transactions,
    required int incompleteCostLineCount,
    TenantSalesTotalsBasis basis = TenantSalesTotalsBasis.server,
    TenantSalesNetTotals? net,
  }) => TenantSalesTotals._(
    query: query,
    scannedTransactions: transactions,
    sales: sales,
    profit: profit,
    transactions: transactions,
    incompleteCostLineCount: incompleteCostLineCount,
    tenderBreakdown: null,
    basis: basis,
    net: net,
  );

  /// The server's `SALES_QUERY_LIMIT`; a period holding more is refused
  /// outright rather than answered from a truncated read.
  static const int maximumTransactions = 5000;

  /// The exact request these totals answer.
  final TenantSalesTotalsQuery query;

  /// How many source sales this answer covers (not the billed read count).
  ///
  /// Equal to [transactions] unless a category was requested, in which case the
  /// difference is the sales in the period that held nothing in it.
  final int scannedTransactions;

  /// Major-unit revenue, exactly as the server added it up.
  ///
  /// Without a category this is the recorded total of each sale. With one it is
  /// the sum of the matching **lines**, which is a smaller and different figure:
  /// the rest of each sale is not in it.
  final double sales;

  /// Major-unit profit, exactly as the server subtracted it. Whether it may be
  /// shown at all is [profitReport]'s answer, not this field's.
  final double profit;

  /// How many sales contributed to [sales].
  final int transactions;

  /// How many sale lines lacked the cost data a profit figure needs.
  final int incompleteCostLineCount;

  /// How [sales] and [transactions] split by how each sale was paid for, or
  /// `null` when the server reported no split at all.
  final TenantSalesTenderBreakdown? tenderBreakdown;

  final TenantSalesTotalsBasis basis;

  /// The same period with its returns taken back out, or null where the
  /// answer did not carry them.
  ///
  /// **Absent is not zero.** A server that does not net returns and a period
  /// that had none are different facts, and a surface must be able to say
  /// "these figures are gross" rather than imply nothing came back.
  final TenantSalesNetTotals? net;

  /// Whether this answer can state takings after returns at all.
  bool get hasNet => net != null;

  /// Takings after returns where they are known, and the gross figure where
  /// they are not - which is what every surface showed before they were.
  double get netOrGrossSales => net?.sales ?? sales;

  /// The transaction count on the same basis as [netOrGrossSales].
  int get netOrGrossTransactions => net?.transactions ?? transactions;

  /// The profit report on the same basis as [netOrGrossSales].
  TenantProfitReport get netOrGrossProfitReport =>
      net?.profitReport ?? profitReport;

  double get averageSale => transactions == 0 ? 0 : sales / transactions;

  bool get hasCompleteCostData => incompleteCostLineCount == 0;

  /// This period's profit, and whether it may be shown at all.
  ///
  /// The same type one reconciled day produces. A category filter changes what
  /// the figures mean - the server sums the matching lines and counts only
  /// their costs - but not what makes one of them believable, so the rule is
  /// the same one.
  TenantProfitReport get profitReport => TenantProfitReport.from(
    sales: sales,
    profit: profit,
    incompleteCostLineCount: incompleteCostLineCount,
  );
}

/// Session-bound gateway with no business input surface.
///
/// The business and - for [TenantSalesScope.mine] - the member both come from
/// one captured live session, so no caller can total somebody else's sales or
/// another business's.
final class TenantSalesTotalsGateway {
  TenantSalesTotalsGateway({
    required TenantSession session,
    required SalesTotalsCallable callable,
    DateTime Function()? clock,
  }) : _session = session,
       _callable = callable,
       _clock = clock ?? _utcNow;

  /// The server's `REPORTING_ROLES`. Tenant-wide revenue is management data,
  /// and this list is deliberately identical to the daily summary's: a period
  /// total is the same information over a different stretch of days.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  final TenantSession _session;
  final SalesTotalsCallable _callable;
  final DateTime Function() _clock;

  static bool canReadInSession(TenantSession session) =>
      session.canAccess(allowedRoles: [...allowedRoles, TenantRole.cashier]);

  /// Resolves [period], [soldById], and [categoryId] against the live session
  /// and the clock.
  ///
  /// [soldById] names one member of this business, or is absent for all of
  /// them. Nothing here proves the member exists - only that the server would
  /// accept the ID - because a departed member's sales are still real sales in
  /// the period. Proving membership is the surface's job, and it does it from
  /// the canonical directory before calling this.
  ///
  /// Refused locally when the session may not read totals, so an unauthorized
  /// tap costs no round trip.
  TenantSalesTotalsQuery createQuery({
    required TenantSalesPeriod period,
    String? soldById,
    String? categoryId,
  }) {
    if (!canReadInSession(_session)) {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.forbidden,
      );
    }
    final now = _clock().toUtc();
    // Subtracting whole days from the UTC instant is exact for a fixed-offset
    // business day, so the Africa/Nairobi boundary the checkout stamps on every
    // sale is respected without any date arithmetic of our own.
    final endDate = checkoutBusinessDate(now);
    final startDate = checkoutBusinessDate(
      now.subtract(Duration(days: period.days - 1)),
    );
    final member = _scopedMember(soldById);
    return TenantSalesTotalsQuery._(
      tenantId: _session.tenantId,
      period: period,
      // Derived, never taken from a caller: what naming this member means is a
      // fact about the session, not a claim the surface gets to make.
      scope: switch (member) {
        null => TenantSalesScope.everyone,
        final uid when uid == _session.uid => TenantSalesScope.mine,
        _ => TenantSalesScope.oneMember,
      },
      startDate: startDate,
      endDate: endDate,
      soldById: member,
      categoryId: categoryId == null ? null : _validatedCategoryId(categoryId),
    );
  }

  /// Resolves one explicitly selected Nairobi business day.
  ///
  /// The callable already accepts inclusive start and end dates, so a daily
  /// report is the existing wire request with both fields set to the same day.
  /// Future days are refused locally rather than presented as empty reports.
  TenantSalesTotalsQuery createBusinessDateQuery({
    required String businessDate,
    String? soldById,
    String? categoryId,
  }) {
    if (!canReadInSession(_session)) {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.forbidden,
      );
    }
    final String date;
    try {
      date = validateCheckoutBusinessDate(businessDate);
    } on ArgumentError {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.invalidRequest,
      );
    }
    if (date.compareTo(checkoutBusinessDate(_clock().toUtc())) > 0) {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.invalidRequest,
      );
    }
    final member = _scopedMember(soldById);
    return TenantSalesTotalsQuery._(
      tenantId: _session.tenantId,
      period: TenantSalesPeriod.today,
      scope: switch (member) {
        null => TenantSalesScope.everyone,
        final uid when uid == _session.uid => TenantSalesScope.mine,
        _ => TenantSalesScope.oneMember,
      },
      startDate: date,
      endDate: date,
      soldById: member,
      categoryId: categoryId == null ? null : _validatedCategoryId(categoryId),
    );
  }

  /// Resolves one explicit inclusive span of Nairobi business days.
  ///
  /// **A range rather than a fifth [TenantSalesPeriod], for the reason
  /// [createBusinessDateQuery] gives about a fourth.** Every value in that enum
  /// ends *today* and is offered to a person choosing one; a week that ended a
  /// fortnight ago is neither. The wire has always accepted an inclusive start
  /// and end, so this is the existing request with both named - which is what
  /// lets the weekly report compare one week against the one before it.
  ///
  /// Future days are refused locally rather than answered as an empty report.
  TenantSalesTotalsQuery createRangeQuery({
    required String startBusinessDate,
    required String endBusinessDate,
    String? soldById,
    String? categoryId,
  }) {
    if (!canReadInSession(_session)) {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.forbidden,
      );
    }
    final String start;
    final String end;
    try {
      start = validateCheckoutBusinessDate(startBusinessDate);
      end = validateCheckoutBusinessDate(endBusinessDate);
    } on ArgumentError {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.invalidRequest,
      );
    }
    if (start.compareTo(end) > 0 ||
        end.compareTo(checkoutBusinessDate(_clock().toUtc())) > 0) {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.invalidRequest,
      );
    }
    final member = _scopedMember(soldById);
    return TenantSalesTotalsQuery._(
      tenantId: _session.tenantId,
      // The nearest standing period this span belongs to. Nothing reads it for
      // a range request, and inventing a `custom` value would put a word in
      // the period chooser that no one may pick.
      period: TenantSalesPeriod.last7Days,
      scope: switch (member) {
        null => TenantSalesScope.everyone,
        final uid when uid == _session.uid => TenantSalesScope.mine,
        _ => TenantSalesScope.oneMember,
      },
      startDate: start,
      endDate: end,
      soldById: member,
      categoryId: categoryId == null ? null : _validatedCategoryId(categoryId),
    );
  }

  /// The same request over the single business day **before** today.
  ///
  /// **A method rather than a fifth [TenantSalesPeriod]**, and the distinction
  /// is not cosmetic: every value in that enum ends today and is *offered to a
  /// person choosing one*, so adding `yesterday` there would put a filter in
  /// the Sales screen's choosers that nobody asked for. This range is never
  /// chosen - it exists so the home can say how today compares with the day
  /// before, which is the one thing a shopkeeper asks before any of the four.
  ///
  /// **[TenantSalesTotalsQuery.period] is [TenantSalesPeriod.today] and that
  /// is honest on the wire**, because the period is not on the wire: only
  /// `previousStartDate` and `previousEndDate` are sent, and both name
  /// yesterday here. The field stays a client-side label for a length of time,
  /// and this query is one day long.
  TenantSalesTotalsQuery createPreviousDayQuery({String? soldById}) {
    if (!canReadInSession(_session)) {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.forbidden,
      );
    }
    // One whole day back from the same UTC instant `createQuery` uses, so the
    // two queries cannot straddle the business-day boundary differently.
    final businessDate = checkoutBusinessDate(
      _clock().toUtc().subtract(const Duration(days: 1)),
    );
    final member = _scopedMember(soldById);
    return TenantSalesTotalsQuery._(
      tenantId: _session.tenantId,
      period: TenantSalesPeriod.today,
      scope: switch (member) {
        null => TenantSalesScope.everyone,
        final uid when uid == _session.uid => TenantSalesScope.mine,
        _ => TenantSalesScope.oneMember,
      },
      startDate: businessDate,
      endDate: businessDate,
      soldById: member,
      categoryId: null,
    );
  }

  String? _scopedMember(String? soldById) {
    if (!_session.canAccess(allowedRoles: allowedRoles)) {
      if (soldById != null && soldById != _session.uid) {
        throw const TenantSalesTotalsException(
          TenantSalesTotalsFailure.forbidden,
        );
      }
      return _session.uid;
    }
    return soldById == null ? null : _validatedUid(soldById);
  }

  /// The signed-in member's own UID, for a caller asking only for its own
  /// sales without consulting any directory.
  String get selfUid => _session.uid;

  /// Validates a category the caller chose, as the server would accept it.
  String _validatedCategoryId(String categoryId) {
    try {
      return validateTenantDocumentId(categoryId, fieldName: 'categoryId');
    } on ArgumentError {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.invalidRequest,
      );
    }
  }

  /// A member UID, as the server would accept it.
  ///
  /// A UID that is not a usable document ID would be rejected by the handler as
  /// an invalid argument, so it is refused here with the same meaning rather
  /// than sent and translated back.
  String _validatedUid(String uid) {
    try {
      return validateTenantDocumentId(uid, fieldName: 'soldById');
    } on ArgumentError {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.invalidRequest,
      );
    }
  }

  /// Reads the totals for [query].
  Future<TenantSalesTotals> load(TenantSalesTotalsQuery query) async {
    if (!canReadInSession(_session)) {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.forbidden,
      );
    }
    if (query.tenantId != _session.tenantId) {
      throw StateError('The sales totals query belongs to another tenant.');
    }
    _scopedMember(query.soldById);
    if (!_session.canAccess(allowedRoles: allowedRoles) &&
        query.soldById != _session.uid) {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.forbidden,
      );
    }
    final Object? response;
    try {
      response = await _callable.call(query.toPayload());
    } on FirebaseFunctionsException catch (error) {
      throw TenantSalesTotalsException(_classify(error));
    } on TimeoutException {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.unavailable,
      );
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'reporting.sales_comparison_request',
      );
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.unavailable,
      );
    }
    return TenantSalesTotals.fromCallable(response, query: query);
  }
}

/// Classifies a refusal from the callable.
///
/// The code alone decides the outcome. An unmodelled code degrades to
/// [TenantSalesTotalsFailure.refused] rather than to a transport failure,
/// because a refusal a retry cannot fix must not be presented as one that can.
TenantSalesTotalsFailure _classify(
  FirebaseFunctionsException error,
) => switch (error.code) {
  'permission-denied' ||
  'unauthenticated' => TenantSalesTotalsFailure.forbidden,
  'resource-exhausted' => TenantSalesTotalsFailure.periodTooLarge,
  'invalid-argument' => TenantSalesTotalsFailure.invalidRequest,
  // The aggregation helpers raise this when a stored sale amount is out of
  // range or cannot be added exactly. It is a data problem in the business's
  // own sales, not a transport one, and asking again will not change it.
  'failed-precondition' => TenantSalesTotalsFailure.unusableSaleData,
  'unavailable' ||
  'deadline-exceeded' ||
  'internal' ||
  'aborted' ||
  'unknown' => TenantSalesTotalsFailure.unavailable,
  _ => TenantSalesTotalsFailure.refused,
};

Map<String, Object?> _strictMap(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('getSalesComparison returned an invalid $field.');
  }
  return <String, Object?>{
    for (final key in value.keys)
      if (key is String) key: value[key],
  };
}

int _requiredCount(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value < 0 || value > _maximumCount) {
    throw FormatException('getSalesComparison returned an invalid $field.');
  }
  return value;
}

double _requiredNonNegativeNumber(Map<String, Object?> data, String field) {
  final value = _requiredFiniteNumber(data, field);
  if (value < 0) {
    throw FormatException('getSalesComparison returned an invalid $field.');
  }
  return value;
}

double _requiredFiniteNumber(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! num || !value.isFinite || value.abs() > _maximumMoney) {
    throw FormatException('getSalesComparison returned an invalid $field.');
  }
  return value.toDouble();
}

const int _maximumCount = 1000000000;

/// The server's `MAX_MONETARY_VALUE`.
const double _maximumMoney = 1000000000000;

DateTime _utcNow() => DateTime.now().toUtc();
