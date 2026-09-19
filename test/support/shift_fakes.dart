/// The fakes every shift widget test builds a shift out of: a server that
/// remembers what was written to it, a reader over it, a ledger, and the
/// records and memberships those need.
///
/// **Shared rather than copied, because the copy is what let a crash through.**
/// These lived in `shift_panel_test.dart` alone. When the gate got a suite of
/// its own the choice was to duplicate two hundred lines or to move them here,
/// and a duplicated `sharedShiftControllerFactory` is precisely the thing that
/// must not drift: it is the one place that states how the composition root
/// hands out a controller, and a second copy would be free to go on modelling
/// the ownership this app had before 2026-08-26.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/checkout/checkout_tender.dart';
import 'package:flutter_application_1/shift/shift.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:hive/hive.dart';

const String shiftDeviceId = 'dev-0123456789abcdef0123456789abcdef';
const String shiftBusinessDate = '2026-07-31';

/// An in-memory shift box, opened the only way a widget test can use one.
///
/// A file-backed box never completes inside a widget test's fake async zone,
/// which is why `bytes: Uint8List(0)` is not an optimisation here.
Future<Box<dynamic>> openShiftTestBox() => Hive.openBox<dynamic>(
  HiveTenantShiftState.boxName,
  encryptionCipher: HiveAesCipher(shiftEncryptionKey),
  crashRecovery: false,
  bytes: Uint8List(0),
);

TenantShiftControllerFactory sharedShiftControllerFactory(
  HiveTenantShiftState state,
  ShiftServer server, {
  ShiftSalesSummary sales = ShiftSalesSummary.empty,
  TenantShiftOnlineCheck? isOnline,
}) {
  final built = Expando<TenantShiftController>();
  return (sessions) => built[sessions] ??= shiftControllerFor(
    sessions,
    state,
    server,
    sales: sales,
    isOnline: isOnline,
  );
}

TenantShiftController shiftControllerFor(
  TenantSessionController sessions,
  HiveTenantShiftState state,
  ShiftServer server, {
  ShiftSalesSummary sales = ShiftSalesSummary.empty,

  /// Online unless a test says otherwise. Closing is the one shift action that
  /// genuinely needs the server, so a test about that refusal has to be able to
  /// take the network away partway through a journey rather than at the start.
  TenantShiftOnlineCheck? isOnline,
}) {
  var nextShift = 0;
  return TenantShiftController(
    sessionController: sessions,
    localState: state,
    salesLedger: ShiftLedger(sales),
    reader: ShiftReader(server),
    writer: FirebaseTenantShiftWriter.forTesting(
      isOnline: isOnline ?? () async => true,
      create: server.create,
      update: server.update,
    ),
    deviceId: shiftDeviceId,
    isOnline: isOnline ?? () async => true,
    shiftIdFactory: () => 'shift-${++nextShift}',
    clock: () => DateTime.utc(2026, 7, 31, 9),
  );
}

final List<int> shiftEncryptionKey = List<int>.generate(
  HiveTenantShiftState.encryptionKeyBytes,
  (index) => (index * 17) % 256,
);

Map<String, Object?> shiftDocument({Map<String, Object?>? overrides}) {
  final data = <String, Object?>{
    'shiftId': 'shift-a',
    'tenantId': 'tenant-a',
    'staffId': 'user-a',
    'deviceId': shiftDeviceId,
    'businessDate': shiftBusinessDate,
    'status': 'open',
    'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 6)),
  };
  if (overrides != null) data.addAll(overrides);
  return data;
}

/// One closing summary with a tender split, as the ledger would have built it.
ShiftSalesSummary shiftSummary({
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

TenantShiftLocalRecord shiftRecord({
  String uid = 'user-a',
  String tenantId = 'tenant-a',
  String shiftId = 'shift-a',
  bool closeInProgress = false,
  DateTime? openedAt,
  int openingFloatMinor = 0,
  ShiftTenderDeclaration? declaration,

  /// The day this shift belongs to. Named for the midnight case, where a shift
  /// from yesterday must stop selling today.
  String businessDate = shiftBusinessDate,
}) => TenantShiftLocalRecord(
  uid: uid,
  tenantId: tenantId,
  shiftId: shiftId,
  businessDate: businessDate,
  deviceId: shiftDeviceId,
  serverConfirmedOpen: true,
  closeInProgress: closeInProgress,
  declaration: declaration,
  openingFloatMinor: openingFloatMinor,
  updatedAt: DateTime.utc(2026, 7, 31, 9),
  openedAt: openedAt ?? DateTime.utc(2026, 7, 31, 9),
);

final class ShiftServer {
  /// Held by a test that needs a write to still be in flight while it does
  /// something else - popping the route that started it, or switching business
  /// underneath it. Completing the gate lets the write finish.
  Completer<void>? createGate;
  Completer<void>? updateGate;

  final Map<String, Map<String, Object?>> shifts =
      <String, Map<String, Object?>>{};
  final List<String> reads = <String>[];
  final List<(String, Map<String, Object?>)> created =
      <(String, Map<String, Object?>)>[];
  final List<(String, Map<String, Object?>)> updated =
      <(String, Map<String, Object?>)>[];

  Future<void> create(String path, Map<String, Object?> data) async {
    await createGate?.future;
    created.add((path, data));
    shifts[path] = <String, Object?>{
      ...data,
      'startTime': Timestamp.fromDate(DateTime.utc(2026, 7, 31, 6)),
    };
  }

  Future<void> update(String path, Map<String, Object?> data) async {
    await updateGate?.future;
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

/// A reader over [ShiftServer], which is a server and holds no local copy.
///
/// **It answers [serverOnly] with itself, and that is not a shortcut.** Every
/// read here goes to `_server.shifts` - there is no cache in this fake for an
/// answer to come out of - so a server-only read and an ordinary one are the
/// same read, which is exactly what the interface is claiming. A fake that
/// declined the mode would make `TenantShiftController._settle` unable to
/// confirm anything, which is the *failure* shape of H2's fix rather than its
/// working one.
final class ShiftReader implements TenantDataReader, TenantServerReadable {
  ShiftReader(this._server);

  final ShiftServer _server;

  @override
  TenantDataReader get serverOnly => this;

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
final class ShiftLedger implements ShiftSalesLedger {
  const ShiftLedger(this.summary);

  final ShiftSalesSummary summary;

  @override
  Future<ShiftSalesSummary> summarize({
    required String uid,
    required String tenantId,
    required String shiftId,
  }) async => summary;
}

TenantMembership shiftMembership(
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
