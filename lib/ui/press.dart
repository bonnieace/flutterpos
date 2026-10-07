/// `PressSurface`: `design.md` §5.1's replacement for the ink ripple, and §2.4's
/// "opacity-plus-scale state overlay (`0.97` scale, `spring.snappy`)".
///
/// **Step 2 killed the ripple and could not build the press.** `NoSplash` on the
/// theme reaches every control in the app in one line and leaves nothing in its
/// place but a colour change, because a `ButtonStyle` can express an overlay and
/// cannot express a scale. This is the other half, and `DESIGN-AUDIT.md` §6
/// decision 4 is why it arrives now rather than then: it needs a spring
/// substrate, and building one in step 2 would have meant touching every call
/// site twice.
///
/// **Three states are drawn here and the fourth is refused.** Hover and pressed
/// are §2.1's overlay rows. Focus-visible is §2.1's **ring** - 2px at a 2px
/// offset - which is a border rather than an overlay and is the row the
/// theme-level step could not express at all. What is deliberately not here is
/// `disabled`: a disabled surface has no press, no hover and no focus, so
/// [PressSurface] renders it by taking [onPressed] away and letting its caller
/// paint the disabled colours. A component knows what its own disabled label
/// looks like; a press surface does not.
///
/// **The ring's 4px is reserved, always, rather than appearing on focus.** A ring
/// at a 2px offset needs 4px outside the shape it decorates. Painting it only
/// when focused would reflow the row it sits in the moment a keyboard user tabs
/// into it, which is a worse accessibility failure than the one §9 is asking to
/// fix.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'spring.dart';
import 'tokens.dart';

/// A tappable surface that scales instead of rippling.
///
/// It paints, in this order: the ring's reserved gutter, the focus ring when
/// the focus is visible, then [child] scaled by the spring, with the state
/// overlay over it. [child] draws its own container - this widget does not know
/// what shape it is wrapping, only [borderRadius], which it needs so the
/// overlay and the ring follow the same outline.
final class PressSurface extends StatefulWidget {
  const PressSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.onPressed,
    this.onLongPress,
    this.hoverOverlay,
    this.pressedOverlay,
    this.focusNode,
    this.autofocus = false,
    this.minimumTapTarget,
    this.mouseCursor,
    this.semanticLabel,
    this.excludeSemantics = false,
    this.fillWidth = false,
    this.fillHeight = false,
    this.reservesRingGutter = true,
    this.ringInside = false,
  });

  /// The surface itself, drawing its own container, border and label.
  final Widget child;

  /// The outline the overlay and the focus ring follow. `design.md` §2.3 makes
  /// this `radius.pill` for a button and `radius.sm` for a chip.
  final BorderRadius borderRadius;

  /// Null makes the surface inert: no hover, no press, no focus, no spring.
  final VoidCallback? onPressed;

  final VoidCallback? onLongPress;

  /// §2.1's hover row. Null paints nothing, for a surface whose hover is
  /// carried by something else.
  final Color? hoverOverlay;

  /// §2.1's pressed row.
  final Color? pressedOverlay;

  final FocusNode? focusNode;

  final bool autofocus;

  /// The smallest area that answers a tap, expanded around the visual surface
  /// without moving it.
  ///
  /// §9 makes 48 x 48 pass/fail on a touch device, and §5.2 gives `AppButton`
  /// an `sm` size of 32h. Both are satisfiable at once only by separating what
  /// is painted from what is hit, which is what this does. Defaults to the
  /// density's own minimum from [AppTokens], so a compact back-office surface
  /// gets §3's 32 x 32 and a touch surface cannot.
  final Size? minimumTapTarget;

  final MouseCursor? mouseCursor;

  /// The semantic label, for a surface whose [child] is an icon. §9 requires
  /// one on an icon-only control.
  final String? semanticLabel;

  /// Set by a caller that announces itself - [AppButton] wraps the whole
  /// surface in its own [Semantics] node, and two nested button nodes read as
  /// two buttons.
  final bool excludeSemantics;

  /// Whether the surface fills the width it is offered.
  ///
  /// The minimum-tap-target box shrink-wraps its child by default, because a
  /// button in a `Wrap` would otherwise be as wide as the row. A caller that
  /// wants a full-width button sets this rather than wrapping the result in a
  /// [SizedBox], which would stretch the box and leave the painted surface
  /// floating in the middle of it.
  final bool fillWidth;

  /// Whether the surface fills the height it is offered.
  ///
  /// [fillWidth]'s twin, and off for the same reason: the minimum-tap-target
  /// box shrink-wraps so that a 32-high button stays 32 while its hit area is
  /// 48, which is what keeps §5.2's three button sizes from collapsing into
  /// one.
  ///
  /// **A caller sets it where equal height is the layout**, which is a grid
  /// rather than a row of buttons - `HomeNavigation` puts two cards side by
  /// side under an `IntrinsicHeight` and needs the painted surfaces to be the
  /// same height, not merely the slots they sit in.
  final bool fillHeight;

  /// Whether this surface reserves the focus ring's gutter around itself.
  ///
  /// **Off only for a segment of a joined group**, which is `Pagination`'s
  /// pager: three segments share one container, and a gutter round each would
  /// pull them 8 apart. The group reserves one gutter round all of them
  /// instead, and a segment's ring is painted outside its own box - into that
  /// gutter at the group's ends, and over the neighbour's edge between
  /// segments. The ring is the same ring, at the same place against the
  /// surface; only where its room comes from moves.
  final bool reservesRingGutter;

  /// Whether the focus ring is painted just inside the surface's own edge,
  /// with no gutter reserved round it.
  ///
  /// **For a row that fills a card**, which is the Bluetooth printer tab's
  /// device list. A gutter round each row would pull it in from the card's
  /// edges, and a ring outside it would land on the card's own edge and on the
  /// rows above and below. Inside, it is the same ring - the same width, the
  /// same colour - drawn where the row has room for it, following
  /// [borderRadius] itself rather than that radius plus the offset.
  /// [reservesRingGutter] does not apply.
  final bool ringInside;

  @override
  State<PressSurface> createState() => _PressSurfaceState();
}

