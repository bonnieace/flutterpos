/// A USB receipt printer, chosen in the browser it is plugged into.
///
/// **Web only, and device-local for Bluetooth's reason.** The developer chose
/// USB as the way the web till prints (2026-10-10): browsers cannot open a
/// socket to a network printer, and most network receipt printers also have a
/// USB port. A USB printer is cabled to one computer, so it is chosen in that
/// computer's browser and kept there, per business - never in the business
/// document, which every other till reads.
///
/// **A chosen USB printer takes this browser's receipts**, as a chosen
/// Bluetooth printer takes a phone's - see `devicePrinterLoading`. The receipt
/// is then queued, retried and reprinted exactly as a network one is:
/// `RoutedPrinterTransport` sends it down the link its endpoint names.
///
/// Nothing here touches the browser. WebUSB lives behind the platform seam in
/// `checkout_print_transport.dart`, so this file, the USB tab and every test
/// are plain Dart.
library;

import 'package:hive/hive.dart';

import 'checkout_print_configuration.dart';
import 'checkout_print_transport_base.dart';

/// A USB device the browser reported: chosen in its picker, or one this site
/// was allowed to use before.
final class UsbPrinterDevice {
  const UsbPrinterDevice({
    required this.vendorId,
    required this.productId,
    this.serialNumber,
    this.productName,
    this.manufacturerName,
  });

  final int vendorId;
  final int productId;
  final String? serialNumber;
  final String? productName;
  final String? manufacturerName;

  /// What it is found again by. See [PrinterEndpoint.usbKey].
  String get key => PrinterEndpoint.usbKey(
    vendorId: vendorId,
    productId: productId,
    serialNumber: serialNumber,
  );

  /// What a person reads: the model name the printer reports, with its maker
  /// where that is not already in it, or its numbers when it reports neither.
  String get label {
    final product = productName?.trim() ?? '';
    final maker = manufacturerName?.trim() ?? '';
    if (product.isEmpty && maker.isEmpty) return 'USB printer $key';
    if (product.isEmpty) return '$maker printer';
    if (maker.isEmpty || product.toLowerCase().contains(maker.toLowerCase())) {
      return product;
    }
    return '$maker $product';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsbPrinterDevice &&
          other.vendorId == vendorId &&
          other.productId == productId &&
          other.serialNumber == serialNumber &&
          other.productName == productName &&
          other.manufacturerName == manufacturerName;

  @override
  int get hashCode => Object.hash(
    vendorId,
    productId,
    serialNumber,
    productName,
    manufacturerName,
  );
}

/// Choosing a USB printer: the USB tab's only view of the browser, so it can
/// be driven by a fake.
abstract interface class UsbPrinterChooser {
  /// Whether this browser has WebUSB at all - Chrome and Edge do, Safari and
  /// Firefox do not. Synchronous, so a screen can decide what to draw first.
  bool get isSupported;

  /// Opens the browser's own device picker. The chosen device, or null when
  /// the person closed it without choosing.
  ///
  /// **Only from a press**: a browser shows the picker for a user gesture and
  /// refuses it otherwise. Printers only, by the USB printer class, unless
  /// [anyDevice] - for the receipt printer that reports itself as a vendor's
  /// own class rather than as a printer.
  Future<UsbPrinterDevice?> choose({bool anyDevice = false});

  /// The USB devices this site may already use, without asking again.
  Future<List<UsbPrinterDevice>> permitted();
}

/// The answer everywhere WebUSB does not exist: every platform but the web,
/// and the browsers that do not have it.
final class UnsupportedUsbPrinterChooser implements UsbPrinterChooser {
  const UnsupportedUsbPrinterChooser();

  @override
  bool get isSupported => false;

  @override
  Future<UsbPrinterDevice?> choose({bool anyDevice = false}) async => null;

  @override
  Future<List<UsbPrinterDevice>> permitted() async =>
      const <UsbPrinterDevice>[];
}

/// The USB printer this browser sends one business's receipts to.
final class DeviceUsbPrinter {
  DeviceUsbPrinter({
    required String key,
    required this.name,
    required this.paperWidth,
    required this.hasCutter,
  }) : endpoint = PrinterEndpoint.usb(key);

  static const int schemaVersion = 1;

  final PrinterEndpoint endpoint;

  /// The name the printer reported when it was chosen, so the page can say
  /// which printer this is without asking the browser.
  final String name;

  final PrinterPaperWidth paperWidth;
  final bool hasCutter;

  String get key => endpoint.host;

