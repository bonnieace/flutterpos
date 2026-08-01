import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the recorded quantity and the ledger are stated as read', (
    tester,
  ) async {
    final reader = _Reader(staffNames: <String, String>{'manager-a': 'Amina'})
      ..respondMovements(<TenantQueryDocumentSnapshot>[
        _adjustment('sa_abc'),
        _sale('sale_chk-1'),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('product-stock-quantity')))
          .data,
      'Recorded stock: 7',
    );
    // A sale is never blocked by a stock count, so the surface says so instead
    // of presenting a negative quantity as an error.
    expect(find.textContaining('may legitimately be negative'), findsOne);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-stock-delta-sa_abc')),
          )
          .data,
      '-3 • Adjustment: damage',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-stock-figures-sa_abc')),
          )
          .data,
      '10 to 7',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-stock-recorded-sa_abc')),
          )
          .data,
      // The adjustment was recorded by the signed-in manager, so the row says
      // so rather than repeating their own UID back at them.
      'Recorded 2026-08-01 09:00 UTC by You (Amina)',
    );
    // A reconciled sale carries no before/after pair, which is named rather
    // than filled in with a locally derived figure.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-stock-figures-sale_chk-1')),
          )
          .data,
      'The recorded before and after quantities are not part of this entry.',
    );
  });

  testWidgets('a product with an empty ledger says so', (tester) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('product-stock-empty')), findsOne);
    expect(reader.queries.single.descending, isFalse);
    expect(reader.queries.single.equalityFilters, isEmpty);
  });

  testWidgets('a cashier is denied and issues no read at all', (tester) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(role: TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('product-stock-denied')), findsOne);
    expect(reader.queries, isEmpty);
    expect(reader.documentPaths, isEmpty);
  });

  testWidgets('the adjustment form is absent without a callable', (
    tester,
  ) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('product-stock-form')), findsNothing);
  });

  testWidgets('an adjustment sends the typed payload and re-reads', (
    tester,
  ) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable(_response());

    await _pump(tester, _controller(), reader, callable: callable);
    await _submit(tester, units: '4', reason: 'Delivery  received');

    expect(callable.payloads.single, <String, Object?>{
      'tenantId': 'tenant-a',
      'productId': 'product-1',
      'quantityDelta': 4,
      'type': 'restock',
      'reason': 'Delivery received',
      'requestId': 'adjust-stock-abcdefgh',
    });
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('product-stock-notice')))
          .data,
      'Stock changed from 7 to 11.',
    );
    // The page is re-read, so what is shown is the server's evidence rather
    // than an optimistic local figure.
    expect(reader.queries.length, 2);
  });

  testWidgets('a removal-only type never offers the add direction', (
    tester,
  ) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable(
      _response(
        overrides: <String, Object?>{'quantityDelta': -4, 'quantity': 3},
      ),
    );

    await _pump(tester, _controller(), reader, callable: callable);
    // A correction may go either way, so the segmented control exists.
    await tester.tap(find.byKey(const ValueKey('product-stock-type')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(TenantStockAdjustmentType.correction.label).last,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product-stock-direction')), findsOne);

    // Damage may only remove, so the direction is stated rather than chosen.
    await tester.tap(find.byKey(const ValueKey('product-stock-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TenantStockAdjustmentType.damage.label).last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product-stock-direction')), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-stock-fixed-direction')),
          )
          .data,
      'This type always removes stock.',
    );

    await _submit(tester, units: '4', reason: 'Broken in transit');
    expect(callable.payloads.single['quantityDelta'], -4);
    expect(callable.payloads.single['type'], 'damage');
  });

  testWidgets('only an unknown outcome keeps the request ID', (tester) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable.failing(
      FirebaseFunctionsException(
        code: 'unavailable',
        message: 'The service is unavailable.',
      ),
    );

    await _pump(tester, _controller(), reader, callable: callable);
    await _submit(tester, units: '4', reason: 'Delivery received');

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('product-stock-notice')))
          .data,
      startsWith('The result is unknown.'),
    );
    // The page is re-read after an unknown outcome, because only the server
    // can say whether stock moved.
    expect(reader.queries.length, 2);

    await _submit(tester, units: '4', reason: 'Delivery received');
    expect(callable.payloads.map((payload) => payload['requestId']), <String>[
      'adjust-stock-abcdefgh',
      'adjust-stock-abcdefgh',
    ]);

  });

  testWidgets('a refusal that proves nothing moved releases the ID', (
    tester,
  ) async {
    // Reusing the ID of an attempt that provably left nothing behind would
    // make an edited retry fail as a duplicate.
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable.failing(
      FirebaseFunctionsException(
        code: 'not-found',
        message: 'The product does not exist in this tenant.',
      ),
    );

    await _pump(
      tester,
      _controller(),
      reader,
      callable: callable,
      requestIds: <String>['adjust-stock-first11', 'adjust-stock-second2'],
    );
    await _submit(tester, units: '4', reason: 'Delivery received');
    await _submit(tester, units: '5', reason: 'Delivery received');

    expect(callable.payloads.map((payload) => payload['requestId']), <String>[
      'adjust-stock-first11',
      'adjust-stock-second2',
    ]);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('product-stock-notice')))
          .data,
      startsWith('This product no longer exists'),
    );
  });

  testWidgets('a response that cannot be trusted is reported, not shown', (
    tester,
  ) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable(
      _response(overrides: <String, Object?>{'quantity': 99}),
    );

    await _pump(tester, _controller(), reader, callable: callable);
    await _submit(tester, units: '4', reason: 'Delivery received');

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('product-stock-notice')))
          .data,
      startsWith('The adjustment response could not be trusted.'),
    );
  });

  testWidgets('a tenant switch discards an outstanding adjustment', (
    tester,
  ) async {
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);
    final callable = _Callable.deferred();
    final controller = _controller();

    await _pump(tester, controller, reader, callable: callable);
    await _submit(
      tester,
      units: '4',
      reason: 'Delivery received',
      settle: false,
    );
    expect(callable.payloads.single['tenantId'], 'tenant-a');

    controller.open(uid: 'manager-a', membership: _membership('tenant-b'));
    await tester.pump();
    callable.complete(_response());
    await tester.pump();
    await tester.pump();

    // The result belonged to a session that is no longer selected.
    expect(find.byKey(const ValueKey('product-stock-notice')), findsNothing);
  });

  testWidgets('the ledger pages forward and back', (tester) async {
    final reader = _Reader()
      ..respondMovements(<TenantQueryDocumentSnapshot>[
        _sale('mv-1'),
        _sale('mv-2'),
        _sale('mv-3'),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2);

    expect(find.byKey(const ValueKey('product-stock-entry-mv-1')), findsOne);
    expect(
      find.byKey(const ValueKey('product-stock-entry-mv-3')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('product-stock-next')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('product-stock-entry-mv-3')), findsOne);
    expect(reader.queries.last.startAfterDocumentId, 'mv-2');

    await tester.tap(find.byKey(const ValueKey('product-stock-previous')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('product-stock-entry-mv-1')), findsOne);
  });

  testWidgets('the ledger opens this product\'s manual corrections', (
    tester,
  ) async {
    // Both surfaces belong to the inventory domain, so the route needs no
    // injection; it opens under this route's own session scope.
    final reader = _Reader()..respondMovements(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);
    await tester.tap(
      find.byKey(const ValueKey('product-stock-adjustments')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Adjustments: Cold lager'), findsOne);
    expect(
      reader.queries.last.collectionPath,
      'tenants/tenant-a/stock_adjustments',
    );
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'productId': 'product-1',
    });
  });

  testWidgets('a ledger entry outside this product hides the page', (
    tester,
  ) async {
    final reader = _Reader()
      ..respondMovements(<TenantQueryDocumentSnapshot>[
        _sale('mv-1', overrides: <String, Object?>{'productId': 'product-9'}),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('product-stock-failure')), findsOne);
    expect(
      find.byKey(const ValueKey('product-stock-entry-mv-1')),
      findsNothing,
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  AdjustStockCallable? callable,
  List<String> requestIds = const <String>['adjust-stock-abcdefgh'],
}) async {
  // The adjustment form adds text fields, so the page carries more than one
  // Scrollable and `scrollUntilVisible` can no longer identify the list. A tall
  // surface builds every row instead, which is what these assertions need.
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var index = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantProductStockPanel(
            reader: reader,
            product: _product(),
            pageSize: pageSize,
            actions: callable == null
                ? null
                : TenantStockActions(adjustCallable: callable),
            requestIdFactory: () =>
                requestIds[index++ < requestIds.length
                    ? index - 1
                    : requestIds.length - 1],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Fills the form and confirms, which is the only way stock ever moves.
Future<void> _submit(
  WidgetTester tester, {
  required String units,
  required String reason,
  bool settle = true,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('product-stock-units')),
    units,
  );
  await tester.enterText(
    find.byKey(const ValueKey('product-stock-reason')),
    reason,
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('product-stock-submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('product-stock-confirm')));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

TenantProduct _product() => TenantProduct.fromDocument(
  path: 'tenants/tenant-a/products/product-1',
  data: _productData(),
);

Map<String, Object?> _productData() => <String, Object?>{
  'name': 'Cold lager',
  'SKU': 'LAGER-001',
  'price': 120.5,
  'quantity': 7,
  'categoryId': 'drinks',
};

Map<String, Object?> _response({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'adjustmentId': 'sa_abc',
    'productId': 'product-1',
    'previousQuantity': 7,
    'quantity': 11,
    'quantityDelta': 4,
  };
  if (overrides != null) data.addAll(overrides);
  return data;
}

TenantQueryDocumentSnapshot _adjustment(String movementId) =>
    TenantQueryDocumentSnapshot(
      path: 'tenants/tenant-a/products/product-1/stock_movements/$movementId',
      data: <String, Object?>{
        'movementId': movementId,
        'tenantId': 'tenant-a',
        'productId': 'product-1',
        'sourceType': 'manual_adjustment',
        'adjustmentType': 'damage',
        'quantityDelta': -3,
        'previousQuantity': 10,
        'quantityAfter': 7,
        'reason': 'Broken in transit',
        'actorUid': 'manager-a',
        'recordedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 9)),
      },
    );

TenantQueryDocumentSnapshot _sale(
  String movementId, {
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'movementId': movementId,
    'tenantId': 'tenant-a',
    'productId': 'product-1',
    'sourceType': 'sale',
    'sourceId': 'chk-1',
    'quantityDelta': -2,
    'recordedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 11)),
  };
  if (overrides != null) data.addAll(overrides);
  return TenantQueryDocumentSnapshot(
    path: 'tenants/tenant-a/products/product-1/stock_movements/$movementId',
    data: data,
  );
}

TenantSessionController _controller({TenantRole role = TenantRole.manager}) =>
    TenantSessionController()..open(
      uid: 'manager-a',
      membership: _membership('tenant-a', role: role),
    );

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.manager,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

final class _Callable implements AdjustStockCallable {
  _Callable(this._response) : _error = null, _defer = false;
  _Callable.failing(Object error)
    : _response = null,
      _error = error,
      _defer = false;
  _Callable.deferred() : _response = null, _error = null, _defer = true;

  final Object? _response;
  final Object? _error;
  final bool _defer;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  final List<Completer<Object?>> _pending = <Completer<Object?>>[];

  void complete(Object? response) {
    if (_pending.isEmpty) return;
    _pending.removeAt(0).complete(response);
  }

  @override
  Future<Object?> call(Map<String, Object?> payload) {
    payloads.add(payload);
    if (_defer) {
      final completer = Completer<Object?>();
      _pending.add(completer);
      return completer.future;
    }
    final error = _error;
    if (error != null) return Future<Object?>.error(error);
    return Future<Object?>.value(_response);
  }
}

final class _Reader implements TenantDataReader {
  _Reader({this.staffNames = const <String, String>{}});

  final Map<String, String> staffNames;
  List<TenantQueryDocumentSnapshot> _movements =
      const <TenantQueryDocumentSnapshot>[];
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<String> documentPaths = <String>[];

  void respondMovements(List<TenantQueryDocumentSnapshot> page) =>
      _movements = page;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentPaths.add(path);
    if (path == 'tenants/tenant-a/products/product-1') {
      return TenantDocumentSnapshot(path: path, data: _productData());
    }
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
  ) async {
    queries.add(query);
    final cursor = query.startAfterDocumentId;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final snapshot in _movements) {
      final id = snapshot.path.split('/').last;
      if (cursor != null && id.compareTo(cursor) <= 0) continue;
      matches.add(snapshot);
      if (matches.length >= query.limit) break;
    }
    return matches;
  }
}
