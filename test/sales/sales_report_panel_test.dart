import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/sales/sales.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/fields.dart';
import 'package:flutter_application_1/ui/skeleton.dart';
import 'package:flutter_test/flutter_test.dart';

const _businessDate = '2026-08-24';
const _deviceId = 'dev-0123456789abcdef0123456789abcdef';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  group('tenant sales report repository', () {
    test('management receives a stable business-wide range page', () async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-3', sequence: 3, soldById: 'user-b'),
        _sale('co-2', sequence: 2),
        _sale('co-1', sequence: 1),
      ]);
      final repository = TenantSaleHistoryRepository(
        session: _session(role: TenantRole.manager),
        reader: reader,
        reportReader: reader,
      );

      final page = await repository.loadReport(
        startBusinessDate: '2026-08-18',
        endBusinessDate: _businessDate,
        pageSize: 2,
      );

      expect(page.items.map((sale) => sale.id), <String>['co-3', 'co-2']);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, isNot(anyOf(isNull, 'co-2')));
      final query = reader.salesQueries.single;
      expect(query.collectionPath, 'tenants/tenant-a/sales');
      expect(query.startBusinessDate, '2026-08-18');
      expect(query.endBusinessDate, _businessDate);
      expect(query.soldById, isNull);
      expect(query.limit, 3);
    });

    test('cashier scope is forced before the query executes', () async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-2', sequence: 2, soldById: 'user-b'),
        _sale('co-1', sequence: 1),
      ]);
      final repository = TenantSaleHistoryRepository(
        session: _session(),
        reader: reader,
        reportReader: reader,
      );

      await expectLater(
        repository.loadReport(
          startBusinessDate: _businessDate,
          endBusinessDate: _businessDate,
          selectedStaffId: 'user-b',
        ),
        throwsA(
          isA<TenantSaleException>().having(
            (error) => error.code,
            'code',
            'sale_report_forbidden',
          ),
        ),
      );
      expect(reader.salesQueries, isEmpty);

      final own = await repository.loadReport(
        startBusinessDate: _businessDate,
        endBusinessDate: _businessDate,
      );
      expect(reader.salesQueries.single.soldById, 'user-a');
      expect(own.items.single.soldById, 'user-a');
    });

    test('a cross-tenant report result fails closed', () async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-1', tenantId: 'tenant-b'),
      ]);
      await expectLater(
        TenantSaleHistoryRepository(
          session: _session(role: TenantRole.manager),
          reader: reader,
          reportReader: reader,
        ).loadReport(
          startBusinessDate: _businessDate,
          endBusinessDate: _businessDate,
        ),
        throwsA(anyOf(isA<TenantScopeViolation>(), isA<TenantSaleException>())),
      );
    });
  });

  group('unified sales presentation', () {
    testWidgets('cashier sees only own mobile cards and no payment mutation', (
      tester,
    ) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-1', tender: 'mpesa'),
      ]);
      await _pump(tester, reader, width: 411, role: TenantRole.cashier);

      expect(find.byKey(const ValueKey('sales-report-cards')), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-own-scope')), findsNothing);
      expect(find.byKey(const ValueKey('sales-date-filter')), findsOneWidget);
      expect(reader.salesQueries.single.soldById, 'user-a');
      expect(find.text('Edit payment method'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('sales-actions-co-1')));
      await tester.pumpAndSettle();
      expect(find.text('View sale details'), findsNothing);
      expect(find.text('Return'), findsOneWidget);
      expect(find.text('Edit payment method'), findsNothing);
    });

    testWidgets('management receives item-led cards at desktop width', (
      tester,
    ) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-2', sequence: 2, soldById: 'user-b', tender: 'card'),
        _sale('co-1', tender: 'cash'),
      ]);
      await _pump(tester, reader, width: 1024, role: TenantRole.manager);

      expect(find.byKey(const ValueKey('sales-report-cards')), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-report-table')), findsNothing);
      expect(find.byKey(const ValueKey('sales-item-co-1-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-staff-filter')), findsOneWidget);
      expect(reader.salesQueries.single.soldById, isNull);
      expect(find.text(_businessDate), findsWidgets);
    });

    testWidgets(
      'sale cards keep items visible and show only the receipt ending',
      (tester) async {
        final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
          _sale('co-1', tender: 'cash'),
        ]);
        await _pump(tester, reader, width: 411, role: TenantRole.cashier);

        final item = find.byKey(const ValueKey('sales-item-co-1-0'));
        final receipt = find.byKey(const ValueKey('sales-receipt-ending-co-1'));
        expect(item, findsOneWidget);
        expect(receipt, findsOneWidget);
        final time = find.byKey(const ValueKey('sales-recorded-time-co-1'));
        expect(time, findsOneWidget);
        expect(
          tester.getTopLeft(time).dx,
          lessThan(tester.getTopLeft(receipt).dx),
        );
        expect(tester.widget<Text>(time).data, isNot(contains('UTC')));
        expect(tester.widget<Text>(time).style?.fontWeight, FontWeight.w800);
        expect(find.text('#0001'), findsOneWidget);
        expect(
          find.text(
            formatCheckoutReceiptNumber(
              deviceId: _deviceId,
              businessDate: _businessDate,
              sequence: 1,
            ),
          ),
          findsNothing,
        );
        expect(find.text('Long-life whole milk 500 ml'), findsOneWidget);
        expect(find.text('View sale details'), findsNothing);
      },
    );

    testWidgets('the compact controls and payment mix use one summary card', (
      tester,
    ) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-2', sequence: 2, tender: 'mpesa'),
        _sale('co-1', tender: 'cash'),
      ]);
      await _pump(
        tester,
        reader,
        width: 411,
        role: TenantRole.manager,
        totalsCallable: _TotalsCallable(),
      );

      final receipt = tester.getRect(
        find.byKey(const ValueKey('sales-receipt-search')),
      );
      final search = tester.getRect(
        find.byKey(const ValueKey('sales-receipt-submit')),
      );
      expect(receipt.center.dy, closeTo(search.center.dy, 1));
      expect(search.width, lessThan(receipt.width));
      expect(find.text('Find a receipt'), findsNothing);

      final date = tester.getRect(
        find.byKey(const ValueKey('sales-date-filter')),
      );
      final staff = tester.getRect(
        find.byKey(const ValueKey('sales-staff-filter')),
      );
      expect(date.top, closeTo(staff.top, 1));
      expect(find.byKey(const ValueKey('sales-period-filter')), findsNothing);

      final summary = find.byKey(const ValueKey('sales-report-summary'));
      expect(summary, findsOneWidget);
      expect(
        find.descendant(
          of: summary,
          matching: find.byKey(const ValueKey('sales-report-revenue')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.byKey(const ValueKey('sales-report-transactions')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.byType(LinearProgressIndicator),
        ),
        findsNWidgets(4),
      );
      expect(find.text(checkoutTenderDisclaimer), findsNothing);
    });

    testWidgets('daily ending search replaces and clearing restores history', (
      tester,
    ) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-1', tender: 'cash'),
      ]);
      await _pump(tester, reader, width: 411, role: TenantRole.cashier);

      await tester.enterText(
        find.byKey(const ValueKey('sales-receipt-search')),
        '1',
      );
      await tester.tap(find.byKey(const ValueKey('sales-receipt-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sales-record-co-1')), findsOneWidget);
      expect(reader.collectionQueries.last.equalityFilters, <String, Object?>{
        'businessDate': _businessDate,
        'receiptSequence': 1,
        'soldById': 'user-a',
      });

      await tester.enterText(
        find.byKey(const ValueKey('sales-receipt-search')),
        '',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('sales-report-cards')), findsOneWidget);
    });

    testWidgets('date changes reset an advanced opaque cursor', (tester) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-2', sequence: 2),
        _sale('co-1', sequence: 1),
      ]);
      await _pump(
        tester,
        reader,
        width: 411,
        role: TenantRole.cashier,
        pageSize: 1,
      );

      await tester.tap(find.byKey(const ValueKey('sales-report-next-page')));
      await tester.pumpAndSettle();
      expect(reader.salesQueries.last.startAfter?.documentId, 'co-2');
      expect(find.byKey(const ValueKey('sales-record-co-1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sales-date-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('23').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final reset = reader.salesQueries.last;
      expect(reset.startAfter, isNull);
      expect(reset.startBusinessDate, '2026-08-23');
      expect(reset.endBusinessDate, '2026-08-23');
    });

    testWidgets('an active ending search reruns for the newly selected date', (
      tester,
    ) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-today', sequence: 1),
        _sale('co-yesterday', sequence: 1, businessDate: '2026-08-23'),
      ]);
      await _pump(tester, reader, width: 411, role: TenantRole.cashier);

      await tester.enterText(
        find.byKey(const ValueKey('sales-receipt-search')),
        '0001',
      );
      await tester.tap(find.byKey(const ValueKey('sales-receipt-submit')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sales-record-co-today')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('sales-date-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('23').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sales-record-co-yesterday')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sales-record-co-today')), findsNothing);
      expect(reader.collectionQueries.last.equalityFilters, <String, Object?>{
        'businessDate': '2026-08-23',
        'receiptSequence': 1,
        'soldById': 'user-a',
      });
    });

    testWidgets('management ending search shows every till collision', (
      tester,
    ) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale(
          'co-2',
          sequence: 42,
          soldById: 'user-b',
          deviceId: 'dev-11111111111111111111111111111111',
        ),
        _sale('co-1', sequence: 42),
      ]);
      await _pump(tester, reader, width: 1024, role: TenantRole.manager);

      await tester.enterText(
        find.byKey(const ValueKey('sales-receipt-search')),
        '42',
      );
      await tester.tap(find.byKey(const ValueKey('sales-receipt-submit')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sales-receipt-ambiguous')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sales-record-co-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-record-co-2')), findsOneWidget);
      expect(reader.collectionQueries.last.equalityFilters, <String, Object?>{
        'businessDate': _businessDate,
        'receiptSequence': 42,
      });
    });

    testWidgets('management staff selection is applied at the query boundary', (
      tester,
    ) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-2', sequence: 2, soldById: 'user-b'),
        _sale('co-1', sequence: 1),
      ]);
      await _pump(tester, reader, width: 1024, role: TenantRole.manager);

      await tester.tap(find.byKey(const ValueKey('sales-staff-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Baraka Cashier (user-b)').last);
      await tester.pumpAndSettle();

      expect(reader.salesQueries.last.soldById, 'user-b');
      expect(find.byKey(const ValueKey('sales-record-co-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-record-co-1')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('sales-receipt-search')),
        '2',
      );
      await tester.tap(find.byKey(const ValueKey('sales-receipt-submit')));
      await tester.pumpAndSettle();
      expect(reader.collectionQueries.last.equalityFilters, <String, Object?>{
        'businessDate': _businessDate,
        'receiptSequence': 2,
        'soldById': 'user-b',
      });
    });

    testWidgets('a tenant switch discards an outstanding report page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reader = _DeferredSalesReader();
      final controller = TenantSessionController()
        ..open(uid: 'user-a', membership: _membership(TenantRole.cashier));
      await tester.pumpWidget(
        MaterialApp(
          home: TenantSessionScope(
            controller: controller,
            child: Scaffold(
              body: TenantSalesReportPanel(
                reader: reader,
                reportReader: reader,
                clock: () => DateTime.utc(2026, 8, 24, 12),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(reader.pending, contains('tenants/tenant-a/sales'));

      controller.open(
        uid: 'user-b',
        membership: _membership(TenantRole.cashier, tenantId: 'tenant-b'),
      );
      await tester.pump();
      await tester.pump();
      expect(reader.pending, contains('tenants/tenant-b/sales'));

      reader.complete('tenants/tenant-a/sales', <TenantQueryDocumentSnapshot>[
        _sale('co-1'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('sales-record-co-1')), findsNothing);

      reader.complete('tenants/tenant-b/sales', <TenantQueryDocumentSnapshot>[
        _sale('co-9', sequence: 9, tenantId: 'tenant-b', soldById: 'user-b'),
      ]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sales-record-co-9')), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-record-co-1')), findsNothing);
    });
  });

  // `docs/stitch/OPEN_QUESTIONS.md` decision 35, and this is the screen it was
  // taken for. **The assertion that matters is the negative one**: the receipt
  // field and the date button are not merely present while the day is being
  // read, they are present *as themselves* rather than as placeholders. A
  // skeleton that swallowed them would satisfy every other test in this file.
  group('a day being read still offers everything it can already do', () {
    testWidgets('the receipt search and the date are real, not placeholders', (
      tester,
    ) async {
      await _pumpUnsettled(tester, role: TenantRole.owner);

      for (final chrome in <ValueKey<String>>[
        const ValueKey('sales-receipt-search'),
        const ValueKey('sales-receipt-submit'),
        const ValueKey('sales-date-picker'),
        const ValueKey('sales-report-page'),
      ]) {
        expect(find.byKey(chrome), findsOne, reason: '$chrome while loading');
        expect(
          find.descendant(
            of: find.byKey(chrome),
            matching: find.byType(SkeletonBlock),
          ),
          findsNothing,
          reason: '$chrome must not be drawn as a placeholder',
        );
      }

      await tester.pumpAndSettle();
    });

    testWidgets('the date button already names the day being read', (
      tester,
    ) async {
      // The date is the panel's own selection - what was *asked for* - so it is
      // known before anything answers. Reading it off the loaded view would
      // have made the button wait for a figure it does not show.
      await _pumpUnsettled(tester, role: TenantRole.owner);

      expect(find.text(_businessDate), findsOne);

      await tester.pumpAndSettle();
    });

    testWidgets('the staff filter holds its place, disabled', (tester) async {
      // Absent would move the date button from half the row to all of it and
      // back again, which is the jump this change exists to remove.
      await _pumpUnsettled(tester, role: TenantRole.owner);

      final filter = tester.widget<AppSelect<String>>(
        find.byKey(const ValueKey('sales-staff-filter')),
      );
      expect(filter.enabled, isFalse);

      await tester.pumpAndSettle();
    });

    testWidgets('the sales and the totals are the placeholders', (
      tester,
    ) async {
      await _pumpUnsettled(tester, role: TenantRole.owner);

      expect(find.byKey(const ValueKey('sales-report-skeleton')), findsOne);
      expect(
        find.byKey(const ValueKey('sales-report-totals-skeleton')),
        findsOne,
      );

      await tester.pumpAndSettle();
    });

    testWidgets('a day with no sales answers with its empty state', (
      tester,
    ) async {
      // The requirement that outranks all of this: an empty read has *answered*,
      // and must never be left looking like one still in flight.
      await _pumpUnsettled(tester, role: TenantRole.owner);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sales-report-empty')), findsOne);
      expect(find.byKey(const ValueKey('sales-report-skeleton')), findsNothing);
      expect(
        find.byKey(const ValueKey('sales-report-totals-skeleton')),
        findsNothing,
      );
    });
  });
}

