import {formatReceiptMoney, readableBusinessDate} from "./receiptContent";
import type {ReceiptContent} from "./receiptContent";

/**
 * The two receipt templates, as registered on the shared WhatsApp Business
 * account, and the parameters each is sent with.
 *
 * **Template names are immutable once submitted.** A wording Meta rejects is
 * resubmitted under the next suffix (`_v2`) and changed here at the same time.
 *
 * Register each under **Utility**, language **English (`en`)**:
 *
 * - `uzapay_receipt_pdf_v1`, with a **Document** header:
 *   > Thank you for shopping at {{1}}. Your receipt {{2}} for {{3}} is
 *   > attached. Reply STOP to stop receipts.
 * - `uzapay_receipt_summary_v1`, no header:
 *   > Thank you for shopping at {{1}}. Receipt {{2}} on {{3}}: {{4}}, total
 *   > {{5}}. Reply STOP to stop receipts.
 *
 * **The way out is in every receipt**, rather than in the automatic reply,
 * because the reply also reaches carerota's carers until it moves to its own
 * account, and it has to make sense to them.
 *
 * Neither carries an itemised list: a template parameter may not contain a
 * line break, which is what an itemised list is.
 */

export const RECEIPT_PDF_TEMPLATE = "uzapay_receipt_pdf_v1";
export const RECEIPT_SUMMARY_TEMPLATE = "uzapay_receipt_summary_v1";

/** Meta refuses a parameter longer than this. */
const MAXIMUM_PARAMETER_LENGTH = 1000;

/**
 * One parameter as Meta accepts it: no line breaks or tabs, never more than
 * four spaces in a row, and not empty.
 */
export function templateText(value: string): string {
  const flattened = value
    .replace(/[\r\n\t]+/g, " ")
    .replace(/ {4,}/g, "   ")
    .trim();
  const bounded = flattened.length > MAXIMUM_PARAMETER_LENGTH ?
    `${flattened.slice(0, MAXIMUM_PARAMETER_LENGTH - 1)}…` :
    flattened;
  return bounded.length > 0 ? bounded : "-";
}

/** `1 item`, `3 items`, counted by units rather than lines. */
export function itemCountText(content: ReceiptContent): string {
  const units = content.lines.reduce((sum, line) => sum + line.quantity, 0);
  return units === 1 ? "1 item" : `${units} items`;
}

export function receiptPdfParameters(content: ReceiptContent): string[] {
  return [
    content.businessName,
    content.receiptNumber,
    formatReceiptMoney(content.currency, content.totalMinor),
  ].map(templateText);
}

export function receiptSummaryParameters(content: ReceiptContent): string[] {
  return [
    content.businessName,
    content.receiptNumber,
    readableBusinessDate(content.businessDate),
    itemCountText(content),
    formatReceiptMoney(content.currency, content.totalMinor),
  ].map(templateText);
}

/** The file name a customer sees on the attachment. */
export function receiptFilename(content: ReceiptContent): string {
  const safe = content.receiptNumber.replace(/[^A-Za-z0-9-]/g, "");
  return `Receipt-${safe || "receipt"}.pdf`;
}

/** What the setup screen previews, in the template's own words. */
export function receiptMessagePreview(
  format: "pdf" | "summary",
  content: ReceiptContent
): string {
  if (format === "pdf") {
    const [business, receipt, total] = receiptPdfParameters(content);
    return `Thank you for shopping at ${business}. Your receipt ${receipt} ` +
      `for ${total} is attached. Reply STOP to stop receipts.`;
  }
  const [business, receipt, date, items, total] = receiptSummaryParameters(content);
  return `Thank you for shopping at ${business}. Receipt ${receipt} on ` +
    `${date}: ${items}, total ${total}. Reply STOP to stop receipts.`;
}

/**
 * The reply to a customer who writes to the number.
 *
 * **Worded for both products**, because until carerota moves to its own
 * account its carers write to this number too, and nobody reading it should
 * be told they reached the wrong place.
 */
export const AUTOMATIC_REPLY =
  "This number sends automated messages and can't read replies. Please " +
  "contact the business directly.";

export const STOPPED_REPLY =
  "You will get no more receipts from this number. Reply START to get them " +
  "again.";

export const STARTED_REPLY =
  "Receipts from shops that use UzaPay can reach you on this number again.";
