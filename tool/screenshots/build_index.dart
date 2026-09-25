/// Writes `screenshots/index.html`: every screen, web beside mobile.
///
/// Run after the captures:
///
/// ```
/// flutter test tool/screenshots
/// dart run tool/screenshots/build_index.dart
/// ```
///
/// It reads the directories rather than a list, so a screen added to a capture
/// file appears here without this file being edited. Only the caption is
/// authored, and a screen with no caption still appears - captions describe, they
/// do not decide what is included.
library;

import 'dart:io';

/// What each screen is, keyed by file name without the extension.
const Map<String, String> captions = <String, String>{
  '01-sign-in':
      'Signing in. The desktop layout carries the on-screen keypad for a till '
      'with no hardware keyboard; below 768 logical pixels it is dropped.',
  '02-choose-business':
      'The business selector: two memberships this identity can open and one '
      'whose invitation has not been accepted.',
  '03-verify-email-address':
      'The same selector for an unverified address, which can neither request a '
      'business nor accept an invitation until it is verified.',
  '04-request-a-business': 'Asking for a new business from the selector.',
  '05-no-businesses': 'An identity with no memberships at all.',
  '06-accept-an-invitation':
      'Accepting a staff invitation from an emailed link, with the token proof '
      'the link carried.',
  '07-invalid-invitation-link': 'A malformed or incomplete invitation link.',
  '08-cannot-open-your-account':
      'Bootstrap failed. Retry and sign out are the only two ways out.',
  '09b-platform-active-and-suspended':
      'Platform administration: suspending or reactivating a live business.',
  '09d-platform-global-user-status':
      'Platform administration: one exact UID at a time. There is deliberately '
      'no user search and no bulk action.',
  '10-business-home-owner':
      'The landing route as an owner: branding, the shift panel, what this '
      'device still holds, and every route the role is offered.',
  '11-business-home-cashier':
      'The same route as a cashier. Four of the owner’s buttons are absent '
      'rather than disabled.',
  '12-shift-open-and-counted':
      'A shift opened and its cash count started, from the same panel.',
  '13-staff-directory':
      'Staff. Above 1024 logical pixels this is a table; below 768 the same '
      'records are cards. Compare the two.',
  '13b-staff-directory-editing':
      'The same directory with one member’s form open, which is the state '
      '`RecordItem.details` exists for.',
  '13c-staff-directory-read-only':
      'The same directory as a manager, who may read it and change nothing. '
      'The only session its standing is true of.',
  '13d-invite-staff':
      'The invitation form open. The one action on this route that names no '
      'existing member, and the first picture of it.',
  '13e-resend-an-invitation':
      'Queueing a second invitation to a pending hire. Three of these forms '
      'need a pending membership, and Faith Njeri is the one seeded member '
      'who has one.',
  '13f-cancel-an-invitation':
      'Withdrawing an invitation, which is destructive and asks for the '
      'reason the audit record keeps.',
  '13g-replace-an-invitation-email':
      'Cancelling a pending membership and queueing a fresh invitation to a '
      'corrected address, stated as the one act it is.',
  '13h-deactivate-a-member':
      'Removing a member’s access. The destructive direction of the status '
      'action; activating is the same form and gives a till back.',
  '14-new-sale':
      'The till. On a desktop the cart is a second pane; on a phone it is a '
      'sheet reached from a badge.',
  '14b-new-sale-browsing-with-a-cart':
      'The staged browse flow mid-sale, at the two widths that have one. The '
      'tile a cashier has rung up twice carries the count and the action '
      'border; the bar carries the total the customer is waiting for.',
  '15-new-sale-with-a-cart':
      'Three products rung up, with the tender still to be chosen.',
  '16-checkout-settings':
      'The one surface that publishes what the till prices in. Owner and '
      'administrator only.',
  '16b-checkout-settings-read-only':
      'The same route in a build with no writer. The notice is the one that was '
      'a bare sentence until 2026-08-22, because no capture had ever contained '
      'this branch.',
  '17-read-only-catalog': 'The catalog every active member may read.',
  '17b-read-only-catalog-cashier':
      'The same catalog as a cashier, which is the role the brief names and '
      'no capture had. All three stock routes are offered to the build and '
      'the screen withholds them, so the narrowing is the screen’s own.',
  '18-manage-catalog':
      'Adding a category, adding a product, and the product list a correction '
      'starts from.',
  '18c-manage-catalog-read-only':
      'Manage catalog with no writer: both read-only notices at once. One says '
      'the catalog cannot be changed at all, the other stands where the form '
      'would be.',
  '18b-catalog-notice':
      'What a write did, in place. The first picture of a notice on any '
      'screen: they appear only after a write, so no capture had one.',
  '18d-manage-catalog-manager':
      'Manage catalog as a manager. Every row offers Correct and none offers '
      'Retire, and the notice under the list says why. Owner and '
      'administrator only, from one role list.',
  '19-correct-a-product':
      'Correcting one product: all five editable fields at once, with clearing '
      'a recorded cost as its own act.',
  '19b-correct-a-product-manager':
      'The same correction form as a manager: three of the five fields, and '
      'an info notice standing where the price, the cost and the clear-cost '
      'act were.',
  '19c-correct-a-product-image':
      'The correction form with its image well: the bordered panel the old '
      'catalog form drew, restored 2026-08-25. Nothing chosen yet, so the '
      'cut-out is drawn disabled rather than removed.',
  '19d-correct-a-product-image-chosen':
      'A photograph chosen, at the size the old form drew it. Two columns on a '
      'desktop and the picture above the fields on a phone, which is the '
      'arrangement the old form used.',
  '19e-cutting-out-a-background':
      'A cut-out in flight. The button holds its own container and swaps its '
      'label for a spinner; everything else in the well is held.',
  '19f-cut-out-refused':
      'A refused cut-out. Every refusal states the same thing, which is the '
      'thing an operator needs after one: the photograph they chose is still '
      'there.',
  '20-bulk-changes-and-import':
      'One field across many products, or a whole catalog from pasted rows. '
      'Both preview before they write.',
  '20b-bulk-report-previewed':
      'The per-row report of a preview. A previewed row is awaiting rather than '
      'confirmed, because nothing has been written yet.',
  '20c-bulk-report-committed':
      'The same three rows after the commit. Only the row that was actually '
      'written changes status; unchanged and refused mean the same either way.',
  '21-product-stock':
      'One product’s recorded stock, its ledger, and the only path in the '
      'app that sets stock to an arbitrary figure.',
  '22-stock-corrections': 'Every manual correction recorded in the business.',
  '23-stock-movements':
      'Everything that moved stock, of which manual corrections are one source.',
  '24-one-product-ledger': 'One product’s whole ledger.',
  '25-daily-summary':
      'The reconciled daily figures. Profit appears only where every sale line '
      'behind it carries a cost; otherwise the count of lines without one is '
      'shown in its place.',
  '26-sales-totals':
      'Totals over a chosen period, member, or category, with the tender split.',
  '27-reconciliation-status':
      'Whether one business day’s published totals are current, and the '
      'runs behind them.',
  '27b-reconciliation-unusable-lines':
      'The same day with sale lines the server could not use, which is the '
      'only state that draws a second stat tile.',
  '28-reconciliation-differences':
      'The differences reconciliation found and could not resolve.',
  '29-one-reconciliation-run': 'One unit of server reconciliation work.',
  '30-shift-corrections':
      'Every closed shift whose recorded sales were corrected, and why.',
  '31-find-a-receipt': 'Receipt lookup, before anything is entered.',
  '31b-a-receipt-found': 'The sale a receipt number resolves to.',
  '32-shift-history':
      'Closed shifts, with counted cash and recorded sales shown exactly as the '
      'server holds them.',
  '33-shift-sales': 'The sales recorded during one shift.',
  '34-returns-on-a-sale':
      'Returns against one sale: a pending one awaiting verification, and the '
      'form that records another.',
  '15b-sale-saved-but-not-printed':
      'A sale that saved and whose receipt did not reach the printer. Two '
      'notices, because two different things happened: the sale is durable and '
      'the paper is not there.',
  '15c-sale-refused':
      'A save that did not happen. The sale is still in the cart, every line '
      'kept, and the sentence names no cause it cannot know - which is the '
      'defect the served mobile cart has and this does not.',
  '36a-printer-not-set-up':
      'Printer settings before a business has one. There is no default address '
      'and never will be, so until this is filled in every receipt queues.',
  '36b-printer-configured':
      'A configured printer, with the reachability test that connects and '
      'closes without wasting a roll.',
  '36c-printer-settings-read-only':
      'The same route in a build with no writer and no transport: neither Save '
      'nor Test this printer is drawn, because a control that cannot work is '
      'worse than a missing one.',
  '36d-printer-settings-not-read':
      'A printer document this build cannot parse. Deliberately not reported '
      'as "no printer configured", which would invite setting up one that '
      'already exists.',
  '37a-no-receipts-waiting': 'The device queue with nothing in it.',
  '37b-receipts-waiting':
      'One receipt the printer did not answer for and one still waiting its '
      'turn. Send again is offered only on the first.',
  '37c-receipts-waiting-read-only':
      'The queue with no retry injected: a statement of what is waiting, and '
      'no control that would fail.',
  '37d-receipts-some-unreadable':
      'A queue holding a durable record this build cannot parse. The count is '
      'stated rather than the record being silently dropped.',
  '34b-returns-as-a-cashier':
      'The same returns route as a cashier, who may record a return and '
      'not verify one. The only session that notice is true of.',
  '35-activity-log':
      'The business’s own event trail, including the changes the platform '
      'made to it.',
  'suppliers-active':
      'Who stock is bought from, as a manager reads it: active suppliers '
      'alphabetically, each with when a delivery was last recorded.',
  'suppliers-every-standing':
      'The same directory showing every standing. Only the inactive supplier '
      'wears a badge; the ordinary case says nothing.',
  'supplier-record':
      'One supplier: how to reach them, and when they last delivered.',
  'supplier-record-inactive':
      'An inactive supplier keeps its record and history, and can be offered '
      'again from here.',
  'supplier-delivery-form':
      'Receiving a delivery from a supplier’s record: the reference, and '
      'each product that arrived with what it holds now. A unit cost is '
      'optional; blank keeps the product’s cost.',
  'supplier-delivery-confirm':
      'Every stock and cost change the delivery makes, stated as from and to '
      'before anything is queued.',
  'supplier-record-deliveries-open':
      'A supplier’s deliveries, newest first, one opened to its lines. The '
      'value says how many lines named no cost.',
  'production-batches':
      'Every batch made, newest first, with what one unit cost. One is opened '
      'to its costs and says how the cost per unit moved.',
  'production-record':
      'Recording a batch, started from the last one of the same product. The '
      'warning about Expenses is opened; the figures follow the rows as they '
      'are typed.',
  'production-confirm':
      'The stock and cost change a batch makes, stated before it is queued.',
  'supplier-report-sheet':
      'The supplier report asks which period and, beside it, which supplier - '
      'all of them first, inactive ones listed and labelled.',
  'supplier-add':
      'Adding a supplier. Only the name is required; the name is checked '
      'against every other supplier before it is queued.',
};

