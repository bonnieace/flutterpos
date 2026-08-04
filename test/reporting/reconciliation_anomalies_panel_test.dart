import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

  testWidgets('offers a correction only on a shift difference', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('sale_a', _saleAnomaly()),
        _snapshot('shift_b', _shiftAnomaly()),
        _snapshot('shift_c', _invalidShiftAnomaly()),
        _snapshot('stock_c', _stockAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: _Callable(_response()),
    );

    // A shift whose totals disagree with its sales is the one difference the
    // server can resolve. A stock figure is corrected from the product, and the
    // records of unreadable data are not a figure that can be put right at all.
    expect(_amendButton('shift_b'), findsOneWidget);
    expect(_amendButton('shift_c'), findsNothing);
    expect(_amendButton('stock_c'), findsNothing);
    expect(_amendButton('sale_a'), findsNothing);
    expect(
      _text(tester, 'reconciliation-anomalies-writes'),
      contains('counted cash is never changed'),
    );
  });

  testWidgets('a build without the capability stays read-only', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(tester, _controller(role: TenantRole.owner), reader);

    // Whatever the composition root did not inject stays unavailable, so the
    // list is exactly the read-only explanation it was before.
    expect(_amendButton('shift_b'), findsNothing);
    expect(
      find.byKey(const ValueKey('reconciliation-amend-forbidden')),
      findsNothing,
    );
    expect(
      _text(tester, 'reconciliation-anomalies-writes'),
      contains('nothing on this page can'),
    );
  });

  testWidgets('a manager is told why rather than shown nothing', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(),
      reader,
      callable: _Callable(_response()),
    );

    // The server's roles are narrower than the roles that read this list, so a
    // manager is told about the one thing they cannot do.
    expect(_amendButton('shift_b'), findsNothing);
    expect(
      _text(tester, 'reconciliation-amend-forbidden'),
      contains('owners and administrators'),
    );
  });

  testWidgets('the explanation is absent when nothing on screen applies', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('stock_c', _stockAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(),
      reader,
      callable: _Callable(_response()),
    );

    expect(
      find.byKey(const ValueKey('reconciliation-amend-forbidden')),
      findsNothing,
    );
  });

  testWidgets('correcting a shift sends the reason and re-reads the list', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);
    // The server deletes a resolved difference, so the second read is the proof
    // that it is gone rather than a locally edited list.
    final callable = _Callable(
      _response(),
      onCall: () => reader.respond(<TenantQueryDocumentSnapshot>[]),
    );

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: callable,
    );
    await _amend(tester, 'shift_b', 'Late  offline\tsale');

    expect(callable.payloads.single, <String, Object?>{
      'tenantId': 'tenant-a',
      'shiftId': 'shift-a',
      'reason': 'Late offline sale',
      'requestId': 'amend-shift-abcdefgh',
    });
    expect(
      _text(tester, 'reconciliation-amend-notice'),
      'Shift shift-a on 2026-07-31 now records 1350.25 instead of 1200.50, '
      'over 10 transactions rather than 9. The counted cash was not changed. '
      'Recorded as sm_abc.',
    );
    expect(reader.queries.length, 2);
    expect(reader.queries.last.startAfterDocumentId, isNull);
    expect(find.byKey(const ValueKey('reconciliation-anomaly-shift_b')),
        findsNothing);
  });

  testWidgets('a refusal names itself and leaves the list alone', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: _Callable.failing(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'refused',
        ),
      ),
    );
    await _amend(tester, 'shift_b', 'Late offline sale');

    // The shift is exactly as it was, so the difference stays listed and the
    // page is not re-read to prove something that did not happen.
    expect(
      _text(tester, 'reconciliation-amend-notice'),
      contains('this shift cannot be corrected'),
    );
    expect(reader.queries.length, 1);
    expect(find.byKey(const ValueKey('reconciliation-anomaly-shift_b')),
        findsOneWidget);
  });

  testWidgets('an unknown outcome re-reads the list and says so', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: _Callable.failing(
        FirebaseFunctionsException(code: 'unavailable', message: 'down'),
      ),
    );
    await _amend(tester, 'shift_b', 'Late offline sale');

    // The shift may or may not have been corrected, and only the server's own
    // record can settle it.
    expect(
      _text(tester, 'reconciliation-amend-notice'),
      contains('The result is unknown'),
    );
    expect(reader.queries.length, 2);
  });

  testWidgets('an untrustworthy answer is refused rather than shown', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      // A response naming another business must never label this one's screen.
      callable: _Callable(_response(overrides: {'tenantId': 'tenant-b'})),
    );
    await _amend(tester, 'shift_b', 'Late offline sale');

    expect(
      _text(tester, 'reconciliation-amend-notice'),
      contains('could not be trusted'),
    );
    expect(find.textContaining('tenant-b'), findsNothing);
  });

  testWidgets('cancelling the dialog sends nothing', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);
    final callable = _Callable(_response());

    await _pump(
      tester,
      _controller(role: TenantRole.owner),
      reader,
      callable: callable,
    );
    await tester.tap(_amendButton('shift_b'));
    await tester.pumpAndSettle();
    expect(
      _text(tester, 'reconciliation-amend-explanation'),
      contains('cannot choose the figure'),
    );
    await tester.tap(find.byKey(const ValueKey('reconciliation-amend-cancel')));
    await tester.pumpAndSettle();

    expect(callable.payloads, isEmpty);
    expect(
      find.byKey(const ValueKey('reconciliation-amend-notice')),
      findsNothing,
    );
  });

  testWidgets('a business switch discards an outstanding correction', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _snapshot('shift_b', _shiftAnomaly()),
      ]);
    final callable = _Callable.deferred();
    final controller = _controller(role: TenantRole.owner);

    await _pump(tester, controller, reader, callable: callable);
    await tester.tap(_amendButton('shift_b'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reconciliation-amend-reason')),
      'Late offline sale',
    );
    await tester.tap(find.byKey(const ValueKey('reconciliation-amend-confirm')));
    await tester.pumpAndSettle();
    // Proved before the switch, so a missing notice below cannot be a
    // correction that was never sent at all.
    expect(callable.payloads, hasLength(1));
    controller.open(uid: 'owner-a', membership: _membership('tenant-b'));
    callable.complete(_response());
    await _settle(tester);

    // Tenant A's correction must never report itself on tenant B's screen.
    expect(
      find.byKey(const ValueKey('reconciliation-amend-notice')),
      findsNothing,
    );
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

Finder _amendButton(String anomalyId) =>
    find.byKey(ValueKey('reconciliation-anomaly-amend-$anomalyId'));

/// Opens the correction dialog for one row, states a reason, and confirms.
Future<void> _amend(
  WidgetTester tester,
  String anomalyId,
  String reason,
) async {
  await tester.tap(_amendButton(anomalyId));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('reconciliation-amend-reason')),
    reason,
  );
  await tester.tap(find.byKey(const ValueKey('reconciliation-amend-confirm')));
  await tester.pumpAndSettle();
}

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
  _Callable? callable,
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
            // Whatever is absent stays unavailable, which is how a build with no
            // correction capability keeps the list read-only.
            actions: callable == null
                ? null
                : TenantReconciliationActions(
                    amendShiftSummaryCallable: callable,
                  ),
            requestIdFactory: () => 'amend-shift-abcdefgh',
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

