import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import 'reconciliation_actions.dart';
import 'reconciliation_anomalies.dart';
import 'shift_amendment.dart';
import 'shift_amendment_feed_panel.dart';

/// Opens the list under the caller's own session scope, so a tenant switch
/// invalidates it exactly as it does every other guarded route rather than
/// leaving a detached screen behind.
///
/// It needs no injected route builder: both this and the run list that points
/// at it belong to the reporting domain, so nothing crosses a domain boundary.
void openTenantReconciliationAnomalies(
  BuildContext context, {
  required TenantDataReader reader,
  TenantReconciliationAnomalyKind? kind,
  TenantReconciliationActions? actions,
}) {
  final controller = TenantSessionScope.of(context);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TenantSessionScope(
        controller: controller,
        child: TenantReconciliationAnomalyScreen(
          reader: reader,
          kind: kind,
          actions: actions,
        ),
      ),
    ),
  );
}

/// Route listing the differences reconciliation found and could not resolve.
///
/// The runs page reports how many stock and shift differences a run found. This
/// says which ones, which is the only thing that makes a count actionable.
final class TenantReconciliationAnomalyScreen extends StatelessWidget {
  const TenantReconciliationAnomalyScreen({
    super.key,
    required this.reader,
    this.kind,
    this.actions,
  });

  final TenantDataReader reader;

  /// Opens the list already narrowed to one kind.
  final TenantReconciliationAnomalyKind? kind;

  final TenantReconciliationActions? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Unresolved differences')),
    body: TenantReconciliationAnomalyPanel(
      reader: reader,
      kind: kind,
      actions: actions,
    ),
  );
}

/// Shows one bounded page of recorded differences, optionally narrowed to one
/// kind, and - for an owner or administrator - resolves a shift difference.
///
/// The route guard owns authorization and stale-session rejection: a tenant
/// switch during an outstanding page discards it before it can update the UI.
///
/// Correcting a shift is the one write here, and it is deliberately the only
/// resolution offered. A stock difference is corrected from the product it
/// belongs to, and the other four kinds are reports of unreadable data rather
/// than of a figure that can be put right.
final class TenantReconciliationAnomalyPanel extends StatefulWidget {
  const TenantReconciliationAnomalyPanel({
    super.key,
    required this.reader,
    this.kind,
    this.actions,
    this.pageSize = 20,
    this.requestIdFactory,
  });

  final TenantDataReader reader;
  final TenantReconciliationAnomalyKind? kind;
  final TenantReconciliationActions? actions;
  final int pageSize;

  /// One fresh request ID per confirmed correction.
  final String Function()? requestIdFactory;

  @override
  State<TenantReconciliationAnomalyPanel> createState() =>
      _TenantReconciliationAnomalyPanelState();
}

