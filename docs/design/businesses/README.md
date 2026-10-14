# My businesses

## 2026-10-13: redrawn in the house style, and shared with *Choose a business*

The developer's brief: make *My businesses* "a high fidelity screen but also matching our design
style in other designs, it sticks out today". It stood out because it was the only white surface in
the app. A paper receipt in all-mono type on the green `AppTokens.uzapay` ground. Every other
screen (Books, the customer account, the home tiles) uses raised green cards, Roboto names, eyebrow
labels and one mono figure.

Boards: [`businesses-phone.html`](businesses-phone.html), [`businesses-wide.html`](businesses-wide.html),
[`businesses-states.html`](businesses-states.html), [`businesses-add.html`](businesses-add.html).
The receipt board is kept as [`businesses-receipt-2026-10-08.html`](businesses-receipt-2026-10-08.html).
The boards reuse Books' CSS and icon sprite (`docs/design/books/books-home.html`), so they share one
vocabulary with the rest of `docs/design/`.

### The card

The 2026-10-08 idea still holds: a business is shown through what is uniquely it, not as a name with
badges. Only the drawing changes.

- **Brand:** the uploaded logo (48, radius 8), or the store glyph on a field square. Never a
  coloured monogram. The name is `titleMedium`, and the slogan is `bodyMedium` in secondary text.
- **Status:** a glyph and a word under the name, so colour is never the only signal: *Open now ·
  you're in it*, *Invited*, *Suspended*, *Setting up*. The open business's edge takes the ok
  border. The tilted *OPEN NOW* stamp is gone.
- **A dashed rule** in the strong border is all that is left of the receipt.
- **One figure:** an eyebrow naming the day (*TODAY*, *LAST COUNTED · 7 OCT*), then a small
  currency code and the amount in mono. Today's is `numericHero` 30; another business's last
  counted day is `numericCompact` 22, so it never reads as live.
- **Facts:** up to three eyebrow-labelled values: Sales, Till, You.
- **Footer row:** what pressing does, in white with a chevron, as on the Books home rows. There is no
  green link text. The whole card is still the one press target.

### What changed besides the drawing

| Change | Kind |
| --- | --- |
| From 768 the cards sit in columns: 2 across, 3 from 1024, 20 apart. Page width `reading` (720) → `records` (1200). | Layout |
| The add sheet's masthead is the new business's card on the sunken surface, captioned *How it will show on this page.* It replaces the 2026-10-08 ruling "the receipt is the sheet's masthead". | Visual, reverses a ruling |
| Copy: *Open now · you're in it*; status words carry *can't be opened*; the edit detail reads *on its receipt*; dates print *7 Oct*. | Copy |
| *Switching…* shows a spinner in the footer. | Visual |

There are no new reads, routes or callables. The data, the order and the press targets are the
receipt's.

### *Choose a business* uses the same card

The developer asked on 2026-10-13 for the selector after sign-in to use this screen. It now draws each
membership as a `BusinessCard` in the same grid, under a header with the count and *Add business*:

- **What the selector already knows, and nothing more:** name, role (*You*) and standing. An open
  business shows *Open this business*. An invitation the person can accept shows *Accept
  invitation*, with the acceptance form under the card. Anything else shows its standing and has
  no action.
- ***Request business* is now *Add business*,** a secondary button in the list's header rather
  than a tertiary toolbar action. The toolbar keeps only *Sign out*, which fixes the title
  truncating to "Choos…" on a phone. With no memberships, the button stays in the toolbar,
  because the empty state has no header.
- **Standing words now match My businesses:** *Invited* (was *Pending*) and *Deactivated* (was
  *Inactive*). `tenantMembershipDisplayStatus` is still there for its other uses.
- **Open question:** no logo, slogan or figure is shown, because no business is open yet. Showing
  them would add the branding and `daily_metrics` reads My businesses makes, per business, before
  one is chosen. Not done without a ruling.

### Built, 2026-10-13

- `lib/tenancy/tenant_business_card.dart`: `BusinessCard` and its status, figure, fact and action
  types, `BusinessCardGrid`, and `businessCardStanding`. Every value comes from `AppTokens`.
