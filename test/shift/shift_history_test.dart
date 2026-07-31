import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';

void main() {
  group('closed shift read model', () {
    test('reports the recorded summary and names the difference', () {
      final entry = TenantShiftHistoryEntry.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _closed(),
      );

      expect(entry.id, 'shift-a');
      expect(entry.staffId, 'user-a');
      expect(entry.businessDate, _businessDate);
      expect(entry.closingCashMinor, 125000);
      expect(entry.summary!.totalSalesMinor, 98750);
      expect(entry.summary!.totalSales, 987.5);
      expect(entry.summary!.transactionCount, 3);
      // The device subtracts two recorded figures; it recomputes neither.
      expect(entry.cashVarianceMinor, 26250);
      expect(entry.endedAt, DateTime.utc(2026, 7, 31, 18));
    });

    test('a shift closed without a summary keeps its counted cash', () {
      final entry = TenantShiftHistoryEntry.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _closed(
          overrides: <String, Object?>{
            'totalSalesMinor': null,
            'totalSales': null,
            'transactionCount': null,
          },
        ),
      );

      expect(entry.summary, isNull);
      expect(entry.cashVarianceMinor, isNull);
      expect(entry.closingCashMinor, 125000);
    });

    test('refuses a partial or incoherent closing summary', () {
      final refused = <String, Map<String, Object?>>{
        'missing-count': <String, Object?>{'transactionCount': null},
        'missing-total': <String, Object?>{'totalSalesMinor': null},
        'missing-mirror': <String, Object?>{'totalSales': null},
        'negative-total': <String, Object?>{
          'totalSalesMinor': -1,
          'totalSales': -0.01,
        },
        'negative-count': <String, Object?>{'transactionCount': -1},
        'string-total': <String, Object?>{'totalSalesMinor': '98750'},
        'fractional-count': <String, Object?>{'transactionCount': 2.5},
        // The major-unit mirror must describe the authoritative minor units.
        'disagreeing-mirror': <String, Object?>{'totalSales': 12.5},
        'sales-without-transactions': <String, Object?>{
          'transactionCount': 0,
          'totalSalesMinor': 500,
          'totalSales': 5,
        },
      };

      for (final entry in refused.entries) {
        expect(
          () => TenantShiftHistoryEntry.fromDocument(
            path: 'tenants/tenant-a/shifts/shift-a',
            data: _closed(overrides: entry.value),
          ),
          throwsA(isA<TenantShiftException>()),
          reason: entry.key,
        );
      }
    });

    test('refuses an open shift and a close with no counted cash', () {
      expect(
        () => TenantShiftHistoryEntry.fromDocument(
          path: 'tenants/tenant-a/shifts/shift-a',
          data: _closed(overrides: <String, Object?>{'status': 'open'}),
        ),
        _code('shift_not_closed'),
      );
      expect(
        () => TenantShiftHistoryEntry.fromDocument(
          path: 'tenants/tenant-a/shifts/shift-a',
          data: _closed(overrides: <String, Object?>{'closingCashMinor': null}),
        ),
        _code('invalid_shift_document'),
      );
    });

    test('a zero summary is coherent and balances against no cash', () {
      final entry = TenantShiftHistoryEntry.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _closed(
          overrides: <String, Object?>{
            'closingCashMinor': 0,
            'closingCash': 0,
            'totalSalesMinor': 0,
            'totalSales': 0,
            'transactionCount': 0,
          },
        ),
      );

      expect(entry.summary!.transactionCount, 0);
      expect(entry.cashVarianceMinor, 0);
    });
  });

  group('shift history repository', () {
    test('pages a cashier own closed shifts, newest document ID first', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _closed(),
        'tenants/tenant-a/shifts/shift-b': _closed(shiftId: 'shift-b'),
        'tenants/tenant-a/shifts/shift-c': _closed(shiftId: 'shift-c'),
      });

      final page = await _repository(reader).loadPage(pageSize: 20);

      expect(page.scope, TenantShiftHistoryScope.ownShifts);
      expect(
        page.items.map((entry) => entry.id),
        <String>['shift-c', 'shift-b', 'shift-a'],
      );
      final query = reader.queries.single;
      expect(query.collectionPath, 'tenants/tenant-a/shifts');
      expect(query.equalityFilters, <String, Object?>{
        'status': 'closed',
        'staffId': 'user-a',
      });
      expect(query.descending, isTrue);
      expect(query.limit, 21);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });

    test('reports an exact pagination boundary and resumes from its cursor', () async {
      final documents = <String, Map<String, Object?>>{
        for (var index = 0; index < 3; index++)
          'tenants/tenant-a/shifts/shift-$index': _closed(
            shiftId: 'shift-$index',
          ),
      };

      final full = await _repository(_Reader(documents)).loadPage(pageSize: 3);
      expect(full.hasMore, isFalse, reason: 'exactly one page');
      expect(full.nextCursor, isNull);

      final reader = _Reader(documents);
      final first = await _repository(reader).loadPage(pageSize: 2);
      expect(first.items.map((entry) => entry.id), <String>[
        'shift-2',
        'shift-1',
      ]);
      expect(first.hasMore, isTrue);
      expect(first.nextCursor, 'shift-1');

      final second = await _repository(
        reader,
      ).loadPage(pageSize: 2, cursor: first.nextCursor);
      expect(second.items.map((entry) => entry.id), <String>['shift-0']);
      expect(second.hasMore, isFalse);
      expect(reader.queries.last.startAfterDocumentId, 'shift-1');
    });

    test('management may page every cashier and a cashier may not', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _closed(),
        'tenants/tenant-a/shifts/shift-b': _closed(
          shiftId: 'shift-b',
          overrides: <String, Object?>{'staffId': 'user-b'},
        ),
      });

      final page = await _repository(reader, role: TenantRole.manager).loadPage(
        scope: TenantShiftHistoryScope.everyCashier,
      );
      expect(page.items.map((entry) => entry.staffId), <String>[
        'user-b',
        'user-a',
      ]);
      expect(reader.queries.single.equalityFilters, <String, Object?>{
        'status': 'closed',
      });

      await expectLater(
        _repository(
          reader,
        ).loadPage(scope: TenantShiftHistoryScope.everyCashier),
        throwsA(_shiftCode('shift_history_forbidden')),
      );
      expect(reader.queries.length, 1, reason: 'no forbidden query was issued');
    });

    test('every role that may read another cashier is management', () {
      for (final role in <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ]) {
        expect(
          TenantShiftHistoryRepository.canReadEveryCashier(_session(role)),
          isTrue,
          reason: role.wireValue,
        );
      }
      expect(
        TenantShiftHistoryRepository.canReadEveryCashier(
          _session(TenantRole.cashier),
        ),
        isFalse,
      );
    });

    test('fails closed on a cross-tenant or foreign response', () async {
      final crossTenant = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _closed(),
      }, collectionResponsePath: 'tenants/tenant-b/shifts/shift-a');
      await expectLater(
        _repository(crossTenant).loadPage(),
        throwsA(isA<TenantScopeViolation>()),
      );

      // The query filters by UID; a transport that ignores it must not widen
      // what this cashier can see.
      final foreign = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _closed(
          overrides: <String, Object?>{'staffId': 'user-b'},
        ),
      }, ignoreFilters: true);
      await expectLater(
        _repository(foreign).loadPage(),
        throwsA(_shiftCode('foreign_shift')),
      );
    });

    test('fails closed when a page is not ordered newest first', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _closed(),
        'tenants/tenant-a/shifts/shift-b': _closed(shiftId: 'shift-b'),
      }, ascending: true);

      await expectLater(
        _repository(reader).loadPage(),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('refuses an open shift returned by a closed-shift page', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _closed(
          overrides: <String, Object?>{
            'status': 'open',
            'closingCashMinor': null,
            'closingCash': null,
            'endTime': null,
          },
        ),
      }, ignoreFilters: true);

      await expectLater(
        _repository(reader).loadPage(),
        throwsA(_shiftCode('shift_not_closed')),
      );
    });
  });
}

