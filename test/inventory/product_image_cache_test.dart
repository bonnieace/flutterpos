import 'dart:io';
import 'dart:typed_data';

import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late LazyBox<Uint8List> bytes;
  late Box<dynamic> index;
  late HiveTenantImageCache cache;
  late DateTime now;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('image-cache-');
    Hive.init(directory.path);
    bytes = await Hive.openLazyBox<Uint8List>('image-bytes-test');
    index = await Hive.openBox<dynamic>('image-index-test');
    now = DateTime.utc(2026, 9, 5);
    cache = HiveTenantImageCache.fromBoxes(
      bytes: bytes,
      index: index,
      // Small enough that two pictures fit and three do not.
      budgetBytes: 300,
      clock: () => now,
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Uint8List blob(int size, int fill) =>
      Uint8List.fromList(List<int>.filled(size, fill));

  void tick() => now = now.add(const Duration(minutes: 1));

  test('a written picture reads back, and a URL never seen misses', () async {
    final url = Uri.parse('https://example.test/a.jpg');
    await cache.write(url, blob(100, 1));

    expect(await cache.read(url), blob(100, 1));
    expect(await cache.read(Uri.parse('https://example.test/b.jpg')), isNull);
  });

  test('a picture survives the boxes being reopened', () async {
    final url = Uri.parse('https://example.test/a.jpg');
    await cache.write(url, blob(100, 1));
    await Hive.close();

    Hive.init(directory.path);
    final reopened = HiveTenantImageCache.fromBoxes(
      bytes: await Hive.openLazyBox<Uint8List>('image-bytes-test'),
      index: await Hive.openBox<dynamic>('image-index-test'),
    );

    expect(await reopened.read(url), blob(100, 1));
  });

  test('the least recently used picture is the one evicted', () async {
    final a = Uri.parse('https://example.test/a.jpg');
    final b = Uri.parse('https://example.test/b.jpg');
    final c = Uri.parse('https://example.test/c.jpg');
    await cache.write(a, blob(150, 1));
    tick();
    await cache.write(b, blob(150, 2));
    // Reading is what makes `a` the newer of the two, which is the whole point
    // of the touch on the read path.
    tick();
    expect(await cache.read(a), isNotNull);
    tick();

    await cache.write(c, blob(150, 3));

    expect(await cache.read(c), isNotNull);
    expect(await cache.read(a), isNotNull);
    expect(await cache.read(b), isNull);
  });

  test('a picture over the entry ceiling is drawn but never kept', () async {
    final url = Uri.parse('https://example.test/huge.jpg');

    await cache.write(url, blob(HiveTenantImageCache.maximumEntryBytes + 1, 9));

    expect(await cache.read(url), isNull);
  });

  test('an index entry whose bytes are gone reads as a miss', () async {
    final url = Uri.parse('https://example.test/a.jpg');
    await cache.write(url, blob(100, 1));
    await bytes.deleteAll(bytes.keys);

    expect(await cache.read(url), isNull);
    // The index is what was wrong, and it is dropped rather than left to
    // report a picture this device does not have.
    expect(index.isEmpty, isTrue);
  });
}
