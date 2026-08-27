import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {TenantRole} from "../core/model";
import {
  MAXIMUM_PRODUCT_NAME_LENGTH,
  MAXIMUM_PRODUCT_SKU_LENGTH,
  ProductUpdateInput,
  StoredProductFields,
  assertProductUpdateAuthorized,
  planProductUpdate,
  productPriceMinorUnits,
  productSearchFields,
  readProductUpdateInput,
  readSellableProduct,
} from "./productUpdate";

/**
 * The decisions behind `updateProduct`, as units.
 *
 * Everything worth pinning about correcting a product lives in this module: the
 * payload it refuses, the price arithmetic it shares with the till, the role
 * split between fixing a name and changing money, and the state it declines to
 * write. The callable around it is the shared authorization wrapper, the shared
 * idempotency wrapper, and two Firestore writes, and those are covered by
 * `products.test.ts` and by their own suites.
 *
 * The prices here are not arbitrary. `19.99` and `0.07` are the two spellings
 * that expose binary floating point - `19.99 * 100` is `1998.9999999999998` and
 * `0.07 * 100` is `7.000000000000001` - and the till accepts both. `19.999` is
 * the one the till refuses, and it is the reason this validation is on the
 * server at all.
 */

const CATEGORY = "ct_drinks";

/** A product every client parses and the till can sell. */
function storedProduct(
  overrides: StoredProductFields = {}
): StoredProductFields {
  return {
    name: "Cola 500ml",
    SKU: "CL500",
    price: 19.99,
    quantity: 12,
    categoryId: CATEGORY,
    ...overrides,
  };
}

function input(data: Record<string, unknown>): ProductUpdateInput {
  return readProductUpdateInput({
    tenantId: "tenant-a",
    productId: "pd_1",
    requestId: "request-00000001",
    ...data,
  });
}

/** The code a refusal reports, which is what a client classifies on. */
function refusalCode(attempt: () => unknown): string {
  return refusal(attempt).code;
}

function refusal(attempt: () => unknown): HttpsError {
  try {
    attempt();
  } catch (error) {
    assert.ok(error instanceof HttpsError, `${error}`);
    return error;
  }
  return assert.fail("The correction was not refused.");
}

function plan(
  product: StoredProductFields | undefined,
  requested: Record<string, unknown>
) {
  return planProductUpdate({product, requested: input(requested)});
}

test("a corrected price is stored as the till converts it back", () => {
  const result = plan(storedProduct(), {price: 24.5});

  assert.deepEqual(result.changedFields, ["price"]);
  assert.equal(result.product.price, 24.5);
  assert.equal(result.product.priceMinor, 2450);
  assert.deepEqual(result.documentUpdate, {price: 24.5});
  assert.deepEqual(result.changes, [
    {field: "price", previous: 19.99, next: 24.5},
  ]);
});

test("a price the till would refuse is refused where it is typed", () => {
  // `19.999` passes `price is number && price >= 0`, which is everything a
  // Firestore rule can check. It then fails `checkoutMinorUnitsFromMajor` at the
  // till with a customer standing there. This is the whole argument for putting
  // the correction on the server.
  assert.equal(refusalCode(() => input({price: 19.999})), "invalid-argument");
  assert.equal(refusalCode(() => input({price: -1})), "invalid-argument");
  assert.equal(refusalCode(() => input({price: Number.NaN})), "invalid-argument");
  assert.equal(
    refusalCode(() => input({price: Number.POSITIVE_INFINITY})),
    "invalid-argument"
  );
  assert.equal(refusalCode(() => input({price: "24.50"})), "invalid-argument");
});

test("the two spellings binary floating point gets wrong are both accepted", () => {
  assert.equal(productPriceMinorUnits(19.99), 1999);
  assert.equal(productPriceMinorUnits(0.07), 7);
  assert.equal(productPriceMinorUnits(0), 0);
  assert.equal(productPriceMinorUnits(19.999), undefined);
  assert.equal(productPriceMinorUnits(1_000_000_000.01), undefined);
});

