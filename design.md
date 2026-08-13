# Design system

**Status:** v0.1 — proposed. Not yet implemented.
**Scope:** every screen the tenant app can reach. Excludes `lib/pos/**` and `lib/screens/**` (legacy, read-only).

---

## 0. How to use this document

This file is the source of truth. `lib/ui/records.dart` is its implementation, not its
origin. The order of operations for any visual change is:

1. Change this document.
2. Change the token file to match.
3. Change the widgets.
4. Regenerate `screenshots/` and diff the images.

A pull request that changes a colour, a size, or a component's behaviour without a
corresponding diff to this file should be rejected. That rule is the difference between a
design system and a folder of constants.

Three things this document deliberately does **not** contain: brand strategy, marketing
palette, or anything about the website. It describes the operating surface a shopkeeper
uses at a till and an owner uses at a desk.

---

## 1. Principles

**A till is not a dashboard.** The cashier's loop is scan, confirm, take money, repeat,
under fluorescent light, one-handed, possibly at speed. Every decision on the sale path
optimises for that. The back-office screens have the opposite constraint: an owner
reconciling a week wants density, sorting, and everything visible at once. One system,
two densities. Never split the difference.

**The record is the unit.** Products, shifts, sales, ledger entries, and differences are
all immutable records that state when they were recorded and by whom. The UI's job is to
present a record faithfully, including when it cannot be read. A record that failed to
load is a first-class state, not an error page.

**Corrections are additive, and the UI must say so.** Nothing here is edited or deleted;
it is corrected by a new record. The interface should never imply otherwise — no pencil
icons, no "edit", no red X that reads as deletion.

**Colour carries meaning or it carries nothing.** The current app is one green doing
seven jobs. Every colour below has exactly one meaning, and status is never communicated
by hue alone.

---

## 2. Foundations

### 2.1 Colour

Two layers. **Primitives** are the raw values and are never referenced by a widget.
**Roles** are what widgets use. If you find yourself writing a hex value in a widget, the
role you need doesn't exist yet — add it here first.

#### Primitives

| Token | Value | Notes |
| --- | --- | --- |
| `green.950` | `#08140E` | |
| `green.900` | `#0D1F16` | existing base |
| `green.850` | `#132A1F` | existing raised |
| `green.800` | `#1C3328` | |
| `green.700` | `#1E3A2B` | existing hairline |
| `green.600` | `#2C5340` | |
| `green.400` | `#34B169` | |
| `green.300` | `#3DD47C` | |
| `mint.400` | `#45F28D` | brand accent |
| `sage.200` | `#849E8F` | |
| `sage.100` | `#A0BCAC` | |
| `sage.050` | `#B8D6C5` | |
| `white` | `#FFFFFF` | |
| `red.400` | `#FF5C6C` | already in use for out-of-stock |
| `amber.400` | `#F2C14E` | new |
| `blue.300` | `#6FB7F2` | new |

Three colours are being introduced. That is deliberate: an app that reconciles money
needs to distinguish "this is fine", "check this", and "this is wrong", and a single hue
cannot.

#### Surface roles

| Role | Value | Use |
| --- | --- | --- |
| `surface.base` | `#0D1F16` | page background |
| `surface.raised` | `#132A1F` | cards, rows, sheets |
| `surface.sunken` | `#08140E` | input wells, table header, code |
| `surface.overlay` | `#1C3328` | dialogs, menus, bottom sheets |
| `surface.scrim` | `#000000` @ 60% | behind overlays |
| `border.subtle` | `#1E3A2B` | hairlines, card edges |
| `border.strong` | `#2C5340` | inputs, secondary buttons, focus targets |

Depth is expressed by surface step, never by drop shadow. On a near-black background a
shadow is invisible and only costs raster time.

#### Text roles

Measured against `surface.base` / `surface.raised`.

| Role | Value | Contrast | Use |
| --- | --- | --- | --- |
| `text.primary` | `#FFFFFF` | 17.1 / 15.2 | headings, figures, record titles |
| `text.secondary` | `#B8D6C5` | 11.0 / 9.8 | body copy, default label colour |
| `text.tertiary` | `#849E8F` | 5.9 / 5.3 | metadata, timestamps, helper text |
| `text.disabled` | `#5D7468` | 3.4 / 3.0 | disabled labels only |

`text.tertiary` is the floor for anything a person is expected to read.
`#5D7468` and `#607A6C` currently appear as caption text on the catalog, pagination, and
ledger metadata — both fail AA at 3.4 and 3.7. They are permitted only on disabled
controls, where WCAG exempts them.

#### Action roles

The single biggest change in this document. Four tiers, visually distinct at a glance,
and **secondary actions stop being mint.**

| Tier | Container | Label | Border | Use |
| --- | --- | --- | --- | --- |
| `action.primary` | `#45F28D` | `#0A0F0C` (13.2:1) | none | exactly one per screen region |
| `action.secondary` | transparent | `#B8D6C5` | `#2C5340` | the ordinary case |
| `action.tertiary` | transparent | `#45F28D` | none | inline, low-commitment |
| `action.destructive` | transparent | `#FF5C6C` | `#FF5C6C` | removes or reverses |

Interaction states, applied as an overlay on the container:

