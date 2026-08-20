import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/states.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../support/notices.dart';

const String _receipt = 'CT-A7F-20260729-0042';
const String _otherReceipt = 'CT-A7F-20260729-0043';
const List<int> _payload = <int>[27, 64, 72, 105, 10];

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HivePrintJobQueue queue;
  late PrinterEndpoint endpoint;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('print-queue-panel-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>(HivePrintJobQueue.boxName);
    queue = HivePrintJobQueue.fromBox(box);
    endpoint = PrinterEndpoint(host: '192.168.1.50', port: 9100);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  // **Every durable write goes through `tester.runAsync`, and that is not
  // ceremony.** `testWidgets` runs its body inside `FakeAsync`; Hive's `put`
  // awaits a real file write on the IO thread pool, and fake time never
  // advances far enough to deliver it - so `await queue.enqueue(...)` in a
  // widget test never returns at all. The first case in this file passed
  // because it seeds nothing, and every case after it hung until the whole
  // file timed out. `PLAN.md` carries the neighbouring trap about turn counts;
  // this is the same hazard one step further on, where no number of turns
  // works.
  Future<void> seed(
    WidgetTester tester, {
    String receiptNumber = _receipt,
    String? failWith,
  }) => tester.runAsync(() async {
    await queue.enqueue(
      tenantId: 'tenant-a',
      receiptNumber: receiptNumber,
      endpoint: endpoint,
      bytes: _payload,
    );
    if (failWith == null) return;
    await queue.run(receiptNumber, transport: _FailingTransport(failWith));
  });

  Future<void> seedUnreadable(WidgetTester tester, List<String> keys) =>
      tester.runAsync(() async {
        for (final key in keys) {
          await box.put(key, <String, Object?>{'schemaVersion': 1});
        }
      });

  Future<void> seedSent(WidgetTester tester, String receiptNumber) =>
      tester.runAsync(() async {
        await queue.enqueue(
          tenantId: 'tenant-a',
          receiptNumber: receiptNumber,
          endpoint: endpoint,
          bytes: _payload,
        );
        await queue.run(receiptNumber, transport: const _SendingTransport());
      });

  testWidgets('an empty queue says so, and says what would put one here', (
    tester,
  ) async {
    await _pump(tester, queue);

    expect(find.byKey(const ValueKey('print-queue-empty')), findsOne);
    expect(find.byType(EmptyState), findsOne);
    expect(find.text('No receipts are waiting'), findsOne);
  });

  testWidgets('a failed receipt is listed with the transports own sentence', (
    tester,
  ) async {
    // The eight codes are mapped once, in `checkout_print_failures.dart`; this
    // screen decides where they appear and invents none.
    await seed(tester, failWith: PrinterTransportCode.writeTimeout);

    await _pump(tester, queue);

    expect(find.text(_receipt), findsWidgets);
    expect(
      find.text(
        PrinterFailureNotice.of(PrinterTransportCode.writeTimeout).message,
      ),
      findsOne,
    );
  });

  testWidgets('a status is a word, not a colour', (tester) async {
    // §9: container, glyph and label. Never hue alone.
    await seed(tester, failWith: PrinterTransportCode.unreachable);

    await _pump(tester, queue);

    expect(find.text('Not sent'), findsOne);
  });

  testWidgets('shows the address on the job, not the one in settings', (
    tester,
  ) async {
    // A receipt queued before the printer moved still says where it is going,
    // which is the whole reason the endpoint lives on the record.
    await seed(tester, failWith: PrinterTransportCode.unreachable);

    await _pump(tester, queue);

    expect(find.text('192.168.1.50:9100'), findsOne);
  });

  group('sending again', () {
    testWidgets('is offered on a failure a retry could fix', (tester) async {
      await seed(tester, failWith: PrinterTransportCode.unreachable);

      await _pump(tester, queue, onRetry: (_) async => null);

      expect(
        find.byKey(const ValueKey('print-queue-retry-$_receipt')),
        findsOne,
      );
    });

    testWidgets('is not offered where a retry cannot possibly work', (
      tester,
    ) async {
      // `printer_not_configured` needs a setting and `transport_unsupported`
      // needs a different device. A control guaranteed to fail is worse than a
      // missing one.
      await seed(tester, failWith: PrinterTransportCode.notConfigured);

      await _pump(tester, queue, onRetry: (_) async => null);

      // The control is drawn and **disabled**, rather than absent: §5's matrix
      // has a `disabled` row, and a row whose action vanishes tells a person
      // nothing about why.
      final action = tester.widget<AppButton>(
        find.byKey(const ValueKey('print-queue-retry-$_receipt')),
      );
      expect(action.onPressed, isNull);
    });

    testWidgets('is not offered at all in a build that cannot send', (
      tester,
    ) async {
      await seed(tester, failWith: PrinterTransportCode.unreachable);

      await _pump(tester, queue);

      expect(
        find.byKey(const ValueKey('print-queue-retry-$_receipt')),
        findsNothing,
      );
    });

    testWidgets('says it was sent, never that it was printed', (tester) async {
      // No ESC/POS transport can prove paper moved without status readback,
      // which Phase 1 does not do.
      final asked = <String>[];
      await seed(tester, failWith: PrinterTransportCode.unreachable);

      await _pump(
        tester,
        queue,
        onRetry: (receiptNumber) async {
          asked.add(receiptNumber);
          return null;
        },
      );
      await tester.tap(find.byKey(const ValueKey('print-queue-retry-$_receipt')));
      await tester.pump();
      await tester.pump();

      expect(asked.single, _receipt);
      expect(
        noticeMessage(tester, 'print-queue-notice'),
        PrinterFailureNotice.sent.message,
      );
      expect(
        noticeMessage(tester, 'print-queue-notice').toLowerCase(),
        isNot(contains('printed')),
      );
    });

    testWidgets('a second failure states the new reason', (tester) async {
      await seed(tester, failWith: PrinterTransportCode.unreachable);

      await _pump(
        tester,
        queue,
        onRetry: (_) async => PrinterTransportCode.connectTimeout,
      );
      await tester.tap(find.byKey(const ValueKey('print-queue-retry-$_receipt')));
      await tester.pump();
      await tester.pump();

      expect(
        noticeMessage(tester, 'print-queue-notice'),
        PrinterFailureNotice.of(PrinterTransportCode.connectTimeout).message,
      );
    });
  });

  group('what it could not read', () {
    testWidgets('is stated, rather than making the queue look empty', (
      tester,
    ) async {
      // **The open question this screen answered.** Throwing would have made
      // one corrupt record look like an empty queue; skipping it silently is
      // the `catch (_)` the design document refuses.
      await seed(tester, failWith: PrinterTransportCode.unreachable);
      await seedUnreadable(tester, <String>['CT-A7F-20260729-0044']);

      await _pump(tester, queue);

      expect(
        noticeStatus(tester, 'print-queue-unreadable'),
        AppStatus.problem,
      );
      expect(
        noticeMessage(tester, 'print-queue-unreadable'),
        startsWith('1 queued receipt could not be read'),
      );
      // And the readable one is still listed, which is the whole point.
      expect(find.text(_receipt), findsWidgets);
    });

    testWidgets('counts more than one in the plural', (tester) async {
      await seedUnreadable(tester, <String>[
        'CT-A7F-20260729-0044',
        'CT-A7F-20260729-0045',
      ]);

      await _pump(tester, queue);

      expect(
        noticeMessage(tester, 'print-queue-unreadable'),
        startsWith('2 queued receipts could not be read'),
      );
    });

    testWidgets('says nothing at all when everything parsed', (tester) async {
      await seed(tester, failWith: PrinterTransportCode.unreachable);

      await _pump(tester, queue);

      expect(find.byKey(const ValueKey('print-queue-unreadable')), findsNothing);
    });
  });

  testWidgets('lists every unfinished receipt and no finished one', (
    tester,
  ) async {
    await seedSent(tester, _receipt);
    await seed(
      tester,
      receiptNumber: _otherReceipt,
      failWith: PrinterTransportCode.unreachable,
    );

    await _pump(tester, queue);

    expect(find.text(_otherReceipt), findsWidgets);
    expect(find.text(_receipt), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  HivePrintJobQueue queue, {
  PrintJobRetry? onRetry,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: spiritTheme,
      home: Scaffold(
        body: TenantPrintQueuePanel(queue: queue, onRetry: onRetry),
      ),
    ),
  );
  // **Two pumps, not `pumpAndSettle`, and that is a finding rather than a
  // style choice.** Every panel test in this repository pumps twice; this one
  // was written with `pumpAndSettle` and hung for two minutes on the first case
  // with a row in it, then timed out. What never settles is inside the table
  // form of `RecordList`, which `test/ui/record_list_test.dart` settles
  // perfectly well on its own - so it is the *combination* that does it, and it
  // is recorded in `PLAN.md` rather than papered over here.
  await tester.pump();
  await tester.pump();
}

final class _FailingTransport implements PrinterTransport {
  const _FailingTransport(this.code);

  final String code;

  @override
  PrinterTransportCapability get capability =>
      const PrinterTransportCapability(
        kind: PrinterTransportKind.directTcp,
        endpointIsPrinter: true,
        label: 'Failing',
      );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async {}

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async =>
      throw PrinterTransportException(code);

  @override
  Future<void> dispose() async {}
}

final class _SendingTransport implements PrinterTransport {
  const _SendingTransport();

  @override
  PrinterTransportCapability get capability =>
      const PrinterTransportCapability(
        kind: PrinterTransportKind.directTcp,
        endpointIsPrinter: true,
        label: 'Sending',
      );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async {}

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async {}

  @override
  Future<void> dispose() async {}
}
