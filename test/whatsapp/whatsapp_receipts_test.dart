import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/ui/record_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uzapay_pos/checkout/checkout_configuration_writer.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/choice.dart';
import 'package:uzapay_pos/ui/illustration.dart';
import 'package:uzapay_pos/whatsapp/whatsapp.dart';

import '../support/notices.dart';

/// The device's half of WhatsApp receipts: what a business has chosen, a
/// cashier's request to send one, and the screen an owner sets it up on.
void main() {
  testWidgets('desktop receipt history aligns recipient, receipt and status', (
    tester,
  ) async {
    await _pump(tester, const _Reader(withDeliveries: true));
    await tester.tap(find.text('Sent receipts'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordSheet), findsOneWidget);
    expect(find.text('JOHN-CT-7F2-001'), findsOneWidget);
    expect(find.text('Jane'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.text('Automatically'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('settings', () {
    test('a business that chose nothing sends nothing', () {
      expect(TenantEReceiptSettings.off.whatsappEnabled, isFalse);
      expect(
        () => TenantEReceiptSettings.fromMap(const <String, Object?>{}),
        throwsFormatException,
      );
      final odd = TenantEReceiptSettings.fromMap(const <String, Object?>{
        'whatsappEnabled': true,
        'mode': 'sometimes',
        'format': 'fax',
      });
      // Anything unrecognised reads as the cautious choice, as on the server.
      expect(odd.mode, EReceiptMode.manual);
      expect(odd.format, EReceiptFormat.pdf);
    });

    test('a refusal names whose problem it was', () {
      String? reasonFor(String reason) => TenantReceiptDelivery.fromSnapshot(
        TenantQueryDocumentSnapshot(
          path: 'tenants/t/receipt_deliveries/rd_1',
          data: <String, Object?>{'status': 'failed', 'reason': reason},
        ),
      ).reasonText;

      // Only Meta's "undeliverable" is about the customer's number.
      expect(reasonFor('refused_131026'), contains('number'));
      // A template that is unknown or still in review is UzaPay's, and the
      // shop must not be sent to check a number that is fine.
      for (final code in <String>['refused_132001', 'refused_132015']) {
        expect(reasonFor(code), contains('approved'));
        expect(reasonFor(code), isNot(contains('number')));
      }
      expect(reasonFor('refused_131000'), 'WhatsApp refused it.');
      expect(reasonFor('refused'), 'WhatsApp refused it.');
    });

    test('automatic sending still lets a cashier send one by hand', () {
      const settings = TenantEReceiptSettings(
        whatsappEnabled: true,
        mode: EReceiptMode.automatic,
        format: EReceiptFormat.summary,
      );
      expect(settings.sendsAutomatically, isTrue);
      expect(settings.offersManualSend, isTrue);
    });
  });

  group('when a receipt went', () {
    // A Saturday afternoon.
    final now = DateTime(2026, 10, 3, 14, 40);

    test(
      'is the time today, a word yesterday, then a weekday, then a date',
      () {
        expect(receiptDeliveryWhen(DateTime(2026, 10, 3, 9, 5), now), '09:05');
        expect(receiptDeliveryWhen(DateTime(2026, 10, 3, 0, 1), now), '00:01');
        expect(
          receiptDeliveryWhen(DateTime(2026, 10, 2, 23, 59), now),
          'Yesterday',
        );
        expect(receiptDeliveryWhen(DateTime(2026, 9, 28, 12), now), 'Mon');
        // Six days back is still this week's Sunday; seven is a date, or the
        // weekday would name two different days.
        expect(receiptDeliveryWhen(DateTime(2026, 9, 27, 12), now), 'Sun');
        expect(receiptDeliveryWhen(DateTime(2026, 9, 26, 12), now), '26 Sep');
        expect(
          receiptDeliveryWhen(DateTime(2025, 12, 31, 12), now),
          '31 Dec 2025',
        );
      },
    );

    test('is nothing for a record with no time on it yet', () {
      expect(receiptDeliveryWhen(null, now), isNull);
    });
  });

  group('a request to send one', () {
    test('is addressed to the record the server will write', () {
      // Printed by `receiptDeliveryId('tenant-a', 'co-1', '+254712345678',
      // 'receipt-request-0001')` in the compiled functions on 2026-10-01.
      expect(
        whatsappReceiptDeliveryId(
          tenantId: 'tenant-a',
          saleId: 'co-1',
          phone: '+254712345678',
          requestId: 'receipt-request-0001',
        ),
        'rd_7415c88a07f943f5f7d565489488d1e7b0243990',
      );
    });

    test('is refused when the number is not a number', () {
      expect(
        () => TenantWhatsappReceiptIntent.build(
          session: _session(TenantRole.cashier),
          saleId: 'co-1',
          phone: '0712345678',
        ),
        throwsA(
          isA<TenantWhatsappReceiptException>().having(
            (error) => error.code,
            'code',
            'invalid_phone',
          ),
        ),
      );
    });

    late Directory directory;
    late TenantPendingMutationStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('whatsapp-queue-');
      Hive.init(directory.path);
      store = TenantPendingMutationStore.fromBox(
        await Hive.openBox<dynamic>('whatsapp-queue-test'),
      );
    });

    tearDown(() async {
      await Hive.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test(
      'is queued as the callable request, and settled by sending again',
      () async {
        final intent = TenantWhatsappReceiptIntent.build(
          session: _session(TenantRole.cashier),
          saleId: 'co-1',
          phone: '+254712345678',
          customerName: 'Jane',
          requestId: 'receipt-request-0001',
        );
        await QueuedTenantWhatsappReceiptWriter(
          store: store,
          currentUid: () => 'user-a',
        ).send(intent);

        final record = (await store.recordsForSession(
          uid: 'user-a',
          tenantId: 'tenant-a',
        )).single;
        expect(record.kind, TenantPendingMutationKind.whatsappReceiptRequest);
        expect(record.targetPath, intent.path);
        expect(record.payload, <String, Object?>{
          'tenantId': 'tenant-a',
          'saleId': 'co-1',
          'phone': '+254712345678',
          'requestId': 'receipt-request-0001',
          'customerName': 'Jane',
        });
        expect(tenantMutationIsCallable(record.kind), isTrue);
        expect(tenantMutationResendConfirms(record.kind), isTrue);

        // Drawn for the WhatsApp screen without the number in the clear.
        final drawn = await TenantPendingMutationOverlayReader(
          base: const _Nothing(),
          store: store,
          currentUid: () => 'user-a',
        ).getDocument(intent.path);
        expect(drawn!.data['status'], 'queued');
        expect(drawn.data['phoneMasked'], '+254•••678');
        expect(drawn.data.values.contains('+254712345678'), isFalse);
      },
    );
  });

  group('the WhatsApp screen', () {
    testWidgets('turning receipts on publishes the format and the timing', (
      tester,
    ) async {
      final writer = _Writer();
      await _pump(tester, const _Reader(), writer: writer, available: true);

      // The switch is its label alone; its position is the state.
      final toggle = find.byKey(const ValueKey('e-receipts-enabled'));
      expect(tester.widget<AppSwitchRow>(toggle).value, isFalse);
      // A switch: one tap turns it on.
      await tester.tap(find.byKey(const ValueKey('e-receipts-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('e-receipts-format-summary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('e-receipts-mode-automatic')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Thank you for shopping at Mama Njeri Shop.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('e-receipts-save')));
      await tester.tap(find.byKey(const ValueKey('e-receipts-save')));
      await tester.pumpAndSettle();

      expect(writer.path, 'tenants/tenant-a/configuration/e_receipts');
      expect(writer.data?['whatsappEnabled'], isTrue);
      expect(writer.data?['format'], 'summary');
      expect(writer.data?['mode'], 'automatic');
      expect(snackNotice(tester).message, contains('Saved'));
      expect(
        find.byKey(const ValueKey('e-receipts-unavailable')),
        findsNothing,
      );
    });

    testWidgets('says plainly when the number is not connected yet', (
      tester,
    ) async {
      await _pump(tester, const _Reader(), available: false);

      expect(
        find.byKey(const ValueKey('e-receipts-unavailable')),
        findsOneWidget,
      );
    });

    testWidgets('lists recent receipts with what became of each, in words', (
      tester,
    ) async {
      await _pump(tester, const _Reader(withDeliveries: true), available: true);
      // Their own tab, not the foot of the settings.
      expect(find.text('Delivered'), findsNothing);
      await tester.tap(find.text('Sent receipts'));
      await tester.pumpAndSettle();

      expect(find.text('Delivered'), findsOneWidget);
      expect(find.text('Not sent'), findsOneWidget);
      expect(find.text('The customer replied STOP.'), findsOneWidget);
    });

    testWidgets('the preview is the chat, and a PDF arrives above its words', (
      tester,
    ) async {
      await _pump(tester, const _Reader(), available: true);
      // Off, there is nothing to preview.
      expect(find.byKey(const ValueKey('e-receipts-preview')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('e-receipts-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('e-receipts-format-pdf')));
      await tester.pumpAndSettle();

      // It leads the page, above the switch and the choices it shows.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('e-receipts-preview'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('e-receipts-enabled')))
              .dy,
        ),
      );
      // The file is a document of its own, not words in the message.
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('e-receipts-preview-file')))
            .data,
        eReceiptPreviewFileName,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('e-receipts-preview-text')))
            .data,
        isNot(contains('.pdf')),
      );

      await tester.tap(find.byKey(const ValueKey('e-receipts-format-summary')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('e-receipts-preview-file')),
        findsNothing,
      );
      expect(
        find.textContaining('3 items, total KES 1,250.00'),
        findsOneWidget,
      );
    });

    testWidgets('a sent receipt says who, when, what became of it, and how', (
      tester,
    ) async {
      final sent = DateTime.utc(2026, 10, 1, 9);
      final now = sent.add(const Duration(minutes: 1));
      await _pump(
        tester,
        const _Reader(withDeliveries: true),
        available: true,
        clock: () => now,
        width: 411,
      );
      await tester.tap(find.text('Sent receipts'));
      await tester.pumpAndSettle();

      // A name is its initials; a bare number, a person glyph.
      expect(find.text('J'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.text(receiptDeliveryWhen(sent, now)!), findsOneWidget);
      expect(find.text('· JOHN-CT-7F2-001'), findsOneWidget);
      // How it went is a glyph, with its words for a screen reader.
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('e-receipts-delivery-rd_1')),
            )
            .label,
        allOf(
          contains('Jane'),
          contains('Delivered'),
          contains('automatically'),
        ),
      );
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('e-receipts-delivery-rd_2')),
            )
            .label,
        contains('Sent by hand'),
      );
      // Two receipts are every receipt there is, so no limit is claimed: the
      // footer is for a full page, where the list stops short of the rest.
      expect(
        find.byKey(const ValueKey('e-receipts-deliveries-end')),
        findsNothing,
      );
    });

    testWidgets('says nothing about the connection while the check is out', (
      tester,
    ) async {
      final check = Completer<bool?>();
      await _pump(tester, const _Reader(), statusCheck: (_) => check.future);
      // Any rebuild will do; this is the one a person makes first.
      await tester.tap(find.byKey(const ValueKey('e-receipts-enabled')));
      await tester.pumpAndSettle();

      // The question has gone out and not come back. A connected phone told
      // to connect to the internet stops believing the note on the day it is
      // true.
      expect(find.byKey(const ValueKey('e-receipts-unknown')), findsNothing);

      check.complete(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('e-receipts-unknown')), findsOneWidget);
    });

    testWidgets('an empty device copy holds the receipts as placeholders', (
      tester,
    ) async {
      final server = Completer<List<TenantQueryDocumentSnapshot>>();
      await _pump(
        tester,
        _HeldDeliveries(server.future),
        available: true,
        settle: false,
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Sent receipts'));
      await tester.pump();
      // The tab's slide; the placeholders sweep for ever, so no settling.
      await tester.pump(const Duration(seconds: 1));

      // The device has never read the receipts, which is not the same as none
      // having been sent.
      expect(
        find.byKey(const ValueKey('e-receipts-deliveries-reading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('e-receipts-deliveries-empty')),
        findsNothing,
      );

      // The server saying none is drawn with the WhatsApp receipt scene.
      server.complete(const <TenantQueryDocumentSnapshot>[]);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('e-receipts-deliveries-empty')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('e-receipts-deliveries-empty')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AppIllustration &&
                widget.asset == 'receipt-whatsapp.svg',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('e-receipts-deliveries-reading')),
        findsNothing,
      );
    });

    testWidgets('a manager is told it is not theirs to decide', (tester) async {
      await _pump(tester, const _Reader(), role: TenantRole.manager);

      expect(
        find.textContaining('Only an owner or administrator'),
        findsOneWidget,
      );
    });
  });
}

