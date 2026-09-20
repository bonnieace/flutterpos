import '../checkout/checkout_outbox.dart';
import '../checkout/checkout_receipt.dart';
import '../checkout/checkout_sale.dart';
import '../checkout/checkout_tender.dart';
import '../returns/return_history.dart';
import '../returns/return_offsets.dart';
import '../sales/sale_history.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import 'sales_totals.dart';

/// Why a device total was deliberately withheld instead of presenting a
/// provisional figure as trustworthy.
enum TenantDeviceSalesRefusal { conflictingEvidence, unreadableEvidence }

/// The result of one cache-only scan.
final class TenantDeviceSalesTotals {
  const TenantDeviceSalesTotals._({
    required this.query,
    required this.totals,
    required this.scannedRecordCount,
    required this.unsentTransactions,
    required this.truncated,
    required this.refusal,
  });

  factory TenantDeviceSalesTotals.complete({
    required TenantSalesTotals queryTotals,
    required int scannedRecordCount,
    required int unsentTransactions,
  }) => TenantDeviceSalesTotals._(
    query: queryTotals.query,
    totals: queryTotals,
    scannedRecordCount: scannedRecordCount,
    unsentTransactions: unsentTransactions,
    truncated: false,
    refusal: null,
  );

  factory TenantDeviceSalesTotals.truncated({
    required TenantSalesTotalsQuery query,
    required int scannedRecordCount,
  }) => TenantDeviceSalesTotals._(
    query: query,
    totals: null,
    scannedRecordCount: scannedRecordCount,
    unsentTransactions: 0,
    truncated: true,
    refusal: null,
  );

  factory TenantDeviceSalesTotals.refused({
    required TenantSalesTotalsQuery query,
    required int scannedRecordCount,
    required TenantDeviceSalesRefusal reason,
  }) => TenantDeviceSalesTotals._(
    query: query,
    totals: null,
    scannedRecordCount: scannedRecordCount,
    unsentTransactions: 0,
    truncated: false,
    refusal: reason,
  );

  final TenantSalesTotalsQuery query;
  final TenantSalesTotals? totals;
  final int scannedRecordCount;

  /// How many of the counted sales the server cannot yet have seen.
  ///
  /// **Only the outbox states that are still owed**, which is why a `confirmed`
  /// record does not count: the server holds that sale, so a published figure
  /// covering this day already includes it. A record the cache also held is not
  /// counted either - it reached the server to get there.
  ///
  /// **It says a figure is short, never which figure to draw.** Which one to
  /// draw is settled by size - the cache holds a subset of what the server has,
  /// so both totals are under the truth and the larger is always the nearer.
  /// What size cannot say is that the winner is still missing something, and on
  /// a day where a busier till carries the published figure past this one, that
  /// is the only thing left to tell somebody. Zero for a truncated or refused
  /// scan, which state no total to qualify.
  final int unsentTransactions;

  final bool truncated;
  final TenantDeviceSalesRefusal? refusal;

  TenantSalesTotalsBasis get basis => TenantSalesTotalsBasis.device;
  bool get canDisplay => totals != null;

  /// The totals a surface may put on screen, or null where this device is not
  /// in a position to state the day.
  ///
  /// **One rule, because two screens reading the same cache must not disagree
  /// about it.** The home tiles and the daily summary both draw what this
  /// device holds for a day the server has not published, and a zero guard
  /// written twice is a zero guard that drifts.
  ///
  /// **A total of zero is the one device figure that cannot be told apart from
  /// ignorance.** *The shop has taken nothing* and *nothing has reached this
  /// till yet* render identically, and on a morning where another register
  /// opened first the second is the true one. Every other figure here is
  /// understated at worst and says so; `0.00` is simply wrong.
  ///
  /// A truncated scan and a refusal are withheld for the reason they were
  /// recorded: neither is a total, and guessing past either would print a
  /// figure this device has already said it cannot stand behind.
  TenantSalesTotals? get displayable =>
      truncated || refusal != null || (totals?.transactions ?? 0) == 0
      ? null
      : totals;
}

