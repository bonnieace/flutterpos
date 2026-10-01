import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp, Transaction} from "firebase-admin/firestore";
import {FakeFirestore} from "../testing/fakeFirestore";
import {
  CustomerNotYetArrived,
  applyCustomerSale,
  customerSaleTaskId,
  planReturnedPoints,
  pointsFor,
  readLoyaltyPolicy,
} from "./customerSale";

/**
 * What a sale to a named customer does to them, once it arrives.
 *
 * The two properties that matter are that it happens once - a retried task or
 * a doubled trigger counts nothing twice - and that it waits for a customer
 * still on an offline till rather than counting a sale against nobody.
 */

const TENANT = "tenant-a";
const JANE = `cu_${"0123456789abcdef".repeat(2)}01234567`;
const ROOT = `tenants/${TENANT}`;

function sale(overrides: DocumentData = {}): DocumentData {
  return {
    tenantId: TENANT,
    receiptNumber: "CT-A7F-20261001-0001",
    customerId: JANE,
    customerName: "Jane Wanjiku",
    subtotalMinor: 50000,
    totalMinor: 45000,
    items: [
      {productId: "flour", quantity: 2, unitPriceMinor: 15000},
      {productId: "sugar", quantity: 2, unitPriceMinor: 10000},
    ],
    createdAt: Timestamp.fromMillis(1790000000000),
    ...overrides,
  };
}

function seeded(documents: Record<string, DocumentData>): FakeFirestore {
  const db = new FakeFirestore();
  for (const [path, data] of Object.entries(documents)) db.seed(path, data);
  db.clearWrites();
  return db;
}

function count(db: FakeFirestore, saleId = "sale-1") {
  return applyCustomerSale(db.asFirestore(), {tenantId: TENANT, saleId});
}

test("a sale earns its customer points at the business's rate, once", async () => {
  const db = seeded({
    [`${ROOT}/sales/sale-1`]: sale(),
    [`${ROOT}/customers/${JANE}`]: {name: "Jane Wanjiku", active: true},
    [`${ROOT}/configuration/loyalty`]: {enabled: true, minorUnitsPerPoint: 10000},
  });

  const first = await count(db);
  const second = await count(db);

  assert.deepEqual(first, {outcome: "counted", customerId: JANE, points: 4, owedMinor: 0});
  assert.deepEqual(second, {outcome: "already_counted", customerId: JANE});
  const customer = db.read(`${ROOT}/customers/${JANE}`);
  assert.equal(customer?.points, 4);
  assert.equal(customer?.saleCount, 1);
  assert.equal((customer?.lastSaleAt as Timestamp).toMillis(), 1790000000000);
  const entry = db.read(`${ROOT}/customers/${JANE}/activity/sale-1`);
  assert.equal(entry?.kind, "sale");
  assert.equal(entry?.points, 4);
  assert.equal(entry?.pointsReturned, 0);
});

test("with loyalty off a sale still counts, and earns nothing", async () => {
  const db = seeded({
    [`${ROOT}/sales/sale-1`]: sale(),
    [`${ROOT}/customers/${JANE}`]: {name: "Jane", active: true},
  });

  const outcome = await count(db);

  assert.deepEqual(outcome, {outcome: "counted", customerId: JANE, points: 0, owedMinor: 0});
  const customer = db.read(`${ROOT}/customers/${JANE}`);
  assert.equal(customer?.saleCount, 1);
  assert.equal("points" in (customer ?? {}), false);
});

test("a customer still on an offline till is waited for, not skipped", async () => {
  const db = seeded({[`${ROOT}/sales/sale-1`]: sale()});

  await assert.rejects(() => count(db), CustomerNotYetArrived);
  assert.deepEqual(db.writtenPaths(), []);
});

