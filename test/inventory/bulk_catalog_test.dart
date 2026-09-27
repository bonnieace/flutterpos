import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sheet the tests reuse: three products, a header naming every column this
/// import reads by its own name.
const String _sheet =
    'name,sku,price,cost,quantity,category\n'
    'White bread loaf,6161100000019,65,40,12,Bakery\n'
    'Brown bread loaf,6161100000026,70,45,,Bakery\n'
    'Cold soda,6161100000033,50,,3,Drinks\n';

void main() {
  group('bulk correction plan', () {
    test('one page carries one request ID and one field per row', () {
      final plan = _batchPlan(
        products: <TenantProduct>[_product('pd-1'), _product('pd-2')],
        edit: const TenantBulkCatalogEdit.category('cat-drinks'),
      );

      expect(plan.pages, hasLength(1));
      expect(plan.rowCount, 2);
      expect(plan.valueLabel, 'Drinks');
      expect(plan.pages.single.payload(TenantBulkCatalogMode.preview), {
        'tenantId': 'tenant-a',
        'mode': 'preview',
        'requestId': 'catalog-1',
        'rows': <Map<String, Object?>>[
          <String, Object?>{'productId': 'pd-1', 'categoryId': 'cat-drinks'},
          <String, Object?>{'productId': 'pd-2', 'categoryId': 'cat-drinks'},
        ],
      });
    });

    test('a preview and its commit are the same rows under one request ID', () {
      // The whole reason the server writes no idempotency record for a preview.
      // Order is part of the request fingerprint, so a commit whose rows moved
      // would be refused as `already-exists` rather than applied.
      final page = _batchPlan(
        products: <TenantProduct>[_product('pd-1'), _product('pd-2')],
        edit: const TenantBulkCatalogEdit.price('19.99'),
      ).pages.single;

      final preview = page.payload(TenantBulkCatalogMode.preview);
      final commit = page.payload(TenantBulkCatalogMode.commit);

      expect(commit['requestId'], preview['requestId']);
      expect(commit['rows'], preview['rows']);
      expect(commit['mode'], 'commit');
      expect((preview['rows']! as List).first, <String, Object?>{
        'productId': 'pd-1',
        // Derived from the minor units rather than from what was typed.
        'price': 19.99,
      });
    });

    test('rows past fifty become further requests, in order', () {
      final plan = _batchPlan(
        products: <TenantProduct>[
          for (var index = 1; index <= 120; index++) _product('pd-$index'),
        ],
        edit: const TenantBulkCatalogEdit.category('cat-drinks'),
      );

      expect(plan.pages.map((page) => page.rows.length), <int>[50, 50, 20]);
      expect(plan.pages.map((page) => page.requestId).toSet(), hasLength(3));
      expect(plan.pages.map((page) => page.number), <int>[1, 2, 3]);
      expect(plan.pages.every((page) => page.pageCount == 3), isTrue);
      // The server indexes an outcome inside its own page; a person recognises
      // the position in their own selection. Both are carried, because a report
      // that confused them would name the wrong product.
      expect(plan.pages[1].rows.first.index, 0);
      expect(plan.pages[1].rows.first.position, 51);
      expect(plan.pages[2].rows.last.index, 19);
      expect(plan.pages[2].rows.last.position, 120);
    });

    test('a price is proved through the till\'s own arithmetic', () {
      for (final price in <String>['19.999', '1e3', '-5', '', '0x10']) {
        expect(
          () => _batchPlan(
            products: <TenantProduct>[_product('pd-1')],
            edit: TenantBulkCatalogEdit.price(price),
          ),
          throwsA(isA<TenantBulkCatalogException>()),
          reason: price,
        );
      }
    });

    test('money needs an owner or administrator, a category does not', () {
      for (final edit in <TenantBulkCatalogEdit>[
        const TenantBulkCatalogEdit.price('19.99'),
        const TenantBulkCatalogEdit.cost('9.99'),
        const TenantBulkCatalogEdit.clearCost(),
      ]) {
        expect(
          () => _batchPlan(
            products: <TenantProduct>[_product('pd-1')],
            edit: edit,
            role: TenantRole.manager,
          ),
          throwsA(
            isA<TenantBulkCatalogException>().having(
              (error) => error.code,
              'code',
              anyOf('price_forbidden', 'cost_forbidden'),
            ),
          ),
        );
      }
      expect(
        _batchPlan(
          products: <TenantProduct>[_product('pd-1')],
          edit: const TenantBulkCatalogEdit.category('cat-drinks'),
          role: TenantRole.manager,
        ).rowCount,
        1,
      );
    });

    test('a cashier plans nothing at all', () {
      expect(
        () => _batchPlan(
          products: <TenantProduct>[_product('pd-1')],
          edit: const TenantBulkCatalogEdit.category('cat-drinks'),
          role: TenantRole.cashier,
        ),
        throwsA(
          isA<TenantBulkCatalogException>().having(
            (error) => error.code,
            'code',
            'catalog_forbidden',
          ),
        ),
      );
    });

    test('a product named twice is refused, as the server refuses it', () {
      // Two rows for one document are two conflicting intents, and the second
      // would be planned against a document the first already changed - so
      // neither has an honest outcome to report.
      expect(
        () => _batchPlan(
          products: <TenantProduct>[_product('pd-1'), _product('pd-1')],
          edit: const TenantBulkCatalogEdit.category('cat-drinks'),
        ),
        throwsA(
          isA<TenantBulkCatalogException>().having(
            (error) => error.code,
            'code',
            'product_named_twice',
          ),
        ),
      );
    });

    test('an empty selection and another business are both refused', () {
      expect(
        () => _batchPlan(
          products: const <TenantProduct>[],
          edit: const TenantBulkCatalogEdit.category('cat-drinks'),
        ),
        throwsA(
          isA<TenantBulkCatalogException>().having(
            (error) => error.code,
            'code',
            'no_products_selected',
          ),
        ),
      );
      expect(
        () => _batchPlan(
          products: <TenantProduct>[_product('pd-1', tenantId: 'tenant-b')],
          edit: const TenantBulkCatalogEdit.category('cat-drinks'),
        ),
        throwsA(
          isA<TenantBulkCatalogException>().having(
            (error) => error.code,
            'code',
            'edit_forbidden',
          ),
        ),
      );
    });

    test('a category this surface did not offer is refused', () {
      expect(
        () => _batchPlan(
          products: <TenantProduct>[_product('pd-1')],
          edit: const TenantBulkCatalogEdit.category('cat-unseen'),
        ),
        throwsA(
          isA<TenantBulkCatalogException>().having(
            (error) => error.code,
            'code',
            'unknown_category',
          ),
        ),
      );
    });

    test('clearing a cost is an explicit null on every row', () {
      final plan = _batchPlan(
        products: <TenantProduct>[_product('pd-1')],
        edit: const TenantBulkCatalogEdit.clearCost(),
      );

      expect(plan.clearsCost, isTrue);
      expect(plan.valueLabel, 'not recorded');
      expect((plan.pages.single.payload(TenantBulkCatalogMode.commit)['rows']!
              as List)
          .single, <String, Object?>{'productId': 'pd-1', 'cost': null});
    });

    test('each row states what the field being changed held', () {
      final byCategory = _batchPlan(
        products: <TenantProduct>[
          _product('pd-1'),
          _product('pd-2', categoryId: 'cat-unseen'),
        ],
        edit: const TenantBulkCatalogEdit.category('cat-drinks'),
      ).pages.single;
      // A product filed off this page has no name here, and its document ID is
      // not one: the report says so in the words every catalog surface uses.
      expect(byCategory.rows.map((row) => row.previous), <String>[
        'Bakery',
        unlistedTenantCategoryLabel,
      ]);
      expect(
        byCategory.rows.map((row) => row.previous),
        isNot(contains(contains('cat-unseen'))),
      );

      final byCost = _batchPlan(
        products: <TenantProduct>[_product('pd-1'), _product('pd-2', cost: null)],
        edit: const TenantBulkCatalogEdit.cost('9.99'),
      ).pages.single;
      expect(byCost.rows.map((row) => row.previous), <String>[
        '40',
        'not recorded',
      ]);
    });
  });

  group('import sheet', () {
    test('a comma sheet becomes rows in the shape the server reads', () {
      final plan = _importPlan(_sheet);

      expect(plan.refused, isEmpty);
      expect(plan.lineCount, 3);
      expect(plan.rowCount, 3);
      final rows = plan.pages.single.payload(TenantBulkCatalogMode.preview)['rows']!
          as List;
      expect(rows.first, <String, Object?>{
        'name': 'White bread loaf',
        'sku': '6161100000019',
        'price': 65.0,
        'cost': 40.0,
        'quantity': 12,
        // A name, never `category`: a stored product's `category` is the legacy
        // alias for `categoryId` and holds an ID.
        'categoryName': 'Bakery',
      });
      // A row opening holding nothing names no quantity, and a row with no cost
      // names no cost - the server treats an absent cost as "not recorded".
      expect(rows[1], <String, Object?>{
        'name': 'Brown bread loaf',
        'sku': '6161100000026',
        'price': 70.0,
        'cost': 45.0,
        'categoryName': 'Bakery',
      });
      expect((rows[2] as Map).containsKey('cost'), isFalse);
    });

    test('tabs, semicolons, and quoted cells are all read', () {
      expect(
        _importPlan('name\tsku\tprice\tcategory\nMandazi\tM-1\t20\tBakery')
            .pages
            .single
            .rows
            .single
            .name,
        'Mandazi',
      );
      expect(
        _importPlan('name;sku;price;category\nMandazi;M-1;20;Bakery')
            .pages
            .single
            .rows
            .single
            .priceMinor,
        2000,
      );
      // Without quoting this row would silently become five cells and shift
      // every column after it - a wrong import that looks like a valid one.
      final quoted = _importPlan(
        'name,sku,price,category\n'
        '"Bread, sliced",B-1,65,"Bakery, fresh"\n'
        '"He said ""hi""",B-2,10,Bakery',
      ).pages.single.rows;
      expect(quoted.first.name, 'Bread, sliced');
      expect(quoted.first.categoryName, 'Bakery, fresh');
      expect(quoted[1].name, 'He said "hi"');
    });

    test('a defect in the header refuses the whole sheet', () {
      for (final entry in <String, String>{
        '': 'sheet_empty',
        '   \n  \n': 'sheet_empty',
        'name sku price category': 'sheet_no_delimiter',
        // A column nobody reads is refused rather than dropped: dropping it
        // silently drops data a person supplied.
        'name,sku,price,category,supplier': 'sheet_unknown_column',
        'name,sku,price,category,product name': 'sheet_repeated_column',
        'name,sku,category': 'sheet_missing_column',
        'name,sku,price': 'sheet_missing_category',
        'name,sku,price,,category': 'sheet_blank_column',
        'name,sku,price,category': 'sheet_has_no_rows',
      }.entries) {
        expect(
          () => _importPlan(entry.key),
          throwsA(
            isA<TenantBulkCatalogException>().having(
              (error) => error.code,
              'code for "${entry.key}"',
              entry.value,
            ),
          ),
        );
      }
    });

    test('a sheet longer than the chain will hold is refused', () {
      final rows = <String>[
        'name,sku,price,category',
        for (var index = 0; index <= maximumBulkCatalogSheetRows; index++)
          'Product $index,P-$index,10,Bakery',
      ];

      expect(
        () => _importPlan(rows.join('\n')),
        throwsA(
          isA<TenantBulkCatalogException>().having(
            (error) => error.code,
            'code',
            'sheet_too_many_rows',
          ),
        ),
      );
    });

    test('a manager\'s sheet is refused for its cost column, not per row', () {
      // Where the server decides it: over the request, before anything is read,
      // so a manager cannot preview green and then meet a commit-time refusal.
      expect(
        () => _importPlan(_sheet, role: TenantRole.manager),
        throwsA(
          isA<TenantBulkCatalogException>().having(
            (error) => error.code,
            'code',
            'cost_forbidden',
          ),
        ),
      );
      // A price is not gated: setting a first price is creation, and the
      // add-product form beside this one accepts one from a manager too.
      expect(
        _importPlan(
          'name,sku,price,category\nMandazi,M-1,20,Bakery',
          role: TenantRole.manager,
        ).rowCount,
        1,
      );
    });

    test('every unreadable row is named at once, and none is sent', () {
      final plan = _importPlan(
        'name,sku,price,cost,quantity,category,categoryId\n'
        'Good,G-1,10,,1,Bakery,\n' // fine
        ',B-1,10,,,Bakery,\n' // no name
        'Spaced,B 2,10,,,Bakery,\n' // a code a scanner cannot emit
        'Priced,B-3,19.999,,,Bakery,\n' // not representable
        'Costly,B-4,10,1.005,,Bakery,\n' // cost not representable
        'Counted,B-5,10,,-4,Bakery,\n' // a negative opening balance
        'Both,B-6,10,,,Bakery,cat-bakery\n' // a category named twice
        'Neither,B-7,10,,,,\n' // filed under nothing
        'Short,B-8,10\n', // fewer cells than the header names
      );

      expect(plan.rowCount, 1);
      expect(plan.pages.single.rows.single.name, 'Good');
      expect(plan.lineCount, 9);
      expect(plan.refused, hasLength(8));
      // Reported by the line of the pasted text, header included, because that
      // is the line the person's own editor shows.
      expect(plan.refused.map((row) => row.position), <int>[
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
      ]);
      expect(
        plan.refused.every(
          (row) => row.status == TenantBulkCatalogRowStatus.failed,
        ),
        isTrue,
      );
      expect(plan.refused.first.subject, 'This row');
      expect(plan.refused[1].subject, 'Spaced');
      expect(plan.refused.last.detail, contains('cells the header names'));
    });

    test('a refused row consumes no row index and no page', () {
      // The index is what the server derives the product's document ID from, so
      // a gap in it would be a product created at an ID nothing else predicts.
      final plan = _importPlan(
        <String>[
          'name,sku,price,category',
          ',B-0,10,Bakery',
          for (var index = 1; index <= 51; index++)
            'Product $index,P-$index,10,Bakery',
        ].join('\n'),
      );

      expect(plan.refused, hasLength(1));
      expect(plan.pages.map((page) => page.rows.length), <int>[50, 1]);
      expect(plan.pages.first.rows.first.index, 0);
      expect(plan.pages.first.rows.first.line, 3);
      expect(plan.pages.last.rows.single.index, 0);
      expect(plan.pages.map((page) => page.requestId).toSet(), hasLength(2));
    });

    test('a categoryId column names a category by ID', () {
      final row = _importPlan(
        'name,sku,price,categoryId\nMandazi,M-1,20,cat-bakery',
      ).pages.single.rows.single;

      expect(row.categoryId, 'cat-bakery');
      expect(row.categoryName, isNull);
      expect(row.payload().containsKey('categoryName'), isFalse);
    });
  });

  group('bulk correction answer', () {
    test('a preview is decoded and reports no audit entry', () {
      final page = _twoRowPage();

      final result = TenantProductBatchResult.fromCallable(
        _batchResponse(mode: 'preview'),
        page: page,
        mode: TenantBulkCatalogMode.preview,
      );

      expect(result.batchId, 'pb_abc');
      expect(result.updatedCount, 1);
      expect(result.unchangedCount, 1);
      expect(result.rows.first.status, TenantBulkCatalogRowStatus.updated);
      expect(result.rows.first.updateId, isNull);
      expect(result.rows.first.product!.priceMinor, 1999);
      expect(result.rows[1].status, TenantBulkCatalogRowStatus.unchanged);
      expect(result.rows[1].changedFields, isEmpty);
    });

    test('a commit must name the audit entry of every row it wrote', () {
      final page = _twoRowPage();

      expect(
        TenantProductBatchResult.fromCallable(
          _batchResponse(mode: 'commit', updateId: 'pu_1'),
          page: page,
          mode: TenantBulkCatalogMode.commit,
        ).rows.first.updateId,
        'pu_1',
      );
      // A correction with no audit entry is the one thing a price change may
      // never be: unanswerable afterwards.
      expect(
        () => TenantProductBatchResult.fromCallable(
          _batchResponse(mode: 'commit'),
          page: page,
          mode: TenantBulkCatalogMode.commit,
        ),
        throwsA(isA<FormatException>()),
      );
      // And a preview that named one would be describing something that exists.
      expect(
        () => TenantProductBatchResult.fromCallable(
          _batchResponse(mode: 'preview', updateId: 'pu_1'),
          page: page,
          mode: TenantBulkCatalogMode.preview,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('an answer is reconciled against the page, never repeated back', () {
      final page = _twoRowPage();

      for (final entry in <String, Map<String, Object?>>{
        'another business': <String, Object?>{'tenantId': 'tenant-b'},
        'the wrong mode': <String, Object?>{'mode': 'commit'},
        'a different row count': <String, Object?>{'rowCount': 3},
        'a disagreeing count': <String, Object?>{'updatedCount': 2},
        'rows out of order': <String, Object?>{
          'rows': <Object?>[
            _batchRow(index: 1, productId: 'pd-1'),
            _batchRow(index: 0, productId: 'pd-2'),
          ],
        },
        'another product': <String, Object?>{
          'rows': <Object?>[
            _batchRow(index: 0, productId: 'pd-other'),
            _batchRow(index: 1, productId: 'pd-2', status: 'unchanged'),
          ],
        },
        'an unknown outcome': <String, Object?>{
          'rows': <Object?>[
            _batchRow(index: 0, productId: 'pd-1', status: 'created'),
            _batchRow(index: 1, productId: 'pd-2', status: 'unchanged'),
          ],
        },
        'a field this correction did not name': <String, Object?>{
          'rows': <Object?>[
            _batchRow(
              index: 0,
              productId: 'pd-1',
              changedFields: <String>['price', 'name'],
            ),
            _batchRow(index: 1, productId: 'pd-2', status: 'unchanged'),
          ],
        },
        'an unchanged row that changed': <String, Object?>{
          'rows': <Object?>[
            _batchRow(index: 0, productId: 'pd-1'),
            _batchRow(
              index: 1,
              productId: 'pd-2',
              status: 'unchanged',
              changedFields: <String>['price'],
            ),
          ],
        },
        'a product not holding what was asked for': <String, Object?>{
          'rows': <Object?>[
            _batchRow(index: 0, productId: 'pd-1', priceMinor: 2000),
            _batchRow(index: 1, productId: 'pd-2', status: 'unchanged'),
          ],
        },
        'two figures for one price': <String, Object?>{
          'rows': <Object?>[
            _batchRow(index: 0, productId: 'pd-1', price: 20.0),
            _batchRow(index: 1, productId: 'pd-2', status: 'unchanged'),
          ],
        },
      }.entries) {
        expect(
          () => TenantProductBatchResult.fromCallable(
            _batchResponse(mode: 'preview', overrides: entry.value),
            page: page,
            mode: TenantBulkCatalogMode.preview,
          ),
          throwsA(isA<FormatException>()),
          reason: entry.key,
        );
      }
    });

    test('a refused row carries its reason and describes no product', () {
      final page = _twoRowPage();

      final result = TenantProductBatchResult.fromCallable(
        _batchResponse(
          mode: 'preview',
          overrides: <String, Object?>{
            'updatedCount': 0,
            'unchangedCount': 1,
            'failedCount': 1,
            'rows': <Object?>[
              <String, Object?>{
                'index': 0,
                'productId': 'pd-1',
                'status': 'failed',
                'changedFields': <String>[],
                'updateId': null,
                'code': 'not-found',
                'message': 'That product no longer exists.',
                'product': null,
              },
              _batchRow(index: 1, productId: 'pd-2', status: 'unchanged'),
            ],
          },
        ),
        page: page,
        mode: TenantBulkCatalogMode.preview,
      );

      expect(result.rows.first.status, TenantBulkCatalogRowStatus.failed);
      expect(result.rows.first.message, 'That product no longer exists.');
      expect(result.rows.first.product, isNull);
    });

    test('a cleared cost must come back holding nothing', () {
      final page = _batchPlan(
        products: <TenantProduct>[_product('pd-1')],
        edit: const TenantBulkCatalogEdit.clearCost(),
      ).pages.single;

      expect(
        TenantProductBatchResult.fromCallable(
          _batchResponse(
            mode: 'preview',
            overrides: <String, Object?>{
              'updatedCount': 1,
              'unchangedCount': 0,
              'rowCount': 1,
              'rows': <Object?>[
                _batchRow(
                  index: 0,
                  productId: 'pd-1',
                  changedFields: <String>['cost'],
                ),
              ],
            },
          ),
          page: page,
          mode: TenantBulkCatalogMode.preview,
        ).rows.single.product!.costMinor,
        isNull,
      );
      expect(
        () => TenantProductBatchResult.fromCallable(
          _batchResponse(
            mode: 'preview',
            overrides: <String, Object?>{
              'updatedCount': 1,
              'unchangedCount': 0,
              'rowCount': 1,
              'rows': <Object?>[
                _batchRow(
                  index: 0,
                  productId: 'pd-1',
                  changedFields: <String>['cost'],
                  cost: 40.0,
                  costMinor: 4000,
                ),
              ],
            },
          ),
          page: page,
          mode: TenantBulkCatalogMode.preview,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('import answer', () {
    test('a preview names no document it did not write', () {
      final page = _importPage();

      final result = TenantProductImportResult.fromCallable(
        _importResponse(mode: 'preview'),
        page: page,
        mode: TenantBulkCatalogMode.preview,
      );

      expect(result.importId, 'im_abc');
      expect(result.createdCount, 1);
      expect(result.rows.single.status, TenantBulkCatalogRowStatus.created);
      expect(result.rows.single.productId, isNull);
      expect(result.rows.single.adjustmentId, isNull);
      expect(result.rows.single.product!.quantity, 12);
      // The resolved category is the one field that legitimately differs from
      // the row, which is the whole reason a name is resolved on the server.
      expect(result.rows.single.product!.categoryId, 'cat-bakery');
    });

    test('a commit names the product, and the ledger entry when stock came in', () {
      final page = _importPage();

      final result = TenantProductImportResult.fromCallable(
        _importResponse(
          mode: 'commit',
          productId: 'pd_created',
          adjustmentId: 'sa_created',
        ),
        page: page,
        mode: TenantBulkCatalogMode.commit,
      );

      expect(result.rows.single.productId, 'pd_created');
      expect(result.rows.single.adjustmentId, 'sa_created');
      // Stock with no ledger entry has no recorded origin, which is the single
      // defect that made accepting a quantity here justifiable at all.
      expect(
        () => TenantProductImportResult.fromCallable(
          _importResponse(mode: 'commit', productId: 'pd_created'),
          page: page,
          mode: TenantBulkCatalogMode.commit,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => TenantProductImportResult.fromCallable(
          _importResponse(mode: 'commit', adjustmentId: 'sa_created'),
          page: page,
          mode: TenantBulkCatalogMode.commit,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a row that opened holding nothing names no ledger entry', () {
      final page = _importPage(quantity: 0);

      final result = TenantProductImportResult.fromCallable(
        _importResponse(
          mode: 'commit',
          productId: 'pd_created',
          quantity: 0,
        ),
        page: page,
        mode: TenantBulkCatalogMode.commit,
      );

      expect(result.rows.single.adjustmentId, isNull);
      expect(
        () => TenantProductImportResult.fromCallable(
          _importResponse(
            mode: 'commit',
            productId: 'pd_created',
            adjustmentId: 'sa_created',
            quantity: 0,
          ),
          page: page,
          mode: TenantBulkCatalogMode.commit,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a product described differently from the row is refused', () {
      final page = _importPage();

      for (final entry in <String, Map<String, Object?>>{
        'another name': <String, Object?>{'name': 'Something else'},
        'another code': <String, Object?>{'sku': 'X-9'},
        'another price': <String, Object?>{'price': 70.0, 'priceMinor': 7000},
        'another cost': <String, Object?>{'cost': 41.0, 'costMinor': 4100},
        'another opening balance': <String, Object?>{'quantity': 11},
        'an unusable category': <String, Object?>{'categoryId': 'cat/escape'},
        'no opening balance at all': <String, Object?>{'quantity': null},
      }.entries) {
        expect(
          () => TenantProductImportResult.fromCallable(
            _importResponse(mode: 'preview', product: entry.value),
            page: page,
            mode: TenantBulkCatalogMode.preview,
          ),
          throwsA(isA<FormatException>()),
          reason: entry.key,
        );
      }
    });

    test('a row that named a category by ID must come back filed under it', () {
      final page = _importPlan(
        'name,sku,price,categoryId\nMandazi,M-1,20,cat-bakery',
      ).pages.single;

      expect(
        () => TenantProductImportResult.fromCallable(
          _importResponse(
            mode: 'preview',
            product: <String, Object?>{
              'name': 'Mandazi',
              'sku': 'M-1',
              'price': 20.0,
              'priceMinor': 2000,
              'cost': null,
              'costMinor': null,
              'quantity': 0,
              'categoryId': 'cat-drinks',
            },
          ),
          page: page,
          mode: TenantBulkCatalogMode.preview,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('gateways', () {
    test('a session that may not change never reaches either callable', () async {
      final batch = _BatchCallable();
      final import = _ImportCallable();
      final page = _twoRowPage();
      final importPage = _importPage();

      await expectLater(
        TenantProductBatchGateway(
          session: _session(role: TenantRole.cashier),
          callable: batch,
        ).send(page, TenantBulkCatalogMode.preview),
        throwsA(isA<TenantBulkCatalogRequestException>()),
      );
      // A page built for one business can never be sent while another is open,
      // even though both payloads would be well-formed.
      await expectLater(
        TenantProductBatchGateway(
          session: _session(tenantId: 'tenant-b'),
          callable: batch,
        ).send(page, TenantBulkCatalogMode.preview),
        throwsA(isA<TenantBulkCatalogRequestException>()),
      );
      await expectLater(
        TenantProductImportGateway(
          session: _session(role: TenantRole.cashier),
          callable: import,
        ).send(importPage, TenantBulkCatalogMode.preview),
        throwsA(isA<TenantBulkCatalogRequestException>()),
      );
      expect(batch.payloads, isEmpty);
      expect(import.payloads, isEmpty);
    });

    test('a page is sent exactly as it was built', () async {
      final callable = _BatchCallable(answer: _batchResponse(mode: 'commit', updateId: 'pu_1'));
      final page = _twoRowPage();

      await TenantProductBatchGateway(
        session: _session(),
        callable: callable,
      ).send(page, TenantBulkCatalogMode.commit);

      expect(callable.payloads.single, page.payload(TenantBulkCatalogMode.commit));
    });

    test('a refusal is classified by what the server actually said', () async {
      for (final entry in <List<String>, TenantBulkCatalogFailure>{
        <String>['permission-denied', "Only an owner or administrator may change a product's price."]:
            TenantBulkCatalogFailure.moneyForbidden,
        <String>['permission-denied', 'Only an owner or administrator may change what a product costs.']:
            TenantBulkCatalogFailure.moneyForbidden,
        <String>['permission-denied', 'Not a member.']:
            TenantBulkCatalogFailure.forbidden,
        <String>['unauthenticated', '']: TenantBulkCatalogFailure.forbidden,
        <String>['already-exists', 'A different request used this requestId.']:
            TenantBulkCatalogFailure.duplicateRequest,
        <String>['failed-precondition', 'This business holds more than 500 categories.']:
            TenantBulkCatalogFailure.tooManyCategories,
        <String>['invalid-argument', 'supplier is not part of a product import.']:
            TenantBulkCatalogFailure.invalidRequest,
        <String>['unavailable', '']: TenantBulkCatalogFailure.ambiguous,
        <String>['deadline-exceeded', '']: TenantBulkCatalogFailure.ambiguous,
        <String>['internal', '']: TenantBulkCatalogFailure.ambiguous,
        <String>['aborted', '']: TenantBulkCatalogFailure.ambiguous,
        <String>['unknown', '']: TenantBulkCatalogFailure.ambiguous,
        <String>['resource-exhausted', 'later']: TenantBulkCatalogFailure.refused,
      }.entries) {
        await expectLater(
          TenantProductBatchGateway(
            session: _session(),
            callable: _BatchCallable(
              error: FirebaseFunctionsException(
                code: entry.key.first,
                message: entry.key.last,
              ),
            ),
          ).send(_twoRowPage(), TenantBulkCatalogMode.commit),
          throwsA(
            isA<TenantBulkCatalogRequestException>().having(
              (error) => error.failure,
              'failure for ${entry.key.first}',
              entry.value,
            ),
          ),
        );
      }
    });

    test('a call that never answers is an unknown outcome', () async {
      for (final error in <Object>[
        TimeoutException('slow'),
        StateError('transport closed'),
      ]) {
        await expectLater(
          TenantProductImportGateway(
            session: _session(),
            callable: _ImportCallable(error: error),
          ).send(_importPage(), TenantBulkCatalogMode.commit),
          throwsA(
            isA<TenantBulkCatalogRequestException>().having(
              (failure) => failure.failure,
              'failure',
              TenantBulkCatalogFailure.ambiguous,
            ),
          ),
        );
      }
    });

    test('only an unknown outcome may have written anything', () {
      for (final failure in TenantBulkCatalogFailure.values) {
        expect(
          TenantBulkCatalogRequestException(failure).mayHaveCommitted,
          failure == TenantBulkCatalogFailure.ambiguous,
          reason: failure.name,
        );
      }
    });
  });

  group('report', () {
    test('a correction is reported by its position in the selection', () {
      // The second page's rows are indexed 0 and 1 by the server, and are the
      // fifty-first and fifty-second products the operator picked.
      final plan = _batchPlan(
        products: <TenantProduct>[
          for (var index = 1; index <= 52; index++) _product('pd-$index'),
        ],
        edit: const TenantBulkCatalogEdit.price('19.99'),
      );
      final page = plan.pages.last;

      final rows = describeBatchOutcomes(
        page,
        TenantProductBatchResult.fromCallable(
          _batchResponse(
            mode: 'preview',
            overrides: <String, Object?>{
              'rows': <Object?>[
                _batchRow(index: 0, productId: 'pd-51'),
                _batchRow(index: 1, productId: 'pd-52', status: 'unchanged'),
              ],
            },
          ),
          page: page,
          mode: TenantBulkCatalogMode.preview,
        ),
      );

      expect(rows.map((row) => row.position), <int>[51, 52]);
      expect(rows.first.subject, 'Product pd-51');
      expect(rows.first.detail, 'from 65 to 19.99');
      expect(rows[1].detail, 'Already 19.99. Nothing was written for this row.');
    });

    test('an import is reported by the line of the pasted sheet', () {
      final page = _importPage();

      final rows = describeImportOutcomes(
        page,
        TenantProductImportResult.fromCallable(
          _importResponse(mode: 'preview'),
          page: page,
          mode: TenantBulkCatalogMode.preview,
        ),
        names: tenantCategoryNames(_categories()),
      );

      expect(rows.single.position, 2);
      expect(rows.single.subject, 'White bread loaf');
      expect(rows.single.detail, contains('opens holding 12'));
      expect(rows.single.detail, contains('costs 40'));
    });

    test('an import preview names the category, never the ID it wrote', () {
      // The whole of finding 5's first half: the sheet says `Bakery`, the server
      // correctly echoes the `cat-bakery` it wrote, and the person reading the
      // preview typed neither an ID nor anything that looks like one.
      final page = _importPage();
      final result = TenantProductImportResult.fromCallable(
        _importResponse(mode: 'preview'),
        page: page,
        mode: TenantBulkCatalogMode.preview,
      );

      expect(
        describeImportOutcomes(
          page,
          result,
          names: tenantCategoryNames(_categories()),
        ).single.detail,
        allOf(contains('filed under Bakery'), isNot(contains('cat-bakery'))),
      );

      // A category this surface did not read still names itself, because the
      // sheet said what it was and the server matched it to accept the row.
      expect(
        describeImportOutcomes(
          page,
          result,
          names: const <String, String>{},
        ).single.detail,
        allOf(contains('filed under Bakery'), isNot(contains('cat-bakery'))),
      );
    });

    test('an import row that named an unread category ID names no ID', () {
      // Nothing can name this category: the row gave an ID rather than a name,
      // and the ID is not one this surface read. It is still not shown.
      final page = _importPlan(
        'name,sku,price,categoryId\nMandazi,M-1,20,cat-elsewhere',
      ).pages.single;

      final rows = describeImportOutcomes(
        page,
        TenantProductImportResult.fromCallable(
          _importResponse(
            mode: 'preview',
            product: <String, Object?>{
              'name': 'Mandazi',
              'sku': 'M-1',
              'price': 20.0,
              'priceMinor': 2000,
              'cost': null,
              'costMinor': null,
              'quantity': 0,
              'categoryId': 'cat-elsewhere',
            },
          ),
          page: page,
          mode: TenantBulkCatalogMode.preview,
        ),
        names: tenantCategoryNames(_categories()),
      );

      expect(
        rows.single.detail,
        allOf(
          contains('filed under $unlistedTenantCategoryPhrase'),
          isNot(contains('cat-elsewhere')),
        ),
      );
    });

    test('a report counts rows and states whether every page answered', () {
      const report = TenantBulkCatalogReport(
        mode: TenantBulkCatalogMode.commit,
        pageCount: 3,
        pagesAnswered: 2,
        rows: <TenantBulkCatalogRowReport>[
          TenantBulkCatalogRowReport(
            position: 1,
            subject: 'A',
            status: TenantBulkCatalogRowStatus.updated,
            detail: '',
          ),
          TenantBulkCatalogRowReport(
            position: 2,
            subject: 'B',
            status: TenantBulkCatalogRowStatus.unchanged,
            detail: '',
          ),
          TenantBulkCatalogRowReport(
            position: 3,
            subject: 'C',
            status: TenantBulkCatalogRowStatus.failed,
            detail: '',
          ),
        ],
        failure: TenantBulkCatalogFailure.ambiguous,
      );

      expect(report.updatedCount, 1);
      expect(report.unchangedCount, 1);
      expect(report.failedCount, 1);
      expect(report.createdCount, 0);
      expect(report.complete, isFalse);
      expect(
        const TenantBulkCatalogReport(
          mode: TenantBulkCatalogMode.preview,
          pageCount: 1,
          pagesAnswered: 1,
          rows: <TenantBulkCatalogRowReport>[],
        ).complete,
        isTrue,
      );
    });

    test('every locally refused row has a message a person can act on', () {
      // A refusal reaching the fallback would be a code this surface raises and
      // does not word, which is the one way this list goes stale silently.
      for (final code in <String>[
        'catalog_forbidden',
        'no_products_selected',
        'too_many_products',
        'product_named_twice',
        'field_not_bulk_editable',
        'unknown_category',
        'edit_forbidden',
        'price_forbidden',
        'cost_forbidden',
        'invalid_price',
        'price_not_representable',
        'invalid_cost',
        'cost_not_representable',
        'invalid_product_name',
        'invalid_category_name',
        'invalid_sku',
        'invalid_quantity',
        'invalid_category_id',
        'row_needs_category',
        'row_category_twice',
        'row_column_count',
        'sheet_empty',
        'sheet_no_delimiter',
        'sheet_blank_column',
        'sheet_unknown_column',
        'sheet_repeated_column',
        'sheet_missing_column',
        'sheet_missing_category',
        'sheet_too_many_rows',
        'sheet_has_no_rows',
        'invalid_catalog_request_id',
      ]) {
        expect(
          bulkCatalogRefusalMessage(TenantBulkCatalogException(code, 'x')),
          isNot('That row could not be read.'),
          reason: code,
        );
      }
      expect(
        bulkCatalogRefusalMessage(
          const TenantBulkCatalogException('something_new'),
        ),
        'That row could not be read.',
      );
    });
  });
}

TenantSession _session({
  TenantRole role = TenantRole.owner,
  String tenantId = 'tenant-a',
}) => TenantSession.active(uid: 'user-a', tenantId: tenantId, role: role);

/// Fresh request IDs, in a fixed order so a payload can be asserted whole.
TenantCatalogRequestIdFactory _requestIds() {
  var next = 0;
  return () => 'catalog-${++next}';
}

List<TenantCategory> _categories() => <TenantCategory>[
  for (final entry in <String, String>{
    'cat-bakery': 'Bakery',
    'cat-drinks': 'Drinks',
  }.entries)
    TenantCategory.fromSnapshot(
      TenantQueryDocumentSnapshot(
        path: 'tenants/tenant-a/categories/${entry.key}',
        data: <String, Object?>{'name': entry.value},
      ),
    ),
];

TenantProduct _product(
  String id, {
  String tenantId = 'tenant-a',
  String categoryId = 'cat-bakery',
  double? cost = 40,
}) => TenantProduct.fromDocument(
  path: 'tenants/$tenantId/products/$id',
  data: <String, Object?>{
    'name': 'Product $id',
    'SKU': 'sku-$id',
    'price': 65,
    if (cost != null) 'cost': cost,
    'quantity': 4,
    'categoryId': categoryId,
  },
);

TenantProductBatchPlan _batchPlan({
  required Iterable<TenantProduct> products,
  required TenantBulkCatalogEdit edit,
  TenantRole role = TenantRole.owner,
}) => TenantBulkCatalogRepository(
  session: _session(role: role),
).buildBatchPlan(
  products: products,
  edit: edit,
  categories: _categories(),
  requestIds: _requestIds(),
);

TenantProductImportPlan _importPlan(
  String sheet, {
  TenantRole role = TenantRole.owner,
}) => TenantBulkCatalogRepository(
  session: _session(role: role),
).buildImportPlan(sheet: sheet, requestIds: _requestIds());

/// Two products being repriced to 19.99, which is what most answers describe.
TenantProductBatchPage _twoRowPage() => _batchPlan(
  products: <TenantProduct>[_product('pd-1'), _product('pd-2')],
  edit: const TenantBulkCatalogEdit.price('19.99'),
).pages.single;

/// One imported row from the shared sheet's first line.
TenantProductImportPage _importPage({int quantity = 12}) => _importPlan(
  'name,sku,price,cost,quantity,category\n'
  'White bread loaf,6161100000019,65,40,$quantity,Bakery\n',
).pages.single;

Map<String, Object?> _batchRow({
  required int index,
  required String productId,
  String status = 'updated',
  List<String>? changedFields,
  String? updateId,
  double price = 19.99,
  int priceMinor = 1999,
  double? cost,
  int? costMinor,
}) => <String, Object?>{
  'index': index,
  'productId': productId,
  'status': status,
  'changedFields':
      changedFields ?? (status == 'updated' ? <String>['price'] : <String>[]),
  'updateId': updateId,
  'code': null,
  'message': null,
  'product': <String, Object?>{
    'name': 'Product $productId',
    'sku': 'sku-$productId',
    'price': price,
    'priceMinor': priceMinor,
    'cost': cost,
    'costMinor': costMinor,
    'categoryId': 'cat-bakery',
  },
};

Map<String, Object?> _batchResponse({
  required String mode,
  String? updateId,
  Map<String, Object?> overrides = const <String, Object?>{},
}) => <String, Object?>{
  'batchId': 'pb_abc',
  'tenantId': 'tenant-a',
  'mode': mode,
  'rowCount': 2,
  'updatedCount': 1,
  'unchangedCount': 1,
  'failedCount': 0,
  'rows': <Object?>[
    _batchRow(index: 0, productId: 'pd-1', updateId: updateId),
    _batchRow(index: 1, productId: 'pd-2', status: 'unchanged'),
  ],
  ...overrides,
};

Map<String, Object?> _importResponse({
  required String mode,
  String? productId,
  String? adjustmentId,
  int quantity = 12,
  Map<String, Object?>? product,
}) => <String, Object?>{
  'importId': 'im_abc',
  'tenantId': 'tenant-a',
  'mode': mode,
  'rowCount': 1,
  'createdCount': 1,
  'failedCount': 0,
  'rows': <Object?>[
    <String, Object?>{
      'index': 0,
      'status': 'created',
      'productId': productId,
      'adjustmentId': adjustmentId,
      'code': null,
      'message': null,
      'product':
          product ??
          <String, Object?>{
            'name': 'White bread loaf',
            'sku': '6161100000019',
            'price': 65.0,
            'priceMinor': 6500,
            'cost': 40.0,
            'costMinor': 4000,
            'quantity': quantity,
            'categoryId': 'cat-bakery',
          },
    },
  ],
};

final class _BatchCallable implements UpdateProductsCallable {
  _BatchCallable({this.answer, this.error});

  final Map<String, Object?>? answer;
  final Object? error;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    if (error != null) throw error!;
    return answer;
  }
}

final class _ImportCallable implements ImportProductsCallable {
  _ImportCallable({this.error});

  final Object? error;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  /// It never answers well-formed, because every test that reaches an answer
  /// decodes one built by hand: the point of those is what the decoder refuses,
  /// which a fake that always answers correctly cannot show.
  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(payload);
    if (error != null) throw error!;
    return null;
  }
}