test("a payload that so much as mentions quantity is refused", () => {
  // The single refusal this callable's safety rests on. Writing a quantity here
  // would be a second way to move stock with no `stock_movements` entry, which
  // is the property `adjustStock` exists to guarantee.
  //
  // The message is asserted, not only the code. `quantity` is refused twice over
  // - once by name and once as a key outside the accepted set - so a test that
  // checked the code alone would still pass with the dedicated refusal deleted,
  // and the caller would be told "not an editable product field" instead of
  // where stock is actually moved. That was true of this test until a mutation
  // run caught it.
  for (const payload of [{name: "Cola", quantity: 5}, {quantity: 0}, {name: "Cola", quantity: null}]) {
    const refused = refusal(() => input(payload));
    assert.equal(refused.code, "invalid-argument");
    assert.match(refused.message, /adjustStock/);
  }
});

test("an unknown key is refused rather than dropped", () => {
  // Silently ignoring one would make "this never writes quantity" something a
  // caller has to take on trust instead of something it can observe.
  assert.equal(refusalCode(() => input({name: "Cola", image: "x"})), "invalid-argument");
  assert.equal(refusalCode(() => input({name: "Cola", createdBy: "uid"})), "invalid-argument");
});

test("a plan never names quantity, however the request is spelled", () => {
  const keys = Object.keys(
    plan(storedProduct(), {name: "Cola 500 ml", sku: "CL-500", price: 21, categoryId: "ct_new"})
      .documentUpdate
  );
  assert.equal(keys.includes("quantity"), false);
  assert.deepEqual(keys.sort(), [
    "SKU", "categoryId", "name", "price", "searchName", "searchPrefixes",
  ]);
});

test("a request naming nothing editable is refused", () => {
  assert.equal(refusalCode(() => input({})), "invalid-argument");
  assert.equal(
    refusalCode(() => input({name: null, sku: null, price: null, categoryId: null})),
    "invalid-argument"
  );
});

test("a name is normalized into the shape the strict read model demands", () => {
  const result = plan(storedProduct(), {name: "  Cola\t\t500 ml  "});

  assert.deepEqual(result.documentUpdate, {
    name: "Cola 500 ml",
    ...productSearchFields("Cola 500 ml", "CL500"),
  });
  assert.equal(result.product.name, "Cola 500 ml");
});

test("a name or SKU that would make the whole catalog unreadable is refused", () => {
  assert.equal(refusalCode(() => input({name: "   "})), "invalid-argument");
  // Built rather than typed, so no source file in this repository carries a
  // raw control character.
  const control = String.fromCharCode(1);
  assert.equal(
    refusalCode(() => input({name: `Co${control}la`})),
    "invalid-argument"
  );
  assert.equal(
    refusalCode(() => input({name: "x".repeat(MAXIMUM_PRODUCT_NAME_LENGTH + 1)})),
    "invalid-argument"
  );
  assert.equal(refusalCode(() => input({name: 42})), "invalid-argument");
  assert.equal(refusalCode(() => input({sku: ""})), "invalid-argument");
  assert.equal(
    refusalCode(() => input({sku: "x".repeat(MAXIMUM_PRODUCT_SKU_LENGTH + 1)})),
    "invalid-argument"
  );
});

test("a SKU with a space in it is refused, because a scanner cannot emit one", () => {
  assert.equal(refusalCode(() => input({sku: "CL 500"})), "invalid-argument");
  // Surrounding whitespace is a typo rather than an unscannable code, so it is
  // trimmed the way the create surface trims it.
  assert.deepEqual(plan(storedProduct(), {sku: "  CL501  "}).documentUpdate, {
    SKU: "CL501",
    ...productSearchFields("Cola 500ml", "CL501"),
  });
});

test("a request that changes nothing is refused rather than audited", () => {
  // Reachable only with a fresh request ID: a genuine retry answers off the
  // idempotency record and never reaches the plan.
  assert.equal(
    refusalCode(() => plan(storedProduct(), {name: "Cola 500ml", price: 19.99})),
    "failed-precondition"
  );
});

test("only the fields that moved are written", () => {
  const result = plan(storedProduct(), {name: "Cola 500ml", sku: "CL501"});

  assert.deepEqual(result.changedFields, ["sku"]);
  assert.deepEqual(result.documentUpdate, {
    SKU: "CL501",
    ...productSearchFields("Cola 500ml", "CL501"),
  });
  assert.deepEqual(result.changes, [
    {field: "sku", previous: "CL500", next: "CL501"},
  ]);
});

