/// The shape of content that has not arrived, for reads a person is waiting on.
///
/// **A skeleton is for the data and never for the page.**
/// `docs/stitch/OPEN_QUESTIONS.md` decision 35, 2026-08-27: buttons, labels,
/// field frames and headings - anything that does not change when the read
/// returns - render for real and immediately, and only the regions the read
/// actually fills are drawn as blocks. What that buys is not tidiness. A person
/// looking at a screen where everything shimmers knows nothing about it and is
/// waiting for all of it; a person looking at a real date picker over three
/// shimmering rows knows exactly what the screen is, can start using the half
/// that works, and is waiting for one thing.
///
/// **It replaces a spinner rather than joining it.** `LoadingState` stays, and
/// stays correct, for a read that genuinely needs a server: there is no honest
/// shape to draw for an answer the device cannot produce. This is for the reads
/// that resolve locally or from cache, where the shape *is* known.
///
/// **Nothing is drawn for the first `motion.skeletonDelay`.** The till's catalog
/// comes from a Hive box and normally resolves in a frame or two; a skeleton
/// that appears and is torn down again is the jitter it was added to remove.
/// [SkeletonBlock] holds its space transparently until the threshold passes, so
/// a warm read shows its content directly and the layout never jumps either way.
///
/// **Under `MediaQuery.disableAnimations` there is no sweep at all** - the
/// blocks render flat. That is §2.4's rule for every animated thing in this app,
/// the same branch `states.dart`'s empty mark takes, and it is also what keeps
/// `pumpAndSettle` working: a loop that never ends is a test that never
/// finishes.
///
/// **One ticker per group, not one per block.** A forty-tile grid with forty
/// controllers is how a cheap phone drops frames while appearing to be idle.
/// [SkeletonGroup] owns the only [AnimationController] and every block below it
/// reads that one.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'fields.dart';
import 'record_list.dart';
import 'tokens.dart';

/// The sweep and the visibility, published to every block below.
///
/// A plain [InheritedWidget] rather than an [InheritedNotifier], because the two
/// things it carries change on completely different clocks: [visible] flips
/// once, through `setState`, and wants a subtree rebuild; [animation] ticks
/// sixty times a second and must never rebuild anything but the blocks' own
/// painting, which is why each block listens to it through an [AnimatedBuilder]
/// of its own.
final class SkeletonSweep extends InheritedWidget {
  const SkeletonSweep({
    super.key,
    required this.animation,
    required this.visible,
    required this.animated,
    required super.child,
  });

  /// 0 to 1, one full pass of the highlight. Safe to read at any time; it simply
  /// does not move when [animated] is false.
  final Animation<double> animation;

  /// Whether `motion.skeletonDelay` has passed. Before it, blocks hold their
  /// space and paint nothing.
  final bool visible;

  /// False under reduced motion, in which case blocks paint flat.
  final bool animated;

  @override
  bool updateShouldNotify(SkeletonSweep old) =>
      old.visible != visible ||
      old.animated != animated ||
      old.animation != animation;
}

/// Owns one sweep for a whole loading region, and announces it.
///
/// **[semanticLabel] is required, and that is rule 6 rather than politeness.**
/// A shimmer says *this is loading* with movement and colour and nothing else,
/// which is precisely the signal §9 forbids leaving to colour alone. A person
/// using a screen reader gets one sentence for the region - *Loading the
/// products.* - and the blocks inside it are excluded from semantics entirely,
/// because forty announcements of "placeholder" is worse than none.
final class SkeletonGroup extends StatefulWidget {
  const SkeletonGroup({
    super.key,
    required this.semanticLabel,
    required this.child,
  });

  /// What is being waited for, in the shopkeeper's words. Same rule as
  /// `LoadingState.message`: a call site that cannot say what it is reading
  /// should not be drawing a loading state.
  final String semanticLabel;

  final Widget child;

  /// The sweep in scope, or null where there is no group above.
  ///
  /// Null rather than a throw, so a [SkeletonBlock] that ends up outside a group
  /// paints flat instead of crashing a screen. A dull placeholder is a cosmetic
  /// defect; an exception during a loading state takes the screen out.
  static SkeletonSweep? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SkeletonSweep>();

  @override
  State<SkeletonGroup> createState() => _SkeletonGroupState();
}

