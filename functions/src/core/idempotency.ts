import {createHash} from "node:crypto";
import {
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

interface IdempotencyRecord<TResult> {
  actorUid: string;
  operation: string;
  scope: string;
  requestId: string;
  inputHash: string;
  status: "completed";
  result: TResult;
}

export interface IdempotentTransactionOptions<TInput> {
  actorUid: string;
  operation: string;
  tenantId?: string;
  requestId: string;
  input: TInput;
}

function stableValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, item]) => [key, stableValue(item)])
    );
  }
  return value;
}

export function fingerprintPayload(value: unknown): string {
  const serialized = JSON.stringify(stableValue(value)) ?? "undefined";
  return createHash("sha256").update(serialized).digest("hex");
}

export function buildIdempotencyIdentity(
  actorUid: string,
  operation: string,
  tenantId: string | undefined,
  requestId: string
): {documentId: string; scope: string} {
  const scope = tenantId ? `tenant:${tenantId}` : "global";
  const rawKey = `${actorUid}\u0000${operation}\u0000${scope}\u0000${requestId}`;
  return {
    documentId: createHash("sha256").update(rawKey).digest("hex"),
    scope,
  };
}

/**
 * Runs Firestore-only work and stores its response in the same transaction.
 * The callback must not perform Auth, HTTP, task-queue, or other external side effects.
 */
export async function runIdempotentFirestoreTransaction<TInput, TResult>(
  db: Firestore,
  options: IdempotentTransactionOptions<TInput>,
  handler: (transaction: Transaction) => Promise<TResult>
): Promise<TResult> {
  const identity = buildIdempotencyIdentity(
    options.actorUid,
    options.operation,
    options.tenantId,
    options.requestId
  );
  const inputHash = fingerprintPayload(options.input);
  const recordRef = db.collection("operation_idempotency").doc(identity.documentId);

  return db.runTransaction(async (transaction) => {
    const existingSnapshot = await transaction.get(recordRef);
    if (existingSnapshot.exists) {
      const existing = existingSnapshot.data() as IdempotencyRecord<TResult>;
      if (existing.inputHash !== inputHash) {
        throw new HttpsError(
          "already-exists",
          "requestId was already used with different input."
        );
      }
      if (existing.status !== "completed") {
        throw new HttpsError("aborted", "The operation is already in progress.");
      }
      return existing.result;
    }

    const result = await handler(transaction);
    transaction.create(recordRef, {
      actorUid: options.actorUid,
      operation: options.operation,
      scope: identity.scope,
      requestId: options.requestId,
      inputHash,
      status: "completed",
      result,
      createdAt: FieldValue.serverTimestamp(),
      completedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000),
    });
    return result;
  });
}
