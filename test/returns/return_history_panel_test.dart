import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/returns/returns.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('verified and pending returns are shown distinctly', (
    tester,
  ) async {
    final reader = _Reader(staffNames: <String, String>{'manager-a': 'Amina'})
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _verified('ret-2'),
        _pending('ret-1'),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sale-returns-counts')))
          .data,
      'On this page: 1 verified, 1 pending.',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sale-returns-status-ret-2')))
          .data,
      'Verified - stock restored',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sale-returns-status-ret-1')))
          .data,
      'Pending verification',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-verified-ret-2')),
          )
          .data,
      'Verified 2026-08-01 06:00 UTC by Amina (manager-a)',
    );
    // A pending return has restored nothing, so it names no verifier.
    expect(
      find.byKey(const ValueKey('sale-returns-verified-ret-1')),
      findsNothing,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sale-returns-lines-ret-1')))
          .data,
      '3 units across 2 products: 2 x Tusker, 1 x product-2',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-recorded-ret-1')),
          )
          .data,
      'Recorded 2026-07-31 12:00 UTC by You',
    );
  });

  testWidgets('a sale with no returns says so', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('sale-returns-empty')), findsOne);
    expect(find.byKey(const ValueKey('sale-returns-counts')), findsNothing);
    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'saleId': 'co-1',
    });
    expect(reader.queries.single.descending, isTrue);
  });

  testWidgets('a return that names another sale hides the whole page', (
    tester,
  ) async {
    final reader = _Reader(ignoreFilters: true)
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1', overrides: <String, Object?>{'saleId': 'co-9'}),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('sale-returns-failure')), findsOne);
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-1')), findsNothing);
  });

  testWidgets('a return whose state contradicts itself hides the page', (
    tester,
  ) async {
    // The verification callable would refuse this document; offering it as
    // pending would invite an action that can never succeed.
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1', overrides: <String, Object?>{'stockRestored': true}),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('sale-returns-failure')), findsOne);
  });

  testWidgets('returns page forward and back', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-3'),
        _pending('ret-2'),
        _pending('ret-1'),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2);
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sale-returns-next')));
    await tester.pump();
    await tester.pump();
    expect(reader.queries.last.startAfterDocumentId, 'ret-2');
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-1')), findsOne);

    await tester.tap(find.byKey(const ValueKey('sale-returns-previous')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-3')), findsOne);
  });

  testWidgets('a tenant switch discards the outstanding returns page', (
    tester,
  ) async {
    final controller = _controller();
    final reader = _Reader(deferred: true)
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-1'),
      ])
      ..respond('tenants/tenant-b/returns', <TenantQueryDocumentSnapshot>[
        _pending('ret-9', tenantId: 'tenant-b'),
      ]);

    await _pump(tester, controller, reader, settle: false);
    await tester.pump();
    expect(reader.pending.length, 1);

    controller.open(uid: 'user-a', membership: _membership('tenant-b'));
    await tester.pump();
    reader.completeFirst();
    await tester.pump();
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-1')), findsNothing);

    reader.completeFirst();
    await tester.pump();
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-9')), findsOne);
    expect(find.byKey(const ValueKey('sale-returns-entry-ret-1')), findsNothing);
  });

  testWidgets('an unreadable staff record leaves the UID in place', (
    tester,
  ) async {
    final reader = _Reader(deniedStaff: true)
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[
        _verified('ret-2'),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-returns-verified-ret-2')),
          )
          .data,
      'Verified 2026-08-01 06:00 UTC by manager-a',
    );
    expect(find.byKey(const ValueKey('sale-returns-failure')), findsNothing);
  });

  testWidgets('no session renders the denied state and starts no load', (
    tester,
  ) async {
    final reader = _Reader();

    await _pump(tester, TenantSessionController(), reader);

    expect(find.byKey(const ValueKey('sale-returns-denied')), findsOne);
    expect(reader.queries, isEmpty);
  });

  testWidgets('the route names the receipt it is reversing', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/returns', <TenantQueryDocumentSnapshot>[]);

    await tester.pumpWidget(
      MaterialApp(
        home: TenantSessionScope(
          controller: _controller(),
          child: TenantSaleReturnsScreen(reader: reader, request: _request()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Returns'), findsOne);
    expect(find.text('Returns against CT-A7F-20260731-0001'), findsOne);
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantSaleReturnsPanel(
            reader: reader,
            request: _request(),
            pageSize: pageSize,
          ),
        ),
      ),
    ),
  );
  if (!settle) return;
  await tester.pump();
  await tester.pump();
}

