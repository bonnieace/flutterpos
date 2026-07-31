import {FieldValue, Firestore} from "firebase-admin/firestore";
import {buildIdempotencyIdentity} from "../core/idempotency";
import {RootUserRecord} from "../core/model";
import {
  PlatformEligibilityEvidence,
  scanPlatformEligibility,
} from "./eligibility";
import {
  removePlatformRoleClaim,
  summarizeEligibilityEvidence,
} from "./grantPlatformAdmin";

const PLATFORM_ADMIN_SCAN_LIMIT = 100;

export interface PlatformRevocationAuthUser {
  uid: string;
  disabled: boolean;
  customClaims?: Record<string, unknown>;
  tokensValidAfterTime?: string;
}

export interface PlatformRevocationAuthClient {
  getUser(uid: string): Promise<PlatformRevocationAuthUser>;
  setCustomUserClaims(uid: string, claims: Record<string, unknown>): Promise<void>;
  revokeRefreshTokens(uid: string): Promise<void>;
}

export interface RevokePlatformAdminDependencies {
  db: Firestore;
  auth: PlatformRevocationAuthClient;
  scanEligibility?: (
    db: Firestore,
    targetUid: string
  ) => Promise<PlatformEligibilityEvidence>;
  scanOtherAdmins?: (
    db: Firestore,
    auth: PlatformRevocationAuthClient,
    targetUid: string
  ) => Promise<OtherPlatformAdminScan>;
}

export interface RevokePlatformAdminInput {
  targetUid: string;
  actorUid: string;
  requestId: string;
  reason: string;
}

export interface RevokePlatformAdminResult {
  targetUid: string;
  operationId: string;
  auditId: string;
  resumed: boolean;
  authValidAfterSeconds: number;
}

export interface OtherPlatformAdminScan {
  candidateRootsScanned: number;
  fullyActiveOtherUids: readonly string[];
  truncated: boolean;
  scanLimit: number;
}

type RevocationPhase =
  | "transition_acquired"
  | "claim_removal_pending"
  | "claim_removed"
  | "tokens_revoked"
  | "completed"
  | "rejected";

interface StoredRevocationOperation extends RevokePlatformAdminInput {
  operationId: string;
  auditId: string;
  phase: RevocationPhase;
  status: "pending" | "partially_failed" | "completed" | "rejected";
  attemptCount: number;
  authValidAfterSeconds?: number;
}

export type PlatformAdminRevocationErrorCode =
  | "actor-target-mismatch"
  | "operation-conflict"
  | "target-state-ineligible"
  | "target-state-disagreement"
  | "target-verification-failed"
  | "canonical-scan-failed"
  | "platform-identity-ineligible"
  | "admin-scan-failed"
  | "last-platform-admin"
  | "claim-removal-failed"
  | "token-revocation-failed"
  | "revoke-completion-failed";

export class PlatformAdminRevocationError extends Error {
  constructor(
    readonly code: PlatformAdminRevocationErrorCode,
    message: string,
    readonly recoverable: boolean,
    readonly underlyingError?: unknown
  ) {
    super(message);
    this.name = "PlatformAdminRevocationError";
  }
}

function operationIdentity(input: RevokePlatformAdminInput): string {
  return buildIdempotencyIdentity(
    input.actorUid,
    "revokePlatformAdmin",
    undefined,
    input.requestId
  ).documentId;
}

function sameRequest(
  operation: StoredRevocationOperation,
  input: RevokePlatformAdminInput
): boolean {
  return operation.actorUid === input.actorUid &&
    operation.targetUid === input.targetUid &&
    operation.requestId === input.requestId &&
    operation.reason === input.reason;
}

function safeErrorCode(error: unknown): string {
  if (error && typeof error === "object" && "code" in error) {
    const code = (error as {code?: unknown}).code;
    if (typeof code === "string") return code.slice(0, 128);
  }
  return "unknown";
}

function activePlatformRoot(
  exists: boolean,
  data: RootUserRecord | undefined
): RootUserRecord {
  if (!exists || !data || data.globalStatus !== "active" ||
    data.accountType !== "platform_admin") {
    throw new PlatformAdminRevocationError(
      "target-state-ineligible",
      "The target is not an active canonical platform administrator.",
      false
    );
  }
  return data;
}

