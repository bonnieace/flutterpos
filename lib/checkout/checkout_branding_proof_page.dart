/// What comes out of the roll when a business saves its own details.
///
/// **A receipt's heading, on paper, and deliberately not a receipt.** It is
/// `CheckoutPrinterTestPage`'s sibling and follows every rule that file follows:
/// no token is read and no layout inherited (`design.md` §12 leaves the paper to
/// its own surface), a line is `_columns` characters or it is a defect, `ESC t`
/// selects the code page before a character is printed, and anything a person
/// typed goes through `ReceiptText.forPrinter`.
///
/// **What it proves, and why it is worth the paper.** A logo and a name look
/// one way on a phone and another on a 58mm thermal roll at 203dpi with no
/// greys: a pale mark disappears, a wide one is reduced to the roll's dots, and
/// a name that fits the field wraps on paper. The only honest way to show a
/// shopkeeper what their receipts will now say is to print it, which is what
/// pressing *Save details* does.
///
/// **It carries no total and no receipt number**, so nothing on this page can
/// be mistaken for evidence of a sale - the same rule the printer test page
/// keeps, stated in its own footer.
library;

import 'dart:typed_data';

import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';

import 'checkout_print_configuration.dart';
import 'checkout_receipt_body.dart';

/// Every word this page prints. See `PrinterTestPageWords` for why they live
/// together rather than inline.
abstract final class BrandingProofWords {
  static const String title = 'RECEIPT HEADING';

  static const List<String> instructions = <String>[
    'This is how the top of every',
    'receipt will now print.',
  ];

  static const List<String> footer = <String>[
    'Nothing was sold and nothing',
    'was recorded.',
  ];
}

/// Builds the ESC/POS bytes for one heading proof.
final class CheckoutBrandingProofPage {
  const CheckoutBrandingProofPage({
    required this.profile,
    required this.configuration,
    this.codePage = 'CP1252',
  });

  final CapabilityProfile profile;
  final TenantPrinterConfiguration configuration;

  /// The code page `ESC t` selects. See `CheckoutReceiptBody.codePage`.
  final String codePage;

  /// The finished payload, ready for `PrinterTransport.send`.
  ///
  /// [logo] is the image file the business published, in whatever format it
  /// published it in; it is decoded, reduced to the roll's dots and dithered
  /// here. Null - and bytes this cannot decode - print the heading without a
  /// mark rather than refusing the page.
  List<int> build({
    required DateTime at,
    required String companyName,
    String? slogan,
    Uint8List? logo,
  }) {
    final generator = Generator(
      paperSizeFor(configuration.paperWidth),
      profile,
    );
    // **The receipt's own mark, from the receipt's own builder.** The whole
    // point of this page is to show what a receipt will do, so it must not
    // reduce or dither a logo its own way. See `receiptLogoMark`.
    final mark = receiptLogoMark(logo);
    final line = slogan?.trim();
    final bytes = <int>[
      ...generator.reset(),
      ...generator.setGlobalCodeTable(codePage),
      // **The heading, spaced exactly as `CheckoutReceiptBody._heading` spaces
      // it**, blank lines included: this page is a claim about what a receipt
      // will look like, and a claim that is a line out is worth nothing.
      if (mark != null) ...<int>[
        ...generator.imageRaster(mark),
        ...generator.emptyLines(1),
      ],
      // The receipt's own heading, at the receipt's own scale: centred by
      // padding at double width, for the reason `CheckoutReceiptBody._heading`
      // gives - `ESC a 1` and an absolute position on one line contradict each
      // other, and each printer resolves that contradiction however it likes.
      ...generator.text(
        _centred(ReceiptText.forPrinter(companyName.trim()), scale: 2),
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
      if (line != null && line.isNotEmpty)
        ...generator.text(_centred(ReceiptText.forPrinter(line))),
      ...generator.emptyLines(1),
      ...generator.text('-' * _columns),
      ...generator.text(_centred(BrandingProofWords.title)),
      ...generator.text(_pair(_printedLabel, _stamp(at))),
      ...generator.text('-' * _columns),
      for (final instruction in BrandingProofWords.instructions)
        ...generator.text(instruction),
      ...generator.text('-' * _columns),
      for (final footer in BrandingProofWords.footer)
        ...generator.text(_centred(footer)),
    ];
    // A cut only where there is a cutter, for the reason `CheckoutReceiptBody`
    // records: the command is ignored by some models without one and prints a
    // control character on others.
    bytes.addAll(
      configuration.hasCutter
          ? generator.cut()
          : generator.feed(_feedLinesWithoutCutter),
    );
    return List<int>.unmodifiable(bytes);
  }

  static const String _printedLabel = 'Printed';

  /// Enough roll past the print head to tear against, as the receipt uses.
  static const int _feedLinesWithoutCutter = 3;

  int get _columns => configuration.paperWidth.columns;

  /// `Printed             3 Sep 2026 15:51` - label left, value hard right, one
  /// row. The label is truncated rather than the value, as the receipt's own
  /// pair is.
  String _pair(String label, String value) {
    final printable = ReceiptText.forPrinter(value);
    if (printable.length >= _columns) return printable.substring(0, _columns);
    final room = _columns - printable.length;
    final left = label.length > room - 1 ? label.substring(0, room - 1) : label;
    return left.padRight(room) + printable;
  }

  /// [text] centred in a row of `_columns`, by spaces and never by a command.
  ///
  /// [scale] is the character width the line prints at, so a double-width
  /// heading is centred over the paper rather than over the left half of it.
  String _centred(String text, {int scale = 1}) {
    final columns = _columns ~/ scale;
    final printable = ReceiptText.forPrinter(text);
    if (printable.length >= columns) return printable.substring(0, columns);
    return ' ' * ((columns - printable.length) ~/ 2) + printable;
  }

  /// `3 Sep 2026 15:51`, in the zone this device is set to.
  String _stamp(DateTime at) {
    final local = at.toLocal();
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year} '
        '${local.hour}:$minute';
  }
}
