import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uzapay_pos/audit/audit.dart';
import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// A display name is the one part of a history row that was never
/// authoritative, and every one of these surfaces resolved it through the live
/// reader on **both** passes. The records came off this disk and then the page
/// waited for a network to label them.
void main() {
  group('a resolver per pass', () {
    test('each reader answers through itself', () {
      final session = TenantSession.active(
        uid: 'admin-a',
        tenantId: 'tenant-a',
        role: TenantRole.admin,
      );
      final live = _NamesReader();
      final cache = _NamesReader();
      final resolvers = TenantStaffNameResolvers();

      final forLive = resolvers.of(session: session, reader: live);
      final forCache = resolvers.of(session: session, reader: cache);

      expect(identical(forLive, forCache), isFalse);
      expect(forLive.reader, same(live));
      expect(forCache.reader, same(cache));
    });

    test('one reader keeps one resolver, so its names stay resolved', () {
      final session = TenantSession.active(
        uid: 'admin-a',
        tenantId: 'tenant-a',
        role: TenantRole.admin,
      );
      final reader = _NamesReader();
      final resolvers = TenantStaffNameResolvers();

      expect(
        resolvers.of(session: session, reader: reader),
        same(resolvers.of(session: session, reader: reader)),
      );
    });

    test('a new session drops every resolver the last one held', () {
      final reader = _NamesReader();
      final resolvers = TenantStaffNameResolvers();
      final first = resolvers.of(
        session: TenantSession.active(
          uid: 'admin-a',
          tenantId: 'tenant-a',
          role: TenantRole.admin,
        ),
        reader: reader,
      );
      final second = resolvers.of(
        session: TenantSession.active(
          uid: 'admin-b',
          tenantId: 'tenant-a',
          role: TenantRole.admin,
        ),
        reader: reader,
      );

      expect(identical(first, second), isFalse);
    });
  });

  testWidgets('a cached page is labelled without reaching for the network', (
    tester,
  ) async {
    // The live reader answers nothing, ever - one bar of signal, or none.
    final reader = _StallingReader(
      cache: _CacheReader(
        page: <TenantQueryDocumentSnapshot>[_staffEvent()],
        staffNames: <String, String>{'cashier-a': 'Amina'},
      ),
    );

    await _pumpAuditLog(tester, reader);

    // The row is drawn from this device, named, while the live pass is still
    // outstanding. Before the fix the cached pass resolved `cashier-a` through
    // the live reader and hung with it, so nothing below was on screen.
    expect(
      find.byKey(const ValueKey('audit-log-event-aud_001')),
      findsOneWidget,
    );
    // At 1400 the log is a table (2026-10-13): the name in the cell, the UID it
    // is recorded under on the line beneath it.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('audit-log-target-aud_001')))
          .data,
      'Amina',
    );
    expect(find.text('cashier-a'), findsOneWidget);
    // **Not one document read was attempted on the live reader.** This is the
    // assertion that fails without the fix: the label is not worth a network
    // round trip in front of records already held.
    expect(reader.documentPaths, isEmpty);
  });

  testWidgets('a name this device does not hold degrades to the UID', (
    tester,
  ) async {
    final reader = _StallingReader(
      cache: _CacheReader(
        page: <TenantQueryDocumentSnapshot>[_staffEvent()],
        staffNames: const <String, String>{},
      ),
    );

    await _pumpAuditLog(tester, reader);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('audit-log-target-aud_001')))
          .data,
      'cashier-a',
    );
    expect(reader.documentPaths, isEmpty);
  });

  testWidgets('a count opened from a cached list reads its lines from cache', (
    tester,
  ) async {
    // #122: the list had a cached pass and the detail behind it did not, so a
    // count you could see offline opened onto a page that waited for a network.
    tester.view.physicalSize = const Size(1400, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final reader = _StallingStockReader();
    await tester.pumpWidget(
      MaterialApp(
        home: TenantSessionScope(
          controller: TenantSessionController()
            ..open(uid: 'staff-owner', membership: _membership()),
          child: TenantStockTakeReviewScreen(reader: reader),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The card itself opens the count - there is no separate `Open` button on
    // it any more, so this taps the record rather than an action inside it.
    expect(find.byKey(ValueKey('stock-take-$_takeId')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('stock-take-$_takeId')));
    await tester.pumpAndSettle();

    // The differing line is on screen, named, with the live reader still
    // holding every request it was given.
    expect(
      find.byKey(const ValueKey('stock-take-line-product-a')),
      findsOneWidget,
    );
    expect(find.textContaining('Sugar'), findsWidgets);
  });
}

Future<void> _pumpAuditLog(WidgetTester tester, TenantDataReader reader) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: TenantSessionController()
          ..open(uid: 'admin-a', membership: _membership()),
        child: Scaffold(
          body: TenantAuditLogPanel(
            reader: reader,
            // The trail opens on today, and every fixture here is dated: the
            // clock is pinned to the day they carry so the page draws them.
            clock: () => DateTime.utc(2026, 8, 1, 12),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// A reader that never answers, paired with a device copy that does.
final class _StallingReader implements TenantDataReader, TenantCacheReadable {
  _StallingReader({required this.cache});

  final _CacheReader cache;

  /// Every live path this reader was asked for. The fix is that it stays empty
  /// for as long as the cached pass is the one drawing.
  final List<String> documentPaths = <String>[];

  @override
  TenantDataReader get cacheOnly => cache;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) {
    documentPaths.add(path);
    return Completer<TenantDocumentSnapshot?>().future;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) => Completer<List<TenantQueryDocumentSnapshot>>().future;
}

/// What this device already holds: the page, and the names for it.
final class _CacheReader implements TenantDataReader {
  _CacheReader({required this.page, required this.staffNames});

  final List<TenantQueryDocumentSnapshot> page;
  final Map<String, String> staffNames;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final uid = path.split('/').last;
    final name = staffNames[uid];
    return name == null
        ? null
        : TenantDocumentSnapshot(
            path: path,
            data: <String, Object?>{'uid': uid, 'name': name},
          );
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => page.take(query.limit).toList(growable: false);
}

/// A reader that answers no name at all; the resolvers are what is under test.
final class _NamesReader implements TenantDataReader {
  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}

TenantQueryDocumentSnapshot _staffEvent() => TenantQueryDocumentSnapshot(
  path: 'tenants/tenant-a/audit_logs/aud_001',
  data: <String, Object?>{
    'tenantId': 'tenant-a',
    'eventType': 'staff_invited',
    'actorUid': 'admin-a',
    'targetUid': 'cashier-a',
    'requestId': 'invite-staff-abcdefgh',
    'role': 'cashier',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 9)),
  },
);

TenantMembership _membership() => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: 'Tenant A',
  tenantSlug: 'tenant-a',
  role: TenantRole.admin,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalMembershipExists: true,
  canonicalTenantExists: true,
);

const String _takeId = 'st_2026-09-10_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// A live reader that never answers, over a device copy holding one count,
/// its differing line, the counter and the product that line names.
final class _StallingStockReader
    implements TenantDataReader, TenantCacheReadable {
  final List<String> documentPaths = <String>[];

  @override
  TenantDataReader get cacheOnly => const _StockCacheReader();

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) {
    documentPaths.add(path);
    return Completer<TenantDocumentSnapshot?>().future;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) => Completer<List<TenantQueryDocumentSnapshot>>().future;
}

