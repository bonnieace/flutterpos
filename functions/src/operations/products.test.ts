import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {fingerprintPayload} from "../core/idempotency";
import {FakeFirestore} from "../testing/fakeFirestore";
import {
  applyProductBatchUpdate,
  applyProductUpdate,
  productUpdateFingerprintInput,
} from "./products";
import {productBatchRowUpdateId, readProductBatchInput} from "./productBatch";
import {ProductUpdateInput, readProductUpdateInput} from "./productUpdate";

/**
 * What `updateProduct` does to a business's data, against an in-memory Firestore.
 *
 * `productUpdate.test.ts` beside this file pins every decision about *what* may
 * be corrected. This suite pins the two writes that carry it out and the one
 * read that guards them, because those are the parts a plan cannot describe:
 * that the product document is updated rather than replaced, that the audit
 * entry is created in the same transaction, that a refused correction leaves
 * both untouched, and that a named category is checked against this business
 * before anything is written.
 *
 * The double refuses an `update` to a document that does not exist and a
 * `create` onto one that does, exactly as Firestore does, so the replay and
 * missing-product cases are real refusals rather than assumptions.
 */

const TENANT = "tenant-a";
const PRODUCT = "pd_cola";
const CATEGORY = "ct_drinks";
const ACTOR = "uid-manager";
const REQUEST = "request-00000001";
const UPDATE = "pu_0123456789abcdef";

function productPath(productId = PRODUCT): string {
  return `tenants/${TENANT}/products/${productId}`;
}

function auditPath(updateId = UPDATE): string {
  return `tenants/${TENANT}/audit_logs/${updateId}`;
}

/** A business holding one sellable product filed under one category. */
function seededFirestore(product: DocumentData = {}): FakeFirestore {
  const db = new FakeFirestore();
  db.seed(`tenants/${TENANT}/categories/${CATEGORY}`, {name: "Drinks"});
  db.seed(productPath(), {
    name: "Cola 500ml",
    SKU: "CL500",
    price: 19.99,
    quantity: 12,
    categoryId: CATEGORY,
    createdBy: "uid-owner",
    ...product,
  });
  db.clearWrites();
  return db;
}

function requested(data: Record<string, unknown>): ProductUpdateInput {
  return readProductUpdateInput({
    tenantId: TENANT,
    productId: PRODUCT,
    requestId: REQUEST,
    ...data,
  });
}

function apply(
  db: FakeFirestore,
  data: Record<string, unknown>,
  options: {productId?: string; updateId?: string} = {}
) {
  return db.runTransaction((transaction) => applyProductUpdate(
    db.asFirestore(),
    transaction as unknown as Transaction,
    {
      tenantId: TENANT,
      productId: options.productId ?? PRODUCT,
      updateId: options.updateId ?? UPDATE,
      requestId: REQUEST,
      actorUid: ACTOR,
      requested: requested(data),
    }
  ));
}

/** The code a refused correction reports. */
async function refusalCode(attempt: () => Promise<unknown>): Promise<string> {
  try {
    await attempt();
  } catch (error) {
    assert.ok(error instanceof HttpsError, `${error}`);
    return error.code;
  }
  return assert.fail("The correction was not refused.");
}

test("a corrected price is written and recorded in one transaction", async () => {
  const db = seededFirestore();

  const response = await apply(db, {price: 24.5});

  assert.deepEqual(response.changedFields, ["price"]);
  assert.equal(response.price, 24.5);
  assert.equal(response.priceMinor, 2450);
  assert.equal(response.tenantId, TENANT);
  assert.equal(response.productId, PRODUCT);

  const product = db.read(productPath());
  assert.equal(product?.price, 24.5);
  assert.deepEqual(db.writtenPaths(), [auditPath(), productPath()].sort());

  const audit = db.read(auditPath());
  assert.equal(audit?.eventType, "product_updated");
  assert.equal(audit?.actorUid, ACTOR);
  assert.equal(audit?.requestId, REQUEST);
  // The before and after, which is the whole reason this is a callable.
  assert.deepEqual(audit?.changes, [
    {field: "price", previous: 19.99, next: 24.5},
  ]);
  // The property that makes this path safe to expose at all.
  assert.equal(audit?.mutatesQuantity, false);
});

