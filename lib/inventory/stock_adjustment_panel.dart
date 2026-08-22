import 'package:flutter/material.dart';

import '../reporting/reconciliation_anomalies.dart';
import '../reporting/reconciliation_labels.dart';
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
import '../ui/stats.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'stock_actions.dart';
import 'stock_adjustment.dart';
import 'stock_adjustment_feed_panel.dart';
import 'stock_movement_labels.dart';
import 'stock_movements.dart';

/// Read-and-correct stock route for one product in the selected tenant.
final class TenantProductStockScreen extends StatelessWidget {
  const TenantProductStockScreen({
    super.key,
    required this.reader,
    required this.product,
    this.actions,
  });

  final TenantDataReader reader;

  /// The already-decoded catalog record this route was opened for. Only its ID
  /// is used to read: the quantity shown is always re-read canonically.
  final TenantProduct product;

  final TenantStockActions? actions;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: product.name,
    contentWidth: AppContentWidth.records,
    body: TenantProductStockPanel(
      reader: reader,
      product: product,
      actions: actions,
    ),
  );
}

/// How many of a product's recorded differences this route reads.
///
/// Reconciliation writes one record per run that found a difference and never
/// deletes an old one, so a long-neglected product can hold many. This is a
/// summary beside a stock figure rather than a list to page through, so it is
/// deliberately small and says when there are more.
const int _productDifferencePageSize = 5;

/// What this route could learn about the differences listed against a product.
///
/// A separate outcome from the stock read on purpose. The recorded quantity and
/// the ledger are what this route exists for, so a reconciliation read that fails
/// or is refused is carried here as a value and reported in place, rather than
/// thrown into the route guard's failure state where it would take the stock
/// figure off the screen with it. The same degrade-rather-than-fail rule the
/// staff-name resolver beside it already follows.
final class _ProductDifferences {
  const _ProductDifferences.listed({required this.items, required this.hasMore})
    : readable = true;

  const _ProductDifferences.unreadable()
    : items = const <TenantReconciliationAnomaly>[],
      hasMore = false,
      readable = false;

  final List<TenantReconciliationAnomaly> items;

  /// Whether more are recorded against this product than were read.
  final bool hasMore;

  /// False only when the read failed or this session may not make it. An empty
  /// readable answer and an unreadable one say very different things, and the
  /// surface must never present the second as the first.
  final bool readable;
}

/// One guarded view of a product's recorded stock and its ledger page.
final class _StockView {
  const _StockView({
    required this.stock,
    required this.names,
    required this.differences,
  });

  final TenantProductStockView stock;
  final Map<String, String> names;
  final _ProductDifferences differences;
}

/// Shows one product's recorded stock, pages its server-written ledger, and
/// records a management-only adjustment behind [TenantRouteGuard].
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding page or call discards it before it can update the UI.
final class TenantProductStockPanel extends StatefulWidget {
  const TenantProductStockPanel({
    super.key,
    required this.reader,
    required this.product,
    this.actions,
    this.pageSize = 20,
    this.requestIdFactory,
  });

  final TenantDataReader reader;
  final TenantProduct product;
  final TenantStockActions? actions;
  final int pageSize;

  /// One fresh request ID per confirmation intent.
  final String Function()? requestIdFactory;

  @override
  State<TenantProductStockPanel> createState() =>
      _TenantProductStockPanelState();
}

