import 'dart:async';

import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'directory follows opaque cursors until the server says complete',
    () async {
      final gateway = _FakeGateway(
        pages: <String?, TenantListPage>{
          null: TenantListPage(
            items: [_membership('tenant-a')],
            nextCursor: 'cursor-1',
            hasMore: true,
          ),
          'cursor-1': TenantListPage(
            items: [_membership('tenant-b')],
            nextCursor: null,
            hasMore: false,
          ),
        },
      );

      final memberships = await TenantDirectory(gateway).loadAll();

      expect(memberships.map((item) => item.tenantId), [
        'tenant-a',
        'tenant-b',
      ]);
      expect(gateway.requestedCursors, [null, 'cursor-1']);
    },
  );

  test('directory rejects repeated cursors', () async {
    final gateway = _FakeGateway(
      pages: <String?, TenantListPage>{
        null: TenantListPage(
          items: const [],
          nextCursor: 'loop',
          hasMore: true,
        ),
        'loop': TenantListPage(
          items: const [],
          nextCursor: 'loop',
          hasMore: true,
        ),
      },
    );

    await expectLater(TenantDirectory(gateway).loadAll(), throwsStateError);
  });

  test('directory rejects duplicate tenant IDs across pages', () async {
    final gateway = _FakeGateway(
      pages: <String?, TenantListPage>{
        null: TenantListPage(
          items: [_membership('tenant-a')],
          nextCursor: 'cursor-1',
          hasMore: true,
        ),
        'cursor-1': TenantListPage(
          items: [_membership('tenant-a')],
          nextCursor: null,
          hasMore: false,
        ),
      },
    );

    await expectLater(TenantDirectory(gateway).loadAll(), throwsStateError);
  });

  test(
    'bootstrap combines root, local selection, and complete directory',
    () async {
      final gateway = _FakeGateway(
        profile: const RootRoutingProfile(
          accountType: RootAccountType.tenantUser,
          globalStatus: 'active',
          defaultTenantId: 'tenant-a',
        ),
        pages: <String?, TenantListPage>{
          null: TenantListPage(
            items: [_membership('tenant-a'), _membership('tenant-b')],
            nextCursor: null,
            hasMore: false,
          ),
        },
      );
      final store = _MemorySelectionStore('tenant-b');
      final bootstrap = TenantBootstrapService(
        rootGateway: gateway,
        directory: TenantDirectory(gateway),
        selectionStore: store,
      );

      final result = await bootstrap.load('user-a');

      expect(result.kind, TenantBootstrapKind.tenant);
      expect(result.selection.source, TenantSelectionSource.lastSelected);
      expect(result.selection.selected?.tenantId, 'tenant-b');
      final opened = await bootstrap.openTenant(
        uid: 'user-a',
        tenantId: 'tenant-a',
      );
      expect(opened.tenantId, 'tenant-a');
      expect(store.value, 'tenant-a');
    },
  );

  test('cached bootstrap asks neither root nor directory gateway', () async {
    final gateway = _HangingGateway();
    final now = DateTime.utc(2026, 8, 30, 9);
    final bootstrap = TenantBootstrapService(
      rootGateway: gateway,
      rootCache: _MemoryRootCache(
        CachedRootRoutingProfile(profile: _activeProfile, cachedAt: now),
      ),
      directory: TenantDirectory(
        gateway,
        cache: _MemoryDirectoryCache(
          CachedTenantDirectory(
            memberships: [_membership('tenant-a')],
            cachedAt: now,
          ),
        ),
      ),
      selectionStore: _MemorySelectionStore('tenant-a'),
    );

    final result = await bootstrap.loadCached('user-a');

    expect(result?.kind, TenantBootstrapKind.tenant);
    expect(result?.selection.selected?.tenantId, 'tenant-a');
    expect(result?.fromCache, isTrue);
    expect(gateway.rootCalls, 0);
    expect(gateway.directoryCalls, 0);
  });

  test(
    'cached bootstrap requires both root and directory projections',
    () async {
      final gateway = _HangingGateway();
      final bootstrap = TenantBootstrapService(
        rootGateway: gateway,
        rootCache: _MemoryRootCache(
          CachedRootRoutingProfile(
            profile: _activeProfile,
            cachedAt: DateTime.utc(2026, 8, 30),
          ),
        ),
        directory: TenantDirectory(gateway),
        selectionStore: _MemorySelectionStore('tenant-a'),
      );

      expect(await bootstrap.loadCached('user-a'), isNull);
      expect(gateway.rootCalls, 0);
      expect(gateway.directoryCalls, 0);
    },
  );

  test('platform identities never load tenant memberships', () async {
    final gateway = _FakeGateway(
      profile: const RootRoutingProfile(
        accountType: RootAccountType.platformAdmin,
        globalStatus: 'active',
      ),
    );
    final result = await TenantBootstrapService(
      rootGateway: gateway,
      directory: TenantDirectory(gateway),
      selectionStore: _MemorySelectionStore(null),
    ).load('platform-user');

    expect(result.kind, TenantBootstrapKind.platform);
    expect(gateway.requestedCursors, isEmpty);
  });

  test('disabled roots fail before tenant routing', () async {
    final gateway = _FakeGateway(
      profile: const RootRoutingProfile(
        accountType: RootAccountType.tenantUser,
        globalStatus: 'disabled',
      ),
    );

    await expectLater(
      TenantBootstrapService(
        rootGateway: gateway,
        directory: TenantDirectory(gateway),
        selectionStore: _MemorySelectionStore(null),
      ).load('user-a'),
      throwsStateError,
    );
    expect(gateway.requestedCursors, isEmpty);
  });

  test('tenant opening revalidates canonical access', () async {
    final gateway = _FakeGateway(
      pages: <String?, TenantListPage>{
        null: TenantListPage(
          items: [_membership('tenant-a')],
          nextCursor: null,
          hasMore: false,
        ),
      },
    );
    final bootstrap = TenantBootstrapService(
      rootGateway: gateway,
      directory: TenantDirectory(gateway),
      selectionStore: _MemorySelectionStore(null),
    );

    expect((await bootstrap.revalidateTenant('tenant-a')).tenantId, 'tenant-a');
    await expectLater(
      bootstrap.revalidateTenant('tenant-missing'),
      throwsStateError,
    );
  });

  test('tenant opening never remembers inaccessible routing state', () async {
    final gateway = _FakeGateway(
      pages: <String?, TenantListPage>{
        null: TenantListPage(
          items: [
            _membership(
              'tenant-a',
              membershipStatus: MembershipStatus.inactive,
              canAccess: false,
            ),
          ],
          nextCursor: null,
          hasMore: false,
        ),
      },
    );
    final store = _MemorySelectionStore(null);
    final bootstrap = TenantBootstrapService(
      rootGateway: gateway,
      directory: TenantDirectory(gateway),
      selectionStore: store,
    );

    await expectLater(
      bootstrap.openTenant(uid: 'user-a', tenantId: 'tenant-a'),
      throwsStateError,
    );
    expect(store.value, isNull);
  });

  test('root routing profile rejects malformed default tenant IDs', () {
    expect(
      () => RootRoutingProfile.fromJson(const <String, Object?>{
        'accountType': 'tenant_user',
        'globalStatus': 'active',
        'defaultTenantId': 'escape/path',
      }),
      throwsFormatException,
    );
  });

  test('root routing profile storage shape round-trips', () {
    final restored = RootRoutingProfile.fromJson(_activeProfile.toJson());
    expect(restored.accountType, RootAccountType.tenantUser);
    expect(restored.globalStatus, 'active');
    expect(restored.defaultTenantId, 'tenant-a');
  });
}

