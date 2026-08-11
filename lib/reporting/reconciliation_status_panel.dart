import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import 'reconciliation_actions.dart';
import 'reconciliation_anomalies_panel.dart';
import 'reconciliation_request.dart';
import 'reconciliation_run_panel.dart';
import 'reconciliation_status.dart';

/// Route explaining how one business day reached the state the daily summary
/// reports, and - for an owner or administrator - asking the server to work.
final class TenantReconciliationStatusScreen extends StatelessWidget {
  const TenantReconciliationStatusScreen({
    super.key,
    required this.reader,
    required this.businessDate,
    this.actions,
  });

  /// The intake record is read by exact path and the runs by a bounded page, so
  /// both halves of the tenant data boundary are needed here.
  final TenantDataReader reader;

  /// The exact business day this route explains.
  final String businessDate;

  final TenantReconciliationActions? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reconciliation status')),
    body: TenantReconciliationStatusPanel(
      reader: reader,
      businessDate: businessDate,
      actions: actions,
    ),
  );
}

/// One guarded day of reconciliation state with the staff names it needs.
final class _ReconciliationView {
  const _ReconciliationView({required this.day, required this.names});

  final TenantReconciliationDay day;
  final Map<String, String> names;
}

/// Shows the server's own verdict for one business day and the runs behind it,
/// and lets an owner or administrator ask the server to reconcile.
///
/// The route guard owns authorization and stale-session rejection: a tenant
/// switch during an outstanding load discards it before it can update the UI.
///
/// Requesting is the one write here, and it is deliberately not aimed at the
/// day on screen. `requestTenantReconciliation` queues one job for the whole
/// business under **today's** business date, and the runners then take the
/// oldest outstanding day first. Presenting it as "reconcile this day" would be
/// a promise the server never made, so the surface says what it actually does.
final class TenantReconciliationStatusPanel extends StatefulWidget {
  const TenantReconciliationStatusPanel({
    super.key,
    required this.reader,
    required this.businessDate,
    this.actions,
    this.pageSize = 20,
    this.requestIdFactory,
  });

  final TenantDataReader reader;
  final String businessDate;
  final TenantReconciliationActions? actions;
  final int pageSize;

  /// One fresh request ID per confirmed intent.
  final String Function()? requestIdFactory;

  @override
  State<TenantReconciliationStatusPanel> createState() =>
      _TenantReconciliationStatusPanelState();
}

