import 'package:flutter/material.dart';

import '../ui/pagination.dart';
import '../ui/record_list.dart';
import '../ui/scaffold.dart';
import '../ui/tokens.dart';
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
    contentWidth: AppContentWidth.records,
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
      final ledger =
          await TenantProductStockRepository(
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
    final guardKey = '${widget.productId}:$_pageIndex:${_cursors[_pageIndex]}';
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
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      key: const ValueKey('product-ledger'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      children: [
        // **The one of the fourteen §7 sites that stays, and it is not a
        // duplicate.** The `AppScaffold` title is `Product stock ledger` and this
        // is the product's name, so the two say different things — it is a
        // `PageHeader.subtitle` candidate rather than a deletion. It cannot move
        // there: the subtitle is built by `TenantProductLedgerScreen`, which is
        // constructed with a `productId` and nothing else, and the name only
        // exists after the guarded load inside this panel. Reaching it means
        // either an optional decoded product on the screen — which its callers,
        // the movement feed included, do not all hold — or hoisting the load out
        // of the guard. Both are structure rather than a title fix. Recorded in
        // `PLAN.md`.
        Text(
          ledger.product?.name ?? 'Deleted product',
          key: const ValueKey('product-ledger-title'),
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s4),
        Text(
          key: const ValueKey('product-ledger-identity'),
          'Product ${ledger.productId}',
        ),
        SizedBox(height: tokens.spacing.s8),
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
        SizedBox(height: tokens.spacing.s8),
        const Text(
          'The ledger is permanent and cannot be edited from this app. It is '
          'listed by record ID, which is not time order; each entry states when '
          'it was recorded.',
        ),
        SizedBox(height: tokens.spacing.s16),
        // §4.3's responsive contract. Every entry is stated in the shared record
        // vocabulary, so this surface and the business-wide feed cannot describe
        // the same document differently - which is what `stock_movement_labels`
        // has existed for since before it held a record model.
        RecordList(
          identityLabel: 'Movement',
          items: <RecordItem>[
            for (final movement in ledger.movements.items)
              stockMovementRecord(
                movement,
                keyPrefix: 'product-ledger',
                rowKey: movement.id,
                names: view.names,
                selfUid: selfUid,
              ),
          ],
          empty: const Text(
            key: ValueKey('product-ledger-empty'),
            'No stock movement has been recorded against this product.',
          ),
        ),
        SizedBox(height: tokens.spacing.s16),
        Pagination(
          pageNumber: pageIndex + 1,
          previousKey: const ValueKey('product-ledger-previous'),
          nextKey: const ValueKey('product-ledger-next'),
          onPrevious: pageIndex > 0 ? onPreviousPage : null,
          onNext: ledger.movements.hasMore ? onNextPage : null,
        ),
      ],
    );
  }
}
