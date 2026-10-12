import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/ui/status.dart';

const String _tenant = 'tenant-a';

DeviceUsbPrinter _printer({String key = '04B8:0E15:J5A0123'}) =>
    DeviceUsbPrinter(
      key: key,
      name: 'EPSON TM-T20II',
      paperWidth: PrinterPaperWidth.columns48,
      hasCutter: true,
    );

void main() {
  group('a USB printer endpoint', () {
    test('is keyed by its model numbers and serial, in upper-case hex', () {
      expect(
        PrinterEndpoint.usbKey(
          vendorId: 0x04b8,
          productId: 0x0e15,
          serialNumber: 'J5A0123',
        ),
        '04B8:0E15:J5A0123',
      );
      // No serial number is the model alone; one the key cannot carry is
      // dropped rather than refused - the printer is still the printer.
      expect(PrinterEndpoint.usbKey(vendorId: 1, productId: 2), '0001:0002');
      expect(
        PrinterEndpoint.usbKey(
          vendorId: 1,
          productId: 2,
          serialNumber: 'has space',
        ),
        '0001:0002',
      );
    });

    test('refuses anything that is not a key', () {
      for (final bad in <String>[
        '',
        '04b8:0e15',
        '4B8:0E15',
        '04B8',
        '192.168.1.50',
        'EC:8E:77:5B:A1:4D',
        '04B8:0E15:has space',
      ]) {
        expect(
          () => PrinterEndpoint.usb(bad),
          throwsArgumentError,
          reason: bad,
        );
      }
    });

    test('is its own kind, equal by key, and says it is USB', () {
      final endpoint = PrinterEndpoint.usb('04B8:0E15');
      expect(endpoint.isUsb, isTrue);
      expect(endpoint.isBluetooth, isFalse);
      expect(endpoint.port, PrinterEndpoint.usbPort);
      expect(endpoint, PrinterEndpoint.usb('04B8:0E15'));
      expect(endpoint, isNot(PrinterEndpoint.usb('04B8:0E15:J5A0123')));
      expect(endpoint.toString(), 'USB 04B8:0E15');
    });
  });

  group('the USB printer record', () {
    test('round-trips, and builds a USB configuration', () {
      final printer = _printer();
      expect(DeviceUsbPrinter.fromMap(printer.toMap()), printer);
      final configuration = printer.configuration;
      expect(configuration.transport, PrinterTransportKind.usb);
      expect(configuration.endpoint, printer.endpoint);
      expect(configuration.paperWidth, PrinterPaperWidth.columns48);
      expect(configuration.hasCutter, isTrue);
    });

    test('refuses what it cannot trust rather than guessing', () {
      final good = _printer().toMap();
      for (final broken in <Map<String, Object?>>[
        {...good, 'schemaVersion': 2},
        {...good, 'key': 'not a key'},
        {...good, 'name': 7},
        {...good, 'paperWidth': 'columns_99'},
        {...good, 'hasCutter': 'yes'},
      ]) {
        expect(
          () => DeviceUsbPrinter.fromMap(broken),
          throwsFormatException,
          reason: '$broken',
        );
      }
    });

    test('is never a business setting', () {
      // A USB printer is cabled to one computer; a business document naming
      // one would point every other till at a device it cannot reach.
      expect(
        () => TenantPrinterConfiguration.transportToWire(
          PrinterTransportKind.usb,
        ),
        throwsArgumentError,
      );
      expect(
        () => TenantPrinterConfiguration(
          transport: PrinterTransportKind.usb,
          endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
          paperWidth: PrinterPaperWidth.columns48,
          hasCutter: true,
        ),
        throwsFormatException,
      );
    });

    test('a device names itself as a person would', () {
      expect(
        const UsbPrinterDevice(
          vendorId: 0x04B8,
          productId: 0x0E15,
          productName: 'TM-T20II',
          manufacturerName: 'EPSON',
        ).label,
        'EPSON TM-T20II',
      );
      expect(
        const UsbPrinterDevice(
          vendorId: 0x0416,
          productId: 0x5011,
          productName: 'POS58 Printer',
          manufacturerName: 'pos58',
        ).label,
        'POS58 Printer',
      );
      expect(
        const UsbPrinterDevice(vendorId: 0x0416, productId: 0x5011).label,
        'USB printer 0416:5011',
      );
    });
  });

  group('the USB printer store', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('usb-printer-');
      Hive.init(directory.path);
    });

    tearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test('keeps one printer per business, and forgets it', () async {
      final store = (await openDeviceUsbPrinterStore())!;
      expect(store.read(_tenant), isNull);

      await store.save(_tenant, _printer());
      expect(store.read(_tenant), _printer());
      expect(store.read('tenant-b'), isNull);

      await Hive.close();
      final reopened = (await openDeviceUsbPrinterStore())!;
      expect(reopened.read(_tenant), _printer());

      await reopened.forget(_tenant);
      expect(reopened.read(_tenant), isNull);
    });
  });

  group('where this device prints', () {
    final business = TenantConfiguredPrinter.configured(
      TenantPrinterConfiguration(
        transport: PrinterTransportKind.directTcp,
        endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
        paperWidth: PrinterPaperWidth.columns48,
        hasCutter: true,
      ),
    );

    test('a USB printer chosen in this browser takes its receipts', () {
      final store = _MemoryUsbStore()..printers[_tenant] = _printer();
      final printer = devicePrinter(
        business: business,
        store: null,
        usbStore: store,
        tenantId: _tenant,
      );
      expect(printer.configuration?.endpoint, _printer().endpoint);
      // Another business in the same browser keeps its own answer.
      expect(
        devicePrinter(
          business: business,
          store: null,
          usbStore: store,
          tenantId: 'tenant-b',
        ),
        business,
      );
    });

    test('a record that cannot be read prints nowhere rather than guess', () {
      final printer = devicePrinter(
        business: business,
        store: null,
        usbStore: _MemoryUsbStore(unreadable: true),
        tenantId: _tenant,
      );
      expect(printer.canPrint, isFalse);
    });

    test('the business printer is not even read when USB answers', () async {
      var asked = 0;
      final printer = await devicePrinterLoading(
        business: () async {
          asked++;
          return business;
        },
        store: null,
        usbStore: _MemoryUsbStore()..printers[_tenant] = _printer(),
        tenantId: _tenant,
      );
      expect(asked, 0);
      expect(printer.configuration?.transport, PrinterTransportKind.usb);
    });
  });

  group('a USB receipt in the queue', () {
    test('keeps its kind, so a retry goes back to the USB printer', () {
      final stored = <String, Object?>{
        'schemaVersion': 1,
        'tenantId': _tenant,
        'receiptNumber': 'CT-A7F-20261010-0042',
        'host': '04B8:0E15:J5A0123',
        'port': PrinterEndpoint.usbPort,
        'kind': 'usb',
        'bytes': const <int>[27, 64],
        'state': PrintJobState.queued.name,
        'attemptCount': 0,
        'attentionReason': null,
        'createdAtMs': DateTime.utc(2026, 10, 10).millisecondsSinceEpoch,
        'updatedAtMs': DateTime.utc(2026, 10, 10).millisecondsSinceEpoch,
      };
      final record = PrintJobRecord.fromMap(stored);
      expect(record.kind, PrinterEndpointKind.usb);
      expect(record.endpoint, PrinterEndpoint.usb('04B8:0E15:J5A0123'));
      // And it is written back as USB, never as a network host.
      expect(record.toMap()['kind'], 'usb');
    });

    test('a key in the network field is refused, never dialled', () {
      final stored = <String, Object?>{
        'schemaVersion': 1,
        'tenantId': _tenant,
        'receiptNumber': 'CT-A7F-20261010-0042',
        'host': '04B8:0E15:J5A0123',
        'port': 9100,
        'bytes': const <int>[27, 64],
        'state': PrintJobState.queued.name,
        'attemptCount': 0,
        'attentionReason': null,
        'createdAtMs': 0,
        'updatedAtMs': 0,
      };
      expect(() => PrintJobRecord.fromMap(stored).endpoint, throwsA(anything));
    });
  });

  group('the routed transport', () {
    test('sends a USB endpoint down the USB link', () async {
      final usb = _RecordingTransport();
      final transport = RoutedPrinterTransport(
        network: _RecordingTransport(),
        bluetooth: _RecordingTransport(),
        usb: usb,
      );
      final endpoint = PrinterEndpoint.usb('04B8:0E15');
      await transport.send(endpoint, const <int>[1, 2, 3]);
      expect(usb.sent, <PrinterEndpoint>[endpoint]);
    });

    test('refuses a USB endpoint where there is no USB link', () async {
      final transport = RoutedPrinterTransport(
        network: _RecordingTransport(),
        bluetooth: _RecordingTransport(),
      );
      await expectLater(
        transport.probe(PrinterEndpoint.usb('04B8:0E15')),
        throwsA(
          const PrinterTransportException(PrinterTransportCode.unsupported),
        ),
      );
    });
  });

  group('what a shopkeeper is told', () {
    test('names the cable, the power and the Windows driver', () {
      expect(
        PrinterFailureNotice.of(PrinterTransportCode.usbNotFound).message,
        contains('cable'),
      );
      final busy = PrinterFailureNotice.of(PrinterTransportCode.usbBusy);
      expect(busy.message, contains('WinUSB'));
      expect(busy.status, AppStatus.problem);
      expect(
        PrinterFailureNotice.isRetryable(PrinterTransportCode.usbBusy),
        isTrue,
      );
    });
  });
}

final class _MemoryUsbStore implements DeviceUsbPrinterStore {
  _MemoryUsbStore({this.unreadable = false});

  final bool unreadable;
  final Map<String, DeviceUsbPrinter> printers = <String, DeviceUsbPrinter>{};

  @override
  DeviceUsbPrinter? read(String tenantId) {
    if (unreadable) throw const FormatException('unreadable');
    return printers[tenantId];
  }

  @override
  Future<void> save(String tenantId, DeviceUsbPrinter printer) async =>
      printers[tenantId] = printer;

  @override
  Future<void> forget(String tenantId) async => printers.remove(tenantId);
}

final class _RecordingTransport implements PrinterTransport {
  final List<PrinterEndpoint> sent = <PrinterEndpoint>[];

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.none,
    endpointIsPrinter: false,
    label: 'recording',
  );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async => sent.add(endpoint);

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async =>
      sent.add(endpoint);

  @override
  Future<void> dispose() async {}
}
