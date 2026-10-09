# Cashier device run — 2026-10-08/09

**Who:** `mziiza261@gmail.com` ("mziza"), cashier at **Smartcom**.
**Where:** Android emulator `pos_test` (Pixel 6, API 35, headless, Impeller off), **against SIT**
(`multitenant-pos-b8326`). Debug build of `4db0b1a` (= release 1.0.12+7).
**When:** 2026-10-08 19:05 – 2026-10-09 09:56 EAT. The business day rolled over during the run.

Everything below was seen on the device unless it says "from the code".

## Data this run left on SIT

- Sales `CT-EC7-20261008-0001` (cash, KES 4000, customer DeviceRun), `-0002` (credit, KES 1000,
  400 paid by M-Pesa, customer OfflineTest), `-0003` (card, KES 1000, rung **offline**).
- A customer called **DeviceRun** (+254 712 000 111, no WhatsApp consent).
- A return of 1 × tallow 30ml on `-0001`, reason Other "device run test". The owner verified it later.
- A whole-catalog stock count. The owner accepted it later.
- Two closed shifts. The first was a stale shift I closed by accident with Cash 500, M-Pesa 0 and
  Card 0 (see C1). The second ran 19:13 → 09:54 with a 1000 float.
- A returns report PDF saved to the emulator only.

## Summary: what to fix first

| # | Severity | Finding |
|---|---|---|
| C1 | **High** | The keyboard's ✓ key on the last field **closes the shift**. One tap you can't undo, with no confirmation. |
| C2 | **High** | The shift reconciliation counts a return the cashier already refunded. The cashier is marked **"Short by KES 1,000"** for doing it right. From the code, this doesn't depend on approval: no shift is ever charged for a refund. |
| C11 | Medium | Re-labelling a cash sale as M-Pesa before closing (C6) passes every reconciliation check. Only the audit row and the M-Pesa statement show it. |
| C3 | **High** | **"Paid by" drops the part paid now on a credit sale.** KES 400 by M-Pesa vanished from the breakdown, so the rows don't add up. |
| C4 | Medium | Searching the full receipt number the app shows (`CT-EC7-20261008-0001`) is **rejected**. |
| C5 | Medium | A cashier **can't find the shift they just closed** in Shift history. It's filed under the day it *opened*. |
| C6 | Medium | A cashier can **re-label a cash sale as M-Pesa** after the fact, and the screen doesn't update. The server does audit it (`sale_tender_changed`), but Logs doesn't name that event. |
| C7 | Medium | **Out-of-stock items sell with no warning**, and a typed quantity has no upper limit (99999 → KES 200,000,000). |
| C8 | Medium | A **stale open shift (>24 h)** is invisible on the home. It only shows when you tap Register. |
| C9 | Low–Med | The **WhatsApp receipt sheet pops up after every sale**, even for a walk-in or a customer who didn't consent. |
| C10 | Low | About 20 copy and polish items (see "Smaller things"). |

---

## Flows walked

### 1. Sign-in and home

