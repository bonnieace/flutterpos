import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";

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

test("platform reads require both the superAdmin claim and an active platform root", async () => {
  await seedDocuments(testEnvironment, {
    "platform_config/current": { maxBusinessesPerUser: 25 },
    "users/target-user": {
      accountType: "tenant_user",
      globalStatus: "active",
    },
    "users/active-platform": {
      accountType: "platform_admin",
      globalStatus: "active",
    },
    "users/no-claim": {
      accountType: "platform_admin",
      globalStatus: "active",
    },
    "users/tenant-with-claim": {
      accountType: "tenant_user",
      globalStatus: "active",
    },
    "users/disabled-platform": {
      accountType: "platform_admin",
      globalStatus: "disabled",
    },
  });

  const activePlatform = authenticatedFirestore(
    testEnvironment,
    "active-platform",
    { platformRole: "superAdmin" },
  );
  await assertSucceeds(
    getDoc(doc(activePlatform, "platform_config/current")),
  );
  await assertSucceeds(getDoc(doc(activePlatform, "users/target-user")));

  const deniedContexts = [
    authenticatedFirestore(testEnvironment, "no-claim"),
    authenticatedFirestore(testEnvironment, "tenant-with-claim", {
      platformRole: "superAdmin",
    }),
    authenticatedFirestore(testEnvironment, "disabled-platform", {
      platformRole: "superAdmin",
    }),
    authenticatedFirestore(testEnvironment, "missing-root", {
      platformRole: "superAdmin",
    }),
    authenticatedFirestore(testEnvironment, "active-platform", {
      platformRole: "viewer",
    }),
  ];

  for (const firestore of deniedContexts) {
    await assertFails(getDoc(doc(firestore, "platform_config/current")));
    await assertFails(getDoc(doc(firestore, "users/target-user")));
  }
});

test("canonical membership documents are client-readable where intended but always server-write-only", async () => {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "manager", role: "manager" }),
    "users/manager/tenant_memberships/tenant-a": {
      tenantId: "tenant-a",
      membershipStatus: "active",
      role: "manager",
    },
    "tenants/tenant-a/staff_invitations/invitee": {
      invitationVersion: 1,
      invitationTokenHash: "server-secret",
    },
  });

  const firestore = authenticatedFirestore(testEnvironment, "manager");
  const mirror = doc(
    firestore,
    "users/manager/tenant_memberships/tenant-a",
  );
  const staff = doc(firestore, "tenants/tenant-a/staff/manager");
  const invitation = doc(
    firestore,
    "tenants/tenant-a/staff_invitations/invitee",
  );

  await assertSucceeds(getDoc(mirror));
  await assertSucceeds(getDoc(staff));
  await assertFails(updateDoc(mirror, { role: "owner" }));
  await assertFails(
    setDoc(
      doc(firestore, "users/manager/tenant_memberships/tenant-b"),
      { tenantId: "tenant-b", membershipStatus: "active", role: "owner" },
    ),
  );
  await assertFails(deleteDoc(mirror));
  await assertFails(setDoc(staff, { uid: "manager", role: "owner" }));
  await assertFails(
    setDoc(doc(firestore, "tenants/tenant-a/staff/new-user"), {
      uid: "new-user",
      role: "admin",
      status: "active",
    }),
  );
  await assertFails(deleteDoc(staff));
  await assertFails(getDoc(invitation));
  await assertFails(setDoc(invitation, { invitationVersion: 2 }));
});

test("platform control-plane collections are admin-readable and server-write-only", async () => {
  const platformCollections = [
    "platform_config",
    "platform_audit_logs",
    "platform_user_operations",
    "platform_membership_repair_runs",
    "owner_recovery_cases",
  ];
  const seeded = Object.fromEntries(
    platformCollections.map((collectionName) => [
      `${collectionName}/record-a`,
      { status: "seeded" },
    ]),
  );

  await seedDocuments(testEnvironment, {
    ...seeded,
    "users/platform-admin": {
      accountType: "platform_admin",
      globalStatus: "active",
    },
    "users/tenant-user": {
      accountType: "tenant_user",
      globalStatus: "active",
    },
  });

  const platform = authenticatedFirestore(testEnvironment, "platform-admin", {
    platformRole: "superAdmin",
  });
  const tenantUser = authenticatedFirestore(testEnvironment, "tenant-user");

  for (const collectionName of platformCollections) {
    const platformReference = doc(platform, `${collectionName}/record-a`);
    await assertSucceeds(getDoc(platformReference));
    await assertFails(updateDoc(platformReference, { status: "tampered" }));
    await assertFails(
      setDoc(doc(platform, `${collectionName}/record-b`), {
        status: "client-created",
      }),
    );
    await assertFails(deleteDoc(platformReference));
    await assertFails(
      getDoc(doc(tenantUser, `${collectionName}/record-a`)),
    );
  }
});

test("sensitive service collections remain opaque even to platform clients", async () => {
  const serviceCollections = [
    "email_deliveries",
    "email_suppressions",
    "tenant_slugs",
    "operation_idempotency",
  ];
  await seedDocuments(testEnvironment, {
    ...Object.fromEntries(
      serviceCollections.map((collectionName) => [
        `${collectionName}/record-a`,
        { status: "server-only" },
      ]),
    ),
    "users/platform-admin": {
      accountType: "platform_admin",
      globalStatus: "active",
    },
  });

  const firestore = authenticatedFirestore(testEnvironment, "platform-admin", {
    platformRole: "superAdmin",
  });

  for (const collectionName of serviceCollections) {
    await assertFails(
      getDoc(doc(firestore, `${collectionName}/record-a`)),
    );
    await assertFails(
      setDoc(doc(firestore, `${collectionName}/record-b`), {
        status: "client-created",
      }),
    );
  }
});

test("legacy root operational collections deny every authenticated client", async () => {
  const legacyCollections = [
    "staff",
    "alcohol",
    "alcoholsales",
    "returns",
    "shifts",
    "categories",
    "store",
    "hwsales",
    "hstock",
  ];
  await seedDocuments(testEnvironment, {
    ...Object.fromEntries(
      legacyCollections.map((collectionName) => [
        `${collectionName}/legacy-record`,
        { status: "legacy" },
      ]),
    ),
    "users/platform-admin": {
      accountType: "platform_admin",
      globalStatus: "active",
    },
    ...activeTenantDocuments({ uid: "tenant-user" }),
  });

  const clients = [
    authenticatedFirestore(testEnvironment, "platform-admin", {
      platformRole: "superAdmin",
    }),
    authenticatedFirestore(testEnvironment, "tenant-user"),
  ];

  for (const firestore of clients) {
    for (const collectionName of legacyCollections) {
      const reference = doc(firestore, `${collectionName}/legacy-record`);
      await assertFails(getDoc(reference));
      await assertFails(setDoc(reference, { status: "client-write" }));
    }
  }
});
