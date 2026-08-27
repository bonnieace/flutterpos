> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 07 handover — staff and access

**Written 2026-08-22, at commit `e775bde`, on branch `stitch-wave-0-tokens`.**

You are running **unsupervised**. Phases 03 and 04 are done. This is the third screen family in
Wave 1, and it is the **best-specified phase left in the whole run** — both designs are canonical
candidates, both were freshly retrieved, and the live audit records no pending defect in either.
That is not true of any other unstarted phase.

## Read these, in this order, and no more

1. **`AUTONOMOUS_HANDOVER.md`** — still the operating charter. §1 authority, §4 testing policy, §5
   commit policy, §7 quality bars and §8 traps all stand. **Its §2 and §3 are struck through in
   places**: order-of-work items 1–3 are done and item 4 is now three-quarters done — Phase 03,
   Phase 04, and this is the third of its four.
2. **`phases/07-staff-access.md`** — the brief. Four acceptance criteria, four required state groups,
   six exclusions in one sentence.
3. **`LIVE_PHASE_HANDOFF.md` § Phase 07** — six lines, and the shortest section in that document for
   a reason: *"No design correction is known. The fresh files match the visually reviewed
   canonical-candidate pair. Freeze both screens."*
4. **`RBAC_MATRIX.md`** — the authority for this phase specifically, not just generally. Rows 58 and
   59 are the two this phase composes, and the closing note about hidden actions is its criterion 3.
5. **`AUTONOMOUS_RUN_LOG.md`, the Phase 04 section** — for its four commits and, more usefully, for
   the shape of what worked: the slice that changed no Dart found the only defect.
6. **`OPEN_QUESTIONS.md` § "Resolved for Phase 07"** — five items, already decided. Do not
   relitigate them. Decisions 24 and 25 are Phase 04's and are the two most recent.

Do **not** sweep `HISTORY.md`. `EXPORT_MAP.md` turns an ID into a folder.

---

## What you are composing

| Design | Export folder | Status |
|---|---|---|
| **ST-055** desktop/tablet | `chilltent_pos_staff_access_desktop_tablet_final_normalized` | `CANONICAL CANDIDATE / VISUAL REVIEWED` — **30,399 bytes, no pending defect** |
| **ST-056** mobile | `chilltent_pos_staff_access_mobile_final_normalized` | `CANONICAL CANDIDATE / VISUAL REVIEWED` — **29,318 bytes, no pending defect** |
| ST-051 / ST-052 | `..._staff_access_desktop_tablet_1`, `..._mobile_1` | `NON-CANONICAL / SUPERSEDED` — rejected first pair |
| ST-053 / ST-054 | `..._staff_access_desktop_tablet_2`, `..._mobile_2` | superseded second pair |

**Open ST-055's PNG first.** It is a six-section specimen sheet and the richest design in the set:

1. the full directory as owner/administrator — a table of `STAFF / ROLE / STATUS + MEMBERSHIP / ACTIONS`;
2. the read-only directory as manager, carrying its own note that a **cashier has no staff-directory
   route at all**;
3. **Form States & Validations** — invite, two correction forms (one of them the owner, labelled
   `Role (Owner roles cannot be changed)`), a queued/busy state and two validation failures;
4. **Dialogs / Consequence Confirmations** — five of them, each naming the person: deactivate Peter
   Otieno, activate Brian Kimani, resend to Faith Njeri, cancel Faith Njeri's invitation with
   `Required for the record audit log`, and replace Faith Njeri's invitation email;
5. **Page, State & Link States** — loading, empty, failed to load, `Action Failed`, and
   `Invitation invalid or expired`;
6. a tablet stacked-layout transformation.

### This design was grounded in the app's own fixtures, which is new

**ST-055 names Grace Wanjiru, Peter Otieno, Amina Hassan, Brian Kimani and Faith Njeri — all five are
the app's actual seeded staff**, in `tool/screenshots/fakes.dart` and
`rules-tests/scripts/seed-dev-emulator.js`. Contrast ST-038, which Phase 04 had to refuse for
inventing products and an invented category. I scanned both Phase 07 exports for every concept the
brief excludes — granular permission toggles, Senior Cashier, Inventory Clerk, scheduling, last-shift
management, owner transfer — and **found none**. The only hit for `schedule` is a Material icon name
(a clock glyph) in ST-056, not a feature.

