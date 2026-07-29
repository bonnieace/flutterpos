import {randomUUID} from "node:crypto";
import {getAuth} from "firebase-admin/auth";
import {
  DocumentData,
  FieldPath,
  FieldValue,
  Firestore,
  getFirestore,
  QueryDocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  GlobalUserStatusInput,
  GlobalUserStatusOperation,
  runGlobalUserStatusSaga,
} from "./globalStatusCore";
import {createGlobalStatusSagaAdapter} from "./globalStatusStore";

const RETRY_LEASE_MILLISECONDS = 10 * 60 * 1000;
const MAX_QUERY_DOCUMENTS = 200;
const RETRYABLE_STATUSES = new Set(["pending", "partially_failed"]);
const STEP_STATUSES = new Set(["pending", "completed", "not_applicable"]);
const CLAIM_STATUSES = new Set([
  "pending",
  "completed",
  "not_applicable",
  "not_restored",
]);

export interface RetryableGlobalStatusWork {
  input: GlobalUserStatusInput;
  retryLeaseOwner: string;
}

export interface RetryGlobalStatusDependencies {
  listRetryable(limit: number): Promise<readonly RetryableGlobalStatusWork[]>;
  resume(work: RetryableGlobalStatusWork): Promise<GlobalUserStatusOperation>;
}

export interface RetryGlobalStatusSummary {
  attempted: number;
  completed: number;
  partiallyFailed: number;
}

function requireStoredString(
  data: DocumentData,
  field: string,
  options: {minLength?: number; maxLength?: number} = {}
): string {
  const value = data[field];
  const minLength = options.minLength ?? 1;
  const maxLength = options.maxLength ?? 512;
  if (
    typeof value !== "string" ||
    value.length < minLength ||
    value.length > maxLength
  ) {
    throw new Error(`invalid_${field}`);
  }
  return value;
}

function requireStepStatus(data: DocumentData, field: string): string {
  const value = data[field];
  if (typeof value !== "string" || !STEP_STATUSES.has(value)) {
    throw new Error(`invalid_${field}`);
  }
  return value;
}

/**
 * Treat operation documents as untrusted persisted input. A malformed target
 * status must never fall through to the activation branch of the saga.
 */
export function parseRetryableGlobalStatusOperation(
  documentId: string,
  data: DocumentData
): GlobalUserStatusInput {
  if (!RETRYABLE_STATUSES.has(data.status)) throw new Error("invalid_status");
  if (data.targetStatus !== "active" && data.targetStatus !== "disabled") {
    throw new Error("invalid_targetStatus");
  }
  const requestId = requireStoredString(data, "requestId", {maxLength: 200});
  if (requestId !== documentId) throw new Error("request_id_mismatch");
  const attemptCount = data.attemptCount;
  if (!Number.isSafeInteger(attemptCount) || attemptCount < 1) {
    throw new Error("invalid_attemptCount");
  }

  const firestoreStatus = requireStepStatus(data, "firestoreStatus");
  const impactStatus = requireStepStatus(data, "impactStatus");
  requireStepStatus(data, "authStatus");
  requireStepStatus(data, "tokenStatus");
  if (typeof data.claimStatus !== "string" || !CLAIM_STATUSES.has(data.claimStatus)) {
    throw new Error("invalid_claimStatus");
  }

  if (data.targetStatus === "disabled") {
    if (
      firestoreStatus !== "completed" ||
      impactStatus === "not_applicable" ||
      data.claimStatus === "not_applicable" ||
      data.claimStatus === "not_restored"
    ) {
      throw new Error("invalid_disable_phases");
    }
  } else if (
    impactStatus !== "not_applicable" ||
    data.claimStatus !== "not_restored" ||
    firestoreStatus === "not_applicable"
  ) {
    throw new Error("invalid_activation_phases");
  }

  return {
    uid: requireStoredString(data, "uid", {maxLength: 128}),
    targetStatus: data.targetStatus,
    requestedBy: requireStoredString(data, "requestedBy", {maxLength: 128}),
    reason: requireStoredString(data, "reason", {minLength: 3, maxLength: 1000}),
    requestId,
  };
}