| State | Primary | Secondary / tertiary / destructive |
| --- | --- | --- |
| hover | `#3DD47C` | label colour @ 8% |
| pressed | `#34B169` | label colour @ 12% |
| focus-visible | 2px `#45F28D` ring, 2px offset | same |
| disabled | container `#1E3A2B`, label `#5D7468` | label `#5D7468`, border `#1E3A2B` |
| loading | container held, label replaced by 16px spinner in label colour, width frozen | same |

The rule that fixes the sale screen: **Clear this sale** is `destructive`, **Save sale**
is `primary`. Today the destructive action is the more prominent of the two.

#### Status roles

Each status is a triple. Status is always rendered as a container plus a label plus a
shape — never as coloured text alone, because roughly 1 in 12 men cannot separate your
red from your green, and this app is about money.

| Status | `fg` | `bg` (on base) | `border` | Meaning |
| --- | --- | --- | --- | --- |
| `status.ok` | `#45F28D` | `#143824` | `#2C5340` | reconciled, confirmed, in stock |
| `status.attention` | `#F2C14E` | `#28321D` | `#5A4C24` | unreconciled, pending, awaiting |
| `status.problem` | `#FF5C6C` | `#2A2620` | `#6B3238` | difference found, unreadable, out of stock |
| `status.info` | `#6FB7F2` | `#193130` | `#2E4C60` | offline, read-only, informational |
| `status.neutral` | `#849E8F` | `#1C3328` | `#1E3A2B` | archived, retired, closed |

All five `fg` values clear 5:1 on both surfaces.

Note the deliberate collision: `status.ok` and the brand accent are the same mint. That
is fine *because* status always appears in a bordered container and an action never does
— the container is what disambiguates them. Do not remove the container to "clean it up".

### 2.2 Typography

One family — Roboto — with a real scale. Two additions matter more than the sizes.

**Tabular figures are mandatory** anywhere numbers stack vertically: prices, totals, stock
counts, transaction counts, ledger deltas, percentages. `fontFeatures: [FontFeature.tabularFigures()]`.
Today's daily summary has proportional figures in a column of currency, which is why the
amounts look ragged.

**Record identifiers are monospace.** SKUs, `rj_000001`, `pd-milk-500`, `shift-yesterday`.
They are strings a person compares character by character, not prose.

| Role | Size / line | Weight | Use |
| --- | --- | --- | --- |
| `display` | 32 / 40 | 700 | screen title, expanded only |
| `title.lg` | 22 / 28 | 500 | screen title (compact), section head |
| `title.md` | 18 / 24 | 500 | card title, record name |
| `body.lg` | 16 / 24 | 400 | primary body, till-facing copy |
| `body.md` | 14 / 20 | 400 | back-office body, table cells |
| `label.lg` | 15 / 20 | 600 | button labels |
| `label.md` | 13 / 16 | 600 | chips, tabs, table headers |
| `label.eyebrow` | 11 / 16 | 700, +0.8 tracking, uppercase | field group labels only |
| `caption` | 12 / 16 | 400 | timestamps, attribution |
| `numeric.hero` | 28 / 32 | 700, tabular | the one figure a stat tile exists for |
| `numeric.body` | 14 / 20 | 500, tabular | money and counts in flow |
| `mono` | 13 / 18 | 400, monospace | record IDs, SKUs |

Uppercase is restricted to `label.eyebrow`. `UNLOCK REGISTER` on the sign-in screen is
both the wrong case and the wrong words.

### 2.3 Spacing, size, radius

4pt base. **A spacing token is named by its value** — `space.4` through `space.64`.
Permitted values only: 4, 8, 12, 16, 20, 24, 32, 40, 48, 64. Nothing else.

The naming is stated because this section used to name tokens by *index* — "`space.1` = 4
through `space.16` = 64" — while §3 asks for a section gap of `space.24` and §5.2 for
padding of `space.20` and `space.16`, which are values. The two collide on the name
`space.16`, meaning 64 under one reading and 16 under the other, and only the value
reading is coherent: under the index reading §3 gives the *compact* density a larger
section gap than the comfortable one, and `space.24` is not on the scale at all.

| Radius | Value | Applies to |
| --- | --- | --- |
| `radius.sm` | 8 | chips, badges, inputs |
| `radius.md` | 12 | cards, rows, sheets |
| `radius.lg` | 20 | dialogs, bottom sheets |
| `radius.pill` | 999 | buttons only |

Pill buttons are the signature and should stay. But when *everything* is a pill —
buttons, chips, filters, cards, inputs — the shape stops signifying. Restrict `pill` to
buttons; chips and inputs drop to `radius.sm`. This alone will make the home screen
legible.

### 2.4 Motion

Anything that moves in space is driven by a **spring**, not a duration. Anything that
only changes opacity or colour uses a duration. This split is the single largest
contributor to an interface reading as iOS rather than as Material: a duration-and-curve
animation cannot be interrupted gracefully, and interruptibility is what makes a surface
feel like it has weight rather than like it is playing a video of itself.

#### Springs — for anything spatial

| Token | Stiffness | Damping | Mass | Use |
| --- | --- | --- | --- | --- |
| `spring.snappy` | 380 | 32 | 1 | press states, chips, toggles, stepper |
| `spring.smooth` | 220 | 30 | 1 | sheets, panes, route transitions, expansion |
| `spring.gentle` | 140 | 24 | 1 | large surfaces, hero figures |
| `spring.bouncy` | 260 | 18 | 1 | reward layer only — see §6.2 |

