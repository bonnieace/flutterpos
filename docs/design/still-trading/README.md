# Still trading — a design, 2026-10-12

Three artboards for the explanation the Sales report gives when it opens after midnight on a business
day that is still trading. Open [`index.html`](index.html) in a browser. Each page is self-contained
HTML with no build step.

**Built the same day**, at the developer's request, as
[`trading_day_explanation.dart`](../../../lib/sales/trading_day_explanation.dart). The boards were
then corrected to what the build draws: see *Where the build departs from the boards* below.

## The question the screen is opened with

*Why is the report on yesterday, and is that the day I want?* A manager who opens Sales at 01:30
expects today. The report has deliberately opened on Sunday, because a shift from Sunday is still
selling and every sale it takes is filed under Sunday. The explanation has one job: make that
obvious in a glance, and let them go to today if they really meant it.

The brief: *"still trading modal into something more custom and minimalistic."*

## What it replaces

The modal shipped earlier today is the stock `AppDialog`:
- a title;
- an info `Callout` inside the dialog, which puts a box inside a box with a glyph;
- *Don't show again* as a tertiary link;
- two buttons, *Show today* and *Show 12 Oct*.

It is correct, but it is a template: the same frame any notice in the app would get, saying in a
paragraph what could be shown.

## What changes

### 1. The night is drawn, not described

The sheet draws the business day as the span it really is:
- **Start:** the shift's opening time on the left.
- **End:** the moment it stops selling on the right. That is 06:00, or 24 hours after it opened if
  that comes first.
- **Midnight:** a notch where midnight falls between them.
- **Now:** the fill runs up to now, with a mark and a "Now 01:30" label.

One look answers "why Sunday": the night started on Sunday, and it isn't over.

