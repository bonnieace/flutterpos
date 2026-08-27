> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 00 normalization audit — 2026-08-20

Project: `7478406619239162026`

Operation: `CORRECT` existing screens only
Design-system asset: `assets/4c1cc58b4aed4b1693e6f8113ba1009a` (retained, not mutated)

## Result

Phase 00 corrected 13 existing source screen IDs and did not create, delete, move, group, rename,
hide, archive, or variant any screen. It did not change Flutter/Firebase product code.

Edited screens:

- Desktop: ST-001 new sale, ST-002 inventory, ST-010 printer, ST-012 Manager home, ST-014 staff,
  ST-022 reconciliation, ST-024 checkout settings, and ST-025 analytics.
- Mobile: ST-009 sale review, ST-011 product browse, ST-019 reconciliation, ST-020 analytics, and
  ST-023 Manager home.

Untouched screens: ST-003, ST-004, ST-005, ST-006, ST-007, ST-008, ST-013, ST-015, ST-016,
ST-017, ST-018, ST-021, and ST-026.

## Canonical selections

- Printer configuration: ST-010 (`32cff1e0ae4f43ddad97b77b55e9be5c`). It now models one configured
  device with address, port, 32/48-column paper width, cutter, save, test, sale-before-print, and
  device-local waiting-receipt semantics. ST-004 and ST-017 remain untouched non-canonical refs.
- New sale: ST-001 desktop, ST-011 mobile browse, and ST-009 mobile review are the working set.
- Manager home: ST-012 desktop and ST-023 mobile are the working pair.
- Reconciliation: ST-022 desktop and ST-019 mobile are the working pair.
- Analytics: ST-025 desktop and ST-020 mobile are the working pair.

## Conflicts removed by the edit instructions

- Kijani/wrong product identity and generic Operational Hub language on corrected compositions.
- VAT/tax rows, payment-verification claims, checkout draft/discount actions.
- Terminal/cloud/local-database telemetry and threshold-based reorder/low-stock behavior.
- Invented roles, granular permissions, staff scheduling, and last-shift controls.
- Broad unsupported settings, export actions, and chart content whose underlying metrics or
  calculations were not verified during Phase 00. This was not a prohibition on visualizations of
  supported data in later design phases.
- Manager reconciliation write actions; cash inputs were disabled in the mobile composition.
- Mobile navigation alternatives were replaced with New sale, Receipts waiting, Catalog, and Find
  receipt where the persistent shell is used. ST-011 remains a deliberate focused browse screen.

## Verification and remaining conflicts

Every edited ID was reread after mutation or included in the final read-only retrieval batch. Mobile
screens were included explicitly. Stitch retrieval remained intermittent, and multiple downloadable
HTML/screenshot artifacts continued to show their pre-edit render even when the mutation response
reported concrete DOM operations. Therefore no edited screen is marked `APPROVED`.

Remaining review items:

- ST-002, ST-012, and ST-025 were submitted for a final Manager-navigation cleanup, but the response
  channel became stale while Stitch processed it. The call was not retried; verify its result in the
  Stitch UI.
- ST-014's first normalization completed, but a later active-route-only cleanup returned service
  unavailable and was not retried.
- ST-024 and several other IDs still fail individual retrieval intermittently.
- ST-003, ST-013, ST-016, ST-026, and the non-canonical printer siblings intentionally retain old
  conflicts as untouched historical references.
- Canvas grouping/reorganization is unsupported by the connected 15-tool MCP surface and remains a
  manual Stitch UI task if desired.

## Status changes

The new-sale, Manager-home, staff, catalog, reporting, reconciliation, settings, and printer areas
move from conflict/stitched to `NORMALIZED / REVIEW` or `PARTIAL`. Missing workflows stay missing.
No status advances to approved until a fresh visual render is compared with RBAC, mobile behavior,
and active code.

## Recommended Phase 01 scope

Phase 01 should cover tenant identity and entry groups 01–08 only: desktop/mobile sign-in, sign-in
failures, email verification, choose/request/no-business states, and invitation acceptance/failure.
Keep platform superAdmin work for its dedicated later phase. Phase 01 has not started.
