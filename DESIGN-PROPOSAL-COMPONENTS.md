> # RETIRED — 2026-08-27
>
> **Not authority.** Implementation history only. **The developer is the source of truth and the
> planner of the work**; their request outranks anything written here. Kept for the reasoning it
> records.

# Five components, proposed — `design.md` §5.1's remaining rows

**Status: a proposal awaiting the product owner. Nothing here is implemented and
nothing here is binding.** Approve or redline it section by section; what survives
moves into `design.md` §5.2 and becomes the specification, and only then does any
of it get built. That is §0's order of operations, and this file exists so the
five components below stop being built-by-guessing risks.

**Why these five.** `design.md` §11 step 7 — the sale path — is half done as of
2026-08-16. The half that shipped used components that already existed. The half
that did not needs all five of these, and `PLAN.md` has carried them as "must not
be guessed at" for five days. **They are not only the till's**: four of the five
appear across the back office too, and the counts below are the whole app.

**Every measurement is from the code on 2026-08-16**, not carried. Every value
proposed is an existing §2 token unless it is flagged as **⚠ new**, and there are
three of those, each stated as a question rather than an answer.

---

## Contents

| # | Component | §5.1 priority | Call sites today | Blocking |
| --- | --- | --- | --- | --- |
| 1 | `ConfirmDialog` | 2 | **12** `AlertDialog`s, 9 files | the destructive pattern, everywhere |
| 2 | `FilterChipBar` | 2 | **20** `ChoiceChip`s, 5 files | §4.3's `FilterChips` row |
| 3 | `QuantityStepper` | **1** | 1 site, the cart line | step 7's cart |
| 4 | `AppSheet` | 2 | **1** `showModalBottomSheet` | step 7's responsive half |
| 5 | `RollingNumber` | 2 | 0 — nothing rolls yet | §6.2's two motion rows |

**Take them in that order.** It is not §5.1's priority order and the reason is the
count: `ConfirmDialog` and `FilterChipBar` are twelve and twenty call sites across
the whole app, and the other three are the till alone. §5.1 gives `QuantityStepper`
priority 1 because the *defect* is bad, not because the sweep is large.

---

## 1. `ConfirmDialog`

### What is there today

**Twelve `AlertDialog`s across nine files.** Every one is hand-built: a `title`, a
`content` paragraph, and an actions row. Since 2026-08-16 every button in them is an
`AppButton`, so the tiers are right and the shapes are not.

```text
lib/checkout/checkout_cart_panel.dart       clear this sale
lib/returns/return_history_panel.dart       restore this stock, record this return
lib/inventory/catalog_management_panel.dart retire a product, correct a product
lib/inventory/stock_adjustment_panel.dart   adjust stock
lib/inventory/bulk_catalog_panel.dart       commit a bulk change
lib/reporting/reconciliation_status_panel.dart  ask for reconciliation
lib/reporting/reconciliation_anomalies_panel.dart  correct a shift
lib/checkout/checkout_configuration_panel.dart  change the currency
lib/tenancy/tenant_routing_shell.dart       two, in the shell
```

### What `design.md` already says

§7's destructive pattern, as amended in v0.6: *"Never immediate. `action.destructive`
opens a `ConfirmDialog` naming the specific record and the specific consequence:
'Clear this sale — 3 items, KES 135.00 will be discarded. Nothing is recorded.'
Confirm button is `action.destructive`."*

§8 rule 4: *"The verb persists. The button says Correct, the dialog says Correct, the
confirmation says Corrected."*

### Proposed specification

