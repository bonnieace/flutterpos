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
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/skeleton.dart';
import '../ui/snackbar.dart';
import '../ui/stats.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'stock_actions.dart';
import 'stock_adjustment.dart';
import 'product_visual.dart';
import 'stock_adjustment_feed_panel.dart';
import 'stock_movement_labels.dart';
import 'stock_movements.dart';

/// The reading route for one product's stock in the selected tenant.
///
/// **A route again rather than half of one, since 2026-08-26.** The split of
/// 2026-08-25 gave correcting its own screen and left the two halves sharing a
/// `mode`; the correction is now [openTenantProductStockAdjustmentSheet], so
/// this is the ledger and nothing else and needs no flag to say which it is.
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

/// Opens the correction form as a screen of its own.
///
/// **A route again, at the product owner's direction on 2026-09-02**, reversing
/// the 2026-08-26 move to a sheet. The reason is the keyboard: this form's
/// subject is a *number a person types*, and a sheet is anchored to the bottom
/// of the screen, which is where the keys come up. Every arrangement that put
/// the quantity field and the submit control in the lower half of the sheet put
/// them under the keyboard the moment the field took focus - so the one figure
/// being entered was the one thing that could not be seen while entering it.
/// `showAppSheet` now lifts a sheet clear of the keys, and a form whose whole
/// purpose is typing still belongs on a surface that was never fighting them.
///
/// **The answer lands on the surface underneath, not in here.** A confirmed
/// adjustment pops this route and the sentence is shown by [showAppSnackBar]
/// over the catalog — see [TenantProductStockAdjustmentPanel.onCompleted] for
/// why a refusal deliberately does not.
Future<void> openTenantProductStockAdjustmentScreen(
  BuildContext context, {
  required TenantDataReader reader,
  required TenantProduct product,
  TenantStockActions? actions,
  String Function()? requestIdFactory,
}) async {
  // The same scope the catalog was authorized against, captured before the
  // route exists: a pushed route inherits nothing from the page it covers, so
  // without this the guard inside it would find no session.
  final sessions = TenantSessionScope.of(context);
  final answer = await Navigator.of(context).push<AppNotice>(
    AppPageRoute<AppNotice>(
      builder: (routeContext) => TenantSessionScope(
        controller: sessions,
        child: AppScaffold(
          // §7's "title appears once": the errand names the toolbar and the
          // product names the line under it, which is what this said before it
          // was briefly a sheet.
          title: 'Adjust stock',
          subtitle: product.name,
          // A form, which is §4.2's `reading` row rather than the `records`
          // row the stock ledger screen above it takes.
          contentWidth: AppContentWidth.reading,
          body: TenantProductStockAdjustmentPanel(
            reader: reader,
            product: product,
            actions: actions,
            requestIdFactory: requestIdFactory,
            onCompleted: (notice) => Navigator.of(routeContext).pop(notice),
            onCancel: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    ),
  );
  // `context.mounted` because the await above spans the whole life of the
  // route, and the catalog under it can be disposed by a tenant switch while
  // it is up. Announcing a stock change over a torn-down page would throw.
  if (answer != null && context.mounted) showAppSnackBar(context, answer);
}

/// Why a stock figure is allowed to be below zero.
///
/// **Hoisted out of the page body so the placeholder can draw the same one.**
/// It is a fixed paragraph that does not change when the read lands, which
/// under decision 35 makes it the page's rather than the read's - and a second
/// copy inside the loading state is a paragraph that would drift from this one.
const Disclosure _stockQuantityDisclosure = Disclosure(
  key: ValueKey('product-stock-quantity-disclosure'),
  summary: 'Why stock can be negative',
  child: Text(
    key: ValueKey('product-stock-quantity-scope'),
    'Stock may legitimately be negative: a sale is never blocked by a stock '
    'count, so a product can be sold past zero and corrected here afterwards.',
  ),
);

/// What the ledger below it lists. Hoisted for the same reason.
const Disclosure _stockLedgerDisclosure = Disclosure(
  key: ValueKey('product-stock-ledger-disclosure'),
  summary: 'What the ledger holds',
  child: Text(
    key: ValueKey('product-stock-ledger-scope'),
    'Every sale, verified return, and manual adjustment the server '
    'recorded for this product. It is listed by record ID, which is not '
    'time order; each entry states when it was recorded.',
  ),
);

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

/// Shows one product's recorded stock and pages its server-written ledger,
/// behind [TenantRouteGuard].
///
/// **Reading only, since the correction became a sheet on 2026-08-26.** It used
/// to carry the adjustment gateway too, behind a `mode` flag that decided which
/// half of itself to draw; that half is [TenantProductStockAdjustmentPanel] now,
/// which is why the busy flag, the notice and the retained request ID have all
/// left this class rather than being duplicated into it.
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding page discards it before it can update the UI.
final class TenantProductStockPanel extends StatefulWidget {
  const TenantProductStockPanel({
    super.key,
    required this.reader,
    required this.product,
    this.actions,
    this.pageSize = 20,
  });

  final TenantDataReader reader;
  final TenantProduct product;

  /// Retained so the composition root's wiring is unchanged and so this route
  /// still knows whether correcting is available at all. Nothing here calls it.
  final TenantStockActions? actions;

  final int pageSize;

  @override
  State<TenantProductStockPanel> createState() =>
      _TenantProductStockPanelState();
}

final class _TenantProductStockPanelState
    extends State<TenantProductStockPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
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

  /// One loader per guard key; a closure rebuilt every frame would reload on
  /// every `setState`.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final productId = widget.product.id;
    final cursor = _cursors[_pageIndex];
    TenantGuardedLoader<_StockView> readWith(TenantDataReader reader) =>
        (session) async {
          final stock =
              await TenantProductStockRepository(
                session: session,
                reader: reader,
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
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
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
  TenantGuardedLoader<_StockView>? _loaderCached;

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '${widget.product.id}:$_pageIndex:$cursor';
    _composeLoaders(guardKey);
    return TenantRouteGuard<_StockView>(
      allowedRoles: TenantProductStockRepository.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      // **A shimmer of this product's page rather than a spinner, at the
      // developer's direction on 2026-08-28.** Everything above the ledger is
      // page rather than read - the two headings, both explanations, the three
      // labels - so all of it is drawn immediately and only the figures and
      // the movements are blocks.
      loading: const _ProductStockReading(),
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
        // The same domain owns both surfaces, so this route needs no injection
        // from the composition root; it opens under this route's own scope.
        onOpenAdjustments: () => openTenantStockAdjustmentFeed(
          context,
          reader: widget.reader,
          product: view.stock.product,
        ),
        onNextPage: () => _nextPage(view.stock.movements.nextCursor),
        onPreviousPage: _previousPage,
      ),
    );
  }
}

/// Records one management-only stock correction behind [TenantRouteGuard].
///
/// **It re-reads the quantity and nothing else, and that is the change of
/// 2026-08-26.** While this was the second half of the ledger route it shared
/// that route's load: a page of twenty stock movements and a reconciliation
/// query, both drawn above the form. The sheet shows neither, so reading them
/// would spend two reads per open on nothing — [TenantProductStockRepository.
/// readProduct] is the same guarded, tenant-checked read `loadStock` begins
/// with, without the ledger page hanging off it.
///
/// The quantity is still never carried in from the catalog. The figure the form
/// states, and the one the confirmation arithmetic is done against, is read from
/// the canonical document when the sheet opens.
final class TenantProductStockAdjustmentPanel extends StatefulWidget {
  const TenantProductStockAdjustmentPanel({
    super.key,
    required this.reader,
    required this.product,
    this.actions,
    this.requestIdFactory,
    this.onCompleted,
    this.onCancel,
  });

  final TenantDataReader reader;

  /// The catalog record this was opened for. Only its ID is used to read.
  final TenantProduct product;

  final TenantStockActions? actions;

  /// One fresh request ID per confirmation intent.
  final String Function()? requestIdFactory;

  /// Called with the confirmation once, and only once, a correction commits.
  ///
  /// **Only a commit reports out, and a refusal deliberately does not.** The
  /// route pops on this callback, so handing it a refusal would throw away a
  /// half-typed reason and a chosen type at the exact moment a person needs
  /// them to fix what was wrong. A refusal stays here as a [Callout] over the
  /// form that produced it; an ambiguous outcome does too, because the figure
  /// above it has just been re-read and is the answer.
  ///
  /// Null renders every outcome in place, which is what a test pumping this
  /// panel bare sees.
  final void Function(AppNotice notice)? onCompleted;

  /// Abandons the correction. Null draws no cancel control.
  final VoidCallback? onCancel;

  @override
  State<TenantProductStockAdjustmentPanel> createState() =>
      _TenantProductStockAdjustmentPanelState();
}

final class _TenantProductStockAdjustmentPanelState
    extends State<TenantProductStockAdjustmentPanel> {
  int _generation = 0;
  bool _busy = false;

  /// Retained only across an ambiguous attempt, so a retry addresses the same
  /// idempotency record instead of moving the same stock twice.
  String? _requestId;

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  /// Restarts the guarded read of the canonical quantity.
  void _reload() => setState(() => _generation++);

  /// Whether the session this work was authorized against is still selected.
  bool _stillCurrent(String capturedKey) {
    if (!mounted) return false;
    final current = TenantSessionScope.of(context).session;
    return current != null && _sessionKey(current) == capturedKey;
  }

  String? _loaderKey;
  TenantGuardedLoader<TenantProduct>? _loader;
  TenantGuardedLoader<TenantProduct>? _loaderCached;

  /// One loader per guard key, for the reason the ledger's own has: a closure
  /// rebuilt every frame would re-read on every keystroke in the reason field
  /// and discard the half-filled form.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final productId = widget.product.id;
    TenantGuardedLoader<TenantProduct> readWith(TenantDataReader reader) =>
        (session) => TenantProductStockRepository(
          session: session,
          reader: reader,
        ).readProduct(productId);
    _loader = readWith(widget.reader);
    final cache = widget.reader.cached;
    _loaderCached = cache == null ? null : readWith(cache);
  }

  /// Reports [notice] the way this panel was wired to, and nothing more.
  void _answer(AppNotice notice) {
    final completed = widget.onCompleted;
    if (notice.status == AppStatus.ok && completed != null) {
      completed(notice);
      return;
    }
    showAppSnackBar(context, notice);
  }

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
    });
    try {
      final gateway = TenantStockAdjustmentGateway(
        session: session,
        product: product,
        callable: callable,
        queue: widget.actions?.adjustQueue,
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
      // **The re-read is skipped when the sheet is closing**, and that is not a
      // shortcut: `_answer` pops the route, so a `_reload` after it would start
      // a guarded read against a deactivated element. The figure this sheet was
      // showing is gone from the screen either way; the sentence carries the
      // server's own before-and-after.
      final confirmation = AppNotice.confirmed(
        'Stock changed from ${result.previousQuantity} to ${result.quantity}.',
      );
      _answer(confirmation);
      if (widget.onCompleted == null) _reload();
    } on TenantStockAdjustmentException catch (error) {
      if (!_stillCurrent(capturedKey)) return;
      // **Two different questions, and answering one with the other moves
      // stock twice.** The key is held whenever an attempt under it may already
      // be recorded - an unknown outcome, or a queue that says it already holds
      // different figures - because minting a fresh one would put a second
      // adjustment on top of the first. Every other refusal left nothing
      // behind, and holding its key would make an edited retry fail as a
      // duplicate for no reason. The re-read follows the same question: if
      // something may be out there, the figure above is worth reading again.
      if (!error.retainsRequestId) _requestId = null;
      _answer(_adjustmentNotice(error.failure));
      if (error.retainsRequestId) _reload();
    } on FormatException {
      if (!_stillCurrent(capturedKey)) return;
      // The call may well have moved stock; only its answer was unusable.
      _answer(
        const AppNotice.unknown(
          'The adjustment response could not be trusted. Close this and open '
          'the product\'s stock to see what the server recorded.',
        ),
      );
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guardKey = '${widget.product.id}:$_generation';
    _composeLoaders(guardKey);
    return TenantRouteGuard<TenantProduct>(
      allowedRoles: TenantProductStockRepository.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      denied: const Center(
        key: ValueKey('product-stock-denied'),
        child: Text('Stock is unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('product-stock-failure'),
        child: Text('This product\'s stock could not be loaded.'),
      ),
      builder: (context, session, product) => _AdjustStockContents(
        product: product,
        busy: _busy,
        canAdjust:
            widget.actions?.adjustCallable != null &&
            TenantStockAdjustmentGateway.canAdjustInSession(session),
        onCancel: widget.onCancel,
        onAdjust: (type, quantityDelta, reason) =>
            _adjust(session, product, type, quantityDelta, reason),
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
      TenantReconciliationAnomalyKind.shiftTenderVariance ||
      TenantReconciliationAnomalyKind.missingTenderDeclaration ||
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
      TenantStockAdjustmentFailure.duplicateRequest => const AppNotice.unknown(
        'An earlier attempt recorded different figures under this correction, '
        'and it has not settled yet. Nothing was changed a second time. Close '
        'this and check the stock and the ledger before recording anything '
        'else.',
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
      // `refused` rather than `unknown`: its own definition is "the write was
      // refused and nothing changed", and that is precisely what is known here.
      // Nothing is awaiting confirmation, so nothing should be drawn as pending.
      TenantStockAdjustmentFailure.notRecorded => const AppNotice.refused(
        'This device could not store the adjustment, so nothing was recorded '
        'and nothing was sent. Try again, and report it if it keeps happening.',
      ),
      TenantStockAdjustmentFailure.ambiguous => const AppNotice.unknown(
        'The result is unknown. This page has been reloaded; check the stock '
        'and the ledger below before trying again.',
      ),
    };

/// One product's stock page while it is still being read.
///
/// **Almost all of this screen is chrome, and that is why it is worth drawing.**
/// The SKU line, the two figure tiles, *Why stock can be negative*, *Stock
/// ledger*, *What the ledger holds* - only the two numbers and the ledger rows
/// change when the read returns. A person waiting on this page can read both
/// explanations while they wait, which is the whole of decision 35's argument
/// in one screen.
///
/// **No figure is claimed.** The tiles are blocks rather than zeroes: a stock
/// count of nothing and a stock count not yet read are very different facts,
/// and this page exists to be the authority on the first.
final class _ProductStockReading extends StatelessWidget {
  const _ProductStockReading();

  /// A figure tile's height, which no source in this app states - the same
  /// composition `_ExpensesReading` measured for the same pair of tiles.
  static double _tileHeight(AppSpacing spacing) => spacing.s64 + spacing.s24;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return SkeletonGroup(
      semanticLabel: 'Reading this product\'s stock.',
      child: ListView(
        key: const ValueKey('product-stock-reading'),
        padding: EdgeInsets.all(tokens.spacing.s20),
        children: <Widget>[
          SizedBox(height: tokens.spacing.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // The product's picture, at the square the real header gives it.
              SkeletonBlock(
                width: tokens.spacing.s64,
                height: tokens.spacing.s64,
                radius: tokens.radius.md,
              ),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: SkeletonLine(
                  widthFactor: 0.42,
                  style: tokens.typography.mono,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s16),
          Row(
            children: <Widget>[
              // Two tiles at `StatRow`'s own gap: *Recorded stock* and *Ledger
              // entries*, which is the pair this screen always draws.
              for (var tile = 0; tile < 2; tile++) ...<Widget>[
                if (tile > 0) SizedBox(width: tokens.spacing.s12),
                Expanded(
                  child: SkeletonBlock(
                    height: _tileHeight(tokens.spacing),
                    radius: tokens.radius.lg,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: tokens.spacing.s12),
          _stockQuantityDisclosure,
          SizedBox(height: tokens.spacing.s24),
          SectionHeading('Stock ledger'),
          SizedBox(height: tokens.spacing.s4),
          _stockLedgerDisclosure,
          SizedBox(height: tokens.spacing.s12),
          // The real ledger is a `RecordList`, so its placeholder is the one
          // that asks `RecordList` which form it will take.
          const RecordListSkeleton(),
        ],
      ),
    );
  }
}

final class _ProductStockContents extends StatelessWidget {
  const _ProductStockContents({
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onOpenAdjustments,
  });

  final _StockView view;
  final String selfUid;
  final int pageIndex;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  /// Opens the manual-correction feed narrowed to this product.
  final VoidCallback onOpenAdjustments;

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
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox.square(
              dimension: tokens.spacing.s64,
              child: TenantProductVisual(product: product),
            ),
            SizedBox(width: tokens.spacing.s12),
            Expanded(
              child: Text(
                'SKU ${product.sku}',
                style: tokens.typography.mono.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
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
        _stockQuantityDisclosure,
        // **No notice block here any more.** This route writes nothing, so
        // there is never an answer to report on it; the one place a stock
        // sentence appears is over the surface the correction sheet closed on
        // to. See `_AdjustStockContents` for the notice that stayed behind.
        ..._differencesSection(context),
        SizedBox(height: tokens.spacing.s24),
        SectionHeading('Stock ledger'),
        SizedBox(height: tokens.spacing.s4),
        _stockLedgerDisclosure,
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
        // **Pagination is secondary.** §2.1 permits exactly one primary per
        // screen region, and "Next page" competing for the eye is the tier
        // system not being applied rather than a taste call. The same repoint
        // is made on every paginated feed - and as of `Pagination` it is made
        // once, in the component, rather than on thirteen screens.
        //
        // It used to say `Adjust stock` was this region's primary. That control
        // is a sheet over the catalog now and this route has no primary at all.
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
      SectionHeading('Reconciliation found'),
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

/// The correction sheet: the figure being corrected, and the form that
/// corrects it.
///
/// **What is not here is the point of the change.** Until 2026-08-26 this was
/// the reading route with a form appended, so a person who pressed *Adjust
/// stock* got the product's picture, its SKU, how many ledger entries were on
/// the current page, a fold explaining why stock can be negative, and the whole
/// reconciliation exception report — every one of them a second copy of what
/// *View stock* is for, above the two fields they had actually come to fill in.
///
/// **The recorded quantity stays, and it is the only thing that did.** It is
/// not context about the product; it is the operand. The confirmation says "from
/// the quantity recorded now, that is 12 to 9", and a person cannot check that
/// arithmetic against a figure they cannot see.
final class _AdjustStockContents extends StatelessWidget {
  const _AdjustStockContents({
    required this.product,
    required this.busy,
    required this.canAdjust,
    required this.onAdjust,
    required this.onCancel,
  });

  final TenantProduct product;
  final bool busy;
  final bool canAdjust;

  final void Function(
    TenantStockAdjustmentType type,
    int quantityDelta,
    String reason,
  )
  onAdjust;

  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('product-stock-adjust'),
      // The page's own inset. No top one: `AppScaffold` already spends a gap
      // under the toolbar, and the toolbar is what carries the title now.
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.s20,
        0,
        tokens.spacing.s20,
        tokens.spacing.s24,
      ),
      children: <Widget>[
        // The figure the form is about, re-read canonically when the screen
        // opened. `StatRow` rather than a bare number because this is a
        // headline figure and §2.1's negative case needs a container, a glyph
        // and a word - a red number alone is §9's own counter-example.
        StatRow(
          tiles: <StatTile>[
            StatTile(
              valueKey: const ValueKey('product-stock-quantity'),
              label: 'Recorded stock',
              value: '${product.quantity}',
              icon: Icons.inventory_2_outlined,
              status: product.quantity < 0 ? AppStatus.problem : null,
              statusLabel: product.quantity < 0 ? 'Below zero' : null,
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.s16),
        if (canAdjust)
          _AdjustStockForm(
            key: const ValueKey('product-stock-form'),
            quantity: product.quantity,
            busy: busy,
            onAdjust: onAdjust,
            onCancel: onCancel,
          )
        else
          // A session that may not adjust must never be offered the control
          // that opens this screen - the catalog withholds it - so arriving
          // here without the permission is a wiring fault rather than a state
          // to design for, and it says so instead of drawing an empty page.
          const Callout(
            key: ValueKey('product-stock-adjust-denied'),
            status: AppStatus.problem,
            message:
                'Only an owner, administrator, or manager may correct '
                'stock.',
          ),
      ],
    );
  }
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
    this.onCancel,
  });

  final int quantity;
  final bool busy;
  final void Function(
    TenantStockAdjustmentType type,
    int quantityDelta,
    String reason,
  )
  onAdjust;

  /// Abandons the correction without recording anything.
  ///
  /// **The sheet is dismissible and still draws this**, which is not a
  /// duplicate control. Dragging a sheet down is a gesture, and §9's target
  /// rules are about things a person can aim at: a reachable, labelled way out
  /// is what a switch or a keyboard has, and the drag handle is not one. It is
  /// `secondary` so §2.1's one-primary-per-region still names `Adjust stock`.
  final VoidCallback? onCancel;

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
        // **No `SectionHeading` here since 2026-08-26.** It read `Adjust stock`
        // directly under a sheet header reading `Adjust stock`, which is the
        // §7 violation this form was the last instance of on this surface.
        //
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
        SizedBox(height: tokens.spacing.s16),
        // **Right-aligned, with the primary last, since 2026-08-26.** Owner
        // direction and the reason is the hand: a sheet is a phone surface, most
        // people hold it right-handed, and the control they will press is the
        // one under the thumb rather than the one furthest from it. `Cancel`
        // first also puts the destructive-by-omission choice where a
        // right-handed thumb has to travel to reach it.
        //
        // `AppActionRow` rather than the `Wrap` this shipped with: it is the
        // app's own footer row, it already defaults to `MainAxisAlignment.end`,
        // and its `Flexible` children contract and ellipsize rather than
        // wrapping - so a large text scale shortens a label instead of dropping
        // a button onto its own line.
        AppActionRow(
          actions: <Widget>[
            if (widget.onCancel case final cancel?)
              AppButton(
                key: const ValueKey('product-stock-cancel-adjust'),
                label: 'Cancel',
                tier: AppButtonTier.secondary,
                // Disabled while a call is outstanding: the write is already on
                // its way and closing the sheet would throw away the answer to
                // it, which is the one thing this form must never do with money.
                onPressed: widget.busy ? null : cancel,
              ),
            AppButton(
              key: const ValueKey('product-stock-submit'),
              label: 'Adjust stock',
              tier: AppButtonTier.primary,
              onPressed: _canSubmit ? _confirm : null,
            ),
          ],
        ),
      ],
    );
  }
}
