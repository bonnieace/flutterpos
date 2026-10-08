import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {TenantRole} from "../core/model";
import {fingerprintPayload} from "../core/idempotency";
import {
  MAXIMUM_PRODUCT_BATCH_ROWS,
  ProductBatchInput,
  ProductBatchRowOutcome,
  assertProductBatchAuthorized,
  planProductBatch,
  productBatchFingerprintInput,
  productBatchId,
  productBatchRowUpdateId,
  readProductBatchInput,
} from "./productBatch";
import {StoredProductFields} from "./productUpdate";

/**
 * The decisions behind `updateProducts`, as units.
 *
 * Everything about *what* one row may correct is already pinned by
 * `productUpdate.test.ts` and is deliberately not repeated here - a row is
 * planned by the same function a single correction is, and a suite that
 * re-asserted the price arithmetic would be pinning a copy rather than the
 * original. What is new, and what this file is for, is everything a bulk change
 * has to decide that one product at a time never raises:
 *
 * - which defects belong to a row and which take the whole request down,
 * - what "already correct" means when it is one row of four hundred,
 * - how a preview differs from a commit, which is: it writes nothing,
 * - and what a retry is recognised by.
 *
 * The identity strings are the sha256 hex the idempotency wrapper produces. They
 * are opaque here on purpose: what matters is which inputs change them.
 */

const CATEGORY = "ct_drinks";
const IDENTITY = "a".repeat(64);
const OTHER_IDENTITY = "b".repeat(64);

function storedProduct(overrides: StoredProductFields = {}): StoredProductFields {
  return {
    name: "Cola 500ml",
    SKU: "CL500",
    price: 19.99,
    quantity: 12,
    categoryId: CATEGORY,
    ...overrides,
  };
}

function batch(
  rows: readonly unknown[],
  overrides: Record<string, unknown> = {}
): ProductBatchInput {
  return readProductBatchInput({
    tenantId: "tenant-a",
    requestId: "request-00000001",
    mode: "commit",
    rows,
    ...overrides,
  });
}

/** The refusal a whole request reports, which is what a client classifies on. */
function refusal(attempt: () => unknown): HttpsError {
  try {
    attempt();
  } catch (error) {
    assert.ok(error instanceof HttpsError, `${error}`);
    return error;
  }
  return assert.fail("The bulk change was not refused.");
}

function plan(
  input: ProductBatchInput,
  options: {
    products?: Record<string, StoredProductFields>;
    categories?: readonly string[];
    identityDocumentId?: string;
  } = {}
) {
  return planProductBatch({
    input,
    identityDocumentId: options.identityDocumentId ?? IDENTITY,
    storedProducts: new Map(Object.entries(options.products ?? {})),
    existingCategoryIds: new Set(options.categories ?? [CATEGORY]),
  });
}

/** A business holding `count` identical sellable products, `pd_0` upward. */
function catalog(count: number): Record<string, StoredProductFields> {
  return Object.fromEntries(
    Array.from({length: count}, (_, index) => [
      `pd_${index}`,
      storedProduct({SKU: `CL${index}`}),
    ])
  );
}

function outcome(
  outcomes: readonly ProductBatchRowOutcome[],
  index: number
): ProductBatchRowOutcome {
  const found = outcomes.find((row) => row.index === index);
  assert.ok(found, `no outcome for row ${index}`);
  return found;
}

test("a request that omits the mode is refused rather than assumed", () => {
  // The failure modes are not symmetric: a preview mistaken for a commit is a
  // report nobody acts on, and a commit mistaken for a preview changes products
  // nobody agreed to. So there is no default.
  assert.equal(
    refusal(() => batch([{productId: "pd_0", name: "Cola"}], {mode: undefined})).code,
    "invalid-argument"
  );
  assert.equal(
    refusal(() => batch([{productId: "pd_0", name: "Cola"}], {mode: "dry-run"})).code,
    "invalid-argument"
  );
  assert.equal(batch([{productId: "pd_0", name: "Cola"}], {mode: "preview"}).mode, "preview");
});

test("an unknown key on the request is refused, not dropped", () => {
  // Same contract `updateProduct` keeps for a field. Silently ignoring one would
  // make "this never writes quantity" something a caller has to take on trust.
  assert.equal(
    refusal(() => batch([{productId: "pd_0", name: "Cola"}], {quantity: 4})).code,
    "invalid-argument"
  );
});

