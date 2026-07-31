import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
  late TenantSessionController sessions;
  late _Server server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shift-controller-test-');
    Hive.init(directory.path);
    box = await _openBox();
    state = HiveTenantShiftState.fromBox(
      box,
      clock: () => DateTime.utc(2026, 7, 31, 9),
    );
    server = _Server();
    sessions = TenantSessionController()
      ..open(uid: 'user-a', membership: _membership('tenant-a'));
  });

  tearDown(() async {
    sessions.dispose();
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  group('opening a shift', () {
    test('writes one canonical shift and confirms it by reading back', () async {
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.phase, TenantShiftPhase.open);
      expect(result.errorCode, isNull);
      expect(server.created.single.$1, 'tenants/tenant-a/shifts/shift-1');
      expect(server.created.single.$2['staffId'], 'user-a');
      expect(server.created.single.$2['status'], 'open');
      expect(server.created.single.$2['deviceId'], _deviceA);
      expect(server.created.single.$2['businessDate'], _businessDate);
      final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(record!.shiftId, 'shift-1');
      expect(record.serverConfirmedOpen, isTrue);
      expect(record.closeInProgress, isFalse);
    });

    test('refuses a second shift while one is already open', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();

      final second = await controller.openShift();

      expect(second.errorCode, 'shift_already_open');
      expect(second.phase, TenantShiftPhase.open);
      expect(server.created.length, 1);
    });

    test('never writes while offline', () async {
      final controller = _controller(sessions, state, server, online: false);

      final result = await controller.openShift();

      expect(result.phase, TenantShiftPhase.unknown);
      expect(result.errorCode, 'offline');
      expect(server.created, isEmpty);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('settles an unacknowledged create by canonical read', () async {
      server.failCreateWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      // Only a successful canonical read may decide that nothing was written.
      expect(result.phase, TenantShiftPhase.none);
      expect(result.errorCode, 'unavailable');
      expect(server.reads, <String>['tenants/tenant-a/shifts/shift-1']);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('keeps evidence when the create outcome cannot be settled', () async {
      server.failCreateWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      server.failReadWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      // The server may still hold the shift, so the durable intent survives
      // for the next canonical settlement.
      expect(result.phase, TenantShiftPhase.unavailable);
      final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(record!.shiftId, 'shift-1');
      expect(record.serverConfirmedOpen, isFalse);
    });

    test('discards a result after the session changed mid-write', () async {
      final controller = _controller(
        sessions,
        state,
        server,
        beforeCreate: () => sessions.open(
          uid: 'user-a',
          membership: _membership('tenant-b'),
        ),
      );

      final result = await controller.openShift();

      expect(result.errorCode, 'session_changed');
      expect(controller.state.phase, TenantShiftPhase.unknown);
    });
  });

  group('restoring a shift', () {
    test('re-reads the canonical shift instead of trusting local state', () async {
      await state.save(_record());
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.open);
      expect(restored.shift!.id, 'shift-a');
      expect(server.reads, <String>['tenants/tenant-a/shifts/shift-a']);
    });

    test('clears local state when the server already closed the shift', () async {
      await state.save(_record(closeInProgress: true, countedCashMinor: 5000));
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document(
        overrides: <String, Object?>{'status': 'closed'},
      );
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.none);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('clears local state when no canonical shift exists', () async {
      await state.save(_record());
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.none);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('refuses a shift that belongs to another cashier', () async {
      await state.save(_record());
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document(
        overrides: <String, Object?>{'staffId': 'user-b'},
      );
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.unavailable);
      expect(restored.errorCode, 'foreign_shift');
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNotNull);
    });

    test('reports only local facts while offline', () async {
      await state.save(_record(closeInProgress: true, countedCashMinor: 900));
      final controller = _controller(sessions, state, server, online: false);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.closing);
      expect(restored.errorCode, 'offline');
      expect(restored.countedCashMinor, 900);
      expect(server.reads, isEmpty);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNotNull);
    });

    test('discards a canonical read that finished after a switch', () async {
      await state.save(_record());
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(
        sessions,
        state,
        server,
        beforeRead: () => sessions.open(
          uid: 'user-a',
          membership: _membership('tenant-b'),
        ),
      );
      final captured = TenantSession.active(
        uid: 'user-a',
        tenantId: 'tenant-a',
        role: TenantRole.cashier,
      );

      final restored = await controller.restore(captured);

      expect(restored.errorCode, 'session_changed');
      expect(controller.state.phase, TenantShiftPhase.unknown);
    });
  });

  group('cash count and closing', () {
    test('an unfinished cash count blocks switching until it settles', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();
      final source = TenantShiftSwitchStateSource(state);

      expect(
        (await source.inspect(sessions.requireSession()))!.blocker,
        isNull,
      );

      final counting = await controller.startCashCount();
      expect(counting.phase, TenantShiftPhase.closing);
      expect(counting.blocksTenantSwitch, isTrue);
      expect(
        (await source.inspect(sessions.requireSession()))!.blocker,
        TenantSwitchBlocker.unfinishedCashCountOrShiftClose,
      );

      final closed = await controller.closeShift(countedCashMinor: 125000);
      expect(closed.phase, TenantShiftPhase.none);
      expect(server.updated.single.$2['status'], 'closed');
      expect(server.updated.single.$2['closingCashMinor'], 125000);
      expect(
        (await source.inspect(sessions.requireSession()))!.blocker,
        isNull,
      );
    });

    test('cancelling a cash count restores the open shift', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();
      await controller.startCashCount();

      final cancelled = await controller.cancelCashCount();

      expect(cancelled.phase, TenantShiftPhase.open);
      expect(
        (await TenantShiftSwitchStateSource(
          state,
        ).inspect(sessions.requireSession()))!.blocker,
        isNull,
      );
    });

    test('refuses a close before the cash count started', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();

      final result = await controller.closeShift(countedCashMinor: 100);

      expect(result.errorCode, 'cash_count_not_started');
      expect(server.updated, isEmpty);
    });

    test('refuses an unusable counted amount', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();
      await controller.startCashCount();

      final result = await controller.closeShift(countedCashMinor: -1);

      expect(result.errorCode, 'invalid_closing_cash');
      expect(result.phase, TenantShiftPhase.closing);
      expect(server.updated, isEmpty);
    });

    test('an unacknowledged close keeps blocking the switch', () async {
      final controller = _controller(sessions, state, server);
      await controller.openShift();
      await controller.startCashCount();
      server.failUpdateWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );

      final result = await controller.closeShift(countedCashMinor: 4200);

      expect(result.phase, TenantShiftPhase.closing);
      expect(result.errorCode, 'unavailable');
      expect(result.countedCashMinor, 4200);
      expect(
        (await TenantShiftSwitchStateSource(
          state,
        ).inspect(sessions.requireSession()))!.blocker,
        TenantSwitchBlocker.unfinishedCashCountOrShiftClose,
      );
    });
  });

  group('closing summary', () {
    test('writes the sale-derived aggregates reconciliation verifies', () async {
      final ledger = _Ledger()
        ..summary = const ShiftSalesSummary(
          transactionCount: 3,
          totalMinor: 98750,
          unsettledCount: 0,
        );
      final controller = _controller(
        sessions,
        state,
        server,
        salesLedger: ledger,
      );
      await controller.openShift();
      await controller.startCashCount();

      final closed = await controller.closeShift(countedCashMinor: 125000);

      expect(closed.phase, TenantShiftPhase.none);
      expect(ledger.requested, contains('shift-1'));
      final update = server.updated.single.$2;
      expect(update['transactionCount'], 3);
      expect(update['totalSalesMinor'], 98750);
      expect(update['totalSales'], 987.5);
      expect(update['closingCashMinor'], 125000);
    });

    test('refuses to close while a sale is still unsynchronized', () async {
      final ledger = _Ledger()
        ..summary = const ShiftSalesSummary(
          transactionCount: 1,
          totalMinor: 500,
          unsettledCount: 1,
        );
      final controller = _controller(
        sessions,
        state,
        server,
        salesLedger: ledger,
      );
      await controller.openShift();
      await controller.startCashCount();

      final result = await controller.closeShift(countedCashMinor: 500);

      // The device cannot describe the shift completely, so it keeps the
      // counted cash and the switch blocker instead of publishing a wrong sum.
      expect(result.errorCode, 'unsynchronized_shift_sales');
      expect(result.phase, TenantShiftPhase.closing);
      expect(result.countedCashMinor, 500);
      expect(server.updated, isEmpty);
      expect(
        (await TenantShiftSwitchStateSource(
          state,
        ).inspect(sessions.requireSession()))!.blocker,
        TenantSwitchBlocker.unfinishedCashCountOrShiftClose,
      );
    });

    test('unreadable sale evidence never closes the shift', () async {
      final ledger = _Ledger()
        ..failure = const ShiftSalesLedgerException('malformed_local_sale');
      final controller = _controller(
        sessions,
        state,
        server,
        salesLedger: ledger,
      );
      await controller.openShift();
      await controller.startCashCount();

      final result = await controller.closeShift(countedCashMinor: 500);

      expect(result.phase, TenantShiftPhase.unavailable);
      expect(result.errorCode, 'malformed_local_sale');
      expect(server.updated, isEmpty);
    });

    test('shows the confirmed summary while the cash count is open', () async {
      final ledger = _Ledger()
        ..summary = const ShiftSalesSummary(
          transactionCount: 2,
          totalMinor: 4200,
          unsettledCount: 0,
        );
      final controller = _controller(
        sessions,
        state,
        server,
        salesLedger: ledger,
      );
      await controller.openShift();

      expect(controller.state.sales, isNull);
      final counting = await controller.startCashCount();

      expect(counting.sales!.transactionCount, 2);
      expect(counting.sales!.totalMinor, 4200);
    });
  });

  group('canonical open-shift discovery', () {
    test('adopts the canonical shift after local state is lost', () async {
      server.shifts['tenants/tenant-a/shifts/shift-restored'] = _document(
        overrides: <String, Object?>{'shiftId': 'shift-restored'},
      );
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.open);
      expect(restored.shift!.id, 'shift-restored');
      final record = await state.read(uid: 'user-a', tenantId: 'tenant-a');
      expect(record!.shiftId, 'shift-restored');
      expect(record.serverConfirmedOpen, isTrue);
      expect(server.queries, <String>['tenants/tenant-a/shifts']);
    });

    test('opens no duplicate when a canonical shift already exists', () async {
      server.shifts['tenants/tenant-a/shifts/shift-existing'] = _document(
        overrides: <String, Object?>{'shiftId': 'shift-existing'},
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.phase, TenantShiftPhase.open);
      expect(result.errorCode, 'shift_already_open');
      expect(result.shift!.id, 'shift-existing');
      expect(server.created, isEmpty);
    });

    test('never adopts a shift opened on another device', () async {
      server.shifts['tenants/tenant-a/shifts/shift-elsewhere'] = _document(
        overrides: <String, Object?>{
          'shiftId': 'shift-elsewhere',
          'deviceId': 'dev-fedcba9876543210fedcba9876543210',
        },
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      // The closing summary is built from local sale evidence, which only the
      // issuing device holds, so a second device must not open or adopt one.
      expect(result.phase, TenantShiftPhase.none);
      expect(result.errorCode, 'shift_open_on_other_device');
      expect(result.otherDeviceShiftOpen, isTrue);
      expect(server.created, isEmpty);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('fails closed on two open shifts for one device', () async {
      for (final id in <String>['shift-one', 'shift-two']) {
        server.shifts['tenants/tenant-a/shifts/$id'] = _document(
          overrides: <String, Object?>{'shiftId': id},
        );
      }
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.phase, TenantShiftPhase.unavailable);
      expect(result.errorCode, 'ambiguous_open_shift');
      expect(server.created, isEmpty);
    });

    test('an unavailable discovery query never opens a shift', () async {
      server.failQueryWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.phase, TenantShiftPhase.unavailable);
      expect(server.created, isEmpty);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('a known local shift needs no discovery query', () async {
      await state.save(_record());
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      final controller = _controller(sessions, state, server);

      await controller.restore(sessions.requireSession());

      expect(server.queries, isEmpty);
    });
  });

  group('cashier cross-business restriction', () {
    test('a cashier cannot open a shift in a second business', () async {
      await state.save(_record(tenantId: 'tenant-b', shiftId: 'shift-b'));
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.errorCode, 'other_tenant_shift_open');
      expect(result.otherTenantShiftOpen, isTrue);
      expect(server.created, isEmpty);
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
    });

    test('a manager may still open a shift elsewhere', () async {
      await state.save(_record(tenantId: 'tenant-b', shiftId: 'shift-b'));
      sessions.open(
        uid: 'user-a',
        membership: _membership('tenant-a', role: TenantRole.manager),
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.phase, TenantShiftPhase.open);
      expect(result.otherTenantShiftOpen, isTrue);
      expect(server.created.length, 1);
    });

    test('another identity on the device never blocks this cashier', () async {
      await state.save(
        _record(uid: 'user-b', tenantId: 'tenant-b', shiftId: 'shift-b'),
      );
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.phase, TenantShiftPhase.open);
      expect(result.otherTenantShiftOpen, isFalse);
    });
  });

  group('fail-closed reporting', () {
    test('malformed durable state never claims a clean device', () async {
      await box.put('user-a:tenant-a', <String, Object?>{'schemaVersion': 99});
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.unavailable);
      expect(restored.errorCode, 'malformed_shift_state');
    });

    test('a cross-tenant reader response fails closed', () async {
      await state.save(_record());
      server.shifts['tenants/tenant-a/shifts/shift-a'] = _document();
      server.responsePath = 'tenants/tenant-b/shifts/shift-a';
      final controller = _controller(sessions, state, server);

      final restored = await controller.restore(sessions.requireSession());

      expect(restored.phase, TenantShiftPhase.unavailable);
      expect(restored.errorCode, 'cross_tenant_shift');
      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNotNull);
    });

    test('no selected session performs no local or remote work', () async {
      sessions.clear();
      final controller = _controller(sessions, state, server);

      final result = await controller.openShift();

      expect(result.errorCode, 'no_selected_session');
      expect(server.created, isEmpty);
      expect(server.reads, isEmpty);
    });
  });
}

