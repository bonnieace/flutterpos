# Quotes — a design, 2026-10-13

Four boards for the Quotes icon in `ACCOUNTING_WORKFLOW_DISCOVERY.md` (D-41, D-42, Phase D).
Open [`index.html`](index.html) in a browser. Self-contained HTML, no build step.

**This is a proposal.** Nothing in `lib/` was changed. The spec is not approved for implementation.
Sample data is the one shop and week shared by every accounting board: see
[`../accounting/README.md`](../accounting/README.md).

## The question the screen is opened with

- **The list:** *which quotes need someone?* One about to expire, one sent and not answered, a
  draft not yet sent.
- **A quote:** *is it still good, and what did the customer say?*

## Where it came from

- **Square Invoices' estimates.** An estimate is accepted and then converted, and a deposit or
  milestones can be asked for
  ([Square help](https://squareup.com/help/gb/article/7215),
  [estimates](https://squareup.com/us/en/invoices/features/estimates)).
  Here, accepting asks which of the spec's two ways the quote is going: sold now, or made into an
  order that holds the deposit.
- **The Register**, for the editor at 1440: the catalog on the left, the document on the right.
  D-41 asks for the till's own product search.
- **Paper.** At 1440 the quote is shown as the customer receives it, the A4 page from
  [`../documents/`](../documents/).

## The boards

| Board | What it shows |
| --- | --- |
| [The list](quotes-list.html) | *Open* and *Won* on a phone; the sheet at 1440 |
| [Making a quote](quote-editor.html) | The phone form; *Add products* (the till's search in a sheet); a one-off line; a phone that matches a customer; revision 3 at 1440 |
| [A quote](quote-detail.html) | A sent quote; *Accept*; *Make an order* with a deposit; *Send*; *Expired*; the 1440 view with the A4 page |
| [States](quote-states.html) | No quotes; a draft made offline; a won quote; closing as declined or cancelled |

## Decisions drawn

1. **A row is who, what and where it stands.** Three lines on a phone, columns from 1024 up.
   The number sits under the total, because that is what a customer quotes back.
2. **Only expiry gets colour.** *Expires tomorrow* (two days or less) is the one `StatusBadge`.
   *Valid until*, *Draft*, *Order OR-0004* and *Sold* are a glyph and a word.
3. **No day strips.** Open quotes sort by expiry, won and closed by newest. A heading per day would
   repeat the dates already in the rows (the ruling on Shift history's day strip, 2026-10-13).
4. **Accept is one button and one question.** A `ChoiceCardGroup`:
   - *Buying it all now* opens the Register at the quoted prices;
   - *Make an order* fixes the prices and can take the deposit.
   A callout settles the reviewer's case: if anything is handed over on another day, make an order.
5. **Making an order makes the customer** from the quote's typed name and phone (D-16). It can
   take the deposit in the same step if the person has an open shift (D-05).
6. **Prices only go down on stocked lines.** The price field starts at the catalog price. Typing
   higher is refused with the catalog price as the limit (D-08: a sale records only reductions). A
   one-off line's price is free.
7. **A one-off line is a not-stocked product plus words.**
   - It picks from the products marked *Not stocked* (Delivery, Catering, Custom order).
   - It then takes a description, a price and an optional cost (D-06, D-32).
   - Reports stay grouped while the quote reads naturally.
8. **Valid until starts empty** (D-18): required, with no default. The chips are shortcuts.
9. **Stock is told, never enforced.** Under a line, and beside a quote at 1440:
   *12 in stock. 40 more on open quotes* (D-20). It is never printed.
10. **A revision shows what changed.** A neutral *New in revision 3* tag, and the old total under
    the new. Red is kept for errors.
11. **At 1440 the quote is its A4 page,** next to its status, actions and revisions. One renderer
    draws the preview, the PDF and the WhatsApp attachment (Phase C).

## Gaps and questions

1. **Accepting an expired quote at the till.** D-08 honours quoted prices "until expiry". Is the
   cut-off the end of the valid-until day in the shop's time zone, or the trading day
   (the 06:00 cutoff of 2026-10-12)? Drawn as the end of the day; the trading-day rule may be what
   staff expect at 1 am.
2. **Quotes and Configs' agreed-price allow list.** CF-7 says quote prices apply for anyone. Should
   *making* a quote with a lowered price also be open to anyone, or only to those on the allow
   list? Drawn as anyone, because the spec only speaks of selling at it.
3. **Who sees a quote's cost.** The one-off line's cost is shown to roles that see profit (D-32).
   Is a quote's margin also shown on the quote screen to them? Not drawn.
4. **Declined vs Cancelled.** Drawn as separate outcomes, each with an optional note. The spec
   lists both states but no reason field.
5. **WhatsApp template:** a document with a caption needs Meta's approval (D-22). Submit with
   Phase A's templates.

## What it takes

This is all Phase D, and nothing here is a restyle.

- New collections `quotes` and `quotes/{id}/revisions`.
- New callables `saveQuote`, `sendQuote` and `cancelQuote`.
- A trigger on sale creation that records conversions.
- A new home destination.

**It depends on:**

- Phase B, for not-stocked products and typed prices;
- Phase C, for the A4 renderer and letterhead.

**Two things are reused, not rebuilt:**

- The product search sheet is the till's search component.
- The editor at 1440 reuses the Register's layout.

## Accessibility

- Every status has a glyph and a word; *Expires tomorrow* is a badge with a glyph.
- Steppers, chips, delete and add buttons are 48 targets.
- The dialogs are `AppDialog`s; *Accept* is a `ChoiceCardGroup` with its radio semantics.
- The A4 preview is an image of the PDF to a screen reader. The screen's own status panel carries
  every figure in text.

## Motion

The sheets move as `AppSheet` does. Nothing here is on the sale path. *Buying it all now* opens the
Register prefilled; the sale is written there as any other.
