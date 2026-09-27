import {createHash} from "node:crypto";
import {Auth, getAuth} from "firebase-admin/auth";
import {
  DocumentReference,
  FieldPath,
  FieldValue,
  Firestore,
  getFirestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {fingerprintPayload} from "../core/idempotency";
import {RootUserRecord} from "../core/model";
import {
  evaluatePlatformEligibility,
  scanPlatformEligibility,
} from "../platform/eligibility";
import {AuthIdentity, resolveOrCreateAuthIdentity} from "./shared";
import {logAbsorbedFailure} from "../core/absorbedFailure";

const ABANDONED_IDENTITY_GRACE_MILLISECONDS = 24 * 60 * 60 * 1000;

export type StaffIdentityOperationStatus =
  | "reserved"
  | "identity_resolved"
  | "completed"
  | "cleanup_pending"
  | "retained"
  | "cleaned";

export interface StaffIdentityReservation<TResult = unknown> {
  operationId: string;
  actorUid: string;
  operation: string;
  tenantId: string;
  requestId: string;
  inputHash: string;
  email: string;
  displayName: string;
  provisionalUid: string;
  status: StaffIdentityOperationStatus;
  identityUid?: string;
  identityOwnedByOperation?: boolean;
  result?: TResult;
  cleanupAfterAt?: unknown;
}

export interface ReserveStaffIdentityOptions<TInput> {
  operationId: string;
  actorUid: string;
  operation: string;
  tenantId: string;
  requestId: string;
  input: TInput;
  email: string;
  displayName: string;
}

interface StoredStaffIdentityOperation<TResult = unknown> {
  operationId?: unknown;
  actorUid?: unknown;
  operation?: unknown;
  tenantId?: unknown;
  requestId?: unknown;
  inputHash?: unknown;
  targetEmail?: unknown;
  requestedDisplayName?: unknown;
  provisionalUid?: unknown;
  status?: unknown;
  identityUid?: unknown;
  identityOwnedByOperation?: unknown;
  result?: TResult;
  cleanupAfterAt?: unknown;
  cleanupRetryAfterAt?: unknown;
}

function operationRef(db: Firestore, operationId: string) {
  return db.collection("staff_identity_operations").doc(operationId);
}

/** Auth UIDs are allocated before Auth creation, making crash recovery unambiguous. */
export function provisionalStaffUid(operationId: string): string {
  const digest = createHash("sha256").update(operationId, "utf8").digest("base64url");
  return `staff_${digest.slice(0, 28)}`;
}

function parseReservation<TResult>(
  data: StoredStaffIdentityOperation<TResult>,
  expected: Omit<ReserveStaffIdentityOptions<unknown>, "input">
): StaffIdentityReservation<TResult> {
  const terminal = ["completed", "retained", "cleaned"].includes(String(data.status));
  if (
    data.operationId !== expected.operationId ||
    data.actorUid !== expected.actorUid ||
    data.operation !== expected.operation ||
    data.tenantId !== expected.tenantId ||
    data.requestId !== expected.requestId ||
    (!terminal && data.targetEmail !== expected.email) ||
    (!terminal && data.requestedDisplayName !== expected.displayName) ||
    typeof data.inputHash !== "string" ||
    typeof data.provisionalUid !== "string" ||
    ![
      "reserved",
      "identity_resolved",
      "completed",
      "cleanup_pending",
      "retained",
      "cleaned",
    ].includes(String(data.status))
  ) {
    throw new HttpsError("failed-precondition", "Staff identity operation state is invalid.");
  }
  return {
    operationId: expected.operationId,
    actorUid: expected.actorUid,
    operation: expected.operation,
    tenantId: expected.tenantId,
    requestId: expected.requestId,
    inputHash: data.inputHash,
    email: expected.email,
    displayName: expected.displayName,
    provisionalUid: data.provisionalUid,
    status: data.status as StaffIdentityOperationStatus,
    ...(typeof data.identityUid === "string" ? {identityUid: data.identityUid} : {}),
    ...(typeof data.identityOwnedByOperation === "boolean" ?
      {identityOwnedByOperation: data.identityOwnedByOperation} : {}),
    ...(data.result !== undefined ? {result: data.result} : {}),
    ...(data.cleanupAfterAt !== undefined ? {cleanupAfterAt: data.cleanupAfterAt} : {}),
  };
}

export async function reserveStaffIdentityOperation<TInput, TResult = unknown>(
  db: Firestore,
  options: ReserveStaffIdentityOptions<TInput>
): Promise<StaffIdentityReservation<TResult>> {
  const inputHash = fingerprintPayload(options.input);
  const ref = operationRef(db, options.operationId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.exists) {
      const existing = parseReservation<TResult>(
        snapshot.data() as StoredStaffIdentityOperation<TResult>,
        options
      );
      if (existing.inputHash !== inputHash) {
        throw new HttpsError(
          "already-exists",
          "requestId was already used with different input."
        );
      }
      return existing;
    }
    const provisionalUid = provisionalStaffUid(options.operationId);
    transaction.create(ref, {
      operationId: options.operationId,
      actorUid: options.actorUid,
      operation: options.operation,
      tenantId: options.tenantId,
      requestId: options.requestId,
      inputHash,
      targetEmail: options.email,
      requestedDisplayName: options.displayName,
      provisionalUid,
      status: "reserved",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      cleanupAfterAt: Timestamp.fromMillis(
        Date.now() + ABANDONED_IDENTITY_GRACE_MILLISECONDS
      ),
    });
    return {
      operationId: options.operationId,
      actorUid: options.actorUid,
      operation: options.operation,
      tenantId: options.tenantId,
      requestId: options.requestId,
      inputHash,
      email: options.email,
      displayName: options.displayName,
      provisionalUid,
      status: "reserved",
    };
  });
}

