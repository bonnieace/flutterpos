import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_types.dart';
import 'daily_metrics.dart';
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Daily summary')),
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
  Widget build(BuildContext context) => TenantRouteGuard<_DailySummaryView>(
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
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('daily-summary-retry'),
                onPressed: _refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        builder: (context, session, view) => _DailySummaryContents(
          days: view.days,
          currency: view.currency,
          // The role is taken from the guarded session, never from the caller,
          // so the action disappears the moment the session stops allowing it.
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

final class _DailySummaryContents extends StatelessWidget {
  const _DailySummaryContents({
    required this.days,
    required this.currency,
    this.reconciliationRoute,
    this.salesTotalsRoute,
  });

  final List<TenantDailyMetricsDay> days;
  final TenantReportingCurrency currency;
  final TenantReconciliationRouteBuilder? reconciliationRoute;
  final TenantSalesTotalsRouteBuilder? salesTotalsRoute;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('daily-summary'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Daily summary',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      const Text(
        'These totals are regenerated by nightly reconciliation from the sales '
        'the server holds. Today is normally still unreconciled.',
      ),
      if (!currency.isKnown) ...[
        const SizedBox(height: 8),
        const Text(
          key: ValueKey('daily-summary-currency-unknown'),
          TenantReportingCurrency.unknownNotice,
        ),
      ],
      // Offered here because the sentence above has just explained why today
      // shows nothing. The totals route answers that exact question, from the
      // sales the server holds rather than from reconciled figures.
      if (salesTotalsRoute != null) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('daily-summary-sales-totals'),
          onPressed: () => _openSalesTotals(context),
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Total sales over a period'),
        ),
      ],
      const SizedBox(height: 16),
      for (final day in days)
        Card(
          key: ValueKey('daily-summary-${day.businessDate}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.businessDate,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (day.metrics case final metrics?) ...[
                  Text(
                    key: ValueKey('daily-summary-sales-${day.businessDate}'),
                    'Sales: ${currency.format(metrics.sales)} over '
                    '${metrics.transactions} transactions in '
                    '${metrics.shiftCount} '
                    '${metrics.shiftCount == 1 ? 'shift' : 'shifts'}',
                  ),
                  if (!metrics.hasCompleteCostData)
                    Text(
                      key: ValueKey('daily-summary-cost-${day.businessDate}'),
                      '${metrics.incompleteCostLineCount} sale lines have no '
                      'cost recorded.',
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Reconciled ${_instant(metrics.regeneratedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else
                  Text(
                    key: ValueKey('daily-summary-pending-${day.businessDate}'),
                    'Not reconciled yet.',
                  ),
                if (reconciliationRoute != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: ValueKey(
                      'daily-summary-reconciliation-${day.businessDate}',
                    ),
                    onPressed: () =>
                        _openReconciliation(context, day.businessDate),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Why is it in this state?'),
                  ),
                ],
              ],
            ),
          ),
        ),
    ],
  );

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
      MaterialPageRoute<void>(
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
