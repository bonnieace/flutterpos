import 'package:flutter/material.dart';

import '../tenancy/tenant_route_guard.dart';
import 'sales_totals.dart';

/// Route showing what a business has taken over a chosen stretch of days.
///
/// This is the one surface that can answer "how much have we taken today?".
/// The daily summary reports only what nightly reconciliation has regenerated,
/// so today - the day anybody at a counter actually asks about - is normally
/// blank there. These figures are added up by the server from the sales it
/// currently holds, which is a different question and is labelled as one.
final class TenantSalesTotalsScreen extends StatelessWidget {
  const TenantSalesTotalsScreen({
    super.key,
    required this.callable,
    this.clock,
  });

  final SalesTotalsCallable callable;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sales totals')),
    body: TenantSalesTotalsPanel(callable: callable, clock: clock),
  );
}

/// Reads one period's totals for the selected tenant session.
///
/// The route guard owns authorization and stale-session rejection: a tenant
/// switch during an outstanding read discards it before it can report one
/// business's takings under another's name.
final class TenantSalesTotalsPanel extends StatefulWidget {
  const TenantSalesTotalsPanel({
    super.key,
    required this.callable,
    this.clock,
    this.period = TenantSalesPeriod.today,
  });

  final SalesTotalsCallable callable;
  final DateTime Function()? clock;

  /// The period the surface opens on. Today, because that is the figure the
  /// daily summary cannot give.
  final TenantSalesPeriod period;

  @override
  State<TenantSalesTotalsPanel> createState() => _TenantSalesTotalsPanelState();
}

final class _TenantSalesTotalsPanelState
    extends State<TenantSalesTotalsPanel> {
  late TenantSalesPeriod _period = widget.period;
  TenantSalesScope _scope = TenantSalesScope.everyone;
  int _generation = 0;

  String? _loaderKey;
  TenantGuardedLoader<TenantSalesTotals>? _loader;

  void _choosePeriod(TenantSalesPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
  }

  void _chooseScope(TenantSalesScope scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
  }

  /// Asks again for the same period and scope.
  ///
  /// Safe without qualification: reading totals writes nothing, so a retry can
  /// never duplicate anything the way a reconciliation request could.
  void _retry() => setState(() => _generation++);

  /// One loader per guard key, so a closure rebuilt every frame cannot spend
  /// another callable invocation on an unrelated `setState`.
  TenantGuardedLoader<TenantSalesTotals> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final period = _period;
    final scope = _scope;
    return _loader = (session) async {
      final gateway = TenantSalesTotalsGateway(
        session: session,
        callable: widget.callable,
        clock: widget.clock,
      );
      return gateway.load(
        gateway.createQuery(period: period, scope: scope),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final guardKey = '${_period.name}:${_scope.name}:$_generation';
    return TenantRouteGuard<TenantSalesTotals>(
      key: ValueKey(guardKey),
      allowedRoles: TenantSalesTotalsGateway.allowedRoles,
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('sales-totals-denied'),
        child: Text('Sales totals are available to managers and owners.'),
      ),
      // The chooser stays on screen through a failure. A period that holds too
      // many sales is refused precisely so a shorter one can be picked, and
      // replacing the whole surface with an error would take that away.
      failure: (context, error) => _SalesTotalsContents(
        period: _period,
        scope: _scope,
        onChoosePeriod: _choosePeriod,
        onChooseScope: _chooseScope,
        onRetry: _retry,
        failureMessage: _failureMessage(error),
      ),
      builder: (context, session, totals) => _SalesTotalsContents(
        period: _period,
        scope: _scope,
        onChoosePeriod: _choosePeriod,
        onChooseScope: _chooseScope,
        onRetry: _retry,
        totals: totals,
      ),
    );
  }
}

