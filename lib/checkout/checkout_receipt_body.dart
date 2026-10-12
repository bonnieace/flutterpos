/// What is on the paper: the ESC/POS body of one sale's receipt.
///
/// **`design.md` §12 says a receipt "is a design surface with its own
/// constraints and will not inherit from this document", and this file is what
/// that means in practice.** Not that no layout may exist — that nothing in
/// §2.1, §2.2 or §2.3 applies here. A thermal printer has no colour, no radius
/// and no type scale; it has a **column count**, three emphasis levels, and a
/// cut. So the structure below is derived from the roll and the wording from
/// §8's content rules, and no token is read anywhere in this file.
///
/// **Every string a person reads is in [ReceiptWords], on purpose.** The
/// product owner has not specified the copy, so it is written once, in one
/// class, where changing it is an edit rather than an archaeology exercise.
/// Nothing here concatenates a literal into a line.
///
/// **The code page is set explicitly and that is the whole reason this uses
/// `Generator` rather than building bytes by hand.**
/// `docs/printer_transport.md`'s scope line says the generator "already emits
/// code-page selection — which is precisely what `printer_network`'s
/// hand-rolled `ReceiptBuilder` gets wrong (it Latin-1 encodes bytes
/// `0x80`–`0xFF` and never emits `ESC t`, so every non-ASCII character prints
/// as the printer's default code page instead)". **Kenyan business names carry
/// non-ASCII characters**, so this is not hypothetical: without `ESC t` a shop
/// called *Kahawa Duka* prints correctly and one called *Mũgumo Stores* does
/// not.
///
/// **It never states a figure without its currency code.** §8 rule 8. The
/// payload carries the code the sale was priced with, and a receipt printed
/// weeks later still shows that one rather than today's.
///
/// **It says nothing about whether the paper moved.** The transport cannot know
/// and neither can this; the confirmation a person sees is
/// `PrinterFailureNotice.sent`.
library;

import 'dart:typed_data';

import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:image/image.dart' as img;

import 'checkout_print_configuration.dart';
import 'checkout_receipt_content.dart';
import 'checkout_sale.dart';
import 'checkout_tender.dart';

/// What a single-byte printer can actually be sent.
///
/// **The generator throws on a character its codec cannot encode, and that is
/// the defect this class exists to stop.** `Generator` encodes with `latin1` by
/// default, and `latin1.encode('Mũgumo Stores')` raises
/// `Invalid argument (string): Contains invalid characters.` — so a shop whose
/// name carries a macron would have **crashed the receipt**, not merely
/// mis-printed it. That is worse than the mojibake
/// `docs/printer_transport.md` §2 warns about, and it was found by the test
/// written for that warning.
///
/// **A thermal printer genuinely cannot render `ũ`.** It has no glyph for it in
/// any single-byte code page this app selects, so there is no correct rendering
/// to preserve — the choice is between a legible substitution and a failed
/// sale. **Legible substitution wins**, and it is lossy on purpose:
///
/// - Letters with a base form in the Latin alphabet lose their mark: `ũ` → `u`,
///   `ĩ` → `i`. Those two are not decoration — they are Gĩkũyũ orthography, and
///   business names in this market carry them.
/// - Anything else outside the code page becomes `?`, which reads as *this
///   printer could not draw that* rather than as a missing letter.
///
/// **Nothing here silently drops a character**, because a name shortened
/// without trace is a name a customer cannot match to the shop.
abstract final class ReceiptText {
  /// The letters worth mapping rather than punching out.
  ///
  /// Deliberately short. It covers the marks that appear in East African
  /// orthography and in the Latin-1 range the code page already handles; a
  /// longer table is a transliteration library, which this is not pretending to
  /// be.
  static const Map<int, String> _substitutions = <int, String>{
    0x0169: 'u', // ũ
    0x0168: 'U', // Ũ
    0x0129: 'i', // ĩ
    0x0128: 'I', // Ĩ
    0x0113: 'e', // ē
    0x0112: 'E', // Ē
    0x014D: 'o', // ō
    0x014C: 'O', // Ō
    0x0101: 'a', // ā
    0x0100: 'A', // Ā
    0x2019: "'", // a curly apostrophe, which word processors insert
    0x2018: "'",
    0x201C: '"',
    0x201D: '"',
    0x2013: '-', // en dash
    0x2014: '-', // em dash
  };

