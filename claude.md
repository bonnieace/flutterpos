# CLAUDE.md

Instructions for Claude Code working in this repository. Keep this file short — it loads
on every turn, and length here costs context on every task.

## Who decides

**The developer is the source of truth and the planner of the work.** What they ask for in the
current conversation outranks every document in this repository, including this one. If a doc and
the developer disagree, the developer is right and the doc is out of date.

**Every document in this repo is history or reference, not authority.** That includes `PLAN.md`,
`HISTORY.md`, everything under `docs/stitch/**`, `design.md`/`DESIGN.md`, and every root `*.md`
review, audit and proposal. They are useful for *why* something was built the way it was. They do
not describe what to build next, and they must not be quoted back at the developer as a constraint
on a request they just made.

- **`PLAN.md` is retired.** It froze on 2026-08-23 and was never brought forward. Do not read it
  as current state, do not treat its status board or "standing decisions" as binding, and do not
  update it.
- **`HISTORY.md` is the record, and the developer decides when it is written.** Do not append to
  it unasked.
- **The Stitch redesign is retired**, along with its phase briefs, handovers, open questions,
  coverage and audit trail. The pre-multitenancy app's look and flow (`lib/pos/**`,
  `lib/screens/**` — read-only reference) is what recent work has been rebuilding on the
  multitenant backend, and the developer directs that screen by screen.

Do not go looking for a document to authorise a decision. Ask the developer, or make the ordinary
call and say which you made.

## Rules that are about the code

These hold unless the developer says otherwise on a given task.

1. **A UI change never changes behaviour.** No repository calls, no state logic, no routing
   conditions, no API shapes in a visual change. If a screen cannot be restyled without a logic
   change, stop and describe the coupling.
2. **No hardcoded values in widgets.** Colours, sizes, radii, spacing, durations and springs come
   from `AppTokens`. Extend the token layer rather than inlining a literal.
3. **Do not touch `lib/pos/**` or `lib/screens/**`.** Legacy, read-only. **Eight more locations
   are equally unreachable** — including a `pill` component set and two rival colour systems.
   `test/dev/reachable_lib_test.dart` holds the list and fails if it changes; read it before
   restyling anything outside `lib/ui/`.
4. **Accessibility is pass/fail.** Contrast, 48dp targets, focus rings, and status never conveyed
   by colour alone.
5. **A component ships with the states it can be in** — enabled, hover, focus-visible, pressed,
   disabled, loading, error, read-only, empty, whichever apply.

## Motion

- Anything spatial uses a spring and must be interruptible from its current position and velocity.
  Never `AnimationController.forward()` from zero on a retrigger.
- Nothing on the sale path may sit between an input and its record. The sale is written first; the
  animation plays over committed state.

## Screenshot harness

```
flutter test tool/screenshots
dart run tool/screenshots/build_index.dart
```

It rasterises the widget tree. It does **not** prove the app runs, and it cannot show motion.
Never report a change as verified on screenshots alone — say what they prove and what still needs
a device.

## Device runs

```
dart run tool/lan_debug_build.dart          # reads this machine's IP, syncs the cleartext
adb install -r --no-streaming build/app/outputs/flutter-apk/app-debug.apk
```

The emulator host and the cleartext allowlist are compiled into the APK, so a DHCP lease change
means a rebuild. `GRADLE_USER_HOME=D:\gradle-home` on this machine, or the build fills `C:`.

## Reporting

Be direct about incomplete work. "Steps 1–3 done, step 4 blocked because X" is useful. A summary
that implies more is finished than is finished costs more than the work saved.
