# Live phase design handoff — 2026-08-21

Project: `7478406619239162026`

Status: `READ-ONLY LIVE AUDIT / NO NEW DESIGN PROMPTS`

This is the starting note for the next agent. It records what Stitch actually served on 2026-08-21,
not what a generation summary or DOM-operation response claimed it had changed. During this pass,
`get_project` returned 75 instances, `list_screens` returned 74 screens, and every working exact ID
below was fetched directly. Intermittent `invalid argument` reads were retried read-only. No screen or
design system was mutated during this all-phase audit.

## Fast disposition

| Phase | Design disposition | TL;DR for the next agent |
|---|---|---|
| 00 | Historical; no design work | Do not repair these legacy normalization sources. Later phases supersede them. |
| 01 | Not ready | Keep the completed majority. Fix only stale sign-in copy, the desktop tenant-entry overlap/target sizing, and bounded copy/linkage on the new mobile tenant-entry successor. |
| 02 | Not ready | Both served home/navigation artifacts still expose the pre-correction false shift route; mobile also retains false formatted-currency evidence and lacks the final checkout-evidence treatment. |
| 03 | Not ready | Desktop/tablet and mobile browse are sound, but the live mobile cart still has an invented save-error cause and a conflicting generic bottom bar. |
| 04 | Not ready | Desktop still collapses three audit routes and uses wrong labels/examples; mobile is materially truncated after the Cashier catalog specimen. |
| 05 | Not ready | Broad composition is complete, but the served files lack the final bounded action/scope/provenance copy. |
| 06 | Not ready | Mobile still serves mug/tax/refund contradictions; desktop still lacks two shift states and minimum target sizing. |
| 07 | Design-ready | No known design discrepancy. Freeze it and use it in the Phase 10 audit. |
| 08 | Not ready | Both served files are pre-correction: desktop stops after the base queue and mobile lacks the final endpoint, recovery, and failure-state completion. |
| 09 | Design-ready | No known design discrepancy. Resolve only canonical canvas lineage for the fetchable-but-unlisted desktop successor. |
| 10 | Not executed | Run the cross-system audit only after the phases above have an explicit canonical disposition. |

## Global rules for follow-up

- Do not send a broad regeneration prompt to a mostly complete phase.
- Treat the live HTML/screenshot as current truth. A successful mutation log is intent evidence until
  the changed artifact is freshly served.
- Preserve Profound Verdant asset `assets/4c1cc58b4aed4b1693e6f8113ba1009a`.
- Target one exact screen and one bounded defect only after the user authorizes a mutation.
- Do not touch Flutter, Firebase, schemas, rules, indexes, or deployment while resolving Stitch
  design debt.
- Do not “improve” copy, roles, routes, settings, examples, or calculations beyond code-backed facts.

## Phase 00 — baseline normalization

### Actual live disposition

Phase 00 is superseded evidence, not a canonical design family. Its stale-artifact and intermittent-
retrieval notes remain useful history, but Phases 01-09 now own the corresponding workflows.

### Pending for the next agent

Nothing should be redesigned here. In Phase 10, exclude Phase 00 screens from the canonical set where
a later-phase successor exists. Do not spend prompts refreshing old cleanup responses or manually
grouping the canvas unless the user separately asks for canvas housekeeping.

## Phase 01 — authentication and tenant entry

### Live lineage

- ST-027 desktop sign-in `4b5739a495cc411b9abce8dd46c54745`, served HTML
  `4c212d80cb8c4354aab5511b885c953c`.
- ST-028 mobile sign-in `cd38c0ed047248c9812a885250910d12`, served HTML
  `b310bf998736410bb1168c75ec40d1f7`.
- ST-031 desktop tenant entry `ba78e973493a4415be02b76fe9ee31a7`, served HTML
  `a4a3bc4312b74f0f8ded8497f1110488`.
- Old mobile tenant entry ST-029 `083b3bb1fb4046489f8db6d937fe4621` remains on the listed canvas.
- New mobile successor `f852fbf76f1d403295e87c500f0ba12b`, served HTML
  `deb62f1e64c14621b9e1c589f81bf057`, is directly fetchable but absent from both the project instance
  list and `list_screens`.

### What is actually pending

- ST-027 still serves `Retry Connection` and `Remember me on this terminal`; the prior exact-ID DOM
  response did not persist into the fetched artifact. The intended labels are `Sign in` and
  `Remember me`, with all targets at least 48px.
- ST-031 contains the required scope, but lower cards overlap. Invalid Invitation is nested inside No
  businesses and also repeated separately. Keep one standalone invalid-invitation card, restore
  normal-flow layout, and raise the remaining `h-10` actions to 48px.
