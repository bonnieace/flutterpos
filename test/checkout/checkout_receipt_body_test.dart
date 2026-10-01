import 'dart:convert';

import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/tenancy/tenant_session.dart';
import 'package:uzapay_pos/tenancy/tenant_types.dart';
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

      // **The number as printed, since 2026-09-29**: the cashier's first name,
      // the till and the day's sequence. The stored `CT-8F8-20260729-0042` is
      // unchanged; the date it carried is the line under it.
      expect(text, contains('AMINA-CT-8F8-042'));
      expect(text, isNot(contains(_sale().receiptNumber)));
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

    test('prints each line\'s code after its name, wrapping with it', () {
      // 58mm: `2 x Maize flour 2kg 6161100000019` is past the 21-character
      // name column, so the code wraps - whole - onto the row the amount is
      // on, directly under the name it follows.
      final narrow = latin1
          .decode(
            body().build(_sale(sku: '6161100000019')),
            allowInvalid: true,
          )
          .split('\n');
      final name = narrow.indexWhere((row) => row.contains('Maize flour 2kg'));
      final code = narrow.indexWhere((row) => row.contains('6161100000019'));
      expect(code, name + 1);
      expect(narrow[code], contains('KES 271.00'));

      // 80mm: the whole line fits its 37-character column, amount and all.
      final wide = latin1
          .decode(
            body(
              width: PrinterPaperWidth.columns48,
            ).build(_sale(sku: '6161100000019')),
            allowInvalid: true,
          )
          .split('\n');
      final row = wide.singleWhere(
        (row) => row.contains('2 x Maize flour 2kg 6161100000019'),
      );
      expect(row, contains('KES 271.00'));

      // *Sugar 1kg* was sold with no code recorded, and prints none.
      expect(
        wide.singleWhere((row) => row.contains('Sugar 1kg')),
        contains('1 x Sugar 1kg '),
      );
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

    test('prints no payment line for a sale that names no method', () {
      // **No "Not recorded" since 2026-09-29**, at the product owner's
      // direction. A blank beside "Paid by" would read as a printer fault, so
      // the label goes with the value: the line is simply not there. A v2 sale
      // may legitimately carry no tender - the method is set afterwards from
      // the sale's own card - so this is a receipt a till really prints.
      expect(ReceiptWords.tender(null), isNull);

      final unpaid = latin1.decode(
        body().build(_sale(tender: null)),
        allowInvalid: true,
      );
      expect(unpaid, isNot(contains(ReceiptWords.paidByLabel)));
      expect(unpaid, isNot(contains('Not recorded')));
      // The rest of the footer is still there.
      expect(unpaid, contains(ReceiptWords.footer));

      final paid = latin1.decode(body().build(_sale()), allowInvalid: true);
      expect(paid, contains(ReceiptWords.paidByLabel));
    });

    test('names the customer and their KRA PIN, and a walk-in not at all', () {
      final named = latin1.decode(
        body().build(
          _sale(
            customer: const CheckoutSaleCustomer(
              id: 'cu_0123456789abcdef0123456789abcdef01234567',
              name: 'Jane Wanjiku',
              kraPin: 'A012345678Z',
            ),
          ),
        ),
        allowInvalid: true,
      );
      expect(named, contains(ReceiptWords.customerLabel));
      expect(named, contains('Jane Wanjiku'));
      expect(named, contains(ReceiptWords.kraPinLabel));
      expect(named, contains('A012345678Z'));

      // "Walk-in" is the absence of a fact, so nothing is printed for it.
      final walkIn = latin1.decode(body().build(_sale()), allowInvalid: true);
      expect(walkIn, isNot(contains(ReceiptWords.customerLabel)));
      expect(walkIn, isNot(contains(ReceiptWords.kraPinLabel)));
      expect(walkIn, isNot(contains('Walk-in')));
    });

    test('heads an unnamed business rather than printing its ID', () {
      // §8 rule 1: a document ID printed at a customer is that rule's own
      // worked example of what not to do.
      final text = latin1.decode(body().build(_sale()), allowInvalid: true);

      expect(text, contains(ReceiptWords.unnamedBusiness));
      expect(text, isNot(contains('tenant-a')));
    });
  });

  group('every line is the width of the roll', () {
    // **The contract this group exists to hold, and the one nothing checked.**
    // On 2026-08-18 a real 80mm printer sliced the last digit off every amount
    // and printed a product name on the same line as its own price. The suite
    // was green throughout, because it asserted on the decoded *text* and the
    // defect was in the *geometry*: `Generator.row` positions columns at
    // absolute dot offsets derived from `PaperSize.width`, which the package
    // reports as 558 for a roll it simultaneously treats as 48 characters -
    // and 48 characters of Font A is 576 dots.
    //
    // `CheckoutReceiptBody` now pads every line to the roll's character count
    // and positions nothing. These tests are the reason it cannot quietly stop.

    /// The visible characters of each printed line.
    ///
    /// Control sequences are skipped by their real lengths, read off
    /// `flutter_esc_pos_utils/src/commands.dart`: `ESC @` is two bytes,
    /// `ESC $ nL nH` is four, `FS &` and `FS .` are two, everything else this
    /// class emits is three. A parser that guesses reports an off-by-one that
    /// belongs to the parser.
    List<String> printedLines(List<int> bytes) {
      final lines = <String>[];
      final current = StringBuffer();
      var i = 0;
      while (i < bytes.length) {
        final byte = bytes[i];
        if (byte == 0x0A) {
          lines.add(current.toString());
          current.clear();
          i++;
        } else if (byte == 0x1B) {
          final command = i + 1 < bytes.length ? bytes[i + 1] : 0;
          i += switch (command) {
            0x40 => 2, // ESC @  initialise
            0x24 => 4, // ESC $  absolute position, nL nH
            0x32 => 2, // ESC 2  default line spacing
            _ => 3, //   ESC a/E/M/d/t/!/- plus one parameter
          };
        } else if (byte == 0x1D) {
          i += 3; // GS !/V/B plus one parameter
        } else if (byte == 0x1C) {
          i += 2; // FS &/.
        } else if (byte < 0x20) {
          i++;
        } else {
          current.writeCharCode(byte);
          i++;
        }
      }
      if (current.isNotEmpty) lines.add(current.toString());
      return lines;
    }

    for (final width in PrinterPaperWidth.values) {
      test('${width.columns} columns: no line is wider than the roll', () {
        final lines = printedLines(
          body(width: width).build(_sale(), servedBy: 'Wanjiku'),
        );
        expect(lines, isNotEmpty);
        for (final line in lines) {
          expect(
            line.length,
            lessThanOrEqualTo(width.columns),
            reason:
                'a line of ${line.length} characters on a ${width.columns} '
                'column roll overflows, and the overflow is what slices the '
                'last digit off an amount: |$line|',
          );
        }
      });

      test('${width.columns} columns: a rule fills the roll exactly', () {
        final lines = printedLines(
          body(width: width).build(_sale(), servedBy: 'Wanjiku'),
        );
        final rules = lines.where((line) => line.startsWith('---')).toList();
        // Heading, provenance, lines and totals each close with one.
        expect(rules, hasLength(4));
        for (final rule in rules) {
          expect(rule.length, width.columns);
        }
      });

      test('${width.columns} columns: money ends at the last column', () {
        final lines = printedLines(
          body(width: width).build(_sale(), servedBy: 'Wanjiku'),
        );
        // **The whole defect, as one assertion.** Every money line must reach
        // the right edge and stop there - not one character past it, which is
        // what the printer cannot draw, and not short of it either.
        final money = lines.where((line) => line.contains('KES ')).toList();
        expect(money, isNotEmpty);
        for (final line in money) {
          expect(line.length, width.columns, reason: '|$line|');
          expect(line.endsWith('0'), isTrue, reason: '|$line|');
        }
      });

      test('${width.columns} columns: a price sits beside its name', () {
        final lines = printedLines(
          body(width: width).build(_sale(), servedBy: 'Wanjiku'),
        );
        // **The opposite of what this asserted until 2026-08-26.** It required
        // that a name and its price never share a line, which is what made a
        // receipt show its totals as aligned pairs and the items that made them
        // up as a ragged column with prices floating underneath.
        final named = lines.where((line) => line.contains(' x ')).toList();
        expect(named, hasLength(2));
        for (final line in named) {
          expect(line, contains('KES '), reason: '|$line|');
          // Still the full width of the roll, money hard against the last
          // column - the same contract every other paired line has.
          expect(line.length, width.columns, reason: '|$line|');
          expect(line.endsWith('0'), isTrue, reason: '|$line|');
        }
      });

      test('${width.columns} columns: a long name wraps inside its column', () {
        // **Owner direction, 2026-08-26: the name wraps in the *name column*,
        // not across the whole roll, and the price lands on the row the wrap
        // ends on.** Laid across the full width, a wrapped line ran under where
        // the price column belongs and the receipt stopped reading as a table.
        final long = 'Sunflower cooking oil 5 litre refined and bottled';
        final lines = printedLines(
          body(
            width: width,
          ).build(_sale(name: long, onlyOneLine: true), servedBy: 'Wanjiku'),
        );

        final amount = lines.singleWhere(
          (line) => line.contains('KES') && !_isTotalRow(line),
        );
        final index = lines.indexOf(amount);
        // The amount shares the row the name finishes on - never a row of its
        // own. `_right` was deleted along with that case.
        expect(amount.length, width.columns, reason: '|$amount|');
        expect(amount.trimLeft(), isNot(startsWith('KES')), reason: amount);

        // The name column: the roll, less the amount, less one space. Every row
        // above the last must stay inside it, so nothing is drawn under the
        // price.
        final column = width.columns - 'KES 899.00'.length - 1;
        final wrapped = <String>[];
        for (var i = index; i >= 0; i--) {
          if (lines[i].startsWith('-')) break;
          wrapped.insert(0, lines[i]);
        }
        for (final row in wrapped.take(wrapped.length - 1)) {
          expect(
            row.length,
            lessThanOrEqualTo(column),
            reason: 'row runs into the price column: |$row|',
          );
        }

        // Nothing was dropped on the way: every word is still on the paper.
        final joined = wrapped.join(' ');
        for (final word in long.split(' ')) {
          expect(joined, contains(word), reason: word);
        }
      });

      test('${width.columns} columns: no line ever overruns the roll', () {
        // **Found on paper rather than in a test.** The old fallback emitted the
        // description raw, so a name one character past the roll overflowed and
        // the printer broke it wherever it ran out - mid-word, unpredictably.
        for (final name in <String>[
          'Sunflower cooking oil 5 litre refined and bottled',
          'A' * (width.columns * 2 + 5),
          'Maize flour 2kg',
        ]) {
          final lines = printedLines(
            body(width: width).build(_sale(name: name), servedBy: 'Wanjiku'),
          );
          for (final line in lines) {
            expect(
              line.length,
              lessThanOrEqualTo(width.columns),
              reason: '${line.length} chars for "$name": |$line|',
            );
          }
        }
      });

      test('${width.columns} columns: one word longer than the column', () {
        // No boundary to break on - a SKU pasted into a name - so it is chopped
        // at the column count rather than left to overflow. Nothing is lost:
        // every character is on the paper, on the next row.
        final long = 'A' * (width.columns * 2 + 5);
        final lines = printedLines(
          body(
            width: width,
          ).build(_sale(name: long, onlyOneLine: true), servedBy: 'Wanjiku'),
        );
        // Only the rows between the provenance rule and the totals rule, so a
        // stray capital in the heading or the receipt number cannot be counted.
        final rules = <int>[
          for (var i = 0; i < lines.length; i++)
            if (lines[i].startsWith('-')) i,
        ];
        final body_ = lines.sublist(rules[1] + 1, rules[2]);
        final letters = body_
            .map((line) => line.replaceAll(RegExp(r'[^A]'), ''))
            .join();
        expect(letters.length, long.length);
      });
    }
  });

  group('the roll and the cutter', () {
    test('cuts only where the printer has a cutter', () {
      // A cut command to a printer without one is ignored by some models and
      // prints a control character on others.
      expect(_indexOf(body().build(_sale()), _gsV), isNonNegative);
      expect(_indexOf(body(hasCutter: false).build(_sale()), _gsV), -1);
    });

    test('maps the two stored roll widths to the generator paper sizes', () {
      expect(paperSizeFor(PrinterPaperWidth.columns32), PaperSize.mm58);
      expect(paperSizeFor(PrinterPaperWidth.columns48), PaperSize.mm80);
    });

    test('both rolls produce the same lines, in different widths', () {
      // The shape does not change with the roll: a receipt with two layouts is
      // two things to reason about and nobody compares them side by side.
      final narrow = latin1.decode(body().build(_sale()), allowInvalid: true);
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
  String name = 'Maize flour 2kg',
  String? sku,
  bool onlyOneLine = false,
  CheckoutSaleCustomer? customer,
}) {
  const deviceId = 'dev-0123456789abcdef0123456789abcdef';
  final lines = <Object?>[
    <String, Object?>{
      'productId': 'product-a',
      'name': name,
      if (sku != null) 'sku': sku,
      'quantity': 2,
      'unitPriceMinor': 13550,
    },
    // Dropped where a test is about one sale line's own layout: a second line
    // puts a second money row on the paper, and `singleWhere` cannot then say
    // which row it meant.
    if (!onlyOneLine)
      <String, Object?>{
        'productId': 'product-b',
        'name': 'Sugar 1kg',
        'quantity': 1,
        'unitPriceMinor': 13500,
      },
  ];
  final subtotalMinor = 2 * 13550 + (onlyOneLine ? 0 : 13500);
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
    ...?customer?.toFields(),
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

/// Whether [line] is one of the totals rather than a sale line's amount.
///
/// The sale lines and the totals both end in money now, which is the point of
/// the change; a test that wants one of them has to say which.
bool _isTotalRow(String line) =>
    line.startsWith(ReceiptWords.subtotalLabel) ||
    line.startsWith(ReceiptWords.discountLabel) ||
    line.startsWith(ReceiptWords.totalLabel);
