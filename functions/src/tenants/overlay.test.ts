import assert from "node:assert/strict";
import test from "node:test";
import {overlayCanonicalTenantState} from "./overlay";

const ACTIVE_USER = {
  accountType: "tenant_user" as const,
  globalStatus: "active" as const,
};

test("canonical tenant and staff state override stale mirror routing data", () => {
  const item = overlayCanonicalTenantState(
    "user-1",
    "canonical-doc-id",
    {
      tenantId: "stale-redirect-id",
      tenantName: "Old name",
      tenantSlug: "old-name",
      role: "owner",
      membershipStatus: "active",
      tenantStatus: "active",
      isOwner: true,
      createdAt: new Date("2026-07-29T10:00:00.000Z"),
      mirrorVersion: 2,
    },
    ACTIVE_USER,
    {
      name: "Current name",
      slug: "current-name",
      status: "suspended",
      ownerUid: "someone-else",
    },
    {
      uid: "user-1",
      role: "manager",
      status: "inactive",
      invitationStatus: "accepted",
    }
  );

  assert.equal(item.tenantId, "canonical-doc-id");
  assert.equal(item.tenantName, "Current name");
  assert.equal(item.tenantSlug, "current-name");
  assert.equal(item.role, "manager");
  assert.equal(item.membershipStatus, "inactive");
  assert.equal(item.tenantStatus, "suspended");
  assert.equal(item.isOwner, false);
  assert.equal(item.canAccess, false);
  assert.equal(item.createdAt, "2026-07-29T10:00:00.000Z");
});

test("an active mirror alone never grants tenant access", () => {
  const item = overlayCanonicalTenantState("user-1", "tenant-1", {
    tenantId: "tenant-1",
    tenantName: "Mirror only",
    tenantSlug: "mirror-only",
    role: "owner",
    membershipStatus: "active",
    tenantStatus: "active",
    isOwner: true,
  }, ACTIVE_USER, undefined, undefined);

  assert.equal(item.canAccess, false);
  assert.equal(item.isOwner, false);
  assert.equal(item.canonicalTenantExists, false);
  assert.equal(item.canonicalMembershipExists, false);
});

test("canAccess requires an active root, tenant, and exact canonical staff record", () => {
  const activeItem = overlayCanonicalTenantState("user-1", "tenant-1", {}, ACTIVE_USER, {
    status: "active",
    ownerUid: "user-1",
  }, {
    uid: "user-1",
    role: "owner",
    status: "active",
  });
  const mismatchedItem = overlayCanonicalTenantState("user-1", "tenant-1", {}, ACTIVE_USER, {
    status: "active",
  }, {
    uid: "different-user",
    role: "admin",
    status: "active",
  });

  assert.equal(activeItem.canAccess, true);
  assert.equal(activeItem.isOwner, true);
  assert.equal(mismatchedItem.canAccess, false);
  assert.equal(mismatchedItem.canonicalMembershipExists, false);
});
