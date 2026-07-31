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
  updateDoc,
  where,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
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

function shiftDocument({
  shiftId,
  staffId,
  status = "closed",
  withSummary = true,
}) {
  return {
    shiftId,
    tenantId: "tenant-a",
    staffId,
    deviceId: DEVICE_A,
    businessDate: BUSINESS_DATE,
    status,
    startTime: Timestamp.fromMillis(1785484800000),
    ...(status === "closed"
      ? {
          endTime: Timestamp.fromMillis(1785528000000),
          closingCashMinor: 125000,
          closingCash: 1250,
          ...(withSummary
            ? { totalSalesMinor: 98750, totalSales: 987.5, transactionCount: 3 }
            : {}),
        }
      : {}),
  };
}

/**
 * One business with two cashiers and a manager, holding the closed shifts a
 * history page reads: the caller's own, a colleague's, and one closed without
 * the sale-derived summary.
 */
async function seedShiftHistory() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier-a", role: "cashier" }),
    "users/cashier-b": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 1,
    },
    "tenants/tenant-a/staff/cashier-b": {
      uid: "cashier-b",
      role: "cashier",
      status: "active",
    },
    "users/manager-a": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 1,
    },
    "tenants/tenant-a/staff/manager-a": {
      uid: "manager-a",
      role: "manager",
      status: "active",
    },
    // The canonical owner of tenant-a, per activeTenantDocuments.
    "users/owner-a": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 1,
    },
    "tenants/tenant-a/staff/owner-a": {
      uid: "owner-a",
      role: "owner",
      status: "active",
    },
    "tenants/tenant-a/shifts/shift-1": shiftDocument({
      shiftId: "shift-1",
      staffId: "cashier-a",
    }),
    "tenants/tenant-a/shifts/shift-2": shiftDocument({
      shiftId: "shift-2",
      staffId: "cashier-a",
      withSummary: false,
    }),
    "tenants/tenant-a/shifts/shift-3": shiftDocument({
      shiftId: "shift-3",
      staffId: "cashier-b",
    }),
    "tenants/tenant-a/shifts/shift-open": shiftDocument({
      shiftId: "shift-open",
      staffId: "cashier-a",
      status: "open",
    }),
  });
}

/** The exact page the client's shift-history repository issues. */
function historyPage(firestore, { staffId, pageSize = 20 } = {}) {
  const constraints = [where("status", "==", "closed")];
  if (staffId) constraints.push(where("staffId", "==", staffId));
  return getDocs(
    query(
      collection(firestore, "tenants/tenant-a/shifts"),
      ...constraints,
      orderBy(documentId(), "desc"),
      limit(pageSize + 1),
    ),
  );
}

test("a cashier pages only its own closed shifts", async () => {
  await seedShiftHistory();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  const page = await assertSucceeds(
    historyPage(firestore, { staffId: "cashier-a" }),
  );
  const ids = page.docs.map((entry) => entry.id);
  if (ids.join(",") !== "shift-2,shift-1") {
    throw new Error(`Unexpected own history page: ${ids.join(",")}`);
  }
  // A shift closed without a summary is still readable; the client reports the
  // absence rather than hiding the shift.
  if ("totalSalesMinor" in page.docs[0].data()) {
    throw new Error("The summary-less shift was not the first result.");
  }
});

test("a cashier cannot widen the page beyond its own shifts", async () => {
  await seedShiftHistory();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  // No staffId constraint, so the query could return a colleague's shift.
  await assertFails(historyPage(firestore));
  await assertFails(historyPage(firestore, { staffId: "cashier-b" }));
  await assertFails(
    getDoc(doc(firestore, "tenants/tenant-a/shifts/shift-3")),
  );
  await assertSucceeds(
    getDoc(doc(firestore, "tenants/tenant-a/shifts/shift-1")),
  );
});

test("management pages every cashier's closed shifts", async () => {
  await seedShiftHistory();

  for (const uid of ["manager-a", "owner-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const page = await assertSucceeds(historyPage(firestore));
    const ids = page.docs.map((entry) => entry.id);
    if (ids.join(",") !== "shift-3,shift-2,shift-1") {
      throw new Error(`Unexpected ${uid} history page: ${ids.join(",")}`);
    }
    await assertSucceeds(
      getDoc(doc(firestore, "tenants/tenant-a/shifts/shift-3")),
    );
  }
});

test("a deactivated or foreign identity reads no shift history", async () => {
  await seedShiftHistory();
  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
  });

  const outsider = authenticatedFirestore(testEnvironment, "outsider");
  await assertFails(historyPage(outsider, { staffId: "outsider" }));
  await assertFails(
    getDoc(doc(outsider, "tenants/tenant-a/shifts/shift-1")),
  );

  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/cashier-a": {
      uid: "cashier-a",
      role: "cashier",
      status: "inactive",
    },
  });
  const deactivated = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertFails(historyPage(deactivated, { staffId: "cashier-a" }));
});

test("history stays read-only for every role", async () => {
  await seedShiftHistory();

  for (const uid of ["cashier-a", "manager-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      updateDoc(doc(firestore, "tenants/tenant-a/shifts/shift-1"), {
        closingCashMinor: 1,
        closingCash: 0.01,
      }),
    );
    await assertFails(
      deleteDoc(doc(firestore, "tenants/tenant-a/shifts/shift-1")),
    );
  }
});
