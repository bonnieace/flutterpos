import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('states each difference and what it is about', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('sale_a', _saleAnomaly()),
        _snapshot('shift_b', _shiftAnomaly()),
        _snapshot('stock_c', _stockAnomaly()),
      ]);

    await _pump(tester, _controller(), reader);

    expect(_text(tester, 'reconciliation-anomaly-kind-sale_a'),
        'Sale lines could not be read');
    expect(_text(tester, 'reconciliation-anomaly-subject-sale_a'),
        'Sale checkout-a');
    expect(
      _text(tester, 'reconciliation-anomaly-detail-sale_a'),
      '2 sale lines could not be read, so they moved no stock.',
    );
    expect(_text(tester, 'reconciliation-anomaly-subject-stock_c'),
        'Product product-a');
    expect(
      _text(tester, 'reconciliation-anomaly-detail-stock_c'),
      'Its ledger expects 10, and the product records 7: 3 fewer than the '
      'ledger accounts for.',
    );
    expect(_text(tester, 'reconciliation-anomaly-subject-shift_b'),
        'Shift shift-a');
    expect(
      _text(tester, 'reconciliation-anomaly-detail-shift_b'),
      'Its sales total is 12.5 short and its transaction count is 2 over '
      'against the sales recorded during it.',
    );
  });

  testWidgets('says the list is business-wide, not the day you came from', (
    tester,
  ) async {
    // A record belongs to a product, a shift, or a sale and carries no business
    // date, so narrowing it to a day would silently hide open differences.
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-anomalies-scope'),
      contains('covers the whole business'),
    );
    expect(reader.queries.single.equalityFilters, isEmpty);
  });

  testWidgets('narrowing to one kind restarts the list', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('sale_a', _saleAnomaly()),
        _snapshot('sale_b', _saleAnomaly()),
        _snapshot('stock_c', _stockAnomaly()),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2);
    await tester.tap(find.byKey(const ValueKey('reconciliation-anomalies-next')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('reconciliation-anomaly-stock_c')),
        findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('reconciliation-anomaly-kind-stock_variance')),
    );
    await _settle(tester);

    // A cursor is a position inside one exact query, so the narrowed list
    // starts again rather than resuming from a position it never established.
    expect(reader.queries.last.startAfterDocumentId, isNull);
    expect(reader.queries.last.equalityFilters, {
      'anomalyType': 'stock_variance',
    });
    expect(find.byKey(const ValueKey('reconciliation-anomaly-stock_c')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reconciliation-anomaly-sale_a')),
        findsNothing);
  });

  testWidgets('offers no chip for a kind it cannot ask for', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('reconciliation-anomaly-kind-all')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('reconciliation-anomaly-kind-stock_variance')),
      findsOneWidget,
    );
    // `other` names every unmodelled kind, so it identifies no stored value.
    expect(find.byKey(const ValueKey('reconciliation-anomaly-kind-')),
        findsNothing);
  });

  testWidgets('shows an unmodelled kind verbatim rather than hiding it', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('other_a', <String, Object?>{
          'tenantId': 'tenant-a',
          'anomalyType': 'price_drift',
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
        }),
      ]);

    await _pump(tester, _controller(), reader);

    expect(_text(tester, 'reconciliation-anomaly-kind-other_a'),
        'Unrecognised difference: price_drift');
    expect(_text(tester, 'reconciliation-anomaly-subject-other_a'),
        'This business');
  });

  testWidgets('states a difference with no recorded time as such', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot(
          'sale_a',
          _saleAnomaly(overrides: <String, Object?>{'createdAt': null}),
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-anomaly-instants-sale_a'),
      'No time was recorded for this difference.',
    );
  });

  testWidgets('says plainly when the business has none', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(
      _text(tester, 'reconciliation-anomalies-empty'),
      'The server has recorded no unresolved differences for this business.',
    );
  });

  testWidgets('a cashier is denied without any read', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(role: TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('reconciliation-anomalies-denied')),
        findsOneWidget);
    expect(reader.queries, isEmpty);
  });

  testWidgets('a business switch discards an outstanding page', (tester) async {
    final reader = _Reader()..defer();
    final controller = _controller();

    await _pump(tester, controller, reader, settle: false);
    await tester.pump();
    controller.open(uid: 'manager-a', membership: _membership('tenant-b'));
    reader.complete(<TenantQueryDocumentSnapshot>[
      _snapshot('sale_a', _saleAnomaly()),
    ]);
    await _settle(tester);

    // Tenant A's page must never label tenant B's screen.
    expect(find.byKey(const ValueKey('reconciliation-anomaly-sale_a')),
        findsNothing);
  });

  testWidgets('a record that contradicts itself fails the page closed', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot(
          'stock_c',
          _stockAnomaly(overrides: <String, Object?>{'variance': 99}),
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('reconciliation-anomalies-failure')),
        findsOneWidget);
    expect(find.textContaining('inconsistent_anomaly'), findsNothing);
  });
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump();
  }
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantReconciliationAnomalyPanel(
            reader: reader,
            pageSize: pageSize,
          ),
        ),
      ),
    ),
  );
  if (!settle) return;
  await _settle(tester);
}

