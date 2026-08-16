import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/checkout/checkout_tender.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_application_1/ui/banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const String _deviceA = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-31';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveTenantShiftState state;
  late _Server server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shift-panel-test-');
    Hive.init(directory.path);
    // An in-memory Hive box keeps every durable operation inside the widget
    // test's fake async zone; a file-backed box would never complete there.
    box = await Hive.openBox<dynamic>(
      HiveTenantShiftState.boxName,
      encryptionCipher: HiveAesCipher(_encryptionKey),
      crashRecovery: false,
      bytes: Uint8List(0),
    );
    state = HiveTenantShiftState.fromBox(
      box,
      clock: () => DateTime.utc(2026, 7, 31, 9),
    );
    server = _Server();
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

    await tester.tap(find.byKey(const ValueKey('open-shift')));
    await _settle(tester);
    expect(_heading(tester), 'Shift open');
    expect(server.created.single.$2['status'], 'open');

    await tester.tap(find.byKey(const ValueKey('start-cash-count')));
    await _settle(tester);
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

    await tester.enterText(
      find.byKey(const ValueKey('counted-cash')),
      '125000',
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

  testWidgets('restores an unfinished cash count after a restart', (
    tester,
  ) async {
    await state.save(_record(closeInProgress: true, countedCashMinor: 900));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

    await _pumpPanel(tester, state, server);

    expect(_heading(tester), 'Cash count unfinished');
    expect(find.byKey(const ValueKey('close-shift')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-shift')), findsNothing);
  });

  testWidgets('shows the confirmed sales summary during the count', (
    tester,
  ) async {
    await state.save(_record(closeInProgress: true, countedCashMinor: 900));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

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

    expect(_detail(tester), contains('Confirmed sales'));
    expect(
      find.text('Confirmed sales: 4 transactions, 98750 minor units.'),
      findsOneWidget,
    );
  });

  testWidgets('a single sale is counted in the singular', (tester) async {
    // The defect a real run found: this line read "Confirmed sales: 1
    // transactions". Every surface beside it - the differences list, the daily
    // summary, the corrections trail - already agreed one is singular.
    await state.save(_record(closeInProgress: true, countedCashMinor: 900));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

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

    expect(
      find.text('Confirmed sales: 1 transaction, 1 minor unit.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the expected cash beside the count', (tester) async {
    await state.save(_record(closeInProgress: true, countedCashMinor: 900));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: _summary(
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

      find.text(

        'Expected cash: 25000 minor units over 2 sales.'),
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
    await state.save(_record(closeInProgress: true));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: _summary(
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
    expect(
      find.text(
        'Expected cash: 0 minor units over 0 sales.'),
      findsOneWidget,
    );
  });

  testWidgets('states the takings that name no recognised method', (
    tester,
  ) async {
    await state.save(_record(closeInProgress: true));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: _summary(
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
        '2 sales name no recognised payment method, worth 5000 minor units. '
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
    await state.save(_record(closeInProgress: true));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: _summary(
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

    expect(

      find.text(

        'Expected cash: 1 minor unit over 1 sale.'),
      findsOneWidget,
    );
    await _openShiftSheet(tester);
    expect(
      find.text(
        '1 sale names no recognised payment method, worth 3000 minor units. '
        'It is inside the confirmed sales above but not in the expected cash.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a shift that recorded no method carries no disclaimer', (
    tester,
  ) async {
    await state.save(_record(closeInProgress: true));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: _summary(
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
    await state.save(_record(closeInProgress: true));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: _summary(
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
    expect(_detail(tester), contains('Confirmed sales'));
    await _openShiftSheet(tester);
    expect(find.byKey(const ValueKey('shift-expected-cash')), findsNothing);
    expect(find.textContaining('Expected cash'), findsNothing);
  });

  testWidgets('states unsynchronized sales instead of a cash figure', (
    tester,
  ) async {
    await state.save(_record(closeInProgress: true));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

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
    await state.save(_record(closeInProgress: true));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

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
    await state.save(_record(closeInProgress: true));
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

    await _pumpPanel(
      tester,
      state,
      server,
      sales: _summary(
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

    expect(_detail(tester), isNot(contains('not synchronized')));
    await _openShiftSheet(tester);
    expect(find.byKey(const ValueKey('shift-expected-cash')), findsOneWidget);
  });

  testWidgets('no cash figure appears before the count begins', (tester) async {
    await state.save(_record());
    server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();

    await _pumpPanel(tester, state, server);

    expect(_heading(tester), 'Shift open');
    await _openShiftSheet(tester);
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
              controllerFactory: (controller) =>
                  _controller(controller, state, server),
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
    await state.save(_record(tenantId: 'tenant-b', shiftId: 'shift-b'));

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
    server.shifts['tenants/tenant-a/shifts/shift-closed'] = _document(
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

    sessions.open(uid: 'user-a', membership: _membership('tenant-b'));
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
  _Server server, {
  ShiftSalesSummary sales = ShiftSalesSummary.empty,
  bool history = false,
}) async {
  final sessions = TenantSessionController()
    ..open(uid: 'user-a', membership: _membership('tenant-a'));
  addTearDown(sessions.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: TenantSessionScope(
        controller: sessions,
        child: Scaffold(
          body: TenantShiftPanel(
            historyReader: history ? _Reader(server) : null,
            controllerFactory: (controller) =>
                _controller(controller, state, server, sales: sales),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return sessions;
}

TenantShiftController _controller(
  TenantSessionController sessions,
  HiveTenantShiftState state,
  _Server server, {
  ShiftSalesSummary sales = ShiftSalesSummary.empty,
}) {
  var nextShift = 0;
  return TenantShiftController(
    sessionController: sessions,
    localState: state,
    salesLedger: _Ledger(sales),
    reader: _Reader(server),
    writer: FirebaseTenantShiftWriter.forTesting(
      isOnline: () async => true,
      create: server.create,
      update: server.update,
    ),
    deviceId: _deviceA,
    isOnline: () async => true,
    shiftIdFactory: () => 'shift-${++nextShift}',
    clock: () => DateTime.utc(2026, 7, 31, 9),
  );
}

final List<int> _encryptionKey = List<int>.generate(
  HiveTenantShiftState.encryptionKeyBytes,
  (index) => (index * 17) % 256,
);

Map<String, Object?> _document({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'shiftId': 'shift-a',
    'tenantId': 'tenant-a',
    'staffId': 'user-a',
    'deviceId': _deviceA,
    'businessDate': _businessDate,
    'status': 'open',
    'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 6)),
  };
  if (overrides != null) data.addAll(overrides);
  return data;
}

/// One closing summary with a tender split, as the ledger would have built it.
ShiftSalesSummary _summary({
  required int totalMinor,
  required int transactionCount,
  Map<CheckoutTender, ShiftTenderTotals> recorded =
      const <CheckoutTender, ShiftTenderTotals>{},
  ShiftTenderTotals unrecorded = ShiftTenderTotals.empty,
  ShiftTenderTotals unrecognised = ShiftTenderTotals.empty,
}) => ShiftSalesSummary(
  transactionCount: transactionCount,
  totalMinor: totalMinor,
  unsettledCount: 0,
  tenders: ShiftTenderSplit(
    recorded: recorded,
    unrecorded: unrecorded,
    unrecognised: unrecognised,
  ),
);

TenantShiftLocalRecord _record({
  String uid = 'user-a',
  String tenantId = 'tenant-a',
  String shiftId = 'shift-a',
  bool closeInProgress = false,
  int? countedCashMinor,
}) => TenantShiftLocalRecord(
  uid: uid,
  tenantId: tenantId,
  shiftId: shiftId,
  businessDate: _businessDate,
  deviceId: _deviceA,
  serverConfirmedOpen: true,
  closeInProgress: closeInProgress,
  countedCashMinor: countedCashMinor,
  updatedAt: DateTime.utc(2026, 7, 31, 9),
);

final class _Server {
  final Map<String, Map<String, Object?>> shifts =
      <String, Map<String, Object?>>{};
  final List<String> reads = <String>[];
  final List<(String, Map<String, Object?>)> created =
      <(String, Map<String, Object?>)>[];
  final List<(String, Map<String, Object?>)> updated =
      <(String, Map<String, Object?>)>[];

  Future<void> create(String path, Map<String, Object?> data) async {
    created.add((path, data));
    shifts[path] = <String, Object?>{
      ...data,
      'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 6)),
    };
  }

  Future<void> update(String path, Map<String, Object?> data) async {
    updated.add((path, data));
    final current = shifts[path];
    if (current == null) throw StateError('No shift at $path.');
    shifts[path] = <String, Object?>{
      ...current,
      ...data,
      'endTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 18)),
    };
  }
}

final class _Reader implements TenantDataReader {
  _Reader(this._server);

  final _Server _server;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    _server.reads.add(path);
    final data = _server.shifts[path];
    if (data == null) return null;
    return TenantDocumentSnapshot(path: path, data: data);
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    final matches = <TenantQueryDocumentSnapshot>[];
    final paths = _server.shifts.keys.toList()..sort();
    if (query.descending) {
      paths.sort((left, right) => right.compareTo(left));
    }
    for (final path in paths) {
      if (!path.startsWith('${query.collectionPath}/')) continue;
      final data = _server.shifts[path]!;
      if (!query.equalityFilters.entries.every(
        (filter) => data[filter.key] == filter.value,
      )) {
        continue;
      }
      matches.add(TenantQueryDocumentSnapshot(path: path, data: data));
      if (matches.length >= query.limit) break;
    }
    return matches;
  }
}

/// The panel renders whatever the controller publishes; the sale evidence
/// itself is proved in the ledger and controller suites.
final class _Ledger implements ShiftSalesLedger {
  const _Ledger(this.summary);

  final ShiftSalesSummary summary;

  @override
  Future<ShiftSalesSummary> summarize({
    required String uid,
    required String tenantId,
    required String shiftId,
  }) async => summary;
}

TenantMembership _membership(
  String tenantId, {
  TenantRole role = TenantRole.cashier,
}) => TenantMembership(
  tenantId: tenantId,
  tenantName: tenantId,
  tenantSlug: tenantId,
  role: role,
  membershipStatus: MembershipStatus.active,
  tenantStatus: TenantStatus.active,
  isOwner: false,
  mirrorVersion: 1,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverCanAccess: true,
  canonicalTenantExists: true,
  canonicalMembershipExists: true,
);

/// The one line the banner states beneath the standing.
///
/// **Seven facts became one line in §11 step 7**, which is what a banner is:
/// the status sentence, two "open elsewhere" warnings, the sales summary, the
/// unsynchronized-sales warning and the error line all competed for the same
/// row, and `ShiftBanner` carries whichever is loudest. So a test that used to
/// look for a keyed paragraph reads the line instead.
String _detail(WidgetTester tester) =>
    tester.widget<ShiftBanner>(find.byType(ShiftBanner)).detail;

/// The standing, in the words §9 requires beside the colour.
String _heading(WidgetTester tester) =>
    tester.widget<ShiftBanner>(find.byType(ShiftBanner)).heading;

/// Opens the sheet behind the banner, where every control that is not the next
/// step in the shift's lifecycle now lives.
Future<void> _openShiftSheet(WidgetTester tester) async {
  if (find.byKey(const ValueKey('tenant-shift-sheet')).evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(find.byKey(const ValueKey('tenant-shift-panel')));
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
