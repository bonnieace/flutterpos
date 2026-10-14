# Cross-check: two accounting discovery documents

**Compared:**
- **A**: `ACCOUNTING_WORKFLOW_DISCOVERY.md`, from this session. Its decisions are numbered `D-01` to `D-33` and the earlier credit rulings `CF-1` to `CF-7`.
- **B**: the other agent's discovery document, pasted on 2026-10-12. Its decisions are numbered `D01` to `D62`.

**Same repository and commit:** `bonnieace/flutterpos` at `4a767dc`. Both documents were static reviews; neither ran any tests.

**What this checks:**
- the same question answered differently in the two documents;
- questions answered in only one of them;
- contradictions inside each document;
- statements about the code that the two disagree on, re-checked against the source.

**Severity:**
- **High**: changes money semantics or the data model, or reverses an earlier ruling.
- **Medium**: changes behaviour users will see.
- **Low**: wording, defaults or details.

---

## 0. Rulings so far (developer, 2026-10-12)

| Conflict | Ruling | Matches |
|---|---|---|
| C1 Credit limits | No credit limits | A (CF-1) |
| C2 Overpaid or excess money | A manager decides: refund or credit; it does not become spendable automatically | B (D15) |
| C2/C18 follow-up: deposits | A deposit taken against a quote or order goes to **that order's** invoices automatically, first invoice first. Only money beyond what is owed waits for a manager. | B (D04), and fixes A's hole A2 |
| C4 When a return takes effect | When it is filed (today's behaviour) | A (D-28) |
| C5 Which period a return lands in | The original sale's day | A (D-28) |
| C7 An order record between quote and sale | Yes: accepting a quote creates an order | B (D01–D03, D26) |
| §2 Bookkeeping scope and order | **In scope, built last.** Order: corrections (voids, payouts, payment receipts) → quotes and orders → invoices and allocation → supplier debt (single-entry, built like customer credit) → double entry (chart of accounts, opening balances, journals posted from existing records, statements; money accounts, VAT accounts and fixed assets come with it). Everything before it is built so it can be posted later: no edits, reversing records, the money used recorded on every payment, linked records, deposits and debt kept apart. | Neither: A excluded bookkeeping, B built it first |
| §2 Stock costing | **Moving average.** The server updates a product's cost when stock arrives (supplier deliveries, production); the till still freezes that cost on each sale line, and profit arithmetic is unchanged. FIFO only if an accountant requires it. | Neither: A kept latest cost, B chose FIFO (D57) |
| §2 Branches | **One tenant per shop**, kept separate. Optional later: a combined report for owners across the shops they own. No shared books, no parent business. | A |
| C7 follow-up: is an order always needed? | No. A quote bought in full in one go converts straight into a till sale. An order is created only for a deposit, a later delivery, or delivery in parts. | Neither (new) |

| C3 Keeping part of a deposit | Allowed (manager; a cancellation-fee sale) | A (D-15) |
| C6 Split payments | Till only; several payments cover the rest | A (D-29) |
| C9 Correcting an issued invoice | Manager correction or replacement, recorded as a `kind: correction` return; the sale is never edited | Neither: B's intent, A's mechanism (D-44) |
| C10 Payment terms | Business default plus optional per-customer terms | B (D-07) |
| C13 Short stock | Partial delivery covers it; no hard cap | A (D-48) |
| B D51 Condition of returned goods | Manager marks sellable or damaged; damaged = restock plus a damage adjustment | B (D-45) |
| B D27 Service revenue | No change: counted when rung up, at completion | A (D-46) |
| B D23 Over-delivery | Flagged; manager decides: charge, recover or write off | B (D-47) |

All held items are now ruled. A money account on every payment (C14) and B's bookkeeping details come with Phase I.

---

## 1. Headline

1. **The two documents are different projects.** B includes full bookkeeping, branches with shared books, first-in-first-out (FIFO) stock costing, VAT accounting, supplier bills and money accounts. A excludes all of them. **A never asked about any of these.** I treated them as out of scope without putting the question to you, so that is a gap in A, not a decision. Your original brief said not to expand into double-entry accounting "unless I explicitly choose that scope", and in B's interview you chose it.
2. **Settle the scope first (§2).** That choice decides roughly half of the conflicts below.
3. **Within the area both documents cover, 19 questions were answered differently or cover overlapping ground (§3).** Five are High:
   - credit limits;
   - automatic store credit;
   - when a return takes effect;
   - which period a return lands in;
   - whether an "order" record exists.
4. **A has two logic holes that B gets right (§7, items A1 and A2):**
   - An accepted made-to-order job delivered after its quote's expiry would be charged current prices.
   - A deposit would pay off the customer's older, unrelated debt before the order it was taken for.
5. **Three of B's code findings check out against the source (§8, items V1 to V3).** A missed two of them and had the third as unverified.

---

## 2. Scope: decide this first

| Topic | A | B | Was it asked? |
|---|---|---|---|
| Bookkeeping (chart of accounts, journals, trial balance / general ledger, P&L, balance sheet, cash flow) | Non-goal (§13) | In scope (D28, D31, D35, D37, D56) | A: **no**. B: yes |
| Supplier bills, amounts owed to suppliers, matching deliveries to bills | Non-goal | In scope (D34, D59) | A: **no**. B: yes |
| Money accounts (separate cash, M-Pesa and bank), transfers, reconciliation | No; three payment methods plus an optional reference (D-12) | In scope; an account is chosen on every payment (D36, D38) | Both, with different answers |
| Stock costing method | Unchanged: cost is frozen on each sale line at the latest cost | FIFO (D57, D60) | A: **no**. B: yes |
| VAT | Later; optional fields reserved but unused (D-04) | VAT amounts and accounts now, eTIMS later (D30, D54) | Both, with different answers |
| Branches and parent business with shared books | None; multiple branches is a non-goal | In scope (D39–D42, D45, D46) | A: **no** (I skipped it because the code has no branches). B: yes |
| Fixed assets and depreciation | None | Asset form plus depreciation journals (D55) | A: **no**. B: yes |

**There are three ways to go:**
- **A's scope now, B's later.** Operational invoicing first; bookkeeping becomes a later project built on the same records.
- **B's scope now.** The quotes and invoices you started with arrive in B's Phases E and F, after full books, FIFO and payments (Phases A to D).
- **A mix.** For example, keep B's money accounts but drop branches.

**What B's scope does to A's compatibility promise.** A's D-31 says new versions add fields and older installed builds keep working. B's changes to return timing (C4) and its parent-business layer cannot be done that way. Choosing B's scope means revisiting D-31.

---

## 3. Same question, different answers

| # | Topic | A | B | Severity | What goes wrong if both stand | Suggested resolution |
|---|---|---|---|---|---|---|
| C1 | Credit limits and overdue customers | CF-1: no limits, a manager can block a customer instead. D-26: an overdue warning that never blocks | D16: overdue or over-limit needs manager approval online. D19: offline, the cashier proceeds with a reason. D20: a stale limit is flagged | **High** | B brings back limits you withdrew on 2026-10-02. It also needs an approval step at the till that neither document designs | Pick one. If B: define how a manager approves at the counter and what "limit" means again |
| C2 | Overpaid or excess money | D-03: leftovers become money on account automatically. D-14: the till can spend it | D15: a manager decides between refund and credit; no automatic credit the customer can spend | **High** | Under A, a duplicate repayment recorded on two offline phones becomes spendable before a manager notices it | Recommend B's rule for overpayments. Keep "use money on account" for deposits, which are money taken on purpose |
| C3 | A cancelled order: may the shop keep part of the deposit? | D-15: yes, as a "cancellation fee" sale paid from the account | D08: refund or credit only; the fee option was rejected | Medium | Opposite answers to the same question | Pick one |
| C4 | When a return takes effect | D-28 keeps today's behaviour: revenue is netted when the return is **filed**, still pending. D-09: a manager can reject it | D50: no effect on sales or debt until a manager **approves** it | **High** | B changes the daily figures, the shared device/server rounding tests and reconciliation. Installed builds still net pending returns on their own screens | Pick one. B's rule is cleaner but is a migration, not a small change |
| C5 | Which period a return lands in | D-28: the original sale's day; past days can change | D29, D33, D52: the current open period; closed periods are locked | **High** | Locked periods (B) cannot coexist with restating past days (A) | Follows from the scope choice: locked periods only make sense with B's bookkeeping |
| C6 | Split payments | D-29: at the till only, as the last phase. Repayments and deposits are one method each; several payments cover a split | D14: on every sale, deposit and repayment, with one receipt listing each method; built early | Medium | Different scope and order. Splitting every payment changes the payment record that A keeps unchanged | Pick one |
| C7 | Is there an "order" record between the quote and the sale? | No. The quote or pro-forma tracks quantities converted (D-02, D-19) | Yes. Accepting a quote creates an **Order**, with fulfilment and service-completion records (D01–D03, D26, D27) | **High** (data model) | Two different entity models for the same workflow | B's Order fixes A's hole A1. Recommend adopting it in A, or "quote becomes accepted and locked", which is lighter |
| C8 | Price on accepted work delivered later | D-08: quoted price honoured until expiry, current prices after | D10: price fixed once accepted; only an authorised revision changes it | Medium | See A1: A charges made-to-order customers new prices after expiry | Adopt B: expiry limits *acceptance*, and acceptance locks the price |
| C9 | Correcting an invoice already issued | Not asked. A's design: an invoice cannot be voided; fix it through a return or write-off | D49: manager correction, reversal or replacement, linked to the original. D22: manager reversal of duplicate sales | Medium | A has no way to replace a wrong invoice | Ask once. B's linked reversal can be built as a return of type "duplicate" so the sale itself stays unchanged |
| C10 | Payment terms | D-07: a business default, editable per invoice | D13: business **and per-customer** defaults, with authorised override | Low | — | Pick one; per-customer terms are cheap to add |
| C11 | Quote expiry default | D-18: typed on every quote, required, no default | Its "proposed defaults" list makes validity a setup choice | Low | B's default contradicts your "typed every time" | Keep D-18 unless you changed your mind |
| C12 | When a customer record is required | D-16: when a deposit or credit sale needs one | Its workflow section: at acceptance, because an order needs a saved customer | Low | — | Follows from C7 |
| C13 | Not enough stock to fulfil an order | Stock never blocks a sale (existing rule) | D12: supply what is available, then leave the remainder or cancel it | Medium | If B means "fulfilment is capped at stock on hand", that cannot be enforced offline and contradicts the till's never-block rule | Ask what D12 means: capped, or simply partial delivery |
| C14 | What each payment records | D-12: method plus optional reference | D38: an explicit money account chosen on every payment | Medium | Slows every counter sale (see B1) | Pick one; if B, add per-method defaults |
| C15 | Offline numbering and what the customer sees | D-10: server numbers on sync; offline quotes print "Draft"; payment receipt numbering left open (recommendation: a number issued by the phone) | D43: final business-wide series with a temporary ID offline. D47: an offline acknowledgement for orders and payments; invoices shared only after sync | Low | Mostly compatible | B's acknowledgement answers A's open question 2; align the wording |
| C16 | Sending invoices automatically | Open question 4, recommendation: send automatically | Proposed default: do not send automatically | Low | Opposite recommendations, and you decided neither | Decide |
| C17 | Thermal printing | D-23: payment receipts print on the till's receipt printer | D44: "PDF/print"; whether that includes the thermal printer is unclear | Low | — | Confirm that thermal is in |
| C18 | What a deposit pays for first | D-05 links the deposit to the pro-forma, but D-03 and D-30 allocate oldest first, with old balance first | D04: the deposit goes to its own order's first invoice | Medium | See A2: A's sofa deposit pays old, unrelated debt | Adopt B's rule |
| C19 | Returning a credit sale the customer has already repaid | Open question 1, recommendation: the counter refund is capped at what was paid at the sale; the rest goes to the account, and a manager pays it out | D06: refund or credit, with a manager approving any cash refund | Low | Compatible: B answers A's open question | Confirm B's answer closes question 1 |

---

## 4. Answered only in B (A never asked)

These are B decisions with no counterpart in A, to confirm or reject. Scope items are in §2.

- **D21:** no lock stopping two phones fulfilling the same order; recovery afterwards instead.
- **D22, D23:** a duplicate entry is reversed by a manager. Genuine over-delivery is charged, physically recovered, or written off as a loss. This partly answers A's open question 9.
- **D26:** staff record who accepted a quote and when, with an optional reference. This answers A's open question 5.
- **D27:** service revenue is recognised when the work is completed.
- **D51:** a manager decides whether returned goods are sellable or damaged. **A gap.** Today every verified return goes back into stock as sellable.
- **D58:** an event that syncs late keeps its own date but posts in the open period.
- **D61:** quantity-only stock entries are allowed, and their valuation is marked incomplete. Compatible with A's D-32.

---

## 5. Answered only in A (B is silent)

These are A decisions that B neither confirms nor contradicts, to carry over if B's scope wins:

- **D-06:** a custom line takes a typed price and its own description. B covers services but not this.
- **D-13:** the report row becomes "Sold on credit".
- **D-14:** the till offers "Use money on account". This conflicts in spirit with B's D15 (see C2).
- **D-16:** a quote can carry just a typed name and phone.
- **D-20:** management sees quantities on open quotes beside stock.
- **D-21:** letterhead fields: phone, address, business KRA PIN, payment instructions, terms.
- **D-23, D-24:** payment receipts on thermal, and every payment receipt sent automatically.
- **D-30:** old balance is settled first.
- **D-31:** older builds keep working.
- **D-32:** cost on a custom line is optional and visible only to roles that see profit.
- **D-33:** reminders are sent by manager and above.

---

## 6. Open in both

- The default number of days before an invoice is due.
- How payment receipts are numbered when taken offline (B's acknowledgement is close to an answer).
- Whether invoices are sent automatically (C16).
- Where invoices sit in the app's navigation.
- WhatsApp message costs and who pays them.
- Confirming eTIMS and VAT obligations with a tax adviser. Both documents defer eTIMS; B also gates VAT on this.
- Whether a return on an invoiced sale prints as a credit note.

---

## 7. Logic holes inside each document

### In A (this session)

- **A1 — High — Accepted made-to-order work loses its price at expiry.**
  - The rules involved: D-08 honours the quote only until expiry, D-19 allows conversion in parts, and D-01 targets made-to-order work.
  - Example: a sofa quoted on 1 Oct, valid until 14 Oct, deposit taken, delivered 30 Oct. The delivery sale charges current prices.
  - Fix: expiry limits acceptance; accepting, or taking a deposit, locks the price for every later conversion. This is what B's D10 does.
- **A2 — Medium — A deposit pays the wrong debt.**
  - D-05 links the deposit to its pro-forma, but D-03 and D-30 allocate oldest first, with old balance first.
  - Result: Wanjiru's sofa deposit pays off her old unrelated balance, and the sofa invoice stays fully owed.
  - Fix: a deposit goes to invoices from its own quote first, then oldest first. This is what B's D04 does.
- **A3 — Medium — Duplicates become spendable credit.** Under D-03 and D-14, an accidental duplicate repayment becomes spendable money on account before any manager has reviewed it. See C2.
- **A4 — Low — Rejecting a return assumes the refund never happened.** D-09 lets a manager reject a pending return and undo its refund expectation. If cash really was handed over, for example against the wrong sale, the drawer then shows a surplus. The rejection needs an option to keep the refund and re-file the return against the right sale.
- **A5 — Gaps.** A never asked about bookkeeping, branches, stock costing, supplier bills, the condition of returned goods, or correcting an issued invoice. The original brief listed bookkeeping, branches and invoice correction as topics.

### In B (the other agent)

- **B1 — Medium — The till gets slower.** D38 requires an account to be chosen on every payment, while §1 and §4 promise to "preserve fast checkout". You rejected the "one account per method" option, so every counter sale gains a choice.
- **B2 — High — Its credit rules depend on limits that no longer exist.** D16, D19 and D20 rely on credit limits that were withdrawn on 2026-10-02. B's own audit row about two devices mentions stale limits, but the till enforces only the block toggle today. No manager-approval mechanism at the till is designed either.
- **B3 — Medium — "Supply what is available" is undefined.** D12, read alongside D07 (never reserve) and D17 (everything captured offline), cannot be enforced against stock offline. Either it means simple partial delivery, which is already D02, or it is a cap that stale phones will apply wrongly.
- **B4 — Low — The numbering decision is ambiguous.** D43 says "one business-wide sequence", and B itself asks whether that means one sequence for all document types together.
- **B5 — Medium — The return change is not compatible with installed builds.** D50 makes pending returns have no effect, but installed builds net pending returns on the device. That logic is pinned by `return_offset_vectors.json`, so devices and server will disagree until every phone updates. B says old readers are preserved but does not address this.
- **B6 — Medium — VAT now, eTIMS later.** With D54 (VAT now) and D30 (eTIMS later), documents would carry VAT figures without being eTIMS invoices. B flags this in its blocking gate 1, but the two decisions pull against each other.
- **B7 — Sequencing, not a contradiction.** B's roadmap builds full books, FIFO and payments (A to D) before quotes (E) and invoices (F), so the features you started with arrive last.

---

## 8. Code claims checked against the source

| # | Claim | A | B | Result from source at `4a767dc` |
|---|---|---|---|---|
| V1 | A part-paid credit sale with no payment method recorded | Missed | "High: partial-credit schema mismatch" | **Confirmed.** `firestore.rules:169-170` accepts a credit sale with no `creditPaidTender`. `credit.ts:77` then reads it as not credit: no debt is charged, and the whole total is expected in the drawer as unattributed money. The app cannot produce such a sale itself (`checkout_cart_panel.dart:3623`, `checkout_sale.dart:159`), so only a modified client can. **Low–Medium** rather than High. Fix: require `creditPaidTender` in the rules when `creditOwedMinor < totalMinor`. |
| V2 | Stock decrement without a sale | Only the unchecked amounts (R1) | "compatibility direct decrement exists" | **Confirmed.** `firestore.rules:368-371` keeps an older-build branch that lets any active staff member lower any product's quantity with no sale (`activeStaff` only). Reconciliation reports the resulting shortage. **Medium**, insiders only. Fix: retire that branch once no build uses it. That depends on D-31 and on knowing which builds testers run. |
| V3 | The owing list stops at 500 customers | Unverified | "no completeness marker" | **Confirmed.** `loadOwing` (`customer_credit.dart:302`) returns a plain list and stops silently after 10 pages of 50. The Customers total (`customer_directory_panel.dart:146`) then understates what is owed. **Low** for small shops. |
| V4 | Latest cost, not FIFO | Same | Same | Agreed. `supplierDeliveries.ts:36`: "the latest event that states a cost sets" the product's cost. |
| V5 | Repaid credit sale, then returned | Medium (D1) | High | Same mechanism, different severity. Medium stands: the balance is correct, but the money has no way back to the customer. |
| V6 | "Stale limits" when two devices sell | — | Two-devices audit row | **Inaccurate.** No limit is enforced at the till since 2026-10-02; only a block can be stale. |
| V7 | Return timing listed as a "High" risk | Design choice (R4) | Listed as a defect | A product decision, not a defect: the code says so (`returnOffsets.ts:17`). B's change is C4/C5. |

B's other references (`net_profit.dart`, `registerSaleReceipt` in `jobs.ts:571`, and the code each S-reference points to) exist and match what B says they do.

---

## 9. Suggested order to resolve

1. **Scope (§2).** A's scope now with B's later, B's scope now, or a named mix.
2. **The High items that change the data model:** C7 (order record), C4 and C5 (return timing and period), C1 (limits), C2 (automatic credit).
3. **Fix A1 and A2** in whichever document survives. Both have B's answer ready.
4. **The Medium items:** C3, C6, C8, C9, C13, C14, C18, then B1, B3, B5 and B6.
5. **The Low items and the open-in-both list (§6).**

Once you choose, I will update the surviving document to match: decisions, data model, phases and checklist.