test("the product document is patched, never replaced", async () => {
  const db = seededFirestore();

  await apply(db, {name: "Cola 500 ml"});

  const product = db.read(productPath());
  // A whole-document write would have dropped everything the correction did not
  // name, and one product the till cannot parse makes the whole cached catalog
  // a miss.
  assert.equal(product?.SKU, "CL500");
  assert.equal(product?.price, 19.99);
  assert.equal(product?.quantity, 12);
  assert.equal(product?.categoryId, CATEGORY);
  assert.equal(product?.createdBy, "uid-owner");
  assert.equal(product?.name, "Cola 500 ml");
  assert.ok(product?.updatedAt instanceof Timestamp);
});

test("the stock a product holds is untouched by every shape of correction", async () => {
  const db = seededFirestore();

  await apply(db, {name: "Cola 500 ml", sku: "CL-500", price: 21, categoryId: CATEGORY});

  assert.equal(db.read(productPath())?.quantity, 12);
  assert.equal(db.writes.filter((write) => write.kind === "update").length, 1);
});

test("a refused correction writes nothing at all", async () => {
  const db = seededFirestore();

  // The product already holds this name, so the plan refuses before any write.
  assert.equal(
    await refusalCode(() => apply(db, {name: "Cola 500ml"})),
    "failed-precondition"
  );
  assert.deepEqual(db.writtenPaths(), []);
  assert.equal(db.read(auditPath()), undefined);
});

test("a product in another business is not found, and nothing is written", async () => {
  const db = seededFirestore();

  assert.equal(
    await refusalCode(() => apply(db, {name: "Cola"}, {productId: "pd_absent"})),
    "not-found"
  );
  assert.deepEqual(db.writtenPaths(), []);
});

test("a category that does not exist in this business is refused", async () => {
  const db = seededFirestore();

  // Nothing on the server enforced this before. A product filed under a category
  // that does not exist is invisible to every grouped catalog surface without
  // being unreadable, which is the hardest kind of wrong to notice.
  assert.equal(
    await refusalCode(() => apply(db, {categoryId: "ct_missing"})),
    "failed-precondition"
  );
  assert.deepEqual(db.writtenPaths(), []);
  assert.equal(db.read(productPath())?.categoryId, CATEGORY);
});

test("a category is checked whenever it is named, not only when it moves", async () => {
  // A business whose category document has been deleted out from under its
  // products. Correcting a name while repeating the category the product already
  // holds is refused, rather than succeeding on the half that changed and
  // leaving the request half-applied.
  const orphaned = new FakeFirestore();
  orphaned.seed(productPath(), {
    name: "Cola 500ml",
    SKU: "CL500",
    price: 19.99,
    quantity: 12,
    categoryId: CATEGORY,
  });
  orphaned.clearWrites();

  assert.equal(
    await refusalCode(() => apply(orphaned, {name: "Cola 500 ml", categoryId: CATEGORY})),
    "failed-precondition"
  );
  assert.deepEqual(orphaned.writtenPaths(), []);
});

test("a legacy alias is written beside the field it aliases", async () => {
  const db = seededFirestore({category: CATEGORY});
  db.seed(`tenants/${TENANT}/categories/ct_snacks`, {name: "Snacks"});
  db.clearWrites();

  await apply(db, {categoryId: "ct_snacks"});

  const product = db.read(productPath());
  assert.equal(product?.categoryId, "ct_snacks");
  // Leaving the alias behind would make the two disagree, and the client's read
  // model refuses a product whose `category` and `categoryId` name different
  // categories.
  assert.equal(product?.category, "ct_snacks");
});

test("a second correction under one update ID is refused by the audit entry", async () => {
  const db = seededFirestore();
  await apply(db, {price: 24.5});
  db.clearWrites();

  // The idempotency wrapper answers a genuine retry off its own record and never
  // reaches this code. Reaching it means two different corrections were given
  // one identity, and the audit trail refuses to let the second overwrite the
  // first - which is what makes reusing a deterministic ID safe.
  await assert.rejects(
    apply(db, {price: 30}),
    /ALREADY_EXISTS/
  );
  assert.equal(db.read(productPath())?.price, 24.5);
  assert.deepEqual(db.writtenPaths(), []);
});

test("a corrected cost comes back beside the fields that can be reconciled", async () => {
  const db = seededFirestore({cost: 9});

  const response = await apply(db, {cost: 12.5});

  // Until 2026-08-08 a cost that moved appeared in `changedFields` with no value
  // beside it, so four of the five fields could be checked against the request
  // and the fifth could not.
  assert.deepEqual(response.changedFields, ["cost"]);
  assert.equal(response.cost, 12.5);
  assert.equal(response.costMinor, 1250);

  const cleared = await apply(
    seededFirestore({cost: 9}),
    {cost: null},
    {updateId: "pu_cleared"}
  );
  assert.equal(cleared.cost, null);
  assert.equal(cleared.costMinor, null);
});

