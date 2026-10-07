# Platform console — a design, 2026-10-06

Five boards for what a platform administrator sees after signing in: today
`PlatformTenantManagementScreen` in
[`platform_tenant_lifecycle.dart`](../../../lib/tenancy/platform_tenant_lifecycle.dart). Open
[`index.html`](index.html) in a browser; each page is self-contained HTML with no build step and
no dependency on the repo.

**This is a proposal, not a record.** It is not a decision, it does not describe what to build
next, and nothing in it should be quoted back as a constraint. It draws pixels only — no widget,
test, rule or token was changed to make it.

## The question the screen is opened with

*Is anything on the platform broken that only I can fix?* After that comes *who is this
business?* or *who is this person?*, usually because an alert email or an owner's phone call
named them.

The console as built answers neither. It has two tabs:

- **Active & suspended** lists businesses by name, slug, owner and status. It offers suspend and
  reactivate, and doesn't say who suspended a business or why.
- **Global user status** takes one exact UID, typed in. Nobody arrives knowing a UID.

The platform alert email links to `PLATFORM_ALERTS_URL`, a dashboard that doesn't exist. The
collection it would read, `platform_alerts`, has no read rule.

So the overview gives **Needs you**, the open alerts in full sentences, the largest tile on the
first screen. The next step is always to find a business or a person, with history attached,
and both are one tap away on the bottom bar.

## The boards

| Board | Frames | What it adds |
| --- | --- | --- |
| Overview | 1280, 411 ×2 | One dashboard of uniform tiles: trading, suspended, opened, accounts, *Needs you*, growth, activity, in progress, platform. The floating bottom bar |
| Businesses | 1280 ×2, 411 ×2 | Every status including archived, search, filter chips. One business: facts, owner and administrators, staff standings, status history with reasons, its audit log |
| People | 1280 ×2, 411 | A directory of every account. One person: standing and why, what it does to each business, history, an email delivery check |
| Alerts, activity, email | 1280 ×3 | Alerts with cause and email status. The platform audit log by day. An email suppression lookup with a reason to clear |
| States | 1280 | Every standing, button states, loading, empty, failed, unreadable, each dialog in each state, no access |

## The overview is one component, repeated

Revised 2026-10-06 at the developer's direction. The first draft mixed a figures band, alert
rows, launcher tiles, chart cards and a list, and read as five different screens stacked
together. Now every block on the overview is the same **dashboard tile**, with the same parts in
the same order:

1. **Header:** a 32 glyph chip tinted in the tile's hue, the label in `overline`, and a chevron.
   The whole tile is the link.
2. **Value line:** the figure in the mono 30/36 figure role (22 on a phone), then its context in
   `bodyMedium`.
3. **Visual, at a fixed height:** 56 on a small tile, 184 on a tall one. It holds a segmented
   bar, a sparkline, a chart, or up to four list lines.
4. **Footnote:** one `caption` line.

Tiles come in two widths, one and two columns of a four-column grid (two columns on a phone).
Every tile in a row has the same visual height, so rows line up without anyone placing them.

| Row | Tiles |
| --- | --- |
| 1 | Trading 14 (status split) · Suspended 2 (longest first) · Opened 3 this month (weekly sparkline) · Accounts 212 (weekly sparkline) |
| 2 | Needs you 2 (the open alerts, wide) · Growth (accounts as bars, businesses as a line on a right scale, wide) |
| 3 | Activity 7 in 7 days (wide) · In progress 1 · Platform 2 administrators and the limits |

The greeting is gone. The toolbar says *Overview* and shows the time the figures were read.

## Bottom navigation

Taken from the developer's three references. The chosen shape is the second (*Stock Bottom
Navigation Bar*, The Flutter Way): a floating stadium of circles, where the current destination
grows into a pill holding a primary-filled circle and its name. The first reference (a tinted
pill in a flat bar) and the third (the current item raised out of a notch) are drawn on the
States board for comparison.

- **Five destinations:** Overview, Businesses, People, Alerts and Activity. Alerts carries the
  open count, which used to sit on a bell in the toolbar.
- **Detail screens are pushed over the bar**, so they keep a back arrow and drop the bar: one
  business, one person, and Email delivery.
- **Email delivery and Limits** are no longer modules. Email delivery is reached from People and
  from a person's page. The limits are a line on the Platform tile.
- **Sizes:** circles are 56 on desktop and 48 on a phone, both at or over the 48dp target. The
  bar floats 24 above the bottom edge (16 on a phone), with a fade behind it on a phone.
- **States:** hover and pressed each move the circle one surface step lighter. Focus-visible is
  the primary ring.
- **Accessible names:** inactive destinations show a glyph only, so each carries an accessible
  name and a tooltip, and Alerts also announces its count.
- **Motion is not drawn.** The pill must grow and shrink on a spring, interruptible from where it
  is, as `CLAUDE.md` requires of anything spatial.

## Where every element reads from

The rules already let a platform administrator read most of this. The table separates **client
work** (a new screen, query or callable call) from **backend work** (a rule, a field, a callable
or an index).

