# Tabs: a design, 2026-10-04

These are four artboards for `AppTabs` (`lib/ui/tabs.dart`), the tab strip above six screens. Open
[`index.html`](index.html) in a browser. Each page is self-contained HTML with no build step and no
dependency on the repo. The states board runs a little JavaScript, so the motion can be tried as
well as read about.

This is the second pass. The first redrew today's underline strip. This one follows two references
you chose:

- **Two tabs:** the *Live / Demo* control in a crypto wallet app
  (`cdn.dribbble.com/userupload/49092282/…/aa89202ed7c3d32ebe0f814060371892.png`).
- **Three or more:** the *Support / Encourage / Monitor / Intervene* tabs in an action dashboard
  (`cdn.dribbble.com/userupload/15249737/…/original-f8718314c725f37a31766cb97fdfda29.png`).

The images are not copied into the repo. The fixes found in the first pass still stand and are
listed under *Found while drawing*.

## The question the strip answers

**Which of these am I looking at, and what else is here?** With two tabs the honest answer is
"this one or that one", which a switch says directly. With three or more, each tab needs its own
name and a way to tell it apart from the next, which is what glyphs and labels give.

## One component, two shapes

`AppTabs` picks the shape from the number of tabs, so no screen has to choose.

| Screen | File | Tabs | Kind | Shape |
| --- | --- | --- | --- | --- |
| Email receipts | `lib/email_receipts/email_receipts_screen.dart` | 2 | Page | Switch |
| WhatsApp receipts | `lib/whatsapp/e_receipt_settings_panel.dart` | 2 | Page | Switch |
| Platform operations | `lib/tenancy/platform_tenant_lifecycle.dart` | 2 | Page | Switch |
| Printer | `lib/checkout/checkout_print_configuration_panel.dart` | 2 | Section | Switch |
| Customer record | `lib/customers/customer_record_panel.dart` | 2 | Section | Switch |
| Configs | `lib/tenancy/tenant_configuration_screens.dart` | 3 or 4 | Page | Icon tabs |

*Page* tabs sit under the toolbar and switch a `TabBarView`. *Section* tabs sit in the reading
column and switch content with `Visibility`.

## What each reference lends, and what it does not

**The crypto wallet's switch lends its shape:** a capsule track, with a raised capsule thumb inset
about 4 behind the selected half. Both labels read as options, not as one active and one dead. The
thumb is what moves.

**It does not lend its colours or its glass.** In this app depth is a surface step, never a blur or
a glow (`AppSurfaceRoles`), and the only blur token belongs to the sign-in pane. Here the track is
`surface.raised` with a `borderSubtle` hairline. The thumb is `#283831` with a `borderStrong` edge.
The thumb is not the accent green, which stays with the one primary action on a screen, as the
reference keeps its bright blue for *Trade*.

**The action dashboard lends its arrangement:** a glyph and a label per tab, packed from the start
rather than stretched into equal shares. The selected tab takes the accent in glyph, label and
underline. The underline spans glyph and label, and a hairline runs under the strip. Measured at
3x, its glyph is about 15, glyph to label is 9, tab to tab is 23, and the underline is about 2.3.
Those snap to the 18 icon size (`icons.row`), `space.8`, two `space.12`s, and 2.

**It does not lend its blue, its white ground, or its larger label.** The label is `label.md` 14/600,
which `design.md` names as the tab role. Each glyph is the one the tab's own panel already leads
with: `payments`, `assignment`, `handshake` and `loyalty`.

## What changes

