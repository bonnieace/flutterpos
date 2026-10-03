import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uzapay_pos/checkout/checkout_configuration_writer.dart';
import 'package:uzapay_pos/customers/customers.dart';
import 'package:uzapay_pos/email_receipts/email_receipts.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/choice.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/whatsapp/whatsapp.dart';

import '../support/notices.dart';

/// The device's half of email receipts: what a business has chosen, a
/// cashier's request to send one, a customer's consent, and the screen an
/// owner sets it up on.
void main() {
  group('settings', () {
    test('a business that chose nothing sends nothing', () {
      expect(TenantEmailReceiptSettings.off.emailEnabled, isFalse);
      expect(
        () => TenantEmailReceiptSettings.fromMap(const <String, Object?>{}),
        throwsFormatException,
      );
      final odd = TenantEmailReceiptSettings.fromMap(const <String, Object?>{
        'emailEnabled': true,
        'mode': 'sometimes',
      });
      // Anything unrecognised reads as the cautious choice, as on the server.
      expect(odd.mode, EReceiptMode.manual);
      expect(odd.sendsAutomatically, isFalse);
      expect(odd.offersManualSend, isTrue);
    });

    test('a refusal says whose problem it was, in words', () {
      String? reasonFor(String reason) =>
          TenantEmailReceiptDelivery.fromSnapshot(
            TenantQueryDocumentSnapshot(
              path: 'tenants/t/email_receipt_deliveries/ed_1',
              data: <String, Object?>{'status': 'failed', 'reason': reason},
            ),
          ).reasonText;

      expect(reasonFor('hard_bounce'), 'The address does not accept mail.');
      expect(reasonFor('opted_out'), 'The customer stopped email receipts.');
      expect(reasonFor('undeliverable'), contains('bounced before'));
      expect(reasonFor('something_new'), 'Not delivered.');
    });
  });

  group('a request to send one', () {
    test('is addressed to the record the server will write', () {
      // Printed by `emailReceiptDeliveryId('tenant-a', 'co-1',
      // 'jane@example.com', 'email-receipt-request-0001')` in the compiled
      // functions on 2026-10-03.
      expect(
        emailReceiptDeliveryId(
          tenantId: 'tenant-a',
          saleId: 'co-1',
          email: 'jane@example.com',
          requestId: 'email-receipt-request-0001',
        ),
        'ed_ad4c7a71978b56faba5a724cbaa0ceee9265bfa0',
      );
      // Typed with capitals and spaces, it is still the same address - and so
      // the same record.
      final intent = TenantEmailReceiptIntent.build(
        session: _session(TenantRole.cashier),
        saleId: 'co-1',
        email: '  Jane@Example.COM ',
        requestId: 'email-receipt-request-0001',
      );
      expect(intent.email, 'jane@example.com');
      expect(
        intent.path,
        'tenants/tenant-a/email_receipt_deliveries/'
        'ed_ad4c7a71978b56faba5a724cbaa0ceee9265bfa0',
      );
    });

    test('is refused when the address is not one', () {
      for (final typed in <String>['jane', 'jane@example', 'a b@c.d', '']) {
        expect(
          () => TenantEmailReceiptIntent.build(
            session: _session(TenantRole.cashier),
            saleId: 'co-1',
            email: typed,
          ),
          throwsA(
            isA<TenantEmailReceiptException>().having(
              (error) => error.code,
              'code',
              'invalid_email',
            ),
          ),
          reason: typed,
        );
      }
    });

    late Directory directory;
    late TenantPendingMutationStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('email-queue-');
      Hive.init(directory.path);
      store = TenantPendingMutationStore.fromBox(
        await Hive.openBox<dynamic>('email-queue-test'),
      );
    });

    tearDown(() async {
      await Hive.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test(
      'is queued as the callable request, and settled by sending again',
      () async {
        final intent = TenantEmailReceiptIntent.build(
          session: _session(TenantRole.cashier),
          saleId: 'co-1',
          email: 'jane@example.com',
          customerName: 'Jane',
          requestId: 'email-receipt-request-0001',
        );
        await QueuedTenantEmailReceiptWriter(
          store: store,
          currentUid: () => 'user-a',
        ).send(intent);

        final record = (await store.recordsForSession(
          uid: 'user-a',
          tenantId: 'tenant-a',
        )).single;
        expect(record.kind, TenantPendingMutationKind.emailReceiptRequest);
        expect(record.targetPath, intent.path);
        expect(record.payload, <String, Object?>{
          'tenantId': 'tenant-a',
          'saleId': 'co-1',
          'email': 'jane@example.com',
          'requestId': 'email-receipt-request-0001',
          'customerName': 'Jane',
        });
        expect(tenantMutationIsCallable(record.kind), isTrue);
        expect(tenantMutationResendConfirms(record.kind), isTrue);

        // Drawn for the Email screen without the address in the clear.
        final drawn = await TenantPendingMutationOverlayReader(
          base: const _Nothing(),
          store: store,
          currentUid: () => 'user-a',
        ).getDocument(intent.path);
        expect(drawn!.data['status'], 'queued');
        expect(drawn.data['emailMasked'], 'j•••@example.com');
        expect(drawn.data.values.contains('jane@example.com'), isFalse);
      },
    );
  });

  group('a customer\'s consent', () {
    TenantCustomer customer(Map<String, Object?> data) =>
        TenantCustomer.fromDocument(
          path: 'tenants/tenant-a/customers/cu_jane',
          data: <String, Object?>{'name': 'Jane', 'active': true, ...data},
        );

    TenantCustomerRepository repository() => TenantCustomerRepository(
      session: _session(TenantRole.manager),
      reader: const _Nothing(),
    );

    test('is a true and nothing else, and needs an address', () {
      expect(customer(const <String, Object?>{}).receivesEmail, isFalse);
      expect(
        customer(const <String, Object?>{'emailOptIn': true}).receivesEmail,
        isFalse,
      );
      expect(
        customer(const <String, Object?>{
          'email': 'jane@example.com',
          'emailOptIn': 'yes',
        }).receivesEmail,
        isFalse,
      );
      expect(
        customer(const <String, Object?>{
          'email': 'jane@example.com',
          'emailOptIn': true,
        }).receivesEmail,
        isTrue,
      );
      expect(
        () => repository().buildCreateIntent(
          draft: const TenantCustomerDraft(name: 'Jane', emailOptIn: true),
          requestId: 'customer-request-0001',
        ),
        throwsA(
          isA<TenantCustomerException>().having(
            (error) => error.code,
            'code',
            'consent_needs_email',
          ),
        ),
      );
    });

    test('is recorded with a new customer and sent with the document', () {
      final intent = repository().buildCreateIntent(
        draft: const TenantCustomerDraft(
          name: 'Jane',
          email: 'jane@example.com',
          emailOptIn: true,
        ),
        requestId: 'customer-request-0001',
      );
      expect(intent.documentData()['emailOptIn'], isTrue);
      expect(intent.documentData().containsKey('whatsappOptIn'), isFalse);
    });

    test('is withdrawn when the address changes, unless given again', () {
      final agreed = customer(const <String, Object?>{
        'email': 'jane@example.com',
        'emailOptIn': true,
      });
      final moved = repository().buildUpdateIntent(
        customer: agreed,
        draft: TenantCustomerDraft.of(agreed).copyEmail('jane@work.example'),
      );
      // The form keeps the tick, and a new address still asks again: the
      // server withdraws a consent the correction does not restate.
      expect(moved.documentData()['emailOptIn'], isTrue);

      final withdrawn = repository().buildUpdateIntent(
        customer: agreed,
        draft: TenantCustomerDraft.of(
          agreed,
        ).copyEmail('jane@example.com', emailOptIn: false),
      );
      expect(withdrawn.documentData(), containsPair('emailOptIn', false));
      expect(withdrawn.documentData().containsKey('email'), isFalse);
    });
  });

  group('the Email screen', () {
    testWidgets(
      'turning receipts on publishes the timing to its own document',
      (tester) async {
        final writer = _Writer();
        await _pump(tester, const _Reader(), writer: writer);

        final toggle = find.byKey(const ValueKey('email-receipts-enabled'));
        expect(tester.widget<AppSwitchRow>(toggle).value, isFalse);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('email-receipts-mode-automatic')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Mama Njeri Shop via UzaPay'), findsOneWidget);
        expect(
          find.text('Receipt JOHN-CT-7F2-001 from Mama Njeri Shop'),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('email-receipts-save')),
        );
        await tester.tap(find.byKey(const ValueKey('email-receipts-save')));
        await tester.pumpAndSettle();

        // Not the WhatsApp document, which that screen writes whole.
        expect(writer.path, 'tenants/tenant-a/configuration/email_receipts');
        expect(writer.data?['emailEnabled'], isTrue);
        expect(writer.data?['mode'], 'automatic');
        expect(writer.data?.containsKey('whatsappEnabled'), isFalse);
        expect(snackNotice(tester).message, contains('Saved'));
      },
    );

    testWidgets('lists recent receipts with what became of each, in words', (
      tester,
    ) async {
      await _pump(tester, const _Reader(withDeliveries: true));
      expect(find.text('Delivered'), findsNothing);
      await tester.tap(find.text('Sent receipts'));
      await tester.pumpAndSettle();

      expect(find.text('Delivered'), findsOneWidget);
      expect(find.text('JOHN-CT-7F2-001 · Jane'), findsOneWidget);
      expect(find.text('Not delivered'), findsOneWidget);
      expect(find.text('The address does not accept mail.'), findsOneWidget);
      // The masked address stands in for a walk-in's name.
      expect(find.text('w•••@example.com'), findsOneWidget);
    });

    testWidgets('a manager is told it is not theirs to decide', (tester) async {
      await _pump(tester, const _Reader(), role: TenantRole.manager);

      expect(
        find.textContaining('Only an owner or administrator'),
        findsOneWidget,
      );
    });
  });

  group('the send sheet', () {
    testWidgets('opens on the customer\'s address and queues the receipt', (
      tester,
    ) async {
      final writer = _ReceiptWriter();
      AppNotice? notice;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  notice = await showSendEmailReceiptSheet(
                    context,
                    session: _session(TenantRole.cashier),
                    writer: writer,
                    saleId: 'co-1',
                    receiptLabel: 'JOHN-CT-7F2-001',
                    customerName: 'Jane',
                    customerEmail: 'jane@example.com',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('jane@example.com'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('send-email-receipt-submit')));
      await tester.pumpAndSettle();

      expect(writer.sent.single.email, 'jane@example.com');
      expect(writer.sent.single.customerName, 'Jane');
      // The notice masks the address: the next customer may be reading it.
      expect(notice?.message, contains('j•••@example.com'));
      expect(notice?.message, isNot(contains('jane@example.com')));
    });

    testWidgets('refuses an address mail cannot reach, and sends nothing', (
      tester,
    ) async {
      final writer = _ReceiptWriter();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSendEmailReceiptSheet(
                  context,
                  session: _session(TenantRole.cashier),
                  writer: writer,
                  saleId: 'co-1',
                  receiptLabel: 'JOHN-CT-7F2-001',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('send-email-receipt-address')),
        'jane@example',
      );
      await tester.tap(find.byKey(const ValueKey('send-email-receipt-submit')));
      await tester.pumpAndSettle();

      expect(
        find.text('That email address is not one mail can reach.'),
        findsOneWidget,
      );
      expect(writer.sent, isEmpty);
    });
  });
}

