> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 03 sale and checkout audit — 2026-08-20

Project: `7478406619239162026`

Operation: `CORRECT` selected existing checkout screens; Stitch returned derived successors
Design-system asset: `assets/4c1cc58b4aed4b1693e6f8113ba1009a` (retained, not mutated)

## Result

Phase 03 selected the retrievable desktop source ST-026 and the existing mobile sources ST-009 and
ST-011. The previously preferred desktop ST-001 returned invalid argument before mutation, so no new
desktop screen was generated from scratch. Stitch returned derived working screens:

- ST-035 `e85cc69d6db24026bc5eeff21a6f1b7f` — final desktop/tablet sale suite.
- ST-036 `0ece972d5e0f4deca20f8ed12686d618` — mobile cart/review suite.
- A mobile product-browse successor was returned successfully, but its exact source ID was obscured
  by response truncation and is not exposed by current project retrieval.

ST-034 `e95caf861f38426580b43519d4cbb901` records the first desktop/tablet result and is superseded by
ST-035. The original selected sources remain as history. No Flutter/Firebase code, design-system
asset, later-phase screen, or unrelated Stitch source was changed. No screen was deleted, moved,
grouped, hidden, or archived.

## Evidence and checkout contract

The correction was grounded in screenshot groups 14, 15, and 15b, responsive component evidence,
`lib/checkout/checkout_cart_panel.dart`, `checkout_tender.dart`, `checkout_refusal.dart`, checkout
cache/outbox behavior, receipt allocation, print failure mapping, and the RBAC matrix.

The working direction preserves these facts:

- Every active tenant role may sell; the specimens show quiet `Dev Corner Shop • Cashier` context.
- Cached product browse exposes search, categories, freshness, prices and last-seen stock. Stock
  shortage warns but does not block sale.
- Cart items support minus, whole-number quantity, plus, and removal. Totals and receipt evidence use
  KES and remain visually prominent.
- Cash, M-Pesa, and Card are cashier assertions. The payment itself is not verified.
- `Save sale` is the single primary transaction action. A refusal retains the cart and tender.
- Local save is durable before automatic server confirmation. Printing is independent and a printer
  failure leaves the sale saved, with recovery through Receipts waiting from the business home.

## Conflicts removed

- Kijani/wrong product identity and competing generic terminal navigation.
- VAT/tax, discount, save-draft, Pay/Checkout/Charge language, and verified-payment implication.
- Stock blocking and any implication that print failure reverses the sale.
- Conflation of local durability, server confirmation, and receipt-print status.
- The first successor's invented `Could not save. Check connection.` error attribution.

## Post-mutation verification

The first desktop successor ST-034 was retrieved, its screenshot was downloaded, and its HTML and
visual composition were inspected. The main total was correctly KES 155.00 and sale/print outcomes
were distinct, but the required tablet specimen was missing and the save error invented a connection
cause. One bounded correction produced ST-035 with the exact active generic refusal:

`This sale could not be saved on this device. Try again, and ask for help if it keeps happening.`

ST-035 was then retrieved and visually reviewed. It retains the dense desktop sale/cart composition,
state strip, correct KES 155.00 total, and adds a labeled 834px two-region tablet specimen.

The initial successful mutation also returned mobile browse and cart successors. ST-036's ID and
metadata were captured, but immediate `get_screen` returned invalid argument. The mobile-browse ID
was hidden by response truncation, `list_screens` returned invalid argument, and
`get_project.screenInstances` omitted all Phase 03 successors. Per the operating contract, the mobile
screens were not regenerated or repeatedly edited. They require Stitch UI visual review and browse-ID
recovery.

## Acceptance summary

- Unambiguous `Save sale`, no payment-verification claim: passed in the working designs.
- Local durability, later confirmation, and print outcome separated: passed.
- Prices, quantities, KES totals, and receipt number remain legible: passed on ST-035; mobile visual
  confirmation remains pending.
- Desktop multi-region and tablet two-region composition: passed and visually reviewed on ST-035.
- Mobile staged browse/review: passed in mutation output; render and exact browse-source ID review
  remain pending.
- Role/tenant context: passed in the working designs.
- Final status: `NORMALIZED / REVIEW`; only ST-035 is a visually reviewed canonical candidate.

## Recommended next phase

Proceed to Phase 04, catalog and stock, after a Stitch UI check recovers the Phase 03 mobile-browse
source ID and confirms the mobile browse/cart renders. Do not fold reporting, returns, staff, settings,
printing administration, or platform operations into Phase 04.
