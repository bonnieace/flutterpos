> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 02 — Role-aware home and navigation

## Objective

Replace the generic manager dashboard with an honest operational home for owner, administrator,
manager, and cashier.

## Evidence to open

- Screenshot groups 10-12 and 99.
- Route composition in `TenantSafeLandingScreen` / `tenant_routing_shell.dart`.
- `RBAC_MATRIX.md`, especially staff, profit, reconciliation writes, settings, printer, and audit.
- Existing Stitch manager desktop/mobile screens ST-012, ST-016, ST-023.

## Required screens/states

- Owner/admin home with allowed management routes and shift/evidence status.
- Manager home with management reads but no restricted settings/audit/profit/write actions.
- Cashier home optimized for new sale, receipts waiting, catalog, receipt lookup, own shift, and
  tenant controls.
- Tenant-switch available/blocked/offline and print/check-out evidence states.

## Exclusions

- Active terminal counts, cloud/local-database health panels, reorder alerts, or any other invented
  telemetry.
- Disabled tiles for forbidden routes; unauthorized features should not be advertised.

## Acceptance criteria

- Every visible route is code-backed and role-correct.
- Mobile navigation is designed deliberately rather than cropped from desktop.
- Shift and local evidence have factual labels and recovery paths.
- Owners do not lose administrator permissions; managers do not gain them.

## Execution record — 2026-08-20

Executed as `CORRECT` in project `7478406619239162026` with Profound Verdant asset
`assets/4c1cc58b4aed4b1693e6f8113ba1009a` retained unchanged. ST-012 and ST-023 were selected for correction;
Stitch returned ST-032 and ST-033 as derived successors. See `../audits/phase-02.md` for exact route,
state, mutation, and stale-retrieval findings. Phase 03 was not started.
