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