function timestampMilliseconds(value: unknown): number | undefined {
  if (value instanceof Timestamp) return value.toMillis();
  if (
    value &&
    typeof value === "object" &&
    "toMillis" in value &&
    typeof (value as {toMillis?: unknown}).toMillis === "function"
  ) {
    const milliseconds = (value as {toMillis(): unknown}).toMillis();
    return typeof milliseconds === "number" && Number.isFinite(milliseconds) ?
      milliseconds : undefined;
  }
  return undefined;
}

async function claimRetryableOperation(
  db: Firestore,
  document: QueryDocumentSnapshot,
  leaseOwner: string,
  nowMilliseconds: number
): Promise<RetryableGlobalStatusWork | undefined> {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(document.ref);
    if (!snapshot.exists) return undefined;
    const data = snapshot.data() ?? {};
    let input: GlobalUserStatusInput;
    try {
      input = parseRetryableGlobalStatusOperation(snapshot.id, data);
    } catch (error) {
      const reason = error instanceof Error ? error.message : "invalid_operation";
      transaction.update(document.ref, {
        status: "quarantined",
        lastErrorCode: `lifecycle/${reason}`.slice(0, 128),
        nextAttemptAt: FieldValue.delete(),
        retryLeaseOwner: FieldValue.delete(),
        retryLeaseExpiresAt: FieldValue.delete(),
        quarantinedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return undefined;
    }

    const dueAt = timestampMilliseconds(data.nextAttemptAt);
    if (dueAt === undefined || dueAt > nowMilliseconds) return undefined;
    const leaseExpiresAt = timestampMilliseconds(data.retryLeaseExpiresAt);
    if (leaseExpiresAt !== undefined && leaseExpiresAt > nowMilliseconds) {
      return undefined;
    }

    transaction.update(document.ref, {
      retryLeaseOwner: leaseOwner,
      retryLeaseExpiresAt: Timestamp.fromMillis(
        nowMilliseconds + RETRY_LEASE_MILLISECONDS
      ),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {input, retryLeaseOwner: leaseOwner};
  });
}

export async function retryGlobalUserStatusOperationsCore(
  dependencies: RetryGlobalStatusDependencies,
  limit = 20
): Promise<RetryGlobalStatusSummary> {
  const inputs = await dependencies.listRetryable(limit);
  let completed = 0;
  let partiallyFailed = 0;
  for (const input of inputs) {
    try {
      const result = await dependencies.resume(input);
      if (result.status === "completed") completed += 1;
      else partiallyFailed += 1;
    } catch {
      // One malformed or concurrently superseded operation must not prevent
      // later durable operations from being retried.
      partiallyFailed += 1;
    }
  }
  return {attempted: inputs.length, completed, partiallyFailed};
}

export const retryGlobalUserStatusOperations = onSchedule({
  schedule: "every 5 minutes",
  timeZone: "Africa/Nairobi",
  maxInstances: 1,
  timeoutSeconds: 540,
}, async () => {
  const firestore = getFirestore();
  const auth = getAuth();
  await retryGlobalUserStatusOperationsCore({
    async listRetryable(limit) {
      const now = Timestamp.now();
      const snapshot = await firestore.collection("platform_user_operations")
        .where("status", "in", ["pending", "partially_failed"])
        .where("nextAttemptAt", "<=", now)
        .orderBy("nextAttemptAt", "asc")
        .orderBy(FieldPath.documentId(), "asc")
        .limit(Math.min(MAX_QUERY_DOCUMENTS, Math.max(limit * 10, limit)))
        .get();
      const claimed: RetryableGlobalStatusWork[] = [];
      for (const document of snapshot.docs) {
        if (claimed.length >= limit) break;
        const work = await claimRetryableOperation(
          firestore,
          document,
          randomUUID(),
          now.toMillis()
        );
        if (work) claimed.push(work);
      }
      return claimed;
    },
    resume(work) {
      return runGlobalUserStatusSaga(
        createGlobalStatusSagaAdapter({
          db: firestore,
          auth,
          internalRetry: true,
          executionLeaseOwner: work.retryLeaseOwner,
        }),
        work.input
      );
    },
  });
});
