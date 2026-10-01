import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {requireDocumentId, requireString} from "../core/validation";
import {readSaleCredit} from "../customers/credit";

export const STOCK_ADJUSTMENT_TYPES = [
  "restock",
  "opening_balance",
  "inventory_count",
  "correction",
  "damage",
  "waste",
] as const;

export type StockAdjustmentType = (typeof STOCK_ADJUSTMENT_TYPES)[number];

export interface ReturnStockLine {
  productId: string;
  quantity: number;
}

export interface SaleLineLike {
  productId?: unknown;
  categoryId?: unknown;
  quantity?: unknown;
  unitPrice?: unknown;
  unitPriceMinor?: unknown;
  lineTotal?: unknown;
  lineTotalMinor?: unknown;
  total?: unknown;
  unitCost?: unknown;
  unitCostMinor?: unknown;
  cost?: unknown;
  costMinor?: unknown;
}

export interface SaleLike {
  /**
   * The sale's own document id, set by the caller from the snapshot.
   *
   * Read rather than inferred from `checkoutId`, because an imported sale may
   * not carry one and the join below has to key on something that always
   * exists.
   */
  saleId?: unknown;
  total?: unknown;
  subtotal?: unknown;
  subtotalMinor?: unknown;
  discount?: unknown;
  discountMinor?: unknown;
  totalMinor?: unknown;
  soldById?: unknown;
  shiftId?: unknown;
  tender?: unknown;
  items?: unknown;
  creditOwedMinor?: unknown;
  creditPaidTender?: unknown;
}

/** Units returned against one sale, by product id. */
export type ReturnedUnits = ReadonlyMap<string, number>;

/** Every sale a period's returns touched, keyed by sale document id. */
export type PeriodReturns = ReadonlyMap<string, ReturnedUnits>;

export interface PeriodMetrics {
  sales: number;
  profit: number;
  transactions: number;
  incompleteCostLineCount: number;
}

/** The exact values Firestore Rules allow a schema v2 sale to record. */
export const SALE_TENDERS = ["cash", "mpesa", "card"] as const;

export type SaleTender = (typeof SALE_TENDERS)[number];

/**
 * The buckets a period's takings are split into.
 *
 * `unrecorded` and `other` are separate on purpose, because they are different
 * facts. A sale with no `tender` at all is a schema v1 sale written before the
 * field existed, which says nothing about how it was paid for. A sale carrying
 * a value this system does not model - an import, a rule rollback - means
 * something wrote a tender nothing here recognises, which is a data problem.
 * Folding the second into the first would report a defect as history.
 */
export const TENDER_BUCKETS = [
  ...SALE_TENDERS,
  "unrecorded",
  "other",
] as const;

export type SaleTenderBucket = (typeof TENDER_BUCKETS)[number];

export interface TenderTotals {
  sales: number;
  transactions: number;
}

export type TenderBreakdown = Record<SaleTenderBucket, TenderTotals>;

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
const MAX_RETURN_LINES = 50;
const MAX_QUANTITY_DELTA = 1_000_000;
const MAX_MONETARY_VALUE = 1_000_000_000_000;

function finiteNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function nonNegativeNumber(value: unknown): number | undefined {
  const parsed = finiteNumber(value);
  return parsed !== undefined && parsed >= 0 && parsed <= MAX_MONETARY_VALUE ?
    parsed : undefined;
}

export function moneyToMinorUnits(value: number): number {
  if (!Number.isFinite(value) || Math.abs(value) > MAX_MONETARY_VALUE) {
    throw new HttpsError("failed-precondition", "A stored monetary amount is out of range.");
  }
  const minorUnits = Math.round((value + Math.sign(value) * Number.EPSILON) * 100);
  if (!Number.isSafeInteger(minorUnits)) {
    throw new HttpsError("failed-precondition", "A stored monetary amount is not safely representable.");
  }
  return minorUnits;
}

export function minorUnitsToMoney(value: number): number {
  if (!Number.isSafeInteger(value)) {
    throw new HttpsError("failed-precondition", "A monetary aggregate is not safely representable.");
  }
  return value / 100;
}

function addMonetaryValue(current: number, addition: number): number {
  const nextMinorUnits = moneyToMinorUnits(current) + moneyToMinorUnits(addition);
  if (!Number.isSafeInteger(nextMinorUnits)) {
    throw new HttpsError(
      "failed-precondition",
      "Stored sale amounts exceed the supported aggregation range."
    );
  }
  return minorUnitsToMoney(nextMinorUnits);
}

