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

    test('builds a close intent only for this cashier\'s open shift', () {
      final repository = _repository(_Reader(const {}));
      final open = TenantShift.fromDocument(
        path: 'tenants/tenant-a/shifts/shift-a',
        data: _document(),
      );

      final intent = repository.buildCloseIntent(
        shift: open,
        closingCashMinor: 125000,
      );
      expect(intent.path, 'tenants/tenant-a/shifts/shift-a');
      expect(intent.updateData(), <String, Object?>{
        'status': 'closed',
        'closingCashMinor': 125000,
        'closingCash': 1250.0,
      });

      expect(
        () => repository.buildCloseIntent(
          shift: TenantShift.fromDocument(
            path: 'tenants/tenant-a/shifts/shift-a',
            data: _document(overrides: <String, Object?>{'status': 'closed'}),
          ),
          closingCashMinor: 0,
        ),
        throwsA(_code('shift_not_open')),
      );
      expect(
        () => repository.buildCloseIntent(shift: open, closingCashMinor: -1),
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
        ),
        throwsA(_code('cross_tenant_shift')),
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

Matcher _code(String code) => isA<TenantShiftException>().having(
  (error) => error.code,
  'code',
  code,
);

final class _Reader implements TenantDocumentReader {
  _Reader(this._documents, {this.responsePath});

  final Map<String, Map<String, Object?>> _documents;
  final String? responsePath;
  final List<String> requested = <String>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    requested.add(path);
    final data = _documents[path];
    if (data == null) return null;
    return TenantDocumentSnapshot(path: responsePath ?? path, data: data);
  }
}
