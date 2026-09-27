import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shift amendment read model', () {
    test('decodes the record amendShiftSummary writes', () {
      final record = _record(data: _amendmentData());

      expect(record.id, 'amend_abc');
      expect(record.tenantId, 'tenant-a');
      expect(record.shiftId, 'shift-1');
      expect(record.staffId, 'cashier-a');
      expect(record.businessDate, '2026-08-04');
      expect(record.sourceType, 'reconciliation_shift_variance');
      expect(record.expectationId, 'se_2026-08-04_shift-1');
      expect(record.expectationGeneration, 'gen-9');
      expect(record.previousTotalSalesMinor, 11500);
      expect(record.previousTransactionCount, 1);
      expect(record.previousRepresentationsAgreed, isTrue);
      expect(record.totalSalesMinor, 34500);
      expect(record.transactionCount, 3);
      expect(record.salesVarianceMinor, -23000);
      expect(record.transactionVariance, -2);
      expect(record.clearedAnomalyId, 'sv_shift-1_gen-9');
      expect(record.reason, 'Late sales arrived after the close.');
      expect(record.actorUid, 'owner-a');
      expect(record.requestId, 'amend-shift-abcdefgh');
      expect(record.recordedAt, DateTime.utc(2026, 8, 4, 15, 30));
    });

    test('reports what the correction moved and in which direction', () {
      final understated = _record(data: _amendmentData());
      expect(understated.overstatedSales, isFalse);
      expect(understated.changedSales, isTrue);
      expect(understated.changedTransactionCount, isTrue);
      expect(understated.clearedListedDifference, isTrue);

      // The other direction: the shift had claimed more than its sales prove.
      final overstated = _record(
        data: _amendmentData()
          ..['previousTotalSalesMinor'] = 34500
          ..['previousTransactionCount'] = 3
          ..['totalSalesMinor'] = 11500
          ..['transactionCount'] = 1
          ..['salesVarianceMinor'] = 23000
          ..['transactionVariance'] = 2,
      );
      expect(overstated.overstatedSales, isTrue);
    });

    test('a correction that moved only the count says so', () {
      final record = _record(
        data: _amendmentData()
          ..['totalSalesMinor'] = 11500
          ..['salesVarianceMinor'] = 0
          ..['transactionCount'] = 2
          ..['transactionVariance'] = -1,
      );

      expect(record.changedSales, isFalse);
      expect(record.changedTransactionCount, isTrue);
    });

    test('an unmodelled source is carried verbatim rather than refused', () {
      // A server deploy may start recording another kind of correction here.
      // Taking a business's whole correction trail down for that would be worse
      // than naming it honestly.
      final record = _record(
        data: _amendmentData()..['sourceType'] = 'operator_stock_take',
      );

      expect(record.sourceType, 'operator_stock_take');
    });

    test('a listed difference may legitimately be absent', () {
      // Null is a real answer: no difference was listed under this generation,
      // or the record at that ID described something else and was left alone.
      final record = _record(
        data: _amendmentData()..['clearedAnomalyId'] = null,
      );

      expect(record.clearedAnomalyId, isNull);
      expect(record.clearedListedDifference, isFalse);
    });

    test('refuses a document that contradicts its own path', () {
      expect(
        () => _record(data: _amendmentData()..['tenantId'] = 'tenant-b'),
        _code('amendment_identity_mismatch'),
      );
      // Unlike a stock adjustment, this record repeats its own ID, so a record
      // that names another amendment is refused rather than trusted.
      expect(
        () => _record(data: _amendmentData()..['amendmentId'] = 'amend_other'),
        _code('amendment_identity_mismatch'),
      );

      for (final path in <String>[
        'tenants/tenant-a/shift_amendments',
        'tenants/tenant-a/audit_logs/amend_abc',
        'tenants/tenant-a/shifts/shift-1/shift_amendments/amend_abc',
        'tenants/tenant-a/shift_amendments/amend_abc/extra',
      ]) {
        expect(
          () => TenantShiftAmendmentRecord.fromDocument(
            path: path,
            data: _amendmentData(),
          ),
          _code('invalid_amendment_path'),
          reason: path,
        );
      }
    });

    test('refuses a record that claims it changed the counted cash', () {
      // The one property that makes this collection safe to show at all. A
      // record claiming otherwise is either a server that changed its guarantee
      // without this client knowing, or a document no server wrote - and
      // neither may be presented as an ordinary correction.
      for (final value in <Object?>[true, null, 'false', 0]) {
        expect(
          () => _record(data: _amendmentData()..['mutatesCountedCash'] = value),
          _code('amendment_mutates_cash'),
          reason: '$value',
        );
      }
      expect(
        () => _record(data: _amendmentData()..remove('mutatesCountedCash')),
        _code('amendment_mutates_cash'),
      );
    });

    test('refuses counts that disagree with the difference they report', () {
      // Whole counts from a single comparison, so the identity is exact.
      expect(
        () => _record(data: _amendmentData()..['transactionVariance'] = -1),
        _code('inconsistent_amendment_counts'),
      );
      expect(
        () => _record(data: _amendmentData()..['transactionCount'] = 4),
        _code('inconsistent_amendment_counts'),
      );
    });

    test('refuses money that disagrees when the shift said it agreed', () {
      expect(
        () => _record(data: _amendmentData()..['salesVarianceMinor'] = -22999),
        _code('inconsistent_amendment_money'),
      );
    });

    test(
      'allows money that disagrees when the shift said it did not agree',
      () {
        // The recorded variance is measured from the major-unit total the
        // verifier compares, which may legitimately differ from the stored
        // minor units. When it does, the amendment says so through this field
        // and overwrites both. Asserting the identity unconditionally would
        // refuse exactly the inconsistent shifts this correction repairs.
        final record = _record(
          data: _amendmentData()
            ..['previousRepresentationsAgreed'] = false
            ..['salesVarianceMinor'] = -22999,
        );

        expect(record.previousRepresentationsAgreed, isFalse);
        expect(record.salesVarianceMinor, -22999);
      },
    );

    test('refuses a record that cannot say who corrected it or why', () {
      final refused = <String, Map<String, Object?>>{
        'missing-reason': _amendmentData()..remove('reason'),
        'blank-reason': _amendmentData()..['reason'] = '  ',
        'short-reason': _amendmentData()..['reason'] = 'no',
        'padded-reason': _amendmentData()..['reason'] = ' Late sales ',
        'control-reason': _amendmentData()..['reason'] = 'Late\u0000sales',
        'long-reason': _amendmentData()..['reason'] = 'a' * 501,
        'missing-actor': _amendmentData()..remove('actorUid'),
        'path-actor': _amendmentData()..['actorUid'] = 'users/owner-a',
        'missing-shift': _amendmentData()..remove('shiftId'),
        'missing-staff': _amendmentData()..remove('staffId'),
        'missing-expectation': _amendmentData()..remove('expectationId'),
        'missing-generation': _amendmentData()..remove('expectationGeneration'),
        'missing-date': _amendmentData()..remove('businessDate'),
        'malformed-date': _amendmentData()..['businessDate'] = '04-08-2026',
        'missing-agreement': _amendmentData()
          ..remove('previousRepresentationsAgreed'),
        'non-bool-agreement': _amendmentData()
          ..['previousRepresentationsAgreed'] = 'true',
        'negative-total': _amendmentData()..['totalSalesMinor'] = -1,
        'non-integer-total': _amendmentData()..['totalSalesMinor'] = 34500.0,
        'missing-previous': _amendmentData()..remove('previousTotalSalesMinor'),
        'bad-instant': _amendmentData()..['createdAt'] = 'yesterday',
      };
      for (final entry in refused.entries) {
        expect(
          () => _record(data: entry.value),
          throwsA(isA<TenantReconciliationException>()),
          reason: entry.key,
        );
      }
    });

    test('a record with no recorded instant is still readable', () {
      // The correction happened; only its time is missing. Refusing it would
      // hide a rewrite of a closed shift, which is the worse outcome.
      final record = _record(data: _amendmentData()..remove('createdAt'));

      expect(record.recordedAt, isNull);
      expect(record.requestId, 'amend-shift-abcdefgh');
    });

    test('a record with no request ID is still readable', () {
      final record = _record(data: _amendmentData()..remove('requestId'));

      expect(record.requestId, isNull);
    });
  });

  group('shift amendment feed repository', () {
    test('the business-wide page is derived from the session alone', () async {
      final reader = _FeedReader(<String, Map<String, Object?>>{
        'amend_abc': _amendmentData(),
      });

      final page = await _repository(reader).loadAmendments();

      expect(
        reader.queries.single.collectionPath,
        'tenants/tenant-a/shift_amendments',
      );
      // An amendment ID is a digest of the actor, operation, business, and
      // request, so document order carries no time information and a
      // newest-first page would be a lie. Ascending key order is also servable
      // by Firestore's automatic index.
      expect(reader.queries.single.descending, isFalse);
      expect(reader.queries.single.equalityFilters, isEmpty);
      expect(page.items.single.id, 'amend_abc');
      expect(page.shiftId, isNull);
      expect(page.isShiftScoped, isFalse);
      expect(page.hasMore, isFalse);
    });

    test('a shift page carries exactly one equality filter', () async {
      final reader = _FeedReader(<String, Map<String, Object?>>{
        'amend_abc': _amendmentData(),
        'amend_def': _amendmentData()
          ..['amendmentId'] = 'amend_def'
          ..['shiftId'] = 'shift-9',
      });

      final page = await _repository(
        reader,
      ).loadShiftAmendments(shiftId: 'shift-1');

      expect(reader.queries.single.equalityFilters, <String, Object?>{
        'shiftId': 'shift-1',
      });
      expect(reader.queries.single.descending, isFalse);
      expect(page.items.single.id, 'amend_abc');
      expect(page.shiftId, 'shift-1');
      expect(page.isShiftScoped, isTrue);
    });

    test('a cashier is refused before any read is issued', () async {
      final reader = _FeedReader(<String, Map<String, Object?>>{
        'amend_abc': _amendmentData(),
      });
      final repository = _repository(reader, role: TenantRole.cashier);

      await expectLater(
        repository.loadAmendments(),
        _code('shift_amendments_forbidden'),
      );
      await expectLater(
        repository.loadShiftAmendments(shiftId: 'shift-1'),
        _code('shift_amendments_forbidden'),
      );
      expect(reader.queries, isEmpty);
    });

    test('a manager reads the trail they may not write to', () async {
      // Deliberately wider than the owner-and-administrator set that may make a
      // correction. Seeing that a shift was rewritten, and why, is operational
      // information a manager answering for that shift needs.
      final reader = _FeedReader(<String, Map<String, Object?>>{
        'amend_abc': _amendmentData(),
      });

      final page = await _repository(
        reader,
        role: TenantRole.manager,
      ).loadAmendments();

      expect(page.items.single.id, 'amend_abc');
      expect(
        TenantShiftAmendmentFeedRepository.canReadInSession(
          TenantSession.active(
            uid: 'manager-a',
            tenantId: 'tenant-a',
            role: TenantRole.manager,
          ),
        ),
        isTrue,
      );
    });

    test('a shift filter that is not a document ID never queries', () async {
      final reader = _FeedReader(const <String, Map<String, Object?>>{});

      await expectLater(
        _repository(reader).loadShiftAmendments(shiftId: '../shift-1'),
        _code('invalid_shift_filter'),
      );
      expect(reader.queries, isEmpty);
    });

    test('a transport that answers outside the scope fails closed', () async {
      // The path proofs in the base repository reject a foreign path outright,
      // so these prove the field-level checks a rule-bypassing document would
      // still have to pass.
      final crossTenant = _FeedReader(<String, Map<String, Object?>>{
        'amend_abc': _amendmentData()..['tenantId'] = 'tenant-b',
      });
      await expectLater(
        _repository(crossTenant).loadAmendments(),
        // The identity comparison against the document's own path is the first
        // thing that fails, which is the same refusal for the same reason.
        throwsA(isA<TenantReconciliationException>()),
      );

      final foreignPath = _FeedReader(
        const <String, Map<String, Object?>>{},
        overridePath: 'tenants/tenant-b/shift_amendments/amend_abc',
      );
      await expectLater(
        _repository(foreignPath).loadAmendments(),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('a filtered page answering for another shift fails closed', () async {
      // A page narrowed to one shift that returns another one is a broken
      // boundary, not a row to quietly skip past.
      final reader = _FeedReader(<String, Map<String, Object?>>{
        'amend_abc': _amendmentData()..['shiftId'] = 'shift-9',
      }, ignoreFilters: true);

      await expectLater(
        _repository(reader).loadShiftAmendments(shiftId: 'shift-1'),
        _code('foreign_shift_amendment'),
      );
    });

    test('pages are bounded and advance a stable cursor', () async {
      final reader = _FeedReader(<String, Map<String, Object?>>{
        'amend_1': _amendmentData()..['amendmentId'] = 'amend_1',
        'amend_2': _amendmentData()..['amendmentId'] = 'amend_2',
        'amend_3': _amendmentData()..['amendmentId'] = 'amend_3',
      });
      final repository = _repository(reader);

      final page = await repository.loadAmendments(pageSize: 2);
      expect(page.items.map((item) => item.id), <String>['amend_1', 'amend_2']);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, 'amend_2');

      final last = await repository.loadAmendments(
        pageSize: 2,
        cursor: page.nextCursor,
      );
      expect(reader.queries.last.startAfterDocumentId, 'amend_2');
      expect(last.items.single.id, 'amend_3');
      expect(last.hasMore, isFalse);
      expect(last.nextCursor, isNull);

      await expectLater(
        repository.loadAmendments(pageSize: 51),
        throwsRangeError,
      );
      await expectLater(
        repository.loadShiftAmendments(shiftId: 'shift-1', pageSize: 0),
        throwsRangeError,
      );
    });
  });
}

TenantShiftAmendmentFeedRepository _repository(
  _FeedReader reader, {
  TenantRole role = TenantRole.owner,
}) => TenantShiftAmendmentFeedRepository(
  session: TenantSession.active(
    uid: 'owner-a',
    tenantId: 'tenant-a',
    role: role,
  ),
  reader: reader,
);

Matcher _code(String code) => throwsA(
  isA<TenantReconciliationException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

TenantShiftAmendmentRecord _record({
  String amendmentId = 'amend_abc',
  required Map<String, Object?> data,
}) => TenantShiftAmendmentRecord.fromDocument(
  path: 'tenants/tenant-a/shift_amendments/$amendmentId',
  data: data,
);

/// The exact immutable record `functions/src/reconciliation/amendments.ts`
/// creates, with the figures from the first real correction this app made.
Map<String, Object?> _amendmentData() => <String, Object?>{
  'amendmentId': 'amend_abc',
  'tenantId': 'tenant-a',
  'shiftId': 'shift-1',
  'staffId': 'cashier-a',
  'businessDate': '2026-08-04',
  'sourceType': 'reconciliation_shift_variance',
  'expectationId': 'se_2026-08-04_shift-1',
  'expectationGeneration': 'gen-9',
  'previousTotalSales': 115.0,
  'previousTotalSalesMinor': 11500,
  'previousTransactionCount': 1,
  'previousRepresentationsAgreed': true,
  'totalSales': 345.0,
  'totalSalesMinor': 34500,
  'transactionCount': 3,
  'salesVarianceMinor': -23000,
  'transactionVariance': -2,
  'clearedAnomalyId': 'sv_shift-1_gen-9',
  'mutatesCountedCash': false,
  'reason': 'Late sales arrived after the close.',
  'actorUid': 'owner-a',
  'requestId': 'amend-shift-abcdefgh',
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 4, 15, 30)),
};

final class _FeedReader implements TenantDataReader {
  _FeedReader(this.amendments, {this.overridePath, this.ignoreFilters = false});

  final Map<String, Map<String, Object?>> amendments;

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
        TenantQueryDocumentSnapshot(path: path, data: _amendmentData()),
      ];
    }
    final ids = amendments.keys.toList()..sort();
    final cursor = query.startAfterDocumentId;
    final selected = <TenantQueryDocumentSnapshot>[];
    for (final id in ids) {
      final data = amendments[id]!;
      if (cursor != null && id.compareTo(cursor) <= 0) continue;
      if (!ignoreFilters &&
          query.equalityFilters.entries.any(
            (filter) => data[filter.key] != filter.value,
          )) {
        continue;
      }
      if (selected.length >= query.limit) break;
      selected.add(
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/$id',
          data: data,
        ),
      );
    }
    return selected;
  }
}
