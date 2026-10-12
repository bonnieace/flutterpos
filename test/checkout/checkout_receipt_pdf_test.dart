import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/reports/render/report_fonts.dart';
import 'package:uzapay_pos/tenancy/tenant_session.dart';
import 'package:uzapay_pos/tenancy/tenant_types.dart';

void main() {
  // The bundled faces are read through `rootBundle`.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what a receipt says', () {
    test('top to bottom, in the paper receipt’s order', () {
      final rows = checkoutReceiptRows(
        _sale(),
        businessName: 'Kahawa Duka',
        servedBy: 'Wanjiku',
      );

      expect(rows.map((row) => row.runtimeType).toList(), <Type>[
        ReceiptTitleRow,
        ReceiptGapRow,
        ReceiptRuleRow,
        ReceiptPairRow, // Receipt
        ReceiptPairRow, // Date
        ReceiptPairRow, // Served by
        ReceiptRuleRow,
        ReceiptItemRow,
        ReceiptItemRow,
        ReceiptRuleRow,
        ReceiptPairRow, // Subtotal
        ReceiptPairRow, // TOTAL
        ReceiptRuleRow,
        ReceiptPairRow, // Paid by
        ReceiptGapRow,
        ReceiptCentredRow, // footer
      ]);
      final total = rows.whereType<ReceiptPairRow>().singleWhere(
        (row) => row.label == ReceiptWords.totalLabel,
      );
      expect(total.value, 'KES 406.00');
      expect(total.emphasis, ReceiptEmphasis.total);
    });

    test('a discount, a customer and credit add their lines, and only '
        'then', () {
      final rows = checkoutReceiptRows(
        _sale(discountMinor: 1000, credit: true),
      );
      final labels = <String>[
        for (final row in rows.whereType<ReceiptPairRow>()) row.label,
      ];

      expect(labels, contains(ReceiptWords.discountLabel));
      expect(labels, contains(ReceiptWords.customerLabel));
      expect(labels, contains(ReceiptWords.kraPinLabel));
      expect(labels, contains('${ReceiptWords.paidNowLabel} (M-Pesa)'));
      expect(labels, contains(ReceiptWords.owedLabel));
      expect(labels, contains(ReceiptWords.balanceLabel));
      // A credit sale's tender is the credit lines, never "Paid by".
      expect(labels, isNot(contains(ReceiptWords.paidByLabel)));

      final plain = <String>[
        for (final row in checkoutReceiptRows(
          _sale(),
        ).whereType<ReceiptPairRow>())
          row.label,
      ];
      expect(plain, isNot(contains(ReceiptWords.discountLabel)));
      expect(plain, isNot(contains(ReceiptWords.customerLabel)));
    });

    test('a business with no name is headed by the receipt’s own words', () {
      final heading = checkoutReceiptHeadingRows(businessName: '   ');

      expect(
        heading.whereType<ReceiptTitleRow>().single.text,
        ReceiptWords.unnamedBusiness,
      );
    });

    test('keeps the shopkeeper’s own letters for the renderer to decide', () {
      final rows = checkoutReceiptRows(_sale(), businessName: 'Mũgumo Stores');

      expect(rows.whereType<ReceiptTitleRow>().single.text, 'Mũgumo Stores');
    });
  });

  group('the receipt as a page', () {
    late TenantReportFonts fonts;

    setUpAll(() async {
      fonts = await TenantReportFonts.load();
    });

    Future<PdfPageFormat> pageOf(
      PrinterPaperWidth width,
      List<CheckoutReceiptRow> rows,
    ) async {
      final document = CheckoutReceiptPdf(
        fonts: fonts,
        paperWidth: width,
      ).compose(rows);
      await document.save();
      return document.document.pdfPageList.pages.single.pageFormat;
    }

    test(
      'is a PDF, the roll’s own width, and no longer than it needs',
      () async {
        final bytes = await CheckoutReceiptPdf(
          fonts: fonts,
          paperWidth: PrinterPaperWidth.columns48,
        ).build(_sale(), businessName: 'Mũgumo Stores');
        expect(SystemPrintTransport.isPdf(bytes), isTrue);

        final narrow = await pageOf(
          PrinterPaperWidth.columns32,
          checkoutReceiptRows(_sale()),
        );
        final wide = await pageOf(
          PrinterPaperWidth.columns48,
          checkoutReceiptRows(_sale()),
        );
        // Pinned to the roll, even though no line fills it.
        expect(narrow.width, closeTo(57 * PdfPageFormat.mm, 0.01));
        expect(wide.width, closeTo(80 * PdfPageFormat.mm, 0.01));

        // As long as the receipt, so a longer one is a longer page.
        final longer = await pageOf(
          PrinterPaperWidth.columns48,
          checkoutReceiptRows(_sale(credit: true, discountMinor: 1000)),
        );
        expect(longer.height, greaterThan(wide.height));
        expect(wide.height, lessThan(200 * PdfPageFormat.mm));
      },
    );

    test('a logo no decoder knows draws nothing rather than failing', () async {
      final bytes = await CheckoutReceiptPdf(
        fonts: fonts,
        paperWidth: PrinterPaperWidth.columns32,
      ).build(_sale(), logo: Uint8List.fromList(<int>[1, 2, 3]));

      expect(SystemPrintTransport.isPdf(bytes), isTrue);
    });

    test(
      'lays out with the built-in faces when the bundled ones fail',
      () async {
        final bytes = await CheckoutReceiptPdf(
          fonts: TenantReportFonts.standard(),
          paperWidth: PrinterPaperWidth.columns48,
        ).build(_sale(credit: true), businessName: 'Mũgumo Stores');

        expect(SystemPrintTransport.isPdf(bytes), isTrue);
      },
    );

    test('the test page and the heading proof are pages too', () async {
      final pdf = CheckoutReceiptPdf(
        fonts: fonts,
        paperWidth: PrinterPaperWidth.columns48,
      );
      final at = DateTime(2026, 10, 10, 21, 30);

      expect(
        SystemPrintTransport.isPdf(
          await pdf.testPage(at: at, businessName: 'Kahawa Duka'),
        ),
        isTrue,
      );
      expect(
        SystemPrintTransport.isPdf(
          await pdf.brandingProof(at: at, companyName: 'Kahawa Duka'),
        ),
        isTrue,
      );
    });
  });
}