  /// What a receipt is built and sent with - the same type a network printer
  /// is, so the receipt body, the test page and the queue need no branch.
  TenantPrinterConfiguration get configuration => TenantPrinterConfiguration(
    transport: PrinterTransportKind.usb,
    endpoint: endpoint,
    paperWidth: paperWidth,
    hasCutter: hasCutter,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'key': key,
    'name': name,
    'paperWidth': paperWidth.wireValue,
    'hasCutter': hasCutter,
  };

  /// Throws [FormatException] on anything it cannot trust: a guessed printer
  /// is worse than none.
  factory DeviceUsbPrinter.fromMap(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('A USB printer record is a map.');
    }
    final key = raw['key'];
    final name = raw['name'];
    final paperWidth = PrinterPaperWidth.tryParse(raw['paperWidth']);
    final hasCutter = raw['hasCutter'];
    if (raw['schemaVersion'] != schemaVersion ||
        key is! String ||
        name is! String ||
        paperWidth == null ||
        hasCutter is! bool) {
      throw const FormatException('Malformed USB printer record.');
    }
    try {
      return DeviceUsbPrinter(
        key: key,
        name: name,
        paperWidth: paperWidth,
        hasCutter: hasCutter,
      );
    } on ArgumentError {
      throw const FormatException('Malformed USB printer key.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceUsbPrinter &&
          other.endpoint == endpoint &&
          other.name == name &&
          other.paperWidth == paperWidth &&
          other.hasCutter == hasCutter;

  @override
  int get hashCode => Object.hash(endpoint, name, paperWidth, hasCutter);
}

/// Which USB printer, if any, this browser uses for each business.
abstract interface class DeviceUsbPrinterStore {
  /// Null when none is chosen. Throws [FormatException] for a record it
  /// cannot trust.
  DeviceUsbPrinter? read(String tenantId);

  Future<void> save(String tenantId, DeviceUsbPrinter printer);

  /// Stops using a USB printer for [tenantId] in this browser.
  Future<void> forget(String tenantId);
}

/// [DeviceUsbPrinterStore] in its own small box, keyed by business.
///
/// **Not encrypted, and not behind the startup storage gate**, for the reason
/// the Bluetooth store gives: it holds a printer's model numbers and a name,
/// and losing it costs choosing the printer again - not a receipt.
final class HiveDeviceUsbPrinterStore implements DeviceUsbPrinterStore {
  const HiveDeviceUsbPrinterStore(this._box);

  static const String boxName = 'checkout-usb-printer-v1';

  static Future<HiveDeviceUsbPrinterStore> open({HiveInterface? hive}) async =>
      HiveDeviceUsbPrinterStore(await (hive ?? Hive).openBox<dynamic>(boxName));

  final Box<dynamic> _box;

  @override
  DeviceUsbPrinter? read(String tenantId) {
    final raw = _box.get(tenantId);
    return raw == null ? null : DeviceUsbPrinter.fromMap(raw);
  }

  @override
  Future<void> save(String tenantId, DeviceUsbPrinter printer) =>
      _box.put(tenantId, printer.toMap());

  @override
  Future<void> forget(String tenantId) => _box.delete(tenantId);
}

/// Opens this browser's USB printer store, or null when it will not open.
///
/// **Null is no choice made**, and on the web that is safe in a way it is not
/// for Bluetooth on a phone: the browser has no network printer to fall back
/// to and send receipts to the wrong counter. A till whose store will not open
/// prints nowhere and says so, and choosing the printer again puts it right.
Future<DeviceUsbPrinterStore?> openDeviceUsbPrinterStore({
  HiveInterface? hive,
  void Function(Object error, StackTrace stackTrace)? onError,
}) async {
  try {
    return await HiveDeviceUsbPrinterStore.open(hive: hive);
  } catch (error, stackTrace) {
    onError?.call(error, stackTrace);
    return null;
  }
}

/// What this browser chose for [tenantId], or null to look elsewhere.
///
/// A record it cannot read is a printer it cannot name, and answers
/// `malformed` - which prints nowhere and says so - rather than a guess.
TenantConfiguredPrinter? usbPrinterChosenHere(
  DeviceUsbPrinterStore? store,
  String tenantId,
) {
  if (store == null) return null;
  final DeviceUsbPrinter? chosen;
  try {
    chosen = store.read(tenantId);
  } on FormatException {
    return const TenantConfiguredPrinter.malformed();
  }
  return chosen == null
      ? null
      : TenantConfiguredPrinter.configured(chosen.configuration);
}