- The emulator held a stale signed-in session (the owner). On a cold start it showed *"Working from
  data saved on this device (6h old)"* even though the network was fine. logcat said `Tenant
  bootstrap refresh unavailable: deadline-exceeded`, and nothing retried until the app was resumed.
  So a slow first refresh is reported as being offline.
- Sign-out is immediate, with no confirmation.
- The password field's hint is `********`, which looks like a password is already filled in.
- The cashier's home has Register, Sales, Returns, Inventory, Count stock and Shift history. The
  greeting reads "Good evening, mziza", in lowercase as stored. The business name in the top bar
  isn't tappable for a cashier, which is correct.

### 2. Stale shift → close → open (C1, C8)

- The home **gave no hint** of an open shift. Tapping **Register** opened a full-screen *"Shift
  over — open more than 24 hours. Close it and open a new one."* screen with no app bar or back
  button.
- **Close shift sheet**
  - It opened with the callout *"COUNTING THE DRAWER — A cash count is unfinished. Finish it before
    switching business."* That's owner wording: a cashier can't switch business.
  - It also said "Enter what you took today" for a shift that was more than 24 hours old, and "This
    shift was opened on another phone."
  - Input filtering is good: minus signs and letters are blocked. `10.555` and `1.2.3` can be typed,
    and blurring the field flags them with *"Enter an amount, like 1250.50."*
- **C1 — I meant only to dismiss the keyboard. Pressing the keyboard's ✓ on the Card field submitted
  the close.** The shift closed with Cash 500, M-Pesa 0 and Card 0.
  - Blank fields silently count as 0.
  - There was no "are you sure?" and no undo.
  - Hiding the keyboard with the navigation-bar arrow does *not* submit, so it's specifically the IME
    action on the last field.
- The result screen says *"Shift closed. Cash: 500. M-Pesa: 0. Card: 0."* It has no currency code,
  and the cashier sees no expected-versus-counted figure. A blind count may be intended.
- After **Done** comes *"Start your shift"* with an optional opening float. A float of 1000 opened
  fine.

### 3. Register and cart (C7)

- **Product grid:** three products, with chips All / oils / tallow / cold drink.
  - "tallow 30ml" and "Tallow 60ml" differ only in case. That's data, but it makes every list harder
    to read.
  - **The search box says "Search by name or code".** The code became the *size* in 1.0.11, and
    Inventory's box already says "name or size". Searching by size (`60ml`) works.
  - **A no-match search** says "Clear it to see the whole list", but the box has **no clear (×)
    button**.
  - **An empty category** ("cold drink") shows the *search* no-match message although nothing was
    searched.
- **C7 — out of stock:** "Tallow 60ml · 0 in stock" adds to the cart with no warning. The cart line
  does say *"This device last saw 0 in stock. The sale is not blocked by that count."* After the sale
  the grid shows **"-1 in stock"**. If selling below zero is intended, fine, but the cashier gets no
  prompt.
- **Cart sheet**
  - **Quantity minus at 1 removes the line** with no confirmation or undo.
  - **The quantity can be typed.** `01` is accepted as 1. **`99999` is accepted**, giving the line
    "99999 x KES 2000 = KES 199998000" and a total of KES 200000000, with no upper limit or sanity
    check. Amounts aren't grouped (`200000000`), so the mistake is easy to miss.
  - The cart **never says who the sale is for**; the customer only shows on the register title
    behind it.
  - **Price:** this cashier can't agree a price. Configs → Agreed prices sets mziza to "Listed price
    only", so that works as configured.
  - **Payment:** Cash, M-Pesa and Card. Saving with no payment method is allowed ("The sale records
    that it was not said, and you can set it later"). Cash has **no amount-tendered field or change
    calculation**.
  - **Put on credit** only appears once a customer is chosen. Good.

### 4. Customers from the register

- The picker ("Who is this sale for?") shows each customer's **debt to the cashier**, e.g.
  "OfflineTest — Owes 3000". Decide whether cashiers should see that.
- **Add new customer:** name, phone (+254 default, so the Kenya change is live) and KRA PIN.
  - The KRA placeholder `A012345678Z` is drawn bright and reads like an entered value.
  - Typing a phone number makes an *"Agreed to get receipts on WhatsApp"* checkbox appear, which
    shifts the form under your finger.
  - **KRA PIN `123`:** no error on the field. Submitting shows a red callout *below* the form, and the
    field itself isn't marked. Clearing the field doesn't clear the error until the next submit.
  - A phone with a trunk zero (`0712000111`) is accepted. The customer was created and attached to
    the sale, with no snackbar.

### 5. Sales (cash and credit) and the WhatsApp sheet (C9)

- **Cash sale:** saved as `CT-EC7-20261008-0001`. The snackbar says *"Saved as … It syncs on its
  own."* Stock updated immediately (tallow 98 → 96). The customer resets to Walk-in after the sale.
- **C9:** straight after every sale a *"Send on WhatsApp"* sheet appears.
  - For DeviceRun (consent left **unticked**) it was pre-filled with their number.
  - For a walk-in, and offline, it was empty.
  - Its own copy says "Send it only if they asked for it". As a mandatory interruption it costs one
    tap per sale, and it pushes towards sending without consent. I always cancelled, so nothing was
    sent.
- **Loyalty** works: DeviceRun showed 40 points after a KES 4000 sale.
- **Credit**
  - The dialog reads *"OfflineTest already owes KES 3000. This sale: KES 1000. Paid now
    (optional)"*, and "Owed on this sale" updates live.
  - Paying 1500 against a 1000 sale gives *"That pays for all of it. Choose how they paid instead of
    credit."* That's sensible, though the surplus can't go towards the old debt.
  - Paying 400 with no payment method gives *"Say how the part paid now was paid."* Good.
  - **Saved summary:** "OfflineTest owes KES 600 on this sale · Paid now: KES 400 by M-Pesa · Balance
    after: KES 3600". Next to it, a green **"Paid in full"** link reads like a *status* next to "owes
    600"; it's actually the action that cancels the credit.

### 6. Leaving the register

*"Leaving the register — Just stepping away / Close shift / Cancel"* is clear. Stepping away shows
a Shift card on the home: "Opened 19:13 by mziza · 11m".

### 7. Sales report (C3, C4, C6)

- The header reads "Your revenue KES 5000 · 2 transactions" with **Paid by: Cash 4000 (80%), Owed on
  credit 600 (12%).**
- **C3 — the KES 400 paid by M-Pesa on the credit sale is missing.** The rows sum to 92%.
  - Root cause, from the code: `functions/src/operations/domain.ts` → `aggregateSalesByTender`. For a
    credit sale it adds the paid part to the tender bucket's `sales` but **never increments that
    bucket's `transactions`**.
  - The client drops any row whose `transactions == 0` (`TenantSalesTenderTotals.isEmpty`), so an
    M-Pesa row holding only a part-payment disappears.
  - It only reappears when another M-Pesa sale exists that day. I re-labelled #0001 as M-Pesa and the
    row showed KES 4400.
  - The owner's view has the same gap.
- **C6 — Change payment method** is on every sale's ⋮ menu: *"This sale says Cash … only possible
  until the shift is counted off."*
  - Changing Cash → M-Pesa gave **no confirmation, and the card still said "Cash"** until I left
    Sales and came back.
  - Separately: a cashier can freely re-label cash takings as M-Pesa before closing, which weakens
    the cash count (see C11). From the code, `functions/src/operations/saleTender.ts` does write a
    `sale_tender_changed` audit row with the previous tender. The client's
    `TenantAuditEventType` doesn't model that event, though, and there's no reason prompt.
- **C4 — receipt search**
  - The full number the app itself shows (save snackbar, return sheet), `CT-EC7-20261008-0001`, is
    **rejected**: *"Enter the receipt as printed, such as JOHN-CT-7F2-001, or its last 1 to 6
    digits"*.
  - `0001` and `CT-EC7-0001` both work.
  - The hint example `JOHN-CT-7F2-00…` matches neither format the app prints.
- **Sale menu:** Return, Send on WhatsApp, Change payment method. There's **no reprint, print or
  email receipt** option for a cashier.

### 8. Returns

- **From a sale's menu**
  - The steppers cap correctly ("2 of 2 available"), although + still *looks* enabled at the cap.
  - Reasons: Spoiled or expired / Damaged or broken / Wrong item given / Customer changed their mind /
    Faulty or not working / Other. Other requires *"Say what happened"*.
  - The return asks nothing about a **refund amount or refund method**.
  - The confirmation reads *"This records 1 unit as a pending return. It restores no stock: a manager
    must verify it first."* That's clear.
- **Afterwards**
  - The sale card's total drops to KES 3000 with a "Partly returned" badge, while the line still says
    "2 x KES 1000".
  - The keyboard pops up on the search field uninvited.
- **Returns tile**
  - It shows *all* returns for the business: "Already off the takings. The stock comes back when this
    is verified." and "Only an owner, administrator or manager can verify a return."
  - **A cashier can export a business-wide Returns report (PDF or Excel).** It saved
    `smartcom-returns-2026-10-01-to-2026-10-08.pdf` (52 KB) through Android's save dialog, with no
    in-app confirmation afterwards. I couldn't read the PDF on this machine. Decide whether cashiers
    should export business reports.
- **View return**
  - It shows the note as "REASON FOR RETURN". The chosen reason ("Other") isn't shown.
  - One state has three names: PENDING (feed), UNVERIFIED (header) and AWAITING VERIFICATION
    (footer).

### 9. Inventory (read-only for a cashier)

- The screen is titled "Inventory Manager — Manage products, categories, and stock", but a cashier
  can only look. Cards don't open, and nothing says the view is read-only.
- **The QR icon in the search box does nothing** except focus the field, so it suggests a scanner
  that doesn't exist.
- The stock filter offers All / Above zero / At-below zero, and its menu is clipped at the right edge
  of the screen.

### 10. Count stock

- **Rows show only the product name** until a number is typed, so "tallow" and "Tallow" (30ml vs
  60ml) can't be told apart before you count them.
  - The size only appears after a non-zero entry.
  - A 0 entry shows "You looked, none there" and never shows the size.
- The confirmation is clear: *"Anything left empty is recorded as not counted… Nothing moves until
  somebody reviews this."*
- **After "Hand it in" the page silently resets** to 0 of 3 with blank fields and the keyboard up.
  There's **no confirmation**, so it looks as if nothing happened, and a cashier may count again. It
  did reach the owner, so the hand-in works.

### 11. Shift history (C5)

- It opens on today's business date. **The shift closed at 19:12 on 10-08 (opened on an unknown
  earlier date) is not listed on 10-06, 10-07, 10-08 or 10-09.** History files a shift under its
  *opening* date and has no cross-date list, so a cashier can't find the shift they just closed.

### 12. Offline sale and sync

- I turned off wifi and mobile data (`svc wifi/data disable`). The register opened from cache, and a
  card sale saved as `-0003`.
  - The snackbar is identical to the online one, "It syncs on its own", with no hint that the sale is
    waiting.
  - The home has no offline banner. The **bell** got a "1" badge: *"1 sale is waiting to send — Saved
    on this device… Nothing is lost while this register is offline."* Good.
  - **Offline, the Shift card loses its time and duration** ("Opened by mziza" instead of "Opened
    19:13 by mziza · 14h 40m").
- **Close shift while offline:** the tap showed **nothing for 15–20 seconds** (no spinner), then a
  correct guard: *"1 sale on this device is not synchronized yet and none of the figures here include
  it. The shift cannot be closed until they are."*
- **Back online, it synced within about 25 seconds** and the badge cleared.
- The receipt number carries the shift's business date (`20261008`) although the sale was rung on
  10-09. That's consistent with the shift, but the owner won't find "this morning's sale" under
  today.

### 13. Proper close and reconciliation (C2)

- The sheet said *"This shift started with 1000 in change. Count it in…"*.
- I entered Cash 4000 (1000 float + 4000 cash sales − 1000 refunded), M-Pesa 400 and Card 1000.
- **Shift history 10-08:** "19:13 → 09:54 · 3 sales · Counted cash 4,000 · Opening float 1,000 ·
  Recorded sales 6,000 · Sold on credit 600 · **Short by KES 1,000**".
- **C2:**
  - "Recorded sales 6,000" is **gross of the KES 1,000 return**.
  - The Returns feed told the cashier that return is *"Already off the takings"*, and Sales shows the
    sale at KES 3000.
  - So the cashier who handed back the refund is marked short by exactly the refund.
  - **From the code, approval doesn't affect it.** Return status never enters any shift figure:
    - The device's `_cashVarianceMinor` (`lib/shift/shift_history.dart`) has no returns term.
    - The server's per-shift expectation (`aggregateDailySales` in
      `functions/src/reconciliation/model.ts`) has none either.
    - Verifying deliberately doesn't recompute the day (`returns.ts`).
    - Pending, verified, today or a week later all give the same result.
  - **It's a design decision with a blind spot, not a slip.** `DailyAggregateResult.shifts` keeps
    shift figures gross on purpose: "Money that came back a week later did not leave that drawer, so
    netting it into a shift's expected cash would mark a correct count short."
    - That holds for the sale's original shift.
    - But no shift is ever charged for the refund. The return records no refund amount or method,
      and isn't tied to the shift that paid it out. So whichever drawer hands the money back comes
      up short, here the same shift.
    - The nightly per-tender check below flags the same KES 1,000 cash shortfall.
- **C11, corrected after reading the server.** The device's shift card and the Shifts report compare
  only the total across cash, M-Pesa and card. The nightly reconciliation
  (`functions/src/reconciliation/processors.ts`) compares **each method separately** and raises a
  `shift_tender_variance` anomaly.
  - Pocketing cash and declaring it as M-Pesa is therefore caught overnight, though not on the card.
  - **Re-labelling the sale first (C6) is not caught:** the expectation follows the new label, so
    every method matches.
  - What remains is the `sale_tender_changed` audit row, which Logs doesn't surface well (owner O2),
    and the M-Pesa statement.
- The card shows only **counted cash**. The counted M-Pesa and Card figures aren't shown, so the
  cashier can't see how "short" was worked out.
- Amounts here are grouped (`4,000`); everywhere else they aren't (`KES 4000`).

## Smaller things

- The "COUNTING THE DRAWER… before switching business" callout is shown to cashiers, who can't switch
  business.
- `Shift closed. Cash: 500.` lacks a currency code and has stray full stops.
- "This shift was opened on another phone" appeared with no way to see when or by whom.
- Product cards in the cart: the 0-stock card has no green "selected" border, unlike in-stock ones.
- The sale card after a partial return shows the old line quantity next to the new total.
- The Returns empty state and filter copy is unclear ("every standing").
- Stock-count rows don't show size before counting (see 10).
- The Inventory stock-filter menu is clipped on the right.

## Not covered

- Printing: no printer on the emulator, and the cashier has no reprint option.
- Actually **sending** a WhatsApp receipt. I didn't want to message real numbers.
- Agreed (haggled) prices: disabled for this cashier.
- Selling across two devices at once.
- Changing the password, Forgot password.
