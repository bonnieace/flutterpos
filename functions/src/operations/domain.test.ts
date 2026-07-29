import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  addStockQuantity,
  aggregateSales,
  assertReturnWithinSale,
  assertAdjustmentDirection,
  assertDateRange,
  normalizeReturnStockLines,
  requireIsoDate,
  requireQuantityDelta,
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
