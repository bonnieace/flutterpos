import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/customers/customer.dart';
import 'package:uzapay_pos/email_receipts/email_receipt_delivery.dart';
import 'package:uzapay_pos/whatsapp/receipt_delivery.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/buttons.dart';
import 'package:uzapay_pos/ui/dialogs.dart';
import 'package:uzapay_pos/ui/fields.dart';
import 'package:uzapay_pos/ui/skeleton.dart';
import 'package:uzapay_pos/ui/snackbar.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/ui/stepper.dart';
import 'package:uzapay_pos/ui/tokens.dart';
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

  testWidgets('the empty cart centers the legacy animation above its message', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      sessions,
      catalog,
      drafts,
      const Size(1400, 900),
      reducedMotion: false,
    );
    final animation = find.byKey(
      const ValueKey('checkout-empty-cart-animation'),
    );
    final message = find.byKey(const ValueKey('checkout-cart-empty'));
    final pane = tester.getRect(
      find.byKey(const ValueKey('checkout-cart-pane')),
    );
    final artwork = tester.getRect(animation);
    final copy = tester.getRect(message);
    expect(artwork.center.dx, closeTo(pane.center.dx, 0.5));
    expect(copy.center.dx, closeTo(pane.center.dx, 0.5));
    expect(copy.top, greaterThan(artwork.bottom));
    expect(artwork.width, greaterThan(96));
    final lottie = tester.widget<LottieBuilder>(animation);
    expect((lottie.lottie as AssetLottie).assetName, 'images/empty.json');
    expect(lottie.repeat, isTrue);
    expect(lottie.animate, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds catalog products and totals the cart', (tester) async {
    await _pump(tester, sessions, catalog, drafts);

    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-product-product-b');

    expect(find.byKey(const ValueKey('checkout-line-product-a')), findsOne);
    // The two-pane line splits the sheet's `2 x KES 120.50 = KES 241` into
    // what the line comes to and what one costs.
    expect(_text(tester, 'checkout-line-amount-product-a'), 'KES 241');
    expect(_text(tester, 'checkout-line-each-product-a'), 'KES 120.50 each');
    expect(_text(tester, 'checkout-total'), 'KES 248');
  });

  group('who the sale is for', () {
    testWidgets('a till that offers no customers still says Register', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      expect(find.text('Register'), findsOneWidget);
      expect(find.byKey(const ValueKey('screen-title-action')), findsNothing);
    });

    testWidgets('every sale starts as a walk-in, and says so', (tester) async {
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        customers: CheckoutCustomerServices(reader: _Customers()),
      );

      expect(find.text('Walk-in'), findsOneWidget);
      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-save');

      expect(drafts.requests.single.customer, isNull);
    });

    testWidgets(
      'a customer chosen from the title goes on the sale, and the next sale '
      'starts as a walk-in again',
      (tester) async {
        await _pump(
          tester,
          sessions,
          catalog,
          drafts,
          customers: CheckoutCustomerServices(reader: _Customers()),
        );

        await tester.tap(find.byKey(const ValueKey('screen-title-action')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('checkout-customer-$_janeId')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Jane Wanjiku'), findsOneWidget);

        await _tap(tester, 'checkout-product-product-b');
        await _tap(tester, 'checkout-save');

        final customer = drafts.requests.single.customer!;
        expect(customer.id, _janeId);
        expect(customer.name, 'Jane Wanjiku');
        expect(customer.kraPin, 'A012345678Z');
        expect(find.text('Walk-in'), findsOneWidget);
      },
    );

    testWidgets('a customer added at the till is chosen straight away', (
      tester,
    ) async {
      final writer = _CustomerWriter();
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        customers: CheckoutCustomerServices(
          reader: _Customers(),
          writer: writer,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('screen-title-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('checkout-customer-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('customer-form-name')),
        'Amina Hassan',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('customer-form-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('customer-form-submit')));
      await tester.pumpAndSettle();

      expect(writer.created, hasLength(1));
      expect(find.text('Amina Hassan'), findsOneWidget);
      expect(snackNotice(tester).message, contains('chosen for this sale'));
      await _waitOutSnackBar(tester);

      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-save');

      expect(
        drafts.requests.single.customer?.id,
        writer.created.single.customerId,
      );
    });

    testWidgets('choosing walk-in again takes the customer off the sale', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        customers: CheckoutCustomerServices(reader: _Customers()),
      );

      await tester.tap(find.byKey(const ValueKey('screen-title-action')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('checkout-customer-$_janeId')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('screen-title-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('checkout-customer-walk-in')));
      await tester.pumpAndSettle();

      expect(find.text('Walk-in'), findsOneWidget);
      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-save');
      expect(drafts.requests.single.customer, isNull);
    });
  });

  group('a receipt on WhatsApp', () {
    const manual = <String, Object?>{
      'whatsappEnabled': true,
      'mode': 'manual',
      'format': 'pdf',
    };
    const automatic = <String, Object?>{
      'whatsappEnabled': true,
      'mode': 'automatic',
      'format': 'summary',
    };

    testWidgets('a business sending by hand opens Send on WhatsApp on save', (
      tester,
    ) async {
      final receipts = _ReceiptWriter();
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        customers: CheckoutCustomerServices(
          reader: _Customers(eReceipts: manual),
          receiptWriter: receipts,
        ),
      );

      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-save');
      await tester.pumpAndSettle();
      // Straight to the sheet, with no snack bar button to find first.
      expect(find.byKey(const ValueKey('send-receipt-sheet')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('checkout-send-whatsapp')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('phone-local-number')),
        '0722 111 222',
      );
      await tester.tap(find.byKey(const ValueKey('send-receipt-submit')));
      await tester.pumpAndSettle();

      final intent = receipts.sent.single;
      expect(intent.saleId, 'co-1');
      // A shop selling in shillings starts the number at +254.
      expect(intent.phone, '+254722111222');
      expect(snackNotice(tester).message, contains('on its way'));
    });

    testWidgets(
      'a sheet closed with nothing sent leaves the sentence, with no button',
      (tester) async {
        final receipts = _ReceiptWriter();
        await _pump(
          tester,
          sessions,
          catalog,
          drafts,
          customers: CheckoutCustomerServices(
            reader: _Customers(eReceipts: manual),
            receiptWriter: receipts,
          ),
        );

        await _tap(tester, 'checkout-product-product-b');
        await _tap(tester, 'checkout-save');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('send-receipt-cancel')));
        await tester.pumpAndSettle();

        expect(receipts.sent, isEmpty);
        expect(find.byKey(const ValueKey('send-receipt-sheet')), findsNothing);
        expect(snackNotice(tester).message, contains('It syncs on its own'));
        expect(
          find.byKey(const ValueKey('checkout-send-whatsapp')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'an automatic business opens the sheet for a walk-in, who is sent '
      'nothing otherwise',
      (tester) async {
        await _pump(
          tester,
          sessions,
          catalog,
          drafts,
          customers: CheckoutCustomerServices(
            reader: _Customers(eReceipts: automatic),
            receiptWriter: _ReceiptWriter(),
          ),
        );

        await _tap(tester, 'checkout-product-product-b');
        await _tap(tester, 'checkout-save');
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('send-receipt-sheet')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('checkout-send-whatsapp')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'an automatic business tells the cashier the customer gets it, and '
      'offers no button',
      (tester) async {
        await _pump(
          tester,
          sessions,
          catalog,
          drafts,
          customers: CheckoutCustomerServices(
            reader: _Customers(eReceipts: automatic),
            receiptWriter: _ReceiptWriter(),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('screen-title-action')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('checkout-customer-$_janeId')),
        );
        await tester.pumpAndSettle();
        await _tap(tester, 'checkout-product-product-b');
        await _tap(tester, 'checkout-save');

        expect(
          snackNotice(tester).message,
          contains('Jane Wanjiku gets the receipt on WhatsApp'),
        );
        expect(
          find.byKey(const ValueKey('checkout-send-whatsapp')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a business that sends on WhatsApp is not told it has no printer',
      (tester) async {
        drafts.printFailure = PrinterTransportCode.notConfigured;
        await _pump(
          tester,
          sessions,
          catalog,
          drafts,
          printerSetupReminder: _Reminder(),
          customers: CheckoutCustomerServices(
            reader: _Customers(eReceipts: manual),
            receiptWriter: _ReceiptWriter(),
          ),
        );

        await _tap(tester, 'checkout-product-product-b');
        await _tap(tester, 'checkout-save');

        await tester.pumpAndSettle();

        expect(find.byType(NoticeDialog), findsNothing);
        expect(
          find.byKey(const ValueKey('send-receipt-sheet')),
          findsOneWidget,
        );
      },
    );

    testWidgets('a business with receipts off reports a sale as before', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        customers: CheckoutCustomerServices(
          reader: _Customers(),
          receiptWriter: _ReceiptWriter(),
        ),
      );

      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-save');

      expect(
        find.byKey(const ValueKey('checkout-send-whatsapp')),
        findsNothing,
      );
      expect(snackNotice(tester).message, contains('It syncs on its own'));
    });
  });

  group('a receipt by email', () {
    const manual = <String, Object?>{'emailEnabled': true, 'mode': 'manual'};
    const automatic = <String, Object?>{
      'emailEnabled': true,
      'mode': 'automatic',
    };
    const whatsappManual = <String, Object?>{
      'whatsappEnabled': true,
      'mode': 'manual',
      'format': 'pdf',
    };
    const whatsappAutomatic = <String, Object?>{
      'whatsappEnabled': true,
      'mode': 'automatic',
      'format': 'pdf',
    };

    Future<void> chooseJane(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('screen-title-action')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('checkout-customer-$_janeId')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a business emailing by hand opens Send by email on save', (
      tester,
    ) async {
      final receipts = _EmailReceiptWriter();
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        customers: CheckoutCustomerServices(
          reader: _Customers(emailReceipts: manual),
          emailReceiptWriter: receipts,
        ),
      );

      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-save');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('send-email-receipt-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('checkout-receipt-channel')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('send-email-receipt-address')),
        'Walk.In@Example.com',
      );
      await tester.tap(find.byKey(const ValueKey('send-email-receipt-submit')));
      await tester.pumpAndSettle();

      final intent = receipts.sent.single;
      expect(intent.saleId, 'co-1');
      expect(intent.email, 'walk.in@example.com');
      expect(snackNotice(tester).message, contains('on its way'));
    });

    testWidgets(
      'a business sending both ways asks which, and opens on the customer\'s '
      'address',
      (tester) async {
        final receipts = _EmailReceiptWriter();
        await _pump(
          tester,
          sessions,
          catalog,
          drafts,
          customers: CheckoutCustomerServices(
            reader: _Customers(
              eReceipts: whatsappManual,
              emailReceipts: manual,
            ),
            receiptWriter: _ReceiptWriter(),
            emailReceiptWriter: receipts,
          ),
        );

        await chooseJane(tester);
        await _tap(tester, 'checkout-product-product-b');
        await _tap(tester, 'checkout-save');
        await tester.pumpAndSettle();
        // The choice opens by itself, each way saying where it goes.
        expect(find.text('To +254712345678'), findsOneWidget);
        expect(find.text('To jane@example.com'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('checkout-receipt-channel-email')),
        );
        await tester.pumpAndSettle();

        expect(find.text('jane@example.com'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('send-email-receipt-submit')),
        );
        await tester.pumpAndSettle();
        expect(receipts.sent.single.email, 'jane@example.com');
        expect(receipts.sent.single.customerName, 'Jane Wanjiku');
      },
    );

    testWidgets(
      'an automatic business tells the cashier how the customer gets it',
      (tester) async {
        await _pump(
          tester,
          sessions,
          catalog,
          drafts,
          customers: CheckoutCustomerServices(
            reader: _Customers(emailReceipts: automatic),
            emailReceiptWriter: _EmailReceiptWriter(),
          ),
        );

        await chooseJane(tester);
        await _tap(tester, 'checkout-product-product-b');
        await _tap(tester, 'checkout-save');

        expect(
          snackNotice(tester).message,
          contains('Jane Wanjiku gets the receipt by email'),
        );
        expect(find.byKey(const ValueKey('checkout-send-email')), findsNothing);
      },
    );

    testWidgets('both automatic, the sentence names both', (tester) async {
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        customers: CheckoutCustomerServices(
          reader: _Customers(
            eReceipts: whatsappAutomatic,
            emailReceipts: automatic,
          ),
          receiptWriter: _ReceiptWriter(),
          emailReceiptWriter: _EmailReceiptWriter(),
        ),
      );

      await chooseJane(tester);
      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-save');

      expect(
        snackNotice(tester).message,
        contains('gets the receipt on WhatsApp and by email'),
      );
      expect(find.byKey(const ValueKey('checkout-send-receipt')), findsNothing);
    });
  });

  testWidgets('preselects no tender and records the silence', (tester) async {
    await _pump(tester, sessions, catalog, drafts);

    expect(find.byKey(const ValueKey('checkout-save-blocked')), findsNothing);
    expect(_save(tester).onPressed, isNull);

    await _tap(tester, 'checkout-product-product-b');

    // **Nothing is preselected and the save is not held for it.** Cash was the
    // default from 2026-08-23 until this change, which meant an untouched
    // control recorded a cash sale whatever happened at the counter - and no
    // surface could correct it afterwards, while reconciliation agrees on the
    // total alone, so the error was both permanent and silent. An item is
    // still the only thing the save waits for; what changed is what an
    // unanswered question records as.
    expect(find.byKey(const ValueKey('checkout-save-blocked')), findsNothing);
    expect(_save(tester).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('checkout-tender-unset')), findsNothing);

    await _tap(tester, 'checkout-save');

    expect(drafts.requests.single.tender, isNull);
  });

  testWidgets('a payment method can be chosen without an unset notice', (
    tester,
  ) async {
    await _pump(tester, sessions, catalog, drafts);
    await _tap(tester, 'checkout-product-product-b');
    await _tap(tester, 'checkout-tender-mpesa');

    expect(find.byKey(const ValueKey('checkout-tender-unset')), findsNothing);

    await _tap(tester, 'checkout-save');

    expect(drafts.requests.single.tender, CheckoutTender.mpesa);
  });

  testWidgets('another tender can still be chosen over the default', (
    tester,
  ) async {
    await _pump(tester, sessions, catalog, drafts);
    await _tap(tester, 'checkout-product-product-b');

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

    expect(snackNotice(tester).message, contains('CT-A7F-20260731-0001'));
    // The cart resets so the next customer cannot inherit these lines, and the
    // tender resets with it so it is never carried over unobserved.
    expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
    expect(find.byKey(const ValueKey('checkout-save-blocked')), findsNothing);
    expect(_save(tester).onPressed, isNull);
  });

  testWidgets('the till holds a Play update only while it holds a sale', (
    tester,
  ) async {
    final activity = CheckoutCartActivity();
    await _pump(tester, sessions, catalog, drafts, cartActivity: activity);
    expect(activity.saleInProgress, isFalse);

    await _tap(tester, 'checkout-product-product-a');
    expect(activity.saleInProgress, isTrue);

    await _tap(tester, 'checkout-tender-cash');
    await _tap(tester, 'checkout-save');
    expect(drafts.requests, hasLength(1));
    expect(activity.saleInProgress, isFalse);

    // A till closed with a cart on it has nothing left to protect.
    await _tap(tester, 'checkout-product-product-b');
    expect(activity.saleInProgress, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(activity.saleInProgress, isFalse);
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
    expect(find.byType(AppSnackBar), findsNothing);
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

  // **Not tapped up to the limit any more.** It was sixteen until 2026-10-05
  // and is four hundred now, past the sixty tiles the till draws at once; the
  // bound itself is held by the draft and payload tests, and this says what
  // the cashier is told when they reach it.
  test('the line limit is said in the number it is', () {
    expect(
      CheckoutRefusal.forCode('invalid_line_count').message,
      'A sale needs between 1 and $maximumCheckoutSaleLines items.',
    );
  });

  testWidgets('removing the last item empties the cart', (tester) async {
    await _pump(tester, sessions, catalog, drafts);

    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-product-product-a');
    await _decrement(tester, 'product-a');

    expect(_text(tester, 'checkout-line-amount-product-a'), 'KES 120.50');

    await _tap(tester, 'checkout-line-remove-product-a');

    expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
    expect(_text(tester, 'checkout-total'), 'KES 0');
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
    final lottie = tester.widget<LottieBuilder>(
      find.byKey(const ValueKey('checkout-empty-cart-animation')),
    );
    expect(lottie.animate, isFalse);
    expect(lottie.controller!.value, 0.5);
    expect(find.byKey(const ValueKey('checkout-save-blocked')), findsNothing);
    expect(_save(tester).onPressed, isNull);
  });

  for (final size in [const Size(1400, 900), const Size(411, 891)]) {
    testWidgets('empty catalog artwork is centered below search at $size', (
      tester,
    ) async {
      catalog.put(uid: 'user-a', tenantId: 'tenant-a', products: const []);
      await _pumpAt(tester, sessions, catalog, drafts, size);
      final pane = tester.getRect(
        find.byKey(const ValueKey('checkout-products-pane')),
      );
      final search = tester.getRect(
        find.byKey(const ValueKey('checkout-search')),
      );
      final artwork = tester.getRect(
        find.byKey(const ValueKey('checkout-catalog-illustration')),
      );
      final copy = tester.getRect(
        find.byKey(const ValueKey('checkout-catalog-empty')),
      );
      expect(artwork.width, 168);
      expect(artwork.center.dx, closeTo(pane.center.dx, 0.5));
      expect(copy.center.dx, closeTo(pane.center.dx, 0.5));
      expect(copy.top, greaterThan(artwork.bottom));
      expect(artwork.top, greaterThan(search.bottom + 24));
      expect(copy.bottom, lessThan(pane.bottom));
      expect(tester.takeException(), isNull);
    });
  }

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
      expect(
        find.byKey(const ValueKey('checkout-catalog-empty')),
        findsNothing,
      );
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
      expect(
        find.byKey(const ValueKey('checkout-product-water')),
        findsNothing,
      );

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
      // The bar scrolls in one line beside the search on a till this wide, so
      // the last chip can be past its end.
      await _tapScrolled(tester, 'checkout-category-other');

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

  group('searching the catalog', () {
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

    testWidgets('a search narrows the list and adds nothing', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _enter(tester, 'checkout-search', 'cola');

      expect(find.byKey(const ValueKey('checkout-product-cola')), findsOne);
      expect(
        find.byKey(const ValueKey('checkout-product-water')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('checkout-line-cola')), findsNothing);
    });

    testWidgets('submitting an exact code adds nothing', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      // The scanner path was removed on 2026-08-23: this field searches and
      // never adds. Submitting the one code that names exactly one product is
      // the case that used to add it, so it is the case worth pinning.
      await _submit(tester, 'checkout-search', 'sku-cola');

      expect(find.byKey(const ValueKey('checkout-line-cola')), findsNothing);
      expect(find.byKey(const ValueKey('checkout-product-cola')), findsOne);
    });

    testWidgets('a code is searchable as text', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _enter(tester, 'checkout-search', 'sku-cola');

      expect(find.byKey(const ValueKey('checkout-product-cola')), findsOne);
      expect(
        find.byKey(const ValueKey('checkout-product-water')),
        findsNothing,
      );
    });

    testWidgets('a search matching nothing says so and adds nothing', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _submit(tester, 'checkout-search', 'nothing-carries-this');

      expect(
        find.byKey(const ValueKey('checkout-catalog-no-matches')),
        findsOne,
      );
      expect(drafts.requests, isEmpty);
    });

    testWidgets('tapping a searched card is what adds it', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _enter(tester, 'checkout-search', 'cola');
      await _tap(tester, 'checkout-product-cola');

      expect(find.byKey(const ValueKey('checkout-line-cola')), findsOne);
    });

    testWidgets('tapping the same card twice sells two of it', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-cola');
      await _tap(tester, 'checkout-product-cola');
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
          for (
            var index = 0;
            index < maximumRenderedCheckoutProducts + 5;
            index++
          )
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
        'search to find the rest.',
      );
    });

    testWidgets('a product past the cap is reachable by searching for it', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      // The cap bounds what is drawn, never what can be sold. Since
      // 2026-08-23 the way through it is to narrow the search until the
      // product is drawn, and then tap it - the code no longer adds directly.
      await _enter(tester, 'checkout-search', 'sku-product-064');
      await _tap(tester, 'checkout-product-product-064');
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

  group('typing a quantity', () {
    testWidgets('sells twelve of something in one entry', (tester) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-b');
      await _enter(tester, 'checkout-line-quantity-product-b', '12');

      expect(_text(tester, 'checkout-line-amount-product-b'), 'KES 84');

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

      expect(_text(tester, 'checkout-line-amount-product-b'), 'KES 70');
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
      expect(_text(tester, 'checkout-line-amount-product-b'), 'KES 7');
      expect(
        _text(tester, 'checkout-save-blocked'),
        'Enter a whole quantity between 1 and 1,000,000 for every item.',
      );
      expect(_save(tester).onPressed, isNull);
      expect(_quantityError(tester, 'product-b'), isNotNull);
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
      expect(_quantityError(tester, 'product-b'), isNull);
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
        'This sale is larger than this register can record. Reduce a quantity.',
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
        'This sale is larger than this register can record. Reduce a quantity.',
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

    /// A tablet: §4.1's `medium` band, at or above 768 and below 1024.
    ///
    /// **Its answer has now changed twice.** It got two panes originally, then a
    /// sheet when the till moved to the `expanded` floor for `design.md` §4.3,
    /// and two panes again since 2026-08-22 - Profound Verdant's tablet band is
    /// a two-column Items + Cart split, and `CLAUDE.md` makes §4.3 history.
    /// `docs/stitch/OPEN_QUESTIONS.md` item 21.
    const tablet = Size(900, 1000);

    testWidgets('puts the cart beside the products on a wide screen', (
      tester,
    ) async {
      await _pumpAt(tester, sessions, catalog, drafts, tillScreen);

      expect(find.byKey(const ValueKey('checkout-wide')), findsOne);
      // Both halves are on screen at once, which is the whole point of the
      // split: nothing about the sale is behind a tap.
      expect(
        find.byKey(const ValueKey('checkout-product-product-a')),
        findsOne,
      );
      expect(find.byKey(const ValueKey('checkout-cart-pane')), findsOne);
      expect(find.byKey(const ValueKey('checkout-open-cart')), findsNothing);
    });

    testWidgets('gives the medium band two panes, not a sheet', (tester) async {
      // **A cashier on a tablet sees the cart without tapping for it**, which is
      // the whole of the decision in `OPEN_QUESTIONS.md` item 21. This test read
      // the other way until 2026-08-22, on §4.3's authority; the assertions are
      // inverted rather than retuned because what the band *should* do changed,
      // not what it happens to measure.
      await _pumpAt(tester, sessions, catalog, drafts, tablet);

      expect(find.byKey(const ValueKey('checkout-wide')), findsOne);
      expect(find.byKey(const ValueKey('checkout-compact')), findsNothing);
      expect(find.byKey(const ValueKey('checkout-cart-pane')), findsOne);
      expect(find.byKey(const ValueKey('checkout-open-cart')), findsNothing);
    });

    testWidgets('the narrowest two-pane till still fits its own panes', (
      tester,
    ) async {
      // **768 exactly, which is the tightest case the new boundary admits.**
      // The cart pane is a fixed 420, so the products get 768 - 420 - 1 = 347 -
      // narrower than the 411 phone this layout is not used on. That is the one
      // number worth a test of its own: a `Row` whose children do not fit
      // overflows, and an overflow throws here, so this passing *is* the
      // assertion. If the cart pane ever grows, this is the test that says so.
      await _pumpAt(tester, sessions, catalog, drafts, const Size(768, 1000));

      expect(find.byKey(const ValueKey('checkout-wide')), findsOne);
      expect(find.byKey(const ValueKey('checkout-cart-pane')), findsOne);
      expect(find.byKey(const ValueKey('checkout-open-cart')), findsNothing);
    });

    testWidgets('asks the same question about a width that the widget does', (
      tester,
    ) async {
      // The boundary is §4.1's `medium` floor and not a figure this file
      // repeats. 767 is the last width that is not `medium`.
      expect(TenantCheckoutPanel.showsTwoPanes(768), isTrue);
      expect(TenantCheckoutPanel.showsTwoPanes(767), isFalse);
      expect(TenantCheckoutPanel.showsTwoPanes(411), isFalse);
      // Still true above the `expanded` floor, which this no longer reads - the
      // till is deliberately independent of it now.
      expect(TenantCheckoutPanel.showsTwoPanes(1024), isTrue);
      expect(TenantCheckoutPanel.showsTwoPanes(1400), isTrue);
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

    testWidgets('gives a wide tile its picture and the count already sold', (
      tester,
    ) async {
      // **The picture came back to the wide till on 2026-10-11.** The fixture
      // has no photograph, so the band draws the product's initials - which
      // is the band being there at all.
      await _pumpAt(tester, sessions, catalog, drafts, tillScreen);
      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-product-product-a');

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('checkout-product-product-a')),
          matching: find.byKey(
            const ValueKey('product-image-fallback-product-a'),
          ),
        ),
        findsOne,
      );
      expect(
        tester
            .widget<Badge>(
              find.byKey(const ValueKey('checkout-product-count-product-a')),
            )
            .isLabelVisible,
        isTrue,
      );
    });

    testWidgets('a long name and size fit a wide tile at its narrowest', (
      tester,
    ) async {
      // A `GridView` cell is a fixed box and a `Column` that does not fit one
      // throws, so these passing is the assertion. 768 is the narrowest
      // two-pane width and 1024 the narrowest three-column one.
      catalog.put(
        uid: 'user-a',
        tenantId: 'tenant-a',
        products: <TenantProduct>[
          _product(
            'tenant-a',
            'golden sunflower cooking oil family pack',
            sku: '5 litre jerrycan with tap',
            quantity: -3,
          ),
        ],
      );
      for (final size in const <Size>[Size(768, 1000), Size(1024, 768)]) {
        await _pumpAt(tester, sessions, catalog, drafts, size);
        expect(find.byKey(const ValueKey('checkout-wide')), findsOne);
      }
    });

    testWidgets('puts the search beside the categories from 1024 up', (
      tester,
    ) async {
      expect(TenantCheckoutPanel.searchesBesideCategories(1024), isTrue);
      expect(TenantCheckoutPanel.searchesBesideCategories(1023), isFalse);

      await _pumpAt(tester, sessions, catalog, drafts, tillScreen);
      expect(find.byKey(const ValueKey('checkout-browse-row')), findsOne);
    });

    testWidgets('stacks the search over the categories on a tablet', (
      tester,
    ) async {
      await _pumpAt(tester, sessions, catalog, drafts, tablet);
      expect(find.byKey(const ValueKey('checkout-browse-row')), findsNothing);
    });

    testWidgets('states the total beside a save that does not move', (
      tester,
    ) async {
      await _pumpAt(tester, sessions, catalog, drafts, tillScreen);
      await _tap(tester, 'checkout-product-product-b');

      final row = find.byKey(const ValueKey('checkout-commit-row'));
      expect(
        find.descendant(
          of: row,
          matching: find.byKey(const ValueKey('checkout-total')),
        ),
        findsOne,
      );
      final save = find.descendant(
        of: row,
        matching: find.byKey(const ValueKey('checkout-save')),
      );
      expect(save, findsOne);

      // **Half the row whatever the figure**: a save whose edge moved as the
      // total grew would move under the finger about to press it.
      final before = tester.getRect(save);
      await _enter(tester, 'checkout-line-quantity-product-b', '9999');
      expect(_text(tester, 'checkout-total'), 'KES 69993');
      expect(tester.getRect(save), before);
    });

    testWidgets('puts the cart behind a bar on a phone', (tester) async {
      await _pumpAt(tester, sessions, catalog, drafts, phone);

      expect(find.byKey(const ValueKey('checkout-compact')), findsOne);
      expect(
        find.byKey(const ValueKey('checkout-product-product-a')),
        findsOne,
      );
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
      //
      // **The word left this string in Phase 03.** The browse render's bar sets
      // `Total` as a label and the amount as money, and one `Text` cannot carry
      // two roles - so the bar is a label over a figure, and this key is on the
      // figure.
      expect(_text(tester, 'checkout-cart-bar-total'), 'KES 14');
      expect(
        tester
            .widget<Badge>(find.byKey(const ValueKey('checkout-cart-badge')))
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
      // **The sheet keeps its own line**, the card with the amount sentence:
      // the two-pane till's receipt row and its foot are wide-only.
      expect(
        _text(tester, 'checkout-line-amount-product-b'),
        '1 x KES 7 = KES 7',
      );
      expect(
        find.byKey(const ValueKey('checkout-line-each-product-b')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('checkout-commit-row')), findsNothing);
      expect(find.byKey(const ValueKey('checkout-tender-unset')), findsNothing);

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
      expect(_text(tester, 'checkout-total'), 'KES 7');

      // The sheet is its own route, so it does not rebuild when the panel
      // behind it does. Removing the only line has to empty it anyway.
      await _tap(tester, 'checkout-line-remove-product-b');

      expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
      expect(_text(tester, 'checkout-total'), 'KES 0');
    });
  });

  group('the till draws the design system rather than Material', () {
    testWidgets('gives the save the primary tier', (tester) async {
      // **`design.md` §2.1's own worked example, and it was still on screen.**
      // "Clear this sale is `destructive`, Save sale is `primary`. Today the
      // destructive action is the more prominent of the two." It was an
      // `OutlinedButton` above a `FilledButton`, so the two read as equals and
      // the destructive one came first.
      await _pump(tester, sessions, catalog, drafts);
      await _tap(tester, 'checkout-product-product-a');

      expect(_save(tester).tier, AppButtonTier.primary);
      // No clear at all since 2026-09-23: a line comes out on its own delete.
      expect(find.byKey(const ValueKey('checkout-clear-sale')), findsNothing);
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

      // The refusal notice this used to read went with the scanner path on
      // 2026-08-23: a search that matches nothing now says so in the grid
      // rather than as a refusal, because nothing was being refused.
      await _submit(tester, 'checkout-search', 'nothing-carries-this');
      expect(
        find.byKey(const ValueKey('checkout-catalog-no-matches')),
        findsOne,
      );

      // The search is still narrowing the list, and clearing it is what a
      // cashier does next rather than something this assertion needs.
      await _enter(tester, 'checkout-search', '');
      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');
      expect(snackNotice(tester).status, AppStatus.ok);
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

      expect(dialogNotice(tester).status, AppStatus.attention);
    });

    testWidgets('a receipt that did not print is stated beside the sale', (
      tester,
    ) async {
      // **Two notices, because two different things happened.** The sale is
      // durable and the receipt is not on paper, and folding those into one
      // sentence would make a printer fault read as a lost sale.
      drafts.printFailure = PrinterTransportCode.unreachable;
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      // **A modal since 2026-08-26, and it is the case that argues for one.**
      // Nothing came out of the printer, so no paper carries the number - a
      // snack bar would take the only copy off the screen after seven seconds.
      expect(find.byType(NoticeDialog), findsOne);
      expect(find.byType(AppSnackBar), findsNothing);
      // The sale's own outcome is in the title, so a printer fault can never
      // read as a lost sale.
      expect(find.text('Saved as CT-A7F-20260731-0001'), findsOne);
      expect(dialogNotice(tester).status, AppStatus.problem);
      // The sentence is `checkout_print_failures.dart`'s, not this screen's.
      expect(
        dialogNotice(tester).message,
        PrinterFailureNotice.of(PrinterTransportCode.unreachable).message,
      );
      // **And where the receipt went, which that sentence cannot say.** Those
      // messages are read by the print queue panel too, so the route belongs to
      // this surface rather than to the shared copy. `OPEN_QUESTIONS.md`'s
      // Phase 03 item 4 is the product decision it states.
      expect(
        find.textContaining('Open Receipts waiting from the business home'),
        findsOne,
      );
    });

    testWidgets('a stalled printer is attention rather than a problem', (
      tester,
    ) async {
      // The one code where the receipt may still come out of the machine, so
      // §2.1's `attention` rather than `problem`. Colour is not carrying this
      // on its own - the sentence names the jam and the cover.
      drafts.printFailure = PrinterTransportCode.writeTimeout;
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(dialogNotice(tester).status, AppStatus.attention);
    });

    testWidgets('no printer hands an owner the page that sets one up', (
      tester,
    ) async {
      sessions.open(
        uid: 'user-a',
        membership: _membership('tenant-a', role: TenantRole.owner),
      );
      drafts.printFailure = PrinterTransportCode.notConfigured;
      final opened = <BuildContext>[];
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        printerSetupReminder: _Reminder(),
        onSetUpPrinter: opened.add,
      );

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      // Nothing was queued without a printer, so nothing is waiting to send.
      expect(
        find.text('The sale itself is saved and syncs on its own.'),
        findsOne,
      );
      expect(find.textContaining('Open Receipts waiting'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('checkout-set-up-printer')));
      await tester.pumpAndSettle();

      // The dialog is off the screen before the page opens, so the page lands
      // over the till rather than over the dialog.
      expect(find.byType(NoticeDialog), findsNothing);
      expect(opened, hasLength(1));
    });

    testWidgets('a cashier is told, but not offered a page they cannot open', (
      tester,
    ) async {
      drafts.printFailure = PrinterTransportCode.notConfigured;
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        printerSetupReminder: _Reminder(),
        onSetUpPrinter: (_) => fail('a cashier cannot change the printer'),
      );

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(find.byType(NoticeDialog), findsOne);
      expect(
        find.byKey(const ValueKey('checkout-set-up-printer')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('checkout-printer-reminder-opt-out')),
        findsOne,
      );
    });

    testWidgets('don’t show again turns the next sale into a snack bar', (
      tester,
    ) async {
      final reminder = _Reminder();
      drafts.printFailure = PrinterTransportCode.notConfigured;
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        printerSetupReminder: reminder,
      );

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');
      await tester.tap(
        find.byKey(const ValueKey('checkout-printer-reminder-opt-out')),
      );
      await tester.pumpAndSettle();

      expect(reminder.silenced, <String>{'tenant-a'});
      expect(find.byType(NoticeDialog), findsNothing);

      // Still no printer, and now reported the way a printed sale is.
      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(find.byType(NoticeDialog), findsNothing);
      expect(find.byType(AppSnackBar), findsOne);
    });

    testWidgets('a printer that does not answer is never silenced', (
      tester,
    ) async {
      // Silencing is for a shop with no printer. One that is set up and does
      // not answer is a fault, and a setup page would not fix it.
      sessions.open(
        uid: 'user-a',
        membership: _membership('tenant-a', role: TenantRole.owner),
      );
      drafts.printFailure = PrinterTransportCode.unreachable;
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        printerSetupReminder: _Reminder()..silenced.add('tenant-a'),
        onSetUpPrinter: (_) {},
      );

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(find.byType(NoticeDialog), findsOne);
      expect(
        find.byKey(const ValueKey('checkout-set-up-printer')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('checkout-printer-reminder-opt-out')),
        findsNothing,
      );
    });

    testWidgets('a receipt that printed adds no second notice', (tester) async {
      // **Null is ambiguous by contract** - it means sent, and it also means a
      // build that queues no receipts at all - so the till draws nothing. Where
      // it printed, the paper is the proof and a green box is noise.
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(find.byType(AppSnackBar), findsOne);
      // The route line belongs to the failure, not to the sale, so a receipt
      // that reached the printer must not send anybody to the queue - and must
      // not raise a modal at all.
      expect(find.byType(NoticeDialog), findsNothing);
      expect(find.textContaining('Unprinted receipts'), findsNothing);
    });

    testWidgets('a till that cannot save says so as information', (
      tester,
    ) async {
      // §2.1's `info` is "offline, **read-only**, informational". Nothing was
      // attempted, so nothing was refused.
      await _pump(tester, sessions, catalog, null);

      expect(_status(tester, 'checkout-unavailable'), AppStatus.info);
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
      //
      // **The price left this string in Phase 03 and did not leave the tile.**
      // `OPEN_QUESTIONS.md` decision 23 sets money on this surface in `mono` and
      // `text.money`, which cannot be done to half of a sentence, so the tile
      // draws two texts where it drew one. `checkout-product-price-oversold` is
      // the other half and is asserted below.
      expect(_text(tester, 'checkout-product-stock-oversold'), '-3 in stock');
      expect(_text(tester, 'checkout-product-price-oversold'), 'KES 5');
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

      expect(_text(tester, 'checkout-product-stock-product-b'), '12 in stock');
      expect(_text(tester, 'checkout-product-price-product-b'), 'KES 7');
      // The freshness sentence that used to sit above the grid was removed on
      // 2026-08-23 to give the products the screen. The figure itself is what
      // a cashier reads, and it is still on the card.
      expect(
        find.byKey(const ValueKey('checkout-catalog-freshness')),
        findsNothing,
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
      expect(find.byType(AppSnackBar), findsOne);
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

      expect(_text(tester, 'checkout-product-stock-oversold'), '-3 in stock');

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
    // **Three outcomes on three surfaces since 2026-08-26**, where all three
    // used to be inline `Callout`s that stayed until the cashier pressed
    // *Close*. The split is by whether anybody has to act: a sale that saved
    // and printed is a snack bar and withdraws itself; the two that need
    // dealing with are modals that cannot.

    testWidgets('a saved sale is a snack bar, not a block on the till', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(
        snackNotice(tester).message,
        'Saved as CT-A7F-20260731-0001. It syncs on its own.',
      );
      expect(snackNotice(tester).status, AppStatus.ok);
      // Nothing is reserved for it in the till's own layout any more, which is
      // the point: the common case stopped pushing the cart down the screen.
      expect(find.byKey(const ValueKey('checkout-saved')), findsNothing);
      expect(find.byType(NoticeDialog), findsNothing);
    });

    testWidgets('it withdraws itself, so the next customer needs no press', (
      tester,
    ) async {
      // The old notice survived every later cart edit and was cleared only by
      // a press, because a cashier had to be able to read the number off the
      // screen. The number is on the paper now.
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');
      expect(find.byType(AppSnackBar), findsOne);

      await _waitOutSnackBar(tester);

      expect(find.byType(AppSnackBar), findsNothing);
      // And it took nothing else with it: the cart the cashier has started for
      // the next customer is untouched.
      await _tap(tester, 'checkout-product-product-b');
      expect(find.byKey(const ValueKey('checkout-line-product-b')), findsOne);
    });

    testWidgets('nothing is offered to copy, because paper carries it', (
      tester,
    ) async {
      // Owner direction, 2026-08-26: the customer has the printed receipt at
      // that moment, and receipt search has been simplified since. The control
      // and the clipboard write are both gone rather than hidden.
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(find.byKey(const ValueKey('checkout-copy-receipt')), findsNothing);
      expect(
        find.byKey(const ValueKey('checkout-receipt-copied')),
        findsNothing,
      );
    });

    testWidgets('a second save announces its own number, not the first', (
      tester,
    ) async {
      // **That a snack bar replaces rather than queues is asserted where the
      // component lives**, in `test/ui/snackbar_test.dart`. What this one is
      // for is the till: the second sale's number is the one announced.
      //
      // The first bar is waited out rather than saved through, because a
      // floating snack bar sits over the bottom of the pane and the save
      // control is down there - see the note on `_waitOutSnackBar`'s call here.
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');
      expect(snackNotice(tester).message, contains('CT-A7F-20260731-0001'));
      await _waitOutSnackBar(tester);

      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-tender-mpesa');
      await _tap(tester, 'checkout-save');

      expect(find.byType(AppSnackBar), findsOne);
      expect(snackNotice(tester).message, contains('CT-A7F-20260731-0002'));
      expect(
        snackNotice(tester).message,
        isNot(contains('CT-A7F-20260731-0001')),
      );
    });

    testWidgets('a refused save announces nothing about a receipt', (
      tester,
    ) async {
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');
      await _waitOutSnackBar(tester);

      drafts.refusal = 'no_open_shift';
      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      // A number beside a refusal reads as if the refused sale saved.
      expect(find.byType(AppSnackBar), findsNothing);
      expect(
        _notice(tester, 'checkout-refusal'),
        'Open a shift before selling.',
      );
    });

    testWidgets('a save with no receipt number is a modal, not a snack bar', (
      tester,
    ) async {
      // **This one cannot be allowed to withdraw itself unseen.** A cashier
      // must not read out a number the till could not produce, and §2.1's
      // `attention` - "unreconciled, pending, **awaiting**" - is what it is:
      // nothing failed, the sale is durable, the number is what is awaited.
      drafts.omitReceiptNumber = true;
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      expect(find.byType(NoticeDialog), findsOne);
      expect(find.byType(AppSnackBar), findsNothing);
      expect(dialogNotice(tester).status, AppStatus.attention);
      expect(
        dialogNotice(tester).message,
        startsWith('The sale is saved on this device'),
      );
      // Silence here would have the cashier ring the same sale up again, so
      // the bound on it is stated rather than left to be inferred.
      expect(find.textContaining('nothing needs ringing up again'), findsOne);
      expect(find.text('Saved without a receipt number'), findsOne);
    });

    testWidgets('the modal has to be answered rather than waited out', (
      tester,
    ) async {
      drafts.omitReceiptNumber = true;
      await _pump(tester, sessions, catalog, drafts);

      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-tender-cash');
      await _tap(tester, 'checkout-save');

      await _waitOutSnackBar(tester, AppSnackBar.actionableDwell);
      expect(find.byType(NoticeDialog), findsOne);

      await tester.tap(find.byKey(const ValueKey('checkout-dismiss-receipt')));
      // `_settle` pumps 60ms, short of the dialog's own exit animation.
      await tester.pumpAndSettle();
      expect(find.byType(NoticeDialog), findsNothing);
    });
  });

  testWidgets(
    'a business switch clears the cart, the search, and the receipt',
    (tester) async {
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
      expect(find.byType(AppSnackBar), findsOne);
      await _waitOutSnackBar(tester);

      sessions.open(uid: 'user-a', membership: _membership('tenant-b'));
      await _settle(tester);

      // Nothing from the first business may be carried into the second: not a
      // line and not a search term. A receipt number is no longer among them -
      // the confirmation is transient and had already withdrawn itself.
      expect(find.byType(AppSnackBar), findsNothing);
      expect(find.byKey(const ValueKey('checkout-cart-empty')), findsOne);
      expect(_field(tester, 'checkout-search').controller!.text, isEmpty);
      expect(_text(tester, 'checkout-total'), 'KES 0');
    },
  );

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

    expect(find.byType(AppSnackBar), findsNothing);
  });

  // `docs/stitch/OPEN_QUESTIONS.md` decision 35. The till used to answer this
  // read with one centred sentence, which said nothing about the screen and
  // then swapped a whole product grid in underneath it.
  group('a till reading its catalog still looks like a till', () {
    testWidgets('the search field is real, and says it is not ready', (
      tester,
    ) async {
      final catalog = _Catalog()
        ..put(uid: 'user-a', tenantId: 'tenant-a', products: <TenantProduct>[]);
      await _pumpUnsettledTill(tester, sessions, catalog);

      final search = tester.widget<AppTextField>(
        find.byKey(const ValueKey('checkout-search')),
      );
      // Present because its frame and label do not come from the read;
      // disabled because it cannot search a list that is not loaded, and a
      // field that swallows keystrokes is worse than one that says so.
      expect(search.enabled, isFalse);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('checkout-search')),
          matching: find.byType(SkeletonBlock),
        ),
        findsNothing,
      );

      await _settle(tester);
    });

    testWidgets('the products are the placeholders', (tester) async {
      final catalog = _Catalog()
        ..put(uid: 'user-a', tenantId: 'tenant-a', products: <TenantProduct>[]);
      await _pumpUnsettledTill(tester, sessions, catalog);

      expect(find.byKey(const ValueKey('checkout-loading')), findsOne);
      expect(find.byType(SkeletonBlock), findsWidgets);

      await _settle(tester);
    });

    testWidgets('a placeholder tile has a tile\'s parts, not one rectangle', (
      tester,
    ) async {
      // **This started as a single filled block per tile and that was a real
      // shortcoming.** A solid rectangle says only *something is coming here*;
      // it does not say the thing coming has a name at the top and a price at
      // the bottom, which is the entire argument for a skeleton over a spinner.
      //
      // Four parts at the wide till: the name, the code under it, the price and
      // the stock figure. Asserting "more than one" rather than an exact count
      // deliberately - the number is the tile's business and will change with
      // it; that there is *structure at all* is what must not regress.
      await _pumpUnsettledTill(
        tester,
        sessions,
        _Catalog()..put(
          uid: 'user-a',
          tenantId: 'tenant-a',
          products: <TenantProduct>[],
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('checkout-product-skeleton-0')),
          matching: find.byType(SkeletonBlock),
        ),
        findsAtLeast(2),
      );

      await _settle(tester);
    });

    testWidgets('an empty catalog answers with its sentence, not a skeleton', (
      tester,
    ) async {
      // The requirement that outranks all of this: an empty read has answered.
      final catalog = _Catalog()
        ..put(uid: 'user-a', tenantId: 'tenant-a', products: <TenantProduct>[]);
      await _pumpUnsettledTill(tester, sessions, catalog);
      await _settle(tester);

      expect(find.byKey(const ValueKey('checkout-catalog-empty')), findsOne);
      expect(find.byType(SkeletonBlock), findsNothing);
    });
  });

  testWidgets('the code is on the phone tile and on the cart line', (
    tester,
  ) async {
    await _pumpAt(tester, sessions, catalog, drafts, const Size(411, 1400));

    // The phone tile, which until 2026-09-29 dropped the code the wide tile
    // has always carried.
    expect(_text(tester, 'checkout-product-code-product-a'), 'sku-product-a');
    expect(tester.takeException(), isNull);

    await _tap(tester, 'checkout-product-product-a');
    await _tap(tester, 'checkout-open-cart');
    await tester.pump(const Duration(milliseconds: 500));

    expect(_text(tester, 'checkout-line-code-product-a'), 'sku-product-a');
  });

  group('agreeing a price', () {
    // **One row on a 360 phone, at the developer's direction of 2026-10-02.**
    // A `Wrap` of the two put them in a column on a Redmi, because either
    // button with its glyph is wider than half of what the phone has.
    testWidgets('sits on one row with Put on credit, on a narrow phone', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        sessions,
        catalog,
        drafts,
        const Size(360, 1400),
        loadPriceAgreement: _agreementPolicy(onDevice: <String>{'user-a'}),
        customers: CheckoutCustomerServices(reader: _Customers()),
      );
      await tester.tap(find.byKey(const ValueKey('screen-title-action')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('checkout-customer-$_janeId')),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-open-cart');
      await tester.pump(const Duration(milliseconds: 500));

      final agree = tester.getRect(
        find.byKey(const ValueKey('checkout-agree-price')),
      );
      final credit = tester.getRect(
        find.byKey(const ValueKey('checkout-put-on-credit')),
      );
      expect(agree.top, credit.top);
      expect(agree.right, lessThan(credit.left));
      expect(credit.right, lessThanOrEqualTo(360));
      expect(agree.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);

      // With a price agreed, still two on one row - and no third button.
      await _agree(tester, total: '6', reason: 'Regular customer');
      final change = tester.getRect(
        find.byKey(const ValueKey('checkout-change-agreed-price')),
      );
      expect(
        change.top,
        tester
            .getRect(find.byKey(const ValueKey('checkout-put-on-credit')))
            .top,
      );
      expect(
        find.byKey(const ValueKey('checkout-remove-agreed-price')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('is offered only to a person the business names', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        loadPriceAgreement: _agreementPolicy(onDevice: <String>{'user-b'}),
      );
      await _tap(tester, 'checkout-product-product-b');

      expect(find.byKey(const ValueKey('checkout-agree-price')), findsNothing);
    });

    testWidgets('a till with no setting wired offers nothing', (tester) async {
      await _pump(tester, sessions, catalog, drafts);
      await _tap(tester, 'checkout-product-product-b');

      expect(find.byKey(const ValueKey('checkout-agree-price')), findsNothing);
    });

    testWidgets('is not offered on an empty cart', (tester) async {
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        loadPriceAgreement: _agreementPolicy(onDevice: <String>{'user-a'}),
      );

      expect(find.byKey(const ValueKey('checkout-agree-price')), findsNothing);
    });

    testWidgets('records the agreed total and the reason with the sale', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        loadPriceAgreement: _agreementPolicy(onDevice: <String>{'user-a'}),
      );
      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-product-product-a');
      await _tap(tester, 'checkout-product-product-b');
      expect(_text(tester, 'checkout-total'), 'KES 248');

      await _agree(tester, total: '230', reason: 'Bought three');

      // The receipt's order: what was listed, what came off, what is paid.
      expect(_text(tester, 'checkout-agreed-list'), 'KES 248');
      expect(_text(tester, 'checkout-agreed-discount'), 'KES 18');
      expect(_text(tester, 'checkout-agreed-reason'), 'Reason: Bought three');
      expect(_text(tester, 'checkout-total'), 'KES 230');

      await _tap(tester, 'checkout-save');

      final request = drafts.requests.single;
      expect(request.agreedPrice?.totalMinor, 23000);
      expect(request.agreedPrice?.reason, 'Bought three');
      expect(
        request.discountMinor,
        0,
        reason: 'the agreed total is the one way money comes off',
      );
      // The next customer does not inherit it.
      expect(find.byKey(const ValueKey('checkout-agreed')), findsNothing);
      expect(
        find.byKey(const ValueKey('checkout-agreement-dropped')),
        findsNothing,
      );
    });

    testWidgets('a total not below the listed one, or no reason, is refused', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        loadPriceAgreement: _agreementPolicy(onDevice: <String>{'user-a'}),
      );
      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-agree-price');
      await _settleDialog(tester);

      await _enter(tester, 'agree-price-total', '7');
      await _tap(tester, 'agree-price-confirm');

      expect(
        _fieldError(tester, 'agree-price-total'),
        'The agreed total must be less than the listed KES 7.',
      );
      expect(
        _fieldError(tester, 'agree-price-reason'),
        'Say why, in at least 3 characters.',
      );
      expect(
        find.byKey(const ValueKey('agree-price-confirm')),
        findsOneWidget,
        reason: 'the dialog stays up until it can be answered',
      );

      await _enter(tester, 'agree-price-total', '0');
      await _tap(tester, 'agree-price-confirm');
      expect(
        _fieldError(tester, 'agree-price-total'),
        'The agreed total must be more than nothing.',
      );

      await _enter(tester, 'agree-price-total', '6.5');
      expect(
        _fieldHelper(tester, 'agree-price-total'),
        'KES 0.50 off the listed price',
      );

      await _tap(tester, 'agree-price-cancel');
      await _settleDialog(tester);
      expect(find.byKey(const ValueKey('checkout-agreed')), findsNothing);
      expect(_text(tester, 'checkout-total'), 'KES 7');
    });

    testWidgets('changing the items takes the agreed price off, and says so', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        loadPriceAgreement: _agreementPolicy(onDevice: <String>{'user-a'}),
      );
      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-product-product-b');
      await _agree(tester, total: '12', reason: 'Bought two');
      expect(_text(tester, 'checkout-total'), 'KES 12');

      await _tap(tester, 'checkout-product-product-b');

      expect(find.byKey(const ValueKey('checkout-agreed')), findsNothing);
      expect(_text(tester, 'checkout-total'), 'KES 21');
      expect(
        _notice(tester, 'checkout-agreement-dropped'),
        contains('because the items changed'),
      );
      expect(
        _status(tester, 'checkout-agreement-dropped'),
        AppStatus.attention,
      );
      // It stays while the cashier keeps editing, rather than vanishing on
      // the next keystroke.
      await _decrement(tester, 'product-b');
      expect(
        find.byKey(const ValueKey('checkout-agreement-dropped')),
        findsOneWidget,
      );

      await _tap(tester, 'checkout-save');
      expect(drafts.requests.single.agreedPrice, isNull);
    });

    testWidgets('the listed price can be put back', (tester) async {
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        loadPriceAgreement: _agreementPolicy(onDevice: <String>{'user-a'}),
      );
      await _tap(tester, 'checkout-product-product-b');
      await _agree(tester, total: '6', reason: 'Regular customer');

      // Inside the change dialog, so the till's row holds two buttons.
      await _tap(tester, 'checkout-change-agreed-price');
      await _settleDialog(tester);
      await _tap(tester, 'checkout-remove-agreed-price');
      await _settleDialog(tester);

      expect(find.byKey(const ValueKey('checkout-agreed')), findsNothing);
      expect(_text(tester, 'checkout-total'), 'KES 7');
      expect(
        find.byKey(const ValueKey('checkout-agreement-dropped')),
        findsNothing,
        reason: 'the cashier took it off, so there is nothing to explain',
      );
      expect(find.byKey(const ValueKey('checkout-agree-price')), findsOne);
    });

    testWidgets('the server answer wins over what this device held', (
      tester,
    ) async {
      // A phone that has never fetched the setting holds nothing, and the
      // server read is what brings it.
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        loadPriceAgreement: _agreementPolicy(onServer: <String>{'user-a'}),
      );
      await _tap(tester, 'checkout-product-product-b');

      expect(find.byKey(const ValueKey('checkout-agree-price')), findsOne);
    });

    testWidgets('a withdrawal that lands mid-sale takes the price off', (
      tester,
    ) async {
      final server = Completer<void>();
      await _pump(
        tester,
        sessions,
        catalog,
        drafts,
        loadPriceAgreement: _agreementPolicy(
          onDevice: <String>{'user-a'},
          onServer: <String>{},
          serverAnswers: server.future,
        ),
      );
      await _tap(tester, 'checkout-product-product-b');
      await _agree(tester, total: '6', reason: 'Regular customer');

      server.complete();
      await _settle(tester);

      expect(find.byKey(const ValueKey('checkout-agreed')), findsNothing);
      expect(find.byKey(const ValueKey('checkout-agree-price')), findsNothing);
      expect(
        _notice(tester, 'checkout-agreement-dropped'),
        contains('no longer lets you agree prices'),
      );
    });

    testWidgets('on a phone, the bar states the agreed total', (tester) async {
      await _pumpAt(
        tester,
        sessions,
        catalog,
        drafts,
        const Size(411, 900),
        loadPriceAgreement: _agreementPolicy(onDevice: <String>{'user-a'}),
      );
      await _tap(tester, 'checkout-product-product-b');
      await _tap(tester, 'checkout-open-cart');
      await tester.pump(const Duration(milliseconds: 500));

      await _tapScrolled(tester, 'checkout-agree-price');
      await _settleDialog(tester);
      await _enter(tester, 'agree-price-total', '6');
      await _enter(tester, 'agree-price-reason', 'Regular customer');
      await _tap(tester, 'agree-price-confirm');
      await _settleDialog(tester);

      expect(tester.takeException(), isNull);
      expect(_text(tester, 'checkout-cart-bar-total'), 'KES 6');
    });
  });
}