final class _TenantReconciliationAnomalyPanelState
    extends State<TenantReconciliationAnomalyPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;
  String? _notice;

  /// The shift the current notice is about, when its corrections trail is worth
  /// offering beside it.
  ///
  /// Set after a correction that succeeded - the row it resolved has been deleted,
  /// so the trail is the only remaining account of it - and after one whose
  /// outcome is unknown, where whether a correction was recorded is exactly the
  /// open question. Left null for a refusal that certainly changed nothing.
  String? _noticeShiftId;

  TenantReconciliationAnomalyKind? _kind;

  /// Retained only across an ambiguous attempt, so a retry addresses the same
  /// idempotency record instead of writing a second amendment.
  String? _requestId;
  String? _loaderKey;
  TenantGuardedLoader<TenantReconciliationAnomalyPage>? _loader;

  @override
  void initState() {
    super.initState();
    _kind = widget.kind;
  }

  @override
  void didUpdateWidget(covariant TenantReconciliationAnomalyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) _narrow(widget.kind);
  }

  /// A cursor is a position inside one exact query, so changing the filter
  /// starts the list again rather than resuming from somewhere the new query
  /// never established.
  void _narrow(TenantReconciliationAnomalyKind? kind) {
    setState(() {
      _kind = kind;
      _cursors = <String?>[null];
      _pageIndex = 0;
    });
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
  ///
  /// A resolved difference is deleted by the server, so the list must be read
  /// again rather than edited locally: what is shown has to be the server's own
  /// record of what is still open.
  void _reload() {
    setState(() {
      _cursors = <String?>[null];
      _pageIndex = 0;
      _generation++;
    });
  }

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  /// Whether the session this work was authorized against is still selected.
  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  /// Corrects one closed shift's summary to the total its own sales prove.
  Future<void> _amend(
    TenantSession session,
    TenantReconciliationAnomaly anomaly,
    String reason,
  ) async {
    final callable = widget.actions?.amendShiftSummaryCallable;
    final shiftId = anomaly.shiftId;
    if (callable == null || shiftId == null || _busy) return;
    final capturedKey = _sessionKey(session);
    setState(() {
      _busy = true;
      _notice = null;
      _noticeShiftId = null;
    });
    try {
      final gateway = TenantShiftAmendmentGateway(
        session: session,
        callable: callable,
        requestIdFactory: () => _requestId ??=
            (widget.requestIdFactory ?? secureShiftAmendmentRequestId)(),
      );
      final result = await gateway.submit(
        gateway.createIntent(shiftId: shiftId, reason: reason),
      );
      if (!_stillCurrent(capturedKey)) return;
      _requestId = null;
      setState(() {
        _notice = _amendedNotice(result);
        // The server's own answer, not the shift this page asked about, so the
        // trail offered beside the notice is narrowed to the shift that was
        // actually corrected.
        _noticeShiftId = result.shiftId;
      });
      _reload();
    } on TenantShiftAmendmentException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      // Only an unknown outcome may have amended anything, so only it keeps the
      // request ID. Every other refusal left the shift exactly as it was, and
      // reusing its ID would make a later attempt fail as a duplicate.
      if (!error.mayHaveAmended) _requestId = null;
      setState(() {
        _notice = _refusalNotice(error.failure);
        // Whether a correction was recorded is the open question after an unknown
        // outcome, and the trail is where it is answered. A refusal that certainly
        // changed nothing has nothing to look at.
        _noticeShiftId = error.mayHaveAmended ? shiftId : null;
      });
      if (error.mayHaveAmended) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      // The shift may well have been amended; only the answer was unusable.
      setState(() {
        _notice =
            'The server answer could not be trusted. The shift may have been '
            'corrected; this list has been read again, so check whether the '
            'difference is still listed - or this shift\'s corrections - before '
            'trying once more.';
        _noticeShiftId = shiftId;
      });
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One loader per guard key, so a closure rebuilt every frame cannot restart
  /// the load on an unrelated `setState`.
  TenantGuardedLoader<TenantReconciliationAnomalyPage> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    final kind = _kind;
    return _loader = (session) =>
        TenantReconciliationAnomalyRepository(
          session: session,
          reader: widget.reader,
        ).loadPage(kind: kind, pageSize: widget.pageSize, cursor: cursor);
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey =
        '${_kind?.wireValue}:$_generation:$_pageIndex:$cursor';
    return TenantRouteGuard<TenantReconciliationAnomalyPage>(
      key: ValueKey(guardKey),
      allowedRoles: TenantReconciliationAnomalyRepository.allowedRoles,
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('reconciliation-anomalies-denied'),
        child: Text(
          'Unresolved differences are available to managers and owners.',
        ),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('reconciliation-anomalies-failure'),
        child: Text('The unresolved differences could not be loaded.'),
      ),
      builder: (context, session, page) => _AnomalyContents(
        page: page,
        selected: _kind,
        pageIndex: _pageIndex,
        busy: _busy,
        notice: _notice,
        noticeShiftId: _noticeShiftId,
        // The correction appears only when the composition root injected the
        // callable and the session holds a role the server would accept.
        // Offering it otherwise would teach an operator nothing except that the
        // app guesses.
        canAmend:
            widget.actions?.amendShiftSummaryCallable != null &&
            TenantShiftAmendmentGateway.canAmendInSession(session),
        // Distinguished from `canAmend` so a manager - who may read this list
        // but not act on it - is told why rather than shown nothing.
        amendOffered: widget.actions?.amendShiftSummaryCallable != null,
        onAmend: (anomaly, reason) => _amend(session, anomaly, reason),
        onNarrow: _narrow,
        // The trail is a read of the same business under the same reader, so it
        // needs no injected capability: unlike the correction itself, there is
        // nothing here for a composition root to grant or withhold. It also needs
        // no role check of its own - this list and the trail are granted to the
        // same three roles, so anyone reading this page can read the trail.
        onOpenAmendments: (shiftId) => openTenantShiftAmendments(
          context,
          reader: widget.reader,
          shiftId: shiftId,
        ),
        onNextPage: () => _nextPage(page.nextCursor),
        onPreviousPage: _previousPage,
      ),
    );
  }
}

