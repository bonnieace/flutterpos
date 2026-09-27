import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/reports/analysis/sales_report.dart';
import 'package:flutter_application_1/reports/report_period.dart';
import 'package:flutter_application_1/returns/return_offsets.dart';
import 'package:flutter_application_1/sales/sales.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/fields.dart';
import 'package:flutter_application_1/ui/press.dart';
import 'package:flutter_application_1/ui/skeleton.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

const _businessDate = '2026-08-24';

/// A day before [_businessDate], for a report opened on a past shift.
const _before = '2026-08-21';
const _deviceId = 'dev-0123456789abcdef0123456789abcdef';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  group('tenant sales report repository', () {
    test(
      'export analysis nets a pending return from the current day',
      () async {
        final reader = _SalesReader(
          <TenantQueryDocumentSnapshot>[
            _sale('co-2', sequence: 2, tender: 'cash'),
            _sale('co-1', sequence: 1, tender: 'cash'),
          ],
          returns: <TenantQueryDocumentSnapshot>[
            _returnRecord('rt-1', saleId: 'co-1'),
          ],
        );
        final session = _session(role: TenantRole.manager);
        final source = TenantSalesReportSource(
          repository: TenantSaleHistoryRepository(
            session: session,
            reader: reader,
            reportReader: reader,
          ),
          returnsLoader: TenantDayReturnsLoader(
            session: session,
            reader: reader,
          ),
        );

        final analysis = await source.gatherAnalysis(
          TenantReportPeriod(startDate: _businessDate, endDate: _businessDate),
        );

        expect(analysis.revenueMinor, 900);
        expect(analysis.transactions, 1);
        expect(analysis.returnedMinor, 900);
        expect(analysis.tenders.single.minor, 900);
        expect(analysis.items.single.quantity, 2);
      },
    );

    test(
      'a truncated preceding period is not offered as a comparison',
      () async {
        final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
          _sale('co-2', sequence: 2, businessDate: '2026-08-23'),
          _sale('co-1', sequence: 1, businessDate: '2026-08-23'),
        ]);
        final source = TenantSalesReportSource(
          repository: TenantSaleHistoryRepository(
            session: _session(role: TenantRole.manager),
            reader: reader,
            reportReader: reader,
          ),
          pageSize: 1,
          maximumPages: 1,
        );

        final previous = await source.gatherPrevious(
          TenantReportPeriod(startDate: _businessDate, endDate: _businessDate),
        );

        expect(previous, isNull);
        expect(reader.salesQueries.single.limit, 2);
      },
    );

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
        // The figures' face at its own weight. It asked for 800 until
        // 2026-09-22, which JetBrains Mono is not bundled at, so the engine
        // synthesised a bold the design never drew.
        expect(tester.widget<Text>(time).style?.fontWeight, FontWeight.w500);
        // **Still the bare sequence, and still ambiguous.** Every register
        // starts a business date at 0001, so this named two different receipts
        // on 2026-09-17 - one from each of two tills - and the row cannot tell
        // them apart. Naming the till here needs the row to give up something;
        // the width check below is the measurement that says so.
        final full = formatCheckoutReceiptNumber(
          deviceId: _deviceId,
          businessDate: _businessDate,
          sequence: 1,
        );
        expect(find.text('#0001'), findsOneWidget);
        expect(find.text(full), findsNothing);

        // **The till is named in the foot instead.** `#0001` above is the same
        // on every register's first sale of a day, which is how two receipts
        // read alike on 2026-09-17. The foot is a `Wrap`, so it reflows rather
        // than ellipsizing the way the header slot does.
        final parts = full.split('-');
        final till = find.byKey(ValueKey('sales-receipt-till-co-1'));
        expect(till, findsOneWidget);
        expect(
          find.descendant(
            of: till,
            matching: find.text('${parts[0]}-${parts[1]}-${parts[3]}'),
          ),
          findsOneWidget,
        );

        // **Proved here because nothing else can prove it.** The label sits in
        // a `Flexible` with `maxLines: 1` and an ellipsis, so a row too narrow
        // for it truncates silently rather than overflowing - no test throws,
        // and the screenshot harness has no case for this screen. This slot is
        // about 66 logical pixels at 411, which is five and a half characters:
        // `#0001` fits and `CT-882-0001`, at 131.5, was cut in half.
        final label = tester.widget<Text>(receipt);
        final painter = TextPainter(
          text: TextSpan(text: label.data, style: label.style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        expect(
          tester.getSize(receipt).width,
          greaterThanOrEqualTo(painter.width - 0.5),
          reason: 'the receipt label must not be ellipsized at 411px',
        );
        expect(find.text('Long-life whole milk 500 ml'), findsOneWidget);
        expect(find.text('View sale details'), findsNothing);
      },
    );

    testWidgets("a sale rung offline shows when it was rung, not when it synced", (
      tester,
    ) async {
      // **The night sale that read as a morning one.** A batch queued with no
      // signal has its server timestamp resolved when it finally lands, so this
      // sale - rung at 22:10, synced at 10:25 the next morning - used to sit in
      // the day's history at 10:25. It is filed under the right trading day
      // either way; it was the hour that lied.
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale(
          'co-1',
          tender: 'cash',
          rungAt: DateTime.utc(2026, 8, 23, 19, 10),
          createdAt: DateTime.utc(2026, 8, 24, 7, 25),
        ),
      ]);
      await _pump(tester, reader, width: 411, role: TenantRole.cashier);

      final time = find.byKey(const ValueKey('sales-recorded-time-co-1'));
      expect(
        tester.widget<Text>(time).data,
        _localClock(DateTime.utc(2026, 8, 23, 19, 10)),
      );

      // And the gap is said out loud, so the row is not read as a wrong clock.
      final synced = find.byKey(const ValueKey('sales-synced-later-co-1'));
      expect(synced, findsOneWidget);
      expect(
        find.descendant(
          of: synced,
          matching: find.text(
            'Synced ${_localClock(DateTime.utc(2026, 8, 24, 7, 25))}',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets("a sale that never waited says nothing about syncing", (
      tester,
    ) async {
      // Seconds apart is what an online commit looks like, and a note on every
      // ordinary sale would be noise that teaches people to stop reading it.
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale(
          'co-1',
          tender: 'cash',
          rungAt: DateTime.utc(2026, 8, 24, 9, 0, 58),
          createdAt: DateTime.utc(2026, 8, 24, 9, 1, 0),
        ),
      ]);
      await _pump(tester, reader, width: 411, role: TenantRole.cashier);

      expect(
        find.byKey(const ValueKey('sales-synced-later-co-1')),
        findsNothing,
      );
    });

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
        totalsCallable: const _TotalsCallable(),
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

    testWidgets('a page turn says which way it went until the page lands', (
      tester,
    ) async {
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
      const next = ValueKey('sales-report-next-page');
      const previous = ValueKey('sales-report-previous-page');
      expect(_text(tester, 'sales-report-page'), '1');
      expect(find.bySemanticsLabel('Showing 1'), findsOne);

      final gate = reader.gate = Completer<void>();
      await tester.tap(find.byKey(next));
      await tester.pump();
      await tester.pump();

      // **Still the page being left**, with the spinner where the press was
      // and the other way waiting. The figure moves when the sales do.
      expect(_text(tester, 'sales-report-page'), '1');
      expect(
        find.descendant(
          of: find.byKey(next),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOne,
      );
      expect(find.bySemanticsLabel('Next page, working'), findsOne);
      expect(tester.widget<PressSurface>(find.byKey(next)).onPressed, isNull);
      expect(
        tester.widget<PressSurface>(find.byKey(previous)).onPressed,
        isNull,
      );

      reader.gate = null;
      gate.complete();
      await tester.pumpAndSettle();

      expect(_text(tester, 'sales-report-page'), '2');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('sales-record-co-1')), findsOneWidget);
      // The second of two sales is the end of the day, and the bar says so.
      expect(find.bySemanticsLabel('Showing 2'), findsOne);
      expect(find.text('· last'), findsOne);
      expect(tester.widget<PressSurface>(find.byKey(next)).onPressed, isNull);
      expect(
        tester.widget<PressSurface>(find.byKey(previous)).onPressed,
        isNotNull,
      );
    });

    testWidgets('a day that fits one page ends with its last card', (
      tester,
    ) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-1', sequence: 1),
      ]);
      await _pump(tester, reader, width: 411, role: TenantRole.cashier);

      expect(find.byKey(const ValueKey('sales-record-co-1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sales-report-next-page')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('sales-report-page')), findsNothing);
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

    testWidgets('opens on the day and member it is handed', (tester) async {
      // What a shift history card does: the report opened on that shift's
      // business date and narrowed to whoever ran it - exactly as if the two
      // filters had been set by hand.
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-3', sequence: 3, soldById: 'user-b'),
        _sale('co-2', sequence: 2, soldById: 'user-b', businessDate: _before),
        _sale('co-1', sequence: 1, businessDate: _before),
      ]);
      await _pump(
        tester,
        reader,
        width: 1024,
        role: TenantRole.manager,
        initialBusinessDate: _before,
        initialStaffId: 'user-b',
      );

      final query = reader.salesQueries.first;
      expect(query.startBusinessDate, _before);
      expect(query.endBusinessDate, _before);
      expect(query.soldById, 'user-b');
      expect(find.byKey(const ValueKey('sales-record-co-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-record-co-1')), findsNothing);
      expect(find.byKey(const ValueKey('sales-record-co-3')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sales-date-filter')),
          matching: find.text(_before),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sales-staff-filter')),
          matching: find.text('Baraka Cashier (user-b)'),
        ),
        findsWidgets,
      );
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
  group('what came back out of the day', () {
    testWidgets('a sale returned in full leaves the list and the takings', (
      tester,
    ) async {
      final reader = _SalesReader(
        <TenantQueryDocumentSnapshot>[
          _sale('co-2', sequence: 2, tender: 'cash'),
          _sale('co-1', tender: 'cash'),
        ],
        // Both units of co-1's only line, so nothing is left of the sale.
        returns: <TenantQueryDocumentSnapshot>[
          _returnRecord('rt-1', saleId: 'co-1'),
        ],
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(
        tester,
        reader,
        width: 1024,
        role: TenantRole.manager,
        totalsCallable: const _TotalsCallable(
          netSales: 91,
          netProfit: 26,
          netTransactions: 3,
          netCashSales: 41,
          netCashTransactions: 0,
          returnsScanned: 1,
        ),
      );

      // The sale that came back is gone; the one that did not is not.
      expect(find.byKey(const ValueKey('sales-record-co-1')), findsNothing);
      expect(find.byKey(const ValueKey('sales-record-co-2')), findsOneWidget);
      // 100.00 taken, 9.00 of it handed back - the sale's *total*, not its
      // line subtotal, so the discount comes off the refund too.
      expect(_text(tester, 'sales-report-revenue'), 'KES 91');
      // Only a sale that came back in full stops being a transaction.
      expect(_text(tester, 'sales-report-transactions'), '3');
      // **The figure is netted and nothing explains it, by decision.** What
      // came back is the Returns record's subject, not this card's.
      expect(find.byKey(const ValueKey('sales-report-returned')), findsNothing);
    });

    testWidgets('a part return badges the sale and takes only its share', (
      tester,
    ) async {
      final reader = _SalesReader(
        <TenantQueryDocumentSnapshot>[_sale('co-1', tender: 'cash')],
        // One of the two units.
        returns: <TenantQueryDocumentSnapshot>[
          _returnRecord('rt-1', saleId: 'co-1', quantity: 1),
        ],
      );

      await _pump(
        tester,
        reader,
        width: 1024,
        role: TenantRole.manager,
        totalsCallable: const _TotalsCallable(
          netSales: 95.50,
          netProfit: 28,
          netCashSales: 45.50,
          returnsScanned: 1,
        ),
      );

      expect(find.byKey(const ValueKey('sales-record-co-1')), findsOneWidget);
      // 500 of a 1000 subtotal came back, and the sale was charged at 900, so
      // the refund is 450 and 450 is what the shop still has.
      expect(_text(tester, 'sales-total-co-1'), 'KES 4.50');
      final badge = tester.widget<StatusBadge>(
        find.byKey(const ValueKey('sales-returned-badge-co-1')),
      );
      expect(badge.label, 'Partly returned');
      expect(badge.status, AppStatus.attention);
      // The badge is the whole of what the card says about the return: the
      // units and the money that came back live on the Returns screen. The
      // returned amount happens to be 4.50 here as well as the net, so one
      // occurrence is exactly the proof that the second figure is gone.
      expect(find.text('KES 4.50'), findsOneWidget);
      expect(_text(tester, 'sales-report-revenue'), 'KES 95.50');
      // A partly returned sale is still a transaction that happened.
      expect(_text(tester, 'sales-report-transactions'), '4');
    });

    testWidgets('a receipt looked up by number is shown however it ended', (
      tester,
    ) async {
      final reader = _SalesReader(
        <TenantQueryDocumentSnapshot>[_sale('co-1', tender: 'cash')],
        returns: <TenantQueryDocumentSnapshot>[
          _returnRecord('rt-1', saleId: 'co-1'),
        ],
      );

      await _pump(tester, reader, width: 1024, role: TenantRole.manager);

      // The day's list has dropped it.
      expect(find.byKey(const ValueKey('sales-record-co-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('sales-report-all-returned')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('sales-receipt-search')),
        '0001',
      );
      await tester.tap(find.byKey(const ValueKey('sales-receipt-submit')));
      await tester.pumpAndSettle();

      // Somebody is holding the paper and asking what happened to it. The
      // answer is the sale, marked, and not "no such receipt".
      expect(find.byKey(const ValueKey('sales-record-co-1')), findsOneWidget);
      expect(
        tester
            .widget<StatusBadge>(
              find.byKey(const ValueKey('sales-returned-badge-co-1')),
            )
            .label,
        'Returned',
      );
      expect(_text(tester, 'sales-total-co-1'), 'KES 0');
    });
  });

  group('a second copy of a receipt', () {
    testWidgets('management is offered one and a cashier is not', (
      tester,
    ) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[_sale('co-1')]);
      final reprinter = _Reprinter();

      await _pump(
        tester,
        reader,
        width: 411,
        role: TenantRole.cashier,
        reprinter: reprinter,
      );
      await tester.tap(find.byKey(const ValueKey('sales-actions-co-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sales-reprint-co-1')), findsNothing);
      expect(find.byKey(const ValueKey('sales-returns-co-1')), findsOneWidget);
    });

    testWidgets('the seller can answer a sale that names no method', (
      tester,
    ) async {
      // **The one write this screen makes to a sale.** The register stopped
      // preselecting a payment method, so a cashier who was never told how the
      // customer paid saves a sale naming none - honest, and useless unless
      // they can answer it afterwards. This is that answer, on the card the old
      // app offered it on, beside Return and Reprint.
      final callable = _TenderCallable();
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[_sale('co-1')]);

      await _pump(
        tester,
        reader,
        width: 411,
        role: TenantRole.cashier,
        tenderCallable: callable,
      );
      await tester.tap(find.byKey(const ValueKey('sales-actions-co-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-set-tender-co-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sale-tender-choice-mpesa')));
      await tester.pumpAndSettle();

      expect(callable.payloads, hasLength(1));
      expect(callable.payloads.single['tenantId'], 'tenant-a');
      expect(callable.payloads.single['saleId'], 'co-1');
      expect(callable.payloads.single['tender'], 'mpesa');
    });

    testWidgets('a recorded method offers a correction, named as one', (
      tester,
    ) async {
      // **The verb changes with the sale.** Filling a blank and correcting a
      // mis-tap are different acts, and a person should know which one they are
      // about to do. Whether the correction is still allowed depends on the
      // shift, which this surface cannot see - the server decides.
      final callable = _TenderCallable();
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-1', tender: 'cash'),
      ]);

      await _pump(
        tester,
        reader,
        width: 411,
        role: TenantRole.cashier,
        tenderCallable: callable,
      );
      await tester.tap(find.byKey(const ValueKey('sales-actions-co-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sales-set-tender-co-1')),
        findsOneWidget,
      );
      expect(find.text('Change payment method'), findsOneWidget);
      expect(find.text('Set payment method'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('sales-set-tender-co-1')));
      await tester.pumpAndSettle();

      // The dialog says what it is replacing, and what bounds the correction.
      expect(
        _text(tester, 'sale-tender-caveat'),
        contains('This sale says Cash'),
      );

      await tester.tap(find.byKey(const ValueKey('sale-tender-choice-mpesa')));
      await tester.pumpAndSettle();

      expect(callable.payloads.single['tender'], 'mpesa');
    });

    testWidgets('a colleague is not offered another cashiers sale', (
      tester,
    ) async {
      // Only the person who was at the counter knows the answer; anybody else
      // would be guessing, and the server refuses them regardless.
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[
        _sale('co-1', soldById: 'user-b'),
      ]);

      await _pump(
        tester,
        reader,
        width: 411,
        role: TenantRole.manager,
        tenderCallable: _TenderCallable(),
      );
      await tester.tap(find.byKey(const ValueKey('sales-actions-co-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sales-set-tender-co-1')), findsNothing);
    });

    testWidgets('no callable leaves the entry off rather than dead', (
      tester,
    ) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[_sale('co-1')]);

      await _pump(tester, reader, width: 411, role: TenantRole.cashier);
      await tester.tap(find.byKey(const ValueKey('sales-actions-co-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sales-set-tender-co-1')), findsNothing);
    });

    testWidgets('a manager reprints, and the sentence names the receipt', (
      tester,
    ) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[_sale('co-1')]);
      final reprinter = _Reprinter();

      await _pump(
        tester,
        reader,
        width: 1024,
        role: TenantRole.manager,
        reprinter: reprinter,
      );
      await tester.tap(find.byKey(const ValueKey('sales-actions-co-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-reprint-co-1')));
      await tester.pumpAndSettle();

      expect(reprinter.sales.single.id, 'co-1');
      // Named by till and sequence, as the row is: a reprint confirmation
      // saying `#0001` on a two-register day names two different receipts.
      final parts = formatCheckoutReceiptNumber(
        deviceId: _deviceId,
        businessDate: _businessDate,
        sequence: 1,
      ).split('-');
      expect(
        snackNotice(tester).message,
        'Receipt ${parts[0]}-${parts[1]}-${parts[3]} reprinted.',
      );
      expect(snackNotice(tester).status, AppStatus.ok);
    });

    testWidgets('a refusal says nothing was printed, and why', (tester) async {
      final reader = _SalesReader(<TenantQueryDocumentSnapshot>[_sale('co-1')]);
      final reprinter = _Reprinter(
        const TenantReceiptReprintReport.refused(
          TenantReceiptReprintCode.unavailable,
        ),
      );

      await _pump(
        tester,
        reader,
        width: 1024,
        role: TenantRole.manager,
        reprinter: reprinter,
      );
      await tester.tap(find.byKey(const ValueKey('sales-actions-co-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-reprint-co-1')));
      await tester.pumpAndSettle();

      expect(
        snackNotice(tester).message,
        'Nothing was printed. A reprint is recorded on the server, so it must '
        'be asked for online.',
      );
      expect(snackNotice(tester).status, AppStatus.problem);
    });
  });

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
      // **The callable is supplied, and that is not incidental.** Without one
      // there are no takings to read, and this used to draw a placeholder for
      // them anyway - promising a band that then rendered as nothing and
      // vanished. See the case below.
      await _pumpUnsettled(
        tester,
        role: TenantRole.owner,
        totalsCallable: const _TotalsCallable(),
      );

      expect(find.byKey(const ValueKey('sales-report-skeleton')), findsOne);
      expect(
        find.byKey(const ValueKey('sales-report-totals-skeleton')),
        findsOne,
      );

      await tester.pumpAndSettle();
    });

    testWidgets('no totals callable means no placeholder for them', (
      tester,
    ) async {
      // A placeholder is a promise that something is coming. Nothing is: this
      // panel was given no way to read takings, so the band never appears and
      // the loading state must not pretend otherwise.
      await _pumpUnsettled(tester, role: TenantRole.owner);

      expect(find.byKey(const ValueKey('sales-report-skeleton')), findsOne);
      expect(
        find.byKey(const ValueKey('sales-report-totals-skeleton')),
        findsNothing,
      );

      await tester.pumpAndSettle();
    });

    // **The report of 2026-08-27, in one assertion**: *if in a page we have
    // some data from offline and some from online, the online data makes the
    // offline data come late*. The day's sales are a Firestore read and serve
    // from its cache; the takings are a callable and cannot be served offline
    // at all. They used to be one chained read, so the sales waited for the
    // takings - which offline is a wait for something that never arrives.
    testWidgets('the day\'s sales draw while the takings are still reading', (
      tester,
    ) async {
      final held = Completer<Object?>();
      addTearDown(() {
        if (!held.isCompleted) held.complete(<String, Object?>{});
      });
      await _pumpUnsettled(
        tester,
        role: TenantRole.owner,
        totalsCallable: _HeldTotalsCallable(held),
        reader: _SalesReader(<TenantQueryDocumentSnapshot>[
          _sale('co-1', tender: 'cash'),
        ]),
      );
      // Enough frames for Firestore to answer. The callable is still held.
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        find.byKey(const ValueKey('sales-report-skeleton')),
        findsNothing,
        reason: 'The day answered, so its sales are drawn, not placeheld.',
      );
      expect(
        find.byKey(const ValueKey('sales-report-totals-skeleton')),
        findsOne,
        reason: 'The takings have not answered, so only they are placeheld.',
      );

      held.complete(<String, Object?>{});
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

  testWidgets('the server netting wins over this screen doing its own', (
    tester,
  ) async {
    // **Two implementations of one money rule drift.** This screen netted
    // returns long before the rest of the reporting stack did, and the
    // callable now joins them itself - from Firestore rather than from
    // whatever this device cached. Where the server states a net figure, that
    // is the figure, and the local arithmetic is only the fallback for a
    // deployment too old to send one.
    final reader = _SalesReader(const <TenantQueryDocumentSnapshot>[]);

    await _pump(
      tester,
      reader,
      width: 1024,
      role: TenantRole.manager,
      totalsCallable: _NettingTotalsCallable(),
    );

    // 90, the server's net - not 100 gross, and not a locally netted figure,
    // since this reader holds no returns at all and would have left it at 100.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-report-revenue')))
          .data,
      contains('90'),
    );
    // Not the gross figure either, which is what a screen ignoring the new
    // block would have drawn.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sales-report-revenue')))
          .data,
      isNot(contains('100')),
    );
  });
}

