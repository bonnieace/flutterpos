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

    test('a shift closed without its sales states no difference', () {
      // **Zero and zero is not a balanced drawer.** A close made by a device
      // holding none of the shift's sales writes zero for both figures as an
      // admission, and subtracting one from the other used to render the most
      // confident badge this surface has - *Cash matches* - over the one shift
      // nobody can say anything about.
      final entry = TenantShiftHistoryEntry.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _closed(
          overrides: <String, Object?>{
            'closingCashMinor': 0,
            'closingCash': 0,
            'totalSalesMinor': 0,
            'totalSales': 0,
            'transactionCount': 0,
            'closedWithoutEvidence': true,
          },
        ),
      );

      expect(entry.closedWithoutEvidence, isTrue);
      expect(entry.cashVarianceMinor, isNull);
    });

    test('a shift closed before the declaration states no difference', () {
      // **The defect this replaces.** Such a shift carries a cash figure and
      // nothing else, and the difference used to be counted *cash* against
      // sales by *every* method - so a shop taking half its money by M-Pesa
      // read as short by exactly that half, for ever, on the surface a cashier
      // is answerable from. There is no honest comparison to make here, so none
      // is made.
      final entry = TenantShiftHistoryEntry.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _closed(
          overrides: <String, Object?>{
            'declaredCashMinor': null,
            'declaredMpesaMinor': null,
            'declaredCardMinor': null,
          },
        ),
      );

      expect(entry.summary!.totalSalesMinor, 98750);
      expect(entry.closingCashMinor, 125000);
      expect(entry.cashVarianceMinor, isNull);
    });

    test(
      'the difference is the whole declaration against the whole takings',
      () {
        // Cash 400.00 and M-Pesa 600.00 against sales of 987.50: over by 12.50.
        // Under the old arithmetic this shift read as *short by 587.50* - the
        // value of its M-Pesa - which is money nobody had lost.
        final entry = TenantShiftHistoryEntry.fromDocument(
          path: 'tenants/tenant-a/shifts/shift-a',
          data: _closed(
            overrides: <String, Object?>{
              'closingCashMinor': 40000,
              'closingCash': 400,
              'declaredCashMinor': 40000,
              'declaredMpesaMinor': 60000,
              'declaredCardMinor': 0,
            },
          ),
        );

        expect(entry.cashVarianceMinor, 1250);
      },
    );

    test('the opening float is counted back rather than read as a surplus', () {
      // The drawer was given 200.00 in change before it sold anything, and the
      // cashier counted the whole thing at close: 987.50 of sales sitting on
      // top of the float. Nothing is missing. Without the float term this row
      // said *Takings over* by 200.00, every day, to the person answerable for
      // the drawer - and disagreed with the server's own verification of the
      // same shift, which is worse than either figure being wrong alone.
      final entry = TenantShiftHistoryEntry.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _closed(
          overrides: <String, Object?>{
            'openingFloatMinor': 20000,
            'closingCashMinor': 118750,
            'closingCash': 1187.5,
            'declaredCashMinor': 118750,
            'declaredMpesaMinor': 0,
            'declaredCardMinor': 0,
          },
        ),
      );

      expect(entry.openingFloatMinor, 20000);
      expect(entry.cashVarianceMinor, 0);
    });

    test('a float does not absorb money genuinely missing from the drawer', () {
      // The same float, and 100.00 of the drawer absent: still short by 100.00.
      final entry = TenantShiftHistoryEntry.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _closed(
          overrides: <String, Object?>{
            'openingFloatMinor': 20000,
            'closingCashMinor': 108750,
            'closingCash': 1087.5,
            'declaredCashMinor': 108750,
            'declaredMpesaMinor': 0,
            'declaredCardMinor': 0,
          },
        ),
      );

      expect(entry.cashVarianceMinor, -10000);
    });

    test('a shift carrying no float reads exactly as it did before one', () {
      // Every shift closed before the field existed, and every shift of every
      // shop that keeps no change in the drawer.
      final entry = TenantShiftHistoryEntry.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _closed(),
      );

      expect(entry.openingFloatMinor, 0);
      expect(entry.cashVarianceMinor, 125000 - 98750);
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

    test('a shift closed and never corrected carries no correction', () {
      final entry = TenantShiftHistoryEntry.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _closed(),
      );

      expect(entry.amendment, isNull);
    });

    test('reports the correction a server made and how many it has had', () {
      final entry = TenantShiftHistoryEntry.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _closed(overrides: _amended()),
      );

      final amendment = entry.amendment!;
      expect(amendment.latestId, 'sm_abc');
      expect(amendment.generation, 'generation-one');
      expect(amendment.count, 2);
      expect(amendment.amendedAt, DateTime.utc(2026, 7, 31, 19));
      // The correction rewrote the summary; the counted cash is untouched, so
      // the difference this surface names is still the one it always was.
      expect(entry.summary!.totalSalesMinor, 98750);
      expect(entry.cashVarianceMinor, 26250);
    });

    test('a correction with no recorded instant is still a correction', () {
      // The instant is a server timestamp. Its absence limits what a row can say
      // about when, and must never put the correction itself in doubt.
      final entry = TenantShiftHistoryEntry.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _closed(
          overrides: <String, Object?>{..._amended(), 'summaryAmendedAt': null},
        ),
      );

      expect(entry.amendment!.count, 2);
      expect(entry.amendment!.amendedAt, isNull);
    });

    test('refuses a partial or incoherent correction record', () {
      final refused = <String, Map<String, Object?>>{
        // No client can write any of these fields, so a partial set is either a
        // server that changed its contract or a document no server wrote.
        'missing-id': <String, Object?>{'summaryAmendmentId': null},
        'missing-generation': <String, Object?>{
          'summaryAmendedGeneration': null,
        },
        'missing-count': <String, Object?>{'summaryAmendmentCount': null},
        'count-below-one': <String, Object?>{'summaryAmendmentCount': 0},
        'negative-count': <String, Object?>{'summaryAmendmentCount': -1},
        'fractional-count': <String, Object?>{'summaryAmendmentCount': 1.5},
        'string-count': <String, Object?>{'summaryAmendmentCount': '2'},
        'id-with-separator': <String, Object?>{
          'summaryAmendmentId': 'shift_amendments/sm_abc',
        },
        'id-not-a-string': <String, Object?>{'summaryAmendmentId': 7},
        'empty-generation': <String, Object?>{'summaryAmendedGeneration': ''},
        'padded-generation': <String, Object?>{
          'summaryAmendedGeneration': ' generation-one ',
        },
        // Built from a code unit rather than written as an escape, so this source
        // file can never carry a literal control byte of its own.
        'control-character-generation': <String, Object?>{
          'summaryAmendedGeneration': 'generation${String.fromCharCode(1)}one',
        },
        'generation-not-a-string': <String, Object?>{
          'summaryAmendedGeneration': 1,
        },
        'instant-not-a-timestamp': <String, Object?>{
          'summaryAmendedAt': '2026-07-31T19:00:00Z',
        },
      };

      for (final entry in refused.entries) {
        expect(
          () => TenantShiftHistoryEntry.fromDocument(
            path: 'tenants/tenant-a/shifts/shift-a',
            data: _closed(
              overrides: <String, Object?>{..._amended(), ...entry.value},
            ),
          ),
          throwsA(isA<TenantShiftException>()),
          reason: entry.key,
        );
      }
    });

    test('refuses an instant that accounts for no correction at all', () {
      expect(
        () => TenantShiftHistoryEntry.fromDocument(
          path: 'tenants/tenant-a/shifts/shift-a',
          data: _closed(
            overrides: <String, Object?>{
              'summaryAmendedAt': Timestamp.fromDate(
                DateTime.utc(2026, 7, 31, 19),
              ),
            },
          ),
        ),
        _code('incomplete_shift_amendment'),
      );
    });

    test('refuses a corrected shift that recorded no totals', () {
      // The correction rewrites the three summary fields, so this document could
      // not have come from one - and the row would have to say both that no
      // totals were recorded and that the totals were corrected.
      expect(
        () => TenantShiftHistoryEntry.fromDocument(
          path: 'tenants/tenant-a/shifts/shift-a',
          data: _closed(
            overrides: <String, Object?>{
              ..._amended(),
              'totalSalesMinor': null,
              'totalSales': null,
              'transactionCount': null,
            },
          ),
        ),
        _code('amended_shift_without_summary'),
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
            // A shift that took nothing declared nothing, by every method.
            'declaredCashMinor': 0,
            'declaredMpesaMinor': 0,
            'declaredCardMinor': 0,
          },
        ),
      );

      expect(entry.summary!.transactionCount, 0);
      expect(entry.cashVarianceMinor, 0);
    });
  });

  group('shift history repository', () {
    test(
      'pages a cashier own closed shifts, newest document ID first',
      () async {
        final reader = _Reader(<String, Map<String, Object?>>{
          'tenants/tenant-a/shifts/shift-a': _closed(),
          'tenants/tenant-a/shifts/shift-b': _closed(shiftId: 'shift-b'),
          'tenants/tenant-a/shifts/shift-c': _closed(shiftId: 'shift-c'),
        });

        final page = await _repository(reader).loadPage(pageSize: 20);

        expect(page.scope, TenantShiftHistoryScope.ownShifts);
        expect(page.items.map((entry) => entry.id), <String>[
          'shift-c',
          'shift-b',
          'shift-a',
        ]);
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
      },
    );

    test(
      'reports an exact pagination boundary and resumes from its cursor',
      () async {
        final documents = <String, Map<String, Object?>>{
          for (var index = 0; index < 3; index++)
            'tenants/tenant-a/shifts/shift-$index': _closed(
              shiftId: 'shift-$index',
            ),
        };

        final full = await _repository(
          _Reader(documents),
        ).loadPage(pageSize: 3);
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
      },
    );

    test('management may page every cashier and a cashier may not', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _closed(),
        'tenants/tenant-a/shifts/shift-b': _closed(
          shiftId: 'shift-b',
          overrides: <String, Object?>{'staffId': 'user-b'},
        ),
      });

      final page = await _repository(
        reader,
        role: TenantRole.manager,
      ).loadPage(scope: TenantShiftHistoryScope.everyCashier);
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

TenantSession _session(TenantRole role) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

Matcher _shiftCode(String code) =>
    isA<TenantShiftException>().having((error) => error.code, 'code', code);

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
  // **The declared triple, because the difference is computed from it.** It
  // mirrors the counted cash unless a case names its own, so a fixture reads as
  // a shift closed by a current build; one closed before the triple existed
  // carries none and states no difference, which a case below asserts.
  // All three or none: a partial triple is refused by the read model, which is
  // right, and would make every case here fail for the wrong reason.
  if (data['closingCashMinor'] != null &&
      !data.containsKey('declaredCashMinor')) {
    data['declaredCashMinor'] = data['closingCashMinor'];
    data.putIfAbsent('declaredMpesaMinor', () => 0);
    data.putIfAbsent('declaredCardMinor', () => 0);
  }
  data.removeWhere((key, value) => value == null);
  return data;
}

/// The four fields `amendShiftSummary` leaves on a shift it corrected, exactly as
/// `functions/src/reconciliation/amendments.ts` writes them. The count is 2 so a
/// test cannot pass by reading a hard-coded one.
Map<String, Object?> _amended() => <String, Object?>{
  'summaryAmendmentId': 'sm_abc',
  'summaryAmendedGeneration': 'generation-one',
  'summaryAmendmentCount': 2,
  'summaryAmendedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 19)),
};

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
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
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