/// Cache/outbox aggregator shared by every reporting surface.
///
/// [cacheReader] and [cacheReportReader] must be cache-only adapters. This
/// object contains no callable and has no live-reader fallback, so a cached
/// loader cannot accidentally turn into a network request.
final class TenantDeviceSalesAggregator {
  TenantDeviceSalesAggregator({
    required TenantSession session,
    required TenantDataReader cacheReader,
    TenantSalesHistoryQueryReader? cacheReportReader,
    HiveCheckoutOutbox? outbox,
    DateTime Function()? clock,
  }) : _session = session,
       _repository = TenantSaleHistoryRepository(
         session: session,
         reader: cacheReader,
         reportReader:
             cacheReportReader ??
             (cacheReader is TenantSalesHistoryQueryReader
                 ? cacheReader as TenantSalesHistoryQueryReader
                 : null),
       ),
       _outbox = outbox,
       _returns = TenantReturnHistoryRepository(
         session: session,
         reader: cacheReader,
       ),
       _queryFactory = TenantSalesTotalsGateway(
         session: session,
         callable: const _NeverSalesTotalsCallable(),
         clock: clock,
       );

  static const int _pageSize = 50;

  final TenantSession _session;
  final TenantSaleHistoryRepository _repository;
  final HiveCheckoutOutbox? _outbox;
  final TenantReturnHistoryRepository _returns;
  final TenantSalesTotalsGateway _queryFactory;

  /// The longest stretch this will read returns for.
  ///
  /// **A day at a time, because there is no range query to use.**
  /// `readCollectionPage` takes equality filters only, and the `returns`
  /// index is on `businessDate` alone - so a range would mean a new reader, a
  /// new index and a migration for a path that runs against the local cache.
  /// A month is thirty-one cache reads, which is affordable; a year is not, so
  /// a longer stretch reports gross rather than paying for it.
  static const int _returnsDayLimit = 62;

  /// Pages of returns read per day before the day is treated as a fault.
  static const int _returnsPageLimit = 20;

  /// The period's returns, from the same cache the sales came from.
  ///
  /// **Null means "not netted", never "none came back".** A stretch longer
  /// than [_returnsDayLimit] and a read that failed both land here, and the
  /// caller reports gross - which is what every figure on this surface did
  /// before returns were netted at all. So the fallback is the old behaviour
  /// rather than a new claim.
  ///
  /// **What the cache does not hold is simply not subtracted.** A return rung
  /// on this till is written locally and is present at once; one rung
  /// elsewhere is present once anything has read it. A device that has never
  /// seen a colleague's return still overstates the period by it - exactly as
  /// it did before - and the server's answer corrects the figure as soon as
  /// there is signal.
  Future<_DeviceReturns?> _readReturns(TenantSalesTotalsQuery query) async {
    final dates = _businessDatesBetween(query.startDate, query.endDate);
    if (dates == null) return null;
    final units = <String, Map<String, int>>{};
    var documents = 0;
    try {
      for (final date in dates) {
        String? cursor;
        for (var page = 0; page < _returnsPageLimit; page++) {
          final read = await _returns.loadDayReturns(
            businessDate: date,
            pageSize: _pageSize,
            cursor: cursor,
          );
          for (final record in read.items) {
            documents += 1;
            final bySale = units.putIfAbsent(
              record.saleId,
              () => <String, int>{},
            );
            for (final line in record.lines) {
              bySale[line.productId] =
                  (bySale[line.productId] ?? 0) + line.quantity;
            }
          }
          cursor = read.nextCursor;
          if (!read.hasMore || cursor == null) break;
          // A day holding more returns than this is a fault rather than a busy
          // shop, and a partial read would understate what came back.
          if (page == _returnsPageLimit - 1) return null;
        }
      }
    } on Object {
      return null;
    }
    return _DeviceReturns(units: units, documentCount: documents);
  }

