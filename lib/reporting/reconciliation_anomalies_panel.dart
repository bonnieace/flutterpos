import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../ui/record_list.dart' show RecordAction;
import '../ui/record_sheet.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/money_text.dart';
import '../ui/pagination.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/stats.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'reconciliation_actions.dart';
import 'reconciliation_anomalies.dart';
import 'reconciliation_labels.dart';
import 'reconciliation_run_panel.dart';
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
    AppPageRoute<void>(
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
  Widget build(BuildContext context) => AppScaffold(
    title: 'Unresolved differences',
    contentWidth: RecordSheet.contentWidth(context),
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

  /// Reports one correction's outcome over the screen, with the way back to
  /// what it recorded.
  ///
  /// **This surface was the one exception to the 2026-08-26 sweep and is not an
  /// exception any more.** It kept its `Callout` because the confirmation
  /// carries the *View this shift's corrections* control, and it carries that
  /// because the row the sentence is about has just been deleted from the list.
  /// The product owner's direction on 2026-09-03 is that every outcome is a
  /// snack bar, so the control comes with it: `showAppSnackBar` takes an action
  /// exactly as `Callout` does. **What is genuinely lost is dwell** - the button
  /// withdraws itself after a few seconds where before it stayed - and the trail
  /// remains reachable from the business's own corrections list.
  ///
  /// [shiftId] is the shift whose trail is worth offering: the one a correction
  /// resolved, or the one whose outcome is unknown, where whether anything was
  /// recorded is exactly the open question. Null for a refusal that certainly
  /// changed nothing.
  void _report(AppNotice notice, {String? shiftId}) => showAppSnackBar(
    context,
    notice,
    action: shiftId == null
        ? null
        : AppButton(
            key: const ValueKey('reconciliation-amend-notice-trail'),
            label: 'View this shift\'s corrections',
            icon: Icons.history_edu_outlined,
            onPressed: () => openTenantShiftAmendments(
              context,
              reader: widget.reader,
              shiftId: shiftId,
            ),
          ),
  );

  TenantReconciliationAnomalyKind? _kind;

  /// Retained only across an ambiguous attempt, so a retry addresses the same
  /// idempotency record instead of writing a second amendment.
  String? _requestId;
  String? _loaderKey;
  TenantGuardedLoader<TenantReconciliationAnomalyPage>? _loader;
  TenantGuardedLoader<TenantReconciliationAnomalyPage>? _loaderCached;

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
    setState(() => _busy = true);
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
      // The server's own answer, not the shift this page asked about, so the
      // trail offered beside the notice is narrowed to the shift that was
      // actually corrected.
      _report(_amendedNotice(result), shiftId: result.shiftId);
      _reload();
    } on TenantShiftAmendmentException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      // Only an unknown outcome may have amended anything, so only it keeps the
      // request ID. Every other refusal left the shift exactly as it was, and
      // reusing its ID would make a later attempt fail as a duplicate.
      if (!error.mayHaveAmended) _requestId = null;
      // Whether a correction was recorded is the open question after an unknown
      // outcome, and the trail is where it is answered. A refusal that certainly
      // changed nothing has nothing to look at.
      _report(
        _refusalNotice(error.failure),
        shiftId: error.mayHaveAmended ? shiftId : null,
      );
      if (error.mayHaveAmended) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      // The shift may well have been amended; only the answer was unusable.
      _report(
        const AppNotice.unknown(
          'The server answer could not be trusted. The shift may have been '
          'corrected; this list has been read again, so check whether the '
          'difference is still listed - or this shift\'s corrections - before '
          'trying once more.',
        ),
        shiftId: shiftId,
      );
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One loader per guard key, so a closure rebuilt every frame cannot restart
  /// the load on an unrelated `setState`.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    final kind = _kind;
    TenantGuardedLoader<TenantReconciliationAnomalyPage> readWith(
      TenantDataReader reader,
    ) =>
        (session) => TenantReconciliationAnomalyRepository(
          session: session,
          reader: reader,
        ).loadPage(kind: kind, pageSize: widget.pageSize, cursor: cursor);
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '${_kind?.wireValue}:$_generation:$_pageIndex:$cursor';
    _composeLoaders(guardKey);
    return TenantRouteGuard<TenantReconciliationAnomalyPage>(
      allowedRoles: TenantReconciliationAnomalyRepository.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      holdsNothing: (page) => page.items.isEmpty,
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
        // Each row already names the run that found it. This is the same read of
        // the same business under the same reader, granted to the same three
        // roles, so like the trail it needs no injected capability.
        onOpenRun: (jobId) => openTenantReconciliationRun(
          context,
          reader: widget.reader,
          jobId: jobId,
        ),
        onNextPage: () => _nextPage(page.nextCursor),
        onPreviousPage: _previousPage,
      ),
    );
  }
}

