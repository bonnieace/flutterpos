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

import '../checkout/checkout_outbox.dart';
import '../sales/sale_history.dart';
import '../tenancy/tenant_repository.dart';
import '../expenses/expense_repository.dart';
import '../returns/return_history.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_types.dart';
import '../ui/money_text.dart';
import '../ui/scaffold.dart';
import '../ui/tokens.dart';
import 'profit_report.dart';
import 'device_sales_totals.dart';
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

/// One report a card on this page opens, and who may open it.
///
/// **A pair rather than a bare callback, because the hub's role gate has to
/// survive its retirement.** Every card the hub drew was filtered by
/// `session.canAccess` before it was drawn at all; folding those reports into
/// this grid without carrying the roles across would have widened who can reach
/// reconciliation. A destination whose roles the session does not hold is not
/// drawn dimmed - it is not drawn.
final class WeeklyReportDestination {
  const WeeklyReportDestination({required this.build, required this.roles});

  /// The screen to push. Called at tap time, under a re-established session
  /// scope, exactly as the hub pushed its own.
  final Widget Function() build;

  final List<TenantRole> roles;
}

/// What this page's cards lead to.
///
/// **The page is no longer named for the week, and this is why.** It used to be
/// one report behind a menu of six; the menu is gone and the figures on this
/// grid are the doors now, so the page is the reports surface and these are the
/// rest of the reports. Every field is optional: a build that wires none gets
/// exactly the read-only week this screen has always been.
final class WeeklyReportDestinations {
  const WeeklyReportDestinations({
    this.salesTotals,
    this.dailySummary,
    this.monthlyReport,
    this.differences,
    this.stockMovements,
    this.openDifferenceCount,
  });

  /// What the server holds for a period, split by how each sale was paid for.
  /// Both *Total sales* and *Transactions* elaborate into it, because it is the
  /// one surface that answers either question.
  final WeeklyReportDestination? salesTotals;

  final WeeklyReportDestination? dailySummary;
  final WeeklyReportDestination? monthlyReport;
  final WeeklyReportDestination? differences;

  /// Everything that moved this business's stock. See
  /// `TenantStockMovementFeedRepository`.
  final WeeklyReportDestination? stockMovements;

  /// How many differences are still open, or null where the figure is unknown.
  ///
  /// Becomes the *Differences* card's own figure. It is the reason the badge on
  /// the home tile still resolves in one tap now the hub is gone.
  final int? Function(TenantSessionController sessions)? openDifferenceCount;
}

/// The guarded route. The reports surface, week-scoped by default.
final class TenantWeeklyReportScreen extends StatefulWidget {
  const TenantWeeklyReportScreen({
    super.key,
    required this.reader,
    required this.callable,
    this.salesRepositoryFactory,
    this.checkoutOutbox,
    this.clock,
    this.destinations = const WeeklyReportDestinations(),
  });

  /// The reports the figures on this page open. See [WeeklyReportDestinations].
  final WeeklyReportDestinations destinations;

  final TenantDataReader reader;
  final SalesTotalsCallable callable;

  /// How the sale-line roll-up reads the week. Injected so a test can supply a
  /// reader with no Firestore behind it.
  final TenantSaleHistoryRepository Function(TenantSession session)?
  salesRepositoryFactory;
  final HiveCheckoutOutbox? checkoutOutbox;

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

  String? _loaderKey;
  TenantGuardedLoader<WeeklyReportView>? _loader;
  TenantGuardedLoader<WeeklyReportView>? _loaderCached;

