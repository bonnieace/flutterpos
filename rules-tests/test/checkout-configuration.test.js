import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

const CHECKOUT_PATH = "tenants/tenant-a/configuration/checkout";
const BRANDING_PATH = "tenants/tenant-a/configuration/branding";

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

/** Exactly what the client merges: the code, its provenance, and nothing else. */
function checkoutConfiguration(currency = "KES", uid = "owner-a") {
  return {
    currency,
    updatedBy: uid,
    updatedAt: serverTimestamp(),
  };
}

async function seedBusiness() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "owner-a", role: "owner" }),
    ...Object.fromEntries(
      [
        ["admin-a", "admin"],
        ["manager-a", "manager"],
        ["cashier-a", "cashier"],
      ].flatMap(([uid, role]) => [
        [
          `users/${uid}`,
          {
            accountType: "tenant_user",
            globalStatus: "active",
            membershipCount: 1,
          },
        ],
        [`tenants/tenant-a/staff/${uid}`, { uid, role, status: "active" }],
      ]),
    ),
    [BRANDING_PATH]: { displayName: "Chilltent Lounge" },
  });
}

test("every active member reads the currency a till prices with", async () => {
  await seedBusiness();
  await seedDocuments(testEnvironment, {
    [CHECKOUT_PATH]: { currency: "KES" },
  });

  // A cashier cannot ring up a sale without this document, so the read is
  // deliberately as wide as the set of people who may sell.
  for (const uid of ["owner-a", "admin-a", "manager-a", "cashier-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const snapshot = await assertSucceeds(
      getDoc(doc(firestore, CHECKOUT_PATH)),
    );
    if (snapshot.data().currency !== "KES") {
      throw new Error(`Unexpected currency for ${uid}.`);
    }
  }
});

test("a business that has published nothing still answers", async () => {
  await seedBusiness();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  // This is the normal state of a new business, and it is the state the till
  // reports as "no sale can be rung up" rather than as a denial.
  const missing = await assertSucceeds(getDoc(doc(firestore, CHECKOUT_PATH)));
  if (missing.exists()) {
    throw new Error("An unpublished configuration unexpectedly existed.");
  }
});

test("an owner and an administrator publish the first currency", async () => {
  await seedBusiness();

  for (const [uid, currency] of [
    ["owner-a", "KES"],
    ["admin-a", "UGX"],
  ]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertSucceeds(
      setDoc(doc(firestore, CHECKOUT_PATH), checkoutConfiguration(currency, uid), {
        merge: true,
      }),
    );
  }
});

test("the merge leaves a sibling setting alone", async () => {
  // `configuration` is one collection with a document per concern, so a client
  // that publishes the currency must not be able to erase the branding beside
  // it. Merging is what keeps a field this build knows nothing about alive.
  await seedBusiness();
  await seedDocuments(testEnvironment, {
    [CHECKOUT_PATH]: { currency: "KES", receiptFooter: "Asante sana" },
  });
  const firestore = authenticatedFirestore(testEnvironment, "owner-a");

  await assertSucceeds(
    setDoc(doc(firestore, CHECKOUT_PATH), checkoutConfiguration("UGX"), {
      merge: true,
    }),
  );

  const snapshot = await assertSucceeds(getDoc(doc(firestore, CHECKOUT_PATH)));
  if (snapshot.data().currency !== "UGX") {
    throw new Error("The published currency was not replaced.");
  }
  if (snapshot.data().receiptFooter !== "Asante sana") {
    throw new Error("A merge discarded a setting this build does not know.");
  }
  const branding = await assertSucceeds(getDoc(doc(firestore, BRANDING_PATH)));
  if (branding.data().displayName !== "Chilltent Lounge") {
    throw new Error("Publishing the currency touched the branding document.");
  }
});

test("a manager and a cashier read the setting and never change it", async () => {
  await seedBusiness();
  await seedDocuments(testEnvironment, {
    [CHECKOUT_PATH]: { currency: "KES" },
  });

  // Running a till and correcting stock are operational; deciding what the
  // business trades in is not, and the client offers the route to neither role.
  for (const uid of ["manager-a", "cashier-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertSucceeds(getDoc(doc(firestore, CHECKOUT_PATH)));
    await assertFails(
      setDoc(doc(firestore, CHECKOUT_PATH), checkoutConfiguration("UGX", uid), {
        merge: true,
      }),
    );
    await assertFails(deleteDoc(doc(firestore, CHECKOUT_PATH)));
  }
});

test("another business's configuration is never reached", async () => {
  await seedBusiness();
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "owner-b",
      tenantId: "tenant-b",
      role: "owner",
    }),
    [CHECKOUT_PATH]: { currency: "KES" },
  });

  const foreign = authenticatedFirestore(testEnvironment, "owner-b");
  await assertFails(getDoc(doc(foreign, CHECKOUT_PATH)));
  await assertFails(
    setDoc(doc(foreign, CHECKOUT_PATH), checkoutConfiguration("UGX", "owner-b"), {
      merge: true,
    }),
  );
  // Its own business still answers, so the denial is the boundary and not a
  // broken rule.
  await assertSucceeds(
    setDoc(
      doc(foreign, "tenants/tenant-b/configuration/checkout"),
      checkoutConfiguration("UGX", "owner-b"),
      { merge: true },
    ),
  );
});

test("a deactivated, disabled, or non-member owner publishes nothing", async () => {
  await seedBusiness();

  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
  });
  const outsider = authenticatedFirestore(testEnvironment, "outsider");
  await assertFails(getDoc(doc(outsider, CHECKOUT_PATH)));
  await assertFails(
    setDoc(
      doc(outsider, CHECKOUT_PATH),
      checkoutConfiguration("UGX", "outsider"),
      { merge: true },
    ),
  );

  // An owner whose staff record was deactivated, and one whose root identity was
  // disabled globally. Rules authorize from canonical staff and root status, so
  // each stops the write on its own.
  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/admin-a": {
      uid: "admin-a",
      role: "admin",
      status: "inactive",
    },
    "users/owner-a": {
      accountType: "tenant_user",
      globalStatus: "disabled",
      membershipCount: 1,
    },
  });
  for (const uid of ["admin-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      setDoc(doc(firestore, CHECKOUT_PATH), checkoutConfiguration("UGX", uid), {
        merge: true,
      }),
    );
  }
});

test("a suspended or archived business publishes nothing", async () => {
  // A lifecycle state the platform set is not something a tenant works around by
  // changing its own settings.
  for (const status of ["suspended", "archived", "pending", "rejected"]) {
    await seedBusiness();
    await seedDocuments(testEnvironment, {
      "tenants/tenant-a": {
        name: "tenant-a",
        ownerUid: "owner-a",
        status,
      },
    });
    const firestore = authenticatedFirestore(testEnvironment, "owner-a");
    await assertFails(
      setDoc(doc(firestore, CHECKOUT_PATH), checkoutConfiguration("UGX"), {
        merge: true,
      }),
    );
    await testEnvironment.clearFirestore();
  }
});

test("an unauthenticated client reads and writes nothing", async () => {
  await seedBusiness();
  const firestore = testEnvironment.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(firestore, CHECKOUT_PATH)));
  await assertFails(
    setDoc(doc(firestore, CHECKOUT_PATH), { currency: "UGX" }, { merge: true }),
  );
});
