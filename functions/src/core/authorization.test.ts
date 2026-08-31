import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {TenantRecord} from "./model";
import {
  assertPlatformAdminDocuments,
  assertTenantMemberDocuments,
  assertVerifiedAuthIdentity,
  assertVerifiedTenantApplicant,
  tenantSatisfiesAccessMode,
} from "./authorization";

function expectHttpsCode(expectedCode: string, callback: () => unknown): void {
  assert.throws(callback, (error: unknown) => {
    return error instanceof HttpsError && error.code === expectedCode;
  });
}

test("a verified Auth record admits the applicant the stale token would refuse", () => {
  assert.doesNotThrow(() => assertVerifiedAuthIdentity(
    "user-1",
    {disabled: false, emailVerified: true}
  ));
});

test("an unverified address is refused, and a disabled account before it", () => {
  expectHttpsCode("permission-denied", () => assertVerifiedAuthIdentity(
    "user-1",
    {disabled: false, emailVerified: false}
  ));
  // Disabled is judged first: an account that is off has nothing to say about
  // whether its address was ever confirmed.
  expectHttpsCode("permission-denied", () => assertVerifiedAuthIdentity(
    "user-1",
    {disabled: true, emailVerified: true}
  ));
});

test("a missing Auth record is a precondition, not a refusal", () => {
  expectHttpsCode("failed-precondition", () => assertVerifiedAuthIdentity(
    "user-1",
    undefined
  ));
});

