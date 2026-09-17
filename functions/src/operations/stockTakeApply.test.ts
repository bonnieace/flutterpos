import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  MAXIMUM_STOCK_TAKE_APPLY_LINES,
  STOCK_TAKE_REASON,
  planStockTakeLine,
  stockTakeAdjustmentId,
} from "./stockTakeApply";
import {MAXIMUM_STOCK_TAKE_LINES} from "./stockTake";

/**
 * The arithmetic that decides where a shop's stock lands after a count.
 *
 * **The test that matters most is "a sale between counting and approving".** It
 * is the one that pins the delta-not-absolute decision, and it is written as an
 * assertion that `quantityAfter` does *not* equal what was counted - which reads
 * like a bug unless the reason is right there beside it. It is not a bug: the
 * variance is a fact about the moment of counting, and a sale since is a real
 * movement of its own.
 */

const TENANT = "tenant-a";
const TAKE = `st_${"a".repeat(40)}`;
const PRODUCT = `pd_${"1".repeat(40)}`;
const ACTOR = "user-manager";
const BUSINESS_DATE = "2026-09-15";

function plan(
  overrides: {
    variance?: number;
    storedQuantity?: number;
    businessDate?: string;
  } = {}
) {
  return planStockTakeLine({
    tenantId: TENANT,
    takeId: TAKE,
    productId: PRODUCT,
    actorUid: ACTOR,
    businessDate: overrides.businessDate ?? BUSINESS_DATE,
    variance: overrides.variance ?? -2,
    storedQuantity: overrides.storedQuantity ?? 40,
  });
}

test("a shortfall takes the units off the books and says so", () => {
  const correction = plan({variance: -2, storedQuantity: 40});

  assert.equal(correction.previousQuantity, 40);
  assert.equal(correction.quantityDelta, -2);
  assert.equal(correction.quantity, 38);
  assert.equal(correction.ledgerData.sourceType, "stock_take");
  assert.equal(correction.ledgerData.adjustmentType, "inventory_count");
  assert.equal(correction.ledgerData.reason, STOCK_TAKE_REASON);
});

test("a surplus is applied the same way, in the other direction", () => {
  // A count finds more than the books claim as readily as less, which is why
  // the adjustment type has to be one that moves either way.
  const correction = plan({variance: 3, storedQuantity: 40});

  assert.equal(correction.quantityDelta, 3);
  assert.equal(correction.quantity, 43);
});

test("a sale between counting and approving is not undone", () => {
  // **The decision this whole file turns on.** The books said 40 and the shelf
  // held 38, so the count recorded a variance of -2. Two were then sold, so the
  // books now say 38. Applying the variance gives 36 - the two that were sold
  // and the two that were never there.
  //
  // Setting the quantity to the counted 38 instead would silently put the two
  // sold units back on the shelf. So `quantityAfter` deliberately does NOT equal
  // `counted` here, and a later reader must not "fix" that.
  const correction = plan({variance: -2, storedQuantity: 38});

  assert.equal(correction.previousQuantity, 38);
  assert.equal(correction.quantity, 36);
  assert.notEqual(
    correction.quantity,
    38,
    "the counted figure is not the answer once trading has happened since"
  );
});

test("books already below zero are corrected, not clamped", () => {
  // Negative is a real, permitted state - a sale is never blocked by a stock
  // count - so the correction lands wherever the arithmetic puts it.
  assert.equal(plan({variance: -1, storedQuantity: 0}).quantity, -1);
  assert.equal(plan({variance: 5, storedQuantity: -3}).quantity, 2);
});

test("a correction that would leave the safe range is refused", () => {
  assert.throws(
    () => plan({variance: 1, storedQuantity: Number.MAX_SAFE_INTEGER}),
    (error: unknown) => error instanceof HttpsError && error.code === "out-of-range"
  );
});

test("the ledger record carries exactly the fields adjustStock writes", () => {
  // A unit counted off and a unit adjusted off are the same unit, and
  // reconciliation reads one ledger. `takeId` and `businessDate` are the two
  // additions: one makes a movement traceable back to the count that caused it,
  // the other says which trading day that count was about.
  assert.deepEqual(Object.keys(plan().ledgerData).sort(), [
    "actorUid",
    "adjustmentType",
    "businessDate",
    "previousQuantity",
    "productId",
    "quantityAfter",
    "quantityDelta",
    "reason",
    "requestId",
    "sourceType",
    "takeId",
    "tenantId",
  ]);
});

test("the correction is dated to the count, not to the approval", () => {
  // **The defect this closes.** A count taken on Tuesday and approved on Friday
  // writes a correction belonging to Tuesday. Dating it to the approval put the
  // shortfall on Friday instead: Tuesday read clean, and Friday read short by
  // units that never moved on it.
  //
  // Nothing here reads a clock, and that is the point - the day is a fact the
  // count carried, not one this arithmetic is entitled to decide.
  const tuesday = plan({businessDate: "2026-09-15"});
  const friday = plan({businessDate: "2026-09-18"});

  assert.equal(tuesday.ledgerData.businessDate, "2026-09-15");
  assert.equal(friday.ledgerData.businessDate, "2026-09-18");
});

test("the trading day does not reach the adjustment identity", () => {
  // The ID is the count and the product, so re-applying a count that somehow
  // arrived with a different day still lands on the one document rather than
  // writing a second correction beside the first.
  assert.equal(
    plan({businessDate: "2026-09-15"}).adjustmentId,
    plan({businessDate: "2026-09-18"}).adjustmentId
  );
});

test("an adjustment is named after the count and the product together", () => {
  const first = stockTakeAdjustmentId(TAKE, PRODUCT);

  // Stable, so every replay of one apply lands on one document.
  assert.equal(first, stockTakeAdjustmentId(TAKE, PRODUCT));
  assert.match(first, /^sa_st_[0-9a-f]{40}$/);
  // And distinct per product and per count, so correcting the same product in
  // next week's count is a separate movement rather than a collision.
  assert.notEqual(first, stockTakeAdjustmentId(TAKE, `pd_${"2".repeat(40)}`));
  assert.notEqual(first, stockTakeAdjustmentId(`st_${"b".repeat(40)}`, PRODUCT));
});

test("a page corrects fewer lines than a page records", () => {
  // Applying writes three documents per line where submitting writes one, so
  // one transaction holds fewer of them.
  assert.ok(MAXIMUM_STOCK_TAKE_APPLY_LINES >= 1);
  assert.ok(MAXIMUM_STOCK_TAKE_APPLY_LINES < MAXIMUM_STOCK_TAKE_LINES);
  assert.ok(MAXIMUM_STOCK_TAKE_APPLY_LINES * 3 <= MAXIMUM_STOCK_TAKE_LINES);
});