export function requireQuantityDelta(value: unknown): number {
  if (
    !Number.isSafeInteger(value) ||
    value === 0 ||
    Math.abs(value as number) > MAX_QUANTITY_DELTA
  ) {
    throw new HttpsError(
      "invalid-argument",
      `quantityDelta must be a non-zero integer between -${MAX_QUANTITY_DELTA} and ${MAX_QUANTITY_DELTA}.`
    );
  }
  return value as number;
}

export function requireStockAdjustmentType(value: unknown): StockAdjustmentType {
  if (
    typeof value !== "string" ||
    !STOCK_ADJUSTMENT_TYPES.includes(value as StockAdjustmentType)
  ) {
    throw new HttpsError("invalid-argument", "type is not a supported stock adjustment type.");
  }
  return value as StockAdjustmentType;
}

export function assertAdjustmentDirection(
  type: StockAdjustmentType,
  quantityDelta: number
): void {
  if ((type === "restock" || type === "opening_balance") && quantityDelta < 0) {
    throw new HttpsError("invalid-argument", `${type} requires a positive quantityDelta.`);
  }
  if ((type === "damage" || type === "waste") && quantityDelta > 0) {
    throw new HttpsError("invalid-argument", `${type} requires a negative quantityDelta.`);
  }
}

export function requireStoredQuantity(value: unknown, field = "product quantity"): number {
  if (!Number.isSafeInteger(value)) {
    throw new HttpsError("failed-precondition", `${field} is not a valid integer.`);
  }
  return value as number;
}

export function addStockQuantity(current: number, delta: number): number {
  const next = current + delta;
  if (!Number.isSafeInteger(next)) {
    throw new HttpsError("out-of-range", "The resulting product quantity is outside the safe range.");
  }
  return next;
}

export function normalizeReason(value: unknown): string {
  const reason = requireString(value, "reason", {minLength: 3, maxLength: 500})
    .replace(/\s+/g, " ");
  if (/\p{Cc}/u.test(reason)) {
    throw new HttpsError("invalid-argument", "reason contains unsupported characters.");
  }
  return reason;
}

function readReturnLine(value: unknown, index: number): ReturnStockLine {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("failed-precondition", `Return item ${index} is invalid.`);
  }
  const item = value as Record<string, unknown>;
  const productId = requireDocumentId(item.productId, `itemsReturned[${index}].productId`);
  const quantity = item.quantity;
  if (!Number.isSafeInteger(quantity) || (quantity as number) <= 0 || (quantity as number) > MAX_QUANTITY_DELTA) {
    throw new HttpsError(
      "failed-precondition",
      `Return item ${index} has an invalid quantity.`
    );
  }
  return {productId, quantity: quantity as number};
}

/** Combines duplicate products so each product is updated exactly once. */
export function normalizeReturnStockLines(value: unknown): ReturnStockLine[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_RETURN_LINES) {
    throw new HttpsError(
      "failed-precondition",
      `itemsReturned must contain between 1 and ${MAX_RETURN_LINES} items.`
    );
  }
  const combined = new Map<string, number>();
  value.forEach((item, index) => {
    const line = readReturnLine(item, index);
    const next = (combined.get(line.productId) ?? 0) + line.quantity;
    if (!Number.isSafeInteger(next) || next > MAX_QUANTITY_DELTA) {
      throw new HttpsError("failed-precondition", "A returned product quantity is too large.");
    }
    combined.set(line.productId, next);
  });
  return [...combined.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([productId, quantity]) => ({productId, quantity}));
}

/** Ensures verified returns can never restore more than the immutable sale sold. */
export function assertReturnWithinSale(
  soldLines: readonly ReturnStockLine[],
  requestedLines: readonly ReturnStockLine[],
  previouslyRestoredLines: readonly ReturnStockLine[]
): void {
  const sold = new Map(soldLines.map((line) => [line.productId, line.quantity]));
  const restored = new Map<string, number>();
  for (const line of previouslyRestoredLines) {
    const next = (restored.get(line.productId) ?? 0) + line.quantity;
    if (!Number.isSafeInteger(next) || next < 0) {
      throw new HttpsError("data-loss", "Prior return verification quantities are invalid.");
    }
    restored.set(line.productId, next);
  }
  for (const line of requestedLines) {
    const soldQuantity = sold.get(line.productId);
    const priorQuantity = restored.get(line.productId) ?? 0;
    if (soldQuantity === undefined || priorQuantity + line.quantity > soldQuantity) {
      throw new HttpsError(
        "failed-precondition",
        `The return quantity for product ${line.productId} exceeds the immutable sale.`
      );
    }
  }
}