const _activeProfile = RootRoutingProfile(
  accountType: RootAccountType.tenantUser,
  globalStatus: 'active',
  defaultTenantId: 'tenant-a',
);

final class _HangingGateway
    implements TenantDirectoryGateway, RootRoutingGateway {
  int rootCalls = 0;
  int directoryCalls = 0;

  @override
  Future<RootRoutingProfile> getRootRoutingProfile(String uid) {
    rootCalls++;
    return Completer<RootRoutingProfile>().future;
  }

  @override
  Future<TenantListPage> listMyTenants({
    required int pageSize,
    String? cursor,
  }) {
    directoryCalls++;
    return Completer<TenantListPage>().future;
  }
}

final class _MemoryRootCache implements RootRoutingProfileCache {
  _MemoryRootCache(this.value);

  CachedRootRoutingProfile? value;

  @override
  Future<CachedRootRoutingProfile?> read(String uid) async => value;

  @override
  Future<void> write(String uid, RootRoutingProfile profile) async {
    value = CachedRootRoutingProfile(
      profile: profile,
      cachedAt: DateTime.now().toUtc(),
    );
  }
}

final class _MemoryDirectoryCache implements TenantDirectoryCache {
  _MemoryDirectoryCache(this.value);

  CachedTenantDirectory? value;

  @override
  Future<CachedTenantDirectory?> read(String uid) async => value;

  @override
  Future<void> write(String uid, Iterable<TenantMembership> memberships) async {
    value = CachedTenantDirectory(
      memberships: List<TenantMembership>.from(memberships),
      cachedAt: DateTime.now().toUtc(),
    );
  }
}

final class _FakeGateway implements TenantDirectoryGateway, RootRoutingGateway {
  _FakeGateway({
    this.profile = const RootRoutingProfile(
      accountType: RootAccountType.tenantUser,
      globalStatus: 'active',
    ),
    this.pages = const <String?, TenantListPage>{},
  });

  final RootRoutingProfile profile;
  final Map<String?, TenantListPage> pages;
  final List<String?> requestedCursors = <String?>[];

  @override
  Future<RootRoutingProfile> getRootRoutingProfile(String uid) async => profile;

  @override
  Future<TenantListPage> listMyTenants({
    required int pageSize,
    String? cursor,
  }) async {
    requestedCursors.add(cursor);
    final page = pages[cursor];
    if (page == null) throw StateError('Missing fake page for $cursor');
    return page;
  }
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
  bool canAccess = true,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: TenantRole.admin,
  membershipStatus: membershipStatus,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: canAccess,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
