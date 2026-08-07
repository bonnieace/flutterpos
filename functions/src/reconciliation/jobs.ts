import {randomUUID} from "node:crypto";
import {
  DocumentData,
  DocumentReference,
  FieldPath,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  DirtyJobDecision,
  DirtyJobInput,
  fiveMinuteBucket,
  isoWeekKey,
  mergeDirtyJob,
  monthlyShardDay,
  ReconciliationCheckpointKind,
  ReconciliationJobPhase,
  ReconciliationJobStatus,
  reconciliationJobId,
  ReconciliationMode,
  ReconciliationSweepKind,
  ReconciliationTaskPayload,
  safeErrorCode,
  sweepRunId,
  TenantDiscoveryTaskPayload,
} from "./model";

// Deliberately exceeds the seven-minute worker deadline. Processor
// transactions also re-check the token, so an expired worker cannot commit
// after a retry owns the job.
const LEASE_MILLISECONDS = 10 * 60 * 1000;
const TENANT_DISCOVERY_PAGE_SIZE = 50;
const RETRY_PAGE_SIZE = 100;

export interface StoredReconciliationJob {
  tenantId: string;
  jobId: string;
  source: "manual" | "sale_trigger" | ReconciliationSweepKind;
  sourceKey: string;
  mode: ReconciliationMode;
  checkpointKind: ReconciliationCheckpointKind;
  checkpointKey: string;
  localDate: string;
  status: ReconciliationJobStatus;
  phase: ReconciliationJobPhase;
  generation: number;
  revision: number;
  attemptCount: number;
  consecutiveFailureCount: number;
  rerunRequested: boolean;
  fullInitialized: boolean;
  metricsProcessed: number;
  productsProcessed: number;
  stockVarianceCount: number;
  shiftsProcessed: number;
  shiftVarianceCount: number;
  productCursor?: string;
  pendingProductId?: string;
  leaseToken?: string;
  leaseExpiresAt?: Timestamp;
  nextAttemptAt?: Timestamp;
}

export interface ClaimedReconciliationJob extends StoredReconciliationJob {
  leaseToken: string;
}

export interface JobAdvance {
  phase?: ReconciliationJobPhase;
  productCursor?: string | null;
  pendingProductId?: string | null;
  fullInitialized?: boolean;
  metricsProcessedDelta?: number;
  productsProcessedDelta?: number;
  stockVarianceDelta?: number;
  shiftsProcessedDelta?: number;
  shiftVarianceDelta?: number;
}

interface SaleMovement {
  productId: string;
  quantityDelta: number;
  lineCount: number;
}

export interface SaleReceiptRegistration {
  task?: ReconciliationTaskPayload;
  invalidLineCount: number;
}

export interface DiscoveryPageResult {
  tenantTasks: ReconciliationTaskPayload[];
  continuation?: TenantDiscoveryTaskPayload;
}

function jobRef(
  db: Firestore,
  tenantId: string,
  jobId: string
): DocumentReference<DocumentData> {
  return db.collection("tenants").doc(tenantId).collection("reconciliation_jobs").doc(jobId);
}

function nonNegativeInteger(value: unknown): number {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : 0;
}

function requireStringField(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("data-loss", `Reconciliation job ${field} is invalid.`);
  }
  return value;
}

