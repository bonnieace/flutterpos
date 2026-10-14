/// `AppTabs`: `design.md` §5.1's priority-3 row for "platform tabs", drawn as
/// `docs/design/tabs/` draws it.
///
/// **Two shapes, chosen by how many tabs there are, so no screen chooses.**
/// Two tabs are a *switch*: a capsule track with a raised thumb behind the
/// selected half, after the *Live / Demo* control the developer picked as the
/// reference on 2026-10-04. Three or more are *icon tabs*: a glyph and a label
/// each, packed from the start, the selected one in the accent and underlined,
/// after the action dashboard reference picked the same day. Both are drawn in
/// this app's own tokens; the board's README says what each reference lends
/// and what it does not.
///
/// **It still wraps `TabBar` rather than redrawing one, and that is the same
/// decision `AppScaffold` made about `AppBar`.** `TabBar` owns the
/// `TabController` handshake, the scroll-into-view of a selected tab, the tab
/// semantics and the keyboard traversal; hand-drawing it would move selection
/// behaviour into a visual change, which `claude.md` hard rule 1 forbids.
///
/// **What this file owns besides the look is the one part that moves.** The
/// switch's thumb and the strip's underline are painted here, behind
/// `TabBar`, from two springs - because `TabBar`'s own indicator follows the
/// controller's 300ms ease and cannot be given a spring, and §2.4 says anything
/// spatial is one. `TabBar` is handed an indicator that paints nothing. While a
/// finger drags the `TabBarView` below, the mark follows the controller's
/// offset directly, so it never lags the finger; the springs take over on a
/// tap.
///
/// **The height is the 48 the component has always claimed, and now is.** The
/// strip used to be a 48 tab plus `TabBar`'s 2px indicator padding, 50 in all,
/// with Material 3 drawing a 3px indicator over the 2 this file asked for.
/// Neither survives: the cells are 48 and the indicator weight is zero.
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';

import 'measure.dart';
import 'spring.dart';
import 'tokens.dart';

/// A row of tabs, in this system's type and colour.
///
/// Requires a `TabController` above it, exactly as `TabBar` does - usually a
/// `DefaultTabController`. This component deliberately does not create one:
/// which tab is selected is state, and a component that owned it would be a
/// behaviour change wearing a visual component's clothes.
final class AppTabs extends StatefulWidget implements PreferredSizeWidget {
  const AppTabs({
    super.key,
    required this.tabs,
    this.icons,
    this.inset = 0,
    this.alignment = AlignmentDirectional.centerStart,
  }) : assert(icons == null || icons.length == tabs.length);

  /// One label per tab, in order. Sentence case, §8 rule 7 - this widget does
  /// not case them.
  final List<String> tabs;

  /// One glyph per tab, for icon tabs. The one each tab's own panel already
  /// leads with, so the tab and what it opens look alike.
  ///
  /// Ignored by the two-tab switch, which the reference draws without glyphs.
  final List<IconData>? icons;

  /// The horizontal inset of the content this strip sits over, so the two line
  /// up.
  ///
  /// **A page passes its inset and a section passes nothing.** Under a toolbar
  /// the strip runs the screen's width while the page's text sits in from it;
  /// inside the reading column the strip is already where the text is. The
  /// switch is drawn inside the inset. Icon tabs reach the screen's edge - their
  /// hairline should - and are padded so the first glyph, which sits a tab's
  /// padding into its cell, lands on the inset.
  final double inset;

  /// Where a switch narrower than its row sits. From the start by default; a
  /// screen whose content column is centred on a wide window centres its
  /// switch over it. Icon tabs ignore it.
  final AlignmentGeometry alignment;

  /// §9's touch-target row, which Material's own tab height misses by two.
  static double get height => AppDensity.comfortable.minimumTapTarget.height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  State<AppTabs> createState() => _AppTabsState();
}

enum _Shape { segmented, strip }

/// How a strip lays out at the width it was given.
typedef _Layout = ({_Shape shape, double? width, double height});

final class _AppTabsState extends State<AppTabs> with TickerProviderStateMixin {
  TabController? _controller;

  /// The two ends of the moving mark, in *tab units* - `1.5` is half way
  /// between the second tab and the third - rather than in pixels.
  ///
  /// **Tab units are what make the mark indifferent to everything else that
  /// moves.** The painter turns them into pixels from where the tabs actually
  /// are on the frame it paints, so a strip that scrolls, a window that
  /// resizes and a text scale that changes mid-flight all land the mark on the
  /// right tab without the springs being told. They are also the controller's
  /// own units, so a drag hands over with no conversion.
  SpringDrive? _start;
  SpringDrive? _end;

