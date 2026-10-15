# Daily trading report PDF — a design, 2026-10-14

Four boards for the PDF that `sendDailyWhatsappReport` (`functions/src/dayReport/`) attaches to
the 08:00 WhatsApp message. Open [`index.html`](index.html) in a browser. Each board is
self-contained HTML with no build step.

The boards are drawn **in pt on an A4 page (595 × 842)**, the unit pdf-lib draws in, so every
measurement carries straight into `reportPdf.ts`. Fonts are the two Noto Sans weights the
functions already embed (`functions/assets/fonts`); colours are `main`'s own `TColors`
(`lib/constants/colors.dart`).

## The question the report is opened with

**How did last night go, and is anything wrong?** It's read on a phone at 08:00, often only as
the WhatsApp thumbnail, so the top third of page 1 answers it: the date, the total and its three
supporting figures, and a warning if a shift was never closed. Everything below that explains the
total: *when* it was sold (by hour, with who was on shift), *how* it was paid, *what* sold. Page 2
onwards is the item list, for whoever wants to check stock against it.

## As built, 2026-10-14

Implemented in `functions/src/dayReport/reportPdf.ts`, and checked against Thamani's real
13 Oct (rendered, not sent) and the sample. Business name and town are fixed in the code
(`BUSINESS_NAME`, `BUSINESS_TOWN`), as Thamani's invoice has them. Real data changed three things,
and the boards were corrected to match where they differed:

- **The axis stops at the till's 05:00 cutoff.** A shift left open keeps stamping its sales with
  the date it was opened on, so on 13 Oct one unclosed shift had stretched the axis to 14:00 the
  next day. Sales after the cutoff are one line beside the chart: "After 05:00 · KES 600 · 1 sale".
- **A time on a later day carries its weekday**: "First · last sale 11:26 · Wed 13:47", and a
  shift's "closed Wed 13:57 →". One that closes the same evening, after the last sale, says
  "closed 23:48 →".
- **Page 2's column headings** sat 6 pt right of the figures under them on the board; the board
  now pads them like the rows.

## Where the layout comes from