final class _TenantProductStockPanelState
    extends State<TenantProductStockPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  int _generation = 0;
  bool _busy = false;
  AppNotice? _notice;

  /// Retained only across an ambiguous attempt, so a retry addresses the same
  /// idempotency record instead of moving the same stock twice.
  String? _requestId;
  TenantStaffNameResolver? _staffNames;
  String? _staffNamesSessionKey;

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

  /// Whether the session this work was authorized against is still selected.
  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  /// One loader per guard key; a closure rebuilt every frame would reload on
  /// every `setState` and discard the half-filled adjustment form.
  TenantGuardedLoader<_StockView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final productId = widget.product.id;
    final cursor = _cursors[_pageIndex];
    return _loader = (session) async {
      final stock =
          await TenantProductStockRepository(
            session: session,
            reader: widget.reader,
          ).loadStock(
            productId: productId,
            pageSize: widget.pageSize,
            cursor: cursor,
          );
      return _StockView(
        stock: stock,
        names: await _resolverFor(session).resolve(
          stock.movements.items
              .map((movement) => movement.actorUid)
              .whereType<String>(),
        ),
        differences: await _readDifferences(session, productId),
      );
    };
  }

  /// Reads what reconciliation recorded against this product, and never fails
  /// the page.
  ///
  /// The repository refuses a session it does not admit, and that refusal is
  /// reported here rather than thrown: this route's own guard already decides who
  /// may see a product's stock, and a difference nobody can read is not a reason
  /// to hide the quantity somebody is accountable for.
  Future<_ProductDifferences> _readDifferences(
    TenantSession session,
    String productId,
  ) async {
    try {
      final page =
          await TenantReconciliationAnomalyRepository(
            session: session,
            reader: widget.reader,
          ).loadProductPage(
            productId: productId,
            pageSize: _productDifferencePageSize,
          );
      return _ProductDifferences.listed(
        items: page.items,
        hasMore: page.hasMore,
      );
    } catch (_) {
      return const _ProductDifferences.unreadable();
    }
  }

  String? _loaderKey;
  TenantGuardedLoader<_StockView>? _loader;

  /// Adjusts this product's stock through the session- and product-bound
  /// gateway, then re-reads so what is shown is the server's own figure rather
  /// than an optimistic local one.
  Future<void> _adjust(
    TenantSession session,
    TenantProduct product,
    TenantStockAdjustmentType type,
    int quantityDelta,
    String reason,
  ) async {
    final callable = widget.actions?.adjustCallable;
    if (callable == null || _busy) return;
    final capturedKey = _sessionKey(session);
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final gateway = TenantStockAdjustmentGateway(
        session: session,
        product: product,
        callable: callable,
        requestIdFactory: () => _requestId ??=
            (widget.requestIdFactory ?? secureStockAdjustmentRequestId)(),
      );
      final result = await gateway.submit(
        gateway.createIntent(
          type: type,
          quantityDelta: quantityDelta,
          reason: reason,
        ),
      );
      if (!_stillCurrent(capturedKey)) return;
      _requestId = null;
      setState(
        () => _notice = AppNotice.confirmed(
          'Stock changed from ${result.previousQuantity} to '
          '${result.quantity}.',
        ),
      );
      _reload();
    } on TenantStockAdjustmentException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      // Only an unknown outcome may have moved stock, so only it keeps the
      // request ID. Every other refusal left nothing behind, and reusing its ID
      // would make an edited retry fail as a duplicate.
      if (!error.mayHaveCommitted) _requestId = null;
      setState(() => _notice = _adjustmentNotice(error.failure));
      if (error.mayHaveCommitted) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      // The call may well have moved stock; only its answer was unusable.
      setState(
        () => _notice = const AppNotice.unknown(
          'The adjustment response could not be trusted. Reload this page to '
          'see what the server recorded.',
        ),
      );
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '${widget.product.id}:$_generation:$_pageIndex:$cursor';
    return TenantRouteGuard<_StockView>(
      key: ValueKey(guardKey),
      allowedRoles: TenantProductStockRepository.allowedRoles,
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('product-stock-denied'),
        child: Text('Stock is unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('product-stock-failure'),
        child: Text('This product\'s stock could not be loaded.'),
      ),
      builder: (context, session, view) => _ProductStockContents(
        view: view,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        busy: _busy,
        notice: _notice,
        // The same domain owns both surfaces, so this route needs no injection
        // from the composition root; it opens under this route's own scope.
        onOpenAdjustments: () => openTenantStockAdjustmentFeed(
          context,
          reader: widget.reader,
          product: view.stock.product,
        ),
        canAdjust:
            widget.actions?.adjustCallable != null &&
            TenantStockAdjustmentGateway.canAdjustInSession(session),
        onNextPage: () => _nextPage(view.stock.movements.nextCursor),
        onPreviousPage: _previousPage,
        onAdjust: (type, quantityDelta, reason) =>
            _adjust(session, view.stock.product, type, quantityDelta, reason),
      ),
    );
  }
}

