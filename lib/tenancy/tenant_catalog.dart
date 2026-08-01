import 'package:flutter/material.dart';

import 'tenant_id.dart';
import 'tenant_paths.dart';
import 'tenant_repository.dart';
import 'tenant_route_guard.dart';
import 'tenant_session_controller.dart';
import 'tenant_types.dart';

const int _maximumSafeInteger = 9007199254740991;

/// Strict read model for `tenants/{tenantId}/categories/{categoryId}`.
final class TenantCategory {
  TenantCategory.fromSnapshot(TenantQueryDocumentSnapshot snapshot)
    : id = _documentId(snapshot.path, TenantCollection.categories),
      name = _requiredTrimmedString(snapshot.data, 'name');

  final String id;
  final String name;
}

/// Strict read model for `tenants/{tenantId}/products/{productId}`.
///
/// New documents use `categoryId`. The legacy `category` alias is accepted
/// only while migration is in progress and must agree when both are present.
final class TenantProduct {
  factory TenantProduct.fromSnapshot(TenantQueryDocumentSnapshot snapshot) =>
      TenantProduct.fromDocument(path: snapshot.path, data: snapshot.data);

  /// Decodes one product read by its exact canonical path.
  ///
  /// A stock surface re-reads the product document rather than carrying a
  /// figure between screens, so the quantity it states is always the one the
  /// server most recently recorded.
  TenantProduct.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) : id = _documentId(path, TenantCollection.products),
       tenantId = _pathTenantId(path, TenantCollection.products),
       name = _requiredTrimmedString(data, 'name'),
       sku = _requiredTrimmedString(data, 'SKU'),
       price = _nonNegativeFiniteNumber(data, 'price'),
       quantity = _signedSafeInteger(data, 'quantity'),
       categoryId = _categoryId(data),
       imageUrl = _optionalHttpsUrl(data, 'image');

  final String id;

  /// The business this exact document path belongs to. A mutation gateway
  /// compares it against its own session, so a product decoded from one
  /// business can never be adjusted while another is open.
  final String tenantId;

  final String name;
  final String sku;
  final double price;
  final int quantity;
  final String categoryId;
  final Uri? imageUrl;
}

/// One typed catalog page with a document-ID cursor.
final class TenantCatalogPage<T> {
  TenantCatalogPage({
    required List<T> items,
    required this.nextCursor,
    required this.hasMore,
  }) : items = List<T>.unmodifiable(items);

  final List<T> items;
  final String? nextCursor;
  final bool hasMore;
}

/// The bounded data initially rendered by the temporary catalog route.
final class TenantCatalogSnapshot {
  const TenantCatalogSnapshot({
    required this.categories,
    required this.products,
  });

  final TenantCatalogPage<TenantCategory> categories;
  final TenantCatalogPage<TenantProduct> products;
}

/// Read-only product/category repository bound to one canonical session.
final class TenantCatalogRepository extends TenantReadRepository {
  TenantCatalogRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;

