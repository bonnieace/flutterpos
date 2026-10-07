/// The dashboard tile: the one component the platform console's overview is
/// made of, and the visuals it holds.
///
/// **One anatomy, every size.** A header (a glyph chip in the tile's hue, the
/// label as an eyebrow, a chevron), a value line (a figure and its context), a
/// visual band of fixed height, and a footnote. Because the band is fixed, every
/// tile in a row is the same height without anyone placing it. Drawn from
/// `docs/design/platform-console`, 2026-10-06.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'press.dart';
import 'tokens.dart';

/// How many of the grid's columns a tile spans.
enum AppDashSpan { one, two }

/// One tile in an [AppDashGrid].
final class AppDashTile extends StatelessWidget {
  const AppDashTile({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.visual,
    this.detail,
    this.footnote,
    this.footer,
    this.span = AppDashSpan.one,
    this.tall = false,
    this.problem = false,
    this.onPressed,
    this.valueKey,
    this.fitsContentOnPhone = false,
  });

  final IconData icon;

  /// The tile's hue: its chip's glyph, and the chip at 15%. Ignored when
  /// [problem], which takes the problem role instead.
  final Color accent;

  /// The eyebrow. Drawn upper-case; written in sentence case.
  final String label;

  /// The figure.
  final String value;

  /// What the figure counts, beside it.
  final String? detail;

  /// The band under the value line: [AppSparkBars], [AppSegmentBar],
  /// [AppGrowthChart], [AppDashLines] or [AppDashList].
  final Widget visual;

  final String? footnote;

  /// A widget in the footnote's place, for a legend.
  final Widget? footer;

  final AppDashSpan span;

  /// The tall band ([AppLayout.dashVisualTall]) rather than the compact one.
  final bool tall;

  /// The figure is a problem: the chip and the figure take the problem role.
  final bool problem;

  /// Opens what the tile summarises. The whole tile is the target.
  final VoidCallback? onPressed;

  final Key? valueKey;

  /// On a phone, the band is as tall as [visual] rather than the fixed tall
  /// band. A tall tile has the whole row to itself there, so nothing needs it
  /// to match a neighbour, and a fixed band under two short lines is empty
  /// space. For list and message visuals only: a chart has no height of its
  /// own and keeps the fixed band.
  final bool fitsContentOnPhone;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final compact =
        MediaQuery.sizeOf(context).width < tokens.layout.mediumFloor;
    final problemRole = colors.status.problem;
    final radius = BorderRadius.circular(tokens.radius.lg);
    final tile = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.raised,
        border: Border.all(color: colors.surface.cardEdge),
        borderRadius: radius,
      ),
      child: Padding(
        padding: EdgeInsets.all(
          compact ? tokens.spacing.s16 : tokens.spacing.s20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: tokens.spacing.s32,
              child: Row(
                children: <Widget>[
                  Container(
                    width: tokens.spacing.s32,
                    height: tokens.spacing.s32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: problem
                          ? problemRole.bg
                          : accent.withValues(alpha: _chipAlpha),
                      borderRadius: BorderRadius.circular(tokens.radius.md),
                    ),
                    child: Icon(
                      icon,
                      size: tokens.icons.row,
                      color: problem ? problemRole.fg : accent,
                    ),
                  ),
                  SizedBox(width: tokens.spacing.s12),
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.labelEyebrow.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                  if (onPressed != null)
                    Icon(
                      Icons.chevron_right,
                      size: tokens.icons.card,
                      color: colors.text.tertiary,
                    ),
                ],
              ),
            ),
            SizedBox(height: tokens.spacing.s12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  value,
                  key: valueKey,
                  style:
                      (compact
                              ? tokens.typography.numericCompact
                              : tokens.typography.numericHero)
                          .copyWith(
                            color: problem
                                ? problemRole.fg
                                : colors.text.primary,
                          ),
                ),
                if (detail != null) ...[
                  SizedBox(width: tokens.spacing.s8),
                  Expanded(
                    child: Text(
                      detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (compact
                                  ? tokens.typography.caption
                                  : tokens.typography.bodyMedium)
                              .copyWith(color: colors.text.secondary),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: tokens.spacing.s12),
            if (compact && tall && fitsContentOnPhone)
              visual
            else
              SizedBox(
                height: tall
                    ? tokens.layout.dashVisualTall
                    : tokens.layout.dashVisualCompact,
                child: visual,
              ),
            SizedBox(height: tokens.spacing.s12),
            footer ??
                Text(
                  footnote ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.caption.copyWith(
                    color: colors.text.tertiary,
                  ),
                ),
          ],
        ),
      ),
    );
    if (onPressed == null) return tile;
    return PressSurface(
      borderRadius: radius,
      onPressed: onPressed,
      hoverOverlay: colors.action.tertiary.hoverWash(),
      pressedOverlay: colors.action.tertiary.pressedWash(),
      reservesRingGutter: false,
      fillWidth: true,
      semanticLabel: '$label, $value${detail == null ? '' : ' $detail'}',
      child: tile,
    );
  }

  /// The chip's tint: the hue at 15%, as the design draws every chip.
  static const double _chipAlpha = 0.15;
}

