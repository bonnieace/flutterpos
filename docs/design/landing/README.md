# Landing page — a design, 2026-09-23

Four artboards for the marketing site. Open [`index.html`](index.html) in a browser; each page is
self-contained HTML with no build step and no dependency on the repo.

**This is a proposal, not a record.** It is not a decision, it does not describe what to build
next, and nothing in it should be quoted back as a constraint. It draws pixels only — no widget,
test or token was changed to make it.

## The brief

[`docs/marketing/landing-page-prompt.md`](../../marketing/landing-page-prompt.md), with
[mobilesasa.com](https://mobilesasa.com/) named as the design inspiration.

This is the **only** artboard set in `docs/design/` that is not a screen of the app. It draws a
website, so it does not owe `design.md` its layout bands, and `AppScaffold`, `RecordList` and the
rest do not appear. What it does owe the app is the palette, the button geometry and rule 4.

## Paper, end to end

The first draft was dark green throughout with two light bands — reconciliation and pricing —
carrying the figures. Those two were the ones that worked, so the whole page moved onto paper.

That did not mean inventing a palette. `AppReportRoles` already is one: `paperWhite`, `paperWash`,
`paperInk`, `paperMutedInk`, `paperRule` and the eight chart hues — the ground every report and
chart in the app is drawn on. White and `paperWash` alternate to break the scroll, and nothing on
the page is a colour the product did not already own.

**Two things stay dark and both earn it.** The phone in the hero, because that is the product and
a dark device against white is the oldest trick there is for making a screenshot the thing you
look at. And the closing band, so the last thing on screen is the app's own world rather than
another white form.

**The primary button went the other way.** Mobile Sasa's CTA is a saturated blue and the obvious
move was a saturated green. It reads consumer — an app you download, not a system you run your
shop on. Near-black ink (`#15251B`) is the serious register the brief asks for, and it leaves the
green to do what it is better at: kickers, ticks, and the day that checks out.

## The copy register

Every heading is short, makes a claim, and uses no word a shopkeeper would not. The test each one
had to pass: could you say it out loud to someone behind a counter without sounding like a
brochure.

| Section | Heading |
| --- | --- |
| Hero | *Tonight the drawer adds up. Or you'll know why.* |
| Problem | *The till was never the problem.* |
| Features | *Six jobs, all the way done.* |
| Reconciliation | *Most systems tell you what they were told. Uzapay checks.* |
| Verticals | *Shops where cash moves fast and hands change often.* |
| Setup | *Sign up before lunch. Sell by dinner.* |
| Pricing | *Free while we're still building it.* |
| FAQ | *Straight answers.* |
| Closing | *Stop guessing what today was worth.* |

The feature cards took the same treatment. *"Sell, even with no signal"* became **"The network
dies. You don't."**; *"Every shift accounted for"* became **"Every drawer has a name on it."**;
*"The right staff, the right screens"* became **"Your cashier sees a till. You see the business."**
The technical detail did not disappear — it moved down into the three ticks under each card, where
somebody who wants it will look and nobody else has to read it.

One line is deliberately sharper than the rest: **"Short? You'll know whose, and when."** It names
the fear the owner actually has. The card above it does the softening — *"Not to catch anyone out
— so that honest mistakes stop looking like something worse."*

## What the inspiration gave

[`landing-inspiration.html`](landing-inspiration.html) is the long answer, with each of Mobile
Sasa's twelve devices marked *took*, *bent* or *left*. The short answer:

**Its shape and its ground both transfer.** Hero → fact band → product cards → verticals → a
technical section → transparent KES pricing → FAQ is a good order for this buyer, and the white
page is most of why theirs stays readable at that length. Even the fine print survives: *"No card,
no contract"* is kept nearly word for word.

**Its evidence does not.** They open on 2,000+ organisations, 99.9% uptime, <5 sec delivery and
*since 2015*, then close with forty client logos and three testimonials. That is the strongest
material on the page and every piece is on the brief's *do not claim* list. A beta with no public
customers that prints an uptime figure has told its first lie above the fold.

So **the band stays and its contents change** — from traction to product. *No signal?*, *4 roles*,
*One story*, *KES*. Same glance, same reassurance, each one checkable by anyone who signs up this
afternoon. The inspiration board draws both versions side by side, because the four figures that
were *not* used are the most persuasive thing that could have gone there.

**The logo wall has no replacement.** It is left empty rather than filled with something weaker.
That is a real cost — the highest-converting block on the reference page — and it is the price of
the constraint.

## Three choices worth arguing with

**The reconciliation section is the centre of the page.** Four numbered beats and a seven-day
strip showing three days *Checks out*, two *Re-checking*, one *Needs you*. The reference puts its
equivalent near the bottom as credibility furniture; here it is the argument, and it kept the
heading the developer picked out.

**The hero shot shows a problem, not a triumph.** The phone carries *3 days don't add up* against
an amber flag. A landing page normally shows the happy state — but the product's whole claim is
that it tells you when something is wrong, so the happy state is the wrong screen to show.

**The awkward FAQ answer is in slot two.** *"Does it take M-Pesa or card payments?"* — answered
**no**, high enough that nobody can miss it. Given the length of the *do not claim* list, the page
either raises that itself or gets found out on day one.

## Copy the page does not make

Checked against the brief's list. No customer accounts or loyalty, no suppliers or purchase
orders, no tax or VAT calculation, no payment processing, no barcode scanning, no fraud detection
or AI, no accounting-package export, no consolidated cross-shop reporting, no uptime figure, no
customer count, no logos, no testimonials.

Two claims carry their limit rather than being dropped:

- *"Can I run more than one shop?"* — yes, **and** there is no combined report across them yet.
- *"Does it take M-Pesa?"* — no, **and** the payment method is still recorded so the figures are
  right.

One line on the boards is a claim about the business rather than the build: **"Now in beta with
shops across Kenya."** It is true only if it is true — check it before this ships.

## Five colours are not tokens

The status roles are drawn for dark chrome and none survives white: `#F2C14E` manages 1.9:1. The
three the checked-week strip needs are darkened until they pass, keeping their hue — `#1A7A33`,
`#8A6A0F`, `#C0392B`. Two greys join them: `#6B756F` for fine print and `#8A938D` for chart axis
ticks.

**If this page is built, all five want to join the token layer beside `AppReportRoles`** rather
than live in a stylesheet. They are the only values here that are not already a token, and they
are flagged rather than quietly inlined because rule 2 is what it is.

## Accessibility

Rule 4 is pass/fail, so [`landing-states.html`](landing-states.html) shows the pass: an
eleven-row contrast table against the ground each colour is actually drawn on, every control in
its enabled, hover, pressed, focus-visible, loading and disabled states, and the day strip drawn a
second time in greyscale to prove the three statuses separate without colour.

One row is deliberately under 4.5:1. `#8A938D` at 3.2:1 is used for chart axis ticks and the
collapsed FAQ caret and for nothing that has to be read — it clears the 3:1 bar for non-text and
graphical objects. Every word on the page is at 4.8:1 or better. Touch targets are 48 minimum,
52 for the phone's full-width CTAs.

## What these are not

**They are not a site.** No page here is responsive — the desktop and phone boards are two fixed
widths drawn separately, the way every other artboard in this directory works. A real build has to
reconcile them at the breakpoints between.

**The screenshots are drawn, not captured.** The phone in the hero and the report card beside it
are CSS approximations, close enough to judge the composition and not close enough to ship. The
brief says to use real screenshots; `flutter test tool/screenshots` produces them and nothing here
has been through it.

**No copy has been reviewed by anyone.** Every sentence is a first draft written to fill the
shape, including the FAQ answers that make commitments about data export and account deletion.
