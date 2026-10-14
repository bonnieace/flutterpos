/// `RecordSheet`: the table from `docs/design/tables/`, for a screen at 1024 and
/// up.
///
/// **A screen opts in; nothing else changes.** `RecordList` keeps its own table
/// for the screens that use it, and a screen that draws cards keeps its cards
/// below `AppBreakpoint.expanded` - the developer's ruling on 2026-10-12 was
/// that only the large-screen version changes. This is the component that
/// version is drawn with, first on shift history.
///
/// What it draws, from the boards:
///
/// - **One raised sheet per list**: the screen's filters in a bar on top, a
///   quiet header, and the rows. **Nothing else**, at the developer's direction
///   on 2026-10-13: a band naming the day under the header and a sentence at
///   the foot were both taken off the first screen, so the component offers
///   neither.
/// - **Rows that read across**, 56 at the least. The whole row is one control
///   when the screen gives it one; a disclosure and a menu, where a row has
///   them, are 48 targets of their own in the first and last columns.
/// - **Figures as a column**: the mono face, right-aligned, the unit stated once
///   in the header, and an optional blank suffix ([SheetFigure.reserve]) so
///   whole amounts line up under amounts with cents.
/// - **Status by exception**: a [SheetStatus] is a [StatusBadge] when the state
///   wants somebody's attention and a quiet glyph and word when it does not.
/// - **Folds**: a [SheetFold] opens beneath its row on a spring, on the row's
///   own surface and in the row's own columns. It had a darker band of its
///   own until 2026-10-14, when the developer asked for the bands to go and
///   for what they held to sit in the table's columns.
///
/// **It scrolls nothing**, for `RecordList`'s reason: every screen it is drawn
/// on already sits in its own list.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, RenderObjectWithChildMixin, RenderViewportBase;

import 'measure.dart';
import 'press.dart';
import 'record_list.dart';
import 'skeleton.dart';
import 'spring.dart';
import 'states.dart';
import 'status.dart';
import 'tokens.dart';

/// What a column holds, which decides its face, its alignment, and whether it
/// is measured or shares what is left.
enum SheetColumnKind {
  /// What a row is: a name, over an optional caption. Shares the room left.
  identity,

  /// Words. Shares the room left with the identity.
  text,

  /// A count or an amount: mono, right-aligned, as wide as its widest value.
  figure,

  /// A clock time or a span of them: mono, left-aligned, measured.
  time,

  /// An identifier - a receipt, a reference, a batch number: mono,
  /// left-aligned, measured. Never summed, so never right-aligned.
  code,

  /// A [SheetStatus]. Measured.
  status,
}

/// One column of a [RecordSheet].
@immutable
final class SheetColumn {
  const SheetColumn({
    required this.label,
    this.kind = SheetColumnKind.text,
    this.unit,
    this.flex = 1,
  }) : assert(flex > 0, 'A column shares the room by a positive share.');

  /// The header, in the caller's words. Drawn upper case.
  final String label;

  final SheetColumnKind kind;

  /// Stated once, after the label in the header, so no cell has to repeat it -
  /// `KES` over a column of amounts. Null states none.
  final String? unit;

  /// This column's share of the room the measured columns leave. Read only by
  /// [SheetColumnKind.identity] and [SheetColumnKind.text].
  final int flex;

  bool get _shares =>
      kind == SheetColumnKind.identity || kind == SheetColumnKind.text;

  bool get _alignsEnd => kind == SheetColumnKind.figure;

  /// The header's words, as a screen reader hears a cell under it.
  String get _spoken => unit == null ? label : '$label ($unit)';
}

/// One cell of a [SheetRow].
sealed class SheetCell {
  const SheetCell();
}

/// Words in a cell: an identity, a text or a time, by its column's kind.
final class SheetText extends SheetCell {
  const SheetText(this.value, {this.caption, this.key, this.captionKey});

  final String value;

  /// A second line under the value, in `caption` at `text.tertiary`.
  final String? caption;

  final Key? key;
  final Key? captionKey;
}

/// A figure: a count or an amount, already formatted by the caller.
final class SheetFigure extends SheetCell {
  const SheetFigure(
    this.value, {
    this.reserve,
    this.caption,
    this.key,
    this.captionKey,
  }) : known = true;

  /// A figure the record does not have, drawn as a dash at `text.tertiary` -
  /// never as a zero, which would be a claim.
  ///
  /// [caption] says why, where there is a reason to give - *No costs
  /// recorded* - so the dash is never read as an amount.
  const SheetFigure.unknown({
    this.reserve,
    this.key,
    this.caption,
    this.captionKey,
  }) : value = '—',
       known = false;

  final String value;

  /// Blank space after the value, held so its digits line up with the
  /// column's others: `.00` after a whole amount in a column where some amount
  /// has cents. The caller knows the amounts, so the caller decides; this
  /// component never reads a number out of a string.
  final String? reserve;

  final String? caption;
  final Key? key;
  final Key? captionKey;
  final bool known;
}

