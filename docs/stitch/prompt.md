# Chilltent POS development orchestration prompt

> **Running unsupervised?** Read `AUTONOMOUS_HANDOVER.md` first. It grants the authority to proceed
> without per-step confirmation, sets the testing and commit cadence, and lists the traps that have
> already cost time. This file stays the substance; that one is the operating charter.

You are the primary integration agent responsible for implementing the approved Chilltent POS
redesign. Coordinate development using a hybrid model: establish shared foundations sequentially,
then delegate independent product domains concurrently, and finish with one cross-system integration
audit. Do not assign one isolated agent to every phase without accounting for shared dependencies.

## Objective

Begin implementation from the existing design system and evidence while preserving product truth,
RBAC, offline behavior, and responsive intent. The designs are sufficiently complete to begin
development, but several screens remain provisional. Do not present provisional screens as
pixel-perfect or invent missing product behavior to fill a visual gap.

**Governing intent, stated by the product owner on 2026-08-22: match the design as closely as the
design actually specifies, without changing core app logic.** Every design-system decision in
`OPEN_QUESTIONS.md` items 8 to 21 was taken on that basis, and it is the tie-breaker when a choice is
otherwise balanced: prefer the option that moves pixels toward the design and leaves repository calls,
state, routing conditions, and API shapes untouched.

Two consequences worth stating plainly:

- **Fidelity is not the goal where the design is factually wrong.** Several screens carry facts the
  code contradicts — ST-027's stale sign-in copy, ST-036's invented save-failure cause, ST-048's
  `Ceramic Mug`/`Tax (16%)`/refund figures, ST-039's `Before/After`, and ST-040's truncation. Those are
  corrections, not fidelity targets. `LIVE_PHASE_HANDOFF.md` lists them per phase.
- **`OPEN_QUESTIONS.md` item 7 is a deliberate exception.** Editable in-app branding was chosen twice
  and does add logic. It is a separate later slice with its own design pass, and it does not enter
  Phase 08.

## Current state — read this before planning anything

Branch `stitch-wave-0-tokens`, as of 2026-08-22. **Do not re-decide or redo any of this.**

| Landed | Where |
|---|---|
| Design source is a local export, mapped to all 73 logical IDs | `EXPORT_MAP.md` |
| Palette resolved and **live** — `_palette = AppTokens.profoundVerdant` in `lib/theme.dart` | `TOKEN_RECONCILIATION.md` |
| `spiritTheme` reads roles for every colour and radius; no literals, no `StadiumBorder` | `lib/theme.dart` |
| Radii repointed: `sm` 2, `md` 8, `lg` 12; buttons, wells and chips off `pill` | `lib/ui/tokens.dart` |
| Status roles carry alpha tints; amber and blue carried forward as additions | `AppStatusRoles.profoundVerdant` |
| Breakpoints **decided and unchanged** at 768/1024; the till moved to `mediumFloor` | `OPEN_QUESTIONS.md` item 21 |
| 48dp guarantee enforced by a source-scanning tripwire | `test/ui/tokens_test.dart` |
| Every question in `OPEN_QUESTIONS.md` answered | items 1-23; 23 closes the half of 22 left open |
| Typography **live end to end** — families bundled and the whole scale repointed to Profound Verdant | `pubspec.yaml`, `AppTypeRoles` |
| `displayCompact` added for `headline-lg-mobile`; thirteen roles now | `lib/ui/tokens.dart` |
| The screenshot harness no longer injects a font family | `tool/screenshots/harness.dart` |
| The width axis has a viewport in **all five** of its regions, and a tripwire that says so | `harness.dart`, `test/ui/tokens_test.dart` |
| Wave 0's six unaudited components audited; four need nothing built | `audits/2026-08-22-wave-0-components.md` |
| read-only rendered as `info` `Callout` at all six sites, plus a scan and the two missing captures | `test/ui/status_test.dart` |
| `ProvenanceLine` built, seven renderings migrated, matrix photographed | `lib/ui/states.dart` |
| **`spiritTheme` now reads `AppTokens` for every text style**, and two scans hold it | `lib/theme.dart`, `test/theme_test.dart` |
| RBAC guards checked against `RBAC_MATRIX.md`: **all 31 role lists agree** | `test/tenancy/rbac_matrix_test.dart` |
| Fixtures checked and clean; eight forbidden tokens scanned for | `test/dev/product_vocabulary_test.dart` |
| The ten locations `lib/main.dart` reaches from nothing, recorded and pinned | `test/dev/reachable_lib_test.dart` |
| Phases 01 and 02 checked structurally; both contracts hold, no Dart change needed | `audits/2026-08-22-phases-01-02-structural.md` |
| **Phase 03 implemented** — the sale path composed at all four widths | `lib/checkout/checkout_cart_panel.dart` |
| Money set apart on the till only: `mono` in `AppTextRoles.money` | `OPEN_QUESTIONS.md` decision 23 |
| Both ST-036 defects checked and **neither needed code** | `AUTONOMOUS_RUN_LOG.md`, Phase 03 |

