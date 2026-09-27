import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uzapay_pos/audit/audit.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tenant audit read model', () {
    test('decodes the envelope a staff writer records', () {
      final record = _record(data: _auditData());

      expect(record.id, 'aud_001');
      expect(record.tenantId, 'tenant-a');
      expect(record.eventType, 'staff_invited');
      expect(record.type, TenantAuditEventType.staffInvited);
      expect(record.actorUid, 'admin-a');
      expect(record.actorType, isNull);
      expect(record.targetUid, 'cashier-a');
      expect(record.requestId, 'invite-staff-abcdefgh');
      expect(record.isPlatformEvent, isFalse);
      expect(record.isCritical, isFalse);
      expect(record.recordedAt, DateTime.utc(2026, 8, 1, 9));
    });

    test('decodes the envelope a platform writer records', () {
      // `tenantLifecycle.ts` records the tenant-readable lifecycle event with
      // an `actorType` and no `actorUid`: the platform is not a member of the
      // business it acted on.
      final record = _record(
        auditId: 'aud_002',
        data: <String, Object?>{
          'tenantId': 'tenant-a',
          'eventType': 'tenant_lifecycle_changed',
          'fromStatus': 'pending',
          'toStatus': 'active',
          'actorType': 'platform_admin',
          'fanoutOperationId': 'op-1',
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 9)),
        },
      );

      expect(record.type, TenantAuditEventType.tenantLifecycleChanged);
      expect(record.actorUid, isNull);
      expect(record.actorType, 'platform_admin');
      expect(record.isPlatformEvent, isTrue);
      expect(record.fromStatus, 'pending');
      expect(record.toStatus, 'active');
    });

    test('decodes the critical alert the impact scan records', () {
      final record = _record(
        data: <String, Object?>{
          'tenantId': 'tenant-a',
          'eventType': 'no_active_administrator',
          'severity': 'critical',
          'actorType': 'platform',
          'reasonCode': 'no_active_administrator',
          'operationReference': 'scan-1',
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 9)),
        },
      );

      expect(record.type, TenantAuditEventType.noActiveAdministrator);
      expect(record.isCritical, isTrue);
      expect(record.isPlatformEvent, isTrue);
    });

    test('an unmodelled event is carried verbatim rather than refused', () {
      // A server deploy may record an event this client does not know. Hiding a
      // real event from the business's own trail would be far worse than naming
      // it honestly.
      final record = _record(
        data: _auditData()..['eventType'] = 'subscription_renewed',
      );

      expect(record.type, isNull);
      expect(record.eventType, 'subscription_renewed');
    });

    test('every modelled event names a writer wire value exactly once', () {
      final wireValues = TenantAuditEventType.values
          .map((type) => type.wireValue)
          .toList();

      expect(wireValues.toSet(), hasLength(wireValues.length));
      for (final type in TenantAuditEventType.values) {
        expect(TenantAuditEventType.tryParse(type.wireValue), type);
      }
      expect(TenantAuditEventType.tryParse('subscription_renewed'), isNull);
    });

    test('refuses a document that contradicts its own path', () {
      expect(
        () => _record(data: _auditData()..['tenantId'] = 'tenant-b'),
        _code('audit_identity_mismatch'),
      );

      for (final path in <String>[
        'tenants/tenant-a/audit_logs',
        'tenants/tenant-a/stock_adjustments/aud_001',
        'platform_audit_logs/aud_001',
        'tenants/tenant-a/audit_logs/aud_001/extra',
      ]) {
        expect(
          () => TenantAuditRecord.fromDocument(path: path, data: _auditData()),
          _code('invalid_audit_path'),
          reason: path,
        );
      }
    });

    test('refuses a record that names nobody at all', () {
      // Every real record is caused either by a named tenant actor or by the
      // platform acting on the business.
      expect(
        () => _record(
          data: _auditData()
            ..remove('actorUid')
            ..remove('targetUid'),
        ),
        _code('unattributed_audit_record'),
      );
    });

    test('refuses a malformed envelope field', () {
      final refused = <String, Map<String, Object?>>{
        'missing-event': _auditData()..remove('eventType'),
        'empty-event': _auditData()..['eventType'] = '',
        'non-string-event': _auditData()..['eventType'] = 7,
        'actor-path': _auditData()..['actorUid'] = 'staff/admin-a',
        'target-path': _auditData()..['targetUid'] = '../cashier-a',
        'non-string-actor-type': _auditData()
          ..remove('actorUid')
          ..['actorType'] = 3,
        'non-instant': _auditData()..['createdAt'] = 'yesterday',
      };
      for (final entry in refused.entries) {
        expect(
          () => _record(data: entry.value),
          throwsA(isA<TenantAuditLogException>()),
          reason: entry.key,
        );
      }
    });

    test('a record without a recorded instant is still evidence', () {
      // A row without a time still proves the event happened, names who caused
      // it, and says what it was. Failing a whole page closed over one missing
      // convenience field would deny an owner the trail entirely.
      final record = _record(data: _auditData()..remove('createdAt'));

      expect(record.recordedAt, isNull);
      expect(record.eventType, 'staff_invited');
    });
  });

  group('tenant audit log repository', () {
    test('the business-wide page is derived from the session alone', () async {
      final reader = _AuditReader(<String, Map<String, Object?>>{
        'aud_001': _auditData(),
      });

      final page = await _repository(reader).loadEvents();

      expect(
        reader.queries.single.collectionPath,
        'tenants/tenant-a/audit_logs',
      );
      // An audit ID is the operation, request, or delivery ID the event belongs
      // to, so document order carries no time information and a newest-first
      // page would be a lie. Ascending key order is also servable by the
      // automatic index.
      expect(reader.queries.single.descending, isFalse);
      expect(reader.queries.single.equalityFilters, isEmpty);
      expect(page.items.single.id, 'aud_001');
      expect(page.eventType, isNull);
      expect(page.isEventScoped, isFalse);
      expect(page.hasMore, isFalse);
    });

    test('an event page carries exactly one equality filter', () async {
      final reader = _AuditReader(<String, Map<String, Object?>>{
        'aud_001': _auditData(),
        'aud_002': _auditData()..['eventType'] = 'staff_status_set',
      });

      final page = await _repository(reader).loadEventsOfType(
        eventType: TenantAuditEventType.staffStatusSet,
      );

      expect(reader.queries.single.equalityFilters, <String, Object?>{
        'eventType': 'staff_status_set',
      });
      expect(reader.queries.single.descending, isFalse);
      expect(page.items.single.id, 'aud_002');
      expect(page.eventType, TenantAuditEventType.staffStatusSet);
      expect(page.isEventScoped, isTrue);
    });

    test('a manager and a cashier are refused before any read', () async {
      // Deliberately narrower than the owner/admin/manager stock surfaces: the
      // trail names who was invited, deactivated, and recovered.
      for (final role in <TenantRole>[TenantRole.manager, TenantRole.cashier]) {
        final reader = _AuditReader(<String, Map<String, Object?>>{
          'aud_001': _auditData(),
        });
        final repository = _repository(reader, role: role);

        await expectLater(
          repository.loadEvents(),
          _code('audit_logs_forbidden'),
          reason: role.wireValue,
        );
        await expectLater(
          repository.loadEventsOfType(
            eventType: TenantAuditEventType.staffInvited,
          ),
          _code('audit_logs_forbidden'),
          reason: role.wireValue,
        );
        expect(reader.queries, isEmpty, reason: role.wireValue);
      }
    });

    test('an owner reads the trail an admin reads', () async {
      final reader = _AuditReader(<String, Map<String, Object?>>{
        'aud_001': _auditData(),
      });

      final page = await _repository(reader, role: TenantRole.owner)
          .loadEvents();

      expect(page.items.single.id, 'aud_001');
    });

    test('a transport that answers outside the scope fails closed', () async {
      // The path proofs in the base repository reject a foreign path outright,
      // so these prove the field-level checks a rule-bypassing document would
      // still have to pass.
      final crossTenant = _AuditReader(<String, Map<String, Object?>>{
        'aud_001': _auditData()..['tenantId'] = 'tenant-b',
      });
      await expectLater(
        _repository(crossTenant).loadEvents(),
        // The identity comparison against the document's own path is the first
        // thing that fails, which is the same refusal for the same reason.
        throwsA(isA<TenantAuditLogException>()),
      );

      final foreignPath = _AuditReader(
        const <String, Map<String, Object?>>{},
        overridePath: 'tenants/tenant-b/audit_logs/aud_001',
      );
      await expectLater(
        _repository(foreignPath).loadEvents(),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('a filtered page answering for another event fails closed', () async {
      // A page narrowed to one event that returns another one is a broken
      // boundary, not a row to quietly skip past.
      final reader = _AuditReader(<String, Map<String, Object?>>{
        'aud_001': _auditData()..['eventType'] = 'staff_status_set',
      }, ignoreFilters: true);

      await expectLater(
        _repository(reader).loadEventsOfType(
          eventType: TenantAuditEventType.staffInvited,
        ),
        _code('foreign_audit_event_type'),
      );
    });

    test('pages are bounded and advance a stable cursor', () async {
      final reader = _AuditReader(<String, Map<String, Object?>>{
        'aud_1': _auditData(),
        'aud_2': _auditData(),
        'aud_3': _auditData(),
      });
      final repository = _repository(reader);

      final page = await repository.loadEvents(pageSize: 2);
      expect(page.items.map((item) => item.id), <String>['aud_1', 'aud_2']);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, 'aud_2');

      final last = await repository.loadEvents(
        pageSize: 2,
        cursor: page.nextCursor,
      );
      expect(reader.queries.last.startAfterDocumentId, 'aud_2');
      expect(last.items.single.id, 'aud_3');
      expect(last.hasMore, isFalse);
      expect(last.nextCursor, isNull);

      await expectLater(repository.loadEvents(pageSize: 51), throwsRangeError);
      await expectLater(
        repository.loadEventsOfType(
          eventType: TenantAuditEventType.staffInvited,
          pageSize: 0,
        ),
        throwsRangeError,
      );
      await expectLater(
        repository.loadEvents(cursor: 'not/a/document'),
        throwsArgumentError,
      );
    });
  });
}

TenantAuditLogRepository _repository(
  _AuditReader reader, {
  TenantRole role = TenantRole.admin,
}) => TenantAuditLogRepository(
  session: TenantSession.active(
    uid: 'admin-a',
    tenantId: 'tenant-a',
    role: role,
  ),
  reader: reader,
);

Matcher _code(String code) => throwsA(
  isA<TenantAuditLogException>().having((error) => error.code, 'code', code),
);

TenantAuditRecord _record({
  String auditId = 'aud_001',
  required Map<String, Object?> data,
}) => TenantAuditRecord.fromDocument(
  path: 'tenants/tenant-a/audit_logs/$auditId',
  data: data,
);

/// The exact envelope `functions/src/staff/shared.ts` `auditData` creates.
Map<String, Object?> _auditData() => <String, Object?>{
  'tenantId': 'tenant-a',
  'eventType': 'staff_invited',
  'actorUid': 'admin-a',
  'targetUid': 'cashier-a',
  'requestId': 'invite-staff-abcdefgh',
  'role': 'cashier',
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 9)),
};

final class _AuditReader implements TenantDataReader {
  _AuditReader(this.records, {this.overridePath, this.ignoreFilters = false});

  final Map<String, Map<String, Object?>> records;

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
        TenantQueryDocumentSnapshot(path: path, data: _auditData()),
      ];
    }
    final ids = records.keys.toList()..sort();
    final cursor = query.startAfterDocumentId;
    final selected = <TenantQueryDocumentSnapshot>[];
    for (final id in ids) {
      final data = records[id]!;
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
