/// `Pagination`: the bar under every record list, drawn as **one pager** - the
/// way back, where you are, and the way on, joined in a single container.
///
/// **Redrawn on 2026-09-22 from `docs/design/pagination/`.** The bar before it
/// was two `AppButton`s at opposite ends of the row with a lone `Page N`
/// between them: in the catalog column at 1440 the controls sat 881 apart, and
/// on a list that fits one page - the most common real case - the two disabled
/// slabs out-painted the live card above them, because `disabledContainer`
/// stands further off the page than the enabled one does. The pager keeps the
/// three inputs, the three keys and the callbacks, and changes what they draw:
///
/// - **One container, two hairlines.** `action.secondary`'s container and edge
///   at `radius.md`, 48 high. A segment's hover, press and disabled states
///   happen inside it; the container itself never changes colour, so a
///   disabled segment only steps its ink down.
/// - **Where you are sits in the middle and never shortens.** The word is
///   quieter than the figure, so the eye reads the number, and the figure rolls
///   through `RollingNumber` the way the page moved. It reserves the width of
///   `Page 000`, so reaching page 10 does not nudge `Previous` sideways.
/// - **By width, as the old bar decided it, plus one tier.** At its own width
///   at the end of the row from `medium`; across the row below it, where the
///   two nav segments split what the position leaves; and glyphs only where the
///   words do not fit - 200% text on a phone - with the words kept in
///   semantics.
///
/// **Three inputs the old bar could not take, each optional**, so a call site
/// that passes none of them gets the restyle and nothing else:
///
/// - [loading] - the segment that was pressed shows a spinner in place of its
///   chevron and the other one waits. A call site knows this already: it
///   started the read.
/// - [range] - which records these are, `Showing 21–40`. Never `of N`: these
///   reads page by cursor and do not learn a total.
/// - [endOfList] - the list has no more records, which the old bar could not
///   tell from *paused while a write is in flight*: both arrived as a null
///   [onNext]. Told, the last page says so in words, and a list that fits one
///   page draws no bar at all.
library;

import 'dart:math' as math;
import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';

import 'buttons.dart';
import 'measure.dart';
import 'press.dart';
import 'rolling_number.dart';
import 'tokens.dart';

/// Which way a page read is going. See [Pagination.loading].
enum PaginationDirection { previous, next }

/// The first and last record numbers on the page shown, counting from 1.
typedef PaginationRange = ({int first, int last});

/// The bar that moves a record list between pages.
final class Pagination extends StatelessWidget {
  const Pagination({
    super.key,
    required this.pageNumber,
    required this.onPrevious,
    required this.onNext,
    this.previousKey,
    this.nextKey,
    this.pageKey,
    this.loading,
    this.range,
    this.endOfList = false,
  });

  /// Which page is shown, counting from **1**.
  ///
  /// Every call site holds a zero-based `pageIndex`; the `+ 1` is the caller's,
  /// because this component states what a person reads and does not know that
  /// there is an index underneath it.
  final int pageNumber;

  /// Null when there is no previous page — which draws the segment disabled
  /// rather than removing it, so nothing moves under a thumb when page two
  /// arrives.
  final VoidCallback? onPrevious;

  /// Null when the read reported no more records, or while a write is in
  /// flight and paging would discard it.
  final VoidCallback? onNext;

  /// Keys on the three parts, for the call sites whose tests already address
  /// them. The two nav keys land on the segments' [PressSurface]s, so a test
  /// taps them and reads `onPressed` off them; [pageKey] lands on the figure's
  /// `Text` at rest, which is the page number alone.
  final Key? previousKey;
  final Key? nextKey;
  final Key? pageKey;

  /// The direction of a page read in flight, or null where none is.
  ///
  /// The segment that way keeps its label colour and trades its chevron for
  /// §2.1's 16px spinner, in a box the chevron's size so the segment does not
  /// resize mid-read; it is announced *working* and does not answer a second
  /// press. The other segment is disabled for the length of the read.
  final PaginationDirection? loading;

  /// The records on this page, drawn as `Showing first–last`. Null draws no
  /// statement. At the start of the row from `medium`; above the pager and
  /// start-aligned below it.
  final PaginationRange? range;

  /// Whether the read said there is nothing after this page.
  ///
  /// On page one that means the list fits one page, and the bar is not drawn
  /// at all: the last row is the end of the list. On a later page the position
  /// says `last` in words beside the disabled `Next`, so the disabled state is
  /// explained by a word rather than by its colour.
  final bool endOfList;

