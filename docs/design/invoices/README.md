# Invoices — a design, 2026-10-13

Three boards for the Invoices icon in `ACCOUNTING_WORKFLOW_DISCOVERY.md` (D-02, D-07, D-44,
Phase E). Open [`index.html`](index.html). Self-contained HTML, no build step.

**This is a proposal.** Nothing in `lib/` was changed. The spec is not approved for
implementation. Sample data: [`../accounting/README.md`](../accounting/README.md).

## The question the screen is opened with

- **The list:** *who has to be chased, and what is coming in this week?*
- **An invoice:** *what is still due on this bill, and what has paid it so far?*

## The boards

| Board | What it shows |
| --- | --- |
| [The list](invoices-list.html) | Six open invoices on a phone, overdue first; at 1440 a four-cell band (open, overdue, due in 7 days, paid since Monday) that is also the filter |
| [An invoice](invoice-detail.html) | INV-0007 overdue; INV-0014 part paid by a deposit; changing a due date; INV-0014 at 1440 as its A4 page |
| [Corrections](invoice-correct.html) | *What is wrong?*; a wrong price; the correction on the invoice; a duplicate cancelled; an invoice for a paid sale from its receipt |

## Decisions drawn

1. **Three figures, always:** total, paid and still due (D-07), side by side. A row shows the
   figure still due, with the total one press away.
2. **Overdue is the one badge.** *3 days late* with the original date under it. Due-soon is a grey
   clock and a word.
3. **No "New invoice".** An invoice belongs to a sale (D-02). A paid sale gets one from its
   receipt menu in the Sales Report.
4. **The list's top figure is invoices only.** Debt from before invoicing has no invoice, so the
   band says *Open* rather than *Owed*. The full owed figure, with that bucket, is on Reports.
5. **"What has paid it" is the allocation list** (§9): deposits, payments, credit used,
   corrections, returns and write-offs, each with who, when and why.
6. **At 1440 the invoice is its A4 page.** The deposit is a printed line, and the Paybill account is
   the invoice number.
7. **Corrections start from the cause, not the mechanism.**
   - Three causes, each describing its stock effect.
   - *Goods came back* hands over to Returns.
   - A price correction edits each line from what was charged, and can lower or raise it.
   - A duplicate shows its twin.
   (D-44.)
8. **Even columns, no captions or strips under the sheet** (2026-10-13 rulings).

## Gaps and questions

1. **Spec question 5** (send an invoice automatically on issue) is drawn as recommended: sent where
   the customer has WhatsApp or email on. The timeline says *Sent on WhatsApp, by itself on
   issue*.
2. **Spec question 19, export.** Drawn as a secondary *Export* button giving a CSV of what the
   filter shows. Keep or drop.
3. **Raising a price.** D-44 makes it a not-stocked *Price adjustment* sale. That sale needs a
   shift and a business day. Whose shift, and which day: today, or the original sale's? Drawn as
   the manager's shift today, which matches how returns are filed (D-28).
4. **Due-date changes and reminders** both need a record (who, when, why) for the timeline. §9
   lists `changeInvoiceDueDate` and `sendPaymentReminder` but no fields to hold their history.
5. **An invoice for a paid walk-in sale** needs a customer. The dialog lets one be chosen or added.
   Should a name typed only on the invoice be allowed, as on quotes (D-16)?

## What it takes

This is all Phase E, after A, C and D.

- `invoices/{saleId}` and `allocations`.
- Issuance in `processCustomerSale`.
- The callables `issueInvoice`, `changeInvoiceDueDate`, `sendPaymentReminder` and `correctInvoice`.
- The A4 renderer from Phase C.
- A new home destination.
- A *Make an invoice* entry in the Sales Report receipt menu.

None of it is a restyle.

## Accessibility

- Every state has a glyph and a word.
- The three figures are labelled cells, read as "Total 2,400 shillings, paid 0, still due 2,400".
- Dialog confirms name their outcome; the destructive ones are outlined.
- The A4 preview is an image of the PDF; the side panel carries every figure as text.
