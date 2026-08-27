> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 09 audit - platform administration

Date: 2026-08-21

Project: `7478406619239162026`

Operation: authorized `CREATE`, followed by approved bounded `CORRECT` passes

Design system: Profound Verdant `assets/4c1cc58b4aed4b1693e6f8113ba1009a`, retained and not mutated

## Scope and product evidence

Phase 09 used screenshot groups 09a through 09d; the active platform tenant review, lifecycle,
archival, and global-user-status panels; the platform routing shell; callable implementations; and
authorization rules. The console is a distinct operational area. Eligibility is conjunctive: an
active root with `accountType=platform_admin` and token `platformRole=superAdmin`. A tenant
membership is neither required nor sufficient.

The admitted lifecycle is pending→active or pending→rejected, active↔suspended, and
rejected→archived through `setTenantLifecycle`. Global user disable/reactivation uses
`setGlobalUserStatus` and one exact Firebase Auth UID. It exposes guarded confirmation, reason,
operation/attempt/affected-tenant evidence, owner/administrator impact warnings, alert behavior,
partial-operation retry, and the possibility that the current operator leaves the console.

Tenant role authority, billing, portfolio management, owner transfer, bulk actions, platform-role
grant/revoke UI, and invented callables were excluded.

## Initial creation

The authorized creation produced:

- ST-065 `57321255989a43c09afabd18be5a0b30` - desktop, 2560x2438.
- ST-066 `9eda47b71aa647cd9c7548dc8ce8890c` - mobile, 780x3786.

Their downloadable artifacts were inspected and rejected. ST-065 stopped after the authority shell,
pending review, active/suspended content, and a compressed ledger. ST-066 stopped after authority
and pending admission. Neither represented the required archive, global-status, state, and
responsive scope.

## Approved corrections

The first bounded correction produced:

- ST-067 `0ac6b3b719dd4573b1208445d171ff78` - desktop, 2560x12714.
- ST-068 `a2a68ab710db4bdd8bc3a0df89631688` - mobile, 780x15786.

Both expanded into long-form suites. Direct artifact review found remaining callable, transition,
authority-copy, global-status, and state-matrix defects. The next approved surgical pass corrected
ST-067 in place and produced mobile successor ST-069
`9a27aa1c5de64228ac85e395e98e3b8d` at 780x19632. ST-069 restored the principal semantics but still
used incomplete route state matrices.

The final approved micro-correction produced ST-070
`79c011b38c4c4bfea3f0db1a2145c366` at 780x27072 and completed ST-067 through exact DOM operations.
Desktop events `95228ada`, `93aeb4c4`, `cb42c78f`, and `45c09e19` cover the authority terminology,
row-specific callables/transitions/evidence, reactivate and unavailable specimens, exact result
metadata, safe partial retry, full `Tenant Owner & Administrator` label, and 48px retry control.

## Verified result

ST-070 was retrieved after generation. Its fresh HTML file `60235cba1c74416a9291fc858ae8716a`
and full-height screenshot `0a0c90f5e3dd4536bb1c542f4e260eef` were downloaded and inspected.

The artifact contains all seven sections: platform authority and distinct shell; pending business
reviews; active/suspended businesses; rejected archive; global user status; consequence matrix; and
mobile interaction ledger. Pending, lifecycle, archive, and global-status routes have concrete
loading, empty or absent, validation, busy, success evidence, conflict, permission, missing-record,
and remote-failure specimens. A mobile-visible Sign out route is present independently of the
desktop header action.

The consequence matrix uses `setTenantLifecycle` for its five tenant transitions and
`setGlobalUserStatus` for disable/reactivate. It preserves pending→active, pending→rejected,
active→suspended, suspended→active, and rejected→archived; carries fanout operation IDs; and states
that suspension does not globally disable users. Global status uses `accountType: tenant_user`, one
exact UID, active relationship warnings, no archived-business warning, a reasoned disable dialog,
reactivation, operation ID, affected tenant IDs, attempt count, conflict/missing/remote states, and
same-operation partial retry. All buttons and inputs resolve to at least 48px.

No prohibited tenant-role, billing, owner-transfer, bulk, or platform-role administration surface
was found in the final mobile artifact.

ST-067 retrieval succeeds but still serves pre-operation HTML file
`e06f5798b3714ce39af875f0d764b62c` and its associated earlier screenshot. Its completion is therefore
mutation-reviewed from the exact DOM-operation payloads rather than visually approved.

## Re-fetch verification

An explicit follow-up re-fetched the project, screen list, every Phase 09 exact screen ID, and the
two final downloadable artifacts. `list_screens` returned 51 screens but none of ST-065 through
ST-070; `get_project.screenInstances` likewise contained none of the six. Direct exact-ID retrieval
produced the following current result:

- ST-065: invalid argument.
- ST-066: retrievable at 780x3786, files `7f4ed815e9444f7088198932d0586ad1` and
  `381024396ad649cc8957e1bf32245146`.
- ST-067: retrievable at 2560x12714, still serving files
  `e06f5798b3714ce39af875f0d764b62c` and `0a3f8404d2a24844b5d5b35512893e3e`.
- ST-068: retrievable at 780x15786, files `7f04943806a7409caf341d1e89110f5b` and
  `6453c4373cef484cbb9899f709a1efec`.
