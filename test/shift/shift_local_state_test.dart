import 'dart:io';

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

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shift-state-test-');
    Hive.init(directory.path);
    box = await _openBox();
    state = HiveTenantShiftState.fromBox(
      box,
      clock: () => DateTime.utc(2026, 7, 31, 9),
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  group('durable shift state', () {
    test('isolates records by both UID and business', () async {
      await state.save(_record());
      await state.save(_record(uid: 'user-b', shiftId: 'shift-b'));
      await state.save(_record(tenantId: 'tenant-b', shiftId: 'shift-c'));

      expect(
        (await state.read(uid: 'user-a', tenantId: 'tenant-a'))!.shiftId,
        'shift-a',
      );
      expect(
        (await state.read(uid: 'user-b', tenantId: 'tenant-a'))!.shiftId,
        'shift-b',
      );
      expect(await state.read(uid: 'user-c', tenantId: 'tenant-a'), isNull);
      expect(
        (await state.recordsForUid('user-a')).map((r) => r.tenantId).toList()
          ..sort(),
        <String>['tenant-a', 'tenant-b'],
      );
      expect((await state.recordsForUid('user-b')).single.shiftId, 'shift-b');
    });

    test('survives a restart with the same encrypted box', () async {
      await state.save(
        _record(closeInProgress: true, countedCashMinor: 125000),
      );
      await state.close();

      box = await _openBox();
      state = HiveTenantShiftState.fromBox(box);
      final restored = await state.read(uid: 'user-a', tenantId: 'tenant-a');

      expect(restored, isNotNull);
      expect(restored!.shiftId, 'shift-a');
      expect(restored.closeInProgress, isTrue);
      expect(restored.countedCashMinor, 125000);
      expect(restored.serverConfirmedOpen, isTrue);
      expect(restored.deviceId, _deviceA);
      expect(restored.updatedAt, DateTime.utc(2026, 7, 31, 9));
    });

    test('clears a record once the server has settled the shift', () async {
      await state.save(_record());
      await state.clear(uid: 'user-a', tenantId: 'tenant-a');

      expect(await state.read(uid: 'user-a', tenantId: 'tenant-a'), isNull);
      expect(await state.recordsForUid('user-a'), isEmpty);
    });

    test('reads a record written before openedAt existed', () async {
      // **The upgrade this file had to survive.** A version mismatch raises
      // `malformed_shift_state`, which the controller turns into a till that
      // refuses to open - so rejecting the old shape would have shut every
      // register holding an open shift at the moment it updated.
      await box.put('user-a:tenant-a', <String, Object?>{
        'schemaVersion': HiveTenantShiftState.legacySchemaVersion,
        'uid': 'user-a',
        'tenantId': 'tenant-a',
        'shiftId': 'shift-a',
        'businessDate': _businessDate,
        'deviceId': _deviceA,
        'serverConfirmedOpen': true,
        'closeInProgress': false,
        'updatedAtMs': 100,
      });

      final restored = await state.read(uid: 'user-a', tenantId: 'tenant-a');

      expect(restored, isNotNull);
      // Dated to its last touch, which can only ever under-state its age.
      expect(
        restored!.openedAt,
        DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
      );
    });

    test('a record written by the previous build still reads', () async {
      // **The half of a schema bump that can shut a till.** A version mismatch
      // raises `malformed_shift_state`, which the controller turns into a
      // register that refuses to open a shift - so version 2, which carried one
      // `countedCashMinor` and no declared triple, has to keep reading rather
      // than merely keep existing.
      await box.put('user-a:tenant-a', <String, Object?>{
        'schemaVersion': 2,
        'uid': 'user-a',
        'tenantId': 'tenant-a',
        'shiftId': 'shift-a',
        'businessDate': _businessDate,
        'deviceId': _deviceA,
        'serverConfirmedOpen': true,
        'closeInProgress': true,
        'countedCashMinor': 125000,
        'updatedAtMs': 100,
        'openedAtMs': 100,
      });

      final restored = await state.read(uid: 'user-a', tenantId: 'tenant-a');

      expect(restored, isNotNull);
      expect(restored!.countedCashMinor, 125000);
      // **Not turned into a declaration.** Reading it as one would invent two
      // zeros the cashier never typed, and the replay would write them to the
      // server as figures they declared.
      expect(restored.declaration, isNull);
    });

    test('the declared triple round-trips through the box', () async {
      final declaration = ShiftTenderDeclaration.tryParse(
        cash: 125000,
        mpesa: 34050,
        card: 900,
      )!;
      await state.save(
        _record(closeInProgress: true, declaration: declaration),
      );
      await state.close();

      box = await _openBox();
      state = HiveTenantShiftState.fromBox(box);
      final restored = await state.read(uid: 'user-a', tenantId: 'tenant-a');

      expect(restored!.declaration, declaration);
      expect(restored.countedCashMinor, isNull);
    });

    test('the opening float round-trips through the box', () async {
      // **Durable because the replay reads it.** A shift opened with no network
      // is sent later from this record, so a float that did not survive the box
      // would be dropped by exactly the opens most likely to carry one - and
      // the shift would then be marked against its sales alone.
      await state.save(_record(openingFloatMinor: 200000));
      await state.close();

      box = await _openBox();
      state = HiveTenantShiftState.fromBox(box);
      final restored = await state.read(uid: 'user-a', tenantId: 'tenant-a');

      expect(restored!.openingFloatMinor, 200000);
    });

    test(
      'a record written before the float existed reads as no float',
      () async {
        await state.save(_record());
        await state.close();

        box = await _openBox();
        state = HiveTenantShiftState.fromBox(box);
        final restored = await state.read(uid: 'user-a', tenantId: 'tenant-a');

        // Absent and zero are one answer, so a till already open when this build
        // arrives keeps trading rather than being refused as malformed.
        expect(restored!.openingFloatMinor, 0);
      },
    );

    test('abandoning a count clears both figures together', () async {
      final saved = await state.save(
        _record(
          closeInProgress: true,
          countedCashMinor: 900,
          declaration: ShiftTenderDeclaration.zero,
        ),
      );

      final cancelled = saved.copyWith(
        closeInProgress: false,
        clearDeclaration: true,
      );

      // One fact, so one clear. A record that dropped the declaration and kept
      // the legacy figure would claim a close had been counted when none had.
      expect(cancelled.declaration, isNull);
      expect(cancelled.countedCashMinor, isNull);
    });

    test('raises on malformed durable state instead of failing open', () async {
      final valid = <String, Object?>{
        'schemaVersion': HiveTenantShiftState.schemaVersion,
        'uid': 'user-a',
        'tenantId': 'tenant-a',
        'shiftId': 'shift-a',
        'businessDate': _businessDate,
        'deviceId': _deviceA,
        'serverConfirmedOpen': true,
        'closeInProgress': false,
        'updatedAtMs': 100,
        'openedAtMs': 100,
      };
      Future<Object?> store(
        Map<String, Object?> Function(Map<String, Object?>) mutate,
      ) async {
        await box.put(
          'user-a:tenant-a',
          mutate(Map<String, Object?>.from(valid)),
        );
        try {
          return await state.read(uid: 'user-a', tenantId: 'tenant-a');
        } on TenantShiftStateException catch (error) {
          return error.code;
        }
      }

      expect(await store((record) => record), isA<TenantShiftLocalRecord>());
      for (final mutation
          in <Map<String, Object?> Function(Map<String, Object?>)>[
            (record) => record..['schemaVersion'] = 99,
            (record) => record..['uid'] = 'user-b',
            (record) => record..['tenantId'] = 'tenant-b',
            (record) => record..['shiftId'] = 'shift/a',
            (record) => record..['deviceId'] = 'laptop-1',
            (record) => record..['businessDate'] = '31 July 2026',
            (record) => record..['serverConfirmedOpen'] = 'yes',
            (record) => record..['closeInProgress'] = 1,
            (record) => record..['countedCashMinor'] = -5,
            // A partial declared triple is refused rather than read with the
            // missing methods as zero. This record is what an unsent close is
            // replayed from, so a figure invented here reaches the server as
            // one the cashier declared.
            (record) => record..['declaredCashMinor'] = 100,
            (record) => record
              ..['declaredCashMinor'] = 100
              ..['declaredMpesaMinor'] = 200,
            (record) => record
              ..['declaredCashMinor'] = -1
              ..['declaredMpesaMinor'] = 0
              ..['declaredCardMinor'] = 0,
            (record) => record
              ..['declaredCashMinor'] = '100'
              ..['declaredMpesaMinor'] = 0
              ..['declaredCardMinor'] = 0,
            (record) => record..remove('updatedAtMs'),
            // A record claiming the current version must carry the field the
            // current version added.
            (record) => record..remove('openedAtMs'),
          ]) {
        expect(await store(mutation), 'malformed_shift_state');
      }

      await box.put('user-a:tenant-a', 'not-a-record');
      expect(
        () => state.recordsForUid('user-a'),
        throwsA(isA<TenantShiftStateException>()),
      );
    });
  });

  group('tenant switch cash-close source', () {
    test('a confirmed open shift alone does not block switching', () async {
      await state.save(_record());

      final inspection = await TenantShiftSwitchStateSource(
        state,
      ).inspect(_session());

      expect(inspection!.area, TenantSwitchStateArea.cashClose);
      expect(inspection.blocker, isNull);
      expect(inspection.hasServerConfirmedOpenShift, isTrue);
    });

    test('an unfinished cash count blocks switching', () async {
      await state.save(_record(closeInProgress: true));

      final inspection = await TenantShiftSwitchStateSource(
        state,
      ).inspect(_session());

      expect(
        inspection!.blocker,
        TenantSwitchBlocker.unfinishedCashCountOrShiftClose,
      );
    });

    test('no local shift state reports clean', () async {
      final inspection = await TenantShiftSwitchStateSource(
        state,
      ).inspect(_session());

      expect(inspection!.blocker, isNull);
      expect(inspection.hasServerConfirmedOpenShift, isFalse);
    });

    test(
      'another business\'s state never leaks into this inspection',
      () async {
        await state.save(_record(tenantId: 'tenant-b', closeInProgress: true));

        final inspection = await TenantShiftSwitchStateSource(
          state,
        ).inspect(_session());

        expect(inspection!.blocker, isNull);
      },
    );

    test('unreadable local state makes the coordinator fail closed', () async {
      await box.put('user-a:tenant-a', <String, Object?>{'schemaVersion': 99});

      expect(
        () => TenantShiftSwitchStateSource(state).inspect(_session()),
        throwsA(isA<TenantShiftStateException>()),
      );
    });
  });
}

