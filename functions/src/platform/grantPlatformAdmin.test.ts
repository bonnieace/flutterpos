import assert from "node:assert/strict";
import test from "node:test";
import {
  mergeSuperAdminClaim,
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
