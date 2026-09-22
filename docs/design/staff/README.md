# Staff screen — a design, 2026-09-20

Five artboards for `TenantStaffDirectoryPanel`. Open [`index.html`](index.html) in a browser;
each page is self-contained HTML with no build step and no dependency on the repo.

**This is a proposal, not a record.** It is not a decision, it does not describe what to build
next, and nothing in it should be quoted back as a constraint. It draws pixels only — no widget,
test or token was changed to make it.

## The question the screen is opened with

Nobody opens Staff to browse a directory. They open it because somebody is starting, somebody's
invitation did not land, or somebody should no longer be able to sign in.

The screen as built draws a staff member as a `RecordItem`: identity, attributes, provenance,
actions, every attribute at one weight. That is right for a catalog row. Here it means
`invitationStatus` is one line among six — so *three invitations expired last week* is invisible
unless you set the status filter to Invited and read every row.

So the badge carries **access standing** rather than membership status, and the invitations in
trouble are named in a callout at the top of the list. Same reasoning as
[`shift_history_card.dart`](../../../lib/shift/shift_history_card.dart) applied to a different
record: one fact the screen exists to settle, stated where a person looks.

Seven standings, each a container plus a glyph plus a word:

| Standing | Condition | Promoted action |
| --- | --- | --- |
| Active | `status == active` | — |
| Invited | pending, sent, deadline ahead | — |
| Not sent yet | pending, delivery has not run | Send now |
| Link expired | pending, deadline passed | Resend |
| Email rejected | pending, delivery undeliverable | Replace email |
| Invitation cancelled | cancelled before acceptance | — |
| Deactivated | `status == inactive` | — |

The two problem standings promote one button out of the kebab, and they promote *different* ones:
resending to a rejected address bounces again.

## Three deliberate departures from the app as built

1. **Role stops wearing the action green.** `_StaffRolePill` tints itself with
   `action.primary.container` — the same green as the Active badge and the Invite button, three
   jobs for one colour on one row. Roles are neutral here (`surface.field` + `borderStrong`);
   Owner and Administrator alone keep `accent.privileged`, which is the one identity colour the
   token layer documents as carrying meaning.

2. **The avatar is a ring, not a fill.** `_StaffAvatar` puts `text.onAccent` white on all six
   `accent.identity` colours, and its comment says they were chosen so it passes on all of them.
   White on `#FFA726` is **1.94:1**. Tinting the fill does not rescue it either — `#AB47BC` on its
   own 16% tint is 3.12:1. This draws `surface.field` behind the initials with a 2px identity ring:
   11.8:1, and the hue stays decorative, which is all it was ever asked to be.

3. **A *Needs attention* filter chip**, counting expired and undeliverable together — the same
   split `ShiftStanding.needsAttention` already makes on shift history.

Sort order is untouched. Floating the actionable rows to the top would be a behaviour change, and
the callout does that job without one.

## What the sample content is allowed to say

Every line on a row comes from a field `TenantStaffSummary` actually holds. Active rows carry no
"signed in yesterday" line because the model has no such field. The callout names two people and
two causes because `invitationExpiresAt` and `invitationDelivery` are both on the record.

## What these files are

Authored as `.dc.html` artboards for a Design canvas and converted to standalone pages — the
`<x-dc>` / `<helmet>` wrappers and the logic block are gone, and the `<helmet>` contents are now
the `<head>`. No artboard used a hole, a loop or a branch, so nothing was lost in the conversion.

They are HTML mockups. They do not prove the app runs, they cannot show motion, and the spring
behaviour the real screen owes `AppMotion` is not represented at all.
