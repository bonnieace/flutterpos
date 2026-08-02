import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('building a query', () {
    test('today asks for one business date and the whole business', () async {
      final callable = _Callable(_response());
      final gateway = _gateway(callable);

      final query = gateway.createQuery(
        period: TenantSalesPeriod.today,
        scope: TenantSalesScope.everyone,
      );
      await gateway.load(query);

      // The Africa/Nairobi business day is the same one the checkout stamps on
      // every sale, so 09:00 UTC is already 31 July at the counter.
      expect(query.startDate, '2026-07-31');
      expect(query.endDate, '2026-07-31');
      expect(callable.payloads.single, <String, Object?>{
        'tenantId': 'tenant-a',
        'previousStartDate': '2026-07-31',
        'previousEndDate': '2026-07-31',
      });
    });

    test('a longer period is inclusive of both ends', () {
      final gateway = _gateway(_Callable(_response()));

      for (final entry in <TenantSalesPeriod, String>{
        TenantSalesPeriod.last7Days: '2026-07-25',
        TenantSalesPeriod.last30Days: '2026-07-02',
        TenantSalesPeriod.last90Days: '2026-05-03',
      }.entries) {
        final query = gateway.createQuery(
          period: entry.key,
          scope: TenantSalesScope.everyone,
        );
        expect(query.startDate, entry.value, reason: entry.key.name);
        expect(query.endDate, '2026-07-31', reason: entry.key.name);
      }
    });

    test('only mine filters by the session UID and nothing else', () async {
      final callable = _Callable(_response());
      final gateway = _gateway(callable);

      final query = gateway.createQuery(
        period: TenantSalesPeriod.today,
        scope: TenantSalesScope.mine,
      );
      await gateway.load(query);

      // The member is never an input: it comes from the captured session, so
      // no caller can total somebody else's sales.
      expect(query.soldById, 'manager-a');
      expect(callable.payloads.single['soldById'], 'manager-a');
    });

    test('a cashier is refused before anything is sent', () {
      final callable = _Callable(_response());
      final gateway = _gateway(callable, role: TenantRole.cashier);

      expect(
        () => gateway.createQuery(
          period: TenantSalesPeriod.today,
          scope: TenantSalesScope.mine,
        ),
        _failure(TenantSalesTotalsFailure.forbidden),
      );
      expect(callable.payloads, isEmpty);
    });

    test('the reading roles are the server reporting roles', () {
      // Identical to the daily summary's, because a period total is the same
      // information over a different stretch of days.
      expect(
        TenantSalesTotalsGateway.allowedRoles,
        TenantDailyMetricsRepository.allowedRoles,
      );
      for (final role in <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ]) {
        expect(
          TenantSalesTotalsGateway.canReadInSession(
            TenantSession.active(
              uid: 'user-a',
              tenantId: 'tenant-a',
              role: role,
            ),
          ),
          isTrue,
          reason: role.name,
        );
      }
      expect(
        TenantSalesTotalsGateway.canReadInSession(
          TenantSession.active(
            uid: 'user-a',
            tenantId: 'tenant-a',
            role: TenantRole.cashier,
          ),
        ),
        isFalse,
      );
    });

    test('a query from another business is never sent', () async {
      final callable = _Callable(_response());
      final other = _gateway(callable, tenantId: 'tenant-b');
      final query = other.createQuery(
        period: TenantSalesPeriod.today,
        scope: TenantSalesScope.everyone,
      );

      await expectLater(_gateway(callable).load(query), throwsStateError);
      expect(callable.payloads, isEmpty);
    });
  });

  group('decoding the answer', () {
    Future<TenantSalesTotals> load(Object? response) {
      final gateway = _gateway(_Callable(response));
      return gateway.load(
        gateway.createQuery(
          period: TenantSalesPeriod.today,
          scope: TenantSalesScope.everyone,
        ),
      );
    }

    Future<void> expectRefused(Object? response) => expectLater(
      load(response),
      throwsA(isA<FormatException>()),
    );

    test('totals are reported exactly as the server added them', () async {
      final totals = await load(_response());

      expect(totals.sales, 4820.75);
      expect(totals.transactions, 37);
      expect(totals.incompleteCostLineCount, 96);
      expect(totals.hasCompleteCostData, isFalse);
      expect(totals.query.period, TenantSalesPeriod.today);
    });

    test('a count that disagrees with what was read is refused', () async {
      // No category filter is ever sent, so the server counts one transaction
      // per sale it read. A different count describes another request.
      await expectRefused(
        _response(scanned: 37, overrides: {'transactions': 36}),
      );
    });

    test('more sales than the server may add up is refused', () async {
      await expectRefused(
        _response(
          scanned: TenantSalesTotals.maximumTransactions + 1,
          overrides: {
            'transactions': TenantSalesTotals.maximumTransactions + 1,
          },
        ),
      );
    });

    test('a response that is not the expected shape is refused', () async {
      await expectRefused(null);
      await expectRefused('4820.75');
      await expectRefused(<String, Object?>{'scannedTransactions': 0});
      await expectRefused(<String, Object?>{
        'previous': 'none',
        'scannedTransactions': 0,
      });
    });

    test('an unusable figure is refused rather than shown', () async {
      await expectRefused(_response(overrides: {'sales': -1}));
      await expectRefused(_response(overrides: {'sales': 'lots'}));
      await expectRefused(_response(overrides: {'sales': 1e13}));
      await expectRefused(_response(overrides: {'profit': double.nan}));
      await expectRefused(
        _response(overrides: {'incompleteCostLineCount': -1}),
      );
      await expectRefused(_response(overrides: {'transactions': 37.0}));
    });

    test('a loss is a legitimate answer and is accepted', () async {
      // Profit may be negative; only revenue may not.
      final totals = await load(_response(overrides: {'profit': -12.5}));

      expect(totals.profit, -12.5);
    });

    test('an empty period is a real answer, not a failure', () async {
      final totals = await load(
        _response(
          scanned: 0,
          overrides: {
            'sales': 0,
            'profit': 0,
            'transactions': 0,
            'incompleteCostLineCount': 0,
          },
        ),
      );

      expect(totals.sales, 0);
      expect(totals.transactions, 0);
      expect(totals.hasCompleteCostData, isTrue);
    });
  });

  group('classifying a refusal', () {
    final cases = <String, TenantSalesTotalsFailure>{
      'permission-denied': TenantSalesTotalsFailure.forbidden,
      'unauthenticated': TenantSalesTotalsFailure.forbidden,
      'resource-exhausted': TenantSalesTotalsFailure.periodTooLarge,
      'invalid-argument': TenantSalesTotalsFailure.invalidRequest,
      'failed-precondition': TenantSalesTotalsFailure.unusableSaleData,
      'unavailable': TenantSalesTotalsFailure.unavailable,
      'deadline-exceeded': TenantSalesTotalsFailure.unavailable,
      'internal': TenantSalesTotalsFailure.unavailable,
      'aborted': TenantSalesTotalsFailure.unavailable,
      'unknown': TenantSalesTotalsFailure.unavailable,
      'not-found': TenantSalesTotalsFailure.refused,
      'already-exists': TenantSalesTotalsFailure.refused,
      'a-code-this-build-never-saw': TenantSalesTotalsFailure.refused,
    };

    for (final entry in cases.entries) {
      test('${entry.key} is ${entry.value.name}', () async {
        final gateway = _gateway(
          _Callable.failing(
            FirebaseFunctionsException(code: entry.key, message: 'refused'),
          ),
        );

        await expectLater(
          gateway.load(
            gateway.createQuery(
              period: TenantSalesPeriod.today,
              scope: TenantSalesScope.everyone,
            ),
          ),
          _failure(entry.value),
        );
      });
    }

    test('a timeout and an unknown throw are both unavailable', () async {
      for (final error in <Object>[TimeoutException('slow'), StateError('x')]) {
        final gateway = _gateway(_Callable.failing(error));
        await expectLater(
          gateway.load(
            gateway.createQuery(
              period: TenantSalesPeriod.today,
              scope: TenantSalesScope.everyone,
            ),
          ),
          _failure(TenantSalesTotalsFailure.unavailable),
        );
      }
    });
  });

  test('every period stays inside the range the server accepts', () {
    for (final period in TenantSalesPeriod.values) {
      expect(period.days, greaterThan(0), reason: period.name);
      // The handler's `assertDateRange` refuses more than 366 days.
      expect(period.days, lessThanOrEqualTo(366), reason: period.name);
    }
  });
}

TenantSalesTotalsGateway _gateway(
  _Callable callable, {
  TenantRole role = TenantRole.manager,
  String tenantId = 'tenant-a',
}) => TenantSalesTotalsGateway(
  session: TenantSession.active(
    uid: 'manager-a',
    tenantId: tenantId,
    role: role,
  ),
  callable: callable,
  clock: () => DateTime.utc(2026, 7, 31, 9),
);

Matcher _failure(TenantSalesTotalsFailure failure) => throwsA(
  isA<TenantSalesTotalsException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

Map<String, Object?> _response({
  int scanned = 37,
  Map<String, Object?>? overrides,
}) {
  final previous = <String, Object?>{
    'sales': 4820.75,
    'profit': 4820.75,
    'transactions': 37,
    'incompleteCostLineCount': 96,
  };
  if (overrides != null) previous.addAll(overrides);
  return <String, Object?>{
    'previous': previous,
    'scannedTransactions': scanned,
  };
}

final class _Callable implements SalesTotalsCallable {
  _Callable(this._response) : _error = null;
  _Callable.failing(Object error) : _response = null, _error = error;

  final Object? _response;
  final Object? _error;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    final error = _error;
    if (error != null) throw error;
    return _response;
  }
}