- The new mobile successor is the complete eight-section direction and has no bottom navigation. Do
  not regenerate it. Its remaining work is bounded copy: undeliverable-email recovery, established
  invitation-safety copy, slug guidance including numbers/single hyphens, and review of short `Retry`
  versus `Retry connection`.
- ST-028 has no known defect. Do not edit it.

See `audits/2026-08-21-phase-01-live-handoff.md` for the exact no-go and copy instructions.

## Phase 02 — role-aware home and navigation

### Live lineage

- ST-032 desktop `34025255d4fe4100bc41dd079642a0e1`, served HTML
  `a8dd5301b29c4aae8c5959b9fc723a6c`.
- ST-033 mobile `66cb86bbe714430fb1103905935b1c75`, served HTML
  `d4e43a8dc0484c93b09dd0666c7b1aa7`.

### What is actually pending

Both artifacts still contain `Own shift panel` as a navigation destination even though Own shift is
home content, not a route. ST-033 also still says `KES 4,200.00 confirmed` instead of the supported
`Confirmed sales: 3 transactions, 420000 minor units`, and its served design does not show the final
separate five-state checkout-evidence readout. Apply only the already-documented route/copy/state
correction; do not redesign the role homes or add telemetry. Preserve View read-only catalog,
Receipts waiting, Change business, default-business behavior, Sign out, and role-specific access.

## Phase 03 — sale and checkout

### Live lineage

- ST-035 desktop/tablet `e85cc69d6db24026bc5eeff21a6f1b7f`, served HTML
  `858181ff2a5b474785c437dff9c8f589`.
- ST-036 mobile cart `0ece972d5e0f4deca20f8ed12686d618`, served HTML
  `82a57748b6c24ebf9c5f15b6eb3bc7d8`.
- The previously lost mobile browse source is now recovered as
  `78f9a1cdd0c74850ad97f7ed06eb2548`, served HTML `62d72eaf4a3f45dcbb80091aece1ac16`.

### What is actually pending

ST-035 remains the reviewed desktop/tablet candidate. The recovered mobile browse render is also
coherent: it exposes cached freshness, search/categories, prices, last-seen stock, a non-blocking
zero-stock warning, and one clear Open the cart action.

ST-036 has two real design defects that the earlier audit could not see:

- Its save refusal says `Could not save sale. Storage full or write error.`, which invents a cause.
  Use the established generic refusal: `This sale could not be saved on this device. Try again, and
  ask for help if it keeps happening.`
- It renders a generic `Sale / Orders / History / Sync` bottom bar, conflicting with the approved
  role-aware mobile navigation and staged browse/cart flow. Remove that bar without changing the
  cart, tender assertion, KES 135.00 total, durable receipt, later confirmation, or independent print
  failure states.

## Phase 04 — catalog and stock

### Live lineage

- ST-039 desktop `1273644f84ce4978a64bcff21fee7728`, served HTML
  `74dce2e67c8e49b09f1ec9211967d4af`.
- ST-040 mobile `04e000e868734d41a53b30acbc810703`, served HTML
  `8fe32c3db67f46dba6cfbd823ac0dda3`.

### What is actually pending

- ST-039 still combines Stock adjustments, Movements, and Ledger into one table; uses
  `Before/After`; and lacks the required exact provenance. Split these into three route specimens,
  use `Before and after`, show the evidenced `+24` manual adjustment and `-2` sale with source
  `co-1`, and remove the supplier-oriented reason placeholder.
- ST-040 is not merely awaiting visual confirmation. Its served 9 KB HTML stops after
  `1. Cashier — Product catalog` and ends with the generator comment asking to add more specimens.
  It is missing the Manager/Owner write structures, bulk preview/error/commit, stock adjustment,
  movement feed, ledger, failure states, and the rest of the mobile route family. A complete mobile
  successor is required, but reuse ST-039's accepted structures and the Phase 04 brief; do not add
  reorder levels, low-stock purchasing, supplier workflows, or generic navigation.

## Phase 05 — reporting and reconciliation

### Live lineage

- ST-041 desktop `80bcf18734c44f5dad68f49caf544058`, served HTML
  `3dbc27b977fe43d3b139732e6a43a031`.
- ST-043 mobile `e54d5ed714c44b9caa93b580c9c01eff`, served HTML
  `d3ea23b0926248b1abebdea687ce52f2`.

### What is actually pending

