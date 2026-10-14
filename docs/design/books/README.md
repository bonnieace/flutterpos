# Books (Phase I): designs, 2026-10-13

These boards draw the screens in [`BOOKKEEPING_DISCOVERY.md`](../../../BOOKKEEPING_DISCOVERY.md), the
discovery that the accounting spec's Phase I asked for (D-39). Open [`index.html`](index.html) for
the seven boards.

**These are proposals.** Nothing in `lib/` changed, and neither the discovery nor these boards is
approved for building.

## What the developer ruled (2026-10-13)

- **B-01 Plain words.**
  - Owners read "Money in", "What the shop owns and owes", "Profit", with the accounting name in
    small type underneath.
  - Debit and credit appear only on the trial balance and the general ledger.
- **B-02 VAT** is a switch, off by default. A tax adviser confirms the rates before it ships.
- **B-03 Filling the gaps:**
  - what the app records posts by itself;
  - M-Pesa and bank statements are imported, matched and sorted, the QuickBooks and Xero way;
  - a few owner forms;
  - export for the accountant.
- **B-04 The accountant has their own login**, posts journals marked as theirs, and nothing comes back
  by file.
- **B-05 Rules before screens.** The discovery gives the journal for every record. These boards
  follow it.

## The sample month

Dev Corner Shop again, a year on from the accounting boards. **The books started on Monday 1 March
2027.** The boards are set on Wednesday 14 April, with March not yet closed.

March was posted by hand from the discovery's rules, and the trial balance balances at **951,377**:

- **Profit:** 24,678 on sales of 412,200 after discounts and returns. Gross profit is 25.9%, and
  running costs are 82,682.
- **Money:**
  - 206,700 on 1 March, 216,045 on 31 March;
  - in came 414,700, out went 405,355.
- **On 31 March the shop:**
  - owns 525,308;
  - owes 99,650;
  - is worth 425,658 to the owner, who took 30,000 out and put 2,500 in.
- **One M-Pesa line** of 1,240 is still unsorted. It is a payment to Jikoni Supplies, and runs
  through every board until it is sorted on the close board.

The April figures on the home and the owner forms stand alone. Each form starts from the same
balances.

## What the boards add

| Board | What it shows |
| --- | --- |
| Home | Money now, account by account, with how each was last checked; the one thing to act on; April so far; the *Books* card in the home's Reports group |
| Setup | Start date (also the D-28 return cut-over); money accounts; opening balances with app figures tagged, typed figures asking for evidence, and the owner's stake as the balancing figure; a gap that holds approval |
| Money and statements | An account's entries; importing; day-matching till sales; sorting a line with a suggestion and a rule; the statement table; a balance that doesn't match |
| Owner forms | Move money, owner money, equipment with monthly wear, a loan repayment with interest; *Paid from* on expenses; *Into* on payments |
| Statements | What the shop made, owns and owes, where the money went; a figure opened to its entries, and an entry in plain words |
| The accountant's pages | Trial balance and general ledger (debit and credit), a journal that must balance, inviting the accountant, export |
| Closing a month | Needs attention; the close checklist with a warning and a reason; a cost correction that arrives after March closed |

## Found while drawing

- **F-5 Expenses never touch a shift's expected cash.**
  - Marking an expense *Paid from: Cash drawer* would leave that shift's count short. The books
    would then count the money twice: as the expense, and again as *Cash short*.
  - A mid-shift *Move money* out of the drawer has the same problem.
  - The discovery's Q-15 recommends tying both to the open shift. That would also answer the
    accounting hub's question 10 (supplier payments and the drawer).
- **The invite form's role descriptions** on the accountant board are placeholders, not today's
  wording.

## Still open

All in the discovery's §11, Q-01 to Q-15. The ones that change what is drawn here:

- **Q-01:** the start date is also the return cut-over.
- **Q-02:** managers see only *Move money*.
- **Q-08:** one cash drawer per shop.
- **Q-09:** year-end adjustments after the months are closed.
- **Q-13:** export layouts.
- **Q-15:** the drawer.

## Rulings these boards follow

- **The legacy look**: Roboto and `AppTokens.uzapay`.
- **Tables:**
  - tables for 1024 and up only;
  - no group strips and no caption under a table;
  - columns of equal width;
  - totals in the bar above.
- **Accessibility:**
  - targets of at least 48;
  - every status carries a glyph and words;
  - the one amber thing is the thing to act on.
- **Built locally**, self-contained HTML, no build step to open.
