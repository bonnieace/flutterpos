import type {Firestore} from "firebase-admin/firestore";

/**
 * What a WhatsApp receipt says, read from the sale the server holds.
 *
 * **The printed receipt's words, in the printed receipt's order.** The thermal
 * receipt (`lib/checkout/checkout_receipt_body.dart`) is what a customer with
 * a printer gets, and a PDF that disagreed with it - another label, another
 * number - would be two receipts for one sale. So the words are `ReceiptWords`
 * copied, and the number is the same readable form, derived the same way.
 *
 * **From the stored sale and nothing a device sent with the request.** A
 * manual send names a sale and a number; everything on the receipt comes from
 * the sale document the checkout wrote, which is what the business's own
 * reports read too.
 */

export const RECEIPT_WORDS = {
  receiptLabel: "Receipt",
  dateLabel: "Date",
  servedByLabel: "Served by",
  customerLabel: "Customer",
  kraPinLabel: "KRA PIN",
  subtotalLabel: "Subtotal",
  discountLabel: "Discount",
  totalLabel: "TOTAL",
  paidByLabel: "Paid by",
  footer: "Keep this receipt for returns",
  unnamedBusiness: "Sales receipt",
} as const;

const TENDER_LABELS: Record<string, string> = {
  cash: "Cash",
  mpesa: "M-Pesa",
  card: "Card",
};

export interface ReceiptLine {
  name: string;
  sku?: string;
  quantity: number;
  unitPriceMinor: number;
  lineTotalMinor: number;
}

export interface ReceiptContent {
  businessName: string;
  slogan?: string;
  logoUrl?: string;
  /** The readable form a customer is told: `JOHN-CT-7F2-001`. */
  receiptNumber: string;
  businessDate: string;
  servedBy?: string;
  customerName?: string;
  customerKraPin?: string;
  currency: string;
  lines: ReceiptLine[];
  subtotalMinor: number;
  discountMinor: number;
  totalMinor: number;
  /** How the cashier said the customer paid, or absent where nobody said. */
  paidBy?: string;
}

const STORED_RECEIPT_PARTS = /^CT-([0-9A-F]{3})-\d{8}-(\d{4,6})$/;

/**
 * The receipt number as it is printed for a customer: `JOHN-CT-7F2-001`.
 *
 * `printedCheckoutReceiptNumber` in `checkout_receipt.dart`, step for step: the
 * first word of the server's name, upper-cased, letters and digits only, at
 * most ten; then the till's code and the day's sequence at three digits. A
 * stored number this cannot read is returned exactly as it is.
 */
export function printedReceiptNumber(receiptNumber: string, servedBy?: string): string {
  const parts = STORED_RECEIPT_PARTS.exec(receiptNumber);
  if (!parts) return receiptNumber;
  const sequence = String(Number.parseInt(parts[2], 10)).padStart(3, "0");
  const core = `CT-${parts[1]}-${sequence}`;
  const first = servedBy?.trim().split(/\s+/)[0] ?? "";
  const letters = [...first.toUpperCase().replace(/[^\p{L}\p{N}]/gu, "")]
    .slice(0, 10)
    .join("");
  return letters ? `${letters}-${core}` : core;
}

/** `KES 1,250.00` - the code always, and two decimals as on paper. */
export function formatReceiptMoney(currency: string, minor: number): string {
  const sign = minor < 0 ? "-" : "";
  const magnitude = Math.abs(minor);
  const whole = Math.floor(magnitude / 100).toLocaleString("en-US");
  const cents = String(magnitude % 100).padStart(2, "0");
  return `${currency} ${sign}${whole}.${cents}`;
}

/** `1 Oct 2026` from `2026-10-01`, or the stored text where it is not a date. */
export function readableBusinessDate(businessDate: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(businessDate);
  if (!match) return businessDate;
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];
  const month = months[Number(match[2]) - 1];
  return month ? `${Number(match[3])} ${month} ${match[1]}` : businessDate;
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function wholeMinor(value: unknown): number {
  return Number.isSafeInteger(value) ? value as number : 0;
}

function readLines(value: unknown): ReceiptLine[] {
  if (!Array.isArray(value)) return [];
  const lines: ReceiptLine[] = [];
  for (const item of value) {
    if (!item || typeof item !== "object") continue;
    const record = item as Record<string, unknown>;
    const quantity = wholeMinor(record.quantity);
    const unitPriceMinor = wholeMinor(record.unitPriceMinor);
    lines.push({
      name: text(record.name) ?? "Item",
      sku: text(record.sku),
      quantity,
      unitPriceMinor,
      lineTotalMinor: Number.isSafeInteger(record.lineTotalMinor) ?
        record.lineTotalMinor as number : quantity * unitPriceMinor,
    });
  }
  return lines;
}

/**
 * The receipt for one stored sale, or null where the sale is not on the server.
 *
 * Branding is the receipt's own - `configuration/branding` - and falls back to
 * the business's registered name, then to the printed receipt's heading for
 * an unnamed business, never to an ID.
 */
export async function readReceiptContent(
  db: Firestore,
  tenantId: string,
  saleId: string
): Promise<ReceiptContent | null> {
  const tenantRef = db.collection("tenants").doc(tenantId);
  const saleSnapshot = await tenantRef.collection("sales").doc(saleId).get();
  if (!saleSnapshot.exists) return null;
  const sale = saleSnapshot.data() ?? {};
  const soldById = text(sale.soldById);
  const [branding, tenant, staff] = await Promise.all([
    tenantRef.collection("configuration").doc("branding").get(),
    tenantRef.get(),
    soldById ?
      tenantRef.collection("staff").doc(soldById).get() :
      Promise.resolve(null),
  ]);
  const servedBy = text(staff?.get("name"));
  const tender = text(sale.tender);
  const logoUrl = text(branding.get("logoUrl"));
  return {
    businessName: text(branding.get("companyName")) ??
      text(tenant.get("name")) ??
      RECEIPT_WORDS.unnamedBusiness,
    slogan: text(branding.get("slogan")),
    logoUrl: logoUrl?.startsWith("https://") ? logoUrl : undefined,
    receiptNumber: printedReceiptNumber(text(sale.receiptNumber) ?? saleId, servedBy),
    businessDate: text(sale.businessDate) ?? "",
    servedBy,
    customerName: text(sale.customerName),
    customerKraPin: text(sale.customerKraPin),
    currency: text(sale.currency) ?? "",
    lines: readLines(sale.items),
    subtotalMinor: wholeMinor(sale.subtotalMinor),
    discountMinor: wholeMinor(sale.discountMinor),
    totalMinor: wholeMinor(sale.totalMinor),
    paidBy: tender ? TENDER_LABELS[tender] : undefined,
  };
}
