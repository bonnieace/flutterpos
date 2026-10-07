import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart'
    show CapabilityProfile;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/checkout/checkout_print_transport_bluetooth.dart';
import 'package:uzapay_pos/tenancy/tenant_session.dart';
import 'package:uzapay_pos/tenancy/tenant_types.dart';
import 'package:uzapay_pos/ui/status.dart';

const String _receipt = 'CT-A7F-20260729-0042';
const String _tenant = 'tenant-a';
const List<int> _payload = <int>[27, 64, 72, 105, 10];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a Bluetooth endpoint', () {
    test('is stored upper case, so one printer is one endpoint', () {
      final lower = PrinterEndpoint.bluetooth('ec:8e:77:5b:a1:4d');
      final upper = PrinterEndpoint.bluetooth('EC:8E:77:5B:A1:4D');

      expect(lower, upper);
      expect(lower.host, 'EC:8E:77:5B:A1:4D');
      expect(lower.port, PrinterEndpoint.bluetoothPort);
      expect(lower.isBluetooth, isTrue);
      expect(lower.toString(), 'EC:8E:77:5B:A1:4D');
    });

    test('refuses anything that is not a device address', () {
      for (final address in <String>[
        '',
        'EC:8E:77:5B:A1',
        'EC-8E-77-5B-A1-4D',
        'EC:8E:77:5B:A1:4D:00',
        'GG:8E:77:5B:A1:4D',
        ' EC:8E:77:5B:A1:4D',
        '192.168.1.50',
      ]) {
        expect(
          () => PrinterEndpoint.bluetooth(address),
          throwsArgumentError,
          reason: address,
        );
      }
    });

    test('is never equal to a network endpoint', () {
      expect(
        PrinterEndpoint.bluetooth('EC:8E:77:5B:A1:4D'),
        isNot(PrinterEndpoint(host: 'printer', port: 9100)),
      );
      expect(
        PrinterEndpoint(host: 'printer', port: 9100).isBluetooth,
        isFalse,
      );
    });
  });

  group('the routed transport', () {
    test('sends each endpoint down the link it names', () async {
      final network = _RecordingTransport();
      final bluetooth = _RecordingTransport();
      final routed = RoutedPrinterTransport(
        network: network,
        bluetooth: bluetooth,
      );
      final tcp = PrinterEndpoint(host: '192.168.1.50', port: 9100);
      final paired = PrinterEndpoint.bluetooth('EC:8E:77:5B:A1:4D');

      await routed.send(tcp, _payload);
      await routed.send(paired, _payload);
      await routed.probe(paired);

      expect(network.sends.single, tcp);
      expect(bluetooth.sends.single, paired);
      expect(bluetooth.probes.single, paired);
      expect(network.probes, isEmpty);
    });
  });

  group('a Bluetooth configuration', () {
    test('needs a Bluetooth address, and only it may carry one', () {
      expect(
        () => TenantPrinterConfiguration(
          transport: PrinterTransportKind.bluetooth,
          endpoint: PrinterEndpoint(host: 'printer', port: 9100),
          paperWidth: PrinterPaperWidth.columns32,
          hasCutter: false,
        ),
        throwsFormatException,
      );
      expect(
        () => TenantPrinterConfiguration(
          transport: PrinterTransportKind.directTcp,
          endpoint: PrinterEndpoint.bluetooth('EC:8E:77:5B:A1:4D'),
          paperWidth: PrinterPaperWidth.columns32,
          hasCutter: false,
        ),
        throwsFormatException,
      );
    });

    test('is never written to the business document', () {
      // A Bluetooth printer is paired with one phone; a business document
      // naming one would point every other till at a device it cannot reach.
      expect(
        () => TenantPrinterConfiguration.transportToWire(
          PrinterTransportKind.bluetooth,
        ),
        throwsArgumentError,
      );
      expect(
        () => TenantPrinterConfiguration.fromMap(<String, Object?>{
          'transport': 'bluetooth',
          'host': 'EC:8E:77:5B:A1:4D',
          'port': 0,
          'paperWidth': 'columns_32',
          'hasCutter': false,
        }),
        throwsFormatException,
      );
    });
  });

  group('the device printer record', () {
    test('round-trips through its map', () {
      final printer = _chosen();

      expect(DeviceBluetoothPrinter.fromMap(printer.toMap()), printer);
      expect(printer.configuration.transport, PrinterTransportKind.bluetooth);
      expect(printer.configuration.endpoint, printer.endpoint);
      expect(printer.configuration.paperWidth, PrinterPaperWidth.columns32);
    });

    test('refuses a record it cannot trust rather than guessing', () {
      final good = _chosen().toMap();
      for (final broken in <Map<String, Object?>>[
        <String, Object?>{...good, 'schemaVersion': 2},
        <String, Object?>{...good, 'address': '192.168.1.50'},
        <String, Object?>{...good, 'name': null},
        <String, Object?>{...good, 'paperWidth': 'columns_40'},
        <String, Object?>{...good, 'hasCutter': 'yes'},
      ]) {
        expect(
          () => DeviceBluetoothPrinter.fromMap(broken),
          throwsFormatException,
          reason: '$broken',
        );
      }
      expect(() => DeviceBluetoothPrinter.fromMap('x'), throwsFormatException);
    });
  });

  group('with Hive', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('bluetooth-printer-');
      Hive.init(directory.path);
    });

    tearDown(() async {
      await Hive.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('the store keeps one printer per business on this device', () async {
      final store = await HiveDeviceBluetoothPrinterStore.open();
      final printer = _chosen();

      expect(store.read(_tenant), isNull);
      await store.save(_tenant, printer);

      expect(store.read(_tenant), printer);
      expect(store.read('tenant-b'), isNull);

      await store.forget(_tenant);
      expect(store.read(_tenant), isNull);
    });

    // **A box that will not open is a choice that cannot be read**, and the
    // receipt is refused rather than sent to the network printer at another
    // counter. Forgetting it there puts that business right.
    test('a choice that will not open refuses until it is made again', () async {
      final business = TenantConfiguredPrinter.configured(_networkPrinter());
      await (await HiveDeviceBluetoothPrinterStore.open()).save(
        _tenant,
        _chosen(),
      );
      await Hive.close();
      Hive.init(directory.path);
      final errors = <Object>[];

      final store = await openDeviceBluetoothPrinterStore(
        hive: _FailingHive(Hive),
        onError: (error, _) => errors.add(error),
      );

      expect(errors, hasLength(1));
      expect(store, isA<UnopenedDeviceBluetoothPrinterStore>());
      for (final tenant in <String>[_tenant, 'tenant-b']) {
        expect(
          devicePrinter(business: business, store: store, tenantId: tenant)
              .state,
          TenantPrinterConfigurationState.malformed,
        );
      }

      await store!.forget(_tenant);
      expect(
        devicePrinter(business: business, store: store, tenantId: _tenant),
        same(business),
      );
      expect(
        devicePrinter(business: business, store: store, tenantId: 'tenant-b')
            .state,
        TenantPrinterConfigurationState.malformed,
      );

      // After a restart the box opens, and still knows it was started again:
      // the business put right is on the network printer, the other is not
      // quietly sent there.
      await Hive.close();
      Hive.init(directory.path);
      final reopened = await HiveDeviceBluetoothPrinterStore.open();
      expect(
        devicePrinter(business: business, store: reopened, tenantId: _tenant),
        same(business),
      );
      expect(
        devicePrinter(business: business, store: reopened, tenantId: 'tenant-b')
            .state,
        TenantPrinterConfigurationState.malformed,
      );
      await reopened.save('tenant-b', _chosen());
      expect(reopened.read('tenant-b'), _chosen());
    });

    test('a device that never chose one stays on the network printer', () async {
      final store = await openDeviceBluetoothPrinterStore(
        hive: _FailingHive(Hive),
      );

      expect(store, isNull);
    });

    test('a Bluetooth job keeps its link through the durable queue', () async {
      final box = await Hive.openBox<dynamic>(HivePrintJobQueue.boxName);
      final queue = HivePrintJobQueue.fromBox(box);
      final paired = PrinterEndpoint.bluetooth('EC:8E:77:5B:A1:4D');

      await queue.enqueue(
        tenantId: _tenant,
        receiptNumber: _receipt,
        endpoint: paired,
        bytes: _payload,
      );

      final stored = Map<Object?, Object?>.from(box.get(_receipt) as Map);
      expect(stored['kind'], 'bluetooth');
      expect(queue.read(_receipt)!.endpoint, paired);

      final transport = _RecordingTransport();
      final ran = await queue.run(_receipt, transport: transport);
      expect(ran.state, PrintJobState.printed);
      expect(transport.sends.single, paired);
    });

    test('a network job is stored exactly as it was before Bluetooth', () async {
      // No `kind` key: every record queued by an earlier build parses as it
      // did, and a network record written now reads the same to that build.
      final box = await Hive.openBox<dynamic>(HivePrintJobQueue.boxName);
      final queue = HivePrintJobQueue.fromBox(box);
      final tcp = PrinterEndpoint(host: '192.168.1.50', port: 9100);

      await queue.enqueue(
        tenantId: _tenant,
        receiptNumber: _receipt,
        endpoint: tcp,
        bytes: _payload,
      );

      final stored = Map<Object?, Object?>.from(box.get(_receipt) as Map);
      expect(stored.containsKey('kind'), isFalse);
      expect(queue.read(_receipt)!.endpoint, tcp);
    });

    test('an unknown link kind is malformed, never dialled', () async {
      final box = await Hive.openBox<dynamic>(HivePrintJobQueue.boxName);
      final queue = HivePrintJobQueue.fromBox(box);
      await queue.enqueue(
        tenantId: _tenant,
        receiptNumber: _receipt,
        endpoint: PrinterEndpoint.bluetooth('EC:8E:77:5B:A1:4D'),
        bytes: _payload,
      );
      final stored = Map<Object?, Object?>.from(box.get(_receipt) as Map);

      await box.put(_receipt, <Object?, Object?>{...stored, 'kind': 'infrared'});
      expect(
        () => queue.read(_receipt),
        throwsA(const PrintJobException('malformed_print_job')),
      );

      // A Bluetooth job that claims a port is as untrustworthy.
      await box.put(_receipt, <Object?, Object?>{...stored, 'port': 9100});
      expect(
        () => queue.read(_receipt),
        throwsA(const PrintJobException('malformed_print_job')),
      );
    });

    test(
      'a receipt for a device on Bluetooth is sent over Bluetooth',
      () async {
        // The whole of "it works the normal way": the dispatcher, the queue and
        // the job are unchanged, and the endpoint carries the decision.
        final box = await Hive.openBox<dynamic>(HivePrintJobQueue.boxName);
        final network = _RecordingTransport();
        final bluetooth = _RecordingTransport();
        final dispatcher = CheckoutPrintDispatcher(
          queue: HivePrintJobQueue.fromBox(box),
          transport: RoutedPrinterTransport(
            network: network,
            bluetooth: bluetooth,
          ),
          profile: await CapabilityProfile.load(),
        );
        final printer = devicePrinter(
          business: TenantConfiguredPrinter.configured(_networkPrinter()),
          store: _MemoryStore(<String, DeviceBluetoothPrinter>{
            _tenant: _chosen(),
          }),
          tenantId: _tenant,
        );

        final result = await dispatcher.dispatch(_sale(), printer: printer);

        expect(result.outcome, CheckoutPrintOutcome.sent);
        expect(bluetooth.sends.single, _chosen().endpoint);
        expect(network.sends, isEmpty);
      },
    );
  });

  group('where this device prints', () {
    final business = TenantConfiguredPrinter.configured(_networkPrinter());

    test('is the business printer when no Bluetooth one is chosen', () {
      expect(
        devicePrinter(
          business: business,
          store: _MemoryStore(<String, DeviceBluetoothPrinter>{}),
          tenantId: _tenant,
        ),
        same(business),
      );
      expect(
        devicePrinter(business: business, store: null, tenantId: _tenant),
        same(business),
      );
    });

    test('is the Bluetooth printer chosen here, for that business only', () {
      final store = _MemoryStore(<String, DeviceBluetoothPrinter>{
        _tenant: _chosen(),
      });

      final here = devicePrinter(
        business: business,
        store: store,
        tenantId: _tenant,
      );
      expect(here.canPrint, isTrue);
      expect(here.configuration, _chosen().configuration);

      expect(
        devicePrinter(business: business, store: store, tenantId: 'tenant-b'),
        same(business),
      );
    });

    test('reads the business printer only when it is the answer', () async {
      var reads = 0;
      Future<TenantConfiguredPrinter> load() async {
        reads += 1;
        return business;
      }

      final bluetooth = await devicePrinterLoading(
        business: load,
        store: _MemoryStore(<String, DeviceBluetoothPrinter>{
          _tenant: _chosen(),
        }),
        tenantId: _tenant,
      );
      expect(bluetooth.configuration, _chosen().configuration);
      expect(reads, 0);

      final network = await devicePrinterLoading(
        business: load,
        store: _MemoryStore(<String, DeviceBluetoothPrinter>{}),
        tenantId: _tenant,
      );
      expect(network, same(business));
      expect(reads, 1);
    });

    test(
      'refuses on an unreadable record rather than using the network one',
      () {
        // Falling back would put receipts on the wrong counter without a word.
        final printer = devicePrinter(
          business: business,
          store: _MemoryStore(<String, DeviceBluetoothPrinter>{}, broken: true),
          tenantId: _tenant,
        );

        expect(printer.state, TenantPrinterConfigurationState.malformed);
        expect(printer.canPrint, isFalse);
      },
    );
  });

  group('the Bluetooth failure sentences', () {
    test('each says what to do about the phone, not the network', () {
      for (final code in <String>[
        PrinterTransportCode.bluetoothOff,
        PrinterTransportCode.bluetoothPermissionDenied,
        PrinterTransportCode.bluetoothUnreachable,
      ]) {
        final notice = PrinterFailureNotice.of(code);
        expect(notice.status, AppStatus.problem, reason: code);
        expect(notice.message, isNot(contains('network')), reason: code);
        expect(PrinterFailureNotice.isRetryable(code), isTrue, reason: code);
      }
      expect(
        PrinterFailureNotice.of(PrinterTransportCode.bluetoothOff).message,
        contains('Bluetooth is off'),
      );
    });
  });

  group('the Android drain', () {
    test('holds the link longer for a longer payload, within bounds', () {
      final short = AndroidBluetoothPrinterTransport.drainTime(400);
      final logo = AndroidBluetoothPrinterTransport.drainTime(12000);

      expect(short, greaterThanOrEqualTo(const Duration(milliseconds: 250)));
      expect(logo, greaterThan(short));
      expect(
        AndroidBluetoothPrinterTransport.drainTime(10000000),
        const Duration(seconds: 6),
      );
    });
  });
}

