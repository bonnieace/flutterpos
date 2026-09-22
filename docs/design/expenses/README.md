# Expenses screens — a design, 2026-09-22

Five artboards for the Expenses route (`TenantExpensesPanel`), one heading's screen
(`TenantExpenseCategoryScreen`), and the two sheets they open (`showExpenseRecordSheet`,
`showExpenseVoidSheet`). Open [`index.html`](index.html) in a browser. Each page is self-contained
HTML with no build step and no dependency on the repo.

**A proposal. Nothing here is built.** Every colour, size, radius and gap is a token the app
already has, and every part is an existing shared component except one small group (below). So
the boards can be built token-true without extending the token layer. They were not measured
against harness captures the way the stock counts boards were, because there is no build to
measure yet.

## The question the screen is opened with

Only an owner or an administrator can open it, and they open it for one of two reasons:

1. **To write down something just paid**: fuel for a delivery, an electricity token, the rent.
   This is the common visit. It is short, it happens standing at the counter, and it is done on
   a phone.
2. **To see where the money went**: at the end of a week or a month, which heading is eating the
   profit.

So the question is **what did the business pay out, and is all of it written down?** The screen
answers the second half well already: the ring, the share rows and the per-heading screen were
all shaped at the developer's direction in August, and this design keeps them. It answers the
first half poorly:

- **The one thing most visits are for is a bare glyph.** Recording is a `+` in a filled circle at
  the trailing edge of the toolbar. On 2026-08-28 it was enlarged because it "was there but not
  findable". Stock counts review already puts a labelled *Count stock* `AppButton` in the same
  slot; Staff uses a glyph.
- **The subtitle is cut off on a phone even beside the glyph.** The harness capture
  `mobile/36-expenses.png` reads *What the business spent, beyond the cost of its st…*.
- **The period's total is drawn at about 15px.** `KES 70830.00` has to fit 82% of a 136px hole,
  so the `FittedBox` scales the 22px figure down to about 15px (measured on that capture: 110px
  across 12 mono glyphs). That is barely larger than each share row's 14px figure. The headline
  number reads no bigger than the rows under it.
- **Nothing says a heading opens.** The share rows are `PressSurface`s that push a screen, but
  they draw no chevron or other sign that they can be opened.
- **Recording picks from a hidden list.** *What for* is an `AppSelect`: two taps, and eight
  headings nobody sees until the menu opens.

## What the boards change

| Part | Today | Proposed | Kind |
| --- | --- | --- | --- |
| Record control | `AppIconButton`, `add_circle` at 24 | `AppButton` primary with an `add` icon, *Record expense*, in the same `primaryAction` slot and calling the same `_record` | Restyle |
| Subtitle | *What the business spent, beyond the cost of its stock.* | *Spending beyond stock*. It fits beside the button at 411 (checked in Chrome). The guard against filing stock purchases moves into the record sheet, which is where that mistake would be made | Copy |
| Ring's total | `KES 70830.00` scaled into the hole | `currency.code` as a 12px `caption` line above `70830.00`, which then fits at its full 22. With no code published, the figure alone | Restyle |
| Share rows | Name, share, figure, bar | The same, plus a trailing `chevron_right` in `text.tertiary` | Restyle |
| Desktop list | Ring centred above six 1,152-wide bars | From `medium`, the ring in a 264 column beside its legend | Restyle |
| Loading | Skeleton of two figure tiles and three lines | A ring and six rows, the shape the page now has | Restyle |
| Nothing recorded | Hint says to record something; nothing to press | `EmptyState.action`: the same *Record expense*, calling `_record` | Restyle (wiring: `_ExpensesContents` takes the callback) |
| A record's void control | Red `remove_circle_outline` `AppIconButton` on every live row | A `more_vert` `PopupMenuButton` with one item, *Void expense*, which is what Staff rows use. The rarest action stops being the loudest thing beside a column of money | Restyle |
| Voided row | Caption *Voided - reason* in `status.neutral.fg` | A neutral `StatusBadge` *Voided* on the date line, with the reason under it in `caption` | Restyle |
| Record sheet: heading | `AppSelect` | All eight as a two-column single-choice group of `AppToggleButton`s (four columns from `medium`), with none chosen at first | Restyle, **one new group widget** (the button exists; a radio group of them does not) |
| Record sheet: order | What for, Description, Amount | What for, **Amount**, Description, the order `_submit` checks them in, so the first complaint is always about the top-most gap | Restyle |
| Record sheet: amount | *Amount* | *Amount in KES* | Wiring: `showExpenseRecordSheet` takes the currency |
| Record sheet: caption | *It counts against profit for 2026-09-22.* | *It counts against profit for today, 22 Sep 2026. Stock bought to sell is not an expense — its cost is counted when it sells.* | Copy |
| Void sheet: caption | ISO date; no word on correcting | `d MMM yyyy`, and *To correct an amount, void it and record it again.* | Copy |
| Dates | Rows `d MMM yyyy`; both sheets, the chart's tooltip and the row's screen-reader label ISO | `d MMM yyyy` everywhere | Copy |

**Unchanged:** the three reads and the route guard, the chip chooser and its three periods, the
ring's geometry and its spring, the share rows' semantics, the per-heading screen's figure,
summary and day chart, every refusal, and every key a test addresses except one: the void's key
(`expense-void-{id}`) moves onto the menu item, so the three taps on it in
`test/expenses/expense_panel_test.dart` have to open the menu first. The menu button takes a key of
its own.

## Not a pure restyle — each is separable

