import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformGlobalUserLookup', () {
    test('requires the platform root and claim before any read', () async {
      for (final identity in [
        _identity(hasClaim: false),
        _identity(profile: _tenantProfile),
        _identity(profile: _disabledPlatformProfile),
      ]) {
        final source = _GlobalUserDataSource();
        await expectLater(
          PlatformGlobalUserLookup(
            identity: identity,
            dataSource: source,
          ).load('target-user'),
          throwsStateError,
        );
        expect(source.rootLoads, isEmpty);
      }
    });

    test('loads one exact UID and canonical administrative impacts', () async {
      final source = _GlobalUserDataSource();
      final result = await PlatformGlobalUserLookup(
        identity: _identity(),
        dataSource: source,
      ).load(' target-user ');

      expect(source.rootLoads.first, 'target-user');
      expect(source.staffLookupUids, ['target-user']);
      expect(source.ownerLookupUids, ['target-user']);
      expect(result?.user.uid, 'target-user');
      expect(result?.affectedTenants.map((tenant) => tenant.tenantId), [
        'tenant-admin',
        'tenant-owner',
      ]);
      expect(
        result?.affectedTenants.first.impact,
        PlatformAdministrativeImpact.noActiveAdministrator,
      );
      expect(
        result?.affectedTenants.last.impact,
        PlatformAdministrativeImpact.ownerUnavailable,
      );
      expect(result?.administrativeWarnings, hasLength(2));
    });

    test('returns null only when the exact canonical root is absent', () async {
      final source = _GlobalUserDataSource(rootExists: false);
      final result = await PlatformGlobalUserLookup(
        identity: _identity(),
        dataSource: source,
      ).load('missing-user');
      expect(result, isNull);
      expect(source.staffLookupUids, isEmpty);
    });

    test('rejects invalid UID and malformed canonical relationships', () async {
      final source = _GlobalUserDataSource();
      final lookup = PlatformGlobalUserLookup(
        identity: _identity(),
        dataSource: source,
      );
      await expectLater(lookup.load('bad/path'), throwsArgumentError);
      expect(source.rootLoads, isEmpty);

      final malformed = _GlobalUserDataSource(malformedStaffUid: true);
      await expectLater(
        PlatformGlobalUserLookup(
          identity: _identity(),
          dataSource: malformed,
        ).load('target-user'),
        throwsFormatException,
      );
    });

    test('counts only canonical active tenant-user administrators', () async {
      final source = _GlobalUserDataSource(includeActiveAdmin: true);
      final result = await PlatformGlobalUserLookup(
        identity: _identity(),
        dataSource: source,
      ).load('target-user');
      final adminTenant = result!.affectedTenants.first;
      expect(adminTenant.remainingActiveAdministrators, 1);
      expect(adminTenant.impact, PlatformAdministrativeImpact.none);
    });
  });

  group('FirebasePlatformGlobalUserDataSource', () {
    test(
      'strictly decodes one callable review and reuses its snapshot',
      () async {
        final callable = _ReviewCallable(_reviewResponse());
        final result = await PlatformGlobalUserLookup(
          identity: _identity(),
          dataSource: FirebasePlatformGlobalUserDataSource(callable: callable),
        ).load('target-user');

        expect(callable.payloads, [
          {'uid': 'target-user'},
        ]);
        expect(result?.affectedTenants, hasLength(2));
        expect(result?.administrativeWarnings, hasLength(2));
      },
    );

    test('rejects extra response fields and mismatched target roots', () async {
      for (final response in [
        {..._reviewResponse(), 'extra': true},
        _reviewResponse(userId: 'other-user'),
      ]) {
        await expectLater(
          PlatformGlobalUserLookup(
            identity: _identity(),
            dataSource: FirebasePlatformGlobalUserDataSource(
              callable: _ReviewCallable(response),
            ),
          ).load('target-user'),
          throwsFormatException,
        );
      }
    });
  });

  group('PlatformGlobalUserStatusGateway', () {
    test('derives a disable payload and normalizes the reason', () async {
      final callable = _StatusCallable();
      final target = await _target();
      final gateway = _gateway(target, callable);
      final result = await gateway.submit(
        gateway.createIntent(
          action: PlatformGlobalUserAction.disable,
          reason: '  Confirmed   security incident. ',
          confirmation: ' target-user ',
        ),
      );
      expect(callable.payloads.single, {
        'uid': 'target-user',
        'status': 'disabled',
        'reason': 'Confirmed security incident.',
        'requestId': 'global-status-request-001',
      });
      expect(result.isCompleted, isTrue);
      expect(result.targetStatus, PlatformGlobalStatus.disabled);
    });

    test(
      'allows only record-derived transitions and exact disable UID',
      () async {
        final active = await _target();
        final disabled = await _target(status: 'disabled');
        expect(
          () => _gateway(active, _StatusCallable()).createIntent(
            action: PlatformGlobalUserAction.reactivate,
            reason: 'Support verified recovery.',
          ),
          throwsStateError,
        );
        expect(
          () => _gateway(disabled, _StatusCallable()).createIntent(
            action: PlatformGlobalUserAction.disable,
            reason: 'Security incident.',
            confirmation: 'target-user',
          ),
          throwsStateError,
        );
        for (final reason in ['', 'x', 'bad\u0000reason']) {
          expect(
            () => _gateway(active, _StatusCallable()).createIntent(
              action: PlatformGlobalUserAction.disable,
              reason: reason,
              confirmation: 'target-user',
            ),
            throwsArgumentError,
          );
        }
        expect(
          () => _gateway(active, _StatusCallable()).createIntent(
            action: PlatformGlobalUserAction.disable,
            reason: 'Security incident.',
            confirmation: 'other-user',
          ),
          throwsArgumentError,
        );
      },
    );

    test('strictly rejects every response mismatch and extra field', () async {
      final target = await _target();
      for (final response in <Object?>[
        _response(operationId: 'other-operation'),
        _response(uid: 'other-user'),
        _response(targetStatus: 'active'),
        _response(status: 'pending'),
        _response(affectedTenantIds: ['tenant-owner', 'tenant-admin']),
        _response(attemptCount: 0),
        {..._response(), 'extra': true},
      ]) {
        final gateway = _gateway(target, _StatusCallable(response: response));
        await expectLater(
          gateway.submit(
            gateway.createIntent(
              action: PlatformGlobalUserAction.disable,
              reason: 'Security incident.',
              confirmation: 'target-user',
            ),
          ),
          throwsFormatException,
        );
      }
    });

    test(
      'decodes a safe partial failure but requires its error code',
      () async {
        final target = await _target();
        final gateway = _gateway(
          target,
          _StatusCallable(
            response: _response(
              status: 'partially_failed',
              lastErrorCode: 'auth/internal-error',
            ),
          ),
        );
        final result = await gateway.submit(
          gateway.createIntent(
            action: PlatformGlobalUserAction.disable,
            reason: 'Security incident.',
            confirmation: 'target-user',
          ),
        );
        expect(result.isCompleted, isFalse);
        expect(result.lastErrorCode, 'auth/internal-error');

        final invalid = _gateway(
          target,
          _StatusCallable(response: _response(status: 'partially_failed')),
        );
        await expectLater(
          invalid.submit(
            invalid.createIntent(
              action: PlatformGlobalUserAction.disable,
              reason: 'Security incident.',
              confirmation: 'target-user',
            ),
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'rejects lost eligibility and target record switches before call',
      () async {
        final target = await _target();
        final callable = _StatusCallable();
        final intent = _gateway(target, callable).createIntent(
          action: PlatformGlobalUserAction.disable,
          reason: 'Security incident.',
          confirmation: 'target-user',
        );
        await expectLater(
          PlatformGlobalUserStatusGateway(
            identity: _identity(hasClaim: false),
            target: target,
            callable: callable,
          ).submit(intent),
          throwsStateError,
        );
        await expectLater(
          _gateway(await _target(day: 2), callable).submit(intent),
          throwsStateError,
        );
        expect(callable.payloads, isEmpty);
      },
    );
  });

  group('PlatformGlobalUserStatusForm', () {
    testWidgets('duplicate taps are single-flight', (tester) async {
      final pending = Completer<Object?>();
      final callable = _StatusCallable(pending: pending);
      var completions = 0;
      await tester.pumpWidget(
        await _formApp(callable: callable, onCompleted: (_) => completions++),
      );
      await _completeDisableForm(tester);
      final confirm = find.byKey(
        const ValueKey('platform-global-status-confirm'),
      );
      await tester.tap(confirm);
      await tester.tap(confirm);
      await tester.pump();
      expect(callable.payloads, hasLength(1));
      pending.complete(_response());
      await tester.pump();
      expect(completions, 1);
    });

    testWidgets('callable retry reuses the same reviewed request ID', (
      tester,
    ) async {
      final callable = _StatusCallable(failures: 1);
      await tester.pumpWidget(await _formApp(callable: callable));
      await _completeDisableForm(tester);
      final confirm = find.byKey(
        const ValueKey('platform-global-status-confirm'),
      );
      await tester.tap(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      expect(callable.payloads, hasLength(2));
      expect(callable.payloads.map((item) => item['requestId']).toSet(), {
        'global-status-request-001',
      });
    });

    testWidgets(
      'partial response stays retryable and stale completion is ignored',
      (tester) async {
        final partial = _StatusCallable(
          response: _response(
            status: 'partially_failed',
            lastErrorCode: 'auth/internal-error',
          ),
        );
        await tester.pumpWidget(await _formApp(callable: partial));
        await _completeDisableForm(tester);
        await tester.tap(
          find.byKey(const ValueKey('platform-global-status-confirm')),
        );
        await tester.pump();
        expect(find.text(platformGlobalUserPartialFailureText), findsOneWidget);

        final completer = Completer<Object?>();
        final stale = _StatusCallable(pending: completer);
        var current = true;
        var completions = 0;
        await tester.pumpWidget(
          await _formApp(
            callable: stale,
            isCurrent: () => current,
            onCompleted: (_) => completions++,
          ),
        );
        await _completeDisableForm(tester);
        await tester.tap(
          find.byKey(const ValueKey('platform-global-status-confirm')),
        );
        await tester.pump();
        current = false;
        completer.complete(_response());
        await tester.pump();
        expect(completions, 0);
      },
    );
  });

  testWidgets('screen performs exact lookup and refreshes only that UID', (
    tester,
  ) async {
    final source = _GlobalUserDataSource();
    final callable = _StatusCallable();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlatformGlobalUserStatusScreen(
            identity: _identity(),
            dataSource: source,
            callable: callable,
            requestIdFactory: () => 'global-status-request-001',
            onCurrentOperatorAffected: () async {},
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('platform-global-user-uid')),
      'target-user',
    );
    await tester.tap(find.byKey(const ValueKey('platform-global-user-lookup')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('platform-global-user-target-user')),
      findsOneWidget,
    );
    expect(find.textContaining('business warning(s)'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('platform-disable-global-user')),
    );
    await tester.pump();
    await _completeDisableForm(tester);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('platform-global-status-confirm')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('platform-global-status-confirm')),
    );
    await tester.pumpAndSettle();
    expect(source.rootLoads.where((uid) => uid == 'target-user'), hasLength(2));
  });
}