/// What one successful correction actually changed, stated from the server's own
/// answer rather than from what was asked for.
String _amendedNotice(TenantShiftAmendmentResult result) {
  final from = _money(result.previousTotalSalesMinor);
  final to = _money(result.totalSalesMinor);
  final counts = result.previousTransactionCount == result.transactionCount
      ? 'over the same ${result.transactionCount} '
            '${result.transactionCount == 1 ? 'transaction' : 'transactions'}'
      : 'over ${result.transactionCount} '
            '${result.transactionCount == 1 ? 'transaction' : 'transactions'} '
            'rather than ${result.previousTransactionCount}';
  return 'Shift ${result.shiftId} on ${result.businessDate} now records $to '
      'instead of $from, $counts. The counted cash was not changed. Recorded as '
      '${result.amendmentId}.';
}

/// The notice shown for one refused correction.
String _refusalNotice(TenantShiftAmendmentFailure failure) => switch (failure) {
  TenantShiftAmendmentFailure.forbidden =>
    'Only an owner or administrator can correct a shift. Nothing was changed.',
  TenantShiftAmendmentFailure.invalidReason =>
    'A reason of between 3 and 500 characters is required, and it cannot '
        'contain control characters. Nothing was sent.',
  TenantShiftAmendmentFailure.notAmendable =>
    'The server refused: this shift cannot be corrected. It is still open, it '
        'already agrees with its sales, its difference has not been settled by '
        'a completed check yet, or it recorded no readable totals at all. '
        'Nothing was changed.',
  TenantShiftAmendmentFailure.shiftNotFound =>
    'No such shift exists in this business, so nothing was changed.',
  TenantShiftAmendmentFailure.duplicateRequest =>
    'An earlier attempt already used this request. Nothing was changed a '
        'second time; try again to start a new one.',
  TenantShiftAmendmentFailure.invalidRequest =>
    'The server rejected this request as invalid, so nothing was changed.',
  TenantShiftAmendmentFailure.refused =>
    'The correction was refused and nothing was changed.',
  TenantShiftAmendmentFailure.ambiguous =>
    'The result is unknown. The shift may have been corrected; this list has '
        'been read again, so check whether the difference is still listed '
        'before trying once more.',
};

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

