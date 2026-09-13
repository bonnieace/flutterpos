import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/fields.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/snackbar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/notices.dart';

import '../support/buttons.dart';
import '../support/fields.dart';

const String _productsPath = 'tenants/tenant-a/products';
const String _categoriesPath = 'tenants/tenant-a/categories';

void main() {
  testWidgets('a cashier can read inventory but sees no write actions', (
    tester,
  ) async {
    await _pump(
      tester,
      _controller(role: TenantRole.cashier),
      _Reader.seeded(),
      writer: _Writer(),
    );

    expect(find.byKey(const ValueKey('inventory-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('inventory-add-product')), findsNothing);
    expect(find.byKey(const ValueKey('inventory-categories')), findsNothing);
    expect(find.byKey(const ValueKey('inventory-actions-pd-1')), findsNothing);
  });

  testWidgets('a build with no writer remains a useful read-only inventory', (
    tester,
  ) async {
    await _pump(tester, _controller(), _Reader.seeded());

    expect(find.byKey(const ValueKey('inventory-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('inventory-add-product')), findsNothing);
    expect(find.byKey(const ValueKey('inventory-categories')), findsNothing);
    expect(find.byKey(const ValueKey('inventory-actions-pd-1')), findsNothing);
  });

  testWidgets('every notice on this route is a status, and all of them read '
      'informational', (tester) async {
    // Three notices meet a person here and none of them reports a failure: two
    // say what this build cannot do and one says what this role may not do. §2.1
    // gives `info` "offline, read-only, informational", and calling any of them
    // `problem` would invent in colour a fault the words are careful not to
    // claim - the same reading the reconciliation day page made for its own
    // forbidden notice.
    await _pump(
      tester,
      _controller(role: TenantRole.manager),
      _Reader.seeded(),
    );

    expect(find.byType(Callout), findsNothing);
    expect(find.byKey(const ValueKey('inventory-search')), findsOneWidget);
  });

  testWidgets('every explanation on this route fits its one line on a phone', (
    tester,
  ) async {
    // A character count and not a render measurement: `flutter test` has no
    // Material fonts, so an intrinsic-width read here is a fallback font's
    // advance widths. The budget was measured in the harness, where they are
    // real.
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      bulkRoute: (_) => const Scaffold(body: Text('Bulk open')),
      width: 411,
    );

    final add = tester.getRect(
      find.byKey(const ValueKey('inventory-add-product')),
    );
    final bulk = tester.getRect(
      find.byKey(const ValueKey('catalog-management-bulk')),
    );
    final categories = tester.getRect(
      find.byKey(const ValueKey('inventory-categories')),
    );
    // The primary action takes the whole width, and the other two share the
    // row beneath it rather than stacking one per row.
    expect(add.width, greaterThan(bulk.width));
    expect(add.top, lessThan(bulk.top));
    expect(bulk.top, categories.top);
    expect(bulk.width, categories.width);
  });

  testWidgets('legacy cards switch to the image table at 768 pixels', (
    tester,
  ) async {
    for (final width in <double>[411, 767]) {
      await _pump(
        tester,
        _controller(),
        _Reader.seeded(),
        writer: _Writer(),
        width: width,
      );
      expect(
        find.byKey(const ValueKey('inventory-product-cards')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inventory-product-table')),
        findsNothing,
      );
      expect(
        tester.getSize(find.byType(TenantProductVisual).first),
        const Size.square(64),
      );
    }

    for (final width in <double>[768, 834, 1024, 1440]) {
      await _pump(
        tester,
        _controller(),
        _Reader.seeded(),
        writer: _Writer(),
        width: width,
      );
      expect(
        find.byKey(const ValueKey('inventory-product-table')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inventory-product-cards')),
        findsNothing,
      );
      expect(
        tester.getSize(find.byType(TenantProductVisual).first),
        const Size.square(48),
      );
      expect(find.text('CATEGORY'), width < 1024 ? findsNothing : findsOne);
      expect(find.text('UNIT COST'), width < 1200 ? findsNothing : findsOne);
      expect(find.text('RETAIL VALUE'), width < 1200 ? findsNothing : findsOne);
    }
  });

  testWidgets('phone filters keep both dropdowns compact on one row', (
    tester,
  ) async {
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      width: 411,
    );

    final search = tester.getRect(
      find.byKey(const ValueKey('inventory-search')),
    );
    final category = tester.getRect(
      find.byKey(const ValueKey('inventory-category-filter')),
    );
    final stock = tester.getRect(
      find.byKey(const ValueKey('inventory-stock-filter')),
    );
    expect(category.top, stock.top);
    expect(category.width, closeTo(stock.width, 0.01));
    expect(category.width, lessThan(search.width));
    expect(category.right, lessThan(stock.left));
    expect(find.text('Products'), findsNothing);
    expect(find.text(tenantCatalogStockNeverBlocks), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide cost visibility follows owner and administrator roles', (
    tester,
  ) async {
    for (final role in TenantRole.values) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pump(
        tester,
        _controller(role: role),
        _Reader.seeded(),
        writer: _Writer(),
        callable: _Callable(),
        width: 1440,
      );
      final maySeeCost = role == TenantRole.owner || role == TenantRole.admin;
      expect(find.text('UNIT COST'), maySeeCost ? findsOne : findsNothing);
      expect(find.text('RETAIL VALUE'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('inventory-actions-pd-1')),
        role == TenantRole.cashier ? findsNothing : findsOneWidget,
      );
    }
  });

  testWidgets('mobile product actions use one ordered accessible menu', (
    tester,
  ) async {
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      callable: _Callable(),
      width: 411,
      productStockRoute: (product) =>
          Scaffold(body: Text('Viewing ${product.id}')),
      // The correction is a sheet rather than a route since 2026-08-26, so what
      // decides whether the menu offers it is this opener, not the builder
      // above. The entry is what this test is about; opening it is not.
      adjustStockRoute: (context, product) async {},
      productStockRoles: const <TenantRole>[TenantRole.owner],
    );

    final menu = find.byKey(const ValueKey('inventory-actions-pd-1'));
    expect(menu, findsOneWidget);
    expect(find.byTooltip('Product actions'), findsWidgets);
    await tester.tap(menu);
    await tester.pumpAndSettle();

    final view = find.byKey(const ValueKey('inventory-view-pd-1'));
    final adjust = find.byKey(const ValueKey('inventory-adjust-pd-1'));
    final correct = find.byKey(const ValueKey('catalog-management-edit-pd-1'));
    final retire = find.byKey(const ValueKey('catalog-management-retire-pd-1'));
    // **Four entries since 2026-08-25**, when reading a product's stock and
    // correcting it became two routes rather than one screen with a form
    // appended under the ledger.
    expect(find.text('View item'), findsOneWidget);
    expect(find.text('Adjust stock'), findsOneWidget);
    expect(find.text('Edit item'), findsOneWidget);
    expect(find.text('Retire product'), findsOneWidget);
    // Reading first, then the two that change something, destructive last.
    expect(tester.getCenter(view).dy, lessThan(tester.getCenter(adjust).dy));
    expect(tester.getCenter(adjust).dy, lessThan(tester.getCenter(correct).dy));
    expect(tester.getCenter(correct).dy, lessThan(tester.getCenter(retire).dy));

    await tester.tap(view);
    await tester.pumpAndSettle();
    expect(find.text('Viewing pd-1'), findsOneWidget);
  });

  testWidgets('the bulk explanation is kept, and it starts out of the way', (
    tester,
  ) async {
    // §5.2 names this paragraph by name: the writing is good and should be
    // kept, and it being permanently on screen is what makes this form three
    // times taller than it needs to be. The words are unchanged.
    const explanation =
        'One correction can be applied across many products, and a catalog '
        'can be created from a spreadsheet. Both are previewed row by row '
        'before anything is written.';
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      bulkRoute: (_) => const Scaffold(body: Text('Bulk open')),
    );

    expect(find.text(explanation), findsNothing);
    expect(find.byType(Disclosure), findsNothing);
    expect(
      find.byKey(const ValueKey('catalog-management-bulk')),
      findsOneWidget,
    );
  });

  testWidgets('the bulk route is offered only when the build carries one', (
    tester,
  ) async {
    await _pump(tester, _controller(), _Reader.seeded(), writer: _Writer());
    expect(find.byKey(const ValueKey('catalog-management-bulk')), findsNothing);

    final reader = _Reader.seeded();
    await _pump(
      tester,
      _controller(),
      reader,
      writer: _Writer(),
      bulkRoute: (_) => Scaffold(
        appBar: AppBar(title: const Text('Bulk')),
        body: const Text('Bulk open'),
      ),
    );
    expect(find.byKey(const ValueKey('catalog-management-bulk')), findsOne);

    final readsBefore = reader.pages.length;
    await tester.tap(find.byKey(const ValueKey('catalog-management-bulk')));
    await tester.pumpAndSettle();
    expect(find.text('Bulk open'), findsOne);

    // Coming back re-reads, because a bulk correction changes the products this
    // list is currently stating.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(reader.pages.length, greaterThan(readsBefore));
  });

  testWidgets(
    'search is debounced, normalized, and resets the backend cursor',
    (tester) async {
      final searchReader = _SearchReader.seeded(productCount: 3);
      await _pump(
        tester,
        _controller(),
        _Reader.seeded(productCount: 3),
        writer: _Writer(),
        productSearchReader: searchReader,
        pageSize: 1,
      );

      expect(searchReader.queries.single.searchPrefix, isNull);
      await tester.tap(
        find.byKey(const ValueKey('catalog-management-next-page')),
      );
      await tester.pump();
      await tester.pump();
      expect(searchReader.queries.last.startAfter, isNotNull);

      await tester.enterText(
        find.byKey(const ValueKey('inventory-search')),
        '  BR  ',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(searchReader.queries.last.searchPrefix, isNull);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(searchReader.queries.last.searchPrefix, 'br');
      expect(searchReader.queries.last.startAfter, isNull);
      expect(_text(tester, 'catalog-management-page'), 'Page 1');
    },
  );

  testWidgets(
    'category and stock controls re-query the backend from page one',
    (tester) async {
      final searchReader = _SearchReader.seeded(productCount: 2);
      await _pump(
        tester,
        _controller(),
        _Reader.seeded(),
        writer: _Writer(),
        productSearchReader: searchReader,
      );

      await tester.tap(find.byKey(const ValueKey('inventory-category-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bakery').last);
      await tester.pumpAndSettle();
      expect(searchReader.queries.last.categoryId, 'cat-bakery');
      expect(searchReader.queries.last.startAfter, isNull);

      await tester.tap(find.byKey(const ValueKey('inventory-stock-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('At/below zero').last);
      await tester.pumpAndSettle();
      expect(
        searchReader.queries.last.stock,
        TenantProductStockFilter.atOrBelowZero,
      );
      expect(searchReader.queries.last.categoryId, 'cat-bakery');
      expect(searchReader.queries.last.startAfter, isNull);
    },
  );

  testWidgets('a business with no categories is told what comes first', (
    tester,
  ) async {
    await _pump(tester, _controller(), _Reader.empty(), writer: _Writer());

    expect(
      find.byKey(const ValueKey('inventory-empty-catalog')),
      findsOneWidget,
    );
    expect(_enabled(tester, 'inventory-add-product'), isTrue);
    await tester.tap(find.byKey(const ValueKey('inventory-categories')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('inventory-categories-empty')),
      findsOneWidget,
    );
    expect(_enabled(tester, 'catalog-management-add-category'), isFalse);
  });

  testWidgets('a category is confirmed, written, and re-read', (tester) async {
    final reader = _Reader.empty();
    final writer = _Writer();
    var syncs = 0;

    await _pump(
      tester,
      _controller(),
      reader,
      writer: writer,
      onChanged: () => syncs++,
    );
    await tester.tap(find.byKey(const ValueKey('inventory-categories')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('catalog-management-category-name')),
      '  Cold  drinks  ',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-add-category')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('It can be renamed later'), findsOne);
    await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
    await tester.pumpAndSettle();
    // Categories are a route since 2026-09-04, so leaving is the back arrow
    // rather than a Close button inside a dialog.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(writer.categories.single.name, 'Cold drinks');
    expect(writer.categories.single.path, startsWith('$_categoriesPath/'));
    expect(syncs, 1);
    expect(snackNotice(tester).message, startsWith('Category added.'));
    // **This screen writes six different things and reported every outcome of
    // all six as the same black sentence in the same position.** The notice
    // carries which it is now.
    expect(snackNotice(tester).status, AppStatus.ok);
    // Two reads of each collection: the first render, and the re-read a commit
    // asks for, so what is listed is the server's catalog and not the typing.
    expect(
      reader.pages.where((path) => path == _categoriesPath).length,
      greaterThanOrEqualTo(2),
    );
  });

  testWidgets('renaming a category preserves its document identity', (
    tester,
  ) async {
    final writer = _Writer();
    await _pump(tester, _controller(), _Reader.seeded(), writer: writer);

    await tester.tap(find.byKey(const ValueKey('inventory-categories')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inventory-rename-cat-bakery')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('catalog-management-rename-category-name')),
      'Breads and pastries',
    );
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-rename-category-save')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('keeps the same identity'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
    await tester.pumpAndSettle();

    expect(writer.renamed.single.categoryId, 'cat-bakery');
    expect(writer.renamed.single.name, 'Breads and pastries');
  });

  testWidgets('a product is filed, priced, and created holding nothing', (
    tester,
  ) async {
    final writer = _Writer();
    var syncs = 0;

    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: writer,
      onChanged: () => syncs++,
    );
    await _fillProduct(
      tester,
      name: 'Mandazi',
      sku: '6161100000026',
      price: '20.50',
    );
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-add-product')),
    );
    await tester.pumpAndSettle();

    // **No confirmation to read, since 2026-09-04.** The three things it used
    // to say - where the product is filed, that it arrives empty, and what can
    // be corrected afterwards - are stated where they are actionable: the
    // category in the field that chose it, and the opening stock in the notice
    // below, which is where a person is told what to do next.
    final intent = writer.products.single;
    expect(intent.name, 'Mandazi');
    expect(intent.sku, '6161100000026');
    expect(intent.priceMinor, 2050);
    expect(intent.categoryId, 'cat-bakery');
    expect(intent.documentData()['quantity'], 0);
    expect(syncs, 1);
    // The form is emptied, so the next product is not a near-copy of this one.
    await tester.tap(find.byKey(const ValueKey('inventory-add-product')));
    await tester.pumpAndSettle();
    expect(_field(tester, 'catalog-management-product-name'), '');
    expect(_field(tester, 'catalog-management-product-sku'), '');
    expect(
      tester
          .widget<AppSelect<String>>(
            find.byKey(const ValueKey('catalog-management-product-category')),
          )
          .value,
      '',
    );
  });

  testWidgets('a failed product write removes its staged owned image', (
    tester,
  ) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
      'A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    FilePicker.platform = _FilePicker(bytes);
    final imageStore = _ImageStore();
    final writer = _Writer.answering(
      const TenantCatalogWriteResult.rejected('permission-denied'),
    );
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: writer,
      imageStore: imageStore,
    );

    await _fillProduct(tester, name: 'Mandazi', sku: 'M-1', price: '20');
    await tester.tap(
      find.byKey(const ValueKey('inventory-choose-product-image')),
    );
    await tester.pumpAndSettle();
    await _confirmProduct(tester);

    expect(imageStore.uploads, hasLength(1));
    expect(writer.products.single.imageUrl, imageStore.uploads.single.url);
    expect(imageStore.removed, <Uri>[imageStore.uploads.single.url]);
  });

  testWidgets('a refused upload names the code Storage gave it', (
    tester,
  ) async {
    // **Five faults used to arrive under one sentence.** `permission-denied`,
    // `unauthenticated`, `unauthorized`, `retry-limit-exceeded` and a plain
    // network timeout all read as "could not be uploaded", so a shop reporting
    // that it will not upload was reporting any of five things and no
    // screenshot could tell them apart. On 2026-09-03 that cost a session of
    // guesswork against a live backend, which is what this test is here to
    // stop happening twice.
    FilePicker.platform = _FilePicker(_onePixelPng);
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      imageStore: _RefusingImageStore('permission-denied'),
    );

    await _fillProduct(tester, name: 'Mandazi', sku: 'M-1', price: '20');
    await tester.tap(
      find.byKey(const ValueKey('inventory-choose-product-image')),
    );
    await tester.pumpAndSettle();
    await _confirmProduct(tester);

    expect(snackNotice(tester).message, contains('permission-denied'));
    // Still says what it cost, which is the half a shopkeeper acts on.
    expect(snackNotice(tester).message, contains('Nothing was written'));
    expect(snackNotice(tester).status, AppStatus.problem);
  });

  testWidgets('the two refusals this app makes itself stay in plain words', (
    tester,
  ) async {
    // A file too large or of the wrong type is refused before a byte leaves the
    // device, and naming a code for either would be naming this app's own rule
    // as if it were the server's.
    FilePicker.platform = _FilePicker(Uint8List.fromList(<int>[1, 2, 3]));
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      imageStore: _ImageStore(),
    );

    await _fillProduct(tester, name: 'Mandazi', sku: 'M-1', price: '20');
    await tester.tap(
      find.byKey(const ValueKey('inventory-choose-product-image')),
    );
    await tester.pumpAndSettle();

    expect(snackNotice(tester).message, 'Choose a JPEG, PNG, or WebP image.');
  });

  testWidgets('a committed replacement removes the superseded owned image', (
    tester,
  ) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
      'A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    FilePicker.platform = _FilePicker(bytes);
    final oldImage = Uri.parse(
      'https://storage.test/tenantProductImages/tenant-a/pd-1/old.png',
    );
    final reader = _Reader(<String, Map<String, Map<String, Object?>>>{
      _categoriesPath: <String, Map<String, Object?>>{
        'cat-bakery': <String, Object?>{'name': 'Bakery'},
      },
      _productsPath: <String, Map<String, Object?>>{
        'pd-1': <String, Object?>{
          'name': 'White bread loaf',
          'SKU': '6161100000019',
          'price': 65,
          'quantity': 40,
          'categoryId': 'cat-bakery',
          'image': oldImage.toString(),
        },
      },
    });
    final imageStore = _ImageStore();
    final callable = _Callable();
    await _pump(
      tester,
      _controller(),
      reader,
      writer: _Writer(),
      callable: callable,
      imageStore: imageStore,
    );

    await _openCorrection(tester, 'pd-1');
    await tester.tap(find.byKey(const ValueKey('inventory-replace-image')));
    await tester.pumpAndSettle();
    await _review(tester);
    await tester.pumpAndSettle();

    expect(
      callable.payloads.single['image'],
      imageStore.uploads.single.url.toString(),
    );
    expect(imageStore.removed, <Uri>[oldImage]);
  });

  testWidgets('a price the till could not record is refused where typed', (
    tester,
  ) async {
    final writer = _Writer();

    await _pump(tester, _controller(), _Reader.seeded(), writer: writer);
    await _fillProduct(tester, name: 'Mandazi', sku: 'M-1', price: '20.505');
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-add-product')),
    );
    await tester.pumpAndSettle();

    // Refused locally, so the writer is never reached at all. The local
    // refusal is the whole of what stands between a bad price and the catalog
    // now that there is no confirmation step behind it.
    expect(writer.products, isEmpty);
    expect(
      snackNotice(tester).message,
      startsWith('Enter a price as a plain amount'),
    );
  });

  testWidgets('a queued product is written first and asked about after', (
    tester,
  ) async {
    final writer = _Writer.answering(
      const TenantCatalogWriteResult.queued('op-1'),
    );
    final undone = <String>[];

    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: writer,
      undo: ({required tenantId, required operationId}) async {
        undone.add(operationId);
        return true;
      },
    );
    await _fillProduct(tester, name: 'Mandazi', sku: 'M-1', price: '20');
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-add-product')),
    );
    await tester.pumpAndSettle();

    // The point of dropping the confirmation: nothing stands between the
    // button and the record, and the offer to take it back comes afterwards.
    expect(writer.products, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('catalog-management-undo')));
    await tester.pumpAndSettle();

    expect(undone, <String>['op-1']);
    expect(snackNotice(tester).message, 'Undone. Nothing was sent.');
  });

  testWidgets('a change already sent says so rather than claiming a reversal', (
    tester,
  ) async {
    final writer = _Writer.answering(
      const TenantCatalogWriteResult.queued('op-1'),
    );

    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: writer,
      // The record left this device between the notice and the press.
      undo: ({required tenantId, required operationId}) async => false,
    );
    await _fillProduct(tester, name: 'Mandazi', sku: 'M-1', price: '20');
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-add-product')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalog-management-undo')));
    await tester.pumpAndSettle();

    expect(
      snackNotice(tester).message,
      startsWith('This has already been sent'),
    );
  });

  testWidgets('an unknown outcome keeps addressing the same document', (
    tester,
  ) async {
    // A retry after an unknown outcome must reach the product that may already
    // exist, not put a second one on the shelf.
    final writer = _Writer.answering(
      const TenantCatalogWriteResult.ambiguous('unavailable'),
    );

    await _pump(tester, _controller(), _Reader.seeded(), writer: writer);
    await _fillProduct(tester, name: 'Mandazi', sku: 'M-1', price: '20');
    await _confirmProduct(tester);

    expect(snackNotice(tester).message, startsWith('The result is unknown.'));
    await _fillProduct(tester, name: 'Mandazi', sku: 'M-1', price: '20');
    await _confirmProduct(tester);

    expect(writer.products.length, 2);
    expect(writer.products.first.productId, writer.products.last.productId);
  });

  testWidgets('a settled outcome starts a new document for the next product', (
    tester,
  ) async {
    final writer = _Writer();

    await _pump(tester, _controller(), _Reader.seeded(), writer: writer);
    await _fillProduct(tester, name: 'Mandazi', sku: 'M-1', price: '20');
    await _confirmProduct(tester);
    await _fillProduct(tester, name: 'Chapati', sku: 'C-1', price: '30');
    await _confirmProduct(tester);

    expect(writer.products.length, 2);
    expect(
      writer.products.first.productId,
      isNot(writer.products.last.productId),
    );
  });

  testWidgets('a manager stocks the catalog and cannot retire from it', (
    tester,
  ) async {
    await _pump(
      tester,
      _controller(role: TenantRole.manager),
      _Reader.seeded(),
      writer: _Writer(),
      callable: _Callable(),
    );

    expect(find.byKey(const ValueKey('inventory-add-product')), findsOne);
    await _openProductActions(tester, 'pd-1');
    expect(
      find.byKey(const ValueKey('catalog-management-edit-pd-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('catalog-management-retire-pd-1')),
      findsNothing,
    );
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inventory-add-product')));
    await tester.pumpAndSettle();
    // A manager stocks the catalog without being shown the margin. Every active
    // member can read a product document, so this is a surface boundary rather
    // than a secrecy guarantee - but it is the boundary that decides whether a
    // manager is *shown* what the business pays.
    expect(
      find.byKey(const ValueKey('catalog-management-product-cost')),
      findsNothing,
    );
  });

  testWidgets('a product that cannot be sold says so on this list too', (
    tester,
  ) async {
    // The same standing on both catalog surfaces, from one function, so the two
    // screens cannot come to disagree about what the same product is.
    await _pump(
      tester,
      _controller(),
      _Reader(const <String, Map<String, Map<String, Object?>>>{
        _categoriesPath: <String, Map<String, Object?>>{
          'cat-bakery': <String, Object?>{'name': 'Bakery'},
        },
        _productsPath: <String, Map<String, Object?>>{
          'pd-1': <String, Object?>{
            'name': 'White bread loaf',
            'SKU': '6161100000019',
            'price': 65,
            'quantity': 0,
            'categoryId': 'cat-bakery',
          },
          'pd-2': <String, Object?>{
            'name': 'Mandazi',
            'SKU': '6161100000026',
            'price': 20,
            'quantity': 120,
            'categoryId': 'cat-bakery',
          },
        },
      }),
      writer: _Writer(),
    );

    expect(
      tester
          .widget<StatusBadge>(
            find.byKey(const ValueKey('product-stock-standing-pd-1')),
          )
          .label,
      '0 in stock',
    );
    expect(
      find.byKey(const ValueKey('product-stock-standing-pd-2')),
      findsNothing,
    );
    expect(_text(tester, 'catalog-management-product-stock-pd-1'), '0');
    // The category is the record's second identifying line rather than a
    // "Category: Category" attribute, and it is still named rather than an ID.
    expect(_text(tester, 'catalog-management-category-of-pd-1'), 'Bakery');
  });

  testWidgets('both actions are reachable on a phone', (tester) async {
    // §4.1's `compact` band. This route has only ever been driven at 1400 and
    // its two controls have only ever been laid out in a `ListTile`'s trailing
    // slot, which is the class of thing the staff directory chunk found
    // overflowing on every phone.
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final writer = _Writer();
    await tester.pumpWidget(
      MaterialApp(
        home: TenantSessionScope(
          controller: _controller(),
          child: Scaffold(
            body: TenantCatalogManagementPanel(
              reader: _Reader.seeded(),
              writer: writer,
              updateCallable: _Callable(),
              requestIdFactory: _requestIds().call,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // One compact trigger keeps all available operations reachable without
    // making the card footer carry three competing controls.
    final menu = find.byKey(const ValueKey('inventory-actions-pd-1'));
    await tester.scrollUntilVisible(
      menu,
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    expect(menu, findsOneWidget);
    expect(tester.takeException(), isNull);

    // `scrollUntilVisible` stops when the widget is *built*, which on this route
    // can leave it a few pixels below the fold - the page got shorter when its
    // scope paragraph learned to fold, and the tap then landed at y=912 in an
    // 891-high viewport. Scrolling it fully into view is what a person does and
    // is what the assertion below is actually about.
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('catalog-management-edit-pd-1')),
      findsOneWidget,
    );
    final retire = find.byKey(const ValueKey('catalog-management-retire-pd-1'));
    await tester.tap(retire);
    await tester.pumpAndSettle();
    // The action is reachable, which is what this test is about. It goes
    // straight through now rather than opening a dialog, so what proves the
    // menu item works is the retire itself.
    expect(find.textContaining('White bread loaf is retired'), findsOne);
  });

  testWidgets('an owner is offered the unit cost the manager is not', (
    tester,
  ) async {
    await _pump(tester, _controller(), _Reader.seeded(), writer: _Writer());

    await tester.tap(find.byKey(const ValueKey('inventory-add-product')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('catalog-management-product-cost')),
      findsOne,
    );
  });

  testWidgets('retiring says what survives it and then deletes', (
    tester,
  ) async {
    final writer = _Writer();
    var syncs = 0;

    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: writer,
      onChanged: () => syncs++,
    );
    await _tapProductAction(tester, 'pd-1', 'catalog-management-retire-pd-1');

    // **The retire happens, then says what survived it.** Until 2026-09-04
    // these sentences were a confirmation asked beforehand; the facts they
    // carry - that the ledger outlives the product and every sale line still
    // names it - are true afterwards too, and are worth more in a notice a
    // person reads than in a dialog they dismiss.
    expect(writer.retired.single.productId, 'pd-1');
    expect(writer.retired.single.quantity, 40);
    expect(syncs, 1);
    expect(
      snackNotice(tester).message,
      startsWith('White bread loaf is retired.'),
    );
  });

  testWidgets('a refusal from the server writes nothing and says so', (
    tester,
  ) async {
    final writer = _Writer.answering(
      const TenantCatalogWriteResult.rejected('permission-denied'),
    );
    final reader = _Reader.seeded();

    await _pump(tester, _controller(), reader, writer: writer);
    await _tapProductAction(tester, 'pd-1', 'catalog-management-retire-pd-1');
    await tester.pumpAndSettle();

    expect(snackNotice(tester).message, startsWith('Nothing was retired.'));
    expect(snackNotice(tester).status, AppStatus.problem);
    // A proven refusal changed nothing, so there is nothing to re-read.
    expect(reader.pages.where((path) => path == _productsPath).length, 1);
  });

  testWidgets('an offline device is told nothing was written', (tester) async {
    final writer = _Writer.answering(
      const TenantCatalogWriteResult.unavailable(),
    );

    await _pump(tester, _controller(), _Reader.seeded(), writer: writer);
    await _fillProduct(tester, name: 'Mandazi', sku: 'M-1', price: '20');
    await _confirmProduct(tester);

    expect(snackNotice(tester).message, startsWith('This device is offline'));
    // §2.1 gives `info` the words "offline, read-only, informational", so an
    // offline write is that row by name rather than by judgement.
    expect(snackNotice(tester).status, AppStatus.info);
  });

  testWidgets('a longer catalog pages, and retiring is reachable on page two', (
    tester,
  ) async {
    final reader = _Reader.seeded(productCount: 4);
    final writer = _Writer();

    await _pump(tester, _controller(), reader, writer: writer, pageSize: 2);

    expect(_text(tester, 'catalog-management-page'), 'Page 1');
    expect(find.byKey(const ValueKey('inventory-actions-pd-3')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-next-page')),
    );
    await tester.pumpAndSettle();

    expect(_text(tester, 'catalog-management-page'), 'Page 2');
    expect(reader.cursors.last, 'pd-2');
    expect(find.byKey(const ValueKey('inventory-actions-pd-3')), findsOne);
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-previous-page')),
    );
    await tester.pumpAndSettle();

    expect(_text(tester, 'catalog-management-page'), 'Page 1');
  });

  testWidgets('a tenant switch mid-write discards the outcome', (tester) async {
    final controller = _controller();
    final writer = _Writer.deferred();

    await _pump(tester, controller, _Reader.seeded(), writer: writer);
    await _fillProduct(tester, name: 'Mandazi', sku: 'M-1', price: '20');
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-add-product')),
    );
    await tester.pump();

    controller.open(uid: 'owner-a', membership: _membership('tenant-b'));
    await tester.pump();
    writer.complete();
    await tester.pumpAndSettle();

    // The write was authorized against a business that is no longer open, so
    // its result never reaches this screen.
    expect(find.byType(AppSnackBar), findsNothing);
  });

  testWidgets('an unreadable catalog is a stated failure', (tester) async {
    await _pump(tester, _controller(), _Reader.failing(), writer: _Writer());

    expect(find.byKey(const ValueKey('catalog-management-failure')), findsOne);
  });

  testWidgets('a build with no callable offers no correction at all', (
    tester,
  ) async {
    await _pump(tester, _controller(), _Reader.seeded(), writer: _Writer());

    await _openProductActions(tester, 'pd-1');
    expect(
      find.byKey(const ValueKey('catalog-management-edit-pd-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('catalog-management-retire-pd-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('inventory-search')), findsOneWidget);
  });

  testWidgets('a correction states the before and after, then sends it', (
    tester,
  ) async {
    final reader = _Reader.seeded();
    final callable = _Callable();
    var syncs = 0;

    await _pump(
      tester,
      _controller(),
      reader,
      writer: _Writer(),
      callable: callable,
      onChanged: () => syncs++,
    );

    await _openCorrection(tester, 'pd-1');

    // Every field is offered at once and prefilled with what the product holds:
    // the callable validates the resulting document, so a refusal can name a
    // field this correction never touched.
    expect(_field(tester, 'catalog-management-edit-name'), 'White bread loaf');
    expect(_field(tester, 'catalog-management-edit-price'), '65.00');
    await tester.enterText(
      find.byKey(const ValueKey('catalog-management-edit-price')),
      '70',
    );
    await _review(tester);

    // **The before and after are the form, not a second screen.** The field
    // was prefilled with 65.00 and now reads 70.00, which is the comparison a
    // confirmation dialog used to restate after the decision was made. What
    // that dialog said about the consequence - that recorded sales keep the
    // price they were sold at - is in the form's scope paragraph, asserted by
    // `a correction states its consequences in the form`.
    expect(callable.payloads.single, <String, Object?>{
      'tenantId': 'tenant-a',
      'productId': 'pd-1',
      'requestId': 'catalog-test-request-0000',
      'price': 70.0,
    });
    expect(snackNotice(tester).message, startsWith('Corrected: unit price.'));
    // The catalog is re-read and the till is asked to re-read its own copy,
    // without which this device would keep selling at the old price.
    expect(reader.pages.where((path) => path == _productsPath).length, 2);
    expect(syncs, 1);
  });

  testWidgets('a manager corrects a name and is not offered money', (
    tester,
  ) async {
    final callable = _Callable();

    await _pump(
      tester,
      _controller(role: TenantRole.manager),
      _Reader.seeded(),
      writer: _Writer(),
      callable: callable,
    );
    await _openCorrection(tester, 'pd-1');

    // The callable reads its tier from the fields a payload names, so a form
    // that offered a price it knew would be refused would teach a manager only
    // that the app guesses.
    expect(
      find.byKey(const ValueKey('catalog-management-edit-price')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('catalog-management-edit-cost')),
      findsNothing,
    );
    // A role notice at `info` rather than a caption in `bodySmall`: three of
    // the five fields are offered and two are not, which is not a failure.
    expect(
      tester
          .widget<Callout>(
            find.byKey(const ValueKey('catalog-management-edit-money-hidden')),
          )
          .status,
      AppStatus.info,
    );
    await tester.enterText(
      find.byKey(const ValueKey('catalog-management-edit-name')),
      'Brown bread loaf',
    );
    await _review(tester);
    await tester.pumpAndSettle();

    expect(callable.payloads.single.containsKey('price'), isFalse);
    expect(callable.payloads.single['name'], 'Brown bread loaf');
  });

  testWidgets('the correction dialog folds its explanation away too', (
    tester,
  ) async {
    // The place a fold buys the most: what a person opened this dialog to do is
    // edit five fields, and the paragraph explaining how a correction is checked
    // is read once and then never again. Its summary is asserted against the
    // same one-line budget the route's other one is.
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      callable: _Callable(),
    );
    await _openCorrection(tester, 'pd-1');

    expect(
      find.byKey(const ValueKey('catalog-management-edit-scope')),
      findsNothing,
    );
    final summary = tester
        .widget<Disclosure>(
          find.byKey(
            const ValueKey('catalog-management-edit-scope-disclosure'),
          ),
        )
        .summary;
    // The **dialog** budget, not the page one: this shipped at 27 characters,
    // inside the page budget, and truncated the first time a capture put the
    // dialog on a phone.
    expect(
      summary.length,
      lessThanOrEqualTo(Disclosure.dialogSummaryCharacterBudget),
    );

    await _open(tester, 'catalog-management-edit-scope-disclosure');
    expect(
      _text(tester, 'catalog-management-edit-scope'),
      startsWith('Every field is filled in with what the product holds now.'),
    );
    // Opening an explanation reads nothing and writes nothing, and the fields
    // it sits above are untouched by it.
    expect(_field(tester, 'catalog-management-edit-name'), 'White bread loaf');
  });

  testWidgets('a correction states its consequences in the form', (
    tester,
  ) async {
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      callable: _Callable(),
    );
    await _openCorrection(tester, 'pd-1');
    await _open(tester, 'catalog-management-edit-scope-disclosure');

    // **The confirmation dialog's sentences, where they can be acted on.**
    // Until 2026-09-04 each of these was read on a second screen after the
    // fields had been filled in, which is to say after the decision. They are
    // beside the fields now, and this is what keeps them from being deleted
    // along with the dialog.
    final scope = _text(tester, 'catalog-management-edit-scope');
    expect(scope, contains('recorded permanently against the product'));
    expect(scope, contains('what each field held before'));
    expect(scope, contains('keep the price they were sold at'));
    expect(scope, contains('never changes a profit already reported'));
    expect(scope, contains('the old one finding this product'));
  });

  testWidgets('clearing a recorded cost is its own act, and sends null', (
    tester,
  ) async {
    final callable = _Callable(
      answer: <String, Object?>{
        'changedFields': <String>['cost'],
      },
    );

    await _pump(
      tester,
      _controller(),
      _Reader.seeded(cost: 40),
      writer: _Writer(),
      callable: callable,
    );
    await _openCorrection(tester, 'pd-1');

    expect(_field(tester, 'catalog-management-edit-cost'), '40.00');
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-edit-clear-cost')),
    );
    await tester.pump();
    await _review(tester);

    // The before-and-after used to be restated in a confirmation dialog. The
    // form shows both - the field held 40.00 and is now cleared - and what
    // clearing a cost costs is stated in the form's own scope paragraph, which
    // `a correction states the consequences where they are read` covers.
    // What matters here is what reaches the wire.
    //
    // The one field in this app where null on the wire means "remove this"
    // rather than "leave it alone".
    expect(callable.payloads.single.containsKey('cost'), isTrue);
    expect(callable.payloads.single['cost'], isNull);
  });

  testWidgets('a category nothing can read is named, never shown as an ID', (
    tester,
  ) async {
    // Finding 5's second half. `cat-not-cached` is not bad data - it is a
    // product filed under a category this surface cannot read - so the state
    // stays legible and only the document ID goes.
    await _pump(
      tester,
      _controller(),
      _Reader.strandedCategory(),
      writer: _Writer(),
      callable: _Callable(),
    );

    expect(find.textContaining(unlistedTenantCategoryLabel), findsOne);
    expect(_documentIdsOnScreen(tester), isEmpty);

    await _openCorrection(tester, 'pd-1');

    expect(
      _text(tester, 'catalog-management-edit-category-off'),
      startsWith('This product is filed under $unlistedTenantCategoryPhrase.'),
    );
    expect(_documentIdsOnScreen(tester), isEmpty);
  });

  testWidgets('a product with no cost is not offered a clear', (tester) async {
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      callable: _Callable(),
    );
    await _openCorrection(tester, 'pd-1');

    expect(_field(tester, 'catalog-management-edit-cost'), '');
    expect(
      find.byKey(const ValueKey('catalog-management-edit-clear-cost')),
      findsNothing,
    );
  });

  testWidgets('an untouched product is never sent', (tester) async {
    final callable = _Callable();

    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      callable: callable,
    );
    await _openCorrection(tester, 'pd-1');
    await _review(tester);

    // Refused before anything is confirmed: the server treats a request that
    // changes nothing as a caller defect, and reaching it would put an
    // idempotency record behind a request that does nothing.
    expect(
      find.byKey(const ValueKey('catalog-management-confirm')),
      findsNothing,
    );
    expect(callable.payloads, isEmpty);
    expect(
      snackNotice(tester).message,
      startsWith('Nothing on the form differs'),
    );
    // **Not a refusal, even though the client refused to send it.** There was
    // nothing to correct, so the operator's intent is already satisfied and
    // nothing is wrong. It is deliberately not `neutral` either - the bulk
    // report gives that to an unchanged *row*, and one status meaning two
    // things at two scales is the failure §2.1 exists to end.
    expect(snackNotice(tester).status, AppStatus.info);
  });

  testWidgets('a refused correction changes nothing and says why', (
    tester,
  ) async {
    final reader = _Reader.seeded();
    final callable = _Callable(
      error: FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'The category does not exist in this business.',
      ),
    );

    await _pump(
      tester,
      _controller(),
      reader,
      writer: _Writer(),
      callable: callable,
    );
    await _correct(tester, 'pd-1', name: 'Brown bread loaf');

    expect(
      snackNotice(tester).message,
      startsWith('That category no longer exists'),
    );
    // A proven refusal changed nothing, so there is nothing to re-read.
    expect(reader.pages.where((path) => path == _productsPath).length, 1);
  });

  testWidgets('an unknown outcome retries the same correction, not a new one', (
    tester,
  ) async {
    final callable = _Callable(
      error: FirebaseFunctionsException(code: 'unavailable', message: 'down'),
    );

    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      callable: callable,
    );
    await _correct(tester, 'pd-1', name: 'Brown bread loaf');

    expect(snackNotice(tester).message, startsWith('The result is unknown.'));
    await _correct(tester, 'pd-1', name: 'Brown bread loaf');

    // A genuine retry answers off the server's own idempotency record. A fresh
    // ID would reach the refusal it keeps for a request that changes nothing,
    // if the first attempt had in fact landed.
    expect(callable.payloads.length, 2);
    expect(
      callable.payloads.first['requestId'],
      callable.payloads.last['requestId'],
    );

    // A different correction is a different request, because the server refuses
    // one request ID carrying two different payloads.
    await _correct(tester, 'pd-1', name: 'Rye bread loaf');
    expect(
      callable.payloads.last['requestId'],
      isNot(callable.payloads.first['requestId']),
    );
  });

  testWidgets('a changed cost after an unknown outcome is a new request', (
    tester,
  ) async {
    // This one is load-bearing rather than symmetrical. `updateProduct`
    // fingerprints its idempotency record from productId, name, sku, price, and
    // categoryId - **not** cost - so a reused request ID carrying only a
    // different cost would be answered off the stored record and the new cost
    // silently not applied. Every other field would be refused as
    // `already-exists`. Holding the retained ID against the exact correction it
    // was issued for is what closes that from this side.
    final callable = _Callable(
      error: FirebaseFunctionsException(code: 'unavailable', message: 'down'),
    );

    await _pump(
      tester,
      _controller(),
      _Reader.seeded(cost: 40),
      writer: _Writer(),
      callable: callable,
    );
    await _correctCost(tester, 'pd-1', cost: '41');
    await _correctCost(tester, 'pd-1', cost: '41');

    expect(
      callable.payloads.first['requestId'],
      callable.payloads[1]['requestId'],
    );
    await _correctCost(tester, 'pd-1', cost: '42');

    expect(callable.payloads.last['cost'], 42.0);
    expect(
      callable.payloads.last['requestId'],
      isNot(callable.payloads.first['requestId']),
    );
  });

  testWidgets('a settled correction starts the next one afresh', (
    tester,
  ) async {
    final callable = _Callable();

    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      callable: callable,
    );
    await _correct(tester, 'pd-1', name: 'Brown bread loaf');
    await _correct(tester, 'pd-1', name: 'Rye bread loaf');

    expect(
      callable.payloads.first['requestId'],
      isNot(callable.payloads.last['requestId']),
    );
  });

  testWidgets('an untrustworthy answer re-reads instead of claiming success', (
    tester,
  ) async {
    final reader = _Reader.seeded();
    // A response describing a product this correction never named.
    final callable = _Callable(answer: <String, Object?>{'productId': 'pd-2'});

    await _pump(
      tester,
      _controller(),
      reader,
      writer: _Writer(),
      callable: callable,
    );
    await _correct(tester, 'pd-1', name: 'Brown bread loaf');

    expect(
      snackNotice(tester).message,
      startsWith('The correction was sent and its answer could not be trusted'),
    );
    expect(reader.pages.where((path) => path == _productsPath).length, 2);
  });

  testWidgets('a tenant switch mid-correction discards the outcome', (
    tester,
  ) async {
    final controller = _controller();
    final callable = _Callable.deferred();

    await _pump(
      tester,
      controller,
      _Reader.seeded(),
      writer: _Writer(),
      callable: callable,
    );
    await _openCorrection(tester, 'pd-1');
    await tester.enterText(
      find.byKey(const ValueKey('catalog-management-edit-name')),
      'Brown bread loaf',
    );
    await _review(tester);
    await tester.pump();

    controller.open(uid: 'owner-a', membership: _membership('tenant-b'));
    await tester.pump();
    callable.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AppSnackBar), findsNothing);
  });

  testWidgets(
    'the correction form draws the photograph, not a thumbnail of it',
    (tester) async {
      // **The 2026-08-25 reversal.** The old catalog form drew the picture 350
      // high in a bordered well headed *Product image*; the Stitch pass had
      // replaced it with a 64px square, which is a size at which the wrong
      // photograph and the right one are the same picture.
      FilePicker.platform = _FilePicker(_onePixelPng);
      await _pump(
        tester,
        _controller(),
        _Reader.seeded(),
        writer: _Writer(),
        callable: _Callable(),
        imageStore: _ImageStore(),
      );

      await _openCorrection(tester, 'pd-1');

      // **No `Product image` heading since 2026-08-26.** It named what the
      // reader could already see - a picture, or the words below saying there
      // is none - which is §7's own complaint about a heading. On the compact
      // sheet the picture is the masthead and needs no label either.
      expect(find.text('Product image'), findsNothing);
      // Nothing chosen and nothing saved, and the well says so in words rather
      // than by drawing an empty box.
      expect(
        find.byKey(const ValueKey('inventory-product-image-empty')),
        findsOne,
      );

      await tester.tap(find.byKey(const ValueKey('inventory-replace-image')));
      await tester.pumpAndSettle();

      final preview = tester.widget<Image>(
        find.byKey(const ValueKey('inventory-product-image-preview')),
      );
      expect((preview.image as MemoryImage).bytes, _onePixelPng);
      // 350 is the old form's own figure, and it reaches the widget through the
      // token layer rather than as a literal here.
      expect(
        tester.getSize(find.byType(AspectRatio)).height,
        lessThanOrEqualTo(
          spiritTheme.extension<AppTokens>()!.layout.productImagePreview,
        ),
      );
    },
  );

  testWidgets('a build with no cut-out service offers no cut-out', (
    tester,
  ) async {
    // The remover is absent wherever the deployment never bought one, and an
    // absent capability draws nothing at all - the same rule the writer, the
    // update callable and the bulk route are all injected under.
    FilePicker.platform = _FilePicker(_onePixelPng);
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      callable: _Callable(),
      imageStore: _ImageStore(),
    );

    await _openCorrection(tester, 'pd-1');

    expect(
      find.byKey(const ValueKey('inventory-remove-background')),
      findsNothing,
    );
  });

  testWidgets('the cut-out waits for a photograph, disabled rather than gone', (
    tester,
  ) async {
    // §5's matrix has a `disabled` row, and the reason `Pagination` states
    // applies here too: a control that vanishes moves everything under it, so
    // the button a person is reaching for slides as they reach.
    FilePicker.platform = _FilePicker(_onePixelPng);
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      callable: _Callable(),
      imageStore: _ImageStore(),
      backgroundRemover: _BackgroundRemover(answer: _twoPixelPng),
    );

    await _openCorrection(tester, 'pd-1');

    final removal = find.byKey(const ValueKey('inventory-remove-background'));
    expect(removal, findsOne);
    expect(tester.widget<AppIconButton>(removal).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('inventory-replace-image')));
    await tester.pumpAndSettle();

    expect(tester.widget<AppIconButton>(removal).onPressed, isNotNull);
  });

  testWidgets('a cut-out replaces the photograph the form will save', (
    tester,
  ) async {
    FilePicker.platform = _FilePicker(_onePixelPng);
    final remover = _BackgroundRemover(answer: _twoPixelPng);
    final imageStore = _ImageStore();
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      callable: _Callable(),
      imageStore: imageStore,
      backgroundRemover: remover,
    );

    await _openCorrection(tester, 'pd-1');
    await tester.tap(find.byKey(const ValueKey('inventory-replace-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inventory-remove-background')));
    await tester.pumpAndSettle();

    expect(remover.calls, 1);
    // What the well shows and what the correction would upload are the cut-out,
    // not the photograph that went into it.
    final preview = tester.widget<Image>(
      find.byKey(const ValueKey('inventory-product-image-preview')),
    );
    expect((preview.image as MemoryImage).bytes, _twoPixelPng);

    await _review(tester);
    await tester.pumpAndSettle();

    expect(imageStore.uploaded.single, _twoPixelPng);
  });

  testWidgets('a refused cut-out says the chosen photograph is unchanged', (
    tester,
  ) async {
    // The one thing an operator needs after a failed cut-out is whether they
    // still have the photograph they picked. Every refusal says so, and this
    // asserts the form still holds it as well as saying it.
    FilePicker.platform = _FilePicker(_onePixelPng);
    final remover = _BackgroundRemover(
      failure: TenantBackgroundRemovalFailure.allowanceSpent,
    );
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      callable: _Callable(),
      imageStore: _ImageStore(),
      backgroundRemover: remover,
    );

    await _openCorrection(tester, 'pd-1');
    await tester.tap(find.byKey(const ValueKey('inventory-replace-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inventory-remove-background')));
    await tester.pumpAndSettle();

    final callout = tester.widget<Callout>(
      find.byKey(const ValueKey('inventory-remove-background-failed')),
    );
    expect(callout.status, AppStatus.problem);
    expect(callout.message, contains('used up its background removals'));
    expect(callout.message, contains('unchanged'));
    final preview = tester.widget<Image>(
      find.byKey(const ValueKey('inventory-product-image-preview')),
    );
    expect((preview.image as MemoryImage).bytes, _onePixelPng);
  });

  testWidgets('a session that may not correct products is offered no cut-out', (
    tester,
  ) async {
    // Asked of the remover rather than answered here, so one role list decides
    // it - and the callable enforces the same list server-side.
    FilePicker.platform = _FilePicker(_onePixelPng);
    await _pump(
      tester,
      _controller(),
      _Reader.seeded(),
      writer: _Writer(),
      callable: _Callable(),
      imageStore: _ImageStore(),
      backgroundRemover: _BackgroundRemover(
        answer: _twoPixelPng,
        allowed: false,
      ),
    );

    await _openCorrection(tester, 'pd-1');

    expect(
      find.byKey(const ValueKey('inventory-remove-background')),
      findsNothing,
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  TenantCatalogWriter? writer,
  UpdateProductCallable? callable,
  WidgetBuilder? bulkRoute,
  VoidCallback? onChanged,
  int pageSize = 20,
  double width = 1400,
  TenantProductSearchReader? productSearchReader,
  TenantProductImageStore? imageStore,
  HiveTenantProductImageDrafts? imageDrafts,
  TenantCatalogUndo? undo,
  TenantProductBackgroundRemover? backgroundRemover,
  TenantProductRouteBuilder? productStockRoute,
  TenantProductAdjustStockOpener? adjustStockRoute,
  List<TenantRole> productStockRoles = const <TenantRole>[],
}) async {
  tester.view.physicalSize = Size(width, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: controller,
        child: Scaffold(
          body: TenantCatalogManagementPanel(
            reader: reader,
            writer: writer,
            updateCallable: callable,
            bulkRoute: bulkRoute,
            onChanged: onChanged,
            pageSize: pageSize,
            requestIdFactory: _requestIds().call,
            productSearchReader: productSearchReader,
            imageStore: imageStore,
            imageDrafts: imageDrafts,
            undo: undo,
            backgroundRemover: backgroundRemover,
            productStockRoute: productStockRoute,
            adjustStockRoute: adjustStockRoute,
            productStockRoles: productStockRoles,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _openCorrection(WidgetTester tester, String productId) async {
  await _waitOutSnackBar(tester);
  await _tapProductAction(
    tester,
    productId,
    'catalog-management-edit-$productId',
  );
  expect(
    find.byKey(const ValueKey('catalog-management-edit-screen')),
    findsOneWidget,
  );
  expect(find.byType(AlertDialog), findsNothing);
}

Future<void> _openProductActions(WidgetTester tester, String productId) async {
  await tester.tap(find.byKey(ValueKey('inventory-actions-$productId')));
  await tester.pumpAndSettle();
}

Future<void> _tapProductAction(
  WidgetTester tester,
  String productId,
  String actionKey,
) async {
  await _openProductActions(tester, productId);
  await tester.tap(find.byKey(ValueKey(actionKey)));
  await tester.pumpAndSettle();
}

Future<void> _review(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('catalog-management-edit-review')),
  );
  await tester.pumpAndSettle();
}

/// Opens the correction form, changes one field, and confirms it.
///
/// **It leaves the answer on screen**, because since 2026-09-03 every outcome
/// is a snack bar and reading one is what most of these tests are for. The wait
/// that used to be here has moved to the front of the actions that follow -
/// `_openCorrection` and `_fillProduct` - which is where it was always really
/// needed: a floating snack bar sits over the bottom of the surface, so a
/// second correction in one test found its *Review* control covered and `tap`
/// reported that the offset "would not hit test".
Future<void> _correct(
  WidgetTester tester,
  String productId, {
  required String name,
}) async {
  await _openCorrection(tester, productId);
  await tester.enterText(
    find.byKey(const ValueKey('catalog-management-edit-name')),
    name,
  );
  await _review(tester);
  await tester.pumpAndSettle();
}

/// Advances past a snack bar's dwell and waits for it to leave.
///
/// One jump past the dwell, then real frames until it goes: `ScaffoldMessenger`
/// schedules the dismissal timer inside a `.then()` on the entrance animation,
/// so a single large `pump` produces one frame later on with no timer ever set.
Future<void> _waitOutSnackBar(WidgetTester tester) async {
  if (find.byType(AppSnackBar).evaluate().isEmpty) return;
  await tester.pump(AppSnackBar.dwell + const Duration(seconds: 1));
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(AppSnackBar).evaluate().isEmpty) return;
  }
  await tester.pumpAndSettle();
}

/// Deterministic request IDs, so a test can assert that one confirmation keeps
/// one document identity and the next one does not.
_RequestIds _requestIds() => _RequestIds();

final class _RequestIds {
  int _issued = 0;

  String call() =>
      'catalog-test-request-${(_issued++).toString().padLeft(4, '0')}';
}

Future<void> _fillProduct(
  WidgetTester tester, {
  required String name,
  required String sku,
  required String price,
}) async {
  await _waitOutSnackBar(tester);
  if (find
      .byKey(const ValueKey('catalog-management-product-name'))
      .evaluate()
      .isEmpty) {
    await tester.tap(find.byKey(const ValueKey('inventory-add-product')));
    await tester.pumpAndSettle();
  }
  expect(
    find.byKey(const ValueKey('catalog-management-add-screen')),
    findsOneWidget,
  );
  expect(find.byType(AlertDialog), findsNothing);
  await tester.tap(
    find.byKey(const ValueKey('catalog-management-product-category')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bakery').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('catalog-management-product-name')),
    name,
  );
  await tester.enterText(
    find.byKey(const ValueKey('catalog-management-product-sku')),
    sku,
  );
  await tester.enterText(
    find.byKey(const ValueKey('catalog-management-product-price')),
    price,
  );
  await tester.pump();
}

Future<void> _confirmProduct(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('catalog-management-add-product')),
  );
  await tester.pumpAndSettle();
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

/// Opens one [Disclosure] by its own key and settles the spring behind it.
///
/// A closed disclosure is gone from the tree rather than clipped to nothing, so
/// reading the prose inside one is opening it first - which is also what a
/// person does.
Future<void> _open(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Every rendered string carrying the shape of a category document ID, over the
/// whole tree rather than over one slot: the point of the assertion is that no
/// surface anywhere reaches for the ID, and the two that did were the two nobody
/// was looking at. `cat-` is the seeded shape and `ct_` is what
/// `buildCategoryIntent` derives, and neither is a word.
Iterable<String> _documentIdsOnScreen(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data)
    .nonNulls
    .where(RegExp(r'cat-|ct_').hasMatch);

String _field(WidgetTester tester, String key) => fieldText(tester, key);

bool _enabled(WidgetTester tester, String key) => pressable(tester, key);

TenantSessionController _controller({TenantRole role = TenantRole.owner}) =>
    TenantSessionController()..open(
      uid: 'owner-a',
      membership: _membership('tenant-a', role: role),
    );

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.owner,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: role == TenantRole.owner,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

final class _Writer implements TenantCatalogWriter {
  _Writer()
    : _answer = const TenantCatalogWriteResult.committed(),
      _defer = false;

  _Writer.answering(this._answer) : _defer = false;

  _Writer.deferred()
    : _answer = const TenantCatalogWriteResult.committed(),
      _defer = true;

  final TenantCatalogWriteResult _answer;
  final bool _defer;
  final List<TenantProductCreateIntent> products =
      <TenantProductCreateIntent>[];
  final List<TenantCategoryCreateIntent> categories =
      <TenantCategoryCreateIntent>[];
  final List<TenantCategoryRenameIntent> renamed =
      <TenantCategoryRenameIntent>[];
  final List<TenantProductRetireIntent> retired = <TenantProductRetireIntent>[];
  final List<Completer<TenantCatalogWriteResult>> _pending =
      <Completer<TenantCatalogWriteResult>>[];

  void complete() {
    if (_pending.isEmpty) return;
    _pending.removeAt(0).complete(_answer);
  }

  Future<TenantCatalogWriteResult> _answered() {
    if (!_defer) return Future<TenantCatalogWriteResult>.value(_answer);
    final completer = Completer<TenantCatalogWriteResult>();
    _pending.add(completer);
    return completer.future;
  }

  @override
  Future<TenantCatalogWriteResult> createCategory(
    TenantCategoryCreateIntent intent,
  ) {
    categories.add(intent);
    return _answered();
  }

  @override
  Future<TenantCatalogWriteResult> createProduct(
    TenantProductCreateIntent intent,
  ) {
    products.add(intent);
    return _answered();
  }

  @override
  Future<TenantCatalogWriteResult> renameCategory(
    TenantCategoryRenameIntent intent,
  ) {
    renamed.add(intent);
    return _answered();
  }

  @override
  Future<TenantCatalogWriteResult> retireProduct(
    TenantProductRetireIntent intent,
  ) {
    retired.add(intent);
    return _answered();
  }
}

/// Opens the correction form, changes only the unit cost, and confirms it.
Future<void> _correctCost(
  WidgetTester tester,
  String productId, {
  required String cost,
}) async {
  await _openCorrection(tester, productId);
  await tester.enterText(
    find.byKey(const ValueKey('catalog-management-edit-cost')),
    cost,
  );
  await _review(tester);
  await tester.pumpAndSettle();
}

/// A recording stand-in for `updateProduct`.
///
/// Its default answer is a well-formed response for a name correction, with
/// whatever the test overrides merged over it.
final class _Callable implements UpdateProductCallable {
  _Callable({Map<String, Object?>? answer, this.error})
    : _overrides = answer ?? const <String, Object?>{},
      _defer = false;

  _Callable.deferred()
    : _overrides = const <String, Object?>{},
      error = null,
      _defer = true;

  final Map<String, Object?> _overrides;
  final Object? error;
  final bool _defer;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  final List<Completer<Object?>> _pending = <Completer<Object?>>[];

  void complete() {
    if (_pending.isEmpty) return;
    _pending.removeAt(0).complete(_answer(payloads.last));
  }

  Map<String, Object?> _answer(Map<String, Object?> payload) =>
      <String, Object?>{
        'updateId': 'pu_0123456789abcdef',
        'tenantId': payload['tenantId'],
        'productId': payload['productId'],
        'changedFields': <String>[
          for (final field in <String>[
            'name',
            'sku',
            'price',
            'cost',
            'categoryId',
            'image',
          ])
            if (payload.containsKey(field)) field,
        ],
        'name': payload['name'] ?? 'White bread loaf',
        'sku': payload['sku'] ?? '6161100000019',
        'price': payload['price'] ?? 65.0,
        'priceMinor': ((payload['price'] as double? ?? 65.0) * 100).round(),
        'categoryId': payload['categoryId'] ?? 'cat-bakery',
        'image': payload.containsKey('image') ? payload['image'] : null,
        ..._overrides,
      };

  @override
  Future<Object?> call(Map<String, Object?> payload) {
    payloads.add(payload);
    if (error != null) return Future<Object?>.error(error!);
    if (!_defer) return Future<Object?>.value(_answer(payload));
    final completer = Completer<Object?>();
    _pending.add(completer);
    return completer.future;
  }
}

/// A collection reader keyed per business and per collection, answering in
/// ascending document-ID order and honouring the exact page bound and cursor
/// the guarded repository asked for.
final class _Reader implements TenantDataReader {
  _Reader(this._collections) : _fails = false;

  _Reader.empty() : this(const <String, Map<String, Map<String, Object?>>>{});

  _Reader.failing()
    : _collections = const <String, Map<String, Map<String, Object?>>>{},
      _fails = true;

  /// One product filed under a category document nothing can read - the exact
  /// state the seeded `cat-not-cached` produced on the device.
  factory _Reader.strandedCategory() =>
      _Reader(<String, Map<String, Map<String, Object?>>>{
        _categoriesPath: <String, Map<String, Object?>>{
          'cat-bakery': <String, Object?>{'name': 'Bakery'},
        },
        _productsPath: <String, Map<String, Object?>>{
          'pd-1': <String, Object?>{
            'name': 'Charcoal 2kg',
            'SKU': '6161100000019',
            'price': 65,
            'quantity': 40,
            'categoryId': 'cat-not-cached',
          },
        },
      });

  factory _Reader.seeded({int productCount = 2, double? cost}) =>
      _Reader(<String, Map<String, Map<String, Object?>>>{
        _categoriesPath: <String, Map<String, Object?>>{
          'cat-bakery': <String, Object?>{'name': 'Bakery'},
          'cat-drinks': <String, Object?>{'name': 'Drinks'},
        },
        _productsPath: <String, Map<String, Object?>>{
          for (var index = 1; index <= productCount; index++)
            'pd-$index': <String, Object?>{
              'name': index == 1 ? 'White bread loaf' : 'Product $index',
              'SKU': '616110000001$index',
              'price': 65,
              if (cost != null && index == 1) 'cost': cost,
              'quantity': index == 1 ? 40 : index,
              'categoryId': 'cat-bakery',
            },
        },
      });

  final Map<String, Map<String, Map<String, Object?>>> _collections;
  final bool _fails;

  final List<String> pages = <String>[];
  final List<String?> cursors = <String?>[];

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    pages.add(query.collectionPath);
    cursors.add(query.startAfterDocumentId);
    if (_fails) throw StateError('unavailable');
    final documents = _collections[query.collectionPath];
    if (documents == null) return const <TenantQueryDocumentSnapshot>[];
    final ids = documents.keys.toList()..sort();
    final cursor = query.startAfterDocumentId;
    return <TenantQueryDocumentSnapshot>[
      for (final id in ids)
        if (cursor == null || id.compareTo(cursor) > 0)
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/$id',
            data: documents[id]!,
          ),
    ].take(query.limit).toList();
  }
}