The reporting, profit-refusal, reconciliation, difference-kind, run, and amendment composition is
already large and should be preserved. The served desktop still uses `Apply Correction` rather than
`Correct this shift's totals`. The served mobile contains that action label and retains `Expected:`,
but still lacks the final explicit Last 7/30/90 periods, named-colleague scope, oldest-first
processing, requester `system:sale_trigger`, unchanged counted cash, server-derived replacement
totals, feed ordering, and manager/evidence identifiers.

This is bounded copy/provenance debt. Do not regenerate the suites. If applying the recorded final DOM
intent, preserve the live `Expected:` label; a prior mutation response accidentally proposed
`Expectation ID: 12`, which is wrong.

## Phase 06 — sales history, receipts, shifts, and returns

### Live lineage

- ST-048 mobile `f2b25ce06fd4404fb08f993f64aeaf17`, served HTML
  `403501e3a12f475499b0b7ba8a1a099e`.
- ST-050 desktop `9f9d275f6ac8463c9dac306d17fbc784`, served HTML
  `0975a3a6a9aa4c05adbd97c44723fa7c`.

### What is actually pending

- ST-048 still serves `Ceramic Mug - Green`, `Tax (16%)`, and
  `Amount to refund: KES 850.00`. Replace only those contradicted facts with the evidenced White bread
  loaf/Mandazi, KES 150.00, Brian Kimani, pending stale-loaf reason, and explicit no-stock-restored
  truth already recorded in the Phase 06 audit.
- ST-050 contains the main Sections 03-05, but still lacks the `Cash over` specimen and desktop
  `No closing summary` specimen. Its filters/actions/pagination and both consequence-dialog action
  groups still need at least 48px targets.

Do not add refund integration, payment reversal, taxes, exports, or editable historical facts.

## Phase 07 — staff and access

### Live lineage

- ST-055 desktop/tablet `740c94b5b6444359b796a16f32347e17`, served HTML
  `ab6ff5444fde4209a60bc247ed3569da`.
- ST-056 mobile `ed557d273cea4784a5c7a7cac47691a9`, served HTML
  `808a392d7bca4840806ec3c826124776`.

### What is actually pending

No design correction is known. The fresh files match the visually reviewed canonical-candidate pair.
Freeze both screens. The next work is Phase 10 lineage/conflict verification only; do not send a
“polish” prompt or add role-management features.

## Phase 08 — supported settings and printing

### Live lineage

- ST-061 desktop `1701f2f2ad1546cd977e3d2cfd25cc16`, served HTML
  `b7870f64505147cbbe83796140ebecab`.
- ST-062 mobile `9fb29b6ac7ba48489b9a5fb575a48f5f`, served HTML
  `74ac285281d54f449a6e25d113d5859d`.

### What is actually pending

- ST-061 still stops after the base Receipts waiting queue. It does not serve the recorded printer
  outcome matrix, queue recovery matrix, 834px tablet specimen, interaction ledger, or explicit 48px
  ledger treatment.
- ST-062 contains the broad currency/printer/queue suite and an interaction-ledger heading, but the
  served design still lacks endpoint-change consequences, supported printer write outcomes, explicit
  read-only and retry-failure queue states, and the final endpoint/disabled-loading semantics.

The successful DOM logs describe the intended bounded completion, but current artifacts do not prove
it. Do not use the rejected short fallback screens ST-063/ST-064 and do not add unsupported tax,
branding, payment, transport-selection, preview, or queue-mutation settings.

## Phase 09 — platform operations

### Live lineage

- ST-070 mobile `79c011b38c4c4bfea3f0db1a2145c366`, served HTML
  `60235cba1c74416a9291fc858ae8716a`.
- ST-073 desktop `3c3f120ed8fe4f5c88946b5e9a54d814`, served HTML
  `bb5e38d211e2496a9d42e76f712d34ba`.

### What is actually pending

No design correction is known; both are the visually reviewed canonical candidates. ST-073 is
directly retrievable by exact ID but is absent from `get_project.screenInstances` and `list_screens`.
Resolve or explicitly document that canonical-linkage condition in Phase 10. Do not regenerate the
desktop suite and do not add tenant membership as platform authority, ownership transfer, bulk
operations, or permanent deletion claims.

## Phase 10 — cross-system audit

### What is pending

Phase 10 has not run. It must select one explained lineage per workflow, exclude superseded/rejected
screens, verify there is no unresolved product/RBAC/responsive conflict, record any fetchable-but-
unlisted canonical source, and produce a dated audit with explicit approval status. It is an audit,
not permission to generate features or silently fix earlier phases.

Do not mark Step 10 complete while Phases 01, 02, 03, 04, 05, 06, and 08 still have the served design
gaps above. Phase 00 needs no new design; Phases 07 and 09 are design-ready.
