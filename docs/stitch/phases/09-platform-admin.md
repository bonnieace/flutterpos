> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 09 — Platform administration

## Objective

Design the platform superAdmin workflows as a distinct operational area, based on the existing
admission, archive, and global-user behavior.

## Evidence to open

- Screenshot groups 09a-09d.
- Platform claim checks and platform screens under `lib/tenancy/`.
- Server callable/rule evidence for each action.

## Required screens/states

- Pending business admission and approve/reject outcome.
- Active/suspended/rejected tenant archive views.
- Global user lookup/status and guarded actions.
- Empty, loading, permission denied, invalid target, conflict, and remote failure states.

## Exclusions

- Tenant membership as platform authority, subscription/billing, portfolio reporting, guessed owner
  transfer, or bulk global actions not supported by code.

## Acceptance criteria

- Platform shell is visually and semantically distinct from tenant management.
- Every action names its server-backed consequence and confirmation boundary.
- Dedicated identities without tenant membership remain usable.
- No platform control appears on tenant role variants.
