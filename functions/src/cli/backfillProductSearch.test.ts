import assert from "node:assert/strict";
import test from "node:test";

import {optionsOf, productSearchUpdateOf} from "./backfillProductSearch";
import {productSearchFields} from "../operations/productUpdate";

test("migration defaults to dry-run and validates its bounded options", () => {
  assert.deepEqual(optionsOf([]), {apply: false, tenantId: undefined, pageSize: 200});
  assert.deepEqual(optionsOf(["--apply", "--tenant", "tenant-a", "--page-size", "40"]), {
    apply: true,
    tenantId: "tenant-a",
    pageSize: 40,
  });
  assert.throws(() => optionsOf(["--tenant", "bad/path"]));
  assert.throws(() => optionsOf(["--page-size", "401"]));
});

test("dry-run finds a change, apply produces it, and repeat is idempotent", () => {
  const stored: Record<string, unknown> = {
    name: "  Brown   Bread ",
    SKU: "BR-100",
    quantity: 4,
  };

  const dryRun = productSearchUpdateOf(stored);
  assert.deepEqual(dryRun, {
    searchName: "brown bread",
    searchPrefixes: [
      "br",
      "br-",
      "br-1",
      "br-10",
      "br-100",
      "bre",
      "brea",
      "bread",
      "bro",
      "brow",
      "brown",
    ],
  });
  assert.equal("searchName" in stored, false, "dry-run must not mutate input");

  Object.assign(stored, dryRun);
  assert.equal(productSearchUpdateOf(stored), null, "repeat apply must have no write");
});

test("unreadable legacy products are explicitly invalid", () => {
  assert.throws(() => productSearchUpdateOf({SKU: "500ml"}));
  assert.throws(() => productSearchUpdateOf({name: "Bread", SKU: 7}));
});

test("a product with no size is indexed by its name alone", () => {
  assert.deepEqual(
    productSearchUpdateOf({name: "Bread"}),
    productSearchFields("Bread", "")
  );
});