  /// The unrepresentable mark. Visible on purpose.
  static const String _unrenderable = '?';

  /// [value], with everything the printer cannot draw replaced.
  static String forPrinter(String value) {
    final out = StringBuffer();
    for (final rune in value.runes) {
      if (rune <= 0xFF) {
        out.writeCharCode(rune);
        continue;
      }
      out.write(_substitutions[rune] ?? _unrenderable);
    }
    return out.toString();
  }
}

/// Every word this app prints on paper.
///
/// **One class, because the copy is unspecified.** `design.md` §12 leaves the
/// receipt to its own surface and the product owner has not written it, so what
/// is here is derived from §8's rules — name things the way the shopkeeper
/// does, state what is true — and is expected to be replaced rather than
/// extended. **A line added anywhere else is a line nobody can find.**
abstract final class ReceiptWords {
  static const String receiptLabel = 'Receipt';
  static const String dateLabel = 'Date';
  static const String servedByLabel = 'Served by';
  static const String customerLabel = 'Customer';
  static const String kraPinLabel = 'KRA PIN';
  static const String subtotalLabel = 'Subtotal';
  static const String discountLabel = 'Discount';
  static const String totalLabel = 'TOTAL';
  static const String paidByLabel = 'Paid by';

  /// A credit sale's three lines: what was paid at the counter, what this
  /// sale left owing, and what the customer owes in all - the figure this
  /// till could see when it sold, which is what a customer leaves knowing.
  static const String paidNowLabel = 'Paid now';
  static const String owedLabel = 'On credit';
  static const String balanceLabel = 'Balance owed';

  /// §8 rule 2, state what is true: this is a record of a sale, and saying so
  /// is more use to a customer returning something than a pleasantry is.
  ///
  /// **29 characters, and the count is the point.** `Keep this receipt to
  /// return an item` was 34, which wraps on a 32-column roll and leaves a
  /// centred line with the word `em` under it. A printed line that wraps looks
  /// like a fault rather than like copy, and nothing catches it but arithmetic
  /// - see [ReceiptWords.longestLineFits].
  static const String footer = 'Keep this receipt for returns';

  /// Printed where the business has published no name.
  ///
  /// **Not blank, and not the tenant ID.** A receipt with no heading looks
  /// like a misprint, and a document ID printed at a customer is §8 rule 1's
  /// own worked example of what not to do.
  static const String unnamedBusiness = 'Sales receipt';

  /// How a tender is named on paper.
  ///
  /// **`CheckoutTender.label` rather than a second table**, and the enum's own
  /// doc comment is the argument: it calls that field "the customer-facing name
  /// of the payment method", which is exactly what a receipt prints. A private
  /// mapping here would be a second vocabulary for one thing, drifting the
  /// moment somebody renames M-Pesa on screen and not on paper.
  ///
  /// Null for a sale that recorded no tender, and **the receipt then prints no
  /// "Paid by" line at all**, since 2026-09-29 - the product owner removed the
  /// "Not recorded" it used to print. A blank beside the label would read as a
  /// printer fault, so the label goes with the value.
  static String? tender(CheckoutTender? tender) => tender?.label;

  /// Every word above, for the test that measures them.
  static const List<String> all = <String>[
    receiptLabel,
    dateLabel,
    servedByLabel,
    customerLabel,
    kraPinLabel,
    subtotalLabel,
    discountLabel,
    totalLabel,
    paidByLabel,
    paidNowLabel,
    owedLabel,
    balanceLabel,
    footer,
    unnamedBusiness,
  ];

  /// Whether every fixed string fits the **narrowest** roll on its own line.
  ///
  /// **The one invariant that copy cannot break silently.** A line longer than
  /// the roll does not fail, it *wraps* - and a centred footer with two words
  /// under it reads as a broken printer rather than as a sentence. There is no
  /// screenshot of paper and never will be, so this arithmetic is the whole of
  /// the review.
  ///
  /// It measures the fixed words only. A product name or a shop name is the
  /// shopkeeper's and may be any length; those wrap by design.
  static bool get longestLineFits =>
      all.every((word) => word.length <= PrinterPaperWidth.columns32.columns);
}

