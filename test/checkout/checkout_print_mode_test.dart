import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uzapay_pos/checkout/checkout.dart';

const String _tenant = 'tenant-a';

final TenantConfiguredPrinter _business = TenantConfiguredPrinter.configured(
  TenantPrinterConfiguration(
    transport: PrinterTransportKind.directTcp,
    endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
    paperWidth: PrinterPaperWidth.columns48,
    hasCutter: true,
  ),
);

final DeviceUsbPrinter _usbPrinter = DeviceUsbPrinter(
  key: '1FC9:2016:06C6ACA91073',
  name: 'Xprinter XP-365B',
  paperWidth: PrinterPaperWidth.columns48,
  hasCutter: true,
);

void main() {
  group('where this device prints, one kind at a time', () {
    TenantConfiguredPrinter printer({
      DevicePrintModeStore? modes,
      DeviceUsbPrinter? usb,
      DeviceSystemPrinter? dialog,
    }) => devicePrinter(
      business: _business,
      store: null,
      usbStore: _Usb(usb),
      systemStore: _System(dialog),
      modeStore: modes,
      tenantId: _tenant,
    );

    test('a device that never chose prints as it always did', () {
      expect(printer(usb: _usbPrinter).configuration?.endpoint.isUsb, isTrue);
      expect(printer().configuration, _business.configuration);
    });

    test('the network printer switched on wins over a USB printer kept '
        'from before', () {
      expect(
        printer(
          modes: _Modes(DevicePrintMode.network),
          usb: _usbPrinter,
        ).configuration,
        _business.configuration,
      );
    });

    test('a kind switched on with nothing chosen prints nowhere, never on '
        'the network printer', () {
      for (final mode in <DevicePrintMode>[
        DevicePrintMode.usb,
        DevicePrintMode.bluetooth,
        DevicePrintMode.dialog,
        DevicePrintMode.off,
      ]) {
        expect(printer(modes: _Modes(mode)).canPrint, isFalse, reason: '$mode');
      }
    });

    test('the print dialog switched on prints through the window', () {
      expect(
        printer(
          modes: _Modes(DevicePrintMode.dialog),
          usb: _usbPrinter,
          dialog: const DeviceSystemPrinter(
            paperWidth: PrinterPaperWidth.columns32,
          ),
        ).configuration?.transport,
        PrinterTransportKind.system,
      );
    });

    test('a choice it cannot read prints nowhere rather than guess', () {
      expect(printer(modes: _Modes.unreadable()).canPrint, isFalse);
    });

    test('the business printer is not read when another kind is on', () async {
      var asked = 0;
      final chosen = await devicePrinterLoading(
        business: () async {
          asked++;
          return _business;
        },
        store: null,
        usbStore: _Usb(_usbPrinter),
        modeStore: _Modes(DevicePrintMode.usb),
        tenantId: _tenant,
      );
      expect(asked, 0);
      expect(chosen.configuration?.endpoint.isUsb, isTrue);
    });
  });

  group('the kind kept on this device', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('print-mode-');
      Hive.init(directory.path);
    });

    tearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test('per business, and refuses a record it cannot trust', () async {
      final store = (await openDevicePrintModeStore())!;
      expect(store.read(_tenant), isNull);

      await store.save(_tenant, DevicePrintMode.dialog);
      expect(store.read(_tenant), DevicePrintMode.dialog);
      expect(store.read('tenant-b'), isNull);

      await Hive.box<dynamic>(
        HiveDevicePrintModeStore.boxName,
      ).put(_tenant, <String, Object?>{'schemaVersion': 1, 'mode': 'fax'});
      expect(() => store.read(_tenant), throwsFormatException);
    });
  });
}

final class _Modes implements DevicePrintModeStore {
  _Modes(this.mode) : unreadable = false;
  _Modes.unreadable() : mode = null, unreadable = true;

  DevicePrintMode? mode;
  final bool unreadable;

  @override
  DevicePrintMode? read(String tenantId) {
    if (unreadable) throw const FormatException('unreadable');
    return mode;
  }

  @override
  Future<void> save(String tenantId, DevicePrintMode mode) async =>
      this.mode = mode;
}

final class _Usb implements DeviceUsbPrinterStore {
  _Usb(this.printer);

  DeviceUsbPrinter? printer;

  @override
  DeviceUsbPrinter? read(String tenantId) => printer;

  @override
  Future<void> save(String tenantId, DeviceUsbPrinter printer) async =>
      this.printer = printer;

  @override
  Future<void> forget(String tenantId) async => printer = null;
}

final class _System implements DeviceSystemPrinterStore {
  _System(this.printer);

  DeviceSystemPrinter? printer;

  @override
  DeviceSystemPrinter? read(String tenantId) => printer;

  @override
  Future<void> save(String tenantId, DeviceSystemPrinter printer) async =>
      this.printer = printer;

  @override
  Future<void> forget(String tenantId) async => printer = null;
}