Future<void> _completeDisableForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('platform-global-status-reason')),
    'Confirmed security incident.',
  );
  await tester.enterText(
    find.byKey(const ValueKey('platform-global-status-confirmation')),
    'target-user',
  );
}

Future<Widget> _formApp({
  required _StatusCallable callable,
  ValueChanged<PlatformGlobalUserStatusResult>? onCompleted,
  PlatformTenantCurrentCheck? isCurrent,
}) async => MaterialApp(
  home: Scaffold(
    body: PlatformGlobalUserStatusForm(
      identity: _identity(),
      target: await _target(),
      action: PlatformGlobalUserAction.disable,
      callable: callable,
      requestIdFactory: () => 'global-status-request-001',
      isCurrent: isCurrent,
      onCompleted: onCompleted ?? (_) {},
      onCancel: () {},
    ),
  ),
);

PlatformGlobalUserStatusGateway _gateway(
  PlatformGlobalUserLookupResult target,
  _StatusCallable callable,
) => PlatformGlobalUserStatusGateway(
  identity: _identity(),
  target: target,
  callable: callable,
  requestIdFactory: () => 'global-status-request-001',
);

Future<PlatformGlobalUserLookupResult> _target({
  String status = 'active',
  int day = 1,
}) async => (await PlatformGlobalUserLookup(
  identity: _identity(),
  dataSource: _GlobalUserDataSource(status: status, day: day),
).load('target-user'))!;

