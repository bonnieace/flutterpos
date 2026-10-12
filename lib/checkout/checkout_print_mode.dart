/// Which kind of printer this device prints its receipts on, per business:
/// one at a time.
///
/// **One switch on the Printer page per kind, and at most one on.** Until
/// 2026-10-11 a USB, Bluetooth or print-dialog choice quietly took a device's
/// receipts away from the business's network printer, and the page showed
/// every kind's settings at once in tabs. Now the device remembers which kind
/// it uses, receipts go there and nowhere else, and switching kinds keeps each
/// kind's own settings - a USB printer switched off is still the one chosen
/// when USB is switched back on.
///
/// **A device that never chose prints as it always did**: a printer chosen on
/// it, or else the business's network printer. That is the reading for every
/// device installed before this file existed.
library;

import 'package:hive/hive.dart';

/// The kinds of printer a device can print on.
enum DevicePrintMode {
  /// The business's network printer, which every till shares.
  network('network'),

  /// A USB printer chosen in this browser.
  usb('usb'),

  /// A Bluetooth printer paired with this phone.
  bluetooth('bluetooth'),

  /// The device's own print window.
  dialog('dialog'),

  /// No printer: sales are recorded, receipts are not printed.
  off('off');

  const DevicePrintMode(this.wireValue);

  final String wireValue;

  static DevicePrintMode? tryParse(Object? value) {
    for (final mode in values) {
      if (mode.wireValue == value) return mode;
    }
    return null;
  }
}

/// Which kind of printer this device uses for each business.
abstract interface class DevicePrintModeStore {
  /// Null when this device never chose. Throws [FormatException] for a record
  /// it cannot trust.
  DevicePrintMode? read(String tenantId);

  Future<void> save(String tenantId, DevicePrintMode mode);
}

/// [DevicePrintModeStore] in its own small box, keyed by business.
///
/// Not encrypted and not behind the startup storage gate, for the printer
/// stores' reason: losing it costs switching a printer on again.
final class HiveDevicePrintModeStore implements DevicePrintModeStore {
  const HiveDevicePrintModeStore(this._box);

  static const String boxName = 'checkout-print-mode-v1';
  static const int schemaVersion = 1;

  static Future<HiveDevicePrintModeStore> open({HiveInterface? hive}) async =>
      HiveDevicePrintModeStore(await (hive ?? Hive).openBox<dynamic>(boxName));

  final Box<dynamic> _box;

  @override
  DevicePrintMode? read(String tenantId) {
    final raw = _box.get(tenantId);
    if (raw == null) return null;
    final mode = raw is Map && raw['schemaVersion'] == schemaVersion
        ? DevicePrintMode.tryParse(raw['mode'])
        : null;
    if (mode == null) {
      throw const FormatException('Malformed print mode record.');
    }
    return mode;
  }

  @override
  Future<void> save(String tenantId, DevicePrintMode mode) => _box.put(
    tenantId,
    <String, Object?>{'schemaVersion': schemaVersion, 'mode': mode.wireValue},
  );
}

/// Opens this device's print-mode store, or null when it will not open -
/// which leaves the device printing as it did before modes existed.
Future<DevicePrintModeStore?> openDevicePrintModeStore({
  HiveInterface? hive,
  void Function(Object error, StackTrace stackTrace)? onError,
}) async {
  try {
    return await HiveDevicePrintModeStore.open(hive: hive);
  } catch (error, stackTrace) {
    onError?.call(error, stackTrace);
    return null;
  }
}