/// Lays [AppDashTile]s out four to a row, two to a row below `medium`, with
/// every tile in a row stretched to the row's height.
final class AppDashGrid extends StatelessWidget {
  const AppDashGrid({super.key, required this.tiles});

  final List<AppDashTile> tiles;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < tokens.layout.mediumFloor;
    // Four across only where a quarter of the page still holds a tile's list
    // line; two across from a phone up to `expanded`.
    final columns = width < tokens.layout.expandedFloor ? 2 : 4;
    final gap = compact ? tokens.spacing.s8 : tokens.spacing.s16;
    final rows = <List<AppDashTile>>[];
    var used = columns;
    for (final tile in tiles) {
      final width = _spanOf(tile, compact);
      if (used + width > columns) {
        rows.add(<AppDashTile>[]);
        used = 0;
      }
      rows.last.add(tile);
      used += width;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var cell = 0; cell < rows[index].length; cell++) ...[
                  if (cell > 0) SizedBox(width: gap),
                  Expanded(
                    flex: _spanOf(rows[index][cell], compact),
                    child: rows[index][cell],
                  ),
                ],
                // A short last row keeps its tiles at their column width.
                if (_used(rows[index], compact) < columns) ...[
                  SizedBox(width: gap),
                  Expanded(
                    flex: columns - _used(rows[index], compact),
                    child: const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// A tall tile takes the whole width on a phone: its list lines do not fit
  /// half of one.
  static int _spanOf(AppDashTile tile, bool compact) =>
      tile.span == AppDashSpan.two || (compact && tile.tall) ? 2 : 1;

  static int _used(List<AppDashTile> row, bool compact) =>
      row.fold(0, (sum, tile) => sum + _spanOf(tile, compact));
}

/// Weekly bars, no axes: the last bar in `chart.barEmphasis`, the rest in
/// `chart.series[3]`, an empty week as a stub on the baseline.
final class AppSparkBars extends StatelessWidget {
  const AppSparkBars({
    super.key,
    required this.values,
    required this.semanticLabel,
  });

  final List<int> values;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.infinite,
          painter: _SparkPainter(values: values, tokens: tokens),
        ),
      ),
    );
  }
}

final class _SparkPainter extends CustomPainter {
  const _SparkPainter({required this.values, required this.tokens});

