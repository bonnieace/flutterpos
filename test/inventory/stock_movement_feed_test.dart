import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/collection_pages.dart';

void main() {
  group('stock movement feed repository', () {
    test('the business-wide page is bound to the session alone', () async {
      final reader = _GroupReader(<String, Map<String, Object?>>{
        'product-1/sa_abc': _adjustmentMovement(),
      });

      final page = await _repository(reader).loadMovements();

      // A group query names no path, so this filter is the only thing that
      // narrows it to one business - and it is the same condition the
      // Firestore rule authorizes the page by.
      expect(reader.queries.single.collectionId, 'stock_movements');
      expect(reader.queries.single.equalityFilters, <String, Object?>{
        'tenantId': 'tenant-a',
      });
      expect(reader.queries.single.startAfterDocumentPath, isNull);
      expect(page.items.single.id, 'sa_abc');
      expect(page.items.single.productId, 'product-1');
      expect(page.source, isNull);
      expect(page.isSourceScoped, isFalse);
      expect(page.hasMore, isFalse);
    });

    test('a narrowed page carries the typed source beside it', () async {
      final reader = _GroupReader(<String, Map<String, Object?>>{
        'product-1/sa_abc': _adjustmentMovement(),
        'product-1/sale_co-1': _saleMovement(),
      });

      final page = await _repository(
        reader,
      ).loadMovementsOfSource(source: TenantStockMovementSource.sale);

      expect(reader.queries.single.equalityFilters, <String, Object?>{
        'tenantId': 'tenant-a',
        'sourceType': 'sale',
      });
      expect(page.items.single.id, 'sale_co-1');
      expect(page.source, TenantStockMovementSource.sale);
      expect(page.isSourceScoped, isTrue);
    });

    test(
      'an unmodelled source is listed but can never be filtered for',
      () async {
        final reader = _GroupReader(<String, Map<String, Object?>>{
          'product-1/wo_abc': _adjustmentMovement()
            ..['sourceType'] = 'stock_take_import',
        });
        final repository = _repository(reader);

        // A server deploy adding a source is not evidence of anything wrong, so
        // the unnarrowed page still names it honestly.
        final page = await repository.loadMovements();
        expect(page.items.single.source, TenantStockMovementSource.other);
        expect(page.items.single.sourceType, 'stock_take_import');

        // There is no wire value to filter by, so asking for one is refused
        // before any query rather than issuing a page that can never match.
        await expectLater(
          repository.loadMovementsOfSource(
            source: TenantStockMovementSource.other,
          ),
          _code('unfilterable_movement_source'),
        );
        expect(reader.queries.length, 1);
      },
    );

    test('a cashier is refused before any read is issued', () async {
      final reader = _GroupReader(<String, Map<String, Object?>>{
        'product-1/sa_abc': _adjustmentMovement(),
      });
      final repository = _repository(reader, role: TenantRole.cashier);

      await expectLater(
        repository.loadMovements(),
        _code('stock_movement_feed_forbidden'),
      );
      await expectLater(
        repository.loadMovementsOfSource(
          source: TenantStockMovementSource.sale,
        ),
        _code('stock_movement_feed_forbidden'),
      );
      expect(reader.queries, isEmpty);
      expect(
        TenantStockMovementFeedRepository.canReadInSession(
          TenantSession.active(
            uid: 'cashier-a',
            tenantId: 'tenant-a',
            role: TenantRole.cashier,
          ),
        ),
        isFalse,
      );
    });

    test('a group answer below another business fails closed', () async {
      // The extended child-path proof rejects a foreign path outright, which is
      // the whole reason a group read is allowed here at all.
      final foreign = _GroupReader(
        const <String, Map<String, Object?>>{},
        overridePath: 'tenants/tenant-b/products/product-1/stock_movements/m1',
      );
      await expectLater(
        _repository(foreign).loadMovements(),
        throwsA(isA<TenantScopeViolation>()),
      );

      // A transport that ignored the tenant filter and answered with a
      // document naming another business is refused by the field-level check
      // behind the path proof.
      final crossTenant = _GroupReader(<String, Map<String, Object?>>{
        'product-1/sa_abc': _adjustmentMovement()..['tenantId'] = 'tenant-b',
      }, ignoreFilters: true);
      await expectLater(
        _repository(crossTenant).loadMovements(),
        throwsA(isA<TenantStockException>()),
      );
    });

    test(
      'a narrowed page answering with another source fails closed',
      () async {
        final reader = _GroupReader(<String, Map<String, Object?>>{
          'product-1/sa_abc': _adjustmentMovement(),
        }, ignoreFilters: true);

        await expectLater(
          _repository(
            reader,
          ).loadMovementsOfSource(source: TenantStockMovementSource.sale),
          _code('foreign_movement_source'),
        );
      },
    );

    test('a movement that contradicts itself hides the page', () async {
      final reader = _GroupReader(<String, Map<String, Object?>>{
        'product-1/sa_abc': _adjustmentMovement()..['quantityAfter'] = 8,
      });

      await expectLater(
        _repository(reader).loadMovements(),
        _code('inconsistent_movement_quantities'),
      );
    });

    test('pages are bounded and resume from a whole document path', () async {
      // **The order is the business's timeline, not the product tree.** These
      // three are deliberately arranged so "newest first" and "by path" cannot
      // both be true: the most recent movement is below `product-2`, which
      // sorts last by path, and the oldest shares a product with the newest.
      final reader = _GroupReader(<String, Map<String, Object?>>{
        'product-1/sa_1': _adjustmentMovement(at: DateTime.utc(2026, 8, 1, 9)),
        'product-1/sa_2': _adjustmentMovement(at: DateTime.utc(2026, 8, 2, 9)),
        'product-2/sa_1': _adjustmentMovement(at: DateTime.utc(2026, 8, 3, 9)),
      });
      final repository = _repository(reader);

      final page = await repository.loadMovements(pageSize: 2);
      expect(page.items.map((item) => '${item.productId}/${item.id}'), <String>[
        'product-2/sa_1',
        'product-1/sa_2',
      ]);
      expect(page.hasMore, isTrue);
      // One movement ID is unique only below its own product, so only a whole
      // path can say where the next page resumes - carried here beside the
      // instant, because two movements recorded in the same millisecond are
      // separated by nothing else.
      expect(
        page.nextCursor,
        endsWith('|tenants/tenant-a/products/product-1/stock_movements/sa_2'),
      );

      final last = await repository.loadMovements(
        pageSize: 2,
        cursor: page.nextCursor,
      );
      expect(
        reader.queries.last.startAfterDocumentPath,
        'tenants/tenant-a/products/product-1/stock_movements/sa_2',
      );
      expect(
        reader.queries.last.startAfterOrderValue,
        DateTime.utc(2026, 8, 2, 9),
      );
      expect(last.items.single.productId, 'product-1');
      expect(last.items.single.id, 'sa_1');
      expect(last.hasMore, isFalse);
      expect(last.nextCursor, isNull);

      await expectLater(
        repository.loadMovements(pageSize: 51),
        throwsRangeError,
      );
      await expectLater(
        repository.loadMovementsOfSource(
          source: TenantStockMovementSource.sale,
          pageSize: 0,
        ),
        throwsRangeError,
      );
    });
  });

  group('stock movement source', () {
    test('every modelled wire value is distinct and round-trips', () {
      final wireValues = <String>{};
      for (final source in TenantStockMovementSource.values) {
        if (source == TenantStockMovementSource.other) continue;
        expect(wireValues.add(source.wireValue), isTrue, reason: source.name);
        expect(TenantStockMovementSource.parse(source.wireValue), source);
        expect(source.label, isNotEmpty);
      }
      expect(TenantStockMovementSource.other.wireValue, isEmpty);
      expect(
        TenantStockMovementSource.parse('stock_take_import'),
        TenantStockMovementSource.other,
      );
    });
  });
}

