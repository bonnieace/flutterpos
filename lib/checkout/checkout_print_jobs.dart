/// Durable print jobs: `docs/printer_transport.md` §7.
///
/// **This is the part the borrowed repository has no concept of.** It prints
/// fire-and-forget and returns a `bool`. Checkout here already survives being
/// offline and crashing — `checkout_outbox.dart`, `checkout_recovery.dart` —
/// and printing has to survive the same things.
///
/// **Storage.** An encrypted Hive box sharing the checkout outbox encryption
/// key, for the reason `checkout_receipt.dart` gives about its counters: a
/// queued receipt holds the same sale detail as the evidence it was printed
/// from, so **the two must share exactly one fate**. A key rotation must never
/// leave readable receipt bytes beside a wiped outbox.
///
/// **Identity is the receipt number, and that is the whole idempotency
/// design.** `HiveCheckoutReceiptCounters` has already allocated
/// `CT-A7F-20260729-0042`, unique per device per business date by construction.
/// Using it as the job key means a crash mid-print recovers into the **same**
/// job rather than a second one, with no extra identifier to invent, persist or
/// reconcile.
///
/// **Serialization is per endpoint, not per job.** One ESC/POS printer accepts
/// one connection on `:9100`; two concurrent jobs to one address interleave
/// their bytes or get refused. The mutex is the same `_operationTails` pattern
/// the outbox and the receipt counters already use, keyed by the address rather
/// than by the receipt, so two printers in one shop still run in parallel.
///
/// **Reaching `printed` means the queue never re-sends on its own.** A
/// duplicate receipt is a cash-handling problem, not a convenience. An operator
/// reprint is a separate deliberate act — see [HivePrintJobQueue.reprint].
library;

import 'dart:async';
import 'package:uzapay_pos/observability/app_telemetry.dart';

import 'package:hive/hive.dart';

import 'checkout_outbox.dart';
import 'checkout_print_transport_base.dart';
import 'checkout_receipt.dart';
import 'package:uzapay_pos/storage/device_storage.dart';

/// The states a print job moves through, mirroring [CheckoutOutboxState].
enum PrintJobState {
  /// Written durably, not yet attempted.
  queued,

  /// A send is in flight. A job found in this state after a restart was
  /// interrupted and is resumed as the same job.
  printing,

  /// The transport handed every byte off. **Terminal, and never re-sent
  /// automatically.**
  printed,

  /// Terminal failure. The reason is a [PrinterTransportCode].
  needsAttention,
}

/// Raised when durable print state cannot be trusted.
final class PrintJobException implements Exception {
  const PrintJobException(this.code);

  final String code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrintJobException && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'PrintJobException($code)';
}

typedef PrintJobClock = DateTime Function();

/// One receipt waiting to reach paper.
final class PrintJobRecord {
  const PrintJobRecord._({
    required this.tenantId,
    required this.receiptNumber,
    required this.host,
    required this.port,
    required this.kind,
    required this.bytes,
    required this.state,
    required this.attemptCount,
    required this.attentionReason,
    required this.createdAt,
    required this.updatedAt,
  });

  static const int schemaVersion = 1;

  final String tenantId;

  /// `CT-A7F-20260729-0042`. Both the identity and the idempotency key.
  final String receiptNumber;

  final String host;
  final int port;

  /// Network or Bluetooth, so a retry goes down the link the receipt was
  /// queued for.
  ///
  /// **Written only for Bluetooth, and read as network when absent**, so every
  /// record queued before Bluetooth existed parses exactly as it did, with no
  /// migration and no new schema version. The reverse holds as well: a build
  /// that predates Bluetooth reads a Bluetooth job's address as a host, refuses
  /// it as `malformed_print_job` and counts it unreadable - it never dials it.
  final PrinterEndpointKind kind;

  /// The finished ESC/POS payload. **This class does not build bytes** —
  /// `flutter_esc_pos_utils`' `Generator` does, and keeping that job out of
  /// here is `docs/printer_transport.md`'s scope line.
  final List<int> bytes;

  final PrintJobState state;
  final int attemptCount;

  /// A [PrinterTransportCode], set only in [PrintJobState.needsAttention].
  final String? attentionReason;

  final DateTime createdAt;
  final DateTime updatedAt;

  PrinterEndpoint get endpoint => _endpointOf(host, port, kind);

