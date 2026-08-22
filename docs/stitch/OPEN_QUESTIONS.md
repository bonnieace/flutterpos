# Open questions

Do not answer these by drawing a plausible control. Record the product decision, then update the
relevant phase and coverage ledger.

## Resolved for Phase 00

1. Working visual references are surface `#071610` and primary `#4BE277`. These are semantic design
   inputs, not permission to hardcode colors in later Flutter screens.
   **Confirmed 2026-08-22 against the project export.** `#071610` is the `surface`/`background` token
   and renders in 75 of 76 screens; `#4BE277` is the `primary` token and renders in 75. The competing
   literals recorded in `DESIGN_RULES.md` are resolved: `#0A1A14` is not a token and renders in zero
   screens, and `#22C55E` is the separate `primary-container` role rather than an alternative primary.
   The design system's YAML frontmatter is authoritative; its prose has drifted. Evidence and counts
   are in `EXPORT_MAP.md`; the role-by-role mapping is in `TOKEN_RECONCILIATION.md`.
2. Normalize selected existing screen IDs in place. Do not create successors or archive history in
   Phase 00.
3. `list_screens` later recovered titles and artifacts for the six earlier retrieval gaps: ST-005
   Staff Management desktop, ST-006 Receipt & Printing Status mobile, ST-007 Inventory & Stock
   Movements mobile, ST-008 Staff Directory mobile, ST-018 Analytical Reports desktop, and ST-021
   Inventory Management desktop. They remain untouched and require content review before reuse.
4. ST-001 is the working desktop new-sale candidate; ST-011 and ST-009 are its mobile browse/review
   counterparts.
5. Phase 00 did not approve its draft chart content because the underlying metrics were not verified,
   not because charts are prohibited. Presentation parity is not required: supported metrics may be
   redesigned as charts, statistics, tables, or combinations during the analytics phase.
6. Tax/VAT remains unsupported and is absent from normalized designs. Editable business branding is
   deferred; current settings scope is currency plus printer linkage.

## Resolved for Phase 01

1. Authentication uses email and password only. Phase 01 adds no password reset, registration,
   social sign-in, SSO, subscription, or support workflow.
2. Email verification remains out-of-band: request/send the message, then explicitly recheck with
   `I have verified`; the UI does not collect a verification code.
3. A business request collects business name and slug, has a review/confirmation step, and remains
   pending until platform review. It does not provision a tenant automatically.
4. Invalid or expired invitations do not offer retry. The recovery is to continue without the link or
   ask the inviter to send a new invitation, according to the evidenced failure.
5. Platform routing is not a role picker: only a root `platform_admin` with the separate
   `platformRole=superAdmin` claim reaches the platform console. Platform operations are covered in
   Phase 09.

## Resolved for Phase 02

1. Mobile home navigation uses a deliberate shift-first, single-column task hub. It is not a cropped
   desktop sidebar and does not use a generic persistent bottom navigation bar.
2. Owner inherits Administrator access. Manager and Cashier homes omit forbidden routes entirely;
   they do not advertise them as disabled tiles.
3. Own shift is content on the home rather than a navigation destination. Its single forward action
   follows the active phase: Open shift, Start cash count, or Close shift.
4. Checkout synchronization evidence and receipt-print queue evidence remain separate. A confirmed
   sale does not imply that its receipt printed.
5. Tenant switching requires another accessible membership, clean inspected local state, and online
   target revalidation. Blocked/offline states keep the current business open.

## Resolved for Phase 03

1. Checkout records Cash, M-Pesa, or Card as the cashier's assertion; it does not verify payment.
2. `Save sale` is the only primary transaction action. Checkout adds no VAT/tax, discount, or draft
   control, and stock shortage remains non-blocking.
3. A locally saved sale is durable before server confirmation. `Confirmed by server` is a later,
   quiet status and is not required before the cashier can retain the receipt number.
4. Receipt printing follows durability. Printer failure never rolls back or relabels the sale; the
   cashier closes the success notice and uses Receipts waiting from the business home.
5. Tablet checkout is a distinct two-region browse/cart composition at 834px. Mobile remains a staged
   browse then cart/review flow rather than shrinking the desktop terminal.

## Resolved for Phase 04

1. Cashier catalog access is read-only and does not expose management or stock-route actions.
2. Manager may create categories/products and set the required first product price, but existing
   price/cost correction, recorded-cost removal, and retirement are Owner/Administrator-only and are
   omitted from Manager correction surfaces.
3. Bulk catalog input is pasted comma-, tab-, or semicolon-delimited text with a required header,
   row-by-row preview, explicit commit, and retained row outcomes. There is no `.xlsx` or file upload.
4. Stock is the server's recorded quantity, may be negative, and never blocks a sale. The product
   does not model reorder points, low-stock thresholds, suppliers, or purchase orders.
5. A stock adjustment is permanent, requires a typed reason and audit context, and is corrected by
   recording another adjustment. Adjustment feeds list manual corrections; movement feeds also
   include sales and verified returns.
6. Movement and ledger ordering is by product/record ID rather than time. Every record therefore
   carries its recorded time and actor/server provenance explicitly.

## Resolved for Phase 05

1. Chart-based presentation is limited to directly evidenced comparisons: two exact daily sales bars
   and exact-value tender bars/rows. Reconciliation state, anomalies, run detail, and shift amendments
   use status/stat/provenance/table treatments because exact source and actionability matter more than
   shape comparison.
2. Daily summary and sales totals are readable by Owner, Administrator, and Manager. Profit and margin
   are Owner/Administrator-only and disappear entirely for Manager or incomplete cost coverage.
3. Sales totals describe server-held sales and remain distinct from reconciled daily figures. Tender
   is cashier-recorded and unverified; `Not recorded` means older tender metadata is absent, not unpaid.
4. Reconciled, unusable-line, and different are distinct states. Unusable lines can coexist with a
   reconciled status but require separate attention language and never count toward stock or profit.
5. Reconciliation requests and shift-total corrections are Owner/Administrator-only. Manager may read
   anomaly and amendment history but receives no mode, request, correction, or reason controls.

## Resolved for Phase 07

1. Staff access remains fixed role-list authorization. The only tenant roles are Owner,
   Administrator, Manager, and Cashier; no granular permission editor or custom role is represented.
2. Owner and Administrator share staff write actions. Manager receives a materially separate
   read-only composition with no write affordance, and Cashier has no staff-directory route.
3. Owner role cannot be assigned by invitation or changed through the staff editor. The owner record
   may expose name/phone correction but cannot be deactivated.
4. Pending invitations support correction, resend, cancellation with an audit reason, and email
   replacement. Confirmation copy names the affected person and the resulting membership/access
   consequence.
