import 'package:flutter/material.dart';

import '../ui/fields.dart';
import '../ui/pagination.dart';
import '../ui/record_list.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/tokens.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import 'stock_movement_feed.dart';
import 'stock_movement_labels.dart';
import 'stock_movements.dart';

/// Opens the ledger of one product named by a feed row.
///
/// Supplied by the composition root, exactly like every other injected route:
/// while it is absent the feed is precisely the read-only list it was before.
/// It takes a product **ID** rather than a decoded product, because a row is
/// all this surface has - and because the product may no longer exist.
typedef TenantProductLedgerRouteBuilder = Widget Function(String productId);

/// Read-only route listing everything that moved this business's stock.
final class TenantStockMovementFeedScreen extends StatelessWidget {
  const TenantStockMovementFeedScreen({
    super.key,
    required this.reader,
    required this.groupReader,
    this.source,
    this.productLedgerRoute,
  });

  /// Only staff labels are read by path here; this surface issues no
  /// single-collection page at all.
  final TenantDocumentReader reader;

  /// The collection-group boundary is injected separately from every
  /// path-bounded read, because it is a genuinely wider one.
  final TenantCollectionGroupReader groupReader;

  /// When present, the feed opens narrowed to exactly this source.
  final TenantStockMovementSource? source;

  final TenantProductLedgerRouteBuilder? productLedgerRoute;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Stock movements',
    contentWidth: AppContentWidth.records,
    body: TenantStockMovementFeedPanel(
      reader: reader,
      groupReader: groupReader,
      source: source,
      productLedgerRoute: productLedgerRoute,
    ),
  );
}

/// One guarded page of movements with the staff names it needs.
final class _MovementFeedView {
  const _MovementFeedView({required this.page, required this.names});

  final TenantStockMovementFeedPage page;
  final Map<String, String> names;
}

/// Pages the business-wide `stock_movements` group behind [TenantRouteGuard].
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding page discards it before it can update the UI. Nothing
/// on this surface can record, amend, or undo a movement.
final class TenantStockMovementFeedPanel extends StatefulWidget {
  const TenantStockMovementFeedPanel({
    super.key,
    required this.reader,
    required this.groupReader,
    this.source,
    this.productLedgerRoute,
    this.pageSize = 20,
  });

  /// Only staff labels are read by path here; this surface issues no
  /// single-collection page at all.
  final TenantDocumentReader reader;
  final TenantCollectionGroupReader groupReader;
  final TenantStockMovementSource? source;
  final TenantProductLedgerRouteBuilder? productLedgerRoute;
  final int pageSize;

  @override
  State<TenantStockMovementFeedPanel> createState() =>
      _TenantStockMovementFeedPanelState();
}

