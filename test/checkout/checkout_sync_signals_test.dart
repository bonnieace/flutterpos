import 'dart:async';
import 'dart:io';

import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('checkout sync signals', () {
    late CheckoutSyncSignals signals;

    setUp(() => signals = CheckoutSyncSignals());
    tearDown(() => signals.dispose());

    test(
      'hands out one stream object, because the shell compares identity',
      () {
        // The routing shell resubscribes when `tenantRecoveryTriggers` changes
        // identity, and a broadcast controller builds a new stream object on
        // every read. An uncached stream would cancel and resubscribe on every
        // rebuild of the composition root.
        expect(identical(signals.syncRequests, signals.syncRequests), isTrue);
        expect(
          identical(signals.evidenceChanges, signals.evidenceChanges),
          isTrue,
        );
      },
    );

    test('a save asks for a sync and says the evidence moved', () async {
      final requests = <Object?>[];
      final changes = <Object?>[];
      signals.syncRequests.listen(requests.add);
      signals.evidenceChanges.listen(changes.add);

      signals.requestSyncAfterSave();
      await pumpEventQueue();

      expect(requests.single, isA<CheckoutSaveSyncRequest>());
      expect(changes, hasLength(1));
    });

    test('a reconnect asks for everything, not just a submission', () async {
      final requests = <Object?>[];
      signals.syncRequests.listen(requests.add);

      signals.requestSyncAfterReconnect();
      await pumpEventQueue();

      // Null is the composition root's "no narrowing reason", which is what
      // lets a reconnect refresh derived data a save deliberately does not.
      expect(requests, [null]);
      expect(requests.single, isNot(isA<CheckoutSaveSyncRequest>()));
    });

    test('a published configuration asks for the same full pass', () async {
      final requests = <Object?>[];
      final changes = <Object?>[];
      signals.syncRequests.listen(requests.add);
      signals.evidenceChanges.listen(changes.add);

      signals.requestSyncAfterConfigurationChange();
      await pumpEventQueue();

      // Deliberately the unnarrowed reason rather than a save-shaped one: the
      // catalog refresh is the only thing that re-reads `configuration/checkout`,
      // and a save-shaped request skips it. No local checkout state moved, so
      // nothing asks a read-only surface to re-read.
      expect(requests, [null]);
      expect(requests.single, isNot(isA<CheckoutSaveSyncRequest>()));
      expect(changes, isEmpty);
    });

    test('a changed catalog asks for the same full pass', () async {
      final requests = <Object?>[];
      final changes = <Object?>[];
      signals.syncRequests.listen(requests.add);
      signals.evidenceChanges.listen(changes.add);

      signals.requestSyncAfterCatalogChange();
      await pumpEventQueue();

      // For the same reason: the catalog refresh is the only thing that
      // re-reads `products` and `categories`, and a save-shaped request skips
      // it - leaving this device unable to sell a product that now exists and
      // still able to sell one that no longer does.
      expect(requests, [null]);
      expect(requests.single, isNot(isA<CheckoutSaveSyncRequest>()));
      expect(changes, isEmpty);
    });

    test(
      'a finished run reports evidence without asking for another run',
      () async {
        final requests = <Object?>[];
        final changes = <Object?>[];
        signals.syncRequests.listen(requests.add);
        signals.evidenceChanges.listen(changes.add);

        signals.reportEvidenceChanged();
        await pumpEventQueue();

        expect(requests, isEmpty);
        expect(changes, hasLength(1));
      },
    );

    test('signalling after disposal is silent rather than fatal', () async {
      await signals.dispose();

      expect(signals.requestSyncAfterSave, returnsNormally);
      expect(signals.requestSyncAfterReconnect, returnsNormally);
      expect(signals.requestSyncAfterConfigurationChange, returnsNormally);
      expect(signals.requestSyncAfterCatalogChange, returnsNormally);
      expect(signals.reportEvidenceChanged, returnsNormally);
    });
  });

  group('sync-on-save draft sink', () {
    test('asks for a sync only after the sale is durable', () async {
      final signals = CheckoutSyncSignals();
      addTearDown(signals.dispose);
      final requests = <Object?>[];
      signals.syncRequests.listen(requests.add);
      final delegate = _RecordingSink();
      final sink = CheckoutSyncOnSaveDraftSink(
        delegate: delegate,
        signals: signals,
      );

      final saved = await sink.saveDraft(_request());
      await pumpEventQueue();

      expect(saved.checkoutId, 'checkout-a');
      expect(saved.receiptNumber, 'CT-A7F-20260802-0001');
      expect(delegate.requests, hasLength(1));
      expect(requests.single, isA<CheckoutSaveSyncRequest>());
    });

    test('passes the request through untouched', () async {
      final signals = CheckoutSyncSignals();
      addTearDown(signals.dispose);
      final delegate = _RecordingSink();
      final request = _request();

      await CheckoutSyncOnSaveDraftSink(
        delegate: delegate,
        signals: signals,
      ).saveDraft(request);

      expect(identical(delegate.requests.single, request), isTrue);
    });

    test('a refused save asks for nothing and refuses identically', () async {
      final signals = CheckoutSyncSignals();
      addTearDown(signals.dispose);
      final requests = <Object?>[];
      signals.syncRequests.listen(requests.add);
      final sink = CheckoutSyncOnSaveDraftSink(
        delegate: const _RefusingSink('no_open_shift'),
        signals: signals,
      );

      await expectLater(
        sink.saveDraft(_request()),
        throwsA(
          isA<CheckoutDraftException>().having(
            (error) => error.code,
            'code',
            'no_open_shift',
          ),
        ),
      );
      await pumpEventQueue();

      expect(requests, isEmpty);
    });

    test('a failed signal never turns a durable sale into a refusal', () async {
      // The sale is already on disk. Reporting this as a failed save would send
      // the cashier to ring the same sale up twice, and the reconnect trigger
      // still submits it.
      final signals = CheckoutSyncSignals();
      await signals.dispose();
      final delegate = _RecordingSink();

      final saved = await CheckoutSyncOnSaveDraftSink(
        delegate: delegate,
        signals: signals,
      ).saveDraft(_request());

      expect(saved.checkoutId, 'checkout-a');
      expect(delegate.requests, hasLength(1));
    });
  });

  _seamGroup();
}

