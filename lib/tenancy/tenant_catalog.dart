import 'package:flutter/material.dart';

import 'tenant_id.dart';
import 'tenant_paths.dart';
import 'tenant_repository.dart';
import 'tenant_route_guard.dart';
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
  TenantProduct.fromSnapshot(TenantQueryDocumentSnapshot snapshot)
    : id = _documentId(snapshot.path, TenantCollection.products),
      name = _requiredTrimmedString(snapshot.data, 'name'),
      sku = _requiredTrimmedString(snapshot.data, 'SKU'),
      price = _nonNegativeFiniteNumber(snapshot.data, 'price'),
      quantity = _signedSafeInteger(snapshot.data, 'quantity'),
      categoryId = _categoryId(snapshot.data),
      imageUrl = _optionalHttpsUrl(snapshot.data, 'image');

  final String id;
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

/// Temporary read-only route; all product and stock actions remain absent.
final class TenantCatalogScreen extends StatelessWidget {
  const TenantCatalogScreen({
    super.key,
    required this.reader,
    this.allowedRoles,
  });

  final TenantDataReader reader;
  final Iterable<TenantRole>? allowedRoles;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Product catalog')),
    body: TenantCatalogPanel(reader: reader, allowedRoles: allowedRoles),
  );
}

/// Guarded catalog content, split out to keep access behavior widget-testable.
final class TenantCatalogPanel extends StatelessWidget {
  const TenantCatalogPanel({
    super.key,
    required this.reader,
    this.allowedRoles,
  });

  final TenantDataReader reader;
  final Iterable<TenantRole>? allowedRoles;

  @override
  Widget build(BuildContext context) => TenantRouteGuard<TenantCatalogSnapshot>(
    allowedRoles: allowedRoles,
    load: (session) =>
        TenantCatalogRepository(session: session, reader: reader).loadInitial(),
    builder: (context, session, snapshot) =>
        _CatalogContents(tenantId: session.tenantId, snapshot: snapshot),
  );
}

final class _CatalogContents extends StatelessWidget {
  const _CatalogContents({required this.tenantId, required this.snapshot});

  final String tenantId;
  final TenantCatalogSnapshot snapshot;

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
                title: Text(product.name),
                subtitle: Text(
                  '${categoryNames[product.categoryId] ?? product.categoryId} '
                  '• SKU ${product.sku} • Stock ${product.quantity}',
                ),
                trailing: Text(product.price.toStringAsFixed(2)),
              ),
            ),
        if (snapshot.products.hasMore)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('More products are available.'),
          ),
        const SizedBox(height: 12),
        const Text(
          'Catalog changes, stock actions, checkout, returns, and reports '
          'remain unavailable.',
        ),
      ],
    );
  }
}

String _documentId(String path, TenantCollection collection) {
  final segments = path.split('/');
  if (segments.length != 4 || segments[0] != 'tenants') {
    throw FormatException('Invalid ${collection.segment} document path.');
  }
  validateTenantId(segments[1]);
  if (segments[2] != collection.segment) {
    throw FormatException('Invalid ${collection.segment} document path.');
  }
  return validateTenantDocumentId(segments[3]);
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