PlatformAdminIdentity _identity({
  RootRoutingProfile profile = _platformProfile,
  bool hasClaim = true,
}) => PlatformAdminIdentity(
  uid: 'platform-user',
  profile: profile,
  hasSuperAdminClaim: hasClaim,
);

Map<String, Object?> _response({
  String operationId = 'global-status-request-001',
  String uid = 'target-user',
  String status = 'completed',
  String targetStatus = 'disabled',
  List<String> affectedTenantIds = const ['tenant-admin', 'tenant-owner'],
  int attemptCount = 1,
  String? lastErrorCode,
}) => {
  'operationId': operationId,
  'uid': uid,
  'status': status,
  'targetStatus': targetStatus,
  'affectedTenantIds': affectedTenantIds,
  'attemptCount': attemptCount,
  if (lastErrorCode != null) 'lastErrorCode': lastErrorCode,
};

Map<String, Object?> _reviewResponse({String userId = 'target-user'}) => {
  'found': true,
  'user': {
    'id': userId,
    'data': {
      'email': 'target-user@example.test',
      'displayName': 'Target User',
      'accountType': 'tenant_user',
      'globalStatus': 'active',
      'updatedAtMillis': DateTime.utc(2026, 7, 1).millisecondsSinceEpoch,
    },
  },
  'targetStaff': [
    {
      'tenantId': 'tenant-admin',
      'id': 'target-user',
      'data': {'uid': 'target-user', 'role': 'admin', 'status': 'active'},
    },
    {
      'tenantId': 'tenant-owner',
      'id': 'target-user',
      'data': {'uid': 'target-user', 'role': 'owner', 'status': 'active'},
    },
  ],
  'ownedTenants': [
    {
      'id': 'tenant-owner',
      'data': {
        'name': 'Business tenant-owner',
        'slug': 'tenant-owner',
        'ownerUid': 'target-user',
        'status': 'active',
      },
    },
  ],
  'tenants': [
    {
      'id': 'tenant-admin',
      'data': {
        'name': 'Business tenant-admin',
        'slug': 'tenant-admin',
        'ownerUid': 'other-owner',
        'status': 'active',
      },
    },
    {
      'id': 'tenant-owner',
      'data': {
        'name': 'Business tenant-owner',
        'slug': 'tenant-owner',
        'ownerUid': 'target-user',
        'status': 'active',
      },
    },
  ],
  'administrativeStaff': [
    {
      'tenantId': 'tenant-admin',
      'id': 'target-user',
      'data': {'uid': 'target-user', 'role': 'admin', 'status': 'active'},
    },
    {
      'tenantId': 'tenant-owner',
      'id': 'target-user',
      'data': {'uid': 'target-user', 'role': 'owner', 'status': 'active'},
    },
  ],
  'administrativeRoots': <Object?>[],
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

final class _GlobalUserDataSource implements PlatformGlobalUserDataSource {
  _GlobalUserDataSource({
    this.rootExists = true,
    this.malformedStaffUid = false,
    this.includeActiveAdmin = false,
    this.status = 'active',
    this.day = 1,
  });

  final bool rootExists;
  final bool malformedStaffUid;
  final bool includeActiveAdmin;
  final String status;
  final int day;
  final List<String> rootLoads = [];
  final List<String> staffLookupUids = [];
  final List<String> ownerLookupUids = [];

  @override
  Future<void> prepareExactReview(String uid) async {}

  @override
  Future<PlatformTenantDocument?> loadRootUser(String uid) async {
    rootLoads.add(uid);
    if (uid == 'missing-user' || (!rootExists && uid == 'target-user')) {
      return null;
    }
    final isTarget = uid == 'target-user';
    return PlatformTenantDocument(
      id: uid,
      data: {
        'email': '$uid@example.test',
        'displayName': isTarget ? 'Target User' : 'Other Administrator',
        'accountType': 'tenant_user',
        'globalStatus': isTarget ? status : 'active',
        'updatedAt': DateTime.utc(2026, 7, day),
      },
    );
  }

  @override
  Future<List<PlatformCanonicalStaffDocument>> loadTargetStaffDocuments(
    String uid,
  ) async {
    staffLookupUids.add(uid);
    return [
      _staff(
        tenantId: 'tenant-admin',
        uid: malformedStaffUid ? 'wrong-user' : uid,
        documentId: uid,
        role: 'admin',
      ),
      _staff(tenantId: 'tenant-owner', uid: uid, role: 'owner'),
    ];
  }

  @override
  Future<List<PlatformTenantDocument>> loadOwnedTenantDocuments(
    String uid,
  ) async {
    ownerLookupUids.add(uid);
    return [_tenantDocument('tenant-owner', ownerUid: uid)];
  }

  @override
  Future<PlatformTenantDocument?> loadTenant(String tenantId) async =>
      _tenantDocument(tenantId, ownerUid: 'other-owner');

  @override
  Future<List<PlatformCanonicalStaffDocument>> loadAdministrativeStaffDocuments(
    String tenantId,
  ) async => [
    if (tenantId == 'tenant-owner')
      _staff(tenantId: tenantId, uid: 'target-user', role: 'owner')
    else
      _staff(tenantId: tenantId, uid: 'target-user', role: 'admin'),
    if (includeActiveAdmin)
      _staff(tenantId: tenantId, uid: 'other-admin', role: 'admin'),
  ];
}

PlatformCanonicalStaffDocument _staff({
  required String tenantId,
  required String uid,
  String? documentId,
  required String role,
}) => PlatformCanonicalStaffDocument(
  tenantId: tenantId,
  id: documentId ?? uid,
  data: {'uid': uid, 'role': role, 'status': 'active'},
);

PlatformTenantDocument _tenantDocument(
  String tenantId, {
  required String ownerUid,
}) => PlatformTenantDocument(
  id: tenantId,
  data: {
    'name': 'Business $tenantId',
    'slug': tenantId,
    'ownerUid': ownerUid,
    'status': 'active',
  },
);

final class _StatusCallable implements SetGlobalUserStatusCallable {
  _StatusCallable({this.response, this.failures = 0, this.pending});

  final Object? response;
  int failures;
  final Completer<Object?>? pending;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    if (failures > 0) {
      failures--;
      throw const PlatformGlobalUserStatusCallableException('unavailable');
    }
    if (pending != null) return pending!.future;
    return response ??
        _response(
          operationId: payload['requestId']! as String,
          uid: payload['uid']! as String,
          targetStatus: payload['status']! as String,
        );
  }
}

final class _ReviewCallable implements GetGlobalUserStatusReviewCallable {
  _ReviewCallable(this.response);

  final Object? response;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    return response;
  }
}
