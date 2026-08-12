import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/buttons.dart';
import '../support/fields.dart';

const String _productsPath = 'tenants/tenant-a/products';
const String _categoriesPath = 'tenants/tenant-a/categories';

void main() {
  testWidgets('a cashier is refused the whole route', (tester) async {
    await _pump(
      tester,
      _controller(role: TenantRole.cashier),
      _Reader.seeded(),
      writer: _Writer(),
    );

    expect(find.byKey(const ValueKey('catalog-management-denied')), findsOne);
    expect(
      find.byKey(const ValueKey('catalog-management-add-product')),
      findsNothing,
    );
  });

  testWidgets('a build with no writer states the catalog and offers nothing', (
    tester,
  ) async {
    await _pump(tester, _controller(), _Reader.seeded());

    expect(
      find.byKey(const ValueKey('catalog-management-read-only')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('catalog-management-add-product')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('catalog-management-category-name')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('catalog-management-retire-pd-1')),
      findsNothing,
    );
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
    await tester.tap(find.text('How bulk changes and import work'));
    await tester.pumpAndSettle();
    expect(find.text(explanation), findsOneWidget);
    // Opening an explanation reads nothing and writes nothing - it is a visual
    // change, which is the whole reason it fits inside this step.
    expect(find.byKey(const ValueKey('catalog-management-bulk')), findsOne);
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

  testWidgets('a business with no categories is told what comes first', (
    tester,
  ) async {
    await _pump(tester, _controller(), _Reader.empty(), writer: _Writer());

    expect(
      find.byKey(const ValueKey('catalog-management-no-categories')),
      findsOne,
    );
    expect(
      _text(tester, 'catalog-management-selected-category'),
      'Add a category before adding a product.',
    );
    // Every product names a category, so adding one is not offered until there
    // is a category to name.
    expect(_enabled(tester, 'catalog-management-add-product'), isFalse);
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
    await tester.enterText(
      find.byKey(const ValueKey('catalog-management-category-name')),
      '  Cold  drinks  ',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-add-category')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('It cannot be renamed or removed'), findsOne);
    await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
    await tester.pumpAndSettle();

    expect(writer.categories.single.name, 'Cold drinks');
    expect(writer.categories.single.path, startsWith('$_categoriesPath/'));
    expect(syncs, 1);
    expect(
      _text(tester, 'catalog-management-notice'),
      startsWith('Category added.'),
    );
    // Two reads of each collection: the first render, and the re-read a commit
    // asks for, so what is listed is the server's catalog and not the typing.
    expect(reader.pages.where((path) => path == _categoriesPath).length, 2);
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

    // The three things the confirmation has to say: where it is filed, that it
    // arrives empty, and that none of it can be corrected afterwards.
    expect(find.textContaining('filed under Bakery'), findsOne);
    expect(find.textContaining('added holding no stock'), findsOne);
    expect(
      find.textContaining('Nothing in this app can change a name'),
      findsOne,
    );
    await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
    await tester.pumpAndSettle();

    final intent = writer.products.single;
    expect(intent.name, 'Mandazi');
    expect(intent.sku, '6161100000026');
    expect(intent.priceMinor, 2050);
    expect(intent.categoryId, 'cat-bakery');
    expect(intent.documentData()['quantity'], 0);
    expect(syncs, 1);
    // The form is emptied, so the next product is not a near-copy of this one.
    expect(_field(tester, 'catalog-management-product-name'), '');
    expect(_field(tester, 'catalog-management-product-sku'), '');
    expect(
      _text(tester, 'catalog-management-selected-category'),
      'Choose the category this product is filed under.',
    );
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

    // Refused before anything is confirmed, so nothing is asked about a value
    // this boundary would not have written.
    expect(
      find.byKey(const ValueKey('catalog-management-confirm')),
      findsNothing,
    );
    expect(writer.products, isEmpty);
    expect(
      _text(tester, 'catalog-management-notice'),
      startsWith('Enter a price as a plain amount'),
    );
  });

  testWidgets('cancelling the confirmation writes nothing', (tester) async {
    final writer = _Writer();

    await _pump(tester, _controller(), _Reader.seeded(), writer: writer);
    await _fillProduct(tester, name: 'Mandazi', sku: 'M-1', price: '20');
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-add-product')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalog-management-cancel')));
    await tester.pumpAndSettle();

    expect(writer.products, isEmpty);
    expect(
      find.byKey(const ValueKey('catalog-management-notice')),
      findsNothing,
    );
    // The typing survives a cancellation, because cancelling is not a mistake.
    expect(_field(tester, 'catalog-management-product-name'), 'Mandazi');
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

    expect(
      _text(tester, 'catalog-management-notice'),
      startsWith('The result is unknown.'),
    );
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
    );

    expect(
      find.byKey(const ValueKey('catalog-management-add-product')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('catalog-management-retire-pd-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('catalog-management-retire-unavailable')),
      findsOne,
    );
    // A manager stocks the catalog without being shown the margin. Every active
    // member can read a product document, so this is a surface boundary rather
    // than a secrecy guarantee - but it is the boundary that decides whether a
    // manager is *shown* what the business pays.
    expect(
      find.byKey(const ValueKey('catalog-management-product-cost')),
      findsNothing,
    );
  });

  testWidgets('an owner is offered the unit cost the manager is not', (
    tester,
  ) async {
    await _pump(tester, _controller(), _Reader.seeded(), writer: _Writer());

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
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-retire-pd-1')),
    );
    await tester.pumpAndSettle();

    // The ledger outlives the product, every sale line still names it, and it
    // is never the way a mistake is corrected.
    expect(find.textContaining('its stock ledger'), findsOne);
    expect(find.textContaining('It still holds 40 in stock'), findsOne);
    expect(
      find.textContaining('This is not how a mistake is corrected'),
      findsOne,
    );
    await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
    await tester.pumpAndSettle();

    expect(writer.retired.single.productId, 'pd-1');
    expect(writer.retired.single.quantity, 40);
    expect(syncs, 1);
    expect(
      _text(tester, 'catalog-management-notice'),
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
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-retire-pd-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
    await tester.pumpAndSettle();

    expect(
      _text(tester, 'catalog-management-notice'),
      startsWith('Nothing was retired.'),
    );
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

    expect(
      _text(tester, 'catalog-management-notice'),
      startsWith('This device is offline'),
    );
  });

  testWidgets('a longer catalog pages, and retiring is reachable on page two', (
    tester,
  ) async {
    final reader = _Reader.seeded(productCount: 4);
    final writer = _Writer();

    await _pump(tester, _controller(), reader, writer: writer, pageSize: 2);

    expect(_text(tester, 'catalog-management-page'), 'Page 1');
    expect(
      find.byKey(const ValueKey('catalog-management-retire-pd-3')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('catalog-management-next-page')),
    );
    await tester.pumpAndSettle();

    expect(_text(tester, 'catalog-management-page'), 'Page 2');
    expect(reader.cursors.last, 'pd-2');
    expect(
      find.byKey(const ValueKey('catalog-management-retire-pd-3')),
      findsOne,
    );
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
    await tester.pump();

    controller.open(uid: 'owner-a', membership: _membership('tenant-b'));
    await tester.pump();
    writer.complete();
    await tester.pumpAndSettle();

    // The write was authorized against a business that is no longer open, so
    // its result never reaches this screen.
    expect(
      find.byKey(const ValueKey('catalog-management-notice')),
      findsNothing,
    );
  });

  testWidgets('an unreadable catalog is a stated failure', (tester) async {
    await _pump(tester, _controller(), _Reader.failing(), writer: _Writer());

    expect(find.byKey(const ValueKey('catalog-management-failure')), findsOne);
  });

  testWidgets('a build with no callable offers no correction at all', (
    tester,
  ) async {
    await _pump(tester, _controller(), _Reader.seeded(), writer: _Writer());

    expect(find.byKey(const ValueKey('catalog-management-edit-pd-1')), findsNothing);
    expect(
      _text(tester, 'catalog-management-scope'),
      contains('are permanent'),
    );
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

    // The route stops claiming a product is permanent the moment it can correct
    // one, because that sentence is what a mistyped price is read against.
    expect(
      _text(tester, 'catalog-management-scope'),
      contains('can be corrected afterwards'),
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

    expect(find.textContaining('Unit price: was 65.00, now 70.00'), findsOne);
    expect(
      find.textContaining('Sales already recorded keep the price'),
      findsOne,
    );
    await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
    await tester.pumpAndSettle();

    expect(callable.payloads.single, <String, Object?>{
      'tenantId': 'tenant-a',
      'productId': 'pd-1',
      'requestId': 'catalog-test-request-0000',
      'price': 70.0,
    });
    expect(
      _text(tester, 'catalog-management-notice'),
      startsWith('Corrected: unit price.'),
    );
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
    expect(find.byKey(const ValueKey('catalog-management-edit-price')), findsNothing);
    expect(find.byKey(const ValueKey('catalog-management-edit-cost')), findsNothing);
    expect(
      find.byKey(const ValueKey('catalog-management-edit-money-hidden')),
      findsOne,
    );
    await tester.enterText(
      find.byKey(const ValueKey('catalog-management-edit-name')),
      'Brown bread loaf',
    );
    await _review(tester);
    await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
    await tester.pumpAndSettle();

    expect(callable.payloads.single.containsKey('price'), isFalse);
    expect(callable.payloads.single['name'], 'Brown bread loaf');
  });

  testWidgets('clearing a recorded cost is its own act, and sends null', (
    tester,
  ) async {
    final callable = _Callable(
      answer: <String, Object?>{'changedFields': <String>['cost']},
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

    expect(
      find.textContaining('Unit cost: was 40.00, now not recorded'),
      findsOne,
    );
    expect(find.textContaining('never changes a profit already reported'), findsOne);
    await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
    await tester.pumpAndSettle();

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
    expect(find.byKey(const ValueKey('catalog-management-confirm')), findsNothing);
    expect(callable.payloads, isEmpty);
    expect(
      _text(tester, 'catalog-management-notice'),
      startsWith('Nothing on the form differs'),
    );
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
      _text(tester, 'catalog-management-notice'),
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

    expect(
      _text(tester, 'catalog-management-notice'),
      startsWith('The result is unknown.'),
    );
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
    final callable = _Callable(
      answer: <String, Object?>{'productId': 'pd-2'},
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
      _text(tester, 'catalog-management-notice'),
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
    await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
    await tester.pump();

    controller.open(uid: 'owner-a', membership: _membership('tenant-b'));
    await tester.pump();
    callable.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('catalog-management-notice')),
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
}) async {
  tester.view.physicalSize = const Size(1400, 3600);
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
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _openCorrection(WidgetTester tester, String productId) async {
  await tester.tap(find.byKey(ValueKey('catalog-management-edit-$productId')));
  await tester.pumpAndSettle();
}

Future<void> _review(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('catalog-management-edit-review')));
  await tester.pumpAndSettle();
}

/// Opens the correction form, changes one field, and confirms it.
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
  await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
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
  await tester.tap(
    find.byKey(const ValueKey('catalog-management-category-cat-bakery')),
  );
  await tester.pump();
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
  await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

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
  await tester.tap(find.byKey(const ValueKey('catalog-management-confirm')));
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
          for (final field in <String>['name', 'sku', 'price', 'cost',
            'categoryId'])
            if (payload.containsKey(field)) field,
        ],
        'name': payload['name'] ?? 'White bread loaf',
        'sku': payload['sku'] ?? '6161100000019',
        'price': payload['price'] ?? 65.0,
        'priceMinor': ((payload['price'] as double? ?? 65.0) * 100).round(),
        'categoryId': payload['categoryId'] ?? 'cat-bakery',
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