DeviceBluetoothPrinter _chosen() => DeviceBluetoothPrinter(
  address: 'EC:8E:77:5B:A1:4D',
  name: 'MPT-II',
  paperWidth: PrinterPaperWidth.columns32,
  hasCutter: false,
);

TenantPrinterConfiguration _networkPrinter() => TenantPrinterConfiguration(
  transport: PrinterTransportKind.directTcp,
  endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
  paperWidth: PrinterPaperWidth.columns48,
  hasCutter: true,
);

/// Hive whose first [openBox] fails, as a box that cannot be opened does.
final class _FailingHive implements HiveInterface {
  _FailingHive(this._real);

  final HiveInterface _real;
  bool _failed = false;

  @override
  Future<Box<E>> openBox<E>(
    String name, {
    HiveCipher? encryptionCipher,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
    String? path,
    Uint8List? bytes,
    String? collection,
    List<int>? encryptionKey,
  }) async {
    if (!_failed) {
      _failed = true;
      throw const FileSystemException('box would not open');
    }
    return _real.openBox<E>(name);
  }

  @override
  Future<bool> boxExists(String name, {String? path}) =>
      _real.boxExists(name);

  @override
  Future<void> deleteBoxFromDisk(String name, {String? path}) =>
      _real.deleteBoxFromDisk(name);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _MemoryStore implements DeviceBluetoothPrinterStore {
  _MemoryStore(this._printers, {this.broken = false});

  final Map<String, DeviceBluetoothPrinter> _printers;
  final bool broken;

  @override
  DeviceBluetoothPrinter? read(String tenantId) {
    if (broken) throw const FormatException('broken');
    return _printers[tenantId];
  }

  @override
  Future<void> save(String tenantId, DeviceBluetoothPrinter printer) async =>
      _printers[tenantId] = printer;

  @override
  Future<void> forget(String tenantId) async => _printers.remove(tenantId);
}

final class _RecordingTransport implements PrinterTransport {
  final List<PrinterEndpoint> sends = <PrinterEndpoint>[];
  final List<PrinterEndpoint> probes = <PrinterEndpoint>[];

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.directTcp,
    endpointIsPrinter: true,
    label: 'Recording',
  );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async => probes.add(endpoint);

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async =>
      sends.add(endpoint);

