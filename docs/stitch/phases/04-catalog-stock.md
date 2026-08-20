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
