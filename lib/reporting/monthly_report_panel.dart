/// A calendar month's takings, against the month before it.
///
/// **The report a month is closed on.** Every other period surface in this app
/// ends *today* - `TenantSalesPeriod` is Today, 7, 30 and 90 days, all of them
/// rolling - so nothing could answer "how did July go" once August had started.
/// The old app had `MonthlySalesReportPage` for exactly that and the
/// multitenant rebuild never carried it over.
///
/// **Two requests, not thirty-one.** See `monthly_report.dart`: the weekly
/// report's per-day chart costs one callable per day, which a month cannot
/// afford. What that buys back is the comparison and the figures; what it costs
/// is the per-day chart and the top-items roll-up, neither of which is drawn
/// here.
///
/// **No payment split here, deliberately.** `TenantSalesTotalsScreen` renders
/// one already, over any of its periods, and duplicating that rendering to put
/// it on a second surface would be the same component twice. The hub offers
/// both.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_outbox.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../ui/buttons.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/stats.dart';
import '../ui/tokens.dart';
import 'monthly_report.dart';
import 'device_sales_totals.dart';
import 'profit_report.dart';
import 'profit_statement.dart';
import 'reporting_currency.dart';
import 'sales_totals.dart';

/// One loaded month, with the currency its figures are labelled in.
final class MonthlyReportView {
  const MonthlyReportView({required this.report, required this.currency});

  final TenantMonthlyReport report;
  final TenantReportingCurrency currency;
}

/// The guarded route.
final class TenantMonthlyReportScreen extends StatefulWidget {
  const TenantMonthlyReportScreen({
    super.key,
    required this.reader,
    required this.callable,
    this.checkoutOutbox,
    this.clock,
  });

  /// Reads the published currency. The figures come from [callable].
  final TenantDataReader reader;
  final SalesTotalsCallable callable;
  final HiveCheckoutOutbox? checkoutOutbox;
  final DateTime Function()? clock;

  @override
  State<TenantMonthlyReportScreen> createState() =>
      _TenantMonthlyReportScreenState();
}

class _TenantMonthlyReportScreenState extends State<TenantMonthlyReportScreen> {
  int _monthOffset = 0;
  int _generation = 0;

  DateTime _now() => (widget.clock ?? DateTime.now)().toUtc();

  void _chooseMonth(int offset) {
    // Never forward past the month in progress: there is nothing there to read
    // and the gateway refuses a future business date outright.
    if (offset > 0) return;
    setState(() => _monthOffset = offset);
  }

  void _retry() => setState(() => _generation++);

  String? _loaderKey;
  TenantGuardedLoader<MonthlyReportView>? _loader;
  TenantGuardedLoader<MonthlyReportView>? _loaderCached;

