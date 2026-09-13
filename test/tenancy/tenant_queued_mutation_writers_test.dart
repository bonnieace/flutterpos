import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/expenses/expenses.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late TenantPendingMutationStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('queued-writers-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('queued-writers-test');
    store = TenantPendingMutationStore.fromBox(box);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('an expense create and void appear in the local overlay', () async {
    final writer = QueuedTenantExpenseWriter(store: store);
    final create = _expenseIntent();

    expect(
      (await writer.recordExpense(create)).kind,
      TenantExpenseWriteKind.queued,
    );
    expect(
      (await writer.voidExpense(
        TenantExpenseVoidIntent(
          tenantId: 'tenant-a',
          expenseId: create.expenseId,
          reason: 'Entered twice',
          voidedBy: 'owner-a',
        ),
      )).kind,
      TenantExpenseWriteKind.queued,
    );

    final reader = TenantPendingMutationOverlayReader(
      base: const _EmptyReader(),
      store: store,
      currentUid: () => 'owner-a',
    );
    final page = await reader.getCollectionPage(
      TenantCollectionQuery.forTesting(
        collectionPath: 'tenants/tenant-a/expenses',
        limit: 20,
      ),
    );

    expect(page, hasLength(1));
    expect(page.single.data['amountMinor'], 12345);
    expect(page.single.data['voidReason'], 'Entered twice');
    expect(page.single.data['createdAt'], isA<DateTime>());
    expect(page.single.data['voidedAt'], isA<DateTime>());
  });

  test(
    'safe configuration queues even when its cache projection is absent',
    () async {
      final writer = QueuedTenantConfigurationWriter(
        remote: const _ConfigurationWriter(),
        store: store,
        cacheReader: const _EmptyReader(throwDocuments: true),
        currentUid: () => 'owner-a',
      );

      final result = await writer.merge(
        path: 'tenants/tenant-a/configuration/branding',
        data: const <String, Object?>{'companyName': 'Device name'},
      );

      expect(result.kind, TenantConfigurationWriteKind.queued);
      final overlay = TenantPendingMutationOverlayReader(
        base: const _EmptyReader(),
        store: store,
        currentUid: () => 'owner-a',
      );
      expect(
        (await overlay.getDocument(
          'tenants/tenant-a/configuration/branding',
        ))!.data['companyName'],
        'Device name',
      );
    },
  );

  test(
    'checkout configuration remains excluded from the mutation queue',
    () async {
      final writer = QueuedTenantConfigurationWriter(
        remote: const _ConfigurationWriter(),
        store: store,
        cacheReader: const _EmptyReader(),
        currentUid: () => 'owner-a',
      );

      final result = await writer.merge(
        path: 'tenants/tenant-a/configuration/checkout',
        data: const <String, Object?>{'currency': 'KES'},
      );

      expect(result.kind, TenantConfigurationWriteKind.unavailable);
      expect(
        await store.recordsForSession(uid: 'owner-a', tenantId: 'tenant-a'),
        isEmpty,
      );
    },
  );

  test(
    'a queued product is on the catalog page before any server sees it',
    () async {
      var signals = 0;
      final writer = QueuedTenantCatalogWriter(
        store: store,
        currentUid: () => 'user-a',
        onQueued: () => signals++,
      );

      final result = await writer.createProduct(_productIntent());

      // The point of the whole change: an outcome without a round trip.
      expect(result.kind, TenantCatalogWriteKind.queued);
      expect(signals, 1, reason: 'the worker must be asked to run now');

      final page = await _overlay(store).searchTenantProducts(
        TenantProductSearchQuery.forTesting(
          collectionPath: 'tenants/tenant-a/products',
          limit: 20,
        ),
      );
      expect(page, hasLength(1));
      expect(page.single.data['name'], 'White bread loaf');
      expect(page.single.data['SKU'], '6161100000019');
    },
  );

  test('a queued retire takes the product off the page', () async {
    final writer = QueuedTenantCatalogWriter(
      store: store,
      currentUid: () => 'user-a',
    );

    expect(
      (await writer.retireProduct(_retireIntent())).kind,
      TenantCatalogWriteKind.queued,
    );

    final page = await _overlay(store, base: _OneProduct())
        .searchTenantProducts(
          TenantProductSearchQuery.forTesting(
            collectionPath: 'tenants/tenant-a/products',
            limit: 20,
          ),
        );
    expect(page, isEmpty);
  });

  test(
    'a rejected mutation stops being drawn, which is the reversal',
    () async {
      final writer = QueuedTenantCatalogWriter(
        store: store,
        currentUid: () => 'user-a',
      );
      await writer.createProduct(_productIntent());

      final queued = await store.recordsForSession(
        uid: 'user-a',
        tenantId: 'tenant-a',
      );
      await store.markRejected(queued.single, 'permission-denied');

      final page = await _overlay(store).searchTenantProducts(
        TenantProductSearchQuery.forTesting(
          collectionPath: 'tenants/tenant-a/products',
          limit: 20,
        ),
      );
      expect(page, isEmpty);
    },
  );

  test(
    'undo withdraws a queued change and refuses once it is in flight',
    () async {
      final writer = QueuedTenantCatalogWriter(
        store: store,
        currentUid: () => 'user-a',
      );
      await writer.createProduct(_productIntent());
      final operationId = 'product-create-${_productIntent().productId}';

      expect(
        await store.cancel(
          uid: 'user-a',
          tenantId: 'tenant-a',
          operationId: operationId,
        ),
        isTrue,
      );
      expect(
        await store.recordsForSession(uid: 'user-a', tenantId: 'tenant-a'),
        isEmpty,
      );

      // A second change, this time taken by a worker before the undo is pressed.
      await writer.createProduct(_productIntent());
      final record = (await store.recordsForSession(
        uid: 'user-a',
        tenantId: 'tenant-a',
      )).single;
      await store.acquire(record, leaseOwner: 'device-a');

      expect(
        await store.cancel(
          uid: 'user-a',
          tenantId: 'tenant-a',
          operationId: operationId,
        ),
        isFalse,
        reason: 'a submitted change may already be on the server',
      );
    },
  );
}

