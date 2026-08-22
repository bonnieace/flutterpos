# Wave 0 foundations audit — 2026-08-22

Scope: the two shared-foundation questions that need no palette decision — the layout contract's
coupling to the retired system, and the 48px versus 32px target-density rule. Colour, typography, and
radius findings are in `TOKEN_RECONCILIATION.md`.

No Dart file was changed by this audit. Findings 1 and 2 below require a decision before the
responsive scaffolds can be called validated.

## Foundation inventory

The orchestration prompt treats Wave 0 as establishing shared foundations. Most already exist, so the
work is validation and repointing rather than construction.

| Foundation | State | Location |
|---|---|---|
| Semantic token layer | Exists — private primitives, public roles, one `ThemeExtension` | `lib/ui/tokens.dart`, 1,431 lines |
| Theme registration | Exists | `lib/theme.dart:201` |
| Token consumers | 58 files read a role | `lib/checkout/`, `lib/inventory/`, `lib/reporting/`, `lib/sales/`, `lib/shift/`, `lib/tenancy/`, `lib/ui/` |
| Breakpoints and content widths | Exist as one contract | `AppLayout`, `lib/ui/tokens.dart:1201` |
| 48px target primitive | Exists as a token | `AppDensity.comfortable.minimumTapTarget`, `lib/ui/tokens.dart:1096` |
| Loading / empty / error states | Exist | `lib/ui/states.dart` — `EmptyState`, `LoadingState`, `ErrorState` |
| RBAC and tenant routing | Exists | 40 files in `lib/tenancy/`, including `tenant_access.dart` |
| Disabled / read-only / offline / busy / provenance components | Not audited in this pass | — |

## Finding 1 — the desktop breakpoint floor contradicts both design sources

`AppLayout` declares `expandedFloor => 1024` (`lib/ui/tokens.dart:1210`). Both authorities for the
redesign put the desktop floor at 1280:

| Source | Tablet band | Desktop floor |
|---|---|---|
| `DESIGN_RULES.md` lines 34 and 38 | 768-1279 | >1280 |
| `profound_verdant/DESIGN.md` lines 141-142 | 768px-1280px | >1280px |
| **`AppLayout.contract` (current code)** | **768-1023** | **>=1024** |

Consequence: every screen from **1024 to 1279 logical px** currently resolves to
`AppBreakpoint.expanded` and receives the desktop composition, where both design sources call it a
tablet and ask for a two-region layout rather than the full three-region desktop one. For the sale
surface specifically, Profound Verdant says tablet is a "2-column split (Items + Cart)" and desktop is
the "Full 3-column operational view", so this band currently gets one column too many.

**The band is untested.** The screenshot harness captures 1440, 834, and 411 px. Nothing between 1024
and 1279 is exercised, so no existing golden or widget test would catch the discrepancy in either
direction.

### Moving the floor alone is the wrong fix, and it regresses the sale path

This was first written up as a one-line change. It is not. `expandedFloor` gates five distinct layout
behaviours, and on the sale surface moving it to 1280 makes the composition **less** correct against
Profound Verdant, not more.

`TenantCheckoutPanel.showsTwoPanes` (`lib/checkout/checkout_cart_panel.dart:211`) is
`isAtLeast(width, expanded)`. Raising the floor to 1280 therefore takes the two-pane till away from
1024-1279 and replaces it with the cart-sheet layout — while Profound Verdant line 141 says that exact
band must be a "2-column split (Items + Cart)", which is the two-pane till.

The real disagreement is not about where one floor sits. Profound Verdant specifies **three** sale
layouts; the code has **two**:

| Width | Profound Verdant (DESIGN.md lines 140-142) | Code today | If the floor moves to 1280 |
|---|---|---|---|
| <768 | Single column, checkout pinned to bottom | Cart sheet — correct | Cart sheet — correct |
| 768-1023 | 2-column, Items + Cart | Cart sheet — **wrong** | Cart sheet — still wrong |
| 1024-1279 | 2-column, Items + Cart | Two panes — **correct** | Cart sheet — **regression** |
| >1280 | 3-column, Categories \| Items \| Cart | Two panes — missing the categories column | Two panes — still missing it |

