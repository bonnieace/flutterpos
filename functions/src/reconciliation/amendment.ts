import {HttpsError} from "firebase-functions/v2/https";
import {requireDocumentId} from "../core/validation";
import {
  minorUnitsToMoney,
  moneyToMinorUnits,
  requireIsoDate,
} from "../operations/domain";
import {shiftAnomalyId, shiftExpectationId} from "./model";

/**
 * May a closed shift's summary ever be amended, and to what?
 *
 * A closed shift is terminal for every client: `firestore.rules` only permits
 * the `open -> closed` transition, so no device can rewrite one. Nightly
 * reconciliation nevertheless finds shifts whose recorded summary disagrees
 * with the immutable sales filed against them - an offline sale that reached
 * the server after its shift closed does exactly that, and the sale rule
 * deliberately accepts it rather than stranding the evidence.
 *
 * The answer this module encodes is: **yes, but only to the figure the
 * immutable sales already prove.** No caller supplies a total. The amendment
 * target is read from the `shift_expectations` record the metrics writer
 * derived from the sales themselves and the verifier has already settled, so
 * the only reachable outcome is the shift agreeing with its own sales.
 *
 * Three things are deliberately out of reach:
 *
 * - **The counted cash.** `closingCashMinor` is a physical count of a drawer.
 *   Amending it would erase a cash discrepancy, which is the single thing this
 *   path must never be able to do, so the plan never names it.
 * - **An open shift.** It is still the cashier's own to close, and closing is
 *   what computes the summary in the first place.
 * - **A shift whose totals could not be read at all.** That is recorded as
 *   `invalid_or_missing_shift`, and there is nothing to compare it against, so
 *   there is no figure the sales prove it should hold.
 */

/** The `verificationStatus` a settled disagreement carries. */
export const AMENDABLE_VERIFICATION_STATUS = "variance";

/** The terminal `verificationStatus` an amendment writes back. */
export const AMENDED_VERIFICATION_STATUS = "amended";

/**
 * The largest shift total that may be written, in minor units.
 *
 * This is the client's own `maximumShiftSalesMinor` from
 * `lib/shift/shift_sales_ledger.dart`. The history read model refuses a larger
 * summary, so an amendment beyond it would leave a shift no device could
 * display - a worse outcome than the variance it corrected.
 */
export const MAXIMUM_SHIFT_SALES_MINOR_UNITS = 1_000_000_000_000;

const MAXIMUM_GENERATION_LENGTH = 200;

/** The fields an amendment reads from `tenants/{tenantId}/shifts/{shiftId}`. */
export interface ClosedShiftFields {
  shiftId?: unknown;
  tenantId?: unknown;
  staffId?: unknown;
  status?: unknown;
  businessDate?: unknown;
  totalSales?: unknown;
  totalSalesMinor?: unknown;
  transactionCount?: unknown;
}

/** The fields an amendment reads from the settled `shift_expectations` record. */
export interface ShiftExpectationFields {
  tenantId?: unknown;
  shiftId?: unknown;
  businessDate?: unknown;
  sales?: unknown;
  transactions?: unknown;
  generation?: unknown;
  needsVerification?: unknown;
  verificationStatus?: unknown;
  verifiedGeneration?: unknown;
}

/** What one closed shift currently records about its own sales. */
export interface ObservedShiftSummary {
  businessDate: string;
  expectationId: string;

  /** The cashier the shift belongs to, named so the record stands on its own. */
  staffId: string;

  totalSales: number;
  totalSalesMinor: number;
  transactionCount: number;

  /**
   * `totalSales` converted the way the verifier converts it.
   *
   * The verifier compares the major-unit figure, so this - not the stored minor
   * figure - is the observation the recorded anomaly is about.
   */
  observedSalesMinor: number;

  /**
   * Whether the shift's two representations of the same money agree.
   *
   * A close writes both from one figure, so they normally do. When they do not,
   * the shift is internally inconsistent, which nothing else reports; the
   * amendment records the disagreement and overwrites both rather than refusing
   * and leaving it unfixable.
   */
  representationsAgree: boolean;
}

/** Exactly what an amendment will write, and what it replaces. */
export interface ShiftSummaryAmendment {
  shiftId: string;
  businessDate: string;
  staffId: string;
  expectationId: string;
  generation: string;

  /** The recorded difference this amendment resolves, if one was listed. */
  anomalyId: string;

  previousTotalSales: number;
  previousTotalSalesMinor: number;
  previousTransactionCount: number;
  previousRepresentationsAgreed: boolean;

  totalSales: number;
  totalSalesMinor: number;
  transactionCount: number;

