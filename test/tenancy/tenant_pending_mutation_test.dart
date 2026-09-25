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

  group('an unanswered stock adjustment', () {
    // Seen on SIT 2026-09-25. An adjustment whose send got no answer was only
    // ever sent again by the *second* pass after its retry fell due: the first
    // read the product back, which can never hold an adjustment, and pushed the
    // retry out again. An offline write-off sat unsent for three hours, and an
    // online one was counted twice on the product until two reconnects.
    Future<void> queueAdjustment() => store.enqueue(
      uid: 'owner-a',
      tenantId: 'tenant-a',
      operationId: 'stock-adjust-adjust-stock-abcdefgh',
      kind: TenantPendingMutationKind.stockAdjust,
      targetPath: 'tenants/tenant-a/products/pd_abc',
      payload: const <String, Object?>{
        'tenantId': 'tenant-a',
        'productId': 'pd_abc',
        'quantityDelta': -1,
        'type': 'damage',
        'reason': 'Broken in transit',
        'requestId': 'adjust-stock-abcdefgh',
      },
    );

    test('is sent again on the first pass its retry is due', () async {
      final clock = _Clock(DateTime.utc(2026, 9, 1, 10));
      store = TenantPendingMutationStore.fromBox(box, clock: clock.call);
      await queueAdjustment();
      final gateway = _AnswersSecondTime(
        product: const <String, Object?>{'quantity': 67},
      );
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

      clock.advance(const Duration(seconds: 31));
      await worker.run(_session());

      // Sending it again is the confirmation: the server settles a repeated
      // request ID with the answer it already gave, and moves no stock twice.
      expect(gateway.submissions, 2);
      expect((await _only(store)).state, TenantPendingMutationState.confirmed);
    });

    test('asks for a pass when its retry falls due', () async {
      final clock = _Clock(DateTime.utc(2026, 9, 1, 10));
      store = TenantPendingMutationStore.fromBox(box, clock: clock.call);
      await queueAdjustment();
      final gateway = _AnswersSecondTime(
        product: const <String, Object?>{'quantity': 67},
      );
      final timers = _Timers();
      var woken = 0;
      final worker = TenantPendingMutationWorker(
        store: store,
        submission: gateway,
        confirmation: gateway,
        workerId: 'device-a',
        onRetryDue: () => woken++,
        timer: timers.call,
      );

      await worker.run(_session());

      // Nothing else would come: no reconnect, no sale, no catalog change.
      expect(timers.requested, <Duration>[const Duration(seconds: 30)]);
      expect(woken, 0);
      timers.fire();
      expect(woken, 1);
    });

    test('an adjustment left mid-send is sent again at once', () async {
      // What a crash leaves: the record says it was being sent, and the lease
      // it was sent under has run out.
      final clock = _Clock(DateTime.utc(2026, 9, 1, 10));
      store = TenantPendingMutationStore.fromBox(box, clock: clock.call);
      await queueAdjustment();
      await store.acquire(await _only(store), leaseOwner: 'previous-process');
      clock.advance(const Duration(minutes: 2, seconds: 1));
      final gateway = _Gateway();

      await TenantPendingMutationWorker(
        store: store,
        submission: gateway,
        confirmation: gateway,
        workerId: 'new-process',
      ).run(_session());

      expect(gateway.submitted, <String>['stock-adjust-adjust-stock-abcdefgh']);
      expect((await _only(store)).state, TenantPendingMutationState.confirmed);
    });
  });

  group('the retry wake', () {
    test('is not asked for when nothing waits on the clock', () async {
      await store.enqueue(
        uid: 'owner-a',
        tenantId: 'tenant-a',
        operationId: 'expense-create-settled-a',
        kind: TenantPendingMutationKind.expenseCreate,
        targetPath: 'tenants/tenant-a/expenses/settled-a',
        payload: const <String, Object?>{'amountMinor': 500},
      );
      final timers = _Timers();
      final gateway = _Gateway();

      await TenantPendingMutationWorker(
        store: store,
        submission: gateway,
        confirmation: gateway,
        workerId: 'device-a',
        onRetryDue: () {},
        timer: timers.call,
      ).run(_session());

      expect(gateway.submitted, <String>['expense-create-settled-a']);
      expect(timers.requested, isEmpty);
    });

    test('is asked for when a send fails outright', () async {
      final clock = _Clock(DateTime.utc(2026, 9, 1, 10));
      store = TenantPendingMutationStore.fromBox(box, clock: clock.call);
      await store.enqueue(
        uid: 'owner-a',
        tenantId: 'tenant-a',
        operationId: 'expense-create-failing-a',
        kind: TenantPendingMutationKind.expenseCreate,
        targetPath: 'tenants/tenant-a/expenses/failing-a',
        payload: const <String, Object?>{'amountMinor': 500},
      );
      final timers = _Timers();

      await TenantPendingMutationWorker(
        store: store,
        submission: const _Throws(),
        confirmation: const _Throws(),
        workerId: 'device-a',
        onRetryDue: () {},
        timer: timers.call,
      ).run(_session());

      expect((await _only(store)).state, TenantPendingMutationState.queued);
      expect(timers.requested, <Duration>[const Duration(seconds: 30)]);
    });
  });

  group('a supplier created here', () {
    // Seen on SIT 2026-09-25: a supplier added online was missing from every
    // offline list until a list was opened online again. Once its create is
    // confirmed the queue stops drawing it, and nothing had read the supplier
    // the server wrote, so the device held no copy of it.
    Future<void> queueSupplier() => store.enqueue(
      uid: 'owner-a',
      tenantId: 'tenant-a',
      operationId: 'supplier-create-sp_abc',
      kind: TenantPendingMutationKind.supplierCreate,
      targetPath: 'tenants/tenant-a/suppliers/sp_abc',
      payload: const <String, Object?>{'name': 'ABC', 'active': true},
    );

    test('is read back from the server once it lands', () async {
      await queueSupplier();
      final gateway = _ReadLog();

      await TenantPendingMutationWorker(
        store: store,
        submission: gateway,
        confirmation: gateway,
        workerId: 'device-a',
      ).run(_session());

      expect((await _only(store)).state, TenantPendingMutationState.confirmed);
      expect(gateway.events, <String>[
        'submit supplier-create-sp_abc',
        'read tenants/tenant-a/suppliers/sp_abc',
      ]);
    });

    test('a read that fails there changes nothing about the create', () async {
      await queueSupplier();
      final gateway = _ReadLog(readFails: true);

      await TenantPendingMutationWorker(
        store: store,
        submission: gateway,
        confirmation: gateway,
        workerId: 'device-a',
      ).run(_session());

      expect((await _only(store)).state, TenantPendingMutationState.confirmed);
      expect(gateway.events, hasLength(2));
    });
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

  group('a product waits for the category it names', () {
    /// Queues a category and a product filed under it, the way a device that
    /// added both offline holds them.
    Future<void> queueBoth({required String categoryId}) async {
      await store.enqueue(
        uid: 'owner-a',
        tenantId: 'tenant-a',
        operationId: 'category-create-$categoryId',
        kind: TenantPendingMutationKind.categoryCreate,
        targetPath: 'tenants/tenant-a/categories/$categoryId',
        payload: const <String, Object?>{'name': 'Bakery'},
      );
      await store.enqueue(
        uid: 'owner-a',
        tenantId: 'tenant-a',
        operationId: 'product-create-pd_abc',
        kind: TenantPendingMutationKind.productCreate,
        targetPath: 'tenants/tenant-a/products/pd_abc',
        payload: <String, Object?>{
          'name': 'White bread loaf',
          'SKU': '6161100000019',
          'price': 65.0,
          'categoryId': categoryId,
        },
      );
    }

    test('the product is held back while its category is still queued', () async {
      // **The race `createProduct` could not check for until now.** Groups drain
      // concurrently, so without this the product could reach a server that has
      // never heard of its category - and the refusal there is permanent.
      await queueBoth(categoryId: 'ct_bakery');
      final gateway = _DeferringGateway(holdCategory: true);

      await TenantPendingMutationWorker(
        store: store,
        submission: gateway,
        confirmation: gateway,
        workerId: 'device-a',
      ).run(_session());

      expect(gateway.submitted, <String>['category-create-ct_bakery']);
    });

    test('it goes on the pass after its category settles', () async {
      await queueBoth(categoryId: 'ct_bakery');
      final gateway = _DeferringGateway();
      final worker = TenantPendingMutationWorker(
        store: store,
        submission: gateway,
        confirmation: gateway,
        workerId: 'device-a',
      );

      await worker.run(_session());
      await worker.run(_session());

      expect(
        gateway.submitted,
        containsAllInOrder(<String>[
          'category-create-ct_bakery',
          'product-create-pd_abc',
        ]),
      );
    });

    test('waiting costs the record no attempt and no backoff', () async {
      // Deferring is not a failure: nothing was sent, so nothing may be counted
      // against the record. A deferral that burned an attempt would eventually
      // exhaust a product whose category simply took a while.
      await queueBoth(categoryId: 'ct_bakery');
      final gateway = _DeferringGateway(holdCategory: true);

      await TenantPendingMutationWorker(
        store: store,
        submission: gateway,
        confirmation: gateway,
        workerId: 'device-a',
      ).run(_session());

      final records = await store.recordsForSession(
        uid: 'owner-a',
        tenantId: 'tenant-a',
      );
      final product = records.firstWhere(
        (record) => record.operationId == 'product-create-pd_abc',
      );
      expect(product.attemptCount, 0);
      expect(product.state, TenantPendingMutationState.queued);
    });

    test('a product naming a category nobody queued is not held', () async {
      // The ordinary case: the category is already on the server, so there is
      // nothing to wait for and the product goes on the first pass.
      await store.enqueue(
        uid: 'owner-a',
        tenantId: 'tenant-a',
        operationId: 'product-create-pd_abc',
        kind: TenantPendingMutationKind.productCreate,
        targetPath: 'tenants/tenant-a/products/pd_abc',
        payload: const <String, Object?>{
          'name': 'White bread loaf',
          'SKU': '6161100000019',
          'price': 65.0,
          'categoryId': 'ct_already_there',
        },
      );
      final gateway = _DeferringGateway();

      await TenantPendingMutationWorker(
        store: store,
        submission: gateway,
        confirmation: gateway,
        workerId: 'device-a',
      ).run(_session());

      expect(gateway.submitted, <String>['product-create-pd_abc']);
    });
  });

  group('the category envelope', () {
    /// The document a device composes for a category, as `documentData()`
    /// writes it. Built here rather than imported so this pins the *shape the
    /// queue holds*, which is what the envelope is derived from.
    Map<String, Object?> composed({String name = 'Bakery'}) =>
        <String, Object?>{'name': name, 'createdBy': 'user-a'};

    Future<TenantPendingMutationRecord> queued({
      TenantPendingMutationKind kind = TenantPendingMutationKind.categoryCreate,
      Map<String, Object?>? payload,
    }) => store.enqueue(
      uid: 'user-a',
      tenantId: 'tenant-a',
      operationId: 'category-create-ct_abc',
      kind: kind,
      targetPath: 'tenants/tenant-a/categories/ct_abc',
      payload: payload ?? composed(),
    );

    test('is derived from the record rather than stored in it', () async {
      final payload = tenantCategoryCallablePayload(await queued());

      expect(payload['tenantId'], 'tenant-a');
      // From the path, which is the only place a category ID is ever written.
      expect(payload['categoryId'], 'ct_abc');
      expect(payload['document'], composed());
      expect(payload.keys, <String>['tenantId', 'categoryId', 'document']);
    });

    test('a category queued before the callable existed still drains', () async {
      // **The migration argument, as a test.** A build that wrote this document
      // directly queued exactly this payload, and it has to reach
      // `createCategory` untouched - otherwise closing `allow create` in the
      // same release would have stranded work already durable on a phone. The
      // server accepts `createdBy` and takes the actor from the request.
      final payload = tenantCategoryCallablePayload(await queued());
      final document = payload['document']! as Map<String, Object?>;

      expect(document['createdBy'], 'user-a');
      expect(document['name'], 'Bakery');
    });

    test('a rename derives the same envelope', () async {
      final payload = tenantCategoryCallablePayload(
        await queued(
          kind: TenantPendingMutationKind.categoryRename,
          payload: <String, Object?>{
            'name': 'Baked goods',
            'updatedBy': 'user-a',
          },
        ),
      );

      expect(payload['categoryId'], 'ct_abc');
      expect(payload['document'], <String, Object?>{
        'name': 'Baked goods',
        'updatedBy': 'user-a',
      });
    });

    test('both kinds reach the server through the Admin SDK', () {
      // The classification the worker branches on. A device cannot decide
      // whether a name is free - it can only see the categories it has read -
      // so neither of these can be a document write again.
      expect(
        tenantMutationIsCallable(TenantPendingMutationKind.categoryCreate),
        isTrue,
      );
      expect(
        tenantMutationIsCallable(TenantPendingMutationKind.categoryRename),
        isTrue,
      );
    });
  });

  group('the createProduct envelope', () {
    /// The document a device composes for a product, as `documentData()` writes
    /// it. Built here rather than imported so this pins the *shape the queue
    /// holds*, which is the thing the envelope is derived from.
    Map<String, Object?> composed({Object? quantity = 24}) => <String, Object?>{
      'name': 'White bread loaf',
      'SKU': '6161100000019',
      'price': 65.0,
      'categoryId': 'cat-bakery',
      if (quantity != null) 'quantity': quantity,
      'searchName': 'white bread loaf',
      'searchPrefixes': const <String>['wh', 'whi'],
      'createdBy': 'user-a',
    };

    Future<TenantPendingMutationRecord> queued({Object? quantity = 24}) =>
        store.enqueue(
          uid: 'user-a',
          tenantId: 'tenant-a',
          operationId: 'product-create-pd_abc',
          kind: TenantPendingMutationKind.productCreate,
          targetPath: 'tenants/tenant-a/products/pd_abc',
          payload: composed(quantity: quantity),
        );

    test('is derived from the record rather than stored in it', () async {
      final payload = tenantProductCreateCallablePayload(await queued());

      expect(payload['tenantId'], 'tenant-a');
      // From the path, which is the only place a product ID is ever written.
      expect(payload['productId'], 'pd_abc');
      expect(payload['document'], composed());
      // Exactly four keys: anything else would be a second source of truth for
      // something the record already knows.
      expect(payload.keys, <String>[
        'tenantId',
        'productId',
        'document',
        'occurredAtMs',
      ]);
    });

    test(
      'says when the product was added, which dates its opening stock',
      () async {
        final record = await queued();

        expect(
          tenantProductCreateCallablePayload(record)['occurredAtMs'],
          record.createdAt.millisecondsSinceEpoch,
        );
      },
    );

    test('a create that opens no stock carries no quantity key', () async {
      // A product brought in with nothing on the shelf queues a document with
      // no `quantity` at all, and it must reach `createProduct` untouched and be
      // read as opening nothing. Absent is not zero anywhere else in this
      // system either, and the envelope must not invent one here.
      final payload = tenantProductCreateCallablePayload(
        await queued(quantity: null),
      );
      final document = payload['document']! as Map<String, Object?>;

      expect(document.containsKey('quantity'), isFalse);
      expect(payload['productId'], 'pd_abc');
    });

    test('the product ID is what the server keys idempotency on', () async {
      // Not a second request ID carried beside it: the product ID is already a
      // digest of the request ID that minted it, so one retry of one
      // confirmation always addresses one record.
      final first = tenantProductCreateCallablePayload(await queued());
      final second = tenantProductCreateCallablePayload(
        await store.enqueue(
          uid: 'user-a',
          tenantId: 'tenant-a',
          operationId: 'product-create-pd_abc',
          kind: TenantPendingMutationKind.productCreate,
          targetPath: 'tenants/tenant-a/products/pd_abc',
          payload: composed(),
        ),
      );

      expect(second['productId'], first['productId']);
      expect(second['document'], first['document']);
      // The record is the same record, so the time it was made is too.
      expect(second['occurredAtMs'], first['occurredAtMs']);
    });
  });

  group('a callable that moves stock says when it was made', () {
    Future<TenantPendingMutationRecord> queued() => store.enqueue(
      uid: 'user-a',
      tenantId: 'tenant-a',
      operationId: 'stock-adjust-req-12345678',
      kind: TenantPendingMutationKind.stockAdjust,
      targetPath: 'tenants/tenant-a/products/pd_abc',
      payload: const <String, Object?>{
        'tenantId': 'tenant-a',
        'productId': 'pd_abc',
        'quantityDelta': 6,
        'type': 'restock',
        'reason': 'Counted the back room',
        'requestId': 'req-12345678',
      },
    );

    test('the whole request, with the moment it was saved beside it', () async {
      final record = await queued();

      final request = tenantTimedCallablePayload(record);

      expect(request, <String, Object?>{
        ...record.payload,
        'occurredAtMs': record.createdAt.millisecondsSinceEpoch,
      });
      // The stored payload is untouched: the overlay and the confirming read
      // compare against it, and neither knows this key.
      expect(record.payload.containsKey('occurredAtMs'), isFalse);
    });

    test('every replay of one record says the same moment', () async {
      final first = tenantTimedCallablePayload(await queued());
      final again = tenantTimedCallablePayload(await queued());

      expect(again['occurredAtMs'], first['occurredAtMs']);
    });
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

/// Timers the worker asks for, fired by hand.
final class _Timers {
  final List<Duration> requested = <Duration>[];
  final List<void Function()> _callbacks = <void Function()>[];

  Timer call(Duration delay, void Function() callback) {
    requested.add(delay);
    _callbacks.add(callback);
    return _InertTimer();
  }

  void fire() => _callbacks.removeLast()();
}

final class _InertTimer implements Timer {
  bool _cancelled = false;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => 0;
}

/// Fails every send and every read, as an unreachable backend would.
final class _Throws
    implements
        TenantMutationSubmissionGateway,
        TenantMutationConfirmationGateway {
  const _Throws();

  @override
  Future<Map<String, Object?>?> read(String targetPath) =>
      Future<Map<String, Object?>?>.error(StateError('unavailable'));

  @override
  Future<TenantMutationSubmissionResult> submit(
    TenantPendingMutationRecord record,
  ) => Future<TenantMutationSubmissionResult>.error(StateError('unavailable'));
}

/// Gives no answer the first time a record is sent, and commits after that.
final class _AnswersSecondTime
    implements
        TenantMutationSubmissionGateway,
        TenantMutationConfirmationGateway {
  _AnswersSecondTime({required this.product});

  /// What reading the target returns: a product, which never holds the
  /// adjustment that was sent to it.
  final Map<String, Object?> product;
  int submissions = 0;

  @override
  Future<Map<String, Object?>?> read(String targetPath) async => product;

  @override
  Future<TenantMutationSubmissionResult> submit(
    TenantPendingMutationRecord record,
  ) async {
    submissions++;
    return TenantMutationSubmissionResult(
      submissions == 1
          ? TenantMutationSubmissionOutcome.uncertain
          : TenantMutationSubmissionOutcome.committed,
      submissions == 1 ? 'write_timeout' : null,
    );
  }
}

/// Commits everything, and records every send and read in order.
final class _ReadLog
    implements
        TenantMutationSubmissionGateway,
        TenantMutationConfirmationGateway {
  _ReadLog({this.readFails = false});

  final bool readFails;
  final List<String> events = <String>[];

  @override
  Future<Map<String, Object?>?> read(String targetPath) async {
    events.add('read $targetPath');
    if (readFails) throw StateError('unavailable');
    return const <String, Object?>{'name': 'ABC', 'active': true};
  }

  @override
  Future<TenantMutationSubmissionResult> submit(
    TenantPendingMutationRecord record,
  ) async {
    events.add('submit ${record.operationId}');
    return const TenantMutationSubmissionResult(
      TenantMutationSubmissionOutcome.committed,
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

/// A gateway that can hold one kind back, so a pass can end with a category
/// still unresolved.
final class _DeferringGateway
    implements
        TenantMutationSubmissionGateway,
        TenantMutationConfirmationGateway {
  _DeferringGateway({this.holdCategory = false});

  /// Whether a category create answers with an uncertain outcome, which is what
  /// leaves it unresolved for the product behind it.
  final bool holdCategory;

  final List<String> submitted = <String>[];

  @override
  Future<Map<String, Object?>?> read(String targetPath) async => null;

  @override
  Future<TenantMutationSubmissionResult> submit(
    TenantPendingMutationRecord record,
  ) async {
    submitted.add(record.operationId);
    if (holdCategory &&
        record.kind == TenantPendingMutationKind.categoryCreate) {
      return const TenantMutationSubmissionResult(
        TenantMutationSubmissionOutcome.uncertain,
      );
    }
    return const TenantMutationSubmissionResult(
      TenantMutationSubmissionOutcome.committed,
    );
  }
}
