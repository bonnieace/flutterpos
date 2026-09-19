import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';

void main() {
  group('strict shift read model', () {
    test('parses a canonical open shift', () {
      final shift = TenantShift.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _document(),
      );

      expect(shift.id, 'shift-a');
      expect(shift.tenantId, 'tenant-a');
      expect(shift.staffId, 'user-a');
      expect(shift.deviceId, _deviceA);
      expect(shift.businessDate, _businessDate);
      expect(shift.status, TenantShiftStatus.open);
      expect(shift.isOpen, isTrue);
      expect(shift.startedAt, DateTime.utc(2026, 7, 31, 6));
      expect(shift.endedAt, isNull);
      expect(shift.closingCashMinor, isNull);
    });

    test('parses a closed shift with counted cash', () {
      final shift = TenantShift.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _document(
          overrides: <String, Object?>{
            'status': 'closed',
            'endTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 18)),
            'closingCashMinor': 125000,
          },
        ),
      );

      expect(shift.isOpen, isFalse);
      expect(shift.endedAt, DateTime.utc(2026, 7, 31, 18));
      expect(shift.closingCashMinor, 125000);
    });

    test('refuses a document that does not repeat its own identity', () {
      expect(
        () => TenantShift.fromDocument(
          path: 'tenants/tenant-a/shifts/shift-a',
          data: _document(overrides: <String, Object?>{'shiftId': 'shift-b'}),
        ),
        throwsA(_code('shift_identity_mismatch')),
      );
      expect(
        () => TenantShift.fromDocument(
          path: 'tenants/tenant-a/shifts/shift-a',
          data: _document(overrides: <String, Object?>{'tenantId': 'tenant-b'}),
        ),
        throwsA(_code('shift_identity_mismatch')),
      );
    });

    test('refuses a path that is not an exact tenant shift document', () {
      for (final path in <String>[
        'shifts/shift-a',
        'tenants/tenant-a/sales/shift-a',
        'tenants/tenant-a/shifts/shift-a/lines/line-a',
      ]) {
        expect(
          () => TenantShift.fromDocument(path: path, data: _document()),
          throwsA(_code('invalid_shift_path')),
          reason: path,
        );
      }
    });

    test('refuses malformed lifecycle fields', () {
      final malformed = <String, Map<String, Object?>>{
        'status': <String, Object?>{'status': 'paused'},
        'missing-status': <String, Object?>{'status': null},
        'staff': <String, Object?>{'staffId': 'user/a'},
        'device': <String, Object?>{'deviceId': 'laptop-1'},
        'business-date': <String, Object?>{'businessDate': '31 July 2026'},
        'impossible-date': <String, Object?>{'businessDate': '2026-02-31'},
        'start-time': <String, Object?>{'startTime': 'today'},
        'closing-cash': <String, Object?>{'closingCashMinor': -1},
        'fractional-cash': <String, Object?>{'closingCashMinor': 10.5},
      };

      malformed.forEach((name, overrides) {
        expect(
          () => TenantShift.fromDocument(
            path: 'tenants/tenant-a/shifts/shift-a',
            data: _document(overrides: overrides),
          ),
          throwsA(isA<TenantShiftException>()),
          reason: name,
        );
      });
    });
  });

  group('guarded shift repository', () {
    test('derives the exact tenant document path from the session', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _document(),
      });

      final shift = await _repository(reader).readShift('shift-a');

      expect(reader.requested, <String>['tenants/tenant-a/shifts/shift-a']);
      expect(shift!.id, 'shift-a');
    });

    test('returns null when the canonical shift does not exist', () async {
      expect(await _repository(_Reader(const {})).readShift('shift-a'), isNull);
    });

    test('fails closed when a reader answers another tenant path', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _document(),
      }, responsePath: 'tenants/tenant-b/shifts/shift-a');

      expect(
        () => _repository(reader).readShift('shift-a'),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('refuses a shift belonging to another cashier', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _document(
          overrides: <String, Object?>{'staffId': 'user-b'},
        ),
      });

      expect(
        () => _repository(reader).readShift('shift-a'),
        throwsA(_code('foreign_shift')),
      );
    });

    test('refuses an unusable shift ID before any read', () async {
      final reader = _Reader(const {});

      expect(
        () => _repository(reader).readShift('shift/a'),
        throwsA(_code('invalid_shift_id')),
      );
      expect(reader.requested, isEmpty);
    });

    test('builds an open intent bound to this session and device', () {
      final intent = _repository(_Reader(const {})).buildOpenIntent(
        shiftId: 'shift-a',
        deviceId: _deviceA,
        businessDate: _businessDate,
      );

      expect(intent.path, 'tenants/tenant-a/shifts/shift-a');
      expect(intent.documentData(), <String, Object?>{
        'shiftId': 'shift-a',
        'tenantId': 'tenant-a',
        'staffId': 'user-a',
        'deviceId': _deviceA,
        'businessDate': _businessDate,
        'status': 'open',
      });
    });

    test('an open intent carries the float the drawer starts with', () {
      final intent = _repository(_Reader(const {})).buildOpenIntent(
        shiftId: 'shift-a',
        deviceId: _deviceA,
        businessDate: _businessDate,
        openingFloatMinor: 200000,
      );

      expect(intent.documentData()['openingFloatMinor'], 200000);
    });

    test('an open intent with no float writes no field about one', () {
      // Absent and zero are one answer to every reader, and a shop that keeps
      // no change in the drawer should not carry a field about one on every
      // shift it opens. It is also what keeps the server from reopening every
      // difference an owner has already dismissed - see the reconciliation
      // processors, which record the float only where there is one.
      final intent = _repository(_Reader(const {})).buildOpenIntent(
        shiftId: 'shift-a',
        deviceId: _deviceA,
        businessDate: _businessDate,
      );

      expect(intent.documentData().containsKey('openingFloatMinor'), isFalse);
    });

    test('refuses a float that is negative or larger than money gets', () {
      final repository = _repository(_Reader(const {}));

      // A negative float lowers the cash the drawer has to account for, which
      // is the one direction a dishonest figure is worth writing in. Rules
      // refuse it too; this is the first of the two locks.
      for (final float in <int>[-1, maximumShiftCashMinor + 1]) {
        expect(
          () => repository.buildOpenIntent(
            shiftId: 'shift-a',
            deviceId: _deviceA,
            businessDate: _businessDate,
            openingFloatMinor: float,
          ),
          throwsA(_code('invalid_opening_float')),
        );
      }
    });

    test('a shift document reads back the float it was opened with', () {
      final shift = TenantShift.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: <String, Object?>{
          'shiftId': 'shift-a',
          'tenantId': 'tenant-a',
          'staffId': 'user-a',
          'deviceId': _deviceA,
          'businessDate': _businessDate,
          'status': 'open',
          'openingFloatMinor': 200000,
        },
      );

      expect(shift.openingFloatMinor, 200000);
    });

    test('refuses an open intent with unusable device or date', () {
      final repository = _repository(_Reader(const {}));

      expect(
        () => repository.buildOpenIntent(
          shiftId: 'shift-a',
          deviceId: 'laptop-1',
          businessDate: _businessDate,
        ),
        throwsA(_code('invalid_shift_document')),
      );
      expect(
        () => repository.buildOpenIntent(
          shiftId: 'shift-a',
          deviceId: _deviceA,
          businessDate: '31-07-2026',
        ),
        throwsA(_code('invalid_shift_document')),
      );
    });

    test('names the one drawer count a close and its sweep share', () {
      // A cashier holds one register and counts it once. The counted close and
      // every shift it sweeps up wear the same name, which is what lets
      // reconciliation add their takings up and measure the total against the
      // single declaration - instead of reporting the counted shift as over by
      // exactly what the others took.
      final repository = _repository(_Reader(const {}));
      final open = TenantShift.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _document(),
      );
      const settlement = 'st-1789630427-a3f90c1d2e4b6789';

      final counted = repository.buildCloseIntent(
        shift: open,
        closingCashMinor: 125000,
        sales: const ShiftSalesSummary(
          transactionCount: 3,
          totalMinor: 98750,
          unsettledCount: 0,
        ),
        settlementId: settlement,
      );
      final swept = repository.buildRecoveryCloseIntent(
        shift: open,
        settlementId: settlement,
      );

      expect(counted.updateData()['settlementId'], settlement);
      expect(swept.updateData()['settlementId'], settlement);
      // The swept one still declares nothing: the drawer is already counted.
      expect(swept.updateData().containsKey('declaredCashMinor'), isFalse);
      expect(swept.updateData()['closedWithoutEvidence'], isTrue);
    });

    test('builds a close intent only for this cashier\'s open shift', () {
      final repository = _repository(_Reader(const {}));
      final open = TenantShift.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _document(),
      );

      final intent = repository.buildCloseIntent(
        shift: open,
        closingCashMinor: 125000,
        sales: const ShiftSalesSummary(
          transactionCount: 3,
          totalMinor: 98750,
          unsettledCount: 0,
        ),
      );
      expect(intent.path, 'tenants/tenant-a/shifts/shift-a');
      expect(intent.updateData(), <String, Object?>{
        'status': 'closed',
        'closingCashMinor': 125000,
        'closingCash': 1250.0,
        'totalSalesMinor': 98750,
        'totalSales': 987.5,
        'transactionCount': 3,
      });

      // **Omitted rather than written null when a close settles only itself**,
      // so an ordinary day costs no field and reconciliation's grouping never
      // has to tell an absence from a null.
      expect(intent.updateData().containsKey('settlementId'), isFalse);

      expect(
        () => repository.buildCloseIntent(
          shift: TenantShift.fromDocument(
            path: 'tenants/tenant-a/shifts/shift-a',
            data: _document(overrides: <String, Object?>{'status': 'closed'}),
          ),
          closingCashMinor: 0,
          sales: ShiftSalesSummary.empty,
        ),
        throwsA(_code('shift_not_open')),
      );
      expect(
        () => repository.buildCloseIntent(
          shift: open,
          closingCashMinor: -1,
          sales: ShiftSalesSummary.empty,
        ),
        throwsA(_code('invalid_closing_cash')),
      );
      expect(
        () => repository.buildCloseIntent(
          shift: TenantShift.fromDocument(
            path: 'tenants/tenant-b/shifts/shift-a',
            data: _document(
              overrides: <String, Object?>{'tenantId': 'tenant-b'},
            ),
          ),
          closingCashMinor: 0,
          sales: ShiftSalesSummary.empty,
        ),
        throwsA(_code('cross_tenant_shift')),
      );
    });

    test('refuses a closing summary the device cannot prove', () {
      final repository = _repository(_Reader(const {}));
      final open = TenantShift.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _document(),
      );

      expect(
        () => repository.buildCloseIntent(
          shift: open,
          closingCashMinor: 0,
          sales: const ShiftSalesSummary(
            transactionCount: 1,
            totalMinor: 500,
            unsettledCount: 1,
          ),
        ),
        throwsA(_code('unsynchronized_shift_sales')),
        reason: 'An unsynchronized sale makes the summary incomplete.',
      );
      expect(
        () => repository.buildCloseIntent(
          shift: open,
          closingCashMinor: 0,
          sales: const ShiftSalesSummary(
            transactionCount: 0,
            totalMinor: 500,
            unsettledCount: 0,
          ),
        ),
        throwsA(_code('invalid_shift_sales_summary')),
        reason: 'Sales without a transaction cannot be reconciled.',
      );
    });

    test('discovers only this cashier\'s open shifts in this tenant', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _document(),
        'tenants/tenant-a/shifts/shift-closed': _document(
          overrides: <String, Object?>{
            'shiftId': 'shift-closed',
            'status': 'closed',
          },
        ),
        'tenants/tenant-a/shifts/shift-colleague': _document(
          overrides: <String, Object?>{
            'shiftId': 'shift-colleague',
            'staffId': 'user-b',
          },
        ),
        'tenants/tenant-b/shifts/shift-elsewhere': _document(
          overrides: <String, Object?>{
            'shiftId': 'shift-elsewhere',
            'tenantId': 'tenant-b',
          },
        ),
      });

      final shifts = await _repository(
        reader,
      ).findOpenShifts(collectionReader: reader);

      expect(shifts.map((shift) => shift.id), <String>['shift-a']);
      expect(reader.queries.single.collectionPath, 'tenants/tenant-a/shifts');
      expect(reader.queries.single.equalityFilters, <String, Object?>{
        'staffId': 'user-a',
        'status': 'open',
      });
      expect(reader.queries.single.limit, 6);
    });

    test('fails closed when discovery answers outside this tenant', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _document(),
      }, collectionResponsePath: 'tenants/tenant-b/shifts/shift-a');

      expect(
        () => _repository(reader).findOpenShifts(collectionReader: reader),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('refuses a discovered shift that names another cashier', () async {
      // The query filters by UID, but a compromised or buggy reader must not
      // be able to hand this device a colleague's shift.
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/shifts/shift-a': _document(
          overrides: <String, Object?>{'staffId': 'user-b'},
        ),
      });

      expect(
        () => _repository(
          reader,
        ).findOpenShifts(collectionReader: _UnfilteredReader(reader)),
        throwsA(_code('foreign_shift')),
      );
    });
  });

  group('firestore shift writer', () {
    test('writes server-owned instants and never a client clock', () async {
      final creates = <(String, Map<String, Object?>)>[];
      final updates = <(String, Map<String, Object?>)>[];
      final writer = FirebaseTenantShiftWriter.forTesting(
        isOnline: () async => true,
        create: (path, data) async => creates.add((path, data)),
        update: (path, data) async => updates.add((path, data)),
      );
      final repository = _repository(_Reader(const {}));

      final opened = await writer.openShift(
        repository.buildOpenIntent(
          shiftId: 'shift-a',
          deviceId: _deviceA,
          businessDate: _businessDate,
        ),
      );
      final closed = await writer.closeShift(
        repository.buildCloseIntent(
          shift: TenantShift.fromDocument(
            path: 'tenants/tenant-a/shifts/shift-a',
            data: _document(),
          ),
          closingCashMinor: 500,
          sales: const ShiftSalesSummary(
            transactionCount: 2,
            totalMinor: 1500,
            unsettledCount: 0,
          ),
        ),
      );

      expect(opened.kind, TenantShiftWriteKind.committed);
      expect(closed.kind, TenantShiftWriteKind.committed);
      expect(creates.single.$1, 'tenants/tenant-a/shifts/shift-a');
      expect(creates.single.$2['startTime'], isA<FieldValue>());
      expect(creates.single.$2.containsKey('endTime'), isFalse);
      expect(updates.single.$2['endTime'], isA<FieldValue>());
      expect(updates.single.$2['status'], 'closed');
    });

    test('never attempts a write while offline', () async {
      var writes = 0;
      final offline = FirebaseTenantShiftWriter.forTesting(
        isOnline: () async => false,
        create: (_, _) async => writes++,
        update: (_, _) async => writes++,
      );
      final failingCheck = FirebaseTenantShiftWriter.forTesting(
        isOnline: () async => throw StateError('connectivity unavailable'),
        create: (_, _) async => writes++,
        update: (_, _) async => writes++,
      );
      final intent = _repository(_Reader(const {})).buildOpenIntent(
        shiftId: 'shift-a',
        deviceId: _deviceA,
        businessDate: _businessDate,
      );

      expect(
        (await offline.openShift(intent)).kind,
        TenantShiftWriteKind.unavailable,
      );
      expect(
        (await failingCheck.openShift(intent)).kind,
        TenantShiftWriteKind.unavailable,
      );
      expect(writes, 0);
    });

    test('separates definitive refusals from uncertain outcomes', () async {
      final intent = _repository(_Reader(const {})).buildOpenIntent(
        shiftId: 'shift-a',
        deviceId: _deviceA,
        businessDate: _businessDate,
      );
      Future<TenantShiftWriteResult> attempt(Object error) =>
          FirebaseTenantShiftWriter.forTesting(
            isOnline: () async => true,
            create: (_, _) async => throw error,
            update: (_, _) async => throw error,
          ).openShift(intent);

      for (final code in <String>['permission-denied', 'failed-precondition']) {
        final result = await attempt(
          FirebaseException(plugin: 'cloud_firestore', code: code),
        );
        expect(result.kind, TenantShiftWriteKind.rejected, reason: code);
        expect(result.reasonCode, code);
      }
      for (final code in <String>['unavailable', 'aborted']) {
        final result = await attempt(
          FirebaseException(plugin: 'cloud_firestore', code: code),
        );
        expect(result.kind, TenantShiftWriteKind.ambiguous, reason: code);
      }
      expect(
        (await attempt(StateError('boom'))).kind,
        TenantShiftWriteKind.ambiguous,
      );

      final timedOut = await FirebaseTenantShiftWriter.forTesting(
        isOnline: () async => true,
        writeTimeout: const Duration(milliseconds: 20),
        create: (_, _) => Completer<void>().future,
        update: (_, _) async {},
      ).openShift(intent);
      expect(timedOut.kind, TenantShiftWriteKind.ambiguous);
      expect(timedOut.reasonCode, 'write_timeout');
    });
  });
}

