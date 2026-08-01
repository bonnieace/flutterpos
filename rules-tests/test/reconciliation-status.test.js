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

const BUSINESS_DATE = "2026-07-31";
const EARLIER_DATE = "2026-07-30";

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

function intakePath(tenantId, businessDate) {
  return `tenants/${tenantId}/reconciliation_dirty_days/${businessDate}`;
}

function jobPath(tenantId, jobId) {
  return `tenants/${tenantId}/reconciliation_jobs/${jobId}`;
}

/** The record the metrics processor leaves behind for a regenerated day. */
function cleanIntake({ tenantId = "tenant-a", businessDate = BUSINESS_DATE } = {}) {
  return {
    tenantId,
    businessDate,
    status: "clean",
    revision: 3,
    processedRevision: 3,
    saleReceiptCount: 12,
    invalidLineCount: 0,
    lastSaleId: "co-9",
    metricGeneration: "a".repeat(40),
    lastReceiptAt: Timestamp.fromMillis(1785528000000),
    processedAt: Timestamp.fromMillis(1785550000000),
    updatedAt: Timestamp.fromMillis(1785550000000),
  };
}

/** The record the sale trigger writes before any run has published totals. */
function dirtyIntake({ tenantId = "tenant-a", businessDate = EARLIER_DATE } = {}) {
  return {
    tenantId,
    businessDate,
    status: "dirty",
    revision: 5,
    saleReceiptCount: 3,
    invalidLineCount: 1,
    lastSaleId: "co-4",
    lastReceiptAt: Timestamp.fromMillis(1785440000000),
    updatedAt: Timestamp.fromMillis(1785440000000),
  };
}

/** The exact job document the reconciliation writers create. */
function job({
  tenantId = "tenant-a",
  localDate = BUSINESS_DATE,
  source = "nightly",
  status = "completed",
  phase = "finalize",
} = {}) {
  return {
    tenantId,
    source,
    sourceKey: `${source}:${localDate}`,
    mode: "incremental",
    checkpointKind: "none",
    checkpointKey: localDate,
    localDate,
    requestedBy: `system:${source}`,
    status,
    phase,
    generation: 0,
    revision: 4,
    attemptCount: 1,
    consecutiveFailureCount: 0,
    rerunRequested: false,
    fullInitialized: true,
    metricsProcessed: 1,
    productsProcessed: 0,
    stockVarianceCount: 0,
    shiftsProcessed: 2,
    shiftVarianceCount: 0,
    authority: "canonical_tenant_data",
    mutatesStock: false,
    completedAt: Timestamp.fromMillis(1785550000000),
    createdAt: Timestamp.fromMillis(1785549000000),
    updatedAt: Timestamp.fromMillis(1785550000000),
  };
}

/**
 * Two business days in one business, plus a second business whose
 * reconciliation state must never be reached from the first.
 */
async function seedReconciliation() {
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
    [intakePath("tenant-a", BUSINESS_DATE)]: cleanIntake(),
    [intakePath("tenant-a", EARLIER_DATE)]: dirtyIntake(),
    [jobPath("tenant-a", "dirty_1785540000000")]: job({
      source: "sale_trigger",
      status: "queued",
      phase: "metrics",
    }),
    [jobPath("tenant-a", "rj_abc")]: job(),
    [jobPath("tenant-a", "rj_zzz")]: job({ localDate: EARLIER_DATE }),
    [intakePath("tenant-b", BUSINESS_DATE)]: cleanIntake({ tenantId: "tenant-b" }),
    [jobPath("tenant-b", "rj_abc")]: job({ tenantId: "tenant-b" }),
  });
}

/**
 * The exact page the client issues: one equality filter on the business date,
 * on the same ascending key order Firestore's automatic single-field index
 * already serves, so no composite index is involved.
 */
function runsPage(firestore, tenantId, businessDate, extra = []) {
  return query(
    collection(firestore, `tenants/${tenantId}/reconciliation_jobs`),
    where("localDate", "==", businessDate),
    ...extra,
    orderBy("__name__"),
    limit(21),
  );
}

test("management reads a day's state and the runs behind it", async () => {
  await seedReconciliation();

  for (const uid of ["manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const intake = await assertSucceeds(
      getDoc(doc(firestore, intakePath("tenant-a", BUSINESS_DATE))),
    );
    if (intake.data().status !== "clean") {
      throw new Error(`Unexpected intake record for ${uid}.`);
    }

    // Only that day's runs come back, and in ascending document-ID order.
    const page = await assertSucceeds(
      getDocs(runsPage(firestore, "tenant-a", BUSINESS_DATE)),
    );
    const ids = page.docs.map((entry) => entry.id).join(",");
    if (ids !== "dirty_1785540000000,rj_abc") {
      throw new Error(`Unexpected runs page for ${uid}: ${ids}`);
    }
  }
});