  /// Whether the springs, rather than the controller, say where the mark is.
  bool _springing = false;

  final _Repaint _repaint = _Repaint();
  final GlobalKey _stackKey = GlobalKey();
  List<GlobalKey> _markKeys = <GlobalKey>[];

  int? _hovered;
  int? _pressed;
  int? _focused;
  late FocusHighlightMode _highlightMode;

  bool _fadeLeft = false;
  bool _fadeRight = false;

  /// Read during `build` and held, for the reason `PressSurface` gives: a
  /// listener can fire after the element has been deactivated.
  AppTokens _tokens = AppTokens.dark;
  bool _animationsDisabled = false;
  _Shape _shape = _Shape.segmented;
  bool _rtl = false;

  @override
  void initState() {
    super.initState();
    _markKeys = _keysFor(widget.tabs.length);
    _highlightMode = FocusManager.instance.highlightMode;
    FocusManager.instance.addHighlightModeListener(_handleHighlightMode);
  }

  @override
  void didUpdateWidget(AppTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabs.length != widget.tabs.length) {
      _markKeys = _keysFor(widget.tabs.length);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tokens = AppTokens.componentOf(context);
    final controller = DefaultTabController.maybeOf(context);
    if (controller != _controller) {
      _controller?.removeListener(_handleIndex);
      _controller?.animation?.removeListener(_handleTick);
      _controller = controller;
      controller?.addListener(_handleIndex);
      controller?.animation?.addListener(_handleTick);
      _springing = false;
    }
    final at = controller?.index.toDouble() ?? 0;
    _start ??= SpringDrive(
      vsync: this,
      spring: _tokens.motion.snappy,
      value: at,
    )..animation.addStatusListener(_handleSettle);
    _end ??= SpringDrive(vsync: this, spring: _tokens.motion.snappy, value: at)
      ..animation.addStatusListener(_handleSettle);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_handleHighlightMode);
    _controller?.removeListener(_handleIndex);
    _controller?.animation?.removeListener(_handleTick);
    _start?.dispose();
    _end?.dispose();
    _repaint.dispose();
    super.dispose();
  }

  static List<GlobalKey> _keysFor(int count) =>
      List<GlobalKey>.generate(count, (_) => GlobalKey());

  void _handleHighlightMode(FocusHighlightMode mode) {
    if (!mounted || mode == _highlightMode) return;
    setState(() => _highlightMode = mode);
  }

  /// A new index. A tap - or anything else that calls `animateTo` - has
  /// `indexIsChanging` set, and that is the move the springs answer. A swipe
  /// settling on its page sets the index without it, and the mark is already
  /// there, having followed the finger.
  void _handleIndex() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;
    if (controller.indexIsChanging) _springTo(controller.index);
    // The cells draw selected and unselected differently on hover.
    setState(() {});
  }

  /// A finger on the page below, mid-spring, takes the mark back.
  void _handleTick() {
    final controller = _controller;
    if (controller == null || !_springing) return;
    if (!controller.indexIsChanging && controller.offset != 0) {
      final at = controller.animation!.value;
      _start!.animateTo(at, immediately: true);
      _end!.animateTo(at, immediately: true);
      _springing = false;
    }
  }

  void _handleSettle(AnimationStatus status) {
    if (_start!.isAnimating || _end!.isAnimating) return;
    if (!_springing) return;
    _springing = false;
    _repaint.notify();
  }

  /// Retargets both ends at [index], from wherever they are and however fast
  /// they are going.
  ///
  /// **The end on the side of travel leads on `spring.snappy` and the other
  /// follows on `spring.smooth`**, so the underline stretches toward the new
  /// tab and settles on its width. The switch's thumb is one piece - both its
  /// halves are the same width - so both ends take `snappy` and it slides.
  void _springTo(int index) {
    final start = _start!;
    final end = _end!;
    final controller = _controller!;
    if (!_springing) {
      // From where the mark is drawn, which until now was the controller.
      final at = controller.animation!.value;
      start.animateTo(at, immediately: true);
      end.animateTo(at, immediately: true);
    }
    final target = index.toDouble();
    final motion = _tokens.motion;
    final trailing = _shape == _Shape.strip ? motion.smooth : motion.snappy;
    // Higher tab units are rightward in a left-to-right strip.
    final rightward = (target >= (start.value + end.value) / 2) != _rtl;
    start.animateTo(
      target,
      immediately: _animationsDisabled,
      physics: rightward ? trailing : motion.snappy,
    );
    end.animateTo(
      target,
      immediately: _animationsDisabled,
      physics: rightward ? motion.snappy : trailing,
    );
    _springing = start.isAnimating || end.isAnimating;
    _repaint.notify();
  }

  /// Where the mark's two ends are, in tab units.
  ({double start, double end}) _position() {
    if (_springing) return (start: _start!.value, end: _end!.value);
    final controller = _controller;
    if (controller == null) return (start: 0, end: 0);
    // §2.4's reduced-motion clause. The controller's own animation still runs
    // its 300ms, and following it would be motion that was switched off.
    final at = _animationsDisabled && controller.indexIsChanging
        ? controller.index.toDouble()
        : controller.animation!.value;
    return (start: at, end: at);
  }

  void _setHovered(bool hovered, int index) {
    if (!mounted) return;
    setState(() {
      if (hovered) {
        _hovered = index;
      } else if (_hovered == index) {
        _hovered = null;
      }
    });
  }

  void _setFocused(bool focused, int index) {
    if (!mounted) return;
    setState(() {
      if (focused) {
        _focused = index;
      } else if (_focused == index) {
        _focused = null;
      }
    });
  }

  void _setPressed(bool pressed, int index) {
    if (!mounted) return;
    setState(() {
      if (pressed) {
        _pressed = index;
      } else if (_pressed == index) {
        _pressed = null;
      }
    });
  }

  /// Which end of a scrolling strip has more tabs past it.
  bool _handleScroll(Notification notification) {
    final ScrollMetrics? metrics = switch (notification) {
      final ScrollNotification n when n.depth == 0 => n.metrics,
      final ScrollMetricsNotification n when n.depth == 0 => n.metrics,
      _ => null,
    };
    if (metrics == null || metrics.axis != Axis.horizontal) return false;
    final before = metrics.extentBefore > precisionErrorTolerance;
    final after = metrics.extentAfter > precisionErrorTolerance;
    final reversed = metrics.axisDirection == AxisDirection.left;
    final left = reversed ? after : before;
    final right = reversed ? before : after;
    if (left != _fadeLeft || right != _fadeRight) {
      setState(() {
        _fadeLeft = left;
        _fadeRight = right;
      });
    }
    _repaint.notify();
    return false;
  }

  /// `label.md`, with its tracking stated.
  ///
  /// **The role names no tracking, which means none.** `TabBar` merges the
  /// style it is given onto Material's own tab label - `titleSmall`, tracked
  /// 0.1 - so a role that leaves `letterSpacing` unset inherits Material's
  /// rather than this system's, and every label comes out wider than the
  /// boards measure it.
  TextStyle _labelStyle() {
    final role = _tokens.typography.labelMedium;
    return role.copyWith(letterSpacing: role.letterSpacing ?? 0);
  }

  /// Two tabs that fit are a switch, at the width the band gives it. Two that
  /// do not, and anything other than two, are a strip.
  _Layout _resolve(double maxWidth) {
    final strip = (shape: _Shape.strip, width: null, height: AppTabs.height);
    if (widget.tabs.length != 2 || !maxWidth.isFinite) return strip;

    final space = _tokens.spacing;
    final scaler = MediaQuery.textScalerOf(context);
    final style = _labelStyle();
    final available = math.max(0.0, maxWidth - 2 * widget.inset);
    final widest = widget.tabs
        .map((label) => measureTextWidth(label, style, textScaler: scaler))
        .reduce(math.max);

    // From `medium` up the switch is as wide as its labels need: each half is
    // the wider label and `space.24` a side, so the halves stay equal and stay
    // a thumb's width apart rather than a column's.
    final hugged = 2 * (widest + 2 * space.s24);
    final wide = maxWidth >= _tokens.layout.mediumFloor;
    if (wide && hugged <= available) {
      final line = _wrappedHeight(widget.tabs.first, style, scaler, widest);
      return (
        shape: _Shape.segmented,
        width: hugged,
        height: _segmentHeight(line ?? 0),
      );
    }

    // Below it the switch fills the width, and a label that is too long for
    // its half wraps onto a second line rather than being cut.
    final room = available / 2 - 2 * _segmentLabelInset(space);
    var text = 0.0;
    for (final label in widget.tabs) {
      final height = _wrappedHeight(label, style, scaler, room);
      // A single word wider than its half cannot wrap. The strip scrolls.
      if (height == null) return strip;
      text = math.max(text, height);
    }
    return (
      shape: _Shape.segmented,
      width: available,
      height: _segmentHeight(text),
    );
  }

  /// The thumb's inset, then `space.16`, from a half's edge to its label.
  double _segmentLabelInset(AppSpacing space) => space.s4 + space.s16;

  /// 48, or the label's lines and `space.12` above and below if that is more.
  double _segmentHeight(double text) =>
      math.max(AppTabs.height, text + 2 * _tokens.spacing.s12);

  /// How tall [label] is when wrapped to [room], or null when it needs more
  /// than two lines or holds a word wider than [room].
  double? _wrappedHeight(
    String label,
    TextStyle style,
    TextScaler scaler,
    double room,
  ) {
    if (room <= 0) return null;
    for (final word in label.split(RegExp(r'\s+'))) {
      if (measureTextWidth(word, style, textScaler: scaler) > room) return null;
    }
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
      textScaler: scaler,
      maxLines: 2,
    )..layout(maxWidth: room);
    final height = painter.didExceedMaxLines ? null : painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens = AppTokens.componentOf(context);
    _animationsDisabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _rtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _resolve(constraints.maxWidth);
        _shape = layout.shape;
        return switch (layout.shape) {
          _Shape.segmented => _buildSwitch(tokens, layout),
          _Shape.strip => _buildStrip(tokens),
        };
      },
    );
  }

  TabBar _tabBar({
    required AppTokens tokens,
    required bool scrolls,
    required Color selected,
    required Color unselected,
    required List<Widget> cells,
  }) {
    final style = _labelStyle();
    return TabBar(
      isScrollable: scrolls,
      tabAlignment: scrolls ? TabAlignment.start : TabAlignment.fill,
      padding: scrolls
          ? EdgeInsets.symmetric(
              horizontal: math.max(0.0, widget.inset - tokens.spacing.s12),
            )
          : null,
      // The cells draw their own padding, wash and ring, so they can be the
      // whole target and know their own state.
      labelPadding: EdgeInsets.zero,
      // The mark is painted behind the bar, on springs; see the library note.
      indicator: const BoxDecoration(),
      indicatorWeight: 0,
      dividerHeight: 0,
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      labelStyle: style,
      unselectedLabelStyle: style,
      labelColor: selected,
      unselectedLabelColor: unselected,
      onHover: _setHovered,
      onFocusChange: _setFocused,
      tabs: cells,
    );
  }

  List<Widget> _cells(_Shape shape, double height) {
    final selectedIndex = _controller?.index ?? 0;
    final focusVisible = _highlightMode == FocusHighlightMode.traditional;
    return <Widget>[
      for (var i = 0; i < widget.tabs.length; i++)
        _Cell(
          markKey: _markKeys[i],
          shape: shape,
          label: widget.tabs[i],
          icon: shape == _Shape.strip ? (widget.icons?[i]) : null,
          height: height,
          selected: i == selectedIndex,
          hovered: _hovered == i,
          pressed: _pressed == i,
          focusVisible: focusVisible && _focused == i,
          animationsDisabled: _animationsDisabled,
          onPressedChanged: (pressed) => _setPressed(pressed, i),
        ),
    ];
  }

  Listenable _repaints() => Listenable.merge(<Listenable?>[
    _repaint,
    _controller?.animation,
    _start!.animation,
    _end!.animation,
  ]);

  Widget _buildSwitch(AppTokens tokens, _Layout layout) {
    final colors = tokens.colors;
    final bar = _tabBar(
      tokens: tokens,
      scrolls: false,
      selected: colors.text.primary,
      unselected: colors.text.secondary,
      cells: _cells(_Shape.segmented, layout.height),
    );
    final track = SizedBox(
      width: layout.width,
      height: layout.height,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.surface.raised,
          shape: StadiumBorder(
            side: BorderSide(color: colors.surface.borderSubtle),
          ),
        ),
        child: Stack(
          key: _stackKey,
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MarkPainter(
                    shape: _Shape.segmented,
                    keys: _markKeys,
                    stackKey: _stackKey,
                    position: _position,
                    tokens: tokens,
                    repaint: _repaints(),
                  ),
                ),
              ),
            ),
            bar,
          ],
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.inset),
      child: Align(alignment: widget.alignment, child: track),
    );
  }

  Widget _buildStrip(AppTokens tokens) {
    final colors = tokens.colors;
    final bar = _tabBar(
      tokens: tokens,
      scrolls: true,
      selected: colors.action.primary.container,
      unselected: colors.text.tertiary,
      cells: _cells(_Shape.strip, AppTabs.height),
    );
    final fade = tokens.spacing.s32;
    return DecoratedBox(
      // The hairline is outside the fade, so it runs to the edge whether or not
      // the tabs above it do.
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.surface.borderSubtle)),
      ),
      child: NotificationListener<Notification>(
        onNotification: _handleScroll,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          // A mask reads alpha alone, so any opaque token serves. A fade is a
          // mask rather than a gradient painted over the tabs because the strip
          // has no colour of its own to fade into: it sits on the page here
          // and could sit on a card elsewhere.
          shaderCallback: (bounds) {
            final opaque = colors.surface.base;
            final clear = opaque.withValues(alpha: 0);
            final stop = bounds.width <= 0
                ? 0.0
                : (fade / bounds.width).clamp(0.0, 0.5);
            return LinearGradient(
              colors: <Color>[
                _fadeLeft ? clear : opaque,
                opaque,
                opaque,
                _fadeRight ? clear : opaque,
              ],
              stops: <double>[0, stop, 1 - stop, 1],
            ).createShader(bounds);
          },
          child: Stack(
            key: _stackKey,
            children: <Widget>[
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MarkPainter(
                      shape: _Shape.strip,
                      keys: _markKeys,
                      stackKey: _stackKey,
                      position: _position,
                      tokens: tokens,
                      repaint: _repaints(),
                    ),
                  ),
                ),
              ),
              bar,
            ],
          ),
        ),
      ),
    );
  }
}

