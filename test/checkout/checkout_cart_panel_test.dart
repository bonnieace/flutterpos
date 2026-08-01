import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Catalog catalog;
  late _Drafts drafts;
  late TenantSessionController sessions;

  setUp(() {
    catalog = _Catalog()
      ..put(
        uid: 'user-a',
        tenantId: 'tenant-a',
        products: <TenantProduct>[
          _product('tenant-a', 'product-a', price: 120.5),
          _product('tenant-a', 'product-b', price: 7),
          _product('tenant-a', 'product-odd', price: 120.555),
        ],
      );
    drafts = _Drafts();
    sessions = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
  });

  tearDown(() => sessions.dispose());

  testWidgets('adds catalog products and totals the cart', (tester) async {
    await _pump(tester, sessions, catalog, drafts);

    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-product-product-b');

    expect(find.byKey(const ValueKey('checkout-line-product-a')), findsOne);
    expect(
      _text(tester, 'checkout-line-amount-product-a'),
      '2 x KES 120.50 = KES 241.00',
    );
    expect(_text(tester, 'checkout-total'), 'Total: KES 248.00');
  });

  testWidgets('refuses to save until a payment method is chosen', (
    tester,
  ) async {
    await _pump(tester, sessions, catalog, drafts);

    expect(
      _text(tester, 'checkout-save-blocked'),
      'Add at least one item to save this sale.',
    );

    await _tap(tester, 'checkout-product-product-b');

    // Nothing is pre-selected, so the sale still cannot be saved. A default
    // would be indistinguishable from a payment somebody actually observed.
    expect(
      _text(tester, 'checkout-save-blocked'),
      'Choose how the customer paid.',
    );
    expect(_save(tester).onPressed, isNull);

    await _tap(tester, 'checkout-tender-mpesa');

    expect(find.byKey(const ValueKey('checkout-save-blocked')), findsNothing);
    expect(_save(tester).onPressed, isNotNull);
  });

  testWidgets('a saved sale reports its receipt and clears the cart', (
    tester,
  ) async {
    await _pump(tester, sessions, catalog, drafts);

    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-tender-cash');
    await _tap(tester, 'checkout-save');

    expect(
      find.byKey(const ValueKey('checkout-refusal')),
      findsNothing,
      reason: _optionalText(tester, 'checkout-refusal'),
    );
    expect(drafts.requests, hasLength(1));
    expect(drafts.requests.single.tender, CheckoutTender.cash);
    expect(drafts.requests.single.lines.single.productId, 'product-a');
    expect(drafts.requests.single.lines.single.quantity, 2);
    // The discount has no control, so a saved sale can never carry one.
    expect(drafts.requests.single.discountMinor, 0);

    expect(_text(tester, 'checkout-saved'), contains('CT-A7F-20260731-0001'));
    // The cart resets so the next customer cannot inherit these lines, and the
    // tender resets with it so it is never carried over unobserved.
    expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
    expect(
      _text(tester, 'checkout-save-blocked'),
      'Add at least one item to save this sale.',
    );
  });

  testWidgets('a refused sale keeps the cart and saves nothing', (
    tester,
  ) async {
    drafts.refusal = 'no_open_shift';
    await _pump(tester, sessions, catalog, drafts);

    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-tender-card');
    await _tap(tester, 'checkout-save');

    expect(_text(tester, 'checkout-refusal'), 'Open a shift before selling.');
    // The cashier does not have to ring the sale up again.
    expect(find.byKey(const ValueKey('checkout-line-product-a')), findsOne);
    expect(find.byKey(const ValueKey('checkout-saved')), findsNothing);
  });

  testWidgets('says when retrying cannot clear the refusal', (tester) async {
    drafts.refusal = 'malformed_receipt_counter';
    await _pump(tester, sessions, catalog, drafts);

    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-tender-cash');
    await _tap(tester, 'checkout-save');

    expect(
      _text(tester, 'checkout-refusal'),
      startsWith('The receipt counter on this device is damaged.'),
    );
    expect(find.byKey(const ValueKey('checkout-refusal-needs-help')), findsOne);
  });

  testWidgets('a fixable refusal does not tell the cashier to get help', (
    tester,
  ) async {
    drafts.refusal = 'shift_closing';
    await _pump(tester, sessions, catalog, drafts);

    await _tap(tester, 'checkout-product-product-b');
    await _tap(tester, 'checkout-tender-cash');
    await _tap(tester, 'checkout-save');

    expect(find.byKey(const ValueKey('checkout-refusal')), findsOne);
    expect(
      find.byKey(const ValueKey('checkout-refusal-needs-help')),
      findsNothing,
    );
  });

  testWidgets('a storage fault still reaches the till as a sentence', (
    tester,
  ) async {
    drafts.failure = StateError('the box is closed');
    await _pump(tester, sessions, catalog, drafts);

    await _tap(tester, 'checkout-product-product-b');
    await _tap(tester, 'checkout-tender-cash');
    await _tap(tester, 'checkout-save');

    expect(
      _text(tester, 'checkout-refusal'),
      startsWith('This sale could not be saved on this device.'),
    );
  });

  testWidgets('an unpriceable item blocks the sale rather than rounding it', (
    tester,
  ) async {
    await _pump(tester, sessions, catalog, drafts);

    await _tap(tester, 'checkout-product-product-odd');
    await _tap(tester, 'checkout-tender-cash');

    expect(
      _text(tester, 'checkout-line-amount-product-odd'),
      'This item cannot be priced on this device.',
    );
    expect(
      _text(tester, 'checkout-save-blocked'),
      'Remove the item whose price cannot be recorded exactly.',
    );
    expect(_save(tester).onPressed, isNull);
    expect(drafts.requests, isEmpty);
  });

  testWidgets('refuses a seventeenth product in the cart itself', (
    tester,
  ) async {
    catalog.put(
      uid: 'user-a',
      tenantId: 'tenant-a',
      products: <TenantProduct>[
        for (var index = 0; index < 17; index++)
          _product('tenant-a', 'product-$index', price: 5),
      ],
    );
    await _pump(tester, sessions, catalog, drafts);

    for (var index = 0; index < 16; index++) {
      await _tap(tester, 'checkout-product-product-$index');
    }
    expect(find.byKey(const ValueKey('checkout-refusal')), findsNothing);

    await _tap(tester, 'checkout-product-product-16');

    expect(
      _text(tester, 'checkout-refusal'),
      'A sale needs between 1 and 16 items.',
    );
    expect(find.byKey(const ValueKey('checkout-line-product-16')), findsNothing);
  });

  testWidgets('removing the last item empties the cart', (tester) async {
    await _pump(tester, sessions, catalog, drafts);

    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-line-less-product-a');

    expect(
      _text(tester, 'checkout-line-amount-product-a'),
      '1 x KES 120.50 = KES 120.50',
    );

    await _tap(tester, 'checkout-line-remove-product-a');

    expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
    expect(_text(tester, 'checkout-total'), 'Total: KES 0.00');
  });

  testWidgets('a device with no catalog for this business cannot sell', (
    tester,
  ) async {
    final other = TenantSessionController()
      ..open(uid: 'user-b', membership: _membership('tenant-b'));
    addTearDown(other.dispose);

    await _pump(tester, other, catalog, drafts);

    expect(
      _text(tester, 'checkout-failure'),
      startsWith('This device has no product list for this business yet.'),
    );
    expect(find.byKey(const ValueKey('checkout-cart')), findsNothing);
  });

  testWidgets('a snapshot belonging to another session is refused', (
    tester,
  ) async {
    // Stands in for a cache that answered with the wrong business.
    catalog.answerWith = CheckoutCatalogSnapshot.forTesting(
      uid: 'user-a',
      tenantId: 'tenant-b',
      configuration: TenantCheckoutConfiguration(currency: 'KES'),
    );
    await _pump(tester, sessions, catalog, drafts);

    expect(find.byKey(const ValueKey('checkout-failure')), findsOne);
    expect(find.byKey(const ValueKey('checkout-cart')), findsNothing);
  });

  testWidgets('no session renders the denied state and reads nothing', (
    tester,
  ) async {
    final signedOut = TenantSessionController();
    addTearDown(signedOut.dispose);

    await _pump(tester, signedOut, catalog, drafts);

    expect(find.byKey(const ValueKey('checkout-denied')), findsOne);
    expect(find.byKey(const ValueKey('checkout-cart')), findsNothing);
    expect(catalog.reads, isEmpty);
  });

  testWidgets('without a draft sink the cart prices but cannot save', (
    tester,
  ) async {
    await _pump(tester, sessions, catalog, null);

    await _tap(tester, 'checkout-product-product-a');

    expect(_text(tester, 'checkout-total'), 'Total: KES 120.50');
    expect(find.byKey(const ValueKey('checkout-unavailable')), findsOne);
    expect(find.byKey(const ValueKey('checkout-save')), findsNothing);
  });

  testWidgets('an empty catalog says so instead of offering an empty till', (
    tester,
  ) async {
    catalog.put(uid: 'user-a', tenantId: 'tenant-a', products: const []);
    await _pump(tester, sessions, catalog, drafts);

    expect(find.byKey(const ValueKey('checkout-catalog-empty')), findsOne);
    expect(
      _text(tester, 'checkout-save-blocked'),
      'Add at least one item to save this sale.',
    );
  });

  testWidgets('a business switch during a save never labels the new session', (
    tester,
  ) async {
    final gate = Completer<void>();
    drafts.gate = gate.future;
    await _pump(tester, sessions, catalog, drafts);

    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-tender-cash');
    await tester.tap(find.byKey(const ValueKey('checkout-save')));
    await tester.pump();

    // The cashier moves to another business while the draft is in flight. The
    // real service refuses this as session_changed; the panel must not present
    // the first business's receipt against the second one either way.
    sessions.open(uid: 'user-a', membership: _membership('tenant-b'));
    drafts.refusal = 'session_changed';
    gate.complete();
    await _settle(tester);

    expect(find.byKey(const ValueKey('checkout-saved')), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Catalog catalog,
  CheckoutDraftSink? drafts,
) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantCheckoutScreen(cache: catalog, drafts: drafts),
      ),
    ),
  );
  await _settle(tester);
}

