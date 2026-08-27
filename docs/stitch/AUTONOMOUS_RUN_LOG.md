> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Autonomous run log

Every decision taken without supervision, and every commit, during the unsupervised completion of
the Stitch reskin. **This is the artifact the product owner reads at the end.** A decision that is
not written here did not happen, as far as review is concerned.

Format, newest last:

```
## <commit sha> — <what shipped>
- Decision: <the choice> — <why, one line> — <evidence, or "no source value">
- Provisional: <anything whose final pixels are not confirmed>
- Deviation: <anything that departs from a brief, and why>
```

Keep entries terse. Record a decision when you chose between real alternatives, not when you
followed an instruction. Record every gap you filled with the standing tie-breaker — *prefer the
option that moves pixels toward the design and leaves behaviour untouched* — because those are the
ones the owner most needs to check.

Operating charter: `AUTONOMOUS_HANDOVER.md`. Substance: `prompt.md`.

---

## Starting point — commit `71f26c2`, 2026-08-22

No autonomous work has run yet. The token layer is complete (palette, radii, status treatments,
spacing, 48dp tripwire, breakpoints, typography in both halves) and **no screen has been recomposed
to a Stitch layout**. All 22 `OPEN_QUESTIONS.md` items are answered.

One fragment of question 22 is deliberately left open and is **not** a gap to fill silently: the
design sets money in `data-mono` (65 occurrences beside `currency-kes`) while `numericBody` stays in
the interface face. Moving every price into the mono face is a composition judgement per surface,
like the `mono` reader sweep. If a phase reaches it, decide per surface and log it here.

---

## Convention — how a commit sha gets into this file

The heading format above names a commit sha, which cannot be known while the commit that produces it
is being written. So each slice lands as **two** commits: the code, then the record naming its sha.
That keeps the sha real, and it keeps `prompt.md` last, which is what the charter's step 5 is actually
protecting against — a session patching the Current state table and then making more code commits
that invalidate it. Decided unsupervised; if the owner would rather have one commit per slice with the
sha left out, this is the line to change.

---

## `7509dcc` — the 1024-1279 harness viewport, and a second region beside it

Order-of-work item 1. Additive: 34 new screenshots, **none of the existing 361 moved**, hashed before
and after.

- Decision: **the width axis has five regions, not three.** §4.1's two band floors (768, 1024) and
  §4.2's two page maxima (720 `reading`, 1200 `records`) are four boundaries on one axis and they
  interleave, so a width can cross a maximum without changing band and the reverse. The handover named
  1024-1279; deriving the boundaries rather than taking the number surfaced a second uncovered region
  at 720-767. Evidence: `AppLayout` in `lib/ui/tokens.dart`, and the harness's own header, which said
  1440 and 411 "straddle" every boundary — true, and not the same as covering what they straddle.
- Decision: **the new widths are the boundaries themselves, 1024 and 767, not midpoints.**
  `AppLayout.isAtLeast` is inclusive, so 1024 is the first width at which all four named behaviours
  flip (`RecordList.formFor`, `HomeNavigation.showsMenu`, `PageHeader.showsDisplayTitle`,
  `routes._isExpanded`) and 767 is the last width that is still `compact`. A picture of a boundary is
  worth more than a picture near one. Evidence: `test/ui/routes_test.dart` already asserts "exactly
  1024 is expanded", so the arithmetic was pinned and only the rendering was not.
- Decision: **`AppLayout.salePane` (420) is not a boundary.** It is the fixed width of a pane inside a
  page rather than a maximum applied to the page, so nothing about a screen changes when the window
  crosses it. Excluding it is what keeps the region count at five. Evidence:
  `checkout_cart_panel.dart:720` sets it as a `SizedBox` width; no `maxWidthOf` path reads it.
- Decision: **`everyBandViewports` renamed to `responsiveViewports`.** With a fourth entry the old name
  states something false. The 20 call sites are a mechanical rename and move no pixel.
  `compactWideViewport` is deliberately **not** in that list — for a component that varies by band and
  not by maximum, 767 is 411's rendering stretched, and 20 more images of that is the diff nobody
  reads. It is the same judgement `tabletViewport`'s own note has recorded since step 6.
- Decision: **the content-width matrix takes all five**, as `everyRegionViewports`, going from 6
  pictures to 15. Its header claimed six was "that matrix in full", which was the matrix of a
  two-value width axis that does not exist.
- Deviation from the handover, upward: it asked for one viewport and got two, plus a tripwire. The
  tripwire is the reason the second one exists — deriving the regions from `AppLayout` in
  `test/ui/tokens_test.dart` is what made 720-767 visible, and shipping a tripwire that checked only
  the region already fixed would have been the weaker artifact. It names the failing interval in its
  message, and was verified by deleting a viewport and watching it fail.
- Provisional: **nothing.** No existing pixel moved and no composition decision was taken. The 34 new
  images are the app's current layout at two widths nothing had rendered — evidence to review, not a
  design proposal.
- Finding for the owner, not a decision: at 1024 a `RecordList` table's action cell **stacks** its two
  buttons where 1440 lays them side by side, so a row is about 145px tall and four fit in the window
  instead of five. Correct behaviour under the existing widget, no logic touched, and now at
  `screenshots/desktop-narrow/96-record-list.png`. Whether it is the wanted arrangement is a Phase 04
  composition question.
- Also observed, not fixed: `build_index.dart`'s generated README still says the only faces loaded are
  "Roboto and the Material icon font" and that two glyphs render as tofu for that reason. Both
  statements predate the typography repoint at `71f26c2` and are now wrong. Left alone because
  correcting generated prose is a different reason to move text and belongs in its own commit.

## `a77e95c` — the Wave 0 component audit, written before anything was built

Order-of-work item 2, first part. No Dart file changed.

- Decision: **four of the six named components need nothing built.** disabled is a state on six
  controls, all photographed; busy is `AppButton.loading` plus `LoadingState`, two treatments for two
  facts; confirmation is `ConfirmDialog`, which has the widest matrix of the six; offline is three
  treatments because `DESIGN_RULES.md` asks for three facts to stay separate. Evidence: greps over
  `lib/` plus the case list in `tool/screenshots/`, both recorded in
  `audits/2026-08-22-wave-0-components.md`. Building all six would have stood four competing systems
  next to working ones, which `prompt.md`'s working discipline forbids by name.
- Decision: **no page-level "everything is disabled" wrapper.** `RBAC_MATRIX.md`'s design implications
  rule it out directly — *"A cashier home should remain intentionally narrow, not appear as a
  disabled manager dashboard"* — and `11-business-home-cashier`'s own caption already records the
  app obeying it: four of the owner's buttons are absent rather than disabled.
- Decision: **read-only gets a corrected site and a scan, not a `ReadOnlyNotice` component.** `Callout`
  already is the component and already has a photographed matrix; a wrapper would add a name, a second
  matrix and six migrated call sites in order to choose `AppStatus.info`. The repository's own habit
  for a cross-file invariant is a source scan, and there are three already.
- Decision: **provenance is the one component to build**, because it cannot be pinned by a scan:
  `caption` with `text.tertiary` appears 29 times in `lib/` and only seven are provenance, so the style
  is not the identifying feature and the concept needs a name.
- Provisional: nothing. An audit.
- Two claims were wrong on the first pass and are corrected in place rather than quietly fixed:
  `record_list.dart:921` is a width measurement in the column allocator, not a seventh provenance
  rendering; and the read-only notice appears in only three captures, not six.

## `19317d7` — read-only says read-only, at the sixth site and in a scan

- Decision: **the two-tier pattern is what five sites already agreed on**, so it is written down rather
  than invented: a **titled** `info` `Callout` states the standing of a whole page, an **untitled** one
  states that a single control is unavailable in this build. `catalog-read-only` and
  `staff-directory-read-only` carry titles; the three build-gated notices do not.
  `checkout-configuration-read-only` was a bare `Text` and now matches its four siblings.
- Decision: **photograph the branch as well as fix it.** Three of the six notices appeared in no
  capture, because every capture reaching a build-gated site injects the writer — which is how a bare
  `Text` survived beside four callouts. `16b-checkout-settings-read-only` and
  `18c-manage-catalog-read-only` are those surfaces with no writer. Rule 5 was nearly true here and is
  now true.
