import 'package:cloud_firestore/cloud_firestore.dart';

import '../checkout/checkout_draft.dart';
import '../checkout/checkout_receipt.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_types.dart';

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
      // data whose completeness `incompleteCostLineCount` reports. It is parsed
      // so a later surface can use it; no screen displays it yet.
      profit: _requiredFiniteNumber(data, 'profit'),
      transactions: transactions,
      shiftCount: _requiredInt(data, 'shiftCount'),
      incompleteCostLineCount: _requiredInt(data, 'incompleteCostLineCount'),
      metricGeneration: _requiredGeneration(data),
      sourceDirtyRevision: _requiredInt(data, 'sourceDirtyRevision'),
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

  /// Whether the day's cost data was complete enough to trust a profit figure.
  bool get hasCompleteCostData => incompleteCostLineCount == 0;
}

/// One business day, reconciled or not.
///
/// An unreconciled day is a first-class result rather than an absence. Today is
/// normally unreconciled, and a report that silently omitted it would read as
/// though the business recorded nothing.
final class TenantDailyMetricsDay {
  const TenantDailyMetricsDay({
    required this.businessDate,
    required this.metrics,
  });

  final String businessDate;
  final TenantDailyMetrics? metrics;

  bool get isReconciled => metrics != null;
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
    final String safeDate;
    try {
      safeDate = validateCheckoutBusinessDate(businessDate);
    } on ArgumentError {
      throw const TenantDailyMetricsException('invalid_business_date');
    }
    final data = await readDocument(
      TenantCollection.dailyMetrics,
      safeDate,
    );
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
    final results = <TenantDailyMetricsDay>[];
    for (var offset = 0; offset < days; offset++) {
      // Subtracting whole days from the UTC instant is exact for a fixed-offset
      // business day, so the Africa/Nairobi boundary is respected without any
      // date arithmetic of our own.
      final businessDate = checkoutBusinessDate(
        now.subtract(Duration(days: offset)),
      );
      results.add(
        TenantDailyMetricsDay(
          businessDate: businessDate,
          metrics: await readDay(businessDate),
        ),
      );
    }
    return List<TenantDailyMetricsDay>.unmodifiable(results);
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

const int _maximumCount = 1000000000;
const double _maximumMoney = 1000000000000;

DateTime _utcNow() => DateTime.now().toUtc();