All are critically or near-critically damped except `spring.bouncy`. Overshoot is a
reward signal; on an operational surface it reads as instability.

#### Durations — for opacity and colour only

| Token | Duration | Curve |
| --- | --- | --- |
| `motion.instant` | 80ms | linear |
| `motion.short` | 160ms | `easeOutCubic` |
| `motion.medium` | 240ms | `easeInOutCubic` |
| `motion.long` | 320ms | `easeInOutCubic` |

#### Rules

**Every animation is interruptible.** A spring retargets from its current position and
velocity; it never restarts from zero and never has to finish. If a person taps twice,
the second tap takes over mid-flight.

**Gestures own their surfaces.** Sheets, panes, and back-navigation follow the finger 1:1,
rubber-band past their bounds, and settle on release velocity rather than on release
position. A sheet that only opens and closes on tap is not the same product.

**Continuity over replacement.** When a record opens, its row expands into the detail
surface — the identity element keeps its position and grows. Nothing cross-fades between
two unrelated layouts.

**No ink ripples.** Replace `InkWell` with an opacity-plus-scale state overlay
(`0.97` scale, `spring.snappy`). The expanding Material ripple is the loudest tell that
an app is not iOS, and it is currently on every control in the app.

**Bouncing scroll physics everywhere**, on both platforms. No Material overscroll glow.

**Frame budget.** 60fps floor on the target device tier (§6.5); 120fps where the display
allows. A frame missed on the sale path is a defect, not a polish item.

Under `MediaQuery.disableAnimations`: springs collapse to instant, durations to 0,
animated assets render their final frame as a static image.

---

## 3. Density

Two modes. Density is a property of the *surface*, chosen by the screen, not by the user.

| | `density.comfortable` | `density.compact` |
| --- | --- | --- |
| Where | sale, shift, sign-in, all compact-width screens | catalog, ledger, reconciliation, activity log, staff — at ≥1024 |
| Row height | 64 min | 40 min |
| Row padding | 16 / 16 | 12 / 8 |
| Body role | `body.lg` | `body.md` |
| Tap target | 48 × 48 | 32 × 32 (pointer only) |
| Section gap | `space.24` | `space.16` |

`density.compact` is only reachable on a pointer device at expanded width. A touch device
never gets 32px targets, whatever its width.

---

## 4. Layout and the responsive contract

### 4.1 Breakpoints

| Name | Range | Notes |
| --- | --- | --- |
| `compact` | < 768 | phone. Current `mobile/` screenshots. |
| `medium` | 768 – 1023 | tablet, split-screen |
| `expanded` | ≥ 1024 | desktop. Current `web/` screenshots. |

These replace `tenantWideLayoutBreakpoint` (768) and `tenantTableBreakpoint` (1024) with
the same numbers under one name, so a screen consults one variable.

**Done 2026-08-12**, in step 6. The one variable is `AppLayout` in `lib/ui/tokens.dart`,
reached as `AppTokens.layout` where a widget has a context. It absorbed a **third**
mechanism the table above did not know about — `login_screen.dart` computed `width < 768`
inline — and the numbers did not move. A band is resolved from a **screen** width, not
from a widget's own `BoxConstraints`: the ranges above describe the surface a person is
looking at, and resolving them inside a padded page invents a fourth boundary by
arithmetic.

### 4.2 Content width

**Every screen has a max content width.** This is the fix for the catalog row whose
"Correct" link sits 1,300px from the product name it belongs to.

| Surface | Max width | Alignment |
| --- | --- | --- |
| Reading and forms | 720 | centred |
| Record lists and tables | 1200 | centred |
| Sale (two-pane) | full | products flex, cart pane fixed 420 |

**Done 2026-08-12**, in step 6, for all 25 migrated routes at once — the sale is step 7's
and is the one row still unclaimed. Which row a page is, is a **required** argument to
`AppScaffold`, not a default: this table gives a form and a table different maxima, so
there is no value that is right when a call site says nothing. The toolbar is
deliberately outside the constraint; the header and the body are inside it together.

### 4.3 The responsive contract

This is the part the current app is missing, and the reason the README's claim about
tables isn't true on screen. Every list-bearing component declares what it *becomes* at
each breakpoint, and that declaration lives with the component, not with the screen:

| Component | compact | medium | expanded |
| --- | --- | --- | --- |
| `RecordList` | stacked cards | two-column cards | data table |
| `ActionSet` (>3) | overflow menu | overflow after 3 | all inline |
| `StatRow` | horizontal scroll | 2-up grid | n-up row |
| `FilterChips` | horizontal scroll, one line | wrap | wrap |
| `Form` | single column | single column | single column, 720 max |
| `Sale` | products + cart sheet | products + cart sheet | two panes |

A screen that renders a `RecordList` gets the right form for free. **A screen cannot opt
out of the form**; if it needs a different one, that's a new component and it gets
specified here.

**It does decide what the narrow form loses, and that is the one concession this table
makes.** `DESIGN-AUDIT.md` §6 decision 2, taken 2026-08-11 and applied here 2026-08-13. A
table has room for six columns and a stacked card does not, and only the screen knows
which of its columns are the ones a person came for — the audit that opened this
concession quotes `lib/ui/records.dart` making the same argument in its own comments a day
before this document was written. So: **the component owns the form, the caller owns the
loss.** In the code that is one flag per attribute, and an attribute that drops out of the
narrow form is a decision visible in the call site rather than in a layout rule nobody can
find.