/// What an adjustment can and cannot do about one recorded difference.
///
/// **This screen's own sentence, which is why it is here and not in
/// `reconciliation_labels.dart` with the figures.** What a difference *is* is the
/// same on every surface that shows it; what to press about it is a fact about
/// this page, and this page is the only one with the form three inches below.
/// Only one of the four kinds a product can hold is a quantity disagreement an
/// adjustment resolves, and the other three say so rather than inviting a
/// correction that would not resolve them.
String _resolutionNote(TenantReconciliationAnomaly anomaly) =>
    switch (anomaly.kind) {
      TenantReconciliationAnomalyKind.stockVariance =>
        'An adjustment recorded below is how this is put right.',
      TenantReconciliationAnomalyKind.invalidStockMovement =>
        'An adjustment will not resolve this: the ledger entry below is what '
            'needs looking at.',
      TenantReconciliationAnomalyKind.checkpointChainInvalid =>
        'An adjustment will not resolve it.',
      TenantReconciliationAnomalyKind.invalidProductQuantity =>
        'Nothing can be added to it until that is repaired.',
      // Reachable only for a kind this build does not model, or one a server
      // started filing against a product. The figures above are the record's
      // own; what an adjustment would do about it is not something this version
      // can promise either way.
      TenantReconciliationAnomalyKind.invalidSaleLines ||
      TenantReconciliationAnomalyKind.invalidOrMissingShift ||
      TenantReconciliationAnomalyKind.shiftVariance ||
      TenantReconciliationAnomalyKind.other =>
        'Whether an adjustment resolves this is not something this version of '
            'the app can say.',
    };

/// **Nine refusals and one unknown**, on the split every other surface in this
/// family takes: `ambiguous` is the only branch where stock may actually have
/// moved, and it is the only one that sends a person to look at the ledger.
AppNotice _adjustmentNotice(TenantStockAdjustmentFailure failure) =>
    switch (failure) {
      TenantStockAdjustmentFailure.forbidden => const AppNotice.refused(
        'Only an owner, administrator, or manager may adjust stock.',
      ),
      TenantStockAdjustmentFailure.productMissing => const AppNotice.refused(
        'This product no longer exists in this business, so nothing changed.',
      ),
      TenantStockAdjustmentFailure.refusedDirection => const AppNotice.refused(
        'That adjustment type cannot move stock in that direction. Nothing '
        'changed.',
      ),
      TenantStockAdjustmentFailure.invalidQuantity => const AppNotice.refused(
        'Enter a whole number of units between 1 and '
        '$maximumStockAdjustmentQuantityDelta.',
      ),
      TenantStockAdjustmentFailure.invalidReason => const AppNotice.refused(
        'Record a reason of at least $minimumStockAdjustmentReasonLength '
        'characters for this adjustment.',
      ),
      TenantStockAdjustmentFailure.duplicateRequest => const AppNotice.refused(
        'An earlier attempt already used this correction. Nothing changed a '
        'second time; start a new adjustment.',
      ),
      TenantStockAdjustmentFailure.outOfRange => const AppNotice.refused(
        'The resulting quantity would be too large to record. Nothing changed.',
      ),
      TenantStockAdjustmentFailure.invalidStoredQuantity =>
        const AppNotice.refused(
          'This product\'s recorded quantity is not a whole number, so nothing '
          'can be added to it. It needs reconciliation.',
        ),
      TenantStockAdjustmentFailure.refused => const AppNotice.refused(
        'The adjustment was refused and no stock changed.',
      ),
      TenantStockAdjustmentFailure.ambiguous => const AppNotice.unknown(
        'The result is unknown. This page has been reloaded; check the stock '
        'and the ledger below before trying again.',
      ),
    };

