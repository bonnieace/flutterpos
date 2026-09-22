# Stock counts screen — a design, 2026-09-21, built the same day

Five artboards for `TenantStockTakeSettingsPanel`, the page behind the *Stock counts* row in
[Settings](../settings/README.md). Open [`index.html`](index.html) in a browser. Each page is
self-contained HTML with no build step and no dependency on the repo.

**Built, token-true.** The first drawing used values the token layer does not have: radius 12 on
fields, buttons and callouts, 13 and 15px text, 14 and 28px gaps, and a page header the app moved
into the toolbar on 2026-08-23. When the build was asked for "1:1", the developer chose to build it
from the shared components on the token scale and then correct the artboards to match the build.
So the boards now draw what the app draws. They were measured against the harness captures
`16e-stock-counts`, `16f-stock-counts-read-only`, `16g-stock-counts-damaged` and
`16h-stock-counts-choice-open`. The corrections are listed below.

## The question the screen is opened with

Nobody opens *Stock counts* to look at a rota. They open it for one of three reasons: a cashier
was held out of the till this morning, somebody has started or left, or counting is being switched
on for the first time. All three come down to one question: **on a count day, who gets asked,
what happens if they don't count, and is the whole shop covered?**

The screen used to answer with three stacked controls and leave the reader to put the answer
together:

- **The three choices were a `FilterChipBar`, and only the selected one's consequence was shown.**
  At `compact` the strip scrolls sideways, so *Hold the register*, the one setting that can stop a
  shop trading, could sit past the edge of a phone.
- **Each person's row was a chip strip** of every category. On a phone what a person counted could
  be scrolled out of view inside their own row. On a monitor, eight people with a dozen categories
  came to over a hundred chips.
- **Nothing said whether the whole shop was covered**, and **a deactivated member got the same row
  as everyone else.** A category down to somebody who can no longer sign in looked counted, and
  the gate will never ask anybody to count it.

## What was built

| Part | Before | Now | Where |
| --- | --- | --- | --- |
| What happens when a count is due | `FilterChipBar` | `ChoiceCardGroup`: three radio cards, each with its consequence and what the register shows | `lib/ui/choice.dart` (new) |
| Which days | `AppButton` primary / secondary | `AppToggleButton`: same tiers, check glyph when on, `toggled` semantics; glyph above the label when too narrow | `lib/ui/choice.dart` (new) |
| Who counts what | One `FilterChipBar` per person | One dense `AppSelect` per person: at the end of the row from `medium`, under the name below it | the panel |
| Coverage | — | A `Callout` at the head of the rota, and *n of m categories counted* | `lib/inventory/stock_take_coverage.dart` (new) |
| Row standing | — | *Invited* / *Deactivated* `StatusBadge`s; a note when the row is a fault | the panel |
| Read-only | Chips live and inert, days and Save disabled | The chosen card only, the days as a sentence, each person's answer as text, no Save | the panel |
| Save | At the end | At the end, with when it takes effect | the panel |
| More than 20 staff | Silently absent | An `info` callout under the rota, from `TenantStaffPage.hasMore` | the panel |

**Unchanged:** the three reads, the seed, the publisher and every refusal, the outcomes, the
host's scroll view and inset, and every key a test addresses. The enforcement keys moved from the
chips onto the cards, and the option keys onto `AppSelectItem.key`, as the same strings.

**New logic, kept separable.** The restyle and the new logic are in different places, so they can
still land as separate commits. The coverage line and the row notes derive facts the screen did
not state before, from data it already held. They make no new read, write or route, and they have
their own tests in `test/inventory/stock_take_coverage_test.dart`. The only data change is keeping
`hasMore`.

**Tests:** `test/ui/choice_test.dart` (11), `test/inventory/stock_take_coverage_test.dart` (11),
`test/inventory/stock_take_settings_panel_test.dart` (10). The source scans in `test/dev` and
`test/ui/status_test.dart` pass with the new files in place.

## The coverage line's rules

It reads **the rota as drawn**, so it moves before Save and never claims to describe what is in
force. The callouts above the form still describe the published document.

- `attention`: only when every person on a category is deactivated. The call site passes a warning
  glyph, because `attention`'s own glyph is a clock and nothing here is waiting.