  /// Every business date from [start] to [end], or null where there are too
  /// many to read a day at a time.
  static List<String>? _businessDatesBetween(String start, String end) {
    final DateTime first;
    final DateTime last;
    try {
      first = DateTime.parse(
        '${validateCheckoutBusinessDate(start)}T00:00:00Z',
      );
      last = DateTime.parse('${validateCheckoutBusinessDate(end)}T00:00:00Z');
    } on Object {
      return null;
    }
    if (last.isBefore(first)) return null;
    final span = last.difference(first).inDays + 1;
    if (span > _returnsDayLimit) return null;
    return <String>[
      for (var day = 0; day < span; day++)
        _isoDate(first.add(Duration(days: day))),
    ];
  }

  static String _isoDate(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  TenantSalesTotalsQuery createQuery({
    required TenantSalesPeriod period,
    String? soldById,
    String? categoryId,
  }) => _queryFactory.createQuery(
    period: period,
    soldById: soldById,
    categoryId: categoryId,
  );

  TenantSalesTotalsQuery createBusinessDateQuery({
    required String businessDate,
    String? soldById,
    String? categoryId,
  }) => _queryFactory.createBusinessDateQuery(
    businessDate: businessDate,
    soldById: soldById,
    categoryId: categoryId,
  );

  TenantSalesTotalsQuery createRangeQuery({
    required String startBusinessDate,
    required String endBusinessDate,
    String? soldById,
    String? categoryId,
  }) => _queryFactory.createRangeQuery(
    startBusinessDate: startBusinessDate,
    endBusinessDate: endBusinessDate,
    soldById: soldById,
    categoryId: categoryId,
  );

  Future<TenantDeviceSalesTotals> load(TenantSalesTotalsQuery query) async {
    if (query.tenantId != _session.tenantId) {
      throw const TenantSaleException('cross_tenant_sale');
    }
    final canonical = <String, _DeviceSale>{};
    // Kept beside the device projection because `describeReturnOffset` prices
    // a return against the whole sale - its discount, its subtotal and its
    // per-line unit prices - and that is the one definition of the
    // arithmetic, shared with the server through the golden vectors.
    final canonicalSales = <String, TenantSale>{};
    String? cursor;
    var rawScanned = 0;
    do {
      final page = await _repository.loadReport(
        startBusinessDate: query.startDate,
        endBusinessDate: query.endDate,
        selectedStaffId: query.soldById,
        pageSize: _pageSize,
        cursor: cursor,
      );
      rawScanned += page.items.length;
      for (final sale in page.items) {
        if (canonical.containsKey(sale.id)) {
          return TenantDeviceSalesTotals.refused(
            query: query,
            scannedRecordCount: rawScanned,
            reason: TenantDeviceSalesRefusal.conflictingEvidence,
          );
        }
        canonical[sale.id] = _DeviceSale.fromCanonical(sale);
        canonicalSales[sale.id] = sale;
      }
      if (canonical.length >= TenantSalesTotals.maximumTransactions &&
          page.hasMore) {
        return TenantDeviceSalesTotals.truncated(
          query: query,
          scannedRecordCount: canonical.length,
        );
      }
      cursor = page.hasMore ? page.nextCursor : null;
    } while (cursor != null);

    final merged = <String, _DeviceSale>{...canonical};
    // Sales this device is still carrying, which is what makes a published
    // figure for the same day provably short. See [unsentTransactions].
    var unsent = 0;
    if (_outbox != null) {
      final records = await _outbox.recordsForSession(
        uid: _session.uid,
        tenantId: _session.tenantId,
      );
      for (final record in records) {
        _DeviceSale candidate;
        try {
          candidate = _DeviceSale.fromOutbox(
            CheckoutSalePayload.fromOutboxRecord(record, session: _session),
          );
        } catch (_) {
          return TenantDeviceSalesTotals.refused(
            query: query,
            scannedRecordCount: merged.length,
            reason: TenantDeviceSalesRefusal.unreadableEvidence,
          );
        }
        if (!candidate.matches(query)) continue;
        if (record.state == CheckoutOutboxState.needsAttention) {
          return TenantDeviceSalesTotals.refused(
            query: query,
            scannedRecordCount: merged.length,
            reason: TenantDeviceSalesRefusal.conflictingEvidence,
          );
        }
        if (!_includedOutboxStates.contains(record.state)) continue;
        final existing = canonical[record.checkoutId];
        if (existing != null) {
          if (existing.payloadHash != record.payloadHash) {
            return TenantDeviceSalesTotals.refused(
              query: query,
              scannedRecordCount: merged.length,
              reason: TenantDeviceSalesRefusal.conflictingEvidence,
            );
          }
          continue;
        }
        merged[record.checkoutId] = candidate;
        // Counted here rather than after the accumulation: a sale the server
        // has never seen is evidence whether or not it survives a return, and
        // the question this answers is what the server can know, not what the
        // day came to.
        if (_unsentOutboxStates.contains(record.state)) unsent += 1;
        if (merged.length > TenantSalesTotals.maximumTransactions) {
          return TenantDeviceSalesTotals.truncated(
            query: query,
            scannedRecordCount: merged.length,
          );
        }
      }
    }

    final buckets = <String>{
      ...checkoutTenderWireValues,
      TenantSalesTenderBreakdown.unrecordedBucket,
      TenantSalesTenderBreakdown.unrecognisedBucket,
    };
    // **Read from the cache the sales came from.** A return rung on this till
    // is written locally and is there immediately; one rung elsewhere is there
    // once anything has read it. What the cache does not hold is simply not
    // subtracted - which is exactly what this surface did for every return
    // before, so the figure can only move closer to the truth.
    var returned = await _readReturns(query);
    final offsets = <String, TenantSaleReturnOffset>{};
    if (returned != null) {
      try {
        for (final entry in returned.units.entries) {
          final sale = canonicalSales[entry.key];
          // A return against a sale this read did not cover belongs to another
          // colleague, another category, or another period. The same scoping
          // the server gets for free by keying on the sales it already read.
          if (sale == null) continue;
          offsets[entry.key] = describeReturnOffset(
            sale,
            entry.value,
            categoryId: query.categoryId,
          );
        }
      } on TenantReturnException {
        // A return that cannot be valued against its own sale is a fault, not
        // a smaller number. The period falls back to gross - which is what it
        // reported before returns were netted at all - rather than publishing
        // a figure it cannot stand behind.
        returned = null;
        offsets.clear();
      }
    }

    _DeviceAccumulation accumulate({required bool net}) {
      final tenderSales = <String, int>{for (final key in buckets) key: 0};
      final tenderTransactions = <String, int>{
        for (final key in buckets) key: 0,
      };
      var revenueMinor = 0;
      var costMinor = 0;
      var transactions = 0;
      var incompleteCosts = 0;
      for (final sale in merged.values) {
        if (!sale.matches(query)) continue;
        final contribution = sale.contribution(
          query.categoryId,
          net ? offsets[sale.id] : null,
        );
        if (!contribution.counted) continue;
        revenueMinor += contribution.revenueMinor;
        costMinor += contribution.costMinor;
        incompleteCosts += contribution.incompleteCostLines;
        transactions += 1;
        final bucket =
            sale.tender?.wireValue ??
            TenantSalesTenderBreakdown.unrecordedBucket;
        final safeBucket = buckets.contains(bucket)
            ? bucket
            : TenantSalesTenderBreakdown.unrecognisedBucket;
        tenderSales[safeBucket] =
            tenderSales[safeBucket]! + contribution.revenueMinor;
        tenderTransactions[safeBucket] = tenderTransactions[safeBucket]! + 1;
      }
      return _DeviceAccumulation(
        revenueMinor: revenueMinor,
        costMinor: costMinor,
        transactions: transactions,
        incompleteCostLines: incompleteCosts,
        tenderSalesMinor: tenderSales,
        tenderTransactions: tenderTransactions,
      );
    }

    final gross = accumulate(net: false);
    // Two passes over the same sales, the way the callable makes two
    // aggregate calls: the gross figures stay exactly the expression they
    // have always been, and only the second one reads the offsets.
    final netPass = returned == null ? null : accumulate(net: true);
    final totals = TenantSalesTotals.fromDevice(
      query: query,
      scannedTransactions: merged.length,
      salesMinor: gross.revenueMinor,
      costMinor: gross.costMinor,
      transactions: gross.transactions,
      incompleteCostLineCount: gross.incompleteCostLines,
      tenderSalesMinor: gross.tenderSalesMinor,
      tenderTransactions: gross.tenderTransactions,
      // **With its own tender split.** The headline and the payment rows have
      // to describe the same money; a net total over gross rows is a page
      // whose own figures do not add up.
      net: netPass == null
          ? null
          : TenantSalesNetTotals.fromDeviceMinorUnits(
              salesMinor: netPass.revenueMinor,
              costMinor: netPass.costMinor,
              transactions: netPass.transactions,
              incompleteCostLineCount: netPass.incompleteCostLines,
              returnsScanned: returned!.documentCount,
              tenderSalesMinor: netPass.tenderSalesMinor,
              tenderTransactions: netPass.tenderTransactions,
            ),
    );
    return TenantDeviceSalesTotals.complete(
      queryTotals: totals,
      scannedRecordCount: merged.length,
      unsentTransactions: unsent,
    );
  }
}

const Set<CheckoutOutboxState> _includedOutboxStates = <CheckoutOutboxState>{
  CheckoutOutboxState.savedOffline,
  CheckoutOutboxState.submitting,
  CheckoutOutboxState.awaitingConfirmation,
  CheckoutOutboxState.confirmed,
};

/// The states in which this device, and not the server, is the only holder of
/// the sale. [CheckoutOutboxState.confirmed] is deliberately absent: the server
/// acknowledged that one, so a published figure already counts it.
const Set<CheckoutOutboxState> _unsentOutboxStates = <CheckoutOutboxState>{
  CheckoutOutboxState.savedOffline,
  CheckoutOutboxState.submitting,
  CheckoutOutboxState.awaitingConfirmation,
};

final class _DeviceSale {
  const _DeviceSale({
    required this.id,
    required this.soldById,
    required this.businessDate,
    required this.payloadHash,
    required this.tender,
    required this.totalMinor,
    required this.lines,
  });

