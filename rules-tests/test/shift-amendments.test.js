import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
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
  seedDocuments,
} from "./support.js";

const FEED_PATH = "tenants/tenant-a/shift_amendments";
const SHIFT_PATH = "tenants/tenant-a/shifts/shift-a";

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

/** The exact immutable record `amendShiftSummary` writes for the business. */
function amendment(overrides = {}) {
  return {
    amendmentId: "sm_abc",
    tenantId: "tenant-a",
    shiftId: "shift-a",
    staffId: "cashier-a",
    businessDate: "2026-07-31",
    sourceType: "reconciliation_shift_variance",
    expectationId: "se_abc",
    expectationGeneration: "generation-one",
    previousTotalSales: 1200.5,
    previousTotalSalesMinor: 120050,
    previousTransactionCount: 9,
    previousRepresentationsAgreed: true,
    totalSales: 1350.25,
    totalSalesMinor: 135025,
    transactionCount: 10,
    salesVarianceMinor: -14975,
    transactionVariance: -1,
    clearedAnomalyId: "shift_abc",
    mutatesCountedCash: false,
    reason: "Offline sale arrived after the shift closed",
    actorUid: "owner-a",
    requestId: "amend-shift-abcdefgh",
    createdAt: Timestamp.fromMillis(1785574800000),
    ...overrides,
  };
}

/** A closed shift already amended by the callable, exactly as it leaves it. */
function amendedShift(overrides = {}) {
  return {
    shiftId: "shift-a",
    tenantId: "tenant-a",
    staffId: "cashier-a",
    deviceId: "dev-0123456789abcdef0123456789abcdef",
    businessDate: "2026-07-31",
    status: "closed",
    startTime: Timestamp.fromMillis(1785484800000),
    endTime: Timestamp.fromMillis(1785574800000),
    closingCashMinor: 118000,
    closingCash: 1180,
    totalSales: 1350.25,
    totalSalesMinor: 135025,
    transactionCount: 10,
    summaryAmendmentId: "sm_abc",
    summaryAmendedGeneration: "generation-one",
    summaryAmendedAt: Timestamp.fromMillis(1785578400000),
    summaryAmendmentCount: 1,
    ...overrides,
  };
}

async function seedAmendments() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier-a", role: "cashier" }),
    ...Object.fromEntries(
      [
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
    [SHIFT_PATH]: amendedShift(),
    [`${FEED_PATH}/sm_abc`]: amendment(),
    [`${FEED_PATH}/sm_def`]: amendment({
      amendmentId: "sm_def",
      shiftId: "shift-b",
      businessDate: "2026-07-30",
      previousTotalSales: 80,
      previousTotalSalesMinor: 8000,
      previousTransactionCount: 2,
      totalSales: 75,
      totalSalesMinor: 7500,
      transactionCount: 2,
      salesVarianceMinor: 500,
      transactionVariance: 0,
      clearedAnomalyId: null,
      reason: "Duplicate sale reversed by reconciliation",
    }),
  });
}

/** The exact business-wide page a client would issue. */
function feedPage(firestore, path = FEED_PATH) {
  return query(collection(firestore, path), orderBy("__name__"), limit(21));
}

/** The exact shift-narrowed page a client would issue. */
function shiftPage(firestore, shiftId, path = FEED_PATH) {
  return query(
    collection(firestore, path),
    where("shiftId", "==", shiftId),
    orderBy("__name__"),
    limit(21),
  );
}

test("management pages the business-wide amendment record", async () => {
  await seedAmendments();

  for (const uid of ["manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const snapshot = await assertSucceeds(
      getDoc(doc(firestore, `${FEED_PATH}/sm_abc`)),
    );
    if (snapshot.data().totalSalesMinor !== 135025) {
      throw new Error(`Unexpected amendment for ${uid}.`);
    }
    // The record states the one property that makes the path safe to expose.
    if (snapshot.data().mutatesCountedCash !== false) {
      throw new Error(`Amendment for ${uid} did not disclaim the counted cash.`);
    }

    // Ascending document ID with no filter, one more document than the page
    // size. An amendment ID is `sm_` plus a digest, so document order carries no
    // time information and a descending page would be neither newest first nor
    // servable without a composite index.
    const page = await assertSucceeds(getDocs(feedPage(firestore)));
    if (page.docs.map((entry) => entry.id).join(",") !== "sm_abc,sm_def") {
      throw new Error(`Unexpected feed order for ${uid}.`);
    }

    // The same order narrowed by one equality filter, which Firestore's
    // automatic single-field index serves without a composite index. If that ever
    // stops being true the emulator rejects the query here rather than a client
    // failing in production.
    const narrowed = await assertSucceeds(
      getDocs(shiftPage(firestore, "shift-a")),
    );
    if (narrowed.docs.map((entry) => entry.id).join(",") !== "sm_abc") {
      throw new Error(`Unexpected shift page for ${uid}.`);
    }
  }
});

