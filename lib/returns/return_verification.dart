import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import 'return_history.dart';

/// Narrow callable boundary for the enabled `verifyReturnAndRestoreStock`
/// mutation. It is the only path that restores stock.
abstract interface class VerifyReturnCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `verifyReturnAndRestoreStock`.
final class FirebaseVerifyReturnCallable implements VerifyReturnCallable {
  FirebaseVerifyReturnCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('verifyReturnAndRestoreStock')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Why a verification did not restore any stock.
///
/// Each case is a distinct, actionable outcome rather than one generic
/// failure. The codes are the ones `functions/src/operations/returns.ts`
/// raises; an unrecognised refusal degrades to [refused], which reports
/// honestly that nothing was restored.
enum TenantReturnVerificationFailure {
  /// The session may not verify, or its membership ended.
  forbidden,

  /// The return no longer exists in this business.
  notFound,

  /// The return had already reached its terminal state.
  alreadyVerified,

  /// The request covers more than the immutable sale still allows.
  exceedsSale,

  /// A returned product no longer exists, so its stock cannot be restored.
  missingProduct,

  /// The immutable source sale is gone, so nothing bounds the restoration.
  missingSale,

  /// The sale carries more prior verifications than automatic restoration
  /// supports.
  tooManyVerifications,

  /// The call was refused for a reason this client does not model.
  refused,

  /// The outcome is unknown; only a canonical re-read may settle it.
  ambiguous,

  /// No attempt reached the server.
  unavailable,
}

/// Raised when a verification did not complete.
final class TenantReturnVerificationException implements Exception {
  const TenantReturnVerificationException(this.failure);

  final TenantReturnVerificationFailure failure;

  /// Whether the attempt may have restored stock despite the failure.
  ///
  /// Only an unknown outcome may have landed. Every other case is proof that
  /// nothing was restored, so only this one requires a canonical re-read
  /// before anything is retried.
  bool get mayHaveCommitted =>
      failure == TenantReturnVerificationFailure.ambiguous;

  @override
  String toString() => 'TenantReturnVerificationException(${failure.name})';
}

/// One product whose stock the verification restored.
final class TenantReturnRestoredProduct {
  const TenantReturnRestoredProduct._({
    required this.productId,
    required this.quantityRestored,
    required this.previousQuantity,
    required this.quantity,
  });

  final String productId;
  final int quantityRestored;
  final int previousQuantity;

  /// The quantity after restoration, as the server recorded it.
  final int quantity;
}

/// One verification intent and its stable idempotency key.
final class TenantReturnVerificationIntent {
  const TenantReturnVerificationIntent._({
    required this.returnId,
    required this.requestId,
  });

  final String returnId;
  final String requestId;
}

/// Strictly decoded result from `verifyReturnAndRestoreStock`.
///
/// The response is reconciled against the return it was requested for: it must
/// name that return, and it must restore exactly the products and units the
/// return itself records. A response describing anything else is refused rather
/// than displayed, because this is the screen that states what stock moved.
final class TenantReturnVerificationResult {
  const TenantReturnVerificationResult._({
    required this.returnId,
    required this.verificationId,
    required this.restoredProducts,
  });

  factory TenantReturnVerificationResult.fromCallable(
    Object? value, {
    required TenantReturn target,
  }) {
    final data = _strictMap(value);
    if (data['returnId'] != target.id) {
      throw const FormatException(
        'verifyReturnAndRestoreStock returned another return.',
      );
    }
    final verificationId = _requiredDocumentId(data, 'verificationId');
    final raw = data['restoredProducts'];
    if (raw is! List || raw.isEmpty || raw.length > maximumReturnLines) {
      throw const FormatException(
        'verifyReturnAndRestoreStock returned invalid restored products.',
      );
    }

    final expected = <String, int>{
      for (final line in target.lines) line.productId: line.quantity,
    };
    final restored = <TenantReturnRestoredProduct>[];
    final seen = <String>{};
    for (final entry in raw) {
      if (entry is! Map) {
        throw const FormatException(
          'verifyReturnAndRestoreStock returned an invalid restored product.',
        );
      }
      final item = <String, Object?>{
        for (final key in entry.keys)
          if (key is String) key: entry[key],
      };
      final productId = _requiredDocumentId(item, 'productId');
      if (!seen.add(productId)) {
        throw const FormatException(
          'verifyReturnAndRestoreStock restored a product twice.',
        );
      }
      final quantityRestored = _requiredInt(item, 'quantityRestored');
      if (quantityRestored < 1 || expected[productId] != quantityRestored) {
        throw const FormatException(
          'verifyReturnAndRestoreStock restored a quantity this return does '
          'not record.',
        );
      }
      final previousQuantity = _requiredInt(item, 'previousQuantity');
      final quantity = _requiredInt(item, 'quantity');
      // The arithmetic is re-derived rather than trusted: a response whose own
      // figures do not add up cannot describe a stock movement that happened.
      if (quantity != previousQuantity + quantityRestored) {
        throw const FormatException(
          'verifyReturnAndRestoreStock returned inconsistent stock figures.',
        );
      }
      restored.add(
        TenantReturnRestoredProduct._(
          productId: productId,
          quantityRestored: quantityRestored,
          previousQuantity: previousQuantity,
          quantity: quantity,
        ),
      );
    }
    if (seen.length != expected.length) {
      throw const FormatException(
        'verifyReturnAndRestoreStock did not restore every returned product.',
      );
    }

    return TenantReturnVerificationResult._(
      returnId: target.id,
      verificationId: verificationId,
      restoredProducts: List<TenantReturnRestoredProduct>.unmodifiable(
        restored,
      ),
    );
  }

  final String returnId;

  /// The immutable `return_verifications` record that restored the stock.
  final String verificationId;
  final List<TenantReturnRestoredProduct> restoredProducts;

