/// A chart, and the figures that must accompany it.
///
/// **Hard rule 4 lives in this file's constructor.** The design system's
/// standing rule is that a colour never carries a fact on its own: every chart
/// in this app ships beside labelled rows carrying the same numbers, so a
/// reader who cannot separate mint from sage - or who printed the thing in
/// black and white - loses nothing. On screen that rule is kept by each surface
/// remembering it. Here it is kept by the type: a [TenantReportVisual] cannot
/// be built without its data, the data carry their own labels and their own
/// formatted values, and both renderers draw the rows from the same list the
/// chart is plotted from. They cannot disagree, because there is only one list.
library;

/// One plotted value, carrying everything needed to draw it and to read it.
final class TenantReportDatum {
  const TenantReportDatum({
    required this.label,
    required this.value,
    required this.formatted,
    this.comparison,
    this.comparisonFormatted,
    this.emphasis = false,
  }) : assert(
         (comparison == null) == (comparisonFormatted == null),
         'A comparison must arrive with the text that prints it.',
       );

  /// What this value is of - a category, a weekday, a person, a product.
  final String label;

  /// The raw number, for plotting and for a spreadsheet cell.
  ///
  /// Money arrives here in **major** units, already divided, because a chart
  /// axis in minor units would label a shelf of tins at 120,000.
  final double value;

  /// The number as it is printed, formatted once by the analysis that knows the
  /// currency.
  ///
  /// **Formatted in the analysis layer, never in a renderer.** Two renderers
  /// formatting independently is two chances to disagree about what a figure
  /// says, and `TenantReportingCurrency` has one opinion about how a figure is
  /// written that both must obey.
  final String formatted;

  /// The same measure over the preceding comparable period, where there is one.
  final double? comparison;

  final String? comparisonFormatted;

  /// Whether this is the value the eye should land on.
  ///
  /// Drawn with `chart.barEmphasis` rather than `chart.bar`. At most one datum
  /// in a visual should carry it; more than one emphasis is none.
  final bool emphasis;

  /// How far this moved against the preceding period, as a fraction.
  ///
  /// Null where there is nothing to compare, or where the earlier figure was
  /// zero - a rise from nothing is not a percentage, and printing one would be
  /// a division nobody can check.
  double? get change {
    final was = comparison;
    if (was == null || was == 0) return null;
    return (value - was) / was.abs();
  }

  /// The move written out, or null where [change] is.
  ///
  /// **Only correct when the comparison is an earlier period.** *Up* and *down*
  /// are claims about time. Where the comparison is a line the value is being
  /// read against - a median, a target, a shop average - the same arithmetic
  /// means something else entirely, and [differenceLabel] is the one to print.
  /// [TenantReportVisual.comparisonKind] decides which.
  String? get changeLabel {
    final moved = change;
    if (moved == null) return null;
    final percent = (moved * 100).abs().toStringAsFixed(1);
    if (moved > 0) return 'up $percent%';
    if (moved < 0) return 'down $percent%';
    return 'unchanged';
  }

  /// The distance from a reference line, written out.
  ///
  /// *Above* and *below*, never *up* and *down*: a person whose average sale
  /// sits a quarter under the shop's median has not fallen by a quarter, and
  /// saying so would invent a trend out of a comparison.
  String? get differenceLabel {
    final apart = change;
    if (apart == null) return null;
    final percent = (apart * 100).abs().toStringAsFixed(1);
    if (apart > 0) return '$percent% above';
    if (apart < 0) return '$percent% below';
    return 'level with it';
  }

  /// The wording that suits [kind].
  String? labelFor(TenantReportComparisonKind kind) => switch (kind) {
    TenantReportComparisonKind.priorPeriod => changeLabel,
    TenantReportComparisonKind.reference => differenceLabel,
  };
}

