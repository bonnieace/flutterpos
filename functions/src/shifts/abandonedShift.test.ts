import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {cashierCanStillClose, readOpenShift} from "./abandonedShift";

const TENANT = "tenant-a";
const SHIFT = "shift_1785574800000_a1b2c3";
const BUSINESS_DATE = "2026-07-31";

function openShift(overrides: Record<string, unknown> = {}) {
  return {
    shiftId: SHIFT,
    tenantId: TENANT,
    staffId: "user-a",
    businessDate: BUSINESS_DATE,
    status: "open",
    ...overrides,
  };
}

function refusal(shift: unknown): string {
  try {
    readOpenShift(TENANT, SHIFT, shift as never);
  } catch (error) {
    assert.ok(error instanceof HttpsError);
    return error.code;
  }
  return "no-refusal";
}

// ---------------------------------------------------------------------------

test("an open shift that describes itself is readable", () => {
  assert.deepEqual(readOpenShift(TENANT, SHIFT, openShift()), {
    staffId: "user-a",
    businessDate: BUSINESS_DATE,
  });
});

test("a shift that disagrees with its own path is refused", () => {
  // The closure record names a cashier and a business date. Both have to be
  // this shift's own or the record is a fiction about somebody.
  assert.equal(refusal(openShift({shiftId: "shift-other"})), "failed-precondition");
  assert.equal(refusal(openShift({tenantId: "tenant-b"})), "failed-precondition");
});

test("only an open shift may be closed this way", () => {
  assert.equal(refusal(openShift({status: "closed"})), "failed-precondition");
  assert.equal(refusal(openShift({status: undefined})), "failed-precondition");
  assert.equal(refusal(undefined), "not-found");
});

test("a shift naming no cashier or no date is refused", () => {
  assert.equal(refusal(openShift({staffId: undefined})), "failed-precondition");
  assert.equal(refusal(openShift({staffId: ""})), "failed-precondition");
  assert.equal(refusal(openShift({staffId: 7})), "failed-precondition");
  assert.equal(refusal(openShift({businessDate: "31-07-2026"})), "failed-precondition");
  assert.equal(refusal(openShift({businessDate: undefined})), "failed-precondition");
});

// ---------------------------------------------------------------------------

test("only an active cashier can still close their own shift", () => {
  assert.equal(cashierCanStillClose(true, "active"), true);
});

test("every other standing counts as abandoned", () => {
  // **Not an allowlist of the inactive ones.** A status this build has never
  // heard of must not read as permission to keep a shift open for ever, which
  // is the state this whole path exists to end.
  for (const status of ["deactivated", "suspended", "invited", "", undefined, null, 7]) {
    assert.equal(
      cashierCanStillClose(true, status),
      false,
      `status ${String(status)} should not block the closure`
    );
  }
});

test("a staff record that is gone cannot close anything", () => {
  // The deleted-membership case. An absent record is the strongest form of
  // abandoned, not a reason to refuse the only recovery there is.
  assert.equal(cashierCanStillClose(false, "active"), false);
  assert.equal(cashierCanStillClose(false, undefined), false);
});