  static const String _previousLabel = 'Previous';
  static const String _nextLabel = 'Next';
  static const String _pageLabel = 'Page';
  static const String _lastLabel = '· last';

  /// The figure the position reserves room for. Three digits, so paging from
  /// 99 to 100 does not move `Previous`; the thousandth page grows it by one.
  static const String _reservedFigure = '000';

  /// Whether this bar draws anything at all: not on a list that fits one page.
  bool get draws => !(endOfList && pageNumber == 1);

  /// This bar with [gap] above it, or nothing where the bar draws nothing.
  ///
  /// **The gap goes with the bar**, because it is the bar's: it spaces the
  /// pager from the list above it. Left behind on a list that fits one page,
  /// it would end that list on a stretch of nothing.
  List<Widget> withGapAbove(double gap) =>
      draws ? <Widget>[SizedBox(height: gap), this] : const <Widget>[];

  /// Whether the pager takes the whole row rather than its own width. Below
  /// `medium`, where each nav segment wants to be a wide target under a thumb.
  static bool fillsRow(double screenWidth) =>
      screenWidth < AppLayout.contract.mediumFloor;

  /// Whether the nav segments carry their words in [width], or glyphs alone.
  ///
  /// **Measured rather than looked up**, as the bar has decided it since
  /// 2026-08-25: how much room two labels, two glyphs and a page statement
  /// need is arithmetic this component can do, where a breakpoint is a guess
  /// about a page. Exposed so a test can ask the question the widget asks
  /// instead of asserting a pixel width.
  static bool showsWords(
    double width,
    AppTokens tokens, {
    required bool fill,
    int pageNumber = 1,
    bool last = false,
    TextScaler textScaler = TextScaler.noScaling,
    TextStyle? ambient,
  }) {
    final previous = _navWidth(
      tokens,
      _previousLabel,
      textScaler: textScaler,
      ambient: ambient,
    );
    final next = _navWidth(
      tokens,
      _nextLabel,
      textScaler: textScaler,
      ambient: ambient,
    );
    final ring = tokens.colors.action.focusRing;
    final needed =
        (ring.width + ring.offset) * 2 +
        (fill ? math.max(previous, next) * 2 : previous + next) +
        _positionWidth(
          tokens,
          pageNumber,
          last: last,
          textScaler: textScaler,
          ambient: ambient,
        );
    return width >= needed;
  }

  /// A nav segment's width with its word: §5.2's padding with an icon, the
  /// glyph, `space.8` to the word, and the word in `label.lg`.
  static double _navWidth(
    AppTokens tokens,
    String label, {
    required TextScaler textScaler,
    TextStyle? ambient,
  }) =>
      AppButtonSize.lg.horizontalPadding(tokens.spacing, hasIcon: true) * 2 +
      AppButton.iconSize +
      tokens.spacing.s8 +
      measureTextWidth(
        label,
        tokens.typography.labelLarge,
        textScaler: textScaler,
        ambient: ambient,
      );