final class _ProductStockContents extends StatelessWidget {
  const _ProductStockContents({
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.busy,
    required this.notice,
    required this.canAdjust,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onOpenAdjustments,
    required this.onAdjust,
  });

  final _StockView view;
  final String selfUid;
  final int pageIndex;
  final bool busy;
  final AppNotice? notice;
  final bool canAdjust;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  /// Opens the manual-correction feed narrowed to this product.
  final VoidCallback onOpenAdjustments;

  final void Function(
    TenantStockAdjustmentType type,
    int quantityDelta,
    String reason,
  )
  onAdjust;

  TenantProduct get product => view.stock.product;
  TenantStockMovementPage get page => view.stock.movements;
  _ProductDifferences get differences => view.differences;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('product-stock'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      children: [
        // §7's "Title appears once", and this was the example `design.md` names
        // in its own words: `web/21-product-stock` read *White bread loaf* in
        // `display` and *White bread loaf* again directly under it. The
        // `AppScaffold` title is this same `product.name`.
        SizedBox(height: tokens.spacing.s4),
        Text('SKU ${product.sku}'),
        SizedBox(height: tokens.spacing.s16),
        // The headline figures. `product-stock-quantity` now keys the number
        // itself rather than a sentence containing it, because the caption is
        // the card's own label - the fact it states is unchanged.
        StatRow(
          tiles: [
            StatTile(
              valueKey: const ValueKey('product-stock-quantity'),
              label: 'Recorded stock',
              value: '${product.quantity}',
              icon: Icons.inventory_2_outlined,
              detail: 'held by the server',
              // Negative is a real, permitted state rather than a fault, but it
              // is the one a person needs to notice on sight. It used to be a red
              // number, which is §9's "out of stock signalled by red text alone"
              // in another place; §2.1 wants a container, a glyph and a word, and
              // "difference found" is `problem`'s own meaning.
              status: product.quantity < 0 ? AppStatus.problem : null,
              statusLabel: product.quantity < 0 ? 'Below zero' : null,
            ),
            StatTile(
              key: const ValueKey('product-stock-stat-movements'),
              label: 'Ledger entries',
              value: '${page.items.length}',
              icon: Icons.receipt_long_outlined,
              detail: page.hasMore
                  ? 'on this page, more to load'
                  : 'on this page',
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.s12),
        // The last unfolded permanent paragraph above the fold on this screen.
        // Step 4 put the adjustment explanation behind a `Disclosure` further down
        // and left this one and the ledger's own note as loose body text, so the
        // screen has been carrying one folded explanation and two unfolded ones
        // ever since. It also carried the only raw `colorScheme` read left on this
        // route; `Disclosure` reads §2.2's own body role from the token layer.
        const Disclosure(
          key: ValueKey('product-stock-quantity-disclosure'),
          summary: 'Why stock can be negative',
          child: Text(
            key: ValueKey('product-stock-quantity-scope'),
            'This is the quantity the server holds, not a figure derived on this '
            'device. Stock may legitimately be negative: a sale is never blocked '
            'by a stock count, so a product can be sold past zero and corrected '
            'here afterwards.',
          ),
        ),
        // **This one sits directly above the "Reconciliation found" section**,
        // which draws every recorded difference as a red `Callout`. A bare
        // sentence saying "Stock changed from 10 to 7." immediately above a stack
        // of red blocks reads as part of the problem rather than as the answer to
        // it, which is the sharpest case in the family for a notice carrying its
        // own status.
        if (notice case final answer?) ...[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('product-stock-notice'),
            status: answer.status,
            message: answer.message,
          ),
        ],
        ..._differencesSection(context),
        SizedBox(height: tokens.spacing.s24),
        Text(
          'Stock ledger',
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s4),
        const Disclosure(
          key: ValueKey('product-stock-ledger-disclosure'),
          summary: 'What the ledger holds',
          child: Text(
            key: ValueKey('product-stock-ledger-scope'),
            'Every sale, verified return, and manual adjustment the server '
            'recorded for this product. It is listed by record ID, which is not '
            'time order; each entry states when it was recorded.',
          ),
        ),
        SizedBox(height: tokens.spacing.s12),
        // §4.3's responsive contract, in the same record vocabulary the two feeds
        // beside it use. This screen used to describe the same document three
        // ways - its own source label, its own figures sentence, its own
        // attribution - which is precisely what `stock_movement_labels` exists to
        // prevent and what it had never been folded into.
        RecordList(
          identityLabel: 'Movement',
          items: <RecordItem>[
            for (final movement in page.items)
              stockMovementRecord(
                movement,
                keyPrefix: 'product-stock',
                rowKey: movement.id,
                names: view.names,
                selfUid: selfUid,
              ),
          ],
          empty: const Text(
            key: ValueKey('product-stock-empty'),
            'No stock movements have been recorded for this product.',
          ),
        ),
        SizedBox(height: tokens.spacing.s16),
        // **Pagination is secondary, and it used to be a primary.** §2.1
        // permits exactly one primary per screen region and on this route that
        // is `Adjust stock`; "Next page" competing with it for the eye is the
        // tier system not being applied rather than a taste call. The same
        // repoint is made on every paginated feed - and as of `Pagination` it
        // is made once, in the component, rather than on thirteen screens.
        Pagination(
          pageNumber: pageIndex + 1,
          previousKey: const ValueKey('product-stock-previous'),
          nextKey: const ValueKey('product-stock-next'),
          onPrevious: pageIndex > 0 ? onPreviousPage : null,
          onNext: page.hasMore ? onNextPage : null,
        ),
        SizedBox(height: tokens.spacing.s12),
        // **Out of the page bar it was sharing, and that is the migration
        // finding on this screen.** It is not pagination: it opens another
        // route. It sat in the same `Wrap` only because the `Wrap` was where
        // the buttons were, and `Pagination` owning its own form is what
        // surfaced it.
        //
        // The ledger explains every movement; this narrows the business-wide
        // correction record to the manual ones recorded against this product.
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            key: const ValueKey('product-stock-adjustments'),
            label: 'Manual adjustments',
            icon: Icons.fact_check_outlined,
            onPressed: onOpenAdjustments,
          ),
        ),
        if (canAdjust) ...[
          SizedBox(height: tokens.spacing.s24),
          const Divider(),
          SizedBox(height: tokens.spacing.s12),
          _AdjustStockForm(
            key: const ValueKey('product-stock-form'),
            quantity: product.quantity,
            busy: busy,
            onAdjust: onAdjust,
          ),
        ],
      ],
    );
  }

  /// What reconciliation recorded against this product, said where the person
  /// who can act on it is already standing.
  ///
  /// Nothing at all is shown for a product with no recorded difference: this
  /// section is an exception report, and a permanent "no differences" line on
  /// every product would make the one that matters easier to miss rather than
  /// harder.
  List<Widget> _differencesSection(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    if (!differences.readable) {
      return <Widget>[
        SizedBox(height: tokens.spacing.s12),
        // **`info` rather than `problem`, and the deciding word is "refused".**
        // §2.1 does give "unreadable" to `problem`, which reads like the obvious
        // home for a read that failed - but this same sentence is what a session
        // permitted to read stock and not differences is shown, and calling a
        // permission boundary a fault would invent an answer the code refuses to
        // invent in words. The same reading step 4 applied to an unrecognised
        // day.
        //
        // Not §5.1's `ErrorState` either: that row replaces a *route's* "could
        // not be read" prose, and this is one degraded panel on a page whose
        // stock figure and ledger both loaded.
        const Callout(
          key: ValueKey('product-stock-differences-unreadable'),
          status: AppStatus.info,
          message:
              'Whether reconciliation recorded a difference for this product '
              'could not be read. The stock and ledger below are unaffected.',
        ),
      ];
    }
    if (differences.items.isEmpty) return const <Widget>[];
    return <Widget>[
      SizedBox(height: tokens.spacing.s24),
      Text(
        'Reconciliation found',
        style: tokens.typography.titleMedium.copyWith(
          color: tokens.colors.text.primary,
        ),
      ),
      SizedBox(height: tokens.spacing.s4),
      // A permanent helper paragraph: it is true of every difference this screen
      // will ever show, so it folds. The distinction it draws is what keeps the
      // section honest - a shift correction deletes the difference it resolved;
      // nothing deletes one of these, so an old record may already have been
      // dealt with and this list cannot tell you which.
      const Disclosure(
        key: ValueKey('product-stock-differences-scope-disclosure'),
        summary: 'Why old differences stay listed',
        child: Text(
          key: ValueKey('product-stock-differences-scope'),
          'A record is kept for each run that found a difference here, and none '
          'is ever removed: a later run that agrees simply records nothing new. '
          'So an older entry may already have been put right. Each one names '
          'the run that found it.',
        ),
      ),
      if (differences.hasMore) ...<Widget>[
        SizedBox(height: tokens.spacing.s12),
        // A notice about this page rather than a standing explanation - it is
        // here only because this particular product holds more than the page
        // read - so it does not fold. `info`: the page is complete, it is the
        // list that is bounded.
        const Callout(
          key: ValueKey('product-stock-differences-truncated'),
          status: AppStatus.info,
          message:
              'More are recorded against this product than are shown here, and '
              'this is not a list in time order, so these are not the most '
              'recent ones.',
        ),
      ],
      SizedBox(height: tokens.spacing.s12),
      for (final anomaly in differences.items) ...<Widget>[
        _difference(anomaly),
        SizedBox(height: tokens.spacing.s12),
      ],
    ];
  }

  /// One recorded difference, as the notice it is.
  ///
  /// **A `Callout` rather than a record, which is `PLAN.md`'s own reading of
  /// this section and holds up on contact.** §5.2's record contract is an
  /// identity, key-value attributes, a status, a provenance line and actions; a
  /// difference here is a kind and two to four sentences of explanation with
  /// nothing to press, and a table column of four-sentence paragraphs is not
  /// what §4.3 is for. The `Callout` container is also how §2.1's status gets
  /// rendered here without a badge: every record in this section is a difference
  /// found, so a badge on each would be a list with no signal in it.
  ///
  /// The figures come from the vocabulary the differences list shares with this
  /// screen; only [_resolutionNote] is this page's own.
  Widget _difference(TenantReconciliationAnomaly anomaly) => Callout(
    key: ValueKey('product-stock-difference-${anomaly.id}'),
    status: reconciliationDifferenceStatus,
    title: reconciliationDifferenceKindLabel(anomaly),
    message:
        '${reconciliationDifferenceFigures(anomaly)} '
        '${_resolutionNote(anomaly)}\n'
        '${reconciliationDifferenceProvenance(anomaly)}',
  );
}

