/// `SyncIndicator`: `design.md` §5.1's row for "five-line offline queue list",
/// §5.2 as added in v0.7 from the product owner's drawing, and §7's
/// *Offline / read-only* pattern — *"the checkout queue counts belong in a
/// `StatRow`, not a five-line list."*
///
/// **Two parts: a badged button in the top bar, and the panel it opens.** The
/// button is the whole signal at rest; the panel is where the counts go so they
/// stop being five lines of prose on the home screen.
///
/// **The badge counts what is still waiting, never what is done.** Eleven
/// confirmed checkouts are not news; two saved offline are. And there is **no
/// badge at all when the device is clear** — a zero is not a state worth
/// drawing, and a permanent "0" trains a person to stop looking at the one
/// place that tells them something is stuck.
///
/// **Colour is not alone.** The badge is `status.info` normally and
/// `status.problem` the moment anything needs attention, which is §9's floor
/// rather than its ceiling: the panel it opens names the state in words, and
/// the button carries a semantic label saying how many are waiting.
library;

import 'package:flutter/material.dart';

import 'press.dart';
import 'status.dart';
import 'tokens.dart';

/// One row of the queue panel: what a count is, and how many.
@immutable
final class SyncQueueEntry {
  const SyncQueueEntry({required this.label, required this.count, this.status});

  /// What this count is, in the shopkeeper's words. §8 rule 1.
  final String label;

  final int count;

  /// The standing this row carries, where it has one.
  ///
  /// **Optional, and an absent status is not a neutral one** — the same rule
  /// `RecordStatus` and `StatTile` both carry. A panel where every row wears a
  /// container is a panel with no signal in it; exactly one row is the one that
  /// is not zero, and that is the row that gets drawn as a status.
  final AppStatus? status;
}

/// The badged button that lives in the top bar.
final class SyncIndicator extends StatelessWidget {
  const SyncIndicator({
    super.key,
    required this.waiting,
    required this.onOpen,
    this.needsAttention = false,
    this.icon = Icons.notifications_outlined,
    this.subject = 'Checkouts on this device',
  });

  /// How many checkouts are still on this device.
  ///
  /// **Zero draws no badge**, which is the rule this component exists to keep.
  final int waiting;

  final VoidCallback onOpen;

  /// Whether anything in the queue needs a person.
  ///
  /// **It says so in the label rather than in the tint, since 2026-09-04.**
  /// The badge is red at every standing now - a sixteen-pixel disc in a
  /// toolbar cannot carry the difference between *moving* and *stuck*, and
  /// §9 does not allow that difference to be carried by colour anyway. A
  /// person using a screen reader is told it; everyone else is told it by the
  /// page the badge opens.
  final bool needsAttention;

  final IconData icon;
  final String subject;

