# Register, 768 and up — a design, 2026-10-11

Four artboards for the two-pane till, `_wideLayout` in
[`checkout_cart_panel.dart`](../../../lib/checkout/checkout_cart_panel.dart). Open
[`index.html`](index.html) in a browser. Each page is self-contained HTML with no build step and no
dependency on the repo.

**This is a proposal, not a record.** It draws pixels only. No widget, test or token was changed to
make it.

**Phones are untouched.** Below 768 the till stays as it is today: the products, with the cart behind
`_CartBar` and its sheet. Read the implementation note at the end before building any of this,
because the cart line and the foot are shared with that sheet today.

## The question the screen is opened with

*Which product is this, and what does the sale come to?* A cashier at a tablet or a desktop till is
looking at two things all day: the grid they pick from and the running sale beside it. The brief
names one failure in each:

> item cards in inventory dont show images and the checkout to the right is not layed out well — a
> single item card takes up too much height, same to the bottom part i.e. totals and save sale.

Measured on the 1024 × 768 harness capture (`screenshots/desktop-narrow/15-new-sale-with-a-cart.png`),
the cart pane showed **2.3 lines**. Each line was a bordered card about 150 tall, and the foot took
240 of the pane's 704, or about 300 when *Agree a price* and *Put on credit* were offered.

## What changes

### 1. The tiles get their pictures back

The wide tile is `_denseBody`. It has no picture by design: its doc comment says *"the grid's job is
density rather than recognition"*. The brief overrules that, and so does the legacy till this
rebuild has been leaning toward, whose `ProductCardWithImage` led with an 80-high picture band.

- **The tile is 204 tall, up from 128.** A 96 picture band sits on top. Under it come the name on up
  to two lines, the size, then the price and stock over the add glyph. That is the phone tile's
  grammar at a wide tile's proportions.
- **The picture is `TenantProductVisual`, unchanged.** A product with no photo shows its initials at
  `title.lg`.
  - **A photo fills the band and is cropped, not drawn whole.** These boards draw cut-outs
    contained in the band, which overstates the build: the visual uses `cover`, because `contain`
    was tried on 2026-09-04 and gave "a till of postage stamps". At 96 tall the band is 1.8:1 at
    1024 and 2.4:1 at 1440, so a square product photo loses its top and bottom. A taller band is
    the fix if real catalogs read badly.
- **The count badge comes to wide tiles too.** On the phone, a tile already in the sale carries a mint
  count on its corner. Wide tiles never did, on the argument that the cart pane says it better.
  Beside a picture, the badge is the quickest *"I already rang that up"*.
  - **The mint edge does not come with it.** Drawn with pictures it outlined half the grid. The
    states board has it as a note.
- **The cost is about three tiles above the fold.** At 1024 × 768 the grid shows about 9 tiles where
  it showed about 12.

### 2. Search and categories share one row from 1024 up

To pay some of that back, the browse head is one row at `expanded` (1024 and up): a 320 search with
the category chips beside it. Chips that do not fit scroll under a 40-pixel fade at the right edge.
That returns about 40 pixels to the grid.

Between 768 and 1023 the products pane is 347–602 wide, which cannot hold a 320 field and the chips
side by side. There they stack, as they do today.

### 3. A cart line is the receipt row over its controls

| | Today | Proposed |
|---|---|---|
| One line | 152 (card, 3 rows, 8 gap) | **89** (2 rows, hairline) |
| Lines on screen at 1024 × 768 | 2.3 | **4.9** |

The card goes. Each line is now two rows on the pane's sunken ground, with a hairline between lines.

- **Top row, which reads like the printed receipt:** the name in `label.md` (14/600), the size in
  `caption`, and the line total right-aligned in `mono` money.
- **Second row, which is the hands on the line:** the same `QuantityStepper` (148 × 48), the unit price
  as *KES 65 each*, and the same 48 destructive bin at the end.
- **A 64 picture beside both rows.** It was 48. The pane has room for 64 now that the card padding is
  gone, and the line's own comment wants the picture: *"a cashier checking a cart against a counter
  reads pictures faster than names"*.
- **Nothing is dropped from today's line.** Today's single sentence, `1 x KES 65 = KES 65`, becomes
  the total at the top right and the unit price in the control row. The code comment that insists
  on the unit price (*"how much is one is the question a cashier is asked across a counter"*) is
  still answered.
- **Long names ellipsise on one line.** A large unit price wraps to two lines inside the 48 row.

The overstock sentence and the stepper's error sit under the controls, in today's words.

### 4. The foot is the phone's bar, plus what only the till has

| | Today | Proposed |
|---|---|---|
| Both adjustments offered, no payment method yet | 292 | **224** |
| Paid, nobody may adjust | 192 | **144** |

The 292 is measured on the anatomy board. The 192 is the same arithmetic, read off the capture's
geometry: the 48 chip bar, no hint and no adjustment row.

