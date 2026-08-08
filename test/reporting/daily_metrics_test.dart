import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('daily metrics read model', () {
    test('accepts the document the reconciliation processor writes', () {
      final metrics = TenantDailyMetrics.fromDocument(
        path: 'tenants/tenant-a/daily_metrics/2026-07-31',
        data: _metrics(),
      );

      expect(metrics.businessDate, '2026-07-31');
      expect(metrics.sales, 1250.5);
      expect(metrics.profit, 430.25);
      expect(metrics.transactions, 12);
      expect(metrics.shiftCount, 2);
      expect(metrics.incompleteCostLineCount, 0);
      expect(metrics.hasCompleteCostData, isTrue);
      expect(metrics.metricGeneration, 'gen-1');
      expect(metrics.regeneratedAt, DateTime.utc(2026, 8, 1, 2, 30));
    });

    test('the day judges its own profit, and the decoder does not', () {
      final complete = TenantDailyMetrics.fromDocument(
        path: 'tenants/tenant-a/daily_metrics/2026-07-31',
        data: _metrics(),
      );
      expect(complete.profitReport.basis, TenantProfitBasis.complete);
      expect(complete.profitReport.marginPercent, closeTo(34.4062, 0.0001));

      // An uncosted line is a document this decoder still accepts: it is a
      // fact about the day, not a defect in the record.
      final incomplete = TenantDailyMetrics.fromDocument(
        path: 'tenants/tenant-a/daily_metrics/2026-07-31',
        data: _metrics(overrides: <String, Object?>{
          'incompleteCostLineCount': 4,
        }),
      );
      expect(incomplete.profit, 430.25);
      expect(incomplete.profitReport.basis, TenantProfitBasis.incomplete);
      expect(incomplete.profitReport.isShowable, isFalse);
    });

    test('a negative profit is legitimate, a negative revenue is not', () {
      final loss = TenantDailyMetrics.fromDocument(
        path: 'tenants/tenant-a/daily_metrics/2026-07-31',
        data: _metrics(overrides: <String, Object?>{'profit': -12.5}),
      );
      expect(loss.profit, -12.5);

      expect(
        () => TenantDailyMetrics.fromDocument(
          path: 'tenants/tenant-a/daily_metrics/2026-07-31',
          data: _metrics(overrides: <String, Object?>{'sales': -1}),
        ),
        _code('invalid_metrics_document'),
      );
    });

    test('refuses a document that disagrees with its own path', () {
      expect(
        () => TenantDailyMetrics.fromDocument(
          path: 'tenants/tenant-b/daily_metrics/2026-07-31',
          data: _metrics(),
        ),
        _code('metrics_identity_mismatch'),
      );
      expect(
        () => TenantDailyMetrics.fromDocument(
          path: 'tenants/tenant-a/daily_metrics/2026-07-30',
          data: _metrics(),
        ),
        _code('metrics_identity_mismatch'),
      );
      expect(
        () => TenantDailyMetrics.fromDocument(
          path: 'tenants/tenant-a/daily_metrics/31-07-2026',
          data: _metrics(),
        ),
        _code('invalid_metrics_path'),
      );
      expect(
        () => TenantDailyMetrics.fromDocument(
          path: 'tenants/tenant-a/sales/2026-07-31',
          data: _metrics(),
        ),
        _code('invalid_metrics_path'),
      );
    });

    test('refuses a contradictory or incomplete document', () {
      final refused = <String, Map<String, Object?>>{
        'transaction-copies-disagree': <String, Object?>{
          'transactionCount': 11,
        },
        'missing-generation': <String, Object?>{'metricGeneration': null},
        'blank-generation': <String, Object?>{'metricGeneration': ''},
        'missing-regenerated-at': <String, Object?>{'regeneratedAt': null},
        'string-regenerated-at': <String, Object?>{'regeneratedAt': 'today'},
        'fractional-transactions': <String, Object?>{'transactions': 1.5},
        'negative-shift-count': <String, Object?>{'shiftCount': -1},
        'missing-cost-count': <String, Object?>{'incompleteCostLineCount': null},
        'infinite-sales': <String, Object?>{'sales': double.infinity},
      };

      for (final entry in refused.entries) {
        expect(
          () => TenantDailyMetrics.fromDocument(
            path: 'tenants/tenant-a/daily_metrics/2026-07-31',
            data: _metrics(overrides: entry.value),
          ),
          throwsA(isA<TenantDailyMetricsException>()),
          reason: entry.key,
        );
      }
    });
  });

  group('daily metrics repository', () {
    test('reads recent Africa/Nairobi business days newest first', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/daily_metrics/2026-07-30': _metrics(
          businessDate: '2026-07-30',
        ),
      });

      final days = await _repository(reader).loadRecentDays(days: 3);

      expect(days.map((day) => day.businessDate), <String>[
        '2026-07-31',
        '2026-07-30',
        '2026-07-29',
      ]);
      // Today is normally unreconciled and must still be listed.
      expect(days.first.isReconciled, isFalse);
      expect(days[1].metrics!.sales, 1250.5);
      expect(days.last.isReconciled, isFalse);
      expect(reader.requested, <String>[
        'tenants/tenant-a/daily_metrics/2026-07-31',
        'tenants/tenant-a/daily_metrics/2026-07-30',
        'tenants/tenant-a/daily_metrics/2026-07-29',
      ]);
    });

    test('the business day boundary follows the +03:00 offset', () async {
      final reader = _Reader(const <String, Map<String, Object?>>{});

      // 21:30 UTC is already the next Africa/Nairobi business day.
      final days = await TenantDailyMetricsRepository(
        session: _session(TenantRole.manager),
        reader: reader,
        clock: () => DateTime.utc(2026, 7, 31, 21, 30),
      ).loadRecentDays(days: 2);

      expect(days.map((day) => day.businessDate), <String>[
        '2026-08-01',
        '2026-07-31',
      ]);
    });

    test('only management may load the summary', () async {
      final reader = _Reader(const <String, Map<String, Object?>>{});

      for (final role in <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ]) {
        await _repository(reader, role: role).loadRecentDays(days: 1);
      }
      expect(reader.requested.length, 3);

      await expectLater(
        _repository(reader, role: TenantRole.cashier).loadRecentDays(days: 1),
        throwsA(_metricsCode('metrics_forbidden')),
      );
      expect(reader.requested.length, 3, reason: 'no forbidden read was issued');
    });

    test('the number of days is bounded', () async {
      final repository = _repository(_Reader(const {}));

      await expectLater(repository.loadRecentDays(days: 0), throwsRangeError);
      await expectLater(
        repository.loadRecentDays(
          days: TenantDailyMetricsRepository.maximumDays + 1,
        ),
        throwsRangeError,
      );
    });

    test('a cross-tenant response fails closed', () async {
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/daily_metrics/2026-07-31': _metrics(),
      }, responsePath: 'tenants/tenant-b/daily_metrics/2026-07-31');

      await expectLater(
        _repository(reader).readDay('2026-07-31'),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('an invalid business date is refused before any read', () async {
      final reader = _Reader(const <String, Map<String, Object?>>{});

      await expectLater(
        _repository(reader).readDay('31 July 2026'),
        throwsA(_metricsCode('invalid_business_date')),
      );
      expect(reader.requested, isEmpty);
    });
  });
}

