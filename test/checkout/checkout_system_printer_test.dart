import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/reports/render/report_fonts.dart';
import 'package:uzapay_pos/tenancy/tenant_session.dart';
import 'package:uzapay_pos/tenancy/tenant_types.dart';
import 'package:uzapay_pos/ui/status.dart';

const String _tenant = 'tenant-a';

/// The smallest thing [SystemPrintTransport] takes for a PDF.
final Uint8List _pdf = Uint8List.fromList('%PDF-1.4 receipt'.codeUnits);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the print-window endpoint', () {
    test('is one endpoint, of its own kind, named as what it is', () {
      const endpoint = PrinterEndpoint.system();
      expect(endpoint.isSystem, isTrue);
      expect(endpoint.isUsb, isFalse);
      expect(endpoint, const PrinterEndpoint.system());
      expect(endpoint.toString(), 'Print dialog');
    });

    test('is never a business setting', () {
      // Which printers a print window offers is a fact about one device.
      expect(
        () => TenantPrinterConfiguration.transportToWire(
          PrinterTransportKind.system,
        ),
        throwsArgumentError,
      );
      expect(
        () => TenantPrinterConfiguration(
          transport: PrinterTransportKind.system,
          endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
          paperWidth: PrinterPaperWidth.columns48,
          hasCutter: false,
        ),
        throwsFormatException,
      );
      expect(
        () => TenantPrinterConfiguration(
          transport: PrinterTransportKind.directTcp,
          endpoint: const PrinterEndpoint.system(),
          paperWidth: PrinterPaperWidth.columns48,
          hasCutter: false,
        ),
        throwsFormatException,
      );
    });

    test('a queued job keeps it, and refuses a host it never names', () {
      Map<String, Object?> stored({String host = 'print-dialog'}) =>
          <String, Object?>{
            'schemaVersion': 1,
            'tenantId': _tenant,
            'receiptNumber': 'CT-A7F-20261010-0042',
            'host': host,
            'port': PrinterEndpoint.systemPort,
            'kind': 'system',
            'bytes': _pdf.toList(),
            'state': PrintJobState.queued.name,
            'attemptCount': 0,
            'attentionReason': null,
            'createdAtMs': 0,
            'updatedAtMs': 0,
          };
      final record = PrintJobRecord.fromMap(stored());
      expect(record.endpoint, const PrinterEndpoint.system());
      expect(record.toMap()['kind'], 'system');
      expect(
        () => PrintJobRecord.fromMap(stored(host: '192.168.1.50')),
        throwsA(isA<PrintJobException>()),
      );
    });

    test(
      'is routed to the print window, and refused where there is none',
      () async {
        final window = _RecordingTransport();
        await RoutedPrinterTransport(
          network: _RecordingTransport(),
          bluetooth: _RecordingTransport(),
          system: window,
        ).send(const PrinterEndpoint.system(), _pdf);
        expect(window.sent, hasLength(1));

        await expectLater(
          RoutedPrinterTransport(
            network: _RecordingTransport(),
            bluetooth: _RecordingTransport(),
          ).send(const PrinterEndpoint.system(), _pdf),
          throwsA(
            const PrinterTransportException(PrinterTransportCode.unsupported),
          ),
        );
      },
    );
  });

  group('the print-window transport', () {
    test('hands the window the PDF itself', () async {
      final shown = <Uint8List>[];
      await SystemPrintTransport(
        present: (pdf) async {
          shown.add(pdf);
          return true;
        },
      ).send(const PrinterEndpoint.system(), _pdf);

      expect(shown.single, _pdf);
    });

    test('a window closed without printing can be sent again', () async {
      await expectLater(
        SystemPrintTransport(
          present: (_) async => false,
        ).send(const PrinterEndpoint.system(), _pdf),
        throwsA(
          const PrinterTransportException(
            PrinterTransportCode.printDialogClosed,
          ),
        ),
      );
      expect(
        PrinterFailureNotice.isRetryable(
          PrinterTransportCode.printDialogClosed,
        ),
        isTrue,
      );
    });

    test('a window that will not open, or bytes that are not a page, '
        'fail as such', () async {
      await expectLater(
        SystemPrintTransport(
          present: (_) async => throw StateError('no window'),
        ).send(const PrinterEndpoint.system(), _pdf),
        throwsA(
          const PrinterTransportException(
            PrinterTransportCode.printDialogFailed,
          ),
        ),
      );
      // ESC/POS is never shown to a print window.
      var opened = false;
      await expectLater(
        SystemPrintTransport(
          present: (_) async => opened = true,
        ).send(const PrinterEndpoint.system(), const <int>[0x1B, 0x40]),
        throwsA(
          const PrinterTransportException(
            PrinterTransportCode.printDialogFailed,
          ),
        ),
      );
      expect(opened, isFalse);
    });

    test('a device with no print window cannot be chosen', () async {
      await expectLater(
        SystemPrintTransport(
          available: () async => false,
        ).probe(const PrinterEndpoint.system()),
        throwsA(
          const PrinterTransportException(PrinterTransportCode.unsupported),
        ),
      );
      await SystemPrintTransport(
        available: () async => true,
      ).probe(const PrinterEndpoint.system());
    });

    test('takes nothing but its own endpoint', () async {
      await expectLater(
        const SystemPrintTransport().send(
          PrinterEndpoint(host: '192.168.1.50', port: 9100),
          _pdf,
        ),
        throwsArgumentError,
      );
    });
  });

  group('the print-window choice', () {
    test('round-trips, and builds a print-window configuration', () {
      const printer = DeviceSystemPrinter(
        paperWidth: PrinterPaperWidth.columns32,
      );
      expect(DeviceSystemPrinter.fromMap(printer.toMap()), printer);
      expect(printer.configuration.transport, PrinterTransportKind.system);
      expect(printer.configuration.endpoint, const PrinterEndpoint.system());
      expect(printer.configuration.paperWidth, PrinterPaperWidth.columns32);
      for (final broken in <Object?>[
        null,
        <String, Object?>{'schemaVersion': 2, 'paperWidth': 'columns_32'},
        <String, Object?>{'schemaVersion': 1, 'paperWidth': 'columns_99'},
      ]) {
        expect(
          () => DeviceSystemPrinter.fromMap(broken),
          throwsFormatException,
          reason: '$broken',
        );
      }
    });

    group('kept on this device', () {
      late Directory directory;

      setUp(() async {
        directory = await Directory.systemTemp.createTemp('system-printer-');
        Hive.init(directory.path);
      });

      tearDown(() async {
        await Hive.close();
        await directory.delete(recursive: true);
      });

      test('per business, and forgotten', () async {
        final store = (await openDeviceSystemPrinterStore())!;
        const printer = DeviceSystemPrinter(
          paperWidth: PrinterPaperWidth.columns48,
        );
        await store.save(_tenant, printer);
        expect(store.read(_tenant), printer);
        expect(store.read('tenant-b'), isNull);

        await store.forget(_tenant);
        expect(store.read(_tenant), isNull);
      });
    });

    test('takes this device’s receipts ahead of the business printer, '
        'and behind a USB printer chosen here', () {
      final business = TenantConfiguredPrinter.configured(
        TenantPrinterConfiguration(
          transport: PrinterTransportKind.directTcp,
          endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
          paperWidth: PrinterPaperWidth.columns48,
          hasCutter: true,
        ),
      );
      final system = _MemorySystemStore()
        ..printers[_tenant] = const DeviceSystemPrinter(
          paperWidth: PrinterPaperWidth.columns32,
        );

      expect(
        devicePrinter(
          business: business,
          store: null,
          systemStore: system,
          tenantId: _tenant,
        ).configuration?.transport,
        PrinterTransportKind.system,
      );
      expect(
        devicePrinter(
          business: business,
          store: null,
          usbStore: _MemoryUsbStore()
            ..printers[_tenant] = DeviceUsbPrinter(
              key: '04B8:0E15',
              name: 'EPSON TM-T20II',
              paperWidth: PrinterPaperWidth.columns48,
              hasCutter: true,
            ),
          systemStore: system,
          tenantId: _tenant,
        ).configuration?.transport,
        PrinterTransportKind.usb,
      );
      // A choice it cannot read prints nowhere rather than guess.
      expect(
        devicePrinter(
          business: business,
          store: null,
          systemStore: _MemorySystemStore(unreadable: true),
          tenantId: _tenant,
        ).canPrint,
        isFalse,
      );
    });
  });

  group('a receipt for the print window', () {
    late Directory directory;
    late HivePrintJobQueue queue;
    late CapabilityProfile profile;

    setUpAll(() async {
      profile = await CapabilityProfile.load();
    });

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('system-dispatch-');
      Hive.init(directory.path);
      queue = HivePrintJobQueue.fromBox(
        await Hive.openBox<dynamic>(HivePrintJobQueue.boxName),
      );
    });

    tearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test('is queued as a page and sent to the window', () async {
      final window = _RecordingTransport();
      final result =
          await CheckoutPrintDispatcher(
            queue: queue,
            transport: RoutedPrinterTransport(
              network: _RecordingTransport(),
              bluetooth: _RecordingTransport(),
              system: window,
            ),
            profile: profile,
            pdfFonts: () async => TenantReportFonts.standard(),
          ).dispatch(
            _sale(),
            printer: TenantConfiguredPrinter.configured(
              const DeviceSystemPrinter(
                paperWidth: PrinterPaperWidth.columns48,
              ).configuration,
            ),
            businessName: 'Kahawa Duka',
          );

      expect(result.outcome, CheckoutPrintOutcome.sent);
      expect(result.job!.endpoint, const PrinterEndpoint.system());
      expect(SystemPrintTransport.isPdf(result.job!.bytes), isTrue);
      expect(SystemPrintTransport.isPdf(window.sent.single), isTrue);
    });

    test('while every other printer still gets ESC/POS', () async {
      final network = _RecordingTransport();
      final result =
          await CheckoutPrintDispatcher(
            queue: queue,
            transport: RoutedPrinterTransport(
              network: network,
              bluetooth: _RecordingTransport(),
            ),
            profile: profile,
            pdfFonts: () async => fail('a network receipt parsed a font'),
          ).dispatch(
            _sale(),
            printer: TenantConfiguredPrinter.configured(
              TenantPrinterConfiguration(
                transport: PrinterTransportKind.directTcp,
                endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
                paperWidth: PrinterPaperWidth.columns48,
                hasCutter: true,
              ),
            ),
          );

      expect(result.outcome, CheckoutPrintOutcome.sent);
      expect(SystemPrintTransport.isPdf(network.sent.single), isFalse);
      // ESC @, the reset every ESC/POS receipt begins with.
      expect(network.sent.single.take(2), <int>[0x1B, 0x40]);
    });
  });

  group('what a shopkeeper is told', () {
    test('a closed window is information, a window that will not open is '
        'a problem', () {
      expect(
        PrinterFailureNotice.of(PrinterTransportCode.printDialogClosed).status,
        AppStatus.info,
      );
      expect(
        PrinterFailureNotice.of(PrinterTransportCode.printDialogFailed).status,
        AppStatus.problem,
      );
      // A browser's answer for a network printer now names the print dialog.
      expect(
        PrinterFailureNotice.of(PrinterTransportCode.unsupported).message,
        contains('print dialog'),
      );
    });
  });
}

