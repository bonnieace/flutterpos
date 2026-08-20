# Phase 01 authentication and tenant-entry audit — 2026-08-20

Project: `7478406619239162026`

Operation: `CREATE`, with in-place truthfulness corrections where Stitch supported them
Design-system asset: `assets/4c1cc58b4aed4b1693e6f8113ba1009a` (retained, not mutated)

## Result

Phase 01 created responsive state-suite coverage for signed-out authentication and signed-in tenant
entry. It did not change Flutter/Firebase code, the design system, or any later-phase screen. It did
not delete, move, group, hide, or archive existing Stitch history.

Working set:

- ST-027 `4b5739a495cc411b9abce8dd46c54745` — desktop sign-in states.
- ST-028 `cd38c0ed047248c9812a885250910d12` — mobile sign-in states.
- ST-029 `083b3bb1fb4046489f8db6d937fe4621` — mobile tenant-entry states.
- ST-031 `ba78e973493a4415be02b76fe9ee31a7` — corrected desktop tenant-entry states.

ST-030 `fa22fc86bb614d3fabd724ec5f376681` is a non-canonical intermediate desktop variant. Its first
layout pass invented verification-code entry, a request reason, an invitation decline action, and
altered empty/failure copy. The subsequent correction response produced ST-031, which is the only
desktop tenant-entry candidate.

## Evidence and supported behavior

The mutation prompts were checked against `lib/main.dart`, `lib/tenancy/sign_in.dart`,
`account_verification.dart`, `tenant_bootstrap.dart`, `tenant_request.dart`,
`tenant_visible_invitation_acceptance.dart`, `invitation_acceptance_failure.dart`, and
`tenant_routing_shell.dart`, plus local screenshot groups 01–08 on web and mobile. Group 09 was used
only to confirm the routing boundary; platform operational UI stayed excluded.

The working set covers:

- Sign-in default, refused credentials, unreachable service, caps-lock, and busy states.
- Email verification send/resend, undeliverable, and recheck behavior without code entry.
- Accessible and pending business membership rows, request business review/confirmation, and the
  no-business state.
- Valid invitation acceptance, invalid/incomplete invitation continuation, and account-open failure.
- The explicit routing boundary: tenant users continue through membership routing; only root
  `platform_admin` plus the separate `platformRole=superAdmin` claim reaches platform operations.

No password reset, account creation, social sign-in, SSO, subscription, automatic tenant
provisioning, platform role picker, or platform operational screen was added.

## Post-mutation verification

- ST-028 rendered as a truthful single-column mobile sign-in suite and was visually compared with the
  local mobile sign-in evidence.
- ST-031's fresh mutation render showed the corrected out-of-band verification, two-field business
  request, exact invitation actions, connectivity failure, and conjunctive platform-routing note.
- ST-027 initially rendered `Retry connection` and expanded Remember-me copy. A completed DOM edit
  changed these to exact `Sign in` and `Remember me`; its downloadable screenshot remained the older
  artifact, so it is `RENDER REVIEW`, not approved.
- ST-029 initially rendered an invented Entry/Pending/Account bottom navigation. A completed DOM edit
  removed it and exposed a labelled Sign out action. Its downloadable screenshot remained older, so
  it is `RENDER REVIEW`, not approved.
- Individual retrieval recovered for ST-027, ST-028, and ST-029. ST-030 and ST-031 later alternated to
  invalid-argument responses after successful generation/edit output. Per the operating contract,
  neither was regenerated.
- `get_project.screenInstances` lists ST-027 but not ST-028 through ST-031. Their exact source IDs and
  artifacts came from successful mutation responses, so they require canvas-link review rather than
  duplicate generation. `list_screens` still returns invalid argument.

## Acceptance summary

- Product behavior and exclusions: passed for the working set after corrections.
- Product identity and Profound Verdant direction: passed.
- Tenant/platform separation: passed in ST-031; platform operations remain excluded.
- Desktop/mobile state coverage: represented, with the retrieval and canvas-link limitations above.
- Accessibility intent: visible labels, text-backed status, focus treatment, and 48 px targets are
  present in the reviewed renders/prompts; device-level focus and scrolling remain later validation.
- Final status: `NORMALIZED / REVIEW`; no Phase 01 screen is promoted to approved while stale artifacts
  or canvas linkage remain unresolved.

## Recommended next phase

Proceed to Phase 02, role-aware home and navigation, after a short Stitch UI check that ST-028 through
ST-031 are linked on the canvas and that the corrected ST-027/ST-029 renders have refreshed. Do not
fold platform administration into Phase 02.
