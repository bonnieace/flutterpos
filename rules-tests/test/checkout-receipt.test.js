import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  doc,
  getDoc,
  increment,
  serverTimestamp,
  writeBatch,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  openShiftDocuments,
  receiptDeviceCode,
  receiptNumber,
  seedDocuments,
} from "./support.js";

const PAYLOAD_HASH = "b".repeat(64);
const DEVICE_A = "dev-0123456789abcdef0123456789abcdef";
const DEVICE_B = "dev-fedcba9876543210fedcba9876543210";
const BUSINESS_DATE = "2026-07-29";

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

/** Two canonical cashiers who share one physical device. */
async function seedSharedDevice() {
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
    // One canonical shift per cashier, device, and business day used below.
    ...openShiftDocuments({
      shiftId: "shift-a",
      staffId: "cashier-a",
      deviceId: DEVICE_A,
      businessDate: BUSINESS_DATE,
    }),
    ...openShiftDocuments({
      shiftId: "shift-b",
      staffId: "cashier-b",
      deviceId: DEVICE_A,
      businessDate: BUSINESS_DATE,
    }),
    ...openShiftDocuments({
      shiftId: "shift-device-b",
      staffId: "cashier-a",
      deviceId: DEVICE_B,
      businessDate: BUSINESS_DATE,
    }),
    ...openShiftDocuments({
      shiftId: "shift-next-day",
      staffId: "cashier-a",
      deviceId: DEVICE_A,
      businessDate: "2026-07-30",
    }),
    "tenants/tenant-a/products/product-a": {
      name: "Coffee",
      quantity: 10,
      updatedAt: Timestamp.fromMillis(0),
    },
  });
}

/** The exact write set the checkout sync worker produces for one sale. */
function checkoutBatch(
  firestore,
  {
    checkoutId,
    soldById = "cashier-a",
    deviceId = DEVICE_A,
    businessDate = BUSINESS_DATE,
    sequence = 1,
    shiftId = "shift-a",
    sale = {},
  },
) {
  const batch = writeBatch(firestore);
  batch.set(doc(firestore, `tenants/tenant-a/sales/${checkoutId}`), {
    checkoutId,
    tenantId: "tenant-a",
    soldById,
    payloadHash: PAYLOAD_HASH,
    payloadSchemaVersion: 2,
    currency: "KES",
    businessDate,
    clientCreatedAtMs: 1785484800000,
    shiftId,
    deviceId,
    receiptNumber: receiptNumber(deviceId, businessDate, sequence),
    receiptSequence: sequence,
    items: [
      {
        productId: "product-a",
        name: "Coffee",
        quantity: 1,
        unitPriceMinor: 25000,
        unitPrice: 250,
        lineTotalMinor: 25000,
        lineTotal: 250,
      },
    ],
    subtotalMinor: 25000,
    subtotal: 250,
    discountMinor: 0,
    discount: 0,
    totalMinor: 25000,
    total: 250,
    createdAt: serverTimestamp(),
    ...sale,
  });
  batch.update(doc(firestore, "tenants/tenant-a/products/product-a"), {
    quantity: increment(-1),
    updatedAt: serverTimestamp(),
  });
  return batch;
}

async function storedSale(checkoutId) {
  let data;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const snapshot = await getDoc(
      doc(context.firestore(), `tenants/tenant-a/sales/${checkoutId}`),
    );
    data = snapshot.exists() ? snapshot.data() : undefined;
  });
  return data;
}

test("two cashiers on one device commit different receipt numbers", async () => {
  await seedSharedDevice();

  await assertSucceeds(
    checkoutBatch(authenticatedFirestore(testEnvironment, "cashier-a"), {
      checkoutId: "checkout-a",
      soldById: "cashier-a",
      sequence: 1,
    }).commit(),
  );
  await assertSucceeds(
    checkoutBatch(authenticatedFirestore(testEnvironment, "cashier-b"), {
      checkoutId: "checkout-b",
      soldById: "cashier-b",
      shiftId: "shift-b",
      sequence: 2,
    }).commit(),
  );

  const first = await storedSale("checkout-a");
  const second = await storedSale("checkout-b");
  if (first.receiptNumber === second.receiptNumber) {
    throw new Error("Two cashiers on one device shared a receipt number.");
  }
  if (first.soldById === second.soldById) {
    throw new Error("The sales did not record distinct cashier UIDs.");
  }
  if (first.receiptNumber !== `CT-${receiptDeviceCode(DEVICE_A)}-20260729-0001`) {
    throw new Error(`Unexpected receipt shape ${first.receiptNumber}.`);
  }
  if (first.checkoutId !== "checkout-a") {
    throw new Error("checkoutId is no longer the database identity.");
  }
});

test("receipt sequences stay independent across devices and business dates", async () => {
  await seedSharedDevice();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  await assertSucceeds(
    checkoutBatch(firestore, { checkoutId: "checkout-a", sequence: 1 }).commit(),
  );
  await assertSucceeds(
    checkoutBatch(firestore, {
      checkoutId: "checkout-other-device",
      deviceId: DEVICE_B,
      shiftId: "shift-device-b",
      sequence: 1,
    }).commit(),
  );
  await assertSucceeds(
    checkoutBatch(firestore, {
      checkoutId: "checkout-next-day",
      businessDate: "2026-07-30",
      shiftId: "shift-next-day",
      sequence: 1,
    }).commit(),
  );

  const receipts = new Set([
    (await storedSale("checkout-a")).receiptNumber,
    (await storedSale("checkout-other-device")).receiptNumber,
    (await storedSale("checkout-next-day")).receiptNumber,
  ]);
  if (receipts.size !== 3) {
    throw new Error("Independent devices or dates produced one receipt.");
  }
});

