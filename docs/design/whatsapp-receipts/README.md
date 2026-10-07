# WhatsApp receipts screen — a design, 2026-10-03

Three artboards for `TenantWhatsappReceiptsScreen` (`lib/whatsapp/e_receipt_settings_panel.dart`)
covering both of its tabs, **Settings** and **Sent receipts**. Open [`index.html`](index.html) in a
browser. Each page is self-contained HTML with no build step and no dependency on the repo.

The brief: minimal, with both tabs taking their cue from WhatsApp itself. The boards were checked
against the harness capture `whatsapp-receipts` (`screenshots/mobile-full/`), which shows the
Settings tab as built on 2026-10-03.

## The question the screen is opened with

**What does my customer get on WhatsApp, and did they get it?** The Settings tab answers the first
half and Sent receipts the second. For a shop without a printer, this is the receipt itself, so
both halves deserve to look like what the customer sees.

## As built, 2026-10-04

Implemented in `lib/whatsapp/e_receipt_settings_panel.dart`, with `ChoiceCardGroup(flat: true)`,
`AppSwitchRow(flat: true)` and `EmptyState(icon:)` added to `lib/ui/`. Harness captures:
`whatsapp-receipts` (all viewports), and `-summary`, `-off`, `-sent`, `-sent-empty` at `mobile`.
Measured against these boards at 2x, every block lands within 0.5px except where a drawn value
was off the token scale. Those were snapped to the nearest token and **the boards above were
corrected to match**:

| Where | Drawn | Built |
| --- | --- | --- |
| Summary bubble, space above the words | 6 | `space.8` |
| Bubble time, padding above / below | 2 / 2 | 0 / `space.4` |
| Reason line, space above | 2 | 0 |
| Bubble tail height | 10 | `space.12` |
| Document tile radius | 6 | `radius.md` |
| Avatar initials tracking | 0.5 | none |
| Reading bars: name, time, status | 14, 36 x 10, 12 | `space.16`, `space.32` x `space.12`, `space.12` |
| Empty state: gap under title, hint | 4, 14/21 | `EmptyState`'s own: `space.8`, density body 16/24 |
| Disclosure chevron, body top | 24, 0 | `Disclosure`'s own: 18, `space.4` |

Still different, and not corrected: a row's hover/pressed wash is 48 high inside its 56 slot (the
other 8 is `PressSurface`'s ring gutter); the read-only switch keeps its check; the harness's top
bar is the app's own toolbar, not the board's 56; and Flutter sets Hanken Grotesk a few percent
wider than Chrome, so one long status line ellipsises its receipt number at 411.

## What WhatsApp lends, and what it does not

**It lends shapes and vocabulary:**

- a chat bubble with its tail and the time inside it
- the day pill above the messages
- the document tile a PDF arrives in
- settings that are flat rows (glyph, title, control) on the page, not cards
- a chat list: avatar, name, time, and a status line under them
- the ticks: a clock, one tick, two ticks, and two ticks lit

**It does not lend its colours or its brand.** There is no WhatsApp green, no read-receipt blue,
no doodle wallpaper and no logo. Everything is Profound Verdant: the wallpaper is `surface.sunken`,
the bubble `surface.overlay`, the document tile `surface.raised`, and *read* is `action.primary`.
There are two reasons:

1. **Hard rule 2.** A WhatsApp palette would mean a token group created for one preview.
2. **A POS screen in another product's colours reads as that product.** The boards borrow the
   layout and conventions, not the brand.

## What changes

