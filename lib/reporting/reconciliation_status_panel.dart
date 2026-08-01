import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_names.dart';
import 'reconciliation_status.dart';

/// Read-only route explaining how one business day reached the state the daily
/// summary reports.
final class TenantReconciliationStatusScreen extends StatelessWidget {
  const TenantReconciliationStatusScreen({
    super.key,
    required this.reader,
    required this.businessDate,
  });

  /// The intake record is read by exact path and the runs by a bounded page, so
  /// both halves of the tenant data boundary are needed here.
  final TenantDataReader reader;

  /// The exact business day this route explains.
  final String businessDate;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reconciliation status')),
    body: TenantReconciliationStatusPanel(
      reader: reader,
      businessDate: businessDate,
    ),
  );
}

/// One guarded day of reconciliation state with the staff names it needs.
final class _ReconciliationView {
  const _ReconciliationView({required this.day, required this.names});

  final TenantReconciliationDay day;
  final Map<String, String> names;
}

/// Shows the server's own verdict for one business day and the runs behind it.
///
/// The route guard owns authorization and stale-session rejection: a tenant
/// switch during an outstanding load discards it before it can update the UI.
/// Nothing on this surface can queue, retry, or cancel a run.
final class TenantReconciliationStatusPanel extends StatefulWidget {
  const TenantReconciliationStatusPanel({
    super.key,
    required this.reader,
    required this.businessDate,
    this.pageSize = 20,
  });

  final TenantDataReader reader;
  final String businessDate;
  final int pageSize;

  @override
  State<TenantReconciliationStatusPanel> createState() =>
      _TenantReconciliationStatusPanelState();
}

final class _TenantReconciliationStatusPanelState
    extends State<TenantReconciliationStatusPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  TenantStaffNameResolver? _staffNames;
  String? _staffNamesSessionKey;
  String? _loaderKey;
  TenantGuardedLoader<_ReconciliationView>? _loader;

  @override
  void didUpdateWidget(covariant TenantReconciliationStatusPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A cursor is a position inside one exact query, so a different day starts
    // the page again rather than resuming from somewhere that day never had.
    if (oldWidget.businessDate != widget.businessDate) {
      setState(() {
        _cursors = <String?>[null];
        _pageIndex = 0;
      });
    }
  }

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  /// One resolver per session, so its cache can never label another session's
  /// rows. An unresolved name degrades to the authoritative UID.
  TenantStaffNameResolver _resolverFor(TenantSession session) {
    final key = _sessionKey(session);
    if (key != _staffNamesSessionKey || _staffNames == null) {
      _staffNamesSessionKey = key;
      _staffNames = TenantStaffNameResolver(
        session: session,
        reader: widget.reader,
      );
    }
    return _staffNames!;
  }

  void _nextPage(String? cursor) {
    if (cursor == null) return;
    setState(() {
      _cursors = <String?>[..._cursors.take(_pageIndex + 1), cursor];
      _pageIndex++;
    });
  }

  void _previousPage() {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex--);
  }

  /// One loader per guard key, so a closure rebuilt every frame cannot restart
  /// the load on an unrelated `setState`.
  TenantGuardedLoader<_ReconciliationView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    return _loader = (session) async {
      final day = await TenantReconciliationStatusRepository(
        session: session,
        reader: widget.reader,
      ).loadDay(
        widget.businessDate,
        pageSize: widget.pageSize,
        cursor: cursor,
      );
      // A scheduled sweep and a sale trigger name no member of the business.
      return _ReconciliationView(
        day: day,
        names: await _resolverFor(session).resolve(<String>[
          for (final run in day.runs.items)
            if (run.actorUid case final actorUid?) actorUid,
        ]),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '${widget.businessDate}:$_pageIndex:$cursor';
    return TenantRouteGuard<_ReconciliationView>(
      key: ValueKey(guardKey),
      allowedRoles: TenantReconciliationStatusRepository.allowedRoles,
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('reconciliation-status-denied'),
        child: Text(
          'Reconciliation status is available to managers and owners.',
        ),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('reconciliation-status-failure'),
        child: Text('The reconciliation status could not be loaded.'),
      ),
      builder: (context, session, view) => _ReconciliationContents(
        view: view,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        onNextPage: () => _nextPage(view.day.runs.nextCursor),
        onPreviousPage: _previousPage,
      ),
    );
  }
}