The limit of the concession is that it is per *attribute*. Identity, status, provenance
and actions are on every rendering at every band; there is nothing to opt out of and no
argument for dropping any of them.

**Done 2026-08-13**, in step 6's second half, as `RecordList` in
`lib/ui/record_list.dart`, with the **activity log** as its first consumer and the **staff
directory** as its second, later the same day — then the two **catalog** screens, then the whole
**stock family** (21–24). Step 6's list above is **twelve** screens, so **four remain** — 30, 32, 33
and 34, the shift family — and they are a sweep, the way `AppButton`'s 133 call sites were. This
count was left stale by the catalog chunk and is corrected here rather than carried.
`ActionSet` is built with it, `StatRow` is step 8's, and `FilterChips`, `Form` and `Sale`
are unclaimed.

The staff directory is the screen this row was written about: it was the only one that made §4.3's
choice itself, with two separate builders under a breakpoint test that showed the two bands
*different information*. It also needed one thing this document does not specify — somewhere to put
a form a record opens — and that is `RecordItem.details`, named in the component as the component's
own addition rather than added here as a sixth row of §5.2.

### 4.4 Navigation

The home screen is currently a `Wrap` of ten identical pills that breaks into a ragged
centred stack on a phone. Replace with a fixed model:

- **compact**: bottom navigation, four destinations — *Sell*, *Stock*, *Money*, *More*.
  The shift control is a persistent banner above the bar, not a destination.
- **medium**: navigation rail, same four.
- **expanded**: navigation rail expanded with labels.

*Sell* is the landing route for a cashier; *Money* for an owner. Everything currently on
the home screen maps into one of the four or into *More*. **New sale** ceases to be a
button among eleven and becomes the default screen for the role that needs it.

---

## 5. Components

Every component specifies all applicable states. A component is not "done" until each row
below exists in the widget and appears in the screenshot harness.

**State matrix:** `enabled` · `hover` · `focus-visible` · `pressed` · `disabled` ·
`loading` · `error` · `read-only` · `empty`

### 5.1 Inventory

| Component | Replaces (current) | Priority |
| --- | --- | --- |
| `AppScaffold` | ad-hoc `Scaffold` per route | 1 |
| `PageHeader` | duplicated title + subtitle | 1 |
| `AppButton` (4 tiers × 3 sizes) | mixed `FilledButton` / `OutlinedButton` / `TextButton` | 1 |
| `AppTextField` | mixed placeholder-label and floating-label fields | 1 |
| `AppSelect` | raw `DropdownButtonFormField` | 1 |
| `RecordCard` / `RecordRow` / `RecordTable` | hand-built card lists | 1 |
| `StatusBadge` | inline coloured text | 1 |
| `StatTile` | "recorded stock" / "ledger entries" tiles | 2 |
| `FilterChipBar` | hand-built chip `Wrap` | 2 |
| `EmptyState` | prose paragraph | 2 |
| `ErrorState` | "could not be read" prose | 2 |
| `LoadingState` | bare `CircularProgressIndicator` | 2 |
| `Disclosure` | permanent helper paragraphs | 2 |
| `Callout` | permanent notice paragraphs | 2 |
| `ConfirmDialog` | none — destructive actions are unconfirmed today | 2 |
| `AppSheet` | ad-hoc `showModalBottomSheet` | 2 |
| `Pagination` | low-contrast Previous / Page N / Next | 3 |
| `AppTabs` | platform tabs | 3 |
| `LedgerEntry` | hand-built ledger rows | 3 |
| `QuantityStepper` | minus + delete, no plus | 1 |
| `PressSurface` | `InkWell` ripples | 1 |
| `MotionAsset` | none | 2 |
| `RollingNumber` | static `Text` on totals and counts | 2 |
| `SyncIndicator` | five-line offline queue list | 2 |

### 5.2 Specifications for the load-bearing five

#### `AppButton`

Sizes: `sm` 32h / `md` 40h / `lg` 48h. Touch surfaces use `lg` only. Label is
`label.lg`, sentence case, always a verb phrase naming the effect. Leading icon 18px,
optional; trailing icon reserved for disclosure. Minimum horizontal padding `space.20`,
`space.16` when an icon is present.

Loading freezes the measured width before swapping the label, so a button does not resize
mid-press.

#### `AppTextField`

One pattern, everywhere: persistent label above the field (`label.md`, `text.secondary`),
`surface.sunken` well, `border.strong` 1px, `radius.sm`, 48h at comfortable density.
Placeholder is an *example*, never a restatement of the label — the sign-in screen
currently uses the placeholder as the label on one field and a floating label on another.

Helper text is `caption` / `text.tertiary`, one line. Anything longer becomes a
`Disclosure`. Error replaces helper text, `status.problem.fg`, with the border switching
to `status.problem.border` — never colour alone: the message must state what to do.

Counters (`0/120`) render only above 80% of the limit.

#### `RecordCard` / `RecordRow` / `RecordTable`

One component, three renderings, chosen by breakpoint per §4.3. Contract:

