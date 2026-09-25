import 'package:flutter/material.dart';
import 'package:flutter_application_1/production/production.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/buttons.dart';
import '../support/notices.dart';

/// The Production route: the batches made, and recording the next one.
void main() {
  testWidgets('batches are listed newest first, with what one unit cost', (
    tester,
  ) async {
    await _pump(tester, _Reader(batches: _twoBatches()));

    expect(find.byKey(const ValueKey('production-row-pb_2')), findsOneWidget);
    expect(find.text('White bread loaf · 100 made'), findsWidgets);
    final show = find.byKey(const ValueKey('production-costs-pb_2'));
    await tester.tap(show);
    await tester.pumpAndSettle();
    expect(find.text('Flour'), findsOneWidget);
    expect(
      find.textContaining('Cost per unit went from KES 28 to KES 30'),
      findsOneWidget,
    );
  });

  testWidgets('a business with no batches is told what to do first', (
    tester,
  ) async {
    await _pump(tester, _Reader());

    expect(find.byKey(const ValueKey('production-empty')), findsOneWidget);
  });

  testWidgets('a batch is recorded from the last one, and every change stated first', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, _Reader(batches: _twoBatches()), writer: writer);

    await tester.tap(find.byKey(const ValueKey('production-record')));
    await tester.pumpAndSettle();
    // The warning that decides whether profit is counted right is on the form.
    expect(
      find.byKey(const ValueKey('production-expenses-warning')),
      findsOneWidget,
    );
    await _chooseProduct(tester, 'prod-bread');

    // The last batch's rows are the start, and it says so.
    expect(find.byKey(const ValueKey('production-started-from')), findsOneWidget);
    expect(_fieldText(tester, 'production-row-description-0'), 'Flour');
    expect(_fieldText(tester, 'production-row-amount-0'), '2000');

    await tester.enterText(
      find.byKey(const ValueKey('production-quantity')),
      '100',
    );
    await tester.pumpAndSettle();
    expect(_text(tester, 'production-total'), 'KES 3000');
    expect(_text(tester, 'production-unit-cost'), 'KES 30');

    await _submit(tester);
    expect(find.textContaining('12 to 112 in stock'), findsOneWidget);
    expect(
      find.textContaining('Its cost changes from KES 28 to KES 30'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('production-confirm')));
    await tester.pumpAndSettle();

    final intent = writer.completed.single;
    expect(intent.product.id, 'prod-bread');
    expect(intent.quantity, 100);
    expect(intent.unitCostMinor, 3000);
    expect(snackNotice(tester).status, AppStatus.ok);
    expect(snackNotice(tester).message, contains('100 White bread loaf recorded'));
  });

  testWidgets('complete stays unavailable until the batch has a cost', (
    tester,
  ) async {
    await _pump(tester, _Reader(), writer: _Writer());

    await tester.tap(find.byKey(const ValueKey('production-record')));
    await tester.pumpAndSettle();
    await _chooseProduct(tester, 'prod-bread');
    await tester.enterText(
      find.byKey(const ValueKey('production-quantity')),
      '100',
    );
    await tester.pumpAndSettle();

    expect(_submitEnabled(tester), isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('production-row-description-0')),
      'Flour',
    );
    await tester.enterText(
      find.byKey(const ValueKey('production-row-amount-0')),
      '2000',
    );
    await tester.pumpAndSettle();

    expect(_submitEnabled(tester), isTrue);
  });

  testWidgets('only products made here are offered, and the rest are explained', (
    tester,
  ) async {
    await _pump(tester, _Reader(), writer: _Writer());

    await tester.tap(find.byKey(const ValueKey('production-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('production-choose-product')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('product-picker-search')),
      'mi',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('product-picker-choose-prod-milk')), findsNothing);
    expect(find.byKey(const ValueKey('product-picker-refused')), findsOneWidget);
  });
}

List<Map<String, Object?>> _rows() => <Map<String, Object?>>[
  <String, Object?>{'description': 'Flour', 'amountMinor': 200000},
  <String, Object?>{'description': 'Labour', 'amountMinor': 100000},
];