test("a product that does not exist is not found", () => {
  assert.equal(refusalCode(() => plan(undefined, {name: "Cola"})), "not-found");
});

test("a field this request does not name and cannot parse refuses the whole request", () => {
  // Quietly making an already-broken product less broken would report success
  // while the cached catalog stayed a miss for every product in the business.
  const broken = storedProduct({SKU: undefined});
  assert.equal(refusalCode(() => plan(broken, {name: "Cola 500 ml"})), "failed-precondition");

  // Naming the broken field in the same request is the way through.
  const fixed = plan(broken, {name: "Cola 500 ml", sku: "CL500"});
  assert.deepEqual(fixed.changedFields, ["name", "sku"]);
  assert.deepEqual(fixed.changes[1], {field: "sku", previous: null, next: "CL500"});
});

test("a stored price the till cannot sell blocks a name fix until it is corrected", () => {
  const unsellable = storedProduct({price: 19.999});
  assert.equal(refusalCode(() => plan(unsellable, {name: "Cola"})), "failed-precondition");

  const corrected = plan(unsellable, {name: "Cola", price: 20});
  assert.deepEqual(corrected.changedFields, ["name", "price"]);
  assert.equal(corrected.product.priceMinor, 2000);
});

test("a non-integer stored quantity is named as an operator's problem", () => {
  // This callable cannot write `quantity` and `adjustStock` refuses to read it,
  // so there is no in-app route out. Saying so beats a green result that changes
  // nothing the till can observe.
  assert.equal(
    refusalCode(() => plan(storedProduct({quantity: 12.5}), {name: "Cola"})),
    "failed-precondition"
  );
  assert.equal(
    refusalCode(() => plan(storedProduct({quantity: "12"}), {name: "Cola"})),
    "failed-precondition"
  );
});

test("a stored image that is not an HTTPS URL is named as an operator's problem", () => {
  assert.equal(
    refusalCode(() => plan(storedProduct({image: "http://cdn/x.png"}), {name: "Cola"})),
    "failed-precondition"
  );
  // Absent and empty both mean no image, exactly as the client's read model has
  // it, so neither blocks a correction.
  assert.deepEqual(
    plan(storedProduct({image: ""}), {name: "Cola"}).changedFields,
    ["name"]
  );
  assert.deepEqual(
    plan(storedProduct({image: "https://cdn.example/x.png"}), {name: "Cola"}).changedFields,
    ["name"]
  );
});

test("an HTTPS image can be added, replaced, and removed without touching money", () => {
  const added = plan(storedProduct(), {image: "https://cdn.example/new.webp"});
  assert.deepEqual(added.changedFields, ["image"]);
  assert.deepEqual(added.documentUpdate, {image: "https://cdn.example/new.webp"});
  assert.deepEqual(added.changes, [{
    field: "image",
    previous: null,
    next: "replacement image",
  }]);

  const removed = plan(
    storedProduct({image: "https://cdn.example/old.png"}),
    {image: null}
  );
  assert.deepEqual(removed.changedFields, ["image"]);
  assert.deepEqual(removed.documentUpdate, {image: null});
  assert.equal(removed.product.image, null);
});

test("a legacy category alias moves with the field it aliases", () => {
  // The client's read model refuses a product whose `category` and `categoryId`
  // name different categories, and one unreadable product misses the whole
  // cached catalog. Leaving the alias behind would do exactly that.
  const legacy = storedProduct({category: CATEGORY});
  const result = plan(legacy, {categoryId: "ct_snacks"});

  assert.deepEqual(result.documentUpdate, {
    categoryId: "ct_snacks",
    category: "ct_snacks",
  });
  assert.deepEqual(result.changes, [
    {field: "categoryId", previous: CATEGORY, next: "ct_snacks"},
  ]);
});

test("a product filed only under the legacy alias is read through it", () => {
  const legacyOnly: StoredProductFields = {
    name: "Cola 500ml",
    SKU: "CL500",
    price: 19.99,
    quantity: 12,
    category: CATEGORY,
  };
  assert.equal(readSellableProduct(legacyOnly).categoryId, CATEGORY);

  // Asked for the category it already holds, it records no change - so the
  // request is refused rather than writing an audit row whose before and after
  // are equal.
  assert.equal(
    refusalCode(() => plan(legacyOnly, {categoryId: CATEGORY})),
    "failed-precondition"
  );
});

