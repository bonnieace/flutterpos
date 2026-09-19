import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/pagination.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/stats.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'reconciliation_actions.dart';
import 'reconciliation_anomalies_panel.dart';
import 'reconciliation_labels.dart';
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
  Widget build(BuildContext context) => AppScaffold(
    title: 'Reconciliation status',
    subtitle: businessDate,
    contentWidth: AppContentWidth.records,
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

  /// Reports one write outcome, over the screen rather than inside the page.
  ///
  /// See `showAppSnackBar`: since 2026-09-03 every outcome goes there, and
  /// inline text is left to the one thing it is still right for - a field
  /// saying what is wrong with what was typed into it.
  void _report(AppNotice notice) => showAppSnackBar(context, notice);

  TenantReconciliationMode _mode = TenantReconciliationMode.incremental;

  /// Retained only across an ambiguous attempt, so a retry addresses the same
  /// idempotency record instead of queueing a second run.
  String? _requestId;
  final TenantStaffNameResolvers _staffNames = TenantStaffNameResolvers();
  String? _loaderKey;
  TenantGuardedLoader<_ReconciliationView>? _loader;
  TenantGuardedLoader<_ReconciliationView>? _loaderCached;

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

  /// One resolver per session **and per pass**, so the cached pass resolves a
  /// name from this device rather than putting a network read in front of
  /// records it already holds. An unresolved name degrades to the UID.
  TenantStaffNameResolver _resolverFor(
    TenantSession session,
    TenantDocumentReader reader,
  ) => _staffNames.of(session: session, reader: reader);

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
      _report(
        AppNotice.confirmed(
          'Queued as ${result.jobId}. The server works through outstanding '
          'days oldest first, so this may regenerate another day before '
          'this one.',
        ),
      );
      _reload();
    } on TenantReconciliationRequestException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      // Only an unknown outcome may have queued anything, so only it keeps the
      // request ID. Every other refusal left nothing behind, and reusing its ID
      // would make a later attempt fail as a duplicate.
      if (!error.mayHaveQueued) _requestId = null;
      _report(_requestNotice(error.failure));
      if (error.mayHaveQueued) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      // The request may well have been queued; only its answer was unusable.
      _report(
        const AppNotice.unknown(
          'The server answer could not be trusted. A check may have been '
          'queued; read this page again before asking for another.',
        ),
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
    TenantGuardedLoader<_ReconciliationView> readWith(
      TenantDataReader reader,
    ) => (session) async {
      final day = await TenantReconciliationStatusRepository(
        session: session,
        reader: reader,
      ).loadDay(widget.businessDate, pageSize: widget.pageSize, cursor: cursor);
      // A scheduled sweep and a sale trigger name no member of the business.
      return _ReconciliationView(
        day: day,
        names: await _resolverFor(session, reader).resolve(<String>[
          for (final run in day.runs.items)
            if (run.actorUid case final actorUid?) actorUid,
        ]),
      );
    };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '${widget.businessDate}:$_generation:$_pageIndex:$cursor';
    _composeLoaders(guardKey);
    return TenantRouteGuard<_ReconciliationView>(
      allowedRoles: TenantReconciliationStatusRepository.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
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
///
/// **Five of the six are `refused` and one is not.** `ambiguous` is the only
/// branch where something may actually have been queued, and it is the only one
/// whose own sentence tells a person to go and look — so it carries `attention`
/// rather than `problem`, which is the distinction the sentences have always
/// drawn and the colour never did.
AppNotice _requestNotice(TenantReconciliationRequestFailure failure) =>
    switch (failure) {
      TenantReconciliationRequestFailure.forbidden => const AppNotice.refused(
        'Only an owner or administrator can ask for a check. Nothing was '
        'queued.',
      ),
      TenantReconciliationRequestFailure.requestedTooRecently =>
        const AppNotice.refused(
          'A check of this kind was asked for too recently, so nothing was '
          'queued. The server allows one catch-up every 5 minutes and one '
          'full check every 24 hours.',
        ),
      TenantReconciliationRequestFailure.duplicateRequest =>
        const AppNotice.refused(
          'An earlier attempt already used this request. Nothing was queued a '
          'second time; ask again to start a new one.',
        ),
      TenantReconciliationRequestFailure.invalidRequest =>
        const AppNotice.refused(
          'The server rejected this request as invalid, so nothing was queued.',
        ),
      TenantReconciliationRequestFailure.refused => const AppNotice.refused(
        'The request was refused and nothing was queued.',
      ),
      TenantReconciliationRequestFailure.ambiguous => const AppNotice.unknown(
        'The result is unknown. A check may have been queued; this page has '
        'been read again, so check the runs below before asking for '
        'another.',
      ),
    };

final class _ReconciliationContents extends StatelessWidget {
  const _ReconciliationContents({
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.busy,
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
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('reconciliation-status'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      children: [
        // §7's "Title appears once". This one named *which* day rather than
        // repeating the title, so the date moved to `PageHeader.subtitle` — the
        // slot step 5a built for exactly "which slice of something this is" and
        // left empty. The screen supplies it from the business date it is
        // already constructed with, so nothing new is read and no new copy is
        // written: the header reads `Reconciliation status` over `2026-08-15`
        // where the page used to say both at once, twice.
        const Disclosure(
          key: ValueKey('reconciliation-status-scope-disclosure'),
          summary: 'What this page can and cannot do',
          child: Text(
            'The server regenerates each day\'s totals from the sales it holds. '
            'This page explains where that work stands. Nothing here can retry, '
            'cancel, or re-order a run.',
          ),
        ),
        SizedBox(height: tokens.spacing.s16),
        Card(
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The badge and the sentence say the same thing at two lengths.
                // The sentence stays because it names *why*, which no five-word
                // status can; the badge is what makes the day's standing legible
                // down a page without reading it.
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(
                    key: const ValueKey('reconciliation-status-badge'),
                    status: _outcomeStatus(day.outcome),
                    label: _outcomeLabel(day.outcome),
                  ),
                ),
                SizedBox(height: tokens.spacing.s8),
                Text(
                  key: const ValueKey('reconciliation-status-verdict'),
                  _verdict(day),
                  style: tokens.typography.titleMedium.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
                if (day.intake case final intake?) ...[
                  SizedBox(height: tokens.spacing.s12),
                  // **§5.1's `StatTile`, and this card is what it is for**: the
                  // day is the subject of this route, and how many receipts the
                  // server registered for it is the evidence the verdict above
                  // rests on. It was `12 sale receipts registered for this day.`
                  // - a figure inside a sentence, needing its own singular, at
                  // body size, on the one screen that exists to state it.
                  //
                  // **The second tile appears only where there is something to
                  // report**, and its own sentence stays underneath rather than
                  // becoming the tile's detail line: the consequence - no stock
                  // moved, no profit counted - is two clauses, and a caption
                  // that ellipsises on a phone is worse than a caption and a
                  // sentence.
                  StatRow(
                    tiles: [
                      StatTile(
                        label: 'Sale receipts',
                        value: '${intake.saleReceiptCount}',
                        icon: Icons.receipt_long_outlined,
                        detail: 'registered for this day',
                        valueKey: const ValueKey(
                          'reconciliation-status-receipts',
                        ),
                      ),
                      if (intake.hasInvalidSaleLines)
                        StatTile(
                          label: 'Unusable lines',
                          value: '${intake.invalidLineCount}',
                          icon: Icons.report_gmailerrorred_outlined,
                          detail: 'of this day\'s sale lines',
                          valueKey: const ValueKey(
                            'reconciliation-status-invalid-lines',
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: tokens.spacing.s12),
                  // **The gap under this is not decoration.** The first picture
                  // of a day with unusable lines ran this sentence straight
                  // into the published-totals line below, and the two read as
                  // one paragraph about one thing - which they are not.
                  if (intake.hasInvalidSaleLines) ...[
                    Text(
                      key: const ValueKey(
                        'reconciliation-status-invalid-lines-note',
                      ),
                      'Those lines moved no stock and count towards no profit.',
                      style: tokens.typography.bodyMedium.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                    SizedBox(height: tokens.spacing.s8),
                  ],
                  // **Left as a sentence deliberately.** A revision is a
                  // generation marker rather than a measurement - `change 2`
                  // against `change 3` says which of two states of the day the
                  // totals were built from, and nothing about it is worth
                  // comparing by magnitude down a column. §2.2's numeric roles
                  // are for money and counts; promoting a sequence number into
                  // one would be applying the letter of step 8 against its own
                  // reason.
                  Text(
                    key: const ValueKey('reconciliation-status-published'),
                    _published(intake),
                    style: tokens.typography.bodyMedium.copyWith(
                      color: tokens.colors.text.primary,
                    ),
                  ),
                  if (intake.dirtyReason case final reason?)
                    Text(
                      key: const ValueKey('reconciliation-status-reason'),
                      'Marked for regeneration by: $reason',
                      style: tokens.typography.bodyMedium.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                  if (intake.lastErrorCode case final code?)
                    Text(
                      key: const ValueKey('reconciliation-status-error'),
                      'Server code: $code',
                      style: tokens.typography.bodyMedium.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                  SizedBox(height: tokens.spacing.s8),
                  ProvenanceLine(
                    _instants(intake),
                    key: const ValueKey('reconciliation-status-instants'),
                  ),
                ],
              ],
            ),
          ),
        ),
        // **What happened is a status, not a paragraph a person has to parse.**
        // This was a bare `Text` whose sentence was the only thing separating
        // "Queued as rj_000123" from "Only an owner can ask for a check" — the
        // §1 failure in the one place it decides whether somebody presses the
        if (requestOffered) ...[
          SizedBox(height: tokens.spacing.s24),
          if (canRequest)
            _RequestReconciliation(
              key: const ValueKey('reconciliation-request-form'),
              mode: mode,
              busy: busy,
              onChooseMode: onChooseMode,
              onRequest: onRequest,
            )
          else
            // A permanent notice paragraph, which is §5.1's own description of
            // what `Callout` replaces. `info` rather than `problem`: nothing has
            // failed and nothing is hidden - the sentence says so itself.
            const Callout(
              key: ValueKey('reconciliation-request-forbidden'),
              status: AppStatus.info,
              message:
                  'Only an owner or administrator can ask the server to '
                  'reconcile. This page is readable by managers as well, so '
                  'nothing here is hidden from you except that one request.',
            ),
        ],
        SizedBox(height: tokens.spacing.s24),
        SectionHeading('Reconciliation runs'),
        SizedBox(height: tokens.spacing.s4),
        const Disclosure(
          key: ValueKey('reconciliation-status-runs-disclosure'),
          summary: 'What a run does not prove',
          child: Text(
            'A run is one unit of server work. Each one takes the oldest '
            'business day still waiting in the whole business, so a completed '
            'run is not by itself proof that this day was regenerated - the '
            'state above is.',
          ),
        ),
        SizedBox(height: tokens.spacing.s12),
        if (day.runs.items.isEmpty)
          const Text(
            key: ValueKey('reconciliation-status-runs-empty'),
            'No reconciliation run has been queued for this day.',
          )
        else
          for (final run in day.runs.items) _run(context, run),
        SizedBox(height: tokens.spacing.s16),
        // A run states how many differences it found and could not resolve. This
        // is the only place that says which ones, so the count above is
        // actionable rather than merely alarming.
        AppButton(
          key: const ValueKey('reconciliation-status-anomalies'),
          label: 'View unresolved differences',
          icon: Icons.report_gmailerrorred_outlined,
          onPressed: onOpenAnomalies,
        ),
        SizedBox(height: tokens.spacing.s16),
        Pagination(
          pageNumber: pageIndex + 1,
          previousKey: const ValueKey('reconciliation-status-previous'),
          nextKey: const ValueKey('reconciliation-status-next'),
          onPrevious: pageIndex > 0 ? onPreviousPage : null,
          onNext: day.runs.hasMore ? onNextPage : null,
        ),
      ],
    );
  }

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
    final confirmed = await showConfirmDialog(
      context,
      title: 'Ask the server to reconcile?',
      consequence:
          'This queues one ${mode.label.toLowerCase()} for the whole '
          'business. ${mode.description}',
      stillTrue: 'It cannot be cancelled or re-ordered once queued.',
      confirmLabel: 'Ask for it',
      tier: AppButtonTier.primary,
      confirmKey: const ValueKey('reconciliation-request-confirm'),
      cancelKey: const ValueKey('reconciliation-request-cancel'),
    );
    if (confirmed) onRequest();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading('Ask the server to reconcile'),
        SizedBox(height: tokens.spacing.s4),
        // The single most important sentence on this surface. A request is
        // filed for the business under today's business date and the runners
        // take the oldest outstanding day first, so it is not a way to
        // reconcile the day being read - and a run queued from here will not
        // appear in the list below unless that day is today.
        //
        // **A `Callout` and deliberately not a `Disclosure`**, unlike the two
        // helper paragraphs above it. §5.1 splits the two by what the prose is
        // for: a permanent *helper* paragraph folds away, a permanent *notice*
        // does not. This is the one sentence that decides whether pressing the
        // button below does what the person thinks it does, and a sentence you
        // have to open is a sentence nobody reads. `info` because nothing has
        // failed - it is telling you what the action covers.
        const Callout(
          key: ValueKey('reconciliation-request-scope'),
          status: AppStatus.info,
          message:
              'A request covers the whole business, not the day above. The '
              'server files it under today and works through the outstanding '
              'days oldest first, so it may regenerate a different day before '
              'this one.',
        ),
        SizedBox(height: tokens.spacing.s12),
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
        SizedBox(height: tokens.spacing.s8),
        Text(
          key: const ValueKey('reconciliation-request-mode-detail'),
          mode.description,
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        SizedBox(height: tokens.spacing.s12),
        AppButton(
          key: const ValueKey('reconciliation-request-submit'),
          label: busy ? 'Asking...' : 'Ask for a check',
          tier: AppButtonTier.primary,
          onPressed: busy ? null : () => _confirm(context),
        ),
      ],
    );
  }
}

/// The day's standing, as one of `design.md` §2.1's five statuses.
///
/// **[TenantReconciliationDayOutcome.unrecognised] is `info` rather than
/// `problem`, and that is a decision rather than a default.** §2.1 gives
/// "unreadable" to `problem`, which reads as the obvious home for it - but the
/// comment on [_verdict] below has already decided the opposite question: a
/// server deploy that introduces a state this app does not model is not
/// evidence of anything wrong, and reporting it as a difference would be
/// inventing an answer in colour after refusing to invent one in words.
/// `info`'s own meaning is "informational", which is exactly what that row is.
AppStatus _outcomeStatus(TenantReconciliationDayOutcome outcome) =>
    switch (outcome) {
      TenantReconciliationDayOutcome.regenerated => AppStatus.ok,
      TenantReconciliationDayOutcome.awaitingRegeneration =>
        AppStatus.attention,
      TenantReconciliationDayOutcome.blocked => AppStatus.problem,
      TenantReconciliationDayOutcome.noSalesRecorded => AppStatus.neutral,
      TenantReconciliationDayOutcome.unrecognised => AppStatus.info,
    };

/// The badge's word. Sentence case per §8, and short enough that the badge
/// stays one line on a phone - the sentence beside it is where the detail is.
String _outcomeLabel(TenantReconciliationDayOutcome outcome) =>
    switch (outcome) {
      TenantReconciliationDayOutcome.regenerated => 'Reconciled',
      TenantReconciliationDayOutcome.awaitingRegeneration => 'Awaiting',
      TenantReconciliationDayOutcome.blocked => 'Stopped',
      TenantReconciliationDayOutcome.noSalesRecorded => 'No sales',
      TenantReconciliationDayOutcome.unrecognised => 'Unrecognised',
    };

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
        : 'Last sale received ${reconciliationInstant(received)}',
    regenerated == null
        ? 'Never regenerated'
        : 'Last regenerated ${reconciliationInstant(regenerated)}',
  ].join(' • ');
}
