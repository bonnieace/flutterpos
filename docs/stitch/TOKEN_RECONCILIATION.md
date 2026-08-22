# Profound Verdant to AppTokens reconciliation — 2026-08-22

Source of intended presentation: `stitch_chilltent_pos_redesign_system/profound_verdant/DESIGN.md`
frontmatter, corroborated against the token block inlined in all 76 exported `code.html` files. See
`EXPORT_MAP.md` for why the frontmatter is authoritative and the prose beneath it is not.

Target role surface: `lib/ui/tokens.dart` — `AppColorRoles`, `AppTypeRoles`, `AppSpacing`, `AppRadii`,
registered as one `ThemeExtension` at `lib/theme.dart:201` and read by 58 files.

**Nothing in this pass changes a pixel.** No token value was repointed and no widget was edited. This
document records what maps, what is ambiguous, and what has no source value at all.

## Why the repoint cannot be written yet

`lib/ui/tokens.dart` keeps its primitives private specifically so a widget must reach a role, and its
own comment describes the extension point: a second palette "arrives as a second instance of this
class and every widget that reads a role follows it without being edited". Writing
`AppColorRoles.profoundVerdant` is therefore the right shape for the repoint.

It cannot be completed today for a mechanical reason and a design reason:

1. **Mechanical.** A new private primitive set with no consumer fails `flutter analyze` with
   `unused_element` and `unused_field` warnings — verified with a throwaway probe file. So the
   primitives cannot land ahead of the instance that reads them; the existing `_Primitive` class is
   clean only because `AppColorRoles.dark` consumes it.
2. **Design.** `AppColorRoles` requires every field. Profound Verdant supplies no value for eleven of
   them, listed under Gaps below. Filling those in would be inventing design decisions, which
   `CLAUDE.md` and `DESIGN_RULES.md` both prohibit.

So the sequence is: resolve the gaps, then land primitives and instance together, then repoint.

## Colour — surface roles

| `AppSurfaceRoles` field | Current (`design.md`) | Profound Verdant token | Value | Status |
|---|---|---|---|---|
| `base` | `green900` `#0D1F16` | `background`, `surface` | `#071610` | Mapped |
| `raised` | `green850` `#132A1F` | `surface-card` | `#0D1F16` | Mapped — DESIGN.md "Level 1 (Card/Container)" |
| `sunken` | `green950` `#08140E` | `surface-container-lowest` | `#03110B` | Mapped |
| `field` | `green700` `#1E3A2B` | `surface-elevated` | `#132A1F` | Mapped — DESIGN.md "Input Fields ... Background should be Level 2 (#132A1F)" |
| `overlay` | `green800` `#1C3328` | `surface-elevated` | `#132A1F` | Mapped — DESIGN.md "Level 2 (Popovers/Modals)". Collapses to the same value as `field` |
| `scrim` | `rgba(0,0,0,0.6)` | — | — | **Gap** |
| `borderSubtle` | `green700` `#1E3A2B` | `outline-variant` | `#3D4A3D` | Mapped, with a caveat below |
| `borderStrong` | `green600` `#2C5340` | `outline` | `#869585` | Mapped |

Notes:

- **Three current primitives are already Profound Verdant values**, under different role names:
  `green850 #132A1F` is `surface-elevated`, `green900 #0D1F16` is `surface-card`, and
  `mint400 #45F28D` is `currency-kes`. The repoint is a re-assignment of existing values as much as an
  introduction of new ones.
- **`base` moves one tier darker and `raised` takes the old `base` value.** Today `base` is `#0D1F16`;
  under Profound Verdant `#0D1F16` becomes `raised` and `base` becomes the darker `#071610`. Every
  surface therefore shifts by one tier, which is the single largest visual consequence of the repoint.
- **`field` and `overlay` collapse to one value.** DESIGN.md assigns `#132A1F` to both input-field
  backgrounds and to popovers/modals. The current system distinguishes them. Either the distinction is
  dropped or a role gains a value Profound Verdant does not state.