TenantSession _session(TenantRole role) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

Future<void> _pump(
  WidgetTester tester,
  TenantDataReader reader, {
  TenantConfigurationDocumentWriter? writer,
  TenantRole role = TenantRole.owner,
  bool? available,
  WhatsappReceiptStatusCheck? statusCheck,
  DateTime Function()? clock,
  bool settle = true,
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 3000);
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
        child: TenantWhatsappReceiptsScreen(
          reader: reader,
          writer: writer ?? _Writer(),
          statusCheck: statusCheck ?? (_) async => available,
          clock: clock,
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

/// The server holds the receipts back; the device's copy has none of them.
final class _HeldDeliveries implements TenantCacheReadable {
  const _HeldDeliveries(this._deliveries);

  final Future<List<TenantQueryDocumentSnapshot>> _deliveries;

  @override
  TenantDataReader get cacheOnly => const _Reader();

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) =>
      const _Reader().getDocument(path);

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) => query.collectionPath.endsWith('/receipt_deliveries')
      ? _deliveries
      : const _Reader().getCollectionPage(query);
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
        !query.collectionPath.endsWith('/receipt_deliveries')) {
      return const <TenantQueryDocumentSnapshot>[];
    }
    return <TenantQueryDocumentSnapshot>[
      TenantQueryDocumentSnapshot(
        path: '${query.collectionPath}/rd_1',
        data: <String, Object?>{
          'saleId': 'co-1',
          'receiptNumber': 'JOHN-CT-7F2-001',
          'customerName': 'Jane',
          'phoneMasked': '+254•••678',
          'trigger': 'automatic',
          'status': 'delivered',
          'createdAt': DateTime.utc(2026, 10, 1, 9),
        },
      ),
      TenantQueryDocumentSnapshot(
        path: '${query.collectionPath}/rd_2',
        data: <String, Object?>{
          'saleId': 'co-2',
          'phoneMasked': '+254•••001',
          'trigger': 'manual',
          'status': 'skipped',
          'reason': 'opted_out',
          'createdAt': DateTime.utc(2026, 10, 1, 8),
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