| Part | Built | Proposed | Restyle? |
| --- | --- | --- | --- |
| Shape | One underline strip for every count | A switch for two tabs, icon tabs for three or more | Yes, inside `AppTabs` |
| Switch | Underline strip | Track: `surface.raised`, 1px `borderSubtle`, `radius.pill`, 48 high. Thumb: `surface.selected`, 1px `borderStrong`, `radius.pill`, inset 4. Selected label `text.primary`, the other `text.secondary` | Yes. A `BoxDecoration` indicator at `TabBarIndicatorSize.tab` with `indicatorPadding` 4, no divider, in a decorated track |
| Icon tabs | Underline strip, labels only | `space.12`, glyph 18, `space.8`, label, `space.12`. At rest `text.tertiary`; selected glyph, label and 2px underline in `action.primary.container`. 1px `borderSubtle` hairline | Mostly. `AppTabs` has to take a glyph per tab, which changes its API. Only Configs passes glyphs |
| Label type | `label.lg` 14/700 +0.7 | `label.md` 14/600, one weight whether selected or not | Yes |
| New token | n/a | `surface.selected` = `#283831`, Profound Verdant's existing `surfaceContainerHighest`. No new hex | A token change. The hex already exists as `cardEdge` and `status.neutral.bg`, but neither of those roles means "selected" |
| Hover, press | Material's overlay over the whole cell | `text.primary` at 8% / 12%, in the thumb's shape on the switch and inset 4 with `radius.md` on icon tabs. No ripple, no scale | Yes. `TabBar.onHover` and `onFocusChange`, plus a `Listener` for the press, tell `AppTabs` which tab to wash. The InkWell overlay goes transparent |
| Keyboard focus | Material's focus overlay | The app's ring, 2px at a 2px offset, around the same shape | Yes, by the same route |
| Height | 50 | 48: a 46 tab plus `indicatorWeight` 2 | Yes. Content under a strip moves up 2 |
| Switch layout | n/a | Below 768 it fills the content width. From 768 each half is the wider label plus `space.24` a side, at the start of the column. At large text a label wraps to two lines and the track grows. A single word too long for its half falls back to the underline strip without glyphs, which scrolls | Yes. Measured inside `AppTabs` with the text scaler |
| Icon tab layout | Configs measures; scrolls after a 52 gap | Always packed from the start. Scrolls with `TabAlignment.start` when it does not fit, with a 32 mask fade on the end that has more. On a page the strip is padded 8, so the first glyph sits at the page inset of 20 | Yes |
| Motion | Follows `TabController`: a 300ms ease on a tap | Switch: the thumb slides as one piece on `spring.snappy`. Icon tabs: the underline's leading end on `spring.snappy`, its trailing end on `spring.smooth`. Both retarget from where they are. A swipe still drives them directly | Yes, but it is new code. `AppTabs` becomes stateful and paints its own thumb or underline from `SpringDrive`s |

**Unchanged:** every `DefaultTabController` and who owns it, every tap and swipe, `TabBarView`, the
`Visibility` switching under section tabs, which tabs exist and their words, the semantics (role
*tab*, *selected*, *Tab 1 of 2*), Flutter's focus traversal, and the label colours following the
controller. Selection logic does not move.

**API changes, named because they are not visual:** a glyph per tab (Configs supplies four), a way to
say a strip is a page strip (four call sites), and `isScrollable` goes away (six call sites). None of
these changes behaviour.

## Found while drawing (first pass, still true)

1. **The indicator has never been the 2px `tabs.dart` says.** Material 3 draws 3 for a label-width
   indicator, with 3px corners. The harness captures measure 3.
2. **The strip is 50 high, not 48.** `AppTabs.preferredSize` understates it by 2.
3. **At 200% text, the fixed strips cut their labels.** On a 411 phone Email and WhatsApp cut *Sent
   receipts*; on a 320 phone all four fixed strips cut a word. The switch wraps instead.
4. **On a 411 phone, Configs' fourth tab is not on screen at all**, behind Material's 52px start gap.

## Your call

1. **The stretch on the icon tabs' underline.** I recommend it: the leading end lands in about 200ms
   and the move settles by about 530ms. Try it on the states board, with quarter speed on. The
   alternative is a rigid slide on `spring.snappy`, like the switch's thumb, settled in about 380ms.
   Only Configs has icon tabs, so this is a small surface either way.
2. **Hover on the switch.** The unselected half's hover wash is the thumb's shape at 8%. Side by side
   in the states board the two are distinct: the thumb is brighter, has an edge, and carries the
   brighter label. In a frame glanced at, though, a hovered half can look like a second thumb. I kept
   the wash because it is the app's hover everywhere else. The alternative is no wash on the switch,
   with only the label coming up a step. Hover exists only with a mouse, so phones never see it.

## Considered and left out

- **The reference's glass, gradient and glow**, for the depth reason above.
- **Glyphs on the switch.** The reference has none, and two words say enough.
- **A count or a dot on a tab.** It needs a read to feed it, so it is not a restyle, and no screen
  asks for one yet.
- **A disabled tab.** `TabBar` has none, and the app removes a tab it cannot open.
- **A transition for section-tab content.** `Visibility` still swaps the content in one frame. The
  thumb or the underline shows what changed.

## What these files are

They are standalone HTML pages written by hand. Every value is a token the build reads, named beside
it, and every contrast ratio was computed from the token hex values. The body content in the phone
and desktop frames is drawn as built from the harness captures, so the strip is the only thing
redesigned. The sentences are the app's own.

They were rendered in headless Chrome and checked by eye. The live demos simulate `spring.snappy`
and `spring.smooth` with the token values, so they show the motion this design asks for. They do not
prove a Flutter build will match it. Nothing here has run on a device, and the harness cannot show
motion.
