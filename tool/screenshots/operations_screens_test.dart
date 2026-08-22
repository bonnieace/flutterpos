/// Every operational route: the till, the catalog, stock, reporting, sales,
/// returns, and the activity log.
///
/// Each one is the real route class the composition root pushes, given the same
/// readers and callables `lib/main.dart` gives it - so what a picture shows is
/// what the screen decides to show, including which controls its role is
/// offered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/audit/audit.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/returns/returns.dart';
import 'package:flutter_application_1/sales/sales.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'harness.dart';

/// Scrolls one keyed control fully into view, presses it, and settles.
///
/// **`ensureVisible` and not only `scrollUntilVisible`**: the latter stops when
/// the widget is *built*, which on a long `ListView` route can leave it below
/// the fold, and a tap there misses without failing. That is how every
/// `mobile/19-correct-a-product` capture came to photograph the list rather than
/// the dialog the case exists for.
Future<void> _press(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// One canonical sale, decoded the way every sales surface decodes one.
TenantSale _sale(String saleId) => TenantSale.fromDocument(
  path: 'tenants/$seedTenantId/sales/$saleId',
  data: seedSales()[saleId]!,
);

void main() {
  // -------------------------------------------------------------------------
  // The till
  // -------------------------------------------------------------------------

  // **The till is captured in all three bands, and the tablet one is why.**
  // Until 2026-08-22 `showsTwoPanes` read §4.1's `expanded` floor, so the till
  // hid its cart behind a button on every tablet - and no screenshot anywhere
  // rendered it at a tablet width, so the one surface a cashier uses all day
  // had its most-affected layout covered by nothing at all. `OPEN_QUESTIONS.md`
  // item 21 moved the boundary to `medium`; this is what proves it.
  screenshotCase(
    '14-new-sale',
    build: () => inSession(
      TenantCheckoutScreen(cache: FakeCatalogSource(), drafts: FakeDraftSink()),
      controller: seedSession(role: TenantRole.cashier, uid: cashierUid),
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '15-new-sale-with-a-cart',
    build: () => inSession(
      TenantCheckoutScreen(cache: FakeCatalogSource(), drafts: FakeDraftSink()),
      controller: seedSession(role: TenantRole.cashier, uid: cashierUid),
    ),
    afterPump: (tester) async {
      for (final id in const <String>[
        'pd-bread-white',
        'pd-mandazi',
        'pd-soda-300',
      ]) {
        final tile = find.byKey(ValueKey('checkout-product-$id'));
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }
      // On a phone the cart is a sheet rather than a second pane, so it has to
      // be opened to be seen. On a desktop the control is not there at all.
      final openCart = find.byKey(const ValueKey('checkout-open-cart'));
      if (openCart.evaluate().isNotEmpty) {
        await tester.tap(openCart);
      }
    },
    viewports: responsiveViewports,
  );

  // **The browse screen with a sale already going, which nothing photographed
  // until Phase 03.** `15` opens the sheet on a phone, so the compact tile's
  // count badge and its action-coloured border - the two things that say *this
  // product is already in the sale* on the one layout where the cart is behind
  // a tap - appeared in none of the 405 images. Compact widths only: on a till
  // screen the cart pane states the same fact in full, and the tile does not
  // draw a badge at all.
  screenshotCase(
    '14b-new-sale-browsing-with-a-cart',
    build: () => inSession(
      TenantCheckoutScreen(cache: FakeCatalogSource(), drafts: FakeDraftSink()),
      controller: seedSession(role: TenantRole.cashier, uid: cashierUid),
    ),
    afterPump: (tester) async {
      for (final id in const <String>['pd-bread-white', 'pd-bread-white']) {
        final tile = find.byKey(ValueKey('checkout-product-$id'));
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }
    },
    viewports: const <ScreenshotViewport>[compactWideViewport, mobileViewport],
  );

  // The state this composition root's wiring made reachable: the sale is
  // durable and the receipt is not on paper, said as two notices because two
  // different things happened.
  screenshotCase(
    '15b-sale-saved-but-not-printed',
    build: () => inSession(
      TenantCheckoutScreen(
        cache: FakeCatalogSource(),
        drafts: FakeDraftSink(printFailure: PrinterTransportCode.unreachable),
      ),
      controller: seedSession(role: TenantRole.cashier, uid: cashierUid),
    ),
    afterPump: (tester) async {
      await _press(tester, 'checkout-product-pd-bread-white');
      // On a phone the tender chips and the save live in the cart sheet, so it
      // has to be opened before either can be pressed. On a desktop the cart is
      // the second pane and the control is not there at all.
      final openCart = find.byKey(const ValueKey('checkout-open-cart'));
      if (openCart.evaluate().isNotEmpty) {
        await tester.tap(openCart);
        await tester.pumpAndSettle();
      }
      await _press(tester, 'checkout-tender-cash');
      await _press(tester, 'checkout-save');
    },
  );

  screenshotCase(
    '16-checkout-settings',
    build: () => inSession(
      TenantCheckoutConfigurationScreen(
        reader: FakeTenantReader.business(),
        writer: FakeCheckoutConfigurationWriter(),
      ),
    ),
  );

  // **The same route with no writer, and until 2026-08-22 nothing photographed
  // it.** `16` above injects one, so the whole `!canPublish` branch - the notice
  // and the absent form - had never appeared in any of the 361 images. That is
  // how the notice came to be a bare `Text` where its four siblings are `info`
  // callouts, and it is the same trap `18b-catalog-notice` records one screen
  // over: a conditional section invisible in every capture is not covered.
  //
  // The counterpart of `36c-printer-settings-read-only`, which is the sibling
  // that *was* photographed and stayed right.
  screenshotCase(
    '16b-checkout-settings-read-only',
    build: () => inSession(
      TenantCheckoutConfigurationScreen(reader: FakeTenantReader.business()),
    ),
  );

  // -------------------------------------------------------------------------
  // Catalog and stock
  // -------------------------------------------------------------------------

  screenshotCase(
    '17-read-only-catalog',
    build: () {
      final reader = FakeTenantReader.business();
      return inSession(
        TenantCatalogScreen(
          reader: reader,
          productStockRoute: (product) =>
              TenantProductStockScreen(reader: reader, product: product),
          productStockRoles: TenantProductStockRepository.allowedRoles,
          adjustmentFeedRoute: () =>
              TenantStockAdjustmentFeedScreen(reader: reader),
          adjustmentFeedRoles: TenantStockAdjustmentFeedRepository.allowedRoles,
          movementFeedRoute: () => TenantStockMovementFeedScreen(
            reader: reader,
            groupReader: reader,
          ),
          movementFeedRoles: TenantStockMovementFeedRepository.allowedRoles,
        ),
      );
    },
  );

  screenshotCase(
    '18-manage-catalog',
    build: () {
      final reader = FakeTenantReader.business();
      return inSession(
        TenantCatalogManagementScreen(
          reader: reader,
          writer: FakeCatalogWriter(),
          updateCallable: FakeCallable(),
          bulkRoute: (_) => TenantBulkCatalogScreen(
            reader: reader,
            batchCallable: FakeCallable(),
            importCallable: FakeCallable(),
          ),
        ),
      );
    },
  );

  // **No picture had ever shown a notice on any screen.** Seven surfaces report
  // what a write did, and every one of those notices appears only *after* a
  // write — so all 225 images showed the state before anybody pressed anything.
  // It is the "a conditional section that is invisible in every capture is not
  // covered" trap again, and structural rather than a fixture gap this time: a
  // screen-level capture has to drive a form and a confirmation to reach one.
  // This is that, on the surface with the most notice branches in the app. The
  // other statuses are covered by the `Callout` matrix; what no matrix can show
  // is how one reads *in place*, above a page of forms.
  // **The only picture of the two catalog read-only notices, and of the pair
  // together.** Both render in this state and they answer different questions -
  // one says the catalog cannot be changed at all, the other stands where the
  // form a person came here to fill in would be - so a picture of one would
  // misrepresent the page. `18` and `18b` both inject a writer, so neither had
  // ever drawn either.
  //
  // No `updateCallable` and no `bulkRoute` either: a build with no writer has no
  // correction path and no bulk route, and passing them would photograph a
  // combination the composition root does not produce.
  screenshotCase(
    '18c-manage-catalog-read-only',
    build: () => inSession(
      TenantCatalogManagementScreen(reader: FakeTenantReader.business()),
    ),
  );

  screenshotCase(
    '18b-catalog-notice',
    build: () {
      final reader = FakeTenantReader.business();
      return inSession(
        TenantCatalogManagementScreen(
          reader: reader,
          writer: FakeCatalogWriter(),
          updateCallable: FakeCallable(),
        ),
      );
    },
    afterPump: (tester) async {
      final field = find.byKey(
        const ValueKey('catalog-management-category-name'),
      );
      await tester.scrollUntilVisible(
        field,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      // `scrollUntilVisible` stops when a widget is built rather than when it is
      // on screen, which is the trap `19-correct-a-product` was quietly failing.
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'Frozen');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('catalog-management-add-category')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('catalog-management-confirm')),
      );
      await tester.pumpAndSettle();
      // The notice lands near the top of the route, above the forms, so the page
      // is scrolled back to it rather than photographed where the tap left it.
      await tester.ensureVisible(
        find.byKey(const ValueKey('catalog-management-notice')),
      );
      // **`Frozen` is deliberately not in the chip strip in this picture.**
      // `FakeCatalogWriter` answers `committed` without writing to the fake
      // reader, so the re-read the panel correctly performs returns the same
      // three seeded categories. That is the fixture rather than the screen, and
      // it is said here so nobody reads the image as a defect.
    },
  );

  screenshotCase(
    '19-correct-a-product',
    build: () => inSession(
      TenantCatalogManagementScreen(
        reader: FakeTenantReader.business(),
        writer: FakeCatalogWriter(),
        updateCallable: FakeCallable(),
      ),
    ),
    afterPump: (tester) async {
      final edit = find.byKey(
        const ValueKey('catalog-management-edit-pd-bread-white'),
      );
      // The route is one long `ListView`, so a row below the fold has not been
      // built yet and `ensureVisible` has nothing to scroll to. Scrolling until
      // it appears is the only way to reach it, which is also what a person
      // does.
      // The route's own list is named explicitly: the category strip inside it
      // scrolls too, and `scrollUntilVisible` insists on exactly one candidate.
      await tester.scrollUntilVisible(
        edit,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      // **`scrollUntilVisible` stops when the widget is built, not when it is on
      // screen**, so at 411 this tap was landing below the fold and missing:
      // every `mobile/19-correct-a-product` capture ever taken photographed the
      // list rather than the dialog the case exists for. Found 2026-08-14 by the
      // catalog sweep, which hit the same thing in a widget test on the same
      // route. The same class as the seeded-record trap - a capture case whose
      // picture is not of the state it names.
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
    },
  );

  screenshotCase(
    '20-bulk-changes-and-import',
    build: () => inSession(
      TenantBulkCatalogScreen(
        reader: FakeTenantReader.business(),
        batchCallable: FakeCallable(),
        importCallable: FakeCallable(),
      ),
    ),
  );

  // **The report, which nothing had ever photographed.** Its rows carry §2.1
  // statuses as of 2026-08-14 and a report genuinely mixes them, so one picture
  // of an all-corrected report would show the case the badge is least useful in.
  // `FakeBulkCatalogCallable` answers one row `unchanged` and one `failed`;
  // `FakeCallable` cannot be used here at all, because the strict decoder
  // reconciles the answer against the page it sent.
  for (final committed in <bool>[false, true]) {
    screenshotCase(
      committed ? '20c-bulk-report-committed' : '20b-bulk-report-previewed',
      build: () => inSession(
        TenantBulkCatalogScreen(
          reader: FakeTenantReader.business(),
          batchCallable: FakeBulkCatalogCallable(),
          importCallable: FakeCallable(),
          requestIdFactory: () => 'pb-dev-0001',
        ),
      ),
      afterPump: (tester) async {
        // Top to bottom, which is both what a person does and the only order
        // that works: `scrollUntilVisible` drives one direction, and a `ListView`
        // has already disposed the category strip by the time three products
        // have been ticked.
        await _press(tester, 'bulk-catalog-category-cat-drinks');
        for (final id in const <String>[
          'pd-bar-soap-blue',
          'pd-bread-white',
          'pd-charcoal-2kg',
        ]) {
          await _press(tester, 'bulk-catalog-select-$id');
        }
        await _press(tester, 'bulk-catalog-preview');
        if (!committed) return;
        // The commit is the only way to photograph `ok`: a previewed row is
        // `attention`, because nothing has been written and §2.1 gives `ok` the
        // meaning "confirmed".
        await _press(tester, 'bulk-catalog-commit');
        await _press(tester, 'bulk-catalog-confirm');
      },
    );
  }

  screenshotCase(
    '21-product-stock',
    build: () => inSession(
      TenantProductStockScreen(
        reader: FakeTenantReader.business(),
        product: seedProduct('pd-bread-white'),
        actions: TenantStockActions(adjustCallable: FakeCallable()),
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
  );

  // **The exception report on 21 has never been in a picture.** The seeded stock
  // difference is filed against `pd-milk-500` and the capture above opens
  // `pd-bread-white`, so every screenshot of that route since it was written has
  // shown the branch where reconciliation found nothing - which is exactly the
  // "a fixture that hides the case the component exists for" trap the stock
  // family recorded. This is the same route on the one seeded product that has a
  // difference recorded against it.
  screenshotCase(
    '21b-product-stock-differences',
    build: () => inSession(
      TenantProductStockScreen(
        reader: FakeTenantReader.business(),
        product: seedProduct('pd-milk-500'),
        actions: TenantStockActions(adjustCallable: FakeCallable()),
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
  );

  screenshotCase(
    '22-stock-corrections',
    build: () => inSession(
      TenantStockAdjustmentFeedScreen(reader: FakeTenantReader.business()),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
  );

  screenshotCase(
    '23-stock-movements',
    build: () {
      final reader = FakeTenantReader.business();
      return inSession(
        TenantStockMovementFeedScreen(
          reader: reader,
          groupReader: reader,
          productLedgerRoute: (productId) =>
              TenantProductLedgerScreen(reader: reader, productId: productId),
        ),
        controller: seedSession(role: TenantRole.manager, uid: managerUid),
      );
    },
  );

  screenshotCase(
    '24-one-product-ledger',
    build: () => inSession(
      TenantProductLedgerScreen(
        reader: FakeTenantReader.business(),
        productId: 'pd-bread-white',
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
  );

  // -------------------------------------------------------------------------
  // Reporting
  // -------------------------------------------------------------------------

  screenshotCase(
    '25-daily-summary',
    build: () {
      final reader = FakeTenantReader.business();
      return inSession(
        TenantDailySummaryScreen(
          reader: reader,
          reconciliationRoute: (businessDate) =>
              TenantReconciliationStatusScreen(
                reader: reader,
                businessDate: businessDate,
                actions: fakeReconciliationActions(),
              ),
          reconciliationRoles:
              TenantReconciliationStatusRepository.allowedRoles,
          salesTotalsRoute: () => TenantSalesTotalsScreen(
            callable: FakeCallable(seedSalesTotalsResponse()),
            reader: reader,
          ),
          salesTotalsRoles: TenantSalesTotalsGateway.allowedRoles,
        ),
      );
    },
  );

  screenshotCase(
    '26-sales-totals',
    build: () => inSession(
      TenantSalesTotalsScreen(
        callable: FakeCallable(seedSalesTotalsResponse()),
        reader: FakeTenantReader.business(),
      ),
    ),
  );

  screenshotCase(
    '27-reconciliation-status',
    build: () => inSession(
      TenantReconciliationStatusScreen(
        reader: FakeTenantReader.business(),
        businessDate: seedBusinessDate(),
        actions: fakeReconciliationActions(),
      ),
    ),
  );

  // **The day page's second stat tile has never been in a picture.** The seeded
  // intake has always recorded a clean day, so `hasInvalidSaleLines` was false
  // in every capture and the tile that counts the lines the server could not use
  // - plus the sentence under the row saying they moved no stock and count
  // towards no profit - existed only in a widget test. This is the same route on
  // a day that has some, which is also the only way to see a two-tile `StatRow`
  // reflow on a phone.
  screenshotCase(
    '27b-reconciliation-unusable-lines',
    build: () => inSession(
      TenantReconciliationStatusScreen(
        reader: FakeTenantReader.business(
          extraDocuments: <String, Map<String, Object?>>{
            'tenants/$seedTenantId/reconciliation_dirty_days/'
                '${seedBusinessDate()}': seedReconciliationIntake(
              businessDate: seedBusinessDate(),
              invalidLineCount: 4,
            ),
          },
        ),
        businessDate: seedBusinessDate(),
        actions: fakeReconciliationActions(),
      ),
    ),
  );

  screenshotCase(
    '28-reconciliation-differences',
    build: () => inSession(
      TenantReconciliationAnomalyScreen(
        reader: FakeTenantReader.business(),
        actions: fakeReconciliationActions(),
      ),
    ),
  );

  screenshotCase(
    '29-one-reconciliation-run',
    build: () => inSession(
      TenantReconciliationRunScreen(
        reader: FakeTenantReader.business(),
        jobId: 'rj_000001',
      ),
    ),
  );

  screenshotCase(
    '30-shift-corrections',
    build: () => inSession(
      TenantShiftAmendmentScreen(reader: FakeTenantReader.business()),
    ),
  );

  // -------------------------------------------------------------------------
  // Sales, returns, and the trail
  // -------------------------------------------------------------------------

  screenshotCase(
    '31-find-a-receipt',
    build: () => inSession(
      TenantReceiptLookupScreen(
        reader: FakeTenantReader.business(),
        returnActions: fakeReturnActions(),
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
  );

  screenshotCase(
    '31b-a-receipt-found',
    build: () => inSession(
      TenantReceiptLookupScreen(
        reader: FakeTenantReader.business(),
        returnActions: fakeReturnActions(),
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
    afterPump: (tester) async {
      await tester.enterText(
        find.byType(TextField).first,
        formatCheckoutReceiptNumber(
          deviceId: seedDeviceId,
          businessDate: seedBusinessDate(),
          sequence: 1,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find receipt'));
    },
  );

  screenshotCase(
    '32-shift-history',
    build: () => inSession(
      TenantShiftHistoryScreen(
        reader: FakeTenantReader.business(),
        returnActions: fakeReturnActions(),
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
  );

  screenshotCase(
    '33-shift-sales',
    build: () => inSession(
      TenantSaleHistoryScreen(
        reader: FakeTenantReader.business(),
        request: TenantShiftSaleHistoryRequest(
          shift: TenantSaleShiftScope(
            shiftId: 'shift-morning',
            staffId: cashierUid,
            deviceId: seedDeviceId,
            businessDate: seedBusinessDate(),
          ),
          recordedTransactionCount: 2,
          recordedTotalSalesMinor: 44000,
          countedCashMinor: 44000,
        ),
        returnActions: fakeReturnActions(),
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
  );

  screenshotCase(
    '34-returns-on-a-sale',
    build: () => inSession(
      TenantSaleReturnsScreen(
        reader: FakeTenantReader.business(),
        request: TenantSaleReturnsRequest(sale: _sale('co-1')),
        actions: fakeReturnActions(),
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
  );

  screenshotCase(
    '35-activity-log',
    build: () => inSession(
      TenantAuditLogScreen(reader: FakeTenantReader.business()),
      controller: seedSession(role: TenantRole.admin, uid: adminUid),
    ),
  );
}