TenantShiftHistoryRepository _repository(
  _Reader reader, {
  TenantRole role = TenantRole.cashier,
}) => TenantShiftHistoryRepository(session: _session(role), reader: reader);

TenantSession _session(TenantRole role) => TenantSession.active(
  uid: 'user-a',
  tenantId: 'tenant-a',
  role: role,
);

Matcher _shiftCode(String code) => isA<TenantShiftException>().having(
  (error) => error.code,
  'code',
  code,
);

Matcher _code(String code) => throwsA(_shiftCode(code));

Map<String, Object?> _closed({
  String shiftId = 'shift-a',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'shiftId': shiftId,
    'tenantId': 'tenant-a',
    'staffId': 'user-a',
    'deviceId': _deviceA,
    'businessDate': _businessDate,
    'status': 'closed',
    'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 6)),
    'endTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 18)),
    'closingCashMinor': 125000,
    'closingCash': 1250,
    'totalSalesMinor': 98750,
    'totalSales': 987.5,
    'transactionCount': 3,
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

/// A transport that answers the repository's own bounded queries.
///
/// [ignoreFilters] and [ascending] stand in for a buggy or hostile reader that
/// returns documents the query excluded or ordered the other way.
final class _Reader implements TenantDataReader {
  _Reader(
    this._documents, {
    this.collectionResponsePath,
    this.ignoreFilters = false,
    this.ascending = false,
  });

  final Map<String, Map<String, Object?>> _documents;
  final String? collectionResponsePath;
  final bool ignoreFilters;
  final bool ascending;
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final data = _documents[path];
    return data == null
        ? null
        : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    final paths = _documents.keys.toList()..sort();
    if (query.descending && !ascending) {
      paths.sort((left, right) => right.compareTo(left));
    }
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final path in paths) {
      if (!path.startsWith('${query.collectionPath}/')) continue;
      final data = _documents[path]!;
      final cursor = query.startAfterDocumentId;
      if (cursor != null) {
        final id = path.substring('${query.collectionPath}/'.length);
        final after = query.descending
            ? id.compareTo(cursor) < 0
            : id.compareTo(cursor) > 0;
        if (!after) continue;
      }
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
