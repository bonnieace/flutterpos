# Phase 07 audit — staff and access

Date: 2026-08-21

Project: `7478406619239162026`

Operation: authorized `REPLACE`, followed by two explicitly approved bounded `CORRECT` passes

Design system: Profound Verdant `assets/4c1cc58b4aed4b1693e6f8113ba1009a`, retained and not mutated

## Scope and product evidence

Phase 07 used screenshot groups 13, 13b, and 13c; the active `TenantRole` contract; the staff
directory repository and route guard; and the invite, update, status, resend, cancellation, and
email-replacement callables in `lib/tenancy/`.

The exact role model is Owner, Administrator, Manager, and Cashier. Owner satisfies Administrator
authorization. Owner/Administrator may write; Manager may read the directory with no write
affordance; Cashier has no directory route. The work excluded granular permissions, custom roles,
Senior Cashier, Inventory/Stock Clerk, scheduling, shift/last-shift management, passcodes, owner
transfer, and staff deletion.

## Initial replacement

The authorized replacement produced:

- ST-051 `2070e8e96c1b4110bdfc462366b584ca` — desktop/tablet, 3072x2048.
- ST-052 `deaba05c2c18441388e1aa2a215669f9` — mobile, 780x1768.

Neither artifact met acceptance. Desktop stopped after the populated directory and invented Access
Management, Roles, Invites, Logs, and unrelated navigation. Mobile showed only Grace and Peter,
abbreviated Administrator as `Admin`, and invented Roles/Invites/Settings navigation. The promised
Manager/forms/confirmations/state coverage was absent from the actual HTML.

## First approved correction

A bounded correction selecting exact ST-051/ST-052 returned derived successors:

- ST-053 `411f3325f8b542248143afde789524e8` — desktop, 2560x10172.
- ST-054 `efdd3245c2954c14a3c80d63cc6e02d1` — mobile, 780x3150.

ST-053 contained the five-person directory, Manager read-only composition, forms, all five
confirmations, page/link states, and tablet frame. Artifact inspection found bounded defects: `Save`
instead of `Save changes`, missing cancellation help, altered empty/link recovery, and no Manager
tablet specimen. ST-054 still ended after Section 02 and used icon-only row actions.

## Final approved correction

The final correction selecting exact ST-053/ST-054 returned:

- ST-055 `740c94b5b6444359b796a16f32347e17` — desktop, 2560x10764.
- ST-056 `ed557d273cea4784a5c7a7cac47691a9` — mobile, 780x12822.

Both final sources were retrieved successfully. The returned file identifiers differed from their
predecessors, and downloadable HTML plus full-height screenshots were inspected.

## Verification result

- Both artifacts contain Grace Wanjiru, Peter Otieno, Amina Hassan, Brian Kimani, and Faith Njeri
  with the exact four roles and supported membership/invitation facts.
- Owner/Administrator actions match active gateways: invite, correct, activate/deactivate accepted
  non-owner members, and correct/resend/cancel/replace-email for pending invitations.
- Desktop, mobile, and tablet Manager compositions contain zero buttons and zero form controls.
- Invite and correction forms preserve labels, valid role choices, exact validation/safe-error copy,
  busy/disabled evidence, and success evidence.
- Deactivate, activate, resend, cancel, and replace-email confirmations identify the person and
  consequence. Cancellation requires the tenant-audit reason.
- Invalid/expired link recovery is outside canonical directory rows, offers no Accept/Retry action,
  and directs the invitee to continue without the link or ask the inviter for a new invitation.
- Mobile row actions are text-labeled, the pending invitation disclosure is visibly expanded, and
  all controls are 48px minimum. Desktop controls use shared `action-button`/`input-field` minimum
  heights of 48px. The tablet frame retains 48px actions without horizontal overflow.
- HTML searches found no invented role, permission matrix, schedule, last-shift, passcode, owner
  transfer, staff-delete, Kijani/Operational Hub, tax/VAT, or generic navigation content.

## Repository and system impact

No Flutter, Firebase, schema, rules, indexes, functions, deployment, or design-system mutation was
made. Repository changes are limited to the Stitch index, coverage/reference ledgers, open-question
record, README, and this audit. No Stitch screen was deleted, hidden, moved, grouped, or archived.

## Final status

Phase 07 is `COMPLETED / VISUAL REVIEWED`:

- ST-055 is the desktop/tablet canonical candidate.
- ST-056 is the mobile canonical candidate.
- ST-051 through ST-054 remain superseded evidence history.

