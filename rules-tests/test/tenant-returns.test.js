import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  documentId,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
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
  if (testEnvironment) await testEnvironment.clearFirestore();
});

after(async () => {
  if (testEnvironment) await testEnvironment.cleanup();
});

/** A pending return exactly as the create rule allows it. */
function pendingReturn({ saleId = "co-1", createdBy = "user-a" } = {}) {
  return {
    tenantId: "tenant-a",
    saleId,
    createdBy,
    status: "pending",
    itemsReturned: [{ productId: "product-1", quantity: 2 }],
    createdAt: Timestamp.fromMillis(1785500000000),
  };
}

/** The evidence `verifyReturnAndRestoreStock` writes back. */
function verifiedReturn() {
  return {
    ...pendingReturn(),
    status: "verified",
    verified: true,
    verifiedBy: "manager-a",
    verifiedAt: Timestamp.fromMillis(1785600000000),
    stockRestored: true,
    stockRestoredAt: Timestamp.fromMillis(1785600000000),
    stockRestorationId: "rv_abc",
    updatedAt: Timestamp.fromMillis(1785600000000),
  };
}

async function seedReturns() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "user-a", role: "cashier" }),
    ...Object.fromEntries(
      [
        ["user-b", "cashier"],
        ["manager-a", "manager"],
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
        [`tenants/tenant-a/staff/${uid}`, { uid, role, status: "active" }],
      ]),
    ),
    "tenants/tenant-a/returns/ret-1": pendingReturn(),
    // Recorded by a colleague against the same sale.
    "tenants/tenant-a/returns/ret-2": verifiedReturn(),
    "tenants/tenant-a/returns/ret-3": pendingReturn({ saleId: "co-2" }),
  });
}

/** The exact newest-first page the sale-scoped repository sends. */
function saleReturnsPage(firestore, saleId) {
  return query(
    collection(firestore, "tenants/tenant-a/returns"),
    where("saleId", "==", saleId),
    orderBy(documentId(), "desc"),
    limit(21),
  );
}

test("an active member pages the returns recorded against one sale", async () => {
  await seedReturns();

  for (const uid of ["user-a", "manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const page = await assertSucceeds(getDocs(saleReturnsPage(firestore, "co-1")));
    const ids = page.docs.map((document) => document.id);
    // Newest document ID first, and only this sale's returns.
    if (ids.join(",") !== "ret-2,ret-1") {
      throw new Error(`Unexpected returns page for ${uid}: ${ids.join(",")}`);
    }
  }
});

test("a return stays a shared business record for every active member", async () => {
  await seedReturns();
  const cashier = authenticatedFirestore(testEnvironment, "user-b");

  // Pinned deliberately. `verifyReturnAndRestoreStock` bounds a restoration by
  // the immutable sale minus every prior verified return, so the quantity a
  // cashier may still request depends on a colleague's returns. Narrowing this
  // rule to `createdBy` would hide that evidence and let one cashier record a
  // return the server can never verify. Changing it must change this test.
  const colleague = await assertSucceeds(
    getDoc(doc(cashier, "tenants/tenant-a/returns/ret-1")),
  );
  if (colleague.data().createdBy !== "user-a") {
    throw new Error("The colleague's return was not readable as recorded.");
  }
  await assertSucceeds(getDocs(saleReturnsPage(cashier, "co-1")));
});

test("a return that does not exist still answers", async () => {
  await seedReturns();
  const firestore = authenticatedFirestore(testEnvironment, "user-a");

  // The rule compares a role, not `resource.data`, so an absent return is
  // answered rather than denied - the normal state for a sale with no returns.
  const snapshot = await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/returns/ret-missing")),
  );
  if (snapshot.exists()) {
    throw new Error("A missing return unexpectedly existed.");
  }
  const empty = await assertSucceeds(getDocs(saleReturnsPage(firestore, "co-9")));
  if (!empty.empty) {
    throw new Error("A sale with no returns unexpectedly returned documents.");
  }
});

test("verification evidence is server-only for every role", async () => {
  await seedReturns();

  for (const uid of ["user-a", "manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const target = doc(firestore, "tenants/tenant-a/returns/ret-1");

    // Only `verifyReturnAndRestoreStock` may write the terminal state, the
    // verifier, and the restoration ID.
    await assertFails(
      updateDoc(target, {
        status: "verified",
        verified: true,
        verifiedBy: uid,
        stockRestored: true,
        stockRestorationId: "rv_forged",
      }),
    );
    await assertFails(updateDoc(target, { status: "verified" }));
    await assertFails(deleteDoc(target));
    // A create still cannot pre-declare itself verified or name another actor.
    await assertFails(
      setDoc(doc(firestore, "tenants/tenant-a/returns/ret-new"), {
        ...pendingReturn(),
        status: "verified",
        createdBy: uid,
      }),
    );
    await assertFails(
      setDoc(doc(firestore, "tenants/tenant-a/returns/ret-new"), {
        ...pendingReturn({ createdBy: "somebody-else" }),
      }),
    );
  }
});

test("a non-member or deactivated identity reads no return", async () => {
  await seedReturns();
  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
  });

  const outsider = authenticatedFirestore(testEnvironment, "outsider");
  await assertFails(
    getDoc(doc(outsider, "tenants/tenant-a/returns/ret-1")),
  );
  await assertFails(getDocs(saleReturnsPage(outsider, "co-1")));

  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/user-b": {
      uid: "user-b",
      role: "cashier",
      status: "inactive",
    },
  });
  const deactivated = authenticatedFirestore(testEnvironment, "user-b");
  await assertFails(
    getDoc(doc(deactivated, "tenants/tenant-a/returns/ret-1")),
  );
  await assertFails(getDocs(saleReturnsPage(deactivated, "co-1")));
});

test("the server-only restoration ledger stays unreadable", async () => {
  await seedReturns();
  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/return_verifications/rv_abc": {
      tenantId: "tenant-a",
      returnId: "ret-2",
      saleId: "co-1",
      verificationId: "rv_abc",
      restoredProducts: [
        { productId: "product-1", quantityRestored: 2 },
      ],
    },
  });

  // The return document itself carries the verifier, the instant, and the
  // restoration ID, so the ledger behind it needs no client read at all.
  for (const uid of ["user-a", "manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      getDoc(doc(firestore, "tenants/tenant-a/return_verifications/rv_abc")),
    );
    await assertFails(
      getDocs(collection(firestore, "tenants/tenant-a/return_verifications")),
    );
  }
});
