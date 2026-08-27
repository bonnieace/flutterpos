> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 05 — Reporting and reconciliation

## Objective

Design supported daily metrics, totals, profit completeness, reconciliation, anomalies, run action,
and shift amendments with exact read/write boundaries.

## Evidence to open

- Screenshot groups 25-30.
- `lib/reporting/` repositories and panels.
- Stitch ST-013, ST-019, ST-020, ST-022, ST-025.

## Required screens/states

- Daily summary and sales totals for owner/admin/manager.
- Profit/margin for owner/admin, including unavailable result when cost coverage is incomplete.
- Reconciliation matched/different/unusable-line states.
- Owner/admin-only reconciliation run and shift amendment actions.
- Manager-readable amendment/anomaly history where code allows it.
- Chart, graph, statistic, table, or combined representations selected according to the analytical
  question. A visualization may be new even when the current implementation is textual or tabular,
  provided every metric, dimension, comparison, and calculation is supported by active data.

## Exclusions

- CSV export; invented metrics, dimensions, data sources, calculations, comparison periods, or
  forecasts; manager profit access; or partial profit presented as complete. Charts themselves are
  not excluded: supported metrics should use visualizations where those materially improve
  comprehension.

## Acceptance criteria

- Every number has a defined source and scope.
- Every visualization is derived from evidenced records and answers a stated analytical question;
  it is not decorative.
- Write actions are absent for manager, not merely visually subdued.
- Difference and unusable-data states cannot be mistaken for success.
- Mobile preserves comparison context and action safety.