/// The width a printed logo is reduced to, in dots.
///
/// **Divisible by eight, which is not a nicety.** `Generator._toRasterFormat`
/// pads a width that is not, and its padding path recomputes the row stride
/// wrongly - so a mark 190 dots wide prints as a smear. 192 is half of the 58mm
/// roll's 384 dots and a third of the 80mm roll's 576, so it is a mark rather
/// than a banner on either.
const int receiptLogoWidthDots = 192;

/// The tallest a printed logo may be, so a portrait mark cannot push the name
/// off the top of the paper.
const int receiptLogoMaximumHeightDots = 192;

/// [logo] as dots a thermal head can print, or null where there is nothing to
/// draw - no bytes, or bytes no decoder recognises.
///
/// **Flattened onto white before anything else, and that is the bug this
/// function exists to hold in one place.** `Generator._toRasterFormat` inverts
/// the image and reads the colour channels only; a transparent pixel is
/// transparent *black*, so a cut-out logo - which is exactly what the business
/// details screen's *Remove background* produces - inverts to white-on-black
/// and prints as a solid black rectangle with the mark punched out of it.
/// Compositing onto white first is what makes transparency mean paper.
///
/// **Greyscale then Floyd-Steinberg.** A thermal head prints a dot or it does
/// not, and a flat threshold turns anything with shading in it into a blot;
/// dithering is what keeps a gradient legible at 203dpi.
img.Image? receiptLogoMark(Uint8List? logo) {
  if (logo == null || logo.isEmpty) return null;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(logo);
  } on Object {
    return null;
  }
  if (decoded == null) return null;
  // The width is what is fixed and the height follows it: a logo is fitted to
  // the roll, never stretched to it.
  var sized = img.copyResize(
    decoded,
    width: receiptLogoWidthDots,
    interpolation: img.Interpolation.average,
  );
  if (sized.height > receiptLogoMaximumHeightDots) {
    final tall = img.copyResize(
      decoded,
      height: receiptLogoMaximumHeightDots,
      interpolation: img.Interpolation.average,
    );
    // Padded back out to a multiple of eight, for the reason above, and centred
    // rather than widened to fill the roll.
    sized = img.copyExpandCanvas(
      tall,
      newWidth: (tall.width + 7) ~/ 8 * 8,
      newHeight: tall.height,
      position: img.ExpandCanvasPosition.center,
      backgroundColor: img.ColorRgb8(255, 255, 255),
    );
  }
  final paper = img.Image(width: sized.width, height: sized.height)
    ..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(paper, sized);
  final mark = _flattened(img.ditherImage(img.grayscale(paper)));
  // **A picture whose ink is white prints its shape instead of nothing.** A
  // logo drawn light-on-dark and then cut out is all subject and no ink: every
  // pixel that survives is pale, so a faithful rendering is a blank strip of
  // paper. What the shopkeeper means by that picture is the shape, and the
  // shape is exactly what the alpha channel holds.
  if (_inkCoverage(mark) >= _blankMarkCoverage) return mark;
  final shape = _alphaAsInk(sized);
  return shape == null || _inkCoverage(shape) < _blankMarkCoverage
      ? mark
      : shape;
}

/// Below this share of fired dots a mark is a blank strip of paper.
const double _blankMarkCoverage = 0.01;

/// [dithered] as plain 8-bit RGB, with no palette behind it.
///
/// **This is the bug that printed a logo inside a black rectangle**, found on a
/// device on 2026-09-05. `img.ditherImage` answers with a *palette* image, and
/// `Generator._toRasterFormat` - which greyscales, inverts and then reads the
/// red channel out of `getBytes` - does not survive one: the ground came back
/// as every dot fired and the subject as none, so a black silhouette on white
/// paper printed as a white silhouette in a black block. Flattening the palette
/// into ordinary pixels is what makes the package see the picture that is
/// actually there.
img.Image _flattened(img.Image dithered) {
  final flat = img.Image(
    width: dithered.width,
    height: dithered.height,
    numChannels: 3,
  );
  for (var y = 0; y < dithered.height; y++) {
    for (var x = 0; x < dithered.width; x++) {
      final value = dithered.getPixel(x, y).luminance < 128 ? 0 : 255;
      flat.setPixelRgb(x, y, value, value, value);
    }
  }
  return flat;
}