| Element | Source | Readable today | Work |
| --- | --- | --- | --- |
| Trading / suspended / archived counts | `tenants` count() by `status` | yes | client |
| New businesses per week | `tenants.createdAt` | yes | client: 12 count() aggregates, or one bounded read |
| Accounts, joined this week, disabled | `users` count() by `createdAt` and `globalStatus`. Both signup paths write `createdAt` | yes | client |
| Open alerts, *Needs you*, Alerts screen | `platform_alerts` | **yes, as of 2026-10-06**: a `platformAdmin()` read rule was added, with a rules test | backend: built, not deployed |
| *Mark handled* | — | **no such state** | Not built: dropped on 2026-10-06. An alert counts as needing someone for seven days after it is raised |
| Recent activity, Activity screen | `platform_audit_logs` | yes | client: a sentence for each `eventType`; an index if filtered by kind and ordered by time |
| Platform administrators card | `users` where `accountType == platform_admin` | yes | client |
| *In progress* | `platform_user_operations` | yes | client |
| Limits tile | `platform_config/limits`, falling back to the code defaults 5 and 25 when absent | yes | client |
| Businesses list, all statuses | `tenants`, owner via `users/{ownerUid}`, staff count via count() | yes | client |
| Search | slug prefix for businesses, email prefix for people | yes | Built as prefix search only. Owner, name and substring search would need backend work: Firestore has no text search |
| Business facts | `tenants/{id}` | yes | client |
| Owner, administrators, staff standings | `tenants/{id}/staff` | yes | client |
| Business history | `tenants/{id}/lifecycle_history` | yes, platform only | client |
| Business audit log | `tenants/{id}/audit_logs` | yes | client, **and a product call** (below) |
| Suspend, reactivate | `setTenantLifecycle` | yes | none: built |
| Archive | `setTenantLifecycle` with `archived` | yes | client: the callable accepts it, and no button exists |
| People directory | `users` list | yes | client |
| Role and business on each person row | collectionGroup `staff` where `uid` | yes | client: one query per row, or a denormalised field (backend) |
| Owners / Staff / No business chips | `ownedTenantCount`, `membershipCount` | yes | client. The code calls these counters advisory, so the chip counts can drift |
| Person detail and impact | `getGlobalUserStatusReview` | yes | none: built, restyled |
| Person history | `platform_audit_logs` by uid | yes | client |
| Disable, reactivate | `setGlobalUserStatus` | yes | none: built |
| Email delivery | `reviewEmailSuppression` | yes | client: the callable exists, and no screen calls it |

**Every lookup writes an audit record.** `reviewEmailSuppression` writes
`email_suppression_inspected` on each call. So the person page checks delivery on a button,
never when it opens; otherwise every visit would leave a row in Activity.

**Two charts were left out on purpose.** Sales, revenue and daily metrics are closed to platform
administrators by the rules. The overview has no GMV, takings or transaction counts, and adding
them is a decision about what owners agreed to share, not a design question.

## Deliberate departures

1. **A business that is `active` reads "Trading".** The rules' own word is `tradingTenant`, and
   "Active" is already the word for a person who can sign in. Suspended and Archived keep their
   names.
