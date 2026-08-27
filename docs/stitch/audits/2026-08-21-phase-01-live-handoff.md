> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 01 live verification and handoff — 2026-08-21

Project: `7478406619239162026`

Status: `PARTIAL / HOLD FOR REVIEW`

This note supersedes any assumption that Phase 01 only needs a generic visual check. It records the
current exact-screen evidence and gives the next agent enough context to review or make a surgical
correction without regenerating the larger completed suite.

## Freeze decision

- Do not issue another broad Phase 01 generation, replacement, or multi-screen correction.
- Do not change the Profound Verdant design system.
- Do not edit ST-028; it remains the visually reviewed mobile sign-in candidate.
- Do not retry the rejected ST-031 in-place edit automatically.
- Prefer read-only canvas/source inspection. If a later edit is authorized, target only the exact
  defect and preserve every unaffected section.

## Current working lineage

| Purpose | Exact screen ID | Current finding | Disposition |
|---|---|---|---|
| Desktop sign-in states | `4b5739a495cc411b9abce8dd46c54745` (ST-027) | An in-place correction returned DOM event `1d6519c6`, but `get_screen` still serves HTML file `4c212d80cb8c4354aab5511b885c953c`, which contains the old copy. | Keep; verify canvas source before any further edit. |
| Mobile sign-in states | `cd38c0ed047248c9812a885250910d12` (ST-028) | Existing five-state mobile suite remains visually reviewed. | Keep; no edit. |
| Old mobile tenant entry | `083b3bb1fb4046489f8db6d937fe4621` (ST-029) | Served source contains only Choose business plus the forbidden Entry/Pending/Account bottom navigation. | Superseded by the new successor; retain as history. |
| New mobile tenant-entry successor | `f852fbf76f1d403295e87c500f0ba12b` | Fresh retrievable HTML `deb62f1e64c14621b9e1c589f81bf057` and screenshot `10041fb810934063b1dcf5157dfe38e6`; 780x7126. All eight required sections are present and bottom navigation is absent. | Strong candidate; bounded copy review remains. |
| Desktop tenant-entry suite | `ba78e973493a4415be02b76fe9ee31a7` (ST-031) | Product scope is present, but the lower specimens overlap and an Invalid Invitation block is incorrectly nested inside No businesses as well as repeated separately. A surgical edit was rejected with `invalid argument` before mutation. | Keep; needs one later exact, layout-only correction if authorized. |

## ST-027 exact pending correction

The successful mutation response claimed these operations, but the served artifact has not changed:

- Replace unreachable-state `Retry Connection` with `Sign in`.
- Replace default `Remember me on this terminal` with `Remember me`.
- Preserve all five sign-in states.
- Keep all interactive targets at least 48 CSS pixels.

Do not add password reset, registration, social sign-in, SSO, subscription, tenant provisioning, or
new navigation.

## New mobile successor verification

The new mobile successor contains:

- Choose business with the three evidenced memberships and in-content Request business / Sign out.
- Out-of-band Verify email states with no verification-code input.
- The two-field Business name / Business slug request form and pending-review statement.
- No-business, valid invitation, invalid invitation, account-open failure, and routing split sections.
- The exact `platform_admin` plus `platformRole=superAdmin` routing boundary.
- Sixteen buttons and two inputs using `h-12`, plus business rows using `h-16`; no persistent bottom
  navigation or fixed-width child wider than the intended mobile container was found.

Do not broadly regenerate this screen. If a later copy-only correction is authorized, preserve the
whole composition and address only these bounded differences:

1. Replace `Undeliverable/Invalid email address. Please contact support.` with the evidenced recovery
   direction `Undeliverable: Check your email address.`
2. Restore the established invitation safety copy: `Continue only if you expected this invitation.
   The link can be used only by the invited account.`
3. Restore the evidenced slug guidance: `Lower-case letters, numbers, and single hyphens.`
4. Review whether the account-open action should use the established short label `Retry` rather than
   `Retry connection`; do not change the underlying recovery behavior.

These are bounded content differences, not grounds for another full-screen prompt.

## ST-031 exact pending correction

If the user later authorizes an edit, it must be layout-only plus target sizing:

- Remove the Invalid Invitation block nested inside No businesses.
- Keep one standalone Invalid/Incomplete Invitation card.
- Put Request business, No businesses, Invalid invitation, and Account-open failure in normal-flow
  grid cards with no overlap, clipping, absolute placement, or negative offsets.
- Raise all `h-10` invitation/recovery actions to at least 48 CSS pixels.
- Preserve all current product facts, fields, roles, invitation behavior, verification behavior, and
  the exact tenant/platform routing statement.

Do not regenerate the entire desktop suite merely to repair these defects.

## Phase 01 handoff gate

Phase 01 is ready for canonical promotion only after read-only evidence confirms:

1. ST-027 serves the two corrected labels and 48px targets.
2. The new mobile successor passes the bounded copy review above.
3. ST-031 has one non-overlapping instance of every required state and 48px controls.
4. ST-028 remains unchanged.

No Flutter, Firebase, schema, rules, deployment, or design-system change belongs in this work.
