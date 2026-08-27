> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 03 handover — compose the sale path

**Written 2026-08-22, at commit `b8b3b31`, on branch `stitch-wave-0-tokens`.**

You are running **unsupervised**, and this is the first phase of the run that changes what a screen
looks like. Everything before it was tokens, components and contracts.

## Read these, in this order, and no more

1. **`AUTONOMOUS_HANDOVER.md`** — still the operating charter. Its §1 authority, §4 testing policy, §5
   commit policy and §8 traps all stand. **Its §2 and §3 are partly struck through**: order-of-work
   items 1–3 are done and the token layer's "finished" claim was corrected. Read the strikethroughs.
2. **`phases/03-sale-checkout.md`** — the brief. Four acceptance criteria, five required state groups,
   six exclusions.
3. **`LIVE_PHASE_HANDOFF.md` § Phase 03** — the two ST-036 defects, with exact replacement copy.
4. **`docs/stitch/AUTONOMOUS_RUN_LOG.md`, the run summary at the end** — what the last run decided and
   what it left provisional.

Do **not** sweep `HISTORY.md` or the export. `EXPORT_MAP.md` turns an ID into a folder.

---

## What you are composing

| Design | Export folder | Status |
|---|---|---|
| **ST-035** desktop/tablet | `chilltent_pos_new_sale_desktop_tablet_normalized` | `CANONICAL CANDIDATE / VISUAL REVIEWED` — **no pending defects** |
| Mobile browse (recovered) | `chilltent_pos_new_sale_mobile_browse` | Handoff calls the render coherent |
| **ST-036** mobile cart | `chilltent_pos_new_sale_mobile_cart` | `NORMALIZED / RENDER REVIEW` — **two named defects, correct them** |

Each folder holds `code.html` (served markup with the Profound Verdant token block inlined) and
`screen.png`. **Open the PNG first.** The HTML is for resolving a value the picture leaves ambiguous,
not for reading front to back.

**Phase 03 is the best-specified phase in Wave 1, which is why it is first.** Phase 04's full mobile
composition does not exist and Phase 09 has no verified canonical screen; starting there means
inventing and then redoing.

## The two ST-036 corrections — not fidelity targets

1. Its save refusal says `Could not save sale. Storage full or write error.`, which **invents a
   cause**. Use the established generic refusal: *"This sale could not be saved on this device. Try
   again, and ask for help if it keeps happening."*
2. It renders a generic `Sale / Orders / History / Sync` **bottom bar**. Delete it. It conflicts with
   the approved role-aware mobile navigation and the staged browse/cart flow.

Change nothing else on that screen: the cart, the tender assertion, the KES 135.00 total, the durable
receipt, the later confirmation and the independent print-failure states are all supported evidence.

---

## The three slices

One commit each. `checkout_cart_panel.dart` is **2,941 lines** and the most behaviour-coupled file in
the app, which is why this is three slices and not one.

### Slice 1 — mobile staged browse

`_productsPane` and `_compactLayout` (`checkout_cart_panel.dart:897`, `:734`), plus `_ProductTile` and
`_ProductThumbnail`. Against the recovered browse render: product grid, search, categories, the
cached-freshness line, the non-blocking zero-stock warning, and one clear *Open the cart*.

Captures: `14-new-sale` at both viewports already exists and will move.

### Slice 2 — mobile cart, tender and outcomes

`_cartPane`, `_CartBar`, `_CartLine` (`:764`, `:1514`, `:1610`). Against ST-036 **with both
corrections applied**. Quantity edit and removal, tender as an assertion, save busy/success/error,
saved-locally versus server-confirmed, and the sale-durable-but-print-failed route to receipts waiting.

Captures: `15-new-sale-with-a-cart` and `15b-sale-saved-but-not-printed` will move.

### Slice 3 — desktop and tablet two-region

`_wideLayout` (`:708`). Against ST-035. The cart pane is `AppLayout.salePane` (420) and the products
pane flexes; `TenantCheckoutPanel.showsTwoPanes` reads `mediumFloor`, so two panes begin at 768.

**The 3-column desktop till stays deferred.** Above 1280 Profound Verdant asks for
`Categories | Items | Cart` and this app draws two panes with categories as a horizontal
`FilterChipBar`. That is recorded design debt in `OPEN_QUESTIONS.md` decision 21, not a Phase 03 task.
Do not build it.

---

## Testing — read this before writing a test

**The last run wrote 65 tests because its work items were verification items. Yours are not.**

> **On a composition slice the screenshot matrix is the deliverable, not new unit tests.**

Write a test only when one of these is true:

- a widget gains a **state nothing photographs** — and prefer adding the capture over adding the test;
- you change a value **another file measures** (the `ProvenanceLine.styleOf` shape: an allocator and a
  renderer that must not drift);