| Part | Built | Proposed | Restyle? |
| --- | --- | --- | --- |
| **Settings:** the preview | An `AppCard` at the foot, with the template text and `[Receipt-….pdf]` in brackets | **At the top, as a chat**: day pill, bubble, a document tile for the PDF, the time. It is the description the titles leave out, so it leads | Yes. The words are `eReceiptMessagePreview`'s, but the tile needs the file name apart from the text. Today it is appended to the string in brackets, so the function would return the two parts separately. It stays a pure function |
| **Settings:** what is sent, and when | Two `ChoiceCardGroup`s of bordered cards with glyph wells | **Flat rows**: glyph, title, radio at the end. The chosen row's glyph takes `action.primary`; a wash for hover and pressed | Needs a flat variant of `ChoiceCardGroup` with the same radio semantics, arrow keys and read-only rule. That is component work, not behaviour |
| **Settings:** section titles | `SectionHeading`, 22 | `labelMedium` 14/600 in `text.secondary` | Yes |
| **Settings:** *Where receipts come from* | A `Disclosure` under the switch | The same `Disclosure` at the foot, after a rule, above Save | Yes. Moves only |
| **Sent:** a row | A card per receipt: `receipt · who`, a reason or *Sent automatically / by hand*, and a `StatusBadge` | **A chat-list row**: avatar (initials, or a person glyph for a masked number), who and the time, then ticks, the status word, the receipt number and a bolt or hand glyph. The reason goes on a third line, only when there is one | Yes. Every field is already read. The time is `createdAt`, which the build reads and does not show. It is formatted the way WhatsApp does it: today's time, *Yesterday*, a weekday, then the date |
| **Sent:** status colour | `sent`, `delivered` and `read` all `ok` | Only `read` is lit (`ok`). `sent` and `delivered` are `text.secondary`, `queued`/`sending` are `info`, `failed` is `problem`, `skipped` is `neutral`. The word is always beside the glyph | Yes, but it changes what green means on this tab. **Your call** |
| **Sent:** the end of the list | Nothing | *The 20 most recent receipts* | New copy. Yes |
| **Sent:** empty | `EmptyState` with the file-search illustration | The same words under one glyph in a ring | Needs `EmptyState` to take a glyph where it takes an illustration today |
| **Sent:** reading | Card-shaped skeletons | An avatar circle and two lines, the shape of the row | Yes |

**Unchanged:** the reads, the status check, the seed, the publisher, Save and every answer it gets,
the switch, the guard and its denied and failure states, the tabs, and every sentence. Save stays
full width at the foot and is never disabled for an unchanged form, because that would be a
behaviour change. WhatsApp applies a setting the moment it is touched; this screen publishes to
every till through a queued write, so Save stays.

## Considered and left out

- **Filter chips** (*All*, *Not delivered*), as WhatsApp's chat list has. The tab reads the 20
  most recent receipts and stops, so a filter would mean "of the last twenty" while looking like
  "ever". Worth adding once the list pages.
- **Opening a receipt from its row.** Nothing on this screen routes to a sale, so it would be new
  behaviour.
- **Unread counts, pinned rows, search, photos.** There is nothing to count or pin, search would
  need a query, and customers have no photos here.
- **WhatsApp's colours and doodle wallpaper.** See above.

## Found while drawing, still open

1. **The preview and the message disagree when no business name is known.** The screen falls back
   to *your business* ("Thank you for shopping at your business."). The server falls back to
   `RECEIPT_WORDS.unnamedBusiness` ("Thank you for shopping at Sales receipt."). Both read oddly in
   a customer's chat, and they are not the same sentence. It is rare, because the registered
   business name fills the gap first. One fix is a callout that points to *Business details* when
   no name is set. **Your call.**
2. **The preview's file name is baked into its text.** `[Receipt-JOHN-CT-7F2-001.pdf]` is appended
   to the string, so drawing the document tile needs the two parts apart. See the first row of
   the table.
3. **`sent` and `delivered` stop being green.** This is deliberate, and it is a change of meaning
   on this tab (see the table).

## The sample content

Mwangi Hardware, as on the other boards. The customers are names a Nairobi counter would see. The
masked numbers are in the server's own format (`maskPhone`: `+254•••678`), and the receipt numbers
are in the till's format. The preview's receipt, `JOHN-CT-7F2-001` for KES 1,250.00, is the
template's own made-up one, exactly as the build draws it. The day pill and the time in the bubble
are drawn, not data.

## What these files are

Standalone HTML pages written by hand, with no build step. Every value is a token the build reads
(Profound Verdant), and every sentence is the app's own except *The 20 most recent receipts*.

They are drawings. The harness rasterises the widget tree, so neither the boards nor the capture
they were checked against prove the app runs on a device, and neither can show motion. The phone
boards are 411, the harness's `mobile` viewport. The first Settings frame is the whole page, as
the harness's `mobile-full` capture draws it. There is no desktop board: the screen is the
reading column at every width.
