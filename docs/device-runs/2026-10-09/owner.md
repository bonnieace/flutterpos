# Owner device run — 2026-10-09

**Who:** `bigxman81@gmail.com` ("John Doe"), owner of **Smartcom**.
**Where:** Android emulator `pos_test` (Pixel 6, API 35, headless, Impeller off), **against SIT**
(`multitenant-pos-b8326`). Debug build of `4db0b1a` (= release 1.0.12+7).
**When:** 2026-10-09 09:56 – 10:20 EAT, straight after the cashier run (see `cashier.md`). The
owner reviewed the cashier's work.

Everything below was seen on the device unless it says "from the code".

## Data this run left on SIT

- **Verified** the cashier's return on `CT-EC7-20261008-0001`, which restored 1 × tallow 30ml.
- **Accepted** the cashier's stock count, which corrected Tallow 60ml from -1 to 0.
- Recorded a **KES 600 cash payment** from OfflineTest (debt 3600 → 3000).
- Created product **DeviceRunTest** (cold drink, sells at 10, costs 20, no size) and then
  **retired** it. It's still in the catalog as retired.
- Opened the Register once. That adopted the owner's already-open shift; I didn't sell anything.
- **Not done on purpose:** adding a business, inviting staff, changing currency, saving branding,
  receiving deliveries, recording production, or saving printer/WhatsApp/Email settings. Each of
  those writes real config or sends real messages on SIT.

## Summary: what to fix first

| # | Severity | Finding |
|---|---|---|
| O1 | **High** | **"Paid by" drops a credit sale's part-payment** (same bug as cashier C3). Here too, the 10-08 rows sum to 92%. |
| O2 | **High** | **The audit trail has gaps.** From the code: stock-count acceptance and customer payments write **no audit row at all**. Return verification does write one, but Logs didn't show it (see 12). |
| O3 | **High** | Verifying a return **always restocks**. "Spoiled" and "Damaged" returns go back into sellable stock, with no write-off path. |
| O4 | Medium | **"Open a shift before selling."** blocks a debt repayment while the owner *has* an open till, until the Register has been opened on this device. |
| O5 | Medium | **Pending returns and old stock counts aren't surfaced.** Returns opens on today, and a count from 10-05 is still "Needs review". |
| O6 | Medium | **Raw staff document IDs** show in the UI ("mziza (staff_ThkLe1BTto2uFRSMvPH1IxUhgN6n)"). |
| O7 | Medium | Stock can be adjusted **below zero** with no warning (Damage 5 at stock 0 → -5). |
| O8 | Medium | A **loss-making price** (buying 20 > selling 10) is accepted with no warning. |
| O9 | Low–Med | "Store performance is **down 100%** today" every morning: a day that has just started compared with all of yesterday. |
| O10 | Low | Copy and polish (see "Smaller things"). |

---

## Flows walked

### 1. Sign-in

- **Wrong password:** *"That email address and password do not match an account. Check both and try
  again."* It doesn't reveal which part was wrong, and it clears as soon as you edit. Good.
- Hiding the keyboard re-centres the login layout, so the Sign in button moves under your finger.

### 2. Home (O9)

- **18 tiles:** Register, Sales, Returns, Customers, Inventory, Stock counts, Suppliers, Production,
  Expenses, Reports, My businesses, Printer, WhatsApp, Email, Configs, Staff, Shift history, Logs.
- **O9:** at 09:58 the greeting said *"Store performance is down ↘ 100% today."* It compares a day
  that has barely started with the whole of yesterday, so every morning reads as a disaster.
- **Figures:** Today's sales —, Transactions —, Shifts **0** opened today, Profit —. Meanwhile My
  businesses says *"Till: Open · John Doe"*: the owner has a till open from an earlier day, which
  "0 opened today" doesn't reveal.

### 3. My businesses (new in 1.0.12)

- **Reached two ways:** from the business name in the top bar ("Smartcom ⌄") and from the tile.
- **The receipt:** hookah logo, SMARTCOM, "elevate your lifestyle", TODAY —, Sales —, **Till: Open ·
  John Doe**, You: Owner, the OPEN NOW stamp, and Edit details. It works as designed, and the till
  line correctly picks up a shift opened on an earlier day.
