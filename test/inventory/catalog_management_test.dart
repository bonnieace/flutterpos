import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/checkout/checkout_draft.dart';
import 'package:flutter_application_1/inventory/catalog_management.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _productsPath = 'tenants/tenant-a/products';
const String _categoriesPath = 'tenants/tenant-a/categories';
const String _requestId = 'catalog-fixed-request-000001';

void main() {
  group('category intent', () {
    test('writes only the name the read model needs, and its provenance', () {
      final intent = _categoryIntent(name: 'Bakery');

      expect(intent.tenantId, 'tenant-a');
      expect(intent.path, '$_categoriesPath/${intent.categoryId}');
      // `createdAt` is deliberately absent: the writer adds a server timestamp,
      // so a device clock never decides when a business added a category.
      expect(intent.documentData(), <String, Object?>{
        'name': 'Bakery',
        'createdBy': 'user-a',
      });
    });

    test('the document it writes is one the strict read model accepts', () {
      final intent = _categoryIntent(name: 'Bakery');

      final decoded = TenantCategory.fromSnapshot(
        TenantQueryDocumentSnapshot(
          path: intent.path,
          data: <String, Object?>{...intent.documentData(), 'createdAt': 1},
        ),
      );

      expect(decoded.id, intent.categoryId);
      expect(decoded.name, 'Bakery');
    });

    test('a name is normalized into the shape the read model demands', () {
      // `_requiredTrimmedString` refuses a value that is not equal to its own
      // trim, so a stray space would otherwise write a category no device could
      // read - and the cache reports the whole snapshot as a miss.
      expect(_categoryIntent(name: '  Cold  drinks \n').name, 'Cold drinks');
    });

    test('an empty or over-long name is refused', () {
      expect(
        () => _categoryIntent(name: '   '),
        _code('invalid_category_name'),
      );
      expect(
        () => _categoryIntent(name: 'x' * (maximumCatalogNameLength + 1)),
        _code('invalid_category_name'),
      );
      expect(
        () => _categoryIntent(name: 'Colddrinks'),
        _code('invalid_category_name'),
      );
    });
  });

  group('product intent', () {
    test('writes exactly the key set the strict read model demands', () {
      final intent = _productIntent(price: '19.99');

      expect(intent.path, '$_productsPath/${intent.productId}');
      expect(intent.documentData(), <String, Object?>{
        'name': 'White bread loaf',
        'SKU': '6161100000019',
        'price': 19.99,
        'quantity': 0,
        'categoryId': 'cat-bakery',
        'createdBy': 'user-a',
      });
    });

    test('the document it writes decodes back through TenantProduct', () {
      // The rule on `products` checks only `quantity is int`, so this boundary
      // is the only thing standing between a typed form and a product the till
      // cannot parse - and one of those makes the whole cached catalog a miss.
      final intent = _productIntent(price: '19.99');

      final decoded = TenantProduct.fromDocument(
        path: intent.path,
        data: <String, Object?>{...intent.documentData(), 'createdAt': 1},
      );

      expect(decoded.id, intent.productId);
      expect(decoded.tenantId, 'tenant-a');
      expect(decoded.name, 'White bread loaf');
      expect(decoded.sku, '6161100000019');
      expect(decoded.price, 19.99);
      expect(decoded.quantity, 0);
      expect(decoded.categoryId, 'cat-bakery');
      expect(decoded.imageUrl, isNull);
    });

    test('a product is always created holding nothing', () {
      // Stock that appears without a `stock_movements` entry has no recorded
      // origin. `adjustStock` carries `opening_balance` for exactly this, so the
      // create never names a quantity of its own.
      expect(catalogOpeningQuantity, 0);
      expect(_productIntent(price: '1').documentData()['quantity'], 0);
    });

    test('the category is taken from the ones this surface offered', () {
      final intent = _productIntent(price: '1', categoryId: 'cat-drinks');

      expect(intent.categoryId, 'cat-drinks');
      // Carried for the confirmation only; a product names its category by ID.
      expect(intent.categoryName, 'Drinks');
      expect(intent.documentData().containsKey('categoryName'), isFalse);
    });

    test('a category this surface did not offer is refused', () {
      expect(
        () => _productIntent(price: '1', categoryId: 'cat-household'),
        _code('unknown_category'),
      );
      expect(
        () => _productIntent(price: '1', categoryId: ''),
        _code('unknown_category'),
      );
    });
  });

  group('price', () {
    test('a plain amount converts to exact minor units', () {
      for (final entry in <String, int>{
        '0': 0,
        '65': 6500,
        '19.99': 1999,
        '19.9': 1990,
        ' 20.05 ': 2005,
        '1000000': 100000000,
      }.entries) {
        expect(
          _productIntent(price: entry.key).priceMinor,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('the stored major-unit price round-trips to the same minor units', () {
      // The till re-derives minor units from the stored figure with the same
      // function, so the two can never disagree about what a line costs.
      for (final price in <String>['0.01', '19.99', '65', '999.95']) {
        final intent = _productIntent(price: price);
        expect(
          checkoutMinorUnitsFromMajor(
            intent.documentData()['price']! as double,
          ),
          intent.priceMinor,
          reason: price,
        );
      }
    });

    test('anything that is not a two-place decimal amount is refused', () {
      // Two places is all `unitPriceMinor` holds, so a third is refused where it
      // is typed rather than rounded into a figure the catalog never showed.
      for (final price in <String>[
        '',
        '  ',
        'free',
        '-5',
        '1.005',
        '1,50',
        '1e3',
        '0x10',
        '.5',
        '1.',
        '+1',
      ]) {
        expect(
          () => _productIntent(price: price),
          _code('invalid_price'),
          reason: price,
        );
      }
    });

    test('an amount larger than a sale can record is refused here', () {
      // The till refuses this line as `price_not_representable` with a customer
      // standing there. This is the same refusal, moved to where it is typed.
      expect(
        () => _productIntent(price: '999999999999'),
        _code('price_not_representable'),
      );
    });
  });

  group('code', () {
    test('a code is trimmed and bounded', () {
      expect(_productIntent(price: '1', sku: '  ABC-1  ').sku, 'ABC-1');
      expect(
        _productIntent(price: '1', sku: 'x' * maximumCatalogSkuLength).sku,
        'x' * maximumCatalogSkuLength,
      );
    });

    test('an empty, over-long, or spaced code is refused', () {
      // A scanner cannot emit a space, and an exact match against the scanned
      // code is the only job the field has.
      for (final sku in <String>[
        '',
        '   ',
        'ABC 1',
        'ABC\t1',
        // A literal no-break space, which a paste from a spreadsheet produces
        // and `trim` leaves alone in the middle of a value.
        'ABC 1',
      ]) {
        expect(
          () => _productIntent(price: '1', sku: sku),
          _code('invalid_sku'),
          reason: sku,
        );
      }
      expect(
        () => _productIntent(
          price: '1',
          sku: 'x' * (maximumCatalogSkuLength + 1),
        ),
        _code('invalid_sku'),
      );
    });
  });

  group('document identity', () {
    test('one request ID always addresses one document', () {
      // A retry after an unknown outcome must reach the same product, not a
      // second one on the shelf.
      expect(
        _productIntent(price: '1').productId,
        _productIntent(price: '1').productId,
      );
      expect(
        _categoryIntent(name: 'Bakery').categoryId,
        _categoryIntent(name: 'Bakery').categoryId,
      );
    });

    test('the identity is not derived from anything correctable', () {
      // A different name, code, price, or category is still the same intent
      // being retried. The ID is permanent and the ledger hangs below it, so it
      // is scoped by the request rather than by a field nothing can fix later.
      final first = _productIntent(price: '19.99');
      final second = _productIntent(
        price: '1',
        name: 'Something else',
        sku: 'OTHER',
        categoryId: 'cat-drinks',
      );

      expect(first.productId, second.productId);
    });

    test('a product and a category never collide', () {
      expect(
        _productIntent(price: '1').productId,
        isNot(_categoryIntent(name: 'Bakery').categoryId),
      );
    });

    test('a different request, business, or actor is a different document', () {
      final base = _productIntent(price: '1').productId;

      expect(
        _productIntent(
          price: '1',
          requestId: 'catalog-other-request-1',
        ).productId,
        isNot(base),
      );
      expect(
        _productIntent(price: '1', tenantId: 'tenant-b').productId,
        isNot(base),
      );
      expect(_productIntent(price: '1', uid: 'user-b').productId, isNot(base));
    });

    test('an unusable request ID is a refusal, never a guessed document', () {
      for (final requestId in <String>['', 'short', 'has space 12345']) {
        expect(
          () => _productIntent(price: '1', requestId: requestId),
          _code('invalid_catalog_request_id'),
          reason: requestId,
        );
        expect(
          () => _categoryIntent(name: 'Bakery', requestId: requestId),
          _code('invalid_catalog_request_id'),
          reason: requestId,
        );
      }
    });

    test(
      'the generated request ID satisfies the boundary that consumes it',
      () {
        final generated = secureTenantCatalogRequestId();

        expect(
          _productIntent(price: '1', requestId: generated).productId,
          isNotEmpty,
        );
        expect(secureTenantCatalogRequestId(), isNot(generated));
      },
    );
  });

  group('roles', () {
    test('an owner, administrator, or manager stocks the catalog', () {
      for (final role in <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
        TenantRole.manager,
      ]) {
        expect(_productIntent(price: '1', role: role).sku, isNotEmpty);
        expect(_categoryIntent(name: 'Bakery', role: role).name, 'Bakery');
      }
    });

    test('a cashier changes nothing', () {
      expect(
        () => _productIntent(price: '1', role: TenantRole.cashier),
        _code('catalog_forbidden'),
      );
      expect(
        () => _categoryIntent(name: 'Bakery', role: TenantRole.cashier),
        _code('catalog_forbidden'),
      );
    });

    test('only an owner or administrator retires a product', () {
      for (final role in <TenantRole>[TenantRole.owner, TenantRole.admin]) {
        expect(_retireIntent(role: role).productId, 'prod-bread');
      }
      // A manager may stock the shelf and may not empty it: retiring removes
      // the only thing that can sell the product, and `allow delete` agrees.
      for (final role in <TenantRole>[TenantRole.manager, TenantRole.cashier]) {
        expect(() => _retireIntent(role: role), _code('retire_forbidden'));
        expect(
          TenantCatalogManagementRepository.canRetireInSession(
            _session(role: role),
          ),
          isFalse,
          reason: role.name,
        );
      }
    });
  });

  group('what the business paid', () {
    test('is optional, and blank means never recorded', () {
      // A business that does not track cost still has to be able to add a
      // product, and an invented cost - zero, or the price - would be a
      // fabricated margin reported as fact.
      final blank = _productIntent(price: '65');

      expect(blank.costMinor, isNull);
      expect(blank.cost, isNull);
      expect(blank.documentData().containsKey('cost'), isFalse);
    });

    test('is stored as the till converts it back, exactly like a price', () {
      final intent = _productIntent(price: '65', cost: '40.50');

      expect(intent.costMinor, 4050);
      expect(intent.cost, 40.5);
      expect(intent.documentData()['cost'], 40.5);
      // The stored figure is derived from the minor units rather than from what
      // was typed, so what the till converts back is exactly what was meant.
      expect(checkoutMinorUnitsFromMajor(intent.cost!), intent.costMinor);
    });

    test('is refused where it is typed if the till could not record it', () {
      for (final entry in <String, String>{
        'nonsense': 'invalid_cost',
        '40.505': 'invalid_cost',
        '-1': 'invalid_cost',
        // Twelve digits passes the format check and then fails the till's own
        // conversion, which is the only way to reach the second refusal.
        '999999999999': 'cost_not_representable',
      }.entries) {
        expect(
          () => _productIntent(price: '65', cost: entry.key),
          throwsA(
            isA<TenantCatalogManagementException>().having(
              (error) => error.code,
              'code for "${entry.key}"',
              entry.value,
            ),
          ),
        );
      }
    });

    test('needs an owner or an administrator, unlike the product itself', () {
      // Adding a product is owner/admin/manager. Stating the margin is not.
      for (final role in <TenantRole>[TenantRole.owner, TenantRole.admin]) {
        expect(
          _productIntent(price: '65', cost: '40', role: role).costMinor,
          4000,
          reason: role.name,
        );
        expect(
          TenantCatalogManagementRepository.canRecordCostInSession(
            _session(role: role),
          ),
          isTrue,
          reason: role.name,
        );
      }

      // Refused rather than dropped: a manager must never be told a cost was
      // recorded when it was silently discarded.
      expect(
        () => _productIntent(price: '65', cost: '40', role: TenantRole.manager),
        throwsA(
          isA<TenantCatalogManagementException>().having(
            (error) => error.code,
            'code',
            'cost_forbidden',
          ),
        ),
      );
      expect(
        TenantCatalogManagementRepository.canRecordCostInSession(
          _session(role: TenantRole.manager),
        ),
        isFalse,
      );

      // A manager may still add the product, just without the margin.
      expect(
        _productIntent(price: '65', role: TenantRole.manager).costMinor,
        isNull,
      );
    });
  });

  group('retire intent', () {
    test('names the product and what it was still holding', () {
      final intent = _retireIntent();

      expect(intent.path, '$_productsPath/prod-bread');
      expect(intent.tenantId, 'tenant-a');
      expect(intent.name, 'White bread loaf');
      expect(intent.sku, '6161100000019');
      // Retiring moves this nowhere and records no movement for it, which is
      // exactly why the confirmation has to state it.
      expect(intent.quantity, 40);
    });

    test('a product decoded in another business is never retired here', () {
      expect(
        () => _retireIntent(productTenantId: 'tenant-b'),
        _code('retire_forbidden'),
      );
    });
  });

  group('catalog writer', () {
    test('a create writes the named keys and a server timestamp', () async {
      final writer = _RecordingWriter();

      final intent = _productIntent(price: '19.99');
      final result = await writer.build().createProduct(intent);

      expect(result.kind, TenantCatalogWriteKind.committed);
      expect(writer.created.single.path, intent.path);
      expect(writer.created.single.data.keys, <String>[
        'name',
        'SKU',
        'price',
        'quantity',
        'categoryId',
        'createdBy',
        'createdAt',
      ]);
      expect(writer.created.single.data['createdAt'], isA<FieldValue>());
      expect(writer.removed, isEmpty);
    });

    test('a category create writes its own path', () async {
      final writer = _RecordingWriter();

      final intent = _categoryIntent(name: 'Bakery');
      final result = await writer.build().createCategory(intent);

      expect(result.kind, TenantCatalogWriteKind.committed);
      expect(writer.created.single.path, intent.path);
      expect(writer.created.single.data['name'], 'Bakery');
    });

    test('a retire deletes the product document and writes nothing', () async {
      final writer = _RecordingWriter();

      final result = await writer.build().retireProduct(_retireIntent());

      expect(result.kind, TenantCatalogWriteKind.committed);
      expect(writer.removed.single, '$_productsPath/prod-bread');
      expect(writer.created, isEmpty);
    });

    test('an offline device attempts nothing at all', () async {
      final writer = _RecordingWriter();

      expect(
        (await writer
                .build(online: false)
                .createProduct(_productIntent(price: '1')))
            .kind,
        TenantCatalogWriteKind.unavailable,
      );
      expect(
        (await writer.build(online: false).retireProduct(_retireIntent())).kind,
        TenantCatalogWriteKind.unavailable,
      );
      expect(writer.created, isEmpty);
      expect(writer.removed, isEmpty);
    });

    test('a failing connectivity check counts as offline', () async {
      final writer = _RecordingWriter();

      final result = await writer
          .build(onlineCheck: () => Future<bool>.error(StateError('no radio')))
          .createProduct(_productIntent(price: '1'));

      expect(result.kind, TenantCatalogWriteKind.unavailable);
      expect(writer.created, isEmpty);
    });

    test('a refusal the server proved is rejected, not retried', () async {
      for (final code in <String>[
        'permission-denied',
        'unauthenticated',
        'invalid-argument',
        'not-found',
        'already-exists',
        'failed-precondition',
      ]) {
        final result = await _RecordingWriter()
            .build(
              error: FirebaseException(plugin: 'firestore', code: code),
            )
            .createProduct(_productIntent(price: '1'));

        expect(result.kind, TenantCatalogWriteKind.rejected, reason: code);
        expect(result.reasonCode, code);
      }
    });

    test('an unproven outcome is ambiguous, never rejected', () async {
      final unavailable = await _RecordingWriter()
          .build(
            error: FirebaseException(plugin: 'firestore', code: 'unavailable'),
          )
          .retireProduct(_retireIntent());
      expect(unavailable.kind, TenantCatalogWriteKind.ambiguous);
      expect(unavailable.reasonCode, 'unavailable');

      final unknown = await _RecordingWriter()
          .build(error: StateError('transport closed'))
          .createCategory(_categoryIntent(name: 'Bakery'));
      expect(unknown.kind, TenantCatalogWriteKind.ambiguous);
      expect(unknown.reasonCode, 'unknown_error');
    });

    test('a write that never answers is ambiguous', () async {
      final writer = FirebaseTenantCatalogWriter.forTesting(
        create: (_, _) => Completer<void>().future,
        remove: (_) => Completer<void>().future,
        isOnline: () async => true,
        writeTimeout: const Duration(milliseconds: 20),
      );

      expect(
        (await writer.createProduct(_productIntent(price: '1'))).reasonCode,
        'write_timeout',
      );
      expect(
        (await writer.retireProduct(_retireIntent())).kind,
        TenantCatalogWriteKind.ambiguous,
      );
    });

    test(
      'every write path is re-derived from the intent\'s own business',
      () async {
        // The writer never trusts the path it was handed. Only the repository can
        // build an intent and it takes both from one session, so the two can only
        // ever agree - which is what this proves for a second business.
        final writer = _RecordingWriter();

        await writer.build().createProduct(
          _productIntent(price: '1', tenantId: 'tenant-b'),
        );

        expect(writer.created.single.path, startsWith('tenants/tenant-b/'));
      },
    );

    test('a non-positive write timeout is a programming error', () {
      expect(
        () => FirebaseTenantCatalogWriter.forTesting(
          create: (_, _) async {},
          remove: (_) async {},
          isOnline: () async => true,
          writeTimeout: Duration.zero,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

TenantSession _session({
  TenantRole role = TenantRole.owner,
  String tenantId = 'tenant-a',
  String uid = 'user-a',
}) => TenantSession.active(uid: uid, tenantId: tenantId, role: role);

TenantCatalogManagementRepository _repository({
  TenantRole role = TenantRole.owner,
  String tenantId = 'tenant-a',
  String uid = 'user-a',
}) => TenantCatalogManagementRepository(
  session: _session(role: role, tenantId: tenantId, uid: uid),
  reader: const _Reader(),
);

/// The categories this surface actually read and offered.
List<TenantCategory> _categories(String tenantId) => <TenantCategory>[
  for (final entry in <String, String>{
    'cat-bakery': 'Bakery',
    'cat-drinks': 'Drinks',
  }.entries)
    TenantCategory.fromSnapshot(
      TenantQueryDocumentSnapshot(
        path: 'tenants/$tenantId/categories/${entry.key}',
        data: <String, Object?>{'name': entry.value},
      ),
    ),
];

TenantCategoryCreateIntent _categoryIntent({
  required String name,
  TenantRole role = TenantRole.owner,
  String requestId = _requestId,
}) => _repository(
  role: role,
).buildCategoryIntent(name: name, requestId: requestId);

TenantProductCreateIntent _productIntent({
  required String price,
  String name = 'White bread loaf',
  String sku = '6161100000019',
  String categoryId = 'cat-bakery',
  String cost = '',
  TenantRole role = TenantRole.owner,
  String tenantId = 'tenant-a',
  String uid = 'user-a',
  String requestId = _requestId,
}) => _repository(role: role, tenantId: tenantId, uid: uid).buildProductIntent(
  name: name,
  sku: sku,
  price: price,
  cost: cost,
  categoryId: categoryId,
  categories: _categories(tenantId),
  requestId: requestId,
);

TenantProductRetireIntent _retireIntent({
  TenantRole role = TenantRole.owner,
  String productTenantId = 'tenant-a',
}) => _repository(role: role).buildRetireIntent(
  TenantProduct.fromDocument(
    path: 'tenants/$productTenantId/products/prod-bread',
    data: <String, Object?>{
      'name': 'White bread loaf',
      'SKU': '6161100000019',
      'price': 65,
      'quantity': 40,
      'categoryId': 'cat-bakery',
    },
  ),
);

Matcher _code(String code) => throwsA(
  isA<TenantCatalogManagementException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

final class _WrittenDocument {
  const _WrittenDocument(this.path, this.data);

  final String path;
  final Map<String, Object?> data;
}

final class _RecordingWriter {
  final List<_WrittenDocument> created = <_WrittenDocument>[];
  final List<String> removed = <String>[];

  FirebaseTenantCatalogWriter build({
    bool online = true,
    Object? error,
    Future<bool> Function()? onlineCheck,
  }) => FirebaseTenantCatalogWriter.forTesting(
    create: (path, data) {
      created.add(_WrittenDocument(path, data));
      return error == null ? Future<void>.value() : Future<void>.error(error);
    },
    remove: (path) {
      removed.add(path);
      return error == null ? Future<void>.value() : Future<void>.error(error);
    },
    isOnline: onlineCheck ?? () async => online,
  );
}

final class _Reader implements TenantDocumentReader {
  const _Reader();

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async => null;
}
