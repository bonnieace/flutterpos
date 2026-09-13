import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenant_session.dart';
import 'package:flutter_application_1/tenancy/tenant_types.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Box<dynamic> box;
  late HivePrintJobQueue queue;
  late CapabilityProfile profile;

  setUpAll(() async {
    profile = await CapabilityProfile.load();
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('print-dispatch-test-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>(HivePrintJobQueue.boxName);
    queue = HivePrintJobQueue.fromBox(box);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  CheckoutPrintDispatcher dispatcher(PrinterTransport transport) =>
      CheckoutPrintDispatcher(
        queue: queue,
        transport: transport,
        profile: profile,
      );

  group('a second copy of a receipt', () {
    test('one this device never printed is rebuilt, audited, and sent', () async {
      final transport = _FakeTransport();
      final audits = <String>[];

      final result = await dispatcher(transport).reprint(
        _sale(),
        printer: _printer(),
        onReprint: () async => audits.add('recorded'),
      );

      expect(result.outcome, CheckoutPrintOutcome.sent);
      expect(audits, hasLength(1));
      expect(transport.sends, hasLength(1));
    });

    test('a printed receipt is re-sent as the bytes that printed', () async {
      final transport = _FakeTransport();
      final subject = dispatcher(transport);
      await subject.dispatch(_sale(), printer: _printer());
      expect(transport.sends, hasLength(1));
      final audits = <String>[];

      final result = await subject.reprint(
        _sale(),
        printer: _printer(),
        onReprint: () async => audits.add('recorded'),
        // Deliberately a different heading. A receipt reprinted after the shop
        // renamed itself must still print what was handed over.
        businessName: 'A Different Name Entirely',
      );

      expect(result.outcome, CheckoutPrintOutcome.sent);
      expect(audits, hasLength(1));
      expect(transport.sends, hasLength(2));
      expect(transport.sends[1], transport.sends[0]);
    });

    test('an audit that refuses prints nothing and queues nothing', () async {
      final transport = _FakeTransport();
      final subject = dispatcher(transport);

      // The record is written before anything else happens, so a reprint that
      // could not be recorded never happened.
      await expectLater(
        subject.reprint(
          _sale(),
          printer: _printer(),
          onReprint: () async => throw const _AuditRefused(),
        ),
        throwsA(isA<_AuditRefused>()),
      );

      expect(transport.sends, isEmpty);
      expect(queue.read(_sale().receiptNumber), isNull);
    });

    test('a refused audit cannot re-send a receipt that already printed', () async {
      final transport = _FakeTransport();
      final subject = dispatcher(transport);
      await subject.dispatch(_sale(), printer: _printer());

      await expectLater(
        subject.reprint(
          _sale(),
          printer: _printer(),
          onReprint: () async => throw const _AuditRefused(),
        ),
        throwsA(isA<_AuditRefused>()),
      );

      expect(transport.sends, hasLength(1));
      expect(
        queue.read(_sale().receiptNumber)!.state,
        PrintJobState.printed,
      );
    });

    test('a first copy still on its way is a retry, and is not audited', () async {
      final transport = _FakeTransport();
      final subject = dispatcher(transport);
      // Queued but never sent: the customer has had no receipt at all yet.
      await subject.enqueue(_sale(), printer: _printer());
      final audits = <String>[];

      final result = await subject.reprint(
        _sale(),
        printer: _printer(),
        onReprint: () async => audits.add('recorded'),
      );

      expect(result.outcome, CheckoutPrintOutcome.sent);
      expect(transport.sends, hasLength(1));
      expect(audits, isEmpty);
    });

    test('a business with no printer is refused before it is audited', () async {
      final audits = <String>[];

      final result = await dispatcher(_FakeTransport()).reprint(
        _sale(),
        printer: const TenantConfiguredPrinter.absent(),
        onReprint: () async => audits.add('recorded'),
      );

      expect(result.outcome, CheckoutPrintOutcome.refused);
      expect(result.reasonCode, PrinterTransportCode.notConfigured);
      expect(audits, isEmpty);
    });
  });

  group('a configured printer', () {
    test('local enqueue persists a job without touching transport', () async {
      final transport = _FakeTransport();

      final result = await dispatcher(
        transport,
      ).enqueue(_sale(), printer: _printer(), businessName: 'Kilimani Grocers');

      expect(result.outcome, CheckoutPrintOutcome.queued);
      expect(queue.read(_sale().receiptNumber), isNotNull);
      expect(transport.sends, isEmpty);
    });

    test('builds the receipt, queues it, and sends it', () async {
      final transport = _FakeTransport();

      final result = await dispatcher(transport).dispatch(
        _sale(),
        printer: _printer(),
        businessName: 'Kilimani Grocers',
      );

      expect(result.outcome, CheckoutPrintOutcome.sent);
      expect(result.reasonCode, isNull);
      expect(result.job!.state, PrintJobState.printed);
      expect(transport.sends, hasLength(1));
      expect(transport.sends.single, isNotEmpty);
    });

    test(
      'keys the job on the receipt number the sale already carries',
      () async {
        final sale = _sale();

        final result = await dispatcher(
          _FakeTransport(),
        ).dispatch(sale, printer: _printer());

        expect(result.job!.receiptNumber, sale.receiptNumber);
        expect(box.keys, contains(sale.receiptNumber));
      },
    );

    test('dispatching one sale twice sends it once', () async {
      // The idempotence arrives from the queue rather than from here, and this
      // is the assertion that says the dispatcher does not defeat it.
      final transport = _FakeTransport();
      final sale = _sale();
      final subject = dispatcher(transport);

      await subject.dispatch(sale, printer: _printer());
      final second = await subject.dispatch(sale, printer: _printer());

      expect(transport.sends, hasLength(1));
      expect(second.outcome, CheckoutPrintOutcome.sent);
    });
  });

  group('when the send fails', () {
    test('the job survives, carrying the transports own code', () async {
      final transport = _FakeTransport(
        failWith: PrinterTransportCode.writeTimeout,
      );

      final result = await dispatcher(
        transport,
      ).dispatch(_sale(), printer: _printer());

      expect(result.outcome, CheckoutPrintOutcome.queued);
      expect(result.reasonCode, PrinterTransportCode.writeTimeout);
      expect(result.job!.state, PrintJobState.needsAttention);
      // Durable, so a retry has something to retry.
      expect(queue.read(_sale().receiptNumber), isNotNull);
    });

    test(
      'never throws for a printing reason, because a sale path calls it',
      () async {
        // §6.3's argument with a larger consequence: a receipt that can break a
        // checkout is a paper jam that can lose a sale.
        for (final code in PrinterTransportCode.all) {
          final local = await Hive.openBox<dynamic>('dispatch-$code');
          final subject = CheckoutPrintDispatcher(
            queue: HivePrintJobQueue.fromBox(local),
            transport: _FakeTransport(failWith: code),
            profile: profile,
          );

          final result = await subject.dispatch(_sale(), printer: _printer());

          expect(result.outcome, CheckoutPrintOutcome.queued, reason: code);
          expect(result.reasonCode, code, reason: code);
        }
      },
    );

    test(
      'a retry re-sends the bytes the sale produced, not new ones',
      () async {
        // A receipt retried after a price change must print what was charged.
        final transport = _FakeTransport(
          failWith: PrinterTransportCode.unreachable,
        );
        final sale = _sale();
        final subject = dispatcher(transport);
        final failed = await subject.dispatch(sale, printer: _printer());
        final queuedBytes = failed.job!.bytes;

        transport.failWith = null;
        final retried = await subject.retry(sale.receiptNumber);

        expect(retried.outcome, CheckoutPrintOutcome.sent);
        expect(transport.sends.single, queuedBytes);
      },
    );
  });

  group('retry, on a job that is not failed', () {
    test('a queued job is simply sent, rather than throwing', () async {
      // **`HivePrintJobQueue.retry` refuses `queued` with `invalid_transition`,
      // and a *Send again* control can easily be pressed in that state** - the
      // queue and the screen do not share a frame, so the job can have been
      // re-queued by recovery between the render and the tap.
      final transport = _FakeTransport();
      final sale = _sale();
      await queue.enqueue(
        tenantId: 'tenant-a',
        receiptNumber: sale.receiptNumber,
        endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
        bytes: const <int>[27, 64],
      );

      final result = await dispatcher(transport).retry(sale.receiptNumber);

      expect(result.outcome, CheckoutPrintOutcome.sent);
      expect(transport.sends, hasLength(1));
    });

    test(
      'a printed job is not re-sent, because that is what reprint is',
      () async {
        // Reaching `printed` means the queue never re-sends on its own, and a
        // second copy is an audited act. This must not become a back door to it.
        final transport = _FakeTransport();
        final sale = _sale();
        final subject = dispatcher(transport);
        await subject.dispatch(sale, printer: _printer());

        final result = await subject.retry(sale.receiptNumber);

        expect(result.outcome, CheckoutPrintOutcome.sent);
        expect(transport.sends, hasLength(1));
      },
    );

    test('an unknown receipt refuses rather than throwing', () async {
      final result = await dispatcher(
        _FakeTransport(),
      ).retry('CT-A7F-20260729-9999');

      expect(result.outcome, CheckoutPrintOutcome.refused);
    });
  });

  group('when no printer is configured', () {
    test('refuses, writes no job, and never guesses an address', () async {
      // `docs/printer_transport.md` §6: no default printer address, ever. The
      // borrowed repo falls back to a built-in `192.168.100.100`, which on a
      // customer LAN is someone else's device.
      final transport = _FakeTransport();

      final result = await dispatcher(
        transport,
      ).dispatch(_sale(), printer: const TenantConfiguredPrinter.absent());

      expect(result.outcome, CheckoutPrintOutcome.refused);
      expect(result.reasonCode, PrinterTransportCode.notConfigured);
      expect(result.job, isNull);
      expect(box.keys, isEmpty);
      expect(transport.sends, isEmpty);
    });

    test(
      'a malformed document refuses exactly as an absent one does',
      () async {
        final result = await dispatcher(
          _FakeTransport(),
        ).dispatch(_sale(), printer: const TenantConfiguredPrinter.malformed());

        expect(result.outcome, CheckoutPrintOutcome.refused);
        expect(box.keys, isEmpty);
      },
    );

    test(
      'the refused receipt is recoverable, because the key is derived',
      () async {
        // The reason refusing is safe: the sale is durable and the job key is the
        // receipt number, so queueing it once a printer exists produces the same
        // job rather than a second delivery.
        final sale = _sale();
        final subject = dispatcher(_FakeTransport());
        await subject.dispatch(
          sale,
          printer: const TenantConfiguredPrinter.absent(),
        );

        final later = await subject.dispatch(sale, printer: _printer());

        expect(later.outcome, CheckoutPrintOutcome.sent);
        expect(later.job!.receiptNumber, sale.receiptNumber);
        expect(
          box.keys.where((key) => key == sale.receiptNumber),
          hasLength(1),
        );
      },
    );
  });
}

TenantConfiguredPrinter _printer({bool hasCutter = true}) =>
    TenantConfiguredPrinter.configured(
      TenantPrinterConfiguration(
        transport: PrinterTransportKind.directTcp,
        endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
        paperWidth: PrinterPaperWidth.columns32,
        hasCutter: hasCutter,
      ),
    );

/// What the audit seam throws when the server will not record the reprint.
final class _AuditRefused implements Exception {
  const _AuditRefused();
}

final class _FakeTransport implements PrinterTransport {
  _FakeTransport({this.failWith});

  String? failWith;
  final List<List<int>> sends = <List<int>>[];

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.directTcp,
    endpointIsPrinter: true,
    label: 'Fake',
  );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async {}

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async {
    if (failWith != null) throw PrinterTransportException(failWith!);
    sends.add(List<int>.unmodifiable(bytes));
  }

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