- Decision: **the print queue stays silent and stays outside the scan.** It renders nothing at all when
  no retry is injected, which `37c-receipts-waiting-read-only`'s caption records as deliberate. It
  carries no `-read-only` key so the scan does not reach it.
- Decision: **role read-only and build read-only must not be merged.** `staff-directory-read-only`
  fires on `session.canAccess` and names the roles that can act; the other five fire because a build
  has no writer and say "this build". `RBAC_MATRIX.md` has exactly one role-based read-only row, so
  that is the only site allowed to speak in role terms. A component that merged them would claim a
  permission boundary where there is only a missing dependency.
- Provisional: nothing moved. 6 new images, none of the existing 395 changed — which is itself the
  finding: the branch had never been in a picture.

## `ab04fff` — four component-theme text styles had no font family at all

**This is the one the owner should read first.** It is a defect the run found rather than a task the
handover set, and it had been visible in `screenshots/` for nine days.

- Finding: `chipTheme.labelStyle`, `chipTheme.secondaryLabelStyle`,
  `listTileTheme.subtitleTextStyle` and `snackBarTheme.contentTextStyle` were written as
  `TextStyle(color: ...)` inline. A component theme's text style **replaces** the text theme's rather
  than merging onto it, so all four reached the engine with a **null family, null size and null
  weight** — `ThemeData.fontFamily` does not rescue them. `prompt.md` and `lib/theme.dart` both said
  naming the family on every role "is what reaches the component themes below"; it reaches the ones
  that *read* a role, and these four did not.
- Evidence: a probe that resolves each component under the real theme and reads back what the engine
  is handed, plus two pictures. `screenshots/web-full/18-manage-catalog.png` drew the `Categories` row
  as filled bars and the category picker below it as words — raw Material `Chip` versus
  `FilterChipBar`, on one screen. Worse, `02-choose-business` — the second screen in the app — drew
  every membership's *Owner — Accessible* line as an unreadable bar, because it is a `ListTile`
  **subtitle** and `ListTile.title` was always fine.
- Decision: `chipTheme` takes **`label.md`** because that is the role `FilterChipBar` already uses, so
  the app's chip and Material's chip cannot disagree. `listTile`'s subtitle takes **`body.md`**: its
  old 13 is on no scale at all §2.2 has 12 and 14 and nothing between — and 14 is both Material's
  own default role for a subtitle and the role a record subtitle resolves to at compact density.
  `snackBar` takes `body.md` for the same reason.
- Decision: the tripwire **resolves the component rather than reading the theme**, so a correct
  `ChipThemeData` wrapped by something that drops it still fails. `SnackBar` is included because no
  capture drives one, so no picture will ever cover it. `InputDecoration` is asserted although it was
  already correct, because `lib/theme.dart` names it among the components the trap applies to.
- 46 of 401 images moved: the catalog surfaces 17-20c, the business selector 02-04, printer settings
  36a/36b/36d. Nothing else moved.

## `af81a2d` — the last three type literals in the theme

- Finding: the three `TextTheme` slots `lib/theme.dart` sets by hand each carried a size §2.2 does not
  have. `headlineLarge` 40 against a 32 ceiling; `bodyMedium` a bare `fontSize: 16` inheriting
  Material's 20/14 leading where §2.2 states 16 / 24; `labelLarge` 15 / 600 against the design's
  *measured* `.btn-primary` at 14 / 700, which `AppButton` already renders.
- Decision: **`headlineLarge` is repointed rather than deleted**, though it has zero readers and moves
  no pixel. The slot exists whether this app reads it or not, and a slot that says 40 when the
  design's ceiling is 32 is a figure somebody will eventually believe.
- Decision: **`bodyMedium` takes `body.lg`, not `body.md`.** `AppDensity.comfortable` reads
  `AppBodyRole.large`, so 16 was already the right size and only the leading was wrong. Taking
  `body.md` would have shrunk every bare `Text` in the app to 14, which is the compact density's
  answer and not the default one.
- Decision: **a source scan over the file rather than three equality assertions alone**, because the
  fourth slot somebody writes next month would pass all three. It forbids any `fontSize`,
  `fontWeight`, `letterSpacing`, `height` or `wordSpacing` written as a number in `lib/theme.dart`,
  with comments stripped so the file can still explain the figures it removed. After the change there
  are no offenders at all.
- Correction taken during the work: "left without a colour" cannot be asserted as `color == null`,
  because `ThemeData` applies its body and display colours to every slot. The assertion and the
  comment both now state the observable thing — that the label arrives carrying the same ink as the
  text beside it.
- Provisional: nothing invented. **122 of 401 images moved**, all of them surfaces with bare `Text`,
  which is the 1.14px per line the corrected leading buys. `93-status` and `96-record-list-empty` are
  the only component matrices in the set, because a `Callout`'s message and an `EmptyState`'s prose are
  bare `Text`.
- Still open in the same file, deliberately: `inputDecorationTheme`'s `hintStyle` and `labelStyle` are
  colour-only inline styles. The probe shows both resolve correctly, because `InputDecorator` merges
  onto the text theme rather than replacing it, which is why they were never part of this defect.

### What these two commits mean for the handover's own claims

`AUTONOMOUS_HANDOVER.md` §2 says **"The token layer is finished"** and lists typography as landed in
both halves. That was true of `AppTokens` and false of `spiritTheme`: seven of the theme's styles were
not reading it. Both are now, and two scans hold the line. The claim is worth re-reading rather than
re-asserting — the trap section in the same file predicted this exact failure and named three of the
four components it happened to.

## `4b1b0da` — a formatter-only pass, separated on purpose

- Decision: **`dart format` over exactly the fifteen files the next commit touches, as its own
  commit.** Most of `test/` has drifted from the current `dart format` — a whole-tree run rewrites
  about ninety files — so any commit that edits one either carries that file's reflow as noise or
  leaves the file unformatted. The provenance commit is 28 assertions and one component; with the
  reflow folded in it read as six hundred lines.
- Deviation from the charter's letter, and the reason: §4 says format the changed files only, which I
  first read as "run `dart format test/`". That produced 90 files of churn and was reverted. The
  instruction means *do not leave your own new code unformatted*, not *reflow everything the formatter
  now disagrees with*.
- Decision: **the other seventy-five drifted files are left alone.** Reformatting them is a decision
  about the repository rather than about this slice, and not this run's to take.

## `9df70c5` — `ProvenanceLine`, the one component the audit said to build

- Decision: **a widget rather than a scan**, which is the opposite of the read-only call two commits
  earlier and for a stated reason: `caption` with `text.tertiary` appears **29 times** in `lib/` and
  only seven are provenance. The style is not the identifying feature, so a scan over it would have
  flagged 22 correct lines. The concept needed a name.
- Decision: **`ProvenanceLine.styleOf` is public for one real caller and it is not a test.**
  `RecordList`'s narrow-loss allocator *measures* provenance to size the identity column, so the
  allocator and the renderer each named `typography.caption` independently and a repoint of one would
  have allocated the table's columns against a style nothing paints.
- Decision: **density does not move it.** §5.2 states `caption` flat and `AppDensity` swaps only the
  body role, so `96-provenance-comfortable` and `-compact` are two pictures of the same line with its
  neighbours at 16 and 14. A test asserts the invariance, so making provenance density-aware becomes a
  decision rather than a drift.
- Decision: **`stock_adjustment_panel.dart:737` is left as it is.** It folds provenance into a
  `Callout.message` after a newline, two type roles from where §5.2 puts it. Correcting it would be
  recomposing a `Callout` rather than naming a style, and that is a Phase 04 composition call.
- Consequence paid rather than avoided: `RecordItem.provenanceKey` now names the component, so 28
  assertions across eleven files stopped being `Text` casts. They ask `test/support/text.dart`'s
  `textAt` instead; the eleven local `_text` helpers are untouched, because "the `Text` at this key" is
  still what they want everywhere else.
- **0 of 401 existing images moved**, which is the proof the migration is faithful rather than
  approximately faithful.

## `2bc89a6` — the RBAC matrix becomes a test

- Result: **every row agreed.** All 31 named role lists in `lib/` hold exactly what `RBAC_MATRIX.md`
  gives them. Nothing in `lib/` needed changing, which is the outcome the run wanted and not the one
  it was prepared for.
