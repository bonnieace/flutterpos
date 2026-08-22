# Phase 04 handover — catalog and stock

**Written 2026-08-22, at commit `6598bee`, on branch `stitch-wave-0-tokens`.**

You are running **unsupervised**. Phase 03 is done and is the only screen family any session has
recomposed. This is the second, and it is four times the surface area.

## Read these, in this order, and no more

1. **`AUTONOMOUS_HANDOVER.md`** — still the operating charter. §1 authority, §4 testing policy, §5
   commit policy, §7 quality bars and §8 traps all stand. **Its §2 and §3 are struck through in
   places**: order-of-work items 1–3 are done, item 4 is now half done, and the token layer's
   "finished" claim was corrected once already.
2. **`PHASE_03_HANDOVER.md`** — not for its content but for its **shape**. It is the model for how a
   phase is scoped, and its §"What will bite" was right four times out of five. One figure in it was
   wrong; see §"What this handover measured" below for why that matters to you.
3. **`phases/04-catalog-stock.md`** — the brief. Four acceptance criteria, six required state groups,
   five exclusions.
4. **`LIVE_PHASE_HANDOFF.md` § Phase 04** — the ST-039 and ST-040 defects. **Read §"The four ST-039
   corrections" below before you act on them.**
5. **`audits/phase-04.md`** — 86 lines, and the last two paragraphs are the ones that matter: they
   explain why the export you will read is *older than the design that was approved*.
6. **`AUTONOMOUS_RUN_LOG.md`, the Phase 03 section** — three deliberate deviations and decision 23's
   four landing sites. Do not relitigate either.

Do **not** sweep `HISTORY.md`. `EXPORT_MAP.md` turns an ID into a folder.

---

## What you are composing

| Design | Export folder | Status |
|---|---|---|
| **ST-039** desktop route suite | `chilltent_pos_catalog_stock_route_suite_desktop` | `NORMALIZED / RENDER REVIEW` — **four named defects, and the export is the pre-correction render** |
| **ST-040** mobile route suite | `chilltent_pos_catalog_stock_mobile_route_suite` | `NORMALIZED / RENDER REVIEW` — **9,218 bytes, one section of nine. It does not exist.** |
| ST-038 mobile (superseded) | `chilltent_pos_catalog_stock_mobile` | `NON-CANONICAL / SUPERSEDED` — **not a fallback. See below.** |

**Open ST-039's PNG first.** It is nine numbered sections on one tall canvas: three role variants of
the catalog table, a product correction form, bulk changes, product stock, the audit table, an 834px
tablet card transformation, and a state strip. That structure — nine specimens rather than one screen
— is the most useful thing about it and is what your captures should mirror.

### ST-040 is not "awaiting review". It is one ninth of a design.

Its served HTML is **9,218 bytes** and stops after `1. Cashier — Product catalog`, ending on the
generator's own comment asking for more specimens. `EXPORT_MAP.md` uses that byte count as one of the
two structural fingerprints proving the export is fresh, so the truncation is real rather than a
download that failed. The PNG shows one phone frame and then a page of empty ground.

**There is no Stitch connector in this session and mutation needs human authorisation anyway**, so you
cannot generate the missing eight sections. That is the central constraint of this phase and you
should plan around it rather than discover it:

> **The mobile composition for Phase 04 must be derived from ST-039's accepted structures plus this
> app's own responsive contract, and every derived screen must be recorded as derived.**

That is not a licence to invent. `RecordList` already decides what a table becomes at each band, it is
already photographed at all three (`96-*` at `tablet/`), and §4.3's contract is the thing ST-039's own
section 8 is a picture of. Derive from those and say so.

### ST-038 is not the fallback, and here is why

It is the superseded first mobile successor, and it carries **two facts this product does not have**
and one this app already refused:

- a `Catalog / Stock / History / Sync` **bottom navigation bar** — the same defect ST-036 had, and the
  app has no bottom navigation in any reachable file;
- invented products (`Premium Arabica Beans 1kg`, `Eco-friendly Cups (500pk)`, codes `BEAN-001` /
  `SUP-042`) and an invented `SUPPLIES` category. `test/dev/product_vocabulary_test.dart` scans for
  eight forbidden tokens; these are not on that list **only because nobody has added them**;
