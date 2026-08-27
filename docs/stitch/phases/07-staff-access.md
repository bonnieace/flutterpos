> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 07 — Staff and access

## Objective

Replace the invented permission editor with the exact role-based directory and invitation lifecycle.

## Evidence to open

- Screenshot groups 13, 13b, 13c.
- `TenantRole`, staff directory/callables, and route guards in `lib/tenancy/`.
- Stitch staff screen ST-014 and `RBAC_MATRIX.md`.

## Required screens/states

- Administrator/owner directory with invite, edit, status, email replacement, resend, and cancel
  actions where applicable.
- Manager read-only directory.
- Pending, active, disabled, expired/invalid, busy, validation, and failure states.
- Exact Owner, Administrator, Manager, Cashier role presentation.

## Exclusions

- Granular permission toggles, Senior Cashier, Inventory Clerk, scheduling, last-shift management,
  or owner transfer unless active code explicitly supports the action.

## Acceptance criteria

- No visual control implies a permission model the backend lacks.
- Destructive/status actions identify the affected person and consequence.
- Manager composition contains no write affordance.
- Responsive edit forms do not overflow and retain accessible labels/errors.
