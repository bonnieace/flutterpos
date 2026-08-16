import 'package:flutter/material.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('branding repository derives the exact path from its session', () async {
    final reader = _FakeReader(
      response: TenantDocumentSnapshot(
        path: 'tenants/tenant-a/configuration/branding',
        data: const {
          'companyName': 'ChillTent Westlands',
          'slogan': 'Stay chilled',
          'logoUrl': 'https://example.test/logo.png',
        },
      ),
    );
    final branding = await TenantBrandingRepository(
      session: TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.cashier,
      ),
      reader: reader,
    ).load();

    expect(reader.requestedPath, 'tenants/tenant-a/configuration/branding');
    expect(branding?.companyName, 'ChillTent Westlands');
    expect(branding?.slogan, 'Stay chilled');
    expect(branding?.logoUrl, Uri.parse('https://example.test/logo.png'));
  });

  test('a cross-tenant document response fails closed', () async {
    final repository = TenantBrandingRepository(
      session: TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.admin,
      ),
      reader: _FakeReader(
        response: TenantDocumentSnapshot(
          path: 'tenants/tenant-b/configuration/branding',
          data: const {'companyName': 'Wrong tenant'},
        ),
      ),
    );

    await expectLater(repository.load(), throwsA(isA<TenantScopeViolation>()));
  });

  /// **The panel stopped drawing the business's name in §11 step 5b**, and this
  /// asserts the absence rather than only the presence. The name is the home's
  /// *title* now, resolved once above the header, and §7's "title appears once"
  /// is the rule that made drawing it here a duplicate. A test that only checked
  /// the slogan would still pass if the name came back.
  testWidgets('branding slice states the slogan and the role, never the name', (
    tester,
  ) async {
    final membership = _membership('tenant-a');
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: membership);

    await tester.pumpWidget(
      MaterialApp(
        home: TenantSessionScope(
          controller: controller,
          child: Scaffold(
            body: TenantBrandingPanel(
              branding: const TenantBranding(
                companyName: 'Tenant A Bar',
                slogan: 'Cold drinks, warm welcome',
              ),
              role: membership.role,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Tenant A Bar'), findsNothing);
    expect(find.text('Cold drinks, warm welcome'), findsOneWidget);
    expect(find.text('Signed in as Administrator'), findsOneWidget);
  });

  /// A business that has published no branding still states its session.
  testWidgets('branding slice without a document still states the role', (
    tester,
  ) async {
    final membership = _membership('tenant-a');
    final controller = TenantSessionController()
      ..open(uid: 'user-a', membership: membership);

    await tester.pumpWidget(
      MaterialApp(
        home: TenantSessionScope(
          controller: controller,
          child: Scaffold(
            body: TenantBrandingPanel(branding: null, role: membership.role),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Signed in as Administrator'), findsOneWidget);
  });

  group('bounded collection filters', () {
    test('passes only simple field equality to the reader', () async {
      final reader = _FakeCollectionReader();

      await _FilteredRepository().page(reader, <String, Object?>{
        'staffId': 'user-a',
        'status': 'open',
      });

      expect(reader.query!.collectionPath, 'tenants/tenant-a/shifts');
      expect(reader.query!.equalityFilters, <String, Object?>{
        'staffId': 'user-a',
        'status': 'open',
      });
      expect(reader.query!.limit, 21);
    });

    test('refuses a filter that is not a bounded document field', () async {
      final reader = _FakeCollectionReader();
      final repository = _FilteredRepository();
      final refused = <String, Map<String, Object?>>{
        'nested-path': <String, Object?>{'shift.staffId': 'user-a'},
        'document-id': <String, Object?>{'__name__': 'shift-a'},
        'path-escape': <String, Object?>{'tenants/x': 'user-a'},
        'empty-value': <String, Object?>{'staffId': ''},
        'unbounded-value': <String, Object?>{'staffId': <String>['user-a']},
        'too-many': <String, Object?>{
          'a': 1,
          'b': 2,
          'c': 3,
          'd': 4,
          'e': 5,
        },
      };

      for (final entry in refused.entries) {
        await expectLater(
          repository.page(reader, entry.value),
          throwsArgumentError,
          reason: entry.key,
        );
      }
      expect(reader.query, isNull);
    });
  });

  group('product subcollection pages', () {
    test('derives the path from the session and the product', () async {
      final reader = _FakeCollectionReader();

      await _FilteredRepository().subcollectionPage(reader, 'product-1');

      expect(
        reader.query!.collectionPath,
        'tenants/tenant-a/products/product-1/stock_movements',
      );
      expect(reader.query!.descending, isFalse);
      expect(reader.query!.equalityFilters, isEmpty);
      expect(reader.query!.limit, 21);
    });

    test('a product ID that is not a document ID is refused', () async {
      final reader = _FakeCollectionReader();

      await expectLater(
        _FilteredRepository().subcollectionPage(reader, 'other/product'),
        throwsArgumentError,
      );
      expect(reader.query, isNull);
    });

    test('the exact-child and ordering proofs still apply', () async {
      final repository = _FilteredRepository();

      // A nested path is not an exact child of the subcollection.
      await expectLater(
        repository.subcollectionPage(
          _PathReader(<String>[
            'tenants/tenant-a/products/product-1/stock_movements/mv-1/extra/x',
          ]),
          'product-1',
        ),
        throwsA(isA<TenantScopeViolation>()),
      );
      // Another product's ledger is not this one's.
      await expectLater(
        repository.subcollectionPage(
          _PathReader(<String>[
            'tenants/tenant-a/products/product-2/stock_movements/mv-1',
          ]),
          'product-1',
        ),
        throwsA(isA<TenantScopeViolation>()),
      );
      // Out-of-order results fail closed exactly as a collection page does.
      await expectLater(
        repository.subcollectionPage(
          _PathReader(<String>[
            'tenants/tenant-a/products/product-1/stock_movements/mv-2',
            'tenants/tenant-a/products/product-1/stock_movements/mv-1',
          ]),
          'product-1',
        ),
        throwsA(isA<TenantScopeViolation>()),
      );
    });
  });

  group('product subcollection group pages', () {
    test('the tenant binding is attached, never supplied', () async {
      final reader = _FakeGroupReader();

      await _FilteredRepository().groupPage(reader);

      // A group query names no path at all, so the only thing that narrows it
      // to one business is this filter - and the matching Firestore rule
      // authorizes the page by exactly the same condition.
      expect(reader.query!.collectionId, 'stock_movements');
      expect(reader.query!.equalityFilters, <String, Object?>{
        'tenantId': 'tenant-a',
      });
      expect(reader.query!.limit, 21);
      expect(reader.query!.startAfterDocumentPath, isNull);

      await _FilteredRepository().groupPage(
        reader,
        filters: const <String, Object?>{'sourceType': 'sale'},
      );
      expect(reader.query!.equalityFilters, <String, Object?>{
        'tenantId': 'tenant-a',
        'sourceType': 'sale',
      });
    });

    test('a caller cannot restate or override the tenant binding', () async {
      final reader = _FakeGroupReader();

      await expectLater(
        _FilteredRepository().groupPage(
          reader,
          filters: const <String, Object?>{'tenantId': 'tenant-b'},
        ),
        throwsArgumentError,
      );
      // Even naming its own business is refused: the binding has exactly one
      // author, so there is no shape in which a caller supplies it.
      await expectLater(
        _FilteredRepository().groupPage(
          reader,
          filters: const <String, Object?>{'tenantId': 'tenant-a'},
        ),
        throwsArgumentError,
      );
      expect(reader.query, isNull);
    });

    test('the exact-child proof is extended, not bypassed', () async {
      final repository = _FilteredRepository();
      final refused = <String, String>{
        'another-business':
            'tenants/tenant-b/products/product-1/stock_movements/mv-1',
        'not-below-a-product': 'tenants/tenant-a/stock_movements/mv-1',
        'another-subcollection':
            'tenants/tenant-a/products/product-1/sales/mv-1',
        'nested-below-the-entry':
            'tenants/tenant-a/products/product-1/stock_movements/mv-1/x/y',
        'not-a-document-id':
            'tenants/tenant-a/products/product-1/stock_movements/.',
      };
      for (final entry in refused.entries) {
        await expectLater(
          repository.groupPage(_GroupPathReader(<String>[entry.value])),
          throwsA(isA<TenantScopeViolation>()),
          reason: entry.key,
        );
      }

      // A page spanning several products is exactly what this read exists for.
      final page = await repository.groupPage(
        _GroupPathReader(<String>[
          'tenants/tenant-a/products/product-1/stock_movements/mv-1',
          'tenants/tenant-a/products/product-2/stock_movements/mv-1',
        ]),
      );
      expect(page.items.length, 2);
    });

    test('ordering is compared segment by segment, as Firestore does', () async {
      final repository = _FilteredRepository();

      // `product-1` sorts before `product-1-b` by segment, while the joined
      // paths compare the other way round because `-` is below `/`. A plain
      // string comparison would reject this legitimate page.
      final page = await repository.groupPage(
        _GroupPathReader(<String>[
          'tenants/tenant-a/products/product-1/stock_movements/mv-1',
          'tenants/tenant-a/products/product-1-b/stock_movements/mv-1',
        ]),
      );
      expect(page.items.length, 2);

      await expectLater(
        repository.groupPage(
          _GroupPathReader(<String>[
            'tenants/tenant-a/products/product-2/stock_movements/mv-1',
            'tenants/tenant-a/products/product-1/stock_movements/mv-1',
          ]),
        ),
        throwsA(isA<TenantScopeViolation>()),
      );
      await expectLater(
        repository.groupPage(
          _GroupPathReader(<String>[
            'tenants/tenant-a/products/product-1/stock_movements/mv-1',
            'tenants/tenant-a/products/product-1/stock_movements/mv-1',
          ]),
        ),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('the cursor is a whole path and is proved before it is used', () async {
      final reader = _GroupPathReader(<String>[
        'tenants/tenant-a/products/product-1/stock_movements/mv-1',
        'tenants/tenant-a/products/product-2/stock_movements/mv-1',
      ]);

      final page = await _FilteredRepository().groupPage(reader, pageSize: 1);

      expect(page.hasMore, isTrue);
      expect(
        page.nextCursor,
        'tenants/tenant-a/products/product-1/stock_movements/mv-1',
      );

      await _FilteredRepository().groupPage(reader, cursor: page.nextCursor);
      expect(reader.query!.startAfterDocumentPath, page.nextCursor);

      for (final cursor in <String>[
        'mv-1',
        'tenants/tenant-b/products/product-1/stock_movements/mv-1',
        'tenants/tenant-a/products/product-1/sales/mv-1',
      ]) {
        await expectLater(
          _FilteredRepository().groupPage(reader, cursor: cursor),
          throwsArgumentError,
          reason: cursor,
        );
      }
    });

    test('the page-size bound is the same one every page carries', () async {
      final reader = _FakeGroupReader();

      await expectLater(
        _FilteredRepository().groupPage(reader, pageSize: 0),
        throwsRangeError,
      );
      await expectLater(
        _FilteredRepository().groupPage(reader, pageSize: 51),
        throwsRangeError,
      );
      expect(reader.query, isNull);
    });
  });

  group('document-ID ordering', () {
    test('a descending page carries the reversed order to the reader', () async {
      final reader = _OrderedReader(<String>['shift-c', 'shift-b', 'shift-a']);

      final page = await _FilteredRepository().page(
        reader,
        const <String, Object?>{'status': 'closed'},
        descending: true,
      );

      expect(reader.query!.descending, isTrue);
      expect(
        page.items.map((item) => item.path.split('/').last),
        <String>['shift-c', 'shift-b', 'shift-a'],
      );
      expect(page.descending, isTrue);
    });

    test('a page ordered the wrong way fails closed in both directions', () async {
      final ascendingResult = _OrderedReader(<String>['shift-a', 'shift-b']);
      final descendingResult = _OrderedReader(<String>['shift-b', 'shift-a']);
      final repository = _FilteredRepository();

      await expectLater(
        repository.page(
          ascendingResult,
          const <String, Object?>{'status': 'closed'},
          descending: true,
        ),
        throwsA(isA<TenantScopeViolation>()),
      );
      await expectLater(
        repository.page(descendingResult, const <String, Object?>{}),
        throwsA(isA<TenantScopeViolation>()),
      );
    });

    test('an unfiltered descending page is refused before it is issued', () async {
      final reader = _OrderedReader(<String>[]);

      // Firestore rejects a descending scan of a whole collection by key, so
      // the boundary refuses to build one at all.
      await expectLater(
        _FilteredRepository().page(
          reader,
          const <String, Object?>{},
          descending: true,
        ),
        throwsArgumentError,
      );
      expect(reader.query, isNull);

      await _FilteredRepository().page(reader, const <String, Object?>{
        'status': 'closed',
      }, descending: true);
      expect(reader.query!.descending, isTrue);
    });

    test('a repeated document ID fails closed in a descending page', () async {
      final reader = _OrderedReader(<String>['shift-b', 'shift-b']);

      await expectLater(
        _FilteredRepository().page(
          reader,
          const <String, Object?>{'status': 'closed'},
          descending: true,
        ),
        throwsA(isA<TenantScopeViolation>()),
      );
    });
  });
}

/// Exposes the guarded collection boundary so its filter contract can be
/// proved directly; production repositories choose their own filters.
final class _FilteredRepository extends TenantReadRepository {
  _FilteredRepository()
    : super(
        session: TenantSession.active(
          uid: 'user-a',
          tenantId: 'tenant-a',
          role: TenantRole.cashier,
        ),
        reader: _FakeReader(response: null),
      );

  Future<TenantDocumentPage> page(
    TenantCollectionReader reader,
    Map<String, Object?> filters, {
    bool descending = false,
  }) => readCollectionPage(
    TenantCollection.shifts,
    collectionReader: reader,
    equalityFilters: filters,
    descending: descending,
  );

  Future<TenantDocumentPage> subcollectionPage(
    TenantCollectionReader reader,
    String productId,
  ) => readProductSubcollectionPage(
    TenantProductSubcollection.stockMovements,
    productId: productId,
    collectionReader: reader,
  );

  Future<TenantDocumentGroupPage> groupPage(
    TenantCollectionGroupReader reader, {
    int pageSize = 20,
    String? cursor,
    Map<String, Object?> filters = const <String, Object?>{},
  }) => readProductSubcollectionGroupPage(
    TenantProductSubcollection.stockMovements,
    groupReader: reader,
    pageSize: pageSize,
    cursor: cursor,
    equalityFilters: filters,
  );
}

/// Returns exactly the group paths it was given, so the extended exact-child
/// and path-ordering proofs can be exercised with results no real reader could
/// be trusted to avoid.
final class _GroupPathReader implements TenantCollectionGroupReader {
  _GroupPathReader(this._paths);

  final List<String> _paths;
  TenantCollectionGroupQuery? query;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionGroupPage(
    TenantCollectionGroupQuery request,
  ) async {
    query = request;
    return <TenantQueryDocumentSnapshot>[
      for (final path in _paths.take(request.limit))
        TenantQueryDocumentSnapshot(path: path, data: const <String, Object?>{}),
    ];
  }
}

final class _FakeGroupReader implements TenantCollectionGroupReader {
  TenantCollectionGroupQuery? query;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionGroupPage(
    TenantCollectionGroupQuery request,
  ) async {
    query = request;
    return const <TenantQueryDocumentSnapshot>[];
  }
}

/// Returns exactly the document paths it was given, so the exact-child proof
/// can be exercised with paths a real reader could never be trusted to avoid.
final class _PathReader implements TenantCollectionReader {
  _PathReader(this._paths);

  final List<String> _paths;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery request,
  ) async => <TenantQueryDocumentSnapshot>[
    for (final path in _paths)
      TenantQueryDocumentSnapshot(path: path, data: const <String, Object?>{}),
  ];
}

/// Returns exactly the document IDs it was given, in that order, so the
/// repository's ordering and uniqueness proofs can be exercised directly.
final class _OrderedReader implements TenantCollectionReader {
  _OrderedReader(this._documentIds);

  final List<String> _documentIds;
  TenantCollectionQuery? query;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery request,
  ) async {
    query = request;
    return <TenantQueryDocumentSnapshot>[
      for (final id in _documentIds)
        TenantQueryDocumentSnapshot(
          path: '${request.collectionPath}/$id',
          data: const <String, Object?>{},
        ),
    ];
  }
}

final class _FakeCollectionReader implements TenantCollectionReader {
  TenantCollectionQuery? query;

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery request,
  ) async {
    query = request;
    return const <TenantQueryDocumentSnapshot>[];
  }
}

final class _FakeReader implements TenantDocumentReader {
  _FakeReader({required this.response});

  final TenantDocumentSnapshot? response;
  String? requestedPath;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    requestedPath = path;
    return response;
  }
}

TenantMembership _membership(String tenantId) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: TenantRole.admin,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 7, 29),
  updatedAt: DateTime.utc(2026, 7, 29),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);
