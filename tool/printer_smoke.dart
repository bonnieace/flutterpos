/// A disposable diagnostic: dial a printer with the real transport.
///
/// The probe-only member of the family. `printer_receipt_smoke.dart` formats a
/// fabricated sale and sends it; `printer_till_smoke.dart` rings one up through
/// the till's own UI. This one connects and closes without writing a byte, so
/// nothing here can waste a roll.
///
///   PRINTER_HOST=192.168.100.20 dart run tool/printer_smoke.dart
///   dart run tool/printer_smoke.dart 192.168.100.20 9100
///
/// It runs under `dart run` rather than `flutter test`, unlike its two
/// siblings, because it needs no `rootBundle`: `checkout_print_transport_io.dart`
/// depends on nothing but `dart:io` and the transport contract.
///
/// Environment, matching the siblings:
///   PRINTER_HOST  required unless given as the first argument
///   PRINTER_PORT  default 9100, or the second argument
library;

import 'dart:io';

import 'package:flutter_application_1/checkout/checkout_print_transport.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty
      ? args.first
      : Platform.environment['PRINTER_HOST'];
  if (host == null || host.isEmpty) {
    stdout.writeln(
      'PRINTER_HOST unset and no address given. Nothing was dialled.\n'
      'Usage: dart run tool/printer_smoke.dart <host> [port]',
    );
    exitCode = 2;
    return;
  }
  final port =
      int.tryParse(
        args.length > 1 ? args[1] : Platform.environment['PRINTER_PORT'] ?? '',
      ) ??
      PrinterEndpoint.rawEscPosPort;

  final PrinterEndpoint endpoint;
  try {
    endpoint = PrinterEndpoint(host: host, port: port);
  } on ArgumentError catch (error) {
    // The refusal a person reads is the refusal the socket would have given:
    // this is the same validation the durable job record uses.
    stdout.writeln('REFUSED before dialling: ${error.message}');
    exitCode = 2;
    return;
  }

  final transport = createPrinterTransport();
  stdout.writeln('transport : ${transport.capability.label}');
  stdout.writeln('kind      : ${transport.capability.kind.name}');
  stdout.writeln('endpoint  : $endpoint');
  stdout.writeln('');

  final started = DateTime.now();
  try {
    await transport.probe(endpoint);
    final ms = DateTime.now().difference(started).inMilliseconds;
    // **Reachable, not "this is a printer".** `probe` proves a TCP listener
    // accepted a connection and nothing more — on a development machine port
    // 9100 is Dart DevTools' default, and it answers this happily.
    stdout.writeln('REACHABLE in ${ms}ms — connected and closed, no bytes sent.');
  } on PrinterTransportException catch (error) {
    final ms = DateTime.now().difference(started).inMilliseconds;
    stdout.writeln('FAILED in ${ms}ms');
    stdout.writeln('  code    : ${error.code}');
    exitCode = 1;
  } finally {
    await transport.dispose();
  }
}
