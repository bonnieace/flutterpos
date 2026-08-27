/// The old app's *Reports & Analytics* page, rebuilt on the multitenant back
/// end.
///
/// **A 1:1 migration of `lib/pos/reports.dart`, composition for composition.**
/// Five metric cards over a filter bar, a seven-bar week chart beside a
/// top-sellers list, and a recent-transactions list under both. The week
/// navigator, the two dropdowns, the percentage-change chips and the payment
/// pills are all the old screen's, in the old order, at the old proportions.
///
/// **What changed is where the values come from, and only that.** Every colour,
/// size, radius and gap is an `AppTokens` role - `claude.md` hard rule 2 - and
/// where the old screen reached for a raw `Colors.white10` gridline or a
/// `Colors.white38` axis label there is now an [AppChartRoles] entry, added for
/// this page rather than hardcoded into it.
///
/// **Two cards carry different figures and the reason is in
/// `weekly_report.dart`:** this product has no low-stock reading to migrate,
/// and *shifts today* is a different question from the week this page is about.
/// The average sale and the units sold take those two slots.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../sales/sale_history.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/tokens.dart';
import 'profit_report.dart';
import 'reporting_currency.dart';
import 'sales_totals.dart';
import 'sales_totals_session_context.dart';
import 'weekly_report.dart';
import 'weekly_report_sections.dart';

/// One loaded week, with the filter options that produced it.
final class WeeklyReportView {
  const WeeklyReportView({required this.report, required this.context});

  final TenantWeeklyReport report;
  final SalesTotalsSessionContext context;
}

/// The guarded route.
final class TenantWeeklyReportScreen extends StatefulWidget {
  const TenantWeeklyReportScreen({
    super.key,
    required this.reader,
    required this.callable,
    this.salesRepositoryFactory,
    this.clock,
  });

  final TenantDataReader reader;
  final SalesTotalsCallable callable;

  /// How the sale-line roll-up reads the week. Injected so a test can supply a
  /// reader with no Firestore behind it.
  final TenantSaleHistoryRepository Function(TenantSession session)?
  salesRepositoryFactory;

  final DateTime Function()? clock;

  @override
  State<TenantWeeklyReportScreen> createState() =>
      _TenantWeeklyReportScreenState();
}

class _TenantWeeklyReportScreenState extends State<TenantWeeklyReportScreen> {
  int _weekOffset = 0;
  String? _soldById;
  String? _categoryId;
  int _generation = 0;

  late final SalesTotalsSessionContextLoader _sessionContext =
      SalesTotalsSessionContextLoader(reader: widget.reader);

  DateTime _now() => (widget.clock ?? DateTime.now)().toUtc();

  void _chooseWeek(int offset) {
    // Never forward past the week in progress: there is nothing there to read
    // and the totals callable refuses a future business date outright.
    if (offset > 0) return;
    setState(() => _weekOffset = offset);
  }

  void _chooseMember(String? uid) => setState(() => _soldById = uid);
  void _chooseCategory(String? id) => setState(() => _categoryId = id);
  void _retry() => setState(() => _generation++);