/// The one difference the server can resolve, and the one it cannot: with no
/// readable totals there was nothing to compare, so there is no figure the
/// sales prove the shift should hold.
Map<String, Object?> _invalidShiftAnomaly() => _document(<String, Object?>{
  'tenantId': 'tenant-a',
  'shiftId': 'shift-b',
  'jobId': 'rj_abc',
  'anomalyType': 'invalid_or_missing_shift',
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 2, 30)),
}, null);

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

Map<String, Object?> _response({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'amendmentId': 'sm_abc',
    'tenantId': 'tenant-a',
    'shiftId': 'shift-a',
    'businessDate': '2026-07-31',
    'previousTotalSalesMinor': 120050,
    'previousTransactionCount': 9,
    'totalSalesMinor': 135025,
    'transactionCount': 10,
    'salesVarianceMinor': -14975,
    'transactionVariance': -1,
    'clearedAnomalyId': 'shift_abc',
  };
  if (overrides != null) data.addAll(overrides);
  return data;
}

final class _Callable implements AmendShiftSummaryCallable {
  _Callable(this._response, {this.onCall}) : _error = null;
  _Callable.failing(Object error)
    : _response = null,
      _error = error,
      onCall = null;

  /// Holds the call open so a business switch can happen mid-correction.
  _Callable.deferred()
    : _response = null,
      _error = null,
      onCall = null,
      _pending = Completer<Object?>();

  final Object? _response;
  final Object? _error;

  /// Runs when the call is made, so a test can arrange the server state the
  /// reload will then read.
  final void Function()? onCall;

  Completer<Object?>? _pending;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  void complete(Object? response) {
    _pending?.complete(response);
    _pending = null;
  }

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    onCall?.call();
    final pending = _pending;
    if (pending != null) return pending.future;
    final error = _error;
    if (error != null) throw error;
    return _response;
  }
}

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
