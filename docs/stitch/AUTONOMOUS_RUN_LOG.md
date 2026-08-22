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
