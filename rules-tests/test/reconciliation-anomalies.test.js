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
  setDoc,
  startAfter,
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

function anomalyPath(tenantId, anomalyId) {
  return `tenants/${tenantId}/reconciliation_anomalies/${anomalyId}`;
}

/** The record `jobs.ts` writes when a sale carried unusable lines. */
function saleAnomaly({ tenantId = "tenant-a" } = {}) {
  return {
    tenantId,
    sourceType: "sale",
    sourceId: "co-9",
    anomalyType: "invalid_sale_lines",
    invalidLineCount: 2,
    observedAt: Timestamp.fromMillis(1785549000000),
    createdAt: Timestamp.fromMillis(1785549000000),
  };
}

/** The record `processors.ts` writes when stock disagrees with its ledger. */
function stockAnomaly({ tenantId = "tenant-a" } = {}) {
  return {
    tenantId,
    productId: "product-a",
    jobId: "rj_abc",
    anomalyType: "stock_short_of_ledger",
    expectedQuantity: 10,
    observedQuantity: 7,
    variance: -3,
    mutatesStock: false,
    createdAt: Timestamp.fromMillis(1785549000000),
    updatedAt: Timestamp.fromMillis(1785550000000),
  };
}

/** The record `processors.ts` writes when a shift disagrees with its sales. */
function shiftAnomaly({ tenantId = "tenant-a" } = {}) {
  return {
    tenantId,
    shiftId: "shift-a",
    jobId: "rj_abc",
    anomalyType: "shift_variance",
    salesVariance: -12.5,
    transactionVariance: 2,
    mutatesShift: false,
    createdAt: Timestamp.fromMillis(1785549000000),
    updatedAt: Timestamp.fromMillis(1785550000000),
  };
}

/**
 * Three differences in one business, plus a second business whose differences
 * must never be reached from the first.
 */
async function seedAnomalies() {
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
    ...activeTenantDocuments({
      uid: "manager-b",
      tenantId: "tenant-b",
      role: "manager",
    }),
    [anomalyPath("tenant-a", "sale_aaa")]: saleAnomaly(),
    [anomalyPath("tenant-a", "shift_bbb")]: shiftAnomaly(),
    [anomalyPath("tenant-a", "stock_ccc")]: stockAnomaly(),
    [anomalyPath("tenant-b", "stock_ccc")]: stockAnomaly({ tenantId: "tenant-b" }),
  });
}

/**
 * The exact business-wide page the client issues: no filter at all, on the
 * ascending key order Firestore's automatic single-field index already serves.
 */
function anomalyPage(firestore, tenantId, extra = []) {
  return query(
    collection(firestore, `tenants/${tenantId}/reconciliation_anomalies`),
    ...extra,
    orderBy("__name__"),
    limit(21),
  );
}

test("management reads every difference recorded for the business", async () => {
  await seedAnomalies();

  for (const uid of ["manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const page = await assertSucceeds(
      getDocs(anomalyPage(firestore, "tenant-a")),
    );
    const ids = page.docs.map((entry) => entry.id).join(",");
    if (ids !== "sale_aaa,shift_bbb,stock_ccc") {
      throw new Error(`Unexpected anomaly page for ${uid}: ${ids}`);
    }
  }
});

test("the page narrows to one kind and resumes from a document ID", async () => {
  await seedAnomalies();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  // The exact narrowed page: one equality filter on the same ascending key
  // order, which is still the automatic single-field index shape.
  const narrowed = await assertSucceeds(
    getDocs(
      anomalyPage(firestore, "tenant-a", [
        where("anomalyType", "==", "stock_short_of_ledger"),
      ]),
    ),
  );
  if (narrowed.docs.map((entry) => entry.id).join(",") !== "stock_ccc") {
    throw new Error("Unexpected narrowed anomaly page.");
  }

  const first = await assertSucceeds(
    getDocs(
      query(
        collection(firestore, "tenants/tenant-a/reconciliation_anomalies"),
        orderBy("__name__"),
        limit(1),
      ),
    ),
  );
  if (first.docs[0].id !== "sale_aaa") {
    throw new Error(`Unexpected first anomaly: ${first.docs[0].id}`);
  }

  // This page already knows its collection, so the cursor is the bare document
  // ID rather than the whole path a collection-group page needs.
  const second = await assertSucceeds(
    getDocs(
      query(
        collection(firestore, "tenants/tenant-a/reconciliation_anomalies"),
        orderBy("__name__"),
        startAfter(first.docs[0].id),
        limit(1),
      ),
    ),
  );
  if (second.docs[0].id !== "shift_bbb") {
    throw new Error(`Unexpected second anomaly: ${second.docs[0].id}`);
  }
});