/// The wiring `main.dart` performs, proved end to end over a real encrypted
/// outbox and a real submission worker.
void _seamGroup() {
  group('a saved sale reaches the server without a restart', () {
    late Directory directory;
    late Box<dynamic> box;
    late HiveCheckoutOutbox outbox;
    late TenantSessionController sessions;
    late CheckoutSyncSignals signals;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('checkout-seam-test-');
      Hive.init(directory.path);
      box = await Hive.openBox<dynamic>(
        'checkout-seam-test',
        encryptionCipher: HiveAesCipher(_encryptionKey),
        crashRecovery: false,
      );
      outbox = HiveCheckoutOutbox.fromBox(box);
      sessions = TenantSessionController()
        ..open(uid: 'user-a', membership: _membership());
      signals = CheckoutSyncSignals();
    });

    tearDown(() async {
      await signals.dispose();
      sessions.dispose();
      await Hive.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('one save submits it, and the record was durable first', () async {
      final durableWhenSubmitted = <CheckoutOutboxState>[];
      final gateway = _FakeGateway((submission) async {
        final record = await outbox.read(
          uid: 'user-a',
          tenantId: 'tenant-a',
          checkoutId: submission.checkoutId,
        );
        durableWhenSubmitted.add(record!.state);
        return const CheckoutSubmissionResult.committed();
      });
      final worker = CheckoutSubmissionWorker(
        sessionController: sessions,
        outbox: outbox,
        submissionGateway: gateway,
        isOnline: () async => true,
      );
      // Exactly what the composition root does with the two ends. Holding the
      // run it starts is the test's own business: the listener still fires and
      // forgets, and the future is how this test knows the run is over instead
      // of guessing at event-loop turns.
      final runs = <Future<Object?>>[];
      signals.syncRequests.listen((_) => runs.add(worker.submitDueCheckouts()));
      final sink = CheckoutSyncOnSaveDraftSink(
        delegate: _OutboxSink(outbox),
        signals: signals,
      );

      await sink.saveDraft(_request());
      await _runsFinished(runs, count: 1);

      // Before this seam existed the worker ran only on session open and on a
      // reconnect, so this record stayed saved_offline until the next restart.
      expect(gateway.submissions, hasLength(1));
      expect(durableWhenSubmitted, [CheckoutOutboxState.submitting]);
      final stored = await outbox.read(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-a',
      );
      expect(stored!.state, CheckoutOutboxState.awaitingConfirmation);
    });

    test('a save during an in-flight run submits once per sale', () async {
      final release = Completer<void>();
      var first = true;
      final gateway = _FakeGateway((_) async {
        if (first) {
          first = false;
          await release.future;
        }
        return const CheckoutSubmissionResult.committed();
      });
      final worker = CheckoutSubmissionWorker(
        sessionController: sessions,
        outbox: outbox,
        submissionGateway: gateway,
        isOnline: () async => true,
      );
      final runs = <Future<Object?>>[];
      signals.syncRequests.listen((_) => runs.add(worker.submitDueCheckouts()));
      final sink = CheckoutSyncOnSaveDraftSink(
        delegate: _OutboxSink(outbox),
        signals: signals,
      );

      await sink.saveDraft(_request());
      await _settleUntil(
        'the first sale was in flight at the gateway',
        () => gateway.submissions.length == 1,
      );
      await sink.saveDraft(_request(checkoutId: 'checkout-b'));
      // The second save must reach the worker while the first run still holds
      // it: that refusal is what sets the rerun this test is really about. Run
      // 1 is still blocked in the gateway, so only run 2 can be awaited here.
      await _settleUntil(
        'the second save had asked for its own run',
        () => runs.length == 2,
      );
      await runs[1];
      release.complete();
      await runs[0];
      // The rerun the worker schedules for itself is the one wait in this group
      // with no future to hold, so it is the one wait that polls. It waits on the
      // rerun's *last* write rather than on its submission, so the run is over
      // before `tearDown` closes the box under it.
      await _settleUntil(
        'the coalesced rerun had submitted and recorded the second sale',
        () async =>
            (await outbox.read(
              uid: 'user-a',
              tenantId: 'tenant-a',
              checkoutId: 'checkout-b',
            ))?.state ==
            CheckoutOutboxState.awaitingConfirmation,
      );

      // The lease and the worker's own coalescing both hold: two sales, two
      // commits, and neither sale committed twice.
      expect(
        gateway.submissions.map((submission) => submission.checkoutId).toList()
          ..sort(),
        ['checkout-a', 'checkout-b'],
      );
    });

    test('a save is not submitted for a session the device has left', () async {
      final gateway = _FakeGateway(
        (_) async => const CheckoutSubmissionResult.committed(),
      );
      final worker = CheckoutSubmissionWorker(
        sessionController: sessions,
        outbox: outbox,
        submissionGateway: gateway,
        isOnline: () async => true,
      );
      final runs = <Future<Object?>>[];
      signals.syncRequests.listen((_) => runs.add(worker.submitDueCheckouts()));
      final sink = CheckoutSyncOnSaveDraftSink(
        delegate: _OutboxSink(outbox),
        signals: signals,
      );

      await sink.saveDraft(_request());
      sessions.open(
        uid: 'user-a',
        membership: _membership(tenantId: 'tenant-b'),
      );
      // A negative assertion needs the run to be over rather than merely
      // unlikely, which is the other thing counting turns could not give it.
      await _runsFinished(runs, count: 1);

      expect(gateway.submissions, isEmpty);
      final stored = await outbox.read(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-a',
      );
      expect(stored!.state, CheckoutOutboxState.savedOffline);
    });

    test('one pass also confirms it, so the shift can be closed', () async {
      final submissions = _FakeGateway(
        (_) async => const CheckoutSubmissionResult.committed(),
      );
      final confirmations = _FakeConfirmationGateway();
      final pass = CheckoutSyncPass(
        recover: CheckoutRecoveryCoordinator(
          sessionController: sessions,
          outbox: outbox,
          confirmationGateway: confirmations,
        ).recoverSelectedSession,
        submit: CheckoutSubmissionWorker(
          sessionController: sessions,
          outbox: outbox,
          submissionGateway: submissions,
          isOnline: () async => true,
        ).submitDueCheckouts,
        refreshCatalog: () async {},
        reportEvidenceChanged: () {},
      );
      // Exactly what the composition root wires, including the trigger's effect
      // on derived data.
      final passes = <Future<Object?>>[];
      signals.syncRequests.listen(
        (trigger) => passes.add(
          pass.run(refreshDerivedData: trigger is! CheckoutSaveSyncRequest),
        ),
      );
      final sink = CheckoutSyncOnSaveDraftSink(
        delegate: _OutboxSink(outbox),
        signals: signals,
      );

      await sink.saveDraft(_request());
      // The pass settles the record before its own future completes, so this is
      // the whole of the wait. This assertion is the one that used to fail
      // roughly one full-suite run in seven; see `_settleUntil` for why.
      await _runsFinished(passes, count: 1);

      // Observed on a real device before the second recovery existed: the sale
      // reached Firestore immediately and stopped at `awaiting_confirmation`, so
      // the shift reported it unsynchronized and refused to close until the app
      // was restarted.
      final stored = await outbox.read(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-a',
      );
      expect(stored!.state, CheckoutOutboxState.confirmed);
      expect(submissions.submissions, hasLength(1));
      // The first recovery had nothing to settle; only the second one did.
      expect(confirmations.checked, ['checkout-a']);
    });
  });

  _slowDiskGroup();
}

