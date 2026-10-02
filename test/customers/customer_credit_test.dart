import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/customers/customers.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';

/// A customer's account on the device: what they owe, the repayment a cashier
/// takes, the statement, and who owes.
void main() {
  group('a customer\'s account', () {
    test('reads the limit, the balance and how long it has been owed', () {
      final jane = _customer(<String, Object?>{
        'creditLimitMinor': 500000,
        'balanceMinor': 120000,
        'owingSince': DateTime.utc(2026, 9, 20),
      });
      expect(jane.allowsCredit, isTrue);
      expect(jane.owedMinor, 120000);
      expect(jane.creditAvailableMinor, 380000);
      expect(jane.overLimit, isFalse);
      expect(jane.owingSince, DateTime.utc(2026, 9, 20));

      // Paid ahead: owes nothing, and the shop owes them.
      final ahead = _customer(<String, Object?>{'balanceMinor': -5000});
      expect(ahead.owedMinor, 0);

      // **Any named customer may buy on credit, with no limit at all**, and
      // owing without one is not being over anything.
      final plain = _customer(<String, Object?>{'balanceMinor': 100});
      expect(plain.allowsCredit, isTrue);
      expect(plain.overLimit, isFalse);
      // Blocked by a manager, or inactive: offered no credit at the till.
      expect(
        _customer(<String, Object?>{'creditBlocked': true}).allowsCredit,
        isFalse,
      );
      expect(
        _customer(<String, Object?>{'active': false}).allowsCredit,
        isFalse,
      );
    });

    test('blocking credit is a manager\'s switch, sent only when it moves', () {
      final manager = TenantCustomerRepository(
        session: _session(TenantRole.manager),
        reader: _Reader(),
      );
      final jane = _customer(const <String, Object?>{});
      final blocked = manager.buildUpdateIntent(
        customer: jane,
        draft: const TenantCustomerDraft(
          name: 'Jane Wanjiku',
          creditAllowed: false,
        ),
      );
      expect(blocked.documentData()['creditBlocked'], isTrue);

      final again = manager.buildUpdateIntent(
        customer: _customer(const <String, Object?>{'creditBlocked': true}),
        draft: const TenantCustomerDraft(name: 'Jane Wanjiku'),
      );
      expect(again.documentData()['creditBlocked'], isFalse);

      // A cashier may add a customer, never blocked from credit.
      expect(
        () => TenantCustomerRepository(
          session: _session(TenantRole.cashier),
          reader: _Reader(),
        ).buildCreateIntent(
          draft: const TenantCustomerDraft(name: 'Jane', creditAllowed: false),
          requestId: 'customer-request-0003',
        ),
        throwsA(isA<TenantCustomerException>()),
      );
    });

    test('a limit is given by a manager, and zero takes it away', () {
      final manager = TenantCustomerRepository(
        session: _session(TenantRole.manager),
        reader: _Reader(),
      );
      final created = manager.buildCreateIntent(
        draft: const TenantCustomerDraft(name: 'Jane', creditLimitMinor: 500000),
        requestId: 'customer-request-0001',
      );
      expect(created.documentData()['creditLimitMinor'], 500000);

      final jane = _customer(<String, Object?>{'creditLimitMinor': 500000});
      final cleared = manager.buildUpdateIntent(
        customer: jane,
        draft: const TenantCustomerDraft(name: 'Jane Wanjiku', creditLimitMinor: 0),
      );
      expect(cleared.documentData()['creditLimitMinor'], isNull);
      expect(cleared.documentData().containsKey('creditLimitMinor'), isTrue);

      final cashier = TenantCustomerRepository(
        session: _session(TenantRole.cashier),
        reader: _Reader(),
      );
      expect(
        () => cashier.buildCreateIntent(
          draft: const TenantCustomerDraft(
            name: 'Jane',
            creditLimitMinor: 500000,
          ),
          requestId: 'customer-request-0002',
        ),
        throwsA(
          isA<TenantCustomerException>().having(
            (error) => error.code,
            'code',
            'customer_forbidden',
          ),
        ),
      );
    });
  });

  group('a repayment', () {
    late Directory directory;
    late TenantPendingMutationStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('customer-payment-');
      Hive.init(directory.path);
      store = TenantPendingMutationStore.fromBox(
        await Hive.openBox<dynamic>('customer-payment-test'),
      );
    });

    tearDown(() async {
      await Hive.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('is queued into the cashier\'s own shift, as the callable asks', () async {
      final intent = TenantCustomerPaymentIntent.build(
        session: _session(TenantRole.cashier),
        customer: _customer(<String, Object?>{'balanceMinor': 70000}),
        amountMinor: 50000,
        tender: CheckoutTender.mpesa,
        shift: _shift(),
        requestId: 'payment-request-0001',
      );
      expect(intent.paymentId, matches(RegExp(r'^cp_[0-9a-f]{40}$')));
      expect(intent.path, 'tenants/tenant-a/customer_payments/${intent.paymentId}');
      expect(intent.callablePayload(), <String, Object?>{
        'tenantId': 'tenant-a',
        'paymentId': intent.paymentId,
        'customerId': _jane,
        'amountMinor': 50000,
        'tender': 'mpesa',
        'shiftId': 'shift-a',
      });

      await QueuedTenantCustomerPaymentWriter(
        store: store,
        currentUid: () => 'user-a',
      ).recordPayment(intent);
      final record = (await store.recordsForSession(
        uid: 'user-a',
        tenantId: 'tenant-a',
      )).single;
      expect(record.kind, TenantPendingMutationKind.customerPayment);
      expect(record.targetPath, intent.path);
      expect(record.payload['businessDate'], '2026-10-01');
      expect(record.payload['recordedBy'], 'user-a');
      expect(record.payload.containsKey('customerName'), isFalse);
      expect(tenantMutationIsCallable(record.kind), isTrue);
      expect(tenantMutationReadsBackOnLanding(record.kind), isTrue);
      // A customer added at the till a moment before is sent first.
      expect(tenantMutationDependencies(record), <String>[
        'tenants/tenant-a/customers/$_jane',
      ]);
    });

    test('is refused into another cashier\'s shift, or for nothing', () {
      expect(
        () => TenantCustomerPaymentIntent.build(
          session: _session(TenantRole.cashier),
          customer: _customer(const <String, Object?>{}),
          amountMinor: 100,
          tender: CheckoutTender.cash,
          shift: _shift(uid: 'user-b'),
        ),
        throwsA(isA<TenantCustomerPaymentException>()),
      );
      expect(
        () => TenantCustomerPaymentIntent.build(
          session: _session(TenantRole.cashier),
          customer: _customer(const <String, Object?>{}),
          amountMinor: 0,
          tender: CheckoutTender.cash,
          shift: _shift(),
        ),
        throwsA(
          isA<TenantCustomerPaymentException>().having(
            (error) => error.code,
            'code',
            'invalid_payment_amount',
          ),
        ),
      );
    });
  });

  group('the statement and who owes', () {
    test('lists only what moved the balance, newest first', () async {
      final reader = _Reader(
        activity: <TenantQueryDocumentSnapshot>[
          _entry('payment-cp_1', 12, <String, Object?>{
            'kind': 'payment',
            'credit': true,
            'tender': 'mpesa',
            'balanceChangeMinor': -50000,
            'balanceAfterMinor': 20000,
          }),
          _entry('sale-points-only', 11, <String, Object?>{
            'kind': 'sale',
            'points': 4,
          }),
          _entry('co-1', 10, <String, Object?>{
            'kind': 'sale',
            'credit': true,
            'receiptNumber': 'CT-A7F-20261001-0002',
            'creditPaidTender': 'cash',
            'balanceChangeMinor': 70000,
            'balanceAfterMinor': 70000,
            'overLimit': true,
          }),
        ],
      );
      final page = await TenantCustomerCreditRepository(
        session: _session(TenantRole.manager),
        reader: reader,
      ).loadStatement(_jane);

      expect(page.entries.map((entry) => entry.kind), <TenantCustomerLedgerKind>[
        TenantCustomerLedgerKind.payment,
        TenantCustomerLedgerKind.sale,
      ]);
      expect(page.entries.first.tender, CheckoutTender.mpesa);
      expect(page.entries.last.overLimit, isTrue);
      expect(page.entries.last.receiptNumber, 'CT-A7F-20261001-0002');
      final query = reader.queries.single;
      expect(query.collectionPath, 'tenants/tenant-a/customers/$_jane/activity');
      expect(query.equalityFilters, <String, Object?>{'credit': true});
      expect(query.order, TenantCollectionOrder.createdAt);
      expect(query.descending, isTrue);
    });

    test('who owes is everyone owing, biggest first', () async {
      final reader = _Reader(
        customers: <TenantQueryDocumentSnapshot>[
          _customerSnapshot('cu_${'1' * 40}', 'Asha', 2000),
          _customerSnapshot('cu_${'2' * 40}', 'Baraka', 90000),
          _customerSnapshot('cu_${'3' * 40}', 'Chao', 0),
        ],
      );
      final owing = await TenantCustomerCreditRepository(
        session: _session(TenantRole.owner),
        reader: reader,
      ).loadOwing();
      expect(owing.map((customer) => customer.name), <String>[
        'Baraka',
        'Asha',
      ]);
      expect(reader.queries.single.equalityFilters, <String, Object?>{
        'owing': true,
      });
    });

    test('a cashier reads no statement', () {
      expect(
        () => TenantCustomerCreditRepository(
          session: _session(TenantRole.cashier),
          reader: _Reader(),
        ).loadStatement(_jane),
        throwsA(isA<TenantCustomerPaymentException>()),
      );
    });
  });

  group('the record', () {
    testWidgets('states what they owe, against their limit, in words', (
      tester,
    ) async {
      await _pumpRecord(
        tester,
        _Reader(
          janeData: <String, Object?>{
            'creditLimitMinor': 100000,
            'balanceMinor': 120000,
          },
        ),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('customer-record-balance')))
            .data,
        'KES 1200',
      );
      expect(
        find.byKey(const ValueKey('customer-record-over-limit')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('customer-statement')), findsOneWidget);
    });

    testWidgets('a payment with no shift open says so, and records nothing', (
      tester,
    ) async {
      final writer = _PaymentWriter();
      await _pumpRecord(
        tester,
        _Reader(
          janeData: <String, Object?>{
            'creditLimitMinor': 100000,
            'balanceMinor': 70000,
          },
        ),
        payments: CustomerPaymentServices(
          writer: writer,
          shifts: const _Binder(null),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('customer-record-take-payment')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('customer-payment-cash')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('customer-payment-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Open a shift before selling.'), findsOneWidget);
      expect(writer.recorded, isEmpty);
    });

    testWidgets('a payment into an open shift is queued for what they owe', (
      tester,
    ) async {
      final writer = _PaymentWriter();
      await _pumpRecord(
        tester,
        _Reader(
          janeData: <String, Object?>{
            'creditLimitMinor': 100000,
            'balanceMinor': 70000,
          },
        ),
        payments: CustomerPaymentServices(
          writer: writer,
          shifts: _Binder(_shift(uid: 'user-a')),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('customer-record-take-payment')),
      );
      await tester.pumpAndSettle();
      // The amount starts at what they owe; most repayments settle it.
      expect(find.text('700'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('customer-payment-mpesa')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('customer-payment-confirm')));
      await tester.pumpAndSettle();

      final intent = writer.recorded.single;
      expect(intent.amountMinor, 70000);
      expect(intent.tender, CheckoutTender.mpesa);
      expect(intent.shiftId, 'shift-a');
      expect(find.textContaining('recorded in your shift'), findsOneWidget);
    });
  });
}