final class _ReconciliationContents extends StatelessWidget {
  const _ReconciliationContents({
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final _ReconciliationView view;
  final String selfUid;
  final int pageIndex;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  TenantReconciliationDay get day => view.day;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('reconciliation-status'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Reconciliation for ${day.businessDate}',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      const Text(
        'The server regenerates each day\'s totals from the sales it holds. '
        'This page explains where that work stands; nothing here can start, '
        'retry, or cancel it.',
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: const ValueKey('reconciliation-status-verdict'),
                _verdict(day),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (day.intake case final intake?) ...[
                const SizedBox(height: 8),
                Text(
                  key: const ValueKey('reconciliation-status-receipts'),
                  '${intake.saleReceiptCount} sale '
                  '${intake.saleReceiptCount == 1 ? 'receipt' : 'receipts'} '
                  'registered for this day.',
                ),
                Text(
                  key: const ValueKey('reconciliation-status-published'),
                  _published(intake),
                ),
                if (intake.hasInvalidSaleLines)
                  Text(
                    key: const ValueKey('reconciliation-status-invalid-lines'),
                    '${intake.invalidLineCount} sale lines could not be used, '
                    'so they moved no stock and count towards no profit.',
                  ),
                if (intake.dirtyReason case final reason?)
                  Text(
                    key: const ValueKey('reconciliation-status-reason'),
                    'Marked for regeneration by: $reason',
                  ),
                if (intake.lastErrorCode case final code?)
                  Text(
                    key: const ValueKey('reconciliation-status-error'),
                    'Server code: $code',
                  ),
                const SizedBox(height: 8),
                Text(
                  key: const ValueKey('reconciliation-status-instants'),
                  _instants(intake),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text(
        'Reconciliation runs',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      const Text(
        'A run is one unit of server work. Each one takes the oldest business '
        'day still waiting in the whole business, so a completed run is not by '
        'itself proof that this day was regenerated - the state above is.',
      ),
      const SizedBox(height: 12),
      if (day.runs.items.isEmpty)
        const Text(
          key: ValueKey('reconciliation-status-runs-empty'),
          'No reconciliation run has been queued for this day.',
        )
      else
        for (final run in day.runs.items) _run(context, run),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            OutlinedButton(
              key: const ValueKey('reconciliation-status-previous'),
              onPressed: onPreviousPage,
              child: const Text('Previous page'),
            ),
          if (day.runs.hasMore)
            FilledButton(
              key: const ValueKey('reconciliation-status-next'),
              onPressed: onNextPage,
              child: const Text('Next page'),
            ),
        ],
      ),
    ],
  );

  Widget _run(BuildContext context, TenantReconciliationRun run) => Card(
    key: ValueKey('reconciliation-status-run-${run.id}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            key: ValueKey('reconciliation-status-run-state-${run.id}'),
            '${_statusLabel(run)} • ${_sourceLabel(run)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            key: ValueKey('reconciliation-status-run-progress-${run.id}'),
            _progress(run),
          ),
          if (run.lastErrorCode case final code?)
            Text(
              key: ValueKey('reconciliation-status-run-error-${run.id}'),
              'Server code: $code',
            ),
          if (run.hasVariances)
            Text(
              key: ValueKey('reconciliation-status-run-variance-${run.id}'),
              '${run.stockVarianceCount} stock and ${run.shiftVarianceCount} '
              'shift differences were recorded.',
            ),
          if (run.rerunRequested)
            Text(
              key: ValueKey('reconciliation-status-run-rerun-${run.id}'),
              'A change arrived while this run was working, so it will run '
              'again.',
            ),
          Text(
            key: ValueKey('reconciliation-status-run-requested-${run.id}'),
            'Requested by ${_requestedByLabel(run)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  /// A member's UID resolves to a name; a `system:` actor names no member of
  /// the business and is shown as the server work it is.
  String _requestedByLabel(TenantReconciliationRun run) {
    final actorUid = run.actorUid;
    if (actorUid == null) return 'the server (${run.requestedBy})';
    return tenantStaffLabel(actorUid, names: view.names, selfUid: selfUid);
  }
}

String _verdict(TenantReconciliationDay day) => switch (day.outcome) {
  TenantReconciliationDayOutcome.noSalesRecorded =>
    'No sale has reached the server for this day, so there is nothing to '
        'reconcile.',
  TenantReconciliationDayOutcome.awaitingRegeneration =>
    'Sales are recorded for this day that the published totals do not cover '
        'yet.',
  TenantReconciliationDayOutcome.regenerated =>
    'The published totals cover every sale the server holds for this day.',
  TenantReconciliationDayOutcome.blocked =>
    'The server stopped reconciling this day and recorded why.',
  // An unmodelled status is named rather than guessed at: a server deploy that
  // introduces one is not evidence of anything wrong, and reporting it as
  // reconciled or pending would be inventing an answer.
  TenantReconciliationDayOutcome.unrecognised =>
    'The server recorded a state this app does not recognise: '
        '"${day.intake!.statusValue}".',
};

String _published(TenantReconciliationIntake intake) {
  final processed = intake.processedRevision;
  if (processed == null) {
    return 'The published totals have never been generated for this day.';
  }
  if (intake.hasUnpublishedSales) {
    return 'The published totals were generated from change $processed; the '
        'day has since reached change ${intake.revision}.';
  }
  return 'The published totals were generated from change ${intake.revision}.';
}

String _instants(TenantReconciliationIntake intake) {
  final received = intake.lastReceiptAt;
  final regenerated = intake.processedAt;
  return <String>[
    received == null
        ? 'No sale receipt instant recorded'
        : 'Last sale received ${_instant(received)}',
    regenerated == null
        ? 'Never regenerated'
        : 'Last regenerated ${_instant(regenerated)}',
  ].join(' • ');
}

/// An unmodelled value is shown as itself: hiding a real run, or renaming its
/// state, would be worse than naming what the server actually recorded.
String _statusLabel(TenantReconciliationRun run) =>
    run.status == TenantReconciliationRunStatus.other
    ? run.statusValue
    : run.status.label;

String _sourceLabel(TenantReconciliationRun run) =>
    run.source == TenantReconciliationRunSource.other
    ? run.sourceValue
    : run.source.label;

String _phaseLabel(TenantReconciliationRun run) =>
    run.phase == TenantReconciliationRunPhase.other
    ? run.phaseValue
    : run.phase.label;

String _modeLabel(TenantReconciliationRun run) => switch (run.mode) {
  'incremental' => 'Incremental',
  'full' => 'Full check',
  final other => other,
};

String _progress(TenantReconciliationRun run) {
  final attempts =
      '${run.attemptCount} '
      '${run.attemptCount == 1 ? 'attempt' : 'attempts'}';
  final failures = run.consecutiveFailureCount == 0
      ? ''
      : ', ${run.consecutiveFailureCount} in a row failed';
  return '${_modeLabel(run)} • reached ${_phaseLabel(run)} • '
      '$attempts$failures';
}

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}