/// The panel on its first frame, before the guard's read has answered.
///
/// `_pump` settles, which is what every other case here wants; this one stops
/// on the loading state deliberately, because that is the state under test.
Future<void> _pumpUnsettled(
  WidgetTester tester, {
  required TenantRole role,
  SalesTotalsCallable? totalsCallable,
  _SalesReader? reader,
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
            reader:
                reader ?? _SalesReader(const <TenantQueryDocumentSnapshot>[]),
            reportReader:
                reader ?? _SalesReader(const <TenantQueryDocumentSnapshot>[]),
            totalsCallable: totalsCallable,
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
  TenantReceiptReprinter? reprinter,
  SetSaleTenderCallable? tenderCallable,
  String? initialBusinessDate,
  String? initialStaffId,
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
            reprinter: reprinter,
            tenderCallable: tenderCallable,
            clock: () => DateTime.utc(2026, 8, 24, 12),
            pageSize: pageSize,
            initialBusinessDate: initialBusinessDate,
            initialStaffId: initialStaffId,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A totals callable that answers only when the test says so.
///
/// The point of the split it proves: a callable is the one source on this page
/// that cannot be served from a cache, so a test that wants to watch the rest
/// of the page arrive without it has to be able to stop it arriving.
final class _TenderCallable implements SetSaleTenderCallable {
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    return <String, Object?>{'saleId': payload['saleId']};
  }
}

final class _HeldTotalsCallable implements SalesTotalsCallable {
  _HeldTotalsCallable(this._gate);

  final Completer<Object?> _gate;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    await _gate.future;
    return _TotalsCallable().call(payload);
  }
}