test("a walk-in and a sale naming nobody recognisable count nothing", async () => {
  const db = seeded({
    [`${ROOT}/sales/walk-in`]: sale({customerId: undefined, customerName: undefined}),
    [`${ROOT}/sales/forged`]: sale({customerId: "sp_abc"}),
  });

  assert.deepEqual(await count(db, "walk-in"), {outcome: "walk_in"});
  assert.deepEqual(await count(db, "forged"), {outcome: "walk_in"});
  assert.deepEqual(await count(db, "missing"), {outcome: "no_sale"});
  assert.deepEqual(db.writtenPaths(), []);
});

test("an older sale arriving late does not move the last purchase back", async () => {
  const db = seeded({
    [`${ROOT}/sales/sale-1`]: sale({createdAt: Timestamp.fromMillis(1000)}),
    [`${ROOT}/customers/${JANE}`]: {
      name: "Jane",
      active: true,
      lastSaleAt: Timestamp.fromMillis(5000),
    },
  });

  await count(db);

  const customer = db.read(`${ROOT}/customers/${JANE}`);
  assert.equal((customer?.lastSaleAt as Timestamp).toMillis(), 5000);
});

test("a malformed loyalty setting earns nothing rather than guessing", () => {
  for (const data of [
    undefined,
    {enabled: "yes", minorUnitsPerPoint: 100},
    {enabled: true, minorUnitsPerPoint: 0},
    {enabled: true, minorUnitsPerPoint: 1.5},
  ]) {
    assert.equal(readLoyaltyPolicy(data).enabled, false, JSON.stringify(data));
  }
  assert.equal(pointsFor({enabled: true, minorUnitsPerPoint: 10000}, 9999), 0);
  assert.equal(pointsFor({enabled: true, minorUnitsPerPoint: 10000}, 20000), 2);
});

test("the same sale always queues under the same task ID", () => {
  const task = {tenantId: TENANT, saleId: "co_20261001_abc"};
  assert.equal(customerSaleTaskId(task), customerSaleTaskId({...task}));
  assert.match(customerSaleTaskId(task), /^customer-sale-[0-9a-f]{48}$/);
});

async function giveBack(
  db: FakeFirestore,
  returnId: string,
  lines: Array<{productId: string; quantity: number}>
) {
  return db.runTransaction(async (transaction) => {
    const tx = transaction as unknown as Transaction;
    const plan = await planReturnedPoints(
      tx,
      db.asFirestore().collection("tenants").doc(TENANT),
      {saleId: "sale-1", sale: sale(), returnId, lines}
    );
    plan?.(tx);
    return plan !== null;
  });
}

test("a return gives back its share of the points, and never more", async () => {
  const db = seeded({
    [`${ROOT}/customers/${JANE}`]: {name: "Jane", points: 10},
    [`${ROOT}/customers/${JANE}/activity/sale-1`]: {
      kind: "sale",
      points: 10,
      pointsReturned: 0,
    },
  });

  // Flour is 30000 of the 50000 listed: three fifths of ten points.
  assert.equal(await giveBack(db, "ret-1", [{productId: "flour", quantity: 2}]), true);
  assert.equal(db.read(`${ROOT}/customers/${JANE}`)?.points, 4);
  assert.equal(
    db.read(`${ROOT}/customers/${JANE}/activity/return-ret-1`)?.points,
    -6
  );

  // The rest of the basket gives back the remaining four, and no more.
  await giveBack(db, "ret-2", [
    {productId: "flour", quantity: 2},
    {productId: "sugar", quantity: 2},
  ]);
  assert.equal(db.read(`${ROOT}/customers/${JANE}`)?.points, 0);
  assert.equal(
    db.read(`${ROOT}/customers/${JANE}/activity/sale-1`)?.pointsReturned,
    10
  );

  // Nothing is left to give back.
  assert.equal(await giveBack(db, "ret-3", [{productId: "sugar", quantity: 1}]), false);
});

test("a return of a sale not counted yet takes nothing", async () => {
  const db = seeded({[`${ROOT}/customers/${JANE}`]: {name: "Jane", points: 3}});

  assert.equal(await giveBack(db, "ret-1", [{productId: "flour", quantity: 1}]), false);
  assert.equal(db.read(`${ROOT}/customers/${JANE}`)?.points, 3);
});
