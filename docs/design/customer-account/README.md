# Customer account — a design, 2026-10-12

Five boards for a customer's page once the accounting work in `ACCOUNTING_WORKFLOW_DISCOVERY.md`
is built. Open [`index.html`](index.html) in a browser. Each page is self-contained HTML with no
build step.

**This is a proposal.** Nothing in `lib/` was changed to make it. The spec it draws is not approved
for implementation; these boards are meant to be part of what it is approved with.

## The question the screen is opened with

*Where do things stand with this person?* The page should answer three things in order:

- what they owe, and how much of it is late;
- what of theirs you are holding;
- whether anything needs doing.

Only owners, admins and managers open it. The route is gated on
`TenantCustomerRepository.manageRoles`. Cashiers take payments from the card menu in the
customer directory, which opens the same dialog.

Today the answer is one figure, *Owes*, in the second card, under the points and contact details.
That was enough while a customer had one balance. From Phase A they have two:

- **debt**, which can now be overdue;
- **money held for them**, which comes in three kinds: deposits on orders, money waiting for a
  manager, and released credit (D-11, D-36).

## Where it came from

- **QuickBooks Online's Money Bar.** A strip of status segments on the Sales page that summarises
  open and overdue amounts and filters the list under it
  ([Intuit help](https://quickbooks.intuit.com/learn-support/en-us/customer-topics/view-sales-transactions/01/185599)).
  Here it is scaled down to one customer: the ageing bar, and three lines under it that filter
  the Invoices tab.
- **Zoho Books' customer overview.** Outstanding receivables and unused credits are separate
  amounts
  ([Zoho KB](https://www.zoho.com/en-de/books/kb/contacts/outstanding-receivables.html)).
  Here *Owes* and *Held for them* are side by side and never netted.
- **Bank apps.** They show an available balance next to an amount on hold. That is the model
  for the three kinds of held money: committed to an order, waiting for a decision, and
  spendable.
- **[`../tables/`](../tables/)**, the sheet, ledger shape and status-by-exception rule it set
  this morning. The Invoices tab and the statement are sheets.

## The boards

| Board | What it shows |
| --- | --- |
| [On a phone](account-phone.html) | The whole page for a customer who owes, is overdue and has money held, with eight numbered notes. Then a customer who owes and holds nothing, one who holds only credit, and the toolbar menu. |
| [From 768 up](account-wide.html) | 1440: details as a strip, the account as a three-column band, and the Invoices sheet with a paid invoice opened. 834: the band in two columns, over the phone's list. |
| [Statement](account-statement.html) | The ledger with two balances, owes and held: an overpayment, its void and the corrected payment on one morning; a payment's menu; the phone list. |
| [Actions](account-actions.html) | Record a payment with *Apply to* and a preview; the snackbar and the 58 mm receipt; refund or keep as credit; void; write off; send a reminder. |
| [States](account-states.html) | Loading; a tab that cannot be read; a payment still on the phone; the page in Phase A before invoices exist; go-live day; inactive and blocked. |

Every board was rendered with headless Chrome and read back before this was written.

**The sample data is one shop on one day.** Dev Corner Shop on Thursday 12 November 2026.
Invoicing started on Monday 2 November.

- The customers are the tables board's: Mary Wambui, Kamau Njoroge, Wanjiku Mwangi,
  Achieng Atieno and Otieno Ouma, plus the harness's Jane Wanjiku.
- The staff are the harness's cast.
- Mary's order is 300 mandazi and 20 loaves for a graduation, because Dev Corner Shop bakes. The
  spec's sofa and chairs did not fit this shop.

**Mary's figures add up across every board.**

- *Owes 4,250* is made of:
  - Before invoicing: 500 left of 1,100;
  - INV-0007: 2,400, overdue;
  - INV-0019: 1,350 still due of 1,850.
- *Held 3,450* is made of:
  - a 3,000 deposit on OR-0004;
  - 450 waiting, from a return on INV-0003, which she had already paid.
- The statement's two after-columns walk from 1,100 on 2 November to those figures.

## Deliberate departures from today's page

1. **The money leads; contact details fold.**
   - On a phone the details become one line: phone, then WhatsApp receipts, points and the last
     purchase. A disclosure opens the rest in place.
   - From 768 they are a strip of captions over values.
   - Today they are a card above the money, headed by a monogram, the points and the last purchase.
2. **Debt and held money are never netted.**
   - A sentence under the held figure says so. A shop owner's first question will be "why does
     she owe 4,250 if I am holding 3,450 of hers?"
   - The three kinds of held money are listed in the order money moves through them: committed
     to an order, waiting for a decision, spendable.
3. **Waiting money is the one exception that surfaces.** It sits in an attention-washed box,
   with its reason, who verified it, and the one action that resolves it. §14 of the spec says
   it must be visible, or customers wait for refunds.
4. **Overdue is the only amber in the debt half.** *Not yet due* and *Before invoicing* are
   quiet. The bar is a summary; each line carries a glyph, a word and an amount, so colour is
   never the only signal.
5. **Invoices is the first tab, and is ordered the way payments settle it.**
   - The order: Before invoicing pinned first, then oldest due (D-03).
   - The list doubles as the explanation of where the next payment goes.
6. **Three tabs: Invoices, Statement, Purchases.** Three tabs are icon tabs by `AppTabs`' own rule.
   A fourth tab for details would scroll at 390, which is part of why details fold instead.
7. **The account's actions move under the account.**
   - *Record a payment* becomes primary, because it is the most common reason to open the page.
     It drops to secondary when nothing is owed, or the customer is inactive.
   - *Remind* shows only while something is due (D-26, D-33).
   - *Edit* moves to the toolbar, and *Mark inactive* to the toolbar's menu. Today both are
     48-tall buttons above everything.
8. ***Credit: Allowed/Blocked* becomes the terms line under the debt.** For example:
   *7-day terms (the shop's) · Credit allowed*. A block shows with a block glyph and the words,
   not a badge, because nothing on this page resolves it.
9. **The statement keeps two balances.**
   - A pair of *Change* / *After* columns for each, under a group heading.
   - A void is its own entry. The original stays, muted and struck through (D-09).
   - Times appear under dates, because same-day order matters once voids exist.
10. **Every action says what it will change before it changes it.**
    - Record a payment previews where the money goes.
    - Void lists what it undoes: the debt, the drawer, the record.
    - The confirm button names the outcome, for example *Put towards INV-0007*, never
      "Confirm".

## What the spec is missing

Drawing it turned up five gaps. Each is drawn one way and marked on its board.

1. **Where the rest of a payment goes when its chosen invoice needs less.** D-03 says a payment
   goes to the invoice the cashier chose, "otherwise" oldest first. It does not say what happens
   when the chosen invoice is smaller than the payment. Drawn: the rest goes on, oldest first,
   and only what exceeds the whole debt is held (Actions board, second frame).
2. **Waiting money that came from a payment needs a void route.**
   - D-36 lists a duplicate offline payment as a source of waiting money. It offers only refund
     or release.
   - If the second payment never happened, both are wrong: a refund hands over money that was
     never received.
   - Drawn: when the waiting money came from a payment, the decision dialog offers *Void the
     payment* first.
3. **A duplicate offline payment usually does not become waiting money.** §8.5 says it does.
   That holds only when the first payment had already cleared the whole debt. Otherwise the
   duplicate settles real debt that was never paid, and nothing flags it.
   - A server check for the same M-Pesa code or reference on two payments from one customer
     would catch most of these, now that D-12 records a reference.
   - That is new server behaviour and is not drawn.
4. **"Last reminded" needs reminders recorded.** D-26 has manual reminders, but §9 gives them no
   record. A manager will want to know whether the customer was already chased. Drawn as
   *Last reminded: never* beside the button.
5. **The payment receipt's balance.** D-24 and D-40 settle the receipt's number and channels, but
   not whether it prints the balance. The sales receipt does (CF-5). Drawn with *Owed before*
   and *Owed after*, and a line saying these are the phone's figures. Offline, another payment
   may already be on its way to the server.

## Open questions

1. **Finding 1:** does the rest of a payment for a chosen invoice go on oldest first?
2. **Finding 2:** offer *Void the payment* from the waiting-money dialog?
3. **Spec question 15** (spend released credit on an invoice) and **question 10** (a payout
   needs the manager's own open shift) are drawn as the spec recommends. Confirm both.
4. ***Send a statement*** in the toolbar menu is not in the spec. It is marked **new**. Keep it or
   drop it?
5. **A payment still on this phone.** The States board shows a callout naming a queued payment.
   It needs the page to read the pending-call queue for this customer, which no screen does
   today. Keep it or drop it?
6. **Details folding on a phone.** Is one line plus a disclosure enough, or should KRA PIN and
   notes stay visible?
7. **Ageing lines as filters** from 768 up. Useful, or a second way of doing what the chips do?

## What it takes, and what is not a pure restyle

Almost none of this is a restyle: it draws data that does not exist yet. It splits by the spec's
phases.

| Phase | What on these boards it ships | Needs |
| --- | --- | --- |
| Layout only, any time | Money first; details fold; *Edit* to the toolbar; *Mark inactive* to its menu; *Credit allowed* into the terms line; statement as the tables board's ledger | Nothing new. `CLAUDE.md` rule 1 holds: no repository call or state logic changes. |
| A — corrections, held money | The held half with *Waiting* and *Credit*; *Refund or keep as credit*; void; write-off; reference on a payment; the receipt; the statement's held columns and new kinds. The page is drawn in this form on the States board. | `waitingMinor`, `creditMinor`, activity kinds, the five Phase A callables, the PY counter |
| D — quotes and orders | *Deposit on an order* in the held half | `orders.depositHeldMinor` |
| E — invoices and allocation | The ageing bar and lines; the Invoices tab; *Apply to* and its preview; *Remind*; terms | `invoices`, `openDueSchedule`, `paymentTermsDays`, `sendPaymentReminder` |

**Phase A ships no *Apply to* field.** With no invoices, payments go to the one balance, as
today. The field appears in Phase E.

**The preview in *Record a payment* is new device logic.** It applies the allocation order to the
customer's cached `openDueSchedule`. It must stay labelled as an estimate: the server does the real
split, inside its transaction (D-03).

## Components and tokens

**Reused as they are:**

- `AppScaffold` (title, subtitle, toolbar action), `AppCard`, `AppButton` in its four tiers,
  `AppIconButton`;
- `AppTabs` (icon tabs at three, the switch at two), `FilterChipBar`;
- `AppDialog`, `ConfirmDialog`, `ChoiceCardGroup` for the waiting-money choice, `AppTextField`,
  `AppSelect`;
- `Callout`, `StatusBadge`, `AppSnackBar`, `ErrorState`, `EmptyState`, `SkeletonLine`;
- `RecordSheet` (`lib/ui/record_sheet.dart`, built for Shift history) for Invoices and the
  statement from 1024 up, with no group strips, no caption under it and evenly spaced columns
  (the 2026-10-13 rulings). Below that they keep the phone's list, by the 2026-10-12 ruling that
  tables are for large screens only.

**New compositions, made only of existing roles:**

- **The money bar:**
  - segments in `status.attention` (overdue), `text.secondary` (not yet due) and a hatch of
    `text.tertiary` over `border.strong` (before invoicing);
  - on a `border.subtle` track.
- **The ageing line:** glyph, `labelMedium` word, `caption` detail, `numericBody` amount.
- **The held row:** the same, with a two-line caption.
- **The waiting box:**
  - the attention wash and edge at `radius.md`, 16 in;
  - its caption is `text.secondary`, not tertiary. Tertiary on the wash is 4.26:1, under 4.5.
- **The account band from 768:** two money columns and a 296-wide actions column, hairlines
  between.

**New layout tokens**, beside the tables board's:

| Token | Value | Why |
| --- | --- | --- |
| `layout.moneyBar` | 8 | The bar's height. `space.8` by value, named so it cannot drift, as `layout.tableMeter` is. |
| `layout.moneyBarGap` | 2 | The gap between segments. The spacing scale starts at 4, which reads as three separate bars at this height. |
| `layout.accountActions` | 296 | The actions column of the band at 1024 and up: a 248 button and its 24 insets. |

## Accessibility

- **Contrast,** worked out from the token hexes:
  - On `surface.raised`: `text.tertiary` 5.27:1, the attention amber 9.08:1, mint 10.4:1.
  - On the waiting box (attention wash over raised): white 12.3:1, `text.secondary` 7.88:1,
    amber 7.33:1.
  - On a dialog (`surface.overlay`): `text.secondary` 8.67:1, `text.tertiary` 4.68:1, problem
    red 4.51:1.
  - On a selected choice card (ok wash over overlay): `text.secondary` 6.92:1, and the radio
    ring 3.74:1 (3:1 is the bar for a control's edge).
- **Not by colour alone:**
  - every ageing segment has a line with a glyph and a word;
  - overdue is a `StatusBadge` with a glyph;
  - a voided entry is struck through and says *voided*;
  - every negative has a real minus.
- **Targets:** every button, menu item, chip target, tab, disclosure and ageing line is 48.
- **Screen readers:**
  - The account is read as two sentences: "Owes 4,250 shillings, 2,400 overdue" and "Holding
    3,450 shillings for them, 450 waiting for your decision".
  - The bar is hidden from them, because the lines say the same thing.
  - The snackbar is a live region, as `AppSnackBar` already is.

## Motion

- **The details disclosure and an opened invoice row are spatial.** They open on a spring and
  reverse from wherever they are, as `CLAUDE.md` requires.
- **The ageing bar does not animate** when figures change. A balance that moves because a
  payment arrived should not look like a celebration.
- **Nothing here is on the sale path.**
  - A payment is written to the queue first; the snackbar comes after.
  - Opening the Refund-or-credit dialog writes nothing until its confirm button is pressed.

## What these files are

They are HTML mockups. They do not prove the app runs, and they cannot show motion. The figures
are worked by hand from the spec's rules, not by the allocation code, which does not exist.

The boards were built from shared sources (one stylesheet and one glyph sprite) by a small
script, so every page carries identical styles. Each page is self-contained, and it is safe to
edit it directly.
