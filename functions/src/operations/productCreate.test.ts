import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {TenantRole} from "../core/model";
import type {
  DocumentReference,
  Transaction,
} from "firebase-admin/firestore";
import {
  CREATE_OPENING_STOCK_REASON,
  assertProductCreateCategoryExists,
  ProductCreateInput,
  assertProductCreateAuthorized,
  planProductCreate,
  productCreateAdjustmentId,
  productCreateAuditId,
  productCreateFingerprintInput,
  readProductCreateInput,
} from "./productCreate";
import {MAXIMUM_IMPORT_OPENING_STOCK} from "./productImport";
import {productSearchFields} from "./productUpdate";

/**
 * The decisions behind `createProduct`, as units.
 *
 * What a product may hold is pinned by `productUpdate.test.ts` and is
 * deliberately not repeated: a created product's name, code, price, cost and
 * image are read by the same `readSellableProduct` a correction's are. What is
 * new here is everything that follows from a single-product create being allowed
 * to name a quantity, which every other single-product payload in this codebase
 * refuses outright:
 *
 * - the opening ledger entry, and its absence when a product opens empty,
 * - that the ledger record is the one `adjustStock` writes rather than a second
 *   dialect of it,
 * - that the fields only a server may decide are taken from the actor and not
 *   from the document a device composed,
 * - and that a cost is owner/administrator work while a first price is not.
 */

const TENANT = "tenant-a";
const PRODUCT = `pd_${"a".repeat(40)}`;
const ACTOR = "user-owner";
const CATEGORY = "ct_drinks";

/** The document a device composes for an ordinary product. */
function document(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    name: "Cola 500ml",
    SKU: "CL500",
    price: 19.99,
    categoryId: CATEGORY,
    quantity: 0,
    ...overrides,
  };
}

function planFor(
  overrides: Record<string, unknown> = {},
  options: {actorUid?: string} = {}
) {
  return planProductCreate({
    tenantId: TENANT,
    productId: PRODUCT,
    actorUid: options.actorUid ?? ACTOR,
    input: readProductCreateInput(document(overrides)),
  });
}

function refusal(body: () => unknown): HttpsError {
  try {
    body();
  } catch (error) {
    assert.ok(error instanceof HttpsError, `expected an HttpsError, got ${error}`);
    return error;
  }
  assert.fail("expected a refusal");
}

test("a product opening empty writes no ledger entry", () => {
  const plan = planFor({quantity: 0});

  assert.equal(plan.adjustmentId, null);
  assert.equal(plan.ledgerData, null);
  assert.equal(plan.quantity, 0);
  assert.equal(plan.documentData.quantity, 0);
  assert.equal(plan.auditData.mutatesQuantity, false);
  assert.equal(plan.auditData.adjustmentId, null);
});

test("a product opening with stock writes the ledger entry that accounts for it", () => {
  const plan = planFor({quantity: 24});

  assert.equal(plan.adjustmentId, productCreateAdjustmentId(PRODUCT));
  assert.equal(plan.documentData.quantity, 24);
  assert.equal(plan.auditData.mutatesQuantity, true);
  assert.equal(plan.auditData.openingQuantity, 24);
  assert.deepEqual(plan.ledgerData, {
    tenantId: TENANT,
    productId: PRODUCT,
    sourceType: "product_created",
    adjustmentType: "opening_balance",
    quantityDelta: 24,
    previousQuantity: 0,
    quantityAfter: 24,
    reason: CREATE_OPENING_STOCK_REASON,
    actorUid: ACTOR,
    requestId: PRODUCT,
  });
});

