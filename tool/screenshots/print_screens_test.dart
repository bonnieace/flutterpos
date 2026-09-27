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

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

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

/// A *Test this printer* that always refuses.
///
/// **The parameter was renamed to `testPrint` and this fixture was not**, so
/// `flutter test tool/screenshots` had not compiled this file for some time.
/// The control needs the whole configuration rather than an endpoint - it
/// prints the paper width and the cutter setting - which is why a transport's
/// bare `probe` no longer fits it.
Future<void> _refusePrint(TenantPrinterConfiguration configuration) async =>
    throw const PrinterTransportException(PrinterTransportCode.unreachable);
