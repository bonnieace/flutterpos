import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late TenantPendingMutationStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tenant-mutations-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('mutations-test');
    store = TenantPendingMutationStore.fromBox(box);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'persists UID/tenant-scoped operations and blocks a tenant switch',
    () async {
      await store.enqueue(
        uid: 'owner-a',
        tenantId: 'tenant-a',
        operationId: 'expense-create-2026-09-01-token-a',
        kind: TenantPendingMutationKind.expenseCreate,
        targetPath: 'tenants/tenant-a/expenses/2026-09-01-token-a',
        payload: const <String, Object?>{
          'expenseId': '2026-09-01-token-a',
          'tenantId': 'tenant-a',
          'amountMinor': 500,
        },
      );

      final reopened = TenantPendingMutationStore.fromBox(box);
      final records = await reopened.recordsForSession(
        uid: 'owner-a',
        tenantId: 'tenant-a',
      );
      expect(records, hasLength(1));
      expect(records.single.state, TenantPendingMutationState.queued);
      expect(
        (await TenantPendingMutationSwitchStateSource(
          reopened,
        ).inspect(_session()))!.blocker,
        TenantSwitchBlocker.pendingWrites,
      );
      expect(
        await reopened.recordsForSession(uid: 'owner-a', tenantId: 'tenant-b'),
        isEmpty,
      );
    },
  );

  test(
    'worker confirms committed evidence and preserves same-path order',
    () async {
      for (final operation
          in <(String, TenantPendingMutationKind, Map<String, Object?>)>[
            (
              'expense-create-2026-09-01-token-a',
              TenantPendingMutationKind.expenseCreate,
              const <String, Object?>{'amountMinor': 500},
            ),
            (
              'expense-void-2026-09-01-token-a',
              TenantPendingMutationKind.expenseVoid,
              const <String, Object?>{'voidReason': 'entered twice'},
            ),
          ]) {
        await store.enqueue(
          uid: 'owner-a',
          tenantId: 'tenant-a',
          operationId: operation.$1,
          kind: operation.$2,
          targetPath: 'tenants/tenant-a/expenses/2026-09-01-token-a',
          payload: operation.$3,
        );
      }
      final gateway = _Gateway();
      await TenantPendingMutationWorker(
        store: store,
        submission: gateway,
        confirmation: gateway,
        workerId: 'device-a',
      ).run(_session());

      expect(gateway.submitted, <String>[
        'expense-create-2026-09-01-token-a',
        'expense-void-2026-09-01-token-a',
      ]);
      expect(
        (await store.recordsForSession(
          uid: 'owner-a',
          tenantId: 'tenant-a',
        )).map((record) => record.state),
        everyElement(TenantPendingMutationState.confirmed),
      );
    },
  );

  test(
    'a changed configuration is retained for administrator review',
    () async {
      final record = await store.enqueue(
        uid: 'owner-a',
        tenantId: 'tenant-a',
        operationId: 'config-branding-change-a',
        kind: TenantPendingMutationKind.brandingMerge,
        targetPath: 'tenants/tenant-a/configuration/branding',
        payload: const <String, Object?>{'companyName': 'Offline name'},
        replacedValueFingerprint: tenantConfigurationMutationFingerprint(
          const <String, Object?>{'companyName': 'Old name'},
        ),
      );
      final gateway = _Gateway()
        ..canonical = <String, Object?>{
          'companyName': 'Newer server name',
          'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
        };
      await TenantPendingMutationWorker(
        store: store,
        submission: gateway,
        confirmation: gateway,
        workerId: 'device-a',
      ).run(_session());

      final saved = (await store.recordsForSession(
        uid: 'owner-a',
        tenantId: 'tenant-a',
      )).single;
      expect(saved.operationId, record.operationId);
      expect(saved.state, TenantPendingMutationState.needsAttention);
      expect(gateway.submitted, isEmpty);
    },
  );

  test(
    'combined local-work evidence can acknowledge retained failures',
    () async {
      final record = await store.enqueue(
        uid: 'owner-a',
        tenantId: 'tenant-a',
        operationId: 'expense-create-review-a',
        kind: TenantPendingMutationKind.expenseCreate,
        targetPath: 'tenants/tenant-a/expenses/review-a',
        payload: const <String, Object?>{'amountMinor': 500},
      );
      await store.markRejected(record, 'permission_denied');
      final source = CombinedLocalWorkEvidenceSource(
        checkouts: const _NoCheckoutEvidence(),
        mutations: store,
      );

      final before = await source.summarize(_session());
      expect(before.mutations.rejected, 1);
      expect(
        before.mutations.reviewItems.single.operationId,
        record.operationId,
      );

      await source.acknowledge(_session(), record.operationId);

      expect((await source.summarize(_session())).mutations.total, 0);
    },
  );

  test('uncertain writes are confirmed canonically before retry', () async {
    final clock = _Clock(DateTime.utc(2026, 9, 1, 10));
    store = TenantPendingMutationStore.fromBox(box, clock: clock.call);
    await store.enqueue(
      uid: 'owner-a',
      tenantId: 'tenant-a',
      operationId: 'expense-create-uncertain-a',
      kind: TenantPendingMutationKind.expenseCreate,
      targetPath: 'tenants/tenant-a/expenses/uncertain-a',
      payload: const <String, Object?>{'amountMinor': 500},
    );
    final gateway = _UncertainGateway();
    final worker = TenantPendingMutationWorker(
      store: store,
      submission: gateway,
      confirmation: gateway,
      workerId: 'device-a',
    );

    await worker.run(_session());
    expect(gateway.submissions, 1);
    expect(
      (await _only(store)).state,
      TenantPendingMutationState.awaitingConfirmation,
    );

    await worker.run(_session());
    expect((await _only(store)).state, TenantPendingMutationState.queued);
    clock.advance(const Duration(seconds: 31));
    gateway.canonical = const <String, Object?>{'amountMinor': 500};

    await worker.run(_session());

    expect(
      gateway.submissions,
      1,
      reason: 'Canonical evidence prevents a replay.',
    );
    expect((await _only(store)).state, TenantPendingMutationState.confirmed);
  });

  test('an active lease is not stolen after process recreation', () async {
    final clock = _Clock(DateTime.utc(2026, 9, 1, 10));
    store = TenantPendingMutationStore.fromBox(box, clock: clock.call);
    final queued = await store.enqueue(
      uid: 'owner-a',
      tenantId: 'tenant-a',
      operationId: 'expense-create-leased-a',
      kind: TenantPendingMutationKind.expenseCreate,
      targetPath: 'tenants/tenant-a/expenses/leased-a',
      payload: const <String, Object?>{'amountMinor': 700},
    );
    await store.acquire(queued, leaseOwner: 'previous-process');
    final gateway = _Gateway();
    final worker = TenantPendingMutationWorker(
      store: store,
      submission: gateway,
      confirmation: gateway,
      workerId: 'new-process',
    );

    await worker.run(_session());
    expect(gateway.submitted, isEmpty);

    clock.advance(const Duration(minutes: 2, seconds: 1));
    await worker.run(_session());
    clock.advance(const Duration(seconds: 31));
    await worker.run(_session());

    expect(gateway.submitted, <String>['expense-create-leased-a']);
  });

  test('an unreachable target does not hold unrelated targets', () async {
    for (final id in <String>['a', 'b']) {
      await store.enqueue(
        uid: 'owner-a',
        tenantId: 'tenant-a',
        operationId: 'expense-create-parallel-$id',
        kind: TenantPendingMutationKind.expenseCreate,
        targetPath: 'tenants/tenant-a/expenses/parallel-$id',
        payload: <String, Object?>{'amountMinor': id == 'a' ? 100 : 200},
      );
    }
    final gateway = _ParallelGateway();
    final running = TenantPendingMutationWorker(
      store: store,
      submission: gateway,
      confirmation: gateway,
      workerId: 'device-a',
    ).run(_session());

    await gateway.otherStarted.future.timeout(const Duration(seconds: 2));

    expect(
      gateway.submitted,
      containsAll(<String>[
        'expense-create-parallel-a',
        'expense-create-parallel-b',
      ]),
    );
    gateway.release.complete();
    await running;
  });
}

