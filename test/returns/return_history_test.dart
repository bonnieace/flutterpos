import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/returns/returns.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonical return read model', () {
    test('accepts the pending document the create rule allows', () {
      final record = TenantReturn.fromDocument(
        path: 'tenants/tenant-a/returns/ret-1',
        data: _pending(),
      );

      expect(record.id, 'ret-1');
      expect(record.tenantId, 'tenant-a');
      expect(record.saleId, 'co-1');
      expect(record.createdBy, 'user-a');
      expect(record.reason, 'Customer returned a damaged bottle');
      expect(record.status, TenantReturnStatus.pending);
      expect(record.isVerified, isFalse);
      expect(record.verification, isNull);
      expect(record.returnedUnits, 3);
      expect(record.lines.first.productId, 'product-1');
      expect(record.lines.first.productName, 'Tusker');
      expect(record.recordedAt, DateTime.utc(2026, 7, 31, 12));
    });

    test('accepts the evidence the verification callable writes back', () {
      final record = TenantReturn.fromDocument(
        path: 'tenants/tenant-a/returns/ret-1',
        data: _verified(),
      );

      expect(record.status, TenantReturnStatus.verified);
      expect(record.isVerified, isTrue);
      expect(record.verification!.verifiedBy, 'manager-a');
      expect(record.verification!.stockRestorationId, 'rv_abc');
      expect(record.verification!.verifiedAt, DateTime.utc(2026, 8, 1, 6));
    });

    test('refuses the historical "restored" spelling', () {
      // #110: the server writes `status: verified` beside `verified: true` and
      // `stockRestored: true` in one transaction, and no longer reads
      // `restored`. A document carrying it is a shape SIT does not hold.
      expect(
        () => TenantReturn.fromDocument(
          path: 'tenants/tenant-a/returns/ret-1',
          data: _verified(overrides: <String, Object?>{'status': 'restored'}),
        ),
        _code('invalid_return_document'),
      );
    });

    test('refuses a document that disagrees with its own path', () {
      expect(
        () => TenantReturn.fromDocument(
          path: 'tenants/tenant-b/returns/ret-1',
          data: _pending(),
        ),
        _code('return_identity_mismatch'),
      );
      // The create rule binds the document ID into the document itself.
      expect(
        () => TenantReturn.fromDocument(
          path: 'tenants/tenant-a/returns/ret-9',
          data: _pending(),
        ),
        _code('return_identity_mismatch'),
      );
      expect(
        () => TenantReturn.fromDocument(
          path: 'tenants/tenant-a/sales/ret-1',
          data: _pending(),
        ),
        _code('invalid_return_path'),
      );
      expect(
        () => TenantReturn.fromDocument(
          path: 'tenants/tenant-a/returns/ret-1/extra/deeper',
          data: _pending(),
        ),
        _code('invalid_return_path'),
      );
    });

    test('refuses a state the verification guard would contradict', () {
      final refused = <String, Map<String, Object?>>{
        // The callable treats any one of these as terminal, so a document that
        // claims to be pending while carrying restoration evidence is one it
        // would never verify.
        'pending-but-verified-flag': <String, Object?>{'verified': true},
        'pending-but-stock-restored': <String, Object?>{'stockRestored': true},
        'verified-status-but-flag-false': <String, Object?>{
          'status': 'verified',
          'verified': false,
        },
        'pending-with-verifier': <String, Object?>{'verifiedBy': 'manager-a'},
        'pending-with-restoration-id': <String, Object?>{
          'stockRestorationId': 'rv_abc',
        },
        'unknown-status': <String, Object?>{'status': 'cancelled'},
        'non-boolean-flag': <String, Object?>{'verified': 'yes'},
        // The create rule requires an auditable reason, so a document without
        // one was not written through that contract.
        'missing-reason': <String, Object?>{'reason': null},
        'blank-reason': <String, Object?>{'reason': '  '},
      };

      for (final entry in refused.entries) {
        expect(
          () => TenantReturn.fromDocument(
            path: 'tenants/tenant-a/returns/ret-1',
            data: _pending(overrides: entry.value),
          ),
          throwsA(isA<TenantReturnException>()),
          reason: entry.key,
        );
      }
    });

    test('a verified return must carry every server-written field', () {
      for (final field in <String>[
        'verifiedBy',
        'verifiedAt',
        'stockRestorationId',
      ]) {
        expect(
          () => TenantReturn.fromDocument(
            path: 'tenants/tenant-a/returns/ret-1',
            data: _verified(overrides: <String, Object?>{field: null}),
          ),
          throwsA(isA<TenantReturnException>()),
          reason: field,
        );
      }
    });

    test('refuses lines the server would not restore stock from', () {
      final refused = <String, Object?>{
        'no-lines': <Object?>[],
        'not-a-list': 'product-1',
        'zero-quantity': <Object?>[
          <String, Object?>{'productId': 'product-1', 'quantity': 0},
        ],
        'fractional-quantity': <Object?>[
          <String, Object?>{'productId': 'product-1', 'quantity': 1.5},
        ],
        'missing-product': <Object?>[
          <String, Object?>{'quantity': 1},
        ],
        'duplicate-product': <Object?>[
          <String, Object?>{'productId': 'product-1', 'quantity': 1},
          <String, Object?>{'productId': 'product-1', 'quantity': 2},
        ],
        'non-map-line': <Object?>['product-1'],
      };

      for (final entry in refused.entries) {
        expect(
          () => TenantReturn.fromDocument(
            path: 'tenants/tenant-a/returns/ret-1',
            data: _pending(
              overrides: <String, Object?>{'itemsReturned': entry.value},
            ),
          ),
          throwsA(isA<TenantReturnException>()),
          reason: entry.key,
        );
      }
    });

    test('refuses a line filed under the old itemId name', () {
      // #110: `normalizeReturnStockLines` no longer reads `itemId`, so a line
      // under the old name names no product on either side.
      expect(
        () => TenantReturn.fromDocument(
          path: 'tenants/tenant-a/returns/ret-1',
          data: _pending(
            overrides: <String, Object?>{
              'itemsReturned': <Object?>[
                <String, Object?>{'itemId': 'product-9', 'quantity': 4},
              ],
            },
          ),
        ),
        // `_requiredDocumentId` answers for the missing field, so the refusal
        // is the document-level one rather than the line-shape one.
        _code('invalid_return_document'),
      );
    });

    test('a return that cannot say which days it belongs to is refused', () {
      // #110: both were nullable while returns recorded before 2026-09-06 were
      // still about. SIT holds none.
      for (final field in <String>['businessDate', 'recordedOn']) {
        expect(
          () => TenantReturn.fromDocument(
            path: 'tenants/tenant-a/returns/ret-1',
            data: _pending()..remove(field),
          ),
          _code('invalid_return_business_date'),
          reason: '$field is required',
        );
      }
    });
  });

  group('return history repository', () {
    test('pages every business return without a sale filter', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/returns/ret-1': _pending(),
        'tenants/tenant-a/returns/ret-2': _verified(returnId: 'ret-2'),
        'tenants/tenant-a/returns/ret-3': _pending(
          returnId: 'ret-3',
          overrides: <String, Object?>{'saleId': 'co-2'},
        ),
      });

      final page = await _repository(reader).loadReturns();

      expect(page.items.map((record) => record.id), <String>[
        'ret-3',
        'ret-2',
        'ret-1',
      ]);
      expect(reader.queries.single.equalityFilters, <String, Object?>{
        'tenantId': 'tenant-a',
      });
      expect(reader.queries.single.descending, isTrue);
    });

    test('pages one sale returns newest first from the tenant path', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/returns/ret-1': _pending(),
        'tenants/tenant-a/returns/ret-2': _verified(returnId: 'ret-2'),
        'tenants/tenant-a/returns/ret-3': _pending(
          returnId: 'ret-3',
          overrides: <String, Object?>{'saleId': 'co-2'},
        ),
      });

      final page = await _repository(reader).loadSaleReturns(saleId: 'co-1');

      expect(page.items.map((record) => record.id), <String>['ret-2', 'ret-1']);
      expect(page.verified.map((record) => record.id), <String>['ret-2']);
      expect(page.pending.map((record) => record.id), <String>['ret-1']);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
      final query = reader.queries.single;
      expect(query.collectionPath, 'tenants/tenant-a/returns');
      expect(query.descending, isTrue);
      expect(query.equalityFilters, <String, Object?>{'saleId': 'co-1'});
    });

    test('resumes a page from its cursor', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/returns/ret-1': _pending(),
        'tenants/tenant-a/returns/ret-2': _pending(returnId: 'ret-2'),
      });

      final first = await _repository(
        reader,
      ).loadSaleReturns(saleId: 'co-1', pageSize: 1);
      expect(first.items.single.id, 'ret-2');
      expect(first.hasMore, isTrue);
      expect(first.nextCursor, 'ret-2');

      final second = await _repository(
        reader,
      ).loadSaleReturns(saleId: 'co-1', pageSize: 1, cursor: 'ret-2');
      expect(second.items.single.id, 'ret-1');
      expect(second.hasMore, isFalse);
      expect(reader.queries.last.startAfterDocumentId, 'ret-2');
    });

    test('a return naming another sale fails the page closed', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/returns/ret-1': _pending(
          overrides: <String, Object?>{'saleId': 'co-2'},
        ),
      }, ignoreFilters: true);

      await expectLater(
        _repository(reader).loadSaleReturns(saleId: 'co-1'),
        throwsA(_returnCode('return_sale_mismatch')),
      );
    });

    test('a cross-tenant response fails closed', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/returns/ret-1': _pending(),
      }, collectionResponsePath: 'tenants/tenant-b/returns/ret-1');

      await expectLater(
        _repository(reader).loadSaleReturns(saleId: 'co-1'),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('an invalid sale ID is refused before any read', () async {
      final reader = _Reader(const <String, Map<String, Object?>>{});

      await expectLater(
        _repository(reader).loadSaleReturns(saleId: 'sales/co-1'),
        throwsA(_returnCode('invalid_sale_id')),
      );
      expect(reader.queries, isEmpty);
    });

    test('a cashier reads returns, because the rule is deliberately wide', () {
      // Pinned on purpose: the remaining returnable quantity of a sale depends
      // on every prior return against it, including a colleague's. Narrowing
      // this boundary has to change this assertion deliberately.
      expect(
        () => TenantReturnHistoryRepository(
          session: TenantSession.active(
            uid: 'user-a',
            tenantId: 'tenant-a',
            role: TenantRole.cashier,
          ),
          reader: _Reader(const <String, Map<String, Object?>>{}),
        ),
        returnsNormally,
      );
    });
  });
}

