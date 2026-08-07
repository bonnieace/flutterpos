import 'dart:async';
import 'dart:io';

import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('checkout sync signals', () {
    late CheckoutSyncSignals signals;

    setUp(() => signals = CheckoutSyncSignals());
    tearDown(() => signals.dispose());

    test('hands out one stream object, because the shell compares identity', () {
      // The routing shell resubscribes when `tenantRecoveryTriggers` changes
      // identity, and a broadcast controller builds a new stream object on
      // every read. An uncached stream would cancel and resubscribe on every
      // rebuild of the composition root.
      expect(identical(signals.syncRequests, signals.syncRequests), isTrue);
      expect(identical(signals.evidenceChanges, signals.evidenceChanges), isTrue);
    });

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

    test('a finished run reports evidence without asking for another run', () async {
      final requests = <Object?>[];
      final changes = <Object?>[];
      signals.syncRequests.listen(requests.add);
      signals.evidenceChanges.listen(changes.add);

      signals.reportEvidenceChanged();
      await pumpEventQueue();

      expect(requests, isEmpty);
      expect(changes, hasLength(1));
    });

    test('signalling after disposal is silent rather than fatal', () async {
      await signals.dispose();

      expect(signals.requestSyncAfterSave, returnsNormally);
      expect(signals.requestSyncAfterReconnect, returnsNormally);
      expect(signals.requestSyncAfterConfigurationChange, returnsNormally);
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
      // Exactly what the composition root does with the two ends.
      signals.syncRequests.listen((_) => worker.submitDueCheckouts());
      final sink = CheckoutSyncOnSaveDraftSink(
        delegate: _OutboxSink(outbox),
        signals: signals,
      );

      await sink.saveDraft(_request());
      await _settle();

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
      signals.syncRequests.listen((_) => worker.submitDueCheckouts());
      final sink = CheckoutSyncOnSaveDraftSink(
        delegate: _OutboxSink(outbox),
        signals: signals,
      );

      await sink.saveDraft(_request());
      await _settle();
      await sink.saveDraft(_request(checkoutId: 'checkout-b'));
      await _settle();
      release.complete();
      await _settle();

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
      signals.syncRequests.listen((_) => worker.submitDueCheckouts());
      final sink = CheckoutSyncOnSaveDraftSink(
        delegate: _OutboxSink(outbox),
        signals: signals,
      );

      await sink.saveDraft(_request());
      sessions.open(uid: 'user-a', membership: _membership(tenantId: 'tenant-b'));
      await _settle();

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
      signals.syncRequests.listen((trigger) => pass.run(
        refreshDerivedData: trigger is! CheckoutSaveSyncRequest,
      ));
      final sink = CheckoutSyncOnSaveDraftSink(
        delegate: _OutboxSink(outbox),
        signals: signals,
      );

      await sink.saveDraft(_request());
      await _settle();

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
}

Future<void> _settle() async {
  for (var turn = 0; turn < 20; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const String _deviceId = 'dev-0123456789abcdef0123456789abcdef';
final List<int> _encryptionKey = List<int>.generate(32, (index) => index);

TenantMembership _membership({String tenantId = 'tenant-a'}) => TenantMembership(
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
        'tender': request.tender.wireValue,
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
