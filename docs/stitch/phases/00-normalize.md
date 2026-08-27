> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 00 — Normalize the Stitch canvas

## Objective

Turn the existing 26-instance canvas into an auditable baseline without redesigning workflows.
Resolve identity, duplicates, source-screen retrieval gaps, and canonical candidates first.

## Evidence to open

- `SCREEN_INDEX.md` and the project instance list.
- Profound Verdant asset `assets/4c1cc58b4aed4b1693e6f8113ba1009a`.
- Local screenshot groups 10-37 for the domains already represented in Stitch.
- The six `REVIEW / RETRIEVAL ERROR` source IDs.

## Proposed operations (approval required)

- `REVIEW` every original/normalized/high-fidelity cluster.
- `KEEP` one working candidate per covered desktop/mobile workflow.
- `CORRECT` naming/branding only after content ownership is known.
- `ARCHIVE` duplicates only after a successor is approved; never delete history.
- If canvas grouping/repositioning is unavailable through the connected MCP toolset, document a
  manual Stitch UI task rather than simulating it with screen edits.

## Exclusions

- No new product behavior, no broad visual re-generation, no design-system application, and no
  product code changes.
- No guessed labels for the six unreadable screens.

## Acceptance criteria

- Every screen has one index row and a verified or explicitly unavailable title.
- Each duplicate cluster has a named candidate and rationale.
- Wrong brand strings are logged.
- No canvas object is removed before approval.
- The next phase can select source screens without relying on canvas-position inference.

## Execution result — 2026-08-20

Phase 00 is complete at the normalization-command level and stopped before Phase 01. Thirteen
existing screens were corrected in place, including all selected mobile views; thirteen were left
untouched. ST-010 is the canonical printer candidate. No screen or design-system object was created,
deleted, moved, grouped, renamed, hidden, archived, or varianted.

Fresh visual approval remains open. Stitch returned concrete DOM edit operations, but several
downloadable renders lagged behind those responses and individual screen retrieval remained
intermittent. See `../audits/phase-00.md` and the per-screen statuses in `../SCREEN_INDEX.md`.
