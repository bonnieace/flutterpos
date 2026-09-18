/// One calendar month of takings, and the month before it.
///
/// **Why this is not the weekly report with a bigger number.**
/// `TenantWeeklyReportLoader` asks the totals callable **once per elapsed day**
/// so it can draw a bar per weekday, then once more for the week before, then
/// walks the week's sale lines for the top-items roll-up. That is eight or nine
/// requests for seven days and it is affordable. The same shape over a month is
/// thirty-one requests plus the comparison - and the sale walk behind *top
/// items* would be a month of sale documents against a scan cap the server
/// enforces at five thousand.
///
/// So this asks **twice**: one range for the month, one for the month before.
/// The price of that is the two readings the per-day requests paid for - there
/// is no per-day chart here and no top-items list. What is left is the reading
/// a month is actually closed on: what was taken, over how many sales, how it
/// split across the ways it was paid for, and whether that is up or down on the
/// month before.
///
/// **Business time, not device time.** Every date here is the Africa/Nairobi
/// business date the till stamps on a sale, cut on the same boundary, for the
/// reason `TenantReportWeek` gives about a Sunday-evening sale landing in the
/// wrong week.
library;

import '../checkout/checkout_draft.dart';
import '../tenancy/tenant_session.dart';
import 'sales_totals.dart';

/// One calendar month, named by how many months back it is.
final class TenantReportMonth {
  const TenantReportMonth._(this.offset, this._first);

  /// The month containing [nowUtc], and [offset] months before it.
  factory TenantReportMonth.at(DateTime nowUtc, {int offset = 0}) {
    final business = nowUtc.toUtc().add(checkoutBusinessDayOffset);
    // Day 1 of the business month, then shifted whole months. `DateTime.utc`
    // normalises a month of 0 or 13 into the neighbouring year, so no
    // arithmetic here has to know where a year ends.
    final first = DateTime.utc(business.year, business.month + offset, 1);
    return TenantReportMonth._(offset, first);
  }

  /// 0 is the month in progress, -1 the one before it. Never positive: the page
  /// refuses to page forward past the current month, because the callable
  /// refuses a future business date outright.
  final int offset;

  final DateTime _first;

  DateTime get first => _first;

  /// The last calendar day of this month.
  ///
  /// Day 0 of the *next* month, which is the last day of this one whatever its
  /// length and whether or not February has 29.
  DateTime get last => DateTime.utc(_first.year, _first.month + 1, 0);

  bool get isCurrent => offset == 0;

  TenantReportMonth get previous =>
      TenantReportMonth._(offset - 1, DateTime.utc(_first.year, _first.month - 1, 1));

  TenantReportMonth get next =>
      TenantReportMonth._(offset + 1, DateTime.utc(_first.year, _first.month + 1, 1));

  String get startBusinessDate => _dateOf(_first);
  String get endBusinessDate => _dateOf(last);

  /// The last day this month may be asked about, clamped to today.
  ///
  /// The month in progress has not finished, and the callable refuses a future
  /// business date rather than answering an empty report - so a month is asked
  /// only for the days it has.
  String endBusinessDateAt(DateTime nowUtc) {
    final today = checkoutBusinessDate(nowUtc);
    final end = endBusinessDate;
    return end.compareTo(today) > 0 ? today : end;
  }

  /// Whether this month has begun at all, given [nowUtc].
  ///
  /// A month whose first day is still in the future has no range to ask about;
  /// clamping would produce an end before its own start, which the gateway
  /// refuses as an invalid request rather than an empty one.
  bool hasBegun(DateTime nowUtc) =>
      startBusinessDate.compareTo(checkoutBusinessDate(nowUtc)) <= 0;

  /// `July 2026`, for the chooser and the header.
  String get label => '${_monthNames[_first.month - 1]} ${_first.year}';

  static const List<String> _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _dateOf(DateTime day) {
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '${day.year.toString().padLeft(4, '0')}-$month-$date';
  }

  @override
  bool operator ==(Object other) =>
      other is TenantReportMonth && other._first == _first;

  @override
  int get hashCode => _first.hashCode;
}

/// One month read, and the month before it where there was one.
final class TenantMonthlyReport {
  const TenantMonthlyReport({
    required this.month,
    required this.totals,
    required this.previousTotals,
    required this.isPartial,
  });

  final TenantReportMonth month;

  /// The month's own figures. Absent only where the month has not begun.
  final TenantSalesTotals? totals;

