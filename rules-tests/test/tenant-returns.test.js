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
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  openShiftDocuments,
  receiptNumber,
  seedDocuments,
} from "./support.js";

const DEVICE_A = "dev-0123456789abcdef0123456789abcdef";
const BUSINESS_DATE = "2026-07-31";

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

/** A pending return exactly as the create rule allows it, as seeded state. */
function pendingReturn({
  returnId = "ret-1",
  saleId = "co-1",
  createdBy = "user-a",
} = {}) {
  return {
    returnId,
    tenantId: "tenant-a",
    saleId,
    // The sale's own trading day, which the create rule reads off the sale
    // document rather than believing. It is what lets a day's takings be netted
    // by one query instead of one per sale on the page.
    businessDate: BUSINESS_DATE,
    // The day the reversal was taken, which is a different fact from the day
    // the sale traded. Shape-checked only: binding it to `request.time` would
    // refuse every return the offline queue replays a day later.
    recordedOn: BUSINESS_DATE,
    // When the device took it - before it arrived, as for every return the
    // queue replays.
    occurredAt: Timestamp.fromMillis(1785499000000),
    createdBy,
    status: "pending",
    reason: "Customer returned a damaged bottle",
    itemsReturned: [{ productId: "product-1", quantity: 2 }],
    createdAt: Timestamp.fromMillis(1785500000000),
  };
}

/**
 * The exact document the client writer commits: the frozen key set with a
 * server-owned `createdAt`.
 */
function newReturn(returnId, overrides = {}) {
  const { drop = [], ...fields } = overrides;
  const data = {
    ...pendingReturn({ returnId }),
    createdAt: serverTimestamp(),
    ...fields,
  };
  for (const key of drop) delete data[key];
  return data;
}

/** The evidence `verifyReturnAndRestoreStock` writes back. */
function verifiedReturn() {
  return {
    ...pendingReturn({ returnId: "ret-2" }),
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

/** The immutable sale a return must name for the create rule to answer. */
function saleDocument(saleId) {
  return {
    checkoutId: saleId,
    tenantId: "tenant-a",
    soldById: "user-a",
    shiftId: "shift-a",
    deviceId: DEVICE_A,
    businessDate: BUSINESS_DATE,
    receiptNumber: receiptNumber(DEVICE_A, BUSINESS_DATE, 1),
    receiptSequence: 1,
    payloadHash: "a".repeat(64),
    items: [{ productId: "product-1", quantity: 4 }],
    total: 25,
    createdAt: Timestamp.fromMillis(1785490000000),
  };
}

async function seedReturns() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "user-a", role: "cashier" }),
    ...openShiftDocuments({ businessDate: BUSINESS_DATE }),
    "tenants/tenant-a/sales/co-1": saleDocument("co-1"),
    "tenants/tenant-a/sales/co-2": saleDocument("co-2"),
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
    "tenants/tenant-a/returns/ret-3": pendingReturn({
      returnId: "ret-3",
      saleId: "co-2",
    }),
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
  }
});

test("an active member records a pending return against any sale", async () => {
  await seedReturns();

  // Recording changes no stock, so every active member may do it and the
  // owner/admin/manager-only callable still gates restoration. A customer
  // returns to whoever is at the till, so `user-b` may reverse `user-a`'s sale.
  for (const [uid, returnId] of [
    ["user-a", "rt_own"],
    ["user-b", "rt_colleague"],
    ["manager-a", "rt_manager"],
  ]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertSucceeds(
      setDoc(
        doc(firestore, `tenants/tenant-a/returns/${returnId}`),
        newReturn(returnId, { createdBy: uid }),
      ),
    );
  }

  // The same deterministic ID is an update, which is denied, so a replayed
  // submit cannot record the reversal twice.
  const firestore = authenticatedFirestore(testEnvironment, "user-a");
  await assertFails(
    setDoc(
      doc(firestore, "tenants/tenant-a/returns/rt_own"),
      newReturn("rt_own", { createdBy: "user-a" }),
    ),
  );
});

test("a return must be exactly the frozen create contract", async () => {
  await seedReturns();
  const firestore = authenticatedFirestore(testEnvironment, "user-a");

  const refused = {
    "id-disagrees-with-path": { returnId: "rt_other" },
    "another-business": { tenantId: "tenant-b" },
    "forged-actor": { createdBy: "user-b" },
    "pre-declared-verified": { status: "verified" },
    "unknown-status": { status: "cancelled" },
    // The callable is the only writer of every verification field.
    "smuggled-verified-flag": { verified: true },
    "smuggled-verifier": { verifiedBy: "manager-a" },
    "smuggled-restoration": { stockRestored: true, stockRestorationId: "rv_x" },
    "unknown-field": { refundedCash: 500 },
    "no-sale": { drop: ["saleId"] },
    "sale-does-not-exist": { saleId: "co-missing" },
    "empty-sale-id": { saleId: "" },
    "no-business-date": { drop: ["businessDate"] },
    "no-recorded-on": { drop: ["recordedOn"] },
    "malformed-recorded-on": { recordedOn: "04-08-2026" },
    "recorded-on-not-a-string": { recordedOn: 20260804 },
    "no-occurred-at": { drop: ["occurredAt"] },
    "occurred-at-not-a-time": { occurredAt: "2026-08-04T09:00:00Z" },
    // A day the sale did not trade on would file the reversal against somebody
    // else's takings.
    "another-day": { businessDate: "2026-07-30" },
    "malformed-business-date": { businessDate: "31-07-2026" },
    "business-date-not-a-string": { businessDate: 20260731 },
    "client-chosen-instant": { createdAt: Timestamp.fromMillis(1785500000000) },
    "no-reason": { drop: ["reason"] },
    "short-reason": { reason: "ab" },
    "oversized-reason": { reason: "x".repeat(501) },
    "no-lines": { itemsReturned: [] },
    "not-a-list": { itemsReturned: "product-1" },
    // A line's own shape - a product, a positive quantity - is no longer
    // checked here, since 2026-10-05: `verifyReturnAndRestoreStock` refuses a
    // malformed line before it restores anything, and checking each position
    // in Rules is what capped a return at sixteen lines.
    "too-many-lines": {
      itemsReturned: Array.from({ length: 401 }, (_unused, index) => ({
        productId: `product-${index}`,
        quantity: 1,
      })),
    },
  };

  for (const [name, overrides] of Object.entries(refused)) {
    try {
      await assertFails(
        setDoc(
          doc(firestore, "tenants/tenant-a/returns/rt_candidate"),
          newReturn("rt_candidate", overrides),
        ),
      );
    } catch (error) {
      throw new Error(`${name} was not denied: ${error.message}`);
    }
  }
});

test("a deactivated or non-member identity records nothing", async () => {
  await seedReturns();
  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
    "tenants/tenant-a/staff/user-b": {
      uid: "user-b",
      role: "cashier",
      status: "inactive",
    },
  });

  for (const uid of ["outsider", "user-b"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      setDoc(
        doc(firestore, "tenants/tenant-a/returns/rt_blocked"),
        newReturn("rt_blocked", { createdBy: uid }),
      ),
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
