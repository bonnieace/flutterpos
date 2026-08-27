import assert from "node:assert/strict";
import test from "node:test";
import {optionsOf, staffSearchUpdateOf} from "./backfillStaffSearch";

test("staff search backfill emits stable name and email prefixes", () => {
  const update = staffSearchUpdateOf({
    name: "Jane Njeri",
    email: "jane.njeri@example.test",
  });
  assert.ok(update);
  assert.equal(update.searchName, "jane njeri");
  assert.ok(update.searchPrefixes.includes("jane n"));
  assert.ok(update.searchPrefixes.includes("njeri"));
  assert.ok(update.searchPrefixes.includes("example"));
  assert.equal(staffSearchUpdateOf({
    name: "Jane Njeri",
    email: "jane.njeri@example.test",
    ...update,
  }), null);
});

test("staff search backfill is dry-run by default and validates options", () => {
  assert.deepEqual(optionsOf([]), {
    apply: false,
    tenantId: undefined,
    pageSize: 200,
  });
  assert.deepEqual(optionsOf(["--apply", "--tenant", "tenant-a"]), {
    apply: true,
    tenantId: "tenant-a",
    pageSize: 200,
  });
  assert.throws(() => optionsOf(["--tenant", "bad/path"]));
  assert.throws(() => optionsOf(["--page-size", "0"]));
});

test("staff search backfill supports email-only canonical identities", () => {
  const update = staffSearchUpdateOf({email: "jane@example.test"});
  assert.ok(update);
  assert.equal(update.searchName, "jane@example.test");
  assert.ok(update.searchPrefixes.includes("jane"));
  assert.ok(update.searchPrefixes.includes("example"));

  assert.throws(() => staffSearchUpdateOf({name: "Jane"}));
  assert.throws(() => staffSearchUpdateOf({name: "Jane", email: "  "}));
});
