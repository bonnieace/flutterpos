import {FieldValue, Firestore} from "firebase-admin/firestore";
import {RootUserRecord} from "../core/model";
import {
  evaluatePlatformEligibility,
  PlatformEligibilityEvaluation,
  PlatformEligibilityEvidence,
  scanPlatformEligibility,
} from "./eligibility";
import {
  acquireIdentityTransition,
  clearIdentityTransition,
  updateRootDuringIdentityTransition,
} from "./identityTransition";

export interface CustomClaimsClient {
  getUser(uid: string): Promise<{customClaims?: Record<string, unknown>}>;
  setCustomUserClaims(uid: string, claims: Record<string, unknown>): Promise<void>;
}

export interface GrantPlatformAdminDependencies {
  db: Firestore;
  auth: CustomClaimsClient;
  scanEligibility?: (
    db: Firestore,
    targetUid: string
  ) => Promise<PlatformEligibilityEvidence>;
}

export interface GrantPlatformAdminInput {
  targetUid: string;
  actorUid: string;
  requestId: string;
  reason: string;
}

export interface GrantPlatformAdminResult {
  targetUid: string;
  auditId: string;
  resumed: boolean;
  warnings: readonly string[];
}

export type PlatformAdminGrantErrorCode =
  | "platform-identity-ineligible"
  | "canonical-scan-failed"
  | "grant-preparation-failed"
  | "custom-claims-update-failed"
  | "grant-completion-failed";

export class PlatformAdminGrantError extends Error {
  constructor(
    readonly code: PlatformAdminGrantErrorCode,
    message: string,
    readonly recoverable: boolean,
    readonly underlyingError?: unknown,
    readonly evaluation?: PlatformEligibilityEvaluation
  ) {
    super(message);
    this.name = "PlatformAdminGrantError";
  }
}

export function mergeSuperAdminClaim(
  existingClaims: Readonly<Record<string, unknown>> | undefined
): Record<string, unknown> {
  return {
    ...(existingClaims ?? {}),
    platformRole: "superAdmin",
  };
}

interface EligibilityAuditSummary {
  canonicalScans: readonly string[];
  canonicalEvidenceCounts: {
    staffMemberships: number;
    ownedTenants: number;
    unresolvedInvitations: number;
  };
  canonicalEvidenceSamplePaths: readonly string[];
  canonicalEvidenceTruncated: boolean;
}

export function summarizeEligibilityEvidence(
  evidence: PlatformEligibilityEvidence,
  maximumSamplePaths = 20
): EligibilityAuditSummary {
  const paths = [
    ...evidence.staffMemberships,
    ...evidence.ownedTenants,
    ...evidence.unresolvedInvitations,
  ].map((item) => item.documentPath);

  return {
    canonicalScans: [...evidence.scannedSources],
    canonicalEvidenceCounts: {
      staffMemberships: evidence.staffMemberships.length,
      ownedTenants: evidence.ownedTenants.length,
      unresolvedInvitations: evidence.unresolvedInvitations.length,
    },
    canonicalEvidenceSamplePaths: paths.slice(0, maximumSamplePaths),
    canonicalEvidenceTruncated: paths.length > maximumSamplePaths,
  };
}

function advisoryCounterSnapshot(user: RootUserRecord): Record<string, number> {
  const counters: Record<string, number> = {};
  if (typeof user.membershipCount === "number") {
    counters.membershipCount = user.membershipCount;
  }
  if (typeof user.ownedTenantCount === "number") {
    counters.ownedTenantCount = user.ownedTenantCount;
  }
  if (typeof user.ownedActiveTenantCount === "number") {
    counters.ownedActiveTenantCount = user.ownedActiveTenantCount;
  }
  return counters;
}

function safeErrorCode(error: unknown): string {
  if (error && typeof error === "object" && "code" in error) {
    const code = (error as {code?: unknown}).code;
    if (typeof code === "string") return code.slice(0, 128);
  }
  return "unknown";
}

