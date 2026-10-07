/// The three full-page states - `EmptyState`, `LoadingState` and `ErrorState` -
/// and `ProvenanceLine`, which is not one of them and says why below.
///
/// `design.md` §5.1 gives them three rows — "prose paragraph", "bare
/// `CircularProgressIndicator`" and "'could not be read' prose" — and §7 gives
/// two of the three a written pattern. They live in one file because a screen
/// that has one of them has all three: a read either has not answered, answered
/// with nothing, or failed, and a caller choosing between them should not have
/// to find three imports to do it.
///
/// **`EmptyState`**: `design.md` §5.1's row for "prose paragraph", §7's *Empty*
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

import 'illustration.dart';
import 'spring.dart';
import 'status.dart';
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
    this.illustration,
    this.icon,
  }) : assert(
         illustration == null || icon == null,
         'One mark: an illustration or a glyph, not both.',
       );

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

  /// A file in `assets/illustrations/` to draw in place of the painted mark.
  ///
  /// **Additive, and null everywhere it is not named.** The painted
  /// [_EmptyMark] stays the default because it is the state this component
  /// shipped in and because it is the only one of the two that animates - an
  /// SVG has no draw-on. A screen opts in by naming a file, and what it gets
  /// is a drawing about *that* screen's emptiness rather than the same box
  /// twenty-one times.
  ///
  /// The file's own colours are not used; see `AppIllustration`.
  final String? illustration;

  /// A glyph to draw in a ring in place of the painted mark, for a list that
  /// is empty because nothing has happened yet rather than because a search
  /// found nothing.
  ///
  /// **New on 2026-10-04, for the WhatsApp receipts screen's sent tab**, where
  /// `file-search.svg` said *a record was looked for* and nothing was: the tab
  /// lists receipts as they go, and an empty one is a chat list nobody has
  /// written to yet. One glyph in a ring is how such a list sits.
  final IconData? icon;

  /// The mark's side, in logical pixels.
  ///
  /// Named rather than tokenised: `design.md` states no illustration size
  /// anywhere, and inventing `size.emptyMark` would be inventing a token, which
  /// `claude.md` forbids one rule before it forbids magic numbers. 96 is two of
  /// §9's 48 tap targets, which is the nearest thing to a derivation available.
  static const double markSize = 96;

  /// The side an [illustration] fits inside.
  ///
  /// Named on the same grounds as [markSize], and larger for the same reason
  /// that one is 96: a painted box outline reads at two tap targets, and a
  /// drawing with a scene in it does not. 168 is three and a half of §9's 48,
  /// which is the nearest derivation available and still leaves the title
  /// above the fold on the shortest phone this app supports.
  static const double illustrationSize = 168;

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
              if (illustration case final asset?)
                AppIllustration(asset: asset, size: illustrationSize)
              else if (icon case final glyph?)
                _GlyphRing(icon: glyph)
              else
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

/// [EmptyState.icon], in its ring: a card's surface and edge, round.
///
/// **Still, and decoration only.** It is the title under it that says the list
/// is empty; the glyph names what the list would hold, and a screen reader is
/// given the title rather than a description of a picture.
final class _GlyphRing extends StatelessWidget {
  const _GlyphRing({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: tokens.icons.emptyRing,
        height: tokens.icons.emptyRing,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface.raised,
          border: Border.all(color: colors.surface.cardEdge),
        ),
        child: Icon(
          icon,
          size: tokens.icons.empty,
          color: colors.text.tertiary,
        ),
      ),
    );
  }
}

/// What a screen shows while a read it has already started has not answered.
///
/// **§5.1's row is "bare `CircularProgressIndicator`" and the word doing the
/// work is *bare*.** A spinner alone says that something is happening and
/// nothing about what — which on this app matters more than it usually would,
/// because the four things it covers on the routing shell alone are checking a
/// sign-in, opening an account, opening a business and signing out, and only
/// one of them is worth waiting for if you meant one of the others. So the
/// message is **required**: a call site that cannot say what it is reading is a
/// call site that should not be drawing a full-page state.
///
/// **No asset, and that is §6.4's budget rather than an omission.** *"Animation
/// used to mask latency. If something is slow, fix the something."* is on that
/// section's banned list, and a bespoke loading illustration is exactly it. The
/// indicator is Material's, in the accent, at a size on §2.3's scale.
///
/// **The state matrix is one row.** A loading state has no `hover`, no `focus`,
/// no `pressed`, no `disabled`, no `error` and no `empty` — every one of those
/// belongs to whatever replaces it when the read answers. What varies is the
/// sentence, and the harness photographs it with one and with a long one.
final class LoadingState extends StatelessWidget {
  const LoadingState({super.key, required this.message});

