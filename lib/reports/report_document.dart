/// The finished report, in the only form a renderer ever sees.
///
/// **This is the whole extension point.** A renderer takes a
/// [TenantReportDocument] and nothing else - it cannot tell a sales report from
/// a stock count, and it has no branch that depends on which one it is drawing.
/// That property is what makes "branded, high fidelity, in both formats" one
/// implementation instead of eight, and it is what stops the eighth report
/// quietly drifting from the first.
///
/// Everything shared - the branding lockup, the period stamp, the currency, the
/// provenance block, the page furniture, the filename - lives here and in
/// [TenantReportIdentity] and [TenantReportScope]. Everything bespoke lives in
/// one `describe()` method per report, which returns [headline] and [sections]
/// and nothing else. Adding the ninth report is an analysis file, a source
/// file, and one `describe()`.
library;

import 'report_identity.dart';
import 'report_period.dart';
import 'report_scope.dart';
import 'report_table.dart';
import 'report_visual.dart';

/// Which of the reports this is.
///
/// Used for the toolbar action's key, the filename, and the share subject. It
/// is deliberately *not* read by any renderer.
enum TenantReportKind {
  sales('sales', 'Sales report'),
  returns('returns', 'Returns report'),
  inventory('inventory', 'Inventory report'),
  stockCounts('stock-counts', 'Stock count report'),
  expenses('expenses', 'Expenses report'),
  staff('staff', 'Staff report'),
  shifts('shifts', 'Shifts report'),
  logs('logs', 'Activity report');

  const TenantReportKind(this.slug, this.title);

  /// The filename fragment.
  final String slug;

  /// What the document calls itself.
  final String title;
}

/// Which file the person asked for.
enum TenantReportFormat {
  /// A document to read: charts, branding, laid out for paper.
  pdf('pdf', 'application/pdf', 'PDF', 'A visual report to read or print'),

  /// A workbook to work with: typed cells, one sheet per section.
  excel(
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'Excel',
    'The figures, to sort and total yourself',
  );

  const TenantReportFormat(
    this.extension,
    this.mimeType,
    this.label,
    this.description,
  );

  final String extension;
  final String mimeType;
  final String label;

  /// One line saying what picking this gets you, shown beside the control.
  final String description;
}

/// One of the few numbers a cover page leads with.
final class TenantReportFigure {
  const TenantReportFigure({
    required this.label,
    required this.value,
    this.comparison,
    this.note,
    this.amount,
    this.amountComparison,
    this.amountKind = TenantReportColumnKind.money,
  });

  /// What the number is - 'Takings', 'Transactions', 'Gross margin'.
  final String label;

  /// The number as it is printed, formatted by the analysis.
  final String value;

  /// The same measure over the preceding comparable period, already written.
  final String? comparison;

  /// The raw number behind [value], where there is one.
  ///
  /// **The page prints [value]; the workbook writes this.** A headline figure
  /// is the number somebody is most likely to want to reference - takings,
  /// margin, the transaction count - and writing it into a spreadsheet as the
  /// string `KES 4863.50` takes away the one thing they opened the spreadsheet
  /// to do with it. Money is in **major** units here, matching
  /// `TenantReportMoneyCell.major`, so a cell needs no further conversion.
  ///
  /// Null where a figure genuinely has no single number behind it.
  final num? amount;

  /// [amount] for the preceding comparable period.
  final num? amountComparison;

  /// What [amount] is, which decides the cell's number format.
  final TenantReportColumnKind amountKind;

  /// A qualification this particular figure carries, printed beneath it.
  ///
  /// Where a headline figure is partial - a margin computed over some of the
  /// lines - the qualification belongs against the figure, not only in the
  /// scope block at the front that a reader may not reach.
  final String? note;
}

/// One part of a report: a question, a picture, and the rows behind it.
final class TenantReportSection {
  TenantReportSection({
    required this.heading,
    required this.summary,
    this.visual,
    this.table,
    List<String> notes = const <String>[],
  }) : notes = List<String>.unmodifiable(notes) {
    if (visual == null && table == null) {
      throw ArgumentError(
        'a section that draws nothing and lists nothing is a heading',
      );
    }
  }

  final String heading;

  /// One sentence saying what this section answers.
  ///
  /// **Required, and it is the analytic content.** A section headed *Takings by
  /// day* with a chart under it restates the screen. The same section saying
  /// "Takings fell on every Monday of the period, and the last one was the
  /// weakest day in six weeks" is the reason somebody asked for a report.
  final String summary;

  final TenantReportVisual? visual;

  final TenantReportTable? table;

  /// Qualifications belonging to this section rather than to the whole report.
  final List<String> notes;

  /// The sheet this section becomes in a workbook.
  String get sheetName {
    final trimmed = heading.replaceAll(RegExp(r'[\[\]\*/\\?:]'), '');
    return trimmed.length <= _sheetNameLimit
        ? trimmed
        : trimmed.substring(0, _sheetNameLimit);
  }

  /// Excel refuses a sheet name longer than this.
  static const int _sheetNameLimit = 31;
}

/// A report, ready to render.
final class TenantReportDocument {
  TenantReportDocument({
    required this.kind,
    required this.identity,
    required this.scope,
    required this.subtitle,
    required List<TenantReportFigure> headline,
    required List<TenantReportSection> sections,
    String? title,
  }) : title = title ?? kind.title,
       headline = List<TenantReportFigure>.unmodifiable(headline),
       sections = List<TenantReportSection>.unmodifiable(sections);

  final TenantReportKind kind;

  final String title;

  /// One sentence under the title saying what the reader is looking at.
  final String subtitle;

  final TenantReportIdentity identity;

  final TenantReportScope scope;

  /// The three to five numbers the cover leads with.
  final List<TenantReportFigure> headline;

  final List<TenantReportSection> sections;

  TenantReportPeriod get period => scope.period;

  /// Every caveat this document must print, the report's own and the currency's.
  ///
  /// Assembled here rather than in each renderer so the PDF and the workbook
  /// cannot print different lists.
  List<String> get caveats => <String>[
    ...scope.caveats.map((c) => c.sentence),
    if (identity.currencyNotice case final notice?) notice,
  ];

  /// What the file is called.
  ///
  /// `business-kind-period.ext`, all lowercase ASCII, so it sorts sensibly in a
  /// folder that accumulates them and survives whatever filesystem the share
  /// sheet lands it on.
  String filename(TenantReportFormat format) =>
      '${identity.slug}-${kind.slug}-${period.slug}.${format.extension}';

  /// What the share sheet offers the file as.
  String get shareSubject => '$title - ${period.spelled}';

  /// The line that accompanies it.
  String get shareText =>
      '$title for ${identity.businessName}, covering ${period.spelled}.';
}