final class _TenantReconciliationStatusPanelState
    extends State<TenantReconciliationStatusPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;
  String? _notice;
  TenantReconciliationMode _mode = TenantReconciliationMode.incremental;

  /// Retained only across an ambiguous attempt, so a retry addresses the same
  /// idempotency record instead of queueing a second run.
  String? _requestId;
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

  /// Restarts the guarded load from the first page.
  void _reload() {
    setState(() {
      _cursors = <String?>[null];
      _pageIndex = 0;
      _generation++;
    });
  }

  /// Whether the session this work was authorized against is still selected.
  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  /// Asks the server to reconcile this business.
  ///
  /// The page is re-read afterwards for the same reason the stock surface
  /// re-reads: what is shown must be the server's own record, not an optimistic
  /// local one. A run queued now is filed under today's business date, so on a
  /// past day the reload will correctly show no new run - which is why the
  /// notice says where the work actually went.
  Future<void> _request(TenantSession session) async {
    final callable = widget.actions?.requestCallable;
    if (callable == null || _busy) return;
    final capturedKey = _sessionKey(session);
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final gateway = TenantReconciliationRequestGateway(
        session: session,
        callable: callable,
        requestIdFactory: () => _requestId ??=
            (widget.requestIdFactory ?? secureReconciliationRequestId)(),
      );
      final result = await gateway.submit(gateway.createIntent(mode: _mode));
      if (!_stillCurrent(capturedKey)) return;
      _requestId = null;
      setState(
        () => _notice =
            'Queued as ${result.jobId}. The server works through outstanding '
            'days oldest first, so this may regenerate another day before '
            'this one.',
      );
      _reload();
    } on TenantReconciliationRequestException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      // Only an unknown outcome may have queued anything, so only it keeps the
      // request ID. Every other refusal left nothing behind, and reusing its ID
      // would make a later attempt fail as a duplicate.
      if (!error.mayHaveQueued) _requestId = null;
      setState(() => _notice = _requestNotice(error.failure));
      if (error.mayHaveQueued) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      // The request may well have been queued; only its answer was unusable.
      setState(
        () => _notice =
            'The server answer could not be trusted. A check may have been '
            'queued; read this page again before asking for another.',
      );
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      ).loadDay(widget.businessDate, pageSize: widget.pageSize, cursor: cursor);
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
    final guardKey = '${widget.businessDate}:$_generation:$_pageIndex:$cursor';
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
        busy: _busy,
        notice: _notice,
        mode: _mode,
        // The request affordance appears only when the composition root
        // injected the callable and the session holds a role the server would
        // accept. Offering it otherwise would teach an operator nothing except
        // that the app guesses.
        canRequest:
            widget.actions?.requestCallable != null &&
            TenantReconciliationRequestGateway.canRequestInSession(session),
        // Distinguished from `canRequest` so a manager - who may read this
        // page but not act on it - is told why rather than shown nothing.
        requestOffered: widget.actions?.requestCallable != null,
        onChooseMode: (mode) => setState(() => _mode = mode),
        onRequest: () => _request(session),
        onNextPage: () => _nextPage(view.day.runs.nextCursor),
        onPreviousPage: _previousPage,
        // A run reports how many differences it found; this is which ones. The
        // list is business-wide because a difference belongs to a product, a
        // shift, or a sale rather than to a day, and it says so itself.
        // The same capabilities travel with the route: correcting a shift is
        // granted by the composition root exactly as requesting a run is, so a
        // build without it opens the read-only list it always was.
        onOpenAnomalies: () => openTenantReconciliationAnomalies(
          context,
          reader: widget.reader,
          actions: widget.actions,
        ),
      ),
    );
  }
}

/// The notice shown for one refused request.
String _requestNotice(TenantReconciliationRequestFailure failure) =>
    switch (failure) {
      TenantReconciliationRequestFailure.forbidden =>
        'Only an owner or administrator can ask for a check. Nothing was '
            'queued.',
      TenantReconciliationRequestFailure.requestedTooRecently =>
        'A check of this kind was asked for too recently, so nothing was '
            'queued. The server allows one catch-up every 5 minutes and one '
            'full check every 24 hours.',
      TenantReconciliationRequestFailure.duplicateRequest =>
        'An earlier attempt already used this request. Nothing was queued a '
            'second time; ask again to start a new one.',
      TenantReconciliationRequestFailure.invalidRequest =>
        'The server rejected this request as invalid, so nothing was queued.',
      TenantReconciliationRequestFailure.refused =>
        'The request was refused and nothing was queued.',
      TenantReconciliationRequestFailure.ambiguous =>
        'The result is unknown. A check may have been queued; this page has '
            'been read again, so check the runs below before asking for '
            'another.',
    };

final class _ReconciliationContents extends StatelessWidget {
  const _ReconciliationContents({
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.busy,
    required this.notice,
    required this.mode,
    required this.canRequest,
    required this.requestOffered,
    required this.onChooseMode,
    required this.onRequest,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onOpenAnomalies,
  });