  /// One pair of loaders per guard key.
  ///
  /// **This used to return a fresh closure on every call and ignore its key
  /// entirely**, so `TenantRouteGuard.didUpdateWidget` saw a different loader
  /// each frame and restarted the whole week - up to eight callables and six
  /// chained Firestore pages - on any rebuild at all, including one caused by
  /// the week that had just finished loading.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    _loader = _readWith(widget.reader, deviceOnly: false);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : _readWith(cache, deviceOnly: true);
  }

  TenantGuardedLoader<WeeklyReportView> _readWith(
    TenantDataReader reader, {
    required bool deviceOnly,
  }) {
    return (session) async {
      final context = await SalesTotalsSessionContextLoader(
        reader: reader,
      ).load(session);
      // A repository factory supplied by the live route may close over its
      // Firestore reader. Never reuse it for the cached branch.
      final sales = deviceOnly
          ? TenantSaleHistoryRepository(session: session, reader: reader)
          : widget.salesRepositoryFactory?.call(session) ??
                TenantSaleHistoryRepository(session: session, reader: reader);
      final expenses = TenantExpenseRepository.canSeeInSession(session)
          ? TenantExpenseRepository(session: session, reader: reader)
          : null;
      // **Unguarded by role, unlike the spending above it.** Every active
      // member may read this business's returns - see
      // `TenantReturnHistoryRepository.allowedRoles` - and this is not an
      // extra figure on the page, it is the basis of two that are already on
      // it. Withholding it would leave a manager reading gross items beside
      // net money, which is the defect rather than a narrower view of it.
      final returns = TenantReturnHistoryRepository(
        session: session,
        reader: reader,
      );
      final loader = deviceOnly
          ? TenantWeeklyReportLoader.device(
              session: session,
              sales: sales,
              expenses: expenses,
              returns: returns,
              clock: widget.clock == null ? null : _now,
            )
          : TenantWeeklyReportLoader(
              session: session,
              callable: widget.callable,
              sales: sales,
              // Built from this route's own reader, and only for a session that may
              // be shown spending at all - which is narrower than the roles that may
              // read this report. A manager sees the week's gross figures and no net
              // card, which is the same boundary the margin already sits behind.
              expenses: expenses,
              returns: returns,
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
      final week = TenantReportWeek.at(_now(), offset: _weekOffset);
      final report = deviceOnly
          ? await loader.loadDevice(
              week,
              aggregator: TenantDeviceSalesAggregator(
                session: session,
                cacheReader: reader,
                outbox: widget.checkoutOutbox,
                clock: widget.clock == null ? null : _now,
              ),
              soldById: member,
              categoryId: category,
            )
          : await loader.load(week, soldById: member, categoryId: category);
      // Individual callable refusals are intentionally contained by the model
      // so item/expense reads can still be tested in isolation. At the route
      // boundary they are not an authoritative totals response: keep the
      // complete device result visible until all elapsed days answer.
      if (!deviceOnly &&
          week.elapsedBusinessDates(_now()).isNotEmpty &&
          report.totals == null) {
        throw StateError('server_week_totals_incomplete');
      }
      return WeeklyReportView(report: report, context: context);
    };
  }

  @override
  Widget build(BuildContext context) {
    final key =
        'w$_weekOffset:${_soldById ?? '-'}:${_categoryId ?? '-'}:$_generation';
    _composeLoaders(key);
    return TenantRouteGuard<WeeklyReportView>(
      allowedRoles: TenantSalesTotalsGateway.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      denied: const _ReportsFrame(
        body: Center(
          key: ValueKey('weekly-report-denied'),
          child: Text('Reports are available to managers and owners.'),
        ),
      ),
      // **The page, with placeholders where the reads will land.** It took a
      // centred spinner until 2026-08-27, which replaced the week picker, the
      // member and category filters and the headings along with the figures -
      // so somebody who came to look at last week had to wait for this one
      // first. Decision 35 again: the furniture is drawn, and only the figures
      // are outstanding.
      loading: _ReportsFrame(
        body: WeeklyReportContents(
          key: const ValueKey('weekly-report-loading'),
          week: TenantReportWeek.at(_now(), offset: _weekOffset),
          report: null,
          reading: true,
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
          destinations: widget.destinations,
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
          destinations: widget.destinations,
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
          destinations: widget.destinations,
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
    // **One word, and no subtitle.** The old pair cost two lines at the top of
    // a phone to say what the tiles below were about to show - and the subtitle
    // never fitted, so it ended in an ellipsis on every handset this app runs
    // on. The week stepper directly beneath says what the page is scoped to,
    // which is the part a person needs at the top.
    title: 'Reports',
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

/// The takings, grouped in thousands, with the code the tiles leave off.
///
/// **Grouped only here.** `17000.00` is read digit by digit; `17,000.00` is
/// read at a glance, which is the whole job of the one figure a dashboard
/// leads with. Every other amount on the page is in a list or a tile where a
/// separator is noise, and `TenantReportingCurrency.format` stays as it is so
/// nothing else on the page changes shape.
String weeklyReportHeroMoney(TenantReportingCurrency? currency, double amount) {
  final grouped = moneyTextGrouped(amount);
  final code = currency?.code;
  return code == null ? grouped : '$code $grouped';
}

/// The same figure with no currency code.
///
/// **For the tiles under the takings, which state the code once between
/// them.** Repeating `KES` on five figures spends the width they have least of
/// - at two across on a phone a coded amount in the 22-point mono face does
/// not fit its cell - and says nothing the card above it has not. A surface
/// that does not carry [weeklyReportMoney] somewhere must not use this.
String weeklyReportAmount(double amount) => moneyText(amount);

/// The old screen's `MMM d` week ends, and its `MMM dd, yyyy - hh:mm a` rows.
final DateFormat weeklyReportDayFormat = DateFormat('MMM d');
final DateFormat weeklyReportStampFormat = DateFormat('MMM dd, yyyy • hh:mm a');

/// Kept beside the two formats above so nothing else has to know that fl_chart
/// is what draws the bars.
typedef WeeklyReportBarBuilder = BarChartGroupData Function(int index);
