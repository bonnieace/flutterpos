import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/stats.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_types.dart';
import 'daily_metrics.dart';
import 'profit_report.dart';
import 'profit_statement.dart';
import 'reporting_currency.dart';

/// Builds the guarded reconciliation status route for one exact business date.
///
/// The composition root supplies it, exactly as it supplies every other route
/// tenancy owns. While it is absent the route stays unreachable and the summary
/// is exactly the read-only surface it was before.
typedef TenantReconciliationRouteBuilder = Widget Function(String businessDate);

/// Builds the guarded route that totals sales the server currently holds.
///
/// Injected exactly like the reconciliation route, and reached from here for
/// the same reason: this is the screen where somebody discovers that today has
/// no reconciled figures, and the unreconciled total is the answer they came
/// for. While it is absent the summary is exactly the surface it was before.
typedef TenantSalesTotalsRouteBuilder = Widget Function();

/// Read-only daily summary route for the selected tenant session.
final class TenantDailySummaryScreen extends StatelessWidget {
  const TenantDailySummaryScreen({
    super.key,
    required this.reader,
    this.reconciliationRoute,
    this.reconciliationRoles = const <TenantRole>[],
    this.salesTotalsRoute,
    this.salesTotalsRoles = const <TenantRole>[],
  });

  /// Only document reads are needed: a day is read by exact path.
  final TenantDocumentReader reader;

  /// Opens the guarded explanation of one day's reconciliation state.
  final TenantReconciliationRouteBuilder? reconciliationRoute;

  /// The roles that route is offered to, decided by the reporting domain.
  final List<TenantRole> reconciliationRoles;

  /// Opens the guarded totals for a chosen stretch of days.
  final TenantSalesTotalsRouteBuilder? salesTotalsRoute;

  /// The roles that route is offered to, decided by the reporting domain.
  final List<TenantRole> salesTotalsRoles;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Daily summary',
    contentWidth: AppContentWidth.records,
    body: TenantDailySummaryPanel(
      reader: reader,
      reconciliationRoute: reconciliationRoute,
      reconciliationRoles: reconciliationRoles,
      salesTotalsRoute: salesTotalsRoute,
      salesTotalsRoles: salesTotalsRoles,
    ),
  );
}

/// Shows the reconciled figures for the most recent business days.
///
/// The route guard owns authorization and stale-session rejection. The panel
/// renders what reconciliation recorded and computes nothing: an unreconciled
/// day says so instead of showing a device-derived total.
final class TenantDailySummaryPanel extends StatefulWidget {
  const TenantDailySummaryPanel({
    super.key,
    required this.reader,
    this.days = 7,
    this.clock,
    this.reconciliationRoute,
    this.reconciliationRoles = const <TenantRole>[],
    this.salesTotalsRoute,
    this.salesTotalsRoles = const <TenantRole>[],
  });

  /// Only document reads are needed: a day is read by exact path.
  final TenantDocumentReader reader;
  final int days;
  final DateTime Function()? clock;

  /// Opens the guarded explanation of one day's reconciliation state.
  final TenantReconciliationRouteBuilder? reconciliationRoute;

  /// The roles that route is offered to, decided by the reporting domain.
  final List<TenantRole> reconciliationRoles;

  /// Opens the guarded totals for a chosen stretch of days.
  final TenantSalesTotalsRouteBuilder? salesTotalsRoute;

  /// The roles that route is offered to, decided by the reporting domain.
  final List<TenantRole> salesTotalsRoles;

  @override
  State<TenantDailySummaryPanel> createState() =>
      _TenantDailySummaryPanelState();
}

/// One guarded load of the summary and the code its figures are labelled with.
final class _DailySummaryView {
  const _DailySummaryView({required this.days, required this.currency});

  final List<TenantDailyMetricsDay> days;
  final TenantReportingCurrency currency;
}

final class _TenantDailySummaryPanelState
    extends State<TenantDailySummaryPanel> {
  int _generation = 0;

  void _refresh() => setState(() => _generation++);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return TenantRouteGuard<_DailySummaryView>(
      key: ValueKey(_generation),
      allowedRoles: TenantDailyMetricsRepository.allowedRoles,
      load: (session) async => _DailySummaryView(
        days: await TenantDailyMetricsRepository(
          session: session,
          reader: widget.reader,
          clock: widget.clock,
        ).loadRecentDays(days: widget.days),
        // Read after the figures, and never allowed to fail them: a label is
        // not the reason this route exists.
        currency: await TenantReportingCurrency.read(
          session: session,
          reader: widget.reader,
        ),
      ),
      denied: const Center(
        key: ValueKey('daily-summary-denied'),
        child: Text('The daily summary is available to managers and owners.'),
      ),
      failure: (context, error) => Center(
        key: const ValueKey('daily-summary-failure'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The daily summary could not be loaded.'),
            SizedBox(height: tokens.spacing.s12),
            AppButton(
              key: const ValueKey('daily-summary-retry'),
              label: 'Retry',
              onPressed: _refresh,
            ),
          ],
        ),
      ),
      builder: (context, session, view) => _DailySummaryContents(
        days: view.days,
        currency: view.currency,
        // Profit is cost, and cost is owner/admin everywhere else - a
        // narrower tier than the one that may read this whole summary.
        showProfit: TenantProfitReport.canSeeInSession(session),
        // The role is taken from the guarded session, never from the caller,
        // so the action - and the figure above - disappears the moment the
        // session stops allowing it.
        reconciliationRoute:
            session.canAccess(allowedRoles: widget.reconciliationRoles)
            ? widget.reconciliationRoute
            : null,
        salesTotalsRoute:
            session.canAccess(allowedRoles: widget.salesTotalsRoles)
            ? widget.salesTotalsRoute
            : null,
      ),
    );
  }
}

