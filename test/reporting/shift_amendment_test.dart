import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shift amendment gateway', () {
    test('sends the session tenant, the shift, and a reason only', () async {
      final callable = _Callable(_response());

      final gateway = _gateway(callable);
      final result = await gateway.submit(
        gateway.createIntent(shiftId: 'shift-a', reason: 'Late offline sale'),
      );

      // The business is never an input, and neither is the corrected figure:
      // the server reads that from the sale-derived total it verified, so no
      // payload from here can name a number.
      expect(callable.payloads.single, <String, Object?>{
        'tenantId': 'tenant-a',
        'shiftId': 'shift-a',
        'reason': 'Late offline sale',
        'requestId': 'amend-shift-abcdefgh',
      });
      expect(result.amendmentId, 'sm_abc');
      expect(result.tenantId, 'tenant-a');
      expect(result.shiftId, 'shift-a');
      expect(result.businessDate, '2026-07-31');
      expect(result.previousTotalSalesMinor, 120050);
      expect(result.totalSalesMinor, 135025);
      expect(result.previousTransactionCount, 9);
      expect(result.transactionCount, 10);
      expect(result.salesVarianceMinor, -14975);
      expect(result.transactionVariance, -1);
      expect(result.clearedAnomalyId, 'shift_abc');
    });

    test('the reason is normalized exactly as the server will', () async {
      final callable = _Callable(_response());
      final gateway = _gateway(callable);

      await gateway.submit(
        gateway.createIntent(
          shiftId: 'shift-a',
          reason: '  Late   offline\tsale\n ',
        ),
      );

      // Sending the already-normalized value is what makes a retry hash to the
      // same idempotency record instead of being refused as one request with
      // two different inputs.
      expect(callable.payloads.single['reason'], 'Late offline sale');
    });

    test('an unusable reason is refused before anything is sent', () {
      final callable = _Callable(_response());
      final gateway = _gateway(callable);

      for (final reason in <String>[
        '',
        '  ',
        'no',
        '  a  ',
        'a' * 501,
        // A control character whitespace collapsing does not remove is the
        // server's own \p{Cc} refusal, reproduced here so it costs no round
        // trip.
        'Late\u0000sale',
        'Late\u0007sale',
      ]) {
        expect(
          () => gateway.createIntent(shiftId: 'shift-a', reason: reason),
          _failure(TenantShiftAmendmentFailure.invalidReason),
          reason: reason,
        );
      }
      expect(callable.payloads, isEmpty);

      // The bounds themselves are the server's: exactly three characters after
      // trimming is enough, and exactly five hundred still is.
      expect(
        gateway.createIntent(shiftId: 'shift-a', reason: ' abc ').reason,
        'abc',
      );
      expect(
        gateway.createIntent(shiftId: 'shift-a', reason: 'a' * 500).reason,
        'a' * 500,
      );
    });

    test('one intent keeps one request ID across a retry', () async {
      final callable = _Callable(_response());
      final gateway = _gateway(
        callable,
        requestIds: <String>['amend-shift-first11', 'amend-shift-second2'],
      );

      final intent = gateway.createIntent(
        shiftId: 'shift-a',
        reason: 'Late offline sale',
      );
      await gateway.submit(intent);
      await gateway.submit(intent);

      // The server's idempotency record settles the repeat, so a retry cannot
      // write a second amendment of the same shift.
      expect(callable.payloads.map((payload) => payload['requestId']), <String>[
        'amend-shift-first11',
        'amend-shift-first11',
      ]);
    });

    test('a manager cannot correct a shift even though it reads the list', () {
      // The server's SHIFT_AMENDMENT_ROLES is narrower than the roles that read
      // the differences, and the client refuses first.
      final gateway = _gateway(
        _Callable(_response()),
        role: TenantRole.manager,
      );

      expect(
        () => gateway.createIntent(shiftId: 'shift-a', reason: 'Late sale'),
        _failure(TenantShiftAmendmentFailure.forbidden),
      );
      expect(
        TenantShiftAmendmentGateway.canAmendInSession(
          TenantSession.active(
            uid: 'manager-a',
            tenantId: 'tenant-a',
            role: TenantRole.manager,
          ),
        ),
        isFalse,
      );
      expect(
        TenantShiftAmendmentGateway.canAmendInSession(
          TenantSession.active(
            uid: 'cashier-a',
            tenantId: 'tenant-a',
            role: TenantRole.cashier,
          ),
        ),
        isFalse,
      );
    });

    test('an owner and an administrator may correct a shift', () {
      for (final role in <TenantRole>[TenantRole.owner, TenantRole.admin]) {
        expect(
          TenantShiftAmendmentGateway.canAmendInSession(
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
    });

    test('a shift ID no path could hold is refused locally', () async {
      final callable = _Callable(_response());
      final gateway = _gateway(callable);

      for (final shiftId in <String>['', 'shift/a', ' shift-a', '..']) {
        expect(
          () => gateway.createIntent(shiftId: shiftId, reason: 'Late sale'),
          _failure(TenantShiftAmendmentFailure.invalidRequest),
          reason: shiftId,
        );
      }
      expect(callable.payloads, isEmpty);
    });

    test('a request ID the server would reject is a programming error', () {
      final gateway = _gateway(
        _Callable(_response()),
        requestIds: <String>['short'],
      );

      // Caught here rather than as an opaque invalid-argument round trip.
      expect(
        () => gateway.createIntent(shiftId: 'shift-a', reason: 'Late sale'),
        throwsStateError,
      );
    });

    test('an intent from another business is never sent', () async {
      final callable = _Callable(_response());
      final other = _gateway(callable, tenantId: 'tenant-b');
      final intent = other.createIntent(
        shiftId: 'shift-a',
        reason: 'Late offline sale',
      );

      await expectLater(_gateway(callable).submit(intent), throwsStateError);
      expect(callable.payloads, isEmpty);
    });
  });

  group('classifying a refusal', () {
    final cases = <String, TenantShiftAmendmentFailure>{
      'permission-denied': TenantShiftAmendmentFailure.forbidden,
      'unauthenticated': TenantShiftAmendmentFailure.forbidden,
      // The most likely refusal in practice, and the one a person can act on:
      // the shift is open, already agrees with its sales, has no settled
      // variance, or recorded no readable totals.
      'failed-precondition': TenantShiftAmendmentFailure.notAmendable,
      'not-found': TenantShiftAmendmentFailure.shiftNotFound,
      'already-exists': TenantShiftAmendmentFailure.duplicateRequest,
      'invalid-argument': TenantShiftAmendmentFailure.invalidRequest,
      'unavailable': TenantShiftAmendmentFailure.ambiguous,
      'deadline-exceeded': TenantShiftAmendmentFailure.ambiguous,
      'internal': TenantShiftAmendmentFailure.ambiguous,
      'aborted': TenantShiftAmendmentFailure.ambiguous,
      'unknown': TenantShiftAmendmentFailure.ambiguous,
      'resource-exhausted': TenantShiftAmendmentFailure.refused,
      'a-code-this-build-never-saw': TenantShiftAmendmentFailure.refused,
    };

    for (final entry in cases.entries) {
      test('${entry.key} is ${entry.value.name}', () async {
        final gateway = _gateway(
          _Callable.failing(
            FirebaseFunctionsException(code: entry.key, message: 'refused'),
          ),
        );

        await expectLater(
          gateway.submit(
            gateway.createIntent(shiftId: 'shift-a', reason: 'Late sale'),
          ),
          _failure(entry.value),
        );
      });
    }

    test('a timeout and an unknown throw are both ambiguous', () async {
      for (final error in <Object>[TimeoutException('slow'), StateError('x')]) {
        final gateway = _gateway(_Callable.failing(error));
        await expectLater(
          gateway.submit(
            gateway.createIntent(shiftId: 'shift-a', reason: 'Late sale'),
          ),
          _failure(TenantShiftAmendmentFailure.ambiguous),
        );
      }
    });

    test('only an unknown outcome may have amended anything', () {
      for (final failure in TenantShiftAmendmentFailure.values) {
        expect(
          TenantShiftAmendmentException(failure).mayHaveAmended,
          failure == TenantShiftAmendmentFailure.ambiguous,
          reason: failure.name,
        );
      }
    });
  });

  group('decoding the response', () {
    Future<void> expectRefused(Object? response) async {
      final gateway = _gateway(_Callable(response));
      await expectLater(
        gateway.submit(
          gateway.createIntent(shiftId: 'shift-a', reason: 'Late sale'),
        ),
        throwsA(isA<FormatException>()),
      );
    }

    test('a response naming another business is refused', () async {
      // Displaying it would tell an owner a shift of theirs was rewritten on
      // the strength of an answer about somebody else's business.
      await expectRefused(_response(overrides: {'tenantId': 'tenant-b'}));
      await expectRefused(_response(overrides: {'tenantId': null}));
    });

    test('a response naming another shift is refused', () async {
      await expectRefused(_response(overrides: {'shiftId': 'shift-b'}));
    });

    test('an unusable amendment or anomaly ID is refused', () async {
      await expectRefused(_response(overrides: {'amendmentId': 'sm/abc'}));
      await expectRefused(_response(overrides: {'amendmentId': 7}));
      await expectRefused(_response(overrides: {'clearedAnomalyId': 'a/b'}));
    });

    test('a business date that is not one is refused', () async {
      await expectRefused(_response(overrides: {'businessDate': '31-07-2026'}));
      await expectRefused(_response(overrides: {'businessDate': 7}));
    });

    test('a figure outside what a shift may hold is refused', () async {
      for (final field in <String>[
        'previousTotalSalesMinor',
        'totalSalesMinor',
        'previousTransactionCount',
        'transactionCount',
      ]) {
        await expectRefused(_response(overrides: {field: -1}));
        await expectRefused(_response(overrides: {field: 1.5}));
        await expectRefused(_response(overrides: {field: null}));
      }
    });

    test('a transaction difference that contradicts its counts is refused', () {
      // Both counts come from one comparison, so the identity is exact and a
      // response that breaks it did not come from the handler.
      return expectRefused(_response(overrides: {'transactionVariance': 4}));
    });

    test('the money difference is deliberately not cross-checked', () async {
      // The recorded variance is measured from the shift's major-unit total,
      // which may legitimately disagree with its stored minor units, so
      // asserting an identity that can fail honestly would refuse a real
      // amendment. The range is still checked.
      final gateway = _gateway(
        _Callable(_response(overrides: {'salesVarianceMinor': 7})),
      );
      final result = await gateway.submit(
        gateway.createIntent(shiftId: 'shift-a', reason: 'Late sale'),
      );

      expect(result.salesVarianceMinor, 7);
      await expectRefused(
        _response(overrides: {'salesVarianceMinor': 'a lot'}),
      );
    });

    test('an amendment that clears no listed difference is accepted', () async {
      // Null is a real answer: no difference was listed under this shift's
      // generation, or the record at that ID described something else.
      final gateway = _gateway(
        _Callable(_response(overrides: {'clearedAnomalyId': null})),
      );
      final result = await gateway.submit(
        gateway.createIntent(shiftId: 'shift-a', reason: 'Late sale'),
      );

      expect(result.clearedAnomalyId, isNull);
    });

    test('an amendment that leaves both totals equal is accepted', () async {
      // This is reachable: a shift whose stored minor units already matched
      // while its major-unit total did not is amended, and its counts need not
      // change. Refusing it would refuse a real correction.
      final gateway = _gateway(
        _Callable(
          _response(
            overrides: {
              'previousTotalSalesMinor': 135025,
              'previousTransactionCount': 10,
              'transactionVariance': 0,
              'salesVarianceMinor': -14975,
            },
          ),
        ),
      );
      final result = await gateway.submit(
        gateway.createIntent(shiftId: 'shift-a', reason: 'Late sale'),
      );

      expect(result.totalSalesMinor, result.previousTotalSalesMinor);
      expect(result.transactionVariance, 0);
    });

    test('a response that is not a map at all is refused', () async {
      await expectRefused('amended');
      await expectRefused(null);
    });
  });

  test('a generated request ID matches the pattern the server accepts', () {
    final pattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
    for (var attempt = 0; attempt < 32; attempt++) {
      final requestId = secureShiftAmendmentRequestId();
      expect(pattern.hasMatch(requestId), isTrue, reason: requestId);
    }
  });
}

