/// The open shift on the home, which is a cashier's and only while it is open.
///
/// Built with `sharedShiftControllerFactory`, as the gate's suite is, because
/// `main.dart` hands the card and the till's gate the same controller.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:uzapay_pos/reporting/reporting_currency.dart';
import 'package:uzapay_pos/shift/shift.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';

import '../support/shift_fakes.dart';

void main() {
  late Directory directory;
  late HiveTenantShiftState state;
  late ShiftServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shift-home-card-test-');
    Hive.init(directory.path);
    state = HiveTenantShiftState.fromBox(
      await openShiftTestBox(),
      clock: () => DateTime.utc(2026, 7, 31, 9),
    );
    server = ShiftServer();
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<void> openShift() async {
    server.shifts['tenants/tenant-a/shifts/shift-a'] = shiftDocument();
    await state.save(shiftRecord());
  }

  testWidgets("a cashier's open shift is on the home", (tester) async {
    await openShift();

    await _pump(tester, state, server);

    expect(find.byKey(_card), findsOneWidget);
    expect(find.byKey(const ValueKey('home-shift-status')), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    // Started 06:00 UTC, read at 08:14 UTC, and stated in the shop's clock.
    final opened = DateFormat('HH:mm').format(
      DateTime.utc(2026, 7, 31, 6).toLocal(),
    );
    expect(
      find.text('Opened $opened by Amina · 2h 14m'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-shift-close')), findsOneWidget);
  });

  testWidgets('no shift open draws nothing, not an empty card', (
    tester,
  ) async {
    await _pump(tester, state, server);

    expect(find.byKey(_card), findsNothing);
    expect(find.text('Close shift'), findsNothing);
  });

  testWidgets("another role's home draws nothing and reads no shift", (
    tester,
  ) async {
    // A manager with a shift of their own open: still the till's to show. The
    // card is a cashier's, and a home drawn for anyone else asks the shift
    // store nothing it did not ask before the card existed.
    await openShift();

    await _pump(tester, state, server, role: TenantRole.manager);

    expect(find.byKey(_card), findsNothing);
    expect(server.reads, isEmpty);
  });

  testWidgets('Close shift opens the count, and a close takes the card away', (
    tester,
  ) async {
    await openShift();
    await _pump(tester, state, server);

    await _tap(tester, const ValueKey('home-shift-close'));
    expect(find.byKey(const ValueKey('declared-cash')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('declared-cash')), '0');
    await _settle(tester);
    await _tap(tester, const ValueKey('close-shift-confirm'));
    expect(server.updated, hasLength(1));
    await _tap(tester, const ValueKey('shift-close-done'));

    expect(find.byKey(_card), findsNothing);
  });

  testWidgets('a cancelled count leaves the card and the shift as they were', (
    tester,
  ) async {
    await openShift();
    await _pump(tester, state, server);

    await _tap(tester, const ValueKey('home-shift-close'));
    await _tap(tester, const ValueKey('cancel-cash-count'));

    expect(find.byKey(_card), findsOneWidget);
    expect(server.updated, isEmpty);
  });

  group('the line under the title', () {
    final startedAt = DateTime(2026, 7, 31, 6, 30);

    test('names the time, the cashier and how long it has run', () {
      expect(
        homeShiftLine(
          startedAt: startedAt,
          memberName: 'Amina',
          now: startedAt.add(const Duration(hours: 2, minutes: 14)),
        ),
        'Opened 06:30 by Amina · 2h 14m',
      );
    });

    test('leaves out a name it does not have', () {
      expect(
        homeShiftLine(
          startedAt: startedAt,
          memberName: '  ',
          now: startedAt.add(const Duration(minutes: 9)),
        ),
        'Opened 06:30 · 9m',
      );
    });

    test('states no time for a shift the server has not dated', () {
      expect(
        homeShiftLine(
          startedAt: null,
          memberName: 'Amina',
          now: startedAt,
        ),
        'Opened by Amina',
      );
    });

    test('never runs backwards on a clock behind the server', () {
      expect(homeShiftRunningTime(const Duration(minutes: -3)), '0m');
      expect(homeShiftRunningTime(const Duration(hours: 26)), '26h 0m');
    });
  });
}

const Key _card = ValueKey('home-shift-card');

Future<void> _pump(
  WidgetTester tester,
  HiveTenantShiftState state,
  ShiftServer server, {
  TenantRole role = TenantRole.cashier,
}) async {
  final sessions = TenantSessionController()
    ..open(uid: 'user-a', membership: shiftMembership('tenant-a', role: role));
  addTearDown(sessions.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: sessions,
        child: Scaffold(
          body: SingleChildScrollView(
            child: TenantHomeShiftCard(
              controllerFactory: sharedShiftControllerFactory(state, server),
              currency: TenantReportingCurrency.unknown,
              memberName: 'Amina',
              clock: () => DateTime.utc(2026, 7, 31, 8, 14),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

/// Enough frames for a durable write, a canonical read and a sheet's spring.
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