  /// One pair of loaders per guard key.
  ///
  /// Rebuilt only when the key changes, for the reason the weekly report gives:
  /// `TenantRouteGuard.didUpdateWidget` compares loaders by identity, so a
  /// fresh closure on every build would restart the whole month on any rebuild
  /// at all - including the one caused by the month that had just landed.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    _loader = _readServer(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : _readDevice(cache);
  }

  TenantGuardedLoader<MonthlyReportView> _readServer(TenantDataReader reader) {
    return (session) async {
      final loader = TenantMonthlyReportLoader(
        session: session,
        callable: widget.callable,
        clock: widget.clock == null ? null : _now,
      );
      final report = await loader.load(
        TenantReportMonth.at(_now(), offset: _monthOffset),
      );
      // The label, not the figure: an unreadable currency leaves the amounts
      // bare rather than taking the page.
      final currency = await TenantReportingCurrency.read(
        session: session,
        reader: reader,
      );
      return MonthlyReportView(report: report, currency: currency);
    };
  }

  TenantGuardedLoader<MonthlyReportView> _readDevice(TenantDataReader reader) {
    return (session) async {
      final now = _now();
      final month = TenantReportMonth.at(now, offset: _monthOffset);
      final aggregator = TenantDeviceSalesAggregator(
        session: session,
        cacheReader: reader,
        outbox: widget.checkoutOutbox,
        clock: widget.clock == null ? null : _now,
      );
      TenantSalesTotals? totals;
      if (month.hasBegun(now)) {
        final result = await aggregator.load(
          aggregator.createRangeQuery(
            startBusinessDate: month.startBusinessDate,
            endBusinessDate: month.endBusinessDateAt(now),
          ),
        );
        totals = result.totals;
        if (totals == null) {
          throw StateError(
            result.truncated
                ? 'device_sales_truncated'
                : 'device_sales_conflicting_evidence',
          );
        }
      }
      final currency = await TenantReportingCurrency.read(
        session: session,
        reader: reader,
      );
      return MonthlyReportView(
        report: TenantMonthlyReport(
          month: month,
          totals: totals,
          // A device-only total never carries a comparison percentage. The
          // authoritative branch will add one when both server periods land.
          previousTotals: null,
          isPartial: month.isCurrent,
        ),
        currency: currency,
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final key = 'm$_monthOffset:$_generation';
    _composeLoaders(key);
    final month = TenantReportMonth.at(_now(), offset: _monthOffset);
    return TenantRouteGuard<MonthlyReportView>(
      allowedRoles: TenantSalesTotalsGateway.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      denied: const _MonthFrame(
        month: null,
        body: Center(
          key: ValueKey('monthly-report-denied'),
          child: Text('Reports are available to managers and owners.'),
        ),
      ),
      // The chooser is drawn while the figures are outstanding, so somebody who
      // came to look at June does not have to wait for August first.
      loading: _MonthFrame(
        month: month,
        onChooseMonth: _chooseMonth,
        body: const Center(
          key: ValueKey('monthly-report-loading'),
          child: LoadingState(message: 'Adding up the month'),
        ),
      ),
      // The chooser survives a failure too: a month holding more sales than the
      // server will scan is refused so a narrower question can be asked, and
      // replacing the page would take the chooser away with it.
      failure: (context, error) => _MonthFrame(
        month: month,
        onChooseMonth: _chooseMonth,
        body: Center(
          child: ErrorState(
            key: const ValueKey('monthly-report-failure'),
            badgeLabel: 'Not added up',
            statement: 'This month could not be added up.',
            detail: monthlyReportFailureMessage(error),
            stillTrue: 'Every sale it covers is recorded and unaffected.',
            actions: <Widget>[
              AppButton(
                label: 'Try again',
                tier: AppButtonTier.secondary,
                onPressed: _retry,
              ),
            ],
          ),
        ),
      ),
      builder: (context, session, view) => _MonthFrame(
        month: view.report.month,
        onChooseMonth: _chooseMonth,
        body: _MonthlyReportContents(
          report: view.report,
          currency: view.currency,
          // Profit is cost, and cost is owner and administrator everywhere in
          // this app. Read from the guarded session, never from the caller.
          showProfit: TenantProfitReport.canSeeInSession(session),
        ),
      ),
    );
  }
}

/// The page's frame: the header, and the month chooser under it.
final class _MonthFrame extends StatelessWidget {
  const _MonthFrame({
    required this.month,
    required this.body,
    this.onChooseMonth,
  });

  final TenantReportMonth? month;
  final Widget body;
  final void Function(int offset)? onChooseMonth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final month = this.month;
    return AppScaffold(
      title: 'Monthly report',
      subtitle: month?.label,
      contentWidth: AppContentWidth.records,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (month != null && onChooseMonth != null) ...<Widget>[
            _MonthChooser(month: month, onChoose: onChooseMonth!),
            SizedBox(height: tokens.spacing.s16),
          ],
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Back a month, forward a month, and the month's own name between them.
final class _MonthChooser extends StatelessWidget {
  const _MonthChooser({required this.month, required this.onChoose});

  final TenantReportMonth month;
  final void Function(int offset) onChoose;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Row(
      children: <Widget>[
        AppButton(
          key: const ValueKey('monthly-report-previous'),
          label: 'Earlier',
          icon: Icons.chevron_left,
          tier: AppButtonTier.tertiary,
          onPressed: () => onChoose(month.offset - 1),
        ),
        Expanded(
          child: Center(
            child: Text(
              month.label,
              key: const ValueKey('monthly-report-month'),
              style: tokens.typography.titleMedium.copyWith(
                color: tokens.colors.text.primary,
              ),
            ),
          ),
        ),
        AppButton(
          key: const ValueKey('monthly-report-next'),
          label: 'Later',
          icon: Icons.chevron_right,
          tier: AppButtonTier.tertiary,
          // The month in progress is the last one there is; forward from it is
          // a month the server refuses to answer, so the control is disabled
          // rather than offered and then rejected.
          onPressed: month.isCurrent ? null : () => onChoose(month.offset + 1),
        ),
      ],
    );
  }
}

/// The figures themselves.
final class _MonthlyReportContents extends StatelessWidget {
  const _MonthlyReportContents({
    required this.report,
    required this.currency,
    required this.showProfit,
  });

  final TenantMonthlyReport report;
  final TenantReportingCurrency currency;
  final bool showProfit;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final totals = report.totals;
    if (totals == null) {
      return const Center(
        child: EmptyState(
          key: ValueKey('monthly-report-not-begun'),
          title: 'This month has not started',
          hint: 'Choose a month that has.',
          // A calendar rather than the empty-read drawing: nothing is
          // missing here, the month simply has not happened.
          illustration: 'calendar.svg',
        ),
      );
    }
    if (totals.transactions == 0) {
      return Center(
        child: EmptyState(
          key: const ValueKey('monthly-report-empty'),
          title: 'Nothing was recorded in ${report.month.label}',
          hint: 'No sale carries a business date in this month.',
          illustration: 'no-data.svg',
        ),
      );
    }

    // Net of returns where the server sent them, and gross where it did not -
    // which is what this page showed before it did.
    final monthSales = totals.netOrGrossSales;
    final monthTransactions = totals.netOrGrossTransactions;
    final average = monthTransactions == 0
        ? 0.0
        : monthSales / monthTransactions;
    // Asked once, so the tile and the sentence under it cannot disagree about
    // whether the figure between them may be shown at all.
    final profit = totals.netOrGrossProfitReport;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (totals.basis == TenantSalesTotalsBasis.device)
            Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.s16),
              child: Text(
                'On this device, less the returns it holds. Sales or returns '
                'from other devices may not be included; the server total '
                'will replace this when available.',
                key: const ValueKey('monthly-report-device-basis'),
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ),
          if (report.isPartial)
            Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.s16),
              child: Text(
                // Said out loud, because the arrow beside every figure below
                // compares a month that is still running against one that
                // finished. Without this line that reads as a fall.
                'This month is still running, so these are figures to date. '
                'The comparison is against the whole of '
                '${report.month.previous.label}.',
                key: const ValueKey('monthly-report-partial'),
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ),
          if (!currency.isKnown)
            Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.s16),
              child: Text(
                TenantReportingCurrency.unknownNotice,
                key: const ValueKey('monthly-report-currency-unknown'),
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ),
          StatRow(
            tiles: <StatTile>[
              StatTile(
                label: 'Sales',
                value: currency.format(monthSales),
                valueKey: const ValueKey('monthly-report-sales'),
                money: true,
                detail: _changeDetail(report.salesChange),
              ),
              StatTile(
                label: 'Transactions',
                value: '$monthTransactions',
                valueKey: const ValueKey('monthly-report-transactions'),
                detail: _changeDetail(report.transactionsChange),
              ),
              StatTile(
                label: 'Average sale',
                value: currency.format(average),
                valueKey: const ValueKey('monthly-report-average'),
                money: true,
              ),
              if (showProfit)
                StatTile(
                  label: 'Profit',
                  // **Drawn as a ceiling, refused only where it is
                  // impossible.** This tile once printed `totals.profit`
                  // whatever its basis with a sentence underneath, then
                  // withheld it entirely to match the totals page. Both were
                  // one rule applied differently; `TenantProfitReport` is that
                  // rule, and `isDrawable` is the question this asks now.
                  value: profit.isDrawable
                      ? currency.format(profit.profit)
                      : '—',
                  valueKey: const ValueKey('monthly-report-profit'),
                  money: true,
                  // **The arrow still needs an exact figure.** A percentage
                  // change is computed from this month's profit and last
                  // month's, and a bound compared against a bound is not a
                  // trend. Where there is no arrow to draw, the caption says
                  // which way the figure is wrong instead.
                  detail: profit.isShowable
                      ? _changeDetail(report.profitChange)
                      : tenantProfitCeilingNote(profit),
                ),
            ],
          ),
          if (showProfit) ...<Widget>[
            SizedBox(height: tokens.spacing.s16),
            Text(
              // Word for word the statement every other surface makes, because
              // it is the same fact about the same sale lines over a different
              // stretch. A second wording here is what let a second rule in.
              tenantProfitNote(profit),
              key: const ValueKey('monthly-report-profit-note'),
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// `Up 12.4% on August 2026`, or nothing where there is no comparison.
  ///
  /// Never a colour on its own: the words carry the direction, which is
  /// `claude.md` rule 4 - status is never conveyed by colour alone.
  String? _changeDetail(double? change) {
    if (change == null) return null;
    final previous = report.month.previous.label;
    if (change == 0) return 'Level with $previous';
    final direction = change > 0 ? 'Up' : 'Down';
    return '$direction ${change.abs().toStringAsFixed(1)}% on $previous';
  }
}

/// What to say when a month cannot be added up.
String monthlyReportFailureMessage(Object error) {
  if (error is TenantSalesTotalsException) {
    return switch (error.failure) {
      TenantSalesTotalsFailure.periodTooLarge =>
        'This month holds more sales than the server will add up at once. '
            'Use the weekly report for a narrower stretch.',
      TenantSalesTotalsFailure.forbidden =>
        'This account may not read the business totals.',
      TenantSalesTotalsFailure.unavailable =>
        'The server could not be reached. The month is unchanged.',
      _ => 'The month could not be added up.',
    };
  }
  return 'The month could not be added up.';
}
