import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';

/// Narrow callable boundary for the enabled `adjustStock` mutation.
///
/// It is the only path in the app that can set product stock to an arbitrary
/// figure; `verifyReturnAndRestoreStock` only ever adds back what a return
/// records, and checkout only ever decrements.
abstract interface class AdjustStockCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `adjustStock`.
final class FirebaseAdjustStockCallable implements AdjustStockCallable {
  FirebaseAdjustStockCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('adjustStock')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Which way an adjustment type is allowed to move stock.
///
/// `functions/src/operations/domain.ts` binds this with
/// `assertAdjustmentDirection`, so a combination the server refuses must never
/// be offered here: an operator would only learn about it from a rejection.
enum TenantStockAdjustmentDirection { increase, decrease, either }

/// The adjustment types `adjustStock` accepts, with their frozen wire values.
enum TenantStockAdjustmentType {
  restock('restock', TenantStockAdjustmentDirection.increase),
  openingBalance('opening_balance', TenantStockAdjustmentDirection.increase),
  inventoryCount('inventory_count', TenantStockAdjustmentDirection.either),
  correction('correction', TenantStockAdjustmentDirection.either),
  damage('damage', TenantStockAdjustmentDirection.decrease),
  waste('waste', TenantStockAdjustmentDirection.decrease);

  const TenantStockAdjustmentType(this.wireValue, this.direction);

  final String wireValue;
  final TenantStockAdjustmentDirection direction;

  bool get allowsIncrease =>
      direction != TenantStockAdjustmentDirection.decrease;
  bool get allowsDecrease =>
      direction != TenantStockAdjustmentDirection.increase;

  bool allows(int quantityDelta) =>
      quantityDelta > 0 ? allowsIncrease : quantityDelta < 0 && allowsDecrease;

  /// The label shown to an operator. It names the direction, because that is
  /// the part the server enforces.
  String get label => switch (this) {
    restock => 'Restock (adds stock)',
    openingBalance => 'Opening balance (adds stock)',
    inventoryCount => 'Inventory count (either way)',
    correction => 'Correction (either way)',
    damage => 'Damage (removes stock)',
    waste => 'Waste (removes stock)',
  };

  /// The same type inside a sentence, where [label]'s parenthesis does not fit.
  ///
  /// **Added by `design.md` §11 step 11 on 2026-08-15**, because the confirm
  /// dialog was interpolating [wireValue] - so a person about to move stock read
  /// "This records a opening_balance of +5 units", which is §8 rule 1 and a
  /// broken article in one clause. The direction is dropped here rather than
  /// carried: the sentence states the before and after two lines later, which
  /// says it in figures rather than in a parenthesis.
  String get sentenceLabel => switch (this) {
    restock => 'restock',
    openingBalance => 'opening balance',
    inventoryCount => 'inventory count',
    correction => 'correction',
    damage => 'damage',
    waste => 'waste',
  };
}

/// Why an adjustment did not change any stock.
///
/// Each case is a distinct, actionable outcome. The codes are the ones
/// `functions/src/operations/stock.ts`, `domain.ts`, and the shared idempotency
/// helper raise; an unrecognised refusal degrades to [refused], which reports
/// honestly that nothing moved.
enum TenantStockAdjustmentFailure {
  /// The session may not adjust stock, or its membership ended.
  forbidden,

  /// The product no longer exists in this business.
  productMissing,

  /// The type and the direction disagree, which the server refuses outright.
  refusedDirection,

  /// The requested change is not a usable, non-zero, bounded quantity.
  invalidQuantity,

  /// The reason is missing, too short, too long, or unsupported.
  invalidReason,

  /// This request ID already settled a different adjustment.
  duplicateRequest,

  /// The resulting quantity would leave the safe integer range.
  outOfRange,

  /// The product's stored quantity is not an integer, so nothing can be added
  /// to it. Only reconciliation can settle that.
  invalidStoredQuantity,

  /// The call was refused for a reason this client does not model.
  refused,

  /// The adjustment could not be stored on this device, so it was never sent
  /// and nothing anywhere recorded it.
  ///
  /// **Distinct from [ambiguous] in the one way that matters**: an ambiguous
  /// attempt may have moved stock and a re-read is how it settles, while this
  /// one certainly did not and the same figures may simply be entered again.
  /// It is a local storage failure - a full disk, an unreadable box - and the
  /// operator can do nothing about it except try, which is why it says so
  /// rather than reporting a server problem.
  notRecorded,

  /// The outcome is unknown; only a canonical re-read may settle it.
  ambiguous,
}

/// Raised when an adjustment did not complete.
final class TenantStockAdjustmentException implements Exception {
  const TenantStockAdjustmentException(this.failure);

  final TenantStockAdjustmentFailure failure;