  factory _DeviceSale.fromCanonical(TenantSale sale) => _DeviceSale(
    id: sale.id,
    soldById: sale.soldById,
    businessDate: sale.businessDate,
    payloadHash: sale.payloadHash,
    tender: sale.tender,
    totalMinor: sale.totalMinor,
    lines: <_DeviceSaleLine>[
      for (final line in sale.lines)
        _DeviceSaleLine(
          categoryId: line.categoryId,
          revenueMinor: line.lineTotalMinor,
          costMinor: line.lineCostMinor,
        ),
    ],
  );

  factory _DeviceSale.fromOutbox(CheckoutSalePayload sale) => _DeviceSale(
    id: sale.checkoutId,
    soldById: sale.uid,
    businessDate: sale.businessDate,
    payloadHash: sale.payloadHash,
    tender: sale.tender,
    totalMinor: sale.totalMinor,
    lines: <_DeviceSaleLine>[
      for (final line in sale.lines)
        _DeviceSaleLine(
          categoryId: line.categoryId,
          revenueMinor: line.lineTotalMinor,
          costMinor: line.lineCostMinor,
        ),
    ],
  );

  final String id;
  final String soldById;
  final String businessDate;
  final String payloadHash;
  final CheckoutTender? tender;
  final int totalMinor;
  final List<_DeviceSaleLine> lines;

