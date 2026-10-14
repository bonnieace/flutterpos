# Tables — a design, 2026-10-12

Seven artboards for one table component, called **the sheet** in these boards, and for how it lands on
the screens that draw phone cards on a large screen today. Open [`index.html`](index.html) in a
browser. Each page is self-contained HTML with no build step.

**This is a proposal.** Nothing in `lib/` was changed to make it.

**What was built is simpler than the boards** (`lib/ui/record_sheet.dart`). These are the
developer's rulings:

- **2026-10-12:**
  - The table is drawn only from 1024 up.
  - Phones and 768–1023 keep their cards. The 834 condensed table and the phone list here were not
    built.
- **2026-10-13:**
  - The day band under the header and the sentence at the foot were both removed, and the component
    offers neither.
  - The columns are evenly spaced rather than each sized to its own widest value.
  - A staff member's uid sits under their name, not in brackets after it.

## The question the screens are opened with

*Which one?* Which shift was short. Which customer owes the most. Which count needs review. Which
receipt this customer is holding. Every screen here is opened to compare records and pick one out.

Today, on a 1232 or 1440 window, most of them draw the phone's card for each record at 1150 wide. A
person reads them one at a time, scrolling, with the figures in a different place on every card.
Shift history's card is 205 tall, so a 1232 × 635 window shows two shifts.

The brief: *"a table system/design that is a bit custom and fitting yet minimalistic and clear that i
can use for these screens."*

## What the sheet is

- **One object per list.** A `surface.raised` sheet holds the filters (the bar), a header, the rows,
  and the paging (the foot). The page carries only the toolbar.
- **Minimal:**
  - monochrome rows;
  - hairline row rules and one firm rule under the header;
  - no zebra striping, no vertical rules, no monograms;
  - status drawn only where something wants attention.
- **Fitted to a till.** These are the "custom" part:
  - Figures are in mono, right-aligned and grouped, with the unit stated once in the header.
  - Whole amounts keep the no-`.00` ruling, but hold `.00` as blank space, so digits still line up
    under `2,350.50`.
  - Day breaks look the way Shift history already heads its days.
  - A receipt's lines and a delivery's lines fold under their row. They align to the parent's
    columns, so the total column still adds up read straight down.
  - A total row is the one mint line in the sheet.
  - A figure with a reservation carries a symbol (`≤`, "at most") that is explained once, in the foot.

### Six rules

1. **Read across.** Everything on one 56-tall row. A caption line is allowed only under the identity
   or under a figure.
2. **Monochrome body.** Colour means state, always beside a glyph and a word. A sign is a real minus.
3. **Units once.** KES, UTC and units go in the header, not in the cells.
4. **Exceptions surface.** Settled states are quiet or absent; `StatusBadge` is kept for what someone
   should act on. A row in that state may promote the one action that resolves it, but only where
   other rows do not need it.
5. **Same data, same calls.** Rows, filters, paging, menus and role gates stay the screen's own.
6. **One component.** It is `RecordList`'s table grown up, so the catalog's and Staff's private tables
   can converge on it too.

## Where it came from

