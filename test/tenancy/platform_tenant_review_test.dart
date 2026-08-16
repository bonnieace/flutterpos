import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

void main() {
  group('PlatformPendingTenantQueue', () {
    test(
      'requires both the active platform root and superAdmin claim',
      () async {
        final source = _ReviewDataSource([_tenantDocument('tenant-a')]);
        for (final identity in [
          _identity(hasClaim: false),
          _identity(profile: _tenantProfile),
          _identity(profile: _disabledPlatformProfile),
        ]) {
          await expectLater(
            PlatformPendingTenantQueue(
              identity: identity,
              dataSource: source,
            ).load(),
            throwsStateError,
          );
        }
        expect(source.pageCalls, 0);
      },
    );

    test(
      'strictly decodes owner metadata and paginates pending records',
      () async {
        final source = _ReviewDataSource([
          _tenantDocument('tenant-c', day: 3),
          _tenantDocument('tenant-b', day: 2),
          _tenantDocument('tenant-a', day: 1),
        ]);
        final queue = PlatformPendingTenantQueue(
          identity: _identity(),
          dataSource: source,
        );

        final first = await queue.load(pageSize: 2);

        expect(first.items.map((item) => item.tenantId), [
          'tenant-c',
          'tenant-b',
        ]);
        expect(first.items.first.owner.displayName, 'Owner tenant-c');
        expect(first.items.first.owner.email, 'owner-tenant-c@example.test');
        expect(first.items.first.owner.globallyActive, isTrue);
        expect(first.hasMore, isTrue);
        expect(first.nextCursor?.tenantId, 'tenant-b');
        expect(source.requestedLimits, [3]);

        final second = await queue.load(pageSize: 2, cursor: first.nextCursor);
        expect(second.items.map((item) => item.tenantId), ['tenant-a']);
        expect(second.hasMore, isFalse);
        expect(source.receivedCursors.last?.tenantId, 'tenant-b');
      },
    );

    test(
      'rejects non-pending, malformed, and ownerless queue records',
      () async {
        final nonPending = _ReviewDataSource([
          _tenantDocument('tenant-a', status: 'active'),
        ]);
        await expectLater(
          PlatformPendingTenantQueue(
            identity: _identity(),
            dataSource: nonPending,
          ).load(),
          throwsFormatException,
        );

        final ownerless = _ReviewDataSource([
          _tenantDocument('tenant-a'),
        ], missingOwner: true);
        await expectLater(
          PlatformPendingTenantQueue(
            identity: _identity(),
            dataSource: ownerless,
          ).load(),
          throwsFormatException,
        );
      },
    );

    test('validates the bounded page size before reading Firestore', () async {
      final source = _ReviewDataSource([]);
      final queue = PlatformPendingTenantQueue(
        identity: _identity(),
        dataSource: source,
      );
      await expectLater(queue.load(pageSize: 0), throwsRangeError);
      await expectLater(queue.load(pageSize: 51), throwsRangeError);
      expect(source.pageCalls, 0);
    });

    test('keeps disabled owner requests visible for rejection', () async {
      final owner = _ownerDocument('tenant-a');
      owner.data['globalStatus'] = 'disabled';
      final source = _ReviewDataSource(
        [_tenantDocument('tenant-a')],
        ownerOverrides: {'owner-tenant-a': owner},
      );

      final page = await PlatformPendingTenantQueue(
        identity: _identity(),
        dataSource: source,
      ).load();

      expect(page.items.single.owner.globallyActive, isFalse);
    });
  });

  group('PlatformTenantReviewGateway', () {
    test('derives exact approval payload from its pending record', () async {
      final callable = _ReviewCallable();
      final gateway = _gateway(callable);
      final intent = gateway.createIntent(
        action: PlatformTenantReviewAction.approve,
      );

      final result = await gateway.submit(intent);

      expect(callable.payloads.single, {
        'tenantId': 'tenant-a',
        'status': 'active',
        'requestId': 'review-request-001',
      });

      expect(result.tenantId, 'tenant-a');
      expect(result.previousStatus, TenantStatus.pending);
      expect(result.status, TenantStatus.active);
      expect(result.fanoutOperationId, 'fanout-operation-001');
    });

    test('requires and normalizes the rejection reason', () async {
      final callable = _ReviewCallable();
      final gateway = _gateway(callable);
      expect(
        () => gateway.createIntent(
          action: PlatformTenantReviewAction.reject,
          reason: ' ',
        ),
        throwsArgumentError,
      );

      final intent = gateway.createIntent(
        action: PlatformTenantReviewAction.reject,
        reason: '  Missing   verification documents. ',
      );
      await gateway.submit(intent);

      expect(callable.payloads.single, {
        'tenantId': 'tenant-a',
        'status': 'rejected',
        'reason': 'Missing verification documents.',
        'requestId': 'review-request-001',
      });
    });

    test(
      'rejects stale record intents and lost platform eligibility',
      () async {
        final callable = _ReviewCallable();
        final intent = _gateway(
          callable,
        ).createIntent(action: PlatformTenantReviewAction.approve);

        await expectLater(
          PlatformTenantReviewGateway(
            identity: _identity(),
            tenant: _pendingTenant('tenant-a', day: 2),
            callable: callable,
          ).submit(intent),
          throwsStateError,
        );
        await expectLater(
          PlatformTenantReviewGateway(
            identity: _identity(hasClaim: false),
            tenant: _pendingTenant('tenant-a'),
            callable: callable,
          ).submit(intent),
          throwsStateError,
        );
        expect(callable.payloads, isEmpty);
      },
    );

    test('strictly rejects response mismatches and extra fields', () async {
      for (final response in <Object?>[
        {
          'tenantId': 'tenant-other',
          'previousStatus': 'pending',
          'status': 'active',
          'fanoutOperationId': 'fanout-operation-001',
        },
        {
          'tenantId': 'tenant-a',
          'previousStatus': 'active',
          'status': 'active',
          'fanoutOperationId': 'fanout-operation-001',
        },
        {
          'tenantId': 'tenant-a',
          'previousStatus': 'pending',
          'status': 'active',
          'fanoutOperationId': 'fanout-operation-001',
          'extra': true,
        },
      ]) {
        final gateway = _gateway(_ReviewCallable(response: response));
        await expectLater(
          gateway.submit(
            gateway.createIntent(action: PlatformTenantReviewAction.approve),
          ),
          throwsFormatException,
        );
      }
    });
  });

  group('PlatformTenantReviewForm', () {
    testWidgets('cancellation performs no mutation', (tester) async {
      final callable = _ReviewCallable();
      var cancelled = false;
      await tester.pumpWidget(
        _formApp(callable: callable, onCancel: () => cancelled = true),
      );

      await tester.tap(find.byKey(const ValueKey('platform-review-cancel')));
      await tester.pump();

      expect(cancelled, isTrue);
      expect(callable.payloads, isEmpty);
    });

    testWidgets('duplicate taps are single-flight', (tester) async {
      final completer = Completer<Object?>();
      final callable = _ReviewCallable(pending: completer);
      var successes = 0;
      await tester.pumpWidget(
        _formApp(callable: callable, onSuccess: (_) => successes++),
      );

      final confirm = find.byKey(
        const ValueKey('platform-review-approve-confirm'),
      );
      await tester.tap(confirm);
      await tester.tap(confirm);
      await tester.pump();

      expect(callable.payloads, hasLength(1));
      completer.complete(_approvalResponse);
      await tester.pump();
      expect(successes, 1);
    });

    testWidgets('recoverable retry reuses the stable request ID', (
      tester,
    ) async {
      final callable = _ReviewCallable(failures: 1);
      await tester.pumpWidget(_formApp(callable: callable));
      final confirm = find.byKey(
        const ValueKey('platform-review-approve-confirm'),
      );

      await tester.tap(confirm);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('platform-review-error')),
        findsOneWidget,
      );
      // A refusal is §2.1's `problem`, and asserting it is what
      // the old red `Text` could not carry: the sentence alone
      // reads the same whether the write landed or not.
      expect(noticeStatus(tester, 'platform-review-error'), AppStatus.problem);
      await tester.tap(confirm);
      await tester.pump();

      expect(callable.payloads, hasLength(2));
      expect(callable.payloads.map((payload) => payload['requestId']).toSet(), {
        'review-request-001',
      });
    });

    testWidgets('discards completion after the platform route becomes stale', (
      tester,
    ) async {
      final completer = Completer<Object?>();
      final callable = _ReviewCallable(pending: completer);
      var current = true;
      var successes = 0;
      await tester.pumpWidget(
        _formApp(
          callable: callable,
          isCurrent: () => current,
          onSuccess: (_) => successes++,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('platform-review-approve-confirm')),
      );
      await tester.pump();
      current = false;
      completer.complete(_approvalResponse);
      await tester.pump();

      expect(successes, 0);
    });
  });

  testWidgets('screen loads more and refreshes only after review success', (
    tester,
  ) async {
    final source = _ReviewDataSource([
      _tenantDocument('tenant-b', day: 2),
      _tenantDocument('tenant-a', day: 1),
    ]);
    final callable = _ReviewCallable();
    await tester.pumpWidget(
      MaterialApp(
        home: PlatformPendingTenantReviewScreen(
          identity: _identity(),
          dataSource: source,
          callable: callable,
          requestIdFactory: () => 'review-request-001',
          pageSize: 1,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Business tenant-b'), findsOneWidget);
    expect(find.text('Business tenant-a'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('platform-review-load-more')));
    await tester.pump();
    expect(find.text('Business tenant-a'), findsOneWidget);
    expect(source.pageCalls, 2);

    await tester.tap(find.byKey(const ValueKey('platform-approve-tenant-b')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('platform-review-approve-confirm')),
    );
    await tester.pump();
    expect(source.pageCalls, 3);
  });
}

Widget _formApp({
  required _ReviewCallable callable,
  VoidCallback? onCancel,
  ValueChanged<PlatformTenantReviewResult>? onSuccess,
  PlatformTenantReviewCurrentCheck? isCurrent,
}) => MaterialApp(
  home: Scaffold(
    body: PlatformTenantReviewForm(
      identity: _identity(),
      tenant: _pendingTenant('tenant-a'),
      action: PlatformTenantReviewAction.approve,
      callable: callable,
      requestIdFactory: () => 'review-request-001',
      isCurrent: isCurrent,
      onCancel: onCancel ?? () {},
      onSuccess: onSuccess ?? (_) {},
    ),
  ),
);

PlatformTenantReviewGateway _gateway(_ReviewCallable callable) =>
    PlatformTenantReviewGateway(
      identity: _identity(),
      tenant: _pendingTenant('tenant-a'),
      callable: callable,
      requestIdFactory: () => 'review-request-001',
    );

PlatformReviewIdentity _identity({
  RootRoutingProfile profile = _platformProfile,
  bool hasClaim = true,
}) => PlatformReviewIdentity(
  uid: 'platform-user',
  profile: profile,
  hasSuperAdminClaim: hasClaim,
);

PlatformPendingTenant _pendingTenant(String tenantId, {int day = 1}) =>
    PlatformPendingTenant.fromDocuments(
      tenant: _tenantDocument(tenantId, day: day),
      owner: _ownerDocument(tenantId),
    );

PlatformTenantDocument _tenantDocument(
  String tenantId, {
  int day = 1,
  String status = 'pending',
}) => PlatformTenantDocument(
  id: tenantId,
  data: {
    'name': 'Business $tenantId',
    'slug': tenantId,
    'ownerUid': 'owner-$tenantId',
    'status': status,
    'createdAt': DateTime.utc(2026, 7, day),
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

const _approvalResponse = <String, Object?>{
  'tenantId': 'tenant-a',
  'previousStatus': 'pending',
  'status': 'active',
  'fanoutOperationId': 'fanout-operation-001',
};

final class _ReviewDataSource implements PlatformPendingTenantDataSource {
  _ReviewDataSource(
    this.documents, {
    this.missingOwner = false,
    this.ownerOverrides = const {},
  });

  final List<PlatformTenantDocument> documents;
  final bool missingOwner;
  final Map<String, PlatformTenantDocument> ownerOverrides;
  final List<int> requestedLimits = [];
  final List<PlatformPendingTenantCursor?> receivedCursors = [];
  int pageCalls = 0;

  @override
  Future<List<PlatformTenantDocument>> loadPendingTenantDocuments({
    required int limit,
    PlatformPendingTenantCursor? cursor,
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
  Future<PlatformTenantDocument?> loadRootUser(String uid) async {
    if (missingOwner) return null;
    if (ownerOverrides.containsKey(uid)) return ownerOverrides[uid];
    return _ownerDocument(uid.substring('owner-'.length));
  }
}

final class _ReviewCallable implements SetTenantLifecycleCallable {
  _ReviewCallable({this.response, this.failures = 0, this.pending});

  final Object? response;
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
      'previousStatus': 'pending',
      'status': payload['status'],
      'fanoutOperationId': 'fanout-operation-001',
    };
  }
}