/// A standing.
final class SheetStatus extends SheetCell {
  const SheetStatus({
    required this.status,
    required this.label,
    this.icon,
    this.semanticLabel,
    this.quiet = false,
    this.key,
  });

  final AppStatus status;

  /// The word. Sentence case.
  final String label;

  /// Overrides [AppStatus.defaultIcon].
  final IconData? icon;

  /// What a screen reader hears in place of [label].
  final String? semanticLabel;

  /// **A settled state, drawn as a glyph and a word in text colour** rather
  /// than a [StatusBadge]. The badge is kept for a state somebody should act
  /// on, which is what makes the rows that need a look stand out.
  final bool quiet;

  final Key? key;
}

/// One record: a row of a [RecordSheet].
@immutable
final class SheetRow {
  const SheetRow({
    required this.id,
    required this.cells,
    this.key,
    this.pressKey,
    this.onPressed,
    this.semanticLabel,
    this.semanticHint,
    this.actions = const <RecordAction>[],
    this.actionsKey,
    this.actionsTooltip = 'More actions',
    this.fold,
  });

  /// Never displayed. Keys the row's state, so a fold stays open on the record
  /// rather than on a position when the list is rebuilt.
  final String id;

  /// One per column, in column order. Null is an empty cell.
  final List<SheetCell?> cells;

  /// On the whole row, fold included.
  final Key? key;

  /// On the row's own control.
  final Key? pressKey;

  /// What pressing the row does. Null makes the row inert.
  final VoidCallback? onPressed;

  /// The start of what a screen reader hears for the row - who or what it is.
  /// The sheet adds every other cell under its column's name, so the caller
  /// does not restate figures it has already handed over.
  final String? semanticLabel;

  /// What pressing the row will do, in a sentence.
  final String? semanticHint;

  /// Behind the row's menu in the last column. Empty draws no menu.
  final List<RecordAction> actions;
  final Key? actionsKey;
  final String actionsTooltip;

  /// What opens under the row. Null draws no disclosure.
  final SheetFold? fold;
}

/// What a row folds away: a sentence, and figures laid on the row's columns.
@immutable
final class SheetFold {
  const SheetFold({
    this.note,
    this.noteKey,
    this.noteColumn = 0,
    this.lines = const <SheetFoldLine>[],
    this.toggleKey,
    this.showLabel = 'Show more',
    this.hideLabel = 'Show less',
    this.alwaysOpen = false,
  }) : assert(
         note != null || lines.length > 0,
         'A fold with nothing in it is a disclosure that opens onto nothing.',
       );

  final String? note;
  final Key? noteKey;

  /// The column the [note] starts under. It runs on to the row's end, so a
  /// reason for a standing can sit under the standing it explains.
  final int noteColumn;

  final List<SheetFoldLine> lines;

  /// **Drawn under its row, with nothing to open.** For a list whose lines are
  /// what a person opens it to read - a supplier's deliveries, where the
  /// developer ruled on 2026-09-27 that every line is on the card with nothing
  /// to tap. The row gets no disclosure, and the lines sit on their band
  /// under it, aligned to the row's columns as an opened fold's are.
  final bool alwaysOpen;

  /// On the disclosure.
  final Key? toggleKey;

  /// What a screen reader hears on the closed disclosure, and on the open one.
  final String showLabel;
  final String hideLabel;
}

/// One line in a fold: words and figures, each under the column it belongs to.
@immutable
final class SheetFoldLine {
  const SheetFoldLine({
    required this.label,
    required this.value,
    required this.column,
    this.labelColumn = 0,
    this.figures = const <int, String>{},
    this.reserve,
    this.valueKey,
  }) : assert(
         labelColumn < column,
         'The label sits in a column before the value.',
       );

  final String label;
  final String value;

  /// The index of the column the value sits under, so the figure lines up
  /// with the row's own.
  final int column;

  /// The column the [label] starts under - usually the one that names what a
  /// row is. It runs on through every empty column after it.
  final int labelColumn;

  /// More figures on the line, by the index of the column each sits under -
  /// a delivery line's units under the row's units. Drawn as the value is.
  final Map<int, String> figures;

  /// See [SheetFigure.reserve].
  final String? reserve;

  final Key? valueKey;
}

/// The widths of one [RecordSheet]'s columns.
///
/// **Equal columns, at the developer's direction on 2026-10-13.** The first
/// version gave each figure column exactly what its widest value needed and
/// handed everything left to the identity, which on a 1280 window drew a
/// cashier column 800 wide and five figure columns crowded at the right edge,
/// each a different width - so the gaps between figures were uneven and the
/// table read as a name with some numbers after it.
///
/// So every column gets the same width, an identity or text column by its
/// share ([SheetColumn.flex]), and the layout only gives that up as the room
/// runs out, one step at a time:
///
/// 1. **Every column equal**, where that leaves each figure room for its
///    widest value and each name room for itself on one line.
/// 2. **Names at what they need, the figure columns equal** across the rest.
/// 3. **The figure columns equal at the widest one's need**, and the names
///    share what is left - wrapping to their second line, then ellipsising.
/// 4. **Each figure column at its own need**, which is the narrowest a table
///    can be without cutting a figure, and the names share the rest.
///
/// A figure, a time or a standing is never wrapped and never cut short in any
/// of the four: it is the one kind of cell whose width is a fact.
@immutable
final class SheetLayout {
  const SheetLayout._({
    required this.leading,
    required this.columns,
    required this.trailing,
    required this.gap,
  });

