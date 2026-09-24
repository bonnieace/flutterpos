/// The period reads a report needs, and the bounds they are held to.
///
/// **A range is the one query shape that can quietly return the wrong period.**
/// An equality filter either matches or it does not; a range depends on an
/// ordering, an index, and two bounds, and a transport that got any of those
/// wrong hands back documents that look exactly like the ones asked for. So
/// every read here proves its own span after the fact: a record outside the
/// period is a refusal, not a row.
///
/// The four shapes differ because the collections do. Returns and shifts carry
/// a business-date field; a stock take carries the date in its document key; an
/// audit record carries neither and has only the instant it was written.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/audit/audit.dart';
import 'package:flutter_application_1/inventory/stock_take_review.dart';
import 'package:flutter_application_1/returns/return_history.dart';
import 'package:flutter_application_1/shift/shift_history.dart';
import 'package:flutter_application_1/shift/tenant_shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('returns over a period', () {
    test('reads the span oldest first, keyed to when it was taken', () async {
      final reader = _RangeReader(
        businessDateDocuments: <String, Map<String, Object?>>{
          'ret-1': _aReturn(returnId: 'ret-1', recordedOn: '2026-09-02'),
          'ret-2': _aReturn(returnId: 'ret-2', recordedOn: '2026-09-05'),
          'ret-3': _aReturn(returnId: 'ret-3', recordedOn: '2026-09-20'),
        },
      );

      final read = await _returns(reader).loadRecordedRange(
        startRecordedOn: '2026-09-01',
        endRecordedOn: '2026-09-10',
      );

      expect(
        read.items.map((record) => record.recordedOn),
        <String>['2026-09-02', '2026-09-05'],
        reason:
            'The 20th is outside the period asked for, and the order is the '
            'one a document reads in: first day forward.',
      );
      expect(read.next, isNull);
    });

    test('the query it builds names the field and both bounds', () async {
      final reader = _RangeReader(
        businessDateDocuments: <String, Map<String, Object?>>{
          'ret-1': _aReturn(returnId: 'ret-1', recordedOn: '2026-09-02'),
        },
      );

      await _returns(reader).loadRecordedRange(
        startRecordedOn: '2026-09-01',
        endRecordedOn: '2026-09-30',
      );

      final query = reader.businessDateQueries.single;
      expect(
        query.orderBy,
        TenantBusinessDateRangeField.recordedOn,
        reason:
            'Not businessDate, which is the day of the sale being reversed. A '
            'returns report answers what came back over the period.',
      );
      expect(query.startBusinessDate, '2026-09-01');
      expect(query.endBusinessDate, '2026-09-30');
      expect(query.collectionPath, 'tenants/tenant-a/returns');
    });

    test('pages, and the position carries the pair it resumes after', () async {
      final reader = _RangeReader(
        businessDateDocuments: <String, Map<String, Object?>>{
          for (var i = 1; i <= 4; i++)
            'ret-$i': _aReturn(returnId: 'ret-$i', recordedOn: '2026-09-0$i'),
        },
      );
      final repository = _returns(reader);

      final first = await repository.loadRecordedRange(
        startRecordedOn: '2026-09-01',
        endRecordedOn: '2026-09-30',
        pageSize: 2,
      );

      expect(first.items, hasLength(2));
      expect(first.next?.businessDate, '2026-09-02');
      expect(
        first.next?.documentId,
        'ret-2',
        reason:
            'Two components, because a day can hold more than one return and '
            'the date alone would either repeat one or skip one.',
      );

      final second = await repository.loadRecordedRange(
        startRecordedOn: '2026-09-01',
        endRecordedOn: '2026-09-30',
        pageSize: 2,
        startAfter: first.next,
      );

      expect(second.items.map((record) => record.id), <String>[
        'ret-3',
        'ret-4',
      ]);
      expect(second.next, isNull);
    });

    test('a return from outside the period is refused, not listed', () async {
      final reader = _RangeReader(
        businessDateDocuments: <String, Map<String, Object?>>{
          'ret-1': _aReturn(returnId: 'ret-1', recordedOn: '2026-08-01'),
        },
        ignoreBounds: true,
      );

      expect(
        () => _returns(reader).loadRecordedRange(
          startRecordedOn: '2026-09-01',
          endRecordedOn: '2026-09-30',
        ),
        throwsA(isA<TenantReturnException>()),
        reason:
            'The document states the period on its own first page. A row that '
            'did not happen in it would make that statement false.',
      );
    });

    test('an inverted period is refused before anything is read', () async {
      final reader = _RangeReader();

      expect(
        () => _returns(reader).loadRecordedRange(
          startRecordedOn: '2026-09-30',
          endRecordedOn: '2026-09-01',
        ),
        throwsA(isA<TenantReturnException>()),
      );
      expect(reader.businessDateQueries, isEmpty);
    });

    test('a reader with no range transport says so', () async {
      expect(
        () => _returns(_PlainReader()).loadRecordedRange(
          startRecordedOn: '2026-09-01',
          endRecordedOn: '2026-09-30',
        ),
        throwsStateError,
        reason:
            'Better than an empty period, which would render as a month in '
            'which nothing was returned.',
      );
    });
  });

  group('shifts over a period', () {
    test('keeps the shift nobody closed', () async {
      final reader = _RangeReader(
        businessDateDocuments: <String, Map<String, Object?>>{
          'shift-1': _aShift(shiftId: 'shift-1', businessDate: '2026-09-02'),
          'shift-2': _aShift(
            shiftId: 'shift-2',
            businessDate: '2026-09-03',
            open: true,
          ),
        },
      );

      final read = await _shifts(reader).loadDateRange(
        startBusinessDate: '2026-09-01',
        endBusinessDate: '2026-09-30',
      );

      expect(
        read.items.map((slice) => slice.shift.status),
        <TenantShiftStatus>[TenantShiftStatus.closed, TenantShiftStatus.open],
        reason:
            'A period holding a drawer nobody counted is a fact about that '
            'period. Dropping it would show the days as settled when one of '
            'them never was.',
      );
    });

    test('a cashier gets no shifts period at all', () async {
      final reader = _RangeReader(
        businessDateDocuments: <String, Map<String, Object?>>{
          'shift-1': _aShift(shiftId: 'shift-1', businessDate: '2026-09-02'),
        },
      );

      expect(
        () => _shifts(reader, role: TenantRole.cashier).loadDateRange(
          startBusinessDate: '2026-09-01',
          endBusinessDate: '2026-09-30',
        ),
        throwsA(isA<TenantShiftException>()),
        reason:
            'Rather than one narrowed to their own shifts, which would read '
            "as the shop's and be one person's.",
      );
    });

    test('it ranges the business date, not the key', () async {
      final reader = _RangeReader(
        businessDateDocuments: <String, Map<String, Object?>>{
          'shift-1': _aShift(shiftId: 'shift-1', businessDate: '2026-09-02'),
        },
      );

      await _shifts(reader).loadDateRange(
        startBusinessDate: '2026-09-01',
        endBusinessDate: '2026-09-30',
      );

      expect(
        reader.businessDateQueries.single.orderBy,
        TenantBusinessDateRangeField.businessDate,
      );
    });

    test('a shift from another day is refused, not listed', () async {
      final reader = _RangeReader(
        businessDateDocuments: <String, Map<String, Object?>>{
          'shift-1': _aShift(shiftId: 'shift-1', businessDate: '2026-08-02'),
        },
        ignoreBounds: true,
      );

      expect(
        () => _shifts(reader).loadDateRange(
          startBusinessDate: '2026-09-01',
          endBusinessDate: '2026-09-30',
        ),
        throwsA(isA<TenantShiftException>()),
      );
    });
  });

  group('stock counts over a period', () {
    test('bounds the document key, because the key carries the day', () async {
      final reader = _RangeReader(
        documentIdDocuments: <String, Map<String, Object?>>{
          'st_2026-09-02_aaa': _aCount(businessDate: '2026-09-02'),
          'st_2026-09-09_bbb': _aCount(businessDate: '2026-09-09'),
          'st_2026-10-01_ccc': _aCount(businessDate: '2026-10-01'),
        },
      );

      final read = await _counts(reader).loadDateRange(
        collectionReader: reader,
        startBusinessDate: '2026-09-01',
        endBusinessDate: '2026-09-30',
      );

      expect(read.items.map((record) => record.businessDate), <String>[
        '2026-09-02',
        '2026-09-09',
      ]);

      final query = reader.documentIdQueries.single;
      expect(query.startAtDocumentId, 'st_2026-09-01_');
      expect(
        query.endAtDocumentId,
        'st_2026-09-30_￿',
        reason:
            'Past every character a digest can hold, so the last day of the '
            'period is included whole rather than cut at whichever count '
            'happens to sort first.',
      );
    });

    test('a count whose day is outside the span is refused', () async {
      // The key range and the recorded day disagreeing is exactly the case a
      // bound-checking transport would let through: the ID sorts inside.
      final reader = _RangeReader(
        documentIdDocuments: <String, Map<String, Object?>>{
          'st_2026-09-02_aaa': _aCount(businessDate: '2026-11-30'),
        },
      );

      expect(
        () => _counts(reader).loadDateRange(
          collectionReader: reader,
          startBusinessDate: '2026-09-01',
          endBusinessDate: '2026-09-30',
        ),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('it pages by the last key it saw', () async {
      final reader = _RangeReader(
        documentIdDocuments: <String, Map<String, Object?>>{
          for (var i = 1; i <= 3; i++)
            'st_2026-09-0${i}_x': _aCount(businessDate: '2026-09-0$i'),
        },
      );
      final repository = _counts(reader);

      final first = await repository.loadDateRange(
        collectionReader: reader,
        startBusinessDate: '2026-09-01',
        endBusinessDate: '2026-09-30',
        pageSize: 2,
      );

      expect(first.nextDocumentId, 'st_2026-09-02_x');

      final second = await repository.loadDateRange(
        collectionReader: reader,
        startBusinessDate: '2026-09-01',
        endBusinessDate: '2026-09-30',
        pageSize: 2,
        startAfterDocumentId: first.nextDocumentId,
      );

      expect(second.items.single.businessDate, '2026-09-03');
    });
  });

  group('the audit trail over a period', () {
    test('orders by the instant, which is the only time it has', () async {
      final reader = _RangeReader(
        instantDocuments: <String, Map<String, Object?>>{
          'aud-2': _anEvent(at: DateTime.utc(2026, 9, 5, 9)),
          'aud-1': _anEvent(at: DateTime.utc(2026, 9, 2, 9)),
        },
      );

      final read = await _audit(reader).loadRecordedRange(
        startAt: DateTime.utc(2026, 9, 1),
        endAt: DateTime.utc(2026, 9, 30),
      );

      expect(
        read.items.map((record) => record.id),
        <String>['aud-1', 'aud-2'],
        reason:
            'An audit ID is a digest, so key order carries no time at all. '
            'This is the ordering that makes a period answerable.',
      );
    });

    test('a record with no recorded instant is refused', () async {
      // Firestore leaves a document with no value for the ordering field out
      // of the index entirely, so one coming back is a transport that did not
      // run the query asked of it.
      final reader = _RangeReader(
        instantDocuments: <String, Map<String, Object?>>{
          'aud-1': _anEvent(at: null),
        },
        ignoreBounds: true,
      );

      expect(
        () => _audit(reader).loadRecordedRange(
          startAt: DateTime.utc(2026, 9, 1),
          endAt: DateTime.utc(2026, 9, 30),
        ),
        throwsA(isA<TenantAuditLogException>()),
      );
    });

    test('a manager may not read the trail over a period either', () async {
      final reader = _RangeReader(
        instantDocuments: <String, Map<String, Object?>>{
          'aud-1': _anEvent(at: DateTime.utc(2026, 9, 2, 9)),
        },
      );

      expect(
        () => _audit(reader, role: TenantRole.manager).loadRecordedRange(
          startAt: DateTime.utc(2026, 9, 1),
          endAt: DateTime.utc(2026, 9, 30),
        ),
        throwsA(isA<TenantAuditLogException>()),
        reason:
            'Owner and admin, exactly as firestore.rules already decided for '
            'the screen. A report is not a way around that.',
      );
    });

    test('an event outside the period is refused', () async {
      final reader = _RangeReader(
        instantDocuments: <String, Map<String, Object?>>{
          'aud-1': _anEvent(at: DateTime.utc(2026, 8, 2, 9)),
        },
        ignoreBounds: true,
      );

      expect(
        () => _audit(reader).loadRecordedRange(
          startAt: DateTime.utc(2026, 9, 1),
          endAt: DateTime.utc(2026, 9, 30),
        ),
        throwsA(isA<TenantAuditLogException>()),
      );
    });
  });
}

TenantSession _session(TenantRole role) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

TenantReturnHistoryRepository _returns(
  TenantDataReader reader, {
  TenantRole role = TenantRole.owner,
}) =>
    TenantReturnHistoryRepository(session: _session(role), reader: reader);

TenantShiftHistoryRepository _shifts(
  TenantDataReader reader, {
  TenantRole role = TenantRole.owner,
}) => TenantShiftHistoryRepository(session: _session(role), reader: reader);

TenantStockTakeReviewRepository _counts(
  TenantDataReader reader, {
  TenantRole role = TenantRole.owner,
}) => TenantStockTakeReviewRepository(session: _session(role), reader: reader);

TenantAuditLogRepository _audit(
  TenantDataReader reader, {
  TenantRole role = TenantRole.owner,
}) => TenantAuditLogRepository(session: _session(role), reader: reader);

Map<String, Object?> _aReturn({
  required String returnId,
  required String recordedOn,
}) => <String, Object?>{
      'returnId': returnId,
      'tenantId': 'tenant-a',
      'saleId': 'co-1',
      'businessDate': recordedOn,
      'recordedOn': recordedOn,
      'createdBy': 'user-a',
      'status': 'pending',
      'reason': 'Customer returned a damaged bottle',
      'itemsReturned': <Object?>[
        <String, Object?>{'productId': 'product-1', 'quantity': 2},
      ],
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 2, 12)),
    };

