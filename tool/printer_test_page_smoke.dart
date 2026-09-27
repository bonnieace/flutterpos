/// A disposable diagnostic: print the **test page** on a real printer.
///
/// The fourth of the family. `printer_smoke.dart` probes and prints nothing;
/// `printer_receipt_smoke.dart` puts a fabricated sale on paper;
/// `printer_till_smoke.dart` rings one up through the till's own UI. This one
/// sends what *Test this printer* sends — `CheckoutPrinterTestPage`, the same
/// class the settings screen calls — so what comes out of the printer is what a
/// shopkeeper pressing that button would get.
///
///   PRINTER_HOST=192.168.100.20 flutter test tool/printer_test_page_smoke.dart
///
/// It runs under `flutter test` rather than `dart run` for the reason
/// `printer_receipt_smoke.dart` gives: `CapabilityProfile.load` reads a package
/// asset through `rootBundle`, which needs a binding.
///
/// **Both rolls by default, one after the other**, because the width is half of
/// what this page exists to prove: the ruler on each is exactly one row of the
/// roll it claims, and the two pages side by side show what a wrong setting
/// looks like. `PRINTER_COLUMNS` narrows it to one.
///
/// It is opt-in: with no `PRINTER_HOST` in the environment it skips rather than
/// prints, which is why it is safe to leave in the tree.
///
/// Environment:
///   PRINTER_HOST     required; no default, ever — see checkout_print_configuration.dart
///   PRINTER_PORT     default 9100
///   PRINTER_COLUMNS  32 (58mm) or 48 (80mm); default is both, in that order
///   PRINTER_CUTTER   true|false; default false, which feeds instead of cutting
///   PRINTER_BUSINESS default 'Mũgumo Stores', whose macron is the point
library;

import 'dart:io';

import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final host = Platform.environment['PRINTER_HOST'];
  final port =
      int.tryParse(Platform.environment['PRINTER_PORT'] ?? '') ??
      PrinterEndpoint.rawEscPosPort;
  final hasCutter = Platform.environment['PRINTER_CUTTER'] == 'true';
  final businessName =
      Platform.environment['PRINTER_BUSINESS'] ?? 'Mũgumo Stores';
  final widths = switch (Platform.environment['PRINTER_COLUMNS']) {
    '32' => const <PrinterPaperWidth>[PrinterPaperWidth.columns32],
    '48' => const <PrinterPaperWidth>[PrinterPaperWidth.columns48],
    _ => PrinterPaperWidth.values,
  };

  test('prints the test page on a real printer', () async {
    if (host == null || host.isEmpty) {
      // Skipping rather than failing: this file is a diagnostic, and a suite
      // run on a machine with no printer on the bench must stay green.
      stdout.writeln('PRINTER_HOST unset. Nothing was dialled or printed.');
      return;
    }

    final PrinterEndpoint endpoint;
    try {
      endpoint = PrinterEndpoint(host: host, port: port);
    } on ArgumentError catch (error) {
      fail('REFUSED before dialling: ${error.message}');
    }

    final profile = await CapabilityProfile.load();
    final transport = createPrinterTransport();
    stdout.writeln('transport : ${transport.capability.label}');
    stdout.writeln('endpoint  : $endpoint');
    stdout.writeln('cutter    : $hasCutter');
    stdout.writeln('business  : $businessName');
    stdout.writeln('');

    try {
      for (final width in widths) {
        final configuration = TenantPrinterConfiguration(
          transport: transport.capability.kind,
          endpoint: endpoint,
          paperWidth: width,
          hasCutter: hasCutter,
        );
        final bytes = CheckoutPrinterTestPage(
          profile: profile,
          configuration: configuration,
        ).build(at: DateTime.now(), businessName: businessName);
        stdout.writeln(
          'sending   : ${width.label} — ${bytes.length} bytes',
        );
        final started = DateTime.now();
        await transport.send(endpoint, bytes);
        stdout.writeln(
          'SENT      : ${width.label} in '
          '${DateTime.now().difference(started).inMilliseconds} ms',
        );
      }
      stdout.writeln('');
      stdout.writeln(
        'Look at the paper: each page\'s ruler must fill one line and end in '
        'that page\'s own column count.',
      );
    } on PrinterTransportException catch (error) {
      fail('FAILED: ${error.code}');
    } finally {
      await transport.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
