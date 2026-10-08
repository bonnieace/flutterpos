# Product form — a design, 2026-10-08

Three artboards for the two screens Inventory opens to add a product and to edit one,
`_AddProductScreen` and `_EditProductScreen` in `lib/inventory/catalog_management_panel.dart`.
Open [`index.html`](index.html) in a browser. Each page is self-contained HTML with no build step
and no dependency on the repo.

The brief: make the two screens friendlier and less intimidating, and stop the image taking up the
screen. They were drawn against the harness captures `18h-add-a-product` (added to
`tool/screenshots/operations_screens_test.dart` for this, as the add form had no capture) and
`19-correct-a-product` to `19f-cut-out-refused`.

## Built, 2026-10-08

Every proposal in the table below is built in `catalog_management_panel.dart`. The developer
approved the boards and settled all five open questions as drawn, with one change to the photo
sheet: the photo fills the top of the sheet, edge to edge under the sheet's own rounded corners,
with no *Photo* heading and no padding. That is `AppSheet`'s existing masthead mode, with one new
option, `mastheadSquare`: the photo is as tall as the sheet is wide, up to two thirds of the sheet.

**The code field became a size the same day.** Nothing read the code: there was no scan-to-add and
nothing made it unique, and every shop already used it for sizes (*30ml*). So the field is now
*Size or volume (optional)*, e.g. *30ml*, in the slot the boards drew *Code*. The app and the
server both accept a blank size and sizes with spaces. Every list that names a product shows
*name · size*. The stored key is still `SKU`. A future barcode scanner needs a field of its own.

**Corrected on the boards to what the build draws:**
- The empty tile has the field's solid edge; nothing in the app draws a dashed one.
- `(optional)` is part of the field label, in the label's own ink.
- Helper lines sit 8 under the field: the focus-ring gutter, then `s4`.
- *Keep the saved photo* is `AppButton` tertiary at `sm`, 20 in from its edge.
- The zoom badge on the tile is 24 on the scrim.
- *How editing works* is the app's `Disclosure`, with its glyph.
- The sheet's close control is drawn, because every `AppSheet` carries one.

**Changed again the same day, at the developer's direction:** *Remove it* and *Keep it* are gone.
Deleting the buying price from its field removes it, and the field's helper says *Removed when
you save.* The stock note moved into the disclosure, renamed *How editing works*, whose four
paragraphs became four short sentences.

**Not yet:** run on a phone, or on SIT.

## The question the screen is opened with

**What do I type to get this product onto the till, and is it right?** Somebody adds a product
when a new line arrives on the shelf, usually with the item in one hand and the phone in the other.
Somebody edits one because a price changed or a name was wrong. Either way the job is a handful of
short fields. The screen should look like a handful of short fields.

## What is wrong today, measured

On the 411 × 891 phone (`mobile-full` captures, 2×):

- **The photo comes first and is huge.** The image well is a 371 × 350 box, with a row of buttons
  under it. With no photo it is still 350 tall and says *No image*. The first field, *Product
  name*, starts at 516, past the middle of the screen. Every form field is below the fold, and
  editing the price means scrolling past a picture you didn't come to change.
- **Three of the four photo buttons are bare icons**: a pencil (it means *Position and zoom*), a
  wand (*Remove background*) and a bin. The pencil reads as "edit the product". When the wand is
  disabled, nothing says why.
- **The two forms don't match.** One is called *Add product*, the other *Edit item*. Add picks a
  category from a dropdown, edit from chips under a 22px *Category* heading that is bigger than
  everything else on the form. The fields come in a different order.
- **The edit form opens with a lecture.** *How this is checked* sits above the first field. Its
  four paragraphs are folded away, but it is still the first thing you read.
- **The button lies.** *Review correction* saves straight away; there is no review step after it.
- **A checkbox for a removal.** *Remove the recorded buying price* is a full-width checkbox row
  under the buying price, worded in a way people have to read twice.
- **The add form's button goes grey without saying why.** It is waiting for the name, the code, the
  price and the category, and nothing tells you which one is missing.

## What the boards propose

| Part | Built | Proposed | Restyle? |
| --- | --- | --- | --- |
| The photo | 371 × 350 well above the form, four buttons under it, three icon-only | **A 128 tile beside a short label and a *Replace* button**, with ⋯ for the rest. The name field moves up from 516 to 232 | Yes. Same callbacks: choose, frame, cut out, remove. Needs one token, `layout.productImageThumb = 128` |
| Seeing the photo large | Always, at 350 | **In a sheet**: tapping the tile or ⋯ opens it, with the picture at full size and the actions named: *Position and zoom*, *Remove background*, *Remove photo* | Presentation only, but the interaction moves from inline to a modal. **Your call** |
| Cut-out progress and refusals | Spinner on the wand; callouts under the well | The same states and the same `backgroundRemovalMessage` sentences, in the sheet, on the row that started them | Yes |
| Remove background on a saved photo | Greyed-out wand, no reason | Disabled row with *Choose a new photo first. A saved photo cannot be cut out.* | Yes, new copy |
| A saved photo marked for removal | A grey line under the well | The tile goes back to *Add photo*, an amber *Removed when you save* line, and **Keep the saved photo** | Mostly. *Keep the saved photo* clears the form's own `_removeImage` flag. That is form-local state and nothing is sent, but it is a new way to reach a state. **Your call** |
| Field order | Add: name, SKU, price, cost, stock, category. Edit: name, SKU, price, cost, category | **Both: name, category, selling + buying price side by side, code, then stock (add only)** | Yes |
| Category in edit | Chips under a 22px heading | **The add form's dropdown**, without *Add new category*. The two notes about unlisted categories go in its helper slot, worded as now | Yes. The same `_categoryId` |
| Removing a buying price | Checkbox row | ***Remove it*** under the field. Once tapped, the field shows the old price struck through, an amber *Removed when you save* line and ***Keep it*** | Yes. The same `_clearCost` flag |
| *How this is checked* | First thing on the edit form | Last thing on it, unchanged inside | Yes |
| Manager editing | A callout saying the two price fields are hidden | **The selling price shown locked**, with *Only an owner or administrator can change prices.* The buying price is still not shown | Yes. `product.price` is already held. **Your call:** whether to show it |
| Edit form note | None | *Stock is not changed here. Use Adjust stock on the product.* | Yes, new copy |
| Add button disabled | Grey, no reason | *Add a name, category, selling price and code to save it.* under the actions while it is disabled | Yes. Driven by the same `_canSubmit` |
| Field glyphs | #, cash, cash, box on four fields | None | Yes |
| Wider screens (≥ 768) | Photo column beside the fields, 2:3, picture up to 350 | One 720 column with the same photo row on top; name and category share a line, prices and code share one | Yes. `_FormWithImageWell` stops branching |

