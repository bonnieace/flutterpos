import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('adjustment gateway', () {
    test('sends the session tenant and the decoded product only', () async {
      final callable = _Callable(_response());

      final gateway = _gateway(callable);
      final result = await gateway.submit(
        gateway.createIntent(
          type: TenantStockAdjustmentType.restock,
          quantityDelta: 6,
          reason: '  Delivery   from   supplier ',
        ),
      );

      final sent = Map<String, Object?>.of(callable.payloads.single);
      // Sent straight away, so it happened now; the server dates the ledger by
      // it and never takes one later than the moment it arrived.
      final occurredAtMs = sent.remove('occurredAtMs');
      expect(occurredAtMs, isA<int>());
      expect(
        DateTime.now().millisecondsSinceEpoch - (occurredAtMs! as int),
        inInclusiveRange(0, 60000),
      );
      expect(sent, <String, Object?>{
        'tenantId': 'tenant-a',
        'productId': 'product-1',
        'quantityDelta': 6,
        'type': 'restock',
        // Normalized exactly as the server normalizes it, so what was
        // confirmed is what the immutable record stores.
        'reason': 'Delivery from supplier',
        'requestId': 'adjust-stock-abcdefgh',
      });
      expect(result.adjustmentId, 'sa_abc');
      expect(result.previousQuantity, 4);
      expect(result.quantity, 10);
      expect(result.quantityDelta, 6);
    });

    test('one intent keeps one request ID across a retry', () async {
      final callable = _Callable(_response());
      final gateway = _gateway(
        callable,
        requestIds: <String>['adjust-stock-first11', 'adjust-stock-second2'],
      );

      final intent = gateway.createIntent(
        type: TenantStockAdjustmentType.restock,
        quantityDelta: 6,
        reason: 'Delivery from supplier',
      );
      await gateway.submit(intent);
      await gateway.submit(intent);

      // The server's own idempotency record settles a repeated attempt, so the
      // retry must not present itself as a new operation.
      expect(callable.payloads.map((payload) => payload['requestId']), <String>[
        'adjust-stock-first11',
        'adjust-stock-first11',
      ]);
    });

    test('a non-management session adjusts nothing', () {
      final callable = _Callable(_response());
      expect(
        () => _gateway(callable, role: TenantRole.cashier).createIntent(
          type: TenantStockAdjustmentType.restock,
          quantityDelta: 1,
          reason: 'Delivery',
        ),
        _failure(TenantStockAdjustmentFailure.forbidden),
      );
      expect(callable.payloads, isEmpty);

      // Management roles are exactly what the callable itself allows.
      for (final role in <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ]) {
        expect(
          () => _gateway(_Callable(_response()), role: role).createIntent(
            type: TenantStockAdjustmentType.restock,
            quantityDelta: 1,
            reason: 'Delivery',
          ),
          returnsNormally,
          reason: role.name,
        );
      }
    });

    test('a product from another business is refused before any call', () {
      final callable = _Callable(_response());

      expect(
        () => _gateway(callable, product: _product(tenantId: 'tenant-b'))
            .createIntent(
              type: TenantStockAdjustmentType.restock,
              quantityDelta: 1,
              reason: 'Delivery',
            ),
        _failure(TenantStockAdjustmentFailure.forbidden),
      );
      expect(callable.payloads, isEmpty);
    });

    test('a direction the server binds is refused locally', () {
      final refused = <TenantStockAdjustmentType, int>{
        TenantStockAdjustmentType.restock: -1,
        TenantStockAdjustmentType.openingBalance: -1,
        TenantStockAdjustmentType.damage: 1,
        TenantStockAdjustmentType.waste: 1,
      };
      for (final entry in refused.entries) {
        final callable = _Callable(_response());
        expect(
          () => _gateway(callable).createIntent(
            type: entry.key,
            quantityDelta: entry.value,
            reason: 'Reason enough',
          ),
          _failure(TenantStockAdjustmentFailure.refusedDirection),
          reason: entry.key.wireValue,
        );
        expect(callable.payloads, isEmpty);
      }

      // The two either-direction types accept both, which is exactly what
      // `assertAdjustmentDirection` leaves unconstrained.
      for (final type in <TenantStockAdjustmentType>[
        TenantStockAdjustmentType.inventoryCount,
        TenantStockAdjustmentType.correction,
      ]) {
        for (final delta in <int>[3, -3]) {
          expect(
            () => _gateway(_Callable(_response())).createIntent(
              type: type,
              quantityDelta: delta,
              reason: 'Reason enough',
            ),
            returnsNormally,
            reason: '${type.wireValue}:$delta',
          );
        }
      }
    });

    test('a zero or unbounded change is refused', () {
      for (final delta in <int>[
        0,
        maximumStockAdjustmentQuantityDelta + 1,
        -maximumStockAdjustmentQuantityDelta - 1,
      ]) {
        expect(
          () => _gateway(_Callable(_response())).createIntent(
            type: TenantStockAdjustmentType.correction,
            quantityDelta: delta,
            reason: 'Reason enough',
          ),
          _failure(TenantStockAdjustmentFailure.invalidQuantity),
          reason: '$delta',
        );
      }
    });

    test('a reason the server would refuse is refused locally', () {
      for (final reason in <String>[
        '',
        '  ',
        'ab',
        ' a ',
        'a' * 501,
        'bad\u0000reason',
      ]) {
        expect(
          () => _gateway(_Callable(_response())).createIntent(
            type: TenantStockAdjustmentType.correction,
            quantityDelta: 1,
            reason: reason,
          ),
          _failure(TenantStockAdjustmentFailure.invalidReason),
          reason: reason,
        );
      }
      expect(normalizeStockAdjustmentReason(' a\t\n b '), 'a b');
      expect(normalizeStockAdjustmentReason('a' * 500), 'a' * 500);
    });

    test('each server refusal becomes a distinct outcome', () async {
      final cases = <TenantStockAdjustmentFailure, List<String>>{
        TenantStockAdjustmentFailure.forbidden: <String>[
          'permission-denied',
          'This operation requires an active tenant membership.',
        ],
        TenantStockAdjustmentFailure.productMissing: <String>[
          'not-found',
          'The product does not exist in this tenant.',
        ],
        TenantStockAdjustmentFailure.duplicateRequest: <String>[
          'already-exists',
          'requestId was already used with different input.',
        ],
        TenantStockAdjustmentFailure.outOfRange: <String>[
          'out-of-range',
          'The resulting product quantity is outside the safe range.',
        ],
        TenantStockAdjustmentFailure.invalidStoredQuantity: <String>[
          'failed-precondition',
          'product quantity is not a valid integer.',
        ],
        TenantStockAdjustmentFailure.refusedDirection: <String>[
          'invalid-argument',
          'restock requires a positive quantityDelta.',
        ],
        TenantStockAdjustmentFailure.invalidQuantity: <String>[
          'invalid-argument',
          'quantityDelta must be a non-zero integer between -1000000 and '
              '1000000.',
        ],
        TenantStockAdjustmentFailure.invalidReason: <String>[
          'invalid-argument',
          'reason must be between 3 and 500 characters.',
        ],
        TenantStockAdjustmentFailure.ambiguous: <String>[
          'aborted',
          'The operation is already in progress.',
        ],
        TenantStockAdjustmentFailure.refused: <String>[
          'invalid-argument',
          'type is not a supported stock adjustment type.',
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
          gateway.submit(
            gateway.createIntent(
              type: TenantStockAdjustmentType.correction,
              quantityDelta: 1,
              reason: 'Reason enough',
            ),
          ),
          throwsA(
            isA<TenantStockAdjustmentException>().having(
              (error) => error.failure,
              'failure',
              entry.key,
            ),
          ),
          reason: '${entry.value.first}: ${entry.value.last}',
        );
      }
    });

    test('only an unknown outcome may have moved stock', () {
      for (final failure in TenantStockAdjustmentFailure.values) {
        expect(
          TenantStockAdjustmentException(failure).mayHaveCommitted,
          failure == TenantStockAdjustmentFailure.ambiguous,
          reason: failure.name,
        );
      }
    });

    test('a key is held whenever an attempt under it may be recorded', () {
      // Deliberately a different question from `mayHaveCommitted`, and
      // answering one with the other is how the same stock moves twice: a
      // duplicate means something already holds this key, so minting a fresh
      // one would record a second adjustment on top of the first.
      for (final failure in TenantStockAdjustmentFailure.values) {
        expect(
          TenantStockAdjustmentException(failure).retainsRequestId,
          failure == TenantStockAdjustmentFailure.ambiguous ||
              failure == TenantStockAdjustmentFailure.duplicateRequest,
          reason: failure.name,
        );
      }
    });
  });

  group('the queue the app actually uses', () {
    // **Every test above this drives the callable, and the app never does.**
    // `main.dart` supplies both a callable and a queue, and `submit` takes the
    // queue branch whenever one is present - so until 2026-09-13 the suite
    // exercised a branch production never runs and never exercised the one it
    // does. That is why an unguarded throw here went unnoticed.

    TenantStockAdjustmentQueue recording(List<Map<String, Object?>> sent) =>
        ({
          required tenantId,
          required productId,
          required requestId,
          required payload,
        }) async => sent.add(payload);

    TenantStockAdjustmentQueue failing(Object error) =>
        ({
          required tenantId,
          required productId,
          required requestId,
          required payload,
        }) async => throw error;

    test('a queued adjustment answers from arithmetic, not a round trip', () async {
      final sent = <Map<String, Object?>>[];
      final callable = _Callable(const <String, Object?>{});
      final gateway = _gateway(callable, queue: recording(sent));

      final result = await gateway.submit(
        gateway.createIntent(
          type: TenantStockAdjustmentType.damage,
          quantityDelta: -2,
          reason: 'Two broken in transit',
        ),
      );

      expect(sent, hasLength(1));
      expect(sent.single['quantityDelta'], -2);
      expect(sent.single['requestId'], 'adjust-stock-abcdefgh');
      // The product held 4, so the answer is arithmetic on this device.
      expect(result.previousQuantity, 4);
      expect(result.quantity, 2);
      // Null because only the server writes the record that ID names.
      expect(result.adjustmentId, isNull);
    });

    test('a queue that cannot store it says so, and says nothing moved', () async {
      // The defect this group exists for. This threw straight past the panel's
      // handlers and the operator was told nothing at all.
      final gateway = _gateway(
        _Callable(const <String, Object?>{}),
        queue: failing(StateError('the box is unwritable')),
      );

      await expectLater(
        gateway.submit(
          gateway.createIntent(
            type: TenantStockAdjustmentType.damage,
            quantityDelta: -2,
            reason: 'Two broken in transit',
          ),
        ),
        throwsA(
          isA<TenantStockAdjustmentException>()
              .having(
                (error) => error.failure,
                'failure',
                TenantStockAdjustmentFailure.notRecorded,
              )
              // Nothing was written, so nothing is awaiting settlement and the
              // key may be discarded.
              .having(
                (error) => error.mayHaveCommitted,
                'mayHaveCommitted',
                isFalse,
              )
              .having(
                (error) => error.retainsRequestId,
                'retainsRequestId',
                isFalse,
              ),
        ),
      );
    });

    test('a key already holding other figures is the duplicate it is', () async {
      // The local queue and the server state one fact - this key already
      // settled something else - so they must reach one failure and one
      // sentence. And the key is held: an earlier adjustment is out there.
      final gateway = _gateway(
        _Callable(const <String, Object?>{}),
        queue: failing(StateError('operation_id_conflict')),
      );

      await expectLater(
        gateway.submit(
          gateway.createIntent(
            type: TenantStockAdjustmentType.damage,
            quantityDelta: -3,
            reason: 'Three broken in transit',
          ),
        ),
        throwsA(
          isA<TenantStockAdjustmentException>()
              .having(
                (error) => error.failure,
                'failure',
                TenantStockAdjustmentFailure.duplicateRequest,
              )
              .having(
                (error) => error.retainsRequestId,
                'retainsRequestId',
                isTrue,
              ),
        ),
      );
    });

    test('a refusal this gateway makes itself never reaches the queue', () async {
      // The authorization guard runs before the queue, so a cashier's
      // adjustment is refused here rather than parked and refused by a server a
      // week later.
      final sent = <Map<String, Object?>>[];
      final gateway = _gateway(
        _Callable(const <String, Object?>{}),
        role: TenantRole.cashier,
        queue: recording(sent),
      );

      expect(
        () => gateway.createIntent(
          type: TenantStockAdjustmentType.damage,
          quantityDelta: -2,
          reason: 'Two broken in transit',
        ),
        throwsA(isA<TenantStockAdjustmentException>()),
      );
      expect(sent, isEmpty);
    });

    test('a timeout is unknown, never a refusal', () async {
      final gateway = _gateway(_Callable.failing(TimeoutException('slow')));

      await expectLater(
        gateway.submit(
          gateway.createIntent(
            type: TenantStockAdjustmentType.correction,
            quantityDelta: 1,
            reason: 'Reason enough',
          ),
        ),
        _failure(TenantStockAdjustmentFailure.ambiguous),
      );
    });
  });

  group('adjustment response', () {
    test('refuses a response that describes anything else', () async {
      final refused = <String, Map<String, Object?>>{
        'another-product': <String, Object?>{'productId': 'product-9'},
        'another-change': <String, Object?>{'quantityDelta': 5},
        'figures-that-do-not-add-up': <String, Object?>{'quantity': 11},
        'missing-adjustment-id': <String, Object?>{'adjustmentId': null},
        'adjustment-id-with-a-separator': <String, Object?>{
          'adjustmentId': 'sa/abc',
        },
        'non-integer-quantity': <String, Object?>{'quantity': 10.0},
      };

      for (final entry in refused.entries) {
        final gateway = _gateway(_Callable(_response(overrides: entry.value)));
        await expectLater(
          gateway.submit(
            gateway.createIntent(
              type: TenantStockAdjustmentType.restock,
              quantityDelta: 6,
              reason: 'Delivery from supplier',
            ),
          ),
          throwsA(isA<FormatException>()),
          reason: entry.key,
        );
      }
    });

    test('refuses a response that is not a map at all', () async {
      final gateway = _gateway(_Callable('sa_abc'));

      await expectLater(
        gateway.submit(
          gateway.createIntent(
            type: TenantStockAdjustmentType.restock,
            quantityDelta: 6,
            reason: 'Delivery from supplier',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'stock may legitimately be corrected from a negative figure',
      () async {
        // Checkout never blocks a sale on a stock count, so a product can be
        // sold past zero and corrected afterwards.
        final gateway = _gateway(
          _Callable(
            _response(
              overrides: <String, Object?>{
                'previousQuantity': -8,
                'quantity': -2,
              },
            ),
          ),
        );

        final result = await gateway.submit(
          gateway.createIntent(
            type: TenantStockAdjustmentType.restock,
            quantityDelta: 6,
            reason: 'Delivery from supplier',
          ),
        );

        expect(result.previousQuantity, -8);
        expect(result.quantity, -2);
      },
    );
  });
}

TenantStockAdjustmentGateway _gateway(
  _Callable callable, {
  TenantRole role = TenantRole.manager,
  TenantProduct? product,
  TenantStockAdjustmentQueue? queue,
  List<String> requestIds = const <String>['adjust-stock-abcdefgh'],
}) {
  var index = 0;
  return TenantStockAdjustmentGateway(
    queue: queue,
    session: TenantSession.active(
      uid: 'manager-a',
      tenantId: 'tenant-a',
      role: role,
    ),
    product: product ?? _product(),
    callable: callable,
    requestIdFactory: () =>
        requestIds[index++ < requestIds.length
            ? index - 1
            : requestIds.length - 1],
  );
}

TenantProduct _product({String tenantId = 'tenant-a'}) =>
    TenantProduct.fromDocument(
      path: 'tenants/$tenantId/products/product-1',
      data: const <String, Object?>{
        'name': 'Cold lager',
        'SKU': 'LAGER-001',
        'price': 120.5,
        'quantity': 4,
        'categoryId': 'drinks',
      },
    );

Matcher _failure(TenantStockAdjustmentFailure failure) => throwsA(
  isA<TenantStockAdjustmentException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

Map<String, Object?> _response({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'adjustmentId': 'sa_abc',
    'productId': 'product-1',
    'previousQuantity': 4,
    'quantity': 10,
    'quantityDelta': 6,
  };
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

final class _Callable implements AdjustStockCallable {
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
