import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/record_list.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/collection_pages.dart';

import '../support/text.dart';

void main() {
  testWidgets('the business-wide record is listed as it was recorded', (
    tester,
  ) async {
    final reader = _Reader(staffNames: <String, String>{'owner-a': 'Juma'})
      ..respond(<TenantQueryDocumentSnapshot>[
        _adjustment('sa_abc'),
        _adjustment(
          'sa_def',
          overrides: <String, Object?>{
            'productId': 'product-9',
            'adjustmentType': 'restock',
            'quantityDelta': 6,
            'previousQuantity': 4,
            'quantityAfter': 10,
            'reason': 'Delivery received',
            'actorUid': 'owner-a',
          },
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('stock-adjustments-scope')))
          .data,
      startsWith('Every manual correction recorded across this business.'),
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('stock-adjustments-delta-sa_abc')),
          )
          .data,
      '-3 • ${TenantStockAdjustmentType.damage.label}',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('stock-adjustments-product-sa_abc')),
          )
          .data,
      'Product product-1',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('stock-adjustments-figures-sa_abc')),
          )
          .data,
      '10 to 7',
    );
    // The reason is a labelled value now rather than a sentence carrying its
    // own key: §5.2's attributes are key-value, so `Reason` is the column
    // header in a table and the key half of a line on a card.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('stock-adjustments-reason-sa_abc')),
          )
          .data,
      'Broken in transit',
    );
    expect(find.text(stockReasonLabel), findsWidgets);
    // The signed-in manager recorded this one, so the row says so rather than
    // repeating their own UID back at them. Their name was never read, so only
    // the authoritative UID is available for them.
    expect(
      textAt(tester, 'stock-adjustments-recorded-sa_abc'),
      'Recorded 2026-08-01 09:00 UTC by You',
    );
    // A colleague is labelled by the resolved name beside their UID.
    expect(
      textAt(tester, 'stock-adjustments-recorded-sa_def'),
      'Recorded 2026-08-01 09:00 UTC by Juma (owner-a)',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('stock-adjustments-delta-sa_def')),
          )
          .data,
      '+6 • ${TenantStockAdjustmentType.restock.label}',
    );
    // Newest first, by when the correction was recorded. An adjustment ID is
    // `sa_` plus a digest, so what this page used to be ordered by said nothing
    // about when anything happened.
    expect(reader.queries.single.descending, isTrue);
    expect(reader.queries.single.order, TenantCollectionOrder.occurredAt);
    expect(reader.queries.single.equalityFilters, isEmpty);
  });

  testWidgets('a business with no corrections says so', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('stock-adjustments-empty')))
          .data,
      'No stock adjustments yet.',
    );
  });

  testWidgets('a product-scoped feed states its scope and filters', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[_adjustment('sa_abc')]);

    await _pump(tester, _controller(), reader, product: _product());

    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'productId': 'product-1',
    });
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('stock-adjustments-scope')))
          .data,
      startsWith('Every manual correction recorded against product product-1.'),
    );
    expect(
      find.byKey(const ValueKey('stock-adjustments-entry-sa_abc')),
      findsOne,
    );
  });

  testWidgets('a cashier is denied and issues no read at all', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(role: TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('stock-adjustments-denied')), findsOne);
    expect(reader.queries, isEmpty);
    expect(reader.documentPaths, isEmpty);
  });

  testWidgets('the feed pages forward and back', (tester) async {
    // Recorded oldest-first in ID order, so the first page holding `sa_3` is
    // the page being newest-first rather than a coincidence of the IDs.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _adjustment('sa_1', recordedAt: DateTime.utc(2026, 8, 1, 9)),
        _adjustment('sa_2', recordedAt: DateTime.utc(2026, 8, 2, 9)),
        _adjustment('sa_3', recordedAt: DateTime.utc(2026, 8, 3, 9)),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 2);

    expect(
      find.byKey(const ValueKey('stock-adjustments-entry-sa_3')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('stock-adjustments-entry-sa_1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('stock-adjustments-next')));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('stock-adjustments-entry-sa_1')),
      findsOne,
    );
    expect(reader.queries.last.startAfterDocumentId, 'sa_2');
    expect(
      reader.queries.last.startAfterOrderValue,
      DateTime.utc(2026, 8, 2, 9),
    );

    await tester.tap(find.byKey(const ValueKey('stock-adjustments-previous')));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('stock-adjustments-entry-sa_3')),
      findsOne,
    );
  });

  testWidgets('a record that contradicts itself hides the page', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _adjustment('sa_abc', overrides: <String, Object?>{'quantityAfter': 8}),
      ]);

    await _pump(tester, _controller(), reader);

    expect(find.byKey(const ValueKey('stock-adjustments-failure')), findsOne);
    expect(
      find.byKey(const ValueKey('stock-adjustments-entry-sa_abc')),
      findsNothing,
    );
  });

  testWidgets('a tenant switch discards an outstanding page', (tester) async {
    final controller = _controller();
    final reader = _Reader.deferred();

    await _pump(tester, controller, reader, settle: false);
    expect(
      reader.queries.single.collectionPath,
      'tenants/tenant-a/stock_adjustments',
    );

    controller.open(uid: 'manager-a', membership: _membership('tenant-b'));
    await tester.pump();
    expect(
      reader.queries.last.collectionPath,
      'tenants/tenant-b/stock_adjustments',
    );

    // The first business's page arrives after the switch and is discarded
    // before it can label another business's screen.
    reader.completeFirst(<TenantQueryDocumentSnapshot>[_adjustment('sa_abc')]);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('stock-adjustments-entry-sa_abc')),
      findsNothing,
    );

    reader.completeFirst(<TenantQueryDocumentSnapshot>[
      _adjustment('sa_xyz', tenantId: 'tenant-b'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('stock-adjustments-entry-sa_xyz')),
      findsOne,
    );
  });

  testWidgets('a correction states the same facts on a phone', (tester) async {
    // The class of defect the staff directory found a step earlier: a surface
    // that has only ever been laid out wide. §4.1's `compact` band gives a
    // record about 340 logical pixels where the 1400 every other case in this
    // file uses gives it the whole page.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[_adjustment('sa_abc')]);

    await _pump(tester, _controller(), reader, width: 411);

    expect(
      RecordList.formFor(tester.view.physicalSize.width),
      RecordForm.stackedCards,
    );
    expect(
      find.byKey(const ValueKey('stock-adjustments-entry-sa_abc')),
      findsOne,
    );
    // Identity, the product it is against, both attributes and the provenance
    // line: §4.3 concedes a *loss* only per attribute, and this record marks
    // none of them, so a phone states everything a table does.
    for (final key in <String>[
      'stock-adjustments-delta-sa_abc',
      'stock-adjustments-product-sa_abc',
      'stock-adjustments-figures-sa_abc',
      'stock-adjustments-reason-sa_abc',
      'stock-adjustments-recorded-sa_abc',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOne, reason: key);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a correction carries no standing and nothing to do', (
    tester,
  ) async {
    // §2.1's five statuses each mean one thing and "a correction was recorded"
    // is not among them, so this list wears no badge at all - the same reading
    // the activity log made. It is also read-only: nothing on this surface can
    // record, amend, or undo an adjustment, so the record offers no action and
    // the table draws no actions column.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[_adjustment('sa_abc')]);

    await _pump(tester, _controller(), reader);

    final list = tester.widget<RecordList>(find.byType(RecordList));
    expect(list.identityLabel, 'Adjustment');
    expect(list.items.single.status, isNull);
    expect(list.items.single.actions, isEmpty);
    expect(list.items.single.details, isNull);
    expect(
      RecordList.columnsOf(list.items).map((column) => column.label),
      <String>[stockBeforeAndAfterLabel, stockReasonLabel],
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  TenantProduct? product,
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
          body: TenantStockAdjustmentFeedPanel(
            reader: reader,
            product: product,
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

TenantProduct _product() => TenantProduct.fromDocument(
  path: 'tenants/tenant-a/products/product-1',
  data: <String, Object?>{
    'name': 'Cold lager',
    'SKU': 'LAGER-001',
    'price': 120.5,
    'quantity': 7,
    'categoryId': 'drinks',
  },
);

TenantQueryDocumentSnapshot _adjustment(
  String adjustmentId, {
  String tenantId = 'tenant-a',
  DateTime? recordedAt,
  DateTime? occurredAt,
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'tenantId': tenantId,
    'productId': 'product-1',
    'sourceType': 'manual_adjustment',
    'adjustmentType': 'damage',
    'quantityDelta': -3,
    'previousQuantity': 10,
    'quantityAfter': 7,
    'reason': 'Broken in transit',
    'actorUid': 'manager-a',
    'requestId': 'adjust-stock-abcdefgh',
    'occurredAt': Timestamp.fromDate(
      occurredAt ?? recordedAt ?? DateTime.utc(2026, 8, 1, 9),
    ),
    'createdAt': Timestamp.fromDate(recordedAt ?? DateTime.utc(2026, 8, 1, 9)),
  };
  if (overrides != null) data.addAll(overrides);
  return TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/stock_adjustments/$adjustmentId',
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

final class _Reader implements TenantDataReader {
  _Reader({this.staffNames = const <String, String>{}}) : _defer = false;
  _Reader.deferred() : staffNames = const <String, String>{}, _defer = true;

  final Map<String, String> staffNames;
  final bool _defer;
  List<TenantQueryDocumentSnapshot> _page =
      const <TenantQueryDocumentSnapshot>[];
  final List<Completer<List<TenantQueryDocumentSnapshot>>> _pending =
      <Completer<List<TenantQueryDocumentSnapshot>>>[];
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];
  final List<String> documentPaths = <String>[];

  void respond(List<TenantQueryDocumentSnapshot> page) => _page = page;

  void completeFirst(List<TenantQueryDocumentSnapshot> page) {
    if (_pending.isEmpty) return;
    _pending.removeAt(0).complete(page);
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    documentPaths.add(path);
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
    if (_defer) {
      final completer = Completer<List<TenantQueryDocumentSnapshot>>();
      _pending.add(completer);
      return completer.future;
    }
    // Ordered, cursored and filtered the way Firestore would: the stock ledger
    // is newest-first by time now, and the repository proves the order of what
    // it is handed.
    return Future<List<TenantQueryDocumentSnapshot>>.value(
      tenantCollectionPageOf(query, _page),
    );
  }
}