**Copy changes**, all display only:

| Built | Proposed |
| --- | --- |
| *Edit item* | *Edit product* |
| *Review correction* | *Save changes* |
| *SKU*, placeholder *e.g. 30ml* | *Code*, placeholder *Barcode or short code*, helper *The till finds the product by this when it is scanned or typed.* **Your call**: *e.g. 30ml* may have been chosen on purpose |
| *Opening stock (optional)* | *Stock on hand (optional)*, helper *How many you have now. Leave it blank if you have none yet.* |
| *Choose image* / *Replace image* | *Choose photo* / *Replace* |
| *Remove the recorded buying price* | *Remove it* / *Keep it* |
| *No image* | *Add photo* |

## Why 128, and not 64 or 350

The 350 well is the 2026-08-25 reversal. Before that the Stitch pass had shrunk the photo to a
64px thumbnail, and `tokens.dart` records why that was undone: *a thumbnail that small is a size at
which a right photo and a wrong one look the same.* That still holds, so the proposal doesn't go
back to 64.

128 is twice that and large enough to tell a loaf from a tray of mandazi. Close inspection, which
is what the 350 was really for, now happens in the sheet. There the picture is drawn at the lesser
of `productImagePreview` (350) and what the sheet leaves after its three rows. The board draws 280,
which is what fits at the half detent on a phone.

## Not proposed

- **Showing a refused price under its field.** Today an unusable price is answered in the snack bar
  after *Add product*. Answering in place means the form running the repository's validation as
  you type, which is a logic change. The states board draws it only to show it was considered.
- **A currency prefix in the price fields** (*KES 65*). Neither form knows the business's currency.
  It is read from `configuration/checkout` elsewhere, so this would mean a new read or a new prop.
- **Splitting the form into steps or *More details*.** With the photo shrunk, the whole add form
  fits on one phone screen, and hiding the optional fields would hide *Buying price*, which owners
  want filled in.
- **Changing the opening-stock, cost-role or category rules.** Who may record a cost, what a
  correction sends, and the server checks are all unchanged.

## What the build would change besides layout

- **Test keys.** Most keys stay. These move or change type:
  - `catalog-management-edit-clear-cost`: a checkbox now, a text button then.
  - `catalog-management-edit-category-*`: chips now, dropdown items then.
  - `inventory-frame-image`, `inventory-remove-background` and `inventory-remove-image`: these
    move into the sheet.
  - `catalog-management-edit-money-hidden`: replaced by the locked field.

  Tests that tap them need updating.
- **Harness captures `18h` and `19`–`19f`** will draw the new layout, and the cut-out cases need to
  open the sheet first.
- **One token**, `layout.productImageThumb`.

## Your calls - all settled as drawn, 2026-10-08

1. **The photo sheet**, or the three actions as labelled buttons inline under the tile. Inline is
   one tap shorter but brings back a row of buttons, which is half of what looks busy today.
2. **The manager's locked selling price**, or keep today's callout.
3. ***Code* and its placeholder**, or keep *SKU* / *e.g. 30ml*.
4. **Dropdown for the category in edit.** Chips are one tap when a shop has three categories, and
   a scrolling row of forty when it has forty. The dropdown matches the add form.
5. ***Keep the saved photo*** after removing it, or leave removal as it is (choose a new photo to
   undo).

## The sample content

The edit boards use the harness's seeded product, *White bread loaf*, code `6161100000019`, 65 to
sell, 48 to buy, in *Bakery*, with the harness's own bread picture. The add boards use *Mandazi*
(code `M-1`, 20, 12, 24 in stock), the product the catalog widget tests add.

## What these files are

Standalone HTML pages written by hand, with no build step. Every colour, size and radius is the
token the build reads (Profound Verdant), except the new 128. Every sentence not marked *new* is
the app's own.

They are drawings, and so are the captures they were checked against. The harness rasterises the
widget tree, so neither proves the app runs on a device, and neither can show motion: the sheet
rising, the tile's press, the cut-out landing. The phone boards are 411, the harness's `mobile`
viewport. Text in the build renders about 3% wider than in Chrome (Material's letter spacing).