So the usual Wave 1 finding — *the app is right where the design is wrong* — is unlikely to be this
phase's story. **Expect the opposite: the design is right and the app's evidence is thin.** Plan for
that.

---

## The two gaps, both measured at `e775bde`

### 1. Five of the directory's six actions have never been in a picture

`tenant_staff_directory.dart` offers six actions, each with its own key:

| Action | Key | Ever captured? |
|---|---|---|
| Correct staff details | `edit-staff-{uid}` | **yes**, `13b-staff-directory-editing` |
| Resend invitation | `resend-staff-invitation-{uid}` | no |
| Cancel invitation | `cancel-staff-invitation-{uid}` | no |
| Replace invitation email | `replace-staff-email-{uid}` | no |
| Set status (activate/deactivate) | `set-staff-status-{uid}` | no |
| Invite staff | `invite-staff-open` | no |

The whole family has **three captures** — `13-staff-directory`, `13b-staff-directory-editing`,
`13c-staff-directory-read-only` — and `TenantStaffDirectoryScreen` is the only staff route class the
harness renders at all. The brief requires *"Pending, active, disabled, expired/invalid, busy,
validation, and failure states"*, hard rule 5 requires every state to appear in the harness, and
**ST-055 section 4 draws a confirmation dialog for every one of the five that has no picture.**

This is the same class of gap Phase 04 found — a conditional surface invisible in every capture is
not covered — but it is five surfaces rather than two roles, and unlike Phase 04 the design tells you
exactly what each should contain. `20b`/`20c` in `operations_screens_test.dart` are the precedent for
driving a form and photographing its outcome; `_press` in that file is the helper.

The behaviour is *not* thin: `test/tenancy/`'s eleven staff and invitation test files are **5,501
lines and 122 tests, all passing**. Every one of those five forms is thoroughly tested and
completely unphotographed. That is the gap exactly.

### 2. The staff routes are photographed at two widths, and the band their table transforms at is not one of them

`13`, `13b` and `13c` render at `web` (1440) and `mobile` (411) only. **Zero captures at `tablet`
(834) or `desktop-narrow` (1024)** — the identical gap Phase 04 had, and ST-055's section 6 is a
labelled tablet stacked-layout specimen of exactly the transformation nobody has photographed.

Criterion 4 is *"Responsive edit forms do not overflow and retain accessible labels/errors"*, and
`13b`'s own capture note records that the five forms this route opens each ended in a `Row` of two
48-high pills that overflowed a phone — so this route has a **history** of overflowing at a width
nobody had photographed. `responsiveViewports` costs nothing to pass and is where to start.

**Phase 04's slice 1 is the model and it worked.** `responsiveViewports` on thirteen routes plus
three role captures produced 71 new images, **moved none of the existing 413**, and turned up the
phase's only real defect. Do that first here.

---

## Suggested slices

Four, one commit each, smallest evidence-bearing first. The code is the authority; adjust if it
disagrees with me.

### Slice 1 — photograph what exists

`responsiveViewports` on `13`, `13b`, `13c`, and new captures for the five unphotographed forms.
**No Dart change.** Expect roughly 6 new images from the width axis and 10–20 from the forms,
depending on how many need both a busy and a settled state.

**If a form overflows at 834 or 1024, that is the finding and it is worth more than a restyle.**
This route has overflowed before, at a width no picture covered, and nothing currently runs a widget
test at either of those widths for it.

### Slice 2 — the token debt, which is countable

`lib/tenancy/`'s staff and invitation files hold **39 literal spacing and inset values**, measured at
`e775bde`:

| File | literal sites | lines |
|---|---:|---:|
| `tenant_staff_directory.dart` | 9 | 813 |
| `tenant_invitation_acceptance.dart` | 5 | 453 |
| `tenant_staff_invitation_cancellation.dart` | 4 | 492 |
| `tenant_staff_invitation_email_replacement.dart` | 4 | 535 |
| `tenant_staff_update.dart` | 4 | 470 |
| `tenant_visible_invitation_acceptance.dart` | 4 | 473 |
| `tenant_staff_invitation.dart` | 3 | 477 |
| `tenant_staff_invitation_resend.dart` | 3 | 429 |
| `tenant_staff_status.dart` | 3 | 395 |