extension on TenantCustomerDraft {
  /// This draft with another address, as the form would hand it over.
  TenantCustomerDraft copyEmail(String email, {bool? emailOptIn}) =>
      TenantCustomerDraft(
        name: name,
        phone: phone,
        email: email,
        kraPin: kraPin,
        notes: notes,
        whatsappOptIn: whatsappOptIn,
        emailOptIn: emailOptIn ?? this.emailOptIn,
        creditLimitMinor: creditLimitMinor,
        creditAllowed: creditAllowed,
      );
}

TenantSession _session(TenantRole role) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

Future<void> _pump(
  WidgetTester tester,
  TenantDataReader reader, {
  TenantConfigurationDocumentWriter? writer,
  TenantRole role = TenantRole.owner,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
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
      ),
    );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantEmailReceiptsScreen(
          reader: reader,
          writer: writer ?? _Writer(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _ReceiptWriter implements TenantEmailReceiptWriter {
  final List<TenantEmailReceiptIntent> sent = <TenantEmailReceiptIntent>[];

  @override
  Future<void> send(TenantEmailReceiptIntent intent) async => sent.add(intent);
}

final class _Writer implements TenantConfigurationDocumentWriter {
  String? path;
  Map<String, Object?>? data;

  @override
  Future<TenantConfigurationWriteResult> merge({
    required String path,
    required Map<String, Object?> data,
  }) async {
    this.path = path;
    this.data = data;
    return const TenantConfigurationWriteResult.committed();
  }
}

final class _Reader implements TenantDataReader {
  const _Reader({this.withDeliveries = false});

  final bool withDeliveries;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (path == 'tenants/tenant-a/configuration/branding') {
      return TenantDocumentSnapshot(
        path: path,
        data: const <String, Object?>{'companyName': 'Mama Njeri Shop'},
      );
    }
    return null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    if (!withDeliveries ||
        !query.collectionPath.endsWith('/email_receipt_deliveries')) {
      return const <TenantQueryDocumentSnapshot>[];
    }
    return <TenantQueryDocumentSnapshot>[
      TenantQueryDocumentSnapshot(
        path: '${query.collectionPath}/ed_1',
        data: <String, Object?>{
          'saleId': 'co-1',
          'receiptNumber': 'JOHN-CT-7F2-001',
          'customerName': 'Jane',
          'emailMasked': 'j•••@example.com',
          'trigger': 'automatic',
          'status': 'delivered',
          'createdAt': DateTime.utc(2026, 10, 3, 9),
        },
      ),
      TenantQueryDocumentSnapshot(
        path: '${query.collectionPath}/ed_2',
        data: <String, Object?>{
          'saleId': 'co-2',
          'emailMasked': 'w•••@example.com',
          'trigger': 'manual',
          'status': 'failed',
          'reason': 'hard_bounce',
          'createdAt': DateTime.utc(2026, 10, 3, 8),
        },
      ),
    ];
  }
}

final class _Nothing implements TenantCacheReadable {
  const _Nothing();

  @override
  TenantDataReader get cacheOnly => this;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}
