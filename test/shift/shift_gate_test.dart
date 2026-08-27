/// The till's shift gate, which had no test until the day it crashed a device.
///
/// **What every case here holds fixed is the ownership.** `main.dart` caches one
/// `TenantShiftController` per session and hands the same instance to the gate
/// and to the shift panel the gate pushes, so `sharedShiftControllerFactory` is
/// what these tests build with. Under a factory that mints one per call - which
/// is what this suite's neighbours used to pass, and what the screenshot harness
/// passed - none of these tests can fail, and the crash of 2026-08-27 walks
/// straight through: `TenantShiftPanel` disposed the shared controller on the
/// way out, and the next `addListener` threw *A TenantShiftController was used
/// after being disposed* over the whole route.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/reporting/reporting_currency.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/banner.dart';
import 'package:flutter_application_1/ui/routes.dart';
import 'package:flutter_application_1/ui/scaffold.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../support/shift_fakes.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveTenantShiftState state;
  late ShiftServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shift-gate-test-');
    Hive.init(directory.path);
    box = await openShiftTestBox();
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

  testWidgets('draws the till for a shift this device already has open', (
    tester,
  ) async {
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    await _pumpHome(tester, state, server);
    await _enterTill(tester);

    expect(find.byKey(_till), findsOneWidget);
    expect(find.byKey(const ValueKey('shift-gate-open')), findsNothing);
  });

  testWidgets('blocks the till with a modal when no shift is open', (
    tester,
  ) async {
    await _pumpHome(tester, state, server);
    await _enterTill(tester);

    expect(find.byKey(const ValueKey('shift-gate-blocked')), findsOneWidget);
    expect(find.byKey(const ValueKey('shift-gate-open')), findsOneWidget);
    expect(find.byKey(_till), findsNothing);
  });

  testWidgets('opening a shift from the modal reveals the till', (
    tester,
  ) async {
    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _tap(tester, const ValueKey('shift-gate-open'));

    expect(find.byKey(_till), findsOneWidget);
    expect(server.created, hasLength(1));
  });

  testWidgets('leaving the modal leaves the till rather than selling', (
    tester,
  ) async {
    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _tap(tester, const ValueKey('shift-gate-leave'));

    // Back on the home: the till went with the refusal to open a shift.
    expect(find.byKey(_home), findsOneWidget);
    expect(find.byKey(_till), findsNothing);
    expect(server.created, isEmpty);
  });

  // **The regression.** Nothing about this journey is unusual - a cashier looks
  // at the close surface and goes back to selling - and before 2026-08-27 the
  // second entry threw during build, because popping the shift manager disposed
  // the controller the whole session shares.
  testWidgets('a till re-entered after the shift manager still opens', (
    tester,
  ) async {
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    expect(find.byKey(_till), findsOneWidget);

    // Out through the exit dialog's *End shift*, which is what pushes the
    // manager, then straight back out of it without closing anything.
    await _openShiftManager(tester);
    await _pop(tester);

    // Back at the till, and out to the home.
    expect(find.byKey(_till), findsOneWidget);
    await _leaveTill(tester);
    await _tap(tester, const ValueKey('shift-exit-step-away'));
    expect(find.byKey(_home), findsOneWidget);

    // The second entry builds a fresh gate against the same session, which is
    // where a disposed controller is first touched.
    await _enterTill(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(_till), findsOneWidget);
  });

  // The journey the product owner reported, end to end.
  testWidgets(
    'an expired shift closes, a replacement opens, and the till returns',
    (tester) async {
      server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
      // Twenty-five hours, against the controller's 24-hour cap.
      await state.save(shiftRecord(openedAt: DateTime.utc(2026, 7, 30, 8)));

      await _pumpHome(tester, state, server);
      await _enterTill(tester);

      // No till: an expired shift may be closed and nothing else.
      expect(find.byKey(const ValueKey('shift-gate-expired')), findsOneWidget);
      expect(find.byKey(_till), findsNothing);

      // The expired screen pushes the manager, whose control opens the sheet
      // with the count already running.
      await _tap(tester, const ValueKey('shift-gate-close'));
      await _tap(tester, const ValueKey('close-shift'));
      await tester.enterText(find.byKey(const ValueKey('counted-cash')), '0');
      await _settle(tester);
      await _tap(tester, const ValueKey('close-shift-confirm'));

      // The gate notices there is no shift and raises its modal over the
      // manager - this is the "open a new shift" prompt in the same flow.
      expect(find.byKey(const ValueKey('shift-gate-open')), findsOneWidget);
      await _tap(tester, const ValueKey('shift-gate-open'));
      expect(tester.takeException(), isNull);

      // Leaving the manager returns to a till selling against the new shift.
      await _pop(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(_till), findsOneWidget);
      expect(server.created, hasLength(1));
      expect(
        await state.read(uid: 'user-a', tenantId: 'tenant-a'),
        isNotNull,
        reason: 'The replacement shift is this device\'s durable record.',
      );
    },
  );

  testWidgets('a refused open keeps the modal up and states the reason', (
    tester,
  ) async {
    // A shift this cashier has open in another business: the controller
    // refuses rather than opening a second one on the same device.
    await state.save(shiftRecord(tenantId: 'tenant-b', shiftId: 'shift-b'));

    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _tap(tester, const ValueKey('shift-gate-open'));

    expect(find.byKey(const ValueKey('shift-gate-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('shift-gate-open')), findsOneWidget);
    expect(find.byKey(_till), findsNothing);
    expect(server.created, isEmpty);
  });

  testWidgets('two taps on the modal open one shift', (tester) async {
    await _pumpHome(tester, state, server);
    await _enterTill(tester);

    final open = find.byKey(const ValueKey('shift-gate-open'));
    await tester.tap(open);
    // Inside the same frame, before the first open has published anything.
    await tester.pump();
    if (open.evaluate().isNotEmpty) await tester.tap(open, warnIfMissed: false);
    await _settle(tester);

    expect(server.created, hasLength(1));
    expect(find.byKey(_till), findsOneWidget);
  });

  testWidgets('a cancelled cash count leaves the shift open', (tester) async {
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _openShiftManager(tester);

    // Opening the sheet is what starts the count, so cancelling is the only
    // way back out of one without closing the shift.
    await _tap(tester, const ValueKey('close-shift'));
    expect(find.byKey(const ValueKey('counted-cash')), findsOneWidget);
    await _tap(tester, const ValueKey('cancel-cash-count'));

    final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
    expect(record, isNotNull);
    expect(record!.closeInProgress, isFalse);
    expect(server.updated, isEmpty);

    // And the till is still in service on the way out.
    await _pop(tester);
    expect(find.byKey(_till), findsOneWidget);
  });

  testWidgets('a close refused for want of a connection keeps the shift', (
    tester,
  ) async {
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    // Online to read the shift, offline by the time the close is attempted -
    // which is the shape of the failure, since closing is the one shift action
    // that cannot be done from a remembered record.
    var online = true;
    await _pumpHome(tester, state, server, isOnline: () async => online);
    await _enterTill(tester);
    await _openShiftManager(tester);
    await _tap(tester, const ValueKey('close-shift'));
    await tester.enterText(find.byKey(const ValueKey('counted-cash')), '0');
    await _settle(tester);

    online = false;
    await _tap(tester, const ValueKey('close-shift-confirm'));

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<ShiftBanner>(find.byType(ShiftBanner)).detail,
      shiftErrorMessage('close_needs_connection'),
    );
    expect(server.updated, isEmpty);
    expect(
      await state.read(uid: 'user-a', tenantId: 'tenant-a'),
      isNotNull,
      reason: 'A close that never reached the server has closed nothing.',
    );
  });

  testWidgets('popping the shift manager while the close is in flight', (
    tester,
  ) async {
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());

    await _pumpHome(tester, state, server);
    await _enterTill(tester);
    await _openShiftManager(tester);
    await _tap(tester, const ValueKey('close-shift'));
    await tester.enterText(find.byKey(const ValueKey('counted-cash')), '0');
    await _settle(tester);

    // The write is held open, so the route can be torn down underneath it.
    server.updateGate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('close-shift-confirm')));
    await tester.pump();
    await _pop(tester);
    server.updateGate!.complete();
    await _settle(tester);

    // The controller outlives the screen that started the close, so the answer
    // has somewhere to land rather than throwing into a disposed notifier.
    expect(tester.takeException(), isNull);
    expect(server.updated, hasLength(1));
    expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
  });

  testWidgets('switching business while a shift is being opened draws no till', (
    tester,
  ) async {
    final sessions = await _pumpHome(tester, state, server);
    await _enterTill(tester);

    server.createGate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('shift-gate-open')));
    // **Settled, not pumped once.** An open reads local state, checks the
    // network and looks for a shift to adopt before it writes anything; a
    // single frame switches business during that preamble, which the controller
    // rejects long before the interesting check. This runs it up to the held
    // write, so the switch lands where it has to.
    await _settle(tester);

    // The business changes underneath the open. Every publish in the
    // controller re-checks uid, tenant and epoch before it lands.
    sessions.open(uid: 'user-a', membership: shiftMembership('tenant-b'));
    server.createGate!.complete();
    await _settle(tester);

    expect(tester.takeException(), isNull);
    // **The write did land**, which is what stops this being a test that could
    // not fail: without the ownership re-check in `_publish` the controller
    // would report that shift as open and the gate would draw a till for a
    // business that has none.
    expect(server.created, hasLength(1));
    expect(server.created.single.$1, contains('tenant-a'));
    expect(
      find.byKey(_till),
      findsNothing,
      reason: 'A shift opened for one business may not draw another a till.',
    );
  });
}

