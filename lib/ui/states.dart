/// `EmptyState`: `design.md` §5.1's row for "prose paragraph", §7's *Empty*
/// pattern, and §6.4's asset **6** — drawn here rather than sourced.
///
/// **§7 specifies this pattern and no component carried it.** *"Icon, one-line
/// statement of what would be here, one sentence on how to create one, and a
/// `primary` action if the person can. Not a paragraph."* Six screens answer an
/// empty read with a bare sentence — `No products found.`, `No staff memberships
/// found.` — which is the prose §5.1 names, and none of them offers the action
/// that would end the emptiness.
///
/// **The mark is a `CustomPainter`, which is §6.4's original argument arriving
/// late.** That section's default position was that six of the eight approved
/// assets are state indicators Flutter draws natively, "and the reason that
/// actually matters — an asset authored in an external tool bakes its colours
/// in. Every hex in §2.1 is a role that can change." v0.7 overrode that and made
/// the eight Lottie; the file sourced for *this* one came back as seven beiges
/// and oranges on a near-black green page, and the product owner's call on
/// 2026-08-16 was to draw it instead. So asset 6 is native and the other seven
/// stay sourced — the split is by what the asset *is*, and this one is a box
/// outline that nobody needs to be charmed by.
///
/// **The numbers behind that call, because they are the argument.** The
/// candidate that was in the repository — `images/empty.gif` — is 244KB against
/// §6.4's 120KB budget for *every* external asset combined and its 64KB
/// per-asset ceiling; 150 × 150 of raster, which is blurry at a phone's 2×; 252
/// colours, so it cannot be tinted at all; and 77 frames that loop forever,
/// where §6.4's budget line reads "idle loops on an operational screen: **0**"
/// and an empty state is a screen somebody is reading.
///
/// **It draws once and stops**, for that same budget line. §6.2 has no row for
/// an empty state, so the motion is the least this can be and still be motion:
/// the box's outline draws on over `motion.medium`, the lid tips on
/// `spring.gentle`, and then nothing moves until the widget is rebuilt into
/// existence again. Under `MediaQuery.disableAnimations` it renders its final
/// frame, which is §2.4's rule for every animated asset.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'spring.dart';
import 'tokens.dart';

/// What a screen shows when a read succeeded and there was nothing in it.
///
/// **Not an error and not a failure**, which is the distinction §7 draws by
/// giving them separate patterns: a list that is empty has been read correctly.
/// That is why nothing here is `status.problem` and why the mark is the
/// page's own quiet colours rather than a warning.
final class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.hint,
    this.action,
  });

  /// §7's "one-line statement of what would be here". A noun phrase about the
  /// records, not an apology: *No products yet*, not *Sorry, nothing found*.
  final String title;

  /// §7's "one sentence on how to create one".
  ///
  /// Optional, because a screen a person cannot add to has no honest sentence
  /// to put here — a cashier looking at an empty catalog cannot stock it, and
  /// telling them how would be telling the wrong person.
  final String? hint;

  /// §7's "a `primary` action **if the person can**".
  ///
  /// A `Widget` rather than an `AppButton`, for the reason `Callout` and
  /// `PageHeader` both give: this component decides where an action sits and
  /// nothing at all about what it does. Null where the person's role does not
  /// allow it, which is the caller's judgement and never this widget's.
  final Widget? action;

  /// The mark's side, in logical pixels.
  ///
  /// Named rather than tokenised: `design.md` states no illustration size
  /// anywhere, and inventing `size.emptyMark` would be inventing a token, which
  /// `claude.md` forbids one rule before it forbids magic numbers. 96 is two of
  /// §9's 48 tap targets, which is the nearest thing to a derivation available.
  static const double markSize = 96;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Semantics(
      container: true,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const _EmptyMark(),
              SizedBox(height: tokens.spacing.s16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: tokens.typography.titleMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
              if (hint case final sentence?) ...<Widget>[
                SizedBox(height: tokens.spacing.s8),
                Text(
                  sentence,
                  textAlign: TextAlign.center,
                  style: tokens.density
                      .body(tokens.typography)
                      .copyWith(color: tokens.colors.text.secondary),
                ),
              ],
              if (action case final control?) ...<Widget>[
                SizedBox(height: tokens.spacing.s20),
                control,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// §6.4's asset 6: an open box that draws itself once.
final class _EmptyMark extends StatefulWidget {
  const _EmptyMark();

  @override
  State<_EmptyMark> createState() => _EmptyMarkState();
}

class _EmptyMarkState extends State<_EmptyMark>
    with TickerProviderStateMixin {
  /// The outline's draw-on. A stroke appearing is not spatial, so §2.4 gives it
  /// a duration and a curve rather than a spring.
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: _drawDuration,
  );

  /// The lid tipping open, which *is* spatial, so §2.4 gives it a spring.
  /// `spring.gentle` is the row for "large surfaces, hero figures", and at this
  /// size the lid is the largest thing that moves.
  SpringDrive? _lid;

  static const Duration _drawDuration = Duration(milliseconds: 240);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tokens = AppTokens.componentOf(context);
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _lid ??= SpringDrive(vsync: this, spring: tokens.motion.gentle);
    if (reduced) {
      // §2.4: "animated assets render their final frame as a static image".
      _draw.value = 1;
      _lid!.animateTo(1, immediately: true);
    } else if (!_draw.isAnimating && _draw.value == 0) {
      _draw.forward();
      _lid!.animateTo(1);
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    _lid?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final lid = _lid!;
    return SizedBox.square(
      dimension: EmptyState.markSize,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_draw, lid.animation]),
        builder: (context, _) => CustomPaint(
          painter: _BoxPainter(
            drawn: Curves.easeInOutCubic.transform(_draw.value),
            lid: lid.value.clamp(0.0, 1.0),
            // **The whole point of drawing this rather than sourcing it.** Both
            // colours are read from the theme every build, so a palette change
            // moves the asset with it and no file has to be re-exported.
            stroke: tokens.colors.text.tertiary,
            accent: tokens.colors.action.primary.container,
          ),
        ),
      ),
    );
  }
}