test("a receipt that disagrees with its own sale envelope is denied", async () => {
  await seedSharedDevice();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  const spoofed = [
    [
      "other-business-date",
      { receiptNumber: receiptNumber(DEVICE_A, "2026-07-28", 1) },
    ],
    ["other-sequence", { receiptSequence: 2 }],
    ["zero-sequence", { receiptSequence: 0 }],
    ["fractional-sequence", { receiptSequence: 1.5 }],
    ["unbounded-sequence", { receiptSequence: 1000000 }],
    ["string-sequence", { receiptSequence: "1" }],
  ];

  for (const [name, sale] of spoofed) {
    await assertFails(
      checkoutBatch(firestore, {
        checkoutId: `checkout-${name}`,
        sale,
      }).commit(),
    );
    if (await storedSale(`checkout-${name}`)) {
      throw new Error(`A denied ${name} receipt still created a sale.`);
    }
  }
});

test("a malformed, missing, or free-text receipt is denied", async () => {
  await seedSharedDevice();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  const malformed = [
    ["missing", { receiptNumber: null }],
    ["missing-sequence", { receiptSequence: null }],
    ["free-text", { receiptNumber: "receipt 1" }],
    ["wrong-prefix", { receiptNumber: "XX-A7F-20260729-0001" }],
    ["lowercase-device", { receiptNumber: "CT-a7f-20260729-0001" }],
    ["short-sequence", { receiptNumber: `CT-${receiptDeviceCode(DEVICE_A)}-20260729-1` }],
    ["numeric", { receiptNumber: 42 }],
    ["missing-device", { deviceId: null }],
    ["missing-business-date", { businessDate: null }],
    ["free-text-business-date", { businessDate: "29 July 2026" }],
  ];

  for (const [name, sale] of malformed) {
    await assertFails(
      checkoutBatch(firestore, {
        checkoutId: `checkout-${name}`,
        sale,
      }).commit(),
    );
    if (await storedSale(`checkout-${name}`)) {
      throw new Error(`A denied ${name} receipt still created a sale.`);
    }
  }
});

test("a committed receipt cannot be rewritten or replayed", async () => {
  await seedSharedDevice();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  await assertSucceeds(
    checkoutBatch(firestore, { checkoutId: "checkout-a", sequence: 1 }).commit(),
  );

  // The same document ID with a different receipt is an update, never a create.
  await assertFails(
    checkoutBatch(firestore, { checkoutId: "checkout-a", sequence: 9 }).commit(),
  );

  const stored = await storedSale("checkout-a");
  if (stored.receiptSequence !== 1) {
    throw new Error("A replayed batch rewrote the committed receipt.");
  }
});

test("the largest allowed sale still evaluates within the Rules budget", async () => {
  // Firestore caps one request at 1000 evaluated expressions. Sale-line
  // validation already checks 16 explicit positions, so the receipt rule must
  // leave room for the largest sale a client may submit.
  await seedSharedDevice();
  await seedDocuments(
    testEnvironment,
    Object.fromEntries(
      Array.from({ length: 16 }, (_, index) => [
        `tenants/tenant-a/products/product-${index}`,
        { name: `Product ${index}`, quantity: 10, updatedAt: Timestamp.fromMillis(0) },
      ]),
    ),
  );
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  const batch = writeBatch(firestore);
  batch.set(doc(firestore, "tenants/tenant-a/sales/checkout-full"), {
    checkoutId: "checkout-full",
    tenantId: "tenant-a",
    soldById: "cashier-a",
    payloadHash: PAYLOAD_HASH,
    payloadSchemaVersion: 2,
    currency: "KES",
    businessDate: BUSINESS_DATE,
    clientCreatedAtMs: 1785484800000,
    shiftId: "shift-a",
    deviceId: DEVICE_A,
    receiptNumber: receiptNumber(DEVICE_A, BUSINESS_DATE, 1),
    receiptSequence: 1,
    items: Array.from({ length: 16 }, (_, index) => ({
      productId: `product-${index}`,
      name: `Product ${index}`,
      quantity: index + 1,
      unitPriceMinor: 100,
      unitPrice: 1,
      lineTotalMinor: 100 * (index + 1),
      lineTotal: index + 1,
    })),
    subtotalMinor: 13600,
    subtotal: 136,
    discountMinor: 0,
    discount: 0,
    totalMinor: 13600,
    total: 136,
    createdAt: serverTimestamp(),
  });
  for (let index = 0; index < 16; index += 1) {
    batch.update(doc(firestore, `tenants/tenant-a/products/product-${index}`), {
      quantity: increment(-(index + 1)),
      updatedAt: serverTimestamp(),
    });
  }

  await assertSucceeds(batch.commit());

  if ((await storedSale("checkout-full")).items.length !== 16) {
    throw new Error("The maximum-size sale did not commit all 16 lines.");
  }
});

test("an inactive cashier cannot commit a well-formed receipt", async () => {
  await seedSharedDevice();
  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/cashier-a": {
      uid: "cashier-a",
      role: "cashier",
      status: "inactive",
    },
  });

  await assertFails(
    checkoutBatch(authenticatedFirestore(testEnvironment, "cashier-a"), {
      checkoutId: "checkout-a",
    }).commit(),
  );

  if (await storedSale("checkout-a")) {
    throw new Error("An inactive cashier created a receipted sale.");
  }
});