/// Chooses one typed adjustment and requires an explicit confirmation.
///
/// The direction offered is decided by the type, because the server binds them:
/// a restock can only add and damage can only remove. Offering a combination
/// the callable refuses would teach an operator nothing except that the app
/// guesses.
final class _AdjustStockForm extends StatefulWidget {
  const _AdjustStockForm({
    super.key,
    required this.quantity,
    required this.busy,
    required this.onAdjust,
  });

  final int quantity;
  final bool busy;
  final void Function(
    TenantStockAdjustmentType type,
    int quantityDelta,
    String reason,
  )
  onAdjust;

  @override
  State<_AdjustStockForm> createState() => _AdjustStockFormState();
}

final class _AdjustStockFormState extends State<_AdjustStockForm> {
  TenantStockAdjustmentType _type = TenantStockAdjustmentType.restock;
  bool _increase = true;
  final TextEditingController _units = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _units.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _changeType(TenantStockAdjustmentType? type) {
    if (type == null) return;
    setState(() {
      _type = type;
      // A type that only moves one way decides the direction itself.
      if (!type.allowsIncrease) _increase = false;
      if (!type.allowsDecrease) _increase = true;
    });
  }

  int? get _unitCount {
    final parsed = int.tryParse(_units.text.trim());
    if (parsed == null ||
        parsed < 1 ||
        parsed > maximumStockAdjustmentQuantityDelta) {
      return null;
    }
    return parsed;
  }

