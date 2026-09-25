/// Evidence for the Production route: the batches made, and recording one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/production/production.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'harness.dart';

final class _Writer implements TenantProductionWriter {
  const _Writer();

  @override
  Future<TenantProductionWriteResult> complete(
    TenantProductionIntent intent,
  ) async => TenantProductionWriteResult.queued(intent.operationId);
}

/// The seeded business with its bread made here, searchable by a word of a
/// product's name - only here, for the reason the supplier captures give.
final class _Bakery implements TenantDataReader, TenantProductSearchReader {
  _Bakery() : _business = FakeTenantReader.business() {
    const root = 'tenants/$seedTenantId';
    final bread = <String, Object?>{
      ...seedProducts['pd-bread-white']!,
      'costType': 'produced',
    };
    _business.collections['$root/products']!['pd-bread-white'] = bread;
    _business.documents['$root/products/pd-bread-white'] = bread;
  }

  final FakeTenantReader _business;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) =>
      _business.getDocument(path);

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) => _business.getCollectionPage(query);

  @override
  Future<List<TenantQueryDocumentSnapshot>> searchTenantProducts(
    TenantProductSearchQuery query,
  ) async {
    final prefix = query.searchPrefix;
    final products =
        _business.collections[query.collectionPath] ??
        const <String, Map<String, Object?>>{};
    final ids = products.keys.toList()..sort();
    return <TenantQueryDocumentSnapshot>[
      for (final id in ids)
        if (prefix == null ||
            '${products[id]!['name']}'
                .toLowerCase()
                .split(' ')
                .any((word) => word.startsWith(prefix)))
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/$id',
            data: products[id]!,
          ),
    ].take(query.limit).toList();
  }
}

Widget _production() {
  final reader = _Bakery();
  return inSession(
    TenantProductionScreen(
      reader: reader,
      services: TenantProductionServices(
        writer: const _Writer(),
        productSearchReader: reader,
      ),
    ),
    controller: seedSession(role: TenantRole.manager, uid: managerUid),
  );
}

/// Opens the form, chooses the bread, and makes a hundred.
Future<void> _fillBatch(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('production-record')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('production-choose-product')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('product-picker-search')),
    'bread',
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('product-picker-choose-pd-bread-white')),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('production-quantity')),
    '100',
  );
  await tester.pumpAndSettle();
}

void main() {
  screenshotCase(
    'production-batches',
    build: _production,
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('production-costs-pb_2')));
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
  );

  screenshotCase(
    'production-record',
    build: _production,
    afterPump: (tester) async {
      await _fillBatch(tester);
      // The warning opened, so the capture shows what it says.
      await tester.tap(find.byKey(const ValueKey('production-expenses-warning')));
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
  );

  screenshotCase(
    'production-confirm',
    build: _production,
    fullPage: false,
    afterPump: (tester) async {
      await _fillBatch(tester);
      final submit = find.byKey(const ValueKey('production-submit'));
      await tester.scrollUntilVisible(
        submit,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('production-form')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
  );
}
