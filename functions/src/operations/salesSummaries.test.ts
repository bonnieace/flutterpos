import assert from "node:assert/strict";
import test from "node:test";
import {FakeFirestore} from "../testing/fakeFirestore";
import {projectSaleTotals, readSalesSummaries, repairTotalsDay} from "./salesSummaries";
import {buildSalesComparison, resolveSalesReportStaff} from "./reports";

const day = "2026-10-05";
const query = {tenantId: "shop", previousStartDate: day, previousEndDate: day};
function sale(fake: FakeFirestore, id: string, staff = "cashier-a", tender = "cash") {
  fake.seed(`tenants/shop/sales/${id}`, {businessDate: day, soldById: staff, tender,
    total: 20, totalMinor: 2000, subtotal: 20, subtotalMinor: 2000, discount: 0, discountMinor: 0,
    items: [{productId: "p", categoryId: "drinks", quantity: 2, unitPrice: 10,
      unitPriceMinor: 1000, lineTotal: 20, lineTotalMinor: 2000, unitCost: 6, unitCostMinor: 600,
      cost: 12, costMinor: 1200}]});
}

test("existing days initialize once and match raw totals, staff and category filters", async () => {
  const fake = new FakeFirestore();
  sale(fake, "one"); sale(fake, "two", "cashier-b", "mpesa");
  for (const scope of [{}, {soldById: "cashier-a"}, {categoryId: "drinks"},
    {soldById: "cashier-b", categoryId: "drinks"}]) {
    const raw = await buildSalesComparison(fake.asFirestore(), {...query, ...scope});
    const {summaryVersion, ...actual} = await readSalesSummaries(fake.asFirestore(), {...query, ...scope});
    assert.equal(summaryVersion, 1);
    assert.deepEqual(actual, raw);
  }
  const writes = fake.writes.length;
  await readSalesSummaries(fake.asFirestore(), query);
  assert.equal(fake.writes.length, writes, "a warm report must not rebuild its sources");
});

test("duplicate and delayed events do not double count; tender edits replace previous contribution", async () => {
  const fake = new FakeFirestore(); sale(fake, "one");
  await readSalesSummaries(fake.asFirestore(), query);
  await projectSaleTotals(fake.asFirestore(), "shop", "one");
  sale(fake, "one", "cashier-a", "mpesa");
  await projectSaleTotals(fake.asFirestore(), "shop", "one");
  await projectSaleTotals(fake.asFirestore(), "shop", "one");
  const result = await readSalesSummaries(fake.asFirestore(), query);
  assert.equal(result.previous.sales, 20);
  assert.equal(result.previous.transactions, 1);
  assert.equal(result.byTender.cash.sales, 0);
  assert.equal(result.byTender.mpesa.sales, 20);
});

test("returns and late sales update already initialized days without rescanning the day", async () => {
  const fake = new FakeFirestore(); sale(fake, "one");
  await readSalesSummaries(fake.asFirestore(), query);
  fake.seed("tenants/shop/returns/r", {saleId: "one", businessDate: day,
    itemsReturned: [{productId: "p", quantity: 1}]});
  await projectSaleTotals(fake.asFirestore(), "shop", "one");
  sale(fake, "two", "cashier-b");
  await projectSaleTotals(fake.asFirestore(), "shop", "two");
  const result = await readSalesSummaries(fake.asFirestore(), query);
  const raw = await buildSalesComparison(fake.asFirestore(), query);
  assert.deepEqual(result.net, raw.net);
  assert.deepEqual(result.netByTender, raw.netByTender);
  const mine = await readSalesSummaries(fake.asFirestore(), {...query, soldById: "cashier-a"});
  assert.equal(mine.previous.sales, 20);
  assert.equal(mine.net.sales, 10);
  assert.equal(mine.returnsScanned, 1);
});

test("cashier scope cannot be widened by omitting or forging the staff filter", () => {
  assert.equal(resolveSalesReportStaff("cashier", "me"), "me");
  assert.equal(resolveSalesReportStaff("cashier", "me", "me"), "me");
  assert.throws(() => resolveSalesReportStaff("cashier", "me", "other"), {code: "permission-denied"});
  assert.equal(resolveSalesReportStaff("manager", "me"), undefined);
  assert.equal(resolveSalesReportStaff("admin", "me", "other"), "other");
});

test("nightly repair restores drifted summary figures from source contributions", async () => {
  const fake = new FakeFirestore(); sale(fake, "one");
  await readSalesSummaries(fake.asFirestore(), query);
  const summaries = await fake.asFirestore().collection("tenants/shop/sales_daily_totals").get();
  for (const doc of summaries.docs) await doc.ref.set({values: {gross_sales: 999999}}, {merge: true});
  await repairTotalsDay(fake.asFirestore(), "shop", day, ["one"]);
  const result = await readSalesSummaries(fake.asFirestore(), query);
  assert.equal(result.previous.sales, 20);
});
