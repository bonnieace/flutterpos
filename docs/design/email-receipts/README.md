# Email receipts screen: a design, 2026-10-04

These are three artboards for `TenantEmailReceiptsScreen` (`lib/email_receipts/email_receipts_screen.dart`).
They cover both of its tabs, **Settings** and **Sent receipts**. Open [`index.html`](index.html) in a
browser. Each page is self-contained HTML with no build step and no dependency on the repo.

The brief had two parts. Sent receipts takes its cue from the way Gmail arranges its inbox.
Settings follows what was done for WhatsApp receipts (`docs/design/whatsapp-receipts/`, built
2026-10-04). This screen has no harness capture yet. The boards were checked against the code on
`feat/email-receipts`. The parts it shares with WhatsApp were also checked against the
`whatsapp-receipts` captures.

## The question the screen is opened with

**What does my customer get by email, and did it reach them?** The Settings tab answers the first
half and Sent receipts the second. A customer sees an email receipt as a line in their inbox
before they open it, so both tabs are drawn as inbox rows.

## Settings: the WhatsApp tab, one choice shorter

It has the same parts as the built WhatsApp tab, in the same order: the preview, the switch, the
timing rows, a rule, *Where receipts come from*, and Save. It has no *What the customer gets*,
because an email always carries the whole receipt with the PDF attached.

Every part except the preview already exists in `lib/ui/`, added by the WhatsApp build:
`AppSwitchRow(flat: true)`, `ChoiceCardGroup(flat: true)`, `Disclosure` and `EmptyState(icon:)`.
They are in the working tree and not yet committed. The preview is the only new widget.

## What Gmail lends, and what it does not

**It lends its arrangement:**

- a list label above the rows (*Inbox*, in the preview)
- a round avatar holding one letter: the first letter of the name, or of the address
- who on the first line, with the time at its end
- the subject on the second line and a snippet on the third
- unread in bold, used in the preview only, because the customer's receipt arrives unread
- the attachment chip under the snippet, also in the preview only
- the avatar set at the top of the row, not centred
- Gmail's time ladder: today's time, then the date, with the year once it is not this year's
- a glyph at the row's right edge, where Gmail keeps its star

**It does not lend its colours, its brand or its gestures.** The boards use no Gmail red, no
per-sender avatar colours, no logo, no star and no swipe. Everything is in Profound Verdant: the
inbox is `surface.sunken`, the avatar is `surface.overlay`, and the chip's edge is `cardEdge`.
There are three reasons:

1. **Hard rule 2.** Avatar colours would mean a token group created only for decoration.
2. **A POS screen in another product's colours reads as that product.** The boards borrow
   Gmail's layout, not its brand.
3. **Gmail's avatar colours carry no meaning.** On this screen a colour would look like a status.

The *Inbox* label is the generic word, not Gmail's *Primary*. A customer might read their mail in
any client.

## What changes

| Part | Built | Proposed | Restyle? |
| --- | --- | --- | --- |
| **Settings:** the preview | An `AppCard` at the foot, below the timing cards: the sender, the subject, then the title and lead with `[Receipt-….pdf]` in brackets | **At the top, as an inbox**: an *Inbox* label, then one unread row with the letter avatar, *Mwangi Hardware via UzaPay* and the time, the subject, the preheader as the snippet, and the PDF as a chip. The subject and snippet get one line each. Shown only while receipts are on, as now | Mostly. `emailReceiptPreview` would return the snippet and the file name as separate values. It stays a pure function. The snippet would also become the preheader's words (open item 1) |
| **Settings:** the switch | `AppSwitchRow` | `AppSwitchRow(flat: true)`, as on WhatsApp | Yes |
| **Settings:** when it is sent | A `ChoiceCardGroup` of bordered cards | `ChoiceCardGroup(flat: true)`: glyph, title and radio, with the chosen glyph in `action.primary` | Yes |
| **Settings:** section title | `SectionHeading`, 22 | `labelMedium` 14/600 in `text.secondary` | Yes |
| **Settings:** *Where receipts come from* | Under the switch | At the foot, after a rule, above Save | Yes. It only moves |
| **Sent:** a row | A card per receipt: `receipt · who`, then a reason or *Sent automatically / by hand*, then a `StatusBadge` | **An inbox row**: a letter avatar; who, with the time; *Receipt* and its number, with a bolt or a hand at the edge; then the status as a glyph and a word, followed by the reason after a dot when there is one. With no receipt number yet, the row is two lines | Yes. Every field is already read. `createdAt` is read but not shown today |
| **Sent:** status | `sent` and `delivered` both badged `ok` | A glyph and a word for each: a clock (`info`), a paper plane for *Sent* (`text.secondary`), an inbox tray for *Delivered* (`ok`), an error glyph (`problem`), a minus sign (`text.tertiary`) | Yes, but *Sent* stops being green (open item 3) |
| **Sent:** the end of the list | Nothing | *The 20 most recent receipts*, the line the WhatsApp tab has as built | Yes |
| **Sent:** empty | `EmptyState` with the file-search illustration | The same words under the mail glyph in a ring | Yes, with `EmptyState(icon:)` |
| **Sent:** reading | Card-shaped skeletons | A circle and one bar in each of the three line boxes, so the real rows land without moving anything | Yes |

