/// Recording an expense, and withdrawing one that was wrong.
///
/// A direct parallel of `FirebaseTenantReturnWriter`: the same four-way result,
/// the same rejected-code set, the same `set` so a reused ID is a rules denial
/// rather than a silent overwrite, and the same refusal to attempt a write with
/// no network. Two money records written by the same client deserve the same
/// treatment, and the return writer is the one this codebase already trusts.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../checkout/checkout_receipt.dart';
import '../checkout/checkout_sale.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import 'expense.dart';

/// One expense a person has asked to record.
///
/// The server-owned `createdAt` is deliberately not part of the data: the
/// writer adds it, so the device clock cannot decide when money left the
/// business. [businessDate] is the device's reading of *which trading day* this
/// belongs to, which is a different question and one only the device can answer
/// for an expense entered at the counter.
final class TenantExpenseCreateIntent {
  factory TenantExpenseCreateIntent({
    required String tenantId,
    required String businessDate,
    required String token,
    required TenantExpenseCategory category,
    required String description,
    required int amountMinor,
    required String recordedBy,
  }) {
    final safeTenantId = validateTenantId(tenantId);
    final safeDate = validateCheckoutBusinessDate(businessDate);
    final expenseId = tenantExpenseId(safeDate, token);
    final trimmed = description.trim();
    if (trimmed.length < 3 || trimmed.length > 500) {
      throw const TenantExpenseException('invalid_expense_description');
    }
    // Zero is refused with the negatives: an expense of nothing did not happen,
    // and recording one puts a row on a report no money corresponds to.
    if (amountMinor <= 0 || amountMinor > maximumExpenseMinorAmount) {
      throw const TenantExpenseException('invalid_expense_amount');
    }
    if (recordedBy.isEmpty || recordedBy.length > 128) {
      throw const TenantExpenseException('invalid_expense_author');
    }
    return TenantExpenseCreateIntent._(
      tenantId: safeTenantId,
      expenseId: expenseId,
      businessDate: safeDate,
      category: category,
      description: trimmed,
      amountMinor: amountMinor,
      recordedBy: recordedBy,
    );
  }

  const TenantExpenseCreateIntent._({
    required this.tenantId,
    required this.expenseId,
    required this.businessDate,
    required this.category,
    required this.description,
    required this.amountMinor,
    required this.recordedBy,
  });

  final String tenantId;
  final String expenseId;
  final String businessDate;
  final TenantExpenseCategory category;
  final String description;
  final int amountMinor;
  final String recordedBy;

  String get path => TenantPaths(tenantId).expenseRecord(expenseId);

  /// Every field the create rule allows, and no other.
  ///
  /// `createdAt` is absent by design; the writer supplies it as a server
  /// timestamp, which is what the rule requires.
  Map<String, Object?> documentData() => <String, Object?>{
    'expenseId': expenseId,
    'tenantId': tenantId,
    'businessDate': businessDate,
    'category': category.wireValue,
    'description': description,
    'amountMinor': amountMinor,
    // The major-unit mirror, stored the way a closed shift stores `totalSales`
    // beside `totalSalesMinor`. The minor figure is canonical; this one is for
    // anything reading the document that does not know the convention.
    'amount': amountMinor / 100,
    'recordedBy': recordedBy,
  };
}

/// A request to withdraw an expense that should not have been recorded.
///
/// **A void, not a delete or an edit.** The record stays, the correction is
/// visible beside it, and neither can be quietly rewritten - which is how every
/// other money record in this app behaves. The Firestore rule freezes every
/// other key of the document, so this can add exactly these three fields and
/// only to a record that has not already been voided.
final class TenantExpenseVoidIntent {
  factory TenantExpenseVoidIntent({
    required String tenantId,
    required String expenseId,
    required String reason,
    required String voidedBy,
  }) {
    final safeTenantId = validateTenantId(tenantId);
    final safeExpenseId = validateTenantDocumentId(
      expenseId,
      fieldName: 'expenseId',
    );
    final trimmed = reason.trim();
    if (trimmed.length < 3 || trimmed.length > 500) {
      throw const TenantExpenseException('invalid_expense_void_reason');
    }
    if (voidedBy.isEmpty || voidedBy.length > 128) {
      throw const TenantExpenseException('invalid_expense_author');
    }
    return TenantExpenseVoidIntent._(
      tenantId: safeTenantId,
      expenseId: safeExpenseId,
      reason: trimmed,
      voidedBy: voidedBy,
    );
  }

  const TenantExpenseVoidIntent._({
    required this.tenantId,
    required this.expenseId,
    required this.reason,
    required this.voidedBy,
  });

  final String tenantId;
  final String expenseId;
  final String reason;
  final String voidedBy;

  String get path => TenantPaths(tenantId).expenseRecord(expenseId);

  Map<String, Object?> documentData() => <String, Object?>{
    'voidReason': reason,
    'voidedBy': voidedBy,
  };
}

/// What became of a write.
enum TenantExpenseWriteKind {
  /// Saved durably on this device and waiting for synchronization.
  queued,

  /// The server accepted it.
  committed,

  /// The server refused it, and retrying the same request will not help.
  rejected,

  /// It is not known whether the write landed.
  ambiguous,

  /// No attempt was made because the device was offline.
  unavailable,
}

