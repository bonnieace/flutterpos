import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_application_1/returns/returns.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('verification gateway', () {
    test('sends the session tenant and the decoded return only', () async {
      final callable = _Callable(_response());

      final gateway = _gateway(callable);
      final result = await gateway.submit(gateway.createIntent());

      expect(callable.payloads.single['tenantId'], 'tenant-a');
      expect(callable.payloads.single['returnId'], 'ret-1');
      expect(callable.payloads.single['requestId'], 'verify-return-abcdefgh');
      expect(result.returnId, 'ret-1');
      expect(result.verificationId, 'rv_abc');
      expect(result.restoredUnits, 3);
      expect(result.restoredProducts.first.productId, 'product-1');
      expect(result.restoredProducts.first.quantity, 12);
    });

    test('one intent keeps one request ID across a retry', () async {
      final callable = _Callable(_response());
      final gateway = _gateway(callable, requestIds: <String>[
        'verify-return-first111',
        'verify-return-second22',
      ]);

      final intent = gateway.createIntent();
      await gateway.submit(intent);
      await gateway.submit(intent);

      // The server's own idempotency record settles a repeated attempt, so the
      // retry must not present itself as a new operation.
      expect(
        callable.payloads.map((payload) => payload['requestId']),
        <String>['verify-return-first111', 'verify-return-first111'],
      );
    });

    test('a non-management session verifies nothing', () {
      for (final role in <TenantRole>[TenantRole.cashier]) {
        final callable = _Callable(_response());
        expect(
          () => _gateway(callable, role: role).createIntent(),
          _failure(TenantReturnVerificationFailure.forbidden),
        );
        expect(callable.payloads, isEmpty);
      }
      // Management roles are exactly what the callable itself allows.
      for (final role in <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ]) {
        expect(
          () => _gateway(_Callable(_response()), role: role).createIntent(),
          returnsNormally,
        );
      }
    });

    test('a verified return is terminal and never offered again', () async {
      final callable = _Callable(_response());
      final gateway = _gateway(callable, target: _record(verified: true));

      expect(
        TenantReturnVerificationGateway.canVerify(_record(verified: true)),
        isFalse,
      );
      expect(
        gateway.createIntent,
        _failure(TenantReturnVerificationFailure.alreadyVerified),
      );
      expect(callable.payloads, isEmpty);
    });

    test('each server refusal becomes a distinct outcome', () async {
      final cases = <TenantReturnVerificationFailure, List<String>>{
        TenantReturnVerificationFailure.forbidden: <String>[
          'permission-denied',
          'This operation requires an active tenant membership.',
        ],
        TenantReturnVerificationFailure.notFound: <String>[
          'not-found',
          'The return does not exist in this tenant.',
        ],
        TenantReturnVerificationFailure.alreadyVerified: <String>[
          'failed-precondition',
          'This return has already been verified.',
        ],
        TenantReturnVerificationFailure.exceedsSale: <String>[
          'failed-precondition',
          'The return quantity for product product-1 exceeds the immutable '
              'sale.',
        ],
        TenantReturnVerificationFailure.missingProduct: <String>[
          'failed-precondition',
          'Returned product product-1 no longer exists.',
        ],
        TenantReturnVerificationFailure.missingSale: <String>[
          'failed-precondition',
          'The immutable source sale for this return does not exist.',
        ],
        TenantReturnVerificationFailure.tooManyVerifications: <String>[
          'resource-exhausted',
          'This sale has too many prior return verifications for automatic '
              'restoration.',
        ],
        TenantReturnVerificationFailure.ambiguous: <String>[
          'unavailable',
          'The service is unavailable.',
        ],
        TenantReturnVerificationFailure.refused: <String>[
          'data-loss',
          'A prior return verification is malformed.',
        ],
      };

      for (final entry in cases.entries) {
        final gateway = _gateway(
          _Callable.failing(
            FirebaseFunctionsException(
              code: entry.value.first,
              message: entry.value.last,
            ),
          ),
        );
        await expectLater(
          gateway.submit(gateway.createIntent()),
          throwsA(
            isA<TenantReturnVerificationException>().having(
              (error) => error.failure,
              'failure',
              entry.key,
            ),
          ),
          reason: entry.value.first,
        );
      }
    });

    test('only an unknown outcome may have restored stock', () {
      for (final failure in TenantReturnVerificationFailure.values) {
        expect(
          TenantReturnVerificationException(failure).mayHaveCommitted,
          failure == TenantReturnVerificationFailure.ambiguous,
          reason: failure.name,
        );
      }
    });

    test('a timeout is unknown, never a refusal', () async {
      final gateway = _gateway(_Callable.failing(TimeoutException('slow')));

      await expectLater(
        gateway.submit(gateway.createIntent()),
        throwsA(
          isA<TenantReturnVerificationException>().having(
            (error) => error.failure,
            'failure',
            TenantReturnVerificationFailure.ambiguous,
          ),
        ),
      );
    });
  });

  group('verification response', () {
    test('refuses a response that names another return', () async {
      final gateway = _gateway(
        _Callable(_response(overrides: <String, Object?>{'returnId': 'ret-9'})),
      );

      await expectLater(
        gateway.submit(gateway.createIntent()),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuses figures that do not add up or products not returned', () async {
      final refused = <String, Map<String, Object?>>{
        'quantity-does-not-add-up': <String, Object?>{
          'restoredProducts': <Object?>[
            _restored('product-1', restored: 2, previous: 10, after: 13),
            _restored('product-2', restored: 1, previous: 4, after: 5),
          ],
        },
        'quantity-the-return-does-not-record': <String, Object?>{
          'restoredProducts': <Object?>[
            _restored('product-1', restored: 3, previous: 10, after: 13),
            _restored('product-2', restored: 1, previous: 4, after: 5),
          ],
        },
        'product-the-return-does-not-name': <String, Object?>{
          'restoredProducts': <Object?>[
            _restored('product-1', restored: 2, previous: 10, after: 12),
            _restored('product-9', restored: 1, previous: 4, after: 5),
          ],
        },
        'a-returned-product-was-skipped': <String, Object?>{
          'restoredProducts': <Object?>[
            _restored('product-1', restored: 2, previous: 10, after: 12),
          ],
        },
        'duplicate-product': <String, Object?>{
          'restoredProducts': <Object?>[
            _restored('product-1', restored: 2, previous: 10, after: 12),
            _restored('product-1', restored: 2, previous: 12, after: 14),
          ],
        },
        'no-products': <String, Object?>{'restoredProducts': <Object?>[]},
        'not-a-list': <String, Object?>{'restoredProducts': 'product-1'},
        'missing-verification-id': <String, Object?>{'verificationId': null},
      };

      for (final entry in refused.entries) {
        final gateway = _gateway(_Callable(_response(overrides: entry.value)));
        await expectLater(
          gateway.submit(gateway.createIntent()),
          throwsA(isA<FormatException>()),
          reason: entry.key,
        );
      }
    });

    test('stock may legitimately be restored from a negative quantity', () async {
      // Checkout may drive product stock negative, so restoration starts from
      // whatever the product held.
      final gateway = _gateway(
        _Callable(
          _response(
            overrides: <String, Object?>{
              'restoredProducts': <Object?>[
                _restored('product-1', restored: 2, previous: -5, after: -3),
                _restored('product-2', restored: 1, previous: 4, after: 5),
              ],
            },
          ),
        ),
      );

      final result = await gateway.submit(gateway.createIntent());

      expect(result.restoredProducts.first.previousQuantity, -5);
      expect(result.restoredProducts.first.quantity, -3);
    });
  });
}

