import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout_tender.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/banner.dart';
import 'package:flutter_application_1/reporting/reporting_currency.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../support/shift_fakes.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveTenantShiftState state;
  late ShiftServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shift-panel-test-');
    Hive.init(directory.path);
    // An in-memory Hive box keeps every durable operation inside the widget
    // test's fake async zone; a file-backed box would never complete there.
    box = await Hive.openBox<dynamic>(
      HiveTenantShiftState.boxName,
      encryptionCipher: HiveAesCipher(shiftEncryptionKey),
      crashRecovery: false,
      bytes: Uint8List(0),
    );
    state = HiveTenantShiftState.fromBox(
      box,
      clock: () => DateTime.utc(2026, 7, 31, 9),
    );
    server = ShiftServer();
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  testWidgets('opens, counts, and closes one shift from the panel', (
    tester,
  ) async {
    final sessions = await _pumpPanel(tester, state, server);

    expect(_heading(tester), 'No shift open');

    // One tap opens the shift. Only closing needs the sheet, because only
    // closing collects anything.
    await tester.tap(find.byKey(const ValueKey('open-shift')));
    await _settle(tester);
    expect(_heading(tester), 'Shift open');
    expect(server.created.single.$2['status'], 'open');

    // Opening the sheet on an open shift is what starts the count - there is
    // no `Start cash count` step any more.
    await _openShiftSheet(tester);
    expect(
      find.byKey(const ValueKey('counted-cash')),
      findsOneWidget,
      reason: 'the cash count must be entered before closing',
    );
    expect(
      (await TenantShiftSwitchStateSource(
        state,
      ).inspect(sessions.requireSession()))!.blocker,
      TenantSwitchBlocker.unfinishedCashCountOrShiftClose,
    );

    // Typed as money - what the drawer holds - and recorded as minor units.
    await tester.enterText(
      find.byKey(const ValueKey('counted-cash')),
      '1250.00',
    );
    // §8 rule 4: the banner says *Close shift* and so does the control in the
    // sheet that finishes it. This is already in the sheet, so it confirms.
    await _tapInSheet(tester, 'close-shift-confirm');
    // **`pumpAndSettle`, not the five-frame `_settle`.** Closing now dismisses
    // a route as well as writing, and a sheet's exit animation outlasts fifty
    // milliseconds - so the banner behind it was still reading the phase the
    // sheet was opened in.
    await tester.pumpAndSettle();

    expect(_heading(tester), 'No shift open');
    expect(server.updated.single.$2['closingCashMinor'], 125000);
    expect(
      (await TenantShiftSwitchStateSource(
        state,
      ).inspect(sessions.requireSession()))!.blocker,
      isNull,
    );
  });

  testWidgets('a cash count does not survive a restart', (tester) async {
    await state.save(shiftRecord(countedCashMinor: 900));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(tester, state, server);

    // The count lives only as long as the sheet it was taken in, so a restart
    // finds an ordinary open shift and a till that still sells - not a card
    // reporting a count nobody on this device can see.
    expect(_heading(tester), 'Shift open');
    expect(find.byKey(const ValueKey('close-shift')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-shift')), findsNothing);
  });

  testWidgets('shows the confirmed sales summary during the count', (
    tester,
  ) async {
    await state.save(shiftRecord(countedCashMinor: 900));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: const ShiftSalesSummary(
        transactionCount: 4,
        totalMinor: 98750,
        unsettledCount: 0,
      ),
    );

    // On the card, with no count started - which is the whole point of the
    // summary no longer being gated on one.
    expect(
      find.text('Confirmed sales: 4 transactions, 987.50.'),
      findsOneWidget,
    );

    // And again in the sheet, beside the drawer figure it is compared against.
    // Two matches, because the card is still mounted behind the sheet.
    await _openShiftSheet(tester);
    expect(
      find.text('Confirmed sales: 4 transactions, 987.50.'),
      findsNWidgets(2),
    );
  });

  testWidgets('a single sale is counted in the singular', (tester) async {
    // The defect a real run found: this line read "Confirmed sales: 1
    // transactions". Every surface beside it - the differences list, the daily
    // summary, the corrections trail - already agreed one is singular.
    await state.save(shiftRecord(countedCashMinor: 900));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: const ShiftSalesSummary(
        transactionCount: 1,
        totalMinor: 1,
        unsettledCount: 0,
      ),
    );

    expect(find.text('Confirmed sales: 1 transaction, 0.01.'), findsOneWidget);
  });

  testWidgets('shows the expected cash beside the count', (tester) async {
    await state.save(shiftRecord(countedCashMinor: 900));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: shiftSummary(
        totalMinor: 42500,
        transactionCount: 4,
        recorded: const <CheckoutTender, ShiftTenderTotals>{
          CheckoutTender.cash: ShiftTenderTotals(
            totalMinor: 25000,
            transactionCount: 2,
          ),
          CheckoutTender.mpesa: ShiftTenderTotals(
            totalMinor: 12500,
            transactionCount: 1,
          ),
          CheckoutTender.card: ShiftTenderTotals(
            totalMinor: 5000,
            transactionCount: 1,
          ),
        },
      ),
    );

    await _openShiftSheet(tester);

    expect(
      find.text('Expected cash: 250.00 over 2 sales.'),
      findsOneWidget,
      reason: 'a drawer holds the cash bucket, not the shift total',
    );
    expect(
      find.byKey(const ValueKey('shift-unattributed-tender')),
      findsNothing,
    );
    expect(
      find.text(checkoutTenderDisclaimer),
      findsOneWidget,
      reason: 'the same sentence every surface uses for a recorded tender',
    );
  });

  testWidgets('a shift with no cash sales still states the figure', (
    tester,
  ) async {
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: shiftSummary(
        totalMinor: 12500,
        transactionCount: 1,
        recorded: const <CheckoutTender, ShiftTenderTotals>{
          CheckoutTender.mpesa: ShiftTenderTotals(
            totalMinor: 12500,
            transactionCount: 1,
          ),
        },
      ),
    );

    // Being told to expect nothing is an answer; an absent line is not.
    await _openShiftSheet(tester);
    expect(find.text('Expected cash: 0.00 over 0 sales.'), findsOneWidget);
  });

  testWidgets('states the takings that name no recognised method', (
    tester,
  ) async {
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: shiftSummary(
        totalMinor: 9000,
        transactionCount: 3,
        recorded: const <CheckoutTender, ShiftTenderTotals>{
          CheckoutTender.cash: ShiftTenderTotals(
            totalMinor: 4000,
            transactionCount: 1,
          ),
        },
        unrecorded: const ShiftTenderTotals(
          totalMinor: 3000,
          transactionCount: 1,
        ),
        unrecognised: const ShiftTenderTotals(
          totalMinor: 2000,
          transactionCount: 1,
        ),
      ),
    );

    await _openShiftSheet(tester);
    expect(
      find.text(
        '2 sales name no recognised payment method, worth 50.00. '
        'They are inside the confirmed sales above but not in the expected '
        'cash.',
      ),
      findsOneWidget,
      reason: 'money left out of the cash figure is stated, never dropped',
    );
    expect(find.textContaining('unpaid'), findsNothing);
  });

  testWidgets('one cash sale and one unattributed sale read in the singular', (
    tester,
  ) async {
    // The same agreement rule applied to the drawer figure, including the
    // pronoun: one sale is "It is inside", not "They are inside".
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: shiftSummary(
        totalMinor: 3001,
        transactionCount: 2,
        recorded: const <CheckoutTender, ShiftTenderTotals>{
          CheckoutTender.cash: ShiftTenderTotals(
            totalMinor: 1,
            transactionCount: 1,
          ),
        },
        unrecorded: const ShiftTenderTotals(
          totalMinor: 3000,
          transactionCount: 1,
        ),
      ),
    );

    await _openShiftSheet(tester);

    expect(find.text('Expected cash: 0.01 over 1 sale.'), findsOneWidget);
    await _openShiftSheet(tester);
    expect(
      find.text(
        '1 sale names no recognised payment method, worth 30.00. '
        'It is inside the confirmed sales above but not in the expected cash.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a shift that recorded no method carries no disclaimer', (
    tester,
  ) async {
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: shiftSummary(
        totalMinor: 3000,
        transactionCount: 1,
        unrecorded: const ShiftTenderTotals(
          totalMinor: 3000,
          transactionCount: 1,
        ),
      ),
    );

    // Nothing on screen was recorded by a cashier, so the sentence claiming so
    // would be about nothing at all.
    expect(find.text(checkoutTenderDisclaimer), findsNothing);
    await _openShiftSheet(tester);
    expect(find.byKey(const ValueKey('shift-expected-cash')), findsOneWidget);
  });

  testWidgets('a split that does not add up shows no cash figure', (
    tester,
  ) async {
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: shiftSummary(
        totalMinor: 9000,
        transactionCount: 2,
        recorded: const <CheckoutTender, ShiftTenderTotals>{
          CheckoutTender.cash: ShiftTenderTotals(
            totalMinor: 4000,
            transactionCount: 1,
          ),
        },
      ),
    );

    // The takings themselves are unaffected; only the claim about how they were
    // paid is refused.
    await _openShiftSheet(tester);
    expect(find.byKey(const ValueKey('shift-confirmed-sales')), findsOneWidget);
    expect(find.byKey(const ValueKey('shift-expected-cash')), findsNothing);
    expect(find.textContaining('Expected cash'), findsNothing);
  });

  testWidgets('states unsynchronized sales instead of a cash figure', (
    tester,
  ) async {
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: const ShiftSalesSummary(
        transactionCount: 0,
        totalMinor: 0,
        unsettledCount: 2,
      ),
    );

    expect(
      find.text(
        '2 sales on this device are not synchronized yet and none of the '
        'figures here include them. The shift cannot be closed until they are.',
      ),
      findsOneWidget,
      reason: 'the run found this surface silent about them until Close failed',
    );
    // An expected-cash figure over an incomplete shift is a number the drawer
    // will not match, so it waits rather than misleading the count.
    await _openShiftSheet(tester);
    expect(find.byKey(const ValueKey('shift-expected-cash')), findsNothing);
  });

  testWidgets('one unsynchronized sale is described in the singular', (
    tester,
  ) async {
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: const ShiftSalesSummary(
        transactionCount: 1,
        totalMinor: 4000,
        unsettledCount: 1,
      ),
    );

    expect(
      find.text(
        '1 sale on this device is not synchronized yet and none of the figures '
        'here include it. The shift cannot be closed until they are.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a complete shift says nothing about synchronization', (
    tester,
  ) async {
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: shiftSummary(
        totalMinor: 4000,
        transactionCount: 1,
        recorded: const <CheckoutTender, ShiftTenderTotals>{
          CheckoutTender.cash: ShiftTenderTotals(
            totalMinor: 4000,
            transactionCount: 1,
          ),
        },
      ),
    );

    await _openShiftSheet(tester);
    expect(find.textContaining('not synchronized'), findsNothing);
    expect(find.byKey(const ValueKey('shift-expected-cash')), findsOneWidget);
  });

  testWidgets('no cash figure appears before the count begins', (tester) async {
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(tester, state, server);

    // The card never shows the figure: reaching it means opening the sheet,
    // and opening the sheet is what starts the count.
    expect(_heading(tester), 'Shift open');
    expect(find.byKey(const ValueKey('shift-expected-cash')), findsNothing);
  });

  testWidgets('renders nothing without an authorized session', (tester) async {
    final sessions = TenantSessionController();
    addTearDown(sessions.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TenantSessionScope(
          controller: sessions,
          child: Scaffold(
            body: TenantShiftPanel(
              currency: TenantReportingCurrency.unknown,
              controllerFactory: sharedShiftControllerFactory(state, server),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byKey(const ValueKey('tenant-shift-panel')), findsNothing);
    expect(find.byKey(const ValueKey('open-shift')), findsNothing);
    expect(server.reads, isEmpty);
  });

  testWidgets('shows the cross-business restriction to a cashier', (
    tester,
  ) async {
    await state.save(shiftRecord(tenantId: 'tenant-b', shiftId: 'shift-b'));

    await _pumpPanel(tester, state, server);
    await tester.tap(find.byKey(const ValueKey('open-shift')));
    await _settle(tester);

    // The error code is louder than the standing warning, so it is the line.
    expect(
      _detail(tester),
      contains('Close the open shift in the other business first.'),
    );
    expect(server.created, isEmpty);
  });

  testWidgets('reports unavailable shift state without internal details', (
    tester,
  ) async {
    await box.put('user-a:tenant-a', <String, Object?>{'schemaVersion': 99});

    await _pumpPanel(tester, state, server);

    expect(_heading(tester), 'Shift unavailable');
    expect(find.textContaining('malformed_shift_state'), findsNothing);
  });

  testWidgets('reaches the read-only shift history from the panel', (
    tester,
  ) async {
    server.shifts['tenants/tenant-a/shifts/shift-closed'] = shiftDocument(
      overrides: <String, Object?>{
        'shiftId': 'shift-closed',
        'status': 'closed',
        'endTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 18)),
        'closingCashMinor': 125000,
        'closingCash': 1250,
        'totalSalesMinor': 98750,
        'totalSales': 987.5,
        'transactionCount': 3,
      },
    );

    // The sheet is reachable only from `Close shift`, so the history it holds
    // needs an open shift to get to. That is the access gap this change
    // introduced and has not yet closed - see the panel's own note.
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(tester, state, server, history: true);
    await _openShiftSheet(tester);
    await _tapInSheet(tester, 'view-shift-history');
    await _settle(tester);

    expect(find.text('Shift history'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('shift-history-entry-shift-closed')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('shift-history-counted-shift-closed')),
          )
          .data,
      '1250.00',
      reason: 'the recorded figures are shown, never recomputed',
    );
  });

  testWidgets('the history route stays unreachable without a reader', (
    tester,
  ) async {
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(tester, state, server);

    await _openShiftSheet(tester);
    expect(find.byKey(const ValueKey('view-shift-history')), findsNothing);
  });

  testWidgets('a tenant switch replaces the surface instead of updating it', (
    tester,
  ) async {
    final sessions = await _pumpPanel(tester, state, server);
    await tester.tap(find.byKey(const ValueKey('open-shift')));
    await _settle(tester);
    expect(_heading(tester), 'Shift open');

    sessions.open(uid: 'user-a', membership: shiftMembership('tenant-b'));
    await _settle(tester);

    expect(_heading(tester), isNot('Shift open'));
    expect(_heading(tester), 'No shift open');
  });
}

/// Pumps a bounded number of frames.
///
/// `pumpAndSettle` cannot be used once the counted-cash field has focus: a
/// blinking cursor keeps scheduling frames, so the tree never settles.
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<TenantSessionController> _pumpPanel(
  WidgetTester tester,
  HiveTenantShiftState state,
  ShiftServer server, {
  ShiftSalesSummary sales = ShiftSalesSummary.empty,
  bool history = false,
}) async {
  final sessions = TenantSessionController()
    ..open(uid: 'user-a', membership: shiftMembership('tenant-a'));
  addTearDown(sessions.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: sessions,
        child: Scaffold(
          body: TenantShiftPanel(
            currency: TenantReportingCurrency.unknown,
            historyReader: history ? ShiftReader(server) : null,
            controllerFactory: sharedShiftControllerFactory(state, server, sales: sales),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return sessions;
}

/// A factory shaped like the composition root's: **one controller per session,
/// answered again on every call.**
///
/// `main.dart` caches on an `Expando` keyed by the session controller, so a
/// second host - the till's gate and this panel share one - is handed the
/// instance the first one is already listening to. A factory that minted a
/// fresh controller per call, which is what every test here used to pass,
/// models the ownership this app had before 2026-08-26 and cannot see the one
/// it has now break. It did not: `TenantShiftPanel` went on disposing a
/// controller it no longer owned for two days, and the whole suite stayed green
/// while a device showed *A TenantShiftController was used after being
/// disposed*.
/// look for a keyed paragraph reads the line instead.
String _detail(WidgetTester tester) =>
    tester.widget<ShiftBanner>(find.byType(ShiftBanner)).detail;

/// The standing, in the words §9 requires beside the colour.
///
/// **A shift with nothing to report is a bare control as of 2026-08-23**, and
/// its standing is the control's own label rather than a banner heading above
/// it: `Open shift` where none is open, `Start cash count` where one is. The
/// design's dashboard draws exactly that - `[ Start New Sale ] [ Open Shift ]`
/// - and a banner reading *SHIFT OPEN, a shift is open in this business* over
/// a button that says `Start cash count` was the same fact three times.
///
/// This reads whichever of the two is on screen, so every assertion below is
/// about the standing a person can see rather than about the widget carrying
/// it.
String _heading(WidgetTester tester) {
  final banner = find.byType(ShiftBanner);
  if (banner.evaluate().isNotEmpty) {
    return tester.widget<ShiftBanner>(banner).heading;
  }
  const standings = <String, String>{
    'open-shift': 'No shift open',
    'close-shift': 'Shift open',
  };
  for (final entry in standings.entries) {
    if (find.byKey(ValueKey(entry.key)).evaluate().isNotEmpty) {
      return entry.value;
    }
  }
  throw StateError('The shift panel drew neither a banner nor a control.');
}

/// Opens the sheet behind the banner, where every control that is not the next
/// step in the shift's lifecycle now lives.
Future<void> _openShiftSheet(WidgetTester tester) async {
  if (find.byKey(const ValueKey('tenant-shift-sheet')).evaluate().isNotEmpty) {
    return;
  }
  // **One way in as of 2026-08-23**: the card's own control, whichever of the
  // two it is. Both open the sheet, so the `Shift details` link this used to
  // fall back to no longer exists. Opening it on a shift that is open is also
  // what starts the cash count.
  // **Only `Close shift` opens the sheet as of 2026-08-23.** `Open shift`
  // opens the shift outright - it collects nothing, so a sheet in front of it
  // was a tap that asked no question.
  final control = find.byKey(const ValueKey('close-shift'));
  if (control.evaluate().isEmpty) {
    throw StateError('The shift panel drew no `Close shift` to open it with.');
  }
  await tester.tap(control);
  await _settle(tester);
}

/// Taps a control inside the shift sheet, after scrolling it into view.
///
/// **`ensureVisible` first**, which is `PLAN.md`'s standing trap from
/// 2026-08-14: a tap on a widget that is built but below the fold lands on
/// whatever is at that coordinate and **does not fail**. The sheet opens at its
/// `half` detent, so its last controls start off screen - and the first run of
/// this file without it reported a close that silently never reached the
/// server.
Future<void> _tapInSheet(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
