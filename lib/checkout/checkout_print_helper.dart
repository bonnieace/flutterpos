/// The print helper, from the web till's side.
///
/// **A browser cannot reach a network printer, nor a USB printer Windows'
/// own driver holds**, and the helper is a small Windows program that can.
/// It listens on this computer only - `http://127.0.0.1:17919` - and prints
/// what UzaPay's pages send it: to a network printer by socket, to a USB
/// printer through the driver Windows gave it. Its source is
/// `tool/print_helper/`.
///
/// **It is only knocked on once it has been seen.** A public page calling
/// this computer makes Chrome ask the person first, and a till that never
/// installed the helper should never be asked that at the counter. So the
/// Printer page looks for it, remembers finding it ([PrintHelperMemory]), and
/// only then do receipts go its way.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'checkout_print_transport_base.dart';

/// Where the helper listens. Kept equal to `helperPort` in
/// `tool/print_helper/lib/src/protocol.dart`.
final Uri printHelperAddress = Uri.parse('http://127.0.0.1:17919');

/// What the helper answers as, so a page knows it found this and not another
/// program on the port.
const String printHelperApp = 'uzapay-print-helper';

/// The helper's download, on UzaPay's own download site: the Hosting site
/// `tool/print_helper/firebase.json` deploys, under its own domain.
///
/// It used to be a Storage token link, and the same file is still kept there
/// for builds that carry that link.
const String printHelperDownloadUrl = String.fromEnvironment(
  'PRINT_HELPER_URL',
  defaultValue:
      'https://downloads.uzapay.co.ke/print-helper/UzaPayPrintHelper.exe',
);

/// A USB printer the helper found.
final class PrintHelperPrinter {
  const PrintHelperPrinter({required this.key, required this.name});

  /// The same key the USB tab builds from a browser's answer, so a printer is
  /// one printer whichever way it was found.
  final String key;
  final String name;
}

/// What asking the helper to remove itself came to.
enum PrintHelperRemoval {
  /// It answered, and is stopping and removing itself.
  removed,

  /// It answered as a version from before it could remove itself (1.0.3 and
  /// earlier), so it has to be uninstalled from Windows' own *Apps* list.
  outdated,

  /// Nothing answered, or not with a yes.
  failed,
}

/// The helper, as the till asks things of it. An interface so a test needs
/// no helper.
abstract interface class PrintHelper {
  /// The version answering on this computer, or null when none does.
  Future<String?> version();

  /// The USB printers the helper can print to now.
  Future<List<PrintHelperPrinter>> usbPrinters();

  /// Sends [bytes] to [endpoint], a network or USB printer. Throws
  /// [PrinterTransportException] with the helper's code, or
  /// [PrinterTransportCode.printHelperUnreachable] when nothing answered.
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes);

  /// Whether [endpoint] is there to print to, without printing.
  Future<void> probe(PrinterEndpoint endpoint);

  /// Asks the helper to stop, stop starting with Windows, and delete itself:
  /// everything its own `--uninstall` does, without a window to say so.
  Future<PrintHelperRemoval> remove();
}

/// Whether this browser has found the helper before.
abstract interface class PrintHelperMemory {
  bool get seen;
  void markSeen();

  /// Back to never having seen it: the helper was removed, so receipts stop
  /// knocking on this computer's door until it is found again.
  void forget();
}

/// [PrintHelperMemory] for one run of the app, and for tests.
final class InMemoryPrintHelperMemory implements PrintHelperMemory {
  InMemoryPrintHelperMemory({this.seen = false});

  @override
  bool seen;

  @override
  void markSeen() => seen = true;

  @override
  void forget() => seen = false;
}

/// [PrintHelper] over HTTP.
final class HttpPrintHelper implements PrintHelper {
  HttpPrintHelper({
    http.Client? client,
    Uri? address,
    this.lookTimeout = const Duration(seconds: 3),
    this.printTimeout = const Duration(seconds: 25),
  }) : _client = client ?? http.Client(),
       _address = address ?? printHelperAddress;

  final http.Client _client;
  final Uri _address;

  /// How long a look for the helper waits: it is on this computer, so it
  /// answers at once or not at all.
  final Duration lookTimeout;

  /// How long a print waits. Longer than the helper's own write timeout, so
  /// its answer arrives rather than this one.
  final Duration printTimeout;

