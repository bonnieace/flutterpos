import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
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

    test('an absent buying price is normal, and a broken one is not', () {
      // Optional on purpose, and this is the test that says why: no product
      // created before `cost` existed carries one, and this read model is
      // strict enough that a single refusal makes the *whole* cached catalog a
      // miss - so requiring it would have stopped every existing business
      // selling. A present-but-unusable value is still refused, because
      // dropping it would report the product's entire revenue as profit.
      expect(
        TenantProduct.fromSnapshot(_productSnapshot('tenant-a', 'p')).cost,
        isNull,
      );
      expect(
        TenantProduct.fromSnapshot(
          _productSnapshot('tenant-a', 'p', data: _productData()..['cost'] = null),
        ).cost,
        isNull,
      );
      expect(
        TenantProduct.fromSnapshot(
          _productSnapshot('tenant-a', 'p', data: _productData()..['cost'] = 60),
        ).cost,
        60,
      );
      expect(
        TenantProduct.fromSnapshot(
          _productSnapshot(
            'tenant-a',
            'p',
            data: _productData()..['cost'] = 0,
          ),
        ).cost,
        0,
      );
      for (final broken in <Object?>['60', -1, double.nan, double.infinity]) {
        expect(
          () => TenantProduct.fromSnapshot(
            _productSnapshot(
              'tenant-a',
              'p',
              data: _productData()..['cost'] = broken,
            ),
          ),
          throwsA(isA<FormatException>()),
          reason: 'cost $broken must be refused rather than dropped',
        );
      }
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

  group('naming a category', () {
    test('a category this surface read is named, and one it did not is not', () {
      final names = tenantCategoryNames(<TenantCategory>[
        TenantCategory.fromSnapshot(_categorySnapshot('tenant-a', 'drinks')),
      ]);

      expect(names, <String, String>{'drinks': 'Drinks'});
      expect(tenantCategoryLabel('drinks', names: names), 'Drinks');
      expect(tenantCategoryPhrase('drinks', names: names), 'Drinks');
      // Two causes arrive here and neither is distinguishable from the other
      // without reading the document: a business holding more categories than
      // one page shows, and a product filed under a category that cannot be
      // read at all. The ID answers neither question, and is not a name.
      expect(
        tenantCategoryLabel('cat-not-cached', names: names),
        unlistedTenantCategoryLabel,
      );
      expect(
        tenantCategoryPhrase('cat-not-cached', names: names),
        unlistedTenantCategoryPhrase,
      );
      for (final wording in <String>[
        unlistedTenantCategoryLabel,
        unlistedTenantCategoryPhrase,
      ]) {
        expect(wording, isNot(contains('cat-not-cached')));
      }
      // Two wordings for one answer, because only one of them can be read in
      // each place: "filed under Category not listed here" is not a sentence
      // anybody wrote, and a list row does not open in lower case.
      expect(unlistedTenantCategoryLabel, startsWith('Category'));
      expect(unlistedTenantCategoryPhrase, startsWith('a category'));
    });
  });

  group('a product as a record', () {
    TenantProduct product({required int quantity}) =>
        TenantProduct.fromSnapshot(
          _productSnapshot(
            'tenant-a',
            'product-a',
            data: _productData()..['quantity'] = quantity,
          ),
        );

    test('only a product that cannot be sold carries a standing', () {
      // §2.1 gives `problem` three meanings and names "out of stock" as one of
      // them, so the badge is a lookup. What is a judgement is the silence on
      // every other product: a list where every row wears a badge has no signal
      // in it, and being in stock is the ordinary case.
      expect(tenantProductStanding(product(quantity: 40)), isNull);
      expect(tenantProductStanding(product(quantity: 1)), isNull);

      for (final empty in <int>[0, -3]) {
        final standing = tenantProductStanding(product(quantity: empty));
        expect(standing, isNotNull, reason: 'quantity $empty cannot be sold');
        expect(standing!.status, AppStatus.problem);
        // §9: never colour alone. The word is the whole point.
        expect(standing.label, 'Out of stock');
      }
    });

    test('the three facts are stated in the order a table draws them', () {
      final attributes = tenantProductAttributes(
        product(quantity: 7),
        keyPrefix: 'somewhere',
      );

      expect(
        attributes.map((attribute) => attribute.label),
        <String>['Code', 'In stock', 'Unit price'],
      );
      expect(
        attributes.map((attribute) => attribute.value),
        <String>['LAGER-001', '7', '120.50'],
      );
      // Nothing is marked out of the narrow form: `inNarrowForm` drops a fact
      // rather than shortening one, and three lines fit a card at every band.
      expect(
        attributes.every((attribute) => attribute.inNarrowForm),
        isTrue,
      );
      // A 13-digit barcode wrapped to two lines at an equal share, which is
      // what a string compared character by character must never do.
      expect(
        attributes.map((attribute) => attribute.flex),
        <int>[2, 1, 1],
      );
      expect(
        attributes.map((attribute) => attribute.valueKey),
        <Key>[
          const ValueKey('somewhere-code-product-a'),
          const ValueKey('somewhere-stock-product-a'),
          const ValueKey('somewhere-price-product-a'),
        ],
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

    testWidgets('a product names its category, never the ID it is filed under', (
      tester,
    ) async {
      final reader = _CatalogReader(
        handler: (query) async => query.collectionPath.endsWith('/categories')
            ? [_categorySnapshot('tenant-a', 'drinks')]
            : [
                _productSnapshot('tenant-a', 'product-a'),
                _productSnapshot(
                  'tenant-a',
                  'product-b',
                  data: _productData()
                    ..['name'] = 'Charcoal 2kg'
                    ..['categoryId'] = 'cat-not-cached',
                ),
              ],
      );

      await tester.pumpWidget(
        _catalogApp(
          controller: TenantSessionController()
            ..open(uid: 'user-a', membership: _membership('tenant-a')),
          reader: reader,
        ),
      );
      await tester.pump();
      await tester.pump();

      // The same two facts, in Â§4.3's rendering rather than in one
      // bullet-separated sentence: the category is the record's second
      // identifying line and the code is a labelled attribute. What the test is
      // about is unchanged - a category is named, and its document ID is not.
      expect(_text(tester, 'catalog-product-category-product-a'), 'Drinks');
      expect(_text(tester, 'catalog-product-code-product-a'), 'LAGER-001');
      expect(
        _text(tester, 'catalog-product-category-product-b'),
        unlistedTenantCategoryLabel,
      );
      expect(_text(tester, 'catalog-product-code-product-b'), 'LAGER-001');
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .nonNulls
            .where(RegExp(r'cat-|ct_').hasMatch),
        isEmpty,
      );
    });

    testWidgets('a product that cannot be sold says so, and its neighbour '
        'says nothing', (tester) async {
      final reader = _CatalogReader(
        handler: (query) async => query.collectionPath.endsWith('/categories')
            ? [_categorySnapshot('tenant-a', 'drinks')]
            : [
                // -2 in the shared fixture: an oversold product is a state this
                // app records rather than refuses, and what it means at the
                // till is what zero means.
                _productSnapshot('tenant-a', 'product-a'),
                _productSnapshot(
                  'tenant-a',
                  'product-b',
                  data: _productData()
                    ..['name'] = 'Warm lager'
                    ..['quantity'] = 6,
                ),
              ],
      );

      await tester.pumpWidget(
        _catalogApp(
          controller: TenantSessionController()
            ..open(uid: 'user-a', membership: _membership('tenant-a')),
          reader: reader,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<StatusBadge>(
              find.byKey(const ValueKey('product-stock-standing-product-a')),
            )
            .label,
        'Out of stock',
      );
      expect(
        find.byKey(const ValueKey('product-stock-standing-product-b')),
        findsNothing,
      );
      // The figure is still stated beside the badge, so the badge adds a
      // meaning rather than replacing a number.
      expect(_text(tester, 'catalog-product-stock-product-a'), '-2');
      expect(_text(tester, 'catalog-product-stock-product-b'), '6');
    });

    testWidgets('the catalog lays a record out on a phone', (tester) async {
      // §4.1's `compact` band. This list has only ever been driven at 800 and
      // wider, which is exactly how the staff directory's five inline forms
      // came to be overflowing on every phone without anybody knowing.
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final reader = _CatalogReader(
        handler: (query) async => query.collectionPath.endsWith('/categories')
            ? [_categorySnapshot('tenant-a', 'drinks')]
            : [_productSnapshot('tenant-a', 'product-a')],
      );
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
      await tester.pumpAndSettle();

      // One action, so §4.3's overflow rule does not apply at any band and the
      // control is inline on a phone as it is on a desktop window.
      final action = find.byKey(
        const ValueKey('catalog-product-view-stock-product-a'),
      );
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('stock route product-a'), findsOneWidget);
    });

    testWidgets('the route states its read-only standing once, as a status', (
      tester,
    ) async {
      // It used to be a `headlineSmall` reading "Read-only catalog" at the top
      // and an uncontained paragraph at the bottom naming what is unavailable -
      // one fact, stated twice, a page apart, and neither of them rendered the
      // way §2.1 requires a status to be.
      final reader = _CatalogReader(
        handler: (query) async => query.collectionPath.endsWith('/categories')
            ? [_categorySnapshot('tenant-a', 'drinks')]
            : [_productSnapshot('tenant-a', 'product-a')],
      );
      await tester.pumpWidget(
        _catalogApp(
          controller: TenantSessionController()
            ..open(uid: 'user-a', membership: _membership('tenant-a')),
          reader: reader,
        ),
      );
      await tester.pump();
      await tester.pump();

      final callout = tester.widget<Callout>(
        find.byKey(const ValueKey('catalog-read-only')),
      );
      // §2.1 gives `info` the meaning "offline, read-only, informational", so
      // this is the document's own lookup rather than a judgement.
      expect(callout.status, AppStatus.info);
      expect(callout.title, 'Read-only catalog');
      expect(callout.message, contains('stock actions'));
      expect(find.text('Read-only catalog'), findsOneWidget);
    });

    testWidgets('the standing says less once a stock route is offered', (
      tester,
    ) async {
      final reader = _CatalogReader(
        handler: (query) async => query.collectionPath.endsWith('/categories')
            ? [_categorySnapshot('tenant-a', 'drinks')]
            : [_productSnapshot('tenant-a', 'product-a')],
      );
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

      final callout = tester.widget<Callout>(
        find.byKey(const ValueKey('catalog-read-only')),
      );
      expect(callout.status, AppStatus.info);
      // Stock is no longer among the things this route cannot reach, and the
      // sentence that says so travelled with the status rather than staying
      // behind at the bottom of the page.
      expect(callout.message, isNot(contains('stock actions')));
      expect(callout.message, contains('Open a product'));
    });

    testWidgets('missing and wrong-role sessions never start a query', (
      tester,
    ) async {
      final reader = _CatalogReader(handler: (_) async => const []);
      final missing = TenantSessionController();
      await tester.pumpWidget(_catalogApp(controller: missing, reader: reader));
      expect(find.text('You do not have access to this page.'), findsOneWidget);
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
      expect(find.text('You do not have access to this page.'), findsOneWidget);
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
      // The record is drawn either way; what a role decides is whether it
      // carries the action. This used to be a `ListTile.onTap` of null, which
      // is the same fact rendered as nothing a person could see.
      expect(
        find.byKey(const ValueKey('catalog-product-product-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('catalog-product-view-stock-product-a')),
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
          productStockRoute: (product) =>
              Scaffold(body: Text('stock route ${product.id}')),
          productStockRoles: const [TenantRole.manager],
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('catalog-product-view-stock-product-a')),
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

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

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