TenantReturnVerificationGateway _gateway(
  _Callable callable, {
  TenantRole role = TenantRole.manager,
  TenantReturn? target,
  List<String> requestIds = const <String>['verify-return-abcdefgh'],
}) {
  var index = 0;
  return TenantReturnVerificationGateway(
    session: TenantSession.active(
      uid: 'manager-a',
      tenantId: 'tenant-a',
      role: role,
    ),
    target: target ?? _record(),
    callable: callable,
    requestIdFactory: () =>
        requestIds[index++ < requestIds.length ? index - 1 : requestIds.length - 1],
  );
}

Matcher _failure(TenantReturnVerificationFailure failure) => throwsA(
  isA<TenantReturnVerificationException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

Map<String, Object?> _restored(
  String productId, {
  required int restored,
  required int previous,
  required int after,
}) => <String, Object?>{
  'productId': productId,
  'quantityRestored': restored,
  'previousQuantity': previous,
  'quantity': after,
};

Map<String, Object?> _response({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'returnId': 'ret-1',
    'verificationId': 'rv_abc',
    'restoredProducts': <Object?>[
      _restored('product-1', restored: 2, previous: 10, after: 12),
      _restored('product-2', restored: 1, previous: 4, after: 5),
    ],
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

TenantReturn _record({bool verified = false}) => TenantReturn.fromDocument(
  path: 'tenants/tenant-a/returns/ret-1',
  data: <String, Object?>{
    'returnId': 'ret-1',
    'tenantId': 'tenant-a',
    'saleId': 'co-1',
    'createdBy': 'user-a',
    'status': verified ? 'verified' : 'pending',
    'reason': 'Damaged bottle',
    'itemsReturned': <Object?>[
      <String, Object?>{'productId': 'product-1', 'quantity': 2},
      <String, Object?>{'productId': 'product-2', 'quantity': 1},
    ],
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
    if (verified) ...<String, Object?>{
      'verified': true,
      'verifiedBy': 'manager-a',
      'verifiedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 6)),
      'stockRestored': true,
      'stockRestorationId': 'rv_abc',
    },
  },
);

final class _Callable implements VerifyReturnCallable {
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