/// [source]'s opaque pixels as ink, or null where it has no alpha to read.
img.Image? _alphaAsInk(img.Image source) {
  if (source.numChannels < 4) return null;
  final flat = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 3,
  );
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final value = source.getPixel(x, y).a >= 128 ? 0 : 255;
      flat.setPixelRgb(x, y, value, value, value);
    }
  }
  return flat;
}

/// The share of [mark] that will fire a dot.
double _inkCoverage(img.Image mark) {
  var ink = 0;
  for (var y = 0; y < mark.height; y++) {
    for (var x = 0; x < mark.width; x++) {
      if (mark.getPixel(x, y).luminance < 128) ink++;
    }
  }
  return ink / (mark.width * mark.height);
}

/// The two rolls, as the generator's own paper sizes.
///
/// `PrinterPaperWidth` is the durable value and this is the mapping to the
/// package. They are separate because the stored value must not change if the
/// package renames a constant.
PaperSize paperSizeFor(PrinterPaperWidth width) => switch (width) {
  PrinterPaperWidth.columns32 => PaperSize.mm58,
  PrinterPaperWidth.columns48 => PaperSize.mm80,
};

/// Builds the ESC/POS bytes for one sale.
///
/// **Takes a loaded [CapabilityProfile] rather than loading one**, because
/// `CapabilityProfile.load` reads an asset through `rootBundle` and a formatter
/// that did I/O could not be called from wherever a sale happens to be
/// committed. The composition root loads it once.
final class CheckoutReceiptBody {
  const CheckoutReceiptBody({
    required this.profile,
    required this.configuration,
    this.codePage = 'CP1252',
  });

  final CapabilityProfile profile;
  final TenantPrinterConfiguration configuration;

  /// The code page `ESC t` selects.
  ///
  /// **CP1252 rather than the printer's default**, which is what makes an
  /// accented or macronned character print as itself. It is a parameter
  /// because a printer whose profile lacks it needs a different one, and
  /// discovering that on a device should not mean editing this file.
  final String codePage;

  /// The finished payload, ready for `PrinterTransport.send`.
  ///
  /// [businessName] is the shop's own name, resolved by the caller from
  /// branding exactly as the home's title is — this class does not read
  /// documents. **What is printed is decided in `checkout_receipt_content.dart`
  /// and drawn here**, so a receipt and its PDF in a print window say the same
  /// thing.
  List<int> build(
    CheckoutReceiptSale sale, {
    String? businessName,
    String? servedBy,
    Uint8List? logo,
    String? slogan,
  }) {
    final generator = Generator(
      paperSizeFor(configuration.paperWidth),
      profile,
    );
    final bytes = <int>[
      ...generator.reset(),
      // **`ESC t` before a single character is printed.** See the library note:
      // this one command is the difference between a shop's own name printing
      // and printing as mojibake.
      ...generator.setGlobalCodeTable(codePage),
      for (final row in checkoutReceiptRows(
        sale,
        businessName: businessName,
        servedBy: servedBy,
        // **Rastered into the bytes, not referenced.** A job is re-sent as it
        // was built, so the logo a receipt printed with is the one it was
        // created with, whatever the business publishes afterwards.
        logo: logo,
        slogan: slogan,
      ))
        ..._row(generator, row),
    ];
    // **A cut only where there is a cutter**, which is the one thing the
    // configuration's `hasCutter` decides. A cut command to a printer without
    // one is ignored by some models and prints a control character on others;
    // feed lines are what a person tears against.
    bytes.addAll(
      configuration.hasCutter
          ? generator.cut()
          : generator.feed(_feedLinesWithoutCutter),
    );
    return List<int>.unmodifiable(bytes);
  }

  /// Enough roll past the print head to tear against. Three is what clears a
  /// typical 58mm mechanism; it is not a design token and does not pretend to
  /// be one.
  static const int _feedLinesWithoutCutter = 3;