/// An open carton, in two strokes and a tipping lid.
final class _BoxPainter extends CustomPainter {
  const _BoxPainter({
    required this.drawn,
    required this.lid,
    required this.stroke,
    required this.accent,
  });

  /// How much of the outline exists, 0 to 1.
  final double drawn;

  /// How far the lid has tipped, 0 to 1.
  final double lid;

  final Color stroke;
  final Color accent;

  /// How far a flap tips when the box is fully open.
  ///
  /// About 22°. Wide enough to read as open at 96 logical pixels, narrow enough
  /// that the two flaps stay inside the mark's square — the first attempt used
  /// 36° and the flaps left the box behind them.
  static const double _openAngle = math.pi / 8;

  @override
  void paint(Canvas canvas, Size size) {
    if (drawn <= 0) return;
    final unit = size.width / 100;
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * unit
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = stroke;

    // The carton body: a trapezium, wider at the top, so it reads as a box seen
    // slightly from above rather than as a square.
    final body = Path()
      ..moveTo(18 * unit, 44 * unit)
      ..lineTo(82 * unit, 44 * unit)
      ..lineTo(74 * unit, 88 * unit)
      ..lineTo(26 * unit, 88 * unit)
      ..close();
    canvas.drawPath(_partial(body, drawn), pen);

    // The two lid flaps, tipping outwards.
    //
    // **They hinge on the box's own top corners, which is the whole of what
    // makes this read as a carton.** Pivoting both about the centre of the top
    // edge - the first thing this painter did - splays them from one point and
    // draws a crown: the first capture of it looked like a tent with a dot
    // under it. A flap hinges where the cardboard actually folds.
    final angle = _openAngle * lid;
    for (final side in <double>[-1, 1]) {
      canvas.save();
      // The left flap hinges at the left corner and reaches inward; the right
      // one mirrors it. `side` is -1 for the left.
      canvas.translate(side < 0 ? 18 * unit : 82 * unit, 44 * unit);
      canvas.rotate(-angle * side);
      final reach = 32 * unit * -side;
      final flap = Path()
        ..moveTo(0, 0)
        ..lineTo(reach, 0)
        ..lineTo(reach * 0.86, -12 * unit)
        ..lineTo(0, -12 * unit)
        ..close();
      canvas.drawPath(_partial(flap, drawn), pen);
      canvas.restore();
    }

    // One accent mark inside the box, at the end of the draw-on: the thing that
    // says *this is empty on purpose* rather than *this is still loading*. It
    // is the only saturated pixel in the mark and it appears last.
    if (drawn >= 1) {
      canvas.drawCircle(
        Offset(50 * unit, 68 * unit),
        3 * unit,
        Paint()..color = accent,
      );
    }
  }

  /// The first [fraction] of [path], so an outline can appear stroke by stroke.
  Path _partial(Path path, double fraction) {
    if (fraction >= 1) return path;
    final drawnPath = Path();
    for (final metric in path.computeMetrics()) {
      drawnPath.addPath(
        metric.extractPath(0, metric.length * fraction),
        Offset.zero,
      );
    }
    return drawnPath;
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.drawn != drawn ||
      old.lid != lid ||
      old.stroke != stroke ||
      old.accent != accent;
}
