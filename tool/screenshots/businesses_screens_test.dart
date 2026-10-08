/// Evidence for *My businesses*: the frames `docs/design/businesses/` draws -
/// two businesses, one business, and the *Add business* sheet with the
/// receipt it will print as its masthead.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';

import 'fakes.dart';
import 'harness.dart';

const List<ScreenshotViewport> _phone = <ScreenshotViewport>[mobileViewport];

/// 9:00 in Nairobi on 8 October, so the other business's counted day is the
/// 7th, as the board prints it.
DateTime _morning() => DateTime.utc(2026, 10, 8, 6);

/// Answers the reads the page makes, for the boards' two businesses.
final class _Reader implements TenantDataReader {
  const _Reader();

  static final Map<String, Map<String, Object?>> _documents =
      <String, Map<String, Object?>>{
        'tenants/$seedTenantId/staff/cashier-amina': <String, Object?>{
          'uid': 'cashier-amina',
          'name': 'Amina',
        },
        'tenants/westlands-mart/configuration/branding': <String, Object?>{
          'companyName': 'Westlands Mart',
          'slogan': 'Your neighbourhood store',
        },
        'tenants/westlands-mart/configuration/checkout': <String, Object?>{
          'currency': 'KES',
        },
        'tenants/westlands-mart/daily_metrics/2026-10-07': <String, Object?>{
          'tenantId': 'westlands-mart',
          'businessDate': '2026-10-07',
          'sales': 12400,
          'profit': 3100,
          'transactions': 38,
          'transactionCount': 38,
          'shiftCount': 2,
          'incompleteCostLineCount': 0,
          'metricGeneration': 'gen-1',
          'sourceDirtyRevision': 1,
          'regeneratedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 8)),
          'netSales': 12400,
          'netProfit': 3100,
          'netTransactions': 38,
          'netIncompleteCostLineCount': 0,
          'returnedSales': 0,
          'returnCount': 0,
          'netMetricsVersion': 1,
        },
      };

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    final data = _documents[path];
    return data == null ? null : TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async => const <TenantQueryDocumentSnapshot>[];
}

final class _Callable implements RequestTenantCallable {
  const _Callable();

  @override
  Future<Object?> call(Map<String, Object?> payload) async => payload;
}

Widget _businesses({bool second = true}) {
  final open = seedMembership();
  final others = <TenantMembership>[
    if (second)
      seedMembership(
        tenantId: 'westlands-mart',
        tenantName: 'Westlands Mart',
        role: TenantRole.manager,
      ),
  ];
  return inSession(
    TenantBusinessesScreen(
      uid: ownerUid,
      membership: open,
      readMemberships: () => <TenantMembership>[open, ...others],
      reader: const _Reader(),
      openReceipt: const TenantOpenBusinessReceipt(
        name: seedTenantName,
        slogan: 'Fresh every morning',
        today: 'KES 910',
        sales: '3',
        currencyCode: 'KES',
        openShiftStaffIds: <String>['cashier-amina'],
      ),
      onEditDetails: () {},
      onSwitchTenant: (membership) async =>
          TenantSwitchResult.switched(membership),
      accountEmail: 'amina@devcorner.co.ke',
      requestIdentity: TenantRequestIdentity(
        uid: ownerUid,
        emailVerified: true,
        profile: const RootRoutingProfile(
          accountType: RootAccountType.tenantUser,
          globalStatus: 'active',
        ),
      ),
      requestTenantCallable: const _Callable(),
      clock: _morning,
    ),
  );
}

void main() {
  screenshotCase(
    'my-businesses',
    build: _businesses,
    fullPage: false,
    viewports: _phone,
  );

  screenshotCase(
    'my-businesses-one',
    build: () => _businesses(second: false),
    fullPage: false,
    viewports: _phone,
  );

  screenshotCase(
    'my-businesses-add',
    build: () => _businesses(second: false),
    fullPage: false,
    viewports: _phone,
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('add-business')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('tenant-request-name')),
          matching: find.byType(EditableText),
        ),
        'Mama Mboga Kilimani',
      );
      await tester.pumpAndSettle();
    },
  );
}
