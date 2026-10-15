/**
 * One business date's sales, shaped for the daily WhatsApp report.
 *
 * Pure: the caller reads Firestore and passes plain objects, so this can be
 * tested without one.
 *
 * Quantities and line amounts are taken as the sale stores them. A split
 * payment on the till writes two sales whose item quantities are scaled by
 * `amount / total * lines`, so a split sale of several lines over-counts its
 * items here exactly as it does in the app's own reports; the day's total
 * comes from `totalAmount` and is unaffected.
 */

export interface SaleItemInput {
  productName?: unknown;
  name?: unknown;
  quantity?: unknown;
  price?: unknown;
  itemid?: unknown;
  /** The size (`375ml`), which tells apart products sharing a name. */
  sku?: unknown;
}

export interface SaleInput {
  totalAmount?: unknown;
  total?: unknown;
  payment?: unknown;
  soldBy?: unknown;
  shiftId?: unknown;
  items?: unknown;
  /** When the till wrote the sale; the hourly chart buckets by it. */
  dateAdded?: Date | null;
}

export interface ShiftInput {
  id: string;
  staffName?: unknown;
  status?: unknown;
  startTime?: Date | null;
  endTime?: Date | null;
}

export interface ProductInput {
  id: string;
  name?: unknown;
  category?: unknown;
}

export interface PaymentTotal {
  method: string;
  amount: number;
}

export interface ShiftTotal {
  staffName: string;
  startTime: Date | null;
  endTime: Date | null;
  open: boolean;
  saleCount: number;
  amount: number;
}

export interface ItemTotal {
  name: string;
  /** The size (`375ml`), or empty; shown after the name. */
  size: string;
  quantity: number;
  amount: number;
}

export interface CategoryTotal {
  name: string;
  quantity: number;
  amount: number;
  items: ItemTotal[];
}

/** One clock hour's sales; [start] is on the hour. */
export interface HourTotal {
  start: Date;
  amount: number;
  count: number;
}

export interface DayReport {
  businessDate: string;
  totalSales: number;
  saleCount: number;
  itemsSold: number;
  /** Every hour from the first sale's to the last's, empty hours included. */
  hourly: HourTotal[];
  firstSaleAt: Date | null;
  lastSaleAt: Date | null;
  payments: PaymentTotal[];
  shifts: ShiftTotal[];
  openShifts: string[];
  categories: CategoryTotal[];
}

export const OTHER_CATEGORY = "Other";

export const HOUR_MS = 60 * 60 * 1000;