  /// §9's touch target, which is also `AppButton`'s `lg`.
  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final radius = BorderRadius.circular(tokens.radius.md);
    return Semantics(
      button: true,
      label: switch ((waiting, needsAttention)) {
        (0, _) => '$subject: none waiting',
        (final count, true) => '$subject: $count waiting, some need you',
        (final count, false) => '$subject: $count waiting',
      },
      excludeSemantics: true,
      child: PressSurface(
        borderRadius: radius,
        onPressed: onOpen,
        excludeSemantics: true,
        hoverOverlay: tokens.colors.action.secondary.hoverFill(),
        pressedOverlay: tokens.colors.action.secondary.pressedFill(),
        // **A glyph, not a box, since 2026-08-23.** The export's top-bar
        // status control is `p-2 rounded-full text-on-surface-variant` with a
        // small dot over it - no container and no outline. This drew a
        // bordered 48-square in the toolbar beside a bordered 48-square
        // hamburger, which is two buttons' worth of chrome for one glyph, and
        // the product owner called it big.
        //
        // **The badge stays a count rather than becoming the design's plain
        // dot**, and it moves inside the square: *two waiting* and *nine
        // waiting* are different enough to act on differently, and a dot says
        // neither. It is inside now because there is no border for it to hang
        // off, and a badge overhanging a bare glyph clips against the toolbar.
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: <Widget>[
              // **A plain bell, whatever is waiting.** The badge beside it is
              // the signal, and tinting the glyph as well made a toolbar with
              // one thing in it read as an alert.
              Icon(
                icon,
                size: Callout.glyphSize,
                color: tokens.colors.text.secondary,
              ),
              if (waiting > 0)
                Positioned(
                  top: tokens.spacing.s4,
                  right: 0,
                  child: _Badge(count: waiting),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The count over the bell: a red disc, at any standing.
///
/// **Red rather than the standing's own colour, at the developer's direction
/// on 2026-09-04.** It took `status.info` for work that was merely moving and
/// `status.problem` for work that needed somebody, which is a distinction two
/// tints cannot carry on a sixteen-pixel disc in a toolbar. What the badge is
/// for is *there is something here*, and that is one thing. Which of it needs
/// a person is the page's job to say, and it says it in words.
///
/// **A disc rather than a pill** until the count needs two digits: a minimum
/// square of `space.16` with the figure centred, so one waiting item is round
/// and nine is the same round. Past ninety-nine it says `99+`, because a
/// three-figure badge covers the glyph it is sitting on.
final class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = AppStatus.problem.role(tokens);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: role.fg,
        borderRadius: BorderRadius.circular(tokens.radius.pill),
        // The ring is the toolbar's own ground, so the disc reads as sitting
        // over the glyph rather than merging into it.
        border: Border.all(color: tokens.colors.surface.base, width: 2),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: tokens.spacing.s16,
          minHeight: tokens.spacing.s16,
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s4),
            child: Text(
              count > 99 ? '99+' : '$count',
              // §2.2's `numeric.body`, tabular, so a two-digit badge does not
              // jitter as the queue drains.
              style: tokens.typography.numericBody.copyWith(
                color: tokens.colors.surface.base,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every count, as a grid of figures rather than a list of rows.
///
/// **It was twelve `label ....... 0` rows until 2026-09-04**, which is the
/// shape §5.1 was replacing when it named "five-line offline queue list" - and
/// twelve of them on a page of their own is that shape again, longer. §7 says
/// where the counts go: *"the checkout queue counts belong in a `StatRow`, not
/// a five-line list."* This is that, at the size a count of two belongs at: the
/// figure is the loud part, the label is underneath it, and only the cells that
/// are not zero take a status container.
///
/// **Every state is still named, including the zeroes.** A real run once
/// reported this panel showing "Saved offline: 0" and seemingly nothing else
/// while a record was present; the five - now twelve - are siblings, so any
/// record at all renders all of them and an absent line can never be confused
/// with a zero. A grid makes that affordable in a way a list did not.
final class SyncQueuePanel extends StatelessWidget {
  const SyncQueuePanel({
    super.key,
    this.title,
    required this.entries,
    this.onClose,
    this.emptyMessage,
    this.explanation,
    this.icon = Icons.notifications_outlined,
  });

  /// The card's own heading.
  ///
  /// **Null where the page already said it.** On the notifications route the
  /// section band above this carries the words, and a card repeating them one
  /// line lower is the duplication §7 forbids.
  final String? title;

  final List<SyncQueueEntry> entries;

  /// The width one count cell is laid out at.
  ///
  /// Named for the reason `EmptyState.markSize` is: `design.md` states no cell
  /// width. 104 fits the longest label this panel carries - *Awaiting change
  /// confirmation* - on three lines at `caption`, and gives three columns at
  /// 411 and more above it.
  static const double cellWidth = 104;

  /// Dismisses the panel, where it is something that can be dismissed.
  ///
  /// **Null where the panel *is* the page.** It hung under a button in the top
  /// bar until 2026-09-03 and closing it was the only way back; on the
  /// notifications route the way back is the route's own, and a second `Close`
  /// beside the title would be a control that undoes nothing.
  final VoidCallback? onClose;

  /// Said instead of the counts when every one of them is zero.
  ///
  /// A device holding nothing draws no badge, so this is the only place left to
  /// state it - and five zeroes in a row is a worse way to say "nothing here"
  /// than a sentence is.
  final String? emptyMessage;

  /// §7's *Long copy*: the paragraph about why a person cannot send these
  /// themselves is policy, so it folds rather than sitting open.
  final Widget? explanation;

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        // §2.1: "dialogs, menus, bottom sheets".
        color: tokens.colors.surface.overlay,
        border: Border.all(color: tokens.colors.surface.borderSubtle),
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (title case final heading?) ...<Widget>[
              Row(
                children: <Widget>[
                  // The same glyph as the button that opened it, which is what
                  // makes the panel read as that button's rather than as a
                  // page.
                  Icon(
                    icon,
                    size: Callout.glyphSize,
                    color: tokens.colors.status.info.fg,
                  ),
                  SizedBox(width: tokens.spacing.s12),
                  Expanded(
                    child: Text(
                      heading,
                      style: tokens.typography.titleMedium.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                  ),
                  if (onClose case final close?) _CloseControl(onClose: close),
                ],
              ),
              SizedBox(height: tokens.spacing.s12),
            ],
            if (emptyMessage case final sentence?)
              Text(
                sentence,
                style: tokens.density
                    .body(tokens.typography)
                    .copyWith(color: tokens.colors.text.secondary),
              )
            else
              Wrap(
                spacing: tokens.spacing.s8,
                runSpacing: tokens.spacing.s8,
                children: <Widget>[
                  for (final entry in entries) _Cell(entry: entry),
                ],
              ),
            if (explanation case final prose?) ...<Widget>[
              SizedBox(height: tokens.spacing.s4),
              prose,
            ],
          ],
        ),
      ),
    );
  }
}

final class _CloseControl extends StatelessWidget {
  const _CloseControl({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Semantics(
      button: true,
      label: 'Close',
      excludeSemantics: true,
      child: PressSurface(
        borderRadius: BorderRadius.circular(tokens.radius.sm),
        onPressed: onClose,
        excludeSemantics: true,
        hoverOverlay: tokens.colors.action.tertiary.hoverFill(),
        pressedOverlay: tokens.colors.action.tertiary.pressedFill(),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s8),
          child: Text(
            'Close',
            style: tokens.typography.labelLarge.copyWith(
              color: tokens.colors.action.tertiary.label,
            ),
          ),
        ),
      ),
    );
  }
}

/// One count: the figure, then what it is.
///
/// **A status cell wears a container and a plain one does not**, which is the
/// rule the row it replaced already kept: a panel where every cell is tinted is
/// a panel with no signal in it. Exactly the cells that are not zero are the
/// ones worth looking at, and they are the ones that are painted.
final class _Cell extends StatelessWidget {
  const _Cell({required this.entry});

  final SyncQueueEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final standing = entry.status;
    final role = standing?.role(tokens);
    return SizedBox(
      width: SyncQueuePanel.cellWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: role?.bg ?? tokens.colors.surface.sunken,
          border: Border.all(
            color: role?.border ?? tokens.colors.surface.borderSubtle,
          ),
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.s12,
            vertical: tokens.spacing.s12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Text(
                    '${entry.count}',
                    // §2.2's `numeric.compact`, which is the role a figure
                    // this size takes: tabular, so a column of them lines up.
                    style: tokens.typography.numericCompact.copyWith(
                      color: role?.fg ?? tokens.colors.text.primary,
                    ),
                  ),
                  if (standing != null) ...<Widget>[
                    const Spacer(),
                    // §9: the tint is never the only carrier. The glyph says
                    // the same thing, and the label below says it in words.
                    Icon(
                      standing.defaultIcon,
                      size: StatusBadge.iconSize,
                      color: role!.fg,
                    ),
                  ],
                ],
              ),
              SizedBox(height: tokens.spacing.s4),
              Text(
                entry.label,
                style: tokens.typography.caption.copyWith(
                  color: role?.fg ?? tokens.colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
