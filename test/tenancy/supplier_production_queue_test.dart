import 'dart:io';

import 'package:flutter_application_1/suppliers/supplier.dart';
import 'package:flutter_application_1/suppliers/supplier_delivery.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// The four queue kinds suppliers and production add, and the two things about
/// them that no earlier kind needed.
///
/// **One record touching many documents.** A delivery page restocks every
/// product it names and a batch restocks the product it makes, while each is
/// addressed to its own record so a refusal strands only that record. The
/// overlay has to draw them over the products, or the stock a delivery brought
/// in would be invisible on the catalog until the queue drained.
///
/// **Waiting for a create on another path.** A delivery naming a supplier or a
/// product this device added a moment ago must not reach the server first.
void main() {
  late Directory directory;
  late Box<dynamic> box;
  late TenantPendingMutationStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('supplier-queue-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('supplier-queue-test');
    store = TenantPendingMutationStore.fromBox(box);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('all four are callables, addressed to their own collections', () {
    for (final kind in <TenantPendingMutationKind>[
      TenantPendingMutationKind.supplierCreate,
      TenantPendingMutationKind.supplierUpdate,
      TenantPendingMutationKind.supplierDeliveryPage,
      TenantPendingMutationKind.productionComplete,
    ]) {
      expect(tenantMutationIsCallable(kind), isTrue, reason: kind.name);
    }
  });

  test('a delivery page may not be addressed to a product', () async {
    // Addressed to the product, a refused page would hold every later stock
    // change to that product behind it.
    await expectLater(
      store.enqueue(
        uid: 'user-a',
        tenantId: 'tenant-a',
        operationId: 'supplier-delivery-sd_1-p000',
        kind: TenantPendingMutationKind.supplierDeliveryPage,
        targetPath: 'tenants/tenant-a/products/prod-bread',
        payload: _deliveryPage(),
      ),
      throwsA(
        isA<TenantPendingMutationException>().having(
          (error) => error.code,
          'code',
          'invalid_target',
        ),
      ),
    );
  });

  test('a queued supplier is in the directory at once', () async {
    final repository = TenantSupplierRepository(
      session: _session(),
      reader: _overlay(store),
    );
    final intent = repository.buildCreateIntent(
      draft: const TenantSupplierDraft(name: 'ABC Distributors'),
      directory: TenantSupplierDirectory(
        suppliers: const <TenantSupplier>[],
        truncated: false,
      ),
      requestId: 'supplier-request-1',
    );
    await QueuedTenantSupplierWriter(
      store: store,
      currentUid: () => 'user-a',
    ).createSupplier(intent);

    final directory = await repository.loadDirectory();

    expect(directory.suppliers.single.name, 'ABC Distributors');
    expect(directory.suppliers.single.active, isTrue);
  });

  group('a queued delivery page', () {
    Future<void> queuePage({int page = 0}) => store.enqueue(
      uid: 'user-a',
      tenantId: 'tenant-a',
      operationId: 'supplier-delivery-sd_1-p${'$page'.padLeft(3, '0')}',
      kind: TenantPendingMutationKind.supplierDeliveryPage,
      targetPath: 'tenants/tenant-a/supplier_deliveries/sd_1',
      payload: _deliveryPage(page: page),
    );

    test('touches the delivery and every product it restocks', () async {
      await queuePage();
      final record = (await store.recordsForSession(
        uid: 'user-a',
        tenantId: 'tenant-a',
      )).single;

      expect(tenantMutationTouchedPaths(record), <String>[
        'tenants/tenant-a/supplier_deliveries/sd_1',
        'tenants/tenant-a/products/prod-bread',
        'tenants/tenant-a/products/prod-milk',
      ]);
    });

    test('raises each product it names, and sets the cost it names', () async {
      await queuePage();
      final overlay = _overlay(store, base: const _Shelf());

      final bread = await overlay.getDocument(
        'tenants/tenant-a/products/prod-bread',
      );
      final milk = await overlay.getDocument(
        'tenants/tenant-a/products/prod-milk',
      );

      expect(bread!.data['quantity'], 40 + 24);
      expect(bread.data['cost'], 45.5);
      // No unit cost on that line, so the recorded cost is left alone.
      expect(milk!.data['quantity'], 5 + 12);
      expect(milk.data['cost'], 30);
    });

    test('shows on a catalog page and in a catalog search', () async {
      await queuePage();
      final overlay = _overlay(store, base: const _Shelf());

      final page = await overlay.getCollectionPage(
        TenantCollectionQuery.forTesting(
          collectionPath: 'tenants/tenant-a/products',
          limit: 10,
        ),
      );
      final search = await overlay.searchTenantProducts(
        TenantProductSearchQuery.forTesting(
          collectionPath: 'tenants/tenant-a/products',
          limit: 10,
        ),
      );

      int quantityOf(List<TenantQueryDocumentSnapshot> rows, String id) =>
          rows.singleWhere((row) => row.path.endsWith('/$id')).data['quantity']
              as int;
      expect(quantityOf(page, 'prod-bread'), 64);
      expect(quantityOf(search, 'prod-bread'), 64);
      // A queued page never invents a product this device holds no copy of.
      expect(page, hasLength(2));
    });

    test('draws the delivery itself, with its totals', () async {
      await queuePage();
      final header = await _overlay(store).getDocument(
        'tenants/tenant-a/supplier_deliveries/sd_1',
      );

      expect(header!.data['supplierId'], 'sp_abc');
      expect(header.data['lineCount'], 2);
      expect(header.data['unitCount'], 36);
      expect(header.data['valueMinor'], 24 * 4550);
      expect(header.data['costlessLineCount'], 1);
    });

    test('stops being drawn once the server refuses it', () async {
      await queuePage();
      final record = (await store.recordsForSession(
        uid: 'user-a',
        tenantId: 'tenant-a',
      )).single;
      await store.markRejected(record, 'invalid-argument');

      final bread = await _overlay(store, base: const _Shelf()).getDocument(
        'tenants/tenant-a/products/prod-bread',
      );

      expect(bread!.data['quantity'], 40);
    });

    test('waits while its supplier or a product is still an unsent create', () async {
      await store.enqueue(
        uid: 'user-a',
        tenantId: 'tenant-a',
        operationId: 'supplier-create-sp_abc',
        kind: TenantPendingMutationKind.supplierCreate,
        targetPath: 'tenants/tenant-a/suppliers/sp_abc',
        payload: const <String, Object?>{'name': 'ABC', 'active': true},
      );
      await queuePage();
      final gateway = _Gateway(holdKind: TenantPendingMutationKind.supplierCreate);

      await _worker(store, gateway).run(_session());

      expect(gateway.submitted, <String>['supplier-create-sp_abc']);

      // The supplier settles - its create is confirmed on the server - and the
      // page goes on the next pass.
      final supplierRecord = (await store.recordsForSession(
        uid: 'user-a',
        tenantId: 'tenant-a',
      )).singleWhere((record) => record.operationId == 'supplier-create-sp_abc');
      await store.markConfirmed(supplierRecord);
      await _worker(store, _Gateway()).run(_session());
      final states = <String, TenantPendingMutationState>{
        for (final record in await store.recordsForSession(
          uid: 'user-a',
          tenantId: 'tenant-a',
        ))
          record.operationId: record.state,
      };
      expect(states['supplier-delivery-sd_1-p000'], TenantPendingMutationState.confirmed);
    });

    test('pages keep their order past the ninth', () async {
      // The queue orders one path's records by when they were queued and then
      // by operation ID as a string, so a page number has to be zero-padded or
      // page ten would drain before page two.
      for (final page in <int>[0, 1, 2, 9, 10, 11]) {
        await queuePage(page: page);
      }
      final gateway = _Gateway();

      await _worker(store, gateway).run(_session());

      expect(gateway.submitted, <String>[
        'supplier-delivery-sd_1-p000',
        'supplier-delivery-sd_1-p001',
        'supplier-delivery-sd_1-p002',
        'supplier-delivery-sd_1-p009',
        'supplier-delivery-sd_1-p010',
        'supplier-delivery-sd_1-p011',
      ]);
    });
  });

  test('the delivery writer queues every page on one path, in order', () async {
    final intent = TenantSupplierDeliveryRepository(
      session: _session(),
      reader: const _Empty(),
    ).buildIntent(
      supplier: TenantSupplier.fromDocument(
        path: 'tenants/tenant-a/suppliers/sp_abc',
        data: const <String, Object?>{'name': 'ABC', 'active': true},
      ),
      reference: 'INV-1',
      lines: <TenantDeliveryLineDraft>[
        for (var index = 0; index < 20; index++)
          TenantDeliveryLineDraft(
            product: TenantProduct.fromDocument(
              path: 'tenants/tenant-a/products/prod-$index',
              data: <String, Object?>{
                'name': 'Product $index',
                'SKU': 'P$index',
                'price': 10,
                'quantity': 0,
                'categoryId': 'cat-a',
              },
            ),
            quantity: '1',
          ),
      ],
      requestId: 'delivery-request-1',
    );
    var signalled = 0;

    final result = await QueuedTenantSupplierDeliveryWriter(
      store: store,
      currentUid: () => 'user-a',
      onQueued: () => signalled++,
    ).receive(intent);

    final records = await store.recordsForSession(
      uid: 'user-a',
      tenantId: 'tenant-a',
    );
    expect(result.operationIds, hasLength(2));
    expect(records.map((record) => record.kind).toSet(), <TenantPendingMutationKind>{
      TenantPendingMutationKind.supplierDeliveryPage,
    });
    expect(records.map((record) => record.targetPath).toSet(), <String>{intent.path});
    expect(records.map((record) => record.payload['page']), <int>[0, 1]);
    // One signal for the whole delivery, not one per page.
    expect(signalled, 1);
  });

  group('a queued production batch', () {
    Future<void> queueBatch() => store.enqueue(
      uid: 'user-a',
      tenantId: 'tenant-a',
      operationId: 'production-complete-pb_1',
      kind: TenantPendingMutationKind.productionComplete,
      targetPath: 'tenants/tenant-a/production_batches/pb_1',
      payload: const <String, Object?>{
        'tenantId': 'tenant-a',
        'batchId': 'pb_1',
        'batchNumber': 'PB-20260924-0001',
        'productId': 'prod-bread',
        'productName': 'White bread loaf',
        'quantity': 100,
        'expenses': <Map<String, Object?>>[
          <String, Object?>{'description': 'Flour', 'amount': 2000},
          <String, Object?>{'description': 'Labour', 'amount': 1000},
        ],
        'totalCostMinor': 300000,
        'unitCostMinor': 3000,
      },
    );

    test('raises its product and sets what one unit cost to make', () async {
      await queueBatch();
      final bread = await _overlay(store, base: const _Shelf()).getDocument(
        'tenants/tenant-a/products/prod-bread',
      );

      expect(bread!.data['quantity'], 140);
      expect(bread.data['cost'], 30);
    });

    test('is drawn as the batch the server will hold', () async {
      await queueBatch();
      final batch = await _overlay(store).getDocument(
        'tenants/tenant-a/production_batches/pb_1',
      );

      expect(batch!.data['batchNumber'], 'PB-20260924-0001');
      expect(batch.data['expenses'], <Map<String, Object?>>[
        <String, Object?>{'description': 'Flour', 'amountMinor': 200000},
        <String, Object?>{'description': 'Labour', 'amountMinor': 100000},
      ]);
      expect(batch.data['actorUid'], 'user-a');
    });

    test('waits while its product is still an unsent create', () async {
      await store.enqueue(
        uid: 'user-a',
        tenantId: 'tenant-a',
        operationId: 'product-create-prod-bread',
        kind: TenantPendingMutationKind.productCreate,
        targetPath: 'tenants/tenant-a/products/prod-bread',
        payload: const <String, Object?>{'name': 'Bread', 'categoryId': 'cat-a'},
      );
      await queueBatch();
      final gateway = _Gateway(holdKind: TenantPendingMutationKind.productCreate);

      await _worker(store, gateway).run(_session());

      expect(gateway.submitted, <String>['product-create-prod-bread']);
    });
  });
}

Map<String, Object?> _deliveryPage({int page = 0}) => <String, Object?>{
  'tenantId': 'tenant-a',
  'deliveryId': 'sd_1',
  'supplierId': 'sp_abc',
  'reference': 'INV-48392',
  'page': page,
  'isFinalPage': true,
  'lines': <Map<String, Object?>>[
    <String, Object?>{
      'productId': 'prod-bread',
      'productName': 'White bread loaf',
      'quantity': 24,
      'unitCost': 45.5,
    },
    <String, Object?>{
      'productId': 'prod-milk',
      'productName': 'Milk 500ml',
      'quantity': 12,
    },
  ],
};

TenantSession _session() => TenantSession.active(
  uid: 'user-a',
  tenantId: 'tenant-a',
  role: TenantRole.manager,
);

TenantPendingMutationWorker _worker(
  TenantPendingMutationStore store,
  _Gateway gateway,
) => TenantPendingMutationWorker(
  store: store,
  submission: gateway,
  confirmation: gateway,
  workerId: 'device-a',
);

TenantPendingMutationOverlayReader _overlay(
  TenantPendingMutationStore store, {
  TenantCacheReadable base = const _Empty(),
}) => TenantPendingMutationOverlayReader(
  base: base,
  store: store,
  currentUid: () => 'user-a',
);

/// Commits everything, except that it can leave one kind uncertain so a pass
/// ends with that kind still unresolved.
final class _Gateway
    implements
        TenantMutationSubmissionGateway,
        TenantMutationConfirmationGateway {
  _Gateway({this.holdKind});

  final TenantPendingMutationKind? holdKind;
  final List<String> submitted = <String>[];

  @override
  Future<Map<String, Object?>?> read(String targetPath) async => null;

  @override
  Future<TenantMutationSubmissionResult> submit(
    TenantPendingMutationRecord record,
  ) async {
    submitted.add(record.operationId);
    return TenantMutationSubmissionResult(
      record.kind == holdKind
          ? TenantMutationSubmissionOutcome.uncertain
          : TenantMutationSubmissionOutcome.committed,
    );
  }
}

final class _Empty implements TenantCacheReadable, TenantProductSearchReader {
  const _Empty();

  @override
  TenantDataReader get cacheOnly => this;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantProducts(
    TenantProductSearchQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}

/// A base reader holding two products.
final class _Shelf implements TenantCacheReadable, TenantProductSearchReader {
  const _Shelf();

  static const Map<String, Map<String, Object?>> _products =
      <String, Map<String, Object?>>{
        'tenants/tenant-a/products/prod-bread': <String, Object?>{
          'name': 'White bread loaf',
          'SKU': 'BR-1',
          'price': 65,
          'cost': 40,
          'quantity': 40,
          'categoryId': 'cat-a',
          'searchName': 'white bread loaf',
        },
        'tenants/tenant-a/products/prod-milk': <String, Object?>{
          'name': 'Milk 500ml',
          'SKU': 'MK-1',
          'price': 50,
          'cost': 30,
          'quantity': 5,
          'categoryId': 'cat-a',
          'searchName': 'milk 500ml',
        },
      };

  @override
  TenantDataReader get cacheOnly => this;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final data = _products[path];
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => _rows();

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantProducts(
    TenantProductSearchQuery query,
  ) async => _rows();

  List<TenantQueryDocumentSnapshot> _rows() => <TenantQueryDocumentSnapshot>[
    for (final entry in _products.entries)
      TenantQueryDocumentSnapshot(path: entry.key, data: entry.value),
  ];
}