5. Invalid or expired invitation-link recovery remains outside the canonical directory row model.
   It offers no Accept/Retry action; the invitee continues without the link or asks the inviter to
   issue another invitation.

## Resolved for Phase 08

1. Checkout settings exposes only the persisted ISO 4217 currency code. A change affects later sales
   after each device syncs; existing sales retain their recorded code and no amount is converted.
2. Printer setup exposes direct-TCP address, port, 32/48-column paper width, and cutter behavior.
   There is no transport selector or bridge-token field while the web bridge remains unbuilt.
3. A printer probe checks the typed endpoint without printing. Successful send/test language never
   claims that paper came out because this transport has no physical-status readback.
4. Printing follows durable sale persistence. A failed receipt remains a successful sale and enters
   a recoverable queue stored on the current device only.
5. Queued receipt bytes and endpoint are immutable. The queue offers no delete, edit, clear, dismiss,
   or mark-printed action; retry appears only for a retryable needs-attention job.

## Resolved for Phase 09

1. Platform superAdmin uses a deliberately separate operations shell, not tenant navigation or a
   tenant-role mode. Eligibility requires the active root, `accountType=platform_admin`, and token
   `platformRole=superAdmin`; tenant membership is neither required nor sufficient.
2. Pending admission supports approve and reasoned reject. Tenant standing then supports only
   active↔suspended and rejected→archived, with the required reason, confirmation, canonical update,
   fanout evidence, and owner-limit/conflict handling through `setTenantLifecycle`.
3. Global status accepts one exact Firebase Auth UID rather than general search. Disable/reactivate
   uses `setGlobalUserStatus`, reason and typed-UID guards where required, operation/attempt/affected-
   tenant evidence, active-relationship warnings and alerts, and safe same-operation retry after a
   partial result.
4. Archived relationships do not produce administrative warnings. Suspending a business does not
   globally disable users, disabling a user performs no owner transfer, and tenant access after
   reactivation still depends on tenant and membership standing.
5. Platform-role grant/revoke remains CLI-controlled. Tenant authority, billing, portfolio
   management, owner transfer, bulk actions, and role administration remain outside this console.

## Product decisions — RESOLVED 2026-08-22

7. **Business profile and receipt branding become editable in-app, by Owner and Administrator only.**
   Chosen twice: once against the recommendation to keep it backend-managed, and again after it was
   pointed out that this is the one decision inconsistent with the stated intent of matching the design
   without changing core app logic. It stands as a deliberate exception. This is a **feature
   addition**, not a restyle, and it has no design coverage:
   - No Stitch screen depicts it. Phase 08's ST-061/ST-062 deliberately restrict the settings surface
     to the persisted ISO 4217 currency code plus printer linkage, and `COVERAGE.md` lists editable
     branding as deferred.
   - It needs new write paths, Firestore rules, RBAC enforcement for the Owner/Administrator boundary,
     validation, and receipt-render changes — none of which exist.
   - Consequence: it cannot ride along inside Phase 08. It needs either a design pass (which requires
     a session with the Stitch connector plus explicit mutation authorization) or an explicitly
     provisional composition derived from the accepted Phase 08 settings patterns.
   - Until one of those exists, Phase 08 ships at its current currency-plus-printer scope and branding
     is tracked as a separate, later slice. Do not depict a branding control on a Phase 08 screen.
8. **Tax/VAT is permanently out of product scope.** Not deferred. `DESIGN_RULES.md` already forbids
   depicting it, checkout does not collect it, and the Phase 06 correction removing `Tax (16%)` from
   ST-048 is therefore a permanent fix rather than a temporary one. No receipt, reporting, or checkout
   surface carries a tax line, and none should be designed with space reserved for one.
9. **Historical discount stays visible on sale and receipt detail; checkout still prohibits new
   discount entry.** Read and write are separate concerns: a past sale's record is immutable, and
   hiding a discount it actually carries would make its line items fail to sum to its recorded total.
   Checkout offers no entry path. This does not authorize new discount capability anywhere.

## Design-system gaps — RESOLVED 2026-08-22

Raised from `TOKEN_RECONCILIATION.md` and **answered by the product owner on 2026-08-22**. The gap
descriptions are kept below as the rationale for each decision. The theme repoint is unblocked.

### Decisions

| # | Gap | Decision |
|---|---|---|
| 10 | No warning colour | Carry `amber400` `#F2C14E` forward as a documented **addition** to Profound Verdant |
| 11 | No info colour | Carry `blue300` `#6FB7F2` forward as a documented addition |
| 12 | Chip background is an alpha mechanism | `AppStatusRole` gains **alpha semantics**: background is the status colour at ~10% composited over the current surface at paint time, not a stored opaque value |
| 13 | Two reds, neither named | `status-critical` `#EF4444` is destructive and problem **content** (label, border, foreground); `error-container` `#93000A` is the error **background** at low alpha |
| 14 | Two greens for success | `status.ok` is `primary` `#4BE277` |
| 15 | No disabled values | Carry forward: `sageDisabled` `#5D7468` for disabled text and label, `green700` `#1E3A2B` for container and border |
| 16 | No hover or pressed value | `action.primary` hover is `primary-fixed` `#6BFF8F`; pressed is `primary-container` `#22C55E` |
| 17 | No scrim | Scrim stays `rgba(0,0,0,0.6)`. The `0.5` in the prose describes a drop shadow, not a scrim |
| 18 | Focus ring width | Stays **2px** wide at 2px offset; colour repoints to `primary` `#4BE277` |
| 19 | Radius scales collide | **Superseded 2026-08-22 — see the correction below.** `AppRadii` keeps its four names, but the values are `sm` 8→**2**, `md` 12→**8**, `lg` 20→**12**, and `pill` stays 999 while buttons, wells and chips move off it |
| 20 | Families not bundled | **Bundle Hanken Grotesk and JetBrains Mono**, declaring only the weights the seven type roles use (400/500/600/700, mono 500). Offline-first, so bundled assets rather than a runtime fetch. **DONE 2026-08-22 — see the note below; mono 400 was declared as well, and why is recorded there** |
| 21 | Sale responsive contract | Profound Verdant governs the bands. Two panes from **768** up; the desktop 3-column `Categories \| Items \| Cart` view is **deferred** and categories stay a `FilterChipBar` |

Density, from `audits/2026-08-22-wave-0-foundations.md` Finding 2: any density resolver **must take the
input kind, not just a width**, and must refuse `AppDensity.compact` on a touch device. A test that
fails if `compact` is ever resolved for touch is required, so the 48dp guarantee is enforced rather
than documented.

### The coupled consequence of decision 21

