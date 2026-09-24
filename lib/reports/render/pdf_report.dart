/// A [TenantReportDocument], laid out on paper.
///
/// **It cannot tell which report it is drawing.** There is no branch here on
/// [TenantReportKind], and there must never be one: the renderer walks a
/// document's headline figures and its sections, and every difference between a
/// sales report and a stock count was already decided by the analysis that
/// built them. That is what makes eight reports one implementation, and it is
/// what stops the eighth quietly drifting from the first.
///
/// **It does no I/O and reads no documents.** Branding arrives loaded, fonts
/// arrive loaded, figures arrive formatted. This is `CheckoutReceiptBody`'s
/// shape, kept for its reason: a layout that reached for an asset or a
/// repository could not be exercised without standing up half the app, and
/// every page of every report would then be unverifiable except by eye.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../report_document.dart';
import '../report_file.dart';
import '../report_metrics.dart';
import '../report_table.dart';
import 'pdf_report_charts.dart';
import 'report_fonts.dart';
import 'report_palette.dart';

/// Renders a report as a PDF.
final class TenantPdfReportRenderer {
  const TenantPdfReportRenderer({required this.palette, required this.fonts});

  /// A renderer with the standard paper palette and the built-in faces.
  ///
  /// For a test and for the sample-rendering tool. A device uses
  /// `TenantReportFonts.load()` so the document carries the brand's own type.
  factory TenantPdfReportRenderer.standard() => TenantPdfReportRenderer(
    palette: TenantReportPalette.standard,
    fonts: TenantReportFonts.standard(),
  );

  final TenantReportPalette palette;
  final TenantReportFonts fonts;

  Future<TenantReportFile> render(TenantReportDocument document) async {
    final pdf = pw.Document(
      title: '${document.title} - ${document.identity.businessName}',
      author: document.identity.businessName,
      creator: document.identity.generatedByName ?? '',
      subject: document.period.spelled,
      theme: fonts.theme(),
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(),
        header: (context) => _runningHeader(document, context),
        footer: (context) => _runningFooter(document, context),
        // A long table will outrun the package's default of twenty pages, and
        // a report that silently stopped halfway would be the one failure this
        // whole area is built to avoid.
        maxPages: TenantReportMetrics.maximumPages,
        build: (context) => <pw.Widget>[
          _cover(document),
          for (final section in document.sections) ..._section(section),
        ],
      ),
    );

