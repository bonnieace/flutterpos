import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/inventory/bulk_catalog_attempt_store.dart';
import 'package:uzapay_pos/inventory/product_image_drafts.dart';
import 'package:uzapay_pos/inventory/stock_take_draft_store.dart';
import 'package:uzapay_pos/shift/shift_local_state.dart';
import 'package:uzapay_pos/storage/device_storage.dart';
import 'package:uzapay_pos/tenancy/tenant_pending_mutation.dart';
import 'package:uzapay_pos/tenancy/tenant_staff_request_ticket.dart';

const _name = 'storage-probe-v1';
final _key = List<int>.generate(32, (index) => index);
final _otherKey = List<int>.generate(32, (index) => 255 - index);

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('device-storage-test-');
    Hive.init(directory.path);
  });

  tearDown(() async {
    DeviceStorage.directory = null;
    await Hive.close();
    // Hive closes a box whose open failed without awaiting it, and that close
    // deletes the box's lock file; let it finish before the folder goes.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<File> writeRecords(
    int count, {
    List<int>? key,
    String name = _name,
  }) async {
    final box = await Hive.openBox<dynamic>(
      name,
      encryptionCipher: HiveAesCipher(key ?? _key),
    );
    for (var index = 0; index < count; index++) {
      await box.put('record-$index', 'sale $index ${'x' * 64}');
    }
    await box.close();
    return deviceStoreFile(directory.path, name);
  }

  List<File> quarantined() {
    final folder = Directory(
      '${directory.path}${Platform.pathSeparator}'
      '${DeviceStorage.quarantineFolder}',
    );
    if (!folder.existsSync()) return const <File>[];
    return folder.listSync().whereType<File>().toList();
  }

  group('openBoxRepairingTornTail', () {
    test('a healthy box opens untouched and nothing is set aside', () async {
      await writeRecords(3);
      final box = await openBoxRepairingTornTail<dynamic>(
        Hive,
        _name,
        cipher: HiveAesCipher(_key),
        directory: directory.path,
      );
      expect(box.length, 3);
      expect(quarantined(), isEmpty);
    });

    test('a write torn part-way keeps every record before it', () async {
      final file = await writeRecords(3);
      final original = await file.readAsBytes();
      // The last record, cut off mid-write the way a killed process leaves it.
      await file.writeAsBytes(
        Uint8List.sublistView(original, 0, original.length - 20),
      );

      final box = await openBoxRepairingTornTail<dynamic>(
        Hive,
        _name,
        cipher: HiveAesCipher(_key),
        directory: directory.path,
      );

      expect(box.keys, <String>['record-0', 'record-1']);
      expect(quarantined(), hasLength(1));
      expect(
        quarantined().single.lengthSync(),
        original.length - 20,
        reason: 'the damaged original is kept, not only the repair',
      );
    });

    test(
      'a flipped byte in the last record is repaired the same way',
      () async {
        final file = await writeRecords(3);
        final bytes = await file.readAsBytes();
        bytes[bytes.length - 3] ^= 0xFF;
        await file.writeAsBytes(bytes);

        final box = await openBoxRepairingTornTail<dynamic>(
          Hive,
          _name,
          cipher: HiveAesCipher(_key),
          directory: directory.path,
        );

        expect(box.keys, <String>['record-0', 'record-1']);
      },
    );

    test(
      'the wrong key is refused and the file is left exactly as it was',
      () async {
        final file = await writeRecords(3, key: _otherKey);
        final original = await file.readAsBytes();

        await expectLater(
          openBoxRepairingTornTail<dynamic>(
            Hive,
            _name,
            cipher: HiveAesCipher(_key),
            directory: directory.path,
          ),
          throwsA(isA<DeviceStorageUnreadable>()),
        );

        expect(await file.readAsBytes(), original);
        expect(quarantined().single.readAsBytesSync(), original);
      },
    );

    test(
      'with no storage directory known, a damaged box throws as before',
      () async {
        final file = await writeRecords(3);
        final bytes = await file.readAsBytes();
        bytes[bytes.length - 3] ^= 0xFF;
        await file.writeAsBytes(bytes);
        DeviceStorage.directory = null;

        await expectLater(
          openBoxRepairingTornTail<dynamic>(
            Hive,
            _name,
            cipher: HiveAesCipher(_key),
          ),
          throwsA(isA<HiveError>()),
        );
      },
    );
  });

  group('quarantineDeviceStore', () {
    test('moves the file aside and removes its lock', () async {
      final file = await writeRecords(1);
      final lock = File('${directory.path}${Platform.pathSeparator}$_name.lock')
        ..writeAsStringSync('');

      final moved = await quarantineDeviceStore(
        _name,
        directory: directory.path,
      );

      expect(moved, isNotNull);
      expect(File(moved!).existsSync(), isTrue);
      expect(file.existsSync(), isFalse);
      expect(lock.existsSync(), isFalse);
    });

    test('reports nothing moved when there was no file', () async {
      expect(
        await quarantineDeviceStore(_name, directory: directory.path),
        isNull,
      );
    });
  });

  group('in a browser, where there is no folder', () {
    // `DeviceStorage.directory` stays null on web, as it does here. The gate
    // clears the store's own box, so that is the box these tests damage.
    const store = DeviceStore.stockTakeDrafts;

    Future<Box<dynamic>> openUnderTheWrongKey() =>
        openBoxRepairingTornTail<dynamic>(
          Hive,
          store.boxName,
          cipher: HiveAesCipher(_otherKey),
        );

    test('setting the file aside moves nothing, so the same box fails '
        'again', () async {
      // The loop this group exists for: "Continue without" asked again, and
      // again, because there was nothing to move.
      await writeRecords(3, name: store.boxName);
      var asked = 0;
      final gate = DeviceStorageGate(
        quarantine: quarantineDeviceStore,
        ask: (store, {required canContinue}) async {
          if (++asked == 3) throw StateError('still asking');
          return DeviceStorageChoice.continueWithout;
        },
      );

      await expectLater(
        gate.open(store, openUnderTheWrongKey),
        throwsStateError,
      );
      expect(asked, 3);
    });

    test('"Continue without" clears the box and asks once', () async {
      await writeRecords(3, name: store.boxName);
      var asked = 0;
      final gate = DeviceStorageGate(
        quarantine: clearBrowserDeviceStore,
        ask: (store, {required canContinue}) async {
          // Fails fast rather than spinning, should the loop come back.
          if (++asked > 1) throw StateError('asked again');
          expect(canContinue, isTrue);
          return DeviceStorageChoice.continueWithout;
        },
      );

      final box = await gate.open(store, openUnderTheWrongKey);

      expect(asked, 1);
      expect(box.isEmpty, isTrue);
    });

    test('says nothing was kept', () async {
      final file = await writeRecords(1, name: store.boxName);
      expect(await clearBrowserDeviceStore(store.boxName), isNull);
      expect(file.existsSync(), isFalse);
      expect(quarantined(), isEmpty);
    });
  });

  group('DeviceStorageGate', () {
    test('asks, and a retry that succeeds carries on', () async {
      final asked = <DeviceStore>[];
      var calls = 0;
      final gate = DeviceStorageGate(
        ask: (store, {required canContinue}) async {
          asked.add(store);
          return DeviceStorageChoice.retry;
        },
        quarantine: (_) async => fail('nothing may be set aside on a retry'),
      );

      final value = await gate.open(DeviceStore.checkoutOutbox, () async {
        if (calls++ == 0) throw HiveError('Wrong checksum in hive file.');
        return 'opened';
      });

      expect(value, 'opened');
      expect(asked, <DeviceStore>[DeviceStore.checkoutOutbox]);
    });

    test('continuing sets the file aside and opens a fresh store', () async {
      final setAside = <String>[];
      var calls = 0;
      final gate = DeviceStorageGate(
        ask: (_, {required canContinue}) async {
          expect(canContinue, isTrue);
          return DeviceStorageChoice.continueWithout;
        },
        quarantine: (name) async {
          setAside.add(name);
          return 'moved';
        },
      );

      final value = await gate.open(DeviceStore.checkoutOutbox, () async {
        if (calls++ == 0) {
          throw const DeviceStorageUnreadable('checkout-outbox-v1', 'key');
        }
        return 'fresh';
      });

      expect(value, 'fresh');
      expect(setAside, <String>['checkout-outbox-v1']);
    });

    test('the catalog copy is set aside once without asking', () async {
      var asked = 0;
      final setAside = <String>[];
      var calls = 0;
      final gate = DeviceStorageGate(
        ask: (_, {required canContinue}) async {
          asked++;
          return DeviceStorageChoice.retry;
        },
        quarantine: (name) async {
          setAside.add(name);
          return 'moved';
        },
      );

      final value = await gate.open(DeviceStore.catalogCache, () async {
        if (calls++ == 0) throw HiveError('Wrong checksum in hive file.');
        return 'rebuilt';
      });

      expect(value, 'rebuilt');
      expect(asked, 0);
      expect(setAside, <String>['checkout-catalog-cache-v1']);
    });

    test('a key store that does not answer can only be retried', () async {
      final offered = <bool>[];
      var calls = 0;
      final gate = DeviceStorageGate(
        ask: (_, {required canContinue}) async {
          offered.add(canContinue);
          // Even a "continue" cannot set aside a key it could not read.
          return DeviceStorageChoice.continueWithout;
        },
        quarantine: (_) async => fail('a key failure is not the file'),
      );

      final value = await gate.open(DeviceStore.receiptCounters, () async {
        if (calls++ < 2) {
          throw PlatformException(code: 'keystore_unavailable');
        }
        return 'opened';
      });

      expect(value, 'opened');
      expect(offered, <bool>[false, false]);
    });
  });

  test('every store names the box its class opens', () {
    expect(
      <DeviceStore, String>{
        for (final store in DeviceStore.values) store: store.boxName,
      },
      <DeviceStore, String>{
        DeviceStore.checkoutOutbox: HiveCheckoutOutbox.boxName,
        DeviceStore.tenantMutations: TenantPendingMutationStore.boxName,
        DeviceStore.shiftState: HiveTenantShiftState.boxName,
        DeviceStore.receiptCounters: HiveCheckoutReceiptCounters.boxName,
        DeviceStore.printJobs: HivePrintJobQueue.boxName,
        DeviceStore.productImageDrafts: HiveTenantProductImageDrafts.boxName,
        DeviceStore.stockTakeDrafts: HiveTenantStockTakeDrafts.boxName,
        DeviceStore.productImportAttempts:
            HiveTenantProductImportAttempts.boxName,
        DeviceStore.staffRequestTickets: HiveTenantStaffRequestTickets.boxName,
        DeviceStore.catalogCache: HiveCheckoutCatalogCache.boxName,
      },
    );
  });
}
