/// *Remove background*: the one catalog action the old app had that this one
/// did not.
///
/// **Restored on 2026-08-25 at the product owner's direction**, along with the
/// image presentation the old correction dialog drew around it. The old app put
/// the vendor's key in the APK (`lib/pos/goods.dart:1927`) and posted to
/// `api.remove.bg` from the phone; `CLIENT_CONFIGURATION_AUDIT.md` §10 records
/// that key as compromised and requires the call to go through a backend
/// holding a secret instead. So the shape here is the old button and a
/// completely different path underneath it: the callable
/// `removeProductBackground` does the talking, and no key exists on this side
/// to leak.
///
/// **Optional throughout.** The remover is nullable at every seam and a null
/// one simply does not offer the action, which is what a deployment that never
/// bought the service should see. It is not an error state and is never drawn
/// as one.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

import '../tenancy/tenant_session.dart';
import 'catalog_management.dart';
import 'product_image_store.dart';
import '../observability/app_telemetry.dart';

/// Why a background was not removed. The image the operator chose is untouched
/// in every one of these cases.
enum TenantBackgroundRemovalFailure {
  /// No background-removal service is set up for this deployment. Offered as a
  /// failure rather than hidden because the button can be configured away
  /// between the form opening and the press.
  unconfigured,

  /// This session may not correct products, or its membership ended.
  forbidden,

  /// The service could not read the photo. A different photo may work.
  unusableImage,

  /// The processed image came back larger than a product image may be.
  tooLarge,

  /// The allowance the business bought is spent.
  allowanceSpent,

  /// The service could not be reached, or answered in a way this cannot use.
  /// The only honest advice is to try again.
  unavailable,
}

final class TenantBackgroundRemovalException implements Exception {
  const TenantBackgroundRemovalException(this.failure);

  final TenantBackgroundRemovalFailure failure;

  @override
  String toString() => 'TenantBackgroundRemovalException($failure)';
}

/// The seam the form presses.
abstract interface class TenantProductBackgroundRemover {
  /// Returns [candidate] with its background removed, as a fresh candidate.
  ///
  /// Never mutates [candidate]: the operator can still undo back to the photo
  /// they chose, which the old dialog could not do.
  Future<TenantProductImageCandidate> remove({
    required TenantSession session,
    required TenantProductImageCandidate candidate,
  });

  /// Whether [session] holds a role that may change a product's image.
  ///
  /// Asked before the button is drawn, so a cashier is not offered an action
  /// whose only possible answer is a refusal.
  bool canRemoveInSession(TenantSession session);
}

/// Narrow callable boundary for `removeProductBackground`.
abstract interface class RemoveProductBackgroundCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `removeProductBackground`.
final class FirebaseRemoveProductBackgroundCallable
    implements RemoveProductBackgroundCallable {
  FirebaseRemoveProductBackgroundCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await traceServerCall(
      'removeProductBackground',
      () => _functions
          .httpsCallable('removeProductBackground')
          .call<Object?>(payload),
    );
    return result.data;
  }
}

/// Removes a background by asking the callable to.
final class CallableTenantProductBackgroundRemover
    implements TenantProductBackgroundRemover {
  const CallableTenantProductBackgroundRemover({required this.callable});

  final RemoveProductBackgroundCallable callable;

  /// The same question `TenantProductUpdateGateway` asks before it will send a
  /// correction, because changing a product's picture *is* correcting the
  /// product - and the callable enforces the same list server-side
  /// (`PRODUCT_UPDATE_ROLES`). A second role list here would be a second
  /// opinion about one question.
  @override
  bool canRemoveInSession(TenantSession session) =>
      TenantProductUpdateGateway.canUpdateInSession(session);

  @override
  Future<TenantProductImageCandidate> remove({
    required TenantSession session,
    required TenantProductImageCandidate candidate,
  }) async {
    if (!canRemoveInSession(session)) {
      throw const TenantBackgroundRemovalException(
        TenantBackgroundRemovalFailure.forbidden,
      );
    }
    final Object? response;
    try {
      response = await callable.call(<String, Object?>{
        'tenantId': session.tenantId,
        'imageBase64': base64Encode(candidate.bytes),
      });
    } on FirebaseFunctionsException catch (error) {
      throw TenantBackgroundRemovalException(_classify(error));
    } on TimeoutException {
      throw const TenantBackgroundRemovalException(
        TenantBackgroundRemovalFailure.unavailable,
      );
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'inventory.background_removal_request',
      );
      throw const TenantBackgroundRemovalException(
        TenantBackgroundRemovalFailure.unavailable,
      );
    }
    return _readCandidate(response, source: candidate);
  }
}