**Surface.** `surface.overlay` (§2.1's own row for "dialogs, menus, bottom sheets"),
`radius.lg` (§2.3's row for "dialogs, bottom sheets"), `space.24` of padding,
`surface.scrim` behind it. The theme already paints `dialogTheme` at radius 20, which
is `radius.lg`, so this is ratification rather than a change.

**Content, in order, and every row required:**

| Row | Role | Rule |
| --- | --- | --- |
| Title | `title.md` / `text.primary` | The **verb**, matching the button that opened it. §8 rule 4. |
| Consequence | `body.lg` / `text.secondary` | Names the **specific record** and the **specific consequence**. §7. |
| What survives | `body.md` / `text.tertiary`, optional | §8 rule 6, "say what is still true". |
| Actions | `AppButton` × 2 | Cancel is `secondary`; confirm takes the **tier of the action that opened the dialog**. |

**The confirm tier is inherited, not chosen.** A dialog opened by a `destructive`
button confirms with `destructive`; one opened by a `primary` button confirms with
`primary`. This is the one rule that stops twelve call sites each deciding, and it
is what makes §8 rule 4 hold in shape as well as in words.

**⚠ Open question 1 — is a confirmation ever dismissible by tapping the scrim?**
Material's default is yes. For a destructive confirm, a stray tap that dismisses is
harmless (nothing happens); for a *primary* confirm mid-flow it loses typed state.
Proposed: **barrier-dismissible for destructive, not for anything else**, on the
grounds that the destructive one's cancel is the safe outcome. Needs your call.

**What it is not.** Not a place for a form. Three of the twelve dialogs above
(`correct a product`, `adjust stock`, `change the currency`) hold *fields*, and those
are a different component or a route. Proposed: **`ConfirmDialog` refuses children**
— it takes strings and two actions — and the three form-bearing dialogs stay
`AlertDialog` until somebody specifies `AppDialog`. Flagging this rather than
quietly widening the component is the whole point of writing it down first.

---

## 2. `FilterChipBar`

### What is there today

**Twenty `ChoiceChip`s across five files**, every one hand-arranged in a `Wrap`:

```text
lib/reporting/sales_totals_choosers.dart          6   period, member, category
lib/inventory/bulk_catalog_panel.dart             6   which field a bulk change moves
lib/checkout/checkout_cart_panel.dart             4   product category, plus 2 FilterChips
lib/reporting/reconciliation_anomalies_panel.dart 2   difference kind
lib/inventory/catalog_management_panel.dart       2   category
```

Plus **3 `ChoiceChip`s for tender** on the till, which are a *different* thing wearing
the same widget — see the open question below.

### What `design.md` already says

§4.3: `FilterChips` is *"horizontal scroll, one line"* at `compact`, and *"wrap"* at
`medium` and `expanded`. **No screen does this today**; all five wrap at every band.

### Proposed specification

**A chip.** `label.md`, 32 high, `space.12` horizontal padding, `space.8` between
chips in both directions.

| State | Container | Label | Border |
| --- | --- | --- | --- |
| unselected | transparent | `text.secondary` | `border.strong` |
| selected | `status.ok.bg` | `status.ok.fg` | `status.ok.border` |
| hover / pressed | label colour @ 8% / 12% | — | — |
| disabled | transparent | `text.disabled` | `border.subtle` |

**Selection carries a check glyph at 14px**, `StatusBadge`'s icon size. That is §9's
"status never by hue alone" applied to a control: a selected chip and an unselected
one must differ by more than fill. The theme already sets `checkmarkColor`, so this
is closer to ratification than it looks.

**⚠ Open question 2 — the chip radius, which is the last thing §2.3's pill argument
guards.** §2.3 as amended in v0.4 says pills are for buttons and inputs and that
*"chips, filters, badges and cards do not get it"* — so a chip is `radius.sm`, 8.
**The theme disagrees**: `chipTheme` has `shape: StadiumBorder()`, so every chip in
the app is a pill today. One of the two is wrong and `PLAN.md` has carried this as
an open decision since 2026-08-13. **Proposed: follow §2.3, `radius.sm`.** The
argument is §2.3's own — when a button, a field and a chip are all pills, the shape
has stopped meaning anything — and a chip is the only thing left still contradicting
it. This changes every chip in the app visually, so it is your call and not mine.

**⚠ Open question 3 — is the tender chooser a filter?** The till's three tender
chips (*Cash*, *M-Pesa*, *Card*) are drawn as `ChoiceChip`s but they are not filters:
a filter narrows a list you are looking at, and a tender is a **fact you are
recording about a sale**. They also carry a rule no filter has — there is deliberately
no default, because "a pre-selected payment method would be indistinguishable from an
observed one". Proposed: **they are not `FilterChipBar`** and want a
single-select control of their own, or `AppSelect`. Naming them a filter would make
"no default" a property of a component whose whole job is having one selected.

---

## 3. `QuantityStepper`

### What is there today

One site, the cart line — and §5.1 describes the defect in four words: **"minus +
delete, no plus"**. A line renders an `AppTextField` labelled `Quantity`, an
`IconButton` with a minus, and an `IconButton` with a bin. Adding a second unit means
going back to the product grid and tapping the tile again.

**Look at `mobile/15-new-sale-with-a-cart` before reading further.** §5.2's persistent
field label repeats `Quantity` down every line, which is correct and is why the cart
is as tall as it is. That is the strongest argument for this component existing.

### Proposed specification

**A single control: `−` │ value │ `+`**, replacing the field and both icon buttons.

- 48 high, which is §9's touch target and `AppButton`'s `lg`.
- The two buttons are 48 × 48, `secondary` tier, glyph only, each with a semantic
  label (§9: "icon-only controls — required semantic label").
- The value is `numeric.body`, **tabular**, centred, in a `surface.field` well at
  `radius.pill` — §5.2's own field treatment, so a stepper and a field still look
  like relatives.
- The whole control carries **one** label above it, `label.md` / `text.secondary`.
- Minimum width sized to the widest permitted value, so the row does not reflow as
  digits are added. `maximumCheckoutLineQuantity` is the bound.

**Typing stays possible.** The value is editable; the current cart's behaviour — a
half-typed number never becomes the sale, and the line keeps its last usable value —
is behaviour, not styling, and this component must not change it.

**Where the bin goes.** Out of the stepper and into the record's action set. Removing
a line is not a quantity change, and §5.2's `RecordCard` contract already has a slot
for it. At `−` on a quantity of 1, proposed: **the stepper disables rather than
deletes**, because a control that sometimes removes the row and sometimes decrements
it is the "no pencil icons, no red X that reads as deletion" problem in §1.

**Motion**, from §6.2 unchanged: *"Quantity change — digit rolls vertically, tabular
so width is fixed, `spring.snappy`, `selectionClick`"*. That is `RollingNumber`
below, so this component depends on it for the value and works without it.

---

## 4. `AppSheet`

### What is there today

One `showModalBottomSheet`, on the till, holding the cart at `compact` and `medium`.
It is Material's own: Material's drag handle, Material's radius, Material's scrim.

### What `design.md` already says

§4.3 gives `Sale` *"products + cart sheet"* at `compact` and `medium`. §2.4:
*"Gestures own their surfaces. Sheets, panes, and back-navigation follow the finger
1:1, rubber-band past their bounds, and settle on release velocity rather than on
release position. A sheet that only opens and closes on tap is not the same
product."* §6.2: *"Sheet drag — follows finger, rubber-bands, settles on velocity,
`spring.smooth`, `lightImpact` at detent."*

**That last one is why this component cannot be a restyle of the Material sheet.**
`DraggableScrollableSheet` settles on *position*, not velocity. §2.4 asks for the
opposite in as many words.

### Proposed specification

- `surface.overlay`, `radius.lg` on the top two corners only, `surface.scrim` behind.
- A drag handle: 32 × 4, `border.strong`, `radius.pill`, `space.12` above and below.
- **Detents**: `peek` (content's own height, capped at 40% of the screen), `half`
  (60%), `full` (95%, never 100% — the scrim stays visible so the sheet still reads
  as a layer). A caller names which detents it wants; the till wants `half` and `full`.
- Drag follows the finger 1:1, rubber-bands past `full` with the standard resistance,
  and settles on **release velocity** to the nearest detent in the direction of
  travel. `spring.smooth`. `lightImpact` on arriving at a detent.
- Dismissed by dragging below `peek`, by the scrim, and by back.
- Under `MediaQuery.disableAnimations`: no spring, detents snap.

**⚠ This is the largest of the five and the only one that is genuinely hard.** The
gesture-and-velocity behaviour above is a real piece of work, and the honest estimate
is that it is its own chunk rather than a component landed alongside four others.
Proposed sequencing: **specify it now, build it last**, and let step 7's responsive
half wait for it rather than shipping a Material sheet in a design-system screen.

---

## 5. `RollingNumber`

### What is there today

Nothing rolls. Every figure is a static `Text`, including the two §6.2 names.

### What `design.md` already says

§6.2, two rows: *"Quantity change — digit rolls vertically, tabular so width is
fixed, `spring.snappy`"* and *"Total recalculates — digits roll; **only changed
digits move**, `spring.smooth`, no haptic"*.

### Proposed specification

- Takes a formatted string, not a number, so the caller keeps §8 rule 8's currency
  code and the component never formats money.
- Compares the new string to the old **per character, right-aligned**, and animates
  only the positions that differ. `KES 135.00` → `KES 185.00` moves one glyph.
- Each changed position slides its old glyph out and its new one in, vertically,
  direction following the value.
- Requires a **tabular** style, and should assert it: with proportional figures the
  positions move under the animation and every digit appears to change.
- Interruptible — a second change mid-flight retargets from where it is. §2.4.
- Under `MediaQuery.disableAnimations`: renders the new string, no motion.

**⚠ It is on the sale path, so §6.3 binds it absolutely.** *"No animation may sit
between an input and its record."* The total must be **correct immediately** and the
roll is decoration over an already-committed value. A `RollingNumber` that delays its
own text by one frame is a defect, not a polish item.

**Proposed: this is the lowest-value of the five and should be built last or not at
all.** It is the only one of the five that fixes nothing — no accessibility failure,
no missing capability, no duplicated code. It is worth building when the till is
otherwise finished and worth cutting if anything else needs the time.

---

## What this proposal deliberately does not answer

- **A light palette.** §12 asks the question and answers nothing; every colour above
  is a dark-mode role.
- **Density.** All the sizes above are `density.comfortable`. §3's `compact` density
  needs a way to answer *is this a pointer device*, which `PLAN.md` carries as an
  open question and which no component can settle for itself.
- **Motion asset integration.** `MotionAsset` and the eight §6.4 assets are step 10's
  and are blocked on three §12 questions.

## If you approve

The order that gets the most out of the least work:

1. **`ConfirmDialog`** — 12 call sites, one component, no new tokens, no new gesture.
2. **`FilterChipBar`** — 20 call sites, and it closes §2.3's chip-radius decision.
3. **`QuantityStepper`** — finishes the cart, needs `RollingNumber` only for polish.
4. **`AppSheet`** — its own chunk; unblocks step 7's responsive half and finishes 7.
5. **`RollingNumber`** — last, or never.

**Nothing above should be built before it is approved here and copied into
`design.md` §5.2.** A component built from a proposal is a component built from a
guess with extra steps.