final class _RecordingTransport implements PrinterTransport {
  final List<List<int>> sent = <List<int>>[];

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.none,
    endpointIsPrinter: false,
    label: 'recording',
  );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async {}

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async =>
      sent.add(bytes);

  @override
  Future<void> dispose() async {}
}

final class _MemorySystemStore implements DeviceSystemPrinterStore {
  _MemorySystemStore({this.unreadable = false});

  final bool unreadable;
  final Map<String, DeviceSystemPrinter> printers =
      <String, DeviceSystemPrinter>{};

  @override
  DeviceSystemPrinter? read(String tenantId) {
    if (unreadable) throw const FormatException('unreadable');
    return printers[tenantId];
  }

  @override
  Future<void> save(String tenantId, DeviceSystemPrinter printer) async =>
      printers[tenantId] = printer;

  @override
  Future<void> forget(String tenantId) async => printers.remove(tenantId);
}

final class _MemoryUsbStore implements DeviceUsbPrinterStore {
  final Map<String, DeviceUsbPrinter> printers = <String, DeviceUsbPrinter>{};

  @override
  DeviceUsbPrinter? read(String tenantId) => printers[tenantId];

  @override
  Future<void> save(String tenantId, DeviceUsbPrinter printer) async =>
      printers[tenantId] = printer;