  bool matches(TenantSalesTotalsQuery query) =>
      businessDate.compareTo(query.startDate) >= 0 &&
      businessDate.compareTo(query.endDate) <= 0 &&
      (query.soldById == null || soldById == query.soldById);

  /// What this sale contributes, optionally net of what came back out of it.
  ///
  /// **The same shape `saleContribution` has on the server**, including the
  /// order of its refusals: a sale returned in full is not a transaction that
  /// happened, and it reports no cost completeness either because it
  /// contributed nothing to have a cost.
  _DeviceContribution contribution(
    String? categoryId, [
    TenantSaleReturnOffset? offset,
  ]) {
    final selected = categoryId == null
        ? lines
        : lines.where((line) => line.categoryId == categoryId).toList();
    if (categoryId != null && selected.isEmpty) {
      return const _DeviceContribution.empty();
    }
    if (offset != null && offset.isFullyReturned) {
      return const _DeviceContribution.empty();
    }
    var lineRevenue = 0;
    var cost = 0;
    var incomplete = 0;
    for (final line in selected) {
      lineRevenue += line.revenueMinor;
      if (line.costMinor == null) {
        incomplete += 1;
      } else {
        cost += line.costMinor!;
      }
    }
    final gross = categoryId == null ? totalMinor : lineRevenue;
    if (offset == null) {
      return _DeviceContribution(
        counted: true,
        revenueMinor: gross,
        costMinor: cost,
        incompleteCostLines: incomplete,
      );
    }
    // Cost comes back with the revenue, or the profit this implies - takings
    // minus cost - collapses by the whole price of the returned goods rather
    // than by the margin on them.
    return _DeviceContribution(
      counted: true,
      revenueMinor: _atLeastZero(gross - offset.returnedMinor),
      costMinor: _atLeastZero(cost - offset.returnedCostMinor),
      incompleteCostLines: _atLeastZero(
        incomplete - offset.fullyReturnedCostlessLines,
      ),
    );
  }
}

final class _DeviceSaleLine {
  const _DeviceSaleLine({
    required this.categoryId,
    required this.revenueMinor,
    required this.costMinor,
  });

