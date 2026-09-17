import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {
  PeriodMetrics,
  SaleLike,
  aggregateSales,
  minorUnitsToMoney,
  moneyToMinorUnits,
  requireIsoDate,
  saleTenderBucket,
} from "../operations/domain";

export const RECONCILIATION_JOB_PHASES = [
  "metrics",
  "stock",
  "shifts",
  "finalize",
] as const;
export type ReconciliationJobPhase = (typeof RECONCILIATION_JOB_PHASES)[number];

export const RECONCILIATION_JOB_STATUSES = [
  "queued",
  "running",
  "failed",
  "completed",
  "quarantined",
] as const;
export type ReconciliationJobStatus = (typeof RECONCILIATION_JOB_STATUSES)[number];

export type ReconciliationMode = "incremental" | "full";
export type ReconciliationCheckpointKind = "none" | "weekly" | "monthly" | "manual";
export type ReconciliationSweepKind = "nightly" | "weekly" | "monthly";

export interface ReconciliationTaskPayload {
  tenantId: string;
  jobId: string;
  generation: number;
  revision: number;
}

export interface TenantDiscoveryTaskPayload {
  runId: string;
  kind: ReconciliationSweepKind;
  localDate: string;
  page: number;
  cursor?: string;
}

export interface DirtyJobInput {
  status: ReconciliationJobStatus;
  phase: ReconciliationJobPhase;
  generation: number;
  revision: number;
  rerunRequested: boolean;
}

export interface DirtyJobDecision extends DirtyJobInput {
  enqueue: boolean;
}

export interface DailyMetrics extends PeriodMetrics {
  businessDate: string;
  transactionCount: number;
  shiftCount: number;
}

/**
 * What one shift's sales say it took, split by how they were paid for.
 *
 * **Minor units, unlike every other figure on `ShiftAggregate`.** The cashier's
 * declaration is recorded in minor units, and this is the side of the
 * comparison that has a choice: carrying major units here would put a
 * `moneyToMinorUnits` round-trip between the sales and the figure they are
 * measured against, which is exactly the imprecision the sales check already
 * inherits by reading `totalSales` rather than `totalSalesMinor`.
 *
 * `unattributed` folds `unrecorded` and `other` together. They are different
 * facts about a sale - one predates the tender field, the other names a method
 * this system does not model - but a drawer declaration has no box for either,
 * so to this comparison they are one figure. It is carried rather than dropped
 * so a split that does not sum to the shift total can say why.
 */
export interface ShiftTenderAggregate {
  cashMinor: number;
  mpesaMinor: number;
  cardMinor: number;
  unattributedMinor: number;
}

export interface ShiftAggregate {
  shiftId: string;
  businessDate: string;
  sales: number;
  transactions: number;
  tenders: ShiftTenderAggregate;
}

export interface DailyAggregateResult {
  metrics: DailyMetrics;
  shifts: ShiftAggregate[];
}

export interface StockCheckpointInput {
  tenantId: string;
  productId: string;
  checkpointKey: string;
  expectedQuantity: number;
  observedQuantity: number;
  movementCursor: string;
  previousCheckpointHash?: string;
}

const DOCUMENT_SEGMENT = /^[^/]{1,128}$/;
const RUN_ID = /^rs_[a-f0-9]{40}$/;
const JOB_ID = /^(?:rj|dirty)_[A-Za-z0-9_-]{1,120}$/;

export function digest(parts: readonly string[], length = 40): string {
  return createHash("sha256").update(parts.join("\u0000")).digest("hex").slice(0, length);
}

export function reconciliationJobId(source: string, sourceKey: string): string {
  return `rj_${digest([source, sourceKey])}`;
}

/**
 * The `shift_expectations` document a business date and shift are addressed by.
 *
 * The metrics writer creates it, the shift verifier reads it, and the amendment
 * callable reads it to learn what the sales prove a closed shift should hold.
 * All three must agree on one definition or the amendment would correct a shift
 * against another shift's expectation, so this is the only one.
 */
export function shiftExpectationId(businessDate: string, shiftId: string): string {
  return `se_${digest([businessDate, shiftId])}`;
}

/**
 * The `reconciliation_anomalies` document one shift generation is recorded at.
 *
 * The verifier writes it when observed and expected disagree, and the amendment
 * callable clears exactly that record once the disagreement is resolved. A
 * second definition here would leave a resolved difference listed forever.
 */