/// One tab: the whole 48-high target, with its wash, its label and its ring.
///
/// **The label's colour is `TabBar`'s, read from the ambient text style**, so
/// the cross-fade between selected and unselected stays the controller's. This
/// widget only lifts an unselected label a step while a pointer is on it or a
/// press is down.
final class _Cell extends StatelessWidget {
  const _Cell({
    required this.markKey,
    required this.shape,
    required this.label,
    required this.icon,
    required this.height,
    required this.selected,
    required this.hovered,
    required this.pressed,
    required this.focusVisible,
    required this.animationsDisabled,
    required this.onPressedChanged,
  });

  /// On what the moving mark spans: the whole cell for the switch, the glyph
  /// and label for icon tabs.
  final GlobalKey markKey;
  final _Shape shape;
  final String label;
  final IconData? icon;
  final double height;
  final bool selected;
  final bool hovered;
  final bool pressed;
  final bool focusVisible;
  final bool animationsDisabled;
  final ValueChanged<bool> onPressedChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final space = tokens.spacing;
    final ring = colors.action.focusRing;
    final overlay = colors.action.secondary;
    final short = tokens.motion.short;
    final duration = animationsDisabled ? Duration.zero : short.duration;
    final ambient = DefaultTextStyle.of(context).style.color;

