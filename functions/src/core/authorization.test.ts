import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  assertPlatformAdminDocuments,
  assertTenantMemberDocuments,
  assertVerifiedTenantApplicant,
} from "./authorization";

function expectHttpsCode(expectedCode: string, callback: () => unknown): void {
  assert.throws(callback, (error: unknown) => {
    return error instanceof HttpsError && error.code === expectedCode;
  });
}

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
