import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/customers/customers.dart';
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
    // Nobody has bought anything yet, which is a state and not a failure.
    expect(
      find.byKey(const ValueKey('customer-purchases-empty')),
      findsOneWidget,
    );
  });

  testWidgets('a history that cannot be read costs that section only', (
    tester,
  ) async {
    await _pump(tester, const _Reader(failSales: true));

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
  const _Reader({this.failSales = false});

  final bool failSales;

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
    return const <TenantQueryDocumentSnapshot>[];
  }
}

/// Shaped as a minted customer ID, which a purchase history requires.
const String _jane = 'cu_0123456789abcdef0123456789abcdef01234567';
