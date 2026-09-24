# Landing page brief — Uzapay POS

Paste everything below into a site builder. It is written to be used as a prompt.

---

## The job

Build a marketing landing page for **Uzapay POS**, a multi-business point-of-sale
system for small retail in East Africa — corner shops, bars, kiosks, minimarts,
hardware stores. It runs on Android phones and tablets, and on desktop browsers.

The page sells to the **owner**, not to a CTO. They have two to ten staff, one or more
shops, a cash drawer, a thermal printer, and a phone that loses signal. They are not
buying software; they are buying an answer to *"did today's money add up, and if it
didn't, where did it go?"*

## Positioning — the one idea the page must land

**Most POS apps record sales. This one reconciles them.**

Every sale, return, stock count, drawer count, expense and staff action lands in one
ledger that the server independently regenerates and checks. When the numbers don't
agree, the app says so on the home screen before the owner has to go looking. That is
the product.

Secondary idea, almost as important: **it does not stop when the internet does.** The
sale is written to the device first, encrypted, and syncs itself when the connection
returns. The till works on a cold start with no network at all.

## Audience and tone

- Plain, concrete, unhurried. Shopkeeper's words, not enterprise words.
- Say "drawer", "shelf", "receipt", "shift", "what the count came to" — not
  "omnichannel", "unified commerce", "leverage", "empower", "seamless".
- Short sentences. No exclamation marks. No stock-photo optimism.
- Currency examples in **KES**. The product supports any ISO 4217 currency, chosen per
  business, but the examples should read as East African.
- Credible over excited. The buyer has been sold a POS before and it went badly.

## Page structure

### 1. Hero

- Headline on the reconciliation idea — in the register of *"Know what today took, and
  what it should have taken."* Write better ones; do not reuse that verbatim.
- One subhead sentence covering offline, roles and reports.
- Primary CTA: **Start free** (self-serve signup). Secondary: **See how it works**.
- Visual: the app's home screen on a phone beside a report on a desktop — dark green
  interface, one card reading something like *3 unresolved differences*.

### 2. The problem strip

Three short lines, no illustrations:

- The drawer is short and nobody knows which shift.
- Stock on the shelf and stock in the system stopped agreeing weeks ago.
- The one person who understands the numbers is the one person who might be taking them.

### 3. Feature sections — six, each a heading, two or three sentences, one screenshot

**Sell, even with no signal.**
The register takes the sale, tenders the payment and prints the receipt. If the network
is down the sale is written to the device in encrypted storage and queued; it syncs
itself when the connection comes back, and the app says what is still waiting. Nothing
sits between a tap and the record.

**Every shift is counted and accounted for.**
Staff open a shift, declare what the drawer started with, and close it with a count.
Shift history shows what each drawer was counted at against the sales it actually took,
so a shortfall has a name and a time on it.

**Stock that gets counted, not guessed.**
Schedule a stock count; a cashier counts the shelf and hands the figures in; a manager
reviews them and applies the correction. Every movement — sale, return, adjustment,
count — is on the product's own ledger.

**Reports that answer a question.**
Daily, weekly and monthly totals, payment breakdowns, profit after expenses, and
per-device sales. Record rent, wages and running costs, and see what profit is left
after them. Export a report as a file.

**The right staff see the right screens.**
Four roles — owner, admin, manager, cashier. A screen a role cannot use is not shown to
them at all, not greyed out. Invite staff by email; they accept and they are in.

**Nothing happens without a record.**
Approvals, staff changes, stock corrections, returns and reconciliation runs are all
written to an audit log. Returns are verified before they offset a sale.

### 4. Reconciliation section — give this one its own full-width treatment

Explain, in four short beats, that the server re-derives each business day's totals from
the sales it received, marks the day clean once the figures regenerate, and flags a day
it could not finish. The owner sees unresolved differences on the home screen. This is
the section that separates the product from a cash-register app; give it room.

### 5. Set-up section

Sign up, verify your email, name your business. Two things before the first sale: pick
your currency and add a product. Then add your logo and what the receipt prints, set
your printer, invite your staff. One owner can run several businesses from the same
login and switch between them.

### 6. Pricing

The plan is not settled yet. Render a pricing section with a single clear
**Start free / no card** call to action and a short "talk to us about multiple shops"
line. Leave the tier table out rather than inventing numbers.

### 7. Footer CTA

Repeat the primary CTA. One sentence, no new argument.

## Visual direction

Take the palette from the app itself — this is a dark, calm, green product, and the site
should look like the software rather than like a generic SaaS template.

- Backgrounds: near-black greens. `#071610` page, `#0D1F16` cards, `#132A1F` raised.
- Text: `#D4E7DD` primary, `#BCCBB9` secondary, `#849E8F` muted.
- Accent and CTA: `#4BE277`, with `#003915` for the label on it, brightening to `#6BFF8F` on
  hover; `#45F28D` sparingly, one highlight per screen.
- Status colours, only where something has a state: `#F2C14E` attention, `#FF5C6C`
  error, `#6FB7F2` information.
- Charts and report imagery sit on **paper** — white `#FFFFFF` ground, `#141A16` ink,
  series in `#25AB2E`, `#1DA39E`, `#398CF2`, `#899C42`. The contrast between dark chrome
  and paper-white reporting is part of the product's look; use it.

Type: one clean grotesque. Generous line height, headings tight, body relaxed.
Layout: single column, wide breathing room, content capped around 1200px. It must work
at 411px wide — most of this audience will first see the page on a phone.
Motion: spring-based and subtle, or none. Nothing that bounces.
Accessibility is pass/fail: real contrast, 48px touch targets, visible focus rings, and
no status conveyed by colour alone.

## Do not claim

These do not exist. A page that promises them is a page that produces refunds.

- Customer accounts, loyalty, CRM, suppliers, purchase orders or supplier invoicing.
- Tax/VAT calculation, e-invoicing, or any revenue-authority integration.
- Mobile-money, card or bank integration of any kind. Payment method is recorded, not
  processed.
- Barcode scanning as a headline feature.
- Fraud detection, risk scoring, or "AI".
- Accounting-package export (QuickBooks, Xero, Sage).
- Franchise or cross-shop consolidated reporting. One owner can hold several businesses;
  their reports stay separate.
- Any uptime figure, customer count, or named customer logo.

## Also

- The product name is not finally settled — it is **ChillTent** in the codebase and
  **Uzapay POS** on the domain. Build with "Uzapay POS", but keep the name in
  one place so it can be swapped in a single edit.
- Use real screenshots of the app, not invented mock-ups. Do not draw a control the
  software does not have.
- No testimonials until there are real ones.
