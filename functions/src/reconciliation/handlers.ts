import {getFunctions} from "firebase-admin/functions";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {requireTenantMember} from "../core/authorization";
import {
  buildIdempotencyIdentity,
  runIdempotentFirestoreTransaction,
} from "../core/idempotency";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {requireIsoDate} from "../operations/domain";
import {
  advanceReconciliationJob,
  claimReconciliationJob,
  createManualJobInTransaction,
  ensureSweep,
  finalizeReconciliationJob,
  listRetryableReconciliationTasks,
  processTenantDiscoveryPage,
  recordReconciliationFailure,
  registerReturnReceipt,
  registerSaleReceipt,
} from "./jobs";
import {
  discoveryTaskId,
  nairobiDate,
  ReconciliationMode,
  reconciliationTaskId,
  ReconciliationTaskPayload,
  requireDiscoveryPayload,
  requireTaskPayload,
  TenantDiscoveryTaskPayload,
} from "./model";
import {
  initializeFullReconciliationWindow,
  processMetricsPage,
  processShiftPage,
  processStockPage,
} from "./processors";

const RECONCILIATION_TASK_FUNCTION = "runTenantReconciliationTask";
const DISCOVERY_TASK_FUNCTION = "runReconciliationTenantDiscoveryTask";
const RECONCILIATION_REQUEST_ROLES = ["owner", "admin"] as const;

interface RequestReconciliationRequest {
  tenantId?: unknown;
  mode?: unknown;
  requestId?: unknown;
}

export interface RequestReconciliationResponse {
  tenantId: string;
  jobId: string;
  mode: ReconciliationMode;
  status: "queued";
}

function requireMode(value: unknown): ReconciliationMode {
  if (value !== "incremental" && value !== "full") {
    throw new HttpsError("invalid-argument", "mode must be incremental or full.");
  }
  return value;
}

function taskAlreadyExists(error: unknown): boolean {
  if (!error || typeof error !== "object" || !("code" in error)) return false;
  const code = (error as {code?: unknown}).code;
  return code === "functions/task-already-exists" || code === "already-exists" || code === 6;
}

export async function enqueueReconciliationTask(
  payload: ReconciliationTaskPayload
): Promise<void> {
  requireTaskPayload(payload);
  try {
    await getFunctions().taskQueue<ReconciliationTaskPayload>(
      RECONCILIATION_TASK_FUNCTION
    ).enqueue(payload, {
      id: reconciliationTaskId(payload),
      dispatchDeadlineSeconds: 420,
    });
  } catch (error) {
    if (!taskAlreadyExists(error)) throw error;
  }
}

export async function enqueueDiscoveryTask(
  payload: TenantDiscoveryTaskPayload
): Promise<void> {
  requireDiscoveryPayload(payload);
  try {
    await getFunctions().taskQueue<TenantDiscoveryTaskPayload>(
      DISCOVERY_TASK_FUNCTION
    ).enqueue(payload, {
      id: discoveryTaskId(payload),
      dispatchDeadlineSeconds: 300,
    });
  } catch (error) {
    if (!taskAlreadyExists(error)) throw error;
  }
}

/** Canonically authorized manual entry point; enqueue is recoverable from the durable job. */
export const requestTenantReconciliation = onCall<
  RequestReconciliationRequest,
  Promise<RequestReconciliationResponse>