  /// The roll's width in characters, and the only geometry this class uses.
  ///
  /// **Every line is padded to exactly this many characters and nothing is
  /// positioned by dot**, which is the fix for a defect found on a real 80mm
  /// printer on 2026-08-18: amounts lost their last digit and a product name
  /// merged with its own price.
  ///
  /// **The cause was in the package, and it is worth writing down.**
  /// `Generator.row` places each column at an absolute dot position derived from
  /// `PaperSize.width`, which `flutter_esc_pos_utils` reports as **558** for an
  /// 80mm roll while treating that same roll as **48 characters** - and 48
  /// characters of Font A is **576** dots. Its own two numbers disagree by a
  /// character and a half. `Generator.text` is worse for this purpose: it emits
  /// an absolute position **and** a justification command for the same line, so
  /// a right-aligned amount is told both *start at dot 0* and *right-align*, and
  /// each printer resolves that contradiction however it likes.
  ///
  /// Spaces are unambiguous, and the roll's character count is a figure a person
  /// can verify with `tool/printer_width_ruler.dart`. That is the whole contract:
  /// **a line is [_columns] characters, or it is a defect.**
  int get _columns => configuration.paperWidth.columns;

  /// One row of the receipt, as the bytes that draw it.
  ///
  /// **Everything the shopkeeper typed goes through `ReceiptText.forPrinter`
  /// here, and only here**, because this renderer is the one whose code page
  /// cannot draw `ũ`. The fixed words are already in it, so for them it
  /// changes nothing.
  List<int> _row(Generator generator, CheckoutReceiptRow row) => switch (row) {
    // **One empty line under the mark, and it is deliberate.** `GS v 0`
    // advances the paper by exactly the height of the image and stops, so
    // without it the first row of dots in the name sits against the last row
    // of the logo. A mark no decoder recognises prints nothing - and no gap.
    ReceiptLogoRow(:final bytes) => <int>[
      if (receiptLogoMark(bytes) case final mark?) ...<int>[
        ...generator.imageRaster(mark),
        ...generator.emptyLines(1),
      ],
    ],
    // Centred by padding at double width, so the name sits over the middle of
    // the paper rather than wherever the printer decides `ESC a 1` means when
    // an absolute position has also been set on the same line.
    ReceiptTitleRow(:final text) => generator.text(
      _centred(ReceiptText.forPrinter(text), scale: 2),
      styles: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    ),
    ReceiptCentredRow(:final text) => generator.text(
      _centred(ReceiptText.forPrinter(text)),
    ),
    ReceiptGapRow() => generator.emptyLines(1),
    ReceiptRuleRow() => _rule(generator),
    // **The whole row takes the emphasis, never half of it.** Emphasising one
    // half of a line needs two writes to that line, and two writes to one line
    // is exactly what was mis-positioning them. Double height changes the
    // glyphs' height and not their width, so the padding is unaffected by it.
    ReceiptPairRow(:final label, :final value, :final emphasis) =>
      generator.text(
        _pair(ReceiptText.forPrinter(label), ReceiptText.forPrinter(value)),
        styles: switch (emphasis) {
          ReceiptEmphasis.plain => const PosStyles(),
          ReceiptEmphasis.strong => const PosStyles(bold: true),
          ReceiptEmphasis.total => const PosStyles(
            bold: true,
            height: PosTextSize.size2,
          ),
        },
      ),
    ReceiptItemRow(:final description, :final amount) => _item(
      generator,
      ReceiptText.forPrinter(description),
      amount,
    ),
  };

  /// [label] on the left, [value] hard against the right, in one full line.
  ///
  /// The label is truncated rather than the value: a value is a receipt number,
  /// a date or money, and half of any of those is worse than a shortened word.
  /// At least one space always separates them.
  String _pair(String label, String value) {
    if (value.length >= _columns) return value.substring(0, _columns);
    final room = _columns - value.length;
    final left = label.length > room - 1 ? label.substring(0, room - 1) : label;
    return left.padRight(room) + value;
  }

  // **No `_right` any more, and its absence is the check on this change.** It
  // put a value hard against the right of a line *with nothing on the left*,
  // and the only caller was the sale line whose amount had been exiled to a row
  // of its own. Every amount on this receipt now shares a row with the words it
  // belongs to, so there is nothing left for it to do.

