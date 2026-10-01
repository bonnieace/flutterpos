import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {FakeFirestore} from "../testing/fakeFirestore";
import {aggregateSalesByTender} from "../operations/domain";
import {
  readCustomerDocument,
  requireCreditGranter,
} from "../operations/customers";
import {planSaleTenderRecord} from "../operations/saleTender";
import {aggregateDailySales} from "../reconciliation/model";
import {readSaleCredit} from "./credit";
import {applyCustomerSale, planReturnedPoints} from "./customerSale";
import {applyCustomerPayment, readCustomerPaymentRequest} from "./payments";

/**
 * Selling on credit, end to end on the server: what a credit sale owes, what
 * a return cancels, what a repayment pays back, and what each does to the
 * drawer its shift is counted against.
 */

const TENANT = "tenant-a";
const JANE = `cu_${"0123456789abcdef".repeat(2)}01234567`;
const ROOT = `tenants/${TENANT}`;
const CASHIER = "uid-cashier";
const SHIFT = "shift-1";
const PAYMENT = `cp_${"ab".repeat(20)}`;

function creditSale(overrides: DocumentData = {}): DocumentData {
  return {
    tenantId: TENANT,
    receiptNumber: "CT-A7F-20261001-0002",
    customerId: JANE,
    customerName: "Jane Wanjiku",
    shiftId: SHIFT,
    businessDate: "2026-10-01",
    tender: "credit",
    creditOwedMinor: 70000,
    creditPaidTender: "cash",
    subtotalMinor: 100000,
    totalMinor: 100000,
    total: 1000,
    items: [
      {productId: "flour", quantity: 2, unitPriceMinor: 30000, unitPrice: 300},
      {productId: "sugar", quantity: 4, unitPriceMinor: 10000, unitPrice: 100},
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

function customer(db: FakeFirestore): DocumentData | undefined {
  return db.read(`${ROOT}/customers/${JANE}`);
}

test("a credit sale adds what it left owing to the balance, once", async () => {
  const db = seeded({
    [`${ROOT}/sales/sale-1`]: creditSale(),
    [`${ROOT}/customers/${JANE}`]: {name: "Jane", active: true, creditLimitMinor: 200000},
  });

  const first = await applyCustomerSale(db.asFirestore(), {tenantId: TENANT, saleId: "sale-1"});
  await applyCustomerSale(db.asFirestore(), {tenantId: TENANT, saleId: "sale-1"});

  assert.deepEqual(first, {outcome: "counted", customerId: JANE, points: 0, owedMinor: 70000});
  assert.equal(customer(db)?.balanceMinor, 70000);
  assert.equal((customer(db)?.owingSince as Timestamp).toMillis(), 1790000000000);
  const entry = db.read(`${ROOT}/customers/${JANE}/activity/sale-1`);
  assert.equal(entry?.credit, true);
  assert.equal(entry?.creditOwedMinor, 70000);
  assert.equal(entry?.creditPaidMinor, 30000);
  assert.equal(entry?.creditPaidTender, "cash");
  assert.equal(entry?.balanceChangeMinor, 70000);
  assert.equal(entry?.balanceAfterMinor, 70000);
  assert.equal(entry?.overLimit, false);
});

test("a sale past the limit still counts, and says it went over", async () => {
  const db = seeded({
    [`${ROOT}/sales/sale-1`]: creditSale(),
    [`${ROOT}/customers/${JANE}`]: {
      name: "Jane",
      active: true,
      creditLimitMinor: 100000,
      balanceMinor: 50000,
      owingSince: Timestamp.fromMillis(5),
    },
  });

  await applyCustomerSale(db.asFirestore(), {tenantId: TENANT, saleId: "sale-1"});

  assert.equal(customer(db)?.balanceMinor, 120000);
  // Already owing: the debt is as old as it was.
  assert.equal((customer(db)?.owingSince as Timestamp).toMillis(), 5);
  assert.equal(db.read(`${ROOT}/customers/${JANE}/activity/sale-1`)?.overLimit, true);
});

test("a sale paid in full is not a debt, whatever its tender says", () => {
  assert.equal(readSaleCredit({tender: "cash", totalMinor: 100}), null);
  for (const forged of [
    {tender: "credit", totalMinor: 100, creditOwedMinor: 0},
    {tender: "credit", totalMinor: 100, creditOwedMinor: 101},
    {tender: "credit", totalMinor: 100, creditOwedMinor: 1.5},
    {tender: "credit", totalMinor: 100, creditOwedMinor: 40},
    {tender: "credit", totalMinor: 100, creditOwedMinor: 40, creditPaidTender: "cheque"},
    {tender: "credit", totalMinor: 100, creditOwedMinor: 100, creditPaidTender: "cash"},
  ]) {
    assert.equal(readSaleCredit(forged), null, JSON.stringify(forged));
  }
  assert.deepEqual(
    readSaleCredit({tender: "credit", totalMinor: 100, creditOwedMinor: 100}),
    {owedMinor: 100, paidMinor: 0, paidTender: null}
  );
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
      {saleId: "sale-1", sale: creditSale(), returnId, lines}
    );
    plan?.(tx);
    return plan !== null;
  });
}

test("goods returned on a credit sale cancel what is still owed, and no more", async () => {
  const db = seeded({
    [`${ROOT}/customers/${JANE}`]: {
      name: "Jane",
      balanceMinor: 70000,
      owingSince: Timestamp.fromMillis(5),
    },
    [`${ROOT}/customers/${JANE}/activity/sale-1`]: {
      kind: "sale",
      points: 0,
      pointsReturned: 0,
      credit: true,
      creditOwedMinor: 70000,
      creditReturnedMinor: 0,
    },
  });

  // The flour was 60000 of the 100000 charged.
  assert.equal(await giveBack(db, "ret-1", [{productId: "flour", quantity: 2}]), true);
  assert.equal(customer(db)?.balanceMinor, 10000);
  const first = db.read(`${ROOT}/customers/${JANE}/activity/return-ret-1`);
  assert.equal(first?.balanceChangeMinor, -60000);
  assert.equal(first?.balanceAfterMinor, 10000);

  // The sugar was 40000, but only 10000 is still owed on this sale.
  await giveBack(db, "ret-2", [{productId: "sugar", quantity: 4}]);
  assert.equal(customer(db)?.balanceMinor, 0);
  assert.equal("owingSince" in (customer(db) ?? {}), false);
  assert.equal(
    db.read(`${ROOT}/customers/${JANE}/activity/sale-1`)?.creditReturnedMinor,
    70000
  );

  assert.equal(await giveBack(db, "ret-3", [{productId: "sugar", quantity: 1}]), false);
});

function paymentRequest(overrides: Record<string, unknown> = {}) {
  return readCustomerPaymentRequest({
    tenantId: TENANT,
    paymentId: PAYMENT,
    customerId: JANE,
    amountMinor: 50000,
    tender: "mpesa",
    shiftId: SHIFT,
    ...overrides,
  });
}

function pay(db: FakeFirestore, input = paymentRequest(), actor = CASHIER) {
  return db.runTransaction((transaction) => applyCustomerPayment(
    db.asFirestore(),
    transaction as unknown as Transaction,
    input,
    actor
  ));
}

test("a repayment lowers the balance into the shift that took it", async () => {
  const db = seeded({
    [`${ROOT}/customers/${JANE}`]: {
      name: "Jane",
      balanceMinor: 70000,
      owingSince: Timestamp.fromMillis(5),
    },
    [`${ROOT}/shifts/${SHIFT}`]: {staffId: CASHIER, businessDate: "2026-10-02"},
  });

  const response = await pay(db);

  assert.deepEqual(response, {paymentId: PAYMENT, customerId: JANE, balanceAfterMinor: 20000});
  assert.equal(customer(db)?.balanceMinor, 20000);
  const payment = db.read(`${ROOT}/customer_payments/${PAYMENT}`);
  assert.equal(payment?.businessDate, "2026-10-02");
  assert.equal(payment?.recordedBy, CASHIER);
  assert.equal(payment?.customerName, "Jane");
  const entry = db.read(`${ROOT}/customers/${JANE}/activity/payment-${PAYMENT}`);
  assert.equal(entry?.balanceChangeMinor, -50000);
  assert.equal(entry?.credit, true);

  // Paying more than is owed leaves them ahead, and owing nothing.
  await pay(db, paymentRequest({paymentId: `cp_${"cd".repeat(20)}`, amountMinor: 30000}));
  assert.equal(customer(db)?.balanceMinor, -10000);
  assert.equal("owingSince" in (customer(db) ?? {}), false);
});

test("a repayment is refused into someone else's shift, or for nobody", async () => {
  const db = seeded({
    [`${ROOT}/customers/${JANE}`]: {name: "Jane", balanceMinor: 70000},
    [`${ROOT}/shifts/${SHIFT}`]: {staffId: "someone-else", businessDate: "2026-10-02"},
  });

  await assert.rejects(() => pay(db), (error: unknown) =>
    error instanceof HttpsError && error.code === "failed-precondition");
  await assert.rejects(
    () => pay(db, paymentRequest({customerId: `cu_${"f".repeat(40)}`})),
    (error: unknown) => error instanceof HttpsError && error.code === "not-found"
  );
  assert.deepEqual(db.writtenPaths(), []);
  for (const bad of [
    {amountMinor: 0},
    {amountMinor: 1.5},
    {tender: "credit"},
    {paymentId: "cp_short"},
  ]) {
    assert.throws(() => paymentRequest(bad), HttpsError, JSON.stringify(bad));
  }
});

test("a shift expects what a credit sale was paid, and what was paid back", () => {
  const result = aggregateDailySales(
    "2026-10-01",
    [
      creditSale(),
      creditSale({creditOwedMinor: 100000, creditPaidTender: undefined}),
      {shiftId: SHIFT, total: 50, totalMinor: 5000, tender: "card"},
    ],
    200,
    undefined,
    0,
    [
      {shiftId: SHIFT, amountMinor: 20000, tender: "mpesa"},
      {shiftId: "shift-2", amountMinor: 5000, tender: "cash"},
      {shiftId: SHIFT, amountMinor: 20000, tender: "credit"},
    ]
  );

  const [first, second] = result.shifts;
  // Sales and transactions are the shift's sales, gross, as its close states.
  assert.equal(first.sales, 2050);
  assert.equal(first.transactions, 3);
  // The drawer: 300 cash paid at the counter, 200 M-Pesa paid back, 50 card.
  assert.deepEqual(first.tenders, {
    cashMinor: 30000,
    mpesaMinor: 20000,
    cardMinor: 5000,
    unattributedMinor: 0,
  });
  // A shift that only took a repayment is still expected to hold it.
  assert.equal(second.shiftId, "shift-2");
  assert.equal(second.sales, 0);
  assert.equal(second.tenders.cashMinor, 5000);
});

test("the period report splits a credit sale between paid and owed", () => {
  const breakdown = aggregateSalesByTender([creditSale()]);
  assert.equal(breakdown.cash.sales, 300);
  assert.equal(breakdown.other.sales, 700);
  assert.equal(breakdown.other.transactions, 1);
  assert.equal(breakdown.cash.transactions, 0);
});

test("a credit limit is a manager's to give, and zero gives none", () => {
  assert.deepEqual(
    readCustomerDocument({name: "Jane", creditLimitMinor: 500000}, "create"),
    {name: "Jane", creditLimitMinor: 500000}
  );
  assert.deepEqual(
    readCustomerDocument({name: "Jane", creditLimitMinor: 0}, "create"),
    {name: "Jane"}
  );
  assert.deepEqual(
    readCustomerDocument({creditLimitMinor: 0}, "update"),
    {creditLimitMinor: null}
  );
  assert.throws(() => readCustomerDocument({creditLimitMinor: -1}, "update"), HttpsError);
  assert.throws(
    () => requireCreditGranter("cashier", {name: "Jane", creditLimitMinor: 500000}),
    HttpsError
  );
  requireCreditGranter("manager", {name: "Jane", creditLimitMinor: 500000});
  requireCreditGranter("cashier", {name: "Jane"});
});

test("a credit sale's payment method cannot be relabelled afterwards", () => {
  assert.throws(() => planSaleTenderRecord({
    tenantId: TENANT,
    saleId: "sale-1",
    actorUid: CASHIER,
    requestId: "tender-request-1",
    tender: "cash",
    sale: {soldById: CASHIER, tender: "credit", businessDate: "2026-10-01"},
    shiftClosed: false,
  }), (error: unknown) => error instanceof HttpsError && error.code === "failed-precondition");
});
