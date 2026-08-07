import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

Future<void> _pump(
  WidgetTester tester,
  TenantSessionController controller,
  _Reader reader, {
  TenantCatalogWriter? writer,
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

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).onPressed !=
    null;

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

/// A collection reader keyed per business and per collection, answering in
/// ascending document-ID order and honouring the exact page bound and cursor
/// the guarded repository asked for.
final class _Reader implements TenantDataReader {
  _Reader(this._collections) : _fails = false;

  _Reader.empty() : this(const <String, Map<String, Map<String, Object?>>>{});

  _Reader.failing()
    : _collections = const <String, Map<String, Map<String, Object?>>>{},
      _fails = true;

  factory _Reader.seeded({int productCount = 2}) =>
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
