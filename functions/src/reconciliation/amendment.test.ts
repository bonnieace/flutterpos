import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  ClosedShiftFields,
  MAXIMUM_SHIFT_SALES_MINOR_UNITS,
  ShiftExpectationFields,
  clearsRecordedAnomaly,
  planShiftSummaryAmendment,
  readClosedShiftSummary,
} from "./amendment";
import {shiftAnomalyId, shiftExpectationId} from "./model";

const TENANT = "tenant-a";
const SHIFT = "shift_1785574800000_a1b2c3";
const BUSINESS_DATE = "2026-07-31";

/** A shift closed with a summary 149.75 short of the sales filed against it. */
function closedShift(overrides: ClosedShiftFields = {}): ClosedShiftFields {
  return {
    shiftId: SHIFT,
    tenantId: TENANT,
    staffId: "cashier-a",
    status: "closed",
    businessDate: BUSINESS_DATE,
    totalSales: 1200.5,
    totalSalesMinor: 120050,
    transactionCount: 9,
    ...overrides,
  };
}

/** The settled `shift_expectations` record the metrics writer derived. */
function settledVariance(
  overrides: ShiftExpectationFields = {}
): ShiftExpectationFields {
  return {
    tenantId: TENANT,
    shiftId: SHIFT,
    businessDate: BUSINESS_DATE,
    sales: 1350.25,
    transactions: 10,
    generation: "generation-one",
    needsVerification: false,
    verificationStatus: "variance",
    verifiedGeneration: "generation-one",
    ...overrides,
  };
}

/**
 * Both arguments are required on purpose: a default would silently substitute a
 * valid document for the explicit `undefined` that every missing-document case
 * is testing, and those cases would pass without ever running.
 */
function plan(
  shift: ClosedShiftFields | undefined,
  expectation: ShiftExpectationFields | undefined
) {
  return planShiftSummaryAmendment({
    tenantId: TENANT,
    shiftId: SHIFT,
    shift,
    expectation,
  });
}

/** The code a refused amendment reports, which is what a client classifies on. */
function refusalCode(
  shift: ClosedShiftFields | undefined,
  expectation: ShiftExpectationFields | undefined
): string {
  try {
    plan(shift, expectation);
  } catch (error) {
    assert.ok(error instanceof HttpsError, `${error}`);
    return error.code;
  }
  return assert.fail("The amendment was not refused.");
}

test("a settled variance is amended to the total the sales prove", () => {
  const amendment = plan(closedShift(), settledVariance());

  assert.equal(amendment.totalSalesMinor, 135025);
  assert.equal(amendment.totalSales, 1350.25);
  assert.equal(amendment.transactionCount, 10);
  assert.equal(amendment.previousTotalSalesMinor, 120050);
  assert.equal(amendment.previousTotalSales, 1200.5);
  assert.equal(amendment.previousTransactionCount, 9);
  assert.equal(amendment.previousRepresentationsAgreed, true);
  assert.equal(amendment.businessDate, BUSINESS_DATE);
  assert.equal(amendment.staffId, "cashier-a");
  assert.equal(amendment.generation, "generation-one");

  // Observed minus expected, the direction the verifier and the listed anomaly
  // both use. A shift that took less than its sales say reports a shortfall.
  assert.equal(amendment.salesVarianceMinor, -14975);
  assert.equal(amendment.transactionVariance, -1);
});

test("the amendment never names the counted cash", () => {
  // The plan is the complete instruction, so a key that is absent here can
  // never be written. Erasing a cash discrepancy is the one thing this path
  // must be unable to do.
  const keys = Object.keys(plan(closedShift(), settledVariance()));
  assert.equal(keys.some((key) => key.toLowerCase().includes("cash")), false);
});

test("the amended shift and the record it clears use the shared identities", () => {
  const amendment = plan(closedShift(), settledVariance());

  // The metrics writer, the verifier, and this planner must address the same
  // two documents. A second definition of either would amend a shift against
  // another shift's expectation, or leave a resolved difference listed forever.
  assert.equal(
    amendment.expectationId,
    shiftExpectationId(BUSINESS_DATE, SHIFT)
  );
  assert.equal(
    amendment.anomalyId,
    shiftAnomalyId(SHIFT, "generation-one")
  );
});

test("only a closed shift that exists and owns its identity may be amended", () => {
  assert.equal(refusalCode(undefined, settledVariance()), "not-found");
  assert.equal(
    refusalCode(closedShift({status: "open"}), settledVariance()),
    "failed-precondition"
  );
  assert.equal(
    refusalCode(closedShift({tenantId: "tenant-b"}), settledVariance()),
    "failed-precondition"
  );
  assert.equal(
    refusalCode(closedShift({shiftId: "shift-other"}), settledVariance()),
    "failed-precondition"
  );
  assert.equal(
    refusalCode(closedShift({businessDate: "2026-02-30"}), settledVariance()),
    "failed-precondition"
  );
  assert.equal(
    refusalCode(closedShift({staffId: "with/slash"}), settledVariance()),
    "failed-precondition"
  );
});

test("a shift with no readable summary has no amendment path", () => {
  // This is the `invalid_or_missing_shift` outcome. There is no difference to
  // resolve, because nothing could be compared in the first place.
  for (const broken of [
    {totalSales: undefined},
    {totalSalesMinor: undefined},
    {transactionCount: undefined},
    {totalSales: "1200.50"},
    {totalSales: -1},
    {totalSalesMinor: 1.5},
    {transactionCount: -1},
    {totalSalesMinor: MAXIMUM_SHIFT_SALES_MINOR_UNITS + 1},
    {totalSales: Number.NaN},
  ]) {
    assert.equal(
      refusalCode(closedShift(broken), settledVariance()),
      "failed-precondition",
      `${JSON.stringify(broken)} was not refused.`
    );
  }
});