export function requireIsoDate(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must use yyyy-MM-dd format.`);
  }
  const match = ISO_DATE.exec(value);
  if (!match) {
    throw new HttpsError("invalid-argument", `${field} must use yyyy-MM-dd format.`);
  }
  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  if (date.toISOString().slice(0, 10) !== value) {
    throw new HttpsError("invalid-argument", `${field} is not a calendar date.`);
  }
  return value;
}

export function assertDateRange(start: string, end: string, maximumDays = 366): void {
  if (start > end) {
    throw new HttpsError("invalid-argument", "previousStartDate must not be after previousEndDate.");
  }
  const elapsedDays = Math.floor(
    (Date.parse(`${end}T00:00:00.000Z`) - Date.parse(`${start}T00:00:00.000Z`)) /
    86_400_000
  ) + 1;
  if (elapsedDays > maximumDays) {
    throw new HttpsError(
      "invalid-argument",
      `The comparison period cannot exceed ${maximumDays} days.`
    );
  }
}

function lineQuantity(line: SaleLineLike): number | undefined {
  const quantity = finiteNumber(line.quantity);
  return quantity !== undefined && Number.isSafeInteger(quantity) && quantity > 0 ?
    quantity : undefined;
}

function lineRevenue(line: SaleLineLike, quantity: number): number | undefined {
  return nonNegativeNumber(line.lineTotal) ??
    nonNegativeNumber(line.total) ??
    (() => {
      const unitPrice = nonNegativeNumber(line.unitPrice);
      if (unitPrice === undefined) return undefined;
      const total = unitPrice * quantity;
      return Number.isFinite(total) && total <= MAX_MONETARY_VALUE ? total : undefined;
    })();
}

function lineCost(line: SaleLineLike, quantity: number): number | undefined {
  const explicitCost = nonNegativeNumber(line.cost);
  if (explicitCost !== undefined) return explicitCost;
  const unitCost = nonNegativeNumber(line.unitCost);
  if (unitCost === undefined) return undefined;
  const total = unitCost * quantity;
  return Number.isFinite(total) && total <= MAX_MONETARY_VALUE ? total : undefined;
}

/**
 * What one sale's returns take back out of it.
 *
 * **A port of `lib/returns/return_offsets.dart`, and it has to answer
 * identically.** The same period is read online through this and offline
 * through that one, and two implementations of one money rule will drift
 * unless they are pinned - `test/fixtures/return_offset_vectors.json` is run
 * from both sides for exactly that reason.
 *
 * Three details are copied rather than paraphrased:
 *
 * - **`grossMinor * (totalMinor / subtotalMinor)` divides first.** The other
 *   grouping is a different binary64 result on some inputs, and the two
 *   languages would then disagree about real money.
 * - **`Math.round`, not `moneyToMinorUnits`.** That helper nudges by
 *   `Number.EPSILON` before rounding and Dart's `.round()` does not. On a
 *   non-negative value plain `Math.round` is exactly Dart's half-up.
 * - **The zero-discount short circuit and the clamp are behaviour**, not
 *   defensive padding.
 */
export interface SaleReturnOffset {
  /** Revenue to take out, in minor units. */
  revenueMinor: number;
  /** Cost of the returned goods, in minor units. Never discount-adjusted. */
  costMinor: number;
  /**
   * How many lines carrying no cost have come back in full.
   *
   * **A period subtracts this from its incomplete-cost count.** A costless
   * line entirely returned contributes no revenue and no cost to the net
   * figures, so its missing cost cannot move net profit - and going on
   * withholding the margin over it would let a customer undo a sale and leave
   * the report unable to state a profit about goods nobody has. A line still
   * partly sold is not counted: some of its cost is genuinely unknown.
   */
  fullyReturnedCostlessLines: number;
  /** Whether every unit of every line in scope has come back. */
  fullyReturned: boolean;
}

const EMPTY_OFFSET: SaleReturnOffset = {
  revenueMinor: 0,
  costMinor: 0,
  fullyReturnedCostlessLines: 0,
  fullyReturned: false,
};

/** A stored minor-unit integer, or the major-unit mirror converted. */
function minorField(
  minor: unknown,
  major: unknown
): number | undefined {
  const stored = finiteNumber(minor);
  if (stored !== undefined && Number.isSafeInteger(stored)) return stored;
  const mirror = finiteNumber(major);
  return mirror === undefined ? undefined : moneyToMinorUnits(mirror);
}

/**
 * Prices [returned] against the sale it came out of.
 *
 * `categoryId` narrows it to one category's lines, and changes the basis with
 * it: a whole-sale figure is the recorded total minus a whole-sale discount,
 * while a category figure is the sum of its own line totals gross of that
 * discount - which is what [saleContribution] itself does. Pro-rating a
 * category's returns against the whole sale's discount would take back money
 * the category was never credited with.
 */
export function describeSaleReturn(
  sale: SaleLike,
  returned: ReturnedUnits | undefined,
  categoryId?: string
): SaleReturnOffset {
  if (returned === undefined || returned.size === 0) return EMPTY_OFFSET;
  const lines = Array.isArray(sale.items) ? sale.items as SaleLineLike[] : [];
  const sold = new Set<string>();
  for (const line of lines) {
    const productId = typeof line.productId === "string" ? line.productId : undefined;
    if (productId !== undefined) sold.add(productId);
  }
  for (const [productId, units] of returned) {
    if (units <= 0) continue;
    // A return naming a product the sale never sold cannot be valued at all,
    // and would silently take nothing off a total it claims to reduce.
    if (!sold.has(productId)) {
      throw new HttpsError(
        "failed-precondition",
        `A return names product ${productId}, which its sale did not sell.`
      );
    }
  }

  // Every line is checked for an impossible quantity whatever the scope: a
  // malformed return is malformed in every report that reads it.
  for (const line of lines) {
    const quantity = lineQuantity(line);
    if (quantity === undefined) continue;
    const productId = typeof line.productId === "string" ? line.productId : undefined;
    const back = productId === undefined ? 0 : returned.get(productId) ?? 0;
    if (back > quantity) {
      throw new HttpsError(
        "failed-precondition",
        `A return takes back more of ${productId} than its sale sold.`
      );
    }
  }

  const scoped = categoryId === undefined ?
    lines :
    lines.filter((line) => line.categoryId === categoryId);

  let grossMinor = 0;
  let costMinor = 0;
  let costlessLinesFullyBack = 0;
  let fullyReturned = scoped.length > 0;
  for (const line of scoped) {
    const quantity = lineQuantity(line);
    if (quantity === undefined) continue;
    const productId = typeof line.productId === "string" ? line.productId : undefined;
    const back = productId === undefined ? 0 : returned.get(productId) ?? 0;
    if (back < quantity) fullyReturned = false;
    if (back === 0) continue;
    // **Per unit, exactly as `describeReturnOffset` does it.** The Dart
    // decoder refuses a line whose `lineTotalMinor` is not
    // `unitPriceMinor * quantity`, so on any sale this till wrote the two
    // bases agree - but an imported sale need not have gone through it, and
    // the two languages must not pick different halves of that disagreement.
    const unitPriceMinor = minorField(line.unitPriceMinor, line.unitPrice);
    if (unitPriceMinor !== undefined) grossMinor += unitPriceMinor * back;
    // A returned line with no recorded cost takes no cost back out, which is
    // consistent rather than incomplete: it put none in either. Whether the
    // *period* can still state a profit is `saleContribution`'s question, and
    // it asks it per line rather than from a flag here.
    const unitCostMinor = minorField(line.unitCostMinor, line.unitCost);
    if (unitCostMinor !== undefined) costMinor += unitCostMinor * back;
    else if (back >= quantity) costlessLinesFullyBack += 1;
  }

  return {
    revenueMinor: categoryId === undefined ?
      wholeSaleReturnMinor(sale, grossMinor, fullyReturned) :
      grossMinor,
    costMinor,
    fullyReturnedCostlessLines: costlessLinesFullyBack,
    fullyReturned,
  };
}

/** The returned share of what was actually charged. */
function wholeSaleReturnMinor(
  sale: SaleLike,
  grossMinor: number,
  complete: boolean
): number {
  const totalMinor = minorField(sale.totalMinor, sale.total) ?? 0;
  if (complete) return totalMinor;
  const subtotalMinor = minorField(sale.subtotalMinor, sale.subtotal) ?? 0;
  if (grossMinor <= 0 || subtotalMinor <= 0) return 0;
  // An imported sale with no discount basis pro-rates to the gross, clamped.
  const discountMinor = minorField(sale.discountMinor, sale.discount) ?? 0;
  if (discountMinor === 0) return grossMinor;
  const share = grossMinor * (totalMinor / subtotalMinor);
  return Math.min(Math.max(Math.round(share), 0), totalMinor);
}

interface SaleContribution {
  /** False only when a category was requested and this sale holds no line in it. */
  counted: boolean;
  revenue: number;
  cost: number;
  incompleteCostLines: number;
}

/**
 * What exactly one sale contributes to a period.
 *
 * This is the single definition of that, so an aggregate and any split of the
 * same sales agree by construction rather than by two implementations staying
 * in step.
 */
function saleContribution(
  sale: SaleLike,
  categoryId?: string,
  returned?: ReturnedUnits
): SaleContribution {
  const lines = Array.isArray(sale.items) ? sale.items as SaleLineLike[] : [];
  const selected = categoryId ?
    lines.filter((line) => line.categoryId === categoryId) :
    lines;
  if (categoryId && selected.length === 0) {
    return {counted: false, revenue: 0, cost: 0, incompleteCostLines: 0};
  }

  // **Netted here rather than outside `aggregateSales`, and that is the whole
  // reason this function exists.** An aggregate and any split of the same
  // sales have to agree by construction; subtracting returns from one of them
  // afterwards is the second implementation this was extracted to prevent.
  const offset = describeSaleReturn(sale, returned, categoryId);
  // A sale returned in full is not a transaction that happened. It also stops
  // reporting cost completeness - it contributed nothing to have cost.
  if (offset.fullyReturned) {
    return {counted: false, revenue: 0, cost: 0, incompleteCostLines: 0};
  }

  let lineRevenueTotal = 0;
  let hasLineRevenue = false;
  let cost = 0;
  let incompleteCostLines = 0;
  for (const line of selected) {
    const quantity = lineQuantity(line);
    if (quantity === undefined) continue;
    const lineRevenueValue = lineRevenue(line, quantity);
    if (lineRevenueValue !== undefined) {
      lineRevenueTotal = addMonetaryValue(lineRevenueTotal, lineRevenueValue);
      hasLineRevenue = true;
    }
    const lineCostValue = lineCost(line, quantity);
    if (lineCostValue === undefined) incompleteCostLines += 1;
    else cost = addMonetaryValue(cost, lineCostValue);
  }
  // **Lines that came back in full stop making the basis incomplete.**
  // Counted once, in the shared arithmetic, so the device aggregator applies
  // the identical rule rather than a second reading of it - and so the rule
  // is covered by the golden vectors both sides run.
  //
  // The gross pass has no returns, so its count is zero and the gross basis
  // keeps every costless line exactly as it always did. That is right too:
  // the goods *were* sold, and gross profit over them is unknowable.
  incompleteCostLines = Math.max(
    incompleteCostLines - offset.fullyReturnedCostlessLines,
    0
  );

  const recordedTotal = nonNegativeNumber(sale.total);
  const grossRevenue = categoryId ?
    lineRevenueTotal :
    recordedTotal ?? (hasLineRevenue ? lineRevenueTotal : 0);
  // Whole minor units on both sides, so the subtraction is exact and a netted
  // period's tender split still sums to its total by integer arithmetic.
  //
  // **Cost comes back too.** Revenue netted on its own drives the derived cost
  // (takings minus profit) down and, on a low-margin period with a large
  // return, negative - which `TenantProfitReport` reads as an impossible
  // figure and withholds the margin for. A returned line that carried no cost
  // is already counted in `incompleteCostLines` above, by the same line.
  const netRevenueMinor = Math.max(
    moneyToMinorUnits(grossRevenue) - offset.revenueMinor,
    0
  );
  const netCostMinor = Math.max(moneyToMinorUnits(cost) - offset.costMinor, 0);
  return {
    counted: true,
    revenue: minorUnitsToMoney(netRevenueMinor),
    cost: minorUnitsToMoney(netCostMinor),
    incompleteCostLines,
  };
}

/**
 * What came back out of one sale, from a period's returns.
 *
 * **A return whose sale is not in `sales` is not this period's**, and skipping
 * it is what scopes the join for free. `firestore.rules` binds a return's
 * `businessDate` to its sale's, so every return in a date window has its sale
 * in the same window - which means a miss here is a sale another filter
 * excluded, most often another cashier's.
 */
function saleReturns(
  sale: SaleLike,
  returns: PeriodReturns | undefined
): ReturnedUnits | undefined {
  if (returns === undefined) return undefined;
  const saleId = typeof sale.saleId === "string" ? sale.saleId : undefined;
  return saleId === undefined ? undefined : returns.get(saleId);
}

/**
 * Aggregates immutable sale snapshots. Category comparisons include only matching
 * lines; unfiltered comparisons prefer the server-recorded transaction total.
 */
export function aggregateSales(
  sales: readonly SaleLike[],
  categoryId?: string,
  returns?: PeriodReturns
): PeriodMetrics {
  let revenue = 0;
  let cost = 0;
  let transactions = 0;
  let incompleteCostLineCount = 0;

  for (const sale of sales) {
    const contribution = saleContribution(sale, categoryId, saleReturns(sale, returns));
    if (!contribution.counted) continue;
    revenue = addMonetaryValue(revenue, contribution.revenue);
    cost = addMonetaryValue(cost, contribution.cost);
    incompleteCostLineCount += contribution.incompleteCostLines;
    transactions += 1;
  }

  return {
    sales: revenue,
    profit: minorUnitsToMoney(moneyToMinorUnits(revenue) - moneyToMinorUnits(cost)),
    transactions,
    incompleteCostLineCount,
  };
}

/** Which bucket one stored `tender` value belongs to. Nothing is coerced. */
export function saleTenderBucket(value: unknown): SaleTenderBucket {
  if (value === undefined || value === null) return "unrecorded";
  return (SALE_TENDERS as readonly unknown[]).includes(value) ?
    value as SaleTender :
    "other";
}

export function emptyTenderBreakdown(): TenderBreakdown {
  const breakdown = {} as TenderBreakdown;
  for (const bucket of TENDER_BUCKETS) {
    breakdown[bucket] = {sales: 0, transactions: 0};
  }
  return breakdown;
}

/**
 * Splits the same sales `aggregateSales` totals by how they were paid for.
 *
 * Every bucket is filled from [saleContribution], and a sale skipped by a
 * category filter is skipped here too, so the buckets sum exactly to the
 * aggregate over the same arguments. That is arithmetic rather than
 * coincidence: money is added in whole minor units, and integer addition does
 * not care how it is grouped.
 */
export function aggregateSalesByTender(
  sales: readonly SaleLike[],
  categoryId?: string,
  returns?: PeriodReturns
): TenderBreakdown {
  const breakdown = emptyTenderBreakdown();
  for (const sale of sales) {
    const contribution = saleContribution(sale, categoryId, saleReturns(sale, returns));
    if (!contribution.counted) continue;
    const credit = readSaleCredit(sale as Record<string, unknown>);
    if (credit !== null) {
      // **A credit sale is split, not moved.** What was paid at the counter is
      // paid-by money like any other sale's; what was left owing is in
      // `other`, the bucket for takings no payment method accounts for, which
      // keeps the bucket set every installed build decodes. The split follows
      // the sale's own owed share, so a partly returned sale splits what is
      // left of it the same way.
      const revenueMinor = moneyToMinorUnits(contribution.revenue);
      const owedShare = Math.round(
        revenueMinor * credit.owedMinor / (credit.owedMinor + credit.paidMinor)
      );
      const owedTotals = breakdown.other;
      owedTotals.sales = addMonetaryValue(owedTotals.sales, minorUnitsToMoney(owedShare));
      owedTotals.transactions += 1;
      if (credit.paidTender !== null) {
        const paidTotals = breakdown[credit.paidTender];
        paidTotals.sales = addMonetaryValue(
          paidTotals.sales,
          minorUnitsToMoney(revenueMinor - owedShare)
        );
      }
      continue;
    }
    const totals = breakdown[saleTenderBucket(sale.tender)];
    totals.sales = addMonetaryValue(totals.sales, contribution.revenue);
    totals.transactions += 1;
  }
  return breakdown;
}

export function immutableLedgerId(parts: readonly string[]): string {
  return createHash("sha256")
    .update(parts.join("\u0000"))
    .digest("hex")
    .slice(0, 40);
}