- **Add business sheet**
  - The receipt fills the top of the sheet ("YOUR BUSINESS / TODAY KES 0 / Sales 0 / Till Closed /
    You Owner") with the torn edge, and **KES is preselected**.
  - Submitting with no name gives *"Enter a business name between 2 and 100 characters."* I didn't
    create a business.
- **Edit details** → Business details (logo, Replace logo, background-removal wand, delete, Position
  and zoom, Brand name, Slogan, Save branding). Back returns to My businesses. Good.
- **Glitches**
  - After coming back, the receipt was briefly drawn narrower, as if its pressed state stuck.
  - Once, the app-bar back arrow didn't respond; the system back key worked.

### 4. Returns (O3, O5, O6)

- **O5:** it opens on **today** ("No returns on 2026-10-09"). The cashier's pending return from last
  night appears nowhere: no home badge, no bell, no cross-day "pending" list. The All / Pending /
  Verified filter only works per day. The empty copy *"Try another day, or every standing."* reads
  oddly.
- **On 10-08 with Pending:** the card shows the recorder as **"mziza (staff_ThkLe1BTto2uFRSMv…"**
  (O6).
- **Verify**
  - *"Restore this stock? This verifies the return and adds 1 × tallow · 30ml back to stock. It cannot
    be undone from this app."*
  - The confirm button is **truncated ("Verify and re…") and red**: a destructive style for a positive
    action.
  - The result, *"Verified this return and restored 1 unit."*, is good.
- **O3:** verifying always restocks. With reasons like *Spoiled or expired* or *Damaged or broken*,
  the owner needs "verify, don't restock" (a write-off), or spoiled goods become sellable stock again.

### 5. Stock counts

- **Screen:** Counts / Settings tabs, Count stock, and Standing / Staff filters. The subtitle is
  truncated ("What was counted, and how it differed from th…").
- **The cashier's count had arrived:** "Whole catalog · 2026-10-09 · mziza
  (staff_ThkLe1BTto2uFRSMvPH1IxUhgN6n) · 1 product differs · 1 unit apart · 3 of 3 · Needs review".
  The full raw staff ID is shown (O6).
- **O5:** a count from **2026-10-05** (by John Doe, 2 products, 88 units apart) is still "Needs
  review" four days later, with no nudge.
- **Count detail:** "Tallow — Counted 0, Books said -1, **+1 over**". There's **no size**, so you
  can't tell which Tallow, and "+1 over" is red.
- **Accept**
  - The dialog says *"…moving **1 units** in total."*, a plural bug.
  - The result, "Accepted. 1 product corrected." with a green callout, is good.

### 6. Customers (O4)

- **List:** Customers / Loyalty tabs, Add customer, search, Active filter.
  - DeviceRun has 30 points (it was 40; the return took 10 back, which is correct) and **no WhatsApp
    label**, which confirms the consent box was saved unticked.
  - OfflineTest: "Owes 3600 · since 2 Oct · 310 points".
- **Record a payment**
  - It's **pre-filled with the whole debt** (3600), with the note *"It goes into your shift, so your
    drawer is expected to hold it when you count it."*
  - **O4 — first attempt, 5000 cash:** *"Open a shift before selling."* It says "selling" for a
    repayment, and the owner already *had* an open till (shown on My businesses). After I opened the
    Register once, which silently adopted that shift, payment worked. So Customers doesn't recognise
    an open shift until the Register has been entered on this device.
  - Overpaying (5000 against 3600) never reached validation because of O4, so it's untested.
  - **600 cash:** the dialog closes with **no confirmation**, and the **list card still says "Owes
    3600"**. The customer page shows the correct KES 3000.
- **Customer page**
  - Contents: Edit, Mark inactive, Points 310, Last bought 8 Oct, phone, "Receipts on WhatsApp:
    Agreed", KRA PIN, email, Owes KES 3000, Credit Allowed, and Statement / Purchases tabs.
  - **Statement:** "Paid back −600 · 9 Oct · Cash · then owed 3000", then "Bought on credit +600 ·
    8 Oct · CT-EC7-20261008-0002 · M-Pesa · then owed 3600".
  - The credit line says "M-Pesa" but not that 400 was paid at the counter.
  - Increases and decreases are both green.

### 7. Sales (O1)

- **Screen:** receipt search, date, All staff, export. Today shows "Revenue KES 0, 0 transactions — No
  sales yet", while the home shows "—" for the same day.
- **10-08:** "Revenue KES 5000 · 3 transactions · Paid by: Cash 3000 (60%), Card 1000 (20%), Owed on
  credit 600 (12%)". The KES 400 M-Pesa part-payment is missing (O1, same root cause as cashier C3).
- **Revenue here is net of the return (5000).** The cashier's shift close compared against gross
  (6000), hence the false "short by 1000" (cashier C2).
- Sale footers show the raw staff ID. The offline sale shows "Synced 09:53", which is nice.

### 8. Inventory (O7, O8)

- **Buttons:** Add product, Add many, Categories. **Categories is the filled primary**, more
  prominent than Add product.
- **Item menu:** View item / Adjust stock / Edit item / Retire product.
- **Add product (rebuilt form)**
  - The photo tile, name, category (with "Add new category"), selling and buying price, "Size or
    volume (optional)" and "Stock on hand (optional)" all work. The disabled button explains what's
    missing. Good.
  - **O8:** buying 20 against selling 10 saved with no warning.
  - **The 1.0.12 blank-size fix is confirmed on a device:** DeviceRunTest has no size and shows no
    blank line.
  - "Stock on hand" is **prefilled with 0**, while its helper says "Leave it blank if you have none
    yet".
- **Adjust stock**
  - Six types (Restock, Opening balance, Inventory count, Correction, Damage, Waste) and a "What an
    adjustment records" disclosure.
  - **O7:** Damage 5 at stock 0 → *"From the quantity recorded now, that is 0 to -5."* That's allowed
    with no warning. I cancelled, so nothing was written.
- **Retire product:** **no confirmation**, an instant "Retired" badge, and retired products **stay in
  the main list** because no default filter hides them.

### 9. Expenses

- This month: KES 10100 in a donut (Rent 10000 · 99%, Utilities 100 · 1%), "2 records".
- The Rent drill-down's chart with one record is **a lone dot on a line** and looks broken. The detail
  row has a red ⊖ void control.

### 10. Reports

- **Week Oct 5–11:** Total sales **18,000 KES net of returns · 9 sales · −25.0%**, plus day bars.
  - Gross profit 9930 = Net profit 9930, flagged "At most: some lines carry no cost".
  - Transactions 9 ("4.5 a day over 2 days", −35.7%). Expenses 0 for the week, which is correct: the
    rent was 3 Oct.
  - Best sellers.
- **Recent transactions**
  - **The credit sale #0002 is listed as "M-Pesa KES 1000"**, with no credit marker; only 400 of it
    was M-Pesa.
  - **M-Pesa rows use a card icon.**
  - #0001 shows **KES 4000** (gross) while Sales shows it as 3000 after the return.
- Number grouping is inconsistent: "18,000" in one place, "KES 7000" in another.

### 11. Configs

- **Currency:** "This business trades in KES". The code field is empty and Change currency is
  disabled until you type.
- **Agreed prices:** "Who can agree a price — Off for 1 person": John Doe can agree a price, mziza is
  "Listed price only". This matches what the cashier saw.

### 12. Logs (O2)

- **Today:** only `product_created` (07:12 UTC) and `product_retired` (07:15 UTC). The **return
  verification (≈07:03), the count acceptance (≈07:04) and the customer payment (≈07:08)** aren't
  listed under "All events". The cashier's payment-method change from yesterday wasn't checked.
- **Event names are raw identifiers** (`product_created`), and **times are in UTC**, not EAT.
- **Next** stays enabled with only 2 entries.
- **From the code, O2 splits in two:**
  - **Not recorded at all.** `stockTakeApply.ts` (accepting a count) and `customers/payments.ts`
    (recording a payment) write no `audit_logs` row.
  - **Recorded but not shown.** `returns.ts` writes `return_verified_stock_restored`, and
    `saleTender.ts` writes `sale_tender_changed`. The Logs screen pages `audit_logs` in document-ID
    order, which is a digest and says nothing about time, and then filters one page down to the
    chosen day on the device. So a day's events can sit on a later page, which fits **Next** staying
    enabled. `loadRecordedRange` (ordered by `createdAt`) exists but the day view doesn't use it.
    `sale_tender_changed` and the product events aren't in `TenantAuditEventType`, hence the raw
    names.

### 13. Visited only, nothing written

- **Suppliers:** Receive delivery, Add supplier, and one active supplier "isiolo" (no phone or email,
  last delivery 3 Oct).
- **Production:** Record production, and Beard Oil batches with cost per unit and total, plus View
  costs.
- **Printer:** Network / Bluetooth tabs. No printer is configured, and the home shows no warning about
  that.
- **Staff:** Invite staff, role and status filters, John Doe (Owner, Active) and mziza (Cashier,
  Active).
- **Shift history:** opens on today with "No closed shifts on this day", the same date-of-opening
  problem as cashier C5. My tap to change the date didn't land, so this is unconfirmed for the owner.
- Not opened: WhatsApp, Email.

## Smaller things

- The confirm button on the return verify dialog is truncated, and red for a positive action.
- The Stock counts subtitle is truncated.
- After coming back from Business details, the receipt on My businesses is briefly drawn narrower.
- The app-bar back arrow on My businesses failed once; the system back key worked.
- Amounts are grouped in some places (18,000; 4,000) and not in others (KES 7000).
- "Open a shift before selling." is used for a debt repayment.
- The returns empty-state copy ("every standing") is unclear.

## Not covered

- Creating a second business. The validation was checked, but I submitted nothing, to avoid a real
  tenant on SIT.
- Invite staff, change currency, save branding, Bluetooth/network printing, a WhatsApp or Email test
  send, a supplier delivery, a production record, Add many (bulk import), and exports from Sales,
  Reports and Logs.
