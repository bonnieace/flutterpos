/// Printing's two surfaces, in every state each one has.
///
/// **`CLAUDE.md` rule 5: a component missing a state is not done.** The printer
/// settings route has four — nothing configured, configured, unreadable, and
/// the read-only rendering a build with no writer and no transport gets — and
/// the queue has four of its own, including the one that matters most: a
/// receipt that did not come out, with the sentence explaining why.
///
/// **The queue is seeded through a real Hive box in `setUpAll`, not in a test
/// body.** `testWidgets` runs inside `FakeAsync`, where Hive's `put` awaits a
/// real file write that fake time never delivers, so a durable write inside a
/// capture would hang rather than fail. `setUpAll` is ordinary async and does
/// not have that problem — the same trap
/// `test/checkout/checkout_print_queue_panel_test.dart` documents, avoided a
/// different way because `screenshotCase` owns the pump.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uzapay_pos/ui/choice.dart';
import 'package:uzapay_pos/ui/tabs.dart';

import 'fakes.dart';
import 'harness.dart';

const String _host = '192.168.1.50';
const int _port = 9100;
const List<int> _payload = <int>[27, 64, 72, 105, 10];

/// The printer document, as `TenantPrinterConfiguration.toCacheEntry` writes it.
Map<String, Map<String, Object?>> _printer({
  String host = _host,
  Object? port = _port,
  String paperWidth = 'columns_32',
  bool hasCutter = false,
}) => <String, Map<String, Object?>>{
  'tenants/$seedTenantId/configuration/printer': <String, Object?>{
    'transport': 'direct_tcp',
    'host': host,
    'port': port,
    'paperWidth': paperWidth,
    'hasCutter': hasCutter,
  },
};