/// Reads the callable's answer, refusing anything it cannot prove is an image.
///
/// The bytes are handed straight to `Image.memory` and then to Storage, so a
/// malformed answer that got this far would surface as a broken picture in the
/// catalog rather than as a failure here.
TenantProductImageCandidate _readCandidate(
  Object? response, {
  required TenantProductImageCandidate source,
}) {
  if (response is! Map) {
    throw const TenantBackgroundRemovalException(
      TenantBackgroundRemovalFailure.unavailable,
    );
  }
  final encoded = response['imageBase64'];
  if (encoded is! String || encoded.isEmpty) {
    throw const TenantBackgroundRemovalException(
      TenantBackgroundRemovalFailure.unavailable,
    );
  }
  final Uint8List bytes;
  try {
    bytes = base64Decode(encoded);
  } on FormatException {
    throw const TenantBackgroundRemovalException(
      TenantBackgroundRemovalFailure.unavailable,
    );
  }
  try {
    return TenantProductImageCandidate(
      bytes: bytes,
      fileName: cutOutFileName(source.fileName),
    );
  } on TenantProductImageException catch (error) {
    // `_validatedType` sniffs the magic number and bounds the size, so this is
    // where "the service returned something that is not an image" lands.
    throw TenantBackgroundRemovalException(
      error.code == 'invalid_image_size'
          ? TenantBackgroundRemovalFailure.tooLarge
          : TenantBackgroundRemovalFailure.unavailable,
    );
  }
}

/// Renames a chosen file to the cut-out that replaced it.
///
/// The extension becomes `.png` because that is what the service returns, and
/// a name saying `.jpg` over PNG bytes is the kind of small lie that is only
/// ever discovered by somebody debugging something else.
String cutOutFileName(String original) {
  final trimmed = original.trim();
  if (trimmed.isEmpty) return 'cutout.png';
  final dot = trimmed.lastIndexOf('.');
  final stem = dot <= 0 ? trimmed : trimmed.substring(0, dot);
  return '$stem-cutout.png';
}

/// Classifies a refusal from the callable.
///
/// The code decides the outcome; where one code covers two conditions the
/// server's own wording separates them. An unrecognised refusal degrades to
/// [TenantBackgroundRemovalFailure.unavailable], which is truthful in every
/// case - nothing was changed and trying again is the only advice left.
TenantBackgroundRemovalFailure _classify(FirebaseFunctionsException error) {
  final message = error.message ?? '';
  return switch (error.code) {
    'permission-denied' ||
    'unauthenticated' => TenantBackgroundRemovalFailure.forbidden,
    'failed-precondition' => TenantBackgroundRemovalFailure.unconfigured,
    'resource-exhausted' => TenantBackgroundRemovalFailure.allowanceSpent,
    'out-of-range' => TenantBackgroundRemovalFailure.tooLarge,
    'invalid-argument' when message.contains('maximum product image size') =>
      TenantBackgroundRemovalFailure.tooLarge,
    'invalid-argument' => TenantBackgroundRemovalFailure.unusableImage,
    _ => TenantBackgroundRemovalFailure.unavailable,
  };
}

/// What each failure says to the person who pressed the button.
///
/// Every sentence states that the chosen image is unchanged, because the one
/// thing an operator needs to know after a failed cut-out is whether they still
/// have the photo they picked.
String backgroundRemovalMessage(TenantBackgroundRemovalFailure failure) =>
    switch (failure) {
      TenantBackgroundRemovalFailure.unconfigured =>
        'Background removal is not set up for this business. The image you '
            'chose is unchanged.',
      TenantBackgroundRemovalFailure.forbidden =>
        'Only an owner, administrator, or manager may change a product image. '
            'The image you chose is unchanged.',
      TenantBackgroundRemovalFailure.unusableImage =>
        'That photo could not be processed. Try a different one - the image '
            'you chose is unchanged.',
      TenantBackgroundRemovalFailure.tooLarge =>
        'The cut-out came back larger than a product image may be. Try a '
            'smaller photo - the image you chose is unchanged.',
      TenantBackgroundRemovalFailure.allowanceSpent =>
        'This business has used up its background removals. The image you '
            'chose is unchanged.',
      TenantBackgroundRemovalFailure.unavailable =>
        'Background removal could not be reached. Try again - the image you '
            'chose is unchanged.',
    };