Future<Box<dynamic>> _openBox() => Hive.openBox<dynamic>(
  HiveTenantShiftState.boxName,
  encryptionCipher: HiveAesCipher(_encryptionKey),
  crashRecovery: false,
);

final List<int> _encryptionKey = List<int>.generate(
  HiveTenantShiftState.encryptionKeyBytes,
  (index) => (index * 11) % 256,
);

TenantSession _session() => TenantSession.active(
  uid: 'user-a',
  tenantId: 'tenant-a',
  role: TenantRole.cashier,
);

TenantShiftLocalRecord _record({
  String uid = 'user-a',
  String tenantId = 'tenant-a',
  String shiftId = 'shift-a',
  bool serverConfirmedOpen = true,
  bool closeInProgress = false,
  int? countedCashMinor,
  ShiftTenderDeclaration? declaration,
  DateTime? openedAt,
  int openingFloatMinor = 0,
}) => TenantShiftLocalRecord(
  uid: uid,
  tenantId: tenantId,
  shiftId: shiftId,
  businessDate: _businessDate,
  deviceId: _deviceA,
  serverConfirmedOpen: serverConfirmedOpen,
  closeInProgress: closeInProgress,
  countedCashMinor: countedCashMinor,
  declaration: declaration,
  openingFloatMinor: openingFloatMinor,
  updatedAt: DateTime.utc(2026, 7, 31, 9),
  openedAt: openedAt ?? DateTime.utc(2026, 7, 31, 9),
);
