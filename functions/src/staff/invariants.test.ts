import assert from "node:assert/strict";
import test from "node:test";
import {
  hasExactCanonicalOwner,
  preservesOwnerInvariant,
  retainsAdministrativePrincipal,
} from "./invariants";
import {STAFF_MANAGEMENT_ROLES} from "./shared";

test("staff management permission includes the canonical owner and admin roles", () => {
  assert.deepEqual(STAFF_MANAGEMENT_ROLES, ["owner", "admin"]);
});

test("owner cannot be demoted, deactivated, or assigned through ordinary APIs", () => {
  assert.equal(preservesOwnerInvariant(
    "owner-1", "owner-1", "owner", "admin", "active"
  ), false);
  assert.equal(preservesOwnerInvariant(
    "owner-1", "owner-1", "owner", "owner", "inactive"
  ), false);
  assert.equal(preservesOwnerInvariant(
    "owner-1", "user-2", "admin", "owner", "active"
  ), false);
  assert.equal(preservesOwnerInvariant(
    "owner-1", "owner-1", "owner", "owner", "active"
  ), true);
});

test("exactly one active canonical owner must match tenant.ownerUid", () => {
  const owner = {uid: "owner-1", role: "owner" as const, status: "active" as const};
  assert.equal(hasExactCanonicalOwner("owner-1", [owner]), true);
  assert.equal(hasExactCanonicalOwner("owner-1", []), false);
  assert.equal(hasExactCanonicalOwner("owner-1", [
    owner,
    {uid: "owner-2", role: "owner", status: "active"},
  ]), false);
  assert.equal(hasExactCanonicalOwner("owner-2", [owner]), false);
  assert.equal(hasExactCanonicalOwner("owner-1", [{...owner, status: "inactive"}]), false);
});

test("role and status mutations retain a globally active administrative principal", () => {
  const staff = [
    {uid: "owner-1", role: "owner" as const, status: "active" as const},
    {uid: "admin-1", role: "admin" as const, status: "active" as const},
  ];
  const roots = new Map([
    ["owner-1", {
      accountType: "tenant_user" as const,
      globalStatus: "disabled" as const,
      membershipCount: 0,
    }],
    ["admin-1", {
      accountType: "tenant_user" as const,
      globalStatus: "active" as const,
      membershipCount: 0,
    }],
  ]);

  assert.equal(retainsAdministrativePrincipal(staff, roots, {
    uid: "admin-1",
    role: "manager",
    status: "active",
  }), false);
  assert.equal(retainsAdministrativePrincipal(staff, roots, {
    uid: "admin-1",
    role: "admin",
    status: "active",
  }), true);
});

test("advisory counters never create an administrative principal", () => {
  const staff = [{uid: "owner-1", role: "owner" as const, status: "active" as const}];
  const roots = new Map([
    ["owner-1", {
      accountType: "tenant_user" as const,
      globalStatus: "disabled" as const,
      membershipCount: 99,
      ownedActiveTenantCount: 99,
    }],
  ]);

  assert.equal(retainsAdministrativePrincipal(staff, roots, {
    uid: "owner-1",
    role: "owner",
    status: "active",
  }), false);
});

test("an identity transition cannot satisfy the administrative-principal invariant", () => {
  const staff = [{uid: "admin-1", role: "admin" as const, status: "active" as const}];
  const roots = new Map([[
    "admin-1",
    {
      accountType: "tenant_user" as const,
      globalStatus: "active" as const,
      identityTransition: "granting_platform" as const,
      membershipCount: 1,
    },
  ]]);
  assert.equal(retainsAdministrativePrincipal(staff, roots, staff[0]), false);
});
