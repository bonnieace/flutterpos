import 'dart:io';

import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<String> box;
  late HiveTenantDirectoryCache cache;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tenant-directory-test-');
    Hive.init(directory.path);
    box = await Hive.openBox<String>(HiveTenantSelectionStore.boxName);
    cache = HiveTenantDirectoryCache(box);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  group('the device\'s copy of its businesses', () {
    test('round-trips every field the routing decision reads', () async {
      await cache.write('user-a', [
        _membership('tenant-a'),
        _membership('tenant-b', canAccess: false),
      ]);

      final restored = await cache.read('user-a');

      expect(restored, isNotNull);
      expect(restored!.memberships.map((item) => item.tenantId), [
        'tenant-a',
        'tenant-b',
      ]);
      // `canAccess` is the field the whole fallback turns on: a membership
      // that came back readable but not openable must stay that way.
      expect(restored.memberships.first.canAccess(), isTrue);
      expect(restored.memberships.last.canAccess(), isFalse);
      expect(restored.memberships.first.role, TenantRole.admin);
    });

    test(
      'never answers one account with another account\'s businesses',
      () async {
        await cache.write('user-a', [_membership('tenant-a')]);

        expect(await cache.read('user-b'), isNull);
      },
    );

    test('an unreadable cache reads as no cache at all', () async {
      // A corrupt local file must never be the reason a till will not open.
      await box.put('user-a:tenantDirectory', 'not json');

      expect(await cache.read('user-a'), isNull);
    });

    test(
      'a cache from a future version is ignored rather than raised',
      () async {
        await box.put('user-a:tenantDirectory', '{"schemaVersion":99}');

        expect(await cache.read('user-a'), isNull);
      },
    );
  });

  group('the directory\'s offline fallback', () {
    test('serves the last copy when the server cannot be reached', () async {
      final gateway = _FakeGateway(page: _page([_membership('tenant-a')]));
      final directory = TenantDirectory(gateway, cache: cache);
      await directory.load(uid: 'user-a');

      gateway.failWith = const TenantDirectoryUnavailable('unavailable');
      final offline = await directory.load(uid: 'user-a');

      expect(offline.fromCache, isTrue);
      expect(offline.memberships.single.tenantId, 'tenant-a');
      expect(offline.cachedAt, isNotNull);
    });

    test('a live answer is never reported as remembered', () async {
      final directory = TenantDirectory(
        _FakeGateway(page: _page([_membership('tenant-a')])),
        cache: cache,
      );

      final live = await directory.load(uid: 'user-a');

      expect(live.fromCache, isFalse);
      expect(live.cachedAt, isNull);
    });

    test('a refusal is never rescued by the cache', () async {
      final gateway = _FakeGateway(page: _page([_membership('tenant-a')]));
      final directory = TenantDirectory(gateway, cache: cache);
      await directory.load(uid: 'user-a');

      // **The safety boundary.** An account whose access has been revoked
      // answers `permission-denied`, and must keep answering it however much
      // this device remembers about happier times.
      gateway.failWith = StateError('permission-denied');
      await expectLater(
        directory.load(uid: 'user-a'),
        throwsA(isA<StateError>()),
      );
    });

    test('a malformed answer is never rescued by the cache', () async {
      final gateway = _FakeGateway(page: _page([_membership('tenant-a')]));
      final directory = TenantDirectory(gateway, cache: cache);
      await directory.load(uid: 'user-a');

      // The server answered and the answer was wrong. Falling back would hide
      // a real defect behind a stale success.
      gateway.failWith = const FormatException('Invalid listMyTenants.');
      await expectLater(
        directory.load(uid: 'user-a'),
        throwsA(isA<FormatException>()),
      );
    });

    test('a device that has never been online still fails', () async {
      final directory = TenantDirectory(
        _FakeGateway(page: _page(const []))
          ..failWith = const TenantDirectoryUnavailable('unavailable'),
        cache: cache,
      );

      await expectLater(
        directory.load(uid: 'user-a'),
        throwsA(isA<TenantDirectoryUnavailable>()),
      );
    });

    test(
      'no uid means no fallback, which is what the switcher needs',
      () async {
        final gateway = _FakeGateway(page: _page([_membership('tenant-a')]));
        final directory = TenantDirectory(gateway, cache: cache);
        await directory.load(uid: 'user-a');

        // Tenant switching is online-gated in its own right and must not be
        // answered from a cache keyed to nobody.
        gateway.failWith = const TenantDirectoryUnavailable('unavailable');
        await expectLater(
          directory.load(),
          throwsA(isA<TenantDirectoryUnavailable>()),
        );
      },
    );
  });
}

TenantListPage _page(List<TenantMembership> items) =>
    TenantListPage(items: items, nextCursor: null, hasMore: false);

final class _FakeGateway implements TenantDirectoryGateway {
  _FakeGateway({required this.page});

  final TenantListPage page;
  Object? failWith;

  @override
  Future<TenantListPage> listMyTenants({
    required int pageSize,
    String? cursor,
  }) async {
    final failure = failWith;
    if (failure != null) throw failure;
    return page;
  }
}

TenantMembership _membership(String tenantId, {bool canAccess = true}) =>
    TenantMembership(
      tenantId: tenantId,
      tenantName: tenantId,
      tenantSlug: tenantId,
      role: TenantRole.admin,
      membershipStatus: MembershipStatus.active,
      tenantStatus: TenantStatus.active,
      isOwner: false,
      mirrorVersion: 1,
      createdAt: DateTime.utc(2026, 7, 29),
      updatedAt: DateTime.utc(2026, 7, 29),
      serverCanAccess: canAccess,
      canonicalTenantExists: true,
      canonicalMembershipExists: true,
    );
