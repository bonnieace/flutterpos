# Settings screen — a design, 2026-09-20

Five artboards for `TenantSettingsScreen`. Open [`index.html`](index.html) in a browser; each page
is self-contained HTML with no build step and no dependency on the repo.

**This is a proposal, not a record.** It is not a decision, it does not describe what to build
next, and nothing in it should be quoted back as a constraint. It draws pixels only — no widget,
test or token was changed to make it.

## The question the screen is opened with

Nobody opens Settings to browse settings. They open it because no paper is coming out, the receipt
has the wrong name at the top of it, the register is holding somebody for a count they did not
expect, or the shop is about to trade for the first time.

The screen as built answers with three words in a tab strip — *Business details*, *Printer*,
*Stock counts* — and nothing to choose between them. Each setting's standing lives *inside* its
tab, and opening the tab is what issues the read. So which setting is unset, unreadable, or
actively stopping the till is invisible until you have opened all three, one at a time.

The worst case is the currency. It is not a tab at all: it is the second panel down inside
*Business details*, below the logo well, the name field and the slogan field. What it says when
nothing is published is *"This business has published no currency, so no sale can be rung up on
any device yet"* — the most consequential sentence on the screen, under a heading that does not
predict it.

So Settings opens on **a list of what is set and what is not**, one row per setting, each carrying
its own standing. Same reasoning as [`staff/README.md`](../staff/README.md) applied to a different
record: one fact the screen exists to settle, stated where a person looks.

## Four rows, not three tabs

| Row | Standing | Condition | What the row says |
| --- | --- | --- | --- |
| Business details | Set | `branding` readable | Mwangi Hardware · Quality tools since 1998 |
| | Awaiting | nothing published | No name yet — the home and its receipts carry none |
| Currency | Set | `published` | KES |
| | **Problem** | `absent` | No sale can be rung up on any device |
| | **Problem** | `malformed` | The published settings cannot be read |
| Printer | Set | `configured` | 192.168.1.50:9100 · 58mm roll |
| | Awaiting | `absent` | Receipts are not sent anywhere. Sales are still recorded. |
| | **Problem** | `malformed` | The saved settings cannot be read |
| Stock counts | Set | `enforcement == off` | Nobody is interrupted · Mon, Thu · 4 people counting |
| | Set | `enforcement == prompt` | Ask at the register · Mon, Thu · 4 people counting |
| | Set | `enforcement == block` | Hold the register · Mon, Thu · 4 people counting |
| | **Problem** | `malformed` | Nobody is being asked to count. The register is unaffected. |

**The index colours faults, not choices.** *Hold the register* is the one setting here that can
stop a shop trading, and it is still drawn as a set value: somebody chose it on purpose. Colour is
reserved for a step nobody has taken and a document nobody can read.

**Only a problem that stops the till gets a callout above the list.** Currency does; the printer
does not, because a shop with no printer still records every sale. That is the printer panel's own
distinction — `AppStatus.attention` for absent, `AppStatus.problem` for malformed — read upwards
onto the index.

## Three deliberate departures from the app as built

1. **The currency's standing gets the container the printer's already has.**
   `checkout_configuration_panel.dart` renders all three of its states as a bare `Text`.
   `checkout_print_configuration_panel.dart` renders its three as a `Callout`, and argues why in a
   comment: *"Whether receipts are going anywhere at all is not prose about the screen, it is the
   screen's standing — and §2.1 wants a container, a glyph and a word for that, which a grey
   sentence is not."* That argument is stronger for the currency, which stops every sale on every
   device rather than the paper, and it was never applied there. Hard rule 4 is the same point:
   a status is never carried by text alone.

2. **Currency goes back to a row of its own.** It was merged into *Business details* on
   2026-09-13, and the stated objection was to a tab called *Checkout* — a name for a screen
   rather than a subject. *Currency* names the subject, and the pressure that made merging
   attractive was horizontal: a tab strip of three-word labels on a 411-pixel phone. An index row
   costs no horizontal space, so the fourth row is free where the fourth tab was not. Both panels'
   role lists are owner and administrator already, so nothing is offered to anybody new.

3. **The tab strip goes.** A standing needs a container, a glyph and a word, and none of those fit
   in a scrolling tab label. `AppTabs` stays the right control for the reports hub and the
   platform console, where the tabs are views of one subject; these are four separate documents
   with four separate standings, which is a list.

## What this cannot ship as

**Not a restyle, and it must not be shipped as one.** The index states four standings before any
of them is opened, and the screen as built cannot: `_LazySettingsTab` exists precisely so that a
panel's document is read when its tab is opened and not before — building them all at once is
what `tenant_settings_screen.dart` calls *"a behaviour change wearing a layout change's
clothes"*, and this design would do exactly that unless it reads differently. Hard rule 1 is the
reason this section exists rather than a note at the bottom.

What it needs is **one read the screen does not currently make**. All four documents sit in one
collection — `tenants/{tenantId}/configuration/{branding,checkout,printer,stock_take}` — and
`TenantDataReader` already exposes `getCollectionPage`, so it is one query rather than four. The
per-row reads are unchanged: tapping a row mounts one panel and reads one document, exactly as
opening a tab does today.

**One standing is free, and it is the one that matters.** `TenantSetupChecklist` already answers
`hasCurrency` out of the encrypted catalog cache that `CheckoutCatalogCacheRefresher` writes on
every session open, at no Firestore read at all. So the currency row — the only standing that
stops a sale — can carry its true state on this device today. The other three cannot. A smaller
version of this design that draws the list, promotes the currency, and leaves the other three
rows stating only their subject is available at zero behavioural cost.

## What the sample content is allowed to say

Every line on a row comes from a field the document actually holds. `TenantBranding` is
`companyName`, `slogan` and `logoUrl` and nothing else, so no row says who last changed a setting
or when — there is no such field on any of the four. The printer row names an endpoint and a roll
because `PrinterEndpoint` and `PrinterPaperWidth.roll` are both on the record; the stock counts
row counts assignments because `TenantStockTakeSchedule.assignments` is a list.

The read-only, role-refused and unreadable states are quoted from the panels that own them, not
rewritten.

## What these files are

Standalone HTML pages, hand-authored, no build step and no dependency on the repo. Every colour,
radius and height in them is quoted from `lib/ui/tokens.dart`, but they are drawings: they do not
prove the app runs, they cannot show motion, and the spring behaviour the real screen owes
`AppMotion` is not represented at all.

`settings-index.html` and `settings-detail.html` are screens, so their content column is 720 —
`TenantSettingsScreen` asks for `AppContentWidth.reading`, and that is what it gets on any
monitor. `settings-row-standings.html` and `settings-screen-states.html` are catalogues rather
than screens and are laid out to be read, not to match a window.