Decision 21 is not a single edit, and the two halves must land **together** or the sale path regresses:

1. `TenantCheckoutPanel.showsTwoPanes` (`lib/checkout/checkout_cart_panel.dart:211`) moves from
   `expandedFloor` to **`mediumFloor`**, so two panes begin at 768 instead of 1024.
2. `AppLayout.expandedFloor` moves from 1024 to **1280**, matching Profound Verdant's desktop floor.

Taken alone, step 2 is the regression identified earlier — it would strip two panes from 1024-1279.
Step 1 removes the sale surface's dependency on `expandedFloor` first, so the band keeps its two panes
and gains them at 768 as well. Order matters.

`expandedFloor` at 1280 still governs four other surfaces, and each moves at 1024-1279:
`record_list.formFor` (table → two-column cards), `home_navigation.showsMenu` (side menu → card grid),
`scaffold.showsDisplayTitle`, and `routes._isExpanded`. The table move is consistent with
`DESIGN_RULES.md`, which reserves full-width operational grids for desktop and asks tablet to prefer
two regions.

This is a layout change with real pixel consequences across three bands. It lands as its own
reviewable commit with the roughly fifteen assertions that pin 1024 updated, and with a harness
viewport added in the 1024-1279 range, which nothing currently covers.

> **Correction, 2026-08-22 — step 2 was not taken, and will not be.** Read this paragraph, not the two
> numbered steps above it. Step 1 landed: `TenantCheckoutPanel.showsTwoPanes` reads `mediumFloor` and
> the cart appears from 768 up. **Step 2 did not**, and `AppLayout.expandedFloor` stays at 1024, which
> `TOKEN_RECONCILIATION.md` item 6 records as a deliberate deviation: a table at 1194 is denser and
> faster to scan than stacked cards, and there is no reason to take that width away from the record
> surfaces. Because step 1 removed the till's dependency on that floor, the coupling the section is
> named for no longer exists and the two questions are independent. The fifteen assertions pinning
> 1024 therefore stand unchanged. ~~**The harness viewport in 1024-1279 is still missing and is still
> worth adding**~~ — that half of the paragraph was right for a different reason, since four surfaces
> flip in that band and nothing photographs them.
>
> **Second correction, same day, at `7509dcc`: that viewport exists.** `desktopNarrowViewport` is
> 1024 x 768 and the width matrices render at it, so the four surfaces are photographed at the floor
> where they flip. It turned out to be two gaps rather than one — §4.1's band floors and §4.2's page
> maxima interleave into five width regions and the harness had three, so `compactWideViewport`
> (767 x 1000) closes 720-767 as well, and a scan in `test/ui/tokens_test.dart` fails if a region
> loses its viewport. **Nothing else in this decision moved**: the floor is still 1024, still
> deliberate, and the fifteen assertions still stand.

### Original gap descriptions

10. **No warning colour exists.** The frontmatter contains no amber, yellow, or orange token. The only
    warning treatment in the export is raw Tailwind `yellow-400`/`yellow-500`, nine occurrences across
    three Phase 00-era screens, none of them a canonical candidate. `DESIGN_RULES.md` nonetheless
    requires `reconciliation differs` and `printer unavailable` to be distinguishable without relying
    on colour alone, and the current system uses `amber400` for exactly that tier. Does Profound
    Verdant gain a warning role, or does the product drop the tier?
11. **No info colour exists.** No blue token in the frontmatter; the current system uses `blue300`.
    Same question as above.
12. **Status chip backgrounds are a mechanism, not values.** The design system specifies "a low-opacity
    background of the status color", implemented in the export as Tailwind `/10` and `/20` alpha
    suffixes. `AppStatusRole.bg` and `.border` are opaque colours. Should the role gain alpha
    semantics, or should each background be composited against `surface` and recorded as a literal?
13. **Which red is destructive?** The frontmatter defines both `error` `#FFB4AB` and `status-critical`
    `#EF4444`, and the prose names neither. Both are used heavily in the export (`status-critical`
    1,042 references, the `error` family 506), so usage does not settle it.
14. **Is `status.ok` `primary` `#4BE277` or `tertiary` `#2EE380`?** Both are defined; neither is
    assigned to a success state.
15. **No disabled values.** Profound Verdant defines nothing for disabled text or disabled action
    container/label/border. Carry the current `sageDisabled` `#5D7468` forward, or decide new values?
16. **No primary hover or pressed value.** `primary-container`, `primary-fixed`, and `primary-fixed-dim`
    exist but are never assigned to an interaction state. Assigning one is a design decision.
17. **No scrim value.** Carry the current `rgba(0,0,0,0.6)` forward, or adopt the `rgba(0,0,0,0.5)` the
    prose names for modal shadow?
18. **Focus ring width.** The prose says a `1px` border glows primary green on focus; the current ring
    is 2px at 2px offset. A 1px ring is the weaker option against the pass/fail accessibility rule in
    `DESIGN_RULES.md` §9.
19. **Radius scale collides by name but not by value.** Profound Verdant `lg` is 8; `AppRadii.lg` is
    20. The current `lg` of 20 has no Profound Verdant equivalent, and Profound Verdant's 2, 4, and 6
    have no current equivalent. Which scale wins, and does `AppRadii` keep four steps or take
    Profound Verdant's six?
20. **Typography families are not bundled.** Profound Verdant names Hanken Grotesk and JetBrains Mono;
    `pubspec.yaml` declares only Roboto and one Roboto Mono face, and neither family appears anywhere
    in the repository. Adopting the type scale requires adding font assets. It does, however, answer
    the question `lib/ui/tokens.dart` recorded as open about the family behind `AppTypeRoles.mono`.
