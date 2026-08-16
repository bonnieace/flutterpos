/// `RollingNumber`: `design.md` §5.1's row for "static `Text` on totals and
/// counts", and the last component §11 step 7 was waiting on.
///
/// **§6.2 gives it two rows and this file honours one of them.** *"Quantity
/// change — digit rolls vertically, tabular so width is fixed, `spring.snappy`"*
/// and *"Total recalculates — digits roll; **only changed digits move**,
/// `spring.smooth`, no haptic"*. The second is what this app has: the two
/// totals on the till. **The first has nowhere to go and that is a finding
/// rather than an omission** — the only quantity a person changes is the one
/// inside `QuantityStepper`, which is an editable `AppTextField` they type
/// into, and rolling the glyphs under a caret is not a thing that can be done.
/// The row stays unbuilt until a quantity is displayed somewhere it is not
/// being typed.
///
/// **§6.3 binds this component absolutely, and the shape of the code is the
/// proof.** *"No animation may sit between an input and its record. The sale is
/// written first; the animation plays over the already-committed state."* So:
/// the widget is handed a **formatted string that is already correct**, it never
/// formats anything, it never delays anything, and its semantics carry the new
/// value from the first frame of the roll rather than from the last. A
/// `RollingNumber` that showed the old total for 300ms would be a defect in the
/// money, not a polish item.
///
/// **It takes a string, not a number.** §8 rule 8 says money always carries a
/// currency code, and formatting money is the caller's job everywhere else in
/// this app; a component that took a `double` would have to decide separators,
/// minor units and the code, and would be the one place they were decided
/// twice.
///
/// **Comparison is per character and right-aligned.** `KES 135.00` → `KES
/// 185.00` moves one glyph. That is the whole of "only changed digits move",
/// and right-alignment is what makes it hold when the string grows: `KES 99.00`
/// → `KES 100.00` is a different length, every position after the space
/// changes, and everything rolls — which is honest, because everything did.
///
/// **The style must be tabular and this asserts it.** With proportional figures
/// a `1` is narrower than a `0`, so every position shifts under the animation
/// and the eye reads every digit as having changed. §2.2's two `numeric` roles
/// are tabular for exactly this reason and the assertion names them.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'spring.dart';
import 'tokens.dart';

/// A figure that rolls its changed glyphs when it is given a new one.
final class RollingNumber extends StatefulWidget {
  const RollingNumber({
    super.key,
    required this.value,
    required this.style,
    this.textKey,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.spring = RollingNumberSpring.smooth,
  });

  /// The figure, already formatted and already correct. See §6.3 above.
  final String value;

  /// One of §2.2's two `numeric` roles. Asserted tabular.
  final TextStyle style;

  /// A key on the `Text` this draws when it is **at rest**.
  ///
  /// **Not the same as [key], and the difference is what keeps a screen's tests
  /// addressing the screen.** Four surfaces already find their figure by key
  /// and read `Text.data` off it; putting the key on this widget instead would
  /// have made every one of them a `RollingNumber` read, which is churn in the
  /// suite for no assertion gained. At rest this component **is** a `Text`, so
  /// the key lands where it always did.
  final Key? textKey;

  final int maxLines;
  final TextOverflow overflow;

  /// Which of §2.4's springs drives the roll. Defaults to §6.2's row for
  /// "total recalculates".
  final RollingNumberSpring spring;

  @override
  State<RollingNumber> createState() => _RollingNumberState();
}

/// The two §6.2 rows that name a spring for a rolling figure.
enum RollingNumberSpring {
  /// §6.2's "Total recalculates".
  smooth,

  /// §6.2's "Quantity change". No reader yet — see the library note.
  snappy;

  SpringDescription of(AppMotion motion) => switch (this) {
    RollingNumberSpring.smooth => motion.smooth,
    RollingNumberSpring.snappy => motion.snappy,
  };
}

