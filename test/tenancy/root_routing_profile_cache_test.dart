import 'dart:io';

import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<String> box;
  late HiveRootRoutingProfileCache cache;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('root-routing-cache-');
    Hive.init(directory.path);
    box = await Hive.openBox<String>(HiveTenantSelectionStore.boxName);
    cache = HiveRootRoutingProfileCache(box);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('round-trips a UID-bound root profile', () async {
    await cache.write(
      'user-a',
      const RootRoutingProfile(
        accountType: RootAccountType.tenantUser,
        globalStatus: 'active',
        defaultTenantId: 'tenant-a',
      ),
    );

    final restored = await cache.read('user-a');

    expect(restored, isNotNull);
    expect(restored!.profile.accountType, RootAccountType.tenantUser);
    expect(restored.profile.defaultTenantId, 'tenant-a');
    expect(restored.cachedAt.isUtc, isTrue);
    expect(await cache.read('user-b'), isNull);
  });

  test('corrupt and future-version entries read as absent', () async {
    await box.put(rootRoutingProfileStorageKey('user-a'), 'not json');
    expect(await cache.read('user-a'), isNull);

    await box.put(
      rootRoutingProfileStorageKey('user-a'),
      '{"schemaVersion":99,"uid":"user-a"}',
    );
    expect(await cache.read('user-a'), isNull);
  });
}