    // §2.1's overlay rows, at the secondary tier's strengths.
    final wash = pressed
        ? overlay.pressedWash()
        : hovered
        ? overlay.hoverWash()
        : overlay.hoverWash().withValues(alpha: 0);
    final lift = !selected && (hovered || pressed) ? 1.0 : 0.0;

    final segmented = shape == _Shape.segmented;
    final washShape = segmented
        ? const StadiumBorder()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius.md),
          );
    // The ring is 2 at a 2 offset round the wash, so its outside is the cell's
    // edge and its corners are the wash's plus both.
    final ringShape = segmented
        ? StadiumBorder(
            side: BorderSide(color: ring.color, width: ring.width),
          )
        : RoundedRectangleBorder(
            side: BorderSide(color: ring.color, width: ring.width),
            borderRadius: BorderRadius.circular(
              tokens.radius.md + ring.offset + ring.width,
            ),
          );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: lift),
      duration: duration,
      curve: short.curve,
      builder: (context, lifted, _) {
        final ink = Color.lerp(ambient, colors.text.secondary, lifted);
        final Widget content = segmented
            ? Padding(
                padding: EdgeInsets.symmetric(horizontal: space.s4 + space.s16),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(color: ink),
                ),
              )
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: space.s12),
                child: Row(
                  key: markKey,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: tokens.icons.row, color: ink),
                      SizedBox(width: space.s8),
                    ],
                    Text(label, style: TextStyle(color: ink)),
                  ],
                ),
              );
        return Listener(
          onPointerDown: (_) => onPressedChanged(true),
          onPointerUp: (_) => onPressedChanged(false),
          onPointerCancel: (_) => onPressedChanged(false),
          child: SizedBox(
            key: segmented ? markKey : null,
            width: segmented ? double.infinity : null,
            height: height,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(ring.width + ring.offset),
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: wash),
                      duration: duration,
                      curve: short.curve,
                      builder: (context, color, _) => DecoratedBox(
                        decoration: ShapeDecoration(
                          color: color,
                          shape: washShape,
                        ),
                      ),
                    ),
                  ),
                ),
                content,
                if (focusVisible)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(shape: ringShape),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The switch's thumb, or the strip's underline.