/// A transport that always refuses, so *Test this printer* renders its failure
/// rather than opening a socket from a screenshot run.
final class _RefusingTransport implements PrinterTransport {
  const _RefusingTransport();

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.directTcp,
    endpointIsPrinter: true,
    label: 'Direct network printing',
  );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async =>
      throw const PrinterTransportException(PrinterTransportCode.unreachable);

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async =>
      throw const PrinterTransportException(PrinterTransportCode.unreachable);

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory directory;
  late HivePrintJobQueue empty;
  late HivePrintJobQueue waiting;
  late HivePrintJobQueue unreadable;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('print-screens-');
    Hive.init(directory.path);

    empty = HivePrintJobQueue.fromBox(await Hive.openBox<dynamic>('empty'));

    // One receipt that failed against a printer that did not answer, and one
    // still waiting its turn: the two states a person acts on differently.
    waiting = HivePrintJobQueue.fromBox(await Hive.openBox<dynamic>('waiting'));
    await waiting.enqueue(
      tenantId: seedTenantId,
      receiptNumber: 'CT-A7F-20260818-0042',
      endpoint: PrinterEndpoint(host: _host, port: _port),
      bytes: _payload,
    );
    await waiting.run(
      'CT-A7F-20260818-0042',
      transport: const _RefusingTransport(),
    );
    await waiting.enqueue(
      tenantId: seedTenantId,
      receiptNumber: 'CT-A7F-20260818-0043',
      endpoint: PrinterEndpoint(host: _host, port: _port),
      bytes: _payload,
    );

    // A durable record this build cannot parse, beside one it can. The screen
    // must state both rather than render an empty queue — see
    // `HivePrintJobQueue.pending`.
    final corrupt = await Hive.openBox<dynamic>('unreadable');
    unreadable = HivePrintJobQueue.fromBox(corrupt);
    await unreadable.enqueue(
      tenantId: seedTenantId,
      receiptNumber: 'CT-A7F-20260818-0044',
      endpoint: PrinterEndpoint(host: _host, port: _port),
      bytes: _payload,
    );
    await corrupt.put('CT-A7F-20260818-0045', 'not a print job');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  // -------------------------------------------------------------------------
  // Printer settings
  // -------------------------------------------------------------------------

  screenshotCase(
    '36a-printer-not-set-up',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
      ),
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '36b-printer-configured',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(extraDocuments: _printer()),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
      ),
    ),
    viewports: responsiveViewports,
  );

  // No writer and no transport: the read-only rendering every injected
  // capability in this app degrades to. Neither *Save* nor *Test this printer*
  // is drawn, because a control that cannot work is worse than a missing one.
  screenshotCase(
    '36c-printer-settings-read-only',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(extraDocuments: _printer()),
      ),
    ),
    viewports: responsiveViewports,
  );

  // A document that exists and cannot be trusted. It is deliberately not
  // reported as "no printer configured": that would invite an owner to set up
  // a printer they already have.
  screenshotCase(
    '36d-printer-settings-not-read',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(
          extraDocuments: _printer(port: 'nine thousand one hundred'),
        ),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
      ),
    ),
    viewports: responsiveViewports,
  );

  // -------------------------------------------------------------------------
  // Bluetooth, since 2026-10-03; drawn to docs/design/bluetooth-printer/ on
  // 2026-10-04. The devices are the boards' own, so a capture and a board can
  // be laid side by side.
  // -------------------------------------------------------------------------

  // The first visit: nothing asked of the phone yet, and the card says where
  // this device's receipts go now - the business's network printer.
  screenshotCase(
    '36e-printer-bluetooth-first-visit',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(extraDocuments: _btNetworkPrinter),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
        bluetooth: _bluetooth(),
        printModes: _ShotModes(),
      ),
    ),
    afterPump: _openBluetooth,
    viewports: responsiveViewports,
  );

  // This device already prints on a Bluetooth printer, so the page opens on
  // that tab with the printer in use at the top.
  screenshotCase(
    '36f-printer-bluetooth-in-use',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(extraDocuments: _btNetworkPrinter),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
        bluetooth: _bluetooth(inUse: true),
        printModes: _ShotModes(),
      ),
    ),
    viewports: responsiveViewports,
  );

  // A search still running: what the phone already knows, then what it is
  // hearing, with the devices that broadcast no name folded away.
  screenshotCase(
    '36h-printer-bluetooth-found',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(extraDocuments: _btNetworkPrinter),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
        bluetooth: _bluetooth(),
        printModes: _ShotModes(),
      ),
    ),
    afterPump: _search,
    viewports: responsiveViewports,
  );

  // One printer opened: its sheet at the half detent, with the paper width,
  // the cutter and *Connect* - and, never paired, what *Connect* will do.
  screenshotCase(
    '36i-printer-bluetooth-sheet',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(extraDocuments: _btNetworkPrinter),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
        bluetooth: _bluetooth(),
        printModes: _ShotModes(),
      ),
    ),
    afterPump: (tester) async {
      await _search(tester);
      final row = find.byKey(
        const ValueKey('printer-bluetooth-device-$_btAddress'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
    },
    // A sheet is a fraction of the screen, so the screen is the capture.
    fullPage: false,
    viewports: responsiveViewports,
  );

  // No printer anywhere: no Bluetooth printer here and none set up for the
  // business, which is a step not taken rather than a fault.
  screenshotCase(
    '36j-printer-bluetooth-no-printer',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
        bluetooth: _bluetooth(),
        printModes: _ShotModes(),
      ),
    ),
    afterPump: _openBluetooth,
    viewports: responsiveViewports,
  );

  // **USB, in a browser** - the web till's way to print since 2026-10-10.
  // Nothing chosen yet, with one printer the browser already allowed.
  screenshotCase(
    '36k-printer-usb-none',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
        usb: _usb(),
        system: _system(),
        printModes: _ShotModes(),
      ),
    ),
    afterPump: _openUsb,
    viewports: responsiveViewports,
  );

  // A USB printer in use: the page opens on its tab.
  screenshotCase(
    '36l-printer-usb-in-use',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(extraDocuments: _btNetworkPrinter),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
        usb: _usb(inUse: true),
        system: _system(),
        printModes: _ShotModes(),
      ),
    ),
    viewports: responsiveViewports,
  );

  // A browser with no WebUSB - Safari, Firefox.
  screenshotCase(
    '36m-printer-usb-unsupported',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
        usb: _usb(supported: false),
        system: _system(),
        printModes: _ShotModes(),
      ),
    ),
    afterPump: _openUsb,
    viewports: responsiveViewports,
  );

  // **The print dialog** - receipts as a page in the device's own print
  // window, for a printer this app cannot reach directly (2026-10-10).
  screenshotCase(
    '36n-printer-system-none',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
        usb: _usb(),
        system: _system(),
        printModes: _ShotModes(),
      ),
    ),
    afterPump: _openSystem,
    viewports: responsiveViewports,
  );

  // The print dialog in use: the page opens on its tab.
  screenshotCase(
    '36o-printer-system-in-use',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(extraDocuments: _btNetworkPrinter),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
        usb: _usb(),
        system: _system(inUse: true),
        printModes: _ShotModes(),
      ),
    ),
    viewports: responsiveViewports,
  );

  // **USB on a web till on Windows** - the print helper's three steps, and
  // nothing of the browser's own picker (2026-10-11).
  for (final (name, version, printers) in <(String, String?, bool)>[
    ('36q-printer-usb-windows-install', null, false),
    ('36r-printer-usb-windows-plug-in', '1.0.3', false),
    ('36s-printer-usb-windows-choose', '1.0.3', true),
  ]) {
    screenshotCase(
      name,
      build: () => inSession(
        TenantPrinterConfigurationScreen(
          reader: FakeTenantReader.business(),
          writer: FakeConfigurationDocumentWriter(),
          testPrint: _refusePrint,
          usb: UsbPrinterSetup(
            chooser: const _ShotUsbChooser(supported: true),
            store: _ShotUsbStore(null),
            probe: (_) async {},
            helper: _helper(version, printers: printers),
          ),
          system: _system(),
          printModes: _ShotModes(),
          printHelper: _helper(version, printers: printers),
        ),
      ),
      afterPump: _openUsb,
      viewports: responsiveViewports,
    );
  }

  // -------------------------------------------------------------------------
  // The queue
  // -------------------------------------------------------------------------

  // **The queue is a section of the notifications page since 2026-09-03**, not
  // a screen of its own reached from the home's grid - so these capture it
  // where a person now meets it, with the local work counts above it.
  screenshotCase(
    '37a-no-receipts-waiting',
    build: () => inSession(_notifications(empty)),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '37b-receipts-waiting',
    build: () => inSession(
      _notifications(
        waiting,
        onRetry: (_) async => PrinterTransportCode.unreachable,
      ),
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '37c-receipts-waiting-read-only',
    build: () => inSession(_notifications(waiting)),
    viewports: responsiveViewports,
  );

  // **The other half of the page**, which the four receipt cases leave empty:
  // every state a sale or a business change can be in, as figures.
  screenshotCase(
    '37e-sending-to-the-server',
    build: () => inSession(
      _notifications(
        empty,
        summary: const CheckoutEvidenceSummary(
          savedOffline: 2,
          submitting: 1,
          awaitingConfirmation: 3,
          needsAttention: 1,
          confirmed: 11,
          mutations: TenantMutationEvidenceSummary(queued: 1, confirmed: 4),
        ),
      ),
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '37d-receipts-some-unreadable',
    build: () => inSession(
      _notifications(
        unreadable,
        onRetry: (_) async => PrinterTransportCode.unreachable,
      ),
    ),
    viewports: responsiveViewports,
  );
}

/// The notifications page around one print queue.
///
/// The local work counts are empty unless a case asks for them: the receipt
/// captures are about the receipts, and a second set of moving figures above
/// them would make the differences between the four harder to see rather than
/// easier.
///
/// **The seeded business, because the queue is now read per business.** Every
/// job above is enqueued under [seedTenantId], and `pending` drops any other
/// tenant's jobs - so a different ID here would capture an empty queue.
Widget _notifications(
  HivePrintJobQueue queue, {
  PrintJobRetry? onRetry,
  CheckoutEvidenceSummary summary = const CheckoutEvidenceSummary(),
}) => TenantNotificationsScreen(
  tenantId: seedTenantId,
  evidenceSource: FakeEvidenceSource(summary),
  printQueue: queue,
  onRetryPrint: onRetry,
);

/// The boards' MPT-II, the common 58mm model, at a made-up address.
const String _btAddress = 'DC:0D:30:9A:4E:21';

/// Mwangi Hardware's network printer as the boards draw it: 80mm, no cutter.
final Map<String, Map<String, Object?>> _btNetworkPrinter = _printer(
  paperWidth: 'columns_48',
);

/// Each kind's tab, by its name on the strip.
const Map<String, String> _tabs = <String, String>{
  'usb': 'USB',
  'bluetooth': 'Bluetooth',
  'dialog': 'Print dialog',
};

/// Opens [mode]'s tab and switches it on, unless it is on already.
Future<void> _switchOn(WidgetTester tester, String mode) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppTabs),
      matching: find.text(_tabs[mode]!),
    ),
  );
  await tester.pumpAndSettle();
  final row = find.byKey(ValueKey('printer-mode-$mode'));
  if (tester.widget<AppSwitchRow>(row).value) return;
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> _openBluetooth(WidgetTester tester) =>
    _switchOn(tester, 'bluetooth');

