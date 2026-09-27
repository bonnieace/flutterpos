/// Every operational route: the till, the catalog, stock, reporting, sales,
/// returns, and the activity log.
///
/// Each one is the real route class the composition root pushes, given the same
/// readers and callables `lib/main.dart` gives it - so what a picture shows is
/// what the screen decides to show, including which controls its role is
/// offered.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uzapay_pos/audit/audit.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/expenses/expenses.dart';
import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/returns/returns.dart';
import 'package:uzapay_pos/sales/sales.dart';
import 'package:uzapay_pos/shift/shift.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:uzapay_pos/ui/scaffold.dart';
import 'package:uzapay_pos/ui/snackbar.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'harness.dart';
import 'image_http.dart';

late Uint8List _screenshotProductImage;

Widget _productVisual(TenantProduct product) => TenantProductVisual(
  product: product,
  imageProvider: product.imageUrl == null
      ? null
      : MemoryImage(_screenshotProductImage),
);

Future<void> _settleProductImages(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pump();
}

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

/// Opens the correction dialog on the seeded white bread, on whichever session
/// the case is rendering under.
///
/// **Shared by `19` and `19b` rather than spelled twice**, because the two
/// differ only in the session and the choreography below is the part with the
/// traps in it.
Future<void> _openProductCorrection(WidgetTester tester) async {
  final menu = find.byKey(const ValueKey('inventory-actions-pd-bread-white'));
  // The route is one long `ListView`, so a row below the fold has not been
  // built yet and `ensureVisible` has nothing to scroll to. Scrolling until it
  // appears is the only way to reach it, which is also what a person does.
  // The route's own list is named explicitly: the category strip inside it
  // scrolls too, and `scrollUntilVisible` insists on exactly one candidate.
  await tester.scrollUntilVisible(
    menu,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 30,
  );
  // **`scrollUntilVisible` stops when the widget is built, not when it is on
  // screen**, so at 411 this tap was landing below the fold and missing: every
  // `mobile/19-correct-a-product` capture ever taken photographed the list
  // rather than the dialog the case exists for. Found 2026-08-14 by the catalog
  // sweep, which hit the same thing in a widget test on the same route. The
  // same class as the seeded-record trap - a capture case whose picture is not
  // of the state it names.
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  await tester.tap(menu);
  await tester.pumpAndSettle();
  final edit = find.byKey(
    const ValueKey('catalog-management-edit-pd-bread-white'),
  );
  await tester.tap(edit);
}

/// Opens the correction dialog and chooses a photograph in its image well.
///
/// Shared by the three image cases, which differ only in what the removal
/// service does next.
Future<void> _chooseCorrectionImage(WidgetTester tester) async {
  FilePicker.platform = FakeProductImagePicker(_screenshotProductImage);
  await _openProductCorrection(tester);
  await tester.pumpAndSettle();
  final replace = find.byKey(const ValueKey('inventory-replace-image'));
  await tester.ensureVisible(replace);
  await tester.pumpAndSettle();
  await tester.tap(replace);
  await tester.pumpAndSettle();
  // `Image.memory` decodes asynchronously, and a widget test's fake-async zone
  // never lets that future complete - which is why the catalog rows have the
  // same helper. Without it the well photographs as an empty box.
  await _settleProductImages(tester);
  // Reaching the button scrolled the picture off the top on a phone, and a
  // capture of the image form that does not contain the image is the trap
  // `19-correct-a-product` already fell into once.
  //
  // **The picture rather than the `Product image` heading, which went on
  // 2026-08-26.** The image well is the only thing that draws it, at every
  // width, since the form went back to being a route on 2026-09-02.
  await tester.ensureVisible(
    find.byKey(const ValueKey('inventory-product-image-preview')),
  );
  await tester.pumpAndSettle();
}

/// Presses *Remove background* on a form that already holds a photograph.
Future<void> _pressCutOut(WidgetTester tester) async {
  final cutOut = find.byKey(const ValueKey('inventory-remove-background'));
  await tester.ensureVisible(cutOut);
  await tester.pumpAndSettle();
  await tester.tap(cutOut);
}

/// One canonical sale, decoded the way every sales surface decodes one.
TenantSale _sale(String saleId) => TenantSale.fromDocument(
  path: 'tenants/$seedTenantId/sales/$saleId',
  data: seedSales()[saleId]!,
);