  int? get _quantityDelta {
    final units = _unitCount;
    return units == null ? null : (_increase ? units : -units);
  }

  bool get _canSubmit =>
      !widget.busy &&
      _quantityDelta != null &&
      normalizeStockAdjustmentReason(_reason.text) != null;

  Future<void> _confirm() async {
    final quantityDelta = _quantityDelta;
    if (quantityDelta == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Adjust this stock?',
      // The type is a trailing clause rather than the sentence's object, so
      // one wording is grammatical for all six - "a opening_balance" was
      // wrong twice over, and an `a`/`an` test would only have fixed half.
      consequence:
          'This records an adjustment of '
          '${quantityDelta > 0 ? '+' : ''}$quantityDelta units, typed as '
          '${_type.sentenceLabel}. From the '
          'quantity recorded now, that is ${widget.quantity} to '
          '${widget.quantity + quantityDelta}.',
      stillTrue:
          'The server re-reads the product, so the final figure is whatever '
          'it holds at that moment. It cannot be undone from this app except '
          'by another adjustment.',
      confirmLabel: 'Adjust stock',
      tier: AppButtonTier.primary,
      confirmKey: const ValueKey('product-stock-confirm'),
      cancelKey: const ValueKey('product-stock-cancel'),
    );
    if (!confirmed || !mounted) return;
    widget.onAdjust(_type, quantityDelta, _reason.text);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Adjust stock',
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s4),
        // §5.2 names the stock-adjustment explanation as prose to keep and move
        // inside a `Disclosure`. The words are unchanged; the summary above them
        // is new because the component requires one.
        const Disclosure(
          key: ValueKey('product-stock-adjustment-disclosure'),
          summary: 'What an adjustment records',
          child: Text(
            'An adjustment is recorded permanently with its reason and cannot be '
            'deleted. Correcting a mistake means recording another adjustment.',
          ),
        ),
        SizedBox(height: tokens.spacing.s12),
        AppSelect<TenantStockAdjustmentType>(
          key: const ValueKey('product-stock-type'),
          value: _type,
          label: 'Adjustment type',
          items: [
            for (final type in TenantStockAdjustmentType.values)
              AppSelectItem<TenantStockAdjustmentType>(
                value: type,
                label: type.label,
              ),
          ],
          onChanged: widget.busy ? null : _changeType,
        ),
        SizedBox(height: tokens.spacing.s12),
        if (_type.direction == TenantStockAdjustmentDirection.either)
          SegmentedButton<bool>(
            key: const ValueKey('product-stock-direction'),
            segments: const [
              ButtonSegment<bool>(value: true, label: Text('Add stock')),
              ButtonSegment<bool>(value: false, label: Text('Remove stock')),
            ],
            selected: <bool>{_increase},
            onSelectionChanged: widget.busy
                ? null
                : (selection) => setState(() => _increase = selection.single),
          )
        else
          Text(
            key: const ValueKey('product-stock-fixed-direction'),
            _increase
                ? 'This type always adds stock.'
                : 'This type always removes stock.',
          ),
        SizedBox(height: tokens.spacing.s12),
        AppTextField(
          key: const ValueKey('product-stock-units'),
          controller: _units,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          label: 'Units',
          leading: Icons.numbers,
        ),
        SizedBox(height: tokens.spacing.s12),
        AppTextField(
          key: const ValueKey('product-stock-reason'),
          controller: _reason,
          maxLength: maximumStockAdjustmentReasonLength,
          onChanged: (_) => setState(() {}),
          label: 'Reason for this adjustment',
        ),
        SizedBox(height: tokens.spacing.s12),
        AppButton(
          key: const ValueKey('product-stock-submit'),
          label: 'Adjust stock',
          tier: AppButtonTier.primary,
          onPressed: _canSubmit ? _confirm : null,
        ),
      ],
    );
  }
}
