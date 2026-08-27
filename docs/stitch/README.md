# Chilltent POS Stitch redesign control room

> **RETIRED for screens being reverted to the old single-tenant look and flow.** As of 2026-08-25
> the product direction changed: existing customers know the pre-multitenancy app
> (`lib/pos/**`, `lib/screens/**`, read-only reference only), and its screens, navigation, and
> visual character — not this redesign's IA — are now the target for those areas, rebuilt on the
> existing multitenant backend and token layer. See
> `C:\Users\BonifaceMasota\.claude\plans\look-at-the-old-expressive-sutton.md` for the current
> plan and which screens are affected (starting with Login, Home/Main Hub, Sales Report/Book
> Keeping). Do not treat the phase briefs below, or their IA/layout decisions in
> `OPEN_QUESTIONS.md`, as authoritative for those screens. **`RBAC_MATRIX.md` is unaffected** — role
> and permission behavior still derives from it regardless of which visual direction a screen
> follows. Areas not yet reverted still follow this directory until the pivot reaches them.

This directory is the operating contract for redesigning Chilltent POS in Stitch project
`7478406619239162026`. It separates product truth from visual exploration so that an attractive
mockup cannot silently add behavior, permissions, data, or settings that the app does not have.

## Running without a human in the loop

`AUTONOMOUS_HANDOVER.md` is the charter for an unsupervised run: what may be decided alone, what
must never happen, the order of work, the anti-overtesting contract, and the commit cadence.
Decisions taken that way are logged in `AUTONOMOUS_RUN_LOG.md`, which is what the product owner
reads afterwards.

**A phase being picked up gets a handover of its own**, written by the session that finished the one
before it: the designs it composes against, the defects to check rather than assume, the measured
baselines, and the traps that phase specifically has. `PHASE_03_HANDOVER.md` is done and is kept as
the model for the shape. **`PHASE_04_HANDOVER.md` is the live one** — read it before
`phases/04-catalog-stock.md`, because it says which of that brief's defects the app already
satisfies and which two gaps no other document names.

## Authority order

When sources disagree, use this order:

1. Active application and server code for behavior, data, permissions, offline rules, and routes.
2. The generated local corpus in `screenshots/` for the current rendered state.
3. Approved Stitch screens for intended layout and interaction presentation.
4. The files in this directory for coordination, naming, coverage, and decisions.
5. Explicitly labelled inference.

Root `DESIGN.md` describes the previous Flutter-led visual system. It remains useful implementation
history, but it is **not** visual authority for this redesign and must not constrain Stitch layout.
The reusable implementation seam remains valuable: approved semantic color, type, shape, spacing,
and motion tokens should later map through Flutter theme extensions rather than hardcoded widget
values. Existing `AppLayout.contract` values are not a Stitch constraint and may be replaced during
implementation after design approval.

**Reading item 3 without a Stitch connector.** Sessions that have no Stitch MCP server cannot fetch a
screen by ID. The project export under `stitch_chilltent_pos_redesign_system/` (gitignored) is the
local stand-in, and `EXPORT_MAP.md` joins every logical ID to its exported folder and records the
evidence that the export matches what Stitch served during the 2026-08-21 live audit. The export is a
design *input*, not an approval: a screen's status in `SCREEN_INDEX.md` and its pending work in
`LIVE_PHASE_HANDOFF.md` still govern. The export cannot be refreshed from a connector-less session, so
any screen change remains a Stitch mutation requiring explicit user authorization.

## Mandatory workflow

Every phase follows this sequence:

1. Read this file, `DESIGN_RULES.md`, `RBAC_MATRIX.md`, `SCREEN_INDEX.md`, `COVERAGE.md`, and the
   selected phase brief.
2. Recheck the relevant active code and local screenshot families. Screenshots are evidence, not a
   complete product specification.
3. Select exactly one operation: `REVIEW`, `KEEP`, `CORRECT`, `REPLACE`, `CREATE`, or `ARCHIVE`.
4. State the exact Stitch project, screen IDs, design-system asset, intended mutation, and exclusions.
5. Obtain the user's approval before any mutating Stitch call.
6. Make the smallest approved mutation; never batch the next phase into it.
7. Re-read every affected screen and compare it with code, RBAC, responsive behavior, and the phase
   acceptance criteria.
8. Update `SCREEN_INDEX.md`, `COVERAGE.md`, `OPEN_QUESTIONS.md`, and a dated file under `audits/`.
9. Stop. Stitch output is not permission to change Flutter code.

## Operation definitions

| Operation | Meaning |
|---|---|
| `REVIEW` | Inspect only. No Stitch or product mutation. |
| `KEEP` | Accept the existing screen as a useful canonical or reference screen. |
| `CORRECT` | Edit an existing screen while preserving its product purpose. |
| `REPLACE` | Create or designate a successor, then archive the superseded screen only after approval. |
| `CREATE` | Add a missing canonical screen or approved variant. |
| `ARCHIVE` | Remove a screen from the active canvas/index without deleting product history. |

## Baseline established 2026-08-20