TenantSaleReturnsRequest _request() => const TenantSaleReturnsRequest(
  saleId: 'co-1',
  receiptNumber: 'CT-A7F-20260731-0001',
);

TenantSessionController _controller({TenantRole role = TenantRole.cashier}) =>
    TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a', role: role));

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.cashier,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 31),
  updatedAt: DateTime.utc(2026, 7, 31),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

TenantQueryDocumentSnapshot _pending(
  String returnId, {
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'tenantId': tenantId,
    'saleId': 'co-1',
    'createdBy': 'user-a',
    'status': 'pending',
    'itemsReturned': <Object?>[
      <String, Object?>{
        'productId': 'product-1',
        'productName': 'Tusker',
        'quantity': 2,
      },
      <String, Object?>{'productId': 'product-2', 'quantity': 1},
    ],
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
  };
  if (overrides != null) data.addAll(overrides);
  return TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/returns/$returnId',
    data: data,
  );
}

TenantQueryDocumentSnapshot _verified(String returnId) {
  final base = _pending(returnId);
  return TenantQueryDocumentSnapshot(
    path: base.path,
    data: <String, Object?>{
      ...base.data,
      'status': 'verified',
      'verified': true,
      'verifiedBy': 'manager-a',
      'verifiedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 6)),
      'stockRestored': true,
      'stockRestoredAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 6)),
      'stockRestorationId': 'rv_abc',
    },
  );
}

final class _Reader implements TenantDataReader {
  _Reader({
    this.deferred = false,
    this.deniedStaff = false,
    this.ignoreFilters = false,
    this.staffNames = const <String, String>{},
  });

  final bool deferred;

  /// Stands in for a staff record this role may not read: the row must still
  /// render, labelled by the authoritative UID.
  final bool deniedStaff;
  final bool ignoreFilters;
  final Map<String, String> staffNames;
  final Map<String, List<TenantQueryDocumentSnapshot>> _pages =
      <String, List<TenantQueryDocumentSnapshot>>{};
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<Completer<List<TenantQueryDocumentSnapshot>>> pending =
      <Completer<List<TenantQueryDocumentSnapshot>>>[];
  final List<List<TenantQueryDocumentSnapshot>> _deferredResults =
      <List<TenantQueryDocumentSnapshot>>[];

  void respond(String path, List<TenantQueryDocumentSnapshot> page) =>
      _pages[path] = page;

  void completeFirst() {
    if (pending.isEmpty) return;
    pending.removeAt(0).complete(_deferredResults.removeAt(0));
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (deniedStaff) throw StateError('permission-denied');
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
  ) {
    queries.add(query);
    final all = _pages[query.collectionPath] ?? const [];
    final cursor = query.startAfterDocumentId;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final snapshot in all) {
      final id = snapshot.path.split('/').last;
      if (cursor != null && id.compareTo(cursor) >= 0) continue;
      final matchesFilters =
          ignoreFilters ||
          query.equalityFilters.entries.every(
            (filter) => snapshot.data[filter.key] == filter.value,
          );
      if (!matchesFilters) continue;
      matches.add(snapshot);
      if (matches.length >= query.limit) break;
    }
    if (!deferred) return Future.value(matches);
    final completer = Completer<List<TenantQueryDocumentSnapshot>>();
    pending.add(completer);
    _deferredResults.add(matches);
    return completer.future;
  }
}