- role-mode tabs (`CATALOG (CASHIER)` / `MANAGE (MGR)` / `MANAGE (OWNER)`) as a control a person
  switches. Role is not a mode in this app — it is the session — and `RBAC_MATRIX.md` §"Hidden actions
  must also be guarded in product code" is the rule that makes a role tab a lie.

Read it for its card shape and for nothing else.

---

## The four ST-039 corrections — and I checked all four against the app

`LIVE_PHASE_HANDOFF.md` lists four things ST-039 gets wrong. **The export is the pre-correction
render**, so all four are present in the file you will open — `audits/phase-04.md`'s last two
paragraphs explain that the final edit completed without returning a new screen ID and retrieval kept
serving the stale artifact.

Phase 03 found that both of ST-036's defects were already satisfied by the app. **I checked these four
the same way, at `6598bee`.** Verify them yourself before you rely on this table — that is what
`AUTONOMOUS_HANDOVER.md` §8's first trap is about — but do not spend the phase rediscovering it.

| ST-039 defect | The app, checked | Where |
|---|---|---|
| Collapses adjustments, movements and ledger into **one table** | **Three separate routes already.** | `stock_adjustment_feed_panel.dart`, `stock_movement_feed_panel.dart`, `stock_product_ledger_panel.dart`; captures `22`, `23`, `24` |
| Says `Before/After` | **Says `Before and after`**, from one named constant | `stock_movement_labels.dart:33`, `stockBeforeAndAfterLabel` |
| Lacks exact provenance (actor, time, source) | **Every record carries a `ProvenanceLine`** through `RecordItem.provenance` | `stock_movement_labels.dart:170` and `:214`, rendered at `record_list.dart:708` |
| Has a supplier-oriented reason placeholder — `e.g., Morning delivery from supplier` | **The reason field has no placeholder at all**, only the label `Reason for this adjustment` | `stock_adjustment_panel.dart:907-912` |

So the likely finding is **four more instances of the Phase 02 and Phase 03 pattern: the app is right
where the design is wrong.** If that holds, say so plainly and do not manufacture work from it. What
is left open, and is a real question rather than a settled one:

- whether the **fixtures** show the evidenced examples the handoff names — a `+24` manual adjustment
  and a `-2` sale with source `co-1`. The routes render provenance; whether any capture *contains* a
  sale-sourced movement beside a manual one is a fixture question, and `21b-product-stock-differences`
  exists precisely because an earlier fixture hid the case its route was written for.

---

## The two gaps I found that no document names

These are the parts of this phase with real work in them. Both are measured, not estimated.

### 1. Every Phase 04 route is photographed at two widths, and the band where its tables transform is not one of them

`RecordList.formFor` has **three** forms — `stackedCards` below 768, `twoColumnCards` from 768 to
1023, `table` at 1024 and above. Phase 04's fourth acceptance criterion is *"Tables transform to
usable mobile records without losing action context"*, and ST-039's section 8 is a labelled 834px
specimen of exactly that.

Every one of the thirteen catalog and stock captures renders at `web` (1440) and `mobile` (411) only:

```
17-read-only-catalog        18-manage-catalog        18b-catalog-notice
18c-manage-catalog-read-only   19-correct-a-product  20-bulk-changes-and-import
20b-bulk-report-previewed   20c-bulk-report-committed
21-product-stock            21b-product-stock-differences
22-stock-corrections        23-stock-movements       24-one-product-ledger
```

**`twoColumnCards` — the middle form, the one ST-039 draws a specimen of — appears in no picture of
any real catalog or stock route.** The *component's* matrix does cover it (`tablet/96-record-list*`,
added when the tablet viewport was), so this is a composition gap rather than a component one, and
that distinction is worth keeping: the shapes are proven and their use on a page of six columns and
two actions is not.

`responsiveViewports` is the four-width list and costs nothing to pass. Start here — it is cheap, it
is the criterion, and it will tell you which of the routes below actually need work.

### 2. The design's strongest structural claim has no photograph at all

ST-039's first three sections are the same catalog table rendered three times — **Owner/Administrator,
Manager, Cashier** — side by side, so the narrowing is visible rather than asserted. Acceptance
criterion 1 is *"Role-narrow fields/actions are structurally clear and cannot be mistaken for manager
capability."*

