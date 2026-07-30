import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformLifecycleTenantQueue', () {
    test('requires platform root and claim before reading', () async {
      final source = _LifecycleDataSource([_tenantDocument('tenant-a')]);
      for (final identity in [
        _identity(hasClaim: false),
        _identity(profile: _tenantProfile),
        _identity(profile: _disabledPlatformProfile),
      ]) {
        await expectLater(
          PlatformLifecycleTenantQueue(
            identity: identity,
            dataSource: source,
          ).load(),
          throwsStateError,
        );
      }
      expect(source.pageCalls, 0);
    });

    test('decodes active and suspended records with a stable cursor', () async {
      final source = _LifecycleDataSource([
        _tenantDocument('tenant-a', status: 'active', day: 3),
        _tenantDocument('tenant-b', status: 'active', day: 2),
        _tenantDocument('tenant-c', status: 'suspended', day: 1),
      ]);
      final queue = PlatformLifecycleTenantQueue(
        identity: _identity(),
        dataSource: source,
      );

      final first = await queue.load(pageSize: 2);
      expect(first.items.map((item) => item.tenantId), [
        'tenant-a',
        'tenant-b',
      ]);
      expect(first.items.first.status, TenantStatus.active);
      expect(first.hasMore, isTrue);
      expect(first.nextCursor?.status, TenantStatus.active);
      expect(first.nextCursor?.tenantId, 'tenant-b');

      final second = await queue.load(pageSize: 2, cursor: first.nextCursor);
      expect(second.items.single.tenantId, 'tenant-c');
      expect(second.items.single.status, TenantStatus.suspended);
      expect(source.requestedLimits, [3, 3]);
      expect(source.receivedCursors.last?.tenantId, 'tenant-b');
    });

    test(
      'rejects unsupported statuses, stale fields, and bad page sizes',
      () async {
        for (final document in [
          _tenantDocument('tenant-a', status: 'pending'),
          _tenantDocument('tenant-a')..data.remove('updatedAt'),
          _tenantDocument('tenant-a')..data['ownerUid'] = 'bad/path',
        ]) {
          await expectLater(
            PlatformLifecycleTenantQueue(
              identity: _identity(),
              dataSource: _LifecycleDataSource([document]),
            ).load(),
            throwsFormatException,
          );
        }
        final source = _LifecycleDataSource([]);
        final queue = PlatformLifecycleTenantQueue(
          identity: _identity(),
          dataSource: source,
        );
        await expectLater(queue.load(pageSize: 0), throwsRangeError);
        await expectLater(queue.load(pageSize: 51), throwsRangeError);
        expect(source.pageCalls, 0);
      },
    );
  });

  group('PlatformTenantLifecycleGateway', () {
    test('derives suspension payload and normalizes its reason', () async {
      final callable = _LifecycleCallable();
      final gateway = _gateway(callable, status: 'active');
      final intent = gateway.createIntent(
        action: PlatformTenantLifecycleAction.suspend,
        reason: '  Repeated   compliance failures. ',
      );

      final result = await gateway.submit(intent);

      expect(callable.payloads.single, {
        'tenantId': 'tenant-a',
        'status': 'suspended',
        'reason': 'Repeated compliance failures.',
        'requestId': 'lifecycle-request-001',
      });
      expect(result.previousStatus, TenantStatus.active);
      expect(result.status, TenantStatus.suspended);
    });

    test('derives reactivation without a reason', () async {
      final callable = _LifecycleCallable(previousStatus: 'suspended');
      final gateway = _gateway(callable, status: 'suspended');
      await gateway.submit(
        gateway.createIntent(
          action: PlatformTenantLifecycleAction.reactivate,
          reason: 'ignored',
        ),
      );

      expect(callable.payloads.single, {
        'tenantId': 'tenant-a',
        'status': 'active',
        'requestId': 'lifecycle-request-001',
      });
    });

    test('denies unsupported transitions and invalid suspension reasons', () {
      final active = _gateway(_LifecycleCallable(), status: 'active');
      expect(
        () => active.createIntent(
          action: PlatformTenantLifecycleAction.reactivate,
        ),
        throwsStateError,
      );
      expect(
        () => active.createIntent(
          action: PlatformTenantLifecycleAction.suspend,
          reason: ' ',
        ),
        throwsArgumentError,
      );
      expect(
        () => active.createIntent(
          action: PlatformTenantLifecycleAction.suspend,
          reason: 'bad\u0000reason',
        ),
        throwsArgumentError,
      );
    });

    test('rejects response mismatches and extra fields', () async {
      for (final response in <Object?>[
        _response(tenantId: 'tenant-other'),
        _response(previousStatus: 'suspended'),
        _response(status: 'active'),
        {..._response(), 'extra': true},
      ]) {
        final gateway = _gateway(
          _LifecycleCallable(response: response),
          status: 'active',
        );
        await expectLater(
          gateway.submit(
            gateway.createIntent(
              action: PlatformTenantLifecycleAction.suspend,
              reason: 'Valid reason',
            ),
          ),
          throwsFormatException,
        );
      }
    });

    test('rejects identity and record switches before calling', () async {
      final callable = _LifecycleCallable();
      final intent = _gateway(callable, status: 'active').createIntent(
        action: PlatformTenantLifecycleAction.suspend,
        reason: 'Valid reason',
      );
      await expectLater(
        PlatformTenantLifecycleGateway(
          identity: _identity(hasClaim: false),
          tenant: _tenant('tenant-a', status: 'active'),
          callable: callable,
        ).submit(intent),
        throwsStateError,
      );
      await expectLater(
        PlatformTenantLifecycleGateway(
          identity: _identity(),
          tenant: _tenant('tenant-a', status: 'active', day: 2),
          callable: callable,
        ).submit(intent),
        throwsStateError,
      );
      expect(callable.payloads, isEmpty);
    });

    test('maps reactivation capacity and invariant errors to safe text', () {
      expect(
        platformTenantLifecycleSafeError(
          const PlatformTenantReviewCallableException('resource-exhausted'),
          action: PlatformTenantLifecycleAction.reactivate,
        ),
        'The owner has reached the active business limit.',
      );
      expect(
        platformTenantLifecycleSafeError(
          const PlatformTenantReviewCallableException('failed-precondition'),
          action: PlatformTenantLifecycleAction.suspend,
        ),
        contains('changed'),
      );
    });
  });

  group('PlatformTenantLifecycleForm', () {
    testWidgets('cancel performs no mutation', (tester) async {
      final callable = _LifecycleCallable();
      var cancelled = false;
      await tester.pumpWidget(
        _formApp(callable: callable, onCancel: () => cancelled = true),
      );
      await tester.tap(find.byKey(const ValueKey('platform-lifecycle-cancel')));
      await tester.pump();
      expect(cancelled, isTrue);
      expect(callable.payloads, isEmpty);
    });

    testWidgets('duplicate taps are single-flight', (tester) async {
      final completer = Completer<Object?>();
      final callable = _LifecycleCallable(pending: completer);
      var successes = 0;
      await tester.pumpWidget(
        _formApp(callable: callable, onSuccess: (_) => successes++),
      );
      await tester.enterText(
        find.byKey(const ValueKey('platform-lifecycle-reason')),
        'Valid suspension reason',
      );
      final confirm = find.byKey(
        const ValueKey('platform-lifecycle-suspend-confirm'),
      );
      await tester.tap(confirm);
      await tester.tap(confirm);
      await tester.pump();
      expect(callable.payloads, hasLength(1));
      completer.complete(_response());
      await tester.pump();
      expect(successes, 1);
    });

    testWidgets('retry reuses request ID and stale completion is discarded', (
      tester,
    ) async {
      final retrying = _LifecycleCallable(failures: 1);
      await tester.pumpWidget(_formApp(callable: retrying));
      await tester.enterText(
        find.byKey(const ValueKey('platform-lifecycle-reason')),
        'Valid suspension reason',
      );
      final confirm = find.byKey(
        const ValueKey('platform-lifecycle-suspend-confirm'),
      );
      await tester.tap(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      expect(retrying.payloads, hasLength(2));
      expect(retrying.payloads.map((p) => p['requestId']).toSet(), {
        'lifecycle-request-001',
      });

      final completer = Completer<Object?>();
      final stale = _LifecycleCallable(pending: completer);
      var current = true;
      var successes = 0;
      await tester.pumpWidget(
        _formApp(
          callable: stale,
          isCurrent: () => current,
          onSuccess: (_) => successes++,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('platform-lifecycle-reason')),
        'Valid suspension reason',
      );
      await tester.tap(confirm);
      await tester.pump();
      current = false;
      completer.complete(_response());
      await tester.pump();
      expect(successes, 0);
    });
  });

  testWidgets('screen paginates and refreshes its queue only after success', (
    tester,
  ) async {
    final source = _LifecycleDataSource([
      _tenantDocument('tenant-a', status: 'active', day: 2),
      _tenantDocument('tenant-b', status: 'suspended', day: 1),
    ]);
    final callable = _LifecycleCallable();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlatformLifecycleTenantScreen(
            identity: _identity(),
            dataSource: source,
            callable: callable,
            requestIdFactory: () => 'lifecycle-request-001',
            pageSize: 1,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Business tenant-a'), findsOneWidget);
    expect(find.text('Business tenant-b'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('platform-lifecycle-load-more')),
    );
    await tester.pump();
    expect(find.text('Business tenant-b'), findsOneWidget);
    expect(source.pageCalls, 2);

    await tester.tap(find.byKey(const ValueKey('platform-suspend-tenant-a')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('platform-lifecycle-reason')),
      'Valid suspension reason',
    );
    await tester.tap(
      find.byKey(const ValueKey('platform-lifecycle-suspend-confirm')),
    );
    await tester.pump();
    expect(source.pageCalls, 3);
  });
}

Widget _formApp({
  required _LifecycleCallable callable,
  VoidCallback? onCancel,
  ValueChanged<PlatformTenantLifecycleResult>? onSuccess,
  PlatformTenantReviewCurrentCheck? isCurrent,
}) => MaterialApp(
  home: Scaffold(
    body: PlatformTenantLifecycleForm(
      identity: _identity(),
      tenant: _tenant('tenant-a', status: 'active'),
      action: PlatformTenantLifecycleAction.suspend,
      callable: callable,
      requestIdFactory: () => 'lifecycle-request-001',
      isCurrent: isCurrent,
      onCancel: onCancel ?? () {},
      onSuccess: onSuccess ?? (_) {},
    ),
  ),
);

PlatformTenantLifecycleGateway _gateway(
  _LifecycleCallable callable, {
  required String status,
}) => PlatformTenantLifecycleGateway(
  identity: _identity(),
  tenant: _tenant('tenant-a', status: status),
  callable: callable,
  requestIdFactory: () => 'lifecycle-request-001',
);

PlatformReviewIdentity _identity({
  RootRoutingProfile profile = _platformProfile,
  bool hasClaim = true,
}) => PlatformReviewIdentity(
  uid: 'platform-user',
  profile: profile,
  hasSuperAdminClaim: hasClaim,
);

PlatformLifecycleTenant _tenant(
  String tenantId, {
  required String status,
  int day = 1,
}) => PlatformLifecycleTenant.fromDocuments(
  tenant: _tenantDocument(tenantId, status: status, day: day),
  owner: _ownerDocument(tenantId),
);

PlatformTenantDocument _tenantDocument(
  String tenantId, {
  String status = 'active',
  int day = 1,
}) => PlatformTenantDocument(
  id: tenantId,
  data: {
    'name': 'Business $tenantId',
    'slug': tenantId,
    'ownerUid': 'owner-$tenantId',
    'status': status,
    'createdAt': DateTime.utc(2026, 7, 1),
    'updatedAt': DateTime.utc(2026, 7, day),
  },
);

PlatformTenantDocument _ownerDocument(String tenantId) =>
    PlatformTenantDocument(
      id: 'owner-$tenantId',
      data: {
        'email': 'owner-$tenantId@example.test',
        'displayName': 'Owner $tenantId',
        'accountType': 'tenant_user',
        'globalStatus': 'active',
      },
    );

Map<String, Object?> _response({
  String tenantId = 'tenant-a',
  String previousStatus = 'active',
  String status = 'suspended',
}) => {
  'tenantId': tenantId,
  'previousStatus': previousStatus,
  'status': status,
  'fanoutOperationId': 'fanout-operation-001',
};

const _platformProfile = RootRoutingProfile(
  accountType: RootAccountType.platformAdmin,
  globalStatus: 'active',
);

const _disabledPlatformProfile = RootRoutingProfile(
  accountType: RootAccountType.platformAdmin,
  globalStatus: 'disabled',
);

const _tenantProfile = RootRoutingProfile(
  accountType: RootAccountType.tenantUser,
  globalStatus: 'active',
);

final class _LifecycleDataSource implements PlatformLifecycleTenantDataSource {
  _LifecycleDataSource(this.documents);

  final List<PlatformTenantDocument> documents;
  final List<int> requestedLimits = [];
  final List<PlatformLifecycleTenantCursor?> receivedCursors = [];
  int pageCalls = 0;

  @override
  Future<List<PlatformTenantDocument>> loadLifecycleTenantDocuments({
    required int limit,
    PlatformLifecycleTenantCursor? cursor,
  }) async {
    pageCalls++;
    requestedLimits.add(limit);
    receivedCursors.add(cursor);
    var start = 0;
    if (cursor != null) {
      start =
          documents.indexWhere((document) => document.id == cursor.tenantId) +
          1;
    }
    return documents.skip(start).take(limit).toList(growable: false);
  }

  @override
  Future<PlatformTenantDocument?> loadRootUser(String uid) async =>
      _ownerDocument(uid.substring('owner-'.length));
}

final class _LifecycleCallable implements SetTenantLifecycleCallable {
  _LifecycleCallable({
    this.response,
    this.previousStatus = 'active',
    this.failures = 0,
    this.pending,
  });

  final Object? response;
  final String previousStatus;
  int failures;
  final Completer<Object?>? pending;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    if (failures > 0) {
      failures--;
      throw const PlatformTenantReviewCallableException('unavailable');
    }
    if (pending != null) return pending!.future;
    if (response != null) return response;
    return {
      'tenantId': payload['tenantId'],
      'previousStatus': previousStatus,
      'status': payload['status'],
      'fanoutOperationId': 'fanout-operation-001',
    };
  }
}