>(async (
  request: CallableRequest<RequestReconciliationRequest>
): Promise<RequestReconciliationResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const mode = requireMode(data.mode);
  const requestId = requireRequestId(data.requestId);
  const db = getFirestore();
  const actor = await requireTenantMember(db, request, tenantId, RECONCILIATION_REQUEST_ROLES);
  const identity = buildIdempotencyIdentity(
    actor.uid,
    "requestTenantReconciliation",
    tenantId,
    requestId
  );
  const jobId = `rj_${identity.documentId.slice(0, 40)}`;
  const localDate = nairobiDate(new Date());
  const requestedAt = Timestamp.now();
  const response = await runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "requestTenantReconciliation",
    tenantId,
    requestId,
    input: {mode},
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      RECONCILIATION_REQUEST_ROLES,
      transaction
    );
    const admissionRef = db.collection("tenants").doc(tenantId)
      .collection("reconciliation_controls").doc(`manual_${mode}`);
    const admissionSnapshot = await transaction.get(admissionRef);
    const nextAllowedAt = admissionSnapshot.get("nextAllowedAt");
    if (nextAllowedAt instanceof Timestamp && nextAllowedAt.toMillis() > requestedAt.toMillis()) {
      throw new HttpsError(
        "resource-exhausted",
        `Another manual ${mode} reconciliation was requested too recently.`
      );
    }
    const cooldownMilliseconds = mode === "full" ? 24 * 60 * 60 * 1000 : 5 * 60 * 1000;
    transaction.set(admissionRef, {
      tenantId,
      mode,
      activeJobId: jobId,
      lastRequestedBy: currentActor.uid,
      lastRequestedAt: requestedAt,
      nextAllowedAt: Timestamp.fromMillis(requestedAt.toMillis() + cooldownMilliseconds),
      updatedAt: requestedAt,
    }, {merge: true});
    createManualJobInTransaction(db, transaction, {
      tenantId,
      jobId,
      actorUid: currentActor.uid,
      requestId,
      mode,
      localDate,
    });
    transaction.create(
      db.collection("tenants").doc(tenantId).collection("audit_logs").doc(jobId),
      {
        eventType: "tenant_reconciliation_requested",
        tenantId,
        jobId,
        mode,
        actorUid: currentActor.uid,
        requestId,
        createdAt: Timestamp.now(),
      }
    );
    return {tenantId, jobId, mode, status: "queued" as const};
  });
  await enqueueReconciliationTask({tenantId, jobId, generation: 0, revision: 0});
  return response;
});

async function executeReconciliationTask(payload: ReconciliationTaskPayload): Promise<void> {
  requireTaskPayload(payload);
  const db = getFirestore();
  const job = await claimReconciliationJob(db, payload);
  if (!job) return;
  try {
    let continuation: ReconciliationTaskPayload | undefined;
    if (job.phase === "metrics") {
      if (job.mode === "full" && !job.fullInitialized) {
        await initializeFullReconciliationWindow(db, job);
        continuation = await advanceReconciliationJob(db, job, {fullInitialized: true});
      } else {
        const result = await processMetricsPage(db, job);
        continuation = await advanceReconciliationJob(db, job, {
          phase: result.hasMore ? "metrics" :
            job.source === "sale_trigger" ? "shifts" : "stock",
          metricsProcessedDelta: result.processed,
          ...(result.hasMore ? {} : {
            productCursor: null,
            pendingProductId: null,
          }),
        });
      }
    } else if (job.phase === "stock") {
      const result = await processStockPage(db, job);
      continuation = await advanceReconciliationJob(db, job, {
        phase: result.hasMore ? "stock" : "shifts",
        productCursor: result.productCursor ?? null,
        pendingProductId: result.pendingProductId ?? null,
        productsProcessedDelta: result.processed,
        stockVarianceDelta: result.varianceCount,
      });
    } else if (job.phase === "shifts") {
      const result = await processShiftPage(db, job);
      continuation = await advanceReconciliationJob(db, job, {
        phase: result.hasMore ? "shifts" : "finalize",
        shiftsProcessedDelta: result.processed,
        shiftVarianceDelta: result.varianceCount,
        tenderVarianceDelta: result.tenderVarianceCount,
      });
    } else {
      continuation = await finalizeReconciliationJob(db, job);
    }
    if (continuation) await enqueueReconciliationTask(continuation);
  } catch (error) {
    await recordReconciliationFailure(db, job, error);
    throw error;
  }
}

/** Private queue worker; every dispatch advances at most one bounded phase page. */
export const runTenantReconciliationTask = onTaskDispatched<ReconciliationTaskPayload>({
  retryConfig: {
    maxAttempts: 12,
    minBackoffSeconds: 15,
    maxBackoffSeconds: 3600,
    maxDoublings: 8,
  },
  rateLimits: {
    maxConcurrentDispatches: 10,
    maxDispatchesPerSecond: 20,
  },
  timeoutSeconds: 420,
  memory: "512MiB",
}, async (request) => executeReconciliationTask(request.data));

/** Lightweight receipt hook: ledger movements + one dirty job per five-minute bucket. */
export const mergeSaleReconciliationJob = onDocumentCreated(
  {
    document: "tenants/{tenantId}/sales/{saleId}",
    retry: true,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const received = new Date(event.time);
    const receivedAt = Timestamp.fromDate(received);
    const rawBusinessDate = snapshot.get("businessDate");
    let businessDate = nairobiDate(received);
    try {
      businessDate = requireIsoDate(rawBusinessDate, "businessDate");
    } catch {
      // Imported/legacy malformed dates are reconciled in their server receipt date.
    }
    const registration = await registerSaleReceipt(getFirestore(), {
      tenantId: event.params.tenantId,
      saleId: event.params.saleId,
      businessDate,
      receivedAt,
      saleData: snapshot.data(),
    });
    if (registration.task) await enqueueReconciliationTask(registration.task);
  }
);