- **Matt Strom, [*Design better data tables*](https://mattstromawn.com/writing/tables/):**
  - right-align numbers, and align each header with its column;
  - use tabular figures;
  - keep rules light and horizontal, with no zebra;
  - keep the table monochrome;
  - show a unit once, not on every row;
  - flag notes with symbols, not shading.

  The `≤` footnote and the units-in-header rule are taken directly from it.
- **Shopify Polaris's
  [web Table](https://shopify.dev/docs/api/app-home/polaris-web-components/layout-and-structure/table.md):**
  - one component that renders a table on wide screens and a list on narrow ones;
  - every column declares what it becomes in the list (primary, secondary, inline, labelled);
  - a row's click goes to its primary action only;
  - paging suits lists longer than about 50 to 100 rows.

  The priority-and-fold rule at 834 and the optional phone list come from this.
- **Bank statements and the till roll** are where the ledger shape comes from: day breaks, signed
  changes beside a running balance, and a total under the column it sums.

## The boards

| Board | What it shows |
| --- | --- |
| [The sheet](tables-system.html) | Anatomy on Customers at 1440, numbered; the six rules |
| [Cells and rows](tables-cells.html) | Fifteen cell kinds; group, expanded, total and promoted-action rows |
| [States](tables-states.html) | Seven row states on Suppliers; seven sheet states |
| [Widths](tables-responsive.html) | Shift history at 1440 × 900, 1232 × 635, 1024 × 768, 834 and 390 |
| [Sales](tables-sales.html) | Sales Report, Shift history, Returns; why Notifications stays a list |
| [Reports](tables-reports.html) | Daily summary, Sales totals' payment breakdown, reconciliation runs, unresolved differences, Logs, Stock counts |
| [Records](tables-records.html) | Customers who owe, a customer's statement, Suppliers, a supplier's deliveries, Production, an expense type |

Every board was rendered with headless Chrome and read back before this was written.

## Screen by screen

| Screen | Today at 1024 and up | In the sheet |
| --- | --- | --- |
| Sales Report | A card per receipt with every line shown | A row per receipt, lines folded under it |
| Shift history | A 205-tall card per shift | A row per shift with a signed difference column |
| Returns | Cards; status in bare coloured capitals | Rows; `StatusBadge`; *Verify* promoted on pending rows |
| Daily summary | Seven cards | Seven rows and a total row |
| Sales totals | A report | Stays a report; the payment breakdown becomes a small sheet |
| Reconciliation runs | A card per run | A row per run, status first |
| Unresolved differences | A card per difference, every figure open | A row per difference, its figures folded; *Correct totals* promoted on shift rows |
| Logs | A timeline | A row per event, family glyph kept, no day grouping (the code rejected it) |
| Stock counts | Full-width cards with two big figure boxes | A row per count with a coverage fraction |
| Customers | Cards | The anatomy board's table; *Who owes* gains its total row |
| A customer's statement | A block per entry | A ledger: change, then what was owed after |
| Suppliers | A summary card, two full-width buttons, cards | A row per supplier, both actions in the bar |
| A supplier's deliveries | A card per delivery, lines always open | A row per delivery, lines folded |
| Production | A card per batch with a *View costs* button | A row per batch that opens the costs |
| An expense type | Ledger rows | Columns, the voided record muted and struck through |
| Notifications | A feed at 1150 wide | **Stays a feed**, at the 720 reading width |
| Platform console | Not drawn | It has its own design in [`../platform-console/`](../platform-console/) |

## Deliberate departures

1. **Status is drawn by exception.** A settled state (*Reconciled*, *Settled*, *Verified*,
   *Accepted*) is a glyph and a word in text colour, not a `StatusBadge`. A state the filter
   already implies (*Active*) is not drawn at all. `StatusBadge` itself is unchanged and is kept for
   states that want action. This answers the 2026-10-08 ruling against rows of tinted badges.
2. **Money in a table body is `text.primary`, not mint.** `RecordValueKind.money` paints
   `text.money` today, and the catalog's own table paints both its selling price and its retail
   value mint. In the sheet, mint marks a total and nothing else.
3. **The currency code moves to the header.** A cell reads `1,250`; the header reads `TOTAL KES`.
4. **Figures in a table are grouped in thousands.** They use `moneyTextGrouped`, which exists. The
   no-`.00` ruling of 2026-09-23 holds: the `.00` is blank space, drawn only in a column where some
   value has cents.
5. **`medium` (768 to 1023) is a condensed table, not two cards per row.** Columns fold into the
   identity's caption by declared priority. This changes `RecordList` for every screen that uses it.
6. **A person is shown by name.** `tenantStaffLabel` appends `(uid)` to every name, which reads
   `Amina Hassan (manager-dev)` in the harness. In a table, the uid moves to the row's screen-reader
   label. See open question 1.
7. **One header style.** The catalog's upper-case `labelEyebrow` in `text.tertiary`. `RecordList`'s
   sentence-case `labelMedium` header goes, so the two tables stop disagreeing.
8. **A row press does what a button on the card did.** Daily summary's *Why is it in this state?*,
   Production's *View costs*, and Returns' view button all become the row. Each keeps its callback
   and its role gate.

## New tokens

These are layout tokens, added beside `AppLayout`'s others.

| Token | Value | Why |
| --- | --- | --- |
| `layout.tableRow` | 56 | A 48 control with 4 above and below, the reasoning `hubBarHeightCompact` already uses. Two lines (20 + 16) fit inside it. |
| `layout.tableHeader` | 40 | The header and group rows. `space.40` by value, but named so it cannot drift. |
| `layout.tableDisclosure` | 32 | The fold column; its 48 target overhangs into the row's padding. |
| `layout.tableMeter` | 64 | The coverage track. Its height is `space.4`. |

Everything else is an existing role: `surface.raised`, `surface.sunken` and `surface.overlay`, the
three borders, the four text inks, `numericBody`, `monoCaption`, `labelEyebrow`, `labelMedium`,
`caption`, `StatusBadge`, `AppButton`, `Pagination`, `SkeletonLine`, `EmptyState` and `Callout`.

## What it takes, and what is not a pure restyle

**Mostly layout.** Each screen keeps its repository, queries, paging, filters, menus and role gates.
It hands its rows to the sheet instead of building cards. That is `CLAUDE.md` rule 1 kept, screen
by screen.

**`RecordList` grows. This is a component API change, not a behaviour change:**

- column kinds beyond `text` / `code` / `money`:
  - count, change, signed figure, percent;
  - time, day, person;
  - settled state;
  - progress;
- a priority on each column, replacing the single `inNarrowForm` flag;
- group rows, a total row, and a foldable row (the `details` slot exists already);
- a row-press callback and one promoted action;
- column widths measured per kind. `RecordTableColumns` already measures through `measureTextWidth`.

**These are additions, not restyles. Each is drawn, and each is yours to decide:**

- Daily summary's **7-day total row**. All seven days are on the page, but the screen does not print
  a sum today.
- **Received by** on a supplier's deliveries. The delivery holds the uid and no screen shows it; it
  would need a staff-name lookup.
- **Receipt and delivery lines folded by default.** Today they are always open. Folding hides
  information until a row is opened.
- **Arrow keys between rows.** Tab order is drawn; arrow-key movement would be new.

**The catalog's and Staff's tables** already draw their own tables. Moving them onto the sheet is a
separate step from the screens above.

**Notifications** needs only the `reading` width: a one-line change, not drawn.

**Phones** are unchanged unless you ask. The 390 list on the Widths board is offered, not proposed.

## Accessibility

- **Contrast on `surface.raised`:**
  - `text.tertiary` 5.27:1, `text.secondary` 9.77:1, white 15.23:1;
  - problem red 5.08:1, mint 10.4:1.
- **Contrast on a hovered or pressed row (`surface.overlay`):**
  - tertiary 4.68:1, problem red 4.51:1.
  - A mint-tinted hover was measured and rejected: it drops tertiary to 4.35:1.
- **Targets:** rows are 56; the kebab, the disclosure and every button are 48.
- **Focus:** the row's ring is drawn inside it, because rows above and below would paint over an
  outside ring. Tab goes row, then kebab, then the next row. Enter opens the row.
- **Not by colour alone:** every status has a glyph and a word; every negative has a real minus;
  every change has a triangle.
- **Screen readers:** a row's label is built from header and cell together ("Recorded, 2,315
  shillings"), so a unit that moved into the header is still heard. The uid and the till receipt
  number move there too.

## Motion

- **Folding a row is spatial.** It opens on a spring and reverses from wherever it is if pressed
  again, as `CLAUDE.md` requires.
- **Hover and press fills** are `PressSurface`'s own state changes.
- **The skeleton** sweeps as it does today.
- **Nothing on the sale path changes.** None of these screens is on it.

## Open questions

1. **Names without uids.** Is `Amina Hassan` enough in a table, or does the uid suffix exist to tell
   two staff with one name apart? If so, a table could show it only when two names collide.
2. **Arrow keys** between rows: worth adding?
3. **"Not sent yet" on a queued supplier.** Does the supplier list know today that a supplier was
   made offline and not yet sent? The States board draws it, and it should only be built where the
   list already knows.
4. **Received by** on deliveries, and the **7-day total** on Daily summary: keep or drop?
5. **Sorting by a column** is not drawn. Every screen's order comes from its query, and changing it
   is behaviour.
6. **Condensed table or two cards per row at 834?** The boards propose the table.
7. **Phones:** keep today's cards, or take the list form?

## A harness problem found while drawing this

The Sales Report captures (`screenshots/*/sales-report-*.png`) show the failure state, *"The sales
for this day could not be read."* `FakeTenantReader.readDocument` (`tool/screenshots/fakes.dart`)
serves only its `documents` map, and the seeded sales are not in it. As a result:

- loading the day's returns throws `return_sale_missing`;
- the Returns feed falls back to `co-1` and "Sold —".

The 1440 day-report capture (`25c`) also draws yellow double-underlined text, which means no
`Material` ancestor. Neither problem comes from this design. Both mean the existing captures of
those screens cannot be used to compare against it.

## What these files are

HTML mockups. They do not prove the app runs, they cannot show motion, and the spring the fold owes
`AppMotion` is not represented. The sample rows follow the harness's cast at Dev Corner Shop (Grace
Wanjiru, Peter Otieno, Amina Hassan, Brian Kimani, Faith Njeri; the seeded products, suppliers,
batches and expenses). A screen whose fixtures hold one record was given more, so its table could be
judged full.
