import 'package:cloud_firestore/cloud_firestore.dart';

import '../checkout/checkout_draft.dart';
import '../checkout/checkout_receipt.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_types.dart';
import 'profit_report.dart';
import 'reconciliation_status.dart';

/// Raised when a canonical daily metric document cannot be trusted.
final class TenantDailyMetricsException implements Exception {
  const TenantDailyMetricsException(this.code);

  final String code;

  @override
  String toString() => 'TenantDailyMetricsException($code)';
}

/// Strict read model for `tenants/{tenantId}/daily_metrics/{businessDate}`.
///
/// Nightly reconciliation is the only writer. The client reports these figures
/// exactly as regenerated and never computes a replacement: a device holds only
/// its own sales, so any total it derived would disagree with the server's for
/// every business that uses more than one device.
final class TenantDailyMetrics {
  factory TenantDailyMetrics.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.dailyMetrics.segment) {
      throw const TenantDailyMetricsException('invalid_metrics_path');
    }
    final String tenantId;
    final String businessDate;
    try {
      tenantId = validateTenantId(segments[1]);
      businessDate = validateCheckoutBusinessDate(segments[3]);
    } on ArgumentError {
      throw const TenantDailyMetricsException('invalid_metrics_path');
    }
    // The document repeats the identity its own path encodes, so a metric can
    // never be presented under a day or a business it does not describe.
    if (data['tenantId'] != tenantId || data['businessDate'] != businessDate) {
      throw const TenantDailyMetricsException('metrics_identity_mismatch');
    }

    final transactions = _requiredInt(data, 'transactions');
    // The writer stores the same count twice. If the copies disagree the
    // document was not written by the reconciliation processor.
    if (_requiredInt(data, 'transactionCount') != transactions) {
      throw const TenantDailyMetricsException('inconsistent_metrics');
    }
    return TenantDailyMetrics._(
      tenantId: tenantId,
      businessDate: businessDate,
      sales: _requiredNonNegativeNumber(data, 'sales'),
      // Profit may legitimately be negative, and it depends on product cost
      // data whose completeness `incompleteCostLineCount` reports. Whether it
      // may be shown is [profitReport]'s decision, never this decoder's.
      profit: _requiredFiniteNumber(data, 'profit'),
      transactions: transactions,
      shiftCount: _requiredInt(data, 'shiftCount'),
      incompleteCostLineCount: _requiredInt(data, 'incompleteCostLineCount'),
      metricGeneration: _requiredGeneration(data),
      sourceDirtyRevision: _requiredInt(data, 'sourceDirtyRevision'),
      net: _requiredNet(
        data,
        grossSales: _requiredNonNegativeNumber(data, 'sales'),
        grossProfit: _requiredFiniteNumber(data, 'profit'),
        grossTransactions: transactions,
      ),
      regeneratedAt: _requiredInstant(data, 'regeneratedAt'),
    );
  }

  const TenantDailyMetrics._({
    required this.tenantId,
    required this.businessDate,
    required this.sales,
    required this.profit,
    required this.transactions,
    required this.shiftCount,
    required this.incompleteCostLineCount,
    required this.metricGeneration,
    required this.sourceDirtyRevision,
    required this.regeneratedAt,
    required this.net,
  });

  final String tenantId;
  final String businessDate;

  /// Major-unit revenue, exactly as reconciliation recorded it.
  final double sales;
  final double profit;
  final int transactions;
  final int shiftCount;

  /// How many sale lines lacked the cost data a profit figure needs.
  final int incompleteCostLineCount;
  final String metricGeneration;
  final int sourceDirtyRevision;

  /// When reconciliation last regenerated this day.
  ///
  /// Required, unlike the pending-write instants on a shift or a sale: the
  /// client never writes this document, so there is no state in which a
  /// server-owned timestamp is legitimately missing.
  final DateTime regeneratedAt;

  /// The same day with its returns taken back out.
  ///
  /// **Required (#104).** It was nullable while days reconciled before returns
  /// were counted were still about; reconciliation writes the block on every
  /// run with `merge: false`, and SIT regenerates rather than migrating, so a
  /// day that cannot state its netting is a document this surface refuses.
  final TenantDailyMetricsNet net;

  /// Whether the day's cost data was complete enough to trust a profit figure.
  bool get hasCompleteCostData => incompleteCostLineCount == 0;

  /// Takings after returns.
  double get netSales => net.sales;

  /// The transaction count on the same basis as [netSales].
  int get netTransactions => net.transactions;

  /// The profit report on the same basis as [netSales].
  TenantProfitReport get netProfitReport => net.profitReport;

  /// This day's profit, and whether it may be shown at all.
  ///
  /// The same type the period totals produce, so one day and a stretch of days
  /// cannot answer that question differently.
  TenantProfitReport get profitReport => TenantProfitReport.from(
    sales: sales,
    profit: profit,
    incompleteCostLineCount: incompleteCostLineCount,
  );
}

