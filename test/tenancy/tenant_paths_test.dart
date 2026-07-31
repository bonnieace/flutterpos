import 'package:flutter_application_1/tenancy/tenancy.dart';
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
        // Server-regenerated daily reporting. Added deliberately as part of the
        // guarded daily summary; the client only ever reads it.
        TenantCollection.dailyMetrics: 'tenants/tenant-a/daily_metrics',
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

    test('scope ownership uses a segment boundary', () {
      final paths = TenantPaths('tenant-a');

      expect(paths.owns('tenants/tenant-a'), isTrue);
      expect(paths.owns('tenants/tenant-a/products/p1'), isTrue);
      expect(paths.owns('tenants/tenant-ab/products/p1'), isFalse);
      expect(paths.owns('products/p1'), isFalse);
    });
  });
}