test("tenant authorization uses canonical documents instead of mirror counters", () => {
  const context = assertTenantMemberDocuments(
    "user-1",
    "tenant-1",
    {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
    {status: "active", ownerUid: "owner-1"},
    {uid: "user-1", role: "manager", status: "active"},
    ["owner", "admin", "manager"]
  );

  assert.equal(context.staff.role, "manager");
  assert.equal(context.tenantId, "tenant-1");
});
test("tenant authorization rejects a mirror-only or mismatched membership", () => {
  expectHttpsCode("permission-denied", () => assertTenantMemberDocuments(
    "user-1",
    "tenant-1",
    {accountType: "tenant_user", globalStatus: "active", membershipCount: 1},
    {status: "active"},
    {uid: "different-user", role: "admin", status: "active"}
  ));
});

test("tenant authorization rejects disabled roots and inactive tenants", () => {
  expectHttpsCode("permission-denied", () => assertTenantMemberDocuments(
    "user-1",
    "tenant-1",
    {accountType: "tenant_user", globalStatus: "disabled"},
    {status: "active"},
    {uid: "user-1", role: "owner", status: "active"}
  ));
  expectHttpsCode("permission-denied", () => assertTenantMemberDocuments(
    "user-1",
    "tenant-1",
    {accountType: "tenant_user", globalStatus: "active"},
    {status: "suspended"},
    {uid: "user-1", role: "owner", status: "active"}
  ));
});

test("tenant authorization checks the tenant-local role", () => {
  expectHttpsCode("permission-denied", () => assertTenantMemberDocuments(
    "user-1",
    "tenant-1",
    {accountType: "tenant_user", globalStatus: "active"},
    {status: "active"},
    {uid: "user-1", role: "cashier", status: "active"},
    ["owner", "admin"]
  ));
});

test("owners inherit admin permission only when the owner invariant is valid", () => {
  const context = assertTenantMemberDocuments(
    "owner-1",
    "tenant-1",
    {accountType: "tenant_user", globalStatus: "active"},
    {status: "active", ownerUid: "owner-1"},
    {uid: "owner-1", role: "owner", status: "active"},
    ["admin"]
  );
  assert.equal(context.staff.role, "owner");

  expectHttpsCode("permission-denied", () => assertTenantMemberDocuments(
    "owner-1",
    "tenant-1",
    {accountType: "tenant_user", globalStatus: "active"},
    {status: "active", ownerUid: "different-user"},
    {uid: "owner-1", role: "owner", status: "active"},
    ["admin"]
  ));
});

test("identity transitions block tenant applications", () => {
  expectHttpsCode("aborted", () => assertVerifiedTenantApplicant("user-1", {
    accountType: "tenant_user",
    globalStatus: "active",
    identityTransition: "granting_platform",
  }));
});

test("platform access requires both claim and active platform record", () => {
  const context = assertPlatformAdminDocuments("platform-1", "superAdmin", {
    accountType: "platform_admin",
    globalStatus: "active",
  });
  assert.equal(context.uid, "platform-1");

  expectHttpsCode("permission-denied", () => assertPlatformAdminDocuments(
    "platform-1",
    "superAdmin",
    {accountType: "tenant_user", globalStatus: "active"}
  ));
  expectHttpsCode("permission-denied", () => assertPlatformAdminDocuments(
    "platform-1",
    undefined,
    {accountType: "platform_admin", globalStatus: "active"}
  ));
});

test("a reactivated root rejects tokens minted before its auth cutoff", () => {
  expectHttpsCode("permission-denied", () => assertTenantMemberDocuments(
    "user-1",
    "tenant-1",
    {
      accountType: "tenant_user",
      globalStatus: "active",
      authValidAfterSeconds: 1_000,
    },
    {status: "active", ownerUid: "owner-1"},
    {uid: "user-1", role: "manager", status: "active"},
    undefined,
    999
  ));
  const fresh = assertTenantMemberDocuments(
    "user-1",
    "tenant-1",
    {
      accountType: "tenant_user",
      globalStatus: "active",
      authValidAfterSeconds: 1_000,
    },
    {status: "active", ownerUid: "owner-1"},
    {uid: "user-1", role: "manager", status: "active"},
    undefined,
    1_000
  );
  assert.equal(fresh.uid, "user-1");
});

// ---------------------------------------------------------------------------
// The provisional trading window
// ---------------------------------------------------------------------------

const HOUR = 60 * 60 * 1000;
const NOW = Date.UTC(2026, 7, 29, 9);

function tenantAt(status: string, provisionalUntil?: number) {
  return {
    name: "Shop",
    slug: "shop",
    status,
    ownerUid: "owner",
    ...(provisionalUntil === undefined ?
      {} :
      {provisionalUntil: {toMillis: () => provisionalUntil}}),
  } as TenantRecord;
}

test("an approved business satisfies every mode", () => {
  for (const mode of ["approved", "trading", "reading"] as const) {
    assert.equal(
      tenantSatisfiesAccessMode(tenantAt("active"), mode, NOW),
      true,
      mode
    );
  }
});

test("a request inside its window may trade but is not approved", () => {
  const tenant = tenantAt("pending", NOW + HOUR);

  assert.equal(tenantSatisfiesAccessMode(tenant, "trading", NOW), true);
  assert.equal(tenantSatisfiesAccessMode(tenant, "reading", NOW), true);
  // Provisioning an identity and mailing a stranger outlive the window.
  assert.equal(tenantSatisfiesAccessMode(tenant, "approved", NOW), false);
});

test("a lapsed request may be read and not written", () => {
  // The whole point of the read-only tail: a week of real trading does not
  // become unreachable to the shop that did it.
  const tenant = tenantAt("pending", NOW - HOUR);

  assert.equal(tenantSatisfiesAccessMode(tenant, "reading", NOW), true);
  assert.equal(tenantSatisfiesAccessMode(tenant, "trading", NOW), false);
  assert.equal(tenantSatisfiesAccessMode(tenant, "approved", NOW), false);
});

test("the window shuts at the instant it names, not after it", () => {
  const tenant = tenantAt("pending", NOW);

  assert.equal(tenantSatisfiesAccessMode(tenant, "trading", NOW - 1), true);
  assert.equal(tenantSatisfiesAccessMode(tenant, "trading", NOW), false);
});

test("a pending tenant with no window reads as lapsed, never as open", () => {
  // Every tenant requested before this field existed, and every tenant seeded
  // by hand. Trading must be the thing they cannot do.
  const tenant = tenantAt("pending");

  assert.equal(tenantSatisfiesAccessMode(tenant, "trading", NOW), false);
  assert.equal(tenantSatisfiesAccessMode(tenant, "reading", NOW), true);
});

test("rejection, suspension and archival are dark in every mode", () => {
  // A rejection is a decision about the business rather than a deadline it
  // missed, so it keeps no read-only tail.
  for (const status of ["rejected", "suspended", "archived"]) {
    for (const mode of ["approved", "trading", "reading"] as const) {
      assert.equal(
        tenantSatisfiesAccessMode(tenantAt(status, NOW + HOUR), mode, NOW),
        false,
        `${status}/${mode}`
      );
    }
  }
});

test("a provisional window cannot resurrect a rejected business", () => {
  // `setTenantLifecycle` moves pending -> rejected without clearing the field,
  // so the status check has to come first. It does.
  assert.equal(
    tenantSatisfiesAccessMode(tenantAt("rejected", NOW + HOUR), "trading", NOW),
    false
  );
});