  /// The disclosure column, or null where no row folds.
  final double? leading;

  /// One per [SheetColumn], in order.
  final List<double> columns;

  /// The menu column, or null where no row has actions.
  final double? trailing;

  /// `space.16`, between every pair of adjacent cells.
  final double gap;

  /// Divides [available] - the row's width inside its own padding - between
  /// the columns. Exposed so a test can assert the arithmetic.
  static SheetLayout resolve({
    required AppTokens tokens,
    required List<SheetColumn> columns,
    required List<SheetRow> rows,
    required double available,
    TextScaler textScaler = TextScaler.noScaling,
    TextStyle? ambient,
  }) {
    final target = tokens.density.minimumTapTarget.width;
    // A disclosure column only where some row has one to open.
    final leading = rows.any((row) => row.fold?.alwaysOpen == false)
        ? target
        : null;
    final trailing = rows.any((row) => row.actions.isNotEmpty) ? target : null;
    final gap = tokens.spacing.s16;

    double text(String value, TextStyle style) => measureTextWidth(
      value,
      style,
      textScaler: textScaler,
      ambient: ambient,
    ).ceilToDouble();

    // What each column needs to show its widest value on one line.
    final demands = <double>[];
    for (final (index, column) in columns.indexed) {
      var demand = text(_headerWords(column), tokens.typography.labelEyebrow);
      for (final row in rows) {
        demand = math.max(
          demand,
          _cellDemand(
            tokens,
            column,
            row.cells[index],
            text,
            textScaler,
            ambient,
          ),
        );
        for (final line in row.fold?.lines ?? const <SheetFoldLine>[]) {
          if (line.figures[index] case final figure?) {
            demand = math.max(demand, text(figure, _figureStyle(tokens)));
          }
          if (line.column != index) continue;
          demand = math.max(
            demand,
            text(line.value + (line.reserve ?? ''), _figureStyle(tokens)),
          );
        }
      }
      demands.add(demand);
    }

    final edges = <double?>[leading, trailing].whereType<double>();
    final gaps = gap * math.max(0, columns.length + edges.length - 1);
    final fixed = edges.fold<double>(0, (sum, width) => sum + width);
    final figures = <int>[
      for (final (index, column) in columns.indexed)
        if (!column._shares) index,
    ];
    final names = <int>[
      for (final (index, column) in columns.indexed)
        if (column._shares) index,
    ];
    final shares = names.fold<int>(0, (sum, i) => sum + columns[i].flex);
    final widest = figures.fold<double>(
      0,
      (most, i) => math.max(most, demands[i]),
    );
    // **The least a name column keeps** before the figures give way: two tap
    // targets per share, room for a name across its two lines.
    final floor = target * 2 * shares;

    List<double> laid(double figure, double Function(int index) name) =>
        <double>[
          for (final (index, column) in columns.indexed)
            column._shares ? name(index) : figure,
        ];

    final List<double> widths;
    if (!available.isFinite) {
      widths = List<double>.of(demands);
    } else {
      final room = math.max(0.0, available - gaps - fixed);
      final unit = room / (figures.length + shares);
      final namesNeed = names.fold<double>(0, (sum, i) => sum + demands[i]);
      final evenFigure = figures.isEmpty
          ? 0.0
          : (room - namesNeed) / figures.length;
      if (unit >= widest &&
          names.every((i) => unit * columns[i].flex >= demands[i])) {
        // 1. Every column equal.
        widths = laid(unit, (i) => unit * columns[i].flex);
      } else if (figures.isNotEmpty && evenFigure >= widest) {
        // 2. Names at their need, the figures equal across the rest.
        widths = laid(evenFigure, (i) => demands[i]);
      } else if (room - widest * figures.length >= floor) {
        // 3. Figures equal at the widest need; names share what is left.
        final rest = room - widest * figures.length;
        widths = laid(widest, (i) => rest * columns[i].flex / shares);
      } else {
        // 4. Each figure at its own need, scaled down together only where even
        // that does not fit, so nothing is cut to zero and no row overflows.
        final measured = figures.fold<double>(0, (sum, i) => sum + demands[i]);
        final scale = measured == 0
            ? 1.0
            : math.min(1.0, math.max(0.0, room - floor) / measured);
        final rest = math.max(0.0, room - measured * scale);
        widths = <double>[
          for (final (index, column) in columns.indexed)
            column._shares
                ? (shares == 0 ? 0 : rest * column.flex / shares)
                : demands[index] * scale,
        ];
      }
    }
    return SheetLayout._(
      leading: leading,
      columns: widths,
      trailing: trailing,
      gap: gap,
    );
  }

