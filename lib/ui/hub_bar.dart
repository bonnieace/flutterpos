/// `HubTopBar`: the home's top bar on a tablet or a desktop - the old hub's,
/// restored on 2026-10-10 at the developer's direction.
///
/// **Measured off the old hub's own screen, figure for figure where the scale
/// has the figure.** A 70-high strip in the card surface with a hairline under
/// it; the hub mark, then - where the old bar said *Main Hub* - the business's
/// name, which is still the control that opens *My businesses*; a pill saying
/// whether this device is online and which terminal it is; and at the far end
/// the signed-in person's pill, then the bar's own controls in white.
///
/// **The pill names a real terminal.** The old one printed `Terminal #8842-A`
/// on every device, whatever it was. This one prints the code this device's
/// receipts carry - `CT-7F2` - which is the same three characters on every
/// receipt it has issued and will issue. Its online half is the platform's
/// connectivity reading, the one the sale queue already wakes on: it says the
/// device has a network, not that the server answered, which is what the old
/// pill's word meant too.
///
/// **A phone keeps the toolbar.** The developer's rule for the old hub's look
/// is wider screens only, and a 360 handset has no room for two pills.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'buttons.dart';
import 'press.dart';
import 'tokens.dart';

/// The old hub's bar. See the library note.
final class HubTopBar extends StatelessWidget implements PreferredSizeWidget {
  const HubTopBar({
    super.key,
    required this.title,
    this.onTitlePressed,
    this.titleActionLabel,
    this.terminalLabel,
    this.onlineCheck,
    this.onlineChanges,
    this.memberName,
    this.memberRole,
    this.actions = const <Widget>[],
    this.compact = false,
  }) : assert(
         onTitlePressed == null || titleActionLabel != null,
         'A title that is a control has to say what it opens.',
       );

  /// The business's name, where the old bar printed *Main Hub*.
  final String title;

  /// What pressing the name does - *My businesses*, or the switcher.
  final VoidCallback? onTitlePressed;

  /// What [onTitlePressed] opens, for a screen reader.
  final String? titleActionLabel;

  /// This device's receipt code, `CT-7F2`. Null draws no status pill.
  final String? terminalLabel;

  /// Asked once, for the pill's first reading.
  final Future<bool> Function()? onlineCheck;

  /// Every later reading.
  final Stream<bool>? onlineChanges;

  /// The signed-in person's name as the business holds it.
  final String? memberName;

  /// Their role, as it reads beside a name - *Owner*, *Cashier*.
  final String? memberRole;

  /// The bar's own controls, in order, at the trailing edge.
  final List<Widget> actions;

  /// The old hub's phone row rather than its desktop one: a smaller mark and
  /// name, the person as a circle alone, and no status pill - which is what
  /// the old bar dropped below 768. The caller decides, because the band is
  /// the page's to know.
  final bool compact;

