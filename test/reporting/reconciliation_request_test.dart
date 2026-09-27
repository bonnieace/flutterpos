import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reconciliation request gateway', () {
    test('sends the session tenant and the chosen mode only', () async {
      final callable = _Callable(_response(overrides: {'mode': 'full'}));

      final gateway = _gateway(callable);
      final result = await gateway.submit(
        gateway.createIntent(mode: TenantReconciliationMode.full),
      );

      // The business is never an input: it comes from the captured session, so
      // no caller can ask the server to reconcile somebody else.
      expect(callable.payloads.single, <String, Object?>{
        'tenantId': 'tenant-a',
        'mode': 'full',
        'requestId': 'reconcile-abcdefgh',
      });
      expect(result.jobId, 'rj_abc');
      expect(result.tenantId, 'tenant-a');
      expect(result.mode, TenantReconciliationMode.full);
    });

    test('one intent keeps one request ID across a retry', () async {
      final callable = _Callable(_response());
      final gateway = _gateway(
        callable,
        requestIds: <String>['reconcile-first11', 'reconcile-second2'],
      );

      final intent = gateway.createIntent(
        mode: TenantReconciliationMode.incremental,
      );
      await gateway.submit(intent);
      await gateway.submit(intent);

      // The server's idempotency record settles the repeat, so a retry cannot
      // spend the cooldown a second time.
      expect(callable.payloads.map((payload) => payload['requestId']), <String>[
        'reconcile-first11',
        'reconcile-first11',
      ]);
    });

    test('a manager cannot request even though it can read the page', () {
      // The server's RECONCILIATION_REQUEST_ROLES is narrower than the roles
      // that read reconciliation status, and the client refuses first.
      final gateway = _gateway(
        _Callable(_response()),
        role: TenantRole.manager,
      );

      expect(
        () => gateway.createIntent(mode: TenantReconciliationMode.incremental),
        _failure(TenantReconciliationRequestFailure.forbidden),
      );
      expect(
        TenantReconciliationRequestGateway.canRequestInSession(
          TenantSession.active(
            uid: 'manager-a',
            tenantId: 'tenant-a',
            role: TenantRole.manager,
          ),
        ),
        isFalse,
      );
    });

    test('an owner and an administrator may request', () {
      for (final role in <TenantRole>[TenantRole.owner, TenantRole.admin]) {
        expect(
          TenantReconciliationRequestGateway.canRequestInSession(
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

    test('a request ID the server would reject is a programming error', () {
      final gateway = _gateway(
        _Callable(_response()),
        requestIds: <String>['short'],
      );

      // Caught here rather than as an opaque invalid-argument round trip.
      expect(
        () => gateway.createIntent(mode: TenantReconciliationMode.incremental),
        throwsStateError,
      );
    });

    test('an intent from another business is never sent', () async {
      final callable = _Callable(_response());
      final other = _gateway(callable, tenantId: 'tenant-b');
      final intent = other.createIntent(
        mode: TenantReconciliationMode.incremental,
      );

      await expectLater(_gateway(callable).submit(intent), throwsStateError);
      expect(callable.payloads, isEmpty);
    });
  });

  group('classifying a refusal', () {
    final cases = <String, TenantReconciliationRequestFailure>{
      'permission-denied': TenantReconciliationRequestFailure.forbidden,
      'unauthenticated': TenantReconciliationRequestFailure.forbidden,
      'resource-exhausted':
          TenantReconciliationRequestFailure.requestedTooRecently,
      'already-exists': TenantReconciliationRequestFailure.duplicateRequest,
      'invalid-argument': TenantReconciliationRequestFailure.invalidRequest,
      'unavailable': TenantReconciliationRequestFailure.ambiguous,
      'deadline-exceeded': TenantReconciliationRequestFailure.ambiguous,
      'internal': TenantReconciliationRequestFailure.ambiguous,
      'aborted': TenantReconciliationRequestFailure.ambiguous,
      'unknown': TenantReconciliationRequestFailure.ambiguous,
      'not-found': TenantReconciliationRequestFailure.refused,
      'failed-precondition': TenantReconciliationRequestFailure.refused,
      'a-code-this-build-never-saw': TenantReconciliationRequestFailure.refused,
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
            gateway.createIntent(mode: TenantReconciliationMode.incremental),
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
            gateway.createIntent(mode: TenantReconciliationMode.incremental),
          ),
          _failure(TenantReconciliationRequestFailure.ambiguous),
        );
      }
    });

    test('only an unknown outcome may have queued anything', () {
      for (final failure in TenantReconciliationRequestFailure.values) {
        expect(
          TenantReconciliationRequestException(failure).mayHaveQueued,
          failure == TenantReconciliationRequestFailure.ambiguous,
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
          gateway.createIntent(mode: TenantReconciliationMode.incremental),
        ),
        throwsA(isA<FormatException>()),
      );
    }

    test('a response naming another business is refused', () async {
      // Displaying it would tell an owner their business is being re-checked
      // on the strength of somebody else's job.
      await expectRefused(_response(overrides: {'tenantId': 'tenant-b'}));
    });

    test('a response naming another mode is refused', () async {
      await expectRefused(_response(overrides: {'mode': 'full'}));
    });

    test('a status the handler never writes is refused', () async {
      await expectRefused(_response(overrides: {'status': 'running'}));
    });

    test('an unusable job ID is refused', () async {
      await expectRefused(_response(overrides: {'jobId': 'rj/abc'}));
      await expectRefused(_response(overrides: {'jobId': 7}));
    });

    test('a response that is not a map at all is refused', () async {
      await expectRefused('queued');
      await expectRefused(null);
    });
  });

  test('each mode carries the cooldown the server enforces', () {
    expect(
      TenantReconciliationMode.incremental.cooldown,
      const Duration(minutes: 5),
    );
    expect(TenantReconciliationMode.full.cooldown, const Duration(hours: 24));
    expect(TenantReconciliationMode.incremental.wireValue, 'incremental');
    expect(TenantReconciliationMode.full.wireValue, 'full');
  });
}

TenantReconciliationRequestGateway _gateway(
  _Callable callable, {
  TenantRole role = TenantRole.owner,
  String tenantId = 'tenant-a',
  List<String> requestIds = const <String>['reconcile-abcdefgh'],
}) {
  var index = 0;
  return TenantReconciliationRequestGateway(
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

Matcher _failure(TenantReconciliationRequestFailure failure) => throwsA(
  isA<TenantReconciliationRequestException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

Map<String, Object?> _response({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'tenantId': 'tenant-a',
    'jobId': 'rj_abc',
    'mode': 'incremental',
    'status': 'queued',
  };
  if (overrides != null) data.addAll(overrides);
  return data;
}

final class _Callable implements RequestReconciliationCallable {
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