test("a product whose two category fields already disagree is refused", () => {
  const contradictory = storedProduct({category: "ct_other"});
  assert.equal(refusalCode(() => plan(contradictory, {name: "Cola"})), "failed-precondition");
});

test("a category ID that is not a document ID is refused as input", () => {
  assert.equal(refusalCode(() => input({categoryId: "a/b"})), "invalid-argument");
  assert.equal(refusalCode(() => input({categoryId: ".."})), "invalid-argument");
  assert.equal(refusalCode(() => input({categoryId: 7})), "invalid-argument");
});

test("only an owner or an administrator may name a price", () => {
  const priceChange = input({price: 24.5});
  const nameChange = input({name: "Cola 500 ml"});

  for (const role of ["owner", "admin"] as TenantRole[]) {
    assert.doesNotThrow(() => assertProductUpdateAuthorized(role, priceChange));
  }
  for (const role of ["manager", "cashier"] as TenantRole[]) {
    assert.equal(
      refusalCode(() => assertProductUpdateAuthorized(role, priceChange)),
      "permission-denied"
    );
  }
  // Everything else is the operational set the `products` create rule names.
  for (const role of ["owner", "admin", "manager", "cashier"] as TenantRole[]) {
    assert.doesNotThrow(() => assertProductUpdateAuthorized(role, nameChange));
  }
});

test("naming a price decides the role, not whether the price turns out to differ", () => {
  // A manager whose permission depended on the value already in the document
  // would be a rule nobody could explain, and would let a manager discover a
  // price by binary search over refusals.
  const unchanged = input({name: "Cola 500 ml", price: 19.99});
  assert.equal(
    refusalCode(() => assertProductUpdateAuthorized("manager", unchanged)),
    "permission-denied"
  );
});

/**
 * What a business paid, and the one guarantee the whole feature rests on.
 *
 * A cost is optional at every layer, it sits behind the same role as a price
 * because it is money and because it is the business's margin written down, and
 * it is the only field here whose *absence* a caller can ask for. A sale copies
 * whatever it holds at the moment of the sale onto its own line, so nothing
 * below can reach a profit figure that has already been reported - that half is
 * proved in `test/checkout/checkout_draft_test.dart`.
 */

test("a recorded cost is stored as the till converts it back", () => {
  const result = plan(storedProduct(), {cost: 12.5});

  assert.deepEqual(result.changedFields, ["cost"]);
  assert.equal(result.product.cost, 12.5);
  assert.equal(result.product.costMinor, 1250);
  assert.deepEqual(result.documentUpdate, {cost: 12.5});
  assert.deepEqual(result.changes, [
    {field: "cost", previous: null, next: 12.5},
  ]);
});

test("a corrected cost records what it replaced", () => {
  const result = plan(storedProduct({cost: 9}), {cost: 11.25});

  assert.deepEqual(result.changes, [
    {field: "cost", previous: 9, next: 11.25},
  ]);
});

test("a cost the till could not record on a sale line is refused", () => {
  // The same arithmetic the price goes through, for the same reason: a sale line
  // records the cost beside the price, so a cost the till cannot convert would
  // silently record no cost at all and report the whole revenue as profit.
  assert.equal(refusalCode(() => input({cost: 12.505})), "invalid-argument");
  assert.equal(refusalCode(() => input({cost: -1})), "invalid-argument");
  assert.equal(refusalCode(() => input({cost: "12.50"})), "invalid-argument");
  assert.equal(refusalCode(() => input({cost: Number.NaN})), "invalid-argument");
});

test("an explicit null clears a cost, unlike every other field", () => {
  // Absent means "leave it alone" everywhere in this payload. `cost` is the one
  // field where null means something else, because a cost entered by mistake
  // would otherwise be permanent - and a wrong margin reported as fact is worse
  // than no margin at all.
  const result = plan(storedProduct({cost: 9}), {cost: null});

  assert.deepEqual(result.changedFields, ["cost"]);
  assert.equal(result.product.cost, null);
  assert.equal(result.product.costMinor, null);
  assert.deepEqual(result.documentUpdate, {cost: null});
  assert.deepEqual(result.changes, [{field: "cost", previous: 9, next: null}]);
});

