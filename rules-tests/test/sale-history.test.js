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

function saleDocument({ saleId, soldById, shiftId, sequence }) {
  return {
    checkoutId: saleId,
    tenantId: "tenant-a",
    soldById,
    payloadHash: "a".repeat(64),
    payloadSchemaVersion: 1,
    currency: "KES",
    businessDate: BUSINESS_DATE,
    clientCreatedAtMs: 1785484800000,
    shiftId,
    deviceId: DEVICE_A,
    receiptNumber: receiptNumber(DEVICE_A, BUSINESS_DATE, sequence),
    receiptSequence: sequence,
    items: [
      {
        productId: "product-1",
        name: "Tusker",
        quantity: 2,
        unitPriceMinor: 500,
        lineTotalMinor: 1000,
      },
    ],
    subtotalMinor: 1000,
    subtotal: 10,
    discountMinor: 100,
    discount: 1,
    totalMinor: 900,
    total: 9,
    createdAt: Timestamp.fromMillis(1785500000000),
  };
}

/** One business, two cashiers, one manager, and sales from two shifts. */
async function seedSaleHistory() {
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
    "tenants/tenant-a/sales/co-1": saleDocument({
      saleId: "co-1",
      soldById: "cashier-a",
      shiftId: "shift-a",
      sequence: 1,
    }),
    "tenants/tenant-a/sales/co-2": saleDocument({
      saleId: "co-2",
      soldById: "cashier-a",
      shiftId: "shift-a",
      sequence: 2,
    }),
    "tenants/tenant-a/sales/co-3": saleDocument({
      saleId: "co-3",
      soldById: "cashier-b",
      shiftId: "shift-b",
      sequence: 3,
    }),
  });
}

/** The exact pages the client's sale-history repository issues. */
function salePage(firestore, { shiftId, soldById, pageSize = 20 } = {}) {
  const constraints = [];
  if (shiftId) constraints.push(where("shiftId", "==", shiftId));
  if (soldById) constraints.push(where("soldById", "==", soldById));
  return getDocs(
    query(
      collection(firestore, "tenants/tenant-a/sales"),
      ...constraints,
      orderBy(documentId(), "desc"),
      limit(pageSize + 1),
    ),
  );
}

test("a cashier pages the sales of one shift, newest first", async () => {
  await seedSaleHistory();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  const page = await assertSucceeds(salePage(firestore, { shiftId: "shift-a" }));
  const ids = page.docs.map((entry) => entry.id);
  if (ids.join(",") !== "co-2,co-1") {
    throw new Error(`Unexpected shift sale page: ${ids.join(",")}`);
  }
});

test("a cashier pages its own sales across shifts", async () => {
  await seedSaleHistory();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  const page = await assertSucceeds(
    salePage(firestore, { soldById: "cashier-a" }),
  );
  if (page.docs.length !== 2) {
    throw new Error(`Unexpected own sale page size: ${page.docs.length}`);
  }
});

test("a sale stays a shared business record for every active member", async () => {
  await seedSaleHistory();
  const colleague = authenticatedFirestore(testEnvironment, "cashier-b");

  // This is the deliberate decision, not an oversight: a receipt lookup, a
  // return against a colleague's sale, and fail-closed confirmation of a
  // deterministic sale path all need the sale to be readable business-wide.
  // Narrowing it to soldById would have to change these three assertions.
  await assertSucceeds(getDoc(doc(colleague, "tenants/tenant-a/sales/co-1")));
  await assertSucceeds(salePage(colleague, { shiftId: "shift-a" }));
  // Every page carries at least one equality filter: Firestore refuses a
  // descending scan of a whole collection by key, so the repository boundary
  // refuses to build one.
  await assertSucceeds(
    salePage(authenticatedFirestore(testEnvironment, "manager-a"), {
      soldById: "cashier-a",
    }),
  );

  // An absent sale must still answer, so an unacknowledged submission can be
  // settled instead of retried forever.
  const missing = await assertSucceeds(
    getDoc(doc(colleague, "tenants/tenant-a/sales/co-never-written")),
  );
  if (missing.exists()) throw new Error("An absent sale unexpectedly existed.");
});

test("an inactive or non-member identity reads no sale", async () => {
  await seedSaleHistory();
  await seedDocuments(testEnvironment, {
    "users/outsider": {
      accountType: "tenant_user",
      globalStatus: "active",
      membershipCount: 0,
    },
  });

  const outsider = authenticatedFirestore(testEnvironment, "outsider");
  await assertFails(getDoc(doc(outsider, "tenants/tenant-a/sales/co-1")));
  await assertFails(salePage(outsider, { shiftId: "shift-a" }));
  await assertFails(
    getDoc(doc(outsider, "tenants/tenant-a/sales/co-never-written")),
  );

  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/cashier-a": {
      uid: "cashier-a",
      role: "cashier",
      status: "inactive",
    },
  });
  const deactivated = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertFails(getDoc(doc(deactivated, "tenants/tenant-a/sales/co-1")));
  await assertFails(salePage(deactivated, { soldById: "cashier-a" }));
});

test("a recorded sale is immutable for every role", async () => {
  await seedSaleHistory();

  for (const uid of ["cashier-a", "manager-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    await assertFails(
      updateDoc(doc(firestore, "tenants/tenant-a/sales/co-1"), {
        totalMinor: 1,
        total: 0.01,
      }),
    );
    await assertFails(
      deleteDoc(doc(firestore, "tenants/tenant-a/sales/co-1")),
    );
  }
});
