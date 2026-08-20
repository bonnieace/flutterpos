/// Rings up a sale **through the till's own UI** and prints the receipt.
///
/// Sibling to `printer_smoke.dart`, which only probes, and to
/// `printer_receipt_smoke.dart`, which formats a fabricated payload and sends
/// it. This one is the whole path: it taps a product tile, taps a tender, taps
/// *Save*, and what comes out of the printer is what that press produced.
///
///   PRINTER_HOST=192.168.100.20 flutter test tool/printer_till_smoke.dart
///
/// **Everything below the screen is the production object.** The real
/// `CheckoutDraftService`, a receipt hook shaped exactly as `lib/main.dart`
/// builds it, the real `CheckoutPrintDispatcher`, the real `HivePrintJobQueue`,
/// and the real platform transport from `createPrinterTransport()`.
///
/// **What is not real is Firebase.** The session, the offline catalog and the
/// printer document are built locally, because `Firebase.initializeApp` needs
/// platform channels a widget test does not have. So this proves the till, the
/// sale path and the print path, and says nothing about auth or Firestore.
///
/// **Every durable step runs inside `tester.runAsync`.** `testWidgets` runs its
/// body in `FakeAsync`, where Hive's `put` awaits a real file write that fake
/// time never delivers — so a tap that saves a draft hangs rather than fails.
/// That is the trap `test/checkout/checkout_print_queue_panel_test.dart`
/// documents, and the reason the save below is not a bare `tester.tap`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart'
    show CapabilityProfile;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const String _uid = 'till-smoke-user';
const String _tenantId = 'till-smoke-tenant';

