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
import 'package:flutter_application_1/audit/audit.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/expenses/expenses.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/returns/returns.dart';
import 'package:flutter_application_1/sales/sales.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/snackbar.dart';
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
  // 2026-08-26.** It is unique either way: on the compact sheet only the
  // masthead draws it, and on the wide one only the image column does.
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
        scrollable: find.byType(Scrollable).first,
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
      await tester.tap(find.text('Close'));
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
    '21c-adjust-stock-sheet',
    build: () => inSession(
      _SheetHost(
        open: (context) => openTenantProductStockAdjustmentSheet(
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

  // The same sheet on a product the server holds a negative quantity for, which
  // is the one state of the figure above the form that carries a status.
  screenshotCase(
    '21d-adjust-stock-below-zero',
    build: () => inSession(
      _SheetHost(
        open: (context) => openTenantProductStockAdjustmentSheet(
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
      TenantShiftHistoryScreen(
        reader: FakeTenantReader.business(),
        returnActions: fakeReturnActions(),
      ),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
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

  // The same sheet with its one fold open, because a `Disclosure` closed is a
  // capture of a summary line and says nothing about the prose behind it.
  screenshotCase(
    '34c-returns-explained',
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
    afterPump: (tester) async {
      await tester.tap(find.text('What a return does'));
      await tester.pumpAndSettle();
    },
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
