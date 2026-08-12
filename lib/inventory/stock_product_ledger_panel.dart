import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/scaffold.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_staff_names.dart';
import 'stock_movement_labels.dart';
import 'stock_movements.dart';

/// Read-only route listing everything recorded against one product.
///
/// Reached from a row of the business-wide movement feed, which holds a product
/// **ID** and not a decoded catalog record - so unlike
/// `TenantProductStockScreen` this route neither needs the product to exist nor
/// offers any way to correct it.
final class TenantProductLedgerScreen extends StatelessWidget {
  const TenantProductLedgerScreen({
    super.key,
    required this.reader,
    required this.productId,
  });

  final TenantDataReader reader;
  final String productId;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Product stock ledger',
    body: TenantProductLedgerPanel(reader: reader, productId: productId),
  );
}

/// One guarded ledger page with the staff names its rows need.
final class _LedgerView {
  const _LedgerView({required this.ledger, required this.names});

  final TenantProductLedger ledger;
  final Map<String, String> names;
}

/// Pages one product's `stock_movements` behind [TenantRouteGuard].
///
/// This is deliberately the path-bounded page rather than a `productId`-
/// narrowed collection group. Both would return exactly the same documents in
/// exactly the same order to exactly the same roles; the group version would
/// additionally need a composite index and would use the one read in this app
/// that Firestore does not bound by a path prefix, to fetch rows that a bounded
/// read already returns. The decision is recorded in PLAN.md so it is not
/// reopened.
final class TenantProductLedgerPanel extends StatefulWidget {
  const TenantProductLedgerPanel({
    super.key,
    required this.reader,
    required this.productId,
    this.pageSize = 20,
  });

  final TenantDataReader reader;
  final String productId;
  final int pageSize;

  @override
  State<TenantProductLedgerPanel> createState() =>
      _TenantProductLedgerPanelState();
}

final class _TenantProductLedgerPanelState
    extends State<TenantProductLedgerPanel> {
  List<String?> _cursors = <String?>[null];
  int _pageIndex = 0;
  TenantStaffNameResolver? _staffNames;
  String? _staffNamesSessionKey;
  String? _loaderKey;
  TenantGuardedLoader<_LedgerView>? _loader;

  @override
  void didUpdateWidget(covariant TenantProductLedgerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A cursor is a position inside one product's ledger, so it can never be
    // carried into another product's.
    if (oldWidget.productId != widget.productId) {
      setState(() {
        _cursors = <String?>[null];
        _pageIndex = 0;
      });
    }
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

  TenantGuardedLoader<_LedgerView> _loaderFor(String key) {
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    final cursor = _cursors[_pageIndex];
    return _loader = (session) async {
      final ledger = await TenantProductStockRepository(
        session: session,
        reader: widget.reader,
      ).loadLedger(
        productId: widget.productId,
        pageSize: widget.pageSize,
        cursor: cursor,
      );
      // A sale movement records no actor: nightly reconciliation writes it.
      return _LedgerView(
        ledger: ledger,
        names: await _resolverFor(session).resolve(<String>[
          for (final movement in ledger.movements.items)
            if (movement.actorUid case final actorUid?) actorUid,
        ]),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final guardKey =
        '${widget.productId}:$_pageIndex:${_cursors[_pageIndex]}';
    return TenantRouteGuard<_LedgerView>(
      key: ValueKey(guardKey),
      allowedRoles: TenantProductStockRepository.allowedRoles,
      load: _loaderFor(guardKey),
      denied: const Center(
        key: ValueKey('product-ledger-denied'),
        child: Text('This product ledger is unavailable for this business.'),
      ),
      failure: (context, error) => const Center(
        key: ValueKey('product-ledger-failure'),
        child: Text('The recorded stock movements could not be loaded.'),
      ),
      builder: (context, session, view) => _LedgerContents(
        view: view,
        selfUid: session.uid,
        pageIndex: _pageIndex,
        onNextPage: () => _nextPage(view.ledger.movements.nextCursor),
        onPreviousPage: _previousPage,
      ),
    );
  }
}

final class _LedgerContents extends StatelessWidget {
  const _LedgerContents({
    required this.view,
    required this.selfUid,
    required this.pageIndex,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final _LedgerView view;
  final String selfUid;
  final int pageIndex;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  TenantProductLedger get ledger => view.ledger;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('product-ledger'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        ledger.product?.name ?? 'Deleted product',
        key: const ValueKey('product-ledger-title'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text(
        key: const ValueKey('product-ledger-identity'),
        'Product ${ledger.productId}',
      ),
      const SizedBox(height: 8),
      if (ledger.product case final product?)
        Text(
          key: const ValueKey('product-ledger-quantity'),
          'Recorded stock: ${product.quantity}',
        )
      else
        // The ledger is `write: if false` and Firestore does not cascade a
        // delete into a subcollection, so it outlives the product it belongs
        // to. Saying nothing here would present a permanent record as if it
        // described something still on the shelf.
        const Text(
          key: ValueKey('product-ledger-product-deleted'),
          'This product no longer exists in the catalog. Its ledger is kept '
          'permanently and is listed below; nothing here can be corrected, '
          'because there is no product left to correct.',
        ),
      const SizedBox(height: 8),
      const Text(
        'The ledger is permanent and cannot be edited from this app. It is '
        'listed by record ID, which is not time order; each entry states when '
        'it was recorded.',
      ),
      const SizedBox(height: 16),
      if (ledger.movements.items.isEmpty)
        const Text(
          key: ValueKey('product-ledger-empty'),
          'No stock movement has been recorded against this product.',
        )
      else
        for (final movement in ledger.movements.items)
          _entry(context, movement),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        children: [
          if (pageIndex > 0)
            AppButton(
              key: const ValueKey('product-ledger-previous'),
              label: 'Previous page',
              onPressed: onPreviousPage,
            ),
          if (ledger.movements.hasMore)
            AppButton(
              key: const ValueKey('product-ledger-next'),
              label: 'Next page',
              onPressed: onNextPage,
            ),
        ],
      ),
    ],
  );

  /// Every label here is the shared one, so this surface and the business-wide
  /// feed cannot describe the same document differently.
  Widget _entry(BuildContext context, TenantStockMovement movement) => Card(
    key: ValueKey('product-ledger-entry-${movement.id}'),
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
                  key: ValueKey('product-ledger-delta-${movement.id}'),
                  '${movement.increasesStock ? '+' : ''}'
                  '${movement.quantityDelta} • '
                  '${stockMovementSourceLabel(movement)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            key: ValueKey('product-ledger-figures-${movement.id}'),
            stockMovementFiguresLabel(movement),
          ),
          if (stockMovementDetailLabel(movement) case final detail?)
            Text(
              key: ValueKey('product-ledger-detail-${movement.id}'),
              detail,
            ),
          Text(
            key: ValueKey('product-ledger-recorded-${movement.id}'),
            stockMovementRecordedLabel(
              movement,
              stockMovementActorLabel(
                movement,
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
