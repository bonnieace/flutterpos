import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens the UID-local selected business', (tester) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a'), _membership('tenant-b')],
      localTenantId: 'tenant-b',
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Business tenant-b'), findsOneWidget);
    expect(fixture.store.value, 'tenant-b');
    await fixture.dispose(tester);
  });

  testWidgets('opens the account default when no local choice is valid', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a'), _membership('tenant-b')],
      profile: const RootRoutingProfile(
        accountType: RootAccountType.tenantUser,
        globalStatus: 'active',
        defaultTenantId: 'tenant-a',
      ),
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Business tenant-a'), findsOneWidget);
    expect(fixture.store.value, 'tenant-a');
    await fixture.dispose(tester);
  });

  testWidgets('opens the sole accessible business automatically', (
    tester,
  ) async {
    final fixture = _ShellFixture(memberships: [_membership('tenant-only')]);
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Business tenant-only'), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets(
    'refreshes the routing profile only after making a tenant default',
    (tester) async {
      late final _ShellFixture fixture;
      final callable = _ShellDefaultCallable((tenantId) {
        fixture.gateway.profile = RootRoutingProfile(
          accountType: RootAccountType.tenantUser,
          globalStatus: 'active',
          defaultTenantId: tenantId,
        );
      });
      fixture = _ShellFixture(
        memberships: [_membership('tenant-a')],
        useDefaultRoute: true,
        setDefaultTenantCallable: callable,
      );
      await fixture.pump(tester);

      fixture.auth.add('user-a');
      await _pumpRouting(tester);
      expect(fixture.gateway.rootCalls, 1);

      await tester.tap(find.byKey(const ValueKey('make-default-tenant')));
      await tester.pumpAndSettle();
      expect(fixture.gateway.rootCalls, 1);
      await tester.tap(
        find.byKey(const ValueKey('set-default-tenant-confirm')),
      );
      await _pumpRouting(tester);

      expect(callable.payloads.single, {
        'tenantId': 'tenant-a',
        'requestId': 'routing-default-request',
      });
      expect(fixture.gateway.rootCalls, 2);
      expect(find.text('Default business'), findsOneWidget);
      await fixture.dispose(tester);
    },
  );

  testWidgets('shows a selector and revalidates the chosen business', (
    tester,
  ) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a'), _membership('tenant-b')],
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Choose a business'), findsOneWidget);
    expect(find.text('admin - Accessible'), findsNWidgets(2));

    await tester.tap(find.text('Business tenant-b'));
    await _pumpRouting(tester);

    expect(find.text('Business tenant-b'), findsOneWidget);
    expect(fixture.gateway.listCalls, 2);
    expect(fixture.store.value, 'tenant-b');
    await fixture.dispose(tester);
  });

  testWidgets(
    'requests a pending business from no-access routing without opening it',
    (tester) async {
      late final _ShellFixture fixture;
      final callable = _ShellRequestCallable((name, slug) {
        fixture.gateway.memberships.add(
          _membership(
            'tenant-requested',
            membershipStatus: MembershipStatus.active,
            tenantStatus: TenantStatus.pending,
            canAccess: false,
          ),
        );
      });
      fixture = _ShellFixture(
        memberships: [],
        emailVerified: true,
        requestTenantCallable: callable,
      );
      await fixture.pump(tester);

      fixture.auth.add('user-a');
      await _pumpRouting(tester);
      expect(find.byKey(const ValueKey('show-tenant-request')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('show-tenant-request')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('tenant-request-name')),
        '  New   Business ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('tenant-request-slug')),
        ' New-Business ',
      );
      await tester.tap(find.byKey(const ValueKey('tenant-request-review')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tenant-request-confirm')));
      await _pumpRouting(tester);

      expect(callable.payloads.single, {
        'name': 'New Business',
        'slug': 'new-business',
        'requestId': 'routing-tenant-request',
      });
      expect(fixture.gateway.rootCalls, 2);
      expect(fixture.gateway.listCalls, 2);
      expect(find.text('Business tenant-requested'), findsOneWidget);
      expect(find.text('admin - Pending'), findsOneWidget);
      expect(fixture.openedController, isNull);
      await fixture.dispose(tester);
    },
  );

  testWidgets('shows tenant requests only to verified tenant identities', (
    tester,
  ) async {
    final unverified = _ShellFixture(memberships: []);
    await unverified.pump(tester);
    unverified.auth.add('user-a');
    await _pumpRouting(tester);
    expect(find.byKey(const ValueKey('show-tenant-request')), findsNothing);
    await unverified.dispose(tester);

    final platform = _ShellFixture(
      memberships: [],
      emailVerified: true,
      profile: const RootRoutingProfile(
        accountType: RootAccountType.platformAdmin,
        globalStatus: 'active',
      ),
    );
    await platform.pump(tester);
    platform.auth.add('platform-user');
    await _pumpRouting(tester);
    expect(find.byKey(const ValueKey('show-tenant-request')), findsNothing);
    await platform.dispose(tester);
  });

  testWidgets('gates the platform queue on both root and superAdmin claim', (
    tester,
  ) async {
    final deniedSource = _ShellPlatformDataSource();
    final denied = _ShellFixture(
      memberships: [],
      profile: const RootRoutingProfile(
        accountType: RootAccountType.platformAdmin,
        globalStatus: 'active',
      ),
      platformDataSource: deniedSource,
    );
    await denied.pump(tester);
    denied.auth.add('platform-user');
    await _pumpRouting(tester);
    expect(
      find.text('Platform administrator access is not available.'),
      findsOneWidget,
    );
    expect(deniedSource.pageCalls, 0);
    await denied.dispose(tester);

    final allowedSource = _ShellPlatformDataSource();
    final allowed = _ShellFixture(
      memberships: [],
      profile: const RootRoutingProfile(
        accountType: RootAccountType.platformAdmin,
        globalStatus: 'active',
      ),
      platformClaim: true,
      platformDataSource: allowedSource,
    );
    await allowed.pump(tester);
    allowed.auth.add('platform-user');
    await _pumpRouting(tester);
    expect(find.text('Pending business reviews'), findsOneWidget);
    expect(find.text('Routing Review Business'), findsOneWidget);
    expect(allowedSource.pageCalls, 1);
    await tester.tap(find.text('Active & suspended'));
    await tester.pumpAndSettle();
    expect(find.text('Routing Active Business'), findsOneWidget);
    expect(allowedSource.lifecycleCalls, 1);
    await tester.tap(find.text('Rejected archive'));
    await tester.pumpAndSettle();
    expect(find.text('Routing Rejected Business'), findsOneWidget);
    expect(allowedSource.archivalCalls, 1);
    await tester.tap(find.text('Global user status'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('platform-global-user-uid')),
      'routing-target-user',
    );
    await tester.tap(find.byKey(const ValueKey('platform-global-user-lookup')));
    await tester.pumpAndSettle();
    expect(find.text('Routing Target User'), findsOneWidget);
    expect(allowedSource.globalUserStaffCalls, 1);
    await allowed.dispose(tester);
  });

  testWidgets('labels every inaccessible membership state', (tester) async {
    final fixture = _ShellFixture(
      memberships: [
        _membership(
          'pending',
          membershipStatus: MembershipStatus.pending,
          canAccess: false,
        ),
        _membership(
          'inactive',
          membershipStatus: MembershipStatus.inactive,
          canAccess: false,
        ),
        _membership(
          'rejected',
          tenantStatus: TenantStatus.rejected,
          canAccess: false,
        ),
        _membership(
          'suspended',
          tenantStatus: TenantStatus.suspended,
          canAccess: false,
        ),
        _membership(
          'archived',
          tenantStatus: TenantStatus.archived,
          canAccess: false,
        ),
      ],
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('admin - Pending'), findsOneWidget);
    expect(find.text('admin - Inactive'), findsOneWidget);
    expect(find.text('admin - Rejected'), findsOneWidget);
    expect(find.text('admin - Suspended'), findsOneWidget);
    expect(find.text('admin - Archived'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(5));
    await fixture.dispose(tester);
  });

  testWidgets('accepts a parsed proof link then refreshes tenant routing', (
    tester,
  ) async {
    final callable = _TokenAcceptCallable();
    final fixture = _ShellFixture(
      memberships: [
        _membership(
          'tenant-a',
          membershipStatus: MembershipStatus.pending,
          canAccess: false,
          invitationStatus: 'sent',
        ),
      ],
      invitationLink: _tokenInvitationLink(),
      acceptTenantInvitationCallable: callable,
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(find.text('Business invitation'), findsOneWidget);
    expect(
      find.text('Accept invitation to Business tenant-a?'),
      findsOneWidget,
    );
    expect(find.text('Invited role: admin'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('accept-token-invitation-confirm')),
    );
    await _pumpRouting(tester);

    expect(callable.payloads.single, {
      'tenantId': 'tenant-a',
      'invitationVersion': 4,
      'invitationToken': _invitationToken,
      'requestId': 'routing-accept-request',
    });
    expect(fixture.gateway.listCalls, 2);
    expect(find.text('Choose a business'), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets('ignores a stale bootstrap completion after sign-out', (
    tester,
  ) async {
    final profile = Completer<RootRoutingProfile>();
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      profileFuture: profile.future,
    );
    await fixture.pump(tester);

    fixture.auth.add('user-a');
    await tester.pump();
    fixture.auth.add(null);
    await tester.pump();
    profile.complete(_activeProfile);
    await _pumpRouting(tester);

    expect(find.text('Signed out'), findsOneWidget);
    expect(fixture.openedController, isNull);
    await fixture.dispose(tester);
  });

  testWidgets('clears the selected session on an Auth UID transition', (
    tester,
  ) async {
    final fixture = _ShellFixture(memberships: [_membership('tenant-a')]);
    await fixture.pump(tester);
    fixture.auth.add('user-a');
    await _pumpRouting(tester);
    final controller = fixture.openedController!;
    expect(controller.hasSession, isTrue);

    fixture.auth.add(null);
    await _pumpRouting(tester);

    expect(controller.hasSession, isFalse);
    expect(find.text('Signed out'), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets('offers retry and sign-out when bootstrap fails', (tester) async {
    final fixture = _ShellFixture(
      memberships: [_membership('tenant-a')],
      rootFailures: 1,
    );
    await fixture.pump(tester);
    fixture.auth.add('user-a');
    await _pumpRouting(tester);

    expect(
      find.text('We could not open your business account.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await _pumpRouting(tester);

    expect(find.text('Business tenant-a'), findsOneWidget);
    await fixture.dispose(tester);
  });
}

Future<void> _pumpRouting(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
    await tester.pump();
  }
}

const _activeProfile = RootRoutingProfile(
  accountType: RootAccountType.tenantUser,
  globalStatus: 'active',
);

final class _ShellFixture {
  _ShellFixture({
    required List<TenantMembership> memberships,
    RootRoutingProfile profile = _activeProfile,
    Future<RootRoutingProfile>? profileFuture,
    String? localTenantId,
    int rootFailures = 0,
    this.invitationLink,
    this.acceptTenantInvitationCallable,
    this.useDefaultRoute = false,
    this.setDefaultTenantCallable,
    this.emailVerified = false,
    this.requestTenantCallable,
    this.platformClaim = false,
    this.platformDataSource,
  }) : gateway = _FakeGateway(
         memberships: memberships,
         profile: profile,
         profileFuture: profileFuture,
         rootFailures: rootFailures,
       ),
       store = _MemorySelectionStore(localTenantId) {
    service = TenantBootstrapService(
      rootGateway: gateway,
      directory: TenantDirectory(gateway),
      selectionStore: store,
    );
  }

  final StreamController<String?> auth = StreamController<String?>();
  final _FakeGateway gateway;
  final _MemorySelectionStore store;
  final TenantInvitationLink? invitationLink;
  final AcceptTenantInvitationCallable? acceptTenantInvitationCallable;
  final bool useDefaultRoute;
  final SetDefaultTenantCallable? setDefaultTenantCallable;
  final bool emailVerified;
  final RequestTenantCallable? requestTenantCallable;
  final bool platformClaim;
  final _ShellPlatformDataSource? platformDataSource;
  late final TenantBootstrapService service;
  TenantSessionController? openedController;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: TenantRoutingShell(
        authUidChanges: auth.stream,
        bootstrapService: service,
        signOut: () async => auth.add(null),
        signedOut: const Scaffold(body: Center(child: Text('Signed out'))),
        isEmailVerified: (_) => emailVerified,
        invitationLink: invitationLink,
        acceptTenantInvitationCallable: acceptTenantInvitationCallable,
        invitationAcceptanceRequestIdFactory: () => 'routing-accept-request',
        setDefaultTenantCallable: setDefaultTenantCallable,
        defaultTenantRequestIdFactory: () => 'routing-default-request',
        requestTenantCallable: requestTenantCallable,
        tenantRequestIdFactory: () => 'routing-tenant-request',
        hasPlatformSuperAdminClaim: (_) async => platformClaim,
        platformPendingTenantDataSource: platformDataSource,
        platformLifecycleTenantDataSource: platformDataSource,
        platformRejectedTenantDataSource: platformDataSource,
        platformGlobalUserDataSource: platformDataSource,
        setTenantLifecycleCallable: _ShellLifecycleCallable(),
        setGlobalUserStatusCallable: _ShellGlobalStatusCallable(),
        platformTenantReviewRequestIdFactory: () => 'routing-platform-review',
        tenantDataReader: useDefaultRoute ? _RoutingReader() : null,
        tenantRouteBuilder: useDefaultRoute
            ? null
            : (context, controller, membership) {
                openedController = controller;
                return Scaffold(body: Text('Business ${membership.tenantId}'));
              },
      ),
    ),
  );

  Future<void> dispose(WidgetTester tester) async {
    await auth.close();
    await tester.pumpWidget(const SizedBox());
  }
}

final class _FakeGateway implements TenantDirectoryGateway, RootRoutingGateway {
  _FakeGateway({
    required this.memberships,
    required this.profile,
    this.profileFuture,
    this.rootFailures = 0,
  });

  final List<TenantMembership> memberships;
  RootRoutingProfile profile;
  final Future<RootRoutingProfile>? profileFuture;
  int rootFailures;
  int listCalls = 0;
  int rootCalls = 0;

  @override
  Future<RootRoutingProfile> getRootRoutingProfile(String uid) async {
    rootCalls++;
    if (rootFailures > 0) {
      rootFailures--;
      throw StateError('Temporary bootstrap failure.');
    }
    return profileFuture ?? profile;
  }

  @override
  Future<TenantListPage> listMyTenants({
    required int pageSize,
    String? cursor,
  }) async {
    listCalls++;
    return TenantListPage(items: memberships, nextCursor: null, hasMore: false);
  }
}

final class _ShellDefaultCallable implements SetDefaultTenantCallable {
  _ShellDefaultCallable(this.onCall);

  final void Function(String tenantId) onCall;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    final tenantId = payload['tenantId']! as String;
    onCall(tenantId);
    return {'tenantId': tenantId, 'defaultTenantId': tenantId};
  }
}

final class _ShellRequestCallable implements RequestTenantCallable {
  _ShellRequestCallable(this.onCall);

  final void Function(String name, String slug) onCall;
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    final name = payload['name']! as String;
    final slug = payload['slug']! as String;
    onCall(name, slug);
    return {
      'tenantId': 'tenant-requested',
      'name': name,
      'slug': slug,
      'status': 'pending',
    };
  }
}

final class _ShellPlatformDataSource
    implements
        PlatformPendingTenantDataSource,
        PlatformLifecycleTenantDataSource,
        PlatformRejectedTenantDataSource,
        PlatformGlobalUserDataSource {
  int pageCalls = 0;
  int lifecycleCalls = 0;
  int archivalCalls = 0;
  int globalUserStaffCalls = 0;

  @override
  Future<void> prepareExactReview(String uid) async {}

  @override
  Future<List<PlatformTenantDocument>> loadPendingTenantDocuments({
    required int limit,
    PlatformPendingTenantCursor? cursor,
  }) async {
    pageCalls++;
    if (cursor != null) return const [];
    return [
      PlatformTenantDocument(
        id: 'routing-review-tenant',
        data: {
          'name': 'Routing Review Business',
          'slug': 'routing-review-tenant',
          'ownerUid': 'routing-review-owner',
          'status': 'pending',
          'createdAt': DateTime.utc(2026, 7, 30),
        },
      ),
    ];
  }

  @override
  Future<PlatformTenantDocument?> loadRootUser(String uid) async =>
      PlatformTenantDocument(
        id: uid,
        data: {
          'email': '$uid@example.test',
          'displayName': uid == 'routing-target-user'
              ? 'Routing Target User'
              : 'Routing Owner',
          'accountType': 'tenant_user',
          'globalStatus': 'active',
          'updatedAt': DateTime.utc(2026, 7, 30),
        },
      );

  @override
  Future<List<PlatformCanonicalStaffDocument>> loadTargetStaffDocuments(
    String uid,
  ) async {
    globalUserStaffCalls++;
    return const [];
  }

  @override
  Future<List<PlatformTenantDocument>> loadOwnedTenantDocuments(
    String uid,
  ) async => const [];

  @override
  Future<PlatformTenantDocument?> loadTenant(String tenantId) async => null;

  @override
  Future<List<PlatformCanonicalStaffDocument>> loadAdministrativeStaffDocuments(
    String tenantId,
  ) async => const [];

  @override
  Future<List<PlatformTenantDocument>> loadLifecycleTenantDocuments({
    required int limit,
    PlatformLifecycleTenantCursor? cursor,
  }) async {
    lifecycleCalls++;
    if (cursor != null) return const [];
    return [
      PlatformTenantDocument(
        id: 'routing-active-tenant',
        data: {
          'name': 'Routing Active Business',
          'slug': 'routing-active-tenant',
          'ownerUid': 'routing-review-owner',
          'status': 'active',
          'updatedAt': DateTime.utc(2026, 7, 30),
        },
      ),
    ];
  }

  @override
  Future<List<PlatformTenantDocument>> loadRejectedTenantDocuments({
    required int limit,
    PlatformRejectedTenantCursor? cursor,
  }) async {
    archivalCalls++;
    if (cursor != null) return const [];
    return [
      PlatformTenantDocument(
        id: 'routing-rejected-tenant',
        data: {
          'name': 'Routing Rejected Business',
          'slug': 'routing-rejected-tenant',
          'ownerUid': 'routing-review-owner',
          'status': 'rejected',
          'updatedAt': DateTime.utc(2026, 7, 30),
        },
      ),
    ];
  }
}

final class _ShellLifecycleCallable implements SetTenantLifecycleCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async => {
    'tenantId': payload['tenantId'],
    'previousStatus': 'pending',
    'status': payload['status'],
    'fanoutOperationId': 'routing-fanout-operation',
  };
}

final class _ShellGlobalStatusCallable implements SetGlobalUserStatusCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async => {
    'operationId': payload['requestId'],
    'uid': payload['uid'],
    'status': 'completed',
    'targetStatus': payload['status'],
    'affectedTenantIds': <String>[],
    'attemptCount': 1,
  };
}

final class _RoutingReader implements TenantDataReader {
  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const [];
}

final class _MemorySelectionStore implements TenantSelectionStore {
  _MemorySelectionStore(this.value);

  String? value;

  @override
  Future<String?> readLastSelectedTenant(String uid) async => value;

  @override
  Future<void> writeLastSelectedTenant(String uid, String tenantId) async {
    value = tenantId;
  }
}

TenantMembership _membership(
  String tenantId, {
  MembershipStatus membershipStatus = MembershipStatus.active,
  TenantStatus tenantStatus = TenantStatus.active,
  bool canAccess = true,
  String? invitationStatus,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: 'Business $tenantId',
  tenantSlug: tenantId,
  role: TenantRole.admin,
  membershipStatus: membershipStatus,
  tenantStatus: tenantStatus,
  invitationStatus: invitationStatus,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: canAccess,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

final class _TokenAcceptCallable implements AcceptTenantInvitationCallable {
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
    return <String, Object?>{
      'tenantId': payload['tenantId'],
      'uid': 'user-a',
      'role': 'admin',
      'membershipStatus': 'active',
      'invitationStatus': 'accepted',
    };
  }
}

TenantInvitationLink _tokenInvitationLink() =>
    TenantInvitationLink.fromUriIfPresent(
      Uri.parse(
        'https://pos.example.test/invitations?tenantId=tenant-a&uid=user-a'
        '&invitationVersion=4&invitationToken=$_invitationToken',
      ),
    )!;

const _invitationToken = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
