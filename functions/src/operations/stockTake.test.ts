import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  MAXIMUM_STOCK_TAKE_LINES,
  StockTakeLineInput,
  planStockTakePage,
  readStockTakeLines,
  readStockTakeScope,
} from "./stockTake";
import {MAXIMUM_IMPORT_OPENING_STOCK} from "./productImport";

/**
 * The decisions behind `submitStockTake`, as units.
 *
 * Three properties carry the whole design, and each is pinned below:
 *
 * - **A count moves no stock.** Nothing in a plan names `products.quantity`, a
 *   `stock_adjustments` record or a `stock_movements` entry. A cashier may submit
 *   one, which is only safe because of that.
 * - **A page is replayable.** Nothing is minted per page, so re-sending one lands
 *   on the same documents with the same values - and must not move the take's
 *   totals a second time.
 * - **Nothing counted is ever thrown away**, including a count of a product the
 *   server has not heard of yet.
 */

const TENANT = "tenant-a";
const TAKE = `st_${"a".repeat(40)}`;
const COUNTER = "user-cashier";

function line(overrides: Partial<StockTakeLineInput> = {}): StockTakeLineInput {
  return {
    productId: `pd_${"1".repeat(40)}`,
    counted: 10,
    seenQuantity: 12,
    countedAt: "2026-09-13T07:30:00.000Z",
    ...overrides,
  };
}

function plan(options: {
  lines?: readonly StockTakeLineInput[];
  stored?: Record<string, number | null>;
  existing?: readonly string[];
  isFinalPage?: boolean;
  page?: number;
} = {}) {
  const lines = options.lines ?? [line()];
  const stored = new Map<string, number | null>(
    Object.entries(options.stored ?? {[line().productId]: 12})
  );
  return planStockTakePage({
    tenantId: TENANT,
    takeId: TAKE,
    counterUid: COUNTER,
    businessDate: "2026-09-13",
    scope: {kind: "all"},
    productsInScope: 40,
    page: options.page ?? 0,
    isFinalPage: options.isFinalPage ?? false,
    lines,
    storedQuantities: stored,
    existingLineIds: new Set(options.existing ?? []),
  });
}

test("a count records the difference from the books without moving them", () => {
  const page = plan({lines: [line({counted: 10})], stored: {[line().productId]: 12}});

  assert.equal(page.lines.length, 1);
  const recorded = page.lines[0].data;
  assert.equal(recorded.counted, 10);
  assert.equal(recorded.expected, 12);
  assert.equal(recorded.variance, -2);
  assert.equal(recorded.matched, true);
  assert.equal(page.countedLineDelta, 1);
  assert.equal(page.varianceLineDelta, 1);
  assert.equal(page.absoluteVarianceDelta, 2);

  // **The property the whole design rests on.** A count is an observation; if it
  // moved stock, the person who caused a shortfall could count it away.
  const keys = Object.keys(recorded);
  for (const forbidden of ["quantity", "quantityDelta", "quantityAfter", "adjustmentType"]) {
    assert.ok(!keys.includes(forbidden), `a count must not write ${forbidden}`);
  }
});

test("a surplus counts as much as a shortfall", () => {
  const page = plan({lines: [line({counted: 15})], stored: {[line().productId]: 12}});

  assert.equal(page.lines[0].data.variance, 3);
  assert.equal(page.varianceLineDelta, 1);
  assert.equal(page.absoluteVarianceDelta, 3);
});

test("a count that agrees with the books is a counted line and not a variance", () => {
  // Worth its own test: the summary is what management's list is sorted and
  // filtered by, and a take where everything agreed must say so rather than look
  // like a take nobody finished.
  const page = plan({lines: [line({counted: 12})], stored: {[line().productId]: 12}});

  assert.equal(page.lines[0].data.variance, 0);
  assert.equal(page.countedLineDelta, 1);
  assert.equal(page.varianceLineDelta, 0);
  assert.equal(page.absoluteVarianceDelta, 0);
});

test("books showing negative stock still produce an honest variance", () => {
  // Negative is a real, permitted state - a sale is never blocked by a stock
  // count - so the books can say less than none while the shelf holds three.
  const page = plan({lines: [line({counted: 3})], stored: {[line().productId]: -2}});

  assert.equal(page.lines[0].data.expected, -2);
  assert.equal(page.lines[0].data.variance, 5);
  assert.equal(page.absoluteVarianceDelta, 5);
});

test("a count of a product the server has not heard of is kept, not discarded", () => {
  // A product added with no connection and counted in the same session: the
  // create and this page sit in the outbox under different target paths and the
  // drain runs those concurrently, so the count can arrive first. Refusing would
  // be permanent and would lose what somebody actually counted.
  const page = plan({lines: [line({counted: 7})], stored: {[line().productId]: null}});

  const recorded = page.lines[0].data;
  assert.equal(recorded.counted, 7);
  assert.equal(recorded.expected, null);
  assert.equal(recorded.variance, null);
  assert.equal(recorded.matched, false);
  assert.equal(page.countedLineDelta, 1);
  assert.equal(page.unmatchedLineDelta, 1);
  // It cannot be a variance, because there is nothing to differ from.
  assert.equal(page.varianceLineDelta, 0);
  assert.equal(page.absoluteVarianceDelta, 0);
});

