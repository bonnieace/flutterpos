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
  receiptNumber,
  seedDocuments,
} from "./support.js";

const PAYLOAD_HASH = "c".repeat(64);
const DEVICE_A = "dev-0123456789abcdef0123456789abcdef";
const DEVICE_B = "dev-fedcba9876543210fedcba9876543210";
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

/** Two cashiers, one product, and one canonical shift for each cashier. */
async function seedShiftTenant() {
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
    ...openShiftDocuments({
      shiftId: "shift-a",
      staffId: "cashier-a",
      deviceId: DEVICE_A,
      businessDate: BUSINESS_DATE,
    }),
    ...openShiftDocuments({
      shiftId: "shift-colleague",
      staffId: "cashier-b",
      deviceId: DEVICE_A,
      businessDate: BUSINESS_DATE,
    }),
    ...openShiftDocuments({
      shiftId: "shift-yesterday",
      staffId: "cashier-a",
      deviceId: DEVICE_A,
      businessDate: "2026-07-30",
    }),
    ...openShiftDocuments({
      shiftId: "shift-other-device",
      staffId: "cashier-a",
      deviceId: DEVICE_B,
      businessDate: BUSINESS_DATE,
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
    shiftId = "shift-a",
    sequence = 1,
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

test("a sale bound to the cashier's own canonical shift commits", async () => {
  await seedShiftTenant();

  await assertSucceeds(
    checkoutBatch(authenticatedFirestore(testEnvironment, "cashier-a"), {
      checkoutId: "checkout-a",
    }).commit(),
  );

  if ((await storedSale("checkout-a")).shiftId !== "shift-a") {
    throw new Error("The committed sale is not attributed to its shift.");
  }
});

test("an unattributed or unknown shift is denied", async () => {
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");
  const denied = [
    ["missing", { shiftId: null }],
    ["empty", { shiftId: "" }],
    ["numeric", { shiftId: 7 }],
    ["unknown", { shiftId: "shift-never-opened" }],
  ];

  for (const [name, sale] of denied) {
    await assertFails(
      checkoutBatch(firestore, { checkoutId: `checkout-${name}`, sale }).commit(),
    );
    if (await storedSale(`checkout-${name}`)) {
      throw new Error(`A denied ${name} shift still created a sale.`);
    }
  }
});

test("a sale cannot be filed under a colleague's shift", async () => {
  await seedShiftTenant();

  await assertFails(
    checkoutBatch(authenticatedFirestore(testEnvironment, "cashier-a"), {
      checkoutId: "checkout-foreign",
      shiftId: "shift-colleague",
    }).commit(),
  );

  if (await storedSale("checkout-foreign")) {
    throw new Error("A foreign-shift sale was created.");
  }
});

test("a sale must share its shift's device and business day", async () => {
  await seedShiftTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier-a");

  // The receipt is internally valid in both cases; only the shift disagrees.
  await assertFails(
    checkoutBatch(firestore, {
      checkoutId: "checkout-other-day",
      shiftId: "shift-yesterday",
    }).commit(),
  );
  await assertFails(
    checkoutBatch(firestore, {
      checkoutId: "checkout-other-device",
      shiftId: "shift-other-device",
    }).commit(),
  );

  if (
    (await storedSale("checkout-other-day")) ||
    (await storedSale("checkout-other-device"))
  ) {
    throw new Error("A sale disagreeing with its shift was created.");
  }
});

test("a closed shift still accepts a late offline sale", async () => {
  // An offline sale may reach the server after its shift closed. Refusing it
  // would strand evidence the device can no longer correct, so reconciliation
  // reports the variance instead.
  await seedShiftTenant();
  await seedDocuments(testEnvironment, {
    ...openShiftDocuments({
      shiftId: "shift-a",
      staffId: "cashier-a",
      deviceId: DEVICE_A,
      businessDate: BUSINESS_DATE,
      status: "closed",
    }),
  });

  await assertSucceeds(
    checkoutBatch(authenticatedFirestore(testEnvironment, "cashier-a"), {
      checkoutId: "checkout-late",
    }).commit(),
  );
});

test("the largest allowed sale still evaluates within the Rules budget", async () => {
  // Firestore caps one request at 1000 evaluated expressions and bounds the
  // document access calls of a batched write. The shift lookup must leave room
  // for the largest sale a client may submit.
  await seedShiftTenant();
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
    throw new Error("The maximum-size shift-bound sale did not commit.");
  }
});