- `tenant_businesses_screen.dart`: `BusinessReceipt`, the stamp and the torn-edge clipper are gone.
- `tenant_routing_shell.dart`: `TenantBusinessSelector` draws its list with the card.
- Tests moved with the copy. Two test changes, both explained in the tests themselves: the switching
  test pumps frames instead of settling, because the spinner never settles when nothing pops the page.
  The invitation test scrolls the confirm button into view, because the card is taller than the old
  `ListTile`.
- Harness: `my-businesses`, `my-businesses-one`, `my-businesses-add`, and `02-choose-business`
  (mobile and web).

**What the screenshots prove and what they don't.** They show the widget tree drawn at those sizes.
They don't prove the app runs, don't show the spinner or the press states moving, and don't cover
the 768/1024 column switch for My businesses. That page has phone captures only, while the selector's
web capture shows 3 across. **Not run on a device.**

---

# My businesses — a design, 2026-10-08

A page that lists every business on the account, each drawn as the receipt it prints, with *Add
business* at the top. It opens from the home tile (renamed from *Business details* to *My
businesses*) and from the business name in the top bar. Open [`index.html`](index.html) in a
browser. Each page is self-contained HTML with no build step.

**This is a proposal, not a record.** No widget, test or token was changed to make it.

## The question the screen is opened with

*Which of my shops is this, and how do I start another?* Today an owner with one business can't
add a second from inside the app. The form exists (`TenantRequestForm`), but its only host inside
the app is the *Choose a business* selector. That screen never shows when there is exactly one
business, or when one was opened last or set as the default.

## The idea: a business is drawn as its receipt

The first draft used a generic card (monogram, name, coloured badges, a link row). It was rejected
on 2026-10-08. Cards here are about the feature they stand for, and the thing that is uniquely a
business in this app is the receipt it prints:

- **Header, from `TenantBranding`:** logo, brand name, slogan. These are the same fields the
  Business details page edits, so the receipt previews exactly what that page changes.
- **A dashed printed rule**, then the business's own lines in mono: takings, sales, the till, and
  your role there.
- **Status as a stamp, in a word:** `OPEN NOW` on the business you're in, the way a receipt is
  stamped *PAID*. Colour never carries it alone.
- **The receipt's footer says what tapping does:** *Edit details* on the open business,
  *Switch to this shop* on any other.