  final _ReconciliationView view;
  final String selfUid;
  final int pageIndex;
  final bool busy;
  final String? notice;
  final TenantReconciliationMode mode;
  final bool canRequest;
  final bool requestOffered;
  final ValueChanged<TenantReconciliationMode> onChooseMode;
  final VoidCallback onRequest;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final VoidCallback onOpenAnomalies;

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
        'This page explains where that work stands. Nothing here can retry, '
        'cancel, or re-order a run.',
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
      if (notice case final message?) ...[
        const SizedBox(height: 12),
        Text(key: const ValueKey('reconciliation-request-notice'), message),
      ],
      if (requestOffered) ...[
        const SizedBox(height: 24),
        if (canRequest)
          _RequestReconciliation(
            key: const ValueKey('reconciliation-request-form'),
            mode: mode,
            busy: busy,
            onChooseMode: onChooseMode,
            onRequest: onRequest,
          )
        else
          const Text(
            key: ValueKey('reconciliation-request-forbidden'),
            'Only an owner or administrator can ask the server to reconcile. '
            'This page is readable by managers as well, so nothing here is '
            'hidden from you except that one request.',
          ),
      ],
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
      // A run states how many differences it found and could not resolve. This
      // is the only place that says which ones, so the count above is
      // actionable rather than merely alarming.
      AppButton(
        key: const ValueKey('reconciliation-status-anomalies'),
        label: 'View unresolved differences',
        icon: Icons.report_gmailerrorred_outlined,
        onPressed: onOpenAnomalies,
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            AppButton(
              key: const ValueKey('reconciliation-status-previous'),
              label: 'Previous page',
              onPressed: onPreviousPage,
            ),
          if (day.runs.hasMore)
            AppButton(
              key: const ValueKey('reconciliation-status-next'),
              label: 'Next page',
              tier: AppButtonTier.primary,
              onPressed: onNextPage,
            ),
        ],
      ),
    ],
  );

  Widget _run(BuildContext context, TenantReconciliationRun run) =>
      TenantReconciliationRunCard(
        run: run,
        names: view.names,
        selfUid: selfUid,
      );
}

/// Chooses one mode and requires an explicit confirmation.
///
/// The confirmation is not ceremony: each mode spends a cooldown the server
/// enforces and this app cannot shorten, so a mistaken tap costs a real
/// allowance - up to a whole day of it for a full check.
final class _RequestReconciliation extends StatelessWidget {
  const _RequestReconciliation({
    super.key,
    required this.mode,
    required this.busy,
    required this.onChooseMode,
    required this.onRequest,
  });

  final TenantReconciliationMode mode;
  final bool busy;
  final ValueChanged<TenantReconciliationMode> onChooseMode;
  final VoidCallback onRequest;

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ask the server to reconcile?'),
        content: Text(
          'This queues one ${mode.label.toLowerCase()} for the whole '
          'business. ${mode.description} It cannot be cancelled or re-ordered '
          'once queued.',
        ),
        actions: [
          AppButton(
            key: const ValueKey('reconciliation-request-cancel'),
            label: 'Cancel',
            tier: AppButtonTier.tertiary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            key: const ValueKey('reconciliation-request-confirm'),
            label: 'Ask for it',
            tier: AppButtonTier.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) onRequest();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Ask the server to reconcile',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      // The single most important sentence on this surface. A request is filed
      // for the business under today's business date and the runners take the
      // oldest outstanding day first, so it is not a way to reconcile the day
      // being read - and a run queued from here will not appear in the list
      // below unless that day is today.
      const Text(
        key: ValueKey('reconciliation-request-scope'),
        'A request covers the whole business, not the day above. The server '
        'files it under today and works through the outstanding days oldest '
        'first, so it may regenerate a different day before this one.',
      ),
      const SizedBox(height: 12),
      SegmentedButton<TenantReconciliationMode>(
        key: const ValueKey('reconciliation-request-mode'),
        segments: [
          for (final option in TenantReconciliationMode.values)
            ButtonSegment<TenantReconciliationMode>(
              value: option,
              label: Text(option.label),
            ),
        ],
        selected: <TenantReconciliationMode>{mode},
        onSelectionChanged: busy
            ? null
            : (selection) => onChooseMode(selection.single),
      ),
      const SizedBox(height: 8),
      Text(
        key: const ValueKey('reconciliation-request-mode-detail'),
        mode.description,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      AppButton(
        key: const ValueKey('reconciliation-request-submit'),
        label: busy ? 'Asking...' : 'Ask for a check',
        tier: AppButtonTier.primary,
        onPressed: busy ? null : () => _confirm(context),
      ),
    ],
  );
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

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}
