import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_directory.dart';
import 'reporting_currency.dart';
import '../expenses/expense.dart';
import '../shift/shift_history.dart';
import 'net_profit.dart';
import 'sales_totals.dart';
import '../observability/app_telemetry.dart';

/// The categories one session may filter by, and whether they could be read.
///
/// An unreadable list is not a failure of the totals route: the whole-business
/// figure does not depend on it, so the filter disappears and the total stays.
final class SalesTotalsCategoryOptions {
  const SalesTotalsCategoryOptions({
    required this.items,
    required this.readable,
    required this.truncated,
  });

  const SalesTotalsCategoryOptions.unreadable()
    : items = const <TenantCategory>[],
      readable = false,
      truncated = false;

  final List<TenantCategory> items;
  final bool readable;

  /// Whether the business holds more categories than [items] lists.
  ///
  /// **Carried for the same reason `SalesTotalsStaffOptions.truncated` is.** One
  /// bounded page is read, and a business past that bound had valid categories
  /// simply absent from the chooser with nothing on the page to say so - which
  /// is a filter that looks complete and is not. The staff chooser has said this
  /// since it was written; the categories were never brought into line with it.
  final bool truncated;

  String? nameOf(String categoryId) {
    for (final category in items) {
      if (category.id == categoryId) return category.name;
    }
    return null;
  }
}

/// The colleagues one session may total separately, and their display names.
///
/// A member who has left the business is deliberately still offered: their
/// sales are still in the period, and hiding them would make the per-member
/// figures fail to add up to the whole-business one.
final class SalesTotalsStaffOptions {
  const SalesTotalsStaffOptions({
    required this.uids,
    required this.names,
    required this.readable,
    required this.truncated,
  });

  const SalesTotalsStaffOptions.unreadable()
    : uids = const <String>[],
      names = const <String, String>{},
      readable = false,
      truncated = false;

  final List<String> uids;

  /// Display names by UID. A member with no recorded name is deliberately
  /// absent so the label degrades to the authoritative UID; a staff record also
  /// carries an email and a phone number, and a report label is not the place
  /// to disclose either.
  final Map<String, String> names;

  final bool readable;

  /// Whether the business has more staff than one page offers.
  final bool truncated;

  bool contains(String uid) => uids.contains(uid);
}

/// The three session-scoped reads the totals surface labels its figures with.
///
/// They are grouped because they obey one rule, stated once in
/// [SalesTotalsSessionContextLoader]: degrade on failure, rethrow a
/// [TenantScopeViolation], and cache by UID, tenant, and epoch. A fourth
/// session-scoped read on this route should join them rather than invent a
/// fourth policy.
final class SalesTotalsSessionContext {
  const SalesTotalsSessionContext({
    required this.categories,
    required this.staff,
    required this.currency,
  });

  /// What a surface shows before anything has been read, and after a failure
  /// that happened before these reads completed.
  static const SalesTotalsSessionContext empty = SalesTotalsSessionContext(
    categories: SalesTotalsCategoryOptions.unreadable(),
    staff: SalesTotalsStaffOptions.unreadable(),
    currency: TenantReportingCurrency.unknown,
  );

  final SalesTotalsCategoryOptions categories;
  final SalesTotalsStaffOptions staff;
  final TenantReportingCurrency currency;
}

/// One period's totals together with the context they are labelled by.
final class SalesTotalsView {
  const SalesTotalsView({
    required this.totals,
    required this.context,
    this.expenses,
    this.shifts = const <TenantShiftDaySlice>[],
  });

  final TenantSalesTotals totals;
  final SalesTotalsSessionContext context;

  /// What the business spent over the same stretch of days, or null where it
  /// was not read.
  ///
  /// **Never read for a filtered view, and that is a correctness rule rather
  /// than a saving.** An expense belongs to the business and to a date; it
  /// belongs to no colleague and to no product category. Subtracting the whole
  /// shop's rent from one cashier's takings, or from the gross profit of one
  /// category, produces a number that looks like net profit and is not one.
  /// So the loader reads spending only for the unfiltered, whole-business
  /// view, and every filtered view shows gross alone.
  final TenantExpensePeriod? expenses;