Map<String, Object?> _aShift({
  required String shiftId,
  required String businessDate,
  bool open = false,
}) {
  final data = <String, Object?>{
    'shiftId': shiftId,
    'tenantId': 'tenant-a',
    'staffId': 'user-a',
    'deviceId': 'dev-0123456789abcdef0123456789abcdef',
    'businessDate': businessDate,
    'status': open ? 'open' : 'closed',
    'startTime': Timestamp.fromDate(DateTime.utc(2026, 9, 2, 6)),
  };
  if (open) return data;
  return <String, Object?>{
    ...data,
    'endTime': Timestamp.fromDate(DateTime.utc(2026, 9, 2, 18)),
    'closingCashMinor': 125000,
    'closingCash': 1250,
    'declaredCashMinor': 125000,
    'declaredMpesaMinor': 0,
    'declaredCardMinor': 0,
    'totalSalesMinor': 98750,
    'totalSales': 987.5,
    'transactionCount': 3,
  };
}

Map<String, Object?> _aCount({required String businessDate}) =>
    <String, Object?>{
      'tenantId': 'tenant-a',
      'counterUid': 'user-a',
      'businessDate': businessDate,
      'status': 'complete',
      'productsInScope': 10,
      'countedLineCount': 10,
      'varianceLineCount': 2,
      'absoluteVarianceUnits': 5,
      'unmatchedLineCount': 0,
    };

