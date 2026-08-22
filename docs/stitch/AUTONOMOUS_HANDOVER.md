# Autonomous handover — complete the Chilltent POS Stitch reskin

**Written 2026-08-22, at commit `71f26c2`, on branch `stitch-wave-0-tokens`.**

You are running **unsupervised**. Read this file first, then `prompt.md`. This file is the
operating charter; `prompt.md` is the substance. Where they disagree about *how to work*, this
file wins. Where they disagree about *what is true*, neither wins — the code does.

---

## 1. Your authority, and its edges

`CLAUDE.md`'s workflow step 2 says state the plan and wait for confirmation. **That is suspended
for this run.** Nobody is watching. Do not stop to ask; decide, record, continue.

**Decide alone, and just get on with it:**

- Anything the export, `DESIGN_RULES.md`, `RBAC_MATRIX.md`, or active code already answers.
- Anything `OPEN_QUESTIONS.md` items 1-22 already answered. They are decided. Do not relitigate.
- Ordinary visual composition: spacing, ordering, grouping, which token a surface reads.
- Which phase brief to take next, within the order in §3.

**When a genuine gap appears** — the design defines no value and no rule implies one — do all four:

1. Apply the standing tie-breaker: **prefer the option that moves pixels toward the design and
   leaves repository calls, state, routing conditions and API shapes untouched.**
2. Add it to `OPEN_QUESTIONS.md` as the next numbered item, with the evidence you had.
3. Log it in `AUTONOMOUS_RUN_LOG.md` (§6) as a decision taken unsupervised.
4. Keep going. **Never stall on a question.** A recorded assumption is worth more than a stop.

**Never, under any circumstance:**

- Change behaviour. `CLAUDE.md` hard rule 1 is absolute — no repository calls, state logic, routing
  conditions or API shapes in a visual change. If a screen cannot be restyled without one, stop
  *that screen*, write down the coupling, and move to the next.
- Touch `lib/pos/**` or `lib/screens/**`. Legacy, read-only.
- Hardcode a colour, size, radius, spacing, duration or spring in a widget.
- Mutate Stitch. There is no connector, and a mutation needs explicit human authorisation anyway.
- Edit `functions/**`, `firestore.rules`, `rules-tests/**`, `pubspec.yaml` dependencies, or any
  lockfile. This whole reskin is client-only and must stay that way.
- `git push`, open a PR, deploy, or publish anything outward.
- Invent a product fact to fill a visual gap. If the design shows a capability the app lacks, the
  design is wrong. `LIVE_PHASE_HANDOFF.md` lists the known-wrong screens per phase.
- Claim a phase is pixel-perfect. Most screens are `NORMALIZED / REVIEW`, which means corrected and
  never visually confirmed. Say provisional when it is provisional.

---

## 2. What is already done — do not redo any of it

Verified at `71f26c2`:

| Landed | Where |
|---|---|
| Palette live — `_palette = AppTokens.profoundVerdant` | `lib/theme.dart:67` |
| Radii — `sm` 2, `md` 8, `lg` 12; buttons/wells/chips off `pill` | `lib/ui/tokens.dart` |
| Status roles with alpha tints; amber and blue as documented additions | `AppStatusRoles.profoundVerdant` |
| Breakpoints settled 768/1024; till on `mediumFloor` | `AppLayout`, `checkout_cart_panel.dart:220` |
| 48dp enforced by a source-scanning tripwire | `test/ui/tokens_test.dart` |
| A viewport in all five width regions, plus its tripwire — **added by this run**, `7509dcc` | `tool/screenshots/harness.dart` |
| Typography — both families bundled, all 13 roles, full metric repoint | `pubspec.yaml`, `AppTypeRoles` |
| All 22 `OPEN_QUESTIONS.md` items answered | that file |

**The token layer is finished.** Six files in `lib/` have been touched by the whole reskin so far.
**No screen has been recomposed yet** — what ships today is the app's existing layout wearing the
new tokens. That is the work you are picking up.

---

## 3. Order of work

Sequential. **Do not fan out to concurrent agents**: the token layer and shared shells are exactly
the files parallel streams would collide on, and the coordination cost is not repaid in one
unsupervised run. Use a read-only subagent for broad searches if it genuinely saves you reading ten
files; never for editing.

1. ~~**1024-1279 harness viewport.**~~ **Done at `7509dcc`.** It was two regions rather than one:
   §4.1's band floors and §4.2's page maxima interleave, so the width axis has five regions and the
   harness had three. `desktopNarrowViewport` (1024) and `compactWideViewport` (767) close both, and a
   tripwire in `test/ui/tokens_test.dart` keeps them closed. 34 new images, none of the existing 361
   moved. Later phases inherit the coverage.