End-of-day reports in other POS products ([Vori](https://help.vori.com/reporting/daily-and-shift-reports/review-and-print-the-end-of-day-report),
[SaleDock](https://help.saledock.com/en/articles/9101255-end-of-day-report),
[TillClose](https://pickyourapp.com/products/tillclose)) share a shape: a headline total with the
order count and average basket, an hourly sales chart near the top, payment methods, then
category sales. This report keeps that order, and adds one thing they don't have: **the shifts
drawn as lanes on the chart's own time axis**. At Thamani, three or four shifts overlap on most
days, and a busy hour is only meaningful next to who was serving in it.

## Boards

| Board | What it shows |
| --- | --- |
| `page-1.html` | Masthead, total, open-shift warning, trading day (hourly bars + shift lanes), payments, categories |
| `page-2.html` | Items by category, two columns, running head |
| `quiet-day.html` | A date with no shifts and no sales |
| `whatsapp.html` | The message as it arrives: the page-1 thumbnail, the file row, the template text |

Sample data is made up, but shaped on Thamani's real 13 Oct: 123 sales, KES 49,010, trading from
11:00 to 02:00, four overlapping shifts of which two were never closed, and its real categories
and items. Staff names are invented.

## Tokens

| Token | Value | From | Used for |
| --- | --- | --- | --- |
| `ink` | `#232323` | `TColors.black` | text, the masthead rule |
| `ink-2` | `#4F4F4F` | `TColors.darkerGrey` | secondary text, the chart's zero line |
| `muted` | `#6C757D` | `TColors.textSecondary` | labels, axis text, sizes, prices (4.7:1 on white) |
| `hairline` | `#E0E0E0` | `TColors.grey` | row and section rules, gridlines |
| `band` | `#F6F6F6` | `TColors.light` | category bands on page 2 |
| `brand` | `#4B68FF` | `TColors.primary` | the peak bar, shift start caps, Cash. **Fills only**: 4.3:1 is too low for small text |
| `brand-tint` | `#B0C7FF` | `TColors.accent` | hour bars, shift spans, category share bars, hero dividers |
| `brand-wash` | `#F3F5FF` | `TColors.primaryBackground` | the hero panel |
| `mpesa` | `#388E3C` | `TColors.success` | M-Pesa |
| `debt` | `#F57C00` | `TColors.warning` | Debt, the warning's border and icon. **Never text**: 2.9:1 |
| `other` | `#939393` | `TColors.darkGrey` | any payment method beyond the three |

Type, all Noto Sans: display 34 bold (the total) · title 15 bold (the date) · value 14 bold ·
section 9.5 bold, tracked 0.8, upper case · body 8.5 · small 7.5 · micro 6.5 bold, tracked 0.6,
upper case. Noto Sans' digits are all 572 units wide, so columns of figures align without
OpenType features, which pdf-lib can't apply.

Geometry: margin 40 · content 515 · on page 1, three columns shared by the chart, the lanes and
"What sold": a 96 gutter (names, axis labels), a 315 plot (the time axis, share bars), and 104 for
figures (36 for counts, 68 for KES). Page 2 has two 245.5 columns with a 24 gap; item rows are 15
high, category bands 20. Footer 24 from the bottom edge.

## Rules the code must keep

- **The time axis runs from the hour of the first sale to the hour after the last**, so a bar
  covers its hour, and a shift starts and ends at its real minutes on the same axis. Labels every
  two hours.
- **The chart's scale rounds the busiest hour up to a step of 1, 2.5 or 5 × 10ⁿ**, with three
  gridlines plus zero. Only the busiest bar is `brand` and labelled; it's also named in words
  beside the chart, so it never depends on colour.
- **A shift that is still open** is hatched to the axis end and says "still open". **A shift that
  closed after the axis ends** (Thamani's are often closed the next afternoon) runs to the edge
  and says when, e.g. "closed Wed 13:57 →". Both say it in words, not only in shape.
- **The open-shift warning appears only when a shift is open at send time.** It's the only use of
  `debt` outside the payments bar.
- **Payment percentages are rounded so they add to 100.** A segment under 2% still draws at least
  3 pt wide, so it's visible.
- **"What sold" bars scale to the biggest category**, not to the total, so small categories still
  show; the percentage beside each bar is of the day's total.
- **Page 2 fills the left column, then the right, then a new page**, in "What sold" order. A
  category that breaks across a column or page repeats its band with "continued".
- **Sizes are muted after the name** ("Viceroy 375ml"); an item sold at more than one price shows
  the average, to the shilling.

## Departures from the PDF as it is today

- **The hourly chart is new data.** Every sale on `main` has `dateAdded` (checked on Thamani's
  11, 12 and 13 Oct: 371 of 371 sales), so `buildDayReport` needs to bucket it by Nairobi hour.
  That's an addition to the data the report reads, not only to its drawing.
- **Average sale, items sold, first and last sale, and the busiest hour** are new derived figures.
- **Business name and town** ("Chilltent Lounge", "Juja") come from the printed invoice
  (`lib/api/pdf_invoice_api.dart`). The report has no other source for them, so they would be two
  new parameters beside the recipient.
- **The → in "closed Wed 13:57 →" is not in the embedded font subset**, so it's drawn as a small
  vector arrow. The en dash and the middle dot are in the subset.

## Left out, deliberately

- **No cash drawer.** Shifts on `main` have `openingCash` and `closingCash`, but on Thamani they
  are 0 on every shift checked (12 shifts over 11–13 Oct). A column of zeros would only be noise.
  It can come back if the till starts recording them.
- **No logo.** Thamani's printed receipt and invoice carry the name only; so does this.
- **Category names are shown as stored** (upper case at Thamani). Re-casing them would make the
  report disagree with the app.

## Open

- **Split sales.** Their item quantities are inflated on `main` (left unfixed on 2026-10-14), so on
  a day with split sales the categories add up to more than the total. The design has no note for
  that. Say if you want one under "What sold".
- **"Debt"** is the till's word. If the owner says "credit", it's a label change.