The app genuinely branches. `catalog_management_panel.dart` takes `canRetire` and `canRecordCost`
from `TenantCatalogManagementRepository.retireRoles` and `.costRoles` — both owner and administrator
only — and uses them at `:756`, `:961` and `:1088`.

**No capture renders that branch.** `17`, `18`, `18b`, `18c`, `19`, `20`, `20b` and `20c` all run
under `seedSession()`, which is **owner**. `21` through `24` run as **manager**, but those are the
stock routes, where the role lists do not differ. So:

- there is **no cashier rendering** of the read-only catalog, and the brief's first required screen is
  "read-only catalog for **all active roles**";
- there is **no manager rendering** of the management list or the correction form, which is the one
  place in this phase where owner and manager see structurally different pages.

`13c-staff-directory-read-only` is the precedent for how this is captured, and its own note calls it
"the only session its standing is true of".

---

## Suggested slices

Four, one commit each, smallest evidence-bearing first. Adjust the order if the code disagrees with
me — it is the authority and I read it from outside.

### Slice 1 — photograph what exists before changing it

`responsiveViewports` on the thirteen routes above, plus the two role renderings §2 names. **No Dart
change in this slice.** It is the cheapest possible way to find out how much of Phase 04 is already
right, and Phase 03's own experience is the argument: four of Wave 0's six components needed nothing
built, and both ST-036 defects needed no code.

Expect roughly 26 new images from the width axis and a handful from the roles. Hash before and after.

**If a route turns out to overflow or truncate at 834, that is the finding, and it is worth more than
a restyle.** A widget test does detect an overflow; nothing is currently running one at that width for
these routes.

### Slice 2 — the token debt, which is hard rule 2 and is countable

`lib/inventory/` holds **97 literal spacing and inset values** in widgets. Measured at `6598bee`:

| File | literal spacing/inset sites | lines |
|---|---:|---:|
| `catalog_management_panel.dart` | 34 | 1,648 |
| `stock_adjustment_panel.dart` | 24 | 924 |
| `bulk_catalog_panel.dart` | 22 | 1,419 |
| `stock_product_ledger_panel.dart` | 6 | 278 |
| `stock_movement_feed_panel.dart` | 6 | 375 |
| `stock_adjustment_feed_panel.dart` | 5 | 268 |

For comparison, `lib/ui/` has 2 and `lib/checkout/` has 7 — and all seven of those are in
`checkout_configuration_panel.dart`, which is **screen 16 and is Phase 08's**, not a Phase 03 leftover
(the brief lists 16 under both 03 and 08; 03's acceptance criteria are all sale-path, 08's brief names
groups 16, 36 and 37). Phase 03 left it deliberately and this is the first place that is written down.

Most of the 97 are `SizedBox(height: 8|12|16)` and are a mechanical repoint to `tokens.spacing`. It
moves few pixels, which is the point — it is the rule, and a phase that restyles a surface while
leaving ninety-seven literals in it has not done the phase.

### Slice 3 — the raw Material still on these screens

Four sites, all of them documented as deliberate hold-backs by earlier steps rather than oversights.
Re-read each note before deciding; two of them may still be right.

| Widget | Where | The note already there |
|---|---|---|
| `SegmentedButton<bool>` — Add stock / Remove stock | `stock_adjustment_panel.dart:879` | none; this one is bare |
| `Chip(` — the category strip | `catalog_management_panel.dart:868` | none |
| `Checkbox(` ×2 | `catalog_management_panel.dart`, `bulk_catalog_panel.dart` | none |
| `Card(` — the bulk report rows | `bulk_catalog_panel.dart:1073` | **argues to keep it**: "screen 20 is not one of the twelve screens step 6 names, and migrating it to `RecordList` would be step 6 work outside step 6's list" |

`FilterChipBar` is the app's answer for a single-selection strip and `AppButton` for actions. There is
**no segmented-control component and no checkbox component**, and §5.2 specifies neither — so if you
conclude one is needed, that is a component with a full state matrix and a set of captures, not a
widget you write inline. Phase 03 declined to build a segmented control for the tender chooser for
exactly this reason; that decision is in the run log and applies here too.

### Slice 4 — the mobile composition, derived and labelled as derived