  /// The position's width: `Page`, `space.4`, and the figure - never less than
  /// three digits' worth - between the segment padding.
  static double _positionWidth(
    AppTokens tokens,
    int pageNumber, {
    required bool last,
    required TextScaler textScaler,
    TextStyle? ambient,
  }) {
    final figure = '$pageNumber'.length > _reservedFigure.length
        ? '$pageNumber'
        : _reservedFigure;
    double measure(String text, TextStyle style) =>
        measureTextWidth(text, style, textScaler: textScaler, ambient: ambient);
    return AppButtonSize.lg.horizontalPadding(tokens.spacing, hasIcon: true) *
            2 +
        measure(_pageLabel, tokens.typography.labelMedium) +
        tokens.spacing.s4 +
        measure(figure, tokens.typography.numericBody) +
        (last
            ? tokens.spacing.s4 +
                  measure(_lastLabel, tokens.typography.labelMedium)
            : 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!draws) {
      return const SizedBox.shrink();
    }
    final tokens = AppTokens.componentOf(context);
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final ambient = DefaultTextStyle.of(context).style;
    // **The screen's width, not the bar's own constraint.** A `LayoutBuilder`
    // would measure the box this bar was actually given, which is the better
    // question - and it cannot be asked here: `AlertDialog` sizes its content
    // by intrinsic height, `LayoutBuilder` refuses to answer an intrinsic
    // query, and every paginated list inside a dialog threw
    // *"LayoutBuilder does not support returning intrinsic dimensions"*. The
    // category dialogs are three of them. So a bar in a dialog narrower than
    // the screen chooses words and ellipsizes them, which is the fallback.
    final screen = MediaQuery.sizeOf(context).width;
    final fill = fillsRow(screen);
    final words = showsWords(
      // Below `medium` every list in the app is inset at least `space.16` a
      // side, and the pager lives inside one.
      fill ? screen - tokens.spacing.s16 * 2 : screen,
      tokens,
      fill: fill,
      pageNumber: pageNumber,
      last: endOfList,
      textScaler: textScaler,
      ambient: ambient,
    );
    final pager = _Pager(
      pageNumber: pageNumber,
      onPrevious: onPrevious,
      onNext: endOfList ? null : onNext,
      previousKey: previousKey,
      nextKey: nextKey,
      pageKey: pageKey,
      loading: loading,
      last: endOfList,
      fill: fill,
      words: words,
      positionWidth: _positionWidth(
        tokens,
        pageNumber,
        last: endOfList,
        textScaler: textScaler,
        ambient: ambient,
      ),
    );
    final shown = range;
    if (shown == null) {
      return fill
          ? pager
          : Align(alignment: AlignmentDirectional.centerEnd, child: pager);
    }
    // The statement lines up with the pager's painted edge rather than with
    // the focus-ring gutter the pager reserves round itself.
    final ring = tokens.colors.action.focusRing;
    final statement = Padding(
      padding: EdgeInsetsDirectional.only(start: ring.width + ring.offset),
      child: _RangeStatement(range: shown),
    );
    if (fill) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Align(alignment: AlignmentDirectional.centerStart, child: statement),
          SizedBox(height: tokens.spacing.s8),
          pager,
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: statement,
          ),
        ),
        SizedBox(width: tokens.spacing.s16),
        pager,
      ],
    );
  }
}

/// The joined group: two nav segments either side of the position.
final class _Pager extends StatelessWidget {
  const _Pager({
    required this.pageNumber,
    required this.onPrevious,
    required this.onNext,
    required this.previousKey,
    required this.nextKey,
    required this.pageKey,
    required this.loading,
    required this.last,
    required this.fill,
    required this.words,
    required this.positionWidth,
  });

  final int pageNumber;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Key? previousKey;
  final Key? nextKey;
  final Key? pageKey;
  final PaginationDirection? loading;
  final bool last;
  final bool fill;
  final bool words;
  final double positionWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final actions = tokens.colors.action;
    final ring = actions.focusRing;
    final radius = BorderRadius.circular(tokens.radius.md);
    final idle = loading == null;

    Widget nav(PaginationDirection direction) {
      final previous = direction == PaginationDirection.previous;
      final segment = _NavSegment(
        surfaceKey: previous ? previousKey : nextKey,
        direction: direction,
        onPressed: idle ? (previous ? onPrevious : onNext) : null,
        working: loading == direction,
        words: words,
        fill: fill,
      );
      return fill ? Expanded(child: segment) : Flexible(child: segment);
    }

