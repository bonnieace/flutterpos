import 'package:flutter/material.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';

import '../sales/sale_history.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/record_list.dart';
import '../ui/scaffold.dart';
import '../ui/sheet.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'return_actions.dart';
import 'return_history.dart';
import 'return_request.dart';
import 'return_verification.dart';

/// What the return process is scoped to.
final class TenantSaleReturnsRequest {
  const TenantSaleReturnsRequest({required this.sale});

  /// The already-validated sale being reversed. It is carried from the sale
  /// page rather than re-read, so the returnable quantities are derived from
  /// the exact immutable document that was proved there.
  final TenantSale sale;

  String get saleId => sale.id;
  String get receiptNumber => sale.receiptNumber;
  String get key => 'sale:$saleId';
}

/// Records a return against one selected sale, as a sheet over the sale it is
/// against.
///
/// **A sheet rather than a route since 2026-08-26**, on the same reading as the
/// stock correction: this is one short errand against a record a person is
/// already looking at, and pushing a screen for it took the sale off the
/// display at the moment they needed to check what was on it.
///
/// **A confirmed return closes the sheet and is announced over the sale
/// list**; see [TenantSaleReturnsPanel.onCompleted] for why a refusal is not.
///
/// Answers with the notice a settled return produced, and null where the sheet
/// was abandoned or its outcome left the person still working on it. A caller
/// that lists the sale reads this as *the day changed, read it again*; a caller
/// that does not can ignore it exactly as they all did before.
Future<AppNotice?> openTenantSaleReturnSheet(
  BuildContext context, {
  required TenantDataReader reader,
  required TenantSaleReturnsRequest request,
  TenantReturnActions? actions,
  String Function()? requestIdFactory,
}) async {
  // Captured before the sheet exists: a sheet is a route of its own and
  // inherits no scope from the page it covers.
  final sessions = TenantSessionScope.read(context);
  final answer = await showAppSheet<AppNotice>(
    context,
    // **Opens at `half` and is dragged to `full`, on the product owner's call
    // of 2026-09-06.** It opened at `full` because a sale of more than two or
    // three lines puts the submit control under the fold at `half` - which is
    // true, and is what the drag is for. What `full` cost was the thing a sheet
    // exists to keep: the sale underneath it. A person recording a return is
    // checking the return against the receipt on screen, and a sheet that
    // covers the whole page is a route that replaced it.
    initialDetent: AppSheetDetent.half,
    builder: (sheetContext, controller) => TenantSessionScope(
      controller: sessions,
      child: TenantSaleReturnsPanel(
        reader: reader,
        request: request,
        actions: actions,
        requestIdFactory: requestIdFactory,
        showHistory: false,
        scrollController: controller,
        onCompleted: (notice) => Navigator.of(sheetContext).pop(notice),
        onCancel: () => Navigator.of(sheetContext).pop(),
      ),
    ),
  );
  if (answer != null && context.mounted) showAppSnackBar(context, answer);
  return answer;
}

/// One guarded view of a sale's returns and what may still be returned.
final class _ReturnsView {
  const _ReturnsView({
    required this.page,
    required this.names,
    required this.returnable,
  });

  final TenantReturnPage page;
  final Map<String, String> names;

  /// Present only when this page is the complete set of returns for the sale.
  final TenantReturnableSale? returnable;
}

/// Pages the returns recorded against one sale behind [TenantRouteGuard], and
/// records a new pending one.
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding page or write discards it before it can update the UI.
/// Nothing here verifies a return or restores any stock.
final class TenantSaleReturnsPanel extends StatefulWidget {
  const TenantSaleReturnsPanel({
    super.key,
    required this.reader,
    required this.request,
    this.actions,
    this.pageSize = 20,
    this.requestIdFactory,
    this.showHistory = true,
    this.scrollController,
    this.onCompleted,
    this.onCancel,
  });

  final TenantDataReader reader;
  final TenantSaleReturnsRequest request;
  final TenantReturnActions? actions;
  final int pageSize;

  /// One fresh request ID per confirmation or verification intent.
  final String Function()? requestIdFactory;

  /// The sale route is a focused return process. The complete business record
  /// lives on the home's Returns screen.
  final bool showHistory;

  /// The sheet's own controller, which must reach the scrollable this builds or
  /// dragging the form scrolls the form and the sheet never moves. Null when
  /// this panel is pumped outside a sheet, which is how its tests reach it.
  final ScrollController? scrollController;

