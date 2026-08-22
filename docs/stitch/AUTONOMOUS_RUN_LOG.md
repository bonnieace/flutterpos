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
