# Chilltent POS — Frozen Implementation Baseline

Current state only. Every dated session handover lives in [HISTORY.md](HISTORY.md),
verbatim and in order — go there for why a decision was made, what a chunk
deliberately left out, and which failures cost a debugging cycle.

Last verified against the code on **2026-08-11**, the session that killed the ink ripple —
`design.md` §11 step 2, and the first step of the redesign that moves anything a person can
see. Claims in this file are checked against source,
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
| **Design system** | ~15% | `design.md` v0.3 is the specification, `DESIGN-AUDIT.md` audits it against the code, and **step 1 of its twelve is done and step 2 all but one part**: `lib/ui/tokens.dart` holds every colour, type, spacing, radius, motion and density token, and the ripple is dead — `splashFactory: NoSplash`, the four button themes reading §2.1's action tiers, and bouncing scroll physics with no overscroll glow. **Route transitions are step 2's fourth part and are not done**, because §2.4 requires a spring and the substrate arrives with `AppButton`. **One thing reads the token layer; everything else still reads the old values.** Steps 3–12 remain, `AppButton` next. The specification, the audit and the harness are all untracked. |
| **Flutter client** | ~92% | The sell-and-settle loop works, a business can publish the currency it sells in, stock itself, record what a product cost, **correct a product**, **correct many at once**, **create a catalog from a pasted spreadsheet**, and **read its profit and margin where the cost data is complete**. **All five of the 2026-08-08 capability routes were driven on an Android device against the emulators the same day and every one of them worked**; what that run found is six defects at the edges, listed under "Found by using the app", **four of which are now fixed**. No printing, no subscription. Suspicious-return scoring was scoped 2026-08-08 as a rewrite and is not started. |
| **Deployment & operations** | ~5% | Nothing deployed anywhere. Only the dev project is even mapped. |

### Can a shop do this yet?

Green means a person could do it in a running app today. Not green if only the
callable exists, and not green if it is merely tested.

| Capability | | Where it stands |
| --- | --- | --- |
| Sign in | 🟢 | `LoginScreen`. A failure renders **a sentence this app wrote**, never an exception: the screen signs in through `EmailPasswordSignIn` and the provider's `message` is dropped at that boundary, so nothing above it can display one. An empty address or password is refused by the form, and any refusal is cleared the moment the input it describes is edited |
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

**The third session of 2026-08-11 changed no board row at all — not a colour and not a word of one
— and this sentence is here so that is stated rather than left silent.** It took `design.md` §11
step 2, the ripple kill, which is a **redesign step rather than a capability**: no shop can do
anything today it could not do yesterday, and the **Design system** track is where it moved, 8% to
15%. It touched no rule and no `functions/` file — `git diff` over both prints zero lines — and it
changed **no rollout step**, because the app's fifteen and the design system's twelve are separate
sequences. **It moved two of the 101 screenshots, and neither of them shows a ripple**; see the
standing decision for what the delta actually is, because the honest reading of it matters more
than the count.

**The second session of 2026-08-11 changed no board row's colour either, and this sentence is here
so that is stated rather than left silent.** It closed finding 5 — no catalog surface states a
category document ID to a person any more — which is a **defect repair inside rows that were
already green**, so there was no colour to move, and it changed **no row's text**, because no row
ever claimed anything about how a category is named. It touched no rule and no `functions/` file:
`git diff` over `firestore.rules`, `functions/` and `rules-tests/` prints **zero lines**, which is
why the four non-Flutter baselines below are carried rather than re-measured. It changed **no
rollout step**, and it moved none of the 101 screenshots — see the standing decision for why that
proves nothing about the repair. **What it corrected in this file is, again, a claim this file
itself made**: the queued chunk said the read-only catalog resolved category names correctly and
that only two surfaces did not. Both are false; the retraction is inline at finding 5.

**The 2026-08-11 token-layer session changed no board row at all — not a colour and not a word of
one — and this sentence is here so that is stated rather than left silent.** It is the first chunk
in this file whose **pass condition was that nothing changed**: `design.md` §11 step 1 defines
every token and wires none of them, so the 101 screenshots were regenerated with the registration
in place and again with it backed out and hashed byte-for-byte identical. It added a **Design
system** row to the tracks table rather than moving a capability row here, because a token layer is
not a capability: no shop can do anything today that it could not do yesterday. It touched no rule and no `functions/`
file — `git diff` over both prints zero lines — and it changed **no rollout step**, because the
fifteen frozen steps are the app's and the design system's twelve are its own.

**The tenth session of 2026-08-08 changed no board row's colour either, and this sentence is here
so that is stated rather than left silent.** It closed finding 3 — a refused invitation now says
what will actually work — which is a **defect repair inside a row that was already green**, so
again there was no colour to move. It changed **one row's text**, "Accept a staff invitation".
It touched no rule and no `functions/` file, and the functions and rules counts held at 409 and
161 to say so. It changed **no rollout step**: step 7 is about the server's invitation
machinery, and the server was already right — it was the client that was throwing the server's
answer away. **What it corrected in this file is a claim this file itself made**: the queued
chunk asserted `failed-precondition` was the code behind the refusal, and the server throws
`permission-denied` carrying a `violation` in `details`. That retraction is inline below.

**The ninth session of 2026-08-08 changed no board row's colour either, and this sentence is here
so that is stated rather than left silent.** It fixed findings 1 and 2 below — the sign-in screen
now says something true — which is a **defect repair inside a row that was already green**, so
there was no colour to move. It changed **one row's text**, "Sign in", to say what a failure now
renders and why that is structural rather than careful. It touched no rule and no `functions/`
file, and the functions and rules counts held at 409 and 161 to say so. It also changed **no
rollout step**: a green capability that stops printing an exception at the user is not a step,
it is the difference between a step being true and being embarrassing.

**The eighth session of 2026-08-08 changed no board row's colour, and this sentence is here so
that is stated rather than left silent.** It drove the app on an Android emulator against real
Auth, Firestore, and Functions, and **every green row it touched stayed green on the evidence of
a person using it** rather than on the evidence of a widget test — add, correct and retire a
product, bulk correction, spreadsheet import, ring up a sale, daily summary as two different
roles, the stock route, and reconciliation. It changed **one row's text**, "Accept a staff
invitation", because the row was wrong about *which* identities may accept in-app; see that row
and the finding behind it below. It changed no code at all, so the four suite baselines are
carried rather than re-measured.

### Found by using the app

Six defects, all at the edges, none blocking, **recorded rather than fixed by the run itself** —
a behavioural session that starts repairing becomes an unbounded one. They were queued as chunks
below; **the first two were taken and closed by the session after it, the third by the
session after that, and the fifth on 2026-08-11.** Two remain and **neither is a queued chunk**:
finding 4's repair is absorbed into the redesign's step 3, because that step rewrites the form it
lives on, and finding 6 is an environment limitation rather than a product defect. **So the
device run's findings have run out as chunks**, which matters for what comes next — see the
current chunk.

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
4. **The add-product form asks for a category with no picker beside it.** "Choose the category
   this product is filed under." sits about a thousand pixels below the chip row that is
   actually the picker, under a heading that also serves as the category list. It works once
   found. The **"Correct" dialog has an inline picker**, so one screen does it both ways.
   **Still open, but no longer a chunk of its own as of 2026-08-11**: its repair is form layout,
   and `AppTextField` plus the 720px content width in `design.md` §4.2 rewrite that form, so it is
   recorded against the redesign's step 3 rather than built twice. The defect has not stopped
   mattering; only its queue position changed.
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
the Android emulator, and the instruction has now won three times. So the sign-in repair is
covered by 32 tests — including the `dev.flutter.pigeon` assertion that would have caught the
original — the invitation repair by 19, and the category repair by 7 including two that assert
over **every** rendered string rather than over the slot that was wrong, and **no person has seen
any of them**. The debt is three chunks deep and all three are queued below against the next
device run, sign-in first.

**One thing the run could not prove, stated because it would otherwise look proved.** The
manager membership used for the profit role-boundary check was activated by a scratchpad Admin
SDK script writing what `acceptVisibleTenantInvitation` would have written, for the reason in
finding 6. `inviteStaff` was genuinely exercised and wrote the staff record, the mirror, the
root identity, and the invitation proof correctly; **acceptance was not**.

**The seventh session of 2026-08-08 changed no board row at all, deliberately, and this sentence
is here so that is stated rather than left silent.** It wrote the emulator integration test for
`deliverPasswordReset` — 11 tests against real Auth and real Firestore, joined to the invitation
suite. Password reset stays **red** because red means a person cannot do it in a running app, and
the client surface is what the App Check decision blocks; this chunk deliberately went past that
gate rather than at it. What it moved is the invitation integration baseline below, **12 → 23**,
and the evidence behind rollout steps 7 and 12. It touched no rule and no Dart file, and the
functions count held at 409 — which is the measurement saying the one production change it made,
exporting `firestorePasswordResetDependencies`, changed no behaviour.

**One row went green in the session before it: profit and margin.** The board is 29
rows at **24 green, 4 red, 1 amber**. It moved with **no server file and no rule touched** —
409 functions tests and 161 rules tests, both unchanged, were the measurement — because
`aggregateSales` already returned `profit` and `incompleteCostLineCount`, `daily_metrics`
already stored both, and both client read models already parsed both. Only the display was
missing, and only for a session allowed to see it.

**What the row does not mean is worth pinning, because green usually means more than this.**
A shop sees a profit figure on a day, or over a period, **only when every sale line behind it
carries a cost** — and every sale recorded before 2026-08-07 has none and never will. So a
90-day total will state that it cannot show one until the window rolls past that date, and a
day is complete as soon as the products sold on it carry costs. That is the capability
working, not failing: see the standing decision for why a partial figure is refused rather
than qualified.

**Two rows went green in the session before it, and they are the two that had been
waiting on nothing but effort**: spreadsheet import and bulk change, which took the board to
23 green. The route is `TenantBulkCatalogScreen`, offered as "Bulk changes and import" from
inside "Manage catalog", and it is the first client caller either callable has ever had. It
changed `firestore.rules` not at all and nothing in `functions/` either — both callables were
already built, and neither needed a change to be reached.

**That session is also the one where the unreachable table stopped growing.** Two
consecutive server chunks had ended in it, which this file named as the limit; the third
chunk was the surface rather than a third callable.

**The import session earlier on 2026-08-08 changed no board row at all, deliberately, and
this sentence is here so that is stated rather than left silent.** `importProducts` was
built, tested, and exported that day and no route called it — the second server chunk in a
row to end that way, which is why the next chunk was a Flutter surface. What it moved is the
functions baseline below, from 378 to 409, and the handler count from 48 to 49. The import
row's *text* changed without its colour, for the third time that pattern occurred; the row
went green hours later.