**The token work is done.** Typography landed on 2026-08-22 and closed item 20. Hanken Grotesk
(400/500/600/700) and JetBrains Mono (400/500) are bundled from the upstream OFL repositories, and
**all twelve `AppTypeRoles` name a family** rather than only `mono`. That second half is the part
worth remembering: a *component* theme's text style replaces the text theme's rather than merging onto
it, so `spiritTheme.fontFamily` — which had said `Roboto` since 2026-08-16 — was never reaching
`ListTile`, `Chip`, `InputDecoration`, `SnackBar` or `Dialog`. The harness had been hiding that by
re-applying a family to nine component themes by hand; naming it on the roles fixed it at the source,
so `screenshotTheme()` now returns `spiritTheme` unmodified and a capture is evidence again.

**The metrics followed the same day, as question 22.** The whole scale is Profound Verdant's now,
not `design.md` §2.2's. It could be decided that fast because the evidence was decisive: normalising
the served `fontSize` config across all 76 screens collapses 31 apparent variants to whitespace, and
**75 of 76 are value-identical and agree with the frontmatter**. That is the *opposite* of the radius
finding — so the lesson is not "never trust the frontmatter", it is "check it against the artifact
every time", and here it passed.

Seven roles take the design's values, five are derived from the stock Tailwind sizes those same
screens use 1,028 times alongside them, and `numericBody` is unchanged. Two things worth carrying
forward: `labelLarge` is **measured**, not derived — `.btn-primary` reads 14 / 700 / +0.05em at
`height: 48px`, which is also where §9's 48dp target appears in the design's own CSS. And **the
design sets money in `data-mono`** (65 occurrences beside `currency-kes`), where `numericBody`
deliberately stayed in the interface face. ~~It is the one fragment of question 22 still open.~~
**Answered for the till on 2026-08-22 as decision 23, and left open everywhere else** — moving every
price in the app into the mono face is still a composition decision nobody has taken, and the token
existing is not permission to take it.

Blast radius: **346 of 361 screenshots moved.** Three assertions outside the token tests moved with
it and each says why where it sits — `AppButton` 15 → 14, safe-landing scrollable 551 → 548, and a
compact row's content 36 → 37 of its 40 minimum.

**One stale instruction was corrected while verifying.** `OPEN_QUESTIONS.md`'s "coupled consequence of
decision 21" still told the reader to move `AppLayout.expandedFloor` from 1024 to 1280 as a mandatory
second step. That step was never taken and will not be — 1024 is the deliberate deviation — so the
section now carries a dated correction.

**Its other half is now closed, at `7509dcc`.** It said no harness viewport covered 1024 to 1279 and
that the four behaviours flipping there were rendered by nothing. Both true. Deriving the boundaries
rather than taking the number found a **second** uncovered region: §4.1's two band floors (768, 1024)
and §4.2's two page maxima (720 `reading`, 1200 `records`) interleave on one axis, so it is cut into
**five** regions and the harness had viewports in three. `desktopNarrowViewport` (1024x768) and
`compactWideViewport` (767x1000) close both, `everyBandViewports` is now `responsiveViewports` because
four widths are not three bands, and `test/ui/tokens_test.dart` scans the harness and fails if any
region loses its viewport. 34 new images; **none of the existing 361 moved**. `AppLayout.salePane` is
excluded from the boundaries deliberately — it is a pane inside a page, not a page maximum.

**Wave 0 is now complete, and one of its claims above was wrong.** The six components were audited
rather than built: **four needed nothing** and the audit says where each already lives. read-only needed
one site corrected and two captures added; provenance was the one component genuinely absent and is
built. The RBAC guards were checked against `RBAC_MATRIX.md` and **all 31 role lists agreed**. The
fixtures were checked and are clean.