- **Identity** — `title.md`, `text.primary`. Never truncated below two lines.
- **Attributes** — `body.md` / `text.secondary`, key-value or bulleted-inline.
- **Status** — a `StatusBadge`, leading position.
- **Provenance** — `caption` / `text.tertiary`. "Recorded {ts} by {actor}".
- **Actions** — an `ActionSet`. On compact, an overflow menu; never bare text links.

The `Correct` / `Retire` text links on the catalog fail this on two counts: 20px targets
on a touch surface, and destructive-adjacent actions rendered identically.

**Done 2026-08-13**, as one `RecordList` in `lib/ui/record_list.dart` rather than three
widgets: the three names above are three *renderings* by §4.3's own words, so they are one
component and a form resolved from the screen width, not three call sites a screen chooses
between. The five rows above are the model — `RecordItem` carries an identity, a
`RecordStatus`, a list of `RecordAttribute`, a provenance line and a list of
`RecordAction`, and every rendering is a way of laying those five out.

Two readings this specification left open, decided in the component and recorded rather
than buried. **"Status — leading position"** is read as *first in the record*, so the badge
sits above the identity on a card and in the first column of a table; it is the thing a
person scans a list for. **"Never truncated below two lines"** is read as a floor rather
than a ban — an identity gets two lines before it ellipsises, where every other line on a
record gets one.

The catalog is not yet on it. Its `Correct` / `Retire` links are in the sweep that follows,
and what fixes them is `ActionSet`: a record's actions are `AppButton`s at 48dp, and a
`destructive` one takes §2.1's destructive tier instead of looking like its neighbour. **The staff
directory proved that half on 2026-08-13** — its five 40dp icon buttons with tooltips became 48dp
labelled actions, with the invitation cancellation and the deactivation on the destructive tier —
and the catalog is the next screen in the sweep.

#### `StatusBadge`

`radius.sm`, `label.md`, 24h, icon 14px leading, `space.8` padding. Uses the full status
triple. The icon is required — it is what makes the status legible without colour.

#### `Disclosure`

The single highest-value component here. Collapsed: one line, `body.md`, with a leading
info glyph and a chevron. Expanded: the full explanation, `body.md` / `text.secondary`.

The app's explanatory copy is unusually good and should be *kept* — but "One correction
can be applied across many products…" and the four-line stock-adjustment explanation are
permanent body text today, which is what makes the catalog form three times taller than
it needs to be. Move them inside `Disclosure` and the writing survives while the screen
becomes usable.

---

## 6. Motion in practice

### 6.1 Two references, one system

The brief names two influences that pull in opposite directions, and both are right about
different parts of the app.

**iOS is the everyday layer.** Restraint, physics, spatial continuity, gesture ownership.
It applies to every interaction a cashier performs more than once a day. This is where
"slick" actually comes from, and almost none of it involves an animation file — it is
springs, interruptibility, gestures, scroll physics, and haptics. If §2.4 is implemented
well and no animated asset is ever added, the app will already feel substantially more
expensive than it does now.

**Duolingo is the reward layer.** Character, overshoot, celebration, personality. It
applies to moments that happen a handful of times per person per week.

The governing principle: **reward scales inversely with frequency.** Duolingo's animation
works because a person opens it voluntarily for ten minutes a day. A cashier records two
hundred sales in a shift. Anything delightful at repetition one is torture at repetition
two hundred, and a shopkeeper who cannot get through a queue because the app is
celebrating will uninstall it. Frequency, not importance, decides whether a moment gets
character.

| Frequency | Layer | Treatment |
| --- | --- | --- |
| Many times per shift — add to cart, save sale, scan | everyday | spring + haptic only. No asset. |
| Few times per shift — open shift, close shift, cash count | everyday+ | spring + haptic + a short one-shot mark |
| Few times per week — reconciliation result, stock import | reward | full asset, one-shot |
| Few times ever — first sign-in, business approved, first product | reward | full asset, character permitted |

### 6.2 Motion inventory

| Interaction | Motion | Token | Haptic |
| --- | --- | --- | --- |
| Any press | scale 0.97 + overlay | `spring.snappy` | `selectionClick` |
| Chip select | fill expands from tap point | `spring.snappy` | `selectionClick` |
| Add to cart | product tile lifts; cart row inserts, height springs open | `spring.snappy` | `lightImpact` |
| Quantity change | digit rolls vertically, tabular so width is fixed | `spring.snappy` | `selectionClick` |
| Total recalculates | digits roll; only changed digits move | `spring.smooth` | none |
| Remove from cart | row collapses to zero height, contents fade first | `spring.smooth` | `lightImpact` |
| Save sale | button label → spinner → check, width frozen; cart collapses | `spring.smooth` | `mediumImpact` |
| Open a record | row expands into detail, identity element continuous | `spring.smooth` | `selectionClick` |
| Sheet drag | follows finger, rubber-bands, settles on velocity | `spring.smooth` | `lightImpact` at detent |
| Route push (compact) | horizontal, incoming full / outgoing parallax at 30%, back-swipe from edge | `spring.smooth` | none |
| Route change (expanded) | fade-through, no horizontal travel | `motion.medium` | none |
| Pane resize | width springs | `spring.gentle` | none |
| Filter applied | list cross-fades; rows that persist do not move | `motion.short` | `selectionClick` |
| Pull to refresh | rubber-band, custom indicator, not the Material arc | `spring.smooth` | `lightImpact` at trigger |
| Large title collapse | title scales into the app bar on scroll | driven by scroll offset | none |
| Error appears | field border colour + message slides down from behind | `motion.short` + `spring.snappy` | `notification.error` |
| Shift opened | one-shot mark, ≤900ms, non-blocking | asset | `mediumImpact` |
| Cash count result | state machine: balanced / short / over | asset | `notification.success` or `.warning` |
| Reconciliation result | state machine: clean / differences found | asset | `notification.success` or `.warning` |
| Business approved | full celebration, character permitted | asset, `spring.bouncy` | `notification.success` |