test("the runs page resumes from a document ID", async () => {
  await seedReconciliation();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  const first = await assertSucceeds(
    getDocs(
      query(
        collection(firestore, "tenants/tenant-a/reconciliation_jobs"),
        where("localDate", "==", BUSINESS_DATE),
        orderBy("__name__"),
        limit(1),
      ),
    ),
  );
  if (first.docs[0].id !== "dirty_1785540000000") {
    throw new Error(`Unexpected first run: ${first.docs[0].id}`);
  }

  // Unlike a collection-group page, this one already knows its collection
  // path, so the cursor is the bare document ID the client sends.
  const rest = await assertSucceeds(
    getDocs(
      query(
        collection(firestore, "tenants/tenant-a/reconciliation_jobs"),
        where("localDate", "==", BUSINESS_DATE),
        orderBy("__name__"),
        startAfter(first.docs[0].id),
        limit(21),
      ),
    ),
  );
  const ids = rest.docs.map((entry) => entry.id).join(",");
  if (ids !== "rj_abc") {
    throw new Error(`Unexpected second runs page: ${ids}`);
  }
});

test("a day the server has never seen still answers", async () => {
  await seedReconciliation();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  // A day with no sales has no intake record at all, and that absence is the
  // answer the surface reports. It is only reachable if the read is answered
  // rather than denied, which is why the rule touches no document field.
  const missing = await assertSucceeds(
    getDoc(doc(firestore, intakePath("tenant-a", "2026-07-01"))),
  );
  if (missing.exists()) {
    throw new Error("An unrecorded business day unexpectedly existed.");
  }
  const empty = await assertSucceeds(
    getDocs(runsPage(firestore, "tenant-a", "2026-07-01")),
  );
  if (!empty.empty) {
    throw new Error("An unrecorded business day unexpectedly had runs.");
  }
});

test("a cashier reads neither the state nor the runs", async () => {
  await seedReconciliation();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  // A cashier does not read business-wide revenue, so a cashier does not read
  // why business-wide revenue is what it is either.
  await assertFails(
    getDoc(doc(firestore, intakePath("tenant-a", BUSINESS_DATE))),
  );
  await assertFails(
    getDoc(doc(firestore, intakePath("tenant-a", "2026-07-01"))),
  );
  await assertFails(getDocs(runsPage(firestore, "tenant-a", BUSINESS_DATE)));
  await assertFails(
    getDocs(collection(firestore, "tenants/tenant-a/reconciliation_jobs")),
  );
});

test("no client may write or delete reconciliation state", async () => {
  await seedReconciliation();

  // A client that could write here could mark a day clean so its sales were
  // never aggregated, or clear the failure record of a run that never
  // succeeded. Reconciliation is requested through the callable instead.
  for (const uid of ["owner-a", "manager-a", "cashier-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      setDoc(doc(firestore, intakePath("tenant-a", BUSINESS_DATE)), cleanIntake()),
    );
    await assertFails(
      deleteDoc(doc(firestore, intakePath("tenant-a", BUSINESS_DATE))),
    );
    await assertFails(setDoc(doc(firestore, jobPath("tenant-a", "rj_forged")), job()));
    await assertFails(deleteDoc(doc(firestore, jobPath("tenant-a", "rj_abc"))));
  }
});

test("another business's reconciliation state is never reached", async () => {
  await seedReconciliation();
  const foreign = authenticatedFirestore(testEnvironment, "manager-b");

  await assertFails(
    getDoc(doc(foreign, intakePath("tenant-a", BUSINESS_DATE))),
  );
  await assertFails(getDocs(runsPage(foreign, "tenant-a", BUSINESS_DATE)));

  // Its own business still answers, so the denial is the boundary rather than
  // a broken rule.
  const own = await assertSucceeds(
    getDoc(doc(foreign, intakePath("tenant-b", BUSINESS_DATE))),
  );
  if (own.data().tenantId !== "tenant-b") {
    throw new Error("Unexpected own-business intake record.");
  }
  const runs = await assertSucceeds(
    getDocs(runsPage(foreign, "tenant-b", BUSINESS_DATE)),
  );
  if (runs.docs.map((entry) => entry.id).join(",") !== "rj_abc") {
    throw new Error("Unexpected own-business runs page.");
  }
});

test("the day filter is what the runs rule permits, not a wider scan", async () => {
  await seedReconciliation();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  // The role check touches no document field, so an unfiltered list is
  // permitted for a member of the business; the narrowing is the repository's
  // own, and it is proved here to return exactly the day it names.
  const earlier = await assertSucceeds(
    getDocs(runsPage(firestore, "tenant-a", EARLIER_DATE)),
  );
  const ids = earlier.docs.map((entry) => entry.id).join(",");
  if (ids !== "rj_zzz") {
    throw new Error(`Unexpected earlier-day runs page: ${ids}`);
  }
});

test("a non-member or deactivated identity reads nothing", async () => {
  await seedReconciliation();
  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
  });

  const outsider = authenticatedFirestore(testEnvironment, "outsider");
  await assertFails(
    getDoc(doc(outsider, intakePath("tenant-a", BUSINESS_DATE))),
  );
  await assertFails(getDocs(runsPage(outsider, "tenant-a", BUSINESS_DATE)));

  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/manager-a": {
      uid: "manager-a",
      role: "manager",
      status: "inactive",
    },
  });
  const deactivated = authenticatedFirestore(testEnvironment, "manager-a");
  await assertFails(
    getDoc(doc(deactivated, intakePath("tenant-a", BUSINESS_DATE))),
  );
  await assertFails(getDocs(runsPage(deactivated, "tenant-a", BUSINESS_DATE)));
});
