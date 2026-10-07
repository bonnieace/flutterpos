import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../tenancy/tenant_paths.dart';
import 'checkout_sale.dart';
import '../observability/app_telemetry.dart';

enum CheckoutSubmissionKind {
  /// The server acknowledged the one atomic batch.
  committed,

  /// The server refused the batch; nothing was written by this attempt.
  rejected,

  /// The outcome is unknown and only a server confirmation check can settle it.
  ambiguous,

  /// No attempt was made because the device was offline.
  unavailable,
}

final class CheckoutSubmissionResult {
  const CheckoutSubmissionResult._(this.kind, [this.reasonCode]);

  const CheckoutSubmissionResult.committed()
    : this._(CheckoutSubmissionKind.committed);

  const CheckoutSubmissionResult.rejected(String reasonCode)
    : this._(CheckoutSubmissionKind.rejected, reasonCode);

  const CheckoutSubmissionResult.ambiguous(String reasonCode)
    : this._(CheckoutSubmissionKind.ambiguous, reasonCode);

  const CheckoutSubmissionResult.unavailable()
    : this._(CheckoutSubmissionKind.unavailable);

  final CheckoutSubmissionKind kind;
  final String? reasonCode;
}

abstract interface class CheckoutSubmissionGateway {
  Future<CheckoutSubmissionResult> submit(CheckoutSaleSubmission submission);
}

typedef CheckoutSubmissionOnlineCheck = Future<bool> Function();
typedef CheckoutBatchCommitter =
    Future<void> Function(CheckoutSaleSubmission submission);

/// Writes one checkout as a single atomic Firestore batch.
///
/// The batch creates only `tenants/{tenantId}/sales/{checkoutId}` and
/// decrements only the exact tenant products named by the immutable payload.
/// No legacy root collection is written.
///
/// A failure classification never proves that the server holds no sale: an
/// offline SDK can still flush a queued batch later. Only the confirmation
/// gateway may decide that a sale is absent.
final class FirebaseCheckoutSubmissionGateway
    implements CheckoutSubmissionGateway {
  FirebaseCheckoutSubmissionGateway({
    FirebaseFirestore? firestore,
    required CheckoutSubmissionOnlineCheck isOnline,
    Duration commitTimeout = const Duration(seconds: 20),
  }) : this._(
         commit: _firestoreCommitter(firestore ?? FirebaseFirestore.instance),
         isOnline: isOnline,
         commitTimeout: commitTimeout,
       );

  FirebaseCheckoutSubmissionGateway.forTesting({
    required CheckoutBatchCommitter commit,
    required CheckoutSubmissionOnlineCheck isOnline,
    Duration commitTimeout = const Duration(seconds: 20),
  }) : this._(commit: commit, isOnline: isOnline, commitTimeout: commitTimeout);

  FirebaseCheckoutSubmissionGateway._({
    required CheckoutBatchCommitter commit,
    required CheckoutSubmissionOnlineCheck isOnline,
    required Duration commitTimeout,
  }) : _commit = commit,
       _isOnline = isOnline,
       _commitTimeout = commitTimeout {
    if (commitTimeout <= Duration.zero) {
      throw ArgumentError.value(commitTimeout, 'commitTimeout');
    }
  }

  static const Set<String> _rejectedCodes = <String>{
    'permission-denied',
    'unauthenticated',
    'invalid-argument',
    'not-found',
    'already-exists',
    'failed-precondition',
    'out-of-range',
  };

  final CheckoutBatchCommitter _commit;
  final CheckoutSubmissionOnlineCheck _isOnline;
  final Duration _commitTimeout;

  @override
  Future<CheckoutSubmissionResult> submit(
    CheckoutSaleSubmission submission,
  ) async {
    _assertTenantScopedWriteSet(submission);
    if (!await _online()) {
      return const CheckoutSubmissionResult.unavailable();
    }
    try {
      await _commit(submission).timeout(_commitTimeout);
      return const CheckoutSubmissionResult.committed();
    } on TimeoutException {
      return const CheckoutSubmissionResult.ambiguous('commit_timeout');
    } on FirebaseException catch (error) {
      return _rejectedCodes.contains(error.code)
          ? CheckoutSubmissionResult.rejected(error.code)
          : CheckoutSubmissionResult.ambiguous(error.code);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'checkout.submission',
      );
      return const CheckoutSubmissionResult.ambiguous('unknown_error');
    }
  }

  Future<bool> _online() async {
    try {
      return await _isOnline();
    } catch (_) {
      return false;
    }
  }

  static CheckoutBatchCommitter _firestoreCommitter(
    FirebaseFirestore firestore,
  ) => (submission) async {
    final batch = firestore.batch();
    batch.set(firestore.doc(submission.salePath), <String, Object?>{
      ...submission.saleFields,
      for (final field in submission.saleServerTimestampFields)
        field: FieldValue.serverTimestamp(),
    });
    for (final decrement in submission.stockDecrements) {
      batch.update(firestore.doc(decrement.productPath), <String, Object?>{
        'quantity': FieldValue.increment(decrement.quantityDelta),
        // The sale this stock left in, being created in this same save. Rules
        // accept the change on the strength of that sale rather than asking
        // again, for every line, whether the cashier is active staff.
        'lastSaleId': submission.checkoutId,
        for (final field in submission.stockServerTimestampFields)
          field: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  };
}

/// Rejects any write set that escaped the exact tenant paths before a commit.
void _assertTenantScopedWriteSet(CheckoutSaleSubmission submission) {
  final paths = TenantPaths(submission.tenantId);
  if (submission.salePath != paths.sale(submission.checkoutId)) {
    throw StateError('A checkout submission escaped its canonical sale path.');
  }
  if (submission.stockDecrements.isEmpty) {
    throw StateError('A checkout submission must decrement at least one item.');
  }
  final seen = <String>{};
  for (final decrement in submission.stockDecrements) {
    if (decrement.quantityDelta >= 0) {
      throw StateError('A checkout submission cannot increase stock.');
    }
    if (decrement.productPath != paths.product(decrement.productId) ||
        !seen.add(decrement.productId)) {
      throw StateError('A checkout submission escaped its tenant products.');
    }
  }
}
