import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/customers/customers.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/ui/tokens.dart';

import '../support/notices.dart';

/// The Customers route, from the home tile to a customer's record.
void main() {
  testWidgets('active customers are listed by name, with how to reach them', (
    tester,
  ) async {
    await _pump(tester, _Reader.seeded());

    expect(_names(tester), <String>['Jane Wanjiku', 'John Otieno']);
    // Consent is said in words beside the number, never by a colour alone.
    expect(
      find.text('+254 ••• 678 · WhatsApp receipts'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('customer-points-cu_jane')), findsOneWidget);

    await _choose(tester, 'customers-standing-filter', 'customers-standing-all');

    expect(_names(tester), <String>['Jane Wanjiku', 'John Otieno', 'Old Mary']);
    expect(
      find.byKey(const ValueKey('customer-inactive-badge-cu_mary')),
      findsOneWidget,
    );
  });

  testWidgets('a customer is found by the number a counter writes', (
    tester,
  ) async {
    await _pump(tester, _Reader.seeded());

    await tester.enterText(
      find.byKey(const ValueKey('customers-search')),
      '0712 345',
    );
    await tester.pump(AppMotion.standard.long.duration);
    await tester.pumpAndSettle();

    expect(_names(tester), <String>['Jane Wanjiku']);
  });

  testWidgets('a business with no customers is told what they are for', (
    tester,
  ) async {
    await _pump(tester, _Reader(const <String, Map<String, Object?>>{}));

    expect(find.byKey(const ValueKey('customers-empty')), findsOneWidget);
  });

  testWidgets('a customer is added with their consent, in the shop\'s country', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, _Reader.seeded(), writer: writer);

    await tester.tap(find.byKey(const ValueKey('customers-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('customer-form-name')),
      'Amina Hassan',
    );
    await tester.enterText(
      find.byKey(const ValueKey('phone-local-number')),
      '0722 111 222',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('customer-form-whatsapp-consent')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('customer-form-kraPin')),
      'p051234567q',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('customer-form-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('customer-form-submit')));
    await tester.pumpAndSettle();

    final created = writer.created.single.documentData();
    expect(created['name'], 'Amina Hassan');
    // A shop selling in shillings starts a number at +254.
    expect(created['phone'], '+254722111222');
    expect(created['whatsappOptIn'], isTrue);
    expect(created['kraPin'], 'P051234567Q');
    expect(snackNotice(tester).status, AppStatus.ok);
    expect(snackNotice(tester).message, contains('Amina Hassan added'));
  });

  testWidgets('a number another customer already holds is refused on the form', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, _Reader.seeded(), writer: writer);

    await tester.tap(find.byKey(const ValueKey('customers-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('customer-form-name')),
      'Someone Else',
    );
    await tester.enterText(
      find.byKey(const ValueKey('phone-local-number')),
      '0712345678',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('customer-form-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('customer-form-submit')));
    await tester.pumpAndSettle();

    expect(writer.created, isEmpty);
    expect(find.textContaining('already belongs to Jane Wanjiku'), findsOneWidget);
    // Choosing the holder instead is a till's offer, not the directory's.
    expect(
      find.byKey(const ValueKey('customer-form-choose-existing')),
      findsNothing,
    );
  });

  testWidgets('marking a customer inactive asks first, then says what it did', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, _Reader.seeded(), writer: writer);

    await tester.tap(find.byKey(const ValueKey('customer-actions-cu_john')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('customer-inactive-cu_john')));
    await tester.pumpAndSettle();
    expect(find.textContaining('stays on record'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('customer-inactive-confirm')));
    await tester.pumpAndSettle();

    expect(writer.updated.single.documentData(), <String, Object?>{
      'active': false,
    });
    expect(snackNotice(tester).message, contains('is inactive'));
  });

  testWidgets('a card offers Record a payment, which opens the payment', (
    tester,
  ) async {
    await _pump(
      tester,
      _Reader.seeded(),
      payments: CustomerPaymentServices(
        writer: _PaymentWriter(),
        shifts: const _NoShift(),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('customer-actions-cu_john')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('customer-record-payment-cu_john')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Record a payment'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('customer-payment-amount')),
      findsOneWidget,
    );
  });

  testWidgets('no payment is offered where this build cannot take one', (
    tester,
  ) async {
    await _pump(tester, _Reader.seeded());

    await tester.tap(find.byKey(const ValueKey('customer-actions-cu_john')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('customer-record-payment-cu_john')),
      findsNothing,
    );
  });

  testWidgets('a cashier is not offered the directory', (tester) async {
    await _pump(tester, _Reader.seeded(), role: TenantRole.cashier);

    expect(find.byKey(const ValueKey('customers')), findsNothing);
  });
}

List<String> _names(WidgetTester tester) => tester
    .widgetList<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('customer-name-'),
      ),
    )
    .map((text) => text.data!)
    .toList();

