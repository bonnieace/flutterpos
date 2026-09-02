import '../checkout/checkout_outbox.dart';
import '../checkout/checkout_sale.dart';
import '../checkout/checkout_tender.dart';
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
    required this.truncated,
    required this.refusal,
  });

  factory TenantDeviceSalesTotals.complete({
    required TenantSalesTotals queryTotals,
    required int scannedRecordCount,
  }) => TenantDeviceSalesTotals._(
    query: queryTotals.query,
    totals: queryTotals,
    scannedRecordCount: scannedRecordCount,
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
    truncated: false,
    refusal: reason,
  );

  final TenantSalesTotalsQuery query;
  final TenantSalesTotals? totals;
  final int scannedRecordCount;
  final bool truncated;
  final TenantDeviceSalesRefusal? refusal;

  TenantSalesTotalsBasis get basis => TenantSalesTotalsBasis.device;
  bool get canDisplay => totals != null;
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
       _queryFactory = TenantSalesTotalsGateway(
         session: session,
         callable: const _NeverSalesTotalsCallable(),
         clock: clock,
       );

  static const int _pageSize = 50;

  final TenantSession _session;
  final TenantSaleHistoryRepository _repository;
  final HiveCheckoutOutbox? _outbox;
  final TenantSalesTotalsGateway _queryFactory;

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
    final tenderSales = <String, int>{for (final key in buckets) key: 0};
    final tenderTransactions = <String, int>{for (final key in buckets) key: 0};
    var revenueMinor = 0;
    var costMinor = 0;
    var transactions = 0;
    var incompleteCosts = 0;
    for (final sale in merged.values) {
      if (!sale.matches(query)) continue;
      final contribution = sale.contribution(query.categoryId);
      if (!contribution.counted) continue;
      revenueMinor += contribution.revenueMinor;
      costMinor += contribution.costMinor;
      incompleteCosts += contribution.incompleteCostLines;
      transactions += 1;
      final bucket =
          sale.tender?.wireValue ?? TenantSalesTenderBreakdown.unrecordedBucket;
      final safeBucket = buckets.contains(bucket)
          ? bucket
          : TenantSalesTenderBreakdown.unrecognisedBucket;
      tenderSales[safeBucket] =
          tenderSales[safeBucket]! + contribution.revenueMinor;
      tenderTransactions[safeBucket] = tenderTransactions[safeBucket]! + 1;
    }
    final totals = TenantSalesTotals.fromDevice(
      query: query,
      scannedTransactions: merged.length,
      salesMinor: revenueMinor,
      costMinor: costMinor,
      transactions: transactions,
      incompleteCostLineCount: incompleteCosts,
      tenderSalesMinor: tenderSales,
      tenderTransactions: tenderTransactions,
    );
    return TenantDeviceSalesTotals.complete(
      queryTotals: totals,
      scannedRecordCount: merged.length,
    );
  }
}

const Set<CheckoutOutboxState> _includedOutboxStates = <CheckoutOutboxState>{
  CheckoutOutboxState.savedOffline,
  CheckoutOutboxState.submitting,
  CheckoutOutboxState.awaitingConfirmation,
  CheckoutOutboxState.confirmed,
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

  _DeviceContribution contribution(String? categoryId) {
    final selected = categoryId == null
        ? lines
        : lines.where((line) => line.categoryId == categoryId).toList();
    if (categoryId != null && selected.isEmpty) {
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
    return _DeviceContribution(
      counted: true,
      revenueMinor: categoryId == null ? totalMinor : lineRevenue,
      costMinor: cost,
      incompleteCostLines: incomplete,
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