final class _AnomalyContents extends StatelessWidget {
  const _AnomalyContents({
    required this.page,
    required this.selected,
    required this.pageIndex,
    required this.busy,
    required this.notice,
    required this.noticeShiftId,
    required this.canAmend,
    required this.amendOffered,
    required this.onAmend,
    required this.onNarrow,
    required this.onOpenAmendments,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final TenantReconciliationAnomalyPage page;
  final TenantReconciliationAnomalyKind? selected;
  final int pageIndex;
  final bool busy;
  final String? notice;

  /// The shift the notice is about, when its trail is worth offering beside it.
  final String? noticeShiftId;

  final bool canAmend;
  final bool amendOffered;
  final void Function(TenantReconciliationAnomaly anomaly, String reason)
  onAmend;
  final ValueChanged<TenantReconciliationAnomalyKind?> onNarrow;

  /// Opens the trail of corrections already made, for one shift or - with null -
  /// for the whole business. A resolved difference is deleted from this list, so
  /// this is the only place they remain visible.
  final ValueChanged<String?> onOpenAmendments;

  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  /// Whether this page lists a difference the correction could act on. The
  /// explanation for a manager is shown once, and only when there is something
  /// on screen it would apply to.
  bool get _listsShiftVariance => page.items.any(
    (anomaly) =>
        anomaly.kind == TenantReconciliationAnomalyKind.shiftVariance,
  );

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('reconciliation-anomalies'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Unresolved differences',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      const Text(
        key: ValueKey('reconciliation-anomalies-scope'),
        'These are the differences the server found and could not resolve on '
        'its own. They belong to a product, a shift, or a sale rather than to '
        'one business day, so this list covers the whole business and is not '
        'narrowed to the day you came from.',
      ),
      const SizedBox(height: 4),
      Text(
        key: const ValueKey('reconciliation-anomalies-writes'),
        canAmend
            ? 'A shift whose totals disagree with its sales can be corrected '
                  'here, to the total those sales prove and nothing else. Its '
                  'counted cash is never changed. Correct a stock figure from '
                  'the product it belongs to.'
            : 'Nothing here changed stock, a shift, or a sale, and nothing on '
                  'this page can. Correct a stock figure from the product it '
                  'belongs to.',
      ),
      if (notice case final message?) ...[
        const SizedBox(height: 12),
        Text(key: const ValueKey('reconciliation-amend-notice'), message),
        // The row this notice is about has been deleted from the list, or may
        // have been, so without this the correction it names would be reachable
        // only by opening the whole business's trail and reading down.
        if (noticeShiftId case final shiftId?) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('reconciliation-amend-notice-trail'),
              onPressed: () => onOpenAmendments(shiftId),
              icon: const Icon(Icons.history_edu_outlined),
              label: const Text('View this shift\'s corrections'),
            ),
          ),
        ],
      ],
      if (amendOffered && !canAmend && _listsShiftVariance) ...[
        const SizedBox(height: 12),
        const Text(
          key: ValueKey('reconciliation-amend-forbidden'),
          'Correcting a shift\'s totals is available to owners and '
          'administrators. This list is readable by managers as well, so '
          'nothing here is hidden from you except that one correction.',
        ),
      ],
      const SizedBox(height: 16),
      _KindChips(selected: selected, onNarrow: onNarrow),
      const SizedBox(height: 16),
      if (page.items.isEmpty)
        Text(
          key: const ValueKey('reconciliation-anomalies-empty'),
          selected == null
              ? 'The server has recorded no unresolved differences for this '
                    'business.'
              : 'No unresolved difference of this kind has been recorded.',
        )
      else
        for (final anomaly in page.items) _anomaly(context, anomaly),
      const SizedBox(height: 8),
      Text(
        'This list is not in time order: a record is addressed by what it is '
        'about, not by when it was found. Each one states its own instants.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      // A resolved difference is deleted from this list, so without this the
      // corrections made here would leave no visible trace. The trail is
      // readable by every role that reads this list, including the managers who
      // may not make one.
      OutlinedButton.icon(
        key: const ValueKey('reconciliation-anomalies-amendments'),
        onPressed: () => onOpenAmendments(null),
        icon: const Icon(Icons.history_edu_outlined),
        label: const Text('View shift corrections already made'),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            OutlinedButton(
              key: const ValueKey('reconciliation-anomalies-previous'),
              onPressed: onPreviousPage,
              child: const Text('Previous page'),
            ),
          if (page.hasMore)
            FilledButton(
              key: const ValueKey('reconciliation-anomalies-next'),
              onPressed: onNextPage,
              child: const Text('Next page'),
            ),
        ],
      ),
    ],
  );

  /// True only for the one kind the server can resolve, and only when this
  /// session may ask it to. A shift ID is required because the correction names
  /// the shift; a record of that kind without one is refused by the read model
  /// long before it reaches here.
  bool _canAmendRow(TenantReconciliationAnomaly anomaly) =>
      canAmend &&
      anomaly.kind == TenantReconciliationAnomalyKind.shiftVariance &&
      anomaly.shiftId != null;

  Widget _anomaly(BuildContext context, TenantReconciliationAnomaly anomaly) =>
      Card(
        key: ValueKey('reconciliation-anomaly-${anomaly.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: ValueKey('reconciliation-anomaly-kind-${anomaly.id}'),
                anomaly.kind == TenantReconciliationAnomalyKind.other
                    ? 'Unrecognised difference: ${anomaly.kindValue}'
                    : anomaly.kind.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                key: ValueKey('reconciliation-anomaly-subject-${anomaly.id}'),
                _subject(anomaly),
              ),
              if (_detail(anomaly) case final detail?)
                Text(
                  key: ValueKey('reconciliation-anomaly-detail-${anomaly.id}'),
                  detail,
                ),
              const SizedBox(height: 4),
              Text(
                key: ValueKey('reconciliation-anomaly-instants-${anomaly.id}'),
                _instants(anomaly),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_canAmendRow(anomaly) || anomaly.shiftId != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (_canAmendRow(anomaly))
                      OutlinedButton.icon(
                        key: ValueKey(
                          'reconciliation-anomaly-amend-${anomaly.id}',
                        ),
                        onPressed: busy
                            ? null
                            : () => _confirmAmend(context, anomaly),
                        icon: const Icon(Icons.rule_outlined),
                        label: Text(
                          busy ? 'Correcting...' : 'Correct this shift\'s totals',
                        ),
                      ),
                    // Offered for every row that names a shift, not only the one
                    // kind that can be corrected. A shift already corrected at a
                    // later generation can still be listed under an earlier one,
                    // so "has this already been dealt with" is a real question
                    // here - and the answer, including "never", comes from the
                    // trail rather than from this list.
                    if (anomaly.shiftId case final shiftId?)
                      OutlinedButton(
                        key: ValueKey(
                          'reconciliation-anomaly-corrections-${anomaly.id}',
                        ),
                        onPressed: () => onOpenAmendments(shiftId),
                        child: const Text('View this shift\'s corrections'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );

  /// Requires a reason and an explicit confirmation.
  ///
  /// The confirmation is not ceremony. This rewrites a record every other part
  /// of the app treats as final, and the reason is stored in the business's
  /// immutable amendment trail beside the name of whoever asked for it.
  Future<void> _confirmAmend(
    BuildContext context,
    TenantReconciliationAnomaly anomaly,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _AmendShiftDialog(anomaly: anomaly),
    );
    if (reason != null) onAmend(anomaly, reason);
  }
}

/// Collects the one input a correction takes, and says what it will do.
final class _AmendShiftDialog extends StatefulWidget {
  const _AmendShiftDialog({required this.anomaly});

  final TenantReconciliationAnomaly anomaly;

  @override
  State<_AmendShiftDialog> createState() => _AmendShiftDialogState();
}

final class _AmendShiftDialogState extends State<_AmendShiftDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Correct this shift\'s totals?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The two sentences that decide whether this is safe to agree to: the
        // figure is not a choice, and the drawer count is untouched.
        Text(
          key: const ValueKey('reconciliation-amend-explanation'),
          'Shift ${widget.anomaly.shiftId} will record the sales total the '
          'server aggregated from the sales filed against it. You cannot '
          'choose the figure, and the cash counted at close is not changed.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('reconciliation-amend-reason'),
          controller: _reason,
          autofocus: true,
          maxLength: 500,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Why is this being corrected?',
            helperText: 'Kept in the business\'s record of the correction.',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        key: const ValueKey('reconciliation-amend-cancel'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('reconciliation-amend-confirm'),
        onPressed: () => Navigator.of(context).pop(_reason.text),
        child: const Text('Correct it'),
      ),
    ],
  );
}

