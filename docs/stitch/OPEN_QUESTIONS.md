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
| 19 | Radius scales collide | `AppRadii` keeps its four names and repoints the values: `sm` 8→**4**, `md` 12→**6**, `lg` 20→**8**, `pill` 999→**9999**. No call site changes |
| 20 | Families not bundled | **Bundle Hanken Grotesk and JetBrains Mono**, declaring only the weights the seven type roles use (400/500/600/700, mono 500). Offline-first, so bundled assets rather than a runtime fetch |
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

    See `audits/2026-08-22-wave-0-foundations.md` Finding 1 for the per-band table and the original
    blast-radius analysis.

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
