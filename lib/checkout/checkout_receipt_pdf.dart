/// A receipt as a page, for a device's own print window.
///
/// **The same receipt as the paper one, drawn differently.** The rows come
/// from `checkout_receipt_content.dart`, which also drives the ESC/POS bytes,
/// so a receipt printed through a browser's or a phone's print window says
/// exactly what one printed straight to a thermal printer says. Only the
/// drawing differs: here a long name wraps by measured width rather than by
/// counted columns, and a shop called *Mũgumo Stores* keeps its `ũ`, which a
/// thermal printer's code page cannot draw.
///
/// **A paper surface, so no tokens.** `design.md` §12 says a receipt "is a
/// design surface with its own constraints", and `CheckoutReceiptBody` reads
/// no token for that reason. The sizes here are typographic points on paper,
/// chosen to sit close to what a thermal head prints at 203 dpi, and the only
/// colour is black.
///
/// **The page is the roll.** 57mm or 80mm wide, as long as the receipt: the
/// `pdf` package sizes a page of unbounded height to what is on it, so there
/// is no blank tail to waste paper on.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../reports/render/report_fonts.dart';
import 'checkout_branding_proof_page.dart' show BrandingProofWords;
import 'checkout_print_configuration.dart';
import 'checkout_printer_test_page.dart'
    show PrinterTestPageWords, printerPageStamp;
import 'checkout_receipt_body.dart' show ReceiptWords, receiptLogoMark;
import 'checkout_receipt_content.dart';
import 'checkout_sale.dart';

/// The words only a print-window page uses.
///
/// The paper test page's instructions are about counting columns on a roll,
/// which a page the device lays out itself has no use for.
abstract final class ReceiptPdfWords {
  /// What the test page names as the printer: the device chooses it.
  static const String printer = 'Print dialog';

  static const String testInstruction =
      'If this page printed at full width, receipts will too. If it came out '
      'small or cut off, check the paper size in the print window.';
}

/// The page a receipt is laid on: the roll's own width, as long as the
/// receipt.
PdfPageFormat receiptPageFormat(PrinterPaperWidth width) => switch (width) {
  PrinterPaperWidth.columns32 => PdfPageFormat.roll57,
  PrinterPaperWidth.columns48 => PdfPageFormat.roll80,
};

/// Lays receipts, and the printer pages that vouch for them, out as PDFs.
///
/// **Takes loaded fonts rather than loading them**, for the reason
/// `CheckoutReceiptBody` takes a loaded profile: a renderer that reached for
/// an asset bundle could not be called from wherever a sale is committed, nor
/// exercised without a Flutter binding.
final class CheckoutReceiptPdf {
  const CheckoutReceiptPdf({required this.fonts, required this.paperWidth});

  final TenantReportFonts fonts;
  final PrinterPaperWidth paperWidth;

  /// [sale]'s receipt.
  Future<Uint8List> build(
    CheckoutReceiptSale sale, {
    String? businessName,
    String? servedBy,
    Uint8List? logo,
    String? slogan,
  }) => _save(
    compose(
      checkoutReceiptRows(
        sale,
        businessName: businessName,
        servedBy: servedBy,
        logo: logo,
        slogan: slogan,
      ),
    ),
  );

  /// The Printer page's test print, for the print-window printer.
  ///
  /// **The receipt's own heading, from the receipt's own rows**, so the test
  /// shows what a receipt's top will look like rather than something like it.
  Future<Uint8List> testPage({
    required DateTime at,
    String? businessName,
    String? slogan,
    Uint8List? logo,
  }) => _save(
    compose(<CheckoutReceiptRow>[
      ...checkoutReceiptHeadingRows(
        businessName: businessName,
        logo: logo,
        slogan: slogan,
      ),
      const ReceiptCentredRow(PrinterTestPageWords.title),
      const ReceiptPairRow(
        PrinterTestPageWords.printerLabel,
        ReceiptPdfWords.printer,
      ),
      ReceiptPairRow(PrinterTestPageWords.paperLabel, paperWidth.roll),
      ReceiptPairRow(PrinterTestPageWords.printedLabel, printerPageStamp(at)),
      const ReceiptRuleRow(),
      const ReceiptCentredRow(ReceiptPdfWords.testInstruction),
      const ReceiptGapRow(),
      ReceiptCentredRow(PrinterTestPageWords.footer.join(' ')),
    ], title: PrinterTestPageWords.title),
  );