export function shiftAnomalyId(shiftId: string, generation: string): string {
  return `shift_${digest([shiftId, generation])}`;
}

/**
 * The one `reconciliation_anomalies` document a shift's declaration is recorded
 * at.
 *
 * **Deliberately not keyed by generation, unlike [shiftAnomalyId].** A
 * declaration difference is a fact about one shift and one drawer, not about
 * one aggregation pass, so re-verifying the same unresolved difference must
 * update the record rather than mint a second one an owner would have to
 * dismiss twice. It is also what lets the verifier delete the record outright
 * once late sales bring the two sides into agreement.
 */
export function shiftTenderAnomalyId(shiftId: string): string {
  return `tender_${digest([shiftId])}`;
}

/**
 * The instant from which a close with no declaration is itself a difference.
 *
 * **Set to the planned end of the rollout, not to a deploy.** Before it, a
 * shift closed by a build that cannot declare is silent; after it, one is
 * `missing_tender_declaration`. Compared against the shift's `endTime`, which
 * the rules pin to `request.time` and a device therefore cannot choose - and
 * against the close rather than the business date, because a shift opened
 * offline last week is declared by whoever closes it today.
 */
export const TENDER_DECLARATION_REQUIRED_FROM = Date.UTC(2026, 8, 26);

export function reconciliationTaskId(payload: ReconciliationTaskPayload): string {
  return `rt_${digest([
    payload.tenantId,
    payload.jobId,
    `${payload.generation}`,
    `${payload.revision}`,
  ])}`;
}

export function sweepRunId(kind: ReconciliationSweepKind, localDate: string): string {
  return `rs_${digest([kind, localDate])}`;
}

export function discoveryTaskId(payload: TenantDiscoveryTaskPayload): string {
  return `rd_${digest([
    payload.runId,
    `${payload.page}`,
    payload.cursor ?? "",
  ])}`;
}

export function requireTaskPayload(payload: ReconciliationTaskPayload): void {
  if (
    !DOCUMENT_SEGMENT.test(payload.tenantId) ||
    !JOB_ID.test(payload.jobId) ||
    !Number.isSafeInteger(payload.generation) || payload.generation < 0 ||
    !Number.isSafeInteger(payload.revision) || payload.revision < 0
  ) {
    throw new HttpsError("invalid-argument", "Invalid reconciliation task payload.");
  }
}

export function requireDiscoveryPayload(payload: TenantDiscoveryTaskPayload): void {
  requireIsoDate(payload.localDate, "localDate");
  if (
    !RUN_ID.test(payload.runId) ||
    (payload.kind !== "nightly" && payload.kind !== "weekly" && payload.kind !== "monthly") ||
    !Number.isSafeInteger(payload.page) || payload.page < 0 || payload.page > 1_000_000 ||
    (payload.cursor !== undefined && !DOCUMENT_SEGMENT.test(payload.cursor)) ||
    payload.runId !== sweepRunId(payload.kind, payload.localDate)
  ) {
    throw new HttpsError("invalid-argument", "Invalid reconciliation discovery payload.");
  }
}

export function fiveMinuteBucket(instant: Date): number {
  const milliseconds = instant.getTime();
  if (!Number.isFinite(milliseconds)) {
    throw new HttpsError("invalid-argument", "The event time is invalid.");
  }
  return Math.floor(milliseconds / 300_000) * 300_000;
}

export function mergeDirtyJob(existing?: DirtyJobInput): DirtyJobDecision {
  if (!existing) {
    return {
      status: "queued",
      phase: "metrics",
      generation: 0,
      revision: 0,
      rerunRequested: false,
      enqueue: true,
    };
  }
  if (existing.status === "running") {
    return {...existing, rerunRequested: true, enqueue: false};
  }
  if (existing.status === "completed") {
    return {
      status: "queued",
      phase: "metrics",
      generation: existing.generation + 1,
      revision: existing.revision + 1,
      rerunRequested: false,
      enqueue: true,
    };
  }
  if (existing.status === "quarantined") {
    return {...existing, rerunRequested: true, enqueue: false};
  }
  return {
    ...existing,
    status: "queued",
    phase: "metrics",
    rerunRequested: existing.rerunRequested,
    enqueue: true,
  };
}

