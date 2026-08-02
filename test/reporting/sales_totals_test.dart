import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_application_1/checkout/checkout_tender.dart';
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
        );
        expect(query.startDate, entry.value, reason: entry.key.name);
        expect(query.endDate, '2026-07-31', reason: entry.key.name);
      }
    });

    test('naming the signed-in member is recognised as my own sales', () async {
      final callable = _Callable(_response());
      final gateway = _gateway(callable);

      final query = gateway.createQuery(
        period: TenantSalesPeriod.today,
        soldById: 'manager-a',
      );
      await gateway.load(query);

      // The scope is derived from the session, never taken from the caller.
      expect(query.soldById, 'manager-a');
      expect(query.scope, TenantSalesScope.mine);
      expect(gateway.selfUid, 'manager-a');
      expect(callable.payloads.single['soldById'], 'manager-a');
    });

    test('naming a colleague is a different scope entirely', () async {
      final callable = _Callable(_response());
      final gateway = _gateway(callable);

      final query = gateway.createQuery(
        period: TenantSalesPeriod.today,
        soldById: 'cashier-b',
      );
      await gateway.load(query);

      expect(query.scope, TenantSalesScope.oneMember);
      expect(callable.payloads.single['soldById'], 'cashier-b');
    });

    test('naming nobody covers the whole business', () {
      final query = _gateway(
        _Callable(_response()),
      ).createQuery(period: TenantSalesPeriod.today);

      expect(query.scope, TenantSalesScope.everyone);
      expect(query.soldById, isNull);
    });

    test('a member the server would reject never leaves the app', () {
      final callable = _Callable(_response());
      final gateway = _gateway(callable);

      expect(
        () => gateway.createQuery(
          period: TenantSalesPeriod.today,
          soldById: 'staff/one',
        ),
        _failure(TenantSalesTotalsFailure.invalidRequest),
      );
      expect(callable.payloads, isEmpty);
    });

    test('a category is sent as the server declared it', () async {
      final callable = _Callable(_response(overrides: {'transactions': 12}));
      final gateway = _gateway(callable);

      final query = gateway.createQuery(
        period: TenantSalesPeriod.today,
        categoryId: 'drinks',
      );
      await gateway.load(query);

      expect(query.categoryId, 'drinks');
      expect(query.isCategoryFiltered, isTrue);
      expect(callable.payloads.single['categoryId'], 'drinks');
    });

    test('no category means the field is absent, not null', () {
      final gateway = _gateway(_Callable(_response()));

      final payload = gateway
          .createQuery(
            period: TenantSalesPeriod.today,
          )
          .toPayload();

      expect(payload.containsKey('categoryId'), isFalse);
      expect(payload.containsKey('soldById'), isFalse);
    });

    test('a category the server would reject never leaves the app', () {
      final callable = _Callable(_response());
      final gateway = _gateway(callable);

      expect(
        () => gateway.createQuery(
          period: TenantSalesPeriod.today,
          categoryId: 'drinks/cold',
        ),
        _failure(TenantSalesTotalsFailure.invalidRequest),
      );
      expect(callable.payloads, isEmpty);
    });

    test('a cashier is refused before anything is sent', () {
      final callable = _Callable(_response());
      final gateway = _gateway(callable, role: TenantRole.cashier);

      expect(
        () => gateway.createQuery(
          period: TenantSalesPeriod.today,
          soldById: 'manager-a',
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
      );

      await expectLater(_gateway(callable).load(query), throwsStateError);
      expect(callable.payloads, isEmpty);
    });
  });

  group('decoding the answer', () {
    Future<TenantSalesTotals> load(Object? response, {String? categoryId}) {
      final gateway = _gateway(_Callable(response));
      return gateway.load(
        gateway.createQuery(
          period: TenantSalesPeriod.today,
          categoryId: categoryId,
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

    test('without a category the two counts must agree exactly', () async {
      // The server counts one transaction per sale it read, so any difference
      // describes another request.
      await expectRefused(
        _response(scanned: 37, overrides: {'transactions': 36}),
      );
      await expectRefused(
        _response(scanned: 37, overrides: {'transactions': 38}),
      );
    });

    test('with a category, fewer counted than read is correct', () async {
      // `aggregateSales` skips a sale holding no matching line, so 37 sales
      // read and 12 counted is exactly what a category answer looks like.
      final totals = await load(
        _response(scanned: 37, overrides: {'transactions': 12}),
        categoryId: 'drinks',
      );

      expect(totals.transactions, 12);
      expect(totals.scannedTransactions, 37);
      expect(totals.query.isCategoryFiltered, isTrue);
    });

    test('with a category, more counted than read is still refused', () async {
      // Nothing the handler can do produces this; it cannot count a sale it
      // never read.
      await expectLater(
        load(
          _response(scanned: 12, overrides: {'transactions': 13}),
          categoryId: 'drinks',
        ),
        throwsA(isA<FormatException>()),
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

  group('decoding the tender split', () {
    Future<TenantSalesTotals> load(Object? response, {String? categoryId}) {
      final gateway = _gateway(_Callable(response));
      return gateway.load(
        gateway.createQuery(
          period: TenantSalesPeriod.today,
          categoryId: categoryId,
        ),
      );
    }

    Future<void> expectRefused(Object? byTender) => expectLater(
      load(_response(byTender: byTender)),
      throwsA(isA<FormatException>()),
    );

    test('a server that reports no split leaves the totals alone', () async {
      // Absent is not a failure: the figure the manager came for does not
      // depend on the split, so it is shown without one.
      final totals = await load(_response());

      expect(totals.tenderBreakdown, isNull);
      expect(totals.sales, 4820.75);
      expect(totals.transactions, 37);
    });

    test('every bucket is decoded and the whole split is kept', () async {
      final totals = await load(_response(byTender: _byTender()));
      final breakdown = totals.tenderBreakdown!;

      expect(breakdown.recorded[CheckoutTender.cash]!.sales, 2000.25);
      expect(breakdown.recorded[CheckoutTender.cash]!.transactions, 20);
      expect(breakdown.recorded[CheckoutTender.mpesa]!.sales, 1800.5);
      expect(breakdown.recorded[CheckoutTender.mpesa]!.transactions, 10);
      expect(breakdown.recorded[CheckoutTender.card]!.sales, 900);
      expect(breakdown.recorded[CheckoutTender.card]!.transactions, 5);
      expect(breakdown.unrecorded.sales, 100);
      expect(breakdown.unrecorded.transactions, 1);
      expect(breakdown.unrecognised.sales, 20);
      expect(breakdown.unrecognised.transactions, 1);
      expect(breakdown.hasRecordedTenders, isTrue);
    });

    test('a split that does not add up is refused', () async {
      // The one figure an owner acts on must not be described by a split that
      // disagrees with it, in either direction and in either dimension.
      await expectRefused(_byTender(cashSales: 2000.26));
      await expectRefused(_byTender(cashSales: 2000.24));
      await expectRefused(_byTender(cashTransactions: 21));
      await expectRefused(_byTender(cashTransactions: 19));
    });

    test('the sum is compared in minor units, not in doubles', () async {
      // 0.1 + 0.2 is 0.30000000000000004 as doubles, so comparing the amounts
      // directly would refuse a split that is exactly right. The server adds
      // whole minor units, and so does this check.
      final totals = await load(
        _response(
          scanned: 2,
          overrides: {'sales': 0.3, 'profit': 0.3, 'transactions': 2},
          byTender: _byTender(
            cashSales: 0.1,
            cashTransactions: 1,
            mpesaSales: 0.2,
            mpesaTransactions: 1,
            cardSales: 0,
            cardTransactions: 0,
            unrecordedSales: 0,
            unrecordedTransactions: 0,
            otherSales: 0,
            otherTransactions: 0,
          ),
        ),
      );

      expect(totals.tenderBreakdown, isNotNull);
      expect(0.1 + 0.2 == 0.3, isFalse);
    });

    test('the check is on the sum, which is all the client can know', () async {
      // One bucket a cent low and another a cent high still adds up, and is
      // accepted: nothing here can independently know what any single bucket
      // should be, so claiming to check one would be a check in name only.
      final totals = await load(
        _response(byTender: _byTender(cashSales: 2000.24, cardSales: 900.01)),
      );

      expect(totals.tenderBreakdown!.recorded[CheckoutTender.cash]!.sales,
          2000.24);
    });

    test('a bucket set that is not the expected five is refused', () async {
      final missing = _byTender()..remove('card');
      await expectRefused(missing);
      final extra = _byTender()
        ..['voucher'] = <String, Object?>{'sales': 0, 'transactions': 0};
      await expectRefused(extra);
      await expectRefused(<String, Object?>{});
    });

    test('a bucket that is not the expected shape is refused', () async {
      await expectRefused(_byTender()..['cash'] = 'lots');
      await expectRefused(
        _byTender()..['cash'] = <String, Object?>{'sales': 2000.25},
      );
      await expectRefused(
        _byTender()
          ..['cash'] = <String, Object?>{
            'sales': -1,
            'transactions': 20,
          },
      );
      await expectRefused(
        _byTender()
          ..['cash'] = <String, Object?>{
            'sales': 2000.25,
            'transactions': 20.0,
          },
      );
      await expectRefused('cash');
    });

    test('an empty period splits into nothing and still adds up', () async {
      final totals = await load(
        _response(
          scanned: 0,
          overrides: {
            'sales': 0,
            'profit': 0,
            'transactions': 0,
            'incompleteCostLineCount': 0,
          },
          byTender: _byTender(
            cashSales: 0,
            cashTransactions: 0,
            mpesaSales: 0,
            mpesaTransactions: 0,
            cardSales: 0,
            cardTransactions: 0,
            unrecordedSales: 0,
            unrecordedTransactions: 0,
            otherSales: 0,
            otherTransactions: 0,
          ),
        ),
      );
      final breakdown = totals.tenderBreakdown!;

      expect(breakdown.hasRecordedTenders, isFalse);
      expect(breakdown.unrecorded.isEmpty, isTrue);
      expect(breakdown.unrecognised.isEmpty, isTrue);
    });

    test('a category answer is checked against its own narrower total',
        () async {
      // With a category the server counts fewer sales than it read, and the
      // split must add up to what it counted rather than to what it scanned.
      final totals = await load(
        _response(
          scanned: 37,
          overrides: {'transactions': 12, 'sales': 300},
          byTender: _byTender(
            cashSales: 200,
            cashTransactions: 8,
            mpesaSales: 100,
            mpesaTransactions: 4,
            cardSales: 0,
            cardTransactions: 0,
            unrecordedSales: 0,
            unrecordedTransactions: 0,
            otherSales: 0,
            otherTransactions: 0,
          ),
        ),
        categoryId: 'drinks',
      );

      expect(totals.tenderBreakdown!.recorded[CheckoutTender.cash]!.sales, 200);
      expect(totals.scannedTransactions, 37);
      expect(totals.transactions, 12);
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
  Object? byTender,
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
    if (byTender != null) 'byTender': byTender,
  };
}

/// The five buckets the handler returns, summing to the default `_response`.
Map<String, Object?> _byTender({
  double cashSales = 2000.25,
  int cashTransactions = 20,
  double mpesaSales = 1800.5,
  int mpesaTransactions = 10,
  double cardSales = 900,
  int cardTransactions = 5,
  double unrecordedSales = 100,
  int unrecordedTransactions = 1,
  double otherSales = 20,
  int otherTransactions = 1,
}) => <String, Object?>{
  'cash': <String, Object?>{
    'sales': cashSales,
    'transactions': cashTransactions,
  },
  'mpesa': <String, Object?>{
    'sales': mpesaSales,
    'transactions': mpesaTransactions,
  },
  'card': <String, Object?>{
    'sales': cardSales,
    'transactions': cardTransactions,
  },
  'unrecorded': <String, Object?>{
    'sales': unrecordedSales,
    'transactions': unrecordedTransactions,
  },
  'other': <String, Object?>{
    'sales': otherSales,
    'transactions': otherTransactions,
  },
};

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
