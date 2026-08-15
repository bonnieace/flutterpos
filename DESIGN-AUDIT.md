# Design system audit

**Date:** 2026-08-11
**Audits:** `design.md` v0.3 against `lib/` at branch `multitenant-main`, commit `1b2b13b`.
**Scope:** the migrated tenant app. Excludes `lib/pos/**` and `lib/screens/**` (legacy, read-only),
`lib/config.dart` (1,100 lines, entirely commented out), `lib/api/**`, `lib/constants/**` and
`lib/component/**` (imported only by legacy), and `lib/main copy.dart`.

**Read for this audit:** `design.md`, `lib/ui/records.dart`, `lib/theme.dart`, and five screens —
the catalog, the daily summary and the reconciliation status (the three named in the brief), plus
the staff directory (the only real consumer of `records.dart`) and the checkout cart panel (the
sale path). Also `lib/tenancy/tenant_routing_shell.dart` for the landing screen and
`lib/login_screen.dart` / `lib/widgets/` for sign-in.

**Purpose:** to find out, before migration step 1, which of `design.md`'s roles map onto something
that already exists, where the same thing has been built twice, and — the point of the exercise —
where the specification is wrong about the codebase or would require a logic change to implement.

The decisions taken in response to this audit are recorded in §6. They are not yet applied to
`design.md`.

---

## 1. §2 tokens — what exists, under what name, what is new

### 1.1 Colour primitives

Seven of sixteen exist, all in `lib/theme.dart:4-17`, all exact value matches:

| `design.md` | Existing name | Where |
| --- | --- | --- |
| `green.900` `#0D1F16` | `bgDark` | [theme.dart:4](lib/theme.dart#L4) |
| `green.850` `#132A1F` | `bgMid` | [theme.dart:5](lib/theme.dart#L5) |
| `green.700` `#1E3A2B` | `mutedGreen` | [theme.dart:7](lib/theme.dart#L7) |
| `mint.400` `#45F28D` | `accentGreen` | [theme.dart:6](lib/theme.dart#L6) |
| `sage.050` `#B8D6C5` | `_bodyGreen` (private) | [theme.dart:14](lib/theme.dart#L14) |
| `red.400` `#FF5C6C` | `_criticalRed` (private) | [theme.dart:17](lib/theme.dart#L17) |
| `white` `#FFFFFF` | `Colors.white` | [theme.dart:70](lib/theme.dart#L70) |

**New:** `green.950`, `green.800`, `green.600`, `green.400`, `green.300`, `sage.200`, `sage.100`,
`amber.400`, `blue.300` — nine values.

§2.1 says "Three colours are being introduced." That undercounts. `amber.400` and `blue.300` are
the two genuinely new *hues*, but `green.400` and `green.300` are also new and they are load-bearing:
they are the primary button's pressed and hover states.

### 1.2 Surface roles

| Role | Exists as | Where |
| --- | --- | --- |
| `surface.base` | `scaffoldBackgroundColor` | [theme.dart:54](lib/theme.dart#L54) |
| `surface.raised` | `colorScheme.surface` | [theme.dart:69](lib/theme.dart#L69) |
| `border.subtle` | `outline` / `outlineVariant` / `dividerColor` | [theme.dart:72-73](lib/theme.dart#L72-L73), [:183](lib/theme.dart#L183) |

**New:** `surface.sunken`, `surface.overlay`, `surface.scrim`, `border.strong`.

~~The input well is `bgMid` today ([theme.dart:140](lib/theme.dart#L140)) where §2.1 wants
`surface.sunken` `#08140E`. That is a visible change on every form in the app.~~

**It was, on 2026-08-15 with §11 step 9 — and it was taken back the same day.** §2.1 v0.4 gives
the input well a role of its own, **`surface.field` `#1E3A2B`**, and leaves `surface.sunken` the
table header and the code block. The product owner looked at the near-black well on a real screen
and did not want it; `#1E3A2B` is what this app's original sign-in always drew, and it is
`green.700`, already a primitive — so v0.4 added a role and no colour. **This audit's prediction
was right about the size and wrong about the direction**: it was a visible change on every form in
the app, twice.

### 1.3 Text roles

| Role | Exists as | Where |
| --- | --- | --- |
| `text.primary` | `onSurface` = `Colors.white` | [theme.dart:70](lib/theme.dart#L70) |
| `text.secondary` | `onSurfaceVariant` = `_bodyGreen`, and `bodyMedium` | [theme.dart:71](lib/theme.dart#L71), [:81](lib/theme.dart#L81) |

`text.tertiary` and `text.disabled` are new, and **there is no third tier in the app today at all.**
See §4.1 — this is the most consequential finding in this section.

The contrast figures in §2.1 are correct. Recomputed against `#0D1F16` / `#132A1F`:

| Role | vs base | vs raised | `design.md` claims |
| --- | --- | --- | --- |
| `text.primary` | 17.15 | 15.23 | 17.2 / 15.2 |
| `text.secondary` | 10.99 | 9.77 | 11.0 / 9.8 |
| `text.tertiary` | 5.93 | 5.27 | 5.9 / 5.3 |
| `text.disabled` | 3.40 | 3.02 | 3.4 / 3.0 |

All five status `fg` values clear 5:1 on both grounds as §2.1 claims — the lowest is
`status.problem` at 5.08 on raised. `#0A0F0C` on `#45F28D` is 13.2:1 as stated.

### 1.4 Action roles

| Tier | Exists as | Conforms? |
| --- | --- | --- |
| `action.primary` | `filledButtonTheme` [theme.dart:105-113](lib/theme.dart#L105-L113) | Yes, including dark ink on mint |
| `action.tertiary` | `textButtonTheme` [theme.dart:133-137](lib/theme.dart#L133-L137) | Yes |
| `action.secondary` | `outlinedButtonTheme` [theme.dart:124-132](lib/theme.dart#L124-L132) | **No** — label is `accentGreen`, spec wants `#B8D6C5` |
| `action.destructive` | — | Does not exist in any form |

Interaction states (hover, pressed, focus-visible, disabled, loading) are Material defaults
throughout. Nothing in the theme names an overlay colour, and there is no focus ring anywhere in
the app.

The `action.secondary` change is the single largest visual delta in the whole migration: it
repaints roughly forty call sites, including nine of the ten buttons on the landing screen.

### 1.5 Status roles

**Built 2026-08-12 as `StatusBadge` in `lib/ui/status.dart`, and `TenantStatusChip` survives it
for one reason worth naming.** The chip is still used for a staff member's *role* - owner, admin,
manager, cashier - which is not one of §2.1's five statuses and must not be dressed as one. A role
belongs to `FilterChipBar`, already in §5.1 at priority 2. Standing beside a badge it is now
visibly the odd one out: it is a 20-radius pill where §2.3 gives a chip `radius.sm`.

All five triples are new. The nearest existing thing is `TenantStatusChip`
([records.dart:184](lib/ui/records.dart#L184)), which takes one arbitrary `Color? tone` and
*derives* its container at 12% alpha and its border at 50% alpha
([records.dart:205-207](lib/ui/records.dart#L205-L207)). That is a computed pair from a single hue,
not the specification's ten hand-picked background and border values. Every one of them is new.

### 1.6 Typography

**Nothing maps.** `spiritTheme` names **3 of 15** `TextTheme` slots — `headlineLarge` 40/700,
`bodyMedium` 16, `labelLarge` 15/600 ([theme.dart:75-86](lib/theme.dart#L75-L86)). The other twelve
fall through to Flutter's `Typography` defaults. None of the thirteen roles in §2.2 exists by name
or by value.

- **No `FontFeature.tabularFigures()` anywhere in `lib/`** — zero occurrences. `numeric.hero` and
  `numeric.body` are entirely new.
- **No monospace anywhere.** `mono` is new.
- **No `fontFamily` is declared at all**, and [theme.dart:45-51](lib/theme.dart#L45-L51) documents
  why: the theme asked for `Inter` for a long time and no `Inter` was ever bundled. The screenshot
  harness injects Roboto itself at [harness.dart:100-109](tool/screenshots/harness.dart#L100-L109).

  **So §2.2's "One family — Roboto" is true only in the screenshots, not on a device.** The harness
  is currently more branded than the app. This should be resolved before step 1, because until it
  is, no screenshot is evidence about type.

### 1.7 Spacing, size, radius

**No token layer exists.** `lib/constants/sizes.dart` defines a `TSizes` class with a different
scale, and it is imported only by `lib/pos/**` — dead for the migrated tree. Every spacing and
radius value in the app is a literal. See §3.

Current radii against §2.3:

| Surface | Today | §2.3 |
| --- | --- | --- |
| Card | 16 [theme.dart:99](lib/theme.dart#L99) | 12 |
| Input | 14 [theme.dart:144](lib/theme.dart#L144), and three more | ~~8~~ **pill**, since v0.4 |
| Chip | `StadiumBorder` [theme.dart:167](lib/theme.dart#L167) | 8 |
| Bottom sheet | 24 [theme.dart:180](lib/theme.dart#L180) | 20 |
| Snackbar | 12 [theme.dart:197](lib/theme.dart#L197) | unspecified |
| Dialog | 20 [theme.dart:172](lib/theme.dart#L172) | 20 |
| Buttons | `StadiumBorder` | pill |

The dialog is the only match. Buttons are already stadium everywhere, so §2.3's "Pill buttons are
the signature and should stay" costs nothing.

**The input row moved on 2026-08-15, in `design.md` v0.4, and the direction is worth recording.**
§2.3 restricted the pill to buttons on the argument that "when *everything* is a pill the shape
stops signifying". The product owner's ruling is that the argument holds for chips, filters, badges
and cards and does not hold for the field: the sign-in pill is what anyone who has used this app
remembers, and the fields are the second half of it. So `radius.sm` keeps the chip and the badge,
and the field is a pill. **What a reviewer should watch for is the thing the original argument
predicted** — a button and a field now share an outline, and what keeps them apart is the action
tier's fill, the field's persistent label, and the field's left-aligned content.

### 1.8 Motion

**Nothing exists.** Zero `SpringDescription`, zero `AnimationController`, zero `Tween` in the
migrated tree. The entire app contains one animation: an `AnimatedContainer` at 150ms in
[pill_input.dart:83-84](lib/widgets/pill_input.dart#L83-L84).

All four springs and all four duration tokens are new. There is nothing to unwind — with one
important exception, recorded in §4.5.

---

## 2. §5.1 components — what exists, and what has been built twice

### 2.1 What `records.dart` provides

| In `records.dart` | §5.1 name | Consumers |
| --- | --- | --- |
| `TenantStatCard` [:50](lib/ui/records.dart#L50) | `StatTile` | 2 |
| `TenantStatStrip` [:145](lib/ui/records.dart#L145) | `StatRow` (§4.3) | 2 |
| `TenantStatusChip` [:184](lib/ui/records.dart#L184) | `StatusBadge` | 1 |
| `TenantRecordCard` [:288](lib/ui/records.dart#L288) | `RecordCard` | 1 |
| `TenantRecordTable` [:381](lib/ui/records.dart#L381) | `RecordTable` | 1 |
| `TenantInitialsAvatar` [:235](lib/ui/records.dart#L235) | not in §5.1 | 1 widget + 1 static call |

~~There is no `RecordRow`, and nothing that *chooses* between card and table.~~ **Superseded
2026-08-13**: `RecordList` in `lib/ui/record_list.dart` is the thing that chooses, and it is one
component rather than three — §4.3 states the three names as three *renderings*, so a caller states
its records once. `TenantRecordCard` and `TenantRecordTable` remain until the sweep moves their one
consumer, the staff directory, off them. `TenantStatusChip` was already superseded by `StatusBadge`
in step 4; `TenantStatCard` and `TenantStatStrip` are `StatTile` and `StatRow` and are step 8's.

**Only three files import `records.dart`**: [checkout_cart_panel.dart:5](lib/checkout/checkout_cart_panel.dart#L5),
[tenant_staff_directory.dart:3](lib/tenancy/tenant_staff_directory.dart#L3),
[stock_adjustment_panel.dart:3](lib/inventory/stock_adjustment_panel.dart#L3).

The cart panel uses only the static helper `TenantInitialsAvatar.initialsOf`
([:1151](lib/checkout/checkout_cart_panel.dart#L1151)) — not one widget from the file. The stock
panel uses only `TenantStatStrip` / `TenantStatCard`
([:481-495](lib/inventory/stock_adjustment_panel.dart#L481-L495)). So `TenantRecordCard`,
`TenantRecordTable` and `TenantStatusChip` have exactly one consumer between them: the staff
directory.

`design.md` line 10 calls `lib/ui/records.dart` "its implementation". It is closer to a prototype
with one customer.

### 2.2 What does not exist

None of the following from §5.1 exists in any form: ~~`AppScaffold`, `PageHeader`, `AppButton`,
`AppTextField`, `AppSelect`~~, `EmptyState`, `ErrorState`, `LoadingState`, ~~`Disclosure`,
`Callout`~~, `AppSheet`, `AppTabs`, `LedgerEntry`, `QuantityStepper`, ~~`PressSurface`~~,
`MotionAsset`, `RollingNumber`, `SyncIndicator`, `FilterChipBar`.

**Struck through as each was built**, so this list stays a statement of what is missing rather than
a snapshot of one day. `PressSurface` and `AppButton` landed 2026-08-11, `AppTextField` and
`AppSelect` on 2026-08-12, `StatusBadge`, `Callout` and `Disclosure` the same day in step 4, and
`AppScaffold` and `PageHeader` the same day in step 5a. `StatusBadge` was never in this list because
it half-existed as `TenantStatusChip`; see §1.5.

~~One correction to the §5.1 table: `AppSelect` is listed as replacing "raw
`DropdownButtonFormField`". **There is no `DropdownButtonFormField` in the migrated tree.**~~

**Withdrawn 2026-08-12: this audit was wrong, and it was wrong in the direction that costs the
most.** There are **five** `DropdownButtonFormField` call sites in the migrated tree —
[audit_log_panel.dart](lib/audit/audit_log_panel.dart),
[stock_adjustment_panel.dart](lib/inventory/stock_adjustment_panel.dart),
[stock_movement_feed_panel.dart](lib/inventory/stock_movement_feed_panel.dart),
[tenant_staff_invitation.dart](lib/tenancy/tenant_staff_invitation.dart) and
[tenant_staff_update.dart](lib/tenancy/tenant_staff_update.dart) — which is exactly what §5.1 says
`AppSelect` replaces. The original claim looked only at the two places a *category* is chosen, saw
`ChoiceChip`, and generalised from them to the whole tree.

The product owner had already acted on the false claim and dropped `AppSelect`; the decision was
put back to them with the correct figure on 2026-08-12 and reversed. **`AppSelect` is built, and
§5.1 stands as written.** The `ChoiceChip` group pattern is not orphaned by that — it is
`FilterChipBar`, already in §5.1 at priority 2.

**What is worth keeping from the mistake:** an audit finding that says "nothing exists" is a claim
about the whole tree and needs a whole-tree grep behind it, not two call sites and an inference.

### 2.3 Built more than once

1. **Text field — two incompatible implementations.** The migrated tree uses bare `TextField` +
   `InputDecorationTheme`
   ([catalog_management_panel.dart:817](lib/inventory/catalog_management_panel.dart#L817),
   [:845](lib/inventory/catalog_management_panel.dart#L845),
   [:854](lib/inventory/catalog_management_panel.dart#L854),
   [:866](lib/inventory/catalog_management_panel.dart#L866),
   [:882](lib/inventory/catalog_management_panel.dart#L882), and again in the correction dialog at
   [:1310-1360](lib/inventory/catalog_management_panel.dart#L1310-L1360)). ~~Sign-in uses
   `PillInput`, which draws its own 56h well at radius 32, its own label, its own focus indicator
   as a green glow `BoxShadow`, and reads nothing from the theme except two raw imported
   constants.~~ **This is the clearest duplication in the repository.**
   **Closed 2026-08-15 by §11 step 9**: both sign-in fields are `AppTextField`s and
   `pill_input.dart` is dead. The migrated tree's bare `TextField`s went in step 3; what is left
   is the two on the sale path, which are step 7's.

2. **Button — the same split.** ~~[`PillButton`](lib/widgets/pill_button.dart) exists alongside the
   four `ButtonTheme`s and is used by exactly one call site. It hardcodes `Colors.black` for the
   label in all four branches whether the button is filled or not.~~ **Closed 2026-08-15 by §11
   step 9**: the one call site is an `AppButton` on §2.1's primary tier, whose label colour is
   `action.primary.label` and is a token rather than `Colors.black`. `pill_button.dart` is dead.

3. **Confirm dialog — four times.**
   [catalog `_confirmed`](lib/inventory/catalog_management_panel.dart#L335-L350) (which already
   takes a `destructive: true` parameter),
   [checkout `_confirmClearSale`](lib/checkout/checkout_cart_panel.dart#L914-L938),
   [reconciliation `_confirm`](lib/reporting/reconciliation_status_panel.dart#L514-L539),
   [`_showDefaultConfirmation`](lib/tenancy/tenant_routing_shell.dart#L1636-L1666).

4. **Pagination — four idioms.** The catalog is a `Row` with `spaceBetween` Previous / Page N / Next
   ([:965-983](lib/inventory/catalog_management_panel.dart#L965-L983)); reconciliation is a `Wrap`
   of "Previous page" / "Next page" where Next is a `FilledButton` and Previous an `OutlinedButton`
   ([:467-483](lib/reporting/reconciliation_status_panel.dart#L467-L483)); the staff directory just
   prints "More staff memberships are available."
   ([:390-394](lib/tenancy/tenant_staff_directory.dart#L390-L394)).

5. **Empty and failure states — once per guarded route.**
   [daily_metrics_panel.dart:136-154](lib/reporting/daily_metrics_panel.dart#L136-L154) and
   [reconciliation_status_panel.dart:246-255](lib/reporting/reconciliation_status_panel.dart#L246-L255)
   are the same `Center` + `Text` shape written twice, and every other `TenantRouteGuard` caller
   repeats it. [`_EmptyBusinessList`](lib/tenancy/tenant_routing_shell.dart#L1099-L1122) and
   [`_InvalidTenantInvitationScreen`](lib/tenancy/tenant_routing_shell.dart#L824-L857) are the
   identical Icon-48 / gap-16 / Text / gap-16 / FilledButton structure built twice, 250 lines apart,
   in one file.

6. **Breakpoint 768 — declared twice.** See §5.

---

## 3. Hardcoded values in widgets

**627 occurrences across 60 files.**

Counted: literal numerics in `EdgeInsets` / `SizedBox` / `spacing` / `runSpacing` /
`Radius.circular` / `size` / `width` / `height` / `fontSize` / `letterSpacing` / `maxWidth`, plus
`Color(0x…)` and `Colors.*`. `lib/theme.dart` is excluded from the total — it *is* the token layer,
and its 29 literals are correct.

| Category | Count |
| --- | --- |
| Spacing (`SizedBox`, `EdgeInsets`, `spacing`/`runSpacing`) | 531 |
| Colour literals | 33 |
| Icon / box size | 32 |
| Radius | 19 |
| `fontSize` / `letterSpacing` | 9 |
| `maxWidth` | 3 |

### Worst five files

| # | File | Count |
| --- | --- | --- |
| 1 | [lib/checkout/checkout_cart_panel.dart](lib/checkout/checkout_cart_panel.dart) | 41 |
| 2 | [lib/tenancy/tenant_routing_shell.dart](lib/tenancy/tenant_routing_shell.dart) | 38 |
| 3 | [lib/inventory/catalog_management_panel.dart](lib/inventory/catalog_management_panel.dart) | 36 |
| 4 | [lib/inventory/stock_adjustment_panel.dart](lib/inventory/stock_adjustment_panel.dart) | 33 |
| 5 | [lib/inventory/bulk_catalog_panel.dart](lib/inventory/bulk_catalog_panel.dart) | 26 |

Sixth is [lib/ui/records.dart](lib/ui/records.dart) at 23, which is worth naming because it is the
file `design.md` calls its implementation. It hardcodes padding 16
([:89](lib/ui/records.dart#L89)), gaps 10 and 4 ([:111](lib/ui/records.dart#L111),
[:123](lib/ui/records.dart#L123)), `minimumWidth = 168` ([:146](lib/ui/records.dart#L146)),
`spacing = 12.0` ([:156](lib/ui/records.dart#L156)), chip padding 10/4 with radius 20 and alphas
0.12/0.5 ([:203-207](lib/ui/records.dart#L203-L207)), a 44×44 avatar at radius 12
([:263-267](lib/ui/records.dart#L263-L267)), card padding 14 ([:318](lib/ui/records.dart#L318)),
table header padding 14/14/14/10 ([:403](lib/ui/records.dart#L403)), and a 0.5px row border
([:461-464](lib/ui/records.dart#L461-L464)).

### Two qualifications that change what the number means

**Almost none of it is colour.** Outside `theme.dart`, sign-in, and `lib/widgets/`, there are
**zero** `Color(0x…)` literals in the migrated tree. The panels read
`Theme.of(context).colorScheme` throughout. `claude.md` hard rule 2 is being broken almost entirely
on *spacing and size*, and the reason is structural: there is no spacing token to read. Introduce
one and most of the 531 become mechanical substitutions.

~~**The colour literals that do exist are concentrated on the first screen a user sees.**
`login_screen.dart` uses `Colors.green` (Material `#4CAF50`) for the Remember Me checkbox — a
*different* green from `accentGreen` — and `Colors.red` (`#F44336`) for the error, not
`_criticalRed`. `PillInput` uses `Colors.white70`, `white54` and `white38` — three greys the
palette does not name. `glass_card.dart:26` and `pos_keyboard.dart:47` add two more. That is the
highest-value colour cleanup in the repository and it is roughly eight lines.~~

**Done 2026-08-15 by §11 step 9, and it was not eight lines — it was the screen.** Every literal
above is gone: the checkbox reads §2.1's primary tier through the theme, the refusal is an
`AppNotice` in a `Callout` on §2.1's `problem`, and the three widgets carrying the greys are
deleted. **The estimate was wrong in the way this repository's estimates keep being wrong** —
substituting a token for each literal would have left a radius-32 well, a green glow where §9 wants
a ring, uppercase labels, and a button saying `UNLOCK REGISTER →`, none of which is a colour. The
count of `Color(0x…)` and `Colors.*` outside `theme.dart` and the legacy island is now **zero**.

### Against the §2.3 spacing scale

Permitted values are {4, 8, 12, 16, 20, 24, 32, 40, 48, 64}. Values in use that are not on the
scale: 2 (×2), 6 (×5), 10 (×3), 14, 28 (×3), 60 (×1) — fourteen `SizedBox` instances plus
`EdgeInsets(14)` in `records.dart`. 8 (×118) and 12 (×100) dominate, so the existing rhythm is close
to the specification rather than far from it.

---

## 4. Where the specification conflicts with the code

### 4.1 The caption-contrast failure does not exist, and the real defect is its opposite

§2.1 states that `#5D7468` and `#607A6C` "currently appear as caption text on the catalog,
pagination, and ledger metadata", and §9 lists "caption text at 3.4:1 and 3.7:1" among known current
failures.

**Neither hex appears anywhere in the repository.** A search across `lib/`, `test/`, `tool/` and
`screenshots/` returns zero occurrences of either.

What actually happens: `spiritTheme` names only three `TextTheme` slots
([theme.dart:75-86](lib/theme.dart#L75-L86)), so `bodySmall` — which every caption in the app uses
([daily_metrics_panel.dart:270](lib/reporting/daily_metrics_panel.dart#L270),
[reconciliation_status_panel.dart:408](lib/reporting/reconciliation_status_panel.dart#L408),
[checkout_cart_panel.dart:1271](lib/checkout/checkout_cart_panel.dart#L1271),
[catalog_management_panel.dart:1381](lib/inventory/catalog_management_panel.dart#L1381)) — falls
through to `Typography`'s white face and renders **`#FFFFFF` at 12px, 17.15:1**.

There is no tertiary tier. Timestamps and attribution render in the same colour as headings.

Two consequences:

- Introducing `text.tertiary` is a contrast **reduction**, from 17.15 to 5.93. It is still the right
  change — hierarchy is the point, and 5.93 clears AA comfortably — but it is not a fix for a
  failure, and it changes pixels on every screen in the app.
- [test/theme_test.dart:66-89](test/theme_test.dart#L66-L89) asserts that every `TextTheme` slot
  clears WCAG AA against both grounds. `text.tertiary` `#849E8F` passes at 5.93 / 5.27.
  `text.disabled` `#5D7468` at 3.40 / 3.02 **would fail that test** if it were ever placed in a
  `TextTheme` slot. §2.1 is right that WCAG exempts disabled controls, but the test does not know
  that, so the disabled role must live outside `TextTheme` — as a `WidgetStateProperty` on the
  button and input themes.

**§2.1 and §9 need correcting.** The right replacement text names the actual defect: captions have
no distinct tier and render at the same weight of colour as titles.

### 4.2 The sale screen's action prominence is already correct

§2.1: "The rule that fixes the sale screen: **Clear this sale** is `destructive`, **Save sale** is
`primary`. Today the destructive action is the more prominent of the two."

False. [checkout_cart_panel.dart:904](lib/checkout/checkout_cart_panel.dart#L904) renders
*Clear this sale* as an `OutlinedButton`;
[:974](lib/checkout/checkout_cart_panel.dart#L974) renders *Save sale* as a `FilledButton`. Given
the themes at [theme.dart:105](lib/theme.dart#L105) and [:124](lib/theme.dart#L124), Save is a
filled mint stadium and Clear is a transparent outline. The prominence is already the right way
round.

The real defect is narrower and still worth fixing: *Clear this sale* is styled **identically to the
nine navigational `OutlinedButton`s on the landing screen**, so it reads as ordinary rather than as
reversing. There is no `action.destructive` tier at all. That is the change; the framing in §2.1
is not.

### 4.3 Destructive actions are already confirmed — in four places

§7 states "Currently *Clear this sale* fires on one tap." It does not:
[:906](lib/checkout/checkout_cart_panel.dart#L906) calls `_confirmClearSale`, an `AlertDialog` at
[:914-938](lib/checkout/checkout_cart_panel.dart#L914-L938) that names the consequence — "Every item
is removed and the payment method is cleared. Nothing has been saved yet, so no record is lost." —
with a *Keep it* / *Clear it* pair. It already follows the §7 template and §8 rule 6.

§5.1 is more consequential: it lists `ConfirmDialog` as replacing "**none** — destructive actions
are unconfirmed today." There are four independent confirmation flows (§2.3 item 3), three of them
guarding something real: retiring a product, discarding a cart, and spending a server reconciliation
allowance the app cannot shorten.

**This changes `ConfirmDialog`'s risk profile.** It is not a greenfield component. It is a
consolidation of four call sites that each `await` a value the caller branches on, and one of them
([`_confirmed(... destructive: true)`](lib/inventory/catalog_management_panel.dart#L335-L350))
already has an API. It is the one §5.1 component that cannot be built without touching control
flow, which brushes `claude.md` hard rule 1. It should be planned and reviewed as a behaviour
change, not as styling.

**Resolved 2026-08-12, at the start of step 4: `ConfirmDialog` leaves step 4 and joins step 7.**
`PLAN.md` required this to be decided before step 4 started, and the decision follows from this
section plus one thing this section did not say: **§11 step 7 already names "destructive confirm"
in its own row.** So there is no need to invent a home for it - it has one, in the step that is
already scoped as touching control flow on the sale path. Step 4 ships `StatusBadge`, `Callout` and
`Disclosure`, all three of which are pure display and none of which awaits anything. Nothing else
in step 4 depended on it, which is what made the decision cheap.

### 4.4 The sign-in fields are not what §5.2 describes

§5.2: "the sign-in screen currently uses the placeholder as the label on one field and a floating
label on another."

False. Both fields are `PillInput` ([login_screen.dart:168-187](lib/login_screen.dart#L168-L187))
with an explicit persistent label above the well
([pill_input.dart:63-70](lib/widgets/pill_input.dart#L63-L70)) and a hint that is a genuine example
(`example@spiritpos.com`). Neither floats — `InputDecoration(border: InputBorder.none,
isCollapsed: true)` at [:117-118](lib/widgets/pill_input.dart#L117-L118) makes floating impossible.
Structurally it is already the §5.2 pattern.

The actual defects on that screen are different, and all three are real:

- The labels are uppercase (`"EMAIL / USER ID"`, `"PASSWORD"`), which §2.2 restricts to
  `label.eyebrow`.
- The well is radius 32 where §2.3 says `radius.sm` = 8.
- The focus indicator is a green glow `BoxShadow`, not the 2px ring with 2px offset that §9
  requires.

The submit button is `"UNLOCK REGISTER →"`, which §2.2 correctly identifies as both the wrong case
and the wrong words.

**All of it went in §11 step 9 on 2026-08-15**, and this section under-counted the screen by four.
The four it did not have:

- **Every field drew two borders**, and had since commit `1b2b13b` on 2026-08-10 — three months
  after this section was written and one day before it. `PillInput` set `border: InputBorder.none`,
  which is correct and no longer sufficient: `InputDecorator` prefers `enabledBorder` and
  `focusedBorder`, both were null on the widget, and `spiritTheme` gained all three plus
  `filled: true` in `1b2b13b`. So a 14-radius filled outline was painted inside the pill's own
  well, in `mobile/01-sign-in.png` and every capture since. `AppFieldWell` strips all six slots and
  a test now asserts it against the real theme rather than a bare one.
- **The refusal was a `String?` painted red**, so "this device could not reach the server" and
  "that password is wrong" were the same sentence in the same colour. The notice sweep of
  2026-08-15 missed this screen because it greps for `-notice'` and this one's key was
  `login-error`. It is an `AppNotice` now, and the transport branch is §2.1's `info`.
- **The on-screen keypad's keys were 24 logical pixels wide at §4.1's `medium` floor**, because the
  screen asked §4.1 whether the window was 768 wide when the question it needed answered was
  whether half the window can hold ten keys at §9's 48dp target. The keypad took four ninths of the
  window and then spent 48 on the card's margin and 48 on its padding, so at 768 ten keys shared
  245 pixels — 24 of slot each and 13 painted — and at 1023 they shared 359, which is 36 and 24.
  `PosKeyboard.minimumWidth` answers that now and the boundary is 1264 rather than 768.
- **The `Enter` key did nothing**, and had since the file was written — an empty branch with the
  comment `// Optional submit action`. It is drawn disabled, which is what "no callback" looks
  like; wiring it is a behaviour change and `claude.md` hard rule 1 keeps that out of a visual
  step.

The three widgets this section names — `pill_input.dart`, `pill_button.dart`, `glass_card.dart` —
are dead as of that step and nothing imports them.

### 4.5 `PressSurface` cannot be a drop-in for `InkWell`, and step 2 is larger than §2.4 implies

§2.4: "Replace `InkWell` with an opacity-plus-scale state overlay… The expanding Material ripple is
the loudest tell that an app is not iOS, and it is currently on every control in the app."

The symptom is right; the instruction is not. There is exactly **one** `InkWell` in the migrated
tree ([checkout_cart_panel.dart:1029](lib/checkout/checkout_cart_panel.dart#L1029)). Replacing it
fixes one product tile.

Every other ripple comes from Material's own `FilledButton`, `OutlinedButton`, `TextButton`,
`IconButton`, `ChoiceChip`, `ListTile` and `SegmentedButton` implementations. So step 2 must choose
between:

- **(a) Theme-level.** Set `splashFactory: NoSplash.splashFactory` plus explicit overlay colours on
  every `ButtonTheme` in `theme.dart`. Cheap, global, one file — but it gives no scale-0.97 and no
  spring, so the press *feel* §2.4 is actually asking for does not arrive.
- **(b) Per-call-site.** Replace every button, chip, tile and icon-button call site with
  `PressSurface`. Correct, and much larger than a single migration step.

This choice determines whether step 2 or step 3 comes first, and it is recorded as still open in §6.

### 4.6 Out-of-stock is not signalled by colour alone

§9 lists it among known current failures.
[checkout_cart_panel.dart:1082-1090](lib/checkout/checkout_cart_panel.dart#L1082-L1090) renders
`Icon(Icons.error_outline, size: 13, color: colors.error)` immediately followed by the text
`'Out of stock'`. It already satisfies the icon-plus-label half of §2.1's status rule. What it lacks
is the container and the border. A `StatusBadge` is still the right answer, for a smaller reason.

### 4.7 §4.3's responsive contract contradicts `records.dart`'s stated design

§4.3: "Every list-bearing component declares what it *becomes* at each breakpoint, and that
declaration lives with the component, not with the screen… A screen cannot opt out; if it needs to,
that's a new component and it gets specified here."

[records.dart:375-380](lib/ui/records.dart#L375-L380) argues the opposite, deliberately and in
writing: *"below that it is a card list, which is what `TenantRecordTable` leaves to the caller
rather than deciding here — the caller knows which of its columns survive the loss."*

The code enforces that position. `TenantRecordCard` takes `title` / `subtitle` / `chips` /
`actions` / `details` ([:288-297](lib/ui/records.dart#L288-L297)). `TenantRecordTable` takes
`List<TenantTableColumn>` + `List<TenantTableRow>`, with an assert that a row's cell count matches
the column count ([:453-458](lib/ui/records.dart#L453-L458)). **There is no shared model between
them.** The one place the choice is made
([tenant_staff_directory.dart:385-389](lib/tenancy/tenant_staff_directory.dart#L385-L389)) calls two
entirely separate builder methods, `_staffCards` ([:496](lib/tenancy/tenant_staff_directory.dart#L496))
and `_staffTable` ([:511](lib/tenancy/tenant_staff_directory.dart#L511)), which present different
information.

So `RecordList` is not a rename of what exists. It requires inventing the record model §5.2
describes — identity, attributes, status, provenance, actions — re-expressing every caller's data in
it, and, for each of the thirteen screens in step 6, **deciding what the compact form loses**. That
decision is precisely what `records.dart` argues belongs to the caller. It is a product judgement
per screen, not a styling change, and step 6 as written assumes it is free.

**Resolved: `design.md` concedes the opt-out.** See §6, decision 2. **Applied to `design.md` on
2026-08-13**, thirteen days after the decision and in the chunk that implements §4.3, which is where
step 6a said it belonged.

**Built the same day, and this finding is what shaped it.** `RecordList` in
`lib/ui/record_list.dart` is the record model this paragraph says has to be invented — identity,
attributes, status, provenance, actions — with the three renderings resolved from the screen width
rather than chosen by the caller. **The concession is `RecordAttribute.inNarrowForm`, one flag per
attribute**, so the per-screen judgement this finding describes is visible in each call site rather
than in a layout rule. The estimate here was right about the shape and right about the cost: it
shipped as the component plus **one** screen, and the other twelve are a sweep.

### 4.8 Step 1 is a full-app repaint, not a no-op

§11: "Step 1 changes no pixels if done correctly, and that is the point: it is the step that proves
the roles map cleanly onto what exists before anything moves."

That is not achievable as specified. Conforming the token layer changes, at minimum:

| Change | Where | Blast radius |
| --- | --- | --- |
| `outlinedButtonTheme.foregroundColor` mint → `#B8D6C5` | [theme.dart:126](lib/theme.dart#L126) | ~40 call sites, most of the landing screen |
| `bodySmall` white → `text.tertiary` | [theme.dart:75-86](lib/theme.dart#L75-L86) | every caption in the app |
| Card radius 16 → 12 | [theme.dart:99](lib/theme.dart#L99) | every card |
| Input radius 14 → ~~8~~ **pill** | [theme.dart:144](lib/theme.dart#L144)–[:157](lib/theme.dart#L157) | every form |
| Input fill `bgMid` → ~~`surface.sunken`~~ **`surface.field`** | [theme.dart:140](lib/theme.dart#L140) | every form |
| Chip `StadiumBorder` → 8 | [theme.dart:167](lib/theme.dart#L167) | catalog, checkout tender |
| Bottom sheet 24 → 20 | [theme.dart:180](lib/theme.dart#L180) | cart sheet |

**Resolved: step 1 becomes additive — define the roles, wire nothing.** Every row in the table
above moves into steps 2–5 instead, where each diff has one cause. §11's "changes no pixels" claim
then stands as written, and an empty screenshot diff becomes step 1's pass condition rather than an
embarrassment. See §6, decision 1.

Three consequences of the rewiring, wherever it lands, that "cosmetic" undersells:

- **Type metrics move layout, not just appearance.** Size, line height and `tabularFigures` all
  change measured extents, so anything that ellipsises, wraps or overflows can flip. Tabular figures
  make digits *wider* — every digit takes the widest digit's advance — and `TenantStatCard`'s value
  is `maxLines: 1, overflow: ellipsis` ([records.dart:115-116](lib/ui/records.dart#L115-L116)).
  [`_LandingScrollArea`](lib/tenancy/tenant_routing_shell.dart#L1172) computes `_moreBelow` from
  `extentAfter > 1` and drives a real `setState`, so text metrics decide an observable state.
  [test/tenancy/tenant_safe_landing_test.dart](test/tenancy/tenant_safe_landing_test.dart) asserts
  that state seven times — but it states its own space (411 × 731) and uses injected panel heights
  of 120 and 900 against it, margins of hundreds of pixels against a shift of tens. **Those
  assertions should survive**, and the reason they will is that the test states the space instead of
  assuming it.
- **`theme_test.dart` stops being complete, without failing.** `bodySmall` moving to
  `text.tertiary` passes at 5.93:1. The gap is elsewhere: §2.2 has thirteen roles and Flutter's
  `TextTheme` has the wrong fifteen slots, so `numeric.hero`, `numeric.body`, `mono` and
  `label.eyebrow` must live in a `ThemeExtension` that
  [test/theme_test.dart:35-51](test/theme_test.dart#L35-L51) enumerates by slot name and will never
  see. Four roles, including both money roles, land outside the one test that stops this class of
  defect.
- **Do not let size tokens touch button `minimumSize`.** It is `Size(0, 48)` today
  ([theme.dart:109](lib/theme.dart#L109)) and §5.2's `md` is 40h. Shrinking the default breaks §9's
  48dp touch target, which is pass/fail under `claude.md` hard rule 6. Button sizing is step 3's
  business.

### 4.9 §2.2's uppercase restriction contradicts `records.dart`

§2.2 restricts uppercase to `label.eyebrow`, "field group labels only". `records.dart` uppercases
the `TenantStatCard` caption ([:98](lib/ui/records.dart#L98)) and every `TenantRecordTable` column
header ([:410](lib/ui/records.dart#L410)). §5.2 assigns table headers `label.md`, which is not
uppercase.

Conforming means un-uppercasing the stat captions and table headers, visible on the staff directory
and both stock screens. Another thing step 1 cannot do silently.

**Half closed 2026-08-13.** `RecordList`'s table draws its headers in sentence case in `label.md`,
which is the row §2.2 gives them, and a test asserts both. What is left is `TenantRecordTable`'s own
headers — which go away with their one consumer in the sweep — and `TenantStatCard`'s caption, which
is step 8's.

### 4.10 §4.4's navigation model is a behaviour change

Each of the ten landing entries
([tenant_routing_shell.dart:1436-1627](lib/tenancy/tenant_routing_shell.dart#L1436-L1627)) is
conditional on two things: whether the composition root injected that route builder, and
`membership.role.canAccess(...)`. A fixed four-destination bar must decide what *Sell* / *Stock* /
*Money* / *More* contain when a role or a build has none of the routes in a bucket — a cashier with
no `dailySummaryRoles` has an empty *Money*.

More seriously, routing today is `Navigator.push` wrapping each route in a fresh
`TenantSessionScope`
([:1470-1477](lib/tenancy/tenant_routing_shell.dart#L1470-L1477), repeated near-identically eight
times). A persistent bottom bar turns those pushes into tab switches, which changes session scoping
and back-navigation behaviour.

That is squarely a logic change, and §11 places it in step 5 alongside `AppScaffold` and
`PageHeader`, which are pure styling.

**Resolved: step 5 is split.** See §6, decision 3.

### 4.11 Smaller inaccuracies

**§4.4 on the landing screen.** It is described as "a `Wrap` of ten identical pills". It is a `Wrap`
of *up to* ten ([tenant_routing_shell.dart:1431-1628](lib/tenancy/tenant_routing_shell.dart#L1431-L1628))
— nine `OutlinedButton.icon` and one `FilledButton.icon` (*New sale*,
[:1466](lib/tenancy/tenant_routing_shell.dart#L1466)) — and how many appear depends on role and
injection. They are not identical: one is filled. The "ragged centred stack on a phone" is exactly
right (`WrapAlignment.center`, [:1434](lib/tenancy/tenant_routing_shell.dart#L1434)), and the file
already carries a comment at [:1396-1411](lib/tenancy/tenant_routing_shell.dart#L1396-L1411) that
measured this row's phone cost in pixels.

**§2.2 on the daily summary.** "Today's daily summary has proportional figures in a column of
currency, which is why the amounts look ragged." The figures are proportional — nothing anywhere
sets `tabularFigures`. But the daily summary does not stack them:
[daily_metrics_panel.dart:242-249](lib/reporting/daily_metrics_panel.dart#L242-L249) renders them
mid-sentence ("Sales: KES 1,234.00 over 12 transactions in 2 shifts"). Whichever screen the
raggedness observation came from, it was not this one. Re-identify it before step 8.

**§5.2 on the `Correct` / `Retire` target size.** "20px targets on a touch surface" is not right.
They are `TextButton`s ([:716](lib/inventory/catalog_management_panel.dart#L716),
[:722](lib/inventory/catalog_management_panel.dart#L722)), and `textButtonTheme`
([theme.dart:133-137](lib/theme.dart#L133-L137)) overrides no sizing, so Material's default
`MaterialTapTargetSize.padded` gives them a 48dp tap height. What they *do* fail is §9's "≥ 8dp
apart": they sit adjacent in a `Row(mainAxisSize: MainAxisSize.min)` at
[:729](lib/inventory/catalog_management_panel.dart#L729) with no gap, so a mis-tap on *Correct*
lands on *Retire*. That is a sharper finding than the one in the document, and it is the same defect
§5.2 identifies second — destructive-adjacent actions rendered identically.

### 4.12 What the specification gets right

Recorded for balance, because these do not need re-litigating:

- **§5.1 `QuantityStepper` — "minus + delete, no plus".** Accurate.
  [checkout_cart_panel.dart:1276-1292](lib/checkout/checkout_cart_panel.dart#L1276-L1292) is a
  quantity `TextField`, an `Icons.remove` `IconButton`, and an `Icons.delete_outline` `IconButton`.
  There is no plus; incrementing requires returning to the catalog list.
- **§7 — "several screens render the title in the app bar *and* again as an `H1` directly beneath
  it".** Accurate, and here they are: Daily summary
  ([:55](lib/reporting/daily_metrics_panel.dart#L55) and
  [:199-202](lib/reporting/daily_metrics_panel.dart#L199-L202)), Reconciliation status
  ([:35](lib/reporting/reconciliation_status_panel.dart#L35) and
  [:354-357](lib/reporting/reconciliation_status_panel.dart#L354-L357)), Manage catalog
  ([:64](lib/inventory/catalog_management_panel.dart#L64) and
  [:752](lib/inventory/catalog_management_panel.dart#L752)), Staff directory
  ([:341-344](lib/tenancy/tenant_staff_directory.dart#L341-L344)).
- **§5.2 — the catalog row whose "Correct" link sits ~1,300px from the product name.** Accurate; §5
  explains the mechanism.
- **§6.3 the sale-path rule.** Nothing to undo. `_save` at
  [:976](lib/checkout/checkout_cart_panel.dart#L976) goes straight to the draft write, and there are
  zero `AnimationController`s in `lib/checkout/`. It is a constraint on step 7, not a repair.
- **§5.2 `Disclosure` on the explanatory copy.** Accurate and worth keeping. The catalog's scope
  paragraph ([:754-769](lib/inventory/catalog_management_panel.dart#L754-L769)) is seven lines of
  permanent body text, and the bulk-changes paragraph
  ([:921-926](lib/inventory/catalog_management_panel.dart#L921-L926)) is another three.
- **Every contrast figure in §2.1.** Independently recomputed; see §1.3.

### 4.13 Document hygiene

- `design.md` line 3 says "**Status:** v0.1 — proposed. Not yet implemented." The changelog's top
  entry is v0.3, and §6.4 refers to "a system still at v0.2". The header is stale.
- `claude.md`'s "Screenshot harness" section ([claude.md:42-49](claude.md#L42-L49)) is an empty code
  block with its `<!-- Fill in the actual command -->` comment still in place. The commands are
  `flutter test tool/screenshots` then `dart run tool/screenshots/build_index.dart`
  ([screenshots/README.md:22-25](screenshots/README.md#L22-L25)). Every migration step's step 4
  depends on this, so it should be filled in before step 1 begins.

---

## 5. Are the breakpoints consulted, or only declared?

**Neither constant is consulted by the catalog, the daily summary, or the reconciliation screens.
All three are fixed single-column `ListView`s at every width.**

**Closed 2026-08-12 in step 6.** Both constants are gone, and with them the third
mechanism and the second declaration of 768. What replaces all four is `AppLayout` in
[tokens.dart](lib/ui/tokens.dart), under §4.1's own names, at the same numbers — which is what
§4.1 asks for in so many words. The table below is kept as the state that motivated the step.

| Constant | Declared | Consumers |
| --- | --- | --- |
| ~~`tenantWideLayoutBreakpoint`~~ → `AppLayout.mediumFloor` | ~~[records.dart:26](lib/ui/records.dart#L26)~~ | ~~**Zero.**~~ ~~**Three**: `PageHeader.placesActionBesideTitle`, `checkout_cart_panel.dart`'s till split, `login_screen.dart`'s `isMobile`.~~ **Two as of 2026-08-15**: step 9 took sign-in's, and it did not rename it — it *replaced* it. Whether the keypad fits is a measurement, not a band; see §4.4. |
| ~~`tenantTableBreakpoint`~~ → `AppLayout.expandedFloor` | ~~[records.dart:36](lib/ui/records.dart#L36)~~ | ~~**One.**~~ **Three**: `PageHeader.showsDisplayTitle`, `AppPageRoute`'s transition row, the staff directory's card-to-table switch. |

- ~~`tenantWideLayoutBreakpoint` has no consumers. The only other reference in `lib/` is its own doc
  comment at [:30](lib/ui/records.dart#L30). Its reader `tenantLayoutIsWide`
  ([records.dart:39](lib/ui/records.dart#L39)) has **zero callers** anywhere in `lib/`, `test/` or
  `tool/`. Both are dead code.~~

  **Half of that closed 2026-08-12 in step 5a.** `PageHeader.placesActionBesideTitle`
  ([scaffold.dart](lib/ui/scaffold.dart)) reads `tenantWideLayoutBreakpoint` to decide whether a
  page's title and its primary action fit on one row, which is the question the constant's own doc
  comment says it answers. `tenantLayoutIsWide` still has zero callers - the header reads the
  constant against a screen width rather than against `BoxConstraints` - so the *reader* is still
  dead code and the constant is not.
- `tenantTableBreakpoint` is consulted once, via `tenantLayoutFitsTable` at
  [tenant_staff_directory.dart:386](lib/tenancy/tenant_staff_directory.dart#L386). That is the only
  breakpoint-driven layout switch in the entire migrated app.

  **Still the only one after step 6, and that is worth stating rather than letting the closure
  above imply otherwise.** Unifying the declarations did not add a layout switch anywhere; what it
  added is a *content maximum* on all 25 routes, which is §4.2 rather than §4.3. The responsive
  contract — what a `RecordList` becomes at each band — is the second half of step 6 and is not
  done. One switch, on one screen, is still the honest count.

  What did change on that one screen: it asks the question of the **screen** width now rather than
  of its own `BoxConstraints`, because §4.2 put a 1200 cap and 20 of padding between the two. At
  1024 exactly, the old reading would have found 984 and drawn cards on a surface §4.1 calls
  expanded.

### The three named screens

| Screen | Layout | Responsive machinery |
| --- | --- | --- |
| Catalog | one `ListView(padding: EdgeInsets.all(20))` [:749-750](lib/inventory/catalog_management_panel.dart#L749-L750) | none — no `LayoutBuilder`, no `MediaQuery`, no import of `records.dart` |
| Daily summary | one `ListView(padding: EdgeInsets.all(20))` [:195-197](lib/reporting/daily_metrics_panel.dart#L195-L197) | none |
| Reconciliation status | one `ListView(padding: EdgeInsets.all(20))` [:350-352](lib/reporting/reconciliation_status_panel.dart#L350-L352) | none |

This is also the mechanism behind §5.2's 1,300px observation. The product row is a `ListTile` inside
a `Card` inside an unconstrained `ListView`
([catalog_management_panel.dart:945-955](lib/inventory/catalog_management_panel.dart#L945-L955)), so
at the 1440px web viewport `trailing` — the `Correct` / `Retire` pair from
[:713-730](lib/inventory/catalog_management_panel.dart#L713-L730) — pins to the right edge of a
~1400px row while the title sits at the left. §4.2's max content width is the fix, and there is no
responsive machinery to remove first.

### Two related findings

~~**768 is declared twice.**~~ **Fixed 2026-08-12 in step 6.**
[checkout_cart_panel.dart:550](lib/checkout/checkout_cart_panel.dart#L550)
declared `static const double wideTillBreakpoint = 768` and consulted it at
[:562](lib/checkout/checkout_cart_panel.dart#L562) — in a file that already imported `records.dart`
at [line 5](lib/checkout/checkout_cart_panel.dart#L5) for a static string helper. The two
declarations could drift. `wideTillBreakpoint` is now a getter reading `AppLayout.mediumFloor`; the
name is kept because it says what the till uses the boundary *for*, and **nothing else in the sale
path was touched**, that being step 7's.

~~**There is a third mechanism.**~~ **Also fixed 2026-08-12.**
[login_screen.dart:47](lib/login_screen.dart#L47) computed
`isMobile` from `MediaQuery.of(context).size.width` against a literal 768 with a comment. So §4.1's
"so a screen consults one variable" had to unify three mechanisms across three files, not merely
rename two constants — and it did: `isMobile` now asks `AppLayout` whether the width is
§4.1's `compact` band. ~~**Sign-in's visual design is still step 9's** and nothing else there
moved.~~

**Step 9 arrived on 2026-08-15 and deleted the consumer rather than keeping it**, which is the more
interesting half of this entry. Unifying the declaration was right and the *question* was wrong:
§4.1's bands say how much room a page has, and what this screen needed to know is whether half the
window can hold ten keys at §9's 48dp tap target. It could not — at §4.1's `medium` floor each key
had 24 pixels of slot and 13 painted, and had since the screen was written, under a boundary that
looked correct because it named a declared constant. `LoginScreen.showsKeypad` asks
`PosKeyboard.minimumWidth` now. **A screen
consulting one variable is not the same as a screen asking the right question**, and this is the
only place in the app where the two came apart.

### On the generated screenshot documentation

`screenshots/README.md:15-16` says "Both breakpoints are declared in `lib/ui/records.dart`, and the
two widths were chosen to straddle them." That is true of the *declarations* and misleading about
the effect: across the whole 108-screen capture, at 1440px versus 411px, **exactly one screen
changes shape.**

§4.3's opening line — "This is the part the current app is missing, and the reason the README's
claim about tables isn't true on screen" — is the most accurate sentence in the document about the
current code.

Renaming the constants touches: [screenshots/README.md](screenshots/README.md) (generated — edit
[tool/screenshots/build_index.dart:197-201](tool/screenshots/build_index.dart#L197-L201) instead) and
[tool/screenshots/harness.dart:22](tool/screenshots/harness.dart#L22), which explains its viewport
choice in terms of both names. **Both were edited in step 6, on 2026-08-12, and the second half of
this finding was answered rather than only renamed**: the two viewports now also straddle §4.2's
maxima in both directions — 1440 is wider than every one of them and 411 narrower than every one —
so the pair shows a page constrained and unconstrained. The "exactly one screen changes shape"
count is unchanged, because a content maximum is not a shape change; **49 of the 51 images the step
moved are `web/` ones**, and every `mobile/` image but two is byte-identical.

**The good news:** because there is almost no responsive logic to unwind, §4.3 is additive rather
than a rewrite. The cost is in defining the record model, not in removing existing behaviour.

---

## 6. Decisions

Taken 2026-08-11 in response to this audit. Not yet applied to `design.md`.

| # | Item | Decision |
| --- | --- | --- |
| 1 | §11 step 1's "changes no pixels" claim (§4.8) | **Step 1 becomes additive.** Define every role, wire nothing. The rewiring moves into steps 2–5, where each diff is attributable to one component. §11's claim then stands as written, and an **empty screenshot diff is step 1's pass condition**. |
| 2 | §4.3's "a screen cannot opt out" vs `records.dart` (§4.7) | **`design.md` concedes the opt-out.** The caller decides what a compact rendering loses, as `records.dart:375-380` argues. ~~§4.3 to be amended.~~ **§4.3 amended 2026-08-13**, in the chunk that implements it, and the amendment states the limit as well as the concession: it is per *attribute*, and the form is never the caller's. |
| 3 | §11 step 5 mixing styling with navigation (§4.10) | **Split step 5.** 5a = `AppScaffold` + `PageHeader`, visual only. 5b = navigation model, reviewed as a behaviour change with a device check. |
| 4 | `PressSurface` scope: theme-level `NoSplash` vs per-call-site (§4.5) | **Neither as posed. `PressSurface` moves inside `AppButton`.** Step 2 is the theme-level ripple kill only; `AppButton` is built on `PressSurface` in step 3, so no call site is touched twice. |
| 5 | The false current-state claims in §2.1, §5.1, §5.2, §7 and §9 | **Fix them** before they become acceptance criteria for work already done. |

### On decision 1

Chosen over correcting the claim because it keeps step 1 doing what §11 says it is for — proving
the roles map onto what exists before anything moves — and because it makes every later diff
attributable to one cause. Under the alternative, the largest image diff of the migration would
also have been the one attributable to nothing in particular, and step 1's mint → sage repaint
would have been re-reviewed as part of `AppButton` in step 3.

The cost accepted with it: for several steps the app runs on a half-migrated palette, with some
surfaces reading new roles and some old. That is the price of attributable diffs and it was taken
knowingly.

The total work is unchanged. Only when the pixels move, and how reviewable each move is.

### On decision 4

`PressSurface` needs a spring substrate that does not exist yet — there are zero
`AnimationController`s in the migrated tree — so a step-2 call-site sweep would mean building the
springs, touching ~40 sites, and then touching all of them again in step 3 when `AppButton`
replaces them. Making it `AppButton`'s internal detail removes the second pass.

- **Step 2** — `splashFactory: NoSplash.splashFactory` on `ThemeData`, plus `overlayColor`
  `WidgetStateProperty`s on the four button themes implementing §2.1's 8% / 12% rows. One file,
  zero call sites.
- **Step 3** — `AppButton` is built on `PressSurface` from the start, so every button gets
  scale-0.97 + `spring.snappy` at the moment its call site is already being rewritten.
- **The stragglers** get theirs when their own step arrives: the single `InkWell` at
  `checkout_cart_panel.dart:1029` is a sale-path product tile (step 7); chips are steps 3–4;
  `ListTile`s go away with `RecordList` in step 6.

Verified against the SDK before committing to this: `InkResponse` falls back to
`ThemeData.splashFactory` (`ink_well.dart:1116`) and the M3 button defaults delegate to it
explicitly (`filled_button.dart:658`, `outlined_button.dart:578`, `text_button.dart:601`). **Caveat:
the M2 default paths hardcode `InkRipple.splashFactory`** (`outlined_button.dart:374`,
`text_button.dart:403`), so this holds only while `useMaterial3` is true. It is unset in
`spiritTheme`, so it is true by default today — but a future `useMaterial3: false` would silently
restore ripples on outlined and text buttons.

**Step 2's screenshot diff will be near-empty.** A ripple only exists mid-press. Its verification is
a device check with the performance overlay on, per §10 — not a screenshot.

### Items still needing a decision, outside the five above

- **§3's density model cannot be expressed in one `ThemeData`, and step 1 must pick a structure.**
  §3 gives comfortable and compact different body roles, but `bodyMedium` is a single global value
  and **all 756 bare `Text(` call sites** in the migrated tree resolve to it through
  `DefaultTextStyle`. One theme cannot hold two body sizes. The three options are a nested `Theme`
  per screen (cheapest, keeps §3's "chosen by the screen" literal, call sites untouched), a
  `ThemeExtension` read explicitly at call sites (correct, but eventually edits all 756), or
  hardcoding comfortable now and retrofitting compact across every back-office screen later. **This
  is the one item here that is not cosmetic in any sense** — it decides the shape of steps 6 and 8,
  and it has to be answered by the token layer rather than discovered at the first compact screen.
- **The `Inter` / Roboto question** (§1.6). The harness injects Roboto; the app names no family and
  renders in the platform default. §2.2 says "One family — Roboto". Either bundle Roboto and name it
  in `theme.dart`, or amend §2.2 to say the family is the platform default. Until this is settled,
  no screenshot is evidence about type.
- ~~**`AppSelect`** (§2.2). Nothing exists for it to replace.~~ **Withdrawn 2026-08-12 — the claim
  was false.** Five `DropdownButtonFormField` call sites exist; see §2.2 above. `AppSelect` was
  built in step 3's second half and §5.1 stands as written.
- **`ConfirmDialog`'s classification** (§4.3). It consolidates four existing `await`-and-branch call
  sites, so it cannot ship as a purely visual pull request. Decide whether it moves out of step 4.