test("the ledger record carries exactly the fields adjustStock writes", () => {
  // A unit opened with and a unit adjusted in are the same unit, and
  // reconciliation reads one ledger. If `adjustStock` grows or drops a field this
  // must follow it, and a drifting second dialect is what this pins. The list is
  // `stock.ts`'s `immutableRecord`, less `createdAt`, which only a write adds.
  const plan = planFor({quantity: 5});

  assert.deepEqual(Object.keys(plan.ledgerData ?? {}).sort(), [
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

test("the ledger entry is derived from the product and from nothing else", () => {
  assert.equal(productCreateAdjustmentId(PRODUCT), `sa_${"a".repeat(40)}`);
  assert.equal(productCreateAuditId(PRODUCT), `pc_${"a".repeat(40)}`);
  // Stable across calls, which is what makes a replay land on one document
  // rather than stocking the shelf twice.
  assert.equal(
    productCreateAdjustmentId(PRODUCT),
    productCreateAdjustmentId(PRODUCT)
  );
  assert.notEqual(
    productCreateAdjustmentId(PRODUCT),
    productCreateAdjustmentId(`pd_${"b".repeat(40)}`)
  );
});

test("the fields only a server may decide are taken from the actor", () => {
  // The device composes this whole document and could name anybody. `createdBy`
  // and the search index are the server's to say, so a client-sent value for
  // either is overwritten rather than trusted - and rather than refused, because
  // a record queued before this callable existed carries both.
  const plan = planFor({
    createdBy: "somebody-else",
    searchName: "not what the name normalizes to",
    searchPrefixes: ["xx"],
  });

  assert.equal(plan.documentData.createdBy, ACTOR);
  assert.equal(plan.documentData.searchName, "cola 500ml");
  assert.ok(
    (plan.documentData.searchPrefixes as string[]).includes("co"),
    "the search index is re-derived from the normalized name"
  );
});

test("a document naming no size creates a product with none", () => {
  // The size is the one descriptive field a product may go without, since
  // 2026-10-08. It is stored as an empty string, so every product still has
  // the key.
  const plan = planFor({SKU: undefined});
  assert.equal(plan.documentData.SKU, "");
  assert.deepEqual(
    plan.documentData.searchPrefixes,
    productSearchFields("Cola 500ml", "").searchPrefixes
  );
});

test("a key that is not part of a product is refused", () => {
  const error = refusal(() => readProductCreateInput(document({soldById: "x"})));

  assert.equal(error.code, "invalid-argument");
  assert.match(error.message, /soldById is not part of a product/);
});

for (const field of ["name", "price", "categoryId"]) {
  test(`a document naming no ${field} is refused`, () => {
    const error = refusal(() =>
      readProductCreateInput(document({[field]: undefined}))
    );

    assert.equal(error.code, "invalid-argument");
    assert.match(error.message, new RegExp(`${field} is required`));
  });
}

test("an opening quantity beyond the import bound is refused", () => {
  // The same bound `importProducts` enforces, and deliberately the same constant:
  // a limit one create path applies and another does not would be a way in rather
  // than a rule.
  const error = refusal(() =>
    readProductCreateInput(document({quantity: MAXIMUM_IMPORT_OPENING_STOCK + 1}))
  );

  assert.equal(error.code, "invalid-argument");
});

for (const quantity of [-1, 1.5, "4"]) {
  test(`an opening quantity of ${JSON.stringify(quantity)} is refused`, () => {
    assert.equal(refusal(() => readProductCreateInput(document({quantity}))).code,
      "invalid-argument");
  });
}

test("an absent quantity opens the product empty rather than refusing", () => {
  // A record queued before this callable existed carries no quantity at all.
  const input = readProductCreateInput(document({quantity: undefined}));

  assert.equal(input.quantity, 0);
});

test("an unreadable image is refused rather than written", () => {
  // The only validation this field gets anywhere: the client's own read model
  // throws on a non-HTTPS image, and one unparseable product makes the whole
  // cached catalog a miss, which stops the business selling everything.
  const error = refusal(() => planFor({image: "http://example.com/a.png"}));

  assert.equal(error.code, "failed-precondition");
});

test("an https image is carried onto the document", () => {
  const plan = planFor({image: "https://example.com/a.png"});

  assert.equal(plan.documentData.image, "https://example.com/a.png");
});

test("a cost is omitted rather than written as null when none was recorded", () => {
  // "Never recorded" and "recorded as nothing" have to stay distinguishable in
  // the document: the daily summary counts the first as missing cost data and
  // would report the second as pure profit.
  for (const cost of [undefined, null]) {
    const plan = planFor({cost});

    assert.ok(!("cost" in plan.documentData), `cost: ${cost} wrote a cost`);
    assert.equal(plan.auditData.created && (plan.auditData.created as {
      cost: number | null;
    }).cost, null);
  }
});

test("only an owner or an administrator may record what a product cost", () => {
  const withCost = readProductCreateInput(document({cost: 12.5}));

  for (const role of ["owner", "admin"] as TenantRole[]) {
    assert.doesNotThrow(() => assertProductCreateAuthorized(role, withCost));
  }
  const error = refusal(() =>
    assertProductCreateAuthorized("manager" as TenantRole, withCost)
  );
  assert.equal(error.code, "permission-denied");
  assert.match(error.message, /what a product costs/);
});

test("a manager may set the price a product is created at", () => {
  // Setting a first price is creation, not a price change, and the add-product
  // form already accepts one from a manager. Gating it here would take the
  // ability to add a product away from the role the rules admit.
  const withoutCost = readProductCreateInput(document({price: 49.5}));

  assert.doesNotThrow(() =>
    assertProductCreateAuthorized("manager" as TenantRole, withoutCost)
  );
});

test("the fingerprint moves with the opening stock", () => {
  // A second attempt that names different stock is a different operation, and
  // must not be answered off the first one's idempotency record.
  const empty = productCreateFingerprintInput(planFor({quantity: 0}));
  const stocked = productCreateFingerprintInput(planFor({quantity: 24}));

  assert.notDeepEqual(empty, stocked);
});

test("the fingerprint ignores the fields the server decides", () => {
  // Including them would make the fingerprint depend on this server rather than
  // on the request, so the same create from two builds would look like two
  // operations.
  const plain = productCreateFingerprintInput(planFor());
  const spoofed = productCreateFingerprintInput(
    planFor({createdBy: "somebody-else", searchName: "xx"}, {actorUid: ACTOR})
  );

  assert.deepEqual(plain, spoofed);
});

test("an input that differs only in how the price was written hashes alike", () => {
  const typed = productCreateFingerprintInput(planFor({price: 19.99}));
  const other: ProductCreateInput = readProductCreateInput(
    document({price: 19.990})
  );
  const replanned = productCreateFingerprintInput(
    planProductCreate({
      tenantId: TENANT,
      productId: PRODUCT,
      actorUid: ACTOR,
      input: other,
    })
  );

  assert.deepEqual(typed, replanned);
});

/**
 * The category check, which this path could not make until the client stopped
 * racing it. See `assertProductCreateCategoryExists` for why.
 */
function transactionHolding(exists: boolean): Transaction {
  return {get: async () => ({exists})} as unknown as Transaction;
}

const categoryTenantRef = {
  collection: () => ({doc: () => ({})}),
} as unknown as DocumentReference;

test("a product filed under a category this business holds is allowed", async () => {
  await assertProductCreateCategoryExists(
    transactionHolding(true),
    categoryTenantRef,
    CATEGORY
  );
});

test("a product filed under a category that does not exist is refused", async () => {
  // The same refusal `updateProduct` makes, in the same words, for the same
  // reason: a product filed under a category that does not exist is invisible
  // to every grouped catalog surface without being unreadable.
  await assert.rejects(
    assertProductCreateCategoryExists(
      transactionHolding(false),
      categoryTenantRef,
      "ct_missing"
    ),
    (error: unknown) =>
      error instanceof HttpsError && error.code === "failed-precondition"
  );
});

test("a product is bought in unless the document says it is made here", () => {
  const plain = planFor();
  const made = planFor({costType: "produced"});

  // Written on every product, so "made here" is an equality read against a
  // stored value rather than an inference from a field's absence.
  assert.equal(plain.documentData.costType, "purchased");
  assert.equal(made.documentData.costType, "produced");
  assert.equal(
    (made.auditData.created as Record<string, unknown>).costType,
    "produced"
  );
});

test("a cost type the catalog does not model is refused at the door", () => {
  const error = refusal(() => readProductCreateInput(document({costType: "made"})));

  assert.equal(error.code, "invalid-argument");
  assert.match(error.message, /costType/);
});

test("the cost type is part of what a retry is recognised by", () => {
  // Two creates under one product ID that differ only in where the cost comes
  // from must not hash the same: the second would be answered off the first's
  // record and the product left bought in.
  assert.notDeepEqual(
    productCreateFingerprintInput(planFor({costType: "produced"})),
    productCreateFingerprintInput(planFor())
  );
});

test("a manager may create a product made here, because the flag is not money", () => {
  assert.doesNotThrow(() =>
    assertProductCreateAuthorized(
      "manager" as TenantRole,
      readProductCreateInput(document({costType: "produced"}))
    )
  );
});
