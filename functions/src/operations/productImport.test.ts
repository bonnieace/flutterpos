import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {TenantRole} from "../core/model";
import {fingerprintPayload} from "../core/idempotency";
import {
  MAXIMUM_IMPORT_OPENING_STOCK,
  MAXIMUM_PRODUCT_IMPORT_ROWS,
  ProductImportCategories,
  ProductImportInput,
  ProductImportRowOutcome,
  assertProductImportAuthorized,
  foldCategoryName,
  planProductImport,
  productImportFingerprintInput,
  productImportId,
  productImportRowIds,
  readProductImportInput,
} from "./productImport";

/**
 * The decisions behind `importProducts`, as units.
 *
 * What a product may hold is already pinned by `productUpdate.test.ts` and is
 * deliberately not repeated here: an imported row's name, code, price, and cost
 * are read by the same function a correction's are, so a suite that re-asserted
 * the price arithmetic would be pinning a copy rather than the original. What is
 * new, and what this file is for, is everything creating a product raises that
 * correcting one does not:
 *
 * - resolving a category named "Bakery" rather than `ct_7f3a`,
 * - deriving a permanent document ID for a product that does not exist yet,
 * - accepting an opening quantity at all, which every other product payload in
 *   this codebase refuses outright,
 * - and which defects belong to a row rather than to the request - a shorter
 *   list than the bulk correction's, because two import rows describing one
 *   product are not a conflict.
 *
 * The identity strings are the sha256 hex the idempotency wrapper produces. They
 * are opaque here on purpose: what matters is which inputs change them.
 */

const CATEGORY = "ct_drinks";
const IDENTITY = "a".repeat(64);
const OTHER_IDENTITY = "b".repeat(64);

/** One row that describes a product this business can sell. */
function row(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    name: "Cola 500ml",
    sku: "CL500",
    price: 19.99,
    categoryId: CATEGORY,
    ...overrides,
  };
}

