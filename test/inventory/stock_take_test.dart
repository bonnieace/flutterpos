import 'dart:io';

import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// The count as it exists on the device, before any server sees it.
///
/// Two properties are load-bearing and everything here defends one of them:
///
/// - **A blank line and a zero are different facts.** One means nobody got to
///   the product; the other means somebody looked and the shelf was empty. The
///   difference has to survive typing, storage, paging and the payload, or an
///   uncounted product silently becomes a claim of nothing on the shelf.
/// - **A count is durable before it is sent.** The take's ID is minted once and
///   the page a line falls in is positional, so a submission interrupted halfway
///   resumes by sending the same pages again.
void main() {
  const tenantId = 'tenant-a';
  const counter = 'user-cashier';
  final startedAt = DateTime.utc(2026, 9, 13, 6);

  TenantStockTakeDraft draft({
    Map<String, TenantStockTakeCount>? counts,
    TenantStockTakeScope scope = const TenantStockTakeEverything(),
    int productsInScope = 40,
  }) => TenantStockTakeDraft(
    takeId: tenantStockTakeId(
      tenantId: tenantId,
      counterUid: counter,
      requestId: 'stocktake-fixed',
      businessDate: '2026-09-13',
    ),
    tenantId: tenantId,
    businessDate: '2026-09-13',
    scope: scope,
    productsInScope: productsInScope,
    startedAt: startedAt,
    counts: counts ?? const <String, TenantStockTakeCount>{},
  );

  TenantStockTakeCount count(int counted, {int? seen = 12}) =>
      TenantStockTakeCount(
        counted: counted,
        seenQuantity: seen,
        countedAt: DateTime.utc(2026, 9, 13, 7, 30),
      );

  group('what a number typed means', () {
    test('a blank field is not a count of zero', () {
      // **The distinction the whole model rests on.** Absent means nobody got
      // there; zero means somebody looked.
      expect(tenantStockTakeCountOf(''), isNull);
      expect(tenantStockTakeCountOf('   '), isNull);
      expect(tenantStockTakeCountOf('0'), 0);
    });

    test('a shelf cannot hold a negative, fractional or absurd number', () {
      for (final raw in <String>['-1', '1.5', 'four', '1e5']) {
        expect(
          () => tenantStockTakeCountOf(raw),
          throwsA(
            isA<TenantStockTakeException>().having(
              (error) => error.failure,
              'failure',
              TenantStockTakeFailure.invalidCount,
            ),
          ),
          reason: raw,
        );
      }
      expect(tenantStockTakeCountOf('$maximumStockTakeCount'), maximumStockTakeCount);
      expect(
        () => tenantStockTakeCountOf('${maximumStockTakeCount + 1}'),
        throwsA(isA<TenantStockTakeException>()),
      );
    });

    test('clearing a field removes the line rather than storing zero', () {
      final counted = draft(
        counts: <String, TenantStockTakeCount>{'pd-1': count(4)},
      );
      expect(counted.countedLineCount, 1);

      final cleared = counted.withoutCount('pd-1');
      expect(cleared.counts.containsKey('pd-1'), isFalse);
      expect(cleared.isEmpty, isTrue);

      // And a zero typed deliberately is kept, which is the other half of it.
      expect(counted.withCount('pd-1', count(0)).counts['pd-1']!.counted, 0);
    });
  });

  group('the take identity', () {
    test('one request mints one take, and a different request another', () {
      final first = tenantStockTakeId(
        tenantId: tenantId,
        counterUid: counter,
        requestId: 'stocktake-a',
        businessDate: '2026-09-13',
      );

      expect(
        first,
        tenantStockTakeId(
          tenantId: tenantId,
          counterUid: counter,
          requestId: 'stocktake-a',
          businessDate: '2026-09-13',
        ),
        reason: 'a retry of one count must address one take',
      );
      expect(first, startsWith('st_2026-09-13_'));
      expect(first.length, 54);
      for (final other in <String>[
        tenantStockTakeId(
          tenantId: tenantId,
          counterUid: counter,
          requestId: 'stocktake-b',
          businessDate: '2026-09-13',
        ),
        tenantStockTakeId(
          tenantId: 'tenant-b',
          counterUid: counter,
          requestId: 'stocktake-a',
          businessDate: '2026-09-13',
        ),
        tenantStockTakeId(
          tenantId: tenantId,
          counterUid: 'user-other',
          requestId: 'stocktake-a',
          businessDate: '2026-09-13',
        ),
      ]) {
        expect(other, isNot(first));
      }
    });

    test('take IDs sort into the order the days happened in', () {
      // **Load-bearing, not cosmetic.** The tenant repositories page by document
      // ID and by nothing else, so this is the whole of what makes management's
      // review list read newest-first. A bare digest would make it arbitrary -
      // which is exactly what the `stock_adjustments` feed is stuck with.
      final ids = <String>[
        for (final date in <String>['2026-09-14', '2026-09-02', '2026-10-01'])
          tenantStockTakeId(
            tenantId: tenantId,
            counterUid: counter,
            requestId: 'stocktake-a',
            businessDate: date,
          ),
      ]..sort();

      expect(
        ids.map((id) => id.substring(3, 13)),
        <String>['2026-09-02', '2026-09-14', '2026-10-01'],
      );
    });

    test('a fresh request ID is not guessable and is differently shaped', () {
      final ids = <String>{
        for (var i = 0; i < 50; i++) secureTenantStockTakeRequestId(),
      };
      expect(ids, hasLength(50));
      expect(ids.first, startsWith('stocktake-'));
    });
  });

  group('paging', () {
    test('lines split in product order, and only the last page finishes it', () {
      final counts = <String, TenantStockTakeCount>{
        for (var i = 0; i < 7; i++)
          'pd-${i.toString().padLeft(3, '0')}': count(i),
      };
      final pages = tenantStockTakePages(draft(counts: counts), pageSize: 3);

      expect(pages.map((page) => page.page), <int>[0, 1, 2]);
      expect(pages.map((page) => page.lines.length), <int>[3, 3, 1]);
      expect(
        pages.map((page) => page.isFinalPage),
        <bool>[false, false, true],
        reason: 'the take is only complete when its last page lands',
      );
      // Deterministic, so a resent submission is the same submission rather
      // than one that merely converges on the same documents.
      expect(
        pages.expand((page) => page.lines.map((line) => line.key)).toList(),
        counts.keys.toList()..sort(),
      );
    });

    test('every page carries the take, not the products in it', () {
      final pages = tenantStockTakePages(
        draft(
          counts: <String, TenantStockTakeCount>{
            'pd-1': count(1),
            'pd-2': count(2),
          },
        ),
        pageSize: 1,
      );

      // One path for the whole count: the outbox drains one path in order, so
      // the pages queue behind each other and nobody else's count waits.
      expect(pages.map((page) => page.path).toSet(), hasLength(1));
      expect(pages.first.path, endsWith('/stock_takes/${pages.first.takeId}'));
      // And a distinct record each, or the second would replace the first.
      expect(pages.map((page) => page.operationId).toSet(), hasLength(2));
    });

    test('a count with nothing in it has nothing to send', () {
      expect(
        () => tenantStockTakePages(draft()),
        throwsA(
          isA<TenantStockTakeException>().having(
            (error) => error.failure,
            'failure',
            TenantStockTakeFailure.nothingCounted,
          ),
        ),
      );
    });

    test('a page never exceeds what one server transaction accepts', () {
      final counts = <String, TenantStockTakeCount>{
        for (var i = 0; i < maximumStockTakeLinesPerPage + 5; i++)
          'pd-${i.toString().padLeft(3, '0')}': count(i),
      };
      final pages = tenantStockTakePages(draft(counts: counts));

      expect(pages, hasLength(2));
      expect(pages.first.lines, hasLength(maximumStockTakeLinesPerPage));
      for (final size in <int>[0, -1, maximumStockTakeLinesPerPage + 1]) {
        expect(
          () => tenantStockTakePages(draft(counts: counts), pageSize: size),
          throwsA(isA<TenantStockTakeException>()),
          reason: 'page size $size',
        );
      }
    });
  });

  group('the payload', () {
    test('carries exactly what submitStockTake reads, and no expected figure', () {
      final page = tenantStockTakePages(
        draft(
          counts: <String, TenantStockTakeCount>{'pd-1': count(9, seen: 11)},
          scope: const TenantStockTakeCategory('cat-bakery'),
          productsInScope: 12,
        ),
      ).single;
      final payload = page.payload();

      expect(payload.keys.toSet(), <String>{
        'tenantId',
        'takeId',
        'businessDate',
        'scope',
        'productsInScope',
        'page',
        'isFinalPage',
        'lines',
      });
      expect(payload['scope'], <String, Object?>{
        'kind': 'category',
        'categoryId': 'cat-bakery',
      });
      expect(payload['isFinalPage'], isTrue);

      final line = (payload['lines']! as List).single as Map<String, Object?>;
      expect(line, <String, Object?>{
        'productId': 'pd-1',
        'counted': 9,
        'seenQuantity': 11,
        'countedAt': '2026-09-13T07:30:00.000Z',
      });
      // **Nothing the count was taken blind to may travel in either direction.**
      // The device never has the server's figure and must not invent one.
      expect(line.containsKey('expected'), isFalse);
      expect(line.containsKey('variance'), isFalse);
    });

    test('a device with no figure of its own still records the count', () {
      final page = tenantStockTakePages(
        draft(counts: <String, TenantStockTakeCount>{'pd-1': count(3, seen: null)}),
      ).single;

      final line = (page.payload()['lines']! as List).single as Map<String, Object?>;
      expect(line['counted'], 3);
      expect(line['seenQuantity'], isNull);
    });
  });

  group('storage', () {
    test('a draft round-trips with its counts intact', () {
      final original = draft(
        counts: <String, TenantStockTakeCount>{
          'pd-1': count(4),
          'pd-2': count(0, seen: null),
        },
        scope: const TenantStockTakeCategory('cat-bakery'),
      );

      final restored = TenantStockTakeDraft.fromStorage(original.toStorage());

      expect(restored.takeId, original.takeId);
      expect(restored.businessDate, '2026-09-13');
      expect(restored.scope, const TenantStockTakeCategory('cat-bakery'));
      expect(restored.productsInScope, 40);
      expect(restored.countedLineCount, 2);
      expect(restored.counts['pd-1']!.counted, 4);
      expect(restored.counts['pd-1']!.seenQuantity, 12);
      expect(restored.counts['pd-2']!.counted, 0);
      expect(restored.counts['pd-2']!.seenQuantity, isNull);
      expect(restored.counts['pd-1']!.countedAt, DateTime.utc(2026, 9, 13, 7, 30));
    });

    test('a damaged record is refused rather than half-read', () {
      for (final broken in <Map<String, Object?>>[
        <String, Object?>{'takeId': 'st_a'},
        <String, Object?>{
          ...draft().toStorage(),
          'scope': <String, Object?>{'kind': 'aisle'},
        },
        <String, Object?>{...draft().toStorage(), 'startedAt': 'not a time'},
      ]) {
        expect(
          () => TenantStockTakeDraft.fromStorage(broken),
          throwsA(isA<TenantStockTakeException>()),
        );
      }
    });
  });

  group('the device store', () {
    late Directory directory;
    late Box<dynamic> box;
    late HiveTenantStockTakeDrafts drafts;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('stock-take-');
      Hive.init(directory.path);
      box = await Hive.openBox<dynamic>('stock-take-test');
      drafts = HiveTenantStockTakeDrafts.fromBox(box);
    });

    tearDown(() async {
      await Hive.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('a count survives being put down and picked up again', () async {
      // The case this exists for: the app is killed mid-aisle.
      await drafts.save(
        uid: counter,
        draft: draft(counts: <String, TenantStockTakeCount>{'pd-1': count(4)}),
      );

      final reopened = HiveTenantStockTakeDrafts.fromBox(box);
      final restored = reopened.draftFor(uid: counter, tenantId: tenantId);
      expect(restored, isNotNull);
      expect(restored!.counts['pd-1']!.counted, 4);
    });

    test('one person\'s count is not another\'s, nor another business\'s', () async {
      await drafts.save(
        uid: counter,
        draft: draft(counts: <String, TenantStockTakeCount>{'pd-1': count(4)}),
      );

      expect(drafts.draftFor(uid: 'user-other', tenantId: tenantId), isNull);
      expect(drafts.draftFor(uid: counter, tenantId: 'tenant-b'), isNull);
    });

    test('clearing it leaves nothing behind', () async {
      await drafts.save(
        uid: counter,
        draft: draft(counts: <String, TenantStockTakeCount>{'pd-1': count(4)}),
      );
      await drafts.clear(uid: counter, tenantId: tenantId);

      expect(drafts.draftFor(uid: counter, tenantId: tenantId), isNull);
    });

    test('an unreadable record does not refuse every future count', () async {
      // Nothing can be done with a half-parsed count, and leaving it in place
      // would block this device from ever starting another.
      await box.put(
        tenantStockTakeDraftKey(uid: counter, tenantId: tenantId),
        <String, Object?>{'takeId': 'st_a', 'counts': 'not a map'},
      );

      expect(drafts.draftFor(uid: counter, tenantId: tenantId), isNull);
      await drafts.save(
        uid: counter,
        draft: draft(counts: <String, TenantStockTakeCount>{'pd-1': count(4)}),
      );
      expect(drafts.draftFor(uid: counter, tenantId: tenantId), isNotNull);
    });
  });
}