function parseJob(tenantId: string, jobId: string, data: DocumentData): StoredReconciliationJob {
  const source = data.source;
  if (
    source !== "manual" && source !== "sale_trigger" && source !== "nightly" &&
    source !== "weekly" && source !== "monthly"
  ) {
    throw new HttpsError("data-loss", `Reconciliation job ${jobId} has an invalid source.`);
  }
  const mode = data.mode;
  if (mode !== "incremental" && mode !== "full") {
    throw new HttpsError("data-loss", `Reconciliation job ${jobId} has an invalid mode.`);
  }
  const checkpointKind = data.checkpointKind;
  if (
    checkpointKind !== "none" && checkpointKind !== "weekly" &&
    checkpointKind !== "monthly" && checkpointKind !== "manual"
  ) {
    throw new HttpsError("data-loss", `Reconciliation job ${jobId} has an invalid checkpoint kind.`);
  }
  const status = data.status;
  if (
    status !== "queued" && status !== "running" && status !== "failed" &&
    status !== "completed" && status !== "quarantined"
  ) {
    throw new HttpsError("data-loss", `Reconciliation job ${jobId} has an invalid status.`);
  }
  const phase = data.phase;
  if (phase !== "metrics" && phase !== "stock" && phase !== "shifts" && phase !== "finalize") {
    throw new HttpsError("data-loss", `Reconciliation job ${jobId} has an invalid phase.`);
  }
  return {
    tenantId,
    jobId,
    source,
    sourceKey: requireStringField(data.sourceKey, "sourceKey"),
    mode,
    checkpointKind,
    checkpointKey: requireStringField(data.checkpointKey, "checkpointKey"),
    localDate: requireStringField(data.localDate, "localDate"),
    status,
    phase,
    generation: nonNegativeInteger(data.generation),
    revision: nonNegativeInteger(data.revision),
    attemptCount: nonNegativeInteger(data.attemptCount),
    consecutiveFailureCount: nonNegativeInteger(data.consecutiveFailureCount),
    rerunRequested: data.rerunRequested === true,
    fullInitialized: data.fullInitialized === true,
    metricsProcessed: nonNegativeInteger(data.metricsProcessed),
    productsProcessed: nonNegativeInteger(data.productsProcessed),
    stockVarianceCount: nonNegativeInteger(data.stockVarianceCount),
    shiftsProcessed: nonNegativeInteger(data.shiftsProcessed),
    shiftVarianceCount: nonNegativeInteger(data.shiftVarianceCount),
    ...(typeof data.productCursor === "string" ? {productCursor: data.productCursor} : {}),
    ...(typeof data.pendingProductId === "string" ? {
      pendingProductId: data.pendingProductId,
    } : {}),
    ...(typeof data.leaseToken === "string" ? {leaseToken: data.leaseToken} : {}),
    ...(data.leaseExpiresAt instanceof Timestamp ? {leaseExpiresAt: data.leaseExpiresAt} : {}),
    ...(data.nextAttemptAt instanceof Timestamp ? {nextAttemptAt: data.nextAttemptAt} : {}),
  };
}

function initialJobData(input: {
  tenantId: string;
  source: StoredReconciliationJob["source"];
  sourceKey: string;
  mode: ReconciliationMode;
  checkpointKind: ReconciliationCheckpointKind;
  checkpointKey: string;
  localDate: string;
  requestedBy: string;
  requestId?: string;
}): DocumentData {
  return {
    tenantId: input.tenantId,
    source: input.source,
    sourceKey: input.sourceKey,
    mode: input.mode,
    checkpointKind: input.checkpointKind,
    checkpointKey: input.checkpointKey,
    localDate: input.localDate,
    requestedBy: input.requestedBy,
    ...(input.requestId ? {requestId: input.requestId} : {}),
    status: "queued",
    phase: "metrics",
    generation: 0,
    revision: 0,
    attemptCount: 0,
    consecutiveFailureCount: 0,
    rerunRequested: false,
    fullInitialized: input.mode !== "full",
    metricsProcessed: 0,
    productsProcessed: 0,
    stockVarianceCount: 0,
    shiftsProcessed: 0,
    shiftVarianceCount: 0,
    nextAttemptAt: Timestamp.now(),
    authority: "canonical_tenant_data",
    mutatesStock: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

export function createManualJobInTransaction(
  db: Firestore,
  transaction: Transaction,
  input: {
    tenantId: string;
    jobId: string;
    actorUid: string;
    requestId: string;
    mode: ReconciliationMode;
    localDate: string;
  }
): ReconciliationTaskPayload {
  const ref = jobRef(db, input.tenantId, input.jobId);
  transaction.create(ref, initialJobData({
    tenantId: input.tenantId,
    source: "manual",
    sourceKey: `${input.actorUid}:${input.requestId}`,
    mode: input.mode,
    checkpointKind: input.mode === "full" ? "manual" : "none",
    checkpointKey: input.jobId,
    localDate: input.localDate,
    requestedBy: input.actorUid,
    requestId: input.requestId,
  }));
  return {tenantId: input.tenantId, jobId: input.jobId, generation: 0, revision: 0};
}

function saleMovements(items: unknown): {movements: SaleMovement[]; invalidLineCount: number} {
  if (!Array.isArray(items)) return {movements: [], invalidLineCount: 1};
  const combined = new Map<string, {quantity: number; lines: number}>();
  let invalidLineCount = 0;
  for (const item of items.slice(0, 100)) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      invalidLineCount += 1;
      continue;
    }
    const line = item as Record<string, unknown>;
    if (
      typeof line.productId !== "string" || line.productId.length === 0 ||
      line.productId.length > 128 || line.productId.includes("/") ||
      !Number.isSafeInteger(line.quantity) || (line.quantity as number) <= 0
    ) {
      invalidLineCount += 1;
      continue;
    }
    const current = combined.get(line.productId) ?? {quantity: 0, lines: 0};
    const quantity = current.quantity + (line.quantity as number);
    if (!Number.isSafeInteger(quantity)) {
      invalidLineCount += 1;
      continue;
    }
    combined.set(line.productId, {quantity, lines: current.lines + 1});
  }
  if (items.length > 100) invalidLineCount += items.length - 100;
  return {
    movements: [...combined.entries()].map(([productId, value]) => ({
      productId,
      quantityDelta: -value.quantity,
      lineCount: value.lines,
    })),
    invalidLineCount,
  };
}