Map<String, Map<String, Object?>> _twoBatches() =>
    <String, Map<String, Object?>>{
      'pb_2': <String, Object?>{
        'batchNumber': 'PB-20260923-AAAAAA',
        'productId': 'prod-bread',
        'productName': 'White bread loaf',
        'quantity': 100,
        'expenses': _rows(),
        'totalCostMinor': 300000,
        'unitCostMinor': 3000,
        'previousCostMinor': 2800,
        'createdAt': DateTime.utc(2026, 9, 23, 5),
      },
      'pb_1': <String, Object?>{
        'batchNumber': 'PB-20260922-BBBBBB',
        'productId': 'prod-bread',
        'productName': 'White bread loaf',
        'quantity': 100,
        'expenses': <Map<String, Object?>>[
          <String, Object?>{'description': 'Flour', 'amountMinor': 280000},
        ],
        'totalCostMinor': 280000,
        'unitCostMinor': 2800,
        'createdAt': DateTime.utc(2026, 9, 22, 5),
      },
    };

String? _fieldText(WidgetTester tester, String key) =>
    tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(EditableText),
          ),
        )
        .controller
        .text;

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

bool _submitEnabled(WidgetTester tester) =>
    pressable(tester, 'production-submit');

Future<void> _chooseProduct(WidgetTester tester, String productId) async {
  await tester.tap(find.byKey(const ValueKey('production-choose-product')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('product-picker-search')),
    'br',
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('product-picker-choose-$productId')));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  final submit = find.byKey(const ValueKey('production-submit'));
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  _Reader reader, {
  TenantProductionWriter? writer,
}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TenantSessionController()
    ..open(uid: 'user-a', membership: _membership());
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantProductionScreen(
          reader: reader,
          services: TenantProductionServices(
            writer: writer ?? _Writer(),
            productSearchReader: reader,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TenantMembership _membership() => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: 'tenant-a',
  tenantSlug: 'tenant-a',
  role: TenantRole.manager,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

final class _Writer implements TenantProductionWriter {
  final List<TenantProductionIntent> completed = <TenantProductionIntent>[];

  @override
  Future<TenantProductionWriteResult> complete(
    TenantProductionIntent intent,
  ) async {
    completed.add(intent);
    return TenantProductionWriteResult.queued(intent.operationId);
  }
}

/// Two products - bread made here, milk bought in - and whatever batches a
/// test names, newest ID highest so the ID order is the time order.
final class _Reader implements TenantDataReader, TenantProductSearchReader {
  _Reader({this.batches = const <String, Map<String, Object?>>{}});

  final Map<String, Map<String, Object?>> batches;

  static const Map<String, Map<String, Object?>> _products =
      <String, Map<String, Object?>>{
        'prod-bread': <String, Object?>{
          'name': 'White bread loaf',
          'SKU': 'BR-1',
          'price': 50,
          'cost': 28,
          'quantity': 12,
          'categoryId': 'ct_bakery',
          'costType': 'produced',
          'searchName': 'white bread loaf',
          'searchPrefixes': <String>['br', 'bre', 'bread', 'wh'],
        },
        'prod-milk': <String, Object?>{
          'name': 'Milk 500ml',
          'SKU': 'MK-1',
          'price': 50,
          'quantity': 5,
          'categoryId': 'ct_dairy',
          'costType': 'purchased',
          'searchName': 'milk 500ml',
          'searchPrefixes': <String>['mi', 'mil', 'milk'],
        },
      };

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (path == 'tenants/tenant-a/configuration/checkout') {
      return TenantDocumentSnapshot(
        path: path,
        data: const <String, Object?>{'currency': 'KES'},
      );
    }
    return null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    if (!query.collectionPath.endsWith('/production_batches')) {
      return const <TenantQueryDocumentSnapshot>[];
    }
    final ids = batches.keys.toList()..sort();
    final ordered = query.descending ? ids.reversed.toList() : ids;
    return <TenantQueryDocumentSnapshot>[
      for (final id in ordered)
        if (query.equalityFilters.entries.every(
          (filter) => batches[id]![filter.key] == filter.value,
        ))
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/$id',
            data: batches[id]!,
          ),
    ].take(query.limit).toList();
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantProducts(
    TenantProductSearchQuery query,
  ) async => <TenantQueryDocumentSnapshot>[
    for (final entry in _products.entries)
      if (query.searchPrefix == null ||
          (entry.value['searchPrefixes']! as List).contains(query.searchPrefix))
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/${entry.key}',
          data: entry.value,
        ),
  ];
}