/// A server that nets the period's returns itself.
///
/// The gross half is `_TotalsCallable`'s; the `net` half says a return of 10
/// came back, and names one fewer cash sale.
final class _NettingTotalsCallable implements SalesTotalsCallable {
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
    'net': <String, Object?>{
      'sales': 90,
      'profit': 26,
      'transactions': 3,
      'incompleteCostLineCount': 0,
    },
    'netByTender': <String, Object?>{
      'cash': <String, Object?>{'sales': 40, 'transactions': 0},
      'mpesa': <String, Object?>{'sales': 30, 'transactions': 1},
      'card': <String, Object?>{'sales': 15, 'transactions': 1},
      'unrecorded': <String, Object?>{'sales': 5, 'transactions': 1},
      'other': <String, Object?>{'sales': 0, 'transactions': 0},
    },
    'returnsScanned': 1,
  };
}

/// The day's takings as the current server states them.
///
/// **`net` is not optional** - `SalesComparison.net` is required in
/// `reports.ts`, so a fixture without one is not an older deployment to
/// tolerate but an answer this app refuses (#103). The defaults net to the
/// gross figures, which is what a day nothing came back from looks like; a
/// test with a return states the netted figures the server would have sent.
final class _TotalsCallable implements SalesTotalsCallable {
  const _TotalsCallable({
    this.netSales = 100,
    this.netProfit = 30,
    this.netTransactions = 4,
    this.netCashSales = 50,
    this.netCashTransactions = 1,
    this.returnsScanned = 0,
  });

