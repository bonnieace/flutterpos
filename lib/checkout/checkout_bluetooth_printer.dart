/// A Bluetooth receipt printer, chosen on this device.
///
/// **Device-local, and that is the decision this file is written around.** The
/// network printer is a business setting - `tenants/{tenantId}/configuration/
/// printer`, one address every till dials. A Bluetooth printer is *paired with
/// one phone*: another till cannot reach it, and could not connect while this
/// one holds it. So it is chosen on the phone that uses it and kept in a box on
/// that phone, per business, and the business document never names one.
///
/// **That also keeps older builds whole.** The business document's shape does
/// not change, so a till still on an earlier build reads exactly what it read
/// before, whatever any other phone has paired with.
///
/// **What it changes is where *this* device's receipts go.** [devicePrinter]
/// is the one rule: a Bluetooth printer chosen here wins on this device, and
/// without one the business's network printer is used as it always was. The
/// receipt is then queued, retried and reprinted exactly as a network one is -
/// `RoutedPrinterTransport` sends it down whichever link its endpoint names.
///
/// Nothing here imports a Bluetooth plugin. The Android implementation lives
/// behind the platform seam in `checkout_print_transport.dart`, so this file,
/// the setup tab and every test are plain Dart.
library;

import 'package:hive/hive.dart';

import 'checkout_print_configuration.dart';
import 'checkout_print_transport_base.dart';

/// One device a Bluetooth search, or the paired list, turned up.
///
/// **Not known to be a printer.** Android's classic discovery reports every
/// nearby device - phones, speakers, a television - and the plugin does not
/// carry the device class that would say *imaging*. The person recognises the
/// printer by its name; the list only orders the named ones first.
final class BluetoothPrinterDevice {
  const BluetoothPrinterDevice({
    required this.address,
    required this.paired,
    this.name,
  });

  /// As Android reports it: upper case, colon separated.
  final String address;

  /// The broadcast name, or null when the device sent none.
  final String? name;

  /// Bonded with this phone already. An unpaired printer is paired before it
  /// is used, which is a prompt the person answers.
  final bool paired;

  /// What a person reads: the name, or the address when there is none.
  String get label {
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? address : trimmed;
  }

  bool get hasName => label != address;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BluetoothPrinterDevice &&
          other.address == address &&
          other.name == name &&
          other.paired == paired;

  @override
  int get hashCode => Object.hash(address, name, paired);
}

/// Whether this device can search for and connect to a Bluetooth printer now.
enum BluetoothReadiness {
  ready,

  /// The radio is switched off. The person can turn it on from the app.
  off,

  /// Android's *Nearby devices* permission (or location, before Android 12)
  /// was refused. Only the phone's settings can grant it after a refusal.
  permissionDenied,

  /// No Bluetooth printing here: web, desktop and iOS, or a phone without a
  /// radio.
  unsupported,
}

/// Finding and pairing Bluetooth printers. The setup tab's only view of the
/// platform, so it can be driven by a fake.
abstract interface class BluetoothPrinterDiscovery {
  /// Whether this platform can use Bluetooth printers at all. Synchronous, so
  /// a screen can decide what to draw before asking anything.
  bool get isSupported;

  /// Asks for the permissions a search needs, then reports the radio.
  ///
  /// **The one call that may raise a system prompt**, and it is only made when
  /// a person presses something - never on opening the page.
  Future<BluetoothReadiness> prepare();

  /// Asks the system to switch Bluetooth on. True when it is on afterwards.
  Future<bool> turnOn();

  /// Opens this app's page in the phone's settings, the only place a refused
  /// permission can be granted again.
  Future<void> openPermissionSettings();

  /// The devices already paired with this phone.
  Future<List<BluetoothPrinterDevice>> paired();

  /// Nearby devices, as discovery finds them. The stream ends when discovery
  /// does - about twelve seconds on Android - and cancelling it stops
  /// discovery early. The same device may be reported more than once.
  Stream<BluetoothPrinterDevice> search();

  /// Pairs with [address], completing once the phone and the printer are
  /// bonded. False when pairing was refused or did not finish in time.
  ///
  /// A device that is already paired answers true at once.
  Future<bool> pair(String address);
}

/// The answer everywhere Bluetooth printing does not exist.
final class UnsupportedBluetoothPrinterDiscovery
    implements BluetoothPrinterDiscovery {
  const UnsupportedBluetoothPrinterDiscovery();

  @override
  bool get isSupported => false;

  @override
  Future<BluetoothReadiness> prepare() async => BluetoothReadiness.unsupported;

  @override
  Future<bool> turnOn() async => false;

  @override
  Future<void> openPermissionSettings() async {}

  @override
  Future<List<BluetoothPrinterDevice>> paired() async =>
      const <BluetoothPrinterDevice>[];

  @override
  Stream<BluetoothPrinterDevice> search() =>
      const Stream<BluetoothPrinterDevice>.empty();

  @override
  Future<bool> pair(String address) async => false;
}