The idea comes from how restaurant POSes describe a business date. [NCR Aloha's
documentation](https://docs.ncrvoyix.com/restaurant/aloha-cloud/using/understanding_business_dates)
says a restaurant that opens at 5 p.m. Monday and closes at 4 a.m. Tuesday has one business date.
That is a span crossing midnight, which is exactly what this draws.

It is built from `AppMeter`'s geometry rather than a new component:
- an 8 track (`space.8`) at `radius.pill`, filled with `status.ok`;
- two additions: the midnight notch and the now mark.

### 2. Nothing inside the frame but the answer

- No `Callout` in the dialog and no info glyph.
- **Eyebrow:** the date, "SUN 11 OCT · BUSINESS DAY".
- **Title:** the weekday, "Still trading on Sunday".
- **Body:** one sentence on what it means and until when.
- **Below the body:** the night, then the answers.

### 3. Weekdays, not dates

The title and the primary button say **Sunday**. At 01:30 people think "is it still Sunday",
not "is it still the 11th". The date stays in the eyebrow, so nothing is lost.

### 4. A sheet on phones, a dialog from 768 up

- **Below `medium` (768):** a bottom sheet (`surface.overlay`, `radius.lg` top corners, the 32×4
  handle). Both answers sit under the thumb, stacked full width with the primary first.
- **From 768 up:** a 520 dialog. The answers are on one line, with *Don't show again* on the left,
  where a desktop dialog puts it.

### 5. *Don't show again* is a checkbox

Today it is a third answer that silences and closes. Here it is a checkbox that either answer
carries, and so does a swipe down. A manager can say "I get it, show me today, and stop
explaining" in one press.

## Deliberate departures

- **The track uses `border.strong`, not `AppMeter`'s `border.subtle`.** The meter sits on a card;
  here the track sits on `surface.overlay`, where `border.subtle` measures 1.09:1 and disappears.
  `border.strong` is 1.56:1. That's enough to see the track. It doesn't need to carry meaning: the
  labels and the ok fill (8.0:1) do that.
- **Times are in `typography.monoCaption`** (JetBrains Mono, 12), so the three clock times line up
  as figures.
- **The dialog is 520 wide**, named `layout.explanationDialog` in the token layer. `AppDialog` caps
  at `reading` (720), and `NoticeDialog` takes `AlertDialog`'s own width. 520 is the narrowest width
  that keeps the foot on one line.
- **The mark is 16 with a 4 ring in the surface colour, and the notch is 2×16.** These are composed
  from `space.16`, `space.4` and `TradingNightTrack.notchWidth`. There is no stroke token, as the
  sales report's own `_hairline` already records.

## Where the build departs from the boards

The boards were corrected to match each of these after the build.

- **"Now" is `caption` at 400**, not the 600 first drawn. That weight is off the scale, and
  `status.ok` already sets the label apart.
- **The checkbox is the app's themed `CheckboxListTile`**: a `surface.field` box with a 1px
  `border.strong` edge. The first boards drew a bare outline. The theme's checkbox brings its own
  hover, focus, pressed and disabled states.
- **The label is *Don't show again*.** That is the till's wording for the same choice.
  *Don't show this again* wrapped to two lines in the 520 dialog.
- **The dialog is a plain `Dialog`, not `AppDialog`.** The night measures itself with a
  `LayoutBuilder`, which `AlertDialog`'s intrinsic sizing cannot ask. The surface, corners, inset
  and scrim are the same rows `AppDialog` reads.
- **The sheet is `showAppFittedSheet`**, new in `lib/ui/sheet.dart`. `showAppSheet` snaps to 70% or
  95% of the screen, which left this paragraph at the top of a mostly empty sheet. The fitted sheet
  is as tall as its content and breaks two existing sheet rulings, because it holds no form:
  - **A drag down closes it.** The developer ruled on 2026-09-23 that no drag dismisses a sheet.
    Its handle now says so.
  - **It has no close control.** The developer ruled on 2026-10-05 that every sheet has one. This
    one ends in its two answers.

## What the build changed beyond pixels

1. **`TenantOpenTradingDayRepository.read` returns a `TenantOpenTradingDay`**, not a date. It
   carries the first opening, the last stop, how many shifts there are, and whether they are the
   reader's own. It is the same query.
2. **The checkbox rides on the answer.** Silencing happens alongside *Show Sunday*, *Show today*,
   or a dismissal, instead of being its own answer.
3. **Phones get the sheet and 768 and up get the dialog.** This is a presentation branch only.
4. **"Now" is the moment the report opened.** It doesn't tick. If someone leaves the sheet open
   across 06:00, it still says what was true when it opened. That matches the report, which also
   decides its day once.

## Accessibility

- **The night is one image with a sentence:** "Shift opened 18:02 on Sunday. It is now 01:30. It
  stops selling at 06:00." Nothing in it is told by colour alone; every mark has its words.
- **Contrast on `surface.overlay`:**
  - `text.tertiary` (`#849E8F`) measures 4.7:1;
  - `text.secondary` is 8.7:1 and `status.ok` 8.0:1;
  - the unfilled track is 1.56:1, decorative, as noted above.
- **Targets:** both buttons are 48, and the checkbox row is 48 with a 40 halo.
- **Focus:** opens on *Show Sunday*. The order follows reading order:
  - on the sheet: *Show Sunday*, *Show today*, the checkbox;
  - on the dialog: the checkbox, *Show today*, *Show Sunday*.

## Motion

The sheet and the dialog come in with the app's existing transitions. Nothing in the night moves:
no pulse on the now mark. It is a still picture of a moment, and the spring rule in `CLAUDE.md` is
not engaged.

## Open questions

1. **After *Don't show again*, is the date button enough?** The report still opens on Sunday, and
   only the date button says so (the last section of the states board). If that's too quiet, one
   caption under the button ("Still trading · stops 06:00") would say it without bringing the sheet
   back. Built without it.
2. **Two shifts open:** the night starts at the first one to open ("17:40 first opened"). A
   per-shift line felt like a report inside the explanation, so it was left out.
