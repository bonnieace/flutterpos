import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive/hive.dart';

import '../observability/app_telemetry.dart';

/// Where Hive keeps this app's boxes, and where an unreadable one is set aside.
///
/// [directory] is set once at startup, right after Hive is initialised. Left
/// null - as every test that does not set it leaves it - the torn-tail repair
/// below is off and a damaged box throws exactly as it always has.
abstract final class DeviceStorage {
  static String? directory;

  /// Sub-folder of [directory] that holds set-aside box files. Nothing in the
  /// app reads it back: it exists so a file this device could not open is
  /// still on the phone for whoever investigates, rather than deleted.
  static const String quarantineFolder = 'quarantine';
}

/// A box that could not be opened, and could not be repaired without risking
/// what is in it.
final class DeviceStorageUnreadable implements Exception {
  const DeviceStorageUnreadable(this.boxName, this.cause);

  final String boxName;
  final Object cause;

  @override
  String toString() => 'DeviceStorageUnreadable($boxName): $cause';
}

/// Opens an encrypted box, repairing it only when the damage is a torn write.
///
/// **Why crash recovery stays off for the first attempt.** Hive's recovery
/// truncates a box at its first record that fails its checksum. After a crash
/// mid-write that is exactly right: only the record being written is lost, and
/// it was never finished. But a box opened with the wrong key fails the
/// checksum on *every* record, and recovery would then erase the whole box
/// without a word - for the outbox, every sale not yet synced (HISTORY.md, the
/// entry that turned recovery off).
///
/// So on a checksum failure the file is copied aside first, recovery is tried,
/// and the result is kept only if records survived. A box recovery leaves
/// empty is indistinguishable from a wrong key: the copy is put back untouched
/// and [DeviceStorageUnreadable] is thrown for the startup screen to explain.
/// The copy is kept either way, so even a repaired box has its original on the
/// phone.
Future<Box<T>> openBoxRepairingTornTail<T>(
  HiveInterface hive,
  String name, {
  required HiveCipher cipher,
  String? directory,
  DateTime Function()? clock,
}) async {
  try {
    return await _openQuietly<T>(hive, name, cipher, crashRecovery: false);
  } on HiveError catch (error, stackTrace) {
    final folder = directory ?? DeviceStorage.directory;
    if (folder == null || !error.message.contains('checksum')) rethrow;
    final file = deviceStoreFile(folder, name);
    if (!await file.exists()) rethrow;
    final originalBytes = await file.length();
    final original = await _copyAside(folder, name, file, clock);
    // Hive closes the failed box without awaiting it; its lock has to be
    // released before the same file can be locked again.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final Box<T> box;
    try {
      box = await _openQuietly<T>(hive, name, cipher, crashRecovery: true);
    } catch (_) {
      await original.copy(file.path);
      throw DeviceStorageUnreadable(name, error);
    }
    if (box.isEmpty) {
      await box.close();
      await original.copy(file.path);
      throw DeviceStorageUnreadable(name, error);
    }
    AppTelemetry.captureHandled(
      error,
      stackTrace,
      boundary: 'storage.torn_tail_repaired',
      data: {
        'box': name,
        'records_kept': box.length,
        'bytes_dropped': originalBytes - await file.length(),
      },
    );
    return box;
  }
}

/// Opens a box, delivering a failure once.
///
/// Hive 2.2.3 completes an internal future with the same error an open throws
/// and then drops it unlistened (`_openingBoxes.remove` in `hive_impl.dart`),
/// so every failed open also surfaced as an uncaught error - a second, empty
/// event in GlitchTip, and a failure in any test that opened a damaged box.
/// The guarded zone keeps that copy; the real one still reaches the caller.
Future<Box<T>> _openQuietly<T>(
  HiveInterface hive,
  String name,
  HiveCipher cipher, {
  required bool crashRecovery,
}) {
  final result = Completer<Box<T>>();
  runZonedGuarded(
    () {
      hive
          .openBox<T>(
            name,
            encryptionCipher: cipher,
            crashRecovery: crashRecovery,
          )
          .then(result.complete, onError: result.completeError);
    },
    (error, stackTrace) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
    },
  );
  return result.future;
}

