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
import {
  applyCustomerSale,
  CustomerNotYetArrived,
  planReturnedPoints,
} from "./customerSale";
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
  assert.equal(customer(db)?.owing, true);
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

test("any customer may owe with no limit; a blocked one is recorded as such", async () => {
  const db = seeded({
    [`${ROOT}/sales/sale-1`]: creditSale(),
    [`${ROOT}/sales/sale-2`]: creditSale({receiptNumber: "CT-A7F-20261001-0003"}),
    [`${ROOT}/customers/${JANE}`]: {name: "Jane", active: true},
  });

  await applyCustomerSale(db.asFirestore(), {tenantId: TENANT, saleId: "sale-1"});
  const first = db.read(`${ROOT}/customers/${JANE}/activity/sale-1`);
  // No limit is not over one.
  assert.equal(first?.overLimit, false);
  assert.equal(first?.whileBlocked, false);
  assert.equal(customer(db)?.balanceMinor, 70000);

  // A till that had not heard of the block sold anyway: counted, and marked.
  db.seed(`${ROOT}/customers/${JANE}`, {...customer(db), creditBlocked: true});
  await applyCustomerSale(db.asFirestore(), {tenantId: TENANT, saleId: "sale-2"});
  assert.equal(db.read(`${ROOT}/customers/${JANE}/activity/sale-2`)?.whileBlocked, true);
  assert.equal(customer(db)?.balanceMinor, 140000);
});

test("blocking credit is a manager's switch, and allowing it is the default", () => {
  assert.deepEqual(
    readCustomerDocument({name: "Jane", creditBlocked: false}, "create"),
    {name: "Jane"}
  );
  assert.deepEqual(
    readCustomerDocument({name: "Jane", creditBlocked: true}, "create"),
    {name: "Jane", creditBlocked: true}
  );
  assert.deepEqual(readCustomerDocument({creditBlocked: false}, "update"), {
    creditBlocked: false,
  });
  assert.throws(() => readCustomerDocument({creditBlocked: "no"}, "update"), HttpsError);
  assert.throws(
    () => requireCreditGranter("cashier", {name: "Jane", creditBlocked: true}),
    HttpsError
  );
  requireCreditGranter("manager", {name: "Jane", creditBlocked: true});
});