Only after 1–3. Against ST-039's structures and §4.3's contract, because ST-040 does not exist.

**Every screen in this slice is a derivation and must be recorded as one** — in
`AUTONOMOUS_RUN_LOG.md` as a decision taken unsupervised, and in `OPEN_QUESTIONS.md` as the next
numbered item where the design defines nothing. `AUTONOMOUS_HANDOVER.md` §1's standing tie-breaker is
the rule: prefer the option that moves pixels toward the design and leaves repository calls, state,
routing conditions and API shapes untouched.

---

## Testing — the same contract, and one figure moved

**Baselines at `6598bee`, measured:**

- `flutter test test/` — **2,315 tests, about 2m40s**. (Was 2,314 before Phase 03 added the money
  role's contrast assertion.)
- `flutter test tool/screenshots` then `dart run tool/screenshots/build_index.dart` — **337 captures
  writing 413 images across 155 screens, about 45s.** (Was 333 / 405 / 151.)
- `flutter test test/inventory` — **272 tests, about 16s.** This is your focused suite.
  `test/inventory/` is **9,345 lines** and all of it passes today.

The anti-overtesting contract has not moved, and it bit correctly on Phase 03:

> **On a composition slice the screenshot matrix is the deliverable, not new unit tests.**

Write a test only when a widget gains a state nothing photographs (and prefer the capture), when you
change a value another file measures, or when you find a defect the existing assertions cannot see.
Phase 03 added exactly one test across seven commits, and it was an accessibility assertion, which §9
makes pass/fail rather than optional.

**A composition change that breaks a behaviour test means you changed behaviour.** That is hard rule 1
and it is the signal, not a gap. Phase 03's evidence for that claim: `test/checkout/`'s 10,981 lines
passed unchanged through a rewrite of the file they cover. Three assertions did move and all three
were *copy* — a rendered string split in two because money took a role of its own.

Per slice: the focused test files, `flutter analyze` **on the changed files only** — never the repo,
it has ~477 pre-existing infos — and `dart format` on the changed files only.

**Never `dart format test/` or `dart format tool/`.** Most of both trees has drifted from the current
formatter. Phase 03 hit this twice and both times the answer was the same: revert, commit the reflow
of the one file alone (`107cdea`, `a5b6ca6`), then make the change on top of it. Budget for that — the
three files slice 2 touches will each want it.

Hash `screenshots/` before and after; it is gitignored, so `git status` reports nothing whatever it
holds. **Report how many of the 413 moved and how many are new.** A count is evidence;
"screenshots regenerated" is not. Phase 03's count was 17 moved, 8 new, 0 removed — and the useful
half of that sentence is that all 17 were till captures, which is what said the change was contained.

---

## What will bite, specifically on this phase

**1. This is four times Phase 03's surface and there is no one file to hold it.** Phase 03 was one
2,289-line file. Phase 04 is **9,847 lines across twelve files**, six of them panels, and the three
largest — `catalog_management_panel.dart` 1,648, `bulk_catalog_panel.dart` 1,419,
`stock_adjustment_panel.dart` 924 — are all bigger than anything Phase 03 touched. **Cut scope, not
quality**, which is §7's own instruction: finish fewer routes properly and say which ones you did not
start.

**2. The audit trail is the product here, not decoration.** Acceptance criterion 3 is "Audit context
(actor, time, reason, before/after) is readable", and `OPEN_QUESTIONS.md`'s Phase 04 item 6 is why it
is load-bearing: **these feeds are ordered by record ID, not by time.** A person reading them cannot
infer sequence from position, so the recorded time on each row is the only thing that carries it. Do
not quieten a provenance line to make a list calmer. It is the one thing on the page that is not
inferable from anything else.

**3. Stock display must never imply a sale is blocked.** Criterion 2, `OPEN_QUESTIONS.md` Phase 04
item 4, and the same product fact Phase 03 stated on every product tile. Recorded stock may be
negative. Phase 03 chose `-3 in stock` over `Out of stock` on the till for exactly this reason and the
run log has the argument; **be consistent with it here or say why you are not.** A red row on a
catalog page that reads as "cannot sell" is the defect this criterion exists to catch.

**4. Five exclusions, and four of them are things a designer will reach for.** No reorder points, no
automatic low-stock thresholds, no supplier or purchase-order workflow, no `.xlsx`, no cashier stock
writes. ST-007 — the original inventory screen this family was corrected from — contained the first
three, and `audits/phase-04.md` records that as the reason the correction happened. If a composition
starts wanting a "low stock" treatment, that is the exclusion talking, not a gap.

**5. `test/dev/product_vocabulary_test.dart` scans for eight forbidden tokens and ST-038 is full of
candidates for a ninth.** If you use that render for anything, do not carry its products across.

**6. The three role lists are the design's subject, and a hidden control is not a guarded one.**
`RBAC_MATRIX.md`'s closing note: *"Hidden actions must also be guarded in product code during
implementation; visual hiding alone is not sufficient."* `test/tenancy/rbac_matrix_test.dart` already
asserts all 31 role lists against the matrix — so the guards are proven and what you are composing is
whether a person can *see* the narrowing. Those are different claims and the phase needs both.

---

## Guard rails that have not moved

- **A UI change never changes behaviour.** No repository calls, state logic, routing conditions or API
  shapes. If a screen cannot be restyled without one: **stop that screen, write the coupling down,
  move to the next.** Do not make it work.
- **No hardcoded values in widgets.** Every colour, size, radius, spacing, duration and spring comes
  from the token layer. Slice 2 is 97 counted violations of this rule.
- **`AppTextRoles.money` is the till's, not the app's.** `OPEN_QUESTIONS.md` decision 23 says so in as
  many words and the role's own doc comment repeats it. Phase 04 is full of money — prices, costs,
  ledgers — and **the token existing is not permission to take it.** If you want it here, that is a
  new numbered decision with its own evidence, and the argument that it is a column of figures rather
  than one figure a person reads aloud is the one to answer.
- **Do not touch `lib/pos/**`, `lib/screens/**`, or the eight other unreachable locations.**
  `test/dev/reachable_lib_test.dart` holds the list and fails if it changes. `lib/widgets/` is a
  **pill** component set; this design has no pills.
- **Do not edit `functions/**`, `firestore.rules`, `rules-tests/**`, `pubspec.yaml` dependencies or
  any lockfile.** Client-only. Check with `git diff` rather than assuming, then skip those suites.
- **No `git push`, no PR, no deploy.**
- **Do not invent a product fact.** Five exclusions above, plus the eight scanned tokens.
- **Never claim a screen is pixel-perfect.** Both Phase 04 designs are `NORMALIZED / RENDER REVIEW` and
  one of them is nine-tenths absent. Say provisional when it is provisional.

## Recording

- One entry per commit in `AUTONOMOUS_RUN_LOG.md`, in its existing format. Code commit first, then the
  record naming its sha.
- Every derived mobile screen gets a numbered `OPEN_QUESTIONS.md` item with the evidence you had.
  Decision 23 was the last one; yours start at 24.
- At phase end: a session entry in `HISTORY.md`, the Current state table in `prompt.md`, and
  `dart run tool/doc_index.dart`. **`prompt.md` last, in the same commit as the phase** — it has gone
  stale three times and Phase 03 was the first to update it in the phase's own final commit.
- Report what the screenshots prove and what still needs a device. They prove the raster. They do not
  prove the app runs, and they cannot show motion at all.

## What this handover measured, and why that sentence is here

Every figure above was taken at `6598bee` by running the thing rather than by carrying it forward:
line counts by `wc -l`, literal spacings by a grep whose pattern is in this repository's history,
capture coverage by listing `screenshots/`, role sessions by reading the capture definitions, and the
four ST-039 checks by opening the four files named beside them.

**`PHASE_03_HANDOVER.md` stated that `checkout_cart_panel.dart` was 2,941 lines. It was 1,779.** The
conclusion drawn from it — three slices, not one — was still right, and the wrong number cost nothing
because the reasoning did not depend on it. But it was the one figure in that document nobody had
re-measured, and it is the reason this section exists. Re-measure anything here that your plan depends
on. If a figure has moved, correct it in place and say so, the way `6598bee` did.

**The web target still does not run**, for two pre-existing bootstrap bugs (`lib/main.dart:60`,
`web/index.html:108`). Both are behaviour changes needing authorisation. **Do not fix them.** Use
Windows desktop if you need to see the app run.
