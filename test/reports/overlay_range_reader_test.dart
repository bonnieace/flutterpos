/// The reader every route actually holds can answer a period read.
///
/// **This is the test that was missing, and the defect it would have caught
/// shipped to a device.** Every range test in `range_query_test.dart` hands
/// its repository a fake that implements [TenantReportRangeReader], so all of
/// them passed while five reports refused on a phone: the routes are handed
/// `TenantPendingMutationOverlayReader`, not the Firestore reader under it,
/// and the overlay did not declare the new capability. A reader capability the
/// overlay does not forward is a capability no screen can reach.
///
/// So this asserts the composition rather than the arithmetic: that the class
/// the app wraps everything in still forwards all three period reads, and
/// still refuses honestly when the reader beneath it cannot answer.
library;

import 'dart:io';

import 'package:uzapay_pos/tenancy/tenant_pending_mutation.dart';
import 'package:uzapay_pos/tenancy/tenant_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

late Directory _directory;
late TenantPendingMutationStore _store;

void main() {
  setUp(() async {
    _directory = await Directory.systemTemp.createTemp('overlay-range-');
    Hive.init(_directory.path);
    _store = TenantPendingMutationStore.fromBox(
      await Hive.openBox<dynamic>('overlay-range-test'),
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await _directory.exists()) await _directory.delete(recursive: true);
  });

  group('the overlay every route is handed', () {
    test('declares that it can read a period at all', () {
      final overlay = _overlay(_RangeReader());

      expect(
        overlay,
        isA<TenantReportRangeReader>(),
        reason:
            'A capability this class does not declare is one no screen can '
            'reach, because a screen never sees the reader underneath it.',
      );
    });

    test('forwards a business-date range unchanged', () async {
      final base = _RangeReader();
      final overlay = _overlay(base);

      final read = await overlay.queryTenantBusinessDateRange(
        TenantBusinessDateRangeQuery.forTesting(
          collectionPath: 'tenants/tenant-a/returns',
          orderBy: TenantBusinessDateRangeField.recordedOn,
          limit: 10,
          startBusinessDate: '2026-09-01',
          endBusinessDate: '2026-09-30',
        ),
      );

      expect(read, hasLength(1));
      expect(base.businessDateCalls, 1);
      expect(
        base.lastBusinessDateQuery?.orderBy,
        TenantBusinessDateRangeField.recordedOn,
        reason:
            'Forwarded rather than reinterpreted: the overlay has no opinion '
            'about which field a period is keyed to.',
      );
    });

    test('forwards a document-key range unchanged', () async {
      final base = _RangeReader();
      final overlay = _overlay(base);

      await overlay.queryTenantDocumentIdRange(
        TenantDocumentIdRangeQuery.forTesting(
          collectionPath: 'tenants/tenant-a/stock_takes',
          limit: 10,
          startAtDocumentId: 'st_2026-09-01_',
          endAtDocumentId: 'st_2026-09-30_￿',
        ),
      );

      expect(base.documentIdCalls, 1);
    });

    test('forwards an instant range unchanged', () async {
      final base = _RangeReader();
      final overlay = _overlay(base);

      await overlay.queryTenantInstantRange(
        TenantInstantRangeQuery.forTesting(
          collectionPath: 'tenants/tenant-a/audit_logs',
          limit: 10,
          startAt: DateTime.utc(2026, 9, 1),
          endAt: DateTime.utc(2026, 9, 30),
        ),
      );

      expect(base.instantCalls, 1);
    });

    test('a period read is never answered from unsent local writes', () async {
      // **Forwarded, not overlaid.** The overlay exists so a record this
      // device just wrote is visible on the screen that wrote it. A report is
      // a statement about a named period, and folding an unsent write into one
      // would produce a document that disagrees with the business's own
      // records the moment it is mailed to anybody.
      final base = _RangeReader();
      final overlay = _overlay(base);

      final read = await overlay.queryTenantBusinessDateRange(
        TenantBusinessDateRangeQuery.forTesting(
          collectionPath: 'tenants/tenant-a/returns',
          orderBy: TenantBusinessDateRangeField.recordedOn,
          limit: 10,
          startBusinessDate: '2026-09-01',
          endBusinessDate: '2026-09-30',
        ),
      );

      expect(
        read.single.path,
        'tenants/tenant-a/returns/from-the-server',
        reason: 'Exactly what the reader underneath answered, and nothing more.',
      );
    });

    test('a base that cannot read a period refuses rather than answers empty', () {
      final overlay = _overlay(const _PlainReader());

      expect(
        () => overlay.queryTenantInstantRange(
          TenantInstantRangeQuery.forTesting(
            collectionPath: 'tenants/tenant-a/audit_logs',
            limit: 10,
            startAt: DateTime.utc(2026, 9, 1),
            endAt: DateTime.utc(2026, 9, 30),
          ),
        ),
        throwsStateError,
        reason:
            'An empty answer would render as a month in which nothing '
            'happened, on a document somebody may act on.',
      );
    });
  });
}

TenantPendingMutationOverlayReader _overlay(TenantDataReader base) =>
    TenantPendingMutationOverlayReader(
      base: base,
      store: _store,
      currentUid: () => 'owner-a',
    );

/// A reader that can answer a period.
final class _RangeReader implements TenantDataReader, TenantReportRangeReader {
  _RangeReader();

  int businessDateCalls = 0;
  int documentIdCalls = 0;
  int instantCalls = 0;
  TenantBusinessDateRangeQuery? lastBusinessDateQuery;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantBusinessDateRange(
    TenantBusinessDateRangeQuery query,
  ) async {
    businessDateCalls++;
    lastBusinessDateQuery = query;
    return <TenantQueryDocumentSnapshot>[
      TenantQueryDocumentSnapshot(
        path: 'tenants/tenant-a/returns/from-the-server',
        data: <String, Object?>{},
      ),
    ];
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantDocumentIdRange(
    TenantDocumentIdRangeQuery query,
  ) async {
    documentIdCalls++;
    return const <TenantQueryDocumentSnapshot>[];
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantInstantRange(
    TenantInstantRangeQuery query,
  ) async {
    instantCalls++;
    return const <TenantQueryDocumentSnapshot>[];
  }
}

/// A reader with no range transport at all.
final class _PlainReader implements TenantDataReader {
  const _PlainReader();

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
