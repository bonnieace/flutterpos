import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { collection, doc, getDoc, getDocs } from "firebase/firestore";

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
  if (testEnvironment) await testEnvironment.clearFirestore();
});

after(async () => {
  if (testEnvironment) await testEnvironment.cleanup();
});

/** One business with an owner, a manager, and two cashiers. */
async function seedRoster() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier-a", role: "cashier" }),
    ...Object.fromEntries(
      [
        ["cashier-b", "cashier"],
        ["manager-a", "manager"],
        ["admin-a", "admin"],
        ["owner-a", "owner"],
      ].flatMap(([uid, role]) => [
        [
          `users/${uid}`,
          {
            accountType: "tenant_user",
            globalStatus: "active",
            membershipCount: 1,
          },
        ],
        [
          `tenants/tenant-a/staff/${uid}`,
          {
            uid,
            role,
            status: "active",
            name: `${uid} name`,
            email: `${uid}@example.test`,
            phone: "+254700000000",
          },
        ],
      ]),
    ),
  });
}

test("a cashier reads only its own canonical staff record", async () => {
  await seedRoster();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/staff/cashier-a")),
  );
  // A colleague's record carries an email and a phone number, so a history row
  // shows the colleague's UID instead of resolving a name.
  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-a/staff/cashier-b")),
  );
  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-a/staff/manager-a")),
  );
  await assertFails(
    getDocs(collection(firestore, "tenants/tenant-a/staff")),
  );
});

test("management reads the whole roster", async () => {
  await seedRoster();

  for (const uid of ["manager-a", "admin-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertSucceeds(
      getDoc(doc(firestore, "tenants/tenant-a/staff/cashier-a")),
    );
    const roster = await assertSucceeds(
      getDocs(collection(firestore, "tenants/tenant-a/staff")),
    );
    if (roster.docs.length !== 5) {
      throw new Error(`Unexpected roster size for ${uid}: ${roster.docs.length}`);
    }
  }
});

test("an absent staff record still answers instead of erroring", async () => {
  await seedRoster();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  const snapshot = await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/staff/never-hired")),
  );
  if (snapshot.exists()) {
    throw new Error("An absent staff record unexpectedly existed.");
  }
});

test("a deactivated or non-member identity reads no staff record", async () => {
  await seedRoster();
  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
  });

  const outsider = authenticatedFirestore(testEnvironment, "outsider");
  await assertFails(
    getDoc(doc(outsider, "tenants/tenant-a/staff/cashier-a")),
  );

  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/manager-a": {
      uid: "manager-a",
      role: "manager",
      status: "inactive",
      name: "manager-a name",
    },
  });
  const deactivated = authenticatedFirestore(testEnvironment, "manager-a");
  // Not even its own record: canonical access ends with the membership.
  await assertFails(
    getDoc(doc(deactivated, "tenants/tenant-a/staff/manager-a")),
  );
});