final List<int> _encryptionKey = List<int>.generate(
  HiveCheckoutOutbox.encryptionKeyBytes,
  (index) => (index * 7) % 256,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final host = Platform.environment['PRINTER_HOST'];
  final port =
      int.tryParse(Platform.environment['PRINTER_PORT'] ?? '') ??
      PrinterEndpoint.rawEscPosPort;
  final columns = Platform.environment['PRINTER_COLUMNS'] == '48'
      ? PrinterPaperWidth.columns48
      : PrinterPaperWidth.columns32;
  final hasCutter = Platform.environment['PRINTER_CUTTER'] == 'true';
  final businessName =
      Platform.environment['PRINTER_BUSINESS'] ?? 'Mugumo Stores';

  late Directory directory;
  late TenantSessionController sessions;
  late HiveCheckoutOutbox outbox;
  late HiveCheckoutCatalogCache cache;
  late HiveCheckoutReceiptCounters receipts;
  late HivePrintJobQueue jobs;
  late CheckoutPrintDispatcher dispatcher;
  final printed = <String>[];

  setUp(() async {
    // **Under the project, not `Directory.systemTemp`.** The boxes here are
    // encrypted and written for real, and on a machine whose system drive is
    // full those writes crawl or fail while reporting nothing useful. The
    // project's own `.dart_tool` is on whichever disk the checkout is on, which
    // is the one the developer chose.
    directory = await Directory(
      '${Directory.current.path}/.dart_tool/till-smoke',
    ).createTemp('run-');
    Hive.init(directory.path);
    Future<Box<dynamic>> open(String name) => Hive.openBox<dynamic>(
      name,
      encryptionCipher: HiveAesCipher(_encryptionKey),
      crashRecovery: false,
    );
    outbox = HiveCheckoutOutbox.fromBox(await open(HiveCheckoutOutbox.boxName));
    cache = HiveCheckoutCatalogCache.fromBox(
      await open(HiveCheckoutCatalogCache.boxName),
    );
    receipts = HiveCheckoutReceiptCounters.fromBox(
      await open(HiveCheckoutReceiptCounters.boxName),
    );
    jobs = HivePrintJobQueue.fromBox(await open(HivePrintJobQueue.boxName));
    dispatcher = CheckoutPrintDispatcher(
      queue: jobs,
      transport: createPrinterTransport(),
      profile: await CapabilityProfile.load(),
    );
    sessions = TenantSessionController()
      ..open(uid: _uid, membership: _membership());
    await cache.write(
      uid: _uid,
      tenantId: _tenantId,
      configuration: TenantCheckoutConfiguration(currency: 'KES'),
      categories: <TenantCategory>[_category('cat-bakery')],
      products: <TenantProduct>[
        _product('prod-bread', 'White bread loaf', 65),
        _product('prod-mandazi', 'Mandazi', 20),
      ],
      complete: true,
    );
  });

  // **`Hive.close()` is deliberately never called, and that cost an hour to
  // learn.** The boxes are opened for real and then written from inside
  // `FakeAsync`, so closing them — from here or from the test body under
  // `runAsync` — waits forever on flushes that fake time is holding. The run
  // then hangs *after* a receipt has already come out of the printer, which
  // reads as a failed print and is not one. The process exits moments later and
  // the operating system closes the handles; this is a smoke tool writing to a
  // scratch directory, not a service.
  tearDown(() async {
    sessions.dispose();
    if (await directory.exists()) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // Windows keeps a handle a moment longer than Dart does. A leftover
        // directory under `.dart_tool` is not worth failing a printed receipt.
      }
    }
  });

  testWidgets('rings up a sale at the till and prints its receipt', (
    tester,
  ) async {
    if (host == null || host.isEmpty) {
      stdout.writeln('PRINTER_HOST unset - skipping, nothing was printed.');
      return;
    }
    final configured = TenantConfiguredPrinter.configured(
      TenantPrinterConfiguration(
        transport: PrinterTransportKind.directTcp,
        endpoint: PrinterEndpoint(host: host, port: port),
        paperWidth: columns,
        hasCutter: hasCutter,
      ),
    );

    // The composition root's hook, in the shape `lib/main.dart` builds it:
    // dispatch a committed sale, return a code when it did not reach the
    // printer and null when it did.
    final drafts = CheckoutDraftService(
      sessionController: sessions,
      cache: cache,
      outbox: outbox,
      receipts: receipts,
      shiftBinder: _OpenShift(receipts),
      onSaved: (record, session) async {
        final result = await dispatcher.dispatch(
          CheckoutSalePayload.fromOutboxRecord(record, session: session),
          printer: configured,
          businessName: businessName,
          servedBy: 'Wanjiku',
        );
        if (result.outcome == CheckoutPrintOutcome.sent) {
          printed.add(result.job!.receiptNumber);
          return null;
        }
        return result.reasonCode;
      },
    );

    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: spiritTheme,
        home: TenantSessionScope(
          controller: sessions,
          child: TenantCheckoutScreen(cache: cache, drafts: drafts),
        ),
      ),
    );
    await _settle(tester);

    // Two loaves, one mandazi, and cash - tapped exactly as a cashier taps them.
    await _tap(tester, 'checkout-product-prod-bread');
    await _tap(tester, 'checkout-product-prod-bread');
    await _tap(tester, 'checkout-product-prod-mandazi');
    await _tap(tester, 'checkout-tender-cash');

    // **The save, and the one place fake time cannot go.** The draft writes to
    // three encrypted Hive boxes and then a socket is dialled; all of it is
    // real I/O on a real file system and a real network.
    //
    // **Fake time and real time have to be advanced alternately, and that is
    // the whole difficulty.** The tap starts the save inside `FakeAsync`, so
    // every `await` in the draft service belongs to fake time — but what those
    // awaits are waiting on is a real file write and a real socket, which only
    // progress in real time. Pumping alone never delivers the I/O; `runAsync`
    // alone never delivers the continuations the I/O completes. So each turn
    // gives a little of both, until the till has drawn its answer.
    await tester.tap(find.byKey(const ValueKey('checkout-save')));
    for (var turn = 0; turn < 120; turn++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      if (find.byKey(const ValueKey('checkout-saved')).evaluate().isNotEmpty) {
        break;
      }
    }
    await _settle(tester);

    // What the cashier is looking at.
    if (find.byKey(const ValueKey('checkout-saved')).evaluate().isEmpty) {
      // Every sentence currently on the screen, so a refusal names itself
      // rather than arriving as "0 widgets found".
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .where((line) => line.trim().isNotEmpty)
          .toList();
      fail('the sale did not save. On screen:\n  ${texts.join("\n  ")}');
    }
    // The callout this wiring added. Its absence is the assertion.
    final failure = find.byKey(const ValueKey('checkout-receipt-print'));
    if (failure.evaluate().isNotEmpty) {
      fail(
        'the till reported a printing failure: '
        '${tester.widget<Callout>(failure).message}',
      );
    }

    expect(printed, hasLength(1), reason: 'exactly one receipt was dispatched');
    final job = jobs.read(printed.single)!;
    expect(job.state, PrintJobState.printed);
    stdout.writeln('endpoint  : ${configured.configuration!.endpoint}');
    stdout.writeln('receipt   : ${job.receiptNumber}');
    stdout.writeln('payload   : ${job.bytes.length} bytes');
    stdout.writeln('SENT - rang up at the till, delivered to the printer.');
  });
}

/// A shift that is always open. The binder is the one collaborator a till
/// cannot run without and the one this smoke test has nothing to say about.
final class _OpenShift implements CheckoutShiftBinder {
  const _OpenShift(this._receipts);

  final HiveCheckoutReceiptCounters _receipts;

  @override
  Future<CheckoutShiftBinding> bindCheckoutShift(TenantSession session) async =>
      CheckoutShiftBinding.bound(
        CheckoutShiftAttribution(
          uid: session.uid,
          tenantId: session.tenantId,
          shiftId: 'till-smoke-shift',
          deviceId: await _receipts.resolveDeviceId(),
          businessDate: checkoutBusinessDate(DateTime.now().toUtc()),
        ),
      );
}

TenantMembership _membership() => TenantMembership(
  tenantId: _tenantId,
  tenantName: 'Till Smoke',
  tenantSlug: 'till-smoke',
  role: TenantRole.cashier,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

TenantCategory _category(String id) => TenantCategory.fromSnapshot(
  TenantQueryDocumentSnapshot(
    path: 'tenants/$_tenantId/categories/$id',
    data: <String, Object?>{'name': 'Bakery'},
  ),
);

TenantProduct _product(String id, String name, double price) =>
    TenantProduct.fromSnapshot(
      TenantQueryDocumentSnapshot(
        path: 'tenants/$_tenantId/products/$id',
        data: <String, Object?>{
          'name': name,
          'SKU': 'sku-$id',
          'price': price,
          'quantity': 40,
          'categoryId': 'cat-bakery',
        },
      ),
    );

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}
