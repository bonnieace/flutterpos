import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../checkout/checkout_draft.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';

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

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('getSalesComparison')
        .call<Object?>(payload);
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
enum TenantSalesScope {
  /// Every sale the business recorded in the period.
  everyone('Whole business'),

  /// Only sales the signed-in member recorded, through the server's
  /// `soldById` filter. The UID comes from the captured session, never from a
  /// caller, so this can never be pointed at somebody else.
  mine('Only mine');

  const TenantSalesScope(this.label);

  final String label;
}

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

/// Strictly decoded totals for one period.
///
/// The response is reconciled against the query it answers. Without a category
/// the server counts one transaction per sale it read, so the two counts must
/// agree exactly; with one it skips a sale holding no matching line, so it may
/// count fewer but can never count more than it read. Either way a count the
/// query cannot explain describes some other request, and it is refused rather
/// than shown - this is the surface an owner reads takings from.
final class TenantSalesTotals {
  const TenantSalesTotals._({
    required this.query,
    required this.scannedTransactions,
    required this.sales,
    required this.profit,
    required this.transactions,
    required this.incompleteCostLineCount,
  });

  factory TenantSalesTotals.fromCallable(
    Object? value, {
    required TenantSalesTotalsQuery query,
  }) {
    final data = _strictMap(value, 'response');
    final previous = _strictMap(data['previous'], 'previous');
    final scanned = _requiredCount(data, 'scannedTransactions');
    if (scanned > maximumTransactions) {
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
    return TenantSalesTotals._(
      query: query,
      scannedTransactions: scanned,
      sales: _requiredNonNegativeNumber(previous, 'sales'),
      // Parsed so the figure is validated rather than ignored, and deliberately
      // never displayed: no product in this app carries a cost, so every sale
      // line reaches the server without one and the server's profit equals its
      // revenue. Showing it would be reporting a margin of 100%.
      profit: _requiredFiniteNumber(previous, 'profit'),
      transactions: transactions,
      incompleteCostLineCount: _requiredCount(
        previous,
        'incompleteCostLineCount',
      ),
    );
  }

  /// The server's `SALES_QUERY_LIMIT`; a period holding more is refused
  /// outright rather than answered from a truncated read.
  static const int maximumTransactions = 5000;

  /// The exact request these totals answer.
  final TenantSalesTotalsQuery query;

  /// How many sales the server read to produce this answer.
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

  /// Never displayed; see [TenantSalesTotals.fromCallable].
  final double profit;

  /// How many sales contributed to [sales].
  final int transactions;

  /// How many sale lines lacked the cost data a profit figure needs.
  final int incompleteCostLineCount;

  bool get hasCompleteCostData => incompleteCostLineCount == 0;
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
      session.canAccess(allowedRoles: allowedRoles);

  /// Resolves [period] and [scope] against the live session and the clock.
  ///
  /// Refused locally when the session may not read totals, so an unauthorized
  /// tap costs no round trip.
  TenantSalesTotalsQuery createQuery({
    required TenantSalesPeriod period,
    required TenantSalesScope scope,
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
    final soldById = switch (scope) {
      TenantSalesScope.everyone => null,
      TenantSalesScope.mine => _validatedSelfUid(),
    };
    return TenantSalesTotalsQuery._(
      tenantId: _session.tenantId,
      period: period,
      scope: scope,
      startDate: startDate,
      endDate: endDate,
      soldById: soldById,
      categoryId: categoryId == null ? null : _validatedCategoryId(categoryId),
    );
  }

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

  /// The signed-in member's own UID, as the server would accept it.
  ///
  /// A UID that is not a usable document ID would be rejected by the handler as
  /// an invalid argument, so it is refused here with the same meaning rather
  /// than sent and translated back.
  String _validatedSelfUid() {
    try {
      return validateTenantDocumentId(_session.uid, fieldName: 'uid');
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
    final Object? response;
    try {
      response = await _callable.call(query.toPayload());
    } on FirebaseFunctionsException catch (error) {
      throw TenantSalesTotalsException(_classify(error));
    } on TimeoutException {
      throw const TenantSalesTotalsException(
        TenantSalesTotalsFailure.unavailable,
      );
    } catch (_) {
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
TenantSalesTotalsFailure _classify(FirebaseFunctionsException error) =>
    switch (error.code) {
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