  /// Whether the attempt may have moved stock despite the failure.
  ///
  /// Only an unknown outcome may have landed. Every other case is proof that
  /// nothing moved, so only this one requires a canonical re-read before
  /// anything is retried.
  bool get mayHaveCommitted =>
      failure == TenantStockAdjustmentFailure.ambiguous;

  /// Whether an attempt under this same key may already have been recorded, so
  /// the key must be held rather than discarded.
  ///
  /// **Not the same question as [mayHaveCommitted], and conflating them is a
  /// way to move stock twice.** An ambiguous attempt may have reached the
  /// server. A [duplicateRequest] certainly reached *something* - the local
  /// queue or the server already holds a different adjustment under this exact
  /// key - so minting a fresh one would record a second adjustment on top of
  /// the first. Everything else left nothing behind, and holding its key would
  /// make an edited retry fail as a duplicate for no reason.
  bool get retainsRequestId =>
      failure == TenantStockAdjustmentFailure.ambiguous ||
      failure == TenantStockAdjustmentFailure.duplicateRequest;

  @override
  String toString() => 'TenantStockAdjustmentException(${failure.name})';
}

/// One validated adjustment intent and its stable idempotency key.
///
/// The reason is already normalized exactly as the server normalizes it, so
/// what an operator confirmed is what is stored on the immutable record.
final class TenantStockAdjustmentIntent {
  const TenantStockAdjustmentIntent._({
    required this.productId,
    required this.type,
    required this.quantityDelta,
    required this.reason,
    required this.requestId,
  });

  final String productId;
  final TenantStockAdjustmentType type;
  final int quantityDelta;
  final String reason;
  final String requestId;

  bool get increasesStock => quantityDelta > 0;
}

/// Strictly decoded result from `adjustStock`.
///
/// The response is reconciled against the intent it was requested for: it must
/// name that product, apply exactly that change, and its own before/after
/// figures must add up. Anything else is refused rather than displayed, because
/// this is the screen that states what stock a business now holds.
final class TenantStockAdjustmentResult {
  const TenantStockAdjustmentResult._({
    required this.adjustmentId,
    required this.productId,
    required this.previousQuantity,
    required this.quantity,
    required this.quantityDelta,
  });

  /// The adjustment as it will stand, from what the product holds and what this
  /// intent moves.
  ///
  /// **No server has seen it.** [adjustmentId] is null because only the server
  /// writes the `stock_adjustments` record whose ID that is, and the arithmetic
  /// is this device's rather than the server's answer.
  ///
  /// The ledger lags this by design and the caller must say so: a device cannot
  /// write `stock_adjustments` or `stock_movements` - both are server-write-only
  /// - so the *quantity* moves immediately everywhere the product is drawn while
  /// its ledger entry appears only once the queue drains.
  factory TenantStockAdjustmentResult.queued({
    required TenantStockAdjustmentIntent intent,
    required int previousQuantity,
  }) => TenantStockAdjustmentResult._(
    adjustmentId: null,
    productId: intent.productId,
    previousQuantity: previousQuantity,
    quantity: previousQuantity + intent.quantityDelta,
    quantityDelta: intent.quantityDelta,
  );

  factory TenantStockAdjustmentResult.fromCallable(
    Object? value, {
    required TenantStockAdjustmentIntent intent,
  }) {
    final data = _strictMap(value);
    if (data['productId'] != intent.productId) {
      throw const FormatException('adjustStock returned another product.');
    }
    final quantityDelta = _requiredInt(data, 'quantityDelta');
    if (quantityDelta != intent.quantityDelta) {
      throw const FormatException(
        'adjustStock returned a change this intent did not request.',
      );
    }
    final previousQuantity = _requiredInt(data, 'previousQuantity');
    final quantity = _requiredInt(data, 'quantity');
    // The arithmetic is re-derived rather than trusted: a response whose own
    // figures do not add up cannot describe a stock movement that happened.
    if (quantity != previousQuantity + quantityDelta) {
      throw const FormatException(
        'adjustStock returned inconsistent stock figures.',
      );
    }
    return TenantStockAdjustmentResult._(
      adjustmentId: _requiredDocumentId(data, 'adjustmentId'),
      productId: intent.productId,
      previousQuantity: previousQuantity,
      quantity: quantity,
      quantityDelta: quantityDelta,
    );
  }

  /// The immutable `stock_adjustments` record, which is also the ID of the
  /// `stock_movements` entry appended below the product. Null while the
  /// adjustment is still only on this device: the server writes that record,
  /// and a locally invented ID would name nothing.
  final String? adjustmentId;
  final String productId;
  final int previousQuantity;

