import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('strict catalog models', () {
    test('decodes current and legacy category references without coercion', () {
      final current = TenantProduct.fromSnapshot(
        _productSnapshot('tenant-a', 'product-a'),
      );
      final legacy = TenantProduct.fromSnapshot(
        _productSnapshot(
          'tenant-a',
          'product-b',
          data: _productData()
            ..remove('categoryId')
            ..['category'] = 'drinks',
        ),
      );

      expect(current.id, 'product-a');
      expect(current.price, 120.5);
      expect(current.quantity, -2);
      expect(current.categoryId, 'drinks');
      expect(legacy.categoryId, 'drinks');
    });

    test('a product carries the business its own path names', () {
      final product = TenantProduct.fromDocument(
        path: 'tenants/tenant-a/products/product-a',
        data: _productData(),
      );

      expect(product.tenantId, 'tenant-a');
      expect(product.id, 'product-a');
      expect(
        TenantProduct.fromSnapshot(
          _productSnapshot('tenant-b', 'product-a'),
        ).tenantId,
        'tenant-b',
      );
    });

    test('rejects malformed paths, quantities, prices, and categories', () {
      expect(
        () => TenantProduct.fromSnapshot(
          TenantQueryDocumentSnapshot(
            path: 'tenants/bad/path/products/product-a',
            data: _productData(),
          ),
        ),
        throwsFormatException,
      );

      for (final invalidQuantity in <Object?>[1.5, '2', 9007199254740992]) {
        expect(
          () => TenantProduct.fromSnapshot(
            _productSnapshot(
              'tenant-a',
              'product-a',
              data: _productData()..['quantity'] = invalidQuantity,
            ),
          ),
          throwsFormatException,
        );
      }

      for (final invalidPrice in <Object?>['120.5', -1, double.nan]) {
        expect(
          () => TenantProduct.fromSnapshot(
            _productSnapshot(
              'tenant-a',
              'product-a',
              data: _productData()..['price'] = invalidPrice,
            ),
          ),
          throwsFormatException,
        );
      }

      expect(
        () => TenantProduct.fromSnapshot(
          _productSnapshot(
            'tenant-a',
            'product-a',
            data: _productData()..['categoryId'] = 'escape/path',
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => TenantProduct.fromSnapshot(
          _productSnapshot(
            'tenant-a',
            'product-a',
            data: _productData()
              ..['categoryId'] = 'drinks'
              ..['category'] = 'food',
          ),
        ),
        throwsFormatException,
      );
    });
  });

  group('tenant collection pagination', () {
    test(
      'derives the path, bounds pages, and advances a stable cursor',
      () async {
        final reader = _CatalogReader(
          handler: (query) async => [
            _productSnapshot('tenant-a', 'product-a'),
            _productSnapshot('tenant-a', 'product-b'),
            _productSnapshot('tenant-a', 'product-c'),
          ],
        );
        final repository = TenantCatalogRepository(
          session: _session('tenant-a'),
          reader: reader,
        );

        final page = await repository.loadProducts(pageSize: 2);

        expect(
          reader.queries.single.collectionPath,
          'tenants/tenant-a/products',
        );
        expect(reader.queries.single.limit, 3);
        expect(page.items.map((item) => item.id), ['product-a', 'product-b']);
        expect(page.hasMore, isTrue);
        expect(page.nextCursor, 'product-b');

        reader.handler = (query) async {
          expect(query.startAfterDocumentId, 'product-b');
          return [_productSnapshot('tenant-a', 'product-c')];
        };
        final finalPage = await repository.loadProducts(
          pageSize: 2,
          cursor: page.nextCursor,
        );
        expect(finalPage.items.single.id, 'product-c');
        expect(finalPage.hasMore, isFalse);
        expect(finalPage.nextCursor, isNull);
      },
    );

    test('rejects invalid page sizes and cross-tenant query results', () async {
      final reader = _CatalogReader(
        handler: (_) async => [_productSnapshot('tenant-b', 'product-a')],
      );
      final repository = TenantCatalogRepository(
        session: _session('tenant-a'),
        reader: reader,
      );

      await expectLater(repository.loadProducts(pageSize: 0), throwsRangeError);
      await expectLater(
        repository.loadProducts(pageSize: 51),
        throwsRangeError,
      );
      await expectLater(
        repository.loadProducts(),
        throwsA(isA<TenantScopeViolation>()),
      );
      expect(
        () => TenantSession.active(
          uid: 'user-a',
          tenantId: 'bad/tenant',
          role: TenantRole.admin,
        ),
        throwsArgumentError,
      );
    });
  });

  group('guarded catalog route', () {
    testWidgets('safe landing opens the guarded read-only route', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(uid: 'user-a', membership: _membership('tenant-a'));
      final reader = _CatalogReader(
        handler: (query) async => query.collectionPath.endsWith('/categories')
            ? [_categorySnapshot('tenant-a', 'drinks')]
            : [_productSnapshot('tenant-a', 'product-a')],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TenantSessionScope(
            controller: controller,
            child: TenantSafeLandingScreen(
              membership: _membership('tenant-a'),
              reader: reader,
              onSignOut: () async {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('View read-only catalog'));
      await tester.pumpAndSettle();

      expect(find.text('Product catalog'), findsOneWidget);
      expect(find.text('Cold lager'), findsOneWidget);
      expect(find.text('Catalog changes'), findsNothing);
      expect(find.textContaining('Catalog changes'), findsOneWidget);
      expect(find.text('Add product'), findsNothing);
    });

    testWidgets('missing and wrong-role sessions never start a query', (
      tester,
    ) async {
      final reader = _CatalogReader(handler: (_) async => const []);
      final missing = TenantSessionController();
      await tester.pumpWidget(_catalogApp(controller: missing, reader: reader));
      expect(find.text('Tenant access unavailable.'), findsOneWidget);
      expect(reader.queries, isEmpty);

      final cashier = TenantSessionController()
        ..open(
          uid: 'user-a',
          membership: _membership('tenant-a', role: TenantRole.cashier),
        );
      await tester.pumpWidget(
        _catalogApp(
          controller: cashier,
          reader: reader,
          allowedRoles: const [TenantRole.manager],
        ),
      );
      expect(find.text('Tenant access unavailable.'), findsOneWidget);
      expect(reader.queries, isEmpty);
    });

    testWidgets('the product stock route is offered only to its roles', (
      tester,
    ) async {
      final reader = _CatalogReader(
        handler: (query) async => query.collectionPath.endsWith('/categories')
            ? [_categorySnapshot('tenant-a', 'drinks')]
            : [_productSnapshot('tenant-a', 'product-a')],
      );

      // A cashier reads the catalog but never reaches the stock surface.
      await tester.pumpWidget(
        _catalogApp(
          controller: TenantSessionController()
            ..open(
              uid: 'user-a',
              membership: _membership('tenant-a', role: TenantRole.cashier),
            ),
          reader: reader,
          productStockRoute: (product) => const Text('stock route'),
          productStockRoles: const [TenantRole.manager],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Cold lager'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('catalog-product-product-a')),
            )
            .onTap,
        isNull,
      );

      // A manager opens it, under the same session scope the catalog runs in.
      await tester.pumpWidget(
        _catalogApp(
          controller: TenantSessionController()
            ..open(
              uid: 'user-a',
              membership: _membership('tenant-a', role: TenantRole.manager),
            ),
          reader: reader,
          productStockRoute: (product) =>
              Scaffold(body: Text('stock route ${product.id}')),
          productStockRoles: const [TenantRole.manager],
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('catalog-product-product-a')),
      );
      await tester.pumpAndSettle();
      expect(find.text('stock route product-a'), findsOneWidget);
    });

    testWidgets('the adjustment feed is offered only to its roles', (
      tester,
    ) async {
      final reader = _CatalogReader(
        handler: (query) async => query.collectionPath.endsWith('/categories')
            ? [_categorySnapshot('tenant-a', 'drinks')]
            : [_productSnapshot('tenant-a', 'product-a')],
      );

      // A cashier reads the catalog but never reaches the correction record.
      await tester.pumpWidget(
        _catalogApp(
          controller: TenantSessionController()
            ..open(
              uid: 'user-a',
              membership: _membership('tenant-a', role: TenantRole.cashier),
            ),
          reader: reader,
          adjustmentFeedRoute: () => const Text('adjustment feed'),
          adjustmentFeedRoles: const [TenantRole.manager],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Cold lager'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('catalog-adjustment-feed')),
        findsNothing,
      );

      // A manager opens it, under the same session scope the catalog runs in.
      await tester.pumpWidget(
        _catalogApp(
          controller: TenantSessionController()
            ..open(
              uid: 'user-a',
              membership: _membership('tenant-a', role: TenantRole.manager),
            ),
          reader: reader,
          adjustmentFeedRoute: () =>
              const Scaffold(body: Text('adjustment feed')),
          adjustmentFeedRoles: const [TenantRole.manager],
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('catalog-adjustment-feed')));
      await tester.pumpAndSettle();
      expect(find.text('adjustment feed'), findsOneWidget);
    });

    testWidgets('the movement feed is offered only to its roles', (
      tester,
    ) async {
      final reader = _CatalogReader(
        handler: (query) async => query.collectionPath.endsWith('/categories')
            ? [_categorySnapshot('tenant-a', 'drinks')]
            : [_productSnapshot('tenant-a', 'product-a')],
      );

      // A cashier reads a product's current quantity at the till but never the
      // ledger that explains it.
      await tester.pumpWidget(
        _catalogApp(
          controller: TenantSessionController()
            ..open(
              uid: 'user-a',
              membership: _membership('tenant-a', role: TenantRole.cashier),
            ),
          reader: reader,
          movementFeedRoute: () => const Text('movement feed'),
          movementFeedRoles: const [TenantRole.manager],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Cold lager'), findsOneWidget);
      expect(find.byKey(const ValueKey('catalog-movement-feed')), findsNothing);

      // A manager opens it, under the same session scope the catalog runs in.
      await tester.pumpWidget(
        _catalogApp(
          controller: TenantSessionController()
            ..open(
              uid: 'user-a',
              membership: _membership('tenant-a', role: TenantRole.manager),
            ),
          reader: reader,
          movementFeedRoute: () => const Scaffold(body: Text('movement feed')),
          movementFeedRoles: const [TenantRole.manager],
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('catalog-movement-feed')));
      await tester.pumpAndSettle();
      expect(find.text('movement feed'), findsOneWidget);
    });

    testWidgets('a tenant switch discards outstanding catalog queries', (
      tester,
    ) async {
      final controller = TenantSessionController()
        ..open(uid: 'user-a', membership: _membership('tenant-a'));
      final pending = <String, Completer<List<TenantQueryDocumentSnapshot>>>{};
      final reader = _CatalogReader(
        handler: (query) {
          final completer = Completer<List<TenantQueryDocumentSnapshot>>();
          pending[query.collectionPath] = completer;
          return completer.future;
        },
      );
      await tester.pumpWidget(
        _catalogApp(controller: controller, reader: reader),
      );
      expect(
        pending.keys,
        containsAll(<String>[
          'tenants/tenant-a/categories',
          'tenants/tenant-a/products',
        ]),
      );

      controller.open(uid: 'user-a', membership: _membership('tenant-b'));
      await tester.pump();
      expect(
        pending.keys,
        containsAll(<String>[
          'tenants/tenant-b/categories',
          'tenants/tenant-b/products',
        ]),
      );

      pending['tenants/tenant-a/categories']!.complete([
        _categorySnapshot('tenant-a', 'drinks'),
      ]);
      pending['tenants/tenant-a/products']!.complete([
        _productSnapshot('tenant-a', 'stale-product', name: 'Stale lager'),
      ]);
      await tester.pump();
      expect(find.text('Stale lager'), findsNothing);

      pending['tenants/tenant-b/categories']!.complete([
        _categorySnapshot('tenant-b', 'drinks'),
      ]);
      pending['tenants/tenant-b/products']!.complete([
        _productSnapshot('tenant-b', 'current-product', name: 'Current soda'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Business: tenant-b'), findsOneWidget);
      expect(find.text('Current soda'), findsOneWidget);
      expect(find.text('Stale lager'), findsNothing);
    });
  });
}

final class _CatalogReader implements TenantDataReader {
  _CatalogReader({required this.handler});

  Future<List<TenantQueryDocumentSnapshot>> Function(TenantCollectionQuery)
  handler;
  final List<TenantCollectionQuery> queries = [];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) {
    queries.add(query);
    return handler(query);
  }
}

Widget _catalogApp({
  required TenantSessionController controller,
  required TenantDataReader reader,
  Iterable<TenantRole>? allowedRoles,
  TenantProductRouteBuilder? productStockRoute,
  List<TenantRole> productStockRoles = const <TenantRole>[],
  TenantAdjustmentFeedRouteBuilder? adjustmentFeedRoute,
  List<TenantRole> adjustmentFeedRoles = const <TenantRole>[],
  TenantMovementFeedRouteBuilder? movementFeedRoute,
  List<TenantRole> movementFeedRoles = const <TenantRole>[],
}) => MaterialApp(
  home: TenantSessionScope(
    controller: controller,
    child: Scaffold(
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
    ),
  ),
);

TenantSession _session(String tenantId) => TenantSession.active(
  uid: 'user-a',
  tenantId: tenantId,
  role: TenantRole.admin,
);

TenantQueryDocumentSnapshot _productSnapshot(
  String tenantId,
  String productId, {
  String name = 'Cold lager',
  Map<String, Object?>? data,
}) => TenantQueryDocumentSnapshot(
  path: 'tenants/$tenantId/products/$productId',
  data: data ?? (_productData()..['name'] = name),
);

Map<String, Object?> _productData() => <String, Object?>{
  'name': 'Cold lager',
  'SKU': 'LAGER-001',
  'price': 120.5,
  'quantity': -2,
  'categoryId': 'drinks',
  'image': 'https://example.test/lager.png',
};

TenantQueryDocumentSnapshot _categorySnapshot(
  String tenantId,
  String categoryId,
) => TenantQueryDocumentSnapshot(
  path: 'tenants/$tenantId/categories/$categoryId',
  data: const {'name': 'Drinks'},
);

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.admin,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