The references were wallet and multi-account banking shots on Dribbble (Toni Adegbenro's *Wallet
Management*, Alex Arutyunov's *Wallet Card Stack*, the *multiple accounts banking app* search). Two
things carried over: each account is its own rich artefact showing its own figure, and the add
action sits in the header of the collection it adds to, not in a footer.

## Rulings, 2026-10-08

| Question | Ruling |
| --- | --- |
| Tile and page name | **My businesses**. *Business details* stays as the name of the page behind the open receipt. |
| Currency the add sheet starts on | **The open business's.** A small behaviour change to the shared `TenantRequestForm` default; onboarding keeps `TZS` since there is no open business. |
| Top-bar business name | **Opens My businesses**, and is tappable with one business too. The *Change business* dialog retires. |
| Till line | **Names who's open:** *Open · Amina*, *2 tills open*, or *Closed*. |
| Add sheet layout | **The receipt is the sheet's masthead**, as the photo is on the product sheet (`AppSheet` masthead mode): edge to edge under the rounded corners, handle and close laid over it, no heading. Its torn edge is the masthead's bottom. It isn't square: it's as tall as the receipt. |
| Other businesses' figures | **Fetched.** The reads are small (below). A name-and-role-only version was drawn and then dropped the same day. |

## What each line says, and where it comes from

| Line | Open business | Any other business | Source |
| --- | --- | --- | --- |
| Logo, name, slogan | yes | yes | `configuration/branding`; rules allow any active staff |
| Takings | **today**, live | **last counted day**, its date printed | open: the home's *Today's sales*; other: latest `daily_metrics` (owner/admin/manager only) |
| Sales | today | last counted day | same |
| Currency on the figure | in hand | `configuration/checkout` | `daily_metrics` has no currency |
| Till | who has it open | not shown | today's shifts (already loaded by the home) + staff names |
| You | role | role | `TenantMembership.role` |

- **No business shows today's live figure unless it's the open one.** Live totals run per open
  session. Running them for every business would be a standing cost, not a page-open cost.
- **A cashier in another business gets no takings line there**, because the rules refuse them
  `daily_metrics`. Their receipt is header + role.
- **Offline, a business never opened on this device has nothing cached.** Its receipt falls back
  to name (from the membership) + role, with the figure lines left off rather than zeroed.
- **A day with nothing counted yet prints `—`**, as the home does, never `KES 0`.

## Reads it adds, per page open

| Read | Count |
| --- | --- |
| `branding` per other business | 1 each |
| Latest `daily_metrics` per other business (limit-1 query) | 1 each, even when empty |
| `checkout` per other business | 1 each |
| Staff names for the till line | about 1 per person with a till open, 0 when cached |

That's about 4 for the board's example and about 73 at the 25-business cap. Only owners and admins
reach the page, and they open it occasionally. Firestore's cache makes repeat visits cheaper.

## What this cannot ship as

**Not a restyle.** It changes routing, adds reads, and adds a write path from inside a session:

1. **Routing.** The tile and the top-bar name open *My businesses*. The open business's receipt
   opens today's Business details page, whose back button returns here. The top bar's
   "only when there's another business" condition (`_canSwitchBusiness`) goes away.
2. **Adding a business from inside a session.** `TenantRequestForm` and `requestTenantCallable`
   have to reach the home's composition. On success the bootstrap refreshes, so the new
   membership becomes a switch candidate without a sign-out.
3. **Reading another business.** Every repository builds its paths from the open session's
   business, so the three reads above need a way to target a business that isn't open, still
   within the rules.
4. **The till line** keeps today's shift list, not just its count, and resolves staff names.
5. **Switching from a receipt** reuses `onSwitchTenant` and its blockers unchanged.

The selector's stale copy is fixed as part of this, wherever the form is hosted. It says *"New
businesses remain pending until platform review"* and *"…was submitted for review"*, but the
server creates the business `active`.

## Not yet drawn

A states board: a suspended business (void stamp), a pending invitation, a day with nothing
counted (`—`), a cashier's receipt, an offline receipt with no cache, loading lines, press and focus
rings on a slip, a switch refused by a blocker, a refusal in the add sheet, and the list after a
business is added.

## Built, 2026-10-08

Built in `lib/tenancy/tenant_businesses_screen.dart`, wired from the home in
`tenant_routing_shell.dart`. Harness captures: `my-businesses`, `my-businesses-one`,
`my-businesses-add` (`tool/screenshots/businesses_screens_test.dart`). Tests:
`test/tenancy/tenant_businesses_screen_test.dart`.

**What the build draws differently from the boards:**
- The receipt's bold is JetBrains Mono at 500, not 800. The face is bundled at 400 and 500 only.
- Sizes snap to the type roles: the name is `numericBody` (14), the masthead name and the total are
  `numericCompact` (22), and the lines are `monoCaption` (12).
- *OPEN NOW* is printed in ink inside a paper-green box with a green tick. Paper green on white is
  3.1:1, which is enough for the box and the tick but not for 12-point text.
- The stamp's border is the default 1px, not 2.
- Without a logo, the name sits one `s24` lower so a long name can't run into the stamp.
- Figures use the app's own money format: *KES 12400*, ungrouped, as on the home's tiles.
- Below `AppSheetDetent.half` the masthead receipt shrinks to fit rather than clipping.

**Decided while building (ordinary calls, not rulings):**
- **The open receipt's figures come from the home**, through `_TodayFigures`, which `_figures` now
  uses too. The receipt and the tiles can't disagree.
- **Another business's figure is yesterday's `daily_metrics`**, read with `readDay`: one document,
  not `loadRecentDays`, which also reads the intake record.
- **After an add, the shell refreshes memberships in the background** (`_startBootstrapRefresh`),
  not with `_retry`, which would close the open business. Until the refresh lands, the new
  business shows on the list as *Setting up*.
- **A member who can't open My businesses** (anyone outside Business details' owner/admin roles)
  keeps the old *Change business* dialog on the top-bar name.
- **The form gained `initialCurrency`, `onDraftChanged` and `expandActions`.** The stale copy is
  fixed at its source: *"A new business opens ready to trade."* and *"… was added."*

**Same day, at the developer's direction:** signup defaults to Kenya. `defaultDialCode` is +254 and
Kenya is first in `dialCodes`; KES is first in `tenantRequestCurrencies`.

**Not run on a device.**