  @override
  Future<String?> version() async {
    try {
      final response = await _client
          .get(_address.resolve('/status'))
          .timeout(lookTimeout);
      final body = _decode(response.body);
      return body['app'] == printHelperApp ? body['version'] as String? : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<List<PrintHelperPrinter>> usbPrinters() async {
    final http.Response response;
    try {
      response = await _client
          .get(_address.resolve('/printers'))
          .timeout(printTimeout);
    } on Object {
      throw const PrinterTransportException(
        PrinterTransportCode.printHelperUnreachable,
      );
    }
    final usb = _decode(response.body)['usb'];
    return <PrintHelperPrinter>[
      if (usb is List)
        for (final printer in usb)
          if (printer is Map &&
              printer['key'] is String &&
              printer['name'] is String)
            PrintHelperPrinter(
              key: printer['key'] as String,
              name: printer['name'] as String,
            ),
    ];
  }

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) => _ask(
    '/print',
    <String, Object?>{'target': _target(endpoint), 'data': base64Encode(bytes)},
    // A print that outlasts the wait may still come out: the helper was
    // handed it. The same honest answer a stalled socket gets.
    onTimeout: PrinterTransportCode.writeTimeout,
  );

  @override
  Future<void> probe(PrinterEndpoint endpoint) => _ask(
    '/probe',
    <String, Object?>{'target': _target(endpoint)},
    onTimeout: PrinterTransportCode.printHelperUnreachable,
  );

  @override
  Future<PrintHelperRemoval> remove() async {
    final http.Response response;
    try {
      response = await _client
          .post(
            _address.resolve('/uninstall'),
            // JSON for the same reason as a print: the helper is only asked
            // after it agreed to talk to this page.
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(const <String, Object?>{}),
          )
          .timeout(lookTimeout);
    } on Object {
      return PrintHelperRemoval.failed;
    }
    if (response.statusCode == 404) return PrintHelperRemoval.outdated;
    return _decode(response.body)['ok'] == true
        ? PrintHelperRemoval.removed
        : PrintHelperRemoval.failed;
  }

  Future<void> _ask(
    String path,
    Map<String, Object?> body, {
    required String onTimeout,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            _address.resolve(path),
            // JSON, which a browser asks the helper about before sending -
            // the question the helper answers only for UzaPay's own pages.
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(printTimeout);
    } on TimeoutException {
      throw PrinterTransportException(onTimeout);
    } on Object {
      throw const PrinterTransportException(
        PrinterTransportCode.printHelperUnreachable,
      );
    }
    final answer = _decode(response.body);
    if (answer['ok'] == true) return;
    final code = answer['code'];
    throw PrinterTransportException(
      code is String && code.isNotEmpty
          ? code
          : PrinterTransportCode.printHelperUnreachable,
    );
  }

  static Map<String, Object?> _target(PrinterEndpoint endpoint) =>
      switch (endpoint.kind) {
        PrinterEndpointKind.network => <String, Object?>{
          'kind': 'network',
          'host': endpoint.host,
          'port': endpoint.port,
        },
        PrinterEndpointKind.usb => <String, Object?>{
          'kind': 'usb',
          'key': endpoint.host,
        },
        _ => throw ArgumentError.value(endpoint, 'endpoint'),
      };

  static Map<String, Object?> _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map ? value.cast<String, Object?>() : const {};
    } on FormatException {
      return const <String, Object?>{};
    }
  }
}

/// Network printers from a browser: through the helper, the only way there.
///
/// **Before the helper has been seen it is not tried**, and the answer is the
/// one a browser has always given - `unsupported`, whose sentence now names
/// the helper.
final class HelperNetworkPrinterTransport implements PrinterTransport {
  const HelperNetworkPrinterTransport({
    required this.helper,
    required this.memory,
  });

  final PrintHelper helper;
  final PrintHelperMemory memory;

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.printHelper,
    endpointIsPrinter: true,
    label: 'Network printing through the print helper',
  );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async {
    _require();
    await helper.probe(endpoint);
  }

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async {
    _require();
    await helper.send(endpoint, bytes);
  }

  void _require() {
    if (!memory.seen) {
      throw const PrinterTransportException(PrinterTransportCode.unsupported);
    }
  }

  @override
  Future<void> dispose() async {}
}

/// USB printers from a browser: through the helper when it is there, and
/// through WebUSB when it is not.
///
/// **The helper first**, because it needs nothing changed on the computer:
/// it prints through the driver Windows already gave the printer, which is
/// exactly the driver that stops WebUSB. WebUSB is tried only when the helper
/// is not running or cannot see the printer - a printer whose driver was
/// swapped for WinUSB is one only WebUSB can reach - and never after the
/// helper reported any other failure, which could mean half a receipt is
/// already on the roll.
final class HelperFirstUsbPrinterTransport implements PrinterTransport {
  const HelperFirstUsbPrinterTransport({
    required this.helper,
    required this.memory,
    required this.webUsb,
  });

  final PrintHelper helper;
  final PrintHelperMemory memory;
  final PrinterTransport webUsb;

  @override
  PrinterTransportCapability get capability => webUsb.capability;

  @override
  Future<void> probe(PrinterEndpoint endpoint) async {
    if (await _byHelper(() => helper.probe(endpoint))) return;
    await webUsb.probe(endpoint);
  }

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async {
    if (await _byHelper(() => helper.send(endpoint, bytes))) return;
    await webUsb.send(endpoint, bytes);
  }

  /// True when the helper did it; false when WebUSB should try.
  Future<bool> _byHelper(Future<void> Function() attempt) async {
    if (!memory.seen) return false;
    try {
      await attempt();
      return true;
    } on PrinterTransportException catch (error) {
      if (error.code == PrinterTransportCode.printHelperUnreachable ||
          error.code == PrinterTransportCode.usbNotFound) {
        return false;
      }
      rethrow;
    }
  }

  @override
  Future<void> dispose() => webUsb.dispose();
}
