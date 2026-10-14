/// `HubTopBar`: the home's top bar, on every width since 2026-10-13
/// (`docs/design/topbar/`).
///
/// **It answers where am I, and is this device all right - and nothing
/// else.** The business's name, which is also the way to a different one;
/// whether this device is online and which terminal it is, from 768 up in
/// plain words and on a phone only when it is not; the bar's own controls; and
/// the signed-in person, who is also the way to settings and out.
///
/// **It stands on the page, not on a strip.** [TopBarSurface] keeps it on
/// `surface.base` with no edge until the page scrolls under it, which is the
/// same rule every other route's toolbar follows now. The old hub's raised
/// 70-high band with a hairline at all times is gone.
///
/// **The person is one control.** The old bar drew a user pill, a gear and a
/// way out side by side, which was four trailing controls on a 360 handset and
/// a pill floating in the middle of the bar. The pill is now a button that
/// opens the account menu, and the gear and the way out are in it, for exactly
/// the people they were drawn for before.
///
/// **The terminal is a real one.** The code is the one this device's receipts
/// carry - `CT-7F2` - not the old bar's `Terminal #8842-A` on every device. Its
/// online half is the platform's connectivity reading, the one the sale queue
/// already wakes on: it says the device has a network, not that the server
/// answered.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'buttons.dart';
import 'press.dart';
import 'spring.dart';
import 'status.dart';
import 'tokens.dart';
import 'top_bar.dart';

/// The home's bar. See the library note.
final class HubTopBar extends StatefulWidget implements PreferredSizeWidget {
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
    this.onSettings,
    this.onSignOut,
    this.compact = false,
    this.horizontalInset,
  }) : assert(
         onTitlePressed == null || titleActionLabel != null,
         'A title that is a control has to say what it opens.',
       );

  /// The business's name.
  final String title;

  /// What pressing the name does - *My businesses*, or the switcher.
  final VoidCallback? onTitlePressed;

  /// What [onTitlePressed] opens, for a screen reader.
  final String? titleActionLabel;

  /// This device's receipt code, `CT-7F2`. Null says nothing about the device.
  final String? terminalLabel;

  /// Asked once, for the first reading.
  final Future<bool> Function()? onlineCheck;

  /// Every later reading.
  final Stream<bool>? onlineChanges;

  /// The signed-in person's name as the business holds it.
  final String? memberName;

  /// Their role, as it reads beside a name - *Owner*, *Cashier*.
  final String? memberRole;

  /// The bar's own glyph controls, before the person - the send queue.
  final List<Widget> actions;

  /// Opens the settings a member may change. Null draws no *Settings* row,
  /// which is everyone the gear was not drawn for.
  final VoidCallback? onSettings;

  /// Signs out. Null draws no *Sign out* row.
  final VoidCallback? onSignOut;

  /// Below 768: no mark, the person as a circle alone, and the device's state
  /// only when it is offline. The caller decides, because the band is the
  /// page's to know.
  final bool compact;

  /// Where the bar's first glyph starts, so it sits on the page's own edge -
  /// the home's cards' margin. Null is `space.16` on a phone and `space.32`
  /// wider, which are the home's.
  final double? horizontalInset;

  @override
  Size get preferredSize => Size.fromHeight(
    compact
        ? AppLayout.contract.topBarHeightCompact
        : AppLayout.contract.topBarHeight,
  );

  /// A name as the bar prints it: the first name and the last name's initial
  /// - *Boniface M.* - in the person's own capitals.
  static String shortName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.last.isEmpty) return parts.first;
    return '${parts.first} ${parts.last.characters.first}.';
  }

  /// The two letters in the person's circle: the first name's and the last
  /// name's, *AW*. One word gives one letter; no name gives none.
  static String initials(String? full) {
    final parts = (full ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    final first = parts.first.characters.first;
    if (parts.length == 1) return first.toUpperCase();
    return '$first${parts.last.characters.first}'.toUpperCase();
  }

  @override
  State<HubTopBar> createState() => _HubTopBarState();
}

final class _HubTopBarState extends State<HubTopBar> {
  bool? _online;
  StreamSubscription<bool>? _changes;

  @override
  void initState() {
    super.initState();
    _check();
    _listen();
  }