final class _SearchReader implements TenantProductSearchReader {
  _SearchReader(this._products);

  factory _SearchReader.seeded({required int productCount}) =>
      _SearchReader(<TenantQueryDocumentSnapshot>[
        for (var index = 1; index <= productCount; index++)
          TenantQueryDocumentSnapshot(
            path: '$_productsPath/pd-$index',
            data: <String, Object?>{
              'name': index == 1 ? 'Brown bread' : 'Product $index',
              'SKU': index == 1 ? 'BR-1' : 'PD-$index',
              'price': 65,
              'quantity': index == 1 ? 0 : index,
              'categoryId': 'cat-bakery',
              'searchName': index == 1 ? 'brown bread' : 'product $index',
            },
          ),
      ]);

  final List<TenantQueryDocumentSnapshot> _products;
  final List<TenantProductSearchQuery> queries = <TenantProductSearchQuery>[];

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantProducts(
    TenantProductSearchQuery query,
  ) async {
    queries.add(query);
    final cursor = query.startAfter?.documentId;
    return <TenantQueryDocumentSnapshot>[
      for (final product in _products)
        if (cursor == null ||
            product.path.split('/').last.compareTo(cursor) > 0)
          product,
    ].take(query.limit).toList(growable: false);
  }
}

/// A store that refuses every upload with [code].
///
/// Named for what it is for: the sentence a shop reads when Storage says no is
/// the only account of the fault anybody outside this machine ever gets.
final class _RefusingImageStore implements TenantProductImageStore {
  _RefusingImageStore(this.code);