/// The viewport directories, in the order a screen's figures are laid out:
/// widest first.
///
/// **Only `web` and `mobile` are written for every screen.** The other three are
/// written by the matrices whose subject is width itself, which is why the loop
/// below skips a missing file rather than expecting one per screen. §4.1 has
/// always had three bands, but `medium` only became a band with a *rendering* of
/// its own in step 6's second half, and photographing every screen at every
/// width for bands almost all of them are indifferent to would be hundreds of
/// images nobody reads.
///
/// `desktop-narrow` and `compact-wide` are the two regions §4.2's page maxima
/// cut inside §4.1's bands - see their notes in `harness.dart`. They are listed
/// beside the band they sit in rather than at the end, so a row of figures reads
/// left to right as one continuous narrowing.
const List<String> viewports = <String>[
  'web',
  'desktop-narrow',
  'tablet',
  'compact-wide',
  'mobile',
];

void main() {
  final root = Directory('screenshots');
  if (!root.existsSync()) {
    stderr.writeln(
      'No screenshots directory. Run `flutter test tool/screenshots` first.',
    );
    exitCode = 1;
    return;
  }

  final names = <String>{};
  for (final viewport in viewports) {
    final directory = Directory('screenshots/$viewport');
    if (!directory.existsSync()) continue;
    for (final file in directory.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (name.endsWith('.png')) {
        names.add(name.substring(0, name.length - 4));
      }
    }
  }
  final ordered = names.toList()..sort();

  final html = StringBuffer()
    ..writeln('<title>Chilltent POS — every screen, large and small</title>')
    ..writeln(_style)
    ..writeln('<header>')
    ..writeln('<h1>Every screen, large and small</h1>')
    ..writeln(
      '<p>${ordered.length} screens, each rendered at a desktop browser window '
      '(1440&thinsp;&times;&thinsp;900) and a phone '
      '(411&thinsp;&times;&thinsp;891). The matrices whose subject is width '
      'itself are rendered at three more: a tablet '
      '(834&thinsp;&times;&thinsp;1000), the floor of the desktop band '
      '(1024&thinsp;&times;&thinsp;768), and the widest window that is still a '
      'phone layout (767&thinsp;&times;&thinsp;1000). Those three are the '
      'regions &sect;4.1&rsquo;s bands and &sect;4.2&rsquo;s content maxima cut '
      'between them, and a screen indifferent to width has no figure there. All '
      'are exact viewports: what you see is what a person sees on arrival, '
      'before scrolling. Where a screen is taller than its window, '
      '<em>whole screen</em> opens the same render at full height.</p>',
    )
    ..writeln('</header>');

  for (final name in ordered) {
    final caption = captions[name];
    html
      ..writeln('<section>')
      ..writeln('<h2>${_title(name)}</h2>')
      ..writeln(if_(caption != null, '<p class="caption">$caption</p>'))
      ..writeln('<div class="pair">');
    for (final viewport in viewports) {
      final shot = 'screenshots/$viewport/$name.png';
      if (!File(shot).existsSync()) continue;
      final full = File('screenshots/$viewport-full/$name.png').existsSync()
          ? '<a href="$viewport-full/$name.png">whole screen</a>'
          : '';
      html
        ..writeln('<figure class="$viewport">')
        ..writeln('<a href="$viewport/$name.png">')
        ..writeln('<img src="$viewport/$name.png" alt="$name on $viewport">')
        ..writeln('</a>')
        ..writeln('<figcaption>$viewport $full</figcaption>')
        ..writeln('</figure>');
    }
    html
      ..writeln('</div>')
      ..writeln('</section>');
  }

  File('screenshots/index.html').writeAsStringSync(html.toString());
  // Written here rather than authored in place, so the whole directory is
  // reproducible: deleting `screenshots/` and re-running restores the prose
  // along with the pictures instead of quietly losing it.
  File('screenshots/README.md').writeAsStringSync(_readme);
  stdout.writeln(
    'Wrote screenshots/index.html and screenshots/README.md '
    '(${ordered.length} screens).',
  );
}

