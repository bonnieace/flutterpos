/// The web transport: receipts to a USB printer through WebUSB.
///
/// **USB is how the web till prints, by the developer's choice (2026-10-10).**
/// A browser cannot open a socket to a network printer, and most network
/// receipt printers also have a USB port, so the till's computer drives one
/// over its cable. The browser part is `web/usb_printer.js`; this file is the
/// Dart side of it and the platform seam's web branch.
///
/// **Network and Bluetooth endpoints are refused as unsupported here**, loudly,
/// as the stub always has: a receipt queued for one must fail where a person
/// sees it, never vanish.
///
/// **The script answers in codes and never throws**, so every failure crosses
/// into Dart as data and becomes a [PrinterTransportCode] here - the queue's
/// retry, the attention reason and the sentence a shopkeeper reads all work as
/// they do for a network printer.
library;

import 'dart:convert';
import 'dart:js_interop';

import 'checkout_bluetooth_printer.dart';
import 'checkout_print_helper.dart';
import 'checkout_print_transport_base.dart';
import 'checkout_print_transport_unsupported.dart';
import 'checkout_system_printer.dart';
import 'checkout_usb_printer.dart';

/// `web/usb_printer.js`'s object, or null when the page did not load it.
@JS('UzaPayUsbPrinter')
external _UsbPrinterScript? get _script;

extension type _UsbPrinterScript._(JSObject _) implements JSObject {
  external JSBoolean get isSupported;
  external JSPromise<JSString> choose(JSBoolean anyDevice);
  external JSPromise<JSString> permitted();
  external JSPromise<JSString> probe(JSString key);
  external JSPromise<JSString> print(JSString key, JSString dataBase64);
}

/// USB for the endpoints a browser can reach; an honest "not here" for the
/// rest.
/// The print helper on this computer, when there is one.
final PrintHelper _printHelper = HttpPrintHelper();

/// Whether this browser has found it. One object, so the Printer page that
/// finds it and the receipts that use it agree.
final PrintHelperMemory _printHelperMemory = _LocalStoragePrintHelperMemory();

PrinterTransport createPrinterTransport() => RoutedPrinterTransport(
  // **Through the print helper, once it has been seen** - the one way a
  // browser reaches a network printer.
  network: HelperNetworkPrinterTransport(
    helper: _printHelper,
    memory: _printHelperMemory,
  ),
  bluetooth: const UnsupportedPrinterTransport(),
  // The helper first, through the driver Windows gave the printer; WebUSB
  // when there is no helper, or the printer was moved to WinUSB.
  usb: HelperFirstUsbPrinterTransport(
    helper: _printHelper,
    memory: _printHelperMemory,
    webUsb: const WebUsbPrinterTransport(),
  ),
  // The browser's own print dialog, for any printer this computer prints to.
  system: const SystemPrintTransport(),
);

PrintHelperMemory createPrintHelperMemory() => _printHelperMemory;

@JS('localStorage')
external _Storage? get _localStorage;

extension type _Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

/// [PrintHelperMemory] in this browser's own storage.
///
/// **A flag and nothing more**, which is why it is not a Hive box: a browser
/// that forgets it only means the Printer page looks for the helper again.
/// Storage can refuse to answer - a private window, blocked site data - and
/// then the helper is simply not tried until it is found again.
final class _LocalStoragePrintHelperMemory implements PrintHelperMemory {
  static const String _key = 'uzapay.printHelperSeen';

  bool _seen = false;

  @override
  bool get seen {
    if (_seen) return true;
    try {
      return _seen = _localStorage?.getItem(_key) == '1';
    } on Object {
      return false;
    }
  }

  @override
  void markSeen() {
    _seen = true;
    try {
      _localStorage?.setItem(_key, '1');
    } on Object {
      // Remembered for this run of the page only.
    }
  }

  @override
  void forget() {
    _seen = false;
    try {
      _localStorage?.removeItem(_key);
    } on Object {
      // Nothing was kept, or nothing can be: either way it is forgotten.
    }
  }
}