/** The order the till lists its payment methods in; anything else follows. */
const PAYMENT_ORDER = ["Cash", "Mpesa", "Card", "Bank", "Debt"];
const PAYMENT_LABELS: Record<string, string> = {Mpesa: "M-Pesa"};

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function number(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function paymentLabel(method: string): string {
  return PAYMENT_LABELS[method] ?? method;
}

export function buildDayReport(input: {
  businessDate: string;
  sales: SaleInput[];
  shifts: ShiftInput[];
  products: ProductInput[];
}): DayReport {
  const byId = new Map<string, ProductInput>();
  const categoryByName = new Map<string, string>();
  for (const product of input.products) {
    byId.set(product.id, product);
    const name = text(product.name).toLowerCase();
    if (name) categoryByName.set(name, text(product.category));
  }

  const shiftTotals = new Map<string, ShiftTotal>();
  for (const shift of input.shifts) {
    shiftTotals.set(shift.id, {
      staffName: text(shift.staffName) || "Unknown",
      startTime: shift.startTime ?? null,
      endTime: shift.endTime ?? null,
      open: text(shift.status) === "open",
      saleCount: 0,
      amount: 0,
    });
  }

  const payments = new Map<string, number>();
  const categories = new Map<string, {quantity: number; amount: number;
    items: Map<string, ItemTotal>}>();
  const hours = new Map<number, {amount: number; count: number}>();
  let totalSales = 0;
  let itemsSold = 0;
  let firstSaleAt: Date | null = null;
  let lastSaleAt: Date | null = null;

  for (const sale of input.sales) {
    const amount = number(sale.totalAmount ?? sale.total);
    totalSales += amount;
    const at = sale.dateAdded instanceof Date ? sale.dateAdded : null;
    if (at) {
      if (!firstSaleAt || at < firstSaleAt) firstSaleAt = at;
      if (!lastSaleAt || at > lastSaleAt) lastSaleAt = at;
      // Nairobi is a whole number of hours from UTC, so its hours start
      // where UTC's do.
      const hour = Math.floor(at.getTime() / HOUR_MS);
      const bucket = hours.get(hour) ?? {amount: 0, count: 0};
      bucket.amount += amount;
      bucket.count += 1;
      hours.set(hour, bucket);
    }
    const method = text(sale.payment) || "Cash";
    payments.set(method, (payments.get(method) ?? 0) + amount);

    // A sale with no shift, or one whose shift is on another date, is still
    // the day's: it gets a row of its own under whoever sold it.
    const shiftId = text(sale.shiftId);
    const shiftKey = shiftId && shiftTotals.has(shiftId) ?
      shiftId : `no-shift:${text(sale.soldBy)}`;
    let shift = shiftTotals.get(shiftKey);
    if (!shift) {
      shift = {
        staffName: `${text(sale.soldBy) || "Unknown"} (no shift)`,
        startTime: null,
        endTime: null,
        open: false,
        saleCount: 0,
        amount: 0,
      };
      shiftTotals.set(shiftKey, shift);
    }
    shift.saleCount += 1;
    shift.amount += amount;

    const items = Array.isArray(sale.items) ? sale.items as SaleItemInput[] : [];
    for (const item of items) {
      const name = text(item.productName) || text(item.name) || "Unnamed item";
      const quantity = number(item.quantity);
      const lineAmount = quantity * number(item.price);
      const product = byId.get(text(item.itemid));
      const category = text(product?.category) ||
        categoryByName.get(name.toLowerCase()) || OTHER_CATEGORY;
      const sku = text(item.sku);
      const size = sku && !name.toLowerCase().includes(sku.toLowerCase()) ? sku : "";
      const itemKey = product ?
        `id:${product.id}` : `name:${name.toLowerCase()}|${size.toLowerCase()}`;
      itemsSold += quantity;

      let bucket = categories.get(category);
      if (!bucket) {
        bucket = {quantity: 0, amount: 0, items: new Map()};
        categories.set(category, bucket);
      }
      bucket.quantity += quantity;
      bucket.amount += lineAmount;
      const line = bucket.items.get(itemKey) ?? {name, size, quantity: 0, amount: 0};
      line.quantity += quantity;
      line.amount += lineAmount;
      bucket.items.set(itemKey, line);
    }
  }

  const methodRank = (method: string) => {
    const index = PAYMENT_ORDER.indexOf(method);
    return index === -1 ? PAYMENT_ORDER.length : index;
  };
  const shifts = [...shiftTotals.values()].sort((a, b) =>
    (a.startTime?.getTime() ?? Infinity) - (b.startTime?.getTime() ?? Infinity) ||
    a.staffName.localeCompare(b.staffName));

  const hourly: HourTotal[] = [];
  if (hours.size) {
    const first = Math.min(...hours.keys());
    const last = Math.max(...hours.keys());
    for (let hour = first; hour <= last; hour++) {
      const bucket = hours.get(hour);
      hourly.push({
        start: new Date(hour * HOUR_MS),
        amount: bucket?.amount ?? 0,
        count: bucket?.count ?? 0,
      });
    }
  }

  return {
    businessDate: input.businessDate,
    totalSales,
    saleCount: input.sales.length,
    itemsSold,
    hourly,
    firstSaleAt,
    lastSaleAt,
    payments: [...payments.entries()]
      .map(([method, amount]) => ({method, amount}))
      .sort((a, b) => methodRank(a.method) - methodRank(b.method) ||
        a.method.localeCompare(b.method)),
    shifts,
    openShifts: shifts.filter((shift) => shift.open).map((shift) => shift.staffName),
    categories: [...categories.entries()]
      .map(([name, bucket]) => ({
        name,
        quantity: bucket.quantity,
        amount: bucket.amount,
        items: [...bucket.items.values()].sort((a, b) =>
          b.quantity - a.quantity || a.name.localeCompare(b.name) ||
          a.size.localeCompare(b.size)),
      }))
      .sort((a, b) => b.amount - a.amount || a.name.localeCompare(b.name)),
  };
}

// ── Dates ────────────────────────────────────────────────────────────────────

export const REPORT_TIME_ZONE = "Africa/Nairobi";

/** The business date a run at [now] reports on: yesterday, in Nairobi. */
export function previousBusinessDate(now: Date): string {
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: REPORT_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
  const [year, month, day] = today.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day - 1)).toISOString().slice(0, 10);
}

/** `2026-10-14` as `Tue 14 Oct 2026`. */
export function formatBusinessDate(businessDate: string): string {
  const [year, month, day] = businessDate.split("-").map(Number);
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "UTC",
    weekday: "short",
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(new Date(Date.UTC(year, month - 1, day))).replace(/,/g, "");
}

