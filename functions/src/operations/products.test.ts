import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {FakeFirestore} from "../testing/fakeFirestore";
import {applyProductUpdate} from "./products";
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