- you find a defect and the fix would otherwise be invisible to every existing assertion.

**Do not re-assert behaviour that already has coverage.** Phase 03's tender, outbox, sync, receipt and
print-queue behaviour is the most tested area in this repository. `test/checkout/` alone is **10,981
lines** and all of it passes today. A composition change that breaks one of those tests means you
changed behaviour, which is hard rule 1 — that is the signal, not a gap.

Per slice: the focused test files for what you touched, `flutter analyze` on the changed files only,
`dart format` on the changed files only. **Never `dart format test/`** — most of that tree has drifted
from the current formatter and a whole-tree run rewrites about ninety files. The last run made that
mistake and had to revert it.

Per phase, once, before the final commit: `flutter test test/` (**2,314 tests, ~2m10s**), then
`flutter test tool/screenshots` and `dart run tool/screenshots/build_index.dart` (**333 captures, 405
images, ~40s**).

Hash `screenshots/` before and after — it is gitignored, so `git status` reports nothing whatever it
holds. Report how many of the 405 moved and how many are new. **A count is evidence; "screenshots
regenerated" is not.**

---

## What will bite, specifically on this phase

**1. The sale path has a motion rule, and it is the one rule a screenshot cannot check.**
*Nothing on the sale path may sit between an input and its record. The sale is written first; the
animation plays over committed state.* And anything spatial uses a spring that is interruptible from
its current position and velocity — never `forward()` from zero on a retrigger. If you touch the save
or tender flow's timing, that is a device check with the performance overlay on, and you must say so
rather than reporting it verified.

**2. Expect at least one screen you cannot restyle without touching logic.**
`checkout_cart_panel.dart` mixes composition with the outbox. When that happens: **stop that screen,
write the coupling down, move to the next.** Do not make it work. Hard rule 1 is absolute and a
half-restyled sale path that changed a state transition is worse than an unstyled one.

**3. The design's money is in `data-mono` and this app's `numericBody` is not.**
65 occurrences beside `currency-kes`. `OPEN_QUESTIONS.md` question 22 left this open deliberately: it
is a composition judgement per surface, not a token value. **The till is the surface where it matters
most.** Decide it here, for this surface, and log it — do not close it globally.

**4. `AppLayout.salePane` (420) is read by exactly one place** —
`checkout_cart_panel.dart:720`, as a `SizedBox` width. It is not a page maximum. The tightest case the
768 floor admits is a cart pane of 420 leaving the products 347, and a `Row` that does not fit
overflows and throws. There is a test pinning 768 exactly; keep it passing.

**5. The width regions are all photographed now.** `desktop-narrow` (1024) and `compact-wide` (767)
exist, and the till is already captured at 1024 — `screenshots/desktop-narrow/14-new-sale.png`. Use
them; that is what they were added for.

---

## Guard rails that have not moved

- **A UI change never changes behaviour.** No repository calls, state logic, routing conditions or API
  shapes.
- **No hardcoded values in widgets.** Every colour, size, radius, spacing, duration and spring comes
  from the token layer. `lib/theme.dart` now names no type metric of its own and a scan keeps it that
  way.
- **Do not touch `lib/pos/**`, `lib/screens/**`, or the eight other unreachable locations** —
  `test/dev/reachable_lib_test.dart` holds the list. `lib/widgets/` is a **pill** component set and
  this design has no pills; it is dead code, not a resource.
- **Do not edit `functions/**`, `firestore.rules`, `rules-tests/**`, `pubspec.yaml` dependencies or any
  lockfile.** This reskin is client-only. Check with `git diff` rather than assuming, then skip those
  suites.
- **No `git push`, no PR, no deploy.**
- **Do not invent a product fact.** `test/dev/product_vocabulary_test.dart` scans for eight of them and
  Phase 03's exclusions name six more: VAT/tax calculation, externally verified payment, discount
  input, save-draft, stock blocking, rollback because printing failed.
- **Never claim a screen is pixel-perfect.** ST-036 is `NORMALIZED / RENDER REVIEW` — corrected and
  never visually confirmed. Say provisional when it is provisional.

## Recording

- One entry per commit in `AUTONOMOUS_RUN_LOG.md`, in its existing format. The convention that file
  states: code commit first, then the record naming its sha.
- At phase end, a session entry in `HISTORY.md`, the Current state table in `prompt.md`, and
  `dart run tool/doc_index.dart`. **`prompt.md` last, in the same commit as the phase** — it has gone
  stale three times now.
- Report what the screenshots prove and what still needs a device. They prove the raster. They do not
  prove the app runs, and they cannot show motion at all.

**The web target still does not run**, for two pre-existing bootstrap bugs (`lib/main.dart:60`,
`web/index.html:108`). Both are behaviour changes needing authorisation. **Do not fix them.** Use
Windows desktop if you need to see the app run.