/// One reconciled day with its returns taken back out.
///
/// **Optional on read, all-or-nothing as a group.** Days reconciled before
/// returns were counted carry none of these fields, and that is not a failure
/// - it is a day whose figures are gross, which a surface must be able to say
/// rather than imply nothing came back. A *half* written block is a different
/// thing entirely: it is a writer defect, and this decoder's whole posture is
/// to refuse a document its writer would not have produced.
final class TenantDailyMetricsNet {
  const TenantDailyMetricsNet._({
    required this.sales,
    required this.profit,
    required this.transactions,
    required this.incompleteCostLineCount,
    required this.returnedSales,
    required this.returnCount,
  });

  final double sales;
  final double profit;
  final int transactions;
  final int incompleteCostLineCount;

  /// What came back over the day.
  final double returnedSales;

  /// How many return documents the day held.
  final int returnCount;

  /// The same trust question the gross figure answers, of the net one.
  TenantProfitReport get profitReport => TenantProfitReport.from(
    sales: sales,
    profit: profit,
    incompleteCostLineCount: incompleteCostLineCount,
  );
}

/// Where one day's published totals stand against the sales the server holds.
///
/// **A published figure is not the same as a current one**, and until this
/// existed the daily summary could not tell them apart. `daily_metrics` is
/// written with `merge: false` and is never deleted, so a later sale that marks
/// the day dirty again leaves the previous document exactly where it was. The
/// intake record is the only thing that knows the difference.
enum TenantDailyMetricsStanding {
  /// Reconciliation has never published this day. Today is normally here.
  unpublished,

  /// Published, and the intake record proves the figures cover every sale it
  /// has seen: it is clean, and at the revision the metrics were built from.
  current,

  /// Published, but the server has since taken more sales for this day, or
  /// stopped working on it. The figures are real and they are out of date.
  superseded,

  /// Published, but the intake record could not be read, so nothing here can
  /// say whether the figures are current.
  ///
  /// **Deliberately not folded into [current].** Every sale writes an intake
  /// record, so a published day without one is not a quiet day - it is a read
  /// that did not answer, and treating silence as confirmation is the whole
  /// failure this enum exists to stop.
  unconfirmed,
}

/// One business day, and what its published figures are worth.
///
/// An unreconciled day is a first-class result rather than an absence. Today is
/// normally unreconciled, and a report that silently omitted it would read as
/// though the business recorded nothing.
final class TenantDailyMetricsDay {
  const TenantDailyMetricsDay({
    required this.businessDate,
    required this.metrics,
    this.intake,
  });

  final String businessDate;
  final TenantDailyMetrics? metrics;

  /// The server's own record of what it has taken for this day, or null where
  /// it does not exist or could not be read.
  final TenantReconciliationIntake? intake;

  /// Whether anything has been published for this day at all.
  ///
  /// **Not a claim that it is current** - that is [standing]. Kept because a
  /// surface drawing the figures needs to know they exist, which is a different
  /// question from whether to believe them.
  bool get isPublished => metrics != null;

  TenantDailyMetricsStanding get standing {
    final metrics = this.metrics;
    if (metrics == null) return TenantDailyMetricsStanding.unpublished;
    final intake = this.intake;
    if (intake == null) return TenantDailyMetricsStanding.unconfirmed;
    // Both halves are required. `hasUnpublishedSales` catches a day the server
    // has taken more sales for; the revision comparison catches a regeneration
    // that published an older revision than the one the intake now names. A
    // quarantined day is out of date by definition - the server stopped.
    if (intake.hasUnpublishedSales ||
        intake.status == TenantReconciliationIntakeStatus.dirty ||
        intake.status == TenantReconciliationIntakeStatus.quarantined ||
        metrics.sourceDirtyRevision != intake.revision) {
      return TenantDailyMetricsStanding.superseded;
    }
    return TenantDailyMetricsStanding.current;
  }
}