///
/// **It finds the tabs where they are on the frame it paints**, from each
/// cell's render box, rather than being told. That is what lets the springs
/// run in tab units: a scrolled strip, a resized window and a new text scale
/// are all already in the boxes this reads.
final class _MarkPainter extends CustomPainter {
  _MarkPainter({
    required this.shape,
    required this.keys,
    required this.stackKey,
    required this.position,
    required this.tokens,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _Shape shape;
  final List<GlobalKey> keys;
  final GlobalKey stackKey;
  final ({double start, double end}) Function() position;
  final AppTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final stack = stackKey.currentContext?.findRenderObject();
    if (stack is! RenderBox || !stack.hasSize) return;
    final rects = <Rect>[];
    for (final key in keys) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      rects.add(box.localToGlobal(Offset.zero, ancestor: stack) & box.size);
    }
    if (rects.isEmpty) return;

    final at = position();
    final left = _edge(rects, at.start, (rect) => rect.left);
    final right = _edge(rects, at.end, (rect) => rect.right);
    final colors = tokens.colors;

    switch (shape) {
      case _Shape.segmented:
        // The thumb is the cell inset by the same 4 the wash and the ring's
        // gutter are, so all three share one outline.
        final ring = colors.action.focusRing;
        final inset = ring.width + ring.offset;
        final cell = rects.first;
        final thumb = Rect.fromLTRB(
          left + inset,
          cell.top + inset,
          right - inset,
          cell.bottom - inset,
        );
        if (thumb.width <= 0 || thumb.height <= 0) return;
        final rrect = RRect.fromRectAndRadius(
          thumb,
          Radius.circular(thumb.shortestSide / 2),
        );
        canvas.drawRRect(rrect, Paint()..color = colors.surface.selected);
        // A 1px edge, inside, as `ShapeDecoration` would draw it.
        const edge = 1.0;
        canvas.drawRRect(
          rrect.deflate(edge / 2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = edge
            ..color = colors.surface.borderStrong,
        );
      case _Shape.strip:
        final weight = colors.action.focusRing.width;
        final corner = Radius.circular(tokens.radius.sm);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(left, size.height - weight, right, size.height),
            topLeft: corner,
            topRight: corner,
          ),
          Paint()..color = colors.action.primary.container,
        );
    }
  }

  /// One side of the mark at [at] tab units, between the tabs either side of
  /// it - and past the last one, by the same step, while a spring overshoots.
  static double _edge(List<Rect> rects, double at, double Function(Rect) side) {
    if (rects.length == 1) return side(rects.first);
    final i = at.floor().clamp(0, rects.length - 2);
    return lerpDouble(side(rects[i]), side(rects[i + 1]), at - i)!;
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => true;
}

final class _Repaint extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// One page of a `TabBarView` under [AppTabs], kept alive while another tab is
/// showing.
///
/// **So a tab is where it was left.** A half-made change to a setting
/// survives a look at the list beside it, and going back to the list does not
/// read it again. A page is still built the first time its tab is opened, not
/// on the way in.
final class AppKeptTab extends StatefulWidget {
  const AppKeptTab({super.key, required this.child});

  final Widget child;

  @override
  State<AppKeptTab> createState() => _AppKeptTabState();
}

final class _AppKeptTabState extends State<AppKeptTab>
    with AutomaticKeepAliveClientMixin<AppKeptTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