void main() {
  setUpAll(
    () async => _screenshotProductImage = await screenshotProductImage(),
  );

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

  // No printer set up, seen by an owner: the one print outcome that offers its
  // setup page and can be silenced for the business.
  screenshotCase(
    '15b-sale-saved-no-printer',
    build: () => inSession(
      TenantCheckoutScreen(
        cache: FakeCatalogSource(),
        drafts: FakeDraftSink(
          printFailure: PrinterTransportCode.notConfigured,
        ),
        printerSetupReminder: _NeverSilenced(),
        onSetUpPrinter: (_) {},
      ),
      controller: seedSession(),
    ),
    afterPump: (tester) async {
      await _press(tester, 'checkout-product-pd-bread-white');
      final openCart = find.byKey(const ValueKey('checkout-open-cart'));
      if (openCart.evaluate().isNotEmpty) {
        await tester.tap(openCart);
        await tester.pumpAndSettle();
      }
      await _press(tester, 'checkout-tender-cash');
      await _press(tester, 'checkout-save');
    },
  );

  // **The sale that was not written, which is the till state no image held.**
  // Hard rule 5 asks for a component's whole matrix in the harness; `15` is the
  // cart before a save, `15b` is a sale that saved, and the refusal branch - the
  // one ST-036 invents a cause for - was reachable only from a widget test. The
  // code is one this build does not model, so `CheckoutRefusal` falls to its
  // generic sentence, which is the exact copy `LIVE_PHASE_HANDOFF.md` says
  // ST-036 should have used.
  screenshotCase(
    '15c-sale-refused',
    build: () => inSession(
      TenantCheckoutScreen(
        cache: FakeCatalogSource(),
        drafts: FakeDraftSink(refusalCode: 'storage_unavailable'),
      ),
      controller: seedSession(role: TenantRole.cashier, uid: cashierUid),
    ),
    afterPump: (tester) async {
      await _press(tester, 'checkout-product-pd-bread-white');
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
    viewports: responsiveViewports,
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
    viewports: responsiveViewports,
  );

  // **The index the settings strip became**, photographed for the reason `16b`
  // above records one screen over: a surface that appears in no capture is a
  // surface nobody is checking. The index is where every standing is stated, so
  // it is the one place a wrong standing would be visible at all.
  screenshotCase(
    '16c-settings-index',
    build: () {
      final reader = FakeTenantReader.business();
      return inSession(
        TenantSettingsScreen(
          standings: (session) => TenantSettingsStandingsRepository(
            session: session,
            reader: reader,
          ).read(collectionReader: reader),
          destinations: _settingsDestinations(reader),
        ),
      );
    },
    viewports: responsiveViewports,
  );

  // **The printer page with the receipt branding under it**, which is where the
  // brand name, slogan and logo moved when *Business details* went, on
  // 2026-09-23.
  screenshotCase(
    '16c2-settings-printer-and-branding',
    build: () {
      final reader = FakeTenantReader.business();
      return inSession(
        TenantSettingsScreen(
          initialSettingKey: 'printer',
          destinations: _settingsDestinations(reader),
        ),
      );
    },
    viewports: responsiveViewports,
  );

  // The one standing that raises a callout above the list. A business with no
  // published currency cannot ring up a sale on any device, which is a
  // different kind of fact from a printer nobody has set up - and this is the
  // only capture in which that callout exists.
  screenshotCase(
    '16d-settings-index-no-currency',
    build: () {
      final reader = FakeTenantReader(
        documents: const <String, Map<String, Object?>>{},
        collections: <String, Map<String, Map<String, Object?>>>{
          'tenants/$seedTenantId/configuration': <String, Map<String, Object?>>{
            'branding': <String, Object?>{'companyName': seedTenantName},
          },
        },
      );
      return inSession(
        TenantSettingsScreen(
          standings: (session) => TenantSettingsStandingsRepository(
            session: session,
            reader: reader,
          ).read(collectionReader: reader),
          destinations: _settingsDestinations(reader),
        ),
      );
    },
    viewports: responsiveViewports,
  );

  // **Stock counts, opened from the index**, drawn to `docs/design/stock-counts/`
  // and photographed with that design's own shop so the two can be laid side
  // by side: six categories, eight people, and a rota with one gap and one
  // category down to somebody who has been deactivated. It goes through
  // `TenantSettingPage`, so the toolbar, the inset and the scroll are the
  // host's and not a stand-in.
  screenshotCase(
    '16e-stock-counts',
    build: () => inSession(
      _stockCountsPage(
        _stockCountsReader(schedule: _stockCountsSchedule),
        writer: FakeConfigurationDocumentWriter(),
      ),
    ),
    viewports: responsiveViewports,
  );

  // A build with no writer: the answers as text, only the chosen card, and no
  // Save - rather than controls that look editable and are not.
  screenshotCase(
    '16f-stock-counts-read-only',
    build: () => inSession(
      _stockCountsPage(_stockCountsReader(schedule: _stockCountsSchedule)),
    ),
  );

  // A published document nobody can parse. The form seeds from the schedule
  // that interrupts nobody, which is also exactly what the till is doing.
  screenshotCase(
    '16g-stock-counts-damaged',
    build: () => inSession(
      _stockCountsPage(
        _stockCountsReader(
          schedule: const <String, Object?>{'enforcement': 'sometimes'},
        ),
        writer: FakeConfigurationDocumentWriter(),
      ),
    ),
  );

  // One person's choice open on a phone: `AppSelect`'s own menu, with the
  // current answer marked.
  screenshotCase(
    '16h-stock-counts-choice-open',
    build: () => inSession(
      _stockCountsPage(
        _stockCountsReader(schedule: _stockCountsSchedule),
        writer: FakeConfigurationDocumentWriter(),
      ),
    ),
    viewports: const <ScreenshotViewport>[mobileViewport],
    fullPage: false,
    afterPump: (tester) async {
      final select = find.byKey(const ValueKey('stock-take-assign-st-peter'));
      await tester.ensureVisible(select);
      await tester.pumpAndSettle();
      await tester.tap(select);
      await tester.pumpAndSettle();
    },
  );

  // **Counting the shelf**, photographed with the shop the stock count design
  // shows: 240 products, 118 counted, one a zero, one left empty, and one box
  // holding a number that is not a count. The invalid figure is typed after
  // the pump, because an invalid number is never recorded - it exists only in
  // the box, which is exactly what the row is saying.
  screenshotCase(
    '16i-stock-count',
    build: () => inSession(
      _stockCountScreen(),
      controller: seedSession(role: TenantRole.cashier, uid: cashierUid),
    ),
    viewports: const <ScreenshotViewport>[webViewport, mobileViewport],
    fullPage: false,
    afterPump: (tester) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('stock-take-line-pd-fanta')),
          matching: find.byType(TextField),
        ),
        '1000001',
      );
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    },
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
    viewports: responsiveViewports,
  );

  // **The same route as a cashier, which is the session the brief actually
  // names.** Phase 04's first required screen is the read-only catalog "for all
  // active roles", and every capture of it ran as owner - so the one role whose
  // catalog is *only* readable had no picture at all. The build is `17`'s
  // unchanged, including all three stock routes and their role lists: what
  // differs is the session, so the absence of the stock entries is the screen's
  // own decision rather than a build that withheld them.
  screenshotCase(
    '17b-read-only-catalog-cashier',
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
        controller: seedSession(role: TenantRole.cashier, uid: cashierUid),
      );
    },
    viewports: responsiveViewports,
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
          productVisualBuilder: _productVisual,
          bulkRoute: (_) => TenantBulkCatalogScreen(
            reader: reader,
            batchCallable: FakeCallable(),
            importCallable: FakeCallable(),
          ),
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
    afterPump: _settleProductImages,
    viewports: responsiveViewports,
  );

  screenshotCase(
    '18a-manage-catalog-actions',
    build: () {
      final reader = FakeTenantReader.business();
      return inSession(
        TenantCatalogManagementScreen(
          reader: reader,
          writer: FakeCatalogWriter(),
          updateCallable: FakeCallable(),
          productVisualBuilder: _productVisual,
          bulkRoute: (_) => TenantBulkCatalogScreen(
            reader: reader,
            batchCallable: FakeCallable(),
            importCallable: FakeCallable(),
          ),
          productStockRoute: (product) =>
              TenantProductStockScreen(reader: reader, product: product),
          productStockRoles: TenantProductStockRepository.allowedRoles,
        ),
      );
    },
    afterPump: (tester) async {
      await _settleProductImages(tester);
      await tester.tap(find.byTooltip('Product actions').first);
      await tester.pumpAndSettle();
    },
    viewports: const <ScreenshotViewport>[mobileViewport],
  );

  screenshotCase(
    '18e-inventory-cashier',
    build: () {
      final reader = FakeTenantReader.business();
      return inSession(
        TenantCatalogManagementScreen(
          reader: reader,
          writer: FakeCatalogWriter(),
          updateCallable: FakeCallable(),
          productVisualBuilder: _productVisual,
          bulkRoute: (_) => TenantBulkCatalogScreen(
            reader: reader,
            batchCallable: FakeCallable(),
            importCallable: FakeCallable(),
          ),
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
        controller: seedSession(role: TenantRole.cashier, uid: cashierUid),
      );
    },
    afterPump: _settleProductImages,
    viewports: responsiveViewports,
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
    viewports: responsiveViewports,
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
      await tester.tap(find.byKey(const ValueKey('inventory-categories')));
      await tester.pumpAndSettle();
      final field = find.byKey(
        const ValueKey('catalog-management-category-name'),
      );
      await tester.scrollUntilVisible(
        field,
        300,
        // **The categories route's own scrollable, by key.** It is a pushed
        // route since 2026-09-04, so the catalog list underneath is still in
        // the tree and `find.byType(Scrollable).first` reaches that one.
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('inventory-categories-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
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
      await tester.pageBack();
      await tester.pumpAndSettle();
      // **The confirmation is a snack bar since 2026-08-26**, so this capture
      // no longer scrolls the route back to an inline notice near the top - it
      // photographs the bar where it actually appears, over the bottom of the
      // page the person is still standing on.
      //
      // `pumpAndSettle` leaves it up: the messenger's dismissal timer is
      // scheduled after the entrance animation and needs real frames to fire,
      // which settling does not provide. That is what makes this capturable.
      expect(find.byType(AppSnackBar), findsOne);
      // **`Frozen` is deliberately not in the chip strip in this picture.**
      // `FakeCatalogWriter` answers `committed` without writing to the fake
      // reader, so the re-read the panel correctly performs returns the same
      // three seeded categories. That is the fixture rather than the screen, and
      // it is said here so nobody reads the image as a defect.
    },
    viewports: responsiveViewports,
  );

  // **The management list as a manager, which is the one session on this route
  // that sees a structurally different page.** `18`, `18b`, `18c` and `19` all
  // run as owner, so the narrowing this phase's first acceptance criterion is
  // about - `Retire` absent from every row, and the notice that says why -
  // appeared in none of the 413 images. `canRetire` is owner and administrator
  // only (`catalog_management.dart:338`) and the row actions read it at `:756`;
  // this is the picture of the other side of that branch.
  screenshotCase(
    '18d-manage-catalog-manager',
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
        controller: seedSession(role: TenantRole.manager, uid: managerUid),
      );
    },
    viewports: responsiveViewports,
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
    afterPump: _openProductCorrection,
    viewports: responsiveViewports,
  );

  // **The same form as a manager**, which is where owner and manager differ most
  // on this route: `canChangeMoney` is `canRecordCostInSession`
  // (`catalog_management_panel.dart:414`), so the price field, the cost field
  // and the clear-cost act are all absent and a single `info` notice stands
  // where they were. That notice - `catalog-management-edit-money-hidden` - is
  // very nearly the sentence ST-039's own section 2 draws, and until this
  // capture it had never been rendered into an image.
  screenshotCase(
    '19b-correct-a-product-manager',
    build: () => inSession(
      TenantCatalogManagementScreen(
        reader: FakeTenantReader.business(),
        writer: FakeCatalogWriter(),
        updateCallable: FakeCallable(),
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
    afterPump: _openProductCorrection,
    viewports: responsiveViewports,
  );

  // -------------------------------------------------------------------------
  // The image well, restored 2026-08-25
  // -------------------------------------------------------------------------

  // **`19` and `19b` are both built without an image store**, so neither has
  // ever photographed the half of this form that holds the picture. These four
  // are that half: the old catalog form's bordered well, the photograph at the
  // size the old form drew it, and the cut-out action in each of the states it
  // has.
  screenshotCase(
    '19c-correct-a-product-image',
    build: () => inSession(
      TenantCatalogManagementScreen(
        reader: FakeTenantReader.business(),
        writer: FakeCatalogWriter(),
        updateCallable: FakeCallable(),
        imageStore: const FakeProductImageStore(),
        backgroundRemover: FakeBackgroundRemover(_screenshotProductImage),
      ),
    ),
    // Nothing chosen yet, so the well says so in words and the cut-out is
    // drawn disabled rather than removed - §5's `disabled` row.
    afterPump: _openProductCorrection,
    viewports: responsiveViewports,
  );

  screenshotCase(
    '19d-correct-a-product-image-chosen',
    build: () => inSession(
      TenantCatalogManagementScreen(
        reader: FakeTenantReader.business(),
        writer: FakeCatalogWriter(),
        updateCallable: FakeCallable(),
        imageStore: const FakeProductImageStore(),
        backgroundRemover: FakeBackgroundRemover(_screenshotProductImage),
      ),
    ),
    afterPump: _chooseCorrectionImage,
    viewports: responsiveViewports,
  );

  // The loading row. `settle: false` because a spinner never reaches a quiet
  // frame, which is the escape hatch `captureScreen` documents.
  screenshotCase(
    '19e-cutting-out-a-background',
    build: () => inSession(
      TenantCatalogManagementScreen(
        reader: FakeTenantReader.business(),
        writer: FakeCatalogWriter(),
        updateCallable: FakeCallable(),
        imageStore: const FakeProductImageStore(),
        backgroundRemover: const FakeBackgroundRemover.holding(),
      ),
    ),
    settle: false,
    // The full-page pass re-renders and settles whatever `settle` said, so a
    // frame that never quietens cannot have one. The dialog is an overlay and
    // is wholly inside the viewport either way.
    fullPage: false,
    afterPump: (tester) async {
      await _chooseCorrectionImage(tester);
      await _pressCutOut(tester);
      await tester.pump();
    },
    viewports: const <ScreenshotViewport>[mobileViewport, webViewport],
  );

  // The error row, and the sentence that matters in it: the photograph the
  // operator chose is still there.
  screenshotCase(
    '19f-cut-out-refused',
    build: () => inSession(
      TenantCatalogManagementScreen(
        reader: FakeTenantReader.business(),
        writer: FakeCatalogWriter(),
        updateCallable: FakeCallable(),
        imageStore: const FakeProductImageStore(),
        backgroundRemover: const FakeBackgroundRemover.refusing(
          TenantBackgroundRemovalFailure.allowanceSpent,
        ),
      ),
    ),
    afterPump: (tester) async {
      await _chooseCorrectionImage(tester);
      await _pressCutOut(tester);
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
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
    viewports: responsiveViewports,
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
      viewports: responsiveViewports,
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
    viewports: responsiveViewports,
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
    viewports: responsiveViewports,
  );

  // **The correcting half, photographed for the first time.** `21` and `21b`
  // both build the reading route, so every capture of this family since the
  // 2026-08-25 split has shown the ledger and none has shown the form - which
  // is the "a fixture that hides the case the component exists for" trap this
  // family has already recorded once.
  screenshotCase(
    '21c-adjust-stock-screen',
    build: () => inSession(
      _SheetHost(
        open: (context) => openTenantProductStockAdjustmentScreen(
          context,
          reader: FakeTenantReader.business(),
          product: seedProduct('pd-bread-white'),
          actions: TenantStockActions(adjustCallable: FakeCallable()),
        ),
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
    viewports: responsiveViewports,
  );

  // The same screen on a product the server holds a negative quantity for,
  // which is the one state of the figure above the form that carries a status.
  screenshotCase(
    '21d-adjust-stock-below-zero',
    build: () => inSession(
      _SheetHost(
        open: (context) => openTenantProductStockAdjustmentScreen(
          context,
          reader: FakeTenantReader.business(),
          product: seedProduct('pd-milk-500'),
          actions: TenantStockActions(adjustCallable: FakeCallable()),
        ),
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '22-stock-corrections',
    build: () => inSession(
      TenantStockAdjustmentFeedScreen(reader: FakeTenantReader.business()),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
    viewports: responsiveViewports,
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
    viewports: responsiveViewports,
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
    viewports: responsiveViewports,
  );

  // -------------------------------------------------------------------------
  // Reporting
  // -------------------------------------------------------------------------

  // **The old app's weekly Reports & Analytics page**, on the slot the daily
  // summary used to hold. The clock is fixed so the seven bars, the week label
  // and the comparison are the same picture every run.
  screenshotCase(
    '25b-weekly-report',
    build: () {
      final reader = FakeTenantReader.business();
      return inSession(
        TenantWeeklyReportScreen(
          reader: reader,
          callable: FakeSalesComparisonCallable(
            salesByBusinessDate: _weeklyReportSeed(),
          ),
          salesRepositoryFactory: (session) => TenantSaleHistoryRepository(
            session: session,
            reader: reader,
            reportReader: reader,
          ),
          clock: () => _weeklyReportClock,
        ),
      );
    },
    viewports: responsiveViewports,
  );

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
    viewports: responsiveViewports,
  );

  screenshotCase(
    '26-sales-totals',
    build: () => inSession(
      TenantSalesTotalsScreen(
        callable: FakeCallable(seedSalesTotalsResponse()),
        reader: FakeTenantReader.business(),
      ),
    ),
    viewports: responsiveViewports,
  );

  // **The monthly report, which had never been in a picture at all.** It was
  // the only routed report screen with neither a widget test nor a capture,
  // and that is how it came to print a profit the totals page and the weekly
  // report both withhold. Two cases, because the withheld reading is the one
  // that was wrong and a picture of the happy path would not have caught it.
  screenshotCase(
    '26b-monthly-report',
    build: () => inSession(
      TenantMonthlyReportScreen(
        callable: FakeCallable(seedSalesTotalsResponse()),
        reader: FakeTenantReader.business(),
        clock: () => _weeklyReportClock,
      ),
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '26c-monthly-report-profit-withheld',
    build: () => inSession(
      TenantMonthlyReportScreen(
        callable: FakeCallable(_monthlyIncompleteCostResponse()),
        reader: FakeTenantReader.business(),
        clock: () => _weeklyReportClock,
      ),
    ),
    viewports: responsiveViewports,
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
    viewports: responsiveViewports,
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
    viewports: responsiveViewports,
  );

  screenshotCase(
    '28-reconciliation-differences',
    build: () => inSession(
      TenantReconciliationAnomalyScreen(
        reader: FakeTenantReader.business(),
        actions: fakeReconciliationActions(),
      ),
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '29-one-reconciliation-run',
    build: () => inSession(
      TenantReconciliationRunScreen(
        reader: FakeTenantReader.business(),
        jobId: 'rj_000001',
      ),
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '30-shift-corrections',
    build: () => inSession(
      TenantShiftAmendmentScreen(reader: FakeTenantReader.business()),
    ),
    viewports: responsiveViewports,
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
    viewports: responsiveViewports,
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
    viewports: responsiveViewports,
  );

  screenshotCase(
    '32-shift-history',
    build: () => inSession(
      _shiftHistory(),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
    viewports: responsiveViewports,
  );

  // **Where a card goes since 2026-09-22**: the Sales report, on the shift's
  // day and narrowed to whoever ran it - the morning shift is the cashier's, so
  // the staff select reads their name rather than *All staff*.
  screenshotCase(
    '32b-shift-history-to-sales',
    build: () => inSession(
      _shiftHistory(),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
    afterPump: (tester) async {
      await tester.tap(
        find.byKey(const ValueKey('shift-history-sales-link-shift-morning')),
      );
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
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
    viewports: responsiveViewports,
  );

  // **A sheet over the sale list since 2026-08-26**, where this was a pushed
  // route. `_SheetHost` opens it on the first frame so the capture is of the
  // composition a person actually gets: the scrim, the handle, the sheet's own
  // header, the one fold that replaced three pieces of standing prose, and the
  // `Record return` / `Cancel` pair.
  screenshotCase(
    '34-returns-on-a-sale',
    build: () => inSession(
      _SheetHost(
        open: (context) => openTenantSaleReturnSheet(
          context,
          reader: FakeTenantReader.business(),
          request: TenantSaleReturnsRequest(sale: _sale('co-1')),
          actions: fakeReturnActions(),
        ),
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
    viewports: responsiveViewports,
  );

  // **The same route as a cashier, which is the session the role standing is
  // for.** `34` runs as a manager, who may verify, so the notice saying a
  // recorded return waits for management renders in none of its images - the
  // "a conditional section invisible in every capture is not covered" trap
  // again, caught this time by the change moving zero pixels.
  screenshotCase(
    '34b-returns-as-a-cashier',
    build: () => inSession(
      _SheetHost(
        open: (context) => openTenantSaleReturnSheet(
          context,
          reader: FakeTenantReader.business(),
          request: TenantSaleReturnsRequest(sale: _sale('co-1')),
          actions: fakeReturnActions(),
        ),
      ),
      controller: seedSession(role: TenantRole.cashier, uid: cashierUid),
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '35-activity-log',
    build: () => inSession(
      TenantAuditLogScreen(reader: FakeTenantReader.business()),
      controller: seedSession(role: TenantRole.admin, uid: adminUid),
    ),
    viewports: responsiveViewports,
  );

  // **The returns feed had no capture at all until 2026-08-28**, which is how
  // its cards went a whole redesign without anybody being able to look at them.
  // Manager, because verifying a return is what this route is for and a role
  // that cannot verify photographs a page with its actions missing.
  screenshotCase(
    '35-returns-feed',
    build: () => inSession(
      TenantReturnFeedScreen(
        reader: FakeTenantReader.business(),
        actions: fakeReturnActions(),
      ),
      controller: seedSession(),
    ),
    viewports: responsiveViewports,
  );

  // **The route that makes profit whole.** Owner, because reading spending is
  // owner and administrator only - the same tier a margin sits behind - so a
  // capture under any other role would photograph the refusal.
  screenshotCase(
    '36-expenses',
    build: () => inSession(
      TenantExpensesScreen(
        reader: FakeTenantReader.business(),
        writer: _FakeExpenseWriter(),
      ),
      controller: seedSession(),
    ),
    viewports: responsiveViewports,
  );

  // One heading on its own, which is the only place the day-by-day chart is
  // drawn.
  //
  // **Reached by pressing the row rather than built directly**, because
  // `TenantReportingCurrency` can only be produced by reading a business's own
  // configuration - there is no synthetic one, deliberately, so that no surface
  // can invent a currency. Navigating gets the real thing and photographs the
  // real route into the bargain.
  screenshotCase(
    '37-expenses-one-category',
    build: () => inSession(
      TenantExpensesScreen(
        reader: FakeTenantReader.business(),
        writer: _FakeExpenseWriter(),
      ),
      controller: seedSession(),
    ),
    afterPump: (tester) async {
      final row = find.byKey(const ValueKey('expense-open-transport'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
  );

  // -------------------------------------------------------------------------
  // Stock counts
  // -------------------------------------------------------------------------

  // One count in each standing the filter offers.
  screenshotCase(
    '38-stock-counts',
    build: () => inSession(
      TenantStockTakeReviewScreen(
        reader: _stockTakeReader(),
        countRoute: (context) => const SizedBox.shrink(),
      ),
      controller: seedSession(),
    ),
    viewports: responsiveViewports,
  );

  // The count that needs review, opened: what differs, biggest first, and the
  // accept pinned under it.
  screenshotCase(
    '38b-the-count',
    build: () => inSession(
      TenantStockTakeReviewScreen(
        reader: _stockTakeReader(),
        applyCallable: _NeverStockTakeApply(),
      ),
      controller: seedSession(),
    ),
    fullPage: false,
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('stock-take-$_reviewTakeId')));
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
  );

  // -------------------------------------------------------------------------
  // Sales
  // -------------------------------------------------------------------------

  screenshotCase(
    '39-set-payment-method',
    build: () => inSession(
      _SheetHost(
        open: (context) => showSaleTenderDialog(context, sale: _sale('co-1')),
      ),
      controller: seedSession(),
    ),
    viewports: responsiveViewports,
  );
}

const String _reviewTakeId =
    'st_2026-09-19_0123456789abcdef0123456789abcdef01234567';

/// The seeded business with three counts: one needing review, one accepted and
/// one where everything agreed.
FakeTenantReader _stockTakeReader() {
  const root = 'tenants/$seedTenantId';
  Map<String, Object?> take({
    required String date,
    required String counter,
    required String status,
    required int variance,
    required int units,
    int unmatched = 0,
  }) => <String, Object?>{
    'tenantId': seedTenantId,
    'counterUid': counter,
    'businessDate': date,
    'status': status,
    'scope': <String, Object?>{'kind': 'everything'},
    'productsInScope': 240,
    'countedLineCount': 240,
    'varianceLineCount': variance,
    'absoluteVarianceUnits': units,
    'unmatchedLineCount': unmatched,
  };
  Map<String, Object?> line({
    required int counted,
    required int? expected,
    int? seen,
  }) => <String, Object?>{
    'counted': counted,
    'expected': expected,
    'variance': expected == null ? null : counted - expected,
    'seenQuantity': seen,
    'matched': expected != null,
    'needsApply': expected != null && counted != expected,
    'countedAt': '2026-09-19T08:30:00Z',
  };
  final reader = FakeTenantReader.business();
  reader.collections['$root/stock_takes'] = <String, Map<String, Object?>>{
    _reviewTakeId: take(
      date: '2026-09-19',
      counter: ownerUid,
      status: 'submitted',
      variance: 2,
      units: 10,
      unmatched: 1,
    ),
    'st_2026-09-12_0123456789abcdef0123456789abcdef01234567': take(
      date: '2026-09-12',
      counter: managerUid,
      status: 'applied',
      variance: 3,
      units: 5,
    ),
    'st_2026-09-05_0123456789abcdef0123456789abcdef01234567': take(
      date: '2026-09-05',
      counter: cashierUid,
      status: 'submitted',
      variance: 0,
      units: 0,
    ),
  };
  reader.collections['$root/stock_takes/$_reviewTakeId/lines'] =
      <String, Map<String, Object?>>{
        'pd-soda-300': line(counted: 41, expected: 48, seen: 48),
        'pd-bread-white': line(counted: 19, expected: 16),
        'p_9fK2xQ7n': line(counted: 12, expected: null),
      };
  return reader;
}

/// Present so the accept button is drawn enabled; never pressed.
final class _NeverStockTakeApply implements ApplyStockTakeCallable {
  @override
  Future<Object?> call(Map<String, Object?> payload) =>
      throw UnimplementedError('The capture never accepts a count.');
}

/// A writer that answers but is never actually pressed: the captures are of
/// the page, and a form it could not submit would be the wrong page.
final class _FakeExpenseWriter implements TenantExpenseWriter {
  @override
  Future<TenantExpenseWriteResult> recordExpense(
    TenantExpenseCreateIntent intent,
  ) async => const TenantExpenseWriteResult.committed();

  @override
  Future<TenantExpenseWriteResult> voidExpense(
    TenantExpenseVoidIntent intent,
  ) async => const TenantExpenseWriteResult.committed();
}

/// Opens a sheet on the first frame, so a capture can be of one.
///
/// **The harness photographs a widget tree, and a sheet is a route rather than
/// a widget in one.** `showAppSheet` needs a `BuildContext` under a `Navigator`
/// and something to sit over, so a capture of a sheet has to open it the way
/// the app does. The surface underneath is deliberately bare: what these
/// captures are of is the sheet, and a seeded list behind the scrim would only
/// make two screens' worth of review out of one.
final class _SheetHost extends StatefulWidget {
  const _SheetHost({required this.open});

  final Future<void> Function(BuildContext context) open;

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

final class _SheetHostState extends State<_SheetHost> {
  @override
  void initState() {
    super.initState();
    // After the first frame, because `showModalBottomSheet` pushes a route and
    // a route cannot be pushed while the tree that owns the navigator is still
    // building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context);
    });
  }

  // No colour of its own: the theme's own scaffold background is what every
  // other capture in this file sits on, and reading a token here would be one
  // more thing to keep in step with it.
  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

/// A Thursday, so the captured week has four days behind it and three ahead.
final DateTime _weeklyReportClock = DateTime.utc(2026, 8, 27, 9);

/// The same month, priced from sale lines that did not all carry a cost.
///
/// `TenantProfitBasis.incomplete`, so the profit tile reads `—` and the note
/// under it says why. Seeded separately from [seedSalesTotalsResponse] because
/// every other surface wants a figure it can show.
Map<String, Object?> _monthlyIncompleteCostResponse() => <String, Object?>{
  'previous': <String, Object?>{
    'sales': 6420.5,
    'profit': 1937.25,
    'transactions': 48,
    'incompleteCostLineCount': 7,
  },
  'scannedTransactions': 48,
};

/// Takings for the captured week and the one before it, so every card carries
/// a figure and the chart has a clear best day.
Map<String, double> _weeklyReportSeed() {
  final week = TenantReportWeek.at(_weeklyReportClock);
  final before = week.previous;
  final takings = <double>[18400, 24800, 21200, 32600, 0, 0, 0];
  return <String, double>{
    for (var day = 0; day < 7; day++) week.businessDates[day]: takings[day],
    before.startBusinessDate: 96000,
  };
}

/// The counting screen over the stock count design's shop.
///
/// Five named products head the list in name order; 235 more follow them, so
/// the progress card can say *118 of 240* and mean it. The draft resumes 118
/// counts on today's business date, which is the case the screen is opened
/// in most: part-way down an aisle.
Widget _stockCountScreen() {
  const businessDate = '2026-09-22';
  TenantProduct product(String id, String name, String sku) =>
      TenantProduct.fromDocument(
        path: 'tenants/$seedTenantId/products/$id',
        data: <String, Object?>{
          'name': name,
          'SKU': sku,
          'price': 120,
          'quantity': 30,
          'categoryId': 'cat-household',
        },
      );
  final products = <TenantProduct>[
    product('pd-blue-band', 'Blue Band 250g', 'SKU-00108'),
    product('pd-fanta', 'Fanta Orange 300ml', 'SKU-00233'),
    product('pd-kericho', 'Kericho Gold 100s', 'SKU-00301'),
    product('pd-omo', 'Omo Fast Action 1kg', 'SKU-00377'),
    product('pd-tusker', 'Tusker Lager 500ml', 'SKU-00412'),
    for (var i = 1; i <= 235; i++)
      product(
        'pd-shelf-$i',
        'Zz shelf item ${i.toString().padLeft(3, '0')}',
        'SKU-${(500 + i).toString().padLeft(5, '0')}',
      ),
  ];
  TenantStockTakeCount counted(int units) => TenantStockTakeCount(
    counted: units,
    seenQuantity: 30,
    countedAt: DateTime.utc(2026, 9, 22, 8),
  );
  final draft = TenantStockTakeDraft(
    takeId: tenantStockTakeId(
      tenantId: seedTenantId,
      counterUid: cashierUid,
      requestId: 'stocktake-screenshot',
      businessDate: businessDate,
    ),
    tenantId: seedTenantId,
    businessDate: businessDate,
    scope: const TenantStockTakeEverything(),
    productsInScope: products.length,
    startedAt: DateTime.utc(2026, 9, 22, 7),
    counts: <String, TenantStockTakeCount>{
      'pd-blue-band': counted(19),
      'pd-kericho': counted(0),
      'pd-tusker': counted(41),
      for (var i = 1; i <= 115; i++) 'pd-shelf-$i': counted(i % 17),
    },
  );
  return TenantStockTakeScreen(
    catalog: FakeCatalogSource(
      snapshot: CheckoutCatalogSnapshot.forTesting(
        uid: cashierUid,
        tenantId: seedTenantId,
        configuration: TenantCheckoutConfiguration(currency: seedCurrency),
        categories: seedCatalogCategories(),
        products: products,
      ),
    ),
    drafts: _ScreenshotStockTakeDrafts(draft),
    writer: _ScreenshotStockTakeWriter(),
    businessDate: () => businessDate,
  );
}

/// Holds one resumed count and forgets nothing, which is all a capture needs.
final class _ScreenshotStockTakeDrafts implements TenantStockTakeDraftSource {
  _ScreenshotStockTakeDrafts(this._draft);

  TenantStockTakeDraft? _draft;

  @override
  TenantStockTakeDraft? draftFor({
    required String uid,
    required String tenantId,
  }) => _draft;

  @override
  Future<void> save({
    required String uid,
    required TenantStockTakeDraft draft,
  }) async => _draft = draft;

  @override
  Future<void> clear({required String uid, required String tenantId}) async =>
      _draft = null;
}

final class _ScreenshotStockTakeWriter implements TenantStockTakeWriter {
  @override
  Future<TenantStockTakeWriteResult> submitPage(
    TenantStockTakePageIntent intent,
  ) async => TenantStockTakeWriteResult.queued(intent.operationId);
}

/// The published rota the stock count captures draw: *Ask at the register* on
/// Monday and Thursday, five people down for a category each.
const Map<String, Object?> _stockCountsSchedule = <String, Object?>{
  'enforcement': 'prompt',
  'weekdays': <int>[DateTime.monday, DateTime.thursday],
  'assignments': <Map<String, Object?>>[
    <String, Object?>{'uid': 'st-boniface', 'categoryId': 'cat-paint'},
    <String, Object?>{'uid': 'st-david', 'categoryId': 'cat-plumbing'},
    <String, Object?>{'uid': 'st-grace', 'categoryId': 'cat-power-tools'},
    <String, Object?>{'uid': 'st-lydia', 'categoryId': 'cat-electrical'},
    <String, Object?>{'uid': 'st-peter', 'categoryId': 'cat-hand-tools'},
  ],
  'updatedBy': ownerUid,
};

/// `docs/design/stock-counts/`'s shop, which is not the seeded business.
///
/// **Its own reader rather than the seed's**, because the design's people and
/// categories are the point of the capture - an invited member on the rota, a
/// deactivated one still down for a category, a category nobody counts - and
/// the seeded corner shop has none of them. The IDs sort in the design's own
/// order, which is the order a page of them is read in.
FakeTenantReader _stockCountsReader({Map<String, Object?>? schedule}) {
  const root = 'tenants/$seedTenantId';
  Map<String, Object?> member(
    String uid,
    String name, {
    String role = 'cashier',
    String status = 'active',
  }) => <String, Object?>{
    'uid': uid,
    'email': '$uid@mwangi.test',
    'name': name,
    'role': role,
    'status': status,
    'invitationStatus': status == 'pending' ? 'sent' : 'accepted',
  };
  final staff = <String, Map<String, Object?>>{
    ownerUid: member(ownerUid, 'Asha Mwangi', role: 'owner'),
    'st-boniface': member('st-boniface', 'Boniface Otieno', role: 'admin'),
    'st-david': member('st-david', 'David Mutiso', status: 'inactive'),
    'st-grace': member('st-grace', 'Grace Wanjiru', role: 'manager'),
    'st-lydia': member('st-lydia', 'Lydia Achieng', status: 'pending'),
    'st-njeri': member('st-njeri', 'Njeri Kariuki', status: 'pending'),
    'st-peter': member('st-peter', 'Peter Kamau'),
    'st-samuel': member('st-samuel', 'Samuel Ochieng', status: 'pending'),
  };
  return FakeTenantReader(
    documents: <String, Map<String, Object?>>{
      root: <String, Object?>{
        'tenantId': seedTenantId,
        'name': 'Mwangi Hardware',
        'slug': seedTenantSlug,
        'status': 'active',
        'ownerUid': ownerUid,
      },
      for (final entry in staff.entries)
        '$root/staff/${entry.key}': entry.value,
      if (schedule != null) '$root/configuration/stock_take': schedule,
    },
    collections: <String, Map<String, Map<String, Object?>>>{
      '$root/staff': staff,
      '$root/categories': const <String, Map<String, Object?>>{
        'cat-electrical': <String, Object?>{'name': 'Electrical'},
        'cat-fasteners': <String, Object?>{'name': 'Fasteners'},
        'cat-hand-tools': <String, Object?>{'name': 'Hand tools'},
        'cat-paint': <String, Object?>{'name': 'Paint'},
        'cat-plumbing': <String, Object?>{'name': 'Plumbing'},
        'cat-power-tools': <String, Object?>{'name': 'Power tools'},
      },
    },
  );
}

/// The Stock counts page as the settings index opens it.
Widget _stockCountsPage(
  FakeTenantReader reader, {
  TenantConfigurationDocumentWriter? writer,
}) => TenantSettingPage(
  destination: TenantSettingsDestination(
    settingKey: 'stock-take',
    kind: TenantSettingKind.stockCounts,
    icon: Icons.fact_check_outlined,
    allowedRoles: TenantStockTakeSchedulePublisher.allowedRoles,
    builder: (_) =>
        TenantStockTakeSettingsPanel(reader: reader, writer: writer),
  ),
);

/// Shift history over the seeded business, with its cards opening the Sales
/// report the way `lib/main.dart` wires them: on the shift's day, narrowed to
/// whoever ran it, against the same reader.
Widget _shiftHistory() {
  final reader = FakeTenantReader.business();
  return TenantShiftHistoryScreen(
    reader: reader,
    returnActions: fakeReturnActions(),
    salesReportRoute: ({required businessDate, required staffId}) =>
        TenantSalesReportScreen(
          reader: reader,
          reportReader: reader,
          totalsCallable: FakeCallable(seedSalesTotalsResponse()),
          returnActions: fakeReturnActions(),
          initialBusinessDate: businessDate,
          initialStaffId: staffId,
        ),
  );
}

/// The three settings the composition root offers, for the index captures.
///
/// Each destination hosts the same panel `lib/main.dart` hosts, so a picture of
/// the index is a picture of the real list rather than three invented rows.
List<TenantSettingsDestination> _settingsDestinations(
  TenantDataReader reader,
) => <TenantSettingsDestination>[
  TenantSettingsDestination(
    settingKey: 'currency',
    kind: TenantSettingKind.currency,
    icon: Icons.payments_outlined,
    allowedRoles: TenantCheckoutConfigurationPublisher.allowedRoles,
    builder: (_) => TenantCheckoutConfigurationPanel(reader: reader),
  ),
  TenantSettingsDestination(
    settingKey: 'printer',
    kind: TenantSettingKind.printer,
    icon: Icons.print_outlined,
    allowedRoles: TenantPrinterConfigurationPublisher.allowedRoles,
    // The printer, then the receipt branding under it, as `lib/main.dart`.
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TenantPrinterConfigurationPanel(reader: reader),
        SizedBox(height: AppTokens.componentOf(context).spacing.s32),
        const SectionHeading('Receipt branding'),
        SizedBox(height: AppTokens.componentOf(context).spacing.s12),
        TenantBrandingPanel(reader: reader),
      ],
    ),
  ),
  TenantSettingsDestination(
    settingKey: 'stock-take',
    kind: TenantSettingKind.stockCounts,
    icon: Icons.fact_check_outlined,
    allowedRoles: TenantStockTakeSchedulePublisher.allowedRoles,
    builder: (_) => TenantStockTakeSettingsPanel(reader: reader),
  ),
];

/// A business that has not chosen *Don't show again*.
final class _NeverSilenced implements CheckoutPrinterSetupReminder {
  @override
  bool isSilenced(String tenantId) => false;

  @override
  Future<void> silence(String tenantId) async {}
}