/// What the difference is about. The identity is the ID the rest of the app
/// attributes by, so it is always shown rather than resolved to a name.
String _subject(TenantReconciliationAnomaly anomaly) {
  if (anomaly.productId case final productId?) return 'Product $productId';
  if (anomaly.shiftId case final shiftId?) return 'Shift $shiftId';
  if (anomaly.saleId case final saleId?) return 'Sale $saleId';
  return 'This business';
}

/// The figures the record itself carries, stated and never recomputed.
String? _detail(TenantReconciliationAnomaly anomaly) {
  if (anomaly.invalidLineCount case final count?) {
    return '$count sale ${count == 1 ? 'line' : 'lines'} could not be read, so '
        'they moved no stock.';
  }
  if (anomaly.isStockAnomaly) {
    final variance = anomaly.quantityVariance!;
    final direction = variance > 0 ? 'more' : 'fewer';
    return 'Its ledger expects ${anomaly.expectedQuantity}, and the product '
        'records ${anomaly.observedQuantity}: ${variance.abs()} $direction '
        'than the ledger accounts for.';
  }
  if (anomaly.kind == TenantReconciliationAnomalyKind.invalidOrMissingShift) {
    return 'The shift is missing, or did not record the totals a comparison '
        'needs, so no difference could be measured.';
  }
  if (anomaly.kind == TenantReconciliationAnomalyKind.shiftVariance) {
    return 'Its sales total ${_signed(anomaly.salesVariance!)} and its '
        'transaction count ${_signed(anomaly.transactionVariance!)} against '
        'the sales recorded during it.';
  }
  return null;
}