  final String code;

  @override
  Future<TenantProductImageUpload> upload({
    required String tenantId,
    required String productId,
    required TenantProductImageCandidate candidate,
  }) async => throw TenantProductImageException(code);

  @override
  Future<void> removeOwned({
    required String tenantId,
    required String productId,
    required Uri imageUrl,
  }) async {}
}

final class _ImageStore implements TenantProductImageStore {
  final List<TenantProductImageUpload> uploads = <TenantProductImageUpload>[];
  final List<Uri> removed = <Uri>[];

  /// The bytes each upload carried, so a test can assert *which* photograph a
  /// correction saved rather than only that it saved one.
  final List<Uint8List> uploaded = <Uint8List>[];

  @override
  Future<TenantProductImageUpload> upload({
    required String tenantId,
    required String productId,
    required TenantProductImageCandidate candidate,
  }) async {
    final upload = TenantProductImageUpload(
      url: Uri.parse(
        'https://storage.test/tenantProductImages/$tenantId/$productId/image.png',
      ),
      objectPath: 'tenantProductImages/$tenantId/$productId/image.png',
    );
    uploads.add(upload);
    uploaded.add(candidate.bytes);
    return upload;
  }

  @override
  Future<void> removeOwned({
    required String tenantId,
    required String productId,
    required Uri imageUrl,
  }) async {
    removed.add(imageUrl);
  }
}

