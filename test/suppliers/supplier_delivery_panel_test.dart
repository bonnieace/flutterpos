import 'package:flutter/material.dart';
import 'package:uzapay_pos/suppliers/suppliers.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

/// Receiving a delivery, from a supplier's record to the queued pages, and the
/// history it leaves behind.
void main() {
  testWidgets(
    'a delivery is received from a supplier\'s record, with every change stated first',
    (tester) async {
      final writer = _DeliveryWriter();
      await _pumpRecord(tester, _Reader(), writer: writer);

      await tester.tap(find.byKey(const ValueKey('supplier-record-receive')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('delivery-reference')),
        'INV-48392',
      );
      await _addProduct(tester, search: 'br', productId: 'prod-bread');
      await tester.enterText(
        find.byKey(const ValueKey('delivery-line-quantity-prod-bread')),
        '24',
      );
      await tester.enterText(
        find.byKey(const ValueKey('delivery-line-cost-prod-bread')),
        '45.50',
      );
      await tester.pumpAndSettle();
      await _submit(tester);

      // The confirmation states each stock and cost change as from and to.
      expect(find.textContaining('40 to 64 in stock'), findsOneWidget);
      expect(
        // The app's money format: whole amounts carry no decimals.
        find.textContaining('Cost changes from KES 40 to KES 45.50'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('delivery-confirm')));
      await tester.pumpAndSettle();

      final intent = writer.received.single;
      expect(intent.supplier.id, 'sp_abc');
      expect(intent.reference, 'INV-48392');
      expect(intent.lines.single.unitCostMinor, 4550);
      expect(snackNotice(tester).status, AppStatus.ok);
      expect(
        snackNotice(tester).message,
        contains('Delivery from ABC Distributors'),
      );
    },
  );

  testWidgets('a reference already on file is warned about, never refused', (
    tester,
  ) async {
    final writer = _DeliveryWriter();
    await _pumpRecord(
      tester,
      _Reader(
        deliveries: <String, Map<String, Object?>>{
          'sd_old': _deliveryDocument(reference: 'INV-48392'),
        },
      ),
      writer: writer,
    );

    await tester.tap(find.byKey(const ValueKey('supplier-record-receive')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('delivery-reference')),
      'INV-48392',
    );
    await _addProduct(tester, search: 'br', productId: 'prod-bread');
    await tester.enterText(
      find.byKey(const ValueKey('delivery-line-quantity-prod-bread')),
      '2',
    );
    await tester.pumpAndSettle();
    await _submit(tester);

    expect(find.textContaining('already has a delivery under'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delivery-confirm')));
    await tester.pumpAndSettle();
    expect(writer.received, hasLength(1));
  });

  testWidgets(
    'a line that cannot be received is named, and nothing is queued',
    (tester) async {
      final writer = _DeliveryWriter();
      await _pumpRecord(tester, _Reader(), writer: writer);

      await tester.tap(find.byKey(const ValueKey('supplier-record-receive')));
      await tester.pumpAndSettle();
      await _addProduct(tester, search: 'br', productId: 'prod-bread');
      await tester.enterText(
        find.byKey(const ValueKey('delivery-line-quantity-prod-bread')),
        '3',
      );
      await tester.enterText(
        find.byKey(const ValueKey('delivery-line-cost-prod-bread')),
        '0',
      );
      await tester.pumpAndSettle();
      await _submit(tester);

      expect(find.byKey(const ValueKey('delivery-error')), findsOneWidget);
      expect(find.textContaining('White bread loaf'), findsWidgets);
      expect(writer.received, isEmpty);

      // The refusal is about that attempt, and goes as soon as the line is put
      // right. Found on a device, 2026-09-25: it stayed up naming a fixed line.
      await tester.enterText(
        find.byKey(const ValueKey('delivery-line-cost-prod-bread')),
        '45',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('delivery-error')), findsNothing);
    },
  );

  testWidgets('a product already on the delivery is offered as added', (
    tester,
  ) async {
    await _pumpRecord(tester, _Reader(), writer: _DeliveryWriter());

    await tester.tap(find.byKey(const ValueKey('supplier-record-receive')));
    await tester.pumpAndSettle();
    await _addProduct(tester, search: 'br', productId: 'prod-bread');
    await tester.tap(find.byKey(const ValueKey('delivery-add-product')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('delivery-product-field-1')),
        matching: find.byKey(const ValueKey('product-typeahead-search')),
      ),
      'br',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('product-typeahead-added-prod-bread')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Add product opens another inline search and adds a second line',
    (tester) async {
      await _pumpRecord(tester, _Reader(), writer: _DeliveryWriter());
      await tester.tap(find.byKey(const ValueKey('supplier-record-receive')));
      await tester.pumpAndSettle();
      await _addProduct(tester, search: 'br', productId: 'prod-bread');

      await tester.tap(find.byKey(const ValueKey('delivery-add-product')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('delivery-product-field-1')),
          matching: find.byKey(const ValueKey('product-typeahead-search')),
        ),
        'mi',
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('product-typeahead-prod-milk')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('delivery-line-prod-bread')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('delivery-line-prod-milk')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a supplier\'s record lists its deliveries and opens their lines',
    (tester) async {
      await _pumpRecord(
        tester,
        _Reader(
          deliveries: <String, Map<String, Object?>>{
            'sd_old': _deliveryDocument(reference: 'INV-1', complete: false),
          },
        ),
        writer: _DeliveryWriter(),
      );

      expect(find.byKey(const ValueKey('delivery-row-sd_old')), findsOneWidget);
      // The amount alone in the money face, and the line without a cost beside
      // it in words rather than inside the figure.
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('delivery-value-sd_old')))
            .data,
        'KES 1092',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('delivery-costless-sd_old')),
            )
            .data,
        '1 line without a cost, not in the value',
      );
      // A delivery still arriving says so, in words.
      expect(
        find.byKey(const ValueKey('delivery-arriving-sd_old')),
        findsOneWidget,
      );
      // Every line is on the card; nothing has to be opened to read it.
      await tester.ensureVisible(
        find.byKey(const ValueKey('delivery-lines-sd_old')),
      );
      expect(find.text('White bread loaf'), findsOneWidget);
      expect(find.text('24 × KES 45.50'), findsOneWidget);
      expect(find.text('12 × no cost recorded'), findsOneWidget);
    },
  );
}