1. **Treat a queued write as done. This fixes a bug.** `main.dart:673` wires
   `QueuedTenantExpenseWriter`, which answers `queued` for every record and every void and never
   anything else. Both sheets map `queued` to `AppNotice.offline('Saved on this device; waiting
   to sync.')`, which is status `info`. That has two effects:
   - Every expense, even with full signal, ends with a sentence saying it is waiting.
   - **A void never closes the heading's screen.** `_void` (`expense_panel.dart:189`) reports
     success only for `AppStatus.ok`, and the category screen pops only on success. It holds the
     period it was handed, so after a void the person is left looking at the record they just
     voided: still live, still with its void control, under the old total. The list behind it
     has re-read, but they cannot see it.

   The catalog already treats `queued` as `AppNotice.confirmed` (*Category added.*), for the reason
   the queued writers' own file gives: the queue is the commit. The proposal is the same here:
   *Expense recorded.* and *Expense voided.*, both `confirmed`. That one change fixes both effects.
2. **Each complaint under its own field.** `_submit` already knows which check failed; today it
   puts the sentence in one `Callout` above the buttons, under every field rather than under the one at fault. The
   boards put it in `AppTextField.error`, and under the heading group. The wording is unchanged.
   The outcome sentences (offline, refused, not known) stay callouts, since they are about the
   whole write.
3. **A *Read again* button on *Not read*.** It bumps the generation `_reload` already bumps.
   Today the only way to retry is to tap another period and back.
4. **Colour by heading, not by rank. Needs your decision.** `ExpenseCompositionRing.colorFor`
   takes the position in `spentCategories`, so Transport can be grey over 30 days and mint over
   one. And two of `chart.series`' eight stops fail the 3:1 a graphic needs against the page:
   rank 6 (`#2C5340`) is 2.14:1 and rank 8 (`#1C3328`) is 1.37:1. The states board shows all
   eight. Names and figures carry every fact, so hard rule 4 holds, but the swatch that ties a row
   to its slice does not show. Changing `series` moves every chart that reads it, so it is your
   call, not the boards'. The boards draw today's palette.

## Found in the code, still open

- **The sheets' offline, refused and not-known sentences cannot be reached** with the writer the
  app ships. A server refusal arrives later, on the notifications screen. The states board marks
  which sentences are live.
- **If the queue itself fails, the sheet spins for ever.** Neither `_submit` catches an exception
  from the writer (`expense_panel.dart:986`, `:1168`), so an `enqueue` that throws leaves `_busy`
  true and both buttons disabled.
- **`main.dart:669-672` describes the writer that was replaced**: "the same online check every
  other client write uses". The queued writer has no online check.
- **The `mobile-full` captures `36-expenses` and `37-expenses-one-category` are stale.** They
  still show the flat record list and the three stat tiles the code has since removed. The
  `mobile` and `web` captures of 36 are current.
- **A filled toolbar button sits 4px from the glass.** `AppBar` gives its actions no end inset,
  and `PressSurface`'s gutter is the only gap (the harness's page-frame capture,
  `mobile/94-page-frame-action.png`). The boards draw it as the scaffold does. It belongs to `AppScaffold`, not this screen.
- **Money has no thousands separator** (`TenantReportingCurrency.format` is `toStringAsFixed(2)`).
  That is app-wide, and the boards reproduce it.
- *0 records, today* over a heading that still opens onto one voided record is accurate but reads
  oddly. Saying *1 voided* would be a new count from data already held.

## Deliberately not drawn

- **A list of recent records on the list screen.** At the developer's direction on 2026-08-28 the
  page ends at the headings, and records are one tap in.
- **Recording against another day.** Every expense is filed under today's business date, so rent
  paid on the 1st and entered on the 3rd counts on the 3rd. A date field is a behaviour change
  and a rules question.
- **This month.** *Last 30 days* is not a calendar month, so whether a rent lands in it depends on
  the day it is opened.
- **A *not sent yet* mark on a queued record.** `TenantExpense` carries no pending flag.
- **Who recorded it.** `recordedBy` is a uid; naming them needs the staff read.
- **What spending did to profit.** That needs the sales read; the home's *Net profit* tile says it
  for today.
- **Bars for the day chart.** The line is the reference's and was asked for. The boards draw it
  as `fl_chart` does: with `preventCurveOverShooting` every tangent is flat, so a day's spend rises
  and falls within one day's width, and reads as a spike.
- **Quick reasons on the void sheet.** Tried: three chips (*Recorded twice*, *Wrong amount*,
  *Wrong heading*) do not fit 411 without teaching `FilterChipBar` to wrap. Voiding is rare, so
  it was not worth extending a shared component for.
- **Icons per heading.** `AppToggleButton` has none, and the share rows' swatch already carries
  the one visual key.

## What the sample content is allowed to say

The business is Mwangi Hardware, as on the [Staff](../staff/README.md) and
[Stock counts](../stock-counts/README.md) boards. No people appear, because nothing on these screens
names one. The six headings and their amounts are the harness fixture's, so the list board can be
compared with `web/36-expenses.png`: KES 70830.00 in total, and the same ranks and shares. The
records moved to September to sit inside a 30-day window ending Tuesday 22 September 2026.
Transport is two live records and one voided duplicate, so its screen shows every kind of row.

## What these files are

Standalone HTML, written with a small generator (not in the repo) so the ring's arcs, the day
chart's curve and the illustrations' recolouring are computed rather than hand-placed. The
illustrations are the real `empty-wallet.svg` and `access-denied.svg` through the same mapping
`_UndrawPalette` applies. The contrast figures were computed with the WCAG formula, not
estimated.

They are drawings. They prove nothing runs and cannot show motion. The phone boards are 411,
the harness's `mobile` viewport, and the desktop board is 1440, its `web`. Both draw the back
arrow a pushed route has; the harness renders these screens as the root route.