  @override
  Future<void> forget(String tenantId) async => printers.remove(tenantId);
}

CheckoutSalePayload _sale() {
  const deviceId = 'dev-0123456789abcdef0123456789abcdef';
  final payload = <String, Object?>{
    'schemaVersion': checkoutSalePayloadSchemaVersion,
    'checkoutId': 'checkout-a',
    'tenantId': _tenant,
    'soldById': 'user-a',
    'currency': 'KES',
    'businessDate': '2026-10-10',
    'createdAtMs': DateTime.utc(2026, 10, 10, 8).millisecondsSinceEpoch,
    'shiftId': 'shift-a',
    'deviceId': deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: deviceId,
      businessDate: '2026-10-10',
      sequence: 42,
    ),
    'receiptSequence': 42,
    'tender': 'cash',
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-a',
        'name': 'Maize flour 2kg',
        'quantity': 2,
        'unitPriceMinor': 13550,
      },
    ],
    'subtotalMinor': 27100,
    'discountMinor': 0,
    'totalMinor': 27100,
  };
  return CheckoutSalePayload.fromLocalPayload(
    session: TenantSession.active(
      uid: 'user-a',
      tenantId: _tenant,
      role: TenantRole.cashier,
    ),
    checkoutId: 'checkout-a',
    payload: payload,
    payloadHash: checkoutPayloadHash(payload),
  );
}