So today's 1024 floor accidentally gives the sale the right answer for part of the tablet band, and the
proposed change would break it. The tablet band needs to **gain** two panes at 768, and the desktop
band needs a third column that does not exist at all — categories are currently a horizontal
`FilterChipBar`, not a column.

This is also a genuine conflict between design sources rather than a code defect: `design.md` §4.3
specifies "products + cart sheet" at both `compact` and `medium`, with two panes only at `expanded`.
Profound Verdant wants two columns from 768 upward. `CLAUDE.md` demotes `design.md` to implementation
history, so Profound Verdant should win — but that makes this a Phase 03 composition decision, not a
Wave 0 constant.

### Blast radius if the floor is moved regardless

Five behaviours flip across 1024-1279:

| Call site | Today at 1024-1279 | After |
|---|---|---|
| `checkout_cart_panel.dart:211` `showsTwoPanes` | two panes | cart sheet |
| `record_list.dart:530` `formFor` | `RecordForm.table` | `RecordForm.twoColumnCards` |
| `home_navigation.dart:179` `showsMenu` | side menu | card grid |
| `scaffold.dart:136` `showsDisplayTitle` | display title shown | hidden |
| `routes.dart:76` `_isExpanded` | expanded route behaviour | medium |

Unaffected: `chips.dart:112` and `scaffold.dart:155` read `mediumFloor`; `dialogs.dart:200` reads
`reading`.

Roughly fifteen test assertions pin 1024 directly — `tokens_test.dart:723`, `:726`, `:749`,
`routes_test.dart:86` ("exactly 1024 is expanded"), `record_list_test.dart:85`,
`home_navigation_test.dart:88`, `chips_test.dart:18`, and
`checkout_cart_panel_test.dart:907` — and about twenty-five doc comments across `lib/` cite 1024 or
§4.1 as their authority. `AppDensity.compact` also describes itself as applying "at 1024 and above".

### Recommendation

Do not move the floor as an isolated change. The responsive contract needs one decision covering all
three bands per surface family, and the sale surface needs a third layout before the desktop band is
correct at any floor value. Treat this as a Phase 03 dependency with a shared-primitive request, and
keep 1024 until then so the sale path is not regressed in the meantime.

## Finding 2 — the 32px density is unreachable, and its guard is unenforced

`AppDensity` defines two densities: `comfortable` with a 48x48 minimum target, and `compact` with
32x32. `DESIGN_RULES.md` makes 48 logical px pass/fail, so the safety of `compact` rests entirely on
its `pointerOnly: true` flag, which the token file documents as "a touch device never gets 32px targets
whatever its width".

Two facts about the current state:

1. **`AppDensity.compact` is applied nowhere in `lib/`.** The only `AppDensity` reference outside
   `lib/ui/tokens.dart` is `lib/ui/tabs.dart:50`, which reads
   `AppDensity.comfortable.minimumTapTarget.height`. `AppTokens.dark` sets
   `density: AppDensity.comfortable`, so every surface in the app currently runs at 48x48.
2. **`pointerOnly` has no enforcement point.** It is read in exactly five places, all of them
   assertions in `test/ui/tokens_test.dart` (lines 639, 652, 673, 803, 886). Zero reads in `lib/`.

So there is **no live 48-versus-32 conflict**: the requirement holds today because the compact density
was never wired up, not because anything enforces it. The latent risk is precise and worth recording
now, because the surfaces `AppDensity.compact` names as its intended consumers — "the catalog, ledger,
reconciliation, activity log and staff surfaces" — are Phases 04, 05, 06, and 07. The first
implementation that resolves density by width alone will hand 32px targets to a touch device at
tablet or desktop width, and nothing in `lib/` will refuse it.

Recommendation: whatever resolves density must take the pointer/touch input kind as an input, not just
a width, and must assert `pointerOnly` before selecting `compact`. That resolver does not exist yet, so
this is a constraint on Phase 04's first density decision rather than a defect to fix today.