**The bulk-change session earlier the same day changed no board row either, for the same
reason.** `updateProducts` was built, tested, and exported and no route calls it, which is
the same shape `updateProduct` had for a day: green means a person could do it in a running
app today, and a callable nothing calls is not that. What it moved is the functions
baseline from 346 to 378, and the handler count from 47 to 48.

**One further row went green earlier on 2026-08-08**: editing a product. The route is
`TenantCatalogManagementScreen`'s "Correct" action, and it is the first client caller
`updateProduct` has ever had — the callable was built on 2026-08-07 and nothing called
it for a day. That row took the board to 21 green before the bulk surface took it to 23.

**Three rows were added on 2026-08-08, all red, and none of them was new work
appearing from nowhere** — spreadsheet import, bulk change, and suspicious-return
flagging are capabilities the *previous* app had that this one did not, and they were
scoped that day rather than left unnamed. Two of the three had never been written down
anywhere; the board became 29 rows because of it. Adding them moved no code. **Two of the
three were built and reachable by the end of the same day**; suspicious-return scoring is
the one still red, and it is sequenced after the first deployment on purpose.

**Two rows moved on 2026-08-07 when a product gained a cost** — "Record what a product
cost" went green and "See profit or margin" was added red, because the server computed a
figure nothing displayed. **That second row closed on 2026-08-08**, which is the whole life
of it: added as a red row by the chunk that created the gap, named as an exclusion for four
consecutive chunks with the same true reason, then taken as a chunk once that reason turned
out to be the design rather than a blocker. Before that: **no row had changed colour since the catalog
chunk, and the flake session did not change one either — it changed no board row at all, deliberately, and
this sentence is here so that is stated rather than left silent.** Five 2026-08-07
sessions followed the catalog chunk: two added unit tests only, one resolved
decisions without touching code, the fourth built `updateProduct`, and the fifth fixed
the intermittent Flutter failure that stood in front of the next capability. The fourth
**rewrote the editing row's text without moving it** — the capability existed on the
server and was unreachable from the app, which is a different sentence and the same
colour. Green means a person could do it in a running app today, and a callable nothing
calls is not that. The fifth touched two test files and no capability; what it moved is
the Flutter baseline below, from 1346 to 1347, and the ⚠️ beside it.

**No red row now stops a business operating.** The two that did both closed on
2026-08-07: a business publishes its own currency, which is what the till refuses to
sell without, and it stocks its own catalog, which every surface downstream of a
product already assumed. Neither needed a rule, a callable, or an export — the rules
had permitted both writes all along, and nothing had ever called them.

**Editing a product was a decision, then a server chunk, and is now finished.**
`updateProduct` landed on 2026-08-07 as the **twenty-fourth callable and the
forty-seventh export**, and it changed `firestore.rules` not at all — `allow update` on
`products` is still the checkout decrement and nothing else, byte for byte. The route
that calls it landed on 2026-08-08 and changed `firestore.rules` not at all either, nor
anything in `functions/`. A mistyped price is no longer an operator's job.

