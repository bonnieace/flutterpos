import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/record_list.dart';
import '../ui/routes.dart';
import '../ui/scaffold.dart';
import '../ui/tokens.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import 'stock_adjustment_feed.dart';
import 'stock_movement_labels.dart';

/// Read-only route listing the manual stock corrections a business recorded.
final class TenantStockAdjustmentFeedScreen extends StatelessWidget {
  const TenantStockAdjustmentFeedScreen({
    super.key,
    required this.reader,
    this.product,
  });

  final TenantDataReader reader;

  /// When present, the feed is narrowed to this already-decoded catalog record
  /// rather than to a product ID a caller named.
  final TenantProduct? product;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: product == null
        ? 'Stock adjustments'
        : 'Adjustments: ${product!.name}',
contentWidth: AppContentWidth.records,
    body: TenantStockAdjustmentFeedPanel(reader: reader, product: product),
  );
}

/// One guarded page of adjustment records with the staff names it needs.
final class _FeedView {
  const _FeedView({required this.page, required this.names});

  final TenantStockAdjustmentRecordPage page;
  final Map<String, String> names;
}

/// Pages the business-wide `stock_adjustments` record behind [TenantRouteGuard].
///
/// The guard owns authorization and stale-session rejection: a tenant switch
/// during an outstanding page discards it before it can update the UI. Nothing
/// on this surface can record, amend, or undo an adjustment.
final class TenantStockAdjustmentFeedPanel extends StatefulWidget {
  const TenantStockAdjustmentFeedPanel({
    super.key,
    required this.reader,
    this.product,
    this.pageSize = 20,
  });

  final TenantDataReader reader;
  final TenantProduct? product;
  final int pageSize;

  @override
  State<TenantStockAdjustmentFeedPanel> createState() =>
      _TenantStockAdjustmentFeedPanelState();
}

final class _TenantStockAdjustmentFeedPanelState
    extends State<TenantStockAdjustmentFeedPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  TenantStaffNameResolver? _staffNames;
  String? _staffNamesSessionKey;
  String? _loaderKey;
  TenantGuardedLoader<_FeedView>? _loader;

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
  /// the page on an unrelated `setState`.
  TenantGuardedLoader<_FeedView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final productId = widget.product?.id;
    final cursor = _cursors[_pageIndex];
    return _loader = (session) async {
      final repository = TenantStockAdjustmentFeedRepository(
        session: session,
        reader: widget.reader,
      );
      final page = productId == null
          ? await repository.loadAdjustments(
              pageSize: widget.pageSize,
              cursor: cursor,
            )
          : await repository.loadProductAdjustments(
              productId: productId,
              pageSize: widget.pageSize,
              cursor: cursor,
            );
      return _FeedView(
        page: page,
        names: await _resolverFor(
          session,
        ).resolve(page.items.map((record) => record.actorUid)),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '${widget.product?.id}:$_pageIndex:$cursor';
    return TenantRouteGuard<_FeedView>(
      key: ValueKey(guardKey),
      allowedRoles: TenantStockAdjustmentFeedRepository.allowedRoles,
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('stock-adjustments-denied'),
        child: Text('Stock adjustments are unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('stock-adjustments-failure'),
        child: Text('The recorded stock adjustments could not be loaded.'),
      ),
      builder: (context, session, view) => _AdjustmentFeedContents(
        view: view,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        onNextPage: () => _nextPage(view.page.nextCursor),
        onPreviousPage: _previousPage,
      ),
    );
  }
}

final class _AdjustmentFeedContents extends StatelessWidget {
  const _AdjustmentFeedContents({
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final _FeedView view;
  final String selfUid;
  final int pageIndex;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  TenantStockAdjustmentRecordPage get page => view.page;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('stock-adjustments'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Recorded stock adjustments',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text(
        key: const ValueKey('stock-adjustments-scope'),
        page.isProductScoped
            ? 'Every manual correction recorded against product '
                  '${page.productId}. Sales and verified returns are not '
                  'adjustments and are not listed here.'
            : 'Every manual correction recorded across this business. Sales '
                  'and verified returns move stock too, but they are not '
                  'adjustments and are not listed here.',
      ),
      const SizedBox(height: 4),
      const Text(
        'An adjustment is permanent: correcting one means recording another. '
        'This page is listed by record ID, which is not time order; each '
        'entry states when it was recorded.',
      ),
      const SizedBox(height: 16),
      // §4.3's responsive contract: stacked cards on a phone, two-column cards
      // on a tablet, and a table on a desktop window. A correction used to be a
      // `Card` of four unlabelled lines - the product, the figures, the reason
      // and the attribution - which is the shape §5.2 replaces with key-value
      // attributes and a provenance line.
      RecordList(
        identityLabel: 'Adjustment',
        items: <RecordItem>[
          for (final record in page.items)
            stockAdjustmentRecord(
              record,
              keyPrefix: 'stock-adjustments',
              names: view.names,
              selfUid: selfUid,
            ),
        ],
        empty: Text(
          key: const ValueKey('stock-adjustments-empty'),
          page.isProductScoped
              ? 'No manual adjustment has been recorded for this product.'
              : 'No manual adjustment has been recorded in this business.',
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            AppButton(
              key: const ValueKey('stock-adjustments-previous'),
              label: 'Previous page',
              onPressed: onPreviousPage,
            ),
          if (page.hasMore)
            AppButton(
              key: const ValueKey('stock-adjustments-next'),
              label: 'Next page',
              onPressed: onNextPage,
            ),
        ],
      ),
    ],
  );

}

/// Opens the feed under the caller's own session scope, so a tenant switch
/// invalidates it exactly as it does every other guarded route rather than
/// leaving a detached screen behind.
void openTenantStockAdjustmentFeed(
  BuildContext context, {
  required TenantDataReader reader,
  TenantProduct? product,
}) {
  final controller = TenantSessionScope.of(context);
  Navigator.of(context).push(
    AppPageRoute<void>(
      builder: (_) => TenantSessionScope(
        controller: controller,
        child: TenantStockAdjustmentFeedScreen(reader: reader, product: product),
      ),
    ),
  );
}