  /// The quantity after the adjustment, as the server recorded it.
  final int quantity;
  final int quantityDelta;
}

typedef TenantStockAdjustmentRequestIdFactory = String Function();

/// Where an adjustment is parked until this device can send it.
///
/// A function rather than the durable store, so `lib/inventory` keeps depending
/// on `lib/tenancy` and not the other way round. The composition root supplies a
/// closure that enqueues and asks the worker to run.
typedef TenantStockAdjustmentQueue =
    Future<void> Function({
      required String tenantId,
      required String productId,
      required String requestId,
      required Map<String, Object?> payload,
    });

/// Session- and product-bound gateway with no tenant or product input surface.
///
/// The tenant comes from one captured live session and the product from one
/// already-decoded catalog record, so no caller can name either.
final class TenantStockAdjustmentGateway {
  TenantStockAdjustmentGateway({
    required TenantSession session,
    required TenantProduct product,
    required AdjustStockCallable callable,
    TenantStockAdjustmentRequestIdFactory? requestIdFactory,
    TenantStockAdjustmentQueue? queue,
  }) : _session = session,
       _product = product,
       _callable = callable,
       _queue = queue,
       _requestIdFactory = requestIdFactory ?? secureStockAdjustmentRequestId;

  /// Adjusting stock is management-only, which is exactly what the callable
  /// enforces. A cashier may see what a product holds through the catalog but
  /// may never set it.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  final TenantSession _session;
  final TenantProduct _product;
  final AdjustStockCallable _callable;
  final TenantStockAdjustmentQueue? _queue;
  final TenantStockAdjustmentRequestIdFactory _requestIdFactory;

  static bool canAdjustInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// Validates one operator intent locally before anything is sent.
  ///
  /// Every check here mirrors one the server performs, so a refusal an operator
  /// can fix is reported on the form instead of costing a round trip and an
  /// idempotency record.
  TenantStockAdjustmentIntent createIntent({
    required TenantStockAdjustmentType type,
    required int quantityDelta,
    required String reason,
  }) {
    _requireAuthorizedSession();
    if (_product.tenantId != _session.tenantId) {
      throw const TenantStockAdjustmentException(
        TenantStockAdjustmentFailure.forbidden,
      );
    }
    if (quantityDelta == 0 ||
        quantityDelta.abs() > maximumStockAdjustmentQuantityDelta) {
      throw const TenantStockAdjustmentException(
        TenantStockAdjustmentFailure.invalidQuantity,
      );
    }
    if (!type.allows(quantityDelta)) {
      throw const TenantStockAdjustmentException(
        TenantStockAdjustmentFailure.refusedDirection,
      );
    }
    final normalizedReason = normalizeStockAdjustmentReason(reason);
    if (normalizedReason == null) {
      throw const TenantStockAdjustmentException(
        TenantStockAdjustmentFailure.invalidReason,
      );
    }
    final requestId = _requestIdFactory();
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw StateError('The stock adjustment request ID generator is invalid.');
    }
    return TenantStockAdjustmentIntent._(
      productId: _product.id,
      type: type,
      quantityDelta: quantityDelta,
      reason: normalizedReason,
      requestId: requestId,
    );
  }

  /// Submits [intent]; one intent keeps one request ID across a retry, so the
  /// server's own idempotency record settles a repeated attempt rather than
  /// moving the same stock twice.
  Future<TenantStockAdjustmentResult> submit(
    TenantStockAdjustmentIntent intent,
  ) async {
    _requireAuthorizedSession();
    if (intent.productId != _product.id) {
      throw StateError('The adjustment intent belongs to another product.');
    }
    final queue = _queue;
    if (queue != null) {
      // **Guarded, because parking an adjustment can fail too.** This branch ran
      // bare until 2026-09-13: the callable below had a try/catch and the queue
      // had none, so a device that could not write its own outbox threw straight
      // past the panel's handlers and the operator was told nothing at all. The
      // queue is the only path the app actually takes, so the one branch with no
      // failure story was the one every adjustment goes through.
      try {
        await queue(
          tenantId: _session.tenantId,
          productId: intent.productId,
          requestId: intent.requestId,
          payload: <String, Object?>{
            'tenantId': _session.tenantId,
            'productId': intent.productId,
            'quantityDelta': intent.quantityDelta,
            'type': intent.type.wireValue,
            'reason': intent.reason,
            'requestId': intent.requestId,
          },
        );
      } on TenantStockAdjustmentException {
        rethrow;
      } catch (error) {
        // A key that already holds different figures is the same fact the
        // server states as `already-exists`, so it is the same failure and the
        // same sentence - one situation must not acquire a second wording
        // depending on which layer noticed it first.
        throw TenantStockAdjustmentException(
          _queueFailure(error) ?? TenantStockAdjustmentFailure.notRecorded,
        );
      }
      return TenantStockAdjustmentResult.queued(
        intent: intent,
        previousQuantity: _product.quantity,
      );
    }
    final Object? response;
    try {
      response = await _callable.call(<String, Object?>{
        'tenantId': _session.tenantId,
        'productId': intent.productId,
        'quantityDelta': intent.quantityDelta,
        'type': intent.type.wireValue,
        'reason': intent.reason,
        'requestId': intent.requestId,
      });
    } on FirebaseFunctionsException catch (error) {
      throw TenantStockAdjustmentException(_classify(error));
    } on TimeoutException {
      throw const TenantStockAdjustmentException(
        TenantStockAdjustmentFailure.ambiguous,
      );
    } catch (_) {
      throw const TenantStockAdjustmentException(
        TenantStockAdjustmentFailure.ambiguous,
      );
    }
    return TenantStockAdjustmentResult.fromCallable(response, intent: intent);
  }

