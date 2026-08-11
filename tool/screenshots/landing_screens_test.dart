/// The route a person lands on once a business is open, and the staff screen
/// reached from it.
///
/// The landing route is built the way `lib/main.dart` builds it, with every
/// route and panel it injects, because which buttons appear there is a decision
/// the composition root makes rather than the screen.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/audit/audit.dart';
import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_application_1/inventory/inventory.dart';
import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/sales/sales.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'fakes.dart';
import 'harness.dart';

void main() {
  late Directory directory;
  late HiveTenantShiftState shiftState;
  late FakeShiftServer shiftServer;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos-screenshots-');
    Hive.init(directory.path);
    shiftState = await openMemoryShiftState();
    shiftServer = FakeShiftServer();
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Widget landing({TenantRole role = TenantRole.owner, String uid = ownerUid}) {
    final reader = FakeTenantReader.business();
    final sessions = seedSession(role: role, uid: uid);
    final returnActions = fakeReturnActions();
    return TenantSessionScope(
      controller: sessions,
      child: TenantSafeLandingScreen(
        membership: seedMembership(role: role),
        reader: reader,
        onSignOut: () async {},
        isDefaultTenant: false,
        switchCandidates: <TenantMembership>[
          seedMembership(role: role),
          seedMembership(
            tenantId: 'westlands-mart',
            tenantName: 'Westlands Mart',
            role: TenantRole.manager,
          ),
        ],
        onSwitchTenant: (membership) async =>
            TenantSwitchResult.switched(membership),
        shiftPanel: TenantShiftPanel(
          historyReader: reader,
          returnActions: returnActions,
          controllerFactory: (controller) => fakeShiftController(
            sessions: controller,
            localState: shiftState,
            server: shiftServer,
          ),
        ),
        pendingCheckoutPanel: CheckoutPendingEvidencePanel(
          source: const FakeEvidenceSource(
            CheckoutEvidenceSummary(savedOffline: 2, confirmed: 11),
          ),
        ),
        checkoutRoute: (_) =>
            TenantCheckoutScreen(cache: FakeCatalogSource(), drafts: FakeDraftSink()),
        checkoutConfigurationRoute: (reader) =>
            TenantCheckoutConfigurationScreen(reader: reader),
        checkoutConfigurationRoles:
            TenantCheckoutConfigurationPublisher.allowedRoles,
        catalogManagementRoute: (reader) =>
            TenantCatalogManagementScreen(reader: reader),
        catalogManagementRoles: TenantCatalogManagementRepository.allowedRoles,
        dailySummaryRoute: (reader) => TenantDailySummaryScreen(reader: reader),
        dailySummaryRoles: TenantDailyMetricsRepository.allowedRoles,
        receiptLookupRoute: (reader) =>
            TenantReceiptLookupScreen(reader: reader),
        receiptLookupRoles: TenantReceiptLookupRepository.allowedRoles,
        productStockRoute: (reader, product) =>
            TenantProductStockScreen(reader: reader, product: product),
        productStockRoles: TenantProductStockRepository.allowedRoles,
        stockAdjustmentFeedRoute: (reader) =>
            TenantStockAdjustmentFeedScreen(reader: reader),
        stockAdjustmentFeedRoles:
            TenantStockAdjustmentFeedRepository.allowedRoles,
        stockMovementFeedRoute: (_) => TenantStockMovementFeedScreen(
          reader: reader,
          // The collection-group boundary is a genuinely wider read, so the
          // landing route injects it separately, exactly as `main.dart` does.
          groupReader: reader,
        ),
        stockMovementFeedRoles: TenantStockMovementFeedRepository.allowedRoles,
        auditLogRoute: (reader) => TenantAuditLogScreen(reader: reader),
        auditLogRoles: TenantAuditLogRepository.allowedRoles,
      ),
    );
  }

  screenshotCase('10-business-home-owner', build: () => landing());

  screenshotCase(
    '11-business-home-cashier',
    build: () => landing(role: TenantRole.cashier, uid: cashierUid),
  );

  screenshotCase(
    '12-shift-open-and-counted',
    build: () => landing(),
    afterPump: (tester) async {
      await tester.tap(find.byKey(const ValueKey('open-shift')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-cash-count')));
    },
  );

  screenshotCase(
    '13-staff-directory',
    build: () => inSession(
      TenantStaffDirectoryScreen(
        reader: FakeTenantReader.business(),
        inviteCallable: FakeStaffCallable(),
        cancelInvitationCallable: FakeStaffCallable(),
        replaceEmailCallable: FakeStaffCallable(),
        resendCallable: FakeStaffCallable(),
        statusCallable: FakeStaffCallable(),
        updateCallable: FakeStaffCallable(),
      ),
      controller: seedSession(role: TenantRole.admin, uid: adminUid),
    ),
  );
}
