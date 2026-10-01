import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uzapay_pos/customers/customer.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';

/// The device's half of a customer: what it may send, how it finds one, and
/// that a customer added with no signal is found by the till's own search.
///
/// The rule that matters most here is parity with
/// `functions/src/operations/customers.ts`. A queued customer is confirmed by
/// reading back what it sent, and found offline by the prefixes it carries -
/// so a device that indexed a name differently from the server would hold a
/// customer it could neither find nor confirm.
void main() {
  group('search fields', () {
    test('match the server for the same customer, prefix for prefix', () {
      // Printed by `customerSearchFields('Jane  Wanjiku', '+254712345678')` in
      // the compiled functions on 2026-10-01.
      const server = <String>[
        '07', '071', '0712', '07123', '071234', '0712345', '07123456',
        '071234567', '0712345678', '25', '254', '2547', '25471', '254712',
        '2547123', '25471234', '254712345', '2547123456', '25471234567',
        '254712345678', '71', '712', '7123', '71234', '712345', '7123456',
        '71234567', '712345678', 'ja', 'jan', 'jane', 'jane ', 'jane w',
        'jane wa', 'jane wan', 'jane wanj', 'jane wanji', 'jane wanjik',
        'jane wanjiku', 'wa', 'wan', 'wanj', 'wanji', 'wanjik', 'wanjiku',
      ];

      final fields = tenantCustomerSearchFields(
        name: 'Jane  Wanjiku',
        phone: '+254712345678',
      );

      expect(fields.searchName, 'jane wanjiku');
      expect(fields.searchPrefixes, server);
    });

    test('a typed number is searched by its digits', () {
      expect(tenantCustomerSearchPrefix('0712 345'), '0712345');
      expect(tenantCustomerSearchPrefix('+254 712'), '254712');
      expect(tenantCustomerSearchPrefix('Jane W'), 'jane w');
      // The index starts at two characters, so one is nothing to search for.
      expect(tenantCustomerSearchPrefix('j'), isNull);
      expect(tenantCustomerSearchPrefix('   '), isNull);
    });
  });

  group('form fields', () {
    test('are normalized exactly as the server stores them', () {
      expect(
        normalizeCustomerField(TenantCustomerField.name, '  Jane   W '),
        'Jane W',
      );
      expect(
        normalizeCustomerField(TenantCustomerField.kraPin, ' a012345678z '),
        'A012345678Z',
      );
      expect(normalizeCustomerField(TenantCustomerField.phone, ''), isNull);
      expect(normalizeCustomerField(TenantCustomerField.email, ' '), isNull);
    });

    test('refuse what the server would refuse', () {
      for (final (field, value, code) in <(TenantCustomerField, String, String)>[
        (TenantCustomerField.name, '', 'invalid_customer_name'),
        (TenantCustomerField.name, 'x' * 121, 'invalid_customer_name'),
        // The form converts to E.164; a bare local number never reaches here.
        (TenantCustomerField.phone, '0712345678', 'invalid_customer_phone'),
        (TenantCustomerField.kraPin, '12345', 'invalid_customer_kra_pin'),
        (TenantCustomerField.email, 'jane', 'invalid_customer_email'),
      ]) {
        expect(
          () => normalizeCustomerField(field, value),
          throwsA(_code(code)),
          reason: '$field "$value"',
        );
      }
    });
  });

  group('creating', () {
    test('a cashier may add a customer, under an ID the server accepts', () {
      final intent = _repository(TenantRole.cashier).buildCreateIntent(
        draft: const TenantCustomerDraft(
          name: 'Jane Wanjiku',
          phone: '+254712345678',
          kraPin: 'a012345678z',
          whatsappOptIn: true,
        ),
        requestId: 'customer-request-0001',
      );

      expect(isTenantCustomerId(intent.customerId), isTrue);
      expect(intent.path, 'tenants/tenant-a/customers/${intent.customerId}');
      final document = intent.documentData();
      expect(document['name'], 'Jane Wanjiku');
      expect(document['kraPin'], 'A012345678Z');
      expect(document['whatsappOptIn'], isTrue);
      expect(document['active'], isTrue);
      expect(document['createdBy'], 'user-a');
      expect(document['searchPrefixes'], contains('0712'));
      expect(document.containsKey('email'), isFalse);
    });

    test('the same request always mints the same customer', () {
      String mint() => _repository()
          .buildCreateIntent(
            draft: const TenantCustomerDraft(name: 'Jane'),
            requestId: 'customer-request-0001',
          )
          .customerId;

      expect(mint(), mint());
    });

    test('says nothing about WhatsApp when the customer did not agree', () {
      final document = _repository()
          .buildCreateIntent(
            draft: const TenantCustomerDraft(
              name: 'Jane',
              phone: '+254712345678',
            ),
            requestId: 'customer-request-0001',
          )
          .documentData();

      expect(document.containsKey('whatsappOptIn'), isFalse);
    });

    test('consent cannot be recorded without a number', () {
      expect(
        () => _repository().buildCreateIntent(
          draft: const TenantCustomerDraft(name: 'Jane', whatsappOptIn: true),
          requestId: 'customer-request-0001',
        ),
        throwsA(_code('consent_needs_phone')),
      );
    });
  });

  group('correcting', () {
    test('a cashier may not correct a customer', () {
      expect(
        () => _repository(TenantRole.cashier).buildUpdateIntent(
          customer: _jane(),
          draft: const TenantCustomerDraft(name: 'Jane W'),
        ),
        throwsA(_code('customer_forbidden')),
      );
    });

    test('carries only what moves, and nothing is refused', () {
      expect(
        () => _repository().buildUpdateIntent(
          customer: _jane(),
          draft: TenantCustomerDraft.of(_jane()),
        ),
        throwsA(_code('customer_unchanged')),
      );

      final renamed = _repository()
          .buildUpdateIntent(
            customer: _jane(),
            draft: TenantCustomerDraft.of(
              _jane(),
            ).copyWithName('Jane Wanjiku Kamau'),
          )
          .documentData();
      expect(renamed['name'], 'Jane Wanjiku Kamau');
      expect(renamed.containsKey('phone'), isFalse);
      expect(renamed['searchPrefixes'], contains('kamau'));
    });

    test('a new number withdraws the consent given for the old one', () {
      final document = _repository()
          .buildUpdateIntent(
            customer: _jane(optedIn: true),
            draft: const TenantCustomerDraft(
              name: 'Jane',
              phone: '+254733333333',
            ),
          )
          .documentData();

      expect(document['phone'], '+254733333333');
      expect(document['whatsappOptIn'], isFalse);
    });

    test('a new number ticked again keeps consent, recorded afresh', () {
      final document = _repository()
          .buildUpdateIntent(
            customer: _jane(optedIn: true),
            draft: const TenantCustomerDraft(
              name: 'Jane',
              phone: '+254733333333',
              whatsappOptIn: true,
            ),
          )
          .documentData();

      expect(document['whatsappOptIn'], isTrue);
    });

    test('marks a customer inactive, and refuses marking them twice', () {
      final intent = _repository().buildStandingIntent(
        customer: _jane(),
        active: false,
      );
      expect(intent.documentData(), <String, Object?>{'active': false});
      expect(
        () => _repository().buildStandingIntent(
          customer: _jane(),
          active: true,
        ),
        throwsA(_code('customer_unchanged')),
      );
    });
  });

  group('reading', () {
    test('consent is true and nothing else', () {
      for (final value in <Object?>[null, false, 'true', 1]) {
        final customer = TenantCustomer.fromDocument(
          path: 'tenants/tenant-a/customers/cu_1',
          data: <String, Object?>{
            'name': 'Jane',
            'phone': '+254712345678',
            'whatsappOptIn': value,
          },
        );
        expect(customer.receivesWhatsapp, isFalse, reason: '$value');
      }
    });

    test('an inactive customer is not sent receipts', () {
      expect(_jane(optedIn: true).receivesWhatsapp, isTrue);
      expect(_jane(optedIn: true, active: false).receivesWhatsapp, isFalse);
    });

    test('the number is masked where somebody else may see it', () {
      expect(_jane().maskedPhone, '+254 ••• 678');
    });
  });

  group('offline', () {
    late Directory directory;
    late TenantPendingMutationStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('customer-queue-');
      Hive.init(directory.path);
      store = TenantPendingMutationStore.fromBox(
        await Hive.openBox<dynamic>('customer-queue-test'),
      );
    });

    tearDown(() async {
      await Hive.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('a customer added with no signal is found by name and number', () async {
      final intent = _repository(TenantRole.cashier).buildCreateIntent(
        draft: const TenantCustomerDraft(
          name: 'Jane Wanjiku',
          phone: '+254712345678',
        ),
        requestId: 'customer-request-0001',
      );
      await QueuedTenantCustomerWriter(
        store: store,
        currentUid: () => 'user-a',
      ).createCustomer(intent);

      final repository = TenantCustomerRepository(
        session: _session(TenantRole.cashier),
        reader: TenantPendingMutationOverlayReader(
          base: const _NoCustomers(),
          store: store,
          currentUid: () => 'user-a',
        ),
      );

      for (final typed in <String>['wanj', '0712 345', 'Jane']) {
        final page = await repository.search(search: typed);
        expect(page.customers.single.id, intent.customerId, reason: typed);
      }
      expect((await repository.search(search: 'otieno')).customers, isEmpty);
      expect(
        (await repository.holderOfPhone('+254712345678'))?.id,
        intent.customerId,
      );
    });

    test('is a callable, addressed to the customer', () {
      expect(
        tenantMutationIsCallable(TenantPendingMutationKind.customerCreate),
        isTrue,
      );
      expect(
        tenantMutationIsCallable(TenantPendingMutationKind.customerUpdate),
        isTrue,
      );
      expect(
        tenantMutationReadsBackOnLanding(
          TenantPendingMutationKind.customerCreate,
        ),
        isTrue,
      );
    });
  });
}

extension on TenantCustomerDraft {
  TenantCustomerDraft copyWithName(String name) => TenantCustomerDraft(
    name: name,
    phone: phone,
    email: email,
    kraPin: kraPin,
    notes: notes,
    whatsappOptIn: whatsappOptIn,
  );
}

TenantSession _session(TenantRole role) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

TenantCustomerRepository _repository([TenantRole role = TenantRole.owner]) =>
    TenantCustomerRepository(session: _session(role), reader: const _NoCustomers());

TenantCustomer _jane({bool optedIn = false, bool active = true}) =>
    TenantCustomer.fromDocument(
      path: 'tenants/tenant-a/customers/cu_jane',
      data: <String, Object?>{
        'name': 'Jane',
        'phone': '+254712345678',
        if (optedIn) 'whatsappOptIn': true,
        if (!active) 'active': false,
      },
    );

Matcher _code(String code) => isA<TenantCustomerException>().having(
  (error) => error.code,
  'code',
  code,
);

final class _NoCustomers
    implements TenantCacheReadable, TenantCustomerSearchReader {
  const _NoCustomers();

  @override
  TenantDataReader get cacheOnly => this;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantCustomers(
    TenantCustomerSearchQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
