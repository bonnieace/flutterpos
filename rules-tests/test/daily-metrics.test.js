import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  seedDocuments,
} from "./support.js";

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

/** The exact document the reconciliation processor regenerates. */
function metricsDocument(businessDate = BUSINESS_DATE) {
  return {
    tenantId: "tenant-a",
    businessDate,
    sales: 1250.5,
    profit: 430.25,
    transactions: 12,
    transactionCount: 12,
    shiftCount: 2,
    incompleteCostLineCount: 0,
    metricGeneration: "a".repeat(40),
    sourceDirtyRevision: 3,
    regeneratedAt: Timestamp.fromMillis(1785550000000),
    updatedAt: Timestamp.fromMillis(1785550000000),
  };
}

async function seedMetrics() {
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
    [`tenants/tenant-a/daily_metrics/${BUSINESS_DATE}`]: metricsDocument(),
  });
}

test("management reads the regenerated daily metrics", async () => {
  await seedMetrics();

  for (const uid of ["manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const snapshot = await assertSucceeds(
      getDoc(doc(firestore, `tenants/tenant-a/daily_metrics/${BUSINESS_DATE}`)),
    );
    if (snapshot.data().transactions !== 12) {
      throw new Error(`Unexpected metrics for ${uid}.`);
    }
    await assertSucceeds(
      getDocs(collection(firestore, "tenants/tenant-a/daily_metrics")),
    );
  }
});

test("a day that has not been reconciled still answers", async () => {
  await seedMetrics();
  const firestore = authenticatedFirestore(testEnvironment, "manager-a");

  // Today is normally unreconciled; the summary reports it as pending, which
  // is only possible if the read is answered rather than denied.
  const snapshot = await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/daily_metrics/2026-08-01")),
  );
  if (snapshot.exists()) {
    throw new Error("An unreconciled day unexpectedly existed.");
  }
});

test("a cashier does not read business-wide revenue", async () => {
  await seedMetrics();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  await assertFails(
    getDoc(doc(firestore, `tenants/tenant-a/daily_metrics/${BUSINESS_DATE}`)),
  );
  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-a/daily_metrics/2026-08-01")),
  );
  await assertFails(
    getDocs(collection(firestore, "tenants/tenant-a/daily_metrics")),
  );
});

test("no client may write or delete a daily metric", async () => {
  await seedMetrics();

  for (const uid of ["owner-a", "manager-a", "cashier-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      setDoc(
        doc(firestore, `tenants/tenant-a/daily_metrics/${BUSINESS_DATE}`),
        metricsDocument(),
      ),
    );
    await assertFails(
      deleteDoc(
        doc(firestore, `tenants/tenant-a/daily_metrics/${BUSINESS_DATE}`),
      ),
    );
  }
});

test("a non-member or deactivated identity reads no metrics", async () => {
  await seedMetrics();
  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
  });

  const outsider = authenticatedFirestore(testEnvironment, "outsider");
  await assertFails(
    getDoc(doc(outsider, `tenants/tenant-a/daily_metrics/${BUSINESS_DATE}`)),
  );

  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/manager-a": {
      uid: "manager-a",
      role: "manager",
      status: "inactive",
    },
  });
  const deactivated = authenticatedFirestore(testEnvironment, "manager-a");
  await assertFails(
    getDoc(doc(deactivated, `tenants/tenant-a/daily_metrics/${BUSINESS_DATE}`)),
  );
});