/// The panel on its first frame, before the guard's read has answered.
///
/// `_pump` settles, which is what every other case here wants; this one stops
/// on the loading state deliberately, because that is the state under test.
Future<void> _pumpUnsettled(
  WidgetTester tester, {
  required TenantRole role,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TenantSessionController()
    ..open(uid: 'user-a', membership: _membership(role));
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantSalesReportPanel(
            reader: _SalesReader(const <TenantQueryDocumentSnapshot>[]),
            reportReader: _SalesReader(const <TenantQueryDocumentSnapshot>[]),
            clock: () => DateTime.utc(2026, 8, 24, 12),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  _SalesReader reader, {
  required double width,
  required TenantRole role,
  int pageSize = 20,
  SalesTotalsCallable? totalsCallable,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TenantSessionController()
    ..open(uid: 'user-a', membership: _membership(role));
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantSalesReportPanel(
            reader: reader,
            reportReader: reader,
            totalsCallable: totalsCallable,
            clock: () => DateTime.utc(2026, 8, 24, 12),
            pageSize: pageSize,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _TotalsCallable implements SalesTotalsCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) async => <String, Object?>{
    'previous': <String, Object?>{
      'sales': 100,
      'profit': 30,
      'transactions': 4,
      'incompleteCostLineCount': 0,
    },
    'scannedTransactions': 4,
    'byTender': <String, Object?>{
      'cash': <String, Object?>{'sales': 50, 'transactions': 1},
      'mpesa': <String, Object?>{'sales': 30, 'transactions': 1},
      'card': <String, Object?>{'sales': 15, 'transactions': 1},
      'unrecorded': <String, Object?>{'sales': 5, 'transactions': 1},
      'other': <String, Object?>{'sales': 0, 'transactions': 0},
    },
  };
}

TenantSession _session({TenantRole role = TenantRole.cashier}) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

TenantMembership _membership(TenantRole role, {String tenantId = 'tenant-a'}) =>
    TenantMembership(
      tenantId: tenantId,
      tenantName: 'Corner Shop',
      tenantSlug: 'corner-shop',
      role: role,
      membershipStatus: MembershipStatus.active,
      tenantStatus: TenantStatus.active,
      isOwner: role == TenantRole.owner,
      mirrorVersion: 1,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 24),
      serverCanAccess: true,
      canonicalTenantExists: true,
      canonicalMembershipExists: true,
    );

TenantQueryDocumentSnapshot _sale(
  String id, {
  int sequence = 1,
  String tenantId = 'tenant-a',
  String soldById = 'user-a',
  String? tender,
  String businessDate = _businessDate,
  String deviceId = _deviceId,
}) {
  final data = <String, Object?>{
    'checkoutId': id,
    'tenantId': tenantId,
    'soldById': soldById,
    'payloadHash': _hash,
    'payloadSchemaVersion': tender == null ? 1 : 2,
    if (tender != null) 'tender': tender,
    'currency': 'KES',
    'businessDate': businessDate,
    'shiftId': 'shift-a',
    'deviceId': deviceId,
    'receiptNumber': formatCheckoutReceiptNumber(
      deviceId: deviceId,
      businessDate: businessDate,
      sequence: sequence,
    ),
    'receiptSequence': sequence,
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-1',
        'name': 'Long-life whole milk 500 ml',
        'quantity': 2,
        'unitPriceMinor': 500,
        'lineTotalMinor': 1000,
      },
    ],
    'subtotalMinor': 1000,
    'subtotal': 10.0,
    'discountMinor': 100,
    'discount': 1.0,
    'totalMinor': 900,
    'total': 9.0,
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 24, 9, sequence)),
  };
  return TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/sales/$id',
    data: data,
  );
}

