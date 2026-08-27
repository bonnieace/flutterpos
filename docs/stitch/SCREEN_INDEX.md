> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Stitch screen index

Project: `7478406619239162026`

Audit date: 2026-08-21
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

| ST-051 | `2070e8e96c1b4110bdfc462366b584ca` | Chilltent POS — Staff & Access (Desktop / Tablet) | Staff/access | Owner/admin write; manager read intended | Desktop 3072x2048 | NON-CANONICAL / SUPERSEDED | Initial Phase 07 replacement stopped after the populated directory and invented Access Management, Roles, Invites, Logs, and unrelated navigation. Superseded by ST-053. |
| ST-052 | `deaba05c2c18441388e1aa2a215669f9` | Chilltent POS — Staff & Access (Mobile) | Staff/access | Owner/admin write; manager read intended | Mobile 780x1768 | NON-CANONICAL / SUPERSEDED | Initial mobile replacement rendered only two people, abbreviated Administrator as Admin, and invented Roles/Invites/Settings navigation. Superseded by ST-054. |
| ST-053 | `411f3325f8b542248143afde789524e8` | Chilltent POS — Staff & Access (Desktop / Tablet) | Staff/access | Owner/admin write; manager read | Desktop 2560x10172 | NORMALIZED / SUPERSEDED | Substantial six-section successor with correct RBAC and lifecycle; superseded for bounded copy, cancellation-help, expired-link recovery, and Manager tablet fixes by ST-055. |
| ST-054 | `efdd3245c2954c14a3c80d63cc6e02d1` | Chilltent POS — Staff & Access (Mobile) | Staff/access | Owner/admin write; manager read intended | Mobile 780x3150 | NON-CANONICAL / SUPERSEDED | Correct directory and Manager read-only opening, but actual HTML ended after Section 02 and used icon-only row actions. Superseded by ST-056. |
| ST-055 | `740c94b5b6444359b796a16f32347e17` | Chilltent POS — Staff & Access (Desktop / Tablet) — Final Normalized | Staff/access | Owner/admin write; manager read | Desktop 2560x10764 | CANONICAL CANDIDATE / VISUAL REVIEWED | Fresh artifact verifies exact roles, five records/actions, Manager zero-write composition, forms, all consequence confirmations, state/link matrix, and 834px Owner/Administrator plus Manager transformation. Controls resolve to at least 48px. |
| ST-056 | `ed557d273cea4784a5c7a7cac47691a9` | Chilltent POS — Staff & Access (Mobile) — Final Normalized | Staff/access | Owner/admin write; manager read | Mobile 780x12822 | CANONICAL CANDIDATE / VISUAL REVIEWED | Fresh long-form artifact verifies labeled row actions, expanded invitation actions, Manager zero-write composition, forms, all five confirmations, and page/stale/expired-link states without unsupported navigation or roles. Controls are 48px minimum. |