  static PrinterEndpoint _endpointOf(
    String host,
    int port,
    PrinterEndpointKind kind,
  ) => switch (kind) {
    PrinterEndpointKind.network => PrinterEndpoint(host: host, port: port),
    PrinterEndpointKind.bluetooth =>
      port == PrinterEndpoint.bluetoothPort
          ? PrinterEndpoint.bluetooth(host)
          : throw ArgumentError.value(port, 'port'),
  };

  Map<String, Object?> toMap() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'tenantId': tenantId,
    'receiptNumber': receiptNumber,
    'host': host,
    'port': port,
    if (kind == PrinterEndpointKind.bluetooth) 'kind': _bluetoothKind,
    'bytes': List<int>.unmodifiable(bytes),
    'state': state.name,
    'attemptCount': attemptCount,
    'attentionReason': attentionReason,
    'createdAtMs': createdAt.toUtc().millisecondsSinceEpoch,
    'updatedAtMs': updatedAt.toUtc().millisecondsSinceEpoch,
  };

  /// **Malformed durable records throw rather than being repaired by
  /// guessing.** Same rule as `malformed_receipt_counter`: a print job whose
  /// bytes cannot be trusted must not be sent to a printer on the strength of
  /// the fields that did parse.
  static PrintJobRecord fromMap(Object? raw) {
    if (raw is! Map) throw const PrintJobException('malformed_print_job');
    final map = Map<Object?, Object?>.from(raw);
    final receiptNumber = map['receiptNumber'];
    final tenantId = map['tenantId'];
    final host = map['host'];
    final port = map['port'];
    final kind = switch (map['kind']) {
      null => PrinterEndpointKind.network,
      _bluetoothKind => PrinterEndpointKind.bluetooth,
      _ => throw const PrintJobException('malformed_print_job'),
    };
    final bytes = map['bytes'];
    final state = _stateFromName(map['state']);
    final attemptCount = map['attemptCount'];
    final attentionReason = map['attentionReason'];
    final createdAtMs = map['createdAtMs'];
    final updatedAtMs = map['updatedAtMs'];
    if (map['schemaVersion'] != schemaVersion ||
        tenantId is! String ||
        receiptNumber is! String ||
        !checkoutReceiptNumberPattern.hasMatch(receiptNumber) ||
        host is! String ||
        port is! int ||
        bytes is! List ||
        bytes.any((byte) => byte is! int || byte < 0 || byte > 255) ||
        state == null ||
        attemptCount is! int ||
        attemptCount < 0 ||
        (attentionReason != null && attentionReason is! String) ||
        createdAtMs is! int ||
        updatedAtMs is! int) {
      throw const PrintJobException('malformed_print_job');
    }
    // A record that says it failed and does not say why is as untrustworthy as
    // one with unreadable bytes.
    if ((state == PrintJobState.needsAttention) != (attentionReason != null)) {
      throw const PrintJobException('malformed_print_job');
    }
    try {
      _endpointOf(host, port, kind);
    } on ArgumentError {
      throw const PrintJobException('malformed_print_job');
    }
    return PrintJobRecord._(
      tenantId: tenantId,
      receiptNumber: receiptNumber,
      host: host,
      port: port,
      kind: kind,
      bytes: List<int>.unmodifiable(bytes.cast<int>()),
      state: state,
      attemptCount: attemptCount,
      attentionReason: attentionReason as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs, isUtc: true),
    );
  }

  static const String _bluetoothKind = 'bluetooth';

  static PrintJobState? _stateFromName(Object? value) {
    if (value is! String) return null;
    for (final state in PrintJobState.values) {
      if (state.name == value) return state;
    }
    return null;
  }

  PrintJobRecord _moveTo(
    PrintJobState next, {
    required DateTime at,
    int? attemptCount,
    String? attentionReason,
  }) => PrintJobRecord._(
    tenantId: tenantId,
    receiptNumber: receiptNumber,
    host: host,
    port: port,
    kind: kind,
    bytes: bytes,
    state: next,
    attemptCount: attemptCount ?? this.attemptCount,
    attentionReason: attentionReason,
    createdAt: createdAt,
    updatedAt: at,
  );
}

/// The one legal move table. Anything not here throws `invalid_transition`.
///
/// **`printed` and `needsAttention` are both terminal from the queue's side.**
/// A job leaves `needsAttention` only by an operator retrying it, and leaves
/// `printed` only by an operator reprinting it — and both of those are explicit
/// entry points on the queue rather than transitions the runner can take.
const Map<PrintJobState, Set<PrintJobState>> _legalMoves =
    <PrintJobState, Set<PrintJobState>>{
      PrintJobState.queued: <PrintJobState>{PrintJobState.printing},
      PrintJobState.printing: <PrintJobState>{
        PrintJobState.printed,
        PrintJobState.needsAttention,
        // A restart finds an interrupted job in `printing` and resumes it as
        // the same job, which means moving it back to `queued`.
        PrintJobState.queued,
      },
      PrintJobState.printed: <PrintJobState>{},
      PrintJobState.needsAttention: <PrintJobState>{PrintJobState.queued},
    };

