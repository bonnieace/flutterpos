/// What a receipt says, decided once, for every surface that draws one.
///
/// **One list of rows, two renderers.** [CheckoutReceiptBody] turns it into
/// ESC/POS for a thermal printer this app drives itself; `CheckoutReceiptPdf`
/// turns it into a page for a device's own print window. Until 2026-10-10 the
/// decisions - a discount line only where there was a discount, no *Paid by*
/// on a sale that recorded no tender, the three credit lines - lived inside
/// the ESC/POS builder, and a second renderer would have had to copy them and
/// then drift from them. Here they are made once, and the ESC/POS bytes they
/// produce were proven byte-identical to the builder's before the move.
///
/// **Words only, never geometry.** Columns, padding, wrapping and type sizes
/// belong to each renderer, because a 32-column roll and a PDF page answer
/// them differently. The text is the shopkeeper's own, unsubstituted: a
/// renderer that cannot draw a character decides what to draw instead - see
/// `ReceiptText.forPrinter`.
library;

import 'dart:typed_data';

import 'checkout_receipt.dart' show printedCheckoutReceiptNumber;
import 'checkout_receipt_body.dart' show ReceiptWords;
import 'checkout_sale.dart';

/// One line, or one block, of a receipt.
sealed class CheckoutReceiptRow {
  const CheckoutReceiptRow();
}

/// The business's mark, above its name.
///
/// **A renderer that cannot decode it draws nothing, and nothing under it**,
/// which is what the ESC/POS receipt has always done with a broken logo.
final class ReceiptLogoRow extends CheckoutReceiptRow {
  const ReceiptLogoRow(this.bytes);

  final Uint8List bytes;
}

/// The business's name, as the heading.
final class ReceiptTitleRow extends CheckoutReceiptRow {
  const ReceiptTitleRow(this.text);

  final String text;
}

/// A centred line at ordinary size: the slogan, the footer.
final class ReceiptCentredRow extends CheckoutReceiptRow {
  const ReceiptCentredRow(this.text);

  final String text;
}

/// One empty line.
final class ReceiptGapRow extends CheckoutReceiptRow {
  const ReceiptGapRow();
}

/// A rule across the paper.
final class ReceiptRuleRow extends CheckoutReceiptRow {
  const ReceiptRuleRow();
}

/// How much a [ReceiptPairRow] stands out.
enum ReceiptEmphasis {
  plain,

  /// Bold: the receipt number, what a credit sale left owing.
  strong,

  /// Bold and tall: the total, which is what a customer looks for first.
  total,
}

/// A label and its value on one line: the receipt number, a date, money.
final class ReceiptPairRow extends CheckoutReceiptRow {
  const ReceiptPairRow(
    this.label,
    this.value, {
    this.emphasis = ReceiptEmphasis.plain,
  });

  final String label;
  final String value;
  final ReceiptEmphasis emphasis;
}

/// One sale line: what was sold, and what it came to.
///
/// **The description is never truncated and the amount is never alone.** A
/// renderer wraps a long description inside its own column and puts the
/// amount on the row the wrap ends on - see `CheckoutReceiptBody._item` for
/// why that layout won.
final class ReceiptItemRow extends CheckoutReceiptRow {
  const ReceiptItemRow(this.description, this.amount);

  final String description;
  final String amount;
}

/// Every row of [sale]'s receipt, top to bottom.
///
/// [businessName] is the shop's own name, resolved by the caller from branding
/// exactly as the home's title is; this reads no documents.
List<CheckoutReceiptRow> checkoutReceiptRows(
  CheckoutReceiptSale sale, {
  String? businessName,
  String? servedBy,
  Uint8List? logo,
  String? slogan,
}) => <CheckoutReceiptRow>[
  ...checkoutReceiptHeadingRows(
    businessName: businessName,
    logo: logo,
    slogan: slogan,
  ),
  ..._provenance(sale, servedBy),
  ..._lines(sale),
  ..._totals(sale),
  ..._footer(sale),
];

/// The mark, the name, the slogan, and the rule that closes them off.
///
/// **Its own function because the branding proof and the test page print it
/// too**, and a heading that differed between them and a real receipt would
/// make both of them proofs of nothing.
///
/// **The gap and the rule are the whole of the spacing, and deliberate.** One
/// empty line under the block is what a heading needs to read as a heading
/// rather than as the top of a list.
List<CheckoutReceiptRow> checkoutReceiptHeadingRows({
  String? businessName,
  Uint8List? logo,
  String? slogan,
}) {
  final line = slogan?.trim();
  return <CheckoutReceiptRow>[
    // **The mark above the name, when the business has published one.** It is
    // the first thing on the paper for the same reason it is the first thing
    // on the business details screen: it is what a customer recognises
    // without reading.
    if (logo != null) ReceiptLogoRow(logo),
    ReceiptTitleRow(
      businessName?.trim().isNotEmpty ?? false
          ? businessName!.trim()
          : ReceiptWords.unnamedBusiness,
    ),
    // **The slogan, which the business details screen promises** - *one line
    // under the name on a receipt*.
    if (line != null && line.isNotEmpty) ReceiptCentredRow(line),
    const ReceiptGapRow(),
    const ReceiptRuleRow(),
  ];
}

