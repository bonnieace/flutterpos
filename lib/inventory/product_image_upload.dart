/// Carries staged product photographs to Storage, and files the URL.
///
/// **The one piece of the catalog that cannot go in the mutation queue.** That
/// queue holds JSON, and a photograph is five megabytes of it; hashing and
/// re-hashing that on every read of the outbox would make every other queued
/// change slower for no gain. So the bytes live in their own store
/// ([HiveTenantProductImageDrafts]) and only the URL - a short string - reaches
/// the queue, as an ordinary `productCorrect`.
///
/// **Why the URL is a correction rather than a write.** `allow update` on
/// `products` admits a strictly decreasing `quantity` and nothing else, so no
/// client may set `image` on a product that already exists. `updateProduct`
/// does it through the Admin SDK, which is the same route a shopkeeper's own
/// image change takes.
///
/// **It waits for the product to exist.** A photograph staged against a product
/// whose creation is still queued is left alone: `updateProduct` would answer
/// `not-found`, and that refusal is permanent, so a create that is merely slow
/// would cost the picture. Once the create is confirmed - or was never queued,
/// because the product has been on the server all along - the upload runs.
library;

import 'dart:async';

import '../tenancy/tenant_pending_mutation.dart';
import '../tenancy/tenant_session.dart';
import 'product_image_drafts.dart';
import 'product_image_store.dart';

/// What one pass over the staged photographs did.
enum TenantProductImageUploadRunKind {
  /// Nothing was waiting.
  idle,

  /// At least one photograph reached Storage and its URL was queued.
  uploaded,

  /// Everything waiting is still waiting on a product that is not on the
  /// server yet.
  deferred,

  /// Storage refused or could not be reached.
  unavailable,
}

final class TenantProductImageUploadResult {
  const TenantProductImageUploadResult(this.kind, {this.uploaded = 0});

  final TenantProductImageUploadRunKind kind;
  final int uploaded;
}

/// Queues the URL of an uploaded photograph against its product.
typedef TenantProductImageCorrectionQueue =
    Future<void> Function({
      required String tenantId,
      required String productId,
      required String requestId,
      required Map<String, Object?> payload,
    });

/// One request ID per photograph, so a retry answers off the server's own
/// idempotency record rather than auditing the same correction twice.
typedef TenantProductImageRequestIdFactory = String Function();

final class TenantProductImageUploadWorker {
  TenantProductImageUploadWorker({
    required HiveTenantProductImageDrafts drafts,
    required TenantProductImageStore store,
    required TenantPendingMutationStore mutations,
    required TenantProductImageCorrectionQueue queue,
    required TenantProductImageRequestIdFactory requestId,
  }) : _drafts = drafts,
       _store = store,
       _mutations = mutations,
       _queue = queue,
       _requestId = requestId;

  final HiveTenantProductImageDrafts _drafts;
  final TenantProductImageStore _store;
  final TenantPendingMutationStore _mutations;
  final TenantProductImageCorrectionQueue _queue;
  final TenantProductImageRequestIdFactory _requestId;

  bool _running = false;

  /// Uploads every photograph whose product the server already holds.
  ///
  /// Re-entrancy is refused rather than queued: a second pass over the same
  /// drafts would upload the same bytes twice, and the caller that lost has
  /// nothing to wait for.
  Future<TenantProductImageUploadResult> run(TenantSession session) async {
    if (_running) {
      return const TenantProductImageUploadResult(
        TenantProductImageUploadRunKind.idle,
      );
    }
    _running = true;
    try {
      return await _run(session);
    } finally {
      _running = false;
    }
  }

  Future<TenantProductImageUploadResult> _run(TenantSession session) async {
    final drafts = <TenantProductImageDraft>[
      for (final draft in _drafts.pending())
        if (draft.tenantId == session.tenantId) draft,
    ];
    if (drafts.isEmpty) {
      return const TenantProductImageUploadResult(
        TenantProductImageUploadRunKind.idle,
      );
    }
    final unresolved = await _unresolvedProductPaths(session);

    var uploaded = 0;
    var deferred = 0;
    for (final draft in drafts) {
      final path = 'tenants/${draft.tenantId}/products/${draft.productId}';
      if (unresolved.contains(path)) {
        deferred++;
        continue;
      }
      final TenantProductImageUpload result;
      try {
        result = await _store.upload(
          tenantId: draft.tenantId,
          productId: draft.productId,
          candidate: draft.toCandidate(),
        );
      } on TenantProductImageException catch (error) {
        // **A refusal this device caused is final; a transport one is not.**
        // An unreadable or oversized draft can never succeed, so keeping it
        // would retry it for ever; anything else - permission, a timeout, no
        // network - is worth another pass, so the draft stays exactly as it is.
        if (_permanent(error.code)) {
          await _drafts.discard(
            tenantId: draft.tenantId,
            productId: draft.productId,
          );
          continue;
        }
        return TenantProductImageUploadResult(
          TenantProductImageUploadRunKind.unavailable,
          uploaded: uploaded,
        );
      }
      // One ID, named twice: the queue keys the record on it, and the payload
      // carries it to the server's idempotency record.
      final requestId = _requestId();
      await _queue(
        tenantId: draft.tenantId,
        productId: draft.productId,
        requestId: requestId,
        payload: <String, Object?>{
          'tenantId': draft.tenantId,
          'productId': draft.productId,
          'requestId': requestId,
          'image': result.url.toString(),
        },
      );
      // The bytes have a second copy now. Dropping the draft here is what
      // returns the surfaces to the stored URL - the same picture, from the
      // place every other device reads it.
      await _drafts.discard(
        tenantId: draft.tenantId,
        productId: draft.productId,
      );
      uploaded++;
    }

    if (uploaded > 0) {
      return TenantProductImageUploadResult(
        TenantProductImageUploadRunKind.uploaded,
        uploaded: uploaded,
      );
    }
    return TenantProductImageUploadResult(
      deferred > 0
          ? TenantProductImageUploadRunKind.deferred
          : TenantProductImageUploadRunKind.idle,
      uploaded: uploaded,
    );
  }

  /// The product paths this device has queued work against that has not
  /// settled. A photograph for one of them waits.
  Future<Set<String>> _unresolvedProductPaths(TenantSession session) async {
    final records = await _mutations.recordsForSession(
      uid: session.uid,
      tenantId: session.tenantId,
    );
    return <String>{
      for (final record in records)
        if (record.kind == TenantPendingMutationKind.productCreate &&
            record.isUnresolved)
          record.targetPath,
    };
  }

  static bool _permanent(String code) =>
      code == 'invalid_image_size' || code == 'unsupported_image_type';
}
