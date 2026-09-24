/// The five shapes a report draws, in vector, on paper.
///
/// **Drawn natively, never captured.** `fl_chart` is a Flutter widget: getting
/// a picture of one means mounting a render tree, pumping a frame and calling
/// `toImage`, which would tie report generation to a live widget that can be
/// disposed halfway through, rasterise every label so the document stops being
/// searchable, and put a chart drawn for a near-black screen onto white paper.
/// The `pdf` package carries its own vector chart engine, so these are real
/// vectors at whatever resolution the thing is eventually printed at, and the
/// whole renderer stays callable from a plain `test`.
///
/// **Two of the five are not charts at all, on purpose.** A ranked listing and
/// a variance listing are drawn as proportional rows rather than through the
/// chart engine: on a page, a row carrying its own label and figure beside a
/// filled bar is more precise than an axis, it cannot overlap its neighbours,
/// and it degrades to a readable table when there are thirty of them. The chart
/// engine is used where an axis genuinely earns its space - a trend over time,
/// two periods side by side, and parts of a whole.
///
/// **Every one of them prints its figures.** Hard rule 4 says a colour never
/// carries a fact alone, and here that is not a convention each caller has to
/// remember: [TenantReportVisual] cannot be built without its labelled data, and
/// every primitive below draws the rows from the same list the picture is
/// plotted from. They cannot disagree, because there is only one list.
library;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../report_metrics.dart';
import '../report_visual.dart';
import 'report_fonts.dart';
import 'report_palette.dart';

/// Draws a [TenantReportVisual] as a block of page.
abstract final class TenantReportCharts {
  const TenantReportCharts._();