const String _productId = 'req-000000000000000000000000000000';

TenantPendingMutationOverlayReader _overlay(
  TenantPendingMutationStore store, {
  TenantCacheReadable base = const _EmptyReader(),
}) => TenantPendingMutationOverlayReader(
  base: base,
  store: store,
  currentUid: () => 'user-a',
);

TenantCatalogManagementRepository _catalogRepository() =>
    TenantCatalogManagementRepository(
      session: TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.owner,
      ),
      reader: const _EmptyReader(),
    );

TenantProductCreateIntent _productIntent() =>
    _catalogRepository().buildProductIntent(
      name: 'White bread loaf',
      sku: '6161100000019',
      price: '65',
      cost: '',
      categoryId: 'cat-bakery',
      categories: <TenantCategory>[
        TenantCategory.fromSnapshot(
          TenantQueryDocumentSnapshot(
            path: 'tenants/tenant-a/categories/cat-bakery',
            data: const <String, Object?>{'name': 'Bakery'},
          ),
        ),
      ],
      requestId: _productId,
    );

TenantProductRetireIntent _retireIntent() =>
    _catalogRepository().buildRetireIntent(_storedProduct());

TenantProduct _storedProduct() => TenantProduct.fromDocument(
  path: 'tenants/tenant-a/products/prod-bread',
  data: const <String, Object?>{
    'name': 'White bread loaf',
    'SKU': '6161100000019',
    'price': 65,
    'quantity': 40,
    'categoryId': 'cat-bakery',
  },
);

/// A base reader holding the one product a retire is aimed at.
final class _OneProduct
    implements TenantCacheReadable, TenantProductSearchReader {
  @override
  TenantDataReader get cacheOnly => this;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => _rows();

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantProducts(
    TenantProductSearchQuery query,
  ) async => _rows();

  List<TenantQueryDocumentSnapshot> _rows() => <TenantQueryDocumentSnapshot>[
    TenantQueryDocumentSnapshot(
      path: 'tenants/tenant-a/products/prod-bread',
      data: const <String, Object?>{
        'name': 'White bread loaf',
        'SKU': '6161100000019',
        'price': 65,
        'quantity': 40,
        'categoryId': 'cat-bakery',
        'searchName': 'white bread loaf',
      },
    ),
  ];
}

TenantExpenseCreateIntent _expenseIntent() => TenantExpenseCreateIntent(
  tenantId: 'tenant-a',
  businessDate: '2026-09-01',
  token: 'offline-a',
  category: TenantExpenseCategory.rent,
  description: 'September rent',
  amountMinor: 12345,
  recordedBy: 'owner-a',
);

final class _ConfigurationWriter implements TenantConfigurationDocumentWriter {
  const _ConfigurationWriter();

  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async => const TenantConfigurationWriteResult.unavailable();
}

final class _EmptyReader
    implements TenantCacheReadable, TenantProductSearchReader {
  const _EmptyReader({this.throwDocuments = false});

  final bool throwDocuments;

  @override
  TenantDataReader get cacheOnly => this;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (throwDocuments) throw StateError('missing cache');
    return null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantProducts(
    TenantProductSearchQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
