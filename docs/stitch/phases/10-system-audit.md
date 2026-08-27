> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 10 — Cross-system audit

## Objective

Audit the complete approved Stitch system before any Flutter implementation handoff.

## Evidence to open

- Every canonical screen and approved responsive/state variant.
- All control documents in `docs/stitch/`.
- Screenshot groups 01-37 and component/system boards 90-99.
- Active route composition, role lists, offline state, and printing contracts.

## Required checks

- Product capability and content truth.
- Exact role/action visibility for owner, administrator, manager, cashier, and platform superAdmin.
- Desktop/tablet/mobile continuity and usable long-content behavior.
- Loading, empty, error, offline, read-only, disabled, busy, and partial-success states.
- Semantic design tokens, component reuse, accessible targets/focus/contrast, and consistent naming.
- No duplicate canonical screens, orphaned variants, wrong-brand strings, or unsupported controls.

## Exclusions

- No opportunistic feature additions, Flutter implementation, or destructive Stitch cleanup during
  the audit itself.

## Acceptance criteria

- `SCREEN_INDEX.md` identifies one canonical lineage for every covered workflow.
- `COVERAGE.md` has no unexplained `CONFLICT`; remaining `MISSING` items are explicitly deferred.
- `OPEN_QUESTIONS.md` contains no blocker for implementation handoff.
- A dated audit records pass/fail evidence and exact follow-up operations.
- The user explicitly approves moving from design to implementation.