  final List<int> values;
  final AppTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final chart = tokens.colors.chart;
    final maxValue = math.max(1, values.reduce(math.max));
    final gapShare = 0.36;
    final slot = size.width / (values.length - gapShare);
    final width = slot * (1 - gapShare);
    for (var index = 0; index < values.length; index++) {
      final left = index * slot;
      final value = values[index];
      final last = index == values.length - 1;
      if (value <= 0) {
        canvas.drawRect(
          Rect.fromLTWH(
            left,
            size.height - tokens.layout.chartStub,
            width,
            tokens.layout.chartStub,
          ),
          Paint()..color = tokens.colors.surface.cardEdge,
        );
        continue;
      }
      final height = math.max(
        tokens.layout.chartStub,
        value / maxValue * size.height,
      );
      canvas.drawRect(
        Rect.fromLTWH(left, size.height - height, width, height),
        Paint()..color = last ? chart.barEmphasis : chart.series[3],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.values != values || old.tokens != tokens;
}

/// One part of an [AppSegmentBar].
@immutable
final class AppSegment {
  const AppSegment({
    required this.count,
    required this.color,
    required this.icon,
    required this.label,
  });

  final int count;
  final Color color;
  final IconData icon;

  /// What the segment is, for the bar's accessible description.
  final String label;
}

/// A capsule split by share, with a legend of glyph and count under it: the
/// glyph, not the hue, is what tells the parts apart.
final class AppSegmentBar extends StatelessWidget {
  const AppSegmentBar({super.key, required this.segments});

  final List<AppSegment> segments;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final shown = segments.where((segment) => segment.count > 0).toList();
    return Semantics(
      label: segments.map((s) => '${s.count} ${s.label}').join(', '),
      child: ExcludeSemantics(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radius.pill),
              child: SizedBox(
                height: tokens.spacing.s12,
                child: Row(
                  children: <Widget>[
                    for (var index = 0; index < shown.length; index++) ...[
                      if (index > 0) SizedBox(width: tokens.layout.chartStub),
                      Expanded(
                        flex: shown[index].count,
                        child: ColoredBox(
                          color: shown[index].color,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: tokens.spacing.s12),
            Row(
              children: <Widget>[
                for (var index = 0; index < segments.length; index++) ...[
                  if (index > 0) SizedBox(width: tokens.spacing.s12),
                  Icon(
                    segments[index].icon,
                    size: tokens.icons.row,
                    color: segments[index].color,
                  ),
                  SizedBox(width: tokens.spacing.s4),
                  Text(
                    '${segments[index].count}',
                    style: tokens.typography.caption.copyWith(
                      color: tokens.colors.text.secondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of an [AppDashLines] band.
@immutable
final class AppDashLine {
  const AppDashLine({
    required this.icon,
    required this.color,
    required this.text,
    this.meta,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String? meta;
}

/// Short lines in a compact band: a glyph, a name, a figure at the end.
final class AppDashLines extends StatelessWidget {
  const AppDashLines({super.key, required this.lines});

  final List<AppDashLine> lines;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: <Widget>[
        for (final line in lines)
          SizedBox(
            height: tokens.spacing.s24,
            child: Row(
              children: <Widget>[
                Icon(line.icon, size: tokens.icons.row, color: line.color),
                SizedBox(width: tokens.spacing.s8),
                Expanded(
                  child: Text(
                    line.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.bodyMedium.copyWith(
                      color: tokens.colors.text.primary,
                    ),
                  ),
                ),
                if (line.meta != null) ...[
                  SizedBox(width: tokens.spacing.s8),
                  Text(
                    line.meta!,
                    style: tokens.typography.caption.copyWith(
                      color: tokens.colors.text.tertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// One row of an [AppDashList].
@immutable
final class AppDashListItem {
  const AppDashListItem({
    required this.icon,
    required this.color,
    required this.title,
    this.meta,
    this.trailing,
    this.problem = false,
    this.tall = false,
  });

  final IconData icon;
  final Color color;

  /// Rich so a name can be bold inside a sentence.
  final InlineSpan title;

  /// Under the title when [tall], at the end of the line otherwise.
  final String? meta;

  /// A time or a figure at the end of a line.
  final String? trailing;

  /// The glyph well takes the problem role.
  final bool problem;

  /// Two lines - a title that may wrap and a meta line under it - in half the
  /// tall band, rather than one line of [AppLayout.dashListLine].
  final bool tall;
}

/// Rows in a tall band, separated by hairlines.
final class AppDashList extends StatelessWidget {
  const AppDashList({super.key, required this.items});

  final List<AppDashListItem> items;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < items.length; index++)
          DecoratedBox(
            decoration: BoxDecoration(
              border: index == 0
                  ? null
                  : Border(
                      top: BorderSide(
                        color: colors.surface.borderSubtle,
                        width: tokens.layout.chartHairline,
                      ),
                    ),
            ),
            child: SizedBox(
              height: items[index].tall
                  ? tokens.layout.dashVisualTall / 2
                  : tokens.layout.dashListLine,
              child: _DashListRow(item: items[index], tokens: tokens),
            ),
          ),
      ],
    );
  }
}

final class _DashListRow extends StatelessWidget {
  const _DashListRow({required this.item, required this.tokens});

  final AppDashListItem item;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final colors = tokens.colors;
    final problem = colors.status.problem;
    final well = Container(
      width: tokens.spacing.s32,
      height: tokens.spacing.s32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: item.problem ? problem.bg : colors.surface.field,
        border: Border.all(
          color: item.problem ? problem.border : colors.surface.cardEdge,
        ),
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Icon(item.icon, size: tokens.icons.row, color: item.color),
    );
    final titleStyle = tokens.typography.bodyMedium.copyWith(
      color: colors.text.primary,
    );
    final metaStyle = tokens.typography.caption.copyWith(
      color: colors.text.tertiary,
    );
    if (item.tall) {
      return Padding(
        padding: EdgeInsets.only(top: tokens.spacing.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            well,
            SizedBox(width: tokens.spacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text.rich(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.labelMedium.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                  if (item.meta != null) ...[
                    SizedBox(height: tokens.spacing.s4),
                    Text(
                      item.meta!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: tokens.spacing.s8),
            Icon(
              Icons.chevron_right,
              size: tokens.icons.card,
              color: colors.text.tertiary,
            ),
          ],
        ),
      );
    }
    return Row(
      children: <Widget>[
        well,
        SizedBox(width: tokens.spacing.s12),
        Expanded(
          flex: 3,
          child: Text.rich(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
        if (item.trailing != null) ...[
          SizedBox(width: tokens.spacing.s8),
          Flexible(
            child: Text(
              item.trailing!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: metaStyle,
            ),
          ),
        ],
      ],
    );
  }
}

/// Twelve weeks of growth: new accounts as bars against the left scale, new
/// businesses as a dotted line against the right one. The two differ in shape
/// as well as hue, and the legend names both.
final class AppGrowthChart extends StatelessWidget {
  const AppGrowthChart({
    super.key,
    required this.bars,
    required this.line,
    required this.weekLabels,
    required this.semanticLabel,
  }) : assert(bars.length == line.length);

  final List<int> bars;
  final List<int> line;

  /// Labels under particular weeks, by index.
  final Map<int, String> weekLabels;

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.infinite,
          painter: _GrowthPainter(
            bars: bars,
            line: line,
            weekLabels: weekLabels,
            tokens: tokens,
            textScaler: MediaQuery.textScalerOf(context),
          ),
        ),
      ),
    );
  }
}

final class _GrowthPainter extends CustomPainter {
  const _GrowthPainter({
    required this.bars,
    required this.line,
    required this.weekLabels,
    required this.tokens,
    required this.textScaler,
  });

  final List<int> bars;
  final List<int> line;
  final Map<int, String> weekLabels;
  final AppTokens tokens;
  final TextScaler textScaler;

  /// A scale's top: the smallest of 4, 8, 20, 40, 100... that holds [value],
  /// so the middle gridline is a whole number.
  static int niceCeiling(int value) {
    var step = 4;
    for (final candidate in <int>[4, 8, 20, 40, 100, 200, 400, 1000]) {
      step = candidate;
      if (value <= candidate) return candidate;
    }
    while (step < value) {
      step *= 2;
    }
    return step;
  }

  TextPainter _label(String text, Color color) => TextPainter(
    text: TextSpan(
      text: text,
      style: tokens.typography.caption.copyWith(color: color),
    ),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final chart = tokens.colors.chart;
    final barTop = niceCeiling(bars.reduce(math.max));
    final lineTop = niceCeiling(line.reduce(math.max));
    final labelBand =
        tokens.typography.caption.fontSize! *
            (tokens.typography.caption.height ?? 1) +
        tokens.spacing.s8;
    final plotTop = tokens.spacing.s8;
    final base = size.height - labelBand;
    final plotHeight = base - plotTop;

    final leftLabels = <TextPainter>[
      for (final value in <int>[0, barTop ~/ 2, barTop])
        _label('$value', chart.axisLabel),
    ];
    final rightLabels = <TextPainter>[
      for (final value in <int>[0, lineTop ~/ 2, lineTop])
        _label('$value', chart.series[1]),
    ];
    final leftGutter =
        leftLabels.map((p) => p.width).reduce(math.max) + tokens.spacing.s8;
    final rightGutter =
        rightLabels.map((p) => p.width).reduce(math.max) + tokens.spacing.s8;
    final plotLeft = leftGutter;
    final plotRight = size.width - rightGutter;

    final grid = Paint()
      ..color = chart.gridLine
      ..strokeWidth = tokens.layout.chartHairline;
    for (var index = 0; index < 3; index++) {
      final y = base - plotHeight * index / 2;
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), grid);
      final left = leftLabels[index];
      left.paint(
        canvas,
        Offset(
          leftGutter - tokens.spacing.s8 - left.width,
          y - left.height / 2,
        ),
      );
      final right = rightLabels[index];
      right.paint(
        canvas,
        Offset(plotRight + tokens.spacing.s8, y - right.height / 2),
      );
    }

    final count = bars.length;
    final gap = size.width > tokens.layout.mediumFloor / 2
        ? tokens.spacing.s8
        : tokens.spacing.s4;
    final width = (plotRight - plotLeft - gap * (count - 1)) / count;
    final barRadius = Radius.circular(tokens.radius.sm);
    final points = <Offset>[];
    for (var index = 0; index < count; index++) {
      final left = plotLeft + index * (width + gap);
      final height = bars[index] / barTop * plotHeight;
      if (bars[index] > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(left, base - height, width, height),
            topLeft: barRadius,
            topRight: barRadius,
          ),
          Paint()
            ..color = index == count - 1 ? chart.barEmphasis : chart.series[3],
        );
      }
      points.add(
        Offset(left + width / 2, base - line[index] / lineTop * plotHeight),
      );
      final label = weekLabels[index];
      if (label != null) {
        final painter = _label(label, chart.axisLabel);
        final x = index == count - 1
            ? plotRight - painter.width
            : left + width / 2 - painter.width / 2;
        painter.paint(canvas, Offset(x, base + tokens.spacing.s8));
      }
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = chart.series[1]
        ..style = PaintingStyle.stroke
        ..strokeWidth = tokens.layout.chartLine
        ..strokeJoin = StrokeJoin.round,
    );
    for (final point in points) {
      canvas.drawCircle(
        point,
        tokens.layout.chartDot,
        Paint()..color = tokens.colors.surface.raised,
      );
      canvas.drawCircle(
        point,
        tokens.layout.chartDot - tokens.layout.chartHairline,
        Paint()..color = chart.series[1],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GrowthPainter old) =>
      old.bars != bars ||
      old.line != line ||
      old.weekLabels != weekLabels ||
      old.tokens != tokens ||
      old.textScaler != textScaler;
}

/// The legend under an [AppGrowthChart]: a square for the bars, a dot for the
/// line, each with its name.
final class AppGrowthLegend extends StatelessWidget {
  const AppGrowthLegend({
    super.key,
    required this.barsLabel,
    required this.lineLabel,
  });

  final String barsLabel;
  final String lineLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final chart = tokens.colors.chart;
    final style = tokens.typography.caption.copyWith(
      color: tokens.colors.text.tertiary,
    );
    Widget swatch(Color color, BoxShape shape) => Container(
      width: tokens.spacing.s8,
      height: tokens.spacing.s8,
      decoration: BoxDecoration(
        color: color,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle
            ? BorderRadius.circular(tokens.radius.sm)
            : null,
      ),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        swatch(chart.series[3], BoxShape.rectangle),
        SizedBox(width: tokens.spacing.s8),
        Text(barsLabel, style: style, maxLines: 1),
        SizedBox(width: tokens.spacing.s16),
        const Spacer(),
        swatch(chart.series[1], BoxShape.circle),
        SizedBox(width: tokens.spacing.s8),
        Flexible(
          flex: 8,
          child: Text(
            lineLabel,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
