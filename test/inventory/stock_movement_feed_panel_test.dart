import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/record_list.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/text.dart';

void main() {
  testWidgets('every source is listed as the server recorded it', (
    tester,
  ) async {
    final reader = _Reader(staffNames: <String, String>{'owner-a': 'Juma'})
      ..respond(<TenantQueryDocumentSnapshot>[
        _movement('product-1', 'sa_abc'),
        _movement(
          'product-2',
          'sale_co-1',
          overrides: <String, Object?>{
            'sourceType': 'sale',
            'sourceId': 'co-1',
            'quantityDelta': -2,
            'adjustmentType': null,
            'reason': null,
            'actorUid': null,
            'previousQuantity': null,
            'quantityAfter': null,
          },
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('stock-movements-feed-scope')),
          )
          .data,
      startsWith('Every entry recorded against this business\'s products'),
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('stock-movements-feed-delta-product-1-sa_abc'),
            ),
          )
          .data,
      '-3 • ${TenantStockMovementSource.manualAdjustment.label}',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('stock-movements-feed-figures-product-1-sa_abc'),
            ),
          )
          .data,
      '10 to 7',
    );
    // A reason and a typed category are labelled values now rather than
    // sentences that carried their own key, and the category is new to this
    // screen: the stock route used to be the only one that stated it, inside a
    // title that read `Adjustment: damage` where this one read `Manual
    // adjustment` for the same document.
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('stock-movements-feed-reason-product-1-sa_abc'),
            ),
          )
          .data,
      'Broken in transit',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey(
                'stock-movements-feed-adjustment-type-product-1-sa_abc',
              ),
            ),
          )
          .data,
      'damage',
    );
    // The signed-in manager recorded this correction, so the row says so.
    expect(
      textAt(tester, 'stock-movements-feed-recorded-product-1-sa_abc'),
      'Recorded 2026-08-01 09:00 UTC by You',
    );
    // A reconciled sale names no member of the business at all, and its writer
    // never read the product, so neither is invented on screen.
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey(
                'stock-movements-feed-figures-product-2-sale_co-1',
              ),
            ),
          )
          .data,
      'Not recorded',
    );
    expect(
      textAt(tester, 'stock-movements-feed-recorded-product-2-sale_co-1'),
      'Recorded 2026-08-01 09:00 UTC by the server',
    );
    // The sale it came from is its own column, so one document is filed under
    // the same label whichever of the three movement surfaces draws it.
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('stock-movements-feed-source-product-2-sale_co-1'),
            ),
          )
          .data,
      'co-1',
    );
    expect(reader.queries.single.equalityFilters, <String, Object?>{
      'tenantId': 'tenant-a',
    });
  });

  testWidgets('one movement ID under two products is two distinct rows', (
    tester,
  ) async {
    // A sale of two items writes `sale_{saleId}` below each product, so the row
    // identity has to be the product and the record together.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _movement('product-1', 'sale_co-1'),
        _movement('product-2', 'sale_co-1'),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      find.byKey(
        const ValueKey('stock-movements-feed-entry-product-1-sale_co-1'),
      ),
      findsOne,
    );
    expect(
      find.byKey(
        const ValueKey('stock-movements-feed-entry-product-2-sale_co-1'),
      ),
      findsOne,
    );
  });

  testWidgets('an unmodelled source is shown as itself', (tester) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _movement(
          'product-1',
          'wo_abc',
          overrides: <String, Object?>{'sourceType': 'stock_take_import'},
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('stock-movements-feed-delta-product-1-wo_abc'),
            ),
          )
          .data,
      '-3 • stock_take_import',
    );
  });

  testWidgets('a business with no movements says so', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(), reader);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('stock-movements-feed-empty')),
          )
          .data,
      'No stock movement has been recorded for this business.',
    );
  });

  testWidgets('a cashier is denied and issues no read at all', (tester) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);

    await _pump(tester, _controller(role: TenantRole.cashier), reader);

    expect(find.byKey(const ValueKey('stock-movements-feed-denied')), findsOne);
    expect(reader.queries, isEmpty);
    expect(reader.documentPaths, isEmpty);
  });

  testWidgets('narrowing the feed restarts it with the typed filter', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _movement('product-1', 'sa_1'),
        _movement('product-1', 'sa_2'),
      ]);

    await _pump(tester, _controller(), reader, pageSize: 1);
    await tester.tap(find.byKey(const ValueKey('stock-movements-feed-next')));
    await tester.pump();
    await tester.pump();
    expect(
      reader.queries.last.startAfterDocumentPath,
      'tenants/tenant-a/products/product-1/stock_movements/sa_1',
    );

    await tester.tap(find.byKey(const ValueKey('stock-movements-feed-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TenantStockMovementSource.sale.label).last);
    await tester.pumpAndSettle();

    // A cursor is a position inside one exact query, so a filter change starts
    // the page over rather than resuming somewhere the new query never was.
    expect(reader.queries.last.equalityFilters, <String, Object?>{
      'tenantId': 'tenant-a',
      'sourceType': 'sale',
    });
    expect(reader.queries.last.startAfterDocumentPath, isNull);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('stock-movements-feed-scope')),
          )
          .data,
      startsWith('Every "${TenantStockMovementSource.sale.label}" entry'),
    );
  });

  testWidgets('a pre-narrowed feed re-narrows when it is rebuilt', (
    tester,
  ) async {
    final reader = _Reader()..respond(<TenantQueryDocumentSnapshot>[]);
    final controller = _controller();

    await _pump(
      tester,
      controller,
      reader,
      source: TenantStockMovementSource.sale,
    );
    expect(reader.queries.single.equalityFilters['sourceType'], 'sale');

    await _pump(
      tester,
      controller,
      reader,
      source: TenantStockMovementSource.verifiedReturn,
    );
    expect(
      reader.queries.last.equalityFilters['sourceType'],
      'verified_return',
    );
  });

  testWidgets('a movement that contradicts itself hides the page', (
    tester,
  ) async {
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _movement(
          'product-1',
          'sa_abc',
          overrides: <String, Object?>{'quantityAfter': 8},
        ),
      ]);

    await _pump(tester, _controller(), reader);

    expect(
      find.byKey(const ValueKey('stock-movements-feed-failure')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('stock-movements-feed-entry-product-1-sa_abc')),
      findsNothing,
    );
  });

  testWidgets('a tenant switch discards an outstanding page', (tester) async {
    final controller = _controller();
    final reader = _Reader.deferred();

    await _pump(tester, controller, reader, settle: false);
    expect(reader.queries.single.equalityFilters['tenantId'], 'tenant-a');

    controller.open(uid: 'manager-a', membership: _membership('tenant-b'));
    await tester.pump();
    expect(reader.queries.last.equalityFilters['tenantId'], 'tenant-b');

    // The first business's page arrives after the switch and is discarded
    // before it can label another business's screen.
    reader.completeFirst(<TenantQueryDocumentSnapshot>[
      _movement('product-1', 'sa_abc'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('stock-movements-feed-entry-product-1-sa_abc')),
      findsNothing,
    );

    reader.completeFirst(<TenantQueryDocumentSnapshot>[
      _movement('product-9', 'sa_xyz', tenantId: 'tenant-b'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('stock-movements-feed-entry-product-9-sa_xyz')),
      findsOne,
    );
  });

  testWidgets('the feed offers no product ledger on its own', (tester) async {
    // Every injected route follows this rule: while the composition root
    // supplies none, the feed is exactly the read-only list it was before.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _movement('product-1', 'sa_abc'),
      ]);

    await _pump(tester, _controller(), reader);

    // The product it names is the record's second identifying line and is
    // stated either way; only the control that opens the ledger is withheld.
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('stock-movements-feed-product-product-1-sa_abc'),
            ),
          )
          .data,
      'Product product-1',
    );
    expect(find.byType(TextButton), findsNothing);
    expect(
      find.byKey(
        const ValueKey('stock-movements-feed-ledger-product-1-sa_abc'),
      ),
      findsNothing,
    );
    expect(
      tester.widget<RecordList>(find.byType(RecordList)).items.single.actions,
      isEmpty,
    );
  });

  testWidgets('a row opens the ledger of the product it names', (tester) async {
    // The row is the only place a product ID appears with nothing behind it,
    // and it is the one entry point that survives the product being deleted.
    final opened = <String>[];
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _movement('product-1', 'sa_abc'),
        _movement('product-2', 'sa_def'),
      ]);

    await _pump(
      tester,
      _controller(),
      reader,
      productLedgerRoute: (productId) {
        opened.add(productId);
        return Scaffold(
          body: Text('ledger', key: ValueKey('ledger-$productId')),
        );
      },
    );

    await tester.tap(
      find.byKey(
        const ValueKey('stock-movements-feed-ledger-product-2-sa_def'),
      ),
    );
    await tester.pumpAndSettle();

    expect(opened, <String>['product-2']);
    expect(find.byKey(const ValueKey('ledger-product-2')), findsOne);
  });

  testWidgets('the ledger opens under this session, not a detached one', (
    tester,
  ) async {
    // The same rule the catalog's product route follows: a tenant switch has to
    // invalidate the opened route rather than leave it behind.
    TenantSessionController? scoped;
    final controller = _controller();
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _movement('product-1', 'sa_abc'),
      ]);

    await _pump(
      tester,
      controller,
      reader,
      productLedgerRoute: (productId) => Builder(
        builder: (context) {
          scoped = TenantSessionScope.of(context);
          return const Scaffold(body: Text('ledger'));
        },
      ),
    );

    await tester.tap(
      find.byKey(
        const ValueKey('stock-movements-feed-ledger-product-1-sa_abc'),
      ),
    );
    await tester.pumpAndSettle();

    expect(scoped, same(controller));
  });

  testWidgets('a movement states the same facts on a phone', (tester) async {
    // The class of defect the staff directory found a step earlier: a screen
    // that has only ever been laid out wide. §4.3 hides an action behind a menu
    // only past three, so this row's one action is still a 48dp button on a
    // phone rather than something a person has to go looking for.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _movement('product-1', 'sa_abc'),
      ]);

    await _pump(
      tester,
      _controller(),
      reader,
      width: 411,
      productLedgerRoute: (productId) => const Scaffold(body: Text('ledger')),
    );

    expect(
      RecordList.formFor(tester.view.physicalSize.width),
      RecordForm.stackedCards,
    );
    for (final key in <String>[
      'stock-movements-feed-entry-product-1-sa_abc',
      'stock-movements-feed-delta-product-1-sa_abc',
      'stock-movements-feed-product-product-1-sa_abc',
      'stock-movements-feed-figures-product-1-sa_abc',
      'stock-movements-feed-reason-product-1-sa_abc',
      'stock-movements-feed-recorded-product-1-sa_abc',
      'stock-movements-feed-ledger-product-1-sa_abc',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOne, reason: key);
    }
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(
        const ValueKey('stock-movements-feed-ledger-product-1-sa_abc'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ledger'), findsOne);
  });

  testWidgets('a movement carries no standing', (tester) async {
    // §2.1's five each mean one thing and "stock moved" is not among them, so
    // no row wears a badge and the table draws no status column.
    final reader = _Reader()
      ..respond(<TenantQueryDocumentSnapshot>[
        _movement('product-1', 'sa_abc'),
        _movement('product-2', 'sale_co-1'),
      ]);

    await _pump(tester, _controller(), reader);

    final list = tester.widget<RecordList>(find.byType(RecordList));
    expect(list.identityLabel, 'Movement');
    expect(list.items.map((item) => item.status), everyElement(isNull));
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  int pageSize = 20,
  TenantStockMovementSource? source,
  TenantProductLedgerRouteBuilder? productLedgerRoute,
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
          body: TenantStockMovementFeedPanel(
            reader: reader,
            groupReader: reader,
            source: source,
            productLedgerRoute: productLedgerRoute,
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

TenantQueryDocumentSnapshot _movement(
  String productId,
  String movementId, {
  String tenantId = 'tenant-a',
  Map<String, Object?>? overrides,
}) {
  final data = <String, Object?>{
    'movementId': movementId,
    'tenantId': tenantId,
    'productId': productId,
    'sourceType': 'manual_adjustment',
    'adjustmentType': 'damage',
    'quantityDelta': -3,
    'previousQuantity': 10,
    'quantityAfter': 7,
    'reason': 'Broken in transit',
    'actorUid': 'manager-a',
    'recordedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 9)),
  };
  if (overrides != null) {
    overrides.forEach((field, value) {
      if (value == null) {
        data.remove(field);
      } else {
        data[field] = value;
      }
    });
  }
  return TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/products/$productId/stock_movements/$movementId',
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

final class _Reader
    implements TenantDocumentReader, TenantCollectionGroupReader {
  _Reader({this.staffNames = const <String, String>{}}) : _defer = false;
  _Reader.deferred() : staffNames = const <String, String>{}, _defer = true;

  final Map<String, String> staffNames;
  final bool _defer;
  List<TenantQueryDocumentSnapshot> _page =
      const <TenantQueryDocumentSnapshot>[];
  final List<Completer<List<TenantQueryDocumentSnapshot>>> _pending =
      <Completer<List<TenantQueryDocumentSnapshot>>>[];
  final List<TenantCollectionGroupQuery> queries =
      <TenantCollectionGroupQuery>[];
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
  Future<List<TenantQueryDocumentSnapshot>> getCollectionGroupPage(
    TenantCollectionGroupQuery query,
  ) {
    queries.add(query);
    if (_defer) {
      final completer = Completer<List<TenantQueryDocumentSnapshot>>();
      _pending.add(completer);
      return completer.future;
    }
    final cursor = query.startAfterDocumentPath;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final snapshot in _page) {
      if (cursor != null && snapshot.path.compareTo(cursor) <= 0) continue;
      if (query.equalityFilters.entries.any(
        (filter) => snapshot.data[filter.key] != filter.value,
      )) {
        continue;
      }
      matches.add(snapshot);
      if (matches.length >= query.limit) break;
    }
    return Future<List<TenantQueryDocumentSnapshot>>.value(matches);
  }
}
