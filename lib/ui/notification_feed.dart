/// The notification feed: individual things that happened, each with whatever
/// can be done about it.
///
/// **A list of facts, not a card of counts.** What stood here counted work -
/// *Unprinted receipts 3*, *Sending to the server 2* - which told a shopkeeper
/// how much was wrong and nothing about what. A count cannot be acted on, so
/// every one of them ended at a panel somewhere else; this list carries the
/// action on the row that states the problem.
///
/// **Built rather than borrowed, at the developer's direction on 2026-09-15.**
/// `RecordList` is the right component for records - a sale, a member, a
/// product - which are rows of the same shape differing only in their values. A
/// notification is not that: it has a severity that has to read at a glance, a
/// body that is usually not worth showing, and nought to several things a
/// person might do about it. Forcing it into the records table would have made
/// every notification look like a database row.
///
/// **Status is never the colour alone.** Each severity wears its own glyph out
/// of [AppStatus.defaultIcon] and names itself in the row's semantics, so the
/// list reads the same to somebody who cannot tell the tints apart.
library;

import 'package:flutter/material.dart';

import 'buttons.dart';
import 'press.dart';
import 'spring.dart';
import 'states.dart';
import 'tokens.dart';
import 'status.dart';

/// One thing a person can do about one notification.
@immutable
final class AppNotificationAction {
  const AppNotificationAction({
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.actionKey,
  });

  /// Sentence case, a verb phrase naming the effect. §8.
  final String label;

  /// Null disables it, exactly as on [AppButton] - which is how an action that
  /// is momentarily impossible stays visible instead of vanishing and moving
  /// everything under it.
  final VoidCallback? onPressed;

  /// **Removes or reverses something**, and takes the destructive tier rather
  /// than looking like its neighbour.
  final bool destructive;

  final Key? actionKey;
}

/// One notification.
@immutable
final class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.status,
    required this.title,
    this.summary,
    this.detail,
    this.sourceLabel,
    this.timeLabel,
    this.actions = const <AppNotificationAction>[],
    this.onDismiss,
    this.busy = false,
  });

  /// What makes this notification itself - a job id, a checkout id, a shift id.
  /// Never displayed; it keeps a row's expansion on the row rather than on its
  /// position when the list is rebuilt underneath.
  final String id;

  /// How bad it is. Carried by glyph and by words, never by tint alone.
  final AppStatus status;

  /// The one line that says what happened.
  final String title;

  /// A second line under the title, for the thing the title refers to - a
  /// receipt number, a product name. Optional because plenty of notifications
  /// are one sentence and nothing more.
  final String? summary;

  /// The part worth reading only if you are going to act, revealed on expansion.
  ///
  /// **A row with none cannot be expanded**, and correctly draws no chevron:
  /// an affordance that opens onto nothing is worse than no affordance.
  final String? detail;

  /// Where it came from - a till, a printer, a business. Drawn as a quiet chip.
  final String? sourceLabel;

  /// When, already in words. **The feed does not format time**: relative
  /// wording is a product decision that differs per surface, and a component
  /// that guessed would have to be overridden everywhere it guessed wrong.
  final String? timeLabel;

  final List<AppNotificationAction> actions;

  /// Removes this notification from the list. Null where it may not be
  /// dismissed - which is most of them: a receipt that has not printed is not
  /// something a person may simply decide is no longer true.
  final VoidCallback? onDismiss;

  /// Whether one of this row's actions is running.
  ///
  /// The row keeps its shape and its words and disables what could be pressed
  /// twice, rather than swapping itself for a spinner and taking the sentence
  /// away from whoever was reading it.
  final bool busy;

  bool get isExpandable => (detail ?? '').isNotEmpty;
}

/// The feed itself.
final class AppNotificationFeed extends StatelessWidget {
  const AppNotificationFeed({
    super.key,
    required this.items,
    this.empty,
    this.footer,
  });

  final List<AppNotificationItem> items;

  /// What stands in for the rows when there are none. A slot rather than an
  /// [EmptyState], so this component owns where the words go and the caller
  /// owns the words.
  final Widget? empty;

  /// The bar under the list - *mark all read*, *go somewhere*. Optional,
  /// because a feed with nothing to act on in bulk should not grow a bar.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    if (items.isEmpty) {
      return empty ?? const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        border: Border.all(color: tokens.colors.surface.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (index, item) in items.indexed) ...<Widget>[
            if (index > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: tokens.colors.surface.borderSubtle,
              ),
            AppNotificationTile(
              key: ValueKey('notification-${item.id}'),
              item: item,
            ),
          ],
          if (footer case final bar?) ...<Widget>[
            Divider(
              height: 1,
              thickness: 1,
              color: tokens.colors.surface.borderSubtle,
            ),
            Padding(padding: EdgeInsets.all(tokens.spacing.s16), child: bar),
          ],
        ],
      ),
    );
  }
}