/// Bounded pumping instead of `pumpAndSettle`.
///
/// `pumpAndSettle` never returns while an indeterminate progress indicator is
/// on screen, which is what the route guard shows by default. The panel supplies
/// its own non-animating loading widget precisely so this screen can be settled.
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await _settle(tester);
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

/// The text at [key], or a note that it is absent. Used only in failure
/// reasons, so a missing widget explains itself rather than throwing.
String _optionalText(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey(key));
  return finder.evaluate().isEmpty ? '($key absent)' : _text(tester, key);
}

FilledButton _save(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const ValueKey('checkout-save')));

/// An in-memory stand-in for the encrypted offline catalog.
final class _Catalog implements CheckoutCatalogSource {
  final Map<String, CheckoutCatalogSnapshot> _snapshots =
      <String, CheckoutCatalogSnapshot>{};
  final List<String> reads = <String>[];

  /// Overrides every lookup, standing in for a cache that answered wrongly.
  CheckoutCatalogSnapshot? answerWith;

  void put({
    required String uid,
    required String tenantId,
    required List<TenantProduct> products,
    String currency = 'KES',
  }) {
    _snapshots['$uid:$tenantId'] = CheckoutCatalogSnapshot.forTesting(
      uid: uid,
      tenantId: tenantId,
      configuration: TenantCheckoutConfiguration(currency: currency),
      products: products,
    );
  }