21. **The two design sources disagree about the tablet sale layout, and the desktop one is unbuilt.**
    `design.md` §4.3 specifies "products + cart sheet" at both `compact` and `medium`, with two panes
    only at `expanded` (1024+). Profound Verdant (`profound_verdant/DESIGN.md` lines 140-142) specifies
    a 2-column "Items + Cart" split across the whole 768-1280 tablet band and a 3-column
    "Categories | Items | Cart" desktop view above 1280. Three consequences, all needing one decision
    rather than a breakpoint tweak:
    - the tablet band should **gain** two panes at 768, where it currently gets a sheet;
    - raising `AppLayout.expandedFloor` to 1280 on its own would **remove** two panes from 1024-1279,
      regressing the band against Profound Verdant — so the floor stays at 1024 until this is settled;
    - the 3-column desktop view does not exist. Categories are a horizontal `FilterChipBar`, not a
      column, so the desktop sale composition is unbuilt at any floor value.
    **Decided 2026-08-22, and it is two answers rather than one.**

    **The breakpoints stay at 768 and 1024.** Profound Verdant's 1280 desktop floor is a documented
    deviation, not unimplemented work. At 1194 — an 11-inch tablet held sideways — a record table is
    denser and faster to scan than the stacked cards the narrower band would give it, which is what an
    operational surface wants; there is no product argument for taking that width away from the
    catalog, ledger, movements or receipt lists. `AppLayout.expandedFloor` is therefore **correct as
    it stands**, and the four surfaces it gates — record lists, home navigation, page display titles,
    route transitions — are left alone. Do not re-open this as a defect; it is a choice with a reason.

    **The cart is visible on a tablet.** `TenantCheckoutPanel.showsTwoPanes` moved from the `expanded`
    floor to the `medium` floor, so two panes now begin at 768. This is the part of Profound Verdant's
    tablet row that was worth taking: a cashier on a tablet sees the cart beside the products instead
    of tapping to open a sheet. It also returns the value to what the app shipped before `design.md`
    §4.3 moved it, so this is a revert with a stated reason rather than a new invention.

    Because the till now reads `medium`, the sale surface **no longer depends on `expandedFloor` at
    all**, which removes the coupling that made the original question awkward. The two halves are
    independent now.

    **The 3-column desktop view stays deferred and unbuilt.** Categories remain a horizontal
    `FilterChipBar`. Above 1280 the till is a two-pane layout where Profound Verdant asks for three
    columns; that is provisional design debt, recorded rather than implied to be done.

    Coverage taken with the change: the till is now captured at all three bands
    (`viewports: everyBandViewports` in `tool/screenshots/operations_screens_test.dart`). Before this
    it was rendered at 1440 and 411 only — **the tablet layout of the one screen a cashier uses all day
    was covered by nothing**, which is why the boundary could sit wrong without anyone seeing it. A
    test also pins 768 exactly, the tightest case the new boundary admits: the cart pane is a fixed
    420, so the products get 347, and a `Row` that does not fit overflows and throws.

    **Extended at `7509dcc`, and it lands on this decision's own deferred half.** That list is
    `responsiveViewports` now, four wide rather than three, because §4.1's band floors and §4.2's
    page maxima interleave into five width regions and the harness had viewports in three of them. So
    the till is captured at **1024** as well — `screenshots/desktop-narrow/14-new-sale.png` and
    `15-new-sale-with-a-cart.png`. That width sits inside the 1024-1279 band this decision created,
    which is exactly where Profound Verdant asks for three columns and this app draws two. The
    deferral is unchanged and still deliberate; what changed is that the debt is now in a picture
    rather than only in this paragraph.

    See `audits/2026-08-22-wave-0-foundations.md` Finding 1 for the per-band table and the original
    blast-radius analysis.

### Correction to decision 19 — the radius scale, 2026-08-22

**Decision 19 was taken from the wrong source and is restated here.** It read the scale out of
`profound_verdant/DESIGN.md`'s frontmatter, the way the palette was read. For colour that was right,
because the frontmatter and the served screens agreed. For radii they do **not** agree, and the served
config is a different scale under the same names:

| Source | Scale |
|---|---|
| `DESIGN.md` frontmatter | `sm` 2, `DEFAULT` 4, `md` 6, `lg` 8, `xl` 12, `full` **9999** |
| **Served config, identical in all 76 screens** | `DEFAULT` 2, `lg` 4, `xl` 8, `full` **12** — four entries |
| App before this change | `sm` 8, `md` 12, `lg` 20, `pill` **999** |

The consequence is not a rounding difference. **The design has no pill.** `rounded-full` is used 484
times across the export and resolves to 12px, so nothing wide is a stadium, and the rendered sign-in
screen shows square-cornered buttons and inputs throughout. `DESIGN.md`'s prose claims a "Pill-shaped"
search bar twice and is contradicted by its own render — the same kind of drift as `#0A1A14`, except
that here the frontmatter is wrong too, so the served artifact is the only reliable source.

What the design actually measures, from its own CSS and class usage rather than from either scale:

| Element | Design value | Evidence |
|---|---|---|
| Buttons | **8** | `.btn-primary { border-radius: theme('borderRadius.xl') }` |
| Input fields | **8** | `input[type=…] { border-radius: theme('borderRadius.xl') }` |
| Cards | **8** | state panels carry `rounded-xl` |
| Status chips | **2** | bare `rounded` in 78 of the 82 places a chip appears |
| Checkbox | **2** | `.checkbox { border-radius: theme('borderRadius.DEFAULT') }` |

So the app's roles take the values their documented jobs call for: `sm` → 2 (chips, badges), `md` → 8
(cards, rows — and now buttons and input wells), `lg` → 12 (dialogs, bottom sheets).

**`pill` is kept at 999 and is now an app value, not a design one.** What still reads it is round on
purpose — the 32×4 sheet handle, the quantity stepper's controls, the sync badge, the keypad keys — and
Flutter clamps a radius to half the shorter side, so those stay capsules regardless. The keypad in
particular has no counterpart in the design at all. Where the design states a shape, the shape is now a
role; where it states none, `pill` is the app's own and is recorded as such rather than presented as
Profound Verdant.

Effect measured: 332 of 359 renders changed. On the sale screen only **0.7%** of pixels moved, but by a
mean of 45/255 against the palette repoint's 10 — far fewer pixels, moving much further. Pixel count is
a poor proxy for how large a change reads, because a corner is structural and a tonal shift is not.

## Typography metrics — RESOLVED 2026-08-22, same day it was raised

**Decision 20 is done and this is what it left behind.** Bundling the families settled *which faces*
render; it settled nothing about *what size, weight, tracking or line height* each role asks them for.

> **Answered by the product owner on 2026-08-22, hours after it was raised.** Read the decision
> below the original text. The three sub-questions were taken as: adopt all seven and derive the
> other five; map by size; add a sibling compact role.

The original question follows, and the metric table in it is the *before* state.