TenantShiftRepository _repository(_Reader reader) => TenantShiftRepository(
  session: TenantSession.active(
    uid: 'user-a',
    tenantId: 'tenant-a',
    role: TenantRole.cashier,
  ),
  reader: reader,
);

/// A reader that ignores the repository's equality filters, standing in for a
/// buggy or hostile transport that returns documents the query excluded.
final class _UnfilteredReader implements TenantCollectionReader {
  const _UnfilteredReader(this._reader);

  final _Reader _reader;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) => _reader.getCollectionPage(
    TenantCollectionQuery.forTesting(
      collectionPath: query.collectionPath,
      limit: query.limit,
    ),
  );
}

Map<String, Object?> _document({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'shiftId': 'shift-a',
    'tenantId': 'tenant-a',
    'staffId': 'user-a',
    'deviceId': _deviceA,
    'businessDate': _businessDate,
    'status': 'open',
    'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 6)),
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null && key != 'status');
  return data;
}

Matcher _code(String code) =>
    isA<TenantShiftException>().having((error) => error.code, 'code', code);

final class _Reader implements TenantDataReader {
  _Reader(this._documents, {this.responsePath, this.collectionResponsePath});

  final Map<String, Map<String, Object?>> _documents;
  final String? responsePath;
  final String? collectionResponsePath;
  final List<String> requested = <String>[];
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    requested.add(path);
    final data = _documents[path];
    if (data == null) return null;
    return TenantDocumentSnapshot(path: responsePath ?? path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    final matches = <TenantQueryDocumentSnapshot>[];
    final paths = _documents.keys.toList()..sort();
    for (final path in paths) {
      if (!path.startsWith('${query.collectionPath}/')) continue;
      final data = _documents[path]!;
      final matchesFilters = query.equalityFilters.entries.every(
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
