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

const PAYLOAD_HASH = "a".repeat(64);
const DEVICE_ID = "dev-0123456789abcdef0123456789abcdef";

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
    ...openShiftDocuments({
      staffId: "cashier",
      deviceId: DEVICE_ID,
      businessDate: "2026-07-31",
    }),
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
  const fields = {
    checkoutId,
    tenantId: "tenant-a",
    soldById: "cashier",
    payloadHash: PAYLOAD_HASH,
    payloadSchemaVersion: 2,
    tender: "cash",
    currency: "KES",
    businessDate: "2026-07-31",
    clientCreatedAtMs: 1785484800000,
    shiftId: "shift-a",
    deviceId: DEVICE_ID,
    receiptNumber: receiptNumber(DEVICE_ID, "2026-07-31", 42),
    receiptSequence: 42,
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
  // An override of `undefined` means the field is absent from the write, which
  // is how a schema v1 sale omits `tender` entirely.
  for (const [field, value] of Object.entries(fields)) {
    if (value === undefined) delete fields[field];
  }
  return fields;
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

test("a schema v2 sale may record any of the three modelled tenders", async () => {
  await seedCheckoutTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");

  for (const tender of ["cash", "mpesa", "card"]) {
    await assertSucceeds(
      checkoutBatch(firestore, {
        checkoutId: `checkout-${tender}`,
        decrements: [["tenants/tenant-a/products/product-a", -1]],
        sale: { tender },
      }).commit(),
    );
  }
});

// **A v2 sale may name no tender at all, and that is an answer.** The register
// does not preselect a payment method, so a cashier who was never told how the
// customer paid saves a sale that names none; `setSaleTender` fills it in
// afterwards, once. An absent key is the silence. A key that is *present* and
// names something unmodelled is still denied, below - that is a corrupt record
// rather than an unanswered question.
test("a schema v2 sale may record no tender at all", async () => {
  await seedCheckoutTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");

  await assertSucceeds(
    checkoutBatch(firestore, {
      checkoutId: "checkout-tender-unanswered",
      sale: { tender: undefined },
    }).commit(),
  );

  if (!(await saleExists("checkout-tender-unanswered"))) {
    throw new Error("A sale naming no tender was not written.");
  }
});

// The tender is the cashier's assertion, but an unconstrained string would not
// even be evidence of that: the `sales` create rule does not freeze its key set
// with `hasOnly`, so without this check a client could write anything at all.
test("a schema v2 sale cannot record an unmodelled tender", async () => {
  await seedCheckoutTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");
  const refused = [
    ["empty", { tender: "" }],
    ["capitalised", { tender: "Cash" }],
    ["padded", { tender: " cash" }],
    ["unmodelled", { tender: "cheque" }],
    ["numeric", { tender: 1 }],
    ["boolean", { tender: true }],
    ["list", { tender: ["cash"] }],
    ["map", { tender: { method: "cash" } }],
    ["null", { tender: null }],
  ];

  for (const [name, sale] of refused) {
    await assertFails(
      checkoutBatch(firestore, {
        checkoutId: `checkout-tender-${name}`,
        sale,
      }).commit(),
    );
    if (await saleExists(`checkout-tender-${name}`)) {
      throw new Error(`A ${name} tender was accepted as a canonical sale.`);
    }
    if (await storedQuantity("tenants/tenant-a/products/product-a") !== 2) {
      throw new Error(`A denied ${name} tender batch still changed stock.`);
    }
  }
});

const CUSTOMER_ID = `cu_${"0123456789abcdef".repeat(2)}01234567`;

// **A walk-in names nobody, and every earlier build sells as a walk-in.** The
// three customer fields are additive, so the absence of all three is the shape
// every sale written before customers existed already has.
test("a sale may name the customer it was for, with or without a KRA PIN", async () => {
  await seedCheckoutTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");

  await assertSucceeds(
    checkoutBatch(firestore, {
      checkoutId: "checkout-customer",
      decrements: [["tenants/tenant-a/products/product-a", -1]],
      sale: { customerId: CUSTOMER_ID, customerName: "Jane Wanjiku" },
    }).commit(),
  );
  await assertSucceeds(
    checkoutBatch(firestore, {
      checkoutId: "checkout-customer-pin",
      decrements: [["tenants/tenant-a/products/product-a", -1]],
      sale: {
        customerId: CUSTOMER_ID,
        customerName: "Jane Wanjiku",
        customerKraPin: "A012345678Z",
      },
    }).commit(),
  );
});

// **The customer document is not read.** A customer added at the till with no
// signal reaches the server through the callable queue, and the sale through the
// outbox, in whichever order the network allows; nothing seeded here names this
// customer, and the sale still commits.
test("a sale naming a customer the server has not received yet still commits", async () => {
  await seedCheckoutTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");

  await assertSucceeds(
    checkoutBatch(firestore, {
      checkoutId: "checkout-customer-unseen",
      sale: { customerId: CUSTOMER_ID, customerName: "Not Yet Synced" },
    }).commit(),
  );
});

// #105: v1 stayed accepted so a device holding an unsubmitted v1 draft across
// the upgrade could still commit it - its payload hash covers the whole
// payload, so migrating the draft would break the hash the server sale is
// matched against. SIT clears app data instead, so there is no such draft.
test("a schema v1 sale is refused, with or without a tender", async () => {
  await seedCheckoutTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");

  for (const [name, tender] of [["none", undefined], ["cash", "cash"]]) {
    const checkoutId = `checkout-v1-${name}`;
    await assertFails(
      checkoutBatch(firestore, {
        checkoutId,
        decrements: [["tenants/tenant-a/products/product-a", -1]],
        sale: { payloadSchemaVersion: 1, tender },
      }).commit(),
    );
    if (await saleExists(checkoutId)) {
      throw new Error(`A schema v1 sale was accepted (${name}).`);
    }
  }
});

// A sale that does not say which contract it was written under cannot be
// checked against one, so the version itself is now mandatory.
test("a sale cannot claim an unsupported or untyped payload schema version", async () => {
  await seedCheckoutTenant();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");
  const refused = [
    ["future", { payloadSchemaVersion: 3 }],
    ["zero", { payloadSchemaVersion: 0 }],
    ["string", { payloadSchemaVersion: "2" }],
    ["missing", { payloadSchemaVersion: undefined }],
  ];

  for (const [name, sale] of refused) {
    await assertFails(
      checkoutBatch(firestore, {
        checkoutId: `checkout-version-${name}`,
        sale,
      }).commit(),
    );
    if (await saleExists(`checkout-version-${name}`)) {
      throw new Error(`A ${name} schema version was accepted.`);
    }
  }
});

// Firestore caps one request at 1000 evaluated expressions, and the tender
// check is new work on the most expensive rule in this file. The v1 budget is
// already proved by checkout-receipt and shift-sale-attribution; this proves
// the v2 branch, which evaluates two more terms, on the largest legal sale.
test("the largest allowed schema v2 sale still evaluates within the Rules budget", async () => {
  await seedCheckoutTenant();
  await seedDocuments(
    testEnvironment,
    Object.fromEntries(
      Array.from({ length: 16 }, (_, index) => [
        `tenants/tenant-a/products/product-${index}`,
        {
          name: `Product ${index}`,
          quantity: 100,
          updatedAt: Timestamp.fromMillis(0),
        },
      ]),
    ),
  );
  const firestore = authenticatedFirestore(testEnvironment, "cashier");
  const batch = writeBatch(firestore);
  batch.set(
    doc(firestore, "tenants/tenant-a/sales/checkout-full"),
    saleFields("checkout-full", {
      tender: "card",
      // A full basket for a named customer is the largest sale a till now
      // writes. The rule does not shape these fields precisely because shaping
      // them took this sale over the budget - see `firestore.rules`.
      customerId: CUSTOMER_ID,
      customerName: "Jane Wanjiku",
      customerKraPin: "A012345678Z",
      items: Array.from({ length: 16 }, (_, index) =>
        saleLine(`product-${index}`, index + 1, 100),
      ),
      subtotalMinor: 13600,
      subtotal: 136,
      totalMinor: 13600,
      total: 136,
    }),
  );
  for (let index = 0; index < 16; index += 1) {
    batch.update(doc(firestore, `tenants/tenant-a/products/product-${index}`), {
      quantity: increment(-(index + 1)),
      updatedAt: serverTimestamp(),
    });
  }

  await assertSucceeds(batch.commit());
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