export function nairobiDate(instant: Date): string {
  const parts = Object.fromEntries(new Intl.DateTimeFormat("en-GB", {
    timeZone: "Africa/Nairobi",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(instant).map((part) => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}

export function trailingIsoDates(endDate: string, count: number): string[] {
  requireIsoDate(endDate, "endDate");
  if (!Number.isSafeInteger(count) || count < 1 || count > 35) {
    throw new HttpsError("invalid-argument", "The trailing date count must be between 1 and 35.");
  }
  const end = new Date(`${endDate}T00:00:00.000Z`);
  return Array.from({length: count}, (_, index) => {
    const day = new Date(end.getTime() - (count - index - 1) * 86_400_000);
    return day.toISOString().slice(0, 10);
  });
}

/** Stable days 1..28 make monthly work evenly staggered and calendar-safe. */
export function monthlyShardDay(tenantId: string): number {
  const prefix = digest([tenantId], 8);
  return (Number.parseInt(prefix, 16) % 28) + 1;
}

export function isoWeekKey(dateValue: string): string {
  requireIsoDate(dateValue, "date");
  const date = new Date(`${dateValue}T00:00:00.000Z`);
  const weekday = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - weekday);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((date.getTime() - yearStart.getTime()) / 86_400_000) + 1) / 7);
  return `${date.getUTCFullYear()}-W${`${week}`.padStart(2, "0")}`;
}

/**
 * Adds one sale's takings to the bucket its tender names.
 *
 * The bucket is chosen by `saleTenderBucket`, which is the same function the
 * period-wide breakdown uses and the same rule the device's own ledger applies,
 * so a sale can never land in one bucket here and another there.
 */
function addShiftTender(
  tenders: ShiftTenderAggregate,
  tender: unknown,
  totalMinor: number
): void {
  switch (saleTenderBucket(tender)) {
  case "cash":
    tenders.cashMinor += totalMinor;
    break;
  case "mpesa":
    tenders.mpesaMinor += totalMinor;
    break;
  case "card":
    tenders.cardMinor += totalMinor;
    break;
  default:
    tenders.unattributedMinor += totalMinor;
  }
}

function finiteNonNegative(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : 0;
}

/** Aggregates sale snapshots once and emits bounded shift expectations. */
export function aggregateDailySales(
  businessDate: string,
  sales: readonly SaleLike[],
  maximumShifts = 200
): DailyAggregateResult {
  requireIsoDate(businessDate, "businessDate");
  const shifts = new Map<string, ShiftAggregate>();
  for (const sale of sales) {
    const shiftId = typeof sale.shiftId === "string" ? sale.shiftId : undefined;
    if (!shiftId || !DOCUMENT_SEGMENT.test(shiftId)) continue;
    // `finiteNonNegative` answers 0 rather than undefined, so this was written
    // as a `??` chain that could never reach its second arm: a sale carrying
    // only `totalAmount` contributed nothing to its shift while `aggregateSales`
    // counted it in full, and the daily metric and the per-shift expectation
    // disagreed with no way to tell from either.
    const total = finiteNonNegative(sale.total ?? sale.totalAmount);
    const current = shifts.get(shiftId) ?? {
      shiftId,
      businessDate,
      sales: 0,
      transactions: 0,
      tenders: {cashMinor: 0, mpesaMinor: 0, cardMinor: 0, unattributedMinor: 0},
    };
    const totalMinor = moneyToMinorUnits(total);
    const nextSalesMinor = moneyToMinorUnits(current.sales) + totalMinor;
    if (!Number.isSafeInteger(nextSalesMinor)) {
      throw new HttpsError(
        "failed-precondition",
        `Business date ${businessDate} has an invalid shift sales total.`
      );
    }
    current.sales = minorUnitsToMoney(nextSalesMinor);
    current.transactions += 1;
    // **Bucketed here rather than by a second walk over the same sales.** A
    // separate pass would produce buckets that merely agree with the total;
    // adding the same validated figure in the same iteration makes them sum to
    // it, which is what lets a declaration be compared method by method.
    addShiftTender(current.tenders, sale.tender, totalMinor);
    shifts.set(shiftId, current);
    if (shifts.size > maximumShifts) {
      throw new HttpsError(
        "resource-exhausted",
        `Business date ${businessDate} exceeds the bounded shift aggregation limit.`
      );
    }
  }
  const period = aggregateSales(sales);
  const shiftValues = [...shifts.values()].sort((left, right) =>
    left.shiftId.localeCompare(right.shiftId)
  );
  return {
    metrics: {
      ...period,
      businessDate,
      transactionCount: period.transactions,
      shiftCount: shiftValues.length,
    },
    shifts: shiftValues,
  };
}

/**
 * What one product's stock comparison concluded, from the four facts that decide
 * it.
 *
 * Extracted from `reconcileProduct` because it is the whole of that decision and
 * none of the transaction around it, and because it is where a branch guarded by
 * a condition another line had already forced went unnoticed for as long as it
 * existed: an unreadable movement always invalidates the chain, the chain was
 * tested first, and so `invalid_stock_movement` could never be recorded.
 */
export interface StockComparisonFacts {
  /**
   * `verified` when the carried state was usable. Anything else names why a
   * baseline had to be established or re-established, and outranks everything
   * below: a run that had no trustworthy figure to compare against did not
   * compare anything.
   */
  baselineStatus: string;

  /** Whether the checkpoint behind this product recomputed to its stored hash. */
  chainValid: boolean;

  /** Movements in this product's ledger that could not be read at all. */
  invalidMovementCount: number;

  /** Observed minus expected. Zero means the two figures agree. */
  variance: number;
}

export interface StockComparisonOutcome {
  /** Recorded on the verification record and the carried state. */
  status: string;

  /**
   * The kind of difference to record, or undefined when there is nothing to
   * record. A run that found nothing wrong writes no difference at all.
   */
  anomalyType?: string;
}

/**
 * Names the most specific cause first, in both fields.
 *
 * A generic condition that a specific one implies will mask it forever, and the
 * symptom is a plausible-looking diagnosis pointing an operator at the wrong
 * evidence - a tamper-evident chain of checks rather than the one ledger row that
 * could not be read. The chain's own verdict is never lost: `chainValid` is
 * recorded beside this outcome either way.
 *
 * A quantity that agrees with a figure derived from evidence that did not verify
 * is deliberately **not** reported as `matched`. Nothing else in this codebase
 * records a check as passed while recording that its own evidence could not be
 * trusted.
 */
export function stockComparisonOutcome(
  facts: StockComparisonFacts
): StockComparisonOutcome {
  const status = facts.baselineStatus !== "verified" ? facts.baselineStatus :
    facts.invalidMovementCount > 0 ? "invalid_movements" :
    !facts.chainValid ? "checkpoint_chain_invalid" :
    facts.variance === 0 ? "matched" : "variance";
  // **Split by direction since 2026-09-17, and for one reason.** Every stock
  // disagreement was reported as `stock_variance`, so "the shelf holds three
  // fewer than anything accounts for" and "three more" reached a shopkeeper as
  // the same undifferentiated fact of a number being wrong. They are not the
  // same event and they do not have the same causes.
  //
  // **Short is the one that matters.** It is what a sale whose ledger entry
  // never landed looks like, and it is what a quantity lowered outside the app
  // looks like - `allow update` on `products` admits a strictly decreasing
  // quantity with no movement required, because the checkout decrement is still
  // written by the till. Neither is visible anywhere else in the system, and
  // both read the same way: units left, and nothing says why.
  //
  // **Over is rarer and points elsewhere.** No client write can produce it; the
  // rule permits only a decrease. Units the books hold that no movement put
  // there means the ledger is incomplete, not that the shelf is.
  const anomalyType = facts.invalidMovementCount > 0 ?
    "invalid_stock_movement" :
    !facts.chainValid ? "checkpoint_chain_invalid" :
    facts.variance < 0 ? "stock_short_of_ledger" :
    facts.variance > 0 ? "stock_over_ledger" : undefined;
  return anomalyType === undefined ? {status} : {status, anomalyType};
}

export function stockCheckpointHash(input: StockCheckpointInput): string {
  return digest([
    "stock-checkpoint-v1",
    input.tenantId,
    input.productId,
    input.checkpointKey,
    `${input.expectedQuantity}`,
    `${input.observedQuantity}`,
    input.movementCursor,
    input.previousCheckpointHash ?? "genesis",
  ], 64);
}

export function safeErrorCode(error: unknown): string {
  if (error && typeof error === "object" && "code" in error) {
    const code = (error as {code?: unknown}).code;
    if (typeof code === "string" && code.length > 0) return code.slice(0, 128);
    if (typeof code === "number" && Number.isFinite(code)) return `${code}`;
  }
  return "unknown";
}
