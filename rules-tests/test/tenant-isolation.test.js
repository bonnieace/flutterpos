import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  deleteDoc,
  doc,
  getDoc,
  increment,
  serverTimestamp,
  updateDoc,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

let testEnvironment;

before(async () => {
  testEnvironment = await createRulesTestEnvironment();
});

afterEach(async () => {
  if (testEnvironment) {
    await testEnvironment.clearFirestore();
  }
});

after(async () => {
  if (testEnvironment) {
    await testEnvironment.cleanup();
  }
});

test("canonical membership allows the selected tenant and denies another tenant", async () => {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "alice",
      tenantId: "tenant-a",
      role: "manager",
    }),
    "users/alice/tenant_memberships/tenant-a": {
      tenantId: "tenant-a",
      membershipStatus: "active",
      role: "manager",
    },
    "users/alice/tenant_memberships/tenant-b": {
      tenantId: "tenant-b",
      membershipStatus: "active",
      role: "owner",
    },
    "tenants/tenant-a/products/product-a": { name: "A", quantity: 4 },
    "tenants/tenant-b": {
      name: "Tenant B",
      ownerUid: "owner-b",
      status: "active",
    },
    "tenants/tenant-b/products/product-b": { name: "B", quantity: 9 },
    "tenants/tenant-a/categories/category-a": { name: "Category A" },
    "tenants/tenant-b/categories/category-b": { name: "Category B" },
  });

  const firestore = authenticatedFirestore(testEnvironment, "alice");

  await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/products/product-a")),
  );
  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-b/products/product-b")),
  );
  // A delete rather than a write: `allow create, update` on `categories` is
  // `if false` for every client since 2026-09-14, so a write would be denied in
  // both businesses and prove nothing about the boundary. Delete is the one
  // client write the collection still admits.
  await assertSucceeds(
    deleteDoc(doc(firestore, "tenants/tenant-a/categories/category-a")),
  );
  await assertFails(
    deleteDoc(doc(firestore, "tenants/tenant-b/categories/category-b")),
  );
  const unauthenticated = testEnvironment.unauthenticatedContext().firestore();
  await assertFails(
    getDoc(doc(unauthenticated, "tenants/tenant-a/products/product-a")),
  );
});

test("an active owner mirror never authorizes without canonical staff", async () => {
  await seedDocuments(testEnvironment, {
    "users/mirror-only": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 1,
      ownedActiveTenantCount: 1,
    },
    "users/mirror-only/tenant_memberships/tenant-a": {
      tenantId: "tenant-a",
      membershipStatus: "active",
      tenantStatus: "active",
      role: "owner",
      isOwner: true,
    },
    "tenants/tenant-a": {
      name: "Tenant A",
      ownerUid: "mirror-only",
      status: "active",
    },
    "tenants/tenant-a/products/product-a": { quantity: 2 },
  });

  const firestore = authenticatedFirestore(testEnvironment, "mirror-only");

  await assertSucceeds(
    getDoc(
      doc(
        firestore,
        "users/mirror-only/tenant_memberships/tenant-a",
      ),
    ),
  );
  await assertFails(getDoc(doc(firestore, "tenants/tenant-a")));
  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-a/products/product-a")),
  );
  await assertFails(
    updateDoc(doc(firestore, "tenants/tenant-a/products/product-a"), {
      quantity: increment(-1),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    deleteDoc(doc(firestore, "tenants/tenant-a/categories/category-a")),
  );
});

test("a disabled root user cannot use otherwise-active canonical membership", async () => {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "disabled-user",
      rootStatus: "disabled",
    }),
    "users/disabled-user/tenant_memberships/tenant-a": {
      tenantId: "tenant-a",
      membershipStatus: "active",
      role: "cashier",
    },
    "tenants/tenant-a/products/product-a": { quantity: 2 },
  });

  const firestore = authenticatedFirestore(testEnvironment, "disabled-user");
  await assertFails(
    getDoc(
      doc(
        firestore,
        "users/disabled-user/tenant_memberships/tenant-a",
      ),
    ),
  );
  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-a/products/product-a")),
  );
  await assertFails(
    updateDoc(doc(firestore, "tenants/tenant-a/products/product-a"), {
      quantity: increment(-1),
      updatedAt: serverTimestamp(),
    }),
  );
});

test("a suspended tenant revokes otherwise-active canonical membership", async () => {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "suspended-user",
      tenantStatus: "suspended",
    }),
    "tenants/tenant-a/products/product-a": { quantity: 2 },
  });

  const firestore = authenticatedFirestore(testEnvironment, "suspended-user");
  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-a/products/product-a")),
  );
  await assertFails(
    updateDoc(doc(firestore, "tenants/tenant-a/products/product-a"), {
      quantity: increment(-1),
      updatedAt: serverTimestamp(),
    }),
  );
});

test("an inactive canonical staff record revokes tenant access", async () => {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "inactive-user",
      staffStatus: "inactive",
    }),
    "tenants/tenant-a/products/product-a": { quantity: 2 },
  });

  const firestore = authenticatedFirestore(testEnvironment, "inactive-user");
  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-a/products/product-a")),
  );
  await assertFails(
    updateDoc(doc(firestore, "tenants/tenant-a/products/product-a"), {
      quantity: increment(-1),
      updatedAt: serverTimestamp(),
    }),
  );
});

test("reactivation requires a token minted at or after the root auth cutoff", async () => {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({uid: "reactivated-user"}),
    "users/reactivated-user": {
      accountType: "tenant_user",
      globalStatus: "active",
      authValidAfterSeconds: 1_000,
    },
    "tenants/tenant-a/products/product-a": {quantity: 2},
  });

  const staleDb = authenticatedFirestore(
    testEnvironment,
    "reactivated-user",
    {auth_time: 999},
  );
  const freshDb = authenticatedFirestore(
    testEnvironment,
    "reactivated-user",
    {auth_time: 1_000},
  );

  await assertFails(getDoc(doc(staleDb, "tenants/tenant-a/products/product-a")));
  await assertSucceeds(getDoc(doc(freshDb, "tenants/tenant-a/products/product-a")));
});

test("a platform identity cannot gain tenant access from a canonical staff record", async () => {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "platform-with-staff",
      accountType: "platform_admin",
      role: "owner",
    }),
    "users/platform-with-staff/tenant_memberships/tenant-a": {
      tenantId: "tenant-a",
      membershipStatus: "active",
      role: "owner",
    },
    "tenants/tenant-a/products/product-a": { quantity: 2 },
  });

  const firestore = authenticatedFirestore(
    testEnvironment,
    "platform-with-staff",
  );
  await assertFails(
    getDoc(
      doc(
        firestore,
        "users/platform-with-staff/tenant_memberships/tenant-a",
      ),
    ),
  );
  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-a/products/product-a")),
  );
});

test("unknown roles and an inconsistent canonical owner fail closed", async () => {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "unknown-role",
      tenantId: "tenant-role",
      role: "auditor",
    }),
    ...activeTenantDocuments({
      uid: "broken-owner",
      tenantId: "tenant-owner",
      role: "owner",
    }),
    "tenants/tenant-owner": {
      name: "tenant-owner",
      ownerUid: "different-owner",
      status: "active",
    },
  });

  const unknownRoleDb = authenticatedFirestore(
    testEnvironment,
    "unknown-role",
  );
  const brokenOwnerDb = authenticatedFirestore(
    testEnvironment,
    "broken-owner",
  );

  await assertFails(getDoc(doc(unknownRoleDb, "tenants/tenant-role")));
  await assertFails(getDoc(doc(brokenOwnerDb, "tenants/tenant-owner")));
});