  @override
  Size get preferredSize => Size.fromHeight(
    compact
        ? AppLayout.contract.hubBarHeightCompact
        : AppLayout.contract.hubBarHeight,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final icons = tokens.icons;
    final role = memberRole;
    return Material(
      color: colors.surface.raised,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: preferredSize.height,
          // The old bar's own insets: 12 a side on a phone, 20 wider.
          padding: EdgeInsets.symmetric(
            horizontal: compact ? tokens.spacing.s12 : tokens.spacing.s20,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.surface.borderSubtle),
            ),
          ),
          child: Row(
            children: <Widget>[
              ExcludeSemantics(
                child: Icon(
                  Symbols.hub_rounded,
                  // The old phone mark was 20, between `row` and `card`.
                  size: compact ? icons.row : icons.card,
                  color: colors.text.primary,
                  fill: icons.primaryFill,
                  weight: icons.weight,
                  grade: icons.grade,
                  opticalSize: icons.opticalSizeFor(
                    compact ? icons.row : icons.card,
                  ),
                ),
              ),
              // The old 10, between `space.8` and `space.12`.
              SizedBox(width: tokens.spacing.s8),
              // **The name and the pill take the slack between them**, so a
              // long name gives way before the controls do - and the
              // controls sit hard against the trailing inset. A `Flexible`
              // name beside a `Spacer` split the slack in two and left half
              // of it, unused, past the last control.
              Expanded(
                child: Row(
                  children: <Widget>[
                    Flexible(
                      child: _HubTitle(
                        title: title,
                        onPressed: onTitlePressed,
                        actionLabel: titleActionLabel,
                        compact: compact,
                      ),
                    ),
                    // The old phone bar had no room for the pill and drew none.
                    if (terminalLabel case final terminal?
                        when !compact) ...<Widget>[
                      SizedBox(width: tokens.spacing.s12),
                      HubStatusPill(
                        terminalLabel: terminal,
                        onlineCheck: onlineCheck,
                        onlineChanges: onlineChanges,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: compact ? tokens.spacing.s8 : tokens.spacing.s12),
              if (memberName != null || role != null) ...<Widget>[
                // On a phone the old bar drew the circle alone.
                if (compact)
                  _HubAvatar(name: memberName, role: role)
                else
                  _HubUserPill(name: memberName, role: role),
                SizedBox(
                  width: compact ? tokens.spacing.s8 : tokens.spacing.s12,
                ),
              ],
              ...actions,
            ],
          ),
        ),
      ),
    );
  }

  /// A name as the old pill printed it: the first name and the last name's
  /// initial - *Boniface M.* - in the person's own capitals.
  static String shortName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.last.isEmpty) return parts.first;
    return '${parts.first} ${parts.last.characters.first}.';
  }
}

/// The business's name, and the way to a different one.
///
/// The same control the toolbar's title is - the same key, the same words to a
/// screen reader, the same chevron - in the old bar's 18 / 600 and its sage.
final class _HubTitle extends StatelessWidget {
  const _HubTitle({
    required this.title,
    required this.onPressed,
    required this.actionLabel,
    required this.compact,
  });