  @override
  Future<void> dispose() async {}
}

CheckoutSalePayload _sale() {
  const deviceId = 'dev-0123456789abcdef0123456789abcdef';
  const subtotalMinor = 2 * 13550 + 13500;
  final payload = <String, Object?>{
    'schemaVersion': checkoutSalePayloadSchemaVersion,
    'checkoutId': 'checkout-a',
    'tenantId': 'tenant-a',
    'soldById': 'user-a',
    'currency': 'KES',
    'businessDate': '2026-07-29',
    'createdAtMs': DateTime.utc(2026, 7, 29, 8).millisecondsSinceEpoch,
    'shiftId': 'shift-a',
    'deviceId': deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: deviceId,
      businessDate: '2026-07-29',
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
      <String, Object?>{
        'productId': 'product-b',
        'name': 'Sugar 1kg',
        'quantity': 1,
        'unitPriceMinor': 13500,
      },
    ],
    'subtotalMinor': subtotalMinor,
    'discountMinor': 0,
    'totalMinor': subtotalMinor,
  };
  return CheckoutSalePayload.fromLocalPayload(
    session: TenantSession.active(
      uid: 'user-a',
      tenantId: 'tenant-a',
      role: TenantRole.cashier,
    ),
    checkoutId: 'checkout-a',
    payload: payload,
    payloadHash: checkoutPayloadHash(payload),
  );
}