  int get restoredUnits => restoredProducts.fold(
    0,
    (total, product) => total + product.quantityRestored,
  );
}

typedef TenantReturnRequestIdFactory = String Function();

/// Session- and target-bound gateway with no tenant or return input surface.
///
/// The tenant comes from one captured live session and the return from one
/// already-decoded canonical record, so no caller can name either.
final class TenantReturnVerificationGateway {
  TenantReturnVerificationGateway({
    required TenantSession session,
    required TenantReturn target,
    required VerifyReturnCallable callable,
    TenantReturnRequestIdFactory? requestIdFactory,
  }) : _session = session,
       _target = target,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? _secureVerificationRequestId;

  /// Restoring stock is management-only, which is exactly what the callable
  /// enforces. Recording a pending return stays open to every active member,
  /// so the two steps remain a deliberate two-person control.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  final TenantSession _session;
  final TenantReturn _target;
  final VerifyReturnCallable _callable;
  final TenantReturnRequestIdFactory _requestIdFactory;

  /// A verified return is terminal, so it is never offered again.
  static bool canVerify(TenantReturn target) => !target.isVerified;

  static bool canVerifyInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  TenantReturnVerificationIntent createIntent() {
    _requireAuthorizedSession();
    if (!canVerify(_target)) {
      throw const TenantReturnVerificationException(
        TenantReturnVerificationFailure.alreadyVerified,
      );
    }
    if (_target.tenantId != _session.tenantId) {
      throw const TenantReturnVerificationException(
        TenantReturnVerificationFailure.forbidden,
      );
    }
    final requestId = _requestIdFactory();
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw StateError('The verification request ID generator is invalid.');
    }
    return TenantReturnVerificationIntent._(
      returnId: _target.id,
      requestId: requestId,
    );
  }

  /// Submits [intent]; one intent keeps one request ID across a retry, so the
  /// server's own idempotency record settles a repeated attempt.
  Future<TenantReturnVerificationResult> submit(
    TenantReturnVerificationIntent intent,
  ) async {
    _requireAuthorizedSession();
    if (intent.returnId != _target.id) {
      throw StateError('The verification intent belongs to another return.');
    }
    if (!canVerify(_target)) {
      throw const TenantReturnVerificationException(
        TenantReturnVerificationFailure.alreadyVerified,
      );
    }
    final Object? response;
    try {
      response = await _callable.call(<String, Object?>{
        'tenantId': _session.tenantId,
        'returnId': _target.id,
        'requestId': intent.requestId,
      });
    } on FirebaseFunctionsException catch (error) {
      throw TenantReturnVerificationException(_classify(error));
    } on TimeoutException {
      throw const TenantReturnVerificationException(
        TenantReturnVerificationFailure.ambiguous,
      );
    } catch (_) {
      throw const TenantReturnVerificationException(
        TenantReturnVerificationFailure.ambiguous,
      );
    }
    return TenantReturnVerificationResult.fromCallable(
      response,
      target: _target,
    );
  }

  void _requireAuthorizedSession() {
    if (!canVerifyInSession(_session)) {
      throw const TenantReturnVerificationException(
        TenantReturnVerificationFailure.forbidden,
      );
    }
  }
}

/// Classifies a refusal from the callable.
///
/// The code decides the outcome. `failed-precondition` covers several distinct
/// server conditions, so those are separated by the exact wording
/// `functions/src/operations/returns.ts` raises. If that wording ever changes,
/// the case degrades to [TenantReturnVerificationFailure.refused], which still
/// reports truthfully that no stock was restored - the classification is only
/// ever used to word a message, never to decide whether to retry.
TenantReturnVerificationFailure _classify(FirebaseFunctionsException error) {
  final message = error.message ?? '';
  return switch (error.code) {
    'permission-denied' ||
    'unauthenticated' => TenantReturnVerificationFailure.forbidden,
    'not-found' => TenantReturnVerificationFailure.notFound,
    'resource-exhausted' =>
      TenantReturnVerificationFailure.tooManyVerifications,
    'unavailable' ||
    'deadline-exceeded' ||
    'internal' ||
    'aborted' ||
    'unknown' => TenantReturnVerificationFailure.ambiguous,
    'failed-precondition'
        when message.contains('already been verified') ||
            message.contains('Only a pending return') =>
      TenantReturnVerificationFailure.alreadyVerified,
    'failed-precondition' when message.contains('exceeds the immutable sale') =>
      TenantReturnVerificationFailure.exceedsSale,
    'failed-precondition' when message.contains('no longer exists') =>
      TenantReturnVerificationFailure.missingProduct,
    'failed-precondition' when message.contains('source sale') =>
      TenantReturnVerificationFailure.missingSale,
    _ => TenantReturnVerificationFailure.refused,
  };
}

Map<String, Object?> _strictMap(Object? value) {
  if (value is! Map) {
    throw const FormatException(
      'verifyReturnAndRestoreStock returned an invalid response.',
    );
  }
  return <String, Object?>{
    for (final key in value.keys)
      if (key is String) key: value[key],
  };
}

String _requiredDocumentId(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String) {
    throw FormatException(
      'verifyReturnAndRestoreStock returned an invalid $field.',
    );
  }
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw FormatException(
      'verifyReturnAndRestoreStock returned an invalid $field.',
    );
  }
}

int _requiredInt(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value.abs() > _maximumQuantity) {
    throw FormatException(
      'verifyReturnAndRestoreStock returned an invalid $field.',
    );
  }
  return value;
}

String _secureVerificationRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'verify-return-${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// Product stock is a signed integer and may legitimately be negative, so only
/// the magnitude is bounded here.
const int _maximumQuantity = 1000000000;

final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