Map<String, Object?> _anEvent({required DateTime? at}) => <String, Object?>{
  'tenantId': 'tenant-a',
  'eventType': 'staff_invited',
  'actorUid': 'user-a',
  if (at != null) 'createdAt': Timestamp.fromDate(at),
};

/// A reader with no range transport at all.
final class _PlainReader implements TenantDataReader {
  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}

/// Answers the three range shapes the way Firestore would, or deliberately
/// does not - see [ignoreBounds].
final class _RangeReader implements TenantDataReader, TenantReportRangeReader {
  _RangeReader({
    this.businessDateDocuments = const <String, Map<String, Object?>>{},
    this.documentIdDocuments = const <String, Map<String, Object?>>{},
    this.instantDocuments = const <String, Map<String, Object?>>{},
    this.ignoreBounds = false,
  });

  final Map<String, Map<String, Object?>> businessDateDocuments;
  final Map<String, Map<String, Object?>> documentIdDocuments;
  final Map<String, Map<String, Object?>> instantDocuments;

  /// Answers with documents the bounds exclude, so the repository's own proof
  /// of the period is what is under test rather than this fake's arithmetic.
  final bool ignoreBounds;

  final List<TenantBusinessDateRangeQuery> businessDateQueries =
      <TenantBusinessDateRangeQuery>[];
  final List<TenantDocumentIdRangeQuery> documentIdQueries =
      <TenantDocumentIdRangeQuery>[];
  final List<TenantInstantRangeQuery> instantQueries =
      <TenantInstantRangeQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantBusinessDateRange(
    TenantBusinessDateRangeQuery query,
  ) async {
    businessDateQueries.add(query);
    final field = query.orderBy.field;
    final entries = businessDateDocuments.entries.toList()
      ..sort((a, b) {
        final byDate = (a.value[field]! as String).compareTo(
          b.value[field]! as String,
        );
        return byDate != 0 ? byDate : a.key.compareTo(b.key);
      });

    final selected = <TenantQueryDocumentSnapshot>[];
    for (final entry in entries) {
      final date = entry.value[field]! as String;
      if (!ignoreBounds) {
        if (date.compareTo(query.startBusinessDate) < 0) continue;
        if (date.compareTo(query.endBusinessDate) > 0) continue;
      }
      if (query.startAfter case final after?) {
        final byDate = date.compareTo(after.businessDate);
        final past =
            byDate > 0 ||
            (byDate == 0 && entry.key.compareTo(after.documentId) > 0);
        if (!past) continue;
      }
      if (selected.length >= query.limit) break;
      selected.add(
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/${entry.key}',
          data: entry.value,
        ),
      );
    }
    return selected;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantDocumentIdRange(
    TenantDocumentIdRangeQuery query,
  ) async {
    documentIdQueries.add(query);
    final ids = documentIdDocuments.keys.toList()..sort();

    final selected = <TenantQueryDocumentSnapshot>[];
    for (final id in ids) {
      if (!ignoreBounds) {
        if (id.compareTo(query.startAtDocumentId) < 0) continue;
        if (id.compareTo(query.endAtDocumentId) > 0) continue;
      }
      if (query.startAfterDocumentId case final after?) {
        if (id.compareTo(after) <= 0) continue;
      }
      if (selected.length >= query.limit) break;
      selected.add(
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/$id',
          data: documentIdDocuments[id]!,
        ),
      );
    }
    return selected;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantInstantRange(
    TenantInstantRangeQuery query,
  ) async {
    instantQueries.add(query);
    DateTime? instantOf(Map<String, Object?> data) =>
        (data['createdAt'] as Timestamp?)?.toDate();

    final entries = instantDocuments.entries.toList()
      ..sort((a, b) {
        final left = instantOf(a.value);
        final right = instantOf(b.value);
        if (left == null || right == null) return a.key.compareTo(b.key);
        final byTime = left.compareTo(right);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });

    final selected = <TenantQueryDocumentSnapshot>[];
    for (final entry in entries) {
      final at = instantOf(entry.value);
      if (!ignoreBounds) {
        // Firestore leaves a document with no value for the ordering field out
        // of the index, so it is never a candidate at all.
        if (at == null) continue;
        if (at.isBefore(query.startAt) || at.isAfter(query.endAt)) continue;
      }
      if (query.startAfter case final after?) {
        if (at == null) continue;
        final byTime = at.compareTo(after.at);
        final past =
            byTime > 0 ||
            (byTime == 0 && entry.key.compareTo(after.documentId) > 0);
        if (!past) continue;
      }
      if (selected.length >= query.limit) break;
      selected.add(
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/${entry.key}',
          data: entry.value,
        ),
      );
    }
    return selected;
  }
}
