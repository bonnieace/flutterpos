import {
  BRAND_NAME,
  BrandedFact,
  BrandedReceipt,
  renderBrandedEmailHtml,
  renderBrandedEmailText,
} from "../email/branding";
import type {RenderedEmail} from "../email/templates";
import {
  RECEIPT_WORDS,
  formatReceiptMoney,
  readableBusinessDate,
} from "../whatsapp/receiptContent";
import type {ReceiptContent} from "../whatsapp/receiptContent";

/**
 * What an email receipt says.
 *
 * **The account emails' layout, with the receipt in it.** The masthead, the
 * card, the colours and the footer are `email/branding.ts`, so a customer who
 * also has an UzaPay account recognises the mail; what is new is the
 * itemised block, drawn in the printed receipt's order with its words
 * (`RECEIPT_WORDS`), and the PDF attached beside it - the same PDF a WhatsApp
 * receipt carries.
 *
 * **Unlike the account emails, this one names a business and a customer.**
 * That is what a receipt is. It still never carries the address it was sent
 * to: nothing a receipt prints came from the request that sent it, only from
 * the sale the server holds (`readReceiptContent`).
 */

export interface EmailReceiptOptions {
  /** Sent on its own to a customer who agreed, or asked for at the counter. */
  trigger: "automatic" | "manual";
  /** The customer's way out, or absent where no unsubscribe page is set up. */
  unsubscribeUrl?: string;
}

/** Control characters out of anything that lands in a header. */
function headerText(value: string): string {
  return value.replace(/[\p{Cc}]+/gu, " ").replace(/\s+/g, " ").trim();
}

function named(content: ReceiptContent): boolean {
  return content.businessName !== RECEIPT_WORDS.unnamedBusiness;
}

/** `Receipt JOHN-CT-7F2-001 from Mama Njeri Shop`, numbered so two don't thread. */
export function emailReceiptSubject(content: ReceiptContent): string {
  return headerText(named(content) ?
    `Receipt ${content.receiptNumber} from ${content.businessName}` :
    `Receipt ${content.receiptNumber}`);
}

/**
 * The name the customer's inbox shows: `Mama Njeri Shop via UzaPay`.
 *
 * **The shop's, because the shop is who they bought from**; the address stays
 * UzaPay's verified sender. Quotes and angle brackets are taken out rather
 * than escaped - a display name is the one place in a message where they
 * change what the header means.
 */
export function emailReceiptSenderName(content: ReceiptContent, fallback: string): string {
  if (!named(content)) return fallback;
  const business = headerText(content.businessName).replace(/["<>\\]/g, "");
  const bounded = business.length > 50 ? `${business.slice(0, 49)}…` : business;
  return bounded.length > 0 ? `${bounded} via ${BRAND_NAME}` : fallback;
}

/** The receipt block: the PDF's rows, in the PDF's order. */
export function emailReceiptBlock(content: ReceiptContent): BrandedReceipt {
  const money = (minor: number) => formatReceiptMoney(content.currency, minor);
  const facts: BrandedFact[] = [
    {label: RECEIPT_WORDS.receiptLabel, value: content.receiptNumber},
    {label: RECEIPT_WORDS.dateLabel, value: readableBusinessDate(content.businessDate)},
  ];
  if (content.servedBy) {
    facts.push({label: RECEIPT_WORDS.servedByLabel, value: content.servedBy});
  }
  if (content.customerName) {
    facts.push({label: RECEIPT_WORDS.customerLabel, value: content.customerName});
  }
  if (content.customerKraPin) {
    facts.push({label: RECEIPT_WORDS.kraPinLabel, value: content.customerKraPin});
  }
  const totals: BrandedFact[] = [
    {label: RECEIPT_WORDS.subtotalLabel, value: money(content.subtotalMinor)},
  ];
  if (content.discountMinor > 0) {
    totals.push({label: RECEIPT_WORDS.discountLabel, value: money(-content.discountMinor)});
  }
  totals.push({
    label: RECEIPT_WORDS.totalLabel,
    value: money(content.totalMinor),
    emphasis: true,
  });
  if (content.owedMinor !== undefined) {
    if (content.paidNowMinor) {
      totals.push({
        label: content.paidBy ?
          `${RECEIPT_WORDS.paidNowLabel} (${content.paidBy})` :
          RECEIPT_WORDS.paidNowLabel,
        value: money(content.paidNowMinor),
      });
    }
    totals.push({label: RECEIPT_WORDS.owedLabel, value: money(content.owedMinor)});
    if (content.balanceOwedMinor !== undefined) {
      totals.push({
        label: RECEIPT_WORDS.balanceLabel,
        value: money(content.balanceOwedMinor),
      });
    }
  } else if (content.paidBy) {
    totals.push({label: RECEIPT_WORDS.paidByLabel, value: content.paidBy});
  }
  return {
    heading: content.businessName,
    subheading: content.slogan,
    facts,
    items: content.lines.map((line) => {
      const detail = [
        line.sku,
        line.quantity > 1 ? `@ ${money(line.unitPriceMinor)}` : undefined,
      ].filter((part): part is string => Boolean(part)).join("  ");
      return {
        description: `${line.quantity} x ${line.name}`,
        detail: detail || undefined,
        amount: money(line.lineTotalMinor),
      };
    }),
    totals,
    closing: RECEIPT_WORDS.footer,
  };
}

export function emailReceiptEmail(
  content: ReceiptContent,
  options: EmailReceiptOptions
): RenderedEmail {
  const total = formatReceiptMoney(content.currency, content.totalMinor);
  const business = named(content) ? content.businessName : "the shop";
  const date = readableBusinessDate(content.businessDate);
  const email = {
    preheader: `${total} at ${business}${date ? `, ${date}` : ""}. ` +
      "The receipt is below and attached as a PDF.",
    eyebrow: `${RECEIPT_WORDS.receiptLabel} ${content.receiptNumber}`,
    title: named(content) ?
      `Thank you for shopping at ${content.businessName}` :
      "Thank you for shopping with us",
    lead: `Here is your receipt for ${total}. A PDF copy is attached to keep.`,
    receipt: emailReceiptBlock(content),
    footnote: options.trigger === "automatic" ?
      `You are receiving this because you agreed to get receipts from ` +
      `${business} by email.` :
      `You are receiving this because you asked ${business} to email you ` +
      "this receipt.",
    ...(options.unsubscribeUrl ? {
      footerLink: {
        text: "Don't want receipts by email?",
        label: "Stop email receipts",
        url: options.unsubscribeUrl,
      },
    } : {}),
  };
  return {
    subject: emailReceiptSubject(content),
    html: renderBrandedEmailHtml(email),
    text: renderBrandedEmailText(email),
  };
}
