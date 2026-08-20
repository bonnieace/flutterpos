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
