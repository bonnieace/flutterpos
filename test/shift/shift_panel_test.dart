import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
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

    expect(
      find.text('No shift is open in this business.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('open-shift')));
    await _settle(tester);
    expect(find.text('A shift is open in this business.'), findsOneWidget);
    expect(server.created.single.$2['status'], 'open');

    await tester.tap(find.byKey(const ValueKey('start-cash-count')));
    await _settle(tester);
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
    await tester.tap(find.byKey(const ValueKey('close-shift')));
    await _settle(tester);

    expect(find.text('No shift is open in this business.'), findsOneWidget);
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

    expect(
      find.text(
        'A cash count is unfinished. Finish it before switching business.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('close-shift')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-shift')), findsNothing);
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

    expect(
      find.byKey(const ValueKey('shift-other-tenant-open')),
      findsOneWidget,
    );
    expect(
      find.text('Close the open shift in the other business first.'),
      findsOneWidget,
    );
    expect(server.created, isEmpty);
  });

  testWidgets('reports unavailable shift state without internal details', (
    tester,
  ) async {
    await box.put('user-a:tenant-a', <String, Object?>{'schemaVersion': 99});

    await _pumpPanel(tester, state, server);

    expect(find.text('Shift state is unavailable.'), findsOneWidget);
    expect(find.textContaining('malformed_shift_state'), findsNothing);
  });

  testWidgets('a tenant switch replaces the surface instead of updating it', (
    tester,
  ) async {
    final sessions = await _pumpPanel(tester, state, server);
    await tester.tap(find.byKey(const ValueKey('open-shift')));
    await _settle(tester);
    expect(find.text('A shift is open in this business.'), findsOneWidget);

    sessions.open(uid: 'user-a', membership: _membership('tenant-b'));
    await _settle(tester);

    expect(find.text('A shift is open in this business.'), findsNothing);
    expect(find.text('No shift is open in this business.'), findsOneWidget);
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
  _Server server,
) async {
  final sessions = TenantSessionController()
    ..open(uid: 'user-a', membership: _membership('tenant-a'));
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
  return sessions;
}

TenantShiftController _controller(
  TenantSessionController sessions,
  HiveTenantShiftState state,
  _Server server,
) {
  var nextShift = 0;
  return TenantShiftController(
    sessionController: sessions,
    localState: state,
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

final class _Reader implements TenantDocumentReader {
  _Reader(this._server);

  final _Server _server;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    _server.reads.add(path);
    final data = _server.shifts[path];
    if (data == null) return null;
    return TenantDocumentSnapshot(path: path, data: data);
  }
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