  Future<TenantCatalogPage<TenantCategory>> loadCategories({
    int pageSize = 20,
    String? cursor,
  }) async {
    final page = await readCollectionPage(
      TenantCollection.categories,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
    );
    return TenantCatalogPage<TenantCategory>(
      items: page.items.map(TenantCategory.fromSnapshot).toList(),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  Future<TenantCatalogPage<TenantProduct>> loadProducts({
    int pageSize = 20,
    String? cursor,
  }) async {
    final page = await readCollectionPage(
      TenantCollection.products,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
    );
    return TenantCatalogPage<TenantProduct>(
      items: page.items.map(TenantProduct.fromSnapshot).toList(),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  Future<TenantCatalogSnapshot> loadInitial() async {
    final pages = await Future.wait<Object>([
      loadCategories(pageSize: 50),
      loadProducts(),
    ]);
    return TenantCatalogSnapshot(
      categories: pages[0] as TenantCatalogPage<TenantCategory>,
      products: pages[1] as TenantCatalogPage<TenantProduct>,
    );
  }
}

/// Builds the per-product stock route for one already-decoded product.
///
/// The composition root supplies it; the catalog only passes the product it
/// already proved. While it is absent the route stays unreachable and the
/// catalog is exactly the read-only surface it was before.
typedef TenantProductRouteBuilder = Widget Function(TenantProduct product);

/// Builds the business-wide stock adjustment feed route.
///
/// It is supplied by the composition root for the same reason: while it is
/// absent the route stays unreachable and the catalog is exactly the read-only
/// surface it was before.
typedef TenantAdjustmentFeedRouteBuilder = Widget Function();

/// Builds the business-wide stock movement feed route, injected for the same
/// reason as its sibling above.
typedef TenantMovementFeedRouteBuilder = Widget Function();

/// Read-only catalog route. Catalog editing remains absent; the only reachable
/// actions are the guarded per-product stock route and the two business-wide
/// stock feeds, each when one is supplied.
final class TenantCatalogScreen extends StatelessWidget {
  const TenantCatalogScreen({
    super.key,
    required this.reader,
    this.allowedRoles,
    this.productStockRoute,
    this.productStockRoles = const <TenantRole>[],
    this.adjustmentFeedRoute,
    this.adjustmentFeedRoles = const <TenantRole>[],
    this.movementFeedRoute,
    this.movementFeedRoles = const <TenantRole>[],
  });

  final TenantDataReader reader;
  final Iterable<TenantRole>? allowedRoles;
  final TenantProductRouteBuilder? productStockRoute;

  /// The roles that route is offered to, decided by the inventory domain.
  final List<TenantRole> productStockRoles;

  final TenantAdjustmentFeedRouteBuilder? adjustmentFeedRoute;

  /// The roles the feed is offered to, decided by the inventory domain.
  final List<TenantRole> adjustmentFeedRoles;

  final TenantMovementFeedRouteBuilder? movementFeedRoute;

  /// The roles the feed is offered to, decided by the inventory domain.
  final List<TenantRole> movementFeedRoles;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Product catalog')),
    body: TenantCatalogPanel(
      reader: reader,
      allowedRoles: allowedRoles,
      productStockRoute: productStockRoute,
      productStockRoles: productStockRoles,
      adjustmentFeedRoute: adjustmentFeedRoute,
      adjustmentFeedRoles: adjustmentFeedRoles,
      movementFeedRoute: movementFeedRoute,
      movementFeedRoles: movementFeedRoles,
    ),
  );
}

/// Guarded catalog content, split out to keep access behavior widget-testable.
final class TenantCatalogPanel extends StatelessWidget {
  const TenantCatalogPanel({
    super.key,
    required this.reader,
    this.allowedRoles,
    this.productStockRoute,
    this.productStockRoles = const <TenantRole>[],
    this.adjustmentFeedRoute,
    this.adjustmentFeedRoles = const <TenantRole>[],
    this.movementFeedRoute,
    this.movementFeedRoles = const <TenantRole>[],
  });

  final TenantDataReader reader;
  final Iterable<TenantRole>? allowedRoles;
  final TenantProductRouteBuilder? productStockRoute;
  final List<TenantRole> productStockRoles;
  final TenantAdjustmentFeedRouteBuilder? adjustmentFeedRoute;
  final List<TenantRole> adjustmentFeedRoles;
  final TenantMovementFeedRouteBuilder? movementFeedRoute;
  final List<TenantRole> movementFeedRoles;

  @override
  Widget build(BuildContext context) => TenantRouteGuard<TenantCatalogSnapshot>(
    allowedRoles: allowedRoles,
    load: (session) =>
        TenantCatalogRepository(session: session, reader: reader).loadInitial(),
    builder: (context, session, snapshot) => _CatalogContents(
      tenantId: session.tenantId,
      snapshot: snapshot,
      // The role is taken from the guarded session, never from the caller, so
      // the action disappears the moment the session stops allowing it.
      productStockRoute: session.canAccess(allowedRoles: productStockRoles)
          ? productStockRoute
          : null,
      adjustmentFeedRoute: session.canAccess(allowedRoles: adjustmentFeedRoles)
          ? adjustmentFeedRoute
          : null,
      movementFeedRoute: session.canAccess(allowedRoles: movementFeedRoles)
          ? movementFeedRoute
          : null,
    ),
  );
}

final class _CatalogContents extends StatelessWidget {
  const _CatalogContents({
    required this.tenantId,
    required this.snapshot,
    this.productStockRoute,
    this.adjustmentFeedRoute,
    this.movementFeedRoute,
  });

  final String tenantId;
  final TenantCatalogSnapshot snapshot;
  final TenantProductRouteBuilder? productStockRoute;
  final TenantAdjustmentFeedRouteBuilder? adjustmentFeedRoute;
  final TenantMovementFeedRouteBuilder? movementFeedRoute;

  @override
  Widget build(BuildContext context) {
    final categoryNames = <String, String>{
      for (final category in snapshot.categories.items)
        category.id: category.name,
    };
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Read-only catalog',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text('Business: $tenantId'),
        if (adjustmentFeedRoute != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('catalog-adjustment-feed'),
            onPressed: () => _openAdjustmentFeed(context),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('View recorded stock adjustments'),
          ),
        ],
        if (movementFeedRoute != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('catalog-movement-feed'),
            onPressed: () => _openMovementFeed(context),
            icon: const Icon(Icons.swap_vert_outlined),
            label: const Text('View every recorded stock movement'),
          ),
        ],
        const SizedBox(height: 20),
        Text('Categories', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (snapshot.categories.items.isEmpty)
          const Text('No categories found.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in snapshot.categories.items)
                Chip(label: Text(category.name)),
            ],
          ),
        if (snapshot.categories.hasMore)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('More categories are available.'),
          ),
        const SizedBox(height: 24),
        Text('Products', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (snapshot.products.items.isEmpty)
          const Text('No products found.')
        else
          for (final product in snapshot.products.items)
            Card(
              child: ListTile(
                key: ValueKey('catalog-product-${product.id}'),
                title: Text(product.name),
                subtitle: Text(
                  '${categoryNames[product.categoryId] ?? product.categoryId} '
                  '• SKU ${product.sku} • Stock ${product.quantity}',
                ),
                trailing: Text(product.price.toStringAsFixed(2)),
                onTap: productStockRoute == null
                    ? null
                    : () => _openStockRoute(context, product),
              ),
            ),
        if (snapshot.products.hasMore)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('More products are available.'),
          ),
        const SizedBox(height: 12),
        Text(
          productStockRoute == null
              ? 'Catalog changes, stock actions, checkout, returns, and '
                    'reports remain unavailable.'
              : 'Catalog changes, checkout, returns, and reports remain '
                    'unavailable. Open a product to see and correct its stock.',
        ),
      ],
    );
  }

  /// Opens the stock route under the same session scope this route runs in, so
  /// a tenant switch invalidates it exactly as it does every other guarded
  /// route rather than leaving a detached screen behind.
  void _openStockRoute(BuildContext context, TenantProduct product) {
    final controller = TenantSessionScope.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: controller,
          child: productStockRoute!(product),
        ),
      ),
    );
  }

  /// Opens the business-wide correction feed under the same session scope, for
  /// the same reason the per-product route does.
  void _openAdjustmentFeed(BuildContext context) {
    final controller = TenantSessionScope.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: controller,
          child: adjustmentFeedRoute!(),
        ),
      ),
    );
  }

  /// Opens the business-wide movement feed, which lists every entry the
  /// corrections above are only one source of, under the same session scope.
  void _openMovementFeed(BuildContext context) {
    final controller = TenantSessionScope.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TenantSessionScope(
          controller: controller,
          child: movementFeedRoute!(),
        ),
      ),
    );
  }
}