final class _SalesReader
    implements TenantDataReader, TenantSalesHistoryQueryReader {
  _SalesReader(this.sales);

  final List<TenantQueryDocumentSnapshot> sales;
  final List<TenantSalesHistoryQuery> salesQueries =
      <TenantSalesHistoryQuery>[];
  final List<TenantCollectionQuery> collectionQueries =
      <TenantCollectionQuery>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (path == 'tenants/tenant-a') {
      return TenantDocumentSnapshot(
        path: path,
        data: const <String, Object?>{'ownerUid': 'owner-a'},
      );
    }
    if (path == 'tenants/tenant-a/configuration/checkout') {
      return TenantDocumentSnapshot(
        path: path,
        data: const <String, Object?>{'currency': 'KES'},
      );
    }
    final match = RegExp(r'^tenants/tenant-a/staff/([^/]+)$').firstMatch(path);
    if (match != null) {
      final uid = match.group(1)!;
      final role = uid == 'owner-a' ? 'owner' : 'cashier';
      return TenantDocumentSnapshot(
        path: path,
        data: _staffData(uid, role: role),
      );
    }
    return null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    collectionQueries.add(query);
    if (query.collectionPath == 'tenants/tenant-a/categories') return const [];
    if (query.collectionPath == 'tenants/tenant-a/staff') {
      return <TenantQueryDocumentSnapshot>[
        TenantQueryDocumentSnapshot(
          path: 'tenants/tenant-a/staff/owner-a',
          data: _staffData('owner-a', role: 'owner'),
        ),
        TenantQueryDocumentSnapshot(
          path: 'tenants/tenant-a/staff/user-a',
          data: _staffData('user-a', name: 'Amina Cashier'),
        ),
        TenantQueryDocumentSnapshot(
          path: 'tenants/tenant-a/staff/user-b',
          data: _staffData('user-b', name: 'Baraka Cashier'),
        ),
      ].take(query.limit).toList();
    }
    if (query.collectionPath == 'tenants/tenant-a/sales') {
      final matches =
          sales
              .where(
                (snapshot) => query.equalityFilters.entries.every(
                  (filter) => snapshot.data[filter.key] == filter.value,
                ),
              )
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      return matches.take(query.limit).toList();
    }
    return const [];
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantSalesHistory(
    TenantSalesHistoryQuery query,
  ) async {
    salesQueries.add(query);
    return sales
        .where((snapshot) {
          final date = snapshot.data['businessDate'] as String;
          final position = query.startAfter;
          final id = snapshot.path.split('/').last;
          final afterCursor =
              position == null ||
              date.compareTo(position.businessDate) < 0 ||
              date == position.businessDate &&
                  id.compareTo(position.documentId) < 0;
          return afterCursor &&
              date.compareTo(query.startBusinessDate) >= 0 &&
              date.compareTo(query.endBusinessDate) <= 0 &&
              (query.soldById == null ||
                  snapshot.data['soldById'] == query.soldById);
        })
        .take(query.limit)
        .toList();
  }
}

