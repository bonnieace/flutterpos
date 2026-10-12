/// What comes out of the roll when somebody presses *Test this printer*.
///
/// **A printed page rather than a silent connect, at the product owner's
/// direction on 2026-09-03.** `PrinterTransport.probe` opens a socket and
/// closes it, and its answer - *the printer answered* - is the answer to a
/// question nobody in a shop is asking. What they are asking is *will a receipt
/// come out of this thing, and will it be readable*, and the only honest answer
/// to that is a piece of paper.
///
/// **It is a receipt's twin and deliberately not a receipt.** `design.md` §12
/// leaves the paper to its own surface, so this reads no token and inherits no
/// layout, exactly as `CheckoutReceiptBody` does; it shares that file's column
/// discipline (**a line is `_columns` characters, or it is a defect**), its
/// `ESC t` code-page selection, and `ReceiptText.forPrinter` for anything a
/// person typed. What it does not share is a total - there is no sale here, and
/// nothing on this page may be mistaken for one.
///
/// **The three things it proves, in the order it prints them:**
///
/// 1. **Graphics.** The mark at the top is a raster image, and the first thing
///    a printer with the wrong density setting gets wrong. **Since 2026-09-23
///    it is the business's own logo where one is published**, headed exactly
///    as a receipt is - logo, brand name, slogan - so the test page shows what
///    a receipt will look like as well as whether the printer works. With no
///    logo it is the built-in test mark.
/// 2. **The width.** The ruler line is exactly one row of the roll. If its last
///    digit is missing, or it has wrapped onto a second line, the paper setting
///    is wrong - a fault that otherwise shows up as receipts with their amounts
///    shaved off, weeks later.
/// 3. **The settings themselves**, printed as the page's own body, so the paper
///    says what it was printed with rather than the screen saying what it
///    thinks it sent.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:image/image.dart' as img;

import 'checkout_print_configuration.dart';
import 'checkout_receipt_body.dart';

/// Every word this page prints, for the reason `ReceiptWords` gives: copy
/// nobody has specified belongs in one place, where changing it is an edit
/// rather than an archaeology exercise.
abstract final class PrinterTestPageWords {
  static const String title = 'PRINTER TEST';
  static const String printerLabel = 'Printer';
  static const String paperLabel = 'Paper';
  static const String cutterLabel = 'Cutter';
  static const String printedLabel = 'Printed';
  static const String cutterFitted = 'Fitted';
  static const String cutterAbsent = 'None';

  /// **What to look at, because a test page nobody knows how to read proves
  /// nothing.** Every line is inside 32 characters, so none of them wraps on
  /// the narrower roll - which would be the page contradicting itself.
  static const List<String> instructions = <String>[
    'The line above is one whole row',
    'of this roll. If it is cut short',
    'or has wrapped, the paper width',
    'is set wrong.',
  ];

  static const List<String> footer = <String>[
    'Nothing was sold and nothing',
    'was recorded.',
  ];
}

/// Builds the ESC/POS bytes for one test page.
///
/// Takes a loaded [CapabilityProfile] for the reason `CheckoutReceiptBody`
/// does: loading one reads an asset, and a formatter that did I/O could not be
/// called from wherever the button happens to be pressed.
final class CheckoutPrinterTestPage {
  const CheckoutPrinterTestPage({
    required this.profile,
    required this.configuration,
    this.codePage = 'CP1252',
  });

  final CapabilityProfile profile;
  final TenantPrinterConfiguration configuration;

  /// The code page `ESC t` selects. See `CheckoutReceiptBody.codePage`: this is
  /// the one command that makes a shop's own name print as itself.
  final String codePage;

