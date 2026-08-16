import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

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
    expect(_text(tester, 'checkout-total'), 'KES 248.00');
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
      reason: _optionalNotice(tester, 'checkout-refusal'),
    );
    expect(drafts.requests, hasLength(1));
    expect(drafts.requests.single.tender, CheckoutTender.cash);
    expect(drafts.requests.single.lines.single.productId, 'product-a');
    expect(drafts.requests.single.lines.single.quantity, 2);
    // The discount has no control, so a saved sale can never carry one.
    expect(drafts.requests.single.discountMinor, 0);

    expect(_notice(tester, 'checkout-saved'), contains('CT-A7F-20260731-0001'));
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

    expect(_notice(tester, 'checkout-refusal'), 'Open a shift before selling.');
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
      _notice(tester, 'checkout-refusal'),
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
      _notice(tester, 'checkout-refusal'),
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
      _notice(tester, 'checkout-refusal'),
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
    expect(_text(tester, 'checkout-total'), 'KES 0.00');
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

    expect(_text(tester, 'checkout-total'), 'KES 120.50');
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

  group('finding a product', () {
    setUp(() {
      catalog.put(
        uid: 'user-a',
        tenantId: 'tenant-a',
        categories: <TenantCategory>[
          _category('tenant-a', 'drinks'),
          _category('tenant-a', 'bread'),
        ],
        products: <TenantProduct>[
          _product('tenant-a', 'cola', categoryId: 'drinks'),
          _product('tenant-a', 'water', categoryId: 'drinks'),
          _product('tenant-a', 'loaf', categoryId: 'bread'),
          // Names a category this device does not hold; it must stay sellable.
          _product('tenant-a', 'candle', categoryId: 'household'),
        ],
      );
    });

    testWidgets('searching narrows the list by name', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _enter(tester, 'checkout-search', 'wat');

      expect(find.byKey(const ValueKey('checkout-product-water')), findsOne);
      expect(find.byKey(const ValueKey('checkout-product-cola')), findsNothing);
      expect(find.byKey(const ValueKey('checkout-product-loaf')), findsNothing);
    });

    testWidgets('searching matches the product code as well', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      // The cashier reads a code off the shelf label, not a product name.
      await _enter(tester, 'checkout-search', 'SKU-LOAF');

      expect(find.byKey(const ValueKey('checkout-product-loaf')), findsOne);
      expect(find.byKey(const ValueKey('checkout-product-cola')), findsNothing);
    });

    testWidgets('a search that matches nothing says so', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _enter(tester, 'checkout-search', 'zzz');

      expect(
        find.byKey(const ValueKey('checkout-catalog-no-matches')),
        findsOne,
      );
      // Not the same thing as a device holding no catalog at all.
      expect(find.byKey(const ValueKey('checkout-catalog-empty')), findsNothing);
    });

    testWidgets('a category chip narrows the list and combines with search', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-category-drinks');

      expect(find.byKey(const ValueKey('checkout-product-cola')), findsOne);
      expect(find.byKey(const ValueKey('checkout-product-water')), findsOne);
      expect(find.byKey(const ValueKey('checkout-product-loaf')), findsNothing);

      await _enter(tester, 'checkout-search', 'cola');

      expect(find.byKey(const ValueKey('checkout-product-cola')), findsOne);
      expect(find.byKey(const ValueKey('checkout-product-water')), findsNothing);

      await _tap(tester, 'checkout-category-all');

      // The search survives clearing the category; only the category widened.
      expect(find.byKey(const ValueKey('checkout-product-cola')), findsOne);
      expect(find.byKey(const ValueKey('checkout-product-loaf')), findsNothing);
    });

    testWidgets('a product naming an uncached category stays reachable', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      // Filtering must never be able to hide something the till can sell.
      await _tap(tester, 'checkout-category-other');

      expect(find.byKey(const ValueKey('checkout-product-candle')), findsOne);
      expect(find.byKey(const ValueKey('checkout-product-cola')), findsNothing);
    });

    testWidgets('a filtered product can still be added and sold', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _enter(tester, 'checkout-search', 'loaf');
      await _tap(tester, 'checkout-product-loaf');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(drafts.requests.single.lines.single.productId, 'loaf');
      // The till returns to the whole catalog for the next customer rather
      // than leaving it narrowed by the last one.
      expect(_field(tester, 'checkout-search').controller!.text, isEmpty);
      expect(find.byKey(const ValueKey('checkout-product-cola')), findsOne);
    });

    testWidgets('reads the device catalog once and never again to filter', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);
      expect(catalog.reads, hasLength(1));

      await _enter(tester, 'checkout-search', 'co');
      await _enter(tester, 'checkout-search', 'col');
      await _tap(tester, 'checkout-category-drinks');
      await _tap(tester, 'checkout-category-all');

      // Searching and filtering are answered from the snapshot already in
      // hand. A sale has to be buildable with no network at all, so neither
      // may reach storage, let alone Firestore.
      expect(catalog.reads, hasLength(1));
    });

    testWidgets('no category row is offered when nothing can be filtered', (
      tester,
    ) async {
      catalog.put(
        uid: 'user-a',
        tenantId: 'tenant-a',
        categories: <TenantCategory>[_category('tenant-a', 'drinks')],
        products: <TenantProduct>[
          _product('tenant-a', 'cola', categoryId: 'drinks'),
        ],
      );
      await _pump(tester, sessions, catalog, drafts);

      expect(find.byKey(const ValueKey('checkout-category-all')), findsOne);
      expect(
        find.byKey(const ValueKey('checkout-category-other')),
        findsNothing,
      );
    });
  });

  group('entering a code', () {
    setUp(() {
      catalog.put(
        uid: 'user-a',
        tenantId: 'tenant-a',
        categories: <TenantCategory>[_category('tenant-a', 'drinks')],
        products: <TenantProduct>[
          _product('tenant-a', 'cola', price: 60, categoryId: 'drinks'),
          _product('tenant-a', 'water', price: 40, categoryId: 'drinks'),
          _product('tenant-a', 'loaf', price: 55, categoryId: 'bread'),
        ],
      );
    });

    testWidgets('a scanned code adds the product and clears the field', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      // A retail scanner types the code and submits, which is exactly this.
      await _submit(tester, 'checkout-search', 'sku-loaf');

      expect(find.byKey(const ValueKey('checkout-line-loaf')), findsOne);
      // Cleared so the next scan starts from the whole catalog.
      expect(_field(tester, 'checkout-search').controller!.text, isEmpty);
      expect(find.byKey(const ValueKey('checkout-code-notice')), findsNothing);
    });

    testWidgets('a code is matched whatever the category filter is set to', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-category-drinks');
      await _submit(tester, 'checkout-search', 'sku-loaf');

      // A scanned code is evidence about what is in the cashier's hand; a chip
      // set earlier must not make the scanner useless.
      expect(find.byKey(const ValueKey('checkout-line-loaf')), findsOne);
      // The filter itself is left exactly as it was.
      expect(find.byKey(const ValueKey('checkout-product-loaf')), findsNothing);
    });

    testWidgets('a code no product carries adds nothing and says so', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _submit(tester, 'checkout-search', 'sku-nothing');

      expect(
        _notice(tester, 'checkout-code-notice'),
        'Nothing on this device matches that. Check the code and try again.',
      );
      expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
    });

    testWidgets('a code two products share is refused rather than guessed', (
      tester,
    ) async {
      // Nothing makes a SKU unique: Firestore Rules do not mention it and the
      // cache only refuses duplicate product IDs, so this is a real state.
      catalog.put(
        uid: 'user-a',
        tenantId: 'tenant-a',
        products: <TenantProduct>[
          _product('tenant-a', 'cola-330', sku: 'SHARED'),
          _product('tenant-a', 'cola-500', sku: 'SHARED'),
        ],
      );
      await _pump(tester, sessions, catalog, drafts);

      await _submit(tester, 'checkout-search', 'SHARED');

      expect(
        _notice(tester, 'checkout-code-notice'),
        'More than one product on this device carries that code, so nothing '
        'was added. Pick the right one from the list.',
      );
      expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
      expect(drafts.requests, isEmpty);
    });

    testWidgets('a search naming exactly one product adds it too', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      // Not a code, but no less unambiguous: one product is left on screen.
      await _submit(tester, 'checkout-search', 'water');

      expect(find.byKey(const ValueKey('checkout-line-water')), findsOne);
    });

    testWidgets('a search naming several products adds none of them', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _submit(tester, 'checkout-search', 'name');

      expect(
        _notice(tester, 'checkout-code-notice'),
        'That matches more than one product, so nothing was added. Pick one '
        'from the list, or enter its exact code.',
      );
      expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
    });

    testWidgets('an empty search does nothing at all', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _submit(tester, 'checkout-search', '');

      expect(find.byKey(const ValueKey('checkout-code-notice')), findsNothing);
      expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
    });

    testWidgets('scanning the same code twice sells two of it', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _submit(tester, 'checkout-search', 'sku-cola');
      await _submit(tester, 'checkout-search', 'sku-cola');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(drafts.requests.single.lines.single.quantity, 2);
    });
  });

  group('a catalog too large to draw', () {
    setUp(() {
      catalog.put(
        uid: 'user-a',
        tenantId: 'tenant-a',
        products: <TenantProduct>[
          for (var index = 0; index < maximumRenderedCheckoutProducts + 5; index++)
            _product(
              'tenant-a',
              'product-${index.toString().padLeft(3, '0')}',
              price: 5,
            ),
        ],
      );
    });

    testWidgets('draws only the bounded number and says how many matched', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      expect(
        find.byKey(const ValueKey('checkout-product-product-000')),
        findsOne,
      );
      // A Wrap builds every child eagerly, so the cap is what keeps a real
      // catalog from building thousands of buttons every frame.
      expect(
        find.byKey(
          ValueKey(
            'checkout-product-product-'
            '${maximumRenderedCheckoutProducts.toString().padLeft(3, '0')}',
          ),
        ),
        findsNothing,
      );
      expect(
        _text(tester, 'checkout-catalog-truncated'),
        'Showing $maximumRenderedCheckoutProducts of '
        '${maximumRenderedCheckoutProducts + 5} matching products. Narrow the '
        'search, or enter a code to add one directly.',
      );
    });

    testWidgets('a product past the cap is still sellable by its code', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      // The cap bounds what is drawn, never what can be sold.
      await _submit(tester, 'checkout-search', 'sku-product-064');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(drafts.requests.single.lines.single.productId, 'product-064');
    });

    testWidgets('a narrowed search drops the cap message', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _enter(tester, 'checkout-search', 'product-01');

      expect(
        find.byKey(const ValueKey('checkout-catalog-truncated')),
        findsNothing,
      );
    });
  });

  group('clearing a sale', () {
    testWidgets('is offered only once there is something to abandon', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      expect(find.byKey(const ValueKey('checkout-clear-sale')), findsNothing);

      await _tap(tester, 'checkout-product-product-a');

      expect(find.byKey(const ValueKey('checkout-clear-sale')), findsOne);
    });

    testWidgets('a confirmed clear empties the cart and the tender', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-clear-sale');
      await _tap(tester, 'checkout-clear-confirm');

      expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
      // The tender goes with the cart so it is never carried into the next
      // customer unobserved.
      expect(
        _text(tester, 'checkout-save-blocked'),
        'Add at least one item to save this sale.',
      );
      // Nothing was ever persisted, so nothing was destroyed.
      expect(drafts.requests, isEmpty);
    });

    testWidgets('a cancelled clear keeps every line', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-clear-sale');
      await _tap(tester, 'checkout-clear-cancel');

      expect(find.byKey(const ValueKey('checkout-line-product-a')), findsOne);
    });

    testWidgets('clearing a sale leaves the last receipt on screen', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');
      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-clear-sale');
      await _tap(tester, 'checkout-clear-confirm');

      // The receipt describes a different, finished sale.
      expect(_notice(tester, 'checkout-saved'), contains('CT-A7F-20260731-0001'));
    });
  });

  group('typing a quantity', () {
    testWidgets('sells twelve of something in one entry', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-b');
      await _enter(tester, 'checkout-line-quantity-product-b', '12');

      expect(
        _text(tester, 'checkout-line-amount-product-b'),
        '12 x KES 7.00 = KES 84.00',
      );

      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(drafts.requests.single.lines.single.quantity, 12);
    });

    testWidgets('a plus tap after typing continues from the typed number', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-b');
      await _enter(tester, 'checkout-line-quantity-product-b', '9');
      await _tap(tester, 'checkout-product-product-b');

      expect(
        _text(tester, 'checkout-line-amount-product-b'),
        '10 x KES 7.00 = KES 70.00',
      );
      expect(
        _field(tester, 'checkout-line-quantity-product-b').controller!.text,
        '10',
      );
    });

    testWidgets('an unusable quantity keeps the line and blocks saving', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-tender-cash');
      await _enter(tester, 'checkout-line-quantity-product-b', '0');

      // The last usable quantity is kept, so a half-typed number can never
      // become the sale.
      expect(
        _text(tester, 'checkout-line-amount-product-b'),
        '1 x KES 7.00 = KES 7.00',
      );
      expect(
        _text(tester, 'checkout-save-blocked'),
        'Enter a whole quantity between 1 and 1,000,000 for every item.',
      );
      expect(_save(tester).onPressed, isNull);
      expect(
        find.byKey(
          const ValueKey('checkout-line-quantity-invalid-product-b'),
        ),
        findsOne,
      );
      // The rejected entry is left on screen to be corrected rather than
      // silently replaced by a number the cashier did not type.
      expect(
        _field(tester, 'checkout-line-quantity-product-b').controller!.text,
        '0',
      );
    });

    testWidgets('the draft quantity bound is refused at the till', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-b');
      await _enter(tester, 'checkout-line-quantity-product-b', '1000001');

      expect(_save(tester).onPressed, isNull);

      await _enter(tester, 'checkout-line-quantity-product-b', '1000000');
      await _tap(tester, 'checkout-tender-cash');

      // Exactly the bound is a legal sale, so nothing blocks it except the
      // money bound the next test covers.
      expect(
        find.byKey(
          const ValueKey('checkout-line-quantity-invalid-product-b'),
        ),
        findsNothing,
      );
    });

    testWidgets('a line beyond the recordable amount is refused legibly', (
      tester,
    ) async {
      catalog.put(
        uid: 'user-a',
        tenantId: 'tenant-a',
        products: <TenantProduct>[
          _product('tenant-a', 'vehicle', price: 250000),
        ],
      );
      await _pump(tester, sessions, catalog, drafts);

      // 1,000,000 x KES 250,000 is past the frozen monetary bound. Without
      // this check the payload contract refuses it as
      // draft_contract_violation, which tells a cashier to ask for help when
      // the answer is a smaller number.
      await _tap(tester, 'checkout-product-vehicle');
      await _enter(tester, 'checkout-line-quantity-vehicle', '1000000');
      await _tap(tester, 'checkout-tender-cash');

      expect(
        _text(tester, 'checkout-save-blocked'),
        'This sale is larger than this till can record. Reduce a quantity.',
      );
      expect(_save(tester).onPressed, isNull);
      expect(drafts.requests, isEmpty);
    });

    testWidgets('a cart total beyond the bound is refused even line by line', (
      tester,
    ) async {
      catalog.put(
        uid: 'user-a',
        tenantId: 'tenant-a',
        products: <TenantProduct>[
          _product('tenant-a', 'estate-a', price: 600000000),
          _product('tenant-a', 'estate-b', price: 600000000),
        ],
      );
      await _pump(tester, sessions, catalog, drafts);

      // Each line is inside the bound; only their sum is not.
      await _tap(tester, 'checkout-product-estate-a');
      await _tap(tester, 'checkout-tender-cash');
      expect(find.byKey(const ValueKey('checkout-save-blocked')), findsNothing);

      await _tap(tester, 'checkout-product-estate-b');

      expect(
        _text(tester, 'checkout-save-blocked'),
        'This sale is larger than this till can record. Reduce a quantity.',
      );
    });

    testWidgets('an unusable entry is cleared by correcting it', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-b');
      await _enter(tester, 'checkout-line-quantity-product-b', '');
      expect(_save(tester).onPressed, isNull);

      await _enter(tester, 'checkout-line-quantity-product-b', '3');
      await _tap(tester, 'checkout-tender-cash');

      expect(find.byKey(const ValueKey('checkout-save-blocked')), findsNothing);
      expect(_save(tester).onPressed, isNotNull);
    });
  });

  group('the till lays itself out for the screen it is on', () {
    // A phone, and a till screen. The breakpoint between them is the panel's
    // own constant rather than a number repeated here, so moving it moves
    // these tests with it.
    const phone = Size(411, 900);
    const tillScreen = Size(1400, 900);

    /// A tablet, which is `design.md` §4.1's `medium` band: at or above 768 and
    /// below 1024. It used to get the two-pane till and §4.3 gives it a sheet.
    const tablet = Size(900, 1000);

    testWidgets('puts the cart beside the products on a wide screen', (
      tester,
    ) async {
      await _pumpAt(tester, sessions, catalog, drafts, tillScreen);

      expect(find.byKey(const ValueKey('checkout-wide')), findsOne);
      // Both halves are on screen at once, which is the whole point of the
      // split: nothing about the sale is behind a tap.
      expect(find.byKey(const ValueKey('checkout-product-product-a')), findsOne);
      expect(find.byKey(const ValueKey('checkout-cart-pane')), findsOne);
      expect(find.byKey(const ValueKey('checkout-open-cart')), findsNothing);
    });

    testWidgets('gives the medium band a sheet, not two panes', (tester) async {
      // **§4.3's `Sale` row: "products + cart sheet" at `compact` *and*
      // `medium`, two panes only at `expanded`.** This band used to get the
      // two-pane layout, because the split was this app's own inherited 768
      // rather than anything §4.3 says.
      await _pumpAt(tester, sessions, catalog, drafts, tablet);

      expect(find.byKey(const ValueKey('checkout-compact')), findsOne);
      expect(find.byKey(const ValueKey('checkout-wide')), findsNothing);
      expect(find.byKey(const ValueKey('checkout-open-cart')), findsOne);
    });

    testWidgets('asks the same question about a width that the widget does', (
      tester,
    ) async {
      // The boundary is §4.1's `expanded` floor and not a figure this file
      // repeats. 1023 is the last width that is not `expanded`.
      expect(TenantCheckoutPanel.showsTwoPanes(1024), isTrue);
      expect(TenantCheckoutPanel.showsTwoPanes(1023), isFalse);
      expect(TenantCheckoutPanel.showsTwoPanes(768), isFalse);
    });

    testWidgets('gives the cart pane the width §4.2 states for it', (
      tester,
    ) async {
      await _pumpAt(tester, sessions, catalog, drafts, tillScreen);

      // §4.2's third row is "products flex, cart pane **fixed 420**", declared
      // as `AppLayout.salePane` in step 6a and read by nothing until step 7.
      final pane = tester.getSize(
        find.byKey(const ValueKey('checkout-cart-pane')),
      );
      expect(pane.width, AppLayout.contract.salePane);
    });

    testWidgets('puts the cart behind a bar on a phone', (tester) async {
      await _pumpAt(tester, sessions, catalog, drafts, phone);

      expect(find.byKey(const ValueKey('checkout-compact')), findsOne);
      expect(find.byKey(const ValueKey('checkout-product-product-a')), findsOne);
      expect(find.byKey(const ValueKey('checkout-open-cart')), findsOne);
      // The cart is a route that has not been pushed, so none of it is built.
      expect(find.byKey(const ValueKey('checkout-cart-pane')), findsNothing);
      expect(find.byKey(const ValueKey('checkout-save')), findsNothing);
    });

    testWidgets('states the total on the bar without opening the cart', (
      tester,
    ) async {
      await _pumpAt(tester, sessions, catalog, drafts, phone);

      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-product-product-b');

      // The number the customer is waiting for is never behind a tap.
      expect(_text(tester, 'checkout-cart-bar-total'), 'Total: KES 14.00');
      expect(
        tester.widget<Badge>(find.byKey(const ValueKey('checkout-cart-badge')))
            .isLabelVisible,
        isTrue,
      );
    });

    testWidgets('opens the cart and sells from inside the sheet', (
      tester,
    ) async {
      await _pumpAt(tester, sessions, catalog, drafts, phone);

      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-open-cart');

      expect(find.byKey(const ValueKey('checkout-line-product-b')), findsOne);

      await _tapScrolled(tester, 'checkout-tender-cash');
      await _tapScrolled(tester, 'checkout-save');

      expect(drafts.requests.single.lines.single.productId, 'product-b');
    });

    testWidgets('the open sheet follows an edit made inside it', (
      tester,
    ) async {
      await _pumpAt(tester, sessions, catalog, drafts, phone);

      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-open-cart');
      expect(_text(tester, 'checkout-total'), 'KES 7.00');

      // The sheet is its own route, so it does not rebuild when the panel
      // behind it does. Removing the only line has to empty it anyway.
      await _tap(tester, 'checkout-line-remove-product-b');

      expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
      expect(_text(tester, 'checkout-total'), 'KES 0.00');
    });
  });

  group('the till draws the design system rather than Material', () {
    testWidgets('gives the save the primary tier and the clear the destructive '
        'one', (tester) async {
      // **`design.md` §2.1's own worked example, and it was still on screen.**
      // "Clear this sale is `destructive`, Save sale is `primary`. Today the
      // destructive action is the more prominent of the two." It was an
      // `OutlinedButton` above a `FilledButton`, so the two read as equals and
      // the destructive one came first.
      await _pump(tester, sessions, catalog, drafts);
      await _tap(tester, 'checkout-product-product-a');

      expect(_save(tester).tier, AppButtonTier.primary);
      expect(
        _button(tester, 'checkout-clear-sale').tier,
        AppButtonTier.destructive,
      );
    });

    testWidgets('replaces the save label with a spinner rather than a word', (
      tester,
    ) async {
      // §2.1's loading row: the container is held, the label is replaced by a
      // spinner, and the width is frozen. It used to swap the label to
      // "Saving...", which is the resize that row exists to forbid.
      final gate = Completer<void>();
      drafts.gate = gate.future;
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await tester.tap(find.byKey(const ValueKey('checkout-save')));
      await tester.pump();

      expect(_save(tester).loading, isTrue);
      expect(_save(tester).label, 'Save sale');
      expect(find.text('Saving...'), findsNothing);

      gate.complete();
      await _settle(tester);
      expect(_save(tester).loading, isFalse);
    });

    testWidgets('says which kind of answer each of its notices is', (
      tester,
    ) async {
      // Four surfaces on this screen held a `String?` whose meaning was in the
      // sentence. `AppNotice` maps the outcome once, and the two that matter
      // most here are the pair a cashier must tell apart at a glance: a sale
      // that was saved and one that was refused.
      await _pump(tester, sessions, catalog, drafts);

      await _submit(tester, 'checkout-search', 'nothing-carries-this');
      expect(_status(tester, 'checkout-code-notice'), AppStatus.problem);

      // The search is still narrowing the list, and clearing it is what a
      // cashier does next rather than something this assertion needs.
      await _enter(tester, 'checkout-search', '');
      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');
      expect(_status(tester, 'checkout-saved'), AppStatus.ok);
    });

    testWidgets('a sale saved with no receipt number is awaiting, not wrong', (
      tester,
    ) async {
      // §2.1's `attention` is "unreconciled, pending, **awaiting**", and what
      // is awaited is the number: the sale is durable and syncs either way.
      // Drawn identically to a confirmed one before this, in the same black
      // paragraph in the same position.
      drafts.omitReceiptNumber = true;
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(_status(tester, 'checkout-saved'), AppStatus.attention);
    });

    testWidgets('a till that cannot save says so as information', (
      tester,
    ) async {
      // §2.1's `info` is "offline, **read-only**, informational". Nothing was
      // attempted, so nothing was refused.
      await _pump(tester, sessions, catalog, null);

      expect(_status(tester, 'checkout-unavailable'), AppStatus.info);
    });

    testWidgets('folds the submission policy rather than printing it', (
      tester,
    ) async {
      // §7's "Long copy": policy folds, current state does not. What happens to
      // a saved sale afterwards was permanent body text at the foot of every
      // cart.
      await _pump(tester, sessions, catalog, drafts);

      final disclosure = tester.widget<Disclosure>(
        find.byKey(const ValueKey('checkout-submission-disclosure')),
      );
      expect(
        disclosure.summary.length,
        lessThanOrEqualTo(Disclosure.summaryCharacterBudget),
      );
      // Closed means gone from the tree, so a screen reader is not read prose
      // nobody can see.
      expect(
        find.byKey(const ValueKey('checkout-submission-policy')),
        findsNothing,
      );
    });
  });

  group('a product this device believes is gone', () {
    testWidgets('is marked at zero and still sells', (tester) async {
      catalog.put(
        uid: 'user-a',
        tenantId: 'tenant-a',
        products: <TenantProduct>[
          _product('tenant-a', 'depleted', price: 5, quantity: 0),
        ],
      );
      await _pump(tester, sessions, catalog, drafts);

      expect(
        find.byKey(const ValueKey('checkout-product-depleted-depleted')),
        findsOne,
      );
      // Marked, never blocked: the cached figure is what this device last saw,
      // and the panel's scope decision is that it cannot stop a sale.
      await _tap(tester, 'checkout-product-depleted');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(drafts.requests, hasLength(1));
    });

    testWidgets('is marked when the cached figure is negative', (tester) async {
      catalog.put(
        uid: 'user-a',
        tenantId: 'tenant-a',
        products: <TenantProduct>[
          _product('tenant-a', 'oversold', price: 5, quantity: -3),
        ],
      );
      await _pump(tester, sessions, catalog, drafts);

      expect(
        find.byKey(const ValueKey('checkout-product-depleted-oversold')),
        findsOne,
      );
      // The figure itself is still stated verbatim beside the mark.
      expect(
        _text(tester, 'checkout-product-stock-oversold'),
        'KES 5.00, -3 in stock',
      );
    });

    testWidgets('a stocked product carries no such mark', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      expect(
        find.byKey(const ValueKey('checkout-product-depleted-product-b')),
        findsNothing,
      );
    });
  });

  group('the cached stock figure', () {
    testWidgets('is stated on the product with when it was read', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      expect(
        _text(tester, 'checkout-product-stock-product-b'),
        'KES 7.00, 12 in stock',
      );
      expect(
        _text(tester, 'checkout-catalog-freshness'),
        'Prices and stock come from this device, last synced 2026-07-31 '
        '00:00 UTC. A sale is never blocked by a stock count.',
      );
    });

    testWidgets('warns past the cached figure but never blocks the sale', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-b');
      await _enter(tester, 'checkout-line-quantity-product-b', '30');

      expect(
        _text(tester, 'checkout-line-stock-product-b'),
        'This device last saw 12 in stock. The sale is not blocked by that '
        'count.',
      );

      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      // An offline device cannot know the true figure, and the server permits
      // signed stock, so refusing here would block a legitimate sale on stale
      // data while guaranteeing nothing.
      expect(drafts.requests.single.lines.single.quantity, 30);
      expect(find.byKey(const ValueKey('checkout-saved')), findsOne);
    });

    testWidgets('a negative cached figure is stated rather than hidden', (
      tester,
    ) async {
      catalog.put(
        uid: 'user-a',
        tenantId: 'tenant-a',
        products: <TenantProduct>[
          _product('tenant-a', 'oversold', price: 5, quantity: -3),
        ],
      );
      await _pump(tester, sessions, catalog, drafts);

      expect(
        _text(tester, 'checkout-product-stock-oversold'),
        'KES 5.00, -3 in stock',
      );

      await _tap(tester, 'checkout-product-oversold');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(drafts.requests, hasLength(1));
    });

    testWidgets('a partly synced catalog says a product may be missing', (
      tester,
    ) async {
      catalog.answerWith = CheckoutCatalogSnapshot.forTesting(
        uid: 'user-a',
        tenantId: 'tenant-a',
        configuration: TenantCheckoutConfiguration(currency: 'KES'),
        products: <TenantProduct>[_product('tenant-a', 'cola')],
        complete: false,
      );
      await _pump(tester, sessions, catalog, drafts);

      expect(find.byKey(const ValueKey('checkout-catalog-partial')), findsOne);
    });
  });

  group('the saved receipt', () {
    testWidgets('survives the next cart edit until it is closed', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');
      expect(_notice(tester, 'checkout-saved'), contains('CT-A7F-20260731-0001'));

      // The cashier starts serving the next customer straight away. The number
      // describes a sale that is already finished, so it must not vanish.
      await _tap(tester, 'checkout-product-product-b');

      expect(_notice(tester, 'checkout-saved'), contains('CT-A7F-20260731-0001'));

      await _tap(tester, 'checkout-dismiss-receipt');

      expect(find.byKey(const ValueKey('checkout-saved')), findsNothing);
      // Closing the receipt is not the same as clearing the cart.
      expect(find.byKey(const ValueKey('checkout-line-product-b')), findsOne);
    });

    testWidgets('can be copied', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');
      await _tap(tester, 'checkout-copy-receipt');

      expect(copied, <String>['CT-A7F-20260731-0001']);
      expect(find.byKey(const ValueKey('checkout-receipt-copied')), findsOne);
    });

    testWidgets('a second save replaces the first receipt', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');
      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-tender-mpesa');
      await _tap(tester, 'checkout-save');

      expect(_notice(tester, 'checkout-saved'), contains('CT-A7F-20260731-0002'));
      expect(
        _notice(tester, 'checkout-saved'),
        isNot(contains('CT-A7F-20260731-0001')),
      );
    });

    testWidgets('a refused save takes the previous receipt off screen', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      drafts.refusal = 'no_open_shift';
      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      // An older number beside a refusal reads as if the refused sale saved.
      expect(find.byKey(const ValueKey('checkout-saved')), findsNothing);
      expect(_notice(tester, 'checkout-refusal'), 'Open a shift before selling.');
    });

    testWidgets('a save with no receipt number still says the sale is kept', (
      tester,
    ) async {
      drafts.omitReceiptNumber = true;
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      // Silence here would have the cashier ring the same sale up again.
      expect(
        _notice(tester, 'checkout-saved'),
        startsWith('Saved on this device, but it could not state a receipt'),
      );
      expect(
        find.byKey(const ValueKey('checkout-copy-receipt')),
        findsNothing,
      );
    });
  });

  testWidgets('a business switch clears the cart, the search, and the receipt', (
    tester,
  ) async {
    catalog.put(
      uid: 'user-a',
      tenantId: 'tenant-b',
      products: <TenantProduct>[_product('tenant-b', 'product-a', price: 3)],
    );
    await _pump(tester, sessions, catalog, drafts);

    await _enter(tester, 'checkout-search', 'product-a');
    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-tender-cash');
    await _tap(tester, 'checkout-save');
    expect(find.byKey(const ValueKey('checkout-saved')), findsOne);

    sessions.open(uid: 'user-a', membership: _membership('tenant-b'));
    await _settle(tester);

    // Nothing from the first business may be carried into the second: not a
    // line, not a search term, and not a receipt number.
    expect(find.byKey(const ValueKey('checkout-saved')), findsNothing);
    expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
    expect(_field(tester, 'checkout-search').controller!.text, isEmpty);
    expect(_text(tester, 'checkout-total'), 'KES 0.00');
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
) => _pumpAt(
  tester,
  controller,
  catalog,
  drafts,
  // Wide enough for the cart to sit beside the products, which is where every
  // test that is not about layout wants to be: it puts the whole till on
  // screen at once.
  const Size(1400, 4000),
);

/// Pumps the till into a surface of an exact size.
///
/// The size is the input to the only layout decision this screen makes, so the
/// tests that care about it state it rather than inheriting a default.
Future<void> _pumpAt(
  WidgetTester tester,
  TenantSessionController controller,
  _Catalog catalog,
  CheckoutDraftSink? drafts,
  Size size,
) async {
  tester.view.physicalSize = size;
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

/// Taps [key] after scrolling it into view.
///
/// The cart sheet on a phone is taller than the phone, so a control below its
/// fold is built and present but not yet tappable - which is exactly the state
/// it is in for a cashier, who scrolls to it.
Future<void> _tapScrolled(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  await tester.enterText(find.byKey(ValueKey(key)), value);
  await _settle(tester);
}

/// Types [value] then submits, which is what a barcode scanner produces.
Future<void> _submit(WidgetTester tester, String key, String value) async {
  await tester.enterText(find.byKey(ValueKey(key)), value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await _settle(tester);
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

/// The sentence a notice at [key] states.
///
/// **The till's five notice surfaces are `Callout`s as of §11 step 7**, which
/// is how every other panel in this app renders an `AppNotice`, so these read
/// through the same `test/support/notices.dart` the other seven surfaces do
/// rather than reaching for a `Text` underneath the component.
String _notice(WidgetTester tester, String key) => noticeMessage(tester, key);

/// Which of §2.1's five a notice at [key] carries.
AppStatus _status(WidgetTester tester, String key) => noticeStatus(tester, key);

/// The single [TextField] at or under [key].
TextField _field(WidgetTester tester, String key) => tester.widget<TextField>(
  find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextField),
    matchRoot: true,
  ),
);

/// The notice at [key], or a note that it is absent. Used only in failure
/// reasons, so a missing widget explains itself rather than throwing.
String _optionalNotice(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey(key));
  return finder.evaluate().isEmpty ? '($key absent)' : _notice(tester, key);
}

AppButton _button(WidgetTester tester, String key) =>
    tester.widget<AppButton>(find.byKey(ValueKey(key)));

AppButton _save(WidgetTester tester) => _button(tester, 'checkout-save');

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
    List<TenantCategory> categories = const <TenantCategory>[],
    String currency = 'KES',
  }) {
    _snapshots['$uid:$tenantId'] = CheckoutCatalogSnapshot.forTesting(
      uid: uid,
      tenantId: tenantId,
      configuration: TenantCheckoutConfiguration(currency: currency),
      categories: categories,
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

  /// Stands in for a payload that somehow carried no receipt number.
  bool omitReceiptNumber = false;
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
      receiptNumber: omitReceiptNumber
          ? null
          : 'CT-A7F-20260731-${_sequence.toString().padLeft(4, '0')}',
    );
  }
}

TenantProduct _product(
  String tenantId,
  String productId, {
  double price = 10,
  int quantity = 12,
  String categoryId = 'drinks',
  String? sku,
}) => TenantProduct.fromSnapshot(
  TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/products/$productId',
    data: <String, Object?>{
      'name': '$productId name',
      'SKU': sku ?? 'sku-$productId',
      'price': price,
      'quantity': quantity,
      'categoryId': categoryId,
    },
  ),
);

TenantCategory _category(String tenantId, String categoryId) =>
    TenantCategory.fromSnapshot(
      TenantQueryDocumentSnapshot(
        path: 'tenants/$tenantId/categories/$categoryId',
        data: <String, Object?>{'name': '$categoryId category'},
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