- **Card borders disagree with `outline-variant`.** DESIGN.md's prose specifies a card border of
  `1px #132A1F` — a surface value — while the frontmatter's semantic outline roles are `outline` and
  `outline-variant`. `borderSubtle` is mapped to `outline-variant` because that is the semantic role;
  the prose's card treatment is recorded as a composition detail, not a competing token.

## Colour — text roles

| `AppTextRoles` field | Current | Profound Verdant token | Value | Status |
|---|---|---|---|---|
| `primary` | `white` `#FFFFFF` | `on-surface`, `on-background` | `#D4E7DD` | Mapped |
| `secondary` | `sage050` `#B8D6C5` | `on-surface-variant` | `#BCCBB9` | Mapped |
| `tertiary` | `sage200` `#849E8F` | `outline` | `#869585` | Derived — Profound Verdant states no third text tier, so this reuses the outline role |
| `disabled` | `sageDisabled` `#5D7468` | — | — | **Gap** |

Note: DESIGN.md's prose names "Secondary / Muted Text (#B8D6C5)". `#B8D6C5` is not a Profound Verdant
token — it is the **current** system's `sage050`. This is further evidence the prose is stale, and it
is why `secondary` maps to `on-surface-variant` rather than to the value the prose names.

Body text also loses pure white: `primary` moves from `#FFFFFF` to the slightly green `#D4E7DD`.

## Colour — action roles

| `AppActionRoles` path | Profound Verdant token | Value | Status |
|---|---|---|---|
| `primary.container` | `primary` | `#4BE277` | Mapped |
| `primary.label` | `on-primary` | `#003915` | Mapped |
| `primary.hoverContainer` | — | — | **Gap** |
| `primary.pressedContainer` | — | — | **Gap** |
| `secondary.container` | transparent | — | Mapped — DESIGN.md "Secondary buttons are Outlined" |
| `secondary.label` | `secondary` | `#B0CDBD` | Mapped |
| `secondary.border` | `outline` | `#869585` | Derived |
| `tertiary.container` | transparent | — | Mapped |
| `tertiary.label` | `primary` | `#4BE277` | Mapped |
| `destructive.label` / `.border` | `error` **or** `status-critical` | `#FFB4AB` / `#EF4444` | **Ambiguous** |
| `disabledContainer` | — | — | **Gap** |
| `disabledLabel` | — | — | **Gap** |
| `disabledBorder` | — | — | **Gap** |
| `focusRing.color` | `primary` | `#4BE277` | Mapped — DESIGN.md "1px border that glows Primary Green on focus" |
| `focusRing.width` | DESIGN.md prose says `1px` | 1 | **Conflict** — current value is 2, and a 1px ring is weaker against the accessibility requirement |

The destructive ambiguity is real and load-bearing: Profound Verdant defines two reds and the prose
says only "Semantic Red: Used strictly for destructive actions ... and critical alerts" without naming
which token. Both are used heavily in the exported screens — `status-critical` appears 1,042 times and
the `error` family 506 times — so usage frequency does not settle it either.

`primary-container` `#22C55E`, `primary-fixed` `#6BFF8F`, and `primary-fixed-dim` `#4AE176` exist and
are plausible hover/pressed candidates, but Profound Verdant never assigns them to an interaction
state. Choosing among them is a design decision, not a reading.

## Colour — status roles

This is the weakest area, and the gap is not a documentation oversight.

| `AppStatusRoles` path | Profound Verdant token | Value | Status |
|---|---|---|---|
| `ok.fg` | `tertiary` **or** `primary` | `#2EE380` / `#4BE277` | **Ambiguous** |
| `ok.bg` | — | — | **Gap** |
| `ok.border` | — | — | **Gap** |
| `attention.fg` / `.bg` / `.border` | — | — | **Gap — no warning colour exists** |
| `problem.fg` | `status-critical` | `#EF4444` | Mapped |
| `problem.bg` | `error-container` | `#93000A` | **Ambiguous** — see the opacity note below |
| `problem.border` | — | — | **Gap** |
| `info.fg` / `.bg` / `.border` | — | — | **Gap — no info colour exists** |
| `neutral.fg` | `on-surface-variant` | `#BCCBB9` | Mapped |
| `neutral.bg` | `surface-container-highest` | `#283831` | Mapped |
| `neutral.border` | `outline-variant` | `#3D4A3D` | Mapped |

