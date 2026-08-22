import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/record_list.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/text.dart';

void main() {
  testWidgets('one product\'s ledger is read by path, not by group', (
    tester,
  ) async {
    // The decision this chunk settled: the same rows a `productId`-narrowed
    // collection group would return, from the read Firestore bounds by path.
    final reader = _Reader(
      product: _productData(),
      movements: <String, Map<String, Object?>>{'sa_abc': _adjustmentData()},
    );

    await _pump(tester, _controller(), reader);

    expect(reader.groupQueries, isEmpty);
    expect(
      reader.queries.single.collectionPath,
      'tenants/tenant-a/products/product-1/stock_movements',
    );
    expect(reader.queries.single.equalityFilters, isEmpty);
    expect(reader.queries.single.descending, isFalse);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('product-ledger-title')))
          .data,
      'Coffee beans',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('product-ledger-quantity')))
          .data,
      'Recorded stock: 7',
    );
    expect(
      find.byKey(const ValueKey('product-ledger-product-deleted')),
      findsNothing,
    );
  });

  testWidgets('a deleted product says so and still lists its ledger', (
    tester,
  ) async {
    // An owner or admin may delete a product; the ledger below it is
    // `write: if false` and Firestore does not cascade, so it outlives the
    // product permanently. This route is the only place it can still be read.
    final reader = _Reader(
      product: null,
      movements: <String, Map<String, Object?>>{'sa_abc': _adjustmentData()},
    );

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('product-ledger-title')))
          .data,
      'Deleted product',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-ledger-product-deleted')),
          )
          .data,
      startsWith('This product no longer exists in the catalog.'),
    );
    // The figure would be a fiction: there is no product document to read one
    // from, so none is shown.
    expect(find.byKey(const ValueKey('product-ledger-quantity')), findsNothing);
    // The ledger itself is unaffected.
    expect(find.byKey(const ValueKey('product-ledger-entry-sa_abc')), findsOne);
  });

  testWidgets('the rows are worded exactly as the business-wide feed', (
    tester,
  ) async {
    // Both surfaces render the same documents, so the labels are shared rather
    // than copied. A movement recorded by nobody names the server.
    final reader = _Reader(
      product: _productData(),
      movements: <String, Map<String, Object?>>{
        'sa_abc': _adjustmentData(),
        'sale_co-1': _saleData(),
      },
      staffNames: <String, String>{'manager-a': 'Amina'},
    );

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-ledger-delta-sa_abc')),
          )
          .data,
      '-3 • ${TenantStockMovementSource.manualAdjustment.label}',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-ledger-figures-sa_abc')),
          )
          .data,
      '10 to 7',
    );
    // A reason and a typed category are labelled values now rather than
    // sentences carrying their own key. The category used to be visible only on
    // the stock route, which said `Adjustment: damage` in the record's title
    // where this screen said `Manual adjustment` for the same document.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-ledger-reason-sa_abc')),
          )
          .data,
      'Broken in transit',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-ledger-adjustment-type-sa_abc')),
          )
          .data,
      'damage',
    );
    expect(
      textAt(tester, 'product-ledger-recorded-sa_abc'),
      'Recorded 2026-08-01 09:00 UTC by You (Amina)',
    );
    // A reconciled sale records neither an actor nor a before and after, and
    // names the sale it came from where an adjustment names a reason. Both are
    // columns rather than one line whose meaning changes per row.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-ledger-figures-sale_co-1')),
          )
          .data,
      'Not recorded',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('product-ledger-source-sale_co-1')),
          )
          .data,
      'co-1',
    );
    expect(
      textAt(tester, 'product-ledger-recorded-sale_co-1'),
      'Recorded 2026-08-01 11:00 UTC by the server',
    );
    // The columns are the union of what any record carries, so a sale that is
    // silent about a reason gets an empty cell rather than a dash.
    expect(
      RecordList.columnsOf(
        tester.widget<RecordList>(find.byType(RecordList)).items,
      ).map((column) => column.label),
      <String>[
        stockBeforeAndAfterLabel,
        stockAdjustmentTypeLabel,
        stockReasonLabel,
        stockSourceLabel,
      ],
    );
  });

  testWidgets('a ledger entry states the same facts on a phone', (
    tester,
  ) async {
    // This route has only ever been laid out at 1400. §4.1's `compact` band is
    // 411 and a record marks nothing out of the narrow form, so every fact
    // survives the card.
    final reader = _Reader(
      product: _productData(),
      movements: <String, Map<String, Object?>>{'sa_abc': _adjustmentData()},
    );

    await _pump(tester, _controller(), reader, width: 411);

    expect(
      RecordList.formFor(tester.view.physicalSize.width),
      RecordForm.stackedCards,
    );
    for (final key in <String>[
      'product-ledger-entry-sa_abc',
      'product-ledger-delta-sa_abc',
      'product-ledger-figures-sa_abc',
      'product-ledger-adjustment-type-sa_abc',
      'product-ledger-reason-sa_abc',
      'product-ledger-recorded-sa_abc',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOne, reason: key);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a movement carries no standing and nothing to do', (
    tester,
  ) async {
    // §2.1's five each mean one thing and "stock moved" is not among them, so
    // no row wears a badge. The direction is the sign on the delta, which is
    // where it always was - the arrow beside it only ever repeated it.
    final reader = _Reader(
      product: _productData(),
      movements: <String, Map<String, Object?>>{'sa_abc': _adjustmentData()},
    );

    await _pump(tester, _controller(), reader);

    final list = tester.widget<RecordList>(find.byType(RecordList));
    expect(list.identityLabel, 'Movement');
    expect(list.items.single.status, isNull);
    expect(list.items.single.actions, isEmpty);
    expect(list.items.single.title, startsWith('-3 • '));
  });

  testWidgets('a product with an empty ledger says so', (tester) async {
    final reader = _Reader(
      product: _productData(),
      movements: const <String, Map<String, Object?>>{},
    );

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('product-ledger-empty')))
          .data,
      'No stock movement has been recorded against this product.',
    );
  });

  testWidgets('nothing on this route can correct anything', (tester) async {
    // The catalog's product route records adjustments; this one is reached
    // from a movement row and is read-only, which is what lets it open for a
    // product that no longer exists.
    final reader = _Reader(
      product: _productData(),
      movements: <String, Map<String, Object?>>{'sa_abc': _adjustmentData()},
    );

    await _pump(tester, _controller(), reader);

    // A single-page ledger renders no control whatsoever: no field to type an
    // adjustment into, and not even a pagination button.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(DropdownButtonFormField<Object?>), findsNothing);
  });

  testWidgets('a cashier is refused the ledger', (tester) async {
    final reader = _Reader(
      product: _productData(),
      movements: <String, Map<String, Object?>>{'sa_abc': _adjustmentData()},
    );

    await _pump(tester, _controller(role: TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('product-ledger-denied')), findsOne);
    expect(reader.queries, isEmpty);
  });

  testWidgets('a failed read shows no ledger at all', (tester) async {
    final reader = _Reader(
      product: _productData(),
      movements: const <String, Map<String, Object?>>{},
      failCollection: true,
    );

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('product-ledger-failure')), findsOne);
    expect(find.byKey(const ValueKey('product-ledger')), findsNothing);
  });

  testWidgets('pages advance and return on a stable cursor', (tester) async {
    final reader = _Reader(
      product: _productData(),
      movements: <String, Map<String, Object?>>{
        'mv-1': _adjustmentData(movementId: 'mv-1'),
        'mv-2': _adjustmentData(movementId: 'mv-2'),
        'mv-3': _adjustmentData(movementId: 'mv-3'),
      },
    );

    await _pump(tester, _controller(), reader, pageSize: 2);
    expect(find.byKey(const ValueKey('product-ledger-entry-mv-1')), findsOne);
    // **Present and disabled rather than absent**, since `Pagination`. Eleven
    // screens used to hide the control on the first page, so the bar moved
    // under a thumb as a person paged; §5's `disabled` row is what that is for,
    // and this is the stronger assertion of the two.
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('product-ledger-previous')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('product-ledger-next')));
    await tester.pump();
    await tester.pump();
    expect(reader.queries.last.startAfterDocumentId, 'mv-2');
    expect(find.byKey(const ValueKey('product-ledger-entry-mv-3')), findsOne);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('product-ledger-next')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('product-ledger-previous')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('product-ledger-entry-mv-1')), findsOne);
  });

  testWidgets('a tenant switch discards the outstanding page', (tester) async {
    final controller = _controller();
    final reader = _Reader.deferred();

    await _pump(tester, controller, reader, settle: false);
    await tester.pump();

    controller.open(uid: 'manager-a', membership: _membership('tenant-b'));
    await tester.pump();

    reader.completeFirst(<String, Map<String, Object?>>{
      'sa_abc': _adjustmentData(),
    });
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('product-ledger-entry-sa_abc')),
      findsNothing,
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  String productId = 'product-1',
  int pageSize = 20,
  bool settle = true,
  double width = 1400,
}) async {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantProductLedgerPanel(
            reader: reader,
            productId: productId,
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

/// Answers the product document, the ledger page, and staff labels.
///
/// It implements the collection-group boundary as well, and refuses it. The
/// panel cannot reach that method through its `TenantDataReader` parameter
/// today, and the refusal is what makes the decision hold if that ever changes.
final class _Reader implements TenantDataReader, TenantCollectionGroupReader {
  _Reader({
    required this.product,
    required this.movements,
    this.staffNames = const <String, String>{},
    this.failCollection = false,
  }) : _defer = false;

  _Reader.deferred()
    : product = _productData(),
      movements = const <String, Map<String, Object?>>{},
      staffNames = const <String, String>{},
      failCollection = false,
      _defer = true;

  final Map<String, Object?>? product;
  final Map<String, Map<String, Object?>> movements;
  final Map<String, String> staffNames;
  final bool failCollection;
  final bool _defer;

  final List<String> documentPaths = <String>[];
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<TenantCollectionGroupQuery> groupQueries =
      <TenantCollectionGroupQuery>[];
  final List<Completer<Map<String, Map<String, Object?>>>> _pending =
      <Completer<Map<String, Map<String, Object?>>>>[];

  void completeFirst(Map<String, Map<String, Object?>> page) {
    if (_pending.isEmpty) return;
    _pending.removeAt(0).complete(page);
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentPaths.add(path);
    final id = path.split('/').last;
    if (path.contains('/products/')) {
      final data = product;
      return data == null
          ? null
          : TenantDocumentSnapshot(path: path, data: data);
    }
    final name = staffNames[id];
    return name == null
        ? null
        : TenantDocumentSnapshot(
            path: path,
            data: <String, Object?>{'uid': id, 'name': name},
          );
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    if (failCollection) throw StateError('unavailable');
    final page = _defer ? await _deferred() : movements;
    final ids = page.keys.toList()..sort();
    final cursor = query.startAfterDocumentId;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final id in ids) {
      if (cursor != null && id.compareTo(cursor) <= 0) continue;
      matches.add(
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/$id',
          data: page[id]!,
        ),
      );
      if (matches.length >= query.limit) break;
    }
    return matches;
  }

  Future<Map<String, Map<String, Object?>>> _deferred() {
    final completer = Completer<Map<String, Map<String, Object?>>>();
    _pending.add(completer);
    return completer.future;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionGroupPage(
    TenantCollectionGroupQuery query,
  ) async {
    groupQueries.add(query);
    throw StateError('This route must not issue a collection group page.');
  }
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

Map<String, Object?> _productData() => <String, Object?>{
  'name': 'Coffee beans',
  'SKU': 'SKU-1',
  'price': 250,
  'quantity': 7,
  'categoryId': 'cat-1',
};

Map<String, Object?> _adjustmentData({String movementId = 'sa_abc'}) =>
    <String, Object?>{
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
    };

Map<String, Object?> _saleData() => <String, Object?>{
  'movementId': 'sale_co-1',
  'tenantId': 'tenant-a',
  'productId': 'product-1',
  'sourceType': 'sale',
  'sourceId': 'co-1',
  'quantityDelta': -2,
  'recordedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 11)),
};