- Decision: **two maps, not one.** One reads the app's constants so a failure names the symbol; the
  other is authored from the matrix so the comparison means something. A single map would assert that
  a list equals itself.
- Decision: **a completeness scan is the assertion worth having.** Everything else checks guards that
  exist; a capability added next month with a list of its own would pass all of them by not appearing,
  and appear in no row of the matrix either.
- Decision: **route offering is deliberately not asserted.** `lib/main.dart` feeds each role-gated
  navigation slot the repository's own constant, twelve of them, so the list the landing route hides
  by and the list the repository refuses by are the **same object**. A test would pass for the wrong
  reason: what makes it safe is that there is one list, not that two agree.
- Two rows gate a **scope** rather than a route, and the matrix now says so: a cashier opens shift
  history and sees their own shifts, with the scope control hidden behind the same predicate the
  repository enforces; a manager reaches the staff directory with `_readOnly` true exactly when
  neither write gateway is present.
- The platform separation is structural: the `superAdmin` claim is read once, reaches the shell as one
  callback, and is consumed only by a routing phase carrying a `PlatformReviewIdentity` rather than a
  `TenantMembership`. No `TenantRole` can reach a platform surface.
- **Not proven, and said so in the test's own header:** the server. `firestore.rules` and the
  callables are the real boundary and `rules-tests/` is where that is shown.

## `eeb7608` — eight dead locations hard rule 3 does not name

- Finding: **`CLAUDE.md` hard rule 3 names two dead directories and there are ten.** `lib/pos/**` and
  `lib/screens/**` are 52 unreachable files and are called out. **Twenty-seven more, 4,627 lines
  across eight more locations, are equally unreachable from `lib/main.dart` and named by nothing.**
- Why it matters to this work specifically, rather than being tidiness: `lib/widgets/` is a **pill**
  component set and decision 19 is that the design has no pills, so a session grepping `pill` finds
  three files that look like the thing it was told does not exist. `lib/constants/colors.dart` and
  `lib/component/colors.dart` are two more colour systems and `constants/sizes.dart` a rival size
  scale — the "competing local design system" the prompt forbids **creating** is already there three
  times over. `lib/model/` holds supplier, customer and invoice models for capabilities the product
  does not have. `lib/config.dart` is 1,178 lines of which **zero** are live code.
- Decision: **record and pin, do not delete.** Deleting 27 files is a substantial unrequested change
  and `lib/pos/**` is explicitly kept for its flow. The test makes the set *stable* instead, so a file
  joining or leaving it is a decision somebody took.
- Decision: **`CLAUDE.md` gains three lines rather than a list**, because that file loads on every turn
  and its own first instruction is to stay short. Editing it at all was a judgement: rule 3 is
  incomplete in a way that costs this exact work, and the tie-breaker prefers the change that leaves
  behaviour untouched.
- Cost paid once: the first version of the closure read only the first URI of each directive and called
  `checkout_print_transport_io.dart` dead. It is reached through `if (dart.library.io)` on a
  continuation line. There is now a test for that specific mistake.

## `246fdfd` — the fixtures, and the words the app must not say

- Result: **the fixtures are clean.** A sweep of `test/` and `tool/` for forbidden branding, invented
  roles, tax, refunds and reorder thresholds found nothing. Screen captures use the seed script's own
  catalog and categories exactly. The component matrices use a second plausible vocabulary of their
  own — *Fresh whole milk 500ml*, *Dairy and chilled* — which is an established convention across
  three files and implies no capability the app lacks.
- Decision: **so the deliverable is keeping them correct, not correcting them.** Wave 1 and Wave 2
  compose the exact screens whose designs carry the invented facts, and a fixture copied out of a
  mockup is the ordinary way one enters an app.
- Decision: **eight tokens, and the list stays short because half the candidates are unscannable.**
  The app already says *"the payment itself is not verified"* and *"the payment is unverified"*, and
  calls *Cancel cash count* a reversal. A scan for `verified payment` or `reversal` would flag four
  sentences that are right, and a tripwire that cries wolf teaches the next person to route around it.
  Those rules stay prose in `DESIGN_RULES.md`.
- Decision: **the ten unreachable locations are out of scope for the scan**, which is the point rather
  than a loophole: `fraud_detection_service.dart` genuinely says `refund` and `Ksh` and none of it
  runs. `eeb7608`'s test is what stops that set growing; this one asks only that nothing live joins it.
- The file excludes itself, which the first run made unmissable: it holds the words as string literals
  rather than comments, so the scan reported eight offences and every one was its own.

---

## Wave 0 is complete, and two of its findings were not on the list

Order-of-work items 1 and 2 are done. The six unaudited components are audited and the two that needed
work have it; the RBAC guards are checked against the matrix and every row agreed; the fixtures are
checked and clean. **2,314 tests pass, up from 2,249.** 405 screenshots, up from 361.

**What was not on the list, and is the part worth the owner's attention:** the handover's §2 says *"The
token layer is finished"* and it was not. Seven of `spiritTheme`'s text styles were not reading
`AppTokens` — four with no font family at all, three with type sizes §2.2 does not have — and the
consequence was visible in `screenshots/` for nine days, most legibly on `02-choose-business`, where
every membership's role line was an unreadable bar. The trap section of the same handover predicted
that exact failure and named three of the four components it happened to. Both halves are fixed and
two scans hold the line.

The second was found while checking fixtures: **27 files in `lib/` that nothing runs and nothing
names**, including a pill component set and two rival colour systems. Recorded, pinned, not deleted.

## `1687709` and `06a24f9` — Wave 0 recorded, Phases 01 and 02 checked

- Decision: **the handover's §2 is struck through rather than rewritten.** "The token layer is
  finished" was true of `lib/ui/tokens.dart` and false of `lib/theme.dart`, and the reason it was wrong
  is more useful to the next reader than a corrected sentence would be — it is §8's own trap, in
  three of the five components §8 names.
- Decision: **Phases 01 and 02 needed no Dart change, and the audit is the deliverable.** Every
  structural acceptance criterion of both was already met, and four of the eight became assertions
  earlier in this run. Adding a ninth test that re-asserted one of them through a different route would
  be coverage theatre, and the audit says so rather than padding.
- Decision: **ST-028's refusal sentence is not adopted.** The design says *"Check the email address and
  password for this account."*; the app says *"That email address and password do not match an
  account. Check both and try again."*, and says something different for six other codes. Evidence:
  `sign_in.dart:183-233`. The app's states what happened before what to do, which is §8's rule, and
  collapsing seven answers into one would lose a distinction the code already makes. Copy, not pixels;
  no layout depends on it.
- Decision: **ST-028's mobile caps-lock hint is recorded as design debt, not implemented.** The app
  answers that need with the sign-in keypad's own caps state, and `01e-sign-in-caps-locked` is `web`
  only because the keypad does not appear below 1264. A phone hint would mean detecting a *physical*
  keyboard's lock state and rendering new state from it — new logic, which hard rule 1 forbids in a
  visual change. If the product wants it, it is a behaviour slice with its own authorisation.