  /// What is being read, in the shopkeeper's words. §8 rule 1, and §8 rule 2 —
  /// state what is true: *Opening the business*, not *Please wait*.
  final String message;

  /// The indicator's side, in logical pixels.
  ///
  /// **`space.32`, read off §2.3's scale rather than invented.** That section
  /// is "Spacing, size, radius" and its permitted values are the sizes this
  /// system has; 32 is the one that reads at arm's length without becoming the
  /// subject of the screen. §2.1's own 16px spinner is the *button's* row and
  /// is half of what a page needs.
  static double get indicatorSize => AppSpacing.scale.s32;

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
              SizedBox(
                width: tokens.spacing.s32,
                height: tokens.spacing.s32,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    tokens.colors.action.primary.container,
                  ),
                ),
              ),
              SizedBox(height: tokens.spacing.s16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: tokens.density
                    .body(tokens.typography)
                    .copyWith(color: tokens.colors.text.secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a screen shows when a read failed.
///
/// **§7 writes this pattern out and this component is the four parts it
/// names**: *"`status.problem` badge, the record's identifier in `mono`, a
/// plain statement of what could not be read, and — this matters — what is
/// still true despite it. '2 sale lines could not be read, so they moved no
/// stock' is exactly right and should be the template."*
///
/// **Not an [EmptyState] with a red mark.** §7 gives the two separate patterns
/// because they are separate facts: an empty list was read correctly and a
/// failed read was not, and the difference decides whether a person should
/// trust the rest of the screen. That is also why this one carries a
/// [StatusBadge] where the empty state carries an illustration — the badge is
/// §9's requirement that a status is never hue alone, and it puts a *word* on
/// the failure.
///
/// **No animated mark at all, which is §6.4's banned list quoting itself**:
/// *"Animated illustrations on error and failed-to-read states. A person
/// looking at '2 sale lines could not be read' needs information, not a sad
/// mascot."*
///
/// **The state matrix is two rows**: with actions and without. `hover`,
/// `focus-visible` and `pressed` arrive with whatever [actions] holds;
/// `loading`, `disabled`, `read-only` and `empty` have no meaning for a
/// statement of fact.
final class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.badgeLabel,
    required this.statement,
    this.identifier,
    this.detail,
    this.stillTrue,
    this.status = AppStatus.problem,
    this.actions = const <Widget>[],
  });

  /// The word on the badge. §9: a status is a glyph and a word, never a colour.
  ///
  /// Required rather than defaulted, because every default available here is a
  /// system word — *Error*, *Failed*, *Problem* — and §8 rule 1 asks for the
  /// shopkeeper's. *Not opened*, *Unavailable*, *Not read*.
  final String badgeLabel;

  /// §7's "plain statement of what could not be read".
  final String statement;

  /// §7's "the record's identifier in `mono`". Optional: a failure that is not
  /// about one record — a business that would not open — has no identifier to
  /// print, and printing a UID there would be §8 rule 1's own worked example of
  /// what not to do.
  final String? identifier;

  /// One more sentence about *this* failure, where the statement is the general
  /// case and something specific is known: *This account is disabled.*
  ///
  /// Separate from [statement] rather than concatenated into it, so a caller
  /// that maps an error to a safe sentence has somewhere to put the result
  /// without rewriting the heading.
  final String? detail;

  /// §7's "what is still true despite it", and §8 rule 6 in the same words.
  /// The half of this pattern that stops a failure reading as a catastrophe.
  final String? stillTrue;

  /// Defaults to §2.1's `problem`, which is what §7 names.
  ///
  /// Overridable because not every dead end is a fault: a build with no
  /// platform console reaches one, nothing went wrong, and painting it
  /// `problem` would tell a person to go looking for a failure that does not
  /// exist.
  final AppStatus status;

  /// The ways out. Laid out here rather than by the caller — a `Wrap` at
  /// `space.12`, matching `ConfirmDialog`'s actions — because two 48-high pills
  /// do not fit a phone side by side and every call site that built its own
  /// row had to rediscover that.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final body = tokens.density.body(tokens.typography);
    return Semantics(
      container: true,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              StatusBadge(status: status, label: badgeLabel),
              if (identifier case final reference?) ...<Widget>[
                SizedBox(height: tokens.spacing.s12),
                Text(
                  reference,
                  textAlign: TextAlign.center,
                  style: tokens.typography.mono.copyWith(
                    color: tokens.colors.text.secondary,
                  ),
                ),
              ],
              SizedBox(height: tokens.spacing.s16),
              Text(
                statement,
                textAlign: TextAlign.center,
                style: tokens.typography.titleMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
              if (detail case final sentence?) ...<Widget>[
                SizedBox(height: tokens.spacing.s8),
                Text(
                  sentence,
                  textAlign: TextAlign.center,
                  style: body.copyWith(color: tokens.colors.text.secondary),
                ),
              ],
              if (stillTrue case final reassurance?) ...<Widget>[
                SizedBox(height: tokens.spacing.s12),
                Text(
                  reassurance,
                  textAlign: TextAlign.center,
                  style: tokens.typography.bodyMedium.copyWith(
                    color: tokens.colors.text.tertiary,
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...<Widget>[
                SizedBox(height: tokens.spacing.s20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: tokens.spacing.s12,
                  runSpacing: tokens.spacing.s8,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Who recorded a thing, and when. §5.2's provenance row.
///
/// **The last of §5.2's rows that nothing implemented.** Its specification is
/// one line long - `caption`, `text.tertiary`, the instant first and then the
/// actor - and until 2026-08-22 that line was written out **seven times** across
/// five files: twice inside `RecordList` and once each in the daily metrics,
/// reconciliation run, reconciliation status and reconciliation anomalies panels.
/// Four of those five carried a comment naming the section they were
/// implementing by hand, which is the clearest signal available that an
/// abstraction is missing rather than declined.
///
/// **It could not be fixed with a scan, which is why it is a widget.** The read-only
/// notices next door were pinned by one - every `-read-only` key must sit on an
/// `info` `Callout` - because the rendering *is* the identifying feature there.
/// Here it is not: `caption` with `text.tertiary` appears **29 times** in `lib/`
/// and only seven are provenance. The other 22 are stat details, cart notes,
/// helper lines and figure captions, all correctly that pair and none of them
/// this. A scan over the style would have flagged all 29; the concept needed a
/// name instead.
///
/// **The drift it prevents had already happened once.**
/// `stock_adjustment_panel.dart` folds a provenance string into a
/// `Callout.message` after a newline, so it renders at the callout's body style
/// and colour rather than at `caption` / `text.tertiary` - the same sentence
/// about the same kind of fact, two type roles from where §5.2 puts it, and no
/// test or picture able to tell the two apart. That site is left alone: the
/// provenance is genuinely part of that message rather than a row under it, and
/// changing it would be recomposing a `Callout`, not naming a style.
///
/// **It takes a string and nothing else.** The label's *format* stays with the
/// callers that already own it - `stockMovementRecordedLabel`,
/// `reconciliationDifferenceProvenance`, and the four others - for the reason
/// `ShiftBanner` takes a status rather than a shift: a component in `lib/ui/`
/// that decided how to word "recorded at, by" would be deciding product meaning.
///
/// **Density does not change it, and that is a decision rather than an
/// oversight.** §5.2 states `caption` flat, and `caption` is one of the roles
/// `AppDensity` does not swap - only the body role moves. So provenance is 12
/// beside a 16 body at comfortable and 12 beside a 14 body at compact, and the
/// pair of captures in the harness exists to show exactly that: the line holding
/// still while its neighbours move.
///
/// **A plain `Text`, with no `Semantics` wrapper.** `EmptyState` has one because
/// it is a whole page speaking as one thing; this is a line inside a record, and
/// giving it a container of its own would announce it separately from the record
/// it belongs to - which is the opposite of what a provenance line is for.
final class ProvenanceLine extends StatelessWidget {
  const ProvenanceLine(this.label, {super.key});

  /// The line, in the caller's words. *Recorded 2026-08-01 09:00 UTC by Amina.*
  final String label;

  /// The style this draws, so a caller that has to *measure* provenance measures
  /// what is actually painted.
  ///
  /// **Exposed for one real caller and it is not a test.** `RecordList`'s
  /// narrow-loss column allocator asks how wide each of a record's lines wants
  /// to be, and provenance is one of them - so before this existed, the
  /// allocator named `typography.caption` and the renderer named
  /// `typography.caption` and nothing tied the two together. A repoint of one
  /// would have allocated the table's columns against a style nothing paints.
  ///
  /// Same reason `RecordList.formFor` and `PageHeader.showsDisplayTitle` are
  /// statics: a question a widget answers is worth more when something else can
  /// ask it the same way.
  static TextStyle styleOf(AppTokens tokens) =>
      tokens.typography.caption.copyWith(color: tokens.colors.text.tertiary);

  @override
  Widget build(BuildContext context) =>
      Text(label, style: styleOf(AppTokens.componentOf(context)));
}

/// §6.4's asset 6: an open box that draws itself once.
final class _EmptyMark extends StatefulWidget {
  const _EmptyMark();

  @override
  State<_EmptyMark> createState() => _EmptyMarkState();
}

class _EmptyMarkState extends State<_EmptyMark> with TickerProviderStateMixin {
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
