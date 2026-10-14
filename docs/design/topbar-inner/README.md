# Inner top bar: designs, 2026-10-13

Open [`index.html`](index.html) for the four boards: anatomy, phone, tablet and desktop, and states.
They use `AppTokens.uzapay` and Roboto, and every colour is quoted from `lib/ui/tokens.dart`.
[`../topbar/`](../topbar/README.md) is the home's bar. This folder is the bar on every other
screen.

## Built, 2026-10-13 (uncommitted, no device run)

The developer asked for it to be built, and that settled the four rulings below in the boards'
favour. The boards have been corrected to what the build draws.

- **Module well:** `TopBarModuleWell` (`lib/ui/top_bar.dart`), drawn by `AppScaffold` from 768
  up.
  - The module is a tag on the route. `HomeDestination.open` pushes inside
    `AppPageRoute.openingModule`, and a route pushed over a tagged one takes its tag in
    `didChangePrevious`.
  - No call site names a module.
  - A screen reached any other way draws no well: the account menu's Settings, a banner, a
    `MaterialPageRoute`.
- **Offline:** `DeviceOnlineScope` sits in `MaterialApp.builder` (`lib/main.dart`) and reads the
  same connectivity as the home bar. `AppScaffold` draws `TopBarOfflineBadge` only when the
  reading is *offline*.
  - It is the home's `StatusBadge`, not the pill the first boards drew.
  - From 1024 up it reads *Offline · sales save on this device*.
- **Report:** `TenantReportAction` is a secondary `md` `AppButton` named *Report* from 1024 up.
  Below that it is the mint glyph it was. Same press, same busy state.
  - Its edge lands 12 from the window, not 20, because the button reserves a 4 focus-ring
    gutter on the 8 the bar leaves for a glyph. That is a known delta.
- **Taglines:** removed at 13 call sites, along with *Customer* and *Supplier* under a record's
  name.
  - Kept: every scope, the expense category's period, and two task instructions (*Write down
    what is on the shelf.* and the photo-framing line).
- **No primary in any inner bar.** *Receive delivery* was always in the Suppliers page body. The
  first boards put it in the bar by mistake.

Tests: 7 new cases in `test/ui/scaffold_test.dart`, plus harness cases `94-page-frame-inner-bar`
and `94-page-frame-inner-bar-offline`. The connectivity wiring and the tag on a real home press
have not been run on a device.

## The question the bar answers

*Where am I, how do I get back, and is this device all right?* The page answers everything else.

## Today

`AppScaffold._toolbar` (`lib/ui/scaffold.dart`) draws one of these on each of about 60 routes. It
already has the 2026-10-13 surface rule (`TopBarSurface`), the 64 height from 768 up and the
inset back arrow. What it carries:

- **A back arrow and a title.**
- **A subtitle on about 20 routes, which is two different things:**
  - **a scope**, which is useful: *Thursday 14 October*, a receipt number, a shift, a run id;
  - **a tagline**, which is not: *Who buys from you.*, *Manage your team, their roles and
    access.*, *What the business spent, beyond the cost of its stock.* A person reads it once,
    and on a phone it costs 12 of height on every visit.
- **One action, and it is nearly always *Report*.** `TenantSessionReportAction` appears on Staff,
  Sales report, Returns, Shift history, Logs, Stock counts, Inventory, Expenses, Production and
  Suppliers. It is a bare `summarize` glyph at every width, so on a 1440 desktop the bar's only
  control is an unlabelled icon 1,300 pixels from the title.
- **One primary:** *Receive delivery* on Suppliers and on a supplier's record.
- **Nothing about the device.** The home has said *Offline* since 2026-10-13. Leaving the home
  stops that, so the Register, the screen where a dropped network matters most, is silent.

## What the boards propose

1. **A module well, from 768 up.** Between the back arrow and the title sits the home card's own
   glyph, filled, in its identity colour (18 in a 32 well of black at 0.4, `radius.md`). That is
   the teal bar chart for Sales, the purple box for Inventory, the orange lorry for Suppliers.
   - It connects the screen to the card the person tapped, in the legacy home's visual language.
   - It answers "which part of the app is this" without a breadcrumb. The two *Stock counts*
     screens and the three *Settings* screens are told apart by their wells.
   - It is decorative and excluded from semantics, because the title already says where you are.
     It is never a control.
   - **Not on a phone:** the 44 it would cost belongs to the title.
2. **Scope stays in the bar; taglines leave it.**
   - From 768 up, the scope sits on the title's line, in tertiary (already built).
   - On a phone it is the second line, and the bar is 68 (as today).
   - A tagline is dropped from the bar. That makes the phone bar 56 on Staff, Customers,
     Suppliers, Expenses, Production, Returns, Inventory, Categories and the stock-count screens.
   - A record's type label is dropped as well, because the well now says it: *Customer* under
     *Mary Achieng*, *Supplier* under *Bidco Africa*.
