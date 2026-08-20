# Stitch screen index

Project: `7478406619239162026`

Audit date: 2026-08-20
Inventory source: `get_project.screenInstances`, `list_screens`, and post-edit `get_screen` calls.

Screen IDs are exact source IDs. Logical IDs are local coordination labels and do not rename Stitch
objects. `NORMALIZED` records a completed edit operation; it does not mean visual approval.

| Logical ID | Exact screen ID | Title returned by Stitch | Domain | Role | Device / size | Status | Reuse notes |
|---|---|---|---|---|---|---|---|
| ST-001 | `00b383316b39404ea4d2f5ef8b277148` | New Sale Terminal - Desktop (Normalized) | Checkout | All active | Desktop 2560x2048 | NORMALIZED / RENDER REVIEW | Task navigation; no VAT, draft, discount, or payment-verification claim. Downloadable render remained stale. |
| ST-002 | `084c238a51814cdca8b47a9cd2af594b` | Inventory Management - Desktop (Normalized) | Catalog/stock | Owner/admin/manager | Desktop 2560x2048 | NORMALIZED / SUPERSEDED | Phase 00 direction retained as history. Selected for Phase 04 correction; Stitch returned derived desktop successors ST-037 and ST-039. |
| ST-003 | `0b6372dd8443424d8dab3a6cde67bf85` | Business Settings - Desktop | Configuration | Owner/admin | Desktop 2560x2048 | NON-CANONICAL / UNTOUCHED | Broad unsupported settings remain; use ST-024 as the working direction. |
| ST-004 | `0f8359d6c2cb4169b2c2e6ca46a3979c` | Printer & Receipt Management - Desktop (Normalized) | Printing | Owner/admin | Desktop 2560x2048 | NON-CANONICAL / UNTOUCHED | Printer reference only; ST-010 is the Phase 00 canonical candidate. |
| ST-005 | `11638425d0ef43d9bd594865fb104279` | Staff Management - Desktop (Normalized) | Staff | Owner/admin/manager | Desktop 2560x2048 | REVIEW / UNTOUCHED | Title recovered through `list_screens`; inspect content before reuse. |
| ST-006 | `1dab954e4720472e97a3319d6ef8a8b9` | Receipt & Printing Status | Printing | All active | Mobile 780x2376 | REVIEW / UNTOUCHED | Mobile artifact recovered; content remains outside the Phase 00 edit set. |
| ST-007 | `220deae97920481393a45bf3e395384a` | Inventory & Stock Movements | Catalog/stock | Owner/admin/manager | Mobile 780x1768 | NON-CANONICAL / SUPERSEDED | Phase 04 confirmed unsupported reorder/low-stock UI and generic navigation. Selected for correction; ST-040 is the working mobile successor. |
| ST-008 | `23004c4bc0234a9a924b869d78cd4335` | Staff Directory | Staff | Owner/admin/manager | Mobile 780x950, resized | REVIEW / UNTOUCHED | Mobile artifact recovered; resized instance may still be a fragment. |
| ST-009 | `2de856e75de1444ba769736bc515a634` | Review Order & Pay | Checkout | All active | Mobile 780x1960 | NORMALIZED / SUPERSEDED | Phase 00 direction retained as history. Selected for Phase 03 correction; Stitch returned the mobile-cart successor recorded as ST-036. |
| ST-010 | `32cff1e0ae4f43ddad97b77b55e9be5c` | Printer & Receipt Management - High Fidelity | Printing | Owner/admin | Desktop 2560x2048 | CANONICAL CANDIDATE / RENDER REVIEW | One device: address, port, 32/48 columns, cutter, save, test, and honest test/queue semantics. |
| ST-011 | `3387f1da47014596b7dfa14f306d5310` | New Sale - Products | Checkout | All active | Mobile 780x1768 | NORMALIZED / SUPERSEDED | Phase 00 direction retained as history. Selected for Phase 03 correction; Stitch returned a derived mobile-browse successor whose exact source ID was not recoverable from the truncated response. |
| ST-012 | `34cba78694a14f64bd60d61bbaa4c4a8` | Manager Dashboard - Desktop (Normalized) | Home/navigation | Manager | Desktop 2560x2048 | NORMALIZED / SUPERSEDED | Phase 00 direction retained as history. Selected for Phase 02 correction; Stitch returned ST-032 as the role-aware successor instead of overwriting this source. |
| ST-013 | `35542e76038c4ae8814f1642b82fa042` | Shift Reconciliation - Desktop | Reconciliation | Owner/admin/manager | Desktop 2560x2048 | NON-CANONICAL / UNTOUCHED | Original reference; ST-022 is the normalized desktop direction. |
| ST-014 | `39332ac87674401695d5d41bf8d712d1` | Staff Management - Desktop | Staff | Owner/admin write; manager read | Desktop 2560x2048 | NORMALIZED / PARTIAL REVIEW | Four exact roles and write/read split. Later active-route cleanup returned unavailable and was not retried. |
| ST-015 | `4e6d521c24634b1ba4ea9fa027624784` | Logo | Brand asset | N/A | Unspecified 1024x1024 | REVIEW / UNTOUCHED | Verify ownership and monochrome/size behavior before adoption. |
| ST-016 | `73968e08ff6d46b6ac55d5c3649dd051` | Manager Dashboard - Desktop | Home/navigation | Manager | Desktop 2560x2048 | NON-CANONICAL / UNTOUCHED | Original telemetry-heavy reference; ST-012 is the normalized direction. |
| ST-017 | `8712bbee07a44d9e9d08bdf80fe952af` | Printer & Receipt Management - Desktop | Printing | Owner/admin | Desktop 2560x2048 | NON-CANONICAL / UNTOUCHED | Printer reference only; ST-010 is the Phase 00 canonical candidate. |
| ST-018 | `8d7268274be84292ac1bd3ba62fde5f5` | Analytical Reports - Desktop | Reporting | Owner/admin/manager | Desktop 2560x2048 | REVIEW / UNTOUCHED | Title recovered; ST-025 is the normalized direction. |
| ST-019 | `96bbb79a8594499c868f23bfaf3bd455` | Shift Reconciliation | Reconciliation | Owner/admin/manager read | Mobile 780x2074 | NORMALIZED / RENDER REVIEW | Manager write actions removed, inputs disabled, and exact mobile nav restored. |
| ST-020 | `9907aa744df54538a3ec2c9ccb17ea66` | Sales Analytics & Reports | Reporting | Owner/admin/manager | Mobile 780x2386 | NORMALIZED / RENDER REVIEW | Uses supported totals, tender data, shifts, and reconciliation status. Phase 05 may introduce evidence-backed visualizations; export remains unsupported. |
| ST-021 | `abb5972386884613a89130219e3bbf03` | Inventory Management - Desktop | Catalog/stock | Owner/admin/manager | Desktop 2560x2048 | REVIEW / UNTOUCHED | Title recovered; ST-002 is the normalized direction. |
| ST-022 | `d61525b378644169a72bab9c26e08728` | Shift Reconciliation - Desktop (Normalized) | Reconciliation | Owner/admin/manager read | Desktop 2560x2048 | NORMALIZED / RENDER REVIEW | Read-only Manager composition aligned to supported reconciliation states. |
| ST-023 | `d8679157b03842378c143b690adf4995` | Manager Dashboard | Home/navigation | Manager | Mobile 780x1892 | NORMALIZED / SUPERSEDED | Original retrieved artifact still showed telemetry and generic bottom navigation. Selected for Phase 02 correction; ST-033 is the role-aware successor. |
| ST-024 | `dce9916937f942b294ed7afaf5351158` | Business Settings - Desktop (Normalized) | Configuration | Owner/admin | Desktop 2560x2048 | NORMALIZED / PARTIAL REVIEW | Broad settings removed; currency and printer linkage retained. Fresh retrieval remains intermittent. |
| ST-025 | `fd37052cefe74241a967328f41eb0fc8` | Analytical Reports - Desktop (Normalized) | Reporting | Owner/admin/manager | Desktop 2560x2048 | NORMALIZED / PARTIAL REVIEW | Phase 00 removed unverified chart content, not chart-based presentation as a design option. Phase 05 may visualize supported metrics; Manager-nav cleanup still needs review. |
| ST-026 | `fdde927e21d6484a9b228209d91d909c` | New Sale Terminal - Desktop | Checkout | All active | Desktop 2560x2048 | NON-CANONICAL / SUPERSEDED | Original Kijani/VAT/payment-conflicting reference. Reused for Phase 03 because ST-001 retrieval returned invalid argument; ST-035 is the corrected working successor. |
| ST-027 | `4b5739a495cc411b9abce8dd46c54745` | Chilltent POS — Sign In States (Desktop) | Authentication | Public | Desktop 2560x2048 | NORMALIZED / RENDER REVIEW | Default, refused, unreachable, caps-lock, and busy states. Post-review DOM correction restored exact `Sign in` recovery and `Remember me`; downloadable screenshot remains pre-correction. |
| ST-028 | `cd38c0ed047248c9812a885250910d12` | Chilltent POS — Sign In States (Mobile) | Authentication | Public | Mobile 780x3638 | CANONICAL CANDIDATE / VISUAL REVIEWED | Responsive single-column equivalents of the five sign-in states; no unsupported recovery, registration, or social sign-in. Source screen is retrievable but is not listed as a project canvas instance. |
| ST-029 | `083b3bb1fb4046489f8db6d937fe4621` | Chilltent POS — Tenant Entry States (Mobile) | Tenant entry | Signed-in identity | Mobile 780x1768 | NORMALIZED / RENDER REVIEW | Choose, verify, request, no-business, invite, failure, and routing-split states. Unsupported bottom navigation was removed by DOM edit; downloadable screenshot remains pre-correction. Source is not linked as a project canvas instance. |
| ST-030 | `fa22fc86bb614d3fabd724ec5f376681` | Chilltent POS — Tenant Entry States (Desktop) | Tenant entry | Signed-in identity | Desktop 2560x2048 | NON-CANONICAL / SUPERSEDED | Intermediate layout variant invented code verification, request reason, decline, and altered failure copy. Retained as history only; ST-031 is the corrected successor. |
| ST-031 | `ba78e973493a4415be02b76fe9ee31a7` | Chilltent POS — Tenant Entry States (Desktop Normalized) | Tenant entry | Signed-in identity | Desktop 2560x2048 | CANONICAL CANDIDATE / VISUAL REVIEWED | Corrected out-of-band email verification, request/confirmation, business selection, invite/failure states, and conjunctive platform-routing note. Fresh mutation render reviewed; later individual retrieval is intermittent. Source is not linked as a project canvas instance. |
| ST-032 | `34025255d4fe4100bc41dd079642a0e1` | Chilltent POS — Role-Aware Home & Navigation (Desktop) | Home/navigation | Owner/admin/manager/cashier specimens | Desktop 2560x2486 | NORMALIZED / RENDER REVIEW | Owner/Administrator hero plus exact Manager/Cashier route specimens, shift and separate checkout/print evidence, and tenant-switch states. Final DOM correction removed false shift destinations and restored common routes; fresh retrieval is intermittent. |
| ST-033 | `66cb86bbe714430fb1103905935b1c75` | Chilltent POS — Role-Aware Home & Navigation (Mobile) | Home/navigation | Cashier hero; owner/admin/manager specimens | Mobile 780x3606 | NORMALIZED / RENDER REVIEW | Deliberate shift-first Cashier task hub with authorized role additions and tenant-switch states. Final DOM correction removed the false shift route, restored default/sign-out controls, and exact minor-unit/evidence copy; downloadable artifact remains pre-correction. |

