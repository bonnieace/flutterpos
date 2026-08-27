/// Reading expenses back, over a stretch of business dates.
///
/// **Why this is a cursor walk and not a query.** `TenantReadRepository` orders
/// every page by document ID and accepts only `field == value` filters; a range
/// is not reachable from a client repository at all, by design - the boundary
/// exists so no caller can compose a query the tenant proof cannot check. An
/// expense ID begins with its business date (`tenantExpenseId`), so ascending
/// document-ID order *is* chronological order, and a date range becomes a
/// starting cursor plus a stop condition. Nothing about the boundary is bent,
/// and no composite index is needed: the walk carries no equality filter.
library;

import '../checkout/checkout_receipt.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import 'expense.dart';

/// Reads one business's expenses.
final class TenantExpenseRepository extends TenantReadRepository {
  TenantExpenseRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;

  /// Who may read an expense.
  ///
  /// **Deliberately identical to `TenantProfitReport.allowedRoles`**, at the
  /// product owner's direction on 2026-08-27: whoever records an expense can
  /// read back what it did to profit, and nobody writes into a figure they are
  /// not shown. It is narrower than the roles that may read the takings, for
  /// the same reason a buying price is - an expense is cost.
  ///
  /// The matching Firestore rule enforces this on the server. Unlike
  /// `daily_metrics`, which a manager's device already holds in full, this is a
  /// real boundary rather than a surface one.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  static bool canSeeInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// How many records one range read will walk before it gives up.
  ///
  /// Five pages of fifty. A business recording more than 250 expenses in one
  /// period is not one this read can total, and it says so rather than
  /// returning a smaller number that looks like an answer.
  static const int maximumRangeRecords = 250;

  static const int _pageSize = 50;

  /// Every expense filed between [startDate] and [endDate], both inclusive.
  ///
  /// Records come back newest first, which is the order a person reads a list
  /// of them in. Voided records are included - the caller shows them struck
  /// through - and `TenantExpensePeriod` excludes them from every total.
  ///
  /// This is a Firestore read and serves from the offline cache, which is the
  /// whole reason net profit is composed on the client rather than asked of a
  /// callable: a shop with no signal can still see what it spent.
  Future<TenantExpensePeriod> readRange({
    required String startDate,
    required String endDate,
  }) async {
    final String safeStart;
    final String safeEnd;
    try {
      safeStart = validateCheckoutBusinessDate(startDate);
      safeEnd = validateCheckoutBusinessDate(endDate);
    } on ArgumentError {
      throw const TenantExpenseException('invalid_expense_range');
    }
    if (safeStart.compareTo(safeEnd) > 0) {
      throw const TenantExpenseException('invalid_expense_range');
    }

    // **The start date itself is the cursor**, and it is `startAfter` rather
    // than `startAt` on purpose. Every ID on that day is `{date}-{token}`,
    // which sorts strictly after the bare `{date}` because a prefix comes
    // first - so nothing on the opening day is skipped, and everything before
    // it is. The cursor is a position rather than a document, so a start date
    // with no expenses on it is perfectly valid.
    var cursor = safeStart;
    final records = <TenantExpense>[];
    var truncated = false;

    while (true) {
      final page = await readCollectionPage(
        TenantCollection.expenses,
        collectionReader: _collectionReader,
        pageSize: _pageSize,
        cursor: cursor,
      );
      var pastEnd = false;
      for (final snapshot in page.items) {
        final record = TenantExpense.fromDocument(
          path: snapshot.path,
          data: snapshot.data,
        );
        if (record.tenantId != session.tenantId) {
          throw const TenantExpenseException('cross_tenant_expense');
        }
        // The key is what the walk is ordered on, so the key is what decides
        // the period has been left. `TenantExpense.fromDocument` has already
        // proved the stored field agrees with it.
        if (record.businessDate.compareTo(safeEnd) > 0) {
          pastEnd = true;
          break;
        }
        records.add(record);
      }
      if (pastEnd || !page.hasMore || page.nextCursor == null) break;
      if (records.length >= maximumRangeRecords) {
        // There is more of this period than this read can hold. What is held
        // is a partial total, and a partial expense total overstates profit,
        // so the shortfall travels with the result.
        truncated = true;
        break;
      }
      cursor = page.nextCursor!;
    }

    return TenantExpensePeriod(
      startDate: safeStart,
      endDate: safeEnd,
      // The walk is chronological because the ordering key is; a list is read
      // newest first.
      records: records.reversed.toList(),
      truncated: truncated,
    );
  }

  /// One business date's expenses.
  Future<TenantExpensePeriod> readDay(String businessDate) =>
      readRange(startDate: businessDate, endDate: businessDate);
}