/// The file Hive keeps [name] in.
File deviceStoreFile(String directory, String name) =>
    File('$directory${Platform.pathSeparator}${name.toLowerCase()}.hive');

/// Moves [name]'s file into the quarantine folder so a fresh, empty box can be
/// opened in its place. Returns where it went, or null when there was nothing
/// to move. Never deletes the file.
Future<String?> quarantineDeviceStore(
  String name, {
  String? directory,
  DateTime Function()? clock,
}) async {
  final folder = directory ?? DeviceStorage.directory;
  if (folder == null) return null;
  final file = deviceStoreFile(folder, name);
  final lock = File(
    '$folder${Platform.pathSeparator}${name.toLowerCase()}.lock',
  );
  String? moved;
  if (await file.exists()) {
    final target = _quarantinePath(folder, name, clock);
    try {
      moved = (await file.rename(target)).path;
    } on FileSystemException {
      moved = (await file.copy(target)).path;
      await file.delete();
    }
  }
  if (await lock.exists()) await lock.delete();
  return moved;
}

/// Empties [name] in a browser, where there is no file to set aside. Returns
/// null, because nothing is kept.
///
/// **The one place a store the person could not open is deleted rather than
/// moved.** A browser keeps each box as an IndexedDB database and the app has
/// no folder there; [quarantineDeviceStore] found no folder, moved nothing,
/// and the same unreadable box failed again behind "Continue without" - which
/// asked again, for as long as the person kept answering. Clearing it is what
/// that screen already told them they were giving up.
Future<String?> clearBrowserDeviceStore(
  String name, {
  HiveInterface? hive,
}) async {
  // Hive closes the failed box without awaiting it, as in
  // [openBoxRepairingTornTail]; a browser holds a database's deletion until
  // its last connection closes.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await (hive ?? Hive).deleteBoxFromDisk(name);
  return null;
}

Future<File> _copyAside(
  String folder,
  String name,
  File file,
  DateTime Function()? clock,
) async => file.copy(_quarantinePath(folder, name, clock));

String _quarantinePath(String folder, String name, DateTime Function()? clock) {
  final directory = Directory(
    '$folder${Platform.pathSeparator}${DeviceStorage.quarantineFolder}',
  );
  directory.createSync(recursive: true);
  final stamp = (clock ?? DateTime.now)().toUtc().microsecondsSinceEpoch;
  return '${directory.path}${Platform.pathSeparator}'
      '${name.toLowerCase()}-$stamp.hive';
}

/// One of the stores the app opens before its first frame, and what is lost
/// if a person chooses to carry on without it.
///
/// [loss] is read out on the startup screen, word for word, before anyone
/// commits to continuing. It must say what *this* store holds and nothing
/// more reassuring than is true.
enum DeviceStore {
  checkoutOutbox(
    boxName: 'checkout-outbox-v1',
    title: 'Sales waiting to sync',
    loss:
        'Sales made on this phone that have not reached the server yet will '
        'not be sent. Check today’s sales on another device before carrying on.',
  ),
  tenantMutations(
    boxName: 'tenant-mutation-outbox-v1',
    title: 'Changes waiting to sync',
    loss:
        'Product, stock, supplier, expense and return changes made on this '
        'phone while offline will not be sent.',
  ),
  shiftState(
    boxName: 'tenant-shift-state-v1',
    title: 'This phone’s shift',
    loss:
        'This phone will forget the shift it has open. Check the shift before '
        'selling again.',
  ),
  receiptCounters(
    boxName: 'checkout-receipt-counters-v1',
    title: 'Receipt numbering',
    loss:
        'This phone will start a new receipt series. Receipts already issued '
        'keep their numbers.',
  ),
  printJobs(
    boxName: 'checkout-print-jobs-v1',
    title: 'Receipts waiting to print',
    loss:
        'Receipts that have not printed yet will not print. They can be '
        'reprinted from the sale.',
  ),
  productImageDrafts(
    boxName: 'tenant-product-image-drafts-v1',
    title: 'Product photos waiting to upload',
    loss:
        'Product photos taken on this phone that have not uploaded will be lost.',
  ),
  stockTakeDrafts(
    boxName: 'tenant-stock-take-drafts-v1',
    title: 'Stock counts in progress',
    loss: 'A stock count started on this phone and not submitted will be lost.',
  ),
  productImportAttempts(
    boxName: 'tenant-product-import-attempts-v1',
    title: 'Unfinished product imports',
    loss:
        'An import that stopped part-way cannot be resumed. Running it again '
        'may create some products twice, so check the catalog first.',
  ),
  staffRequestTickets(
    boxName: 'tenant-staff-request-tickets-v1',
    title: 'Staff changes awaiting an answer',
    loss:
        'The app will not know whether a staff invitation or change sent just '
        'before this went through. Check the staff list.',
  ),

