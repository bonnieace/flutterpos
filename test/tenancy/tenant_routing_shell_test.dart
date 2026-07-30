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
  late final TenantBootstrapService service;
  TenantSessionController? openedController;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: TenantRoutingShell(
        authUidChanges: auth.stream,
        bootstrapService: service,
        signOut: () async => auth.add(null),
        signedOut: const Scaffold(body: Center(child: Text('Signed out'))),
        tenantRouteBuilder: (context, controller, membership) {
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
  final RootRoutingProfile profile;
  final Future<RootRoutingProfile>? profileFuture;
  int rootFailures;
  int listCalls = 0;

  @override
  Future<RootRoutingProfile> getRootRoutingProfile(String uid) async {
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

  @override
  Future<void> setDefaultTenant({
    required String tenantId,
    required String requestId,
  }) async {}
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
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: 'Business $tenantId',
  tenantSlug: tenantId,
  role: TenantRole.admin,
  membershipStatus: membershipStatus,
  tenantStatus: tenantStatus,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: canAccess,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