class _PressSurfaceState extends State<PressSurface>
    with SingleTickerProviderStateMixin {
  SpringDrive? _drive;
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;
  late FocusHighlightMode _highlightMode;

  /// The tokens and the reduced-motion flag, **read during `build` and held**,
  /// rather than looked up from `context` when a gesture arrives.
  ///
  /// Not a convenience. A pointer that is still down when the tree is torn
  /// down - a route popped mid-press, or a test releasing a held gesture in a
  /// tear-down - delivers its `up` to a **deactivated** element, and
  /// `MediaQuery.of` there throws "Looking up a deactivated widget's ancestor
  /// is unsafe". Reading in `build` also registers the dependency properly, so
  /// switching motion off rebuilds this widget instead of being noticed at the
  /// next press.
  AppTokens _tokens = AppTokens.dark;
  bool _animationsDisabled = false;

  bool get _enabled => widget.onPressed != null || widget.onLongPress != null;

  /// §9's focus indicator is for a person navigating with a keyboard, so a tap
  /// that happens to focus a button does not draw a ring.
  ///
  /// This is the same rule `InkResponse` applies, and it is read from the same
  /// place, so the ring appears and disappears in this app exactly when it does
  /// in an unmigrated Material control beside it.
  bool get _focusVisible =>
      _focused && _highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    _highlightMode = FocusManager.instance.highlightMode;
    FocusManager.instance.addHighlightModeListener(_handleHighlightModeChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(
      _handleHighlightModeChange,
    );
    _drive?.dispose();
    super.dispose();
  }

  void _handleHighlightModeChange(FocusHighlightMode mode) {
    if (!mounted || mode == _highlightMode) return;
    setState(() => _highlightMode = mode);
  }

  /// The spring, created on first use because its physics is a token and
  /// [initState] has no theme to read. A surface nobody has touched holds no
  /// ticker at all.
  SpringDrive get _spring =>
      _drive ??= SpringDrive(vsync: this, spring: _tokens.motion.snappy);

  /// Retargets the spring toward pressed (1) or released (0).
  ///
  /// **Never `forward()` and never from zero**: `SpringDrive.animateTo` reads
  /// the live value and the live velocity, so a second press arriving while the
  /// first is still releasing takes over mid-flight, which is `claude.md`'s
  /// motion rule and §2.4's first one.
  void _setPressed(bool pressed) {
    // A pointer can come up after the tree it was pressing has gone.
    if (!mounted || _pressed == pressed) return;
    setState(() => _pressed = pressed);
    _spring.animateTo(pressed ? 1 : 0, immediately: _animationsDisabled);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens = AppTokens.componentOf(context);
    _animationsDisabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final ring = tokens.colors.action.focusRing;
    final gutter = ring.width + ring.offset;
    final target = widget.minimumTapTarget ?? tokens.density.minimumTapTarget;

    final overlay = !_enabled
        ? null
        : _pressed
        ? widget.pressedOverlay
        // §2.1 gives focus-visible a ring and no wash, so a focused button
        // that is not hovered paints no overlay. The ring is the feedback.
        : _hovered
        ? widget.hoverOverlay
        : null;

    Widget surface = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        widget.child,
        if (overlay != null)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: overlay,
                  borderRadius: widget.borderRadius,
                ),
              ),
            ),
          ),
      ],
    );

    final drive = _drive;
    if (drive != null) {
      surface = AnimatedBuilder(
        animation: drive.animation,
        builder: (context, child) => Transform.scale(
          // The spring runs 0 to 1 and the scale is read off it, rather than
          // the spring running 1.0 to 0.97: `SpringSimulation` decides it is
          // done against an absolute tolerance, and a 0.03-wide journey is
          // over before it starts.
          //
          // No `filterQuality`: passing one installs an `ImageFilter` and a
          // save layer on every pressed control, and §2.4's frame budget makes
          // a dropped frame on the sale path a defect rather than a polish
          // item.
          scale: lerpDouble(1, tokens.motion.pressScale, drive.value)!,
          child: child,
        ),
        child: surface,
      );
    }

    // The ring is drawn outside the surface, in a gutter reserved whether it is
    // visible or not, so tabbing into a row cannot reflow it.
    final reserves = widget.reservesRingGutter && !widget.ringInside;
    Widget framed = reserves
        ? Padding(padding: EdgeInsets.all(gutter), child: surface)
        : surface;
    if (_focusVisible) {
      // Where the ring's box sits against [framed]: inside the reserved
      // gutter, or - with no gutter of its own - the same distance outside the
      // surface, in room the caller reserved. Both put the ring in one place.
      // [PressSurface.ringInside] puts it on the surface's own edge instead.
      final inset = widget.ringInside
          ? 0.0
          : reserves
          ? ring.offset
          : ring.offset - gutter;
      framed = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          framed,
          Positioned(
            left: inset,
            top: inset,
            right: inset,
            bottom: inset,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: ring.color, width: ring.width),
                  // The ring sits outside the shape, so its corners are the
                  // shape's plus the offset. On a pill both are already past
                  // any real dimension and it makes no difference; on a chip
                  // at `radius.sm` it is the difference between a ring that
                  // follows the corner and one that cuts across it.
                  borderRadius: widget.ringInside
                      ? widget.borderRadius
                      : widget.borderRadius +
                            BorderRadius.circular(ring.offset),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // The hit area, expanded around the painted surface rather than applied to
    // it. `heightFactor: 1` is what keeps them separate: the box is at least
    // 48 high and the surface inside it stays whatever §5.2 says it is, so a
    // 32-high button is still 48 to a thumb. Constraining the surface directly
    // would have made every small button 48 high and quietly deleted two of
    // §5.2's three sizes.
    //
    // **This sits *inside* the gesture detector, and the order is the whole
    // point.** With the detector inside instead, the extra area is reserved,
    // laid out, and answers nothing: a tap two pixels inside the top of a 32
    // high button lands on the padding and is swallowed. §9's target would
    // have measured 48 in a size assertion and been 32 to a finger, which is
    // the kind of pass a test can give you while the defect ships.
    final sized = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: target.width,
        minHeight: target.height,
      ),
      child: Align(
        alignment: Alignment.center,
        widthFactor: widget.fillWidth ? null : 1,
        heightFactor: widget.fillHeight ? null : 1,
        child: framed,
      ),
    );

    Widget result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => _setPressed(true) : null,
      onTapUp: _enabled ? (_) => _setPressed(false) : null,
      onTapCancel: _enabled ? () => _setPressed(false) : null,
      onTap: widget.onPressed,
      onLongPress: widget.onLongPress,
      child: sized,
    );

    result = MouseRegion(
      cursor:
          widget.mouseCursor ??
          (_enabled ? SystemMouseCursors.click : SystemMouseCursors.basic),
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: result,
    );

    result = Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: _enabled,
      skipTraversal: !_enabled,
      onFocusChange: (focused) {
        if (!mounted) return;
        setState(() => _focused = focused);
      },
      onKeyEvent: _handleKeyEvent,
      child: result,
    );

    if (widget.excludeSemantics) return result;
    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      onTap: widget.onPressed,
      child: result,
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered || !mounted) return;
    setState(() => _hovered = hovered);
  }

  /// Space and Enter activate a focused surface, which is what a keyboard user
  /// expects and what [GestureDetector] alone does not give them.
  ///
  /// The press spring runs on the key too, so the feedback a keyboard user gets
  /// is the same feedback a finger gets rather than nothing at all.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_enabled) return KeyEventResult.ignored;
    final isActivation =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isActivation) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _setPressed(true);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _setPressed(false);
      widget.onPressed?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