Far smaller than Phase 04's 97, and the mechanics are known. The pattern that finds them:

```
grep -oE "SizedBox\((width|height): [0-9]|EdgeInsets\.(all|symmetric|only|fromLTRB)\(([a-z]+: )?[0-9]"
```

**Watch for an off-scale value.** Phase 04's only pixel movement came from three `28`s in one file,
and 28 is not on `AppSpacing.all`. Check every value against that list before repointing it; where one
is off-scale, the decision is which neighbour it takes and the argument is what the same gap already
uses elsewhere in the app.

**Two mechanical traps, both paid for in Phase 04.** An expression-bodied `build` has no `tokens` in
scope and needs converting to a block body; and `const Padding(padding: EdgeInsets.all(token))` does
not compile, because a token is not a compile-time constant — the outer `const` goes and the child
`Text` takes one.

### Slice 3 — the composition, against ST-055 and ST-056

Only after 1 and 2, and scoped by what slice 1 found. `tenant_staff_directory.dart` is **813 lines**
and is the only route class; the five forms live in their own files of 395–535 lines each. That is a
kinder shape than Phase 04's 1,648-line panel.

Note that the directory already draws a **four-tile stat strip** (`staff-stat-total`,
`-active`, `-pending`, `-privileged`) that ST-055 does not have, and ST-055 draws a combined
`STATUS + MEMBERSHIP` column the app splits into a `StatusBadge` and a `RecordAttribute`. Both are
composition judgements for this phase to take and record — neither is a defect on its face.

### Slice 4 — mobile, against ST-056, which actually exists

**This is the one thing that is easier here than in Phase 04.** ST-040 was 9,218 bytes and one
section of nine, so Phase 04's mobile had to be derived and recorded as derived (decision 25).
ST-056 is **29,318 bytes and a complete canonical candidate**. Compose against it directly. If you
find yourself deriving, check the export again first.

---

## Testing — the same contract, measured at `e775bde`

- `flutter test test/` — **2,316 tests, about 2m03s**. (Was 2,315 after Phase 03, 2,314 before it.)
- `flutter test tool/screenshots` then `dart run tool/screenshots/build_index.dart` — **375 captures
  writing 484 images across 158 screens, about 50s.** (Was 337 / 413 / 155 before Phase 04.)
- Your focused suite is the eleven staff and invitation files in `test/tenancy/`: **122 tests, about
  10s**, 5,501 lines, all passing today. `flutter test test/tenancy/rbac_matrix_test.dart` is **36
  tests** and asserts all 31 role lists against the matrix.

The anti-overtesting contract has not moved:

> **On a composition slice the screenshot matrix is the deliverable, not new unit tests.**

Phase 03 added one test in seven commits and Phase 04 added one in four. Both were §9 accessibility
assertions, which §9 makes pass/fail rather than optional. **A composition change that breaks a
behaviour test means you changed behaviour** — that is hard rule 1 and it is the signal, not a gap.

Per slice: the focused test files, `flutter analyze` **on the changed files only** — never the repo,
it has ~477 pre-existing infos — and `dart format` on the changed files only.

**`dart format` the changed files, and check first whether the file needs reflowing on its own.**
`dart format --output=none --show=changed <paths>` tells you before you commit. Most of `test/` and
`tool/` has drifted from the current formatter, so a touched test file will often want a reflow of
lines that have nothing to do with your change: commit that reflow **alone, first**, then make the
change on top. Phase 03 did this twice (`107cdea`, `a5b6ca6`). **Phase 04 failed to and `06472ad`
carries about 200 lines of unrelated reflow around a 25-line change** — read that commit knowing it,
and do not repeat it. None of the six `lib/inventory/` panels needed reflow; check yours the same way.

Hash `screenshots/` before and after — it is gitignored, so `git status` reports nothing whatever it
holds. The comparison that works, given `sha256sum` prints `hash *path`:

```
find screenshots -name "*.png" -print0 | sort -z | xargs -0 sha256sum \
  | sed 's/^\([0-9a-f]*\) \*/\1 /' | awk '{print $2" "$1}' | sort > before.nh
```

then `comm` the name columns for new and removed, and `join` the two files and compare hashes for
moved. **Report how many of the 484 moved and how many are new.** A count is evidence;
"screenshots regenerated" is not. Phase 04's counts were 71 new / 0 moved on the no-Dart slice, then
49 moved / 0 new, then 40 moved / 0 new — and the useful half of each sentence is *which* files
moved, because that is what says a change was contained.

---

## What will bite, specifically on this phase

**1. The design is good, so the temptation is to stop reading the code.** Phase 04's four ST-039
defects were all already fixed in the app, and the time cost was rediscovering that. Here the risk
inverts: ST-055 is detailed and canonical, and the failure mode is implementing a *picture* of a
control the backend does not have. Criterion 1 is *"No visual control implies a permission model the
backend lacks"*, and `RBAC_MATRIX.md` row 59 is the whole permission model — invite, edit, disable,
resend, cancel, at owner and administrator, and nothing finer. There are **four tenant roles** and
no permission editor.

**2. `RBAC_MATRIX.md`'s closing note is this phase's criterion 3, and a hidden control is not a
guarded one.** *"Hidden actions must also be guarded in product code during implementation; visual
hiding alone is not sufficient."* `test/tenancy/rbac_matrix_test.dart` already asserts all 31 role
lists, so the guards are proven; what you are composing is whether a person can **see** the
narrowing. Criterion 3 is *"Manager composition contains no write affordance"* — `13c` is the only
capture of that session and its own note calls it "the only session its standing is true of".
**Phase 04's own §2 gap was exactly this**, and photographing the manager rendering is what turned up
its defect.

**3. Every destructive action must name the person and the consequence.** Criterion 2, and ST-055
section 4 draws all five that way — *"This removes the staff member's access to this business"*, and
the cancel dialog's `Required for the record audit log`. `OPEN_QUESTIONS.md`'s Phase 07 item 4 says
the same: confirmation copy names the affected person and the resulting membership consequence. This
is the phase where a tidied-up dialog is a defect.

**4. The owner is not editable the way everyone else is, and the design knows it.** Phase 07 item 3:
the owner role cannot be assigned by invitation or changed through the staff editor, and the owner
record may expose name/phone correction but cannot be deactivated. ST-055 draws the owner's
correction form with `Role (Owner roles cannot be changed)`. If a composition starts offering a
role picker on the owner, that is the item talking.

**5. An invalid or expired invitation link offers no action, and that is deliberate.** Phase 07 item
5: it stays outside the canonical directory row model and offers no Accept/Retry — the invitee
continues without the link or asks for another. ST-055's section 5 draws it that way. A `Retry`
button here would be inventing a recovery the product does not have.

**6. `test/dev/product_vocabulary_test.dart` scans eight forbidden tokens across `lib`, `test` and
`tool`, and two of them are this phase's.** `Senior Cashier` and `Inventory Clerk` are on that list
because `RBAC_MATRIX.md` names them as the invented roles. The scan will catch you; do not make it
have to.

---

## Guard rails that have not moved

- **A UI change never changes behaviour.** No repository calls, state logic, routing conditions or API
  shapes. If a screen cannot be restyled without one: **stop that screen, write the coupling down,
  move to the next.**
- **No hardcoded values in widgets.** Slice 2 is 39 counted violations.
- **`AppTextRoles.money` is the till's, not the app's.** Decision 23 says so and Phase 04 did not
  take it either. This phase has almost no money in it, so the question should not arise — but the
  token existing is still not permission to take it.
- **Do not touch `lib/pos/**`, `lib/screens/**`, or the eight other unreachable locations.**
  `test/dev/reachable_lib_test.dart` holds the list and fails if it changes. `lib/widgets/` is a
  **pill** component set; this design has no pills.
- **Do not edit `functions/**`, `firestore.rules`, `rules-tests/**`, `pubspec.yaml` dependencies or
  any lockfile.** Client-only. Check with `git diff` rather than assuming, then skip those suites —
  Phase 04 checked and it printed nothing.