  /// Called with the confirmation once, and only once, a return commits.
  ///
  /// **Only a commit reports out, and a refusal deliberately does not.** The
  /// sheet closes on this callback, so handing it a refusal would throw away a
  /// set of chosen quantities and a typed reason at the exact moment a person
  /// needs them to fix what was wrong. A refusal stays here as a [Callout] over
  /// the form that produced it, and so does an ambiguous outcome — that one has
  /// a page re-read behind it whose records are the answer.
  ///
  /// Null renders every outcome in place, which is what the full returns
  /// surface and a test pumping this panel bare both see.
  final void Function(AppNotice notice)? onCompleted;

  /// Abandons the return. Null draws no cancel control.
  final VoidCallback? onCancel;

  @override
  State<TenantSaleReturnsPanel> createState() => _TenantSaleReturnsPanelState();
}

final class _TenantSaleReturnsPanelState extends State<TenantSaleReturnsPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;

  /// Retained only across an ambiguous attempt, so a retry addresses the same
  /// deterministic document instead of recording the reversal twice.
  String? _requestId;
  final TenantStaffNameResolvers _staffNames = TenantStaffNameResolvers();

  /// One resolver per session **and per pass**, so the cached pass resolves a
  /// name from this device rather than putting a network read in front of
  /// records it already holds. An unresolved name degrades to the UID.
  TenantStaffNameResolver _resolverFor(
    TenantSession session,
    TenantDocumentReader reader,
  ) => _staffNames.of(session: session, reader: reader);

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

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

  Future<void> _record(
    TenantSession session,
    TenantReturnableSale returnable,
    Map<String, int> quantities,
    String reason,
  ) async {
    final writer = widget.actions?.writer;
    if (writer == null || _busy) return;
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'returns.record',
      screen: 'returns',
      context: {
        'user_id': session.uid,
        'tenant_id': session.tenantId,
        'sale_id': widget.request.saleId,
      },
    );
    final capturedKey = _sessionKey(session);
    setState(() {
      _busy = true;
    });
    try {
      final intent =
          TenantReturnRequestRepository(
            session: session,
            reader: widget.reader,
          ).buildCreateIntent(
            returnable: returnable,
            quantities: quantities,
            reason: reason,
            requestId: _requestId ??=
                (widget.requestIdFactory ?? secureTenantReturnRequestId)(),
          );
      final result = await telemetry.trace(
        operation,
        'save_return',
        () => writer.recordReturn(intent),
      );
      if (result.kind == TenantReturnWriteKind.queued) {
        telemetry.recordStep(operation, 'saved_locally');
      } else if (result.kind == TenantReturnWriteKind.committed) {
        telemetry.recordStep(operation, 'confirmed_on_server');
      } else {
        AppTelemetry.captureHandled(
          StateError(result.kind.name),
          StackTrace.current,
          operation: operation,
          code: result.kind.name,
          data: {'quantities': quantities},
        );
      }
      if (!_stillCurrent(capturedKey)) return;
      // Only an ambiguous outcome may have landed, so only it keeps the
      // request ID. A rejected or unattempted write left nothing behind, and
      // reusing its ID would deny an edited retry as a duplicate.
      if (result.kind != TenantReturnWriteKind.ambiguous) _requestId = null;
      final settled = _settles(result.kind);
      _answer(_resultNotice(result), settled: settled);
      // **The re-read is skipped when the sheet is closing.** `_answer` pops
      // the route on a settled outcome, and a `_reload` after it would start a
      // guarded read against a deactivated element.
      if (settled && widget.onCompleted == null) _reload();
    } on TenantReturnException catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'returns.record',
        data: {'quantities': quantities},
      );
      if (!_stillCurrent(capturedKey)) return;
      _requestId = null;
      _answer(_refusalNotice(error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Whether [kind] has taken this return off the form for good.
  ///
  /// **A queued return settles exactly as a committed one does, and that it did
  /// not is the defect reported on 2026-09-06: the sheet never closed.** The
  /// writer this app composes is `QueuedTenantReturnWriter` — every return a
  /// device records goes to the durable mutation store and is replayed from
  /// there — so [TenantReturnWriteKind.committed] is a result only the direct
  /// Firestore writer ever produces, and in the product the settling branch was
  /// unreachable. What the person came to do is finished either way: the units
  /// and the reason are recorded, the overlay reader already draws the pending
  /// return, and there is nothing left on the form to correct. Holding the sheet
  /// open over it only invites the same return to be recorded twice.
  ///
  /// The three that do not settle each leave something to do here — a refusal
  /// keeps the quantities and the reason so they can be fixed, an ambiguous
  /// write has a re-read behind it, and an unattempted one has recorded nothing
  /// at all.
  static bool _settles(TenantReturnWriteKind kind) => switch (kind) {
    TenantReturnWriteKind.committed || TenantReturnWriteKind.queued => true,
    TenantReturnWriteKind.rejected ||
    TenantReturnWriteKind.ambiguous ||
    TenantReturnWriteKind.unavailable => false,
  };

  /// Reports [notice] the way this panel was wired to, and nothing more.
  ///
  /// A settled outcome hands the sentence to
  /// [TenantSaleReturnsPanel.onCompleted] where there is one; every other
  /// outcome, and every outcome at all where there is not, is rendered in place.
  ///
  /// **[settled] rather than `notice.status`**, because the two are not the same
  /// question. A queued return is `info` — nothing has reached the server, and
  /// saying otherwise would be a false claim on a screen about money — while
  /// still being the end of this form's work. Reading the sentence's colour to
  /// decide whether the sheet closes tied one to the other, and the honest
  /// sentence was what kept the sheet open.
  void _answer(AppNotice notice, {bool settled = false}) {
    final completed = widget.onCompleted;
    if (settled && completed != null) {
      completed(notice);
      return;
    }
    showAppSnackBar(context, notice);
  }

  /// Whether the session this work was authorized against is still selected.
  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  /// One loader per guard key.
  ///
  /// [TenantRouteGuard] restarts whenever its loader changes identity, which is
  /// how a new loader is stopped from serving an old page. A closure rebuilt on
  /// every frame would therefore reload on every `setState` - discarding the
  /// half-filled record form each time the busy flag or a notice changed - so
  /// the loader is cached against the same key the guard is keyed by.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final request = widget.request;
    final cursor = _cursors[_pageIndex];
    final pageIndex = _pageIndex;
    TenantGuardedLoader<_ReturnsView> readWith(
      TenantDataReader reader,
    ) => (session) async {
      final page =
          await TenantReturnHistoryRepository(
            session: session,
            reader: reader,
          ).loadSaleReturns(
            saleId: request.saleId,
            pageSize: widget.pageSize,
            cursor: cursor,
          );
      return _ReturnsView(
        page: page,
        names: await _resolverFor(session, reader).resolve(
          page.items.expand(
            (record) => <String>[
              record.createdBy,
              if (record.verification case final verification?)
                verification.verifiedBy,
            ],
          ),
        ),
        // The remaining returnable quantity can only be derived from the
        // complete set of returns, which is exactly a first page with nothing
        // behind it.
        returnable: pageIndex == 0 && !page.hasMore
            ? TenantReturnRequestRepository(
                session: session,
                reader: reader,
              ).describeReturnable(sale: request.sale, recorded: page)
            : null,
      );
    };
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  String? _loaderKey;
  TenantGuardedLoader<_ReturnsView>? _loader;
  TenantGuardedLoader<_ReturnsView>? _loaderCached;

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final request = widget.request;
    final guardKey = '${request.key}:$_generation:$_pageIndex:$cursor';
    _composeLoaders(guardKey);
    return TenantRouteGuard<_ReturnsView>(
      load: _loader!,
      loadCached: _loaderCached,
      // What may still be returned is worked out from the returns read, so an
      // empty copy would also offer back what was already returned.
      holdsNothing: (view) => view.page.items.isEmpty,
      denied: const Center(
        key: ValueKey('sale-returns-denied'),
        child: Text('Returns are unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('sale-returns-failure'),
        child: Text('Returns could not be loaded.'),
      ),
      builder: (context, session, view) => _SaleReturnsContents(
        request: request,
        view: view,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        busy: _busy,
        canRecord:
            widget.actions?.writer != null &&
            session.canAccess(
              allowedRoles: TenantReturnRequestRepository.allowedRoles,
            ),
        canVerify:
            widget.actions?.verifyCallable != null &&
            TenantReturnVerificationGateway.canVerifyInSession(session),
        onNextPage: () => _nextPage(view.page.nextCursor),
        onPreviousPage: _previousPage,
        onRecord: (quantities, reason) =>
            _record(session, view.returnable!, quantities, reason),
        onVerify: (record) => _verify(session, record),
        showHistory: widget.showHistory,
        scrollController: widget.scrollController,
        onCancel: widget.onCancel,
      ),
    );
  }

  /// Verifies one pending return and restores its stock.
  ///
  /// The gateway is bound to this exact session and this exact decoded record,
  /// so nothing on this screen can name another business or another return.
  /// After any outcome the page is re-read, so what is shown is the server's own
  /// verification evidence rather than an optimistic local state.
  Future<void> _verify(TenantSession session, TenantReturn record) async {
    final callable = widget.actions?.verifyCallable;
    if (callable == null || _busy) return;
    final capturedKey = _sessionKey(session);
    setState(() {
      _busy = true;
    });
    try {
      final gateway = TenantReturnVerificationGateway(
        session: session,
        target: record,
        callable: callable,
        requestIdFactory: widget.requestIdFactory == null
            ? null
            : () => 'verify-${widget.requestIdFactory!()}',
      );
      final result = await gateway.submit(gateway.createIntent());
      if (!_stillCurrent(capturedKey)) return;
      _answer(
        AppNotice.confirmed(
          'Restored ${result.restoredUnits} '
          '${result.restoredUnits == 1 ? 'unit' : 'units'} across '
          '${result.restoredProducts.length} '
          '${result.restoredProducts.length == 1 ? 'product' : 'products'}.',
        ),
        settled: true,
      );
      _reload();
    } on TenantReturnVerificationException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      _answer(_verificationNotice(error.failure));
      // Only an unknown outcome may have restored stock, and only the server
      // can say. Re-reading is the one safe response; retrying is not.
      if (error.mayHaveCommitted) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      // The call may well have restored stock; only its answer was unusable.
      _answer(
        const AppNotice.unknown(
          'The verification response could not be trusted. Reload this page '
          'to see what the server recorded.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// **`alreadyVerified` is the one branch that is not a refusal**, and it is the
/// clearest case in the app for this model. "This return had already been
/// verified, so nothing was restored again" is not a failure — the stock the
/// operator wanted restored *is* restored — and painting it the same red as
/// "Only an owner may restore stock" would tell a manager something went wrong
/// when nothing did.
AppNotice _verificationNotice(TenantReturnVerificationFailure failure) =>
    switch (failure) {
      TenantReturnVerificationFailure.forbidden => const AppNotice.refused(
        'Only an owner, administrator, or manager may restore stock.',
      ),
      TenantReturnVerificationFailure.notFound => const AppNotice.refused(
        'This return no longer exists in this business.',
      ),
      TenantReturnVerificationFailure.alreadyVerified =>
        const AppNotice.offline(
          'This return had already been verified, so nothing was restored '
          'again.',
        ),
      TenantReturnVerificationFailure.exceedsSale => const AppNotice.refused(
        'This return covers more than the original sale still allows. It '
        'cannot be verified; record a corrected return instead.',
      ),
      TenantReturnVerificationFailure.missingProduct => const AppNotice.refused(
        'A returned product no longer exists, so its stock cannot be restored.',
      ),
      TenantReturnVerificationFailure.missingSale => const AppNotice.refused(
        'The original sale is missing, so nothing bounds this restoration.',
      ),
      TenantReturnVerificationFailure.tooManyVerifications =>
        const AppNotice.refused(
          'This sale has too many prior verifications for automatic '
          'restoration. It needs manual stock adjustment.',
        ),
      TenantReturnVerificationFailure.refused => const AppNotice.refused(
        'The return was refused and no stock was restored.',
      ),
      TenantReturnVerificationFailure.ambiguous => const AppNotice.unknown(
        'The result is unknown. This page has been reloaded; check whether the '
        'return is now verified before trying again.',
      ),
      TenantReturnVerificationFailure.unavailable => const AppNotice.offline(
        'The server could not be reached, so no stock was restored.',
      ),
    };

/// A recorded return is `ok` and **that is a claim worth being careful about**:
/// nothing has been restored yet. The sentence says so, and the status means
/// only that the record this screen was asked to write exists.
AppNotice _resultNotice(TenantReturnWriteResult result) =>
    switch (result.kind) {
      // **Queued is every return, online or not**: the writer stores it here
      // and the worker carries it on, so *waiting to sync* announced an outage
      // on a connected phone. The sync badge says when one is genuinely stuck.
      TenantReturnWriteKind.queued ||
      TenantReturnWriteKind.committed => const AppNotice.confirmed(
        'Return recorded. No stock has been restored yet; a manager must '
        'verify it first.',
      ),
      TenantReturnWriteKind.rejected => const AppNotice.refused(
        'The return was refused and nothing was recorded. Check the '
        'quantities and try again.',
      ),
      TenantReturnWriteKind.ambiguous => const AppNotice.unknown(
        'The result is unknown. Reload this page to see whether the return '
        'was recorded, and do not record it again.',
      ),
      TenantReturnWriteKind.unavailable => const AppNotice.offline(
        'This device is offline, so nothing was recorded. A return must be '
        'recorded while online.',
      ),
    };

/// Every one of these is the client refusing before anything was sent.
AppNotice _refusalNotice(String code) => AppNotice.refused(switch (code) {
  'return_exceeds_sale' =>
    'That is more than this sale still has available to return.',
  'invalid_return_reason' =>
    'Record a reason of at least 3 characters for this return.',
  'invalid_return_quantities' => 'Choose at least one unit to return.',
  'return_forbidden' => 'This role may not record a return.',
  _ => 'The return could not be recorded.',
});

final class _SaleReturnsContents extends StatelessWidget {
  const _SaleReturnsContents({
    required this.request,
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.busy,
    required this.canRecord,
    required this.canVerify,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onRecord,
    required this.onVerify,
    required this.showHistory,
    required this.scrollController,
    required this.onCancel,
  });

  final TenantSaleReturnsRequest request;
  final _ReturnsView view;
  final String selfUid;
  final int pageIndex;
  final bool busy;
  final bool canRecord;

  /// Whether this session may restore stock. The action is offered on a pending
  /// return only; a verified one is terminal.
  final bool canVerify;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final void Function(Map<String, int> quantities, String reason) onRecord;
  final ValueChanged<TenantReturn> onVerify;
  final bool showHistory;

  /// The sheet's drag controller. See
  /// [TenantSaleReturnsPanel.scrollController].
  final ScrollController? scrollController;

  final VoidCallback? onCancel;

  TenantReturnPage get page => view.page;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('sale-returns'),
      controller: scrollController,
      padding: showHistory
          ? EdgeInsets.all(tokens.spacing.s20)
          // The sheet's handle already sits above this and pads it, so there is
          // no top inset; the bottom is the sheet's, so the submit control
          // clears its edge.
          : EdgeInsets.fromLTRB(
              tokens.spacing.s20,
              0,
              tokens.spacing.s20,
              tokens.spacing.s24,
            ),
      children: [
        // §7's "Title appears once". This named *which* sale rather than
        // repeating the title, so the receipt number moved to
        // `PageHeader.subtitle`; the header reads `Returns` over the receipt
        // where the page used to say `Returns` and then `Returns against …`.
        if (showHistory) ...<Widget>[
          SizedBox(height: tokens.spacing.s4),
          const Text(
            'Stock is restored only when a return is verified. A pending '
            'return has changed no stock yet.',
          ),
        ] else ...<Widget>[
          // The sheet carries what `AppScaffold` used to, for the same reason
          // the stock sheet does: it is a route of its own with no app bar.
          PageHeader(
            key: const ValueKey('sale-returns-header'),
            title: 'Return',
            subtitle: request.receiptNumber,
          ),
        ],
        // **Phase 06's second criterion, which this page left to inference.**
        // Requesting a return is open to every active role and verifying it is
        // management's, and for a cashier the difference was that the action
        // simply was not drawn - correct guarding, and silent. Nothing told them
        // whether a pending return was waiting on somebody or stuck.
        //
        // The same shape the catalog's `Only an owner or administrator may
        // retire a product` and the staff directory's read-only standing both
        // use, and `info` for the same reason: nothing has failed, the whole
        // list is readable, and one action belongs to somebody else. The
        // refusal copy that already existed says this too, but only after an
        // attempt that a cashier can never make.
        // **A footnote rather than an `info` container, 2026-09-04.** It is
        // policy: nothing has failed, the whole list is readable, and the one
        // action it explains is simply not drawn. Three sentences in a tinted
        // box above the returns made the page look as though something were
        // wrong with it. It moves to the foot, in one line, under the list it
        // is about.
        if (showHistory) ...[
          SizedBox(height: tokens.spacing.s16),
          if (page.items.isNotEmpty) ...[
            Text(
              key: const ValueKey('sale-returns-counts'),
              _countsLabel(page),
            ),
            SizedBox(height: tokens.spacing.s12),
          ],
          // §4.3's responsive contract.
          RecordList(
            identityLabel: 'Return',
            items: <RecordItem>[
              for (final record in page.items) _entry(context, record),
            ],
            empty: const Text(
              key: ValueKey('sale-returns-empty'),
              'No returns were recorded against this sale.',
            ),
          ),
          ...Pagination(
            pageNumber: pageIndex + 1,
            previousKey: const ValueKey('sale-returns-previous'),
            nextKey: const ValueKey('sale-returns-next'),
            onPrevious: pageIndex > 0 ? onPreviousPage : null,
            onNext: page.hasMore ? onNextPage : null,
            endOfList: !page.hasMore,
          ).withGapAbove(tokens.spacing.s16),
          if (!canVerify) ...[
            SizedBox(height: tokens.spacing.s12),
            Text(
              key: const ValueKey('sale-returns-verification-unavailable'),
              'A return you record waits for an owner, administrator or '
              'manager to verify it.',
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.tertiary,
              ),
            ),
          ],
        ],
        if (canRecord) ...[
          SizedBox(
            height: showHistory ? tokens.spacing.s24 : tokens.spacing.s16,
          ),
          if (showHistory) ...[
            const Divider(),
            SizedBox(height: tokens.spacing.s12),
          ],
          if (view.returnable case final returnable?)
            if (returnable.hasReturnableLines)
              _RecordReturnForm(
                key: const ValueKey('sale-returns-form'),
                returnable: returnable,
                busy: busy,
                onRecord: onRecord,
                onCancel: onCancel,
              )
            else
              const Text(
                key: ValueKey('sale-returns-nothing-left'),
                'Every unit on this sale has already been returned.',
              )
          else
            const Text(
              key: ValueKey('sale-returns-form-unavailable'),
              'More returns exist than this page shows. Go back to the first '
              'page to record another return against this sale.',
            ),
        ] else if (!showHistory) ...[
          SizedBox(height: tokens.spacing.s16),
          const Callout(
            key: ValueKey('sale-return-recording-unavailable'),
            status: AppStatus.info,
            message: 'Return recording is unavailable for this session.',
          ),
        ],
      ],
    );
  }

  /// One return as §5.2's rows.
  ///
  /// **The standing was already the first thing on this record and is now a
  /// badge rather than a heading.** A return is pending or it is verified, which
  /// is §2.1's "pending, awaiting" and its "confirmed" exactly, and it decides
  /// what a person can do to the record - which is what makes it the standing
  /// rather than an attribute. It used to be a glyph beside a `titleMedium`
  /// sentence, so the record had a status where its identity goes and no
  /// identity at all.
  ///
  /// **"Stock restored" leaves the badge and stays on the record.** A badge is
  /// one word about a standing; what the verification did, when, and by whom is
  /// the `Verified` attribute beside it, and the page says above the list that
  /// stock moves only on verification. §9 is unaffected either way: both states
  /// carry an icon and a word, and neither is carried by colour.
  RecordItem _entry(BuildContext context, TenantReturn record) => RecordItem(
    id: record.id,
    recordKey: ValueKey('sale-returns-entry-${record.id}'),
    // The units and the products they came from are what one return *is* on a
    // page that is already about one sale. The itemisation is a fact about it
    // and takes a column of its own.
    title:
        '${record.returnedUnits} '
        '${record.returnedUnits == 1 ? 'unit' : 'units'} across '
        '${record.lines.length} '
        '${record.lines.length == 1 ? 'product' : 'products'}',
    titleKey: ValueKey('sale-returns-subject-${record.id}'),
    status: RecordStatus(
      badgeKey: ValueKey('sale-returns-status-${record.id}'),
      status: record.isVerified ? AppStatus.ok : AppStatus.attention,
      label: record.isVerified ? 'Verified' : 'Pending verification',
      icon: record.isVerified ? Icons.verified_outlined : Icons.hourglass_empty,
      semanticLabel: record.isVerified
          ? 'Verified; stock restored'
          : 'Pending verification; no stock restored yet',
    ),
    attributes: <RecordAttribute>[
      RecordAttribute(
        kind: RecordValueKind.money,
        label: 'Returned',
        value: record.lines.map(_lineLabel).join(', '),
        valueKey: ValueKey('sale-returns-lines-${record.id}'),
        flex: 2,
      ),
      RecordAttribute(
        label: 'Reason',
        value: record.reason,
        valueKey: ValueKey('sale-returns-reason-${record.id}'),
        flex: 2,
      ),
      // An attribute rather than a second provenance line, because a record has
      // one provenance and this is a second event against the same record:
      // recording it and verifying it are two acts by two people at two times.
      if (record.verification case final verification?)
        RecordAttribute(
          label: 'Verified',
          value:
              '${_instant(verification.verifiedAt)} by '
              '${_label(verification.verifiedBy)}',
          valueKey: ValueKey('sale-returns-verified-${record.id}'),
          flex: 2,
        ),
    ],
    provenance: _recordedLabel(record, _label(record.createdBy)),
    provenanceKey: ValueKey('sale-returns-recorded-${record.id}'),
    actions: <RecordAction>[
      if (!record.isVerified && canVerify)
        RecordAction(
          label: 'Verify and restore stock',
          actionKey: ValueKey('sale-returns-verify-${record.id}'),
          onPressed: busy ? null : () => _confirmVerification(context, record),
        ),
    ],
  );

  /// Names the exact products and units whose stock will move before anything
  /// is restored. Restoration is not reversible through this app.
  Future<void> _confirmVerification(
    BuildContext context,
    TenantReturn record,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore this stock?',
      consequence:
          'This verifies the return and adds '
          '${record.lines.map(_lineLabel).join(', ')} back to stock.',
      stillTrue: 'It cannot be undone from this app.',
      confirmLabel: 'Verify and restore',
      tier: AppButtonTier.primary,
      confirmKey: const ValueKey('sale-returns-confirm-verify'),
      cancelKey: const ValueKey('sale-returns-cancel-verify'),
    );
    if (confirmed) onVerify(record);
  }

  String _label(String uid) =>
      tenantStaffLabel(uid, names: view.names, selfUid: selfUid);
}

/// Selects the units to return and requires an explicit confirmation.
final class _RecordReturnForm extends StatefulWidget {
  const _RecordReturnForm({
    super.key,
    required this.returnable,
    required this.busy,
    required this.onRecord,
    this.onCancel,
  });

  final TenantReturnableSale returnable;
  final bool busy;

  /// Abandons the return without recording anything.
  ///
  /// **The sheet is dismissible and still draws this**, which is not a
  /// duplicate control: dragging a sheet down is a gesture, and §9's target
  /// rules are about things a person can aim at. `secondary`, so §2.1's
  /// one-primary-per-region still names `Record return`.
  final VoidCallback? onCancel;
  final void Function(Map<String, int> quantities, String reason) onRecord;

  @override
  State<_RecordReturnForm> createState() => _RecordReturnFormState();
}

final class _RecordReturnFormState extends State<_RecordReturnForm> {
  /// The select's value for the free-text option.
  ///
  /// **Not a reason, and never written.** A bare `Other` would be
  /// indistinguishable from somebody typing the word, so the sentinel is a
  /// value no typed reason can be.
  static const String _otherReason = '__other__';

  /// The select's value for "nothing chosen yet".
  static const String _noReason = '';

  final Map<String, int> _quantities = <String, int>{};
  final TextEditingController _reason = TextEditingController();
  String _choice = _noReason;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// The reason this form would record, chosen or typed.
  String get _resolvedReason =>
      _choice == _otherReason ? _reason.text : _choice;

  int _quantityOf(String productId) => _quantities[productId] ?? 0;

  void _change(TenantReturnableLine line, int delta) {
    final next = _quantityOf(line.productId) + delta;
    if (next < 0 || next > line.remainingQuantity) return;
    setState(() => _quantities[line.productId] = next);
  }

  int get _selectedUnits =>
      _quantities.values.fold(0, (total, value) => total + value);

  bool get _canSubmit =>
      !widget.busy &&
      _selectedUnits > 0 &&
      _resolvedReason.trim().length >= minimumReturnReasonLength;

  Future<void> _confirm() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Record this return?',
      consequence:
          'This records $_selectedUnits '
          '${_selectedUnits == 1 ? 'unit' : 'units'} as a pending return.',
      stillTrue: 'It restores no stock: a manager must verify it first.',
      confirmLabel: 'Record return',
      tier: AppButtonTier.primary,
      confirmKey: const ValueKey('sale-returns-confirm'),
      cancelKey: const ValueKey('sale-returns-cancel-confirm'),
    );
    if (!confirmed || !mounted) return;
    widget.onRecord(
      Map<String, int>.unmodifiable(_quantities),
      _resolvedReason,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in widget.returnable.lines)
          Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.spacing.s4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    key: ValueKey('sale-returns-remaining-${line.productId}'),
                    '${tenantProductLabel(line.name, line.size)}: '
                    '${line.remainingQuantity} of '
                    '${line.soldQuantity} available',
                  ),
                ),
                IconButton(
                  key: ValueKey('sale-returns-decrease-${line.productId}'),
                  onPressed: line.remainingQuantity == 0
                      ? null
                      : () => _change(line, -1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  key: ValueKey('sale-returns-quantity-${line.productId}'),
                  '${_quantityOf(line.productId)}',
                ),
                IconButton(
                  key: ValueKey('sale-returns-increase-${line.productId}'),
                  onPressed: line.remainingQuantity == 0
                      ? null
                      : () => _change(line, 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
        SizedBox(height: tokens.spacing.s12),
        // **A short list, and a way past it.** See
        // [commonTenantReturnReasons]: the list is what makes returns
        // countable, and *Other* is what stops the list making somebody pick
        // the nearest wrong entry.
        AppSelect<String>(
          key: const ValueKey('sale-returns-reason-choice'),
          value: _choice,
          label: 'Reason for this return',
          leading: Icons.assignment_return_outlined,
          items: <AppSelectItem<String>>[
            const AppSelectItem<String>(
              key: ValueKey('sale-returns-reason-none'),
              value: _noReason,
              label: 'Choose a reason',
            ),
            for (final reason in commonTenantReturnReasons)
              AppSelectItem<String>(
                key: ValueKey('sale-returns-reason-option-$reason'),
                value: reason,
                label: reason,
              ),
            const AppSelectItem<String>(
              key: ValueKey('sale-returns-reason-option-other'),
              value: _otherReason,
              label: 'Other',
            ),
          ],
          onChanged: (value) => setState(() => _choice = value ?? _noReason),
        ),
        // **Present only for *Other*, and it keeps what was typed.** The
        // controller is not cleared when the choice moves off *Other*, so a
        // person who opens the list to check the wording and comes back finds
        // their sentence still there.
        if (_choice == _otherReason) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          AppTextField(
            key: const ValueKey('sale-returns-reason'),
            controller: _reason,
            maxLength: maximumReturnReasonLength,
            onChanged: (_) => setState(() {}),
            label: 'Say what happened',
          ),
        ],
        SizedBox(height: tokens.spacing.s16),
        // Right-aligned with the primary last, for the reason the stock sheet's
        // pair gives: the control a right-handed thumb reaches is the one it
        // should press.
        AppActionRow(
          actions: <Widget>[
            if (widget.onCancel case final cancel?)
              AppButton(
                key: const ValueKey('sale-returns-cancel'),
                label: 'Cancel',
                tier: AppButtonTier.secondary,
                // Disabled while a write is outstanding: it is already on its
                // way, and closing the sheet would discard the answer to it.
                onPressed: widget.busy ? null : cancel,
              ),
            AppButton(
              key: const ValueKey('sale-returns-submit'),
              label: 'Record return',
              tier: AppButtonTier.primary,
              onPressed: _canSubmit ? _confirm : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Names the two states separately on the page a user is inspecting.
///
/// The counts describe this page only. They are not a total for the sale: a
/// later page may carry more, and a running total computed here would be a
/// second, weaker aggregate that disagrees with the server's.
String _countsLabel(TenantReturnPage page) {
  final verified = page.verified.length;
  final pending = page.pending.length;
  return 'On this page: $verified verified, $pending pending.';
}

String _lineLabel(TenantReturnLine line) =>
    '${line.quantity} x ${line.label ?? line.productId}';

String _recordedLabel(TenantReturn record, String createdByLabel) {
  final recordedAt = record.recordedAt;
  return recordedAt == null
      ? 'Recorded by $createdByLabel; the server has not confirmed it yet.'
      : 'Recorded ${_instant(recordedAt)} by $createdByLabel';
}

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
}
