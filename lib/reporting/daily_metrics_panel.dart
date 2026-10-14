import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/money_text.dart';
import '../ui/record_sheet.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/stats.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_types.dart';
import '../checkout/checkout_outbox.dart';
import '../expenses/expense.dart';
import '../expenses/expense_repository.dart';
import 'net_profit.dart';
import 'daily_metrics.dart';
import 'device_sales_totals.dart';
import 'reconciliation_status.dart';
import 'profit_report.dart';
import 'profit_statement.dart';
import 'reporting_currency.dart';
import '../observability/app_telemetry.dart';

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
    this.expenseReader,
    this.reconciliationRoute,
    this.reconciliationRoles = const <TenantRole>[],
    this.salesTotalsRoute,
    this.salesTotalsRoles = const <TenantRole>[],
    this.checkoutOutbox,
  });

  /// Only document reads are needed: a day is read by exact path.
  final TenantDocumentReader reader;

  /// The reader used for the collection page an expense range needs.
  ///
  /// **Separate and optional because [reader] cannot do it.** This route holds
  /// a document reader; a range walk is a collection page, which is a wider
  /// boundary. The same split `TenantSalesReportScreen` already makes with its
  /// `reportReader`. Absent, this surface shows gross profit exactly as it did
  /// before expenses existed - which is the right degradation, not a failure.
  final TenantDataReader? expenseReader;

  /// Opens the guarded explanation of one day's reconciliation state.
  final TenantReconciliationRouteBuilder? reconciliationRoute;

  /// The roles that route is offered to, decided by the reporting domain.
  final List<TenantRole> reconciliationRoles;

  /// Opens the guarded totals for a chosen stretch of days.
  final TenantSalesTotalsRouteBuilder? salesTotalsRoute;

  /// The roles that route is offered to, decided by the reporting domain.
  final List<TenantRole> salesTotalsRoles;

  /// The sales this device has rung and not yet sent. See
  /// [TenantDailySummaryPanel.checkoutOutbox].
  final HiveCheckoutOutbox? checkoutOutbox;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Daily summary',
    contentWidth: RecordSheet.contentWidth(context),
    body: TenantDailySummaryPanel(
      reader: reader,
      expenseReader: expenseReader,
      reconciliationRoute: reconciliationRoute,
      reconciliationRoles: reconciliationRoles,
      salesTotalsRoute: salesTotalsRoute,
      salesTotalsRoles: salesTotalsRoles,
      checkoutOutbox: checkoutOutbox,
    ),
  );
}

/// Shows the reconciled figures for the most recent business days.
///
/// The route guard owns authorization and stale-session rejection. The panel
/// renders what reconciliation recorded, and - for a day it has not published
/// yet - what this device itself holds, labelled as that and never mixed in
/// with a certified figure.
final class TenantDailySummaryPanel extends StatefulWidget {
  const TenantDailySummaryPanel({
    super.key,
    required this.reader,
    this.expenseReader,
    this.days = 7,
    this.clock,
    this.reconciliationRoute,
    this.reconciliationRoles = const <TenantRole>[],
    this.salesTotalsRoute,
    this.salesTotalsRoles = const <TenantRole>[],
    this.checkoutOutbox,
  });

  /// Only document reads are needed: a day is read by exact path.
  final TenantDocumentReader reader;

  /// The reader used for the collection page an expense range needs.
  ///
  /// **Separate and optional because [reader] cannot do it.** This route holds
  /// a document reader; a range walk is a collection page, which is a wider
  /// boundary. The same split `TenantSalesReportScreen` already makes with its
  /// `reportReader`. Absent, this surface shows gross profit exactly as it did
  /// before expenses existed - which is the right degradation, not a failure.
  final TenantDataReader? expenseReader;
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

  /// The sales this device has rung and not yet sent.
  ///
  /// **The cache cannot stand in for it.** A sale rung offline is never handed
  /// to the Firestore SDK, so it is neither a pending write nor a server
  /// document - and an unpublished day drawn without it understates exactly the
  /// day this surface exists to describe.
  final HiveCheckoutOutbox? checkoutOutbox;