const String _readme = r'''
# Screens, large and small

Every screen this app can reach, rendered at a desktop browser window and at a
phone. Open [`index.html`](index.html) in a browser to see the two side by side.

**This directory is generated. Do not edit it - including this file.** Its source
is `tool/screenshots/`.

| Directory | Viewport | What it is |
| --- | --- | --- |
| `web/` | 1440 x 900 logical, 1x | A desktop browser window. `design.md` §4.1's `expanded` band, wider than every content maximum §4.2 states. **Every screen.** |
| `desktop-narrow/` | 1024 x 768 logical, 1x | The **floor** of `expanded`, and under §4.2's 1200 records maximum - so a table fills the window instead of being capped. Written by the width matrices only. |
| `tablet/` | 834 x 1000 logical, 1x | A tablet, or a half-screen desktop window. §4.1's `medium` band. Written by the width matrices only. |
| `compact-wide/` | 767 x 1000 logical, 1x | The **widest** window that is still `compact`, and over §4.2's 720 reading maximum - a phone layout with a capped, centred column. Written by the content-width matrix only. |
| `mobile/` | 411 x 891 logical, 2x | A phone. §4.1's `compact` band, narrower than every maximum, so those surfaces draw cards edge to edge. **Every screen.** |
| `<viewport>-full/` | Same width, full content height | Only for screens taller than their window. The viewport files above are what a person sees **on arrival**; these are the whole screen. |

**Three of the five are photographed for a handful of components and not for
every screen**, and that is a decision rather than an omission. §4.1 has declared
three bands since it was written, but until `design.md` §4.3 landed in step 6
there was nothing a screen *became* at `medium` that it did not also become at
`compact` - the difference was a content maximum firing or not firing, and both
of those show at 1440 and 411. `RecordList` is the first component with a
rendering of its own in the middle band, so its matrix is captured at every width
and a screen indifferent to width stays at two. Rendering the whole app five
times would add hundreds of images to a diff in which almost all of them would be
indistinguishable from the phone.

**Five regions rather than three, and that is the part worth reading twice.**
§4.1's two band floors (768, 1024) and §4.2's two page maxima (720 reading, 1200
records) are four boundaries on **one** axis, and they interleave. So a width can
cross a maximum without changing band, and change band without crossing a
maximum. `desktop-narrow` and `compact-wide` are the two regions that produces
and that nothing used to photograph: a table laid out with no cap above it, and a
phone layout with a cap already firing. `test/ui/tokens_test.dart` scans
`harness.dart` and fails if any of the five is left without a viewport.

Both boundaries are declared once, as `AppLayout` in
[`lib/ui/tokens.dart`](../lib/ui/tokens.dart), and the two widths were chosen to
straddle them: 411 is also the figure `tenant_routing_shell.dart` measured its
landing route against. They used to be two constants in `lib/ui/records.dart`
and a third written inline; `design.md` §11 step 6 folded all three into one
name at the same numbers.

**1440 is above §4.2's widest content maximum (1200) and 411 is below its
narrowest (720)**, which is why a `web/` image shows a centred column with ground
either side and a `mobile/` image of the same screen shows content edge to edge.
The other three sit between those two facts, one region each.

## Regenerating

```
flutter test tool/screenshots
dart run tool/screenshots/build_index.dart
```

Under a minute for all of it, and it commits to nothing: no Firebase, no
emulators, no device. The screens are pumped as widget tests with real fonts and
a repaint boundary at the root - see
[`tool/screenshots/harness.dart`](../tool/screenshots/harness.dart) for why each
piece is arranged the way it is.

Those files live outside `test/` deliberately. `flutter test` walks that
directory and they assert nothing, so counting them in the suite baseline would
make the figure in `PLAN.md` mean two different things.

## What the pictures are of

The screens are the real route classes the composition root pushes, given the
same readers and callables `lib/main.dart` gives them, so which controls appear
is the screen's own decision about the session's role rather than something this
harness posed.

The business is the local seed script's - `Dev Corner Shop`, trading in KES,
with the catalog from
[`rules-tests/scripts/seed-dev-emulator.js`](../rules-tests/scripts/seed-dev-emulator.js) -
so a picture here and a person driving the emulators see the same shop. The
document shapes behind it are copied from the widget test that already pins each
read model, which is what keeps a screen from rendering its "could not be read"
state because of a wrong field name.

Dates come from the wall clock, because the daily summary and reconciliation
compute a business date from `DateTime.now()` and read by exact path. Re-running
on another day produces the same screens carrying that day's dates.

## Two things these are not

**They are not a device.** A widget test rasterizes the same widget tree a device
does, but it is not proof that the app starts, that Firebase answers, or that a
platform channel works - the sign-in defect this repository found on 2026-08-08
was invisible to every widget test for exactly that reason. Treat these as
pictures of layout and copy, not as evidence a route works end to end.

**Two glyphs render as tofu**, on the sign-in screen's keypad and its submit
button. They fall outside Roboto and the Material icon font, which are the only
two faces loaded here; on a device the platform's fallback draws them. That is a
limit of the harness, not of the app.

## Not pictured

- **Printing a receipt** - no printed body exists yet, so there is no screen.
- **Recovering a forgotten password** - the callable has no client surface.
- **Seeing a subscription** - the path and rules exist and nothing reads them.
- **Flagging a suspicious return** - scoped, not started.
- `lib/pos/**` and `lib/screens/**` - the previous single-tenant app. They are
  reachable from nothing that runs, and are read for their flow rather than kept.
''';