async function recordRecoverableFailure(
  db: Firestore,
  auditPath: string,
  phase: string,
  error: unknown
): Promise<void> {
  try {
    await db.doc(auditPath).set({
      status: "partially_failed",
      recoverable: true,
      failedPhase: phase,
      lastErrorCode: safeErrorCode(error),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  } catch {
    // The root transition remains the durable recovery signal if audit writing
    // is unavailable at the same time as the failed external effect.
  }
}

/**
 * Grants the platform role as a resumable saga.
 *
 * The root remains in `granting_platform` after scan, preparation, Auth, or
 * completion failures. Calling the service again resumes from that guarded
 * state. Authorization still requires both the Auth claim and active platform
 * root record, so no partial phase grants platform access on its own.
 */
export async function grantPlatformAdmin(
  dependencies: GrantPlatformAdminDependencies,
  input: GrantPlatformAdminInput
): Promise<GrantPlatformAdminResult> {
  const {db, auth} = dependencies;
  const auditRef = db.collection("platform_audit_logs").doc();
  const auditPath = auditRef.path;
  const transitionTimestamp = FieldValue.serverTimestamp();
  const acquired = await acquireIdentityTransition(db, {
    targetUid: input.targetUid,
    transition: "granting_platform",
    expectedAccountType: "tenant_user",
    resumableAccountTypes: ["tenant_user", "platform_admin"],
    audit: {
      documentPath: auditPath,
      data: {
        action: "grant_platform_admin",
        status: "transition_acquired",
        targetUid: input.targetUid,
        actorUid: input.actorUid,
        requestId: input.requestId,
        reason: input.reason,
        createdAt: transitionTimestamp,
        updatedAt: transitionTimestamp,
      },
    },
  });

  let evidence: PlatformEligibilityEvidence;
  try {
    evidence = await (dependencies.scanEligibility ?? scanPlatformEligibility)(
      db,
      input.targetUid
    );
  } catch (error) {
    await recordRecoverableFailure(db, auditPath, "canonical_eligibility_scan", error);
    throw new PlatformAdminGrantError(
      "canonical-scan-failed",
      "Canonical platform eligibility could not be established.",
      true,
      error
    );
  }

  const evaluation = evaluatePlatformEligibility(evidence, acquired.user);
  const evidenceSummary = summarizeEligibilityEvidence(evidence);

  if (!evaluation.eligible) {
    const restoreTenantAccount = acquired.user.accountType === "platform_admin";
    await clearIdentityTransition(db, {
      targetUid: input.targetUid,
      expectedTransition: "granting_platform",
      expectedAccountTypes: ["tenant_user", "platform_admin"],
      ...(restoreTenantAccount ? {rootUpdates: {accountType: "tenant_user"}} : {}),
      audit: {
        documentPath: auditPath,
        data: {
          status: "rejected_ineligible",
          recoverable: false,
          warnings: [...evaluation.warnings],
          ...evidenceSummary,
          stalePlatformClaimCannotAuthorize: restoreTenantAccount,
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
      },
    });
    throw new PlatformAdminGrantError(
      "platform-identity-ineligible",
      "The identity has canonical tenant ownership, membership, or an unresolved invitation.",
      false,
      undefined,
      evaluation
    );
  }

  try {
    await updateRootDuringIdentityTransition(db, {
      targetUid: input.targetUid,
      expectedTransition: "granting_platform",
      expectedAccountTypes: ["tenant_user", "platform_admin"],
      rootUpdates: {accountType: "platform_admin"},
      audit: {
        documentPath: auditPath,
        data: {
          status: "custom_claim_pending",
          advisoryCounters: advisoryCounterSnapshot(acquired.user),
          warnings: [...evaluation.warnings],
          ...evidenceSummary,
          updatedAt: FieldValue.serverTimestamp(),
        },
      },
    });
  } catch (error) {
    await recordRecoverableFailure(db, auditPath, "firestore_preparation", error);
    throw new PlatformAdminGrantError(
      "grant-preparation-failed",
      "The platform grant could not be prepared.",
      true,
      error
    );
  }

  try {
    const authUser = await auth.getUser(input.targetUid);
    const mergedClaims = mergeSuperAdminClaim(authUser.customClaims);
    await auth.setCustomUserClaims(input.targetUid, mergedClaims);
  } catch (error) {
    await recordRecoverableFailure(db, auditPath, "custom_claims_update", error);
    throw new PlatformAdminGrantError(
      "custom-claims-update-failed",
      "The Auth claim update failed; retrying the grant will resume it.",
      true,
      error
    );
  }

  try {
    await clearIdentityTransition(db, {
      targetUid: input.targetUid,
      expectedTransition: "granting_platform",
      expectedAccountTypes: ["platform_admin"],
      audit: {
        documentPath: auditPath,
        data: {
          status: "completed",
          recoverable: false,
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
      },
    });
  } catch (error) {
    await recordRecoverableFailure(db, auditPath, "firestore_completion", error);
    throw new PlatformAdminGrantError(
      "grant-completion-failed",
      "The Auth claim was applied but completion is pending; retry the grant.",
      true,
      error
    );
  }

  return {
    targetUid: input.targetUid,
    auditId: auditRef.id,
    resumed: acquired.resumed,
    warnings: evaluation.warnings,
  };
}