test("rows must be a non-empty array", () => {
  assert.equal(refusal(() => batch("pd_0" as unknown as never[])).code, "invalid-argument");
  assert.equal(refusal(() => batch([])).code, "invalid-argument");
});

test("more rows than the bound is refused for the whole request", () => {
  const rows = Array.from(
    {length: MAXIMUM_PRODUCT_BATCH_ROWS + 1},
    (_, index) => ({productId: `pd_${index}`, name: `Cola ${index}`})
  );

  const error = refusal(() => batch(rows));

  assert.equal(error.code, "invalid-argument");
  // Applying the first fifty and reporting the rest as failed would read as
  // partial success rather than as a caller that needs to chain, so the message
  // says what to do instead.
  assert.match(error.message, /further request with its own requestId/);
  assert.equal(batch(rows.slice(0, MAXIMUM_PRODUCT_BATCH_ROWS)).rows.length, 50);
});

test("a product named twice takes the whole request down, naming both rows", () => {
  // Two rows for one product are two conflicting intents, and there is no honest
  // outcome to report for either: the second is planned against a document the
  // first has already changed, so both would describe a before-and-after that
  // never existed.
  const error = refusal(() => batch([
    {productId: "pd_0", name: "Cola"},
    {productId: "pd_1", name: "Fanta"},
    {productId: "pd_0", price: 21},
  ]));

  assert.equal(error.code, "invalid-argument");
  assert.match(error.message, /rows\[0\], rows\[2\]/);
});

test("a product named by one good row and one broken row still counts as twice", () => {
  // The duplicate is recorded before the rest of the row is read, so a spelling
  // mistake in one of the two cannot hide the ambiguity.
  const error = refusal(() => batch([
    {productId: "pd_0", price: 19.999},
    {productId: "pd_0", name: "Cola"},
  ]));

  assert.match(error.message, /rows\[0\], rows\[1\]/);
});

test("a row's own defect is that row's problem, and the rest still parse", () => {
  const input = batch([
    {productId: "pd_0", name: "Cola 500 ml"},
    {productId: "pd_1", price: 19.999},
    {productId: "pd_2", sku: "FN500"},
  ]);

  assert.deepEqual(input.rows.map((row) => row.index), [0, 2]);
  assert.equal(input.rowCount, 3);
  assert.deepEqual(input.refusals.map((row) => [row.index, row.productId, row.code]), [
    [1, "pd_1", "invalid-argument"],
  ]);
});

test("a row that mentions quantity is refused with the message that names adjustStock", () => {
  // The single most important refusal in the single-product path, and a bulk
  // path that lost it would be a second way to move stock with no ledger entry.
  const input = batch([{productId: "pd_0", quantity: 40}]);

  assert.equal(input.rows.length, 0);
  assert.match(input.refusals[0].message, /adjustStock/);
});

test("a row that repeats the business or the request ID is refused", () => {
  // Those belong to the request that carries the rows. A row that could name a
  // business would let one payload address two.
  const input = batch([
    {productId: "pd_0", tenantId: "tenant-b", name: "Cola"},
    {productId: "pd_1", requestId: "request-00000002", name: "Fanta"},
  ]);

  assert.equal(input.rows.length, 0);
  assert.deepEqual(input.refusals.map((row) => row.index), [0, 1]);
});

test("a row naming no editable field, and a row naming no product, are refusals", () => {
  const input = batch([{productId: "pd_0"}, {name: "Cola"}, "pd_2"]);

  assert.equal(input.rows.length, 0);
  assert.deepEqual(
    input.refusals.map((row) => [row.index, row.productId]),
    [[0, "pd_0"], [1, null], [2, null]]
  );
});

test("a manager may correct descriptions in bulk", () => {
  const input = batch([
    {productId: "pd_0", name: "Cola 500 ml"},
    {productId: "pd_1", sku: "FN500", categoryId: CATEGORY},
  ]);

  assert.doesNotThrow(() => assertProductBatchAuthorized("manager", input.rows));
});

test("a manager naming money anywhere in the request is refused, and told where", () => {
  // The tier is delegated to the single-product rule so the two cannot drift.
  // What is added is the message: a rename of four hundred rows carrying three
  // stray price columns has to say which three, or the refusal is not
  // actionable.
  const input = batch([
    {productId: "pd_0", name: "Cola 500 ml"},
    {productId: "pd_1", price: 21},
    {productId: "pd_2", cost: 12},
  ]);

  const error = refusal(() => assertProductBatchAuthorized("manager", input.rows));

  assert.equal(error.code, "permission-denied");
  assert.match(error.message, /rows\[1\], rows\[2\]/);
  for (const role of ["owner", "admin"] as TenantRole[]) {
    assert.doesNotThrow(() => assertProductBatchAuthorized(role, input.rows));
  }
});

