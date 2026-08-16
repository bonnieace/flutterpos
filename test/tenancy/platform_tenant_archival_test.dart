import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

void main() {
  group('PlatformRejectedTenantQueue', () {
    test('requires the platform root and claim before reading', () async {
      final source = _ArchivalDataSource([_tenantDocument('tenant-a')]);
      for (final identity in [
        _identity(hasClaim: false),
        _identity(profile: _tenantProfile),
        _identity(profile: _disabledPlatformProfile),
      ]) {
        await expectLater(
          PlatformRejectedTenantQueue(
            identity: identity,
            dataSource: source,
          ).load(),
          throwsStateError,
        );
      }
      expect(source.pageCalls, 0);
    });

    test('decodes rejected records with a stable time and ID cursor', () async {
      final source = _ArchivalDataSource([
        _tenantDocument('tenant-a', day: 3),
        _tenantDocument('tenant-b', day: 2),
        _tenantDocument('tenant-c', day: 1),
      ]);
      final queue = PlatformRejectedTenantQueue(
        identity: _identity(),
        dataSource: source,
      );

      final first = await queue.load(pageSize: 2);
      expect(first.items.map((item) => item.tenantId), [
        'tenant-a',
        'tenant-b',
      ]);
      expect(first.items.first.status, TenantStatus.rejected);
      expect(
        first.items.first.archiveConfirmation,
        'Business tenant-a (tenant-a)',
      );
      expect(first.hasMore, isTrue);
      expect(first.nextCursor?.tenantId, 'tenant-b');

      final second = await queue.load(pageSize: 2, cursor: first.nextCursor);
      expect(second.items.single.tenantId, 'tenant-c');
      expect(source.requestedLimits, [3, 3]);
      expect(source.receivedCursors.last?.tenantId, 'tenant-b');
    });

    test(
      'rejects every other status, malformed records, and bad sizes',
      () async {
        for (final status in ['pending', 'active', 'suspended', 'archived']) {
          await expectLater(
            PlatformRejectedTenantQueue(
              identity: _identity(),
              dataSource: _ArchivalDataSource([
                _tenantDocument('tenant-a', status: status),
              ]),
            ).load(),
            throwsFormatException,
          );
        }
        for (final document in [
          _tenantDocument('tenant-a')..data.remove('updatedAt'),
          _tenantDocument('tenant-a')..data['ownerUid'] = 'bad/path',
        ]) {
          await expectLater(
            PlatformRejectedTenantQueue(
              identity: _identity(),
              dataSource: _ArchivalDataSource([document]),
            ).load(),
            throwsFormatException,
          );
        }
        final source = _ArchivalDataSource([]);
        final queue = PlatformRejectedTenantQueue(
          identity: _identity(),
          dataSource: source,
        );
        await expectLater(queue.load(pageSize: 0), throwsRangeError);
        await expectLater(queue.load(pageSize: 51), throwsRangeError);
        expect(source.pageCalls, 0);
      },
    );
  });

  group('PlatformTenantArchivalGateway', () {
    test('derives the archival payload and normalizes its reason', () async {
      final callable = _ArchivalCallable();
      final gateway = _gateway(callable);
      final result = await gateway.submit(
        gateway.createIntent(
          reason: '  Application   was withdrawn. ',
          confirmation: ' Business tenant-a (tenant-a) ',
        ),
      );

      expect(callable.payloads.single, {
        'tenantId': 'tenant-a',
        'status': 'archived',
        'reason': 'Application was withdrawn.',
        'requestId': 'archival-request-001',
      });
      expect(result.previousStatus, TenantStatus.rejected);
      expect(result.status, TenantStatus.archived);
    });

    test('requires a safe reason and exact canonical confirmation', () {
      final gateway = _gateway(_ArchivalCallable());
      for (final reason in ['', 'x', 'bad\u0000reason']) {
        expect(
          () => gateway.createIntent(
            reason: reason,
            confirmation: 'Business tenant-a (tenant-a)',
          ),
          throwsArgumentError,
        );
      }
      for (final confirmation in [
        '',
        'tenant-a',
        'Business tenant-a',
        'Business tenant-b (tenant-b)',
      ]) {
        expect(
          () => gateway.createIntent(
            reason: 'Valid archival reason',
            confirmation: confirmation,
          ),
          throwsArgumentError,
        );
      }
    });

    test(
      'rejects response mismatches, malformed IDs, and extra fields',
      () async {
        for (final response in <Object?>[
          _response(tenantId: 'tenant-other'),
          _response(previousStatus: 'active'),
          _response(status: 'rejected'),
          _response(fanoutOperationId: 'bad/path'),
          {..._response(), 'extra': true},
        ]) {
          final gateway = _gateway(_ArchivalCallable(response: response));
          await expectLater(
            gateway.submit(
              gateway.createIntent(
                reason: 'Valid archival reason',
                confirmation: 'Business tenant-a (tenant-a)',
              ),
            ),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'rejects platform identity and stale record switches before calling',
      () async {
        final callable = _ArchivalCallable();
        final intent = _gateway(callable).createIntent(
          reason: 'Valid archival reason',
          confirmation: 'Business tenant-a (tenant-a)',
        );
        await expectLater(
          PlatformTenantArchivalGateway(
            identity: _identity(hasClaim: false),
            tenant: _tenant('tenant-a'),
            callable: callable,
          ).submit(intent),
          throwsStateError,
        );
        await expectLater(
          PlatformTenantArchivalGateway(
            identity: _identity(),
            tenant: _tenant('tenant-a', day: 2),
            callable: callable,
          ).submit(intent),
          throwsStateError,
        );
        await expectLater(
          PlatformTenantArchivalGateway(
            identity: _identity(),
            tenant: _tenant('tenant-b'),
            callable: callable,
          ).submit(intent),
          throwsStateError,
        );
        expect(callable.payloads, isEmpty);
      },
    );

    test('maps invariant and access failures to fixed safe text', () {
      expect(
        platformTenantArchivalSafeError(
          const PlatformTenantReviewCallableException('failed-precondition'),
        ),
        contains('changed'),
      );
      expect(
        platformTenantArchivalSafeError(
          const PlatformTenantReviewCallableException('permission-denied'),
        ),
        contains('no longer available'),
      );
    });
  });

  group('PlatformTenantArchivalForm', () {
    testWidgets('cancel and invalid confirmation perform no mutation', (
      tester,
    ) async {
      final callable = _ArchivalCallable();
      var cancelled = false;
      await tester.pumpWidget(
        _formApp(callable: callable, onCancel: () => cancelled = true),
      );
      expect(
        find.text('Archive Business tenant-a (tenant-a)?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('platform-archival-cancel')));
      await tester.pump();
      expect(cancelled, isTrue);

      await tester.enterText(
        find.byKey(const ValueKey('platform-archival-reason')),
        'Valid archival reason',
      );
      await tester.enterText(
        find.byKey(const ValueKey('platform-archival-confirmation')),
        'tenant-a',
      );
      await tester.tap(find.byKey(const ValueKey('platform-archival-confirm')));
      await tester.pump();
      expect(callable.payloads, isEmpty);
      expect(
        find.byKey(const ValueKey('platform-archival-error')),
        findsOneWidget,
      );
      // A refusal is §2.1's `problem`, and asserting it is what
      // the old red `Text` could not carry: the sentence alone
      // reads the same whether the write landed or not.
      expect(noticeStatus(tester, 'platform-archival-error'), AppStatus.problem);
    });

    testWidgets('duplicate taps are single-flight', (tester) async {
      final completer = Completer<Object?>();
      final callable = _ArchivalCallable(pending: completer);
      var successes = 0;
      await tester.pumpWidget(
        _formApp(callable: callable, onSuccess: (_) => successes++),
      );
      await _completeForm(tester);
      final confirm = find.byKey(const ValueKey('platform-archival-confirm'));
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
      final retrying = _ArchivalCallable(failures: 1);
      await tester.pumpWidget(_formApp(callable: retrying));
      await _completeForm(tester);
      final confirm = find.byKey(const ValueKey('platform-archival-confirm'));
      await tester.tap(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      expect(retrying.payloads, hasLength(2));
      expect(retrying.payloads.map((p) => p['requestId']).toSet(), {
        'archival-request-001',
      });

      final completer = Completer<Object?>();
      final stale = _ArchivalCallable(pending: completer);
      var current = true;
      var successes = 0;
      await tester.pumpWidget(
        _formApp(
          callable: stale,
          isCurrent: () => current,
          onSuccess: (_) => successes++,
        ),
      );
      await _completeForm(tester);
      await tester.tap(confirm);
      await tester.pump();
      current = false;
      completer.complete(_response());
      await tester.pump();
      expect(successes, 0);
    });
  });

  testWidgets('screen paginates and refreshes only after current success', (
    tester,
  ) async {
    final source = _ArchivalDataSource([
      _tenantDocument('tenant-a', day: 2),
      _tenantDocument('tenant-b', day: 1),
    ]);
    final callable = _ArchivalCallable();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlatformRejectedTenantScreen(
            identity: _identity(),
            dataSource: source,
            callable: callable,
            requestIdFactory: () => 'archival-request-001',
            pageSize: 1,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Business tenant-a'), findsOneWidget);
    expect(find.text('Business tenant-b'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('platform-archival-load-more')));
    await tester.pump();
    expect(find.text('Business tenant-b'), findsOneWidget);
    expect(source.pageCalls, 2);

    await tester.tap(find.byKey(const ValueKey('platform-archive-tenant-a')));
    await tester.pump();
    await _completeForm(tester);
    await tester.tap(find.byKey(const ValueKey('platform-archival-confirm')));
    await tester.pump();
    expect(source.pageCalls, 3);
  });
}

Future<void> _completeForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('platform-archival-reason')),
    'Valid archival reason',
  );
  await tester.enterText(
    find.byKey(const ValueKey('platform-archival-confirmation')),
    'Business tenant-a (tenant-a)',
  );
}

Widget _formApp({
  required _ArchivalCallable callable,
  VoidCallback? onCancel,
  ValueChanged<PlatformTenantArchivalResult>? onSuccess,
  PlatformTenantReviewCurrentCheck? isCurrent,
}) => MaterialApp(
  home: Scaffold(
    body: PlatformTenantArchivalForm(
      identity: _identity(),
      tenant: _tenant('tenant-a'),
      callable: callable,
      requestIdFactory: () => 'archival-request-001',
      isCurrent: isCurrent,
      onCancel: onCancel ?? () {},
      onSuccess: onSuccess ?? (_) {},
    ),
  ),
);

PlatformTenantArchivalGateway _gateway(_ArchivalCallable callable) =>
    PlatformTenantArchivalGateway(
      identity: _identity(),
      tenant: _tenant('tenant-a'),
      callable: callable,
      requestIdFactory: () => 'archival-request-001',
    );

PlatformReviewIdentity _identity({
  RootRoutingProfile profile = _platformProfile,
  bool hasClaim = true,
}) => PlatformReviewIdentity(
  uid: 'platform-user',
  profile: profile,
  hasSuperAdminClaim: hasClaim,
);

PlatformRejectedTenant _tenant(String tenantId, {int day = 1}) =>
    PlatformRejectedTenant.fromDocuments(
      tenant: _tenantDocument(tenantId, day: day),
      owner: _ownerDocument(tenantId),
    );

PlatformTenantDocument _tenantDocument(
  String tenantId, {
  String status = 'rejected',
  int day = 1,
}) => PlatformTenantDocument(
  id: tenantId,
  data: {
    'name': 'Business $tenantId',
    'slug': tenantId,
    'ownerUid': 'owner-$tenantId',
    'status': status,
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
  String previousStatus = 'rejected',
  String status = 'archived',
  String fanoutOperationId = 'fanout-operation-001',
}) => {
  'tenantId': tenantId,
  'previousStatus': previousStatus,
  'status': status,
  'fanoutOperationId': fanoutOperationId,
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

final class _ArchivalDataSource implements PlatformRejectedTenantDataSource {
  _ArchivalDataSource(this.documents);

  final List<PlatformTenantDocument> documents;
  final List<int> requestedLimits = [];
  final List<PlatformRejectedTenantCursor?> receivedCursors = [];
  int pageCalls = 0;

  @override
  Future<List<PlatformTenantDocument>> loadRejectedTenantDocuments({
    required int limit,
    PlatformRejectedTenantCursor? cursor,
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

final class _ArchivalCallable implements SetTenantLifecycleCallable {
  _ArchivalCallable({this.response, this.failures = 0, this.pending});

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
    return response ??
        {
          'tenantId': payload['tenantId'],
          'previousStatus': 'rejected',
          'status': payload['status'],
          'fanoutOperationId': 'fanout-operation-001',
        };
  }
}