test("a business that has never amended a shift still answers", async () => {
  await seedAmendments();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  // An unwritten amendment discloses nothing, and a shift that was never amended
  // is the normal state, so both must answer rather than deny.
  const missing = await assertSucceeds(
    getDoc(doc(firestore, `${FEED_PATH}/sm_never`)),
  );
  if (missing.exists()) {
    throw new Error("An unwritten amendment unexpectedly existed.");
  }
  const emptyShift = await assertSucceeds(
    getDocs(shiftPage(firestore, "shift-404")),
  );
  if (!emptyShift.empty) {
    throw new Error("An unamended shift unexpectedly returned records.");
  }

  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "manager-c",
      tenantId: "tenant-c",
      role: "manager",
    }),
  });
  const fresh = authenticatedFirestore(testEnvironment, "manager-c");
  const emptyFeed = await assertSucceeds(
    getDocs(feedPage(fresh, "tenants/tenant-c/shift_amendments")),
  );
  if (!emptyFeed.empty) {
    throw new Error("An empty feed unexpectedly returned documents.");
  }
});

test("a cashier reads the amended shift but never the amendment", async () => {
  await seedAmendments();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  // The corrected totals are the cashier's own shift and stay readable. The
  // record of which owner amended it, why, and by how much is the business's
  // governance in exactly the way a stock correction is.
  const shift = await assertSucceeds(getDoc(doc(firestore, SHIFT_PATH)));
  if (shift.data().closingCashMinor !== 118000) {
    throw new Error("The amended shift lost its counted cash.");
  }
  await assertFails(getDoc(doc(firestore, `${FEED_PATH}/sm_abc`)));
  await assertFails(getDoc(doc(firestore, `${FEED_PATH}/sm_never`)));
  await assertFails(getDocs(feedPage(firestore)));
  await assertFails(getDocs(shiftPage(firestore, "shift-a")));
});

test("no client may record, rewrite, or delete an amendment", async () => {
  await seedAmendments();

  for (const uid of ["owner-a", "manager-a", "cashier-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    // A client that could create here could claim a correction that never
    // happened; one that could update or delete could erase the only record of
    // one that did. Every real record is written by `amendShiftSummary` inside
    // the transaction that changes the shift.
    await assertFails(
      setDoc(doc(firestore, `${FEED_PATH}/sm_forged`), amendment()),
    );
    await assertFails(
      setDoc(
        doc(firestore, `${FEED_PATH}/sm_abc`),
        amendment({ totalSalesMinor: 1 }),
      ),
    );
    await assertFails(deleteDoc(doc(firestore, `${FEED_PATH}/sm_abc`)));
  }
});

test("an amended shift is still terminal for the cashier who closed it", async () => {
  await seedAmendments();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  // Amending adds fields to a closed shift. The close rule only ever permitted
  // `open -> closed`, so the amendment must not have opened a second way in: no
  // client may restate the summary the server just corrected, re-close the
  // shift, touch the counted cash, or claim an amendment of its own.
  await assertFails(
    updateDoc(doc(firestore, SHIFT_PATH), {
      totalSales: 1200.5,
      totalSalesMinor: 120050,
      transactionCount: 9,
    }),
  );
  await assertFails(
    updateDoc(doc(firestore, SHIFT_PATH), {
      status: "closed",
      endTime: serverTimestamp(),
      closingCashMinor: 135025,
      closingCash: 1350.25,
      totalSales: 1350.25,
      totalSalesMinor: 135025,
      transactionCount: 10,
    }),
  );
  await assertFails(
    updateDoc(doc(firestore, SHIFT_PATH), { closingCashMinor: 135025 }),
  );
  await assertFails(
    updateDoc(doc(firestore, SHIFT_PATH), {
      summaryAmendmentId: "sm_forged",
      summaryAmendmentCount: 2,
    }),
  );
  await assertFails(
    updateDoc(doc(firestore, SHIFT_PATH), { status: "open" }),
  );

  // An owner cannot reach it either: the shift rule is the cashier's own, and
  // amending runs through the callable rather than through a privileged write.
  const owner = authenticatedFirestore(testEnvironment, "owner-a");
  await assertFails(
    updateDoc(doc(owner, SHIFT_PATH), {
      totalSalesMinor: 1,
      totalSales: 0.01,
      transactionCount: 1,
    }),
  );
});

test("another business's amendment record is never reached", async () => {
  await seedAmendments();
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({
      uid: "manager-b",
      tenantId: "tenant-b",
      role: "manager",
    }),
    "tenants/tenant-b/shift_amendments/sm_abc": amendment({
      tenantId: "tenant-b",
    }),
  });

  const foreign = authenticatedFirestore(testEnvironment, "manager-b");
  await assertFails(getDoc(doc(foreign, `${FEED_PATH}/sm_abc`)));
  await assertFails(getDocs(feedPage(foreign)));
  await assertFails(getDocs(shiftPage(foreign, "shift-a")));
  // Its own business still answers, so the denial is the boundary and not a
  // broken rule.
  await assertSucceeds(
    getDoc(doc(foreign, "tenants/tenant-b/shift_amendments/sm_abc")),
  );
  await assertSucceeds(
    getDocs(feedPage(foreign, "tenants/tenant-b/shift_amendments")),
  );
});

