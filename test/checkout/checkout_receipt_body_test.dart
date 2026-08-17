import 'dart:convert';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenant_session.dart';
import 'package:flutter_application_1/tenancy/tenant_types.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// `ESC t` — the code-page selector, and the one command this file exists to
/// prove is present.
const List<int> _escT = <int>[0x1B, 0x74];

/// `GS V` — the cutter.
const List<int> _gsV = <int>[0x1D, 0x56];

void main() {
  // `CapabilityProfile.load` reads a package asset through `rootBundle`.
  TestWidgetsFlutterBinding.ensureInitialized();

  late CapabilityProfile profile;

  setUpAll(() async {
    profile = await CapabilityProfile.load();
  });

  CheckoutReceiptBody body({
    PrinterPaperWidth width = PrinterPaperWidth.columns32,
    bool hasCutter = true,
  }) => CheckoutReceiptBody(
    profile: profile,
    configuration: TenantPrinterConfiguration(
      transport: PrinterTransportKind.directTcp,
      endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
      paperWidth: width,
      hasCutter: hasCutter,
    ),
  );

  group('the code page', () {
    test('emits ESC t before a single character is printed', () {
      // `docs/printer_transport.md`'s scope line: the borrowed repo's builder
      // "Latin-1 encodes bytes 0x80-0xFF and never emits `ESC t`, so every
      // non-ASCII character prints as the printer's default code page
      // instead". This is the assertion that says this one does not.
      final bytes = body().build(_sale());

      final escT = _indexOf(bytes, _escT);
      expect(escT, isNonNegative, reason: 'ESC t was never emitted');

      // And it is emitted before anything printable. A code page set after the
      // shop name is a code page that did not apply to the shop name.
      final firstLetter = bytes.indexOf('S'.codeUnitAt(0));
      expect(escT, lessThan(firstLetter));
    });

    test('a non-ASCII business name does not crash the receipt', () {
      // **This is the finding this file was written for and it is worse than
      // the one it was aiming at.** `Generator` encodes with `latin1`, and
      // `latin1.encode` *throws* on U+0169 - so a shop called `Mũgumo Stores`
      // did not print badly, it failed the receipt outright. Mojibake is a
      // cosmetic defect; an exception on the sale path is not.
      final bytes = body().build(_sale(), businessName: 'Mũgumo Stores');

      expect(bytes, isNotEmpty);
      expect(_indexOf(bytes, _escT), isNonNegative);
      // Legible, lossy, and traceable: the mark is dropped, the letter is not.
      expect(_indexOf(bytes, latin1.encode('Mugumo Stores')), isNonNegative);
    });

    test('substitutes what the printer cannot draw, and never drops it', () {
      // A name shortened without trace is a name a customer cannot match to
      // the shop, so anything unmappable becomes a visible mark.
      expect(ReceiptText.forPrinter('Mũgumo'), 'Mugumo');
      expect(ReceiptText.forPrinter('Gĩkũyũ'), 'Gikuyu');
      // A curly apostrophe is what a word processor inserts, and it is not in
      // Latin-1 either.
      expect(ReceiptText.forPrinter('Wanjiku’s'), "Wanjiku's");
      // Everything else keeps its position rather than vanishing.
      expect(ReceiptText.forPrinter('shop 中'), 'shop ?');
      expect(ReceiptText.forPrinter('Café'), 'Café');
    });
  });

  group('what is on the paper', () {
    test('states the receipt number, the date and every line', () {
      final bytes = body().build(_sale(), servedBy: 'Amina');
      final text = latin1.decode(bytes, allowInvalid: true);

      expect(text, contains(_sale().receiptNumber));
      expect(text, contains('2026-07-29'));
      expect(text, contains('Maize flour 2kg'));
      expect(text, contains('Sugar 1kg'));
      expect(text, contains('Amina'));
    });

    test('never states a figure without its currency code, per §8 rule 8', () {
      final text = latin1.decode(body().build(_sale()), allowInvalid: true);

      // Every amount on the paper: two line totals, the subtotal and the total.
      for (final amount in const <String>[
        'KES 271.00',
        'KES 135.00',
        'KES 406.00',
      ]) {
        expect(text, contains(amount), reason: amount);
      }
    });

    test('prints the code the sale was priced with, not a current one', () {
      // A receipt reprinted after the business changed currency still says what
      // was actually charged.
      final text = latin1.decode(
        body().build(_sale(currency: 'UGX')),
        allowInvalid: true,
      );

      expect(text, contains('UGX 406.00'));
      expect(text, isNot(contains('KES')));
    });

    test('omits the discount line when there was no discount', () {
      // A permanent `Discount KES 0.00` teaches a customer to ignore the line,
      // which is the one place it matters.
      final without = latin1.decode(body().build(_sale()), allowInvalid: true);
      final with_ = latin1.decode(
        body().build(_sale(discountMinor: 2000)),
        allowInvalid: true,
      );

      expect(without, isNot(contains(ReceiptWords.discountLabel)));
      expect(with_, contains(ReceiptWords.discountLabel));
    });

    test('names the tender in the app own vocabulary', () {
      // `CheckoutTender.label` rather than a second table: renaming M-Pesa on
      // screen renames it on paper.
      final text = latin1.decode(
        body().build(_sale(tender: 'mpesa')),
        allowInvalid: true,
      );

      expect(text, contains(CheckoutTender.mpesa.label));
    });

    test('says a tender was not recorded rather than leaving a blank', () {
      // **Asserted on the mapping rather than through a payload, because a
      // payload cannot reach it**: `CheckoutSalePayload` refuses a sale with no
      // tender outright - `tender must name one of the recorded payment
      // methods`. So this branch is defensive, and it stays because the
      // formatter takes a nullable tender from an enum that models one. A
      // blank beside "Paid by" reads as a printer fault rather than as missing
      // data.
      expect(ReceiptWords.tender(null), 'Not recorded');

      final text = latin1.decode(body().build(_sale()), allowInvalid: true);
      expect(text, contains(ReceiptWords.paidByLabel));
    });

    test('heads an unnamed business rather than printing its ID', () {
      // §8 rule 1: a document ID printed at a customer is that rule's own
      // worked example of what not to do.
      final text = latin1.decode(body().build(_sale()), allowInvalid: true);

      expect(text, contains(ReceiptWords.unnamedBusiness));
      expect(text, isNot(contains('tenant-a')));
    });
  });

  group('the roll and the cutter', () {
    test('cuts only where the printer has a cutter', () {
      // A cut command to a printer without one is ignored by some models and
      // prints a control character on others.
      expect(_indexOf(body().build(_sale()), _gsV), isNonNegative);
      expect(
        _indexOf(body(hasCutter: false).build(_sale()), _gsV),
        -1,
      );
    });

    test('maps the two stored roll widths to the generator paper sizes', () {
      expect(paperSizeFor(PrinterPaperWidth.columns32), PaperSize.mm58);
      expect(paperSizeFor(PrinterPaperWidth.columns48), PaperSize.mm80);
    });

    test('both rolls produce the same lines, in different widths', () {
      // The shape does not change with the roll: a receipt with two layouts is
      // two things to reason about and nobody compares them side by side.
      final narrow = latin1.decode(
        body().build(_sale()),
        allowInvalid: true,
      );
      final wide = latin1.decode(
        body(width: PrinterPaperWidth.columns48).build(_sale()),
        allowInvalid: true,
      );

      for (final line in const <String>[
        'Maize flour 2kg',
        'KES 406.00',
        ReceiptWords.totalLabel,
      ]) {
        expect(narrow, contains(line), reason: '32: $line');
        expect(wide, contains(line), reason: '48: $line');
      }
    });
  });

  group('the words', () {
    test('are all in one class, so the copy can be replaced in one place', () {
      // The product owner has not specified the receipt's copy; this is the
      // assertion that keeps it findable when they do.
      expect(ReceiptWords.receiptLabel, isNotEmpty);
      expect(ReceiptWords.footer, isNotEmpty);
      // **Every fixed line fits the narrowest roll**, which is the one
      // invariant copy can break in silence. A line longer than 32 columns
      // does not fail, it wraps - and the footer at 34 characters left a
      // centred sentence with the word `em` under it, which reads as a broken
      // printer. There is no screenshot of paper and never will be, so this
      // arithmetic is the whole of the review.
      expect(ReceiptWords.longestLineFits, isTrue);
      for (final word in ReceiptWords.all) {
        expect(
          word.length,
          lessThanOrEqualTo(PrinterPaperWidth.columns32.columns),
          reason: '${word.length} chars: "$word"',
        );
      }

      // And nothing claims paper moved - the transport cannot know that.
      for (final word in const <String>[
        ReceiptWords.receiptLabel,
        ReceiptWords.dateLabel,
        ReceiptWords.servedByLabel,
        ReceiptWords.subtotalLabel,
        ReceiptWords.discountLabel,
        ReceiptWords.totalLabel,
        ReceiptWords.paidByLabel,
        ReceiptWords.footer,
        ReceiptWords.unnamedBusiness,
      ]) {
        expect(word.trim(), word, reason: 'padded: "$word"');
      }
    });
  });
}