- Repository branch: `design-step-5b-card-home`; clean before this documentation run.
- Reference corpus: 359 PNGs: 147 web, 129 mobile, 18 tablet, plus 65 full-height captures.
- Coverage shape: 37 numbered product workflow/state groups (`01`-`37`) and 10 component/system
  boards (`90`-`99`).
- Stitch canvas: 26 screen instances and one design-system asset.
- Design system: `assets/4c1cc58b4aed4b1693e6f8113ba1009a`, **Profound Verdant**, version 1.
- Retrieval: 20 source screens were readable; six source screens returned an invalid-argument error
  and remain evidence gaps. `list_screens` also returned invalid argument, so the project instance
  list is the complete inventory source for this audit.
- Mutations: none. No screen was generated, edited, renamed, moved, grouped, archived, or deleted.

That bullet records the pre-Phase-00 baseline. Phase 00 was subsequently authorized and executed on
2026-08-20: 13 existing screens were edited in place and 13 were untouched. No screen was created,
deleted, renamed, moved, grouped, hidden, archived, or varianted; the design-system asset was not
mutated. See `audits/phase-00.md`. Edited screens remain render-review items because Stitch's
downloadable artifacts lagged several completed DOM edit responses.

Phase 01 was authorized and executed on 2026-08-20 for authentication and tenant entry only. Four
working responsive state suites were created, plus one non-canonical intermediate desktop tenant-entry
variant that was superseded by a corrected source screen. The Profound Verdant asset was retained and
not mutated. See `audits/phase-01.md`. Some generated source screens are retrievable but are not yet
linked as project canvas instances; two corrected screens also retain stale downloadable artifacts and
remain visual-review items.

Phase 02 was authorized and executed on 2026-08-20 for role-aware home and navigation only. Existing
Manager desktop/mobile sources ST-012 and ST-023 were selected for correction; Stitch returned derived
successors ST-032 and ST-033 rather than overwriting those sources. The successors encode Owner/
Administrator, Manager, and Cashier route sets plus shift, device-evidence, and tenant-switch states.
The Profound Verdant asset was retained and not mutated. See `audits/phase-02.md`. Post-correction
retrieval remained stale/intermittent, so both successors remain render-review items.

Phase 03 was authorized and executed on 2026-08-20 for sale and checkout only. Existing desktop and
mobile sale sources ST-026, ST-009, and ST-011 were selected for correction; Stitch returned derived
successors. ST-035 is the visually reviewed desktop/tablet canonical candidate with a dense till,
state evidence, and labeled 834px two-region specimen. ST-036 is the mobile cart successor; the
mobile-browse successor also completed but current retrieval did not expose its exact ID. The mobile
outputs remain render-review items and were not regenerated. The Profound Verdant asset was retained
and not mutated. See `audits/phase-03.md`.

Phase 04 was authorized and executed on 2026-08-20 for catalog and stock only. Existing desktop and
mobile inventory sources ST-002/ST-007 were corrected into derived long-form route suites ST-039 and
ST-040. They separate Cashier read-only catalog, Manager operational work, Owner/Administrator
money/retire controls, pasted-text bulk preview/commit, recorded stock, reasoned adjustments,
movements, ledgers, responsive transformations, and failure states. Reorder/low-stock policy and
generic inventory navigation were removed. Final retrieval was stale/invalid, so both remain render-
review items. The Profound Verdant asset was retained and not mutated. See `audits/phase-04.md`.

Phase 05 was authorized and executed on 2026-08-20 for reporting and reconciliation only. Existing
desktop/mobile reporting and reconciliation sources ST-019/ST-020/ST-022/ST-025 were selected for one
correction operation; Stitch returned derived desktop/mobile suite screens ST-041/ST-042 rather than
overwriting those sources. ST-041 contains the evidenced reporting totals, profit refusal, tender
disclaimer, reconciliation states, run detail, and amendment provenance, but its shift-correction
action label still needs correction. ST-042 is non-canonical: its artifact is incomplete and contains
an unsupported comparison and date, and individual retrieval failed after the successful mutation.
A later approved mobile-only correction produced ST-043, a fresh 780x7794 successor that removes the
invented values and restores the principal mobile reporting/reconciliation sections. ST-043 remains
partial because several exact scope/provenance phrases were omitted; ST-042 is superseded. A final
approved copy-only edit completed in place for ST-041/ST-043. The mutation log confirms the missing
copy was applied, but ST-041 still serves its pre-edit artifact and ST-043 retrieval became invalid;
one anomaly value was also mislabelled as an expectation ID. Phase 05 is closed as `COMPLETED /
RENDER REVIEW`, not canonical approval. The Profound Verdant asset was retained and not mutated. See
`audits/phase-05.md`.

Phase 06 was authorized for a `CREATE` operation on sales, receipts, shift history, and returns. Its
initial and intermediate outputs required bounded corrections. The approved surgical pass corrected
mobile ST-048 in place and produced complete desktop successor ST-050; the final approved ST-050 edit
added the missing `Cash over` and `No closing summary` specimens and raised every Section 03-05
interactive target to at least 48px. Direct canvas-code copies later proved those first edits had not
persisted, so the user authorized exact-ID reapplication on both screens. Both reapplications returned
successful DOM operations; mobile retrieval remains cached and desktop retrieval is invalid. Phase 06
remains `COMPLETED / RENDER REVIEW`, pending fresh canvas-code inspection rather than another edit.
See `audits/phase-06.md`.