  static double _cellDemand(
    AppTokens tokens,
    SheetColumn column,
    SheetCell? cell,
    double Function(String, TextStyle) text,
    TextScaler textScaler,
    TextStyle? ambient,
  ) => switch (cell) {
    null => 0,
    SheetText(:final value, :final caption) => math.max(
      text(value, _textStyle(tokens, column.kind)),
      caption == null ? 0 : text(caption, tokens.typography.caption),
    ),
    // **A figure's caption asks for half its length**: it may take two lines
    // under the figure. It is usually a qualification - *At most: some lines
    // carry no cost* - that must be read whole, and asked for at full length it
    // made its one column twice the width of every other, which is the uneven
    // table equal columns exist to prevent.
    SheetFigure(:final value, :final reserve, :final caption) => math.max(
      text(value + (reserve ?? ''), _figureStyle(tokens)),
      caption == null ? 0 : (text(caption, tokens.typography.caption) / 2),
    ),
    SheetStatus(:final label, :final quiet) =>
      quiet
          ? tokens.icons.row +
                tokens.spacing.s8 +
                text(label, _bodyStyle(tokens))
          // With the ambient style, which is what the badge's `Text` merges
          // onto: without it the measure is short by Material's own letter
          // spacing and the word ellipsises.
          : StatusBadge.measureWidth(
              tokens,
              label,
              textScaler: textScaler,
              ambient: ambient,
            ).ceilToDouble(),
  };

  /// One row's cells, each in its column's width, with [gap] between them.
  /// The header, every row and every skeleton go through this, so they line up.
  List<Widget> lay({
    Widget? leading,
    required List<Widget> cells,
    Widget? trailing,
  }) {
    assert(cells.length == columns.length);
    final laid = <Widget>[];
    void add(double width, Widget? child) {
      if (laid.isNotEmpty) laid.add(SizedBox(width: gap));
      laid.add(SizedBox(width: width, child: child));
    }

    if (this.leading case final width?) add(width, leading);
    for (final (index, width) in columns.indexed) {
      add(width, cells[index]);
    }
    if (this.trailing case final width?) add(width, trailing);
    return laid;
  }

  /// A fold's line on the row's columns: [label] from [labelColumn] across
  /// every empty column after it, and each of [cells] under its own column.
  List<Widget> layFoldLine({
    required int labelColumn,
    required Widget label,
    required Map<int, Widget> cells,
  }) {
    assert(!cells.containsKey(labelColumn));
    final laid = <Widget>[];
    void add(double width, Widget? child) {
      if (laid.isNotEmpty) laid.add(SizedBox(width: gap));
      laid.add(SizedBox(width: width, child: child));
    }

    if (leading case final width?) add(width, null);
    var index = 0;
    while (index < columns.length) {
      if (index != labelColumn) {
        add(columns[index], cells[index]);
        index++;
        continue;
      }
      var end = index + 1;
      while (end < columns.length && !cells.containsKey(end)) {
        end++;
      }
      add(spanOf(index, end), label);
      index = end;
    }
    return laid;
  }

  /// The width of columns [from] up to [to], with the gaps between them.
  double spanOf(int from, int to) {
    var span = 0.0;
    for (var index = from; index < to; index++) {
      span += columns[index] + (index > from ? gap : 0);
    }
    return span;
  }

  /// How far column [index] starts in from the row's padding.
  double startOf(int index) =>
      (leading == null ? 0 : leading! + gap) +
      (index == 0 ? 0 : spanOf(0, index) + gap);
}

String _headerWords(SheetColumn column) => column.unit == null
    ? column.label.toUpperCase()
    : '${column.label.toUpperCase()} ${column.unit}';

TextStyle _figureStyle(AppTokens tokens) => tokens.typography.numericBody;

/// `body.md`, not the density's body: a table's text sits beside 14-pixel
/// figures and badges, and the comfortable density's 16 stood a word taller
/// than the figure on either side of it.
TextStyle _bodyStyle(AppTokens tokens) => tokens.typography.bodyMedium;

TextStyle _textStyle(AppTokens tokens, SheetColumnKind kind) => switch (kind) {
  SheetColumnKind.identity => tokens.typography.labelMedium,
  SheetColumnKind.time || SheetColumnKind.code => tokens.typography.numericBody,
  _ => _bodyStyle(tokens),
};

/// A list of records as one table.
final class RecordSheet extends StatelessWidget {
  const RecordSheet({
    super.key,
    required this.columns,
    required this.rows,
    this.bar,
    this.body,
    this.loadingRows = 4,
    this.loadingLabel = 'Reading the list.',
  });

  final List<SheetColumn> columns;

  /// The rows. **Null while they are read**, which draws the real header over
  /// placeholder rows shaped like the columns.
  final List<SheetRow>? rows;

