# Top bar: designs, 2026-10-13

Open [`index.html`](index.html) for the five boards: anatomy, phone, tablet, desktop and states.
They use `AppTokens.uzapay` and Roboto, and every colour is quoted from `lib/ui/tokens.dart`.

**These are proposals.** Nothing in `lib/` changed.

## The question the bar answers

*Where am I, and is this device all right?* The bar says which business or screen this is and the
way back. It speaks up only when something is wrong with the device. Everything else belongs to
the page.

## Today

The app has two bars, and they don't match.

- **The home** draws `HubTopBar` (`lib/ui/hub_bar.dart`):
  - 70 tall on the raised surface, with a hairline under it, so the bar is a separate strip;
  - a status pill, a user pill, then the bell, the gear and sign out.
  - On a phone that is four trailing controls, and the avatar floats in the middle of the bar.
- **Every other screen** draws `AppScaffold`'s `AppBar` (`lib/ui/scaffold.dart`):
  - 56 tall, or 68 with a subtitle, on the page surface, with no edge.

## What the boards propose

1. **One surface rule for every bar.** At rest the bar is `surface.base`, the page's own surface,
   with no edge, and on a phone the status bar shares it. Once content scrolls under it, the bar
   steps up to `surface.raised` and gains a `borderSubtle` hairline over `motion.short`. There is
   no shadow, which is `spiritTheme`'s existing rule ("a surface step, never a drop shadow").
2. **Two heights.** 56 below 768 (68 for a two-line title on a phone, as today) and **64 from 768
   up**, with or without a subtitle. On wide screens the subtitle moves onto the title's line, in
   tertiary after a 12 gap. 64 is Material 3's small top app bar.
3. **The leading glyph sits on the page's own inset**, so the bar and the content share a left
   edge:
   - the home's mark sits on the cards' 32 margin;
   - an inner screen's back arrow sits on `AppScaffold.horizontalInset`, which is 20;
   - on a phone, the home's name and every back arrow sit at 16.

   The toolbar still spans the full window (the scaffold's recorded reason stands: a back arrow
   stays in the corner).
4. **The home bar drops to two trailing controls**: the existing send-queue bell, and the person.
   - Phone: a 28 initials circle.
   - 768 and up: the circle plus *Amina W.*
   - Either one opens an **account menu** with:
     - the person and their role;
     - this device's terminal code and whether it is online;
     - **Settings**, for the same roles the gear is drawn for today;
     - **Sign out**.
5. **Device state: quiet when it's normal, loud when it isn't.**
   - Online, from 768 up: plain tertiary text, *● Online · CT-7F2*, with no pill fill.
   - Online on a phone: nothing.
   - Offline, at every width: an amber chip with a word and a `cloud_off` glyph, so the state is
     never shown by colour alone.
   - Not yet known: the terminal code alone, with no dot.
6. **Controls:**
   - 48 circular targets with 24 glyphs, in `text.secondary`, rising to `text.primary` on hover
     and press;
   - washes at 0.08 and 0.12;
   - the mint focus ring on every control.
   - A page that already has a primary action in its bar draws it as a 40 filled button inside a
     48 target.
7. **The count badge is ink on red400** (about 6.5:1). The legacy white-on-red fails at 12px.

## Deliberate departures from the 2026-10-10 rulings

These reverse parts of the "old hub's bar" restoration. Rule on each one; none is assumed:

- **No raised strip.** At rest the home bar is on the page surface instead of a 70-high
  `raised` band with a hairline.
- **70 becomes 64**, and the home bar on a phone is the same 56 as every other phone bar.
- **No status pill and no user pill.** The status is plain text, and the person is a circle plus
  a first name and last initial. The role moves into the account menu, and the violet figure
  becomes neutral initials (`privileged` is the colour a privileged role wears, and on a
  cashier's bar it said otherwise).
- **The business name is white**, not sage: it is the bar's heading.
- **The hub mark appears only from 768 up.** On a 390 phone, removing it is what lets *Offline*
  fit beside *Dev Corner Shop* without cutting the name.
- **Gear and sign out move into the account menu** (see below).

**Unchanged:** the screen title at `titleLarge` 22 in the toolbar, the switcher behind the
business name and its chevron, the bell and what it counts, the terminal code, and the full-width
toolbar.

## What cannot ship as a pure restyle

Per CLAUDE.md rule 1, these change behaviour or state, not only looks:

1. **The account menu.** Folding the gear and sign out into a menu adds a menu (an open/closed
   state, focus management) and puts sign out one tap further away.
   - **If you'd rather not:** keep the gear and sign out as bare 48 icon actions after the person.
     That is a pure restyle. The bar gets busier on a phone (four controls, as today), but nothing
     moves.
2. **Lifting the home bar on scroll.** `AppBar` already does this through
   `scrolledUnderElevation` and the theme. `HubTopBar` is hand-drawn and would need to listen for
   the page's scroll notifications. That is small, but it is state in the bar.

Everything else is styling: the surface at rest, the heights, the insets, the inline subtitle,
the chip, the badge ink and the colours.

## Tokens

One new token, `topBarHeight` 64, which replaces `hubBarHeight` 70. Everything else already
exists. The [anatomy board](topbar-anatomy.html) maps each part to its token.

## Motion

- The scrolled-under lift is colour, not movement: `motion.short`, interrupted from its current
  value.
- The account menu is spatial. It scales from 0.96 at the button's corner on `spring.snappy`, with
  opacity on `motion.short`. A second press reverses it from its current position and velocity.

## Where the ideas came from

These are drawn from what the products ship, not from a fresh survey:

- **Linear and Vercel:** the bar is the page's surface and gets an edge only on scroll; the
  workspace name doubles as the switcher.
- **Shopify POS:** the signed-in staff member is one avatar at the trailing edge, and its menu
  holds sign out.
- **Square POS:** connection state appears only when the device is offline.
- **Material 3:** the small top app bar is 64 tall, and its scrolled-under state is a surface
  change.

## What the boards prove and what they don't

They are HTML at the stated widths and were rendered headless in Chrome. They don't prove the
Flutter build, they can't show motion, and they draw text without the 0.25 letter spacing the
runtime adds (see the M3 tracking note). Expect the built bar to set text about 3% wider.