test("a sale paid in full is not a debt, whatever its tender says", () => {
  assert.equal(readSaleCredit({tender: "cash", totalMinor: 100}), null);
  const credit = {tender: "credit", customerId: JANE, totalMinor: 100};
  for (const forged of [
    {...credit, creditOwedMinor: 0},
    {...credit, creditOwedMinor: 101},
    {...credit, creditOwedMinor: 1.5},
    {...credit, creditOwedMinor: 40},
    {...credit, creditOwedMinor: 40, creditPaidTender: "cheque"},
    {...credit, creditOwedMinor: 100, creditPaidTender: "cash"},
    // Nobody the server can charge: the owed part would leave the drawer
    // expectation and land on no balance.
    {...credit, creditOwedMinor: 100, customerId: undefined},
    {...credit, creditOwedMinor: 100, customerId: "x"},
  ]) {
    assert.equal(readSaleCredit(forged), null, JSON.stringify(forged));
  }
  assert.deepEqual(
    readSaleCredit({...credit, creditOwedMinor: 100}),
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

test("a return verified before the sale was counted is applied by the count", async () => {
  const db = seeded({
    [`${ROOT}/sales/sale-1`]: creditSale(),
    [`${ROOT}/customers/${JANE}`]: {name: "Jane", active: true},
    [`${ROOT}/return_verifications/rv_1`]: {
      tenantId: TENANT,
      returnId: "ret-1",
      saleId: "sale-1",
      restoredProducts: [{productId: "flour", quantityRestored: 2}],
    },
  });

  await applyCustomerSale(db.asFirestore(), {tenantId: TENANT, saleId: "sale-1"});

  // The flour was 60000 of the 70000 owed: the customer owes only the rest.
  assert.equal(customer(db)?.balanceMinor, 10000);
  const sale = db.read(`${ROOT}/customers/${JANE}/activity/sale-1`);
  assert.equal(sale?.creditReturnedMinor, 60000);
  assert.equal(sale?.balanceAfterMinor, 70000);
  const returned = db.read(`${ROOT}/customers/${JANE}/activity/return-ret-1`);
  assert.equal(returned?.balanceChangeMinor, -60000);
  assert.equal(returned?.balanceAfterMinor, 10000);
});

test("returns verified before the count apply in the order they were verified", async () => {
  // The sugar came back first and the flour second. Applied in that order
  // the sugar cancels 40000 and the flour the 30000 left; their IDs sort the
  // other way round, which would hand the flour all but 10000 of it.
  const db = seeded({
    [`${ROOT}/sales/sale-1`]: creditSale(),
    [`${ROOT}/customers/${JANE}`]: {name: "Jane", active: true},
    [`${ROOT}/return_verifications/rv_b`]: {
      returnId: "ret-sugar",
      saleId: "sale-1",
      restoredProducts: [{productId: "sugar", quantityRestored: 4}],
      createdAt: Timestamp.fromMillis(1000),
    },
    [`${ROOT}/return_verifications/rv_a`]: {
      returnId: "ret-flour",
      saleId: "sale-1",
      restoredProducts: [{productId: "flour", quantityRestored: 2}],
      createdAt: Timestamp.fromMillis(2000),
    },
  });

  await applyCustomerSale(db.asFirestore(), {tenantId: TENANT, saleId: "sale-1"});

  const activity = `${ROOT}/customers/${JANE}/activity`;
  const sugar = db.read(`${activity}/return-ret-sugar`);
  const flour = db.read(`${activity}/return-ret-flour`);
  assert.equal(sugar?.balanceChangeMinor, -40000);
  assert.equal(sugar?.balanceAfterMinor, 30000);
  assert.equal(flour?.balanceChangeMinor, -30000);
  assert.equal(flour?.balanceAfterMinor, 0);
  assert.equal(customer(db)?.balanceMinor, 0);
  // The statement lists by time: the sale, then each return in turn.
  const at = (entry: DocumentData | undefined) =>
    (entry?.createdAt as Timestamp).toMillis();
  const sale = db.read(`${activity}/sale-1`);
  assert.ok(at(sale) < at(sugar) && at(sugar) < at(flour));
});

test("a credit sale to a customer refused for a taken number owes the holder", async () => {
  // The till added "Jane" offline with a number Jane already had, and sold
  // to the new record on credit. The create was refused; the sale counts on
  // the customer who holds the number, and so does its return later.
  const added = `cu_${"f".repeat(40)}`;
  const db = seeded({
    [`${ROOT}/sales/sale-1`]: creditSale({customerId: added}),
    [`${ROOT}/customers/${JANE}`]: {name: "Jane", active: true},
    [`${ROOT}/customer_aliases/${added}`]: {customerId: JANE, reason: "phone_taken"},
  });

  const outcome = await applyCustomerSale(
    db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"}
  );

  assert.deepEqual(outcome, {outcome: "counted", customerId: JANE, points: 0, owedMinor: 70000});
  assert.equal(customer(db)?.balanceMinor, 70000);
  assert.equal(db.read(`${ROOT}/customers/${added}`), undefined);

  await db.runTransaction(async (transaction) => {
    const tx = transaction as unknown as Transaction;
    const plan = await planReturnedPoints(
      tx,
      db.asFirestore().collection("tenants").doc(TENANT),
      {
        saleId: "sale-1",
        sale: creditSale({customerId: added}),
        returnId: "ret-1",
        lines: [{productId: "flour", quantity: 2}],
      }
    );
    plan?.(tx);
  });
  assert.equal(customer(db)?.balanceMinor, 10000);
});

test("a credit sale whose customer never arrives adds them on the last attempt", async () => {
  const db = seeded({[`${ROOT}/sales/sale-1`]: creditSale()});
  const task = {tenantId: TENANT, saleId: "sale-1"};

  await assert.rejects(
    applyCustomerSale(db.asFirestore(), task),
    CustomerNotYetArrived
  );
  assert.equal(customer(db), undefined);

  await applyCustomerSale(db.asFirestore(), task, {lastAttempt: true});

  const added = customer(db);
  assert.equal(added?.name, "Jane Wanjiku");
  assert.equal(added?.createdFromSaleId, "sale-1");
  assert.equal(added?.balanceMinor, 70000);
  assert.equal(added?.owing, true);
  assert.equal(added?.saleCount, 1);
});

test("a sale owing nothing still waits for its customer, however late", async () => {
  const db = seeded({
    [`${ROOT}/sales/sale-1`]: creditSale({tender: "cash", creditOwedMinor: undefined}),
  });

  await assert.rejects(
    applyCustomerSale(
      db.asFirestore(),
      {tenantId: TENANT, saleId: "sale-1"},
      {lastAttempt: true}
    ),
    CustomerNotYetArrived
  );
  assert.equal(customer(db), undefined);
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
  assert.equal(customer(db)?.owing, false);
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

test("a partly returned credit sale reports its debt cancelled first", () => {
  // The flour (60000) came back: it cancels 60000 of the 70000 owed, as the
  // customer's ledger does, and the 30000 paid in cash stays paid.
  const breakdown = aggregateSalesByTender(
    [creditSale({saleId: "sale-1"})],
    undefined,
    new Map([["sale-1", new Map([["flour", 2]])]])
  );
  assert.equal(breakdown.cash.sales, 300);
  assert.equal(breakdown.other.sales, 100);
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