test("re-sending a page rewrites its lines and moves no total twice", () => {
  // **The replay property.** Nothing is minted per page, so the outbox may send
  // one again at any time. The line documents are keyed by product and take the
  // same values; the take's running totals must not.
  const first = plan({lines: [line({counted: 10})], stored: {[line().productId]: 12}});
  const replay = plan({
    lines: [line({counted: 10})],
    stored: {[line().productId]: 12},
    existing: [line().productId],
  });

  assert.deepEqual(replay.lines[0].data, first.lines[0].data);
  assert.equal(replay.lines[0].counts, false);
  assert.equal(replay.countedLineDelta, 0);
  assert.equal(replay.varianceLineDelta, 0);
  assert.equal(replay.absoluteVarianceDelta, 0);
  assert.equal(replay.unmatchedLineDelta, 0);
});

test("a page mixing new and already-recorded lines counts only the new ones", () => {
  const already = `pd_${"2".repeat(40)}`;
  const fresh = `pd_${"3".repeat(40)}`;
  const page = plan({
    lines: [
      line({productId: already, counted: 1}),
      line({productId: fresh, counted: 4}),
    ],
    stored: {[already]: 5, [fresh]: 10},
    existing: [already],
  });

  assert.equal(page.lines.length, 2);
  assert.equal(page.countedLineDelta, 1);
  assert.equal(page.varianceLineDelta, 1);
  assert.equal(page.absoluteVarianceDelta, 6);
});

test("only the final page completes the take", () => {
  assert.equal(plan({isFinalPage: false}).completes, false);
  assert.equal(plan({isFinalPage: true}).completes, true);
});

test("every page carries the same header, which is what makes merging safe", () => {
  // The outbox keeps the pages of one take in order because they share a target
  // path, but this callable is not entitled to assume it. Every page merging an
  // identical header means a take is complete whichever page lands first.
  assert.deepEqual(plan({page: 0}).header, plan({page: 3, isFinalPage: true}).header);
  assert.deepEqual(plan().header, {
    tenantId: TENANT,
    counterUid: COUNTER,
    businessDate: "2026-09-13",
    scope: {kind: "all"},
    productsInScope: 40,
  });
});

test("the counter on a line is the actor, never anything the device sent", () => {
  const page = plan();

  assert.equal(page.lines[0].data.counterUid, COUNTER);
  assert.equal(page.header.counterUid, COUNTER);
});

test("what the device believed is recorded beside what it counted", () => {
  // Recorded, never rendered. It is how a count entered at ten and submitted at
  // two can be read against the window it was taken in, without the counter ever
  // having been shown a figure to match.
  const page = plan({lines: [line({seenQuantity: 12, counted: 10})]});

  assert.equal(page.lines[0].data.seenQuantity, 12);
  assert.equal(page.lines[0].data.countedAt, "2026-09-13T07:30:00.000Z");
});

test("a shelf cannot hold a negative or fractional count", () => {
  for (const counted of [-1, 1.5, Number.NaN, "4"]) {
    assert.throws(
      () => readStockTakeLines([{...line(), counted}]),
      (error: unknown) => error instanceof HttpsError &&
        error.code === "invalid-argument",
      `counted ${String(counted)} must be refused`
    );
  }
  assert.equal(readStockTakeLines([{...line(), counted: 0}])[0].counted, 0);
});

test("a count is bounded by the figure the import path is bounded by", () => {
  assert.equal(
    readStockTakeLines([{...line(), counted: MAXIMUM_IMPORT_OPENING_STOCK}])[0].counted,
    MAXIMUM_IMPORT_OPENING_STOCK
  );
  assert.throws(
    () => readStockTakeLines([{...line(), counted: MAXIMUM_IMPORT_OPENING_STOCK + 1}]),
    (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument"
  );
});

test("what the device saw may be negative, or absent entirely", () => {
  assert.equal(readStockTakeLines([{...line(), seenQuantity: -3}])[0].seenQuantity, -3);
  assert.equal(readStockTakeLines([{...line(), seenQuantity: null}])[0].seenQuantity, null);
  const withoutSeen: Record<string, unknown> = {...line()};
  delete withoutSeen.seenQuantity;
  assert.equal(readStockTakeLines([withoutSeen])[0].seenQuantity, null);
  assert.throws(
    () => readStockTakeLines([{...line(), seenQuantity: 1.5}]),
    (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument"
  );
});

test("a page naming one product twice is refused", () => {
  // The line document is keyed by product, so a duplicate would silently discard
  // one of the two numbers rather than record both.
  assert.throws(
    () => readStockTakeLines([line({counted: 1}), line({counted: 2})]),
    (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument"
  );
});

test("a page is bounded by what one transaction can write", () => {
  const full = Array.from({length: MAXIMUM_STOCK_TAKE_LINES}, (_, index) =>
    line({productId: `pd_${String(index).padStart(40, "0")}`}));
  assert.equal(readStockTakeLines(full).length, MAXIMUM_STOCK_TAKE_LINES);

  assert.throws(
    () => readStockTakeLines([
      ...full,
      line({productId: `pd_${"f".repeat(40)}`}),
    ]),
    (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument"
  );
  assert.throws(
    () => readStockTakeLines([]),
    (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument"
  );
});

test("a scope is the whole catalog or one category of it, and nothing else", () => {
  assert.deepEqual(readStockTakeScope({kind: "all"}), {kind: "all"});
  assert.deepEqual(readStockTakeScope({kind: "category", categoryId: "ct_bakery"}), {
    kind: "category",
    categoryId: "ct_bakery",
  });
  for (const scope of [{kind: "aisle"}, {kind: "category"}, {}, null]) {
    assert.throws(
      () => readStockTakeScope(scope),
      (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument",
      `scope ${JSON.stringify(scope)} must be refused`
    );
  }
});
