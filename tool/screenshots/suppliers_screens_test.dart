/// Evidence for the Suppliers route: the directory, a supplier's record, and
/// the form that adds one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/reports/report_file.dart';
import 'package:flutter_application_1/suppliers/suppliers.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'harness.dart';

/// Takes every write and records nothing: these captures are of what a person
/// sees, and no capture here submits.
final class _Writer implements TenantSupplierWriter {
  const _Writer();

  @override
  Future<TenantSupplierWriteResult> createSupplier(
    TenantSupplierCreateIntent intent,
  ) async => TenantSupplierWriteResult.queued('supplier-create-capture');

  @override
  Future<TenantSupplierWriteResult> updateSupplier(
    TenantSupplierUpdateIntent intent,
  ) async => TenantSupplierWriteResult.queued('supplier-update-capture');
}

final class _DeliveryWriter implements TenantSupplierDeliveryWriter {
  const _DeliveryWriter();

  @override
  Future<TenantSupplierDeliveryWriteResult> receive(
    TenantSupplierDeliveryIntent intent,
  ) async => const TenantSupplierDeliveryWriteResult.queued(<String>[]);
}

/// Saves nothing: these captures stop at the sheet.
final class _Saver implements TenantReportSaver {
  const _Saver();

  @override
  Future<TenantReportSaveOutcome> save(
    TenantReportFile file, {
    required TenantReportDestination destination,
  }) async => TenantReportSaveOutcome.dismissed;
}

/// The seeded business, searchable the way the catalog is: by a word of the
/// name, or the start of the code.
///
/// **Only here**, rather than on the shared fake, because every screen that
/// reads the catalog prefers a search reader when it has one - the Inventory
/// captures would start reading through this instead.
final class _Searchable implements TenantDataReader, TenantProductSearchReader {
  _Searchable() : _business = FakeTenantReader.business();

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
    final products = _business.collections[query.collectionPath] ??
        const <String, Map<String, Object?>>{};
    final ids = products.keys.toList()..sort();
    return <TenantQueryDocumentSnapshot>[
      for (final id in ids)
        if (prefix == null ||
            '${products[id]!['name']}'
                .toLowerCase()
                .split(RegExp(r'\s+'))
                .any((word) => word.startsWith(prefix)) ||
            '${products[id]!['SKU']}'.toLowerCase().startsWith(prefix))
          TenantQueryDocumentSnapshot(
            path: '${query.collectionPath}/$id',
            data: products[id]!,
          ),
    ].take(query.limit).toList();
  }
}

TenantSupplierDeliveryServices _deliveries(_Searchable reader) =>
    TenantSupplierDeliveryServices(
      writer: const _DeliveryWriter(),
      productSearchReader: reader,
    );

Widget _directory() {
  final reader = _Searchable();
  return inSession(
    TenantSuppliersScreen(
      reader: reader,
      writer: const _Writer(),
      deliveries: _deliveries(reader),
      reportSaver: const _Saver(),
    ),
    controller: seedSession(role: TenantRole.manager, uid: managerUid),
  );
}

Widget _record(String supplierId) {
  final reader = _Searchable();
  return inSession(
    TenantSupplierRecordScreen(
      reader: reader,
      writer: const _Writer(),
      deliveries: _deliveries(reader),
      supplierId: supplierId,
    ),
    controller: seedSession(role: TenantRole.manager, uid: managerUid),
  );
}

/// Opens the delivery form from ABC's record and puts two lines on it.
Future<void> _fillDelivery(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('supplier-record-receive')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('delivery-reference')),
    'INV-48520',
  );
  for (final (search, productId, quantity, cost) in <(String, String, String, String)>[
    ('bread', 'pd-bread-white', '24', '49.50'),
    ('soap', 'pd-bar-soap-blue', '36', ''),
  ]) {
    // The form opens with one search already out; each later product asks
    // for another.
    final field = find.byKey(const ValueKey('product-typeahead-search'));
    if (field.evaluate().isEmpty) {
      final add = find.byKey(const ValueKey('delivery-add-product'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
    }
    await tester.enterText(field, search);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('product-typeahead-$productId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(ValueKey('delivery-line-quantity-$productId')),
      quantity,
    );
    if (cost.isNotEmpty) {
      await tester.enterText(
        find.byKey(ValueKey('delivery-line-cost-$productId')),
        cost,
      );
    }
    await tester.pumpAndSettle();
  }
}

void main() {
  screenshotCase(
    'suppliers-active',
    build: _directory,
    viewports: responsiveViewports,
  );

  screenshotCase(
    'suppliers-every-standing',
    build: _directory,
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('suppliers-standing-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('suppliers-standing-all')).last);
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
  );

  screenshotCase(
    'supplier-record',
    build: () => _record('sp_abc'),
    viewports: responsiveViewports,
  );

  screenshotCase(
    'supplier-record-inactive',
    build: () => _record('sp_xyz'),
    viewports: responsiveViewports,
  );

  screenshotCase(
    'supplier-delivery-form',
    build: () => _record('sp_abc'),
    afterPump: _fillDelivery,
    viewports: responsiveViewports,
  );

  screenshotCase(
    'supplier-delivery-confirm',
    build: () => _record('sp_abc'),
    fullPage: false,
    afterPump: (tester) async {
      await _fillDelivery(tester);
      // Scrolled to rather than assumed: a short viewport has not built the
      // bottom of the form yet.
      final submit = find.byKey(const ValueKey('delivery-submit'));
      await tester.scrollUntilVisible(
        submit,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('delivery-form')),
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

  screenshotCase(
    'supplier-record-deliveries-open',
    build: () => _record('sp_abc'),
    afterPump: (tester) async {
      final lines = find.byKey(const ValueKey('delivery-lines-sd_2'));
      await tester.ensureVisible(lines);
      await tester.pumpAndSettle();
      await tester.tap(lines);
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
  );

  screenshotCase(
    'supplier-report-sheet',
    build: _directory,
    fullPage: false,
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('report-action-suppliers')));
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
  );

  screenshotCase(
    'supplier-add',
    build: _directory,
    fullPage: false,
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('suppliers-add')));
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
  );
}
