# Chilltent POS development orchestration prompt

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
6. `docs/stitch/OPEN_QUESTIONS.md` — **mandatory, not optional.** Items 10 to 20 are unresolved
   design-system gaps that block the theme layer. Implementing against them means inventing design
   decisions.
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
  than as opaque values. Consult `TOKEN_RECONCILIATION.md` before assuming a role exists. Where it
  does not, record the gap in `OPEN_QUESTIONS.md`; do not pick a plausible hex.
- The most important provisional areas are Phase 04 mobile and Phase 08 completion matrices. Phase 02
  checkout evidence and the two Phase 06 shift cards also lack persisted final pixels.
- Eleven colour roles, the radius scale, and both type families are unresolved (`OPEN_QUESTIONS.md`
  items 10 to 20). Until they are answered, `AppTokens.dark` stays pointed at `AppColorRoles.dark`
  and no theme repoint is in scope.

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
  primitives. **The colour, radius, and typography repoint is blocked** on `OPEN_QUESTIONS.md` items
  10 to 20 and is not available to pick up. Spacing already agrees. 48px holds today only because
  `AppDensity.compact` was never wired up — `pointerOnly` has no enforcement point in `lib/`, so any
  density resolver must take the input kind, not just a width;
- responsive desktop/tablet/mobile scaffolds. These exist; the breakpoint floors are the live
  question, and no harness viewport covers 1024 to 1279;
- authenticated identity, tenant selection, platform separation, and RBAC route guards;
- role-aware tenant navigation and the distinction between common routes and role-specific routes;
- reusable loading, empty, error, disabled, read-only, offline, busy, confirmation, and provenance
  components. `EmptyState`, `LoadingState`, and `ErrorState` exist in `lib/ui/states.dart`; the other
  six are unaudited;
- test fixtures/builders that use supported Chilltent facts instead of invented examples.

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

- the current foundation status discovered from the repository;
- the Wave 0 bounded chunk you will implement first;
- the proposed later agent streams and non-overlapping ownership boundaries;
- the known design debts that will remain provisional;
- the focused validation plan.

Then implement Wave 0. Do not stop after merely restating this prompt.
