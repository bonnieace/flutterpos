import assert from "node:assert/strict";
import test from "node:test";
import {
  addRootRoutingCounts,
  planMembershipMirrorRepair,
  planRootRoutingRepair,
  rootRoutingContribution,
} from "./membershipMirror";

test("canonical lifecycle and staff state replace stale mirror routing data", () => {
  const decision = planMembershipMirrorRepair({
    uid: "user-a",
    tenantId: "tenant-a",
    tenant: {
      name: "Canonical Shop",
      slug: "canonical-shop",
      ownerUid: "owner-a",
      status: "suspended",
    },
    staff: {
      uid: "user-a",
      role: "manager",
      status: "inactive",
      invitationStatus: "accepted",
    },
    mirror: {
      tenantId: "tenant-a",
      tenantName: "Old Shop",
      tenantSlug: "old-shop",
      role: "admin",
      membershipStatus: "active",
      tenantStatus: "active",
      invitationStatus: "pending",
      isOwner: true,
      mirrorVersion: 4,
    },
  });

  assert.equal(decision.action, "upsert");
  assert.deepEqual(decision.issues, ["mirror_drift"]);
  assert.deepEqual(decision.value, {
    tenantId: "tenant-a",
    tenantName: "Canonical Shop",
    tenantSlug: "canonical-shop",
    role: "manager",
    membershipStatus: "inactive",
    tenantStatus: "suspended",
    invitationStatus: "accepted",
    isOwner: false,
    mirrorVersion: 5,
  });
});

test("invalid routing metadata forces a rewrite even when projection fields match", () => {
  const decision = planMembershipMirrorRepair({
    uid: "user-a",
    tenantId: "tenant-a",
    tenant: {
      name: "Shop",
      slug: "shop",
      ownerUid: "owner-a",
      status: "active",
    },
    staff: {uid: "user-a", role: "admin", status: "active"},
    mirror: {
      tenantId: "tenant-a",
      tenantName: "Shop",
      tenantSlug: "shop",
      role: "admin",
      membershipStatus: "active",
      tenantStatus: "active",
      isOwner: false,
      mirrorVersion: 2,
    },
    forceDrift: true,
  });
  assert.equal(decision.action, "upsert");
  assert.deepEqual(decision.issues, ["mirror_drift"]);
  assert.equal(decision.value.mirrorVersion, 3);
});

test("a mirror without canonical staff is deleted instead of authorizing", () => {
  const decision = planMembershipMirrorRepair({
    uid: "user-a",
    tenantId: "tenant-a",
    tenant: {
      name: "Shop",
      slug: "shop",
      ownerUid: "owner-a",
      status: "active",
    },
    mirror: {
      tenantId: "tenant-a",
      tenantName: "Shop",
      tenantSlug: "shop",
      role: "admin",
      membershipStatus: "active",
      tenantStatus: "active",
      isOwner: false,
      mirrorVersion: 3,
    },
  });

  assert.deepEqual(decision, {
    action: "delete",
    tenantId: "tenant-a",
    issues: ["missing_canonical_membership"],
  });
});

test("missing and platform root identities delete routing mirrors", () => {
  const canonical = {
    uid: "user-a",
    tenantId: "tenant-a",
    tenant: {
      name: "Shop",
      slug: "shop",
      ownerUid: "owner-a",
      status: "active" as const,
    },
    staff: {uid: "user-a", role: "admin" as const, status: "active" as const},
  };
  assert.deepEqual(planMembershipMirrorRepair({...canonical, root: null}), {
    action: "delete",
    tenantId: "tenant-a",
    issues: ["missing_root_user"],
  });
  assert.deepEqual(planMembershipMirrorRepair({
    ...canonical,
    root: {accountType: "platform_admin", globalStatus: "active"},
  }), {
    action: "delete",
    tenantId: "tenant-a",
    issues: ["invalid_root_identity"],
  });
  assert.equal(planMembershipMirrorRepair({
    ...canonical,
    root: {accountType: "tenant_user", globalStatus: "disabled"},
  }).action, "upsert");
});

test("a corrupt owner relationship fails closed", () => {
  const ownerRoleMismatch = planMembershipMirrorRepair({
    uid: "user-a",
    tenantId: "tenant-a",
    tenant: {
      name: "Shop",
      slug: "shop",
      ownerUid: "different-owner",
      status: "active",
    },
    staff: {uid: "user-a", role: "owner", status: "active"},
  });
  const ownerUidMismatch = planMembershipMirrorRepair({
    uid: "user-a",
    tenantId: "tenant-a",
    tenant: {
      name: "Shop",
      slug: "shop",
      ownerUid: "user-a",
      status: "active",
    },
    staff: {uid: "user-a", role: "admin", status: "active"},
  });

  assert.equal(ownerRoleMismatch.action, "delete");
  assert.deepEqual(ownerRoleMismatch.issues, ["invalid_owner_invariant"]);
  assert.equal(ownerUidMismatch.action, "delete");
  assert.deepEqual(ownerUidMismatch.issues, ["invalid_owner_invariant"]);
});

test("root counters and default selection are rebuilt only from valid projections", () => {
  const accessibleOwner = planMembershipMirrorRepair({
    uid: "user-a",
    tenantId: "tenant-a",
    tenant: {
      name: "Shop A",
      slug: "shop-a",
      ownerUid: "user-a",
      status: "active",
    },
    staff: {uid: "user-a", role: "owner", status: "active"},
  });
  const inactiveAdmin = planMembershipMirrorRepair({
    uid: "user-a",
    tenantId: "tenant-b",
    tenant: {
      name: "Shop B",
      slug: "shop-b",
      ownerUid: "owner-b",
      status: "active",
    },
    staff: {uid: "user-a", role: "admin", status: "inactive"},
  });
  const orphan = planMembershipMirrorRepair({
    uid: "user-a",
    tenantId: "tenant-c",
    tenant: {
      name: "Shop C",
      slug: "shop-c",
      ownerUid: "owner-c",
      status: "active",
    },
  });
  const archivedOwner = planMembershipMirrorRepair({
    uid: "user-a",
    tenantId: "tenant-d",
    tenant: {
      name: "Shop D",
      slug: "shop-d",
      ownerUid: "user-a",
      status: "archived",
    },
    staff: {uid: "user-a", role: "owner", status: "active"},
  });

  assert.deepEqual(
    planRootRoutingRepair(
      [accessibleOwner, inactiveAdmin, orphan, archivedOwner],
      "tenant-b"
    ),
    {
      membershipCount: 3,
      ownedTenantCount: 1,
      ownedActiveTenantCount: 1,
      clearDefaultTenant: true,
    },
  );
  assert.equal(
    planRootRoutingRepair([accessibleOwner, inactiveAdmin], "tenant-a")
      .clearDefaultTenant,
    false,
  );

  assert.deepEqual(
    addRootRoutingCounts(
      rootRoutingContribution(accessibleOwner),
      rootRoutingContribution(archivedOwner)
    ),
    {membershipCount: 2, ownedTenantCount: 1, ownedActiveTenantCount: 1}
  );
});