final class _TenantStockMovementFeedPanelState
    extends State<TenantStockMovementFeedPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  TenantStockMovementSource? _source;
  final TenantStaffNameResolvers _staffNames = TenantStaffNameResolvers();
  String? _loaderKey;
  TenantGuardedLoader<_MovementFeedView>? _loader;
  TenantGuardedLoader<_MovementFeedView>? _loaderCached;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
  }

  @override
  void didUpdateWidget(covariant TenantStockMovementFeedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _selectSource(widget.source);
  }

  /// One resolver per session **and per pass**, so the cached pass resolves a
  /// name from this device rather than putting a network read in front of
  /// records it already holds. An unresolved name degrades to the UID.
  TenantStaffNameResolver _resolverFor(
    TenantSession session,
    TenantDocumentReader reader,
  ) => _staffNames.of(session: session, reader: reader);

  /// Narrowing the feed restarts it: a cursor is a position inside one exact
  /// query, so carrying it across a filter change would page from somewhere the
  /// new query never established.
  void _selectSource(TenantStockMovementSource? source) {
    if (source == _source) return;
    setState(() {
      _source = source;
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

  /// One loader per guard key, so a closure rebuilt every frame cannot restart
  /// the page on an unrelated `setState`.
  void _composeLoaders(String key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    final source = _source;
    final cursor = _cursors[_pageIndex];
    // Both readers per pass, for the reason `catalog_management_panel` takes
    // both: this feed reads across every product's `stock_movements` through a
    // second boundary, and naming the live one on the cached pass makes the
    // page wait for a network whatever the disk is holding.
    TenantGuardedLoader<_MovementFeedView> readWith(
      TenantDocumentReader reader,
      TenantCollectionGroupReader groupReader,
    ) => (session) async {
      final repository = TenantStockMovementFeedRepository(
        session: session,
        reader: reader,
        groupReader: groupReader,
      );
      final page = source == null
          ? await repository.loadMovements(
              pageSize: widget.pageSize,
              cursor: cursor,
            )
          : await repository.loadMovementsOfSource(
              source: source,
              pageSize: widget.pageSize,
              cursor: cursor,
            );
      // A sale movement records no actor: nightly reconciliation writes it.
      return _MovementFeedView(
        page: page,
        names: await _resolverFor(session, reader).resolve(<String>[
          for (final movement in page.items)
            if (movement.actorUid case final actorUid?) actorUid,
        ]),
      );
    };
    _loader = readWith(widget.reader, widget.groupReader);
    final cache = widget.reader.cached;
    // **No cached pass without both halves.** This repository has no fallback
    // for the group reader - it is required - so a device copy that cannot
    // answer the collection group has nothing to offer the feed, and a pass
    // built on the live one would be the defect this change removes.
    final cachedGroup = widget.groupReader.cachedCollectionGroup;
    _loaderCached = cache == null || cachedGroup == null
        ? null
        : readWith(cache, cachedGroup);
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '${_source?.wireValue}:$_pageIndex:$cursor';
    _composeLoaders(guardKey);
    return TenantRouteGuard<_MovementFeedView>(
      allowedRoles: TenantStockMovementFeedRepository.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      denied: const Center(
        key: ValueKey('stock-movements-feed-denied'),
        child: Text('Stock movements are unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('stock-movements-feed-failure'),
        child: Text('The recorded stock movements could not be loaded.'),
      ),
      builder: (context, session, view) => _MovementFeedContents(
        view: view,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        onSelectSource: _selectSource,
        onNextPage: () => _nextPage(view.page.nextCursor),
        onPreviousPage: _previousPage,
        productLedgerRoute: widget.productLedgerRoute,
      ),
    );
  }
}

final class _MovementFeedContents extends StatelessWidget {
  const _MovementFeedContents({
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.onSelectSource,
    required this.onNextPage,
    required this.onPreviousPage,
    this.productLedgerRoute,
  });

  final _MovementFeedView view;
  final String selfUid;
  final int pageIndex;
  final ValueChanged<TenantStockMovementSource?> onSelectSource;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final TenantProductLedgerRouteBuilder? productLedgerRoute;

  TenantStockMovementFeedPage get page => view.page;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return PagedListView(
      listKey: const ValueKey('stock-movements-feed'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      pagination: Pagination(
        pageNumber: pageIndex + 1,
        previousKey: const ValueKey('stock-movements-feed-previous'),
        nextKey: const ValueKey('stock-movements-feed-next'),
        onPrevious: pageIndex > 0 ? onPreviousPage : null,
        onNext: page.hasMore ? onNextPage : null,
        endOfList: !page.hasMore,
      ),
      children: [
        // §7's "Title appears once": the `AppScaffold` above says `Stock
        // movements`, and this said the same thing at greater length under it.
        SizedBox(height: tokens.spacing.s4),
        Text(
          key: const ValueKey('stock-movements-feed-scope'),
          page.isSourceScoped
              ? 'Every "${page.source!.label}" entry recorded against this '
                    'business\'s products. Other movements are not listed on '
                    'this page.'
              : 'Every entry recorded against this business\'s products: sales, '
                    'verified returns, and manual corrections alike.',
        ),
        SizedBox(height: tokens.spacing.s4),
        const Text(
          'The ledger is permanent and cannot be edited from this app. It is '
          'listed by when the stock moved, most recent first - which for a '
          'sale reconciled later is when the sale happened, not when it '
          'reached the server.',
        ),
        SizedBox(height: tokens.spacing.s16),
        AppSelect<TenantStockMovementSource?>(
          key: const ValueKey('stock-movements-feed-filter'),
          value: page.source,
          label: 'Show',
          dense: true,
          leading: Icons.filter_list,
          items: <AppSelectItem<TenantStockMovementSource?>>[
            const AppSelectItem<TenantStockMovementSource?>(
              value: null,
              label: 'All movements',
            ),
            // `other` carries no wire value, so it is deliberately absent: an
            // unmodelled source cannot be filtered for and is only ever reached
            // through the unnarrowed page above.
            for (final source in TenantStockMovementSource.values)
              if (source != TenantStockMovementSource.other)
                AppSelectItem<TenantStockMovementSource?>(
                  value: source,
                  label: source.label,
                ),
          ],
          onChanged: onSelectSource,
        ),
        SizedBox(height: tokens.spacing.s16),
        // §4.3's responsive contract. This is the one movement surface whose
        // records are about *different* products, so the product is the record's
        // second identifying line - §5.2's identity row admits "an address, a
        // code, a category" - and opening its ledger is an action rather than a
        // link on that line.
        RecordList(
          identityLabel: 'Movement',
          items: <RecordItem>[
            for (final movement in page.items) _record(context, movement),
          ],
          empty: Text(
            key: const ValueKey('stock-movements-feed-empty'),
            page.isSourceScoped
                ? 'No "${page.source!.label}" entry has been recorded for this '
                      'business.'
                : 'No stock movement has been recorded for this business.',
          ),
        ),
      ],
    );
  }

  /// One movement as §5.2's rows.
  ///
  /// One movement ID is unique only below its own product - a sale of two items
  /// writes `sale_{saleId}` under each - so a row is identified by both.
  ///
  /// **The product ID and the control that opens its ledger are now two things
  /// with two keys**, where they used to be one widget that changed type. The
  /// ID is the record's second identifying line and is stated whether or not
  /// the route was injected; the ledger is a `RecordAction`, offered only when
  /// it was. That is §5.2's "never bare text links" and its 48dp target in one
  /// move - the control was an `AppButtonSize.sm` pill wearing the fact as its
  /// label - and it is the same two-owners-of-one-prefix mistake the catalog
  /// chunk found, made deliberately visible here rather than repeated.
  ///
  /// Opening the ledger from this row is the one entry point that survives the
  /// product being deleted, which the catalog route cannot be: that one needs a
  /// decoded product the catalog no longer lists.
  RecordItem _record(BuildContext context, TenantStockMovement movement) {
    final rowKey = '${movement.productId}-${movement.id}';
    return stockMovementRecord(
      movement,
      keyPrefix: 'stock-movements-feed',
      rowKey: rowKey,
      names: view.names,
      selfUid: selfUid,
      subtitle: 'Product ${movement.productId}',
      subtitleKey: ValueKey<String>('stock-movements-feed-product-$rowKey'),
      actions: <RecordAction>[
        if (productLedgerRoute != null)
          RecordAction(
            label: 'Open ledger',
            actionKey: ValueKey<String>('stock-movements-feed-ledger-$rowKey'),
            icon: Icons.receipt_long_outlined,
            onPressed: () => _openLedger(context, movement.productId),
          ),
      ],
    );
  }

  /// Opens the ledger under the same session scope this route runs in, so a
  /// tenant switch invalidates it exactly as it does every other guarded route
  /// rather than leaving a detached screen behind.
  void _openLedger(BuildContext context, String productId) {
    final controller = TenantSessionScope.of(context);
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: controller,
          child: productLedgerRoute!(productId),
        ),
      ),
    );
  }
}