Three findings:

1. **Profound Verdant has no warning or info colour at all.** There is no amber, yellow, orange, or
   blue token anywhere in the frontmatter. Where the exported designs needed a warning treatment they
   reached for raw Tailwind defaults — `yellow-400` and `yellow-500`, nine occurrences across exactly
   three screens (`inventory_management_desktop`, `inventory_management_desktop_normalized`,
   `shift_reconciliation`). All three are Phase 00-era screens; none is a canonical candidate. So the
   canonical designs contain no warning colour to copy.
2. **This collides with a product requirement.** `DESIGN_RULES.md` requires distinguishing
   `saved locally`, `confirmed`, `waiting to print`, `printer unavailable`, and
   `reconciliation differs`, and requires that status is never conveyed by colour alone. The current
   system uses `amber400` and `blue300` for exactly these. Dropping them without a replacement would
   lose a status tier the product needs.
3. **Chip backgrounds are a mechanism, not a value.** DESIGN.md specifies chips as "a low-opacity
   background of the status color with high-opacity text", and the screens implement this as Tailwind
   `/10` and `/20` alpha suffixes. `AppStatusRole.bg` and `.border` are opaque colours. Either the
   role gains alpha semantics or each background is composited against `base` and recorded as a
   literal — a mechanism decision that affects every status surface.

## Typography

| Profound Verdant role | Family, size, weight, line height | Nearest `AppTypeRoles` field |
|---|---|---|
| `headline-lg` | Hanken Grotesk 32 / 700 / 1.2, tracking -0.02em | `display` or `titleLarge` |
| `headline-lg-mobile` | Hanken Grotesk 28 / 700 / 1.2 | no responsive type role exists |
| `section-title` | Hanken Grotesk 22 / 600 / 1.4 | `titleMedium` |
| `body-md` | Hanken Grotesk 16 / 400 / 1.5 | `bodyLarge` |
| `body-sm` | Hanken Grotesk 14 / 400 / 1.5 | `bodyMedium` |
| `label-caps` | Hanken Grotesk 12 / 700 / 1.0, tracking 0.05em | `labelEyebrow` |
| `data-mono` | JetBrains Mono 14 / 500 / 1.0, tracking -0.01em | `mono` |

Profound Verdant defines **7** type roles; `AppTypeRoles` has **12** (`display`, `titleLarge`,
`titleMedium`, `bodyLarge`, `bodyMedium`, `labelLarge`, `labelMedium`, `labelEyebrow`, `caption`,
`numericHero`, `numericBody`, `mono`). Five current roles — `labelLarge`, `labelMedium`, `caption`,
`numericHero`, `numericBody` — have no Profound Verdant counterpart, and `headline-lg-mobile` has no
counterpart in the other direction because the current type roles are not breakpoint-aware.

Two structural notes:

- **Profound Verdant answers an open question the current system deliberately left open.**
  `lib/ui/tokens.dart` records that no type role names a family, and that the family behind
  `AppTypeRoles.mono` was undecided. Profound Verdant decides both: **Hanken Grotesk** for interface
  text and **JetBrains Mono** for figures and identifiers.
- **Neither family is bundled.** `pubspec.yaml` declares only `Roboto` and one `Roboto Mono` face, and
  neither "Hanken" nor "JetBrains" appears anywhere in the repository. Adopting Profound Verdant
  typography requires adding font assets, which is a `pubspec.yaml` change and therefore
  integration-owner work, not a token edit.

## Radii — a genuine conflict