### 6.3 The sale-path rule

**No animation may sit between an input and its record.** The sale is written first; the
animation plays over the already-committed state. A cashier can start the next scan while
the previous confirmation is still on screen, and doing so cancels it without penalty.

Concretely: *Save sale* does not wait for the check mark. The check mark is a report that
something already happened.

Total motion-attributable latency on scan → cart → save must be zero. This is testable and
should be tested.

### 6.4 Animated assets

**Default position: build them in Flutter, not in an animation tool.**

Six of the eight approved assets below are state indicators — a check mark that draws on,
a sync glyph with four states, a small empty-state mark. Flutter draws these natively with
`CustomPainter`, `AnimatedBuilder`, and the spring tokens in §2.4. Doing so costs nothing,
adds no dependency, adds no payload, and — the reason that actually matters — **an asset
authored in an external tool bakes its colours in.** Every hex in §2.1 is a role that can
change. A natively drawn indicator reads its colour from the theme and follows a palette
change for free; a `.riv` or `.json` file has to be re-authored and re-exported. With
eight assets and a system still at v0.2, that is a maintenance liability, not a detail.

Only two things on the list genuinely want an animation tool: the brand mark and the
business-approval celebration. Both are one-shots, both are seen rarely, and both are the
only places character is permitted.

#### If you do commission assets, use Rive

The brief names Duolingo, which is the strongest argument for it: <cite index="27-1">Duolingo moved its interactive characters to Rive and reported roughly a fifteenfold file-size reduction alongside better performance and interactivity.</cite>
The look being asked for is a Rive look.

The technical case matters here because of where this app runs. <cite index="26-1">Lottie is a JSON keyframe recording the runtime replays, with each instance driving its own ticker even when nothing on screen changes; Rive is a binary file containing a state machine, and comparable icon-scale assets are typically three to five times smaller.</cite>
One benchmark on an older Android device put the same animation at <cite index="29-1">roughly 17fps under Lottie and roughly 60fps under Rive</cite> — directional rather than a measurement of your assets, but the direction is consistent across sources.

**On cost.** Rive is freemium and the ceiling is low. <cite index="12-1">The editor, fonts, and runtimes are free; there is no runtime fee, and exported files keep working forever. Cadet, at $9 per month billed annually or $17 monthly, is the tier that permits shipping exports.</cite>
<cite index="11-1">The free plan covers learning, personal files, and up to three collaborative files, but exports are what the paid tiers unlock.</cite>
So the real cost of the two assets that need a tool is **one month of Cadet — $17 —
provided you author both in the same month.** Exports do not stop working when the
subscription does. If you are studying, <cite index="12-1">Rive grants export access for qualified educational use on request.</cite>

**Lottie is not the cheaper escape hatch.** Its authoring path is After Effects, which
costs more per month than Rive Cadet and never stops costing it. Free Lottie files from
public libraries exist, but they are generic mascots that will not match this palette or
this product, and using one is worse than using nothing.

Rive's other cost is real and non-monetary: it is a separate editor with its own learning
curve, and <cite index="25-1">complex animations cannot be reliably imported from Lottie — they get rebuilt.</cite>
Budget a weekend, not an afternoon.

#### Asset budget

| Constraint | Value |
| --- | --- |
| Total animated assets | ≤ 8 |
| Externally authored assets | ≤ 2 |
| Total external payload | ≤ 120KB |
| Any single external asset | ≤ 64KB |
| Concurrent playing assets | 1 |
| Idle loops on an operational screen | 0 |
| Assets on the sale path | 0 |

Every external asset is precached at start and rendered at a fixed logical size — never
`Expanded`, never sized by the layout, because an artboard resized every frame
re-tessellates every frame.

#### Approved assets

| # | Asset | Built as | Where |
| --- | --- | --- | --- |
| 1 | Brand mark | external, one-shot 600ms | sign-in, app open |
| 2 | Shift state — closed / open / counting | native | shift banner |
| 3 | Cash count result — balanced / short / over | native | close shift |
| 4 | Sync state — offline / syncing / synced / attention | native | global indicator |
| 5 | Reconciliation result — clean / differences | native | reconciliation status |
| 6 | Empty state, 4 variants | native | products, sales, differences, staff |
| 7 | Business approval celebration, character permitted | external, one-shot | onboarding |
| 8 | First product added | native, one-shot 900ms | catalog, once per business |

Everything not on this list is a spring and a haptic. Adding a ninth requires removing one
or amending this table. Promoting a native asset to an external one requires a reason
written down here.

The `MotionAsset` component abstracts the difference: a caller asks for asset 4 in state
`syncing` and does not know or care which implementation answers. That indirection is what
lets you start entirely native and promote individual assets later without touching the
screens.

#### Banned

