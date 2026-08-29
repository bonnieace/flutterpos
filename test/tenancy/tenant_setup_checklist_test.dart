import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

TenantSession _session({TenantRole role = TenantRole.owner}) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

void main() {
  group('what a new business still has to do', () {
    test('a cache this device has never written means neither is done', () async {
      // The safe way round: the card appears and points at the two screens that
      // fix it, rather than staying silent about a till that will refuse.
      final state = await const TenantSetupChecklist(
        cache: _Cache(null),
      ).read(_session());

      expect(state.hasCurrency, isFalse);
      expect(state.hasProducts, isFalse);
      expect(state.isComplete, isFalse);
      expect(state.outstanding, <TenantSetupStep>[
        TenantSetupStep.currency,
        TenantSetupStep.products,
      ]);
    });

    test('a currency with no products leaves one step', () async {
      final state = await TenantSetupChecklist(
        cache: _Cache(_snapshot(products: const <TenantProduct>[])),
      ).read(_session());

      expect(state.hasCurrency, isTrue);
      expect(state.hasProducts, isFalse);
      expect(state.outstanding, <TenantSetupStep>[TenantSetupStep.products]);
    });

    test('a business that can trade has nothing outstanding', () async {
      final state = await TenantSetupChecklist(
        cache: _Cache(_snapshot()),
      ).read(_session());

      expect(state.isComplete, isTrue);
      expect(state.outstanding, isEmpty);
    });

    test('currency comes before products, because pricing needs one', () async {
      final state = await const TenantSetupChecklist(
        cache: _Cache(null),
      ).read(_session());

      expect(state.outstanding.first, TenantSetupStep.currency);
    });

    test('it reads the session it was given and no other', () async {
      final cache = _Cache(_snapshot());
      await TenantSetupChecklist(cache: cache).read(_session());

      expect(cache.requested, <String>['user-a/tenant-a']);
    });
  });

  group('who is shown it', () {
    test('an owner and an administrator, who can fix both steps', () {
      for (final role in <TenantRole>[TenantRole.owner, TenantRole.admin]) {
        expect(
          TenantSetupChecklist.showsInSession(_session(role: role)),
          isTrue,
          reason: role.name,
        );
      }
    });

    test('not a manager or a cashier, who can fix neither', () {
      // A card telling somebody to publish a currency they have no permission
      // to publish is worse than no card.
      for (final role in <TenantRole>[TenantRole.manager, TenantRole.cashier]) {
        expect(
          TenantSetupChecklist.showsInSession(_session(role: role)),
          isFalse,
          reason: role.name,
        );
      }
    });
  });

  group('what each step says', () {
    test('every step has a label and a consequence', () {
      for (final step in TenantSetupStep.values) {
        expect(tenantSetupStepLabel(step), isNotEmpty, reason: step.name);
        expect(tenantSetupStepDetail(step), isNotEmpty, reason: step.name);
      }
    });

    test('the currency step names the refusal it prevents', () {
      // The whole reason this exists: the till refuses and nothing said why.
      expect(tenantSetupStepDetail(TenantSetupStep.currency), contains('refuse'));
    });
  });
}

CheckoutCatalogSnapshot _snapshot({
  String currency = 'KES',
  List<TenantProduct>? products,
}) => CheckoutCatalogSnapshot.forTesting(
  uid: 'user-a',
  tenantId: 'tenant-a',
  refreshedAt: DateTime.utc(2026, 8, 29),
  complete: true,
  configuration: TenantCheckoutConfiguration(currency: currency),
  categories: const <TenantCategory>[],
  products: products ?? <TenantProduct>[_product()],
);

TenantProduct _product() => TenantProduct.fromDocument(
  path: 'tenants/tenant-a/products/product-a',
  data: const <String, Object?>{
    'name': 'Cola',
    'SKU': 'COLA-1',
    'price': 120.5,
    'quantity': 4,
    'categoryId': 'drinks',
  },
);

final class _Cache implements CheckoutCatalogSource {
  const _Cache(this._snapshot);

  final CheckoutCatalogSnapshot? _snapshot;

  static final List<String> _requested = <String>[];
  List<String> get requested => _requested;

  @override
  Future<CheckoutCatalogSnapshot?> read({
    required String uid,
    required String tenantId,
  }) async {
    _requested
      ..clear()
      ..add('$uid/$tenantId');
    return _snapshot;
  }
}
