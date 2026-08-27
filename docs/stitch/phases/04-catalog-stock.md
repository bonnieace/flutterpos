> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 04 — Catalog and stock

## Objective

Unify read-only catalog, management, bulk changes, stock correction, movement feed, and product
ledger without inventing inventory policy.

## Evidence to open

- Screenshot groups 17-24.
- `lib/inventory/` role lists and panels.
- Stitch inventory screen ST-002.

## Required screens/states

- Read-only catalog for all active roles.
- Management list and product/category create/edit.
- Owner/admin-only price/cost/retire actions versus manager operational edits.
- Bulk delimited-text preview, row errors, and commit result.
- Recorded stock, difference, reasoned correction, movement feed, and per-product ledger.
- Empty, stale/offline, loading, and error states.

## Exclusions

- Reorder points, automatic low-stock thresholds, supplier/purchase-order workflows, `.xlsx`, or
  cashier stock writes.

## Acceptance criteria

- Role-narrow fields/actions are structurally clear and cannot be mistaken for manager capability.
- Stock display does not imply sales are blocked by availability.
- Audit context (actor, time, reason, before/after) is readable.
- Tables transform to usable mobile records without losing action context.