22. **Profound Verdant's seven type roles do not map onto `AppTypeRoles`' twelve, and where they do
    meet, the metrics differ.** `TOKEN_RECONCILIATION.md` §Typography has the full table. The
    disagreements, role by role:

    | Design role | Design metrics | Nearest app role | App metrics | Delta |
    |---|---|---|---|---|
    | `headline-lg` | 32 / 700 / 1.2, tracking -0.02em | `display` | 32 / 700 / 1.25, no tracking | line height, tracking |
    | `headline-lg-mobile` | 28 / 700 / 1.2 | *none* | — | the app has no breakpoint-aware type role |
    | `section-title` | 22 / 600 / 1.4 | `titleMedium` per the reconciliation, but 22 is `titleLarge`'s size | 18 / 500 / 1.33, or 22 / 500 / 1.27 | **which role it even is** |
    | `body-md` | 16 / 400 / 1.5 | `bodyLarge` | 16 / 400 / 1.5 | **agree** |
    | `body-sm` | 14 / 400 / 1.5 | `bodyMedium` | 14 / 400 / 1.43 | line height |
    | `label-caps` | 12 / 700 / 1.0, tracking +0.05em | `labelEyebrow` | 11 / 700 / 1.45, tracking +0.8 | size, line height, tracking |
    | `data-mono` | 14 / 500 / 1.0, tracking -0.01em | `mono` | 13 / 400 / 1.38 | size, weight, line height, tracking |

    Five app roles — `labelLarge`, `labelMedium`, `caption`, `numericHero`, `numericBody` — have no
    design counterpart at all, so a wholesale repoint would leave them stranded on a scale nothing
    else uses. That count is `TOKEN_RECONCILIATION.md`'s and it depends on two mappings that are
    themselves unsettled: it pairs `headline-lg` with "`display` **or** `titleLarge`" without choosing,
    and pairs `section-title` with `titleMedium` when the size matches `titleLarge`. Resolve those two
    first — the count of stranded roles moves with them.

    Three questions, and they are not independent:

    - Do the five uncounterparted roles stay on §2.2's scale while the seven move, giving one file two
      systems? Or does the whole scale move and the five are derived?
    - `headline-lg-mobile` needs a breakpoint-aware type role, which the token layer does not have.
      That is a structural addition, not a value change.
    - Tracking is stated in `em` throughout and `AppTypeRoles` stores `letterSpacing` in logical
      pixels. -0.02em at 32 is -0.64; +0.05em at 12 is +0.6 against the current +0.8. Converting is
      arithmetic, but it means every tracked role's stored number stops matching the source document.

    **Nothing here was guessed at on 2026-08-22.** The families changed and every metric stayed put,
    so the type scale is still exactly `design.md` §2.2 and still internally consistent. Choosing
    otherwise needs the product owner, because it is the same class of question as the radius scale
    and that one turned on evidence rather than on the frontmatter.

### Decision on question 22, 2026-08-22

**The evidence first, because it is the reason this could be answered the same day.** Normalising
the served Tailwind `fontSize` config across all 76 exported screens collapses 31 apparent variants
to whitespace and quoting: **75 of 76 are value-identical, and they agree with the `DESIGN.md`
frontmatter.** One outlier states `data-mono` 13 / 1.2 and `section-title` 20, and is outvoted 75 to
1. That is the opposite of the radius situation, where the served artifact contradicted both
frontmatter and prose — so here the frontmatter could be trusted, having been corroborated rather
than assumed.

Three answers:

1. **Adopt all seven, derive the other five.** The design's real scale is wider than its seven named
   roles: stock Tailwind sizes appear **1,028 times** alongside them (`text-sm` 475, `text-xs` 316,
   `text-lg` 78, `text-xl` 54, `text-3xl` 44, `text-2xl` 41). The five app roles with no named
   counterpart are derived from those rather than left on §2.2, so the file carries one scale.
2. **Map by size.** `headline-lg` 32 → `display` 32; `section-title` 22 → `titleLarge` 22. This
   file previously hedged the first and paired the second with `titleMedium` at 18. Size is the
   unambiguous property, and it leaves `titleMedium` free for the design's `text-lg` 18.
3. **Add a sibling compact role.** `displayCompact` at 28 for `headline-lg-mobile`, chosen by
   `AppLayout` band at the call site — not a token that silently resolves to two values.

The scale as it now stands, with the source of each row:

| Role | Value | Source |
|---|---|---|
| `display` | 32 / 1.2 / 700 / -0.64 | `headline-lg` |
| `displayCompact` | 28 / 1.2 / 700, untracked | `headline-lg-mobile` |
| `titleLarge` | 22 / 1.4 / 600 | `section-title` |
| `titleMedium` | 18 / 28 / 500 | derived, `text-lg` |
| `bodyLarge` | 16 / 1.5 / 400 | `body-md` — the one row the two scales already agreed on |
| `bodyMedium` | 14 / 1.5 / 400 | `body-sm` |
| `labelLarge` | 14 / 20 / 700 / +0.7 | **`.btn-primary`, measured** |
| `labelMedium` | 14 / 20 / 600 | derived, `text-sm` |
| `labelEyebrow` | 12 / 1.0 / 700 / +0.6 | `label-caps` |
| `caption` | 12 / 16 / 400 | derived, `text-xs` — unchanged, §2.2 already matched |
| `numericHero` | 30 / 36 / 700 | derived, `text-3xl` |
| `numericBody` | 14 / 20 / 500 | unchanged |
| `mono` | 14 / 1.0 / 500 / -0.14 | `data-mono` |

**Two findings that changed an answer.** The preview this decision was taken against proposed
`labelLarge` at 16 / 600 from the stock `text-base`. It is wrong: the design **measures** the button
directly, and `.btn-primary` reads `font-size: 14px; font-weight: 700; letter-spacing: 0.05em` at
`height: 48px`. Measured beats inferred, so `labelLarge` is 14 / 700 / +0.7. That CSS rule is also
where §9's 48dp target turns up in the design's own source rather than only in this app's rules.

The second: **the design sets money in `data-mono`**, not in a tabular interface face — 65 of the
places a `currency-kes` colour appears also carry `text-data-mono`. `numericBody` was **left in the
interface family** anyway, because moving every price in the app into the mono face is a composition
decision rather than a metric one. ~~**That is the one piece of question 22 still open**~~ —
**answered for the till on 2026-08-22 as decision 23 below, and left open everywhere else.** It is a
per-surface judgement like the `mono` reader sweep rather than a token value, and decision 23 takes
exactly one surface.

Tracking is stated in `em` by the design and in logical pixels by `TextStyle`, which has no `em`.
Every converted figure is the design's `em` times that role's own size, and the test asserts the
arithmetic rather than the result. Four roles are tracked, not the three the frontmatter names — the
fourth is the button.

**Blast radius, measured rather than estimated.** 346 of 361 screenshots changed; 15 did not. Two
assertions outside the token tests moved and both are recorded where they sit: `AppButton`'s label
size 15 → 14, and the safe-landing scrollable 551 → 548, the latter because `section-title`'s 1.4
line height grows the page header's title line from 28 to 30.8 and the body loses the difference.
A third moved inside them: a compact row's content is now **37** of its 40 minimum rather than 36,
which still fits and is now the tighter of the two measurements holding §3's "12 / 8" reading.

### Note on decision 20 as implemented, 2026-08-22