final class TenantExpenseWriteResult {
  const TenantExpenseWriteResult._(this.kind, [this.reasonCode]);

  const TenantExpenseWriteResult.committed()
    : this._(TenantExpenseWriteKind.committed);

  const TenantExpenseWriteResult.queued()
    : this._(TenantExpenseWriteKind.queued);

  const TenantExpenseWriteResult.rejected(String reasonCode)
    : this._(TenantExpenseWriteKind.rejected, reasonCode);

  const TenantExpenseWriteResult.ambiguous(String reasonCode)
    : this._(TenantExpenseWriteKind.ambiguous, reasonCode);

  const TenantExpenseWriteResult.unavailable()
    : this._(TenantExpenseWriteKind.unavailable);

  final TenantExpenseWriteKind kind;
  final String? reasonCode;
}

/// The narrow write boundary used to record and withdraw an expense.
abstract interface class TenantExpenseWriter {
  Future<TenantExpenseWriteResult> recordExpense(
    TenantExpenseCreateIntent intent,
  );

  Future<TenantExpenseWriteResult> voidExpense(TenantExpenseVoidIntent intent);
}

typedef TenantExpenseOnlineCheck = Future<bool> Function();
typedef TenantExpenseDocumentCreator =
    Future<void> Function(String path, Map<String, Object?> data);
typedef TenantExpenseDocumentUpdater =
    Future<void> Function(String path, Map<String, Object?> data);

/// Firestore implementation of the expense write boundary.
final class FirebaseTenantExpenseWriter implements TenantExpenseWriter {
  FirebaseTenantExpenseWriter({
    FirebaseFirestore? firestore,
    required TenantExpenseOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(
         create: _firestoreCreator(firestore ?? FirebaseFirestore.instance),
         update: _firestoreUpdater(firestore ?? FirebaseFirestore.instance),
         isOnline: isOnline,
         writeTimeout: writeTimeout,
       );

  FirebaseTenantExpenseWriter.forTesting({
    required TenantExpenseDocumentCreator create,
    required TenantExpenseDocumentUpdater update,
    required TenantExpenseOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(
         create: create,
         update: update,
         isOnline: isOnline,
         writeTimeout: writeTimeout,
       );

  FirebaseTenantExpenseWriter._({
    required TenantExpenseDocumentCreator create,
    required TenantExpenseDocumentUpdater update,
    required TenantExpenseOnlineCheck isOnline,
    required Duration writeTimeout,
  }) : _create = create,
       _update = update,
       _isOnline = isOnline,
       _writeTimeout = writeTimeout {
    if (writeTimeout <= Duration.zero) {
      throw ArgumentError.value(writeTimeout, 'writeTimeout');
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

  final TenantExpenseDocumentCreator _create;
  final TenantExpenseDocumentUpdater _update;
  final TenantExpenseOnlineCheck _isOnline;
  final Duration _writeTimeout;

  @override
  Future<TenantExpenseWriteResult> recordExpense(
    TenantExpenseCreateIntent intent,
  ) {
    if (TenantPaths(intent.tenantId).expenseRecord(intent.expenseId) !=
        intent.path) {
      throw const TenantExpenseException('expense_path_escaped_tenant');
    }
    return _attempt(
      () => _create(intent.path, <String, Object?>{
        ...intent.documentData(),
        'createdAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  @override
  Future<TenantExpenseWriteResult> voidExpense(TenantExpenseVoidIntent intent) {
    if (TenantPaths(intent.tenantId).expenseRecord(intent.expenseId) !=
        intent.path) {
      throw const TenantExpenseException('expense_path_escaped_tenant');
    }
    return _attempt(
      () => _update(intent.path, <String, Object?>{
        ...intent.documentData(),
        'voidedAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  Future<TenantExpenseWriteResult> _attempt(
    Future<void> Function() write,
  ) async {
    if (!await _online()) return const TenantExpenseWriteResult.unavailable();
    try {
      await write().timeout(_writeTimeout);
      return const TenantExpenseWriteResult.committed();
    } on TimeoutException {
      return const TenantExpenseWriteResult.ambiguous('write_timeout');
    } on FirebaseException catch (error) {
      return _rejectedCodes.contains(error.code)
          ? TenantExpenseWriteResult.rejected(error.code)
          : TenantExpenseWriteResult.ambiguous(error.code);
    } catch (_) {
      return const TenantExpenseWriteResult.ambiguous('unknown_error');
    }
  }

  Future<bool> _online() async {
    try {
      return await _isOnline();
    } catch (_) {
      return false;
    }
  }

  static TenantExpenseDocumentCreator _firestoreCreator(
    FirebaseFirestore firestore,
  ) =>
      (path, data) => firestore.doc(path).set(data);

  /// `update`, never `set(merge:)`. A void must land on a record that already
  /// exists; merging would create one out of three fields if the ID were wrong.
  static TenantExpenseDocumentUpdater _firestoreUpdater(
    FirebaseFirestore firestore,
  ) =>
      (path, data) => firestore.doc(path).update(data);
}

/// The largest expense this app will record.
///
/// The same ceiling the till applies to a sale, so one boundary governs every
/// monetary figure a client can write.
const int maximumExpenseMinorAmount = maximumCheckoutMinorAmount;
