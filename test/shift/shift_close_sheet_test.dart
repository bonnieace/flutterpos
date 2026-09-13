/// The sheet that counts a drawer and closes a shift.
///
/// **It was `TenantShiftPanel`'s test until 2026-09-03**, when the panel and
/// the route that pushed it were deleted: closing a shift is one tap from the
/// till's exit dialog to this sheet, and the page in between held nothing the
/// sheet does not. What was asserted "on the card" is asserted in the sheet
/// here, because the sheet is where a cashier reads it now.
///
/// The cases about a *refused open* and about *unavailable* shift state moved
/// to `shift_gate_test.dart`, which owns the surfaces that report them.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout_tender.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/reporting/reporting_currency.dart';
import 'package:flutter_application_1/ui/banner.dart';
import 'package:flutter_application_1/ui/buttons.dart';
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

  testWidgets('opens, counts, and closes one shift', (
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
    // no `Start cash count` step any more, and no page in front of it either.
    await _openShiftSheet(tester);
    for (final tender in CheckoutTender.values) {
      expect(
        find.byKey(ValueKey('declared-${tender.wireValue}')),
        findsOneWidget,
        reason: 'every payment method must be declared before closing',
      );
    }
    expect(
      (await TenantShiftSwitchStateSource(
        state,
      ).inspect(sessions.requireSession()))!.blocker,
      TenantSwitchBlocker.unfinishedCashCountOrShiftClose,
    );

    // Typed as money - what the till holds - and recorded as minor units. The
    // card box is left empty on purpose: an empty box is zero, because a shift
    // that took no card must not need a typed nought to close.
    await tester.enterText(
      find.byKey(const ValueKey('declared-cash')),
      '1250.00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('declared-mpesa')),
      '340.50',
    );
    // §8 rule 4: the banner says *Close shift* and so does the control in the
    // sheet that finishes it. This is already in the sheet, so it confirms.
    await _tapInSheet(tester, 'close-shift-confirm');

    // **The close reports here, on the surface it was taken on.** It used to
    // pop the sheet and then dispatch, which put the server's answer on a card
    // behind a surface that was already gone.
    expect(find.text('Shift closed'), findsOneWidget);
    // Only what was typed is read back. The figure it was measured against is
    // deliberately absent here too: a declaration that prints the expected
    // total on submission is blind exactly once.
    expect(find.text('Cash: 1250.00.'), findsOneWidget);
    expect(find.text('M-Pesa: 340.50.'), findsOneWidget);
    expect(find.text('Card: 0.00.'), findsOneWidget);
    expect(find.byKey(const ValueKey('shift-close-sales')), findsNothing);
    await _tapInSheet(tester, 'shift-close-done');

    expect(_heading(tester), 'No shift open');
    expect(server.updated.single.$2['closingCashMinor'], 125000);
    expect(server.updated.single.$2['declaredCashMinor'], 125000);
    expect(server.updated.single.$2['declaredMpesaMinor'], 34050);
    expect(server.updated.single.$2['declaredCardMinor'], 0);
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

  testWidgets('the sheet never states a figure the drawer is measured against', (
    tester,
  ) async {
    // **The regression test for the whole control.** Every one of these keys
    // used to be on this surface, and each of them told a cashier the answer
    // before they were asked the question. The declaration is worth taking only
    // while none of them is here - so this asserts their absence against the
    // richest possible shift: complete, with a full split, every method used,
    // and money the sales could not attribute.
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: shiftSummary(
        totalMinor: 72500,
        transactionCount: 7,
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
        unrecorded: const ShiftTenderTotals(
          totalMinor: 30000,
          transactionCount: 3,
        ),
      ),
    );

    // Before the sheet, while the count runs, and after a close: three phases,
    // one rule.
    expect(find.byKey(const ValueKey('shift-expected-cash')), findsNothing);
    expect(find.byKey(const ValueKey('shift-confirmed-sales')), findsNothing);

    await _openShiftSheet(tester);
    expect(find.byKey(const ValueKey('shift-expected-cash')), findsNothing);
    expect(find.byKey(const ValueKey('shift-confirmed-sales')), findsNothing);
    expect(find.byKey(const ValueKey('shift-unattributed-tender')), findsNothing);
    expect(find.textContaining('Expected cash'), findsNothing);
    expect(find.textContaining('Confirmed sales'), findsNothing);
    // The disclaimer is now always present, because the sheet always names
    // three payment methods.
    expect(find.text(checkoutTenderDisclaimer), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('declared-cash')),
      '250.00',
    );
    await _tapInSheet(tester, 'close-shift-confirm');

    expect(find.text('Shift closed'), findsOneWidget);
    expect(find.byKey(const ValueKey('shift-close-sales')), findsNothing);
    expect(find.textContaining('Confirmed sales'), findsNothing);
    expect(find.textContaining('Expected cash'), findsNothing);
  });

  testWidgets('an empty box is zero and a misspelling is refused', (
    tester,
  ) async {
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(tester, state, server);
    await _openShiftSheet(tester);

    // Not an amount. The fault is named against the box that has it and
    // nothing is dispatched - a spelling is not a range.
    await tester.enterText(find.byKey(const ValueKey('declared-cash')), '..');
    await _tapInSheet(tester, 'close-shift-confirm');
    expect(find.text('Enter an amount, like 1250.50.'), findsOneWidget);
    expect(server.updated, isEmpty);

    // Corrected, with the other two boxes left empty.
    await tester.enterText(
      find.byKey(const ValueKey('declared-cash')),
      '80.00',
    );
    await _tapInSheet(tester, 'close-shift-confirm');

    expect(find.text('Shift closed'), findsOneWidget);
    expect(server.updated.single.$2['declaredCashMinor'], 8000);
    expect(server.updated.single.$2['declaredMpesaMinor'], 0);
    expect(server.updated.single.$2['declaredCardMinor'], 0);
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

    // **Beside the control it blocks**, which is where a real device run found
    // this surface silent about them until `Close shift` failed.
    await _openShiftSheet(tester);
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

    await _openShiftSheet(tester);
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
    // The blocker is the only thing this sheet says about the shift's sales,
    // so a shift with none to report says nothing at all about them.
    expect(find.byKey(const ValueKey('shift-unsynchronized-sales')), findsNothing);
  });

  testWidgets('the declaration is asked for only once the sheet is open', (
    tester,
  ) async {
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(tester, state, server);

    // Reaching the boxes means opening the sheet, and opening the sheet is
    // what starts the count.
    expect(_heading(tester), 'Shift open');
    expect(find.byKey(const ValueKey('declared-cash')), findsNothing);
  });

  testWidgets('reaches the read-only shift history from the sheet', (
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
    // needs an open shift to get to. That is a standing access gap rather than
    // a new one - the panel this replaced had the same shape.
    await state.save(shiftRecord());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();

    await _pumpPanel(tester, state, server, history: true);
    await _openShiftSheet(tester);
    await _tapInSheet(tester, 'view-shift-history');
    await _settle(tester);
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
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
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
          body: _ShiftHost(
            controllerFactory: sharedShiftControllerFactory(
              state,
              server,
              sales: sales,
            ),
            historyReader: history ? ShiftReader(server) : null,
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return sessions;
}

/// The till, reduced to the two controls the gate offers a shift.
///
/// **It stands in for `TenantShiftGate`, not for the deleted panel.** The gate
/// opens a shift from its blocking modal and opens this sheet from its exit
/// dialog; both are one tap on a live `TenantShiftController`, and this is that
/// pair with the routing taken out. Nothing here draws anything the sheet is
/// asserted on - the phase is readable only from which of the two controls is
/// on screen, so a case that reads a figure has to open the sheet to find it.
final class _ShiftHost extends StatefulWidget {
  const _ShiftHost({required this.controllerFactory, this.historyReader});

  final TenantShiftControllerFactory controllerFactory;
  final TenantDataReader? historyReader;

  @override
  State<_ShiftHost> createState() => _ShiftHostState();
}

final class _ShiftHostState extends State<_ShiftHost> {
  TenantSessionController? _sessions;
  TenantShiftController? _shifts;
  String? _sessionKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sessions = TenantSessionScope.of(context);
    final session = sessions.session;
    // **Keyed on the session, not on the controller.** The shell reopens the
    // same `TenantSessionController` against a new business, so an identity
    // check on the controller alone would never notice a switch - which is
    // what `TenantRouteGuard` did for the deleted panel and what this stands
    // in for.
    final key = session == null
        ? null
        : '${session.uid}:${session.tenantId}:${session.epoch}';
    if (identical(sessions, _sessions) && key == _sessionKey) return;
    _sessions = sessions;
    _sessionKey = key;
    // Exchanged, never disposed: the controller belongs to the session, which
    // is the ownership `sharedShiftControllerFactory` exists to model.
    final shifts = _shifts = widget.controllerFactory(sessions);
    if (session != null) unawaited(shifts.restore(session));
  }

  @override
  Widget build(BuildContext context) {
    final shifts = _shifts;
    if (shifts == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: shifts,
      builder: (context, _) => Center(
        child: switch (shifts.state.phase) {
          // A shift closed on this device offers nothing: it is finished
          // here and sends itself.
          TenantShiftPhase.closedPending => const SizedBox.shrink(),
          TenantShiftPhase.none => AppButton(
            key: const ValueKey('open-shift'),
            label: 'Open shift',
            onPressed: () => unawaited(shifts.openShift()),
          ),
          TenantShiftPhase.open ||
          TenantShiftPhase.closing ||
          TenantShiftPhase.expired => AppButton(
            key: const ValueKey('close-shift'),
            label: 'Close shift',
            onPressed: () {
              final session = _sessions?.session;
              if (session == null) return;
              unawaited(
                showShiftCloseSheet(
                  context,
                  shifts: shifts,
                  session: session,
                  currency: TenantReportingCurrency.unknown,
                  historyReader: widget.historyReader,
                ),
              );
            },
          ),
          TenantShiftPhase.unknown ||
          TenantShiftPhase.unavailable => const SizedBox.shrink(),
        },
      ),
    );
  }
}

/// A factory shaped like the composition root's: **one controller per session,
/// answered again on every call.**
/// (Documented on `sharedShiftControllerFactory` in `shift_fakes.dart`.)
///
/// `main.dart` caches on an `Expando` keyed by the session controller, so a
/// second host - the till's gate and this sheet share one - is handed the
/// instance the first one is already listening to. A factory that minted a
/// fresh controller per call, which is what every test here used to pass,
/// models the ownership this app had before 2026-08-26 and cannot see the one
/// it has now break. It did not: the shift panel went on disposing a
/// controller it no longer owned for two days, and the whole suite stayed green
/// while a device showed *A TenantShiftController was used after being
/// disposed*.

/// The standing, in the words §9 requires beside the colour.
///
/// **The banner moved into the sheet on 2026-09-03**, with everything else the
/// deleted card carried. While the sheet is up it is the standing; while it is
/// not, the standing is which of the till's two controls is on screen.
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
  throw StateError('The till drew neither a banner nor a control.');
}