export async function resolveReservedStaffIdentity(
  db: Firestore,
  reservation: StaffIdentityReservation,
  auth: Auth = getAuth()
): Promise<AuthIdentity> {
  if (reservation.status === "cleaned") {
    throw new HttpsError("failed-precondition", "The provisional identity was cleaned up.");
  }
  if (reservation.status === "retained") {
    throw new HttpsError("failed-precondition", "The provisional identity was retained.");
  }
  const identity = await resolveOrCreateAuthIdentity(
    reservation.email,
    reservation.displayName,
    reservation.provisionalUid,
    auth
  );
  const ref = operationRef(db, reservation.operationId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      throw new HttpsError("failed-precondition", "Staff identity reservation is missing.");
    }
    const current = snapshot.data() as StoredStaffIdentityOperation;
    if (
      current.inputHash !== reservation.inputHash ||
      (typeof current.identityUid === "string" && current.identityUid !== identity.uid)
    ) {
      throw new HttpsError("failed-precondition", "Staff identity reservation changed.");
    }
    if (current.status === "completed") return;
    transaction.update(ref, {
      identityUid: identity.uid,
      identityOwnedByOperation: identity.uid === reservation.provisionalUid,
      status: "identity_resolved",
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return identity;
}

/** Finalizes Firestore membership work atomically with the durable saga result. */
export async function finalizeReservedStaffOperation<TResult>(
  db: Firestore,
  reservation: StaffIdentityReservation<TResult>,
  identity: AuthIdentity,
  handler: (transaction: Transaction) => Promise<TResult>
): Promise<TResult> {
  const ref = operationRef(db, reservation.operationId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      throw new HttpsError("failed-precondition", "Staff identity reservation is missing.");
    }
    const current = snapshot.data() as StoredStaffIdentityOperation<TResult>;
    if (current.inputHash !== reservation.inputHash || current.identityUid !== identity.uid) {
      throw new HttpsError("failed-precondition", "Staff identity reservation changed.");
    }
    if (current.status === "completed") {
      if (current.result === undefined) {
        throw new HttpsError("failed-precondition", "Completed operation has no result.");
      }
      return current.result;
    }
    if (current.status !== "identity_resolved") {
      throw new HttpsError("aborted", "Staff identity operation is not resumable.");
    }
    const result = await handler(transaction);
    transaction.update(ref, {
      status: "completed",
      result,
      targetEmail: FieldValue.delete(),
      requestedDisplayName: FieldValue.delete(),
      cleanupAfterAt: FieldValue.delete(),
      cleanupRetryAfterAt: FieldValue.delete(),
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return result;
  });
}

function authErrorCode(error: unknown): string | undefined {
  return error && typeof error === "object" && "code" in error ?
    String((error as {code?: unknown}).code) : undefined;
}

/**
 * Reclaims only an Auth UID allocated by this operation. The cleanup transition
 * blocks tenant/platform attachment while canonical eligibility is scanned.
 */
export async function cleanupAbandonedStaffIdentity(
  db: Firestore,
  operationId: string,
  auth: Auth = getAuth()
): Promise<"cleaned" | "retained" | "not_due"> {
  const opRef = operationRef(db, operationId);
  const claimed = await db.runTransaction(async (transaction): Promise<
    {outcome: "claimed"; uid: string; userRef: DocumentReference} |
    {outcome: "retained"} |
    undefined
  > => {
    const opSnapshot = await transaction.get(opRef);
    if (!opSnapshot.exists) return undefined;
    const op = opSnapshot.data() as StoredStaffIdentityOperation;
    if (!["reserved", "identity_resolved", "cleanup_pending"].includes(String(op.status))) {
      return undefined;
    }
    const identityUid = typeof op.identityUid === "string" ?
      op.identityUid : op.status === "reserved" && typeof op.provisionalUid === "string" ?
        op.provisionalUid : undefined;
    const identityOwnedByOperation = op.identityOwnedByOperation === true ||
      (op.status === "reserved" && identityUid === op.provisionalUid);
    if (
      !identityOwnedByOperation ||
      typeof identityUid !== "string" ||
      identityUid !== op.provisionalUid
    ) {
      transaction.update(opRef, {
        status: "retained",
        cleanupOutcome: "identity_not_operation_owned",
        targetEmail: FieldValue.delete(),
        requestedDisplayName: FieldValue.delete(),
        cleanupAfterAt: FieldValue.delete(),
        cleanupRetryAfterAt: FieldValue.delete(),
        retainedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {outcome: "retained"};
    }
    if (
      op.status !== "cleanup_pending" &&
      (!(op.cleanupAfterAt instanceof Timestamp) ||
        op.cleanupAfterAt.toMillis() > Date.now())
    ) return undefined;
    const userRef = db.collection("users").doc(identityUid);
    const rootSnapshot = await transaction.get(userRef);
    if (rootSnapshot.exists) {
      const root = rootSnapshot.data() as RootUserRecord;
      if (
        root.accountType !== "tenant_user" ||
        root.identityOrigin !== "staff_invitation" ||
        (root.identityTransition && root.identityTransition !== "cleanup_pending")
      ) {
        transaction.update(opRef, {
          status: "retained",
          cleanupOutcome: "root_identity_not_provisional",
          targetEmail: FieldValue.delete(),
          requestedDisplayName: FieldValue.delete(),
          cleanupAfterAt: FieldValue.delete(),
          cleanupRetryAfterAt: FieldValue.delete(),
          retainedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return {outcome: "retained"};
      }
      transaction.update(userRef, {
        identityTransition: "cleanup_pending",
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      transaction.create(userRef, {
        email: typeof op.targetEmail === "string" ? op.targetEmail : "",
        displayName: typeof op.requestedDisplayName === "string" ?
          op.requestedDisplayName : "",
        accountType: "tenant_user",
        identityOrigin: "staff_invitation",
        identityTransition: "cleanup_pending",
        globalStatus: "active",
        membershipCount: 0,
        ownedTenantCount: 0,
        ownedActiveTenantCount: 0,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.update(opRef, {
      status: "cleanup_pending",
      identityUid,
      identityOwnedByOperation: true,
      cleanupRetryAfterAt: Timestamp.now(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {outcome: "claimed", uid: identityUid, userRef};
  });
  if (!claimed) return "not_due";
  if (claimed.outcome === "retained") return "retained";

  const eligibility = evaluatePlatformEligibility(
    await scanPlatformEligibility(db, claimed.uid)
  );
  if (!eligibility.eligible) {
    await db.runTransaction(async (transaction) => {
      const [opSnapshot, rootSnapshot] = await transaction.getAll(opRef, claimed.userRef);
      if (opSnapshot.data()?.status !== "cleanup_pending") return;
      if (rootSnapshot.data()?.identityTransition === "cleanup_pending") {
        transaction.update(claimed.userRef, {
          identityTransition: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      transaction.update(opRef, {
        status: "retained",
        cleanupOutcome: "canonical_evidence_present",
        canonicalBlockerCount: eligibility.blockers.length,
        targetEmail: FieldValue.delete(),
        requestedDisplayName: FieldValue.delete(),
        cleanupAfterAt: FieldValue.delete(),
        cleanupRetryAfterAt: FieldValue.delete(),
        retainedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    return "retained";
  }

  try {
    await auth.deleteUser(claimed.uid);
  } catch (error) {
    if (authErrorCode(error) !== "auth/user-not-found") throw error;
  }
  await db.runTransaction(async (transaction) => {
    const [opSnapshot, rootSnapshot] = await transaction.getAll(opRef, claimed.userRef);
    if (opSnapshot.data()?.status !== "cleanup_pending") {
      throw new HttpsError("aborted", "Cleanup ownership was lost.");
    }
    if (rootSnapshot.exists && rootSnapshot.data()?.identityTransition !== "cleanup_pending") {
      throw new HttpsError("aborted", "Cleanup transition was lost.");
    }
    if (rootSnapshot.exists) transaction.delete(claimed.userRef);
    transaction.update(opRef, {
      status: "cleaned",
      targetEmail: FieldValue.delete(),
      requestedDisplayName: FieldValue.delete(),
      cleanupAfterAt: FieldValue.delete(),
      cleanupRetryAfterAt: FieldValue.delete(),
      cleanedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return "cleaned";
}

export const cleanupAbandonedStaffIdentities = onSchedule(
  {
    schedule: "every 60 minutes",
    timeoutSeconds: 540,
    maxInstances: 1,
  },
  async () => {
    const db = getFirestore();
    const due = await db.collection("staff_identity_operations")
      .where("status", "in", ["reserved", "identity_resolved"])
      .where("cleanupAfterAt", "<=", Timestamp.now())
      .orderBy("cleanupAfterAt", "asc")
      .orderBy(FieldPath.documentId())
      .limit(50)
      .get();
    const resuming = await db.collection("staff_identity_operations")
      .where("status", "==", "cleanup_pending")
      .where("cleanupRetryAfterAt", "<=", Timestamp.now())
      .orderBy("cleanupRetryAfterAt", "asc")
      .orderBy(FieldPath.documentId())
      .limit(50)
      .get();
    const operationIds = new Set([
      ...due.docs
        .map((document) => document.id),
      ...resuming.docs.map((document) => document.id),
    ]);
    for (const operationId of operationIds) {
      try {
        await cleanupAbandonedStaffIdentity(db, operationId);
      } catch (error) {
        const code = authErrorCode(error) ?? "cleanup_failed";
        logAbsorbedFailure("staff.identity_cleanup_failed", error, {
          operationId,
          safeCode: code,
        });
        const ref = db.collection("staff_identity_operations").doc(operationId);
        await db.runTransaction(async (transaction) => {
          const snapshot = await transaction.get(ref);
          const status = snapshot.data()?.status;
          if (!["reserved", "identity_resolved", "cleanup_pending"].includes(status)) return;
          const retryAt = Timestamp.fromMillis(Date.now() + 60 * 60 * 1000);
          transaction.update(ref, {
            ...(status === "cleanup_pending" ?
              {cleanupRetryAfterAt: retryAt} : {cleanupAfterAt: retryAt}),
            cleanupLastErrorCode: code.slice(0, 128),
            cleanupLastFailedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
        });
      }
    }
  }
);