  /// The finished payload, ready for `PrinterTransport.send`.
  ///
  /// [businessName], [slogan] and [logo] are the receipt branding, resolved by
  /// the caller exactly as the receipt's are - this class reads no documents.
  /// [logo] is the published image file; bytes that do not decode fall back to
  /// the test mark rather than refusing the page. [at] is passed rather than
  /// taken from the wall clock, so the bytes are a function of their inputs.
  List<int> build({
    required DateTime at,
    String? businessName,
    String? slogan,
    Uint8List? logo,
  }) {
    final generator = Generator(
      paperSizeFor(configuration.paperWidth),
      profile,
    );
    final name = businessName?.trim();
    final line = slogan?.trim();
    // The receipt's own reduction of the logo, so the test page cannot print a
    // mark a receipt would not.
    final mark = receiptLogoMark(logo);
    final bytes = <int>[
      ...generator.reset(),
      ...generator.setGlobalCodeTable(codePage),
      ...generator.imageRaster(mark ?? _mark(_markSize)),
      if (name != null && name.isNotEmpty) ...<int>[
        // **The receipt's heading, at the receipt's scale**: double width,
        // centred by padding over the paper - see `CheckoutReceiptBody`.
        ...generator.emptyLines(1),
        ...generator.text(
          _centred(name, scale: 2),
          styles: const PosStyles(
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
        if (line != null && line.isNotEmpty) ...generator.text(_centred(line)),
        ...generator.hr(),
      ],
      ...generator.text(
        _centred(PrinterTestPageWords.title),
        styles: const PosStyles(bold: true, height: PosTextSize.size2),
      ),
      ...generator.hr(),
      ...generator.text(
        _pair(
          PrinterTestPageWords.printerLabel,
          configuration.endpoint.toString(),
        ),
      ),
      ...generator.text(
        _pair(PrinterTestPageWords.paperLabel, configuration.paperWidth.roll),
      ),
      ...generator.text(
        _pair(
          PrinterTestPageWords.cutterLabel,
          configuration.hasCutter
              ? PrinterTestPageWords.cutterFitted
              : PrinterTestPageWords.cutterAbsent,
        ),
      ),
      ...generator.text(_pair(PrinterTestPageWords.printedLabel, _stamp(at))),
      ...generator.hr(),
      // **The ruler, and it is most of why this page is worth the paper.** One
      // full row of the roll's own width: what comes out either fills a single
      // line and ends in the column count, or the setting is wrong.
      ...generator.text(_ruler()),
      for (final line in PrinterTestPageWords.instructions)
        ...generator.text(line),
      ...generator.hr(),
      for (final line in PrinterTestPageWords.footer)
        ...generator.text(_centred(line)),
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

  /// Enough roll past the print head to tear against, as the receipt uses.
  static const int _feedLinesWithoutCutter = 3;

  /// The mark's side in dots.
  ///
  /// **Divisible by eight, which is not a nicety.**
  /// `Generator._toRasterFormat` pads a width that is not, and its padding path
  /// re-computes the row stride wrongly - so a mark 190 dots wide prints as a
  /// smear. 192 is half of the 58mm roll's 384 dots and a third of the 80mm
  /// roll's 576, so it is a mark rather than a banner on either.
  static const int _markSize = 192;

  int get _columns => configuration.paperWidth.columns;

  /// `Printer      192.168.1.50:9100` - label left, value hard right, one row.
  ///
  /// The label is truncated rather than the value, for the reason
  /// `CheckoutReceiptBody._pair` gives: half an address is worse than a
  /// shortened word.
  String _pair(String label, String value) {
    final printable = ReceiptText.forPrinter(value);
    if (printable.length >= _columns) return printable.substring(0, _columns);
    final room = _columns - printable.length;
    final left = label.length > room - 1 ? label.substring(0, room - 1) : label;
    return left.padRight(room) + printable;
  }

  /// [text] centred in a row of `_columns`, by spaces and never by a command.
  ///
  /// The reason is `CheckoutReceiptBody._centred`'s: `Generator.text` emits an
  /// absolute dot position *and* a justification for the same line, and each
  /// printer resolves that contradiction however it likes.
  ///
  /// [scale] is the character width the line prints at, so a double-width
  /// heading is centred over the paper rather than over its left half.
  String _centred(String text, {int scale = 1}) {
    final columns = _columns ~/ scale;
    final printable = ReceiptText.forPrinter(text);
    if (printable.length >= columns) return printable.substring(0, columns);
    return ' ' * ((columns - printable.length) ~/ 2) + printable;
  }

  /// One full row, marked every five characters and ending in the column count.
  ///
  /// It reads as a ruler at a glance, and the number at the end is the figure
  /// the form was set to - so a page whose ruler ends in `32` on a roll that
  /// was set to 48 says which of the two is wrong.
  String _ruler() {
    final row = StringBuffer();
    for (var column = 1; column <= _columns; column++) {
      row.write(column % 5 == 0 ? '+' : '.');
    }
    final tail = '$_columns';
    return row.toString().substring(0, _columns - tail.length) + tail;
  }

  String _stamp(DateTime at) => printerPageStamp(at);
}

/// `3 Sep 2026 15:51`, in the zone this device is set to.
///
/// Written here rather than taken from `intl`, because every other string on
/// a printed page is measured against the roll's character count and a
/// locale-aware formatter can return one longer than the row it has to fit.
String printerPageStamp(DateTime at) {
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
  final local = at.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year} $hour:$minute';
}

/// A tick inside a filled disc, [size] dots square.
///
/// **Drawn rather than shipped as an asset**, for two reasons that are both
/// about this being the page that prints when printing is already suspect. An
/// asset is decoded through `rootBundle`, which is I/O this class has no way to
/// do and no business doing; and a photograph or a logo dithers into grey mush
/// on a one-bit head. A disc and two strokes are pure black or pure white at
/// every dot, which is the only kind of picture a thermal printer draws well.
///
/// The paper is white here because `Generator._toRasterFormat` inverts what it
/// is given: black in this bitmap is ink on the roll.
img.Image _mark(int size) {
  final image = img.Image(width: size, height: size);
  final white = img.ColorRgb8(255, 255, 255);
  final black = img.ColorRgb8(0, 0, 0);
  img.fill(image, color: white);

  final centre = size / 2;
  final radius = size * 0.46;
  // The tick as two segments, in fractions of the square rather than in dots,
  // so it is the same drawing at any size.
  final strokes = <List<double>>[
    <double>[size * 0.30, size * 0.52, size * 0.44, size * 0.66],
    <double>[size * 0.44, size * 0.66, size * 0.72, size * 0.35],
  ];
  final stroke = size * 0.075;

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x + 0.5 - centre;
      final dy = y + 0.5 - centre;
      if (dx * dx + dy * dy > radius * radius) continue;
      final onTick = strokes.any(
        (s) =>
            _distanceToSegment(x + 0.5, y + 0.5, s[0], s[1], s[2], s[3]) <=
            stroke,
      );
      image.setPixel(x, y, onTick ? white : black);
    }
  }
  return image;
}

/// How far `(px, py)` lies from the segment `(ax, ay) - (bx, by)`.
double _distanceToSegment(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final vx = bx - ax;
  final vy = by - ay;
  final lengthSquared = vx * vx + vy * vy;
  final t = lengthSquared == 0
      ? 0.0
      : (((px - ax) * vx + (py - ay) * vy) / lengthSquared).clamp(0.0, 1.0);
  final dx = px - (ax + t * vx);
  final dy = py - (ay + t * vy);
  return math.sqrt(dx * dx + dy * dy);
}
