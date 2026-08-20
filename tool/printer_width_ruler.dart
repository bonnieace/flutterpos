/// A disposable diagnostic: print a ruler and read the printer's real width.
///
/// **ESC/POS cannot be asked how wide it is.** `GS I n` returns a
/// vendor-specific model byte, `DLE EOT n` reports paper and cover state, and
/// nothing in the common command set reports dots per line. So the width is a
/// setting, and this is how the setting is *checked* instead of guessed:
/// paper is the measuring instrument.
///
///   dart run tool/printer_width_ruler.dart 192.168.100.20 9100
///
/// It prints a digit ruler and three marker lines of exactly 32, 42 and 48
/// characters, each ending in its own number. **Whichever numbers are printed
/// whole is how many columns this printer really has** - a marker that is
/// clipped, or whose digits are sliced in half, is wider than the paper.
///
/// 42 is on the list deliberately: an 80mm roll is 576 dots on some mechanisms
/// and 512 on others, which is 48 columns and 42 columns of Font A. A receipt
/// laid out for 48 on a 512-dot printer loses its last six columns, and the
/// first thing anyone notices is the right-hand digits of the money.
///
/// Raw bytes rather than `Generator`, so it needs no `CapabilityProfile` and
/// therefore no Flutter binding.
library;

import 'dart:io';

import 'package:flutter_application_1/checkout/checkout_print_transport.dart';

/// `ESC @` - reset. `ESC M 0` - Font A, the font every column count above is
/// quoted in; a printer left in Font B would measure narrower glyphs and give
/// a reading that does not describe a receipt.
const List<int> _reset = <int>[0x1B, 0x40, 0x1B, 0x4D, 0x00];

List<int> _line(String text) => <int>[...text.codeUnits, 0x0A];

/// A marker exactly [columns] wide, ending in its own number.
List<int> _marker(int columns) {
  final label = '$columns';
  return _line('-' * (columns - label.length) + label);
}

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty
      ? args.first
      : Platform.environment['PRINTER_HOST'];
  if (host == null || host.isEmpty) {
    stdout.writeln('Usage: dart run tool/printer_width_ruler.dart <host> [port]');
    exitCode = 2;
    return;
  }
  final port =
      int.tryParse(
        args.length > 1 ? args[1] : Platform.environment['PRINTER_PORT'] ?? '',
      ) ??
      PrinterEndpoint.rawEscPosPort;

  // The tens ruler: a digit at every tenth column, dots between, so the exact
  // column where the paper runs out can be read off the page.
  final tens = StringBuffer();
  for (var column = 1; column <= 60; column++) {
    tens.write(column % 10 == 0 ? '${(column ~/ 10) % 10}' : '.');
  }

  final bytes = <int>[
    ..._reset,
    ..._line('WIDTH TEST'),
    ..._line(''),
    ..._line(tens.toString()),
    ..._marker(48),
    ..._line(''),
    ..._line('RIGHT MARGIN PROBE'),
    // Flush to the theoretical edge, which is what `generator.row()` asks for.
    ..._line(' ' * 38 + 'KES 271.00'),
    // One column short of it.
    ..._line(' ' * 37 + 'KES 271.00'),
    // Two columns short.
    ..._line(' ' * 36 + 'KES 271.00'),
    ..._line(''),
    ..._line('1st=flush 2nd=-1 3rd=-2'),
    // Feed rather than cut: this is a measurement, and a cut command to a
    // printer without a cutter prints a control character on some models.
    0x0A, 0x0A, 0x0A, 0x0A,
  ];

  final endpoint = PrinterEndpoint(host: host, port: port);
  final transport = createPrinterTransport();
  stdout.writeln('endpoint : $endpoint');
  stdout.writeln('payload  : ${bytes.length} bytes');
  try {
    await transport.send(endpoint, bytes);
    stdout.writeln('SENT - read the widest marker that printed whole.');
  } on PrinterTransportException catch (error) {
    stdout.writeln('FAILED: ${error.code}');
    exitCode = 1;
  } finally {
    await transport.dispose();
  }
}
