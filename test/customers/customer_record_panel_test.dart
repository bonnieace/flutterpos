import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/customers/customers.dart';
import 'package:uzapay_pos/sales/sales.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';

/// One customer's record: who they are, how their receipts reach them, and what
/// they bought - each section read on its own.
void main() {
  testWidgets('states the customer, their consent in words, and their points', (
    tester,
  ) async {
    await _pump(tester, const _Reader());

    expect(find.text('Jane Wanjiku'), findsWidgets);
    expect(find.text('+254712345678'), findsOneWidget);
    expect(
      find.text('Agreed. Their receipts can go to this number.'),
      findsOneWidget,
    );
    expect(find.text('A012345678Z'), findsOneWidget);
    final points = tester.widget<Text>(
      find.byKey(const ValueKey('customer-record-points')),
    );
    expect(points.data, '12');
    // The statement is the first tab; purchases are the second.
    expect(find.byKey(const ValueKey('customer-statement')), findsOneWidget);
    await _openPurchases(tester);
    // Nobody has bought anything yet, which is a state and not a failure.
    expect(
      find.byKey(const ValueKey('customer-purchases-empty')),
      findsOneWidget,
    );
  });

  testWidgets('a purchase is drawn with the Sales report card', (tester) async {
    await _pump(tester, const _Reader(withSale: true));
    await _openPurchases(tester);

    expect(find.byType(TenantSaleCard), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-purchase-co-1')), findsOneWidget);
    // A card with no actions draws no menu.
    expect(find.byKey(const ValueKey('sales-actions-co-1')), findsNothing);
  });

  testWidgets('a history that cannot be read costs that section only', (
    tester,
  ) async {
    await _pump(tester, const _Reader(failSales: true));
    await _openPurchases(tester);

    expect(
      find.byKey(const ValueKey('customer-purchases-failure')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('customer-record-summary')),
      findsOneWidget,
    );
  });

  testWidgets('a customer this business does not hold is said, not guessed', (
    tester,
  ) async {
    await _pump(tester, const _Reader(), customerId: 'cu_missing');

    expect(
      find.byKey(const ValueKey('customer-record-missing')),
      findsOneWidget,
    );
  });
}

Future<void> _openPurchases(WidgetTester tester) async {
  await tester.tap(find.text('Purchases'));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  _Reader reader, {
  String customerId = _jane,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TenantSessionController()
    ..open(
      uid: 'user-a',
      membership: TenantMembership(
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
      ),
    );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantCustomerRecordScreen(
          reader: reader,
          customerId: customerId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _Reader implements TenantDataReader {
  const _Reader({this.failSales = false, this.withSale = false});

  final bool failSales;
  final bool withSale;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (path == 'tenants/tenant-a/customers/$_jane') {
      return TenantDocumentSnapshot(
        path: path,
        data: const <String, Object?>{
          'name': 'Jane Wanjiku',
          'phone': '+254712345678',
          'whatsappOptIn': true,
          'kraPin': 'A012345678Z',
          'active': true,
          'points': 12,
        },
      );
    }
    return null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    if (failSales && query.collectionPath.endsWith('/sales')) {
      throw StateError('index still building');
    }
    if (withSale && query.collectionPath.endsWith('/sales')) {
      return <TenantQueryDocumentSnapshot>[
        TenantQueryDocumentSnapshot(
          path: '${query.collectionPath}/co-1',
          data: _sale,
        ),
      ];
    }
    return const <TenantQueryDocumentSnapshot>[];
  }
}

/// Shaped as a minted customer ID, which a purchase history requires.
const String _jane = 'cu_0123456789abcdef0123456789abcdef01234567';

const String _device = 'dev-0123456789abcdef0123456789abcdef';

final Map<String, Object?> _sale = <String, Object?>{
  'checkoutId': 'co-1',
  'tenantId': 'tenant-a',
  'soldById': 'user-a',
  'payloadHash': 'a' * 64,
  'payloadSchemaVersion': 2,
  'currency': 'KES',
  'businessDate': '2026-10-01',
  'clientCreatedAtMs': 1790000000000,
  'shiftId': 'shift-a',
  'deviceId': _device,
  'receiptNumber': formatCheckoutReceiptNumber(
    deviceId: _device,
    businessDate: '2026-10-01',
    sequence: 1,
  ),
  'receiptSequence': 1,
  'items': <Object?>[
    <String, Object?>{
      'productId': 'product-1',
      'name': 'Tusker',
      'quantity': 2,
      'unitPriceMinor': 500,
      'unitPrice': 5.0,
      'lineTotalMinor': 1000,
      'lineTotal': 10.0,
    },
  ],
  'subtotalMinor': 1000,
  'subtotal': 10.0,
  'discountMinor': 0,
  'discount': 0.0,
  'totalMinor': 1000,
  'total': 10.0,
  'tender': 'cash',
  'customerId': _jane,
  'customerName': 'Jane Wanjiku',
};