/**
 * Merges the dirty date and five-minute job with deterministic sale movements.
 * Replays overwrite only the trigger-owned deterministic movement documents.
 */
export interface SaleTriggerJobFields {
  /**
   * Written when no job exists for this five-minute bucket yet.
   *
   * It must never contain a `FieldValue.delete()` sentinel. Firestore rejects
   * one outright in `create()` and in `set()` without `{merge: true}`, and a
   * brand-new job has no cursor to clear in the first place.
   */
  create: DocumentData;

  /** Written when one does. This is the only branch that may clear a cursor. */
  update: DocumentData;
}

/**
 * The two payloads the sale trigger writes for a bucket's reconciliation job.
 *
 * They are built together and returned separately because they are **not** the
 * same document. Sharing one object between the create and the update is what
 * broke this trigger for every first sale of a bucket: the requeue branch clears
 * `productCursor` and `pendingProductId` with `FieldValue.delete()`, which is
 * legal in `update()` and rejected in `create()`. The failure surfaced only
 * against a real Firestore, because a sentinel is an ordinary object until the
 * write is serialized.
 */
export function saleTriggerJobFields(input: {
  tenantId: string;
  bucket: number;
  businessDate: string;
  decision: DirtyJobDecision;
}): SaleTriggerJobFields {
  const {decision} = input;
  const common: DocumentData = {
    tenantId: input.tenantId,
    source: "sale_trigger",
    sourceKey: `${input.bucket}`,
    mode: "incremental",
    checkpointKind: "none",
    checkpointKey: `${input.bucket}`,
    localDate: input.businessDate,
    requestedBy: "system:sale_trigger",
    status: decision.status,
    phase: decision.phase,
    generation: decision.generation,
    revision: decision.revision,
    rerunRequested: decision.rerunRequested,
    fullInitialized: true,
    nextAttemptAt: Timestamp.now(),
    authority: "canonical_tenant_data",
    mutatesStock: false,
    updatedAt: FieldValue.serverTimestamp(),
  };
  return {
    create: {
      ...common,
      attemptCount: 0,
      consecutiveFailureCount: 0,
      metricsProcessed: 0,
      productsProcessed: 0,
      stockVarianceCount: 0,
      shiftsProcessed: 0,
      shiftVarianceCount: 0,
      createdAt: FieldValue.serverTimestamp(),
    },
    update: {
      ...common,
      // A job returning to `queued` starts its phases again, so any cursor a
      // previous pass left behind describes work this pass has not done.
      ...(decision.status === "queued" ? {
        productCursor: FieldValue.delete(),
        pendingProductId: FieldValue.delete(),
        consecutiveFailureCount: 0,
      } : {}),
    },
  };
}