TenantDailyMetricsRepository _repository(
  _Reader reader, {
  TenantRole role = TenantRole.manager,
}) => TenantDailyMetricsRepository(
  session: _session(role),
  reader: reader,
  clock: () => DateTime.utc(2026, 7, 31, 9),
);

TenantSession _session(TenantRole role) => TenantSession.active(
  uid: 'user-a',
  tenantId: 'tenant-a',
  role: role,
);

Matcher _metricsCode(String code) =>
    isA<TenantDailyMetricsException>().having((error) => error.code, 'code', code);

Matcher _code(String code) => throwsA(_metricsCode(code));

Map<String, Object?> _metrics({
  String businessDate = '2026-07-31',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'tenantId': 'tenant-a',
    'businessDate': businessDate,
    'sales': 1250.5,
    'profit': 430.25,
    'transactions': 12,
    'transactionCount': 12,
    'shiftCount': 2,
    'incompleteCostLineCount': 0,
    'metricGeneration': 'gen-1',
    'sourceDirtyRevision': 3,
    'regeneratedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

final class _Reader implements TenantDocumentReader {
  _Reader(this._documents, {this.responsePath});

  final Map<String, Map<String, Object?>> _documents;
  final String? responsePath;
  final List<String> requested = <String>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    requested.add(path);
    final data = _documents[path];
    return data == null
        ? null
        : TenantDocumentSnapshot(path: responsePath ?? path, data: data);
  }
}