/// Opens the sheet behind the banner, where every control that is not the next
/// step in the shift's lifecycle now lives.
Future<void> _openShiftSheet(WidgetTester tester) async {
  if (find.byKey(const ValueKey('tenant-shift-sheet')).evaluate().isNotEmpty) {
    return;
  }
  // **One tap, and only `Close shift`.** `Open shift` opens the shift outright
  // - it collects nothing, so a sheet in front of it was a tap that asked no
  // question. Opening this one is also what starts the cash count.
  final control = find.byKey(const ValueKey('close-shift'));
  if (control.evaluate().isEmpty) {
    throw StateError('The till drew no `Close shift` to open it with.');
  }
  await tester.tap(control);
  await _settle(tester);
  await _settle(tester);
}

/// Taps a control inside the shift sheet, after scrolling it into view.
///
/// **`ensureVisible` first**, which is the standing trap from 2026-08-14: a tap
/// on a widget that is built but below the fold lands on whatever is at that
/// coordinate and **does not fail**. The first run of this file without it
/// reported a close that silently never reached the server.
///
/// **`_settle` rather than `pumpAndSettle`**: the counted-cash field takes
/// focus the moment the sheet opens, and a blinking cursor keeps scheduling
/// frames forever.
Future<void> _tapInSheet(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
  await _settle(tester);
}
