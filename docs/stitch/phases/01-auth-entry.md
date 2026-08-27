> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 01 — Authentication and tenant entry

## Objective

Design the complete path from signed-out state to a valid tenant or platform destination.

## Evidence to open

- Screenshot groups 01-09: sign-in states, choose business, email verification, business request,
  no businesses, invitation acceptance/invalidity, account refusal, and platform entry states.
- Active authentication and tenancy composition in `lib/main.dart` and `lib/tenancy/`.
- Platform superAdmin separation in `RBAC_MATRIX.md`.

## Required screens/states

- Sign in: default, caps-lock, refused credentials, unreachable service, busy.
- Verify email and resend/retry states.
- Choose/default business, no business, request business.
- Accept valid invite, invalid/expired invite, cannot open account.
- Explicit routing split between tenant membership and platform superAdmin.

## Exclusions

- No password-reset invention beyond current supported behavior.
- No social sign-in, subscriptions, self-created tenant schema, or implied automatic platform access.

## Acceptance criteria

- Each state has a single clear recovery action.
- Responsive mobile and desktop compositions preserve form labels, errors, focus, and 48 px targets.
- Tenant roles and platform claim are never conflated.
- Copy does not promise unavailable recovery or provisioning behavior.

## Execution record — 2026-08-20

Executed as `CREATE` in project `7478406619239162026` with Profound Verdant asset
`assets/4c1cc58b4aed4b1693e6f8113ba1009a` retained unchanged. The working set is ST-027 through ST-029 and
ST-031. ST-030 is a superseded intermediate variant. See `../audits/phase-01.md` for exact mutation,
verification, stale-retrieval, and canvas-link findings. Phase 02 was not started.

## Live follow-up — 2026-08-21

Read-only retrieval found persisted/stale-content discrepancies, and a bounded mobile correction
produced successor `f852fbf76f1d403295e87c500f0ba12b`. Phase 01 is frozen at `PARTIAL / HOLD FOR
REVIEW`; do not broadly regenerate it. See `../audits/2026-08-21-phase-01-live-handoff.md` for the
exact lineage, remaining bounded copy/layout issues, and no-go instructions for the next agent.