test("the page narrows to one product for the surface that answers for it", async () => {
  // The shape the product stock surface issues, so a manager standing where a
  // stock adjustment is recorded can see what reconciliation found there. One
  // equality filter on the same ascending key order, which is still the
  // automatic single-field index shape - a second filter beside it would need a
  // composite index, so the client deliberately never sends `anomalyType` with
  // this one. If that ever stopped being servable the emulator rejects it here
  // rather than a client failing in production.
  await seedAnomalies();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  const narrowed = await assertSucceeds(
    getDocs(
      anomalyPage(firestore, "tenant-a", [
        where("productId", "==", "product-a"),
      ]),
    ),
  );
  if (narrowed.docs.map((entry) => entry.id).join(",") !== "stock_ccc") {
    throw new Error("Unexpected product-narrowed anomaly page.");
  }

  // A product with nothing recorded against it answers with an empty page, which
  // is what lets that surface say nothing at all rather than reporting a failure.
  const none = await assertSucceeds(
    getDocs(
      anomalyPage(firestore, "tenant-a", [
        where("productId", "==", "product-z"),
      ]),
    ),
  );
  if (none.docs.length !== 0) throw new Error("Expected an empty product page.");

  // And a cashier cannot reach it, exactly as they cannot reach the unnarrowed
  // page: the product stock surface is management-only for the same reason.
  const cashier = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertFails(
    getDocs(
      anomalyPage(cashier, "tenant-a", [
        where("productId", "==", "product-a"),
      ]),
    ),
  );
});

test("a business with no differences answers rather than raising", async () => {
  // The role check touches no document field, so an empty collection - and an
  // anomaly that does not exist - both answer instead of failing evaluation.
  await seedAnomalies();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  const absent = await assertSucceeds(
    getDoc(doc(firestore, anomalyPath("tenant-a", "stock_missing"))),
  );
  if (absent.exists()) throw new Error("Expected an absent anomaly.");

  const page = await assertSucceeds(
    getDocs(
      anomalyPage(firestore, "tenant-a", [
        where("anomalyType", "==", "checkpoint_chain_invalid"),
      ]),
    ),
  );
  if (page.docs.length !== 0) throw new Error("Expected an empty page.");
});

test("a cashier reads no difference at all", async () => {
  // A cashier reads its own sales and shifts, but the differences behind
  // business-wide reporting are management information, exactly as the runs
  // that count them are.
  await seedAnomalies();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  await assertFails(getDocs(anomalyPage(firestore, "tenant-a")));
  await assertFails(getDoc(doc(firestore, anomalyPath("tenant-a", "sale_aaa"))));
});

test("another business's differences stay unreachable", async () => {
  await seedAnomalies();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  await assertFails(getDocs(anomalyPage(firestore, "tenant-b")));
  await assertFails(getDoc(doc(firestore, anomalyPath("tenant-b", "stock_ccc"))));
});

test("the open-difference count is read by management and written by nobody", async () => {
  // One document, recomputed by every completed run, so a launcher can badge a
  // figure without listing the differences to count them - those are keyed by
  // digest and can be neither ordered nor counted cheaply from a client.
  const summaryPath = (tenantId) =>
    `tenants/${tenantId}/reconciliation_summary/open_differences`;

  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier-a", role: "cashier" }),
    ...Object.fromEntries(
      [
        ["manager-a", "manager"],
        ["admin-a", "admin"],
        ["owner-a", "owner"],
      ].flatMap(([uid, role]) => [
        [
          `users/${uid}`,
          { accountType: "tenant_user", globalStatus: "active", membershipCount: 1 },
        ],
        [`tenants/tenant-a/staff/${uid}`, { uid, role, status: "active" }],
      ]),
    ),
    [summaryPath("tenant-a")]: {
      tenantId: "tenant-a",
      jobId: "rj_abc",
      openCount: 3,
      truncated: false,
      byType: { shift_tender_variance: 2, stock_short_of_ledger: 1 },
      countedAt: Timestamp.fromDate(new Date("2026-08-01T02:30:00Z")),
    },
  });

  // The same set that reads the differences it counts.
  for (const uid of ["owner-a", "admin-a", "manager-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertSucceeds(getDoc(doc(firestore, summaryPath("tenant-a"))));
  }

  const cashier = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertFails(getDoc(doc(cashier, summaryPath("tenant-a"))));

  // A client that could write here could report a shop's books clean.
  for (const uid of ["owner-a", "admin-a", "manager-a", "cashier-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      setDoc(doc(firestore, summaryPath("tenant-a")), { openCount: 0 }, { merge: true }),
    );
    await assertFails(deleteDoc(doc(firestore, summaryPath("tenant-a"))));
  }
});

test("no client may invent, amend, or erase a difference", async () => {
  // A client that could write here could invent a discrepancy, or erase the
  // only record of a real one.
  await seedAnomalies();

  for (const uid of ["manager-a", "owner-a", "cashier-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      setDoc(doc(firestore, anomalyPath("tenant-a", "stock_new")), stockAnomaly()),
    );
    await assertFails(
      setDoc(
        doc(firestore, anomalyPath("tenant-a", "stock_ccc")),
        { variance: 0 },
        { merge: true },
      ),
    );
    await assertFails(
      deleteDoc(doc(firestore, anomalyPath("tenant-a", "stock_ccc"))),
    );
  }
});