- Confetti, coins, or celebration of any kind on a screen that displays money. A sale is
  not an achievement; it is a record. Celebrating the two-hundredth sale of a shift is
  condescending, and celebrating a figure that reconciliation may later correct is
  actively misleading.
- Character reactions to routine actions.
- Animated illustrations on error and failed-to-read states. A person looking at
  "2 sale lines could not be read" needs information, not a sad mascot.
- Autoplaying loops anywhere a person is reading numbers.
- Animation used to mask latency. If something is slow, fix the something.

### 6.5 Haptics

| Token | Trigger |
| --- | --- |
| `selectionClick` | chips, tabs, stepper, keypad, filter |
| `lightImpact` | add to cart, remove, sheet detent, refresh trigger |
| `mediumImpact` | sale saved, shift opened, shift closed |
| `notification.success` | reconciliation clean, cash count balanced |
| `notification.warning` | difference found, count short or over |
| `notification.error` | submission rejected, record unreadable |
| `heavyImpact` | never |

Haptics are iOS-first by nature; Android's actuator is coarser and the same call reads as
a buzz on some handsets. Gate the notification tier behind a platform check and a user
setting, defaulting on for iOS and off for Android below the full tier.

### 6.6 Device tiers

Motion degrades by tier rather than switching off. Tier is resolved once at start from
platform, refresh rate, and available memory, and is user-overridable in settings.

| Tier | Springs | Gestures | Assets | Blur |
| --- | --- | --- | --- | --- |
| `full` | all | all | all | permitted, ≤ 2 surfaces |
| `reduced` | all | all | one-shots only, no state loops | none |
| `minimal` | instant | all | static final frame | none |

Gestures never degrade. A drag that stops following the finger is worse than no animation
at all.

Backdrop blur is the one iOS idiom to be careful with: it is expensive, and on a
near-black green surface it buys very little. Use `surface.overlay` instead, and reserve
blur for the sheet scrim on `full` tier only.

---

## 7. Patterns

**Page.** `PageHeader` (title, optional subtitle, optional primary action) →
optional `Callout` → filters → content → pagination. Title appears once. Today several
screens render the title in the app bar *and* again as an `H1` directly beneath it.

**Destructive action.** Never immediate. `action.destructive` opens a `ConfirmDialog`
naming the specific record and the specific consequence: "Clear this sale — 3 items,
KES 135.00 will be discarded. Nothing is recorded." Confirm button is
`action.destructive`, filled. Currently *Clear this sale* fires on one tap.

**Empty.** Icon, one-line statement of what would be here, one sentence on how to create
one, and a `primary` action if the person can. Not a paragraph.

**Failure to read a record.** `status.problem` badge, the record's identifier in `mono`,
a plain statement of what could not be read, and — this matters — what is still true
despite it. "2 sale lines could not be read, so they moved no stock" is exactly right and
should be the template.

**Offline / read-only.** A persistent `Callout` in `status.info`, not prose buried in a
panel. The checkout queue counts belong in a `StatRow`, not a five-line list.

**Long copy.** Anything over two lines that explains *policy* rather than *the current
state* goes in a `Disclosure`.

---

## 8. Content rules

The app's voice is already strong. These are the rules that produce it, written down so
they survive being handed to someone else.

1. **Name things the way the shopkeeper does.** Never the way the system does.
   "Operational screens remain locked until their data access is migrated to
   tenant-scoped repositories" is a commit message on a production screen. It should read:
   "Some screens aren't available yet."
2. **State what is true, then what it means.** "Its ledger expects 10, and the product
   records 7: 3 fewer than the ledger accounts for." Keep doing this.
3. **A control names its effect.** *Save sale*, *Open shift*, *Correct this shift's
   totals*. Never *Submit*, *OK*, *Unlock register*.
4. **The verb persists.** The button says *Correct*, the dialog says *Correct*, the
   confirmation says *Corrected*.
5. **Errors don't apologise and are never vague.** No "Something went wrong."
6. **Say what is still true.** A failure message should tell the person what was *not*
   affected. This is the app's best existing instinct.
7. **Sentence case everywhere** except `label.eyebrow`.
8. **Money is always currency-coded and tabular.** `KES 135.00`, never `135`.
9. **Timestamps state their zone.** Keep `2026-08-10 02:30 UTC`.
10. **Never imply mutation.** Correct, retire, adjust, record. Not edit, delete, remove.

---

## 9. Accessibility contract

These are pass/fail, not aspirations. They should be asserted in tests, not eyeballed.

| Requirement | Value |
| --- | --- |
| Body text contrast | ≥ 4.5:1 |
| Large text (≥ 18.66px bold / 24px) and UI boundaries | ≥ 3:1 |
| Touch target | 48 × 48 dp, ≥ 8dp apart |
| Pointer target (compact density) | 32 × 32, pointer devices only |
| Focus indicator | 2px `#45F28D`, 2px offset, visible on every interactive element |
| Status conveyed by | container + icon + label. Never hue alone |
| Icon-only controls | required semantic label |
| Text scaling | legible to 200% without clipping |
| Motion | fully disabled under `disableAnimations` |
| Form errors | programmatically associated, announced |

**What "UI boundaries" means, decided 2026-08-12.** The 3:1 row applies to a boundary that
**carries meaning on its own** — not to every border that exists. A decorative edge may sit below
3:1; a boundary a person must perceive to understand the interface may not.

