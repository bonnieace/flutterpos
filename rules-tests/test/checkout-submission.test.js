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
  seedDocuments,
} from "./support.js";

const PAYLOAD_HASH = "a".repeat(64);

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

async function seedCheckoutTenant() {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier", role: "cashier" }),
    "tenants/tenant-a/products/product-a": {
      name: "Coffee",
      quantity: 2,
      updatedAt: Timestamp.fromMillis(0),
    },
    "tenants/tenant-a/products/product-b": {
      name: "Tea",
      quantity: 0,
      updatedAt: Timestamp.fromMillis(0),
    },
    "tenants/tenant-b": {
      name: "tenant-b",
      ownerUid: "owner-b",
      status: "active",
    },
    "tenants/tenant-b/products/product-c": {
      name: "Water",
      quantity: 5,
      updatedAt: Timestamp.fromMillis(0),
    },
  });
}

function saleLine(productId, quantity, unitPriceMinor) {
  return {
    productId,
    name: productId,
    quantity,
    unitPriceMinor,
    unitPrice: unitPriceMinor / 100,
    lineTotalMinor: unitPriceMinor * quantity,
    lineTotal: (unitPriceMinor * quantity) / 100,
  };
}

function saleFields(checkoutId, overrides = {}) {
  return {
    checkoutId,
    tenantId: "tenant-a",
    soldById: "cashier",
    payloadHash: PAYLOAD_HASH,
    payloadSchemaVersion: 1,
    currency: "KES",
    businessDate: "2026-07-31",
    clientCreatedAtMs: 1785484800000,
    items: [saleLine("product-a", 2, 25000), saleLine("product-b", 1, 15000)],
    subtotalMinor: 65000,
    subtotal: 650,
    discountMinor: 0,
    discount: 0,
    totalMinor: 65000,
    total: 650,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

/** Builds the exact atomic write set produced by the checkout sync worker. */
function checkoutBatch(
  firestore,
  {
    checkoutId = "checkout-a",
    documentId = checkoutId,
    sale = {},
    decrements = [
      ["tenants/tenant-a/products/product-a", -2],
      ["tenants/tenant-a/products/product-b", -1],
    ],
  } = {},
) {
  const batch = writeBatch(firestore);
  batch.set(
    doc(firestore, `tenants/tenant-a/sales/${documentId}`),
    saleFields(checkoutId, sale),
  );
  for (const [path, delta] of decrements) {
    batch.update(doc(firestore, path), {
      quantity: increment(delta),
      updatedAt: serverTimestamp(),
    });
  }
  return batch;
}

async function storedQuantity(path) {
  let quantity;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const snapshot = await getDoc(doc(context.firestore(), path));
    quantity = snapshot.exists() ? snapshot.data().quantity : undefined;
  });
  return quantity;
}

async function saleExists(documentId) {
  let exists;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const snapshot = await getDoc(
      doc(context.firestore(), `tenants/tenant-a/sales/${documentId}`),
    );
    exists = snapshot.exists();
  });
  return exists;
}

test("one checkout batch creates the deterministic sale and decrements exact tenant stock", async () => {
  await seedCheckoutTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");

  await assertSucceeds(checkoutBatch(firestore).commit());

  const sale = await getDoc(
    doc(firestore, "tenants/tenant-a/sales/checkout-a"),
  );
  if (sale.data().payloadHash !== PAYLOAD_HASH) {
    throw new Error("The committed sale did not retain its exact payload hash.");
  }
  if (!(sale.data().createdAt instanceof Timestamp)) {
    throw new Error("The committed sale did not receive a server timestamp.");
  }
  if (await storedQuantity("tenants/tenant-a/products/product-a") !== 0) {
    throw new Error("The first product stock decrement did not apply exactly.");
  }
  if (await storedQuantity("tenants/tenant-a/products/product-b") !== -1) {
    throw new Error("A sale below zero stock did not produce signed stock.");
  }
});

test("a replayed checkout batch cannot rewrite the immutable sale or stock", async () => {
  await seedCheckoutTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");
  await assertSucceeds(checkoutBatch(firestore).commit());

  await assertFails(checkoutBatch(firestore).commit());

  if (await storedQuantity("tenants/tenant-a/products/product-a") !== 0) {
    throw new Error("A replayed checkout batch changed committed stock.");
  }
});

test("a checkout batch cannot decrement another tenant's product", async () => {
  await seedCheckoutTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");

  await assertFails(
    checkoutBatch(firestore, {
      checkoutId: "checkout-cross-tenant",
      decrements: [
        ["tenants/tenant-a/products/product-a", -2],
        ["tenants/tenant-b/products/product-c", -1],
      ],
    }).commit(),
  );

  if (await saleExists("checkout-cross-tenant")) {
    throw new Error("A denied cross-tenant batch still created its sale.");
  }
  if (await storedQuantity("tenants/tenant-a/products/product-a") !== 2) {
    throw new Error("A denied cross-tenant batch still changed local stock.");
  }
  if (await storedQuantity("tenants/tenant-b/products/product-c") !== 5) {
    throw new Error("A denied cross-tenant batch changed foreign stock.");
  }
});

test("a checkout batch cannot raise stock or write a non-decrementing product", async () => {
  await seedCheckoutTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");

  await assertFails(
    checkoutBatch(firestore, {
      checkoutId: "checkout-increase",
      decrements: [["tenants/tenant-a/products/product-a", 2]],
    }).commit(),
  );
  await assertFails(
    checkoutBatch(firestore, {
      checkoutId: "checkout-unchanged",
      decrements: [["tenants/tenant-a/products/product-a", 0]],
    }).commit(),
  );

  if (await storedQuantity("tenants/tenant-a/products/product-a") !== 2) {
    throw new Error("A denied stock write still changed product quantity.");
  }
});

test("a checkout batch cannot spoof the sale identity or envelope", async () => {
  await seedCheckoutTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");
  const spoofed = [
    ["document-id", { checkoutId: "checkout-a", documentId: "checkout-other" }],
    ["tenant", { checkoutId: "checkout-tenant", sale: { tenantId: "tenant-b" } }],
    ["cashier", { checkoutId: "checkout-cashier", sale: { soldById: "owner-a" } }],
    [
      "client-created-time",
      {
        checkoutId: "checkout-clock",
        sale: { createdAt: Timestamp.fromMillis(0) },
      },
    ],
    ["hash", { checkoutId: "checkout-hash", sale: { payloadHash: "" } }],
    ["items", { checkoutId: "checkout-items", sale: { items: [] } }],
  ];

  for (const [name, options] of spoofed) {
    await assertFails(checkoutBatch(firestore, options).commit());
    if (await storedQuantity("tenants/tenant-a/products/product-a") !== 2) {
      throw new Error(`A denied ${name} batch still changed product stock.`);
    }
  }
});

test("an inactive canonical cashier cannot submit a checkout batch", async () => {
  await seedCheckoutTenant();
  await seedDocuments(testEnvironment, {
    "tenants/tenant-a/staff/cashier": {
      uid: "cashier",
      role: "cashier",
      status: "inactive",
    },
  });
  const firestore = authenticatedFirestore(testEnvironment, "cashier");

  await assertFails(checkoutBatch(firestore).commit());

  if (await saleExists("checkout-a")) {
    throw new Error("An inactive cashier created a canonical sale.");
  }
});