/// The flake above, made permanent.
///
/// The failure this group exists for was never reproducible on demand: it needed
/// a Hive write to take longer than twenty `Duration.zero` turns, which happened
/// roughly one full-suite run in seven and never once in fifteen runs of the file
/// alone. Delaying every write past any number of zero-duration turns makes that
/// rare condition the only condition, so a wait that counts turns instead of
/// waiting for the work fails here every single time.
///
/// It asserts nothing the seam group does not already assert. Its whole job is to
/// fail if this file ever goes back to guessing.
void _slowDiskGroup() {
  group('a slow disk decides nothing about whether the seam worked', () {
    late Directory directory;
    late Box<dynamic> box;
    late HiveCheckoutOutbox outbox;
    late TenantSessionController sessions;
    late CheckoutSyncSignals signals;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('checkout-slow-test-');
      Hive.init(directory.path);
      box = await Hive.openBox<dynamic>(
        'checkout-slow-disk-test',
        encryptionCipher: HiveAesCipher(_encryptionKey),
        crashRecovery: false,
      );
      outbox = HiveCheckoutOutbox.fromBox(_SlowBox(box, _slowWrite));
      sessions = TenantSessionController()
        ..open(uid: 'user-a', membership: _membership());
      signals = CheckoutSyncSignals();
    });

    tearDown(() async {
      await signals.dispose();
      sessions.dispose();
      await Hive.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('a save still ends confirmed when every write is slow', () async {
      final confirmations = _FakeConfirmationGateway();
      final pass = CheckoutSyncPass(
        recover: CheckoutRecoveryCoordinator(
          sessionController: sessions,
          outbox: outbox,
          confirmationGateway: confirmations,
        ).recoverSelectedSession,
        submit: CheckoutSubmissionWorker(
          sessionController: sessions,
          outbox: outbox,
          submissionGateway: _FakeGateway(
            (_) async => const CheckoutSubmissionResult.committed(),
          ),
          isOnline: () async => true,
        ).submitDueCheckouts,
        refreshCatalog: () async {},
        reportEvidenceChanged: () {},
      );
      final passes = <Future<Object?>>[];
      signals.syncRequests.listen(
        (trigger) => passes.add(
          pass.run(refreshDerivedData: trigger is! CheckoutSaveSyncRequest),
        ),
      );
      final sink = CheckoutSyncOnSaveDraftSink(
        delegate: _OutboxSink(outbox),
        signals: signals,
      );

      await sink.saveDraft(_request());
      await _runsFinished(passes, count: 1);

      final stored = await outbox.read(
        uid: 'user-a',
        tenantId: 'tenant-a',
        checkoutId: 'checkout-a',
      );
      expect(stored!.state, CheckoutOutboxState.confirmed);
    });
  });
}