This was raised by step 4, which draws the container the question is about. Measured against
`surface.base`: `border.subtle` is 1.38, `border.strong` 1.97, and the five status borders sit
between 1.38 and 2.04 — so under the other reading, ten colours would be re-derived. Under this
one, nothing changes, and the reason is §2.1's own construction: a status is **container + icon +
label**, so no meaning rests on the border, and all five foreground colours clear 5:1 on both
grounds. The one boundary this file names with a number — the focus indicator — clears 3:1 at
11.71.

**This is not a licence to leave a boundary invisible.** Where a border is the *only* thing
separating two regions a person must tell apart, it carries meaning and the 3:1 row applies to it.

Known current failures: caption text at 3.4:1 and 3.7:1; `Correct` / `Retire` targets;
`Previous` / `Next` pagination; out-of-stock signalled by red text alone; no visible focus
ring anywhere in the screenshots.

---

## 10. Governance

- This file is versioned. Breaking token changes bump the minor version and are listed in
  a changelog at the bottom.
- A token is removed only after one release deprecated.
- Every component lands with its full state matrix in the screenshot harness. A component
  with an unrepresented state is incomplete.
- The screenshot diff is the review artefact. A visual PR without regenerated screenshots
  cannot be reviewed.
- Animated assets are versioned alongside code and listed in §6.4. Adding one requires
  amending that table in the same pull request. The payload budget is enforced in CI.
- **The harness cannot see motion.** Screenshots prove layout and copy; they say nothing
  about whether a spring is interruptible or whether a frame was dropped. Motion work is
  reviewed on a device with the performance overlay on, against the lowest tier you
  support, not on a simulator.
- **The harness is not a device.** Widget tests rasterise the tree; they do not prove the
  route runs — the 2026-08-08 sign-in defect was invisible to every one of them. Device
  check before merge, every time.

---

## 11. Migration order

Each step is independently shippable and independently reviewable. Do not begin the next
until the screenshots for the current one are clean.

| # | Step | Screens touched |
| --- | --- | --- |
| 1 | Token layer: roles, type, spacing, radius | none visually |
| 2 | Motion substrate: springs, `PressSurface`, scroll physics, route transitions | all |
| 3 | `AppButton`, `AppTextField`, `AppSelect` | all |
| 4 | `StatusBadge`, `Callout`, `Disclosure` | all |
| 5 | `AppScaffold` + `PageHeader` + navigation model | 10, 11, all headers |
| 6 | `RecordList` contract and content widths | 13, 17, 18, 21–24, 30, 32–35 |
| 7 | Sale path: two-pane, `QuantityStepper`, `RollingNumber`, destructive confirm | 14, 15, 16 |
| 8 | Money surfaces: `StatTile`, tabular figures, tables | 25, 26, 27, 28, 29 |
| 9 | Sign-in and onboarding | 01–08 |
| 10 | Motion assets: 6 native, 2 external, and the tier system | per §6.4 |
| 11 | Copy pass against §8 | all |
| 12 | Accessibility audit against §9 | all |

Step 1 changes no pixels if done correctly, and that is the point: it is the step that
proves the roles map cleanly onto what exists before anything moves.

Step 2 comes second, and step 10 comes ninth, deliberately. The substrate is what makes
the app feel expensive; the assets are decoration on top of it. Building the assets first
produces a slow app with nice animations in it, which is the failure mode this ordering
exists to prevent.

---

## 12. Open decisions

Recorded here rather than settled, because each needs a call you haven't made yet.

- **Is dark the only theme?** A till under a shop window in Nairobi at midday is a strong
  argument for a light mode. Doubles the colour work; decide before step 1, not after.
- **Currency and locale.** KES today. Does the type scale hold for a currency with no
  minor units, or one that needs four digits after the separator?
- **Offline as a first-class state.** The queue counts imply it matters. Does it deserve
  a persistent global indicator?
- **Role-based landing.** Cashier lands on *Sell*, owner on *Money* — or does everyone
  land on the same screen and just see different controls?
- **Printing.** Named as not-yet-existing. A receipt is a design surface with its own
  constraints and will not inherit from this document.
- **Is there a character?** Duolingo's warmth comes from a creature with opinions, not
  from the animation engine. A mascot is a brand commitment, not a motion decision, and it
  is the wrong thing to arrive at accidentally through asset 7. Decide before commissioning
  anything.
- **Who builds the Rive files?** Rive needs its own editor and its own skill. Either you
  learn it, your collaborator does, or you contract eight assets once and treat them as
  fixed. Assume the third unless you decide otherwise.
- **What is the floor device?** The tier system needs a named handset to test against.
  Everything in §6.6 is unverifiable until that exists.

---

## Changelog

**v0.3** — Animated assets default to native Flutter rather than external files, on
maintenance grounds as much as cost: an authored asset bakes its colours in and cannot
follow a token change. Two assets remain external. Budget reduced from 10 to 8.

**v0.2** — Motion. Springs replace durations for spatial animation; added §6 covering the
everyday and reward layers, the sale-path latency rule, the Rive asset budget, haptics,
and device tiers. Motion substrate moved to step 2 of migration, assets to step 10.

**v0.1** — Initial specification. Derived from the 108-screen capture of 2026-08-10.
Nothing in it is implemented yet.