# CLAUDE.md

Instructions for Claude Code working in this repository. Keep this file short — it loads
on every turn, and length here costs context on every task.

## The design system

`DESIGN.md` in the repo root is the source of truth for all visual work. Read it before
any change to a widget, a colour, a size, or a layout. Do not summarise it into the code
and do not work from memory of it — open it.

If a task requires a value that `DESIGN.md` does not define, stop and say so. Do not
invent a token. The correct outcome is a question, not a plausible hex code.

## Hard rules

1. **A UI change never changes behaviour.** No repository calls, no state logic, no
   routing conditions, no API shapes in a visual pull request. If a screen cannot be
   restyled without a logic change, stop and describe the coupling.
2. **No hardcoded values in widgets.** Every colour, size, radius, spacing, duration and
   spring comes from the token layer. A literal hex or a magic number in a widget is a
   defect regardless of whether it looks right.
3. **Do not touch `lib/pos/**` or `lib/screens/**`.** Legacy, read-only, out of scope.
4. **One step per branch.** The migration order in `DESIGN.md` §11 is numbered. Do one
   number. Do not begin the next because it seems related.
5. **Every component ships with its full state matrix** — enabled, hover, focus-visible,
   pressed, disabled, loading, error, read-only, empty, whichever apply — and each state
   appears in the screenshot harness. A component missing a state is not done.
6. **Accessibility is pass/fail.** See §9. Contrast, 48dp targets, focus rings, and
   status never conveyed by colour alone are requirements, not preferences.

## Workflow for any visual change

1. Read the relevant sections of `DESIGN.md`.
2. State the plan and the file list before writing code. Wait for confirmation.
3. Implement.
4. Regenerate the screenshots and report which images changed.
5. Report anything you had to deviate from, and why.

Do not skip step 2, and do not batch steps 3 and 4 into a single unreviewable change.

## Screenshot harness

<!-- Fill in the actual command from screenshots/README.md -->

```
# regenerate:
# diff:
```

The harness rasterises the widget tree. It does **not** prove the app runs, and it cannot
show motion at all. Never report a change as verified on the basis of screenshots alone —
say what the screenshots prove and what still needs a device.

## Motion

`DESIGN.md` §6. Two rules that are easy to get wrong:

- Anything spatial uses a spring and must be interruptible from its current position and
  velocity. Never `AnimationController.forward()` from zero on a retrigger.
- Nothing on the sale path may sit between an input and its record. The sale is written
  first; the animation plays over committed state.

## Reporting

Be direct about incomplete work. "Steps 1–3 done, step 4 blocked because X" is useful.
A summary that implies more is finished than is finished costs more than the work saved.