String _signed(num value) {
  if (value == 0) return 'agrees';
  return value > 0 ? 'is $value over' : 'is ${value.abs()} short';
}

String _instants(TenantReconciliationAnomaly anomaly) {
  final parts = <String>[
    if (anomaly.recordedAt case final at?) 'First recorded ${_time(at)}',
    if (anomaly.updatedAt case final at?) 'last seen ${_time(at)}',
    if (anomaly.jobId case final jobId?) 'found by run $jobId',
  ];
  // A record with no recorded time still proves the difference was found, so it
  // is named as such rather than hidden.
  if (parts.isEmpty) return 'No time was recorded for this difference.';
  return '${parts.join(', ')}.';
}

String _time(DateTime value) => value.toIso8601String();

/// One chip per kind this client models, plus every kind.
///
/// `other` is deliberately absent: it names every kind this build does not
/// model, so it identifies no stored value and cannot be asked for. Those
/// records still appear in the unnarrowed list.
final class _KindChips extends StatelessWidget {
  const _KindChips({required this.selected, required this.onNarrow});

  final TenantReconciliationAnomalyKind? selected;
  final ValueChanged<TenantReconciliationAnomalyKind?> onNarrow;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      ChoiceChip(
        key: const ValueKey('reconciliation-anomaly-kind-all'),
        label: const Text('Every kind'),
        selected: selected == null,
        onSelected: (_) => onNarrow(null),
      ),
      for (final kind in TenantReconciliationAnomalyKind.values)
        if (kind != TenantReconciliationAnomalyKind.other)
          ChoiceChip(
            key: ValueKey('reconciliation-anomaly-kind-${kind.wireValue}'),
            label: Text(kind.label),
            selected: selected == kind,
            onSelected: (_) => onNarrow(kind),
          ),
    ],
  );
}
