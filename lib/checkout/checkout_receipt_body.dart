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

import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';

import 'checkout_print_configuration.dart';
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
  static const String subtotalLabel = 'Subtotal';
  static const String discountLabel = 'Discount';
  static const String totalLabel = 'TOTAL';
  static const String paidByLabel = 'Paid by';

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
  /// The null case is a sale that recorded no tender. **Not blank** — a blank
  /// beside "Paid by" reads as a printer fault rather than as missing data.
  static String tender(CheckoutTender? tender) =>
      tender?.label ?? 'Not recorded';

  /// Every word above, for the test that measures them.
  static const List<String> all = <String>[
    receiptLabel,
    dateLabel,
    servedByLabel,
    subtotalLabel,
    discountLabel,
    totalLabel,
    paidByLabel,
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
  static bool get longestLineFits => all.every(
    (word) => word.length <= PrinterPaperWidth.columns32.columns,
  );
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
  /// documents.
  List<int> build(
    CheckoutSalePayload sale, {
    String? businessName,
    String? servedBy,
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
      ..._heading(generator, businessName),
      ..._provenance(generator, sale, servedBy),
      ..._lines(generator, sale),
      ..._totals(generator, sale),
      ..._footer(generator, sale),
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

  /// [value] hard against the right of a full line.
  String _right(String value) => value.length >= _columns
      ? value.substring(0, _columns)
      : value.padLeft(_columns);

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

  List<int> _heading(Generator generator, String? businessName) => <int>[
    ...generator.text(
      // Centred by padding at double width, so the name sits over the middle of
      // the paper rather than wherever the printer decides `ESC a 1` means when
      // an absolute position has also been set on the same line.
      _centred(
        ReceiptText.forPrinter(
          businessName?.trim().isNotEmpty ?? false
              ? businessName!.trim()
              : ReceiptWords.unnamedBusiness,
        ),
        scale: 2,
      ),
      styles: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    ),
    ..._rule(generator),
  ];

  List<int> _provenance(
    Generator generator,
    CheckoutSalePayload sale,
    String? servedBy,
  ) => <int>[
    // The receipt number is the thing a person quotes on the phone, so it is
    // first and it is emphasised. It is also the queue's idempotency key, which
    // means the paper and the durable record cannot disagree about which sale
    // this is.
    //
    // **The whole row is bold, not just the number.** Emphasising one half of a
    // line needs two writes to that line, and two writes to one line is exactly
    // what was mis-positioning them.
    ...generator.text(
      _pair(ReceiptWords.receiptLabel, sale.receiptNumber),
      styles: const PosStyles(bold: true),
    ),
    ...generator.text(_pair(ReceiptWords.dateLabel, sale.businessDate)),
    if (servedBy != null && servedBy.trim().isNotEmpty)
      ...generator.text(
        _pair(
          ReceiptWords.servedByLabel,
          ReceiptText.forPrinter(servedBy.trim()),
        ),
      ),
    ..._rule(generator),
  ];

  /// One line per sale line, over two printed rows.
  ///
  /// **Two rows rather than one, and the roll decides it.** A 32-column line
  /// cannot hold `2 x Maize flour 2kg` and `KES 271.00` side by side without
  /// truncating the product name to about twelve characters — and the name is
  /// the thing a customer checks. So the description takes a whole line and the
  /// amount is right-aligned under it. At 48 columns there is room for one row,
  /// but it stays two: a receipt whose shape changes with the roll is two
  /// layouts to reason about, and nobody is comparing them side by side.
  ///
  /// **They were arriving on one line anyway**, which was the clearest symptom
  /// of the positioning defect: two `text()` calls, each with its own line feed,
  /// printed as a single row with the price sliced.
  List<int> _lines(Generator generator, CheckoutSalePayload sale) {
    final bytes = <int>[];
    for (final line in sale.lines) {
      bytes.addAll(
        generator.text(
          ReceiptText.forPrinter('${line.quantity} x ${line.name}'),
        ),
      );
      bytes.addAll(
        generator.text(_right(_money(sale.currency, line.lineTotalMinor))),
      );
    }
    bytes.addAll(_rule(generator));
    return bytes;
  }

  List<int> _totals(Generator generator, CheckoutSalePayload sale) => <int>[
    ..._amount(generator, ReceiptWords.subtotalLabel, sale, sale.subtotalMinor),
    // **A discount line only where there was a discount.** A permanent
    // `Discount  KES 0.00` teaches a customer to ignore the line, which is
    // the one place it matters.
    if (sale.discountMinor != 0)
      ..._amount(
        generator,
        ReceiptWords.discountLabel,
        sale,
        sale.discountMinor,
      ),
    // Double height applies to the whole row. It changes the glyphs' height and
    // not their width, so the padding above is unaffected by it.
    ..._amount(
      generator,
      ReceiptWords.totalLabel,
      sale,
      sale.totalMinor,
      styles: const PosStyles(bold: true, height: PosTextSize.size2),
    ),
    ..._rule(generator),
  ];

  List<int> _footer(Generator generator, CheckoutSalePayload sale) => <int>[
    ...generator.text(
      _pair(ReceiptWords.paidByLabel, ReceiptWords.tender(sale.tender)),
    ),
    ...generator.emptyLines(1),
    ...generator.text(_centred(ReceiptText.forPrinter(ReceiptWords.footer))),
  ];

  /// A label and a money amount, in one full line.
  List<int> _amount(
    Generator generator,
    String label,
    CheckoutSalePayload sale,
    int minor, {
    PosStyles styles = const PosStyles(),
  }) => generator.text(
    _pair(label, _money(sale.currency, minor)),
    styles: styles,
  );

  /// §8 rule 8: money always carries a currency code.
  ///
  /// The code is the **sale's own**, not the business's current one, so a
  /// receipt reprinted after a currency change still states what was charged.
  static String _money(String currency, int minor) =>
      '$currency ${(minor / 100).toStringAsFixed(2)}';
}
