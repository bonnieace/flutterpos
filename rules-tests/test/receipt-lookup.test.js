import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  documentId,
  getDocs,
  limit,
  orderBy,
  query,
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

function saleDocument(saleId, sequence, soldById = "user-a") {
  return {
    checkoutId: saleId,
    tenantId: "tenant-a",
    soldById,
    shiftId: "shift-a",
    deviceId: DEVICE_A,
    businessDate: BUSINESS_DATE,
    receiptNumber: receiptNumber(DEVICE_A, BUSINESS_DATE, sequence),
    receiptSequence: sequence,
    payloadHash: "a".repeat(64),
    items: [{ productId: "product-1", quantity: 2 }],
    total: 10,
    createdAt: Timestamp.fromMillis(1785490000000),
  };
}

async function seedSales() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "user-a", role: "cashier" }),
    ...openShiftDocuments({ businessDate: BUSINESS_DATE }),
    ...Object.fromEntries(
      [
        ["user-b", "cashier"],
        ["manager-a", "manager"],
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
    "tenants/tenant-a/sales/co-1": saleDocument("co-1", 1),
    // Issued by a colleague; a receipt is looked up by whoever is at the till.
    "tenants/tenant-a/sales/co-2": saleDocument("co-2", 42, "user-b"),
  });
}

/** The exact page the receipt-lookup repository sends. */
function receiptPage(firestore, sequence) {
  return query(
    collection(firestore, "tenants/tenant-a/sales"),
    where(
      "receiptNumber",
      "==",
      receiptNumber(DEVICE_A, BUSINESS_DATE, sequence),
    ),
    orderBy(documentId()),
    limit(6),
  );
}

test("every active member looks a receipt up, including a colleague's", async () => {
  await seedSales();

  // The equality filter with the default ascending key order is served by the
  // automatic single-field index, so this page needs no composite index. If
  // that ever stops being true, the emulator rejects the query here rather than
  // the client failing in production.
  for (const uid of ["user-a", "user-b", "manager-a"]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const page = await assertSucceeds(getDocs(receiptPage(firestore, 42)));
    const ids = page.docs.map((document) => document.id);
    if (ids.join(",") !== "co-2") {
      throw new Error(`Unexpected receipt page for ${uid}: ${ids.join(",")}`);
    }
  }
});

test("a receipt with no sale answers empty rather than failing", async () => {
  await seedSales();
  const firestore = authenticatedFirestore(testEnvironment, "user-a");

  const page = await assertSucceeds(getDocs(receiptPage(firestore, 999)));
  if (!page.empty) {
    throw new Error("An unissued receipt unexpectedly matched a sale.");
  }
});

test("a receipt lookup never crosses into another business", async () => {
  await seedSales();
  await seedDocuments(testEnvironment, {
    "tenants/tenant-b": {
      name: "tenant-b",
      ownerUid: "owner-b",
      status: "active",
    },
    // The same receipt number, issued by a device in another business.
    "tenants/tenant-b/sales/co-9": {
      ...saleDocument("co-9", 42),
      tenantId: "tenant-b",
    },
  });

  const firestore = authenticatedFirestore(testEnvironment, "user-a");
  const page = await assertSucceeds(getDocs(receiptPage(firestore, 42)));
  if (page.docs.some((document) => document.id === "co-9")) {
    throw new Error("A receipt lookup reached another business.");
  }
  await assertFails(
    getDocs(
      query(
        collection(firestore, "tenants/tenant-b/sales"),
        where(
          "receiptNumber",
          "==",
          receiptNumber(DEVICE_A, BUSINESS_DATE, 42),
        ),
        orderBy(documentId()),
        limit(6),
      ),
    ),
  );
});

test("a non-member or deactivated identity looks nothing up", async () => {
  await seedSales();
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
    await assertFails(getDocs(receiptPage(firestore, 42)));
  }
});
