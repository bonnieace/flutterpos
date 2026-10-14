# Accounting and documents — designs, 2026-10-12 to 13

The screens and documents for `ACCOUNTING_WORKFLOW_DISCOVERY.md`, in ten folders, plus *Books* for
Phase I from its own discovery, `BOOKKEEPING_DISCOVERY.md` (2026-10-13). Open
[`index.html`](index.html) for the map. Every board is self-contained HTML with no build step.

**These are proposals.** Nothing in `lib/` was changed. The spec is not approved for
implementation, and these boards are meant to help approve it. Each folder's README lists what
that area adds, the gaps it found, and what it takes to build.

## What is here

| Folder | Spec | Boards |
| --- | --- | --- |
| [Customer account](../customer-account/) | D-03, D-07, D-09, D-11, D-24, D-27, D-36, D-40; Phase A, E | 5 |
| [Quotes](../quotes/) | D-08, D-10, D-16 to D-18, D-34, D-41; Phase D | 4 |
| [Orders](../orders/) | D-05, D-15, D-19, D-35, D-43, D-47; Phase D | 3 |
| [Invoices](../invoices/) | D-02, D-07, D-44; Phase E | 3 |
| [Register](../till-accounting/) | D-06, D-08, D-14, D-26, D-29, D-41; Phases B, D, E, G | 3 |
| [Documents](../documents/) | D-04, D-10, D-21 to D-24, D-40; Phase C | 3 |
| [Reports](../accounting-reports/) | D-11, D-13, D-27, R6; Phase F | 2 |
| [Returns](../returns-accounting/) | D-09, D-28, D-45, D-49; Phase A, D | 1 |
| [Settings](../accounting-settings/) | D-06, D-07, D-21, D-30, D-42; Phases B, C, E | 3 |
| [Supplier debt and cost](../supplier-debt/) | D-37; Phase H | 2 |
| [Books](../books/) | Phase I, from `BOOKKEEPING_DISCOVERY.md` (B-01 to B-05) | 7 |

**Not drawn:**

- **The customer statement as a document.** *Send a statement* was offered on the customer page
  as new, but not drawn.
- **A credit-note print** (spec question 6, optional).
- **The *Sold on credit* rename** on today's reports (a label change, D-13).

## The sample week

Every board describes one shop: Dev Corner Shop (the harness's), on **Thursday 12 November 2026**.
Invoicing started on **Monday 2 November**. The figures are worked by hand from the spec's rules
and agree across boards wherever the same record appears.

- **Staff:** Grace Wanjiru, Brian Kimani, Faith Njeri, Amina Hassan (manager), and Amina Wanjiru
  (owner, on the home).
- **Customers:**
  - Mary Wambui: owes 4,250, and 3,450 is held for her.
  - Kamau Njoroge: holds 300 credit; QT-0019 is his charcoal quote.
  - St. Mark's Church: OR-0005, three Sundays of mandazi.
  - Achieng Atieno: OR-0003, delivered in two parts.
  - Wanjiku Mwangi: owes 3,680.50 and has an over-delivered OR-0002.
  - Jane Wanjiku: cancelled OR-0001, so 1,000 is waiting.
  - Otieno Ouma: inactive, owes 450 from before invoicing.
  - Esther Kariuki and Brightstar School: quotes only.
- **Products:** the harness's, plus not-stocked *Delivery*, *Custom order* and *Cancellation fee*.

A few frames say they are examples from another day; those figures stand alone. The States board in
Customer account is set on go-live day and in Phase A.

## Rulings these boards follow

- **The legacy look**: Roboto and `AppTokens.uzapay`. The home uses the 277 × 191 cards
  (2026-10-10).
- **Tables are for 1024 and up only.** Phones and 768–1023 keep their lists (2026-10-12).
- **Tables have no group or day strips, no caption under them, and evenly spaced columns**
  (2026-10-13, after the Shift history day strip).
- **Cards are feature-based**: a row or card shows what the thing is and where it stands, with
  status drawn only where someone should act (2026-10-08).
- **Designs are built locally** in `docs/design/` (2026-09-21).

## Shared patterns

- **Money is never netted across kinds.** Debt and held money sit side by side, an order's
  deposit and its due are separate, and collected and sold are shown together.
- **The one thing to act on is amber,** with a glyph and words. Everything settled is grey.
- **Every action states what it will change before it changes it.** Confirm buttons name their
  outcome; destructive ones are outlined.
- **Documents are the screen.** At 1440 a quote or an invoice is shown as its A4 page, beside its
  status and actions. One renderer makes the preview, the PDF and the attachment.
- **The sale is written first.** Nothing new sits between *Save sale* and the record.

## Every open question, in one list

Each folder's README has the reasoning; this is the index.

**Status, 2026-10-13: all deferred.** The developer asked for these to be kept for later. None has
been ruled on. Raise the relevant ones before building a phase that depends on them. The four that
shape the build most are: where a payment's remainder goes (1), a *Void* route for waiting money
(1), supplier payments and the drawer (10), and where the letterhead lives (9).

**Findings in the spec** (things a ruling is needed for):

1. **Customer account:**
   - where a payment's remainder goes when its chosen invoice needs less;
   - a *Void* route for waiting money that came from a payment;
   - duplicate offline payments only become waiting money if the debt was already cleared;
   - reminders need a record;
   - whether the payment slip prints the balance.
2. **Quotes:**
   - the expiry cut-off (end of day or trading day);
   - whether lowering prices on a quote follows the agreed-price allow list;
   - margin on the quote screen;
   - declined vs cancelled reasons.
3. **Orders:**
   - deposits larger than the order;
   - late deposits after the last delivery;
   - scheduled delivery days (a new field);
   - recording a delivery without the till.
4. **Invoices:**
   - whose shift and day a price-raising correction uses;
   - history fields for due-date changes and reminders;
   - typed names on an invoice for a walk-in.
5. **Register:**
   - more than a quote's quantity;
   - credit spent twice offline;
   - the default quantity on a part delivery.
6. **Documents:**
   - which documents get signature lines;
   - space reserved for VAT;
   - second pages.
7. **Reports:**
   - collected per shift;
   - joining the empty ageing cells;
   - owed as at a date.
8. **Returns:**
   - splitting a line's condition;
   - rejecting and re-filing in one step;
   - the cost of damaged goods.
9. **Settings:**
   - letterhead in Configs or Business details;
   - turning invoicing off again;
   - who sees Invoices on the home;
   - seeding *Cancellation fee*.
10. **Supplier debt:**
    - supplier payments and the drawer;
    - supplier terms (a new field);
    - bills without a delivery.
11. **Books (Phase I):** Q-01 to Q-15 in `BOOKKEEPING_DISCOVERY.md` §11. Its Q-15 (expenses and
    supplier payments from the drawer) would settle question 10 above.

**Spec questions drawn as recommended:**

- 5: send invoices automatically. Drawn as a setting, default on.
- 8: phone match is suggested and confirmed.
- 10: payouts need the manager's own shift.
- 13: managers change order prices, with a reason.
- 15: credit can be put towards an invoice.
- 19: export as CSV, as an easy-to-drop secondary button.

**Marked new, keep or drop:**

- *Send a statement*;
- the *not sent yet* callout for queued payments;
- *Export*;
- *Received by* on deliveries (from the tables boards).

## How the boards were made

Each folder's pages were assembled from shared sources (one stylesheet and one glyph sprite) by a
small script, so every page carries identical styles. The pages themselves are self-contained and
safe to edit directly. Every board was rendered with headless Chrome and read back while it was
drawn.
