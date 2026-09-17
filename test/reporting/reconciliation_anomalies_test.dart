import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('anomaly read model', () {
    test('accepts the record the sale trigger writes', () {
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: 'tenants/tenant-a/reconciliation_anomalies/sale_abc',
        data: _saleAnomaly(),
      );

      expect(anomaly.id, 'sale_abc');
      expect(anomaly.tenantId, 'tenant-a');
      expect(anomaly.kind, TenantReconciliationAnomalyKind.invalidSaleLines);
      expect(anomaly.saleId, 'checkout-a');
      expect(anomaly.invalidLineCount, 2);
      expect(anomaly.jobId, isNull);
      expect(anomaly.productId, isNull);
      expect(anomaly.recordedAt, DateTime.utc(2026, 8, 1, 2, 30));
    });

    test('accepts every stock record, including a negative observed stock', () {
      // Checkout may legitimately drive a product below zero, so a signed
      // observed quantity is a real record rather than a broken one.
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: 'tenants/tenant-a/reconciliation_anomalies/stock_abc',
        data: _stockAnomaly(
          overrides: <String, Object?>{
            'expectedQuantity': 4,
            'observedQuantity': -3,
            'variance': -7,
          },
        ),
      );

      expect(anomaly.kind, TenantReconciliationAnomalyKind.stockShortOfLedger);
      expect(anomaly.isStockAnomaly, isTrue);
      expect(anomaly.productId, 'product-a');
      expect(anomaly.quantityVariance, -7);
    });

    test('refuses a stock record that cannot explain its own difference', () {
      // `variance` is exactly `observedQuantity - expectedQuantity` in the one
      // transaction that writes all three, so a record about a discrepancy that
      // misstates the discrepancy is not evidence of anything.
      expect(
        () => TenantReconciliationAnomaly.fromDocument(
          path: 'tenants/tenant-a/reconciliation_anomalies/stock_abc',
          data: _stockAnomaly(overrides: <String, Object?>{'variance': 5}),
        ),
        _throwsCode('inconsistent_anomaly'),
      );
    });

    test('refuses a stock variance of nothing at all', () {
      // That kind is chosen only once the chain is valid and every movement was
      // readable, which leaves a non-zero variance as the only reason it exists.
      expect(
        () => TenantReconciliationAnomaly.fromDocument(
          path: 'tenants/tenant-a/reconciliation_anomalies/stock_abc',
          data: _stockAnomaly(
            overrides: <String, Object?>{
              'expectedQuantity': 9,
              'observedQuantity': 9,
              'variance': 0,
            },
          ),
        ),
        _throwsCode('inconsistent_anomaly'),
      );
    });

    test('a broken checkpoint chain may legitimately have no variance', () {
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: 'tenants/tenant-a/reconciliation_anomalies/stock_abc',
        data: _stockAnomaly(
          overrides: <String, Object?>{
            'anomalyType': 'checkpoint_chain_invalid',
            'expectedQuantity': 9,
            'observedQuantity': 9,
            'variance': 0,
          },
        ),
      );

      expect(
        anomaly.kind,
        TenantReconciliationAnomalyKind.checkpointChainInvalid,
      );
      expect(anomaly.quantityVariance, 0);
    });

    test('accepts a shift variance and its signed figures', () {
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: 'tenants/tenant-a/reconciliation_anomalies/shift_abc',
        data: _shiftAnomaly(),
      );

      expect(anomaly.kind, TenantReconciliationAnomalyKind.shiftVariance);
      expect(anomaly.isShiftAnomaly, isTrue);
      expect(anomaly.shiftId, 'shift-a');
      expect(anomaly.salesVariance, -12.5);
      expect(anomaly.transactionVariance, 2);
    });

    test('a tender variance carries all nine figures and its context', () {
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: 'tenants/tenant-a/reconciliation_anomalies/tender_abc',
        data: _tenderAnomaly(),
      );

      expect(anomaly.kind, TenantReconciliationAnomalyKind.shiftTenderVariance);
      expect(anomaly.isTenderAnomaly, isTrue);
      expect(anomaly.isShiftAnomaly, isTrue);
      expect(anomaly.declaredMinor[CheckoutTender.cash], 120000);
      expect(anomaly.expectedMinor[CheckoutTender.card], 900);
      expect(anomaly.tenderVarianceMinor[CheckoutTender.cash], -5000);
      expect(anomaly.tenderVarianceMinor[CheckoutTender.mpesa], 0);
      // Money the sales could not attribute is carried rather than dropped, so
      // three expected figures that do not sum to the shift can say why.
      expect(anomaly.expectedUnattributedMinor, 3000);
      expect(anomaly.businessDate, '2026-08-01');
      expect(anomaly.staffId, 'user-a');
      expect(anomaly.resolution, TenantReconciliationResolution.open);
    });

    test('a declared figure larger than a count still decodes', () {
      // The bound on a money figure is a thousand times the bound on a count of
      // things, and decoding one through the other refused a large but
      // perfectly legitimate declaration as a malformed record.
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: 'tenants/tenant-a/reconciliation_anomalies/tender_abc',
        data: _tenderAnomaly(
          overrides: <String, Object?>{
            'declaredCashMinor': 1000000000000,
            'expectedCashMinor': 0,
            'cashVarianceMinor': 1000000000000,
          },
        ),
      );

      expect(anomaly.declaredMinor[CheckoutTender.cash], 1000000000000);
    });

    test('a tender variance that cannot explain itself is refused', () {
      for (final override in <Map<String, Object?>>[
        // A difference that is not declared minus expected.
        <String, Object?>{'cashVarianceMinor': -4000},
        // A figure the writer always records together with the rest.
        <String, Object?>{'declaredCardMinor': null},
        <String, Object?>{'expectedMpesaMinor': null},
        // Written only when the declaration did not match, so one that agrees
        // on all three contradicts its own writer.
        <String, Object?>{
          'declaredCashMinor': 125000,
          'declaredCardMinor': 900,
          'cashVarianceMinor': 0,
          'cardVarianceMinor': 0,
        },
      ]) {
        expect(
          () => TenantReconciliationAnomaly.fromDocument(
            path: 'tenants/tenant-a/reconciliation_anomalies/tender_abc',
            data: _tenderAnomaly(overrides: override),
          ),
          throwsA(
            isA<TenantReconciliationException>().having(
              (error) => error.code,
              'code',
              'inconsistent_anomaly',
            ),
          ),
          reason: override.keys.join(','),
        );
      }
    });

    test('a missing declaration states nothing it could not have compared', () {
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: 'tenants/tenant-a/reconciliation_anomalies/tender_abc',
        data: _tenderAnomaly(
          overrides: <String, Object?>{
            'anomalyType': 'missing_tender_declaration',
            'declaredCashMinor': null,
            'declaredMpesaMinor': null,
            'declaredCardMinor': null,
            'cashVarianceMinor': null,
            'mpesaVarianceMinor': null,
            'cardVarianceMinor': null,
          },
        ),
      );

      expect(
        anomaly.kind,
        TenantReconciliationAnomalyKind.missingTenderDeclaration,
      );
      expect(anomaly.declaredMinor[CheckoutTender.cash], isNull);
      // The expected side survives: it is what the shift should have declared.
      expect(anomaly.expectedMinor[CheckoutTender.cash], 125000);

      // Figures on it would be a comparison the writer could not have made.
      expect(
        () => TenantReconciliationAnomaly.fromDocument(
          path: 'tenants/tenant-a/reconciliation_anomalies/tender_abc',
          data: _tenderAnomaly(
            overrides: <String, Object?>{
              'anomalyType': 'missing_tender_declaration',
              'declaredMpesaMinor': null,
              'declaredCardMinor': null,
              'mpesaVarianceMinor': null,
              'cardVarianceMinor': null,
            },
          ),
        ),
        throwsA(isA<TenantReconciliationException>()),
      );
    });

    test('an unknown resolution is carried as unsettled, never as settled', () {
      // Over-reporting an open difference is recoverable; hiding one is not.
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: 'tenants/tenant-a/reconciliation_anomalies/tender_abc',
        data: _tenderAnomaly(
          overrides: <String, Object?>{'resolution': 'deferred'},
        ),
      );

      expect(anomaly.resolution, TenantReconciliationResolution.other);
      expect(anomaly.resolution.isOpen, isTrue);
      expect(TenantReconciliationResolution.acknowledged.isOpen, isFalse);
    });

    test('a shift whose totals could not be read carries neither figure', () {
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: 'tenants/tenant-a/reconciliation_anomalies/shift_abc',
        data: _shiftAnomaly(
          overrides: <String, Object?>{
            'anomalyType': 'invalid_or_missing_shift',
            'salesVariance': null,
            'transactionVariance': null,
          },
        ),
      );

      expect(
        anomaly.kind,
        TenantReconciliationAnomalyKind.invalidOrMissingShift,
      );
      expect(anomaly.salesVariance, isNull);
      expect(anomaly.transactionVariance, isNull);
    });

    test('refuses a missing shift that still claims a measured variance', () {
      // The writer records both variances only when all four figures could be
      // read, and calls that record `shift_variance`.
      expect(
        () => TenantReconciliationAnomaly.fromDocument(
          path: 'tenants/tenant-a/reconciliation_anomalies/shift_abc',
          data: _shiftAnomaly(
            overrides: <String, Object?>{
              'anomalyType': 'invalid_or_missing_shift',
            },
          ),
        ),
        _throwsCode('inconsistent_anomaly'),
      );
    });

    test('refuses a shift variance that varies by nothing', () {
      expect(
        () => TenantReconciliationAnomaly.fromDocument(
          path: 'tenants/tenant-a/reconciliation_anomalies/shift_abc',
          data: _shiftAnomaly(
            overrides: <String, Object?>{
              'salesVariance': 0,
              'transactionVariance': 0,
            },
          ),
        ),
        _throwsCode('inconsistent_anomaly'),
      );
    });

    test('refuses a sale anomaly with no unusable line', () {
      expect(
        () => TenantReconciliationAnomaly.fromDocument(
          path: 'tenants/tenant-a/reconciliation_anomalies/sale_abc',
          data: _saleAnomaly(
            overrides: <String, Object?>{'invalidLineCount': 0},
          ),
        ),
        _throwsCode('inconsistent_anomaly'),
      );
    });

    test('an unmodelled kind is carried verbatim rather than refused', () {
      // A server deploy that records a new kind of difference is not evidence
      // of anything wrong, and hiding a real difference would be far worse.
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: 'tenants/tenant-a/reconciliation_anomalies/other_abc',
        data: <String, Object?>{
          'tenantId': 'tenant-a',
          'anomalyType': 'price_drift',
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
        },
      );

      expect(anomaly.kind, TenantReconciliationAnomalyKind.other);
      expect(anomaly.kindValue, 'price_drift');
    });

    test('a record with no recorded time still describes the difference', () {
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: 'tenants/tenant-a/reconciliation_anomalies/sale_abc',
        data: _saleAnomaly(overrides: <String, Object?>{'createdAt': null}),
      );

      expect(anomaly.recordedAt, isNull);
      expect(anomaly.invalidLineCount, 2);
    });

    test('refuses a record naming another business', () {
      expect(
        () => TenantReconciliationAnomaly.fromDocument(
          path: 'tenants/tenant-a/reconciliation_anomalies/sale_abc',
          data: _saleAnomaly(overrides: <String, Object?>{'tenantId': 'other'}),
        ),
        _throwsCode('anomaly_identity_mismatch'),
      );
    });

    test('refuses a path outside the anomalies collection', () {
      expect(
        () => TenantReconciliationAnomaly.fromDocument(
          path: 'tenants/tenant-a/reconciliation_jobs/sale_abc',
          data: _saleAnomaly(),
        ),
        _throwsCode('invalid_anomaly_path'),
      );
    });

    test('every modelled kind round-trips a distinct wire value', () {
      final values = <String>{};
      for (final kind in TenantReconciliationAnomalyKind.values) {
        if (kind == TenantReconciliationAnomalyKind.other) continue;
        expect(values.add(kind.wireValue), isTrue, reason: kind.name);
        expect(TenantReconciliationAnomalyKind.parse(kind.wireValue), kind);
      }
      // Ten since the stock disagreement split by direction: short and over are
      // different events with different causes, and one kind covering both put
      // them in front of a shopkeeper as the same fact.
      expect(values, hasLength(10));
    });

    test('refuses a stock record whose sign contradicts its own kind', () {
      // **The kind is the sign.** The server picks `stock_short_of_ledger` only
      // for a negative variance and `stock_over_ledger` only for a positive one,
      // so a record calling itself short while its figures say the books are
      // over is a writer and a reader that disagree. Drawing it either way would
      // put a sentence in front of somebody that its own numbers contradict.
      for (final contradiction in <String, Map<String, Object?>>{
        'short with the books over': <String, Object?>{
          'anomalyType': 'stock_short_of_ledger',
          'expectedQuantity': 7,
          'observedQuantity': 10,
          'variance': 3,
        },
        'over with the books short': <String, Object?>{
          'anomalyType': 'stock_over_ledger',
          'expectedQuantity': 10,
          'observedQuantity': 7,
          'variance': -3,
        },
        'short with no difference at all': <String, Object?>{
          'anomalyType': 'stock_short_of_ledger',
          'expectedQuantity': 7,
          'observedQuantity': 7,
          'variance': 0,
        },
      }.entries) {
        expect(
          () => TenantReconciliationAnomaly.fromDocument(
            path: 'tenants/tenant-a/reconciliation_anomalies/stock_abc',
            data: _stockAnomaly(overrides: contradiction.value),
          ),
          throwsA(isA<TenantReconciliationException>()),
          reason: contradiction.key,
        );
      }
    });

    test('reads a record whose books are over its ledger', () {
      final anomaly = TenantReconciliationAnomaly.fromDocument(
        path: 'tenants/tenant-a/reconciliation_anomalies/stock_abc',
        data: _stockAnomaly(
          overrides: <String, Object?>{
            'anomalyType': 'stock_over_ledger',
            'expectedQuantity': 7,
            'observedQuantity': 10,
            'variance': 3,
          },
        ),
      );

      expect(anomaly.kind, TenantReconciliationAnomalyKind.stockOverLedger);
      expect(anomaly.isStockAnomaly, isTrue);
      expect(anomaly.quantityVariance, 3);
    });
  });

  group('anomaly repository', () {
    test('reads one business-wide page with no filter and no index', () async {
      final reader = _Reader(
        page: <TenantQueryDocumentSnapshot>[
          _snapshot('sale_a', _saleAnomaly()),
          _snapshot('stock_b', _stockAnomaly()),
        ],
      );

      final page = await _repository(reader).loadPage();

      expect(page.items, hasLength(2));
      expect(page.kind, isNull);
      expect(reader.queries.single.equalityFilters, isEmpty);
      expect(reader.queries.single.descending, isFalse);
      expect(
        reader.queries.single.collectionPath,
        'tenants/tenant-a/reconciliation_anomalies',
      );
    });

    test('narrows to one kind with a single equality filter', () async {
      final reader = _Reader(
        page: <TenantQueryDocumentSnapshot>[
          _snapshot('sale_a', _saleAnomaly()),
          _snapshot('stock_b', _stockAnomaly()),
        ],
      );

      final page = await _repository(
        reader,
      ).loadPage(kind: TenantReconciliationAnomalyKind.stockShortOfLedger);

      expect(
        page.items.single.kind,
        TenantReconciliationAnomalyKind.stockShortOfLedger,
      );
      expect(reader.queries.single.equalityFilters, {
        'anomalyType': 'stock_short_of_ledger',
      });
    });

    test('refuses to ask for a kind it does not model', () async {
      // `other` names every unmodelled kind, so it identifies no stored value.
      final reader = _Reader();

      await expectLater(
        _repository(
          reader,
        ).loadPage(kind: TenantReconciliationAnomalyKind.other),
        _failsWithCode('unfilterable_anomaly_kind'),
      );
      expect(reader.queries, isEmpty);
    });

    test('pages forward on the last document ID', () async {
      final reader = _Reader(
        page: <TenantQueryDocumentSnapshot>[
          _snapshot('sale_a', _saleAnomaly()),
          _snapshot('sale_b', _saleAnomaly()),
          _snapshot('sale_c', _saleAnomaly()),
        ],
      );
      final repository = _repository(reader);

      final first = await repository.loadPage(pageSize: 2);
      expect(first.items, hasLength(2));
      expect(first.hasMore, isTrue);
      expect(first.nextCursor, 'sale_b');

      final second = await repository.loadPage(
        pageSize: 2,
        cursor: first.nextCursor,
      );
      expect(second.items.single.id, 'sale_c');
      expect(second.hasMore, isFalse);
    });

    test('fails closed on a response from another business', () async {
      // The base repository's exact-child proof answers first and is the
      // stronger refusal: a transport answering outside this tenant is a broken
      // boundary rather than one unreadable record.
      final reader = _Reader(
        page: <TenantQueryDocumentSnapshot>[
          _snapshot(
            'sale_a',
            _saleAnomaly(tenantId: 'tenant-b'),
            tenantId: 'tenant-b',
          ),
        ],
        ignoreFilters: true,
      );

      await expectLater(
        _repository(reader).loadPage(),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test(
      'fails closed when a record in this path names another business',
      () async {
        final reader = _Reader(
          page: <TenantQueryDocumentSnapshot>[
            _snapshot('sale_a', _saleAnomaly(tenantId: 'tenant-b')),
          ],
          ignoreFilters: true,
        );

        await expectLater(
          _repository(reader).loadPage(),
          _failsWithCode('anomaly_identity_mismatch'),
        );
      },
    );

    test(
      'fails closed when a narrowed page answers with another kind',
      () async {
        // A filtered page returning foreign rows is a broken boundary, not rows
        // to quietly skip past.
        final reader = _Reader(
          page: <TenantQueryDocumentSnapshot>[
            _snapshot('sale_a', _saleAnomaly()),
          ],
          ignoreFilters: true,
        );

        await expectLater(
          _repository(
            reader,
          ).loadPage(kind: TenantReconciliationAnomalyKind.stockShortOfLedger),
          _failsWithCode('foreign_anomaly_kind'),
        );
      },
    );

    test('refuses a cashier before issuing any read', () async {
      final reader = _Reader();

      await expectLater(
        _repository(reader, role: TenantRole.cashier).loadPage(),
        _failsWithCode('anomalies_forbidden'),
      );
      expect(reader.queries, isEmpty);
    });

    test('reads for every role that reads the runs it explains', () {
      expect(
        TenantReconciliationAnomalyRepository.allowedRoles,
        TenantReconciliationStatusRepository.allowedRoles,
      );
    });
  });
}

TenantReconciliationAnomalyRepository _repository(
  TenantDataReader reader, {
  TenantRole role = TenantRole.manager,
}) => TenantReconciliationAnomalyRepository(
  session: _session(role: role),
  reader: reader,
);

TenantSession _session({TenantRole role = TenantRole.manager}) =>
    TenantSession.fromMembership(uid: 'user-a', membership: _membership(role));

TenantMembership _membership(TenantRole role) => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: 'Tenant A',
  tenantSlug: 'tenant-a',
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

Matcher _throwsCode(String code) => throwsA(
  isA<TenantReconciliationException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

Matcher _failsWithCode(String code) => throwsA(
  isA<TenantReconciliationException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

Map<String, Object?> _saleAnomaly({
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) => _document(<String, Object?>{
  'tenantId': tenantId,
  'sourceType': 'sale',
  'sourceId': 'checkout-a',
  'anomalyType': 'invalid_sale_lines',
  'invalidLineCount': 2,
  'observedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 29)),
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
}, overrides);

Map<String, Object?> _stockAnomaly({
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) => _document(<String, Object?>{
  'tenantId': tenantId,
  'productId': 'product-a',
  'jobId': 'rj_abc',
  'anomalyType': 'stock_short_of_ledger',
  'expectedQuantity': 10,
  'observedQuantity': 7,
  'variance': -3,
  'mutatesStock': false,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 31)),
}, overrides);

Map<String, Object?> _shiftAnomaly({
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) => _document(<String, Object?>{
  'tenantId': tenantId,
  'shiftId': 'shift-a',
  'jobId': 'rj_abc',
  'anomalyType': 'shift_variance',
  'salesVariance': -12.5,
  'transactionVariance': 2,
  'mutatesShift': false,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 31)),
}, overrides);

/// A tender variance whose three differences each explain themselves.
Map<String, Object?> _tenderAnomaly({
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) => _document(<String, Object?>{
  'tenantId': tenantId,
  'shiftId': 'shift-a',
  'jobId': 'rj_abc',
  'businessDate': '2026-08-01',
  'staffId': 'user-a',
  'anomalyType': 'shift_tender_variance',
  'declaredCashMinor': 120000,
  'declaredMpesaMinor': 34050,
  'declaredCardMinor': 0,
  'expectedCashMinor': 125000,
  'expectedMpesaMinor': 34050,
  'expectedCardMinor': 900,
  'expectedUnattributedMinor': 3000,
  'cashVarianceMinor': -5000,
  'mpesaVarianceMinor': 0,
  'cardVarianceMinor': -900,
  'resolution': 'open',
  'mutatesShift': false,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 31)),
}, overrides);

Map<String, Object?> _document(
  Map<String, Object?> base,
  Map<String, Object?>? overrides,
) {
  final data = Map<String, Object?>.of(base);
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

TenantQueryDocumentSnapshot _snapshot(
  String id,
  Map<String, Object?> data, {
  String tenantId = 'tenant-a',
}) => TenantQueryDocumentSnapshot(
  path: 'tenants/$tenantId/reconciliation_anomalies/$id',
  data: data,
);

final class _Reader implements TenantDataReader {
  _Reader({
    this.page = const <TenantQueryDocumentSnapshot>[],
    this.ignoreFilters = false,
  });

  final List<TenantQueryDocumentSnapshot> page;

  /// Answers regardless of the repository's own filter, which is the only
  /// honest way to exercise a check that exists for a transport ignoring it.
  final bool ignoreFilters;
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    final cursor = query.startAfterDocumentId;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final snapshot in page) {
      final id = snapshot.path.split('/').last;
      if (cursor != null && id.compareTo(cursor) <= 0) continue;
      final matchesFilters = query.equalityFilters.entries.every(
        (filter) => snapshot.data[filter.key] == filter.value,
      );
      if (!ignoreFilters && !matchesFilters) continue;
      matches.add(snapshot);
      if (matches.length >= query.limit) break;
    }
    return matches;
  }
}