3. **Device state: offline only.** Inner screens show nothing while the device is online. Offline
   draws the home's amber chip (`cloud_off` glyph and the word, `role=status`) at the trailing
   edge, before the page's actions. From 1024 up it adds *· sales save on this device*. Online
   shows nothing, because the home carries the terminal code.
4. **Page actions say their names from 1024 up.**
   - At 1024 and up, *Report* is an outlined 40 button with a glyph and a label, inside a 48
     target.
   - Below 1024 it stays a 48 glyph target with a tooltip.
   - Its loading state, which already exists, gets a look: a spinner, and the label *Making
     report*.
5. **The primary is the mint filled button, last.** On a phone it becomes a 40 glyph square,
   named *Receive delivery* to a screen reader, so *Suppliers* is not truncated.
6. **Order, leading to trailing:** back, well, title, scope, space, device state, quiet actions,
   primary. Width runs out in this order: first the space between, then the scope ellipsises,
   then the title. The chip and the actions never shrink.

## Rulings needed

None of these is assumed:

- **The well.** It is a new element on every inner screen. The alternative is a text crumb
  (*Inventory › Stock counts*). I didn't draw a crumb, because a crumb looks like a set of links,
  and making it a set of links is routing.
- **Taglines out of the bar.** This is a copy decision. They could move into empty states, where
  a first-time owner meets them, or be deleted. The boards drop them and show nothing in their
  place.
- **Offline on inner screens.** The home's rule was "the bar speaks up only when something is
  wrong". This extends it to every route.
- **Labelled actions from 1024 up.** This adds one button style to the bar: outlined, 40, with
  the `border.strong` edge.

## Deliberately not changed

- The back arrow and `AppBar`'s decision about whether to draw one.
- `titleLarge` 22 for the title, in the toolbar.
- The surface at rest and the lift on scroll (`TopBarSurface`).
- 56/68 on a phone and 64 from 768 up.
- The insets: 20 wide, 16 on a phone.
- The full-width toolbar.
- What *Report* does.
- The platform console's routes and the shell's sign-in screens (*Choose a business*, *Business
  invitation*). They have no back arrow and no module, so they get the title and their existing
  actions with no well.

## What cannot ship as a pure restyle

Per CLAUDE.md rule 1:

1. **The offline chip on inner screens.** `AppScaffold` would need the connectivity reading that
   `HubTopBar` takes (`onlineCheck`/`onlineChanges`), either wired into every route or read from
   an ancestor. That is state in the frame. It is small, but it is not styling.
2. **The well needs a new `AppScaffold` field** (`module`, or the `HomeDestination` it came from)
   at about 60 call sites. That is data, not behaviour, but it touches every route file.
3. **Dropping taglines** is `subtitle: null` at about 12 call sites. Some widget tests may assert
   the old text.

Everything else is styling: the labelled report button, the glyph-only primary on a phone, the
chip's look, the spinner and the order of the parts.

## Tokens

One new token: `icons.barWell` 32. Everything else already exists:

| Part | Tokens |
|---|---|
| Well | `radius.md`, `cardWellWashOpacity`, `icons.row` 18, `accent.identity` |
| Chip | `amber400`, `amberTint10`, `amberTint30` |
| Labelled action | `border.strong`, `labelLarge` |
| Title | `titleLarge` |
| Scope | `bodyMedium`, `text.tertiary` / `text.secondary` |

The [anatomy board](topbar-inner-anatomy.html) maps each part to its token.

## Motion

- **The offline chip** fades in over `motion.short`. Its space is reserved by width only once it
  is drawn, and the actions after it don't move because it comes before them.
- **The scroll lift** is colour, already built, and interruptible.
- **Report's spinner** replaces the glyph in place. The target never changes size.

## Where the ideas came from

These are products I know, not a fresh survey:

- **Shopify admin:** the page bar has a back arrow, the title and its badge, and labelled
  secondary actions with one filled primary at the right.
- **Linear:** the team's icon sits before the page name and stands in for a breadcrumb.
- **Square POS:** connection state appears only when the device is offline, on the screen you
  are on.
- **Material 3:** the small top app bar is 64, scrolled-under is a surface change, and an action
  has a label once there is room.

## What the boards prove and what they don't

They are HTML at the stated widths, rendered headless in Chrome and checked by eye. They don't
prove the Flutter build, they can't show the chip's fade, and they draw text without the 0.25
letter spacing the runtime adds, so expect the built bar about 3% wider. Sample data matches the
other boards (Dev Corner Shop, Amina Wanjiru, CT-7F2).
