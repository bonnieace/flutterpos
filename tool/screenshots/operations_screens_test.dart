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

/// One canonical sale, decoded the way every sales surface decodes one.
TenantSale _sale(String saleId) => TenantSale.fromDocument(
  path: 'tenants/$seedTenantId/sales/$saleId',
  data: seedSales()[saleId]!,
);

void main() {
  // -------------------------------------------------------------------------
  // The till
  // -------------------------------------------------------------------------

  screenshotCase(
    '14-new-sale',
    build: () => inSession(
      TenantCheckoutScreen(
        cache: FakeCatalogSource(),
        drafts: FakeDraftSink(),
      ),
      controller: seedSession(role: TenantRole.cashier, uid: cashierUid),
    ),
  );

  screenshotCase(
    '15-new-sale-with-a-cart',
    build: () => inSession(
      TenantCheckoutScreen(
        cache: FakeCatalogSource(),
        drafts: FakeDraftSink(),
      ),
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
          reconciliationRoles: TenantReconciliationStatusRepository.allowedRoles,
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
