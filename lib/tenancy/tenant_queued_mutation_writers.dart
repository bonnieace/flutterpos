/// **The queue is the commit, and that is the whole point of this file.**
///
/// Until 2026-09-04 every writer here tried the network first and reached for
/// the durable record only once that had failed, which made the queue a
/// consolation prize: the fast path and the slow path were the same path, and a
/// shopkeeper on one bar of signal waited twenty seconds to find out their
/// expense had been saved locally all along. Enqueuing first inverts it. The
/// record is written to encrypted local storage, the caller is told *queued*
/// immediately, and [TenantPendingMutationWorker] carries it - online in the
/// same second, offline whenever the device comes back.
///
/// **Nothing is lost by not waiting.** The outcome still arrives: the worker
/// confirms or rejects each record, [TenantPendingMutationOverlayReader] draws
/// unresolved ones over every read so the change is visible at once, and a
/// rejection withdraws that overlay and is retained as evidence for the
/// notifications screen. What changed is only *when the person may carry on*.
///
/// **Validation did not move.** Every intent here is built by a guarded
/// repository, and [TenantPendingMutationStore.enqueue] re-checks the target
/// path against the tenant before writing anything, so a malformed or
/// out-of-tenant change still refuses synchronously, exactly as it did.
library;

import '../checkout/checkout_configuration_writer.dart';
import '../expenses/expense_request.dart';
import '../inventory/catalog_management.dart';
import '../inventory/stock_take.dart';
import '../production/production_batch.dart';
import '../returns/return_request.dart';
import '../suppliers/supplier.dart';
import '../suppliers/supplier_delivery.dart';
import 'tenant_pending_mutation.dart';
import 'tenant_repository.dart';

/// Fires once a change is durable on this device, so the worker that carries it
/// to the server can start now rather than at the next reconnect.
typedef TenantQueuedMutationSignal = void Function();

/// Durable-first expense writing.
final class QueuedTenantExpenseWriter implements TenantExpenseWriter {
  const QueuedTenantExpenseWriter({
    required TenantPendingMutationStore store,
    TenantQueuedMutationSignal? onQueued,
  }) : _store = store,
       _onQueued = onQueued;

  final TenantPendingMutationStore _store;
  final TenantQueuedMutationSignal? _onQueued;

  @override
  Future<TenantExpenseWriteResult> recordExpense(
    TenantExpenseCreateIntent intent,
  ) async {
    await _store.enqueue(
      uid: intent.recordedBy,
      tenantId: intent.tenantId,
      operationId: 'expense-create-${intent.expenseId}',
      kind: TenantPendingMutationKind.expenseCreate,
      targetPath: intent.path,
      payload: intent.documentData(),
    );
    _onQueued?.call();
    return const TenantExpenseWriteResult.queued();
  }

  @override
  Future<TenantExpenseWriteResult> voidExpense(
    TenantExpenseVoidIntent intent,
  ) async {
    await _store.enqueue(
      uid: intent.voidedBy,
      tenantId: intent.tenantId,
      operationId: 'expense-void-${intent.expenseId}',
      kind: TenantPendingMutationKind.expenseVoid,
      targetPath: intent.path,
      payload: intent.documentData(),
    );
    _onQueued?.call();
    return const TenantExpenseWriteResult.queued();
  }
}

/// Durable-first pending-return writing.
final class QueuedTenantReturnWriter implements TenantReturnWriter {
  const QueuedTenantReturnWriter({
    required TenantPendingMutationStore store,
    TenantQueuedMutationSignal? onQueued,
  }) : _store = store,
       _onQueued = onQueued;

  final TenantPendingMutationStore _store;
  final TenantQueuedMutationSignal? _onQueued;

  @override
  Future<TenantReturnWriteResult> recordReturn(
    TenantReturnCreateIntent intent,
  ) async {
    await _store.enqueue(
      uid: intent.createdBy,
      tenantId: intent.tenantId,
      operationId: 'return-create-${intent.returnId}',
      kind: TenantPendingMutationKind.pendingReturnCreate,
      targetPath: intent.path,
      payload: intent.documentData(),
    );
    _onQueued?.call();
    return const TenantReturnWriteResult.queued();
  }
}

