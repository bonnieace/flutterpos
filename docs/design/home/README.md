# Home screen — a design, 2026-09-20

Four artboards for the landing route, `_TenantHome` in
[`tenant_routing_shell.dart`](../../../lib/tenancy/tenant_routing_shell.dart). Open
[`index.html`](index.html) in a browser; each page is self-contained HTML with no build step and
no dependency on the repo.

**This is a proposal, not a record.** It is not a decision, it does not describe what to build
next, and nothing in it should be quoted back as a constraint. It draws pixels only — no widget,
test or token was changed to make it.

## The brief

Keep the phone tile grid. Make the rest of the screen feel natural around it, and fit the design
inspiration — the pre-multitenancy hub in [`main_hub_screen.dart`](../../../lib/screens/main_hub_screen.dart),
which `CLAUDE.md` names as the reference and which recent work has been rebuilding on.

## The grid is untouched

Four across, a 56 glyph well tinted to 14% with a 38% border, the badge on the corner of the well
rather than inside it, the label under it, one word never broken. Nothing in this design changes a
tile's size, shape, spacing, glyph or behaviour, and the order is the order `HomeNavigation._ordered`
already produces.

Two things *around* the tiles change how the grid reads, and both are drift from the inspiration
rather than new ideas:

**Colour belongs to the module, not to the position.** The accent is
`accent.identity[position % 6]` — a hue chosen by where a tile falls in the list. The destinations
are role-gated, so a manager who cannot see *Returns* gets every tile after it shifted one hue:
*Inventory* is orange for one person and purple for another, on the same build, for no reason
either of them can see. The inspiration pins a colour to a module — Register blue, Book Keeping
teal, Returns orange, Inventory purple, Staff pink, Reports green — and those are the same six
hues `accent.identity` already holds.

So the hue is keyed on the destination rather than on its index in the filtered list. The six the
inspiration names keep the hue it gave them; the seven it never had take one by family — stock
purple (Inventory, Stock counts, Count stock), money-out orange (Expenses), insight green (Shift
history), tools blue (Settings, Printer, Logs). Which family a newer module belongs to is a
product call; the point of the change is only that it stops moving when the role does.

**The last row is short, and that is fine.** An owner can reach up to thirteen destinations and
four columns will not divide them. The design does not stretch, centre or pad the final row; it
lets it be short and puts nothing in the space beside it, which is what a launcher does.

## What the rest of the screen does instead

### 1. The greeting stops saying what the title bar just said

`_LandingGreeting` falls back to the business name when no member name is known
(`subject = who == null || who.isEmpty ? businessName : who`), and `AppScaffold.title` is already
`branding?.companyName ?? membership.tenantName`. A session with no member name therefore prints
the shop's name twice, about a hundred pixels apart, at 32 and at 22 — and *Good evening, Dev
Corner Shop* is not a thing anybody says to their own shop.

With a name: *Good evening, Amina*. Without one: *Good evening.* — the salutation alone. The
trend line and *Select a module to begin.* are unchanged, and so is the centred funnel.

### 2. The figures band comes back to four tiles

The inspiration's `_StatsBar` is exactly four tiles in one bordered panel: a 2×2 grid on a phone,
one row with hairline dividers above 768. The rebuild has five — Today's sales, Transactions,
Shifts, Gross profit, Net profit — so a phone gets two, two, then a single orphan tile with a
hole beside it, directly under a grid whose own last row is short. Two ragged rows on one screen
is most of what reads as unnatural.

It is also a figure printed twice. Net profit is gross profit minus expenses, so on any day with
no expenses recorded the two tiles carry the identical number — `KES 274.00` in both, in the
capture this design was drawn against.

**One profit tile**: net where expenses are known, gross where they are not. Which one it is goes
in the detail line the tile already carries — *After cost of goods* against *After cost of goods
and expenses* — so nothing is hidden and nothing is said twice. Four tiles, 2×2, no orphan.

### 3. The setup card gets the home it was written for

[`TenantSetupChecklistCard`](../../../lib/tenancy/tenant_setup_checklist.dart) is built,
role-gated, covered by `rbac_matrix_test.dart` and `tenant_setup_checklist_test.dart` — and no
screen in `lib/` builds it. Its own header says what it is for: *"What a newly approved business
still has to do before it can sell … Nothing on the home said so."*

It goes above the grid, for a business that has published no currency or has nothing in its
catalog, and is absent for everybody else — which is almost always. It costs no Firestore read:
both facts are already in the encrypted catalog cache the till writes on every session open.

### 4. The rhythm is the inspiration's

The old hub spaced its body 24 / greeting / 40 / grid / 36 / stats. The rebuild uses 32 / 32.
This takes `space.40` above the grid and `space.32` below it — 40 and 36 were the inspiration's
numbers and `space.36` does not exist, so the design uses the scale rather than inventing a token.

## What this cannot ship as

Three of the four moves are pure composition and change no behaviour: the greeting fallback, the
spacing, and the module colours. **The other two are not restyles.**

- **The single profit tile** decides which figure to draw from whether `overview.expenses` is
  known. The data is already loaded and already drives `TenantNetProfitReport.from`, so nothing
  new is read — but one tile disappearing is a change to what the screen states, and that is the
  product owner's call rather than a visual one.
- **The setup card** builds a widget the home does not build today. It reads only the Hive cache,
  so it costs no query, but it is a new element on the landing route and it is gated on roles
  (`TenantSetupChecklist.allowedRoles`, owner and admin) that the home does not currently consult.

Hard rule 1 is why these are listed here rather than mentioned at the end.

## The capture this was drawn against is stale, and the harness does not compile

`screenshots/mobile-full/10-business-home-owner.png` is from 13 September and still shows a *Make
default* tile in the grid. That tile was removed on 2026-09-16 — the account controls moved to the
business name in the top bar — so the orphan tile it shows is already fixed and is **not** part of
this design.

Regenerating it fails: `flutter test tool/screenshots/landing_screens_test.dart` does not compile
against current `lib/`, on three signatures that have moved since it was written —
`TenantNotificationsScreen` now requires `tenantId`, `alsoWaiting` is now `int Function(String)`,
and `settingsRoute` now takes `(reader, initialTabKey)`. Everything in this design is therefore
read off the code rather than off a picture, and the harness wants repairing before anything here
is checked against a render.

## What the sample content is allowed to say

Every figure comes from a field the overview already holds: `metrics.sales`,
`metrics.transactions`, `metrics.shiftCount`, `report.profit`, `TenantNetProfitReport`, and the
device cache's `unsentTransactions`. The em dash, *Not reconciled*, *On this device* and *n not
sent* are the tiles' own existing words, not new ones.

## What these files are

Standalone HTML pages, hand-authored, no build step. Colours, radii and heights are quoted from
`lib/ui/tokens.dart`. They are drawings: they do not prove the app runs, they cannot show motion,
and the grid's press springs are not represented at all.