  /// The picture for [visual], with its caption above and its figures below.
  ///
  /// A renderer calls this and never chooses a shape itself - the analysis
  /// decided what kind of thing it was describing, and the drawing follows.
  static pw.Widget forVisual(
    TenantReportVisual visual, {
    required TenantReportPalette palette,
    required TenantReportFonts fonts,
  }) {
    final picture = switch (visual.kind) {
      TenantReportVisualKind.comparison => _comparison(visual, palette, fonts),
      TenantReportVisualKind.trend => _trend(visual, palette, fonts),
      TenantReportVisualKind.composition => _composition(visual, palette, fonts),
      TenantReportVisualKind.ranked => _ranked(visual, palette, fonts),
      TenantReportVisualKind.variance => _variance(visual, palette, fonts),
    };

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        picture,
        pw.SizedBox(height: TenantReportMetrics.spaceItem),
        _figures(visual, palette, fonts),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // The three the chart engine draws
  // ---------------------------------------------------------------------------

  /// This period against the one before it, bar beside bar.
  ///
  /// The two series sit half a bar either side of their tick, which is what
  /// makes them read as a pair rather than as one series hiding another.
  static pw.Widget _comparison(
    TenantReportVisual visual,
    TenantReportPalette palette,
    TenantReportFonts fonts,
  ) {
    final ceiling = TenantReportMetrics.axisCeilingFor(visual.peak);
    final paired = visual.hasComparison;

    return pw.SizedBox(
      height: TenantReportMetrics.chartHeight,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: _categoryAxis(
            visual.data.map((d) => d.label).toList(),
            palette,
            fonts,
          ),
          yAxis: pw.FixedAxis<double>(
            _ticks(0, ceiling),
            format: _compact,
            textStyle: _axisStyle(palette, fonts),
            color: palette.rule,
            width: TenantReportMetrics.gridLineWidth,
            divisions: true,
            divisionsColor: palette.gridLine,
            divisionsWidth: TenantReportMetrics.gridLineWidth,
          ),
        ),
        datasets: <pw.Dataset>[
          if (paired)
            pw.BarDataSet<pw.PointChartValue>(
              legend: visual.comparisonLabel,
              color: palette.bar,
              width: TenantReportMetrics.groupedBarWidth,
              offset: -TenantReportMetrics.groupedBarOffset,
              data: <pw.PointChartValue>[
                for (var i = 0; i < visual.data.length; i++)
                  pw.PointChartValue(
                    i.toDouble(),
                    visual.data[i].comparison ?? 0,
                  ),
              ],
            ),
          pw.BarDataSet<pw.PointChartValue>(
            legend: visual.valueAxisLabel,
            color: palette.barEmphasis,
            width: paired
                ? TenantReportMetrics.groupedBarWidth
                : TenantReportMetrics.barWidth,
            offset: paired ? TenantReportMetrics.groupedBarOffset : 0,
            data: <pw.PointChartValue>[
              for (var i = 0; i < visual.data.length; i++)
                pw.PointChartValue(i.toDouble(), visual.data[i].value),
            ],
          ),
        ],
      ),
    );
  }

  /// A value across the days of the period.
  static pw.Widget _trend(
    TenantReportVisual visual,
    TenantReportPalette palette,
    TenantReportFonts fonts,
  ) {
    final ceiling = TenantReportMetrics.axisCeilingFor(visual.peak);
    final interval = TenantReportMetrics.trendLabelInterval(visual.data.length);
    final plotPoints =
        visual.data.length <= TenantReportMetrics.maximumPlottedPoints;

    return pw.SizedBox(
      height: TenantReportMetrics.chartHeight,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: _categoryAxis(
            <String>[
              for (var i = 0; i < visual.data.length; i++)
                // Every label on a ninety-day axis is unreadable overlap. The
                // first and the last always print - they are the two a reader
                // looks for to know what they are looking at.
                if (i == 0 ||
                    i == visual.data.length - 1 ||
                    i % interval == 0)
                  visual.data[i].label
                else
                  '',
            ],
            palette,
            fonts,
          ),
          yAxis: pw.FixedAxis<double>(
            _ticks(0, ceiling),
            format: _compact,
            textStyle: _axisStyle(palette, fonts),
            color: palette.rule,
            width: TenantReportMetrics.gridLineWidth,
            divisions: true,
            divisionsColor: palette.gridLine,
            divisionsWidth: TenantReportMetrics.gridLineWidth,
          ),
        ),
        datasets: <pw.Dataset>[
          if (visual.hasComparison)
            pw.LineDataSet<pw.PointChartValue>(
              legend: visual.comparisonLabel,
              color: palette.bar,
              lineWidth: TenantReportMetrics.gridLineWidth * 2,
              drawPoints: false,
              isCurved: true,
              data: <pw.PointChartValue>[
                for (var i = 0; i < visual.data.length; i++)
                  pw.PointChartValue(
                    i.toDouble(),
                    visual.data[i].comparison ?? 0,
                  ),
              ],
            ),
          pw.LineDataSet<pw.PointChartValue>(
            legend: visual.valueAxisLabel,
            color: palette.barEmphasis,
            lineWidth: TenantReportMetrics.chartLineWidth,
            drawSurface: true,
            surfaceOpacity: TenantReportMetrics.areaOpacity,
            drawPoints: plotPoints,
            pointSize: TenantReportMetrics.pointRadius,
            pointColor: palette.barEmphasis,
            isCurved: true,
            data: <pw.PointChartValue>[
              for (var i = 0; i < visual.data.length; i++)
                pw.PointChartValue(i.toDouble(), visual.data[i].value),
            ],
          ),
        ],
      ),
    );
  }

  /// Parts of one whole, as a ring.
  ///
  /// A ring rather than a full pie because the hole is where the total goes,
  /// which is the figure a reader wants first and the one a pie has nowhere to
  /// put.
  static pw.Widget _composition(
    TenantReportVisual visual,
    TenantReportPalette palette,
    TenantReportFonts fonts,
  ) {
    // A period in which nothing was spent draws no ring at all. A single grey
    // circle would claim one undifferentiated something, which is a different
    // fact from nothing, and the figures below still say so in words.
    if (visual.total <= 0) {
      return pw.SizedBox(height: TenantReportMetrics.spaceTight);
    }

    final drawable = visual.data.where((d) => d.value > 0).toList();

    return pw.SizedBox(
      height: TenantReportMetrics.compositionHeight,
      child: pw.Chart(
        grid: pw.PieGrid(startAngle: TenantReportMetrics.donutStartAngle),
        datasets: <pw.Dataset>[
          for (var i = 0; i < drawable.length; i++)
            pw.PieDataSet(
              legend: drawable[i].label,
              value: drawable[i].value,
              color: palette.seriesAt(visual.data.indexOf(drawable[i])),
              innerRadius: TenantReportMetrics.donutInnerRadius,
              borderColor: palette.paper,
              legendStyle: _captionStyle(palette, fonts),
              legendPosition: pw.PieLegendPosition.auto,
              legendOffset: TenantReportMetrics.spaceBlock,
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // The two drawn as rows
  // ---------------------------------------------------------------------------

  /// Largest to smallest, each on its own line.
  ///
  /// Proportional flex rather than a measured width, because a `pw.Widget` does
  /// not know the page width until it lays out. A thousandth is finer than the
  /// eye can read off a bar, so nothing is lost to the rounding.
  static pw.Widget _ranked(
    TenantReportVisual visual,
    TenantReportPalette palette,
    TenantReportFonts fonts,
  ) {
    final ordered = visual.data.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = ordered
        .take(TenantReportMetrics.rankedMaximumRows.toInt())
        .toList();
    final largest = shown.isEmpty ? 0.0 : shown.first.value;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        for (final datum in shown)
          pw.Padding(
            padding: pw.EdgeInsets.only(
              bottom: TenantReportMetrics.legendRowGap,
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: <pw.Widget>[
                pw.SizedBox(
                  width: TenantReportMetrics.pageWidth / 5,
                  child: pw.Text(
                    datum.label,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: _bodyStyle(palette, fonts),
                  ),
                ),
                pw.SizedBox(width: TenantReportMetrics.spaceRow),
                pw.Expanded(
                  child: _proportionalBar(
                    fraction: largest <= 0 ? 0 : datum.value / largest,
                    colour: datum.emphasis
                        ? palette.barEmphasis
                        : palette.bar,
                    palette: palette,
                  ),
                ),
                pw.SizedBox(width: TenantReportMetrics.spaceRow),
                pw.SizedBox(
                  width: TenantReportMetrics.pageWidth / 6,
                  child: pw.Text(
                    datum.formatted,
                    textAlign: pw.TextAlign.right,
                    style: _figureStyle(palette, fonts),
                  ),
                ),
              ],
            ),
          ),
        if (ordered.length > shown.length)
          pw.Padding(
            padding: pw.EdgeInsets.only(top: TenantReportMetrics.spaceTight),
            child: pw.Text(
              '${ordered.length - shown.length} more, in the workbook.',
              style: _captionStyle(palette, fonts),
            ),
          ),
      ],
    );
  }

  /// Signed values either side of a centre line.
  ///
  /// A variance reads as a direction before it reads as a number, so the zero
  /// runs down the middle of the page and short is left of it, over is right.
  static pw.Widget _variance(
    TenantReportVisual visual,
    TenantReportPalette palette,
    TenantReportFonts fonts,
  ) {
    final widest = <double>[
      visual.peak.abs(),
      visual.trough.abs(),
    ].reduce((a, b) => a > b ? a : b);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        for (final datum
            in visual.data.take(TenantReportMetrics.rankedMaximumRows.toInt()))
          pw.Padding(
            padding: pw.EdgeInsets.only(
              bottom: TenantReportMetrics.legendRowGap,
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: <pw.Widget>[
                pw.SizedBox(
                  width: TenantReportMetrics.pageWidth / 5,
                  child: pw.Text(
                    datum.label,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: _bodyStyle(palette, fonts),
                  ),
                ),
                pw.SizedBox(width: TenantReportMetrics.spaceRow),
                pw.Expanded(
                  child: _divergingBar(
                    fraction: widest <= 0 ? 0 : datum.value / widest,
                    palette: palette,
                  ),
                ),
                pw.SizedBox(width: TenantReportMetrics.spaceRow),
                pw.SizedBox(
                  width: TenantReportMetrics.pageWidth / 6,
                  child: pw.Text(
                    datum.formatted,
                    textAlign: pw.TextAlign.right,
                    style: _figureStyle(palette, fonts),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget _proportionalBar({
    required double fraction,
    required PdfColor colour,
    required TenantReportPalette palette,
  }) {
    final filled = (fraction.clamp(0, 1) * 1000).round();
    return pw.SizedBox(
      height: TenantReportMetrics.legendSwatch + TenantReportMetrics.spaceHair,
      child: pw.Row(
        children: <pw.Widget>[
          if (filled > 0)
            pw.Expanded(
              flex: filled,
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  color: colour,
                  borderRadius: pw.BorderRadius.circular(
                    TenantReportMetrics.radiusSmall,
                  ),
                ),
              ),
            ),
          if (filled < 1000)
            pw.Expanded(flex: 1000 - filled, child: pw.SizedBox()),
        ],
      ),
    );
  }

  static pw.Widget _divergingBar({
    required double fraction,
    required TenantReportPalette palette,
  }) {
    final magnitude = (fraction.abs().clamp(0, 1) * 500).round();
    final below = fraction < 0;
    return pw.SizedBox(
      height: TenantReportMetrics.legendSwatch + TenantReportMetrics.spaceHair,
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(flex: below ? 500 - magnitude : 500, child: pw.SizedBox()),
          if (below)
            pw.Expanded(
              flex: magnitude,
              child: pw.Container(color: palette.bar),
            ),
          pw.Container(
            width: TenantReportMetrics.gridLineWidth * 2,
            color: palette.mutedInk,
          ),
          if (!below)
            pw.Expanded(
              flex: magnitude,
              child: pw.Container(color: palette.barEmphasis),
            ),
          pw.Expanded(flex: below ? 500 : 500 - magnitude, child: pw.SizedBox()),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // The figures, which every picture carries
  // ---------------------------------------------------------------------------

  /// The labelled rows that make a chart readable without colour.
  ///
  /// Not a legend in the decorative sense: this is the data, and the picture
  /// above it is the summary. A reader who cannot separate two hues, or who
  /// printed the thing in black and white, loses the shape and keeps every
  /// fact.
  static pw.Widget _figures(
    TenantReportVisual visual,
    TenantReportPalette palette,
    TenantReportFonts fonts,
  ) {
    // Ranked and variance already print their label and figure on every row.
    // Repeating them underneath would be the same table twice.
    if (visual.kind == TenantReportVisualKind.ranked ||
        visual.kind == TenantReportVisualKind.variance) {
      return pw.SizedBox();
    }

    final swatched = visual.kind == TenantReportVisualKind.composition;
    // A ninety-day trend wants ninety figures, which is three pages nobody
    // reads and a block too tall to fit a page at all. The note below says how
    // many were withheld and where the rest of them are.
    final shown = visual.data.length <= TenantReportMetrics.maximumFigureRows
        ? visual.data.length
        : TenantReportMetrics.maximumFigureRows;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Wrap(
          spacing: TenantReportMetrics.spaceBlock,
          runSpacing: TenantReportMetrics.legendRowGap,
          children: <pw.Widget>[
        for (var i = 0; i < shown; i++)
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: <pw.Widget>[
              if (swatched) ...<pw.Widget>[
                pw.Container(
                  width: TenantReportMetrics.legendSwatch,
                  height: TenantReportMetrics.legendSwatch,
                  decoration: pw.BoxDecoration(
                    color: palette.seriesAt(i),
                    borderRadius: pw.BorderRadius.circular(
                      TenantReportMetrics.radiusSmall,
                    ),
                  ),
                ),
                pw.SizedBox(width: TenantReportMetrics.legendSwatchGap),
              ],
              pw.Text(
                '${visual.data[i].label}  ',
                style: _captionStyle(palette, fonts),
              ),
              pw.Text(
                visual.data[i].formatted,
                style: _figureStyle(palette, fonts),
              ),
              if (visual.data[i].labelFor(visual.comparisonKind)
                  case final moved?)
                pw.Text(
                  '  ($moved)',
                  style: _captionStyle(palette, fonts),
                ),
            ],
          ),
          ],
        ),
        if (shown < visual.data.length) ...<pw.Widget>[
          pw.SizedBox(height: TenantReportMetrics.spaceRow),
          pw.Text(
            '${visual.data.length - shown} further readings are not printed '
            'here. The workbook for this period carries all '
            '${visual.data.length}.',
            style: _captionStyle(palette, fonts),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared type and axis arithmetic
  // ---------------------------------------------------------------------------

  static pw.TextStyle _axisStyle(
    TenantReportPalette palette,
    TenantReportFonts fonts,
  ) => pw.TextStyle(
    font: fonts.regular,
    fontSize: TenantReportMetrics.eyebrowSize,
    color: palette.axisLabel,
  );

  static pw.TextStyle _captionStyle(
    TenantReportPalette palette,
    TenantReportFonts fonts,
  ) => pw.TextStyle(
    font: fonts.regular,
    fontSize: TenantReportMetrics.captionSize,
    color: palette.mutedInk,
  );

  static pw.TextStyle _bodyStyle(
    TenantReportPalette palette,
    TenantReportFonts fonts,
  ) => pw.TextStyle(
    font: fonts.regular,
    fontSize: TenantReportMetrics.bodySize,
    color: palette.ink,
  );

  static pw.TextStyle _figureStyle(
    TenantReportPalette palette,
    TenantReportFonts fonts,
  ) => pw.TextStyle(
    font: fonts.monoMedium,
    fontSize: TenantReportMetrics.captionSize,
    color: palette.ink,
  );

  /// The category axis, which always has a span to divide by.
  ///
  /// **A single category is the case this exists for.** `FixedAxis.fromStrings`
  /// puts n labels at positions 0..n-1, so one label is one position, the axis
  /// runs from 0 to 0, and every bar's geometry divides by that zero span. The
  /// `pdf` package then asserts on the NaN rather than drawing anything - which
  /// is how a one-person shop, the commonest business this app serves, got a
  /// staff report that refused to build at all.
  ///
  /// A second, unlabelled position gives the axis a width. The bar stays at 0
  /// and the empty half reads as room rather than as a missing category.
  static pw.GridAxis _categoryAxis(
    List<String> labels,
    TenantReportPalette palette,
    TenantReportFonts fonts,
  ) => pw.FixedAxis.fromStrings(
    labels.length < 2 ? <String>[...labels, ''] : labels,
    textStyle: _axisStyle(palette, fonts),
    color: palette.rule,
    width: TenantReportMetrics.gridLineWidth,
    // Without these the paired bar at index zero falls outside the plot area
    // and vanishes, which reads as a category that had no trading last period
    // rather than one that was clipped.
    marginStart: TenantReportMetrics.axisEndMargin,
    marginEnd: TenantReportMetrics.axisEndMargin,
  );

  /// Axis ticks that land on numbers a person would choose.
  ///
  /// An axis labelled 0, 3164, 6328 is arithmetically correct and unreadable.
  /// This walks 1, 2, 2.5, 5, 10 by powers of ten until the step is at least
  /// the span divided by the tick count, which is how every axis anyone has
  /// ever found legible is built.
  static List<double> _ticks(double from, double to, {int count = 4}) {
    if (!to.isFinite || to <= from) return <double>[from, from + 1];
    final rough = (to - from) / count;
    var step = 1.0;
    while (step < rough) {
      if (step * 2 >= rough) {
        step *= 2;
        break;
      }
      if (step * 2.5 >= rough) {
        step *= 2.5;
        break;
      }
      if (step * 5 >= rough) {
        step *= 5;
        break;
      }
      step *= 10;
    }
    final ticks = <double>[];
    for (var value = from; value <= to + step / 2; value += step) {
      ticks.add(value);
    }
    // A single tick is not an axis, and `FixedAxis` wants its values ascending.
    return ticks.length < 2 ? <double>[from, from + step] : ticks;
  }

  /// Thousands as `12k`, so an axis label is three characters rather than six.
  static String _compact(num value) {
    final magnitude = value.abs();
    if (magnitude >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}m';
    }
    if (magnitude >= 1000) return '${(value / 1000).toStringAsFixed(0)}k';
    return value.toStringAsFixed(0);
  }
}
