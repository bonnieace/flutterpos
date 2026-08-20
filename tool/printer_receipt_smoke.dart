/// A disposable diagnostic: print **one real receipt** on a real printer.
///
/// Sibling to `printer_smoke.dart`, which only probes. This one puts ink on
/// paper, so it is opt-in: with no `PRINTER_HOST` in the environment it skips
/// rather than prints, which is why it is safe to leave in the tree.
///
///   PRINTER_HOST=192.168.100.20 flutter test tool/printer_receipt_smoke.dart
///
/// It runs under `flutter test` rather than `dart run` for exactly one reason:
/// `CapabilityProfile.load` reads a package asset through `rootBundle`, which
/// needs a binding. Everything else here is the production path —
/// `createPrinterTransport()` is the same platform seam the app will use, and
/// `CheckoutReceiptBody` is the same formatter, so what comes out of the
/// printer is what a sale would have produced.
///
/// It does **not** touch the sale path, the outbox, or the job queue. It
/// fabricates a payload, formats it, and sends the bytes.
///
/// Environment:
///   PRINTER_HOST     required; no default, ever — see checkout_print_configuration.dart
///   PRINTER_PORT     default 9100
///   PRINTER_COLUMNS  32 (58mm) or 48 (80mm); default 32
///   PRINTER_CUTTER   true|false; default false, which feeds instead of cutting
///   PRINTER_BUSINESS default 'Mũgumo Stores', whose macron is the point
library;

import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenant_session.dart';
import 'package:flutter_application_1/tenancy/tenant_types.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final host = Platform.environment['PRINTER_HOST'];
  final port =
      int.tryParse(Platform.environment['PRINTER_PORT'] ?? '') ??
      PrinterEndpoint.rawEscPosPort;
  final columns = Platform.environment['PRINTER_COLUMNS'] == '48'
      ? PrinterPaperWidth.columns48
      : PrinterPaperWidth.columns32;
  final hasCutter = Platform.environment['PRINTER_CUTTER'] == 'true';
  final businessName =
      Platform.environment['PRINTER_BUSINESS'] ?? 'Mũgumo Stores';

  test('sends one real receipt to a real printer', () async {
    if (host == null || host.isEmpty) {
      stdout.writeln('PRINTER_HOST unset — skipping, nothing was printed.');
      return;
    }

    final configuration = TenantPrinterConfiguration(
      transport: PrinterTransportKind.directTcp,
      endpoint: PrinterEndpoint(host: host, port: port),
      paperWidth: columns,
      hasCutter: hasCutter,
    );
    final body = CheckoutReceiptBody(
      profile: await CapabilityProfile.load(),
      configuration: configuration,
    );
    final bytes = body.build(
      _sale(),
      businessName: businessName,
      servedBy: 'Wanjiku',
    );

    stdout.writeln('endpoint  : ${configuration.endpoint}');
    stdout.writeln('paper     : ${columns.columns} columns');
    stdout.writeln('cutter    : $hasCutter');
    stdout.writeln('business  : $businessName');
    stdout.writeln('payload   : ${bytes.length} bytes');

    // The production seam, not a directly-constructed IoPrinterTransport.
    final transport = createPrinterTransport();
    final started = DateTime.now();
    try {
      await transport.send(configuration.endpoint, bytes);
      final ms = DateTime.now().difference(started).inMilliseconds;
      // "sent", never "printed" — checkout_print_transport_base.dart's rule.
      stdout.writeln('SENT in ${ms}ms — delivered to the printer.');
    } on PrinterTransportException catch (error) {
      stdout.writeln('FAILED: ${error.code}');
      rethrow;
    } finally {
      await transport.dispose();
    }
  });
}

/// The same fixture `checkout_receipt_body_test.dart` formats against, so what
/// prints here is comparable to what that suite asserts on.
CheckoutSalePayload _sale() {
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
  const discountMinor = 2000;
  final payload = <String, Object?>{
    'schemaVersion': checkoutSalePayloadSchemaVersion,
    'checkoutId': 'checkout-smoke',
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'currency': 'KES',
    'businessDate': '2026-08-18',
    'createdAtMs': DateTime.utc(2026, 8, 18, 8).millisecondsSinceEpoch,
    'shiftId': 'shift-a',
    'deviceId': deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: deviceId,
      businessDate: '2026-08-18',
      sequence: 42,
    ),
    'receiptSequence': 42,
    'tender': 'cash',
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
    checkoutId: 'checkout-smoke',
    payload: payload,
    payloadHash: checkoutPayloadHash(payload),
  );
}
