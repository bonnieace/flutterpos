import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  addStockQuantity,
  aggregateSales,
  aggregateSalesByTender,
  assertReturnWithinSale,
  assertAdjustmentDirection,
  assertDateRange,
  emptyTenderBreakdown,
  normalizeReturnStockLines,
  requireIsoDate,
  requireQuantityDelta,
  saleTenderBucket,
  SaleLike,
  TENDER_BUCKETS,
  TenderBreakdown,
} from "./domain";

test("stock quantities remain signed safe integers", () => {
  assert.equal(addStockQuantity(-2, -3), -5);
  assert.equal(addStockQuantity(-2, 7), 5);
  assert.throws(() => addStockQuantity(Number.MAX_SAFE_INTEGER, 1), HttpsError);
  assert.throws(() => requireQuantityDelta(0), HttpsError);
  assert.throws(() => requireQuantityDelta(1.5), HttpsError);
});

test("adjustment types enforce semantic direction", () => {
  assert.doesNotThrow(() => assertAdjustmentDirection("correction", -2));
  assert.doesNotThrow(() => assertAdjustmentDirection("restock", 2));
  assert.throws(() => assertAdjustmentDirection("restock", -2), HttpsError);
  assert.throws(() => assertAdjustmentDirection("damage", 2), HttpsError);
});

test("return lines are bounded, combined, and deterministically sorted", () => {
  assert.deepEqual(normalizeReturnStockLines([
    {itemId: "product-b", quantity: 2},
    {productId: "product-a", quantity: 1},
    {productId: "product-b", quantity: 3},
  ]), [
    {productId: "product-a", quantity: 1},
    {productId: "product-b", quantity: 5},
  ]);
  assert.throws(() => normalizeReturnStockLines([]), HttpsError);
  assert.throws(
    () => normalizeReturnStockLines([{productId: "product-a", quantity: -1}]),
    HttpsError
  );
});

test("returns cannot cumulatively restore more units than the immutable sale", () => {
  assert.doesNotThrow(() => assertReturnWithinSale(
    [{productId: "product-a", quantity: 5}],
    [{productId: "product-a", quantity: 2}],
    [{productId: "product-a", quantity: 3}]
  ));
  assert.throws(() => assertReturnWithinSale(
    [{productId: "product-a", quantity: 5}],
    [{productId: "product-a", quantity: 3}],
    [{productId: "product-a", quantity: 3}]
  ), HttpsError);
  assert.throws(() => assertReturnWithinSale(
    [{productId: "product-a", quantity: 5}],
    [{productId: "product-b", quantity: 1}],
    []
  ), HttpsError);
});

test("ISO dates reject impossible values and oversized ranges", () => {
  assert.equal(requireIsoDate("2026-07-29", "date"), "2026-07-29");
  assert.throws(() => requireIsoDate("2026-02-30", "date"), HttpsError);
  assert.doesNotThrow(() => assertDateRange("2026-01-01", "2026-12-31"));
  assert.throws(() => assertDateRange("2026-01-01", "2027-01-02"), HttpsError);
});

test("sales aggregation uses immutable line snapshots and category scope", () => {
  const sales = [{
    total: 50,
    items: [
      {categoryId: "beer", quantity: 2, unitPrice: 10, unitCost: 4},
      {categoryId: "food", quantity: 1, unitPrice: 30, unitCost: 12},
    ],
  }, {
    totalAmount: 12,
    items: [{categoryId: "beer", quantity: 1, price: 12}],
  }];
  assert.deepEqual(aggregateSales(sales), {
    sales: 62,
    profit: 42,
    transactions: 2,
    incompleteCostLineCount: 1,
  });
  assert.deepEqual(aggregateSales(sales, "beer"), {
    sales: 32,
    profit: 24,
    transactions: 2,
    incompleteCostLineCount: 1,
  });
});

test("sales aggregation uses deterministic minor-unit rounding", () => {
  assert.deepEqual(aggregateSales([
    {total: 0.1, items: [{quantity: 1, price: 0.1, unitCost: 0.03}]},
    {total: 0.2, items: [{quantity: 1, price: 0.2, unitCost: 0.07}]},
  ]), {
    sales: 0.3,
    profit: 0.2,
    transactions: 2,
    incompleteCostLineCount: 0,
  });
});

function totalOf(breakdown: TenderBreakdown): {sales: number; transactions: number} {
  let sales = 0;
  let transactions = 0;
  for (const bucket of TENDER_BUCKETS) {
    sales = Math.round((sales + breakdown[bucket].sales) * 100) / 100;
    transactions += breakdown[bucket].transactions;
  }
  return {sales, transactions};
}