Future<void> _search(WidgetTester tester) async {
  await _openBluetooth(tester);
  await tester.tap(find.byKey(const ValueKey('printer-bluetooth-search')));
  await tester.pumpAndSettle();
}

/// A Bluetooth tab over a radio that hears what a shop counter does, and a
/// device store holding this device's printer when [inUse].
BluetoothPrinterSetup _bluetooth({bool inUse = false}) => BluetoothPrinterSetup(
  discovery: const _ShotDiscovery(),
  store: _ShotStore(
    inUse
        ? DeviceBluetoothPrinter(
            address: _btAddress,
            name: 'MPT-II',
            paperWidth: PrinterPaperWidth.columns32,
            hasCutter: false,
          )
        : null,
  ),
  probe: (_) async {},
);

final class _ShotDiscovery implements BluetoothPrinterDiscovery {
  const _ShotDiscovery();

  @override
  bool get isSupported => true;

  @override
  Future<BluetoothReadiness> prepare() async => BluetoothReadiness.ready;

  @override
  Future<bool> turnOn() async => true;

  @override
  Future<void> openPermissionSettings() async {}

  /// Somebody's earbuds.
  @override
  Future<List<BluetoothPrinterDevice>> paired() async =>
      const <BluetoothPrinterDevice>[
        BluetoothPrinterDevice(
          address: '3C:B0:ED:41:7A:02',
          name: 'oraimo FreePods lite',
          paired: true,
        ),
      ];