/// What a queue screen is given: the jobs it can show, and the count it cannot.
///
/// **The count is not decoration.** A screen that showed only [jobs] would
/// render an empty queue for a box holding one corrupt record and nine good
/// ones, which is the failure this type exists to make impossible to write.
final class PrintJobListing {
  const PrintJobListing({required this.jobs, required this.unreadable});

  /// Unfinished jobs, oldest first.
  final List<PrintJobRecord> jobs;

  /// How many durable records could not be parsed. **Say this out loud** — see
  /// [HivePrintJobQueue.pending].
  final int unreadable;

  bool get isEmpty => jobs.isEmpty && unreadable == 0;
}

/// The durable queue.
final class HivePrintJobQueue {
  HivePrintJobQueue._(this._box, this._clock);

  static const String boxName = 'checkout-print-jobs-v1';
  static const int encryptionKeyBytes = HiveCheckoutOutbox.encryptionKeyBytes;

  /// Keyed by **endpoint**, not by job: one printer accepts one connection, and
  /// two printers in one shop should still run in parallel.
  static final Map<String, Future<void>> _operationTails =
      <String, Future<void>>{};

  final Box<dynamic> _box;
  final PrintJobClock _clock;

  static Future<HivePrintJobQueue> open({
    required CheckoutOutboxEncryptionKeyProvider keyProvider,
    HiveInterface? hive,
    PrintJobClock? clock,
  }) async {
    final key = await keyProvider.loadOrCreateKey();
    if (key.length != encryptionKeyBytes) {
      throw const PrintJobException('invalid_encryption_key');
    }
    final box = await openBoxRepairingTornTail<dynamic>(
      hive ?? Hive,
      boxName,
      cipher: HiveAesCipher(List<int>.from(key)),
    );
    return HivePrintJobQueue._(box, clock ?? _utcNow);
  }

  /// Test and composition boundary for an already encrypted Hive box.
  factory HivePrintJobQueue.fromBox(Box<dynamic> box, {PrintJobClock? clock}) =>
      HivePrintJobQueue._(box, clock ?? _utcNow);