test("two corrections differing only in cost are not one another's retry", () => {
  // The gap this closes: `products.ts` hashed productId, name, sku, priceMinor
  // and categoryId, so two payloads under one request ID differing only in cost
  // hashed the same. The second was then answered off the stored record with the
  // new cost silently not applied, where any other field would have been refused
  // as `already-exists` - a silent wrong answer rather than a refusal.
  const hash = (data: Record<string, unknown>) =>
    fingerprintPayload(productUpdateFingerprintInput(PRODUCT, requested(data)));

  assert.notEqual(hash({cost: 12}), hash({cost: 13}));
  assert.notEqual(hash({name: "Cola", cost: 12}), hash({name: "Cola"}));
  // Clearing a cost and leaving it alone mean different things, so they must
  // hash differently too.
  assert.notEqual(hash({name: "Cola", cost: null}), hash({name: "Cola"}));
  assert.equal(hash({name: "Cola", cost: 12}), hash({name: "Cola", cost: 12}));
});

/**
 * What `updateProducts` does to a business's data.
 *
 * `productBatch.test.ts` pins every decision about which rows a bulk change
 * applies and what it reports. What is left, and what these cover, is the part a
 * plan cannot describe: that a commit writes two documents per corrected row and
 * nothing for the rest, that a preview writes none at all, and that the whole
 * pass reads before it writes - which is not a style preference but the only
 * shape Firestore permits, and the double enforces it exactly as Firestore does.
 */

const BATCH_IDENTITY = "c".repeat(64);
const SECOND_PRODUCT = "pd_fanta";

/** A business holding two sellable products filed under one category. */
function seededCatalog(): FakeFirestore {
  const db = seededFirestore();
  db.seed(productPath(SECOND_PRODUCT), {
    name: "Fanta 500ml",
    SKU: "FN500",
    price: 19.99,
    quantity: 7,
    categoryId: CATEGORY,
    createdBy: "uid-owner",
  });
  db.clearWrites();
  return db;
}

function batchInput(rows: readonly unknown[], mode = "commit") {
  return readProductBatchInput({
    tenantId: TENANT,
    requestId: REQUEST,
    mode,
    rows,
  });
}

function applyBatch(
  db: FakeFirestore,
  rows: readonly unknown[],
  options: {identityDocumentId?: string} = {}
) {
  return db.runTransaction((transaction) => applyProductBatchUpdate(
    db.asFirestore(),
    {
      tenantId: TENANT,
      identityDocumentId: options.identityDocumentId ?? BATCH_IDENTITY,
      requestId: REQUEST,
      actorUid: ACTOR,
      input: batchInput(rows),
      transaction: transaction as unknown as Transaction,
    }
  ));
}

function previewBatch(db: FakeFirestore, rows: readonly unknown[]) {
  return applyProductBatchUpdate(db.asFirestore(), {
    tenantId: TENANT,
    identityDocumentId: BATCH_IDENTITY,
    requestId: REQUEST,
    actorUid: ACTOR,
    input: batchInput(rows, "preview"),
  });
}

test("a committed bulk change writes two documents per corrected row", async () => {
  const db = seededCatalog();

  const response = await applyBatch(db, [
    {productId: PRODUCT, price: 24.5},
    {productId: SECOND_PRODUCT, name: "Fanta 500 ml"},
  ]);

  assert.equal(response.mode, "commit");
  assert.equal(response.updatedCount, 2);
  assert.equal(db.read(productPath())?.price, 24.5);
  assert.equal(db.read(productPath(SECOND_PRODUCT))?.name, "Fanta 500 ml");

  const first = productBatchRowUpdateId(BATCH_IDENTITY, PRODUCT);
  const second = productBatchRowUpdateId(BATCH_IDENTITY, SECOND_PRODUCT);
  assert.deepEqual(db.writtenPaths(), [
    auditPath(first),
    auditPath(second),
    productPath(),
    productPath(SECOND_PRODUCT),
  ].sort());

  const audit = db.read(auditPath(first));
  assert.equal(audit?.eventType, "product_updated");
  assert.equal(audit?.rowIndex, 0);
  // What makes one bulk change answerable as one thing, without inventing a new
  // kind of record for it.
  assert.equal(audit?.batchId, response.batchId);
  assert.equal(audit?.requestId, REQUEST);
  assert.deepEqual(audit?.changes, [
    {field: "price", previous: 19.99, next: 24.5},
  ]);
  assert.equal(audit?.mutatesQuantity, false);
});

