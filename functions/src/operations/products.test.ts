import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {fingerprintPayload} from "../core/idempotency";
import {FakeFirestore} from "../testing/fakeFirestore";
import {
  applyProductBatchUpdate,
  applyProductImport,
  applyProductUpdate,
  productUpdateFingerprintInput,
} from "./products";
import {productBatchRowUpdateId, readProductBatchInput} from "./productBatch";
import {
  MAXIMUM_IMPORT_CATEGORY_SCAN,
  productImportRowIds,
  readProductImportInput,
} from "./productImport";
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

/**
 * What `importProducts` does to a business's data.
 *
 * `productImport.test.ts` pins every decision about which rows an import creates
 * and what it reports. What is left, and what these cover, is the part a plan
 * cannot describe: that a created product is written in the shape every device
 * reads, that its opening stock arrives with the ledger entry that says where it
 * came from, that a preview writes none of it, and that resolving a category by
 * name reads this business's categories rather than trusting the row.
 */

const IMPORT_IDENTITY = "e".repeat(64);

/** A business holding two categories and no products at all. */
function seededCategories(): FakeFirestore {
  const db = new FakeFirestore();
  db.seed(`tenants/${TENANT}/categories/${CATEGORY}`, {name: "Drinks"});
  db.seed(`tenants/${TENANT}/categories/ct_snacks`, {name: "Snacks"});
  db.clearWrites();
  return db;
}

function importRow(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    name: "Cola 500ml",
    sku: "CL500",
    price: 19.99,
    categoryId: CATEGORY,
    ...overrides,
  };
}

function importInput(rows: readonly unknown[], mode = "commit") {
  return readProductImportInput({
    tenantId: TENANT,
    requestId: REQUEST,
    mode,
    rows,
  });
}

function applyImport(
  db: FakeFirestore,
  rows: readonly unknown[],
  options: {identityDocumentId?: string} = {}
) {
  return db.runTransaction((transaction) => applyProductImport(
    db.asFirestore(),
    {
      tenantId: TENANT,
      identityDocumentId: options.identityDocumentId ?? IMPORT_IDENTITY,
      requestId: REQUEST,
      actorUid: ACTOR,
      input: importInput(rows),
      transaction: transaction as unknown as Transaction,
    }
  ));
}

function previewImport(db: FakeFirestore, rows: readonly unknown[]) {
  return applyProductImport(db.asFirestore(), {
    tenantId: TENANT,
    identityDocumentId: IMPORT_IDENTITY,
    requestId: REQUEST,
    actorUid: ACTOR,
    input: importInput(rows, "preview"),
  });
}

test("an imported product with opening stock writes four documents", async () => {
  const db = seededCategories();

  const response = await applyImport(db, [importRow({quantity: 24, cost: 12.5})]);

  assert.equal(response.mode, "commit");
  assert.equal(response.createdCount, 1);
  const ids = productImportRowIds(IMPORT_IDENTITY, 0);
  assert.deepEqual(db.writtenPaths(), [
    productPath(ids.productId),
    auditPath(ids.auditId),
    `tenants/${TENANT}/stock_adjustments/${ids.adjustmentId}`,
    `${productPath(ids.productId)}/stock_movements/${ids.adjustmentId}`,
  ].sort());

  // The product, in exactly the shape `TenantProductCreateIntent` writes plus
  // the provenance and the timestamps the writer owns.
  const product = db.read(productPath(ids.productId));
  assert.deepEqual(Object.keys(product ?? {}).sort(), [
    "SKU", "categoryId", "cost", "createdAt", "createdBy", "name", "price",
    "quantity", "updatedAt",
  ]);
  assert.equal(product?.name, "Cola 500ml");
  assert.equal(product?.price, 19.99);
  assert.equal(product?.cost, 12.5);
  assert.equal(product?.quantity, 24);
  assert.equal(product?.createdBy, ACTOR);
  assert.ok(product?.createdAt instanceof Timestamp);
  // Written so the nightly stock verification defers a product whose ledger
  // entry may not be visible to its query yet.
  assert.ok(product?.updatedAt instanceof Timestamp);
});

test("imported stock arrives with the ledger entry that says where it came from", async () => {
  const db = seededCategories();

  const response = await applyImport(db, [importRow({quantity: 24})]);

  const ids = productImportRowIds(IMPORT_IDENTITY, 0);
  const movement = db.read(
    `${productPath(ids.productId)}/stock_movements/${ids.adjustmentId}`
  );
  // `adjustStock`'s own shape, because an imported unit and an adjusted unit are
  // the same unit and reconciliation reads one ledger. `quantityDelta` and
  // `recordedAt` are the two fields that ledger walk actually reads.
  assert.equal(movement?.adjustmentType, "opening_balance");
  assert.equal(movement?.sourceType, "product_import");
  assert.equal(movement?.quantityDelta, 24);
  assert.equal(movement?.previousQuantity, 0);
  assert.equal(movement?.quantityAfter, 24);
  assert.equal(movement?.productId, ids.productId);
  assert.equal(movement?.actorUid, ACTOR);
  assert.ok(movement?.recordedAt instanceof Timestamp);

  const adjustment = db.read(`tenants/${TENANT}/stock_adjustments/${ids.adjustmentId}`);
  assert.equal(adjustment?.quantityDelta, 24);
  assert.equal(adjustment?.adjustmentType, "opening_balance");

  // Whenever the audit entry says a quantity moved, it names the record that
  // says where the stock came from. That pairing is what makes an opening
  // quantity acceptable in a product payload at all.
  const audit = db.read(auditPath(ids.auditId));
  assert.equal(audit?.eventType, "product_imported");
  assert.equal(audit?.mutatesQuantity, true);
  assert.equal(audit?.adjustmentId, ids.adjustmentId);
  assert.equal(audit?.openingQuantity, 24);
  assert.equal(audit?.rowIndex, 0);
  assert.equal(audit?.importId, response.importId);
  assert.equal(audit?.requestId, REQUEST);
  assert.deepEqual(audit?.created, {
    name: "Cola 500ml",
    sku: "CL500",
    price: 19.99,
    cost: null,
    categoryId: CATEGORY,
    quantity: 24,
  });
});

