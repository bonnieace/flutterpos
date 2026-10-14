# Accounting reports — a design, 2026-10-13

Two boards for the report figures in `ACCOUNTING_WORKFLOW_DISCOVERY.md` (D-11, D-13, D-27; defect R6;
Phase F). Open [`index.html`](index.html). Self-contained HTML.

**This is a proposal.** Nothing in `lib/` was changed. The spec is not approved for
implementation. Sample week: Monday 9 to Thursday 12 November 2026, Dev Corner Shop.

## The question each report is opened with

- **Money collected:** *how much actually came in, and how?*
- **Owed now:** *how much is owed, how late is it, and who do I chase?*
- **Money held:** *whose money am I holding, and does any of it need me?*

## The boards

| Board | What it shows |
| --- | --- |
| [Collected and held](reports-money.html) | A week of money collected on a phone: headline, by method, by source, and what was sold but not collected. Money held at 1440, with the waiting money filtered |
| [Owed now](reports-owed.html) | Everything owed today, aged, with the late list and *Written off* on a phone; the bucket row and the customer sheet at 1440 |

## Decisions drawn

1. **Collected is shown beside sales, never instead of it.** The headline is cash in hand, and the
   line under it gives sales for the same days. The last card lists what was sold but not
   collected, so the two can be reconciled by eye.
2. **By method first, then by source.** Method is what gets counted against a drawer, an M-Pesa
   statement or a card settlement. Source is D-11's formula, written as a list that sums to the
   headline. A zero line (payouts) stays listed.
3. **Owed now uses the customer page's bar,** for the whole shop. All six buckets are listed,
   including empty ones. *Before invoicing* is hatched and kept separate, because it has no due
   date.
4. **The total says it is complete.** "Every one counted, not capped" answers R6: the old
   who-owes total stopped silently at 500 customers.
5. **Late, by customer is the reminder list.** Each row shows the late amount against the whole
   balance, and opens the customer.
6. **Money held is three cells that never total into takings.** Only waiting money is amber. A
   waiting row shows its age after a day (§14).
7. **Written off has its own line** and says *nothing written off* rather than disappearing.
8. **Tables follow the 2026-10-13 rulings:** even columns, no strips, no captions under them.

**Not drawn:** the rename of *Owed on credit* to *Sold on credit* on the existing Sales totals and
day report (D-13). It is a label change, and *Sold on credit* appears here under its new name.

## Gaps and questions

1. **"Collected" and the drawer.** Repayments and deposits count in the recorder's shift (CF-4,
   D-05), so the shift reconciliation already expects them. Should *Money collected* by method be
   offered per shift as well as per period? Drawn per period only.
2. **A payout from a shift that is not the manager's.** *Paid back to customers* assumes payouts
   come from the manager's own shift (spec question 10, drawn as recommended).
3. **Ageing by due date across 31–60 and 61–90** joins the two cells at 1440 while both are empty.
   Is that worth the extra rule, or should all six cells always show?
4. **Owed now at a past date.** The spec's figures are "now". A month-end figure for an accountant
   would need balances as at a date, which the ledger can give, but no screen asks for it. Not
   drawn.

## What it takes

Phase F, after E:

- `collected*Minor` in `daily_metrics` (Phase A adds them);
- a server total for owed now that pages completely (R6);
- an ageing query over open invoices by `dueDate`, plus the `preInvoicingOutstandingMinor` sum;
- held-money sums from `orders` and `customers`.

There are three new Reports entries, and none is a restyle.

## Accessibility

- Every bar has its figure and its word.
- The method colours are the Sales totals report's, and are never the only label.
- Late cells and rows carry a glyph and a badge.
- Figures are read with their unit: "13,980 shillings 50".
