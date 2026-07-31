import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout_receipt.dart';
import 'package:flutter_application_1/sales/sales.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';
const String _payloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  testWidgets('a shift page shows the recorded figures and its sales', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-2', sequence: 2),
        _snapshot('co-1'),
      ]);

    await _pump(tester, _controller(), reader, _shiftRequest());

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('sale-history-recorded'))).data,
      'Recorded: 18.00 over 2 transactions. Counted cash was 20.00.',
    );
    expect(find.byKey(const ValueKey('sale-history-entry-co-2')), findsOne);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('sale-history-total-co-1'))).data,
      'Total: KES 9.00 after 1.00 discount',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('sale-history-lines-co-1'))).data,
      '1 item: 2 x Tusker',
    );
    // The screen states the recorded figures; it computes no replacement.
    expect(find.textContaining('Actual total'), findsNothing);
  });

  testWidgets('a shift closed without a summary says so on its sales page', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[]);

    await _pump(
      tester,
      _controller(),
      reader,
      TenantShiftSaleHistoryRequest(
        shift: _scope(),
        recordedTransactionCount: null,
        recordedTotalSalesMinor: null,
        countedCashMinor: 2000,
      ),
    );

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('sale-history-recorded'))).data,
      'This shift closed without a recorded summary. Counted cash was 20.00.',
    );
    expect(find.byKey(const ValueKey('sale-history-empty')), findsOne);
  });

  testWidgets('a sale that contradicts its shift hides the whole page', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-1', overrides: <String, Object?>{'soldById': 'user-b'}),
      ]);

    await _pump(tester, _controller(), reader, _shiftRequest());

    expect(find.byKey(const ValueKey('sale-history-failure')), findsOne);
    expect(find.byKey(const ValueKey('sale-history-entry-co-1')), findsNothing);
  });

  testWidgets('own recent sales page forward and back', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-3', sequence: 3),
        _snapshot('co-2', sequence: 2),
        _snapshot('co-1'),
      ]);

    await _pump(
      tester,
      _controller(),
      reader,
      const TenantOwnSaleHistoryRequest(),
      pageSize: 2,
    );
    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'soldById': 'user-a',
    });
    expect(find.byKey(const ValueKey('sale-history-entry-co-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sale-history-next')));
    await tester.pump();
    await tester.pump();
    expect(reader.queries.last.startAfterDocumentId, 'co-2');
    expect(find.byKey(const ValueKey('sale-history-entry-co-1')), findsOne);

    await tester.tap(find.byKey(const ValueKey('sale-history-previous')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('sale-history-entry-co-3')), findsOne);
  });

  testWidgets('a tenant switch discards the outstanding sale page', (
    tester,
  ) async {
    final controller = _controller();
    final reader = _Reader(deferred: true)
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-1'),
      ])
      ..respond('tenants/tenant-b/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-9', tenantId: 'tenant-b'),
      ]);

    await _pump(
      tester,
      controller,
      reader,
      const TenantOwnSaleHistoryRequest(),
      settle: false,
    );
    await tester.pump();
    expect(reader.pending.length, 1);

    controller.open(uid: 'user-a', membership: _membership('tenant-b'));
    await tester.pump();
    reader.completeFirst();
    await tester.pump();
    expect(find.byKey(const ValueKey('sale-history-entry-co-1')), findsNothing);

    reader.completeFirst();
    await tester.pump();
    expect(find.byKey(const ValueKey('sale-history-entry-co-9')), findsOne);
    expect(find.byKey(const ValueKey('sale-history-entry-co-1')), findsNothing);
  });

  testWidgets('a colleague shift page names its cashier beside the UID', (
    tester,
  ) async {
    final reader = _Reader(staffNames: <String, String>{'user-b': 'Brian'})
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _colleagueSale('co-2', sequence: 2),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.manager),
      reader,
      _colleagueShiftRequest(),
    );

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-history-recorded-at-co-2')),
          )
          .data,
      'Recorded 2026-07-31 12:00 UTC by Brian (user-b)',
    );
  });

  testWidgets('a cashier own page labels itself', (tester) async {
    final reader = _Reader()
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _snapshot('co-1'),
      ]);

    await _pump(
      tester,
      _controller(),
      reader,
      const TenantOwnSaleHistoryRequest(),
    );

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-history-recorded-at-co-1')),
          )
          .data,
      'Recorded 2026-07-31 12:00 UTC by You',
    );
  });

  testWidgets('an unreadable staff record leaves the cashier UID in place', (
    tester,
  ) async {
    final reader = _Reader(deniedStaff: true)
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _colleagueSale('co-2', sequence: 2),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.manager),
      reader,
      _colleagueShiftRequest(),
    );

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('sale-history-recorded-at-co-2')),
          )
          .data,
      'Recorded 2026-07-31 12:00 UTC by user-b',
    );
    expect(find.byKey(const ValueKey('sale-history-failure')), findsNothing);
  });

  testWidgets('each scope names itself on its own route', (tester) async {
    final controller = _controller();
    final reader = _Reader()
      ..respond('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[]);

    for (final request in <TenantSaleHistoryRequest>[
      _shiftRequest(),
      const TenantOwnSaleHistoryRequest(),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: TenantSessionScope(
            controller: controller,
            child: TenantSaleHistoryScreen(reader: reader, request: request),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(request.title), findsOne);
    }
  });

  testWidgets('no session renders the denied state and starts no load', (
    tester,
  ) async {
    final reader = _Reader();

    await _pump(
      tester,
      TenantSessionController(),
      reader,
      const TenantOwnSaleHistoryRequest(),
    );

    expect(find.byKey(const ValueKey('sale-history-denied')), findsOne);
    expect(reader.queries, isEmpty);
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader,
  TenantSaleHistoryRequest request, {
  int pageSize = 20,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantSaleHistoryPanel(
            reader: reader,
            request: request,
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

TenantShiftSaleHistoryRequest _shiftRequest() => TenantShiftSaleHistoryRequest(
  shift: _scope(),
  recordedTransactionCount: 2,
  recordedTotalSalesMinor: 1800,
  countedCashMinor: 2000,
);

TenantSaleShiftScope _scope() => const TenantSaleShiftScope(
  shiftId: 'shift-a',
  staffId: 'user-a',
  deviceId: _deviceA,
  businessDate: _businessDate,
);

/// A manager inspecting the shift of another cashier: the only page on which
/// a colleague's identity is shown.
TenantShiftSaleHistoryRequest _colleagueShiftRequest() =>
    TenantShiftSaleHistoryRequest(
      shift: const TenantSaleShiftScope(
        shiftId: 'shift-a',
        staffId: 'user-b',
        deviceId: _deviceA,
        businessDate: _businessDate,
      ),
      recordedTransactionCount: 1,
      recordedTotalSalesMinor: 900,
      countedCashMinor: 900,
    );

TenantQueryDocumentSnapshot _colleagueSale(String saleId, {int sequence = 1}) =>
    _snapshot(
      saleId,
      sequence: sequence,
      overrides: <String, Object?>{'soldById': 'user-b'},
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
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 31),
  updatedAt: DateTime.utc(2026, 7, 31),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

TenantQueryDocumentSnapshot _snapshot(
  String saleId, {
  int sequence = 1,
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'checkoutId': saleId,
    'tenantId': tenantId,
    'soldById': 'user-a',
    'payloadHash': _payloadHash,
    'payloadSchemaVersion': 1,
    'currency': 'KES',
    'businessDate': _businessDate,
    'clientCreatedAtMs': 1785484800000,
    'shiftId': 'shift-a',
    'deviceId': _deviceA,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: _deviceA,
      businessDate: _businessDate,
      sequence: sequence,
    ),
    'receiptSequence': sequence,
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-1',
        'name': 'Tusker',
        'quantity': 2,
        'unitPriceMinor': 500,
        'lineTotalMinor': 1000,
      },
    ],
    'subtotalMinor': 1000,
    'subtotal': 10.0,
    'discountMinor': 100,
    'discount': 1.0,
    'totalMinor': 900,
    'total': 9.0,
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 12)),
  };
  if (overrides != null) data.addAll(overrides);
  return TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/sales/$saleId',
    data: data,
  );
}

final class _Reader implements TenantDataReader {
  _Reader({
    this.deferred = false,
    this.deniedStaff = false,
    this.staffNames = const <String, String>{},
  });

  final bool deferred;

  /// Stands in for the narrowed canonical staff read: a role the rule refuses
  /// gets no name and must still see the sales.
  final bool deniedStaff;
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
      final matchesFilters = query.equalityFilters.entries.every(
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
