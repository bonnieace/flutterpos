import {randomUUID} from "node:crypto";
import {
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

const LEASE_MILLISECONDS = 5 * 60 * 1000;
export const MAX_EMAIL_DELIVERY_ATTEMPTS = 8;

export interface ActionDeliveryIdentity {
  deliveryId: string;
  deliveryType: "account_verification" | "platform_alert";
  targetUid: string;
  recipientHash: string;
  recipientHashKeyVersion: string;
}

export interface ActionDeliveryAttempt {
  leaseId: string;
  attemptNumber: number;
}

export interface ClaimActionDeliveryOptions {
  /** Internal callers may rebind a nonterminal user-scoped delivery after Auth email/key rotation. */
  allowRecipientRebind?: boolean;
}

type AppliedDeliveryWrite = (transaction: Transaction) => void;

function retryDelayMilliseconds(attempt: number): number {
  return Math.min(6 * 60 * 60 * 1000, 30_000 * (2 ** Math.min(attempt - 1, 10)));
}

export async function claimActionDelivery(
  db: Firestore,
  identity: ActionDeliveryIdentity,
  additionalFields: Record<string, unknown> = {},
  options: ClaimActionDeliveryOptions = {}
): Promise<ActionDeliveryAttempt | undefined> {
  const ref = db.collection("email_deliveries").doc(identity.deliveryId);
  const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data() ?? {};
    if ([
      "sent",
      "delivered",
      "suppressed",
      "permanent_failure",
    ].includes(data.status)) return undefined;
    if (snapshot.exists && (
      data.deliveryType !== identity.deliveryType ||
      data.targetUid !== identity.targetUid ||
      (!options.allowRecipientRebind && (
        data.recipientHash !== identity.recipientHash ||
        data.recipientHashKeyVersion !== identity.recipientHashKeyVersion
      ))
    )) throw new Error("Email delivery identity mismatch.");
    if (
      data.status === "processing" &&
      data.leaseExpiresAt instanceof Timestamp &&
      data.leaseExpiresAt.toMillis() > now.toMillis()
    ) return undefined;
    const previousAttempts = Number.isSafeInteger(data.attemptCount) ?
      data.attemptCount as number : 0;
    const attemptNumber = previousAttempts + 1;
    if (attemptNumber > MAX_EMAIL_DELIVERY_ATTEMPTS) {
      transaction.update(ref, {
        status: "permanent_failure",
        retryable: false,
        sendable: false,
        lastErrorCode: "delivery_attempts_exhausted",
        leaseId: FieldValue.delete(),
        leaseExpiresAt: FieldValue.delete(),
        nextAttemptAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return undefined;
    }
    const leaseId = randomUUID();
    transaction.set(ref, {
      ...identity,
      ...additionalFields,
      status: "processing",
      sendable: true,
      retryable: true,
      attemptCount: attemptNumber,
      leaseId,
      leaseExpiresAt: Timestamp.fromMillis(now.toMillis() + LEASE_MILLISECONDS),
      nextAttemptAt: FieldValue.delete(),
      ...(snapshot.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {leaseId, attemptNumber};
  });
}

export async function recordActionDeliverySuppressed(
  db: Firestore,
  identity: ActionDeliveryIdentity,
  additionalFields: Record<string, unknown> = {},
  onApplied?: AppliedDeliveryWrite
): Promise<boolean> {
  const ref = db.collection("email_deliveries").doc(identity.deliveryId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.exists && [
      "sent",
      "delivered",
      "suppressed",
      "permanent_failure",
    ].includes(snapshot.data()?.status)) return false;
    transaction.set(ref, {
      ...identity,
      ...additionalFields,
      status: "suppressed",
      sendable: false,
      retryable: false,
      attemptCount: snapshot.data()?.attemptCount ?? 0,
      ...(snapshot.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    onApplied?.(transaction);
    return true;
  });
}

export async function completeActionDelivery(
  db: Firestore,
  identity: ActionDeliveryIdentity,
  attempt: ActionDeliveryAttempt,
  provider: string,
  providerMessageId: string,
  onApplied?: AppliedDeliveryWrite
): Promise<boolean> {
  const ref = db.collection("email_deliveries").doc(identity.deliveryId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.data()?.leaseId !== attempt.leaseId) return false;
    transaction.update(ref, {
      status: "sent",
      provider,
      providerMessageId,
      retryable: false,
      sentAt: FieldValue.serverTimestamp(),
      leaseId: FieldValue.delete(),
      leaseExpiresAt: FieldValue.delete(),
      nextAttemptAt: FieldValue.delete(),
      lastErrorCode: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    onApplied?.(transaction);
    return true;
  });
}

export async function failActionDelivery(
  db: Firestore,
  identity: ActionDeliveryIdentity,
  attempt: ActionDeliveryAttempt,
  safeCode: string,
  retryable: boolean,
  onApplied?: AppliedDeliveryWrite
): Promise<boolean> {
  const ref = db.collection("email_deliveries").doc(identity.deliveryId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.data()?.leaseId !== attempt.leaseId) return false;
    transaction.update(ref, {
      status: retryable ? "retry_pending" : "permanent_failure",
      retryable,
      sendable: retryable,
      lastErrorCode: safeCode,
      ...(retryable ? {
        nextAttemptAt: Timestamp.fromMillis(
          Date.now() + retryDelayMilliseconds(attempt.attemptNumber)
        ),
      } : {nextAttemptAt: FieldValue.delete()}),
      leaseId: FieldValue.delete(),
      leaseExpiresAt: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    onApplied?.(transaction);
    return true;
  });
}