**Unchanged:** the reads, the seed, the publisher, Save and every answer it gets, the switch, the
guard with its denied and failure states, the tabs, the read-only and damaged-setting notices, and
every sentence except where the table says otherwise. Save stays full width at the foot, and it is
never disabled for an unchanged form, because that would change behaviour.

The row, the avatar, the skeleton and `_KeptTab` nearly duplicate WhatsApp's. When this is
built, they are worth sharing between the two screens rather than copying.

## Found while drawing, still open

1. **The preview's snippet is not what an inbox shows.** The build's preview body is the email's
   title and lead. An inbox shows the preheader first: *KES 1,250.00 at Mwangi Hardware, 1 Oct
   2026. The receipt is below and attached as a PDF.* The boards draw the preheader. Both
   versions are the server's own words (`template.ts`). **Your call.**
2. **The preview and the email disagree when no business name is known.** WhatsApp has the same
   problem. The screen falls back to *your business*, so its preview reads *your business via
   UzaPay*. The server sends from *UzaPay*, with the subject *Receipt JOHN-CT-7F2-001* and *at the
   shop* in the preheader. The server's version reads well and the screen's does not. Matching it
   means `_BusinessName` returning nothing instead of a phrase. That is a change to a read, so it
   is not a pure restyle. It is rare, because the registered name fills the gap first. The states
   board draws both versions. **Your call.**
3. ***Delivered* is lit here, and *Sent* is no longer green.** An email has no *Read* (UzaPay's
   emails carry no tracking pixel), so *Delivered* is as far as a receipt is ever known to get,
   and it takes `ok`. On the WhatsApp tab *Delivered* stays plain, because *Read* comes after it.
   On both tabs, then, green means "as far as it can go". The same word ends up in two colours on
   sibling screens. **Your call.**
4. **There are two time ladders.** This tab drops *Yesterday* and the weekday, as Gmail does.
   WhatsApp's tab keeps them. If you want one ladder on both tabs, WhatsApp's
   `receiptDeliveryWhen` serves this tab unchanged.

## Considered and left out

- **Gmail's search bar, its category tabs and its filter chips.** The tab reads the 20 most recent
  receipts and stops. A search or a filter would mean "of the last twenty" while looking like
  "ever". They are worth adding once the list pages, on both tabs.
- **An attachment chip on every sent row.** A chip reads as something to open. Opening a receipt
  from this list would be new behaviour, and the receipt number on the subject line already says
  which receipt it was.
- **The star, swipe to archive, tapping the avatar to select, and bold for unread in the list.**
  There is nothing here to star, archive, select or read.
- **The address under a customer's name.** It would add a line to every row, and a shopkeeper
  knows the customer by name. A row with no name already shows the masked address.
- **The opened email in the preview.** The inbox row answers what the customer gets. The
  Disclosure says what is inside the email, and `email-previews/email-receipt-390.png` shows it.
- **A second Settings frame for *by hand*.** Timing changes only a footnote at the end of the
  email, and an inbox does not show it. The read-only frame shows the by-hand row instead.

## The sample content

The shop is Mwangi Hardware, and the customers are the same as on the WhatsApp boards. Masked
addresses are in the server's own format (`maskEmail`: `n•••@gmail.com`). Rows that show only an
address were sent by hand. An automatic receipt goes to a saved customer who agreed, and every
saved customer on these boards has a name. *Today* on the boards is 3 Oct 2026, and the receipt
numbers are in the till's format. The preview's receipt is the template's made-up one,
`JOHN-CT-7F2-001` for KES 1,250.00 on 1 Oct 2026, exactly as the build's preview uses it. The
*Inbox* label and the time in the preview are drawn, not data.

## What these files are

They are standalone HTML pages written by hand, with no build step. Every value is a token the
build reads. Every sentence is the app's own or the server's, except two: *Inbox*, which is new,
and *The 20 most recent receipts*, which the WhatsApp tab already has.

They are drawings. They were rendered in headless Chrome and checked by eye. They do not prove the
app runs on a device, and they cannot show motion. The phone boards are 411 wide, the harness's
`mobile` viewport. The first frame of each tab is the whole page. There is no desktop board,
because the screen is the reading column at every width.