| ST-034 | `e95caf861f38426580b43519d4cbb901` | Chilltent POS — New Sale (Desktop & Tablet) | Checkout | All active | Desktop 2560x3476 | NORMALIZED / SUPERSEDED | First Phase 03 successor. Visually reviewed; correct KES 155.00 and durability/printing separation, but it omitted the required tablet specimen and guessed a connection-specific save error. Superseded by ST-035. |
| ST-035 | `e85cc69d6db24026bc5eeff21a6f1b7f` | Chilltent POS — New Sale (Desktop & Tablet Normalized) | Checkout | All active | Desktop 2560x4838 | CANONICAL CANDIDATE / VISUAL REVIEWED | Dense sale/cart composition, exact generic save refusal, durable/save/confirm/print states, and a labeled 834px two-region tablet specimen. Profound Verdant retained. |
| ST-036 | `0ece972d5e0f4deca20f8ed12686d618` | Chilltent POS — New Sale (Mobile Cart) | Checkout | All active | Mobile 780x2146 | NORMALIZED / RENDER REVIEW | Staged cart with KES 135.00, quantity/removal, asserted tender, Save sale, durable receipt, later confirmation, and independent print failure. Successful mutation returned the source ID, but subsequent retrieval returned invalid argument. |
| ST-037 | `8fff386768994eed8fa3dbd08f173684` | Chilltent POS — Catalog & Stock (Desktop) | Catalog/stock | Owner/admin/manager/cashier specimens | Desktop 2560x2048 | NON-CANONICAL / SUPERSEDED | First Phase 04 desktop successor. Removed reorder policy but compressed routes, included unrelated navigation, and omitted required bulk/audit/state coverage. Superseded by ST-039. |
| ST-038 | `df83e2b93aa74dbb8d809e281093f8cb` | Chilltent POS — Catalog & Stock (Mobile) | Catalog/stock | Owner/admin/manager/cashier specimens | Mobile 780x1768 | NON-CANONICAL / SUPERSEDED | First Phase 04 mobile successor retained generic bottom navigation, role-mode tabs, invented products, and incomplete state coverage. Superseded by ST-040. |
| ST-039 | `1273644f84ce4978a64bcff21fee7728` | Chilltent POS — Catalog & Stock Route Suite (Desktop) | Catalog/stock | Owner/admin/manager/cashier specimens | Desktop 2560x10000 | NORMALIZED / RENDER REVIEW | Long-form role-aware catalog, bulk, product-stock, tablet, and state suite. Fresh render verified core role/bulk/state structure; a final in-place audit-record correction completed but retrieval remains on the pre-correction artifact. |
| ST-040 | `04e000e868734d41a53b30acbc810703` | Chilltent POS — Catalog & Stock Mobile Route Suite | Catalog/stock | Owner/admin/manager/cashier specimens | Mobile 780x12000 | NORMALIZED / RENDER REVIEW | Staged mobile read/manage/bulk/stock/feed/ledger family with unsupported generic navigation removed. Successful correction returned the source ID; immediate retrieval returned invalid argument. |
| ST-041 | `80bcf18734c44f5dad68f49caf544058` | Chilltent POS — Reporting & Reconciliation (Desktop Suite) | Reporting/reconciliation | Owner/admin/manager specimens | Desktop 2560x4752 | NORMALIZED / RENDER REVIEW | Final DOM operation changed the owner/admin action to `Correct this shift’s totals`, but retrieval still serves the pre-edit `Apply Correction` artifact. Dense provenance and the fresh label need canvas review before canonical promotion. |
| ST-042 | `7dbcfee9a4134038804e32ed000c8e9b` | Chilltent POS — Reporting & Reconciliation (Mobile Suite) | Reporting/reconciliation | Owner/admin/manager specimens intended | Mobile 780x1768 | NON-CANONICAL / SUPERSEDED | Incomplete artifact showed unsupported `+14% vs Prev`, a 2023 date, and invented totals. Superseded by corrected mobile successor ST-043. |
| ST-043 | `e54d5ed714c44b9caa93b580c9c01eff` | Chilltent POS — Reporting & Reconciliation (Mobile Suite) — Normalized | Reporting/reconciliation | Owner/admin/manager specimens | Mobile 780x7794 | NORMALIZED / RENDER REVIEW | Final DOM operations restored filter, scope, oldest-first, server-trigger, counted-cash, server-derived, ordering, and history copy. Immediate retrieval then returned invalid argument. Mutation log also mislabels existing `Expected: 12` as `Expectation ID: 12`; treat that label as non-canonical pending canvas correction. |
| ST-044 | `c27739cfddce4d1b80f1d912a12b6255` | Sales, Receipts, Shifts & Returns — Desktop / Tablet | Sales/receipts/shifts/returns | Owner/admin/manager/cashier specimens intended | Desktop 2560x2048 | NON-CANONICAL / SUPERSEDED | Initial Phase 06 desktop source was blank/unreadable. Selected for the approved correction; Stitch returned derived ST-046. |
| ST-045 | `dc3114027cc6484f8b780add43995b6a` | Sales, Receipts, Shifts & Returns — Mobile | Sales/receipts/shifts/returns | Owner/admin/manager/cashier specimens intended | Mobile 780x1768 | NON-CANONICAL / SUPERSEDED | Initial mobile fragment had unsupported bottom navigation and omitted downstream routes. Selected for correction; Stitch returned derived ST-047. |
| ST-046 | `cb7e953594294ad18ffb16e126566280` | Chilltent POS — Sales, Receipts & Returns (Desktop Suite) — Normalized | Sales/receipts/shifts/returns | Owner/admin/manager/cashier specimens intended | Desktop 2560x2048 | NON-CANONICAL / SUPERSEDED | Receipt-only, misbranded correction selected for the approved final pass; Stitch returned derived ST-049. |
| ST-047 | `06ad7c6b69ca41dabd6b950435fad557` | Chilltent POS — Sales, Receipts & Returns (Mobile Suite) — Normalized | Sales/receipts/shifts/returns | Owner/admin/manager/cashier specimens | Mobile 780x7452 | NON-CANONICAL / SUPERSEDED | Partial mobile correction selected for the approved final pass; Stitch returned derived ST-048. |
| ST-048 | `f2b25ce06fd4404fb08f993f64aeaf17` | Chilltent POS — Sales, Receipts & Returns (Mobile Suite) — Final Normalized | Sales/receipts/shifts/returns | Owner/admin/manager/cashier specimens intended | Mobile 780x9470 | NORMALIZED / RENDER REVIEW | Direct canvas-code evidence showed the first edit had not persisted. The approved exact-ID reapplication again removes the mug/tax/refund content and restores White bread loaf, Mandazi, KES 150.00, Brian Kimani, stale-loaf, and no-stock-restored facts. Retrieval still serves the pre-edit file; recopy canvas code before approval. |
| ST-049 | `a53adf8e86b5429d86b883790af76ecc` | Chilltent POS — Sales, Receipts & Returns (Desktop Suite) — Final Normalized | Sales/receipts/shifts/returns | Owner/admin/manager/cashier specimens intended | Desktop 2560x14000 | NON-CANONICAL / SUPERSEDED | Sections 01-02 only. Selected for the approved surgical correction; Stitch returned derived ST-050. |
| ST-050 | `9f9d275f6ac8463c9dac306d17fbc784` | Chilltent POS — Sales, Receipts & Returns (Desktop Suite) — Complete Normalized | Sales/receipts/shifts/returns | Owner/admin/manager/cashier specimens | Desktop 2560x14000 | NORMALIZED / RENDER REVIEW | Direct canvas-code evidence showed the first edit had not persisted. The approved exact-ID reapplication appends `Cash over` and `No closing summary` and raises Section 03-04 controls to at least 48px; Section 05 has no controls. Retrieval now returns invalid argument; recopy canvas code before approval. |

