import 'dart:async';
import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// A receipt number in the frozen shape `HiveCheckoutReceiptCounters` allocates.
const String _receipt = 'CT-A7F-20260729-0042';
const String _otherReceipt = 'CT-A7F-20260729-0043';
const String _tenant = 'tenant-a';
const List<int> _payload = <int>[27, 64, 72, 105, 10];

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HivePrintJobQueue queue;
  late PrinterEndpoint endpoint;
  late PrinterEndpoint otherEndpoint;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('print-jobs-test-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>(HivePrintJobQueue.boxName);
    queue = HivePrintJobQueue.fromBox(box);
    endpoint = PrinterEndpoint(host: '192.168.1.50', port: 9100);
    otherEndpoint = PrinterEndpoint(host: '192.168.1.51', port: 9100);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<PrintJobRecord> enqueue({
    String receiptNumber = _receipt,
    PrinterEndpoint? at,
  }) => queue.enqueue(
    tenantId: _tenant,
    receiptNumber: receiptNumber,
    endpoint: at ?? endpoint,
    bytes: _payload,
  );

  group('identity and idempotence', () {
    test('the receipt number is the key, so one sale is one job', () async {
      // §7: the receipt number is "unique per device per business date by
      // construction, which makes it a free idempotency key". Two enqueues for
      // one sale produce one job and therefore one delivery.
      final first = await enqueue();
      final second = await enqueue();

      expect(second.createdAt, first.createdAt);
      expect(queue.pending().jobs, hasLength(1));
      expect(box.keys, contains(_receipt));
    });

    test('two send calls for one receipt number produce one delivery', () async {
      final transport = _RecordingTransport();
      await enqueue();

      await queue.run(_receipt, transport: transport);
      // The second call finds the job already `printed` and does nothing: the
      // queue never re-sends on its own.
      await queue.run(_receipt, transport: transport);

      expect(transport.sends, hasLength(1));
      expect(queue.read(_receipt)!.state, PrintJobState.printed);
    });

    test('refuses a receipt number that is not the frozen shape', () async {
      await expectLater(
        queue.enqueue(
          tenantId: _tenant,
          receiptNumber: 'not-a-receipt',
          endpoint: endpoint,
          bytes: _payload,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('refuses an empty payload rather than dialling for nothing', () async {
      await expectLater(
        queue.enqueue(
          tenantId: _tenant,
          receiptNumber: _receipt,
          endpoint: endpoint,
          bytes: const <int>[],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the state machine', () {
    test('a successful run goes queued to printing to printed', () async {
      final transport = _RecordingTransport();
      final queued = await enqueue();
      expect(queued.state, PrintJobState.queued);
      expect(queued.attemptCount, 0);

      final printed = await queue.run(_receipt, transport: transport);

      expect(printed.state, PrintJobState.printed);
      expect(printed.attemptCount, 1);
      expect(printed.attentionReason, isNull);
      expect(transport.sends.single.bytes, _payload);
    });

    test('a failed run lands in needsAttention with the transports code', () async {
      // The transport throws a code; deciding what that means for the record
      // is the queue's, and the code is what gets persisted.
      final transport = _RecordingTransport(
        failWith: PrinterTransportCode.writeTimeout,
      );
      await enqueue();

      final failed = await queue.run(_receipt, transport: transport);

      expect(failed.state, PrintJobState.needsAttention);
      expect(failed.attentionReason, PrinterTransportCode.writeTimeout);
      expect(failed.attemptCount, 1);
    });

    test('an unknown throw still leaves the job out of printing', () async {
      // A job stuck in `printing` forever is unrecoverable without a restart,
      // so anything the transport throws has to land somewhere terminal.
      final transport = _RecordingTransport(failWith: 'not-a-transport-code');
      await enqueue();

      final failed = await queue.run(_receipt, transport: transport);

      expect(failed.state, PrintJobState.needsAttention);
    });

    test('every illegal move throws invalid_transition', () async {
      final transport = _RecordingTransport();
      await enqueue();
      await queue.run(_receipt, transport: transport);
      expect(queue.read(_receipt)!.state, PrintJobState.printed);

      // `printed` is terminal from the queue's side: a retry cannot leave it.
      await expectLater(
        queue.retry(_receipt),
        throwsA(const PrintJobException('invalid_transition')),
      );
      // And a reprint refuses anything that has not printed.
      await queue.enqueue(
        tenantId: _tenant,
        receiptNumber: _otherReceipt,
        endpoint: endpoint,
        bytes: _payload,
      );
      expect(
        () => queue.reprint(_otherReceipt, onReprint: (_) async {}),
        throwsA(const PrintJobException('invalid_transition')),
      );
    });

    test('a failed job can be retried back to queued', () async {
      await enqueue();
      await queue.run(
        _receipt,
        transport: _RecordingTransport(
          failWith: PrinterTransportCode.unreachable,
        ),
      );

      final retried = await queue.retry(_receipt);

      expect(retried.state, PrintJobState.queued);
      // The attempt count survives, because it is the record of how many times
      // this receipt has been tried rather than of the current run.
      expect(retried.attemptCount, 1);
      expect(retried.attentionReason, isNull);
    });

    test('an unknown receipt is a refusal rather than a null', () async {
      await expectLater(
        queue.run(_receipt, transport: _RecordingTransport()),
        throwsA(const PrintJobException('unknown_print_job')),
      );
    });
  });

  group('recovery', () {
    test('run really does leave the record in printing while it sends', () async {
      // The half of recovery that can be observed live: the durable record says
      // `printing` for the whole of the send, which is what makes an interrupted
      // job findable at all.
      final transport = _RecordingTransport(hang: true);
      await enqueue();
      unawaited(queue.run(_receipt, transport: transport));
      await transport.started.future;

      expect(queue.read(_receipt)!.state, PrintJobState.printing);

      transport.release();
    });

    test('a job interrupted in printing resumes as the same job', () async {
      // §9: "Recovery: a job interrupted in `printing` resumes as the same
      // job." A crash mid-send must not become a second receipt.
      //
      // **The crash is simulated by writing the record, not by hanging a
      // transport**, and that is the honest simulation rather than a shortcut:
      // after a process dies the only thing that exists is the box, and a test
      // that kept the original `run` alive would still be holding the endpoint
      // mutex it died inside. The test above proves the state this one starts
      // from is the state a real send leaves behind.
      final queued = await enqueue();
      await box.put(_receipt, <String, Object?>{
        ...queued.toMap(),
        'state': PrintJobState.printing.name,
        'attemptCount': 1,
      });

      final restarted = HivePrintJobQueue.fromBox(box);
      final resumed = await restarted.resumeInterrupted(_receipt);

      expect(resumed.state, PrintJobState.queued);
      expect(resumed.receiptNumber, _receipt);
      // The same job, not a second one: one key, and the attempt it already
      // made is still counted.
      expect(box.keys.where((key) => key == _receipt), hasLength(1));
      expect(resumed.attemptCount, 1);
      expect(resumed.createdAt, queued.createdAt);
    });

    test('resuming a job that is not interrupted changes nothing', () async {
      await enqueue();

      final untouched = await queue.resumeInterrupted(_receipt);

      expect(untouched.state, PrintJobState.queued);
    });
  });

  group('serialization', () {
    test('two jobs to one endpoint never overlap', () async {
      // One ESC/POS printer accepts one connection on :9100. Concurrent jobs
      // interleave their bytes or get refused.
      final transport = _RecordingTransport(delay: const Duration(milliseconds: 30));
      await enqueue();
      await enqueue(receiptNumber: _otherReceipt);

      await Future.wait(<Future<void>>[
        queue.run(_receipt, transport: transport),
        queue.run(_otherReceipt, transport: transport),
      ]);

      expect(transport.maximumConcurrent, 1);
      expect(transport.sends, hasLength(2));
    });

    test('two printers in one shop still run in parallel', () async {
      // The mutex is keyed by endpoint rather than by job, which is the whole
      // reason a second printer is not slowed down by the first.
      final transport = _RecordingTransport(delay: const Duration(milliseconds: 30));
      await enqueue();
      await enqueue(receiptNumber: _otherReceipt, at: otherEndpoint);

      await Future.wait(<Future<void>>[
        queue.run(_receipt, transport: transport),
        queue.run(_otherReceipt, transport: transport),
      ]);

      expect(transport.maximumConcurrent, 2);
    });
  });

  group('fail closed', () {
    test('a malformed durable record throws rather than resetting', () async {
      // Same rule as `malformed_receipt_counter`: bytes that cannot be trusted
      // must not be sent on the strength of the fields that did parse.
      await box.put(_receipt, <String, Object?>{'schemaVersion': 1});

      expect(
        () => queue.read(_receipt),
        throwsA(const PrintJobException('malformed_print_job')),
      );
    });

    test('a record that failed without saying why is malformed', () async {
      final good = await enqueue();
      await box.put(_receipt, <String, Object?>{
        ...good.toMap(),
        'state': PrintJobState.needsAttention.name,
        'attentionReason': null,
      });

      expect(
        () => queue.read(_receipt),
        throwsA(const PrintJobException('malformed_print_job')),
      );
    });

    test('a record whose bytes are not bytes is malformed', () async {
      final good = await enqueue();
      await box.put(_receipt, <String, Object?>{
        ...good.toMap(),
        'bytes': <Object?>[27, 'not a byte', 999],
      });

      expect(
        () => queue.read(_receipt),
        throwsA(const PrintJobException('malformed_print_job')),
      );
    });

    test('a record carrying an address we would refuse is malformed', () async {
      final good = await enqueue();
      await box.put(_receipt, <String, Object?>{
        ...good.toMap(),
        'host': 'http://printer',
      });

      expect(
        () => queue.read(_receipt),
        throwsA(const PrintJobException('malformed_print_job')),
      );
    });
  });

  group('reprint', () {
    test('is audited before it is re-queued', () async {
      // The audit record is written first, so a reprint that was not recorded
      // never happens. The opposite order loses the line exactly when it
      // matters, which is a crash mid-reprint.
      final order = <String>[];
      await enqueue();
      await queue.run(_receipt, transport: _RecordingTransport());

      final requeued = await queue.reprint(
        _receipt,
        onReprint: (job) async {
          order.add('audited');
          expect(job.state, PrintJobState.printed);
        },
      );
      order.add('requeued');

      expect(order, <String>['audited', 'requeued']);
      expect(requeued.state, PrintJobState.queued);
    });

    test('a refused audit leaves the job printed', () async {
      await enqueue();
      await queue.run(_receipt, transport: _RecordingTransport());

      await expectLater(
        queue.reprint(_receipt, onReprint: (_) async => throw StateError('no')),
        throwsA(isA<StateError>()),
      );
      expect(queue.read(_receipt)!.state, PrintJobState.printed);
    });
  });

  group('pending', () {
    test('lists everything unfinished, oldest first, and nothing printed', () async {
      await enqueue();
      await enqueue(receiptNumber: _otherReceipt);
      await queue.run(_receipt, transport: _RecordingTransport());

      final pending = queue.pending();

      expect(
        pending.jobs.map((job) => job.receiptNumber),
        <String>[_otherReceipt],
      );
      expect(pending.unreadable, 0);
      expect(pending.isEmpty, isFalse);
    });

    test('counts an unreadable record instead of hiding the readable ones', () async {
      // **The question this answers was open until the queue screen needed
      // it.** Throwing would have made one corrupt record look like an empty
      // queue on the only screen that could act on the rest; skipping it
      // silently is the `catch (_)` the design document refuses. So both are
      // reported, the way the profit display reports the lines it could not
      // use.
      await enqueue();
      await box.put('CT-A7F-20260729-0044', <String, Object?>{
        'schemaVersion': 1,
      });

      final pending = queue.pending();

      expect(pending.jobs.map((job) => job.receiptNumber), <String>[_receipt]);
      expect(pending.unreadable, 1);
    });

    test('an empty queue is empty, and a queue of only rubbish is not', () async {
      expect(queue.pending().isEmpty, isTrue);

      await box.put('CT-A7F-20260729-0044', <String, Object?>{
        'schemaVersion': 1,
      });

      // Nothing to show and something to say, which is not the same as nothing
      // at all.
      expect(queue.pending().isEmpty, isFalse);
      expect(queue.pending().jobs, isEmpty);
    });
  });
}

final class _SentPayload {
  const _SentPayload(this.endpoint, this.bytes);

  final PrinterEndpoint endpoint;
  final List<int> bytes;
}

/// A transport that records what it was asked to do, and can be made to fail,
/// to be slow, or to hang until released.
final class _RecordingTransport implements PrinterTransport {
  _RecordingTransport({this.failWith, this.delay, this.hang = false});

  final String? failWith;
  final Duration? delay;
  final bool hang;

  final List<_SentPayload> sends = <_SentPayload>[];
  final Completer<void> started = Completer<void>();
  final Completer<void> _held = Completer<void>();

  int _concurrent = 0;
  int maximumConcurrent = 0;

  void release() {
    if (!_held.isCompleted) _held.complete();
  }

  @override
  PrinterTransportCapability get capability =>
      const PrinterTransportCapability(
        kind: PrinterTransportKind.directTcp,
        endpointIsPrinter: true,
        label: 'Recording',
      );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async {}

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async {
    _concurrent++;
    if (_concurrent > maximumConcurrent) maximumConcurrent = _concurrent;
    if (!started.isCompleted) started.complete();
    try {
      if (hang) await _held.future;
      if (delay != null) await Future<void>.delayed(delay!);
      if (failWith != null) throw PrinterTransportException(failWith!);
      sends.add(_SentPayload(endpoint, List<int>.unmodifiable(bytes)));
    } finally {
      _concurrent--;
    }
  }

  @override
  Future<void> dispose() async {}
}