BluetoothPrinterDiscovery createBluetoothPrinterDiscovery() =>
    const UnsupportedBluetoothPrinterDiscovery();

UsbPrinterChooser createUsbPrinterChooser() => const WebUsbPrinterChooser();

/// Whether the script is loaded and the browser has WebUSB.
bool _scriptSupported() {
  try {
    return _script?.isSupported.toDart ?? false;
  } catch (_) {
    return false;
  }
}

/// Runs one script call and reads its answer.
Future<Map<String, Object?>> _call(
  JSPromise<JSString> Function(_UsbPrinterScript script) operation,
) async {
  final script = _script;
  if (script == null) return const <String, Object?>{'ok': false};
  final text = (await operation(script).toDart).toDart;
  final decoded = jsonDecode(text);
  return decoded is Map<String, Object?>
      ? decoded
      : const <String, Object?>{'ok': false};
}

/// The [PrinterTransportCode] for a code the script answered.
String _codeOf(Object? code) => switch (code) {
  'unsupported' => PrinterTransportCode.unsupported,
  'not_found' => PrinterTransportCode.usbNotFound,
  'busy' => PrinterTransportCode.usbBusy,
  'write_timeout' => PrinterTransportCode.writeTimeout,
  _ => PrinterTransportCode.usbFailed,
};

final class WebUsbPrinterTransport implements PrinterTransport {
  const WebUsbPrinterTransport();

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.usb,
    // The printer chosen is the printer itself; there is no bridge.
    endpointIsPrinter: true,
    label: 'USB printing from this browser',
  );

  /// Opens and claims the printer, and lets it go, without printing.
  @override
  Future<void> probe(PrinterEndpoint endpoint) =>
      _run(endpoint, (script) => script.probe(endpoint.host.toJS));

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) => _run(
    endpoint,
    (script) => script.print(endpoint.host.toJS, base64Encode(bytes).toJS),
  );

  Future<void> _run(
    PrinterEndpoint endpoint,
    JSPromise<JSString> Function(_UsbPrinterScript script) operation,
  ) async {
    if (!endpoint.isUsb || !_scriptSupported()) {
      throw const PrinterTransportException(PrinterTransportCode.unsupported);
    }
    final Map<String, Object?> result;
    try {
      result = await _call(operation);
    } catch (_) {
      // The script itself never throws; anything that does is the browser
      // refusing the call, which is not a printer to retry against.
      throw const PrinterTransportException(PrinterTransportCode.usbFailed);
    }
    if (result['ok'] != true) {
      throw PrinterTransportException(_codeOf(result['code']));
    }
  }

  @override
  Future<void> dispose() async {}
}

final class WebUsbPrinterChooser implements UsbPrinterChooser {
  const WebUsbPrinterChooser();

  @override
  bool get isSupported => _scriptSupported();

  @override
  Future<UsbPrinterDevice?> choose({bool anyDevice = false}) async {
    if (!isSupported) return null;
    final result = await _call((script) => script.choose(anyDevice.toJS));
    if (result['ok'] != true) {
      throw PrinterTransportException(_codeOf(result['code']));
    }
    return _device(result['device']);
  }

  @override
  Future<List<UsbPrinterDevice>> permitted() async {
    if (!isSupported) return const <UsbPrinterDevice>[];
    final result = await _call((script) => script.permitted());
    final devices = result['devices'];
    if (result['ok'] != true || devices is! List) {
      return const <UsbPrinterDevice>[];
    }
    return <UsbPrinterDevice>[
      for (final raw in devices)
        if (_device(raw) case final device?) device,
    ];
  }

  static UsbPrinterDevice? _device(Object? raw) {
    if (raw is! Map) return null;
    final vendorId = raw['vendorId'];
    final productId = raw['productId'];
    if (vendorId is! int || productId is! int) return null;
    String? text(Object? value) => value is String ? value : null;
    return UsbPrinterDevice(
      vendorId: vendorId,
      productId: productId,
      serialNumber: text(raw['serialNumber']),
      productName: text(raw['productName']),
      manufacturerName: text(raw['manufacturerName']),
    );
  }
}