## Design-system asset

| Asset | Name | Version | Current disposition |
|---|---|---:|---|
| `assets/4c1cc58b4aed4b1693e6f8113ba1009a` | Profound Verdant | 1 | RETAINED, NOT MUTATED; working semantic references use surface `#071610` and primary `#4BE277`. |

## Canvas observations

Phase 00 edited 13 existing screen IDs and left the other 13 screens untouched. Phase 01 created five
source screens: four working responsive state suites and one superseded intermediate variant. Only
ST-027 currently appears in `get_project.screenInstances`; ST-028 through ST-031 require canvas-link
review even though their successful generation responses returned exact source IDs and artifacts.
Stitch's downloadable artifacts still lag some completed DOM edits, so no edited screen is marked
approved solely from an edit response. No screen was deleted, moved, grouped, hidden, or archived.
Manual canvas grouping remains a later Stitch UI task because no connected tool supports it.

Phase 02 selected ST-012 and ST-023 for `CORRECT`, but Stitch produced derived source screens ST-032
and ST-033. The original sources remain as superseded history. Project retrieval became invalid-
argument after the final correction, so canvas-instance linkage for the successors needs visual review.

Phase 03 selected ST-026, ST-009, and ST-011 for `CORRECT`; Stitch again produced derived source
screens rather than overwriting the sources. ST-034 was the first desktop/tablet successor and ST-035
is its bounded corrected successor. ST-036 is the mobile-cart successor. The mobile-browse successor
was present in the successful mutation response, but its exact ID was lost to response truncation and
neither it nor the other Phase 03 successors appears in `get_project.screenInstances`. Do not
regenerate it; recover its ID and review all mobile renders in the Stitch UI.