Three details worth recording, because each is a place the decision as written and the decision as
built differ or could be misread.

1. **Neither family existed anywhere.** Not in `fonts/`, not in the 18 MB export. The export links
   both from `fonts.googleapis.com`, which is the thing an offline-first till cannot do and the reason
   the decision says bundle. The faces came from the upstream OFL repositories — `marcologous/hanken-grotesk`
   and `JetBrains/JetBrainsMono` — because `google/fonts` ships only variable masters and a variable
   font would need `fontVariations` on every style, which `copyWith(fontWeight:)` would then silently
   ignore. Static instances keep the ordinary Flutter weight mechanism working. Both licences ship as
   `fonts/HankenGrotesk-OFL.txt` and `fonts/JetBrainsMono-OFL.txt`.
2. **JetBrains Mono is declared at 400 *and* 500, where the decision says 500.** `AppTypeRoles.mono`
   reads weight 400 and this change moved no metric. Declaring 500 alone would not have failed — the
   engine picks the nearest declared face — so the role would have claimed 400 and rendered 500, with
   nothing anywhere saying so. Bundling both keeps the token honest and costs one file, and means the
   `data-mono` repoint in question 22 needs no download when it is taken.
3. **The family is named on every role, not only on `ThemeData.fontFamily`.** A component theme's text
   style *replaces* the text theme's rather than merging onto it, so `ListTile`, `Chip`,
   `InputDecoration`, `SnackBar` and `Dialog` reach the engine with whatever the role names and
   nothing else. `spiritTheme.fontFamily` had named Roboto since 2026-08-16 and was never reaching
   those five. It is kept as the fallback for widgets built from no role at all.

## Decision 23 — how money is set, taken for the till only, 2026-08-22

**This is the half of question 22 that was left open**, and it is answered here for one surface
rather than for the app. Question 22's own words: *"the design sets money in `data-mono`, not in a
tabular interface face — 65 of the places a `currency-kes` colour appears also carry
`text-data-mono`. `numericBody` was left in the interface family anyway, because moving every price
in the app into the mono face is a composition decision rather than a metric one. That is the one
piece of question 22 still open, and it is a per-surface judgement."*

**Decision: on the till, money is `AppTypeRoles.mono` in `AppTextRoles.money`. Nowhere else changes.**

`AppTextRoles.money` is `currency-kes` `#45F28D`, which had been quoted in `_ProfoundVerdant` and
deliberately wired to nothing since the palette landed. It is a role now because hard rule 2 forbids
a widget holding a hex, and because the next phase that wants it should read a name rather than copy
a value. **The token existing is not permission to sweep it.** Every other price in the app stays
`numericBody` in `text.primary`/`text.secondary` until its own phase decides otherwise.

### Why the till and not the app

The till is the only surface where money is the *subject* rather than a column. A cashier reads a
figure aloud to a customer while four other figures are on screen, and the design's own emphasis is
strongest exactly there: both served Phase 03 screens set every price and every line amount in
`data-mono` and `currency-kes`. A back-office report is a column of amounts that must line up, which
is what `numeric.body`'s tabular figures are for and what a proportional-metric mono face does not
improve.

### The four places it lands, and the one it does not

| Figure | Role | Colour |
|---|---|---|
| Product tile price | `mono` | `text.money` |
| Cart line amount | `mono` | `text.money` |
| Compact cart bar total | `mono` | `text.money` |
| Cart footer total | **`numericHero`** | `text.money` |
| A price the till cannot record exactly | `mono` | `status.problem.fg` |

**The grand total keeps the interface face, and the two designs are why.** ST-035 sets it in
`font-data-mono`; ST-036 sets it in `font-headline-lg-mobile`, which is the interface face. They
disagree, so the tie-breaker applies to the half they disagree about and not to the half they agree
on: the colour moves and the face does not. There is a mechanical reason as well — that figure is a
`RollingNumber`, which asserts a tabular style, and a monospace face being fixed-width is not the
same property as `FontFeature.tabularFigures()`; the assertion is what stops every digit position
shifting mid-roll.

**A figure that is not an amount does not wear the money colour.** `Price unusable` and a line that
cannot be priced take `status.problem`, because a colour that means *this is what it costs* must not
be worn by a thing that is not a cost.

### What this does not settle

Whether the back office follows. Phases 04, 05 and 06 each have surfaces full of money, and each is
free to take this pair, to take the colour alone, or to keep `numericBody`. This section is the
precedent, not the rule.

## Decision 24 — a stock badge states the figure, never `Out of stock`, 2026-08-22

**Phase 04's second acceptance criterion is that stock display does not imply sales are blocked by
availability, and both catalog surfaces failed it.** `tenantProductStanding` gave any product at or
below zero a `problem` badge reading `Out of stock`, and neither screen 17 nor screen 18 said
anything to qualify it.

**Decision: the badge label is the quantity — `-3 in stock`, `0 in stock` — and each catalog surface
states ST-039's non-blocking sentence once, under its product heading. `AppStatus.problem` is kept.**

### Why the old label was wrong rather than merely blunt

`Out of stock` asserts that the product cannot be sold. This product never blocks a sale on a stock
count: Firestore Rules permit signed stock deliberately, Phase 04 resolved item 4 as *"may be
negative, and never blocks a sale"*, and `audits/phase-04.md` records the same fact. Phase 03 had
already refused these exact two words one file over — `checkout_cart_panel.dart:1670` reasons that
*"`0 in stock` says what `Out of stock` says; `-3 in stock` says something it cannot"* — so the app
was saying two different things about one product fact on two screens.

The catalog is where it mattered most, for two reasons the till does not have. It lists **every**
product, so the badge is the page's only summary of a zero figure; and it is the one catalog surface a
**cashier** sees, read-only, where a red badge is exactly what would stop somebody selling.

### Why `problem` is kept and the words carry the meaning

§2.1 names *"out of stock"* among `problem`'s three meanings, and ST-039 draws this same row in
`text-error` on `bg-error-container/10`. The colour is not the defect — a figure at or below zero is
worth a correction. The defect was the claim. §9 is satisfied because the words rather than the colour
carry it, and the words are now true.

### The sentence, and why it is a page line rather than a per-row one

`tenantCatalogStockNeverBlocks` is *"A sale is never blocked by a stock count. A product whose
recorded quantity has reached or passed zero can still be sold."* Its first clause is ST-039's own,
which `audits/phase-04.md` calls "the exact non-blocking stock sentence"; the app already ended two
other sentences with it (`checkout_cart_panel.dart:1282`, `stock_adjustment_panel.dart:528`), so this
is one constant reaching the two screens that were missing it rather than a third copy.