  final String? categoryId;
  final int revenueMinor;
  final int? costMinor;
}

final class _DeviceContribution {
  const _DeviceContribution({
    required this.counted,
    required this.revenueMinor,
    required this.costMinor,
    required this.incompleteCostLines,
  });

  const _DeviceContribution.empty()
    : counted = false,
      revenueMinor = 0,
      costMinor = 0,
      incompleteCostLines = 0;

  final bool counted;
  final int revenueMinor;
  final int costMinor;
  final int incompleteCostLines;
}

final class _NeverSalesTotalsCallable implements SalesTotalsCallable {
  const _NeverSalesTotalsCallable();

  @override
  Future<Object?> call(Map<String, Object?> payload) =>
      throw StateError('A device totals query cannot invoke a callable.');
}

int _atLeastZero(int value) => value < 0 ? 0 : value;

/// One pass over the period's sales.
final class _DeviceAccumulation {
  const _DeviceAccumulation({
    required this.revenueMinor,
    required this.costMinor,
    required this.transactions,
    required this.incompleteCostLines,
    required this.tenderSalesMinor,
    required this.tenderTransactions,
  });

  final int revenueMinor;
  final int costMinor;
  final int transactions;
  final int incompleteCostLines;
  final Map<String, int> tenderSalesMinor;
  final Map<String, int> tenderTransactions;
}

/// What the cache holds about the period's returns.
final class _DeviceReturns {
  const _DeviceReturns({required this.units, required this.documentCount});

  /// Units returned per product, grouped by the sale each return reverses.
  final Map<String, Map<String, int>> units;

  /// How many return documents were read.
  final int documentCount;
}
