import assert from "node:assert/strict";
import test from "node:test";
import {
  RETIRE_CLOSING_STOCK_REASON,
  planProductRetire,
  productRetireAdjustmentId,
  productRetireAuditId,
} from "./productRetire";

/**
 * The decisions behind `setProductRetired`, as units.
 *
 * **What changed, and why this file exists.** Retiring a product was a document
 * delete: the quantity went with the document, nothing recorded the stock
 * leaving, and the `stock_movements` below it were orphaned rather than removed,
 * so the ledger survived with no way into it. This path sets a flag and writes
 * the movement that clears the stock in the same transaction, which is the same
 * rule `createProduct` follows in the other direction.
 */

const TENANT = "tenant-a";
const PRODUCT = `pd_${"a".repeat(40)}`;
const ACTOR = "user-owner";
const REQUEST = "retire-request-1";

function plan(overrides: {retired?: boolean; previousQuantity?: number} = {}) {
  return planProductRetire({
    tenantId: TENANT,
    productId: PRODUCT,
    actorUid: ACTOR,
    requestId: REQUEST,
    retired: overrides.retired ?? true,
    previousQuantity: overrides.previousQuantity ?? 17,
  });
}

test("retiring a product that holds stock clears it through the ledger", () => {
  const retirement = plan({previousQuantity: 17});

  assert.equal(retirement.clears, true);
  assert.equal(retirement.quantity, 0);
  assert.equal(retirement.adjustmentId, productRetireAdjustmentId(REQUEST));
  assert.deepEqual(retirement.ledgerData, {
    tenantId: TENANT,
    productId: PRODUCT,
    sourceType: "product_retired",
    adjustmentType: "correction",
    quantityDelta: -17,
    previousQuantity: 17,
    quantityAfter: 0,
    reason: RETIRE_CLOSING_STOCK_REASON,
    actorUid: ACTOR,
    requestId: REQUEST,
  });
  assert.equal(retirement.auditData.eventType, "product_retired");
  assert.equal(retirement.auditData.mutatesQuantity, true);
});

test("retiring a product that holds nothing writes no ledger entry", () => {
  // There is nothing to account for, so inventing a zero-unit movement would be
  // a record of an event that did not happen.
  const retirement = plan({previousQuantity: 0});

  assert.equal(retirement.clears, false);
  assert.equal(retirement.adjustmentId, null);
  assert.equal(retirement.ledgerData, null);
  assert.equal(retirement.quantity, 0);
  assert.equal(retirement.auditData.mutatesQuantity, false);
  assert.equal(retirement.auditData.adjustmentId, null);
});

test("a product holding negative stock is still cleared, and to zero", () => {
  // Negative is a real, permitted state - a sale is never blocked by a stock
  // count - so a product can be retired from below zero, and the movement that
  // squares it is positive.
  const retirement = plan({previousQuantity: -3});

  assert.equal(retirement.clears, true);
  assert.equal(retirement.quantity, 0);
  assert.equal(
    (retirement.ledgerData as {quantityDelta: number}).quantityDelta,
    3
  );
  assert.equal(
    (retirement.ledgerData as {quantityAfter: number}).quantityAfter,
    0
  );
});

test("restoring gives no stock back, whatever the product held", () => {
  // Those units were accounted for as leaving. Handing them back would be a
  // second movement nobody could explain, so a restored product takes an
  // ordinary opening balance through the route that says where stock came from.
  for (const previousQuantity of [0, 17]) {
    const restoration = plan({retired: false, previousQuantity});

    assert.equal(restoration.clears, false, `held ${previousQuantity}`);
    assert.equal(restoration.ledgerData, null);
    assert.equal(restoration.quantity, previousQuantity);
    assert.equal(restoration.auditData.eventType, "product_restored");
  }
});

test("the ledger record carries exactly the fields adjustStock writes", () => {
  // A unit cleared and a unit adjusted out are the same unit, and reconciliation
  // reads one ledger. The list is `stock.ts`'s `immutableRecord`, less
  // `createdAt`, which only a write adds.
  assert.deepEqual(Object.keys(plan().ledgerData ?? {}).sort(), [
    "actorUid",
    "adjustmentType",
    "previousQuantity",
    "productId",
    "quantityAfter",
    "quantityDelta",
    "reason",
    "requestId",
    "sourceType",
    "tenantId",
  ]);
});

test("the documents are named after the request, not the product", () => {
  // **The difference from `createProduct`, and it matters.** A product may be
  // retired, restored and retired again, and each retirement clears whatever it
  // held at that moment. Deriving the IDs from the product would make the second
  // collide with the first and lose it.
  const first = planProductRetire({
    tenantId: TENANT,
    productId: PRODUCT,
    actorUid: ACTOR,
    requestId: "retire-request-1",
    retired: true,
    previousQuantity: 17,
  });
  const second = planProductRetire({
    tenantId: TENANT,
    productId: PRODUCT,
    actorUid: ACTOR,
    requestId: "retire-request-2",
    retired: true,
    previousQuantity: 4,
  });

  assert.notEqual(first.adjustmentId, second.adjustmentId);
  assert.notEqual(first.auditId, second.auditId);
  // And stable for one request, so a replay lands on one document.
  assert.equal(productRetireAdjustmentId(REQUEST), productRetireAdjustmentId(REQUEST));
  assert.equal(productRetireAuditId(REQUEST), productRetireAuditId(REQUEST));
});