  /** Observed minus expected, the same direction the verifier records. */
  salesVarianceMinor: number;
  transactionVariance: number;
}

function safeNonNegativeInteger(value: unknown, maximum: number): number | undefined {
  return Number.isSafeInteger(value) && (value as number) >= 0 &&
    (value as number) <= maximum ? value as number : undefined;
}

function finiteNonNegativeNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ?
    value : undefined;
}

/** Minor units, or undefined when the amount is outside the supported range. */
function boundedMinorUnits(value: number): number | undefined {
  let minorUnits: number;
  try {
    minorUnits = moneyToMinorUnits(value);
  } catch {
    return undefined;
  }
  return minorUnits >= 0 && minorUnits <= MAXIMUM_SHIFT_SALES_MINOR_UNITS ?
    minorUnits : undefined;
}

/**
 * Re-checks a stored field and reports a defect as stored state, not as input.
 *
 * `requireIsoDate` and `requireDocumentId` raise `invalid-argument`, which is
 * the right code for a caller's payload and the wrong one here: the caller named
 * a real shift and it is the document that is unusable. Keeping the two codes
 * apart is what lets a client tell "fix your request" from "this shift cannot be
 * amended".
 */
function storedField<T>(read: () => T, label: string): T {
  try {
    return read();
  } catch {
    throw new HttpsError(
      "failed-precondition",
      `The shift does not record a usable ${label}.`
    );
  }
}

function requireGeneration(value: unknown, label: string): string {
  if (
    typeof value !== "string" || value.length === 0 ||
    value.length > MAXIMUM_GENERATION_LENGTH
  ) {
    throw new HttpsError(
      "failed-precondition",
      `The recorded expectation has an unusable ${label}.`
    );
  }
  return value;
}

/**
 * Reads what a closed shift records about its own sales.
 *
 * Every refusal here is `failed-precondition` rather than `invalid-argument`:
 * the caller named a real shift, and it is the stored state that makes the
 * amendment impossible. The one exception is a shift that does not exist, which
 * is the caller naming nothing.
 */
export function readClosedShiftSummary(
  tenantId: string,
  shiftId: string,
  shift: ClosedShiftFields | undefined
): ObservedShiftSummary {
  if (!shift) {
    throw new HttpsError("not-found", "The shift does not exist in this business.");
  }
  if (shift.tenantId !== tenantId || shift.shiftId !== shiftId) {
    throw new HttpsError(
      "failed-precondition",
      "The shift does not repeat the identity it was addressed by."
    );
  }
  if (shift.status !== "closed") {
    throw new HttpsError(
      "failed-precondition",
      "Only a closed shift's summary may be amended."
    );
  }
  const businessDate = storedField(
    () => requireIsoDate(shift.businessDate, "businessDate"),
    "business date"
  );
  const staffId = storedField(
    () => requireDocumentId(shift.staffId, "staffId"),
    "cashier"
  );
  const totalSales = finiteNonNegativeNumber(shift.totalSales);
  const totalSalesMinor = safeNonNegativeInteger(
    shift.totalSalesMinor,
    MAXIMUM_SHIFT_SALES_MINOR_UNITS
  );
  const transactionCount = safeNonNegativeInteger(
    shift.transactionCount,
    Number.MAX_SAFE_INTEGER
  );
  const observedSalesMinor = totalSales === undefined ?
    undefined : boundedMinorUnits(totalSales);
  if (
    totalSales === undefined || totalSalesMinor === undefined ||
    transactionCount === undefined || observedSalesMinor === undefined
  ) {
    // This is the `invalid_or_missing_shift` case, which has no amendment path:
    // with no readable summary there is no difference to resolve, only a shift
    // that never recorded one.
    throw new HttpsError(
      "failed-precondition",
      "This shift did not record a readable summary, so there is no difference to resolve."
    );
  }
  return {
    businessDate,
    expectationId: shiftExpectationId(businessDate, shiftId),
    staffId,
    totalSales,
    totalSalesMinor,
    transactionCount,
    observedSalesMinor,
    representationsAgree: totalSalesMinor === observedSalesMinor,
  };
}

/**
 * Decides the one amendment a settled shift variance permits.
 *
 * The expectation must be the *settled* one for this exact shift: verification
 * finished, the generation it settled is the generation it still carries, and
 * the outcome it settled on was a variance. A pending, stale, matched, or
 * quarantined record is refused, because amending against a figure that is
 * about to be recomputed would write a total nothing has verified.
 */
