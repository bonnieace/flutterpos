/// Printing through the device's own print window.
///
/// **The route that needs nothing installed, on any device.** The receipt is
/// laid out as a PDF (`CheckoutReceiptPdf`) and handed to whatever the device
/// prints with: a browser's print dialog on a computer, Android's print
/// screen in the app. The person - or a print service they installed - picks
/// the printer there. So a printer this app cannot reach directly still
/// prints: one with its own driver on a Windows computer, or a receipt
/// printer behind a printing app on a phone.
///
/// **What it costs, and why it is a choice rather than the default.** A window
/// opens for every receipt; cutting and the cash drawer happen only if the
/// printer's own driver is set to do them; and a browser never tells the page
/// whether anything printed, so a job sent here counts as sent once the window
/// has opened. Android does say when the window was closed without printing,
/// and that comes back as `print_dialog_closed`, which can be sent again.
library;

import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:printing/printing.dart';

import 'checkout_print_configuration.dart';
import 'checkout_print_transport_base.dart';

/// Hands a PDF to the device's print window.
///
/// **Only a PDF goes through.** Every job for the print-window endpoint is
/// built as one by the dispatcher, so anything else here is a job this app did
/// not build for it - and a print window shown ESC/POS bytes would print
/// garbage at best.
final class SystemPrintTransport implements PrinterTransport {
  const SystemPrintTransport({
    Future<bool> Function(Uint8List pdf)? present,
    Future<bool> Function()? available,
  }) : _present = present ?? _openPrintWindow,
       _available = available ?? _canPrint;

  /// Opens the window on [pdf]; true unless the device says it was closed
  /// without printing.
  final Future<bool> Function(Uint8List pdf) _present;

  /// Whether this device has a print window at all.
  final Future<bool> Function() _available;

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.system,
    endpointIsPrinter: false,
    label: 'This device’s print window',
  );

  /// Confirms there is a window to open. There is no printer to reach: the
  /// person chooses it in the window.
  @override
  Future<void> probe(PrinterEndpoint endpoint) async {
    _require(endpoint);
    final bool available;
    try {
      available = await _available();
    } on Object {
      throw const PrinterTransportException(
        PrinterTransportCode.printDialogFailed,
      );
    }
    if (!available) {
      throw const PrinterTransportException(PrinterTransportCode.unsupported);
    }
  }

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async {
    _require(endpoint);
    if (!isPdf(bytes)) {
      throw const PrinterTransportException(
        PrinterTransportCode.printDialogFailed,
      );
    }
    final bool printed;
    try {
      printed = await _present(Uint8List.fromList(bytes));
    } on Object {
      throw const PrinterTransportException(
        PrinterTransportCode.printDialogFailed,
      );
    }
    if (!printed) {
      throw const PrinterTransportException(
        PrinterTransportCode.printDialogClosed,
      );
    }
  }

  @override
  Future<void> dispose() async {}

  /// Whether [bytes] begin as a PDF does.
  static bool isPdf(List<int> bytes) {
    const magic = <int>[0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
    if (bytes.length < magic.length) return false;
    for (var index = 0; index < magic.length; index++) {
      if (bytes[index] != magic[index]) return false;
    }
    return true;
  }

  static void _require(PrinterEndpoint endpoint) {
    if (!endpoint.isSystem) {
      throw ArgumentError.value(endpoint, 'endpoint', 'Not the print window.');
    }
  }

  static Future<bool> _openPrintWindow(Uint8List pdf) =>
      Printing.layoutPdf(onLayout: (_) async => pdf, name: 'Receipt');

  static Future<bool> _canPrint() async => (await Printing.info()).canPrint;
}

/// Printing through this device's print window, chosen on this device.
///
/// **Only the paper width is remembered.** The printer is picked in the
/// window each time, and cutting belongs to that printer's driver, so the
/// width the page is laid out for is the one thing this app decides.
final class DeviceSystemPrinter {
  const DeviceSystemPrinter({required this.paperWidth});

