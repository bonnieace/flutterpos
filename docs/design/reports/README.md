# Reports — the Day report, a design, 2026-09-21

**REVERTED on 2026-09-21, by the product owner, after seeing it on a device.** Two reasons, both
of them about the product rather than the drawing:

1. **Day duplicates the home screen.** The landing route already carries *Today's sales*,
   *Transactions*, *Shifts* and *Profit* as stat cards. A whole report answering the same question
   one tap further in is a second place to read one number.
2. **Month is a range, not a report.** Whatever a month can say, a download with a date range says
   — so the month belongs in the export flow rather than in a pill of its own.

So the Reports screen is back to the single weekly report it was before. `PillTabBar`,
`TenantReportsHomeScreen`, `TenantDayReport` and their tests are deleted; the `framed` flag on the
weekly and monthly screens, `loadDay`, `loadDayShifts`, the two shift indexes and the RBAC row are
all reverted.

**Where the Day design went instead: the Sales totals screen.** Tapping *Total sales* on the weekly
report opens `TenantSalesTotalsScreen`, which already answered *what did we take today* and was
the product owner's "information overload". It now wears the Day artboard's card language — one
card per question: takings, *How it was paid*, *Across the day*, *Profit*, *Net profit* — with:

- a `‹ Today ›` stepper in place of the period dropdown, walking the four fixed
  `TenantSalesPeriod` values;
- member and category as two captioned selects in one row (captioned, not `dense`: at half width
  the dense glyph left room for about ten characters, and both read *All memb…* / *All catego…*);
- the tender rows coloured from `AppChartRoles.series`, so four methods read as four things;
- *Across the day* as the per-cashier column chart (`shift_comparison_chart.dart`), **only for
  Today** and **only when at least two shifts can be drawn with a height**. A running shift has no
  height, so one closed shift beside one open one is stated as rows, not plotted as one bar;
- *Profit* and *Net profit* as separate figure cards, replacing `TenantProfitStatement`'s stacked
  rows here. The wording still comes from `tenantProfitCeilingNote` and `tenantProfitNote`.

`loadDayShifts` and the two shift indexes (`businessDate, __name__` and
`staffId, businessDate, __name__`) came back for it. **The indexes are not deployed, and the
owner's reading does not need them:** on SIT, 2026-09-21, an owner's *Across the day* rendered
with the day's open shift. An equality filter ordered ascending by document ID is served by the
automatic single-field index. The cashier's own-shifts reading (`staffId` *and* `businessDate`) has
not been tried on a device; Firestore can usually merge single-field indexes for equality-only
filters, so the composite may be unnecessary there too, but that is unproven.

**What survives, and is worth reading:** the artboards below, and the download design in
[`reports-download.html`](reports-download.html), which is still unbuilt and still wanted — now
with a **range picker**, since that is what replaces the Month pill. Three screenshot-fixture bugs
the work uncovered are also kept; they are listed at the bottom.

---

Four artboards for a Day dashboard, the pill strip that selects between reports, and the download
flow. Open [`index.html`](index.html) in a browser; each page is self-contained HTML with no build
step and no dependency on the repo.

**These artboards were a proposal; the Day report has since been built.** What shipped differs
from the drawings in the places recorded under *What changed between the drawing and the code*
below. The artboards are kept as the reasoning, not as the specification — where they and the code
disagree, the code is right.

**Download is drawn here and is not built.** [`reports-download.html`](reports-download.html) is
still a proposal in full.

## What this is a design for

Each pill is **its own report with its own cards**, not one dashboard re-summed at three
resolutions. Day, Week and Month have different data behind them, cost different amounts to open,
and download to different documents. That is the whole reason they are pills rather than a period
selector, and it is what makes the Differences and Stock problem go away: nothing is shared, so
nothing is a control that visibly does nothing.

The current Reports screen becomes the **Week** pill unchanged. **Month** stays exactly as it is
and gains a download button. This design is only the **Day** pill, which today is a list.

## The fact that shapes the whole screen

`TenantDailyMetricsStanding` has four values, and its own doc comment says **today is normally
`unpublished`**. Reconciliation runs nightly, so the most-opened day of the most-opened report is
the one with no certified figure in it.

So the takings figure cannot simply be a number. It has to say what kind of number it is, and
[`reports-day-states.html`](reports-day-states.html) is eight versions of that one card.