class _SkeletonGroupState extends State<SkeletonGroup>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Timer? _reveal;
  bool _visible = false;

  /// Whether the sweep may run at all. Decided in [didChangeDependencies]
  /// because it reads `MediaQuery`.
  bool _animated = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tokens = AppTokens.componentOf(context);
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _animated = !reduced;

    final controller =
        _controller ??= AnimationController(
          vsync: this,
          duration: tokens.motion.skeletonSweep.duration,
        );

    // The threshold is not animation, so reduced motion does not shorten it: a
    // person who has turned animation off still should not see a placeholder
    // flash for a read that had already finished.
    _reveal ??= Timer(tokens.motion.skeletonDelay.duration, () {
      if (!mounted) return;
      setState(() => _visible = true);
      if (_animated) controller.repeat();
    });

    // Reduced motion can be switched on while a slow read is still in flight,
    // and a controller left repeating would keep the tree from ever settling.
    if (!_animated && controller.isAnimating) {
      controller.stop();
    } else if (_animated && _visible && !controller.isAnimating) {
      controller.repeat();
    }
  }

  @override
  void dispose() {
    // A pending timer outlives the widget and fires into a disposed state; a
    // pending timer at the end of a widget test fails it outright.
    _reveal?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: widget.semanticLabel,
    child: SkeletonSweep(
      animation: _controller!,
      visible: _visible,
      animated: _animated,
      child: ExcludeSemantics(child: widget.child),
    ),
  );
}

/// Which surface a placeholder is being drawn on top of.
///
/// **Two tiers, because this app draws depth as a surface step and a block has
/// to be a step away from whatever is behind it.** A placeholder painted the
/// same colour as its background is invisible, and the first structured tile
/// skeleton was exactly that: `raised` lines inside a `raised` card, which
/// rendered as an empty card.
enum SkeletonTone {
  /// On the page itself. The block is a card, one step up from the ground.
  onPage,

  /// Inside a card or a row that is already `surface.raised` - so the block
  /// steps up again rather than matching what it sits on.
  onRaised,
}