/// One row of [AppNotificationFeed].
final class AppNotificationTile extends StatefulWidget {
  const AppNotificationTile({super.key, required this.item});

  final AppNotificationItem item;

  @override
  State<AppNotificationTile> createState() => _AppNotificationTileState();
}

class _AppNotificationTileState extends State<AppNotificationTile>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  SpringDrive? _drive;
  AppTokens? _tokens;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tokens = AppTokens.componentOf(context);
  }

  @override
  void dispose() {
    _drive?.dispose();
    super.dispose();
  }

  /// **Driven from where it is, never from zero.** A row toggled twice quickly
  /// carries its current position and velocity into the next throw, which is
  /// the rule every spatial move in this app keeps.
  SpringDrive get _expansion =>
      _drive ??= SpringDrive(vsync: this, spring: _tokens!.motion.smooth);

  void _toggle() {
    if (!widget.item.isExpandable) return;
    setState(() => _expanded = !_expanded);
    _expansion.animateTo(_expanded ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final item = widget.item;
    final role = item.status.role(tokens);
    final expandable = item.isExpandable;
    return Semantics(
      container: true,
      label: '${_statusWord(item.status)}. ${item.title}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PressSurface(
            borderRadius: BorderRadius.circular(tokens.radius.md),
            onPressed: expandable ? _toggle : null,
            child: Padding(
              padding: EdgeInsets.all(tokens.spacing.s16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _StatusMark(status: item.status),
                  SizedBox(width: tokens.spacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          item.title,
                          key: ValueKey('notification-title-${item.id}'),
                          style: tokens.typography.bodyLarge.copyWith(
                            color: tokens.colors.text.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (item.summary case final line?) ...<Widget>[
                          SizedBox(height: tokens.spacing.s4),
                          Text(
                            line,
                            style: tokens.typography.bodyMedium.copyWith(
                              color: tokens.colors.text.secondary,
                            ),
                          ),
                        ],
                        if (item.sourceLabel != null || item.timeLabel != null)
                          Padding(
                            padding: EdgeInsets.only(top: tokens.spacing.s8),
                            child: _Meta(
                              source: item.sourceLabel,
                              time: item.timeLabel,
                              role: role,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (expandable)
                    _Chevron(
                      expanded: _expanded,
                      itemId: item.id,
                      onPressed: _toggle,
                    ),
                  if (item.onDismiss case final dismiss?)
                    _IconAction(
                      icon: Icons.close,
                      semanticLabel: 'Dismiss',
                      actionKey: ValueKey('notification-dismiss-${item.id}'),
                      onPressed: item.busy ? null : dismiss,
                    ),
                ],
              ),
            ),
          ),
          // The body and the actions ride one spring together, so a row never
          // shows its buttons before the text they belong to.
          if (expandable)
            AnimatedBuilder(
              animation: _expansion.animation,
              builder: (context, child) {
                final revealed = _expansion.value.clamp(0.0, 1.0);
                // **Gone rather than merely invisible once it is closed.** A
                // body clipped to no height is still in the tree, so a screen
                // reader still reads it and a tap still finds its buttons -
                // which makes the chevron a lie to everyone not looking at the
                // pixels. It stays built while the spring is still moving, so
                // the close animates rather than snapping.
                if (revealed <= 0 && !_expanded) return const SizedBox.shrink();
                return ClipRect(
                  child: Align(
                    alignment: Alignment.topLeft,
                    heightFactor: revealed,
                    child: Opacity(opacity: revealed, child: child),
                  ),
                );
              },
              child: _Body(item: item),
            )
          else if (item.actions.isNotEmpty)
            _Actions(item: item),
        ],
      ),
    );
  }
}

/// The severity, as a glyph in its own tinted disc.
final class _StatusMark extends StatelessWidget {
  const _StatusMark({required this.status});

  final AppStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = status.role(tokens);
    final extent = tokens.spacing.s32;
    return SizedBox(
      width: extent,
      height: extent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: role.bg,
          shape: BoxShape.circle,
          border: Border.all(color: role.border),
        ),
        // Excluded from semantics: the row already says the severity in words,
        // and a second reading of it is noise rather than help.
        child: ExcludeSemantics(
          child: Icon(
            status.defaultIcon,
            size: tokens.spacing.s16,
            color: role.fg,
          ),
        ),
      ),
    );
  }
}

