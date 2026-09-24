/// Every measurement a generated document uses, named.
///
/// **Two reasons this class exists, and both are load-bearing.**
///
/// The first is the one `ExpenseChartMetrics` gives: a chart is arithmetic, and
/// arithmetic buried in a widget cannot be checked without reading pixels out
/// of a screenshot. A document is worse - there is no screenshot at all, because
/// `tool/screenshots` rasterises a Flutter widget tree and none of this ever
/// enters one. If these numbers are not named and testable here, they are not
/// checkable anywhere.
///
/// The second is mechanical. `test/dev/token_spacing_test.dart` scans all of
/// `lib/` for `SizedBox(height: 12)` and `EdgeInsets.all(20)`, and its pattern
/// is anchored on a word boundary - so `pw.SizedBox(height: 180)` and
/// `pw.EdgeInsets.all(16)` match it just as readily as the Flutter ones do. The
/// renderer would trip a rule written for widgets. Routing every figure through
/// here means the scan never sees a digit, which is the outcome the rule wants
/// rather than an exemption that would be a hole in it.
///
/// **These are print points, not logical pixels.** A 16-pixel body on a phone
/// held at arm's length and an 11-point body on A4 are the same apparent size;
/// copying the screen's scale onto paper would set the whole document two sizes
/// too large. So the type scale here is derived from `AppTypeRoles`' intent
/// rather than its numbers.
library;

/// The page, its furniture, and its charts.
abstract final class TenantReportMetrics {
  const TenantReportMetrics._();

  // --- The page -------------------------------------------------------------

  /// A4 in points. The default nearly everywhere this app is used.
  static const double pageWidth = 595.28;
  static const double pageHeight = 841.89;

  static const double marginHorizontal = 40;
  static const double marginTop = 36;
  static const double marginBottom = 36;

  /// A long table can easily outrun the `pdf` package's default of 20 pages.
  static const int maximumPages = 200;

  // --- Type, in points ------------------------------------------------------

  static const double displaySize = 22;
  static const double titleSize = 15;
  static const double headingSize = 12;
  static const double bodySize = 9.5;
  static const double captionSize = 8;
  static const double eyebrowSize = 7.5;
  static const double figureSize = 18;
  static const double figureLabelSize = 8;

  static const double eyebrowSpacing = 0.6;
  static const double tightLineHeight = 1.25;
  static const double readingLineHeight = 1.45;

  // --- Spacing, in points ---------------------------------------------------

  static const double spaceHair = 2;
  static const double spaceTight = 4;
  static const double spaceSnug = 6;
  static const double spaceRow = 8;
  static const double spaceItem = 12;
  static const double spaceBlock = 16;
  static const double spaceSection = 24;
  static const double spaceBand = 32;

  static const double radiusSmall = 2;
  static const double radiusBand = 4;

  static const double ruleWidth = 0.6;
  static const double gridLineWidth = 0.4;
  static const double chartLineWidth = 1.6;

  // --- The branding lockup --------------------------------------------------

  /// The logo's longest side on a cover page.
  static const double logoCover = 56;

  /// And in the running header, where it sits beside one line of type.
  static const double logoHeader = 14;

  static const double coverBandPadding = 14;
  static const double headerHeight = 28;
  static const double footerHeight = 20;

  // --- Headline figures -----------------------------------------------------

  /// How many figures fit across the cover before they start to crowd.
  static const int headlineAcross = 3;

  static const double figureTilePadding = 10;
  static const double figureTileGap = 8;

  // --- Charts ---------------------------------------------------------------

  static const double chartHeight = 170;
  static const double compositionHeight = 190;

  /// A ranked chart grows with its rows rather than squeezing them.
  static const double rankedRowHeight = 18;
  static const double rankedMinimumHeight = 90;
  static const double rankedMaximumRows = 12;

  static const double barWidth = 14;
  static const double groupedBarWidth = 7;

  /// Half the grouped width, applied either side of the tick, so this period
  /// and the one before it sit shoulder to shoulder rather than overlapping.
  static const double groupedBarOffset = 3.6;

  static const double donutInnerRadius = 34;
  static const double donutOuterRadius = 62;
  static const double donutStartAngle = 90;

  static const double pointRadius = 2;
  static const double areaOpacity = 0.12;

  /// Headroom above the tallest bar, so a peak does not touch the frame.
  static const double axisHeadroom = 1.12;

  /// A trend line labels only this many ticks, however many days it covers.
  static const int trendLabelCount = 5;

  /// Space left at each end of a category axis.
  ///
  /// **Without it the first and last bars are clipped.** A grouped comparison
  /// draws this period half a bar right of its tick and the period before it
  /// half a bar left; at index zero that second bar falls outside the plot
  /// area and simply vanishes, which reads as a category that had no trading
  /// last period rather than one whose bar ran off the edge.
  static const double axisEndMargin = 12;

  /// How many labelled figures print beneath a chart before the rest are left
  /// to the workbook.
  ///
  /// Hard rule 4 wants the figures beside the picture, and a ninety-day trend
  /// wants ninety of them - which is three pages of numbers nobody reads and,
  /// worse, a block too tall to fit on a page at all. The cap keeps the section
  /// atomic; the note under it says how many were withheld and where they are.
  static const int maximumFigureRows = 24;

  /// Past this many days a trend draws no point markers - they merge into a
  /// caterpillar and stop being readable.
  static const int maximumPlottedPoints = 31;

  // --- Tables ---------------------------------------------------------------

  static const double tableCellPaddingVertical = 4.5;
  static const double tableCellPaddingHorizontal = 6;
  static const double tableHeaderPaddingVertical = 5.5;

  /// The label column of a figures-beside-the-chart listing.
  static const double legendSwatch = 7;
  static const double legendSwatchGap = 5;
  static const double legendRowGap = 3;

  /// How many rows of a long table print before it is cut with a note saying
  /// how many were left. A report is a summary; the workbook carries the lot.
  static const int maximumTableRows = 40;

  /// Where a trend's x-axis label should be placed for a period of [days].
  ///
  /// Every day on a 90-day axis is unreadable overlap, so this thins the labels
  /// to about [trendLabelCount] and always keeps the first and the last - the
  /// two a reader looks for to know what they are looking at.
  static int trendLabelInterval(int days) {
    if (days <= trendLabelCount) return 1;
    final interval = (days - 1) / (trendLabelCount - 1);
    return interval.ceil();
  }

  /// How tall a ranked chart of [rows] bars should be.
  static double rankedHeightFor(int rows) {
    final height = rows * rankedRowHeight;
    return height < rankedMinimumHeight ? rankedMinimumHeight : height;
  }

  /// The top of a value axis that must reach [peak] without touching the frame.
  ///
  /// A period with no takings at all still needs an axis, or the chart has no
  /// height and the zero line has nowhere to sit - hence the floor of one.
  static double axisCeilingFor(double peak) {
    if (!peak.isFinite || peak <= 0) return 1;
    return peak * axisHeadroom;
  }
}
