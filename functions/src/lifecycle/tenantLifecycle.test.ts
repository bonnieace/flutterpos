import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  assertExactCanonicalOwnerDocuments,
  assertOwnedActiveTenantCapacity,
  assertActivationOwnerDocuments,
  assertTenantLifecycleTransition,
  isTenantActivation,
  lifecycleOwnerCounterUpdates,
  privilegedLifecycleAuditData,
  requireTenantStatus,
  tenantReadableLifecycleAuditData,
} from "./tenantLifecycle";

function expectHttpsCode(expectedCode: string, callback: () => unknown): void {
  assert.throws(callback, (error: unknown) =>
    error instanceof HttpsError && error.code === expectedCode
  );
}

test("tenant lifecycle permits suspension, reactivation, and archival", () => {
  assert.doesNotThrow(() => assertTenantLifecycleTransition("active", "suspended"));
  assert.doesNotThrow(() => assertTenantLifecycleTransition("suspended", "active"));
  assert.doesNotThrow(() => assertTenantLifecycleTransition("active", "archived"));
  assert.doesNotThrow(() => assertTenantLifecycleTransition("suspended", "archived"));
});

test("tenant lifecycle rejects no-ops and any change to an archived tenant", () => {
  expectHttpsCode("failed-precondition", () =>
    assertTenantLifecycleTransition("active", "active")
  );
  expectHttpsCode("failed-precondition", () =>
    assertTenantLifecycleTransition("suspended", "suspended")
  );
  expectHttpsCode("failed-precondition", () =>
    assertTenantLifecycleTransition("archived", "active")
  );
  expectHttpsCode("failed-precondition", () =>
    assertTenantLifecycleTransition("archived", "suspended")
  );
});

test("reactivation is the only capacity-checked transition", () => {
  assert.equal(isTenantActivation("suspended", "active"), true);
  assert.equal(isTenantActivation("active", "suspended"), false);
  assert.equal(isTenantActivation("active", "archived"), false);
});

test("active-owned capacity fails closed at the configured limit", () => {
  assert.doesNotThrow(() => assertOwnedActiveTenantCapacity(24, 25));
  expectHttpsCode("resource-exhausted", () => assertOwnedActiveTenantCapacity(25, 25));
  expectHttpsCode("resource-exhausted", () => assertOwnedActiveTenantCapacity(0, 0));
});

test("tenant status parsing accepts only canonical lowercase states", () => {
  assert.equal(requireTenantStatus("suspended"), "suspended");
  expectHttpsCode("invalid-argument", () => requireTenantStatus("SUSPENDED"));
  expectHttpsCode("invalid-argument", () => requireTenantStatus("deleted"));
});

test("activation requires a globally active tenant owner and exact canonical owner staff", () => {
  assert.doesNotThrow(() => assertActivationOwnerDocuments(
    "owner-a",
    {accountType: "tenant_user", globalStatus: "active"},
    {uid: "owner-a", role: "owner", status: "active"}
  ));
  expectHttpsCode("permission-denied", () => assertActivationOwnerDocuments(
    "owner-a",
    {accountType: "tenant_user", globalStatus: "disabled"},
    {uid: "owner-a", role: "owner", status: "active"}
  ));
  expectHttpsCode("failed-precondition", () => assertActivationOwnerDocuments(
    "owner-a",
    {accountType: "tenant_user", globalStatus: "active"},
    {uid: "other-user", role: "owner", status: "active"}
  ));
  expectHttpsCode("aborted", () => assertActivationOwnerDocuments(
    "owner-a",
    {
      accountType: "tenant_user",
      globalStatus: "active",
      identityTransition: "granting_platform",
    },
    {uid: "owner-a", role: "owner", status: "active"}
  ));
});

test("every non-archived transition can require exactly one canonical active owner", () => {
  const owner = {uid: "owner-a", role: "owner" as const, status: "active" as const};
  assert.deepEqual(assertExactCanonicalOwnerDocuments("owner-a", [{
    documentId: "owner-a",
    data: owner,
  }]), owner);

  expectHttpsCode("failed-precondition", () =>
    assertExactCanonicalOwnerDocuments("owner-a", [])
  );
  expectHttpsCode("failed-precondition", () =>
    assertExactCanonicalOwnerDocuments("owner-a", [
      {documentId: "owner-a", data: owner},
      {
        documentId: "owner-b",
        data: {uid: "owner-b", role: "owner", status: "active"},
      },
    ])
  );
  expectHttpsCode("failed-precondition", () =>
    assertExactCanonicalOwnerDocuments("owner-a", [{
      documentId: "owner-b",
      data: owner,
    }])
  );
  expectHttpsCode("failed-precondition", () =>
    assertExactCanonicalOwnerDocuments("owner-a", [{
      documentId: "owner-a",
      data: {...owner, status: "inactive"},
    }])
  );
});

test("tenant-readable lifecycle audit omits operator identity and raw reason", () => {
  const input = {
    tenantId: "tenant-a",
    previousStatus: "active" as const,
    targetStatus: "suspended" as const,
    actorUid: "platform-operator",
    requestId: "raw-client-request-id",
    reason: "Contains internal investigation details",
    fanoutOperationId: "opaque-operation-id",
  };

  assert.deepEqual(tenantReadableLifecycleAuditData(input), {
    tenantId: "tenant-a",
    eventType: "tenant_lifecycle_changed",
    fromStatus: "active",
    toStatus: "suspended",
    actorType: "platform_admin",
    fanoutOperationId: "opaque-operation-id",
  });
  assert.deepEqual(privilegedLifecycleAuditData(input), {
    tenantId: "tenant-a",
    eventType: "tenant_lifecycle_changed",
    fromStatus: "active",
    toStatus: "suspended",
    actorUid: "platform-operator",
    requestId: "raw-client-request-id",
    reason: "Contains internal investigation details",
    fanoutOperationId: "opaque-operation-id",
  });
});

test("archival removes owned and active-owned advisory counts without underflow", () => {
  assert.deepEqual(lifecycleOwnerCounterUpdates(
    {ownedTenantCount: 3, ownedActiveTenantCount: 2},
    "active",
    "archived"
  ), {
    ownedTenantCount: 2,
    ownedActiveTenantCount: 1,
  });
  assert.deepEqual(lifecycleOwnerCounterUpdates(
    {ownedTenantCount: 1, ownedActiveTenantCount: 0},
    "suspended",
    "archived"
  ), {
    ownedTenantCount: 0,
  });
});

test("activation and suspension update only active-owned advisory count", () => {
  assert.deepEqual(lifecycleOwnerCounterUpdates(
    {ownedTenantCount: 4, ownedActiveTenantCount: 2},
    "suspended",
    "active"
  ), {ownedActiveTenantCount: 3});
  assert.deepEqual(lifecycleOwnerCounterUpdates(
    {ownedTenantCount: 4, ownedActiveTenantCount: 2},
    "active",
    "suspended"
  ), {ownedActiveTenantCount: 1});
});