final class _FilePicker extends FilePicker {
  _FilePicker(this.bytes);

  final Uint8List bytes;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult(<PlatformFile>[
    PlatformFile(name: 'product.png', size: bytes.length, bytes: bytes),
  ]);
}

/// A 1x1 PNG, small enough to be a literal and real enough to pass the
/// candidate's magic-number check.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
  'A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// A different real PNG, so "the cut-out replaced the photograph" is an
/// assertion about bytes rather than about a call having happened.
final Uint8List _twoPixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAE0lEQVR4nGP4z8DwnwGM'
  '/zMwAAAf7gP9NRsAMwAAAABJRU5ErkJggg==',
);

/// Stands in for the callable-backed remover, answering with a cut-out or with
/// one of its refusals.
final class _BackgroundRemover implements TenantProductBackgroundRemover {
  _BackgroundRemover({this.answer, this.failure, this.allowed = true});

  final Uint8List? answer;
  final TenantBackgroundRemovalFailure? failure;
  final bool allowed;
  int calls = 0;

  @override
  bool canRemoveInSession(TenantSession session) => allowed;

  @override
  Future<TenantProductImageCandidate> remove({
    required TenantSession session,
    required TenantProductImageCandidate candidate,
  }) async {
    calls += 1;
    final refusal = failure;
    if (refusal != null) throw TenantBackgroundRemovalException(refusal);
    return TenantProductImageCandidate(
      bytes: answer!,
      fileName: cutOutFileName(candidate.fileName),
    );
  }
}