ST-039 draws it inline under the product name. It is a page line here for the reason the till puts its
own version in one freshness strip rather than on every tile: on a phone a 100-character warning
repeated down six cards is the loudest thing on the screen, and `RecordItem` has no warning slot that
is not `provenance` — which Phase 04's own handover forbids quietening. Stated unconditionally, because
a conditional section invisible in every capture is not covered.

### What this does not settle

Whether zero deserves a softer status than below-zero. They are arguably different facts — zero is a
shop that sold out, below zero is a record that disagrees with itself — and ST-039 shows only the
below-zero row, so the design defines nothing for zero. One status is kept because splitting it is a
second judgement the evidence does not force.

## Decision 25 — Phase 04's mobile records are derived from §4.3, because ST-040 does not exist

**ST-040 is one ninth of a design.** Its served HTML is 9,218 bytes and stops after
`1. Cashier — Product catalog`; `EXPORT_MAP.md` uses that byte count as a freshness fingerprint, so
the truncation is the artifact rather than a failed download. There is no Stitch connector in this
session and mutation needs human authorisation, so the missing eight sections cannot be generated.

**Decision: the mobile composition for every Phase 04 route except screen 20 is `RecordList`'s own
responsive contract, and it is recorded as a derivation rather than as a design implemented.**

The derivation is not an invention. `RecordList.formFor` already decides what a table becomes at each
band — `stackedCards` below 768, `twoColumnCards` to 1023, `table` at 1024 — and ST-039's section 8 is
a labelled 834px specimen of exactly that transformation. So the derived screens are ST-039's accepted
structures rendered through the contract its own specimen draws.

**What changed is the evidence, not the composition.** All thirteen catalog and stock routes were
photographed at 1440 and 411 only, so `twoColumnCards` appeared in no picture of any real route; they
now render at all four of `responsiveViewports`. The transformation holds: at 834 the movement feed
draws two cards carrying the delta, three attributes, the provenance line and the `Open ledger`
action, and at 411 the same record stacks with nothing dropped. Criterion 4 is met on evidence.

### The one route this does not cover

**Screen 20 and its two report states are not derived from the contract and were not migrated.** Their
rows are `CheckboxListTile`s whose subtitle is a bullet-separated sentence — `Household ▪ 5901234123457
▪ 145.00 ▪ costs 112.00` — which is the pre-migration shape §5.2 replaces with key-value attributes,
and the report rows below them are raw `Card`s. The note already at `bulk_catalog_panel.dart` argues
the same thing this decision concludes: migrating screen 20 to `RecordList` is the work step 6 did for
twelve screens and is larger than a Phase 04 slice. It is recorded as the phase's unfinished route
rather than half-done.

## Decision 26 — three shapes the product owner chose, over the design's evidence, 2026-08-23

**These are owner directions rather than readings of the design, and they are recorded that way on
purpose.** Every other decision in this file argues from the export, `DESIGN_RULES.md` or active
code. These three do not, and two of them reverse a decision that did. A shape is the owner's to
choose; what this section owes a later reader is the evidence it overrides, so nobody re-derives the
old answer and calls it a regression.

### 26a. Buttons, chips and input wells are `radius.pill` again

**The evidence points the other way and the notes this replaces were right about it.** Profound
Verdant's own CSS gives `.btn-primary` and its inputs `borderRadius.xl`; its status chips carry a
bare `rounded` — `0.125rem` — in 78 of the 82 places one appears; and its rendered screens are
square-cornered throughout. That is what moved buttons to `md`, chips to `sm` and wells to `md` on
2026-08-22.

**What takes the pill:** `AppButton`, `FilterChipBar`'s chip, the `AppTextField` well, the three
Material button themes, `chipTheme`, and the theme's `InputDecoration` border.

**What deliberately does not:** cards, rows, dialogs, sheets, banners, stat tiles, the snack bar, and
`StatusBadge`. A badge is read rather than pressed and was never a pill; and a fully round corner on
a wide surface is not a pill but a mistake — Flutter clamps a radius to half the shorter side, so 999
on a card would draw a lozenge.

**The token values did not move.** `sm` is still 2, `md` 8, `lg` 12, `pill` 999. This changes only
which component reads which role, which is the line `AppRadii`'s scale test and the component tests
already divide between them.

For the input well this is the third move of one value: v0.4 made it a pill at the owner's request on
2026-08-15, 2026-08-22 took it back to the design's corner, and this restores it. **417 of 536 images
moved**, which is the correct blast radius for a token change reaching every button, chip and field in
the app.

### 26b. More than one filter on a surface means dropdowns, not chip strips

**Decision: where a surface carries more than one filter, its filters are `AppSelect`. A single
filter stays a `FilterChipBar`.**

Sales totals is the surface this is about and the only one in the app with three filters open at
once. As chip strips their height grew with the business — one chip per colleague and one per
category — so a shop with twelve staff and nine categories pushed the figures the page exists for off
the bottom of a phone. A dropdown is a fixed height whatever the business holds, and the three
figures now sit on the first screen.

The other half of the rule matters as much: **one strip stays a strip.** A single chip row shows its
options without a tap, which is what `FilterChipBar` is for, and turning it into a dropdown would hide
information to no benefit. The till's category chooser and
`reconciliation_anomalies_panel.dart`'s filter keep theirs.

`AppSelectItem` gained a `key` for this. `FilterChipBar` keys every option and `DropdownMenuItem` had
none, so moving a filter between them would otherwise drop every option-level contract the surface
had. All nine option keys on the sales-totals surface are unchanged.

**One cost, stated rather than discovered later: a dropdown's options are not in a screenshot.** A
closed `DropdownButton` builds only the selected option, so hard rule 5's "every state appears in the
harness" is weaker for a dropdown filter than it was for a chip strip, where every option was always
rendered. A capture would have to open the menu, and an open Material menu is an overlay route. No
capture does this today and none did before either — the chip strips were photographed with their
options showing, which is the coverage this trades away.

### 26c. The password field shows asterisks

The field carried no placeholder at all from step 9 until now, on the reasoning that §5.2 forbids a
placeholder that restates its label — which was right about `Enter Password`, the string it deleted,
and wrong to conclude the field could therefore carry nothing.

**Decision: the placeholder is `********`, and `obscuringCharacter` is `*` to match.** Asterisks are
the permitted kind of placeholder: they are what the box will look like once somebody types in it,
which is an example rather than a second copy of the label. The two settings travel together for a
reason worth keeping — a placeholder showing asterisks over a field that types Flutter's default
bullets is a box that appears to change character set the moment it is touched. `AppTextField` gained
`obscuringCharacter` for this, defaulting to `*` for every obscured field in the app rather than only
this one.

