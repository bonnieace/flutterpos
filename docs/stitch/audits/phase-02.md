> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 02 role-aware home and navigation audit — 2026-08-20

Project: `7478406619239162026`

Operation: `CORRECT` selected existing home screens; Stitch returned derived successors
Design-system asset: `assets/4c1cc58b4aed4b1693e6f8113ba1009a` (retained, not mutated)

## Result

Phase 02 selected existing Manager home sources ST-012 and ST-023 for correction. Stitch returned two
derived working screens instead of overwriting those sources:

- ST-032 `34025255d4fe4100bc41dd079642a0e1` — desktop role-aware home/navigation suite.
- ST-033 `66cb86bbe714430fb1103905935b1c75` — mobile role-aware home/navigation suite.

ST-012 and ST-023 remain superseded history. No Flutter/Firebase code, design-system asset, later-
phase screen, or unrelated Stitch source was changed. No screen was deleted, moved, grouped, hidden,
or archived.

## Evidence and route contract

The mutation was checked against `TenantSafeLandingScreen` and `TenantBusinessSwitcher` in
`lib/tenancy/tenant_routing_shell.dart`, `TenantShiftPanel` and its controller, the route wiring in
`lib/main.dart`, active allowed-role lists, RBAC, and local screenshot groups 10–12 and 99.

Common visible routes for every active role are New sale, Receipts waiting, View read-only catalog,
Find a receipt, eligible Change business, Make default or the disabled Default business state, and
Sign out. Own shift is content on the home and is not a route tile.

Role additions:

- Owner/Administrator: Manage catalog, View daily summary, Checkout settings, Printer, View activity
  log, and View staff directory.
- Manager: Manage catalog, View daily summary, and View staff directory as a read-only destination.
- Cashier: no management, settings, printer, staff, audit, profit, reconciliation, or stock-management
  destination.

The suites also cover no shift, shift open, unfinished cash count, offline/unconfirmed shift,
device-local checkout evidence, receipts waiting as a separate print fact, and tenant switching when
available, blocked by cash close, or unavailable offline.

## Conflicts removed

- Active-terminal, cloud, local-database, order-total, low-stock, recent-activity, and generic sync
  telemetry.
- Generic bottom navigation and desktop-sidebar behavior on mobile.
- Disabled tiles advertising forbidden routes.
- Settings, printer, audit, profit, or write capabilities on Manager/Cashier specimens.
- A false `Own shift panel` navigation destination.
- Formatted-currency shift evidence where the active shift panel reports confirmed transactions and
  minor units.
- Conflation of confirmed checkout evidence with receipt-print status.

## Post-mutation verification

The first successor renders were downloaded and visually compared with active screenshots and route
composition. They established the intended desktop density and mobile task-hub layout but exposed four
truth gaps: missing common catalog/default routes, false shift destinations, ambiguous print-queue
copy, and formatted shift currency. A second, smallest correction returned concrete DOM operations:

- ST-032 replaced the Owner/Admin, Manager, and Cashier route lists; removed false shift destinations;
  restored View read-only catalog, Change business, and Make default; applied exact receipt status;
  and added a separate read-only checkout-evidence strip.
- ST-033 removed the false shift card from navigation; changed the shift line to `Confirmed sales: 3
  transactions, 420000 minor units`; added Make default and Sign out; and added the separate five-state
  checkout-evidence readout with automatic-submission copy.

After that successful correction, ST-033 individual retrieval served the earlier screenshot/HTML and
ST-032 returned invalid argument. Project retrieval also returned invalid argument. Per the operating
contract, neither screen was regenerated or repeatedly edited. Both remain `RENDER REVIEW` and need a
fresh Stitch canvas check. The mutation responses provide exact source IDs and DOM-operation evidence.

## Acceptance summary

- Code-backed, role-correct routes: passed in the final correction instructions/DOM operations.
- Owner inheritance and Manager/Cashier restrictions: passed.
- Deliberate mobile navigation: passed; shift-first task hub, no generic bottom bar.
- Factual shift, checkout, print, and tenant-switch semantics: passed after correction.
- Visual system: Profound Verdant retained; no design-system mutation.
- Final status: `NORMALIZED / REVIEW`; stale/intermittent retrieval prevents approval.

## Recommended next phase

Proceed to Phase 03, sale and checkout, after one Stitch UI review confirms the final ST-032/ST-033
renders and canvas linkage. Do not fold catalog, reporting, or platform-administration work into that
phase.