/// Durable-first catalog writing.
///
/// **All four of these are document writes `firestore.rules` already admits**
/// for exactly the roles this route is offered to - create is owner, admin or
/// manager; delete is owner or admin - so queueing them replays the same write
/// the panel used to issue inline. No rule is widened, and none needs to be.
///
/// The uid comes from [currentUid] rather than from the intent, even where an
/// intent carries a `createdBy` that holds the same value. The record's uid is
/// what scopes its storage key and what
/// [TenantPendingMutationOverlayReader] matches on when deciding whether to
/// draw it; taking both from one source is what guarantees a queued change is
/// visible to the session that made it.
final class QueuedTenantCatalogWriter implements TenantCatalogWriter {
  const QueuedTenantCatalogWriter({
    required TenantPendingMutationStore store,
    required TenantPendingMutationUidProvider currentUid,
    TenantQueuedMutationSignal? onQueued,
  }) : _store = store,
       _currentUid = currentUid,
       _onQueued = onQueued;

  final TenantPendingMutationStore _store;
  final TenantPendingMutationUidProvider _currentUid;
  final TenantQueuedMutationSignal? _onQueued;

  @override
  Future<TenantCatalogWriteResult> createCategory(
    TenantCategoryCreateIntent intent,
  ) => _queue(
    tenantId: intent.tenantId,
    operationId: 'category-create-${intent.categoryId}',
    kind: TenantPendingMutationKind.categoryCreate,
    targetPath: intent.path,
    payload: intent.documentData(),
  );

  @override
  Future<TenantCatalogWriteResult> createProduct(
    TenantProductCreateIntent intent,
  ) => _queue(
    tenantId: intent.tenantId,
    operationId: 'product-create-${intent.productId}',
    kind: TenantPendingMutationKind.productCreate,
    targetPath: intent.path,
    payload: intent.documentData(),
  );

  @override
  Future<TenantCatalogWriteResult> renameCategory(
    TenantCategoryRenameIntent intent,
  ) => _queue(
    tenantId: intent.tenantId,
    // A category may be renamed more than once before either lands, and a
    // second rename must replace the first rather than collide with it under a
    // shared operation ID. The name it is going to is what makes them
    // different, so it is what separates the records.
    operationId:
        'category-rename-${intent.categoryId}-'
        '${tenantMutationFingerprint(intent.documentData()).substring(0, 16)}',
    kind: TenantPendingMutationKind.categoryRename,
    targetPath: intent.path,
    payload: intent.documentData(),
  );

  @override
  Future<TenantCatalogWriteResult> retireProduct(
    TenantProductRetireIntent intent,
  ) => _queue(
    tenantId: intent.tenantId,
    // The request, not the product: one product may be retired, restored and
    // retired again, and each of those clears whatever it held at that moment.
    // Keying on the product would make the second collide with the first.
    operationId: 'product-retire-${intent.requestId}',
    kind: TenantPendingMutationKind.productRetire,
    targetPath: intent.path,
    // **It carries the request now, where a delete carried nothing.** Retiring
    // is a callable, because clearing the stock means writing the ledger entry
    // that accounts for it, and no device may write that.
    payload: intent.payload(),
  );

  Future<TenantCatalogWriteResult> _queue({
    required String tenantId,
    required String operationId,
    required TenantPendingMutationKind kind,
    required String targetPath,
    required Map<String, Object?> payload,
  }) async {
    final uid = _currentUid();
    if (uid == null) {
      throw const TenantCatalogManagementException('catalog_no_session');
    }
    await _store.enqueue(
      uid: uid,
      tenantId: tenantId,
      operationId: operationId,
      kind: kind,
      targetPath: targetPath,
      payload: payload,
    );
    _onQueued?.call();
    return TenantCatalogWriteResult.queued(operationId);
  }
}

