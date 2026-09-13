import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/landing_drawer.dart';

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
          _productSnapshot(
            'tenant-a',
            'p',
            data: _productData()..['cost'] = null,
          ),
        ).cost,
        isNull,
      );
      expect(
        TenantProduct.fromSnapshot(
          _productSnapshot(
            'tenant-a',
            'p',
            data: _productData()..['cost'] = 60,
          ),
        ).cost,
        60,
      );
      expect(
        TenantProduct.fromSnapshot(
          _productSnapshot('tenant-a', 'p', data: _productData()..['cost'] = 0),
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
    test(
      'a category this surface read is named, and one it did not is not',
      () {
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
      },
    );
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

    test('only a product at or below zero carries a standing', () {
      // What is a judgement is the silence on every other product: a list where
      // every row wears a badge has no signal in it, and an ordinary stock
      // figure is the ordinary case.
      expect(tenantProductStanding(product(quantity: 40)), isNull);
      expect(tenantProductStanding(product(quantity: 1)), isNull);

      // **The badge states the figure, never `Out of stock`.** That phrase
      // asserts a sale is blocked, which this product never does - Phase 03
      // refused it on the till for the same reason, and Phase 04's second
      // acceptance criterion is exactly this. The label is checked against the
      // phrase rather than only for its own text so that a later edit cannot
      // reintroduce it quietly.
      for (final MapEntry(key: quantity, value: label) in <int, String>{
        0: '0 in stock',
        -3: '-3 in stock',
      }.entries) {
        final standing = tenantProductStanding(product(quantity: quantity));
        expect(
          standing,
          isNotNull,
          reason: 'quantity $quantity has a standing',
        );
        expect(standing!.status, AppStatus.problem);
        // §9: never colour alone. The words are the whole point.
        expect(standing.label, label);
        expect(standing.label, isNot(contains('Out of stock')));
      }
    });

    test('the three facts are stated in the order a table draws them', () {
      final attributes = tenantProductAttributes(
        product(quantity: 7),
        keyPrefix: 'somewhere',
      );

      expect(attributes.map((attribute) => attribute.label), <String>[
        'Code',
        'In stock',
        'Unit price',
      ]);
      expect(attributes.map((attribute) => attribute.value), <String>[
        'LAGER-001',
        '7',
        '120.50',
      ]);
      // Nothing is marked out of the narrow form: `inNarrowForm` drops a fact
      // rather than shortening one, and three lines fit a card at every band.
      expect(attributes.every((attribute) => attribute.inNarrowForm), isTrue);
      // A 13-digit barcode wrapped to two lines at an equal share, which is
      // what a string compared character by character must never do.
      expect(attributes.map((attribute) => attribute.flex), <int>[2, 1, 1]);
      expect(attributes.map((attribute) => attribute.valueKey), <Key>[
        const ValueKey('somewhere-code-product-a'),
        const ValueKey('somewhere-stock-product-a'),
        const ValueKey('somewhere-price-product-a'),
      ]);
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

    test('every category is read, across as many pages as it takes', () async {
      // **The defect: one page was all any form ever saw.** Filing a product
      // under a category, moving one, and filtering by one all read a single
      // page, so a business past it had categories it could see in the
      // Categories screen and could select nowhere else.
      var page = 0;
      final reader = _CatalogReader(
        handler: (query) async {
          page++;
          if (page == 1) {
            expect(query.startAfterDocumentId, isNull);
            // 51 for a page size of 50: one extra so `hasMore` is exact.
            return <TenantQueryDocumentSnapshot>[
              for (var i = 0; i < 51; i++)
                _categorySnapshot(
                  'tenant-a',
                  'cat-a-${i.toString().padLeft(3, '0')}',
                ),
            ];
          }
          expect(query.startAfterDocumentId, 'cat-a-049');
          return <TenantQueryDocumentSnapshot>[
            _categorySnapshot('tenant-a', 'cat-b-0'),
          ];
        },
      );
      final repository = TenantCatalogRepository(
        session: _session('tenant-a'),
        reader: reader,
      );

      final categories = await repository.loadEveryCategory();

      expect(page, 2, reason: 'the second page has to be asked for');
      expect(categories.items, hasLength(51));
      expect(categories.items.last.id, 'cat-b-0');
      expect(categories.hasMore, isFalse);
    });

    test('the category scan stops at the bound the server also enforces', () async {
      // A client that loaded more categories than `importProducts` will scan
      // would offer a choice the import then refuses to resolve, so one figure
      // governs both. `hasMore` then means "more than anything here reads",
      // which is what the screen says.
      final reader = _CatalogReader(
        handler: (query) async => <TenantQueryDocumentSnapshot>[
          for (var i = 0; i < 51; i++)
            _categorySnapshot(
            'tenant-a',
            'cat-${query.startAfterDocumentId}-${i.toString().padLeft(3, '0')}',
          ),
        ],
      );
      final repository = TenantCatalogRepository(
        session: _session('tenant-a'),
        reader: reader,
      );

      final categories = await repository.loadEveryCategory(maximum: 120);

      expect(categories.items, hasLength(120));
      expect(categories.hasMore, isTrue);
    });

    test('a page claiming more with no cursor ends the scan', () async {
      // Otherwise the loop asks for the same page for ever. It cannot happen
      // through `readCollectionPage`, which is exactly why it is worth pinning:
      // nothing else would notice if it started to.
      var calls = 0;
      final reader = _CatalogReader(
        handler: (_) async {
          calls++;
          return <TenantQueryDocumentSnapshot>[
            _categorySnapshot('tenant-a', 'drinks'),
          ];
        },
      );
      final repository = TenantCatalogRepository(
        session: _session('tenant-a'),
        reader: reader,
      );

      final categories = await repository.loadEveryCategory();

      expect(calls, 1);
      expect(categories.items.single.id, 'drinks');
      expect(categories.hasMore, isFalse);
    });

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

  group('tenant product backend search', () {
    test('passes every filter and advances an opaque stable cursor', () async {
      final reader = _CatalogReader(handler: (_) async => const []);
      final searchReader = _ProductSearchReader(
        handler: (_) async => <TenantQueryDocumentSnapshot>[
          _productSnapshot(
            'tenant-a',
            'product-a',
            data: _productData()
              ..['searchName'] = 'brown bread'
              ..['quantity'] = 0,
          ),
          _productSnapshot(
            'tenant-a',
            'product-b',
            data: _productData()
              ..['searchName'] = 'brown bun'
              ..['quantity'] = -1,
          ),
          _productSnapshot(
            'tenant-a',
            'product-c',
            data: _productData()
              ..['searchName'] = 'brown cake'
              ..['quantity'] = -2,
          ),
        ],
      );
      final repository = TenantCatalogRepository(
        session: _session('tenant-a'),
        reader: reader,
        productSearchReader: searchReader,
      );

      final first = await repository.searchProducts(
        pageSize: 2,
        searchPrefix: 'br',
        categoryId: 'drinks',
        stock: TenantProductStockFilter.atOrBelowZero,
      );

      final query = searchReader.queries.single;
      expect(query.collectionPath, 'tenants/tenant-a/products');
      expect(query.limit, 3);
      expect(query.searchPrefix, 'br');
      expect(query.categoryId, 'drinks');
      expect(query.stock, TenantProductStockFilter.atOrBelowZero);
      expect(first.items.map((product) => product.id), [
        'product-a',
        'product-b',
      ]);
      expect(first.nextCursor, isNot(anyOf(isNull, 'product-b')));

      searchReader.handler = (next) async {
        expect(next.startAfter?.searchName, 'brown bun');
        expect(next.startAfter?.documentId, 'product-b');
        expect(next.startAfter?.quantity, -1);
        return <TenantQueryDocumentSnapshot>[
          _productSnapshot(
            'tenant-a',
            'product-c',
            data: _productData()
              ..['searchName'] = 'brown cake'
              ..['quantity'] = -2,
          ),
        ];
      };
      final second = await repository.searchProducts(
        pageSize: 2,
        cursor: first.nextCursor,
        searchPrefix: 'br',
        categoryId: 'drinks',
        stock: TenantProductStockFilter.atOrBelowZero,
      );
      expect(second.items.single.id, 'product-c');
      expect(second.hasMore, isFalse);
    });

    test(
      'rejects malformed filters, cursors, and cross-tenant results',
      () async {
        final searchReader = _ProductSearchReader(
          handler: (_) async => <TenantQueryDocumentSnapshot>[
            _productSnapshot(
              'tenant-b',
              'product-a',
              data: _productData()..['searchName'] = 'bread',
            ),
          ],
        );
        final repository = TenantCatalogRepository(
          session: _session('tenant-a'),
          reader: _CatalogReader(handler: (_) async => const []),
          productSearchReader: searchReader,
        );

        await expectLater(
          repository.searchProducts(searchPrefix: 'b'),
          throwsArgumentError,
        );
        await expectLater(
          repository.searchProducts(searchPrefix: 'BR'),
          throwsArgumentError,
        );
        await expectLater(
          repository.searchProducts(categoryId: 'escape/path'),
          throwsArgumentError,
        );
        await expectLater(
          repository.searchProducts(cursor: 'not-a-cursor'),
          throwsFormatException,
        );
        await expectLater(
          repository.searchProducts(searchPrefix: 'br'),
          throwsA(isA<TenantScopeViolation>()),
        );
      },
    );
  });

  group('guarded catalog route', () {
    testWidgets('safe landing opens the unified inventory route', (
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
              catalogManagementRoute: (reader) =>
                  TenantCatalogManagementScreen(reader: reader),
              onSignOut: () async {},
            ),
          ),
        ),
      );
      await tester.pump();

      await openLandingDrawer(tester);
      await tester.tap(find.text('Inventory'));
      await tester.pumpAndSettle();

      // **The route's own title, which is not the tile's label.** The grid
      // tile reads *Inventory*; the screen it opens is titled *Inventory
      // Manager*, and `find.text` is an exact match - so this asserted a
      // string the opened route has never drawn.
      expect(find.text('Inventory Manager'), findsWidgets);
      expect(find.text('Cold lager'), findsOneWidget);
      expect(find.byKey(const ValueKey('inventory-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('inventory-add-product')), findsNothing);
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
        '-2 in stock',
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
      // Scrolled to before it is tapped, the way the sibling test above already
      // does it. The page grew by one caption line when the catalog gained the
      // sentence saying a stock count never blocks a sale, which put this action
      // at y=640 on an 800x600 test surface - and `tap` on an off-screen widget
      // warns rather than fails, so what broke was the assertion after it.
      final action = find.byKey(
        const ValueKey('catalog-product-view-stock-product-a'),
      );
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
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

final class _ProductSearchReader implements TenantProductSearchReader {
  _ProductSearchReader({required this.handler});

  Future<List<TenantQueryDocumentSnapshot>> Function(TenantProductSearchQuery)
  handler;
  final List<TenantProductSearchQuery> queries = <TenantProductSearchQuery>[];

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantProducts(
    TenantProductSearchQuery query,
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