/// The Bluetooth printer this device sends one business's receipts to.
final class DeviceBluetoothPrinter {
  DeviceBluetoothPrinter({
    required String address,
    required this.name,
    required this.paperWidth,
    required this.hasCutter,
  }) : endpoint = PrinterEndpoint.bluetooth(address);

  static const int schemaVersion = 1;

  final PrinterEndpoint endpoint;

  /// The name the printer broadcast when it was chosen, so the page can say
  /// which printer this is without asking the radio.
  final String name;

  final PrinterPaperWidth paperWidth;
  final bool hasCutter;

  String get address => endpoint.host;

  /// What a receipt is built and sent with - the same type a network printer
  /// is, so the receipt body, the test page and the queue need no branch.
  TenantPrinterConfiguration get configuration => TenantPrinterConfiguration(
    transport: PrinterTransportKind.bluetooth,
    endpoint: endpoint,
    paperWidth: paperWidth,
    hasCutter: hasCutter,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'address': address,
    'name': name,
    'paperWidth': paperWidth.wireValue,
    'hasCutter': hasCutter,
  };

  /// Throws [FormatException] on anything it cannot trust, for the reason
  /// `TenantPrinterConfiguration.fromMap` gives: a guessed printer is worse
  /// than none.
  factory DeviceBluetoothPrinter.fromMap(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('A Bluetooth printer record is a map.');
    }
    final address = raw['address'];
    final name = raw['name'];
    final paperWidth = PrinterPaperWidth.tryParse(raw['paperWidth']);
    final hasCutter = raw['hasCutter'];
    if (raw['schemaVersion'] != schemaVersion ||
        address is! String ||
        name is! String ||
        paperWidth == null ||
        hasCutter is! bool) {
      throw const FormatException('Malformed Bluetooth printer record.');
    }
    try {
      return DeviceBluetoothPrinter(
        address: address,
        name: name,
        paperWidth: paperWidth,
        hasCutter: hasCutter,
      );
    } on ArgumentError {
      throw const FormatException('Malformed Bluetooth printer address.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceBluetoothPrinter &&
          other.endpoint == endpoint &&
          other.name == name &&
          other.paperWidth == paperWidth &&
          other.hasCutter == hasCutter;

  @override
  int get hashCode => Object.hash(endpoint, name, paperWidth, hasCutter);
}

/// Which Bluetooth printer, if any, this device uses for each business.
abstract interface class DeviceBluetoothPrinterStore {
  /// Null when none is chosen. Throws [FormatException] for a record it
  /// cannot trust.
  DeviceBluetoothPrinter? read(String tenantId);

  Future<void> save(String tenantId, DeviceBluetoothPrinter printer);

  /// Stops using a Bluetooth printer for [tenantId] on this device.
  Future<void> forget(String tenantId);
}

/// [DeviceBluetoothPrinterStore] in its own small box, keyed by business.
///
/// **Not encrypted, and not behind the startup storage gate**, for the reason
/// `HiveCheckoutPrinterSetupReminder` gives: it holds a device address and a
/// name, and losing it costs choosing the printer again - not a receipt.
final class HiveDeviceBluetoothPrinterStore
    implements DeviceBluetoothPrinterStore {
  const HiveDeviceBluetoothPrinterStore(this._box);

  static const String boxName = 'checkout-bluetooth-printer-v1';

  static Future<HiveDeviceBluetoothPrinterStore> open({
    HiveInterface? hive,
  }) async => HiveDeviceBluetoothPrinterStore(
    await (hive ?? Hive).openBox<dynamic>(boxName),
  );

  final Box<dynamic> _box;

  /// Marks a box started again after the one before it would not open.
  ///
  /// **It outlives the restart that follows**, which is the point: in such a
  /// box a business with no record may have chosen a printer in the one that
  /// was lost, so it reads as unreadable until it is chosen or forgotten
  /// again, never as no choice.
  static const String _rebuiltKey = '__rebuilt__';

  /// What [forget] leaves in a rebuilt box: a business that chose nothing.
  static const String _noneChosen = 'none';

  @override
  DeviceBluetoothPrinter? read(String tenantId) {
    final raw = _box.get(tenantId);
    if (raw == _noneChosen) return null;
    if (raw == null) {
      if (_box.get(_rebuiltKey) == true) {
        throw const FormatException(
          'This device lost its Bluetooth printer choice for this business.',
        );
      }
      return null;
    }
    return DeviceBluetoothPrinter.fromMap(raw);
  }

  @override
  Future<void> save(String tenantId, DeviceBluetoothPrinter printer) =>
      _box.put(tenantId, printer.toMap());

  @override
  Future<void> forget(String tenantId) => _box.get(_rebuiltKey) == true
      ? _box.put(tenantId, _noneChosen)
      : _box.delete(tenantId);

  /// Says this box replaces one that would not open; see [_rebuiltKey].
  Future<void> markRebuilt() => _box.put(_rebuiltKey, true);
}

/// Opens this device's Bluetooth printer store, or answers what a box that
/// will not open means.
///
/// **No box yet is no choice made**: choosing a printer is what creates it, so
/// a device that cannot open one it never had prints on the network printer
/// (null). **A box that exists and will not open is a choice that cannot be
/// read**, and answers [UnopenedDeviceBluetoothPrinterStore] - which refuses
/// rather than sending receipts to another counter, and is put right from the
/// Bluetooth tab by choosing again or forgetting.
Future<DeviceBluetoothPrinterStore?> openDeviceBluetoothPrinterStore({
  HiveInterface? hive,
  void Function(Object error, StackTrace stackTrace)? onError,
}) async {
  final store = hive ?? Hive;
  try {
    return await HiveDeviceBluetoothPrinterStore.open(hive: store);
  } catch (error, stackTrace) {
    onError?.call(error, stackTrace);
    try {
      if (!await store.boxExists(HiveDeviceBluetoothPrinterStore.boxName)) {
        return null;
      }
    } catch (_) {
      // Whether it exists cannot be told either; nor can what it held.
    }
    return UnopenedDeviceBluetoothPrinterStore(hive: store);
  }
}

/// The store for a Bluetooth printer box that exists but would not open.
///
/// **Every business reads as unreadable** until it is put right, because any
/// of them may have chosen a printer this device can no longer name. Saving or
/// forgetting one starts the box again, marked rebuilt, so the businesses not
/// put right yet stay unreadable after a restart too.
final class UnopenedDeviceBluetoothPrinterStore
    implements DeviceBluetoothPrinterStore {
  UnopenedDeviceBluetoothPrinterStore({HiveInterface? hive})
    : _hive = hive ?? Hive;

  final HiveInterface _hive;
  HiveDeviceBluetoothPrinterStore? _fresh;

  @override
  DeviceBluetoothPrinter? read(String tenantId) {
    final fresh = _fresh;
    if (fresh == null) {
      throw const FormatException(
        'This device could not open its Bluetooth printer choice.',
      );
    }
    return fresh.read(tenantId);
  }

  @override
  Future<void> save(String tenantId, DeviceBluetoothPrinter printer) async =>
      (await _startAgain()).save(tenantId, printer);

  @override
  Future<void> forget(String tenantId) async =>
      (await _startAgain()).forget(tenantId);

  Future<HiveDeviceBluetoothPrinterStore> _startAgain() async {
    final fresh = _fresh;
    if (fresh != null) return fresh;
    await _hive.deleteBoxFromDisk(HiveDeviceBluetoothPrinterStore.boxName);
    final started = await HiveDeviceBluetoothPrinterStore.open(hive: _hive);
    await started.markRebuilt();
    return _fresh = started;
  }
}

/// Where this device sends [tenantId]'s receipts.
///
/// **A Bluetooth printer chosen on this device wins; otherwise the business's
/// network printer, unchanged.** A record this device cannot read refuses
/// rather than falling back: printing on the network printer when somebody
/// chose a Bluetooth one would put receipts on the wrong counter without a
/// word, which is §2's fail-open in a new place.
TenantConfiguredPrinter devicePrinter({
  required TenantConfiguredPrinter business,
  required DeviceBluetoothPrinterStore? store,
  required String tenantId,
}) => _chosenHere(store, tenantId) ?? business;

/// [devicePrinter], reading the business's printer only when it is the
/// answer: a device printing on Bluetooth never needs it, and this asks for
/// it on every receipt.
Future<TenantConfiguredPrinter> devicePrinterLoading({
  required Future<TenantConfiguredPrinter> Function() business,
  required DeviceBluetoothPrinterStore? store,
  required String tenantId,
}) async => _chosenHere(store, tenantId) ?? await business();

/// What this device chose for [tenantId], or null to use the business's.
TenantConfiguredPrinter? _chosenHere(
  DeviceBluetoothPrinterStore? store,
  String tenantId,
) {
  if (store == null) return null;
  final DeviceBluetoothPrinter? chosen;
  try {
    chosen = store.read(tenantId);
  } on FormatException {
    return const TenantConfiguredPrinter.malformed();
  }
  return chosen == null
      ? null
      : TenantConfiguredPrinter.configured(chosen.configuration);
}