/// The first index of [needle] in [haystack], or -1.
int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}

CheckoutSalePayload _sale({
  String currency = 'KES',
  int discountMinor = 0,
  Object? tender = 'cash',
}) {
  const deviceId = 'dev-0123456789abcdef0123456789abcdef';
  final lines = <Object?>[
    <String, Object?>{
      'productId': 'product-a',
      'name': 'Maize flour 2kg',
      'quantity': 2,
      'unitPriceMinor': 13550,
    },
    <String, Object?>{
      'productId': 'product-b',
      'name': 'Sugar 1kg',
      'quantity': 1,
      'unitPriceMinor': 13500,
    },
  ];
  const subtotalMinor = 2 * 13550 + 13500;
  final payload = <String, Object?>{
    'schemaVersion': checkoutSalePayloadSchemaVersion,
    'checkoutId': 'checkout-a',
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'currency': currency,
    'businessDate': '2026-07-29',
    'createdAtMs': DateTime.utc(2026, 7, 29, 8).millisecondsSinceEpoch,
    'shiftId': 'shift-a',
    'deviceId': deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: deviceId,
      businessDate: '2026-07-29',
      sequence: 42,
    ),
    'receiptSequence': 42,
    if (tender != null) 'tender': tender,
    'items': lines,
    'subtotalMinor': subtotalMinor,
    'discountMinor': discountMinor,
    'totalMinor': subtotalMinor - discountMinor,
  };
  return CheckoutSalePayload.fromLocalPayload(
    session: TenantSession.active(
      uid: 'user-a',
      tenantId: 'tenant-a',
      role: TenantRole.cashier,
    ),
    checkoutId: 'checkout-a',
    payload: payload,
    payloadHash: checkoutPayloadHash(payload),
  );
}