| ST-057 | `297e9e7c97e5453f9ae269552f924c7f` | Chilltent POS — Settings & Printing (Desktop / Tablet) — Normalized | Configuration/printing | Owner/admin config; queue all intended | Desktop 2560x2048 | NON-CANONICAL / SUPERSEDED | Initial Phase 08 replacement rendered only the four currency specimens. Superseded by ST-059. |
| ST-058 | `218035ab052244c9b9c21aef8b87bf23` | Chilltent POS — Settings & Printing (Mobile) — Normalized | Configuration/printing | Owner/admin config; queue all intended | Mobile 780x3158 | NON-CANONICAL / SUPERSEDED | Initial mobile replacement stopped after a minimal queue and used the unrelated `Staff Portal` heading. Superseded by ST-060. |
| ST-059 | `0560439c79ce4be4b095a523c218261d` | Chilltent POS — Settings & Printing (Desktop Canonical) — Phase 08 Normalized | Configuration/printing | Owner/admin config; queue all | Desktop 2560x5012 | NORMALIZED / PARTIAL REVIEW | Fresh artifact verifies exact currency fields, core printer fields, device-local populated queue, and unreadable-record disclosure. It still omits most printer outcome states, queue recovery/empty/read-only states, the 834px tablet frame, and the interaction ledger. Not a canonical candidate. |
| ST-060 | `b38ea012bde44303a926c5c9ea54937d` | Chilltent POS — Settings & Printing (Mobile) — Final Normalized | Configuration/printing | Owner/admin config; queue all | Mobile 780x12908 | NORMALIZED / PARTIAL REVIEW | Fresh artifact verifies currency lifecycle, direct-TCP form/test states, device-local queue, unreadable record, sending/success, and non-retryable setup/browser states. Endpoint-change/write-failure/read-only/retry-failure details and one waiting-row endpoint remain incomplete. Not a canonical candidate. |
| ST-061 | `1701f2f2ad1546cd977e3d2cfd25cc16` | Chilltent POS — Settings & Printing (Desktop Canonical) — Final Completion | Configuration/printing | Owner/admin config; queue all | Desktop 2560x24000 | NORMALIZED / RENDER REVIEW | Correction logs add printer outcomes, queue recovery, 834px tablet evidence, and an interaction ledger. Retrieval still serves file `b7870f64505147cbbe83796140ebecab`, which predates those DOM operations; canvas review is required. |
| ST-062 | `9fb29b6ac7ba48489b9a5fb575a48f5f` | Chilltent POS — Settings & Printing (Mobile) — Phase 08 Final Completion (v2) | Configuration/printing | Owner/admin config; queue all | Mobile 780x12950 | NORMALIZED / RENDER REVIEW | Correction logs restore the full device-local queue, add printer outcomes and complete mobile ledgers, and record the missing endpoint/loading micro-fix. Retrieval still serves file `74ac285281d54f449a6e25d113d5859d`; exact final canvas code must be reviewed. |
| ST-063 | `d8c41fb7d7f6469191b21b281062e3b0` | Chilltent POS — Settings & Printing — Mobile Canonical | Configuration/printing | Owner/admin config; queue all intended | Mobile 780x3020 | NON-CANONICAL / REJECTED | The returned artifact ends during Printer configuration and omits the queue and interaction ledger. The screen endpoint was not yet retrievable; returned HTML/screenshot were inspected directly. |
| ST-064 | `52a6154f4d8e43d496a142cee1393ad8` | Chilltent POS — Settings & Printing — Desktop Canonical | Configuration/printing | Owner/admin config; queue all intended | Desktop 2560x2048 | NON-CANONICAL / REJECTED | Fresh artifact contains only published currency, one printer form, and one populated queue row. It omits the promised state matrices, tablet evidence, and interaction ledger. |
| ST-065 | `57321255989a43c09afabd18be5a0b30` | Chilltent POS — Platform Operations (Desktop / Tablet) — Phase 09 | Platform operations | Platform superAdmin intended | Desktop 2560x2438 | NON-CANONICAL / SUPERSEDED | Initial Phase 09 creation stopped after the shell, pending reviews, active/suspended records, and a compressed ledger. Superseded by ST-067; exact-ID re-fetch now returns invalid argument. |
| ST-066 | `9eda47b71aa647cd9c7548dc8ce8890c` | Chilltent POS — Platform Operations (Mobile) — Phase 09 | Platform operations | Platform superAdmin intended | Mobile 780x3786 | NON-CANONICAL / SUPERSEDED | Initial mobile creation stopped after authority and pending-review content. Superseded by ST-068. |
| ST-067 | `0ac6b3b719dd4573b1208445d171ff78` | Chilltent POS — Platform Operations & Global Authority — Phase 09 Canonical Suite | Platform operations | Platform superAdmin intended | Desktop 2560x12714 | NON-CANONICAL / SUPERSEDED | Exact-ID retrieval and user-copied current canvas code both prove the recorded DOM corrections did not persist. The source retains invented lifecycle callables and other pre-correction semantics. Superseded by ST-071. |
| ST-068 | `a2a68ab710db4bdd8bc3a0df89631688` | Chilltent POS — Platform Operations (Mobile) — Phase 09 Canonical Suite | Platform operations | Platform superAdmin intended | Mobile 780x15786 | NON-CANONICAL / SUPERSEDED | First long-form mobile successor included all principal routes but retained lifecycle/global semantics and prose-only state gaps. Superseded by ST-069. |
| ST-069 | `9a27aa1c5de64228ac85e395e98e3b8d` | Chilltent POS — Platform Operations (Mobile) — Canonical Phase 09 Suite | Platform operations | Platform superAdmin | Mobile 780x19632 | NORMALIZED / SUPERSEDED | Semantic correction restored the exact authority, transitions, callables, records, and global-status consequences, but route state matrices remained incomplete. Superseded by ST-070; exact-ID re-fetch now returns invalid argument. |
| ST-070 | `79c011b38c4c4bfea3f0db1a2145c366` | Chilltent POS — Platform Operations (Mobile) — Phase 09 Final Normalized Suite | Platform operations | Platform superAdmin | Mobile 780x27072 | CANONICAL CANDIDATE / VISUAL REVIEWED | Fresh HTML and full-height screenshot verify all seven sections, four concrete route state matrices, exact records/callables/transitions, exact-UID global status, relationship warnings, result evidence, separate mobile sign-out, and 48px minimum controls without prohibited tenant authority or bulk actions. Re-fetch returned the identical HTML SHA-256 `946E809B…E4E2366`. |
| ST-071 | `9eb5043c3c45455b96c920eb49bbfcb6` | Chilltent POS — Platform Operations & Global Authority — Final Canonical Suite (Desktop) | Platform operations | Platform superAdmin | Desktop 2560x13564 | NORMALIZED / PARTIAL VISUAL REVIEW | Fresh HTML and screenshot verify the distinct shell, exact authority, records, five `setTenantLifecycle` plus two `setGlobalUserStatus` rows, exact UID, relationship warnings, dialogs, result metadata, tablet frame, and 48px controls. It retains bounded matrix/copy/state defects. Event `356c191b` corrected them, but user-copied current canvas code proves those DOM operations did not persist. |
| ST-072 | `85d612f037d745beb304a7cf078cea11` | Chilltent POS — Platform Operations & Global Authority — Final Successor Suite (Desktop) | Platform operations | Platform superAdmin | Desktop 2560x14614 | NON-CANONICAL / REJECTED | Final fresh variant fixes the bounded ST-071 lifecycle, archived-warning, visible-help, busy/success, and archival-copy defects, but duplicates `Reuses the same operation/request ID.` into unrelated invalid, permission, failure, self-disable, and archived-status chips. Returned HTML/screenshot were inspected; exact-ID retrieval is invalid. |
| ST-073 | `3c3f120ed8fe4f5c88946b5e9a54d814` | Chilltent POS — Platform Operations & Global Authority — Final Successor Suite (Desktop) | Platform operations | Platform superAdmin | Desktop 2560x14576 | CANONICAL CANDIDATE / VISUAL REVIEWED | Fresh exact-ID retrieval, HTML, and screenshot verify all ST-072 lifecycle/state corrections while removing retry-help pollution. The help appears once visibly beneath the partial retry; unrelated chips and markup are clean. All 48 interactive elements meet the 48px minimum. |

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