const String _jane = 'cu_0123456789abcdef0123456789abcdef01234567';

TenantSession _session(TenantRole role, {String uid = 'user-a'}) =>
    TenantSession.active(uid: uid, tenantId: 'tenant-a', role: role);

TenantCustomer _customer(Map<String, Object?> data) => TenantCustomer.fromDocument(
  path: 'tenants/tenant-a/customers/$_jane',
  data: <String, Object?>{'name': 'Jane Wanjiku', 'active': true, ...data},
);

CheckoutShiftAttribution _shift({String uid = 'user-a'}) =>
    CheckoutShiftAttribution(
      uid: uid,
      tenantId: 'tenant-a',
      shiftId: 'shift-a',
      deviceId: 'dev-0123456789abcdef0123456789abcdef',
      businessDate: '2026-10-01',
    );

TenantQueryDocumentSnapshot _entry(
  String id,
  int hour,
  Map<String, Object?> data,
) => TenantQueryDocumentSnapshot(
  path: 'tenants/tenant-a/customers/$_jane/activity/$id',
  data: <String, Object?>{...data, 'createdAt': DateTime.utc(2026, 10, 1, hour)},
);

TenantQueryDocumentSnapshot _customerSnapshot(
  String id,
  String name,
  int balance,
) => TenantQueryDocumentSnapshot(
  path: 'tenants/tenant-a/customers/$id',
  data: <String, Object?>{
    'name': name,
    'active': true,
    'balanceMinor': balance,
    'owing': balance > 0,
  },
);

