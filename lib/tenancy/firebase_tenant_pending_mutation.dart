import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'tenant_pending_mutation.dart';

/// The `createProduct` request one queued create describes.
///
/// **Derived from the record rather than stored in it**, which is what let the
/// create rule close in the same release the callable shipped. The payload is
/// the document a device composed - unchanged from when this kind was a
/// Firestore `set` - and the business and the product come from the path the
/// record already targets. So a create queued by a build that wrote the document
/// directly, one carrying no `quantity` at all, drains through the callable
/// untouched and is read as opening nothing. Nothing durable on anybody's phone
/// had to be migrated.
///
/// The product ID is also the idempotency key. It is already a digest of the
/// request ID that minted it, so a replay answers off the server's own record
/// instead of stocking the shelf twice.
Map<String, Object?> tenantProductCreateCallablePayload(
  TenantPendingMutationRecord record,
) => <String, Object?>{
  'tenantId': record.tenantId,
  'productId': record.targetPath.split('/').last,
  'document': record.payload,
};

/// Carries one queued mutation to the server, by whichever route its kind uses.
///
/// **Two transports, one queue.** Most kinds are document writes the rules
/// already admit, and replaying one is replaying the same `set` or `delete`.
/// Three are callables, and each for the same underlying reason: the write
/// cannot be split from the ledger entry that accounts for it. `allow update` on
/// `products` cannot be widened without giving up the guarantee that no client
/// inflates stock, so a correction and an adjustment go through the Admin SDK -
/// and since 2026-09-13 a create does too, because a created product may carry
/// an opening quantity whose `stock_movements` entry is server-written.
///
/// **Replaying a callable is safe, and that is a server property rather than a
/// hope.** `runIdempotentFirestoreTransaction` in `functions/src/core/`
/// stores each result against `actorUid + operation + scope + requestId`; a
/// repeat with the same input returns the stored result rather than acting
/// twice, and only a repeat with *different* input under the same request ID is
/// refused as `already-exists`. The queue keeps one request ID per operation
/// for its whole life, so a retry always takes the first branch.
final class FirebaseTenantMutationGateway
    implements
        TenantMutationSubmissionGateway,
        TenantMutationConfirmationGateway {
  FirebaseTenantMutationGateway({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    this.deadline = const Duration(seconds: 8),
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final Duration deadline;

  static const Set<String> _rejectedCodes = <String>{
    'permission-denied',
    'unauthenticated',
    'invalid-argument',
    'not-found',
    'already-exists',
    'failed-precondition',
    'out-of-range',
  };

  @override
  Future<Map<String, Object?>?> read(String targetPath) async {
    final snapshot = await _firestore
        .doc(targetPath)
        .get(const GetOptions(source: Source.server))
        .timeout(deadline);
    return snapshot.data();
  }

  @override
  Future<TenantMutationSubmissionResult> submit(
    TenantPendingMutationRecord record,
  ) async {
    try {
      final document = _firestore.doc(record.targetPath);
      switch (record.kind) {
        case TenantPendingMutationKind.expenseCreate:
        case TenantPendingMutationKind.pendingReturnCreate:
          await document
              .set(<String, Object?>{
                ...record.payload,
                'createdAt': FieldValue.serverTimestamp(),
              })
              .timeout(deadline);
        case TenantPendingMutationKind.expenseVoid:
          await document
              .update(<String, Object?>{
                ...record.payload,
                'voidedAt': FieldValue.serverTimestamp(),
              })
              .timeout(deadline);
        case TenantPendingMutationKind.brandingMerge:
        case TenantPendingMutationKind.printerConfigurationMerge:
          await document
              .set(<String, Object?>{
                ...record.payload,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true))
              .timeout(deadline);
        // **A callable, because a created product may hold stock.** The
        // `stock_adjustments` record and `stock_movements` entry that account for
        // an opening balance are server-write-only, so the product and its ledger
        // entry must be written by one principal inside one transaction. That is
        // the whole reason this stopped being a `set`.
        //
        // **The envelope is rebuilt from the record, not stored in it.** The
        // payload is the document a device composed, exactly as it always was,
        // and the tenant and product come from `targetPath`. So a record queued
        // by a build that wrote this document directly - one carrying no
        // `quantity` at all, which the callable reads as zero - drains through
        // here unchanged. That is what let `allow create` close in the same
        // release without stranding work already durable on somebody's phone.
        //
        // The product ID is the idempotency key. It is already a digest of the
        // request ID that minted it, so a replay answers off the server's record
        // rather than stocking the shelf twice.
        case TenantPendingMutationKind.productCreate:
          await _call(
            'createProduct',
            tenantProductCreateCallablePayload(record),
          );
        // A whole-document `set` rather than a merge: the document is being
        // brought into existence, the strict read model needs every field it
        // names, and merging onto a deterministic ID that already exists would
        // patch a category instead of refusing a replay. A category carries no
        // quantity and has no ledger, so it stays the document write `allow
        // create` on `categories` still admits.
        case TenantPendingMutationKind.categoryCreate:
          await document
              .set(<String, Object?>{
                ...record.payload,
                'createdAt': FieldValue.serverTimestamp(),
              })
              .timeout(deadline);
        case TenantPendingMutationKind.categoryRename:
          await document
              .update(<String, Object?>{
                ...record.payload,
                'updatedAt': FieldValue.serverTimestamp(),
              })
              .timeout(deadline);
        // **A callable, because retiring clears stock.** The units a retired
        // product was holding leave through a `stock_movements` entry written in
        // the same transaction as the flag, and no device may write that
        // collection - the same reason creating a product stopped being a `set`.
        // The payload is the whole request, so nothing is derived here.
        case TenantPendingMutationKind.productRetire:
          await _call('setProductRetired', record.payload);
        case TenantPendingMutationKind.productCorrect:
          await _call('updateProduct', record.payload);
        case TenantPendingMutationKind.stockAdjust:
          await _call('adjustStock', record.payload);
      }
      return const TenantMutationSubmissionResult(
        TenantMutationSubmissionOutcome.committed,
      );
    } on TimeoutException {
      return const TenantMutationSubmissionResult(
        TenantMutationSubmissionOutcome.uncertain,
        'write_timeout',
      );
    } on FirebaseException catch (error) {
      if (_settledAnyway(record, error)) {
        return const TenantMutationSubmissionResult(
          TenantMutationSubmissionOutcome.committed,
        );
      }
      return TenantMutationSubmissionResult(
        _rejectedCodes.contains(error.code)
            ? TenantMutationSubmissionOutcome.rejected
            : TenantMutationSubmissionOutcome.uncertain,
        error.code,
      );
    } catch (_) {
      return const TenantMutationSubmissionResult(
        TenantMutationSubmissionOutcome.uncertain,
        'unknown_error',
      );
    }
  }

  Future<void> _call(String name, Map<String, Object?> payload) =>
      _functions.httpsCallable(name).call<Object?>(payload).timeout(deadline);

  /// Whether a refusal means the change is in place regardless.
  ///
  /// **`updateProduct` refuses a request that changes nothing**, and a queued
  /// correction can reach that state honestly: the same edit may have been made
  /// from another till while this one was offline. The device asked for a
  /// product to hold certain values and it holds them. Reporting that as a
  /// rejection would take a correct value off the screen and tell a shopkeeper
  /// their edit failed, which is false twice over.
  ///
  /// Deliberately narrow. `already-exists` is *not* here: that one means this
  /// request ID settled a **different** payload, which is a real conflict and
  /// has to be seen.
  bool _settledAnyway(
    TenantPendingMutationRecord record,
    FirebaseException error,
  ) =>
      record.kind == TenantPendingMutationKind.productCorrect &&
      error.code == 'failed-precondition' &&
      (error.message ?? '').contains('already holds every value');
}