test("a bulk change patches its products and never their stock", async () => {
  const db = seededCatalog();

  await applyBatch(db, [
    {productId: PRODUCT, name: "Cola 500 ml", sku: "CL-500", categoryId: CATEGORY},
    {productId: SECOND_PRODUCT, price: 22},
  ]);

  const product = db.read(productPath());
  assert.equal(product?.quantity, 12);
  assert.equal(product?.price, 19.99);
  assert.equal(product?.createdBy, "uid-owner");
  assert.ok(product?.updatedAt instanceof Timestamp);
  assert.equal(db.read(productPath(SECOND_PRODUCT))?.quantity, 7);
  assert.equal(db.writes.filter((write) => write.kind === "update").length, 2);
});

test("an unchanged row and a failed row leave both their documents alone", async () => {
  const db = seededCatalog();

  const response = await applyBatch(db, [
    // Already holds this name.
    {productId: PRODUCT, name: "Cola 500ml"},
    {productId: "pd_absent", name: "Ghost"},
    {productId: SECOND_PRODUCT, name: "Fanta 500 ml"},
  ]);

  assert.deepEqual(
    response.rows.map((row) => row.status),
    ["unchanged", "failed", "updated"]
  );
  // Partial success, stated: one row wrote, and the writes prove the other two
  // did not - including no audit entry claiming a correction that never
  // happened.
  assert.deepEqual(db.writtenPaths(), [
    auditPath(productBatchRowUpdateId(BATCH_IDENTITY, SECOND_PRODUCT)),
    productPath(SECOND_PRODUCT),
  ].sort());
  assert.equal(db.read(productPath())?.name, "Cola 500ml");
});

test("a preview reads the catalog and writes nothing whatsoever", async () => {
  const db = seededCatalog();

  const response = await previewBatch(db, [
    {productId: PRODUCT, price: 24.5},
    {productId: SECOND_PRODUCT, name: "Fanta 500 ml"},
  ]);

  assert.equal(response.mode, "preview");
  assert.equal(response.updatedCount, 2);
  assert.equal(response.rows[0].product?.price, 24.5);
  // Not the corrections, not the audit entries, and - decided at the callable
  // rather than here - not an idempotency record either, which is what lets the
  // commit that follows carry the same request ID.
  assert.deepEqual(db.writtenPaths(), []);
  assert.equal(db.read(productPath())?.price, 19.99);
  assert.equal(response.rows[0].updateId, null);
});

test("a request whose every row was refused reads nothing at all", async () => {
  const db = seededCatalog();

  // `getAll()` with no document references is an error rather than an empty
  // answer, so the writer has to notice that there is nothing to read.
  const response = await applyBatch(db, [{productId: PRODUCT, price: 19.999}]);

  assert.equal(response.failedCount, 1);
  assert.deepEqual(db.writtenPaths(), []);
});

test("a replayed bulk change is refused by the audit entry it already wrote", async () => {
  const db = seededCatalog();
  await applyBatch(db, [{productId: PRODUCT, price: 24.5}]);
  db.clearWrites();

  // As in the single-product path, the idempotency wrapper answers a genuine
  // retry and never reaches this code. Reaching it means one identity was given
  // two different changes, and the audit trail refuses to let the second
  // overwrite the first.
  await assert.rejects(
    applyBatch(db, [{productId: PRODUCT, price: 30}]),
    /ALREADY_EXISTS/
  );
  assert.equal(db.read(productPath())?.price, 24.5);
  assert.deepEqual(db.writtenPaths(), []);
});

test("a bulk change under a second request records rather than collides", async () => {
  const db = seededCatalog();
  await applyBatch(db, [{productId: PRODUCT, price: 24.5}]);
  db.clearWrites();

  await applyBatch(
    db,
    [{productId: PRODUCT, price: 30}],
    {identityDocumentId: "d".repeat(64)}
  );

  assert.equal(db.read(productPath())?.price, 30);
  assert.equal(db.ids(`tenants/${TENANT}/audit_logs`).length, 2);
});