  /// The printer, a second printer, a phone, and two devices that broadcast
  /// no name - and **still listening**, so the capture is of a search under
  /// way, as the boards draw it.
  @override
  Stream<BluetoothPrinterDevice> search() {
    // Never closed: discovery is still running when the capture is taken.
    // ignore: close_sinks
    final heard = StreamController<BluetoothPrinterDevice>();
    for (final device in const <BluetoothPrinterDevice>[
      BluetoothPrinterDevice(
        address: _btAddress,
        name: 'MPT-II',
        paired: false,
      ),
      BluetoothPrinterDevice(
        address: '86:67:7A:0C:53:9E',
        name: 'XP-P323B',
        paired: false,
      ),
      BluetoothPrinterDevice(
        address: '5C:F3:70:12:9A:01',
        name: 'Galaxy A15',
        paired: false,
      ),
      BluetoothPrinterDevice(address: '4F:21:9C:05:BB:10', paired: false),
      BluetoothPrinterDevice(address: '61:0A:EE:73:1D:58', paired: false),
    ]) {
      heard.add(device);
    }
    return heard.stream;
  }

  @override
  Future<bool> pair(String address) async => true;
}

final class _ShotStore implements DeviceBluetoothPrinterStore {
  _ShotStore(this._printer);

  DeviceBluetoothPrinter? _printer;

  @override
  DeviceBluetoothPrinter? read(String tenantId) => _printer;

  @override
  Future<void> save(String tenantId, DeviceBluetoothPrinter printer) async =>
      _printer = printer;

  @override
  Future<void> forget(String tenantId) async => _printer = null;
}

/// A *Test this printer* that always refuses.
///
/// **The parameter was renamed to `testPrint` and this fixture was not**, so
/// `flutter test tool/screenshots` had not compiled this file for some time.
/// The control needs the whole configuration rather than an endpoint - it
/// prints the paper width and the cutter setting - which is why a transport's
/// bare `probe` no longer fits it.
Future<void> _refusePrint(TenantPrinterConfiguration configuration) async =>
    throw const PrinterTransportException(PrinterTransportCode.unreachable);

