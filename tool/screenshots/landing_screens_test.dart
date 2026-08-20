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
  late HivePrintJobQueue printJobs;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos-screenshots-');
    Hive.init(directory.path);
    shiftState = await openMemoryShiftState();
    shiftServer = FakeShiftServer();
    // Two receipts this device has not managed to send, so the home's card
    // states a condition rather than being a button. §4.4 names queue depth as
    // the example.
    printJobs = HivePrintJobQueue.fromBox(
      await Hive.openBox<dynamic>(HivePrintJobQueue.boxName),
    );
    for (final receipt in const <String>[
      'CT-A7F-20260818-0042',
      'CT-A7F-20260818-0043',
    ]) {
      await printJobs.enqueue(
        tenantId: seedTenantId,
        receiptNumber: receipt,
        endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
        bytes: const <int>[27, 64],
      );
    }
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
        printerConfigurationRoute: (reader) =>
            TenantPrinterConfigurationScreen(reader: reader),
        printerConfigurationRoles:
            TenantPrinterConfigurationPublisher.allowedRoles,
        printQueueRoute: () => TenantPrintQueueScreen(queue: printJobs),
        printQueueStatus: () {
          final listing = printJobs.pending();
          return PrinterFailureNotice.queueDepth(
            waiting: listing.jobs.length,
            unreadable: listing.unreadable,
          );
        },
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

  Widget staffDirectory() => inSession(
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
  );

  screenshotCase('13-staff-directory', build: staffDirectory);

  /// The same route as a manager, which is the only session it says anything to.
  ///
  /// **The heading this replaced was drawn for every role**, including the
  /// administrator above who is then offered `Invite staff` two lines under it,
  /// and no capture or test had ever looked at it. A page's standing is §2.1's,
  /// so it is an `info` `Callout` shown only to a session that can neither
  /// invite nor edit — and this is the picture of that session, which the
  /// admin-role case above cannot be.
  screenshotCase(
    '13c-staff-directory-read-only',
    build: () => inSession(
      TenantStaffDirectoryScreen(reader: FakeTenantReader.business()),
      controller: seedSession(role: TenantRole.manager, uid: managerUid),
    ),
  );

  /// The same route with one member's form open - the state `RecordItem.details`
  /// exists for, and the state nothing had ever photographed.
  ///
  /// It is worth its own picture because it is where a defect was hiding. The
  /// five forms this route opens each ended in a `Row` of two 48-high pills at
  /// `MainAxisAlignment.end`, which fitted the ~760 logical pixels a full-width
  /// card gave it and overflowed the ~340 a phone does. Nobody had opened one on
  /// a phone, and no capture had either.
  ///
  /// The member is the manager rather than the pending hire deliberately: an
  /// active accepted membership carries two actions, so both are inline at every
  /// band and one tap reaches the form at each viewport.
  screenshotCase(
    '13b-staff-directory-editing',
    build: staffDirectory,
    afterPump: (tester) async {
      final edit = find.byKey(const ValueKey('edit-staff-$managerUid'));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
    },
  );
}