export function planShiftSummaryAmendment(input: {
  tenantId: string;
  shiftId: string;
  shift: ClosedShiftFields | undefined;
  expectation: ShiftExpectationFields | undefined;
}): ShiftSummaryAmendment {
  const observed = readClosedShiftSummary(input.tenantId, input.shiftId, input.shift);
  const expectation = input.expectation;
  if (!expectation) {
    throw new HttpsError(
      "failed-precondition",
      "Reconciliation has not recorded what the sales prove this shift should hold."
    );
  }
  if (
    expectation.tenantId !== input.tenantId ||
    expectation.shiftId !== input.shiftId ||
    expectation.businessDate !== observed.businessDate
  ) {
    throw new HttpsError(
      "failed-precondition",
      "The recorded expectation describes another shift."
    );
  }
  if (expectation.needsVerification !== false) {
    throw new HttpsError(
      "failed-precondition",
      "This shift is still waiting to be re-checked against its sales."
    );
  }
  if (expectation.verificationStatus !== AMENDABLE_VERIFICATION_STATUS) {
    throw new HttpsError(
      "failed-precondition",
      "Only a shift reconciliation settled as a variance may be amended."
    );
  }
  const generation = requireGeneration(expectation.generation, "generation");
  if (requireGeneration(expectation.verifiedGeneration, "verifiedGeneration") !== generation) {
    throw new HttpsError(
      "failed-precondition",
      "The recorded variance was settled against an older generation of this shift's sales."
    );
  }
  const expectedSales = finiteNonNegativeNumber(expectation.sales);
  const expectedTransactions = safeNonNegativeInteger(
    expectation.transactions,
    Number.MAX_SAFE_INTEGER
  );
  const expectedSalesMinor = expectedSales === undefined ?
    undefined : boundedMinorUnits(expectedSales);
  if (
    expectedSales === undefined || expectedTransactions === undefined ||
    expectedSalesMinor === undefined
  ) {
    throw new HttpsError(
      "failed-precondition",
      "The sale-derived total for this shift could not be read."
    );
  }
  // Firestore Rules and the client history read model both refuse a summary
  // that records takings over no transactions, so writing one would leave a
  // shift no device can display.
  if (expectedSalesMinor > 0 && expectedTransactions === 0) {
    throw new HttpsError(
      "failed-precondition",
      "The sale-derived total for this shift is not a summary a shift may hold."
    );
  }
  // This is the verifier's own comparison, asked again on the same two figures.
  // Asking a different question would let this path amend a shift the verifier
  // would have called matched - and, in the other direction, would let a record
  // that contradicts the only code that could have written it be acted on.
  //
  // A shift whose stored minor units are broken while its major units are
  // correct is therefore not amendable here. That is a different defect from a
  // reconciliation variance, and inventing a second purpose for a governance
  // callable is worse than leaving it to be reported on its own terms.
  if (
    observed.observedSalesMinor === expectedSalesMinor &&
    observed.transactionCount === expectedTransactions
  ) {
    throw new HttpsError(
      "failed-precondition",
      "This shift's summary already matches the sales recorded against it."
    );
  }
  return {
    shiftId: input.shiftId,
    businessDate: observed.businessDate,
    staffId: observed.staffId,
    expectationId: observed.expectationId,
    generation,
    anomalyId: shiftAnomalyId(input.shiftId, generation),
    previousTotalSales: observed.totalSales,
    previousTotalSalesMinor: observed.totalSalesMinor,
    previousTransactionCount: observed.transactionCount,
    previousRepresentationsAgreed: observed.representationsAgree,
    totalSales: minorUnitsToMoney(expectedSalesMinor),
    totalSalesMinor: expectedSalesMinor,
    transactionCount: expectedTransactions,
    salesVarianceMinor: observed.observedSalesMinor - expectedSalesMinor,
    transactionVariance: observed.transactionCount - expectedTransactions,
  };
}

/**
 * Whether a listed difference is the one this amendment resolves.
 *
 * The anomaly is addressed by a digest of the shift and generation, so a record
 * at that ID naming anything else is corruption rather than this shift's
 * difference. Clearing it would delete evidence about something else, so it is
 * left exactly where it is and the amendment records that it cleared nothing.
 */
export function clearsRecordedAnomaly(
  amendment: ShiftSummaryAmendment,
  anomaly: {tenantId?: unknown; shiftId?: unknown; anomalyType?: unknown} | undefined,
  tenantId: string
): boolean {
  return anomaly !== undefined &&
    anomaly.tenantId === tenantId &&
    anomaly.shiftId === amendment.shiftId &&
    anomaly.anomalyType === "shift_variance";
}
