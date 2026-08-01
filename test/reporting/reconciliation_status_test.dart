import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reconciliation intake read model', () {
    test('accepts the record the metrics processor writes', () {
      final intake = TenantReconciliationIntake.fromDocument(
        path: 'tenants/tenant-a/reconciliation_dirty_days/2026-07-31',
        data: _intake(),
      );

      expect(intake.tenantId, 'tenant-a');
      expect(intake.businessDate, '2026-07-31');
      expect(intake.status, TenantReconciliationIntakeStatus.clean);
      expect(intake.revision, 3);
      expect(intake.processedRevision, 3);
      expect(intake.hasUnpublishedSales, isFalse);
      expect(intake.saleReceiptCount, 12);
      expect(intake.invalidLineCount, 0);
      expect(intake.hasInvalidSaleLines, isFalse);
      expect(intake.metricGeneration, 'gen-1');
      expect(intake.processedAt, DateTime.utc(2026, 8, 1, 2, 30));
      expect(intake.lastReceiptAt, DateTime.utc(2026, 7, 31, 18));
    });

    test('a day the sale trigger has only marked dirty is complete', () {
      // The trigger writes no `processedRevision` at all until a run publishes
      // one, and that absence is the answer rather than a broken record.
      final intake = TenantReconciliationIntake.fromDocument(
        path: 'tenants/tenant-a/reconciliation_dirty_days/2026-07-31',
        data: _intake(
          overrides: <String, Object?>{
            'status': 'dirty',
            'processedRevision': null,
            'metricGeneration': null,
            'processedAt': null,
          },
        ),
      );

      expect(intake.status, TenantReconciliationIntakeStatus.dirty);
      expect(intake.processedRevision, isNull);
      expect(intake.hasUnpublishedSales, isTrue);
    });

    test('an unmodelled status is carried rather than refused', () {
      final intake = TenantReconciliationIntake.fromDocument(
        path: 'tenants/tenant-a/reconciliation_dirty_days/2026-07-31',
        data: _intake(
          overrides: <String, Object?>{
            'status': 'rebuilding',
            'processedRevision': null,
          },
        ),
      );

      expect(intake.status, TenantReconciliationIntakeStatus.other);
      expect(intake.statusValue, 'rebuilding');
    });

    test('refuses a record that disagrees with its own path', () {
      expect(
        () => TenantReconciliationIntake.fromDocument(
          path: 'tenants/tenant-b/reconciliation_dirty_days/2026-07-31',
          data: _intake(),
        ),
        _code('intake_identity_mismatch'),
      );
      expect(
        () => TenantReconciliationIntake.fromDocument(
          path: 'tenants/tenant-a/reconciliation_dirty_days/2026-07-30',
          data: _intake(),
        ),
        _code('intake_identity_mismatch'),
      );
      expect(
        () => TenantReconciliationIntake.fromDocument(
          path: 'tenants/tenant-a/reconciliation_dirty_days/31-07-2026',
          data: _intake(),
        ),
        _code('invalid_intake_path'),
      );
      expect(
        () => TenantReconciliationIntake.fromDocument(
          path: 'tenants/tenant-a/daily_metrics/2026-07-31',
          data: _intake(),
        ),
        _code('invalid_intake_path'),
      );
    });

    test('refuses a record that contradicts itself', () {
      final refused = <String, Map<String, Object?>>{
        'clean-without-a-published-revision': <String, Object?>{
          'processedRevision': null,
        },
        'clean-behind-its-own-revision': <String, Object?>{
          'processedRevision': 2,
        },
        'published-ahead-of-what-happened': <String, Object?>{
          'status': 'dirty',
          'processedRevision': 4,
        },
        'quarantined-without-a-code': <String, Object?>{
          'status': 'quarantined',
          'processedRevision': null,
        },
      };

      for (final entry in refused.entries) {
        expect(
          () => TenantReconciliationIntake.fromDocument(
            path: 'tenants/tenant-a/reconciliation_dirty_days/2026-07-31',
            data: _intake(overrides: entry.value),
          ),
          _code('inconsistent_intake_record'),
          reason: entry.key,
        );
      }

      // The same quarantined day is accepted once it says why.
      final quarantined = TenantReconciliationIntake.fromDocument(
        path: 'tenants/tenant-a/reconciliation_dirty_days/2026-07-31',
        data: _intake(
          overrides: <String, Object?>{
            'status': 'quarantined',
            'processedRevision': null,
            'lastErrorCode': 'invalid_dirty_revision',
          },
        ),
      );
      expect(quarantined.lastErrorCode, 'invalid_dirty_revision');
    });

    test('refuses malformed counts and instants', () {
      final refused = <String, Map<String, Object?>>{
        'missing-revision': <String, Object?>{'revision': null},
        'fractional-revision': <String, Object?>{'revision': 1.5},
        'negative-receipts': <String, Object?>{'saleReceiptCount': -1},
        'string-processed-at': <String, Object?>{'processedAt': 'today'},
        'blank-status': <String, Object?>{'status': ''},
      };

      for (final entry in refused.entries) {
        expect(
          () => TenantReconciliationIntake.fromDocument(
            path: 'tenants/tenant-a/reconciliation_dirty_days/2026-07-31',
            data: _intake(overrides: entry.value),
          ),
          throwsA(isA<TenantReconciliationException>()),
          reason: entry.key,
        );
      }
    });
  });

  group('reconciliation run read model', () {
    test('accepts the job document the sweep writes', () {
      final run = TenantReconciliationRun.fromDocument(
        path: 'tenants/tenant-a/reconciliation_jobs/rj_abc',
        data: _job(),
      );

      expect(run.id, 'rj_abc');
      expect(run.tenantId, 'tenant-a');
      expect(run.businessDate, '2026-07-31');
      expect(run.source, TenantReconciliationRunSource.nightly);
      expect(run.status, TenantReconciliationRunStatus.completed);
      expect(run.phase, TenantReconciliationRunPhase.finalize);
      expect(run.mode, 'incremental');
      expect(run.attemptCount, 1);
      expect(run.shiftsProcessed, 2);
      expect(run.hasVariances, isFalse);
      expect(run.isOutstanding, isFalse);
      expect(run.completedAt, DateTime.utc(2026, 8, 1, 2, 31));
      // A sweep names no member of the business, so no name is ever resolved.
      expect(run.requestedBy, 'system:nightly');
      expect(run.actorUid, isNull);
    });

    test('a manual run names the member who asked for it', () {
      final run = TenantReconciliationRun.fromDocument(
        path: 'tenants/tenant-a/reconciliation_jobs/rj_def',
        data: _job(
          overrides: <String, Object?>{
            'source': 'manual',
            'mode': 'full',
            'requestedBy': 'owner-a',
            'status': 'running',
            'phase': 'stock',
            'completedAt': null,
          },
        ),
      );

      expect(run.source, TenantReconciliationRunSource.manual);
      expect(run.actorUid, 'owner-a');
      expect(run.isOutstanding, isTrue);
      expect(run.mode, 'full');
    });

    test('unmodelled sources, statuses, and phases are carried', () {
      final run = TenantReconciliationRun.fromDocument(
        path: 'tenants/tenant-a/reconciliation_jobs/rj_ghi',
        data: _job(
          overrides: <String, Object?>{
            'source': 'hourly',
            'status': 'paused',
            'phase': 'costing',
            'completedAt': null,
          },
        ),
      );

      expect(run.source, TenantReconciliationRunSource.other);
      expect(run.sourceValue, 'hourly');
      expect(run.status, TenantReconciliationRunStatus.other);
      expect(run.statusValue, 'paused');
      expect(run.phase, TenantReconciliationRunPhase.other);
      expect(run.phaseValue, 'costing');
      expect(run.isOutstanding, isFalse);
    });

    test('refuses a run that disagrees with its own path', () {
      expect(
        () => TenantReconciliationRun.fromDocument(
          path: 'tenants/tenant-b/reconciliation_jobs/rj_abc',
          data: _job(),
        ),
        _code('run_identity_mismatch'),
      );
      expect(
        () => TenantReconciliationRun.fromDocument(
          path: 'tenants/tenant-a/audit_logs/rj_abc',
          data: _job(),
        ),
        _code('invalid_run_path'),
      );
      expect(
        () => TenantReconciliationRun.fromDocument(
          path: 'tenants/tenant-a/reconciliation_jobs/rj_abc/pages/1',
          data: _job(),
        ),
        _code('invalid_run_path'),
      );
    });

    test('refuses a run that contradicts itself', () {
      final refused = <String, Map<String, Object?>>{
        'completed-before-finishing': <String, Object?>{'phase': 'stock'},
        'completed-without-an-instant': <String, Object?>{'completedAt': null},
        'failed-without-a-failure': <String, Object?>{
          'status': 'failed',
          'phase': 'metrics',
          'completedAt': null,
          'lastErrorCode': 'deadline-exceeded',
        },
        'failed-without-a-code': <String, Object?>{
          'status': 'failed',
          'phase': 'metrics',
          'completedAt': null,
          'consecutiveFailureCount': 2,
        },
        'quarantined-without-a-code': <String, Object?>{
          'status': 'quarantined',
          'phase': 'metrics',
          'completedAt': null,
        },
      };

      for (final entry in refused.entries) {
        expect(
          () => TenantReconciliationRun.fromDocument(
            path: 'tenants/tenant-a/reconciliation_jobs/rj_abc',
            data: _job(overrides: entry.value),
          ),
          _code('inconsistent_run_record'),
          reason: entry.key,
        );
      }

      // A quarantined run whose failure count was never incremented is
      // deliberately accepted: the retry sweep quarantines a malformed job
      // without touching that counter, and hiding it would hide the evidence.
      final quarantined = TenantReconciliationRun.fromDocument(
        path: 'tenants/tenant-a/reconciliation_jobs/rj_abc',
        data: _job(
          overrides: <String, Object?>{
            'status': 'quarantined',
            'phase': 'metrics',
            'completedAt': null,
            'lastErrorCode': 'malformed_reconciliation_job',
          },
        ),
      );
      expect(quarantined.consecutiveFailureCount, 0);
      expect(quarantined.lastErrorCode, 'malformed_reconciliation_job');
    });

    test('refuses a malformed envelope', () {
      final refused = <String, Map<String, Object?>>{
        'missing-local-date': <String, Object?>{'localDate': null},
        'unparseable-local-date': <String, Object?>{'localDate': '31-07-2026'},
        'impossible-local-date': <String, Object?>{'localDate': '2026-02-31'},
        'missing-requested-by': <String, Object?>{'requestedBy': null},
        'path-shaped-requested-by': <String, Object?>{
          'requestedBy': 'users/owner-a',
        },
        'missing-attempts': <String, Object?>{'attemptCount': null},
        'negative-variance': <String, Object?>{'stockVarianceCount': -1},
        'missing-mode': <String, Object?>{'mode': null},
      };

      for (final entry in refused.entries) {
        expect(
          () => TenantReconciliationRun.fromDocument(
            path: 'tenants/tenant-a/reconciliation_jobs/rj_abc',
            data: _job(overrides: entry.value),
          ),
          throwsA(isA<TenantReconciliationException>()),
          reason: entry.key,
        );
      }
    });
  });

  group('reconciliation status repository', () {
    test('reads the day by exact path and its runs by one filter', () async {
      final reader = _Reader(
        documents: <String, Map<String, Object?>>{
          'tenants/tenant-a/reconciliation_dirty_days/2026-07-31': _intake(),
        },
        page: <TenantQueryDocumentSnapshot>[
          _runSnapshot('dirty_1785540000000'),
          _runSnapshot('rj_abc'),
        ],
      );

      final day = await _repository(reader).loadDay('2026-07-31');

      expect(day.businessDate, '2026-07-31');
      expect(day.outcome, TenantReconciliationDayOutcome.regenerated);
      expect(day.intake!.saleReceiptCount, 12);
      expect(day.runs.items.map((run) => run.id), <String>[
        'dirty_1785540000000',
        'rj_abc',
      ]);
      expect(reader.documentPaths, <String>[
        'tenants/tenant-a/reconciliation_dirty_days/2026-07-31',
      ]);
      expect(
        reader.queries.single.collectionPath,
        'tenants/tenant-a/reconciliation_jobs',
      );
      expect(reader.queries.single.equalityFilters, <String, Object?>{
        'localDate': '2026-07-31',
      });
      expect(reader.queries.single.descending, isFalse);
    });

    test('a day the server never saw is an answer, not an absence', () async {
      final reader = _Reader(page: const <TenantQueryDocumentSnapshot>[]);

      final day = await _repository(reader).loadDay('2026-07-31');

      expect(day.intake, isNull);
      expect(day.outcome, TenantReconciliationDayOutcome.noSalesRecorded);
      expect(day.runs.items, isEmpty);
      // The run query is still issued: a scheduled sweep queues work for a day
      // that recorded no sale, and refusing to look would hide a failed one.
      expect(reader.queries, hasLength(1));
    });

    test('a failed run explains a day that is still waiting', () async {
      final reader = _Reader(
        documents: <String, Map<String, Object?>>{
          'tenants/tenant-a/reconciliation_dirty_days/2026-07-31': _intake(
            overrides: <String, Object?>{
              'status': 'dirty',
              'processedRevision': 2,
            },
          ),
        },
        page: <TenantQueryDocumentSnapshot>[
          _runSnapshot(
            'rj_abc',
            overrides: <String, Object?>{
              'status': 'failed',
              'phase': 'metrics',
              'completedAt': null,
              'consecutiveFailureCount': 3,
              'lastErrorCode': 'resource-exhausted',
            },
          ),
        ],
      );

      final day = await _repository(reader).loadDay('2026-07-31');

      expect(day.outcome, TenantReconciliationDayOutcome.awaitingRegeneration);
      expect(day.intake!.hasUnpublishedSales, isTrue);
      expect(day.runs.items.single.lastErrorCode, 'resource-exhausted');
      expect(day.runs.items.single.consecutiveFailureCount, 3);
    });

    test('a quarantined day reports the code the server recorded', () async {
      final reader = _Reader(
        documents: <String, Map<String, Object?>>{
          'tenants/tenant-a/reconciliation_dirty_days/2026-07-31': _intake(
            overrides: <String, Object?>{
              'status': 'quarantined',
              'processedRevision': null,
              'lastErrorCode': 'invalid_dirty_revision',
            },
          ),
        },
        page: const <TenantQueryDocumentSnapshot>[],
      );

      final day = await _repository(reader).loadDay('2026-07-31');

      expect(day.outcome, TenantReconciliationDayOutcome.blocked);
      expect(day.intake!.lastErrorCode, 'invalid_dirty_revision');
    });

    test('only management may read why a day is in its state', () async {
      for (final role in <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ]) {
        final reader = _Reader(page: const <TenantQueryDocumentSnapshot>[]);
        await _repository(reader, role: role).loadDay('2026-07-31');
        expect(reader.queries, hasLength(1));
      }

      final refused = _Reader(page: const <TenantQueryDocumentSnapshot>[]);
      await expectLater(
        _repository(refused, role: TenantRole.cashier).loadDay('2026-07-31'),
        throwsA(_exception('reconciliation_forbidden')),
      );
      expect(refused.queries, isEmpty, reason: 'no forbidden read was issued');
      expect(refused.documentPaths, isEmpty);
    });

    test('an invalid business date is refused before any read', () async {
      final reader = _Reader(page: const <TenantQueryDocumentSnapshot>[]);

      await expectLater(
        _repository(reader).loadDay('31 July 2026'),
        throwsA(_exception('invalid_business_date')),
      );
      expect(reader.queries, isEmpty);
      expect(reader.documentPaths, isEmpty);
    });

    test('a cross-tenant response fails closed', () async {
      final reader = _Reader(
        documents: <String, Map<String, Object?>>{
          'tenants/tenant-a/reconciliation_dirty_days/2026-07-31': _intake(),
        },
        page: const <TenantQueryDocumentSnapshot>[],
        documentResponsePath:
            'tenants/tenant-b/reconciliation_dirty_days/2026-07-31',
      );

      await expectLater(
        _repository(reader).loadDay('2026-07-31'),
        throwsA(isA<TenantScopeViolation>()),
      );

      final foreignRun = _Reader(
        page: <TenantQueryDocumentSnapshot>[
          _runSnapshot('rj_abc', tenantId: 'tenant-b'),
        ],
      );
      await expectLater(
        _repository(foreignRun).loadDay('2026-07-31'),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('a page answering with another day fails closed', () async {
      // The filter is attached by the repository, so a transport that ignores
      // it is a broken boundary rather than rows to skip past.
      final reader = _Reader(
        page: <TenantQueryDocumentSnapshot>[
          _runSnapshot(
            'rj_abc',
            overrides: <String, Object?>{'localDate': '2026-07-30'},
          ),
        ],
        ignoreFilters: true,
      );

      await expectLater(
        _repository(reader).loadDay('2026-07-31'),
        throwsA(_exception('foreign_reconciliation_day')),
      );
    });

    test('the runs page is bounded and resumable', () async {
      final reader = _Reader(
        page: <TenantQueryDocumentSnapshot>[
          _runSnapshot('rj_1'),
          _runSnapshot('rj_2'),
          _runSnapshot('rj_3'),
        ],
      );

      final first = await _repository(reader).loadDay('2026-07-31', pageSize: 2);
      expect(first.runs.items.map((run) => run.id), <String>['rj_1', 'rj_2']);
      expect(first.runs.hasMore, isTrue);
      expect(first.runs.nextCursor, 'rj_2');

      final second = await _repository(reader).loadDay(
        '2026-07-31',
        pageSize: 2,
        cursor: first.runs.nextCursor,
      );
      expect(second.runs.items.map((run) => run.id), <String>['rj_3']);
      expect(second.runs.hasMore, isFalse);
      expect(second.runs.nextCursor, isNull);
      expect(reader.queries.last.startAfterDocumentId, 'rj_2');

      await expectLater(
        _repository(reader).loadDay('2026-07-31', pageSize: 0),
        throwsRangeError,
      );
      await expectLater(
        _repository(reader).loadDay('2026-07-31', pageSize: 51),
        throwsRangeError,
      );
    });
  });
}

TenantReconciliationStatusRepository _repository(
  _Reader reader, {
  TenantRole role = TenantRole.manager,
}) => TenantReconciliationStatusRepository(
  session: TenantSession.active(
    uid: 'manager-a',
    tenantId: 'tenant-a',
    role: role,
  ),
  reader: reader,
);

Matcher _exception(String code) => isA<TenantReconciliationException>().having(
  (error) => error.code,
  'code',
  code,
);

Matcher _code(String code) => throwsA(_exception(code));

Map<String, Object?> _intake({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'tenantId': 'tenant-a',
    'businessDate': '2026-07-31',
    'status': 'clean',
    'revision': 3,
    'processedRevision': 3,
    'saleReceiptCount': 12,
    'invalidLineCount': 0,
    'lastSaleId': 'sale-9',
    'metricGeneration': 'gen-1',
    'lastReceiptAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 18)),
    'processedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

Map<String, Object?> _job({
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'tenantId': tenantId,
    'source': 'nightly',
    'sourceKey': 'nightly:2026-07-31',
    'mode': 'incremental',
    'checkpointKind': 'none',
    'checkpointKey': '2026-07-31',
    'localDate': '2026-07-31',
    'requestedBy': 'system:nightly',
    'status': 'completed',
    'phase': 'finalize',
    'generation': 0,
    'revision': 4,
    'attemptCount': 1,
    'consecutiveFailureCount': 0,
    'rerunRequested': false,
    'fullInitialized': true,
    'metricsProcessed': 1,
    'productsProcessed': 0,
    'stockVarianceCount': 0,
    'shiftsProcessed': 2,
    'shiftVarianceCount': 0,
    'authority': 'canonical_tenant_data',
    'mutatesStock': false,
    'completedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 31)),
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 31)),
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

TenantQueryDocumentSnapshot _runSnapshot(
  String jobId, {
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) => TenantQueryDocumentSnapshot(
  path: 'tenants/$tenantId/reconciliation_jobs/$jobId',
  data: _job(tenantId: tenantId, overrides: overrides),
);

final class _Reader implements TenantDataReader {
  _Reader({
    this.documents = const <String, Map<String, Object?>>{},
    this.page = const <TenantQueryDocumentSnapshot>[],
    this.documentResponsePath,
    this.ignoreFilters = false,
  });

  final Map<String, Map<String, Object?>> documents;
  final List<TenantQueryDocumentSnapshot> page;
  final String? documentResponsePath;

  /// Answers regardless of the repository's own filter, which is the only
  /// honest way to exercise a check that exists for a transport ignoring it.
  final bool ignoreFilters;
  final List<String> documentPaths = <String>[];
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentPaths.add(path);
    final data = documents[path];
    return data == null
        ? null
        : TenantDocumentSnapshot(
            path: documentResponsePath ?? path,
            data: data,
          );
  }

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
      // A fake that ignored the repository's own filter would prove nothing
      // about a page that carries one, so it is modelled in both directions.
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