2. **Wave 0 remainder.** The six unaudited components — disabled, read-only, offline, busy,
   confirmation, provenance. `EmptyState`, `LoadingState`, `ErrorState` already exist in
   `lib/ui/states.dart`; follow their shape. Then RBAC guards against `RBAC_MATRIX.md`, then test
   fixtures built from supported Chilltent facts rather than invented examples.
3. **Phases 01 and 02**, structurally. Every tenant workflow depends on their routing and
   permission contracts.
4. **Wave 1:** Phase 03 (sale/checkout), 04 (catalog/stock), 07 (staff/access), 09 (platform ops).
5. **Wave 2:** Phase 06 (sales/returns), 05 (reporting/reconciliation), 08 (printing/settings).
6. **Wave 3:** Phase 10, one coherent cross-system pass. Single owner, no delegation.

Take the phase brief under `phases/`, its audit under `audits/`, and its row in
`LIVE_PHASE_HANDOFF.md` before touching code. Use `EXPORT_MAP.md` to turn a logical ID into a file.

---

## 4. Testing policy — this is the anti-overtesting contract

The full Flutter suite is **2,250 tests and about 2m00s**. The screenshot harness is **325 tests,
395 images, about 40s**. Running either per screen is the main way this run wastes time.
(Was 2,249 / 296 / 361 when this file was written; `7509dcc` added one test and 34 images.)

**Per screen or component slice:**

- Only the focused test files covering what you touched. `flutter test test/ui/buttons_test.dart`,
  not `test/ui/`.
- `flutter analyze <the files you changed>`. **Never the repo** — it has ~477 pre-existing infos and
  the noise will teach you to ignore real output.
- `dart format` the changed files only.

**Per phase, once, before its final commit:**

- `flutter test test/` — the whole client suite.
- Regenerate screenshots **once**: `flutter test tool/screenshots` then
  `dart run tool/screenshots/build_index.dart`. Not per screen.

**Never run** the functions, rules, or integration suites unless `git diff` over `functions/`,
`firestore.rules` and `rules-tests/` prints something. It will not — this work is client-only.
Check rather than assume, then skip.

**Do not re-run a suite that passed when nothing it covers has changed since.** Diagnose the first
failure before retrying; do not re-run hoping.

**Verifying pixels:** `screenshots/` is **gitignored**, so `git status` reports nothing whatever the
files contain. Hash before and after — `find screenshots -name "*.png" -print0 | sort -z | xargs -0
sha256sum` into a scratch file, regenerate, hash again, and `comm` the two. Report how many of the
395 moved, and how many are new. A count is evidence; "screenshots regenerated" is not.

**Screenshots prove the raster and nothing else.** They do not prove the app runs and cannot show
motion at all. Never call a change verified on screenshots alone.

---

## 5. Commit policy

**One commit per screen or component slice.** Small, reviewable, each moving pixels for one reason.
The repo's own note is worth obeying: *"each moves pixels for a different reason, and a combined
diff makes every regression ambiguous."*

Before each commit: `git diff --check`, focused tests green, `git status --short` reviewed for
anything you did not intend.

Message style — read `git log` and match it. Imperative, says *why*, not what. Three real examples
from this branch: "Take the pills out, because the design never had any"; "Make the 48dp guarantee
a tripwire instead of a coincidence"; "Show the cashier the cart on a tablet".

End every message with the `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`
trailer.

**Never commit:** `functions/.secret.local` (gitignored, holds local dummy secrets), anything under
`build/`, or the export directory. **Never push and never open a PR.**

At each phase end, update `prompt.md`'s Current state table and append a session entry to
`HISTORY.md`, then regenerate the indexes with `dart run tool/doc_index.dart`. **`prompt.md` has
gone stale twice** because a session patched it and then made more commits — update it *last*, in
the same commit as the phase.

---

## 6. The decision log the human reads at the end

Create and append to `docs/stitch/AUTONOMOUS_RUN_LOG.md`. One entry per decision taken without
supervision and per commit. Keep it terse — commit sha and what shipped as the heading, then a line
each for: the decision and why and on what evidence; anything provisional; any deviation from a
brief and its reason.

This is the artifact the human reviews. A decision that is not in here did not happen as far as
they are concerned. Be honest about what is unfinished — "Phases 1-4 done, 5 blocked because X" is
worth more than a summary implying more is finished than is.

---

