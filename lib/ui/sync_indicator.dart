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
  const SyncQueueEntry({
    required this.label,
    required this.count,
    this.status,
  });

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
    this.icon = Icons.upload_outlined,
  });

  /// How many checkouts are still on this device.
  ///
  /// **Zero draws no badge**, which is the rule this component exists to keep.
  final int waiting;

  final VoidCallback onOpen;

  /// Whether anything in the queue needs a person. Turns the badge
  /// `status.problem`.
  final bool needsAttention;

  final IconData icon;

  /// §9's touch target, which is also `AppButton`'s `lg`.
  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = (needsAttention ? AppStatus.problem : AppStatus.info)
        .role(tokens);
    final radius = BorderRadius.circular(tokens.radius.md);
    return Semantics(
      button: true,
      label: waiting == 0
          ? 'Checkouts on this device: none waiting'
          : 'Checkouts on this device: $waiting waiting',
      excludeSemantics: true,
      child: PressSurface(
        borderRadius: radius,
        onPressed: onOpen,
        excludeSemantics: true,
        hoverOverlay: tokens.colors.action.secondary.hoverFill(),
        pressedOverlay: tokens.colors.action.secondary.pressedFill(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: waiting == 0 ? null : role.bg,
            border: Border.all(
              color: waiting == 0
                  ? tokens.colors.surface.borderStrong
                  : role.border,
            ),
            borderRadius: radius,
          ),
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: <Widget>[
                Icon(
                  icon,
                  size: Callout.glyphSize,
                  color: waiting == 0 ? tokens.colors.text.secondary : role.fg,
                ),
                if (waiting > 0)
                  Positioned(
                    top: -tokens.spacing.s8,
                    right: -tokens.spacing.s8,
                    child: _Badge(count: waiting, role: role),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.role});

  final int count;
  final AppStatusRole role;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: role.fg,
        borderRadius: BorderRadius.circular(tokens.radius.pill),
        border: Border.all(color: tokens.colors.surface.base, width: 2),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s4),
        child: Text(
          '$count',
          // §2.2's `numeric.body`, tabular, so a two-digit badge does not jitter
          // as the queue drains.
          style: tokens.typography.numericBody.copyWith(
            color: tokens.colors.surface.base,
          ),
        ),
      ),
    );
  }
}

/// What the button opens: every count, with the one that is not zero drawn as a
/// status and the rest as plain rows.
final class SyncQueuePanel extends StatelessWidget {
  const SyncQueuePanel({
    super.key,
    required this.title,
    required this.entries,
    required this.onClose,
    this.emptyMessage,
    this.explanation,
    this.icon = Icons.upload_outlined,
  });

  final String title;
  final List<SyncQueueEntry> entries;
  final VoidCallback onClose;

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
            Row(
              children: <Widget>[
                // The same glyph as the button that opened it, which is what
                // makes the panel read as that button's rather than as a page.
                Icon(
                  icon,
                  size: Callout.glyphSize,
                  color: tokens.colors.status.info.fg,
                ),
                SizedBox(width: tokens.spacing.s12),
                Expanded(
                  child: Text(
                    title,
                    style: tokens.typography.titleMedium.copyWith(
                      color: tokens.colors.text.primary,
                    ),
                  ),
                ),
                _CloseControl(onClose: onClose),
              ],
            ),
            SizedBox(height: tokens.spacing.s12),
            if (emptyMessage case final sentence?)
              Text(
                sentence,
                style: tokens.density
                    .body(tokens.typography)
                    .copyWith(color: tokens.colors.text.secondary),
              )
            else
              for (final entry in entries) ...<Widget>[
              _Row(entry: entry),
              SizedBox(height: tokens.spacing.s8),
            ],
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

/// One count. A status row where it has one, a plain row where it does not.
final class _Row extends StatelessWidget {
  const _Row({required this.entry});

  final SyncQueueEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final standing = entry.status;
    final role = standing?.role(tokens);
    final label = Text(
      entry.label,
      style: (standing == null
              ? tokens.density.body(tokens.typography)
              : tokens.typography.labelLarge)
          .copyWith(
            color: role?.fg ?? tokens.colors.text.secondary,
          ),
    );
    final count = Text(
      '${entry.count}',
      style: tokens.typography.numericBody.copyWith(
        color: role?.fg ?? tokens.colors.text.primary,
      ),
    );
    final row = Row(
      children: <Widget>[
        if (standing != null) ...<Widget>[
          Icon(standing.defaultIcon, size: StatusBadge.iconSize, color: role!.fg),
          SizedBox(width: tokens.spacing.s8),
        ],
        Expanded(child: label),
        SizedBox(width: tokens.spacing.s12),
        count,
      ],
    );
    if (standing == null) return row;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: role!.bg,
        border: Border.all(color: role.border),
        borderRadius: BorderRadius.circular(tokens.radius.sm),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.s12,
          vertical: tokens.spacing.s8,
        ),
        child: row,
      ),
    );
  }
}
