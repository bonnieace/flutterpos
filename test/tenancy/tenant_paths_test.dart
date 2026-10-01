import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tenant ID validation', () {
    test('accepts safe Firestore document IDs', () {
      for (final tenantId in <String>[
        'abc123',
        'tenant-a',
        'tenant_A',
        '企業-42',
      ]) {
        expect(isValidTenantId(tenantId), isTrue);
        expect(validateTenantId(tenantId), tenantId);
      }
    });

    test(
      'rejects paths, whitespace, controls, dot segments, and oversize IDs',
      () {
        final invalidIds = <String>[
          '',
          ' ',
          ' tenant-a',
          'tenant-a ',
          '.',
          '..',
          'tenant/a',
          'tenant\nname',
          'a' * 1501,
        ];

        for (final tenantId in invalidIds) {
          expect(isValidTenantId(tenantId), isFalse, reason: tenantId);
          expect(
            () => validateTenantId(tenantId),
            throwsArgumentError,
            reason: tenantId,
          );
        }
        expect(isValidTenantId(42), isFalse);
        expect(isValidTenantId(null), isFalse);
      },
    );
  });

  group('TenantPaths', () {
    test('every business collection is rooted below the exact tenant', () {
      final paths = TenantPaths('tenant-a');
      final expected = <TenantCollection, String>{
        TenantCollection.products: 'tenants/tenant-a/products',
        TenantCollection.categories: 'tenants/tenant-a/categories',
        TenantCollection.sales: 'tenants/tenant-a/sales',
        TenantCollection.shifts: 'tenants/tenant-a/shifts',
        TenantCollection.returns: 'tenants/tenant-a/returns',
        TenantCollection.staff: 'tenants/tenant-a/staff',
        TenantCollection.configuration: 'tenants/tenant-a/configuration',
        TenantCollection.subscription: 'tenants/tenant-a/subscription',
        TenantCollection.auditLogs: 'tenants/tenant-a/audit_logs',
        // The business-wide manual correction record. Added deliberately as
        // part of the guarded adjustment feed; `adjustStock` is the only
        // writer and the client only ever reads it.
        TenantCollection.stockAdjustments: 'tenants/tenant-a/stock_adjustments',
        // Server-regenerated daily reporting. Added deliberately as part of the
        // guarded daily summary; the client only ever reads it.
        TenantCollection.dailyMetrics: 'tenants/tenant-a/daily_metrics',
        // The reconciliation work behind those figures, and the per-day record
        // of whether they are current. Added deliberately as part of the
        // guarded reconciliation status surface; the client only ever reads
        // them and can never queue, retry, or cancel a run.
        TenantCollection.reconciliationJobs:
            'tenants/tenant-a/reconciliation_jobs',
        TenantCollection.reconciliationDirtyDays:
            'tenants/tenant-a/reconciliation_dirty_days',
        // The differences that work found and could not resolve. Added
        // deliberately as part of the guarded anomaly surface; the same
        // reconciliation workers are the only writers, and nothing the client
        // can reach changes stock, a shift, or a sale.
        TenantCollection.reconciliationAnomalies:
            'tenants/tenant-a/reconciliation_anomalies',
        // How many of those differences are still open, in one document the
        // server recomputes at the end of every completed run. Added
        // deliberately so a launcher can badge a figure without listing the
        // collection above to count it - those documents are keyed by digest
        // and can be neither ordered nor counted cheaply. Read-only to every
        // client.
        TenantCollection.reconciliationSummary:
            'tenants/tenant-a/reconciliation_summary',
        // The immutable trail of every closed shift whose summary was
        // corrected. Added deliberately as part of the guarded correction
        // trail; `amendShiftSummary` is the only writer, it only ever appends,
        // and the client can never create, change, or erase one.
        TenantCollection.shiftAmendments: 'tenants/tenant-a/shift_amendments',
        // What the business spent outside the cost of its stock. Added
        // deliberately: the client is the only writer, a record is immutable
        // once written, and the only permitted change is a void that freezes
        // every other key. Owner and administrator only, read as well as
        // write, matching the roles a profit figure is shown to.
        TenantCollection.expenses: 'tenants/tenant-a/expenses',
        // Who stock is bought from, what each delivery brought in, and what
        // each production batch cost. Added deliberately: all three are
        // server-written, readable by owners, admins and managers, and a
        // supplier is never deleted because deliveries name it.
        TenantCollection.suppliers: 'tenants/tenant-a/suppliers',
        TenantCollection.supplierDeliveries:
            'tenants/tenant-a/supplier_deliveries',
        TenantCollection.productionBatches:
            'tenants/tenant-a/production_batches',
        // Who the business sells to, and what became of every WhatsApp
        // receipt. Added deliberately on 2026-10-01: customers are
        // server-written (one phone number each) and read by every member,
        // because the till chooses them; receipt deliveries are written by the
        // delivery worker and the webhook alone and read by management.
        TenantCollection.customers: 'tenants/tenant-a/customers',
        TenantCollection.receiptDeliveries:
            'tenants/tenant-a/receipt_deliveries',
        // What customers paid back on credit, written only by
        // `recordCustomerPayment`. Added deliberately on 2026-10-01.
        TenantCollection.customerPayments:
            'tenants/tenant-a/customer_payments',
      };

      expect(TenantPaths.businessCollections.toSet(), expected.keys.toSet());
      for (final entry in expected.entries) {
        final actual = paths.collectionPath(entry.key);
        expect(actual, entry.value);
        expect(paths.owns(actual), isTrue);
        expect(actual.startsWith('${paths.root}/'), isTrue);
      }
    });

    test('named collection getters preserve the same scope', () {
      final paths = TenantPaths('tenant-a');

      expect(paths.products, 'tenants/tenant-a/products');
      expect(paths.categories, 'tenants/tenant-a/categories');
      expect(paths.sales, 'tenants/tenant-a/sales');
      expect(paths.shifts, 'tenants/tenant-a/shifts');
      expect(paths.returns, 'tenants/tenant-a/returns');
      expect(paths.staff, 'tenants/tenant-a/staff');
      expect(paths.configuration, 'tenants/tenant-a/configuration');
      expect(paths.subscription, 'tenants/tenant-a/subscription');
      expect(paths.auditLogs, 'tenants/tenant-a/audit_logs');
      expect(paths.stockAdjustments, 'tenants/tenant-a/stock_adjustments');
      expect(paths.dailyMetrics, 'tenants/tenant-a/daily_metrics');
      expect(
        paths.reconciliationJobs,
        'tenants/tenant-a/reconciliation_jobs',
      );
      expect(
        paths.reconciliationDirtyDays,
        'tenants/tenant-a/reconciliation_dirty_days',
      );
      expect(paths.shiftAmendments, 'tenants/tenant-a/shift_amendments');
    });

    test('document factories cannot escape the tenant root', () {
      final paths = TenantPaths('tenant-a');
      final documents = <String>[
        paths.product('product-1'),
        paths.category('category-1'),
        paths.sale('sale-1'),
        paths.shift('shift-1'),
        paths.returnRecord('return-1'),
        paths.staffMember('user-1'),
        paths.configurationDocument('checkout'),
        paths.currentSubscription,
        paths.auditRecord('audit-1'),
        paths.stockAdjustment('sa_abc'),
        paths.dailyMetric('2026-07-31'),
        paths.reconciliationJob('rj_abc'),
        // The intake record's document ID is the business date itself, so a
        // day is addressed by path rather than searched for.
        paths.reconciliationDirtyDay('2026-07-31'),
        paths.shiftAmendment('amend_abc'),
      ];

      for (final document in documents) {
        expect(paths.owns(document), isTrue);
        expect(document.startsWith('tenants/tenant-a/'), isTrue);
      }
      expect(
        paths.currentSubscription,
        'tenants/tenant-a/subscription/current',
      );
      expect(() => paths.product('../other'), throwsArgumentError);
      expect(() => paths.staffMember('users/other'), throwsArgumentError);
    });

    test('product subcollections stay below their exact product', () {
      final paths = TenantPaths('tenant-a');

      expect(
        paths.productSubcollectionPath(
          'product-1',
          TenantProductSubcollection.stockMovements,
        ),
        'tenants/tenant-a/products/product-1/stock_movements',
      );
      expect(
        paths.productStockMovements('product-1'),
        'tenants/tenant-a/products/product-1/stock_movements',
      );
      expect(
        paths.productStockMovement('product-1', 'sa_abc'),
        'tenants/tenant-a/products/product-1/stock_movements/sa_abc',
      );
      expect(paths.owns(paths.productStockMovements('product-1')), isTrue);

      // Neither segment may be used to walk out of the product.
      expect(
        () => paths.productStockMovements('../other'),
        throwsArgumentError,
      );
      expect(
        () => paths.productStockMovement('product-1', 'a/b'),
        throwsArgumentError,
      );
    });

    test('scope ownership uses a segment boundary', () {
      final paths = TenantPaths('tenant-a');

      expect(paths.owns('tenants/tenant-a'), isTrue);
      expect(paths.owns('tenants/tenant-a/products/p1'), isTrue);
      expect(paths.owns('tenants/tenant-ab/products/p1'), isFalse);
      expect(paths.owns('products/p1'), isFalse);
    });
  });
}