  /// The month before, or null where it could not be read.
  ///
  /// **A missing comparison, never a missing page.** The loader swallows this
  /// one's failure for the same reason the weekly report swallows its own: the
  /// month on screen is the subject, and losing the arrow beside a figure is
  /// not a reason to lose the figure.
  final TenantSalesTotals? previousTotals;

  /// Whether the month is still running, so its figures are to date rather than
  /// final. Stated on the page: a partial month compared against a whole one is
  /// a comparison that flatters the older month, and a reader who is not told
  /// will read the arrow as a trend.
  final bool isPartial;

  // **Net against net, or gross against gross, never one of each.** Both
  // sides come through `netOrGross*`, so a month the server netted is never
  // compared with one it did not - an arrow across two bases is a trend that
  // did not happen.
  double? get salesChange =>
      _change(totals?.netOrGrossSales, previousTotals?.netOrGrossSales);

  double? get transactionsChange => _change(
    totals?.netOrGrossTransactions.toDouble(),
    previousTotals?.netOrGrossTransactions.toDouble(),
  );

  double? get profitChange => _change(
    totals?.netOrGrossProfitReport.profit,
    previousTotals?.netOrGrossProfitReport.profit,
  );

  /// The share of this month over the one before, or null where there is
  /// nothing to compare against. The same rule the weekly report applies:
  /// a previous figure of zero has no percentage.
  static double? _change(double? current, double? previous) {
    if (current == null || previous == null || previous == 0) return null;
    return (current - previous) / previous * 100;
  }
}

/// Reads one month, and the month before it, for one set of filters.
///
/// **Two requests, and that is the whole design.** See the library note.
final class TenantMonthlyReportLoader {
  TenantMonthlyReportLoader({
    required TenantSession session,
    required SalesTotalsCallable callable,
    DateTime Function()? clock,
  }) : _gateway = TenantSalesTotalsGateway(
         session: session,
         callable: callable,
         clock: clock,
       ),
       _clock = clock ?? _utcNow;

  final TenantSalesTotalsGateway _gateway;
  final DateTime Function() _clock;

  /// Whether this session may read a month at all. The same list the totals
  /// gateway owns: a month is the same information over a longer stretch.
  static bool canReadInSession(TenantSession session) =>
      TenantSalesTotalsGateway.canReadInSession(session);

  Future<TenantMonthlyReport> load(
    TenantReportMonth month, {
    String? soldById,
    String? categoryId,
  }) async {
    final now = _clock().toUtc();
    if (!month.hasBegun(now)) {
      return TenantMonthlyReport(
        month: month,
        totals: null,
        previousTotals: null,
        isPartial: false,
      );
    }

    // Started together rather than one after another, and gathered with
    // `Future.wait` so that a rejection cannot be stranded without a listener -
    // the reasoning `TenantWeeklyReportLoader.load` sets out at length.
    final results = await Future.wait<TenantSalesTotals?>(<
      Future<TenantSalesTotals?>
    >[
      _totals(month, soldById: soldById, categoryId: categoryId),
      _previousTotals(month, soldById: soldById, categoryId: categoryId),
    ]);

    return TenantMonthlyReport(
      month: month,
      totals: results[0],
      previousTotals: results[1],
      isPartial: month.isCurrent,
    );
  }

  /// The month itself. Its failure is **not** swallowed: it is the page.
  Future<TenantSalesTotals?> _totals(
    TenantReportMonth month, {
    required String? soldById,
    required String? categoryId,
  }) {
    final now = _clock().toUtc();
    return _gateway.load(
      _gateway.createRangeQuery(
        startBusinessDate: month.startBusinessDate,
        endBusinessDate: month.endBusinessDateAt(now),
        soldById: soldById,
        categoryId: categoryId,
      ),
    );
  }

  /// The month before, degraded to null on any refusal.
  Future<TenantSalesTotals?> _previousTotals(
    TenantReportMonth month, {
    required String? soldById,
    required String? categoryId,
  }) async {
    final previous = month.previous;
    final now = _clock().toUtc();
    if (!previous.hasBegun(now)) return null;
    try {
      return await _gateway.load(
        _gateway.createRangeQuery(
          startBusinessDate: previous.startBusinessDate,
          endBusinessDate: previous.endBusinessDateAt(now),
          soldById: soldById,
          categoryId: categoryId,
        ),
      );
    } on Object {
      // Every failure, including a scope violation: a comparison that cannot be
      // read is a comparison this page does without. The month itself is read
      // by [_totals], which does not catch.
      return null;
    }
  }
}

DateTime _utcNow() => DateTime.now().toUtc();