function importRequest(
  rows: readonly unknown[],
  overrides: Record<string, unknown> = {}
): ProductImportInput {
  return readProductImportInput({
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
  return assert.fail("The import was not refused.");
}

/** A business holding the named categories, keyed by ID and by folded name. */
function categories(
  named: Record<string, string> = {[CATEGORY]: "Drinks"}
): ProductImportCategories {
  const byFoldedName = new Map<string, string[]>();
  for (const [id, name] of Object.entries(named)) {
    const folded = foldCategoryName(name);
    byFoldedName.set(folded, [...(byFoldedName.get(folded) ?? []), id]);
  }
  return {ids: new Set(Object.keys(named)), byFoldedName};
}

function plan(
  input: ProductImportInput,
  options: {
    categories?: ProductImportCategories;
    identityDocumentId?: string;
  } = {}
) {
  return planProductImport({
    input,
    identityDocumentId: options.identityDocumentId ?? IDENTITY,
    categories: options.categories ?? categories(),
  });
}

function outcome(
  outcomes: readonly ProductImportRowOutcome[],
  index: number
): ProductImportRowOutcome {
  const found = outcomes.find((entry) => entry.index === index);
  assert.ok(found, `no outcome for row ${index}`);
  return found;
}

test("a request that omits the mode is refused rather than assumed", () => {
  // The same refusal the bulk correction keeps, through the same reader: a
  // commit mistaken for a preview creates four hundred products nobody agreed
  // to, and unlike a correction there is no undo for that.
  assert.equal(
    refusal(() => importRequest([row()], {mode: undefined})).code,
    "invalid-argument"
  );
  assert.equal(
    refusal(() => importRequest([row()], {mode: "dry-run"})).code,
    "invalid-argument"
  );
  assert.equal(importRequest([row()], {mode: "preview"}).mode, "preview");
});

test("an unknown key on the request, and on a row, is refused rather than dropped", () => {
  assert.equal(
    refusal(() => importRequest([row()], {createdBy: "uid-owner"})).code,
    "invalid-argument"
  );
  // A row key is that row's problem, because the rest of the spreadsheet is
  // still importable.
  const input = importRequest([row({image: "https://example.test/cola.png"})]);
  assert.equal(input.rows.length, 0);
  assert.equal(input.refusals[0].code, "invalid-argument");
  assert.match(input.refusals[0].message, /image is not part of an imported product/);
});

test("rows must be a non-empty array", () => {
  assert.equal(refusal(() => importRequest("cola" as unknown as never[])).code, "invalid-argument");
  assert.equal(refusal(() => importRequest([])).code, "invalid-argument");
});

test("more rows than the bound is refused for the whole request", () => {
  const rows = Array.from(
    {length: MAXIMUM_PRODUCT_IMPORT_ROWS + 1},
    (_, index) => row({sku: `CL${index}`})
  );

  const error = refusal(() => importRequest(rows));

  assert.equal(error.code, "invalid-argument");
  assert.match(error.message, /further request with its own requestId/);
  assert.equal(
    importRequest(rows.slice(0, MAXIMUM_PRODUCT_IMPORT_ROWS)).rows.length,
    50
  );
});

test("a row must name a name and a price, and may leave out the size", () => {
  const input = importRequest([
    row({name: undefined}),
    row({sku: null}),
    row({price: undefined}),
    row(),
  ]);

  assert.deepEqual(input.rows.map((entry) => entry.index), [1, 3]);
  assert.deepEqual(
    input.refusals.map((entry) => entry.index),
    [0, 2]
  );
  assert.equal(plan(input).outcomes[1].product?.sku, "");
  assert.match(input.refusals[0].message, /name is required to create a product/);
});

test("a product named twice is not a refusal, unlike a bulk correction", () => {
  // Two rows addressing one *document* are two conflicting intents, which is why
  // `updateProducts` refuses them. Two rows describing one product are not that:
  // each creates its own document, and a shop legitimately stocking two products
  // with one name and one code is a state this app already permits. SKU
  // uniqueness is stated rather than enforced everywhere else, and a check
  // against fifty rows would not see the four hundred already in the catalog.
  const input = importRequest([row(), row()]);

  assert.equal(input.rows.length, 2);
  const result = plan(input);
  assert.equal(result.createdCount, 2);
  assert.notEqual(
    outcome(result.outcomes, 0).productId,
    outcome(result.outcomes, 1).productId
  );
});

test("an opening quantity is accepted here, and only here", () => {
  // `updateProduct` refuses a payload that so much as mentions a quantity, with
  // a message naming `adjustStock`. This path accepts one because it writes the
  // ledger entry that refusal exists to protect - which is asserted where the
  // writes are, in `products.test.ts`.
  assert.equal(importRequest([row({quantity: 24})]).rows[0].quantity, 24);
  // A product is created holding nothing unless the row says otherwise, exactly
  // as the catalog's own create form behaves.
  assert.equal(importRequest([row()]).rows[0].quantity, 0);
  assert.equal(importRequest([row({quantity: null})]).rows[0].quantity, 0);

  const input = importRequest([
    row({quantity: -1}),
    row({quantity: 4.5}),
    row({quantity: MAXIMUM_IMPORT_OPENING_STOCK + 1}),
    row({quantity: "24"}),
  ]);
  assert.equal(input.rows.length, 0);
  assert.equal(input.refusals.length, 4);
  assert.match(input.refusals[0].message, /whole number of units/);
});

test("a row must name a category, by ID or by name and never both", () => {
  const input = importRequest([
    row({categoryId: undefined}),
    row({categoryId: undefined, categoryName: "Drinks"}),
    row(),
  ]);

  assert.equal(input.refusals.length, 1);
  assert.match(input.refusals[0].message, /named by categoryId or by categoryName/);
  assert.equal(input.rows[0].categoryName, "Drinks");
  assert.equal(input.rows[0].categoryId, undefined);
  assert.equal(input.rows[1].categoryId, CATEGORY);

  // Two ways of saying one thing, with no honest answer when they disagree.
  const both = importRequest([row({categoryName: "Drinks"})]);
  assert.equal(both.rows.length, 0);
  assert.match(both.refusals[0].message, /not both/);
});

test("a category is resolved by name, case and spacing folded", () => {
  const result = plan(
    importRequest([
      row({categoryId: undefined, categoryName: "  drinks  "}),
      row({categoryId: undefined, categoryName: "SOFT   DRINKS", sku: "SD1"}),
    ]),
    {categories: categories({[CATEGORY]: "Drinks", ct_soft: "Soft Drinks"})}
  );

  assert.equal(outcome(result.outcomes, 0).product?.categoryId, CATEGORY);
  assert.equal(outcome(result.outcomes, 1).product?.categoryId, "ct_soft");
});

test("an unmatched category name fails the row and says to add it first", () => {
  // It does not create the category. A category is permanent - the rules permit
  // rename and delete, this app offers neither - so "Bakry" typed once would
  // become a grouping nobody can repair, holding products every report separates
  // from the ones filed under "Bakery".
  const result = plan(importRequest([
    row({categoryId: undefined, categoryName: "Bakry"}),
    row({sku: "CL501"}),
  ]));

  assert.equal(outcome(result.outcomes, 0).status, "failed");
  assert.equal(outcome(result.outcomes, 0).code, "failed-precondition");
  assert.match(outcome(result.outcomes, 0).message ?? "", /Add it to the catalog first/);
  assert.equal(outcome(result.outcomes, 1).status, "created");
  assert.equal(result.createdCount, 1);
  assert.equal(result.failedCount, 1);
  assert.deepEqual(result.writes.map((write) => write.rowIndex), [1]);
});

test("a category name two categories share fails the row rather than guessing", () => {
  // Nothing in this app makes a category name unique: `allow create` on
  // `categories` checks nothing at all, and there is no rename and no delete. So
  // two "Bakery" categories are reachable, and a row naming that name has no
  // honest answer.
  const result = plan(
    importRequest([row({categoryId: undefined, categoryName: "Bakery"})]),
    {categories: categories({ct_one: "Bakery", ct_two: "bakery"})}
  );

  assert.equal(outcome(result.outcomes, 0).code, "failed-precondition");
  assert.match(outcome(result.outcomes, 0).message ?? "", /2 categories/);
  assert.match(outcome(result.outcomes, 0).message ?? "", /Name the category by categoryId/);
});

test("a category ID this business does not hold fails the row", () => {
  const result = plan(importRequest([row({categoryId: "ct_missing"})]));

  assert.equal(outcome(result.outcomes, 0).code, "failed-precondition");
  assert.match(outcome(result.outcomes, 0).message ?? "", /category does not exist/);
});

test("the product a row would create is read back before it is written", () => {
  // One product the till cannot parse makes the *whole* cached catalog a miss,
  // and an import is the one operation that can add hundreds at once. The
  // resulting document therefore goes through `readSellableProduct` - the
  // server-side twin of `TenantProduct.fromDocument` - and a category ID
  // carrying a control character is refused there rather than written.
  // Built with fromCharCode rather than typed: a control character typed into a
  // source file has reached this repository as a literal NUL byte before.
  const broken = `ct_${String.fromCharCode(1)}bad`;
  const result = plan(
    importRequest([row({categoryId: broken})]),
    {categories: categories({[broken]: "Broken"})}
  );

  assert.equal(outcome(result.outcomes, 0).status, "failed");
  assert.equal(outcome(result.outcomes, 0).code, "failed-precondition");
});

test("a created row carries exactly the keys the catalog's own create writes", () => {
  // `TenantProductCreateIntent.documentData()`, key for key. A product written in
  // any other shape is one the strict read model may refuse, and the rule on
  // `products` checks only that `quantity is int`.
  const result = plan(importRequest([
    row({quantity: 24, cost: 12.5}),
    row({sku: "CL501"}),
  ]));

  assert.deepEqual(Object.keys(result.writes[0].documentData).sort(), [
    "SKU", "categoryId", "cost", "name", "price", "quantity",
    "searchName", "searchPrefixes",
  ]);
  assert.deepEqual(result.writes[0].documentData, {
    name: "Cola 500ml",
    SKU: "CL500",
    price: 19.99,
    cost: 12.5,
    quantity: 24,
    categoryId: CATEGORY,
    searchName: "cola 500ml",
    searchPrefixes: [
      "50", "500", "500m", "500ml", "cl", "cl5", "cl50", "cl500",
      "co", "col", "cola",
    ],
  });
  // Omitted rather than written as null when no cost was recorded, so "never
  // recorded" and "recorded as nothing" stay distinguishable in the document.
  assert.equal("cost" in result.writes[1].documentData, false);
  assert.equal(result.writes[1].documentData.quantity, 0);
});

test("a row with no opening stock names no stock adjustment", () => {
  const result = plan(importRequest([row(), row({sku: "CL501", quantity: 24})]));

  assert.equal(outcome(result.outcomes, 0).adjustmentId, null);
  assert.equal(result.writes[0].adjustmentId, null);
  assert.ok(outcome(result.outcomes, 1).adjustmentId?.startsWith("sa_"));
  assert.equal(outcome(result.outcomes, 1).product?.quantity, 24);
});

test("an absent cost and an explicit null both mean not recorded", () => {
  // The opposite of `updateProduct`, where null clears a recorded cost and
  // absence leaves it alone. There is nothing to clear on a product that does
  // not exist yet, so a blank spreadsheet cell means the business did not say.
  const result = plan(importRequest([row({cost: null}), row({sku: "CL501"})]));

  for (const index of [0, 1]) {
    assert.equal(outcome(result.outcomes, index).product?.cost, null);
    assert.equal(outcome(result.outcomes, index).product?.costMinor, null);
  }
  const hash = (rows: readonly unknown[]) =>
    fingerprintPayload(productImportFingerprintInput(importRequest(rows)));
  assert.equal(hash([row({cost: null})]), hash([row()]));
});

test("a manager may import priced products, and may not import costs", () => {
  // A price is *not* gated here, and that is a decision. `updateProduct` puts a
  // price behind owner or administrator because changing one silently alters
  // what every later sale records; setting the first price is creation, which
  // the catalog's own add-product form already offers a manager. An import that
  // refused what the form beside it accepts would be a rule nobody could
  // explain.
  const priced = importRequest([row(), row({sku: "CL501", price: 21})]);
  assert.doesNotThrow(() => assertProductImportAuthorized("manager", priced.rows));

  const costed = importRequest([
    row(),
    row({sku: "CL501", cost: 12}),
    row({sku: "CL502", cost: 9.5}),
  ]);
  const error = refusal(() => assertProductImportAuthorized("manager", costed.rows));
  assert.equal(error.code, "permission-denied");
  assert.match(error.message, /what a product costs/);
  assert.match(error.message, /rows\[1\], rows\[2\]/);
  for (const role of ["owner", "admin"] as TenantRole[]) {
    assert.doesNotThrow(() => assertProductImportAuthorized(role, costed.rows));
  }
  // A null cost records nothing, so it is not a monetary row.
  const cleared = importRequest([row({cost: null})]);
  assert.doesNotThrow(() => assertProductImportAuthorized("manager", cleared.rows));
});

test("a row's documents are identified by where it sat, and by the request", () => {
  // The one deterministic ID in this codebase derived from a position. A bulk
  // correction derives a row's audit entry from the product it corrects, so a
  // reordered retry lands on the same documents; an import has no product to
  // derive from, which is what makes order part of the fingerprint below.
  assert.deepEqual(productImportRowIds(IDENTITY, 0), productImportRowIds(IDENTITY, 0));
  assert.notEqual(
    productImportRowIds(IDENTITY, 0).productId,
    productImportRowIds(IDENTITY, 1).productId
  );
  assert.notEqual(
    productImportRowIds(IDENTITY, 0).productId,
    productImportRowIds(OTHER_IDENTITY, 0).productId
  );
  const ids = productImportRowIds(IDENTITY, 0);
  assert.match(ids.productId, /^pd_[0-9a-f]{40}$/);
  assert.match(ids.adjustmentId, /^sa_[0-9a-f]{40}$/);
  assert.match(ids.auditId, /^pi_[0-9a-f]{40}$/);
  assert.match(productImportId(IDENTITY), /^im_[0-9a-f]{40}$/);
});

test("a retry is recognised by the rows, their order, and their opening stock", () => {
  const hash = (rows: readonly unknown[]) =>
    fingerprintPayload(productImportFingerprintInput(importRequest(rows)));
  const first = row();
  const second = row({sku: "FN500", name: "Fanta 500ml"});

  assert.equal(hash([first, second]), hash([first, second]));
  // Order matters more here than anywhere else: a product's ID is derived from
  // where its row sat, so a reordered retry answered off the stored record would
  // report IDs belonging to different products, and one *not* answered off it
  // would create the whole catalog a second time.
  assert.notEqual(hash([first, second]), hash([second, first]));
  assert.notEqual(hash([row({quantity: 24})]), hash([row()]));
  assert.notEqual(hash([row({cost: 12})]), hash([row()]));
  // Naming a category by ID and by the name that resolves to it are different
  // requests, because only one of them depends on what the business holds.
  assert.notEqual(
    hash([row({categoryId: undefined, categoryName: "Drinks"})]),
    hash([row()])
  );
});

test("a preview plans the same rows and names none of the documents", () => {
  const rows = [row({quantity: 24}), row({sku: "CL501"})];

  const preview = plan(importRequest(rows, {mode: "preview"}));
  const commit = plan(importRequest(rows));

  assert.deepEqual(
    preview.outcomes.map((entry) => [entry.index, entry.status, entry.product]),
    commit.outcomes.map((entry) => [entry.index, entry.status, entry.product])
  );
  // What the products *would* be is the whole point of a preview.
  assert.equal(outcome(preview.outcomes, 0).product?.priceMinor, 1999);
  assert.equal(outcome(preview.outcomes, 0).product?.quantity, 24);
  assert.deepEqual(preview.writes, []);
  // A preview names no document, so its outcome can never be mistaken for a
  // record of something that exists - even though both IDs are derivable.
  assert.equal(outcome(preview.outcomes, 0).productId, null);
  assert.equal(outcome(preview.outcomes, 0).adjustmentId, null);
  assert.ok(outcome(commit.outcomes, 0).productId?.startsWith("pd_"));
});

test("outcomes come back in request order, refusals among them", () => {
  const result = plan(importRequest([
    row({price: 19.999}),
    row({sku: "500ml"}),
    row({categoryId: "ct_missing", sku: "1 L"}),
    row({sku: "1.5 L"}),
  ]));

  assert.deepEqual(result.outcomes.map((entry) => entry.index), [0, 1, 2, 3]);
  assert.deepEqual(
    result.outcomes.map((entry) => entry.status),
    ["failed", "created", "failed", "created"]
  );
  assert.equal(result.createdCount, 2);
  assert.equal(result.failedCount, 2);
});

test("a request whose every row was refused plans nothing", () => {
  const input = importRequest([row({price: 19.999})]);

  assert.equal(input.rows.length, 0);
  assert.equal(input.rowCount, 1);
  const result = plan(input);
  assert.equal(result.failedCount, 1);
  assert.deepEqual(result.writes, []);
});