- **No `git push`, no PR, no deploy.**
- **Do not invent a product fact.** Six exclusions in the brief's one sentence, plus the eight
  scanned tokens.
- **Never claim a screen is pixel-perfect.** Both Phase 07 designs are `CANONICAL CANDIDATE / VISUAL
  REVIEWED`, which is the strongest status in this project and still not an approval of *your*
  implementation. No implementation in this run has been compared to a design by a person.

## Recording

- One entry per commit in `AUTONOMOUS_RUN_LOG.md`, in its existing format. Code commit first, then the
  record naming its sha.
- Every genuine gap gets a numbered `OPEN_QUESTIONS.md` item with the evidence you had. **Decision 25
  was the last one; yours start at 26.**
- At phase end: a session entry in `HISTORY.md`, then `dart run tool/doc_index.dart`, which rewrites
  the line-numbered index in `PLAN.md` and `HISTORY.md` and is part of the same commit.
- **`PLAN.md` is the Current state file, not `prompt.md`.** Both earlier handovers said to update
  "the Current state table in `prompt.md`"; `prompt.md` is the instruction prompt, has no such table,
  and its own first line points at `PLAN.md`. What to update there: the **Flutter test baseline row**
  under "Test baselines" (line 693 at this commit, currently 2316 / 375 captures / 484 images / 158 screens) and a
  one-line row in the **Chunk index**. Phase 04 added the first Stitch row since Phase 00 — Wave 0 and
  Phase 03 never added theirs, so decide whether to backfill and say which you chose.
- Report what the screenshots prove and what still needs a device. They prove the raster. They do not
  prove the app runs, and they cannot show motion at all.

---

## Phase 04's leftovers, which are yours to decide about but not to fold in silently

Phase 04 finished three of its four slices. What it deliberately did not do:

- **Screens 20, 20b and 20c were not migrated to `RecordList`.** Their rows are `CheckboxListTile`s
  whose subtitle is a bullet-separated sentence — `Household ▪ 5901234123457 ▪ 145.00 ▪ costs 112.00`,
  the pre-migration shape §5.2 replaces with key-value attributes — and the report rows below them are
  raw `Card`s. The note at `bulk_catalog_panel.dart` and `OPEN_QUESTIONS.md` decision 25 both reach the
  same conclusion: this is the work step 6 did for twelve screens, and it is larger than a Phase 04
  slice. **It is not Phase 07's either.** Leave it named rather than absorbing it.
- **`checkout_evidence.dart:311` holds a literal `EdgeInsets.only(bottom: 8)` that no phase claims.**
  `PHASE_04_HANDOVER.md` asserted all seven of `lib/checkout/`'s literals were in
  `checkout_configuration_panel.dart`, which is Phase 08's screen 16; six are, and this one is Phase
  02's checkout-evidence surface. One line, hard rule 2, and currently nobody's.
- **Whether a zero stock figure deserves a softer status than a negative one is open** — decision 24
  says so explicitly. ST-039 draws only the below-zero row, so the design defines nothing for zero.

## What this handover measured, and why that sentence is here

Every figure above was taken at `e775bde` by running the thing: line counts by `wc -l`, literal
spacings by the grep printed in slice 2, capture coverage by listing `screenshots/` and grepping the
capture definitions, action coverage by grepping `tenant_staff_directory.dart` for its action keys and
the harness for each, test counts by running the suites, and the exclusion scan by grepping both
export files for every concept the brief forbids.

**`PHASE_04_HANDOVER.md` got two things wrong and both are corrected above**: `lib/checkout/`'s seven
literals are six plus one elsewhere, and `prompt.md` has no Current state table. Its 97, its per-file
table, its four ST-039 checks and its ST-040 byte count were all exactly right and reproduced on the
first try. `PHASE_03_HANDOVER.md` before it had one wrong figure. **Re-measure anything here that your
plan depends on**; if a figure has moved, correct it in place and say so.

**The web target still does not run**, for two pre-existing bootstrap bugs (`lib/main.dart:60`,
`web/index.html:108`). Both are behaviour changes needing authorisation. **Do not fix them.** Use
Windows desktop if you need to see the app run.