  final double netSales;
  final double netProfit;
  final int netTransactions;

  /// The returned sales in these fixtures are all cash, so the cash bucket is
  /// the only one that moves and the five still sum to [netSales].
  final double netCashSales;
  final int netCashTransactions;
  final int returnsScanned;

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
    'net': <String, Object?>{
      'sales': netSales,
      'profit': netProfit,
      'transactions': netTransactions,
      'incompleteCostLineCount': 0,
    },
    'netByTender': <String, Object?>{
      'cash': <String, Object?>{
        'sales': netCashSales,
        'transactions': netCashTransactions,
      },
      'mpesa': <String, Object?>{'sales': 30, 'transactions': 1},
      'card': <String, Object?>{'sales': 15, 'transactions': 1},
      'unrecorded': <String, Object?>{'sales': 5, 'transactions': 1},
      'other': <String, Object?>{'sales': 0, 'transactions': 0},
    },
    'returnsScanned': returnsScanned,
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

/// The panel prints local time, and this suite must not assume a zone.
String _localClock(DateTime instant) {
  final local = instant.toLocal();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${pad(local.hour)}:${pad(local.minute)}';
}

TenantQueryDocumentSnapshot _sale(
  String id, {
  int sequence = 1,
  String tenantId = 'tenant-a',
  String soldById = 'user-a',
  String? tender,
  String businessDate = _businessDate,
  String deviceId = _deviceId,
  DateTime? rungAt,
  DateTime? createdAt,
}) {
  final data = <String, Object?>{
    'checkoutId': id,
    'tenantId': tenantId,
    'soldById': soldById,
    'payloadHash': _hash,
    // #105: an absent tender no longer implies v1. A v2 sale may carry none -
    // that is the question going unanswered.
    'payloadSchemaVersion': 2,
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
    'createdAt': Timestamp.fromDate(
      createdAt ?? DateTime.utc(2026, 8, 24, 9, sequence),
    ),
    if (rungAt != null)
      'clientCreatedAtMs': rungAt.toUtc().millisecondsSinceEpoch,
  };
  return TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/sales/$id',
    data: data,
  );
}

