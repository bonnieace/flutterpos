import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import path from "node:path";
import test from "node:test";
import {describeSaleReturn, ReturnedUnits, SaleLike} from "./domain";

/**
 * The TypeScript half of the shared return-offset vectors.
 *
 * **Why a fixture file rather than inline cases.** The same money rule exists
 * twice - `describeSaleReturn` here and `describeReturnOffset` in
 * `lib/returns/return_offsets.dart` - because a period is read online through
 * the callable and offline through the device aggregator. Two implementations
 * of one rule drift. `test/returns/return_offset_vectors_test.dart` reads this
 * same file and asserts the same numbers, so a divergent rounding or a
 * re-parenthesised multiply fails on one side and not the other.
 */

interface Vector {
  name: string;
  categoryId: string | null;
  returnedUnits: Record<string, number>;
  expect: {
    revenueMinor: number;
    costMinor: number;
    fullyReturnedCostlessLines: number;
    fullyReturned: boolean;
  };
  sale: SaleLike;
}

// From `functions/lib/operations/` at run time - the suite is `node --test`
// over compiled JS, not over this file. Three levels up is the repo root.
const FIXTURE = path.resolve(
  __dirname,
  "..",
  "..",
  "..",
  "test",
  "fixtures",
  "return_offset_vectors.json"
);

const vectors: Vector[] =
  JSON.parse(readFileSync(FIXTURE, "utf8")).vectors as Vector[];

test("the shared fixture is not silently empty", () => {
  // A runner that reads nothing passes, and a passing runner over no vectors
  // is worse than no runner: it reports agreement never checked.
  assert.ok(vectors.length >= 9, `only ${vectors.length} vectors were read`);
});

for (const vector of vectors) {
  test(`return offset: ${vector.name}`, () => {
    const returned: ReturnedUnits = new Map(
      Object.entries(vector.returnedUnits)
    );
    const offset = describeSaleReturn(
      vector.sale,
      returned,
      vector.categoryId ?? undefined
    );
    assert.deepEqual(
      {
        revenueMinor: offset.revenueMinor,
        costMinor: offset.costMinor,
        fullyReturnedCostlessLines: offset.fullyReturnedCostlessLines,
        fullyReturned: offset.fullyReturned,
      },
      vector.expect
    );
  });
}