/// One rectangle standing in for a value that has not arrived.
///
/// **It is given a size rather than deriving one**, because the whole point is
/// that the space it occupies is the space its content will occupy: a block
/// measured differently from the thing it replaces reintroduces the layout jump
/// it exists to remove. The call site knows the row height, the tile extent and
/// the column width; this does not.
final class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width,
    required this.height,
    this.radius,
    this.tone = SkeletonTone.onPage,
  });

  /// Null means "as wide as the parent allows", which is what a block inside a
  /// column or a grid cell wants.
  final double? width;

  final double height;

  /// Defaults to `radius.lg`.
  ///
  /// **Rounder than the `radius.md` a real card takes, at the product owner's
  /// direction of 2026-08-27, and the mismatch is deliberate.** A placeholder
  /// is not pretending to be a card; it is standing where one will be, and a
  /// softer corner reads as *unresolved* rather than as a card that came out
  /// wrong. The corner is also the one property of a block that can differ from
  /// its content without costing anything - a radius moves no layout, so
  /// nothing shifts when the real card replaces it.
  ///
  /// A call site that genuinely needs the content's own corner passes it: the
  /// till's placeholder tile draws its real card frame at `radius.md`, because
  /// that frame *is* the tile's rather than a stand-in for it.
  final double? radius;

  /// What this block is painted on top of. See [SkeletonTone].
  final SkeletonTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final sweep = SkeletonGroup.maybeOf(context);
    final corner = BorderRadius.circular(radius ?? tokens.radius.lg);
    // **Each tone is one step up from what it sits on, never level with it.**
    // This app draws depth as a surface step rather than a shadow, and the steps
    // run sunken -> base -> raised -> borderSubtle -> borderStrong. On the page,
    // a block is `raised`: the tier a card is painted at, so a placeholder for a
    // card is the colour of a card. The first version used `sunken`, which is
    // *below* the page, and the capture showed the result - a grid of slightly
    // darker gaps reading as holes in the screen.
    final surface = tokens.colors.surface;
    final (base, highlight) = switch (tone) {
      SkeletonTone.onPage => (surface.raised, surface.borderSubtle),
      SkeletonTone.onRaised => (surface.borderSubtle, surface.borderStrong),
    };

    // Before the threshold the block holds its space and paints nothing.
    // Holding the space rather than collapsing is deliberate: a scroll extent
    // that grows when the skeleton appears is the same jolt in miniature.
    if (sweep != null && !sweep.visible) {
      return SizedBox(width: width, height: height);
    }

    // **No group above at all paints flat, and does not disappear.** This
    // branch was `SizedBox` alone until a review caught it: a block whose call
    // site forgot its group rendered as empty space forever, which is a screen
    // that silently shows nothing rather than a placeholder that looks dull.
    // Invisible is the one failure mode a fallback here must not have.
    if (sweep == null || !sweep.animated) {
      return SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: base, borderRadius: corner),
        ),
      );
    }

    final curve = tokens.motion.skeletonSweep.curve;
    return SizedBox(
      width: width,
      height: height,
      child: AnimatedBuilder(
        animation: sweep.animation,
        builder: (context, _) {
          // -1 to 1: the highlight enters off one edge and leaves off the other,
          // so the pass reads as a sweep rather than a pulse in place.
          final slide = curve.transform(sweep.animation.value) * 2 - 1;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: corner,
              gradient: LinearGradient(
                begin: Alignment(slide - 1, 0),
                end: Alignment(slide + 1, 0),
                colors: <Color>[base, highlight, base],
                stops: const <double>[0, 0.5, 1],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Placeholder records, in whatever shape [RecordList] will draw them.
///
/// **It asks [RecordList.formFor] the same question the real list asks**, rather
/// than carrying its own idea of what a band looks like. A skeleton of stacked
/// cards that resolves into a table is worse than no skeleton at all - it tells
/// a person the wrong thing about the screen they are waiting for, which is the
/// one failure a placeholder can actually cause.
///
/// **No empty state, ever.** An empty read is not a slow read: it has answered,
/// and the answer was nothing. This draws only while the answer is outstanding,
/// and `RecordList`'s own `empty` takes over the moment it lands.
final class RecordListSkeleton extends StatelessWidget {
  const RecordListSkeleton({super.key, this.rows = 4});

  /// How many placeholder records to draw. Four fills a phone without
  /// pretending to know how many the read will return.
  final int rows;

  /// A table row, and it is `space.48` because that is §9's tap target.
  ///
  /// The one figure here that is derived rather than chosen: a table row carries
  /// actions, so it cannot be shorter than the smallest thing a finger may be
  /// asked to hit.
  static double _tableRowHeight(AppSpacing spacing) => spacing.s48;

  /// A card, which is an identity line, its attributes and its actions.
  ///
  /// **Named here rather than tokenised, for the reason `EmptyState.markSize`
  /// gives**: no source this app has states a record card's height, and
  /// `RecordList` derives its own from the content it has - which a placeholder
  /// does not have. 132 is what a four-attribute sale card measures, which is
  /// the shape of every list this is used on.
  static const double _cardHeight = 132;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final form = RecordList.formFor(MediaQuery.sizeOf(context).width);
    final gap = SizedBox(height: tokens.spacing.s8);

    if (form == RecordForm.table) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The header rule, which a table has and a card list does not.
          SkeletonBlock(
            height: tokens.spacing.s32,
            radius: tokens.radius.sm,
          ),
          for (var row = 0; row < rows; row++) ...<Widget>[
            gap,
            SkeletonBlock(height: _tableRowHeight(tokens.spacing)),
          ],
        ],
      );
    }

    final card = SkeletonBlock(height: _cardHeight);
    if (form == RecordForm.stackedCards) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var row = 0; row < rows; row++) ...<Widget>[
            if (row > 0) gap,
            card,
          ],
        ],
      );
    }

    // `twoColumnCards`: the same card, two to a row, which is §4.3's medium band.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var row = 0; row < (rows / 2).ceil(); row++) ...<Widget>[
          if (row > 0) gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: card),
              SizedBox(width: tokens.spacing.s8),
              Expanded(child: card),
            ],
          ),
        ],
      ],
    );
  }
}