Phase 04 selected ST-002 and ST-007 for `CORRECT`. The first successors ST-037/ST-038 exposed
compression and unsupported-navigation conflicts, so one bounded correction produced long-form
desktop/mobile route suites ST-039/ST-040. ST-039 was freshly reviewed before a final in-place
audit-record correction; its downloadable artifact then remained stale. ST-040 immediately returned
invalid argument. Neither final successor appears in current project instances, so both require a
fresh Stitch UI render/canvas-link review and must not be regenerated merely to refresh retrieval.

Phase 05 selected ST-019, ST-020, ST-022, and ST-025 for one `CORRECT` operation. Stitch consolidated
them into derived ST-041/ST-042 rather than overwriting the four sources. ST-041 was retrieved and
visually/structurally checked. ST-042's mutation artifact was checked, but individual retrieval then
failed; the artifact is visibly non-conforming and remains a rework item rather than a canonical
mobile direction. No second generation or correction was attempted in Phase 05.

An explicitly approved Phase 05 remediation later targeted ST-042. A combined ST-041/ST-042 edit was
rejected as invalid and made no mutation; the narrowed mobile correction succeeded as derived ST-043.
Fresh retrieval and artifact review confirmed its 780x7794 full-height composition and removal of the
unsupported ST-042 data. ST-041 was unchanged, and ST-043 retains bounded copy/provenance omissions.

The user then authorized the final Phase 05 copy-only pass on ST-041/ST-043. Stitch reported successful
in-place DOM operations. ST-041 retrieval continues to serve the old `Apply Correction` artifact;
ST-043 immediately returns invalid argument. The operation log also shows one semantic regression:
the existing anomaly field `Expected: 12` was relabelled `Expectation ID: 12`. Per the stale-retrieval
rule no regeneration/repeated correction was issued. Phase 05 is closed with both screens requiring
render review before canonical promotion.

Phase 06 used the authorized `CREATE` operation and returned ST-044/ST-045. Post-generation review
rejected both artifacts. Approved corrections produced ST-046/ST-047, then ST-049/ST-048, and the
surgical pass corrected ST-048 in place while deriving desktop ST-050 from ST-049. A final approved
in-place correction on exact ST-050 added the missing `Cash over` and `No closing summary` shift
specimens and raised all Section 03-05 interactive targets to at least 48px. The complete desktop
route trail and forbidden-content exclusions were verified on the immediately preceding fresh
artifact; subsequent retrieval succeeds for both screens but serves their pre-edit artifacts.
Phase 06 is therefore closed as `COMPLETED / RENDER REVIEW`, not canonical approval. No design-system
asset was changed.