  TenantGuardedLoader<WeeklyReportView> _loaderFor(String key) {
    return (session) async {
      final context = await _sessionContext.load(session);
      final sales =
          widget.salesRepositoryFactory?.call(session) ??
          TenantSaleHistoryRepository(session: session, reader: widget.reader);
      final loader = TenantWeeklyReportLoader(
        session: session,
        callable: widget.callable,
        sales: sales,
        clock: widget.clock == null ? null : _now,
      );
      // A stale selection is dropped rather than sent: the same rule the totals
      // page applies, for the same reason - a colleague or a category can stop
      // existing between one read and the next.
      final chosenMember = _soldById;
      final member =
          chosenMember != null &&
              (context.staff.contains(chosenMember) ||
                  chosenMember == session.uid)
          ? chosenMember
          : null;
      final chosenCategory = _categoryId;
      final category =
          chosenCategory != null &&
              context.categories.nameOf(chosenCategory) != null
          ? chosenCategory
          : null;
      return WeeklyReportView(
        report: await loader.load(
          TenantReportWeek.at(_now(), offset: _weekOffset),
          soldById: member,
          categoryId: category,
        ),
        context: context,
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final key =
        'w$_weekOffset:${_soldById ?? '-'}:${_categoryId ?? '-'}:$_generation';
    return TenantRouteGuard<WeeklyReportView>(
      key: ValueKey(key),
      allowedRoles: TenantSalesTotalsGateway.allowedRoles,
      load: _loaderFor(key),
      denied: const _ReportsFrame(
        body: Center(
          key: ValueKey('weekly-report-denied'),
          child: Text('Reports are available to managers and owners.'),
        ),
      ),
      loading: const _ReportsFrame(
        body: Center(
          key: ValueKey('weekly-report-loading'),
          child: LoadingState(message: 'Reading this week.'),
        ),
      ),
      // The filters survive a failure, exactly as they do on the totals page: a
      // week that holds too many sales is refused so a narrower one can be
      // picked, and replacing the page would take that away.
      failure: (context, error) => _ReportsFrame(
        body: WeeklyReportContents(
          week: TenantReportWeek.at(_now(), offset: _weekOffset),
          report: null,
          sessionContext:
              _sessionContext.cached ?? SalesTotalsSessionContext.empty,
          soldById: _soldById,
          selfUid: TenantSessionScope.of(context).session?.uid,
          categoryId: _categoryId,
          showProfit: false,
          onChooseWeek: _chooseWeek,
          onChooseMember: _chooseMember,
          onChooseCategory: _chooseCategory,
          onRetry: _retry,
          failureMessage: weeklyReportFailureMessage(error),
        ),
      ),
      builder: (context, session, view) => _ReportsFrame(
        body: WeeklyReportContents(
          week: view.report.week,
          report: view.report,
          sessionContext: view.context,
          soldById: _soldById,
          selfUid: session.uid,
          categoryId: _categoryId,
          currency: view.context.currency,
          // Profit is cost, and cost is owner and administrator everywhere in
          // this app. Read from the guarded session, never from the caller.
          showProfit: TenantProfitReport.canSeeInSession(session),
          onChooseWeek: _chooseWeek,
          onChooseMember: _chooseMember,
          onChooseCategory: _chooseCategory,
          onRetry: _retry,
        ),
      ),
    );
  }
}

String weeklyReportFailureMessage(Object error) => switch (error) {
  TenantSalesTotalsException(
    failure: TenantSalesTotalsFailure.periodTooLarge,
  ) =>
    'This week holds more sales than one report may read. '
        'Narrow it with a category or a colleague.',
  TenantSalesTotalsException(failure: TenantSalesTotalsFailure.forbidden) =>
    'This account may not read the business totals.',
  TenantSalesTotalsException(failure: TenantSalesTotalsFailure.unavailable) =>
    'The totals could not be reached. Check the connection and try again.',
  _ => 'This week could not be read.',
};

/// The page chrome: the old screen's title, subtitle and content maximum.
final class _ReportsFrame extends StatelessWidget {
  const _ReportsFrame({required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Reports & Analytics',
    subtitle:
        'Overview of sales performance, inventory levels, and transaction '
        'history.',
    contentWidth: AppContentWidth.records,
    body: body,
  );
}

/// A chart axis label: a compact figure, and no currency code.
///
/// **Neither the code nor the decimals fit, and neither is needed.** `KES
/// 39120.00` truncates to `KES 391...` in the 60 pixels the old screen
/// reserved for this rule, and widening the reserve takes the room out of the
/// plot. The `Total:` line directly above the chart already names the currency
/// once, which is where a reader looks for it; an axis is measured against,
/// not read aloud.
String weeklyReportAxisMoney(TenantReportingCurrency? currency, double amount) {
  final whole = amount.round();
  if (whole.abs() < 1000) return '$whole';
  final thousands = whole / 1000;
  // One decimal below a hundred thousand, none above it - so `39.1k` and
  // `120k` both stay inside the rule.
  return thousands.abs() < 100
      ? '${thousands.toStringAsFixed(1)}k'
      : '${thousands.round()}k';
}

/// Money in the business's own currency, or a plain figure where none is
/// published. The old screen's `_formatCurrency`.
String weeklyReportMoney(TenantReportingCurrency? currency, double amount) =>
    (currency ?? TenantReportingCurrency.unknown).format(amount);

/// The old screen's `MMM d` week ends, and its `MMM dd, yyyy - hh:mm a` rows.
final DateFormat weeklyReportDayFormat = DateFormat('MMM d');
final DateFormat weeklyReportStampFormat = DateFormat('MMM dd, yyyy • hh:mm a');

/// Kept beside the two formats above so nothing else has to know that fl_chart
/// is what draws the bars.
typedef WeeklyReportBarBuilder = BarChartGroupData Function(int index);
