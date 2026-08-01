import { after, afterEach, before, test } from "node:test";

import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
  Timestamp,
  deleteDoc,
  doc,
  getDoc,
  increment,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

import {
  activeTenantDocuments,
  authenticatedFirestore,
  createRulesTestEnvironment,
  openShiftDocuments,
  receiptNumber,
  seedDocuments,
} from "./support.js";

let testEnvironment;

before(async () => {
  testEnvironment = await createRulesTestEnvironment();
});

afterEach(async () => {
  if (testEnvironment) {
    await testEnvironment.clearFirestore();
  }
});

after(async () => {
  if (testEnvironment) {
    await testEnvironment.cleanup();
  }
});

async function seedCashierAndProduct(quantity = 2) {
  await seedDocuments(testEnvironment, {
    ...activeTenantDocuments({ uid: "cashier", role: "cashier" }),
    ...openShiftDocuments({
      staffId: "cashier",
      deviceId: DEVICE_ID,
      businessDate: BUSINESS_DATE,
    }),
    "tenants/tenant-a/products/product-a": {
      name: "Coffee",
      quantity,
      updatedAt: Timestamp.fromMillis(0),
    },
  });
}

const DEVICE_ID = "dev-0123456789abcdef0123456789abcdef";
const BUSINESS_DATE = "2026-07-31";

function sale(checkoutId, overrides = {}) {
  return {
    checkoutId,
    tenantId: "tenant-a",
    soldById: "cashier",
    payloadHash: `sha256:${checkoutId}`,
    // A sale must now say which payload contract it was written under, and a
    // v2 sale must name the tender the cashier selected.
    payloadSchemaVersion: 2,
    tender: "cash",
    createdAt: serverTimestamp(),
    businessDate: BUSINESS_DATE,
    shiftId: "shift-a",
    deviceId: DEVICE_ID,
    receiptNumber: receiptNumber(DEVICE_ID, BUSINESS_DATE, 1),
    receiptSequence: 1,
    items: [{ productId: "product-a", quantity: 1 }],
    ...overrides,
  };
}

test("direct product writes allow only a strict integer stock decrease plus server updatedAt", async () => {
  await seedCashierAndProduct(2);
  const firestore = authenticatedFirestore(testEnvironment, "cashier");
  const product = doc(firestore, "tenants/tenant-a/products/product-a");

  await assertSucceeds(
    updateDoc(product, {
      quantity: increment(-5),
      updatedAt: serverTimestamp(),
    }),
  );
  const snapshot = await assertSucceeds(getDoc(product));
  if (snapshot.data().quantity !== -3) {
    throw new Error("A permitted negative increment did not produce signed stock.");
  }

  await assertFails(
    updateDoc(product, {
      quantity: increment(1),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(product, {
      quantity: increment(0),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(product, {
      quantity: -3.5,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(product, {
      name: "Tampered Coffee",
      quantity: -4,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(product, {
      quantity: -4,
      updatedAt: Timestamp.fromMillis(0),
    }),
  );
  await assertFails(updateDoc(product, { quantity: -4 }));
});

test("a valid sale uses its deterministic checkout ID and is immutable", async () => {
  await seedCashierAndProduct();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");
  const saleReference = doc(
    firestore,
    "tenants/tenant-a/sales/checkout-valid",
  );
  const validSale = sale("checkout-valid");

  await assertSucceeds(setDoc(saleReference, validSale));
  await assertFails(setDoc(saleReference, validSale));
  await assertFails(updateDoc(saleReference, { payloadHash: "replacement" }));
  await assertFails(deleteDoc(saleReference));
});

test("sale identity and server-owned envelope fields cannot be spoofed", async () => {
  await seedCashierAndProduct();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");
  const invalidSales = [
    ["wrong-document-id", sale("different-checkout-id")],
    ["wrong-tenant", sale("wrong-tenant", { tenantId: "tenant-b" })],
    ["wrong-cashier", sale("wrong-cashier", { soldById: "other-user" })],
    ["non-string-hash", sale("non-string-hash", { payloadHash: 123 })],
    ["empty-hash", sale("empty-hash", { payloadHash: "" })],
    [
      "client-created-time",
      sale("client-created-time", { createdAt: Timestamp.fromMillis(0) }),
    ],
  ];

  // A sale carrying no payload schema version cannot be checked against any
  // contract, so it is refused rather than accepted as an implicit v1.
  const noVersion = sale("no-schema-version");
  delete noVersion.payloadSchemaVersion;
  delete noVersion.tender;
  invalidSales.push(["no-schema-version", noVersion]);

  for (const [documentId, data] of invalidSales) {
    await assertFails(
      setDoc(doc(firestore, `tenants/tenant-a/sales/${documentId}`), data),
    );
  }
});

test("every sale line requires a non-empty product ID and positive integer quantity", async () => {
  await seedCashierAndProduct();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");
  const missingItems = sale("missing-items");
  delete missingItems.items;
  await assertFails(
    setDoc(
      doc(firestore, "tenants/tenant-a/sales/missing-items"),
      missingItems,
    ),
  );

  const invalidLineSets = [
    null,
    { productId: "product-a", quantity: 1 },
    [],
    [{ productId: "product-a", quantity: 0 }],
    [{ productId: "product-a", quantity: -1 }],
    [{ productId: "product-a", quantity: 1.5 }],
    [{ productId: "product-a", quantity: "1" }],
    [{ productId: "", quantity: 1 }],
    [{ quantity: 1 }],
    ["not-a-map"],
    [
      { productId: "product-a", quantity: 1 },
      { productId: "product-b", quantity: 0 },
    ],
  ];

  for (const [index, items] of invalidLineSets.entries()) {
    const checkoutId = `invalid-lines-${index}`;
    await assertFails(
      setDoc(
        doc(firestore, `tenants/tenant-a/sales/${checkoutId}`),
        sale(checkoutId, { items }),
      ),
    );
  }
});

test("sale line validation covers all 16 supported positions and rejects overflow", async () => {
  await seedCashierAndProduct();
  const firestore = authenticatedFirestore(testEnvironment, "cashier");
  const sixteenValidLines = Array.from({ length: 16 }, (_, index) => ({
    productId: `product-${index}`,
    quantity: index + 1,
  }));

  await assertSucceeds(
    setDoc(
      doc(firestore, "tenants/tenant-a/sales/sixteen-lines"),
      sale("sixteen-lines", { items: sixteenValidLines }),
    ),
  );

  const invalidLastLine = [...sixteenValidLines];
  invalidLastLine[15] = { productId: "product-15", quantity: 0 };
  await assertFails(
    setDoc(
      doc(firestore, "tenants/tenant-a/sales/invalid-last-line"),
      sale("invalid-last-line", { items: invalidLastLine }),
    ),
  );

  const seventeenLines = [
    ...sixteenValidLines,
    { productId: "product-16", quantity: 1 },
  ];
  await assertFails(
    setDoc(
      doc(firestore, "tenants/tenant-a/sales/seventeen-lines"),
      sale("seventeen-lines", { items: seventeenLines }),
    ),
  );
});
