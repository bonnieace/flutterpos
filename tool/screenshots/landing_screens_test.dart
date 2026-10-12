/// The route a person lands on once a business is open, and the staff screen
/// reached from it.
///
/// The landing route is built the way `lib/main.dart` builds it, with every
/// route and panel it injects, because which buttons appear there is a decision
/// the composition root makes rather than the screen.
library;

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uzapay_pos/audit/audit.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/sales/sales.dart';
import 'package:uzapay_pos/shift/shift.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
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
    // **One controller for both hosts, as `main.dart` composes it.** The gate
    // and the shift panel it pushes are handed the same instance there - the
    // composition root caches one per session - and a harness that built two
    // photographs a screen this app does not run. It also photographs a
    // lifetime this app does not have: the panel used to dispose what it was
    // given, which under one shared instance is the crash of 2026-08-27.
    final shifts = <TenantSessionController, TenantShiftController>{};
    TenantShiftController shiftControllerFactory(
      TenantSessionController controller,
    ) => shifts.putIfAbsent(
      controller,
      () => fakeShiftController(
        sessions: controller,
        localState: shiftState,
        server: shiftServer,
      ),
    );
    return TenantSessionScope(
      controller: sessions,
      child: TenantSafeLandingScreen(
        membership: seedMembership(role: role),
        reader: reader,
        onSignOut: () async {},
        isDefaultTenant: false,
        // What the old hub's bar shows on a wider screen: this device's
        // receipt code and that it is online.
        terminalLabel: 'CT-7F2',
        onlineCheck: () async => true,
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
        // Yesterday took more than today, so the greeting draws its fall:
        // the arrow, the percentage, and the word. `checkoutBusinessDate` is
        // what stamps a sale, so the two dates here are the two the home asks
        // for.
        salesTotalsCallable: FakeSalesComparisonCallable(
          salesByBusinessDate: <String, double>{
            checkoutBusinessDate(DateTime.now().toUtc()): 18400,
            checkoutBusinessDate(
              DateTime.now().toUtc().subtract(const Duration(days: 1)),
            ): 24800,
          },
        ),
        pendingCheckoutPanel: CheckoutPendingEvidencePanel(
          source: const FakeEvidenceSource(
            CheckoutEvidenceSummary(savedOffline: 2, confirmed: 11),
          ),
          alsoWaiting: (_) => printJobs.pending().jobs.length,
          notificationsRoute: (_) => TenantNotificationsScreen(
            tenantId: 'tenant-a',
            evidenceSource: const FakeEvidenceSource(
              CheckoutEvidenceSummary(savedOffline: 2, confirmed: 11),
            ),
            printQueue: printJobs,
          ),
        ),
        checkoutRoute: (_) => TenantShiftGate(
          controllerFactory: shiftControllerFactory,
          currency: TenantReportingCurrency.unknown,
          returnActions: returnActions,
          child: TenantCheckoutScreen(
            cache: FakeCatalogSource(),
            drafts: FakeDraftSink(),
          ),
        ),
        // **One Settings route that opens on an index**, where this harness
        // used to supply two of the three separate ones and then one tab strip.
        // The standings are read the same way the composition root reads
        // them - one bounded page of `configuration` - so the captures show
        // what a real index shows rather than a row with nothing on it.
        settingsRoute: (reader, initialSettingKey) => TenantSettingsScreen(
          initialSettingKey: initialSettingKey,
          standings: (session) => TenantSettingsStandingsRepository(
            session: session,
            reader: reader,
          ).read(collectionReader: reader),
          destinations: <TenantSettingsDestination>[
            TenantSettingsDestination(
              settingKey: 'currency',
              kind: TenantSettingKind.currency,
              icon: Icons.payments_outlined,
              allowedRoles: TenantCheckoutConfigurationPublisher.allowedRoles,
              builder: (_) => TenantCheckoutConfigurationPanel(reader: reader),
            ),
            TenantSettingsDestination(
              settingKey: 'printer',
              kind: TenantSettingKind.printer,
              icon: Icons.print_outlined,
              allowedRoles: TenantPrinterConfigurationPublisher.allowedRoles,
              ownsScroll: true,
              builder: (_) => TenantPrinterConfigurationPanel(reader: reader),
            ),
          ],
        ),
        settingsRoles: TenantCheckoutConfigurationPublisher.allowedRoles,
        // The listing as a figure, so the top bar's badge and its problem
        // colour are in the captures rather than left to be imagined.
        printQueueCount: () => printJobs.pending().jobs.length,
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
        memberName: 'Amina Wanjiru',
        shiftPanel: (currency, memberName) => TenantHomeShiftCard(
          controllerFactory: shiftControllerFactory,
          currency: currency,
          memberName: memberName,
          returnActions: returnActions,
        ),
      ),
    );
  }

  screenshotCase('10-business-home-owner', build: () => landing());

  // **The home at the old hub's own screenshot geometry**, which the cards were
  // measured off on 2026-10-10: 1232 wide at 1.5, so an old card and a new one
  // can be held side by side pixel for pixel. Admin, the old screenshot's role,
  // and owner, who gets the same four-across row.
  // **Every role at every width a tablet or a desktop can be, since
  // 2026-10-10**: the grid takes its columns from the width for every role,
  // after a cashier's cards came out 600 wide under the old per-role table.
  // The phone is here too, to show it is the launcher it always was.
  for (final (role, uid) in const <(TenantRole, String)>[
    (TenantRole.owner, ownerUid),
    (TenantRole.manager, ownerUid),
    (TenantRole.cashier, cashierUid),
  ]) {
    screenshotCase(
      '10d-business-home-grid-${role.wireValue}',
      build: () => landing(role: role, uid: uid),
      viewports: const <ScreenshotViewport>[
        _desktopWideViewport,
        webViewport,
        desktopNarrowViewport,
        tabletViewport,
        compactWideViewport,
        mobileViewport,
      ],
    );
  }

  for (final role in const <TenantRole>[TenantRole.admin, TenantRole.manager]) {
    screenshotCase(
      '10c-business-home-old-hub-${role.wireValue}',
      build: () => landing(role: role),
      viewports: const <ScreenshotViewport>[_oldHubViewport],
    );
  }

  screenshotCase(
    '11-business-home-cashier',
    build: () => landing(role: TenantRole.cashier, uid: cashierUid),
  );

  // **A cashier's open shift, on the home, since 2026-09-30.** The card at the
  // foot of the page, two hours and a quarter in.
  screenshotCase(
    '11b-business-home-cashier-shift-open',
    build: () => landing(role: TenantRole.cashier, uid: cashierUid),
    beforePump: () async {
      const age = Duration(hours: 2, minutes: 14);
      await shiftState.save(_openShiftRecord(uid: cashierUid, age: age));
      shiftServer.shifts['tenants/$seedTenantId/shifts/shift-open'] =
          _openShiftDocument(uid: cashierUid, age: age);
    },
    afterPump: (tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('home-shift-card')));
      await tester.pumpAndSettle();
    },
  );

  // The destinations, which left the body on 2026-08-23. Below `expanded` they
  // are behind the toolbar's hamburger, so the only way to photograph them on
  // a phone is to open the panel the way a person does.
  screenshotCase(
    '10b-business-home-destinations',
    build: () => landing(),
    afterPump: (tester) async {
      // At `expanded` there is no drawer and no hamburger - the destinations
      // are already beside the page in the frame's own column - so this
      // capture is the panel on the bands that have one and the ordinary page
      // on the band that does not.
      final hamburger = find.byTooltip(
        const DefaultMaterialLocalizations().openAppDrawerTooltip,
      );
      if (hamburger.evaluate().isEmpty) return;
      await tester.tap(hamburger);
      await tester.pumpAndSettle();
    },
  );

  // **The shift gate, which is where the shift lives as of 2026-08-25.** It
  // was a card on the home until then; the old app opened a shift on the way
  // into the till and this capture follows it there. Opening *New sale* with
  // no shift open is the whole of the state: a modal that cannot be dismissed,
  // over a till that is deliberately not drawn behind it.
  screenshotCase(
    '12-shift-gate-at-the-till',
    build: () => landing(),
    afterPump: (tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('start-checkout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-checkout')));
      await tester.pumpAndSettle();
    },
  );

  // **The twenty-four hour cap, which is the till's other closed state.**
  // A shift opened more than a day ago stops taking sales: the product owner
  // set that on 2026-08-26, and it is also what bounds how long a device may
  // trade offline, because counting a shift off needs the server. The screen
  // has to say both halves - why it stopped, and what is still safe - so this
  // captures it rather than leaving the state to the description alone.
  screenshotCase(
    '12c-shift-gate-past-the-cap',
    build: () => landing(),
    // The record has to exist before the gate reads it, which it does on the
    // way up rather than after the first frame.
    beforePump: () async {
      final openedAt = DateTime.now().toUtc().subtract(
        TenantShiftController.maximumShiftDuration + const Duration(hours: 1),
      );
      // The canonical shift too: `_settle` clears a confirmed record the
      // server has no shift for, which is correct and would otherwise leave
      // this capture showing *Start your shift*.
      shiftServer.shifts['tenants/$seedTenantId/shifts/shift-overrun'] =
          <String, Object?>{
            'shiftId': 'shift-overrun',
            'tenantId': seedTenantId,
            'staffId': ownerUid,
            'deviceId': seedDeviceId,
            'businessDate': checkoutBusinessDate(openedAt),
            'status': 'open',
            'startTime': Timestamp.fromDate(openedAt),
          };
      await shiftState.save(
        TenantShiftLocalRecord(
          uid: ownerUid,
          tenantId: seedTenantId,
          shiftId: 'shift-overrun',
          businessDate: checkoutBusinessDate(openedAt),
          deviceId: seedDeviceId,
          serverConfirmedOpen: true,
          closeInProgress: false,
          updatedAt: openedAt,
          openedAt: openedAt,
        ),
      );
    },
    afterPump: (tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('start-checkout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-checkout')));
      await tester.pumpAndSettle();
    },
  );

  /// The two ways out of the till, in the layout the pre-multitenancy app
  /// used.
  ///
  /// **Stepping away is the common answer and used to be the quiet one.** It
  /// was the outlined half of a button pair, beside a mint *End shift*; it is
  /// the first full-width row now, in the `ok` role, with *Close shift* under
  /// it. Captured because the point of the change is what it looks like.
  screenshotCase(
    '12d-leaving-the-register',
    build: () => landing(),
    beforePump: () async {
      await shiftState.save(_openShiftRecord());
      shiftServer.shifts['tenants/$seedTenantId/shifts/shift-open'] =
          _openShiftDocument();
    },
    afterPump: (tester) async {
      await _enterTill(tester);
      await _leaveTill(tester);
    },
  );

  /// The count itself, which had no capture at all before 2026-09-03 - which
  /// is part of why it drifted into a four-surface journey.
  screenshotCase(
    '12e-counting-the-drawer',
    build: () => landing(),
    beforePump: () async {
      await shiftState.save(_openShiftRecord());
      shiftServer.shifts['tenants/$seedTenantId/shifts/shift-open'] =
          _openShiftDocument();
    },
    afterPump: (tester) async {
      await _enterTill(tester);
      await _leaveTill(tester);
      await tester.tap(find.byKey(const ValueKey('shift-exit-end')));
      await _frames(tester);
    },
  );

  /// What a finished close says before the sheet goes.
  ///
  /// **The old app reported this in a snack bar over a screen that had already
  /// changed.** A cashier who has just counted a drawer is owed the figures
  /// they counted it against, on the surface they counted it on.
  screenshotCase(
    '12f-shift-closed',
    build: () => landing(),
    beforePump: () async {
      await shiftState.save(_openShiftRecord());
      shiftServer.shifts['tenants/$seedTenantId/shifts/shift-open'] =
          _openShiftDocument();
    },
    afterPump: (tester) async {
      await _enterTill(tester);
      await _leaveTill(tester);
      await tester.tap(find.byKey(const ValueKey('shift-exit-end')));
      await _frames(tester);
      await tester.enterText(
        find.byKey(const ValueKey('counted-cash')),
        '1250.00',
      );
      await _frames(tester);
      await tester.tap(find.byKey(const ValueKey('close-shift-confirm')));
      await _frames(tester);
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

  /// Opens one of the route's actions and settles, on whichever session and at
  /// whichever width the case is rendering under.
  ///
  /// **Shared by every form case below rather than spelled six times.** All five
  /// member forms are `RecordItem.details` reached from a row action, so the
  /// choreography is identical and only the key differs - and at 411 the action
  /// is below the fold, where `tap` warns rather than fails when it misses.
  ///
  /// **`underRecord` is not optional decoration; it is §4.3's overflow rule.**
  /// `RecordActionSet.inlineCountFor` draws **no** action inline on
  /// `stackedCards` once a record has more than three, and three on
  /// `twoColumnCards` - so a pending membership's four actions are all behind
  /// the menu at 411, and its fourth is behind the menu at 834 as well. The key
  /// then exists only as a `PopupMenuItem` in an overlay, which is why the
  /// finder is tried first and the menu opened only when it comes back empty.
  /// `13b` never had to do this because an accepted membership carries two
  /// actions and two are inline at every band.
  Future<void> Function(WidgetTester) openStaffAction(
    String key, {
    String? underRecord,
  }) => (tester) async {
    final scrollable = find.byType(Scrollable).first;
    Future<void> reach(Finder target) async {
      await tester.scrollUntilVisible(
        target,
        300,
        scrollable: scrollable,
        maxScrolls: 30,
      );
      // `scrollUntilVisible` stops when a widget is built rather than when it
      // is on screen, which is the trap the catalog's captures paid for twice.
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }

    final action = find.byKey(ValueKey(key));
    if (action.evaluate().isEmpty && underRecord != null) {
      final menu = find.descendant(
        of: find.byKey(ValueKey(underRecord)),
        matching: find.byIcon(Icons.more_vert),
      );
      await reach(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      // The item is in an overlay now, so it needs no scrolling of its own.
      await tester.tap(find.byKey(ValueKey(key)));
    } else {
      await reach(action);
      await tester.tap(action);
    }
    await tester.pumpAndSettle();
    // The form opened inside the record, so the record is what to frame - the
    // action that opened it may have been a menu item that no longer exists.
    if (underRecord != null) {
      await tester.ensureVisible(find.byKey(ValueKey(underRecord)));
      await tester.pumpAndSettle();
    }
  };

  screenshotCase(
    '13-staff-directory',
    build: staffDirectory,
    viewports: responsiveViewports,
  );

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
    viewports: responsiveViewports,
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
    afterPump: openStaffAction(
      'edit-staff-$managerUid',
      underRecord: 'staff-record-$managerUid',
    ),
    viewports: responsiveViewports,
  );

  // **The other five surfaces this route opens, none of which had a picture.**
  // `13b` photographed one of the six actions and the whole family had three
  // captures; the brief asks for pending, active, disabled, expired/invalid,
  // busy, validation and failure states, hard rule 5 asks for each of them in
  // the harness, and ST-055's fourth section draws a consequence dialog for
  // every one of the five below. Their behaviour is not thin - eleven test files
  // and 5,501 lines cover them - so what was missing was only ever the raster.
  //
  // Faith Njeri (`pending-dev`) is the subject of three of them because resend,
  // cancel and replace-email all require a pending membership with an
  // unaccepted invitation, and she is the one seeded member who has one. The
  // status change targets Brian Kimani rather than Peter Otieno, whom ST-055
  // draws: Peter is `adminUid` and therefore the acting session in these
  // captures, and a person deactivating themselves is not the picture this
  // state is for.
  screenshotCase(
    '13d-invite-staff',
    build: staffDirectory,
    afterPump: openStaffAction('invite-staff-open'),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '13e-resend-an-invitation',
    build: staffDirectory,
    afterPump: openStaffAction(
      'resend-staff-invitation-pending-dev',
      underRecord: 'staff-record-pending-dev',
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '13f-cancel-an-invitation',
    build: staffDirectory,
    afterPump: openStaffAction(
      'cancel-staff-invitation-pending-dev',
      underRecord: 'staff-record-pending-dev',
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '13g-replace-an-invitation-email',
    build: staffDirectory,
    afterPump: openStaffAction(
      'replace-staff-email-pending-dev',
      underRecord: 'staff-record-pending-dev',
    ),
    viewports: responsiveViewports,
  );

  screenshotCase(
    '13h-deactivate-a-member',
    build: staffDirectory,
    afterPump: openStaffAction(
      'set-staff-status-$cashierUid',
      underRecord: 'staff-record-$cashierUid',
    ),
    viewports: responsiveViewports,
  );
}

/// Pumps a bounded number of frames.
///
/// **Not `pumpAndSettle`.** The counted-cash field takes focus as the sheet
/// lands, and a blinking cursor schedules frames forever.
Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Leaves the till the way a person does, which `PopScope` turns into the exit
/// dialog rather than a pop.
Future<void> _leaveTill(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

/// Enters the till from the home, at whichever width the case is rendering
/// under - at 411 the launcher tile is below the fold.
Future<void> _enterTill(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('start-checkout')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('start-checkout')));
  await tester.pumpAndSettle();
}

/// A shift this device already has open, so the till draws rather than gating.
TenantShiftLocalRecord _openShiftRecord({
  String uid = ownerUid,
  Duration age = const Duration(hours: 3),
}) {
  final openedAt = DateTime.now().toUtc().subtract(age);
  return TenantShiftLocalRecord(
    uid: uid,
    tenantId: seedTenantId,
    shiftId: 'shift-open',
    businessDate: checkoutBusinessDate(openedAt),
    deviceId: seedDeviceId,
    serverConfirmedOpen: true,
    closeInProgress: false,
    updatedAt: openedAt,
    openedAt: openedAt,
  );
}

/// The canonical shift behind it. `_settle` clears a confirmed record the
/// server has no shift for, which would leave these captures on *Start your
/// shift*.
Map<String, Object?> _openShiftDocument({
  String uid = ownerUid,
  Duration age = const Duration(hours: 3),
}) {
  final openedAt = DateTime.now().toUtc().subtract(age);
  return <String, Object?>{
    'shiftId': 'shift-open',
    'tenantId': seedTenantId,
    'staffId': uid,
    'deviceId': seedDeviceId,
    'businessDate': checkoutBusinessDate(openedAt),
    'status': 'open',
    'startTime': Timestamp.fromDate(openedAt),
  };
}

/// The geometry of the developer's screenshot of the old hub: 1828 by 912
/// pixels at 1.5, and its cards put the window at 1232 logical wide - four of
/// them at 277 with 32 a side and 20 between.
const ScreenshotViewport _oldHubViewport = ScreenshotViewport(
  name: 'old-hub',
  size: Size(1232, 608),
  devicePixelRatio: 1.5,
);

/// A 1920 desktop, the widest window the home's grid is checked at.
const ScreenshotViewport _desktopWideViewport = ScreenshotViewport(
  name: 'desktop-wide',
  size: Size(1920, 1080),
  devicePixelRatio: 1,
);