class _RollingNumberState extends State<RollingNumber>
    with SingleTickerProviderStateMixin {
  /// Every string this widget has been given that the drive has not yet
  /// reached, oldest first. `_stages[j]` is generation `_base + j`.
  ///
  /// **It is pruned to one entry every time the spring settles**, which is what
  /// keeps a till that rings four hundred sales a shift from holding four
  /// hundred strings. The drive's own value keeps counting up; only the list
  /// rebases.
  late List<String> _stages = <String>[widget.value];
  int _base = 0;

  SpringDrive? _drive;

  int get _latest => _base + _stages.length - 1;

  bool get _reduced => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tokens = AppTokens.componentOf(context);
    _drive ??= SpringDrive(
      vsync: this,
      spring: widget.spring.of(tokens.motion),
      value: _base.toDouble(),
    )..animation.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(covariant RollingNumber old) {
    super.didUpdateWidget(old);
    if (widget.value == _stages.last) return;
    // §2.4's reduced-motion clause: "springs collapse to instant". The figure
    // is simply the new figure, with no intermediate frame at all.
    if (_reduced) {
      setState(() {
        _stages = <String>[widget.value];
        _base = _latest + 1;
      });
      _drive!.animateTo(_base.toDouble(), immediately: true);
      return;
    }
    setState(() => _stages.add(widget.value));
    // **Retargeted, never restarted.** A second change arriving mid-roll hands
    // the live position and the live velocity to a new simulation that carries
    // on through the intervening generation, so the glyphs keep moving rather
    // than snapping back to the start. `claude.md`'s motion rule, and the whole
    // reason `SpringDrive` has no `forward()`.
    _drive!.animateTo(_latest.toDouble());
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.forward) return;
    if (_stages.length == 1) return;
    // Settled: everything before the last generation can never be drawn again.
    setState(() {
      _base = _latest;
      _stages = <String>[_stages.last];
    });
  }

  @override
  void dispose() {
    _drive?.animation.removeStatusListener(_onStatus);
    _drive?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.style.fontFeatures?.contains(const FontFeature.tabularFigures()) ??
          false,
      'RollingNumber needs a tabular style, or every position shifts under the '
      'roll and the eye reads every digit as changed. design.md §2.2 gives '
      'numeric.hero and numeric.body tabular figures for this reason.',
    );
    final drive = _drive!;
    return AnimatedBuilder(
      animation: drive.animation,
      builder: (context, _) {
        final roll = _rollAt(drive.value);
        // **The committed figure is in the tree on every frame, painted or
        // not, and that is §6.3 expressed as a widget rather than as a
        // comment.** It is what [RollingNumber.textKey] addresses, what a
        // screen reader is told, and what a screen's own tests find - so the
        // roll is invisible to everything except the eye, and no call site's
        // assertions had to learn that its figure had become a component.
        //
        // **This is not how it was built first.** The first version returned
        // the roll *instead of* the text, and six checkout tests went red at
        // once: they read `checkout-total` sixty milliseconds after a tap, and
        // `spring.smooth` is still moving then. The tests were right and the
        // component was wrong - a total that cannot be read mid-roll is a
        // total that is briefly not stated.
        return Stack(
          children: <Widget>[
            Opacity(
              opacity: roll == null ? 1 : 0,
              // **`alwaysIncludeSemantics`, and it is not a formality.**
              // `Opacity` drops its subtree's semantics at zero by default, so
              // without this the one thing §6.3 asks for - that the figure is
              // correct from the first frame *including* for someone who is
              // not looking at it - would hold for the eye and fail for a
              // screen reader, which is the reader the rule is really about.
              alwaysIncludeSemantics: true,
              child: _text(_stages.last, key: widget.textKey),
            ),
            if (roll != null)
              // **Clipped and allowed to overflow, and this is a finding
              // rather than defensive plumbing.** The overlay is laid out in
              // the *committed* figure's box, and a roll between two figures of
              // different length is wider than either: `KES 120.50` → `KES
              // 0.00` pads to ten positions over an eight-character box and
              // the `Row` overflowed by exactly two glyphs, 57 pixels, in five
              // checkout tests at once. Left-aligned, so the figure's left edge
              // stays where the layout around it put it, and the positions that
              // are rolling away spill off the end rather than shifting
              // everything under them.
              Positioned.fill(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: double.infinity,
                    child: ExcludeSemantics(child: roll),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The transition to paint over the committed figure, or null when there is
  /// none because the spring is at rest.
  _Roll? _rollAt(double value) {
    if (_stages.length == 1) return null;
    final t = value.clamp(_base.toDouble(), _latest.toDouble());
    final index = math.min(t.floor(), _latest - 1);
    final fraction = (t - index).clamp(0.0, 1.0);
    if (fraction >= 1) return null;
    return _Roll(
      from: _stages[index - _base],
      to: _stages[index - _base + 1],
      fraction: fraction,
      style: widget.style,
    );
  }

  Widget _text(String value, {Key? key}) => Text(
    value,
    key: key,
    maxLines: widget.maxLines,
    overflow: widget.overflow,
    style: widget.style,
  );
}

/// Which way the glyphs travel: **the direction the figure moved**.
///
/// A total going up rolls up, one going down rolls down, and a person watching
/// a cart learns which happened without reading the number. Where neither
/// string parses as a figure — a currency code changed, say — it rolls up,
/// because there is nothing to be wrong about.
///
/// Public because it is the one rule in this file a picture cannot show: §10
/// says the harness cannot see motion, so the direction has to be asserted
/// against the function rather than against a rendering.
abstract final class RollingNumberDirection {
  /// `1` for upward, `-1` for downward.
  static double of(String from, String to) {
    final before = _figure(from);
    final after = _figure(to);
    if (before == null || after == null) return 1;
    return after >= before ? 1 : -1;
  }

  static double? _figure(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(digits);
  }
}

/// One transition, drawn as a row of per-position cells.
final class _Roll extends StatelessWidget {
  const _Roll({
    required this.from,
    required this.to,
    required this.fraction,
    required this.style,
  });

  final String from;
  final String to;
  final double fraction;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // Right-aligned comparison: the pair is padded on the **left** so the minor
    // units line up, which is where a figure's stable end is.
    final width = math.max(from.length, to.length);
    final before = from.padLeft(width);
    final after = to.padLeft(width);
    final travel = RollingNumberDirection.of(from, to);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        for (var i = 0; i < width; i++)
          if (before[i] == after[i])
            // Unchanged, and therefore still. §6.2: "only changed digits move".
            Text(after[i], style: style)
          else
            _Glyph(
              from: before[i],
              to: after[i],
              fraction: fraction,
              direction: travel,
              style: style,
            ),
      ],
    );
  }
}

/// One position that changed, sliding its old glyph out as the new one arrives.
final class _Glyph extends StatelessWidget {
  const _Glyph({
    required this.from,
    required this.to,
    required this.fraction,
    required this.direction,
    required this.style,
  });

  final String from;
  final String to;
  final double fraction;
  final double direction;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      children: <Widget>[
        // The incoming glyph sizes the cell. Both are digits in a tabular face,
        // so the box does not change width when they swap - which is §6.2's
        // "tabular so width is fixed", enforced by the assertion in the state.
        FractionalTranslation(
          translation: Offset(0, (1 - fraction) * direction),
          child: Text(to, style: style),
        ),
        Positioned.fill(
          child: FractionalTranslation(
            translation: Offset(0, -fraction * direction),
            child: Text(from, style: style),
          ),
        ),
      ],
    ),
  );
}
