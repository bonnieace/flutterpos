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
      ),
    ),
    viewports: responsiveViewports,
  );

  // The network tab on that device: the business setting, with this device's
  // exception stated above it.
  screenshotCase(
    '36g-printer-network-with-bluetooth-in-use',
    build: () => inSession(
      TenantPrinterConfigurationScreen(
        reader: FakeTenantReader.business(extraDocuments: _btNetworkPrinter),
        writer: FakeConfigurationDocumentWriter(),
        testPrint: _refusePrint,
        bluetooth: _bluetooth(inUse: true),
      ),
    ),
    afterPump: (tester) async {
      await tester.tap(
        find.descendant(
          of: find.byType(AppTabs),
          matching: find.text('Network'),
        ),
      );
      await tester.pumpAndSettle();
    },
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
      ),
    ),
    afterPump: _openBluetooth,
    viewports: responsiveViewports,
  );

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

Future<void> _openBluetooth(WidgetTester tester) async {
  await tester.tap(find.text('Bluetooth'));
  await tester.pumpAndSettle();
}

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