Future<void> _pumpRecord(
  WidgetTester tester,
  _Reader reader, {
  CustomerPaymentServices? payments,
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
          customerId: _jane,
          currency: 'KES',
          payments: payments,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _Reader implements TenantDataReader {
  _Reader({
    this.janeData = const <String, Object?>{},
    this.activity = const <TenantQueryDocumentSnapshot>[],
    this.customers = const <TenantQueryDocumentSnapshot>[],
  });

  final Map<String, Object?> janeData;
  final List<TenantQueryDocumentSnapshot> activity;
  final List<TenantQueryDocumentSnapshot> customers;
  final List<TenantCollectionQuery> queries = <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (path == 'tenants/tenant-a/customers/$_jane') {
      return TenantDocumentSnapshot(
        path: path,
        data: <String, Object?>{
          'name': 'Jane Wanjiku',
          'active': true,
          ...janeData,
        },
      );
    }
    return null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    queries.add(query);
    if (query.collectionPath.endsWith('/activity')) return activity;
    if (query.collectionPath == 'tenants/tenant-a/customers') return customers;
    return const <TenantQueryDocumentSnapshot>[];
  }
}

final class _PaymentWriter implements TenantCustomerPaymentWriter {
  final List<TenantCustomerPaymentIntent> recorded =
      <TenantCustomerPaymentIntent>[];

  @override
  Future<void> recordPayment(TenantCustomerPaymentIntent intent) async {
    recorded.add(intent);
  }
}

final class _Binder implements CheckoutShiftBinder {
  const _Binder(this.attribution);

  final CheckoutShiftAttribution? attribution;

  @override
  Future<CheckoutShiftBinding> bindCheckoutShift(TenantSession session) async {
    final bound = attribution;
    return bound == null
        ? const CheckoutShiftBinding.refused('no_open_shift')
        : CheckoutShiftBinding.bound(bound);
  }
}