test("the sale-derived figure must exist and describe this exact shift", () => {
  assert.equal(refusalCode(closedShift(), undefined), "failed-precondition");
  for (const foreign of [
    {tenantId: "tenant-b"},
    {shiftId: "shift-other"},
    {businessDate: "2026-07-30"},
  ]) {
    assert.equal(
      refusalCode(closedShift(), settledVariance(foreign)),
      "failed-precondition",
      `${JSON.stringify(foreign)} was not refused.`
    );
  }
});

test("a pending, stale, or non-variance verification is refused", () => {
  // A record still waiting to be re-checked is about to be recomputed, so a
  // total taken from it is a total nothing has verified.
  for (const unsettled of [
    {needsVerification: true},
    {needsVerification: undefined},
    {verificationStatus: "matched"},
    {verificationStatus: "invalid_or_missing_shift"},
    {verificationStatus: "quarantined"},
    {verificationStatus: "amended"},
    {verificationStatus: undefined},
    {verifiedGeneration: "generation-zero"},
    {verifiedGeneration: undefined},
    {generation: undefined},
    {generation: ""},
    {generation: 7},
  ]) {
    assert.equal(
      refusalCode(closedShift(), settledVariance(unsettled)),
      "failed-precondition",
      `${JSON.stringify(unsettled)} was not refused.`
    );
  }
});

test("an unusable or unstorable sale-derived figure is refused", () => {
  for (const broken of [
    {sales: undefined},
    {sales: "1350.25"},
    {sales: -1},
    {sales: Number.POSITIVE_INFINITY},
    {transactions: undefined},
    {transactions: -1},
    {transactions: 2.5},
    {sales: MAXIMUM_SHIFT_SALES_MINOR_UNITS},
    // Firestore Rules and the client history model both refuse takings over no
    // transactions, so amending to one would leave an unreadable shift.
    {sales: 12.5, transactions: 0},
  ]) {
    assert.equal(
      refusalCode(closedShift(), settledVariance(broken)),
      "failed-precondition",
      `${JSON.stringify(broken)} was not refused.`
    );
  }
});

test("a shift that already matches its sales is refused rather than rewritten", () => {
  assert.equal(
    refusalCode(
      closedShift({totalSales: 1350.25, totalSalesMinor: 135025, transactionCount: 10}),
      settledVariance()
    ),
    "failed-precondition"
  );
  // Zero sales over zero transactions is a legitimate settled shift, and
  // matching it is still nothing to amend.
  assert.equal(
    refusalCode(
      closedShift({totalSales: 0, totalSalesMinor: 0, transactionCount: 0}),
      settledVariance({sales: 0, transactions: 0})
    ),
    "failed-precondition"
  );
});

test("a shift whose own two figures disagree is amended and the disagreement recorded", () => {
  // The verifier compares the major-unit figure, so this shift's difference is
  // measured from 1200.50 while its stored minor units claim 99999. Refusing
  // would leave an internally inconsistent shift nothing else reports; the
  // amendment overwrites both and records that they had disagreed.
  const amendment = plan(
    closedShift({totalSalesMinor: 99999}),
    settledVariance()
  );

  assert.equal(amendment.previousRepresentationsAgreed, false);
  assert.equal(amendment.previousTotalSalesMinor, 99999);
  assert.equal(amendment.previousTotalSales, 1200.5);
  assert.equal(amendment.salesVarianceMinor, 120050 - 135025);
  assert.equal(amendment.totalSalesMinor, 135025);
});

test("a matching major figure with broken minor units is not this path's business", () => {
  // The verifier compares major units, so it would have settled this shift as
  // matched and no variance record could exist. Amending it would mean acting on
  // an expectation that contradicts its own writer, and would quietly give a
  // governance callable a second purpose.
  assert.equal(
    refusalCode(
      closedShift({totalSales: 1350.25, totalSalesMinor: 1, transactionCount: 10}),
      settledVariance()
    ),
    "failed-precondition"
  );
});

test("the observed summary reports what the verifier compared", () => {
  const observed = readClosedShiftSummary(TENANT, SHIFT, closedShift());

  assert.equal(observed.observedSalesMinor, 120050);
  assert.equal(observed.expectationId, shiftExpectationId(BUSINESS_DATE, SHIFT));
  assert.equal(observed.staffId, "cashier-a");
  assert.equal(observed.representationsAgree, true);
});

test("only this shift's own recorded variance is ever cleared", () => {
  const amendment = plan(closedShift(), settledVariance());
  const recorded = {
    tenantId: TENANT,
    shiftId: SHIFT,
    anomalyType: "shift_variance",
  };

  assert.equal(clearsRecordedAnomaly(amendment, recorded, TENANT), true);
  assert.equal(clearsRecordedAnomaly(amendment, undefined, TENANT), false);
  for (const foreign of [
    {tenantId: "tenant-b"},
    {shiftId: "shift-other"},
    {anomalyType: "invalid_or_missing_shift"},
    {anomalyType: "stock_variance"},
    {anomalyType: undefined},
  ]) {
    assert.equal(
      clearsRecordedAnomaly(amendment, {...recorded, ...foreign}, TENANT),
      false,
      `${JSON.stringify(foreign)} was unexpectedly cleared.`
    );
  }
});