test("a deactivated or non-member identity reads no amendments", async () => {
  await seedAmendments();
  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
  });

  const outsider = authenticatedFirestore(testEnvironment, "outsider");
  await assertFails(getDoc(doc(outsider, `${FEED_PATH}/sm_abc`)));
  await assertFails(getDocs(feedPage(outsider)));

  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/manager-a": {
      uid: "manager-a",
      role: "manager",
      status: "inactive",
    },
  });
  const deactivated = authenticatedFirestore(testEnvironment, "manager-a");
  await assertFails(getDoc(doc(deactivated, `${FEED_PATH}/sm_abc`)));
  await assertFails(getDocs(feedPage(deactivated)));
});

test("the server-only reconciliation records behind an amendment stay unreachable", async () => {
  await seedAmendments();
  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/shift_expectations/se_abc": {
      tenantId: "tenant-a",
      shiftId: "shift-a",
      businessDate: "2026-07-31",
      sales: 1350.25,
      transactions: 10,
      generation: "generation-one",
      needsVerification: false,
      verificationStatus: "amended",
      verifiedGeneration: "generation-one",
      amendmentId: "sm_abc",
    },
  });

  // The amendment reads the settled expectation and clears the listed
  // difference. Neither is client-readable, and a client that could write the
  // expectation could choose the total the callable amends a shift to.
  for (const uid of ["owner-a", "manager-a", "cashier-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      getDoc(doc(firestore, "tenants/tenant-a/shift_expectations/se_abc")),
    );
    await assertFails(
      setDoc(doc(firestore, "tenants/tenant-a/shift_expectations/se_forged"), {
        tenantId: "tenant-a",
        shiftId: "shift-a",
        businessDate: "2026-07-31",
        sales: 999999,
        transactions: 1,
        generation: "generation-one",
        needsVerification: false,
        verificationStatus: "variance",
        verifiedGeneration: "generation-one",
      }),
    );
  }

  // The difference itself is readable by management and writable by nobody, so
  // only the callable can clear one.
  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/reconciliation_anomalies/shift_abc": {
      tenantId: "tenant-a",
      shiftId: "shift-a",
      anomalyType: "shift_variance",
      salesVariance: -149.75,
      transactionVariance: -1,
      mutatesShift: false,
    },
  });
  const owner = authenticatedFirestore(testEnvironment, "owner-a");
  await assertSucceeds(
    getDoc(doc(owner, "tenants/tenant-a/reconciliation_anomalies/shift_abc")),
  );
  await assertFails(
    deleteDoc(doc(owner, "tenants/tenant-a/reconciliation_anomalies/shift_abc")),
  );
});