/// Where it came from and when, on one quiet line.
final class _Meta extends StatelessWidget {
  const _Meta({required this.source, required this.time, required this.role});

  final String? source;
  final String? time;
  final AppStatusRole role;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Wrap(
      spacing: tokens.spacing.s8,
      runSpacing: tokens.spacing.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (source case final label?)
          DecoratedBox(
            decoration: BoxDecoration(
              color: role.bg,
              borderRadius: BorderRadius.circular(tokens.radius.sm),
              border: Border.all(color: role.border),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.spacing.s8,
                vertical: tokens.spacing.s4,
              ),
              child: Text(
                label,
                style: tokens.typography.labelMedium.copyWith(color: role.fg),
              ),
            ),
          ),
        if (time case final stamp?)
          Text(
            stamp,
            style: tokens.typography.labelMedium.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
      ],
    );
  }
}

/// The detail and the actions, revealed together.
final class _Body extends StatelessWidget {
  const _Body({required this.item});

  final AppNotificationItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        // Indented to the title rather than the disc, so the body reads as
        // belonging to the sentence above it.
        tokens.spacing.s16 + tokens.spacing.s32 + tokens.spacing.s12,
        0,
        tokens.spacing.s16,
        tokens.spacing.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (item.detail case final body?)
            Text(
              body,
              key: ValueKey('notification-detail-${item.id}'),
              style: tokens.typography.bodyMedium.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
          if (item.actions.isNotEmpty) ...<Widget>[
            SizedBox(height: tokens.spacing.s12),
            _Actions(item: item, padded: false),
          ],
        ],
      ),
    );
  }
}

/// What can be done, as buttons that keep the 48dp target.
final class _Actions extends StatelessWidget {
  const _Actions({required this.item, this.padded = true});

  final AppNotificationItem item;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final row = Wrap(
      spacing: tokens.spacing.s8,
      runSpacing: tokens.spacing.s8,
      children: <Widget>[
        for (final action in item.actions)
          AppButton(
            key: action.actionKey,
            label: action.label,
            tier: action.destructive
                ? AppButtonTier.destructive
                : AppButtonTier.secondary,
            // **Disabled while a sibling runs**, so a second press cannot
            // start a second attempt at the same thing.
            onPressed: item.busy ? null : action.onPressed,
          ),
      ],
    );
    if (!padded) return row;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.s16 + tokens.spacing.s32 + tokens.spacing.s12,
        0,
        tokens.spacing.s16,
        tokens.spacing.s16,
      ),
      child: row,
    );
  }
}

/// The expand affordance, which rotates rather than swapping glyph.
final class _Chevron extends StatelessWidget {
  const _Chevron({
    required this.expanded,
    required this.itemId,
    required this.onPressed,
  });

  final bool expanded;
  final String itemId;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return _IconAction(
      icon: expanded ? Icons.expand_less : Icons.expand_more,
      semanticLabel: expanded ? 'Hide detail' : 'Show detail',
      actionKey: ValueKey('notification-expand-$itemId'),
      onPressed: onPressed,
      tokens: tokens,
    );
  }
}

/// A glyph-only control that still answers for its own tap target.
final class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.semanticLabel,
    required this.actionKey,
    required this.onPressed,
    this.tokens,
  });

  final IconData icon;
  final String semanticLabel;
  final Key actionKey;
  final VoidCallback? onPressed;
  final AppTokens? tokens;

  @override
  Widget build(BuildContext context) {
    final theme = tokens ?? AppTokens.componentOf(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      child: PressSurface(
        key: actionKey,
        borderRadius: BorderRadius.circular(theme.radius.md),
        onPressed: onPressed,
        child: SizedBox(
          // The density's own minimum, kept here rather than left to the
          // glyph's size - a 20pt icon is a 20pt target without it.
          width: theme.density.minimumTapTarget.width,
          height: theme.density.minimumTapTarget.height,
          child: ExcludeSemantics(
            child: Icon(
              icon,
              size: theme.spacing.s20,
              color: onPressed == null
                  ? theme.colors.text.tertiary
                  : theme.colors.text.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

String _statusWord(AppStatus status) => switch (status) {
  AppStatus.ok => 'Done',
  AppStatus.attention => 'Waiting',
  AppStatus.problem => 'Problem',
  AppStatus.info => 'Information',
  AppStatus.neutral => 'Closed',
};
