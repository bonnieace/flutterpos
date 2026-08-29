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
  /**
   * Whether this grant is the break-glass bootstrap of the very first platform
   * administrator, which has no operator to act on its behalf.
   *
   * Recorded in the audit trail so a bootstrapped administrator is
   * distinguishable from one an operator granted. It authorizes nothing: the
   * refusal that makes this safe - that no platform administrator may already
   * exist - is made by `requireBootstrapEligible` before the saga is entered.
   */
  bootstrap?: boolean;
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

export function removePlatformRoleClaim(
  existingClaims: Readonly<Record<string, unknown>> | undefined
): Record<string, unknown> {
  const claims = {...(existingClaims ?? {})};
  delete claims.platformRole;
  return claims;
}

export class PlatformGrantCompletionCompensationError extends Error {
  constructor(
    readonly completionError: unknown,
    readonly claimCompensated: boolean,
    readonly compensationError?: unknown
  ) {
    super(claimCompensated ?
      "The platform grant completion failed and its Auth claim was removed." :
      "The platform grant completion and Auth claim rollback both failed."
    );
    this.name = "PlatformGrantCompletionCompensationError";
  }
}

/**
 * Completes the Firestore half of an already-applied claim change. If the
 * guarded completion loses its race, the claim is removed so a later account
 * reactivation cannot turn the stale Auth state into platform access.
 */
export async function completeGrantWithClaimCompensation(
  auth: CustomClaimsClient,
  targetUid: string,
  complete: () => Promise<void>
): Promise<void> {
  try {
    await complete();
  } catch (completionError) {
    try {
      const authUser = await auth.getUser(targetUid);
      const currentClaims = authUser.customClaims;
      if (currentClaims &&
        Object.prototype.hasOwnProperty.call(currentClaims, "platformRole")) {
        await auth.setCustomUserClaims(
          targetUid,
          removePlatformRoleClaim(currentClaims)
        );
      }
      throw new PlatformGrantCompletionCompensationError(
        completionError,
        true
      );
    } catch (compensationError) {
      if (compensationError instanceof PlatformGrantCompletionCompensationError) {
        throw compensationError;
      }
      throw new PlatformGrantCompletionCompensationError(
        completionError,
        false,
        compensationError
      );
    }
  }
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
        ...(input.bootstrap ? {bootstrap: true} : {}),
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
    await completeGrantWithClaimCompensation(auth, input.targetUid, async () => {
      await clearIdentityTransition(db, {
        targetUid: input.targetUid,
        expectedTransition: "granting_platform",
        // `platform_admin` supports safe resumption of operations prepared by
        // the previous saga ordering. New grants remain tenant_user until this
        // completion commits atomically with the transition clear.
        expectedAccountTypes: ["tenant_user", "platform_admin"],
        rootUpdates: {accountType: "platform_admin"},
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
    });
  } catch (error) {
    const compensated = error instanceof PlatformGrantCompletionCompensationError &&
      error.claimCompensated;
    await recordRecoverableFailure(
      db,
      auditPath,
      compensated ? "firestore_completion_claim_rolled_back" : "custom_claims_rollback",
      error
    );
    throw new PlatformAdminGrantError(
      "grant-completion-failed",
      compensated ?
        "The grant did not complete and its Auth claim was removed; retry the grant." :
        "The grant and Auth claim rollback did not complete; retry remediation is required.",
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