  @override
  void didUpdateWidget(HubTopBar oldWidget) {
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
      // A reading that fails says nothing; the bar keeps what it had.
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
    final icons = tokens.icons;
    final spacing = tokens.spacing;
    final compact = widget.compact;
    final inset =
        widget.horizontalInset ?? (compact ? spacing.s16 : spacing.s32);
    // A 48 control draws its 24 glyph 12 in from its edge, so ending the row
    // 12 short of the inset puts the last glyph on the page's edge too.
    final trailingInset = (inset - spacing.s12).clamp(0.0, inset);
    final terminal = widget.terminalLabel;
    final hasPerson =
        widget.memberName != null ||
        widget.memberRole != null ||
        widget.onSettings != null ||
        widget.onSignOut != null;
    return TopBarSurface(
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: widget.preferredSize.height,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: inset,
              end: trailingInset,
            ),
            child: Row(
              children: <Widget>[
                // **The mark from 768 up, and no mark on a phone.** On a 390
                // handset its 40 pixels are what let *Offline* sit beside
                // *Dev Corner Shop* without cutting the name.
                if (!compact) ...<Widget>[
                  ExcludeSemantics(
                    child: Icon(
                      Symbols.hub_rounded,
                      size: icons.card,
                      color: colors.text.primary,
                      fill: icons.primaryFill,
                      weight: icons.weight,
                      grade: icons.grade,
                      opticalSize: icons.opticalSizeFor(icons.card),
                    ),
                  ),
                  SizedBox(width: spacing.s12),
                ],
                // **The name and the device's state take the slack**, so a
                // long name gives way before any control does and the
                // controls sit hard against the trailing inset.
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: _HubTitle(
                          title: widget.title,
                          onPressed: widget.onTitlePressed,
                          actionLabel: widget.titleActionLabel,
                        ),
                      ),
                      if (terminal != null &&
                          (!compact || _online == false)) ...<Widget>[
                        SizedBox(width: compact ? spacing.s8 : spacing.s12),
                        HubDeviceState(
                          terminalLabel: terminal,
                          online: _online,
                          compact: compact,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: spacing.s8),
                ...widget.actions,
                if (hasPerson) ...<Widget>[
                  if (!compact) SizedBox(width: spacing.s4),
                  _AccountButton(
                    name: widget.memberName,
                    role: widget.memberRole,
                    businessName: widget.title,
                    terminalLabel: terminal,
                    online: _online,
                    onSettings: widget.onSettings,
                    onSignOut: widget.onSignOut,
                    compact: compact,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The business's name, and the way to a different one.
///
/// The same control the toolbar's title is - the same key, the same words to a
/// screen reader, the same chevron - at `moduleTitle`, white, since it is the
/// bar's heading. The chevron is tertiary: it says there is more, and the name
/// is what is read.
final class _HubTitle extends StatelessWidget {
  const _HubTitle({
    required this.title,
    required this.onPressed,
    required this.actionLabel,
  });

  final String title;
  final VoidCallback? onPressed;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final text = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tokens.typography.moduleTitle.copyWith(color: colors.text.primary),
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
        hoverOverlay: _wash(tokens, hovered: true),
        pressedOverlay: _wash(tokens, hovered: false),
        onPressed: press,
        excludeSemantics: true,
        // The ring is drawn outside the name, into the gaps either side, so
        // the name starts on the inset rather than 4 further in.
        reservesRingGutter: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(child: text),
            SizedBox(width: tokens.spacing.s4),
            Icon(
              Icons.expand_more,
              size: AppButton.iconSize,
              color: colors.text.tertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// The bar's hover and pressed washes: white over whichever surface the bar
/// is on at the time, at the tertiary action's opacities.
Color _wash(AppTokens tokens, {required bool hovered}) {
  final role = tokens.colors.action.tertiary;
  return tokens.colors.text.primary.withValues(
    alpha:
        (hovered ? role.hoverOverlayOpacity : role.pressedOverlayOpacity) ?? 0,
  );
}

/// Whether this device is online, and which terminal it is.
///
/// **Quiet when it is normal, loud when it is not.** Online is plain tertiary
/// words behind a green dot, with no fill - nothing a person needs to act on.
/// Offline is an attention [StatusBadge] with a word and a glyph, so it is
/// never colour alone. Before the first reading it names the terminal and
/// guesses nothing. On a phone the bar draws it only offline, as a badge that
/// says *Offline* and leaves the terminal to the account menu.
final class HubDeviceState extends StatelessWidget {
  const HubDeviceState({
    super.key,
    required this.terminalLabel,
    required this.online,
    this.compact = false,
  });

  final String terminalLabel;

  /// Null before the first reading.
  final bool? online;

  final bool compact;

  /// What the state says in full, and what a screen reader hears.
  static String sentence(String terminalLabel, bool? online) {
    final state = switch (online) {
      true => 'Online · ',
      false => 'Offline · ',
      null => '',
    };
    return '${state}Terminal $terminalLabel';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final full = sentence(terminalLabel, online);
    final Widget drawn;
    if (online == false) {
      drawn = StatusBadge(
        status: AppStatus.attention,
        label: compact ? 'Offline' : full,
        icon: Icons.cloud_off,
        semanticLabel: full,
      );
    } else {
      drawn = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (online == true) ...<Widget>[
            Container(
              width: tokens.spacing.s8,
              height: tokens.spacing.s8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.status.ok.fg,
              ),
            ),
            SizedBox(width: tokens.spacing.s4),
          ],
          Flexible(
            child: Text(
              full,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.caption.copyWith(
                color: colors.text.tertiary,
              ),
            ),
          ),
        ],
      );
    }
    return Semantics(
      key: const ValueKey('hub-status'),
      label: full,
      // A change of network is news to someone who cannot see the bar.
      liveRegion: true,
      excludeSemantics: true,
      child: drawn,
    );
  }
}

/// The person: a circle with their initials, and the account menu behind it.
///
/// **One control on every width.** A phone draws the circle alone; from 768
/// up it carries the short name and a chevron. Either opens the menu: who
/// they are and in what role, this device, *Settings* for those allowed it,
/// and *Sign out*. The button stays pressed while its menu is open.
final class _AccountButton extends StatefulWidget {
  const _AccountButton({
    required this.name,
    required this.role,
    required this.businessName,
    required this.terminalLabel,
    required this.online,
    required this.onSettings,
    required this.onSignOut,
    required this.compact,
  });

  final String? name;
  final String? role;
  final String businessName;
  final String? terminalLabel;
  final bool? online;
  final VoidCallback? onSettings;
  final VoidCallback? onSignOut;
  final bool compact;

  @override
  State<_AccountButton> createState() => _AccountButtonState();
}

final class _AccountButtonState extends State<_AccountButton> {
  final MenuController _menu = MenuController();
  bool _open = false;

  void _toggle(BuildContext anchor) {
    if (_menu.isOpen) {
      _menu.close();
      return;
    }
    final tokens = AppTokens.componentOf(context);
    final size = (anchor.findRenderObject()! as RenderBox).size;
    final width = tokens.layout.accountMenuWidth;
    // **Under the button, its trailing edges lined up**, so the menu hangs
    // from the person rather than from the corner of the screen.
    final ltr = Directionality.of(context) == TextDirection.ltr;
    _menu.open(
      position: Offset(
        ltr ? size.width - width : 0,
        size.height + tokens.spacing.s4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final spacing = tokens.spacing;
    final label = <String?>[
      widget.name,
      widget.role,
    ].whereType<String>().join(', ');
    final short = widget.name == null || widget.name!.trim().isEmpty
        ? null
        : HubTopBar.shortName(widget.name!);
    final transparent = colors.surface.base.withValues(alpha: 0);
    return MenuAnchor(
      controller: _menu,
      onOpen: () => setState(() => _open = true),
      onClose: () => setState(() => _open = false),
      // The panel is drawn by [_AccountMenu] so that it can arrive on a
      // spring; the menu's own surface is left empty.
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(transparent),
        surfaceTintColor: WidgetStatePropertyAll<Color>(transparent),
        shadowColor: WidgetStatePropertyAll<Color>(transparent),
        elevation: const WidgetStatePropertyAll<double>(0),
        padding: const WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.zero),
      ),
      menuChildren: <Widget>[
        _AccountMenu(
          name: widget.name,
          role: widget.role,
          businessName: widget.businessName,
          terminalLabel: widget.terminalLabel,
          online: widget.online,
          onSettings: widget.onSettings,
          onSignOut: widget.onSignOut,
        ),
      ],
      builder: (anchor, _, _) => CallbackShortcuts(
        // Escape from the button too, where a keyboard user who opened the
        // menu still is; inside the menu it is the menu's own.
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): _menu.close,
        },
        child: Semantics(
          button: true,
          expanded: _open,
          label: label.isEmpty ? 'Account' : '$label. Account',
          excludeSemantics: true,
          child: PressSurface(
            key: const ValueKey('hub-account'),
            borderRadius: BorderRadius.circular(tokens.radius.pill),
            hoverOverlay: _wash(tokens, hovered: true),
            pressedOverlay: _wash(tokens, hovered: false),
            onPressed: () => _toggle(anchor),
            excludeSemantics: true,
            // The ring is drawn into the bar's own inset and the gap before the
            // button, so the circle's 48 is the whole of what it takes.
            reservesRingGutter: false,
            child: DecoratedBox(
              // Held pressed while the menu it opened is up.
              decoration: BoxDecoration(
                color: _open ? _wash(tokens, hovered: false) : null,
                borderRadius: BorderRadius.circular(tokens.radius.pill),
              ),
              child: widget.compact
                  ? SizedBox.square(
                      dimension: AppIconButton.size,
                      child: Center(child: _Initials(name: widget.name)),
                    )
                  : SizedBox(
                      height: AppIconButton.size,
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: spacing.s8,
                          end: spacing.s12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _Initials(name: widget.name),
                            if (short != null) ...<Widget>[
                              SizedBox(width: spacing.s8),
                              Text(
                                short,
                                maxLines: 1,
                                style: tokens.typography.labelMedium.copyWith(
                                  color: colors.text.primary,
                                ),
                              ),
                            ],
                            SizedBox(width: spacing.s4),
                            Icon(
                              Icons.expand_more,
                              size: AppButton.iconSize,
                              color: colors.text.tertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The person's initials in a circle on the field surface.
///
/// **Neutral for everyone.** The old circle wore `accent.privileged`, which is
/// what a privileged role wears, and it wore it for a cashier too.
final class _Initials extends StatelessWidget {
  const _Initials({required this.name, this.large = false});

  final String? name;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final icons = tokens.icons;
    final size = large ? icons.accountAvatar : icons.hubAvatar;
    final letters = HubTopBar.initials(name);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface.field,
          border: Border.all(color: colors.surface.borderStrong),
        ),
        child: letters.isEmpty
            ? Icon(
                Symbols.person_rounded,
                size: icons.row,
                color: colors.text.secondary,
                fill: icons.primaryFill,
                weight: icons.weight,
                grade: icons.grade,
                opticalSize: icons.opticalSizeFor(icons.row),
              )
            : Text(
                letters,
                style:
                    (large
                            ? tokens.typography.labelMedium
                            : tokens.typography.caption.copyWith(
                                fontWeight:
                                    tokens.typography.labelMedium.fontWeight,
                              ))
                        .copyWith(color: colors.text.secondary),
              ),
      ),
    );
  }
}

/// The account menu's panel: the person, this device, and the way out.
///
/// **It arrives on `spring.snappy`**, growing from `motion.pressScale` at the
/// corner under the button, with its opacity on `motion.short`. It is a fresh panel each
/// time the menu opens and goes the moment it closes, so there is no running
/// animation for a second press to restart.
final class _AccountMenu extends StatefulWidget {
  const _AccountMenu({
    required this.name,
    required this.role,
    required this.businessName,
    required this.terminalLabel,
    required this.online,
    required this.onSettings,
    required this.onSignOut,
  });

  final String? name;
  final String? role;
  final String businessName;
  final String? terminalLabel;
  final bool? online;
  final VoidCallback? onSettings;
  final VoidCallback? onSignOut;

  @override
  State<_AccountMenu> createState() => _AccountMenuState();
}

final class _AccountMenuState extends State<_AccountMenu>
    with SingleTickerProviderStateMixin {
  SpringDrive? _arrival;
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrival != null) return;
    final tokens = AppTokens.componentOf(context);
    final drive = SpringDrive(vsync: this, spring: tokens.motion.snappy);
    _arrival = drive;
    drive.animateTo(1, immediately: MediaQuery.disableAnimationsOf(context));
    // The fade starts on the first frame, so it has somewhere to fade from.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _arrival?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final spacing = tokens.spacing;
    final terminal = widget.terminalLabel;
    final role = widget.role;
    final arrival = _arrival!;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final pressScale = tokens.motion.pressScale;
    final hasRows = widget.onSettings != null || widget.onSignOut != null;

    final panel = Container(
      width: tokens.layout.accountMenuWidth,
      padding: EdgeInsets.all(spacing.s8),
      decoration: BoxDecoration(
        color: colors.surface.overlay,
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        border: Border.all(color: colors.surface.cardEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            container: true,
            label: <String?>[
              widget.name,
              role,
              widget.businessName,
            ].whereType<String>().join(', '),
            excludeSemantics: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.s8,
                spacing.s8,
                spacing.s8,
                spacing.s12,
              ),
              child: Row(
                children: <Widget>[
                  _Initials(name: widget.name, large: true),
                  SizedBox(width: spacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (widget.name case final name?)
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.typography.bodyLarge.copyWith(
                              fontWeight:
                                  tokens.typography.labelMedium.fontWeight,
                              color: colors.text.primary,
                            ),
                          ),
                        Text(
                          <String?>[
                            role,
                            widget.businessName,
                          ].whereType<String>().join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.typography.bodyMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (terminal != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.s8,
                0,
                spacing.s8,
                spacing.s8,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface.base,
                  borderRadius: BorderRadius.circular(tokens.radius.md),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: spacing.s12,
                    vertical: spacing.s8,
                  ),
                  child: Semantics(
                    key: const ValueKey('hub-account-device'),
                    label: HubDeviceState.sentence(terminal, widget.online),
                    excludeSemantics: true,
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: spacing.s8,
                          height: spacing.s8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: switch (widget.online) {
                              true => colors.status.ok.fg,
                              false => colors.status.attention.fg,
                              null => colors.text.tertiary,
                            },
                          ),
                        ),
                        SizedBox(width: spacing.s8),
                        Expanded(
                          child: Text(
                            HubDeviceState.sentence(terminal, widget.online),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.typography.bodyMedium.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (hasRows) ...<Widget>[
            Padding(
              padding: EdgeInsets.symmetric(vertical: spacing.s4),
              child: Divider(
                height: 1,
                thickness: 1,
                color: colors.surface.cardEdge,
              ),
            ),
            if (widget.onSettings case final open?)
              _AccountRow(
                key: const ValueKey('hub-settings'),
                icon: Icons.settings_outlined,
                label: 'Settings',
                onPressed: open,
              ),
            // **Not red.** It ends a session; it destroys nothing.
            if (widget.onSignOut case final leave?)
              _AccountRow(
                key: const ValueKey('sign-out'),
                icon: Icons.logout,
                label: 'Sign out',
                onPressed: leave,
              ),
          ],
        ],
      ),
    );

    return AnimatedOpacity(
      opacity: _shown || reduced ? 1 : 0,
      duration: reduced ? Duration.zero : tokens.motion.short.duration,
      curve: tokens.motion.short.curve,
      child: AnimatedBuilder(
        animation: arrival.animation,
        builder: (context, child) => Transform.scale(
          // From `motion.pressScale`, the app's one "slightly smaller".
          scale: pressScale + (1 - pressScale) * arrival.value,
          alignment: Directionality.of(context) == TextDirection.ltr
              ? Alignment.topRight
              : Alignment.topLeft,
          child: child,
        ),
        child: panel,
      ),
    );
  }
}

/// One row of the account menu: a glyph and a word, 48 high.
final class _AccountRow extends StatelessWidget {
  const _AccountRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final ring = colors.action.focusRing;
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: Icon(icon, size: AppButton.iconSize),
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size>(
          Size.fromHeight(AppIconButton.size),
        ),
        padding: WidgetStatePropertyAll<EdgeInsets>(
          EdgeInsets.symmetric(horizontal: tokens.spacing.s12),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius.md),
          ),
        ),
        foregroundColor: WidgetStatePropertyAll<Color>(colors.text.primary),
        iconColor: WidgetStatePropertyAll<Color>(colors.text.secondary),
        backgroundColor: WidgetStatePropertyAll<Color>(
          colors.surface.overlay.withValues(alpha: 0),
        ),
        overlayColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.pressed)
              ? _wash(tokens, hovered: false)
              : states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
              ? _wash(tokens, hovered: true)
              : null,
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(
          tokens.typography.labelMedium,
        ),
        // The ring every control in the app draws, inside the row so it
        // does not land on its neighbours.
        side: WidgetStateProperty.resolveWith<BorderSide?>(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: ring.color, width: ring.width)
              : null,
        ),
      ),
      child: Text(label),
    );
  }
}