TenantStockMovementFeedRepository _repository(
  _GroupReader reader, {
  TenantRole role = TenantRole.manager,
}) => TenantStockMovementFeedRepository(
  session: TenantSession.active(
    uid: 'manager-a',
    tenantId: 'tenant-a',
    role: role,
  ),
  reader: reader,
  groupReader: reader,
);

Matcher _code(String code) => throwsA(
  isA<TenantStockException>().having((error) => error.code, 'code', code),
);

/// The exact entry `adjustStock` appends below the product.
Map<String, Object?> _adjustmentMovement({DateTime? at}) => <String, Object?>{
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
  // Both, as `adjustStock` writes them in one transaction. The feed is ordered
  // by `occurredAt`, so a fixture without one is a document no writer produces.
  'occurredAt': Timestamp.fromDate(at ?? DateTime.utc(2026, 8, 1, 9)),
  'recordedAt': Timestamp.fromDate(at ?? DateTime.utc(2026, 8, 1, 9)),
};

/// The entry nightly reconciliation writes for a confirmed sale: no actor and
/// no before/after, because the writer never read the product.
Map<String, Object?> _saleMovement() => <String, Object?>{
  'movementId': 'sale_co-1',
  'tenantId': 'tenant-a',
  'productId': 'product-1',
  'sourceType': 'sale',
  'sourceId': 'co-1',
  'quantityDelta': -2,
  'occurredAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 8)),
  'recordedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 8)),
};

final class _GroupReader
    implements TenantDocumentReader, TenantCollectionGroupReader {
  _GroupReader(this.movements, {this.overridePath, this.ignoreFilters = false});

  /// Keyed by `productId/movementId`, which is the identity a group page has.
  final Map<String, Map<String, Object?>> movements;

  /// Lets a test answer a group page from outside the requested scope.
  final String? overridePath;

  /// Lets a test answer a narrowed page with a document the filter excludes.
  final bool ignoreFilters;

  final List<TenantCollectionGroupQuery> queries =
      <TenantCollectionGroupQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionGroupPage(
    TenantCollectionGroupQuery query,
  ) async {
    queries.add(query);
    if (overridePath case final path?) {
      return <TenantQueryDocumentSnapshot>[
        TenantQueryDocumentSnapshot(path: path, data: _adjustmentMovement()),
      ];
    }
    // Ordered, cursored and filtered the way Firestore would, because the
    // repository proves the order of what it is handed - and this feed is
    // newest-first by `occurredAt`, so a fake answering in path order is
    // answering a query it was not asked.
    final documents = <TenantQueryDocumentSnapshot>[
      for (final key in movements.keys)
        () {
          final parts = key.split('/');
          // Every writer repeats the identity its own path encodes, so the fake
          // does too rather than making each case restate it.
          return TenantQueryDocumentSnapshot(
            path:
                'tenants/tenant-a/products/${parts[0]}/stock_movements/'
                '${parts[1]}',
            data: <String, Object?>{
              ...movements[key]!,
              'productId': parts[0],
              'movementId': parts[1],
            },
          );
        }(),
    ];
    return tenantCollectionGroupPageOf(
      ignoreFilters
          ? TenantCollectionGroupQuery.forTesting(
              collectionId: query.collectionId,
              limit: query.limit,
              startAfterDocumentPath: query.startAfterDocumentPath,
              startAfterOrderValue: query.startAfterOrderValue,
              descending: query.descending,
              order: query.order,
            )
          : query,
      documents,
    );
  }
}