/// A policy this device holds and, where it differs, the one the server
/// answers with. Null is a document that is not there.
CheckoutPriceAgreementLoader _agreementPolicy({
  Set<String>? onDevice,
  Set<String>? onServer,
  Future<void>? serverAnswers,
}) => (session, {required cached}) async {
  if (!cached && serverAnswers != null) await serverAnswers;
  final allowed = cached ? onDevice : (onServer ?? onDevice);
  return allowed == null
      ? const TenantPublishedPriceAgreement.absent()
      : TenantPublishedPriceAgreement.published(
          TenantPriceAgreementPolicy(allowed: allowed),
        );
};

/// Opens *Agree a price*, answers it, and closes it.
Future<void> _agree(
  WidgetTester tester, {
  required String total,
  required String reason,
}) async {
  await _tap(tester, 'checkout-agree-price');
  await _settleDialog(tester);
  await _enter(tester, 'agree-price-total', total);
  await _enter(tester, 'agree-price-reason', reason);
  await _tap(tester, 'agree-price-confirm');
  await _settleDialog(tester);
}

/// A dialog's route transition, which `_settle`'s few frames do not cover.
Future<void> _settleDialog(WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String? _fieldError(WidgetTester tester, String key) =>
    tester.widget<AppTextField>(find.byKey(ValueKey(key))).error;

String? _fieldHelper(WidgetTester tester, String key) =>
    tester.widget<AppTextField>(find.byKey(ValueKey(key))).helper;

/// The till on its first frame, before the catalog read has answered.
Future<void> _pumpUnsettledTill(
  WidgetTester tester,
  TenantSessionController controller,
  _Catalog catalog,
) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: TenantCheckoutScreen(cache: catalog, drafts: null),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Catalog catalog,
  CheckoutDraftSink? drafts, {
  CheckoutPrinterSetupReminder? printerSetupReminder,
  void Function(BuildContext context)? onSetUpPrinter,
  CheckoutCartActivity? cartActivity,
  CheckoutPriceAgreementLoader? loadPriceAgreement,
  CheckoutCustomerServices? customers,
}) => _pumpAt(
  tester,
  controller,
  catalog,
  drafts,
  // Wide enough for the cart to sit beside the products, which is where every
  // test that is not about layout wants to be: it puts the whole till on
  // screen at once.
  const Size(1400, 4000),
  printerSetupReminder: printerSetupReminder,
  onSetUpPrinter: onSetUpPrinter,
  cartActivity: cartActivity,
  loadPriceAgreement: loadPriceAgreement,
  customers: customers,
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
  Size size, {
  bool reducedMotion = true,
  CheckoutPrinterSetupReminder? printerSetupReminder,
  void Function(BuildContext context)? onSetUpPrinter,
  CheckoutCartActivity? cartActivity,
  CheckoutPriceAgreementLoader? loadPriceAgreement,
  CheckoutCustomerServices? customers,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: TenantSessionScope(
        controller: controller,
        child: TenantCheckoutScreen(
          cache: catalog,
          drafts: drafts,
          printerSetupReminder: printerSetupReminder,
          onSetUpPrinter: onSetUpPrinter,
          cartActivity: cartActivity,
          loadPriceAgreement: loadPriceAgreement,
          customers: customers,
        ),
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
/// Advances past a snack bar's dwell and waits for it to leave.
///
/// **One big `pump` does not do it, and the reason is where Material starts the
/// clock.** `ScaffoldMessenger` schedules the dismissal timer inside a `.then()`
/// on the *entrance* animation, so the timer does not exist until that
/// animation has run to completion — and a single `pump(5s)` produces one frame
/// five seconds later rather than the frames the animation needs to finish.
/// Jumping the clock that way leaves the bar up with no timer ever set.
///
/// So: one jump past the dwell, then real frames until it goes.
Future<void> _waitOutSnackBar(
  WidgetTester tester, [
  Duration dwell = AppSnackBar.dwell,
]) async {
  await tester.pump(dwell + const Duration(seconds: 1));
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(AppSnackBar).evaluate().isEmpty) return;
  }
  await tester.pumpAndSettle();
}

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

  /// A `PrinterTransportCode` the sale comes back carrying, or null for a
  /// receipt that reached the printer.
  String? printFailure;
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
      receiptPrintFailure: printFailure,
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

final class _Reminder implements CheckoutPrinterSetupReminder {
  final Set<String> silenced = <String>{};

  @override
  bool isSilenced(String tenantId) => silenced.contains(tenantId);

  @override
  Future<void> silence(String tenantId) async => silenced.add(tenantId);
}

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.cashier,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

/// Presses the stepper's minus on one cart line.
///
/// The minus is `QuantityStepper`'s as of §11 step 7, so it is addressed
/// through the line's own key rather than by a key of its own - which is what
/// keeps a screen's tests pointed at the screen rather than at the component.
Future<void> _decrement(WidgetTester tester, String productId) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(ValueKey('checkout-line-quantity-$productId')),
      matching: find.byKey(const ValueKey('quantity-stepper-decrement')),
    ),
  );
  await _settle(tester);
}