  /// Reads a queue refusal this gateway can name, or null for anything else.
  ///
  /// Matched on the message rather than the type, because `lib/inventory`
  /// deliberately does not import the durable store - the queue is a function so
  /// the dependency runs one way. Degrading to null is safe: the caller words it
  /// as a storage failure, which is still truthful about the thing that matters,
  /// that nothing was recorded.
  static TenantStockAdjustmentFailure? _queueFailure(Object error) =>
      '$error'.contains('operation_id_conflict')
      ? TenantStockAdjustmentFailure.duplicateRequest
      : null;

  void _requireAuthorizedSession() {
    if (!canAdjustInSession(_session)) {
      throw const TenantStockAdjustmentException(
        TenantStockAdjustmentFailure.forbidden,
      );
    }
  }
}

/// Normalizes a reason exactly as `normalizeReason` does on the server.
///
/// The trimmed length is bounded first and whitespace runs are collapsed
/// afterwards, in that order, so the client and the server can never disagree
/// about whether a reason is acceptable. Returns null when it is not.
String? normalizeStockAdjustmentReason(String value) {
  final trimmed = value.trim();
  if (trimmed.length < minimumStockAdjustmentReasonLength ||
      trimmed.length > maximumStockAdjustmentReasonLength) {
    return null;
  }
  final collapsed = trimmed.replaceAll(_whitespaceRun, ' ');
  for (final codeUnit in collapsed.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) return null;
  }
  return collapsed;
}

/// Classifies a refusal from the callable.
///
/// The code decides the outcome. `invalid-argument` covers several distinct
/// server conditions, so those are separated by the exact wording
/// `functions/src/operations/domain.ts` raises. If that wording ever changes,
/// the case degrades to [TenantStockAdjustmentFailure.refused], which still
/// reports truthfully that no stock moved - the classification is only ever
/// used to word a message, never to decide whether to retry.
TenantStockAdjustmentFailure _classify(FirebaseFunctionsException error) {
  final message = error.message ?? '';
  return switch (error.code) {
    'permission-denied' ||
    'unauthenticated' => TenantStockAdjustmentFailure.forbidden,
    'not-found' => TenantStockAdjustmentFailure.productMissing,
    'already-exists' => TenantStockAdjustmentFailure.duplicateRequest,
    'out-of-range' => TenantStockAdjustmentFailure.outOfRange,
    'failed-precondition' when message.contains('not a valid integer') =>
      TenantStockAdjustmentFailure.invalidStoredQuantity,
    'unavailable' ||
    'deadline-exceeded' ||
    'internal' ||
    'aborted' ||
    'unknown' => TenantStockAdjustmentFailure.ambiguous,
    'invalid-argument'
        when message.contains('requires a positive') ||
            message.contains('requires a negative') =>
      TenantStockAdjustmentFailure.refusedDirection,
    'invalid-argument' when message.contains('quantityDelta') =>
      TenantStockAdjustmentFailure.invalidQuantity,
    'invalid-argument' when message.contains('reason') =>
      TenantStockAdjustmentFailure.invalidReason,
    _ => TenantStockAdjustmentFailure.refused,
  };
}

Map<String, Object?> _strictMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('adjustStock returned an invalid response.');
  }
  return <String, Object?>{
    for (final key in value.keys)
      if (key is String) key: value[key],
  };
}

String _requiredDocumentId(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String) {
    throw FormatException('adjustStock returned an invalid $field.');
  }
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw FormatException('adjustStock returned an invalid $field.');
  }
}

int _requiredInt(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value.abs() > maximumStockQuantityMagnitude) {
    throw FormatException('adjustStock returned an invalid $field.');
  }
  return value;
}

String secureStockAdjustmentRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'adjust-stock-${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// The server's `MAX_QUANTITY_DELTA`.
const int maximumStockAdjustmentQuantityDelta = 1000000;

/// Product stock is a signed integer and may legitimately be negative, so only
/// the magnitude is bounded.
const int maximumStockQuantityMagnitude = 1000000000;

const int minimumStockAdjustmentReasonLength = 3;
const int maximumStockAdjustmentReasonLength = 500;

final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