String if_(bool condition, String value) => condition ? value : '';

/// `14-new-sale` becomes `14 · New sale`.
String _title(String name) {
  final split = name.indexOf('-');
  final number = name.substring(0, split);
  final words = name.substring(split + 1).replaceAll('-', ' ');
  return '$number · ${words[0].toUpperCase()}${words.substring(1)}';
}

const String _style = '''
<style>
  :root {
    --ground: #0D1F16;
    --raised: #132A1F;
    --line: #1E3A2B;
    --ink: #FFFFFF;
    --body: #B8D6C5;
    --accent: #45F28D;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 32px clamp(16px, 4vw, 56px) 96px;
    background: var(--ground);
    color: var(--body);
    font: 16px/1.55 system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
  }
  header { max-width: 68ch; margin-bottom: 48px; }
  h1 { color: var(--ink); font-size: clamp(28px, 4vw, 40px); margin: 0 0 12px; }
  h2 {
    color: var(--ink);
    font-size: 20px;
    margin: 0 0 6px;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--line);
  }
  section { margin-bottom: 64px; }
  .caption { max-width: 78ch; margin: 10px 0 20px; }
  .pair {
    display: flex;
    flex-wrap: wrap;
    gap: 24px;
    align-items: flex-start;
  }
  figure { margin: 0; }
  figure.web { flex: 1 1 640px; min-width: 320px; }
  figure.desktop-narrow { flex: 0 0 460px; }
  figure.tablet { flex: 0 0 380px; }
  figure.compact-wide { flex: 0 0 340px; }
  figure.mobile { flex: 0 0 260px; }
  img {
    display: block;
    width: 100%;
    height: auto;
    border: 1px solid var(--line);
    border-radius: 12px;
    background: var(--raised);
  }
  figcaption {
    margin-top: 8px;
    font-size: 13px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
  }
  a { color: var(--accent); }
  figcaption a { text-transform: none; letter-spacing: 0; margin-left: 10px; }
</style>
''';
