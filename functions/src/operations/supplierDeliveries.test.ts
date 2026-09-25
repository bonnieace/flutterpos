import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {FakeFirestore} from "../testing/fakeFirestore";
import {
  MAXIMUM_DELIVERY_PAGE_LINES,
  applyDeliveryPage,
  deliveryLineAdjustmentId,
  readDeliveryPageRequest,
} from "./supplierDeliveries";

/**
 * What one page of a supplier delivery does to a business, against an
 * in-memory Firestore that refuses what Firestore refuses: a read after a
 * write, a create over an existing document, an update of a missing one.
 */

const TENANT = "tenant-a";
const DELIVERY = `sd_${"d".repeat(40)}`;
const ACTOR = "uid-manager";

/** When the delivery was received on the device: the evening before it was sent. */
const SAVED_AT = Date.UTC(2026, 8, 24, 18, 2);

function root(path: string): string {
  return `tenants/${TENANT}/${path}`;
}

function seeded(extra: Record<string, DocumentData> = {}): FakeFirestore {
  const db = new FakeFirestore();
  db.seed(root("suppliers/sp_abc"), {name: "ABC Distributors", active: true});
  db.seed(root("products/prod-bread"), {
    name: "White bread loaf",
    SKU: "BR-1",
    price: 65,
    cost: 40,
    quantity: 40,
    categoryId: "ct_bakery",
  });
  db.seed(root("products/prod-milk"), {
    name: "Milk 500ml",
    SKU: "MK-1",
    price: 50,
    cost: 30,
    quantity: 5,
    categoryId: "ct_dairy",
  });
  for (const [path, data] of Object.entries(extra)) db.seed(root(path), data);
  db.clearWrites();
  return db;
}

function page(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    tenantId: TENANT,
    deliveryId: DELIVERY,
    supplierId: "sp_abc",
    reference: "INV-48392",
    page: 0,
    isFinalPage: true,
    lines: [
      {productId: "prod-bread", productName: "White bread loaf", quantity: 24, unitCost: 45.5},
      {productId: "prod-milk", quantity: 12},
    ],
    occurredAtMs: SAVED_AT,
    ...overrides,
  };
}

