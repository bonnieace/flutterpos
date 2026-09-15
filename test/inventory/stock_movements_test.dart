import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/collection_pages.dart';

void main() {
  group('stock movement read model', () {
    test('decodes the three shapes the server actually writes', () {
      final adjustment = _movement(data: _adjustmentData());
      expect(adjustment.source, TenantStockMovementSource.manualAdjustment);
      expect(adjustment.adjustmentType, 'damage');
      expect(adjustment.reason, 'Broken in transit');
      expect(adjustment.actorUid, 'manager-a');
      expect(adjustment.quantityDelta, -3);
      expect(adjustment.previousQuantity, 10);
      expect(adjustment.quantityAfter, 7);
      expect(adjustment.increasesStock, isFalse);
      expect(adjustment.recordedAt, DateTime.utc(2026, 8, 1, 9));

      final restoration = _movement(
        movementId: 'rv_abc_product-1',
        data: _returnData(),
      );
      expect(restoration.source, TenantStockMovementSource.verifiedReturn);
      expect(restoration.sourceId, 'ret-1');
      expect(restoration.quantityAfter, 9);
      expect(restoration.increasesStock, isTrue);
      expect(restoration.reason, isNull);

      // A reconciled sale records no before or after: nothing read the product
      // inside that transaction, so there is no pair to report.
      final sale = _movement(movementId: 'sale_chk-1', data: _saleData());
      expect(sale.source, TenantStockMovementSource.sale);
      expect(sale.quantityDelta, -2);
      expect(sale.previousQuantity, isNull);
      expect(sale.quantityAfter, isNull);
      expect(sale.actorUid, isNull);
    });

    test('an unmodelled source is carried verbatim rather than refused', () {
      // A server deploy may add a source this client does not know. Taking the
      // ledger down for that would be worse than naming it honestly.
      final movement = _movement(
        data: _adjustmentData()..['sourceType'] = 'stock_take_import',
      );

      expect(movement.source, TenantStockMovementSource.other);
      expect(movement.sourceType, 'stock_take_import');
    });

    test('refuses a document that contradicts its own path', () {
      final refused = <String, Map<String, Object?>>{
        'movement-id': _adjustmentData()..['movementId'] = 'sa_other',
        'tenant-id': _adjustmentData()..['tenantId'] = 'tenant-b',
        'product-id': _adjustmentData()..['productId'] = 'product-9',
      };
      for (final entry in refused.entries) {
        expect(
          () => _movement(data: entry.value),
          _code('movement_identity_mismatch'),
          reason: entry.key,
        );
      }

      for (final path in <String>[
        'tenants/tenant-a/products/product-1/stock_movements',
        'tenants/tenant-a/products/product-1/sales/mv-1',
        'tenants/tenant-a/sales/sale-1/stock_movements/mv-1',
        'tenants/tenant-a/products/product-1/stock_movements/mv-1/extra',
      ]) {
        expect(
          () => TenantStockMovement.fromDocument(
            path: path,
            data: _adjustmentData(),
          ),
          _code('invalid_movement_path'),
          reason: path,
        );
      }
    });

    test('refuses arithmetic and quantities that disagree', () {
      final refused = <String, Map<String, Object?>>{
        'does-not-add-up': _adjustmentData()..['quantityAfter'] = 8,
        'half-a-pair': _adjustmentData()..remove('quantityAfter'),
        'zero-change': _adjustmentData()
          ..['quantityDelta'] = 0
          ..['quantityAfter'] = 10,
        'non-integer-change': _adjustmentData()..['quantityDelta'] = -3.0,
      };
      for (final entry in refused.entries) {
        expect(
          () => _movement(data: entry.value),
          throwsA(isA<TenantStockException>()),
          reason: entry.key,
        );
      }
    });

    test('a movement may legitimately leave stock negative', () {
      final movement = _movement(
        data: _adjustmentData()
          ..['previousQuantity'] = -1
          ..['quantityAfter'] = -4,
      );

      expect(movement.previousQuantity, -1);
      expect(movement.quantityAfter, -4);
    });
  });

  group('product stock repository', () {
    test('derives both reads from the session and the product', () async {
      final reader = _StockReader(
        product: _productData(),
        movements: <String, Map<String, Object?>>{'sa_abc': _adjustmentData()},
      );

      final view = await _repository(reader).loadStock(productId: 'product-1');

      expect(reader.documentPaths, <String>[
        'tenants/tenant-a/products/product-1',
      ]);
      expect(
        reader.queries.single.collectionPath,
        'tenants/tenant-a/products/product-1/stock_movements',
      );
      // **Newest first, by `occurredAt`, since 2026-09-14.** Movement IDs are
      // digests and `sale_{saleId}` values, so document order carried no time
      // information at all - which made "what happened to this product most
      // recently" a matter of reading every page and comparing by eye.
      expect(reader.queries.single.descending, isTrue);
      expect(reader.queries.single.order, TenantCollectionOrder.occurredAt);
      expect(reader.queries.single.equalityFilters, isEmpty);
      expect(view.product.quantity, 7);
      expect(view.movements.items.single.id, 'sa_abc');
      expect(view.movements.hasMore, isFalse);
    });

    test('a cashier is refused before any read is issued', () async {
      final reader = _StockReader(
        product: _productData(),
        movements: <String, Map<String, Object?>>{'sa_abc': _adjustmentData()},
      );
      final repository = _repository(reader, role: TenantRole.cashier);

      await expectLater(
        repository.loadStock(productId: 'product-1'),
        _code('stock_ledger_forbidden'),
      );
      await expectLater(
        repository.loadMovements(productId: 'product-1'),
        _code('stock_ledger_forbidden'),
      );
      await expectLater(
        repository.readProduct('product-1'),
        _code('stock_ledger_forbidden'),
      );
      expect(reader.documentPaths, isEmpty);
      expect(reader.queries, isEmpty);
    });

    test('an absent product is reported, never assumed to be empty', () async {
      final reader = _StockReader(
        product: null,
        movements: const <String, Map<String, Object?>>{},
      );

      await expectLater(
        _repository(reader).loadStock(productId: 'product-1'),
        _code('product_unavailable'),
      );
      expect(reader.queries, isEmpty);
    });

    test('a transport that answers outside the scope fails closed', () async {
      // The path proofs in the base repository reject a foreign path outright,
      // so these prove the field-level checks a rule-bypassing document would
      // still have to pass.
      final crossTenant = _StockReader(
        product: _productData(),
        movements: <String, Map<String, Object?>>{
          'sa_abc': _adjustmentData()..['tenantId'] = 'tenant-b',
        },
      );
      await expectLater(
        _repository(crossTenant).loadMovements(productId: 'product-1'),
        // The identity comparison against the document's own path is the first
        // thing that fails, which is the same refusal for the same reason.
        throwsA(isA<TenantStockException>()),
      );

      final foreignPath = _StockReader(
        product: _productData(),
        movements: const <String, Map<String, Object?>>{},
        overridePath: 'tenants/tenant-b/products/product-1/stock_movements/x',
      );
      await expectLater(
        _repository(foreignPath).loadMovements(productId: 'product-1'),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('a product read from another business fails closed', () async {
      final reader = _StockReader(
        product: _productData(),
        movements: const <String, Map<String, Object?>>{},
        productPath: 'tenants/tenant-b/products/product-1',
      );

      await expectLater(
        _repository(reader).readProduct('product-1'),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('pages are bounded and advance a stable cursor', () async {
      final reader = _StockReader(
        product: _productData(),
        // Arranged so "newest first" and "by ID" cannot both hold: the
        // most recent movement is the one whose ID sorts last.
        movements: <String, Map<String, Object?>>{
          'mv-1': _saleData(at: DateTime.utc(2026, 8, 1, 11)),
          'mv-2': _saleData(at: DateTime.utc(2026, 8, 2, 11)),
          'mv-3': _saleData(at: DateTime.utc(2026, 8, 3, 11)),
        },
      );
      final repository = _repository(reader);

      final page = await repository.loadMovements(
        productId: 'product-1',
        pageSize: 2,
      );
      expect(page.items.map((item) => item.id), <String>['mv-3', 'mv-2']);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, endsWith('|mv-2'));

      final last = await repository.loadMovements(
        productId: 'product-1',
        pageSize: 2,
        cursor: page.nextCursor,
      );
      expect(reader.queries.last.startAfterDocumentId, 'mv-2');
      expect(
        reader.queries.last.startAfterOrderValue,
        DateTime.utc(2026, 8, 2, 11),
      );
      expect(last.items.single.id, 'mv-1');
      expect(last.hasMore, isFalse);
      await expectLater(
        repository.loadMovements(productId: 'product-1', pageSize: 51),
        throwsRangeError,
      );
    });
  });

  group('the ledger of a product that may no longer exist', () {
    test('reads the same page the stock route reads', () async {
      // The point of the whole decision recorded in PLAN.md: this is the
      // path-bounded page, not a `productId`-narrowed collection group, and it
      // issues exactly the query the product stock route already issues.
      final reader = _StockReader(
        product: _productData(),
        movements: <String, Map<String, Object?>>{'sa_abc': _adjustmentData()},
      );

      final ledger = await _repository(
        reader,
      ).loadLedger(productId: 'product-1');

      expect(reader.documentPaths, <String>[
        'tenants/tenant-a/products/product-1',
      ]);
      expect(
        reader.queries.single.collectionPath,
        'tenants/tenant-a/products/product-1/stock_movements',
      );
      expect(reader.queries.single.descending, isTrue);
      expect(reader.queries.single.order, TenantCollectionOrder.occurredAt);
      expect(reader.queries.single.equalityFilters, isEmpty);
      expect(ledger.productId, 'product-1');
      expect(ledger.productExists, isTrue);
      expect(ledger.product!.quantity, 7);
      expect(ledger.movements.items.single.id, 'sa_abc');
    });

    test('a deleted product still yields its permanent ledger', () async {
      // An owner or admin may delete a product; `stock_movements` below it is
      // `write: if false` and Firestore does not cascade, so the ledger
      // outlives it. This is the only read in the app that can still state it.
      final reader = _StockReader(
        product: null,
        movements: <String, Map<String, Object?>>{'sa_abc': _adjustmentData()},
      );

      final ledger = await _repository(
        reader,
      ).loadLedger(productId: 'product-1');

      expect(ledger.productExists, isFalse);
      expect(ledger.product, isNull);
      expect(ledger.productId, 'product-1');
      expect(ledger.movements.items.single.id, 'sa_abc');
    });

    test('the stock route still refuses the same absent product', () async {
      // Deliberately unchanged: reading what moved a product is safe once it is
      // gone, and correcting the stock of one that does not exist is not.
      final reader = _StockReader(
        product: null,
        movements: <String, Map<String, Object?>>{'sa_abc': _adjustmentData()},
      );

      await expectLater(
        _repository(reader).loadStock(productId: 'product-1'),
        _code('product_unavailable'),
      );
    });

    test(
      'a product ID that is not a document ID never reaches a path',
      () async {
        // A row of the business-wide feed is where this ID comes from, so unlike
        // the stock route it was never validated by a decoded catalog record.
        final reader = _StockReader(
          product: _productData(),
          movements: const <String, Map<String, Object?>>{},
        );
        final repository = _repository(reader);

        for (final productId in <String>['', 'a/b', '.', '..', 'x' * 1501]) {
          await expectLater(
            repository.loadLedger(productId: productId),
            _code('invalid_product_id'),
            reason: productId,
          );
        }
        expect(reader.documentPaths, isEmpty);
        expect(reader.queries, isEmpty);
      },
    );

    test('a cashier is refused before any read is issued', () async {
      final reader = _StockReader(
        product: _productData(),
        movements: const <String, Map<String, Object?>>{},
      );
      final repository = _repository(reader, role: TenantRole.cashier);

      await expectLater(
        repository.loadLedger(productId: 'product-1'),
        _code('stock_ledger_forbidden'),
      );
      await expectLater(
        repository.findProduct('product-1'),
        _code('stock_ledger_forbidden'),
      );
      expect(reader.documentPaths, isEmpty);
      expect(reader.queries, isEmpty);
    });

    test(
      'a product answered from another business still fails closed',
      () async {
        // Tolerating absence must not tolerate a foreign document: an absent
        // product is a fact about this business, a foreign one is a broken
        // boundary.
        final reader = _StockReader(
          product: _productData(),
          movements: const <String, Map<String, Object?>>{},
          productPath: 'tenants/tenant-b/products/product-1',
        );

        await expectLater(
          _repository(reader).findProduct('product-1'),
          throwsA(isA<TenantScopeViolation>()),
        );
      },
    );

    test('the ledger pages exactly as the stock route does', () async {
      final reader = _StockReader(
        product: null,
        movements: <String, Map<String, Object?>>{
          'mv-1': _saleData(at: DateTime.utc(2026, 8, 1, 11)),
          'mv-2': _saleData(at: DateTime.utc(2026, 8, 2, 11)),
          'mv-3': _saleData(at: DateTime.utc(2026, 8, 3, 11)),
        },
      );
      final repository = _repository(reader);

      final page = await repository.loadLedger(
        productId: 'product-1',
        pageSize: 2,
      );
      expect(page.movements.items.map((item) => item.id), <String>[
        'mv-3',
        'mv-2',
      ]);
      expect(page.movements.hasMore, isTrue);

      final last = await repository.loadLedger(
        productId: 'product-1',
        pageSize: 2,
        cursor: page.movements.nextCursor,
      );
      expect(reader.queries.last.startAfterDocumentId, 'mv-2');
      expect(last.movements.items.single.id, 'mv-1');
      expect(last.movements.hasMore, isFalse);
    });
  });
}

TenantProductStockRepository _repository(
  _StockReader reader, {
  TenantRole role = TenantRole.manager,
}) => TenantProductStockRepository(
  session: TenantSession.active(
    uid: 'manager-a',
    tenantId: 'tenant-a',
    role: role,
  ),
  reader: reader,
);

Matcher _code(String code) => throwsA(
  isA<TenantStockException>().having((error) => error.code, 'code', code),
);

TenantStockMovement _movement({
  String movementId = 'sa_abc',
  required Map<String, Object?> data,
}) => TenantStockMovement.fromDocument(
  path: 'tenants/tenant-a/products/product-1/stock_movements/$movementId',
  data: data,
);

Map<String, Object?> _adjustmentData() => <String, Object?>{
  'movementId': 'sa_abc',
  'tenantId': 'tenant-a',
  'productId': 'product-1',
  'sourceType': 'manual_adjustment',
  'adjustmentType': 'damage',
  'quantityDelta': -3,
  'previousQuantity': 10,
  'quantityAfter': 7,
  'reason': 'Broken in transit',
  'actorUid': 'manager-a',
  'requestId': 'adjust-stock-abcdefgh',
  'occurredAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 9)),
  'recordedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 9)),
};

Map<String, Object?> _returnData() => <String, Object?>{
  'movementId': 'rv_abc_product-1',
  'tenantId': 'tenant-a',
  'productId': 'product-1',
  'sourceType': 'verified_return',
  'sourceId': 'ret-1',
  'verificationId': 'rv_abc',
  'quantityDelta': 2,
  'previousQuantity': 7,
  'quantityAfter': 9,
  'actorUid': 'manager-a',
  'recordedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 10)),
};

Map<String, Object?> _saleData({DateTime? at}) => <String, Object?>{
  'movementId': 'sale_chk-1',
  'tenantId': 'tenant-a',
  'productId': 'product-1',
  'sourceType': 'sale',
  'sourceId': 'chk-1',
  'quantityDelta': -2,
  'lineCount': 1,
  // The ledger is ordered by when the stock moved, which for a sale reconciled
  // later is the sale rather than the write. Every writer sets both.
  'occurredAt': Timestamp.fromDate(at ?? DateTime.utc(2026, 8, 1, 11)),
  'recordedAt': Timestamp.fromDate(at ?? DateTime.utc(2026, 8, 1, 11)),
};

Map<String, Object?> _productData() => <String, Object?>{
  'name': 'Cold lager',
  'SKU': 'LAGER-001',
  'price': 120.5,
  'quantity': 7,
  'categoryId': 'drinks',
};

final class _StockReader implements TenantDataReader {
  _StockReader({
    required this.product,
    required this.movements,
    this.productPath,
    this.overridePath,
  });

  final Map<String, Object?>? product;
  final Map<String, Map<String, Object?>> movements;

  /// Lets a test answer a document read from outside the requested scope.
  final String? productPath;

  /// Lets a test answer a collection page from outside the requested scope.
  final String? overridePath;

  final List<String> documentPaths = <String>[];
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentPaths.add(path);
    final data = product;
    if (data == null) return null;
    return TenantDocumentSnapshot(path: productPath ?? path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    if (overridePath case final path?) {
      return <TenantQueryDocumentSnapshot>[
        TenantQueryDocumentSnapshot(path: path, data: _saleData()),
      ];
    }
    // Ordered and cursored the way Firestore would: this ledger is newest-first
    // by `occurredAt`, and the repository proves the order of what it is given.
    return tenantCollectionPageOf(query, <TenantQueryDocumentSnapshot>[
      for (final entry in movements.entries)
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/${entry.key}',
          data: <String, Object?>{...entry.value, 'movementId': entry.key},
        ),
    ]);
  }
}
