# UzaPay — Bookkeeping (Phase I) Discovery

**Status:** Draft for rulings; **not approved for implementation.** This is the discovery that
`ACCOUNTING_WORKFLOW_DISCOVERY.md` (D-39, Phase I) asks for before bookkeeping is built.

**Date:** 2026-10-13. **Method:** source reading and an interview. No tests were run.

**Designs:** [`docs/design/books/`](docs/design/books/index.html).

---

## 1. Summary

The app already records about 80% of what a small shop's books need: sales, payments, returns, stock
movements, expenses and (from Phase H) supplier debt. Phase I turns each of those records into a
balanced journal **automatically**. Nobody types a debit or a credit for an ordinary day.

**The 20% the app cannot know** sits mostly in the M-Pesa and bank statements: charges, money moved
between accounts, money the owner took out, rent paid from the bank. The app fills that gap the way
QuickBooks and Xero do:
1. the owner imports a statement;
2. lines that match something the app already holds tick themselves off;
3. the owner says what each remaining line was, from a short list;
4. rules remember the answer for next time.

**What is left** (depreciation, loan interest splits, tax, year-end adjustments) belongs to an
accountant in any software. The accountant gets their own login and posts those as journals marked
as theirs. An owner without an accountant still gets working statements. An owner with one can
export everything to the accountant's software.

## 2. Rulings from the interview (2026-10-13)

**B-01 Who the books are for.** The owner, in plain words.
- Every screen says what happened in shop terms: "Money in", "What the shop owns and owes", "Profit".
- The accounting name appears under each plain name, smaller.
- **Debit and credit columns appear on two pages only:** the trial balance and the general ledger,
  which are the accountant's pages.

**B-02 VAT is a switch, off by default.**
- When it is on, prices are taken as VAT-inclusive, VAT accounts appear, and there is a VAT summary
  per period.
- Obligations and rates are confirmed with a tax adviser before the switch ships (D-04).
- eTIMS stays separate and later.

**B-03 How the gaps are filled.** The app:
- posts what it knows automatically;
- imports M-Pesa and bank statements to match and categorise the rest;
- offers short owner forms for owner money, equipment and loans;
- exports for the accountant.

**B-04 The accountant has their own login.**
- A new **Accountant** role reads everything in the books.
- It posts balanced journals with a reason. Each is marked as the accountant's, and can be reversed
  but never edited.
- It cannot sell, open shifts or change stock.
- **No file comes back:** the accountant types their adjustments in.

**B-05 Rules before screens.** This document sets the journal for every record. The boards in
`docs/design/books/` follow it.

## 3. What the app records today, and what each will post

`Dr` and `Cr` are used here because this section is for whoever builds the posting engine. Owners
never see them (B-01).

### 3.1 The chart of accounts

The chart is seeded for every shop. Owners can add **sub-accounts** (a second M-Pesa till, a bank,
a new running cost) but cannot delete or rename the seeded ones. Codes are fixed, so exports stay
stable.