/// Durable-first supplier writing.
///
/// Both are callables, queued the way categories are and for the same reason:
/// a supplier's name is unique across the business, which only the server can
/// check. The uid comes from [currentUid], as the catalog writer's does, so a
/// queued supplier is drawn for the session that added it.
final class QueuedTenantSupplierWriter implements TenantSupplierWriter {
  const QueuedTenantSupplierWriter({
    required TenantPendingMutationStore store,
    required TenantPendingMutationUidProvider currentUid,
    TenantQueuedMutationSignal? onQueued,
  }) : _store = store,
       _currentUid = currentUid,
       _onQueued = onQueued;

  final TenantPendingMutationStore _store;
  final TenantPendingMutationUidProvider _currentUid;
  final TenantQueuedMutationSignal? _onQueued;

  @override
  Future<TenantSupplierWriteResult> createSupplier(
    TenantSupplierCreateIntent intent,
  ) => _queue(
    tenantId: intent.tenantId,
    operationId: 'supplier-create-${intent.supplierId}',
    kind: TenantPendingMutationKind.supplierCreate,
    targetPath: intent.path,
    payload: intent.documentData(),
  );

  @override
  Future<TenantSupplierWriteResult> updateSupplier(
    TenantSupplierUpdateIntent intent,
  ) => _queue(
    tenantId: intent.tenantId,
    operationId: intent.operationId,
    kind: TenantPendingMutationKind.supplierUpdate,
    targetPath: intent.path,
    payload: intent.documentData(),
  );

  Future<TenantSupplierWriteResult> _queue({
    required String tenantId,
    required String operationId,
    required TenantPendingMutationKind kind,
    required String targetPath,
    required Map<String, Object?> payload,
  }) async {
    final uid = _currentUid();
    if (uid == null) {
      throw const TenantSupplierException('supplier_no_session');
    }
    await _store.enqueue(
      uid: uid,
      tenantId: tenantId,
      operationId: operationId,
      kind: kind,
      targetPath: targetPath,
      payload: payload,
    );
    _onQueued?.call();
    return TenantSupplierWriteResult.queued(operationId);
  }
}

/// Durable-first supplier deliveries.
///
/// **Every page of one delivery is queued at once**, which is what lets a
/// delivery be received with no connection. They share one target path - the
/// delivery - so the worker carries them in order, each page all or none, and
/// the overlay draws the stock each page brings in on the catalog the moment it
/// is queued.
final class QueuedTenantSupplierDeliveryWriter
    implements TenantSupplierDeliveryWriter {
  const QueuedTenantSupplierDeliveryWriter({
    required TenantPendingMutationStore store,
    required TenantPendingMutationUidProvider currentUid,
    TenantQueuedMutationSignal? onQueued,
  }) : _store = store,
       _currentUid = currentUid,
       _onQueued = onQueued;

  final TenantPendingMutationStore _store;
  final TenantPendingMutationUidProvider _currentUid;
  final TenantQueuedMutationSignal? _onQueued;

  @override
  Future<TenantSupplierDeliveryWriteResult> receive(
    TenantSupplierDeliveryIntent intent,
  ) async {
    final uid = _currentUid();
    if (uid == null) {
      throw const TenantSupplierDeliveryException('delivery_no_session');
    }
    final operationIds = <String>[];
    for (final page in intent.pages()) {
      await _store.enqueue(
        uid: uid,
        tenantId: page.tenantId,
        operationId: page.operationId,
        kind: TenantPendingMutationKind.supplierDeliveryPage,
        targetPath: page.path,
        payload: page.payload,
      );
      operationIds.add(page.operationId);
    }
    _onQueued?.call();
    return TenantSupplierDeliveryWriteResult.queued(
      List<String>.unmodifiable(operationIds),
    );
  }
}