Phase 07 was authorized as a `REPLACE` operation for staff and access. Initial desktop/mobile
replacements ST-051/ST-052 were rejected after artifact review found invented navigation and omitted
lifecycle states. Two approved bounded corrections produced intermediate ST-053/ST-054 and final
desktop/mobile successors ST-055/ST-056. Fresh retrieval and HTML/screenshot inspection verified the
exact four roles, Owner/Administrator write versus Manager read-only composition, invitation and
status actions, all five consequence confirmations, validation/busy/failure/link states, labeled
mobile actions, and the 834px tablet transformation. Both final screens are `CANONICAL CANDIDATE /
VISUAL REVIEWED`. The Profound Verdant asset was retained and no Flutter or Firebase code changed.
See `audits/phase-07.md`.

Phase 08 was authorized as a `REPLACE` operation for supported settings and printing. Initial
desktop/mobile replacements ST-057/ST-058 were rejected after fresh artifact review showed that both
stopped early. Device-specific bounded corrections produced ST-059 through ST-062. ST-061/ST-062 are
the strongest working pair: their successful DOM-operation logs cover the supported ISO 4217 field,
direct-TCP printer outcomes, device-local queue recovery, responsive evidence, and interaction-state
ledgers without generic settings or receipt preview. Retrieval still serves their pre-operation
files, so that completion is mutation-reviewed rather than visually approved. Fresh fallback
generations ST-063/ST-064 were downloaded and rejected because they also stopped early. Phase 08 is
closed as `COMPLETED / RENDER REVIEW`, not canonical approval. The Profound Verdant asset was retained
and no Flutter or Firebase code changed. See `audits/phase-08.md`.

Phase 09 was authorized as a `CREATE` operation for the distinct platform superAdmin operations
area. Initial desktop/mobile sources ST-065/ST-066 stopped early and were rejected. Approved
corrections produced ST-067 through ST-070. Fresh ST-070 HTML and full-height screenshot inspection
verified the complete mobile authority, admission, lifecycle, archive, exact-UID global status,
consequence, state, and 48px interaction scope. Current canvas evidence proved ST-067's desktop DOM
corrections had not persisted; fresh desktop ST-071 then normalized the main scope but retained six
bounded copy/state defects. Its micro-edit also did not persist. The authorized last fresh variant
ST-072 fixed those defects but duplicated retry-help copy into unrelated status chips and was
rejected. A final authorized surgical cleanup produced ST-073. Fresh exact-ID HTML and screenshot
inspection verifies clean retry help, exact lifecycle/global-status truth, complete state evidence,
the tablet composition, and 48px controls. Phase 09 is `COMPLETED / VISUAL REVIEWED`; desktop ST-073
and mobile ST-070 are canonical candidates. The Profound Verdant asset was retained and no Flutter
or Firebase code changed. See `audits/phase-09.md`.

## Document map

- `LIVE_PHASE_HANDOFF.md` - live-fetched per-phase design debt, exact working lineage, and no-go notes
  for the next agent.
- `EXPORT_MAP.md` - the local Stitch project export: logical ID to export folder, freshness evidence,
  and the resolved Profound Verdant palette. **Read this before citing any screen**, because sessions
  without the Stitch connector cannot fetch a screen ID.
- `TOKEN_RECONCILIATION.md` - Profound Verdant mapped role by role onto `lib/ui/tokens.dart`, with the
  eleven gaps that block the theme repoint.
- `prompt.md` - hybrid sequential/concurrent development orchestration prompt for implementation
  agents.
- `DESIGN_RULES.md` - portable design guardrails and token policy.
- `REFERENCE_MAP.md` - current product domains, routes, screenshot evidence, and Stitch coverage.
- `RBAC_MATRIX.md` - permissions derived from active code.
- `SCREEN_INDEX.md` - exact Stitch inventory, evidence status, and recommendation.
- `COVERAGE.md` - supported, missing, conflicting, and inferred capability coverage.
- `OPEN_QUESTIONS.md` - decisions that must not be guessed.
- `phases/` - one bounded brief per redesign phase.
- `audits/` - dated evidence and post-mutation verification records.

## Non-negotiable boundaries

- Do not invent VAT, tax configuration, terminal telemetry, stock thresholds, granular permissions,
  scheduling, exports, or server behavior because a draft screen depicts them.
- Do not flatten owner, administrator, manager, and cashier into cosmetic variants. Navigation and
  actions are permission-driven.
- Preserve offline-first checkout, durable sale-before-print behavior, tenant isolation, shift
  semantics, and the distinction between configured and verified payment.
- Use semantic tokens. A screen-specific hex color or spacing constant is not a reusable theme.
- Maintain useful density for operational screens; management screens may be more spacious.
- Design desktop, tablet, mobile, loading, empty, error, disabled, read-only, and offline states when
  the workflow requires them.
