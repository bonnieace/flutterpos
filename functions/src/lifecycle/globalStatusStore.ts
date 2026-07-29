import {randomUUID} from "node:crypto";
import {Auth} from "firebase-admin/auth";
import {
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {assertPlatformAdminDocuments} from "../core/authorization";
import {buildIdempotencyIdentity} from "../core/idempotency";
import {RootUserRecord} from "../core/model";
import {
  globalStatusRetryDelayMilliseconds,
  GlobalUserStatusInput,
  GlobalUserStatusOperation,
  GlobalUserStatusSagaAdapter,
  isSameGlobalStatusRequest,
  withoutPlatformRole,
} from "./globalStatusCore";
import {scanAndRecordGlobalDisableImpact} from "./impactScan";

export interface GlobalStatusStoreOptions {
  db: Firestore;
  auth: Auth;
  internalRetry?: boolean;
  executionLeaseOwner?: string;
  actorPlatformRole?: unknown;
  actorAuthTime?: unknown;
}

interface StoredOperation extends GlobalUserStatusOperation {
  auditId: string;
  cancelledIdentityTransition?: RootUserRecord["identityTransition"];
  retryLeaseOwner?: string;
  retryLeaseExpiresAt?: Timestamp;
}

const EXECUTION_LEASE_MILLISECONDS = 10 * 60 * 1000;

function operationRef(db: Firestore, requestId: string) {
  return db.collection("platform_user_operations").doc(requestId);
}

function auditRef(db: Firestore, auditId: string) {
  return db.collection("platform_audit_logs").doc(auditId);
}

function operationData(snapshotData: FirebaseFirestore.DocumentData): StoredOperation {
  return snapshotData as StoredOperation;
}

function attemptCount(value: unknown): number {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : 0;
}

function assertTargetTransition(
  root: RootUserRecord | undefined,
  input: GlobalUserStatusInput
): RootUserRecord {
  if (!root) throw new HttpsError("not-found", "The target root user does not exist.");
  if (root.globalStatus === input.targetStatus) {
    throw new HttpsError(
      "failed-precondition",
      `The target user is already ${input.targetStatus}.`
    );
  }
  if (root.globalStatus !== "active" && root.globalStatus !== "disabled") {
    throw new HttpsError("failed-precondition", "The target root status is invalid.");
  }
  return root;
}

function assertOperationLock(
  root: RootUserRecord & {globalStatusOperationId?: unknown},
  requestId: string
): void {
  if (
    root.globalStatusOperationId !== undefined &&
    root.globalStatusOperationId !== requestId
  ) {
    throw new HttpsError(
      "aborted",
      "Another global-status operation is already in progress for this user."
    );
  }
}

function assertOperationLockHeld(
  root: RootUserRecord & {globalStatusOperationId?: unknown},
  requestId: string
): void {
  if (root.globalStatusOperationId !== requestId) {
    throw new HttpsError(
      "aborted",
      "The target user no longer holds this global-status operation."
    );
  }
}

async function prepareOperation(
  options: GlobalStatusStoreOptions,
  input: GlobalUserStatusInput,
  executionLeaseOwner: string
): Promise<GlobalUserStatusOperation> {
  const {db} = options;
  const ref = operationRef(db, input.requestId);
  const targetRef = db.collection("users").doc(input.uid);
  const actorRef = db.collection("users").doc(input.requestedBy);

  return db.runTransaction(async (transaction) => {
    const existingSnapshot = await transaction.get(ref);
    let actorSnapshot: FirebaseFirestore.DocumentSnapshot | undefined;
    if (!options.internalRetry) {
      actorSnapshot = await transaction.get(actorRef);
      assertPlatformAdminDocuments(
        input.requestedBy,
        options.actorPlatformRole,
        actorSnapshot.exists ? actorSnapshot.data() as RootUserRecord : undefined,
        options.actorAuthTime
      );
    }

    const targetSnapshot = input.uid === input.requestedBy && actorSnapshot ?
      actorSnapshot :
      await transaction.get(targetRef);
    const target = targetSnapshot.exists ?
      targetSnapshot.data() as RootUserRecord & {globalStatusOperationId?: unknown} :
      undefined;

    if (existingSnapshot.exists) {
      const existing = operationData(existingSnapshot.data() ?? {});
      if (!isSameGlobalStatusRequest(existing, input)) {
        throw new HttpsError(
          "already-exists",
          "requestId was already used for a different global-status operation."
        );
      }
      if (existing.status === "completed") return existing;
      const leaseExpiresAt = existing.retryLeaseExpiresAt instanceof Timestamp ?
        existing.retryLeaseExpiresAt.toMillis() : 0;
      if (options.internalRetry) {
        if (
          existing.retryLeaseOwner !== executionLeaseOwner ||
          leaseExpiresAt <= Date.now()
        ) {
          throw new HttpsError(
            "aborted",
            "The retry execution lease is no longer held by this worker."
          );
        }
      } else if (
        typeof existing.retryLeaseOwner === "string" &&
        existing.retryLeaseOwner !== executionLeaseOwner &&
        leaseExpiresAt > Date.now()
      ) {
        throw new HttpsError(
          "aborted",
          "This global-status operation is already being executed."
        );
      }
      if (!target) throw new HttpsError("not-found", "The target root user does not exist.");
      assertOperationLockHeld(target, input.requestId);
      const resumed = {
        ...existing,
        status: "pending" as const,
        attemptCount: attemptCount(existing.attemptCount) + 1,
        lastErrorCode: undefined,
      };
      transaction.update(ref, {
        status: "pending",
        attemptCount: resumed.attemptCount,
        lastErrorCode: FieldValue.delete(),
        retryLeaseOwner: executionLeaseOwner,
        retryLeaseExpiresAt: Timestamp.fromMillis(
          Date.now() + EXECUTION_LEASE_MILLISECONDS
        ),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(auditRef(db, existing.auditId), {
        status: "pending",
        attemptCount: resumed.attemptCount,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return resumed;
    }

    if (options.internalRetry) {
      throw new HttpsError("not-found", "The retry operation no longer exists.");
    }
    const root = assertTargetTransition(target, input);
    assertOperationLock(root, input.requestId);
    const auditId = buildIdempotencyIdentity(
      input.requestedBy,
      "setGlobalUserStatus",
      undefined,
      input.requestId
    ).documentId;
    const disabling = input.targetStatus === "disabled";
    const operation: StoredOperation = {
      ...input,
      auditId,
      firestoreStatus: disabling ? "completed" : "pending",
      impactStatus: disabling ? "pending" : "not_applicable",
      authStatus: "pending",
      claimStatus: disabling ? "pending" : "not_restored",
      tokenStatus: "pending",
      status: "pending",
      attemptCount: 1,
      affectedTenantIds: [],
      scannedTenantIds: [],
      ...(disabling && root.identityTransition ? {
        cancelledIdentityTransition: root.identityTransition,
      } : {}),
    };

    transaction.create(ref, {
      ...operation,
      nextAttemptAt: FieldValue.serverTimestamp(),
      retryLeaseOwner: executionLeaseOwner,
      retryLeaseExpiresAt: Timestamp.fromMillis(
        Date.now() + EXECUTION_LEASE_MILLISECONDS
      ),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(auditRef(db, auditId), {
      eventType: "global_user_status_changed",
      uid: input.uid,
      targetStatus: input.targetStatus,
      requestedBy: input.requestedBy,
      reason: input.reason,
      requestId: input.requestId,
      status: "pending",
      attemptCount: 1,
      cancelledIdentityTransition: root.identityTransition ?? null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(targetRef, {
      ...(disabling ? {
        globalStatus: "disabled",
        identityTransition: FieldValue.delete(),
      } : {}),
      globalStatusOperationId: input.requestId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return operation;
  });
}

function createAdapter(options: GlobalStatusStoreOptions): GlobalUserStatusSagaAdapter {
  const {db, auth} = options;
  const executionLeaseOwner = options.executionLeaseOwner ?? randomUUID();
  return {
    prepare: (input) => prepareOperation(options, input, executionLeaseOwner),
    processDisableImpact: (operation) =>
      scanAndRecordGlobalDisableImpact(db, operation),
    async setAuthDisabled(uid, disabled) {
      await auth.updateUser(uid, {disabled});
    },
    async removePlatformClaim(uid) {
      const authUser = await auth.getUser(uid);
      const claims = authUser.customClaims as Record<string, unknown> | undefined;
      if (claims && Object.prototype.hasOwnProperty.call(claims, "platformRole")) {
        await auth.setCustomUserClaims(uid, withoutPlatformRole(claims));
      }
    },
    async revokeRefreshTokens(uid) {
      await auth.revokeRefreshTokens(uid);
      const refreshed = await auth.getUser(uid);
      const validAfterMilliseconds = typeof refreshed.tokensValidAfterTime === "string" ?
        Date.parse(refreshed.tokensValidAfterTime) : Number.NaN;
      if (!Number.isFinite(validAfterMilliseconds)) {
        throw new HttpsError("internal", "Auth did not return a valid session cutoff.");
      }
      // Firebase Auth timestamps have second-level token precision. Advancing
      // one second prevents a token minted in the revocation second from
      // satisfying the root cutoff.
      return Math.floor(validAfterMilliseconds / 1000) + 1;
    },
    async activateRoot(uid, requestId, authValidAfterSeconds) {
      const ref = db.collection("users").doc(uid);
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists) {
          throw new HttpsError("not-found", "The target root user no longer exists.");
        }
        const root = snapshot.data() as RootUserRecord & {globalStatusOperationId?: unknown};
        assertOperationLockHeld(root, requestId);
        if (root.globalStatus !== "disabled" && root.globalStatus !== "active") {
          throw new HttpsError("failed-precondition", "The target root status is invalid.");
        }
        transaction.update(ref, {
          globalStatus: "active",
          authValidAfterSeconds,
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
    },
    async recordSteps(requestId, steps) {
      await operationRef(db, requestId).update({
        ...steps,
        updatedAt: FieldValue.serverTimestamp(),
      });
    },
    async complete(operation) {
      const ref = operationRef(db, operation.requestId);
      const targetRef = db.collection("users").doc(operation.uid);
      return db.runTransaction(async (transaction) => {
        const [stored, targetSnapshot] = await transaction.getAll(ref, targetRef);
        if (!stored.exists) {
          throw new HttpsError("not-found", "The status operation no longer exists.");
        }
        const data = operationData(stored.data() ?? {});
        if (data.status === "completed") return data;
        if (!targetSnapshot.exists) {
          throw new HttpsError("not-found", "The target root no longer exists.");
        }
        const target = targetSnapshot.data() as RootUserRecord & {
          globalStatusOperationId?: unknown;
        };
        assertOperationLockHeld(target, operation.requestId);
        transaction.update(ref, {
          status: "completed",
          lastErrorCode: FieldValue.delete(),
          nextAttemptAt: FieldValue.delete(),
          retryLeaseOwner: FieldValue.delete(),
          retryLeaseExpiresAt: FieldValue.delete(),
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.update(targetRef, {
          globalStatusOperationId: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.set(auditRef(db, data.auditId), {
          status: "completed",
          affectedTenantIds: [...operation.affectedTenantIds],
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {
          ...operation,
          status: "completed" as const,
          lastErrorCode: undefined,
        };
      });
    },
    async recordFailure(operation, errorCode) {
      const ref = operationRef(db, operation.requestId);
      return db.runTransaction(async (transaction) => {
        const stored = await transaction.get(ref);
        if (!stored.exists) {
          throw new HttpsError("not-found", "The status operation no longer exists.");
        }
        const data = operationData(stored.data() ?? {});
        if (data.status === "completed") return data;
        const nextAttemptAt = Timestamp.fromMillis(
          Date.now() + globalStatusRetryDelayMilliseconds(operation.attemptCount)
        );
        transaction.update(ref, {
          status: "partially_failed",
          lastErrorCode: errorCode,
          nextAttemptAt,
          retryLeaseOwner: FieldValue.delete(),
          retryLeaseExpiresAt: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.set(auditRef(db, data.auditId), {
          status: "partially_failed",
          lastErrorCode: errorCode,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {
          ...operation,
          status: "partially_failed" as const,
          lastErrorCode: errorCode,
        };
      });
    },
  };
}

export function createGlobalStatusSagaAdapter(
  options: GlobalStatusStoreOptions
): GlobalUserStatusSagaAdapter {
  return createAdapter(options);
}
