import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {requireDocumentId, requireString} from "../core/validation";

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
  price?: unknown;
  unitPrice?: unknown;
  lineTotal?: unknown;
  total?: unknown;
  buyingPrice?: unknown;
  unitCost?: unknown;
  cost?: unknown;
}

export interface SaleLike {
  total?: unknown;
  totalAmount?: unknown;
  soldById?: unknown;
  shiftId?: unknown;
  tender?: unknown;
  items?: unknown;
}

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
  const productId = requireDocumentId(item.productId ?? item.itemId, `itemsReturned[${index}].productId`);
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
      const unitPrice = nonNegativeNumber(line.unitPrice) ?? nonNegativeNumber(line.price);
      if (unitPrice === undefined) return undefined;
      const total = unitPrice * quantity;
      return Number.isFinite(total) && total <= MAX_MONETARY_VALUE ? total : undefined;
    })();
}

function lineCost(line: SaleLineLike, quantity: number): number | undefined {
  const explicitCost = nonNegativeNumber(line.cost);
  if (explicitCost !== undefined) return explicitCost;
  const unitCost = nonNegativeNumber(line.unitCost) ?? nonNegativeNumber(line.buyingPrice);
  if (unitCost === undefined) return undefined;
  const total = unitCost * quantity;
  return Number.isFinite(total) && total <= MAX_MONETARY_VALUE ? total : undefined;
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
  categoryId?: string
): SaleContribution {
  const lines = Array.isArray(sale.items) ? sale.items as SaleLineLike[] : [];
  const selected = categoryId ?
    lines.filter((line) => line.categoryId === categoryId) :
    lines;
  if (categoryId && selected.length === 0) {
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

  const recordedTotal = nonNegativeNumber(sale.total) ?? nonNegativeNumber(sale.totalAmount);
  return {
    counted: true,
    revenue: categoryId ?
      lineRevenueTotal :
      recordedTotal ?? (hasLineRevenue ? lineRevenueTotal : 0),
    cost,
    incompleteCostLines,
  };
}

/**
 * Aggregates immutable sale snapshots. Category comparisons include only matching
 * lines; unfiltered comparisons prefer the server-recorded transaction total.
 */
export function aggregateSales(
  sales: readonly SaleLike[],
  categoryId?: string
): PeriodMetrics {
  let revenue = 0;
  let cost = 0;
  let transactions = 0;
  let incompleteCostLineCount = 0;

  for (const sale of sales) {
    const contribution = saleContribution(sale, categoryId);
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
  categoryId?: string
): TenderBreakdown {
  const breakdown = emptyTenderBreakdown();
  for (const sale of sales) {
    const contribution = saleContribution(sale, categoryId);
    if (!contribution.counted) continue;
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