## Non-blocking audit limitations

- The built-in Stitch connector in this chat retained an unauthenticated transport. Read-only audit
  calls succeeded through the configured API-key endpoint instead; a fresh Codex session should
  reload the connector configuration.
- Stitch retrieval was intermittent: `list_screens` ultimately returned all 26 screens, while some
  individual `get_screen` calls still alternated between success, invalid argument, not found, and
  service unavailable.
- Several post-edit downloadable HTML/screenshot artifacts remained stale even though the mutation
  response returned concrete DOM operations. Those screens remain render-review items, not approved.
- Phase 01 source screens ST-028 through ST-031 were returned by successful generation/edit responses
  but are not present in `get_project.screenInstances`; they need canvas-link review. ST-027 and ST-029
  also retained pre-correction downloadable screenshots after successful DOM edits.
- Phase 02 correction returned derived successors ST-032/ST-033 instead of overwriting ST-012/ST-023.
  Final DOM corrections succeeded, but ST-033 still serves its pre-correction artifact, ST-032
  individual retrieval is intermittent, and project retrieval later returned invalid argument.
- Phase 03 correction returned derived successors instead of overwriting ST-026/ST-009/ST-011.
  ST-035 is retrievable and visually reviewed. ST-036 returned invalid argument after successful
  generation, and response truncation hid the exact mobile-browse successor ID. Project instances
  still omit every Phase 03 successor. Per the operating contract, neither mobile screen was
  regenerated; recover and review them in the Stitch UI.
- Phase 04 correction returned derived successors rather than overwriting ST-002/ST-007. The first
  ST-037/ST-038 pair was superseded by ST-039/ST-040 after visual review found compressed routes,
  role-mode navigation, generic bottom navigation, invented products, and missing audit states.
  ST-039's final audit-record correction completed without a new source ID, but retrieval still serves
  the pre-correction artifact; ST-040 immediately returns invalid argument. Do not regenerate either
  merely to refresh retrieval; review them in the Stitch UI.
- Phase 05 correction returned derived ST-041/ST-042 rather than overwriting ST-019/ST-020/ST-022/
  ST-025. ST-041 is retrievable and partially verified, but its exact shift-correction action label
  and dense provenance still need review. ST-042 was later superseded by approved mobile correction
  ST-043. ST-043 is freshly retrievable and removes the invented comparison/date/totals, but artifact
  inspection shows omitted exact filter, oldest-first, server-trigger, counted-cash, server-derived,
  ordering, and evidence-provenance phrases. These are bounded copy/provenance defects, not permission
  to invent replacement values.
- The final approved copy-only ST-041/ST-043 mutation reports those phrases and the desktop action
  label as corrected. ST-041 still serves its pre-edit artifact and ST-043 retrieval is invalid, so
  both require canvas review. The mutation log changed `Expected: 12` to `Expectation ID: 12`; this is
  a known semantic defect and must be restored to `Expected: 12` before canonical approval. Phase 05
  is nevertheless closed; do not regenerate either screen merely to refresh retrieval.
- Phase 06 CREATE returned rejected ST-044/ST-045, and approved corrections produced successor chain
  ST-046/ST-047, ST-049/ST-048, and ST-050. The approved in-place ST-048 correction removes the
  invented Ceramic Mug, 16% tax, and refund amount; its retrieval remains stale. ST-050's inspected
  pre-final artifact renders Sections 03-05 without forbidden content. The final approved in-place
  ST-050 DOM correction adds `Cash over` and desktop `No closing summary` and raises all Section 03-05
  controls to at least 48px. Direct canvas-code copies then proved both first edits had not persisted.
  The approved exact-ID reapplications completed with concrete DOM operations, but mobile retrieval
  remains cached and desktop retrieval is invalid. Fresh canvas-code copies are required before
  canonical promotion or any additional mutation; Phase 06 execution itself is closed.
- Phase 07 REPLACE returned rejected ST-051/ST-052. Approved corrections produced ST-053/ST-054 and
  final ST-055/ST-056. Unlike several earlier phases, both final sources were freshly retrievable and
  their downloadable HTML and screenshots reflected the correction output. Fresh artifacts satisfy
  the Phase 07 content/RBAC/state checks; physical keyboard, focus, and device behavior remain part
  of the system audit rather than a reason for another Stitch mutation.
- Phase 08 REPLACE returned incomplete ST-057/ST-058. Corrections produced ST-059 through ST-062;
  ST-061/ST-062 are the strongest working pair. Successful DOM-operation logs record the missing
  printer, recovery, tablet, interaction, endpoint, and disabled-loading content, but individual
  retrieval still serves their pre-operation artifacts. Fresh fallback generations ST-063/ST-064
  were downloaded and rejected because they stop early. Review exact ST-061/ST-062 canvas code and
  renders before canonical promotion; do not substitute the incomplete fallback generations.
- Phase 09 CREATE returned incomplete ST-065/ST-066. Approved corrections produced ST-067 through
  ST-070. Fresh ST-070 HTML and screenshot pass the mobile content/state/accessibility review.
  ST-067's exact DOM operations complete the desktop semantics and 48px retry target, but
  `get_screen` continues to serve pre-operation file `e06f5798b3714ce39af875f0d764b62c`.
  Review the current ST-067 canvas code/render before canonical promotion; do not regenerate it only
  to refresh retrieval.
- A complete Phase 09 re-fetch found none of ST-065 through ST-070 in `list_screens` or
  `get_project.screenInstances`. Exact-ID retrieval nevertheless succeeds for ST-066, ST-067,
  ST-068, and ST-070; ST-065 and ST-069 return invalid argument. ST-070's downloaded HTML is
  byte-identical to the reviewed artifact, while ST-067 is byte-stable on its stale pre-operation
  file. Treat direct exact-ID evidence as authoritative for this audit and keep the list/canvas-link
  mismatch non-blocking.
- User-provided current canvas exports subsequently proved that neither ST-067 nor ST-071 persisted
  their reported DOM-only corrections. Fresh ST-071 remains the strongest desktop base but has
  bounded consequence, archived-warning, retry-help, and global-state defects. The authorized last
  variant ST-072 baked in those fixes but duplicated retry-help text into unrelated status chips;
  its returned artifact is rejected and exact-ID retrieval is invalid. A later authorized cleanup
  produced ST-073. Its exact-ID HTML and screenshot are fresh and directly verified: only the correct
  visible retry help remains, all prior lifecycle/state corrections persist, and desktop Phase 09 is
  no longer a rework item. Mobile ST-070 remains confirmed.
- Local screenshots are deterministic widget renders, not physical-device proof. Native keyboard,
  focus, printing, scroll performance, and motion need later device review.
