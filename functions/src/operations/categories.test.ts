import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import type {
  DocumentReference,
  Transaction,
} from "firebase-admin/firestore";
import {assertCategoryNameFree, readCategoryName} from "./categories";
import {MAXIMUM_IMPORT_CATEGORY_SCAN} from "./productImport";

/**
 * The two decisions behind `createCategory` and `renameCategory`, as units.
 *
 * Neither callable has logic beyond them: the rest is the authorization and the
 * transaction every other operation in this directory already has, and both are
 * exercised where those are.
 *
 * - **What a name may be**, which has to agree field for field with what the
 *   device already refuses. A name this accepted and the client did not would be
 *   a category no form could have created.
 * - **Whether the name is free**, which is the whole reason these stopped being
 *   document writes. Two categories folding to one name cannot be told apart
 *   when a spreadsheet names that category, and a rule cannot ask the question.
 */

/** A Firestore query snapshot, as much of one as the check under test reads. */
function snapshotOf(
  categories: ReadonlyArray<{id: string; name: unknown}>
): unknown {
  return {
    size: categories.length,
    docs: categories.map((category) => ({
      id: category.id,
      get: (field: string) =>
        field === "name" ? category.name : undefined,
    })),
  };
}

/** A transaction whose only job is to answer the categories query. */
function transactionOver(
  categories: ReadonlyArray<{id: string; name: unknown}>
): Transaction {
  return {
    get: async () => snapshotOf(categories),
  } as unknown as Transaction;
}

/** A tenant reference whose `categories` collection is a bounded query. */
const tenantRef = {
  collection: () => ({limit: () => ({})}),
} as unknown as DocumentReference;

async function refusalFrom(
  categories: ReadonlyArray<{id: string; name: unknown}>,
  name: string,
  exceptId: string | null = null
): Promise<HttpsError | null> {
  try {
    await assertCategoryNameFree(
      transactionOver(categories),
      tenantRef,
      name,
      exceptId
    );
    return null;
  } catch (error) {
    assert.ok(error instanceof HttpsError, `not an HttpsError: ${error}`);
    return error;
  }
}

test("a name is normalized the way the device normalizes it", () => {
  assert.equal(readCategoryName({name: "  Soft   drinks "}), "Soft drinks");
});

test("a name that is only whitespace is refused", () => {
  assert.throws(
    () => readCategoryName({name: "   "}),
    (error: unknown) =>
      error instanceof HttpsError && error.code === "invalid-argument"
  );
});

test("a control character is refused rather than stored", () => {
  assert.throws(
    () => readCategoryName({name: "Drinks"}),
    (error: unknown) =>
      error instanceof HttpsError && error.code === "invalid-argument"
  );
});

test("a field that is not part of a category is refused", () => {
  assert.throws(
    () => readCategoryName({name: "Drinks", colour: "blue"}),
    (error: unknown) =>
      error instanceof HttpsError && error.code === "invalid-argument"
  );
});

test("the provenance fields a queued document carries are accepted", () => {
  // **The migration argument.** A category queued by the build that wrote this
  // document directly carries `createdBy` or `updatedBy`, and this callable
  // takes both from the actor instead. Refusing a field that is merely
  // redundant would reject work already durable on somebody's phone.
  assert.equal(
    readCategoryName({name: "Drinks", createdBy: "user-a"}),
    "Drinks"
  );
  assert.equal(
    readCategoryName({name: "Drinks", updatedBy: "user-a"}),
    "Drinks"
  );
});

test("a free name passes", async () => {
  assert.equal(
    await refusalFrom([{id: "ct_bakery", name: "Bakery"}], "Drinks"),
    null
  );
});

test("a name another category already folds to is refused", async () => {
  const refusal = await refusalFrom(
    [{id: "ct_drinks", name: "Drinks"}],
    "  drinks  "
  );

  assert.equal(refusal?.code, "already-exists");
  // The name as it is actually spelled on the other category, so somebody can
  // find the one that is already there.
  assert.match(refusal?.message ?? "", /Drinks/);
});

test("case and spacing are what folding removes, and nothing else", async () => {
  const existing = [{id: "ct_soft", name: "Soft   Drinks"}];

  assert.equal((await refusalFrom(existing, "soft drinks"))?.code, "already-exists");
  // A different word is a different category, however similar it reads.
  assert.equal(await refusalFrom(existing, "Soft drink"), null);
});

test("a category does not collide with itself", async () => {
  // Renaming "drinks" to "Drinks" is a capitalisation fix, and refusing it
  // would make the one category holding that name the reason it cannot hold it.
  assert.equal(
    await refusalFrom([{id: "ct_drinks", name: "drinks"}], "Drinks", "ct_drinks"),
    null
  );
});

test("a rename onto another category's name is still refused", async () => {
  const refusal = await refusalFrom(
    [
      {id: "ct_drinks", name: "Drinks"},
      {id: "ct_bakery", name: "Bakery"},
    ],
    "Drinks",
    "ct_bakery"
  );

  assert.equal(refusal?.code, "already-exists");
});

test("a category holding no readable name blocks nothing", async () => {
  // It cannot be resolved by name either, so it cannot make an import
  // ambiguous - and refusing every new name because of it would be worse.
  assert.equal(
    await refusalFrom([{id: "ct_broken", name: 42}], "Drinks"),
    null
  );
});

test("more categories than an import resolves is refused outright", async () => {
  // The same bound `getProductImportCategories` stops at, deliberately: above
  // it an import refuses every row that names a category by name, so there is
  // no ambiguity left to prevent - and the message says the same thing that
  // path says.
  const many = Array.from(
    {length: MAXIMUM_IMPORT_CATEGORY_SCAN + 1},
    (_, index) => ({id: `ct_${index}`, name: `Category ${index}`})
  );

  const refusal = await refusalFrom(many, "Drinks");

  assert.equal(refusal?.code, "failed-precondition");
  assert.match(refusal?.message ?? "", /categoryId/);
});