final class _DeferredSalesReader
    implements TenantDataReader, TenantSalesHistoryQueryReader {
  final Map<String, Completer<List<TenantQueryDocumentSnapshot>>> pending =
      <String, Completer<List<TenantQueryDocumentSnapshot>>>{};

  void complete(String path, List<TenantQueryDocumentSnapshot> snapshots) =>
      pending[path]!.complete(snapshots);

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    if (RegExp(r'^tenants/[^/]+/configuration/checkout$').hasMatch(path)) {
      return TenantDocumentSnapshot(
        path: path,
        data: const <String, Object?>{'currency': 'KES'},
      );
    }
    final staff = RegExp(r'^tenants/([^/]+)/staff/([^/]+)$').firstMatch(path);
    if (staff != null) {
      return TenantDocumentSnapshot(
        path: path,
        data: _staffData(staff.group(2)!),
      );
    }
    return null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];

  @override
  Future<List<TenantQueryDocumentSnapshot>> queryTenantSalesHistory(
    TenantSalesHistoryQuery query,
  ) {
    final completer = Completer<List<TenantQueryDocumentSnapshot>>();
    pending[query.collectionPath] = completer;
    return completer.future;
  }
}

Map<String, Object?> _staffData(
  String uid, {
  String role = 'cashier',
  String? name,
}) => <String, Object?>{
  'uid': uid,
  'email': '$uid@example.test',
  'name': name ?? (uid == 'owner-a' ? 'Owner Person' : 'Staff Person'),
  'phone': '+254700000000',
  'role': role,
  'status': 'active',
  'invitationStatus': 'accepted',
};