    // **The container paints under the segments and its edge over them**, so
    // a segment's hover and press wash fill the group to its corners and the
    // edge is still drawn round them, as a border inside a box is.
    return Padding(
      // One focus-ring gutter round the whole group: the segments reserve
      // none of their own - see `PressSurface.reservesRingGutter`.
      padding: EdgeInsets.all(ring.width + ring.offset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: actions.secondary.container,
          borderRadius: radius,
        ),
        position: DecorationPosition.background,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color:
                  actions.secondary.border ??
                  tokens.colors.surface.borderStrong,
            ),
          ),
          position: DecorationPosition.foreground,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: AppButtonSize.lg.height),
            child: IntrinsicHeight(
              child: Row(
                mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  nav(PaginationDirection.previous),
                  _Position(
                    pageNumber: pageNumber,
                    pageKey: pageKey,
                    last: last,
                    minWidth: positionWidth,
                  ),
                  nav(PaginationDirection.next),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `Previous` or `Next`: a pressable segment with a chevron and, room
/// permitting, a word.
///
/// **On `PressSurface` rather than an `AppButton`**, because `Next`'s chevron
/// trails its word and `AppButton` offers a leading icon only. Every state is
/// `PressSurface`'s, exactly as a button's are.
final class _NavSegment extends StatelessWidget {
  const _NavSegment({
    required this.surfaceKey,
    required this.direction,
    required this.onPressed,
    required this.working,
    required this.words,
    required this.fill,
  });

  /// The call site's key, put on the [PressSurface] and nowhere else, so one
  /// key finds one widget.
  final Key? surfaceKey;

  final PaginationDirection direction;
  final VoidCallback? onPressed;
  final bool working;
  final bool words;
  final bool fill;

  bool get _previous => direction == PaginationDirection.previous;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final actions = tokens.colors.action;
    final role = actions.secondary;
    final textDirection = Directionality.of(context);
    // Working is not disabled: it is a press already accepted, so it keeps the
    // label colour while refusing a second one.
    final label = onPressed == null && !working
        ? actions.disabledLabel
        : role.label;
    final corner = Radius.circular(tokens.radius.md);
    final shape =
        (_previous
                ? BorderRadiusDirectional.horizontal(start: corner)
                : BorderRadiusDirectional.horizontal(end: corner))
            .resolve(textDirection);
    final divider = BorderSide(
      color: role.border ?? tokens.colors.surface.borderStrong,
    );

    final Widget glyph = SizedBox.square(
      dimension: AppButton.iconSize,
      child: working
          ? Center(
              child: SizedBox.square(
                dimension: actions.loadingIndicatorSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  // §2.1: "a 16px spinner in label colour".
                  valueColor: AlwaysStoppedAnimation<Color>(label),
                ),
              ),
            )
          : Icon(
              _previous ? Icons.chevron_left : Icons.chevron_right,
              size: AppButton.iconSize,
              color: label,
            ),
    );
    final Widget content;
    if (words) {
      final word = Flexible(
        child: Text(
          _previous ? Pagination._previousLabel : Pagination._nextLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.labelLarge.copyWith(color: label),
        ),
      );
      final gap = SizedBox(width: tokens.spacing.s8);
      content = Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppButtonSize.lg.horizontalPadding(
            tokens.spacing,
            hasIcon: true,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: _previous
              ? <Widget>[glyph, gap, word]
              : <Widget>[word, gap, glyph],
        ),
      );
    } else {
      // Glyphs alone keep §9's square target.
      content = SizedBox(
        width: AppButtonSize.lg.height,
        child: Center(child: glyph),
      );
    }

    final name = _previous ? 'Previous page' : 'Next page';
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      // Announced in full at every width, including where only a chevron
      // shows, because a screen reader hears it without the bar round it.
      label: working ? '$name, working' : name,
      onTap: onPressed,
      excludeSemantics: true,
      child: PressSurface(
        key: surfaceKey,
        borderRadius: shape,
        onPressed: onPressed,
        hoverOverlay: role.hoverFill(),
        pressedOverlay: role.pressedFill(),
        mouseCursor: working ? SystemMouseCursors.progress : null,
        excludeSemantics: true,
        reservesRingGutter: false,
        fillWidth: fill,
        fillHeight: true,
        child: DecoratedBox(
          // The hairline between this segment and the position, drawn inside
          // the segment so its own focus ring paints over it rather than
          // under the neighbour that follows it in the row.
          decoration: BoxDecoration(
            border: _previous
                ? BorderDirectional(end: divider)
                : BorderDirectional(start: divider),
          ),
          child: Center(widthFactor: fill ? null : 1, child: content),
        ),
      ),
    );
  }
}

/// Where the list is: `Page` and the figure. Not pressable, and a polite live
/// region, so a page change is heard as well as seen.
final class _Position extends StatelessWidget {
  const _Position({
    required this.pageNumber,
    required this.pageKey,
    required this.last,
    required this.minWidth,
  });