test("a refusal naming more monetary rows than it lists summarizes the rest", () => {
  const input = batch(Array.from(
    {length: 14},
    (_, index) => ({productId: `pd_${index}`, price: 21})
  ));

  const error = refusal(() => assertProductBatchAuthorized("manager", input.rows));

  assert.match(error.message, /rows\[9\], and 4 more/);
});

test("a row that already holds every requested value is unchanged, not failed", () => {
  // One product at a time this is refused, because it can only be a caller
  // defect. In a bulk change it is the ordinary case: re-running a change that
  // half applied must be able to finish, and it cannot if the rows that already
  // landed take the request down with them.
  const result = plan(
    batch([
      {productId: "pd_0", name: "Cola 500ml"},
      {productId: "pd_1", name: "Fanta 500 ml"},
    ]),
    {products: catalog(2)}
  );

  assert.equal(outcome(result.outcomes, 0).status, "unchanged");
  assert.deepEqual(outcome(result.outcomes, 0).changedFields, []);
  assert.equal(outcome(result.outcomes, 1).status, "updated");
  assert.equal(result.unchangedCount, 1);
  assert.equal(result.updatedCount, 1);
  // An unchanged row writes nothing at all, so no audit entry claims a
  // correction that did not happen.
  assert.deepEqual(result.writes.map((write) => write.productId), ["pd_1"]);
});

test("an unchanged row on a product no device can read still fails", () => {
  // The resulting document is validated whether or not anything moved, so
  // "nothing to do here" never becomes a way to skip the read model.
  const result = plan(
    batch([{productId: "pd_0", name: "Cola 500ml"}]),
    {products: {pd_0: storedProduct({name: "Cola 500ml", price: "19.99"})}}
  );

  assert.equal(outcome(result.outcomes, 0).status, "failed");
  assert.equal(outcome(result.outcomes, 0).code, "failed-precondition");
});

test("a missing product, a missing category, and a broken document fail one row each", () => {
  const result = plan(
    batch([
      {productId: "pd_0", name: "Cola 500 ml"},
      {productId: "pd_absent", name: "Ghost"},
      {productId: "pd_1", categoryId: "ct_missing"},
      {productId: "pd_2", name: "Sprite"},
    ]),
    {products: {...catalog(3), pd_2: storedProduct({quantity: 4.5})}}
  );

  assert.equal(outcome(result.outcomes, 0).status, "updated");
  assert.equal(outcome(result.outcomes, 1).code, "not-found");
  assert.equal(outcome(result.outcomes, 2).code, "failed-precondition");
  assert.match(outcome(result.outcomes, 2).message ?? "", /category does not exist/);
  // A stored quantity that is not an integer is an operator's problem, and
  // saying so on that row alone is the whole point of a per-row outcome.
  assert.match(outcome(result.outcomes, 3).message ?? "", /needs an operator/);
  assert.equal(result.updatedCount, 1);
  assert.equal(result.failedCount, 3);
  assert.deepEqual(result.writes.map((write) => write.productId), ["pd_0"]);
});

test("outcomes come back in request order, refusals among them", () => {
  // A refused row never reaches the planning pass, so without the sort the two
  // groups would come back separated and a caller could not line the answer up
  // against its own rows by position.
  const result = plan(
    batch([
      {productId: "pd_0", price: 19.999},
      {productId: "pd_1", name: "Fanta 500 ml"},
      {productId: "pd_2", price: -1},
      {productId: "pd_3", name: "Sprite 500 ml"},
    ]),
    {products: catalog(4)}
  );

  assert.deepEqual(result.outcomes.map((row) => row.index), [0, 1, 2, 3]);
  assert.deepEqual(
    result.outcomes.map((row) => row.status),
    ["failed", "updated", "failed", "updated"]
  );
});

