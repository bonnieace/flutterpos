# Bluetooth printer screen — a design, 2026-10-03

Three artboards for the **Bluetooth** tab of the printer page
(`lib/checkout/checkout_bluetooth_printer_panel.dart`), reached from the *Printer* row in
[Settings](../settings/README.md) and from the till when a receipt could not print. Open
[`index.html`](index.html) in a browser. Each page is self-contained HTML with no build step and
no dependency on the repo.

**Drawn after the build, the same day.** The tab was built first. These boards draw that build on
the token scale and propose a handful of changes to it, each listed below and marked *new* on the
states board. They were checked against the harness captures `36e-printer-bluetooth-found`,
`36f-printer-bluetooth-in-use` and `36g-printer-network-with-bluetooth-in-use`.

## Built, 2026-10-04

Every proposal in the table below is now in `checkout_bluetooth_printer_panel.dart`, the sheet
included. Asking for the redesign "pixel perfectly" was taken as the answer to *Your call*. The
harness captures use these boards' sample devices: `36e` first visit, `36f` in use, `36g` the
Network tab, `36h` found, `36i` the sheet, `36j` no printer. Each was measured against its board
at 411 @2x, and every line is within 1–2px.

**What the build needed and the boards did not draw:**

- **The business's printer settings unreadable.** This is a fifth card: *Network printer* with a
  *Not read* `problem` badge, and the sentence "Its settings cannot be read, so receipts from
  this device are not sent anywhere. Connect a Bluetooth printer below, or save the network
  printer again on the Network tab." The copy is new. It is not *Not set up*, because a business
  that already has a printer must not be invited to set one up again.
- **Answers while the sheet is open appear in the sheet**, as a callout under its title in the
  slot the before-pairing note uses. The page's snack bar is drawn underneath the sheet.
  *Connected* still closes the sheet and answers in the snack bar.
- **The sheet cannot be closed while it is working**, by the scrim or the back key, until the
  pairing, connection or test has answered.
- **Two component options:** `PressSurface.ringInside` puts the row's focus ring inside the card,
  and `Disclosure.indentChild: false` gives the no-name devices' card the full width.
- **The list's edge and hairlines are laid out, not just painted**, so rows do not drift from
  these boards by a pixel each.

**Corrected on the boards to what the build draws:** 20 between two buttons' faces
(`AppActionRow`'s `s12` plus each button's gutter), the app's checkbox (1px `border.strong` over
`surface.field`), the 16px spinner, and a disabled button keeping its glyph.

**Still not as drawn:** text renders about 3% wider in the harness than in Chrome, which is the
rasteriser and not the layout. The checkbox also sits 4px further right, from `CheckboxListTile`'s
own trailing padding.

**Open, and new:** against the sheet, the unticked checkbox's 1px `border.strong` edge is 1.6:1,
and against the page it is 2.0:1. Both are under the 3:1 a control's boundary needs. The edge
comes from the app-wide theme (`theme.dart`, `checkboxTheme`), so it is not changed here.

## The question the screen is opened with

**Will a receipt rung up on this phone come out of the printer on this counter?** Somebody opens
this tab in one of three situations: a little Bluetooth printer has just come out of its box, a
receipt has just failed to print, or a phone is being handed to a new cashier. In every one, the
first thing they need to know is where this phone's receipts go *now*. The second is how to point
them at the printer in front of them.

The build answers the first question only once a Bluetooth printer is connected. Until then the
tab opens on a heading and a search button, and *where receipts go now* is on the other tab.

## What the boards propose