final class _DailySummaryContents extends StatelessWidget {
  const _DailySummaryContents({
    required this.days,
    required this.currency,
    required this.showProfit,
    this.reconciliationRoute,
    this.salesTotalsRoute,
  });

  final List<TenantDailyMetricsDay> days;
  final TenantReportingCurrency currency;

  /// Whether this session may be shown what the business made, rather than
  /// only what it took.
  final bool showProfit;
  final TenantReconciliationRouteBuilder? reconciliationRoute;
  final TenantSalesTotalsRouteBuilder? salesTotalsRoute;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('daily-summary'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      children: [
        // **The screen's own title used to be drawn here as well**, in a
        // `headlineSmall` under the `PageHeader` that already carries it. §7's
        // page pattern says "Title appears once" and names this exact defect;
        // step 5a put the header in and left the second copy behind on this
        // screen and a dozen others. This is the one step 8 owns.
        //
        // §7's order from here down: optional `Callout`, then the content.
        if (!currency.isKnown) ...[
          const Callout(
            key: ValueKey('daily-summary-currency-unknown'),
            status: AppStatus.info,
            message: TenantReportingCurrency.unknownNotice,
          ),
          SizedBox(height: tokens.spacing.s12),
        ],
        // A permanent helper paragraph - true of every day this route will ever
        // list - which is §5.1's own description of what a `Disclosure` is for,
        // and the rule the reconciliation sweep established on 2026-08-14.
        const Disclosure(
          key: ValueKey('daily-summary-basis-disclosure'),
          summary: 'Where these figures come from',
          child: Text(
            key: ValueKey('daily-summary-basis'),
            'These totals are regenerated by nightly reconciliation from the '
            'sales the server holds. Today is normally still unreconciled.',
          ),
        ),
        // Offered here because the fold above has just explained why today
        // shows nothing. The totals route answers that exact question, from the
        // sales the server holds rather than from reconciled figures.
        if (salesTotalsRoute != null) ...[
          SizedBox(height: tokens.spacing.s12),
          AppButton(
            key: const ValueKey('daily-summary-sales-totals'),
            label: 'Total sales over a period',
            icon: Icons.calculate_outlined,
            onPressed: () => _openSalesTotals(context),
          ),
        ],
        SizedBox(height: tokens.spacing.s16),
        for (final (index, day) in days.indexed)
          Card(
            key: ValueKey('daily-summary-${day.businessDate}'),
            child: Padding(
              padding: EdgeInsets.all(tokens.spacing.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          day.businessDate,
                          style: tokens.typography.titleMedium.copyWith(
                            color: tokens.colors.text.primary,
                          ),
                        ),
                      ),
                      SizedBox(width: tokens.spacing.s12),
                      // **A day's standing is a lookup in §2.1 and not a
                      // sentence.** "Reconciled" is `ok`'s own meaning and
                      // "unreconciled" is `attention`'s, word for word, so this
                      // is the document's decision rather than this screen's.
                      // The unreconciled key is the one the sentence carried,
                      // because it states the same fact.
                      if (day.metrics == null)
                        StatusBadge(
                          key: ValueKey(
                            'daily-summary-pending-${day.businessDate}',
                          ),
                          status: AppStatus.attention,
                          label: 'Not reconciled yet',
                          semanticLabel:
                              '${day.businessDate} is not reconciled yet',
                        )
                      else
                        StatusBadge(
                          key: ValueKey(
                            'daily-summary-reconciled-${day.businessDate}',
                          ),
                          status: AppStatus.ok,
                          label: 'Reconciled',
                          semanticLabel: '${day.businessDate} is reconciled',
                        ),
                    ],
                  ),
                  if (day.metrics case final metrics?) ...[
                    SizedBox(height: tokens.spacing.s8),
                    // **The sentence these three lines replace is why §2.2
                    // names this screen.** "Sales: KES 1250.50 over 12
                    // transactions in 2 shifts" put three figures inside prose,
                    // so nothing lined up down a column of days and every count
                    // needed its own singular. Three `numeric.body` figures,
                    // right-aligned, line up and need none.
                    StatLine(
                      label: 'Sales',
                      value: currency.format(metrics.sales),
                      valueKey: ValueKey(
                        'daily-summary-sales-${day.businessDate}',
                      ),
                      emphasis: true,
                    ),
                    // **The comparison this page could not make.** It listed
                    // seven days and never said whether one was up or down on
                    // the day before it, which is the analytical question
                    // ST-041 draws two bars to answer. Two bars is the wrong
                    // form for it - `dataviz`'s own table sends a handful of
                    // headline numbers to stat tiles and names the one-bar and
                    // grouped-bar versions as what *not* to do - and a chart
                    // beside figures the page already states is the decorative
                    // case Phase 05's second criterion forbids. A value and its
                    // delta is the form that reference recommends, and
                    // `OPEN_QUESTIONS.md` Phase 05 item 1 caps charting at
                    // "two exact daily sales bars" as a ceiling rather than
                    // asking for them.
                    //
                    // **Stated only where the day before it is also
                    // reconciled.** An unreconciled neighbour has no sales
                    // figure at all, and a delta against nothing would read as
                    // a fall to zero.
                    if (_previousSales(days, index) case final previous?)
                      StatLine(
                        label: 'Change on the day before',
                        value: _signedCurrency(
                          currency,
                          metrics.sales - previous,
                        ),
                        valueKey: ValueKey(
                          'daily-summary-change-${day.businessDate}',
                        ),
                      ),
                    StatLine(
                      label: 'Transactions',
                      value: '${metrics.transactions}',
                      valueKey: ValueKey(
                        'daily-summary-transactions-${day.businessDate}',
                      ),
                    ),
                    StatLine(
                      label: 'Shifts',
                      value: '${metrics.shiftCount}',
                      valueKey: ValueKey(
                        'daily-summary-shifts-${day.businessDate}',
                      ),
                    ),
                    // The whole statement about profit, or - for a session that
                    // may not be shown one - the cost-data fact on its own.
                    // Never both: the statement carries the same count inside
                    // it, and saying it twice reads as two different findings.
                    if (showProfit)
                      TenantProfitStatement(
                        report: metrics.profitReport,
                        currency: currency,
                        keyPrefix: 'daily-summary-${day.businessDate}',
                      )
                    else if (!metrics.hasCompleteCostData)
                      Padding(
                        padding: EdgeInsets.only(top: tokens.spacing.s4),
                        child: Text(
                          key: ValueKey(
                            'daily-summary-cost-${day.businessDate}',
                          ),
                          '${metrics.incompleteCostLineCount} sale '
                          '${metrics.incompleteCostLineCount == 1 ? 'line has' : 'lines have'} '
                          'no cost recorded.',
                          style: tokens.typography.caption.copyWith(
                            color: tokens.colors.text.tertiary,
                          ),
                        ),
                      ),
                    SizedBox(height: tokens.spacing.s8),
                    ProvenanceLine(
                      'Reconciled ${_instant(metrics.regeneratedAt)}',
                    ),
                  ],
                  if (reconciliationRoute != null) ...[
                    SizedBox(height: tokens.spacing.s8),
                    AppButton(
                      key: ValueKey(
                        'daily-summary-reconciliation-${day.businessDate}',
                      ),
                      label: 'Why is it in this state?',
                      icon: Icons.help_outline,
                      onPressed: () =>
                          _openReconciliation(context, day.businessDate),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Opens the reconciliation route under the same session scope this route
  /// runs in, so a tenant switch invalidates it exactly as it does every other
  /// guarded route rather than leaving a detached screen behind.
  void _openReconciliation(BuildContext context, String businessDate) =>
      _push(context, reconciliationRoute!(businessDate));

  void _openSalesTotals(BuildContext context) =>
      _push(context, salesTotalsRoute!());

  void _push(BuildContext context, Widget child) {
    final controller = TenantSessionScope.of(context);
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) =>
            TenantSessionScope(controller: controller, child: child),
      ),
    );
  }
}

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}

/// The sales figure of the day *before* [index], or null where there is none.
///
/// The list is newest-first, so the day before is the next element. Null covers
/// both the oldest day on the page and a neighbour that has not been reconciled:
/// neither has a figure to compare against.
double? _previousSales(List<TenantDailyMetricsDay> days, int index) {
  if (index + 1 >= days.length) return null;
  return days[index + 1].metrics?.sales;
}

/// A signed money delta, with the sign doing the work.
///
/// **Deliberately not coloured.** §2.1's statuses have defined meanings and
/// none of them is "sales went up": a rise is not `ok` and a fall is not
/// `problem` - a shop can take more by discounting and less by closing early,
/// and this screen cannot know which. The figure and its sign say what happened
/// and stop there, which is the same reasoning decision 24 applied to a stock
/// badge.
String _signedCurrency(TenantReportingCurrency currency, double delta) {
  if (delta == 0) return 'No change';
  final formatted = currency.format(delta.abs());
  return delta > 0 ? '+$formatted' : '-$formatted';
}