  /// The screen's filters and its one action, laid on the sheet's top edge.
  final Widget? bar;

  /// Drawn in place of the header and rows - an empty or a failed state - so
  /// the sheet keeps its frame and its bar through every state.
  final Widget? body;

  /// How many placeholder rows stand in while [rows] is read.
  final int loadingRows;

  /// What a screen reader hears in place of the placeholder rows. Only the
  /// rows are announced this way: the bar and the header are real and stay
  /// readable while the list is read.
  final String loadingLabel;

  /// Whether a screen [screenWidth] wide draws this table rather than its
  /// cards: from `AppBreakpoint.expanded`, the band `RecordList` draws its own
  /// table from.
  ///
  /// **One answer for every screen**, so no two lists switch at different
  /// widths. Below it a screen's cards are unchanged - the developer's ruling on
  /// 2026-10-12 was that only the large-screen version changes.
  static bool drawnAt(double screenWidth) =>
      AppLayout.contract.isAtLeast(screenWidth, AppBreakpoint.expanded);

  /// Tables use the available page width; smaller screens keep the records cap.
  static AppContentWidth contentWidth(BuildContext context) =>
      drawnAt(MediaQuery.sizeOf(context).width)
      ? AppContentWidth.full
      : AppContentWidth.records;

  /// A desktop page has the same 24-pixel margin on every edge.
  ///
  /// The scaffold already supplies 8 above its body. A nested scroll view,
  /// below tabs or other content, supplies its whole top margin itself.
  /// Smaller screens retain the caller's existing padding.
  static EdgeInsetsGeometry pagePadding(
    BuildContext context, {
    required EdgeInsetsGeometry fallback,
    bool belowScaffold = true,
  }) {
    if (!drawnAt(MediaQuery.sizeOf(context).width)) return fallback;
    final spacing = AppTokens.componentOf(context).spacing;
    return EdgeInsets.fromLTRB(
      spacing.s24,
      belowScaffold ? spacing.s16 : spacing.s24,
      spacing.s24,
      spacing.s24,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final shape = BorderRadius.circular(tokens.radius.md);
    final inset = tokens.spacing.s24;
    final textScaler = MediaQuery.textScalerOf(context);
    final ambient = DefaultTextStyle.of(context).style;

    Widget table() => LayoutBuilder(
      builder: (context, constraints) {
        final shown = rows ?? const <SheetRow>[];
        final layout = SheetLayout.resolve(
          tokens: tokens,
          columns: columns,
          rows: shown,
          available: constraints.hasBoundedWidth
              ? constraints.maxWidth - inset * 2
              : double.infinity,
          textScaler: textScaler,
          ambient: ambient,
        );
        final drawn = <Widget>[_SheetHeader(columns: columns, layout: layout)];
        if (rows == null) {
          drawn.add(
            SkeletonGroup(
              semanticLabel: loadingLabel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (var index = 0; index < loadingRows; index++)
                    _SheetSkeletonRow(
                      columns: columns,
                      layout: layout,
                      first: index == 0,
                    ),
                ],
              ),
            ),
          );
        } else {
          for (final (index, row) in shown.indexed) {
            drawn.add(
              _SheetRowView(
                key: row.key ?? ValueKey<String>('sheet-row-${row.id}'),
                row: row,
                columns: columns,
                layout: layout,
                first: index == 0,
              ),
            );
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: drawn,
        );
      },
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.raised,
        border: Border.all(color: colors.surface.cardEdge),
        borderRadius: shape,
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (bar case final controls?)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.surface.borderSubtle),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: inset,
                    vertical: tokens.spacing.s16,
                  ),
                  child: controls,
                ),
              ),
            // An `EmptyState` pads itself by `space.24` all round; a second
            // inset around it left 48 under its sentence (2026-10-13). Any
            // other body - an error, a line of text - gets the sheet's inset.
            //
            // **Only an empty or failed state takes whatever the page leaves**,
            // so its illustration sits in one panel to the foot of the window.
            // Rows stop at the last row: a short table stretched to the foot
            // was a block of empty panel under it, and the developer asked on
            // 2026-10-14 for the table not to stretch. See [_FillsViewport].
            switch (body) {
              final EmptyState state => _FillsViewport(child: state),
              final Widget state => _FillsViewport(
                child: Padding(padding: EdgeInsets.all(inset), child: state),
              ),
              null => table(),
            },
          ],
        ),
      ),
    );
  }
}

/// Stretches [child] until the scroll view it is in reaches the bottom of the
/// window, and no further.
///
/// **Measured after layout, because it cannot be known during it.** A box in a
/// list is laid out with an unbounded height and no view of what follows it,
/// and the screens hosting a sheet scroll in five different ways. So this reads
/// the result instead: if the scroll view's content stops short of its
/// viewport, the shortfall is added to [child]'s height; if stretching has
/// pushed the content past the viewport, it is taken back. A list long enough
/// to scroll is never stretched at all.
///
/// Rows sit at the top of the extra height, and an `EmptyState` - whose own
/// `Center` sizes to the height it is given - is centred in it.
final class _FillsViewport extends StatefulWidget {
  const _FillsViewport({required this.child});