2. **Chart bars use `green400` (#34B169), not `chart.bar`.** The token is `green700`, which
   measures **1.38:1** against a card. A chart graphic needs 3:1 (WCAG 1.4.11). `green400` is
   6.24:1, and this week's bar keeps `barEmphasis`. That makes this a question about the token,
   not about this screen.
3. **The count on the Alerts destination is page colour on red, not white.** White on `#EF4444`
   is **3.76:1** at 12px bold, under 4.5. The build reuses `HomeModuleGrid`'s badge:
   `surface.base` on `status.problem.fg`, about 5:1.
4. **Cards and tiles use radius 12 (`radius.lg`).** The home design drew 16, which is
   `radius.xl`.
5. **Filter chips are `FilterChipBar`'s, 32 tall.** The first boards drew 48 to meet the 48dp
   target. The build uses the shared component, which is 32 tall everywhere in the app, so this
   is an open accessibility question about the component rather than this screen.
6. **The figure labels use the `overline` role (12px).** The home design drew a 10px label that
   has no role.
7. **Destructive buttons are `AppButton`'s destructive tier**, outlined in `status.critical`, in
   dialogs too. The first boards drew a filled red confirmation.
8. **The bottom bar and its items are stadiums: `radius.pill` (999),** which the scale already
   keeps for "genuine capsules and circles". No new token is needed. An earlier draft of this
   README said the scale stopped at 12; it doesn't.
9. **The businesses line on the Growth chart is `blue300` (#6FB7F2),** which is `chart.series[1]`.
   A line with dots against bars, so the two series differ in shape as well as hue.

## Product calls this design does not make

- **Whether a platform administrator should read a business's audit log.** The rules allow it
  today (`firestore.rules:1119`). It holds prices, cost prices, shift variances and tender
  changes. Putting it on screen turns a permission nobody uses into one that gets used.
- **What "handled" means for an alert.** No resolution state exists. The design assumes a person
  marks an alert handled. An alternative is that an alert closes itself when its cause clears,
  e.g. the owner is reactivated.
- **Owner recovery is CLI-only.** The person page says a business can't be managed "until she is
  back, or ownership is recovered", and offers no button to recover it.

## Copy that still needs checking against the code

- **Suspend dialog:** *"Sales still waiting on a till send after it is reactivated."* Suspension
  makes the business unreadable to staff (`tradingTenant`). I haven't traced what happens to a
  queued sale through the stranded-sales path.
- **Failed suspend:** *"Trying again is safe; it cannot suspend twice."* This rests on
  `setTenantLifecycle` taking a `requestId`. Reusing the same ID on a retry is a client
  obligation.

## Sample world

The sample world is fictional, and frozen at **Tuesday 20 October 2026, 09:40** so that a
history with two administrators is consistent:

- **Administrators:** Bonnie Master is the real SIT administrator, bootstrapped 6 October. Mercy
  Chebet is invented.
- **Mwangi Hardware's people** match [`docs/design/staff`](../staff/README.md): Asha Mwangi,
  Boniface Otieno, Grace Wanjiru, Lydia Achieng, Njeri Kariuki, Samuel Ochieng. Samuel's address
  is the one the email board finds suppressed.
- **The numbers add up:**
  - 17 businesses: 14 trading, 2 suspended, 1 archived.
  - The weekly new-business series sums to 17, and the accounts series to 212.
  - People chips: 17 owners + 185 staff + 8 with no business + 2 platform = 212.

## Built, 2026-10-06

Implemented in the app on `feat/email-receipts`, uncommitted, against the components as they
stand in the working tree. The boards were then corrected to what the build draws, which is the
token-true rule: where a board and a shared component disagreed, the component won and the board
moved.

| Part | Where |
| --- | --- |
| Bottom bar | `lib/ui/bottom_nav.dart` (`AppBottomNav`); the `bottomNavigation` slot on `AppScaffold` |
| Dashboard tile and its visuals | `lib/ui/dash_tile.dart` |
| What the console reads | `lib/tenancy/platform_console_data.dart`: every query is a value, so the harness and the tests answer the same questions from seeded documents |
| Shell and overview | `lib/tenancy/platform_console.dart` |
| Businesses, one business, suspend / reactivate / archive | `lib/tenancy/platform_console_businesses.dart` |
| People, one person, disable / reactivate, Email delivery | `lib/tenancy/platform_console_people.dart` |
| Alerts, Activity | `lib/tenancy/platform_console_activity.dart` |
| Rows, panels, facts, timeline, pills, loader | `lib/tenancy/platform_console_widgets.dart` |
| Read rule | `firestore.rules`: `platform_alerts` readable by `platformAdmin()` |
| Indexes | `firestore.indexes.json`: ten composite indexes for the filtered lists |
| Tokens | `AppEffects.floatingShadow*`, `AppLayout.dashVisual*`, `dashListLine`, `chart*` |

The routing shell opens `PlatformConsoleScreen` for a platform administrator in place of
`PlatformTenantManagementScreen`. The old two-tab screen and its forms are still in
`platform_tenant_lifecycle.dart` and `platform_global_user_status.dart`, used only by their own
tests. The lookup, gateway and intent classes in the second are what the new person page calls.

**What differs from the first boards, and why:**

- The overview's *In progress* and *Platform* tiles are list lines, like every other tall tile.
- A business has no currency on its record (it lives in a configuration document the platform
  cannot read), so its facts are status, created, slug and ID.
- The business audit log cannot name products. Most records carry only a product ID, and products
  are closed to a platform administrator.
- There is no sort selector, no Activity search and no *All staff* button: each needed a query or
  a screen that does not exist.
- Clearing an email suppression asks *what changed*, because the backend requires a confirmation
  value.
- A lookup is recorded by the backend, so the person page checks delivery on a button, and the
  Email delivery lookup is recorded with the reason *Looked up from the platform console.*

**Proved:**

- 34 new tests: the data readers against the sample world, the dialogs, the bar and the grid.
- The routing shell's gating test, and the tokens, scaffold, home-navigation and reachability
  suites. 259 in all.
- The control-plane rules test on the emulator, including `platform_alerts`: 8 of 8 pass.
- Twenty harness captures (`flutter test tool/screenshots/platform_console_test.dart`, `p01` to
  `p10` at web and mobile), compared against these boards with PIL.

**Not proved:**

- Nothing has run on a device or against SIT.
- The ten indexes are not deployed, and the emulator does not enforce indexes, so a missing one
  would only show on SIT.
- The rule is not deployed either.
- The bar's spring is tested to move and settle, but no capture shows motion.

## What these files are

Standalone HTML artboards, rendered in headless Chrome at 1330 wide and read back before they
were reported; that render caught a wrapped status line, a redundant day prefix in Activity and
an email-check that would have audited every page view. They are mockups. They don't prove
anything runs, they cannot show motion, and none of the spring behaviour `AppMotion` owes a
dialog or a list is represented.