**The good news is the cost.** For today, `TenantDeviceSalesAggregator` — the thing
`daily_metrics_panel.dart` already uses for unpublished days — adds up this device's own encrypted
cache plus the outbox, at **zero Firestore reads**, and it includes sales that have not sent yet.
For a past day it is **one document read**, served from cache offline.

And `TenantSalesTotals.fromDevice` takes `costMinor`, `incompleteCostLineCount`,
`tenderSalesMinor` and `tenderTransactions`. So takings, profit with its basis, the tender split
and returns are all available for today **with no network at all**. Day is the one report in this
product that works offline, which is a better argument for it being first than any of the ones I
made before checking.

## The five cards, and where each figure comes from

| Card | Source | Cost |
| --- | --- | --- |
| Takings, net, average sale | `TenantDailyMetrics` or `TenantDeviceSalesTotals` | 1 read, or 0 for today |
| How it was paid | `tenderSalesMinor` on the same object | free, same read |
| Across the day | `TenantShiftHistoryEntry.summary` per shift | 1 query |
| Profit | `TenantProfitReport` off the same totals | free, same read |
| Came back | `net.returnedSales`, `net.returnCount` | free, same read |

## Three things deliberately not drawn

1. **No hourly curve.** Nothing on a sale or in `daily_metrics` carries time-of-day in a form
   anything aggregates. *Across the day* uses **shifts** instead — they are the day's real
   buckets, `ShiftClosingSummary` already carries a per-shift total and transaction count, and
   the open shift is drawn as an outline rather than a fill because it is not finished.
2. **No top items.** The week gets its best-sellers from a capped sale-line walk. Paying that on
   every Day open — the report most likely to be opened several times a day — is the wrong trade.
   The expand arrow is where it goes if it turns out to be wanted.
3. **No target, and no *vs yesterday*.** There is no per-day target field in the model, and
   yesterday is a second document read. Worth deciding on purpose rather than assuming.

## The pills are a new component — but three existing ones were weighed first

This README's first draft said only that `AppTabs` was the wrong control. That was incomplete, and
the omission mattered: **`FilterChipBar` already exists**, is already pill-shaped, already scrolls
in one line at `compact`, and is already built on `PressSurface`. Building a second selection
control without saying why would have been exactly the "competing local design system" the
working discipline forbids.

The reason it is still a new component is what each one is *for*:

- `AppTabs` is a Material `TabBar` with a travelling underline — right where tabs are views of one
  subject, which the platform console's four are. It stays there.
- `FilterChipBar` narrows a list that is already on screen. Its null means *no filter*, and its own
  library note says it refuses to invent a default. A report selector is never null and replaces
  the page rather than narrowing it. Its chip is also **32** high and wears `status.ok` as a
  translucent container; a report pill is **48** and wears `action.primary` as a fill.
- `lib/widgets/pill_button.dart` is unreachable, predates the token layer and carries its own
  colours. Not a starting point.

That argument is recorded in `lib/ui/pill_tabs.dart`'s own library comment, so the next person to
grep for `pill` finds it.

Hard rule 5 means it ships with all nine states, which is what
[`reports-pills.html`](reports-pills.html) catalogues. **48 high, not the reference's ~40**, because
hard rule 4 is pass/fail; `ui/tabs.dart` already carries a comment about having been two pixels
short for its whole life, and this starts at the right number instead.

**The strip must never trigger a read.** The report body behind it is built lazily on first
selection and kept alive after. Otherwise switching back to Week pays its nine callables twice,
and the cheap-by-default property that makes this structure worth having is gone.

**One flag, not an objection.** There is a retired decision against pills — `OPEN_QUESTIONS.md`
decision 19, quoted in `test/dev/reachable_lib_test.dart`, alongside three unreachable pill widgets
in `lib/widgets/`. Per `CLAUDE.md` that document is reference and not authority, and this is your
call; it is named here only so nobody re-opens it later as though it had been settled the other
way. `lib/widgets/pill_button.dart` is **not** a starting point — it predates the token layer and
carries its own colours.

## Download

One icon in the header action slot, on every report, exporting **the report and period already on
screen**. The sheet states the period rather than asking for it.

The state that is not optional is the fifth sheet. `profit_statement.dart` holds the rule that no
profit figure is ever rendered without, in the same block, what is known about the cost data
behind it. A PDF bypasses the widget, and it is read by people who cannot ask a follow-up
question. So the caveat has to be re-enforced inside the exporter — which argues for **one shared
export pipeline that owns it**, rather than a `pw.Document` per report each doing its own thing,
which is what `lib/pos/reports/paymentsfreq.dart` did in the old app.