List<CheckoutReceiptRow> _provenance(
  CheckoutReceiptSale sale,
  String? servedBy,
) => <CheckoutReceiptRow>[
  // The receipt number is the thing a person quotes on the phone, so it is
  // first and it is emphasised. **Printed in its readable form since
  // 2026-09-29** - `JOHN-CT-7F2-001` - derived from the stored number and
  // nothing else but the name below, so the paper still names exactly one sale
  // once the date line is read with it.
  ReceiptPairRow(
    ReceiptWords.receiptLabel,
    printedCheckoutReceiptNumber(sale.receiptNumber, servedBy: servedBy),
    emphasis: ReceiptEmphasis.strong,
  ),
  // **Required, not decoration.** The printed number carries no date and
  // restarts every day, so this line is what makes it one sale.
  ReceiptPairRow(ReceiptWords.dateLabel, sale.businessDate),
  if (servedBy != null && servedBy.trim().isNotEmpty)
    ReceiptPairRow(ReceiptWords.servedByLabel, servedBy.trim()),
  // **Who it was for, only when the till named somebody.** A walk-in prints
  // nothing here rather than the word, because a receipt is a record of what is
  // true and "walk-in" is the absence of a fact, not one.
  if (sale.customer case final customer?) ...<CheckoutReceiptRow>[
    ReceiptPairRow(ReceiptWords.customerLabel, customer.name),
    // A business buyer's PIN is why many of them ask for a receipt at all.
    if (customer.kraPin case final pin?)
      ReceiptPairRow(ReceiptWords.kraPinLabel, pin),
  ],
  const ReceiptRuleRow(),
];

List<CheckoutReceiptRow> _lines(CheckoutReceiptSale sale) =>
    <CheckoutReceiptRow>[
      for (final line in sale.lines)
        ReceiptItemRow(
          // **The code follows the name on the same line, and wraps with it**
          // - the owner's choice on 2026-09-29 over a row of its own. A line
          // sold before the code was recorded shows none.
          switch (line.sku) {
            final sku? => '${line.quantity} x ${line.name} $sku',
            null => '${line.quantity} x ${line.name}',
          },
          receiptMoney(sale.currency, line.lineTotalMinor),
        ),
      const ReceiptRuleRow(),
    ];

List<CheckoutReceiptRow> _totals(CheckoutReceiptSale sale) =>
    <CheckoutReceiptRow>[
      ReceiptPairRow(
        ReceiptWords.subtotalLabel,
        receiptMoney(sale.currency, sale.subtotalMinor),
      ),
      // **A discount line only where there was a discount.** A permanent
      // `Discount  KES 0.00` teaches a customer to ignore the line, which is
      // the one place it matters.
      if (sale.discountMinor != 0)
        ReceiptPairRow(
          ReceiptWords.discountLabel,
          receiptMoney(sale.currency, sale.discountMinor),
        ),
      ReceiptPairRow(
        ReceiptWords.totalLabel,
        receiptMoney(sale.currency, sale.totalMinor),
        emphasis: ReceiptEmphasis.total,
      ),
      const ReceiptRuleRow(),
    ];

List<CheckoutReceiptRow> _footer(CheckoutReceiptSale sale) =>
    <CheckoutReceiptRow>[
      if (sale.credit case final credit?) ...<CheckoutReceiptRow>[
        if (credit.paidMinor(sale.totalMinor) > 0)
          ReceiptPairRow(
            switch (ReceiptWords.tender(credit.paidTender)) {
              final paid? => '${ReceiptWords.paidNowLabel} ($paid)',
              null => ReceiptWords.paidNowLabel,
            },
            receiptMoney(sale.currency, credit.paidMinor(sale.totalMinor)),
          ),
        ReceiptPairRow(
          ReceiptWords.owedLabel,
          receiptMoney(sale.currency, credit.owedMinor),
          emphasis: ReceiptEmphasis.strong,
        ),
        if (credit.balanceAfterMinor case final balance?)
          ReceiptPairRow(
            ReceiptWords.balanceLabel,
            receiptMoney(sale.currency, balance),
          ),
      ] else if (ReceiptWords.tender(sale.tender) case final paid?)
        ReceiptPairRow(ReceiptWords.paidByLabel, paid),
      const ReceiptGapRow(),
      const ReceiptCentredRow(ReceiptWords.footer),
    ];

/// §8 rule 8: money always carries a currency code.
///
/// The code is the **sale's own**, not the business's current one, so a
/// receipt reprinted after a currency change still states what was charged.
String receiptMoney(String currency, int minor) =>
    '$currency ${(minor / 100).toStringAsFixed(2)}';
