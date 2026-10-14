# Orders — a design, 2026-10-13

Three boards for the Orders icon in `ACCOUNTING_WORKFLOW_DISCOVERY.md` (D-19, D-34, D-35, D-43,
D-47, Phase D). Open [`index.html`](index.html). Self-contained HTML, no build step.

**This is a proposal.** Nothing in `lib/` was changed. The spec is not approved for
implementation. Sample data: [`../accounting/README.md`](../accounting/README.md).

## The question the screen is opened with

- **The list:** *what goes out next, and which jobs need a manager?*
- **An order:** *how much has gone out, and where does the money stand?*

## The boards

| Board | What it shows |
| --- | --- |
| [The list](orders-list.html) | *Open* on a phone, with the over-delivered order kept visible; the sheet at 1440 under *All* |
| [An order](order-detail.html) | OR-0005, one Sunday of three delivered, as a whole phone page with notes, and at 1440 |
| [Working an order](order-actions.html) | Deposit; Deliver; a new order with no quote; Change a price; Cancel what's left; keeping part of a deposit as a fee; the over-delivery flag and its decision |

## Decisions drawn

1. **An order is a delivery count.**
   - The headline is delivered of ordered (*200 of 600*), with a meter in `ok` green and the
     words beside it.
   - Each line counts ordered, delivered and still to go (D-19).
   - A cancelled part shows as *Cancelled 400* in grey, so the three always add up.
2. **Two sums of money, never netted.**
   - *Deposit held* is the customer's money waiting for a delivery.
   - *Still due on deliveries* is what the invoices have open.
   - *Not yet delivered* is the value still to go, which nobody owes yet (§14).
3. **Every delivery is a sale with an invoice** (D-07). The order's deliveries list is its own
   statement: total, deposit used and due per delivery.
4. **Deliver is a sheet first.** It asks how many go out today, starting at the scheduled part,
   then opens the Register with those lines at the order's prices. The sale is written at the till
   like any other. The deposit is used by the server, not chosen by the cashier (D-14).
5. **Over-delivery is the one exception.**
   - An amber meter segment and a *Decide* badge mark it.
   - A callout on the order gives who, when and which receipt.
   - Three outcomes, each stating its stock effect (D-47).
   - It stays under *Open* until decided.
6. **Changes say which units they touch.**
   - A price change reprices only what is still to go.
   - Cancelling what's left names where the deposit goes.
7. **Keeping part of a deposit** is decided on the customer's page, as a third outcome of the
   waiting-money dialog. That outcome only exists for a cancelled order's deposit (D-15).
8. **No day strips, no captions under the tables, even columns** (the 2026-10-13 table rulings).

## Gaps and questions

1. **A deposit larger than the order.** Nothing in the spec stops a 10,000 deposit on a 7,400
   order. Should the dialog cap it at the order's value? The excess would otherwise sit held on the
   order until a cancellation releases it.
2. **Deposits after the last delivery.** If a deposit arrives (offline, late) after everything was
   delivered, D-35 says it pays the order's invoices first invoice first. Drawn nowhere; the
   order's money panel would show it as *used on INV-…* like any other.
3. **Delivery days.** The spec has no field for scheduled delivery days, only "a later delivery".
   The boards draw an optional list of days on the order, used for sorting and for *Deliver*'s
   default. That is a new field (`orders.deliveryDays`).
4. **Spec question 13** (who changes an order's price) is drawn as recommended: manager and up,
   with a reason.
5. **Delivery without the Register.** Should a driver be able to record a delivery from the order
   without opening the till? Not drawn. D-19 makes every delivery a normal sale, which needs a
   shift.

## What it takes

This is all Phase D, after A, B and C.

- New collections `orders` and `orders/{id}/deliveries`.
- New callables `createOrder`, `changeOrderPrice`, `cancelOrderRemainder` and
  `resolveOverDelivery`.
- Deposits through `recordCustomerPayment` with `kind: deposit`.
- A trigger on sale creation that records deliveries and flags over-delivery.
- The Register's *load an order* entry point (see [`../till-accounting/`](../till-accounting/)).
- A new home destination.

None of it is a restyle.

## Accessibility

- Every meter has words beside it.
- The over-delivery flag has a glyph, a word and a callout.
- Steppers and buttons are 48.
- Each dialog's confirm button names its outcome; the destructive ones are outlined.