  static const int schemaVersion = 1;

  final PrinterPaperWidth paperWidth;

  PrinterEndpoint get endpoint => const PrinterEndpoint.system();

  /// What a receipt is built and sent with - the type every other printer
  /// uses, so the dispatcher and the queue need only ask which kind it is.
  TenantPrinterConfiguration get configuration => TenantPrinterConfiguration(
    transport: PrinterTransportKind.system,
    endpoint: endpoint,
    paperWidth: paperWidth,
    // The driver's to decide; the PDF carries no cut command to send.
    hasCutter: false,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'paperWidth': paperWidth.wireValue,
  };

  /// Throws [FormatException] on anything it cannot trust.
  factory DeviceSystemPrinter.fromMap(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('A print-window record is a map.');
    }
    final paperWidth = PrinterPaperWidth.tryParse(raw['paperWidth']);
    if (raw['schemaVersion'] != schemaVersion || paperWidth == null) {
      throw const FormatException('Malformed print-window record.');
    }
    return DeviceSystemPrinter(paperWidth: paperWidth);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceSystemPrinter && other.paperWidth == paperWidth;

  @override
  int get hashCode => paperWidth.hashCode;
}

/// Whether, and at what width, this device prints each business's receipts
/// through its print window.
abstract interface class DeviceSystemPrinterStore {
  /// Null when not chosen. Throws [FormatException] for a record it cannot
  /// trust.
  DeviceSystemPrinter? read(String tenantId);

  Future<void> save(String tenantId, DeviceSystemPrinter printer);

  /// Stops printing [tenantId]'s receipts through the print window here.
  Future<void> forget(String tenantId);
}

/// [DeviceSystemPrinterStore] in its own small box, keyed by business.
///
/// Not encrypted and not behind the startup storage gate, for the USB and
/// Bluetooth stores' reason: losing it costs choosing again, not a receipt.
final class HiveDeviceSystemPrinterStore implements DeviceSystemPrinterStore {
  const HiveDeviceSystemPrinterStore(this._box);

  static const String boxName = 'checkout-system-printer-v1';

  static Future<HiveDeviceSystemPrinterStore> open({
    HiveInterface? hive,
  }) async => HiveDeviceSystemPrinterStore(
    await (hive ?? Hive).openBox<dynamic>(boxName),
  );

  final Box<dynamic> _box;

  @override
  DeviceSystemPrinter? read(String tenantId) {
    final raw = _box.get(tenantId);
    return raw == null ? null : DeviceSystemPrinter.fromMap(raw);
  }

  @override
  Future<void> save(String tenantId, DeviceSystemPrinter printer) =>
      _box.put(tenantId, printer.toMap());

  @override
  Future<void> forget(String tenantId) => _box.delete(tenantId);
}

/// Opens this device's print-window store, or null when it will not open -
/// which is no choice made, and costs nothing but the option.
Future<DeviceSystemPrinterStore?> openDeviceSystemPrinterStore({
  HiveInterface? hive,
  void Function(Object error, StackTrace stackTrace)? onError,
}) async {
  try {
    return await HiveDeviceSystemPrinterStore.open(hive: hive);
  } catch (error, stackTrace) {
    onError?.call(error, stackTrace);
    return null;
  }
}

/// What this device chose for [tenantId], or null to look elsewhere.
///
/// A record it cannot read answers `malformed` - which prints nowhere and
/// says so - rather than a guess, as the USB and Bluetooth choices do.
TenantConfiguredPrinter? systemPrinterChosenHere(
  DeviceSystemPrinterStore? store,
  String tenantId,
) {
  if (store == null) return null;
  final DeviceSystemPrinter? chosen;
  try {
    chosen = store.read(tenantId);
  } on FormatException {
    return const TenantConfiguredPrinter.malformed();
  }
  return chosen == null
      ? null
      : TenantConfiguredPrinter.configured(chosen.configuration);
}
