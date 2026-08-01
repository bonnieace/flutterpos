import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_names.dart';
import 'stock_movement_feed.dart';
import 'stock_movements.dart';

/// Read-only route listing everything that moved this business's stock.
final class TenantStockMovementFeedScreen extends StatelessWidget {
  const TenantStockMovementFeedScreen({
    super.key,
    required this.reader,
    required this.groupReader,
    this.source,
  });

  /// Only staff labels are read by path here; this surface issues no
  /// single-collection page at all.
  final TenantDocumentReader reader;

  /// The collection-group boundary is injected separately from every
  /// path-bounded read, because it is a genuinely wider one.
  final TenantCollectionGroupReader groupReader;

  /// When present, the feed opens narrowed to exactly this source.
  final TenantStockMovementSource? source;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stock movements')),
    body: TenantStockMovementFeedPanel(
      reader: reader,
      groupReader: groupReader,
      source: source,
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
    this.pageSize = 20,
  });

  /// Only staff labels are read by path here; this surface issues no
  /// single-collection page at all.
  final TenantDocumentReader reader;
  final TenantCollectionGroupReader groupReader;
  final TenantStockMovementSource? source;
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
  TenantStaffNameResolver? _staffNames;
  String? _staffNamesSessionKey;
  String? _loaderKey;
  TenantGuardedLoader<_MovementFeedView>? _loader;

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
  TenantGuardedLoader<_MovementFeedView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final source = _source;
    final cursor = _cursors[_pageIndex];
    return _loader = (session) async {
      final repository = TenantStockMovementFeedRepository(
        session: session,
        reader: widget.reader,
        groupReader: widget.groupReader,
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
        names: await _resolverFor(session).resolve(<String>[
          for (final movement in page.items)
            if (movement.actorUid case final actorUid?) actorUid,
        ]),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursors[_pageIndex];
    final guardKey = '${_source?.wireValue}:$_pageIndex:$cursor';
    return TenantRouteGuard<_MovementFeedView>(
      key: ValueKey(guardKey),
      allowedRoles: TenantStockMovementFeedRepository.allowedRoles,
      load: _loaderFor(guardKey),
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
  });

  final _MovementFeedView view;
  final String selfUid;
  final int pageIndex;
  final ValueChanged<TenantStockMovementSource?> onSelectSource;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  TenantStockMovementFeedPage get page => view.page;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('stock-movements-feed'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Recorded stock movements',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text(
        key: const ValueKey('stock-movements-feed-scope'),
        page.isSourceScoped
            ? 'Every "${page.source!.label}" entry recorded against this '
                  'business\'s products. Other movements are not listed on '
                  'this page.'
            : 'Every entry recorded against this business\'s products: sales, '
                  'verified returns, and manual corrections alike.',
      ),
      const SizedBox(height: 4),
      const Text(
        'The ledger is permanent and cannot be edited from this app. It is '
        'listed by product and then by record ID, which is not time order; '
        'each entry states when it was recorded.',
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<TenantStockMovementSource?>(
        key: const ValueKey('stock-movements-feed-filter'),
        initialValue: page.source,
        decoration: const InputDecoration(
          labelText: 'Show',
          border: OutlineInputBorder(),
        ),
        items: <DropdownMenuItem<TenantStockMovementSource?>>[
          const DropdownMenuItem<TenantStockMovementSource?>(
            value: null,
            child: Text('All movements'),
          ),
          // `other` carries no wire value, so it is deliberately absent: an
          // unmodelled source cannot be filtered for and is only ever reached
          // through the unnarrowed page above.
          for (final source in TenantStockMovementSource.values)
            if (source != TenantStockMovementSource.other)
              DropdownMenuItem<TenantStockMovementSource?>(
                value: source,
                child: Text(source.label),
              ),
        ],
        onChanged: onSelectSource,
      ),
      const SizedBox(height: 16),
      if (page.items.isEmpty)
        Text(
          key: const ValueKey('stock-movements-feed-empty'),
          page.isSourceScoped
              ? 'No "${page.source!.label}" entry has been recorded for this '
                    'business.'
              : 'No stock movement has been recorded for this business.',
        )
      else
        for (final movement in page.items) _entry(context, movement),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            OutlinedButton(
              key: const ValueKey('stock-movements-feed-previous'),
              onPressed: onPreviousPage,
              child: const Text('Previous page'),
            ),
          if (page.hasMore)
            FilledButton(
              key: const ValueKey('stock-movements-feed-next'),
              onPressed: onNextPage,
              child: const Text('Next page'),
            ),
        ],
      ),
    ],
  );

  /// One movement ID is unique only below its own product - a sale of two items
  /// writes `sale_{saleId}` under each - so a row is identified by both.
  Widget _entry(BuildContext context, TenantStockMovement movement) {
    final rowKey = '${movement.productId}-${movement.id}';
    return Card(
      key: ValueKey('stock-movements-feed-entry-$rowKey'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  movement.increasesStock
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    key: ValueKey('stock-movements-feed-delta-$rowKey'),
                    '${movement.increasesStock ? '+' : ''}'
                    '${movement.quantityDelta} • ${_sourceLabel(movement)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              key: ValueKey('stock-movements-feed-product-$rowKey'),
              'Product ${movement.productId}',
            ),
            Text(
              key: ValueKey('stock-movements-feed-figures-$rowKey'),
              _figuresLabel(movement),
            ),
            if (_detailLabel(movement) case final detail?)
              Text(
                key: ValueKey('stock-movements-feed-detail-$rowKey'),
                detail,
              ),
            Text(
              key: ValueKey('stock-movements-feed-recorded-$rowKey'),
              _recordedLabel(movement, _actorLabel(movement)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  /// Nightly reconciliation writes a sale's movement, so it names no member of
  /// the business. Attributing it to a missing colleague would be a fiction.
  String _actorLabel(TenantStockMovement movement) {
    final actorUid = movement.actorUid;
    if (actorUid == null) return 'the server';
    return tenantStaffLabel(actorUid, names: view.names, selfUid: selfUid);
  }
}

/// An unmodelled source is shown as itself: a server deploy adding one is not
/// evidence of anything wrong, and hiding the row would hide a real movement.
String _sourceLabel(TenantStockMovement movement) =>
    movement.source == TenantStockMovementSource.other
    ? movement.sourceType
    : movement.source.label;

/// Only the writers that read the product inside their own transaction record a
/// before and after. A reconciled sale carries neither, which this names rather
/// than filling in with a figure nobody recorded.
String _figuresLabel(TenantStockMovement movement) {
  final previousQuantity = movement.previousQuantity;
  if (previousQuantity == null) return 'Before and after were not recorded';
  return '$previousQuantity to ${movement.quantityAfter}';
}

String? _detailLabel(TenantStockMovement movement) {
  if (movement.reason case final reason?) return 'Reason: $reason';
  if (movement.sourceId case final sourceId?) return 'From $sourceId';
  return null;
}

String _recordedLabel(TenantStockMovement movement, String actorLabel) {
  final recordedAt = movement.recordedAt ?? movement.occurredAt;
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