/// Durable-first production batches.
///
/// **Addressed to the batch, never the product**, so a batch the server refuses
/// strands only itself and not every later stock change to what it made. The
/// overlay draws the stock and the cost it brings on the catalog the moment it
/// is queued.
final class QueuedTenantProductionWriter implements TenantProductionWriter {
  const QueuedTenantProductionWriter({
    required TenantPendingMutationStore store,
    required TenantPendingMutationUidProvider currentUid,
    TenantQueuedMutationSignal? onQueued,
  }) : _store = store,
       _currentUid = currentUid,
       _onQueued = onQueued;

  final TenantPendingMutationStore _store;
  final TenantPendingMutationUidProvider _currentUid;
  final TenantQueuedMutationSignal? _onQueued;

  @override
  Future<TenantProductionWriteResult> complete(
    TenantProductionIntent intent,
  ) async {
    final uid = _currentUid();
    if (uid == null) {
      throw const TenantProductionException('production_no_session');
    }
    await _store.enqueue(
      uid: uid,
      tenantId: intent.tenantId,
      operationId: intent.operationId,
      kind: TenantPendingMutationKind.productionComplete,
      targetPath: intent.path,
      payload: intent.payload(),
    );
    _onQueued?.call();
    return TenantProductionWriteResult.queued(intent.operationId);
  }
}

/// Durable-first stock counting.
///
/// **Every page of one count is queued at once**, which is what lets submitting
/// return immediately with no connection. They share a target path - the take -
/// so the worker carries them in order, while a colleague's count on another
/// device drains independently of them.
final class QueuedTenantStockTakeWriter implements TenantStockTakeWriter {
  const QueuedTenantStockTakeWriter({
    required TenantPendingMutationStore store,
    required TenantPendingMutationUidProvider currentUid,
    TenantQueuedMutationSignal? onQueued,
  }) : _store = store,
       _currentUid = currentUid,
       _onQueued = onQueued;

  final TenantPendingMutationStore _store;
  final TenantPendingMutationUidProvider _currentUid;
  final TenantQueuedMutationSignal? _onQueued;

  @override
  Future<TenantStockTakeWriteResult> submitPage(
    TenantStockTakePageIntent intent,
  ) async {
    final uid = _currentUid();
    if (uid == null) {
      // Nothing durable can be written without a session to scope its storage
      // key to, and a count that is silently not queued is a count somebody
      // believes they have handed in.
      throw const TenantStockTakeException(TenantStockTakeFailure.forbidden);
    }
    await _store.enqueue(
      uid: uid,
      tenantId: intent.tenantId,
      operationId: intent.operationId,
      kind: TenantPendingMutationKind.stockTakePage,
      targetPath: intent.path,
      payload: intent.payload(),
    );
    _onQueued?.call();
    return TenantStockTakeWriteResult.queued(intent.operationId);
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
    TenantQueuedMutationSignal? onQueued,
  }) : _remote = remote,
       _store = store,
       _cacheReader = cacheReader,
       _currentUid = currentUid,
       _onQueued = onQueued;

  final TenantConfigurationDocumentWriter _remote;
  final TenantPendingMutationStore _store;
  final TenantDataReader _cacheReader;
  final TenantPendingMutationUidProvider _currentUid;
  final TenantQueuedMutationSignal? _onQueued;

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
    final uid = _currentUid();
    // Without a session there is nothing to scope a durable record to, so this
    // is the one case that still has to go straight at the server.
    if (uid == null) return _remote.merge(path: path, data: data);
    TenantDocumentSnapshot? before;
    try {
      before = await _cacheReader.getDocument(path);
    } catch (_) {
      // An empty fingerprint is safe: if a server value exists, confirmation
      // will detect the mismatch and retain this edit for review. A damaged or
      // absent local projection must not make an offline edit disappear.
      before = null;
    }
    final payloadHash = tenantMutationFingerprint(data).substring(0, 32);
    final editSequence = DateTime.now().toUtc().microsecondsSinceEpoch;
    await _store.enqueue(
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
    _onQueued?.call();
    return const TenantConfigurationWriteResult.queued();
  }
}