- Finding, and the clearest case in the repository of *fidelity is not the goal where the design is
  wrong*: **the app is already right where both Phase 02 artifacts are wrong.** They show `Own shift
  panel` as a navigation destination and the app has no such route — the shift is a banner, and
  §4.4's "never a destination" is asserted. ST-033 states the local evidence as `KES 4,200.00
  confirmed` and the app states it as **counts**, in exactly the five states the handoff says the served
  design does not show. Implementing ST-033 faithfully would replace a correct readout with an
  incorrect one.
- Provisional, named rather than implied: **nothing in either phase is pixel-approved.** Phase 01 is
  frozen at `PARTIAL / HOLD FOR REVIEW`; ST-032 and ST-033 are `NORMALIZED / RENDER REVIEW`, which
  means corrected and never visually confirmed.

---

# Run summary — what is done, what is not, and what to read

**Fourteen commits, `7509dcc` to `06a24f9`.** Branch `stitch-wave-0-tokens`, nothing pushed, no PR.
**2,314 tests pass** (from 2,249) and the harness writes **405 images** (from 361).

## Implementation-complete against the §7 bars

1. **Order-of-work item 1 — the harness width regions.** Two viewports rather than the one asked
   for, plus a tripwire that derives the regions from `AppLayout` and fails naming the interval.
2. **Order-of-work item 2 — Wave 0's remainder.** The six components audited (four needed nothing),
   read-only corrected and photographed, `ProvenanceLine` built and seven renderings migrated with
   **zero pixels moved**, the RBAC guards asserted against the matrix on all 31 role lists, the fixtures
   checked and scanned.
3. **Order-of-work item 3 — Phases 01 and 02, structurally.** Both contracts hold; the audit records
   the two divergences kept and the two places the app is right where the design is wrong.

**Plus two defects found rather than assigned**, both in the token layer the handover said was
finished: four component-theme text styles reaching the engine with **no font family at all**, and
three `TextTheme` slots carrying type sizes §2.2 does not have.

## Not started

**Waves 1, 2 and 3 — Phases 03 to 10.** No screen has been recomposed to a Stitch layout by this run
or any before it. What ships is the app's existing layout wearing the new tokens, now with every text
style actually reading them.

## Every still-provisional pixel

Nothing this run produced is provisional: the 44 new images are the app's current layout at widths or
in branches nothing had rendered, and the 168 that moved are two font corrections whose before-pictures
were unreadable bars. **What remains provisional is everything the run did not touch**, unchanged from
the handover's own list: Phase 04 mobile, Phase 08 completion matrices, Phase 02 checkout evidence, the
two Phase 06 shift cards, and every `NORMALIZED / REVIEW` screen. Phase 01 gains one item — ST-028's
mobile caps-lock hint, recorded above.

## What the tests prove, and what still needs a device

They prove the raster, the token wiring and the authorisation lists. **No screen overflows or truncates**
at any of the five width regions, `spiritTheme` hands every restyled Material component one of the
app's two families, and all 31 role lists match `RBAC_MATRIX.md`.

They do not prove the app runs — the web target still does not, for the two pre-existing bootstrap
bugs, deliberately unfixed. They cannot show motion, and nothing here touches motion. And they say
nothing about the server: `firestore.rules` and the callables are the real authorisation boundary and
`rules-tests/` is where that is shown, which the RBAC test's own header states so a green run is not
read as more than it is.

## The commits, in order

| | |
|---|---|
| `7509dcc` | Photograph the two width regions no viewport was in |
| `b440c71` | Record the width-region chunk, and close the gap claims it falsified |
| `a77e95c` | Audit the six unaudited components before building any of them |
| `19317d7` | Say read-only the way the other five sites say it |
| `ab04fff` | Give a chip, a subtitle and a snack bar the face the design chose |
| `af81a2d` | Take the last three type literals out of the theme |
| `b2f556e` | Log the four Wave 0 component commits while they are fresh |
| `4b1b0da` | Run dart format over the files the next commit touches |
| `9df70c5` | Give the provenance row a name, since a scan could not give it a rule |
| `2bc89a6` | Make the RBAC matrix a test instead of a snapshot |
| `eeb7608` | Name the eight dead locations hard rule 3 does not |
| `246fdfd` | Scan the fixtures for facts the product does not have |
| `1687709` | Record Wave 0 as complete, and the claim it falsified |
| `06a24f9` | Check Phases 01 and 02 structurally, and change nothing |

## The two things to read first

1. **`ab04fff` and `af81a2d`.** The token layer was not finished, and the evidence had been sitting in
   `screenshots/` for nine days: `02-choose-business` drew every membership's role line as an
   unreadable bar. Seven of `spiritTheme`'s text styles were not reading `AppTokens`.
2. **`a77e95c`.** Four of Wave 0's six named components needed nothing built. The most useful sentence
   in that audit is a negative one, and the alternative was four competing systems next to working
   ones.

---

# Phase 03 — the sale path, composed

**Seven commits, `107cdea` to `82f2f50`**, on the same branch. Nothing pushed, no PR. This is the
first chunk of the run that changes what a screen looks like; everything before it was tokens,
components and contracts.

## `107cdea` and `a5b6ca6` — the formatter, alone, twice

- Decision: **two `dart format` commits of their own, before the slices that need them.** The
  formatter rewrites seventy-three lines of `test/checkout/checkout_cart_panel_test.dart` and twenty
  of `tool/screenshots/fakes.dart` that have nothing to do with Phase 03, because most of `test/` and
  `tool/` has drifted from the current formatter. `4b1b0da` set this precedent for the Wave 0
  components and the handover's §4 names the whole-tree run as a mistake this run already made once.

## `e51b8bc` — a colour role for money

- Decision: **`AppTextRoles.money` exists, and reading it is a per-surface choice.** This is the half
  of `OPEN_QUESTIONS.md` question 22 that was left open on purpose. Evidence: 65 of the places
  `currency-kes` appears in the export also carry `text-data-mono`, and both Phase 03 screens set
  every price that way. `OPEN_QUESTIONS.md` **decision 23** records the answer, the four figures it
  lands on, and the one it does not.
- Decision: **the token is not permission to sweep.** Every price outside the till stays
  `numericBody`. The role's own doc comment says so, because a role in the token layer is the exact
  thing a later phase will read as a licence.
- Both palettes carry the same hex — `currency-kes` is `_Primitive.mint400` — so this is the one row
  a repoint left alone. It clears AA on all four grounds, and a test says so: a figure a cashier reads
  aloud to a customer is not exempt from §9 for being a number.

## `047eb6e` — the browse screen

- Decision: **the products pane is a fixed head over a scrolling grid.** Both served designs draw it
  that way, and the reason is not tidiness: a cashier who scrolled to the twentieth product lost the
  search field off the top of the screen, and typing a name is the fastest way to reach a product.
- Decision: **two tiles, chosen by §4.1's band, because the two designs are two tiles.** ST-035's till
  card is dense text with the scanner's code on it and no picture at all; the recovered browse render
  leads with a picture band and carries a count of what is already rung up. The badge is compact-only:
  on a till screen the cart pane states that fact in full.
- Decision: **the grid extent moves 230 → 260.** It is the number that gives this app the column
  counts both designs ask for at every band — two on a phone and a tablet, three at 1024, four at a
  till — from one value, with no second breakpoint deciding columns. At 230 the 1440 till took five
  and the price ellipsised at 1024.
- Deviation, deliberate: **`-3 in stock` rather than `Out of stock`.** Both designs write the state;
  this writes the figure. Firestore Rules permit signed stock deliberately, the cached count in this
  app really can be negative, and `0 in stock` says what the phrase says while `-3 in stock` says
  something it cannot.
- Deviation, deliberate: **the price and the cached figure take two lines where ST-035 puts them on
  one.** That row works at its ten-pixel stock label; §2.1 makes `caption` at twelve the floor for
  anything a person is expected to read, and this app has no role below it. The first attempt drew
  `KES 145.…` at 1024, and an ellipsised price on a till is the one thing this screen may not do.
- Finding, and it had been true since before this run: **the tiles never filled their grid cells.**
  `PressSurface.fillWidth`/`fillHeight` offer the whole cell but pass *loose* constraints on, so a
  `MainAxisSize.min` column shrink-wrapped its own text and sat centred — four cards of four widths
  with ragged gutters — and the `Spacer` in the old tile was inert for the same reason. Both bodies
  are `max` and `stretch` now.
- Provisional: nothing here is pixel-approved. The recovered browse render is `RECOVERED` and was
  never visually confirmed against an implementation.

## `777db74` — the cart

- Decision: **head, scrolling middle, foot.** The cart pane was one `ListView`, so on a phone a
  cashier with six items scrolled past all six to reach the save and the total went off the top while
  they did. Both designs draw the same three regions.
- Decision: **the clear moves into the head.** ST-035's arrangement, and it finishes §2.1's own worked
  example: the destructive action and the primary one are now at opposite ends of the pane rather than
  adjacent, so a thumb reaching for the save cannot land on the clear.
- Decision: **the total is a line, not a `StatTile`.** Both designs put the word and the figure at the
  ends of one line, and a card inside a bordered footer is a box in a box. It keeps `numeric.hero` and
  its roll — see decision 23 for why the face does not move where the colour does.
- Decision: **the three regions are divided by hairlines, not by ST-035's surface step.** The same
  pane renders inside `AppSheet`, whose ground is §2.1's `overlay` — a step *above* `raised` — so a
  `raised` header inside one would draw recessed. The step is added back for the wide layout only, in
  the next commit, as an explicit argument.
- Finding, paid for in layout throws: **a labelled removal cannot share a row with the stepper.** A
  `QuantityStepper` is 188 wide at its widest bound, a labelled button about 150, and a 411 phone
  leaves 347 inside the card. Splitting them into ST-036's own three rows is the design's layout and
  not a workaround for one.
- **The first of the two ST-036 defects needed no code at all.** The handoff says its save refusal
  invents a cause and prescribes *"This sale could not be saved on this device. Try again, and ask for
  help if it keeps happening."* — which is verbatim what `checkout_refusal.dart:202` has said all
  along, as the fallback for any code this build does not model. `15c-sale-refused` photographs it.
- **The second needed none either.** ST-036 renders a `Sale / Orders / History / Sync` bottom bar; the
  till has no bottom navigation of any kind and never has. Nothing to delete. Both corrections are
  therefore *the app is already right where the design is wrong*, which is the same shape the Phase 02
  audit found twice.

## `1fef562` — the two-region till

- Decision: **depth separates the panes, and it is wide-only.** ST-035 gives the cart its own ground
  with the header and footer a step up and the list of lines a step down. In this app's roles that is
  the page ground, `raised` and `sunken`. `_cartPane` takes it as an argument rather than inferring it
  from whether a scroll controller arrived, because the sheet must not get it.
- Decision: **the boundary between panes is `border.strong`.** It was `border.subtle` — the weight
  this app uses between two rows of one list — and this is the boundary between the catalog and the
  sale. §9's 3:1 row, and the argument `_CartBar` already makes for its own top edge.
- **The 3-column desktop till stays deferred**, per decision 21. Not reopened, not built.
- Unchanged and still asserted: the cart pane is `AppLayout.salePane`, two panes begin at 768, and the
  test pinning the tightest case — 420 of cart leaving the products 347 — passes.

## `82f2f50` — where the receipt went

- Decision, and it closes a gap the brief names: **the till says where to find a receipt that did not
  print.** Phase 03's brief asks for "route to receipts waiting" and `OPEN_QUESTIONS.md`'s Phase 03
  item 4 records the product decision; the till said the sale was durable and the printer had failed,
  and stopped there.
- Decision: **the sentence belongs to this surface, not to the shared copy.**
  `checkout_print_failures.dart` is the one place in the printing slice that holds English and the
  print queue panel reads the same sentences — telling somebody already standing in that queue to open
  it would be nonsense.
- It **names a destination and does not become one.** A button here would be a routing condition, and
  hard rule 1 keeps those out of a visual change.

## Two figures in the handover that were wrong, and one that was right

- `PHASE_03_HANDOVER.md` says `checkout_cart_panel.dart` is **2,941 lines**. It was **1,779** at
  `6181ff2` and is **2,289** now. The conclusion it was drawn for still holds — this is the most
  behaviour-coupled file on the sale path and three slices was the right split — but the measurement
  is not, and a reader planning against it should re-measure.
- The same file says the two ST-036 corrections are *"not fidelity targets"* and gives exact
  replacement copy for one of them. Both were already satisfied; see `777db74` above.
- **`test/checkout/` really is 10,981 lines and all of it really does pass unchanged.** That figure was
  right, and it is the one the phase's safety argument rests on.

## Testing, and what it proves

- **2,315 tests pass**, from 2,314. One test was added — the money role's value and its contrast on
  all four grounds — and it is the §9 case, which is pass/fail rather than optional.
- **Three copy assertions changed and none of them is behaviour.** The tile's price left the stock
  sentence (`KES 5.00, -3 in stock` → `-3 in stock` plus a keyed price), and the compact bar's total
  left the word (`Total: KES 14.00` → a label over `KES 14.00`). Both are the same cause: money takes
  a role of its own now, and one `Text` cannot carry two roles.
- **No behaviour test moved.** `test/checkout/` is 10,981 lines and every line of it passes unchanged,
  which is the signal the handover asked for: a composition change that broke one would have meant a
  state transition changed.
- **The harness writes 413 images, from 405.** Eight new, **seventeen moved, none removed** — and every
  one of the seventeen is a `14`, `15` or `15b` till capture. Nothing outside the sale path moved,
  which is the measurement that says the change is contained.
- New captures: `14b-new-sale-browsing-with-a-cart` at the two compact widths, and `15c-sale-refused`.
  The second is the state hard rule 5 was missing — a sale that was *not* written existed only in the
  widget tests, and it is the branch ST-036 gets wrong.

## The commits, in order

| | |
|---|---|
| `107cdea` | Run dart format over the till's test file before Phase 03 touches it |
| `e51b8bc` | Give money a colour role, because the till is where a figure is read aloud |
| `047eb6e` | Compose the browse screen the way a cashier uses it |
| `a5b6ca6` | Run dart format over the harness fakes before Phase 03 touches them |
| `777db74` | Put the cart's answer where a cashier can reach it |
| `1fef562` | Make the till's two regions read as two regions |
| `82f2f50` | Tell the cashier where the receipt that did not print went |

## What still needs a device

- **The screenshots prove the raster and nothing else.** They do not prove the app runs, and they
  cannot show motion at all.
- **Nothing in this phase touched the save or tender timing**, so the sale path's motion rule is where
  it was: the sale is written first and the roll plays over committed state, which
  `RollingNumber`'s own note and `_save`'s ordering both still say. That is *unchanged*, not
  *verified* — confirming it takes a device with the performance overlay on.
- The web target still does not run, for the two pre-existing bootstrap bugs. Deliberately unfixed.

## Every pixel that is still provisional

- **All of Phase 03.** ST-035 is `CANONICAL CANDIDATE / VISUAL REVIEWED` and this implementation of it
  has never been compared to it by a person. ST-036 is `NORMALIZED / RENDER REVIEW` — corrected and
  never visually confirmed — and the mobile browse render is recovered rather than approved.
- The tender chooser is still a `FilterChipBar` where both designs draw a three-up segmented control.
  Kept deliberately: it is the app's existing single-selection component, it carries its selected state
  with a glyph as well as a colour, and §5.2 specifies no segmented control at all — inventing one is
  the thing `ConfirmDialog` and `EmptyState` were both left alone for.
- The two empty states in the grid stay prose rather than becoming `EmptyState`, which is the decision
  step 9 already took for screen 08 and this phase did not reopen.

# Phase 04 — catalog and stock, photographed and corrected

**Four commits, `f8a4095` to `1efe758`**, on the same branch. Nothing pushed, no PR. Three of the
brief's four slices are done; the fourth is recorded as a derivation and one route inside it is
deliberately not started.

## The one sentence worth reading first

**Slice 1 changed no Dart and found the phase's only real defect.** Photographing the thirteen routes
at the two widths nobody had photographed, and at the two roles nobody had rendered, is what turned up
a red `Out of stock` badge on a cashier's read-only catalog — the exact thing acceptance criterion 2
exists to catch. The handover predicted slice 1 would be the cheapest way to find out how much of
Phase 04 was already right; it was, and the answer was "most of it, except this".

## `f8a4095` — photograph the width and the roles

- Decision: **`responsiveViewports` on all thirteen catalog and stock captures.** They rendered at 1440
  and 411 only, so `twoColumnCards` — the middle of `RecordList.formFor`'s three forms, and the one
  ST-039 section 8 draws an 834px specimen of — appeared in no picture of any real route. The
  component's own matrix covered it (`tablet/96-record-list*`); its use on a page of six columns and
  two actions did not.
- Decision: **three new role captures**, because the branch this phase is *about* had never been
  rendered. `17b-read-only-catalog-cashier`, `18d-manage-catalog-manager`,
  `19b-correct-a-product-manager`. Everything from `17` to `20c` ran under `seedSession()`, which is
  owner; `21`–`24` run as manager but the stock routes' role lists do not differ.
- **No route overflows or truncates at 834 or 1024.** That was the finding slice 1 was told to look
  for and it is a negative one: 108 capture tests pass, and an overflow throws.
- **The manager's correction form states its own narrowing in a notice that is very nearly ST-039's own
  sentence** — `catalog-management-edit-money-hidden`, "Only an owner or administrator may change what
  this product is priced at or what it costs, so neither is offered here" — and it had never been
  rasterised. Neither had the list notice, "Only an owner or administrator may retire a product."
- **The cashier's catalog withholds all three stock routes and every row action**, from the same build
  that offers them to an owner. That is the screen deciding, which is what makes the capture evidence.
- **The one open fixture question in the handover is closed.** `23-stock-movements` contains both
  evidenced examples the handoff names: the `+24` manual adjustment with reason `Morning delivery
  received`, and the `-2` sale with source `co-1`, side by side in one picture.
- 71 new images, **0 moved, 0 removed** — the measurement that says a no-Dart slice only added coverage.

## `06472ad` — the badge that told a cashier not to sell

- **The defect, and it is criterion 2's exactly.** `tenantProductStanding` gave every product at or
  below zero a `problem` badge reading `Out of stock`, on both catalog surfaces, with nothing on either
  page to qualify it. `Milk 500ml` at `-3` and `Water 1L` at `0` both wore it. Recorded stock may be
  negative and never blocks a sale — Phase 04 item 4, `audits/phase-04.md`, and Phase 03's own refusal
  of these two words at `checkout_cart_panel.dart:1670`.
- Decision: **the label is the quantity and the page carries ST-039's sentence.** `OPEN_QUESTIONS.md`
  **decision 24** has the argument, the reason `problem` is kept, and the one thing it does not settle.
- Decision: **the sentence is a page line, not a per-row warning**, where ST-039 draws it inline. The
  till's precedent, and `RecordItem` has no warning slot that is not `provenance` — which this phase's
  own handover forbids quietening.
- **Two copy assertions moved and neither is behaviour.** A third test broke on *layout*: the caption
  line pushed `View stock` to y=640 on an 800x600 surface, and `tap` warns rather than fails when it
  misses, so what failed was the assertion after it. It scrolls first now, the way its own sibling in
  the same file already did.
- 49 images moved, 0 new, 0 removed, **all 49 screens 17 to 19**. The bulk and stock routes did not
  move, which is what says the change is contained.
- **Deviation from the handover's formatter convention, stated plainly.** `dart format` on the two
  touched test files reflowed ~200 lines that have nothing to do with this change, and the handover's
  instruction was to commit that reflow alone first. This commit carries both. The split was attempted
  and the `git reset` it needed was declined, so it stands as one commit: read its two test files
  knowing most of their diff is reflow.

## `0c18437` — the token debt, counted and cleared

- **97 literal spacings in `lib/inventory/`, against two in `lib/ui/`.** All 97 gone; 94 of them are
  the same value the token names and moved no pixel, which is the point.
- Decision: **three off-scale gaps take `s24`.** `catalog_management_panel.dart` separated its four
  section headings at two values — one 24 and three 28 — and 28 is not on `AppSpacing.all` at all, which
  is documented as *every* permitted value. `s24` is the value already doing that job in the same file
  and in `reconciliation_status_panel.dart` one directory over.
- Two feed panels had expression-bodied builds with no `tokens` in scope and now read it as every other
  panel does. One `const Padding` became a `Padding` around a `const Text`: a token is not a
  compile-time constant.
- **40 of the 484 images moved and all 40 are the six management-catalog screens** — the one file the
  three off-scale gaps were in. Nothing else in the app moved a pixel, which is the measurement that
  says the other 94 repoints were value for value.
- **Corrected in place, per the handover's own instruction to re-measure.** The handover says
  `lib/checkout/` holds seven literals and *"all seven of those are in
  `checkout_configuration_panel.dart`"*. The count is right and the attribution is not: six are there
  and the seventh is `checkout_evidence.dart:311`, which is Phase 02's checkout-evidence surface rather
  than screen 16's. It is a real hard-rule-2 site with no phase claiming it.

## `1efe758` — slice 3, and the answer was to keep all four

- **Finding: none of the four raw Material sites should change.** Every one is themed and reads the
  token layer — `chipTheme`, `checkboxTheme`, `cardTheme`, and `SegmentedButton` reached three ways at
  `theme.dart:257` and `:322`. `lib/theme.dart`'s `chipTheme` note names the catalog's raw category
  list as the site it was written for, so the handover's "none; this one is bare" is true of the call
  site and not of the repository. §5.2 specifies neither a segmented control nor a checkbox, so
  building one is a component with a full state matrix — which is what Phase 03 declined for the tender
  chooser.
- **The one thing that needed measuring was §9, and the guess was wrong.** The direction control looked
  like a 48dp defect: Material draws a segmented button at 40 by default and `lib/theme.dart` has no
  `segmentedButtonTheme`, so nothing in the token layer was holding it up. It draws at **48.0**.
- Decision: **keep the measurement as an assertion.** `test/ui/tokens_test.dart` asserts §9's floor for
  the three button themes that have a `minimumSize` to read and is silent on every widget family that
  does not, so nothing would notice a later `segmentedButtonTheme` arriving under the floor. One test,
  and §9 is pass/fail rather than optional — the same justification Phase 03 used for its only test.

## Slice 4 — derived, recorded, and one route not started

- `OPEN_QUESTIONS.md` **decision 25**: Phase 04's mobile records are `RecordList`'s responsive contract,
  recorded as a derivation because ST-040 is 9,218 bytes and one section of nine. The derivation is
  ST-039's own section 8 rendered through the contract that specimen draws, and it is now photographed
  at all four widths rather than asserted.
- **Screen 20, `20b` and `20c` were not migrated and are the phase's unfinished route.** Their rows are
  `CheckboxListTile`s with a bullet-separated subtitle — the pre-migration shape §5.2 replaces — and the
  report rows below them are raw `Card`s. The note already at `bulk_catalog_panel.dart` reaches the same
  conclusion: this is step 6's twelve-screen migration, not a Phase 04 slice. Cut deliberately, per §7.

## The four ST-039 defects — all four, the app was already right

Checked against the app at `7d54e28`, which is what the handover asked rather than taken from its table.

| ST-039 defect | The app |
|---|---|
| Collapses adjustments, movements and ledger into one table | Three separate routes and three panels |
| Says `Before/After` | `stockBeforeAndAfterLabel = 'Before and after'`, one constant, two call sites |
| Lacks exact provenance | Both record builders set `provenance:` with actor and recorded time |
| Supplier-oriented reason placeholder | The reason field has no placeholder at all |

**Four for four, and the same shape Phases 02 and 03 found twice each: the app is right where the
design is wrong.** No code was written for any of them.

## Testing, and what it proves

- **2,316 tests pass**, from 2,315. One test added, and it is the §9 case.
- **No behaviour test moved.** Three assertions changed: two are copy that followed the badge label, and
  one is a `tap` that now scrolls first because the page grew by a caption line. `test/inventory/` is
  9,345 lines and all 272 of its tests pass unchanged.
- **The harness writes 484 images, from 413.** 71 new across four commits, 89 moved, 0 removed — and
  every moved image is a screen between 17 and 19, which is what says the two Dart changes were
  contained to the surfaces they were about.
- **158 screens in the index, from 155.**

## What still needs a device

- **The screenshots prove the raster and nothing else.** They do not prove the app runs and cannot show
  motion at all.
- **Nothing in this phase touched motion**, so the sale path's rule is where Phase 03 left it. That is
  *unchanged*, not *verified*.
- The catalog's new caption line and the relabelled badge have never been read on a physical screen. The
  badge is a `StatusBadge` inside a `RecordList` row at three forms; the raster is right at all four
  widths and a device is what would show whether the sentence reads as standing context or as noise.
- The web target still does not run, for the two pre-existing bootstrap bugs. Deliberately unfixed.

## Every pixel that is still provisional

- **All of Phase 04.** ST-039 is `NORMALIZED / RENDER REVIEW` *and* the export is its pre-correction
  render, so no part of this implementation has been compared against an approved artifact by a person.
  ST-040 does not meaningfully exist. Nothing here is pixel-approved and none of it should be read as
  approved.
- **Decision 24's badge wording is this run's, not the design's.** ST-039 shows `Below zero. A sale is
  never blocked by a stock count.` inline under a product name; this is the quantity in a badge plus the
  sentence once per page. The clause is the design's and the arrangement is not.
- Screens 20, 20b and 20c keep their pre-migration rows.
- Whether zero should carry a softer status than below-zero is open — decision 24 says so.

## The commits, in order

| | |
|---|---|
| `f8a4095` | Photograph the catalog at the width and the roles it changes shape at |
| `06472ad` | Stop the catalog telling a cashier a product cannot be sold |
| `0c18437` | Put lib/inventory's spacing back on the token scale |
| `1efe758` | Measure the 48dp floor on the Material controls nothing was asserting |

# Phase 07 and the owner's three shapes — 2026-08-23

**Thirteen commits, `fd247c4` to `d0f54fa`.** Phase 07's evidence and token work are done and its
composition slice is not started. Three product-owner directions landed across the whole app, and
hard rule 2's spacing half is now discharged everywhere and held by a tripwire.

## Phase 07 — staff and access

### `8c38be0` — the five forms nothing had photographed

- **The gap the handover measured was right and was the whole phase.** `tenant_staff_directory.dart`
  offers six actions and one of them — `Correct` — had a capture. The family had three images in
  total, against a brief asking for pending, active, disabled, expired/invalid, busy, validation and
  failure states, and ST-055's fourth section draws a consequence dialog for every one of the five
  with none.
- **The behaviour was never the thin part.** Eleven test files, 5,501 lines, 122 tests, all passing.
  What was missing was the raster, and with it any way to notice what the forms said.
- Decision: **Faith Njeri is the subject of three of the five.** Resend, cancel and replace-email all
  require a pending membership with an unaccepted invitation and she is the one seeded member who has
  one. The status change targets **Brian Kimani rather than Peter Otieno**, whom ST-055 draws: Peter
  is `adminUid` and therefore the acting session, and a person deactivating themselves is not the
  picture that state is for.
- **Finding, and it is why photographing one action is not photographing a route:** §4.3 folds a row's
  actions into an overflow menu below 1024. `RecordActionSet.inlineCountFor` draws **no** action
  inline on stacked cards once a record carries more than three, and three on two-column cards — so a
  pending membership's four actions are all behind the menu at 411 and its fourth is behind it at 834.
  `13b` never had to deal with that because an accepted membership carries two. The first attempt at
  these captures failed at exactly those two widths.
- No form overflows or truncates at any of the four widths. **52 new, 0 removed, 3 moved** — all three
  `13b`, which now settles and frames the record through the shared helper rather than photographing
  wherever the tap left the page.

### `96c7401` — the verb that changed halfway

- **The defect, found by photographing it.** The row action says `Correct` and the form it opened said
  `Edit`. §8 rule 4 is the rule, in as many words: *"The verb persists. The button says Correct, the
  dialog says Correct."* It was the only one of the route's five forms that broke it — the other four
  already carry the verb of the action that opened them.
- ST-055 writes the heading `Correct Staff: {name}`, so the design and the rule agree and the words
  are the design's rather than a third phrasing invented to settle it.
- **It had been in every `13b` image ever taken.** Nothing beside it to compare against until the
  other five forms had pictures, four of which say it correctly. That is twice in two phases that
  adding coverage rather than reading code is what surfaced the defect.
- The confirmation is left alone: §8 rule 4's third clause asks for `Corrected`, ST-055 draws
  `Staff details updated.`, the app already says exactly that, and `DESIGN.md` is implementation
  history rather than visual authority for a Stitch composition.

### `158f969` — the staff token debt, which moved nothing

39 literal spacings across nine files and **every one already a value `AppSpacing` names**, so this
moved zero pixels. Phase 04's equivalent had three off-scale values and moved 40 images. Hard rule 2
is about where a widget reads its numbers from, not about what the numbers are.

### `1ee6302` — the midnight-UTC trap, written down

- **`seedBusinessDate` and `seedTimestamp` read the wall clock**, deliberately: the daily summary and
  reconciliation compute the same string from `DateTime.now()` and read by exact path, so a hardcoded
  fixture date renders them permanently empty.
- **What nobody had written down is the consequence for how this project proves a change is
  contained.** "N images moved" is the evidence and it is only valid inside one UTC day. This session
  crossed midnight between a baseline hash and a re-measure, and a nine-file spacing repoint appeared
  to move 36 reporting, shift, returns and receipt images it had not touched. Against a same-day
  baseline it moved **zero**. It cost a bisect; the note now says what the tell is — the moved set is
  all date-bearing screens and contains nothing you edited — and to re-baseline rather than hunt your
  own diff.

### What Phase 07 did not do

**The composition slice is not started.** Slices 1 and 2 are done and slice 3 — the pass against
ST-055 and ST-056 — is not. What the new captures show is that the app already matches ST-055 closely:
every form names its person and consequence, the manager's read-only reading carries no write
affordance at any width, and the tablet transformation holds. Two divergences are recorded and neither
is a defect on its face: the app draws a four-tile stat strip ST-055 does not have, and it splits
ST-055's combined `STATUS + MEMBERSHIP` column into a badge and an attribute.

**One finding is left open rather than fixed, because the fix is a component change.** On stacked
cards a record with more than three actions draws **no** label at all — just an unlabelled `⋮`. The
`_staffActions` comment says these were once "a 40dp `IconButton` with the member's name in a tooltip
and no visible label" and that §5.2's `ActionSet` fixed it; at the compact band it is still an
icon-only control, and `13f-cancel-an-invitation @ mobile` is the picture. Fixing it means changing
`RecordList`, which every record surface in the app reads, so it is a Wave 3 item rather than a
Phase 07 slice.

---

## The product owner's three shapes — `OPEN_QUESTIONS.md` decision 26

**These are owner directions, not readings of the design, and they are recorded that way.** Two of
them reverse a decision that argued from evidence. A shape is the owner's to choose; what the record
owes a later reader is the evidence it overrides, so nobody re-derives the old answer and files a
regression.

### `1a41c9a` and `3a4f2c2` — the pill is back

- On `radius.pill`: `AppButton`, `FilterChipBar`'s chip, the `AppTextField` well, the three Material
  button themes, `chipTheme`, and the theme's `InputDecoration` border.
- **Deliberately not:** cards, rows, dialogs, sheets, banners, stat tiles, the snack bar and
  `StatusBadge`. A badge is read rather than pressed and was never a pill; and Flutter clamps a radius
  to half the shorter side, so 999 on a card draws a lozenge rather than a pill.
- **The token values did not move at all** — `sm` 2, `md` 8, `lg` 12, `pill` 999. Only which component
  reads which role, which is the line `AppRadii`'s scale test and the component tests already divide.
- For the input well this is the third move of one value: v0.4 made it a pill at the owner's request,
  2026-08-22 took it back to the design's corner, this restores it.
- **417 of 536 images moved**, the correct blast radius for a token change reaching every button, chip
  and field. Six assertions moved with it, each keeping the evidence it used to assert beside the
  override.
- **Recorded honestly:** `1a41c9a` was meant to be a formatter reflow alone and `git add -A` swept the
  pill change in with it. The message was corrected to match the content rather than the history
  rewritten; about 90 of its test-file lines are reflow.

### `726e185` — dropdowns where a surface has more than one filter

- Sales totals is the surface the direction is about and the only one with three filters open at once.
  As chip strips their height **grew with the business** — one chip per colleague and one per category
  — so twelve staff and nine categories pushed the figures the page exists for off the bottom of a
  phone. The three figures now sit on the first screen.
- **A single filter stays a chip strip**, which is the other half of the rule: one strip shows its
  options without a tap. The till's category chooser and the anomalies filter keep theirs.
- `AppSelectItem` gained a `key`, because `FilterChipBar` keys every option and `DropdownMenuItem` had
  none — moving a filter between them would otherwise silently drop every option-level contract the
  surface had. All nine option keys are unchanged.
- **Two test mechanics were worth getting right rather than working around.** Choosing an option taps
  the option's `Text`, not its `DropdownMenuItem`: a closed `DropdownButton` keeps an offstage copy of
  the *selected* item, so `.last` on the key sometimes picked the button's copy over the menu's, and
  tapping an offstage widget warns instead of failing — which left four tests asserting against a
  filter nobody had changed. `hitTestable()` is no help; the menu item is not its own hit target. And
  label assertions now read `AppSelect.items` rather than the rendering, the reverse of what that file
  used to do and for the same underlying reason.
- **One cost, stated rather than discovered later:** a dropdown's options are not in a screenshot. A
  closed dropdown builds only the selected option, so hard rule 5's coverage is weaker here than for
  the chip strip it replaced, where every option was always rendered.

### `1a41c9a` — asterisks in the password field

The field carried no placeholder from step 9 until now, on reasoning that was right about the string it
deleted (`Enter Password` restates the label) and wrong to conclude the field could carry nothing.
`********` is the permitted kind: it is what the box looks like once somebody types in it.
`AppTextField` gained `obscuringCharacter`, defaulting to `*` for every obscured field — the two
travel together because a placeholder showing asterisks over a field that types bullets is a box that
appears to change character set the moment it is touched.

---

## `4ba7243` and `d0f54fa` — hard rule 2's spacing half, finished and held

- **The last 92 literals across 41 files.** After Phases 03, 04 and 07 the debt was the surfaces no
  phase had reached: the platform-admin family, the sales, returns, shift and audit histories, the
  routing shell, and eight `lib/ui/` components. There are now **none** outside the token layer.
- Three decisions: `SizedBox(height: 10)` takes `s8` (groups the error with its field);
  `cardTheme`'s `vertical: 6` takes `s4` (equidistant from 4 and 8, and the margin doubles between two
  cards); and `EdgeInsets.fromLTRB(20, 20, 20, 0)`'s zero **stays a literal zero**, because an inset of
  nothing is not a spacing and `AppSpacing` rightly has no token for it.
- Three deliberate non-moves: `lib/ui/tokens.dart` keeps its own literals because `AppDensity`'s
  `rowPadding` values are the layer defining itself and are `const`; `lib/theme.dart` reads a new
  `_spacing` off the registered palette rather than a `tokens` that has no meaning at top level; and
  **comment lines are untouched throughout**, because several files document a spacing that used to be
  there and rewriting the prose would be a lie about history.
- It also closes `checkout_evidence.dart:311`, the hard-rule-2 site `PHASE_04_HANDOVER.md` flagged as
  belonging to no phase. Its helper reads `State.context`, since it takes no `BuildContext` of its own.
- **`test/dev/token_spacing_test.dart` is the tripwire, and it was verified by breaking it.** A planted
  literal is reported with its file and line, and the message carries the scale, the rule for an
  off-scale value, and the two mechanical traps this work paid for. The pattern is deliberately narrow:
  one that also flagged `Size(48, 48)` and every `elevation: 0` would be a scan people silence rather
  than obey. A second test asserts every exempt path still exists, because an exemption naming a
  deleted file is a hole nobody can see.

## Testing

**2,318 tests pass**, from 2,316. Two added, both in the tripwire. The harness writes **536 images
across 163 screens**, from 484 across 158 — 52 new, all of them staff captures.

## The commits, in order

| | |
|---|---|
| `fd247c4` | Run dart format over the staff capture file before Phase 07 touches it |
| `8c38be0` | Photograph the five staff forms nothing had ever rendered |
| `96c7401` | Make the staff correction form say the verb its own button says |
| `3336f03` | Run dart format over the three staff files before Phase 07 repoints them |
| `158f969` | Put the staff surfaces' spacing on the token scale |
| `1ee6302` | Write down the midnight-UTC trap that cost Phase 07 a bisect |
| `1a41c9a` | Put the pill back on buttons, chips and fields |
| `3a4f2c2` | Move the corner and placeholder assertions onto the owner's shape |
| `726e185` | Make the three sales-totals filters dropdowns instead of a wall of pills |
| `733771e` | Record the owner's three shapes as overrides, with what they override |
| `11472e1` | Run dart format over the five files the global repoint touches |
| `4ba7243` | Put the whole reachable tree's spacing on the token scale |
| `d0f54fa` | Make hard rule 2's spacing half a tripwire instead of a coincidence |

## What is still not started

**Phases 09, 06, 05 and 08 have had no composition pass, and Phase 10 has not been run.** Phases 01
and 02 were checked structurally at `06a24f9` and still need their visual pass. Phase 07's own slice 3
is not started. The token layer, the harness coverage and the three owner shapes now reach all of
them, so none of that work will need redoing — but none of it is done, and the reskin is not finished.

# Phases 05, 06, 08, 09 — one fast evidence pass, 2026-08-23

**Five commits, `6d3c216` to `7217bf4`.** Deliberately thin records: the coverage pass and three
defects, no long-form narrative.

- **`6d3c216`** — all 27 captures across the four phases rendered at 1440 and 411 only, none at 834
  or 1024. All four now, and **nothing overflows**: 455 capture tests pass. 68 new images.
- **`098162b`** — **Reject a business, archive one, suspend one, disable a user were all drawn as
  ordinary secondary buttons**, identical to Approve or Reactivate beside them, while all four
  confirmations they open already take §2.1's destructive tier — two with a comment saying why. The
  decision was made one screen deeper and never reached the row. A scan for the same shape found no
  other untiered destructive `AppButton` anywhere in the reachable tree.
- **`afac531`** — the differences filter had **nine options with sentence-length labels**, wrapping to
  three rows and taking more of a tablet than the first difference card. Decision 26b leaves a lone
  chip strip alone; nine long options is where that stops being right, because the rule is about a
  wall of pills rather than about counting filters.
- **`7217bf4`** — **the print queue never said whose queue it is.** Phase 08's third criterion is that
  scope is clearly device-local; the screen opened straight into its callouts and list, and "2
  receipts waiting" with no scope reads as the business's. It is a Hive box on one handset.

**Checked and found already right:** Phase 06's return verification names its consequence, lists the
exact lines being restored and says what stays true; Phase 05's difference and unusable-line states
carry their meaning in words rather than colour.

2,318 tests pass, 604 images across 163 screens, 9 moved — the four platform screens, the differences
screen and the four queue screens, which is exactly what the three fixes touched.

**Still not started: the composition passes for 05, 06, 08 and 09, Phase 10, Phase 07's slice 3, and
the 01/02 visual passes.** This was an evidence-and-defect pass, not a rewrite.

## Composition changes across 05, 06, 08 and 09 — 2026-08-23

Six screen changes on top of the coverage pass. Each serves a named acceptance
criterion and each was found by looking at the new pictures or at the code behind them.

- **`b253a09` — the daily summary compares days now.** It listed seven and never said whether one
  was up or down on the day before. ST-041 draws two bars for that question; **two bars is the
  wrong form** — `dataviz`'s form table sends a handful of headline numbers to stat tiles and names
  the grouped-bar version as what not to do, and a chart beside figures the page already states is
  the decorative case criterion 2 forbids. `OPEN_QUESTIONS.md` Phase 05 item 1 caps charting at
  "two exact daily sales bars" as a ceiling, not a request. So: a value and its delta, exact, from
  the seven days already loaded, stated only where the neighbour is also reconciled, and **not
  coloured** — no §2.1 status means "sales went up", and a shop can take more by discounting.
- **`6851d3f` — the platform shell says it is not a business.** Criterion 1 is that it be distinct
  from tenant management and the shell was *titled* `Platform tenant management`. It is
  `Platform operations` now, ST-073's own words, plus an authority marker naming the operator and
  stating the reach — criterion 3, because a dedicated operator has no membership, no business name
  and no role line to infer any of it from.
- **`e3c9a83` — the paper is named the way it is bought.** `32 columns` is the ESC/POS abstraction;
  the enum's own doc comments already said `58mm roll` and `80mm roll` and nothing rendered them.
  §8 rule 1, criterion 4, and `tool/printer_row_probe.dart` already wrote the pair in this shape.
- **`7217bf4` — the print queue says whose queue it is.** Criterion 3, and the screen said nothing
  about scope at all.
- **`ebaba64` and `1fd13e6` — the returns route states its role split.** Criterion 2. A cashier saw
  the verify action simply absent: correct guarding, silent. **The notice commit moved zero images**,
  which is how its own gap surfaced — `34` runs as a manager, so the branch was unphotographed.
  `34b` is the cashier reading, and a zero-pixel diff catching a coverage hole is worth recording.
- **`098162b` and `afac531`** — the four platform destructive tiers and the nine-option filter, above.

2,318 tests pass. 612 images across 164 screens.

**Still not started:** Phase 10, Phase 07's slice 3, and the 01/02 visual passes. These were
criterion-driven fixes on real screens, not full recompositions against each design.
