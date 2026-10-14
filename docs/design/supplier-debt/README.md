# Supplier debt and cost — a design, 2026-10-13

Two boards for Phase H of `ACCOUNTING_WORKFLOW_DISCOVERY.md`: single-entry supplier debt, and
moving-average cost (D-37). Open [`index.html`](index.html). Self-contained HTML.

**This is a proposal.** Nothing in `lib/` was changed. The spec describes Phase H in outline only,
so these boards make more calls of their own than the others. Each one is listed below.

## The question each screen is opened with

- **A supplier:** *what do I owe them, and when is it due?*
- **A product's cost:** *what did this cost me, and why did that change?*

## The boards

| Board | What it shows |
| --- | --- |
| [What you owe a supplier](supplier-account.html) | ABC Distributors at 1440 (owed, this month, *Pay ABC*, the bills sheet); the bill on the delivery form; paying |
| [Moving-average cost](cost-history.html) | White bread loaf's cost history at 1440; Bar soap with its cost unknown; the week's profit with *Final cost adjustments* |

## Decisions drawn

1. **The supplier page is the customer page turned round.**
   - *You owe them* with its age and the supplier's terms, and one primary action.
   - Tabs are Bills, Deliveries and Statement.
   - *Receive delivery* moves to the toolbar; *Edit* and *Mark inactive* move to its menu.
2. **A bill is the supplier's own invoice, recorded on the delivery form.** It has a number, an
   amount, and a due date from the supplier's terms. A delivered line with no cost can take its
   cost from the bill, which clears *cost unknown*.
3. **Paying a supplier settles the oldest bill first unless one is chosen,** with a preview, a
   method and a reference, as customer payments work. It can be voided by a manager.
4. **Cash from the drawer is its own method,** apart from M-Pesa and Bank, because only it touches a
   shift.
5. **Cost history shows its arithmetic per line:** what came in, at what cost, how many were on
   hand, and the average after. One line can be checked with a calculator.
6. **Cost changes are grey.** A rising cost is not good or bad news on this page.
7. **Unknown cost is a word and a callout,** never the old figure. Profit on what sold meanwhile
   reads *pending*, not 0.
8. **Profit shows its working:** sales, the till's cost, then the final-cost adjustments. Its label
   says *final costs used*, or *provisional* when offline.

## Gaps and questions

1. **Supplier payments and the drawer.** Paying in cash from the till must lower that shift's
   expected cash. Through which shift: the payer's open one, like customer payouts (spec question
   10)? The spec is silent. Drawn as a separate *Cash from the drawer* method so the rule has a
   place to attach.
2. **Supplier terms.** Drawn as a field on the supplier (*30 days*) that fills each bill's due date.
   §9 has no such field.
3. **Bills without a delivery.** Rent-like supplier charges, or a bill for a delivery recorded
   before Phase H. Drawn nowhere. Expenses may be the better home for those.
4. **Which cost a damaged return uses** (the returns README, question 3) belongs here too.
5. **The starting cost.** §12: product costs keep their current value and become averages from
   the next delivery. The history's first line says so, in its own words.

## What it takes

All Phase H:

- a supplier balance and ledger;
- bills linked to deliveries, payments with void rules, due dates and ageing;
- `receiveSupplierDelivery` and `completeProduction` setting the weighted average inside their
  transactions;
- `cost_history` and `sale_cost_adjustments`;
- a bounded recompute job for late events;
- reports adding adjustments to profit.

None of this is a restyle.

## Accessibility

- Every change has a sign and a glyph.
- *Unknown* and *pending* are words.
- The late state follows the invoices: an amber badge with a glyph.