/// What a datum's comparison actually is.
///
/// **Two different claims, and mixing them up prints a falsehood.** A bar drawn
/// against the same measure last month supports *up* and *down*. A bar drawn
/// against the shop's median supports *above* and *below*. The arithmetic is
/// identical and the sentences are not interchangeable, so the visual has to
/// say which it means rather than leave a renderer to assume.
enum TenantReportComparisonKind {
  /// The same measure over the preceding comparable period.
  priorPeriod,

  /// A line the value is being read against - a median, an average, a target.
  reference,
}

/// The shapes a report draws.
///
/// A closed set, because each one has a primitive that draws it in the PDF and
/// a layout that writes it in the workbook. A report picks a shape; it never
/// hands a renderer a widget.
enum TenantReportVisualKind {
  /// This period against the one before it, side by side.
  comparison,

  /// A value over the days of the period.
  trend,

  /// Largest to smallest, drawn along the page.
  ranked,

  /// Parts of one whole.
  composition,

  /// Signed values about a zero line.
  variance,
}

/// A chart together with the figures that make it readable without colour.
final class TenantReportVisual {
  TenantReportVisual({
    required this.kind,
    required this.caption,
    required this.valueAxisLabel,
    required List<TenantReportDatum> data,
    this.comparisonLabel,
    this.comparisonKind = TenantReportComparisonKind.priorPeriod,
  }) : data = List<TenantReportDatum>.unmodifiable(data) {
    if (data.isEmpty) {
      throw ArgumentError.value(
        data,
        'data',
        'a chart with no rows would be a colour carrying a fact alone',
      );
    }
  }

  final TenantReportVisualKind kind;

  /// One sentence saying what the picture shows.
  final String caption;

  /// What the values are measured in - 'Takings', 'Units', 'Share of takings'.
  final String valueAxisLabel;

  /// What the comparison series is, where the data carry one.
  final String? comparisonLabel;

  /// Whether the comparison is an earlier period or a reference line.
  ///
  /// Decides whether the figures beside the chart read *up 25%* or *25%
  /// below*. See [TenantReportComparisonKind].
  final TenantReportComparisonKind comparisonKind;

  /// The plotted values, and the rows printed beside them.
  final List<TenantReportDatum> data;

  /// Whether any datum carries a comparison, which decides whether the chart
  /// draws one series or two.
  bool get hasComparison => data.any((d) => d.comparison != null);

  /// The largest value plotted, for an axis that must reach it.
  double get peak => data
      .map((d) => <double>[d.value, d.comparison ?? d.value])
      .expand((values) => values)
      .fold(0, (highest, value) => value > highest ? value : highest);

  /// The smallest value plotted, which is negative on a variance chart.
  double get trough => data
      .map((d) => <double>[d.value, d.comparison ?? d.value])
      .expand((values) => values)
      .fold(0, (lowest, value) => value < lowest ? value : lowest);

  /// The sum of the plotted values, which is the whole a composition divides.
  double get total => data.fold(0, (sum, d) => sum + d.value);

  /// The share the largest value takes of the whole, or null where the whole is
  /// nothing.
  ///
  /// The concentration sentence every ranked and composition section prints -
  /// "3 products are 61% of returns" - is the analytic claim those charts exist
  /// to support, so the arithmetic lives here where it can be tested.
  double? get concentration {
    final whole = total;
    if (whole <= 0) return null;
    return data.map((d) => d.value).reduce((a, b) => a > b ? a : b) / whole;
  }

  /// How many of the largest values it takes to pass [fraction] of the whole.
  ///
  /// Null where the whole is nothing. Used for "2 of 9 staff took 58% of
  /// takings", which says more than any single share does.
  int? headCountFor(double fraction) {
    final whole = total;
    if (whole <= 0) return null;
    final descending = data.map((d) => d.value).toList()
      ..sort((a, b) => b.compareTo(a));
    var running = 0.0;
    for (var i = 0; i < descending.length; i++) {
      running += descending[i];
      if (running / whole >= fraction) return i + 1;
    }
    return descending.length;
  }
}