  /// [text] centred in a line of [_columns] characters, at [scale] times normal
  /// glyph width.
  ///
  /// **Only the left padding is emitted.** A centred line padded on both sides is
  /// exactly full, and a printer that wraps at its last column would turn those
  /// trailing spaces into an empty line.
  String _centred(String text, {int scale = 1}) {
    final room = _columns ~/ scale;
    if (text.length >= room) return text.substring(0, room);
    return ' ' * ((room - text.length) ~/ 2) + text;
  }

  /// A full-width rule.
  ///
  /// **Padded here rather than `generator.hr()`**, so every line on the receipt
  /// is built the same way and a rule cannot disagree with the rows it separates.
  List<int> _rule(Generator generator) => generator.text('-' * _columns);

  /// One sale line: the name in its own column, the amount against the right.
  ///
  /// **A receipt has two columns and this draws them, which is the whole of the
  /// 2026-08-26 change.** It used to print every line over two rows - the
  /// description on one, the amount right-aligned on the next - while the
  /// totals below used [_pair] on a single row. So a customer read `Subtotal`
  /// and `KES 406.00` aligned, and then the items that made them up as a ragged
  /// column of names with prices floating underneath. Two layouts for the same
  /// label-and-money relationship, on one piece of paper.
  ///
  /// **The name column is the roll less the amount and one space**, and it is
  /// the *only* width the description is ever laid into. A long name wraps
  /// inside that column rather than across the whole roll, so the price column
  /// stays empty above the price - which is what makes a wrapped line still
  /// read as one row of a table rather than as prose with a number after it.
  ///
  /// **The amount goes on the row the wrap ends on**, never on a line of its
  /// own. That was the last thing separating a long line from a short one, and
  /// there is now no case where a price sits alone.
  ///
  /// **A product name is never truncated.** That was the real point of the old
  /// two-row form and it is kept exactly: the name takes as many rows of its
  /// column as it needs.
  ///
  /// The old comment defending two rows had its arithmetic wrong, which is why
  /// it stood: it claimed a 32-column line would cut the name "to about twelve
  /// characters", where the real budget is 21 - and `2 x Maize flour 2kg` is
  /// nineteen. The common case always fitted.
  List<int> _item(Generator generator, String description, String amount) {
    final rows = _wrapped(description, _nameColumn(amount));
    return <int>[
      // Every row but the last is name only; the last carries the amount.
      for (final row in rows.take(rows.length - 1)) ...generator.text(row),
      ...generator.text(_pair(rows.last, amount)),
    ];
  }

  /// How wide the name column is, given the amount that shares its row.
  ///
  /// The roll, less the amount, less the one space [_pair] always keeps between
  /// them. Clamped at 1 rather than allowed to go negative: an amount wider
  /// than the whole roll is a degenerate case [_pair] already handles by
  /// truncating the value, and this must not hand [_wrapped] a width it would
  /// loop forever on.
  int _nameColumn(String amount) {
    final room = _columns - amount.length - 1;
    return room < 1 ? 1 : room;
  }

  /// [text] broken into lines of at most [width] characters.
  ///
  /// **Word boundaries where there are any, and a hard break where there are
  /// not.** A single token longer than the column - a SKU pasted into a product
  /// name, say - has no boundary to break on, and letting that one case
  /// overflow would put back the defect this exists to fix: before it, a
  /// description one character past the roll was emitted raw and the printer
  /// broke it wherever it happened to run out, mid-word. Every character is
  /// still on the paper; only the choice of where the break falls has moved
  /// from the machine to here.
  ///
  /// Never returns empty: a nameless product would otherwise print no row at
  /// all, which reads as a sale line that was silently dropped.
  List<String> _wrapped(String text, int width) {
    final rows = <String>[];
    var line = '';

    void flush() {
      if (line.isNotEmpty) {
        rows.add(line);
        line = '';
      }
    }

    for (final word in text.split(' ')) {
      var pending = word;
      while (pending.length > width) {
        flush();
        rows.add(pending.substring(0, width));
        pending = pending.substring(width);
      }
      if (pending.isEmpty) continue;
      final candidate = line.isEmpty ? pending : '$line $pending';
      if (candidate.length <= width) {
        line = candidate;
      } else {
        flush();
        line = pending;
      }
    }
    flush();
    return rows.isEmpty ? <String>[''] : rows;
  }
}