TenantShiftAmendmentGateway _gateway(
  _Callable callable, {
  TenantRole role = TenantRole.owner,
  String tenantId = 'tenant-a',
  List<String> requestIds = const <String>['amend-shift-abcdefgh'],
}) {
  var index = 0;
  return TenantShiftAmendmentGateway(
    session: TenantSession.active(
      uid: 'owner-a',
      tenantId: tenantId,
      role: role,
    ),
    callable: callable,
    requestIdFactory: () =>
        requestIds[index++ < requestIds.length
            ? index - 1
            : requestIds.length - 1],
  );
}

Matcher _failure(TenantShiftAmendmentFailure failure) => throwsA(
  isA<TenantShiftAmendmentException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

Map<String, Object?> _response({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'amendmentId': 'sm_abc',
    'tenantId': 'tenant-a',
    'shiftId': 'shift-a',
    'businessDate': '2026-07-31',
    'previousTotalSalesMinor': 120050,
    'previousTransactionCount': 9,
    'totalSalesMinor': 135025,
    'transactionCount': 10,
    'salesVarianceMinor': -14975,
    'transactionVariance': -1,
    'clearedAnomalyId': 'shift_abc',
  };
  if (overrides != null) data.addAll(overrides);
  return data;
}

final class _Callable implements AmendShiftSummaryCallable {
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