  final Widget child;

  @override
  State<_FillsViewport> createState() => _FillsViewportState();
}

final class _FillsViewportState extends State<_FillsViewport> {
  double _minHeight = 0;

  @override
  Widget build(BuildContext context) {
    // A window resized is a viewport resized: build again, and so measure.
    MediaQuery.sizeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: _minHeight),
      child: widget.child,
    );
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    if (box is! RenderBox || !box.hasSize || scrollable == null) return;
    final position = scrollable.position;
    if (!position.hasContentDimensions || !position.hasViewportDimension) {
      return;
    }
    final height = box.size.height;
    final overflow = position.maxScrollExtent - position.minScrollExtent;
    final double next;
    if (overflow > 0) {
      // Past the window: give back what stretching added, which is all a
      // list that scrolls on its own merits ever gets back to.
      if (_minHeight == 0) return;
      next = math.max(0, math.min(_minHeight, height) - overflow);
    } else {
      final content = _contentExtent(box);
      if (content == null) return;
      next = math.max(0, height + position.viewportDimension - content);
    }
    if ((next - _minHeight).abs() < 0.5) return;
    setState(() => _minHeight = next);
  }

  /// How tall everything in the scroll view is, padding included: the slivers
  /// of a list, or the one child of a `SingleChildScrollView`.
  ///
  /// Measured against the viewport's own height. Every screen's scroll view is
  /// held to the full body height by `AppScaffold`'s `Expanded`; one that is
  /// free to shrink to its content has none to give, and stays as it is.
  static double? _contentExtent(RenderObject from) {
    final viewport = RenderAbstractViewport.maybeOf(from);
    if (viewport is RenderViewportBase) {
      if (viewport.axis != Axis.vertical) return null;
      var extent = 0.0;
      var sliver = viewport.firstChild;
      while (sliver != null) {
        extent += sliver.geometry?.scrollExtent ?? 0;
        sliver = viewport.childAfter(sliver);
      }
      return extent;
    }
    if (viewport is RenderObjectWithChildMixin<RenderBox>) {
      final child = (viewport as RenderObjectWithChildMixin<RenderBox>).child;
      return child != null && child.hasSize ? child.size.height : null;
    }
    return null;
  }
}

/// The column names: `label.eyebrow` at `text.tertiary`, a unit at
/// `text.disabled`, over the sheet's one firm rule.
final class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.columns, required this.layout});

  final List<SheetColumn> columns;
  final SheetLayout layout;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final style = tokens.typography.labelEyebrow.copyWith(
      color: tokens.colors.text.tertiary,
    );
    return Container(
      height: tokens.layout.tableHeader,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s24),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: tokens.colors.surface.borderStrong),
        ),
      ),
      child: Row(
        children: layout.lay(
          cells: <Widget>[
            for (final column in columns)
              Text.rich(
                TextSpan(
                  text: column.label.toUpperCase(),
                  children: <InlineSpan>[
                    if (column.unit case final unit?)
                      TextSpan(
                        text: ' $unit',
                        style: TextStyle(color: tokens.colors.text.disabled),
                      ),
                  ],
                ),
                style: style,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                textAlign: column._alignsEnd ? TextAlign.end : TextAlign.start,
              ),
          ],
        ),
      ),
    );
  }
}

/// A placeholder row: a line in every cell, aligned the way its column is.
final class _SheetSkeletonRow extends StatelessWidget {
  const _SheetSkeletonRow({
    required this.columns,
    required this.layout,
    required this.first,
  });

