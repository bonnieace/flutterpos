import '../checkout/checkout_configuration_writer.dart';
import '../expenses/expense_request.dart';
import '../returns/return_request.dart';
import 'tenant_pending_mutation.dart';
import 'tenant_repository.dart';

/// Adds durable offline semantics to the existing authoritative expense
/// writer without changing its online behavior.
final class QueuedTenantExpenseWriter implements TenantExpenseWriter {
  const QueuedTenantExpenseWriter({
    required TenantExpenseWriter remote,
    required TenantPendingMutationStore store,
  }) : _remote = remote,
       _store = store;

  final TenantExpenseWriter _remote;
  final TenantPendingMutationStore _store;

  @override
  Future<TenantExpenseWriteResult> recordExpense(
    TenantExpenseCreateIntent intent,
  ) async {
    final result = await _remote.recordExpense(intent);
    if (result.kind != TenantExpenseWriteKind.unavailable &&
        result.kind != TenantExpenseWriteKind.ambiguous) {
      return result;
    }
    final record = await _store.enqueue(
      uid: intent.recordedBy,
      tenantId: intent.tenantId,
      operationId: 'expense-create-${intent.expenseId}',
      kind: TenantPendingMutationKind.expenseCreate,
      targetPath: intent.path,
      payload: intent.documentData(),
    );
    if (result.kind == TenantExpenseWriteKind.ambiguous) {
      await _store.markAwaiting(record);
    }
    return const TenantExpenseWriteResult.queued();
  }

  @override
  Future<TenantExpenseWriteResult> voidExpense(
    TenantExpenseVoidIntent intent,
  ) async {
    final result = await _remote.voidExpense(intent);
    if (result.kind != TenantExpenseWriteKind.unavailable &&
        result.kind != TenantExpenseWriteKind.ambiguous) {
      return result;
    }
    final record = await _store.enqueue(
      uid: intent.voidedBy,
      tenantId: intent.tenantId,
      operationId: 'expense-void-${intent.expenseId}',
      kind: TenantPendingMutationKind.expenseVoid,
      targetPath: intent.path,
      payload: intent.documentData(),
    );
    if (result.kind == TenantExpenseWriteKind.ambiguous) {
      await _store.markAwaiting(record);
    }
    return const TenantExpenseWriteResult.queued();
  }
}

final class QueuedTenantReturnWriter implements TenantReturnWriter {
  const QueuedTenantReturnWriter({
    required TenantReturnWriter remote,
    required TenantPendingMutationStore store,
  }) : _remote = remote,
       _store = store;

  final TenantReturnWriter _remote;
  final TenantPendingMutationStore _store;

  @override
  Future<TenantReturnWriteResult> recordReturn(
    TenantReturnCreateIntent intent,
  ) async {
    final result = await _remote.recordReturn(intent);
    if (result.kind != TenantReturnWriteKind.unavailable &&
        result.kind != TenantReturnWriteKind.ambiguous) {
      return result;
    }
    final record = await _store.enqueue(
      uid: intent.createdBy,
      tenantId: intent.tenantId,
      operationId: 'return-create-${intent.returnId}',
      kind: TenantPendingMutationKind.pendingReturnCreate,
      targetPath: intent.path,
      payload: intent.documentData(),
    );
    if (result.kind == TenantReturnWriteKind.ambiguous) {
      await _store.markAwaiting(record);
    }
    return const TenantReturnWriteResult.queued();
  }
}

/// Queues only the two safe fixed configuration documents. Checkout currency
/// and every other configuration mutation remain server-only.
final class QueuedTenantConfigurationWriter
    implements TenantConfigurationDocumentWriter {
  const QueuedTenantConfigurationWriter({
    required TenantConfigurationDocumentWriter remote,
    required TenantPendingMutationStore store,
    required TenantDataReader cacheReader,
    required TenantPendingMutationUidProvider currentUid,
  }) : _remote = remote,
       _store = store,
       _cacheReader = cacheReader,
       _currentUid = currentUid;

  final TenantConfigurationDocumentWriter _remote;
  final TenantPendingMutationStore _store;
  final TenantDataReader _cacheReader;
  final TenantPendingMutationUidProvider _currentUid;

  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async {
    final parts = path.split('/');
    if (parts.length != 4 ||
        parts[0] != 'tenants' ||
        parts[2] != 'configuration' ||
        parts[3] != 'branding' && parts[3] != 'printer') {
      return _remote.merge(path: path, data: data);
    }
    TenantDocumentSnapshot? before;
    try {
      before = await _cacheReader.getDocument(path);
    } catch (_) {
      // An empty fingerprint is safe: if a server value exists, confirmation
      // will detect the mismatch and retain this edit for review. A damaged or
      // absent local projection must not make an offline edit disappear.
      before = null;
    }
    final result = await _remote.merge(path: path, data: data);
    if (result.kind != TenantConfigurationWriteKind.unavailable &&
        result.kind != TenantConfigurationWriteKind.ambiguous) {
      return result;
    }
    final uid = _currentUid();
    if (uid == null) return result;
    final payloadHash = tenantMutationFingerprint(data).substring(0, 32);
    final editSequence = DateTime.now().toUtc().microsecondsSinceEpoch;
    final record = await _store.enqueue(
      uid: uid,
      tenantId: parts[1],
      operationId: 'config-${parts[3]}-$editSequence-$payloadHash',
      kind: parts[3] == 'branding'
          ? TenantPendingMutationKind.brandingMerge
          : TenantPendingMutationKind.printerConfigurationMerge,
      targetPath: path,
      payload: data,
      replacedValueFingerprint: tenantConfigurationMutationFingerprint(
        before?.data ?? const <String, Object?>{},
      ),
    );
    if (result.kind == TenantConfigurationWriteKind.ambiguous) {
      await _store.markAwaiting(record);
    }
    return const TenantConfigurationWriteResult.queued();
  }
}