`pdf: ^3.10.0`, `printing: ^5.11.1` and `share_plus` are already in `pubspec.yaml`. All three
existing PDF files — `lib/api/pdf_api.dart`, `lib/api/pdf_invoice_api.dart` and
`lib/pdf_preview_screen.dart` — are on the unreachable list in `test/dev/reachable_lib_test.dart`,
and none is a starting point.

## What this cannot ship as

**Not a restyle.** Hard rule 1 says a UI change never changes behaviour, and two things here are
behaviour:

- **The pill strip is new routing.** Five reports reachable from one screen, lazily built, is a
  navigation change, not a visual one.
- **Download does not exist.** New capability, new permission surface on Android, new failure
  modes.

The Day dashboard *itself* is closest to a restyle — every figure on it is one
`daily_metrics_panel.dart` already reads — with one addition: **the shift strip is a query that
screen does not currently make.** A version without *Across the day* is a genuine restyle of the
daily summary and costs no extra read.

## What the sample content is allowed to say

Every figure comes from a field that exists. Amounts are `KES` because `TenantReportingCurrency`
supplies one and the artboards should not invent a symbol. Staff names on the shift strip come
from `staffId` resolved the way the shift history already resolves it. No card says who last
looked at a report or when — there is no such field.

The refusal wording is quoted from `TenantDeviceSalesRefusal`, and the four standings from
`TenantDailyMetricsStanding`, rather than rewritten.

## What these files are

Standalone HTML pages, hand-authored, no build step. Every colour and radius is quoted from
`lib/ui/tokens.dart`, but they are drawings: they do not prove the app runs, they cannot show
motion, and the spring behaviour a real pill selection owes `AppMotion` is not represented at all.


## What changed between the drawing and the code

Five differences, all of them the token layer or the data winning over a hex I had picked by eye.

1. **The tender bars are chart tokens, not hand-mixed greens.** The artboard used `#4BE277`,
   `#2FA85A` and `#1C6B39`; the code uses `AppChartRoles.bar` against `gridLine`, which is what the
   weekly report's bars already use. Hard rule 2.
2. **The selected pill's pressed state is `#22C55E`, not `#2FA85A`.** `action.primary` already
   carries a hover and a pressed container — `primaryFixed` and `primaryContainer` — so the pill
   reads them instead of naming its own.
3. **The pill's border is `borderStrong` (`#3D4A3D`), not `cardEdge` (`#283831`).** A pill is a
   control, and `borderStrong` is what the design's own CSS puts on a secondary button.
4. **The payment split is absent on a settled day.** The drawing showed it on every day. It is not
   in `daily_metrics` at all — only an unreconciled day gets it free, from
   `TenantSalesTotals.fromDevice`. The card now says *why* it is missing rather than showing
   nothing, because showing nothing reads as a day nobody paid for.
5. **The profit card has no heading.** `TenantProfitStatement` writes its own *Profit* row, so the
   card title printed the word twice.

## What the build turned up that the drawing could not

- **The screenshot fixture had never carried the `net` block** that #104 made required, so every
  seeded day was undecodable. Nothing caught it because the only reader was the seven-day window,
  which swallows a day it cannot read; reading one day *by name* surfaced it immediately.
- **The fixture seeded a reconciliation intake for today only**, so every other seeded day
  pictured *Cannot confirm* rather than *Reconciled*.
- **`FilterChipBar` already existed** and had to be argued against rather than ignored. See above.
- **The shift strip needs a composite index** (`status`, `businessDate`, `__name__`), now in
  `firestore.indexes.json` in both the scoped and unscoped shapes. **It has not been deployed.**


## The three fixture bugs this work uncovered, which are kept

These are `tool/screenshots/fakes.dart` and have nothing to do with the Reports screen; they were
latent and are fixed regardless of the reversal.

1. **`seedDailyMetrics` never carried the `net` block** that #104 made required, so **every seeded
   day was undecodable**. Nothing caught it because the only reader was the seven-day window,
   which swallows a day it cannot read; reading one day *by name* surfaced it immediately.
2. **Only today had a reconciliation intake record**, so every other seeded day pictured
   *Cannot confirm* rather than *Reconciled*.
3. **Every seeded sale was `cash`**, so any payment-split card could only ever photograph one bar
   — the one shape that cannot show whether a split is legible.

All three change existing screenshots, for the better. Revert them if that is not wanted.