- ST-069: invalid argument.
- ST-070: retrievable at 780x27072, still serving final files
  `60235cba1c74416a9291fc858ae8716a` and `0a0c90f5e3dd4536bb1c542f4e260eef`.

The re-fetched ST-070 HTML SHA-256 is
`946E809B38CC6CD02AF667FA9F8701AD2F6380BC56D3CC6A0FA9D9ABEF4E2366`, exactly matching the artifact
already reviewed. The re-fetched ST-067 HTML SHA-256 is
`3D68F0684A791762885E350B7558BC650EE9E04D145661858662FA533FC43BB7`; content inspection confirms it
is still pre-correction (for example, the consequence matrix contains only
`setGlobalUserStatus`, not the five `setTenantLifecycle` rows recorded by the DOM operations).
Therefore the re-fetch strengthens, rather than changes, the mixed review classification.

## Current-canvas confirmation and final desktop attempts

The user copied ST-067's current canvas HTML directly from its exact screen route. After line-ending
normalization it was character-for-character identical to the freshly downloaded pre-operation
artifact: 50,380 characters across 780 lines. It retained `approveTenant`, `rejectTenant`,
`suspendTenant`, `reactivateTenant`, and `archiveTenant`, and lacked the recorded exact-UID,
relationship, partial-retry, and accessibility corrections. ST-067 is therefore superseded rather
than mutation-reviewed.

An approved comprehensive correction produced fresh desktop ST-071
`9eb5043c3c45455b96c920eb49bbfcb6` at 2560x13564. Its HTML file
`ea9fc39a7b934af99fac26387e63c148` and screenshot `3e03efa6a3f941f992c2e9d3abc0678f`
were downloaded and inspected. SHA-256 is
`47B860FF92FB19908B0704915DDE2BD0B709D1C0BFB0565B0F87F3FB5DA0EB31`.

ST-071 removes the invented callables; contains five `setTenantLifecycle` and two
`setGlobalUserStatus` matrix rows; restores the distinct authority shell, exact UID,
`accountType: tenant_user`, relationship warnings, guarded dialogs, result values, and 48px
controls; and preserves the 834px tablet specimen. Six bounded defects remained: suspension used
audit-log-only evidence, reactivation omitted `after checks`, archive added `(hidden)`, the archived
relationship omitted its no-warning statement, retry help was tooltip-only, and global busy/success
specimens were absent.

The approved micro-correction returned exact event `356c191b`, but direct retrieval continued to
serve the same ST-071 files and the user-copied current canvas HTML confirmed that none of those
changes persisted.

At the user's request, one last correction used a single refined fresh variant and produced ST-072
`85d612f037d745beb304a7cf078cea11` at 2560x14614. Its returned HTML file
`f6469b48242b4ed6a60996aea5756096` and screenshot `8443ee0629e3465e8c8a64bdd794e380`
were downloaded and inspected; HTML SHA-256 is
`355E6BC51BC49C45FA892D788478E8188141FC27DF633299B5CC04E2F640F381`.

ST-072 successfully bakes in the exact prerequisites, lifecycle evidence/transitions, archived no-
warning copy, visible retry help, global busy/success evidence, archival copy, correct callables,
and 48px controls. It is nevertheless rejected because the generator also injected
`Reuses the same operation/request ID.` into unrelated invalid, permission-denied, remote-failure,
archived-status, failure, and current-operator self-disable chips, including invalid paragraph-inside-
span markup. Exact-ID `get_screen` returns invalid argument. No automatic follow-up was attempted.

The user subsequently authorized fixing that regression. A single text-content refinement produced
ST-073 `3c3f120ed8fe4f5c88946b5e9a54d814` at 2560x14576. Exact-ID retrieval succeeds and serves HTML
file `bb5e38d211e2496a9d42e76f712d34ba` plus screenshot
`bf78d5088408476a961aa28fd13950dd`. The downloaded HTML SHA-256 is
`F9D36218C2055FA2936AA4ADA4997EF6F48ED7941B27CE7165A80A0785B167CE`.

Direct inspection confirms one visible `Reuses the same operation/request ID.` help paragraph below
the partial-failure retry button and no copy pollution in other state chips. There is no paragraph
nested inside a span. The artifact retains the five `setTenantLifecycle` and two
`setGlobalUserStatus` matrix rows; exact prerequisites, transitions, inputs, and evidence; archived
no-warning copy; global busy/success result values; exact UID/account type; archival consequence;
and every required exclusion. All 48 button/input/textarea elements have a confirmed minimum height
of 48px. The fresh full-height screenshot was visually inspected.

## Repository and system impact

No Flutter, Firebase, schema, rules, indexes, functions, deployment, or design-system mutation was
made. Repository changes are limited to the Stitch index, coverage/reference ledgers, open-question
record, README, and this audit. No Stitch screen was deleted, hidden, moved, grouped, or archived.

## Final status

Phase 09 is `COMPLETED / VISUAL REVIEWED`:

- ST-070 is the mobile `CANONICAL CANDIDATE / VISUAL REVIEWED` successor.
- ST-073 is the desktop `CANONICAL CANDIDATE / VISUAL REVIEWED` successor.
- ST-071 is superseded; its micro-edit did not persist.
- ST-072 is rejected because its fresh artifact pollutes unrelated state chips with retry-help copy.
- ST-065/ST-067 are superseded desktop history; ST-066/ST-068/ST-069 are superseded mobile history.
- Product scope is resolved and both final device directions qualify for canonical promotion.