/// Guarded read boundary over one tenant's regenerated daily metrics.
///
/// Days are read by exact document path rather than by query, because a query
/// cannot return a day that has no document yet, and hiding an unreconciled day
/// is exactly the failure this surface must not have.
final class TenantDailyMetricsRepository extends TenantReadRepository {
  TenantDailyMetricsRepository({
    required super.session,
    required super.reader,
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  /// The roles that may read business-wide revenue.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  /// The most business days one load may read, one document each.
  static const int maximumDays = 14;

  final DateTime Function() _clock;

  /// Reads one exact business day, or `null` when it is not reconciled yet.
  Future<TenantDailyMetrics?> readDay(String businessDate) async {
    final safeDate = _validatedDate(businessDate);
    return _decodeDay(
      safeDate,
      await readDocument(TenantCollection.dailyMetrics, safeDate),
    );
  }

  String _validatedDate(String businessDate) {
    try {
      return validateCheckoutBusinessDate(businessDate);
    } on ArgumentError {
      throw const TenantDailyMetricsException('invalid_business_date');
    }
  }

  /// Turns what the document said into metrics, refusing anything that does
  /// not describe this business coherently.
  TenantDailyMetrics? _decodeDay(String safeDate, Map<String, Object?>? data) {
    if (data == null) return null;
    final metrics = TenantDailyMetrics.fromDocument(
      path: paths.dailyMetric(safeDate),
      data: data,
    );
    if (metrics.tenantId != session.tenantId) {
      throw const TenantDailyMetricsException('cross_tenant_metrics');
    }
    return metrics;
  }

  /// Reads the most recent [days] business days, newest first.
  Future<List<TenantDailyMetricsDay>> loadRecentDays({int days = 7}) async {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantDailyMetricsException('metrics_forbidden');
    }
    if (days < 1 || days > maximumDays) {
      throw RangeError.range(days, 1, maximumDays, 'days');
    }
    final now = _clock().toUtc();
    final dates = <String>[
      for (var offset = 0; offset < days; offset++)
        // Subtracting whole days from the UTC instant is exact for a
        // fixed-offset business day, so the Africa/Nairobi boundary is
        // respected without any date arithmetic of our own.
        checkoutBusinessDate(now.subtract(Duration(days: offset))),
    ];
    // **Started together rather than one after another.** This awaited one
    // document at a time, and reading the intake record beside each metric
    // would have doubled a fourteen-round-trip page to twenty-eight. They do
    // not depend on each other. `Future.wait` also attaches to every future
    // before any can complete, so a rejection cannot be left unhandled.
    final settled = await Future.wait(<Future<Object?>>[
      for (final date in dates) _readPublishedDay(date),
      for (final date in dates) _readIntake(date),
    ]);
    return List<TenantDailyMetricsDay>.unmodifiable(<TenantDailyMetricsDay>[
      for (var index = 0; index < dates.length; index++)
        TenantDailyMetricsDay(
          businessDate: dates[index],
          metrics: settled[index] as TenantDailyMetrics?,
          intake: settled[dates.length + index] as TenantReconciliationIntake?,
        ),
    ]);
  }

  /// [readDay], except that a day this device could not reach reads as one
  /// with nothing published.
  ///
  /// **It is the offline case that made this necessary.** Firestore refuses a
  /// document `get` it holds no cached copy of rather than answering that the
  /// document is absent, so the first business day of a stretch with no signal
  /// throws - and `Future.wait` fails the whole set on the first rejection, so
  /// one unreachable day took every other day with it. The home swallows that
  /// and draws no figures at all, which is the one state that page is built
  /// never to be in; the daily summary loses the week.
  ///
  /// **The guard is around the read and never around the decode**, which is
  /// the whole of the distinction. *This device could not ask* is a gap, and a
  /// gap is what `TenantDailyMetricsDay.metrics` being null already means.
  /// *The document answered, and what it said does not add up* is a fault, and
  /// the daily summary fails closed on it with a retry rather than drawing a
  /// day as unreconciled that the server has in fact reconciled - see
  /// `daily_metrics_panel.dart`. Deciding that by exception type would mean
  /// enumerating every way a decoder can fail; deciding it by which half threw
  /// cannot drift.
  ///
  /// **Per day rather than around the whole set**, so a day that did read is
  /// still reported. The role gate in [loadRecentDays] is outside this too:
  /// being refused the figures is an answer, not a gap.
  Future<TenantDailyMetrics?> _readPublishedDay(String businessDate) async {
    final safeDate = _validatedDate(businessDate);
    final Map<String, Object?>? data;
    try {
      data = await readDocument(TenantCollection.dailyMetrics, safeDate);
    } on Object {
      return null;
    }
    return _decodeDay(safeDate, data);
  }

  /// What the server has taken for one day, or null where it cannot be read.
  ///
  /// **Decoded by `TenantReconciliationIntake`, not by anything written here.**
  /// The reconciliation surface already owns what this document means, down to
  /// refusing one whose processed revision runs ahead of its own; a second
  /// decoder is a second opinion about the only record that can say whether
  /// these figures are current.
  ///
  /// A failure degrades to null rather than taking the page. The figures are
  /// what a reader came for, and a day that cannot prove itself current is
  /// reported as [TenantDailyMetricsStanding.unconfirmed] - which is a weaker
  /// claim than the one this surface used to make for free.
  Future<TenantReconciliationIntake?> _readIntake(String businessDate) async {
    try {
      final data = await readDocument(
        TenantCollection.reconciliationDirtyDays,
        businessDate,
      );
      if (data == null) return null;
      final intake = TenantReconciliationIntake.fromDocument(
        path: paths.reconciliationDirtyDay(businessDate),
        data: data,
      );
      return intake.tenantId == session.tenantId ? intake : null;
    } on Object {
      return null;
    }
  }
}

int _requiredInt(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value < 0 || value > _maximumCount) {
    throw const TenantDailyMetricsException('invalid_metrics_document');
  }
  return value;
}