| Code | Plain name (shown) | Accounting name (small) |
| --- | --- | --- |
| **1000–1999** | **What the shop owns** | Assets |
| 1010 | Cash drawer | Cash on hand |
| 1020 | Cash kept aside *(optional, Q-15)* | Petty cash |
| 1100 | M-Pesa *(one per till or paybill)* | Mobile money |
| 1200 | Bank *(one per account)* | Bank |
| 1150 | Card payments on the way | Card clearing |
| 1300 | Customers owe us | Accounts receivable |
| 1400 | Stock | Inventory |
| 1500 | Equipment | Fixed assets |
| 1510 | Equipment wear so far | Accumulated depreciation |
| 1600 | VAT we can claim back *(VAT on)* | Input VAT |
| 1900 | Not sorted yet | Suspense |
| **2000–2999** | **What the shop owes** | Liabilities |
| 2000 | We owe suppliers | Accounts payable |
| 2110 | Order deposits we hold | Customer deposits |
| 2120 | Customer credit | Customer credit balances |
| 2130 | Money waiting for a manager | Unapplied receipts |
| 2200 | VAT we owe *(VAT on)* | Output VAT |
| 2300 | Loans | Loans payable |
| **3000–3999** | **The owner's stake** | Equity |
| 3000 | Owner's money in | Capital |
| 3100 | Owner took out | Drawings |
| 3200 | Profit kept from earlier years | Retained earnings |
| **4000–4999** | **Money from sales** | Income |
| 4000 | Sales of stock | Sales |
| 4010 | Sales of services and one-offs | Service income |
| 4100 | Discounts given | Sales discounts |
| 4200 | Goods returned | Sales returns |
| 4900 | Other money in | Other income |
| **5000–5999** | **What the goods cost** | Cost of sales |
| 5000 | Cost of goods sold | Cost of goods sold |
| 5100 | Stock lost or damaged | Inventory write-off |
| **6000–6999** | **Running costs** | Expenses |
| 6000–6090 | Rent, Wages, Utilities, Transport, Supplies, Repairs, Licences, Other | *(today's expense categories)* |
| 6100 | Bank and M-Pesa charges | Bank charges |
| 6200 | Equipment wear | Depreciation |
| 6300 | Loan interest | Interest expense |
| 6400 | Debts written off | Bad debts |
| 6500 | Cash short | Cash over/short |

**Customer money is never netted** (shared pattern, D-36). Deposits, credit and waiting money are
three accounts, not one.

### 3.2 The posting table

Each record posts **once**, when it reaches the server. A void or rejection posts a **reversing
journal**, and nothing is edited (D-39).

The rows below run from the source record (with where it lives), to the journal it posts, to notes.

**Sale** (`checkoutSales`, `processCustomerSale`).
- Journal:
  - Dr one money account per tender: Cash drawer, M-Pesa, or Card on the way;
  - Dr *Customers owe us* for the part on credit;
  - Dr *Order deposits* for a deposit applied;
  - Dr *Customer credit* for credit used;
  - Dr *Discounts given*;
  - Cr *Sales of stock* or *Services*, at the gross amount;
  - Dr *Cost of goods sold*, Cr *Stock*, at the till's cost.
- Notes:
  - a split sale (D-29) posts one money line per method;
  - not-stocked lines go to *Services* (D-06, D-46);
  - with VAT on, Cr *VAT we owe* = VAT-inclusive net × rate ÷ (100 + rate), per line's VAT class.

**Cost adjustment** (`sale_cost_adjustments`, D-37).
- Journal: Dr or Cr *Cost of goods sold*, against Cr or Dr *Stock*.
- Notes: posted in the open month if the sale's month is closed (D-28).

**Customer payment** (repayment, D-03).
- Journal: Dr money account, Cr *Customers owe us*. Any excess is Cr *Money waiting* (D-36).
- Notes: "which account received it" is chosen from Phase I on (D-12).

**Deposit** (D-05).
- Journal: Dr money account, Cr *Order deposits*.

**Waiting money released to credit.**
- Journal: Dr *Money waiting*, Cr *Customer credit*.

**Refund paid out.**
- Journal: Dr *Money waiting* or *Customer credit* or *Order deposits*, Cr money account.

**Part of a deposit kept on cancellation** (D-15).
- Journal: posts as a sale of *Cancellation fee* paid from the deposit (the sale row above).

**Write-off** (D-27).
- Journal: Dr *Debts written off*, Cr *Customers owe us*.

**Payment void, write-off void** (D-09).
- Journal: the reversing journal.

**Invoice** (D-02).
- Journal: **nothing.** It is a document, and the sale already posted.

**Invoice correction** (D-44).
- Journal, by kind:
  - price: Dr *Sales* (or *Discounts given*), Cr *Customers owe us*;
  - recorded twice: a full reversal of the duplicate sale, stock included;
  - goods came back: the return row below.
- Notes: posted on the day of the correction.

**Return, verified** (`returns.ts`, D-28, D-45).
- Journal:
  - Dr *Goods returned*, Cr the way the money went back: a money account, *Customers owe us*, or
    *Customer credit*;
  - sellable: Dr *Stock*, Cr *Cost of goods sold*, at the cost the sale carried;
  - damaged: Dr *Stock lost or damaged*, Cr *Cost of goods sold*.
- Notes: on the day it happens, from the books' start date (§6). A rejection reverses it.

**Stock adjustment** (`adjustStock`).
- Journal, by type:
  - `damage`, `waste`: Dr *Stock lost*, Cr *Stock*;
  - `inventory_count` or `correction` down: the same;
  - `inventory_count` or `correction` up: Dr *Stock*, Cr *Other money in*;
  - `restock`: Dr *Stock*, Cr *Not sorted yet* (Q-07);
  - `opening_balance`: Dr *Stock*, Cr *Owner's money in* before the start date, and *Not sorted
    yet* after it.
- Notes: valued at the moving average when it happened. An unknown cost posts nothing and goes to
  *Needs attention*.

**Stock-take applied** (`stockTakeApply`).
- Journal: each line's difference, as `inventory_count`.

**Supplier delivery with a bill** (Phase H).
- Journal: Dr *Stock* (and Dr *VAT we can claim back*), Cr *We owe suppliers*.
- Notes: if paid on the spot, the payment row follows at once.

**Supplier payment** (Phase H).
- Journal: Dr *We owe suppliers*, Cr money account.
- Notes: open question 10 in the accounting hub (the drawer).

**Production batch** (`completeProduction`).
- Journal: Dr *Stock* (outputs), Cr *Stock* (inputs), at input cost.
- Notes: extra costs, Q-06.

**Expense** (`TenantExpense`).
- Journal: Dr the category's running cost, Cr **what paid it**: Cash drawer, M-Pesa, Bank, or
  *Owner's money in* when the owner paid from their own pocket.
- Notes: **finding F-1.** Expenses do not record what paid them today.

**Expense void.**
- Journal: the reversing journal.

**Shift closed with a cash difference** (`ShiftTenderDeclaration`).
- Journal:
  - short: Dr *Cash short*, Cr *Cash drawer*;
  - over: Dr *Cash drawer*, Cr *Other money in*.
- Notes: **cash only.** An M-Pesa or card difference moves no money; the statement settles it (§4).

**Loyalty points earned.**
- Journal: **nothing.**
- Notes: points have no money value while there is no redemption (ruled 2026-10-01). When redemption
  is designed, it needs a liability.

### 3.3 Findings

- **F-1 Expenses do not say what paid them.**
  - D-39 lists "an expense records what paid it" as a posting-ready rule.
  - `lib/expenses/expense.dart` stores category, description, amount, date and void fields, and no
    payment source.
  - Phase I adds a **Paid from** field. Expenses from before the books start are not reposted (D-39).
- **F-2 There is no return-to-supplier record.**
  - The supplier code has deliveries but nothing for goods sent back. The spec's gap list names it.
  - See Q-05.
- **F-3 `restock` adds stock without a supplier or a bill.** After Phase H this should be rare, but
  it exists. See Q-07.
- **F-4 Card money is not tracked to the bank.**
  - A card sale's money lands in the bank days later, less a fee.
  - *Card payments on the way* holds it until the bank statement shows the settlement.
  - Shops without card terminals never see that account.
- **F-5 Expenses never touch a shift's expected cash.**
  - Expenses are recorded apart from shifts. The drawer expectation (`reconciliation/model.ts`)
    counts sales, repayments, refunds and returns handed back, but not expenses.
  - If an expense is marked *Paid from: Cash drawer*, that shift's count comes up short by the
    expense. The books would then show the money twice: once as the expense, and again as *Cash
    short*.
  - This is the same question as supplier payments and the drawer (accounting hub, question 10).
    See Q-15.

## 4. Money accounts and statements

**Money accounts:**
- The *Cash drawer*, one per shop (Q-08).
- One *M-Pesa* account per till or paybill.
- One *Bank* per account.
- *Card payments on the way*, if the shop takes cards.

Every payment the app records says which account received it. A shop with one of each never
chooses; the choice appears only when there are two.

**Importing a statement:**
1. **Upload.**
   - The M-Pesa business statement (CSV or Excel export) is read by a known layout. *To verify: the
     exact export format from the M-Pesa business portal.*
   - A bank CSV is mapped once per bank (date, details, money in, money out, balance), and the
     mapping is kept.
2. **De-duplication.** A line's identity is its reference, date and amount. Importing an
   overlapping statement adds only the new lines.
3. **Matching.** Each line is matched to something the app already holds:
   - by reference: an M-Pesa code typed on a payment (D-12);
   - **by day, in a group:** "M-Pesa sales, Tue 10 Nov" in the app against all the till's incoming
     lines that day. Matching single small sales one by one is not attempted;
   - by amount and date: supplier payments, expenses, transfers already recorded.
4. **Sorting the rest.** Each unmatched line gets a plain choice:
   - Bank or M-Pesa charge
   - Moved to another account
   - Owner took it
   - Owner put it in
   - A running cost (category)
   - A supplier payment
   - A customer payment
   - Loan in
   - Loan repayment
   - Something else (*Not sorted yet*)
5. **Rules.** "Lines whose details contain *Charge* are bank charges", offered after the second
   time the same choice is made.
6. **Balance check.** The statement's closing balance against the books' balance for that account,
   on that date. A difference is shown in words and figures, never hidden.

## 5. Owner forms

Each form is a few fields and states the result before saving ("Bank goes up by 50,000; Cash drawer
goes down by 50,000").

- **Move money:** from, to, amount, an optional fee. Banking the cash is the common case.
- **Owner put money in:** into which account, amount.
- **Owner took money out:** from which account, amount.
  - *Owner took stock* is the same, with products valued at cost.
- **Bought equipment:**
  - what it is, cost, paid from (account, owner, or a supplier on credit);
  - how many years it will last (default 5).
  - The app works out monthly wear (straight line) until an accountant says otherwise.
- **Took a loan:** lender, amount, into which account.
- **Repaid a loan:** amount and from where. Interest is split out if the lender's statement says so.
  Otherwise the whole amount lowers the loan and *Needs attention* asks for the split.
- **Paid tax:** amount and from where. It lowers a tax-owed figure the accountant has set, and
  otherwise goes to *Not sorted yet*.

## 6. Opening balances and the start date

**The books start on the first day of a month** chosen by the owner, after Phases A–H are live. On
the same date, returns switch to counting on the day they happen (D-28). The two are one cut-over,
announced in the app beforehand.

**Opening balances, as a guided list:**

| Line | Where it comes from |
| --- | --- |
| Each money account | Typed from a count or a statement on the start date, with that statement's date |
| Stock | The app: quantity × moving average. Unknown costs are listed and must be filled |
| Customers owe us, deposits, credit, waiting | The app (server balances) |
| We owe suppliers | The app (Phase H) |
| Equipment | Typed: what, bought when, cost, value now |
| Loans | Typed |
| VAT owed | Typed, if VAT is on |
| **Owner's stake** | **The balancing figure**, explained ("what the shop is worth to you on 1 Dec") |

- The owner approves the list. It can be reopened until the first month is closed.
- The accountant can review the list but does not need to.

## 7. Months, closing, and late records

- A month is closed by the owner or the accountant.
- **Closing asks for, in order:**
  - nothing left in *Needs attention* for that month;
  - each money account reconciled to a statement.

  Each is a warning that can be overridden with a reason, not a block, because some shops will
  never import a bank statement.
- **A closed month never changes (D-28).**
  - A record dated in a closed month keeps its own date and posts in the open month.
  - Reversals post there too.
  - The ledger shows both dates.
- **At year end**, profit moves to *Profit kept from earlier years* by the app.
- **Accountant adjustments for a closed year:** Q-09.

## 8. Statements

| Plain name | Accounting name | Who |
| --- | --- | --- |
| What the shop made | Profit and loss | Owner, accountant |
| What the shop owns and owes | Balance sheet | Owner, accountant |
| Where the money went | Cash flow | Owner, accountant |
| Trial balance (Dr/Cr) | Trial balance | Accountant, owner |
| Every entry (Dr/Cr) | General ledger | Accountant, owner |
| VAT summary | VAT return workings | *(VAT on)* |

- Every statement works for a month, a quarter, a year or a custom range, with the previous period
  beside it.
- **Every figure opens the entries behind it,** and every entry opens its sale, payment or bill.

**Needs attention** lists the records that could not post cleanly:
- unknown cost;
- an expense paid from *Not sorted yet*;
- a loan repayment not split;
- statement lines not sorted;
- a drawer holding more cash than it usually does with no record of it being banked.

## 9. The accountant

- **Invited** by the owner from Staff, by email, with the role *Accountant*. Seats are free.
- **Sees:** Books, Reports, Customers, Suppliers, Expenses, read-only. No till, shifts, stock edits
  or settings.
- **Posts journals:**
  - a date, lines (account, debit or credit), a reason, and an optional attachment;
  - it must balance before it saves;
  - shown as **Accountant's entry**, with a name;
  - it is reversed, never edited.
- **Exports** for any period:
  - the general ledger, the trial balance and the journals, as CSV in a generic layout (date, entry
    number, account code, account name, debit, credit, description, source);
  - statements as PDF.
  - *Matching Xero's and QuickBooks' own import templates is Q-13.*

## 10. How it is built

- **Journals:** `books_journals/{id}`.
  - The id is derived from the source (`sale_<saleId>`, `sale_<saleId>_rev`), so posting twice is
    impossible.
  - Fields: source type and id, `occurredAt`, `businessDate`, `postedPeriod`, lines, kind (`auto`,
    `owner`, `accountant`, `opening`), author, reason, and the journal it reverses.
- **The posting engine:**
  - server triggers on each source collection, plus a sweep job for anything missed;
  - pure functions from a record to its lines, with shared test vectors like the return offsets;
  - **refuses an unbalanced journal.**
- **Balances:** `books_balances/{account}_{period}`, updated in the same transaction. Statements
  read balances, not journals, so a year's balance sheet is a few dozen reads.
- **Checks** run daily and are monitored like the balance invariant in the spec's rollout:
  - *Customers owe us* equals the sum of customer balances;
  - *We owe suppliers* equals the sum of supplier balances;
  - *Stock* against the stock valuation, where differences are expected for unknown costs and are
    listed.
- **Rules:** journals are written by the server only. Accountant journals go through a callable.
  The new role is added to `TenantRole` and to the rules.
- **Offline:** the books are server figures, shown read-only with an "as at" time when offline.
- **D-28 switch:** the return arithmetic on server and device, the shared vectors, daily metrics, and
  the rule pinning a return's date to its sale's. It ships with I-2.

**Order inside Phase I:**
- **I-1:**
  - the chart;
  - the posting engine for every row in §3.2;
  - *Paid from* on expenses (F-1);
  - the trial balance and general ledger;
  - *Needs attention*;
  - CSV export.
- **I-2:**
  - setup and opening balances;
  - money accounts and the owner forms;
  - the three statements;
  - the Books icon;
  - the D-28 switch.
- **I-3:** statement import, matching, sorting, rules and reconciliation.
- **I-4:** month close, the Accountant role and accountant journals.
- **I-5:** equipment wear and loan splits.
- **I-6:** VAT, after the tax adviser.

## 11. Open questions

- **Q-01 Start date.** Is the books' start date also the D-28 return switch? *Recommended: yes, one
  cut-over.*
- **Q-02 Who opens Books.** *Recommended:*
  - owner, admin and accountant;
  - managers can record *Move money* (banking the cash) and nothing else.
- **Q-03 Haggled prices** (agreed-price rulings). Is the difference between list and agreed price a
  *Discount given*? *Recommended: yes, so discounts show what haggling costs.*
- **Q-04 Typed cost on one-off lines** (D-32). *Recommended: profit display only, not posted.* The
  real cost arrives as a bill or an expense, and posting both would count it twice.
- **Q-05 Goods sent back to a supplier.** *Recommended: a small record in Suppliers (I-1 or later):
  Dr *We owe suppliers*, Cr *Stock*.*
- **Q-06 Extra production costs** (packaging, labour). Are they added to the batch's stock value, or
  left as running costs? *Recommended: left as running costs.*
- **Q-07 Restock without a bill.** *Recommended: it posts to *Not sorted yet* and asks for a bill or
  an expense.*
- **Q-08 The cash drawer.**
  - Is it one account per shop, or one per till?
  - Should shift close ask where the cash went (banked, safe, owner)? *Recommended: one per shop, and
    no question at close.* A *Needs attention* nudge is enough.
- **Q-09 Year-end adjustments after the months are closed.** *Recommended: a separate adjustments
  period at the end of each year, open only to the accountant.*
- **Q-10 VAT class per product** (standard, zero-rated, exempt). Needed only when VAT is on, and
  confirmed with the adviser.
- **Q-11 Loyalty.** Revisit when redemption is designed.
- **Q-12 Statement formats.**
  - Confirm the M-Pesa business export layout.
  - Which banks to support first?
- **Q-13 Export layouts.** Generic CSV only, or Xero and QuickBooks import templates as well?
- **Q-14 Damaged returns** (returns hub question). The cost goes to *Stock lost or damaged*, as in
  §3.2?

- **Q-15 Expenses and supplier payments from the drawer** (F-5). *Recommended:*
  - *Cash drawer* is offered only to someone with an open shift, and it lowers that shift's expected
    cash, as a return handed back does (since 2026-10-09);
  - without an open shift, cash comes from *Cash kept aside*, a second cash account outside the
    drawer.

  This settles hub question 10 the same way. *Move money* out of the drawer while a shift is open (a
  cash pickup) is the same case, and lowers that shift's expected cash too.

## 12. Non-goals

- Rebuilding history from before the start date (D-39).
- Editing any journal.
- Payroll, multi-currency, budgets, consolidation across shops (D-38).
- Bank feeds by live connection. Statements are uploaded.
- eTIMS (D-04).