/// The error the stepper is showing for one line, or null.
///
/// §5.2 gives a field one slot that holds either the helper line or the error,
/// so what used to be a keyed paragraph beside the row is now a property of the
/// control it is about.
String? _quantityError(WidgetTester tester, String productId) => tester
    .widget<QuantityStepper>(
      find.byKey(ValueKey('checkout-line-quantity-$productId')),
    )
    .error;

/// A customer ID shaped as the device mints them.
const String _janeId = 'cu_0123456789abcdef0123456789abcdef01234567';

/// A server holding one customer, answering searches the indexed way.
final class _Customers implements TenantDataReader, TenantCustomerSearchReader {
  _Customers({this.eReceipts, this.emailReceipts});

  /// The business's `configuration/e_receipts`, or null for none.
  final Map<String, Object?>? eReceipts;

  /// The business's `configuration/email_receipts`, or null for none.
  final Map<String, Object?>? emailReceipts;

  Map<String, Object?> get _jane {
    final search = tenantCustomerSearchFields(
      name: 'Jane Wanjiku',
      phone: '+254712345678',
    );
    return <String, Object?>{
      'name': 'Jane Wanjiku',
      'phone': '+254712345678',
      'kraPin': 'A012345678Z',
      'email': 'jane@example.com',
      'whatsappOptIn': true,
      'emailOptIn': true,
      'active': true,
      'searchName': search.searchName,
      'searchPrefixes': search.searchPrefixes,
    };
  }

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final settings = eReceipts;
    if (settings != null &&
        path == 'tenants/tenant-a/configuration/e_receipts') {
      return TenantDocumentSnapshot(path: path, data: settings);
    }
    final email = emailReceipts;
    if (email != null &&
        path == 'tenants/tenant-a/configuration/email_receipts') {
      return TenantDocumentSnapshot(path: path, data: email);
    }
    return null;
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantCustomers(
    TenantCustomerSearchQuery query,
  ) async {
    final prefix = query.searchPrefix;
    final jane = _jane;
    if (prefix != null &&
        !(jane['searchPrefixes']! as List<String>).contains(prefix)) {
      return const <TenantQueryDocumentSnapshot>[];
    }
    return <TenantQueryDocumentSnapshot>[
      TenantQueryDocumentSnapshot(
        path: '${query.collectionPath}/$_janeId',
        data: jane,
      ),
    ];
  }
}

final class _CustomerWriter implements TenantCustomerWriter {
  final List<TenantCustomerCreateIntent> created =
      <TenantCustomerCreateIntent>[];

  @override
  Future<TenantCustomerWriteResult> createCustomer(
    TenantCustomerCreateIntent intent,
  ) async {
    created.add(intent);
    return TenantCustomerWriteResult.queued('customer-create');
  }

  @override
  Future<TenantCustomerWriteResult> updateCustomer(
    TenantCustomerUpdateIntent intent,
  ) async => TenantCustomerWriteResult.queued(intent.operationId);
}

final class _EmailReceiptWriter implements TenantEmailReceiptWriter {
  final List<TenantEmailReceiptIntent> sent = <TenantEmailReceiptIntent>[];

  @override
  Future<void> send(TenantEmailReceiptIntent intent) async => sent.add(intent);
}

final class _ReceiptWriter implements TenantWhatsappReceiptWriter {
  final List<TenantWhatsappReceiptIntent> sent =
      <TenantWhatsappReceiptIntent>[];

  @override
  Future<void> send(TenantWhatsappReceiptIntent intent) async =>
      sent.add(intent);
}