| Profound Verdant | Value | `AppRadii` | Value |
|---|---:|---|---:|
| `sm` | 2 | — | — |
| `DEFAULT` | 4 | — | — |
| `md` | 6 | — | — |
| `lg` | 8 | `sm` | 8 |
| `xl` | 12 | `md` | 12 |
| — | — | `lg` | 20 |
| `full` | 9999 | `pill` | 999 |

The two scales disagree by roughly a factor of two at every step, and the names collide while the
values do not: Profound Verdant `lg` is 8, the current `lg` is 20. This corroborates
`DESIGN_RULES.md`'s statement that corners are "compact (generally 4-8 px in the Stitch system)".
The current `lg` of 20 has no Profound Verdant equivalent, and Profound Verdant's 2, 4, and 6 have no
current equivalent. Because the names overlap but the values do not, this repoint cannot be done by
renaming; every call site that reads a radius needs review.

## Spacing — compatible

Profound Verdant states `unit: 4px`, `gutter: 16px`, `margin-mobile: 16px`, `margin-desktop: 32px`,
`density-high: 8px`, `density-low: 24px`. Every one of those values already exists in `AppSpacing`
(`s4`, `s8`, `s16`, `s24`, `s32`). No gap and no conflict; the 4px base unit agrees.

## Roles Profound Verdant adds

The frontmatter carries roles with no home in the current surface. They need either a new role or an
explicit decision to ignore them:

- `currency-kes` `#45F28D` — a dedicated colour for money. The current system has no currency text
  role, and this value is currently `mint400`, the action primary. Used 182 times across the export.
- `primary-container`, `secondary-container`, `tertiary-container` and their `on-` pairs.
- `inverse-surface`, `inverse-on-surface`, `inverse-primary`.
- The eight `-fixed` and `-fixed-dim` roles.
- `surface-tint`, `surface-bright`, `surface-variant`, and the five-step
  `surface-container-*` ramp, of which the mapping above consumes only `lowest` and `highest`.

## Summary — all gaps resolved 2026-08-22

**Every gap and ambiguity below was answered by the product owner on 2026-08-22.** The decisions, with
the exact values, are the table in `OPEN_QUESTIONS.md` under "Design-system gaps — RESOLVED". The
repoint is unblocked; the sections below remain as the rationale for each decision.

Headline outcomes: `amber400` and `blue300` carry forward as documented additions because Profound
Verdant has no warning or info tier; `AppStatusRole` gains alpha semantics to match the design
system's chip mechanism; `status-critical` is destructive content and `error-container` is the error
background; `status.ok` is `primary`; the four `AppRadii` names repoint to 4/6/8/9999; both type
families get bundled; and the sale surface takes Profound Verdant's bands with the desktop 3-column
view deferred.

### The gaps as originally recorded

| Gap | Role affected |
|---|---|
| No scrim value | `surface.scrim` |
| No disabled text value | `text.disabled` |
| No primary hover value | `action.primary.hoverContainer` |
| No primary pressed value | `action.primary.pressedContainer` |
| No disabled action values (3) | `action.disabledContainer`, `disabledLabel`, `disabledBorder` |
| No warning colour (3) | `status.attention.fg`, `.bg`, `.border` |
| No info colour (3) | `status.info.fg`, `.bg`, `.border` |
| No status backgrounds or borders for `ok` (2) and `problem` (1) | `status.ok.bg`, `.border`, `problem.border` |

Plus three ambiguities needing a decision rather than a value: which red is destructive, whether
`ok` is `primary` or `tertiary`, and whether the focus ring is 1px or stays 2px.

All of the above are now answered — see the decision table in `OPEN_QUESTIONS.md`.

## Landing order for the repoint

The mechanical constraint from the top of this document still applies: a new private primitive set with
no consumer fails `flutter analyze`, so primitives and their consuming instance land in the same
change. Suggested sequence, each step its own reviewable commit:

1. ~~**`AppStatusRole` alpha semantics** (decision 12).~~ **DONE 2026-08-22.** No shape change was
   needed: a translucent `Color` already composites over the surface behind it, which is exactly the
   design system's `/10` mechanism. What the step actually required was an audit — all three consumers
   (`StatusBadge` and `StatusBlock` in `lib/ui/status.dart`, and the selected `FilterChip` in
   `lib/ui/chips.dart`) paint `bg` as a single flat `BoxDecoration.color`, none nested inside another
   status container, so translucency is safe. Recorded on `AppStatusRole`'s doc, including the warning
   that a future nested consumer would double the tint.
2. ~~**`_ProfoundVerdant` primitives plus `AppColorRoles.profoundVerdant`**, unread.~~
   **DONE 2026-08-22.** Every decided value is now written down once in `lib/ui/tokens.dart` and pinned
   by 18 new tests in `test/ui/tokens_test.dart`, each naming the decision that chose it. Zero-pixel by
   construction — the instance is declared and nothing selects it — and a test asserts `AppTokens.dark`
   still carries `AppColorRoles.dark`.

   > **How not to verify a screenshot claim.** `/screenshots/` is gitignored (`.gitignore` line 57 —
   > it is generated output). So `git status --porcelain screenshots/` returns nothing **whatever the
   > files contain**, and reading that as "no screenshot changed" is reading an ignore rule as a diff.
   > Two claims in this document and in the commit messages were first made that way. The real check is
   > a content hash: `find screenshots -name '*.png' | sort | xargs md5sum > before.txt`, regenerate,
   > hash again, `comm`/`diff` the two. Every zero-pixel claim below was re-verified that way.

   Two things worth carrying into step 3. **The palette is already known accessible**: every one of the
   five status foregrounds, plus body and muted text, clears 4.5:1 on the new darker
   `#071610` base, and the primary label clears 4.5:1 on `#4BE277`. And **the tint arithmetic is
   test-checked rather than trusted** — a `const` cannot compute an alpha, so each tint is a composited
   ARGB literal whose RGB and alpha byte are asserted against its base colour and percentage.
3. ~~**Point `AppTokens.dark` at the new roles.**~~ **DONE 2026-08-22, in two commits rather than one.**

   The swap could not be one line as planned, because **two thirds of `spiritTheme` had never been
   migrated to the token layer at all.** The scaffold, the `ColorScheme` surfaces, every body-text
   colour, cards, the app bar, dialogs, sheets, chips, dividers, list tiles, icons, the spinner and the
   snackbar were all painted straight from the four literals at the top of `lib/theme.dart`; only the
   four button themes, the input borders and the checkbox read roles, from `design.md` §11 step 3.
   Steps 4 and 5 were meant to finish that and never ran. Flipping the extension alone would have put
   new buttons on old surfaces.

   So: **first** a zero-pixel migration moving every slot onto a role and reducing the palette to one
   named place, **then** the flip. Verified by hash — 0 of 359 renders differ across the migration, and
   **359 of 359 differ across the flip**, which is also the useful proof that no screen bypasses the
   theme.

   Where a literal served two jobs the roles now split it by meaning rather than by value: `mutedGreen`
   was containers *and* lines, identical under the old palette and two different roles under this one,
   so the choice is made where it can be read instead of falling out of a hex collision later. One such
   collision was already load-bearing — `fields_test.dart` allowed the input well's colour only because
   `surface.field` and `action.disabledBorder` were both `green.700`; Profound Verdant separates them
   and the omission surfaced as a test failure.

   Roughly forty tests pinned old-palette values. They now read whatever palette the theme registers,
   so they check the wiring rather than the hues, and a future palette change will not break them.
4. **`AppRadii` values** (decision 19). Independent of colour; separate diff so roundness changes are
   not confused with palette changes.
5. **Font assets and `AppTypeRoles` families** (decision 20). A `pubspec.yaml` change, integration
   owner only.
6. **The responsive contract** (decision 21) — `showsTwoPanes` to `mediumFloor` first, then
   `expandedFloor` to 1280, together, with the 1024-1279 harness viewport added.

Keeping 3, 4, 5 and 6 apart matters: each moves pixels for a different reason, and a combined diff
makes every regression ambiguous.