test("a product imported holding nothing writes no ledger entry", async () => {
  const db = seededCategories();

  const response = await applyImport(db, [importRow()]);

  const ids = productImportRowIds(IMPORT_IDENTITY, 0);
  assert.deepEqual(db.writtenPaths(), [
    productPath(ids.productId),
    auditPath(ids.auditId),
  ].sort());
  assert.equal(db.read(productPath(ids.productId))?.quantity, 0);
  // No stock moved, so nothing claims any did - the same sentence the catalog's
  // own create form makes true.
  assert.equal(db.read(auditPath(ids.auditId))?.mutatesQuantity, false);
  assert.equal(db.read(auditPath(ids.auditId))?.adjustmentId, null);
  assert.equal(response.rows[0].adjustmentId, null);
});

test("a category named by name is resolved against this business", async () => {
  const db = seededCategories();

  const response = await applyImport(db, [
    {name: "Crisps", sku: "CR1", price: 5, categoryName: "snacks"},
    {name: "Bread", sku: "BR1", price: 4, categoryName: "Bakery"},
    {name: "Fanta 500ml", sku: "FN500", price: 19.99, categoryId: "ct_snacks"},
  ]);

  assert.deepEqual(
    response.rows.map((entry) => entry.status),
    ["created", "failed", "created"]
  );
  assert.equal(response.rows[0].product?.categoryId, "ct_snacks");
  assert.match(response.rows[1].message ?? "", /No category in this business/);
  // Partial success, stated: the unmatched row wrote nothing while the other two
  // landed, and no audit entry claims a product that does not exist.
  assert.equal(db.ids(`tenants/${TENANT}/products`).length, 2);
  assert.equal(db.ids(`tenants/${TENANT}/audit_logs`).length, 2);
});

test("a business with more categories than the scan is refused, not guessed at", async () => {
  const db = seededCategories();
  for (let index = 0; index < MAXIMUM_IMPORT_CATEGORY_SCAN; index += 1) {
    db.seed(`tenants/${TENANT}/categories/ct_${index}`, {name: `Aisle ${index}`});
  }
  db.clearWrites();

  // The defect belongs to the business rather than to any row, so reporting it
  // per row would be describing the wrong thing.
  await assert.rejects(
    applyImport(db, [importRow({categoryId: undefined, categoryName: "Drinks"})]),
    (error: unknown) => error instanceof HttpsError &&
      error.code === "failed-precondition" &&
      /Name each row's category by categoryId/.test(error.message)
  );
  assert.deepEqual(db.writtenPaths(), []);
  // A request naming every category by ID needs no scan, so it is unaffected.
  const response = await applyImport(db, [importRow()]);
  assert.equal(response.createdCount, 1);
});

test("an import preview reads the categories and writes nothing whatsoever", async () => {
  const db = seededCategories();

  const response = await previewImport(db, [
    importRow({quantity: 24}),
    {name: "Crisps", sku: "CR1", price: 5, categoryName: "Snacks"},
  ]);

  assert.equal(response.mode, "preview");
  assert.equal(response.createdCount, 2);
  assert.equal(response.rows[0].product?.quantity, 24);
  assert.equal(response.rows[1].product?.categoryId, "ct_snacks");
  // Not the products, not the audit entries, not the stock ledger, and - decided
  // at the callable rather than here - not an idempotency record either, which is
  // what lets the commit that follows carry the same request ID.
  assert.deepEqual(db.writtenPaths(), []);
  assert.deepEqual(db.ids(`tenants/${TENANT}/products`), []);
  assert.equal(response.rows[0].productId, null);
});

test("an import whose every row was refused reads nothing at all", async () => {
  const db = seededCategories();

  // `getAll()` with no document references is an error rather than an empty
  // answer, and a request with no rows to plan must not reach it.
  const response = await applyImport(db, [importRow({price: 19.999})]);

  assert.equal(response.failedCount, 1);
  assert.deepEqual(db.writtenPaths(), []);
});

test("a replayed import is refused by the product it already created", async () => {
  const db = seededCategories();
  await applyImport(db, [importRow()]);
  db.clearWrites();

  // The idempotency wrapper answers a genuine retry off its own record and never
  // reaches this code. Reaching it means one identity was given two different
  // imports, and `create` refuses to let the second overwrite the first - which
  // is what makes a deterministic ID safe to reuse.
  await assert.rejects(
    applyImport(db, [importRow({name: "Cola 1L"})]),
    /ALREADY_EXISTS/
  );
  assert.equal(db.ids(`tenants/${TENANT}/products`).length, 1);
  assert.deepEqual(db.writtenPaths(), []);
});

test("an import under a second request stocks the shelf twice", async () => {
  const db = seededCategories();
  await applyImport(db, [importRow()]);
  db.clearWrites();

  // Stated rather than prevented. Nothing in this system makes a SKU or a name
  // unique - the till already refuses an ambiguous scan - so a fresh request ID
  // creates a second product describing the same thing. The preview is the
  // answer to that, not a duplicate check this app has never been able to make.
  await applyImport(db, [importRow()], {identityDocumentId: "f".repeat(64)});

  assert.equal(db.ids(`tenants/${TENANT}/products`).length, 2);
  assert.equal(db.ids(`tenants/${TENANT}/audit_logs`).length, 2);
});