## 7. Quality bars that do not bend under time pressure

- **Every component ships its full state matrix** — enabled, hover, focus-visible, pressed,
  disabled, loading, error, read-only, empty, whichever apply — and each state appears in the
  screenshot harness. A component missing a state is not done.
- **Accessibility is pass/fail**: contrast, 48dp targets, focus rings, and status never conveyed by
  colour alone.
- **Motion**: anything spatial uses a spring and must be interruptible from its current position and
  velocity — never `forward()` from zero on a retrigger. Nothing on the sale path sits between an
  input and its record; the sale is written first and the animation plays over committed state.
- **No literals in widgets.** Every value comes through the token layer.

If you are running short, **cut scope, not quality**: finish fewer phases properly and say which
ones you did not start. Do not ship half-stated components across many phases.

---

## 8. Traps that have already cost time

Read this section. Every item here was paid for once.

- **`prompt.md`'s Current state has gone stale twice.** Verify the claims that matter to your first
  chunk against the code before planning on them.
- **Frontmatter versus artifact is a per-token-family question.** Colour agreed with the served
  screens. **Radii did not** — the frontmatter promised a pill and all 76 screens render 12px square
  corners, which cost a whole decision. Typography agreed again. So: check the artifact every time;
  do not conclude the frontmatter is untrustworthy, and do not conclude it is safe.
- **A component theme's text style replaces the text theme's, it does not merge.** This is why
  naming a family only on `ThemeData` silently missed `ListTile`, `Chip`, `InputDecoration`,
  `SnackBar` and `Dialog` for months. Watch for the same shape with any other component-theme value.
- **The harness no longer overrides anything.** `screenshotTheme()` returns `spiritTheme` unmodified
  and that is deliberate — it is what makes a capture evidence. Do not reintroduce an override to
  make something look right.
- **`screenshots/` is gitignored.** See §4.
- **The web target does not run**, for two pre-existing bootstrap bugs — `FirebaseAppCheck.activate`
  passing no web provider (`lib/main.dart:60`) and `removeSplashFromWeb()` never being called
  (`web/index.html:108`). Both are behaviour changes needing authorisation. **Do not fix them.** Use
  Windows desktop if you need to see the app run.
- **The phone cannot be driven by adb.** `INJECT_EVENTS` is denied at the service layer *and*
  SELinux blocks `/dev/input`, so `input tap`, `input text`, `sendevent`, `pm clear` and
  `cmd clipboard` all fail. Do not spend time on it; ask the human to tap.
- **Running the emulator suite needs the portable toolchain**, not the system one. `JAVA_HOME` must
  be `D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8` — the **nested** root — and its `bin` must be
  **first** on PATH, or Java 17 stays authoritative and firebase-tools refuses. Node 24 comes from
  `D:\firebase-emulator-tools\node-v24.18.1-win-x64`. Use firebase-tools **15.24.0** from
  `rules-tests/node_modules`, with `FUNCTIONS_DISCOVERY_TIMEOUT=60000`, `--config
  firebase.device.json`, `--only auth,firestore,functions`, `--project multitenant-pos-b8326`.
  Version 13 cannot run `firebase-functions` 7 at all — the emulator worker calls the removed
  `functions.config()` and every invocation dies with no response.
  **`firebase.device.json`'s header comment still recommends 13 for a JDK reason that no longer
  holds; it is wrong and worth correcting.** `functions/.secret.local` must exist or the emulator
  tries real Secret Manager and 403s. Seed with `node scripts/seed-dev-emulator.js` from
  `rules-tests/`, with `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080` and
  `FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099`. Sign in as `owner@example.com` /
  `Local-emulator-password-123!`.
- **Do not sweep `HISTORY.md`.** It is ~26,000 lines. Use its index and read only the session a
  current decision points at. The same goes for the 18 MB export — go through `EXPORT_MAP.md`.

---

## 9. Definition of done for the run

Report at the end, in `AUTONOMOUS_RUN_LOG.md` and to the human:

- Which phases are implementation-complete against the §7 bars and the phase completion contract in
  `prompt.md`, and which were not started.
- Every decision taken unsupervised, with its evidence.
- Every still-provisional pixel, named. Do not imply approval.
- What the tests actually prove, and what still needs a device.
- The commits, in order.

**The deliberate deviations below are not debt and need no apology:** the 768/1024 breakpoints,
`pill` surviving as an app-only value, and the deferred 3-column desktop till. The real remaining
design debt is Phase 04 mobile, Phase 08 completion matrices, Phase 02 checkout evidence, and the
two Phase 06 shift cards.