/** `2026-10-13` as `Tuesday 13 October 2026`. */
export function formatLongDate(businessDate: string): string {
  const [year, month, day] = businessDate.split("-").map(Number);
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "UTC",
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
  }).format(new Date(Date.UTC(year, month - 1, day))).replace(/,/g, "");
}

/** A moment as `Wed 14 Oct 08:00`, in Nairobi. */
export function formatDayTime(value: Date): string {
  const day = new Intl.DateTimeFormat("en-GB", {
    timeZone: REPORT_TIME_ZONE,
    weekday: "short",
    day: "numeric",
    month: "short",
  }).format(value).replace(/,/g, "");
  return `${day} ${formatTime(value)}`;
}

/** A moment as `Wed 13:57`, in Nairobi. */
export function formatWeekdayTime(value: Date): string {
  const weekday = new Intl.DateTimeFormat("en-GB", {
    timeZone: REPORT_TIME_ZONE,
    weekday: "short",
  }).format(value);
  return `${weekday} ${formatTime(value)}`;
}

/** The Nairobi calendar date of [value], `2026-10-13`. */
export function nairobiDate(value: Date): string {
  return new Intl.DateTimeFormat("en-CA", {timeZone: REPORT_TIME_ZONE}).format(value);
}

/** A moment as `Thu 15 Oct 2026 08:00`, in Nairobi. */
export function formatDateTime(value: Date): string {
  const date = new Intl.DateTimeFormat("en-GB", {
    timeZone: REPORT_TIME_ZONE,
    weekday: "short",
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(value).replace(/,/g, "");
  return `${date} ${formatTime(value)}`;
}

/**
 * A shift's span, `16:02 – 23:48`; an end on a later day than the start
 * carries that day, `13:36 – Wed 12:29`.
 */
export function formatShiftSpan(start: Date | null, end: Date | null, open: boolean): string {
  const day = (value: Date) => new Intl.DateTimeFormat("en-CA", {
    timeZone: REPORT_TIME_ZONE,
  }).format(value);
  const weekday = (value: Date) => new Intl.DateTimeFormat("en-GB", {
    timeZone: REPORT_TIME_ZONE,
    weekday: "short",
  }).format(value);
  const from = start ? formatTime(start) : "";
  let to = "";
  if (open) {
    to = "still open";
  } else if (end) {
    to = start && day(end) !== day(start) ?
      `${weekday(end)} ${formatTime(end)}` : formatTime(end);
  }
  return from || to ? `${from || "?"} – ${to || "?"}` : "";
}

export function formatTime(value: Date): string {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: REPORT_TIME_ZONE,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(value);
}

// ── Numbers ──────────────────────────────────────────────────────────────────

/** `39650` as `39,650`; cents only where there are any. */
export function formatMoney(amount: number): string {
  return amount.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

/** Whole counts as they are; a fractional one (from a split sale) to 2 places. */
export function formatQuantity(quantity: number): string {
  return quantity.toLocaleString("en-US", {maximumFractionDigits: 2});
}

// ── Template ─────────────────────────────────────────────────────────────────

/**
 * Meta refuses a body parameter holding a newline, a tab or more than four
 * spaces in a row, and an empty one.
 */
export function templateParameter(value: string, maxLength = 200): string {
  const flat = value.replace(/\s+/g, " ").trim();
  const capped = flat.length > maxLength ? `${flat.slice(0, maxLength - 1)}…` : flat;
  return capped || "-";
}

/**
 * The approved template's six body values, in order:
 *
 *   Business day summary for {{1}}.
 *   Shifts: {{2}}
 *   Total sales: KES {{3}} from {{4}} sales.
 *   Payments: {{5}}
 *   Shifts still open: {{6}}
 *   The category and item breakdown is in the attached report.
 */
export function templateParameters(report: DayReport): string[] {
  const staffed = report.shifts.map((shift) => shift.staffName);
  const shifts = staffed.length ? `${staffed.length} (${staffed.join(", ")})` : "none";
  const payments = report.payments
    .map((payment) => `${paymentLabel(payment.method)} ${formatMoney(payment.amount)}`)
    .join(" · ");
  return [
    formatBusinessDate(report.businessDate),
    shifts,
    formatMoney(report.totalSales),
    String(report.saleCount),
    payments || "none",
    report.openShifts.length ? report.openShifts.join(", ") : "none",
  ].map((value) => templateParameter(value));
}

export function reportFilename(businessDate: string): string {
  return `Day-report-${businessDate}.pdf`;
}