/// *End shift* out of the till, which is what pushes the close panel.
Future<void> _openShiftManager(WidgetTester tester) async {
  await _leaveTill(tester);
  await _tap(tester, const ValueKey('shift-exit-end'));
  expect(find.byKey(const ValueKey('close-shift')), findsOneWidget);
}

const Key _home = ValueKey('gate-test-home');
const Key _till = ValueKey('gate-test-till');

/// The home, composed the way `tenant_routing_shell.dart` composes it: a button
/// that pushes a fresh gate under the session scope on every tap.
///
/// **A fresh gate per entry is the point**, not incidental. The gate takes its
/// controller in `didChangeDependencies`, so a second entry is the first place
/// a controller disposed during the first one is touched.
Future<TenantSessionController> _pumpHome(
  WidgetTester tester,
  HiveTenantShiftState state,
  ShiftServer server, {
  TenantShiftOnlineCheck? isOnline,
}) async {
  final sessions = TenantSessionController()
    ..open(uid: 'user-a', membership: shiftMembership('tenant-a'));
  addTearDown(sessions.dispose);
  final controllerFactory = sharedShiftControllerFactory(
    state,
    server,
    isOnline: isOnline,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: sessions,
        child: Builder(
          builder: (context) => Scaffold(
            key: _home,
            body: Center(
              child: TextButton(
                key: const ValueKey('enter-till'),
                onPressed: () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    builder: (_) => TenantSessionScope(
                      controller: sessions,
                      child: TenantShiftGate(
                        controllerFactory: controllerFactory,
                        shiftManagerBuilder: (context) => AppScaffold(
                          title: 'Close shift',
                          contentWidth: AppContentWidth.records,
                          body: TenantShiftPanel(
                            currency: TenantReportingCurrency.unknown,
                            controllerFactory: controllerFactory,
                          ),
                        ),
                        child: const Scaffold(
                          key: _till,
                          body: Center(child: Text('Till')),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('New sale'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return sessions;
}

Future<void> _enterTill(WidgetTester tester) =>
    _tap(tester, const ValueKey('enter-till'));

/// The system back gesture, which is the only way out of the till and which
/// `PopScope` turns into the exit dialog.
Future<void> _leaveTill(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

Future<void> _pop(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await _settle(tester);
}

/// Enough frames for a durable write, a canonical read and a route transition.
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