Future<void> _openUsb(WidgetTester tester) => _switchOn(tester, 'usb');

/// The print helper as a capture needs it: answering as [version], or not
/// installed when that is null, with the Xprinter plugged in when [printers].
PrintHelperSetup _helper(String? version, {required bool printers}) =>
    PrintHelperSetup(
      helper: _ShotPrintHelper(version, printers: printers),
      memory: InMemoryPrintHelperMemory(),
      download: () async {},
    );

final class _ShotPrintHelper implements PrintHelper {
  const _ShotPrintHelper(this._version, {required this.printers});

  final String? _version;
  final bool printers;

  @override
  Future<String?> version() async => _version;

  @override
  Future<List<PrintHelperPrinter>> usbPrinters() async => printers
      ? const <PrintHelperPrinter>[
          PrintHelperPrinter(
            key: '1FC9:2016:06C6ACA91073',
            name: 'Xprinter XP-365B',
          ),
        ]
      : const <PrintHelperPrinter>[];

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async {}

  @override
  Future<void> probe(PrinterEndpoint endpoint) async {}

  @override
  Future<PrintHelperRemoval> remove() async => PrintHelperRemoval.removed;
}

Future<void> _openSystem(WidgetTester tester) => _switchOn(tester, 'dialog');

/// The kind of printer a capture's device prints on: none chosen yet, so the
/// page reads it from what is chosen, as an installed device does.
final class _ShotModes implements DevicePrintModeStore {
  DevicePrintMode? _mode;

  @override
  DevicePrintMode? read(String tenantId) => _mode;

  @override
  Future<void> save(String tenantId, DevicePrintMode mode) async =>
      _mode = mode;
}

/// The print dialog tab, chosen when [inUse].
SystemPrinterSetup _system({bool inUse = false}) => SystemPrinterSetup(
  store: _ShotSystemStore(
    inUse
        ? const DeviceSystemPrinter(paperWidth: PrinterPaperWidth.columns48)
        : null,
  ),
  probe: (_) async {},
);

final class _ShotSystemStore implements DeviceSystemPrinterStore {
  _ShotSystemStore(this._printer);

  DeviceSystemPrinter? _printer;

  @override
  DeviceSystemPrinter? read(String tenantId) => _printer;

  @override
  Future<void> save(String tenantId, DeviceSystemPrinter printer) async =>
      _printer = printer;

  @override
  Future<void> forget(String tenantId) async => _printer = null;
}

const UsbPrinterDevice _usbPrinter = UsbPrinterDevice(
  vendorId: 0x04B8,
  productId: 0x0E15,
  serialNumber: 'J5A0123',
  productName: 'TM-T20II',
  manufacturerName: 'EPSON',
);

/// A USB tab in a browser that has WebUSB unless [supported] is false, with
/// the counter's printer already allowed - and chosen, when [inUse].
UsbPrinterSetup _usb({bool inUse = false, bool supported = true}) =>
    UsbPrinterSetup(
      chooser: _ShotUsbChooser(supported: supported),
      store: _ShotUsbStore(
        inUse
            ? DeviceUsbPrinter(
                key: _usbPrinter.key,
                name: _usbPrinter.label,
                paperWidth: PrinterPaperWidth.columns48,
                hasCutter: true,
              )
            : null,
      ),
      probe: (_) async {},
    );

final class _ShotUsbChooser implements UsbPrinterChooser {
  const _ShotUsbChooser({required this.supported});

  final bool supported;

  @override
  bool get isSupported => supported;

  @override
  Future<UsbPrinterDevice?> choose({bool anyDevice = false}) async => null;

  @override
  Future<List<UsbPrinterDevice>> permitted() async => const <UsbPrinterDevice>[
    _usbPrinter,
  ];
}

final class _ShotUsbStore implements DeviceUsbPrinterStore {
  _ShotUsbStore(this._printer);

  DeviceUsbPrinter? _printer;

  @override
  DeviceUsbPrinter? read(String tenantId) => _printer;

  @override
  Future<void> save(String tenantId, DeviceUsbPrinter printer) async =>
      _printer = printer;

  @override
  Future<void> forget(String tenantId) async => _printer = null;
}
