import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'tenant_pending_mutation.dart';

final class FirebaseTenantMutationGateway
    implements
        TenantMutationSubmissionGateway,
        TenantMutationConfirmationGateway {
  FirebaseTenantMutationGateway({
    FirebaseFirestore? firestore,
    this.deadline = const Duration(seconds: 8),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
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
}