  /// The business details screen's proof of a new heading.
  Future<Uint8List> brandingProof({
    required DateTime at,
    required String companyName,
    String? slogan,
    Uint8List? logo,
  }) => _save(
    compose(<CheckoutReceiptRow>[
      ...checkoutReceiptHeadingRows(
        businessName: companyName,
        logo: logo,
        slogan: slogan,
      ),
      const ReceiptCentredRow(BrandingProofWords.title),
      ReceiptPairRow(PrinterTestPageWords.printedLabel, printerPageStamp(at)),
      const ReceiptRuleRow(),
      ReceiptCentredRow(BrandingProofWords.instructions.join(' ')),
      const ReceiptRuleRow(),
      ReceiptCentredRow(BrandingProofWords.footer.join(' ')),
    ], title: BrandingProofWords.title),
  );

  /// [rows] as an unsaved document, one roll-shaped page long.
  @visibleForTesting
  pw.Document compose(
    List<CheckoutReceiptRow> rows, {
    String title = ReceiptWords.receiptLabel,
  }) {
    final format = receiptPageFormat(paperWidth);
    return pw.Document(title: title)..addPage(
      pw.Page(
        pageFormat: format,
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
        ).copyWith(defaultTextStyle: const pw.TextStyle(fontSize: _body)),
        // **Pinned to the roll's full width.** A page of unbounded height is
        // sized to its content in both directions, so a receipt of short lines
        // would otherwise come out narrower than the roll and be centred or
        // scaled by whatever the print window decides.
        build: (_) => pw.SizedBox(
          width: format.availableWidth,
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[for (final row in rows) _row(row)],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _save(pw.Document document) => document.save();

  pw.Widget _row(CheckoutReceiptRow row) => switch (row) {
    ReceiptLogoRow(:final bytes) => _logo(bytes),
    ReceiptTitleRow(:final text) => pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: _title, fontWeight: pw.FontWeight.bold),
    ),
    ReceiptCentredRow(:final text) => pw.Text(
      text,
      textAlign: pw.TextAlign.center,
    ),
    ReceiptGapRow() => pw.SizedBox(height: _body),
    ReceiptRuleRow() => pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: _ruleMargin),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(width: _ruleWidth, style: pw.BorderStyle.dashed),
        ),
      ),
    ),
    ReceiptPairRow(:final label, :final value, :final emphasis) => _columns(
      label,
      value,
      switch (emphasis) {
        ReceiptEmphasis.plain => null,
        ReceiptEmphasis.strong => pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ReceiptEmphasis.total => pw.TextStyle(
          fontSize: _total,
          fontWeight: pw.FontWeight.bold,
        ),
      },
    ),
    // A long description wraps inside its own column and the amount sits on
    // the row the wrap ends on - the paper receipt's layout, for its reasons.
    ReceiptItemRow(:final description, :final amount) => _columns(
      description,
      amount,
      null,
    ),
  };

  /// [left] in a column of its own, [right] against the right edge, on the
  /// last line [left] takes.
  pw.Widget _columns(String left, String right, pw.TextStyle? style) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: <pw.Widget>[
      pw.Expanded(child: pw.Text(left, style: style)),
      pw.SizedBox(width: _columnGap),
      pw.Text(right, style: style),
    ],
  );

  /// The mark a thermal printer would print, at the size it would print it.
  ///
  /// **The receipt's own reduction, `receiptLogoMark`**, rather than the
  /// original picture: it is what turns a cut-out logo into ink on white, and
  /// a page that printed the logo its own way would be a different receipt.
  /// Nothing - and no gap - for a mark no decoder recognises.
  pw.Widget _logo(Uint8List bytes) {
    final mark = receiptLogoMark(bytes);
    if (mark == null) return pw.SizedBox();
    return pw.Column(
      children: <pw.Widget>[
        pw.Image(
          pw.MemoryImage(img.encodePng(mark)),
          width: mark.width * _pointsPerDot,
          height: mark.height * _pointsPerDot,
        ),
        pw.SizedBox(height: _body),
      ],
    );
  }

  /// Body text, in points: close to a thermal printer's 24-dot Font A.
  static const double _body = 9;

  /// The business's name, which a thermal printer prints at double size.
  static const double _title = 16;

  /// The total, which a thermal printer prints at double height.
  static const double _total = 12;

  /// The space a rule keeps above and below itself.
  static const double _ruleMargin = 3;

  static const double _ruleWidth = 0.6;

  /// The least space between a description and its amount.
  static const double _columnGap = 6;

  /// One thermal printer dot, in points: 72 points to the inch over 203 dots.
  static const double _pointsPerDot = 72 / 203;
}
