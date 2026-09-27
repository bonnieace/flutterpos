import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/collection_pages.dart';

void main() {
  group('stock adjustment read model', () {
    test('decodes the record adjustStock writes', () {
      final record = _record(data: _adjustmentData());

      expect(record.id, 'sa_abc');
      expect(record.tenantId, 'tenant-a');
      expect(record.productId, 'product-1');
      expect(record.sourceType, 'manual_adjustment');
      expect(record.adjustmentType, 'damage');
      expect(record.type, TenantStockAdjustmentType.damage);
      expect(record.reason, 'Broken in transit');
      expect(record.actorUid, 'manager-a');
      expect(record.requestId, 'adjust-stock-abcdefgh');
      expect(record.quantityDelta, -3);
      expect(record.previousQuantity, 10);
      expect(record.quantityAfter, 7);
      expect(record.increasesStock, isFalse);
      expect(record.recordedAt, DateTime.utc(2026, 8, 1, 9));
    });

    test('an unmodelled category is carried verbatim rather than refused', () {
      // A server deploy may add a category this client does not know. Taking a
      // business's whole correction record down for that would be worse than
      // naming it honestly.
      final record = _record(
        data: _adjustmentData()..['adjustmentType'] = 'stock_take_import',
      );

      expect(record.type, isNull);
      expect(record.adjustmentType, 'stock_take_import');
    });

    test('refuses a document that contradicts its own path', () {
      expect(
        () => _record(data: _adjustmentData()..['tenantId'] = 'tenant-b'),
        _code('adjustment_identity_mismatch'),
      );

      for (final path in <String>[
        'tenants/tenant-a/stock_adjustments',
        'tenants/tenant-a/audit_logs/sa_abc',
        'tenants/tenant-a/products/product-1/stock_adjustments/sa_abc',
        'tenants/tenant-a/stock_adjustments/sa_abc/extra',
      ]) {
        expect(
          () => TenantStockAdjustmentRecord.fromDocument(
            path: path,
            data: _adjustmentData(),
          ),
          _code('invalid_adjustment_path'),
          reason: path,
        );
      }
    });

    test('refuses figures that disagree with themselves', () {
      final refused = <String, Map<String, Object?>>{
        'does-not-add-up': _adjustmentData()..['quantityAfter'] = 8,
        // `adjustStock` reads the product inside its transaction, so unlike a
        // reconciled sale movement there is no shape here that legitimately
        // omits a before or an after.
        'missing-after': _adjustmentData()..remove('quantityAfter'),
        'missing-before': _adjustmentData()..remove('previousQuantity'),
        'zero-change': _adjustmentData()
          ..['quantityDelta'] = 0
          ..['quantityAfter'] = 10,
        'non-integer-change': _adjustmentData()..['quantityDelta'] = -3.0,
        'missing-product': _adjustmentData()..remove('productId'),
        'product-path': _adjustmentData()..['productId'] = 'other/product-1',
        'missing-reason': _adjustmentData()..remove('reason'),
        'missing-actor': _adjustmentData()..remove('actorUid'),
      };
      for (final entry in refused.entries) {
        expect(
          () => _record(data: entry.value),
          throwsA(isA<TenantStockException>()),
          reason: entry.key,
        );
      }
    });

    test('a correction may legitimately leave stock negative', () {
      final record = _record(
        data: _adjustmentData()
          ..['previousQuantity'] = -1
          ..['quantityAfter'] = -4,
      );

      expect(record.previousQuantity, -1);
      expect(record.quantityAfter, -4);
    });
  });

  group('stock adjustment feed repository', () {
    test('the business-wide page is derived from the session alone', () async {
      final reader = _FeedReader(<String, Map<String, Object?>>{
        'sa_abc': _adjustmentData(),
      });

      final page = await _repository(reader).loadAdjustments();

      expect(
        reader.queries.single.collectionPath,
        'tenants/tenant-a/stock_adjustments',
      );
      // **Newest first, by when it was made, since 2026-09-25** - by
      // `createdAt` from 2026-09-14, when the server heard of it. An adjustment
      // ID is `sa_` plus a digest, so document order carries no time
      // information, and an adjustment made offline arrives hours late.
      expect(reader.queries.single.descending, isTrue);
      expect(reader.queries.single.order, TenantCollectionOrder.occurredAt);
      expect(reader.queries.single.equalityFilters, isEmpty);
      expect(page.items.single.id, 'sa_abc');
      expect(page.productId, isNull);
      expect(page.isProductScoped, isFalse);
      expect(page.hasMore, isFalse);
    });

    test('a product page carries exactly one equality filter', () async {
      final reader = _FeedReader(<String, Map<String, Object?>>{
        'sa_abc': _adjustmentData(),
        'sa_def': _adjustmentData()..['productId'] = 'product-9',
      });

      final page = await _repository(
        reader,
      ).loadProductAdjustments(productId: 'product-1');

      expect(reader.queries.single.equalityFilters, <String, Object?>{
        'productId': 'product-1',
      });
      expect(reader.queries.single.descending, isTrue);
      expect(reader.queries.single.order, TenantCollectionOrder.occurredAt);
      expect(page.items.single.id, 'sa_abc');
      expect(page.productId, 'product-1');
      expect(page.isProductScoped, isTrue);
    });

    test('a cashier is refused before any read is issued', () async {
      final reader = _FeedReader(<String, Map<String, Object?>>{
        'sa_abc': _adjustmentData(),
      });
      final repository = _repository(reader, role: TenantRole.cashier);

      await expectLater(
        repository.loadAdjustments(),
        _code('stock_adjustments_forbidden'),
      );
      await expectLater(
        repository.loadProductAdjustments(productId: 'product-1'),
        _code('stock_adjustments_forbidden'),
      );
      expect(reader.queries, isEmpty);
    });

    test('a product filter that is not a document ID never queries', () async {
      final reader = _FeedReader(const <String, Map<String, Object?>>{});

      await expectLater(
        _repository(reader).loadProductAdjustments(productId: '../product-1'),
        _code('invalid_product_filter'),
      );
      expect(reader.queries, isEmpty);
    });

    test('a transport that answers outside the scope fails closed', () async {
      // The path proofs in the base repository reject a foreign path outright,
      // so these prove the field-level checks a rule-bypassing document would
      // still have to pass.
      final crossTenant = _FeedReader(<String, Map<String, Object?>>{
        'sa_abc': _adjustmentData()..['tenantId'] = 'tenant-b',
      });
      await expectLater(
        _repository(crossTenant).loadAdjustments(),
        // The identity comparison against the document's own path is the first
        // thing that fails, which is the same refusal for the same reason.
        throwsA(isA<TenantStockException>()),
      );

      final foreignPath = _FeedReader(
        const <String, Map<String, Object?>>{},
        overridePath: 'tenants/tenant-b/stock_adjustments/sa_abc',
      );
      await expectLater(
        _repository(foreignPath).loadAdjustments(),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test(
      'a filtered page answering for another product fails closed',
      () async {
        // A page narrowed to one product that returns another one is a broken
        // boundary, not a row to quietly skip past.
        final reader = _FeedReader(<String, Map<String, Object?>>{
          'sa_abc': _adjustmentData()..['productId'] = 'product-9',
        }, ignoreFilters: true);

        await expectLater(
          _repository(reader).loadProductAdjustments(productId: 'product-1'),
          _code('foreign_product_adjustment'),
        );
      },
    );

    test('pages are bounded and advance a stable cursor', () async {
      // Deliberately recorded out of ID order, so "newest first" and "by ID"
      // cannot both be true of the result: `sa_1` is the most recent.
      final reader = _FeedReader(<String, Map<String, Object?>>{
        'sa_1': _adjustmentData(recordedAt: DateTime.utc(2026, 8, 3, 9)),
        'sa_2': _adjustmentData(recordedAt: DateTime.utc(2026, 8, 2, 9)),
        'sa_3': _adjustmentData(recordedAt: DateTime.utc(2026, 8, 1, 9)),
      });
      final repository = _repository(reader);

      final page = await repository.loadAdjustments(pageSize: 2);
      expect(page.items.map((item) => item.id), <String>['sa_1', 'sa_2']);
      expect(page.hasMore, isTrue);
      // The instant and the document, because two records written in the same
      // millisecond are separated only by the second.
      expect(page.nextCursor, endsWith('|sa_2'));

      final last = await repository.loadAdjustments(
        pageSize: 2,
        cursor: page.nextCursor,
      );
      expect(reader.queries.last.startAfterDocumentId, 'sa_2');
      expect(
        reader.queries.last.startAfterOrderValue,
        DateTime.utc(2026, 8, 2, 9),
      );
      expect(last.items.single.id, 'sa_3');
      expect(last.hasMore, isFalse);
      expect(last.nextCursor, isNull);

      await expectLater(
        repository.loadAdjustments(pageSize: 51),
        throwsRangeError,
      );
      await expectLater(
        repository.loadProductAdjustments(productId: 'product-1', pageSize: 0),
        throwsRangeError,
      );
    });
  });
}

TenantStockAdjustmentFeedRepository _repository(
  _FeedReader reader, {
  TenantRole role = TenantRole.manager,
}) => TenantStockAdjustmentFeedRepository(
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

TenantStockAdjustmentRecord _record({
  String adjustmentId = 'sa_abc',
  required Map<String, Object?> data,
}) => TenantStockAdjustmentRecord.fromDocument(
  path: 'tenants/tenant-a/stock_adjustments/$adjustmentId',
  data: data,
);

/// The exact immutable record `functions/src/operations/stock.ts` creates.
Map<String, Object?> _adjustmentData({
  DateTime? recordedAt,
  DateTime? occurredAt,
}) => <String, Object?>{
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
  'occurredAt': Timestamp.fromDate(
    occurredAt ?? recordedAt ?? DateTime.utc(2026, 8, 1, 9),
  ),
  'createdAt': Timestamp.fromDate(recordedAt ?? DateTime.utc(2026, 8, 1, 9)),
};

final class _FeedReader implements TenantDataReader {
  _FeedReader(
    this.adjustments, {
    this.overridePath,
    this.ignoreFilters = false,
  });

  final Map<String, Map<String, Object?>> adjustments;

  /// Lets a test answer a collection page from outside the requested scope.
  final String? overridePath;

  /// Lets a test answer a filtered page with a document the filter excludes.
  final bool ignoreFilters;

  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    if (overridePath case final path?) {
      return <TenantQueryDocumentSnapshot>[
        TenantQueryDocumentSnapshot(path: path, data: _adjustmentData()),
      ];
    }
    // Ordered, cursored and filtered the way Firestore would, because the
    // repository proves the order of what it is handed - and since the feed is
    // newest-first by `occurredAt`, a fake answering in ID order is answering a
    // query it was not asked.
    final documents = <TenantQueryDocumentSnapshot>[
      for (final entry in adjustments.entries)
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/${entry.key}',
          data: entry.value,
        ),
    ];
    if (ignoreFilters) {
      return tenantCollectionPageOf(
        TenantCollectionQuery.forTesting(
          collectionPath: query.collectionPath,
          limit: query.limit,
          startAfterDocumentId: query.startAfterDocumentId,
          startAfterOrderValue: query.startAfterOrderValue,
          descending: query.descending,
          order: query.order,
        ),
        documents,
      );
    }
    return tenantCollectionPageOf(query, documents);
  }
}