  final List<SheetColumn> columns;
  final SheetLayout layout;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Container(
      constraints: BoxConstraints(minHeight: tokens.layout.tableRow),
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s24),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(color: tokens.colors.surface.borderSubtle),
              ),
      ),
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        children: layout.lay(
          cells: <Widget>[
            for (final column in columns)
              Align(
                alignment: column._alignsEnd
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: column._shares ? 0.6 : 0.8,
                  child: SkeletonLine(
                    style: column._alignsEnd
                        ? _figureStyle(tokens)
                        : _textStyle(tokens, column.kind),
                    tone: SkeletonTone.onRaised,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One record: the row's own control, its disclosure and its menu, and the
/// fold beneath it.
final class _SheetRowView extends StatefulWidget {
  const _SheetRowView({
    super.key,
    required this.row,
    required this.columns,
    required this.layout,
    required this.first,
  });

  final SheetRow row;
  final List<SheetColumn> columns;
  final SheetLayout layout;
  final bool first;

  @override
  State<_SheetRowView> createState() => _SheetRowViewState();
}

final class _SheetRowViewState extends State<_SheetRowView>
    with SingleTickerProviderStateMixin {
  SpringDrive? _drive;
  bool _open = false;

  /// Held from `build` for the reason `Disclosure` holds them: a tap can land
  /// while the tree above is being torn down.
  late AppTokens _tokens;
  bool _reducedMotion = false;

  SpringDrive get _spring => _drive ??= SpringDrive(
    vsync: this,
    spring: _tokens.motion.smooth,
    value: _open ? 1 : 0,
  );

  @override
  void dispose() {
    _drive?.dispose();
    super.dispose();
  }

  /// **From wherever the fold is**, which is the rule: a second press while it
  /// opens sends it back from where it got to, never from closed.
  void _toggle() {
    setState(() => _open = !_open);
    _spring.animateTo(_open ? 1 : 0, immediately: _reducedMotion);
  }

  @override
  Widget build(BuildContext context) {
    _tokens = AppTokens.componentOf(context);
    _reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final tokens = _tokens;
    final colors = tokens.colors;
    final row = widget.row;
    final layout = widget.layout;
    assert(
      row.cells.length == widget.columns.length,
      'Row "${row.id}" has ${row.cells.length} cells for '
      '${widget.columns.length} columns.',
    );
    final inset = tokens.spacing.s24;

    final cells = Row(
      children: layout.lay(
        cells: <Widget>[
          for (final (index, column) in widget.columns.indexed)
            _cell(tokens, column, row.cells[index]),
        ],
      ),
    );

    final surface = Semantics(
      container: true,
      button: row.onPressed != null,
      label: _spoken(),
      hint: row.semanticHint,
      onTap: row.onPressed,
      excludeSemantics: true,
      child: PressSurface(
        key: row.pressKey,
        borderRadius: BorderRadius.zero,
        onPressed: row.onPressed,
        fillWidth: true,
        ringInside: true,
        excludeSemantics: true,
        hoverOverlay: colors.action.secondary.hoverWash(),
        pressedOverlay: colors.action.secondary.pressedWash(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: tokens.layout.tableRow),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: inset,
                vertical: tokens.spacing.s8,
              ),
              child: cells,
            ),
          ),
        ),
      ),
    );

    // **The disclosure and the menu sit over the row rather than inside its
    // control**, in the columns kept for them: a control nested in another is
    // a tap a person cannot predict and a pair of buttons a screen reader
    // reads as one.
    final controls = layout.leading == null && layout.trailing == null
        ? null
        : Positioned.fill(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: Row(
                children: <Widget>[
                  if (layout.leading case final width?)
                    SizedBox(
                      width: width,
                      child: row.fold?.alwaysOpen == false
                          ? _disclosure(tokens)
                          : null,
                    ),
                  const Spacer(),
                  if (layout.trailing case final width?)
                    SizedBox(
                      width: width,
                      child: row.actions.isEmpty
                          ? null
                          : RecordOverflowMenu(
                              key: row.actionsKey,
                              actions: row.actions,
                              tooltip: row.actionsTooltip,
                            ),
                    ),
                ],
              ),
            ),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: widget.first
            ? null
            : Border(top: BorderSide(color: colors.surface.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Stack(
            children: <Widget>[surface, if (controls case final over?) over],
          ),
          if (row.fold case final fold?)
            fold.alwaysOpen ? _foldBody(tokens, fold) : _reveal(tokens, fold),
        ],
      ),
    );
  }

  /// The row as one sentence: the caller's own words, then every other cell
  /// under its column's name, so a unit moved into the header is still heard.
  String _spoken() {
    final parts = <String>[if (widget.row.semanticLabel case final lead?) lead];
    for (final (index, column) in widget.columns.indexed) {
      final cell = widget.row.cells[index];
      final said = switch (cell) {
        null => null,
        SheetText(:final value, :final caption) =>
          column.kind == SheetColumnKind.identity &&
                  widget.row.semanticLabel != null
              ? null
              : '${column._spoken}: $value${caption == null ? '' : ', $caption'}',
        SheetFigure(:final value, :final caption, :final known) =>
          '${column._spoken}: ${known ? value : 'not known'}'
              '${caption == null ? '' : ', $caption'}',
        SheetStatus(:final label, :final semanticLabel) =>
          semanticLabel ?? label,
      };
      if (said != null) parts.add(said);
    }
    return parts.join('. ');
  }

  Widget _cell(AppTokens tokens, SheetColumn column, SheetCell? cell) {
    final colors = tokens.colors;
    final caption = tokens.typography.caption.copyWith(
      color: colors.text.tertiary,
    );
    switch (cell) {
      case null:
        return const SizedBox.shrink();
      case SheetText(
        :final value,
        caption: final under,
        :final key,
        :final captionKey,
      ):
        final style = _textStyle(tokens, column.kind).copyWith(
          color: column.kind == SheetColumnKind.identity
              ? colors.text.primary
              : colors.text.secondary,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              value,
              key: key,
              style: style,
              maxLines: column.kind == SheetColumnKind.identity ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (under != null)
              Text(
                under,
                key: captionKey,
                style: caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        );
      case SheetFigure(
        :final value,
        :final reserve,
        caption: final under,
        :final key,
        :final captionKey,
        :final known,
      ):
        final style = _figureStyle(
          tokens,
        ).copyWith(color: known ? colors.text.primary : colors.text.tertiary);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // **Scaled down rather than cut or overflowing**, in the one layout
            // that can hand a figure less than it needs - [SheetLayout]'s last
            // step, on a window too narrow for the columns. Everywhere else
            // the column was sized to it and this draws it at its own size.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(value, key: key, style: style, maxLines: 1),
                  if (reserve != null)
                    ExcludeSemantics(
                      child: Opacity(
                        opacity: 0,
                        child: Text(reserve, style: style, maxLines: 1),
                      ),
                    ),
                ],
              ),
            ),
            if (under != null)
              Text(
                under,
                key: captionKey,
                style: caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
          ],
        );
      case SheetStatus(
        :final status,
        :final label,
        :final icon,
        :final semanticLabel,
        :final quiet,
        :final key,
      ):
        if (!quiet) {
          // Scaled down in [SheetLayout]'s last step, as a figure is.
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: StatusBadge(
              key: key,
              status: status,
              label: label,
              icon: icon,
              semanticLabel: semanticLabel,
            ),
          );
        }
        return Row(
          key: key,
          children: <Widget>[
            Icon(
              icon ?? status.defaultIcon,
              size: tokens.icons.row,
              color: status.role(tokens).fg,
            ),
            SizedBox(width: tokens.spacing.s8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _bodyStyle(
                  tokens,
                ).copyWith(color: colors.text.secondary),
              ),
            ),
          ],
        );
    }
  }

  Widget _disclosure(AppTokens tokens) {
    final fold = widget.row.fold!;
    final drive = _spring;
    return Center(
      child: Semantics(
        button: true,
        expanded: _open,
        label: _open ? fold.hideLabel : fold.showLabel,
        onTap: _toggle,
        excludeSemantics: true,
        child: PressSurface(
          key: fold.toggleKey,
          borderRadius: BorderRadius.circular(tokens.radius.md),
          onPressed: _toggle,
          ringInside: true,
          excludeSemantics: true,
          hoverOverlay: tokens.colors.action.secondary.hoverWash(),
          pressedOverlay: tokens.colors.action.secondary.pressedWash(),
          child: SizedBox.square(
            dimension: tokens.density.minimumTapTarget.width,
            child: Center(
              // The chevron turns on the spring the fold opens on, so the two
              // cannot disagree mid-flight.
              child: AnimatedBuilder(
                animation: drive.animation,
                builder: (context, child) => Transform.rotate(
                  angle: drive.value * math.pi,
                  child: child,
                ),
                child: Icon(
                  Icons.expand_more,
                  size: tokens.icons.row,
                  color: tokens.colors.text.secondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The fold: `Disclosure`'s reveal of [_foldBody].
  Widget _reveal(AppTokens tokens, SheetFold fold) {
    final drive = _spring;
    return AnimatedBuilder(
      animation: drive.animation,
      builder: (context, child) {
        final extent = drive.value.clamp(0.0, 1.0);
        // Closed is gone from the tree, not clipped to nothing, so a screen
        // reader does not read figures nobody can see. See `Disclosure`.
        if (!_open && extent <= Tolerance.defaultTolerance.distance) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            heightFactor: extent,
            child: child,
          ),
        );
      },
      child: _foldBody(tokens, fold),
    );
  }

  /// What a fold holds, **on the row's own surface** and laid on the row's
  /// columns, so a figure in it sits under the figure it explains and the
  /// record and its lines read as one block between two rules.
  Widget _foldBody(AppTokens tokens, SheetFold fold) {
    final colors = tokens.colors;
    final layout = widget.layout;
    final body = _bodyStyle(tokens).copyWith(color: colors.text.secondary);
    final figure = _figureStyle(tokens).copyWith(color: colors.text.secondary);
    Widget figureCell(String value, {String? reserve, Key? key}) => Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(value, key: key, style: figure),
          if (reserve != null)
            ExcludeSemantics(
              child: Opacity(
                opacity: 0,
                child: Text(reserve, style: figure),
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.s24,
        0,
        tokens.spacing.s24,
        tokens.spacing.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (fold.note case final note?)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: layout.startOf(fold.noteColumn),
                bottom: tokens.spacing.s4,
              ),
              child: Text(note, key: fold.noteKey, style: body),
            ),
          for (final line in fold.lines)
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: tokens.spacing.s32),
              child: Row(
                children: layout.layFoldLine(
                  labelColumn: line.labelColumn,
                  label: Text(
                    line.label,
                    style: body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  cells: <int, Widget>{
                    for (final MapEntry(:key, :value) in line.figures.entries)
                      key: figureCell(value),
                    line.column: figureCell(
                      line.value,
                      reserve: line.reserve,
                      key: line.valueKey,
                    ),
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
