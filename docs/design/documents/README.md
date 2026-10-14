# Documents — a design, 2026-10-13

Three boards for Phase C of `ACCOUNTING_WORKFLOW_DISCOVERY.md` (D-04, D-10, D-21 to D-24, D-40):
the A4 documents and the till slips. Open [`index.html`](index.html). Self-contained HTML.

**This is a proposal.** Nothing in `lib/` was changed. The spec is not approved for
implementation. The letterhead's settings screen is on
[`../accounting-settings/`](../accounting-settings/).

## The question a document answers

*What do I owe or get, by when, and how do I pay?* The figure the reader must act on is boxed;
every step from the total to it is a printed line above.

## Where it came from

- **The PDF reports already in the app** (`lib/reports/report_metrics.dart`, `AppReportRoles`):
  595 × 842 points, 40-point sides, Hanken Grotesk, ink, muted ink, rule, wash and the accent
  green. A business's documents should look like its reports.
- **Stripe's invoice PDFs.** A memo area for notes, and a footer for fixed or legally required
  text ([Stripe docs](https://docs.stripe.com/invoicing/customize)). Here, *Terms* and *How to pay*
  are boxes filled from the letterhead.
- **Today's till receipt** (`checkout_receipt_content.dart`) for the slips. Its order and words are
  kept; new lines are added in place.

## The boards

| Board | What it shows |
| --- | --- |
| [Quote and invoice](documents-a4.html) | QT-0019 and INV-0014; INV-0009, an order delivery paid in full by its deposit |
| [Order, receipt, draft, email](documents-more.html) | OR-0004's confirmation; payment receipt GRACE-PY-7F2-003 with what it paid; a draft quote with a watermark; the email |
| [Till slips](documents-thermal.html) | A delivery with *Deposit applied*; *From account*; a quote sale; *Deposit received*; *Refund paid* |

## Decisions drawn

1. **One letterhead for every document.** Logo, name and slogan come from Business details. The
   phone, address, KRA PIN, payment instructions and terms come from the new letterhead fields
   (D-21).
2. **Titles are plain:** *Quote*, *Order*, *Invoice*, *Payment receipt*. Never *Tax invoice*
   (D-04). Footers say "This is a quote, not an invoice" and "This is an order, not an invoice".
3. **The boxed figure is the one to act on:** a quote's total, an order's amount to pay on
   delivery, an invoice's amount due.
4. **Paid is a stamp and a zero,** never only colour. It is in the accent green, at 8.4:1 on paper;
   the report palette's brighter green is 3.0:1 and too light.
5. **On an invoice the Paybill account is the invoice number,** so payments arrive quoting it.
6. **The A4 payment receipt prints the allocation**, because the server's split is known when it
   is made. The till slip, printed at once, prints the phone's estimate and says so
   (customer-account finding 5).
7. **A draft carries a watermark across the page,** and its number field says the same in words
   (D-10).
8. **Slips add lines; nothing is reordered.** The order or quote is printed in the header block,
   *Deposit applied* and *From account* are separate lines above *Paid now*, and *Credit left*
   prints only when credit was used.
9. **No invoice number on the slip.** It is issued after the sale reaches the server, so the slip
   says how it was sent. A reprint from the Sales Report shows the number.

## Gaps and questions

1. **Signature lines.** Drawn on the order confirmation (shop and customer) and on the refund slip
   (customer). D-21 calls the signature line optional. Which documents get one?
2. **The sender address for email.** Drawn as the product domain; SIT mail comes from
   `swahilipro.com`. Not a design decision, but the subject line pattern assumes a sender a
   customer recognises.
3. **VAT.** No VAT lines are drawn (D-04: VAT accounts come with bookkeeping, and obligations are to
   be confirmed with an adviser). The renderer should reserve the space: a tax row above the boxed
   figure.
4. **A second page.** An order or quote with more than about 14 lines runs over. Drawn nowhere;
   the footer already carries *Page 1 of 1*.

## What it takes

Phase C:

- branding fields on the business;
- `configuration/invoicing`;
- one A4 renderer for the four kinds, reusing `pdf_report.dart`'s fonts, palette and metrics;
- the email and WhatsApp templates (submit the WhatsApp ones with Phase A's, D-22).

Changes to the slip land with the phase that adds each line (D, E). None of this is a restyle.

## Accessibility

- Paper has no states, but the PDF has a text layer, so a screen reader or a search reads every
  figure.
- On paper, ink is 17.7:1 and muted ink 7.8:1 (the report roles' own figures).