  /// Queues one receipt, or returns the job that already exists for it.
  ///
  /// **Idempotent by the receipt number**, which is the point of keying on it:
  /// calling this twice for one sale produces one job and therefore one
  /// delivery, whether the second call is a retry, a rebuild or a recovery.
  Future<PrintJobRecord> enqueue({
    required String tenantId,
    required String receiptNumber,
    required PrinterEndpoint endpoint,
    required List<int> bytes,
  }) async {
    // **`async`, so these arrive as a failed future rather than a synchronous
    // throw.** A `Future`-returning method that sometimes throws before it
    // returns one is a trap: `await queue.enqueue(...)` inside a `try` catches
    // it and `queue.enqueue(...).catchError(...)` does not.
    if (!checkoutReceiptNumberPattern.hasMatch(receiptNumber)) {
      throw ArgumentError.value(receiptNumber, 'receiptNumber');
    }
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'Nothing to print.');
    }
    return _serialized(endpoint, () async {
      final existing = _read(receiptNumber);
      if (existing != null) return existing;
      final now = _now();
      final record = PrintJobRecord._(
        tenantId: tenantId,
        receiptNumber: receiptNumber,
        host: endpoint.host,
        port: endpoint.port,
        kind: endpoint.kind,
        bytes: List<int>.unmodifiable(bytes),
        state: PrintJobState.queued,
        attemptCount: 0,
        attentionReason: null,
        createdAt: now,
        updatedAt: now,
      );
      await _box.put(receiptNumber, record.toMap());
      return record;
    });
  }

  /// Reads one job, or null. Throws `malformed_print_job` rather than
  /// answering null for a record it cannot trust.
  PrintJobRecord? read(String receiptNumber) => _read(receiptNumber);

  /// Every job that is not finished, oldest first, **and how many could not be
  /// read at all**.
  ///
  /// **This is the third answer, and it was an open question until the surface
  /// that needed it was built.** Two obvious options were both wrong. Skipping
  /// a malformed record silently is the `catch (_)`
  /// `docs/printer_transport.md` §2 refuses outright. Throwing — which this did
  /// first — is the fail-closed rule applied where it does harm: **one
  /// unreadable job would hide every readable one** from the only screen that
  /// could act on them, so a single corrupt record would look like an empty
  /// queue.
  ///
  /// So the listing carries both, and the surface states both. It is exactly
  /// the shape the profit display already uses: a figure, plus the count of the
  /// lines it could not use, and never a figure that quietly excludes them.
  ///
  /// **[tenantId] narrows it to one business, and every surface should pass
  /// one.** This box is keyed by receipt number and is the device's, not a
  /// tenant's - so an unfiltered listing shows the receipts of whichever
  /// businesses this device has served. A queued job records the tenant it was
  /// rung for; until 2026-09-19 nothing read it, and switching business left
  /// the badge counting, and the notifications page naming, another shop's
  /// receipt numbers - with a *Send again* beside each one.
  ///
  /// Null lists every job, which is what the queue's own tests and the
  /// device-wide recovery pass want. A surface a person is looking at is not
  /// one of those.
  PrintJobListing pending({String? tenantId}) {
    final records = <PrintJobRecord>[];
    var unreadable = 0;
    for (final key in _box.keys) {
      if (key is! String) continue;
      final PrintJobRecord? record;
      try {
        record = _read(key);
      } on PrintJobException {
        // **Counted for every business, because it cannot be attributed to
        // one.** A record that will not parse cannot be asked whose it is, and
        // a corrupt job hidden from every surface is the failure this listing
        // exists to prevent. The count is a number, never a receipt.
        unreadable++;
        continue;
      }
      if (record == null) continue;
      if (record.state == PrintJobState.printed) continue;
      if (tenantId != null && record.tenantId != tenantId) continue;
      records.add(record);
    }
    records.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return PrintJobListing(
      jobs: List<PrintJobRecord>.unmodifiable(records),
      unreadable: unreadable,
    );
  }

  /// Sends one queued job through [transport], moving it to `printed` or to
  /// `needsAttention` with the transport's own code.
  ///
  /// **The queue owns the state machine and the transport owns nothing.** The
  /// transport throws a code; deciding what that means for the record is here.
  Future<PrintJobRecord> run(
    String receiptNumber, {
    required PrinterTransport transport,
  }) async {
    final job = _require(receiptNumber);
    if (job.state == PrintJobState.printed) return job;
    return _serialized(job.endpoint, () async {
      final current = _require(receiptNumber);
      // Re-read inside the mutex: a concurrent runner may have finished it
      // between the check above and this line.
      if (current.state == PrintJobState.printed) return current;
      final telemetry = AppTelemetry.current;
      final operation = telemetry.start(
        'printing.receipt',
        screen: 'print_queue',
        context: {
          'tenant_id': current.tenantId,
          'receipt_number': current.receiptNumber,
          'attempt_number': current.attemptCount + 1,
        },
      );
      final started = await _move(
        current,
        PrintJobState.printing,
        attemptCount: current.attemptCount + 1,
      );
      try {
        telemetry.recordStep(operation, 'submitted');
        await telemetry.trace(
          operation,
          'send_to_printer',
          () => transport.send(started.endpoint, started.bytes),
        );
      } on PrinterTransportException catch (error, stackTrace) {
        AppTelemetry.captureHandled(
          error,
          stackTrace,
          operation: operation,
          boundary: 'printing.send',
          data: {
            'receipt_number': receiptNumber,
            'printer_host': started.host,
            'printer_port': started.port,
            'attempt_number': started.attemptCount,
          },
        );
        return _move(
          started,
          PrintJobState.needsAttention,
          attentionReason: error.code,
        );
      } catch (error, stackTrace) {
        AppTelemetry.captureHandled(
          error,
          stackTrace,
          operation: operation,
          boundary: 'printing.send',
          data: {
            'receipt_number': receiptNumber,
            'attempt_number': started.attemptCount,
          },
        );
        // An unknown throw is still a failed print and must not leave the job
        // stuck in `printing` forever.
        return _move(
          started,
          PrintJobState.needsAttention,
          attentionReason: PrinterTransportCode.unreachable,
        );
      }
      final printed = await _move(started, PrintJobState.printed);
      telemetry.recordStep(operation, 'confirmed');
      telemetry.finishOperation(operation);
      return printed;
    });
  }

  /// Returns an interrupted job to `queued` so it resumes as the same job.
  ///
  /// Called by recovery at start-up: a process that died mid-`send` leaves a
  /// record in `printing`, and the receipt number means the resumed job is the
  /// same one rather than a second delivery.
  Future<PrintJobRecord> resumeInterrupted(String receiptNumber) {
    final job = _require(receiptNumber);
    return _serialized(job.endpoint, () async {
      final current = _require(receiptNumber);
      if (current.state != PrintJobState.printing) return current;
      return _move(current, PrintJobState.queued);
    });
  }

  /// Returns a failed job to `queued` after an operator asked for another try.
  Future<PrintJobRecord> retry(String receiptNumber) {
    final job = _require(receiptNumber);
    return _serialized(job.endpoint, () async {
      final current = _require(receiptNumber);
      return _move(current, PrintJobState.queued);
    });
  }

  /// An operator's deliberate second copy of a receipt that already printed.
  ///
  /// **Separate from [retry], and it must be**: reaching `printed` means the
  /// queue never re-sends on its own, because a duplicate receipt is a
  /// cash-handling problem rather than a convenience. This is the only way past
  /// that, it is an explicit act, and `docs/printer_transport.md` §7 requires it
  /// to be **audited** — `receipt_reprinted` beside `stock_adjusted` and
  /// `return_verified_stock_restored`.
  ///
  /// **The audit write is not in this chunk and the reason is a boundary rather
  /// than an omission**: `audit_log.dart` states that "server code is its only
  /// writer", so `receipt_reprinted` is a Cloud Function and a server chunk.
  /// [onReprint] is the seam it will land on; until one is passed, a reprint
  /// still refuses to happen silently, because the caller must supply it.
  Future<PrintJobRecord> reprint(
    String receiptNumber, {
    required Future<void> Function(PrintJobRecord job) onReprint,
  }) async {
    final job = _require(receiptNumber);
    if (job.state != PrintJobState.printed) {
      throw const PrintJobException('invalid_transition');
    }
    return _serialized(job.endpoint, () async {
      final current = _require(receiptNumber);
      // The audit record is written **before** the job is re-queued, so a
      // reprint that was not recorded never happens. The opposite order loses
      // the audit line exactly when it matters, which is a crash mid-reprint.
      await onReprint(current);
      final now = _now();
      final requeued = current._moveTo(PrintJobState.queued, at: now);
      await _box.put(receiptNumber, requeued.toMap());
      return requeued;
    });
  }

  Future<void> close() => _box.close();

  PrintJobRecord _require(String receiptNumber) {
    final record = _read(receiptNumber);
    if (record == null) throw const PrintJobException('unknown_print_job');
    return record;
  }

  PrintJobRecord? _read(String receiptNumber) {
    final raw = _box.get(receiptNumber);
    if (raw == null) return null;
    return PrintJobRecord.fromMap(raw);
  }

  Future<PrintJobRecord> _move(
    PrintJobRecord job,
    PrintJobState next, {
    int? attemptCount,
    String? attentionReason,
  }) async {
    if (!(_legalMoves[job.state] ?? const <PrintJobState>{}).contains(next)) {
      throw const PrintJobException('invalid_transition');
    }
    final moved = job._moveTo(
      next,
      at: _now(),
      attemptCount: attemptCount,
      attentionReason: attentionReason,
    );
    await _box.put(job.receiptNumber, moved.toMap());
    return moved;
  }

  /// The clock, truncated to the millisecond the durable record stores.
  ///
  /// **Without this a record does not equal its own persisted form.** Hive
  /// holds `createdAtMs`, so a re-read loses the microseconds a `DateTime`
  /// carries, and a caller comparing what `enqueue` returned with what `read`
  /// answers would find two different timestamps for one job.
  DateTime _now() => DateTime.fromMillisecondsSinceEpoch(
    _clock().toUtc().millisecondsSinceEpoch,
    isUtc: true,
  );

  Future<T> _serialized<T>(
    PrinterEndpoint endpoint,
    Future<T> Function() action,
  ) async {
    final lockKey = '${_box.name}:$endpoint';
    final previous = _operationTails[lockKey] ?? Future<void>.value();
    final release = Completer<void>();
    _operationTails[lockKey] = release.future;
    try {
      await previous;
      return await action();
    } finally {
      release.complete();
      if (identical(_operationTails[lockKey], release.future)) {
        _operationTails.remove(lockKey);
      }
    }
  }
}

DateTime _utcNow() => DateTime.now().toUtc();