TenantShiftController _controller(
  TenantSessionController sessions,
  HiveTenantShiftState state,
  _Server server, {
  bool online = true,
  VoidCallback? beforeCreate,
  VoidCallback? beforeRead,
  ShiftSalesLedger? salesLedger,
}) {
  var nextShift = 0;
  return TenantShiftController(
    sessionController: sessions,
    localState: state,
    salesLedger: salesLedger ?? _Ledger(),
    reader: _Reader(server, beforeRead: beforeRead),
    writer: FirebaseTenantShiftWriter.forTesting(
      isOnline: () async => online,
      create: (path, data) async {
        beforeCreate?.call();
        await server.create(path, data);
      },
      update: server.update,
    ),
    deviceId: _deviceA,
    isOnline: () async => online,
    shiftIdFactory: () => 'shift-${++nextShift}',
    clock: () => DateTime.utc(2026, 7, 31, 9),
  );
}

Future<Box<dynamic>> _openBox() => Hive.openBox<dynamic>(
  HiveTenantShiftState.boxName,
  encryptionCipher: HiveAesCipher(_encryptionKey),
  crashRecovery: false,
);

final List<int> _encryptionKey = List<int>.generate(
  HiveTenantShiftState.encryptionKeyBytes,
  (index) => (index * 13) % 256,
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
  bool serverConfirmedOpen = true,
  bool closeInProgress = false,
  int? countedCashMinor,
}) => TenantShiftLocalRecord(
  uid: uid,
  tenantId: tenantId,
  shiftId: shiftId,
  businessDate: _businessDate,
  deviceId: _deviceA,
  serverConfirmedOpen: serverConfirmedOpen,
  closeInProgress: closeInProgress,
  countedCashMinor: countedCashMinor,
  updatedAt: DateTime.utc(2026, 7, 31, 9),
);