async function prepareOperation(
  db: Firestore,
  input: RevokePlatformAdminInput
): Promise<{operation: StoredRevocationOperation; resumed: boolean}> {
  if (input.actorUid === input.targetUid) {
    throw new PlatformAdminRevocationError(
      "actor-target-mismatch",
      "The actor and target must be different identities.",
      false
    );
  }
  const operationId = operationIdentity(input);
  const operationRef = db.collection("platform_identity_operations").doc(operationId);
  const auditRef = db.collection("platform_audit_logs").doc(operationId);
  const targetRef = db.collection("users").doc(input.targetUid);

  return db.runTransaction(async (transaction) => {
    const [operationSnapshot, targetSnapshot] = await Promise.all([
      transaction.get(operationRef),
      transaction.get(targetRef),
    ]);
    if (operationSnapshot.exists) {
      const operation = operationSnapshot.data() as StoredRevocationOperation;
      if (!sameRequest(operation, input) || operation.operationId !== operationId) {
        throw new PlatformAdminRevocationError(
          "operation-conflict",
          "The request ID is already bound to different revocation input.",
          false
        );
      }
      if (operation.status === "completed") {
        return {operation, resumed: true};
      }
      if (operation.status === "rejected") {
        throw new PlatformAdminRevocationError(
          "operation-conflict",
          "The revocation request has already reached a terminal rejection.",
          false
        );
      }
      const root = activePlatformRoot(
        targetSnapshot.exists,
        targetSnapshot.exists ? targetSnapshot.data() as RootUserRecord : undefined
      );
      const lockedRoot = root as RootUserRecord & {platformIdentityOperationId?: unknown};
      if (lockedRoot.identityTransition !== "revoking_platform" ||
        lockedRoot.platformIdentityOperationId !== operationId) {
        throw new PlatformAdminRevocationError(
          "target-state-disagreement",
          "The pending operation no longer owns the canonical target lock.",
          true
        );
      }
      const resumed = {
        ...operation,
        status: "pending" as const,
        attemptCount: operation.attemptCount + 1,
      };
      transaction.update(operationRef, {
        status: "pending",
        attemptCount: resumed.attemptCount,
        lastErrorCode: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(auditRef, {
        status: "pending",
        attemptCount: resumed.attemptCount,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {operation: resumed, resumed: true};
    }

    const root = activePlatformRoot(
      targetSnapshot.exists,
      targetSnapshot.exists ? targetSnapshot.data() as RootUserRecord : undefined
    );
    if (root.identityTransition) {
      throw new PlatformAdminRevocationError(
        "target-state-ineligible",
        "The target already has an identity transition.",
        false
      );
    }
    const operation: StoredRevocationOperation = {
      ...input,
      operationId,
      auditId: operationId,
      phase: "transition_acquired",
      status: "pending",
      attemptCount: 1,
    };
    transaction.create(operationRef, {
      ...operation,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(auditRef, {
      action: "revoke_platform_admin",
      status: "pending",
      phase: "transition_acquired",
      actorUid: input.actorUid,
      targetUid: input.targetUid,
      requestId: input.requestId,
      reason: input.reason,
      attemptCount: 1,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(targetRef, {
      identityTransition: "revoking_platform",
      platformIdentityOperationId: operationId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {operation, resumed: false};
  });
}

async function markFailure(
  db: Firestore,
  operation: StoredRevocationOperation,
  phase: string,
  error: unknown
): Promise<void> {
  try {
    const data = {
      status: "partially_failed",
      recoverable: true,
      failedPhase: phase,
      lastErrorCode: safeErrorCode(error),
      updatedAt: FieldValue.serverTimestamp(),
    };
    const batch = db.batch();
    batch.set(
      db.collection("platform_identity_operations").doc(operation.operationId),
      data,
      {merge: true}
    );
    batch.set(db.collection("platform_audit_logs").doc(operation.auditId), data, {
      merge: true,
    });
    await batch.commit();
  } catch {
    // The target-level transition and operation lock remain the recovery signal.
  }
}

async function rejectOperation(
  db: Firestore,
  operation: StoredRevocationOperation,
  code: string,
  auditData: Record<string, unknown> = {}
): Promise<void> {
  const operationRef = db.collection("platform_identity_operations")
    .doc(operation.operationId);
  const auditRef = db.collection("platform_audit_logs").doc(operation.auditId);
  const targetRef = db.collection("users").doc(operation.targetUid);
  await db.runTransaction(async (transaction) => {
    const targetSnapshot = await transaction.get(targetRef);
    const root = activePlatformRoot(
      targetSnapshot.exists,
      targetSnapshot.exists ? targetSnapshot.data() as RootUserRecord : undefined
    ) as RootUserRecord & {platformIdentityOperationId?: unknown};
    if (root.identityTransition !== "revoking_platform" ||
      root.platformIdentityOperationId !== operation.operationId) {
      throw new PlatformAdminRevocationError(
        "target-state-disagreement",
        "The revocation lock was lost while rejecting the operation.",
        true
      );
    }
    transaction.update(targetRef, {
      identityTransition: FieldValue.delete(),
      platformIdentityOperationId: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(operationRef, {
      phase: "rejected",
      status: "rejected",
      recoverable: false,
      rejectionCode: code,
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(auditRef, {
      phase: "rejected",
      status: "rejected",
      recoverable: false,
      rejectionCode: code,
      ...auditData,
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

async function updatePhase(
  db: Firestore,
  operation: StoredRevocationOperation,
  phase: RevocationPhase,
  data: Record<string, unknown> = {}
): Promise<void> {
  const operationRef = db.collection("platform_identity_operations")
    .doc(operation.operationId);
  const targetRef = db.collection("users").doc(operation.targetUid);
  const auditRef = db.collection("platform_audit_logs").doc(operation.auditId);
  await db.runTransaction(async (transaction) => {
    const targetSnapshot = await transaction.get(targetRef);
    const root = activePlatformRoot(
      targetSnapshot.exists,
      targetSnapshot.exists ? targetSnapshot.data() as RootUserRecord : undefined
    ) as RootUserRecord & {platformIdentityOperationId?: unknown};
    if (root.identityTransition !== "revoking_platform" ||
      root.platformIdentityOperationId !== operation.operationId) {
      throw new PlatformAdminRevocationError(
        "target-state-disagreement",
        "The revocation operation no longer owns the target lock.",
        true
      );
    }
    transaction.set(operationRef, {
      phase,
      status: "pending",
      ...data,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(auditRef, {
      phase,
      status: "pending",
      ...data,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

export function isFullyActivePlatformAdmin(
  root: RootUserRecord,
  authUser: PlatformRevocationAuthUser
): boolean {
  return root.accountType === "platform_admin" &&
    root.globalStatus === "active" &&
    root.identityTransition === undefined &&
    authUser.disabled === false &&
    authUser.customClaims?.platformRole === "superAdmin";
}

export async function scanOtherFullyActivePlatformAdmins(
  db: Firestore,
  auth: PlatformRevocationAuthClient,
  targetUid: string
): Promise<OtherPlatformAdminScan> {
  const snapshot = await db.collection("users")
    .where("accountType", "==", "platform_admin")
    .limit(PLATFORM_ADMIN_SCAN_LIMIT + 1)
    .get();
  const documents = snapshot.docs.slice(0, PLATFORM_ADMIN_SCAN_LIMIT);
  const fullyActiveOtherUids: string[] = [];
  for (const document of documents) {
    if (document.id === targetUid) continue;
    const root = document.data() as RootUserRecord;
    if (root.globalStatus !== "active" || root.identityTransition !== undefined) continue;
    const authUser = await auth.getUser(document.id);
    if (authUser.uid !== document.id) {
      throw new Error("auth_uid_mismatch");
    }
    if (isFullyActivePlatformAdmin(root, authUser)) {
      fullyActiveOtherUids.push(document.id);
    }
  }
  return {
    candidateRootsScanned: documents.length,
    fullyActiveOtherUids,
    truncated: snapshot.size > PLATFORM_ADMIN_SCAN_LIMIT,
    scanLimit: PLATFORM_ADMIN_SCAN_LIMIT,
  };
}

export function assertAnotherFullyActivePlatformAdmin(
  scan: OtherPlatformAdminScan
): void {
  if (scan.fullyActiveOtherUids.length > 0) return;
  if (scan.truncated) {
    throw new PlatformAdminRevocationError(
      "admin-scan-failed",
      "The bounded platform-administrator scan was inconclusive.",
      true
    );
  }
  throw new PlatformAdminRevocationError(
    "last-platform-admin",
    "Revoking the last fully active platform administrator is forbidden.",
    false
  );
}

function phaseAtLeastClaimPending(phase: RevocationPhase): boolean {
  return phase === "claim_removal_pending" || phase === "claim_removed" ||
    phase === "tokens_revoked" || phase === "completed";
}

function authCutoffSeconds(authUser: PlatformRevocationAuthUser): number {
  const milliseconds = typeof authUser.tokensValidAfterTime === "string" ?
    Date.parse(authUser.tokensValidAfterTime) : Number.NaN;
  if (!Number.isFinite(milliseconds)) {
    throw new Error("invalid_auth_session_cutoff");
  }
  return Math.floor(milliseconds / 1000) + 1;
}

async function completeOperation(
  db: Firestore,
  operation: StoredRevocationOperation,
  authValidAfterSeconds: number
): Promise<void> {
  const operationRef = db.collection("platform_identity_operations")
    .doc(operation.operationId);
  const auditRef = db.collection("platform_audit_logs").doc(operation.auditId);
  const targetRef = db.collection("users").doc(operation.targetUid);
  await db.runTransaction(async (transaction) => {
    const targetSnapshot = await transaction.get(targetRef);
    const root = activePlatformRoot(
      targetSnapshot.exists,
      targetSnapshot.exists ? targetSnapshot.data() as RootUserRecord : undefined
    ) as RootUserRecord & {platformIdentityOperationId?: unknown};
    if (root.identityTransition !== "revoking_platform" ||
      root.platformIdentityOperationId !== operation.operationId) {
      throw new PlatformAdminRevocationError(
        "target-state-disagreement",
        "The revocation operation no longer owns the target lock.",
        true
      );
    }
    transaction.update(targetRef, {
      accountType: "tenant_user",
      authValidAfterSeconds,
      identityTransition: FieldValue.delete(),
      platformIdentityOperationId: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    const completion = {
      phase: "completed",
      status: "completed",
      recoverable: false,
      authValidAfterSeconds,
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    transaction.set(operationRef, completion, {merge: true});
    transaction.set(auditRef, completion, {merge: true});
  });
}

/**
 * Revokes one dedicated platform identity through a resumable operator saga.
 * The claim is never restored: a retry after the external Auth effect observes
 * the persisted pending phase and continues toward root demotion.
 */
export async function revokePlatformAdmin(
  dependencies: RevokePlatformAdminDependencies,
  input: RevokePlatformAdminInput
): Promise<RevokePlatformAdminResult> {
  const {db, auth} = dependencies;
  const prepared = await prepareOperation(db, input);
  const operation = prepared.operation;
  if (operation.status === "completed") {
    return {
      targetUid: input.targetUid,
      operationId: operation.operationId,
      auditId: operation.auditId,
      resumed: true,
      authValidAfterSeconds: operation.authValidAfterSeconds as number,
    };
  }

  let phase = operation.phase;
  if (!phaseAtLeastClaimPending(phase)) {
    let targetAuth: PlatformRevocationAuthUser;
    try {
      targetAuth = await auth.getUser(input.targetUid);
    } catch (error) {
      await markFailure(db, operation, "target_auth_verification", error);
      throw new PlatformAdminRevocationError(
        "target-verification-failed",
        "The target Auth state could not be verified.",
        true,
        error
      );
    }
    if (targetAuth.uid !== input.targetUid || targetAuth.disabled ||
      targetAuth.customClaims?.platformRole !== "superAdmin") {
      await rejectOperation(db, operation, "target-state-disagreement", {
        targetAuthEnabled: targetAuth.uid === input.targetUid && !targetAuth.disabled,
        targetHadSuperAdminClaim:
          targetAuth.customClaims?.platformRole === "superAdmin",
      });
      throw new PlatformAdminRevocationError(
        "target-state-disagreement",
        "The target Auth claim and canonical root do not agree.",
        false
      );
    }

    let evidence: PlatformEligibilityEvidence;
    try {
      evidence = await (dependencies.scanEligibility ?? scanPlatformEligibility)(
        db,
        input.targetUid
      );
    } catch (error) {
      await markFailure(db, operation, "canonical_eligibility_scan", error);
      throw new PlatformAdminRevocationError(
        "canonical-scan-failed",
        "Canonical tenant evidence could not be established.",
        true,
        error
      );
    }
    const evidenceSummary = summarizeEligibilityEvidence(evidence);
    const blockers = [
      ...evidence.staffMemberships,
      ...evidence.ownedTenants,
      ...evidence.unresolvedInvitations,
    ];
    if (blockers.length > 0) {
      await rejectOperation(db, operation, "platform-identity-ineligible", {
        ...evidenceSummary,
      });
      throw new PlatformAdminRevocationError(
        "platform-identity-ineligible",
        "The target has canonical tenant ownership, membership, or invitations.",
        false
      );
    }

    let adminScan: OtherPlatformAdminScan;
    try {
      adminScan = await (dependencies.scanOtherAdmins ??
        scanOtherFullyActivePlatformAdmins)(db, auth, input.targetUid);
      assertAnotherFullyActivePlatformAdmin(adminScan);
    } catch (error) {
      if (error instanceof PlatformAdminRevocationError && !error.recoverable) {
        await rejectOperation(db, operation, error.code, {
          canonicalScans: [...evidence.scannedSources],
        });
        throw error;
      }
      await markFailure(db, operation, "active_platform_admin_scan", error);
      if (error instanceof PlatformAdminRevocationError) throw error;
      throw new PlatformAdminRevocationError(
        "admin-scan-failed",
        "The active platform-administrator scan failed.",
        true,
        error
      );
    }

    await updatePhase(db, operation, "claim_removal_pending", {
      ...evidenceSummary,
      platformAdminScanLimit: adminScan.scanLimit,
      platformAdminRootsScanned: adminScan.candidateRootsScanned,
      platformAdminScanTruncated: adminScan.truncated,
      fullyActiveOtherAdminCount: adminScan.fullyActiveOtherUids.length,
      fullyActiveOtherAdminSampleUids:
        adminScan.fullyActiveOtherUids.slice(0, 20),
    });
    phase = "claim_removal_pending";
  }

  if (phase === "claim_removal_pending") {
    try {
      const targetAuth = await auth.getUser(input.targetUid);
      if (targetAuth.uid !== input.targetUid) throw new Error("auth_uid_mismatch");
      if (targetAuth.customClaims &&
        Object.prototype.hasOwnProperty.call(targetAuth.customClaims, "platformRole")) {
        await auth.setCustomUserClaims(
          input.targetUid,
          removePlatformRoleClaim(targetAuth.customClaims)
        );
      }
      await updatePhase(db, operation, "claim_removed", {
        claimStatus: "removed",
      });
      phase = "claim_removed";
    } catch (error) {
      await markFailure(db, operation, "claim_removal", error);
      throw new PlatformAdminRevocationError(
        "claim-removal-failed",
        "The platform claim removal did not complete; retry the same request.",
        true,
        error
      );
    }
  }

  let authValidAfterSeconds = operation.authValidAfterSeconds;
  if (phase === "claim_removed") {
    try {
      await auth.revokeRefreshTokens(input.targetUid);
      authValidAfterSeconds = authCutoffSeconds(await auth.getUser(input.targetUid));
      await updatePhase(db, operation, "tokens_revoked", {
        tokenStatus: "completed",
        authValidAfterSeconds,
      });
      phase = "tokens_revoked";
    } catch (error) {
      await markFailure(db, operation, "token_revocation", error);
      throw new PlatformAdminRevocationError(
        "token-revocation-failed",
        "Session revocation did not complete; retry the same request.",
        true,
        error
      );
    }
  }

  if (phase === "tokens_revoked") {
    if (!Number.isSafeInteger(authValidAfterSeconds) ||
      (authValidAfterSeconds as number) <= 0) {
      throw new PlatformAdminRevocationError(
        "revoke-completion-failed",
        "The persisted session cutoff is invalid.",
        true
      );
    }
    try {
      await completeOperation(db, operation, authValidAfterSeconds as number);
    } catch (error) {
      await markFailure(db, operation, "firestore_completion", error);
      if (error instanceof PlatformAdminRevocationError) throw error;
      throw new PlatformAdminRevocationError(
        "revoke-completion-failed",
        "The canonical revocation completion failed; retry the same request.",
        true,
        error
      );
    }
  }

  return {
    targetUid: input.targetUid,
    operationId: operation.operationId,
    auditId: operation.auditId,
    resumed: prepared.resumed,
    authValidAfterSeconds: authValidAfterSeconds as number,
  };
}