/// Longer than any plausible run of zero-duration turns, and short enough that
/// the four writes one save performs still cost well under a second.
const Duration _slowWrite = Duration(milliseconds: 60);

/// A real Hive box whose writes take a visible amount of time.
///
/// Only the five members [HiveCheckoutOutbox] uses are delegated; anything else
/// this test reaches for should be a loud failure rather than a silent default,
/// which is what the inherited `noSuchMethod` gives.
final class _SlowBox implements Box<dynamic> {
  _SlowBox(this._delegate, this._writeDelay);

  final Box<dynamic> _delegate;
  final Duration _writeDelay;

  @override
  String get name => _delegate.name;

  @override
  Iterable<dynamic> get keys => _delegate.keys;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _delegate.get(key, defaultValue: defaultValue);

  @override
  Future<void> put(dynamic key, dynamic value) async {
    await Future<void>.delayed(_writeDelay);
    await _delegate.put(key, value);
  }

  @override
  Future<void> close() => _delegate.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// How long a wait in this file is allowed to take before it is a failure.
///
/// Generous on purpose: it is not a performance budget, it is the point past
/// which the seam is broken rather than slow.
const Duration _settleTimeout = Duration(seconds: 10);

/// Waits until [expectation] holds, or fails saying what it was waiting for.
///
/// **Nothing in this group counts event-loop turns, and this is why.** The seam
/// runs over a real encrypted Hive box on a real filesystem, so every state
/// change costs a file write dispatched to the IO thread pool. A fixed number of
/// `Duration.zero` turns is therefore not a wait at all - it is a race against
/// the disk, and it is one the disk sometimes wins.
///
/// Measured on 2026-08-07, one save at a time, reading the record after every
/// turn: the three writes a save sets off - `beginSubmission`,
/// `markAwaitingConfirmation`, `recordConfirmation` - settle by turn 3 in the
/// median case, but the tail of 172 runs reached turn 19 once and turn 26 once.
/// This file used to allow exactly 20, which is precisely how one full-suite run
/// in seven ended with the sale still `awaiting_confirmation` and no fault in
/// any of the code it was testing. Neither the outbox's static per-box lock nor
/// the submission pipeline was involved: the transitions all happened, late.
///
/// So a positive assertion waits for the run it is about to assert on to
/// *finish*, and the one wait with no future to hold - a rerun the worker
/// schedules for itself - polls for a condition under a wall-clock deadline.
/// A genuinely broken seam still fails, just after [_settleTimeout].
Future<void> _settleUntil(
  String expectation,
  FutureOr<bool> Function() satisfied,
) async {
  final deadline = DateTime.now().add(_settleTimeout);
  while (!await satisfied()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Timed out after ${_settleTimeout.inSeconds}s waiting until '
        '$expectation.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Waits until [count] runs have been asked for and every one of them is over.
///
/// The listener fires and forgets exactly as the composition root does; the
/// futures are the test's own, and holding them is what makes this a wait
/// rather than a guess.
Future<void> _runsFinished(
  List<Future<Object?>> runs, {
  required int count,
}) async {
  await _settleUntil(
    'the save had asked for $count sync run(s)',
    () => runs.length >= count,
  );
  await Future.wait<Object?>(runs.take(count));
}

const String _deviceId = 'dev-0123456789abcdef0123456789abcdef';
final List<int> _encryptionKey = List<int>.generate(32, (index) => index);

TenantMembership _membership({String tenantId = 'tenant-a'}) =>
    TenantMembership(
      tenantId: tenantId,
      tenantName: tenantId,
      tenantSlug: tenantId,
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

/// Writes the frozen payload the submission worker parses, so the seam is
/// proved over real durable evidence rather than a stubbed save.
final class _OutboxSink implements CheckoutDraftSink {
  const _OutboxSink(this._outbox);

  final HiveCheckoutOutbox _outbox;

  @override
  Future<CheckoutSavedDraft> saveDraft(CheckoutDraftRequest request) async {
    final checkoutId = request.lines.single.productId == 'product-b'
        ? 'checkout-b'
        : 'checkout-a';
    final receiptNumber = formatCheckoutReceiptNumber(
      deviceId: _deviceId,
      businessDate: '2026-08-02',
      sequence: 7,
    );
    await _outbox.saveOffline(
      uid: 'user-a',
      tenantId: 'tenant-a',
      checkoutId: checkoutId,
      payload: <String, Object?>{
        'schemaVersion': checkoutSalePayloadSchemaVersion,
        'checkoutId': checkoutId,
        'tenantId': 'tenant-a',
        'soldById': 'user-a',
        'currency': 'KES',
        'businessDate': '2026-08-02',
        'createdAtMs': 1785484800000,
        'shiftId': 'shift-a',
        'deviceId': _deviceId,
        'receiptNumber': receiptNumber,
        'receiptSequence': 7,
        if (request.tender != null) 'tender': request.tender!.wireValue,
        'items': <Map<String, Object?>>[
          {
            'productId': request.lines.single.productId,
            'name': 'Coffee',
            'quantity': request.lines.single.quantity,
            'unitPriceMinor': 25000,
          },
        ],
        'subtotalMinor': 25000 * request.lines.single.quantity,
        'discountMinor': 0,
        'totalMinor': 25000 * request.lines.single.quantity,
      },
    );
    return CheckoutSavedDraft(
      checkoutId: checkoutId,
      receiptNumber: receiptNumber,
    );
  }
}

/// Answers that the server holds exactly the sale the record describes, which is
/// what a real confirmation read finds immediately after an acknowledged commit.
final class _FakeConfirmationGateway implements CheckoutConfirmationGateway {
  final List<String> checked = <String>[];

  @override
  Future<CheckoutConfirmationResult> check(CheckoutOutboxRecord record) async {
    checked.add(record.checkoutId);
    return CheckoutConfirmationResult.matching(record.payloadHash);
  }
}

final class _FakeGateway implements CheckoutSubmissionGateway {
  _FakeGateway(this.handler);

  final Future<CheckoutSubmissionResult> Function(CheckoutSaleSubmission)
  handler;
  final List<CheckoutSaleSubmission> submissions = <CheckoutSaleSubmission>[];

  @override
  Future<CheckoutSubmissionResult> submit(CheckoutSaleSubmission submission) {
    submissions.add(submission);
    return handler(submission);
  }
}

CheckoutDraftRequest _request({String checkoutId = 'checkout-a'}) =>
    CheckoutDraftRequest(
      tender: CheckoutTender.cash,
      lines: [
        CheckoutDraftLineRequest(
          productId: checkoutId == 'checkout-b' ? 'product-b' : 'product-a',
          quantity: 1,
        ),
      ],
    );

final class _RecordingSink implements CheckoutDraftSink {
  final List<CheckoutDraftRequest> requests = <CheckoutDraftRequest>[];

  @override
  Future<CheckoutSavedDraft> saveDraft(CheckoutDraftRequest request) async {
    requests.add(request);
    return const CheckoutSavedDraft(
      checkoutId: 'checkout-a',
      receiptNumber: 'CT-A7F-20260802-0001',
    );
  }
}

final class _RefusingSink implements CheckoutDraftSink {
  const _RefusingSink(this.code);

  final String code;

  @override
  Future<CheckoutSavedDraft> saveDraft(CheckoutDraftRequest request) async =>
      throw CheckoutDraftException(code);
}