/// A minimal in-memory stand-in for the canonical shift documents.
final class _Server {
  final Map<String, Map<String, Object?>> shifts =
      <String, Map<String, Object?>>{};
  final List<String> reads = <String>[];
  final List<String> queries = <String>[];
  final List<(String, Map<String, Object?>)> created =
      <(String, Map<String, Object?>)>[];
  final List<(String, Map<String, Object?>)> updated =
      <(String, Map<String, Object?>)>[];
  Object? failCreateWith;
  Object? failUpdateWith;
  Object? failReadWith;
  Object? failQueryWith;
  String? responsePath;

  Future<void> create(String path, Map<String, Object?> data) async {
    final failure = failCreateWith;
    if (failure != null) throw failure;
    created.add((path, data));
    shifts[path] = <String, Object?>{
      ...data,
      'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 6)),
    };
  }

  Future<void> update(String path, Map<String, Object?> data) async {
    final failure = failUpdateWith;
    if (failure != null) throw failure;
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
  _Reader(this._server, {this.beforeRead});

  final _Server _server;
  final VoidCallback? beforeRead;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) async {
    beforeRead?.call();
    _server.reads.add(path);
    final failure = _server.failReadWith;
    if (failure != null) throw failure;
    final data = _server.shifts[path];
    if (data == null) return null;
    return TenantDocumentSnapshot(
      path: _server.responsePath ?? path,
      data: data,
    );
  }

  @override
  Future<List<TenantQueryDocumentSnapshot>> getCollectionPage(
    TenantCollectionQuery query,
  ) async {
    _server.queries.add(query.collectionPath);
    final failure = _server.failQueryWith;
    if (failure != null) throw failure;
    final matches = <TenantQueryDocumentSnapshot>[];
    for (final path in _server.shifts.keys.toList()..sort()) {
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

/// A configurable stand-in for the local sale evidence of one shift.
final class _Ledger implements ShiftSalesLedger {
  ShiftSalesSummary summary = ShiftSalesSummary.empty;
  Object? failure;
  final List<String> requested = <String>[];

  @override
  Future<ShiftSalesSummary> summarize({
    required String uid,
    required String tenantId,
    required String shiftId,
  }) async {
    requested.add(shiftId);
    final error = failure;
    if (error != null) throw error;
    return summary;
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
