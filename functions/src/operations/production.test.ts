import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {FakeFirestore} from "../testing/fakeFirestore";
import {
  MAXIMUM_PRODUCTION_EXPENSES,
  applyProduction,
  productionAdjustmentId,
  productionUnitCostMinor,
  readProductionRequest,
} from "./production";

/**
 * What completing a production batch does to a business, against an in-memory
 * Firestore that refuses what Firestore refuses.
 */

const TENANT = "tenant-a";
const BATCH = `pb_${"b".repeat(40)}`;
const ACTOR = "uid-manager";

/** When the batch was recorded on the device: the evening before it was sent. */
const SAVED_AT = Date.UTC(2026, 8, 24, 18, 2);

function root(path: string): string {
  return `tenants/${TENANT}/${path}`;
}

function seeded(): FakeFirestore {
  const db = new FakeFirestore();
  db.seed(root("products/prod-bread"), {
    name: "White bread loaf",
    SKU: "BR-1",
    price: 50,
    cost: 28,
    quantity: 12,
    categoryId: "ct_bakery",
    costType: "produced",
  });
  db.clearWrites();
  return db;
}

function batch(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    tenantId: TENANT,
    batchId: BATCH,
    batchNumber: "PB-20260924-7F3A2C",
    productId: "prod-bread",
    productName: "White bread loaf",
    quantity: 100,
    expenses: [
      {description: "Flour", amount: 2000},
      {description: " Labour ", amount: 500},
      {description: "Gas", amount: 200},
      {description: "Packaging", amount: 300},
    ],
    // The device's own arithmetic, carried for its overlay and ignored here.
    totalCostMinor: 1,
    unitCostMinor: 1,
    occurredAtMs: SAVED_AT,
    ...overrides,
  };
}

function complete(db: FakeFirestore, request: Record<string, unknown> = batch()) {
  const input = readProductionRequest(request);
  return db.runTransaction((transaction) =>
    applyProduction(db.asFirestore(), transaction as unknown as Transaction, {
      input,
      actorUid: ACTOR,
    })
  );
}

async function refusal(attempt: () => unknown): Promise<HttpsError> {
  try {
    await attempt();
  } catch (error) {
    assert.ok(error instanceof HttpsError, `${error}`);
    return error;
  }
  return assert.fail("The batch was not refused.");
}

test("a batch adds what was made and sets what one unit cost to make", async () => {
  const db = seeded();

  const response = await complete(db);

  const product = db.read(root("products/prod-bread"));
  assert.equal(product?.quantity, 112);
  assert.equal(product?.cost, 30);
  assert.equal(response.totalCostMinor, 300000);
  assert.equal(response.unitCostMinor, 3000);
  assert.equal(response.previousCostMinor, 2800);
});

test("the cost is the server's arithmetic, never what the device sent", async () => {
  const db = seeded();

  await complete(db, batch({totalCostMinor: 999, unitCostMinor: 999}));

  assert.equal(db.read(root(`production_batches/${BATCH}`))?.unitCostMinor, 3000);
});

test("the batch is saved with its rows, the cost it replaced, and its ledger entry", async () => {
  const db = seeded();

  await complete(db);

  const saved = db.read(root(`production_batches/${BATCH}`));
  assert.equal(saved?.productName, "White bread loaf");
  assert.equal(saved?.previousCostMinor, 2800);
  assert.deepEqual(saved?.expenses, [
    {description: "Flour", amountMinor: 200000},
    {description: "Labour", amountMinor: 50000},
    {description: "Gas", amountMinor: 20000},
    {description: "Packaging", amountMinor: 30000},
  ]);
  const id = productionAdjustmentId(BATCH);
  const movement = db.read(root(`products/prod-bread/stock_movements/${id}`));
  assert.equal(movement?.sourceType, "production");
  assert.equal(movement?.quantityDelta, 100);
  assert.equal(movement?.reason, "Production batch PB-20260924-7F3A2C");
  assert.ok(movement?.recordedAt, "the verifier orders movements by recordedAt");
  assert.ok(db.read(root(`audit_logs/${BATCH}`)), "the audit entry");
});

test("a batch is dated when it was recorded, not when it reached the server", async () => {
  const db = seeded();

  await complete(db);

  const saved = db.read(root(`production_batches/${BATCH}`));
  assert.equal((saved?.occurredAt as Timestamp).toMillis(), SAVED_AT);
  assert.ok((saved?.createdAt as Timestamp).toMillis() > SAVED_AT);
  const id = productionAdjustmentId(BATCH);
  assert.equal(
    (db.read(root(`stock_adjustments/${id}`))?.occurredAt as Timestamp).toMillis(),
    SAVED_AT
  );
  const movement = db.read(root(`products/prod-bread/stock_movements/${id}`));
  assert.equal((movement?.occurredAt as Timestamp).toMillis(), SAVED_AT);
  assert.ok((movement?.recordedAt as Timestamp).toMillis() > SAVED_AT);
});

test("cost per unit is rounded half up to the cent", () => {
  assert.equal(productionUnitCostMinor(100000, 3), 33333);
  assert.equal(productionUnitCostMinor(100, 8), 13); // 12.5 rounds up
  assert.equal(productionUnitCostMinor(99, 8), 12); // 12.375 rounds down
});

test("a batch with no cost cannot be made", async () => {
  const cases: Array<Record<string, unknown>> = [
    batch({expenses: []}),
    batch({expenses: [{description: "Flour", amount: 0}]}),
    batch({expenses: [{description: "Flour", amount: -5}]}),
    batch({expenses: [{description: "  ", amount: 10}]}),
    // One cent over a million units rounds to nothing a unit.
    batch({quantity: 1_000_000, expenses: [{description: "Flour", amount: 0.01}]}),
  ];
  for (const request of cases) {
    const error = await refusal(() => readProductionRequest(request));
    assert.equal(error.code, "invalid-argument", JSON.stringify(request).slice(0, 140));
  }
});

test("what a batch may carry is bounded", async () => {
  const cases: Array<Record<string, unknown>> = [
    batch({quantity: 0}),
    batch({quantity: 2.5}),
    batch({batchNumber: "PB-001"}),
    batch({expenses: [{description: "Flour", amount: 1.005}]}),
    batch({expenses: [{description: "Flour", amount: 10, kind: "x"}]}),
    batch({
      expenses: Array.from({length: MAXIMUM_PRODUCTION_EXPENSES + 1}, (_, index) => ({
        description: `Row ${index}`,
        amount: 1,
      })),
    }),
    batch({draft: true}),
    batch({occurredAtMs: undefined}),
    batch({occurredAtMs: "2026-09-24"}),
  ];
  for (const request of cases) {
    const error = await refusal(() => readProductionRequest(request));
    assert.equal(error.code, "invalid-argument", JSON.stringify(request).slice(0, 140));
  }
});

test("a product the business does not hold refuses the batch", async () => {
  const error = await refusal(() => complete(seeded(), batch({productId: "prod-gone"})));

  assert.equal(error.code, "failed-precondition");
});

test("a product made or bought is costed alike: the flag is the form's to check", async () => {
  // Whether a product is made here can change while a batch waits offline, so
  // the server does not refuse a bought-in product; the form never offers one.
  const db = seeded();
  db.seed(root("products/prod-bought"), {
    name: "Cola",
    SKU: "CL-1",
    price: 80,
    quantity: 0,
    categoryId: "ct_drinks",
  });

  await complete(db, batch({productId: "prod-bought"}));

  assert.equal(db.read(root("products/prod-bought"))?.quantity, 100);
});