/// A block the height of one line of text, for prose that has not arrived.
///
/// **[widthFactor] rather than a width**, because a paragraph of placeholders
/// reads as text only if the lines are not all the same length - and the caller
/// knows the ragged edge it wants better than a component does.
final class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.widthFactor = 1,
    this.style,
    this.tone = SkeletonTone.onPage,
  });

  /// A fraction of the available width, 0 to 1.
  final double widthFactor;

  /// The role the real text will take, so the placeholder is the height of the
  /// line it replaces. Defaults to the density's body role.
  final TextStyle? style;

  /// What this line is painted on top of. See [SkeletonTone].
  final SkeletonTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = style ?? tokens.density.body(tokens.typography);
    // The line box, not the glyph box: a placeholder matched to cap height would
    // leave the leading out and the real text would shift down when it landed.
    final size = role.fontSize ?? tokens.typography.bodyMedium.fontSize ?? 14;
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: SkeletonBlock(
        height: size * (role.height ?? 1.4),
        radius: tokens.radius.sm,
        tone: tone,
      ),
    );
  }
}

/// A form control on a page whose read has not landed, drawn as itself.
///
/// **Nothing here shimmers, and that is the finding rather than an omission.**
/// Decision 35 asks which parts of a screen change when the read returns, and
/// on these routes the filter row is not one of them: the labels are fixed
/// words, the wells are fixed frames, and *All roles* / *All statuses* /
/// *All categories* are the values the controls already hold - they are page
/// state, decided before the read started and untouched by it. So the whole
/// control is drawn for real, and what shimmers is the records below it, which
/// is the only thing anybody is actually waiting for.
///
/// **A block inside the well would also have been invisible.** Both palettes
/// set `surface.field` and `surface.borderSubtle` to the same value
/// (`#132A1F` under Profound Verdant, `green700` under dark), so
/// [SkeletonTone.onRaised] - the tone for a block inside a raised thing -
/// paints a placeholder exactly the colour of the well it sits in. That is the
/// failure [SkeletonTone] warns about in its own doc, found here by a capture
/// showing three empty wells.
///
/// **It draws [AppFieldWell] rather than measuring one.** A well's height is
/// `density.minimumTapTarget` plus the focus ring's reserved gutter plus its
/// label line - three figures a placeholder must not carry a second copy of,
/// because a copy drifts and the drift is the layout jump this exists to
/// prevent. A filter row under a skeleton is the same height, to the pixel, as
/// the filter row that replaces it.
///
/// **It is not a disabled field.** `AppFieldWell(enabled: false)` greys the
/// label and the border, and what that says is *you may not use this* - where
/// what is true is that the page is a moment from being usable.
final class SkeletonField extends StatelessWidget {
  const SkeletonField({
    super.key,
    required this.label,
    this.value,
    this.leading,
    this.trailing,
    this.helper,
  });

  /// The control's own label. Empty draws no label row, exactly as
  /// [AppFieldWell] does for the same string.
  final String label;

  /// What the control already reads, where it reads anything.
  ///
  /// Null leaves the well empty, which is what an untyped search field looks
  /// like once the page has landed - so leaving it out is the accurate
  /// rendering rather than a missing one.
  final String? value;

  /// The glyph at the well's leading edge, where the real control has one.
  final IconData? leading;

  /// The glyph at the well's trailing edge - a select's chevron.
  ///
  /// [AppSelect] draws a `DropdownButton`, whose arrow is part of what makes a
  /// select look like one; a well holding a word and no chevron reads as a
  /// disabled field rather than as a filter.
  final IconData? trailing;

  /// The sentence under the well, for a field whose real counterpart carries
  /// one - without it the row is a line shorter than the row it stands in for.
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    return AppFieldWell(
      label: label,
      leading: leading,
      helper: helper,
      // A `Row` rather than a bare `Text`, because [AppFieldWell] centres a
      // child that does not fill and both real controls do fill: a `TextField`
      // and a `DropdownButton(isExpanded: true)` are each the width of the
      // well, and their content starts at its leading edge.
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              value ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // The density's body role, which is the style `AppSelect` hands
              // its own button - read from the same place rather than guessed
              // at from the nearest-looking typography role.
              style: tokens.density
                  .body(tokens.typography)
                  .copyWith(color: colors.text.primary),
            ),
          ),
          if (trailing case final glyph?)
            Icon(glyph, color: colors.text.secondary),
        ],
      ),
    );
  }
}