/// The sentence shown for one failed read.
///
/// A `FormatException` is the strict decoder refusing an answer it could not
/// reconcile with the request. It is reported as an untrustworthy answer rather
/// than as an unavailable server, because the server did reply - and reporting
/// a figure from that reply is exactly what must not happen.
String _failureMessage(Object error) => switch (error) {
  TenantSalesTotalsException(:final failure) => switch (failure) {
    TenantSalesTotalsFailure.forbidden =>
      'This business no longer allows you to read its sales totals.',
    TenantSalesTotalsFailure.periodTooLarge =>
      'That period holds more than ${TenantSalesTotals.maximumTransactions} '
          'sales, which is more than the server will add up at once. Choose a '
          'shorter period, or read the daily summary instead.',
    TenantSalesTotalsFailure.invalidRequest =>
      'The server rejected this request, so no total was produced.',
    TenantSalesTotalsFailure.unusableSaleData =>
      'The server found a stored sale amount it could not add up, so it '
          'produced no total. Asking again will not change it.',
    TenantSalesTotalsFailure.unavailable =>
      'The totals could not be read. Nothing was changed; try again.',
    TenantSalesTotalsFailure.refused =>
      'The server refused this request, so no total was produced.',
  },
  FormatException() =>
    'The server answer could not be trusted, so no total is shown.',
  _ => 'The totals could not be read.',
};

final class _SalesTotalsContents extends StatelessWidget {
  const _SalesTotalsContents({
    required this.period,
    required this.scope,
    required this.onChoosePeriod,
    required this.onChooseScope,
    required this.onRetry,
    this.totals,
    this.failureMessage,
  });

  final TenantSalesPeriod period;
  final TenantSalesScope scope;
  final ValueChanged<TenantSalesPeriod> onChoosePeriod;
  final ValueChanged<TenantSalesScope> onChooseScope;
  final VoidCallback onRetry;
  final TenantSalesTotals? totals;
  final String? failureMessage;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('sales-totals'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Sales totals',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      const Text(
        'The server adds these up from the sales it holds right now, so a sale '
        'still waiting on a device is not in them. They are not the reconciled '
        'figures the daily summary reports.',
      ),
      const SizedBox(height: 16),
      // Chips rather than a segmented button: four periods do not fit across a
      // phone, and a chooser that overflows is a chooser that cannot be used.
      Wrap(
        key: const ValueKey('sales-totals-period'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in TenantSalesPeriod.values)
            ChoiceChip(
              key: ValueKey('sales-totals-period-${option.name}'),
              label: Text(option.label),
              selected: option == period,
              onSelected: (_) => onChoosePeriod(option),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        key: const ValueKey('sales-totals-scope'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in TenantSalesScope.values)
            ChoiceChip(
              key: ValueKey('sales-totals-scope-${option.name}'),
              label: Text(option.label),
              selected: option == scope,
              onSelected: (_) => onChooseScope(option),
            ),
        ],
      ),
      const SizedBox(height: 20),
      if (totals case final answer?) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key: const ValueKey('sales-totals-range'),
                  _range(answer.query),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  key: const ValueKey('sales-totals-amount'),
                  'Sales: ${answer.sales.toStringAsFixed(2)} over '
                  '${answer.transactions} '
                  '${answer.transactions == 1 ? 'sale' : 'sales'}',
                ),
                if (!answer.hasCompleteCostData) ...[
                  const SizedBox(height: 8),
                  Text(
                    key: const ValueKey('sales-totals-cost'),
                    '${answer.incompleteCostLineCount} sale lines have no cost '
                    'recorded, so no profit figure is shown.',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const ValueKey('sales-totals-refresh'),
          onPressed: onRetry,
          child: const Text('Read again'),
        ),
      ],
      if (failureMessage case final message?) ...[
        Text(key: const ValueKey('sales-totals-failure'), message),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const ValueKey('sales-totals-retry'),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    ],
  );

  /// Names the exact days and whose sales were counted, so a figure is never
  /// shown without the question it answers.
  String _range(TenantSalesTotalsQuery query) {
    final days = query.startDate == query.endDate
        ? query.endDate
        : '${query.startDate} to ${query.endDate}';
    return switch (query.scope) {
      TenantSalesScope.everyone => days,
      TenantSalesScope.mine => '$days • your sales only',
    };
  }
}
