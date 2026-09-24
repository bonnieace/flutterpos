/// Evidence for the Suppliers route: the directory, a supplier's record, and
/// the form that adds one.
library;

import 'package:flutter/material.dart';
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

Widget _directory() => inSession(
  TenantSuppliersScreen(
    reader: FakeTenantReader.business(),
    writer: const _Writer(),
  ),
  controller: seedSession(role: TenantRole.manager, uid: managerUid),
);

Widget _record(String supplierId) => inSession(
  TenantSupplierRecordScreen(
    reader: FakeTenantReader.business(),
    writer: const _Writer(),
    supplierId: supplierId,
  ),
  controller: seedSession(role: TenantRole.manager, uid: managerUid),
);

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