  @override
  State<TenantDailySummaryPanel> createState() =>
      _TenantDailySummaryPanelState();
}

/// One guarded load of the summary and the code its figures are labelled with.
final class _DailySummaryView {
  const _DailySummaryView({
    required this.days,
    required this.currency,
    this.expenses,
    this.deviceDays = const <String, TenantDeviceSalesTotals>{},
  });

  final List<TenantDailyMetricsDay> days;
  final TenantReportingCurrency currency;

  /// What this device holds for the days the server has not published,
  /// by business date. Empty where nothing could be read, which leaves every
  /// unpublished day saying exactly what it said before.
  final Map<String, TenantDeviceSalesTotals> deviceDays;

  /// Every expense across the days shown, read once and sliced per day, or
  /// null where this session may not read them.
  final TenantExpensePeriod? expenses;
}

final class _TenantDailySummaryPanelState
    extends State<TenantDailySummaryPanel> {
  int _generation = 0;

  void _refresh() => setState(() => _generation++);

  /// What the business spent across the days on screen.
  ///
  /// Null rather than an exception on failure: an expense read that did not
  /// answer must remove the net figure, never the day's takings above it -
  /// which is exactly what a null does, through
  /// `TenantNetProfitBasis.expensesUnread`.
  Future<TenantExpensePeriod?> _readExpenses(
    TenantSession session,
    List<TenantDailyMetricsDay> days,
  ) async {
    final expenseReader = widget.expenseReader;
    if (expenseReader == null ||
        days.isEmpty ||
        !TenantExpenseRepository.canSeeInSession(session)) {
      return null;
    }
    final dates = days.map((day) => day.businessDate).toList()..sort();
    try {
      return await TenantExpenseRepository(
        session: session,
        reader: expenseReader,
      ).readRange(startDate: dates.first, endDate: dates.last);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'reporting.daily_expenses_read',
      );
      return null;
    }
  }

  /// The most recent days this will add up off the device.
  ///
  /// **Bounded, because a day is a walk of the cache and not a lookup.** The
  /// days that are genuinely unpublished are the ones at the top of this page -
  /// reconciliation runs nightly - so reading the newest few answers the
  /// question a manager opened this screen with, and a page of seven days
  /// never turns into seven scans of local storage.
  static const int _deviceDayLimit = 3;

  /// What this device can add up for the days the server has not published.
  ///
  /// **The whole of #115.** This screen knew an unreconciled day was a
  /// first-class state and treated it as a reason to show nothing, sending the
  /// reader to Sales Totals for a figure this device could already state. The
  /// certified result still wins wherever there is one; this only fills the
  /// days where there is none.
  ///
  /// Failure is silent and per-day: a device figure is an addition to this
  /// page, never a reason to lose the reconciled days above it.
  Future<Map<String, TenantDeviceSalesTotals>> _readDeviceDays(
    TenantSession session,
    List<TenantDailyMetricsDay> days,
  ) async {
    final cache = widget.reader.cached;
    if (cache == null) return const <String, TenantDeviceSalesTotals>{};
    final unpublished = days
        .where((day) => day.metrics == null)
        .take(_deviceDayLimit)
        .toList();
    if (unpublished.isEmpty) return const <String, TenantDeviceSalesTotals>{};
    final aggregator = TenantDeviceSalesAggregator(
      session: session,
      cacheReader: cache,
      // Without this an unpublished day is drawn from the cache alone, which
      // is precisely the evidence an offline sale is missing from.
      outbox: widget.checkoutOutbox,
      // The same clock the days themselves were read against, so the dates
      // this totals cannot drift from the dates it is labelling.
      clock: widget.clock,
    );
    final totals = <String, TenantDeviceSalesTotals>{};
    for (final day in unpublished) {
      try {
        totals[day.businessDate] = await aggregator.load(
          aggregator.createBusinessDateQuery(businessDate: day.businessDate),
        );
      } catch (error, stackTrace) {
        AppTelemetry.captureHandled(
          error,
          stackTrace,
          boundary: 'reporting.daily_totals_read',
        );
        // Nothing for this day; the badge says what it always said.
      }
    }
    return totals;
  }

  /// One loader pair per generation, memoised so an unrelated rebuild does not
  /// restart the read. See [TenantRouteGuard.load] for why this shape is what
  /// lets the guard keep the figures on screen while it refreshes them.
  void _composeLoaders(int key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    TenantGuardedLoader<_DailySummaryView> readWith(
      TenantDocumentReader reader,
    ) => (session) async {
      final days = await TenantDailyMetricsRepository(
        session: session,
        reader: reader,
        clock: widget.clock,
      ).loadRecentDays(days: widget.days);
      return _DailySummaryView(
        days: days,
        // Read after the figures, and never allowed to fail them: a label
        // is not the reason this route exists.
        currency: await TenantReportingCurrency.read(
          session: session,
          reader: reader,
        ),
        // **One read for the whole span, sliced per day below.** The span
        // is taken from the days that came back rather than from the
        // clock, so it can only ever cover dates this page is showing.
        expenses: await _readExpenses(session, days),
        // Read on both passes, because a day the server has not published is
        // unpublished whether or not there is a network.
        deviceDays: await _readDeviceDays(session, days),
      );
    };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  int? _loaderKey;
  TenantGuardedLoader<_DailySummaryView>? _loader;
  TenantGuardedLoader<_DailySummaryView>? _loaderCached;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    _composeLoaders(_generation);
    return TenantRouteGuard<_DailySummaryView>(
      allowedRoles: TenantDailyMetricsRepository.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      // **A past day with no figures in the copy is usually one this device
      // has not downloaded**, not one the server has not reconciled: it was
      // published after this device last read it. Drawn, it said *Not
      // reconciled yet* and *Counted on this device*, then flipped to
      // Reconciled. Today is left out: it is often genuinely unpublished, and
      // counting it would keep this page off the device copy almost always.
      holdsNothing: (view) =>
          view.days.skip(1).any((day) => day.metrics == null),
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
        expenses: view.expenses,
        deviceDays: view.deviceDays,
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
    this.expenses,
    this.deviceDays = const <String, TenantDeviceSalesTotals>{},
    this.reconciliationRoute,
    this.salesTotalsRoute,
  });

  final List<TenantDailyMetricsDay> days;
  final TenantReportingCurrency currency;

  /// Every expense across the days shown, or null where none were read.
  final TenantExpensePeriod? expenses;

  /// What this device holds for the days the server has not published.
  final Map<String, TenantDeviceSalesTotals> deviceDays;

  /// Whether this session may be shown what the business made, rather than
  /// only what it took.
  final bool showProfit;
  final TenantReconciliationRouteBuilder? reconciliationRoute;
  final TenantSalesTotalsRouteBuilder? salesTotalsRoute;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final table = RecordSheet.drawnAt(MediaQuery.sizeOf(context).width);
    return ListView(
      key: const ValueKey('daily-summary'),
      padding: RecordSheet.pagePadding(
        context,
        fallback: EdgeInsets.all(tokens.spacing.s20),
      ),
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
        // On the table's top edge from 1024 instead; see [_sheet].
        if (salesTotalsRoute != null && !table) ...[
          SizedBox(height: tokens.spacing.s12),
          AppButton(
            key: const ValueKey('daily-summary-sales-totals'),
            label: 'Total sales over a period',
            icon: Icons.calculate_outlined,
            onPressed: () => _openSalesTotals(context),
          ),
        ],
        SizedBox(height: tokens.spacing.s16),
        if (table)
          _sheet(context, tokens)
        else
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
                        // **Four readings, because a published figure and a
                        // current one are different facts.** This used to ask
                        // `metrics == null` and call everything else
                        // *Reconciled*, so a day the server had taken more sales
                        // for - or had stopped working on entirely - kept a green
                        // badge over figures the intake record knew were stale.
                        switch (day.standing) {
                          TenantDailyMetricsStanding.unpublished => StatusBadge(
                            key: ValueKey(
                              'daily-summary-pending-${day.businessDate}',
                            ),
                            status: AppStatus.attention,
                            label: 'Not reconciled yet',
                            semanticLabel:
                                '${day.businessDate} is not reconciled yet',
                          ),
                          TenantDailyMetricsStanding.current => StatusBadge(
                            key: ValueKey(
                              'daily-summary-reconciled-${day.businessDate}',
                            ),
                            status: AppStatus.ok,
                            label: 'Reconciled',
                            semanticLabel: '${day.businessDate} is reconciled',
                          ),
                          TenantDailyMetricsStanding.superseded => StatusBadge(
                            key: ValueKey(
                              'daily-summary-superseded-${day.businessDate}',
                            ),
                            status: AppStatus.attention,
                            // The intake record's own word for the state it is
                            // in, so this screen does not invent a second
                            // vocabulary for the server's decision.
                            label:
                                day.intake?.status ==
                                    TenantReconciliationIntakeStatus.quarantined
                                ? 'Stopped'
                                : 'Waiting to be regenerated',
                            semanticLabel:
                                '${day.businessDate} has figures that are out of '
                                'date',
                          ),
                          TenantDailyMetricsStanding.unconfirmed => StatusBadge(
                            key: ValueKey(
                              'daily-summary-unconfirmed-${day.businessDate}',
                            ),
                            status: AppStatus.attention,
                            label: 'Not confirmed current',
                            semanticLabel:
                                '${day.businessDate} could not be confirmed as '
                                'current',
                          ),
                        },
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
                        money: true,
                        value: currency.format(metrics.netSales),
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
                          money: true,
                          value: _signedCurrency(
                            currency,
                            metrics.netSales - previous,
                          ),
                          valueKey: ValueKey(
                            'daily-summary-change-${day.businessDate}',
                          ),
                        ),
                      StatLine(
                        label: 'Transactions',
                        value: '${metrics.netTransactions}',
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
                          report: metrics.netProfitReport,
                          currency: currency,
                          keyPrefix: 'daily-summary-${day.businessDate}',
                          // This day's slice of the span read once above. Null
                          // where the session may not read spending at all, in
                          // which case the block says `Profit` exactly as it
                          // always did rather than implying a net it has not got.
                          net: expenses == null
                              ? null
                              : TenantNetProfitReport.from(
                                  gross: metrics.netProfitReport,
                                  expenses: expenses!.forDate(day.businessDate),
                                ),
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
                      // Said where anything came back, for the reason the
                      // totals page says it: takings net of returns and takings
                      // gross of them are different numbers, and a reader
                      // checking against a till roll needs to know which.
                      if (metrics.net case final net when net.returnCount > 0)
                        Padding(
                          padding: EdgeInsets.only(top: tokens.spacing.s4),
                          child: Text(
                            key: ValueKey(
                              'daily-summary-returns-${day.businessDate}',
                            ),
                            '${net.returnCount} '
                            '${net.returnCount == 1 ? 'return has' : 'returns have'} '
                            'been taken back out of these figures.',
                            style: tokens.typography.caption.copyWith(
                              color: tokens.colors.text.tertiary,
                            ),
                          ),
                        ),
                      SizedBox(height: tokens.spacing.s8),
                      // **When these figures were made, not when the day was
                      // settled.** Saying *Reconciled* over a superseded day
                      // would restate the claim the badge has just withdrawn.
                      ProvenanceLine(
                        day.standing == TenantDailyMetricsStanding.current
                            ? 'Reconciled ${_instant(metrics.regeneratedAt)}'
                            : 'Published ${_instant(metrics.regeneratedAt)}',
                      ),
                      if (day.standing ==
                          TenantDailyMetricsStanding.superseded) ...[
                        SizedBox(height: tokens.spacing.s4),
                        Text(
                          key: ValueKey(
                            'daily-summary-superseded-note-${day.businessDate}',
                          ),
                          day.intake?.status ==
                                  TenantReconciliationIntakeStatus.quarantined
                              ? 'The server stopped working on this day, so these '
                                    'figures are the last it published.'
                              : 'Sales have reached the server since these '
                                    'figures were published.',
                          style: tokens.typography.caption.copyWith(
                            color: tokens.colors.text.tertiary,
                          ),
                        ),
                      ],
                    ]
                    // **A day the server has not published, added up here.**
                    // #115: this screen showed a badge and nothing else, and sent
                    // the reader to Sales Totals for a figure this device was
                    // already holding. A certified result still wins wherever
                    // there is one - this branch is only reachable where there is
                    // none - and it is labelled as what it is rather than being
                    // mixed in with a reconciled figure.
                    else if (deviceDays[day.businessDate]?.displayable
                        case final counted?) ...[
                      SizedBox(height: tokens.spacing.s8),
                      StatLine(
                        label: 'Sales',
                        money: true,
                        value: currency.format(
                          counted.net?.sales ?? counted.sales,
                        ),
                        valueKey: ValueKey(
                          'daily-summary-device-sales-${day.businessDate}',
                        ),
                        emphasis: true,
                      ),
                      StatLine(
                        label: 'Transactions',
                        value:
                            '${counted.net?.transactions ?? counted.transactions}',
                        valueKey: ValueKey(
                          'daily-summary-device-transactions-${day.businessDate}',
                        ),
                      ),
                      // **No shift count, and no change on the day before.** The
                      // cache holds this device's sales, not the registers
                      // another till opened, so a count from here would
                      // understate exactly the days that had more than one. A
                      // delta across two different bases would be arithmetic on
                      // figures that do not mean the same thing.
                      if (showProfit)
                        TenantProfitStatement(
                          report:
                              counted.net?.profitReport ?? counted.profitReport,
                          currency: currency,
                          keyPrefix: 'daily-summary-device-${day.businessDate}',
                          net: expenses == null
                              ? null
                              : TenantNetProfitReport.from(
                                  gross:
                                      counted.net?.profitReport ??
                                      counted.profitReport,
                                  expenses: expenses!.forDate(day.businessDate),
                                ),
                        ),
                      SizedBox(height: tokens.spacing.s8),
                      const ProvenanceLine('Counted on this device'),
                      SizedBox(height: tokens.spacing.s4),
                      Text(
                        key: ValueKey(
                          'daily-summary-device-basis-${day.businessDate}',
                        ),
                        'Rung on this till and not reconciled yet. A sale rung on '
                        'another register is not in this figure.',
                        style: tokens.typography.caption.copyWith(
                          color: tokens.colors.text.tertiary,
                        ),
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

  /// The large-screen form: one row per day.
  ///
  /// **The same days, read the same way, drawn as rows** - `docs/design/
  /// tables/`, at the developer's direction on 2026-10-13 for every screen
  /// that stretched a phone card across a large window. A week's sales read
  /// down one column, where seven cards had to be read one at a time. Below
  /// 1024 the cards above are unchanged.
  ///
  /// **What a card says about only some days folds under the row**: when its
  /// figures were made, the returns taken out of them, why they are out of
  /// date, the device's caveat, and the whole sentence about the cost data
  /// behind the profit. The profit cell still carries its qualification -
  /// `tenantProfitCeilingNote`, the wording written for a figure drawn without
  /// room for the full sentence - so no ceiling is ever drawn as a plain
  /// figure, which is the rule `TenantProfitStatement` exists to keep.
  Widget _sheet(BuildContext context, AppTokens tokens) {
    final code = currency.code;
    final columns = <SheetColumn>[
      const SheetColumn(label: 'Day', kind: SheetColumnKind.identity),
      SheetColumn(label: 'Sales', kind: SheetColumnKind.figure, unit: code),
      // **Change, not the card's "Change on the day before"**: a header is
      // read once over every row, and the long form made it the widest column
      // on the sheet, which every other column is then drawn as wide as.
      SheetColumn(label: 'Change', kind: SheetColumnKind.figure, unit: code),
      const SheetColumn(label: 'Transactions', kind: SheetColumnKind.figure),
      const SheetColumn(label: 'Shifts', kind: SheetColumnKind.figure),
      if (showProfit) ...<SheetColumn>[
        SheetColumn(
          // Gross only where there is a net to tell it apart from, as the
          // card's own statement names it.
          label: expenses == null ? 'Profit' : 'Gross profit',
          kind: SheetColumnKind.figure,
          unit: code,
        ),
        const SheetColumn(label: 'Margin', kind: SheetColumnKind.figure),
      ],
      const SheetColumn(label: 'Standing', kind: SheetColumnKind.status),
    ];
    final profitColumn = showProfit ? 5 : -1;
    final marginColumn = showProfit ? 6 : -1;

    final rows = <_DayFigures>[
      for (final (index, day) in days.indexed) _figuresOf(day, index),
    ];
    // **Whole amounts hold `.00` as blank space where their column has cents**,
    // decided per column from the amounts themselves.
    bool hasCents(Iterable<double?> amounts) => amounts.any(
      (amount) => amount != null && (amount * 100).round() % 100 != 0,
    );
    final salesCents = hasCents(rows.map((row) => row.sales));
    final changeCents = hasCents(rows.map((row) => row.change));
    final profitCents = hasCents(<double?>[
      for (final row in rows) ...<double?>[
        row.report?.profit,
        row.net?.expenses,
        row.net?.netProfit,
      ],
    ]);
    String? reserve(bool cents, double? amount) =>
        cents && (amount == null || (amount * 100).round() % 100 == 0)
        ? '.00'
        : null;
    SheetCell money(
      double? amount,
      bool cents,
      String key, {
      String? caption,
    }) => amount == null
        ? SheetFigure.unknown(
            reserve: reserve(cents, null),
            key: ValueKey<String>(key),
          )
        : SheetFigure(
            moneyTextGrouped(amount),
            reserve: reserve(cents, amount),
            caption: caption,
            key: ValueKey<String>(key),
          );
    SheetCell count(int? value, String key) => value == null
        ? SheetFigure.unknown(key: ValueKey<String>(key))
        : SheetFigure('$value', key: ValueKey<String>(key));

    final route = reconciliationRoute;
    return RecordSheet(
      key: const ValueKey('daily-summary-sheet'),
      columns: columns,
      bar: salesTotalsRoute == null
          ? null
          : Row(
              children: <Widget>[
                const Spacer(),
                AppButton(
                  key: const ValueKey('daily-summary-sales-totals'),
                  label: 'Total sales over a period',
                  icon: Icons.calculate_outlined,
                  onPressed: () => _openSalesTotals(context),
                ),
              ],
            ),
      rows: <SheetRow>[
        for (final row in rows)
          SheetRow(
            id: row.date,
            key: ValueKey<String>('daily-summary-${row.date}'),
            // The card's *Why is it in this state?*, which is the one thing a
            // day leads to. Absent where the session may not be offered it.
            pressKey: route == null
                ? null
                : ValueKey<String>('daily-summary-reconciliation-${row.date}'),
            onPressed: route == null
                ? null
                : () => _openReconciliation(context, row.date),
            semanticLabel: row.date,
            semanticHint: route == null
                ? null
                : 'Opens why this day is in this state.',
            cells: <SheetCell?>[
              SheetText(
                row.date,
                caption: row.counted ? 'Counted on this device' : null,
              ),
              money(row.sales, salesCents, row.salesKey),
              switch (row.change) {
                final delta? => SheetFigure(
                  _signedFigure(delta),
                  reserve: reserve(changeCents, delta),
                  key: ValueKey<String>('daily-summary-change-${row.date}'),
                ),
                null => SheetFigure.unknown(
                  reserve: reserve(changeCents, null),
                  key: ValueKey<String>('daily-summary-change-${row.date}'),
                ),
              },
              count(row.transactions, row.transactionsKey),
              count(row.shifts, 'daily-summary-shifts-${row.date}'),
              if (showProfit) ...<SheetCell?>[
                switch (row.report) {
                  final report? when report.isDrawable => money(
                    report.profit,
                    profitCents,
                    '${row.prefix}-profit',
                    caption: report.isShowable
                        ? null
                        : tenantProfitCeilingNote(report),
                  ),
                  _ => money(null, profitCents, '${row.prefix}-profit'),
                },
                switch (row.report?.marginPercent) {
                  final margin? => SheetFigure(
                    '${margin.toStringAsFixed(1)}%',
                    key: ValueKey<String>('${row.prefix}-margin'),
                  ),
                  null => SheetFigure.unknown(
                    key: ValueKey<String>('${row.prefix}-margin'),
                  ),
                },
              ],
              _standing(row.day),
            ],
            fold: _foldOf(
              row,
              profitColumn: profitColumn,
              marginColumn: marginColumn,
              reserve: (amount) => reserve(profitCents, amount),
            ),
          ),
      ],
    );
  }

  /// One day's figures, from whichever source has them: the server's
  /// published day, or - where there is none - what this device counted.
  _DayFigures _figuresOf(TenantDailyMetricsDay day, int index) {
    final date = day.businessDate;
    final metrics = day.metrics;
    final counted = metrics == null ? deviceDays[date]?.displayable : null;
    final report =
        metrics?.netProfitReport ??
        (counted == null
            ? null
            : counted.net?.profitReport ?? counted.profitReport);
    final previous = metrics == null ? null : _previousSales(days, index);
    return _DayFigures(
      day: day,
      date: date,
      counted: counted != null,
      // The card's keys: a device's own figures are named as such, and a day
      // with no figures at all keeps the published day's names.
      prefix: counted == null
          ? 'daily-summary-$date'
          : 'daily-summary-device-$date',
      salesKey: counted == null
          ? 'daily-summary-sales-$date'
          : 'daily-summary-device-sales-$date',
      transactionsKey: counted == null
          ? 'daily-summary-transactions-$date'
          : 'daily-summary-device-transactions-$date',
      sales:
          metrics?.netSales ??
          (counted == null ? null : counted.net?.sales ?? counted.sales),
      transactions:
          metrics?.netTransactions ??
          (counted == null
              ? null
              : counted.net?.transactions ?? counted.transactions),
      // **No shift count and no change for a device's figure**, for the
      // card's reason: the cache holds this till's sales, not another's.
      shifts: metrics?.shiftCount,
      change: metrics == null || previous == null
          ? null
          : metrics.netSales - previous,
      report: showProfit ? report : null,
      net: !showProfit || report == null || expenses == null
          ? null
          : TenantNetProfitReport.from(
              gross: report,
              expenses: expenses!.forDate(date),
            ),
      returnCount: metrics?.net.returnCount ?? 0,
      incompleteCostLines: metrics == null || metrics.hasCompleteCostData
          ? 0
          : metrics.incompleteCostLineCount,
    );
  }

  /// The card's badge, as a cell. A reconciled day is the settled state, so it
  /// is a quiet glyph and word; every other standing wants a look.
  SheetStatus _standing(TenantDailyMetricsDay day) {
    final date = day.businessDate;
    final stopped =
        day.intake?.status == TenantReconciliationIntakeStatus.quarantined;
    return switch (day.standing) {
      TenantDailyMetricsStanding.unpublished => SheetStatus(
        key: ValueKey('daily-summary-pending-$date'),
        status: AppStatus.attention,
        label: 'Not reconciled yet',
        semanticLabel: '$date is not reconciled yet',
      ),
      TenantDailyMetricsStanding.current => SheetStatus(
        key: ValueKey('daily-summary-reconciled-$date'),
        status: AppStatus.ok,
        label: 'Reconciled',
        semanticLabel: '$date is reconciled',
        quiet: true,
      ),
      TenantDailyMetricsStanding.superseded => SheetStatus(
        key: ValueKey('daily-summary-superseded-$date'),
        status: AppStatus.attention,
        label: stopped ? 'Stopped' : 'Waiting to be regenerated',
        semanticLabel: '$date has figures that are out of date',
      ),
      TenantDailyMetricsStanding.unconfirmed => SheetStatus(
        key: ValueKey('daily-summary-unconfirmed-$date'),
        status: AppStatus.attention,
        label: 'Not confirmed current',
        semanticLabel: '$date could not be confirmed as current',
      ),
    };
  }

  /// Everything the card says in sentences about this day, and the net
  /// figures where spending was read. Null where the day has nothing to say,
  /// which is a day nothing was published or counted for.
  SheetFold? _foldOf(
    _DayFigures row, {
    required int profitColumn,
    required int marginColumn,
    required String? Function(double?) reserve,
  }) {
    final day = row.day;
    final metrics = day.metrics;
    final notes = <String>[
      if (metrics != null)
        day.standing == TenantDailyMetricsStanding.current
            ? 'Reconciled ${_instant(metrics.regeneratedAt)}.'
            : 'Published ${_instant(metrics.regeneratedAt)}.',
      if (metrics != null &&
          day.standing == TenantDailyMetricsStanding.superseded)
        day.intake?.status == TenantReconciliationIntakeStatus.quarantined
            ? 'The server stopped working on this day, so these figures are '
                  'the last it published.'
            : 'Sales have reached the server since these figures were '
                  'published.',
      if (row.counted)
        'Rung on this till and not reconciled yet. A sale rung on another '
            'register is not in this figure.',
      if (row.returnCount > 0)
        '${row.returnCount} '
            '${row.returnCount == 1 ? 'return has' : 'returns have'} been '
            'taken back out of these figures.',
      if (row.report case final report?) tenantProfitNote(report),
      if (!showProfit && row.incompleteCostLines > 0)
        '${row.incompleteCostLines} sale '
            '${row.incompleteCostLines == 1 ? 'line has' : 'lines have'} no '
            'cost recorded.',
    ];
    final net = row.net;
    final lines = <SheetFoldLine>[
      if (net != null && net.isDrawable && profitColumn > 0) ...<SheetFoldLine>[
        SheetFoldLine(
          label: 'Expenses',
          value: moneyTextGrouped(net.expenses),
          reserve: reserve(net.expenses),
          column: profitColumn,
          valueKey: ValueKey<String>('${row.prefix}-expenses'),
        ),
        SheetFoldLine(
          label: net.isShowable ? 'Net profit' : 'Net profit, at most',
          value: moneyTextGrouped(net.netProfit),
          reserve: reserve(net.netProfit),
          column: profitColumn,
          valueKey: ValueKey<String>('${row.prefix}-net-profit'),
        ),
        if (net.netMarginPercent case final margin? when marginColumn > 0)
          SheetFoldLine(
            label: 'Net margin',
            value: '${margin.toStringAsFixed(1)}%',
            column: marginColumn,
            valueKey: ValueKey<String>('${row.prefix}-net-margin'),
          ),
      ],
    ];
    if (notes.isEmpty && lines.isEmpty) return null;
    return SheetFold(
      note: notes.isEmpty ? null : notes.join(' '),
      noteKey: ValueKey<String>('daily-summary-note-${row.date}'),
      lines: lines,
      toggleKey: ValueKey<String>('daily-summary-fold-${row.date}'),
      showLabel: 'Show more about ${row.date}',
      hideLabel: 'Show less about ${row.date}',
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
  // The same basis as the day it is subtracted from, or the delta is a
  // difference between two different questions.
  return days[index + 1].metrics?.netSales;
}

/// A signed delta for a table cell: [_signedCurrency]'s rule, with no code
/// (the column's header states it once), grouped, and a real minus.
String _signedFigure(double delta) {
  if (delta == 0) return '0';
  final formatted = moneyTextGrouped(delta.abs());
  return delta > 0 ? '+$formatted' : '−$formatted';
}

/// One day's figures as the table reads them.
final class _DayFigures {
  const _DayFigures({
    required this.day,
    required this.date,
    required this.counted,
    required this.prefix,
    required this.salesKey,
    required this.transactionsKey,
    required this.sales,
    required this.transactions,
    required this.shifts,
    required this.change,
    required this.report,
    required this.net,
    required this.returnCount,
    required this.incompleteCostLines,
  });

  final TenantDailyMetricsDay day;
  final String date;

  /// Whether the figures are this device's rather than the server's.
  final bool counted;

  /// The card's own key prefix for this day's profit figures.
  final String prefix;
  final String salesKey;
  final String transactionsKey;
  final double? sales;
  final int? transactions;
  final int? shifts;
  final double? change;

  /// The profit, or null where this session is not shown one.
  final TenantProfitReport? report;
  final TenantNetProfitReport? net;
  final int returnCount;
  final int incompleteCostLines;
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