    return TenantReportFile(
      filename: document.filename(TenantReportFormat.pdf),
      bytes: Uint8List.fromList(await pdf.save()),
      mimeType: TenantReportFormat.pdf.mimeType,
      subject: document.shareSubject,
      text: document.shareText,
    );
  }

  pw.PageTheme _pageTheme() => pw.PageTheme(
    pageFormat: PdfPageFormat(
      TenantReportMetrics.pageWidth,
      TenantReportMetrics.pageHeight,
      marginLeft: TenantReportMetrics.marginHorizontal,
      marginRight: TenantReportMetrics.marginHorizontal,
      marginTop: TenantReportMetrics.marginTop,
      marginBottom: TenantReportMetrics.marginBottom,
    ),
    theme: fonts.theme(),
    buildBackground: (context) =>
        pw.FullPage(ignoreMargins: true, child: pw.Container(color: palette.paper)),
  );

  // ---------------------------------------------------------------------------
  // Furniture
  // ---------------------------------------------------------------------------

  /// The branding lockup, the title, the period, the headline, and the scope.
  pw.Widget _cover(TenantReportDocument document) {
    final identity = document.identity;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Container(
          width: double.infinity,
          padding: pw.EdgeInsets.all(TenantReportMetrics.coverBandPadding),
          decoration: pw.BoxDecoration(
            color: palette.wash,
            borderRadius: pw.BorderRadius.circular(
              TenantReportMetrics.radiusBand,
            ),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: <pw.Widget>[
              if (identity.logo case final logo?) ...<pw.Widget>[
                pw.SizedBox(
                  height: TenantReportMetrics.logoCover,
                  width: TenantReportMetrics.logoCover,
                  child: pw.Image(
                    pw.MemoryImage(logo),
                    fit: pw.BoxFit.contain,
                  ),
                ),
                pw.SizedBox(width: TenantReportMetrics.spaceBlock),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(
                      identity.businessName,
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: TenantReportMetrics.displaySize,
                        color: palette.ink,
                      ),
                    ),
                    if (identity.slogan case final slogan?)
                      pw.Text(
                        slogan,
                        style: pw.TextStyle(
                          font: fonts.regular,
                          fontSize: TenantReportMetrics.bodySize,
                          color: palette.mutedInk,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: TenantReportMetrics.spaceSection),
        pw.Text(
          document.title.toUpperCase(),
          style: pw.TextStyle(
            font: fonts.semiBold,
            fontSize: TenantReportMetrics.eyebrowSize,
            letterSpacing: TenantReportMetrics.eyebrowSpacing,
            color: palette.accent,
          ),
        ),
        pw.SizedBox(height: TenantReportMetrics.spaceTight),
        pw.Text(
          document.period.spelled,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: TenantReportMetrics.titleSize,
            color: palette.ink,
          ),
        ),
        pw.SizedBox(height: TenantReportMetrics.spaceSnug),
        pw.Text(
          document.subtitle,
          style: pw.TextStyle(
            font: fonts.regular,
            fontSize: TenantReportMetrics.bodySize,
            height: TenantReportMetrics.readingLineHeight,
            color: palette.mutedInk,
          ),
        ),
        pw.SizedBox(height: TenantReportMetrics.spaceSection),
        if (document.headline.isNotEmpty) _headline(document),
        pw.SizedBox(height: TenantReportMetrics.spaceSection),
        _scopeBlock(document),
      ],
    );
  }

  /// The three to five figures the report leads with.
  ///
  /// **A table rather than a row, so the tiles are the same height.** Each
  /// figure carries a different amount underneath it - one has a prior period
  /// to compare against, one has a sentence about incomplete cost lines, one
  /// has neither - and a `Row` sizes every child to its own content, so three
  /// tiles side by side were three different heights with their bottom rules
  /// stepping down the page. A `Table` row is as tall as its tallest cell, and
  /// [pw.TableCellVerticalAlignment.full] lays the rest out again at that
  /// height, which is the only mechanism in this package that does it:
  /// `CrossAxisAlignment.stretch` stretches to the *incoming* constraint, which
  /// inside a `MultiPage` is the rest of the page.
  ///
  /// The gaps are columns of their own rather than padding inside a cell,
  /// because the border belongs to the tile and padding inside the cell would
  /// put the gap inside the rule.
  pw.Widget _headline(TenantReportDocument document) {
    const across = TenantReportMetrics.headlineAcross;
    final rows = <List<TenantReportFigure>>[];
    for (var i = 0; i < document.headline.length; i += across) {
      rows.add(document.headline.skip(i).take(across).toList());
    }

    // Alternating tile and gap: 0, 2, 4... are tiles sharing the width evenly,
    // and the odd columns between them are the fixed gutters.
    final widths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < across * 2 - 1; i++)
        i: i.isEven
            ? const pw.FlexColumnWidth()
            : const pw.FixedColumnWidth(TenantReportMetrics.figureTileGap),
    };

    return pw.Table(
      columnWidths: widths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
      children: <pw.TableRow>[
        for (final (index, row) in rows.indexed) ...<pw.TableRow>[
          // The gutter between bands of figures, as a row of its own - a table
          // has no row spacing, and padding inside a cell would fall inside
          // the tile's own rule.
          if (index > 0)
            pw.TableRow(
              children: <pw.Widget>[
                pw.SizedBox(height: TenantReportMetrics.figureTileGap),
              ],
            ),
          pw.TableRow(
            children: <pw.Widget>[
              for (var i = 0; i < across; i++) ...<pw.Widget>[
                // An empty cell rather than a narrower row: a report with four
                // figures leaves the fifth and sixth slots blank so the four
                // that exist stay the width of the three above them.
                i < row.length ? _figureTile(row[i]) : pw.SizedBox(),
                if (i < across - 1) pw.SizedBox(),
              ],
            ],
          ),
        ],
      ],
    );
  }

  pw.Widget _figureTile(TenantReportFigure figure) => pw.Container(
    padding: pw.EdgeInsets.all(TenantReportMetrics.figureTilePadding),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(
        color: palette.rule,
        width: TenantReportMetrics.ruleWidth,
      ),
      borderRadius: pw.BorderRadius.circular(TenantReportMetrics.radiusBand),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          figure.label.toUpperCase(),
          style: pw.TextStyle(
            font: fonts.semiBold,
            fontSize: TenantReportMetrics.eyebrowSize,
            letterSpacing: TenantReportMetrics.eyebrowSpacing,
            color: palette.mutedInk,
          ),
        ),
        pw.SizedBox(height: TenantReportMetrics.spaceSnug),
        pw.Text(
          figure.value,
          style: pw.TextStyle(
            font: fonts.monoMedium,
            fontSize: TenantReportMetrics.figureSize,
            color: palette.ink,
          ),
        ),
        if (figure.comparison case final was?) ...<pw.Widget>[
          pw.SizedBox(height: TenantReportMetrics.spaceHair),
          pw.Text(
            'was $was',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: TenantReportMetrics.captionSize,
              color: palette.mutedInk,
            ),
          ),
        ],
        if (figure.note case final note?) ...<pw.Widget>[
          pw.SizedBox(height: TenantReportMetrics.spaceTight),
          pw.Text(
            note,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: TenantReportMetrics.captionSize,
              height: TenantReportMetrics.tightLineHeight,
              color: palette.mutedInk,
            ),
          ),
        ],
      ],
    ),
  );

  /// What this report covered, and every reason it fell short.
  ///
  /// **Prints whether or not anything went wrong.** A provenance block that
  /// appears only when something is broken is a block people learn to skip, and
  /// the one time it matters is the one time it gets skipped.
  pw.Widget _scopeBlock(TenantReportDocument document) {
    final caveats = document.caveats;

    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(TenantReportMetrics.figureTilePadding),
      decoration: pw.BoxDecoration(
        color: palette.wash,
        borderRadius: pw.BorderRadius.circular(TenantReportMetrics.radiusBand),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            'SCOPE AND PROVENANCE',
            style: pw.TextStyle(
              font: fonts.semiBold,
              fontSize: TenantReportMetrics.eyebrowSize,
              letterSpacing: TenantReportMetrics.eyebrowSpacing,
              color: palette.mutedInk,
            ),
          ),
          pw.SizedBox(height: TenantReportMetrics.spaceSnug),
          pw.Text(
            document.scope.summary,
            style: pw.TextStyle(
              font: fonts.medium,
              fontSize: TenantReportMetrics.bodySize,
              height: TenantReportMetrics.readingLineHeight,
              color: palette.ink,
            ),
          ),
          pw.SizedBox(height: TenantReportMetrics.spaceTight),
          pw.Text(
            'Generated ${_stamp(document.identity.generatedAt)} by '
            '${document.identity.generatedBy}.',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: TenantReportMetrics.captionSize,
              color: palette.mutedInk,
            ),
          ),
          for (final caveat in caveats) ...<pw.Widget>[
            pw.SizedBox(height: TenantReportMetrics.spaceSnug),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Container(
                  width: TenantReportMetrics.ruleWidth * 3,
                  height: TenantReportMetrics.bodySize,
                  color: palette.accent,
                ),
                pw.SizedBox(width: TenantReportMetrics.spaceSnug),
                pw.Expanded(
                  child: pw.Text(
                    caveat,
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: TenantReportMetrics.captionSize,
                      height: TenantReportMetrics.readingLineHeight,
                      color: palette.ink,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _runningHeader(TenantReportDocument document, pw.Context context) {
    if (context.pageNumber == 1) return pw.SizedBox();
    return pw.Container(
      height: TenantReportMetrics.headerHeight,
      margin: pw.EdgeInsets.only(bottom: TenantReportMetrics.spaceItem),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            color: palette.rule,
            width: TenantReportMetrics.ruleWidth,
          ),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          pw.Text(
            document.identity.businessName,
            style: pw.TextStyle(
              font: fonts.semiBold,
              fontSize: TenantReportMetrics.captionSize,
              color: palette.ink,
            ),
          ),
          pw.Text(
            '${document.title} - ${document.period.spelled}',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: TenantReportMetrics.captionSize,
              color: palette.mutedInk,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _runningFooter(TenantReportDocument document, pw.Context context) =>
      pw.Container(
        height: TenantReportMetrics.footerHeight,
        margin: pw.EdgeInsets.only(top: TenantReportMetrics.spaceRow),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              _stamp(document.identity.generatedAt),
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: TenantReportMetrics.eyebrowSize,
                color: palette.mutedInk,
              ),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: TenantReportMetrics.eyebrowSize,
                color: palette.mutedInk,
              ),
            ),
          ],
        ),
      );

  // ---------------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------------

  /// A section, as the one or two page-items it is really made of.
  ///
  /// **The heading must not be orphaned, and a long table must still break.**
  /// `MultiPage` splits any child that reports itself spanning, and in this
  /// package a `Column` always does - `Flex.canSpan` is `direction ==
  /// vertical`, and `StatelessWidget` inherits its child's answer, so wrapping
  /// a `Column` in a `Container` changes nothing. That is what put a section
  /// heading at the foot of one page and its chart at the top of the next.
  ///
  /// A `Row` is the opposite: horizontal, so it never spans. Wrapping the
  /// heading, the summary and the picture in one makes them a single atom that
  /// moves to the next page whole. The table is emitted as its own item and is
  /// left spanning, because a forty-row table *should* break across pages - it
  /// just has to carry its column headings over with it, which is what
  /// `TableRow(repeat: true)` is for.
  ///
  /// The atom must never exceed a page or `MultiPage` throws rather than
  /// breaking it, which is why the figures beneath a chart are capped.
  List<pw.Widget> _section(TenantReportSection section) => <pw.Widget>[
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(child: _sectionHead(section)),
      ],
    ),
    if (section.table case final table?) _table(table),
    for (final note in section.notes) _sectionNote(note),
  ];

  pw.Widget _sectionNote(String note) => pw.Padding(
    padding: pw.EdgeInsets.only(top: TenantReportMetrics.spaceRow),
    child: pw.Text(
      note,
      style: pw.TextStyle(
        font: fonts.regular,
        fontSize: TenantReportMetrics.captionSize,
        height: TenantReportMetrics.readingLineHeight,
        color: palette.mutedInk,
      ),
    ),
  );

  pw.Widget _sectionHead(TenantReportSection section) => pw.Container(
    margin: pw.EdgeInsets.only(top: TenantReportMetrics.spaceBand),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          section.heading,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: TenantReportMetrics.headingSize,
            color: palette.ink,
          ),
        ),
        pw.SizedBox(height: TenantReportMetrics.spaceTight),
        pw.Container(
          width: double.infinity,
          height: TenantReportMetrics.ruleWidth,
          color: palette.rule,
        ),
        pw.SizedBox(height: TenantReportMetrics.spaceItem),
        // The sentence is the analytic content. A section headed "Takings by
        // day" with a chart under it restates the screen; the same section
        // saying which day was weakest and by how much is the reason anybody
        // asked for a report.
        pw.Text(
          section.summary,
          style: pw.TextStyle(
            font: fonts.regular,
            fontSize: TenantReportMetrics.bodySize,
            height: TenantReportMetrics.readingLineHeight,
            color: palette.ink,
          ),
        ),
        if (section.visual case final visual?) ...<pw.Widget>[
          pw.SizedBox(height: TenantReportMetrics.spaceBlock),
          TenantReportCharts.forVisual(
            visual,
            palette: palette,
            fonts: fonts,
          ),
        ],
        // The table and the notes are emitted as their own page-items by
        // [_section], so a long table can break across pages while the block
        // above stays whole.
      ],
    ),
  );

  pw.Widget _table(TenantReportTable table) {
    // A margin here rather than a SizedBox above, because this is emitted as
    // its own page-item and may open a page.
    final shown = table.rows.take(TenantReportMetrics.maximumTableRows).toList();
    final withheld = table.rows.length - shown.length;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(
              color: palette.rule,
              width: TenantReportMetrics.gridLineWidth,
            ),
          ),
          children: <pw.TableRow>[
            pw.TableRow(
              // Carried onto every page the table runs over. A continuation
              // page of bare figures under no headings is a page of numbers
              // nobody can attribute to a column.
              repeat: true,
              decoration: pw.BoxDecoration(color: palette.wash),
              children: <pw.Widget>[
                for (final column in table.columns)
                  pw.Padding(
                    padding: pw.EdgeInsets.symmetric(
                      vertical: TenantReportMetrics.tableHeaderPaddingVertical,
                      horizontal:
                          TenantReportMetrics.tableCellPaddingHorizontal,
                    ),
                    child: pw.Text(
                      column.heading,
                      textAlign: column.isNumeric
                          ? pw.TextAlign.right
                          : pw.TextAlign.left,
                      style: pw.TextStyle(
                        font: fonts.semiBold,
                        fontSize: TenantReportMetrics.captionSize,
                        color: palette.ink,
                      ),
                    ),
                  ),
              ],
            ),
            for (var r = 0; r < shown.length; r++)
              pw.TableRow(
                children: <pw.Widget>[
                  for (var c = 0; c < table.columns.length; c++)
                    pw.Padding(
                      padding: pw.EdgeInsets.symmetric(
                        vertical: TenantReportMetrics.tableCellPaddingVertical,
                        horizontal:
                            TenantReportMetrics.tableCellPaddingHorizontal,
                      ),
                      child: pw.Text(
                        shown[r][c].text,
                        textAlign: table.columns[c].isNumeric
                            ? pw.TextAlign.right
                            : pw.TextAlign.left,
                        style: pw.TextStyle(
                          font: _cellFont(shown[r][c], table.emphasisRow == r),
                          fontSize: TenantReportMetrics.captionSize,
                          color: shown[r][c] is TenantReportAbsentCell
                              ? palette.mutedInk
                              : palette.ink,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
        if (withheld > 0) ...<pw.Widget>[
          pw.SizedBox(height: TenantReportMetrics.spaceRow),
          pw.Text(
            '$withheld further rows are not printed here. The workbook for '
            'this period carries all ${table.rows.length}.',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: TenantReportMetrics.captionSize,
              color: palette.mutedInk,
            ),
          ),
        ],
      ],
    );
  }

  /// Figures are set in the monospace face so a column of money lines up.
  pw.Font _cellFont(TenantReportCell cell, bool emphasised) => switch (cell) {
    TenantReportTextCell() => emphasised ? fonts.semiBold : fonts.regular,
    TenantReportAbsentCell() => fonts.regular,
    _ => emphasised ? fonts.monoMedium : fonts.mono,
  };

  /// A stamp that is unambiguous six months later, in the business day's zone.
  static String _stamp(DateTime at) {
    final local = at.toUtc().add(const Duration(hours: 3));
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}
