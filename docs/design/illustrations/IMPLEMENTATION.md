# Workflow illustrations

Implemented 2026-10-13 following the [coverage audit](COVERAGE.md).

The app now has 40 original SVG compositions drawn for its business workflows,
using the same cream, jade, sky, lilac, coral and amber pigment roles as the
previous palette work. Source geometry is reproducible with
`dart run tool/generate_workflow_illustrations.dart`. Every pigment is assigned
through `--paint-*` IDs and resolves through `AppTokens` at runtime.

## Subjects and placement

| Family | Artwork now used |
| --- | --- |
| Customers | Customer portraits; customer search; account ledger; purchase receipt |
| Returns | Returned parcel, reverse arrow and receipt; also used for fully returned sales and a sale's empty return history |
| Inventory | Product shelves; product search; catalog sync; product category tags |
| Stock counts | Shelf and count clipboard; review sheets; count search; staff/calendar assignments; due-count prompt and held register |
| Stock records | In/out parcel movement; quantity adjustment; product ledger |
| Production | Products on a production workbench, including empty cost breakdown |
| Suppliers | Store/vendor and goods; supplier lookup; compact delivery form |
| Audit | Business activity timeline and ledger |
| Sales and reports | Receipt history/search and chart/report artwork |
| Notifications | Bell, receipt and delivery tray |
| Receipt delivery | Separate email-envelope/receipt and WhatsApp-message/receipt scenes |
| Reconciliation | Balanced ledgers for differences/runs; ledger and pencil for shift corrections |
| Shift closure | Cash drawer and receipt with completion marker |
| Settings/session | Settings/access scene; session/doorway scene; price agreement tag and staff |
| Platform console | Business storefronts, archived business tray, paused storefront, business search, accounts, people search, alerts and activity |
| Printer discovery | Printer and connecting cable beside the existing notice |

The empty checkout cart reuses the legacy `images/empty.json` Lottie animation,
centered above its message at the full 168px scene size on desktop and in the
mobile cart. It loops and displays a static representative frame under
reduced motion. `empty-cart.svg` remains its loading-error fallback.
The empty catalog and search states use the same centered 168px presentation
below the search field. Checkout messages are kept short: "No products yet.
Connect to sync.", "No matching products. Try another search.", and "Your cart
is empty. Add a product."
`printing-invoices.svg` is connected to the receipt print queue. Relevant shared
subjects remain for expenses, team membership, onboarding verification,
completion and access restrictions.

## Presentation

Full empty pages use `EmptyState` with a relevant asset. Illustrated section
messages and notices also use 168px artwork above centered, concise text.
Existing message keys and typography are retained. Illustrated notices retain
their status glyphs. Ordinary notices keep their existing layout.

The [layout and copy follow-up](LAYOUT_AND_COPY.md) documents 19 additional
placements centered and 63 illustrated states whose copy was shortened.

The category read failure now uses `ErrorState` with the explicit “Not read”
badge and the original explanation, rather than an empty-data illustration.
The conditions that show states, repository operations, permissions, routing,
stock counting and transaction logic were not changed.

## Previews

All assets are shown on both the page and raised/dialog backgrounds:

- [Main workflow gallery](../../../screenshots/audit/illustration-artistic-gallery-01.png)
- [Additional workflows](../../../screenshots/audit/illustration-artistic-gallery-02.png)
- [Search, reports and remaining artwork](../../../screenshots/audit/illustration-artistic-gallery-03.png)
- [Remaining artwork](../../../screenshots/audit/illustration-artistic-gallery-04.png)

Actual empty screens are captured at phone and desktop sizes by
`tool/screenshots/workflow_illustrations_test.dart`, using real route widgets
with in-memory readers. This covers Customers, Inventory, Returns, stock-count
review, Production and the compact message layout.

## Alternatives reviewed

The [unDraw shopping library](https://undraw.co/search/buy) and
[people library](https://undraw.co/search/people), plus
[SVG Repo's vector catalog](https://www.svgrepo.com/), were reviewed for relevant
subjects. The final workflow additions are original project SVGs: shelf counting,
returned goods, customer credit and reconciliation have purpose-specific
compositions. The original unDraw-based assets remain separately identifiable.

## Verification

Validation completed:

- 1,265 focused tests passed across 50 widget/screen test files, including
  enlarged-text layout, decorative semantics, status glyphs, palette contrast,
  paint markers, and existing inventory/transaction/permission contracts.
- Four gallery captures render all 54 illustrations on both backgrounds.
- Twelve actual screen captures passed at phone and desktop sizes. The five
  real route captures assert their intended empty-state keys before writing
  the image, so a read error cannot masquerade as the empty screen being tested.
- Targeted Flutter analysis of 61 files reported no issues. Full-library
  analysis reports existing warnings/information in unrelated legacy code,
  with no compile errors; the changed code passes targeted analysis.

Static captures establish layout and appearance; no device/backend run is claimed.

The empty-cart follow-up passed 123 focused checkout/illustration tests and two
desktop/mobile cart captures. Targeted analysis reported no issues. The desktop
layout check verifies that animation and copy share the cart pane's horizontal
center, the copy sits below the artwork, and the legacy asset is used.

The looping/centered-catalog follow-up passed all 134 checkout tests and workflow
captures, with clean targeted analysis. Desktop and phone checks verify the
catalog artwork is 168px, horizontally centered, and above the message below
the search field. The cart check asserts looping playback; reduced-motion
checks assert a static representative frame.

Checkout no longer shows the "This sale" header, unset-payment helper, or
empty-cart save helper. Payment choices and save validation keep their existing
behavior; other validation messages remain visible for invalid sale items.