  /// The shifts of the day, where the period **is** a single day.
  ///
  /// **Empty for every longer period, and not because the read failed.** A
  /// shift belongs to one business date and `ShiftClosingSummary` is a
  /// per-shift total rather than a per-cashier one, so summing shifts across a
  /// stretch would put one cashier in several columns. The loader therefore
  /// asks only when the period is *Today*; see `ShiftComparisonChart`.
  final List<TenantShiftDaySlice> shifts;

  /// This period after everything the business spent, or null where either
  /// half is missing.
  TenantNetProfitReport? get netProfitReport {
    final spending = expenses;
    if (spending == null) return null;
    return TenantNetProfitReport.from(
      gross: totals.profitReport,
      expenses: spending,
    );
  }
}

/// Reads this session's categories, colleagues, and currency once each.
///
/// The figure a manager came for depends on none of the three, so an unreadable
/// one removes that affordance and says so rather than replacing the total with
/// an error. A [TenantScopeViolation] is the single exception and is rethrown
/// from every one of them: a reader answering outside this tenant is a broken
/// boundary, not an unavailable label.
final class SalesTotalsSessionContextLoader {
  SalesTotalsSessionContextLoader({
    required this.reader,
    this.categoryPageSize = 50,
    this.staffPageSize = 25,
  });

  final TenantDataReader reader;

  /// The most categories offered as filters, in one page.
  final int categoryPageSize;

  /// The most colleagues offered as filters, in one page.
  final int staffPageSize;

  String? _cacheKey;
  SalesTotalsSessionContext? _cached;

  /// Whatever has been read for the current session, or `null` before any read
  /// completed. A surface showing a failure uses it so the choosers it already
  /// had do not disappear along with the figure.
  SalesTotalsSessionContext? get cached => _cached;

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  /// Returns the context for [session], reading it at most once per session.
  ///
  /// Nothing is cached until all three reads have finished, so a rethrown
  /// scope violation can never leave a half-built context behind.
  Future<SalesTotalsSessionContext> load(TenantSession session) async {
    final key = _sessionKey(session);
    if (key == _cacheKey && _cached != null) return _cached!;
    final categories = await _readCategories(session);
    final staff = await _readStaff(session);
    final currency = await TenantReportingCurrency.read(
      session: session,
      reader: reader,
    );
    final context = SalesTotalsSessionContext(
      categories: categories,
      staff: staff,
      currency: currency,
    );
    _cacheKey = key;
    return _cached = context;
  }

  Future<SalesTotalsCategoryOptions> _readCategories(
    TenantSession session,
  ) async {
    try {
      final page = await TenantCatalogRepository(
        session: session,
        reader: reader,
      ).loadCategories(pageSize: categoryPageSize);
      return SalesTotalsCategoryOptions(
        items: page.items,
        readable: true,
        truncated: page.hasMore,
      );
    } on TenantScopeViolation {
      rethrow;
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'reporting.category_options_read',
      );
      return const SalesTotalsCategoryOptions.unreadable();
    }
  }

  /// Reads one bounded page of this business's canonical staff.
  ///
  /// Only management may read the whole roster, and only management reaches the
  /// totals route, so the two agree. A page that cannot be read leaves
  /// "everyone" and "only mine" working, because both are answerable from the
  /// session alone.
  Future<SalesTotalsStaffOptions> _readStaff(TenantSession session) async {
    try {
      final page = await TenantStaffDirectoryRepository(
        session: session,
        reader: reader,
      ).loadPage(pageSize: staffPageSize);
      return SalesTotalsStaffOptions(
        uids: <String>[for (final member in page.items) member.uid],
        names: <String, String>{
          for (final member in page.items)
            if (member.name case final name?) member.uid: name,
        },
        readable: true,
        truncated: page.hasMore,
      );
    } on TenantScopeViolation {
      rethrow;
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'reporting.staff_options_read',
      );
      return const SalesTotalsStaffOptions.unreadable();
    }
  }
}
