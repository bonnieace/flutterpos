# Register: accounting — a design, 2026-10-13

Two boards for what `ACCOUNTING_WORKFLOW_DISCOVERY.md` adds to the Register (D-06, D-08, D-14,
D-26, D-34, D-41; §10 "Till"). Open [`index.html`](index.html). Self-contained HTML, no build step.

**This is a proposal.** Nothing in `lib/` was changed. The spec is not approved for
implementation. The till's layout is today's (the 2026-10-11 wide Register, and the phone's cart
sheet). These boards add pieces to it and move nothing.

## The question the screen is opened with

Unchanged: *what is this customer buying, and how are they paying?* The additions answer two more:

- *Is this a job we already agreed?* A quote at its prices, or an order's delivery with its deposit.
- *Does this customer have money with us, or owe us?* Credit to spend, or an overdue warning.

## The boards

| Board | What it shows |
| --- | --- |
| [Orders and quotes](till-orders-quotes.html) | OR-0004 delivered at 1440: deposit applied, part paid, rest on credit, the overdue warning; the *Quotes and orders* list; QT-0019 sold at its prices |
| [The cart](till-cart.html) | *Use money on account*; a not-stocked product priced at the sale; *Save as quote*; the confirmation after a sale that used credit |
| [Split payment](till-split.html) | Phase G: two methods covering a sale; a split not yet covered |

## Decisions drawn

1. **A loaded quote or order is a strip at the top of the cart.**
   - It names what was loaded, and its × sets it aside.
   - Lines carry an `ORDER PRICE` or `QUOTE PRICE` tag where the price differs from the catalog.
2. **A quote sale uses today's agreed-price display:** *Listed price*, *Agreed discount*,
   *Reason: Quote QT-0019*, *Agreed total*. The allow list does not apply (CF-7).
3. **The deposit is a line, not a tender.** *Deposit applied* sits under the order value; the big
   figure is what changes hands now. The server applies it regardless (D-14).
4. **The overdue warning is one amber line with no button.** It never blocks (D-26), and it reads
   the customer's cached open-due schedule, so it works offline.
5. **Use money on account is a switch, off by default.**
   - Shown only when the customer has released credit.
   - It takes the smaller of the credit and the total.
   - It works for a blocked customer (D-14).
6. **A not-stocked product asks its price when added.** The optional words print under its name
   (D-06).
7. **Save as quote lives in the cart's menu,** away from *Save sale* (D-41). It confirms that
   nothing is sold, then opens the quote screen with the lines.
8. **A split is rows under *Paid by*.**
   - A method and an amount per row, with *Left to pay* as the check.
   - Only cash may exceed the total, as change.
   - A named customer can put the rest on account (D-29).
9. **Nothing sits between Save sale and the record.** The confirmation, including what came off
   the account, is the existing snackbar after the save.

## Gaps and questions

1. **More than the quote's quantity.** A quote for 40 bags sold as 45: are the extra 5 at the quoted
   price or the catalog's? The spec does not say. Not drawn.
2. **Credit spent twice offline.** The till's claim (`creditFromAccountMinor`) is checked by the
   server. If two tills both spend the same 300 offline, the second becomes debt. The spec accepts
   this kind of lag (R2); a manager would see it on the statement.
3. **Loading an order with no shift open.** The Register already refuses a sale without a shift.
   The list can still be browsed; the refusal comes at *Save sale*, as today.
4. **Quantities on a part delivery** default to what is still to go here, and to the scheduled
   part on the order's own *Deliver* sheet. Is one default enough?

## What it takes

**Phase B** (not-stocked products):

- `stocked: false` and the price prompt;
- `checkout_sale.dart` decrements only stocked lines;
- `checkout_submission.dart` no longer requires at least one decrement.

**Phase D** (quotes and orders):

- the *Quotes and orders* entry point;
- loaded lines and their tags;
- `quoteId` / `orderId` on the sale;
- *Save as quote* through the pending-call queue.

**Phase G** (split payments):

- `paymentsMinor` on the sale, and the cart's rows.

**Phase E** (invoices and allocation):

- *Deposit applied* and *From account* on the cart and receipt;
- `creditFromAccountMinor` and `depositAppliedMinor` on the sale;
- the overdue warning from `openDueSchedule`.

**What these are, and what they need:**

- These are behaviour changes on the sale path. Each needs its device/server vectors and rules
  budget measured (§12).
- None is a restyle.
- Every one must keep the rule that the sale is written first.

## Accessibility

- The tags and the warning have glyphs and words.
- The switch has a label and a state.
- Steppers, chips and buttons are 48.
- The snackbar is a live region.