  final int pageNumber;
  final Key? pageKey;
  final bool last;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // `label.md` at `text.secondary` for the words: §9's 4.5:1 row rather than
    // the `caption` this would otherwise reach for, which §9's own failure
    // list names at 3.4:1.
    final word = tokens.typography.labelMedium.copyWith(
      color: tokens.colors.text.secondary,
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: last ? 'Page $pageNumber, the last' : 'Page $pageNumber',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppButtonSize.lg.horizontalPadding(
              tokens.spacing,
              hasIcon: true,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(Pagination._pageLabel, style: word),
              SizedBox(width: tokens.spacing.s4),
              // Rolls the way the page moved, and only the digits that changed.
              // Nothing waits for it: the page callback has already fired.
              RollingNumber(
                value: '$pageNumber',
                textKey: pageKey,
                spring: RollingNumberSpring.snappy,
                style: tokens.typography.numericBody.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
              if (last) ...<Widget>[
                SizedBox(width: tokens.spacing.s4),
                Text(Pagination._lastLabel, style: word),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `Showing 21–40`: the words in `label.md`, the figures in `numeric.body`.
final class _RangeStatement extends StatelessWidget {
  const _RangeStatement({required this.range});

  final PaginationRange range;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // A page of one record is that record, not a span from it to itself.
    final single = range.first == range.last;
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: 'Showing ',
            style: tokens.typography.labelMedium.copyWith(
              color: tokens.colors.text.secondary,
            ),
          ),
          TextSpan(
            text: single ? '${range.first}' : '${range.first}–${range.last}',
            style: tokens.typography.numericBody.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
        ],
      ),
      semanticsLabel: single
          ? 'Showing ${range.first}'
          : 'Showing ${range.first} to ${range.last}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// A record list whose pager, where it has one, is held at the bottom of the
/// screen instead of waiting at the end of the list.
///
/// **Held rather than scrolled to, at the developer's direction on
/// 2026-09-22**: a list that runs past one page says so from its first row,
/// and the way to the next page is already where a thumb is. The bar keeps one
/// place on every page - it does not ride up under a short last page - which
/// is the rule the pager itself was drawn to: nothing moves under a thumb.
///
/// **A list that fits one page is an ordinary list**, with no pager and no
/// footer: [Pagination.draws] says so, and this draws the list alone.
///
/// **Only where the paged list is the screen.** A pager for a list inside a
/// form or a dialog - the bulk change's product picker, the category dialog,
/// a sale's returns above the form that records one - stays in the flow, next
/// to the list it moves.
///
/// **The footer has no fill of its own.** The list's viewport stops where the
/// footer starts, so nothing scrolls beneath it, and it takes whatever surface
/// it sits on - a page or a sheet - with one hairline to mark where the list
/// is cut.
///
/// **The shape of this tree never changes, for the reason `AppSheet`'s does.**
/// This first returned the bare list when there was no bar and a column round
/// it when there was, so the list and every row in it were re-inflated each
/// time the bar came or went - and the catalog and the staff directory keep
/// their search field in those rows. On a list longer than a page, the keyboard
/// coming up for the search put the bar away, which took the field, which took
/// the keyboard. The list is always the column's first child now, and only the
/// slot below it changes.
final class PagedListView extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.pagination,
    required this.children,
    this.listKey,
    this.controller,
    this.padding,
  });

  /// The bar, or null where this list is showing something that does not
  /// page - a receipt looked up by its number, say, or a first read.
  final Pagination? pagination;

  final List<Widget> children;

  /// The key on the list itself, for the tests and captures that scroll it by
  /// name.
  final Key? listKey;

  final ScrollController? controller;

  /// The list's padding. Its start and end insets are the footer's too, so the
  /// pager lines up with the rows above it.
  final EdgeInsetsGeometry? padding;

  @override
  State<PagedListView> createState() => _PagedListViewState();
}

final class _PagedListViewState extends State<PagedListView>
    with WidgetsBindingObserver {
  /// The view this list was last built in, and whether the keyboard was up in
  /// it then - so a change of metrics rebuilds only when that answer changes,
  /// not on every frame of the keyboard's travel.
  FlutterView? _view;
  bool _keyboardOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// **Watched rather than read, because nothing else rebuilds this.** The
  /// view's insets are not an inherited dependency, so reading them in `build`
  /// alone left the bar where the last unrelated rebuild had put it: pinned
  /// above a keyboard that had just come up, or missing after it went down.
  @override
  void didChangeMetrics() {
    final view = _view;
    if (view == null || (view.viewInsets.bottom > 0) == _keyboardOpen) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // **Not while the keyboard is open.** It takes the bottom of the screen
    // for as long as a search is being typed, and a bar held above it would
    // leave the results a sliver of the screen to show themselves in. Read
    // from the view, because the scaffold has already taken the keyboard's
    // inset out of the `MediaQuery` this body sees.
    final view = _view = View.of(context);
    _keyboardOpen = view.viewInsets.bottom > 0;
    final bar = widget.pagination;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView(
            key: widget.listKey,
            controller: widget.controller,
            padding: widget.padding,
            children: widget.children,
          ),
        ),
        if (bar != null && bar.draws && !_keyboardOpen)
          _footer(context, bar)
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _footer(BuildContext context, Pagination bar) {
    final tokens = AppTokens.componentOf(context);
    final inset = (widget.padding ?? EdgeInsets.zero).resolve(
      Directionality.of(context),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.colors.surface.borderSubtle),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            inset.left,
            tokens.spacing.s8,
            inset.right,
            tokens.spacing.s8,
          ),
          child: bar,
        ),
      ),
    );
  }
}