  /// A copy of the server's catalog. Set aside and rebuilt without asking.
  catalogCache(
    boxName: 'checkout-catalog-cache-v1',
    title: 'Product catalog on this phone',
    loss:
        'The catalog will be downloaded again the next time this phone is online.',
    disposable: true,
  );

  const DeviceStore({
    required this.boxName,
    required this.title,
    required this.loss,
    this.disposable = false,
  });

  final String boxName;
  final String title;
  final String loss;

  /// Holds nothing the server does not also hold.
  final bool disposable;
}

/// What the person holding the phone chose.
enum DeviceStorageChoice { retry, continueWithout }

/// Asks the person holding the phone what to do about [store].
///
/// [canContinue] is false when the failure is not the box file - the phone's
/// secure key store not answering - which setting a file aside cannot fix.
typedef DeviceStorageQuestion =
    Future<DeviceStorageChoice> Function(
      DeviceStore store, {
      required bool canContinue,
    });

/// Opens each startup store, and never lets one that fails stop the app for
/// good while a file can be set aside instead.
final class DeviceStorageGate {
  DeviceStorageGate({
    required DeviceStorageQuestion ask,
    Future<String?> Function(String boxName)? quarantine,
  }) : _ask = ask,
       _quarantine =
           quarantine ??
           (kIsWeb ? clearBrowserDeviceStore : quarantineDeviceStore);

  final DeviceStorageQuestion _ask;
  final Future<String?> Function(String boxName) _quarantine;

  Future<T> open<T>(DeviceStore store, Future<T> Function() open) async {
    var attempt = 0;
    var setAsideWithoutAsking = store.disposable;
    while (true) {
      attempt++;
      try {
        return await open();
      } catch (error, stackTrace) {
        AppTelemetry.captureHandled(
          error,
          stackTrace,
          boundary: 'storage.open_failed',
          data: {'box': store.boxName, 'attempt': attempt},
        );
        final canContinue = isDeviceStoreFileFailure(error);
        if (setAsideWithoutAsking && canContinue) {
          setAsideWithoutAsking = false;
          await _quarantine(store.boxName);
          continue;
        }
        final choice = await _ask(store, canContinue: canContinue);
        if (choice == DeviceStorageChoice.continueWithout && canContinue) {
          final moved = await _quarantine(store.boxName);
          // Its own event: the open failure above is already reported, and
          // this is the separate fact that a person chose to carry on.
          AppTelemetry.captureHandled(
            StateError('continued_without_${store.boxName}'),
            StackTrace.current,
            boundary: 'storage.continued_without',
            code: 'continued_without',
            data: {'box': store.boxName, 'set_aside': moved != null},
          );
        }
      }
    }
  }
}

/// Whether [error] is the box file itself, which setting it aside can fix.
bool isDeviceStoreFileFailure(Object error) =>
    error is HiveError ||
    error is DeviceStorageUnreadable ||
    error is FileSystemException;