TenantSession _session() => TenantSession.active(
  uid: 'owner-a',
  tenantId: 'tenant-a',
  role: TenantRole.owner,
);

final class _Gateway
    implements
        TenantMutationSubmissionGateway,
        TenantMutationConfirmationGateway {
  final List<String> submitted = <String>[];
  Map<String, Object?>? canonical;

  @override
  Future<Map<String, Object?>?> read(String targetPath) async => canonical;

  @override
  Future<TenantMutationSubmissionResult> submit(
    TenantPendingMutationRecord record,
  ) async {
    submitted.add(record.operationId);
    canonical = <String, Object?>{...?canonical, ...record.payload};
    return const TenantMutationSubmissionResult(
      TenantMutationSubmissionOutcome.committed,
    );
  }
}

final class _NoCheckoutEvidence implements CheckoutEvidenceSource {
  const _NoCheckoutEvidence();

  @override
  Future<CheckoutEvidenceSummary> summarize(TenantSession session) async =>
      const CheckoutEvidenceSummary();
}

Future<TenantPendingMutationRecord> _only(
  TenantPendingMutationStore store,
) async => (await store.recordsForSession(
  uid: 'owner-a',
  tenantId: 'tenant-a',
)).single;

final class _Clock {
  _Clock(this.value);

  DateTime value;

  DateTime call() => value;

  void advance(Duration duration) => value = value.add(duration);
}

final class _UncertainGateway
    implements
        TenantMutationSubmissionGateway,
        TenantMutationConfirmationGateway {
  int submissions = 0;
  Map<String, Object?>? canonical;

  @override
  Future<Map<String, Object?>?> read(String targetPath) async => canonical;

  @override
  Future<TenantMutationSubmissionResult> submit(
    TenantPendingMutationRecord record,
  ) async {
    submissions++;
    return const TenantMutationSubmissionResult(
      TenantMutationSubmissionOutcome.uncertain,
      'write_timeout',
    );
  }
}

final class _ParallelGateway
    implements
        TenantMutationSubmissionGateway,
        TenantMutationConfirmationGateway {
  final Completer<void> release = Completer<void>();
  final Completer<void> otherStarted = Completer<void>();
  final List<String> submitted = <String>[];

  @override
  Future<Map<String, Object?>?> read(String targetPath) async => null;

  @override
  Future<TenantMutationSubmissionResult> submit(
    TenantPendingMutationRecord record,
  ) async {
    submitted.add(record.operationId);
    if (record.operationId.endsWith('-a')) await release.future;
    if (record.operationId.endsWith('-b') && !otherStarted.isCompleted) {
      otherStarted.complete();
    }
    return const TenantMutationSubmissionResult(
      TenantMutationSubmissionOutcome.committed,
    );
  }
}
