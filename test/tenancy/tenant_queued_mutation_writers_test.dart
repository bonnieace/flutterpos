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

  test('a queued retire marks the product rather than hiding it', () async {
    // **This asserted the opposite until 2026-09-13**, and rightly: retiring
    // was a delete, so the overlay drew a tombstone. It is a flag now - the
    // document stays so every past sale line and the ledger below it still name
    // something that answers - and the row stays with it, marked.
    //
    // The quantity goes to zero because the server clears it in the same
    // transaction the flag is written in. Drawing the old figure against a
    // retired row would state stock already accounted for as gone.
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
    expect(page, hasLength(1));
    expect(page.single.data['retired'], isTrue);
    expect(page.single.data['quantity'], 0);
    // Everything else the row draws is still the product's own.
    expect(page.single.data['SKU'], '6161100000019');
  });

  test('a queued restore puts it back without inventing stock', () async {
    // Restoring clears the flag and nothing else. Those units were accounted
    // for as leaving; handing them back would be a movement nobody could
    // explain, so a restored product takes an ordinary opening balance.
    final writer = QueuedTenantCatalogWriter(
      store: store,
      currentUid: () => 'user-a',
    );

    expect(
      (await writer.retireProduct(_retireIntent(retired: false))).kind,
      TenantCatalogWriteKind.queued,
    );

    final page = await _overlay(store, base: _OneProduct())
        .searchTenantProducts(
          TenantProductSearchQuery.forTesting(
            collectionPath: 'tenants/tenant-a/products',
            limit: 20,
          ),
        );
    expect(page.single.data['retired'], isFalse);
    // Untouched: only a retirement clears the figure.
    expect(page.single.data['quantity'], 40);
  });

  test('every page of one count queues under the count, not the products', () async {
    // **The property the ordering rests on.** The outbox drains one target path
    // strictly in sequence and different paths concurrently, so pages sharing
    // the take go up in order while a colleague's count on another device does
    // not wait behind them.
    final writer = QueuedTenantStockTakeWriter(
      store: store,
      currentUid: () => 'user-a',
    );
    final draft = _stockTakeDraft(lines: 3);

    for (final page in tenantStockTakePages(draft, pageSize: 2)) {
      await writer.submitPage(page);
    }

    final records = await store.recordsForSession(
      uid: 'user-a',
      tenantId: 'tenant-a',
    );
    expect(records, hasLength(2));
    expect(
      records.map((record) => record.targetPath).toSet(),
      <String>{'tenants/tenant-a/stock_takes/${draft.takeId}'},
    );
    expect(records.map((record) => record.operationId).toSet(), hasLength(2));
    for (final record in records) {
      expect(record.kind, TenantPendingMutationKind.stockTakePage);
    }
    // Only the last page says the count is complete.
    final finals = records
        .map((record) => record.payload['isFinalPage'])
        .toList();
    expect(finals.where((value) => value == true), hasLength(1));
  });

  test('two counts queue independently of one another', () async {
    final writer = QueuedTenantStockTakeWriter(
      store: store,
      currentUid: () => 'user-a',
    );

    await writer.submitPage(
      tenantStockTakePages(_stockTakeDraft(takeSuffix: 'a')).single,
    );
    await writer.submitPage(
      tenantStockTakePages(_stockTakeDraft(takeSuffix: 'b')).single,
    );

    final records = await store.recordsForSession(
      uid: 'user-a',
      tenantId: 'tenant-a',
    );
    expect(records, hasLength(2));
    expect(
      records.map((record) => record.targetPath).toSet(),
      hasLength(2),
      reason: 'one path each, so neither waits on the other',
    );
  });

  test('a queued count is drawn as still on its way', () async {
    // The counter's own list must show the take from the moment it is handed
    // in, marked for what it is: the lines are still in the queue behind it.
    final writer = QueuedTenantStockTakeWriter(
      store: store,
      currentUid: () => 'user-a',
    );
    final draft = _stockTakeDraft();
    await writer.submitPage(tenantStockTakePages(draft).single);

    final page = await _overlay(store).getCollectionPage(
      TenantCollectionQuery.forTesting(
        collectionPath: 'tenants/tenant-a/stock_takes',
        limit: 20,
      ),
    );

    expect(page, hasLength(1));
    expect(page.single.data['status'], 'submitting');
    expect(page.single.data['counterUid'], 'user-a');
    expect(page.single.data['businessDate'], '2026-09-13');
    expect(page.single.data['productsInScope'], 9);
    // The counted figures are not projected: they belong to the lines under the
    // take, and the only surface that reads those is a review of counts that
    // have arrived.
    expect(page.single.data.containsKey('lines'), isFalse);
  });

  test('a count queued with no session throws rather than vanishing', () async {
    final writer = QueuedTenantStockTakeWriter(
      store: store,
      currentUid: () => null,
    );

    expect(
      () => writer.submitPage(tenantStockTakePages(_stockTakeDraft()).single),
      throwsA(
        isA<TenantStockTakeException>().having(
          (error) => error.failure,
          'failure',
          TenantStockTakeFailure.forbidden,
        ),
      ),
    );
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

TenantStockTakeDraft _stockTakeDraft({int lines = 1, String takeSuffix = 'a'}) =>
    TenantStockTakeDraft(
      takeId: tenantStockTakeId(
        tenantId: 'tenant-a',
        counterUid: 'user-a',
        requestId: 'stocktake-$takeSuffix',
        businessDate: '2026-09-13',
      ),
      tenantId: 'tenant-a',
      businessDate: '2026-09-13',
      scope: const TenantStockTakeEverything(),
      productsInScope: 9,
      startedAt: DateTime.utc(2026, 9, 13, 6),
      counts: <String, TenantStockTakeCount>{
        for (var i = 0; i < lines; i++)
          'pd-$i': TenantStockTakeCount(
            counted: i,
            seenQuantity: i + 1,
            countedAt: DateTime.utc(2026, 9, 13, 7),
          ),
      },
    );

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

TenantProductRetireIntent _retireIntent({
  String requestId = 'retire-request-1',
  bool retired = true,
}) => _catalogRepository().buildRetireIntent(
  _storedProduct(),
  requestId: requestId,
  retired: retired,
);

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