**Three properties of that route are worth knowing before anything reuses the
callable**, and all three come from its contract rather than from taste. It sends
**only the fields that moved**, because the callable authorizes on the fields a payload
names rather than on the resulting diff — resending an unchanged price would refuse a
manager's name correction. It offers **all five fields at once**, because the callable
validates the *resulting* document, so a refusal can name a field the correction never
touched. And it holds one request ID **against the correction, not merely across the
attempt**: see the finding below, which is the reason that distinction matters.

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
| Flutter | `flutter test --no-pub --concurrency=1 --reporter=failures-only` | **1598** ⚠️ see below |
| Functions | `npm --prefix functions test` | **409** ⚠️ carried, see below |
| Rules | `npm --prefix rules-tests run test:emulator` | **161** ⚠️ carried |
| Reconciliation integration | `npm --prefix rules-tests run test:emulator:reconciliation` | **10** ⚠️ carried |
| Invitation integration | `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **23** ⚠️ carried; one flaky test, see below |

**2201 tests across five suites** — and there is a sixth figure that is deliberately not in
this table: `flutter test --no-pub --concurrency=1 tool/screenshots` runs **78 captures**
writing 101 images, and it asserts nothing, which is why it is not counted here.

⚠️ **The four non-Flutter figures have been carried rather than measured since the second session
of 2026-08-11, and that is a decision rather than a lapse.** Both chunks that day changed Dart and
nothing else; `git diff` over `firestore.rules`, `functions/` and `rules-tests/` prints **zero
lines**, which this file already calls a stronger measurement than an unchanged suite count, and
no suite among the four can observe a Dart file. The precedent is the Android device session,
which carried all five. **Re-measure them in any chunk that touches JavaScript, TypeScript, or a
rule** — and a chunk that carries them must say so, which is what these marks do. **Two
consecutive carries is the limit worth naming**: a third should measure them, on the same
reasoning that made the third consecutive unreachable callable a surface instead.

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
after the category-naming repair, and 1598 after the ripple kill.** One failure in twenty-two
runs, and the last twenty-one green.

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

### A sale records how it was paid for, chosen manually

Resolved 2026-08-01 by the product owner, implemented 2026-08-02. The cashier
selects the tender at the point of sale — **cash, M-Pesa, or card** — and it is
recorded on the sale. No payment *integration* is in scope: nothing authorizes a
card, queries an STK push, or reconciles a provider statement. The recorded
tender is the cashier's assertion, and every surface that displays it says so
through the shared `checkoutTenderDisclaimer`.

The five hazards are settled, not open:

1. **A v1 payload still parses and is never rewritten.**
   `supportedCheckoutSalePayloadSchemaVersions = {1, 2}`. Version is read from
   the payload, never from the current constant.
2. **That is why the hash still matches.** `checkoutPayloadHash` covers the whole
   payload and `_parseRecord` re-derives it on every read, so an in-place
   migration would make every stored record `malformed_record`.
3. **Rules constrain the tender** through `validSaleTender`, and now *require*
   `payloadSchemaVersion`, which the rule previously ignored.
4. **The receipt pattern was not touched.** `CT-A7F-20260729-0042` is an identity,
   derivable from device, business date, and sequence alone.
5. **Reconciliation needed no change.** A per-tender breakdown was added to
   `getSalesComparison` only, not to stored `daily_metrics`.

### A business publishes its own currency, and it converts nothing

Decided and implemented 2026-08-07, because the alternative was a business that
cannot trade until an operator runs a script. "Checkout settings" on the landing
route merges `configuration/checkout` for an owner or administrator — the pair the
Firestore rule already allowed — and it is the only client write to that document.

The hazards are settled, not open:

1. **No amount is ever converted or re-priced.** `checkout_draft.dart` copies the
   cached `currency` into each sale payload and that payload is hashed, so a
   recorded sale keeps the code it was priced with permanently. There is no exchange
   rate anywhere in this app, and the route says so.
2. **A device that has not synced keeps pricing with the previous code.** The till
   prices from the encrypted Hive snapshot, which only the catalog refresh re-reads,
   so two devices can record one day's sales in two currencies. This is *stated in
   the confirmation* rather than prevented, because preventing it would block the
   correction of a typo — and a typo here stops nothing, while a wrong code
   mislabels every report.
3. **A commit asks for a full sync pass**, through
   `CheckoutSyncSignals.requestSyncAfterConfigurationChange()`. It emits the same
   unnarrowed reason a reconnect does; a save-shaped request sets
   `refreshDerivedData: false` and would have skipped the only read that matters.
4. **The write merges.** A whole-document `set` would delete a setting a later build
   adds, because the strict read model ignores unknown fields rather than refusing
   them. `configuration/branding` beside it is never touched.
5. **A document the till cannot parse is correctable here.** The publishing
   repository reports `malformed` where the till's read model throws, so the one
   person who can fix an unusable currency is not shown the cashier's refusal.
6. **No request ID, deliberately.** One fixed path and one fixed value make the
   write idempotent by construction, so an unknown outcome is answered by
   re-reading and, if needed, publishing the same code again.

### A shop stocks itself, and a retired product keeps its history

Decided and implemented 2026-08-07, the same day and for the same reason as the
currency above: the alternative was a business that cannot trade until an operator
runs a script. "Manage catalog" on the landing route adds a category, adds a product,
and retires one. Adding is owner, administrator, or manager; retiring is owner or
administrator — exactly the two role sets the Firestore rules already named, so no
rule, callable, or export changed.

The hazards are settled, not open:

1. **A product is written in exactly the shape the strict read model demands.** The
   rule checks only `quantity is int`. One product the till cannot parse makes the
   *whole* cached catalog a miss, so `TenantProductCreateIntent` is the only thing
   standing between a typed form and a business that has stopped selling. The unit
   suite proves it by decoding `documentData()` back through `TenantProduct`.
2. **A price is proved through the till's own function.** Bounded to a plain decimal
   with at most two places — two is all `unitPriceMinor` holds — then round-tripped
   through `checkoutMinorUnitsFromMajor`, and the stored major-unit figure is derived
   from the minor units rather than from what was typed. The till's
   `price_not_representable` refusal therefore happens where the price is typed, not
   with a customer standing there.
3. **A product is always created holding nothing.** Stock with no `stock_movements`
   entry has no recorded origin, and `adjustStock` already carries `opening_balance`
   for exactly this, so the opening quantity is recorded through the route that
   writes a ledger entry.
4. **Retiring is not an undo, and says so.** The confirmation states that the stock
   ledger, every past sale line, and every reported figure keep naming the product;
   that it still holds *n* in stock and nothing moves it; and that a replacement gets
   its own identity, so this is not how a wrong name, code, or price is fixed. It is
   **not** blocked on non-zero stock — that would invent a rule nothing else has.
5. **The document ID is deterministic and scoped by request, never a SKU slug.**
   `pd_<40 hex of sha256("createTenantProduct tenantId createdBy requestId")>`,
   mirroring `_deterministicReturnId`. The ID is permanent and the ledger hangs below
   it, while a SKU is neither unique nor correctable; deriving one from the other
   would make a typo permanent in the ledger key. A replay lands on the same document,
   where `allow update` refuses it — which is what makes reusing the ID safe.
6. **Category create only.** The rule permits rename and delete to the same three
   roles; neither is offered, because deleting a category orphans the `categoryId` on
   every product filed under it and nothing in this app repairs that.
7. **SKU uniqueness is stated, not enforced.** Nothing on the server makes a SKU
   unique, the seed script seeds a deliberate collision, and the till already refuses
   an ambiguous scan. A client-side check against one loaded page would be a guarantee
   the next device breaks, so the confirmation names the consequence instead.

### A price is corrected on the server, and never a quantity

Decided and built 2026-08-07. `updateProduct` is the only way a product's name, SKU,
price, or category ever changes, and it exists as a callable rather than as a wider
Firestore rule — see "How a price is corrected", resolved, for why. It writes through
the Admin SDK, so `firestore.rules` is byte-identical and `allow update` on `products`
is still the checkout decrement and nothing else.

The guarantees are settled, not open:

1. **It never writes `quantity`, and a payload that mentions it is refused** with a
   message naming `adjustStock`. This is what everything else rests on: a callable that
   could write a price *and* a quantity would be a second way to move stock with no
   `stock_movements` entry. An unknown key is refused too, rather than dropped, so that
   guarantee is observable from outside instead of taken on trust.
2. **A price is proved through the till's own arithmetic.** `productPriceMinorUnits` is
   `checkoutMinorUnitsFromMajor`, tolerance included, so `19.999` — which passes
   everything a Firestore rule can check — is refused here rather than at the till with
   a customer waiting. The stored major-unit figure is derived from the minor units.
3. **The *resulting* document must parse and be sellable, not just the fields written.**
   `readSellableProduct` is the server-side twin of `TenantProduct.fromDocument`, run
   against the document as it will exist. One unparseable product makes the whole cached
   catalog a miss, so the contract is: name every broken field in one request, or none.
   A non-integer stored `quantity` and a non-HTTPS `image` are refused as an operator's
   problem, because neither this callable nor `adjustStock` can correct them.
4. **A price needs an owner or an administrator; a name, SKU, or category needs the
   operational three.** Its own decision, not one inherited from create or delete. It is
   read from the *requested* fields rather than the resulting diff, so a manager cannot
   discover a price by binary search over refusals.
5. **A named category must exist in this business**, checked whenever it is named rather
   than only when it moves. A product filed under a category that does not exist is
   invisible to every grouped surface without being unreadable.
6. **A stored legacy `category` alias moves with `categoryId`.** The read model refuses a
   product whose two category fields disagree, and that would take the whole cached
   catalog down.
7. **The before and after of every changed field is audited**, at
   `audit_logs/pu_<40 hex>`, with actor, request ID, and `mutatesQuantity: false`. A
   rule-based edit would have written `updatedAt` and nothing else. No `stock_movements`
   entry and no `stock_adjustments` record, because nothing moves.
8. **A request that changes nothing is refused, not audited as a no-op.** Reachable only
   with a fresh request ID: a genuine retry answers off the idempotency record.

**The client route landed 2026-08-08 and its shape is forced by the eight guarantees
above, not chosen.** "Correct" on any product in "Manage catalog" opens one dialog
holding every editable field, prefilled with what the product holds. It sends only the
fields that moved (the callable authorizes on requested fields, so an unchanged price
resent would refuse a manager's name correction); it offers all five at once (the
callable validates the resulting document, so a refusal can name a field the correction
never touched); it hides price and cost from a manager rather than letting them be
refused; and clearing a cost is a checkbox rather than an empty field, because omitting
`cost` and sending `cost: null` mean different things.

**Two gaps in the callable were found while wiring the route on 2026-08-08, and the
bulk-change chunk later the same day fixed both** — it was inside `functions/`, which
the route chunk was not. They are kept here because the reasoning is what stops either
coming back:

1. ~~**The idempotency fingerprint omits `cost`.**~~ **Closed 2026-08-08.** `products.ts`
   hashed `productId`, `name`, `sku`, `priceMinor`, and `categoryId`, so two payloads
   under one request ID differing *only* in cost hashed the same, and the second was
   answered off the stored record with the new cost silently not applied — where any
   other field would have been refused as `already-exists`. A silent wrong answer rather
   than a refusal. It is now `productUpdateFingerprintInput`, exported so the property is
   testable rather than buried in a callable, and **absent, `null`, and a value all hash
   differently** — which is the distinction that matters, because omitting `cost` leaves
   a recorded cost alone and `cost: null` clears it. **The client's own protection was
   kept**: the retained request ID is still held against a fingerprint of the exact
   correction, so this is belt and braces rather than the only guard, and a second client
   would otherwise inherit nothing.
2. ~~**`UpdateProductResponse` does not echo `cost`.**~~ **Closed on both sides
   2026-08-08.** The server echoes `cost` and `costMinor`; before that a cost that moved
   appeared in `changedFields` with no value beside it, so four of the five fields could be
   reconciled against the request and the fifth could not. ~~The client half is still
   open~~ — **also closed, in the bulk-surface session the same day.**
   `TenantProductUpdateResult` now reads both, proves the pair agrees through
   `checkoutMinorUnitsFromMajor`, and **reconciles them against the correction**: a
   corrected cost must come back holding the requested figure and a cleared one must come
   back null. The route states the new cost in its notice instead of leaving it to the
   re-read. The reader is `tenantCatalogOptionalMoney`, shared with the bulk decoders, which
   read the same pair out of a per-row product. (`UpdateProductRequest` declares `cost` too,
   which is typing only — the handler reads a `Record<string, unknown>` — and changed no
   behaviour.)

**The `cost: null` escape hatch for a malformed stored cost is unreachable from this
route, deliberately.** `TenantProduct` is strict and one product it refuses makes the
whole page a read failure, so a product with an unreadable cost never renders a row and
therefore has no "Correct" button. The same holds for every `readSellableProduct`
refusal: `productUnreadable` and `needsOperator` are modelled and worded, and are
reachable only if the document changes between the page load and the call. Neither half
is wrong; the intersection is an operator's job, and "the callable can do it" is a
different sentence from "a person can do it".

### A product records what it cost, and a sale freezes it

Asked for and built 2026-08-07, with one requirement attached by the product owner:
**a change to a buying price must never move a profit figure already reported.** That
requirement decided the design, and it is met by machinery that already existed rather
than by a new rule someone could later relax.

The guarantees are settled, not open:

1. **The cost is copied onto the sale line at the moment of the sale**, in
   `checkout_draft.dart`, beside the price and through the same
   `checkoutMinorUnitsFromMajor`. Nothing downstream ever consults the product again.
2. **Four independent locks hold it there**, and no new one was invented: profit is
   computed from the line (`lineCost()` in `operations/domain.ts` reads `cost`, then
   `unitCost`, then the legacy `buyingPrice`, and there is no product join anywhere in
   the pipeline); a sale document refuses every client update (`allow update, delete:
   if false`); nightly regeneration re-reads `sales` rather than `products`; and the
   offline payload is hash-sealed, so the device copy cannot be edited either.
3. **An absent cost stays absent, never zero.** Zero would claim the business paid
   nothing and report a 100% margin. The server already counts those lines as
   `incompleteCostLineCount` and the daily summary already says so.
4. **A missing cost never refuses a sale.** Stopping a till trading over a reporting
   field would be the wrong trade. A cost the till *cannot represent* is refused where
   it is typed, as `cost_not_representable`.
5. **`firestore.rules` is byte-identical, and the rules suite was run to say so.**
   `validSaleLine` constrains only `productId` and `quantity` and names no key list, and
   `allow create` on `products` checks only `quantity is int`. A rules test now pins
   both, because the day someone tightens the create rule with a `hasOnly`, a business
   that records what it pays stops being able to add products.
6. **No payload schema version bump.** `unitCostMinor` was already an allowed optional
   line key at v2 and the parser already read it, so `validSaleTender`'s
   `payloadSchemaVersion == 2` branch is untouched. The consuming half of this feature
   was built long ago and idle; only the source was missing.
7. **Cost is money, so it sits behind owner/admin** — `MONETARY_PRODUCT_FIELDS` on the
   server, `costRoles` on the client — while creating a product stays
   owner/admin/manager. A client that sends a cost without the role is **refused, not
   ignored**.
8. **This is a surface boundary, not secrecy, and is documented as one.** `products` is
   readable by any active member because the till cannot price a sale otherwise, and
   Firestore cannot hide one field of a document. Every staff device therefore caches
   buying prices. What the boundary buys is that no manager is *shown* a margin. The
   alternative — a trigger stamping cost onto the sale server-side — was considered and
   declined: it costs a write per sale, leaves a window where the sale has no cost, and
   cannot work offline, which is the platform the whole Hive design exists for.
9. **Clearing is `cost: null`, and it is the only field where null means something.**
   It is also the escape hatch for a stored cost too malformed for the callable to
   correct. The audit keeps the unreadable previous value verbatim.

### A profit figure is complete or it is not shown

Built 2026-08-08, the **last capability chunk** of that day, and it is what made "See profit or
margin" green. It changed `firestore.rules` not at all and nothing in `functions/` either — 409
functions tests and 161 rules tests, both unchanged, are the measurement. Everything it needed
already existed: `aggregateSales` returns `profit` and `incompleteCostLineCount`,
`getSalesComparison` sends both for a business, a member, or a category, `daily_metrics`
stores both, and both client read models already parsed both. **Only the display was missing.**

**The rule is one sentence, and everything else follows from it:**

> **No profit figure is shown unless every sale line behind it carries a cost.**

The guarantees are settled, not open:

1. **A proportion is not available, and that is what decided the rule.** Nothing reported
   anywhere says how many sale lines there were altogether — only how many lacked a cost. So
   "96 lines have no cost" cannot become "96 of 4,000" without a server change. A line with no
   cost is counted by the server as costing nothing, so an incomplete figure is an **upper
   bound**, and with no denominator **how far above the truth it sits is unmeasurable**. An
   unmeasurable overstatement is not a smaller version of the truth.
2. **An "at most" ceiling was considered and declined.** It is honest wording, but the number
   it decorates is still the number a reader remembers, and the qualifier's weight is exactly
   what nothing here can quantify: two costed lines in five hundred produce a ceiling equal to
   the takings — the 100% margin this app already refused once. Suppression heals as costs are
   recorded; a ceiling only stops being *very* misleading.
3. **Three bases, decided from the figures themselves rather than from where they came**, so
   the reconciled daily summary and the server-added period totals cannot disagree about when a
   number may be believed. `complete` shows the figure and its margin and **says that it is
   complete**, because a reader cannot tell a complete figure from an overstated one by looking
   at it. `incomplete` shows no figure and carries the count inside the reason. `inconsistent`
   is a profit exceeding the takings it came from — a negative total cost, which nothing that
   writes either figure can produce — and it **outranks** `incomplete` the way
   `stockComparisonOutcome` orders its causes, because naming missing cost data for it would
   name a cause that does not explain it.
4. **The subtracted cost is recovered in whole minor units**, as `sales - profit`, which is
   exact rather than approximate because the server adds money as integers. The rounding is
   `reportingMinorUnits`, promoted out of `sales_totals.dart`, where the tender split is
   checked against its own total the same way. Deliberately **not**
   `checkoutMinorUnitsFromMajor`: that one refuses an amount the till could not price, and
   these figures are already recorded.
5. **A margin never outlives the figure it was divided from**, and is also absent for a period
   that took nothing — a margin on no takings is a division by zero, not a figure of zero. A
   percentage is the most believed number on any report and carries no units to warn a reader.
6. **Owner and administrator only, and no rule changed.** This is the tier the product-cost
   decision above already named, in the sentence saying what it buys is that no manager is
   *shown* a margin. `daily_metrics` is readable by owner/admin/manager and
   `getSalesComparison` answers all three, so **a manager's device already holds every figure
   involved**: this is a surface boundary, not a secrecy guarantee, exactly as recording a cost
   is. `TenantProfitReport.allowedRoles` restates `costRoles` rather than importing it, because
   it is this domain's own decision about a different document.
7. **A session sees the profit statement or the bare count sentence, never both.** Both panels
   already named the count to every reporting role; a profit block that also named it gave an
   owner two sentences holding one number, which reads as two findings. The sales-totals
   sentence lost its trailing "so no profit figure is shown" and is now word for word the daily
   summary's, because it is the same fact about the same sale lines over a different stretch.
8. **`TenantProfitStatement` is shared by both surfaces**, so one fact cannot be worded two
   ways, and it takes a `keyPrefix` because the daily summary renders one per day.

**What this costs a real shop, stated because green usually means more.** Every sale recorded
before 2026-08-07 has no cost and never will, so a 90-day total says it cannot show a figure
until the window rolls past that date. A **day** is complete as soon as everything sold on it
carries a cost, which is why the daily summary is the surface where this becomes useful first.

### Bulk catalog work is a rewrite, and the old code is not the starting point

Scoped 2026-08-08 by the product owner: spreadsheet import and bulk change are wanted,
**the idea and the flow carry over, the code does not.** The previous app holds
`lib/services/bulk_upload_service.dart` (320 lines) and
`lib/services/bulk_update_service.dart` (468 lines), reachable only from
`lib/pos/goods.dart` and therefore from nothing that runs. Read them for the flow; do
not port them.

**Five reasons a port fails, and the second one is fatal rather than awkward:**

1. **They write the root `alcohol` collection.** Products live at
   `tenants/{tenantId}/products/{productId}`, and the rules deny legacy root
   operational collections outright.
2. **`batch.update(docRef, arbitraryFields)` is structurally impossible here.**
   `allow update` on `products` permits `['quantity', 'updatedAt']` with a strictly
   decreasing quantity — the checkout decrement, and nothing else. Widening it is
   exactly what "How a price is corrected" rejected, because a rule-based edit records
   no actor, no previous value, and no reason. **So bulk change is N × `updateProduct`
   executed on the server, not a batch executed on a device.** That is a different
   program, not a modified one.
3. **The create path bypasses four guarantees**, each of which cost a chunk:
   `TenantProductCreateIntent` validation, without which one unparseable product makes
   the *whole* cached catalog a miss and the business stops selling; the deterministic
   `pd_<40 hex>` ID, which is what makes a replay land on the same document instead of
   duplicating it; request-ID idempotency, absent entirely, so a retried import today
   duplicates the catalog; and "a product is created holding nothing", which
   `BulkProduct.quantity` writes straight through, leaving stock with no ledger origin.
4. **Two field names have drifted, and both fail silently.** It writes `buyingPrice`,
   not `cost`, so an import's cost data would be invisible to `TenantProduct.cost` —
   the server reads `buyingPrice` only as a legacy alias on *sale lines*, never on a
   product. And it writes `category` as a display *name* where the model wants a
   `categoryId`: "Bakery" passes document-ID validation, matches no category document,
   and leaves the product invisible to every grouped surface without being unreadable.
5. **It enforces SKU uniqueness by reading the entire collection into the client.**
   Already decided against — a client-side check against what one device loaded is a
   guarantee the next device breaks, and at tenant scale the read itself is the cost.

**The bulk-change half landed 2026-08-08 as `updateProducts`, and four decisions it made
are not re-derivable from the list above:**

1. **An unchanged row is an outcome, not a refusal.** One product at a time, a request
   that changes nothing is refused as a caller defect. In a bulk change it is the
   ordinary case: re-running a 400-row correction that half applied must be able to
   finish, and it cannot if the rows that already landed take the request down with them.
   The *resulting* document is still validated either way, so "nothing to do here" is
   never a way to skip the read model.
2. **Three defects belong to the request rather than to a row**, because reporting them
   per row would make the report itself wrong: an unknown top-level key, more rows than
   the bound, and **a product named twice**. The last is the interesting one — two rows
   for one product are two conflicting intents and there is no honest outcome to report
   for either, since the second would be planned against a document the first has already
   changed.
3. **Permission is decided over the union of every row's requested fields, before
   anything is read**, and the decision is delegated to `assertProductUpdateAuthorized`
   so the tier cannot drift. A manager naming a price or a cost *anywhere* refuses the
   whole request, and the refusal names the offending rows as `rows[1], rows[2]` —
   payload paths rather than ordinals, matching the zero-based `index` every outcome
   carries. Deciding it up front means the preview refuses too, which is the point: a
   manager who previewed green and then hit a commit-time refusal learns only that the
   app guesses.
4. **One `getAll` for the whole request, because Firestore permits nothing else.** A
   transaction may not read after its first write, so a per-row read-then-write loop is
   not a slower version of this — it is a transaction that throws on its second row. Two
   corollaries: a request whose every row was refused reads nothing at all, because
   `getAll()` with no references is an error; and `FakeFirestore` gained `getAll`, whose
   first caller is the preview path.

**Order is part of the request fingerprint, deliberately**, because every outcome is
indexed by where its row sat — a reordered retry answered off the stored record would
hand back indexes naming different rows. The corrections are unaffected either way: a
row's audit entry is identified by its product, not by its position, so re-sending with
rows reordered lands on the same documents.

**A name collision to know about before grepping.** `MOBILE_BULK_UPDATE_IMPLEMENTATION.md`
and `MOBILE_BULK_UPDATE_SETUP.md` both document a method called **`updateProducts()`** —
the previous app's client-side Firestore batch in `bulk_update_service.dart`, which
writes the root `alcohol` collection. The new server callable shares the name and does
the structurally opposite thing. Those two documents are pre-migration artifacts and were
left alone.

**What the rewrite should do differently, beyond being server-side. All seven are now
built: the first six landed on 2026-08-08 as `updateProducts`, and the seventh with
`importProducts` the same day:**

- ✅ **Validate, then *preview*, then commit.** The old flow validated and committed. The
  preview is the improvement and it is the whole point: a spreadsheet is the one input
  nobody proofreads, and the first time a person should see what 400 rows are about to
  do is *before* they do it, not in the catalog afterwards. `mode` is **required and has
  no default**, and a preview writes nothing — not the corrections, not the audit
  entries, and deliberately **not an idempotency record**, which is what lets a client
  preview and then commit under one request ID.
- ✅ **Name every broken row at once**, the same contract `updateProduct` already keeps
  for fields. A row-at-a-time refusal turns a 400-row import into 400 round trips of
  discovery.
- ✅ **Partial success is stated, never implied.** A per-row outcome — `updated`,
  `unchanged`, or `failed` — with nothing silently dropped and nothing silently coerced.
- ✅ **Reuse `planProductUpdate`.** It was already a pure function from a stored document
  plus a request to a validated plan, and it already produced the per-field audit
  entries. It gained exactly one option, `allowUnchanged`, and the two paths cannot
  validate differently because there is only one of them.
- ✅ **Bounded and chained.** `MAXIMUM_PRODUCT_BATCH_ROWS` is **50**. There is no
  server-side cursor because there is no server-side collection to walk — the caller
  holds the rows — so the server owes a bound it will not exceed and a request that is
  independently idempotent.
- ✅ **One audit entry per product, correlated by the import's request ID**, so "what did
  that import do" is answerable without inventing a new kind of record. Each row writes
  `audit_logs/pu_<40 hex>` carrying `batchId` and `rowIndex` beside the usual
  `eventType: "product_updated"`; a single-product correction carries neither, so a
  query by batch matches only bulk rows. Import writes `audit_logs/pi_<40 hex>` carrying
  `importId` and `rowIndex` beside `eventType: "product_imported"`, for the same reason.
- ✅ **Opening stock goes through `adjustStock` semantics**, so imported units have a
  recorded origin like every other unit in the system. **Built 2026-08-08 with
  `importProducts`** — see the decision below for what it costs per row, and why the
  product is created *holding* the opening quantity rather than created empty and adjusted.

### A spreadsheet becomes products, and its stock has an origin

Built 2026-08-08 as `importProducts`, the second half of the rewrite above and the larger
one. It reuses that half's envelope — the required mode, the bounded row list, the per-row
outcome, the preview that writes nothing, `describeRows` for a refusal that names offending
rows as payload paths — and it reuses the *validation* that decides what a product may
hold: a row's name, code, price, and cost are read by `readProductUpdateInput`, and the
document each row would create is read back through `readSellableProduct`, the server-side
twin of `TenantProduct.fromDocument`, before anything is written. The two paths cannot
drift about what a product is.

**The three problems only a create raises, and how each was answered:**

1. **A category named "Bakery" is resolved, and an unmatched name refuses the row.** A row
   names its category by `categoryId` **or** by `categoryName`, never both and never
   neither. A name is folded — case-insensitive, over collapsed whitespace — because
   "bakery" and "Bakery" are one category to everybody who is not a computer. **It does not
   create the category**, and that is the decision: a category is permanent here, since the
   rules permit rename and delete and this app offers neither, so "Bakry" typed once would
   become a grouping nobody can repair whose products every grouped report separates from
   the real one. The preview is what makes refusing tolerable — every unmatched name comes
   back at once, before anything is written, and the catalog surface already creates
   categories. A name **two** categories share fails that row too, because nothing makes a
   category name unique and there is no honest answer. The wire key is `categoryName` and
   never `category`: a stored product's `category` is the legacy alias for `categoryId` and
   holds an ID, which is exactly the drift the previous app's uploader shipped.
2. **The product ID is derived from the row's position**, as
   `pd_<40 hex of sha256(identity + NUL + rowIndex)>`, together with `sa_` for the row's
   stock adjustment and `pi_` for its audit entry, all three from one digest. This is
   the only deterministic ID in this codebase derived from a position, and it is a
   deliberate reversal: `productBatchRowUpdateId` derives a correction's audit entry from
   the *product* so a reordered retry lands on the same documents, and an import has no
   product to derive from. So **order is part of the fingerprint and matters more here than
   anywhere else** — a reordered retry answered off the stored record would report IDs
   belonging to different products, and one not answered off it would create the whole
   catalog a second time.
3. **A row may carry a `quantity`, and this is the only product payload that may.**
   `updateProduct` refuses one outright with a message naming `adjustStock`; that refusal is
   not relaxed here, it is satisfied. The reason it exists is that a quantity with no
   `stock_movements` entry has no recorded origin, and this path writes that entry in the
   same transaction: a `stock_adjustments` record and a `stock_movements` entry in
   `adjustStock`'s own shape, field for field, with `sourceType: "product_import"`,
   `adjustmentType: "opening_balance"`, and `previousQuantity: 0` — the product is created
   in the same transaction, so it held nothing. It is created **holding** the opening
   quantity rather than created empty and then adjusted: the recorded history is identical
   and it is one write fewer. **A row that opens holding nothing writes no ledger entry at
   all** and its audit entry says `mutatesQuantity: false`; whenever that flag is true the
   entry names the `adjustmentId`, and that pairing is the whole justification for accepting
   a quantity here.

**Four decisions that are not re-derivable from the bulk-change half:**

1. **A product named twice is *not* refused, reversing the correction's rule.** Two rows
   addressing one document are conflicting intents; two rows describing one product each
   create their own document. A shop legitimately stocking two products with one name and
   one code is a state this app permits and the till already refuses to resolve by scan, SKU
   uniqueness is stated rather than enforced everywhere else, and a check against fifty rows
   would not see the four hundred already in the catalog.
2. **A price is not behind owner/admin here; only cost is.** `updateProduct` gates both,
   because *changing* a price silently alters what every later sale records. Setting the
   first price is creation — `allow create` on `products` already names the operational
   three and the add-product form already lets a manager type a price — so an import that
   refused what the form beside it accepts would be a rule nobody could explain. The cost
   tier is delegated to `assertProductUpdateAuthorized` over the single field `cost`, so
   neither threshold nor wording can drift, and it is decided before anything is read, so
   the preview refuses too.
3. **An absent cost and an explicit `null` mean the same thing and hash the same** — the
   opposite of `updateProduct`, where null clears. There is nothing to clear on a product
   that does not exist yet, so a blank spreadsheet cell means the business did not say, and
   a null cost is therefore not a monetary row.
4. **Re-running an import needs a new request ID, and that stocks the shelf twice.** Stated
   rather than prevented, and tested. A genuine retry under the same request ID is answered
   off the idempotency record and lands on the same documents, which the previous app's
   uploader could not do at all. The preview is the answer to a duplicated import, not a
   uniqueness check this app has never been able to make.

**Two bounds, both stated rather than implied.** `MAXIMUM_PRODUCT_IMPORT_ROWS` is **50** —
the same figure the correction half uses even though the per-row budget is four documents
rather than two, because fifty rows is at most 200 writes plus one idempotency record
against Firestore's 500, and two different bounds for one screen would be a trap.
`MAXIMUM_IMPORT_CATEGORY_SCAN` is **500**, read as `limit(501)` so "there are too many" is
answered by the read itself; exceeding it refuses the **whole request**, because the defect
belongs to the business rather than to a row, and the message says to name each row's
category by ID, which needs no scan. Which read runs is decided by the rows: an ID-only
request reads exactly those documents through `getAll`, and a request naming any name scans
instead — that scan answers the ID rows too, so the two are alternatives rather than both.

**One field is written that the catalog's own create form does not: `updatedAt`.** The
nightly stock verification defers a product written in the last five minutes by reading it,
and this is the one create path that can produce a product already holding stock — without
it, an imported product could be compared against a ledger entry the query walking it
cannot see yet.

**What import still does not do is parse anything.** The callable takes rows; whatever turns
a spreadsheet into rows is a client concern, and so is every surface. Which is why this
moved no board row. **The surface landed the same day** — see the decision below.

### One screen reaches both bulk callables, and it previews before it writes

Built 2026-08-08, the chunk immediately before the profit display, and it is what made
spreadsheet import and bulk change green. `TenantBulkCatalogScreen` is offered as **"Bulk
changes and import"** from
inside "Manage catalog" rather than from the landing route, because correcting many products
starts by looking at them and the product list it needs is the list that route already shows.
It changed `firestore.rules` not at all and nothing in `functions/` either.

**Where the rows come from was the open question and it is now answered.** A **bulk
correction reads its rows from the catalog this app already holds** — tick products on the
route's own paged list — and an **import reads delimited text pasted into the screen**.
Delimited text is the input a person already has: every spreadsheet exports it, it survives a
copy-and-paste, and it needs no package and no file picker. `.xlsx` is still excluded and
adding it later changes nothing else, because the parser is one function from text to rows.

The guarantees are settled, not open:

1. **A bulk correction moves one field across many products, never a form.** Three reasons.
   The rows come from products already on the device, so there is no column to read a
   per-product value out of. A name and a code belong to one product each — two products
   cannot share a corrected name, and a shared code is what the till refuses to resolve by
   scan. And the server decides permission over the **union** of every row's requested
   fields, so folding a price into a category move would refuse the whole request for a
   manager who never asked to change money. Four things are offered: file under a category,
   set a unit price, set a unit cost, remove the unit cost.
2. **A page is immutable once built, and a commit re-sends the objects the preview sent.**
   Order is part of the request fingerprint and a page keeps one request ID across its own
   preview and its own commit — which is exactly what the server's decision to record no
   idempotency record for a preview exists to allow. Rebuilding the plan would issue new IDs
   and could reorder rows, so anything that changes what the plan was built from throws the
   plan and its report away rather than letting them drift apart.
3. **A commit is offered only after a preview that answered every page.** A rule, not
   caution: committing a page nobody previewed is the thing the preview exists to prevent.
4. **The role asymmetry is honoured twice, differently, because the server imposes two
   rules.** A correction naming money *anywhere* refuses the whole request, so a manager is
   offered **no money correction at all**. An import **may** take a price from a manager —
   setting a first price is creation and the add-product form beside it accepts one — and must
   still refuse a cost, so a manager's sheet carrying a `cost` column is refused **as a
   sheet**, before any row is read, which is where the server decides it too.
5. **A row is labelled by what a person recognises, not by what the server indexes.** A
   correction shows its **position in the selection** and an import shows the **line of the
   pasted sheet, header included**. The server's index is page-local: index 0 of the second
   request is the fifty-first product ticked, and a person fixing a refusal is looking at
   their own file.
6. **Every row appears in the report, and a row this client can refuse is refused before
   anything is sent and still reported.** A blank name, a spaced code, an unrepresentable
   price, a negative opening balance, a row naming a category twice or not at all, a row with
   fewer cells than its header — each is that row's own refusal, carried beside the server's
   outcomes so every broken row is named at once.
7. **The catalog surface's own validators decide what a row may hold.**
   `tenantCatalogNormalizedName`, `tenantCatalogNormalizedSku`, and
   `tenantCatalogPriceMinorUnits` were promoted from private to public for this, so a product
   created by an import, created by the add-product form, and corrected one at a time cannot
   differ in what this client will write. A `_shared` wrapper converts their exception type
   and carries the code through unchanged — deliberately not a second copy.
8. **A sheet-level defect throws and a row-level defect is reported**, the split the server
   already makes. No header, a required column missing, no category column, one column twice,
   more rows than the chain holds, and **a column this import does not read** all refuse the
   sheet. The last one matters: a column nobody reads is refused rather than ignored, so
   nothing a person supplied is dropped without being mentioned.
9. **The delimiter is decided from the header alone** — tab, comma, or semicolon — so every
   row splits the same way. Deciding it per row would let one row with a stray tab split
   differently from its neighbours. A double-quoted cell may hold the delimiter and two
   quotes inside one are a literal quote, without which `Bread, sliced` becomes two cells and
   shifts every column after it.
10. **A half-answered chain is the ordinary case and is stated.** Pages go one after another,
    a refusal stops the chain, and the report says how many requests answered — which in a
    commit is how many were written. A page whose answer cannot be decoded is an **unknown
    outcome** rather than a failure, because the request was sent.
11. **The duplicate-import hazard is stated where a person can see it.** The commit
    confirmation says that running the sheet again creates the products a second time, because
    nothing here makes a code unique and retiring a product is not an undo.

**Two bounds are the client's own.** A page is `maximumBulkCatalogRows` = **50**, matching
both server constants, and one pasted sheet is `maximumBulkCatalogSheetRows` = **500**, ten
pages. The server bounds a request; nothing bounds how many requests a client makes, and a
pasted ten-thousand-row sheet is two hundred sequential round trips nobody can watch finish.

**One thing to know before reusing the selection.** A catalog read page is bounded at fifty
by `readCollectionPage`, so a selection gets past fifty only by paging — which the selection
survives, because it is held by product ID above the guard rather than derived from what is
rendered.

### A suspicious return is scored on the server, after the first deployment

Scoped 2026-08-08 and **deliberately sequenced after the first deployment** — rollout
step 13 — at the product owner's direction. The supporting reason is worth recording
because it also makes the work better: every threshold in this feature is a judgement
about what normal looks like, and normal is not knowable from seed data. A ruleset tuned
against fixtures is a guess that will be re-tuned the week real returns arrive.

The previous app has `lib/services/fraud_detection_service.dart` (555 lines) and
`lib/model/return_analysis.dart`, reachable only from the legacy returns screens. **Six
signals carry over as an idea**: a quick return (under 4 hours), a late one (over 72), a
seller's return rate, void behaviour, a refund amount beyond a z-score of 2, and
velocity (3 returns in 4 hours). A seventh, product-level analysis, is commented out in
the original.

**Four things must change, and the first is why it is not a port:**

1. **It is client-side, and a client-computed score is not a control.** It touches
   Firestore not at all — it takes already-fetched snapshots — and the result lands in
   `_riskCache`, widget state that dies with the screen. Nothing is persisted, so
   nothing can be reviewed, audited, or acted on later. The gate that matters is
   `verifyReturnAndRestoreStock`, which is on the server.
2. **One of the six signals has no input.** The void signal keys on `type == 'void'`,
   and **this app has no void concept at all.** Either voids get modelled first or that
   signal is dropped; it must not be ported as dead code that always scores zero.
3. **Thresholds cannot be global constants in a multi-tenant app.** Three returns in
   four hours is an ordinary afternoon for a bar and an emergency for a jeweller. They
   belong in `configuration/`, per business, which is also why this waits for real data.
4. **The destination already exists**, which makes this cheaper than its line count
   suggests. `reconciliation_anomalies` is a server-written collection with a live
   surface at `lib/reporting/reconciliation_anomalies_panel.dart`, readable by
   owner/admin/manager — and a risky return is an anomaly. The shape is a trigger that
   scores on return creation and writes one anomaly document, surfaced where operators
   already look.

Field drift to expect on the way: the old scorer reads `soldBy` (a display name),
`dateAdded`, `productName`, `totalReturned`, and `itemsReturned`; this app records
`soldById` (a UID) and `businessDate`.

### A sign-in failure is a sentence this app wrote, and it cannot be anything else

Built 2026-08-08, the last chunk of that day, closing findings 1 and 2 from the Android run. It
changed `firestore.rules` not at all and nothing in `functions/` either — 409 functions tests and
161 rules tests, both unchanged, are the measurement. It moved no board row's colour, because it
is a defect repair inside a row that was already green.

**The defect was that the first screen of this app printed a Flutter platform-channel name at
whoever was signing in.** The fix is deliberately not a patch on the code that produced it.

The guarantees are settled, not open:

1. **The provider's `message` is dropped at a boundary, so no surface above it can render one.**
   `lib/tenancy/sign_in.dart` holds `EmailPasswordSignIn` (the interface),
   `FirebaseEmailPasswordSignIn` (the adapter), and `SignInException`, which carries **a code and
   nothing else** — the same shape `email_delivery_status.dart` and `account_verification.dart`
   already use for their callables. The old screen rendered `e.message ?? "Login failed"`. "A
   user reads language" is now a property of the type, not of care taken at a call site.
2. **`signInSafeError` reads a code and never a message, and its fallback names no cause.**
   Anything that is not a `SignInException` — a platform channel error, a plugin defect, a
   programming mistake — gets one sentence that does not mention the credential. Mapping only the
   code that caused the report would have left every other channel-level failure printing itself,
   and the bug class is "the error is a string nobody wrote", not that one code.
3. **A wrong password, an unknown address, and a malformed credential are one identical
   sentence.** Firebase collapses them into `invalid-credential` itself once email enumeration
   protection is on, so distinguishing them here is a disclosure that survives only until that
   setting changes — and this app already closes enumeration deliberately on the password-reset
   endpoint. A test asserts the set of answers over all five codes has size one.
4. **An empty address or password is refused by the form, before Firebase is called.** An empty
   password is not a credential. The address is judged first and is trimmed; the password is
   **not** trimmed, because a space is a character a password may contain, so one made of spaces
   is the server's to judge. The only thing this app claims to know is that a password is absent.
5. **A refusal is cleared by editing, and a cursor moving is not editing.** The handler compares
   the **text**, not the notification, because a `TextEditingController` also notifies on a
   selection change — which is exactly what the password field's own reveal toggle does, and
   revealing a password answers nothing the refusal said.
6. **A sign-in that succeeded leaves the button busy, deliberately.** The routing shell replaces
   this screen when the session opens; releasing the button first would offer a second sign-in
   against a session already being built.
7. **The user is answered before Sentry is told.** The old order awaited
   `Sentry.captureException` and only then set the message, so a slow or failing reporting
   transport delayed — or swallowed — the sentence on screen.
8. **The screen holds no Firebase type at all**, `setPersistence` included. Its swallowed failure
   is unchanged and now documented as the *expected* case: persistence is a web concept and every
   other platform answers `unimplemented`. The default adapter is built lazily on first
   submission, which is what lets the whole screen be widget-tested without initializing Firebase
   and left `lib/main.dart` untouched.

**What is not proved is that anybody has looked at it.** The chunk's own shape asked for one
device pass afterwards and the session instruction forbade the Android build, so this is 32 tests
and no eyes — including the `no rendered string contains dev.flutter.pigeon` assertion that would
have caught the original in 2026-08-04, asserted over every `Text` in the tree rather than over
the error slot alone. Queued below.

### A refused invitation names what will work, and only a transient failure invites a retry

Built 2026-08-08, the chunk after the sign-in repair and the same defect class on the other
surface a stranger meets. It closed finding 3. It changed `firestore.rules` not at all and
nothing in `functions/` either — 409 functions tests and 161 rules tests, both unchanged, are
the measurement. It moved no board row's colour, because it is a defect repair inside a row
that was already green.

**The queued chunk's own premise was wrong, and checking it was the finding.** This file said
`failed-precondition` was the code behind the refusal and attached an instruction to check the
server rather than guess from the flag name. The server throws **`permission-denied`** with
`{violation}` in `details` (`functions/src/staff/acceptance.ts:171`), where the violation is one
of **eight** tokens from `invitationAcceptanceViolation` in `staff/acceptancePolicy.ts`.
`versioned_proof_required` — the one the device hit — is the last of them. **The code alone
could never have identified it**, and the detail that could had never been read by anything.
`failed-precondition` is a real answer from these callables, but it is the five-minute
recent-authentication rule, not this.

**The rule is one sentence, and everything else follows from it:**

> **Only a failure this app knows to be transient may invite a retry.**

The guarantees are settled, not open:

1. **One module, because it is one server function.**
   `lib/tenancy/invitation_acceptance_failure.dart` is imported by both acceptance paths, since
   `acceptTenantInvitation` and `acceptVisibleTenantInvitation` are two `onCall` wrappers over a
   single `acceptInvitation` refusing through a single policy function. Two client copies would
   be two ways to word one server decision, and the first divergence would be invisible.
2. **`InvitationAcceptanceException` carries a code and a violation, and no message.** Same
   shape and same reason as `SignInException`. The violation may cross the boundary because it
   is a server-authored enumerated token rather than prose; the rule that no string this app did
   not write reaches a user is unchanged.
3. **Every violation the server produces is permanent for the invitation it refused**, so none
   of them says "try again" and each names the one thing that can move the user forward.
   Exactly two answers offer a retry — `unavailable`/`deadline-exceeded` and
   `resource-exhausted` — and a test asserts that partition over seventeen codes and both modes
   rather than describing it.
4. **The mode is carried because the server branches on it.** A `permission-denied` naming no
   violation means a rejected HMAC proof on the token path and an ineligible signed-in identity
   on the visible one. One sentence covering both would be vague on purpose.
5. **The sentence for `versioned_proof_required` does not tell the user to verify anything.**
   `visibleAcceptanceAllowed` is fixed at invite time and verifying afterwards does not change
   it, so that advice would be true-sounding, actionable, and useless — the same failure mode as
   "Please try again" in different clothes. It sends them to the emailed link and names
   `resendStaffInvitation`'s effect as the way to get another one.
6. **`email_unverified` is unreachable today and is mapped anyway.** The server's own
   `mode === "visible" && emailVerified !== true` guard throws before the policy function is
   consulted, so nothing produces that token. It is modelled because the server declares it;
   **do not delete it as dead code.**
7. **Reading a violation is tolerant, and it is the only tolerant thing in the file.** An older
   client meeting a violation a later server adds degrades to the code-level sentence rather
   than turning a refusal into an unrenderable failure. Shape is judged strictly and content
   permissively, in that order.
8. **The fallback offers no retry**, unlike the sign-in fallback, which does. A user staring at
   a sign-in screen has nothing else to do; here there is somebody to ask, an acceptance that
   failed for an unmodelled reason is far more often a policy refusal than a blip, and the
   button is still on screen for anyone who wants to retry anyway.

**`catch (_)` was the defect and the sentence was the symptom, and both halves were missing.**
Neither adapter converted anything — each called `httpsCallable(...).call()` with **no
`try`/`catch` at all**, unlike `FirebaseSendAccountVerificationCallable` beside them — and both
surfaces then discarded the error. So there was no code to branch on anywhere in the client.

**What is not proved is that anybody has looked at it**, and it cannot be proved locally
either: the identity that hits this refusal is the one whose invitation email never arrives on
the emulators. Queued below.

**Seven other surfaces still say "Please try again." and were deliberately left alone** — staff
invitation, resend, cancellation, email replacement, staff status, staff update, default tenant,
and tenant request. None of them strands a user with no way forward, which is what made this one
a finding, and widening to them would have made an unbounded chunk. Named so the next session
sees a decision rather than an oversight.

### The token layer is additive, and a density is a nested `Theme`

Built 2026-08-11, `design.md` §11 step 1. It changed `firestore.rules` not at all and nothing in
`functions/` either — `git diff` over both prints **zero lines**, which is a stronger measurement
than an unchanged suite count. It moved no board row, and **an empty screenshot diff was its pass
condition** rather than an embarrassment.

**Step 1 is additive, and that was a decision rather than the obvious reading.** `design.md` §11
says step 1 "changes no pixels"; `DESIGN-AUDIT.md` §4.8 found that conforming the token layer in
place moves the outlined button's label off mint at ~40 call sites, every caption to
`text.tertiary`, every card from radius 16 to 12, every input from 14 to 8 and off `bgMid`, every
chip off stadium, and the bottom sheet from 24 to 20 — the largest image diff of the whole
migration, attributable to nothing in particular. §6 decision 1 moved all of it into steps 2–5,
where each diff has one cause. The cost accepted with it: for several steps the app runs on a
half-migrated palette. **The divergences are asserted as divergences** in
`test/ui/tokens_test.dart`, so the step that closes one fails the test and removes the row in the
same change.

**Density is a nested `Theme` per screen.** Decided by the product owner this session, and it was
the one open item `DESIGN-AUDIT.md` §6 called "not cosmetic in any sense": §3 gives comfortable and
compact different body roles, `bodyMedium` is a single global value, and **all 756 bare `Text(`
call sites** in the migrated tree resolve to it through `DefaultTextStyle`, so one `ThemeData`
cannot hold two body sizes. A back-office screen will wrap its subtree in a `Theme` built from
`Theme.of(context).copyWith(...)` carrying the compact `AppTokens` and a `bodyMedium` swapped to
that density's body role. It keeps §3's "chosen by the screen" literal and edits **none** of the
756 sites; reading the role at every call site was the other correct answer and eventually edits
all of them.

**The mechanism is not in this chunk, only the half that decides.** `AppDensity` holds both value
sets, `bodyRole` is the seam the nested `Theme` reads, and `pointerOnly` carries §3's rule that a
touch device never gets 32px targets whatever its width — as data, so the widget that resolves
density cannot forget it. A widget test drives the seam end to end, so the decision is proved
rather than described. The widget arrives with the first compact screen.

**One thing to know before building it, found while writing the test and deliberately not fixed in
a frozen tree.** `AppTokens` implements no `==`, so equality is identity, and identity is free for
`AppTokens.dark` because a `const` instance is canonicalized. A `withDensity(...)` call **inside a
build method** allocates a new instance every build, which makes the enclosing `ThemeData` unequal
to its predecessor and rebuilds everything below the nested `Theme` on every parent rebuild. The
fix when that widget is written is to hold the compact token set as a `static const` beside
`AppTokens.dark` rather than to build one per frame — not to add an `==` over six nested role
objects.

The guarantees are settled, not open:

1. **A widget reaches a role, never a value.** §2.1's primitives are private to
   `lib/ui/tokens.dart`; a widget that cannot find its role needs `design.md` amended, not a hex
   code. That is `design.md` §0's order of operations and `claude.md` hard rule 2.
2. **The type roles carry no colour and name no family**, and both are asserted. Colour is a
   separate role and a widget pairs the two; the family is absent because `lib/theme.dart` names
   none either — this app asked for `Inter` for years and no `Inter` was ever bundled.
3. **A field named `type` would have broken the extension silently.** `ThemeExtension` declares
   `Object get type` and it is the key `ThemeData.extensions` is looked up under, so a field of
   that name makes `Theme.of(context).extension<AppTokens>()` answer `null` for ever with nothing
   failing to compile. The type roles are reached as `typography`; the analyzer reported the
   override as an `Information`-level hint, which is how it would have shipped.
4. **`AppTokens.of` throws rather than falling back.** A `Theme` built from a fresh `ThemeData`
   drops every extension, and answering with the defaults would render a compact screen at
   comfortable spacing — a wiring fault wearing a layout fault's clothes. The error names
   `copyWith`.
5. **A published contrast figure is asserted as a measurement, not as a floor.** Which is what
   caught §2.1's `text.primary` cell: white on `#0D1F16` is **17.147**, the document said 17.2,
   and the first run failed by 0.0028 over a 0.05 tolerance. Corrected to 17.1 in `design.md`.
   `DESIGN-AUDIT.md` §1.3 had recomputed 17.15, printed it beside the claim and concluded the
   figures were correct, so a recomputation had already looked straight past it.
6. **A spacing token is named by its value**, because §2.3 named the scale by index while §3 and
   §5.2 name it by value and the two collide on `space.16` — 64 against 16. Only the value reading
   is coherent: the index reading gives *compact* a larger section gap than comfortable, and
   `space.24` is not on the scale at all. §2.3 now says so. No value moved.
7. **Button `minimumSize` was not touched, and a test says so.** It is `Size(0, 48)` and §5.2's
   `md` is 40h; a token layer that shrank a touch target would break §9, which is pass/fail under
   `claude.md` hard rule 6.
8. **§3's "12 / 8" row padding is read as horizontal-then-vertical, by arithmetic.** The document
   never says which is which, comfortable is symmetric, and only compact carries the question: 8
   above and below a 20-high `body.md` line is 36 inside the 40 minimum, and 12 would need 44 and
   could not fit. Both readings are on the §2.3 scale; only one fits its own row height, and the
   test pins both halves of that.

**Three things are recorded rather than resolved, because resolving any of them means inventing a
value `design.md` does not define.** `claude.md` says the correct outcome there is a question.

1. **§2.1's container borders do not clear §9's 3:1 for a UI boundary.** Measured on
   `surface.base`: `border.subtle` 1.38, `border.strong` 1.97, the five status borders 1.38 to
   2.04. **The one boundary that carries information on its own — the focus ring — clears it at
   11.71**, and it is the only boundary §9 names with a value; a status is a container plus an icon
   plus a word, so its border is decoration rather than signal. That is an argument, not a
   resolution: either §9's boundary row means something narrower than every border, or ten colours
   have to become lighter. **This is a product-owner question, and it is the one item from step 1
   that a later step cannot quietly absorb** — `StatusBadge` is step 4 and it will need the answer.
2. **`mono` has no family and cannot have one yet.** §2.2 opens with "One family — Roboto" and its
   last row says "monospace", and this app bundles no font at all — which is also why the
   screenshot harness is currently more branded than the app, since it injects Roboto itself. The
   role carries its 13 / 18 / 400 metrics and **is not yet fit for the job §2.2 gives it**: record
   IDs and SKUs still render proportionally. A test asserts every role's family is null, so the
   day this is answered that assertion fails deliberately. Same decision as §1.6 of the audit,
   which is still open.
3. **Dark is the only palette, because it is the only one defined.** §12 asks whether dark is the
   only theme and answers nothing, and inventing a light palette is exactly what `claude.md`
   forbids. If one is ever decided it arrives as a second `AppColorRoles` instance and every widget
   that reads a role follows it without being edited, which is the reason the role layer exists.

### The ripple dies at the theme, and the press arrives with the button

Built 2026-08-11, `design.md` §11 step 2 and the first redesign step that changes what a person
sees. It changed `firestore.rules` not at all and nothing in `functions/` either — `git diff` over
both prints **zero lines**. It moved no board row: a redesign step is not a capability.

**§2.4 says to replace `InkWell` with an opacity-and-scale overlay, and that instruction is wrong
about this codebase.** There is exactly **one** `InkWell` in the migrated tree
(`checkout_cart_panel.dart:1029`); every other ripple comes from Material's own button, chip, tile
and icon-button implementations. `DESIGN-AUDIT.md` §4.5 found it and §6 decision 4 split the work
accordingly, and this chunk is the first half of that split.

The guarantees are settled, not open:

1. **One line reaches every ripple in the app.** `splashFactory: NoSplash.splashFactory` on
   `ThemeData`, because `InkResponse` falls back to it and the Material 3 button defaults delegate
   to it explicitly. Zero call sites were touched.
2. **`useMaterial3: true` is now stated rather than inherited, and that is load-bearing.** The
   **Material 2** paths in `outlined_button.dart` and `text_button.dart` hardcode
   `InkRipple.splashFactory`, so flipping that flag would silently restore ripples on two of the
   four tiers. It was unset before, which means true-by-default; a test asserts both it and the
   splash factory.
3. **The four button themes are the first thing in the app to read the token layer.** Filled and
   elevated carry `action.primary`, outlined carries `action.secondary`, text carries
   `action.tertiary`. `AppActionRole.hoverFill()` and `pressedFill()` answer §2.1's **two**
   different rules — the primary tier moves its container to named colours, the other three wash
   their own label at 8% and 12% — so the theme does not have to know which kind of tier it holds.
4. **`action.destructive` has no Material theme to attach to** and arrives with `AppButton` in
   step 3. So does the label repoint: the outlined button is **still mint** where §2.1 wants sage,
   and `test/ui/tokens_test.dart` still asserts that divergence. The overlay moved; the label did
   not.
5. **Only two rows of §2.1's state table are implemented, and the other three are named rather
   than implied.** Hover and pressed are here. **Disabled** still resolves through Material's
   defaults rather than to §2.1's `#1E3A2B` / `#5D7468`, and **loading** — container held, label
   replaced by a 16px spinner, width frozen — cannot be expressed in a `ButtonStyle` at all. Both
   are `AppButton`'s, which is why `AppActionRoles` already carries `disabledContainer`,
   `disabledLabel`, `disabledBorder` and `loadingIndicatorSize` with no reader.
6. **Focus resolves to the hover wash, and that is deliberately not §2.1's focus row.** §2.1 gives
   focus-visible a 2px ring at 2px offset, which is a border rather than an overlay and belongs to
   `AppButton` and to §9's audit in step 12. What a `WidgetStateProperty` must not do meanwhile is
   answer `null` for a focused button — that paints no overlay at all and would leave a keyboard
   user with less feedback than before the step.
7. **Scroll physics bounce everywhere with no glow**, through `SpiritScrollBehavior` on the app
   rather than a physics argument at each scrollable, because §2.4 says *everywhere* and that is
   not a rule three hundred list views can be trusted to remember. `MaterialScrollBehavior` is
   extended rather than replaced, so desktop scrollbars and the drag-device set are untouched.
8. **`PressSurface` is not here, and the reason is arithmetic.** It needs a spring substrate that
   does not exist — there are zero `AnimationControllers` in the migrated tree — so a step-2 sweep
   would build the springs, touch ~40 call sites, and touch all of them again in step 3 when
   `AppButton` replaces them. Inside `AppButton` it costs one pass.

**Two of the 101 screenshots moved, and what changed in them is a text caret rather than a
ripple.** Both are `31b-a-receipt-found`. The harness case ends with `tester.tap('Find receipt')`
and **no `pumpAndSettle`**, so the capture lands wherever the frame timeline happens to be: with a
ripple in flight the binding kept pumping frames and the field's caret was captured mid-blink in
its "on" phase, and with no ripple the tree settles immediately and the caret is captured "off".
The change is real and attributable — two consecutive runs of identical code hash identically —
but **it is not a picture of the thing this step did**. A ripple exists only mid-press and a glow
only mid-drag; neither can appear in a screenshot, which is why this step's verification is a
device check with the performance overlay on, per `design.md` §10, and why the five tests below
matter more than the images. **Expect that pair to move again at step 3**, when springs change the
frame timeline once more.

**One part of §11 step 2 is not done, and it is named rather than left as an implied
completion: route transitions.** The step's title includes them, and §2.4 requires anything
spatial to be a **spring** that retargets from its current position and velocity. A
`PageTransitionsBuilder` written on a duration would satisfy the step number while contradicting
the section it comes from, so it waits for the substrate `AppButton` builds in step 3. Step 2 is
therefore the ripple, the overlays, and the scroll physics — three of its four parts.

### A category is named, and a document ID is not a name

Built 2026-08-11, closing finding 5. It changed `firestore.rules` not at all and nothing in
`functions/` or `rules-tests/` either — `git diff` over all three prints **zero lines**. It moved
no board row, because a defect repair inside rows that were already green has no colour to move.

**The queued chunk's premise was wrong twice and checking it decided the work.** This file said
the defect sat in two surfaces and that the read-only catalog already resolved names correctly.
It held the identical `?? product.categoryId` fallback; it looked right on the device only
because nothing filed off its categories page was ever rendered through it. Counted against
source, **eight places named a category and every one of them could state an ID** — the
read-only catalog list, the "Manage catalog" list and its "Filed under" line, the "Correct"
dialog's off-page sentence, the correction confirmation's "Category: was …", the bulk selection
list, the bulk correction report, and the import preview. Six reached the ID through a `?? id`
fallback and two printed it outright; between them they held **five** copies of the lookup, and
only the "Filed under" line was unreachable.

**The rule is one sentence, and everything else follows from it:**

> **A document ID is not a worse name for a category. It is not a name.**

The guarantees are settled, not open:

1. **One resolution, in the file that defines what a category is.** `tenantCategoryNames`,
   `tenantCategoryLabel` and `tenantCategoryPhrase` live in `lib/tenancy/tenant_catalog.dart`
   beside `TenantCategory`, which every one of those surfaces already imports. Modelled on
   `tenantStaffLabel`, and the doc comment records where the two deliberately disagree: a staff
   label **keeps the UID visible** beside a resolved name, because a UID is what every sale,
   shift and audit record is attributed by. Nothing a person sees refers to a category by its ID.
2. **The unlisted state stays legible rather than blank.** `cat-not-cached` is not bad data — it
   is a product filed under a category the surface cannot read — so it reads **"Category not
   listed here"**. Two causes arrive there and the client cannot tell them apart: a business with
   more categories than one bounded page, and a category document that cannot be read at all. The
   wording says only what is known and claims neither.
3. **Two wordings for one answer, and the split is grammar.** `tenantCategoryLabel` opens a line;
   `tenantCategoryPhrase` sits inside one, because "filed under Category not listed here" is not
   a sentence anybody wrote. Both are asserted, so they cannot quietly become one.
4. **The import preview names what the sheet said, in three descending degrees of certainty**:
   the categories this surface read, then the row's own `categoryName` — a true name, because the
   server matched it against a real category to accept the row — then the unlisted phrase. **The
   ID is not a third degree.** The row's own name is second because the server's fold is
   case-insensitive, so what was typed can differ in case from what is stored.
5. **The import's wording is held with its plan.** `_importCategoryNames` is captured with the
   preview and cleared with it, because a commit re-sends the pages the preview sent and must word
   them identically while the route re-reads its categories between the two. A bulk correction
   needs no equivalent: its rows carry the wording they were planned with.
6. **A recorded decision was reversed on purpose.** "Stating the ID beats stating nothing" was a
   comment in two modules and the reason on a test. All three now say the opposite, per
   `design.md` §8 rule 1 — name things the way the shopkeeper does, never the way the system does.
7. **Reporting was left alone.** `SalesTotalsCategoryOptions.nameOf` with `?? 'one category'` is
   correct for a filter label, where naming an unlisted category is noise about something the
   reader did not ask about. Six resolution paths became two, and the second is that one.
8. **No behaviour changed.** No repository call, no state logic, no routing condition, no payload.
   Two functions gained a named parameter; every wire payload in the diff is byte-identical.

**The 101 screenshots moved not one byte, and that is evidence about the rest of the app rather
than about this repair.** `tool/screenshots/fakes.dart` files every seeded product under one of
its three seeded categories, so no capture reaches the branch this chunk changed and the four
that render a category *could not* move. The repair is covered by the seven tests, two of which
assert over **every `Text` in the tree** — `cat-` and `ct_`, the seeded shape and the shape
`buildCategoryIntent` derives — rather than over the slot that was wrong, because the two
defective surfaces were exactly the two nobody was looking at.

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

---

## Open decisions

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

### Three design-system questions the redesign has refused to answer

The first two were opened on 2026-08-11 by building step 1 and the third by building step 2. None
is answerable from `design.md`, and `claude.md` forbids inventing the value that would close any of
them, so they are here rather than in the code.

**Do §2.1's container borders have to clear §9's 3:1?** Measured against `surface.base`:
`border.subtle` 1.38, `border.strong` 1.97, and the five status borders between 1.38 and 2.04. §9
makes 3:1 pass/fail for "UI boundaries" and lists no exemption. Two readings, and they lead to
different work:

1. **The boundary rule means a boundary that carries information on its own.** Under it the system
   already conforms: the focus ring — the only boundary §9 names with a value — clears 3:1 at
   11.71, and a status is a container *plus an icon plus a word*, so no meaning rests on its border.
   Nothing to do.
2. **It means every border.** Then ten colours have to become lighter, and §2.1's status palette is
   re-derived rather than adjusted, because a border cannot brighten without the container behind
   it moving too.

**Step 4 is where this stops being theoretical** — `StatusBadge` is that step, and it draws the
container the whole argument is about. Answer it before then, not during.

**A third was opened by step 2, and step 3's second half needs it: what is `AppSelect`?** §5.1
names it as one of the load-bearing components and **nothing exists for it to replace** —
`DESIGN-AUDIT.md` §6 says either drop it from §5.1 or re-scope it to the `ChoiceChip` group pattern
that is actually in use on the catalog, bulk, and reporting surfaces. Both are defensible and only
one of them is a component. It is not answerable from `design.md`, so it is here rather than
decided inside the chunk that meets it.

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
- **Never free a port by killing an emulator you did not start** — a held run may be
  holding seeded data. Read its command line; `--hold` is the tell.
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
re-running on a different day moves about **39 of the 101 images** with nothing behind them;
tracking the output would put those 39 into every future diff. The harness is tracked, the
output is not, and a baseline is regenerated the same day it is compared against.

---

## Next bounded chunk

**`design.md` §11 step 3, first half: `AppButton`.** Step 2 is done and step 3 is queued as **two**
chunks rather than one, because the two halves share nothing but a step number.

**Why `AppButton` is a chunk on its own.** The call-site migration is mechanical — roughly forty
buttons — and the cost is `claude.md` hard rule 5, which wants every state in the screenshot
harness: four tiers × three sizes × nine states. That matrix is the work, not the widget.

**What it must carry, all of it already decided and none of it invented here:**

- **`PressSurface` is built inside it**, per `DESIGN-AUDIT.md` §6 decision 4 — scale 0.97 on
  `spring.snappy`, interruptible from its current position and velocity, never
  `forward()`-from-zero on a retrigger. **This is the chunk that builds the spring substrate**,
  because there are zero `AnimationController`s in the migrated tree today.
- **Step 2's unfinished fourth part rides with it: route transitions.** §2.4 makes anything
  spatial a spring, so a transition cannot be written before the substrate above exists. It is
  carried here rather than left behind step 2, so it does not become the part nobody owns.
- **The fourth tier arrives.** `action.destructive` has no Material button theme and exists only
  once `AppButton` does. §2.1's rule that fixes the sale screen — *Clear this sale* is
  destructive, *Save sale* is primary — is step 7's to apply, not this one's.
- **Two divergences close and their assertions come out of `test/ui/tokens_test.dart` in the same
  change**: the outlined button's label goes from mint to `action.secondary`'s sage, and the
  primary label from `bgDark` to `#0A0F0C`. That test names them as divergences on purpose so the
  step that closes one fails it.
- **§9's focus ring**, 2px at 2px offset, which step 2 deliberately left as a hover-strength
  overlay because a ring is a border rather than an overlay.
- **`minimumSize` stays 48.** §5.2's `md` is 40h and §9's touch target is pass/fail under hard
  rule 6; a component that shrinks a target is a defect however well it matches the table.

**Explicitly excluded from it:** `AppTextField` and `AppSelect`, which are the step's second chunk
— that is where finding 4's missing category picker gets closed and where the two incompatible
field implementations become one; every other component (`StatusBadge` is step 4, `AppScaffold`
step 5); the sale screen's action prominence, which is step 7; every server file and
`firestore.rules`; deployment; and every standing exclusion below.

**App Check was passed over a fourth time, and this is the reason rather than the ordering.** The
previous session queued it here on this file's own instruction — the device findings had run out,
and it is the only queued item that would move a red row. **The product owner redirected to the
redesign**, having asked why the reskin chunks were not being taken. That is a decision, not
drift, and it is recorded here so the next session does not re-derive it as an oversight. The
research chunk is unchanged and sits at the head of the preference order below: what a **Windows**
build can actually attest with, the `1:…:web:…` app-ID registration mismatch, and the three
options costed rather than chosen. **It is now behind two redesign chunks, and the fifth
deferral needs its own reason.**

**The device-run debt is now five chunks deep, and one of the five cannot be verified any other
way.** Nobody has looked at the sign-in repair, the invitation repair, the category repair, commit
`1b2b13b` — which repainted every screen by wiring a `ColorScheme` the theme had named and never
used — or **the ripple kill**. Between them that is 63 tests, 101 screenshots, and no eyes.
**Whenever the next device run happens, those come first** — for sign-in, an empty password, a
wrong password, then editing a field; for the invitation, the refusal an identity that was
unverified at invite time receives; for the category wording, the seeded product filed under
`cat-not-cached` in "Manage catalog" and an import preview of a sheet naming `Bakery`; for the
theme, any screen with a button, a spinner or an icon on it. The invitation one **cannot be
reproduced on the emulators at all** (finding 6): it needs either a real Brevo key or an
invitation written by hand with `visibleAcceptanceAllowed: false`.

**The ripple kill is a different kind of debt from the other four and should be treated as
one.** The other four are repairs whose tests are genuine evidence and whose device pass would be
confirmation. **Step 2's central claim cannot be tested at all**: a ripple exists only mid-press
and an overscroll glow only mid-drag, so `design.md` §10 makes its verification a device check
with the performance overlay on. The five tests below prove the theme is wired the way §2.1 and
§2.4 describe — including at the `InkWell` the button actually builds, which is where a
`ButtonStyle` merge could have lost — and they prove nothing about how it feels. **Press a
`FilledButton`, an `OutlinedButton`, a `ChoiceChip` and a `ListTile`, and drag a list past its
end.** That is a prerequisite attached to the next device session, not a chunk of its own; step 3
should not ship before somebody has done it, because `AppButton` builds its press on top of this.

**One exclusion named because it has been inherited for many consecutive chunks: the printed
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
  transitions, is deliberately not done** and rides with `AppButton`: §2.4 requires a spring, and
  a transition written on a duration would satisfy the step number while contradicting the section
  it comes from.
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
- **The design system, step 3, second half: `AppTextField` and `AppSelect`** — the other half of
  the current chunk, and the one that closes **finding 4**, the add-product form's category picker.
  It is where the two incompatible field implementations become one: bare `TextField` in the
  migrated tree, and `PillInput` on sign-in, which draws its own well, its own label, and its own
  focus glow while reading nothing from the theme. Roughly twenty call sites. `AppSelect` has
  nothing to replace and `DESIGN-AUDIT.md` §6 says to drop it from §5.1 or re-scope it to the
  `ChoiceChip` group pattern actually in use — **that is a question for the product owner before
  this chunk starts, not a thing to decide inside it.**
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
  **split, and the second half is done.** Finding 5 closed on 2026-08-11; finding 4's repair is
  the add-product form's layout and belongs to the redesign's step 3, which rewrites that form.
  The pair was queued together because both are about a category being named the wrong way, and
  they came apart because only one of them is wording.
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
so there is no second palette to write and inventing one is what `claude.md` forbids. **The
breakpoints and the content widths** — §4.1's three names and §4.2's 720 / 1200 / 420 are not in
the token layer, because 768 is already declared twice (`records.dart:26`,
`checkout_cart_panel.dart:550`) with a third mechanism in `login_screen.dart:47`, and a fourth
declaration that removes none of the three makes the drift worse; unifying them is a rewiring step
in §4.1's own words. **The eight animated assets and the device-tier system** — step 10, ninth in
the order deliberately, because building assets before the substrate produces a slow app with nice
animations in it. And **`lib/pos/**` and `lib/screens/**` throughout, which `claude.md` hard rule 3
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

Nothing of it is excluded now; it is queued as step 9 of the redesign, which is far enough down that
the queue position is doing the work the exclusion used to.

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