Future<void> _addProduct(
  WidgetTester tester, {
  required String search,
  required String productId,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('product-typeahead-search')),
    search,
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('product-typeahead-$productId')));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  final submit = find.byKey(const ValueKey('delivery-submit'));
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

Future<void> _pumpRecord(
  WidgetTester tester,
  _Reader reader, {
  required TenantSupplierDeliveryWriter writer,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
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
        child: TenantSupplierRecordScreen(
          reader: reader,
          supplierId: 'sp_abc',
          deliveries: TenantSupplierDeliveryServices(
            writer: writer,
            productSearchReader: reader,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, Object?> _deliveryDocument({
  required String reference,
  bool complete = true,
}) => <String, Object?>{
  'tenantId': 'tenant-a',
  'supplierId': 'sp_abc',
  'supplierName': 'ABC Distributors',
  'reference': reference,
  'complete': complete,
  'occurredAt': DateTime.utc(2026, 9, 22, 7),
  'createdAt': DateTime.utc(2026, 9, 22, 7),
  'lines': <Map<String, Object?>>[
    <String, Object?>{
      'productId': 'prod-bread',
      'productName': 'White bread loaf',
      'quantity': 24,
      'unitCostMinor': 4550,
    },
    <String, Object?>{
      'productId': 'prod-milk',
      'productName': 'Milk 500ml',
      'quantity': 12,
      'unitCostMinor': null,
    },
  ],
};

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

final class _DeliveryWriter implements TenantSupplierDeliveryWriter {
  final List<TenantSupplierDeliveryIntent> received =
      <TenantSupplierDeliveryIntent>[];

  @override
  Future<TenantSupplierDeliveryWriteResult> receive(
    TenantSupplierDeliveryIntent intent,
  ) async {
    received.add(intent);
    return TenantSupplierDeliveryWriteResult.queued(<String>[
      for (final page in intent.pages()) page.operationId,
    ]);
  }
}

/// One supplier, two products, and whatever deliveries a test names.
final class _Reader implements TenantDataReader, TenantProductSearchReader {
  _Reader({this.deliveries = const <String, Map<String, Object?>>{}});

  final Map<String, Map<String, Object?>> deliveries;

  static const Map<String, Map<String, Object?>> _products =
      <String, Map<String, Object?>>{
        'prod-bread': <String, Object?>{
          'name': 'White bread loaf',
          'SKU': 'BR-1',
          'price': 65,
          'cost': 40,
          'quantity': 40,
          'categoryId': 'ct_bakery',
          'searchName': 'white bread loaf',
          'searchPrefixes': <String>['br', 'bre', 'brea', 'bread', 'wh', 'whi'],
        },
        'prod-milk': <String, Object?>{
          'name': 'Milk 500ml',
          'SKU': 'MK-1',
          'price': 50,
          'quantity': 5,
          'categoryId': 'ct_dairy',
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
    final Map<String, Map<String, Object?>> source;
    if (query.collectionPath.endsWith('/suppliers')) {
      source = const <String, Map<String, Object?>>{
        'sp_abc': <String, Object?>{'name': 'ABC Distributors', 'active': true},
      };
    } else if (query.collectionPath.endsWith('/supplier_deliveries')) {
      source = deliveries;
    } else {
      return const <TenantQueryDocumentSnapshot>[];
    }
    return <TenantQueryDocumentSnapshot>[
      for (final entry in source.entries)
        if (query.equalityFilters.entries.every(
          (filter) => entry.value[filter.key] == filter.value,
        ))
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/${entry.key}',
            data: entry.value,
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