final class _StockCacheReader implements TenantDataReader {
  const _StockCacheReader();

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final documents = <String, Map<String, Object?>>{
      'tenants/tenant-a/staff/staff-owner': <String, Object?>{
        'uid': 'staff-owner',
        'name': 'Bonnie',
      },
      'tenants/tenant-a/products/product-a': <String, Object?>{
        'name': 'Sugar 1kg',
      },
    };
    final data = documents[path];
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    if (query.collectionPath.endsWith('/lines')) {
      return <TenantQueryDocumentSnapshot>[
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/product-a',
          data: <String, Object?>{
            'counted': 8,
            'expected': 10,
            'variance': -2,
            'seenQuantity': 10,
            'matched': true,
            'needsApply': true,
          },
        ),
      ];
    }
    return <TenantQueryDocumentSnapshot>[
      TenantQueryDocumentSnapshot(
        path: 'tenants/tenant-a/stock_takes/$_takeId',
        data: <String, Object?>{
          'tenantId': 'tenant-a',
          'counterUid': 'staff-owner',
          'businessDate': '2026-09-10',
          'status': 'submitted',
          'productsInScope': 3,
          'countedLineCount': 2,
          'varianceLineCount': 1,
          'absoluteVarianceUnits': 2,
          'unmatchedLineCount': 0,
        },
      ),
    ];
  }
}
