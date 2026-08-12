import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/routes.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import '../tenancy/tenant_staff_names.dart';
import 'stock_adjustment_feed.dart';

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        product == null ? 'Stock adjustments' : 'Adjustments: ${product!.name}',
      ),
    ),
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
      if (page.items.isEmpty)
        Text(
          key: const ValueKey('stock-adjustments-empty'),
          page.isProductScoped
              ? 'No manual adjustment has been recorded for this product.'
              : 'No manual adjustment has been recorded in this business.',
        )
      else
        for (final record in page.items) _entry(context, record),
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

  Widget _entry(BuildContext context, TenantStockAdjustmentRecord record) =>
      Card(
        key: ValueKey('stock-adjustments-entry-${record.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    record.increasesStock
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    key: ValueKey('stock-adjustments-delta-${record.id}'),
                    '${record.increasesStock ? '+' : ''}'
                    '${record.quantityDelta} • ${_typeLabel(record)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                key: ValueKey('stock-adjustments-product-${record.id}'),
                'Product ${record.productId}',
              ),
              Text(
                key: ValueKey('stock-adjustments-figures-${record.id}'),
                '${record.previousQuantity} to ${record.quantityAfter}',
              ),
              Text(
                key: ValueKey('stock-adjustments-reason-${record.id}'),
                'Reason: ${record.reason}',
              ),
              Text(
                key: ValueKey('stock-adjustments-recorded-${record.id}'),
                _recordedLabel(
                  record,
                  tenantStaffLabel(
                    record.actorUid,
                    names: view.names,
                    selfUid: selfUid,
                  ),
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}

/// An unmodelled category is shown as itself: a server deploy adding one is not
/// evidence of anything wrong, and hiding the row would hide a real correction.
String _typeLabel(TenantStockAdjustmentRecord record) =>
    record.type?.label ?? record.adjustmentType;

String _recordedLabel(TenantStockAdjustmentRecord record, String actorLabel) {
  final recordedAt = record.recordedAt;
  final when = recordedAt == null
      ? 'Recorded instant unavailable'
      : 'Recorded ${_instant(recordedAt)}';
  return '$when by $actorLabel';
}

String _instant(DateTime value) {
  final utc = value.toUtc();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} '
      '${pad(utc.hour)}:${pad(utc.minute)} UTC';
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