  final String title;
  final VoidCallback? onPressed;
  final String? actionLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final text = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // The old desktop bar's 18 / 600; its phone bar's 16 / 600, which is
      // `body.lg`'s size at the name's weight.
      style:
          (compact
                  ? tokens.typography.bodyLarge.copyWith(
                      fontWeight: tokens.typography.moduleTitle.fontWeight,
                    )
                  : tokens.typography.moduleTitle)
              .copyWith(color: tokens.colors.text.secondary),
    );
    final press = onPressed;
    if (press == null) return Semantics(header: true, child: text);
    return Semantics(
      header: true,
      button: true,
      label: '$title. $actionLabel.',
      excludeSemantics: true,
      child: PressSurface(
        key: const ValueKey('screen-title-action'),
        borderRadius: BorderRadius.circular(tokens.radius.md),
        onPressed: press,
        excludeSemantics: true,
        // The ring is drawn outside the name, into the gaps either side, so
        // the name starts where the old bar's did rather than 4 further in.
        reservesRingGutter: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(child: text),
            SizedBox(width: tokens.spacing.s4),
            Icon(
              Icons.expand_more,
              size: AppButton.iconSize,
              color: tokens.colors.text.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// *Online · Terminal CT-7F2*, kept current.
///
/// **Never colour alone**: the dot is green online and amber offline, and the
/// word says which. Until the first reading arrives it names the terminal and
/// says nothing about the network rather than guessing.
final class HubStatusPill extends StatefulWidget {
  const HubStatusPill({
    super.key,
    required this.terminalLabel,
    this.onlineCheck,
    this.onlineChanges,
  });

  final String terminalLabel;
  final Future<bool> Function()? onlineCheck;
  final Stream<bool>? onlineChanges;

  @override
  State<HubStatusPill> createState() => _HubStatusPillState();
}

final class _HubStatusPillState extends State<HubStatusPill> {
  bool? _online;
  StreamSubscription<bool>? _changes;

  @override
  void initState() {
    super.initState();
    _check();
    _listen();
  }

  @override
  void didUpdateWidget(HubStatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.onlineChanges, widget.onlineChanges)) {
      unawaited(_changes?.cancel());
      _listen();
    }
    if (!identical(oldWidget.onlineCheck, widget.onlineCheck)) _check();
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  void _check() {
    final check = widget.onlineCheck;
    if (check == null) return;
    check().then(
      (online) {
        if (mounted) setState(() => _online = online);
      },
      // A reading that fails says nothing; the pill keeps what it had.
      onError: (Object _) {},
    );
  }

  void _listen() {
    _changes = widget.onlineChanges?.listen((online) {
      if (mounted) setState(() => _online = online);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final state = switch (_online) {
      true => 'Online · ',
      false => 'Offline · ',
      null => '',
    };
    final sentence = '${state}Terminal ${widget.terminalLabel}';
    return Semantics(
      label: sentence,
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('hub-status-pill'),
        // The old 10 across, between `space.8` and `space.12`; 4 down.
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.s8,
          vertical: tokens.spacing.s4,
        ),
        decoration: BoxDecoration(
          color: colors.surface.field,
          borderRadius: BorderRadius.circular(tokens.radius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: tokens.spacing.s8,
              height: tokens.spacing.s8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (_online) {
                  true => colors.status.ok.fg,
                  false => colors.status.attention.fg,
                  null => colors.text.tertiary,
                },
              ),
            ),
            // The old 6, between `space.4` and `space.8`.
            SizedBox(width: tokens.spacing.s4),
            Text(
              sentence,
              style: tokens.typography.caption.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The signed-in person: a circle with a figure in it, the name, the role.
final class _HubUserPill extends StatelessWidget {
  const _HubUserPill({required this.name, required this.role});

  final String? name;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final shown = name == null || name!.trim().isEmpty
        ? null
        : HubTopBar.shortName(name!);
    return Semantics(
      label: <String?>[name, role].whereType<String>().join(', '),
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('hub-user-pill'),
        // The old 12 across; its 6 down is between `space.4` and `space.8`.
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.s12,
          vertical: tokens.spacing.s4,
        ),
        decoration: BoxDecoration(
          color: colors.surface.field,
          borderRadius: BorderRadius.circular(tokens.radius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _HubFigure(),
            SizedBox(width: tokens.spacing.s8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (shown != null)
                  Text(
                    shown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.labelMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                if (role case final line?)
                  Text(
                    line.toUpperCase(),
                    style: tokens.typography.hubRole.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The signed-in person on a phone: the old bar's circle alone, saying to a
/// screen reader what the pill says in print wider than a phone.
final class _HubAvatar extends StatelessWidget {
  const _HubAvatar({required this.name, required this.role});

  final String? name;
  final String? role;

  @override
  Widget build(BuildContext context) => Semantics(
    label: <String?>[name, role].whereType<String>().join(', '),
    excludeSemantics: true,
    child: const _HubFigure(key: ValueKey('hub-user-avatar')),
  );
}

/// A circle with a figure in it, in the old hub's place for the person.
final class _HubFigure extends StatelessWidget {
  const _HubFigure({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final icons = tokens.icons;
    return Container(
      width: icons.hubAvatar,
      height: icons.hubAvatar,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // The old circle was Material's own pale violet; this is the nearest
        // role the palette has, with dark ink on it as the old one had.
        color: tokens.colors.accent.privileged,
      ),
      child: Icon(
        Symbols.person_rounded,
        size: icons.row,
        color: tokens.colors.surface.base,
        fill: icons.primaryFill,
        weight: icons.weight,
        grade: icons.grade,
        opticalSize: icons.opticalSizeFor(icons.row),
      ),
    );
  }
}