export async function registerSaleReceipt(
  db: Firestore,
  input: {
    tenantId: string;
    saleId: string;
    businessDate: string;
    receivedAt: Timestamp;
    saleData: DocumentData;
  }
): Promise<SaleReceiptRegistration> {
  const bucket = fiveMinuteBucket(input.receivedAt.toDate());
  const jobId = `dirty_${bucket}`;
  const ref = jobRef(db, input.tenantId, jobId);
  const tenantRef = db.collection("tenants").doc(input.tenantId);
  const dirtyRef = tenantRef.collection("reconciliation_dirty_days").doc(input.businessDate);
  const receiptRef = tenantRef.collection("reconciliation_sale_receipts").doc(input.saleId);
  const {movements, invalidLineCount} = saleMovements(input.saleData.items);

  return db.runTransaction(async (transaction) => {
    const [jobSnapshot, dirtySnapshot, receiptSnapshot] = await transaction.getAll(
      ref,
      dirtyRef,
      receiptRef
    );
    if (receiptSnapshot.exists) {
      if (
        receiptSnapshot.get("tenantId") !== input.tenantId ||
        receiptSnapshot.get("businessDate") !== input.businessDate ||
        receiptSnapshot.get("jobId") !== jobId
      ) {
        throw new HttpsError("already-exists", "The sale receipt identity is inconsistent.");
      }
      const generation = nonNegativeInteger(receiptSnapshot.get("generation"));
      const revision = nonNegativeInteger(receiptSnapshot.get("revision"));
      return {
        task: {tenantId: input.tenantId, jobId, generation, revision},
        invalidLineCount: nonNegativeInteger(receiptSnapshot.get("invalidLineCount")),
      };
    }
    let existing: DirtyJobInput | undefined;
    if (jobSnapshot.exists) {
      const job = parseJob(input.tenantId, jobId, jobSnapshot.data() ?? {});
      if (job.source !== "sale_trigger" || job.sourceKey !== `${bucket}`) {
        throw new HttpsError("already-exists", "The dirty bucket belongs to another source.");
      }
      existing = {
        status: job.status,
        phase: job.phase,
        generation: job.generation,
        revision: job.revision,
        rerunRequested: job.rerunRequested,
      };
    }
    const decision = mergeDirtyJob(existing);
    const dirtyRevision = nonNegativeInteger(dirtySnapshot.get("revision")) + 1;
    const dirtyData: DocumentData = {
      tenantId: input.tenantId,
      businessDate: input.businessDate,
      status: "dirty",
      revision: dirtyRevision,
      lastSaleId: input.saleId,
      lastReceiptAt: input.receivedAt,
      saleReceiptCount: FieldValue.increment(1),
      invalidLineCount: FieldValue.increment(invalidLineCount),
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (!dirtySnapshot.exists) dirtyData.createdAt = FieldValue.serverTimestamp();
    transaction.set(dirtyRef, dirtyData, {merge: true});

    const jobFields = saleTriggerJobFields({
      tenantId: input.tenantId,
      bucket,
      businessDate: input.businessDate,
      decision,
    });
    if (jobSnapshot.exists) {
      transaction.update(ref, jobFields.update);
    } else {
      transaction.create(ref, jobFields.create);
    }

    for (const movement of movements) {
      const movementId = `sale_${input.saleId.length <= 120 ?
        input.saleId : reconciliationJobId("sale", input.saleId).slice(3)}`;
      transaction.set(
        tenantRef.collection("products").doc(movement.productId)
          .collection("stock_movements").doc(movementId),
        {
          movementId,
          tenantId: input.tenantId,
          productId: movement.productId,
          sourceType: "sale",
          sourceId: input.saleId,
          quantityDelta: movement.quantityDelta,
          lineCount: movement.lineCount,
          occurredAt: input.receivedAt,
          recordedAt: FieldValue.serverTimestamp(),
          createdAt: FieldValue.serverTimestamp(),
        },
        {merge: false}
      );
    }
    if (invalidLineCount > 0) {
      const anomalyId = `sale_${reconciliationJobId("sale-anomaly", input.saleId).slice(3)}`;
      transaction.set(tenantRef.collection("reconciliation_anomalies").doc(anomalyId), {
        tenantId: input.tenantId,
        sourceType: "sale",
        sourceId: input.saleId,
        anomalyType: "invalid_sale_lines",
        invalidLineCount,
        observedAt: input.receivedAt,
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: false});
    }
    transaction.create(receiptRef, {
      tenantId: input.tenantId,
      saleId: input.saleId,
      businessDate: input.businessDate,
      jobId,
      generation: decision.generation,
      revision: decision.revision,
      invalidLineCount,
      receivedAt: input.receivedAt,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      ...(decision.enqueue ? {
        task: {
          tenantId: input.tenantId,
          jobId,
          generation: decision.generation,
          revision: decision.revision,
        },
      } : {}),
      invalidLineCount,
    };
  });
}

export async function claimReconciliationJob(
  db: Firestore,
  payload: ReconciliationTaskPayload,
  now = Timestamp.now()
): Promise<ClaimedReconciliationJob | undefined> {
  const ref = jobRef(db, payload.tenantId, payload.jobId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return undefined;
    const job = parseJob(payload.tenantId, payload.jobId, snapshot.data() ?? {});
    if (job.generation !== payload.generation || job.revision !== payload.revision) {
      return undefined;
    }
    if (job.status === "completed") return undefined;
    if (job.status === "quarantined") return undefined;
    if (
      job.status === "running" && job.leaseExpiresAt &&
      job.leaseExpiresAt.toMillis() > now.toMillis()
    ) {
      return undefined;
    }
    if (job.nextAttemptAt && job.nextAttemptAt.toMillis() > now.toMillis()) {
      throw new HttpsError("unavailable", "The reconciliation retry backoff is still active.");
    }
    const leaseToken = randomUUID();
    const leaseExpiresAt = Timestamp.fromMillis(now.toMillis() + LEASE_MILLISECONDS);
    transaction.update(ref, {
      status: "running",
      leaseToken,
      leaseExpiresAt,
      attemptCount: job.attemptCount + 1,
      lastAttemptAt: now,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {...job, status: "running", leaseToken, leaseExpiresAt};
  });
}

export async function advanceReconciliationJob(
  db: Firestore,
  job: ClaimedReconciliationJob,
  advance: JobAdvance
): Promise<ReconciliationTaskPayload> {
  const ref = jobRef(db, job.tenantId, job.jobId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new HttpsError("not-found", "Reconciliation job disappeared.");
    const current = parseJob(job.tenantId, job.jobId, snapshot.data() ?? {});
    if (
      current.generation !== job.generation || current.revision !== job.revision ||
      current.status !== "running" || current.leaseToken !== job.leaseToken
    ) {
      throw new HttpsError("aborted", "The reconciliation job lease changed.");
    }
    const revision = current.revision + 1;
    const update: DocumentData = {
      status: "queued",
      phase: advance.phase ?? current.phase,
      revision,
      // Every page that finishes is continued now. No phase asks to be picked up
      // later: a stock page that stopped short has a movement backlog waiting, and
      // a product too recently written to compare is deferred and stepped past
      // rather than held. The field is still written rather than cleared for two
      // reasons - a backoff a previous failure left behind must not outlive the
      // attempt that succeeded, and `listRetryableReconciliationTasks` finds a
      // stranded job by filtering on this field, so a queued job without one is
      // invisible to the only sweep that can recover a lost dispatch.
      nextAttemptAt: Timestamp.now(),
      leaseToken: FieldValue.delete(),
      leaseExpiresAt: FieldValue.delete(),
      lastErrorCode: FieldValue.delete(),
      consecutiveFailureCount: 0,
      updatedAt: FieldValue.serverTimestamp(),
      metricsProcessed: current.metricsProcessed + (advance.metricsProcessedDelta ?? 0),
      productsProcessed: current.productsProcessed + (advance.productsProcessedDelta ?? 0),
      stockVarianceCount: current.stockVarianceCount + (advance.stockVarianceDelta ?? 0),
      shiftsProcessed: current.shiftsProcessed + (advance.shiftsProcessedDelta ?? 0),
      shiftVarianceCount: current.shiftVarianceCount + (advance.shiftVarianceDelta ?? 0),
    };
    if (advance.productCursor !== undefined) {
      update.productCursor = advance.productCursor === null ? FieldValue.delete() : advance.productCursor;
    }
    if (advance.pendingProductId !== undefined) {
      update.pendingProductId = advance.pendingProductId === null ?
        FieldValue.delete() : advance.pendingProductId;
    }
    if (advance.fullInitialized !== undefined) update.fullInitialized = advance.fullInitialized;
    transaction.update(ref, update);
    return {tenantId: job.tenantId, jobId: job.jobId, generation: current.generation, revision};
  });
}

export async function finalizeReconciliationJob(
  db: Firestore,
  job: ClaimedReconciliationJob
): Promise<ReconciliationTaskPayload | undefined> {
  const ref = jobRef(db, job.tenantId, job.jobId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new HttpsError("not-found", "Reconciliation job disappeared.");
    const current = parseJob(job.tenantId, job.jobId, snapshot.data() ?? {});
    if (
      current.generation !== job.generation || current.revision !== job.revision ||
      current.status !== "running" || current.leaseToken !== job.leaseToken
    ) {
      throw new HttpsError("aborted", "The reconciliation job lease changed.");
    }
    if (current.rerunRequested) {
      const generation = current.generation + 1;
      const revision = current.revision + 1;
      transaction.update(ref, {
        status: "queued",
        phase: "metrics",
        generation,
        revision,
        rerunRequested: false,
        productCursor: FieldValue.delete(),
        pendingProductId: FieldValue.delete(),
        leaseToken: FieldValue.delete(),
        leaseExpiresAt: FieldValue.delete(),
        nextAttemptAt: Timestamp.now(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {tenantId: job.tenantId, jobId: job.jobId, generation, revision};
    }
    transaction.update(ref, {
      status: "completed",
      phase: "finalize",
      leaseToken: FieldValue.delete(),
      leaseExpiresAt: FieldValue.delete(),
      nextAttemptAt: FieldValue.delete(),
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return undefined;
  });
}

export async function recordReconciliationFailure(
  db: Firestore,
  job: ClaimedReconciliationJob,
  error: unknown
): Promise<void> {
  const ref = jobRef(db, job.tenantId, job.jobId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return;
    const current = parseJob(job.tenantId, job.jobId, snapshot.data() ?? {});
    if (
      current.generation !== job.generation || current.revision !== job.revision ||
      current.leaseToken !== job.leaseToken
    ) return;
    const consecutiveFailureCount = current.consecutiveFailureCount + 1;
    const exponent = Math.min(Math.max(consecutiveFailureCount - 1, 0), 8);
    const delayMilliseconds = Math.min(60 * 60 * 1000, 15_000 * (2 ** exponent));
    const quarantined = consecutiveFailureCount >= 8;
    transaction.update(ref, {
      status: quarantined ? "quarantined" : "failed",
      consecutiveFailureCount,
      lastErrorCode: safeErrorCode(error),
      lastFailedAt: FieldValue.serverTimestamp(),
      nextAttemptAt: quarantined ?
        FieldValue.delete() : Timestamp.fromMillis(Date.now() + delayMilliseconds),
      leaseToken: FieldValue.delete(),
      leaseExpiresAt: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (quarantined) {
      transaction.set(db.collection("platform_alerts")
        .doc(`reconciliation_${job.tenantId}_${job.jobId}`), {
        type: "tenant_reconciliation_quarantined",
        severity: "critical",
        tenantId: job.tenantId,
        jobId: job.jobId,
        errorCode: safeErrorCode(error),
        consecutiveFailureCount,
        notificationStatus: "pending",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });
}

function scheduledJobDefinition(
  tenantId: string,
  kind: ReconciliationSweepKind,
  localDate: string
): {
  jobId: string;
  data: DocumentData;
} {
  const sourceKey = `${kind}:${localDate}`;
  const jobId = reconciliationJobId(kind, sourceKey);
  const mode: ReconciliationMode = kind === "monthly" ? "full" : "incremental";
  const checkpointKind: ReconciliationCheckpointKind = kind === "weekly" ?
    "weekly" : kind === "monthly" ? "monthly" : "none";
  const checkpointKey = kind === "weekly" ? isoWeekKey(localDate) :
    kind === "monthly" ? localDate.slice(0, 7) : localDate;
  return {
    jobId,
    data: initialJobData({
      tenantId,
      source: kind,
      sourceKey,
      mode,
      checkpointKind,
      checkpointKey,
      localDate,
      requestedBy: `system:${kind}`,
    }),
  };
}

async function ensureScheduledTenantJob(
  db: Firestore,
  tenantId: string,
  kind: ReconciliationSweepKind,
  localDate: string
): Promise<ReconciliationTaskPayload | undefined> {
  const definition = scheduledJobDefinition(tenantId, kind, localDate);
  const ref = jobRef(db, tenantId, definition.jobId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      transaction.create(ref, definition.data);
      return {tenantId, jobId: definition.jobId, generation: 0, revision: 0};
    }
    const existing = parseJob(tenantId, definition.jobId, snapshot.data() ?? {});
    if (existing.source !== kind || existing.sourceKey !== `${kind}:${localDate}`) {
      throw new HttpsError("already-exists", "Scheduled reconciliation identity collision.");
    }
    if (
      existing.status === "completed" || existing.status === "running" ||
      existing.status === "quarantined"
    ) return undefined;
    return {
      tenantId,
      jobId: definition.jobId,
      generation: existing.generation,
      revision: existing.revision,
    };
  });
}

export async function ensureSweep(
  db: Firestore,
  kind: ReconciliationSweepKind,
  localDate: string
): Promise<TenantDiscoveryTaskPayload> {
  const runId = sweepRunId(kind, localDate);
  const ref = db.collection("platform_reconciliation_sweeps").doc(runId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      transaction.create(ref, {
        runId,
        kind,
        localDate,
        status: "running",
        pagesProcessed: 0,
        tenantsScanned: 0,
        tenantJobsCreated: 0,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }
    const data = snapshot.data() ?? {};
    if (data.kind !== kind || data.localDate !== localDate) {
      throw new HttpsError("already-exists", "Reconciliation sweep identity collision.");
    }
  });
  return {runId, kind, localDate, page: 0};
}

export async function processTenantDiscoveryPage(
  db: Firestore,
  payload: TenantDiscoveryTaskPayload
): Promise<DiscoveryPageResult> {
  let query = db.collection("tenants")
    .where("status", "==", "active")
    .orderBy(FieldPath.documentId())
    .limit(TENANT_DISCOVERY_PAGE_SIZE);
  if (payload.cursor) query = query.startAfter(payload.cursor);
  const snapshot = await query.get();
  const localDay = Number(payload.localDate.slice(8, 10));
  const eligible = payload.kind === "monthly" ?
    snapshot.docs.filter((document) => monthlyShardDay(document.id) === localDay) :
    snapshot.docs;
  const tenantTasks = (await Promise.all(eligible.map((document) =>
    ensureScheduledTenantJob(db, document.id, payload.kind, payload.localDate)
  ))).filter((task): task is ReconciliationTaskPayload => task !== undefined);
  const last = snapshot.docs.length > 0 ? snapshot.docs[snapshot.docs.length - 1] : undefined;
  const hasMore = snapshot.size === TENANT_DISCOVERY_PAGE_SIZE && last !== undefined;
  const continuation = hasMore ? {
    ...payload,
    page: payload.page + 1,
    cursor: last.id,
  } : undefined;
  const sweepRef = db.collection("platform_reconciliation_sweeps").doc(payload.runId);
  const pageRef = sweepRef.collection("pages").doc(`${payload.page}`.padStart(8, "0"));
  await db.runTransaction(async (transaction) => {
    const [sweepSnapshot, pageSnapshot] = await transaction.getAll(sweepRef, pageRef);
    if (!sweepSnapshot.exists) {
      throw new HttpsError("not-found", "The reconciliation sweep disappeared.");
    }
    if (pageSnapshot.exists) return;
    transaction.create(pageRef, {
      runId: payload.runId,
      page: payload.page,
      inputCursor: payload.cursor ?? null,
      outputCursor: last?.id ?? payload.cursor ?? null,
      tenantsScanned: snapshot.size,
      tenantsEligible: eligible.length,
      tenantTasksReturned: tenantTasks.length,
      hasMore,
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.update(sweepRef, {
      status: hasMore ? "running" : "completed",
      pagesProcessed: FieldValue.increment(1),
      tenantsScanned: FieldValue.increment(snapshot.size),
      tenantJobsCreated: FieldValue.increment(tenantTasks.length),
      tenantsEligible: FieldValue.increment(eligible.length),
      cursor: last?.id ?? payload.cursor ?? null,
      ...(hasMore ? {} : {completedAt: FieldValue.serverTimestamp()}),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {tenantTasks, ...(continuation ? {continuation} : {})};
}

export async function listRetryableReconciliationTasks(
  db: Firestore,
  now = Timestamp.now()
): Promise<ReconciliationTaskPayload[]> {
  const [readySnapshot, expiredLeaseSnapshot] = await Promise.all([
    db.collectionGroup("reconciliation_jobs")
      .where("status", "in", ["queued", "failed"])
      .where("nextAttemptAt", "<=", now)
      .orderBy("nextAttemptAt", "asc")
      .orderBy(FieldPath.documentId(), "asc")
      .limit(RETRY_PAGE_SIZE)
      .get(),
    db.collectionGroup("reconciliation_jobs")
      .where("status", "==", "running")
      .where("leaseExpiresAt", "<=", now)
      .orderBy("leaseExpiresAt", "asc")
      .orderBy(FieldPath.documentId(), "asc")
      .limit(RETRY_PAGE_SIZE)
      .get(),
  ]);
  const candidates = [
    ...readySnapshot.docs.map((document) => ({
      document,
      dueAt: document.get("nextAttemptAt") instanceof Timestamp ?
        (document.get("nextAttemptAt") as Timestamp).toMillis() : 0,
    })),
    ...expiredLeaseSnapshot.docs.map((document) => ({
      document,
      dueAt: document.get("leaseExpiresAt") instanceof Timestamp ?
        (document.get("leaseExpiresAt") as Timestamp).toMillis() : 0,
    })),
  ].sort((left, right) => left.dueAt - right.dueAt ||
    left.document.ref.path.localeCompare(right.document.ref.path)
  ).slice(0, RETRY_PAGE_SIZE);
  const tasks: ReconciliationTaskPayload[] = [];
  const quarantines: Array<Promise<unknown>> = [];
  for (const {document} of candidates) {
    const segments = document.ref.path.split("/");
    if (
      segments.length !== 4 || segments[0] !== "tenants" ||
      segments[2] !== "reconciliation_jobs"
    ) continue;
    try {
      const job = parseJob(segments[1], document.id, document.data());
      tasks.push({
        tenantId: job.tenantId,
        jobId: job.jobId,
        generation: job.generation,
        revision: job.revision,
      });
    } catch {
      // Malformed jobs are not activated. Operators can inspect the anomaly.
      quarantines.push(document.ref.set({
        status: "quarantined",
        lastErrorCode: "malformed_reconciliation_job",
        nextAttemptAt: FieldValue.delete(),
        leaseToken: FieldValue.delete(),
        leaseExpiresAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}));
    }
  }
  await Promise.all(quarantines);
  return tasks;
}

export function reconciliationJobDocument(
  db: Firestore,
  tenantId: string,
  jobId: string
): DocumentReference<DocumentData> {
  return jobRef(db, tenantId, jobId);
}
