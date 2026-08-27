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
    // Issued by a colleague; only management or that cashier may search it.
    "tenants/tenant-a/sales/co-2": saleDocument("co-2", 42, "user-b"),
  });
}

/** The daily ending page the Sales screen sends. */
function receiptEndingPage(firestore, sequence, soldById) {
  const constraints = [
    where("businessDate", "==", BUSINESS_DATE),
    where("receiptSequence", "==", sequence),
  ];
  if (soldById) constraints.push(where("soldById", "==", soldById));
  return query(
    collection(firestore, "tenants/tenant-a/sales"),
    ...constraints,
    orderBy(documentId()),
    limit(51),
  );
}

/** The compatibility full-number lookup, under the same staff scope. */
function exactReceiptPage(firestore, sequence, soldById) {
  const constraints = [
    where(
      "receiptNumber",
      "==",
      receiptNumber(DEVICE_A, BUSINESS_DATE, sequence),
    ),
  ];
  if (soldById) constraints.push(where("soldById", "==", soldById));
  return query(
    collection(firestore, "tenants/tenant-a/sales"),
    ...constraints,
    orderBy(documentId()),
    limit(51),
  );
}

test("management finds every till sharing a daily receipt ending", async () => {
  await seedSales();

  const firestore = authenticatedFirestore(testEnvironment, "manager-a");
  const page = await assertSucceeds(
    getDocs(receiptEndingPage(firestore, 42)),
  );
  const ids = page.docs.map((document) => document.id);
  if (ids.join(",") !== "co-2") {
    throw new Error(`Unexpected management receipt page: ${ids.join(",")}`);
  }
});

test("a cashier finds only receipts they issued", async () => {
  await seedSales();

  for (const [uid, sequence, expected] of [
    ["user-a", 1, "co-1"],
    ["user-b", 42, "co-2"],
  ]) {
    const firestore = authenticatedFirestore(testEnvironment, uid);
    const page = await assertSucceeds(
      getDocs(receiptEndingPage(firestore, sequence, uid)),
    );
    const ids = page.docs.map((document) => document.id);
    if (ids.join(",") !== expected) {
      throw new Error(`Unexpected own receipt page for ${uid}: ${ids.join(",")}`);
    }
  }
});

test("a cashier cannot run an unscoped or foreign receipt search", async () => {
  await seedSales();
  const firestore = authenticatedFirestore(testEnvironment, "user-a");

  await assertFails(getDocs(receiptEndingPage(firestore, 42)));
  await assertFails(getDocs(receiptEndingPage(firestore, 42, "user-b")));
  await assertFails(getDocs(exactReceiptPage(firestore, 42, "user-b")));

  // Searching a colleague's exact number under the caller's authorized scope
  // succeeds empty, so the result does not reveal that the colleague has it.
  const hidden = await assertSucceeds(
    getDocs(exactReceiptPage(firestore, 42, "user-a")),
  );
  if (!hidden.empty) throw new Error("A foreign receipt leaked to a cashier.");
});

test("an authorized empty receipt search is a first-class answer", async () => {
  await seedSales();
  const firestore = authenticatedFirestore(testEnvironment, "user-a");

  const page = await assertSucceeds(
    getDocs(receiptEndingPage(firestore, 999, "user-a")),
  );
  if (!page.empty) throw new Error("An unissued receipt matched a sale.");
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
  const ownPage = await assertSucceeds(
    getDocs(receiptEndingPage(firestore, 1, "user-a")),
  );
  if (ownPage.docs.some((document) => document.id === "co-9")) {
    throw new Error("A receipt lookup reached another business.");
  }
  await assertFails(
    getDocs(
      query(
        collection(firestore, "tenants/tenant-b/sales"),
        where("businessDate", "==", BUSINESS_DATE),
        where("receiptSequence", "==", 42),
        where("soldById", "==", "user-a"),
        orderBy(documentId()),
        limit(51),
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
    await assertFails(getDocs(receiptEndingPage(firestore, 42, uid)));
  }
});
