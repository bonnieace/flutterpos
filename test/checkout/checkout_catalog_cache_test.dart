import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveCheckoutCatalogCache cache;
  late _Clock clock;
  late TenantSessionController sessions;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('checkout-catalog-test-');
    Hive.init(directory.path);
    box = await _openBox();
    clock = _Clock(DateTime.utc(2026, 7, 31, 10));
    cache = HiveCheckoutCatalogCache.fromBox(box, clock: clock.call);
    sessions = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
  });

  tearDown(() async {
    sessions.dispose();
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  group('what this device has sold since the catalog was read', () {
    late CheckoutCatalogLocalSales sold;
    late HiveCheckoutCatalogCache tallied;

    setUp(() {
      sold = CheckoutCatalogLocalSales();
      tallied = HiveCheckoutCatalogCache.fromBox(
        box,
        clock: clock.call,
        localSales: sold,
      );
    });

    Future<void> storeTen() => tallied.write(
      uid: 'user-a',
      tenantId: 'tenant-a',
      configuration: _configuration,
      categories: [_category('tenant-a', 'drinks')],
      products: [_product('tenant-a', 'product-a', quantity: 10)],
      complete: true,
    );

    test('a sale on this device comes off the figure the register reads', () async {
      // **The reported defect.** A sale deliberately does not refresh the
      // catalog, so the register went on reporting the stock the last refresh
      // saw - seen on a device reading `84 in stock` against an Inventory
      // reading `82`, and still `84` after two more sales.
      await storeTen();
      sold.recordSale(
        uid: 'user-a',
        tenantId: 'tenant-a',
        unitsByProduct: <String, int>{'product-a': 3},
      );

      final snapshot = await tallied.read(uid: 'user-a', tenantId: 'tenant-a');

      expect(snapshot!.productById('product-a')!.quantity, 7);
    });

    test('writing a fresh catalog settles the tally', () async {
      // The server counted these sales before it answered, so subtracting them
      // from what it said would take them off twice.
      await storeTen();
      sold.recordSale(
        uid: 'user-a',
        tenantId: 'tenant-a',
        unitsByProduct: <String, int>{'product-a': 3},
      );
      await storeTen();

      final snapshot = await tallied.read(uid: 'user-a', tenantId: 'tenant-a');

      expect(snapshot!.productById('product-a')!.quantity, 10);
      expect(sold.hasSalesFor(uid: 'user-a', tenantId: 'tenant-a'), isFalse);
    });

    test('one business never subtracts another\'s sales', () async {
      await storeTen();
      sold.recordSale(
        uid: 'user-a',
        tenantId: 'tenant-elsewhere',
        unitsByProduct: <String, int>{'product-a': 3},
      );

      final snapshot = await tallied.read(uid: 'user-a', tenantId: 'tenant-a');

      expect(snapshot!.productById('product-a')!.quantity, 10);
    });

    test('more sold than the books knew about reads as a negative', () async {
      // `-3 in stock` is a real state this till already states in words: it
      // means the shelf owed more than the books recorded. Clamping it at zero
      // would hide exactly the case somebody needs to see.
      await storeTen();
      sold.recordSale(
        uid: 'user-a',
        tenantId: 'tenant-a',
        unitsByProduct: <String, int>{'product-a': 13},
      );

      final snapshot = await tallied.read(uid: 'user-a', tenantId: 'tenant-a');

      expect(snapshot!.productById('product-a')!.quantity, -3);
    });

    test('a cache told nothing reports the stored figure unchanged', () async {
      await cache.write(
        uid: 'user-a',
        tenantId: 'tenant-a',
        configuration: _configuration,
        categories: [_category('tenant-a', 'drinks')],
        products: [_product('tenant-a', 'product-a', quantity: 10)],
        complete: true,
      );

      final snapshot = await cache.read(uid: 'user-a', tenantId: 'tenant-a');

      expect(snapshot!.productById('product-a')!.quantity, 10);
    });
  });

  group('encrypted cache storage', () {
    test('isolates snapshots by both UID and tenant', () async {
      await cache.write(
        uid: 'user-a',
        tenantId: 'tenant-a',
        configuration: _configuration,
        categories: [_category('tenant-a', 'drinks')],
        products: [_product('tenant-a', 'product-a')],
        complete: true,
      );

      final owned = await cache.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(owned, isNotNull);
      expect(owned!.products.single.id, 'product-a');
      expect(owned.categories.single.name, 'drinks name');
      expect(owned.configuration.currency, 'KES');
      expect(owned.complete, isTrue);
      expect(owned.refreshedAt, DateTime.utc(2026, 7, 31, 10));
      expect(await cache.read(uid: 'user-b', tenantId: 'tenant-a'), isNull);
      expect(await cache.read(uid: 'user-a', tenantId: 'tenant-b'), isNull);
    });

    test('reopens the encrypted box with the same key after a restart', () async {
      await cache.write(
        uid: 'user-a',
        tenantId: 'tenant-a',
        configuration: _configuration,
        categories: [_category('tenant-a', 'drinks')],
        products: [
          _product('tenant-a', 'product-a', price: 120.5, quantity: -2),
        ],
        complete: false,
      );
      await cache.close();

      box = await _openBox();
      cache = HiveCheckoutCatalogCache.fromBox(box, clock: clock.call);
      final restored = await cache.read(uid: 'user-a', tenantId: 'tenant-a');

      expect(restored, isNotNull);
      expect(restored!.complete, isFalse);
      expect(restored.productById('product-a')!.price, 120.5);
      expect(restored.productById('product-a')!.quantity, -2);
      expect(restored.categoryById('drinks')!.name, 'drinks name');
      expect(restored.productById('missing'), isNull);
    });

    test('treats malformed and foreign records as a miss', () async {
      final valid = <String, Object?>{
        'schemaVersion': HiveCheckoutCatalogCache.schemaVersion,
        'uid': 'user-a',
        'tenantId': 'tenant-a',
        'refreshedAtMs': 100,
        'complete': true,
        'configuration': <String, Object?>{'currency': 'KES'},
        'categories': <Object?>[],
        'products': <Object?>[
          <String, Object?>{
            'path': 'tenants/tenant-a/products/product-a',
            'name': 'Product',
            'SKU': 'sku-a',
            'price': 10.0,
            'quantity': 1,
            'categoryId': 'drinks',
          },
        ],
      };
      Future<CheckoutCatalogSnapshot?> store(
        Map<String, Object?> Function(Map<String, Object?>) mutate,
      ) async {
        await box.put(
          'user-a:tenant-a',
          mutate(Map<String, Object?>.from(valid)),
        );
        return cache.read(uid: 'user-a', tenantId: 'tenant-a');
      }

      expect(await store((record) => record), isNotNull);
      expect(await store((record) => record..['schemaVersion'] = 1), isNull);
      expect(await store((record) => record..['uid'] = 'user-b'), isNull);
      expect(await store((record) => record..['complete'] = 'yes'), isNull);
      expect(await store((record) => record..remove('configuration')), isNull);
      expect(
        await store(
          (record) => record..['configuration'] = <String, Object?>{
            'currency': 'kes',
          },
        ),
        isNull,
      );
      expect(
        await store(
          (record) => record
            ..['products'] = <Object?>[
              <String, Object?>{
                'path': 'tenants/tenant-b/products/product-a',
                'name': 'Product',
                'SKU': 'sku-a',
                'price': 10.0,
                'quantity': 1,
                'categoryId': 'drinks',
              },
            ],
        ),
        isNull,
      );
      expect(
        await store(
          (record) => record
            ..['products'] = <Object?>[
              <String, Object?>{
                'path': 'tenants/tenant-a/products/product-a',
                'name': '',
                'SKU': 'sku-a',
                'price': 10.0,
                'quantity': 1,
                'categoryId': 'drinks',
              },
            ],
        ),
        isNull,
      );
      expect(
        await store(
          (record) => record
            ..['products'] = <Object?>[
              <String, Object?>{
                'path': 'tenants/tenant-a/products/product-a',
                'name': 'Product',
                'SKU': 'sku-a',
                'price': -1,
                'quantity': 1,
                'categoryId': 'drinks',
              },
            ],
        ),
        isNull,
      );
      expect(await store((record) => record..['products'] = 'not-a-list'), isNull);
    });

    test('rejects duplicate documents in one written snapshot', () async {
      await expectLater(
        cache.write(
          uid: 'user-a',
          tenantId: 'tenant-a',
          configuration: _configuration,
          categories: const [],
          products: [
            _product('tenant-a', 'product-a'),
            _product('tenant-a', 'product-a'),
          ],
          complete: true,
        ),
        throwsA(isA<CheckoutCatalogCacheException>()),
      );
    });
  });

  group('guarded refresh', () {
    test('refuses to refresh without a selected session', () async {
      sessions.clear();
      final result = await _refresher(sessions, cache, _Reader()).
          refreshSelectedSession();

      expect(result.kind, CheckoutCatalogRefreshKind.noSelectedSession);
      expect(await cache.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('pages the guarded catalog and caches the complete result', () async {
      final reader = _Reader(
        categories: [_categorySnapshot('tenant-a', 'drinks')],
        products: [
          _productSnapshot('tenant-a', 'product-a'),
          _productSnapshot('tenant-a', 'product-b'),
          _productSnapshot('tenant-a', 'product-c'),
        ],
      );

      final result = await _refresher(
        sessions,
        cache,
        reader,
        pageSize: 2,
      ).refreshSelectedSession();

      expect(result.kind, CheckoutCatalogRefreshKind.completed);
      expect(result.products, 3);
      expect(result.categories, 1);
      expect(result.complete, isTrue);
      expect(
        reader.queries.map((query) => query.collectionPath).toSet(),
        {'tenants/tenant-a/categories', 'tenants/tenant-a/products'},
      );
      expect(reader.documentPaths, [
        'tenants/tenant-a/configuration/checkout',
      ]);
      final snapshot = await cache.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(snapshot!.products.map((product) => product.id), [
        'product-a',
        'product-b',
        'product-c',
      ]);
    });

    test('bounds a large catalog and records an incomplete refresh', () async {
      final reader = _Reader(
        products: [
          _productSnapshot('tenant-a', 'product-a'),
          _productSnapshot('tenant-a', 'product-b'),
          _productSnapshot('tenant-a', 'product-c'),
        ],
      );

      final result = await _refresher(
        sessions,
        cache,
        reader,
        pageSize: 1,
        maximumProducts: 2,
      ).refreshSelectedSession();

      expect(result.kind, CheckoutCatalogRefreshKind.completed);
      expect(result.products, 2);
      expect(result.complete, isFalse);
      final snapshot = await cache.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(snapshot!.products, hasLength(2));
      expect(snapshot.complete, isFalse);
    });

    test('discards a result whose session epoch changed mid-query', () async {
      final reader = _Reader(
        products: [_productSnapshot('tenant-a', 'product-a')],
        onQuery: (_) => sessions.open(
          uid: 'user-a',
          membership: _membership('tenant-b'),
        ),
      );

      final result = await _refresher(
        sessions,
        cache,
        reader,
      ).refreshSelectedSession();

      expect(result.kind, CheckoutCatalogRefreshKind.sessionChanged);
      expect(await cache.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
      expect(await cache.read(uid: 'user-a', tenantId: 'tenant-b'), isNull);
    });

    test('fails closed on a cross-tenant query result', () async {
      final reader = _Reader(
        products: [_productSnapshot('tenant-b', 'product-a')],
      );

      final result = await _refresher(
        sessions,
        cache,
        reader,
      ).refreshSelectedSession();

      expect(result.kind, CheckoutCatalogRefreshKind.unavailable);
      expect(await cache.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('fails closed without a usable checkout configuration', () async {
      final missing = await _refresher(
        sessions,
        cache,
        _Reader(
          products: [_productSnapshot('tenant-a', 'product-a')],
          configuration: null,
        ),
      ).refreshSelectedSession();

      expect(
        missing.kind,
        CheckoutCatalogRefreshKind.configurationUnavailable,
      );
      expect(await cache.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);

      final malformed = await _refresher(
        sessions,
        cache,
        _Reader(
          products: [_productSnapshot('tenant-a', 'product-a')],
          configuration: const <String, Object?>{'currency': 'shillings'},
        ),
      ).refreshSelectedSession();

      expect(
        malformed.kind,
        CheckoutCatalogRefreshKind.configurationUnavailable,
      );
      expect(await cache.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('leaves an existing cache untouched when a refresh fails', () async {
      await cache.write(
        uid: 'user-a',
        tenantId: 'tenant-a',
        configuration: _configuration,
        categories: const [],
        products: [_product('tenant-a', 'product-a')],
        complete: true,
      );

      final result = await _refresher(
        sessions,
        cache,
        _Reader(configuration: null),
      ).refreshSelectedSession();

      expect(
        result.kind,
        CheckoutCatalogRefreshKind.configurationUnavailable,
      );
      final snapshot = await cache.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(snapshot!.products.single.id, 'product-a');
    });

    test('coalesces a concurrent refresh instead of running twice', () async {
      final reader = _Reader(products: [_productSnapshot('tenant-a', 'a')]);
      final refresher = _refresher(sessions, cache, reader);

      final first = refresher.refreshSelectedSession();
      final second = await refresher.refreshSelectedSession();

      expect(second.kind, CheckoutCatalogRefreshKind.alreadyRunning);
      expect((await first).kind, CheckoutCatalogRefreshKind.completed);
    });
  });
}

Future<Box<dynamic>> _openBox() => Hive.openBox<dynamic>(
  HiveCheckoutCatalogCache.boxName,
  encryptionCipher: HiveAesCipher(_encryptionKey),
  crashRecovery: false,
);

final List<int> _encryptionKey = List<int>.generate(
  HiveCheckoutCatalogCache.encryptionKeyBytes,
  (index) => (index * 7) % 256,
);

final TenantCheckoutConfiguration _configuration = TenantCheckoutConfiguration(
  currency: 'KES',
);

CheckoutCatalogCacheRefresher _refresher(
  TenantSessionController sessions,
  HiveCheckoutCatalogCache cache,
  TenantDataReader reader, {
  int pageSize = 50,
  int maximumProducts = 2000,
  int maximumCategories = 500,
}) => CheckoutCatalogCacheRefresher(
  sessionController: sessions,
  cache: cache,
  reader: reader,
  pageSize: pageSize,
  maximumProducts: maximumProducts,
  maximumCategories: maximumCategories,
);

TenantQueryDocumentSnapshot _productSnapshot(
  String tenantId,
  String productId, {
  double price = 10,
  int quantity = 4,
}) => TenantQueryDocumentSnapshot(
  path: 'tenants/$tenantId/products/$productId',
  data: <String, Object?>{
    'name': '$productId name',
    'SKU': 'sku-$productId',
    'price': price,
    'quantity': quantity,
    'categoryId': 'drinks',
  },
);

TenantQueryDocumentSnapshot _categorySnapshot(
  String tenantId,
  String categoryId,
) => TenantQueryDocumentSnapshot(
  path: 'tenants/$tenantId/categories/$categoryId',
  data: <String, Object?>{'name': '$categoryId name'},
);

TenantProduct _product(
  String tenantId,
  String productId, {
  double price = 10,
  int quantity = 4,
}) => TenantProduct.fromSnapshot(
  _productSnapshot(tenantId, productId, price: price, quantity: quantity),
);

TenantCategory _category(String tenantId, String categoryId) =>
    TenantCategory.fromSnapshot(_categorySnapshot(tenantId, categoryId));

final class _Reader implements TenantDataReader {
  _Reader({
    List<TenantQueryDocumentSnapshot>? categories,
    List<TenantQueryDocumentSnapshot>? products,
    this.configuration = const <String, Object?>{'currency': 'KES'},
    this.onQuery,
  }) : categories = categories ?? const [],
       products = products ?? const [];

  final List<TenantQueryDocumentSnapshot> categories;
  final List<TenantQueryDocumentSnapshot> products;
  final Map<String, Object?>? configuration;
  final void Function(TenantCollectionQuery query)? onQuery;
  final List<TenantCollectionQuery> queries = [];
  final List<String> documentPaths = [];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentPaths.add(path);
    final data = configuration;
    if (data == null) return null;
    return TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    onQuery?.call(query);
    final source = query.collectionPath.endsWith('/categories')
        ? categories
        : products;
    final cursor = query.startAfterDocumentId;
    final remaining = cursor == null
        ? source
        : source
              .where(
                (snapshot) =>
                    snapshot.path.split('/').last.compareTo(cursor) > 0,
              )
              .toList();
    return remaining.take(query.limit).toList();
  }
}

final class _Clock {
  _Clock(this.value);

  DateTime value;

  DateTime call() => value;
}

TenantMembership _membership(String tenantId) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: TenantRole.cashier,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