⛔ **"The token layer is finished" was true of `AppTokens` and false of `spiritTheme`.** Seven of the
theme's text styles were not reading it: four component-theme styles reached the engine with **no font
family at all** — `chipTheme.labelStyle`, its `secondaryLabelStyle`, `listTileTheme.subtitleTextStyle`
and `snackBarTheme.contentTextStyle` — and three `TextTheme` slots carried type sizes §2.2 does not
have (40, 16 with Material's leading, 15/600 against the measured 14/700). The consequence was in
`screenshots/` for nine days: `02-choose-business` drew every membership's role line as an unreadable
bar, because a `ListTile` **subtitle** is taken as given where its title merges. This is the trap
`AUTONOMOUS_HANDOVER.md` §8 predicted, in three of the five components it names. Both halves are fixed;
`lib/theme.dart` now names no type metric of its own at all, and two scans in `test/theme_test.dart`
hold the line.

**Phases 01 and 02 are checked structurally, at `06a24f9`, and needed no Dart change.** Every
structural acceptance criterion of both was already met and four of the eight are now asserted by
tests. See `audits/2026-08-22-phases-01-02-structural.md` for the two divergences kept — ST-028's
refusal sentence and its mobile caps-lock hint — and for the two places the app is already right
where the served design is wrong: `Own shift panel` is not a route here, and the local evidence is five
**counts** rather than ST-033's `KES 4,200.00`.

**Wave 1 has started, and Phase 03 is done.** The sale path is the first screen any session has
recomposed to a Stitch layout — `107cdea` to `82f2f50`. The browse pane is a fixed head over a
scrolling grid; the product tile is two tiles chosen by §4.1's band, because ST-035 and the recovered
browse render *are* two tiles; the cart pane is a head, a scrolling middle and a foot, so a save is
never below a fold; and above 768 the two regions are separated by depth rather than by a hairline.
**Both ST-036 defects the handoff named needed no code at all** — the app already returns the generic
save refusal and has no bottom navigation anywhere — which is the third and fourth instance of the
Phase 02 pattern, *the app is right where the design is wrong*.

**Next: Phase 04 (catalog/stock), then 07 (staff/access), then 09 (platform ops)**, which is the rest
of Wave 1 in `AUTONOMOUS_HANDOVER.md` §3's order. Phase 04's full mobile composition does not exist and
Phase 09 has no verified canonical screen; both mean inventing where Phase 03 had evidence.

**Read `AUTONOMOUS_RUN_LOG.md`'s Phase 03 section before touching the till again.** It carries three
deliberate deviations from the served designs and the reason for each, and the four figures decision 23
lands on.

**The web target does not run, and it is not the redesign's fault.** Two independent pre-existing bugs,
both in the bootstrap, both unfixed because they are behaviour changes needing explicit authorization:

- `lib/main.dart:60` — `FirebaseAppCheck.instance.activate()` passes only `providerAndroid` and
  `providerApple`, so on web the JS side dereferences a null web provider and debug boot throws
  `Cannot read properties of null (reading 'initialize')`. `kDebugMode` gates the block, so release
  web is unaffected. Guarding with `!kIsWeb` fixes it.
- `web/index.html:108` defines `removeSplashFromWeb()` and **nothing calls it** — `flutter_native_splash`
  is a dependency no file in `lib/` imports. The engine mounts and paints (`<flutter-view>` and
  `flt-glass-pane` are in the DOM, no JS errors) behind a permanent full-screen splash.

Verified working: web **compiles** in debug and release, and **Windows desktop is a connected device
with neither problem** — use it if you need to see the app actually run. Nothing in the remaining
Stitch work depends on a running app.

## Read before changing code

Read these sources in order:

1. Repository guidance and the indexed current-state sections of `PLAN.md`.
2. `docs/stitch/EXPORT_MAP.md` — the local design source, and the first thing to read. Design
   artifacts now come from the gitignored project export, not from a connector. This map is the only
   way to turn a logical ID or a phase into a file you can open, and it records which export folder is
   canonical where several are near-identical.
3. `docs/stitch/LIVE_PHASE_HANDOFF.md` — per-phase design debt, pending work, exact IDs, and no-go
   instructions.
4. `docs/stitch/README.md` and `docs/stitch/DESIGN_RULES.md`.
5. `docs/stitch/RBAC_MATRIX.md`.
6. `docs/stitch/OPEN_QUESTIONS.md` — **mandatory, not optional.** All 23 items are answered, so read
   it as the decision record rather than a list of blockers: it says which values were chosen, which
   were carried forward because the design defines none, and why. **Four sections carry dated
   answers or corrections that reverse the text above them** — item 19 on the radius scale, the
   "coupled consequence of decision 21" on `expandedFloor`, question 22 on typography metrics, and
   decision 23 on how money is set. Read the correction, never the row above it.
7. `docs/stitch/TOKEN_RECONCILIATION.md` — how Profound Verdant maps onto `lib/ui/tokens.dart`, and
   which roles have no source value at all.
8. `docs/stitch/SCREEN_INDEX.md` and `COVERAGE.md` as needed.
9. The brief and audit for each phase being implemented, plus
   `audits/2026-08-22-wave-0-foundations.md` for the state of the shared foundations.
10. Relevant active Flutter/Firebase code and tests. Code is authoritative for behavior and data.

Do not sweep `HISTORY.md`; use its index and read only the sessions referenced by a current decision.
Inspect Git status before editing and preserve all existing unrelated changes.

## Authority and design-debt rules

- Active code and server contracts define behavior, permissions, data, and offline semantics.
- The exported Stitch artifacts named in `EXPORT_MAP.md` define intended presentation. **There is no
  Stitch connector.** Do not plan around fetching, refreshing, or re-rendering a screen: if a session
  has no Stitch MCP server, the export is the whole of the available design truth, and no amount of
  retrying will produce a live read.
- `LIVE_PHASE_HANDOFF.md` overrides earlier assumptions that a mutation summary proves persistence.
  Its pending-work lists still stand; the export reproduces the state it audited, defects included.
- A successful Stitch DOM-operation response recorded in an earlier session is intent evidence only.
  The export is what was actually served.
- Do not issue any Stitch mutation, broad regeneration, design-system change, or feature addition
  unless the user explicitly authorizes it. A mutation additionally requires a session that has the
  connector, which this one does not.
- Resolve ordinary visual gaps from the established Profound Verdant system **only where it actually
  defines a value.** It is incomplete in specific, documented ways — most importantly it has no
  warning colour and no info colour, and its status chips are specified as an alpha mechanism rather
  than as opaque values. Consult `TOKEN_RECONCILIATION.md` before assuming a role exists. The gaps
  named above are already answered — amber and blue carry forward as documented additions, and the
  chips became alpha tints — so this rule is for the **next** gap, not those. Where a role has no
  source value, record it in `OPEN_QUESTIONS.md`; do not pick a plausible hex.
- The most important provisional areas are Phase 04 mobile and Phase 08 completion matrices. Phase 02
  checkout evidence and the two Phase 06 shift cards also lack persisted final pixels.
- **The colour, radius and typography repoints have landed.** `lib/theme.dart` registers
  `AppTokens.profoundVerdant`; `AppTokens.dark` is kept as the record of the shipped palette and must
  come out of any change unedited, which a test asserts. **No token family is still on the old
  values**, metrics included.
- **The design system's frontmatter is not automatically the authority.** It was for colour, where it
  agreed with the served screens. It was **wrong** for radii: the frontmatter declares `full: 9999px`
  and the prose promises a pill, while every one of the 76 served screens inlines `full: 0.75rem` and
  renders square-cornered buttons. When frontmatter, prose and artifact disagree, **the artifact
  decides** — and check the artifact before trusting either of the other two.

## Coordination model

Use one primary integration owner and at most three concurrent implementation agents. Delegate only
bounded work with non-overlapping file ownership. If isolated worktrees are unavailable, agents must
not edit the same shared files concurrently.

Only the integration owner may change:

- application bootstrap and top-level routing;
- shared tenant/platform shells and global navigation;
- design tokens, app theme, and common responsive primitives;
- shared domain models, service interfaces, generated configuration, dependency files, or lockfiles;
- `PLAN.md`, `HISTORY.md`, central Stitch control documents, and final commits.

Domain agents own their assigned feature directories and focused tests. If a domain agent needs a
shared change, it must describe the required interface to the integration owner instead of editing
shared infrastructure opportunistically. Subagents must not stage, commit, revert, or overwrite
unrelated work; the integration owner reviews and commits phase-sized increments.

## Implementation waves

### Wave 0 — sequential foundations

**Most of these already exist.** `lib/ui/tokens.dart` is a 1,431-line two-layer semantic token system
registered at `lib/theme.dart:201` and read by 58 files. Wave 0 is therefore validation and repointing,
not construction. Read `audits/2026-08-22-wave-0-foundations.md` before deciding anything here.

The integration owner validates or establishes:

- Profound Verdant semantic tokens, typography, spacing, shapes, status treatments, and 48px target
  primitives. **All of it is done** as of 2026-08-22: colour, radii, status treatments, spacing, and
  typography in both halves — families and metrics. Nothing in the token layer is outstanding. 48px
  is now enforced by a
  test that fails if `lib/` ever applies `AppDensity.compact`, whose targets are 32x32; when a density
  resolver is written it must take the pointer/touch kind, not just a width, and refuse compact on
  touch;
- responsive desktop/tablet/mobile scaffolds. These exist and the breakpoint floors are **settled** at
  768/1024 as a deliberate deviation from Profound Verdant's 1280 — a table at 1194 beats stacked
  cards on an operational surface. **Done at `7509dcc`:** the harness now declares a viewport in every
  one of the width axis's five regions, so the four behaviours that flip at 1024
  (`record_list.formFor`, `home_navigation.showsMenu`, `PageHeader.showsDisplayTitle`,
  `routes._isExpanded`) are photographed at the floor where they flip, and 720-767 — compact band,
  reading maximum already firing — is photographed too. A tripwire in `test/ui/tokens_test.dart` fails
  if a region loses its viewport;
- authenticated identity, tenant selection, platform separation, and RBAC route guards;
- role-aware tenant navigation and the distinction between common routes and role-specific routes;
- reusable loading, empty, error, disabled, read-only, offline, busy, confirmation, and provenance
  components. **Done, and the answer was not six components.** `audits/2026-08-22-wave-0-components.md`
  records that **four of the six need nothing built** — disabled is a state on six controls, busy is
  `AppButton.loading` plus `LoadingState`, confirmation is `ConfirmDialog`, offline is three treatments
  because it is three facts. read-only needed one site corrected (a bare `Text` where five siblings are
  `info` callouts) plus the two captures that had never contained the branch. **provenance was the one
  genuinely absent**, and `ProvenanceLine` in `lib/ui/states.dart` replaces seven hand-written
  renderings with zero pixels moved;
- test fixtures/builders that use supported Chilltent facts instead of invented examples. **Checked and
  clean:** no forbidden branding, invented role, tax, refund or reorder threshold anywhere in `test/`
  or `tool/`, and the screen captures use the seed script's own catalog exactly.
  `test/dev/product_vocabulary_test.dart` keeps it that way for the waves that implement the screens
  whose designs carry those facts.

Implement Phases 01 and 02 structurally during this wave because every tenant workflow depends on
their routing and permission contracts. Keep their documented visual debt explicit and bounded.

Do not start broad parallel feature work until the shared component APIs, navigation contract, and
file-ownership map are stable.

### Wave 1 — concurrent product streams

Run these streams concurrently when their files do not overlap:

1. **Commerce agent — Phase 03:** sale browse/cart, asserted tender, durable local save, later server
   confirmation, and independent printing outcomes. Remove the documented mobile generic bottom bar
   and invented save-error cause. Preserve the supported KES 135.00 mobile evidence.
2. **Catalog agent — Phase 04:** desktop/tablet catalog and stock structures first, then mobile. Treat
   the missing full mobile composition as provisional; derive styling from established route and
   card patterns without inventing reorder, supplier, purchasing, or stock-blocking behavior.
3. **Administration agent — Phases 07 and 09:** implement the visually reviewed staff/access and
   separate platform-operations candidates. Do not merge tenant authority with platform authority.

The integration owner reviews shared-shell usage, RBAC, responsive behavior, semantics, and focused
tests after each merge-sized result.

### Wave 2 — concurrent dependent streams

After Wave 1 interfaces are stable, run:

1. **Sales operations agent — Phase 06:** receipt lookup, immutable sale detail, shift history,
   returns, verification/restoration, and consequences. Reuse Phase 03 sale evidence and Phase 04
   stock contracts. Do not invent refunds, payment reversal, or tax.
2. **Reporting agent — Phase 05:** daily summary, scoped totals, profit refusal, reconciliation,
   anomalies, and permanent amendments. Preserve exact provenance and Manager read-only boundaries.
3. **Printing/settings agent — Phase 08:** supported checkout currency, direct-TCP printer settings,
   and the device-local receipts-waiting queue. Start only after Phase 03/06 receipt and print-job
   interfaces are stable. Mark non-persisted outcome/recovery layouts provisional and do not add
   unsupported settings or queue mutation.

### Wave 3 — single-owner Phase 10 integration

Do not distribute Phase 10 among independent agents. The integration owner must perform one coherent
cross-system pass that:

- selects one explained implementation/design lineage per workflow;
- checks tenant and platform shell separation;
- verifies Owner, Administrator, Manager, and Cashier permissions and navigation;
- verifies mobile, tablet, desktop, loading, empty, error, disabled, read-only, and offline behavior;
- checks checkout → sale history → return → stock and checkout → print queue dependencies;
- removes superseded/rejected design references from active implementation decisions;
- records every still-provisional pixel decision instead of claiming approval;
- runs proportionate unit, widget, golden, integration, rules, and emulator coverage.

## Phase completion contract

A phase is implementation-complete only when:

- its brief and live handoff acceptance items are represented;
- excluded capabilities remain absent;
- role and tenant boundaries are tested rather than cosmetic;
- affected layouts pass focused responsive/widget or golden checks;
- offline and failure states preserve supported consequences;
- there are no unexplained deviations from the canonical candidate or documented provisional choice;
- focused tests pass and the integration owner has reviewed the diff.

Do not block all development on a stale Stitch artifact. Implement stable behavior and established
visual patterns, but label any unrendered final arrangement provisional. Conversely, do not call a
phase pixel-perfect merely because its behavior is implemented.

## Working discipline

For every delegated task:

1. State the phase, exact scope, owned paths, dependencies, exclusions, and acceptance tests.
2. Inspect existing implementation and tests before editing.
3. Reuse shared components; do not create a competing local design system or navigation shell.
4. Implement a complete bounded slice, not scattered scaffolding across several phases.
5. Run focused tests during development and diagnose the first failure before retrying.
6. Return changed files, decisions, provisional items, test commands/results, and any shared-interface
   request to the integration owner.

For every integration checkpoint:

1. Review all agent diffs and reject overlapping, invented, or out-of-scope changes.
2. Run `git diff --check` and the proportionate combined validation suite.
3. Update `PLAN.md` and append the durable implementation/test record to `HISTORY.md` according to
   their existing governance rules; regenerate their line-number indexes with
   `dart run tool/doc_index.dart`.
4. Commit only reviewed, scoped files with a concise phase-sized message.
5. Report completed behavior, tests, status movement, provisional design debt, remaining unrelated
   changes, the commit, and the next bounded wave.

Do not deploy, push, open a PR, publish a status board, or mutate Stitch unless the user asks for that
specific external action. Continue through safe in-scope implementation while useful work remains.

## Required first response

Before editing, provide a short execution brief containing:

- the current foundation status **verified against the repository**, not copied from the Current state
  table above. That table was accurate when written and this prompt has already gone stale once, so
  check the claims that matter to your first chunk: what `_palette` points at, what `AppRadii` holds,
  and whether `OPEN_QUESTIONS.md` still reads resolved;
- the bounded chunk you will implement first, from what the Current state section says is left. Wave 0
  and Phase 03 are **done** as of `82f2f50`, so the next chunk is Phase 04 (catalog and stock);
- the proposed later agent streams and non-overlapping ownership boundaries;
- the known design debts that will remain provisional — including the deliberate deviations, which are
  not debt: 768/1024 breakpoints, `pill` as an app-only value, and the deferred 3-column desktop till;
- the focused validation plan. Verify pixel claims by hashing `screenshots/` before and after, never
  with `git status` — that directory is gitignored, so it reports nothing whatever the files contain.

Then implement. Do not stop after merely restating this prompt, and **update this section and the
Current state table when you finish a step** — the previous session patched this file and then made
four more commits that invalidated the patch.
