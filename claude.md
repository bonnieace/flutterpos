# CLAUDE.md

Instructions for Claude Code working in this repository. Keep this file short — it loads
on every turn, and length here costs context on every task.

## The design system

**Direction changed 2026-08-25.** Existing customers know the pre-multitenancy app
(`lib/pos/**`, `lib/screens/**` — still read-only reference only, see hard rule 3) and find the
Stitch redesign's navigation and visual changes confusing. For screens covered by that reversal,
the old app's screens/flows/visual character are the target, rebuilt on the existing multitenant
backend and token layer — see the plan at
`C:\Users\BonifaceMasota\.claude\plans\look-at-the-old-expressive-sutton.md` for scope
(currently Login, Home/Main Hub, Sales Report/Book Keeping) and approach. `docs/stitch/README.md`
carries a retirement notice for those screens; treat its phase briefs and `OPEN_QUESTIONS.md` as
historical for them, not authoritative. For any screen **not yet** covered by the reversal,
`docs/stitch/README.md` and the selected phase brief are still the coordination point — read them
before visual work there.

`docs/stitch/RBAC_MATRIX.md` remains the authority for behavior and access everywhere,
regardless of which visual direction a screen follows. `docs/stitch/DESIGN_RULES.md`'s
accessibility and product-truthfulness rules (§9 contrast/target/focus/state requirements,
offline-first truthfulness) still apply everywhere too — only its Profound Verdant visual
character is what old-look screens override, deliberately.

Root `DESIGN.md` documents the previous Flutter-led system. It is implementation history, not
visual authority for new Stitch compositions. Preserve reusable semantic theming: approved
tokens must flow through the theme layer rather than becoming hardcoded widget values, even
when recreating an old screen's look — extend `AppTokens` rather than hardcoding a value the
old screen used. If neither the applicable rules nor product evidence define a decision, record
it in `docs/stitch/OPEN_QUESTIONS.md` instead of inventing one.

## Hard rules

1. **A UI change never changes behaviour.** No repository calls, no state logic, no
   routing conditions, no API shapes in a visual pull request. If a screen cannot be
   restyled without a logic change, stop and describe the coupling.
2. **No hardcoded values in widgets.** Every colour, size, radius, spacing, duration and
   spring comes from the token layer. A literal hex or a magic number in a widget is a
   defect regardless of whether it looks right.
3. **Do not touch `lib/pos/**` or `lib/screens/**`.** Legacy, read-only, out of scope.
   **Eight more locations are equally unreachable and equally out of scope** — including a
   `pill` component set and two rival colour systems. `test/dev/reachable_lib_test.dart` holds
   the list and fails if it changes; read it before restyling anything outside `lib/ui/`.
4. **One phase per branch.** Use the numbered briefs under `docs/stitch/phases/`. Do one
   phase and stop; a completed Stitch design is not permission to begin Flutter implementation.
5. **Every component ships with its full state matrix** — enabled, hover, focus-visible,
   pressed, disabled, loading, error, read-only, empty, whichever apply — and each state
   appears in the screenshot harness. A component missing a state is not done.
6. **Accessibility is pass/fail.** See §9. Contrast, 48dp targets, focus rings, and
   status never conveyed by colour alone are requirements, not preferences.

## Workflow for any visual change

1. Read `docs/stitch/README.md`, the relevant control documents, and one phase brief.
2. State the plan, exact Stitch operation/IDs or code file list, and exclusions. Wait for confirmation.
3. Perform only the approved design operation or implementation phase.
4. Re-read affected Stitch screens and/or regenerate the local screenshots as applicable.
5. Update the Stitch index/coverage/audit trail and report deviations.

Do not skip step 2, and do not batch steps 3 and 4 into a single unreviewable change.

## Screenshot harness

```
flutter test tool/screenshots
dart run tool/screenshots/build_index.dart
```

The harness rasterises the widget tree. It does **not** prove the app runs, and it cannot
show motion at all. Never report a change as verified on the basis of screenshots alone —
say what the screenshots prove and what still needs a device.

## Motion

Two product motion rules that carry forward independently of the retired layout system:

- Anything spatial uses a spring and must be interruptible from its current position and
  velocity. Never `AnimationController.forward()` from zero on a retrigger.
- Nothing on the sale path may sit between an input and its record. The sale is written
  first; the animation plays over committed state.

## Reporting

Be direct about incomplete work. "Steps 1–3 done, step 4 blocked because X" is useful.
A summary that implies more is finished than is finished costs more than the work saved.