TenantReturnHistoryRepository _repository(_Reader reader) =>
    TenantReturnHistoryRepository(
      session: TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.cashier,
      ),
      reader: reader,
    );

Matcher _returnCode(String code) =>
    isA<TenantReturnException>().having((error) => error.code, 'code', code);

Matcher _code(String code) => throwsA(_returnCode(code));

Map<String, Object?> _pending({
  String returnId = 'ret-1',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'returnId': returnId,
    'tenantId': 'tenant-a',
    'saleId': 'co-1',
    'businessDate': '2026-07-31',
    'recordedOn': '2026-07-31',
    'createdBy': 'user-a',
    'status': 'pending',
    'reason': 'Customer returned a damaged bottle',
    'itemsReturned': <Object?>[
      <String, Object?>{
        'productId': 'product-1',
        'productName': 'Tusker',
        'quantity': 2,
      },
      <String, Object?>{'productId': 'product-2', 'quantity': 1},
    ],
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

Map<String, Object?> _verified({
  String returnId = 'ret-1',
  Map<String, Object?>? overrides,
}) {
  final data = _pending(returnId: returnId);
  data.addAll(<String, Object?>{
    'status': 'verified',
    'verified': true,
    'verifiedBy': 'manager-a',
    'verifiedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 6)),
    'stockRestored': true,
    'stockRestoredAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 6)),
    'stockRestorationId': 'rv_abc',
  });
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

final class _Reader implements TenantDataReader {
  _Reader(
    this._documents, {
    this.collectionResponsePath,
    this.ignoreFilters = false,
  });

  final Map<String, Map<String, Object?>> _documents;
  final String? collectionResponsePath;
  final bool ignoreFilters;
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final data = _documents[path];
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    final paths = _documents.keys.toList()..sort();
    if (query.descending) {
      paths.sort((left, right) => right.compareTo(left));
    }
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final path in paths) {
      if (!path.startsWith('${query.collectionPath}/')) continue;
      final id = path.substring('${query.collectionPath}/'.length);
      final cursor = query.startAfterDocumentId;
      if (cursor != null && id.compareTo(cursor) >= 0) continue;
      final data = _documents[path]!;
      final matchesFilters =
          ignoreFilters ||
          query.equalityFilters.entries.every(
            (filter) => data[filter.key] == filter.value,
          );
      if (!matchesFilters) continue;
      matches.add(
        TenantQueryDocumentSnapshot(
          path: collectionResponsePath ?? path,
          data: data,
        ),
      );
      if (matches.length >= query.limit) break;
    }
    return matches;
  }
}