/// What one successful correction actually changed, stated from the server's own
/// answer rather than from what was asked for.
AppNotice _amendedNotice(TenantShiftAmendmentResult result) =>
    AppNotice.confirmed(_amendedMessage(result));

String _amendedMessage(TenantShiftAmendmentResult result) {
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
///
/// **Seven of the eight are `refused` and one is not**, on the same split the
/// day page's request notices take: `ambiguous` is the only branch where the
/// shift may actually have been corrected, and it is the only one whose sentence
/// sends a person to look. Every other branch states, in its own words, that
/// nothing changed.
AppNotice _refusalNotice(TenantShiftAmendmentFailure failure) =>
    switch (failure) {
      TenantShiftAmendmentFailure.forbidden => const AppNotice.refused(
        'Only an owner or administrator can correct a shift. Nothing was '
        'changed.',
      ),
      TenantShiftAmendmentFailure.invalidReason => const AppNotice.refused(
        'A reason of between 3 and 500 characters is required, and it cannot '
        'contain control characters. Nothing was sent.',
      ),
      TenantShiftAmendmentFailure.notAmendable => const AppNotice.refused(
        'The server refused: this shift cannot be corrected. It is still open, '
        'it already agrees with its sales, its difference has not been settled '
        'by a completed check yet, or it recorded no readable totals at all. '
        'Nothing was changed.',
      ),
      TenantShiftAmendmentFailure.shiftNotFound => const AppNotice.refused(
        'No such shift exists in this business, so nothing was changed.',
      ),
      TenantShiftAmendmentFailure.duplicateRequest => const AppNotice.refused(
        'An earlier attempt already used this request. Nothing was changed a '
        'second time; try again to start a new one.',
      ),
      TenantShiftAmendmentFailure.invalidRequest => const AppNotice.refused(
        'The server rejected this request as invalid, so nothing was changed.',
      ),
      TenantShiftAmendmentFailure.refused => const AppNotice.refused(
        'The correction was refused and nothing was changed.',
      ),
      TenantShiftAmendmentFailure.ambiguous => const AppNotice.unknown(
        'The result is unknown. The shift may have been corrected; this list '
        'has been read again, so check whether the difference is still listed '
        'before trying once more.',
      ),
    };

String _money(int minorUnits) => moneyTextOfMinor(minorUnits);

final class _AnomalyContents extends StatelessWidget {
  const _AnomalyContents({
    required this.page,
    required this.selected,
    required this.pageIndex,
    required this.busy,
    required this.canAmend,
    required this.amendOffered,
    required this.onAmend,
    required this.onNarrow,
    required this.onOpenAmendments,
    required this.onOpenRun,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final TenantReconciliationAnomalyPage page;
  final TenantReconciliationAnomalyKind? selected;
  final int pageIndex;
  final bool busy;

  final bool canAmend;
  final bool amendOffered;
  final void Function(TenantReconciliationAnomaly anomaly, String reason)
  onAmend;
  final ValueChanged<TenantReconciliationAnomalyKind?> onNarrow;

  /// Opens the trail of corrections already made, for one shift or - with null -
  /// for the whole business. A resolved difference is deleted from this list, so
  /// this is the only place they remain visible.
  final ValueChanged<String?> onOpenAmendments;

  /// Opens the run a row names as having found it.
  final ValueChanged<String> onOpenRun;

  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  /// Whether this page lists a difference the correction could act on. The
  /// explanation for a manager is shown once, and only when there is something
  /// on screen it would apply to.
  bool get _listsShiftVariance => page.items.any(
    (anomaly) => anomaly.kind == TenantReconciliationAnomalyKind.shiftVariance,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return PagedListView(
      listKey: const ValueKey('reconciliation-anomalies'),
      padding: RecordSheet.pagePadding(
        context,
        fallback: EdgeInsets.all(tokens.spacing.s20),
      ),
      pagination: Pagination(
        pageNumber: pageIndex + 1,
        previousKey: const ValueKey('reconciliation-anomalies-previous'),
        nextKey: const ValueKey('reconciliation-anomalies-next'),
        onPrevious: pageIndex > 0 ? onPreviousPage : null,
        onNext: page.hasMore ? onNextPage : null,
        endOfList: !page.hasMore,
      ),
      children: [
        // §7's "Title appears once": the `AppScaffold` above carries this exact
        // string in its `PageHeader`. The only literal repeat of the fourteen.
        // Three permanent helper paragraphs behind one fold, which is §5.1's own
        // description of what `Disclosure` replaces. All three are true of every
        // record this route will ever list - what the list covers, what can be
        // corrected from it, and why it is not in time order - and the third
        // used to sit *below* the records as a loose caption, which is the least
        // likely place for a person to look for the reason the order surprised
        // them.
        Disclosure(
          key: const ValueKey('reconciliation-anomalies-scope-disclosure'),
          summary: 'What this list covers',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                key: ValueKey('reconciliation-anomalies-scope'),
                'These are the differences the server found and could not '
                'resolve on its own. They belong to a product, a shift, or a '
                'sale rather than to one business day, so this list covers the '
                'whole business and is not narrowed to the day you came from.',
              ),
              SizedBox(height: tokens.spacing.s8),
              Text(
                key: const ValueKey('reconciliation-anomalies-writes'),
                canAmend
                    ? 'A shift whose totals disagree with its sales can be '
                          'corrected here, to the total those sales prove and '
                          'nothing else. Its counted cash is never changed. '
                          'Correct a stock figure from the product it belongs '
                          'to.'
                    : 'Nothing here changed stock, a shift, or a sale, and '
                          'nothing on this page can. Correct a stock figure '
                          'from the product it belongs to.',
              ),
              SizedBox(height: tokens.spacing.s8),
              const Text(
                key: ValueKey('reconciliation-anomalies-order'),
                'This list is not in time order: a record is addressed by what '
                'it is about, not by when it was found. Each one states its own '
                'instants.',
              ),
            ],
          ),
        ),
        if (amendOffered && !canAmend && _listsShiftVariance) ...[
          SizedBox(height: tokens.spacing.s12),
          // The same notice the day page has carried behind the same component
          // since step 4, at the same status and for the same reason: `info`
          // rather than `problem` because nothing has failed and nothing is
          // hidden - the sentence says so itself.
          const Callout(
            key: ValueKey('reconciliation-amend-forbidden'),
            status: AppStatus.info,
            message:
                'Correcting a shift\'s totals is available to owners and '
                'administrators. This list is readable by managers as well, so '
                'nothing here is hidden from you except that one correction.',
          ),
        ],
        SizedBox(height: tokens.spacing.s16),
        if (RecordSheet.drawnAt(MediaQuery.sizeOf(context).width))
          _sheet(context, tokens)
        else ...[
          _KindChips(selected: selected, onNarrow: onNarrow),
          SizedBox(height: tokens.spacing.s16),
          if (page.items.isEmpty)
            _empty
          else
            for (final anomaly in page.items) _anomaly(context, anomaly),
        ],
        SizedBox(height: tokens.spacing.s16),
        // A resolved difference is deleted from this list, so without this the
        // corrections made here would leave no visible trace. The trail is
        // readable by every role that reads this list, including the managers
        // who may not make one.
        AppButton(
          key: const ValueKey('reconciliation-anomalies-amendments'),
          label: 'View shift corrections already made',
          icon: Icons.history_edu_outlined,
          onPressed: () => onOpenAmendments(null),
        ),
      ],
    );
  }

  Widget get _empty => IllustratedMessage(
    illustration: 'reconciliation.svg',
    textKey: const ValueKey('reconciliation-anomalies-empty'),
    message: selected == null
        ? 'No unresolved differences.'
        : 'No differences of this kind.',
  );

  /// The large-screen list: one row per difference, its kind filter on its
  /// top edge.
  ///
  /// **The same page, narrowed the same way, drawn as rows** -
  /// `docs/design/tables/`, at the developer's direction on 2026-10-13. Every
  /// row is a difference, so there is no status column. A row states its kind,
  /// what it is about, and its headline figure; the rest of its figures, its
  /// sentence and its instants fold under it, and its three buttons are its
  /// menu under the same conditions. Below 1024 the cards are unchanged.
  Widget _sheet(BuildContext context, AppTokens tokens) => RecordSheet(
    key: const ValueKey('reconciliation-anomalies-sheet'),
    columns: const <SheetColumn>[
      SheetColumn(label: 'Difference', kind: SheetColumnKind.identity),
      SheetColumn(label: 'Figure', kind: SheetColumnKind.figure),
      SheetColumn(label: 'Run', kind: SheetColumnKind.code),
    ],
    bar: Row(
      children: <Widget>[
        // The kinds are sentences, so the select takes a search field's room.
        SizedBox(
          width: tokens.layout.tableSearch,
          child: _KindChips(selected: selected, onNarrow: onNarrow),
        ),
      ],
    ),
    body: page.items.isEmpty ? _empty : null,
    rows: <SheetRow>[for (final anomaly in page.items) _row(context, anomaly)],
  );

  SheetRow _row(BuildContext context, TenantReconciliationAnomaly anomaly) {
    final id = anomaly.id;
    final figures = reconciliationDifferenceFigureLines(anomaly);
    final headline = figures.isEmpty ? null : figures.first;
    final notes = <String>[
      if (reconciliationDifferenceExplanation(anomaly) case final prose?) prose,
      reconciliationDifferenceProvenance(anomaly),
    ];
    return SheetRow(
      id: id,
      key: ValueKey('reconciliation-anomaly-$id'),
      semanticLabel: reconciliationDifferenceKindLabel(anomaly),
      cells: <SheetCell?>[
        SheetText(
          reconciliationDifferenceKindLabel(anomaly),
          key: ValueKey('reconciliation-anomaly-kind-$id'),
          caption: reconciliationDifferenceSubject(anomaly),
          captionKey: ValueKey('reconciliation-anomaly-subject-$id'),
        ),
        if (headline != null)
          SheetFigure(
            headline.value,
            key: ValueKey('reconciliation-anomaly-figure-${headline.slug}-$id'),
            // What the figure is a measure of, as the card's line names it.
            caption: headline.detail == null
                ? headline.label
                : '${headline.label}, ${headline.detail}',
          )
        else
          // The kinds that report something could not be read: they have a
          // sentence, folded, and no measurement to stand here.
          SheetFigure.unknown(),
        SheetText(anomaly.jobId ?? '—'),
      ],
      actions: <RecordAction>[
        if (_canAmendRow(anomaly))
          RecordAction(
            label: busy ? 'Correcting...' : 'Correct this shift\'s totals',
            icon: Icons.rule_outlined,
            onPressed: busy ? null : () => _confirmAmend(context, anomaly),
            actionKey: ValueKey('reconciliation-anomaly-amend-$id'),
          ),
        if (anomaly.shiftId case final shiftId?)
          RecordAction(
            label: 'View this shift\'s corrections',
            onPressed: () => onOpenAmendments(shiftId),
            actionKey: ValueKey('reconciliation-anomaly-corrections-$id'),
          ),
        if (anomaly.jobId case final jobId?)
          RecordAction(
            label: 'About this run',
            onPressed: () => onOpenRun(jobId),
            actionKey: ValueKey('reconciliation-anomaly-run-$id'),
          ),
      ],
      actionsKey: ValueKey('reconciliation-anomaly-menu-$id'),
      actionsTooltip: 'More about this difference',
      fold: SheetFold(
        note: notes.join(' '),
        noteKey: ValueKey('reconciliation-anomaly-notes-$id'),
        lines: <SheetFoldLine>[
          for (final figure in figures.skip(1))
            SheetFoldLine(
              label: figure.detail == null
                  ? figure.label
                  : '${figure.label}, ${figure.detail}',
              value: figure.value,
              column: 1,
              valueKey: ValueKey(
                'reconciliation-anomaly-figure-${figure.slug}-$id',
              ),
            ),
        ],
        toggleKey: ValueKey('reconciliation-anomaly-fold-$id'),
        showLabel: 'Show more about this difference',
        hideLabel: 'Show less about this difference',
      ),
    );
  }

  /// True only for the one kind the server can resolve, and only when this
  /// session may ask it to. A shift ID is required because the correction names
  /// the shift; a record of that kind without one is refused by the read model
  /// long before it reaches here.
  bool _canAmendRow(TenantReconciliationAnomaly anomaly) =>
      canAmend &&
      anomaly.kind == TenantReconciliationAnomalyKind.shiftVariance &&
      anomaly.shiftId != null;

  /// One recorded difference: what it is about, what it says, and its figures.
  ///
  /// **`design.md` §11 step 8 on this screen is the figures leaving the
  /// sentence.** A stock difference read "Its ledger expects 10, and the product
  /// records 7: 3 fewer than the ledger accounts for", which is three numbers
  /// inside one clause - so on a page of differences nothing lined up, nothing
  /// could be compared down a column, and §2.2's rule about numbers stacking
  /// vertically had nowhere to apply. Each figure is a [StatLine] now, at
  /// `numeric.body` and right-aligned to a shared edge, and what is left of the
  /// prose is whatever the figures do not already say. Three of the eight kinds
  /// report that something could not be read rather than a measurement, and
  /// those still carry prose and no figures at all.
  Widget _anomaly(BuildContext context, TenantReconciliationAnomaly anomaly) {
    final tokens = AppTokens.componentOf(context);
    return Card(
      key: ValueKey('reconciliation-anomaly-${anomaly.id}'),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              key: ValueKey('reconciliation-anomaly-kind-${anomaly.id}'),
              reconciliationDifferenceKindLabel(anomaly),
              style: tokens.typography.titleMedium.copyWith(
                color: tokens.colors.text.primary,
              ),
            ),
            SizedBox(height: tokens.spacing.s4),
            Text(
              key: ValueKey('reconciliation-anomaly-subject-${anomaly.id}'),
              reconciliationDifferenceSubject(anomaly),
              style: tokens.typography.bodyMedium.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
            if (reconciliationDifferenceExplanation(anomaly)
                case final prose?) ...[
              SizedBox(height: tokens.spacing.s4),
              Text(
                key: ValueKey('reconciliation-anomaly-detail-${anomaly.id}'),
                prose,
                style: tokens.typography.bodyMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
            ],
            for (final figure in reconciliationDifferenceFigureLines(anomaly))
              StatLine(
                label: figure.label,
                value: figure.value,
                detail: figure.detail,
                valueKey: ValueKey(
                  'reconciliation-anomaly-figure-${figure.slug}-${anomaly.id}',
                ),
              ),
            SizedBox(height: tokens.spacing.s4),
            ProvenanceLine(
              reconciliationDifferenceProvenance(anomaly),
              key: ValueKey('reconciliation-anomaly-instants-${anomaly.id}'),
            ),
            if (_canAmendRow(anomaly) ||
                anomaly.shiftId != null ||
                anomaly.jobId != null) ...[
              SizedBox(height: tokens.spacing.s8),
              Wrap(
                spacing: tokens.spacing.s12,
                runSpacing: tokens.spacing.s8,
                children: [
                  if (_canAmendRow(anomaly))
                    AppButton(
                      key: ValueKey(
                        'reconciliation-anomaly-amend-${anomaly.id}',
                      ),
                      label: busy
                          ? 'Correcting...'
                          : 'Correct this shift\'s totals',
                      icon: Icons.rule_outlined,
                      onPressed: busy
                          ? null
                          : () => _confirmAmend(context, anomaly),
                    ),
                  // Offered for every row that names a shift, not only the one
                  // kind that can be corrected. A shift already corrected at a
                  // later generation can still be listed under an earlier one,
                  // so "has this already been dealt with" is a real question
                  // here - and the answer, including "never", comes from the
                  // trail rather than from this list.
                  if (anomaly.shiftId case final shiftId?)
                    AppButton(
                      key: ValueKey(
                        'reconciliation-anomaly-corrections-${anomaly.id}',
                      ),
                      label: 'View this shift\'s corrections',
                      onPressed: () => onOpenAmendments(shiftId),
                    ),
                  // The row already names the run above; this is the only way
                  // to ask anything about it. Whether that run finished, and
                  // what else it found, is what decides whether this difference
                  // is the whole of a problem or one symptom of it.
                  if (anomaly.jobId case final jobId?)
                    AppButton(
                      key: ValueKey('reconciliation-anomaly-run-${anomaly.id}'),
                      label: 'About this run',
                      onPressed: () => onOpenRun(jobId),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Requires a reason and an explicit confirmation.
  ///
  /// The confirmation is not ceremony. This rewrites a record every other part
  /// of the app treats as final, and the reason is stored in the business's
  /// immutable amendment trail beside the name of whoever asked for it.
  Future<void> _confirmAmend(
    BuildContext context,
    TenantReconciliationAnomaly anomaly,
  ) async {
    final reason = await showAppDialog<String>(
      context,
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
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppDialog(
      title: 'Correct this shift\'s totals?',
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
          SizedBox(height: tokens.spacing.s12),
          AppTextField(
            key: const ValueKey('reconciliation-amend-reason'),
            controller: _reason,
            autofocus: true,
            maxLength: 500,
            maxLines: 2,
            label: 'Why is this being corrected?',
            helper: 'Kept in the business\'s record of the correction.',
          ),
        ],
      ),
      actions: [
        AppButton(
          key: const ValueKey('reconciliation-amend-cancel'),
          label: 'Cancel',
          tier: AppButtonTier.tertiary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          key: const ValueKey('reconciliation-amend-confirm'),
          label: 'Correct it',
          tier: AppButtonTier.primary,
          onPressed: () => Navigator.of(context).pop(_reason.text),
        ),
      ],
    );
  }
}

/// One chip per kind this client models, plus every kind.
///
/// `other` is deliberately absent: it names every kind this build does not
/// model, so it identifies no stored value and cannot be asked for. Those
/// records still appear in the unnarrowed list.
final class _KindChips extends StatelessWidget {
  const _KindChips({required this.selected, required this.onNarrow});

  final TenantReconciliationAnomalyKind? selected;
  final ValueChanged<TenantReconciliationAnomalyKind?> onNarrow;

  /// **A dropdown, not a chip strip, and this is the one filter on a single-filter
  /// surface that takes one.** Decision 26b sends a surface with more than one
  /// filter to dropdowns and leaves a lone strip alone, on the grounds that a
  /// strip shows its options without a tap. Nine options is where that stops
  /// being true: these labels are sentences - `Stock checkpoint chain is broken`
  /// - so the strip wrapped onto three rows and took more of a tablet than the
  /// first difference below it. The rule is about a wall of pills rather than
  /// about the number of filters, and nine long options is a wall.
  @override
  Widget build(BuildContext context) =>
      AppSelect<TenantReconciliationAnomalyKind?>(
        key: const ValueKey('reconciliation-anomaly-kind'),
        label: 'Kind',
        dense: true,
        leading: Icons.filter_alt_outlined,
        value: selected,
        onChanged: onNarrow,
        items: <AppSelectItem<TenantReconciliationAnomalyKind?>>[
          const AppSelectItem<TenantReconciliationAnomalyKind?>(
            key: ValueKey('reconciliation-anomaly-kind-all'),
            value: null,
            label: 'Every kind',
          ),
          for (final kind in TenantReconciliationAnomalyKind.values)
            if (kind != TenantReconciliationAnomalyKind.other)
              AppSelectItem<TenantReconciliationAnomalyKind?>(
                key: ValueKey('reconciliation-anomaly-kind-${kind.wireValue}'),
                value: kind,
                label: kind.label,
              ),
        ],
      );
}
