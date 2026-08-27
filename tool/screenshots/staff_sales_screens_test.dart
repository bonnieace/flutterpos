/// Focused evidence for the responsive Staff and unified Sales migrations.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/sales/sales.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'harness.dart';

FakeTenantReader _businessWithLongContent() {
  final reader = FakeTenantReader.business();
  const root = 'tenants/$seedTenantId';

  final pending = <String, Object?>{
    ...reader.collections['$root/staff']!['pending-dev']!,
    'name': 'Faith Wanjiku Njeri, Westlands Evening Operations',
    'email': 'faith.njeri.operations@devcorner.test',
  };
  reader.collections['$root/staff']!['pending-dev'] = pending;
  reader.documents['$root/staff/pending-dev'] = pending;

  final sourceSale = reader.collections['$root/sales']!['co-3']!;
  final items = <Map<String, Object?>>[
    for (final value in sourceSale['items']! as List<Object?>)
      <String, Object?>{...(value! as Map<String, Object?>)},
  ];
  items.first['name'] =
      'Family-size passion fruit sparkling drink, limited edition';
  reader.collections['$root/sales']!['co-3'] = <String, Object?>{
    ...sourceSale,
    'items': items,
  };
  return reader;
}

Widget _staff({required TenantRole role, required String uid}) {
  final reader = _businessWithLongContent();
  return inSession(
    TenantStaffDirectoryScreen(
      reader: reader,
      queryReader: reader,
      inviteCallable: FakeStaffCallable(),
      cancelInvitationCallable: FakeStaffCallable(),
      replaceEmailCallable: FakeStaffCallable(),
      resendCallable: FakeStaffCallable(),
      statusCallable: FakeStaffCallable(),
      updateCallable: FakeStaffCallable(),
    ),
    controller: seedSession(role: role, uid: uid),
  );
}

Widget _sales({required TenantRole role, required String uid}) {
  final reader = _businessWithLongContent();
  return inSession(
    TenantSalesReportScreen(
      reader: reader,
      reportReader: reader,
      totalsCallable: FakeCallable(seedSalesTotalsResponse()),
      returnActions: fakeReturnActions(),
    ),
    controller: seedSession(role: role, uid: uid),
  );
}

Future<void> _openMenu(WidgetTester tester, {required String key}) async {
  final menu = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(
    menu,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

void main() {
  screenshotCase(
    'staff-management',
    build: () => _staff(role: TenantRole.admin, uid: adminUid),
    viewports: responsiveViewports,
  );

  screenshotCase(
    'staff-management-read-only',
    build: () => _staff(role: TenantRole.manager, uid: managerUid),
    viewports: responsiveViewports,
  );

  screenshotCase(
    'staff-management-menu',
    build: () => _staff(role: TenantRole.admin, uid: adminUid),
    fullPage: false,
    afterPump: (tester) => _openMenu(tester, key: 'staff-actions-pending-dev'),
    viewports: responsiveViewports,
  );

  screenshotCase(
    'sales-report-management',
    build: () => _sales(role: TenantRole.manager, uid: managerUid),
    viewports: responsiveViewports,
  );

  screenshotCase(
    'sales-report-cashier',
    build: () => _sales(role: TenantRole.cashier, uid: cashierUid),
    viewports: responsiveViewports,
  );

  screenshotCase(
    'sales-report-menu',
    build: () => _sales(role: TenantRole.manager, uid: managerUid),
    fullPage: false,
    afterPump: (tester) => _openMenu(tester, key: 'sales-actions-co-3'),
    viewports: responsiveViewports,
  );

  screenshotCase(
    'sales-report-receipt',
    build: () => _sales(role: TenantRole.manager, uid: managerUid),
    afterPump: (tester) async {
      await tester.enterText(
        find.byKey(const ValueKey('sales-receipt-search')),
        '1',
      );
      await tester.tap(find.byKey(const ValueKey('sales-receipt-submit')));
      await tester.pumpAndSettle();
      final result = find.byKey(const ValueKey('sales-record-co-1'));
      await tester.scrollUntilVisible(
        result,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await tester.ensureVisible(result);
      await tester.pumpAndSettle();
    },
    viewports: responsiveViewports,
  );
}
