import assert from "node:assert/strict";
import test from "node:test";
import {
  completeGrantWithClaimCompensation,
  mergeSuperAdminClaim,
  PlatformGrantCompletionCompensationError,
  removePlatformRoleClaim,
  summarizeEligibilityEvidence,
} from "./grantPlatformAdmin";
import {PLATFORM_ELIGIBILITY_SCAN_SOURCES} from "./eligibility";

test("platform claim merge preserves all unrelated custom claims", () => {
  const existing = {
    supportTier: "senior",
    canImpersonate: false,
    platformRole: "viewer",
  };

  const merged = mergeSuperAdminClaim(existing);

  assert.deepEqual(merged, {
    supportTier: "senior",
    canImpersonate: false,
    platformRole: "superAdmin",
  });
  assert.deepEqual(existing, {
    supportTier: "senior",
    canImpersonate: false,
    platformRole: "viewer",
  });
});

test("platform claim merge also handles identities without prior claims", () => {
  assert.deepEqual(mergeSuperAdminClaim(undefined), {
    platformRole: "superAdmin",
  });
});

test("platform claim removal preserves every unrelated custom claim", () => {
  const existing = {
    supportTier: "senior",
    canImpersonate: false,
    platformRole: "superAdmin",
  };

  assert.deepEqual(removePlatformRoleClaim(existing), {
    supportTier: "senior",
    canImpersonate: false,
  });
  assert.equal(existing.platformRole, "superAdmin");
});

test("failed guarded completion compensates a late platform claim", async () => {
  const calls: string[] = [];
  let storedClaims: Record<string, unknown> = {
    supportTier: "senior",
    platformRole: "superAdmin",
  };
  const completionFailure = new Error("identity transition was cleared by disable");
  const auth = {
    async getUser(uid: string) {
      calls.push(`get:${uid}`);
      return {customClaims: storedClaims};
    },
    async setCustomUserClaims(uid: string, claims: Record<string, unknown>) {
      calls.push(`set:${uid}`);
      storedClaims = claims;
    },
  };

  await assert.rejects(
    completeGrantWithClaimCompensation(auth, "target-user", async () => {
      calls.push("complete");
      throw completionFailure;
    }),
    (error: unknown) =>
      error instanceof PlatformGrantCompletionCompensationError &&
      error.completionError === completionFailure &&
      error.claimCompensated === true
  );

  assert.deepEqual(calls, ["complete", "get:target-user", "set:target-user"]);
  assert.deepEqual(storedClaims, {supportTier: "senior"});
});

test("failed claim compensation is surfaced for operator remediation", async () => {
  const completionFailure = new Error("completion failed");
  const compensationFailure = new Error("auth unavailable");
  const auth = {
    async getUser(_uid: string) {
      throw compensationFailure;
    },
    async setCustomUserClaims(
      _uid: string,
      _claims: Record<string, unknown>
    ) {},
  };

  await assert.rejects(
    completeGrantWithClaimCompensation(auth, "target-user", async () => {
      throw completionFailure;
    }),
    (error: unknown) =>
      error instanceof PlatformGrantCompletionCompensationError &&
      error.completionError === completionFailure &&
      error.compensationError === compensationFailure &&
      error.claimCompensated === false
  );
});

test("audit evidence proves every canonical scan and bounds path samples", () => {
  const summary = summarizeEligibilityEvidence({
    targetUid: "target-user",
    scannedSources: [...PLATFORM_ELIGIBILITY_SCAN_SOURCES],
    staffMemberships: [
      {kind: "staff_membership", documentPath: "tenants/a/staff/target-user"},
      {kind: "staff_membership", documentPath: "tenants/b/staff/target-user"},
    ],
    ownedTenants: [
      {kind: "tenant_ownership", documentPath: "tenants/c"},
    ],
    unresolvedInvitations: [
      {
        kind: "unresolved_invitation",
        documentPath: "tenants/d/staff_invitations/target-user",
      },
    ],
  }, 2);

  assert.deepEqual(summary.canonicalScans, PLATFORM_ELIGIBILITY_SCAN_SOURCES);
  assert.deepEqual(summary.canonicalEvidenceCounts, {
    staffMemberships: 2,
    ownedTenants: 1,
    unresolvedInvitations: 1,
  });
  assert.equal(summary.canonicalEvidenceSamplePaths.length, 2);
  assert.equal(summary.canonicalEvidenceTruncated, true);
});