Future<void> _choose(WidgetTester tester, String select, String item) async {
  await tester.tap(find.byKey(ValueKey(select)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(item)).last);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  _Reader reader, {
  TenantCustomerWriter? writer,
  TenantRole role = TenantRole.manager,
  CustomerPaymentServices? payments,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TenantSessionController()
    ..open(uid: 'user-a', membership: _membership(role));
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantCustomersScreen(
          reader: reader,
          writer: writer ?? _Writer(),
          payments: payments,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _PaymentWriter implements TenantCustomerPaymentWriter {
  @override
  Future<void> recordPayment(TenantCustomerPaymentIntent intent) async {}
}

final class _NoShift implements CheckoutShiftBinder {
  const _NoShift();

  @override
  Future<CheckoutShiftBinding> bindCheckoutShift(TenantSession session) async =>
      const CheckoutShiftBinding.refused('no_open_shift');
}

TenantMembership _membership(TenantRole role) => TenantMembership(
  tenantId: 'tenant-a',
  tenantName: 'tenant-a',
  tenantSlug: 'tenant-a',
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

final class _Writer implements TenantCustomerWriter {
  final List<TenantCustomerCreateIntent> created =
      <TenantCustomerCreateIntent>[];
  final List<TenantCustomerUpdateIntent> updated =
      <TenantCustomerUpdateIntent>[];

  @override
  Future<TenantCustomerWriteResult> createCustomer(
    TenantCustomerCreateIntent intent,
  ) async {
    created.add(intent);
    return TenantCustomerWriteResult.queued(
      'customer-create-${intent.customerId}',
    );
  }

  @override
  Future<TenantCustomerWriteResult> updateCustomer(
    TenantCustomerUpdateIntent intent,
  ) async {
    updated.add(intent);
    return TenantCustomerWriteResult.queued(intent.operationId);
  }
}

Map<String, Object?> _customer(
  String name, {
  String? phone,
  bool optedIn = false,
  bool active = true,
  int points = 0,
}) {
  final search = tenantCustomerSearchFields(name: name, phone: phone);
  return <String, Object?>{
    'name': name,
    if (phone != null) 'phone': phone,
    if (optedIn) 'whatsappOptIn': true,
    'active': active,
    if (points > 0) 'points': points,
    'searchName': search.searchName,
    'searchPrefixes': search.searchPrefixes,
  };
}

/// A server that answers customer searches the way the indexed query does.
final class _Reader implements TenantDataReader, TenantCustomerSearchReader {
  _Reader(this.customers);

  factory _Reader.seeded() => _Reader(<String, Map<String, Object?>>{
    'cu_jane': _customer(
      'Jane Wanjiku',
      phone: '+254712345678',
      optedIn: true,
      points: 12,
    ),
    'cu_john': _customer('John Otieno', phone: '+254700000001'),
    'cu_mary': _customer('Old Mary', active: false),
  });

  final Map<String, Map<String, Object?>> customers;

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
  ) async => const <TenantQueryDocumentSnapshot>[];

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantCustomers(
    TenantCustomerSearchQuery query,
  ) async {
    final rows = <TenantQueryDocumentSnapshot>[
      for (final entry in customers.entries)
        if ((query.active == null ||
                (entry.value['active'] != false) == query.active) &&
            (query.searchPrefix == null ||
                (entry.value['searchPrefixes']! as List<String>).contains(
                  query.searchPrefix,
                )))
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/${entry.key}',
            data: entry.value,
          ),
    ]..sort(
        (left, right) => (left.data['searchName']! as String).compareTo(
          right.data['searchName']! as String,
        ),
      );
    return rows.take(query.limit).toList();
  }
}