test("a preview plans the same rows and writes none of them", () => {
  const rows = [
    {productId: "pd_0", name: "Cola 500 ml", price: 21},
    {productId: "pd_1", name: "Fanta 500ml"},
  ];
  const products = catalog(2);

  const preview = plan(batch(rows, {mode: "preview"}), {products});
  const commit = plan(batch(rows), {products});

  assert.deepEqual(
    preview.outcomes.map((row) => [row.index, row.status, row.changedFields]),
    commit.outcomes.map((row) => [row.index, row.status, row.changedFields])
  );
  // What the product *would* hold is the whole point of a preview.
  assert.equal(outcome(preview.outcomes, 0).product?.priceMinor, 2100);
  assert.deepEqual(preview.writes, []);
  // A preview names no audit entry, so its outcome can never be mistaken for a
  // record of something that happened.
  assert.equal(outcome(preview.outcomes, 0).updateId, null);
  assert.ok(outcome(commit.outcomes, 0).updateId?.startsWith("pu_"));
});

test("a corrected row reports the cost it now carries, cleared or not", () => {
  const result = plan(
    batch([
      {productId: "pd_0", cost: 12.5},
      {productId: "pd_1", cost: null},
    ]),
    {products: {pd_0: storedProduct(), pd_1: storedProduct({cost: 9})}}
  );

  assert.equal(outcome(result.outcomes, 0).product?.cost, 12.5);
  assert.equal(outcome(result.outcomes, 0).product?.costMinor, 1250);
  assert.deepEqual(outcome(result.outcomes, 1).changedFields, ["cost"]);
  assert.equal(outcome(result.outcomes, 1).product?.cost, null);
  assert.equal(outcome(result.outcomes, 1).product?.costMinor, null);
});

test("a row's audit entry is identified by its product, not by where it sat", () => {
  // Which is what makes re-sending a request with its rows reordered land on the
  // same documents rather than duplicating every entry.
  assert.equal(
    productBatchRowUpdateId(IDENTITY, "pd_0"),
    productBatchRowUpdateId(IDENTITY, "pd_0")
  );
  assert.notEqual(
    productBatchRowUpdateId(IDENTITY, "pd_0"),
    productBatchRowUpdateId(IDENTITY, "pd_1")
  );
  // A different request is a different set of entries, so a second change to the
  // same product is recorded rather than refused by the first one's document.
  assert.notEqual(
    productBatchRowUpdateId(IDENTITY, "pd_0"),
    productBatchRowUpdateId(OTHER_IDENTITY, "pd_0")
  );
  assert.match(productBatchRowUpdateId(IDENTITY, "pd_0"), /^pu_[0-9a-f]{40}$/);
  assert.match(productBatchId(IDENTITY), /^pb_[0-9a-f]{40}$/);
});

test("a retry is recognised by the rows, and cost is part of them", () => {
  // The gap this closes was found in the single-product callable and is the same
  // one here: two payloads under one request ID differing only in cost hashing
  // the same would answer the second off the first, silently not applying it.
  const hash = (rows: readonly unknown[]) =>
    fingerprintPayload(productBatchFingerprintInput(batch(rows)));
  const leftAlone = hash([{productId: "pd_0", name: "Cola"}]);

  assert.equal(hash([{productId: "pd_0", name: "Cola"}]), leftAlone);
  assert.notEqual(hash([{productId: "pd_0", name: "Cola", cost: 12}]), leftAlone);
  assert.notEqual(
    hash([{productId: "pd_0", name: "Cola", cost: 12}]),
    hash([{productId: "pd_0", name: "Cola", cost: 13}])
  );
  // Clearing a cost and leaving it alone are different requests.
  assert.notEqual(hash([{productId: "pd_0", name: "Cola", cost: null}]), leftAlone);
});

test("a retry that reorders its rows is a different request", () => {
  // Every outcome is indexed by where its row sat, so answering a reordered
  // retry off the stored record would hand back indexes naming different rows.
  // The corrections are unaffected either way - a row's audit entry is
  // identified by its product.
  const hash = (rows: readonly unknown[]) =>
    fingerprintPayload(productBatchFingerprintInput(batch(rows)));
  const first = {productId: "pd_0", name: "Cola"};
  const second = {productId: "pd_1", name: "Fanta"};

  assert.notEqual(hash([first, second]), hash([second, first]));
});

test("a request whose every row was refused plans nothing and reads nothing", () => {
  // The shape the writer has to guard: `getAll()` with no references is an
  // error, not an empty answer.
  const input = batch([{productId: "pd_0", price: 19.999}]);

  assert.equal(input.rows.length, 0);
  const result = plan(input);
  assert.equal(result.failedCount, 1);
  assert.deepEqual(result.writes, []);
});