function receive(db: FakeFirestore, request: Record<string, unknown> = page()) {
  const input = readDeliveryPageRequest(request);
  return db.runTransaction((transaction) =>
    applyDeliveryPage(db.asFirestore(), transaction as unknown as Transaction, {
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
  return assert.fail("The page was not refused.");
}

test("a page restocks each product and re-costs only the lines that name a cost", async () => {
  const db = seeded();

  const response = await receive(db);

  assert.equal(db.read(root("products/prod-bread"))?.quantity, 64);
  assert.equal(db.read(root("products/prod-bread"))?.cost, 45.5);
  assert.equal(db.read(root("products/prod-milk"))?.quantity, 17);
  assert.equal(db.read(root("products/prod-milk"))?.cost, 30);
  assert.equal(response.complete, true);
  assert.deepEqual(response.lines.map((line) => line.costMinor), [4550, 3000]);
});

test("each line leaves a ledger entry reconciliation can sum", async () => {
  const db = seeded();

  await receive(db);

  const id = deliveryLineAdjustmentId(DELIVERY, "prod-bread");
  const movement = db.read(root(`products/prod-bread/stock_movements/${id}`));
  assert.equal(movement?.sourceType, "supplier_delivery");
  assert.equal(movement?.adjustmentType, "restock");
  assert.equal(movement?.quantityDelta, 24);
  assert.equal(movement?.previousQuantity, 40);
  assert.equal(movement?.quantityAfter, 64);
  assert.equal(movement?.unitCostMinor, 4550);
  assert.equal(movement?.previousCostMinor, 4000);
  assert.equal(movement?.reason, "Delivery from ABC Distributors · INV-48392");
  assert.ok(movement?.recordedAt, "the verifier orders movements by recordedAt");
  assert.ok(db.read(root(`stock_adjustments/${id}`)), "the adjustment record");
});

test("the delivery is one record, with its totals and the supplier's name", async () => {
  const db = seeded();

  await receive(db);

  const header = db.read(root(`supplier_deliveries/${DELIVERY}`));
  assert.equal(header?.supplierName, "ABC Distributors");
  assert.equal(header?.lineCount, 2);
  assert.equal(header?.unitCount, 36);
  assert.equal(header?.valueMinor, 24 * 4550);
  assert.equal(header?.costlessLineCount, 1);
  assert.equal(header?.complete, true);
  assert.ok(header?.createdAt);
  assert.ok(db.read(root("suppliers/sp_abc"))?.lastDeliveryAt);
});

test("pages may land in any order, and the delivery is whole once every one has", async () => {
  const db = seeded();

  // The final page first: the delivery knows how many pages it has, and is
  // not whole until the rest arrive.
  await receive(db, page({
    page: 1,
    isFinalPage: true,
    lines: [{productId: "prod-milk", quantity: 12}],
  }));
  assert.equal(db.read(root(`supplier_deliveries/${DELIVERY}`))?.complete, false);

  await receive(db, page({
    page: 0,
    isFinalPage: false,
    lines: [{productId: "prod-bread", quantity: 24, unitCost: 45.5}],
  }));

  const header = db.read(root(`supplier_deliveries/${DELIVERY}`));
  assert.equal(header?.complete, true);
  assert.deepEqual(header?.pagesRecorded, [0, 1]);
  assert.deepEqual(
    (header?.lines as Array<{productId: string}>).map((line) => line.productId),
    ["prod-bread", "prod-milk"]
  );
});

test("one product on two pages of one delivery is refused", async () => {
  const db = seeded();
  await receive(db, page({isFinalPage: false, lines: [{productId: "prod-bread", quantity: 2}]}));

  const error = await refusal(() => receive(db, page({
    page: 1,
    lines: [{productId: "prod-bread", quantity: 3}],
  })));

  assert.equal(error.code, "failed-precondition");
  assert.equal(db.read(root("products/prod-bread"))?.quantity, 42);
});

test("a supplier the business does not hold is not found", async () => {
  const error = await refusal(() => receive(seeded(), page({supplierId: "sp_missing"})));

  assert.equal(error.code, "not-found");
});

test("a product the business does not hold refuses the whole page", async () => {
  const db = seeded();

  const error = await refusal(() => receive(db, page({
    lines: [
      {productId: "prod-bread", quantity: 1},
      {productId: "prod-gone", quantity: 1},
    ],
  })));

  assert.equal(error.code, "failed-precondition");
  // All or none: the bread was not restocked either.
  assert.equal(db.read(root("products/prod-bread"))?.quantity, 40);
});

test("a later page naming another supplier or reference is refused", async () => {
  const db = seeded({"suppliers/sp_xyz": {name: "XYZ", active: false}});
  await receive(db, page({isFinalPage: false, lines: [{productId: "prod-bread", quantity: 1}]}));

  for (const overrides of [{supplierId: "sp_xyz"}, {reference: "INV-1"}]) {
    const error = await refusal(() => receive(db, page({
      page: 1,
      lines: [{productId: "prod-milk", quantity: 1}],
      ...overrides,
    })));
    assert.equal(error.code, "failed-precondition", JSON.stringify(overrides));
  }
});

test("an inactive supplier still receives, because it may have become so while offline", async () => {
  const db = seeded({"suppliers/sp_xyz": {name: "XYZ Wholesale", active: false}});

  await receive(db, page({supplierId: "sp_xyz"}));

  assert.equal(db.read(root("products/prod-bread"))?.quantity, 64);
});

test("what a page may carry is bounded", async () => {
  const cases: Array<Record<string, unknown>> = [
    page({lines: []}),
    page({lines: [{productId: "prod-bread", quantity: 0}]}),
    page({lines: [{productId: "prod-bread", quantity: 1.5}]}),
    // Zero would set the cost to nothing and report the price as profit.
    page({lines: [{productId: "prod-bread", quantity: 1, unitCost: 0}]}),
    page({lines: [{productId: "prod-bread", quantity: 1, unitCost: 1.005}]}),
    page({lines: [{productId: "prod-bread", quantity: 1, sku: "x"}]}),
    page({lines: [
      {productId: "prod-bread", quantity: 1},
      {productId: "prod-bread", quantity: 2},
    ]}),
    page({
      lines: Array.from({length: MAXIMUM_DELIVERY_PAGE_LINES + 1}, (_, index) => ({
        productId: `prod-${index}`,
        quantity: 1,
      })),
    }),
    page({page: 13}),
    page({isFinalPage: "yes"}),
    page({reference: "r".repeat(65)}),
    page({extra: 1}),
    // Every queued page says when it was saved; one that does not was built by
    // something other than the queue.
    page({occurredAtMs: undefined}),
    page({occurredAtMs: "2026-09-24"}),
  ];
  for (const request of cases) {
    const error = await refusal(() => readDeliveryPageRequest(request));
    assert.equal(error.code, "invalid-argument", JSON.stringify(request).slice(0, 120));
  }
});

test("a page carries at most sixteen lines, three writes each", () => {
  assert.equal(MAXIMUM_DELIVERY_PAGE_LINES, 16);
});

// ---------------------------------------------------------------------------
// When the delivery happened
// ---------------------------------------------------------------------------

function millis(value: unknown): number {
  assert.ok(value instanceof Timestamp, `${String(value)} is not a Timestamp.`);
  return value.toMillis();
}

test("a delivery is dated when it was received, not when it reached the server", async () => {
  const db = seeded();

  await receive(db);

  const header = db.read(root(`supplier_deliveries/${DELIVERY}`));
  assert.equal(millis(header?.occurredAt), SAVED_AT);
  // The server's own time is kept beside it: that is when it arrived.
  assert.ok(millis(header?.createdAt) > SAVED_AT);
  const adjustmentId = deliveryLineAdjustmentId(DELIVERY, "prod-bread");
  assert.equal(millis(db.read(root(`stock_adjustments/${adjustmentId}`))?.occurredAt), SAVED_AT);
  const movement = db.read(root(`products/prod-bread/stock_movements/${adjustmentId}`));
  assert.equal(millis(movement?.occurredAt), SAVED_AT);
  assert.ok(millis(movement?.recordedAt) > SAVED_AT);
  assert.equal(millis(db.read(root("suppliers/sp_abc"))?.lastDeliveryAt), SAVED_AT);
});

test("the first page to arrive dates the whole delivery", async () => {
  const db = seeded();

  await receive(db, page({
    page: 0,
    isFinalPage: false,
    lines: [{productId: "prod-bread", quantity: 24}],
  }));
  await receive(db, page({
    page: 1,
    isFinalPage: true,
    lines: [{productId: "prod-milk", quantity: 12}],
    occurredAtMs: SAVED_AT + 60_000,
  }));

  assert.equal(millis(db.read(root(`supplier_deliveries/${DELIVERY}`))?.occurredAt), SAVED_AT);
  const milk = deliveryLineAdjustmentId(DELIVERY, "prod-milk");
  assert.equal(millis(db.read(root(`stock_adjustments/${milk}`))?.occurredAt), SAVED_AT);
});

test("a delivery older than the supplier's last one leaves the last one alone", async () => {
  const later = Timestamp.fromMillis(SAVED_AT + 60 * 60 * 1000);
  const db = seeded({"suppliers/sp_abc": {name: "ABC Distributors", active: true, lastDeliveryAt: later}});

  await receive(db);

  assert.ok((db.read(root("suppliers/sp_abc"))?.lastDeliveryAt as Timestamp).isEqual(later));
});

test("a device clock running ahead cannot date a delivery after it arrived", async () => {
  const db = seeded();
  const before = Date.now();

  await receive(db, page({occurredAtMs: Date.now() + 24 * 60 * 60 * 1000}));

  const occurredAt = millis(db.read(root(`supplier_deliveries/${DELIVERY}`))?.occurredAt);
  assert.ok(occurredAt >= before && occurredAt <= Date.now());
});