## Finding 3 — the static layout reads are deliberate, not accidental coupling

`CLAUDE.md` and `DESIGN_RULES.md` both say the old `AppLayout.contract` must not determine the new
compositions, which invites reading the direct static reads as the coupling defect. They are not.

There are **eight static reads across seven files**, not the three that a search of `lib/ui/` alone
suggests:

| File | Line |
|---|---|
| `lib/checkout/checkout_cart_panel.dart` | 211 |
| `lib/ui/chips.dart` | 112 |
| `lib/ui/dialogs.dart` | 200 |
| `lib/ui/home_navigation.dart` | 179 |
| `lib/ui/record_list.dart` | 530 |
| `lib/ui/routes.dart` | 76 |
| `lib/ui/scaffold.dart` | 136, 155 |

(`lib/tenancy/tenant_staff_directory.dart:420` mentions it in a comment only.)

`lib/ui/scaffold.dart:130-134` states the reason: a static method has no `BuildContext` to read a theme
from; `AppLayout` is the one part of the token set that nothing overrides per subtree, unlike
`AppDensity`; and `test/ui/tokens_test.dart:810-811` asserts both that `AppTokens.dark.layout` is
`same(AppLayout.contract)` and that the registered theme carries that same contract, so the static and
the theme-routed paths cannot drift.

That guard holds, which means the static pattern **helps** the repoint rather than obstructing it:
changing `expandedFloor` in `AppLayout` propagates to all eight call sites and to the theme at once.
The coupling to the retired system is in the *value* 1024, not in the access mechanism.

One inconsistency is worth tidying when Finding 1 is actioned: `lib/ui/home_navigation.dart` reads the
contract both ways in the same file — statically at line 179 and through the theme at line 189.

## What remains unvalidated in Wave 0

- Disabled, read-only, offline, busy, confirmation, and provenance components — whether they exist as
  reusable primitives or are open-coded per screen.
- RBAC route guards — 40 files exist in `lib/tenancy/`; whether they cover the Owner, Administrator,
  Manager, Cashier matrix in `RBAC_MATRIX.md` was not tested here.
- Test fixtures and builders, and whether they use supported Chilltent facts.

## Decisions — taken 2026-08-22

Both findings were answered by the product owner on 2026-08-22. Full decision table in
`OPEN_QUESTIONS.md`.

1. **Finding 1 — SUPERSEDED 2026-08-22 by the decision in `OPEN_QUESTIONS.md` item 21.** The band
   analysis below stands as the reasoning, but its conclusion changed once the two halves were
   separated: `AppLayout.expandedFloor` **stays at 1024** as a deliberate deviation, and only
   `showsTwoPanes` moved (to `mediumFloor`, so a tablet shows the cart). There is no coupled change and
   no regression risk, because the till no longer reads that floor. The blast-radius table below
   describes a change that was **not** made; read it as why it was not.

   The finding's durable value is the coverage hole it exposed: the till was rendered at 1440 and 411
   only, so its tablet layout — the busiest screen in the product — was covered by nothing. Both till
   cases now capture all three bands.

   *Original conclusion, kept for the record:*
   **Profound Verdant governs the bands, and the change is coupled.**
   `TenantCheckoutPanel.showsTwoPanes` moves from `expandedFloor` to `mediumFloor` so two panes begin
   at 768; `AppLayout.expandedFloor` then moves 1024 → 1280. **Both together, in that order** — step
   two alone is the regression described above, and step one removes the sale surface's dependency on
   the floor before it moves. The desktop 3-column `Categories | Items | Cart` view is deferred and
   categories stay a `FilterChipBar`. Lands as its own commit with the ~15 assertions pinning 1024
   updated and a harness viewport added in the 1024-1279 band.
2. **Finding 2 — the resolver must honour `pointerOnly`.** Any density resolution takes the input kind,
   not just a width, and refuses `AppDensity.compact` on touch. A test that fails if `compact` is ever
   resolved for a touch device is required, so the 48dp guarantee is enforced in code rather than
   documented in a comment.