CheckoutSalePayload _sale({int discountMinor = 0, bool credit = false}) {
  const deviceId = 'dev-0123456789abcdef0123456789abcdef';
  const subtotal = 2 * 13550 + 13500;
  final payload = <String, Object?>{
    'schemaVersion': checkoutSalePayloadSchemaVersion,
    'checkoutId': 'checkout-a',
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'currency': 'KES',
    'businessDate': '2026-10-10',
    'createdAtMs': DateTime.utc(2026, 10, 10, 8).millisecondsSinceEpoch,
    'shiftId': 'shift-a',
    'deviceId': deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: deviceId,
      businessDate: '2026-10-10',
      sequence: 42,
    ),
    'receiptSequence': 42,
    'tender': 'cash',
    'items': <Object?>[
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
    ],
    'subtotalMinor': subtotal,
    'discountMinor': discountMinor,
    'totalMinor': subtotal - discountMinor,
    if (credit) ...<String, Object?>{
      ...const CheckoutSaleCustomer(
        id: 'cu_0123456789abcdef0123456789abcdef01234567',
        name: 'Njũgũna wa Kĩmani',
        kraPin: 'A012345678Z',
      ).toFields(),
      ...const CheckoutSaleCredit(
        owedMinor: 20000,
        paidTender: CheckoutTender.mpesa,
        balanceAfterMinor: 45000,
      ).toFields(),
    },
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
