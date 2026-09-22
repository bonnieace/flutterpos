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
        data: _metrics(
          overrides: <String, Object?>{'incompleteCostLineCount': 4},
        ),
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
        'missing-cost-count': <String, Object?>{
          'incompleteCostLineCount': null,
        },
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
      expect(days.first.isPublished, isFalse);
      expect(days[1].metrics!.sales, 1250.5);
      expect(days.last.isPublished, isFalse);
      // **Every day's metric and its intake record, all started together.**
      // The intake reads are what tell a published day from a current one, and
      // the whole page is one batch rather than a document at a time - two
      // round trips per day, awaited sequentially, is what this replaced.
      expect(reader.requested, <String>[
        'tenants/tenant-a/daily_metrics/2026-07-31',
        'tenants/tenant-a/daily_metrics/2026-07-30',
        'tenants/tenant-a/daily_metrics/2026-07-29',
        'tenants/tenant-a/reconciliation_dirty_days/2026-07-31',
        'tenants/tenant-a/reconciliation_dirty_days/2026-07-30',
        'tenants/tenant-a/reconciliation_dirty_days/2026-07-29',
      ]);
    });

    test('a day that cannot be read does not take the others with it', () async {
      // **The offline case.** Firestore refuses a document `get` it holds no
      // cached copy of rather than reporting the document absent, so on the
      // first business day of a stretch with no signal this threw - and
      // `Future.wait` fails the whole set on the first rejection. The home
      // swallows that and draws no figures at all, which is the one state that
      // page is built never to be in.
      final reader = _UnreachableReader(
        <String, Map<String, Object?>>{
          'tenants/tenant-a/daily_metrics/2026-07-30': _metrics(
            businessDate: '2026-07-30',
          ),
        },
        unreachable: <String>{'tenants/tenant-a/daily_metrics/2026-07-31'},
      );

      final days = await _repository(reader).loadRecentDays(days: 3);

      expect(days.map((day) => day.businessDate), <String>[
        '2026-07-31',
        '2026-07-30',
        '2026-07-29',
      ]);
      // The unreadable day reads exactly as an unpublished one, which is what
      // every surface already draws as "not reconciled".
      expect(days.first.metrics, isNull);
      expect(days.first.isPublished, isFalse);
      // And the day that did read is still reported, rather than being lost
      // to its neighbour's failure.
      expect(days[1].metrics!.sales, 1250.5);
    });

    test('a day that answered with nonsense is still a fault', () async {
      // The other half of the distinction, and the reason the guard is around
      // the read rather than around `readDay`: a document that answered and
      // does not add up is not a gap. The daily summary fails closed on it and
      // offers a retry, rather than drawing a day as unreconciled that the
      // server has in fact reconciled.
      final reader = _Reader(<String, Map<String, Object?>>{
        'tenants/tenant-a/daily_metrics/2026-07-31': _metrics(
          overrides: <String, Object?>{'transactionCount': 99},
        ),
      });

      await expectLater(
        _repository(reader).loadRecentDays(days: 1),
        throwsA(_metricsCode('inconsistent_metrics')),
      );
    });

    test('being refused the figures is still an answer, not a gap', () async {
      // The mirror of the case above, and the reason the degradation is per
      // day rather than around the whole call: a cashier asking for figures
      // they may not see must be told so, not handed a week of empty days.
      await expectLater(
        _repository(
          _Reader(const <String, Map<String, Object?>>{}),
          role: TenantRole.cashier,
        ).loadRecentDays(days: 3),
        throwsA(_metricsCode('metrics_forbidden')),
      );
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
      // One day each, and each day is a metric read plus an intake read.
      expect(reader.requested.length, 6);

      await expectLater(
        _repository(reader, role: TenantRole.cashier).loadRecentDays(days: 1),
        throwsA(_metricsCode('metrics_forbidden')),
      );
      expect(
        reader.requested.length,
        6,
        reason: 'no forbidden read was issued',
      );
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

  group('a day with its returns taken out', () {
    // The gross fixture is 1250.50 over 12 transactions at 430.25 profit, so
    // a net block of 900 over 11 leaves 350.50 returned.

    test('a document written before returns were counted is refused', () {
      // #104: reconciliation writes the whole block on every run with
      // `merge: false`, so a day without one was written by a deployment SIT
      // no longer runs. It is regenerated, not read as gross.
      expect(
        () => _decode(const <String, Object?>{}, omitNet: true),
        _code('invalid_metrics_document'),
      );
    });

    test('a complete block decodes and drives the net accessors', () {
      final metrics = _decode(_net());

      expect(metrics.net.returnedSales, 350.5);
      expect(metrics.net.returnCount, 1);
      expect(metrics.netSales, 900);
      expect(metrics.netTransactions, 11);
      expect(metrics.netProfitReport.profit, 300);
    });

    test('a half-written block is refused', () {
      // A writer defect, and this decoder refuses a document its writer would
      // not have produced - the same posture as the `transactionCount`
      // double-write check beside it.
      expect(
        () => _decode(_net(), omit: const <String>{'returnCount'}),
        throwsA(isA<TenantDailyMetricsException>()),
      );
    });

    test('a future version is refused rather than read as this one', () {
      expect(
        () => _decode(_net(version: 2)),
        throwsA(isA<TenantDailyMetricsException>()),
      );
    });

    test('netting a day to more than it took is refused', () {
      expect(
        () => _decode(_net(sales: 2000, returnedSales: -749.5)),
        throwsA(isA<TenantDailyMetricsException>()),
      );
      expect(
        () => _decode(_net(transactions: 13)),
        throwsA(isA<TenantDailyMetricsException>()),
      );
    });

    test('a returned total that is not the difference is refused', () {
      expect(
        () => _decode(_net(returnedSales: 10)),
        throwsA(isA<TenantDailyMetricsException>()),
      );
    });

    test('revenue netted without its cost is refused', () {
      // **The regression this check exists for.** Gross cost is 1250.50 -
      // 430.25 = 820.25. Netting takings to 900 while leaving profit at
      // 430.25 implies a net cost of 469.75, which is fine - but leaving
      // profit at the *gross* figure while netting further drives the implied
      // cost below zero, which no writer can produce.
      expect(
        () => _decode(_net(sales: 300, profit: 430.25, returnedSales: 950.5)),
        throwsA(isA<TenantDailyMetricsException>()),
      );
    });
  });

  group('what a published day is worth', () {
    // **The defect this group exists for.** `daily_metrics` is written with
    // `merge: false` and never deleted, so a later sale that marks the day
    // dirty again leaves the previous document in place. Reading its mere
    // existence as *reconciled* is what let the summary badge known-stale
    // figures green.

    test('a day with no metrics has not been published', () {
      expect(
        _day(metrics: null, intake: _intake()).standing,
        TenantDailyMetricsStanding.unpublished,
      );
    });

    test('a clean day at the published revision is current', () {
      expect(
        _day(metrics: _publishedMetrics(), intake: _intake()).standing,
        TenantDailyMetricsStanding.current,
      );
    });

    test('a day the server has taken more sales for is superseded', () {
      expect(
        _day(
          metrics: _publishedMetrics(),
          // The sale trigger bumps the revision and sets the day back to
          // dirty without touching the metric document.
          intake: _intake(status: 'dirty', revision: 4, processedRevision: 3),
        ).standing,
        TenantDailyMetricsStanding.superseded,
      );
    });

    test('a quarantined day is superseded however clean it looks', () {
      expect(
        _day(
          metrics: _publishedMetrics(),
          intake: _intake(
            status: 'quarantined',
            revision: 3,
            processedRevision: 3,
            overrides: <String, Object?>{'lastErrorCode': 'metrics_failed'},
          ),
        ).standing,
        TenantDailyMetricsStanding.superseded,
      );
    });

    test('a clean day that published a different revision is superseded', () {
      // Belt and braces against the status alone: a record claiming `clean`
      // while naming a revision the metric was not built from is not proof.
      expect(
        _day(
          metrics: _publishedMetrics(revision: 2),
          intake: _intake(revision: 3, processedRevision: 3),
        ).standing,
        TenantDailyMetricsStanding.superseded,
      );
    });

    test('a published day with no readable intake is not confirmed', () {
      // **Never [TenantDailyMetricsStanding.current].** Every sale writes an
      // intake record, so its absence is a read that did not answer - and
      // treating silence as confirmation is the original defect.
      expect(
        _day(metrics: _publishedMetrics(), intake: null).standing,
        TenantDailyMetricsStanding.unconfirmed,
      );
    });
  });
}

/// The fields `regenerateDailyMetric` writes beside the gross ones.
Map<String, Object?> _net({
  double sales = 900,
  double profit = 300,
  int transactions = 11,
  int incompleteCostLineCount = 0,
  double returnedSales = 350.5,
  int returnCount = 1,
  int version = 1,
}) => <String, Object?>{
  'netSales': sales,
  'netProfit': profit,
  'netTransactions': transactions,
  'netIncompleteCostLineCount': incompleteCostLineCount,
  'returnedSales': returnedSales,
  'returnCount': returnCount,
  'netMetricsVersion': version,
};

/// Every field of the net block, which `_metrics` now always supplies.
const Set<String> _netFields = <String>{
  'netSales',
  'netProfit',
  'netTransactions',
  'netIncompleteCostLineCount',
  'returnedSales',
  'returnCount',
  'netMetricsVersion',
};

TenantDailyMetrics _decode(
  Map<String, Object?> overrides, {
  bool omitNet = false,
  Set<String> omit = const <String>{},
}) {
  final data = _metrics(overrides: overrides);
  data.removeWhere(
    (key, value) => omit.contains(key) || omitNet && _netFields.contains(key),
  );
  return TenantDailyMetrics.fromDocument(
    path: 'tenants/tenant-a/daily_metrics/2026-07-31',
    data: data,
  );
}

TenantDailyMetricsDay _day({
  required TenantDailyMetrics? metrics,
  required TenantReconciliationIntake? intake,
}) => TenantDailyMetricsDay(
  businessDate: '2026-07-31',
  metrics: metrics,
  intake: intake,
);

TenantDailyMetrics _publishedMetrics({int revision = 3}) =>
    TenantDailyMetrics.fromDocument(
      path: 'tenants/tenant-a/daily_metrics/2026-07-31',
      data: _metrics(
        overrides: <String, Object?>{'sourceDirtyRevision': revision},
      ),
    );

TenantReconciliationIntake _intake({
  String status = 'clean',
  int revision = 3,
  int? processedRevision,
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'tenantId': 'tenant-a',
    'businessDate': '2026-07-31',
    'status': status,
    'revision': revision,
    'processedRevision': processedRevision ?? revision,
  };
  if (overrides != null) data.addAll(overrides);
  return TenantReconciliationIntake.fromDocument(
    path: 'tenants/tenant-a/reconciliation_dirty_days/2026-07-31',
    data: data,
  );
}

TenantDailyMetricsRepository _repository(
  TenantDocumentReader reader, {
  TenantRole role = TenantRole.manager,
}) => TenantDailyMetricsRepository(
  session: _session(role),
  reader: reader,
  clock: () => DateTime.utc(2026, 7, 31, 9),
);

TenantSession _session(TenantRole role) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

Matcher _metricsCode(String code) => isA<TenantDailyMetricsException>().having(
  (error) => error.code,
  'code',
  code,
);

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
  // #104: reconciliation writes the net block on every run, so every fixture
  // carries one. A day nothing came back on nets to its own gross figures -
  // which means an override of the gross side moves both, unless the caller
  // states the net side itself.
  data.putIfAbsent('netSales', () => data['sales']);
  data.putIfAbsent('netProfit', () => data['profit']);
  data.putIfAbsent('netTransactions', () => data['transactions']);
  data.putIfAbsent(
    'netIncompleteCostLineCount',
    () => data['incompleteCostLineCount'],
  );
  data.putIfAbsent('returnedSales', () => 0);
  data.putIfAbsent('returnCount', () => 0);
  data.putIfAbsent('netMetricsVersion', () => 1);
  data.removeWhere((key, value) => value == null);
  return data;
}

/// A reader that cannot answer for some paths, the way an offline Firestore
/// cannot answer for a document it has never cached.
final class _UnreachableReader implements TenantDocumentReader {
  _UnreachableReader(this._documents, {required this.unreachable});

  final Map<String, Map<String, Object?>> _documents;
  final Set<String> unreachable;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (unreachable.contains(path)) {
      throw StateError('offline: $path has no cached copy');
    }
    final data = _documents[path];
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }
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
