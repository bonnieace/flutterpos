import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/customers/customers.dart';
import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/production/production.dart';
import 'package:uzapay_pos/returns/returns.dart';
import 'package:uzapay_pos/tenancy/tenant_repository.dart';
import 'package:uzapay_pos/ui/scaffold.dart';
import 'package:uzapay_pos/ui/states.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/ui/tokens.dart';

import 'fakes.dart';
import 'harness.dart';

FakeTenantReader _empty() => FakeTenantReader.business()
  ..collections.clear()
  ..groups.clear();

final class _EmptyCustomers
    implements TenantDataReader, TenantCustomerSearchReader {
  final reader = _empty();

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) =>
      reader.getDocument(path);

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) => reader.getCollectionPage(query);

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantCustomers(
    TenantCustomerSearchQuery query,
  ) async => [];
}

Future<void> _expectState(WidgetTester tester, String key) async {
  expect(find.byKey(ValueKey(key)), findsOneWidget);
}

final class _PendingCounts implements TenantStockTakeObligationSource {
  @override
  Set<String> satisfiedScopes({
    required String uid,
    required String tenantId,
    required String businessDate,
  }) => {};

  @override
  Future<void> markSatisfied({
    required String uid,
    required String tenantId,
    required String businessDate,
    required String scopeKey,
  }) async {}
}

void main() {
  for (final blocking in [false, true]) {
    screenshotCase(
      blocking
          ? 'workflow-stock-count-blocking'
          : 'workflow-stock-count-prompt',
      build: () => inSession(
        TenantStockTakeGate(
          businessDate: () => '2026-09-14',
          loadSchedule: (_) async => TenantPublishedStockTakeSchedule.published(
            TenantStockTakeSchedule(
              enforcement: blocking
                  ? TenantStockTakeEnforcement.block
                  : TenantStockTakeEnforcement.prompt,
              weekdays: const {DateTime.monday},
              assignments: const [TenantStockTakeAssignment(uid: ownerUid)],
            ),
          ),
          obligations: _PendingCounts(),
          countRoute: (_, _) => const Scaffold(),
          child: const AppScaffold(
            title: 'Register',
            contentWidth: AppContentWidth.full,
            body: SizedBox.shrink(),
          ),
        ),
      ),
      fullPage: false,
      afterPump: (tester) => _expectState(tester, 'stock-take-gate-start'),
    );
  }
  screenshotCase(
    'workflow-illustrated-notice',
    build: () => const AppScaffold(
      title: 'Printer',
      contentWidth: AppContentWidth.reading,
      body: SingleChildScrollView(
        child: Callout(
          status: AppStatus.info,
          illustration: 'printer-connection.svg',
          message:
              'Connect and switch on the printer. It appears automatically.',
        ),
      ),
    ),
    fullPage: false,
  );
  screenshotCase(
    'workflow-checkout-empty-catalog',
    build: () => inSession(
      TenantCheckoutScreen(
        cache: FakeCatalogSource(
          snapshot: CheckoutCatalogSnapshot.forTesting(
            uid: ownerUid,
            tenantId: seedTenantId,
            configuration: TenantCheckoutConfiguration(currency: seedCurrency),
            categories: const [],
            products: const [],
          ),
        ),
        drafts: FakeDraftSink(),
      ),
    ),
    fullPage: false,
    afterPump: (tester) => _expectState(tester, 'checkout-catalog-empty'),
  );
  screenshotCase(
    'workflow-checkout-empty-cart',
    build: () => inSession(
      TenantCheckoutScreen(cache: FakeCatalogSource(), drafts: FakeDraftSink()),
    ),
    viewports: const [webViewport],
    fullPage: false,
    afterPump: (tester) =>
        _expectState(tester, 'checkout-empty-cart-animation'),
  );
  screenshotCase(
    'workflow-checkout-empty-cart-mobile',
    build: () => inSession(
      TenantCheckoutScreen(cache: FakeCatalogSource(), drafts: FakeDraftSink()),
    ),
    viewports: const [mobileViewport],
    fullPage: false,
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('checkout-open-cart')));
      await tester.pumpAndSettle();
      await _expectState(tester, 'checkout-empty-cart-animation');
    },
  );
  screenshotCase(
    'workflow-customers-empty',
    build: () => inSession(TenantCustomersScreen(reader: _EmptyCustomers())),
    afterPump: (tester) => _expectState(tester, 'customers-empty'),
  );
  screenshotCase(
    'workflow-inventory-empty',
    build: () => inSession(TenantCatalogManagementScreen(reader: _empty())),
    afterPump: (tester) => _expectState(tester, 'inventory-empty-catalog'),
  );
  screenshotCase(
    'workflow-returns-empty',
    build: () => inSession(
      TenantReturnFeedScreen(reader: _empty(), actions: fakeReturnActions()),
    ),
    afterPump: (tester) => _expectState(tester, 'return-feed-no-matches'),
  );
  screenshotCase(
    'workflow-stock-review-empty',
    build: () => inSession(TenantStockTakeReviewScreen(reader: _empty())),
    afterPump: (tester) => _expectState(tester, 'stock-take-review-empty'),
  );
  screenshotCase(
    'workflow-production-empty',
    build: () => inSession(TenantProductionScreen(reader: _empty())),
    afterPump: (tester) => _expectState(tester, 'production-empty'),
  );
  screenshotCase(
    'workflow-compact-message',
    build: () => const AppScaffold(
      title: 'Stock movements',
      contentWidth: AppContentWidth.reading,
      body: Padding(
        padding: EdgeInsets.all(16),
        child: IllustratedMessage(
          illustration: 'stock-movements.svg',
          message: 'No stock movements yet.',
        ),
      ),
    ),
    fullPage: false,
  );
}