The order, top to bottom:

1. *Agree a price* · *Put on credit*, as halves, for whoever is allowed each. This is unchanged
   except for where the row sits; see the first ruling below.
2. **Paid by** with the Cash / M-Pesa / Card chips. Under them, only while no method is chosen, a
   one-line hint.
3. With a price agreed: listed price, agreed discount and reason, in the receipt's order.
4. **The total and *Save sale* on one row.** The total is on the left: its word over the figure, still
   `numeric.hero` 30 with the rolling digits. *Save sale* is on the right at half the pane (182),
   so its edge does not move as the figure grows. A figure past about ten characters scales down to
   fit rather than pushing the button.
5. The blocker caption, or the refusal callout, under that row as today.

This is the arrangement `_CartBar` already gives the phone, so a cashier who uses both sees one
grammar. Square ("Charge $X") and Loyverse ("CHARGE") make the same move. The figure the customer
is waiting for sits beside the control that commits it. That reference is from knowledge of those
products, not from a fresh look.

The head is 44, down from 47. "This sale" moves from `title.lg` to `title.md`, and the right end
gains the unit count, which is `_itemCount`, the figure the phone's badge already shows.

## Needs a ruling

These go against something already ruled or worded on purpose:

- **The adjustment row is no longer between the total and the save.** On 2026-10-02 you put
  *Agree a price* and *Put on credit* *"side by side … between the total and the save"*. Once the
  total and the save share a row, nothing can be between them, so the pair moves above the payment
  row.
  - **The alternative** is to keep today's order: total row, adjustments, payment, then a full-width
    save. That costs about 40 more pixels of foot.
- **Copy, three places:**
  - The hint under the payment row is shortened from *"No payment method yet. The sale records that
    it was not said, and you can set it later from the sale."* to *"Not said yet. You can set it
    later from the sale."* That drops the clause saying the sale records the method as not said.
  - **Paid by** is a new visible label. The chip bar was named only for screen readers ("How the
    customer paid").
  - With a price agreed, the total's word reads **Agreed total**.
- **Wide tiles trade density for recognition.** The ST-035 reasoning in `_ProductTile`'s doc comment
  is reversed, and that comment will need rewriting rather than deleting.

## What this cannot ship as

**All of it is composition.** No repository call, state, routing condition or API shape changes. The
count badge and the head's unit count read state the panel already holds. Three costs are still
worth knowing before anyone calls it a restyle:

- **The phone shares these widgets.** `_cartPane` builds both the wide pane (`stepped: true`) and the
  phone's sheet, and `_CartLine` and `_cartFoot` are the same widgets in both. Building this without
  touching the phone means the new line and foot have to be the wide branch only: a flag on the
  existing widgets, or wide-only siblings. Doing it by editing `_CartLine` in place would change the
  phone sheet.
- **The wide grid starts decoding pictures.** It decoded none. Up to `maximumRenderedCheckoutProducts`
  (60) photos now load on a till. `TenantProductVisual` sizes each decode to its box, but whether that
  is comfortable on the cheapest tablet in use is a device question, not a screenshot one.
- **The category bar needs one new option.** `FilterChipBar.scrollsInOneLine` is true only at
  `compact`. Wider than that it is a `Wrap`, which beside a 320 search would grow downward as a
  business adds categories. The one-row head needs the bar to scroll in one line there. That is a
  parameter on the component, and it does not change what the bar selects.
- **The skeleton and the tests follow.** `_CheckoutSkeleton` mirrors the tile geometry exactly, so it
  needs the band and the new height; the states board draws it. Tests that pin `_wideProductTileHeight`
  or the foot's order will need updating. That is churn, not behaviour.

## What the sample content is allowed to say

The first seven products are `tool/screenshots/fakes.dart`'s, at their prices and counts, including
Milk at −3 and Water at 0. The other nine are invented to fill a 1440 grid. The pictures are drawn
stand-ins, not anybody's photographs, and the build crops a real one to the band (see *What
changes*, section 1). Every sentence in the
states board is the app's own, quoted from `checkout_cart_panel.dart`, except the three copy changes
above.

## What these files are

Standalone HTML, colours quoted from `lib/ui/tokens.dart`'s `AppTokens.uzapay`.

- **Faces:** Roboto and JetBrains Mono. Every role that names no tracking carries Material's 0.25, so
  the boards measure like a build rather than reading about 3% narrower.
- **How they were made:** the four boards were generated from one script, so they draw identical
  components. They are edited as HTML from here.
- **What was checked:** each one was rendered in headless Chrome at its frame size and looked at, and
  the anatomy board's rulers are measured by the browser rather than typed.
- **What they cannot show:** they are drawings. They do not prove the app runs, they cannot show the
  rolling total or the press springs, and none of this has been on a device.