String _documentId(String path, TenantCollection collection) =>
    validateTenantDocumentId(_pathSegments(path, collection)[3]);

String _pathTenantId(String path, TenantCollection collection) =>
    _pathSegments(path, collection)[1];

List<String> _pathSegments(String path, TenantCollection collection) {
  final segments = path.split('/');
  if (segments.length != 4 ||
      segments[0] != 'tenants' ||
      segments[2] != collection.segment) {
    throw FormatException('Invalid ${collection.segment} document path.');
  }
  validateTenantId(segments[1]);
  return segments;
}

String _requiredTrimmedString(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw FormatException('$field must be a non-empty trimmed string.');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw FormatException('$field cannot contain control characters.');
    }
  }
  return value;
}

double _nonNegativeFiniteNumber(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('$field must be a finite non-negative number.');
  }
  return value.toDouble();
}

int _signedSafeInteger(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! int ||
      value < -_maximumSafeInteger ||
      value > _maximumSafeInteger) {
    throw FormatException('$field must be a signed safe integer.');
  }
  return value;
}

String _categoryId(Map<String, Object?> map) {
  final current = map['categoryId'];
  final legacy = map['category'];
  if (current == null && legacy == null) {
    throw const FormatException('categoryId is required.');
  }
  String validate(Object? value, String field) {
    if (value is! String) {
      throw FormatException('$field must be a category document ID.');
    }
    try {
      return validateTenantDocumentId(value, fieldName: field);
    } on ArgumentError {
      throw FormatException('$field must be a category document ID.');
    }
  }

  final resolved = current == null
      ? validate(legacy, 'category')
      : validate(current, 'categoryId');
  if (legacy != null && validate(legacy, 'category') != resolved) {
    throw const FormatException(
      'category and categoryId must identify the same category.',
    );
  }
  return resolved;
}

Uri? _optionalHttpsUrl(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value == null || value == '') return null;
  if (value is! String || value != value.trim()) {
    throw FormatException('$field must be an HTTPS URL when present.');
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw FormatException('$field must be an HTTPS URL when present.');
  }
  return uri;
}