Phase 07 used the authorized `REPLACE` operation to create ST-051/ST-052, then two explicitly
approved bounded `CORRECT` passes. Stitch returned derived ST-053/ST-054 and final ST-055/ST-056
rather than editing their selected sources in place. Both final sources were freshly retrievable;
their downloadable HTML and screenshots were inspected rather than accepting generation summaries.
The final artifacts contain no invented navigation, granular permission editor, unsupported role,
scheduling, shift, passcode, owner-transfer, or staff-delete concept. No source was deleted, hidden,
moved, grouped, or archived, and the design-system asset was not changed.

Phase 08 used the authorized `REPLACE` operation to create ST-057/ST-058. Fresh artifact inspection
rejected both early-stopping outputs. Device-specific `CORRECT` work produced ST-059 through ST-062;
ST-061/ST-062 are the strongest desktop/mobile working successors. Their later correction responses
contain concrete DOM operations for the missing printer, queue, responsive, and interaction states,
but individual retrieval continues to serve the pre-operation files. Fresh canonical-generation
attempts ST-063/ST-064 were downloaded and rejected because they stopped early. Phase 08 is closed
as `COMPLETED / RENDER REVIEW`; no screen is promoted to canonical candidate until ST-061/ST-062
canvas code and renders reflect the recorded operations. No source was deleted, hidden, moved,
grouped, or archived, and the design-system asset was not changed.

Phase 09 used the authorized `CREATE` operation to create ST-065/ST-066. Fresh artifact inspection
rejected both early-stopping outputs. Approved corrections produced ST-067 through ST-070; ST-070 is
freshly retrieved and visually reviewed as the complete mobile direction. User-copied canvas code
proved ST-067's DOM corrections had not persisted, so a fresh correction produced desktop ST-071.
ST-071 is substantially normalized but its final micro-correction again remained DOM-only. ST-072
baked those corrections into fresh HTML but polluted unrelated status chips with retry-help copy and
was rejected. A final authorized surgical cleanup produced ST-073; exact-ID retrieval and direct
HTML/screenshot inspection confirm the corrected desktop direction. Phase 09 is `COMPLETED / VISUAL
REVIEWED`; no source was deleted, hidden, moved, grouped, or archived, and the design-system asset
was not changed.