| Part | Built | Proposed | Restyle? |
| --- | --- | --- | --- |
| Top of the tab | A card only when a Bluetooth printer is in use | **A card in every state**: the Bluetooth printer, the network printer with its address, or *No printer*. The tab always opens on its answer | Needs the business printer passed into `BluetoothPrinterTab` as a prop. The panel already holds it from the route guard, so there is no new read |
| The device list | One `ChoiceCardGroup` of radio cards | **Rows in a card, in two groups**: *Paired with this device* and *Nearby*, each with a count. Devices with no name fold into a `Disclosure` | Yes. The paired flag and the name are already on every device |
| Choosing a printer | A radio selects it; the paper width, cutter, *Connect* and *Test this printer* appear under the whole list | **A row opens an `AppSheet`** holding the paper width, the cutter, *Test print* and *Connect* | Presentation only, but the interaction changes from inline to a modal. **Your call** |
| Before pairing | A pairing callout appears only once pairing has started | The sheet says what will happen for an unpaired printer: *Connecting pairs it first…* | New copy. Yes |
| The printer in use, in the list | Radio card with the description *In use on this device* | Print glyph in `action.primary` plus the same words | Yes |
| *Bluetooth is off* | `attention`'s default clock glyph | `bluetooth_disabled` | Yes. `Callout.icon` exists |

**Why rows instead of radios.** A radio says *this one is chosen*. On this screen nothing is
chosen until the printer has answered a real connection, which is why *Connect* opens a link
before it saves anything. Tapping a radio and seeing it fill in claims a choice the app has not
made. A row that opens the printer makes no such claim.

**Why a sheet.** The paper width and *Connect* sit under the whole list. In the `36e` capture,
with only three devices found, *Connect* is at 874–922 logical pixels, already past the bottom of
an 891 screen, and each further device pushes it about 116 lower. A shop counter hears more than
three. In a sheet they arrive with the printer they belong to, under the thumb.

**Unchanged:** the transport, the device store, discovery, the pairing flow, the probe-before-save
rule, every refusal and every sentence the build already says (quoted, not rewritten), and the
Network tab apart from its one callout.

## Found while drawing, still open

1. **"Send it again" on a setup page.** The three Bluetooth failure sentences come from
   `PrinterFailureNotice`. They are shared with the print queue, where *Send again* is the control
   they refer to. On this page the controls are *Connect* and *Test print*, so the words point at a
   button that isn't there. A per-surface variant would fix it, but so far the vocabulary has been
   kept to one sentence per fault. **Your call.**
2. **The sheet's empty middle.** `AppSheet` rests only at its detents. At 0.7 of the screen, the
   sheet for one printer has about 200 pixels of nothing between the cutter row and the actions.
   The actions stay anchored to the bottom on purpose. A content-sized detent would be a change to
   the component.
3. **Not run on a phone yet.** The build has unit and widget tests and harness captures, but
   pairing, connecting and printing have not been done on a device.

## Deliberately absent

- **"Connected" as a standing state.** The app connects for each receipt and lets go, so nothing
  is held open between receipts. The card says *In use*, and *Connected* only describes what just
  happened, in the snack bar.
- **Paper, battery or cover status.** It would need the printer's status read back, which the
  transport doesn't do. `docs/printer_transport.md` §10 leaves it open.
- **"Last printed".** Nothing records receipts per printer.
- **Showing only printers.** Android knows a device's class (*imaging*), but `flutter_blue_classic`
  doesn't pass it through. Sorting or filtering by it would mean a plugin change, not a restyle.
- **Several Bluetooth printers on one phone.** It's one printer per business per device, which is
  what the device store holds.

## The sample content

Mwangi Hardware's network printer is the one the harness seeds, `192.168.1.50:9100` on 80mm. The
Bluetooth printer is an MPT-II, the common 58mm model, at a made-up address. The other devices
are what a shop counter actually hears: somebody's earbuds (paired), a second printer, a phone, and
two devices that broadcast no name.

## What these files are

Standalone HTML pages written by hand, with no build step. Every colour, size and radius is the
token the build reads (Profound Verdant), and every sentence marked *built* is the app's own.
Android's pairing prompt on the connect board is system UI, drawn only so the sequence reads; the
app does not style it.

They are drawings, and so are the captures they were checked against. The harness rasterises the
widget tree, so neither proves the app runs on a device, and neither can show motion. The phone
boards are 411, the harness's `mobile` viewport. There is no desktop board: Bluetooth printing is
Android only, and on a tablet the page is the same reading column, centred.