/// One pending return against [saleId], on the sale's own trading day.
TenantQueryDocumentSnapshot _returnRecord(
  String id, {
  required String saleId,
  int quantity = 2,
  String productId = 'product-1',
  String businessDate = _businessDate,
}) => TenantQueryDocumentSnapshot(
  path: 'tenants/tenant-a/returns/$id',
  data: <String, Object?>{
    'returnId': id,
    'recordedOn': '2026-07-31',
    'tenantId': 'tenant-a',
    'saleId': saleId,
    'businessDate': businessDate,
    'createdBy': 'user-a',
    'status': 'pending',
    'reason': 'Damaged bottle',
    'itemsReturned': <Object?>[
      <String, Object?>{'productId': productId, 'quantity': quantity},
    ],
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 24, 10)),
  },
);

/// Records every sale a reprint was asked for, and answers as told.
final class _Reprinter implements TenantReceiptReprinter {
  _Reprinter([this._report = const TenantReceiptReprintReport.printed()]);

  final TenantReceiptReprintReport _report;
  final List<TenantSale> sales = <TenantSale>[];

  @override
  Future<TenantReceiptReprintReport> reprint({
    required TenantSession session,
    required TenantSale sale,
  }) async {
    sales.add(sale);
    return _report;
  }
}

/// The string one keyed `Text` is drawing, wherever it sits.
String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

final class _SalesReader
    implements TenantDataReader, TenantSalesHistoryQueryReader {
  _SalesReader(
    this.sales, {
    this.returns = const <TenantQueryDocumentSnapshot>[],
  });

  final List<TenantQueryDocumentSnapshot> sales;

  /// Holds every sales read until it completes, so a page turn can be watched
  /// while its page is still being read. Null answers at once.
  Completer<void>? gate;

  /// The returns filed against those sales, which the day's list and the
  /// takings band both net themselves against.
  final List<TenantQueryDocumentSnapshot> returns;
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
    // A return is priced against the sale it came out of, which the offsets
    // loader reads by exact path - `allow get` on sales is business-wide.
    for (final sale in sales) {
      if (sale.path == path) {
        return TenantDocumentSnapshot(path: path, data: sale.data);
      }
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
    if (query.collectionPath == 'tenants/tenant-a/returns') {
      final matches =
          returns
              .where(
                (snapshot) => query.equalityFilters.entries.every(
                  (filter) => snapshot.data[filter.key] == filter.value,
                ),
              )
              .toList()
            ..sort((left, right) => right.path.compareTo(left.path));
      return matches.take(query.limit).toList();
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
    if (gate case final held?) await held.future;
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