double _requiredNonNegativeNumber(Map<String, Object?> data, String field) {
  final value = _requiredFiniteNumber(data, field);
  if (value < 0) {
    throw const TenantDailyMetricsException('invalid_metrics_document');
  }
  return value;
}

double _requiredFiniteNumber(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! num || !value.isFinite || value.abs() > _maximumMoney) {
    throw const TenantDailyMetricsException('invalid_metrics_document');
  }
  return value.toDouble();
}

String _requiredGeneration(Map<String, Object?> data) {
  final value = data['metricGeneration'];
  if (value is! String || value.isEmpty || value.length > 128) {
    throw const TenantDailyMetricsException('invalid_metrics_document');
  }
  return value;
}

DateTime _requiredInstant(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantDailyMetricsException('invalid_metrics_document');
}

/// The net block of one metric document.
///
/// Every check here is the same kind the surrounding decoder already makes:
/// a document that contradicts itself describes some other day, and this is
/// the surface an owner reads takings from.
TenantDailyMetricsNet _requiredNet(
  Map<String, Object?> data, {
  required double grossSales,
  required double grossProfit,
  required int grossTransactions,
}) {
  const fields = <String>[
    'netSales',
    'netProfit',
    'netTransactions',
    'netIncompleteCostLineCount',
    'returnedSales',
    'returnCount',
    'netMetricsVersion',
  ];
  // #104: the whole block or nothing. A day missing any of it was written by
  // a deployment SIT no longer runs.
  if (data.keys.where(fields.contains).length != fields.length) {
    throw const TenantDailyMetricsException('invalid_metrics_document');
  }
  // A future shape must not be read as this one.
  if (_requiredInt(data, 'netMetricsVersion') != 1) {
    throw const TenantDailyMetricsException('invalid_metrics_document');
  }

  final sales = _requiredNonNegativeNumber(data, 'netSales');
  final profit = _requiredFiniteNumber(data, 'netProfit');
  final transactions = _requiredInt(data, 'netTransactions');
  final returnedSales = _requiredNonNegativeNumber(data, 'returnedSales');
  final salesMinor = reportingMinorUnits(sales);
  final grossSalesMinor = reportingMinorUnits(grossSales);
  if (salesMinor > grossSalesMinor || transactions > grossTransactions) {
    throw const TenantDailyMetricsException('invalid_metrics_document');
  }
  // Exact, in whole minor units: what came back is the difference, and a
  // document where it is not is not describing one day.
  if (grossSalesMinor - salesMinor != reportingMinorUnits(returnedSales)) {
    throw const TenantDailyMetricsException('invalid_metrics_document');
  }
  // **The check that catches a revenue-netted-without-cost regression.**
  // Cost is derived, so netting takings alone drives it down and eventually
  // negative - which is exactly the figure `TenantProfitBasis.inconsistent`
  // exists to refuse, arriving here instead as a document that cannot be
  // believed.
  final netCostMinor = salesMinor - reportingMinorUnits(profit);
  final grossCostMinor = grossSalesMinor - reportingMinorUnits(grossProfit);
  if (netCostMinor < 0 || netCostMinor > grossCostMinor) {
    throw const TenantDailyMetricsException('invalid_metrics_document');
  }

  return TenantDailyMetricsNet._(
    sales: sales,
    profit: profit,
    transactions: transactions,
    incompleteCostLineCount: _requiredInt(data, 'netIncompleteCostLineCount'),
    returnedSales: returnedSales,
    returnCount: _requiredInt(data, 'returnCount'),
  );
}

const int _maximumCount = 1000000000;
const double _maximumMoney = 1000000000000;

DateTime _utcNow() => DateTime.now().toUtc();
