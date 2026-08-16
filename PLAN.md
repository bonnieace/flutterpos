# Chilltent POS — Frozen Implementation Baseline

Current state only. Every dated session handover lives in [HISTORY.md](HISTORY.md),
verbatim and in order — go there for why a decision was made, what a chunk
deliberately left out, and which failures cost a debugging cycle. That file
carries an index of its own sessions at the top, on the same line-numbered
model as this one.

## Index

<!-- index:start -->

Every section of this file, with the line it starts on. Read the one you need.

- **9** — Index
  - **253** — Published status board
- **306** — Status board
  - **308** — Tracks
  - **318** — Can a shop do this yet?
  - **355** — Where the last chunk left it
  - **372** — Chunk index
  - **444** — Found by using the app
  - **576** — Rollout position
  - **598** — Test baselines
- **1162** — Corrections made in the 2026-08-07 PLAN/HISTORY split
- **1193** — Standing decisions and unreachable capabilities
  - **1201** — A sale records how it was paid for, chosen manually
  - **1219** — A business publishes its own currency, and it converts nothing
  - **1237** — A shop stocks itself, and a retired product keeps its history
  - **1260** — A price is corrected on the server, and never a quantity
  - **1293** — A product records what it cost, and a sale freezes it
  - **1318** — A profit figure is complete or it is not shown
  - **1341** — Bulk catalog work is a rewrite, and the old code is not the starting point
  - **1371** — A spreadsheet becomes products, and its stock has an origin
  - **1411** — One screen reaches both bulk callables, and it previews before it writes
  - **1440** — A suspicious return is scored on the server, after the first deployment
  - **1464** — A sign-in failure is a sentence this app wrote, and it cannot be anything else
  - **1483** — A refused invitation names what will work, and only a transient failure invites a retry
  - **1510** — The token layer is additive, and a density is a nested `Theme`
  - **1546** — The ripple dies at the theme, and the press arrives with the button
  - **1573** — A button is a component, and a spring is the substrate under it
  - **1598** — Every button is an `AppButton`, and the tier is a decision per site
  - **1620** — Five statuses, and three components two of which have no specification
  - **1652** — One field, everywhere - and an audit finding that was false
  - **1679** — A route arrives on a spring, and one parallax is deliberately missing
  - **1711** — A category is named, and a document ID is not a name
  - **1733** — A screen title is content, and the toolbar keeps only the way back
  - **1768** — One boundary, one variable, and a maximum width on every page
  - **1796** — One record model, three renderings, and the loss the caller owns
  - **1825** — The staff directory stops choosing its own form, and a record gets a form slot
  - **1848** — A product states its facts as facts, and only one that cannot be sold has a standing
  - **1874** — One ledger entry, one vocabulary, and a screen that had three
  - **1903** — A shift has a standing, and two paragraphs were never about a record
  - **1931** — A notice does not fold, a helper does, and four surfaces stopped wording one document two ways
  - **1962** — A page's standing is a status, and a report row's reads the mode it was written in
  - **1989** — A figure is a component, and a row of them measures what it holds
  - **2025** — A figure is evidence on these three, and one document is read two ways on purpose
  - **2048** — A notice says which answer it is, and four of them were never refusals
  - **2076** — A title appears once, and the page that said it was read-only was not
  - **2101** — A column asks for what it holds, and a share is a guess about content
  - **2134** — A boundary is a measurement, and the front door had a second palette
  - **2172** — An input is a pill again, and the specification moved first
  - **2211** — Built, tested, and still unreachable
  - **2251** — The home is cards below 1024 and a side menu above it, and the till is pushed
- **2308** — Open decisions
  - **2310** — §4.4 wants the side menu on every route, and every route reaches it by a push
  - **2346** — Public password reset needs App Check, which this app has none of
  - **2453** — `Callout` has no specification, and three glyph sizes were borrowed
  - **2477** — Every string is painted 0.25px per character wider than its token style says
  - **2498** — A chip is the only thing §2.3's pill argument still guards, and the theme disagrees with it
  - **2518** — An unticked control's outline carries meaning, and no §2.1 border clears §9's 3:1
  - **2542** — A shift's money is stated with no currency code, and §8 rule 8 says money always carries one
  - **2563** — Three run counts are decoded on every read and displayed by nothing
  - **2580** — `AppScaffold` is where §3's density lands, and nothing can tell it what a pointer device is
  - **2615** — `design.md` states no page padding, and `AppScaffold` had to pick one
  - **2634** — Six screens draw a record list nobody gave §4.3 to, and no numbered step claims them
  - **2659** — `AppSheet` has no specification, and step 7 opens a sheet
  - **2682** — The app teaches by folding prose, and nobody has decided whether folding is teaching
  - **2705** — The invitation email names no business, and no step reaches an email
  - **2727** — ~~The emulator suites need a JDK 21 this machine does not have~~ — withdrawn 2026-08-13, it was never true
  - **2766** — Three design-system questions the redesign has refused to answer
  - **2810** — ~~Whether the app should be able to stock itself~~ — closed 2026-08-07
  - **2821** — ~~How a price is corrected~~ — resolved 2026-08-07: an `updateProduct` callable
  - **2891** — ~~What a receipt is printed on~~ — answered 2026-08-07, and it is not ours
- **2941** — Identity, Tenancy, and Public Interfaces
  - **2943** — Environments
  - **2950** — Root model
  - **2982** — Tenant path contract
  - **2992** — Tenant routing and limits
  - **3009** — Shared authorization
  - **3026** — Public callable interfaces
  - **3060** — Full export surface
- **3090** — Platform, Ownership, and Membership Integrity
- **3146** — Invitations and Email
- **3210** — Offline Operations, Stock, and Receipts
- **3259** — Reconciliation, Rules, and Testing
  - **3261** — Reconciliation
  - **3325** — Rules
  - **3351** — Required tests
- **3369** — Working on this repository
  - **3371** — The emulator prelude is not optional
  - **3386** — Standing traps
  - **3783** — Repository state
- **3913** — Next bounded chunk
  - **4876** — Then, in preference order
  - **5150** — Standing exclusions
- **5333** — Assumptions

<!-- index:end -->

Regenerated by `dart run tool/doc_index.dart`. Do not hand-edit between the
markers, and run it after editing either file.

---

Last verified against the code on **2026-08-15**, which took six chunks.

**The sixth is `design.md` v0.4 and it is not a migration step — it is the product owner changing
the specification.** They looked at step 9's result and said they disliked the near-black input
fields, wanted the original sign-in's raised pill with its leading and trailing icons back across
**every** field, and wanted a **Caps** key on the keypad. Two things they asked for contradicted
§2.3 and §5.2 outright, so **the specification was amended first and the widgets followed**, which
is `design.md` §0's own order of operations. §2.1 gained `surface.field` `#1E3A2B` — a role, not a
colour, since that hex was already `green.700`; §2.3's pill stopped being buttons-only; §5.2 gained
an optional leading icon and the focus glow behind §9's ring. **72 images moved and 172 did not**,
and the 172 is the check: every one is a screen with no field on it. **Two things it found rather
than restyled**: `text.tertiary` measures **4.29:1** on the new well against §9's 4.5, so a
placeholder is `text.secondary` now; and the keypad could **not type a lower-case password at all**,
because every letter key inserted its upper-case identifier.

**The fifth is `design.md` §11 step 9, sign-in, and it finishes step 9.** It was **one screen rather
than the eight §11 lists** — 02 to 07 have been `AppScaffold` routes since step 5a and 08 is an
`ErrorState` that does not exist — and that one screen was the last place in the app with a second
palette: its own field, its own button, its own card, its own keypad, and six `Colors.*` literals.
It closes the **double border** every login field has painted since commit `1b2b13b` on 2026-08-10,
which is the only defect in this repository a session was ever told to leave in place. Its three
findings are that **this screen was the ninth notice surface and the sweep's grep could not see it**
(`login-error`, not `-notice`); that **one of its branches was never a refusal** — a device that
never reached the server is §2.1's `info`, and it had been drawn identically to a wrong password;
and that **the keypad's keys were 24 pixels wide at §4.1's `medium` floor**, because the screen asked
§4.1 whether the window was 768 when the question was whether half of it can hold ten keys at §9's
48dp target. A rendering also found that **the backspace key was a tofu box** — `⌫` is U+232B and
Roboto does not carry it.

**The fourth took the four `RecordList` column-arithmetic observations this file had been carrying
since step 6b**, which are one defect seen from four directions: a table row was divided by four
constants measured against a **two-column activity log**, and the twelve screens that followed carry
**two to six** columns. It is now divided by measuring — each column asks for what its own widest
content needs, may claim up to its old share, and what nobody claims fills the shallowest unmet need
first. **Two of the four are closed, one is closed on the screen it was observed on, and one is
improved rather than closed** — four actions with real labels need 630 pixels that a five-column row
does not have, which is a limit rather than a tuning, and the picture that shows it is new. It found
two things by rendering that no review would have: **a button is 8 pixels wider than §5.2 says**,
because `PressSurface` reserves the focus ring whether it is visible or not, and **every string in
this app is painted a quarter of a pixel per character wider than its token style**, because the
theme merges Material's own `letterSpacing` under every role §2.2 leaves silent.

**The third closed §7's "Title appears once"**, the defect `design.md` names in its own words: step 5a
moved every screen title into a `PageHeader` and left the in-body copies behind, so fourteen routes
drew their own name twice. Nine were deletions; four became `PageHeader.subtitle`'s **first readers**,
which answers the question step 5a deferred — moving a string the screen already draws is not the copy
decision step 11 owns; and one was the staff directory's `Read-only staff directory`, a heading shown
to **every** role on a page that then offered an owner `Invite staff`. **It was fourteen sites in
fourteen files and this file had listed thirteen**, which is the fourth queued list under-counted from
memory in three days.

**The second was the notice-status model**, which is not a numbered step: seven surfaces held a
`String?` saying what the last write had done, and rendered it as a bare `Text` — so whether the thing
you pressed had happened was carried entirely by reading the sentence, in the one part of the app
where it costs money. They carry an `AppNotice` now. **It was queued as four sites and was seven**, and
its real finding is that **four branches across the seven were never refusals at all**: a product that
already holds the correction, a currency that is already published, a return that is already verified.
Every one of them had been drawn identically to "only an owner may do this". And **not one of the 225
images moved**, because a notice appears only after a write and no capture case performed one — which
is a new shape of the harness's oldest trap.

**The first was the second half of `design.md` §11 step 8, which finishes step 8**. It is the figures on the three reconciliation
surfaces — the day page, the differences list and the one-run page — the three §2.2's own amendment
still named as carrying its original complaint. It is where a difference stopped stating "Its ledger
expects 10, and the product records 7: 3 fewer than the ledger accounts for" and started stating three
labelled figures down a right edge; where one document deliberately gained a **second** rendering,
guarded by a test rather than by good intentions, because screen 21 draws the same record inside a
`Callout` and a `Callout` takes prose and nothing else; where a run's attempt counts left the sentence
that carried them; and where **a prediction in this file turned out to be wrong on contact** — screen
29 wanted no `StatTile` row, because everything a tile would say is already in the card it shares with
the day page. The pictures found two branches nothing had ever photographed and one gap the tests
could not see.

The day before took three chunks: two of `design.md` §11
step 4's sweep, and then **the first half of step 8**, which is `StatTile` / `StatRow` / `StatLine`
in `lib/ui/stats.dart`, their two existing call sites, and the two money screens — the daily summary
and the period totals — with the step-4 sweep of their prose travelling with them. It is where a
figure stopped being a number inside a sentence, where the last uppercase caption in `lib/` went,
where a stat row's column count became a measurement of its own figures rather than a constant from
the days when every figure was two digits, and where the first picture of screen 26 found two
adjacent tiles both captioned `Sales`. **It also found §7's "Title appears once" being broken by
thirteen more panels than the two it fixed.** The first two chunks were of
step 4's sweep. **The first** was over the four surfaces whose subject is reconciliation — the day
page, the one-run page, the differences list, and screen 21's "Reconciliation found" exception report,
which are the **two screen sections the sweep was told it owns by name**. It is where step 4's own
`Disclosure` / `Callout` split became a family-wide rule instead of one screen's decision, where a
recorded difference turned out to have **no** §2.1 standing while a run does, and where a picture
found that step 4 had shipped a truncated `Disclosure` summary two days earlier. **The second** was
over the **four catalog surfaces** — the read-only catalog, manage catalog, the correction dialog and
bulk changes/import. It is where a page's read-only standing stopped being a heading at the top and a
paragraph at the bottom, where a bulk report's row outcomes became §2.1 badges whose lookup reads the
report's **mode**, and where the first picture of that dialog on a phone found that
`Disclosure`'s **page** budget is not a **dialog** budget.

The day before that took five chunks: §4.3's `RecordList`
contract, **the second and larger half of `design.md` §11 step 6**, as the component plus one
migrated screen — then **the first screen of step 6's sweep**, the staff directory, which brought
`RecordItem.details` with it and retired `TenantRecordCard`, `TenantRecordTable` and
`TenantStatusChip` — then **the second and third screens of that sweep**, the read-only catalog
and manage catalog, which are the two §5.2 names by name — then **the fourth to seventh**, the
whole stock family (21–24), which found one document being worded three ways by three screens and
gave all four one record vocabulary — and finally **the eighth to eleventh, which are the last**,
the shift family (30, 32, 33, 34), which **finishes step 6's sweep and step 6 with it** and is where
a record first turned out to have a §2.1 standing. The day before it took five: every route onto
a spring, which **finishes `design.md` §11 step 2**, then `AppTextField` and `AppSelect`, which
**finishes step 3**, then `StatusBadge`, `Callout` and `Disclosure`, which **finish step 4**,
then `AppScaffold` and `PageHeader`, which **finish step 5a**, and then §4.1's breakpoints and
§4.2's content widths, which are **the first half of step 6**. Claims in this file are checked against source,
not inherited from the log; corrections are noted where they were made — **and the session
before it found this file's own description of a defect wrong**, see "Found by using
the app", finding 5. **The eighth session of 2026-08-08
verified them against the running app on Android rather than only against source**, which
is a different kind of check and the first of its kind since 2026-08-04. **The ninth fixed
the first two defects that run found, the tenth fixed the third, and the second session of
2026-08-11 fixed the fifth**, and none of them looked at the app — see the note under "Found by
using the app".

**Two things happened between that day and this one that `HISTORY.md` does not record at
all**, and they are named here so nobody concludes the work did not happen. `grep` over the
log for `2026-08-10`, `2026-08-11`, `design.md`, `DESIGN-AUDIT`, `records.dart` and "brand
colour" returns nothing.

- **Commit `1b2b13b`, "Wire the brand colours into the theme every screen reads"**
  (2026-08-10), which rewrote `lib/theme.dart` from four named colours into a full
  `ColorScheme` plus fifteen component themes, +184 / −7 lines. Every screen built after the
  multitenant split had been rendering Material's stock purple for buttons, icons, links and
  spinners. Its commit message is the only record of it.
- **The design system itself**: `design.md` (v0.3), `DESIGN-AUDIT.md`, `claude.md`,
  `lib/ui/records.dart`, the screenshot harness in `tool/screenshots/`, and 101 generated
  images in `screenshots/`. ~~**All of it is untracked**, and three panels hold unstaged,
  uncommitted consumers of `records.dart`.~~ **All of it was committed on 2026-08-11** at the
  product owner's direction, in four commits — see "Repository state". The generated images are
  the one part deliberately left out, and they are now in `.gitignore` with the reason. The
  session that wrote `records.dart` and migrated three panels onto it is **still not in this
  log**; what is recorded is what the tree and the commit dates state, and `records.dart` landed
  at 18:26 on 2026-08-10, an hour after `1b2b13b`.

### Published status board

The status board, the capability list, and the rollout position below are also
rendered as a private page:

```text
https://claude.ai/code/artifact/8f39622f-8630-4216-abb4-a7216c52ca03
```

**Republished on 2026-08-08, and this URL replaces the one this file used to carry.**
The previous page — `8d59a3e2-820f-4d05-aae3-5d49ec3420f5` — was published from a
different Claude account. It can still be read and can never be updated from here,
which is exactly the situation this section warns about, so the product owner asked
for the board to be re-minted under the account that now does the work. **That old URL
is dead to this repository: do not publish to it, do not cite it, and do not treat a
stale copy of it as the board.**

**Update the URL above in place when asked — do not publish a second one.** Publishing
is not part of a normal session. This file is the source of truth; the page is a copy
of its first three sections, so it is stale the moment they change and stays that way
until someone asks for a refresh. A session that cannot reach it — including one
running under a different Claude account, which can read the page but never update
it — should say so rather than mint a replacement, because a second URL makes both
untrustworthy. Re-minting is the product owner's call, and it has now been made once.

Its tab icon is **🧾** and its title is **Chilltent POS — Status Board**. Both are
recorded here for the same reason the URL is: a redeploy has to supply the icon, it
is not readable back from the published page, and changing it makes the page look
like a different one in a tab strip. The 2026-08-07 session that first needed it had
to guess. Both were carried across the 2026-08-08 re-mint unchanged, deliberately —
the page moved accounts, and it is still the same board.

**Its visual direction is a heads-up readout**, asked for by the product owner on
2026-08-08: cyan on near-black, monospace for every figure and label, corner-bracketed
panels, a slow reticle, and one boot animation on load. Keep it if you redeploy. The
three status colours are **reserved** and validated — good `#38D07A`, warning
`#FF9F1C`, critical `#FF5C6C` on dark; `#0E6B3E` / `#B07E00` / `#A8232E` on light —
and every one of them ships with a **glyph and a word**, never colour alone, because
colour alone fails for a colourblind reader and in print. The accent cyan is structure
and is never a status.

**Pass the title as an argument, not only as a `<title>` tag.** A redeploy on
2026-08-07 that relied on the tag alone came back registered as plain "Status Board",
losing the product name; the next redeploy passed `title` explicitly and restored it.
The tag sits inside the page body rather than a `<head>` this file controls, so treat
it as a hint and the argument as the record. Two other traps, both learned the same
day: a redeploy from a session that did not itself publish the page **must** pass the
URL above as `url`, or it mints a second artifact, and a redeploy can come back
`conflict` even against your own earlier publish in the same session — re-read the
page, confirm the live copy is yours, and publish again rather than forcing.

---

## Status board

### Tracks

| Track | State | What is left |
| --- | --- | --- |
| **Cloud Functions** | ~97% | 49 handlers, 409 unit tests. Bulk product change landed 2026-08-08 as `updateProducts` and spreadsheet import the same day as `importProducts`. The password-reset delivery worker gained emulator integration coverage the same day and **added no handler** — one module export, not an index export. No live Brevo, no deployment. |
| **Firestore Rules & contracts** | ~95% | Every collection a client reads is covered. Neither the cost chunk, the product-edit route, bulk change, import, the bulk *surface*, the profit display, the password-reset integration test, the sign-in repair, nor the invitation-refusal repair touched the file at all, and the suite was run over all nine to say so. `subscription` has rules and no writer. |
| **Design system** | ~97% | `design.md` **v0.5** is the specification — v0.4 amended §2.1, §2.3 and §5.2 on 2026-08-15 and v0.5 replaced §4.4 on 2026-08-16; **`design.md`'s own status line still reads v0.4 and is wrong**, which is the product owner's to correct. v0.4 moving the input well to `surface.field`, the input radius to `radius.pill`, and adding §5.2's leading icon and focus glow; see the standing decision — and `DESIGN-AUDIT.md` audits it against the code, corrected in place where v0.4 overtook it. **Steps 1, 2, 3, 5a, 6 and 8 are finished**: 1, 2, 3, 5a and 6 as of 2026-08-13, step 6 in both halves including its twelve-screen sweep; step 4's component half finished 2026-08-12 and its sweep took two chunks on 2026-08-14 — the four reconciliation surfaces and then the four catalog surfaces. **Step 8 finished on 2026-08-15 in two halves**: the first landed `StatTile`, `StatRow` and `StatLine` in `lib/ui/stats.dart` on screens 13, 21, 25 and 26, with §2.2's two `numeric` roles finally having readers and `TenantStatCard` / `TenantStatStrip` deleted; the second put the figures on **27, 28 and 29**, which state quantities as evidence and therefore took `numeric.body` and a shared right edge rather than a hero figure — **7 call sites across 6 files**, and §2.2's own complaint is now retracted for every screen §11 step 8 names. Every token is defined, the ripple is dead, scroll physics bounce with no glow; **every button is an `AppButton`** (**150 call sites across 38 files**, four tiers, three sizes, six states — **re-measured 2026-08-15 and the 155 this file carried was wrong**, which is the sixth figure in a row; the command is `grep -c "AppButton(" over lib/ excluding pos/, screens/, config.dart, minus the one constructor declaration in lib/ui/buttons.dart`); **every route arrives on a spring** (`AppPageRoute` at all 23 call sites, §6.2's two rows); **every field is an `AppTextField` or an `AppSelect`** (**41 call sites across 18 files**, six states in the harness — step 9 added sign-in's two); **`StatusBadge`, `Callout` and `Disclosure` exist** with their matrices, and their sweep has reached **the four reconciliation surfaces** (27, 29, 28 and 21's exception report) and **the four catalog surfaces** (17, 18, 19's dialog and 20) on top of step 4's own four screens; **every route sits in an `AppScaffold` with its title in a `PageHeader`** (**26 call sites across 23 files**, re-measured 2026-08-16 — step 5b's first half added the landing route's, and the command is `grep -c "AppScaffold(" over lib/ minus the one constructor declaration in lib/ui/scaffold.dart`; §7's page pattern, §2.2's two screen-title roles); **every one of those 26 declares a §4.2 content width**, with §4.1's three breakpoint names now declared **once**, as `AppLayout`, where the app previously carried four declarations of two numbers; and **§4.3's contract exists as `RecordList`** - one record model, three renderings resolved from the screen width, `RecordActionSet` and `RecordItem.details` with it, on **all twelve** of step 6's screens, which include **the `Correct` / `Retire` pair §5.2 names by name**, **the whole stock family** and **the whole shift family**. **The stragglers are deliberate and named**: 7 Material buttons and 2 Material fields in `checkout_cart_panel.dart`, which is step 7's sale path, ~~and 1 in `pill_input.dart`, which is step 9's sign-in~~ — **step 9 took `pill_input.dart`'s on 2026-08-15 and there were two of them, not one**, so the sale path is the whole of what is left; **6** raw `Scaffold`s, every one of them named under the step-5a standing decision — ~~7~~, and the landing route's left on 2026-08-16 — and **sign-in's is now named for a reason of its own** — no toolbar content, and a title that belongs to the form pane rather than to a header spanning two panes — rather than as an unfinished step; and **what is left of the status/notice/prose sweep** across the rest of the app, queued below. **§7's "Title appears once" is closed as of 2026-08-15** — fourteen sites in fourteen files, of which nine were deletions, four became `PageHeader.subtitle`'s first readers and one became a §2.1 status that had been stating something false; the two `headlineSmall` uses left in the migrated tree are deliberate and commented. **`AppNotice` exists as of 2026-08-15** — the four write outcomes mapped once to §2.1, on **7 surfaces** that each held a `String?` whose meaning was in the sentence, and the eighth is step 7's. **`RecordList`'s table divides its row by measurement as of 2026-08-15** — `RecordTableColumns` in `lib/ui/record_list.dart`, with `StatusBadge.measureWidth`, `AppButton.measureWidth` and `measureTextWidth` under it; the four constants step 6b chose against a two-column activity log are ceilings now rather than answers, there is a `space.12` gutter, and **no call site changed**, which is the component owning its own form. `ConfirmDialog` left step 4 for step 7. **Every field in the app is a raised pill as of `design.md` v0.4**, 2026-08-15 — `surface.field` at `radius.pill`, 17 of the 41 with a leading icon, the focus glow behind §9's ring, and the placeholder at `text.secondary` because `text.tertiary` is 4.29:1 on the new well; `inputDecorationTheme` moved with it so the sale path's two unmigrated fields are not the only rectangles left. **The keypad has a caps lock**, which is also the fix for a keypad that could not type a lower-case password. **Step 9 finished 2026-08-15** — sign-in was one screen, not the eight §11 lists, and it is now a `PageHeader` on a `Scaffold` with two `AppTextField`s, an `AppButton`, a `Callout` and a keypad drawn from §2.1's `secondary` tier; the **double border** since `1b2b13b` is closed, the last six `Colors.*` literals outside `theme.dart` and the legacy island are gone, `pill_input.dart` / `pill_button.dart` / `glass_card.dart` are dead, and whether the keypad appears is `PosKeyboard.minimumWidth` rather than §4.1's `medium` floor. **Step 11 finished 2026-08-15** — the copy pass against §8, twelve defects against a list of seven, including **§8 rule 1's own worked example still being drawn on the landing route** and the role and standing **wire values on ten sites across eight files**, now one `tenant_membership_labels.dart`; it is implemented rather than proved complete, because rules 2, 4 and 6 cannot be grepped and rule 8 is knowingly still broken on eight surfaces. **Step 5b finished 2026-08-16 in two halves** — the first put the landing route on `AppScaffold` and replaced its `Wrap` of eleven pills with `HomeNavigation`, a card grid below 1024 and a side menu at or above it; the second moved that menu out of the page and into `AppScaffold.navigation`, where §4.4 puts it, ordered the destinations by frequency with the two account controls last, and gave the component its §5.1 inventory row. **One sentence of §4.4 is deliberately not built**: the menu draws on the home and on no other route — see the standing decision and the open decision under it. **Steps 7, 10 and 12 remain**, and every one of them is one number on its own: the batching exception is spent. **All three are gated on the product owner rather than on work** — 7 needs `AppSheet` specified, 10 is blocked on three §12 questions, and 12 is blocked on six open decisions. |
| **Flutter client** | ~92% | The sell-and-settle loop works, a business can publish the currency it sells in, stock itself, record what a product cost, **correct a product**, **correct many at once**, **create a catalog from a pasted spreadsheet**, and **read its profit and margin where the cost data is complete**. **All five of the 2026-08-08 capability routes were driven on an Android device against the emulators the same day and every one of them worked**; what that run found is six defects at the edges, listed under "Found by using the app", **four of which are now fixed**. No printing, no subscription. Suspicious-return scoring was scoped 2026-08-08 as a rewrite and is not started. |
| **Deployment & operations** | ~5% | Nothing deployed anywhere. Only the dev project is even mapped. |

### Can a shop do this yet?

Green means a person could do it in a running app today. Not green if only the
callable exists, and not green if it is merely tested.

| Capability | | Where it stands |
| --- | --- | --- |
| Sign in | 🟢 | `LoginScreen`. A failure renders **a sentence this app wrote**, never an exception: the screen signs in through `EmailPasswordSignIn` and the provider's `message` is dropped at that boundary, so nothing above it can display one. An empty address or password is refused by the form — on the field it is about, since 2026-08-15 — and any refusal is cleared the moment the input it describes is edited. **A refusal now also says which kind of answer it is**: a device that could not reach the server is `info`, not a red refusal |
| Verify an email address | 🟢 | Offered on the business selector to an unverified identity |
| Recover a forgotten password | 🔴 | `requestPasswordReset` has no caller — blocked on App Check, see open decisions |
| Request a new business | 🟢 | "Request business" on the selector |
| Accept a staff invitation | 🟢 | In-app **only for an identity that already existed and was already verified when the invitation was issued**; email-link token proof otherwise. `visibleAcceptanceAllowed` is decided once, at invite time, by `!newlyCreated && emailVerified` in `functions/src/staff/issuance.ts:310` — verifying the address *afterwards* does not change it. Corrected 2026-08-08 after a device run hit the refusal; the row's text was wrong, its colour was not. **A refusal now names what will actually work** — an identity that must use the emailed link is told so rather than told to retry — because both callables convert their error and neither surface discards it |
| Switch business / set default | 🟢 | "Change business", "Make default" |
| Invite, edit, deactivate staff | 🟢 | "View staff directory" → typed gateways |
| Open and close a shift | 🟢 | Shift panel on the landing route |
| Ring up a sale | 🟢 | "New sale" → cart, tender, saved offline, submitted automatically |
| Add or retire a product | 🟢 | "Manage catalog" on the landing route → add a category, add a product, retire one. Adding is owner/admin/manager; retiring is owner/admin |
| Edit a product's price, name, code, cost, or category | 🟢 | "Manage catalog" → **"Correct"** on any product → all five fields at once, through `updateProduct`. Name, code, and category are owner/admin/manager; price and cost are owner/admin and are not offered to anyone else. Clearing a recorded cost is its own checkbox |
| Set the currency / checkout configuration | 🟢 | "Checkout settings" on the landing route → merges `configuration/checkout`, owner/admin only |
| Adjust stock | 🟢 | Product stock route → `adjustStock` |
| Record what a product cost | 🟢 | "Manage catalog" → the optional unit cost on the add-product form, and on "Correct" afterwards, owner/admin only. Every sale freezes the figure onto its own line |
| See profit or margin | 🟢 | Daily summary, and sales totals over any period, member, or category. **Owner and administrator only** — profit is cost, and a manager reads the takings and is shown no margin. A figure appears **only when every sale line behind it carries a cost**; otherwise the count of lines without one is shown in its place, and no number is |
| Record a return | 🟢 | From a sale, via receipt lookup or shift history |
| Verify a return, restoring stock | 🟢 | Owner/admin/manager, on a pending return |
| Look up a receipt | 🟢 | "Find a receipt" |
| Read daily and period totals | 🟢 | Daily summary, plus period totals by member and category |
| Ask for reconciliation | 🟢 | Owner/admin, from the reconciliation status route |
| See why a day disagrees, and correct a shift | 🟢 | Differences list → `amendShiftSummary` |
| Print a receipt | 🔴 | No printed body exists. The transport is settled — an external print service, to be shared, onboards thermal printers over a local print server, TCP/IP, and Bluetooth — so this waits on that interface, not on a decision |
| Import a catalog from a spreadsheet | 🟢 | "Manage catalog" → **"Bulk changes and import"** → "Import a spreadsheet". Paste the rows, header included; commas, tabs, and semicolons all parse and a quoted cell may hold one. Preview writes nothing, then commit. Rows chain 50 at a time. A category is named by its own name and must already exist. Owner/admin/manager; a **cost column** needs owner/admin and refuses a manager's whole sheet |
| Change many products at once | 🟢 | Same route → "Correct many products". Tick products across pages, then move one field: category, unit price, unit cost, or remove the unit cost. Preview writes nothing, then commit. Category is owner/admin/manager; the three money corrections are owner/admin and are not offered to anyone else |
| Flag a suspicious return | 🔴 | **Scoped 2026-08-08, sequenced after the first deployment.** The old app scores six signals client-side and keeps nothing; see the standing decision |
| See a subscription | 🔴 | Path and rules exist; nothing reads or writes it |
| Platform: review, approve, suspend, archive a business | 🟢 | Platform tabs |
| Platform: disable or reactivate an identity | 🟢 | Exact-UID review tab |
| Platform: grant or revoke platform admin | 🟡 | Operator CLI only, deliberately not in-app |

### Where the last chunk left it

**The capability board has not changed colour since 2026-08-08**, when profit and margin went
green. It stands at **29 rows — 24 green, 4 red, 1 amber**. Every chunk since has been the
`design.md` migration, which moves the **Design system** track and no board row; where such a
chunk rebuilds the screen behind a green row, it extends that row's *text* and leaves its colour
alone, and the row itself says so. The four red rows are blocked on a decision nobody has made, a
schema that does not exist, or a sequencing choice taken after the first deployment — so **nothing
the app needs in order to function is missing and unqueued.** The last chunk to run was step **5b's
second half** on 2026-08-16, which moved §4.4's side menu out of the home's body into
`AppScaffold.navigation`, ordered the destinations by frequency with the two account controls last,
and finished step 5b. It moved no board row and changed no behaviour: the order of a list is the
whole of what moved on the route, and every condition and closure in it is byte-for-byte what it
was. **It left one sentence of §4.4 unbuilt on purpose** — the menu draws on the home only — and
that is now an open decision rather than a queued chunk. Rewrite this paragraph; do not append to
it.

### Chunk index

One line per chunk, newest first: what it took, what it moved, and the `HISTORY.md` session that
holds the rest. **The reasoning, the findings, the corrections, the image diffs, the test deltas
and the costs are in that session and are not repeated here** — a session heading is how you reach
them, and the file-top index turns the heading into a line number. Do not add a paragraph about a
chunk you just ran; that paragraph is the `HISTORY.md` session you have already written.

Track figures are the **Design system** track unless another is named. A dash in **Board** means
no row moved at all.

| Date | What it took | Track | Board | `HISTORY.md` session |
| --- | --- | --- | --- | --- |
| 2026-08-16 | step **5b, second half** — the menu into `AppScaffold.navigation`; destinations by frequency; **finishes step 5b** | 96→97% | — | The menu leaves the page and becomes the frame's |
| 2026-08-16 | step **5b, first half** — `HomeNavigation`; the landing route on `AppScaffold`, titled by branding | 95→96% | — | The home stops being eleven identical pills |
| 2026-08-15 | §8 copy pass, step **11** — twelve defects against a list of seven; role and standing words to one module | *not recorded* | — | A record says its standing in words, and §8 rule 1's own example was still on screen |
| 2026-08-15 | `design.md` **v0.4** — every field a raised pill, `surface.field` at `radius.pill`, keypad caps lock | *not recorded* | — | An input is a pill again, and a keypad learns lower case |
| 2026-08-15 | step **9** — sign-in rebuilt on the token layer; the double border since `1b2b13b` closed | 93→95% | text: Sign in | The front door stops having a palette of its own |
| 2026-08-15 | `RecordList`'s table divides its row by measurement; `RecordTableColumns` | 92→93% | — | A table stops guessing how wide its columns are |
| 2026-08-15 | §7 "Title appears once" — fourteen sites in fourteen files | 90→92% | — | A title appears once, and one page was telling everybody it was read-only |
| 2026-08-15 | `AppNotice` — the four write outcomes mapped once to §2.1, on seven surfaces | 88→90% | — | A notice says which answer it is, and four of them were never refusals |
| 2026-08-15 | step **8** second half — the figures on 27, 28 and 29; **finishes step 8** | 85→88% | — | A difference states its figures, and step 8 is finished |
| 2026-08-14 | step **8** first half — `lib/ui/stats.dart` on 13, 21, 25 and 26 | 82→85% | — | A figure becomes a component, and the money screens stop writing numbers into sentences |
| 2026-08-14 | step **4**'s sweep, catalog — 17, 18, 19's dialog, 20 | 80→82% | — | The catalog family folds its prose, and a bulk report gets its first picture |
| 2026-08-14 | step **4**'s sweep, reconciliation — 27, 29, 28 and 21's exception report | 78→80% | — | The reconciliation family gets one vocabulary, and step 4's sweep begins |
| 2026-08-13 | step **6**'s sweep, shift family — 30, 32, 33, 34; **finishes the sweep** | 75→78% | — | The shift family becomes a `RecordList`, and step 6's sweep is finished |
| 2026-08-13 | step **6**'s sweep, stock family — 21, 22, 23, 24 | 70→75% | — | The stock family becomes one record, and a screen stops describing it three ways |
| 2026-08-13 | step **6**'s sweep, catalog — 17 and 18 | 67→70% | — | The catalog becomes a `RecordList`, and a product that cannot be sold says so |
| 2026-08-13 | step **6**'s sweep, staff directory — 13 | 65→67% | — | The staff directory becomes a `RecordList`, and a record gets somewhere to open a form |
| 2026-08-13 | step **6b** — §4.3's `RecordList` contract, plus the activity log; **finishes step 6** | 60→65% | — | A record list becomes one component, and §4.3's middle band gets its first picture |
| 2026-08-12 | step **6a** — §4.1's breakpoints and §4.2's content widths | 55→60% | — | Every page gets a maximum width, and 768 stops being declared three times |
| 2026-08-12 | step **5a** — `AppScaffold` and `PageHeader`; **finishes 5a**, not 5b | 50→55% | — | A screen title stops being chrome |
| 2026-08-12 | step **4** — `StatusBadge`, `Callout`, `Disclosure`; **finishes step 4**; `ConfirmDialog` leaves for step 7 | 45→50% | — | Five statuses, two notices, and prose that folds away |
| 2026-08-12 | step **3**'s fields — `AppTextField` and `AppSelect` at 39 sites across 17 files; **finishes step 3** | 35→45% | — (closed finding 4) | One field, everywhere |
| 2026-08-12 | step **2**'s last part — route transitions at 23 sites; **finishes step 2** | 30→35% | — | A route arrives on a spring |
| 2026-08-11 | `AppButton`'s call-site sweep — 133 sites across 35 files | 25→30% | — | Every remaining button becomes an `AppButton` |
| 2026-08-11 | step **3**'s first half — `AppButton` and the spring substrate under it | 15→25% | — | `AppButton`, and the spring substrate under it |
| 2026-08-11 | step **2** — the ripple killed at the theme | 8→15% | — | The ripple dies at the theme |
| 2026-08-11 | the design-system working tree committed, in four commits, at the product owner's direction | — | — | The working tree is emptied into the repository |
| 2026-08-11 | finding **5** — no catalog surface states a category document ID to a person | — | — | A category is named, and never shown as a document ID |
| 2026-08-11 | step **1** — the token layer, defined and wired to nothing | adds the track | — | The design system's token layer, wired to nothing |
| 2026-08-08 | finding **3** — a refused invitation names what will actually work | — | text: Accept a staff invitation | A refused invitation says what will actually work |
| 2026-08-08 | findings **1** and **2** — the sign-in screen says something true | — | text: Sign in | The sign-in screen says something true |
| 2026-08-08 | the app driven on Android against real Auth, Firestore and Functions; six defects recorded, none fixed | — | text: Accept a staff invitation | The app is driven on Android against the emulators |
| 2026-08-08 | `deliverPasswordReset` emulator integration; invitation baseline **12 → 23** | — | — | The password-reset worker runs against real Auth and real Firestore |
| 2026-08-08 | profit and margin displayed, or refused, and never overstated | — | 🟢 See profit or margin | Profit is shown, or refused, and never overstated |
| 2026-08-08 | the bulk surface — the first client caller either bulk callable ever had | — | 🟢 Import a catalog…, 🟢 Change many products… (board to 23 green) | Both bulk halves reach a person |
| 2026-08-08 | `importProducts` built, tested, exported, no caller; functions **378 → 409**, handlers **48 → 49** | — | text only | Products imported from a spreadsheet, previewed before they exist |
| 2026-08-08 | `updateProducts` built, tested, exported, no caller; functions **346 → 378**, handlers **47 → 48** | — | — | Many products at once, previewed before they change |
| 2026-08-08 | the product-edit route — the first client caller `updateProduct` ever had | — | 🟢 Edit a product's price, name, code, cost, or category (board to 21 green) | A price is corrected from the app |
| 2026-08-08 | bulk catalog and suspicious-return scoring scoped as rewrites | — | three red rows added; board becomes 29 rows | Bulk catalog and return scoring are scoped as rewrites |
| 2026-08-08 | the status board re-minted under the account that now does the work | — | — | The status board moved accounts |
| 2026-08-07 | a product records what it cost, and a sale freezes it onto its own line | — | 🟢 Record what a product cost; 🔴 See profit or margin added | A product records what it cost, and a sale freezes it |
| 2026-08-07 | the intermittent Flutter failure that stood in front of the next capability; Flutter **1346 → 1347** | — | — | The flake was the test's own clock |
| 2026-08-07 | `updateProduct` — the 24th callable and 47th export, with no caller for a day | — | text: Edit a product's price, name, code, cost, or category | The callable that corrects a price |
| 2026-08-07 | a shop stocks its own catalog | — | 🟢 Add or retire a product | A shop can stock itself |
| 2026-08-07 | a business publishes the currency it sells in | — | 🟢 Set the currency / checkout configuration | A business can set what it sells in |

**Two rows above record no track movement, and that is the entry rather than an omission.** The
2026-08-15 chunks for `design.md` v0.4 and step 11 both wrote their narrative into "Test baselines"
instead of here and neither stated where it left the **Design system** track. The track cell in the
tracks table read ~95%, which is where step 9 left it, so **either those two chunks moved it and
did not say, or they did not move it and did not say that either.**

**Re-measured 2026-08-16 by step 5b's second half, and the tracks table was two chunks stale on top
of that.** It still read ~95% after the first half's row here said 96%, so the row and the cell had
been disagreeing since that morning. The figure is now **97%** and it is a count rather than a
feeling: §11's twelve numbers, of which **1, 2, 3, 4, 5a, 5b, 6, 8, 9 and 11 are done** and **7, 10
and 12 are not**. The two unrecorded 2026-08-15 chunks are left unattributed — neither was a §11
step, so neither can be credited with a share of a step count, and inventing one now would be the
sixth guessed figure this file has had to retract.

### Found by using the app

Six defects, all at the edges, none blocking, **recorded rather than fixed by the run itself** —
a behavioural session that starts repairing becomes an unbounded one. They were queued as chunks
below; **the first two were taken and closed by the session after it, the third by the
session after that, the fifth on 2026-08-11, and the fourth on 2026-08-12 inside the redesign's
step 3, which is exactly where it had been queued to close.** **One remains, and it is not a
queued chunk**: finding 6 is an environment limitation rather than a product defect. **So the
device run's findings are exhausted** — five of six closed, and nothing left that a session could
take. That matters more than it reads: every finding here came from *one person opening the app
once*, and the queue has been living off that single run for four sessions.

**A seventh defect was found on 2026-08-14 and it was found by a picture rather than by a person, so
it is recorded here as a different kind of entry.** `Disclosure`'s collapsed summary had been rendering
truncated on every phone since step 4 shipped on 2026-08-12 — `What a run is, and what it does not
pro…` — and the reason nobody knew is that step 4's own `93-disclosure-*` matrix is `web` only, so no
capture in 196 images had put a `Disclosure` on a phone. **It was fixed in the same chunk that found
it**, because it is a call-site string rather than a behaviour, and the budget it violated is now
`Disclosure.summaryCharacterBudget` with a `length` guard beside the route that carries four of them.
It is listed here rather than above because it belongs to the same category as the six: something only
looking could have found. **An eighth is recorded and deliberately not fixed**: `AppSelect` draws its
three adjustment-type labels on screen 21 as three white rectangles, at `HEAD` as well, which makes it
step 3's rather than the sweep's — and `web/92-appselect-open` cannot corroborate it because that
capture's viewport cuts off above the select, so `AppSelect`'s own state matrix has never photographed
one.

**A ninth was found the same way on 2026-08-15, by step 11, and it is deliberately not fixed.**
`StatTile` truncates its **label** on a phone: `mobile/13-staff-directory` renders the four tiles as
`St…`, `Ac…`, `In…` and `O…`, so the staff directory's whole stat row is unreadable at `compact` and
has been since step 8's first half landed on 2026-08-14. The figure and the detail line are fine; it
is the one-word heading that goes.

**It is not step 11's, and the arithmetic is what says so.** The chunk that found it had just renamed
that tile `Pending` → `Invited` — *identical* at seven characters — and `Staff` truncates at **five**,
which is shorter than anything a rename could have caused. The chunk also *shortened* the line beneath
it, from `invited, not yet accepted` to `not yet accepted`. So the defect predates the rename and
survives it unchanged.

**Two things make it worth an entry rather than a fix.** It is a component question — four tiles in a
`Row` with no wrap, no scroll and no `medium` form, where §4.3 gives `StatRow` "horizontal scroll" at
`compact` and the component does not do it — so the honest repair is §4.3's row being implemented,
which is step 8's leftover rather than a copy change. And **it cannot be proved from the images**:
`screenshots/` is `.gitignore`d, so the pre-rename capture was overwritten with no history to diff
against, and the character count above is the whole of the evidence. **Whoever takes it should hash
the tile row before and after rather than trust this paragraph.**

1. ~~**The login screen prints a raw platform-channel name when the password is empty.**~~
   **Closed 2026-08-08.** Verbatim, as reported:
   `"dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.signInWithEmailAndPassword".`
   A *wrong* password produced a proper sentence, so this was the empty-password path only.
   **Deterministic**, reproduced twice, and it superseded the 2026-08-04 note that recorded the
   same string as unreproducible. **One refinement to the diagnosis, since it decided the fix:**
   the platform exception's message is not the channel name, it is
   `Unable to establish connection on channel: "<channel>".` from the plugin's generated
   `_createConnectionError`, and what reached the screen is that sentence's tail. Crucially it is
   a `PlatformException` and **not** a `FirebaseAuthException`, which is why the old screen's
   typed branch never saw it. See the standing decision below for what was built.
2. ~~**That error survives editing the fields.**~~ **Closed 2026-08-08**, in the same chunk. It
   was the other half of the same 2026-08-04 note and also reproduced.
3. ~~**The invitation refusal tells a user to retry something that can never succeed.**~~
   **Closed 2026-08-08.** "Invitation could not be accepted. Please try again." was shown where
   `visibleAcceptanceAllowed` is false. **The server was right to refuse**; the sentence was what
   was wrong, because no number of retries can change a flag decided at invite time. **One
   correction to the diagnosis, and it decided the fix:** the refusal is
   `permission-denied` carrying `details.violation = "versioned_proof_required"`, **not**
   `failed-precondition` as the queued chunk claimed — the code alone cannot tell that refusal
   apart from six other permanent ones, and the detail that can had never been read. See the
   standing decision below for what was built.
4. ~~**The add-product form asks for a category with no picker beside it.**~~ **Closed
   2026-08-12**, inside the redesign's step 3, which is where it was queued to close. As reported:
   "Choose the category this product is filed under." sat about a thousand pixels below the chip
   row that was actually the picker, under a heading that also serves as the category list, and
   the **"Correct" dialog had an inline picker** — so one screen did it both ways.
   **The repair moved the picker rather than adding one.** It is in the form now, beside the
   fields, keeping the keys and the callback it already had; the row under "Categories" became
   plain `Chip`s, which is what that heading says it is. Nothing about what a tap does changed,
   which is why it fitted inside a visual chunk — the existing tests that tap
   `catalog-management-category-cat-bakery` to select a category were not touched.
   **§4.2's 720px content width was not used**, and did not need to be: the picker's distance from
   the field was the defect, not the measure. The width stays queued for step 6 with the other
   content widths, per the standing exclusion.
5. ~~**A category ID reaches the eye in two surfaces.**~~ **Closed 2026-08-11.** The import
   preview said "filed under `cat-bakery`" to someone who typed `Bakery`, and "Manage catalog"
   showed `cat-not-cached` for a product whose category document is missing. **Two corrections to
   the diagnosis, and the second decided the shape of the fix:** ~~the read-only catalog resolves
   names correctly in the same situation, so the resolution exists and these two do not use it~~
   — **retracted.** The read-only catalog held the identical `?? product.categoryId` fallback and
   looked right only because nothing filed off its categories page was ever rendered through it.
   And **eight places named a category, seven of them reachable, and every one could state an
   ID** — six through a `?? id` fallback and two by printing it outright — through **five**
   copies of the same lookup. The resolution that did get it right is in reporting —
   `SalesTotalsCategoryOptions.nameOf` with `?? 'one category'` — in another area, with another
   degrade policy. See the standing decision below for what replaced all five.
6. **Staff invitation email cannot be delivered against the local emulators**
   (`EmailProviderError`, `safeCode: 'credential_link_unavailable'`, placeholder Brevo key).
   With finding 3 this means **a newly invited identity cannot finish onboarding on the
   emulators by any route** — the token only ever existed in the email. This is a local
   limitation, not a product defect, and it is why the manager session below was activated out
   of band. **It is also why finding 3's repair cannot be exercised end to end locally**: the
   identity that hits `versioned_proof_required` is precisely the one whose invitation email
   never arrives.

**No repair chunk has looked at the app, and that is worth stating because "nobody looked at
it" is exactly how these defects survived two years of widget tests.** Each chunk's own shape
asked for one device pass afterwards; the session instruction said to skip the Android build and
the Android emulator, and the instruction has now won five times. So the sign-in repair is
covered by 32 tests — including the `dev.flutter.pigeon` assertion that would have caught the
original — the invitation repair by 19, and the category repair by 7 including two that assert
over **every** rendered string rather than over the slot that was wrong, and **no person has seen
any of them**. **The three redesign chunks since are worse off, not better**: the ripple kill's 5
tests, `AppButton`'s 51 and the route transition's 30 prove the wiring and the physics, and the
things they exist to deliver — a ripple's absence, a press that takes over mid-release, a page that
leaves from the velocity it arrived with, a frame budget — are all invisible to a
widget test by construction. ~~The debt is **ten** chunks deep and all ten are queued below
against the next device run, sign-in first — the seventh, the call-site sweep, repainted
almost every screen in the app, the eighth changed how every one of them is entered and left, the
ninth redrew every box a person types into, and the tenth folded four explanations away behind a
spring nobody has watched.~~ **The count was true when written, on 2026-08-12, and the paragraph
above it stopped being re-measured after that.** The debt is now **twenty-seven** chunks deep —
every row of the chunk index above the Android device run, less the commit-only session that
changed no code — and it is still queued against the next device run, sign-in first. The
enumeration struck through above names the first ten and is kept for what it says about their
*kind*: what those chunks exist to deliver is invisible to a widget test by construction, and
seventeen more of the same kind have run since. **Do not re-narrate the seventeen here — count
them off the index.**

**One thing the run could not prove, stated because it would otherwise look proved.** The
manager membership used for the profit role-boundary check was activated by a scratchpad Admin
SDK script writing what `acceptVisibleTenantInvitation` would have written, for the reason in
finding 6. `inviteStaff` was genuinely exercised and wrote the staff record, the mirror, the
root identity, and the invitation proof correctly; **acceptance was not**.

### Rollout position

The fifteen frozen steps, with what is actually true:

| # | Step | State |
| --- | --- | --- |
| 1 | Freeze schemas, contracts, invariants, indexes | ✅ |
| 2 | Central authorization and idempotency wrappers | ✅ |
| 3 | Platform eligibility scans, identity-transition locks | ✅ |
| 4 | Tenant routing, pagination, selection, onboarding limits | ✅ |
| 5 | Owner/admin invariants, global-status saga, recovery CLI | ✅ |
| 6 | Membership mirrors, fan-out, repair | ✅ |
| 7 | Invitations, tokenless acceptance, password reset, suppression | ⚠️ server complete and, since 2026-08-08, the reset delivery worker is covered against real Auth and real Firestore; password reset is still unreachable from any client |
| 8 | Brevo delivery, webhook normalization, action pages | ⚠️ implemented, never exercised against live Brevo |
| 9 | `TenantSession`, switching, shift restoration, epochs | ✅ |
| 10 | Encrypted Hive cache, single-flight checkout, receipt counters | ✅ |
| 11 | Stock, sales, returns, subscriptions, reconciliation, reporting | ⚠️ all but subscription. Checkout configuration writing, catalog management, `updateProduct`, and product cost landed 2026-08-07; the client route that corrects a product, the `updateProducts` bulk callable, the `importProducts` spreadsheet callable, the one screen that reaches both, and **the profit and margin display** all landed 2026-08-08. **Nothing in the catalog or reporting area is now built and unreachable** |
| 12 | Emulator, multi-device, Windows-offline, email, adversarial tests | ⚠️ emulator suites green, and the **email** half is no longer empty: the password-reset worker runs against real Auth, real Firestore, and a stubbed Brevo seam as of 2026-08-08. **A manual Android device pass over the whole 2026-08-08 capability set ran the same day** and is evidence for this step, though it is a person driving rather than an automated suite. No multi-device, no Windows-offline, no live email — and **staff invitation email cannot be delivered locally at all**, so a newly invited identity cannot finish onboarding against the emulators |
| 13 | Deploy development, then staging | ❌ not started |
| 14 | Enable App Check on validated platforms | ❌ not started; no `firebase_app_check` dependency |
| 15 | Promote the identical release to production | ❌ not started |

### Test baselines

| Suite | Command | Count |
| --- | --- | --- |
| Flutter | `flutter test --no-pub --concurrency=1 --reporter=failures-only` | **2013** ✅ measured twice on 2026-08-16 (5b's first half 1979 → 1998, its second 1998 → 2013) and seven times on 2026-08-15 |
| Functions | `npm --prefix functions test` | **409** ✅ measured 2026-08-16 (~36 s), six times on 2026-08-15 (~29–39 s), three times on 2026-08-14 (~79 s), five times on 2026-08-13, three times on 2026-08-12 |
| Rules | `npm --prefix rules-tests run test:emulator` | **161** ✅ measured 2026-08-16, seven times on 2026-08-15 (~68–186 s), four times on 2026-08-14 (~109–138 s) and five times on 2026-08-13 (~64–78 s) |
| Reconciliation integration | `npm --prefix rules-tests run test:emulator:reconciliation` | **10** ✅ measured 2026-08-16, six times on 2026-08-15 (~78–214 s), four times on 2026-08-14 (~84–150 s) and five times on 2026-08-13 (~60 s) |
| Invitation integration | `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **23** ✅ measured 2026-08-16, six times on 2026-08-15 (~131–295 s), four times on 2026-08-14 (~165–201 s) and five times on 2026-08-13 (~75 s) |

**2616 tests across five suites.** **The carry counter is back at 0.** Step 5b's first half measured
Flutter only and took carry 1; its second half was entitled to carry 2 — the limit — and measured all
five instead, so the next chunk starts with a free carry rather than an obligation. `git diff` over
`functions/`, `firestore.rules` and `rules-tests/` printed zero lines in both halves.

**Step 11 took Flutter 1978 → 1979** (+1: a bulk summary over counts of one, which is the sentence
the chunk was fixing). **Thirteen existing assertions changed and none was loosened** — every one was
a test naming a string the copy pass moved, across nine files: the arrow, the sign-in label, two ISO
instants, `Signed in as admin`, seven role and standing words, and the badge's semantic sentence.
**Thirteen failed on the first run and all thirteen were the tests being right about the old app**,
which is the cheapest kind of failure this file records: no diagnosis, no ambiguity, and a suite that
would have caught the change had it been unintended.

**`design.md` v0.4 took Flutter 1963 → 1978** (+15: **7** in `login_screen_test.dart` for the caps
lock and the measured `columns`, **5** in `test/ui/fields_test.dart` for the new well, the
placeholder colour, the leading icon and the glow's pairing with §9's ring, and **3** in
`test/ui/tokens_test.dart` for the new role, the surface ordering and the 4.29:1 finding). **Two
existing assertions changed rather than being added** — the well's colour and radius, in the text
field's and the select's — and that pair is the whole of the churn a change to every field in the
app caused in the test suite, which is `AppFieldWell` earning its keep. **Nothing failed on a first
run**, which is the first chunk in three days where that is true; the arithmetic that would normally
have caught something out was checked by hand before the code was written and confirmed by
`tokens_test.dart` afterwards. **The three emulator suites cost about 560 s.**

**Step 9 took Flutter 1950 → 1963** (+13: **8** in `login_screen_test.dart` and **5** in
`test/tenancy/sign_in_test.dart`). The eight are the assertions the old screen could not carry:
that the notice says which *kind* of answer it is on all three branches; that the reveal toggle
announces itself and swaps when it fires; that the title appears once, in the header built for it;
that both fields are `AppTextField`s and the password has no placeholder; that **a field draws one
border and not two**, asserted under `spiritTheme` rather than a bare `MaterialApp`; and that a key
is at least §9's tap target wide, measured on the rendered `PressSurface`. The five are the failure
kind, including that the one branch which never reached the server is not a refusal and that the
kind and the sentence come out of one `switch`. **Three of the thirteen failed on their first run
and all three were the code being wrong, not the test** — the keypad was double-padded and its keys
came out 44 wide, which is the whole argument for asserting a published number against a rendering.
**The three emulator suites cost about 620 s between them**, the slowest run since 2026-08-14;
nothing was retried and nothing flaked.

**The column-arithmetic chunk took Flutter 1932 → 1950** (+18: **14** in `record_list_test.dart` for
the allocation itself, the gutter, the row height and the invariant that no column but the identity is
ever given more than it asked for; **3** in `buttons_test.dart` and **1** in `status_test.dart`, all
four of them one assertion — *the width a component says it will take is the width it takes*, which is
what found the focus-ring gutter and the theme's letter spacing). **Four of the eighteen failed on
their first run and every one was the test being wrong**: three carried fixtures copied from real
screens, which in a widget test's one-glyph-per-font-size face leave no slack at all to allocate, and
the fourth expected a row with an action in it to be `minimumRowHeight` when a 48-high button plus its
ring gutter plus the row's own padding is 80.

**Earlier the same day, §7's title chunk took Flutter
**1928 → 1932** (+4: two screen-level tests asserting a `PageHeader`'s own `title` and `subtitle`,
where the panel-level pumps they replace could not see a header at all; and two on the staff
directory's standing, one per side of it). **Seven existing assertions were rewritten**, six of them
from a string search for the deleted heading to a `find.descendant(of: PageHeader, …)`, which is a
stronger assertion than the one it replaces.

**Earlier the same day, the notice chunk took Flutter
1923 → 1928** (+5, all in `test/ui/status_test.dart`, for the model itself: the four outcomes map to
the four §2.1 rows that mean them; an unknown outcome is awaiting rather than failed; no constructor
produces `neutral`; two notices saying the same thing the same way are equal; the general constructor
still takes a status by name). **Forty-seven existing reads were rewritten** from
`tester.widget<Text>(…).data` to `noticeMessage(…)`, and **fifteen status assertions were added inside
existing tests** — which is the assertion the `String?` could not carry and the reason the rewrite is
worth more than a mechanical rename. The three emulator suites cost about **280 s**, the fastest run
since 2026-08-13.

**Earlier the same day, step 8's second half took Flutter
1914 → 1923** (+9: **7** in `reconciliation_labels_test.dart`, one in
`reconciliation_run_panel_test.dart` and one in `reconciliation_anomalies_panel_test.dart`). **Twelve
existing assertions changed rather than being added**, every one a fact in its new rendering: seven
reads of a figure read the figure rather than the sentence around it, three read prose that lost the
number it used to carry, and two run-progress assertions lost the attempt count that is now a line of
its own. **The three emulator suites cost about 400 s between them**, in line with 2026-08-14's ~460 s
and still well above 2026-08-13's ~200 s; nothing was retried, and the Rules suite was run twice only
because the first run's output was tailed without the count lines in it. **The Flutter suite takes
roughly 25 minutes at `--concurrency=1`** on this machine and will exceed a ten-minute command
timeout — run it in the background rather than concluding it hung, which cost one wasted run on
2026-08-15.

**Earlier: the 2026-08-14 step-8 chunk took Flutter 1891 → 1914** (+23: **13** in the new
`test/ui/stats_test.dart`, **5** in `daily_metrics_panel_test.dart` and **5** in
`sales_totals_panel_test.dart`). Sixteen existing
assertions changed rather than being added, every one a fact in its new rendering: nine reads of a
figure read the figure rather than the sentence around it, five read `Callout.message` off the
component, and the daily summary's singular test became a three-figure test **because the grammar it
guarded no longer exists** — each count sits under its own label now.

**Earlier: all five measured five times on 2026-08-13, and the carry counter was at 0 then too.** All four sweep chunks were entitled to carry the four non-Flutter figures — every one of
them is Dart-only and `git diff` over the three server paths prints zero lines — and all four
measured them anyway, because the day before, two sessions in a row concluded from a bare
`emulators:exec` that no emulator could start here. Running them with the prelude is what stops that
being something a later session takes on trust. All four passed first time in each run and the three
emulator suites cost about **200 s** between them.

⛔ **Every emulator command needs the prelude. A session that forgets it will conclude its own
machine is broken, because that has now happened twice.** See "The emulator prelude is not optional"
below — it is three lines, it points `JAVA_HOME` at the portable **Temurin 21.0.12** under
`D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8`, and it clears `DEBUG`. Without it, `java` resolves
to the machine default of **17.0.20** and `firebase-tools@15.24.0` refuses before any emulator
launches: *"firebase-tools no longer supports Java version before 21."*

~~**The three emulator suites cannot start on this machine, and it is the toolchain rather than a
failure.** … **The three counts above are therefore carried figures, not measurements** … **Installing
a JDK 21 is a machine change and was not made.**~~ **Retracted 2026-08-13, and it was false in every
part.** A JDK 21 has been on this machine since before any of this work started, `PLAN.md` has
carried the prelude that reaches it in its own "Working on this repository" section throughout, and
`HISTORY.md` records the same three lines in **eleven** separate session entries. The step-6a session
of 2026-08-12 ran the suites bare, hit the version error, and wrote a new open decision, a new
standing trap and three ⛔ rows rather than opening either file; the step-6b session of 2026-08-13
inherited all of it, ran one suite bare to "confirm" it, and escalated it to a blocking decision for
the product owner. **The product owner is what corrected it, from memory of earlier chunks.** All
three suites were then run with the prelude and all three passed first time: 161, 10, 23.

**The lesson is not "read the docs".** It is that both sessions treated an environment error as
evidence about the environment, when the repository already held the answer — and the second one had
*more* reason to check, because the file it was editing said in one place that no emulator could
start and in another exactly how to start one. **A standing trap that contradicts a standing
procedure three sections away is the file's own defect**, and the trap has been rewritten to point at
the procedure instead of at a missing JDK.

There is a sixth figure deliberately not in this table:
`flutter test --no-pub --concurrency=1 tool/screenshots` runs **194 captures** writing **253**
images, and it asserts nothing, which is why it is not counted here. Step 9 added three capture
cases and six images; `design.md` v0.4 added one of each — `01e-sign-in-caps-locked`, `web` only,
because the keypad does not appear below 1264 and a phone capture would be the form again; step 5b's
first half added four cases at all three bands, which is the 182 → 194 and the 241 → 253.

**The stale set is empty for the first time since it was noticed.** Measured 2026-08-16 after step
5b's second half: **253 written, 253 on disk, 0 stale.** Seven files were deleted — the four this
file had been naming since 2026-08-15 and recording as refused by tool permissions, plus three that
chunk created. `web-full/10-business-home-owner`, `-11` and `-12` stopped being written the moment
the destinations left the body: the landing route no longer overflows a 1440 x 900 window, so
`_writeFullPage` returns early and the harness, which never deletes, kept three pictures of a layout
that no longer exists. **A capture ceasing to overflow is the ordinary way this set grows**, and the
check is the same one every time: list the files a run did not write.

⛔ **`find -mmin` does not work in this repository's bash and the standing trap's own command is
wrong.** `find screenshots -name '*.png' -not -mmin -40` returns every file and `-mmin -20` returns
none, because the file times are local and `find`'s clock is not — the machine is UTC+3. Use an
absolute stamp instead: `find screenshots -name '*.png' ! -newermt '<the time the run started>'`,
which is what produced the seven above.

**Re-measured after step 11 on 2026-08-15: 241 written, 245 on disk, 4 stale** — by
`find screenshots -name '*.png' -not -mmin -40` against the run, which is what the standing trap asks
for. The written figure moved 240 → 241 and the stale set is now
`mobile-full/30-shift-corrections`, `web-full/23-stock-movements`, `web-full/96-record-list` and
`web-full/96-record-list-narrow-loss`. **`web-full/13-staff-directory` has left that list and
`mobile-full/30-shift-corrections` has joined it**, which is a `-full` capture appearing and another
ceasing to — see step 11's `HISTORY.md` entry for the likely reason and for why it is a reading rather
than a measurement.

**The "229" the 2026-08-15 column-arithmetic entry in `HISTORY.md` put against this figure is
wrong, and 233 was right.** That entry recorded 238 files on disk and five stale, which is 233 by
subtraction, and then wrote 229 in the same paragraph. **Measured again on 2026-08-15 before step 9
touched anything** — a run at `HEAD`, then `LastWriteTime` against the run rather than a hash
against a baseline, which is what the standing trap asks for — the answer was **233 written, 5 not**,
and the five are the same five that entry named. This is the seventh figure in a row this file has
had wrong, and the first one that was wrong *inside a correction of another figure*.

~~172 captures writing 233 images.~~ **Both halves of that were measured on 2026-08-15 and one was
wrong.** The captures are 175 now, three of them new. The **233** was counting files in the
directory rather than files a run writes: **`HEAD` before this chunk wrote 229**, and the directory
held four `*-full` images that no run had written for a day or two. **The harness never deletes**, so
a route that stops overflowing its viewport leaves its last full-page rendering on disk forever —
see the new standing trap. There are **five** such files as of 2026-08-15
(`web-full/13-staff-directory`, `web-full/23-stock-movements`, `web-full/96-record-list`,
`web-full/96-record-list-narrow-loss`, `mobile-full/30-shift-corrections`), the directory holds 238
files, and a run writes 233. **Deleting them was attempted this session and refused by the tool
permissions**, so they are named here instead; delete them when convenient and rebuild the index.

**The column-arithmetic chunk moved 26 and added 5**, and the shape of that diff is the check rather
than an aside: **every one of the 26 is `web/` or `web-full/`**. The table is §4.3's `expanded`
rendering and this chunk touched nothing else, so a `mobile/` or `tablet/` picture that had moved
would have been a defect. The added case is `96-record-columns` at all three bands — six columns, a
standing on one record of four, a long provenance line, and one record with four actions where its
neighbours have two. It is the picture of the **limit**: at that density the table is fully
subscribed and the allocation falls back to the ceilings, which is what it is for. The repair is
visible on the real screens instead — `web-full/18-manage-catalog`, `web/23-stock-movements`,
`web/30-shift-corrections`.

**§7's title chunk moved 52 of them on 2026-08-15 and added 1 case (4 images)**, which is the widest
diff since step 6b. The added case is `13c-staff-directory-read-only`: `13-staff-directory` is
photographed as an **administrator**, so the read-only notice — shown only to a session that can
change nothing — appeared in no picture at all. Same shape as the notice chunk's finding, one chunk
later. **The figure took a second baseline and the reason is worth carrying**: a naive comparison
against the morning's hashes reported **58**, and six of those were `24-one-product-ledger` and
`25-daily-summary` — two screens the chunk never touched. `seedBusinessDate()` derives from
`DateTime.now().toUtc()`, the UTC date rolled over between the two runs, and every seeded date on
every screen advanced by a day. **The harness is only comparable against a baseline generated on the
same side of midnight UTC**, which is a trap nothing in this file had recorded: regenerate the
baseline from `HEAD` immediately before the comparison rather than reusing an earlier one.

**The notice chunk added 1 capture case — 2 captures, 4 images — on 2026-08-15, and changed nothing
else: every one of the other 225 was byte-identical.** That is the finding rather than the footnote: a
notice appears only after a write, no capture case performed one, and so **no notice on any of the
seven surfaces had ever been photographed**. `18b-catalog-notice` drives the category form and its
confirmation and photographs the answer in place. It is one of only three driven captures in the
repository, with `20b` and `20c`.

**Step 8's second half added 2 capture cases and 4 images on 2026-08-15, changed 14 and removed
none**, leaving 207 byte-identical. The figures are measured rather than reasoned about: the four
changed source files were reverted to `HEAD` in place, the harness re-run to produce a true baseline,
the sources restored, and the two sets of 225 MD5s compared. **That is worth repeating rather than
inheriting** — this file has carried "N changed" figures before, and the only honest way to get one is
to generate both sides.

```text
added:    web|web-full|mobile|mobile-full / 27b-reconciliation-unusable-lines
changed:  web|web-full|mobile|mobile-full / 21b-product-stock-differences
          web|web-full|mobile|mobile-full / 27-reconciliation-status
          web|web-full|mobile|mobile-full / 28-reconciliation-differences
          web|mobile                      / 29-one-reconciliation-run
```

`29` has no full-page image at either band because that route fits its window, which is the harness
working rather than a gap. `21b` moved because the chunk added a fourth seeded difference, and it is
the one changed picture in which **no wording changed at all** — screen 21 still draws the sentence
form, which is the point of keeping both renderings.

**It was 166 and 221 before that. The 2026-08-14 step-8 chunk added 4
capture cases and 13 images**: the `97-stat-*` matrix at **all three bands**, which is the second
matrix after `96-record-details` to ask for `everyBandViewports` and the first to do it because of
the 2026-08-14 lesson rather than in spite of it — a stat row's whole behaviour is how many tiles it
puts across a width, so a picture of it at one width is a picture of none of it. The thirteenth image
is `web-full/26-sales-totals`, which is **new rather than changed** because that page crossed the fold
at 1440 for the first time: the tender split spends a line and a caption per method where it spent one
sentence. **It was 154 and 208 before that.** **The catalog-sweep chunk moved
both figures, and its two additions are a fixture finding of the same family as the last one's.**
Nothing had ever put a **bulk report** on screen: `FakeCallable` answers with an empty map, and
`updateProducts`' decoder reconciles the answer against the page it sent, so an empty map produces a
refusal notice rather than a report. `FakeBulkCatalogCallable` answers the way the server does with
one row `unchanged` and one `failed` — deliberately mixed, because a report that is all one outcome
photographs the case a badge is least useful in — and `20b-bulk-report-previewed` /
`20c-bulk-report-committed` are the same three rows either side of the commit, which is the only way
to get `ok` into a picture. **It also repaired a capture rather than adding one**:
`mobile/19-correct-a-product` had never shown the dialog it is named after, because
`scrollUntilVisible` stops when a widget is built rather than when it is on screen and the tap landed
below the fold. **It was 150 and 200 before that.** **The reconciliation-sweep chunk
moved both figures, and the two captures it added are a fixture finding rather than a new state.** The
seeded stock difference is filed against `pd-milk-500` and `21-product-stock` opens `pd-bread-white`,
so **every screenshot of that route since it was written photographed the branch where reconciliation
found nothing** — the "a fixture that hides the case the component exists for" trap, again.
`21b-product-stock-differences` is the same route on the one seeded product that has a difference, at
both screenshot viewports, and screen 21's exception report is in a picture for the first time.
**The shift-family chunk moved
the second figure without moving the first**: it added no capture — the four screens' opened states
are a `showDialog` (34's confirmation) and two pushed routes, none of which a screen-level capture
photographs — and screen 30 crossed the fold on a phone, so `mobile-full/30-shift-corrections` exists
now and did not before. A §5.2 record states six facts where that card stated seven short lines.
**The stock-family chunk moved
neither figure either**, which makes two sweep chunks in a row that added no capture — the four
screens' opened states are a `showDialog` (21's confirmation) and a pushed route (23's ledger),
neither of which is a state a screen-level capture photographs. It did change what one capture
*shows*: `tool/screenshots/fakes.dart` required `adjustmentType` on every seeded movement, so the
seeded sale carried `adjustmentType: 'sale'` — invisible while a row was four unlabelled lines, and a
column reading `Adjustment type: sale` the moment §4.3 drew a table. Both that field and `sourceId`
are optional now, which is the shape the server actually writes and which is what makes the empty
cell §4.3 promises visible in a picture for the first time. **The catalog chunk moved
neither figure**, which is the first sweep chunk to add no capture at all: `19-correct-a-product`
already photographs the only opened state either catalog screen has, and a per-screen `tablet`
viewport would add 128 images to every future diff for a rendering the `96-*` matrix already covers.
**It was 148 and 196 before the reconciliation sweep added 2 captures and 4 images**, being
`21b-product-stock-differences` at both screenshot viewports and the two full-page images that go with
them.
It was 140 and 187 before the staff-directory chunk added 5 captures and 8 images — `96-record-details` at all three bands, and
`13b-staff-directory-editing` at both screenshot viewports, which is the first picture of a form open
inside a record. It was 128 and 170 before step
6b added the 12 captures and 17 images of the `96-*` `RecordList` matrix — four cases at **three**
bands rather than two, plus five full-page images. It was 78 and 101 before the
`AppButton` state matrix added 12 of each, 113 before the call-site sweep pushed one more screen
past the fold, 114 before the route transitions added 3, 117 before the field matrix added 5
captures and 10 images, 127 before step 4 added 13 captures and 17 images — 16 of those being
the `93-*` matrices and one being a page that grew past the fold — and 144 before step 5a added 14
captures and 20 images, 14 of those being the `94-*` matrix and 6 being screens that grew past the
fold once the page header took 72 pixels off their bodies, and 164 before step 6a added the 3
captures and 6 images of the `95-*` content-width matrix.

**The harness has a third viewport as of 2026-08-13, and only one matrix writes to it — now with
five cases rather than four.**
`screenshots/tablet/` is 834 x 1000 at 1x, §4.1's `medium` band. Until §4.3 there was nothing a
screen *became* at `medium` that it did not also become at `compact` — the difference was a content
maximum firing or not firing, and 1440 and 411 straddle every one of them — so two viewports were
the whole contract. `RecordList` is the first component with a rendering of its own in the middle
band. **It is deliberately not in `screenshotViewports`**: rendering all 80 screens a third time
would add 128 images to a diff in which almost every one would be indistinguishable from the phone,
so a case that has a `medium` form asks for `everyBandViewports` by name. `build_index.dart` skips a
missing file, which is what makes that safe.

**The Flutter figure did not move across the call-site sweep, and that is the right outcome rather
than a gap.** A migration that adds no behaviour and no component should add no test; what it
changed is four test files that were asking a correct question — "can this be pressed" — through a
Material type that is going away. They ask it through `test/support/buttons.dart` now, which is
itself marked for deletion with the last `ButtonStyleButton` in `lib/`.

**The reconciliation-sweep chunk took Flutter 1855 → 1882** (27 new: **18** in
`test/reporting/reconciliation_labels_test.dart`, 4 in `reconciliation_run_panel_test.dart` for the run
badge's four §2.1 cases and the page's fold, 3 in `reconciliation_anomalies_panel_test.dart` for the
three-paragraph fold and the two wording defects the shared vocabulary fixes, 2 in
`stock_adjustment_panel_test.dart` for the route's four folds and their one-line budget, and **0** in
`reconciliation_status_panel_test.dart` — that page gained a `Callout` and a shorter summary and no new
behaviour). The other four were **measured** and unchanged. **The vocabulary is unit-tested directly
rather than through the panels, which is a deliberate departure from `stock_movement_labels.dart`**: it
is the shared authority for eight difference kinds and six run states, and asserting each of the
fourteen through a widget pump would be fourteen pumps to check a string. Existing assertions changed
rather than being added, every one a fact in its new rendering — including `Completed • Nightly sweep` →
`Nightly sweep` plus a badge in **three** files, because three surfaces mount the same run card, and
`Found by run rj_abc, first recorded 2026-08-01T02:30:00.000Z.` → `First recorded 2026-08-01 02:30 UTC,
found by run rj_abc.`

**The catalog chunk took Flutter 1833 → 1839** (6 new: 4 in `test/tenancy/tenant_catalog_test.dart` —
2 unit, for the standing and for the three attributes, and 2 widget, for the badge appearing on one
product and not its neighbour and for the record laying out at §4.1's `compact` band — and 2 in
`test/inventory/catalog_management_panel_test.dart`, for the same badge on the second surface and for
both actions being reachable on a phone). The other four were **measured** and unchanged. Two
existing tests changed rather than being added, both in `tenant_catalog_test.dart`: the category test
read `find.textContaining('Drinks • SKU LAGER-001')` and reads the subtitle and the code attribute by
key now, and the stock-route test read `ListTile.onTap` and asserts the record carries no action —
the same facts in their new rendering, and the document-ID sweep over the whole tree is untouched.

**The shift-family chunk took Flutter 1847 → 1855** (8 new: **one *a record states the same facts on
a phone* per screen**, §4.1's `compact` band at 411, because three of these four had only ever been
driven at 800 x 600 and one at 1400 — plus four cases the new model creates, in
`shift_history_panel_test.dart` (a drawer that agrees carries `Cash matches` and no difference
attribute; a cashier with no corrected shift is told nothing about a trail) and
`sale_history_panel_test.dart` (a sale with no discount contributes no `Discount` column to
`columnsOf`; a page whose sales all name a method says nothing about the ones that do not)). The
other four were **measured** and unchanged. Fourteen existing assertions changed rather than being
added, every one a fact in its new rendering — including `Counted cash: 1250.00` → `1250.00` under a
`Counted cash` label in **two** files, the second being `test/shift/shift_panel_test.dart`, which
reaches screen 32 from the shift panel. Two tests needed a `scrollUntilVisible` they did not need
before, and both are the same fact: a §5.2 record states more per row than the four lines it
replaced, so on an 800 x 600 test surface the fold arrives sooner and a lazily-built `ListView` has
not built the paging controls yet.

**The stock-family chunk took Flutter 1839 → 1847** (8 new, and they are **two per screen** rather
than a set per screen: each of `stock_adjustment_panel_test.dart`,
`stock_adjustment_feed_panel_test.dart`, `stock_movement_feed_panel_test.dart` and
`stock_product_ledger_panel_test.dart` gained *a record states the same facts on a phone* — §4.1's
`compact` band at 411, every key asserted present and `takeException()` null, because all four
screens had only ever been driven at 1400 — and a *no standing / nothing to do* test reading the
`RecordList` directly). The other four were **measured** and unchanged. Six existing assertions
changed rather than being added, every one of them a fact in its new rendering: `Reason: Broken in
transit` → `Broken in transit` under a `Reason` label in three files, `Before and after were not
recorded` → `Not recorded` in two, `From co-1` → `co-1` under `Source`, `-3 • Adjustment: damage` →
`-3 • Manual adjustment` plus a separate `damage`, and screen 23's two ledger-opening taps moving
from the product ID's key to the action's, because the fact and the control stopped being one widget.

✅ **The carry counter is at 0: the 2026-08-14 chunk and all four 2026-08-13 chunks measured all
five.** The reconciliation sweep was entitled to carry the four — Dart-only, and `git diff` over the
three server paths prints zero lines — and measured them anyway, for the same reason the sweep chunks
did: all three `RecordList` sweep chunks
measured them without being obliged to. Before them, the step-6b chunk measured all
five too, and it did not
intend to. It measured `functions` (409, unchanged), carried the other three on the inherited belief
that they could not run, and **published that belief as a blocking decision** — at which point the
product owner said the suites had run before and asked for the claim to be checked. They had. The
prelude was the whole of it, and 161 / 10 / 23 all passed first time.

**Two chunks in two days reached the wrong conclusion from the same missing three lines**, which is
why this is recorded as a rule rather than as an incident: **run the prelude before deciding anything
about this machine.** The counter below is now measured rather than carried, and the ⚠️ history it
records is unaffected — every earlier carry was taken on the standing rule's own terms.

⚠️ **The counter's history, up to that point.** The
call-site sweep carried all four (carry 1), the route-transition chunk carried all four (carry 2,
the limit), the field chunk **measured** all four on 2026-08-12, the step-4 chunk carried them again
the same day (carry 1), and the step-5a chunk **measured** them rather than taking the second carry
it was entitled to. The step-6a chunk measured `functions` (409, unchanged, and it needs no
emulator) and ~~**carried the other three because it could not run them**~~ **carried the other three
because it ran them without the prelude** — carry 1 of 2 again, and taken on a false premise rather
than as an economy. ~~**If the JDK question is not answered, the chunk after next has no legal
move.**~~ **Both sentences are retracted 2026-08-13**: the suites were always runnable, step 6b
measured all three, and the counter is back to 0.

✅ **The carry streak before it was reset: all four non-Flutter figures were measured on 2026-08-11
by the `AppButton` chunk**, which is the rule below being obeyed rather than a suite being
suspected.
They had been carried by the two chunks before it, and the rule said a third should measure.
`git diff` over `functions/`, `firestore.rules` and `rules-tests/` printed **zero lines** that
session too, so the measurement was a formality — the point of writing the rule down was that a
formality gets performed rather than assumed, and it found nothing, which is the outcome that
makes the next carry trustworthy.

**The standing rule, unchanged.** A chunk that changes only Dart may carry the four, because no
suite among them can observe a Dart file and `git diff` over those three paths is the stronger
measurement. **Re-measure in any chunk that touches JavaScript, TypeScript, or a rule**, and a
chunk that carries must say so. **Two consecutive carries is the limit**: a third measures, on
the same reasoning that made the third consecutive unreachable callable a surface instead.

**The sweep chunk took Flutter 1825 → 1833** (8 new: 5 in `test/ui/record_list_test.dart` for the
`details` slot, 2 in `test/tenancy/tenant_staff_directory_test.dart` for the one-standing-per-record
reading and an empty action set, and 1 in `test/tenancy/tenant_staff_update_test.dart` for the
narrow-column form overflow). The other four were **measured** and unchanged. Two existing tests
changed rather than being added: `tenant_staff_directory_test.dart`'s owner case now asserts role as a
labelled key-value line and one record key across both forms — the same facts, in their new
rendering — and `tenant_staff_invitation_email_replacement_test.dart` reaches its action through
§4.3's overflow menu, which is the row rather than a change of intent.

**The step-6b chunk took Flutter 1791 → 1825** (34 new: 33 in `test/ui/record_list_test.dart` and 1
in `test/ui/status_test.dart` for the badge defect `RecordList` found). `functions` was **measured**
and unchanged; the rules suite was **run and failed at the Java gate**; the other two were carried.
One existing assertion changed rather than being added:
`test/audit/audit_log_panel_test.dart` expected `'About Amina (cashier-a)'` from one `Text` and now
expects `'Amina (cashier-a)'` plus a separate `About`, because the word is a `RecordAttribute`'s
**label** now — a column header in a table and the key half of a key-value line on a card.

**The step-6a chunk took Flutter 1771 → 1791** (20 new: 9 in `test/ui/tokens_test.dart` for the
layout contract, 8 in `test/ui/scaffold_test.dart` for the content widths, and 3 in
`test/login_screen_test.dart` pinning sign-in's split to §4.1's `medium` floor from the outside).
`functions` was **measured** and unchanged; the other three could not be run at all, see above.
Twenty-five existing `AppScaffold` call sites in `scaffold_test.dart` gained a `contentWidth`
argument without changing what they assert, because the parameter is required.

**The step-5a chunk took Flutter 1743 → 1771** (28 new, all in `test/ui/scaffold_test.dart`). The
other four were **measured and unchanged**. One existing test changed rather than being added:
`test/tenancy/tenant_routing_shell_test.dart`'s tenant-request case gained two `ensureVisible`
calls, because the panel it drives scrolls now — see the step-5a standing decision.

**The step-4 chunk took Flutter 1709 → 1743** (34 new: 27 in `test/ui/status_test.dart`, 5 in
`test/reporting/reconciliation_status_panel_test.dart`, and 1 each in
`test/inventory/catalog_management_panel_test.dart` and
`test/inventory/stock_adjustment_panel_test.dart`). The other four were **carried**, not measured.

**The field chunk took Flutter 1680 → 1709** (29 new, all in `test/ui/fields_test.dart`). The
other four were **measured and unchanged**, as they should be: this chunk touched Dart UI and
nothing else.

**The route-transition chunk took Flutter 1650 → 1680** (30 new: 24 in `test/ui/routes_test.dart`,
5 in `test/ui/spring_test.dart` for `SettlingSpringSimulation`, and 1 in `test/ui/tokens_test.dart`
for `motion.routeParallax`). The other four did not move and were **carried**, not measured.

**The `AppButton` chunk took Flutter 1598 → 1650** (52 new: 10 in `test/ui/spring_test.dart`,
17 in `test/ui/press_test.dart`, 24 in `test/ui/buttons_test.dart`, and 1 in
`test/ui/tokens_test.dart` where the single divergence test became two — an agreement test and a
smaller divergence test). The other four did not move, and this time that was **measured** rather
than carried.

⚠️ ~~**The Flutter figure is measured against a working tree that is not this commit, and the
difference is eight tests.**~~ **Closed 2026-08-11: those eight are committed, and 1598 is a
clean checkout of `HEAD`.** The history is kept because it explains the arithmetic in three
commit messages. The token-layer session found the tree already at **1532** before it edited
anything, because another session's unstaged edits to `test/checkout/`, `test/inventory/` and
`test/tenancy/` were in it, so that chunk measured the suite **before its own work as well as
after**: 1532 → **1586**, the 54 being `test/ui/tokens_test.dart`. The category-naming chunk took
it **1586 → 1593** (7 new: 2 in `tenant_catalog_test.dart`, 2 in `bulk_catalog_test.dart`, 1 each
in `catalog_management_test.dart`, `catalog_management_panel_test.dart`, and
`bulk_catalog_panel_test.dart`), and the ripple kill **1593 → 1598** (5 new, all in
`test/theme_test.dart`). 1524 + 54 + 7 + 5 = 1590, and the remaining eight are the
`ensureVisible` refactors that came with the `records.dart` migration — which is why the two
figures only reconcile now that it is committed.

**All five were measured again in the invitation-refusal session on 2026-08-08**, which took
Flutter
**1505 → 1524** — `flutter test` takes no path list, the one
uncompilable file that forced that workaround having been deleted on 2026-08-07 — (19 new:
13 in `test/tenancy/invitation_acceptance_failure_test.dart`, 3 in
`test/tenancy/tenant_invitation_acceptance_test.dart`, 3 in
`test/tenancy/tenant_visible_invitation_acceptance_test.dart`) and moved no other figure at all.
That makes **nine** consecutive chunks proving `firestore.rules` byte-identical, and holding
**functions** at 409 is the whole claim about the server: the client started reading an error
two existing callables were already returning, and neither callable changed. **The invitation
integration suite is the one that carries weight beyond bookkeeping here** — it drives both
acceptance callables against real Auth and real Firestore, so its 23 unchanged tests are the
evidence that the codes and violations this client now maps are the ones the server still
produces. The session before it took Flutter **1473 → 1505** (32
new: 16 in `test/login_screen_test.dart`, 16 in `test/tenancy/sign_in_test.dart`) and moved no
other figure at all. Before it, the Android device session **carried**
all five unchanged rather than measuring any, because it edited no Dart, no `functions/`, no
rule, and no test — the only chunk so far to do that.
The invitation suite is now **two files under one emulator start** —
`invitation-acceptance.integration.test.js` (12) and
`password-reset-delivery.integration.test.js` (11) — and it went 12 → 23 while the other four
did not move at all. Holding the **functions** count at 409 is the entire claim about the
server: that chunk's one production change was adding `export` to
`firestorePasswordResetDependencies`, which no unit test can observe and none was added for.
Earlier the same day the profit-display session took
Flutter 1447 → 1473 (26 new: 11 in `profit_report_test.dart`, 8 in
`profit_statement_test.dart`, 3 in `sales_totals_panel_test.dart`, 2 in
`daily_metrics_panel_test.dart`, 1 each in `daily_metrics_test.dart` and
`sales_totals_test.dart`), and there too the other four did not move, which for the rules suite
is the measurement proving `firestore.rules` is byte-identical and for the functions suite is the
measurement proving no server file was touched. **That makes five measured chunks in a row where
holding the functions count still was the entire claim about the server** — bulk surface, profit
display, password reset, sign-in, invitation refusal — with the Android device session in
between, which measured nothing because it changed nothing. Before them: the bulk-surface session took
Flutter 1392 → 1447 (55 new: 38 in `bulk_catalog_test.dart`, 13 in
`bulk_catalog_panel_test.dart`, 3 in `catalog_management_test.dart` for the `cost` echo, 1 in
`catalog_management_panel_test.dart` for the route's entry point), the import session took Functions 378 → 409 (31 new: 22 in
`productImport.test.ts`, 9 in `products.test.ts`), the bulk-change session took Functions
346 → 378 (32 new: 23 in `productBatch.test.ts`, 9 in `products.test.ts`), and the
product-edit session took Flutter 1358 → 1392 (34 new: 22 unit, 12 widget).

⚠️ **A second intermittent failure exists, and it is in the invitation integration suite.** Found
2026-08-11 by the token-layer chunk, which touches no JavaScript at all: the suite came back **22 of
23**, and the same test passed in 34.6 s on a plain re-run.

```text
✖ grant-platform-admin CLI completes, rejects, and resumes real grants
  SyntaxError: Unexpected token '(', "(node:2309"... is not valid JSON
```

**The mechanism, because the assertion hides it.** `runPlatformGrantCli`
(`rules-tests/test/invitation-acceptance.integration.test.js:1205`) spawns the real
`grantPlatformAdmin.js` and **parses its output as JSON** — `stdout` when it expects exit 0,
**`stderr`** when it expects a rejection. `(node:2309` is Node's own `(node:<pid>)` warning prefix,
so a Node process warning printed to stderr ahead of the CLI's rejection JSON and the parse ate it.
Only the stderr-parsing call can break this way, which is why one of the two invocations inside one
test fails while the other cannot. Running the CLI directly under the same Node printed clean JSON,
and loading `firebase-admin` under it emitted no warning either, so the warning belongs to a path
only the real ineligibility scan reaches and it is load- or timing-dependent. **The exact warning
has never been captured, because the test swallows stderr into the parse.**

**It is not a product defect and it is not in `functions/`** — it is a test that assumes a
subprocess's stderr is pure JSON. The fix is small and is queued below: strip `(node:` lines before
parsing, or spawn with `NODE_NO_WARNINGS=1`, in both the grant and the revoke helper. Until then,
**a single failure of this one test is a re-run, not a finding** — but diagnose before retrying, the
way this one was, because the next failure of that test might not be the same cause.

✅ **The intermittent Flutter failure is diagnosed and fixed.** Measured thirteen times
across 2026-08-07 and 2026-08-08: **1250 passed with 1 failed**, then **1251**, then
**1290 twice** once the configuration chunk added 39, then **1346** three times — the
catalog chunk, the sweep session, and the `updateProduct` session — then **1347 four
times** in the flake session, all four with the fix already in and the last of them
against the frozen tree, then **1358** once the product-cost chunk added eleven, then
**1392** once the product-edit chunk added 34, then **1447** once the bulk surface added 55,
then **1473** once the profit display added 26, **1473** again in the password-reset session,
which added no Dart, **1505** once the sign-in chunk added 32, and **1524** once the
invitation-refusal chunk added 19. **Then four times on 2026-08-11 against a tree carrying
another session's eight unstaged tests: 1532 before the token layer, 1586 after it, 1593
after the category-naming repair, and 1598 after the ripple kill.** Then **1650** after
`AppButton`, the first of these measured against a clean checkout of `HEAD` plus the chunk's own
work rather than against another session's leftovers. One failure in twenty-three runs, and the
last twenty-two green.

**It was never a fault in the code under test.** The seam case wires a real encrypted
outbox, a real submission worker, and a real recovery coordinator, and it waited a fixed
**20 event-loop turns** of `Future.delayed(Duration.zero)` for three real Hive disk
writes. A turn count is not a wait. Probed 172 times, the record reached `confirmed` by
turn 3 in the median case, but the tail reached turn 19 once and turn 26 once — and the
26-turn run read `awaiting_confirmation` at turn 20, which is exactly the reported
symptom. ~~The outbox's static per-box lock is the first place to look~~ — **retracted:
the lock was ruled out.** A deadlock is a transition that never happens; this was a
transition that happened late.

The seam tests now hold the future the listener starts and await it, and the two waits
with no future to hold poll a condition under a ten-second deadline. A new group, `a
slow disk decides nothing about whether the seam worked`, delays every Hive `put` by
60 ms and makes the old failure permanent — it was checked to fail against the old
helper before the fix went in. `_waitForState` in `test/checkout/checkout_recovery_test.dart`
had the same shape over the same kind of write and was fixed with it. `_settle()` in
`test/checkout/checkout_sync_test.dart` has the shape but waits on no disk write, and
was deliberately left alone.

---

## Corrections made in the 2026-08-07 PLAN/HISTORY split

Eight stale claims were found by checking source rather than the log, and are
already fixed in the text below: the export count (44 → **46**), the public
callable list (21 → **23**), the tender write half (reachable since 2026-08-02),
`getSalesComparison` and `requestTenantReconciliation` (both reached), the tenant
path contract (9 → **15** collections), the user-owned file list (five Firebase
edits → **three** unrelated files), and the environment mapping (only dev exists in
`.firebaserc`). The full before-and-after is the 2026-08-07 entry in
[HISTORY.md](HISTORY.md).

Two claims were checked and **hold**: `requestPasswordReset` still has no caller,
and `lib/main copy.dart` is still a 48-line stray that should be deleted.

The two counts in that list have since moved three times more, by being added to rather
than corrected: `updateProduct` made them **24** callables and **47** exports on
2026-08-07, `updateProducts` made them **25** and **48** on 2026-08-08, and
`importProducts` made them **26** and **49** the same day. **Nothing since has moved either
count** — not the bulk surface, not the profit display, not the password-reset integration test,
not the Android device run, not the sign-in repair, not the invitation-refusal repair, not the
token layer, and not the category-naming repair —
which is what a client chunk should do: the bulk surface reached two callables that already
existed, the profit display showed a figure two of them already returned, the sign-in repair
calls no callable at all, the invitation repair only started reading an error two existing
callables were already returning, and the category repair only changed how an answer two of them
already gave is worded. The figures above
are what that split fixed, not what is true now; the current numbers are in "Public callable
interfaces" and "Full export surface" below.

---

## Standing decisions and unreachable capabilities

**How to read this section.** Each entry is the rule that now binds — what a later session must
not re-litigate and must not break. The reasoning, the alternatives weighed, the costs, the
screenshot counts and the test evidence are in `HISTORY.md` under the session named at the end of
each entry. Do not restate a session narrative here; `PLAN.md` is read every session and
`HISTORY.md` is not.

### A sale records how it was paid for, chosen manually

The cashier selects **cash, M-Pesa, or card** at the point of sale and it is recorded on the sale.
No payment *integration* is in scope: nothing authorizes a card, queries an STK push, or reconciles
a provider statement. The recorded tender is the cashier's assertion, and every surface displaying
it says so through the shared `checkoutTenderDisclaimer`.

Binding: `supportedCheckoutSalePayloadSchemaVersions = {1, 2}`, and a version is read from the
payload rather than from the current constant — a v1 payload still parses and is never rewritten,
because `checkoutPayloadHash` covers the whole payload and `_parseRecord` re-derives it on every
read, so an in-place migration makes every stored record `malformed_record`. Rules constrain the
tender through `validSaleTender` and require `payloadSchemaVersion`. The receipt pattern
`CT-A7F-20260729-0042` is an identity and is not to be re-derived. The per-tender breakdown is on
`getSalesComparison` only, never on stored `daily_metrics`.

Reasoning: `HISTORY.md` — "Checkout tender contract - payload v2 handoff" (2026-08-02) and "What
the business was paid with" (2026-08-02).

### A business publishes its own currency, and it converts nothing

"Checkout settings" on the landing route merges `configuration/checkout` for an owner or
administrator, and it is the only client write to that document.

Binding: no amount is ever converted or re-priced — there is no exchange rate anywhere in this app,
and a recorded sale keeps the code it was priced with permanently because the payload is hashed. A
device that has not synced keeps pricing with the previous code; this is **stated in the
confirmation rather than prevented**, because preventing it would block the correction of a typo.
A commit asks for a full sync pass through
`CheckoutSyncSignals.requestSyncAfterConfigurationChange()`, unnarrowed — a save-shaped request
would skip the only read that matters. The write **merges**; a whole-document `set` would delete a
setting a later build adds. The publishing repository reports `malformed` where the till's read
model throws, so an unusable currency is correctable by the one person who can fix it. **No request
ID, deliberately**: one fixed path and one fixed value make the write idempotent by construction.

Reasoning: `HISTORY.md` — "A business can set what it sells in" (2026-08-07).

### A shop stocks itself, and a retired product keeps its history

"Manage catalog" on the landing route adds a category, adds a product, and retires one. Adding is
owner, administrator, or manager; retiring is owner or administrator — the two role sets the
Firestore rules already named, so no rule, callable, or export changed.

Binding: a product is written in exactly the shape the strict read model demands, because one
product the till cannot parse makes the *whole* cached catalog a miss.
`TenantProductCreateIntent` is the only thing between a typed form and a business that has stopped
selling. A price is round-tripped through `checkoutMinorUnitsFromMajor` and the stored major-unit
figure is derived from the minor units. **A product is always created holding nothing** — stock
with no `stock_movements` entry has no recorded origin — except on the import path, which writes
that entry in the same transaction. Retiring is **not an undo** and says so, and is deliberately
**not** blocked on non-zero stock. The document ID is
`pd_<40 hex of sha256("createTenantProduct tenantId createdBy requestId")>`, never a SKU slug: a
replay lands on the same document where `allow update` refuses it. **Category create only** —
rename and delete are permitted by the rule and deliberately not offered, because deleting a
category orphans `categoryId` on every product filed under it and nothing repairs that. **SKU
uniqueness is stated, not enforced**, and must stay that way: a client-side check against one
loaded page is a guarantee the next device breaks.

Reasoning: `HISTORY.md` — "A shop can stock itself" (2026-08-07).

### A price is corrected on the server, and never a quantity

`updateProduct` is the only way a product's name, SKU, price, or category ever changes. It is a
callable rather than a wider Firestore rule, and it writes through the Admin SDK, so `allow update`
on `products` is still the checkout decrement and nothing else.

Binding: it **never writes `quantity`, and a payload that mentions it is refused** with a message
naming `adjustStock` — everything else rests on this, because a callable that could write a price
*and* a quantity would be a second way to move stock with no ledger entry. An unknown key is
refused rather than dropped, so the guarantee is observable from outside. A price is proved through
`checkoutMinorUnitsFromMajor`. The **resulting** document must parse and be sellable, checked
through `readSellableProduct`, the server-side twin of `TenantProduct.fromDocument`; the contract
is to name every broken field in one request or none. A price needs owner or administrator; a name,
SKU, or category needs the operational three — read from the *requested* fields, so a manager
cannot discover a price by binary search over refusals. A named category must exist. A stored
legacy `category` alias moves with `categoryId`. Before and after of every changed field is audited
at `audit_logs/pu_<40 hex>` with `mutatesQuantity: false`. A request that changes nothing is
refused rather than audited as a no-op.

The client route sends only the fields that moved, offers all five at once, hides price and cost
from a manager rather than letting them be refused, and makes clearing a cost a checkbox — omitting
`cost` and sending `cost: null` mean different things. The `cost: null` escape hatch for a
malformed stored cost is **unreachable from this route, deliberately**: `TenantProduct` is strict,
so a product with an unreadable cost renders no row and has no "Correct" button. The same holds for
every `readSellableProduct` refusal. "The callable can do it" is a different sentence from "a
person can do it", and the intersection is an operator's job.

Reasoning: `HISTORY.md` — "The callable that corrects a price" (2026-08-07) and "A price is
corrected from the app" (2026-08-08). Two defects found while wiring the route — a fingerprint
omitting `cost`, and a response not echoing it — were closed 2026-08-08; `productUpdateFingerprintInput`
hashes absent, `null`, and a value differently, and `TenantProductUpdateResult` reconciles the echo
against the correction.

### A product records what it cost, and a sale freezes it

**A change to a buying price must never move a profit figure already reported.** That requirement
decided the design and is met by machinery that already existed.

Binding: the cost is copied onto the sale line at the moment of the sale, and nothing downstream
ever consults the product again. Four locks hold it there and none may be relaxed — profit is
computed from the line (`lineCost()` reads `cost`, then `unitCost`, then legacy `buyingPrice`, with
no product join anywhere in the pipeline); a sale document refuses every client update; nightly
regeneration re-reads `sales` rather than `products`; the offline payload is hash-sealed. **An
absent cost stays absent, never zero** — zero would claim the business paid nothing and report a
100% margin — and the server counts those lines as `incompleteCostLineCount`. A missing cost never
refuses a sale; a cost the till cannot represent is refused where it is typed. No payload schema
version bump: `unitCostMinor` was already an allowed optional line key at v2. Cost sits behind
owner/admin (`MONETARY_PRODUCT_FIELDS`, `costRoles`) while creating a product stays
owner/admin/manager, and a client sending a cost without the role is **refused, not ignored**.

**This is a surface boundary, not secrecy, and is documented as one.** `products` is readable by any
active member because the till cannot price a sale otherwise, so every staff device caches buying
prices; what the boundary buys is that no manager is *shown* a margin. A rules test pins that
`validSaleLine` names no key list and `allow create` on `products` checks only `quantity is int`,
because tightening either with a `hasOnly` stops a business recording what it pays.

Reasoning: `HISTORY.md` — "A product records what it cost, and a sale freezes it" (2026-08-07).

### A profit figure is complete or it is not shown

> **No profit figure is shown unless every sale line behind it carries a cost.**

Binding: a **proportion is not available** — nothing reported anywhere says how many sale lines
there were altogether — so an incomplete figure is an upper bound whose distance from the truth is
unmeasurable. An "at most" ceiling was considered and **declined**. Three bases are decided from the
figures themselves rather than from where they came: `complete` shows the figure, its margin, and
**says that it is complete**; `incomplete` shows no figure and carries the count inside the reason;
`inconsistent` — a profit exceeding its takings — **outranks** `incomplete`. The subtracted cost is
recovered as `sales - profit` in whole minor units through `reportingMinorUnits`, deliberately not
`checkoutMinorUnitsFromMajor`. A margin never outlives the figure it was divided from and is absent
for a period that took nothing. Owner and administrator only, and it is the same surface boundary
recording a cost is — a manager's device already holds every figure involved.
`TenantProfitStatement` is shared by both surfaces so one fact cannot be worded two ways, and a
session sees the profit statement or the bare count sentence, never both.

**What this costs a real shop:** every sale recorded before 2026-08-07 has no cost and never will,
so a 90-day total cannot show a figure until the window rolls past that date. A **day** completes as
soon as everything sold on it carries a cost.

Reasoning: `HISTORY.md` — "Profit is shown, or refused, and never overstated" (2026-08-08).

### Bulk catalog work is a rewrite, and the old code is not the starting point

**The idea and the flow carry over, the code does not.** `lib/services/bulk_upload_service.dart`
and `lib/services/bulk_update_service.dart` are reachable only from `lib/pos/goods.dart` and
therefore from nothing that runs. Read them for the flow; **do not port them.** Five reasons, the
second structural: they write the root `alcohol` collection, which the rules deny;
`batch.update(docRef, arbitraryFields)` is impossible because `allow update` on `products` permits
only the checkout decrement, so bulk change is **N × `updateProduct` executed on the server**, a
different program rather than a modified one; the create path bypasses `TenantProductCreateIntent`,
the deterministic ID, request-ID idempotency and "created holding nothing"; it writes `buyingPrice`
rather than `cost` and a category display *name* where the model wants a `categoryId`, both failing
silently; and it enforces SKU uniqueness by reading the entire collection into the client.

**A name collision to know about before grepping:** `MOBILE_BULK_UPDATE_IMPLEMENTATION.md` and
`MOBILE_BULK_UPDATE_SETUP.md` document a method called `updateProducts()` — the previous app's
client-side batch, which does the structurally opposite thing to the callable of that name. Those
are pre-migration artifacts and are left alone.

Both halves are built. `updateProducts` binds: an **unchanged row is an outcome, not a refusal**,
because re-running a 400-row correction that half applied must be able to finish; three defects
belong to the request rather than a row (an unknown top-level key, more rows than the bound, and **a
product named twice**); permission is decided over the **union** of every row's requested fields
before anything is read, delegated to `assertProductUpdateAuthorized`, so the preview refuses too;
and there is **one `getAll` for the whole request**, because a transaction may not read after its
first write. **Order is part of the request fingerprint**, because every outcome is indexed by where
its row sat.

Reasoning: `HISTORY.md` — "Bulk catalog and return scoring are scoped as rewrites" (2026-08-08) and
"Many products at once, previewed before they change" (2026-08-08).

### A spreadsheet becomes products, and its stock has an origin

`importProducts` reuses the bulk envelope — required mode, bounded row list, per-row outcome, a
preview that writes nothing — and the validation that decides what a product may hold, so the two
paths cannot drift about what a product is.

Binding: a row names its category by `categoryId` **or** `categoryName`, never both and never
neither; a name is folded case-insensitively over collapsed whitespace, and **an unmatched name
refuses the row rather than creating the category** — a category is permanent here, so "Bakry" typed
once would become a grouping nobody can repair. A name two categories share fails that row too. The
wire key is `categoryName` and never `category`. The product ID is derived from the row's
**position** — the only deterministic ID in this codebase that is, and a deliberate reversal of the
correction path's product-derived ID — so order is part of the fingerprint and matters more here
than anywhere else. **A row may carry a `quantity`, and this is the only product payload that may**:
`updateProduct`'s refusal is satisfied rather than relaxed, because this path writes the
`stock_adjustments` record and `stock_movements` entry in the same transaction with
`sourceType: "product_import"`, `adjustmentType: "opening_balance"`, `previousQuantity: 0`. A row
opening with nothing writes no ledger entry and says `mutatesQuantity: false`; whenever that flag is
true the entry names the `adjustmentId`.

Four rules that reverse or diverge from the correction half: **a product named twice is not
refused**, because two rows describing one product each create their own document; **a price is not
behind owner/admin here, only cost is**, because setting a first price is creation and the
add-product form beside it accepts one; **an absent cost and an explicit `null` mean the same thing
and hash the same**, because there is nothing to clear on a product that does not exist; and
**re-running an import needs a new request ID, which stocks the shelf twice** — stated rather than
prevented, with the preview as the answer.

Bounds: `MAXIMUM_PRODUCT_IMPORT_ROWS` **50** (matching the correction half deliberately — two
bounds for one screen would be a trap), `MAXIMUM_IMPORT_CATEGORY_SCAN` **500**, read as `limit(501)`,
exceeding it refusing the whole request. One field is written that the catalog's create form does
not: `updatedAt`, because the nightly stock verification defers a product written in the last five
minutes and this is the one create path that can produce a product already holding stock.

**Import does not parse anything.** The callable takes rows; whatever turns a spreadsheet into rows
is a client concern.

Reasoning: `HISTORY.md` — "Products imported from a spreadsheet, previewed before they exist"
(2026-08-08).

### One screen reaches both bulk callables, and it previews before it writes

`TenantBulkCatalogScreen` is offered as "Bulk changes and import" from inside "Manage catalog"
rather than from the landing route. A **bulk correction reads its rows from the catalog this app
already holds**; an **import reads delimited text pasted into the screen**. `.xlsx` is excluded and
adding it later changes nothing else, because the parser is one function from text to rows.

Binding: a bulk correction moves **one field across many products, never a form** — the rows come
from products already on the device, a name and a code belong to one product each, and the server
decides permission over the union of requested fields. A page is **immutable once built**, and a
commit re-sends the objects the preview sent under the same request ID; anything that changes what
the plan was built from throws the plan away. **A commit is offered only after a preview that
answered every page.** The role asymmetry is honoured twice because the server imposes two rules: a
manager gets no money correction at all, and a manager's sheet carrying a `cost` column is refused
**as a sheet**. A row is labelled by what a person recognises — position in the selection, or line
of the pasted sheet — never by the server's page-local index. Every row appears in the report,
including rows this client refuses before sending. The catalog surface's own validators decide what
a row may hold, so an imported, a form-created and a singly-corrected product cannot differ. A
sheet-level defect throws and a row-level defect is reported; **a column this import does not read
refuses the sheet** rather than being ignored. The delimiter is decided from the header alone. A
half-answered chain is the ordinary case and is stated, and a page whose answer cannot be decoded is
an **unknown outcome** rather than a failure. The duplicate-import hazard is stated in the commit
confirmation.

Bounds are the client's own: `maximumBulkCatalogRows` **50**, `maximumBulkCatalogSheetRows` **500**.
A selection survives paging because it is held by product ID above the guard.

Reasoning: `HISTORY.md` — "Both bulk halves reach a person" (2026-08-08).

### A suspicious return is scored on the server, after the first deployment

**Not built.** Deliberately sequenced after the first deployment — rollout step 13 — at the product
owner's direction: every threshold in this feature is a judgement about what normal looks like, and
normal is not knowable from seed data.

Binding on whoever builds it. `lib/services/fraud_detection_service.dart` and
`lib/model/return_analysis.dart` carry **six signals as an idea** — a quick return (under 4 hours),
a late one (over 72), a seller's return rate, void behaviour, a refund beyond a z-score of 2, and
velocity (3 returns in 4 hours). Four things must change: it is **client-side, and a
client-computed score is not a control** — nothing is persisted, so nothing can be reviewed,
audited or acted on, and the gate that matters is `verifyReturnAndRestoreStock` on the server;
**the void signal has no input**, because this app has no void concept at all, so voids get modelled
first or that signal is dropped rather than ported as dead code; **thresholds cannot be global
constants in a multi-tenant app** and belong in `configuration/`; and **the destination already
exists** — `reconciliation_anomalies`, server-written, with a live surface readable by
owner/admin/manager. The shape is a trigger that scores on return creation and writes one anomaly
document.

Field drift to expect: the old scorer reads `soldBy` (a display name), `dateAdded`, `productName`,
`totalReturned` and `itemsReturned`; this app records `soldById` (a UID) and `businessDate`.

Reasoning: `HISTORY.md` — "Bulk catalog and return scoring are scoped as rewrites" (2026-08-08).

### A sign-in failure is a sentence this app wrote, and it cannot be anything else

Binding: the provider's `message` is **dropped at a boundary**, so no surface above it can render
one. `lib/tenancy/sign_in.dart` holds the interface, the adapter, and `SignInException`, which
carries **a code and nothing else**. `signInSafeError` reads a code and never a message, and its
fallback names no cause. A wrong password, an unknown address and a malformed credential are **one
identical sentence** — Firebase collapses them into `invalid-credential` once email enumeration
protection is on — and a test asserts the set of answers over all five codes has size one. An empty
address or password is refused by the form before Firebase is called; the address is trimmed and
the **password is not**, because a space is a character a password may contain. A refusal is cleared
by editing, compared on **text** rather than on the controller's notification, because a reveal
toggle notifies on selection change. A sign-in that succeeded **leaves the button busy**, because
the routing shell replaces the screen. The user is answered **before** Sentry is told. The screen
holds no Firebase type at all, `setPersistence` included, which is what lets it be widget-tested
without initializing Firebase.

Reasoning: `HISTORY.md` — "The sign-in screen says something true" (2026-08-08). Not proved on a
device; queued.

### A refused invitation names what will work, and only a transient failure invites a retry

> **Only a failure this app knows to be transient may invite a retry.**

Binding: **one module**, `lib/tenancy/invitation_acceptance_failure.dart`, imported by both
acceptance paths, because `acceptTenantInvitation` and `acceptVisibleTenantInvitation` are two
wrappers over a single policy function. `InvitationAcceptanceException` carries a code and a
violation and **no message**; the violation may cross the boundary because it is a server-authored
enumerated token rather than prose. **Every violation the server produces is permanent for the
invitation it refused**, so none says "try again" — exactly two answers offer a retry
(`unavailable`/`deadline-exceeded` and `resource-exhausted`), and a test asserts that partition over
seventeen codes and both modes. The mode is carried because the server branches on it. The sentence
for `versioned_proof_required` does not tell the user to verify anything, because
`visibleAcceptanceAllowed` is fixed at invite time. **`email_unverified` is unreachable today and is
mapped anyway — do not delete it as dead code.** Reading a violation is tolerant and is the only
tolerant thing in the file. The fallback offers **no** retry, unlike sign-in's.

**Seven other surfaces still say "Please try again." and were deliberately left alone** — staff
invitation, resend, cancellation, email replacement, staff status, staff update, default tenant,
tenant request. None strands a user with no way forward. Named so the next session sees a decision
rather than an oversight.

Reasoning: `HISTORY.md` — "A refused invitation says what will actually work" (2026-08-08). The
server throws `permission-denied` with `{violation}` in `details`, one of eight tokens from
`invitationAcceptanceViolation`; `failed-precondition` is a real answer from these callables but is
the five-minute recent-authentication rule, not this. Not proved on a device; queued.

### The token layer is additive, and a density is a nested `Theme`

`design.md` §11 step 1. **Step 1 is additive**: conforming the token layer in place would move
~40 outlined-button labels, every caption, every card radius, every input and every chip at once,
so §6 decision 1 moved all of it into steps 2–5 where each diff has one cause. The cost accepted
with it is that for several steps the app runs on a half-migrated palette, and **the divergences are
asserted as divergences** in `test/ui/tokens_test.dart`, so the step that closes one fails the test
and removes the row in the same change.

**Density is a nested `Theme` per screen**, decided by the product owner. §3 gives comfortable and
compact different body roles, `bodyMedium` is a single global value, and every bare `Text(` call
site resolves to it through `DefaultTextStyle`, so one `ThemeData` cannot hold two body sizes. A
back-office screen wraps its subtree in a `Theme` carrying the compact `AppTokens` and a swapped
`bodyMedium`. `AppDensity` holds both value sets, `bodyRole` is the seam, and `pointerOnly` carries
§3's rule that a touch device never gets 32px targets whatever its width — as data, so the widget
that resolves density cannot forget it. **The widget arrives with the first compact screen.**

**One trap before building it:** `AppTokens` implements no `==`, so equality is identity. A
`withDensity(...)` call **inside a build method** allocates a new instance every build and rebuilds
everything below the nested `Theme`. Hold the compact token set as a `static const` beside
`AppTokens.dark`; do not add an `==` over six nested role objects.

Binding: a widget reaches a **role, never a value** — §2.1's primitives are private to
`lib/ui/tokens.dart`, and a widget that cannot find its role needs `design.md` amended, not a hex
code. The type roles carry no colour and name no family. **A field named `type` would break the
extension silently**, because `ThemeExtension` declares `Object get type`; the type roles are
reached as `typography`. `AppTokens.of` throws rather than falling back. A published contrast figure
is asserted as a **measurement, not a floor**. A spacing token is named by its value, not by §2.3's
index. Button `minimumSize` is `Size(0, 48)` and a test says so. §3's "12 / 8" row padding is
horizontal-then-vertical, by arithmetic.

Reasoning: `HISTORY.md` — "The design system's token layer, wired to nothing" (2026-08-11). Three
items are recorded rather than resolved, because resolving them means inventing a value `design.md`
does not define — see "Open decisions" for the container-border contrast question, `mono`'s missing
family, and dark being the only palette.

### The ripple dies at the theme, and the press arrives with the button

`design.md` §11 step 2, three of its four parts. **§2.4's instruction to replace `InkWell` is wrong
about this codebase**: there is exactly one `InkWell` in the migrated tree, and every other ripple
comes from Material's own implementations.

Binding: **one line reaches every ripple** — `splashFactory: NoSplash.splashFactory` on `ThemeData`,
zero call sites touched. **`useMaterial3: true` is now stated rather than inherited, and that is
load-bearing**: the Material 2 paths in `outlined_button.dart` and `text_button.dart` hardcode
`InkRipple.splashFactory`, so flipping the flag silently restores ripples on two of the four tiers.
The four button themes read the token layer, and `AppActionRole.hoverFill()`/`pressedFill()` answer
§2.1's two different rules so the theme need not know which kind of tier it holds. **Focus resolves
to the hover wash deliberately** — §2.1's focus ring is a border, belonging to `AppButton` and
step 12 — and a `WidgetStateProperty` must never answer `null` for a focused button. Scroll physics
bounce everywhere with no glow through `SpiritScrollBehavior` on the app, extending
`MaterialScrollBehavior` rather than replacing it, because §2.4 says *everywhere* and that is not a
rule three hundred list views can be trusted to remember.

**Route transitions were not in it**, and are named rather than left as an implied completion: §2.4
requires anything spatial to be a spring, and a `PageTransitionsBuilder` written on a duration would
satisfy the step number while contradicting the section it comes from. They landed with
`AppPageRoute` below.

Reasoning: `HISTORY.md` — "The ripple dies at the theme" (2026-08-11). A ripple exists only
mid-press and a glow only mid-drag, so this step's verification is a device check with the
performance overlay on, per `design.md` §10.

### A button is a component, and a spring is the substrate under it

`design.md` §11 step 3.

Binding: **a spring never starts from zero.** `SpringDrive.animateTo` is the only way to move one
and always reads the live value and live velocity out of the controller it retargets.
`AnimationController.forward()` is deliberately neither wrapped nor exposed. The drive runs 0 to 1
and the widget lerps off it, because `SpringSimulation` decides it is done against an absolute
`Tolerance`. **The painted height and the tap target are different things** — §5.2 gives `sm` 32h
and §9 makes 48dp pass/fail, and both hold only by separating them; the test taps all four edges
rather than measuring a box. **The focus ring's 4px gutter is reserved always**, because a ring
appearing on focus would reflow the row a keyboard user just tabbed into. It is `focus-visible`,
not `focused`, read from `FocusManager.instance.highlightMode` — the same place `InkResponse` reads
it. The label flexes unconditionally, because Material's own button does. `action.destructive`
exists for the first time here. Six of §5's nine states apply; `error` belongs to `AppTextField`, a
button that may not be used is `disabled` rather than read-only, and there is no empty button.

**`spring.snappy` is underdamped and §2.4 is generous about it.** Measured damping ratios: `snappy`
**0.821**, `smooth` 1.012, `gentle` 1.014, `bouncy` 0.558. No value was changed and none should be
— 1.1% of a press is 0.0003 of scale for one frame — but the ratios are asserted so
"near-critically damped" cannot quietly cover a different spring later. `bouncy` overshoots by 12%,
which is the distinction §6.2's reward layer rests on.

Reasoning: `HISTORY.md` — "`AppButton`, and the spring substrate under it" (2026-08-11).

### Every button is an `AppButton`, and the tier is a decision per site

**A call-site count that greps source without excluding comment lines finds work that does not
exist.** `lib/config.dart` is fully commented out and its only importer is legacy; two successive
wrong figures came from that. Method, not number: exclude comments before counting.

Binding: the **7 remaining sites are `checkout_cart_panel.dart`'s and they are step 7's**, not
skipped — that is where §2.1's rule that *Clear this sale* is destructive and *Save sale* is primary
must be applied. Fifteen call sites hand-rolling §2.1's loading row are `loading:` now, and **the
nulled callback did not come with them**: a null callback renders *disabled*, which says "you may
not do this" over a control whose truth is "this is happening"; `AppButton` suppresses the press
while loading and freezes the width. Where one control has two meanings, the tier is read from the
same expression that already picked the icon and the label. **Pagination stopped being primary** —
§2.1 permits one primary per screen region. Prefer a balanced-paren rewriter over a regex: the
rewriter refused 17 sites it was not sure of, and every one held a decision.

One layout consequence is owned rather than left to be found: a form action inside a stretching
`Column` is now centred at its natural width instead of full width, because `AppButton`
shrink-wraps, and §5.2 describes a padding-sized button.

Reasoning: `HISTORY.md` — "Every remaining button becomes an `AppButton`" (2026-08-11).

### Five statuses, and three components two of which have no specification

`design.md` §11 step 4. `StatusBadge`, `Callout` and `Disclosure` are in `lib/ui/status.dart`, with
`AppStatus` as the five-valued enum §2.1 describes.

**Only `StatusBadge` and `Disclosure` are specified.** `Callout` has a §5.1 row and no measurements,
so it is drawn out of §2 rows that already exist, each named in its own doc comment. Recorded so a
reader does not mistake a borrowed row for a specified one. **Two icon sizes were borrowed and are
open questions** — see "Open decisions".

Binding: the prose inside a callout is `text.secondary`, **not the status colour** — §2.1's rule is
that a status is a container plus an icon plus a word, not that every word inside is tinted. **The
glyphs are the component's decision**: §5.2 makes an icon mandatory and names none, so a default per
status is what stops that requirement being a blank each call site fills differently. A call site may
override it. **Closed means gone from the tree** — a collapsed `Disclosure` renders no part of its
explanation, and the condition is the widget's own flag **and**
`extent <= Tolerance.defaultTolerance.distance`, because keying on `extent == 0` leaves the prose
mounted forever. `SettlingSpringSimulation` was deliberately not wired into `SpringDrive`: that
changes every press spring in the app for an invisible difference. The reveal is `spring.smooth` and
the chevron rotates off the same drive.

Two mappings are decisions rather than lookups: an **inactive** member is `neutral`, not `problem`;
an **unrecognised** reconciliation state is `info`, not `problem`, because a server state this app
does not model is not evidence of anything wrong.

**`ConfirmDialog` left step 4 for step 7**, whose own row names "destructive confirm": it
consolidates four `await`-and-branch call sites and so cannot ship as a visual change.

Reasoning: `HISTORY.md` — "Five statuses, two notices, and prose that folds away" (2026-08-12). A
`Disclosure` is not free at desktop width — at 1440 folding two short paragraphs saves less than the
badge and padding add.

### One field, everywhere - and an audit finding that was false

`design.md` §11 step 3's second half. `AppTextField`, `AppSelect` and the `AppFieldWell` they share
are at **41 call sites across 18 files**. **The only fields left in the migrated tree are the sale
path's two**, and they are step 7's.

Binding: **the error replaces the helper line**, so the field does not change height when it goes
wrong and a form does not reflow under the finger typing into it; asserted as a size equality. The
counter renders only above 80% of the limit and counts **characters**, the unit `maxLength`
enforces. **A field shows focus however it was focused, and a button does not** — a focused field is
*where the keys go*, and on a form with several of them not saying which is receiving the typing is
the failure §9 is about. A validator is supported rather than rewriting the eight `TextFormField`
call sites, and where both a validator message and an explicit error exist the explicit one wins,
because a server's refusal is about the value that was *submitted*. `AppSelect` has no specification
and borrows the field's entirely; its menu takes `radius.md` as the nearest row rather than a fifth
radius being invented. **`hover` is in the harness showing no change, on purpose** — §5.2 specifies
no hover treatment for a field and `claude.md` forbids inventing a token; queued as a question for
the product owner.

**An audit finding that says "nothing exists" is a claim about the whole tree and needs a whole-tree
grep behind it.** `DESIGN-AUDIT.md` §2.2 said there was no `DropdownButtonFormField` in the migrated
tree; there are five, and `AppSelect` had been dropped from §5.1 on that basis. Caught before
anything was built around it and reversed the same session. Both claims are struck through with the
correction rather than deleted.

Reasoning: `HISTORY.md` — "One field, everywhere" (2026-08-12).

### A route arrives on a spring, and one parallax is deliberately missing

`design.md` §11 step 2's fourth part. `AppPageRoute` is a `PageRoute` subclass and all **23**
`MaterialPageRoute` call sites in the migrated tree are now it.

Binding: the SDK supplies the seam — `TransitionRoute.createSimulation({required bool forward})` —
and the pop path hands the result to `AnimationController.animateBackWith`, so the finished route
reaches `dismissed`, `finalizeRoute` runs, and the leak this chunk was scoped around **cannot happen
through this API**. **Interruptibility is a property of when that hook is called**, not of code
written here: `createSimulation` runs before the controller is stopped, so the live value and
velocity are the figures of the transition still in flight. It uses **`SettlingSpringSimulation`**,
because a plain spring parks a page a fraction of a pixel off its own edge for as long as it is on
screen; **`SpringDrive` still uses the plain one on purpose.** Two rows, latched once in `install()`
— a transition changing identity halfway because a window was resized would be worse than either
row. §4.1's `medium` is not named by §6.2 and the literal reading is taken: 768–1023 gets the
compact row. **Reduced motion is a simulation that is already done**, not a shortened duration.
The route reads `MediaQuery` **without depending on it**, because a route is not a widget and the
context it holds is the navigator's.

**Fifteen pushes parallax and eight do not, and both halves are asserted.** `MaterialApp.home`
builds the landing route as a `MaterialPageRoute`, which will not animate out under a route offering
no `delegatedTransition`. The delegated transition was built, worked, and was taken out again
because it cost **an extra Firestore read on every push and every pop**: offering one re-parents the
covered page's subtree, which rebuilds it, which hands `TenantRouteGuard` a fresh `load` closure,
which its identity comparison treats as a reload. `claude.md` hard rule 1 decides it. The day the
coupling closes, the test pinning the boundary fails and gets rewritten in the same change.

**The coupling predates this chunk and is queued below as its own item.** It is a latent defect
either way: any rebuild of those panels, from any cause, already re-queries.

Reasoning: `HISTORY.md` — "A route arrives on a spring" (2026-08-12).

### A category is named, and a document ID is not a name

> **A document ID is not a worse name for a category. It is not a name.**

Binding: **one resolution**, in `lib/tenancy/tenant_catalog.dart` beside `TenantCategory` —
`tenantCategoryNames`, `tenantCategoryLabel`, `tenantCategoryPhrase`. It deliberately disagrees with
`tenantStaffLabel`, which **keeps the UID visible**, because a UID is what every sale, shift and
audit record is attributed by while nothing a person sees refers to a category by its ID. The
unlisted state reads **"Category not listed here"**: two causes arrive there — a business with more
categories than one page, and a category document that cannot be read — and the wording claims
neither. Two wordings for one answer, split by grammar: `tenantCategoryLabel` opens a line,
`tenantCategoryPhrase` sits inside one. The import preview names what the sheet said in three
descending degrees of certainty, and **the ID is not a third degree**. The import's wording is held
with its plan, because a commit re-sends the pages the preview sent. **A recorded decision was
reversed on purpose**: "stating the ID beats stating nothing" now says the opposite in all three
places, per `design.md` §8 rule 1. Reporting was left alone — `SalesTotalsCategoryOptions.nameOf`
with `?? 'one category'` is correct for a filter label.

Reasoning: `HISTORY.md` — "A category is named, and never shown as a document ID" (2026-08-11). The
premise was wrong twice: eight surfaces named a category and every one could state an ID, holding
five copies of the lookup between them.

### A screen title is content, and the toolbar keeps only the way back

`design.md` §11 step **5a** — `AppScaffold` and `PageHeader`. **5b, §4.4's navigation model, is not
in it and stays queued**: it is a behaviour change and needs a device check.

Binding: **the title left the toolbar because §2.2 will not fit in one** — `display` is 32/40 at 700
and no 56-high Material toolbar holds it, so a screen title is a piece of *content*, at `title.lg`
below §4.1's `expanded` floor and `display` at or above it. **`AppBar` was kept rather than
hand-drawn**, because it owns the leading control, the "is there a way back" logic, the safe-area
inset and the toolbar semantics, and redrawing it would move routing behaviour into a visual change.
**The frame costs a route 72 logical pixels of body** — written down rather than discovered, and
attached to the next device run. The tab strip on the platform route sits under the header, because
§7's order is header → callout → filters → content. **Below 768 the primary action drops under the
title**, because a `Row` gives an unflexed action all the width it asks for. The title role is
resolved against the **screen**, not the header's own box, or a `LayoutBuilder` would produce a
fourth breakpoint at 1064 that nobody declared. **`subtitle` and `primaryAction` shipped with no call
site**; `subtitle` gained callers with §7's title chunk.

**Six raw `Scaffold`s remain and every one is named** — ~~seven~~, and **the landing route left this
list on 2026-08-16** when step 5b's first half put it on `AppScaffold`, which was the whole of what
its entry below was waiting for: `checkout_cart_panel.dart` (step 7);
`login_screen.dart` (deliberately a `Scaffold` — no toolbar content, and on a wide window the title
belongs to the form pane); `_RoutingProgress`, `_TenantBootstrapError` and `PlatformRouteUnavailable`
(three full-page states that are `LoadingState`/`ErrorState`/`EmptyState` in §5.1, none of which
exists yet); and `pdf_preview_screen.dart`, which is legacy-adjacent and has no title.

~~**The landing route is out, and not because it is step 5b.** Its title is genuinely undecided: the
toolbar says `membership.tenantName` and `TenantBrandingPanel` resolves `branding.companyName`, **and
the two can differ**. Which is the page's title is a product question.~~ **Answered by the product
owner on 2026-08-16: `branding.companyName`, falling back to `membership.tenantName`.** It was a
product question and it got a product answer; see the v0.5 standing decision for why this is
ratification rather than a new rule, and for the one structural consequence it hands to step 5b.

Reasoning: `HISTORY.md` — "A screen title stops being chrome" (2026-08-12).

### One boundary, one variable, and a maximum width on every page

`design.md` §11 step **6, first half** — §4.1's breakpoints and §4.2's content widths. Split from
§4.3's `RecordList` contract because that half requires inventing a record model and **deciding per
screen what the compact form loses**, which is a product judgement per screen. Same shape
`AppButton` and `AppTextField` both shipped in: the mechanism first, the per-screen judgement
second.

Binding: **one declaration.** `AppLayout` in `lib/ui/tokens.dart` holds §4.1's two floors and §4.2's
three widths; four former mechanisms are gone, and `tokens_test.dart` asserts both floors as
literals. **A band is resolved from a screen width, never from a `BoxConstraints`** — §4.2 now puts
a 1200 cap and 20 of padding between the screen and anything inside it, so a `BoxConstraints` at a
1024 screen finds 984 and draws the compact form on a surface §4.1 calls expanded.
**`AppScaffold.contentWidth` is required rather than defaulted**, because §4.2 gives a form and a
table different maxima and no value is right when a call site says nothing; requiring it puts the
judgement in the diff, one line per screen. **The header and the body are constrained together; the
toolbar is not** — a back arrow drifting inwards would be chrome obeying a content rule.
`AppContentWidth.full` adds **no widget** rather than an unbounded one. Nothing overrides the layout
contract per subtree, unlike density: §3 says density is chosen by the screen, while §4.1 and §4.2
state ranges no screen is entitled to disagree with.

Two of the four rewired declarations sat in step 7's and step 9's files. §4.1 names both files as
part of its own rewiring; each edit was one expression and neither file's visual design was touched.
**Sanctioned rather than smuggled** — the same latitude is not general.

Reasoning: `HISTORY.md` — "Every page gets a maximum width, and 768 stops being declared three
times" (2026-08-12).

### One record model, three renderings, and the loss the caller owns

`design.md` §11 step **6, second half** — §4.3's responsive contract as `RecordList` in
`lib/ui/record_list.dart`.

Binding: **the model is §5.2's five rows and nothing else** — identity, optional `RecordStatus`,
`RecordAttribute` list, provenance, `RecordAction` list. **§4.3's opt-out is conceded in writing and
is per attribute** (`RecordAttribute.inNarrowForm`), with the limit stated: identity, status,
provenance and actions are on every rendering at every band, and **the form is never the caller's**.
**Columns are a property of the list, not of its first record** — `columnsOf` is the ordered union
of every label any record carries, and a silent record gets an **empty cell, not a dash**, because a
dash is a value. Two readings of §5.2 went into the document as well as the code: *status — leading
position* means first **in the record**, and *never truncated below two lines* is a **floor**.
§4.3's `(>3)` is honoured: three or fewer actions are inline at every band; past three, compact
takes an overflow menu, medium keeps three, expanded draws them all. **Every action is
`AppButtonSize.lg` in every form** — this component resolves no density and a 1024-wide surface may
be a touchscreen till. **An ordinary audit event carries no status**: a list where every row wears a
badge is a list with no signal in it. `RecordItem.details` is the component's own addition, named as
such in its doc comment rather than written into `design.md`; it is drawn **at every band**, and in
a table it takes the whole row beneath the cells.

The three column shares were the component's first guess, measured at 1200 against a two-column
list, and are now ceilings rather than answers — see "A column asks for what it holds" below.

Reasoning: `HISTORY.md` — "A record list becomes one component, and §4.3's middle band gets its
first picture" (2026-08-13). It found a `StatusBadge` defect unreachable before it: the badge
declared `maxLines: 1` and could honour neither that nor `ellipsis`, because its `Row` sits at
`MainAxisSize.min`.

### The staff directory stops choosing its own form, and a record gets a form slot

The first screen of step 6's sweep. `TenantRecordCard`, `TenantRecordTable`, `TenantTableColumn`,
`TenantTableRow` and `TenantStatusChip` are **deleted** — this was the last consumer of all five.
`TenantInitialsAvatar` survives because the till uses it.

Binding: **a record carries one standing, and this screen showed two badges.** Membership status is
the `RecordStatus`, because it is the one that decides what a person can do; the invitation state
became a **`RecordAttribute`** — §5.2's key-value row — which is where a fact that is not one of
§2.1's five belongs. **The initials block is gone**: §5.2 names no leading row, and an avatar slot
for one caller would be inventing a specification row. **The action order is inherited, so which
action a narrow band hides is inherited too** — reordering is a product decision, and this was a
restyle. "Cancel invitation" and "Deactivate" are destructive; "Activate" is not. The state-clearing
toggle stays **per form**.

`Pagination` was examined and declined here and three times after: this screen's pagination is one
sentence rather than one of `DESIGN-AUDIT.md` §2.3's four idioms, and where it *is* one of the four,
`Pagination` is §5.1 priority 3 and not step 6's.

Reasoning: `HISTORY.md` — "The staff directory becomes a `RecordList`, and a record gets somewhere
to open a form" (2026-08-13). It found a step-3-era overflow: five inline forms ended in a `Row` of
two 48-high buttons that had only ever been driven at full-card width.

### A product states its facts as facts, and only one that cannot be sold has a standing

The second and third screens of step 6's sweep — the read-only catalog (17) and manage catalog (18).
**These are the two screens §5.2 wrote its catalog example against, and the example is now false of
them**: both drew a product as four facts in one bullet-separated subtitle.

Binding: **the category is the record's `subtitle`, not an attribute** — §5.2's identity row admits
"an address, a code, a category", and the deciding case is that an unlisted category reads
*"Category: Category not listed here"* as an attribute and simply *"Category not listed here"* as a
subtitle. **Only a product that cannot be sold carries a standing**; the silence on every other
product is the activity log's rule. **A negative quantity is out of stock rather than a fourth
status**, and the figure is still stated beside the badge. One definition of both, as
`tenantProductStanding` and `tenantProductAttributes` beside `TenantProduct`. **Nothing is marked out
of the narrow form** — `inNarrowForm` drops a fact rather than shortening one, so a tidier card would
cost a shopkeeper the code they scan by. The `Code` column takes twice an ordinary share through
`RecordAttribute.flex`. **Opening a product's stock is a control now**, a `RecordAction` rather than
a whole-row `ListTile.onTap`; what decides whether it is offered is unchanged. `details` has no
consumer here, because turning the edit dialog into an inline form would be a behaviour change.

**One prefix with two owners is a defect a passing test can hide.** The "In stock" value key and the
"View stock" action key collided; the test asserting the action is *absent* for a cashier is what
caught it, because a collision only shows where the two are expected to disagree.

Reasoning: `HISTORY.md` — "The catalog becomes a `RecordList`, and a product that cannot be sold says
so" (2026-08-13).

### One ledger entry, one vocabulary, and a screen that had three

The fourth to seventh screens of step 6's sweep — product stock (21), stock corrections (22), stock
movements (23), one product ledger (24). **The file written to prevent this exact drift had never
reached the screen that had it**: `stock_movement_labels.dart` says two copies of a sentence is two
chances to change one and not the other, and screen 21 was a third copy while screen 22 was a fourth
surface nobody had noticed was the same shape.

Binding: **what is shared is the whole `RecordItem`, not the strings inside it.** The labels file
exports `stockMovementRecord` and `stockAdjustmentRecord`, and the four screens differ in exactly
two things — `subtitle` and `actions`. **No record carries a status**, by the activity log's rule.
The typed adjustment category is an **attribute**, not part of the identity. **A reason and a source
are two columns**, not one precedence-based line, or one document files under different columns
depending on which screen drew it. Screen 23's product ID and the control that opens its ledger are
**two things with two keys**: the ID is the `subtitle`, `Open ledger` is a `RecordAction` at 48dp
offered only when the route was injected.

Screen 21's exception report was deliberately left for the step-4 sweep: §5.2 has no row for prose,
and turning four paragraphs into key-value attributes rewrites what the screen says rather than what
shape it says it in.

**`dart format` is not safe to run over a whole file in this repository.** At `HEAD`,
`dart format --set-exit-if-changed lib test` reports 201 of 322 files would change — the tree was
written against an older formatter — so formatting a file rewrites regions a chunk never touched and
strips a UTF-8 BOM in two files. **Format the lines you write, not the file they are in.**

Reasoning: `HISTORY.md` — "The stock family becomes one record, and a screen stops describing it
three ways" (2026-08-13).

### A shift has a standing, and two paragraphs were never about a record

The eighth to eleventh screens of step 6's sweep and its last — shift corrections (30), shift history
(32), shift sales (33), returns on a sale (34). **`design.md` §11 step 6 is finished with it.**

Binding: **a shift carries a standing** — `ok` where the drawer agrees with the sales, `problem`
where it does not, `attention` where the shift closed with no summary; "closed" is not the standing,
because every shift on that page is closed. The amount stays an attribute, so **no figure is ever
carried by a badge**. A return's standing is pending/verified. **A correction and a sale carry
none**: what varies across a page of sales is whether *this device* has seen the server confirm one,
and every surface states that in a provenance line. **A sentence naming whichever of two figures
moved cannot be a column** — they are two columns, and the figure that did not move says
**`Unchanged`** rather than leaving an empty cell that would read as a figure nobody recorded.
Screen 30's `Difference` is one column holding up to four sentences, deliberately: four columns to
say one thing would leave two empty on nearly every record. **Three page-invariant paragraphs left
the record for the page** — a claim about how the system works is not a fact about a record, however
many records raise it. **`Verify and restore stock` stops being primary**, because `RecordActionSet`
draws every action `secondary` unless destructive and §2.1 gives `action.primary` to one per screen
region. **A count under a heading never has to agree**: §5.2 makes the noun the key, so the
singular-plural rule stops reaching the figure.

The payment caution's move to the page was decided by the first render rather than by argument: the
contract in `sale_history.dart` is per *surface*, and a single-sale screen keeps the sentence beside
the value because there the two are the same thing.

Reasoning: `HISTORY.md` — "The shift family becomes a `RecordList`, and step 6's sweep is finished"
(2026-08-13).

### A notice does not fold, a helper does, and four surfaces stopped wording one document two ways

`design.md` §11 **step 4's sweep**, first part — the four reconciliation surfaces: the day page (27),
the one-run page (29), the differences list (28) and screen 21's exception report.

Binding, and it is family-wide: **§5.1 splits the two components by what the prose is for.** A
permanent **helper** paragraph — always the same, true of every record the screen will ever show,
read once — is a `Disclosure` and folds. A permanent **notice** — about the state of this page, this
read, this role — is a `Callout` and does not. The one judgement in applying it is screen 27's
`reconciliation-request-scope`, a `Callout` **because** it decides whether pressing the button below
does what the person thinks it does, and a sentence you have to open is a sentence nobody reads.

**A recorded difference has no §2.1 standing; a run has one.** Every record on all four surfaces is
a difference found, so a badge on each is the no-signal case. A page of runs genuinely mixes `ok`,
`attention` and `problem`. `failed` and `quarantined` are both `problem`, separated by a detail line
that is **the enum's own label, shown only where it says more than the badge's word**. Screen 21's
unreadable difference read is **`info`, not `problem`**, because the same sentence covers a read that
fails *or is refused*, and calling a permission boundary a fault would invent in colour an answer the
code refuses to invent in words.

`lib/reporting/reconciliation_labels.dart` is the family vocabulary, on the model of
`stock_movement_labels.dart`. **What a screen can *do* about a record stayed at the call site** —
`_resolutionNote` names a form three inches down one page — while the kind, the subject, the figures
and the provenance are shared. What a difference *is* is the same everywhere.

Screen 28's cards stay cards: 28 is **not one of the twelve screens step 6 names**, and migrating it
would be step 6 work outside step 6's list.

Reasoning: `HISTORY.md` — "The reconciliation family gets one vocabulary, and step 4's sweep begins"
(2026-08-14).

### A page's standing is a status, and a report row's reads the mode it was written in

`design.md` §11 **step 4's sweep**, second part — the four catalog surfaces: read-only catalog (17),
manage catalog (18), the correction dialog (19), bulk changes and import (20).

Binding: **screen 17 was stating one fact twice and rendering it as neither** — a `headlineSmall`
title and, a page below, an uncontained paragraph. §2.1's row for `info` is *"offline, read-only,
informational"*, so `Callout.title` supplies the word and the paragraph is the message. **Six of the
family's seven notices are `info` and the seventh is `problem`, and the split is what the sentences
claim rather than how they feel**: the six say what *this build* or *this role* cannot do; the
seventh is a stopped bulk chain, and `ambiguous` is deliberately included in it because an unknown
outcome is not `attention`'s "awaiting" — nothing further is coming. **A bulk report's row status
reads the report's mode**: `unchanged` is `neutral`, `failed` is `problem`, and `created`/`updated`
are **`attention` in a preview and `ok` in a commit**, because a green badge over a report whose own
first sentence is `Nothing has been written.` would state the opposite of the line above it. What the
badge cannot fix is the word beside it — the four labels read as past tense, so a previewed row says
`Created` before anything exists. **That is a copy question and it is queued, not decided.**

**No pagination line became a `Callout`**: "More products are available." states a property of the
pager rather than something a person can or cannot do, and sits directly under the list it qualifies,
which is §5.2's helper-text position.

Screen 20's report cards stay cards, for the reason 28's did.

Reasoning: `HISTORY.md` — "The catalog family folds its prose, and a bulk report gets its first
picture" (2026-08-14).

### A figure is a component, and a row of them measures what it holds

`design.md` §11 step 8, first half. `lib/ui/stats.dart` holds `StatTile`, `StatRow` and `StatLine`;
`TenantStatCard` and `TenantStatStrip` are deleted, and `lib/ui/records.dart` is down to
`TenantInitialsAvatar`, which is the till's and therefore step 7's.

**Only `StatTile` is in §5.1's inventory**, and `StatLine` is in neither §5.1 nor §5.2 — admitted on
the precedent `RecordItem.details` set, and labelled the same way. All three are built from named §2
rows, because §5.2 covers five components and none of these is among them.

Binding: **a stat tile is for "the one figure a stat tile exists for", and §2.2's own words are the
test** — `numeric.hero` has exactly one use in the document and `numeric.body` is "money and counts
in flow". Screen 26 gets tiles; screen 25 lists seven days and gets `StatLine`s. **The minimum tile
width is measured rather than declared**: `StatRow.minimumTileWidth` lays every figure out with a
`TextPainter` at `numeric.hero` and takes the widest plus the tile's own padding — no constant, no
caller knob, nothing invented, no figure ellipsised. **The caption is sentence case, which closes the
last uppercase surface in `lib/`**; `label.eyebrow`'s only readers now are the harness's section
headings. **A figure with a standing wears a badge; a figure without one wears nothing** — the raw
`Color` a caller used to pass was a hardcoded value *and* colour-alone signalling, and a badge on a
*count* of records that each already wear one is the same signal twice. **A run of tiles is a `Row`
inside an `IntrinsicHeight`, not a `Wrap`**, or a tile carrying a badge stands taller than its
neighbour.

**The note under the profit statement did not fold.** The rule that widget exists to keep is that no
profit figure is rendered without, in the same block, what is known about the cost data behind it,
and a `Disclosure` would make the qualification optional to read. **The tender disclaimer is the
same exception**: permanent and page-invariant, and a visible `Callout` anyway, because
`checkout_tender.dart` requires every surface showing a tender to carry it.

`design.md` §2.2 was amended: its ragged-figures example was false of these screens, and the
retraction says what was actually wrong — not the numerals, but that the figures were *inside
sentences*.

Reasoning: `HISTORY.md` — "A figure becomes a component, and the money screens stop writing numbers
into sentences" (2026-08-14).

### A figure is evidence on these three, and one document is read two ways on purpose

`design.md` §11 step 8, second half, **and it finishes step 8** — screens 27, 28 and 29.

Binding: **these three state quantities as evidence**, which is a column of comparable numbers and
therefore `numeric.body` and a shared right edge, where 25 and 26 answer one question with one figure
and took `numeric.hero`. **Screen 29 gets no `StatTile` row**, because every one of those counts is
already stated by `TenantReconciliationRunCard`, which 29 shares with 27 so two routes cannot
describe one run differently; a tile row would print one figure at 28px and again at 14px a
centimetre below. **One difference is rendered two ways on purpose, and both live in one `switch`**:
`reconciliation_labels.dart` declares each kind's reading once as a private `_DifferenceReading` —
sentence, prose-without-figures, figures — and the test asserts every figure's magnitude also appears
in that kind's sentence. **This is the one thing in the chunk that could rot**, and the guard is why
it is written down. **A variance states its direction twice**, by sign and by word, which is §9's
never-colour-alone rule in another form. **A revision is not a figure** and `_published` stayed a
sentence: §2.2's numeric roles are for money and counts, and nothing about a generation marker is
worth comparing by magnitude. **A figure label is a column heading and is never inflected.**

The three panels moved onto the token layer while they were open — they were the last reporting
surfaces reading `Theme.of(context).textTheme` and padding with bare integers.

Reasoning: `HISTORY.md` — "A difference states its figures, and step 8 is finished" (2026-08-15).

### A notice says which answer it is, and four of them were never refusals

A model chunk rather than a step: `lib/ui/status.dart` gains `AppNotice`, and the surfaces that
reported what a write had just done stopped carrying a `String?` whose meaning was in the sentence.

Binding: **the four named constructors are the four outcomes this app's write boundaries already
model.** `TenantCatalogWriteKind` is literally `committed / rejected / ambiguous / unavailable`, and
`AppNotice.confirmed`, `.refused`, `.unknown` and `.offline` map to §2.1's `ok`, `problem`,
`attention` and `info` **once, here**, so a call site names *what happened* and never picks a colour.
**There is deliberately no constructor for `neutral`**: §2.1 gives it "archived, retired, closed",
which is a standing a *record* has and never a page reporting on a write. **Every `ambiguous` branch
is `attention` rather than `problem`** — nothing is known to have failed, and painting it red reports
a failure the app has no evidence of. **Four branches were never refusals**:
`TenantProductUpdateFailure.unchanged`, `product_unchanged`, `currency_unchanged` and
`TenantReturnVerificationFailure.alreadyVerified` all say *what you asked for is already true*, and
are `info`. A surface with no success branch at all carries an `AppNotice` anyway, because the type
states that invariant where a `String?` left it to be traced through the assignments.
`test/support/notices.dart` is **not** a migration seam like `buttons.dart` and `fields.dart` — it
reads the destination.

**The grep that finds these is `grep -n "\-notice'" lib`.** It found seven where this file listed
four, and missed sign-in's `login-error`, since renamed `login-notice` so the next run finds it.
`checkout-code-notice` in `checkout_cart_panel.dart` stays excluded with the rest of step 7.

Reasoning: `HISTORY.md` — "A notice says which answer it is, and four of them were never refusals"
(2026-08-15). All 225 images were byte-identical, because no capture case performs a write — the
"invisible in every capture" trap, structural rather than a narrow fixture.

### A title appears once, and the page that said it was read-only was not

It closes §7's own named defect: *"several screens render the title in the app bar and again as an
`H1` directly beneath it"*. **The check is `grep -n headlineSmall lib`**, which returns two live uses
now, both deliberate, where step 8 left thirteen — the entry carries the grep rather than a number,
because this file has under-counted four queued lists from memory in three days.

Binding: **moving a string the screen already draws is not a copy decision**, where *rewriting* a
title into a title-and-subtitle pair is and remains step 11's. So: if the in-body heading equals what
the `AppScaffold` title says, it goes; if it names *which* record the route is showing, it becomes
`PageHeader.subtitle`; and the noun goes with it, because `Reconciliation run` over `rj_000001` is
what the header already says.

**The staff directory's heading was also saying something false** — `Read-only staff directory`
unconditionally, over a page offering `Invite staff` two lines below. A page's standing is §2.1's
rather than a heading's, so it is an `info` `Callout` shown only when the session can neither invite
nor edit. **Screen 24's heading stays and is not a duplicate**: the product *name* only exists after
the guarded load inside the panel, so reaching it is structure rather than a title fix, and it is
commented at the site.

Reasoning: `HISTORY.md` — "A title appears once, and one page was telling everybody it was read-only"
(2026-08-15). Two observations it did not act on are in "Open decisions": a subtitle carrying a record
ID is drawn at the body role where §2.2 says identifiers are `mono`, and the membership badges read
`active`/`pending` in the enum's own wire case.

### A column asks for what it holds, and a share is a guess about content

The four `RecordList` column-arithmetic observations, taken as one chunk because they are one defect
seen from four directions. Step 6b divided a table row with four constants measured at 1200 against a
**two-column** activity log; the twelve screens that followed carry two to six columns. The mechanism
is `RecordTableColumns` in `lib/ui/record_list.dart`.

Binding: **every column states a demand** — the widest badge, the widest inline action set, the
longest value, and in every case at least its own header, because a column narrower than its heading
would ellipsise the heading. **A demand is capped at the column's old share**, so the first pass
always fits and nothing can overflow at any width; the four constants are **ceilings now, not
answers**. **What nobody claimed fills the shallowest unmet need first** — proportion is the obvious
rule and the wrong one, because a column 6 pixels short and one 400 short are not two claims of the
same kind. **The identity takes what is left over** and is the only column ever given more than it
asked for. A title asks for half its width; the subtitle and provenance are `maxLines: 1` and ask for
all of theirs. **A component answers for its own geometry** — `StatusBadge.measureWidth` and
`AppButton.measureWidth`, rather than the table reassembling §5.2's padding rules. `space.12` between
adjacent cells; `design.md` asked for no gutter and now records one.

**The actions column is deliberately *not* sized to the widest set**, which is the obvious intrinsic
answer: four of the staff directory's five rows carry two actions, so a column sized for the fifth
would be 380 pixels of nothing on 80% of the table. A tall row on one record is a smaller cost than an
empty column on all of them.

Two findings that only came from asserting a measurement against a rendering: **a button is 8 pixels
wider than §5.2's arithmetic**, because `PressSurface` reserves the ring's width and offset on every
side whether visible or not; and **every `Text` in this app is painted 0.25px per character wider than
its token style says**, because a style with `inherit: true` merges onto a `ThemeData` carrying
Material's `letterSpacing: 0.25`. Every measurement here takes the ambient style as an argument. **The
theme half is a finding and not a repair** — see "Open decisions".

Reasoning: `HISTORY.md` — "A table stops guessing how wide its columns are" (2026-08-15).

### A boundary is a measurement, and the front door had a second palette

`design.md` §11 step **9**, sign-in. **It was one screen rather than the eight §11 lists**: screens
02–07 are phases of `tenant_routing_shell.dart` and were swept with everything else, and screen 08 is
one of the three full-page states §5.1 names and none of which exists.

Binding: **it is a `Scaffold` with a `PageHeader`, not an `AppScaffold`.** Sign-in has nothing for a
toolbar, so `AppScaffold` would draw 56 pixels of empty chrome; the decisive half is that on a wide
window this screen is two panes and **the title belongs to the form**, not to a header spanning a form
and a keypad. **Whether the keypad appears is a measurement, and it replaces a breakpoint.** The screen
used to ask §4.1 whether the window was 768 wide; what it needs to know is whether half the window
holds ten keys at §9's 48dp target. It did not — at 768 that was 24 pixels of slot each and 13 painted.
`PosKeyboard.minimumWidth` is **632**, so the keypad shows at **1264** and above. **A screen consulting
one variable is not the same as a screen asking the right question.** **A keypad key is not an
`AppButton`**, because §5.2's own minimum horizontal padding plus the ring gutter leaves nothing for
the character at §9's 48-wide minimum; the key draws itself out of the same §2 rows and invents no
token. **A defect this screen found itself sits on the field it is about; a provider answer sits in the
page notice.** **`Enter` is drawn disabled because it does nothing** — its handler has been an empty
branch since the file was written, and wiring it is a behaviour change `claude.md` hard rule 1 keeps
out of a visual step.

**The double border is closed, and the mechanism is worth keeping.** `PillInput` set
`border: InputBorder.none`, which was correct and stopped being sufficient the day `spiritTheme`
gained `enabledBorder`, `focusedBorder` and `filled: true` — `InputDecorator` prefers the specific
slots over `border`. `AppFieldWell` strips all six and sets `filled: false`, and a test pumps the
screen **under the real theme** rather than a bare one and asserts every slot.

**A glyph outside the Latin ranges is an asset, not a character, and it needs a picture before it
ships.** `⌫` is U+232B, Roboto does not carry it, and the first picture of the new keypad showed an
empty rectangle where the key's entire face should be. It is `Icons.backspace_outlined` with a
semantic label now. Same defect as the bulk report's before/after arrow, one step worse.

**Three widget files are dead and nothing imports them**: `pill_input.dart`, `pill_button.dart`,
`glass_card.dart`. Deleting them was refused by the session's tool permissions, so they are named here
and in the exclusions rather than quietly left.

Reasoning: `HISTORY.md` — "The front door stops having a palette of its own" (2026-08-15).

### An input is a pill again, and the specification moved first

**`design.md` v0.4**, taken at the product owner's direction rather than as a migration step. **The
specification changed before the code did, which is `design.md` §0's own order of operations and the
only reason this was a chunk rather than a patch.**

Binding: **§2.1 gains `surface.field` `#1E3A2B` and `surface.sunken` loses the input well**, keeping
the table header and the code block, which genuinely are recessed. No new hex — `#1E3A2B` is
`green.700`, so v0.4 added a *role*. It collides with `border.subtle` by value, deliberately and
named: they never meet, because a field well is bounded by `border.strong`. **A field is the lightest
surface in the set**, so the ordering runs `sunken` → `base` → `raised` → `overlay` → `field`, and
`tokens_test.dart` walks the five in order. **§2.3's pill stops being buttons-only**, and what it costs
is written into §2.3 rather than discovered: a button and a field share an outline, and what keeps them
apart is the action tier's fill, the field's persistent label, and the field's left-aligned content —
**if those stop being enough the honest fix is to take the amendment back, not to add a fourth
distinction**. **§5.2's leading icon is optional in the strong sense**: 17 of 41 fields carry one and
24 decline it, because a glyph that does not narrow what a field is for is noise. **The focus glow is
back and §9's ring is still in front of it** — both are drawn, and the test asserts the pairing rather
than the glow; §2.1 gains its only permitted shadow, on the grounds that a focus glow is an interaction
state and not depth. **The placeholder moved to `text.secondary`, and that one is arithmetic**:
`text.tertiary` measures **4.29:1** on `surface.field` against §9's 4.5 floor, asserted at the figure
rather than at a floor so a later session that "restores" it fails a test that says why. Helper text is
untouched, because it sits outside the well. **The 1px `border.strong` stays** because §5.2 switches the
border to `status.problem.border` on error, and a well with no border has no error border.
**`inputDecorationTheme` moved with it**, which `AppFieldWell` does not reach — what still reads it is
the sale path's two unmigrated `TextField`s and the legacy island — and its `hintStyle` had to move or
it would have vanished into the new fill.

**The keypad has a caps lock, and it fixes something as well as adding something.** Every letter key
used to insert its upper-case identifier, so this keypad typed `OWNER@EXAMPLE.COM` and could **not type
a lower-case password at all**. Off is the default; `Caps` latches; the key faces change with it.
**`Caps` is one flex unit and an icon, forced by arithmetic** — a labelled `Caps` needs two, which would
make the `Z` row 11 and narrow every key below §9's 48 — and `PosKeyboard.columns` is now **measured
over `rows`** rather than hardcoded to 10, so the next key added widens the pane instead of silently
shrinking every key. **A latched key is §2.1's `primary` tier**, the one tier that fills its container,
and its announcement reads `Caps, on`.

Reasoning: `HISTORY.md` — "An input is a pill again, and a keypad learns lower case" (2026-08-15).

### Built, tested, and still unreachable

| Capability | State |
| --- | --- |
| `requestPasswordReset` | **Blocked on App Check.** Still no caller — see below. The *worker* behind it is a different sentence and is no longer untested: `deliverPasswordReset`'s dependencies run against real Auth and real Firestore as of 2026-08-08. What keeps this row here is the client surface, which is what the decision blocks. |
| Subscription | `TenantPaths.currentSubscription` and rules exist; **nothing reads it and nothing writes it**. `grep -i subscription functions/src` finds nothing at all, so there is no schema to model. Start on the server, not in Flutter. |
| Category rename and delete | Permitted by `allow create, update, delete` on `categories` to owner/admin/manager, and offered to nobody. Deliberate, for the orphaning reason above; recorded here so the gap between rule and surface stays a decision. |

Checkout configuration writing left this table on 2026-08-07. The route is
`TenantCheckoutConfigurationScreen`, offered as "Checkout settings" to owner and
administrator, and it merges `configuration/checkout` rather than replacing it so a
setting a later build adds cannot be deleted by this one.

Catalog management left it the same day, and took the "Catalog management" row with
it. The route is `TenantCatalogManagementScreen`, offered as "Manage catalog", and as
of 2026-08-08 it covers all three halves: create, correct, and retire.

**`updateProduct` entered this table on 2026-08-07 and left it on 2026-08-08**, which
is exactly the life a row here is supposed to have. It was the *good* kind of entry:
unreachable for one bounded reason, with the reason queued, and it stayed for one day.

**`updateProducts` and `importProducts` both entered on 2026-08-08 and both left the same
day**, and they left together because they wanted one screen. That screen is
`TenantBulkCatalogScreen`.

**Product cost and profit left this table in the profit-display session of 2026-08-08**, and it
is the row that had been here longest with nothing but effort in front of it. Its first half closed
on 2026-08-07, when a product gained a cost and a sale began freezing it onto its line; the
second closed when the daily summary and the sales totals started reporting it. What that
chunk had to decide was not how to display a number but **when a number may be displayed at
all** — see the standing decision above. **Every row left here is once again blocked on a
decision, a schema, or a deliberate refusal**, which is the state this table is supposed to
be in, and the three rows that were waiting on effort alone all left within one day of each
other.

**Two consecutive server chunks ending here was the limit, it was named, and the next chunk
was the surface rather than a third callable.** That is the mechanism working: a third would
have meant a growing pile of callables no person can reach, which is the failure mode this
table exists to make visible.

### The home is cards below 1024 and a side menu above it, and the till is pushed

`design.md` **v0.5** replaced §4.4 on 2026-08-16. The rules that now bind:

- **Navigation is `HomeNavigation`, one component with two renderings.** Card grid below 1024 — two
  columns to 768, three to 1023 — and a persistent side menu at 1024 and above. **No overflow
  bucket at any band**, which is the property the model exists to hold; four destinations could not
  carry eleven controls without one, and it would have been the largest destination in the app.
- **The home is the root route at every band.** At `expanded` it keeps its content and loses its
  cards. Landing a role on a default section is a routing condition and is not permitted here.
- **The side menu belongs to `AppScaffold`, never to a nested `Navigator`.** That is what keeps this
  step visual and keeps `Navigator.pop` meaning what it means. It is `AppScaffold.navigation`, a
  `List<HomeDestination>` and not a `Widget` slot: the frame owns the column's width, its band and
  its scroll, and a widget slot would let a call site put anything in a 256-wide column beside every
  page.
- **The menu draws on the home and on no other route**, which is where §4.4's own text and the code
  part company. A menu press is a `push`, so a menu on a pushed route grows the stack a route per
  press — and the two repairs are the two things forbidden here: a nested `Navigator`, and popping
  to the home before pushing, which is a routing condition. **Do not add it to another route without
  answering the open decision below first.** The slot is on all 26 call sites and empty at 25.
- **The two navigation renderings have two hosts, and the constructor names which.**
  `HomeNavigation.cards` is the page's and draws nothing at `expanded`; `HomeNavigation.menu` is the
  frame's and draws nothing below it. The band still owns the form; the pair is exhaustive and
  disjoint at every width, and a change that lets both draw at one width puts the destinations on
  screen twice.
- **§4.2's maximum is measured against what is left after the menu**, not against the window. The
  column costs `AppScaffold.horizontalInset + HomeNavigation.menuWidth` = 276, so a records page in
  a 1440 window is 1164 and 1200 does not fire. The menu itself is outside the maximum, like the
  toolbar.
- **Destinations are ordered by frequency with the two account controls last**, in the list the
  route builds — source order is what both renderings draw. `tool/screenshots/home_navigation_test.dart`
  carries the same order, and the two must not drift.
- **The till is pushed, never mounted.** An unsaved cart is in-memory only, so a mounted till would
  make its survival depend on `IndexedStack` keep-alive. Do not make any home destination a mounted
  tab without making the cart durable first.
- **A card states its own condition.** A card carrying no state is a button, and eleven buttons is
  what §4.4 opened by objecting to.
- **The home's title is `branding.companyName`, falling back to `membership.tenantName`.** The route
  resolves the document above its own header; `TenantBrandingPanel` does not draw the name and does
  not load it.
- **`HomeNavigation`'s menu width is 256** — a component decision on §2.3's scale, in the same
  position as `AppScaffold.horizontalInset` and open for the same reason: no section states a
  navigation column's width.

**Still unanswered, and no chunk should invent them**: `AppTabs` is §5.1 priority 3 and unbuilt, and
the mockups' Money strip needs it; the top bar's shop switcher and queue badge are two extensions
`PageHeader` does not have; and **whether a navigation column has a `selected` state**, which nobody
has asked and which becomes real the moment the menu draws on a route it could point at.
`HomeNavigation`'s §5.1 inventory row went in on 2026-08-16 and is no longer on this list.

Reasoning, the mockups, the cart evidence and the two layout defects the screenshots caught:
`HISTORY.md` — "The home stops being eleven identical pills" (2026-08-16). The frame slot, the three
layout questions it answered and the argument for the home-only menu: `HISTORY.md` — "The menu
leaves the page and becomes the frame's" (2026-08-16).

---

## Open decisions

### §4.4 wants the side menu on every route, and every route reaches it by a push

**The question, in one line: should a destination pressed from a pushed route push again, or replace
the stack back to the home?** Nothing else about the menu is open.

§4.4 says the menu "renders on each one without routing moving and `Navigator.pop` keeps meaning
what it means". The first half of that is buildable and is built — `AppScaffold.navigation` is on
all 26 call sites. **The second half is not true of a push-based app.** Every destination this app
offers is a `Navigator.push`, so a live menu on a pushed route means pressing three destinations
leaves the back arrow three routes deep, in a model whose whole promise is that a person is
*switching sections*; and pressing the destination for the route already on screen opens a second
copy of it.

**Three answers, and only the product owner can pick.**

1. **The menu stays on the home only.** What ships. Costs a desktop the persistence §4.4 asked for:
   open a section and the navigation disappears until you go back.
2. **`pushAndRemoveUntil` back to the home, then push.** Gives §4.4 exactly what it describes and
   keeps the stack one deep, at the price of a real question nobody has answered — whether a screen
   reached from the menu should have a way *back* at all, or only a way home. It is a **routing
   change**, so it is not a visual chunk and `claude.md` hard rule 1 keeps it out of one.
3. **A nested `Navigator` under the menu.** §4.4 forbids it by name, and the reason it gives is the
   right one: it buys persistence by making navigation a behaviour change.

**Two facts whoever answers this should not have to rediscover.** `MaterialApp(home:
TenantRoutingShell(...))` puts the shell below the root navigator, so an `InheritedWidget` there is
invisible to a pushed route — which is why `TenantSessionScope` is re-provided 27 times across 14
files. And **the reach problem is the cheap half**: carrying destinations to a pushed route is
mechanical, and it delivers answer 2's layout with answer 1's routing, which is the worst of the
three.

Blocks nothing today. It blocks calling §4.4 implemented in step 12, and it should be answered
before anything else is added to the top bar, because a shop switcher and a queue badge land in the
same frame. Reasoning and evidence: `HISTORY.md` — "The menu leaves the page and becomes the
frame's" (2026-08-16).

### Public password reset needs App Check, which this app has none of

`requestPasswordReset` is declared `enforceAppCheck: true` **and** calls
`requireAppCheckedPublic`, which throws `failed-precondition` when `request.app` is
absent. There is no `firebase_app_check` dependency in `pubspec.yaml` and no
initialization, so the callable would reject every request the client could make.
Signing in first is no workaround: reset is a *public* endpoint used by someone who
cannot authenticate, so unlike every other callable it has no authenticated
fallback.

The harder half is Windows. Built-in App Check providers cover Apple, Android, and
web only, and the spec already records Windows relying on authentication until a
tested custom provider exists. A public endpoint has no authentication to rely on,
so **in-app password reset is structurally unreachable on Windows** — the platform
the whole Hive offline design exists for. Three ways out, none obviously right:

1. Add `firebase_app_check` and offer reset on Apple, Android, and web only, telling
   a Windows user to reset elsewhere. Cheapest; leaves the primary POS platform
   without recovery.
2. Implement the custom Windows provider the spec anticipates. Most faithful, by far
   the most work.
3. Relax the endpoint to accept an unattested request under different rate limiting.
   ~~Weakens a deliberate enumeration boundary~~ — **corrected 2026-08-07: that is not
   the exposure.** Enumeration is already closed by design, because the response is a
   constant `{accepted: true}` whatever happens and plaintext never reaches Firestore.
   What an unattested public endpoint actually risks is **abuse volume**: anyone can
   drive the Brevo sender domain to mail arbitrary addresses, and that domain is shared
   with staff invitations, its SPF/DKIM/DMARC records, and the suppression list. So the
   damage is sender reputation and cost, not disclosure. A smaller risk than this file
   claimed, landing on the one system never exercised live. Still not casual.

Until this is decided, a user who forgets their password has no in-app recovery on
any platform.

**Started in the console on 2026-08-07, and the "structurally unreachable" claim above
now needs re-checking before it is relied on.** The product owner opened App Check in
the Firebase console. Two repository facts bear on it and neither was recorded before:

- **`firebase_app_check` lists Windows among its supported platforms** as of 0.4.6 on
  pub.dev. That is *plugin* support and is **not** the same as a built-in attestation
  provider existing for Windows — the three built-ins are still Play Integrity, App
  Attest/DeviceCheck, and reCAPTCHA Enterprise. Check what a Windows build can
  actually attest with before treating option 2 as "by far the most work"; it may have
  become much cheaper, or it may resolve to the debug provider only, which is not a
  production answer. **Do not restate the structural claim either way without
  checking.**
- **The Windows app is registered as a web app.** `DefaultFirebaseOptions.windows` in
  `lib/firebase_options.dart` carries a `1:...:web:...` app ID, because Firebase has no
  native Windows app type. Whatever provider Windows ends up using, it is attesting
  against a web app registration, which is the thing to reconcile with the console's
  per-app provider settings.

**Nothing in the client sends an App Check token today**, so console enforcement must
stay off for Firestore, Auth, Functions, and Storage until a build that initializes
the SDK is actually in users' hands — the metrics page is the gate, not the calendar.
The one exception is already live and is code, not console:
`requestPasswordReset` carries `enforceAppCheck: true` in its own declaration, which is
why that single callable rejects everything today while every other callable is
unaffected.

**Do not remove the enforcement in order to test the pipeline — it gates almost
nothing.** Asked and answered 2026-08-07, and deferred by the product owner rather than
acted on. Three facts, so nobody re-derives them:

- **The gated part is seventeen lines.** `requestPasswordReset` validates input,
  enqueues a task, and returns `{accepted: true}`. Everything worth testing is past the
  queue in `processPasswordResetTask`, reached by the private worker
  `deliverPasswordReset`, which has no attestation of any kind.
- **That logic is already covered.** `functions/src/email/passwordReset.test.ts` holds
  **7 tests** — unknown identity, the current-Auth-email HMAC recheck, active
  suppression, an eligible send, a retryable provider error, a globally disabled
  canonical root, and malformed email. Removing enforcement would reveal nothing they
  do not already assert.
- **Both gates are ours, not the platform's.** Line 421 calls
  `requireAppCheckedPublic`, which throws on an absent `request.app` in the emulator
  too. "Turn it off locally" means deleting production code, not changing a setting.

~~**The one layer with no coverage** is the worker against real infrastructure.~~ **Built
2026-08-08 and this paragraph is now history.** `rules-tests/test/password-reset-delivery.integration.test.js`
holds **11** tests that build the task with `preparePasswordResetRequest` and drive
`processPasswordResetTask` over the real Firestore and Auth adapters, inside the invitation
suite's project. It resolved none of the App Check question above and was not meant to: what it
covered is the half that was never blocked.

~~It changes no production code.~~ **Retracted — it changed one keyword.**
`firestorePasswordResetDependencies` is now exported from
`functions/src/email/passwordReset.ts`. Rebuilding those adapters inside the test would have
been a test of the rebuild: the unit suite substitutes all eight dependencies, so the Firestore
transactions and the Auth gateway had never executed anywhere. No signature, behaviour, or call
site moved, and the functions suite held at 409 to say so.

**What it still does not reach is three lines of `deliverPasswordReset` itself** — the keyring
parsed out of its secret, the Brevo provider constructed out of its secrets, and the
`getFirestore()`/`getAuth()` defaults. That is deliberate and the reason is a trap rather than
laziness: reaching them needs `functions/integration/index.js` to export an email function, and
every parameter in `email/config.ts` would then have to be answered at emulator startup or the
run hangs after "Serving at port ...". That fixture's seven exports reach
`firebase-functions/params` not at all. The parts of those three lines are unit-tested
separately, so the residual risk is low; if it is ever taken, it is a fixture chunk, not a test
chunk.

**Nothing was found broken.** The deletion sentinels serialize against real Firestore — the
shape that took `mergeSaleReconciliationJob` down on every sale it ever saw —
`generatePasswordResetLink` works against the Auth emulator, real Auth folds a mixed-case
address so the current-email HMAC recheck matches, and a missing identity raises exactly the
`auth/user-not-found` code the gateway swallows.

### `Callout` has no specification, and three glyph sizes were borrowed

**Raised by step 4 on 2026-08-12 and not decided inside it**, because `claude.md` forbids inventing
a value `design.md` does not define and the honest alternative to inventing one is asking.

`design.md` §5.1 gives `Callout` a row — it replaces "permanent notice paragraphs" — and §5.2
specifies only the "load-bearing five", which it is not among. So every measurement it uses is read
from a §2 row that exists for something else: `radius.md` from §2.3's "cards, rows, sheets",
`space.16` padding, `space.12` between glyph and words, `title.md` and the density's body role. The
precedent is `AppSelect`, which took the same treatment in step 3 for the same reason.

Separately, §5.2 names exactly **two** icon sizes anywhere — `AppButton`'s leading icon at 18 and
`StatusBadge`'s at 14 — and specifies none for `Disclosure`'s info glyph, `Disclosure`'s chevron, or
`Callout`'s glyph. All three take 18, as the nearest named row for a leading glyph on a line of body
text. **A fourth joined them on 2026-08-13**: `RecordActionSet`'s overflow glyph and the glyphs on
its menu items, at the same 18 for the same reason. §5.1's inventory names no menu component at all,
so there is no row to read one from.

**Either §5.2 gains a `Callout` paragraph and an icon-size row, or it gains a sentence saying the
borrowed rows are the specification.** Both are fine; what is not fine is leaving it unstated,
because a later reader cannot tell a borrowed row from a specified one by looking at the code.
**It blocks calling §5's inventory complete in step 12**, the same way the field-hover question
blocks §9's audit.

### Every string is painted 0.25px per character wider than its token style says

**Found by the column-arithmetic chunk on 2026-08-15, by asserting a measurement against a
rendering.** A `TextStyle` with `inherit: true` — and every style in `AppTypeRoles` is one, because
none of them sets `inherit: false` — is merged onto the enclosing `DefaultTextStyle` before it is
painted. This app's `ThemeData` carries Material's own **`letterSpacing: 0.25`** on the roles §2.2
does not name a spacing for, which is all of them except `label.eyebrow`. So the type this app draws
is not quite the type the token layer declares.

**It is small and it is not nothing.** A quarter of a pixel per character is 4.25 pixels on
`Cancel invitation`, and on a row of four buttons it was the difference between one line and two —
which is how it was found rather than reasoned about. `measureTextWidth` takes the ambient style as
an argument for exactly this reason, so nothing measured here is wrong; what is unstated is which of
the two is the specification.

**Three honest resolutions.** §2.2 gains a letter-spacing column and the theme is made to match it;
or the token layer sets `letterSpacing: 0` on every role it does not name one for, so a role means
what it says; or §2.2 gains a sentence saying the ambient spacing is deliberate and the roles are
deltas onto it. **Do not decide it inside a chunk**: the second and third are one line each and would
move **every string in the app**, which is a diff no visual step should be carrying incidentally.

### A chip is the only thing §2.3's pill argument still guards, and the theme disagrees with it

**Raised by `design.md` v0.4 on 2026-08-15, not decided inside it.** §2.3's reason for restricting
`radius.pill` was that "when *everything* is a pill — buttons, chips, filters, cards, inputs — the
shape stops signifying". v0.4 gave the input the pill back and kept the argument, which now rests
entirely on the remaining rows: chips, filters, badges and cards.

**And the code does not honour it on the one row that matters most.** `chipTheme` is
`StadiumBorder` in `lib/theme.dart` where §2.3 says `radius.sm`, and it has been since before the
migration started — `DESIGN-AUDIT.md` §1.7 lists it, and `theme.dart`'s own doc names it as a
divergence owed to step 4. So today a chip *is* a pill, which means §2.3's argument is currently
being made by a document about a codebase that contradicts it. **The catalog's category chips and
the checkout tender chips are where a person meets this.**

**Two honest resolutions, and this chunk took neither because both are somebody else's.** Close it —
move `chipTheme` to `radius.sm`, which is step 4's leftover and moves the catalog and checkout
images; or amend §2.3 again to say the pill is the app's shape and `radius.sm` is for badges alone,
which is a bigger claim than v0.4 made and should be made deliberately rather than by attrition.
**Do not decide it inside a copy pass.**

### An unticked control's outline carries meaning, and no §2.1 border clears §9's 3:1

**Raised by step 9 on 2026-08-15, not decided inside it, and it is the first place §9's own
2026-08-12 reading bites.** That reading says the 3:1 row applies to "a boundary that **carries
meaning on its own** — not to every border that exists", and it clears the five status borders on
the grounds that a status is container + icon + label, so no meaning rests on the edge.

**An unticked checkbox is the counter-example.** There is no container, no icon and no label inside
it: the outline is the *only* thing on screen saying there is a control there and that it is off.
It carries meaning by that reading's own test, so it owes 3:1 — and `border.strong` `#2C5340` is
**1.97** on `surface.base`, `border.subtle` `#1E3A2B` is **1.38**, and there is no third border role.
The one boundary §2.1 gives a number to, the focus ring at `#45F28D`, clears it at 11.71 and is not
a resting state.

**Step 9 moved it from `border.subtle` to `border.strong`**, which is §2.1's own row for an input and
is a real improvement — it is visibly lighter in `web/20-bulk-changes-and-import` — and it is still
under 3. **Inventing a colour is what `claude.md` forbids**, so it is here rather than in the theme.
Three honest resolutions: §2.1 gains a role for a control edge that must be perceived, at
`text.tertiary`'s 5.9 or thereabouts; or §9 gains a sentence saying an unticked control is exempt
because its label sits beside it and the pair is the control; or §5.1 gains a `Checkbox` row and
§5.2 specifies it, which is the answer that also settles the tap-target and label-tap questions
nobody has asked yet. **It affects three call sites** — sign-in's remember box and the two
`CheckboxListTile`s on screens 19 and 20 — so it is cheap whenever it is decided.

### A shift's money is stated with no currency code, and §8 rule 8 says money always carries one

**Raised by step 8's second half on 2026-08-15, not decided inside it, and it is a capability question
wearing a copy question's clothes.**

§8 rule 8 is unambiguous: *"Money is always currency-coded and tabular. `KES 135.00`, never `135`."*
Screen 28 states a shift's sales variance as `-12.5` with no code, and the differences list has done
so since it was written — the sentence it replaced said "its sales total is 12.5 short" and carried no
code either. Step 8 made it *tabular* and did not make it *coded*, so this chunk fixed half of a rule
it did not create. The same is true of `_amendedNotice`, which formats two amounts with a bare
`(minor / 100).toStringAsFixed(2)`.

**The reason it was not fixed is a hard rule rather than a preference.** The code lives in
`configuration/checkout`; `TenantReportingCurrency.read` is how every other reporting surface gets it,
and it is a document read. Adding one to this route is a repository call, which `claude.md` hard rule 1
forbids in a visual chunk. **Three honest resolutions, none of them a restyle**: the anomaly panel
gains the same guarded currency read the two money screens already make, and shows
`TenantReportingCurrency.unknownNotice` when there is none; or §8 gains a sentence exempting a
*variance* on a diagnostic surface; or the shift variance stops being shown as an amount at all. The
first is the most likely and is a capability chunk of about an hour.

### Three run counts are decoded on every read and displayed by nothing

**Found by step 8's second half on 2026-08-15 while deciding what a run's figures are.**
`TenantReconciliationRun` decodes `metricsProcessed`, `productsProcessed` and `shiftsProcessed` —
literally "what the run read and what it wrote", which is what this file predicted the run screens
would want — and **no surface has ever shown any of the three**. Neither the day page's run list nor
the one-run route mentions them; the only counts on screen are attempts, failures in a row, and the
two variance counts.

**They were deliberately not added.** Showing a field that has never been shown is new content on a
screen, not a new rendering of existing content, and the chunk that would decide *whether an operator
wants to know that a run read 7 products* is a product decision rather than step 8's. **The honest
options are all cheap**: show all three as `StatLine`s beside the two variance counts, which is four
lines of code and makes the variance counts legible as proportions ("1 of 7 products"); show none and
delete the decode; or leave them decoded and unread with this entry against them. The middle one is
the only one that loses information the server already sends.

### `AppScaffold` is where §3's density lands, and nothing can tell it what a pointer device is

**Raised again by step 5a on 2026-08-12, examined, and declined rather than answered.**
`lib/ui/tokens.dart` has been carrying it since step 1: §3 says density is "chosen by the screen",
the two value sets exist, and the widget that does the choosing does not. `AppScaffold` is now that
widget — it is the only thing every route has in common — so this is the last honest place to leave
the question open before step 6 and step 8 need it, and `DESIGN-AUDIT.md` §6 already calls it "the
one item here that is not cosmetic in any sense".

**What blocks it is one sentence in §3**: *"a touch device never gets 32px targets whatever its
width."* Density is not a width test — it is a width test **and** an input test, and Flutter has no
honest answer to the second. `defaultTargetPlatform` describes the OS, not the hardware: a Windows
tablet, a Chromebook in tablet mode and a touchscreen desktop till are all pointer platforms with
fingers on them, and this app is for a shop counter. `MouseTracker.mouseIsConnected` answers only
after a mouse has moved. Choosing one of those and calling it the rule would put a 32 x 32 tap
target on a real till, which is the one failure §9 makes pass/fail.

**So `AppScaffold` takes no density and every screen is still comfortable**, which is the stricter
setting on every dimension §9 measures. Nothing regressed and nothing was invented. **Either §3
gains a rule this code can evaluate** — width alone, or width plus an explicit per-screen opt-in a
till build can refuse — **or it gains a sentence saying comfortable is the only density that
ships** and `AppDensity.compact` becomes documentation. **A question for the product owner, not a
chunk.** It blocks §3 being called implemented in step 12, and step 8 will want the answer.

**Met by step 6b on 2026-08-13, examined again, and declined again — and the meeting is the useful
part.** §3's table gives `density.compact` to "catalog, ledger, reconciliation, activity log, staff —
at ≥1024", which is exactly the set `RecordList` covers, and `RecordList` draws a **table** at
exactly that floor. So the one screen shape §3 wrote the compact density for now exists, and it is
still comfortable: 64-high rows where §3 offers 40, 48dp actions where §3 offers 32. **Nothing about
the question changed and the code that would answer it is now written**, which narrows the cost of
answering to two constants and a wrapper. What still blocks it is the same sentence — *a touch device
never gets 32px targets whatever its width* — and the same absence of any honest way to ask Flutter
whether a pointer is present. **It is now the largest single thing standing between this app and
§3.**

### `design.md` states no page padding, and `AppScaffold` had to pick one

**Raised by step 5a on 2026-08-12.** §4.2 states a maximum content *width* and hands it to step 6;
no section states the inset between a page's content and the edge of the screen. `AppScaffold` uses
`space.20`, which is on §2.3's scale and is what the three largest list screens already pad their
bodies with, so the header lines up with the content beneath it where lining up is most visible.

~~**Two routes pad 24 instead and are 4 pixels out until step 6 unifies them** — checkout settings
and the landing route.~~ **Corrected and closed 2026-08-12 by step 6a.** There were **three**, not
two, and the landing route was not among them: it is a raw `Scaffold` with no `AppScaffold` header
to be out of line with. The three were checkout settings and the shell's **two** invitation screens,
and all three now pad `space.20` through `AppScaffold.horizontalInset` rather than a literal.

**The question underneath is still open and is narrower than it was.** `design.md` still states no
page padding; 20 is still a component decision reading §2.3's scale rather than a value the
specification names. What has changed is that it is now applied consistently, so the answer costs
one edit in one place. **Not a blocking question**; it becomes one only if §4 is to be called
complete in step 12 without stating a value.

### Six screens draw a record list nobody gave §4.3 to, and no numbered step claims them

**Raised by the product owner on 2026-08-15, asking whether the platform screenshots were final, and
answered by a grep rather than from memory.** They are final by omission rather than by intent.

§4.3's contract — stacked cards, two-column cards, data table, resolved from the screen width — is
`RecordList`, and step 6 put twelve screens on it. **Six list-bearing surfaces were never on step 6's
list and are therefore still hand-built `ListView` + `Card` at every band**: the four platform tabs
(`platform_tenant_review.dart:857`, `platform_tenant_lifecycle.dart:837`,
`platform_tenant_archival.dart:712`, `platform_global_user_status.dart:1094`), the business selector's
list in `tenant_routing_shell.dart`, and the invitation list beside it. So a platform administrator on
a 1920px window reads a single column of cards on a screen whose whole job is comparing businesses —
which is the complaint §4.2 was written about, arriving on the screens §4.2 never reached.

**Two of them are worse than the other four**: the selector and the platform tabs at least sit in an
`AppScaffold` with `AppContentWidth.records`, so they are centred at 1200 rather than stretched.

**This is the largest remaining hole in §4.3's coverage and it is nobody's number.** §11 names screens
by their §11 numbers and none of these six has one. Three honest resolutions: §11 gains a step 6c for
the platform and tenancy surfaces, which is the faithful one and is about the size of step 6's second
half; or §4.3 gains a sentence saying the contract covers *business* records and the platform console
is exempt, which is a real argument — an operator is not a shopkeeper and §8 rule 1 does not reach
them; or it is left, in which case step 12 cannot call §4.3 complete and should say why. **Do not
decide it inside a chunk.**

### `AppSheet` has no specification, and step 7 opens a sheet

**Raised by the product owner on 2026-08-15, asking whether the sale path's drawer behaviour was
handled.** It is not, and the reason is a gap rather than a queue position.

§5.1 gives `AppSheet` a row — it replaces "ad-hoc `showModalBottomSheet`" at priority 2 — and §5.2
specifies only the load-bearing five, which it is not among. **So there is no specified height, no
drag behaviour, no dismissal rule, no scrim, and nothing about what closing one does to the work
inside it.** §4.3's `Sale` row says compact and medium are "products + cart sheet", so step 7 cannot
be built without answering all of that, and `lib/ui/record_list.dart:321` already records working
around the absence with a `PopupMenuButton`.

**There is exactly one `showModalBottomSheet` left in the migrated tree** —
`checkout_cart_panel.dart:614`, the cart itself — so the component has one caller and the caller is
step 7's. That makes this cheap to settle and impossible to skip: **it blocks step 7 the way the
`Callout` question blocks §5's inventory**, except that this one blocks building rather than blocks
calling something complete. Either §5.2 gains an `AppSheet` paragraph, or step 7 specifies it and §5.2
gains a sentence saying so.

**The dismissal rule is the part to think hardest about**, because §6's own hard rule reaches it:
nothing on the sale path may sit between an input and its record. A sheet that animates closed before
the cart is written would be exactly that.

### The app teaches by folding prose, and nobody has decided whether folding is teaching

**Raised by the product owner on 2026-08-15**, asking whether a tutorial or onboarding flow was
planned so that screens like the shift corrections stop carrying paragraphs.

**Neither document contains one.** `design.md` and this file were both grepped for tutorial,
walkthrough, onboarding, coach marks and first-run: §11 step 9's "onboarding" is the sign-in and
business-selection *phases*, and §6.4's asset 7 is a one-shot celebration. There is no teaching layer
as a concept anywhere.

**What exists instead is structural and is working.** §7's long-copy rule sends policy prose into a
`Disclosure`; §5.2 calls it "the single highest-value component here" precisely so the writing
survives while the screen shrinks; and the 2026-08-15 rule splits a permanent *helper* (folds) from a
permanent *notice* (does not). There are **17 `Disclosure`s across 9 files** today and the coverage is
uneven — `catalog_management_panel.dart` carries 13 long strings against 3 of them.

**The question is whether folding is the whole answer.** Folding makes a screen shorter; it does not
make a person who has never closed a shift understand what a correction is. Three honest
resolutions: finish the fold and declare it sufficient, which costs nothing beyond the sweep already
queued; add a teaching layer, which is new product scope in neither document and needs §5.1 rows that
do not exist; or accept that some screens teach by being read and write them accordingly. **A
question for the product owner, not a chunk**, and unlike the other two here it blocks nothing.

### The invitation email names no business, and no step reaches an email

**Raised by the product owner on 2026-08-15**, asking whether an invited person sees a list of
businesses in the email. **They see neither a list nor a name.**

`functions/src/staff/invitationDelivery.ts` sends one sentence — *"You have been invited to a business
workspace."* — and the body is a single `<p>`. It does not name the business, the inviter, the role, or
what to do next beyond the link. **Three facts compound it and none was recorded before:**

- **`design.md` governs the app and stops at its edge.** §11's twelve steps contain no email step, so
  the one surface a person meets *before* they can open the app is the one surface with no
  specification at all. §8's ten content rules have never been read over it.
- **It has never been seen.** Staff invitation email cannot be delivered against the emulators —
  rollout step 12 records it — so nothing here is evidence about what actually arrives.
- **It is not a copy fix.** Naming the business means the delivery worker reading one, which is a
  payload change to a callable and a `functions/` chunk, not a wording pass.

**Whether it should list businesses at all is the part only the product owner can answer**, and it is
a different question from naming one: an invitation is issued against a single business by
`functions/src/staff/issuance.ts`, so a *list* implies something the model does not currently
describe. If a screenshot exists showing one, it is describing a capability rather than a restyle.

### ~~The emulator suites need a JDK 21 this machine does not have~~ — withdrawn 2026-08-13, it was never true

**This decision should never have been opened, and it is kept rather than deleted because the way it
was opened is the useful part.**

It read: `firebase-tools@15.24.0` refuses to start any emulator below Java 21, the only JDK on this
machine is Temurin 17.0.20, so the rules suite, the reconciliation integration suite and the
invitation integration suite — 161, 10 and 23 tests, three of the five baselines — cannot be run
here at all. It offered the product owner three ways out: install a JDK 21, pin `firebase-tools`
back, or find another machine.

**All of it was false.** A portable Temurin **21.0.12** sits at
`D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8` and has been there since before this work began.
Reaching it is the three-line prelude under "The emulator prelude is not optional" in this file's own
"Working on this repository" section, which also clears `DEBUG` because this machine sets
`DEBUG=release`. `HISTORY.md` records the same three lines in **eleven** separate session entries.
With the prelude, all three suites pass first time: **161, 10, 23**, measured 2026-08-13.

**How it survived two sessions.** Step 6a on 2026-08-12 ran the suites bare, read the version error
as a fact about the machine, and wrote this decision plus a standing trap — **three sections above
the prelude that answers it**, in the same file. Step 6b on 2026-08-13 inherited it, ran one suite
bare to "confirm" it, escalated it to a blocking decision in its opening line, and then searched
`C:\Program Files` and the home directory for a JDK 21 while `HISTORY.md` said it was on `D:`. **The
product owner corrected it from memory of earlier chunks.**

**What it costs to leave a claim like this standing** is the part worth keeping. For one day this
file told every future session that three of its five baselines were unrunnable, that the carry
counter was at its limit, and that the queue was gated on a machine change the product owner had to
authorise. None of that was true, and each layer was written by a session that trusted the previous
one instead of running three lines.

**Two rules come out of it, and both are now in "Standing traps":**

- **Run the prelude before concluding anything about this machine.** An environment error is not
  evidence about the environment until the documented environment has been used.
- **A trap that contradicts a procedure in the same file is the file's defect.** The trap said no
  emulator could start; the procedure said exactly how to start one. Whoever writes the next trap
  should grep this file for what it contradicts.

### Three design-system questions the redesign has refused to answer

The first two were opened on 2026-08-11 by building step 1 and the third by building step 2. None
is answerable from `design.md`, and `claude.md` forbids inventing the value that would close any of
them, so they are here rather than in the code.

**~~Do §2.1's container borders have to clear §9's 3:1?~~ Answered by the product owner on
2026-08-12: the border is decoration.** §9's 3:1 row applies to a boundary that **carries meaning
on its own**, not to every border that exists. Nothing is re-derived; `design.md` §9 gains the
sentence and the reasoning, so the next reader does not re-open it.

The measurements that framed it, kept because they are what made the call: on `surface.base`,
`border.subtle` is 1.38, `border.strong` 1.97, and the five status borders sit between 1.38 and
2.04 — so the other reading would have re-derived ten colours and §2.1's whole status palette. The
system already conforms under the reading taken: a status is **container + icon + label**, all five
foreground colours clear 5:1, and the focus ring — the one boundary §9 names with a number —
clears 3:1 at 11.71.

**It is not a blanket exemption.** Where a border is the *only* thing separating two regions a
person must tell apart, it carries meaning and 3:1 applies. Step 12's audit checks that, not the
decorative edges.

**~~A third was opened by step 2: what is `AppSelect`?~~ Closed 2026-08-12, and it was never a
question — it was a wrong fact.** `DESIGN-AUDIT.md` said nothing existed for it to replace, and
that is false: there are **five** `DropdownButtonFormField` call sites. Put back to the product
owner with the real figure and reversed; `AppSelect` is built and §5.1 stands. **The lesson is
about this list rather than about selects**: a question here is only worth the fact under it, and
this one's fact was never checked with a grep.

**A third is open in its place, from step 3: what does a field look like under a pointer?** §5.2
specifies a field's rest, focus and error treatments and says nothing about hover. `AppTextField`
therefore has none, and `92-appfield-hover` is a capture of no change at all. Either §5.2 gains a
row — `surface.raised` for the well would be the obvious one, and is deliberately **not** applied
unasked — or it gains a sentence saying a field has no hover state. It blocks nothing until step
12, where §9's audit cannot be called complete over an unspecified state.

**What family is `mono`?** §2.2 opens with "One family — Roboto" and its last row says
"monospace", and the app bundles no font at all: `lib/theme.dart` names none, deliberately, and
the screenshot harness injects Roboto itself, which is why the harness is more branded than the
app. So `mono` carries its metrics and names no family, and **record IDs and SKUs still render
proportionally** — the role exists and does not yet do its job. `DESIGN-AUDIT.md` §6 already lists
the Roboto half of this; the monospace half is the part with no answer at all, because "one family"
and "monospace" cannot both be true. Until it is settled **no screenshot is evidence about type**.

### ~~Whether the app should be able to stock itself~~ — closed 2026-08-07

**Resolved in the client's favour, in full.** The question was never stated as a
decision, which is why it went unnoticed for so long: every operational surface
downstream of a product worked and nothing created one. It was answered twice on the
same day and the same way. First for `configuration/checkout` — a business publishes
its own currency, because refusing it would have meant a business that cannot trade
until an operator runs a script. Then for the catalog itself, on identical reasoning.
Both are now standing decisions above; the seed script is a development convenience
and not the supported route.

### ~~How a price is corrected~~ — resolved 2026-08-07: an `updateProduct` callable

Opened by the configuration chunk and resolved the same week. Firestore rules let a
client **create** a product (owner/admin/manager) and **delete** one (owner/admin) —
both of which the app now does — but `allow update` on `products/{productId}` permits
only a strictly decreasing `quantity` with
`affectedKeys().hasOnly(['quantity', 'updatedAt'])`: the checkout decrement, and
nothing else. So no client can change a name, a price, a SKU, or a category, and no
callable does either.

~~Three ways out, undecided.~~ **Delete-and-re-create was never viable** — the product
ID is what `stock_movements`, `daily_metrics`, and every past sale line refer to, so
re-creating under a new ID severs the whole ledger, which is why the retire
confirmation says in as many words that this is not how a mistake is corrected. Of the
two that remained, **the callable wins on three counts, and the first is the one the
original framing missed:**

1. **A wider rule means editing the most dangerous clause in `firestore.rules`.** The
   current `allow update` is a single tight clause and it is the whole guarantee that
   no client can ever inflate stock. Widening it means OR-ing a second clause onto it,
   where a mistake is a stock-integrity hole rather than an audit gap. **A callable
   writes through the Admin SDK, which bypasses rules entirely, so this route changes
   `firestore.rules` not at all** and that clause stays byte-identical. Cost was the
   original argument for the rule; this is the cost it hid.
2. **A price is money, and the rule route is the only path here that would change
   money with no record.** `adjustStock` changes a *quantity* and still writes three
   documents — a `stock_adjustments` record, a `stock_movements` ledger entry, and an
   `audit_logs` entry — each carrying actor, reason, request ID, and the before and
   after. A rule-based price edit writes none of that: no actor, no previous value, no
   reason, nothing but `updatedAt`. "This was 450 last week, who made it 45?" would be
   unanswerable. It lands hardest against reconciliation, which exists to explain
   differences and could never account for that one.
3. **The server is the only place price validation becomes a guarantee.** A rule can
   check `price is number && price >= 0`. It cannot check two-decimal
   representability, so `19.999` passes the rule and then fails
   `checkoutMinorUnitsFromMajor` at the till with a customer standing there. `name` and
   `SKU` are strict in `TenantProduct`, and one unparseable product makes the *whole*
   cached catalog a miss. Today only client-side `TenantProductCreateIntent` guards
   that; a callable is the first chance to make it real on the server.

**The cost was overstated.** `functions/src/operations/stock.ts` is 128 lines end to
end including imports, request and response types, and the audit writes.
`updateProduct` is that skeleton with a different payload and *no* ledger entry,
reusing `requireTenantMember`, `runIdempotentFirestoreTransaction`, `requireDocumentId`
and `requireRequestId`. The rule route was not free either: a second clause, a
`hasOnly` key list, an explicit `quantity` exclusion, and rules-emulator coverage for
every combination.

Two things settled with it, so the chunk does not reopen them:

- **It must not touch `quantity`.** That belongs to `adjustStock` and the checkout
  decrement, and a callable that could write both would be a second way to move stock
  without a ledger entry.
- **The role split is its own choice, not an inherited one.** Creating is
  owner/admin/manager and deleting is owner/admin; a price edit is closer in
  consequence to deleting than to creating. The callable can say a manager may fix a
  name or SKU while only an owner or administrator may change a price — which a rule
  realistically cannot.

**Built on 2026-08-07, and every one of those three grounds held.** See "A price is
corrected on the server, and never a quantity" among the standing decisions above for
what it actually guarantees. The one thing worth repeating here, because it was the
argument that flipped the decision: `firestore.rules` is byte-identical, and the
160-test rules suite was run to say so with a measurement rather than an assertion.

**Reached from the app on 2026-08-08, and the rules file was measured byte-identical a
second time** — 161 tests, over a chunk that touched no server file at all. A mistyped
price is corrected from "Manage catalog" → "Correct", and the catalog surface now
creates, corrects, and retires.

### ~~What a receipt is printed on~~ — answered 2026-08-07, and it is not ours

Opened by the sweep session for a procedural reason: receipt printing had been a
standing exclusion for many consecutive chunks, was named once in the previous
handover as "the next capability chunk this list will run out of excuses for", and
re-excluding it silently a second time is what this file forbids. It is no longer
correctly excluded **as a capability**.

~~It needs one thing decided first: the `printing` package's system dialog, networked
ESC/POS through `flutter_esc_pos_network`, or the printed body alone with no
transport.~~ **Retracted the same day.** The product owner answered it before the
question was a day old: **a print service, to be shared, handles thermal printer
onboarding across a local print server, TCP/IP, and Bluetooth.** So the transport is
external, the range of connections is settled, and none of the three options above is
the shape of the work. Two consequences, and they run in opposite directions:

1. **The transport is not this app's problem, so the surfaces the second option
   implied are not either** — no printer-address settings route, no discovery UI, no
   connection state machine, and nothing new in the encrypted Hive `printer` slot
   until the service says otherwise. `flutter_esc_pos_network` and
   `flutter_esc_pos_utils` are in `pubspec.yaml`, unused by live code, and stay unused
   unless the service's own interface asks for them.
2. **The printed body is squarely ours, and it stops being an unreachable artifact.**
   Option 3 was discounted for landing in "built, tested, and unreachable"; with a
   service on the other side of it that objection is gone. The body is the half this
   app owes, and it is the half that is transport-independent by construction.

**What is still unknown is the interface, and it is unknown enough to block.** The
body cannot be written faithfully without it, because the answer changes what a
"body" even is:

- **What the service takes.** ESC/POS byte sequences, plain text with a column width,
  a structured payload it renders itself, or a PDF. Each makes a different function.
- **How it is reached.** A Dart package in `pubspec.yaml`, a local HTTP endpoint, or a
  platform channel. This decides whether printing is testable as a unit at all.
- **Whether it holds the printer selection**, or hands this app a list to choose from
  and store — the one thing that could still pull a settings surface back in.
- **What it does offline.** The till is offline-first on Windows by design, and a
  receipt is printed at the moment of sale. A service that needs the network to print
  makes printing conditional in a way the sell-and-settle loop currently is not.
- **Column width and character set**, which are formatting inputs, not details: a
  32-column roll and a 48-column roll are different layouts.

Until the service is shared, a sale is recorded, found by receipt lookup, and returned
without anything ever being printed, and "Print a receipt" stays red. **Do not start
the body on a guessed interface** — a receipt formatter written against the wrong
contract is worse than none, because it looks finished.

---

## Identity, Tenancy, and Public Interfaces

### Environments

`dev multitenant-pos-b8326`, `staging chilltent-pos-staging`,
`prod chilltent-pos-prod`. CI must always receive an explicit environment/project
mapping. **Only `dev` is mapped in `.firebaserc` today** (`default` and `control`
both point at it); staging and production exist in this spec and nowhere else.

### Root model

```text
/users/{uid}
  email, displayName
  accountType                 // tenant_user | platform_admin
  identityOrigin              // self_signup | staff_invitation | platform_bootstrap
  identityTransition?         // granting_platform | revoking_platform | cleanup_pending
  globalStatus                // active | disabled
  defaultTenantId?
  membershipCount, ownedTenantCount, ownedActiveTenantCount
  createdAt, updatedAt

/users/{uid}/tenant_memberships/{tenantId}
  tenantId, tenantName, tenantSlug
  role                        // owner | admin | manager | cashier
  membershipStatus            // pending | active | inactive
  tenantStatus                // pending | active | suspended | rejected | archived
  invitationStatus, isOwner
  createdAt, joinedAt, updatedAt, mirrorVersion
```

Mirrors, counters, and `defaultTenantId` are advisory. They never authorize
access. Canonical authorization remains `/tenants/{tenantId}` and
`/tenants/{tenantId}/staff/{uid}`, and every staff document carries a
server-controlled `uid` for collection-group scans.

Platform collections: `/platform_config`, `/platform_audit_logs`,
`/platform_user_operations`, `/platform_identity_operations`,
`/platform_membership_repair_runs`, `/owner_recovery_cases`, `/email_deliveries`,
`/email_suppressions`, `/tenant_slugs`.

### Tenant path contract

`TenantPaths.businessCollections`, all fifteen. The enumeration is frozen and
`test/tenancy/tenant_paths_test.dart` fails when it changes without being declared
there: `products`, `categories`, `sales`, `shifts`, `returns`, `staff`,
`configuration`, `subscription`, `audit_logs`, `stock_adjustments`,
`daily_metrics`, `reconciliation_jobs`, `reconciliation_dirty_days`,
`reconciliation_anomalies`, `shift_amendments` — plus one product subcollection,
`stock_movements`.

### Tenant routing and limits

`listMyTenants({pageSize?, cursor?})` — default 20, maximum 50, ordered by
membership creation descending then tenant ID, server-issued opaque cursor, each
result overlaid with canonical tenant and staff state, returning `items`,
`nextCursor`, `hasMore`.

Login order: device-local last selection if canonically valid; else
`defaultTenantId` if valid; else the sole accessible tenant; else the selector.
Pending, rejected, suspended, and inactive memberships are shown without granting
access. Opening a tenant updates only the device-local selection; `defaultTenantId`
changes only through an explicit "Make default".

Limits, enforced when requesting, approving, or reactivating:
`maxPendingTenantsPerUser: 3`, `maxTenantRequestsPer24Hours: 5`,
`maxOwnedActiveTenantsPerUser: 25`.

### Shared authorization

```text
requireAppCheckedPublic()
requireAuthenticatedUser({allowUnverified})
requireVerifiedTenantApplicant()
requirePendingTenantInvite(tenantId)
requireTenantMember(tenantId, allowedRoles)
requirePlatformAdmin()
```

`requireTenantMember` verifies auth exists, root `globalStatus == active`, tenant
exists and is active, canonical staff membership exists, staff status is active,
and the tenant-local role is allowed. No handler implements these independently.

Idempotency keys are scoped by `actorUid + operation + tenantId/global-scope + requestId`.

### Public callable interfaces

Twenty-six `onCall` endpoints. The last five were added after the original list
was frozen and are marked:

```text
sendAccountVerification({requestId})
requestPasswordReset({email, requestId})
getMyEmailDeliveryStatus()
listMyTenants({pageSize?, cursor?})
setDefaultTenant({tenantId, requestId})
requestTenant({name, slug, requestId})
setTenantLifecycle({tenantId, status, reason?, requestId})
setGlobalUserStatus({uid, status, reason, requestId})
getGlobalUserStatusReview({uid})                          // added later
inviteStaff({tenantId, email, name, phone, role, requestId})
updateStaffUser({tenantId, uid, name, phone, role, requestId})
setStaffStatus({tenantId, uid, status, requestId})
replacePendingStaffEmail({tenantId, uid, email, requestId})
resendStaffInvitation({tenantId, uid, requestId})
cancelTenantInvitation({tenantId, uid, reason, requestId})
acceptTenantInvitation({tenantId, invitationVersion, invitationToken, requestId})
acceptVisibleTenantInvitation({tenantId, requestId})
reviewEmailSuppression({email, action, reason, confirmation?, evidenceReference?, requestId})
adjustStock({tenantId, productId, quantityDelta, type, reason, requestId})
updateProduct({tenantId, productId, name?, sku?, price?, cost?, categoryId?, requestId})  // added later
updateProducts({tenantId, mode, rows, requestId})                                        // added later
importProducts({tenantId, mode, rows, requestId})                                        // added later
verifyReturnAndRestoreStock({tenantId, returnId, requestId})
getSalesComparison({tenantId, previousStartDate, previousEndDate, soldById?, categoryId?})
requestTenantReconciliation({tenantId, mode, requestId})
amendShiftSummary({tenantId, shiftId, reason, requestId})  // added later
```

### Full export surface

`functions/src/index.ts` exports **49** handlers — 47 until `updateProducts` landed on
2026-08-08, 48 until `importProducts` landed the same day, and unchanged by the 2026-08-07
cost chunk, which widened `updateProduct`'s payload and added no export — callables above,
plus task workers, triggers, retry workers, and schedulers:

```text
cleanupAbandonedStaffIdentities  consumePendingPlatformAlert
consumeTenantMembershipFanout    deliverAccountVerification
deliverPasswordReset             deliverPlatformAlertNotification
deliverStaffInvitation           mergeSaleReconciliationJob
receiveBrevoEmailWebhook         repairCanonicalStaffMirror
repairTenantRoutingProjection    retryGlobalUserStatusOperations
retryMembershipRepairTasks       retryPlatformAlertNotifications
retryStaffInvitationDeliveries   retryTenantReconciliationTasks
runMembershipRepairTask          runReconciliationTenantDiscoveryTask
runTenantReconciliationTask      startNightlyTenantReconciliation
startStaggeredMonthlyReconciliation  startWeeklyMembershipRepair
startWeeklyStockCheckpoints
```

`grantPlatformAdmin` and `revokePlatformAdmin` are deliberately **not** exported.
They are Admin SDK CLIs (`npm --prefix functions run grant-platform-admin`,
`revoke-platform-admin`) with a fixed project allowlist, actor authorization, exact
target confirmation, and deterministic exit states. Do not re-export the legacy
root-collection staff or reporting handlers.

---

## Platform, Ownership, and Membership Integrity

**Platform-admin eligibility** requires all three: `platformRole == "superAdmin"`
in the Auth claim, `accountType == "platform_admin"`, and `globalStatus == "active"`.
Granting never trusts counters: it places `identityTransition=granting_platform`
transactionally, runs `collectionGroup("staff").where("uid","==",target)`, searches
tenants by `ownerUid`, confirms no membership or unresolved invitation of any kind,
then sets the account type and merges the claim. Any canonical membership clears
the transition and rejects. The same scans are mandatory before deleting an
abandoned invitation-created identity. `requestTenant` rejects platform identities
and `inviteStaff` rejects platform targets — platform identities hold no tenant
memberships in v1.

**Owner invariant.** Every non-archived tenant has exactly one owner, with
`tenant.ownerUid` equal to the owner staff UID and that staff role `owner`. The
owner has all administrator permissions, cannot be demoted or deactivated through
ordinary APIs, and counts as an administrative principal — a globally active user
with an active membership and role `owner` or `admin`. Normal membership and role
operations must retain at least one. Global security disabling is the deliberate
exception: it proceeds even when it removes the last principal, then raises a
critical `tenant_owner_unavailable` or `no_active_administrator` alert, identifies
affected tenants, notifies operators, suspends nothing automatically, and directs
operators to owner recovery.

**Global-status saga.** `/platform_user_operations/{requestId}` records uid, target
status, per-step Firestore/Auth/claim status, overall
`pending | completed | partially_failed`, attempt count, requester, reason,
affected tenants, and last error code. Disable order: create the operation and set
root `globalStatus=disabled`; determine tenants losing a principal; raise alerts;
disable Firebase Auth; remove platform privilege; revoke refresh tokens; finish
audits. Reactivate order: enable Auth; set root active; complete audits; require a
new sign-in; **never restore platform claims automatically.** A private retry
worker resumes partial failures, and root status is checked by both Rules and
Functions, so a failed Auth update does not restore access.

**Owner recovery** is operator-only, unavailable through Flutter and the dashboard.
Normal recovery replaces an owner with an existing active admin. Exceptional
recovery promotes a verified, globally active tenant user who is not yet an
administrator, and additionally requires a recorded
`/owner_recovery_cases/{caseId}`, a support reference, `--exceptional`, typed
confirmation of the slug and both UIDs, a second confirmation flag, a written
reason, and proof the replacement is not a platform identity. Default outcome: the
old owner becomes an inactive admin and the replacement the active owner, in one
transaction updating the tenant, canonical staff, mirrors, owner counters,
lifecycle history, and both audits. Both paths preserve exactly-one-owner.

**Membership-mirror repair.** Canonical membership and mirror update
transactionally; tenant-wide name and status changes fan out asynchronously.
Targeted repair runs after a failed fan-out and a paginated full repair runs
weekly. Canonical data always wins. Repair fixes missing or orphaned mirrors, wrong
tenant/role/membership/invitation/lifecycle status, incorrect counts, wrong owner
flags, invalid `defaultTenantId`, and mirrors without canonical staff. Summaries
are audited and never authorize anything.

---

## Invitations and Email

**Invitation proof.** `/tenants/{tenantId}/staff_invitations/{uid}` is server-only
and holds the version, a versioned HMAC of the token, key version, issue and expiry
instants, used-at, status, invited email, inviter, and latest delivery ID. Each
attempt generates 32 random bytes, stores only the HMAC, increments the version,
expires after seven days, invalidates older versions, and gets its own delivery
record. Acceptance requires matching tenant, UID, invited email, version, hash,
expiry, unused state, and authentication no older than five minutes.

**Existing-user in-app acceptance.** `acceptVisibleTenantInvitation` requires the
caller to be the exact invited UID, a globally active root, a verified Firebase
email matching `invitedEmail`, a pending canonical membership, invitation status
pending or sent, `auth_time` under five minutes, and an active tenant. Flutter must
visibly show the business name, invited role, and an accept/cancel confirmation
first. The transaction activates the membership, updates the mirror, marks the
invitation accepted, consumes any outstanding token, and writes the tenant audit.
Versioned token proof remains mandatory for new identities, unverified identities,
password setup, and direct email-link acceptance.

**Email correction.** A tenant administrator never changes a shared identity's
global Auth email. Correcting a pending address cancels that invitation and creates
or reuses the identity for the corrected address. Before disabling or cleaning an
abandoned provisional UID: canonical staff collection-group scan, tenant owner
query, pending invitation scan, identity-transition check.

**Password-reset task.** The public endpoint enqueues a private Cloud Task carrying
the normalized email. The worker performs the Auth lookup and creates a delivery
only for an eligible identity. Plaintext never enters Firestore or normal logs, and
the public response is always `{"accepted": true}`. Before sending, the worker
confirms the Auth user's current email HMAC still matches the requested hash.

**Suppression mapping.** Permanent: hard bounce, invalid recipient, spam complaint,
and a provider block whose exact reason confirms permanent invalidity, prior
complaint, or prior hard bounce. Temporary: soft bounce, mailbox full, greylisting,
rate limit, timeout, temporary policy or reputation block, and **unknown blocked
reasons** — only a versioned, tested reason-code mapping may reclassify one.

**Suppression review.** `reviewEmailSuppression` is platform-admin-only. It
normalizes in memory, calculates current and supported previous HMAC versions,
finds matching records without storing plaintext, returns only redacted category,
event date, status, and reason class, and audits inspection and clearing. Clearing
a hard bounce or invalid recipient requires confirmation the address was corrected
or independently verified; clearing a complaint requires
`confirmation=clear_spam_complaint` and an evidence reference. Clearing marks the
record inactive with `clearedAt`, `clearedBy`, and a reason — never deleting
history. Tenant administrators cannot inspect or clear global suppression.

`getMyEmailDeliveryStatus()` answers for the caller's own address only and returns
one of two exact strings. The client matches them as sentinels rather than
displaying the server's sentence, because that sentence covers four different
causes and is itself the enumeration boundary. The public reset flow never reveals
this state.

**Brevo webhook privacy.** Persist only `providerMessageId`, `eventType`,
`providerTimestamp`, `recipientHash`, `normalizedReasonCode`, `processedAt`,
`payloadSchemaVersion`. Unparseable payloads may be encrypted in quarantine for
seven days; no raw payload is retained indefinitely. Continue using
provider-independent delivery, Admin action links, the Brevo HTTP API,
authenticated webhooks, source-controlled templates, SPF, DKIM, DMARC, a custom
return path, and disabled tracking.

---

## Offline Operations, Stock, and Receipts

**Tenant switching** is blocked by an unsynchronized checkout, a submission in
flight, other tracked pending writes, an unfinished cash count or shift close, an
unsaved tenant-scoped workflow, or no connectivity for target validation. **A
server-confirmed open shift alone does not block switching.** Owners and managers
may inspect another tenant while a shift stays open; a cashier cannot open checkout
in a second tenant on the same device while another tenant's shift remains open.
Returning restores only that tenant's own validated shift.

**Hive checkout state machine**, keyed `{uid}:{tenantId}:{checkoutId}`:

```text
saved_offline → submitting → awaiting_confirmation → confirmed | needs_attention
```

Each record holds submission attempt, persistent lease, retry time, payload, and
payload hash. Only one sync worker may call `batch.commit()` for a checkout, and
lease expiry permits a confirmation check, **never blind resubmission**. On restart:
inspect the local deterministic sale, wait if Firestore reports pending writes,
query the server when online, confirm a matching hash, flag a mismatch, and retry
only when no pending write and no server sale exist.

A saved sale triggers the sync pass immediately through `CheckoutSyncSignals` rather
than waiting for the next session open or connectivity change. The pass is
recover → submit → **recover again** → refresh derived data; the second recovery is
what settles a commit made during the same pass. Hive stores encrypted
tenant-specific product, price, configuration, shift, draft, printer, and sync
state; Firestore offline persistence is unavailable on Windows, so Hive remains the
cross-platform offline source.

**Stock rules.** Sale-line quantity is a positive integer; product quantity is
signed and may be negative. Checkout uses `FieldValue.increment(-quantity)` and
`FieldValue.serverTimestamp()`, and may change only product `quantity` and
`updatedAt`; positive changes require trusted adjustment, return, or import logic.
**The till does not refuse to sell below zero** — Rules permit signed stock, an
offline device holds a figure that was true at the last sync, and refusing would
block a legitimate sale while guaranteeing nothing on the server.

**Receipt sequence.** Counter key
`{tenantId}:{deviceId}:{businessDate}:receiptCounter`, deliberately not scoped by
cashier UID, allocated atomically in Hive under the checkout coordinator's local
lock, so two checkouts on one device cannot share a value. The receipt is
`CT-A7F-20260729-0042`; the sale records cashier UID separately and `saleId` remains
the database identity. Malformed counter state fails closed rather than restarting,
because restarting would reissue a number a committed sale already carries.

---

## Reconciliation, Rules, and Testing

### Reconciliation

Sale triggers merge one job per tenant per five-minute server-receipt bucket.
Nightly processing runs at 05:30 `Africa/Nairobi`, paginates tenants through
chained Cloud Tasks, enqueues one deterministic task per active tenant, and
regenerates dirty daily metrics while verifying stock and shifts. Weekly
checkpoints at 04:30 Sunday retain expected and observed quantities separately;
staggered monthly discovery at 04:45 validates the checkpoint chain, with a
ten-minute recovery scheduler. **Reconciliation never silently changes stock.**

**A sweep is one document per kind and local date, and its pages are counted once.**
`sweepRunId` is a digest of both, so the retry a scheduler is configured for re-enters
the same sweep instead of restarting it, and a document at that ID disagreeing about
either throws `already-exists`. `TENANT_DISCOVERY_PAGE_SIZE` is 50 and the
continuation is decided by what the query returned, **not** by what the monthly shard
filter kept — on a twenty-eight-way split most monthly pages are nearly empty, and
deciding it the other way would end the sweep at the first of them. A redelivered
discovery task re-returns its tenant tasks and writes nothing, which is safe because
the job and task IDs are digests. All of it is pinned by
`functions/src/reconciliation/sweep.test.ts`, together with one asymmetry worth
knowing: a page creates its tenant jobs **before** it records itself, so a sweep
document that has disappeared under a live page throws `not-found` with that page's
jobs already committed. They are queued, valid, and resumed rather than duplicated on
the retry, for the same digest reason.

**A sale is registered once, and `reconciliation_sale_receipts/{saleId}` is what
says so.** The trigger is declared `retry: true`, so redelivery is its documented
behaviour, not a hazard: the receipt is `create`d in the same transaction as the
movement, the dirty day, and the job, and a redelivery answers off the receipt and
writes nothing. A receipt disagreeing about tenant, business date, or bucket throws
`already-exists` rather than being adopted, and so does a job document sitting at the
predictable `dirty_<bucket>` ID that another source created — refusing the whole
transaction, so no half-written ledger entry survives. A malformed sale line is
counted and dropped rather than thrown on, because the sale is already committed and
throwing would leave the day unreconciled behind a poison delivery; the count reaches
an operator through one `reconciliation_anomalies` document per sale and the dirty
day's `invalidLineCount`. Lines past the hundredth are counted and dropped, and the
movement document ID becomes a digest past 120 characters of sale ID. All of it is
pinned by `functions/src/reconciliation/saleReceipt.test.ts`, including one
asymmetry worth knowing before changing it: **a redelivery returns a task even when
the first delivery returned none**, which is safe only because the task ID is a
digest of tenant, job, generation, and revision, `already-exists` is swallowed on
enqueue, and a superseded dispatch is refused by the claim.

A stock comparison concludes through one tested function,
`stockComparisonOutcome` in `reconciliation/model.ts`, ordered most-specific
cause first: an unreadable movement outranks an unverifiable chain, which
outranks a quantity variance. A first run **baselines** rather than compares, so
a variance needs two runs. A product written in the last five minutes is
deferred, carrying nothing forward.

Three bounds share one Firestore write budget and none is safe to raise alone:
5,000 sales read per business date, 200 stale shift expectations deleted, 200
distinct shifts written — 402 writes against the limit of 500.

The backoff ladder is 15s, 30s, 60s, 120s, 240s, 480s, 960s. Quarantine at eight
consecutive failures fires at the seventh rung, so the one-hour cap is unreachable;
the threshold must also stay below the queue's `maxAttempts: 12`, or the queue
abandons the task before the job quarantines itself and no alert is ever written.

The claim lease is ten minutes against a seven-minute worker deadline. The
three-minute margin is what stops a worker inside its own deadline from losing its
lease, which is the only way two workers reach one job's processors at once.

### Rules

Rules authorize from root global status, canonical tenant, and canonical staff
membership — never from mirrors or counters. Platform access requires both the
claim and an active platform record. Tenant membership operations involving platform
identities are rejected. Invitation proof, suppression, delivery, repair, lifecycle,
saga, subscription, and audit records are server-write-only. Positive direct stock
updates, return approval, and legacy root operational collections are denied.

Role boundaries, each decided deliberately rather than by default:

| Collection | Read |
| --- | --- |
| `sales`, `returns` | any active member — a receipt lookup and a return against a colleague's sale both need it |
| `shifts` | owner/admin/manager, or the shift's own cashier |
| `staff` | owner/admin/manager, or the member's own record |
| `daily_metrics`, `stock_adjustments`, `stock_movements`, `reconciliation_*`, `shift_amendments` | owner/admin/manager — and `daily_metrics` holds `profit`, which **only owner and admin are shown**. That is a surface boundary in `TenantProfitReport.allowedRoles`, not a rule: a manager's device already receives the field, exactly as every staff device already caches buying prices, and Firestore cannot hide one field of a document |
| `audit_logs` | owner/admin, plus platform |
| `configuration` | any active member — a till cannot price a sale without it. Writing is owner/admin, the one client-writable settings collection |
| `products`, `categories` | any active member — a till cannot sell what it cannot read. Writing is client-reachable and split three ways: create is owner/admin/manager on both, delete is owner/admin on `products` and owner/admin/manager on `categories`, and **update on `products` is the checkout decrement and nothing else** — a descriptive field, including `cost`, changes only through `updateProduct` or `updateProducts`, both of which write past rules entirely. `allow create` names no key list, which is what lets a product carry a `cost` with no rule change. `importProducts` also creates past rules, and **not** because it has to: `allow create` is client-reachable, but no device can write the `stock_adjustments` record and `stock_movements` entry that give imported units a recorded origin, since both collections are server-write-only |

App Check built-in providers cover Apple, Android, and web. Windows relies on
authentication, canonical authorization, rate limiting, and idempotency until a
tested custom provider exists. Enforcement is currently set on the public
password-reset endpoint only.

### Required tests

The frozen list is honoured: canonical platform-grant scans despite zero counters;
grant and invitation cannot race through `identityTransition`; abandoned identities
survive while a membership exists; exactly one owner per non-archived tenant; staff
operations retain an active principal; global disable proceeds but alerts; both
recovery paths restore an owner; verified users accept in-app without a token and
unverified ones cannot; token and tokenless acceptance cannot both complete;
suppression inspection is platform-only and audited; complaint clearing needs
stronger confirmation; password reset never reveals suppression; two cashiers on one
device get different receipts; counters are independent per device, tenant, and
date; confirmed open shifts do not block owner/manager switching while pending
checkout and cash-close do; mirror repair fixes routing without touching
authorization; Windows checkout survives restart using Hive; App Check is enabled
only for validated platforms.

---

## Working on this repository

### The emulator prelude is not optional

The machine's default `java` is JDK 17 and firebase-tools hard-fails on anything
below 21. Every emulator command needs this first:

```powershell
if (Test-Path Env:DEBUG) { Remove-Item Env:DEBUG }
$env:JAVA_HOME = 'D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8'
$env:Path = "D:\firebase-emulator-tools\node-v24.18.1-win-x64;$env:JAVA_HOME\bin;$env:Path"
```

`DEBUG` is cleared because this machine sets `DEBUG=release`, and Firebase treats
any non-empty value as debug mode, answering with complete environments and
enormous expected-denial traces.

### Standing traps

- ⛔ **Run the prelude, or you will diagnose your own machine wrongly — two consecutive sessions
  did.** `firebase-tools@15.24.0` requires Java **21 or above** and refuses before any emulator
  launches, and the machine default `java` is Temurin **17.0.20**. The JDK 21 it needs is the
  portable Temurin **21.0.12** under `D:\firebase-emulator-tools`, reached by the three lines in
  "The emulator prelude is not optional" three sections above. **The error names Java rather than
  the prelude**, which is what makes it read as a fact about the machine.
  ~~**No emulator starts on this machine at all** … the only JDK here is Temurin 17.0.20 … every
  trap below it is currently unreachable rather than fixed.~~ **Written 2026-08-12 by step 6a,
  repeated and escalated 2026-08-13 by step 6b, and withdrawn the same day when the product owner
  said the suites had run before.** They had; with the prelude all three pass first time. **This
  trap contradicted a procedure in its own file, and that is the second lesson: before writing a
  trap that says something is impossible, grep this file for the section that does it anyway.**
- ⛔ **The harness never deletes, so a `*-full` image can outlive the layout it shows.** A full-page
  capture is written **only when something is below the fold**, and a chunk that makes a route
  shorter can stop one being written — the file stays on disk showing the old rendering forever, and
  a hash comparison reports it as *unchanged*. The column-arithmetic chunk of 2026-08-15 shortened
  `13-staff-directory` past 900 pixels and left `web-full/13-staff-directory` behind; four others were
  already stale, one of them by two days. **Check `LastWriteTime` against the run, not the hash
  against the baseline**, and delete what the run did not write before quoting an image count. It is
  also why the "233 images" this file carried was four too high — see "Test baselines".
- ⛔ **A screenshot baseline is only comparable on the same side of midnight UTC.**
  `seedBusinessDate()` in `tool/screenshots/fakes.dart` derives from `DateTime.now().toUtc()`, so
  every seeded date on every screen advances when the UTC date rolls. On 2026-08-15 a chunk that
  touched fourteen panels compared against a baseline hashed forty minutes earlier and reported **58**
  moved images; six of them were two screens it never opened. **Regenerate the baseline from `HEAD`
  immediately before the comparison** — copy the changed files aside, `git checkout HEAD --` them, run
  the harness, restore, run it again — rather than reusing hashes from earlier in the session. It is
  two extra harness runs and it is the difference between a measurement and a number.
- **A local `emulators:exec` against `firebase.json` needs `functions/.secret.local`
  and `functions/.env.local`.** Five secrets and six string parameters have no
  default, so the emulator stops to ask and the run hangs silently after
  `Serving at port ...`. `run-dev-emulators.js` writes and removes both and refuses
  to overwrite leftovers from a killed run — delete them, and clear the ports.
- **The Auth emulator reserves three ports:** `port`, `port + 200`, `port + 400`.
  Dev 9099, invitations 9199, reconciliation 9699; a fourth may not use 9299, 9399,
  9499, 9599, 9899, or 10099. **Refined 2026-08-11**: all three suites were run while a held
  `emulators:dev` from the day before was still up, and they passed. What the collision
  actually looks like is two warnings rather than a failure — the invitation suite's **eventarc
  and Cloud Tasks** emulators default to 9299 and 9499, which is precisely what the held run's
  Auth on 9099 reserves, and firebase-tools moved them to 9300 and 9500 by itself. So a held
  run does not block a suite; it silently shifts two of its ports.
- ⛔ **Refined again 2026-08-15 by step 11, and the refinement is worse than the trap.** The
  shifting above is what happens to the *eventarc and Cloud Tasks* ports. **Firestore does not
  shift.** The reconciliation suite hit `Port 8280 is not open on localhost`, printed
  `Error: Could not start Firestore Emulator, port taken`, and **ran no test at all** — and the shell
  wrapping it still **exited 0**, because the last command in the pipeline succeeded. A caller reading
  the exit code would have recorded a suite that never executed as a suite that passed.
  **Grep the log for `ℹ pass N` rather than trusting an exit code**, and check `netstat -ano | rg
  ":8280"` first if a previous run was interrupted.
- ⛔ **Stopping a background test runner orphans the emulator it spawned.** The port above was held by
  a `java.exe` still listening after its npm parent was killed. Killing the wrapper does not kill the
  JVM, and the next run fails with a message about a port rather than about a process.
- **Never free a port by killing an emulator you did not start** — a held run may be
  holding seeded data. Read its command line; `--hold` is the tell. **The exception is an orphan you
  created yourself**, which is what the entry above describes; check the PID against a run you
  started before killing anything.
- **Do not run Gradle and the emulators together**: 2–3 GB free, and the Firestore
  JVM dies with a native `OutOfMemoryError`.
- **Use Flutter's own `adb`** at
  `C:\Users\BonifaceMasota\develop\android-sdk\platform-tools\adb.exe`; the one first
  on `PATH` is a different binary and the two servers fight.
- **The Android emulator needs `ANDROID_SDK_ROOT=D:\android-emulator-sdk`, or it will not
  boot.** Found 2026-08-08. This machine sets `ANDROID_SDK_ROOT` and `ANDROID_HOME` to
  `C:\Users\BonifaceMasota\develop\android-sdk`, whose
  `system-images\android-35\google_apis\x86_64\` directory **is an empty stub**; the real image
  holding `kernel-ranchu` is on `D:`. Without the override the emulator dies immediately with
  `This AVD's configuration is missing a kernel file!`, which reads like a broken AVD and is
  not. Override it **for the emulator process only** — Flutter's `adb` lives under the `develop`
  tree and is invoked by absolute path, so nothing else needs to move. Full line:
  `ANDROID_AVD_HOME=D:\android-avds ANDROID_SDK_ROOT=D:\android-emulator-sdk`, then
  `D:\android-emulator-sdk\emulator\emulator.exe -avd chilltent_api35 -no-snapshot-save
  -no-boot-anim -gpu swiftshader_indirect -memory 1536`. Boots in about 90 seconds.
- **`./gradlew --stop` after `flutter build apk`, before starting either emulator.** The daemon
  survives the build and holds enough that only ~1.5 GB is free; stopping it returns ~3.1 GB,
  which is what makes the Android and Firebase emulators fit together on this host.
- **Opening the soft keyboard scrolls the login form**, so a tap aimed at the password field can
  land on the sign-in button. That is not cosmetic: it submits with an **empty** password, which
  is its own defect (see "Found by using the app"). Screenshot between every field rather than
  between every chain, and re-read coordinates from the shot with the keyboard already open.
- **Staff invitation and password-reset email go nowhere locally.** The Brevo key
  `run-dev-emulators.js` writes is a placeholder, so `deliverStaffInvitation` fails with
  `EmailProviderError` / `safeCode: 'credential_link_unavailable'`. An identity **created by**
  its own invitation therefore cannot be onboarded on the emulators at all: tokenless in-app
  acceptance is correctly barred for it, and the token existed only in the mail that failed. To
  get a non-owner session locally, either invite an identity that **already exists and is
  already verified** (which makes `visibleAcceptanceAllowed` true), or write the membership
  directly with the Admin SDK and say so in the handover.
- **A cold emulator's first trigger delivery costs ~25 s**, every later one ~310 ms.
  Set timeouts from the first. **The reconciliation integration suite takes two to
  three minutes**, measured end to end on 2026-08-07 twice: 2 min 09 s with 66 s inside
  the tests, and 2 min 35 s with 93 s inside them. The "more than ten minutes" figure
  this file carried from 2026-08-05 is retracted; it was the stated reason for carrying
  that suite's count forward un-measured through three sessions. Backgrounding it is
  still fine and no longer necessary.
- **A held `emulators:dev` run may already be up. Check before assuming either way.**
  One was, from 2026-08-07 — `scripts/seed-dev-emulator.js --hold` on the dev ports —
  and by 2026-08-08 it had exited: `Get-CimInstance Win32_Process` for node and java
  returned nothing. **`functions/.env.local` and `functions/.secret.local` outlived
  it**, dated 2026-08-06, which makes them exactly the leftovers `run-dev-emulators.js`
  refuses to overwrite. They were left in place rather than deleted, because deleting
  another session's files to save a future one a command is the wrong trade. The
  reconciliation and invitation suites take their own projects, ports, and copy of the
  Functions build, so none of this affects them and all three emulator suites ran
  clean on 2026-08-08.
- **An integration-fixture `index.js` must not export a function whose require closure
  reaches `firebase-functions/params`.** Every `define*` without a default makes the
  emulator stop and ask at startup, which with no terminal to answer is a run that appears
  to hang forever after `Serving at port ...`. Both fixtures document this; the invitation
  fixture's seven exports and the reconciliation fixture's four were each checked against
  it. It is why the password-reset suite drives the worker **in process** instead of
  exporting `deliverPasswordReset`, whose closure reaches five parameters in
  `email/config.ts`.
- **An integration test that drives compiled `functions/lib` code must build its Admin
  handles from the Functions copy of firebase-admin**, through
  `createRequire(new URL("../../functions/package.json", import.meta.url))`. The two
  installs are the same version and different module instances, so a handle from
  `rules-tests/node_modules` fails `instanceof Timestamp` and mis-serializes `FieldValue`
  sentinels written by the other copy — as a wrong answer, not an import error.
- **`defineString(...).value()` outside a deployed function is just `process.env`**, so a
  parameter a test needs is set in the suite runner's `env`, beside its secrets. A test
  that must vary one holds the original and restores it in a `finally`.
- **Collection-page test fakes must** answer in ascending document-ID order, be keyed
  per business, be keyed per collection, and model the equality-filter contract in
  both directions. All four mistakes have cost a debugging cycle.
- **A fixed number of `Duration.zero` turns is not a wait.** Any test that drives the
  checkout pipeline over a real Hive box is waiting on real file writes dispatched to
  the IO thread pool, and their latency has no bound in event-loop turns. Probed 172
  times on 2026-08-07: median 3 turns to settle three writes, tail at 19 and at 26. A
  20-turn helper therefore failed about one full-suite run in seven and passed 15/15
  when the file ran alone. **Hold the future the work returns and await it**; where
  there is none — a rerun a worker schedules for itself with `unawaited` — poll a
  condition against a wall-clock deadline. Raising the turn count only moves the tail.
- **`TenantRouteGuard` reloads on a session change, not a rebuild** — a second
  `pumpWidget` into the same tree keeps the first answer, so tear the tree down
  between cases. Its `loading` widget replaces the whole subtree, so any panel that
  re-reads on a signal blanks unless it passes its last value as that widget.
- **Render the screen before diagnosing the screen**, with real fonts via
  `FontLoader` over `<flutter>/bin/cache/artifacts/material_fonts` — without them
  every glyph is a filled box. Set `debugShowCheckedModeBanner: false`, or read the
  banner as a clipped app-bar action. Two layout claims here were wrong and were
  settled in minutes by one rendering each.
- **A screenshot diff is only attributable against a same-day baseline.** Regenerating the
  set on 2026-08-11 moved **39 of 101 images** against a set generated on 2026-08-10, with
  no code change behind any of them: `tool/screenshots/fakes.dart` derives its business
  dates from `DateTime.now()`, because the daily summary and reconciliation compute a
  business date the same way and read by exact path, so a hardcoded date would render those
  screens permanently empty. `screenshots/README.md` says as much. **Every migration step's
  step 4 depends on this**: regenerate a baseline the same day, or a review sees dozens of
  moved images nobody touched. The way to attribute a change is to regenerate with it and
  again without it and hash both sets, which is how step 1 proved it moved nothing.
  **Confirmed from the other side later the same day**: the category-naming chunk regenerated
  against a baseline generated hours earlier and **all 101 hashed identical**, so the date drift
  really is the whole of the 39. Copy the set to the scratchpad before regenerating — those
  images are another session's untracked files — and hash the copy afterwards rather than
  trusting that nothing moved.
- **A capture case that taps without settling is a photograph of the frame timeline, not of the
  widget tree.** `31b-a-receipt-found` ends its `afterPump` with `tester.tap('Find receipt')` and
  no `pumpAndSettle`, so **anything that changes how many frames the binding pumps moves that
  image** while changing nothing a person would point at. The ripple kill moved it on 2026-08-11:
  the visible delta is the receipt field's **caret blink phase**, because a ripple in flight used
  to keep frames coming. Springs in step 3 will move it again. Two runs of identical code hash
  identically, so a moved image here is still attributable — but read what actually differs
  before attributing it to the thing you meant to change.
- **A widget test cannot measure text, and it will answer confidently anyway.** Found 2026-08-14. A
  plain `flutter test` renders without the Material fonts, so `RenderParagraph.didExceedMaxLines`,
  `getMaxIntrinsicWidth` and every `Text` size read from one are a fallback font's advance widths: a
  25-character `Disclosure` summary that needs **175** logical pixels reported **406** against 295
  available, and an assertion written on it failed against a string that fits comfortably. This is the
  standing "render the screen before diagnosing the screen" trap from the other direction — that one
  says a rendering settles a layout claim, and the missing half is that only a rendering **with fonts**
  does. The screenshot harness loads them through `FontLoader`, so a capture is the honest measurement
  and a widget test is not. **Assert a character budget beside the screen and measure the budget in the
  harness**; never assert an ellipsis, an overflow or an intrinsic width in a widget test.
- **A component with a one-line label needs a call-site budget, and `Disclosure` is the one that has
  one.** §5.2 gives `Disclosure` one collapsed line and the widget does not wrap, so a long summary
  ellipsises silently. About **32 characters** survive at §4.1's `compact` band —
  `Disclosure.summaryCharacterBudget` — and step 4 shipped a 41-character one on the reconciliation day
  page that nobody saw for two days, because **step 4's own `93-disclosure-*` matrix is `web` only**.
  The general form is the part to carry: a component state matrix photographed at one band is a matrix
  that has not been tested, and the states most likely to break are the ones a narrow screen creates.
- **A one-line budget measured on a page is not a budget in a dialog.** Found 2026-08-14, the day
  after the budget itself. `Disclosure.summaryCharacterBudget` is 32 and was measured at §4.1's
  `compact` band on a full-width route; an `AlertDialog` there insets itself from the window and then
  pads its own content, so a summary has roughly **200** logical pixels where a page gives it about
  **250**. `How a correction is checked` is **27 characters — inside the page budget** — and it
  shipped and truncated in the same chunk, caught only because that chunk was the first thing ever to
  photograph the dialog on a phone. `Disclosure.dialogSummaryCharacterBudget` is 24. **The general
  form is the part to carry**: a measurement is a measurement *of a container*, and a call site in a
  narrower one owes its own.
- **`scrollUntilVisible` stops when a widget is built, not when it is on screen — and a tap that
  misses does not fail.** Found 2026-08-14, twice on one route in one chunk. In the screenshot
  harness, `19-correct-a-product` had been tapping `Correct` at y≈912 in an 891-high viewport since it
  was written, so **every mobile capture of that case was a picture of the product list rather than of
  the dialog it is named after**, and nothing ever said so. In a widget test on the same route the
  same miss surfaced only as a later `findsOne` failing on the dialog's own text. **Follow it with
  `ensureVisible`** — and note that `scrollUntilVisible` drives one direction, so a capture case must
  act top to bottom: reaching back up for a control a `ListView` has already disposed leaves no
  `Scrollable` to drive and throws `Bad state: No element` from somewhere that names neither.
- **A glyph outside the Latin ranges is an asset, not a character, and this repository's fonts do
  not have one.** Found 2026-08-14 in a sentence and 2026-08-15 in a *control*. The bulk report
  writes a before/after arrow (`bulk_catalog.dart:1590`) and it renders as tofu in the harness's
  Roboto; the sign-in keypad's backspace key was `⌫` — U+232B ERASE TO THE LEFT — and its **entire
  face** was an empty rectangle in the first picture of it. Roboto's `material_fonts` cache carries
  neither. The Material **icon** font is loaded beside it and does, which is why the repair is
  `Icons.backspace_outlined` with a semantic label rather than a different character. **Whether a
  device shows either is still unknown** and does not change the rule: a string literal outside
  ASCII needs a picture before it ships, and a control whose only label is one needs an icon
  instead. `grep -nP "[^\x00-\x7F]" lib --include=*.dart` finds the class; the harness finds the
  ones that fail.
- **A call-site count that does not exclude comment lines is wrong.** `lib/config.dart` is a
  **fully commented-out file** and contributed 8 phantom buttons to two consecutive estimates in
  this file. Strip lines whose trimmed form starts with `//` before counting anything, and check
  whether the file's only importer is in the legacy island before counting it at all.
- **`flutter test` can be killed by memory pressure and it does not look like a test failure.**
  Found 2026-08-11: a full run exited `-1073740791` (`0xC0000409`, stack buffer overrun) part way
  through, while a `flutter run -d chrome` session and the held Firebase emulators were also up
  and free memory was under 2 GB. Nothing was wrong with the suite - killing the browser run and
  re-running gave a clean pass with no other change. **The same family as the Gradle trap above**:
  this host runs one heavy thing at a time.
- **An `ErrorWidget` in a `Row` reports a six-figure overflow, and the number is a decoy.**
  Found 2026-08-11. A build that throws is replaced by `ErrorWidget`, which is enormous, so the
  first symptom of *any* build-time exception inside a list of controls is
  `RenderFlex overflowed by 99200 pixels` — and the overflow is the loudest line in the log while
  the real exception scrolls past above it. **Read the first exception in the run, not the biggest
  one.** This cost a wrong diagnosis: the overflow was attributed to a `Flexible` in the widget
  being built, that `Flexible` was removed, and the actual cause was a throwing `AppTokens.of` in
  the same batch. Removing the `Flexible` then caused two further failures of its own.
- **`Transform.getMaxScaleOnAxis()` answers 1.0 for every 2D scale.** `Transform.scale` builds
  `Matrix4.diagonal3Values(s, s, 1.0)`, and the method takes the largest scale across all three
  axes — so **z pins the answer at 1.0** for any shrink. A press-scale assertion written on it
  passes against a completely static widget. Read `transform.storage[0]` instead. Found
  2026-08-11 after the widget was briefly believed broken.
- **A minimum-tap-target box must sit *inside* the gesture detector.** With the detector inside
  it, the extra area is reserved, laid out, painted around — and answers nothing. `getSize`
  reports the padded figure and a finger landing 2px inside the edge hits nothing, so a
  size-based §9 assertion passes against a control that fails §9. **Assert a tap target by
  tapping its edges**, never by measuring a box.
- **A gesture callback must not read `MediaQuery` or any inherited widget off `context`.** A
  pointer still down when its tree is torn down — a route popped mid-press, a held gesture
  released in a tear-down — delivers its `up` to a **deactivated** element, and the lookup throws
  "Looking up a deactivated widget's ancestor is unsafe". Read in `build` and hold the value,
  which also registers the dependency properly. Found 2026-08-11 by a screenshot capture, not by
  a test.
- **A `LayoutBuilder` cannot answer an intrinsic-width query, and `AlertDialog` asks one.**
  Dialog actions go in an `OverflowBar`, which measures intrinsics; so do `IntrinsicWidth`,
  `Table`, and `Row` with `CrossAxisAlignment.baseline`. A widget built on a `LayoutBuilder`
  inside any of them fails with a bare `hasSize` assertion naming **the dialog**, which is a long
  way from the cause. Found 2026-08-11 while fixing the overflow above.
- **`MouseTracker` asserts on a second simultaneous mouse pointer, and the damage outlives the
  test.** Two `PointerDeviceKind.mouse` gestures at once throws
  `(event is PointerAddedEvent) == (lastEvent is PointerRemovedEvent)`, and because the tracker
  lives on the **binding** rather than on the test, the next test in the same file fails too and
  looks unrelated. Multi-touch is fine — several `startGesture` pointers work — it is mice that
  are singular.
- **On Flutter web, a signed-in user's callables arrive with `auth: MISSING`, and the landing
  route then loads forever.** Found 2026-08-12, on the first run that has ever got *past* sign-in
  on web — the 2026-08-11 attempt never signed in, so this had never been reachable. Evidence, all
  from one run: the Auth emulator's seeded account shows `lastLoginAt` **newer** than `createdAt`,
  so the sign-in genuinely succeeded; then the functions emulator logs
  `"verifications":{"app":"MISSING","auth":"MISSING"}` for two back-to-back
  `listMyTenants` calls, finishing in 131ms and 5ms. The callable is reaching the emulator without
  an ID token, so it answers with nothing and `TenantRouteGuard` never leaves its loading state.
  **The seed script predicts this symptom in its own comment** — "presents in the app as a business
  list that never loads" — but attributes it to a short `TENANT_CURSOR_HMAC_SECRET`, which is not
  the cause here: the secret file was present and correct for the whole run.
  **`lib/dev/firebase_emulators.dart` is not obviously at fault** — it redirects Auth, Firestore
  and Functions at the same derived host in one place, and web correctly derives `127.0.0.1`. The
  open question is why the ID token is not attached to the callable, and whether this is
  web-specific or would reproduce on desktop. **Until it is answered, no device run on web can see
  a single migrated screen**, which is most of why the device-run debt reached nine chunks.
- **The emulator switch is debug-only by design, so `--profile` cannot reach seeded data.**
  `resolveFirebaseEmulatorTarget` throws `not_a_debug_build` when `kDebugMode` is false — a
  deliberate property, since a runtime toggle would be reachable from a shipped binary. The
  consequence is easy to walk into: profile mode is the honest build for judging motion, and it is
  exactly the build that cannot see the seed. **Judging `AppPageRoute`'s springs on web debug is
  worthless** — web debug drops frames by construction — so §6's motion can only be judged on a
  non-web debug build. That is a real argument for the Windows desktop surface, not a preference.
- **An interrupted `emulators:dev` leaves `functions/.secret.local` and `.env.local` behind, and
  the next run then refuses to start.** Hit 2026-08-12; the leftovers were from **2026-08-10**, so
  two days and several sessions passed before anyone tried again. The script writes both files for
  the run and removes them afterwards, and refuses to overwrite an existing pair so a real
  developer's secrets are never clobbered — correct behaviour that presents as
  `Refusing to overwrite existing Functions emulator configuration`. **Check before deleting, and
  check the right way**: both files are byte-identical to what the script itself writes, so compare
  against `run-dev-emulators.js`'s own string literals rather than eyeballing them. If they match,
  they are machine-generated placeholders holding no real secret and both are gitignored. If they
  do **not** match, they are somebody's real configuration and deleting them is unrecoverable —
  stop and ask.
- **Changing the shape of the widget tree above a stateful subtree is not free, and the cost never
  looks like the cause.** Hit twice on 2026-08-12, from opposite ends, and the general form is
  worth more than either instance. Inserting or removing a wrapper — a `Stack` on focus, a
  transition on push — re-parents everything under it. State survives only through a `GlobalKey`,
  and even then the subtree is deactivated, reactivated and **rebuilt**. What breaks is whatever
  was keyed to identity: a `TextField`'s platform input connection, a closure compared with `!=`,
  a controller captured in `initState`. **Both symptoms pointed somewhere else entirely** — seven
  failing assertions about `onChanged` and `maxLength` for the field, and four about
  `reader.queries.last` for the route, and not one of them named focus or transitions. If a
  widget stops accepting input or starts refetching after an unrelated visual change, look at
  what appears and disappears *above* it, not at it.
- **A field that takes focus and then refuses every keystroke has been re-parented.** The specific
  instance of the above, kept because the symptom is so misleading: `AppFieldWell` originally
  inserted its focus-ring `Stack` on focus, the way `PressSurface` does. Harmless for a button,
  fatal for a field. The fix is that the `Stack` is always in the tree and the ring appears by
  gaining a border. `PressSurface` still inserts its own and that is fine — a button has no
  editing state to lose — but anything else copying that pattern should not.
- **A route that offers a `delegatedTransition` re-parents the page below it, and that page
  reloads.** Found 2026-08-12. `ModalRoute.didChangeNext` sets `receivedTransition` when the
  incoming route offers one and the covered route's own does not match; `_buildFlexibleTransitions`
  then changes the **shape** of the tree above the page, so the page — which hangs off
  `route._subtreeKey`, a `GlobalKey` — is re-parented rather than updated, and a re-parented
  subtree rebuilds. Any panel that builds a closure in `build` and hands it to something comparing
  closures by identity then re-runs it. Here that is `TenantRouteGuard`, and the symptom is an
  extra Firestore read per push and per pop that looks like a test timing problem: four tests
  failed on `reader.queries.last` naming the *outer* panel's query. **A transition mechanism can
  cost a network read** — check the query log, not just the picture.
- **A `ThemeExtension` field named `type` breaks the extension silently.**
  `ThemeExtension` declares `Object get type` and `ThemeData.extensions` is keyed by it, so
  a field of that name makes `Theme.of(context).extension<T>()` answer `null` for ever while
  compiling cleanly — the analyzer reports only an `Information`-level "overrides an
  inherited member" hint. `AppTokens` reaches its type roles as `typography` for this reason.
  A second half to know: a `Theme` built from a fresh `ThemeData` rather than from
  `Theme.of(context).copyWith(...)` **drops every extension**.
- **Do not key a directory comparison on `FullName.Substring($root.Length + 1)`** when
  either root is an 8.3 short path — the scratchpad's is. `FullName` expands differently, so
  every relative key is cut at the wrong offset and the comparison reports that all 101 files
  changed. Key on `$_.Directory.Name` plus `$_.Name`. A comparison claiming *everything*
  moved should be suspected before the change is.
- **Do not revert a mutation with `git checkout -- <path>`** in a session that also
  edits that file. Hold the original in memory and restore in a `finally`.
- **A `.cmd` cannot be spawned from Node without `shell: true`** — it fails as
  `EINVAL` with no output. Call
  `node functions/node_modules/typescript/bin/tsc -p functions/tsconfig.json`.
- **`node --test` needs `--test-reporter=tap`** before its output is filtered; the
  default failure marker is `✖`, so filtering for `not ok` reports a silent pass.
  **`Select-Object -First N` terminates the upstream command** and reports a
  meaningless exit code — capture with `Out-String`, then filter.
- **Never filter an emulator run's stream; redirect it, then filter the file.** A
  `Select-String` pattern containing `Error` matched every expected
  `PERMISSION_DENIED` trace the rules suite produces and dropped the summary lines
  entirely — 115 KB of noise and no counts, from a run that passed. `npm ... *> $log`
  followed by a `Select-String` over `$log` is the shape that works, and the counts
  appear as `ℹ tests N` / `ℹ pass N`, not as `# pass N`, unless the TAP reporter is
  asked for.
- **Do not type a Unicode escape into a file this way.** A control-character escape
  intended for a validation test reached the source as a literal NUL byte; `file`
  reported the file as binary and `grep` for the surrounding text then found nothing.
  The editing tools cannot repair it, because the anchor would have to contain the
  byte — a small Node script replacing the line by index is the way out. Build such a
  character in the test with `String.fromCharCode(n)` instead. This is the standing
  `sed`-eats-`\u` trap from the other direction.
  **It has now happened seven times, six of them on 2026-08-08.** In `productBatch.ts`, where
  `productBatchRowUpdateId`'s digest separator was a literal NUL for a day — `grep` reported
  the whole module as "Binary file ... matches" and returned no lines from it, so the module
  was hiding from every search of the repository. In `productImport.ts`, whose
  `productImportRowIds` was written in the same shape the same way and acquired one of its
  own. In the *handover prose describing the first repair*, which acquired two. **In Dart, in
  `lib/inventory/catalog_management_panel.dart`**, where `_ProductEditDraft.fingerprint`
  joined its fields on a literal NUL: committed on 2026-08-07, unnoticed for a day while
  `grep` reported the 1,400-line catalog route as binary, and found only by running the check
  below over the files a chunk touched. And twice more in the prose recording *that* repair,
  once here and once in `HISTORY.md`. All are fixed and all read `\u0000` now.
  **The mechanism behind the prose ones is the part worth more than the count**: writing the
  six-character escape through a shell heredoc into a script turns it back into the byte,
  whatever quoting is used. Build it as `chr(92) + 'u0000'` and concatenate.
  **So it is not a `functions/` habit — it is whatever file is being written, prose
  included**, and the check below is the only thing that has ever caught one.
  **The failure is not "typing a test fixture" — it is writing any separator as a
  control character at all**, in source or in prose, and the escape has to be spelled out
  as six characters. **The check is cheap and should be habitual**: run `file`, or count
  `indexOf(0x00)`, over anything whose text mentions a control character, before committing.
  A repaired escape must stay the same character: turning any of these NULs into a space
  would change every audit ID that digest addresses, and for the Dart one it would change
  what a retained request ID is held against.
- **Do not rewrite a source file with PowerShell** unless the BOM is preserved; check
  `git diff` for a changed first line afterwards.
- **GNU `sed` eats `\u` in a replacement** — it means "uppercase the next character",
  not a Unicode escape, so a replacement carrying one loses it and still reports
  success. Fix a source line with the editing tools instead, and check the result with
  `cat -A` whenever the character in question is invisible.
- **Do not run `dart format` over a whole existing file.** The repository is not
  formatted with this SDK's line-breaking, so formatting a file to land a small
  addition rewrites unrelated blocks — it turned one 19-line test addition into a
  95-line diff. Format the file, keep the added block, and revert the rest; a
  formatter run afterwards still reporting only pre-existing blocks is the check.
  **Hit again on 2026-08-12 by step 6a, at twenty-five times the scale**, which is why this now
  reads as a prohibition rather than a caution: `dart format` over the whole change set turned
  **834 insertions and 123 deletions into 2,060 and 863**, with `checkout_cart_panel.dart` at
  124/124 for a one-line edit. **Do not run `dart format` across a change set in this
  repository at all.** Write the edit in the file's existing style; if you must format, format one
  file and revert every block the formatter touched that you did not. Recovering from it cost
  restoring 27 files from `HEAD` and re-applying every edit by hand — and `git checkout --` is
  blocked in this harness, so the recovery is `git show HEAD:<path>` written back over the file.
  **The check is the per-file line count**, not a visual scan: a call-site change that should be
  two lines and reports twelve is the formatter, every time.

### Repository state

`flutter analyze --no-pub lib test` reports **475 pre-existing issues**, measured again on
2026-08-11 and **one fewer than the 476 this file carried**, which is what commit `1b2b13b`
rewriting `lib/theme.dart` cost it. Analyse the paths a chunk touches. Where they actually
are, counted rather than characterised:

```text
323  lib/pos/**              legacy, read-only
 87  lib/screens/**          legacy, read-only
 47  lib/services/**         includes the two 788-line bulk upload/update services
  6  lib/api/**
  5  lib/widgets/**          pill_input, glass_card, pill_button - reachable from sign-in
  3  lib/pdf_preview_screen.dart
  1  lib/main.dart           the experimental Sentry profilesSampleRate warning
  1  lib/keyboard_scope.dart
  1  lib/constants/**
```

**Measured again on 2026-08-14 over `lib test tool`, at 475, unchanged — and on 2026-08-12 by step 6a,
also 475.** Nothing in
`lib/ui`, `lib/tenancy`, `lib/inventory`, `lib/reporting`, `lib/sales`, `lib/returns`, `lib/shift`,
`lib/audit`, `lib/checkout`, `test/` or `tool/screenshots` reports an error or a warning.

**`lib/theme.dart` now holds none**, and neither does `lib/ui/`, `test/ui/` or
`test/support/`. The legacy screens reference each other and nothing in `lib/main.dart` or
the tenancy shell reaches `lib/pos/**` or `lib/screens/**`, so those 410 are a closed
unreachable island; the other 65 are not, and `lib/widgets/**` is the set the sign-in screen
mounts.

`lib/main copy.dart` is a 48-line stray in `lib/` and should be deleted; it is noted
only so nobody mistakes it for a live entry point.

The Sentry DSN in `lib/main.dart` is an `http://` URL. Android blocks cleartext in
every build, so those envelopes have never been delivered from a device. The debug
network-security config deliberately does not cover it.

**That list was thirteen files long, and on 2026-08-11 the product owner had all of it
committed.** It is worth recording what it was, because the *shape* of it is a hazard this
workflow produces rather than an accident: `design.md`, `DESIGN-AUDIT.md`, `claude.md`,
`lib/ui/records.dart`, the harness, `docs/printer_transport.md`, three migrated panels and ten
test files sat in the working tree for a day while four consecutive chunks committed around
them. Nobody was wrong at any step — "stage only the scoped files" is what keeps a chunk
reviewable — but **work that arrives outside a chunk has no way of ever being committed under
that rule**, and it accumulated until it was 1,143 lines of code plus the specification the
committed work was being held to. Four commits closed it:

```text
1262476  design.md, DESIGN-AUDIT.md, claude.md, docs/printer_transport.md
64d27b1  tool/screenshots/, six files - the harness, without its output
2942214  lib/ui/records.dart, three panels, ten test files
   +one  .gitignore for the generated output, and this file
```

**Two things that were true of that list are now false and are corrected here.** The Flutter
baseline is no longer a measurement of a tree rather than of a commit — the eight tests that
made it so are committed, so **1598 is a clean checkout of `HEAD`**. And `design.md` is in the
repository, so the two corrections the token layer made to it are no longer carried by a
working tree alone.

**What is still local, and why each one stays that way:**

```text
.vscode/settings.json        editor settings, machine-local
android/gradle.properties    machine-local
pubspec.lock                 modified locally, not by any chunk here
prompt.md                    the session instruction, the product owner's own file
screenshots/                 generated - now ignored, see below
screenshots.zip              a 9.5 MB archive of the same output - ignored
.codex-*.png                 scratch captures from 2026-08-03 - ignored
```

**The generated screenshot output is ignored deliberately and the reason is in `.gitignore`
rather than only here.** `fakes.dart` derives its business dates from `DateTime.now()`, so
re-running on a different day moves about **39 of the images** with nothing behind them;
tracking the output would put those 39 into every future diff. The harness is tracked, the
output is not, and a baseline is regenerated the same day it is compared against. The set is
**221 images from 166 captures** since step 8's first half added the `97-stat-*` matrix at all three
bands, plus `web-full/26-sales-totals`, which is new because that page crossed the 1440 fold for the
first time. It was 208 from 154 after the catalog chunk added
`20b`/`20c`, and 200 from 150 after the reconciliation sweep added
`21b-product-stock-differences` at both screenshot viewports — the first picture of screen 21's
exception report, which every earlier capture of that route had missed because it opens a product with
no difference recorded against it. It was 196 from 148 after the shift chunk, and 195 from 148 after the
staff-directory chunk added `96-record-details` at three bands and `13b-staff-directory-editing` at two.
~~**The 39 was
re-measured on 2026-08-12 and it is still 39**~~ — **it is 32 as of 2026-08-14**, and it was 42 on
2026-08-13. The figure moves with which date-bearing screens happen to cross a fold at each viewport, so
treat it as "between about 30 and 45" rather than as a constant; what does not move is that it is
**every date-bearing screen and no others**. The 2026-08-14 measurement is the cleanest of the three,
because it came from a reverted regeneration that separated 32 drifted images from 14 attributable ones
in one comparison. It has been confirmed rather than carried twice now: the set was generated
twice the same day, once with the migration and once with it reverted, and everything outside the
migrated screen is identical. The 2026-08-12 measurement was the first of its kind — the route
chunk's set was generated twice and the two were identical across all 117 files — and the whole of
the day-to-day delta is the business date either way. **The two sweep chunks later on 2026-08-13
needed none of it**: each shared a day with the baseline before it, so drift was **zero** both times
and one regeneration settled each diff. The catalog chunk's was **0 added, 9 changed, 186
identical**, and all nine are its own three captures. **Step 8's first half shared a day with its
baseline too**: 13 added, 0 removed, 22 changed, 186 identical, and every one of the 22 is a screen
it edited — 25, 26, and the two strips at 13 and 21.

**The field chunk is the proof the rule works, and step 5a is the proof it keeps working.** The
field chunk's baseline was generated a few hours earlier the same day, so the drift was **zero** and
the diff was 10 added, 32 changed, 85 identical. Step 5a, four chunks into the same day, got the
same free baseline: **zero drift, 20 added, 85 changed, 59 identical** — and the 59 are the whole
check, because every one of them is a screen it deliberately did not touch. Step 6a, fifth on the
same day, got it again: **zero drift, 6 added, 51 changed, 113 identical**, and 49 of the 51 are
`web/`. **Five chunks on one day is the cheapest arrangement this harness has had**; each one after
the first compares against a baseline that costs nothing.

**Step 6b, alone on the next day, paid the full price and is worth reading as the counter-example.**
Its raw diff was 17 added and **45 changed**, of which three are the chunk. Establishing that cost a
second full regeneration with the migrated file reverted to `HEAD` — about two minutes — and it is
the only way the claim "three images moved" is a measurement rather than an assertion. **A chunk
that cannot share a day with its baseline must do this**, and the reverted run is cheap enough that
there is no excuse not to.

**The 2026-08-14 reconciliation sweep paid it too, and its numbers are the clearest statement yet of
what the drift costs.** Its raw diff against the shift chunk's baseline was 4 added and **46 changed**,
on four migrated screens. The reverted regeneration attributed **14** of the 46 to the chunk, so **32
were the business date** — screens 22, 23, 24, 26, 30, 31b, 32, 33, 34 and 35, none of which it
touched. That is the largest drift figure measured so far and it is consistent with the 42 the
2026-08-13 re-measurement found, since the two sets differ by which screens happen to cross a fold.
**It cost three regenerations rather than two**, because a defect the first set revealed — the
truncated `Disclosure` summaries — was fixed and the migrated set had to be generated again to compare
against the reverted one. Budget for that: a chunk whose pictures find something has to re-shoot.

---

## Next bounded chunk

~~**Nothing, until the JDK question is answered — and that is not a stalling tactic, it is the carry
rule.** … the next session's opening line is this question, not a step number.~~ **Retracted the same
day it was written.** There is no JDK question. All five baselines were measured on 2026-08-13 and
the carry counter is at 0 — see "Test baselines" and the withdrawn open decision for how two
sessions came to believe otherwise. **Nothing is gating the queue.**

**One instruction survives it, and it is the only thing worth carrying forward from the episode:**
**run the prelude before drawing any conclusion about this machine**, and if a suite refuses to
start, check "The emulator prelude is not optional" before writing anything down.

---

~~**The queued chunk is `design.md` §11 step 9 — sign-in and onboarding.**~~ **Done 2026-08-15, and
it was one screen rather than the eight §11 lists.** Screens 02 to 07 have been `AppScaffold` routes
since step 5a and screen 08 is one of the three full-page `Center` states §5.1 names
`LoadingState` / `ErrorState` / `EmptyState`, so the whole of the step was **01**. The six defects
this file listed were all real and all closed, including the **double border** the product owner
reported — the one defect in this repository a session was ever told to leave in place. See the
standing decision for the ten decisions, and for the three things it found that were not on any
list: this screen was the **ninth notice surface** and the sweep's own grep could not see it, one
of its branches **was never a refusal**, and its keypad's keys were **24 pixels wide** at §4.1's
`medium` floor under a boundary that named a declared constant.

**Its estimate was wrong in a new direction, and that is worth recording next to the five
mis-counts.** Every previous chunk this file over- or under-*counted*. This one it **mis-scoped**:
it described step 9 as `login_screen.dart` plus four widgets, which was right, while §11 says
"01–08" — so a session reading §11 rather than this file would have opened seven screens that were
already migrated and concluded the step was mostly done. **Both readings were partly wrong and
neither was checked against the code**, which is one command:
`grep -n "AppScaffold\|AppTextField\|AppButton" lib/tenancy/tenant_routing_shell.dart`.

**One chunk ran between step 9 and this queue entry and it was not a step at all**: `design.md`
**v0.4**, the product owner's own amendment to §2.1, §2.3 and §5.2 on 2026-08-15, plus a `Caps` key.
It is recorded as a standing decision rather than here, because a specification change is not a
migration step and re-queueing it as one would be wrong. **What it leaves for whoever is next** is
in the exclusions below: the chip radius, which §2.3 now guards alone; and the two §5.2 questions it
did not answer, hover and the `Callout` measurements, both still open.

~~**The queued chunk is `design.md` §11 step 11 — the copy pass against §8.**~~ **Done 2026-08-15,
and it found twelve defects against a list of seven.** All seven below were real; five more were not
on any list, and the two largest were among the five — **§8 rule 1's own worked example was still
being drawn on the landing route**, and the wire values were **ten sites across eight files** rather
than four on one screen. See the standing decision for the twelve, for the two judgement calls, for
the one defect the chunk introduced and a picture caught, and for the `•` suspicion the pictures
cleared.

**It is implemented rather than proved complete, and that distinction is the entry's own.** Seven of
§8's ten rules can be grepped and were; rules **2, 4 and 6** — *state what is true*, *the verb
persists*, *say what is still true* — cannot be, and instances of all three were walked into rather
than audited for. **§8 rule 8 is knowingly still broken on eight surfaces** and is a capability chunk,
not a copy one. So step 11 should not be called finished in step 12 without a pass that reads prose
rather than greps it.

~~**The next chunk is not obvious and this file is not choosing one.** What is left of §11 is step 5b
(a behaviour change), step 7 (the sale path, which now needs `AppSheet` specified first — a new open
decision), step 10 (still blocked on §12) and step 12 (blocked on six open decisions of its own). The
honest reading is that **the redesign is now gated on the product owner rather than on work**, which
is a different state from any this file has recorded before.~~ **Half of that gate lifted on
2026-08-16 and the reading was right about what it would take.** `design.md` **v0.5** replaced §4.4,
which makes **step 5b a visual chunk rather than a behaviour change** — the till is pushed, so the
step never reaches `checkout_draft`, `checkout_recovery` or `checkout_outbox` — and answers the
landing route's title, which was the last thing holding step 5a's remaining raw `Scaffold`. **Step 5b
is now the obvious next chunk**, and it is the first time since step 9 that this section can name one.

---

~~**The queued chunk is `design.md` §11 step 5b's second half — the persistent side menu.**~~ **Done
2026-08-16, and it finishes step 5b.** All three questions it queued are answered in the standing
decision: the maximum is measured against what is left after the menu, the menu scrolls on its own,
and a pushed route shows no menu. Both small items went in with it — the destinations are ordered by
frequency with the two account controls last, and `HomeNavigation` has its §5.1 row.

**Its own estimate was wrong in the same direction as five before it, and this time by a factor of
five.** It predicted "a screenshot sweep rather than a component… every migrated route's `web/` image
gains a 256-wide column, the largest single image diff since step 6". **Nine images moved**, six of
them the home and three of them the component's own captures, because the menu draws on one route
rather than 27. The prediction assumed the answer to its own third question, which is the thing this
file keeps doing: **a chunk that queues a question should not size itself as though it were already
answered.**

**What it found that was on no list.** The third question does not have the answer §4.4 assumes: a
live menu on a pushed route grows the stack a route per press, and the two repairs are the two things
forbidden here. That is an open decision now, above, and it is the one thing left of step 5b.

---

**The queued chunk is the end of step 4's sweep, headed by `receipt_lookup_panel.dart`.** It is the
only chunk on this page that needs nothing that does not exist: no new component, no `design.md`
answer, no product-owner call. Screen 16 is **the densest genuinely unswept file left** at three
`textTheme` reads, and behind it is the long tail of 35 files with one or two each — the platform
tabs, the staff gateways, `shift_panel.dart`, `sale_history_panel.dart`,
`return_history_panel.dart`, `audit_log_panel.dart` and the stock feeds. The list and its
measurement are below, re-counted 2026-08-15.

**Size it by reading the record models first, not by counting `textTheme` reads.** Four chunks in a
row found their real cost in a shared document rather than in a restyle, and the sweep's own three
lessons — a status on a migrated screen is a `RecordStatus` and not a loose `StatusBadge`; "does this
record have a standing" is answered both ways on purpose; a shared wording module is worth reaching
for the moment two surfaces render one document — are what the tail should be read against.

**The alternative, and why it is second rather than first**: step 11's copy backlog, the seven items
listed below. It is unblocked too, but **step 11 already ran** and this file cannot say which of the
seven it closed — the entry predates the chunk. Taking it means re-verifying every item against the
app before writing anything, which is the right way to take it and is not the same size of job as it
looks.

**What did not move**: step 7 still needs `AppSheet` specified and still needs three components that
do not exist — `QuantityStepper` (§5.1 priority **1**), `RollingNumber` and `ConfirmDialog` — which
is a larger build than "blocked on a spec" implied; step 10 is still blocked on the same three §12
calls, though **six of its eight assets are native and blocked by none of them**, and v0.5 gave two
of those six a host; and step 12 is still blocked on its own six.

**What the step-10 blockers were, kept because they are still true:**

- **Two of its eight assets are external and need product decisions nobody has made.** §12 asks *"Is
  there a character?"* and *"Who builds the Rive files?"*, and asset 7 is "business approval
  celebration, **character permitted**". Building it means answering the first by drawing something.
- **The tier system has no floor device.** §6.6 degrades motion by tier and §12 says outright:
  *"The tier system needs a named handset to test against. Everything in §6.6 is unverifiable until
  that exists."*
- **Four of the six native assets have no host.** Asset 2 lives on the shift banner, and **step 5b
  finishing did not give it one**: §4.4 says the shift control "is a persistent banner and is never a
  destination", and what ships is the shift *panel* in the home's body, exactly where it was. The
  banner is unbuilt and unspecified beyond that sentence. Asset 4 is `SyncIndicator` and asset 6 is
  `EmptyState`, both §5.1 rows that do not exist. Building an asset into a component that has not
  been specified is how a fourth empty state gets written.
- **Its two remaining assets are on screens that are done.** Assets 3 and 5 — the cash-count and
  reconciliation state machines — are the honest half of step 10, and they are two assets, which is
  not a chunk.

**Step 11 needs nothing that does not exist, and it already has a backlog this file has been
accumulating for four days.** Every item below was found by a chunk that could not fix it because
copy was not its number:

```text
bulk_catalog.dart:1590   the before/after arrow renders as tofu in the harness fonts
_summary                 "1 were corrected, 1 already hold this value" - no singular form
bulk report row labels   `Created` / `Corrected` shown by a preview, before anything exists
13c-staff-directory      badges read `active` and `pending` - the enum's own wire values
login-email placeholder  `example@spiritpos.com` - the product is Chilltent
login-email label        `Email / user ID` - step 9 fixed the case and left the words
screen 28's variances    a signed number is a bookkeeper's idiom, §8 rules 6 and 10
```

**The arrow and the backspace glyph are the same defect and step 11 owns both**, which is the
generalisation step 9 earned: **a glyph outside the Latin ranges is an asset rather than a
character**, and this repository's fonts carry neither U+2192 nor U+232B. Step 9 replaced its own
with `Icons.backspace_outlined`; `bulk_catalog.dart:1590` still has one. **Grep for the class rather
than the two known instances**, and take a picture before believing any of them:
`grep -nP "[^\x00-\x7F]" lib --include=*.dart`.

**Size step 11 by running §8's ten rules over the app rather than by trusting the list above**,
which is seven items and is certainly not all of them — that is the counting habit this file has now
been burned by six times.

**Steps 1, 2, 3, 4, 5a, 5b, 6, 8, 9 and 11 are all done.** Step 4's sweep is a class of thing rather than a
screen list, `AppNotice` closed the seven-surface item that had been queued as four, and step 9
closed the last surface with a palette of its own.

```text
step 6's twelve, all done:                        step 4's sweep so far:
13 staff directory   21 product stock             27 reconciliation status  - done 2026-08-14
17 read-only catalog 22 stock corrections         29 one reconciliation run - done 2026-08-14
18 manage catalog    23 stock movements           28 unresolved differences - done 2026-08-14
35 activity log      24 one product ledger        21 "Reconciliation found" - done 2026-08-14
30 shift corrections 32 shift history             17 read-only catalog      - done 2026-08-14
33 shift sales       34 returns on a sale         18 manage catalog         - done 2026-08-14
                                                  19 correct a product      - done 2026-08-14
                                                  20 bulk changes/import    - done 2026-08-14
                                                  25 daily summary          - done 2026-08-14
                                                  26 sales totals           - done 2026-08-14

step 8's five, all done:
25 daily summary          - done 2026-08-14 (StatLine, and the day's standing)
26 sales totals           - done 2026-08-14 (StatTile, StatLine, the tender split)
27 reconciliation status  - done 2026-08-15 (StatTile x2, the run cards' counts)
28 unresolved differences - done 2026-08-15 (StatLine, and a second rendering of one document)
29 one reconciliation run - done 2026-08-15 (the shared run card; no tile row, deliberately)
```

**What the three reconciliation screens actually cost, against what this file predicted.** The
prediction was "the `StatLine` right-edge alignment is what most of the work will be, and screen 29 is
the one candidate for a `StatTile` row". The alignment half was right. **The tile half was wrong on
contact** and is now a standing decision: 29's counts are all in the card it shares with 27, so a tile
row would state one figure twice at two sizes. The real cost was neither — it was **that screen 21
draws a difference inside a `Callout`, which takes a `message` and has no slot for a widget**, so
taking the figures out of the prose could not simply replace the prose. That is the fourth chunk in a
row whose cost was a shared document rather than a restyle, and this file's own instruction to check
the record models first is what found it.

**What is left of the sweep is a class of thing rather than a screen list, and both named sections
are closed**: every remaining permanent notice paragraph, every remaining multi-line explanation, and
every remaining status rendered as a word or a coloured `Text`. **Where to look, re-counted on
2026-08-15 rather than inherited**: `textTheme` is read in **39 files** across the migrated tree — the
figure this file carried was 37 and was measured over a narrower set of directories, so it is a
different count rather than a rise. **Almost all of the remaining reads are one or two per file**, and
the top of the list is the legend rather than the tail:

```text
checkout_cart_panel.dart        12   step 7, the sale path, excluded
bulk_catalog_panel.dart          4   swept 2026-08-14; the reads are captions and one headlineSmall
stock_adjustment_panel.dart      4   swept 2026-08-14; same shape
receipt_lookup_panel.dart        3   never swept — the densest genuinely unswept file left
...then 35 files with one or two each: the platform tabs, the staff gateways,
   shift_panel.dart, sale_history_panel.dart, return_history_panel.dart,
   audit_log_panel.dart and the stock feeds.
```

**The three reconciliation panels came off the dense end on 2026-08-15** and hold exactly one
`textTheme` read each — the in-body `headlineSmall` screen title, which is §7's queued defect and is
commented as such at all three sites. `sales_totals_panel.dart` and `daily_metrics_panel.dart` came
off on 2026-08-14 with step 8's first half.

**Step 8 no longer draws a boundary through this list**, because step 8 is finished. What is left is
the long tail above, and it is small enough to be an ending rather than a chunk — with the single
exception of `receipt_lookup_panel.dart`, which is a real unswept screen rather than a residue.

~~**A defect the step-8 chunk found and only half-fixed, which is a chunk of its own: §7's "Title
appears once".**~~ **Done 2026-08-15, and it was fourteen sites in fourteen files rather than the
thirteen this file listed** — `tenant_staff_directory.dart` was never on it, and
`sale_history_panel.dart` held two. `grep -n headlineSmall lib` over the migrated tree returns **two**
live uses now: screen 24's, which is not a duplicate and cannot reach the subtitle, and
`tenant_branding.dart`'s, which is a business name on a card rather than a page title. See the standing
decision for the rule, for the two judgement calls, and for the heading that turned out to be stating
something false. **The `PageHeader.subtitle` question step 5a deferred is answered**: moving a string
the screen already draws into the slot built for it is not the copy decision step 11 owns.

**A rule this chunk established that the rest of the sweep should follow.** §5.1 splits the two
components by what the prose is *for*: a permanent **helper** paragraph — always the same, true of every
record the screen will ever show — is a `Disclosure` and folds; a permanent **notice** — about the state
of this page, this read, this role — is a `Callout` and does not. It was read off the day page, which
step 4 had already decided this way, rather than invented; see the standing decision for the one
judgement call in applying it.

~~**Four items in the sweep are not sweep items, and they are one small model chunk together — and as
of 2026-08-15 they are the queued chunk.**~~ **Done 2026-08-15, and there were seven of them rather
than four.** `AppNotice` is in `lib/ui/status.dart` and the seven surfaces carry one: 27, 28, 18, 20,
and — never on this file's list — 21, 34 and 16. The eighth, `checkout-code-notice`, is in the sale
path and stays with step 7. See the standing decision for what the extra three were, for the four
branches that turned out never to have been refusals, and for why no picture in the harness had ever
shown a notice at all.

**The lesson this file predicted is the one it got.** It knew about one of these two days before it
knew about four, and about four a day before it knew about seven. The grep closed the gap each time,
and the one that works is `grep -n "\-notice'" lib` — the phrasing this file carried,
`grep -n "notice," lib/**/*.dart`, matches the *parameter* rather than the key and misses the two
panels that name theirs differently.

**Three things the sweep so far has learned.** First, a status rendered as a coloured `Text` on a
migrated screen is a `RecordStatus` now rather than a loose `StatusBadge`, so read the record model
before reaching for the component. Second, **"does this record have a standing" keeps being answered
both ways and that is the answer working** — member, product, shift, return and now a reconciliation
*run* carry one; audit event, ledger entry, correction, sale and now a recorded *difference* do not. A
sweep that adds a badge to everything with a state word in it would undo that. Third, **a shared
wording module is worth reaching for the moment two surfaces render one document**: that is **four**
chunks in a row where the real cost was reconciling vocabularies rather than restyling, and
`stock_movement_labels.dart` and `reconciliation_labels.dart` are the two that exist.

**A fifth, from the notice chunk of 2026-08-15.** When a `String?` on a screen carries a *meaning* the
type does not — success or refusal, this device or the server, already-true or forbidden — **the fix is
a named constructor per outcome, not a status argument.** `AppNotice.confirmed / .refused / .unknown /
.offline` are the four kinds this app's write boundaries already answer in, so a call site says what
happened; an `AppNotice(message, status)` at every call site would have reproduced, in statuses,
exactly the drift §1 describes in colours. The general constructor exists and is used **once**, in a
test.

**A sixth, and it is a counting habit rather than a design one.** This file has now mis-counted
**five** figures in a row from memory — 8 `IconButton`s that were 6, 4 notices that were 7,
13 title panels that were 14 sites in 14 files, 15 `headlineSmall` uses of which the remainder was
never re-grepped, and **233 screenshots that were 229**, because the count was taken over the
directory rather than over what a run writes and the harness never deletes. **Size a figure by
running its command at the moment you write it down**, and put the command in the entry so the next
session runs the same one. The notice entry carried a grep matching the *parameter* rather than the
key and would have found four of seven; the title entry carried a file list rather than a grep and
missed a file entirely; the image count had no command against it at all.

**A seventh, from the column-arithmetic chunk, and it is the strongest argument in this file for a
test that compares a claim to a rendering.** Two facts about this app were wrong in every head and
every document until a test asserted `measureWidth == getSize().width`: a button is **8 pixels wider
than §5.2's arithmetic**, because `PressSurface` reserves the focus ring whether it is visible or
not and §9's target is a minimum *width* too; and every string is painted **0.25px per character
wider than its token style**, because the theme merges Material's letter spacing underneath. Neither
is visible in a screenshot, neither is findable by reading, and both would have shipped as a
component that wraps when it was told there was room. **Where a component publishes a number about
itself, assert it against the rendering** — it is two lines and it is the only instrument that
answers.

**A fourth, from the step-8 chunk of 2026-08-15, and it is the one to carry forward.** A shared wording module stops two
surfaces wording one document differently; it does **not** stop them needing different *containers*.
Screen 21 draws a difference as a `Callout`, which takes prose; screen 28 draws it as a card, which can
hold a column of figures. The answer that worked was to keep both renderings in the one `switch` that
already owned the words, plus a test asserting every figure's magnitude appears in that kind's
sentence. **The answer that would not have worked is a second module**, and it was the obvious move
until the shape was in front of the code. Reach for the guard, not the copy.

**One thing to check before the next `Disclosure` goes anywhere, and it is now two figures rather than
one.** Its summary fits about **32 characters** on a phone on a full-width route —
`Disclosure.summaryCharacterBudget` — and about **24** inside a dialog —
`Disclosure.dialogSummaryCharacterBudget`. The budget is a call-site responsibility because the widget
will not wrap, and **the second figure exists because the first one was trusted in the wrong
container**: a 27-character summary, inside the page budget, shipped truncated in a dialog on
2026-08-14. Assert the length beside the screen against the budget for the container it is in; do
**not** try to assert the rendering, for the reason the standing trap gives.

**Three lessons the catalog chunk adds, all cheap to reuse.** First, **a widget-test overflow at a
narrow width is a reason to open the capture, never a measurement to design against** — two `Row`s on
screen 20 reported 73 and 45 pixels of overflow at 411, and the 411 harness capture with real fonts
showed the first fitting comfortably and the second genuinely cramped. Second, **`scrollUntilVisible`
is not `ensureVisible`**, in the harness as well as in a test; see the new standing trap and the
capture case it had been quietly breaking. Third, **check what a capture case's fake can actually
answer**: `FakeCallable` returns an empty map, which no strict decoder in this app accepts, so any
screen whose interesting state is behind a decoded server answer has never been photographed in it.

**Cost it from what the sweep actually took rather than from what this file predicts.** This file
over-predicted the same sweep twice and under-described it twice: the staff directory's "five
actions, two behind a menu, five test files" was really four, one and one; the catalog's "six
columns, the first real consumer of `inNarrowForm`, the second consumer of `details`" was really five
columns, no consumer and no `details`; the stock family's cost was not the record model but
reconciling three screens that worded one document three ways; and the shift family's cost was not
the standing question this file flagged — that took one lookup — but **three page-invariant
paragraphs that had been repeated per record**, which nothing in the estimate mentioned. And the
reconciliation sweep's cost was neither the components nor the prose but **one document worded two
ways**, plus a defect a picture found in a step that had already shipped. **And step 8's first half
cost neither the component nor the sweep but the arithmetic under the component** — a fixed minimum
tile width that was fine for two-digit counts and would have truncated every money figure — plus a
copy defect that only existed once the sentence was taken apart. **And step 8's second half cost
neither the figures nor the sweep but the *container* the same record is drawn in on a screen outside
the chunk** — screen 21's `Callout` takes prose and nothing else, so the prose could not simply be
replaced. Read what the screens *say* before assuming the work is shape rather than words, and read
what the screens *outside the chunk* do with the same model before assuming a rewrite is safe.

**Three classes of thing to expect, all drawn from what actually happened.** First, **a layout that
has only ever been laid out wide**: the staff directory's five inline forms were overflowing on every
phone from step 3 onwards and nobody had opened one there. Every screen since has asserted a record
at `compact`, which is two lines of test and is why it is worth doing. Second, **a value that is only
wrong once a table draws it**: a 13-digit barcode wrapped at an equal column share, a four-character
source ID took twice one, and a seventy-character payment caution made every row four lines tall —
`RecordAttribute.flex` is the knob for the first two and the third was a sentence in the wrong place.
Third, **a fixture that hides the case the component exists for**: `fakes.dart` gave every seeded
movement an `adjustmentType`, so no seeded record was ever silent about a column and no picture
showed §4.3's empty cell. Check the seed's shape against what the server actually writes before
believing a render. **The third class hit again on 2026-08-14 and in the harness rather than in the
fixture**: the seeded stock difference is filed against `pd-milk-500` while `21-product-stock` opens
`pd-bread-white`, so every picture of that route had photographed the branch where reconciliation found
nothing. **A conditional section that is invisible in every capture is not covered**, whatever the
tests say — check which seeded record a capture case actually opens. **It hit twice more on
2026-08-15, both in the fixture**: `seedReconciliationIntake` has always written
`invalidLineCount: 0`, so the day card's second stat tile had never been photographed at all; and the
three seeded differences happened to include no kind that carries a long paragraph *and* a figure,
which is the mixed case step 8 creates. **The generalisation is now four incidents wide and worth
stating as a rule**: before restyling a branch, grep the seed for the field that opens it, and if the
seed never sets it, add a capture case in the same chunk. Four chunks running have found the code
right and the seed narrow.

**The fifth incident is different in kind and is the one to generalise from.** The notice chunk of
2026-08-15 changed how seven surfaces report every write in the app, and **not one of the 225 images
moved by a single byte** — because a notice appears only *after* a write, and no capture case performs
one. It is not a narrow fixture this time: reaching one needs a form driven, a confirmation tapped and
a fake write boundary, which is three things a screen-level capture does not do by default. **So the
rule has a second half**: a chunk that changes what a screen says *in response to an action* has no
harness coverage at all until it adds a driven capture, however many pictures exist of that screen.
`18b-catalog-notice` is the first one in the repository, and `20b`/`20c` are the only other captures
that drive anything.

**A fourth class, new on 2026-08-14: a component matrix photographed at one band.** Step 4's
`93-disclosure-*` captures are `web` only, so nothing in 196 images had ever put a `Disclosure` on a
phone, and a truncated summary shipped and survived two days. `claude.md` hard rule 5 says every state
appears in the harness; it does not say at which width, and the states most likely to break are the ones
a narrow screen creates. When a component gains a narrow-band behaviour, its matrix wants
`everyBandViewports` the way `96-record-details` has it. **Step 8 took that instruction the same day**:
`97-stat-*` is at all three bands from its first commit, and the four pictures at 411 are what showed
that a fixed minimum tile width would truncate money.

**A fifth class, from step 8: a figure that only reads wrongly once it is beside its neighbour.**
Screen 26's `Sales: KES 4820.75 over 37 sales` was unambiguous as a sentence and became two adjacent
tiles both captioned `Sales`, one money and one a count. Nothing in a test could have caught it and
nothing in the sentence predicted it; **the first render of the new form is the check**, which is an
argument for taking the picture before writing the tests rather than after. **It recurred on
2026-08-15 as a missing gap rather than a wrong word**: with the figures lifted out of the day card,
the sentence saying what the unusable lines cost ran straight into the published-totals line below and
the two read as one paragraph. Nothing asserts a gap between two `Text`s and nothing ever will; the
capture is the only instrument for it.

**`inNarrowForm` has no consumer, the sweep is over, and that is now a finding rather than a
prediction.** It was predicted for the catalog, which had five columns rather than six; the stock
family's four columns all fit a card; the shift family's five and six fit too, because what a narrow
card is short of is *width* and every one of these values is short. **Twelve screens declined it.**
`DESIGN-AUDIT.md` §6 decision 2 conceded something no screen wanted. Two honest responses: leave it
as an unused parameter with this note against it, or take the concession back out of §4.3 and delete
the flag. **Do not delete it inside another chunk** — it is a documented concession in `design.md`
and removing it is a specification change.

~~**Four observations about the same arithmetic are carried, and the chunk that settles them now has
all twelve screens in front of it.**~~ **Done 2026-08-15, and the reason they were held back is the
reason the answer is not a retuned constant**: tuning a component constant from one screenshot of one
screen is how a component acquires a value that fits the last screen somebody looked at, so the
column asks the list instead. See the standing decision. **Two of the four are closed, one is closed
on the screen it was observed on, and observation 1 is improved rather than closed** — the outcome
per item is recorded against each below.

1. **`_actionsFlex = 3`.** At `expanded`, a record with four inline actions wraps its action column
   to three runs and makes that row three times taller than its neighbours —
   `web-full/13-staff-directory`. Screen 32's two long actions do the same at 1440 —
   `web/32-shift-history`. Step 6b set the constant against the two-short-action case, which was the
   only case it had. Honest fixes: the actions column earns a caller knob the way
   `RecordAttribute.flex` has one, or §4.3's `expanded` cell says something other than "all inline".
   **Improved rather than closed, 2026-08-15**, and neither of those was the fix. Three runs became
   two on the staff directory and one wherever the row has slack. It cannot become one *there*: four
   actions with real labels need ~630px, the other four columns need ~700, and the row is 1128.
   **Sizing the column to the widest set was tried on paper and rejected on the picture** — four of
   the five rows carry two actions, so that column would be 380px of nothing on 80% of the table.
2. **`_statusFlex = 2`.** The `Status` column is empty on five of screen 18's seven rows, so on a
   catalog it reads as a wide left margin — `web-full/18-manage-catalog`. Honest fixes: derive the
   share from the widest label the list actually carries, or read §5.2's "leading position" as
   leading *within* the identity rather than as a column. **Closed 2026-08-15 by the first of those**;
   §5.2's reading was not reopened, because it is written into the document and changing it is a
   specification change.
3. **`_identityFlex = 3`.** With four attribute columns and an actions column it leaves the identity
   roughly a quarter of 1200, and `Recorded 2026-08-10 08:30 UTC by Grace Wanjiru (owner-dev)` wraps
   to two lines on every row of `web/23-stock-movements`. **Not a §5.2 failure** — "never truncated
   below two lines" governs the identity and nothing is truncated — which is why it is an
   observation. Honest fixes: a caller knob, or the provenance line takes a column of its own, which
   step 6b refused on the grounds that a column of near-identical timestamps is width spent on
   nothing. **Closed 2026-08-15 on the screen it was observed on** — the identity asks for its
   provenance line's full width and `web/23-stock-movements` now fits it on one line on every row —
   and **still open on `web/30-shift-corrections`**, which is six columns and out of room. Neither
   named fix was used.
4. **`_RecordTable` puts no gap between its cells at all**, which the shift family surfaced and which
   is the same family as the other three. At six columns a value ends where the next begins:
   `web/30-shift-corrections` reads `A late sale arrived after|Corrected from expectation` across the
   `Reason` / `Evidence` boundary. **It is not new code's defect** — `web/23-stock-movements` runs
   `Before and after|Adjustment type|Reason` together in its header row in exactly the same way, and
   has since the stock chunk. Honest fixes: a `space.12` gap between cells, or column shares derived
   from content. It is carried with the other three rather than fixed because a gutter changes every
   column's effective width on all twelve screens, which is precisely the arithmetic the other three
   are about. **Closed 2026-08-15 by doing both**, which is why they were one chunk: the gutter costs
   width the derived shares had to find.

~~**All four are one chunk's work now**~~ — **and they were, on 2026-08-15.** The constants were all
measured against a two-column activity log while the twelve screens carry two to six, which is the
sentence the whole chunk turned out to be about.

**`Pagination` has now been examined and declined four times, and the reasons differ.** The staff
directory's pagination is one sentence — not one of `DESIGN-AUDIT.md` §2.3's four idioms. **Screen
18's `Previous` / `Page n` / `Next` row is one of them**, so the catalog chunk declined it on a queue
position instead: §5.1 has `Pagination` at priority 3 and it is not step 6's. **All four stock
screens and all four shift screens carry a `Previous page` / `Next page` pair**, which is another,
and both chunks declined it on the same ground. **The sweep is over and it is still excluded**, so
the next session to meet one of those rows must say what it is doing rather than let a `Pagination`
arrive with something else.

~~**The four carried observations about `RecordList`'s column arithmetic are the chunk**~~ — **done
2026-08-15, and they were one chunk exactly as predicted**, for the reason predicted: they need all
twelve screens in front of them. ~~**`design.md` §11 step 9, sign-in and onboarding, is now the queued
chunk**~~ — **also done 2026-08-15. `design.md` §11 step 11, the copy pass, is now the queued chunk**
and is described at the top of this section, together with why step 10 is not.

**Five things are genuinely finished and should not be re-queued.** `design.md` §11 step 8: all five
of its screens are done, §2.2's own complaint is retracted for every one of them, and the only figure
on those screens deliberately left in prose is a revision number, which has a standing decision against
it. **The notice-status model**, which was queued as four items and turned out to be seven; the eighth
is `checkout_cart_panel.dart`'s and belongs to step 7. **§7's "Title appears once"**, which was
queued as thirteen panels and turned out to be fourteen sites; the two `headlineSmall` uses left in the
migrated tree are both deliberate and both commented at the site. And **the four `RecordList`
column-arithmetic observations**, closed as one chunk — with observation 1 improved rather than closed
and the reason recorded against it, so that a later session does not re-queue it as an oversight.
And **step 9**, which is one screen and is done: `DESIGN-AUDIT.md` §4.4's three defects, §2.2's
`UNLOCK REGISTER`, the two `Colors.*` literals, the double border, the notice model and the keypad's
tap targets. **Screens 02–08 are not an unfinished remainder of it** — 02 to 07 were migrated in
steps 3 and 5a, and 08 is an `ErrorState`, which is a component question rather than a screen one.

**The batch is a deliberate relaxation of `claude.md` hard rule 4, granted by the product owner on
2026-08-12 and scoped to steps 4, 5a, 6 and 8 only.** All four pieces of step 6's own half were taken
on their own, each because it fitted one session: step 4 first because `StatusBadge` is
used by 6 and 8, then 5a because 6 and 8 both sit inside the page frame, then 6a because the
breakpoint rewiring is what §4.2 and §4.3 both stand on, then 6b because §4.3 is a model rather than
a restyle. The exception is a permission to batch, not an instruction to, and splitting on the
boundaries it names has cost the batch nothing four times running — **nine**, counting the sweep's
four chunks and step 8's first half, which are one step's own sweep rather than further boundaries.
The rule stands everywhere
else: step 7, step 10 and steps 11–12 are one number each — **step 9 was taken on its own under it on
2026-08-15 and cost nothing by being** — and **5b (the navigation model) was
not in this exception** either; v0.5 later made it a visual step, and it was taken on its own in two
halves on 2026-08-16. **The exception is now fully
spent and should not be invoked again**: steps 4, 5a, 6 and 8 — every step it named — are finished as
of 2026-08-15. Its last act was the catalog chunk's ruling that **step 8 takes the step-4 sweep of its
own five screens with it** rather than those screens being swept now and restyled later; the first
half honoured that on 25 and 26, and the second half inherited nothing to sweep, because 27, 28 and 29
had been swept the day before. **Ten chunks were taken under it and every one of them split on a
boundary the exception permitted it not to.** Everything left — 5b, 7, 10, 11, 12 — is one number
on its own under the unrelaxed rule, and step 9 was the first to be taken that way. **Step 11
followed on 2026-08-15 and step 5b on 2026-08-16**, the latter in two halves that are one number
between them; **7, 10 and 12 are what "everything left" now means.**

**The product owner chose the composition layer over the web callable-auth defect on 2026-08-12,
and the step-4, step-5a, step-6a, step-6b and both sweep sessions all checked that choice rather than
inheriting it.** The defect still cannot be settled either way. **The Windows route
was last checked in step 6a and was shut**: `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock` has no
`AllowDevelopmentWithoutDevLicense` value at all, so Developer Mode is off and
`flutter run -d windows` still cannot link its plugins. ~~**Android is now shut for a second,
independent reason**: the emulators it would run against cannot start at all on this machine.~~
**Retracted 2026-08-13 with the rest of the JDK claim.** The emulators start; step 6b ran all three
suites against them. **Android is shut for the one reason it always was** — the resource conflict:
Gradle and the Firebase emulators together kill the Firestore JVM with a native `OutOfMemoryError`,
and a held `emulators:dev` run must not be killed to make room. And **the source settles nothing**: every callable in the migrated tree
goes through `FirebaseFunctions.instance` with no platform branch anywhere, so the client is
byte-identical on web, Windows and Android and the difference, if there is one, is in the emulator
transport rather than in this repository.
**So the instruction stands unchanged for the next session**: if it reproduces off web, the app is
broken past login for every user, that outranks any reskin step, and the session that establishes
it should propose the fix instead and say so in its opening line.

**Two questions for the product owner, both from step 4 and neither decided inside a chunk.**
§5.2 names exactly two icon sizes — `AppButton`'s leading icon at 18 and `StatusBadge`'s at 14 —
and specifies none for `Disclosure`'s info glyph and chevron or for `Callout`'s glyph. All three
take 18 as the nearest named row. And **`Callout` has no specification at all**: §5.1 gives it a
row and §5.2 does not cover it, so every measurement it uses is borrowed from a §2 row. Either
§5.2 gains a `Callout` paragraph and an icon-size row, or it gains a sentence saying the borrowed
rows are the specification. **This blocks calling §5's inventory complete in step 12**, the same
way the field-hover question blocks §9's audit.

**One question is left from step 5a, it is the older and larger of the two it raised, and step 6b
has now met it rather than anticipated it.** **§3's
density has no rule this code can evaluate** — it is a width test *and* an input test, and nothing
in Flutter honestly answers "is this a pointer device". §3's own table gives `density.compact` to
"catalog, ledger, reconciliation, activity log, staff — at ≥1024", and `RecordList` now draws a
**table** at exactly that floor on exactly those screens. So the screen shape §3 wrote the compact
density for exists, and it is still comfortable: 64-high rows where §3 offers 40, 48dp actions where
§3 offers 32. **Answering it is now two constants and a wrapper.** It has its
own entry under "Open decisions" and it is the largest single thing standing between this app and
§3. **Step 8 was the last step that would have used it and did not need it**, so it is no longer
waiting on a step — it is waiting on the product owner, or on step 12's audit meeting it.

**Its companion is closed.** `design.md` still states no page padding, but the three routes that
padded 24 now pad `space.20` with everything else, so the question is a naming gap rather than an
inconsistency. Step 6a also found this file's own description of it wrong: there were **three**
routes and the landing route was not one of them.

**Explicitly excluded from the queued step-11 chunk.** A copy pass reaches every string in the app,
which makes it the chunk most likely to become a rewrite of whatever it is reading; everything below
is a neighbour. **New to this list on 2026-08-15**, and the first three are step 9's own leavings:

- **`pill_input.dart`, `pill_button.dart` and `glass_card.dart`**, which nothing imports and which
  should be **deleted**. Step 9 tried and its tool permissions refused, exactly as they refused the
  five stale screenshots. They are dead rather than excluded — a session that can delete a file
  should take these three with whatever it is doing, and `flutter analyze lib/widgets` reporting
  five issues in three files nothing reads is the tell.
- **`enableInteractiveSelection`**, which `PillInput` set to false and `AppTextField` does not
  offer. A person can now select the text in the two sign-in fields, as they can in every other
  field in the app. If that turns out to be wrong on a till it is a component change and not a copy
  one.
- **The `Enter` key on the sign-in keypad**, which is drawn disabled because it does nothing.
  Wiring it to submit is a behaviour change; dropping the key is a product decision. Neither is
  step 11's.
- **Observation 1's remaining wrap** — a four-action record on a five-column row at 1128 still takes
  two runs, the arithmetic for why is recorded above, and the only remaining fixes are §4.3 or §5.2
  amendments; **the ambient `letterSpacing` the theme merges under every token role**, which has its
  own open decision and would move every string in the app; **the checkbox outline's 1.97:1**, which
  has an open decision of its own and needs a §2.1 role that does not exist; and **the five stale
  `*-full` screenshots**, still not deleted for the same reason.
- **New with `design.md` v0.4, 2026-08-15**, and all three are leavings rather than defects:
  **the chip radius**, which is now the only thing §2.3's "when everything is a pill the shape stops
  signifying" argument is guarding — a chip is `StadiumBorder` in the theme where §2.3 says
  `radius.sm`, so the argument and the code disagree on the one row that still carries it, and
  closing that is step 4's leftover rather than a copy pass's; **the sale path's two fields**, which
  now read a `radius.pill` `surface.field` `inputDecorationTheme` and so *look* right while still
  being Material fields with none of §5.2's label, helper, counter or error behaviour — step 7's,
  and the theme change makes that easier to forget rather than harder; and **the 24 fields that
  declined a leading icon**, which is a judgement per field and should be revisited by somebody
  looking at the forms rather than at a list.

**Inherited, and still excluded:** **`inNarrowForm` and `StatRow`'s own unused
capacity** — neither is a knob any
screen has asked for and deleting either is a specification change;
**the three run counts nothing displays** (`metricsProcessed`, `productsProcessed`,
`shiftsProcessed`), which are an open decision about content rather than a rendering;
**screen 28's uncoded money figure**, which needs a `configuration/checkout` read and is therefore a
capability chunk, not a restyle — both are new to this list on 2026-08-15 and both have entries under
"Open decisions";
**`RecordList` for screen 28's difference cards and screen 20's report cards**, because neither is one
of the twelve screens step 6 names and migrating either would be step 6 work outside step 6's list —
**and note that both would now inherit the measured column arithmetic for free**, which is a reason to
do it one day rather than a reason to do it inside another step;
~~**the two copy defects the bulk report's first picture found** … both of which are §8 and therefore
step 11's; **the past-tense row labels** `Created` / `Corrected` …~~ **These three stop being
exclusions the moment step 11 is the chunk, and they are now listed under it above** — the tofu
arrow at `bulk_catalog.dart:1590`, `_summary`'s missing singular, and the past-tense row labels a
preview shows before anything exists. **`AppSelect`'s rendering on
screen 21**, where the three adjustment-type labels draw as three white rectangles — it is present at `HEAD`
and therefore step 3's, not the sweep's, and `web/92-appselect-open` compounds it by cutting off above
the select so that component's own matrix has never photographed one; **the four carried `RecordList`
observations above**, unless taken deliberately as their own
chunk, because a gutter or a changed column share moves every one of the twelve migrated screens and
a status sweep should not be carrying that diff;
`checkout_cart_panel.dart`'s 7 buttons, 2 fields and 1 `InkWell`
and the whole sale path, step 7 — **note that step 6a touched one expression in that file**, the
till's breakpoint, which §4.1 named as its own and which is not a licence to touch anything else
there; `ConfirmDialog`, which left step 4 for step 7 on 2026-08-12;
~~`pill_input.dart` and sign-in's visual design, step 9~~ — **done 2026-08-15**, and the note that
went with it is now history: step 6a rewired `isMobile` and nothing else, and step 9 deleted
`isMobile` outright; **`Pagination`**, §5.1 priority 3, whose four idioms sit on the very screens the
sweep touched and which is the thing a sweeping session will be most tempted to fold in;
the remaining `IconButton` call sites, which have
no component yet — **the count is 6, and the 8 this file carried was wrong in the exact way its own
standing trap describes.** `lib/config.dart` is a fully commented-out file and contributed the other
two; excluding it and the legacy island, what is left is
`checkout_cart_panel.dart` (2, step 7), `return_history_panel.dart` (2), `platform_tenant_review.dart`
(1) and `tenant_routing_shell.dart` (1). It was 13 before the staff directory's 5 became
`RecordAction`s, which are the first that `RecordActionSet` took; **no catalog, stock or shift screen
carried one inside a record**, and `return_history_panel.dart`'s two are the quantity steppers in
screen 34's record-a-return *form* — they are `QuantityStepper`'s, §5.1 priority 1, which does not
exist. **Re-count before quoting this**, and strip commented lines when you do;
**the unit cost as a catalog column**, which is
new to this list and is a *permission* boundary rather than a taste one — a manager may stock the
catalog and may not be shown what the business pays, so a column that appears for an owner and not a
manager is a role-dependent record model and is not a restyle; the **navigation model**, step
5b, which `DESIGN-AUDIT.md` decision 3 splits out
as a behaviour change needing a device check, **and the landing route with it** — step 5a left that
route's `Scaffold` alone because which string is its title is a product question, see the standing
decision; the three full-page `Center` states in `tenant_routing_shell.dart`, which are
§5.1's `LoadingState` / `ErrorState` / `EmptyState` and have no component yet;
`pdf_preview_screen.dart`, which is legacy-adjacent and has no title;
every server file and `firestore.rules`; deployment;
and every standing exclusion below.

~~**One exclusion is not a choice any more and should not be listed as one.** Every server file and
`firestore.rules` … are now excluded by *circumstance* as well, because a chunk touching them must
re-measure three suites that cannot run.~~ **Retracted 2026-08-13.** Those three suites run, and were
measured the same day. **Every server file and `firestore.rules` are excluded by choice, exactly as
they have been for seven chunks**, and a chunk that wants them is free to take them — it must
re-measure, and re-measuring is a matter of running the prelude first.

**Two things to delete when their moment comes, so they are not inherited silently.**
`test/support/buttons.dart` and `test/support/fields.dart` exist only because `lib/` holds more
than one button and field system. ~~Step 7 takes the last `ButtonStyleButton` and two of the last
three `TextField`s; step 9 takes the third.~~ **Step 9 took its half on 2026-08-15**, so the only
thing keeping either file alive is `checkout_cart_panel.dart` — 7 buttons and 2 fields, step 7's.
When that lands, both files should be deleted and their callers pointed at `AppButton` and
`AppTextField` directly.

**Three files in `lib/widgets/` are dead and should go with them, sooner.** `pill_input.dart`,
`pill_button.dart` and `glass_card.dart` have no importer as of 2026-08-15. They are not a step 7
dependency and nothing is waiting on them; the only reason they are still on disk is that step 9's
tool permissions refused both `Remove-Item` and `git rm`.

**`test/support/notices.dart` is not one of them and should not be swept up with them.** It was added
2026-08-15 and reads `Callout`, which is the destination rather than a stop on the way to one; its
own doc comment says so, because a later reader deleting "the `test/support` seams" would take it too.

**App Check was passed over an eighth time**, on the same fresh instruction the sixth was: the
product owner asked on 2026-08-12 for the redesign to be run through to the end of its visual steps
without stopping, and named 5b and 7 as the two that stay out. App Check is still **the only queued
item that would move a red row**, and it is still at the head of the preference order below. It
should be taken the moment the redesign's visual steps are done — **and that moment is closer than
it has been**: with 9 finished and 10 blocked on three §12 decisions, what is left of the redesign
is one copy pass and one accessibility audit.

~~**One defect is queued against step 9 rather than fixed, and the choice was the product owner's.**
Every login field has drawn **two borders** since commit `1b2b13b` on 2026-08-10 …
**It is the only known defect in this repository that a session was told to leave in place**, which
is why it is named twice.~~ **Fixed 2026-08-15 by the step that was told to fix it.** `PillInput` is
gone; both fields are `AppTextField`s over an `AppFieldWell` that strips all six border slots and
sets `filled: false`. **What the repair added that the original diagnosis did not have is a test
that would have caught it**: `test/login_screen_test.dart` now pumps this screen under `spiritTheme`
rather than a bare `MaterialApp` and asserts every slot, because the whole mechanism of this defect
is a theme reaching past a widget's own `border`. **No other screen in the app was ever affected** —
the till's two unmigrated fields sit in no well and take the theme's single outline correctly.

**A question for the product owner, from step 3 rather than step 4.** §5.2 specifies a field's
rest, focus and error treatments and **says nothing about hover**. `AppTextField` therefore has no
hover treatment and `92-appfield-hover` is a capture of no change at all. Either §5.2 gains a row
— a `surface.raised` well on hover would be the obvious one, and is *not* being applied without
being asked for — or it gains a sentence saying a field has no hover state and the harness capture
stands as documentation. **Do not decide this inside a chunk.**

**A device run was attempted on 2026-08-11 and got half way, which is worth recording so the next
session does not repeat the dead ends.** The app **builds and runs on Chrome** against the live
emulators — `flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true`, Hive boxes opened,
the Auth emulator connected — and the **unmigrated sign-in screen was seen on a real run**, which
confirms `DESIGN-AUDIT.md` §4.4 from the outside: uppercase field labels, a pill-radius well where
§2.3 says 8, and a green glow where §9 wants a 2px ring. **The migrated landing route was not
seen**, because sign-in could not be driven: synthetic clicks and `SendKeys` do not reach Flutter
web's input layer, so the form cannot be filled programmatically. Three routes to a real run, in
preference order:

- **Windows desktop is one system toggle away and is the best surface for this chunk** — it has a
  real mouse for hover and a real keyboard for the focus ring, which are two of the three states no
  screenshot can show. `flutter run -d windows` currently fails with *"Building with plugins
  requires symlink support. Please enable Developer Mode"*, which is a machine setting nobody
  should flip on the product owner's behalf.
- **Chrome works and needs a human to type.** The app is reachable; sign in as
  `owner@example.com` with the seed script's password and the landing route is two clicks away.
- **Android is blocked by a resource conflict, not by tooling.** A held `emulators:dev` run with
  seeded data was up (`seed-dev-emulator.js --hold`), free memory was **2.1 GB**, and the standing
  trap says Gradle and the Firebase emulators together kill the Firestore JVM with a native
  `OutOfMemoryError`. Killing a held run to make room would destroy another session's seeded state,
  which the traps forbid. Either stop the held run deliberately first, or run Android on a machine
  that is not also serving the emulators.

**The title chunk adds the item with the largest visual diff and the smallest question.** Fourteen
routes lost a heading and five gained a header subtitle, which is 52 images and every back-office
screen in the app. **What a screenshot cannot settle is whether the page now opens too high**: a route
that used to start with a `display` title, a gap, and an `H1` now starts with the title and the
content, and whether that reads as tightened or as abrupt is proportion on a real screen. **Open three
or four back-office routes on a phone**; if it reads as abrupt the honest fix is `density.sectionGap`
between the header and the body rather than restoring a heading, and that is a §3 amendment.

**Its second item is one word.** The staff directory now shows `Read-only staff directory` as an
`info` `Callout` **only to a session that can change nothing** — where it was a heading every role
saw. A cashier or manager should read it and understand they are looking rather than failing. Open the
directory as a manager and say whether the blue-grey block at the top of the page reads as an
explanation or as a warning.

**The notice chunk adds the item that touches the most surfaces and needs the least equipment.** Every
write in the back office now answers in colour as well as in words: green for a category added, red for
a refusal, amber for an unknown outcome, blue-grey for offline or already-true. **Chrome is enough** —
add a category, then add it again; publish the currency that is already published; try to correct a
product with the same values it holds. **What to judge is whether four notice colours on one screen
read as a system or as a traffic light.** The four branches that turned out never to have been refusals
are the ones to look at hardest: a blue-grey "That is already the published currency" is a claim that
nothing is wrong, and if it reads as a shrug rather than as reassurance, the honest fix is `ok` for
those four — which is a `design.md` question about whether "already true" is a confirmation, not a code
change.

**Step 8's second half adds the item that is cheapest to check and most likely to be wrong**, and it
is a wording judgement rather than a layout one. Screen 28 now states a shift's difference as
`Sales total -12.5` and `Transactions +2`, where it used to say "its sales total is 12.5 short and its
transaction count is 2 over". **A signed number is a bookkeeper's idiom, not a shopkeeper's** — and
this app's own §8 rule 10 forbids implying mutation and rule 6 asks a message to say what is still
true, both of which are about reading like a person rather than a ledger. The direction is spelled out
in words under each figure, so nothing is carried by the sign alone; the question is whether the
figures now read as *evidence you can compare* or as *a spreadsheet somebody pasted in*. **Open the
differences list against real data** and read the shift rows. If it reads as a spreadsheet, the honest
fix is that a variance keeps its magnitude and drops the sign, with the direction word doing all the
work — which loses column comparability and is a `design.md` question before it is code. **The same
figure also carries no currency code**, which §8 rule 8 forbids outright; that one is an open decision
with a named fix rather than a judgement.

**The column-arithmetic chunk adds the item that most needs a wide screen and least needs a device.**
Every table in the back office was re-divided: the status column shrank to its badge, the identity
grew, and the actions column takes the spare width. **Chrome is enough** — open the staff directory,
manage catalog, and stock movements at a full window and at 1024. Two things to judge. First,
**whether a column that is exactly as wide as its content reads as tidy or as ragged**: the columns no
longer line up on a grid, they line up on what they hold, and a table whose `On hand` column is 60
pixels wide next to a `Reason` column of 400 is either legible or lopsided. Second, **the staff
directory's four-action row still wraps to two lines** and the arithmetic says it must; whether that
row reads as an exception or as a defect is a judgement about how often a shop sees a pending
invitation, and if it reads as a defect the fix is §4.3's `expanded` cell saying something other than
"all inline", which is a `design.md` amendment before it is code.

**`design.md` v0.4 adds the item that touches the most screens of anything on this list, and the
product owner has already seen the thing it answers.** Every field in the app is a raised pill now.
**Chrome is enough and the back office is where to look**, not sign-in — sign-in is the screen the
change was asked for and the one place it is certain to be right. Three things to judge. First,
**whether a form of six pills reads as this app or as a novelty**: §2.3's own argument was that when
everything is a pill the shape stops signifying, and the answer to it is that a button is filled and
a field is not — open "Manage catalog", press *Correct*, and see whether the *Review correction*
button still reads as the button. Second, **whether 17 leading icons is too few or too many**; the
24 that declined one are listed as a judgement to revisit. Third, **the caps lock**: it defaults off,
which means the keypad now types lower case where it always typed capitals, and whether that is
right is a question about how this till is actually used at a counter.

**Step 9 adds the item a person meets before anything else in this app, and it is the one on this
list that needs a device least and a *pair of eyes* most.** Sign-in is rebuilt: `Welcome back` at
§2.2's title roles instead of a hand-sized 40px, one border per field instead of two, a 2px focus
ring instead of a green glow, `Sign in` instead of `UNLOCK REGISTER →`, and a keypad that only
appears above 1264. **Chrome is enough for the form** — it is the one screen a run reaches without
signing in, which is the whole reason the web callable-auth defect has never blocked looking at it.
Three things to judge. First, **whether the form reads as centred or as adrift**: it sits in the
middle of the window with a lot of ground above the title, which is what it did before and is more
visible now the title is smaller. Second, **whether losing the keypad below 1264 is right** — the
arithmetic says a key below 48 fails §9, but a till at 1280 that used to have a keyboard now does
not, and only somebody who has used one can say whether that is a loss. Third, **the disabled
`Enter` key**: it does nothing and now looks like it does nothing, and whether that reads as honest
or as broken decides whether it gets wired or dropped.

**The device-run debt is therefore now twenty-five chunks deep**, and the last twenty are the ones that
most need a device — between them they changed how nearly every screen in the app looks, how every
button feels, how every screen is entered and left, how every box a person types into is drawn, how
every explanation folds away, where the title of every screen sits, how wide every page
is, **what a list of records even is**, on **all twelve** of the screens `design.md` names,
**where every remaining explanation and status on the reconciliation surfaces sits**, **what a
difference and a run state about themselves**, and now **what
a figure looks like** on the two screens a person reads money from.
Nobody has looked at the
sign-in repair, the invitation repair, the category repair, commit
`1b2b13b`, **the ripple kill**, **`AppButton`**, **`AppPageRoute`**, **`AppTextField`**,
**`Disclosure`**, **`AppScaffold`**, **`AppLayout`**, **`RecordList`**, **the staff directory on
it**, **either catalog screen on it**, **any of the four stock screens on it**, **any of the four
shift screens on it**, **any of the four reconciliation surfaces**, **any of the four catalog
surfaces**, **`StatTile` on any of its five**, **`StatLine` on a difference or a run**, **any of the
seven notices that now answer in colour**, **any of the fourteen routes that stopped saying their
own name twice**, **any of the twelve tables whose columns are now measured rather than shared
out**, or **the screen a person sees before any of the others**. Between them that is 409 tests,
239 screenshots, and no eyes.

**One item on this list stopped being purely a matter of judgement on 2026-08-14, and it is the
strongest argument yet for looking rather than asserting.** A `Disclosure` had shipped truncated on a
phone for two days and 196 pictures did not show it, because the component's own matrix is `web` only.
A screenshot at the right width caught it in one look. That is not a device finding — the harness found
it — but it is the same lesson at one remove: **the states nobody photographs are the states nobody
knows about.** **The catalog chunk made the point twice more the same day**: the same class of defect
recurred inside a *dialog*, where the budget is smaller again; and `mobile/19-correct-a-product` turned
out never to have photographed the dialog it is named after, so a picture that existed was evidence
about nothing.

**Step 8's own item for a shopkeeper is the one on this list that a person will notice within a
second of opening the app, and it needs a real screen rather than a picture.** `numeric.hero` is
**28px at weight 700**, and a period total now reads `KES 6420.50` at that size on a card that fills
a phone's width — where this morning the same figure sat inside a sentence at body size. Whether that
reads as *the answer this screen exists for* or as shouting is exactly the judgement §2.2 wrote the
role for and no screenshot settles, because the question is about proportion on a real screen held at
arm's length. **Open screen 26 on a phone, and screen 25 under it**, where the same money is
deliberately at `numeric.body` in a column of seven days. If the hero reads as too loud, the honest
fixes are named rather than invented — a smaller role for money specifically, or a tile that is not
full-width on a phone — and both are `design.md` amendments before they are code.

**Its second item is a badge on every past day.** Screen 25 now wears **`Reconciled`** in green on
every day the server has regenerated and **`Not reconciled yet`** in amber on today. That is §2.1's
own vocabulary and it passes the every-row test in the seed data — but a shop that reads this screen
every morning sees six greens and one amber, every morning, and a badge that is always the same on
six rows out of seven is close to the every-row badge the rule exists to prevent. **Count the greens
against real data.** If it reads as decoration, the honest fix is that only the exception wears one,
and that is a `design.md` question about what a standing is for rather than a code change.

**The catalog chunk's own item for a shopkeeper is a wording judgement, and it is cheap to check
because the pictures are now there.** `web-full/20b-bulk-report-previewed` and
`web-full/20c-bulk-report-committed` are the same three rows either side of a commit. Two things in
them are decisions rather than lookups. The first is that a **previewed** row wears an amber
*awaiting* badge and reads `Created` — the badge is honest and the word is not, because the label is
the enum's own and is past tense in both modes. The second is that a **stopped chain** paints one red
notice while the rows underneath it keep their individual outcomes, which is either exactly right or
one alarm too many. Open the pair and say whether the amber reads as "not yet" or as "something is
wrong".

**The shift family adds the item with the most money on it, and it needs a shopkeeper rather than a
device.** Screen 32 now wears a badge on every closed shift: **`Cash matches`** in green,
**`Cash over`** or **`Cash short`** in red, **`No closing summary`** in amber. The lookup is §2.1's
own table — a drawer that disagrees with the sales is a "difference found" — but what a red badge on
a shift *means to the person whose drawer it was* is not a `design.md` question. A till that is 20
short on a Friday is ordinary in most shops, and a page of red rows either says "look here" or says
"you are always wrong". Open the history against real data and count the reds. If it reads as an
accusation, the fix is a threshold or a different status for a small difference, and both are
`design.md` amendments before they are code.

**Its second item is the two words a chunk chose**, in the same family as the stock family's `Not
recorded` below: screen 32's corrections attribute reads **`Corrected twice, last 2026-08-12 19:30
UTC`**, and the paragraph it replaced — which promised that a correction never touches the counted
cash — is now one clause of the page's own note. The claim survives; what changed is that a cashier
reads it once at the top instead of on the row that concerns them. If the reassurance only lands when
it sits *on* the row, that is a wording decision and it is the product owner's.

**The stock family adds the item that is a wording judgement rather than a layout one**, and it is
the cheapest thing on this list to check because it needs no device at all — only somebody who knows
what these screens are for. Four screens now describe a ledger entry in **one** vocabulary where
three used to differ, and two of the words in it were chosen inside a chunk: `Before and after` as
the key over a figure like `10 to 7`, and **`Not recorded` as its value when the writer recorded
neither**. The second is the one to look at. A reconciled sale legitimately has no before and after —
nightly reconciliation writes the movement without reading the product — and "Not recorded" is
briefer than the sentence it replaces but is also two words a person could read as *"somebody failed
to record this"* rather than *"this kind of entry does not have one"*. If it reads as a fault, the
fix is a wording amendment and not code.

**The catalog chunk adds the item a shopkeeper would notice first**, and it is a judgement rather
than a check: **whether "Out of stock" on a catalog is a signal or a nag.** Two of the seven seeded
products wear it, which is the ratio the decision was made for — but a real shop's catalog may be a
third out of stock on a Friday, and a badge on a third of the rows is halfway to the badge on every
row the rule exists to prevent. Open "Manage catalog" against real data and count. If it reads as
noise, the fix is not to delete the badge but to say what the threshold is, and that is a
`design.md` amendment before it is code.

**The sweep's first screen adds the item with the strongest argument for a phone specifically**, and
it is not a matter of taste: **the staff directory's five inline forms were overflowing on every phone
and nobody knew**, because no capture opened one and no test drove one below 768. The fix is asserted
and photographed now, but the whole class of defect is "a layout that has only ever been laid out
wide". Open the directory on a phone, press Edit, press Deactivate, and look at the form — then do the
same on the catalog once 18 is swept, because that screen's forms have never been narrow either.

**Step 6b adds the item with the least evidence behind it of anything on this list.** Two-column
cards at §4.1's `medium` band are a rendering **no person has seen at any size on any surface** —
the harness could not photograph that band until this chunk added a viewport for it, and what exists
now is four pictures of a synthetic catalog. **Chrome settles it**, the same way it settles §4.2's
maxima: open a back-office list, drag the window narrower past 1024 and past 768, and watch it
change form twice. Whether the two-column card reads as a denser list or as a page that could not
decide between a phone and a desktop is exactly the judgement §4.3 exists to make, and it is the
cheapest unanswered question in this file.

**Step 6a adds the first item on that list that needs a *wide* surface rather than a phone.** §4.2's
maxima cannot fire below 720, so nothing about them is visible on the device everything else on this
list wants. The only evidence that exists is the 1440 harness capture, and the question — whether a
1200 column centred in a 1440 window reads as composed or as a page that failed to fill its space —
is the same kind of judgement the page header's 128 pixels is. **Chrome is enough for this one**,
which makes it the cheapest item on the list rather than another blocked one.

**The page frame is now the first thing to look at, ahead of the field.** It is the one change in
the six whose central question a screenshot genuinely cannot answer, because the question is about
*proportion on a real screen*: a toolbar and a header cost a route roughly **128 logical pixels of
frame on a phone where a toolbar alone cost 56**, and whether that reads as generous or as a
near-empty strip above a title is a judgement. Open two or three back-office routes on a phone and
say which. If the answer is "wasteful", the honest fixes are named rather than invented — a slimmer
toolbar, or a header that scrolls away — and both are `design.md` amendments before they are code.

**A field is still where this hurts most among the atoms, and a `Disclosure` is next.** Whether the
reveal reads as the same screen growing or as a new one appearing, whether an 18px chevron's
rotation is legible, and whether the spring holds a frame budget on a low tier are all judged and
not asserted.

**A field is where this hurts most.** The cursor, the caret colour, the keyboard's return key, the
counter appearing mid-word, whether a 50-character helper line wraps to two on a phone, and whether
the ring reads as focus or as an error — all of it is asserted by a widget test and none of it is
judged by one. **Whenever the next device run happens, those come first** — for
sign-in, an empty password, a wrong password, then editing a field; for the invitation, the refusal
an identity that was unverified at invite time receives; for the category wording, the seeded
product filed under `cat-not-cached` in "Manage catalog" and an import preview of a sheet naming
`Bakery`; for the theme, any screen with a button, a spinner or an icon on it. The invitation one
**cannot be reproduced on the emulators at all** (finding 6): it needs either a real Brevo key or
an invitation written by hand with `visibleAcceptanceAllowed: false`.

**The ripple kill and `AppButton` are a different kind of debt from the other four and should be
treated as one.** The other four are repairs whose tests are genuine evidence and whose device pass
would be confirmation. **Their central claims cannot be tested at all**: a ripple exists only
mid-press, an overscroll glow only mid-drag, and *interruptibility* is a property of a spring
between two frames. `design.md` §10 makes all of it a device check with the performance overlay on.
The 51 new tests prove the spring retargets from its position and velocity when driven directly,
and the harness photographs a **settled** press; neither says anything about how it feels.
**Press and release the landing route's buttons, press one twice in quick succession to feel the
second press take over mid-release, tab through the route to see the ring, drag a list past its
end, and watch the frame graph while doing it.**

**One exclusion named because it has been inherited for many consecutive chunks, and it is this
chunk's own neighbour: renaming or deleting a category.** Still correctly excluded and it has not
become blocking. It has carried since 2026-08-07 for one reason that has not changed — deleting a
category orphans the `categoryId` on every product filed under it, and renaming one is only safe
because nothing stores the name — and the catalog chunk was the first to work inside both catalog
screens since it was written. It found nothing that makes it more urgent: a category is a `Chip` in a
`Wrap` on both screens, neither is a `RecordList`, and `unlistedTenantCategoryLabel` already answers
the one state a person meets. It becomes a decision when somebody asks to correct a misspelt
category, which nobody has.

**A second exclusion named because it has been inherited for many consecutive chunks, and this chunk
is the first to have worked inside the screen that shows it: a resolution path for the four stock and
sale differences.** Still correctly excluded and it has not become blocking. Screen 21's
"Reconciliation found" section is where a person meets one, and the stock chunk read every word of it
while deciding not to migrate it. What it found supports the exclusion rather than weakening it: the
section already says which of the four kinds an adjustment resolves and which three it does not, and
for the one that it does the resolution path exists three inches below on the same screen — the
adjust-stock form. The three it does not resolve need a *server* answer (a re-run, a repaired ledger
entry, a repaired quantity), and inventing a client button for any of them would offer an action that
cannot work. It becomes a decision when somebody asks what to press for an unreadable movement, and
the honest first move then is a re-run request rather than a correction.

**A third exclusion named because it has been inherited for many consecutive chunks: the printed
receipt body.** Still correctly excluded and it has not become blocking — a sale is recorded,
found by receipt lookup, and returned without anything being printed. It is **not** blocked on
a decision, which is the part worth restating: the transport was answered on 2026-08-07 and an
external print service owns it. It is blocked on that service's interface, which decides what
a "body" even is — ESC/POS bytes, text at a column width, a structured payload, or a PDF. The
moment it is shared this becomes the next capability chunk. **Do not start it on a guessed
contract**; a formatter written against the wrong one is worse than none, because it looks
finished.

### Then, in preference order

- **~~The design system, step 1: the token layer~~** — **done 2026-08-11.** It moved no board row
  and no rollout step, and it is the only chunk in this file whose pass condition was that nothing
  changed: 101 screenshots, hashed with the registration in and out, byte-for-byte identical. What
  it decided — additive rather than conforming, and a density as a nested `Theme` — is recorded in
  its own standing decision above, together with the two corrections it made to `design.md` and the
  three questions it refused to answer by inventing a value.
- **Find out what a Windows build can actually attest with under App Check** — the only queued
  item that would move a red row, and now deferred **four** times. The device findings that
  outranked it are gone; what moved it aside on 2026-08-11 was the product owner asking for the
  redesign instead. It is a research chunk that ends in a decision only they can make, and it owes
  the evidence rather than the choice: what a Windows build can attest with today (the three
  built-ins are Play Integrity, App Attest/DeviceCheck and reCAPTCHA Enterprise, and
  `firebase_app_check` listing Windows as supported is *plugin* support, not an attestation
  provider — establish whether it resolves to anything but the debug provider); whether console
  enforcement is still off everywhere, since nothing in the client sends a token; the
  `DefaultFirebaseOptions.windows` `1:…:web:…` registration mismatch; and the three options costed
  — Apple/Android/web only, a custom Windows provider, or an unattested endpoint under different
  rate limiting. **Do not restate the "structurally unreachable" claim in either direction without
  checking it**, and do not build the reset surface, initialize App Check, or turn on enforcement:
  those follow the decision.
- **~~The design system, step 2: remove every ink ripple~~** — **done 2026-08-11**, and with it the
  scroll physics. `splashFactory: NoSplash` plus `overlayColor` on the four button themes reading
  §2.1's action tiers, and `SpiritScrollBehavior` for §2.4's bouncing physics with no overscroll
  glow. It moved no board row and no rollout step; it moved the **Design system** track from 8% to
  15%. Two screenshots moved and neither shows a ripple — see the standing decision, and the new
  standing trap about a capture case that taps without settling. **Step 2's fourth part, route
  transitions, was left out of it**: §2.4 requires a spring, and a transition written on a
  duration would satisfy the step number while contradicting the section it comes from. That
  reasoning held; it was taken as its own chunk on 2026-08-12 and step 2 is now finished.
- **~~Stop showing a category ID to a person~~** — **done 2026-08-11**, closing finding 5. It
  moved no board row and no rollout step, and it moved none of the 101 screenshots either — for a
  reason that is recorded rather than celebrated: the harness files every seeded product under a
  category it reads, so no capture reaches the branch that changed. What it decided — one
  resolution replacing six, two wordings of one answer, and an import preview that names what the
  sheet said in three descending degrees of certainty — is in its own standing decision above,
  together with the two corrections it made to this file's description of the defect.
- **Harden the two platform-CLI helpers against a Node warning** — small, and it protects every
  future session's reading of the invitation suite. `runPlatformGrantCli` and its revoke twin parse
  a spawned CLI's **stderr** as JSON, so any `(node:<pid>)` warning fails the test with a
  `SyntaxError` that names nothing about the CLI. Strip warning lines before parsing, or spawn with
  `NODE_NO_WARNINGS=1`, and **capture what the warning actually was** while doing it — nobody has
  seen it yet. Touches `rules-tests/test/` only: no product code, no rule, no `functions/` file. It
  is queued below the App Check research because it costs a session nothing to re-run a flake and
  the research chunk is the one holding a red row shut.
- **~~The design system, step 3, first half: `AppButton` and its call sites~~** — **done
  2026-08-11, in two chunks.** The component, its spring substrate and its state matrix landed
  first; the remaining 133 call sites followed the same day. Together they moved no board row and
  no rollout step, moved the **Design system** track 15% to 30%, and produced the two largest image
  diffs of the migration — 75 of 101 and then 74 of 113. Both have their own standing decision
  above, including the three defects the component found in its own first draft and the two
  successive corrections to this file's estimate of the work's size.
- **~~The design system, step 2, fourth part: route transitions~~** — **done 2026-08-12**, and with
  it step 2. `AppPageRoute` at all **23** call sites, §6.2's two rows, and the whole thing about
  a third the size this file predicted because Flutter 3.44's `TransitionRoute.createSimulation`
  is the seam it said did not exist. It moved no board row and no rollout step, moved the **Design
  system** track 30% to 35%, added 30 tests and 3 screenshots, and its own standing decision above
  records the parallax it deliberately leaves off the landing route and why.
- **`TenantRouteGuard` reloads whenever its `load` closure is re-created**, which is on every
  rebuild of every panel that hosts one. `didUpdateWidget` compares `oldWidget.load !=
  widget.load` by identity, and every `build` makes a new closure, so an unrelated rebuild costs a
  Firestore read. Found 2026-08-12 by the route chunk, which had to abandon a correct transition
  because of it — see that standing decision. **It is a behaviour change and does not belong in a
  visual chunk**; the shape of the fix is a stable identity for "the loader changed", which is
  probably the key the caller already computes. Closing it is what would let the landing route
  parallax.
- **~~The design system, step 3, second half: `AppTextField` and `AppSelect`~~** — **done
  2026-08-12**, and with it step 3. 39 call sites across 17 files, §5.2's well and rules, six
  states in the harness, **finding 4 closed**, and `AppSelect` built after the audit claim it was
  dropped on turned out to be false. It moved no board row, moved the **Design system** track 35%
  to 45%, added 29 tests and 10 screenshots, and **measured all four non-Flutter suites**.
- **§5.2 covers `Callout` not at all, and names no icon size for `Disclosure` or `Callout`.** Every
  measurement `Callout` uses is borrowed from a §2 row, and all three glyphs take `AppButton`'s 18
  as the nearest named leading-icon size. Either §5.2 gains a `Callout` paragraph and an icon-size
  row, or a sentence saying the borrowed rows are the specification. **A question for the product
  owner, not a chunk** — but it blocks calling §5's inventory complete in step 12.
- **§5.2 does not say what a field looks like under a pointer.** `AppTextField` has no hover
  treatment because there is no row to read one from, and `92-appfield-hover` is a capture of that
  absence. Either §5.2 gains a hover row or it gains a sentence saying a field has no hover state.
  **A question for the product owner, not a chunk** — but it blocks calling §9's audit complete in
  step 12.
- **~~The design system, step 4: `StatusBadge`, `Callout`, `Disclosure`~~** — **done 2026-08-12.**
  Three components, `AppStatus`, 8 harness captures and 34 tests, on four migrated screens. It
  moved no board row and no rollout step, moved the **Design system** track 45% to 50%, and its own
  standing decision above records what it decided — the glyph defaults, the two borrowed icon
  sizes, the `text.secondary` prose, the tolerance the reveal closes against, the two status
  mappings that are decisions rather than lookups, and `ConfirmDialog` leaving for step 7.
- **The step-4 sweep: every remaining status, notice and permanent explanation** — the second half
  of step 4, the way the call-site sweep was the second half of `AppButton`. **Three chunks on
  2026-08-14**, the third being the two money screens, which travelled with step 8's first half
  exactly as the second chunk said they should. The first two: the four reconciliation surfaces, which are both of the screen sections it owned by
  name, and then the four catalog surfaces. The first established the `Disclosure` / `Callout` rule the
  remainder follows, added `lib/reporting/reconciliation_labels.dart`, and corrected step 4's own
  truncated summary; the second added a page-standing `Callout`, the report-row badges whose lookup
  reads the report's mode, `Disclosure.dialogSummaryCharacterBudget`, and two harness captures of a
  state nothing had ever photographed; the third folded the two money screens' prose, put their
  currency notice and their failed read into `Callout`s, and made a day's reconciliation state a
  badge. **What is left is the long tail of one- and two-`textTheme` files**, which is an ending
  rather than a chunk. **Four items in it are not restyles**:
  `reconciliation-request-notice`, `reconciliation-amend-notice`, `catalog-management-notice` and
  `bulk-catalog-notice` all need a status the model does not carry, and they are one small chunk
  together rather than four.
- **~~The design system, step 5a: `AppScaffold` and `PageHeader`~~** — **done 2026-08-12.** The page
  frame at **25 call sites across 23 files**, §7's page pattern, §2.2's two screen-title roles, 28
  tests and 14 harness captures. It moved no board row and no rollout step, moved the **Design
  system** track 50% to 55%, and **measured all four non-Flutter suites** rather than taking the
  carry it was entitled to. Its own standing decision above records what it decided — the title
  leaving the toolbar, the 72 pixels that costs a route, the one screen that had to change shape to
  pay for it, the tab strip moving under the header, the action row's two arrangements, and the
  seven raw `Scaffold`s it deliberately left alone, the landing route among them.
- **~~The design system, step 6, first half: §4.1's breakpoints and §4.2's content widths~~** —
  **done 2026-08-12.** One `AppLayout` where the app carried four declarations of two numbers, a
  required content width on all **25** `AppScaffold` call sites, and the three routes that padded 24
  brought onto `space.20`. It moved no board row and no rollout step, moved the **Design system**
  track 55% to 60%, added 20 tests and 6 screenshots, and moved 51 — **49 of them `web/`**, which is
  the check rather than an aside. Its own standing decision above records what it decided, including
  the one reason to argue with it: `contentWidth` is required rather than defaulted.
- **~~Install a JDK 21, or pin `firebase-tools` back, or find a machine that has one~~** —
  **withdrawn 2026-08-13; there was never anything to install.** Queued 2026-08-12 by step 6a on the
  belief that three baselines could not run here, escalated 2026-08-13 by step 6b to the head of
  this list, and removed the same day when the product owner said the suites had run before. The
  JDK 21 was always present; what was missing was the prelude. **Nothing is owed to it.** The
  withdrawn open decision above keeps the reasoning, because how it survived two sessions is worth
  more than the item ever was.
- **~~The design system, step 6, second half: §4.3's `RecordList` contract~~** — **done
  2026-08-13**, and with it step 6. One record model, three renderings resolved from the screen
  width, `RecordActionSet` with them, 12 harness captures across **three** bands, 34 tests, and the
  **activity log** as the first migrated consumer. It moved no board row and no rollout step, moved
  the **Design system** track 60% to 65%, applied `DESIGN-AUDIT.md` §6 decision 2 to `design.md` at
  last, and found a constrained-overflow defect in step 4's own `StatusBadge` that nothing before it
  could have reached. Its own standing decision above records what it decided, including the one
  thing most likely to be argued with: columns are the union across the list rather than the first
  record's.
- **~~The `RecordList` sweep: the remaining twelve screens~~** — **done 2026-08-13, all twelve**
  (step 6's list is twelve screens, not thirteen; both figures were inherited wrongly). It took four
  chunks. The staff directory deleted the hand-rolled choice and retired `TenantRecordCard`,
  `TenantRecordTable`, `TenantTableColumn`, `TenantTableRow` and `TenantStatusChip`, and brought
  `RecordItem.details` with it. It cost **one** test file rather than five — a staff record can carry
  at most four actions, so only one moved behind the menu — and found a phone-width overflow in five
  inline forms that predated `RecordList` by a step. **The catalog, 17 and 18, went next** and made
  §5.2's own `Correct` / `Retire` example false of the app; it corrected three of this file's
  predictions about itself and cost two test files. **The stock family, 21–24, went third** and found
  three screens wording one document three ways, which is the drift
  `lib/inventory/stock_movement_labels.dart` had been written to prevent and had never reached; it
  cost four test files, +8 tests, 12 images and no board row. **The shift family, 30 and 32–34, went
  fourth and last**, and is where a record first turned out to have a §2.1 standing; it also found
  three page-invariant paragraphs being repeated per record, and one of the three was settled by a
  screenshot rather than by argument. It cost five test files, +8 tests, 11 moved images, 1 added,
  and no board row.
- **~~The design system, step 8, first half: the money component and the two money screens~~** —
  **done 2026-08-14.** `StatTile`, `StatRow` and `StatLine` in `lib/ui/stats.dart`, on **four**
  screens — 13 and 21, which already had a stat strip, and 25 and 26, which are step 8's own and took
  the step-4 sweep of their prose with them. It moved no board row and no rollout step, moved the
  **Design system** track 82% to 85%, added 23 tests and 13 screenshots, moved 22, and deleted
  `TenantStatCard` and `TenantStatStrip`. Its own standing decision above records what it decided,
  including the one most likely to be argued with: **a stat row measures its own figures** rather than
  reading a minimum width somebody chose. **Tables, step 8's third word, needed nothing** — they are
  `RecordList`'s and step 6 shipped them.
- **The design system, step 8, second half: the figures on 27, 28 and 29** — the queued chunk. Their
  prose was swept for step 4 earlier the same day, so this is only what step 8 is about. **It wants
  §3's density answered**, and §3's density is still two constants away from being answerable.
- **~~§7's "Title appears once", broken on 13 panels~~** — **done 2026-08-15**, and it was fourteen
  sites in fourteen files. Step 5a moved every title into a `PageHeader` and left the in-body
  `headlineSmall` copies behind it; nine were deletions, four became `PageHeader.subtitle`'s first
  readers, and one was a heading telling every role a page was read-only when it was not. 52 images.
- **~~The four `RecordList` column-arithmetic observations~~** — **done 2026-08-15**, as one chunk,
  for the reason they were queued as one: a changed column share moves all twelve migrated screens.
  `RecordTableColumns` measures what the list holds instead of dividing the row by four constants
  chosen against a two-column activity log. It moved no board row and no rollout step, moved the
  **Design system** track 92% to 93%, added 18 tests and 5 screenshots, moved 26 — **every one of them
  `web/` or `web-full/`** — and changed **no call site**. Its own standing decision above records what
  it decided, including the one most likely to be argued with: the actions column is **not** sized to
  the widest set in the list.
- **~~The design system, step 9: sign-in and onboarding~~** — **done 2026-08-15**, and it was one
  screen rather than the eight §11 lists. It moved no board row and no rollout step, moved the
  **Design system** track 93% to 95%, added 12 tests, added 6 screenshots and moved 18 — **16 of the
  18 are not sign-in**, they are the two `CheckboxListTile` screens the theme change reaches. Its own
  standing decision above records the ten decisions, including the two most likely to be argued
  with: it is a `Scaffold` with a `PageHeader` rather than an `AppScaffold`, and a keypad key is
  **not** an `AppButton` because §5.2's padding rule cannot be honoured at §9's minimum key width.
- **The design system, step 11: the copy pass against §8** — the queued chunk, described at the top
  of "Next bounded chunk", together with the four reasons step 10 is not takeable and the seven-item
  backlog four previous chunks left for it.
- **~~The Flutter surface that edits a product~~** — **done 2026-08-08.** It was
  promoted out of this list into the current chunk on 2026-08-07 once the flake in front
  of it was fixed, and it is now the board's twenty-first green row. What it found on the
  way is recorded in the standing decision above.
- **~~Bulk change: `updateProducts` as a server callable~~** — **done 2026-08-08.** It
  moved no board row, deliberately: the callable is built, tested, exported, and called
  by nothing, which is the same day-long life `updateProduct` had. What it decided is
  recorded in the standing decision above.
- **~~Spreadsheet import: `importProducts` as a server callable~~** — **done 2026-08-08.**
  It moved no board row either, for the same reason bulk change did not: built, tested,
  exported, and called by nothing. What it decided — category resolution by name, a
  product ID derived from the row's position, and opening stock through `adjustStock`
  semantics — is recorded in its own standing decision above.
- **~~The Flutter surface for bulk change and import~~** — **done 2026-08-08**, as one
  chunk covering both callables, and it is the only chunk so far to move **two** board rows
  at once. `TenantBulkCatalogScreen` is reached from "Manage catalog", it touched no server
  file and no rule, and it emptied the unreachable table of everything that was waiting on
  nothing but effort. What it decided — one field across many products, an immutable page per
  request, a commit only after a whole-chain preview, and two different money rules on one
  screen — is recorded in its own standing decision above.
- **~~A surface that shows profit and margin~~** — **done 2026-08-08**, and it is the board's
  twenty-fourth green row. It was never in this list, which is the point: it was created as a
  red board row by the product-cost chunk and left as an exclusion four times over. It touched
  no server file and no rule, and what it decided — that an incomplete figure is refused rather
  than qualified, because nothing reports the denominator that would let it be qualified — is
  recorded in its own standing decision above.
- **The printed receipt body** — **waiting on an interface, not on a decision.** The
  transport question was answered on 2026-08-07: an external print service, to be
  shared, handles thermal printer onboarding over a local print server, TCP/IP, and
  Bluetooth. See the closed decision above for what is still unknown, all of it about
  what that service takes and how it is reached. The moment it is shared this becomes
  the next capability chunk and it is a well-shaped one; until then it is blocked on
  something no session can resolve by thinking about it.
- **~~An emulator integration test for `deliverPasswordReset`~~** — **done 2026-08-08.** It
  moved no board row, deliberately: the client surface is what the App Check decision blocks
  and this chunk went past that gate rather than at it. What it moved is the invitation
  integration baseline, 12 → 23. It is also the one chunk so far whose "changes no production
  code" claim did not survive contact — it added `export` to
  `firestorePasswordResetDependencies`, because rebuilding those adapters in the test would
  have been a test of the rebuild. See the closed half of the App Check decision above.
- **~~Run the app against the emulators~~** — **done 2026-08-08**, on **Android**, after being
  queued eleven times. The product owner answered the one open question by putting Android back
  in scope and asking for it first. It moved no board row's colour, corrected one row's text, and
  changed no repository file. Every green route it touched worked; it found six defects at the
  edges, all listed under "Found by using the app" and queued individually below. The traps it
  cost are now in "Standing traps": the emulator needs `ANDROID_SDK_ROOT` overridden to `D:`, the
  Gradle daemon must be stopped before either emulator starts, and staff invitation email cannot
  be delivered locally at all.
- **~~The login screen's failure messages~~** — **done 2026-08-08**, closing findings 1 and 2. It
  moved no board row's colour, because a defect repair inside an already-green row has none to
  move; it changed the "Sign in" row's text. What it decided — that the provider's `message` is
  dropped at a typed boundary so no surface above it can render one, and that a wrong password,
  an unknown address, and a malformed credential are one sentence — is recorded in its own
  standing decision above. **It owes one thing: nobody has looked at it**, because the session
  was told to skip the Android build. That debt is attached to the next device run.
- **~~The invitation refusal that says "Please try again" when retrying cannot work~~** —
  **done 2026-08-08**, closing finding 3. It moved no board row's colour, because a defect repair
  inside an already-green row has none to move; it changed the "Accept a staff invitation" row's
  text. It was queued here as "the smallest of them"; **that was wrong twice over.** Both
  acceptance surfaces `catch (_)` and **neither adapter converted anything**, so the whole
  boundary had to be built twice — and the refusal is `permission-denied` carrying a `violation`
  in `details`, not the `failed-precondition` this file predicted. What it decided — that only a
  failure known to be transient may invite a retry, and that one server function gets one client
  mapping — is recorded in its own standing decision above. **It owes the same thing sign-in
  does: nobody has looked at it.**
- **~~The add-product form's category picker, and the two surfaces that show a category ID~~** —
  **both halves are done.** Finding 5 closed on 2026-08-11; **finding 4 closed on 2026-08-12**
  inside the redesign's step 3, by moving the picker into the form rather than adding a second
  one. The pair was queued together because both are about a category being named the wrong way,
  and they came apart because only one of them was wording.
- **A fixture chunk that reaches the last three lines of `deliverPasswordReset`** — the
  keyring parsed out of its secret, the Brevo provider constructed out of its secrets, and the
  `getFirestore()`/`getAuth()` defaults. Small, and deliberately not folded into the test
  chunk that named it: it means exporting an email function from
  `functions/integration/index.js`, whose closure reaches five parameters in
  `email/config.ts`, and every one of them has to be answered at emulator startup or the run
  hangs. The parts are unit-tested separately, so this buys wiring confidence and nothing else.
- **`regenerateDailyMetric` writes `daily_metrics` with `merge: false` and no
  `createdAt`**, unlike every other document in this pipeline. Probably deliberate;
  nothing says which.

**Below the line: scoped, and deliberately not in this ordering yet.**

- **Suspicious-return scoring** — scoped 2026-08-08 and sequenced **after the first
  deployment**, rollout step 13. It is not queued above because taking it earlier would
  mean tuning every threshold against seed data, and those numbers are the feature. See
  "A suspicious return is scored on the server" for the six signals, the one that has no
  input in this app, and why the destination already exists. **Do not pull it forward
  without saying so** — the sequencing is a decision, not an accident of ordering.

### Standing exclusions

Outside every chunk until deliberately scheduled: a resolution path for the four
stock and sale differences, currency labels on the differences list, the subscription
surfaces, discounts, camera barcode scanning, **the in-app password reset surface**
(blocked on the App Check decision above, which is now in motion), renaming or
deleting a category, SKU uniqueness, a `platform_audit_logs`
surface, branding surfaces, the Sentry DSN, the 475 pre-existing analyzer issues, a
root-widget smoke test and the startup seams it would need, and deployment.

**Four things the design system excludes, new to this list on 2026-08-11 and each its own
decision rather than an oversight.** A light palette — §12 asks the question and answers nothing,
so there is no second palette to write and inventing one is what `claude.md` forbids.
~~**The breakpoints and the content widths** — §4.1's three names and §4.2's 720 / 1200 / 420 are
not in the token layer, because 768 is already declared twice (`records.dart:26`,
`checkout_cart_panel.dart:550`) with a third mechanism in `login_screen.dart:47`, and a fourth
declaration that removes none of the three makes the drift worse; unifying them is a rewiring step
in §4.1's own words.~~ **Discharged 2026-08-12 by step 6a, which is the outcome the exclusion was
written to produce rather than a reversal of it.** The exclusion said a fourth declaration that
removes none of the three makes the drift worse — so the step that was allowed to add one was the
step that removed all three, and it did: `AppLayout` is the only declaration of either number, and
§4.2's three widths went in with it. It had been narrowed once already, on 2026-08-12, when step 5a
*read* both `records.dart` constants without declaring anything.
**The eight animated assets and the device-tier system** — step 10, ninth in
the order deliberately, because building assets before the substrate produces a slow app with nice
animations in it. **As of 2026-08-15 that queue position is no longer the whole reason**: with steps
1 to 9 done, step 10 is the next number and it is blocked on three of `design.md` §12's own open
questions plus two §5.1 components that do not exist. The four blockers are itemised under "Next
bounded chunk", and they are why step 11 was taken out of order rather than step 10 being started
half-built. And **`lib/pos/**` and `lib/screens/**` throughout, which `claude.md` hard rule 3
makes read-only.

**Seven other surfaces that say "Please try again." are new to this list**, and they are named
rather than left silent because the chunk that repaired the invitation refusal deliberately did
not touch them: staff invitation, resend, cancellation, email replacement, staff status, staff
update, default tenant, and tenant request. **None of them strands a user with no way forward**,
which is exactly what made the invitation refusal a finding — the person meeting those seven is
already inside a business, doing something else instead is possible, and a retry frequently does
work. They become a decision if a device run finds one of them misdirecting the way the
invitation did, and the boundary to reuse is
`lib/tenancy/invitation_acceptance_failure.dart`.

**The sign-in screen's visual design has left this list, and the reason it used to carry is now
false in two ways.** It was excluded on the grounds that "it is legacy styling, not a defect:
`pill_input` and `glass_card` are in the closed unreachable island for analyzer purposes, the screen
works, and nobody has asked for it. It becomes a decision only if somebody does."

**Somebody has.** `design.md` §11 step 9 is sign-in and onboarding, and `DESIGN-AUDIT.md` §4.4 names
what is actually wrong with it: labels in uppercase where §2.2 permits it only on `label.eyebrow`, a
radius-32 well where §2.3 says 8, a green glow `BoxShadow` where §9 requires a 2px focus ring,
`Colors.green` for the Remember Me checkbox — a *different* green from `accentGreen` — and
`Colors.red` for the error rather than the palette's own critical red. "UNLOCK REGISTER →" stays
named because §8 rule 3 and §2.2 both reach it: wrong case and wrong words.

**And the island claim was wrong.** `lib/main.dart:4` imports `login_screen.dart` and mounts it at
`:460` as `signedOut`; that screen imports `pill_input`, `pos_keyboard`, `glass_card`, and
`pill_button`. The app's root reaches all four. See the analyzer-issues entry below, which carried
the same error.

~~Nothing of it is excluded now; it is queued as step 9 of the redesign, which is far enough down
that the queue position is doing the work the exclusion used to.~~ **Done 2026-08-15**, and every
defect this entry lists is closed — plus four it did not have, of which the largest is that the
keypad's keys were 24 pixels wide at §4.1's `medium` floor. See the standing decision. **The screen
takes 12 tests, 6 pictures and two of the app's 244 images**, which is worth stating against the two
sentences this entry spent arguing about whether it was excluded.

**That entry was narrowed on 2026-08-08 and the narrowing is the point.** It used to read
"password reset" flat, which made a whole area look closed when only one half of it was. The
**client surface** is what App Check blocks, and it stays excluded. The **server worker** was
not blocked by anything and never was: `deliverPasswordReset` has no attestation of any kind.
**Its emulator integration test was written later the same day** — the rule attached to this
exclusion said a third consecutive exclusion is when it gets taken, and it was — so that half
is no longer an exclusion, no longer queued, and no longer untested. What is still excluded
here is only the surface, and only for as long as the App Check decision stands.

**Editing a product's descriptive fields left this list on 2026-08-07 and was finished
on 2026-08-08.** The `updateProduct` callable exists, is tested, and is now called by
`TenantCatalogManagementPanel`'s "Correct" action. Neither half is excluded and neither
is queued; the row is green. What remains excluded from *around* it is unchanged and
listed above: category rename and delete, SKU uniqueness, and `quantity` in any form.

Two of those are consequences of the catalog chunk on 2026-08-07 rather than
inherited: **renaming or deleting a category** (it orphans the `categoryId` on every
product filed under it) and **SKU uniqueness** (nothing on the server enforces it and a
client-side check would be a guarantee the next device breaks).

**Bulk catalog import left this list on 2026-08-08, and the reason it used to carry was
wrong.** It read: "`BULK_UPLOAD_GUIDE.md` describes a pre-migration flow that ~~reaches
no code in `lib/`~~". **Retracted — 788 lines of it are in `lib/services/`**
(`bulk_upload_service.dart` and `bulk_update_service.dart`), reachable from
`lib/pos/goods.dart`. The claim was true in effect and false in letter, which is the
kind of thing that makes a later session conclude the feature was never built. It is now
scoped work rather than an exclusion, as a **rewrite**; the standing decision above says
what carries over and what must not.

**Receipt printing has left this list.** It was named once in the previous handover as
the item this list would run out of excuses for, and re-excluding it silently a second
time is what this section exists to prevent — so it became an open decision on
2026-08-07, was answered the same day, and is now the head of the preference order
below the current chunk, **blocked on an interface rather than on a decision**: an
external print service handles the transport, and this app owes the printed body. Do
not re-exclude it and do not start it on a guessed contract. Nothing about it is
blocking today: a sale completes, is recorded, is found by receipt lookup, and is
returnable without anything being printed.

**Product cost left this list on 2026-08-07, profit display replaced it, and profit display
left it on 2026-08-08 by being built.** The product owner asked for buying price and attached
one requirement: a change to it must never move a profit already reported. That is now
guaranteed by the sale line rather than by care — see the standing decision above. The
**display** of profit or margin was excluded from four consecutive chunks with the same true
reason — it cannot show a number without also showing how many lines have no cost behind it —
and that reason turned out to be the design rather than a blocker: the chunk resolved it by
**refusing the number** whenever any line lacks a cost, because nothing reports the total line
count that would let a partial figure be honestly qualified. Nothing of it is excluded and
nothing of it is queued.

**What stays excluded from around it**, and the first of these is new rather than inherited:
**a server change adding a total line count**, which is the one thing that could justify
showing an incomplete figure and which nobody has asked for; **no backfill** of sales recorded
before cost existed, which is impossible and must not be faked with zero; and **discounts**.

**Named once, as it has been inherited for many consecutive chunks: the 475
pre-existing analyzer issues.** Still correctly excluded, but **the reason it has been carrying was
partly false and is corrected here.** It read: "every one of them is in the closed unreachable island
(`lib/pos/**`, `lib/screens/**`, `thermal_printer_service`, `glass_card`, `pill_input`,
`theme.dart`) plus one experimental Sentry warning, and nothing in `lib/main.dart` or the tenancy
shell reaches any of it."

**Three of those six are reachable from the app's root.** `lib/main.dart:6` imports `theme.dart` and
`:201` mounts `spiritTheme` as the app's only theme; `:4` imports `login_screen.dart` and `:460`
mounts it as `signedOut`, and that screen imports `pill_input`, `glass_card`, `pill_button`, and
`pos_keyboard`. The island is `lib/pos/**`, `lib/screens/**`, and `thermal_printer_service` — which
is still the overwhelming bulk of the 475 — **410 of them, counted on 2026-08-11** — so the
exclusion stands on its own weight rather than on the sentence that was wrong. The other 65 are
listed by area under "Repository state", because "all of them are in the island" was the part that
was false and a count is the only thing that stops it being said again.

**`theme.dart` has left the island outright.** The redesign's step 1 landed on 2026-08-11 and
registers the token layer there, and **step 2 landed the same day and made it the ripple
substrate**; commit `1b2b13b` had already rewritten it into the `ColorScheme` every screen reads. It is now analysed with every chunk
that touches it — `flutter analyze` over `lib/theme.dart`, `lib/ui` and the tests beside them
reports **no issues** — and `lib/ui/` is held to the same standard.

The thing to watch is unchanged: the printing decision above points at
`thermal_printer_service.dart`, which is genuinely *in* the island, so whichever chunk takes printing
has to say whether it revives that file or writes past it. Until then, analyse the paths a chunk
touches and leave `lib/pos/**` and `lib/screens/**` alone.

**Suspicious-return scoring was never on this list either, and that was an oversight
rather than a decision.** A 555-line capability of the previous app appeared in no board
row, no rollout step, and no exclusion — it had simply never been written down. Scoped
2026-08-08 and sequenced after the first deployment. Recorded here because "not
excluded" and "not noticed" look identical in a file like this one, and only one of them
is a decision.

The subscription surfaces, named the same way two handovers ago, are unchanged and
still correctly excluded: `grep -i subscription functions/src` still finds nothing at
all, so a Flutter surface would invent the schema, lifecycle, and billing states the
server later has to agree with. That one starts on the server or not at all, and
nothing in the sell-and-settle loop reads it. The exclusions that moved from cosmetic
to load-bearing are tracked above instead of here, and only one of the three is still
an open question: **the in-app password reset surface**, now in motion in the console —
though the server-side half of that area stopped being an exclusion on 2026-08-08 and was
taken and finished the same day. **How a price is corrected** is resolved, built, and reachable —
nothing of it is left — and **what a receipt is printed on** is answered and waiting on
an interface.

**Bulk catalog work was dropped from the list above on 2026-08-08 and is finished.** It
stopped being an exclusion when it was scoped as a rewrite; `updateProducts` landed that
morning, `importProducts` that afternoon, and the one screen that reaches both landed that
evening. Nothing of it is excluded and nothing of it is queued; both board rows are green.
**`.xlsx` and any binary spreadsheet format are the one part still excluded**, and that is
this chunk's own decision rather than an inherited one: delimited text is the input a person
already has, and the parser is one function from text to rows, so a picker changes nothing
else when somebody wants one.

**The gap between "a callable exists" and "a person can do it" closed the same day it was
named as the limit**, and the mechanism is worth keeping: two consecutive server chunks ended
in the unreachable table, this file said a third would make that a pile, and the third chunk
was the surface. Nothing in that table is now waiting on effort alone.

---

## Assumptions

- The mono-tenant Firebase project remains untouched.
- The shared Firebase projects begin empty.
- Standard users may own or join several tenants.
- Tenant switching requires connectivity; the current tenant remains offline-first.
- Platform identities are dedicated and membership-free.
- Public ownership transfer remains deferred; operator recovery is included.
- Offline revocation takes effect when connectivity returns.
- Consolidated portfolios, shared billing, and group-wide permissions remain future work.
