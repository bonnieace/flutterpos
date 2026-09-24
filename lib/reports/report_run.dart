/// Gather, analyse, render, deliver - the one path every report takes.
///
/// **The range drives the fetch, never the screen.** A report is not an export
/// of whatever the surface behind it happens to have paged in: the person picks
/// a period at the moment they ask for the file, and [build] goes and reads
/// that period. What is on screen is irrelevant to what comes out, which is the
/// difference between this and a download button.
///
/// The eight reports differ only in [build]. Everything after it - which
/// renderer, what the file is called, how it reaches the person, what is said
/// back to them - is the same for all of them and lives here.
library;

import 'report_document.dart';
import 'report_file.dart';
import 'report_period.dart';
import 'render/excel_report.dart';
import 'render/pdf_report.dart';
import 'render/report_fonts.dart';
import 'render/report_palette.dart';

/// Reads a period and describes what it found.
///
/// This is the whole extension point for a new report: a function that turns a
/// period into a document. Everything it needs - repositories, the session, the
/// branding, the currency - is closed over by whoever supplies it, so this
/// layer needs to know about none of them.
typedef TenantReportBuilder =
    Future<TenantReportDocument> Function(TenantReportPeriod period);

/// What the person asked for.
final class TenantReportRequest {
  const TenantReportRequest({
    required this.period,
    required this.format,
    required this.destination,
  });

  final TenantReportPeriod period;
  final TenantReportFormat format;

  /// Where the finished file goes. The report sheet always asks for
  /// [TenantReportDestination.device] since 2026-09-23; the field stays so a
  /// caller that wants the share sheet can still ask for it.
  final TenantReportDestination destination;
}

/// How far a report has got, for a control that has to say something while it
/// works.
enum TenantReportStage {
  /// Reading the records the period covers. The long part, and the part that
  /// costs.
  gathering('Reading the records'),

  /// Laying out the document.
  rendering('Building the report'),

  /// Handing it to the file picker or the share sheet, whichever was asked
  /// for - so the wording covers both.
  delivering('Opening where to put it');

  const TenantReportStage(this.label);

  final String label;
}

/// One report, end to end.
final class TenantReportRun {
  const TenantReportRun({
    required this.kind,
    required this.support,
    required this.build,
    required this.saver,
    this.pdf,
    this.excel,
  });

  final TenantReportKind kind;

  /// What the records behind this report can honestly answer for.
  ///
  /// The picker reads it and offers only the controls that support allows, so
  /// a screen whose records carry no history never shows a date range it
  /// cannot honour.
  final TenantReportPeriodSupport support;

  final TenantReportBuilder build;

  /// Where a finished file goes. Null renders no control at all - see
  /// [TenantReportSaver].
  final TenantReportSaver? saver;

  /// Overridable so a test can pass a renderer with the built-in faces rather
  /// than loading the bundled ones.
  final TenantPdfReportRenderer? pdf;
  final TenantExcelReportRenderer? excel;

  /// Reads the period, builds the file, and hands it over.
  ///
  /// [onStage] is a callback rather than a stream: this is one-shot work, and
  /// a stream here would be ceremony around a value that changes three times.
  Future<TenantReportSaveOutcome> deliver(
    TenantReportRequest request, {
    void Function(TenantReportStage stage)? onStage,
  }) async {
    final delivery = saver;
    if (delivery == null) return TenantReportSaveOutcome.unavailable;

    onStage?.call(TenantReportStage.gathering);
    final document = await build(request.period);

    onStage?.call(TenantReportStage.rendering);
    final file = switch (request.format) {
      // **Loads the bundled faces rather than falling back to Helvetica.**
      // `TenantPdfReportRenderer.standard()` is the built-in-faces renderer,
      // meant for a test and for the sample tool. Reaching for it here is what
      // put a device-generated report in Helvetica with nothing embedded while
      // every sample rendered in the brand's own type - a gap no unit test
      // could show, because they all pass `.standard()` deliberately.
      TenantReportFormat.pdf => await (pdf ?? await _brandedPdf()).render(
        document,
      ),
      TenantReportFormat.excel =>
        await (excel ?? TenantExcelReportRenderer.standard()).render(document),
    };

    onStage?.call(TenantReportStage.delivering);
    return delivery.save(file, destination: request.destination);
  }

  /// A renderer set in the brand's own faces.
  ///
  /// The load is cached across reports, and degrades to the built-in faces on
  /// its own if the bundle cannot be read - a report set in Helvetica is worth
  /// having, and one that refused to generate is not.
  static Future<TenantPdfReportRenderer> _brandedPdf() async =>
      TenantPdfReportRenderer(
        palette: TenantReportPalette.standard,
        fonts: await TenantReportFonts.bundled(),
      );
}