/**
 * A return was filed, so the day its sale belongs to is no longer settled.
 *
 * **Pending counts.** The standing product decision is that a report agrees
 * with what the cashier just did rather than with what a manager has not got
 * to yet, which is what the device already does. `daily_metrics` can only
 * agree with the live report if a *filed* return regenerates the day, not only
 * a verified one - and clients write returns directly under `firestore.rules`,
 * so no callable exists to do it on the way in.
 *
 * A rejected return dirties the day too, by the same route: it is a write to
 * the same document, and takings that stayed depressed after a claim was
 * thrown out would be the same defect pointing the other way.
 */
export const mergeReturnReconciliationJob = onDocumentCreated(
  {
    document: "tenants/{tenantId}/returns/{returnId}",
    retry: true,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const received = new Date(event.time);
    // The return's own `businessDate` is pinned by rules to its sale's, so it
    // is the sale's trading day rather than the day the goods came back. A
    // malformed one falls back to the receipt date, exactly as the sale
    // trigger does with its own.
    let businessDate = nairobiDate(received);
    try {
      businessDate = requireIsoDate(snapshot.get("businessDate"), "businessDate");
    } catch {
      // Imported/legacy malformed dates are reconciled in their receipt date.
    }
    const registration = await registerReturnReceipt(getFirestore(), {
      tenantId: event.params.tenantId,
      returnId: event.params.returnId,
      businessDate,
      receivedAt: Timestamp.fromDate(received),
    });
    if (registration.task) await enqueueReconciliationTask(registration.task);
  }
);

async function executeDiscoveryTask(payload: TenantDiscoveryTaskPayload): Promise<void> {
  requireDiscoveryPayload(payload);
  const result = await processTenantDiscoveryPage(getFirestore(), payload);
  await Promise.all(result.tenantTasks.map(enqueueReconciliationTask));
  if (result.continuation) await enqueueDiscoveryTask(result.continuation);
}

/** Private tenant paginator used by nightly, weekly, and staggered monthly sweeps. */
export const runReconciliationTenantDiscoveryTask = onTaskDispatched<
  TenantDiscoveryTaskPayload
>({
  retryConfig: {
    maxAttempts: 10,
    minBackoffSeconds: 15,
    maxBackoffSeconds: 900,
    maxDoublings: 6,
  },
  rateLimits: {
    maxConcurrentDispatches: 2,
    maxDispatchesPerSecond: 5,
  },
  timeoutSeconds: 300,
}, async (request) => executeDiscoveryTask(request.data));

async function beginSweep(
  kind: "nightly" | "weekly" | "monthly",
  scheduleTime: string
): Promise<void> {
  const localDate = nairobiDate(new Date(scheduleTime));
  const payload = await ensureSweep(getFirestore(), kind, localDate);
  await enqueueDiscoveryTask(payload);
}

/** Runs at the frozen product-local time and paginates all active tenants. */
export const startNightlyTenantReconciliation = onSchedule({
  schedule: "30 5 * * *",
  timeZone: "Africa/Nairobi",
  retryCount: 3,
  timeoutSeconds: 120,
}, async (event) => beginSweep("nightly", event.scheduleTime));

/** Weekly expected-vs-observed checkpoints are independent of nightly metrics. */
export const startWeeklyStockCheckpoints = onSchedule({
  schedule: "30 4 * * 0",
  timeZone: "Africa/Nairobi",
  retryCount: 3,
  timeoutSeconds: 120,
}, async (event) => beginSweep("weekly", event.scheduleTime));

/** Daily discovery selects only the tenant's stable day-of-month shard (1..28). */
export const startStaggeredMonthlyReconciliation = onSchedule({
  schedule: "45 4 * * *",
  timeZone: "Africa/Nairobi",
  retryCount: 3,
  timeoutSeconds: 120,
}, async (event) => beginSweep("monthly", event.scheduleTime));

/** Recovers jobs durably committed before enqueue and expired Cloud Task chains. */
export const retryTenantReconciliationTasks = onSchedule({
  schedule: "every 10 minutes",
  retryCount: 1,
  timeoutSeconds: 120,
  maxInstances: 1,
}, async () => {
  const tasks = await listRetryableReconciliationTasks(getFirestore());
  await Promise.all(tasks.map(enqueueReconciliationTask));
});