test("clearing a cost that was never recorded changes nothing and is refused", () => {
  assert.equal(
    refusal(() => plan(storedProduct(), {cost: null})).message,
    "This product already holds every value in the request."
  );
});

test("re-recording the cost a product already holds is refused", () => {
  assert.equal(
    refusal(() => plan(storedProduct({cost: 9}), {cost: 9})).message,
    "This product already holds every value in the request."
  );
});

test("a stored cost nothing can read blocks an unrelated correction", () => {
  // The same contract every other field has: name every broken field in one
  // request, or none. A cost is money on a sale line, so a product carrying an
  // unreadable one must not quietly keep selling with it.
  assert.equal(
    refusalCode(() => plan(storedProduct({cost: "nine"}), {name: "Cola 1L"})),
    "failed-precondition"
  );
  assert.equal(
    refusalCode(() => plan(storedProduct({cost: 12.505}), {name: "Cola 1L"})),
    "failed-precondition"
  );
});

test("clearing is the escape hatch for a cost too broken to correct", () => {
  // The refusal above names `cost: null` as the way out, so it has to work: the
  // cleared value is what is validated, not the stored garbage.
  const result = plan(storedProduct({cost: "nine"}), {cost: null});

  assert.deepEqual(result.documentUpdate, {cost: null});
  // The audit keeps the unreadable value verbatim rather than flattening it to
  // null. "Who set this to `nine`, and when" is exactly the question a cleared
  // cost leaves behind, and it is answerable only if the string survives here.
  assert.deepEqual(result.changes, [
    {field: "cost", previous: "nine", next: null},
  ]);
});

test("an absent cost is not a fault, because no old product has one", () => {
  // The client's read model is strict and one product it refuses makes the whole
  // cached catalog a miss. Requiring a cost would have stopped every existing
  // business selling the moment this shipped.
  const product = readSellableProduct(storedProduct());

  assert.equal(product.cost, null);
  assert.equal(product.costMinor, null);
  assert.equal(product.priceMinor, 1999);
});

test("only an owner or an administrator may say what a product cost", () => {
  const cost = input({cost: 12.5});
  for (const role of ["owner", "admin"] as TenantRole[]) {
    assert.doesNotThrow(() => assertProductUpdateAuthorized(role, cost));
  }
  const denied = refusal(
    () => assertProductUpdateAuthorized("manager" as TenantRole, cost)
  );
  assert.equal(denied.code, "permission-denied");
  assert.match(denied.message, /what a product costs/);

  // A manager keeps everything that is not money.
  assert.doesNotThrow(
    () => assertProductUpdateAuthorized(
      "manager" as TenantRole,
      input({name: "Cola 1L"})
    )
  );
});

test("naming a cost is enough to need the money role, whatever it holds", () => {
  // Read from the requested fields rather than the resulting diff, so a manager
  // cannot discover a cost by binary search over refusals.
  const unchanged = input({cost: 9});
  assert.equal(
    refusalCode(
      () => assertProductUpdateAuthorized("manager" as TenantRole, unchanged)
    ),
    "permission-denied"
  );
  assert.equal(
    refusalCode(
      () => assertProductUpdateAuthorized("cashier" as TenantRole, input({cost: null}))
    ),
    "permission-denied"
  );
});

test("cost travels with the other editable fields in one request", () => {
  const result = plan(storedProduct({cost: 9}), {
    name: "Cola 1L",
    price: 24.5,
    cost: 11,
  });

  assert.deepEqual(result.changedFields, ["name", "price", "cost"]);
  assert.deepEqual(result.documentUpdate, {
    name: "Cola 1L",
    price: 24.5,
    cost: 11,
    ...productSearchFields("Cola 1L", "CL500"),
  });
});

test("quantity is still the refusal that outranks everything", () => {
  // Adding a second monetary field must not have opened a second way to move
  // stock without a ledger entry.
  assert.equal(
    refusalCode(() => input({cost: 12.5, quantity: 40})),
    "invalid-argument"
  );
});