  @override
  Future<CheckoutCatalogSnapshot?> read({
    required String uid,
    required String tenantId,
  }) async {
    reads.add('$uid:$tenantId');
    return answerWith ?? _snapshots['$uid:$tenantId'];
  }
}

/// Records what the cart asked to save, and how the save was answered.
final class _Drafts implements CheckoutDraftSink {
  final List<CheckoutDraftRequest> requests = <CheckoutDraftRequest>[];
  String? refusal;
  Object? failure;
  Future<void>? gate;
  int _sequence = 0;

  @override
  Future<CheckoutSavedDraft> saveDraft(CheckoutDraftRequest request) async {
    requests.add(request);
    final pending = gate;
    if (pending != null) await pending;
    final error = failure;
    if (error != null) throw error;
    final refused = refusal;
    if (refused != null) throw CheckoutDraftException(refused);
    _sequence++;
    return CheckoutSavedDraft(
      checkoutId: 'co-$_sequence',
      receiptNumber: 'CT-A7F-20260731-${_sequence.toString().padLeft(4, '0')}',
    );
  }
}

TenantProduct _product(String tenantId, String productId, {double price = 10}) =>
    TenantProduct.fromSnapshot(
      TenantQueryDocumentSnapshot(
        path: 'tenants/$tenantId/products/$productId',
        data: <String, Object?>{
          'name': '$productId name',
          'SKU': 'sku-$productId',
          'price': price,
          'quantity': 12,
          'categoryId': 'drinks',
        },
      ),
    );

TenantMembership _membership(String tenantId) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: TenantRole.cashier,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