test("a stored tender is bucketed exactly, never coerced", () => {
  assert.equal(saleTenderBucket("cash"), "cash");
  assert.equal(saleTenderBucket("mpesa"), "mpesa");
  assert.equal(saleTenderBucket("card"), "card");
  // Absent is a schema v1 sale: the record predates the field.
  assert.equal(saleTenderBucket(undefined), "unrecorded");
  assert.equal(saleTenderBucket(null), "unrecorded");
  // Present but unmodelled is a data problem, and a different one.
  for (const value of ["Cash", " cash", "CASH", "cheque", "", 1, true, {}, []]) {
    assert.equal(saleTenderBucket(value), "other", `${JSON.stringify(value)}`);
  }
});

test("an empty period reports every bucket at zero", () => {
  const breakdown = aggregateSalesByTender([]);
  assert.deepEqual(breakdown, emptyTenderBreakdown());
  assert.deepEqual(Object.keys(breakdown).sort(), [...TENDER_BUCKETS].sort());
  assert.deepEqual(totalOf(breakdown), {sales: 0, transactions: 0});
});

test("takings split by tender and the split adds back up", () => {
  const sales: SaleLike[] = [
    {tender: "cash", total: 50, items: [{categoryId: "beer", quantity: 2, unitPrice: 25}]},
    {tender: "cash", total: 12.5, items: [{categoryId: "food", quantity: 1, unitPrice: 12.5}]},
    {tender: "mpesa", total: 30.25, items: [{categoryId: "beer", quantity: 1, unitPrice: 30.25}]},
    {tender: "card", total: 7, items: [{categoryId: "food", quantity: 1, unitPrice: 7}]},
    // A schema v1 sale, written before the tender existed.
    {total: 4.75, items: [{categoryId: "beer", quantity: 1, unitPrice: 4.75}]},
    // Something wrote a tender nothing here models.
    {tender: "cheque", total: 9, items: [{categoryId: "food", quantity: 1, unitPrice: 9}]},
  ];

  const breakdown = aggregateSalesByTender(sales);

  assert.deepEqual(breakdown.cash, {sales: 62.5, transactions: 2});
  assert.deepEqual(breakdown.mpesa, {sales: 30.25, transactions: 1});
  assert.deepEqual(breakdown.card, {sales: 7, transactions: 1});
  assert.deepEqual(breakdown.unrecorded, {sales: 4.75, transactions: 1});
  assert.deepEqual(breakdown.other, {sales: 9, transactions: 1});

  // The whole point: the split describes the same money as the total.
  const aggregate = aggregateSales(sales);
  assert.deepEqual(totalOf(breakdown), {
    sales: aggregate.sales,
    transactions: aggregate.transactions,
  });
});

test("a category filter narrows the split exactly as it narrows the total", () => {
  const sales: SaleLike[] = [
    {
      tender: "cash",
      total: 50,
      items: [
        {categoryId: "beer", quantity: 2, unitPrice: 10},
        {categoryId: "food", quantity: 1, unitPrice: 30},
      ],
    },
    // Skipped entirely: it holds no line in the requested category, so it must
    // not appear in any bucket either.
    {tender: "mpesa", total: 30, items: [{categoryId: "food", quantity: 1, unitPrice: 30}]},
    {tender: "card", total: 12, items: [{categoryId: "beer", quantity: 1, price: 12}]},
  ];

  const breakdown = aggregateSalesByTender(sales, "beer");

  // The cash sale contributes its matching lines only, not its recorded total.
  assert.deepEqual(breakdown.cash, {sales: 20, transactions: 1});
  assert.deepEqual(breakdown.mpesa, {sales: 0, transactions: 0});
  assert.deepEqual(breakdown.card, {sales: 12, transactions: 1});

  const aggregate = aggregateSales(sales, "beer");
  assert.deepEqual(totalOf(breakdown), {
    sales: aggregate.sales,
    transactions: aggregate.transactions,
  });
  // And it is genuinely narrower than the unfiltered answer.
  assert.equal(aggregateSales(sales).transactions, 3);
});

test("the split rounds in whole minor units, so grouping cannot change it", () => {
  const sales: SaleLike[] = [
    {tender: "cash", total: 0.1, items: [{quantity: 1, price: 0.1}]},
    {tender: "mpesa", total: 0.2, items: [{quantity: 1, price: 0.2}]},
    {tender: "cash", total: 0.2, items: [{quantity: 1, price: 0.2}]},
  ];

  const breakdown = aggregateSalesByTender(sales);

  assert.deepEqual(breakdown.cash, {sales: 0.3, transactions: 2});
  assert.deepEqual(breakdown.mpesa, {sales: 0.2, transactions: 1});
  assert.equal(totalOf(breakdown).sales, aggregateSales(sales).sales);
});