TenantSessionController _controller({TenantRole role = TenantRole.manager}) =>
    TenantSessionController()
      ..open(uid: 'manager-a', membership: _membership('tenant-a', role: role));

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.manager,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: 'Business $tenantId',
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

Map<String, Object?> _saleAnomaly({Map<String, Object?>? overrides}) =>
    _document(<String, Object?>{
      'tenantId': 'tenant-a',
      'sourceType': 'sale',
      'sourceId': 'checkout-a',
      'anomalyType': 'invalid_sale_lines',
      'invalidLineCount': 2,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
    }, overrides);

Map<String, Object?> _stockAnomaly({Map<String, Object?>? overrides}) =>
    _document(<String, Object?>{
      'tenantId': 'tenant-a',
      'productId': 'product-a',
      'jobId': 'rj_abc',
      'anomalyType': 'stock_variance',
      'expectedQuantity': 10,
      'observedQuantity': 7,
      'variance': -3,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
    }, overrides);

Map<String, Object?> _shiftAnomaly({Map<String, Object?>? overrides}) =>
    _document(<String, Object?>{
      'tenantId': 'tenant-a',
      'shiftId': 'shift-a',
      'jobId': 'rj_abc',
      'anomalyType': 'shift_variance',
      'salesVariance': -12.5,
      'transactionVariance': 2,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
    }, overrides);

Map<String, Object?> _document(
  Map<String, Object?> base,
  Map<String, Object?>? overrides,
) {
  final data = Map<String, Object?>.of(base);
  if (overrides != null) data.addAll(overrides);
  data.removeWhere((key, value) => value == null);
  return data;
}

TenantQueryDocumentSnapshot _snapshot(String id, Map<String, Object?> data) =>
    TenantQueryDocumentSnapshot(
      path: 'tenants/tenant-a/reconciliation_anomalies/$id',
      data: data,
    );

final class _Reader implements TenantDataReader {
  List<TenantQueryDocumentSnapshot> _page = const <TenantQueryDocumentSnapshot>[];
  Completer<List<TenantQueryDocumentSnapshot>>? _pending;
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  void respond(List<TenantQueryDocumentSnapshot> page) => _page = page;

  /// Holds the next page open so a business switch can happen mid-read.
  void defer() =>
      _pending = Completer<List<TenantQueryDocumentSnapshot>>();

  void complete(List<TenantQueryDocumentSnapshot> page) {
    _page = page;
    _pending?.complete(page);
    _pending = null;
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    final pending = _pending;
    if (pending != null) await pending.future;
    final cursor = query.startAfterDocumentId;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final snapshot in _page) {
      final id = snapshot.path.split('/').last;
      if (cursor != null && id.compareTo(cursor) <= 0) continue;
      // A fake that ignored the repository's own filter would make a narrowed
      // page prove nothing, so the filter contract is modelled here too.
      final matchesFilters = query.equalityFilters.entries.every(
        (filter) => snapshot.data[filter.key] == filter.value,
      );
      if (!matchesFilters) continue;
      matches.add(snapshot);
      if (matches.length >= query.limit) break;
    }
    return matches;
  }
}
