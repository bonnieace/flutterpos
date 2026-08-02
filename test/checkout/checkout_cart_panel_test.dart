import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      expect(_text(tester, 'checkout-saved'), contains('CT-A7F-20260731-0001'));

      // The cashier starts serving the next customer straight away. The number
      // describes a sale that is already finished, so it must not vanish.
      await _tap(tester, 'checkout-product-product-b');

      expect(_text(tester, 'checkout-saved'), contains('CT-A7F-20260731-0001'));

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

      expect(_text(tester, 'checkout-saved'), contains('CT-A7F-20260731-0002'));
      expect(
        _text(tester, 'checkout-saved'),
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
      expect(_text(tester, 'checkout-refusal'), 'Open a shift before selling.');
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
        _text(tester, 'checkout-saved'),
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
    expect(_text(tester, 'checkout-total'), 'Total: KES 0.00');
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

Future<void> _enter(WidgetTester tester, String key, String value) async {
  await tester.enterText(find.byKey(ValueKey(key)), value);
  await _settle(tester);
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

/// The single [TextField] at or under [key].
TextField _field(WidgetTester tester, String key) => tester.widget<TextField>(
  find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextField),
    matchRoot: true,
  ),
);

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
}) => TenantProduct.fromSnapshot(
  TenantQueryDocumentSnapshot(
    path: 'tenants/$tenantId/products/$productId',
    data: <String, Object?>{
      'name': '$productId name',
      'SKU': 'sku-$productId',
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