- `info`: categories nobody is down for. Leaving garden stock uncounted can be a decision.
- `ok`: every category covered, or somebody who can sign in counting the whole list.
- `neutral`: nobody on the rota, a rota under *Nothing*, or no categories. Nobody is being asked,
  so gaps are not raised, and there is no count figure.

An invited person covers their category. Somebody past the staff page covers theirs too, because
unknown is not deactivated.

## Where the boards moved to meet the build

| First drawing | Built, and now drawn |
| --- | --- |
| A `‹ Settings` link and a 32px page title | The toolbar title, 22px `titleLarge`, as on every screen |
| Radius 12 on the selects, buttons, day toggles and callouts | `radius.md`, 8, which `AppSelect`, `AppButton` and `Callout` read. Cards stay at `radius.lg`, 12 |
| 18px section headings, 15px names, 13px secondary lines | `SectionHeading` 22, `bodyLarge` 600 16, `caption` 12 |
| Callout title 15/600, text 13/19 | `titleMedium` 18/28 over the density body 16/24 |
| Gaps of 14 and 28 | 12 and 24, the scale's own; `density.sectionGap` between sections |
| Boxes at the column's edge | Every box 4px in, because `PressSurface` reserves a focus-ring gutter round every pressable surface and everything else takes the same inset to line up with it |
| A deactivated avatar at 60% opacity, and an amber edge on their select | The ring steps down to `border.strong`, the name to `text.secondary`, and the note alone carries the fault |
| Phone: select squeezed beside the name | Under the name, aligned with it, at the row's full width |
| Phone days 56 tall with 3px gaps | 48 tall, glyph above the label, 8 apart through the gutters |
| A check glyph in the open menu | `AppSelect`'s own menu, which highlights the current choice |
| A dashed footer for more than 20 people | An `info` `Callout` |
| Em dashes in the row notes | The hyphen the rest of the panel's copy uses |

## Found in the code, still open

1. **The duplicate callout says "first"; the form keeps the last.** `_seed` writes
   `_assigned[uid]` once per assignment, so for a person listed twice the last category wins. The
   callout, quoted unchanged, tells the owner that saving leaves them counting *"only the first
   category they are listed against."* The row note now states what the code does
   (*Also listed for Fasteners - saving drops it*), so right now the screen contradicts itself for
   that one hand-edited record. **Which one is right is your call.**
2. `tool/screenshots/print_screens_test.dart:253` does not compile: a required `tenantId` is
   missing. It is unrelated to this screen and was not touched.

Smaller, and noted only:

- *Nobody to ask yet* is effectively unreachable. `loadPage` throws unless the owner's own staff
  record exists, and that record is in the page it reads.
- `TenantStockTakeSettingsScreen`, the standalone wrapper, has no callers.
- The Settings index row counts `schedule.assignments.length` as *people counting*. For the sample
  rota that is 5: one of the five cannot sign in and another has not accepted their invitation.

## What the sample content is allowed to say

Every line on a row comes from a field the screen already reads. Mwangi Hardware's people are the
ones on the [Staff](../staff/README.md) artboards: Asha is the owner, David is deactivated, and
Lydia, Njeri and Samuel are invited. Their identity rings are the ones `accent.identityFor` gives
the harness's IDs, so the boards match the captures and not the Staff boards' colours.

**Deliberately absent:** a *last counted* line (whether a count was handed in is recorded on the
device that took it), a *next count* line (it would need the gate's business date, not a second
idea of today), *last changed by* (`fromMap` ignores `updatedBy`), and a *Discard* control or a
Save disabled for an unchanged form (that would change behaviour).

## What these files are

Standalone HTML pages written by hand, with no build step and no dependency on the repo. Every
value is the token the build reads, and every sentence is the app's own. The contrast figures
quoted were measured, not estimated.

They are drawings, and so are the captures they were checked against. The harness rasterises the
widget tree, so neither proves the app runs on a device, and neither can show motion. The desktop
board is 1440 wide, the harness's `web` viewport, and the phone board is 411, its `mobile`. The
desktop board draws the back arrow a pushed route has; the harness renders the page as the root
route, so its capture has none. The rota rows, coverage and screen-states boards are catalogues,
laid out to be read rather than to match a window.
