import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../checkout/checkout_receipt.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import 'shift_declaration.dart';
import 'shift_sales_ledger.dart';
import '../observability/app_telemetry.dart';

// The bound moved to the declaration, which owns every money figure a close
// records. Re-exported so the many callers that reach for it through this
// library keep working.
export 'shift_declaration.dart' show maximumShiftCashMinor;

/// Raised when canonical shift state cannot be trusted for this session.
final class TenantShiftException implements Exception {
  const TenantShiftException(this.code);

  final String code;

  @override
  String toString() => 'TenantShiftException($code)';
}

/// The two lifecycle states a canonical shift document may hold.
enum TenantShiftStatus {
  open('open'),
  closed('closed');

  const TenantShiftStatus(this.wireValue);

  final String wireValue;

  static TenantShiftStatus fromWire(Object? value) => switch (value) {
    'open' => TenantShiftStatus.open,
    'closed' => TenantShiftStatus.closed,
    _ => throw const TenantShiftException('invalid_shift_status'),
  };
}

/// Strict read model for `tenants/{tenantId}/shifts/{shiftId}`.
///
/// Every field the lifecycle depends on must be exactly valid, and the
/// document must repeat the tenant and shift identity encoded in its own path.
/// `startTime` and `endTime` are server-owned, so they may briefly be absent
/// while a write is still pending; any other shape is refused.
final class TenantShift {
  factory TenantShift.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.shifts.segment) {
      throw const TenantShiftException('invalid_shift_path');
    }
    final String tenantId;
    final String shiftId;
    try {
      tenantId = validateTenantId(segments[1]);
      shiftId = validateTenantDocumentId(segments[3], fieldName: 'shiftId');
    } on ArgumentError {
      throw const TenantShiftException('invalid_shift_path');
    }
    if (data['shiftId'] != shiftId || data['tenantId'] != tenantId) {
      throw const TenantShiftException('shift_identity_mismatch');
    }
    return TenantShift._(
      id: shiftId,
      tenantId: tenantId,
      staffId: _requiredDocumentId(data, 'staffId'),
      deviceId: _requiredDeviceId(data),
      businessDate: _requiredBusinessDate(data),
      status: TenantShiftStatus.fromWire(data['status']),
      startedAt: _earlier(
        _optionalInstant(data, 'openedAt'),
        _optionalInstant(data, 'startTime'),
      ),
      endedAt: _endedAt(data),
      closingCashMinor: _optionalNonNegativeInteger(data, 'closingCashMinor'),
      openingFloatMinor:
          _optionalNonNegativeInteger(data, 'openingFloatMinor') ?? 0,
      declaration: _optionalDeclaration(data),
      closedWithoutEvidence: _optionalTrueFlag(data, 'closedWithoutEvidence'),
    );
  }

  const TenantShift._({
    required this.id,
    required this.tenantId,
    required this.staffId,
    required this.deviceId,
    required this.businessDate,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.closingCashMinor,
    required this.openingFloatMinor,
    required this.declaration,
    required this.closedWithoutEvidence,
  });

  final String id;
  final String tenantId;
  final String staffId;
  final String deviceId;
  final String businessDate;
  final TenantShiftStatus status;

  /// When the cashier opened the shift, by the device that opened it.
  ///
  /// **The device's `openedAt`, held to the server's `startTime`, since
  /// 2026-09-25.** A shift opened offline reaches the server hours later, and
  /// `startTime` alone said it began then. The device's clock is believed
  /// unless it claims a time after the open arrived, which it cannot be; the
  /// server keeps `startTime` for itself.
  final DateTime? startedAt;

  /// When the drawer was counted and the shift closed - `closedAt` held to
  /// `endTime`, as [startedAt] is, and never before [startedAt].
  final DateTime? endedAt;
  final int? closingCashMinor;

  /// The change the drawer started the shift with, in minor units.
  ///
  /// **Zero and absent are the same answer**, which is why this is not
  /// nullable: a shop that floats no change and a shop that has never recorded
  /// one both expect their takings compared against their sales alone. Every
  /// shift written before the float existed reads as zero, so no history
  /// changes meaning under it.
  ///
  /// **It is part of what the drawer should hold, not part of what the shift
  /// took.** The cashier counts the whole drawer at close, float included, and
  /// reconciliation adds this to the cash its sales expect - so the float
  /// cancels out and a balanced drawer reads as balanced. Without it, a shop
  /// that floats its till books that float as a surplus every single day.
  ///
  /// Fixed at open and never rewritten: the close rule's `affectedKeys` does
  /// not list it, so the server refuses a close that would move it.
  final int openingFloatMinor;

  /// What the cashier declared the till held, by payment method.
  ///
  /// Absent on every shift closed before the declaration existed, and on one
  /// still open. Never partial: a document carrying some of the three is
  /// refused rather than read as the rest being zero.
  final ShiftTenderDeclaration? declaration;

  /// Whether this shift was closed by a device that held none of its sales.
  ///
  /// Its zero summary describes what that device could prove, which is nothing
  /// - not what the shift took. See
  /// `TenantShiftRepository.buildRecoveryCloseIntent`.
  final bool closedWithoutEvidence;

  bool get isOpen => status == TenantShiftStatus.open;
}

/// A validated create instruction for exactly one tenant shift document.
///
/// Only [TenantShiftRepository] can build one, so no caller can name an
/// arbitrary Firestore path. The server-owned `startTime` is deliberately not
/// part of the data: the writer adds it so the client cannot choose it.
final class TenantShiftOpenIntent {
  const TenantShiftOpenIntent._({
    required this.path,
    required this.tenantId,
    required this.shiftId,
    required this.staffId,
    required this.deviceId,
    required this.businessDate,
    required this.openedAt,
    required this.openingFloatMinor,
  });

  final String path;
  final String tenantId;
  final String shiftId;
  final String staffId;
  final String deviceId;
  final String businessDate;

  /// When the cashier opened the shift, by this device's clock - written beside
  /// the server's `startTime` as `openedAt`. See [TenantShift.startedAt].
  final DateTime openedAt;

  /// The change the drawer starts with, in minor units. See
  /// [TenantShift.openingFloatMinor].
  final int openingFloatMinor;

  Map<String, Object?> documentData() => <String, Object?>{
    'shiftId': shiftId,
    'tenantId': tenantId,
    'staffId': staffId,
    'deviceId': deviceId,
    'businessDate': businessDate,
    'status': TenantShiftStatus.open.wireValue,
    // **Omitted entirely when there is no float**, rather than written as a
    // zero. Absent and zero mean the same thing to every reader, and a shop
    // that keeps no change in the drawer should not have a field about one on
    // every shift it ever opens.
    if (openingFloatMinor > 0) 'openingFloatMinor': openingFloatMinor,
  };
}

/// A validated close instruction for one already-open tenant shift.
///
/// The close carries the sale-derived aggregates nightly reconciliation
/// compares against its own per-shift expectation. They are computed only from
/// sales this device can prove the server already holds.
final class TenantShiftCloseIntent {
  const TenantShiftCloseIntent._({
    required this.path,
    required this.tenantId,
    required this.shiftId,
    required this.closingCashMinor,
    required this.totalSalesMinor,
    required this.transactionCount,
    required this.closedAt,
    this.declaration,
    this.closedWithoutEvidence = false,
    this.settlementId,
    this.creditOwedMinor = 0,
    this.repaidMinor = 0,
  });

  final String path;
  final String tenantId;
  final String shiftId;

  /// The part of [totalSalesMinor] customers took on credit, and what they
  /// paid back into this drawer - so the shift's own history row can tell a
  /// drawer that is short from one whose customers owe. Written only when
  /// there is one; reconciliation counts both again itself.
  final int creditOwedMinor;
  final int repaidMinor;

  /// When the drawer was counted, by this device's clock - written beside the
  /// server's `endTime` as `closedAt`. See [TenantShift.endedAt].
  final DateTime closedAt;
  final int closingCashMinor;
  final int totalSalesMinor;
  final int transactionCount;

  /// What the cashier said the till held, by payment method.
  ///
  /// **Null only for a replay of a close recorded by an earlier build.** A
  /// device that counted its drawer offline before this shape existed holds a
  /// record with a cash figure and nothing else, and that close must still be
  /// sendable - refusing it would strand a closed shift on the device forever.
  final ShiftTenderDeclaration? declaration;

  /// Whether this close is being made by a device holding none of the shift's
  /// sales, which is why its summary is zero.
  ///
  /// See `TenantShiftController.closeShiftWithoutEvidence`. The flag is what
  /// stops a zero summary reading as a shift that took nothing: reconciliation
  /// refuses to believe the figures rather than reporting a variance against
  /// them.
  final bool closedWithoutEvidence;

  /// The one drawer count this close belongs to, shared by every shift it
  /// settled.
  ///
  /// **A cashier holds one register, so they count one drawer.** When a close
  /// sweeps up shifts left open elsewhere, all of them are settled by that
  /// single count - and reconciliation has to know, because it builds its
  /// expectation per shift. Without this it measured a whole drawer against one
  /// shift's sales and reported the counted shift as over by exactly what the
  /// others took, while calling the others unverifiable.
  ///
  /// **Null is the ordinary close of an ordinary day**, and reads exactly as it
  /// always has: a shift compared against itself. Nothing is backfilled, so a
  /// shift closed before this existed keeps the answer it was given.
  final String? settlementId;

  Map<String, Object?> updateData() => <String, Object?>{
    'status': TenantShiftStatus.closed.wireValue,
    'closingCashMinor': closingCashMinor,
    // The major-unit mirror matches the money convention of the sale document
    // that reporting already aggregates. Minor units remain authoritative.
    'closingCash': closingCashMinor / 100,
    'totalSalesMinor': totalSalesMinor,
    'totalSales': totalSalesMinor / 100,
    'transactionCount': transactionCount,
    // All three keys or none. `declaredCashMinor` restates `closingCashMinor`
    // rather than replacing it, so no reader can be shown two cash figures that
    // disagree, and every surface built on the old name keeps working.
    if (declaration case final declared?) ...<String, Object?>{
      'declaredCashMinor': declared.cashMinor,
      'declaredMpesaMinor': declared.mpesaMinor,
      'declaredCardMinor': declared.cardMinor,
    },
    // Written only when true. An ordinary close omits it, which is what lets
    // the rules treat its presence as the whole of the claim.
    if (closedWithoutEvidence) 'closedWithoutEvidence': true,
    // Omitted rather than written null, so a close that settles only itself
    // costs no field and reconciliation's grouping never has to tell a null
    // apart from an absence.
    if (settlementId case final settlement?) 'settlementId': settlement,
    if (creditOwedMinor > 0) 'creditOwedMinor': creditOwedMinor,
    if (repaidMinor > 0) 'repaidMinor': repaidMinor,
  };
}

/// Guarded read/intent boundary for one tenant's shifts.
///
/// Reads derive every path from the session's [TenantPaths] and refuse a shift
/// that belongs to another cashier, so a device can never restore or close a
/// colleague's shift.
final class TenantShiftRepository extends TenantReadRepository {
  TenantShiftRepository({required super.session, required super.reader});

  /// Reads one canonical shift by exact document ID.
  Future<TenantShift?> readShift(String shiftId) async {
    final safeId = _validatedShiftId(shiftId);
    final data = await readDocument(TenantCollection.shifts, safeId);
    if (data == null) return null;
    final shift = TenantShift.fromDocument(
      path: paths.shift(safeId),
      data: data,
    );
    if (shift.tenantId != session.tenantId) {
      throw const TenantShiftException('cross_tenant_shift');
    }
    if (shift.staffId != session.uid) {
      throw const TenantShiftException('foreign_shift');
    }
    return shift;
  }

  /// Builds the create for one shift, with the change its drawer starts with.
  ///
  /// [openingFloatMinor] defaults to none, so every existing caller opens a
  /// shift that took no float and is compared against its sales alone - which
  /// is exactly what those shifts meant before the field existed.
  TenantShiftOpenIntent buildOpenIntent({
    required String shiftId,
    required String deviceId,
    required String businessDate,
    required DateTime openedAt,
    int openingFloatMinor = 0,
  }) {
    if (openingFloatMinor < 0 || openingFloatMinor > maximumShiftCashMinor) {
      throw const TenantShiftException('invalid_opening_float');
    }
    final safeId = _validatedShiftId(shiftId);
    final String safeDeviceId;
    final String safeBusinessDate;
    try {
      safeDeviceId = validateCheckoutDeviceId(deviceId);
      safeBusinessDate = validateCheckoutBusinessDate(businessDate);
    } on ArgumentError {
      throw const TenantShiftException('invalid_shift_document');
    }
    return TenantShiftOpenIntent._(
      path: paths.shift(safeId),
      tenantId: session.tenantId,
      shiftId: safeId,
      staffId: session.uid,
      deviceId: safeDeviceId,
      businessDate: safeBusinessDate,
      openedAt: openedAt.toUtc(),
      openingFloatMinor: openingFloatMinor,
    );
  }

  TenantShiftCloseIntent buildCloseIntent({
    required TenantShift shift,
    required int closingCashMinor,
    required ShiftSalesSummary sales,
    required DateTime closedAt,
    ShiftTenderDeclaration? declaration,
    String? settlementId,
  }) {
    _assertClosable(shift);
    if (closingCashMinor < 0 || closingCashMinor > maximumShiftCashMinor) {
      throw const TenantShiftException('invalid_closing_cash');
    }
    // **The same money, stated twice.** `closingCashMinor` is what every
    // existing surface reads and `declaredCashMinor` is what reconciliation
    // compares, so a close that let them differ would put two cash figures for
    // one drawer into one document.
    if (declaration != null && declaration.cashMinor != closingCashMinor) {
      throw const TenantShiftException('declaration_disagrees_with_cash');
    }
    // An incomplete summary would understate the shift and guarantee a
    // reconciliation variance, so it can never become a closing summary.
    if (!sales.isComplete) {
      throw const TenantShiftException('unsynchronized_shift_sales');
    }
    if (sales.transactionCount < 0 ||
        sales.totalMinor < 0 ||
        sales.totalMinor > maximumShiftSalesMinor ||
        (sales.totalMinor > 0 && sales.transactionCount == 0)) {
      throw const TenantShiftException('invalid_shift_sales_summary');
    }
    return TenantShiftCloseIntent._(
      path: paths.shift(_validatedShiftId(shift.id)),
      tenantId: session.tenantId,
      shiftId: shift.id,
      closingCashMinor: closingCashMinor,
      totalSalesMinor: sales.totalMinor,
      transactionCount: sales.transactionCount,
      closedAt: closedAt.toUtc(),
      declaration: declaration,
      settlementId: settlementId,
      creditOwedMinor:
          sales.creditOwedMinor > 0 && sales.creditOwedMinor <= sales.totalMinor
          ? sales.creditOwedMinor
          : 0,
      repaidMinor: sales.repaidMinor > 0 ? sales.repaidMinor : 0,
    );
  }

  /// Closes a shift this device holds none of the sales for.
  ///
  /// **The summary is zero because it is unknown, and the flag says so.** The
  /// closing figures are built from local sale evidence, which only the
  /// installation that opened the shift ever held - so a device recovering a
  /// shift left open elsewhere has nothing to summarize and must not invent
  /// one. `closedWithoutEvidence` is what stops the zeros being read as a shift
  /// that took nothing: reconciliation refuses the figures outright rather than
  /// reporting a variance against them.
  ///
  /// The declaration is still asked for and still recorded. It needs no sale
  /// evidence - the person is standing at the drawer - and reconciliation
  /// derives the other side of the comparison from the sales the server already
  /// holds. So a recovery close says *more* than the dead end it replaces.
  ///
  /// **Null where the drawer has already been counted onto another shift.** A
  /// cashier who ends up with two open shifts for one till counts that till
  /// once, and the count belongs to whichever shift can carry it; asking again
  /// here would take a second figure for money that has already been declared,
  /// and every surface downstream would then hold one drawer twice. An omitted
  /// declaration writes no declared keys at all - which the rules permit, and
  /// which `compareShiftTenders` reads as *unverifiable* rather than as a
  /// declaration a current build should have recorded and did not.
  TenantShiftCloseIntent buildRecoveryCloseIntent({
    required TenantShift shift,
    required DateTime closedAt,
    ShiftTenderDeclaration? declaration,
    String? settlementId,
  }) {
    _assertClosable(shift);
    return TenantShiftCloseIntent._(
      path: paths.shift(_validatedShiftId(shift.id)),
      tenantId: session.tenantId,
      shiftId: shift.id,
      // Zero because nothing was counted onto this shift, which is the same
      // thing its zero summary says. The rules require the field; they do not
      // require it to claim anything.
      closingCashMinor: declaration?.cashMinor ?? 0,
      totalSalesMinor: 0,
      transactionCount: 0,
      closedAt: closedAt.toUtc(),
      declaration: declaration,
      closedWithoutEvidence: true,
      settlementId: settlementId,
    );
  }

  /// The three facts that must hold before any close may be built.
  void _assertClosable(TenantShift shift) {
    if (shift.tenantId != session.tenantId) {
      throw const TenantShiftException('cross_tenant_shift');
    }
    if (shift.staffId != session.uid) {
      throw const TenantShiftException('foreign_shift');
    }
    if (!shift.isOpen) {
      throw const TenantShiftException('shift_not_open');
    }
  }

  /// Finds this cashier's open shifts in this business, bounded and ordered.
  ///
  /// Restoration after a lost local record must discover the canonical shift
  /// rather than open a duplicate. The query is filtered by the authenticated
  /// UID and the open status only; every returned document is still proved to
  /// be an exact child of this tenant's shift collection and to belong to this
  /// cashier before it is trusted.
  Future<List<TenantShift>> findOpenShifts({
    required TenantCollectionReader collectionReader,
    int limit = 5,
  }) async {
    final page = await readCollectionPage(
      TenantCollection.shifts,
      collectionReader: collectionReader,
      pageSize: limit,
      equalityFilters: <String, Object?>{
        'staffId': session.uid,
        'status': TenantShiftStatus.open.wireValue,
      },
    );
    final shifts = <TenantShift>[];
    for (final item in page.items) {
      final shift = TenantShift.fromDocument(path: item.path, data: item.data);
      if (shift.tenantId != session.tenantId) {
        throw const TenantShiftException('cross_tenant_shift');
      }
      if (shift.staffId != session.uid) {
        throw const TenantShiftException('foreign_shift');
      }
      if (!shift.isOpen) {
        throw const TenantShiftException('shift_not_open');
      }
      shifts.add(shift);
    }
    return List<TenantShift>.unmodifiable(shifts);
  }

  String _validatedShiftId(String shiftId) {
    try {
      return validateTenantDocumentId(shiftId, fieldName: 'shiftId');
    } on ArgumentError {
      throw const TenantShiftException('invalid_shift_id');
    }
  }
}

enum TenantShiftWriteKind {
  /// The server acknowledged the write.
  committed,

  /// The server refused the write; a canonical re-read decides what exists.
  rejected,

  /// The outcome is unknown; only a canonical re-read may settle it.
  ambiguous,

  /// No attempt was made because the device was offline.
  unavailable,
}

final class TenantShiftWriteResult {
  const TenantShiftWriteResult._(this.kind, [this.reasonCode]);

  const TenantShiftWriteResult.committed()
    : this._(TenantShiftWriteKind.committed);

  const TenantShiftWriteResult.rejected(String reasonCode)
    : this._(TenantShiftWriteKind.rejected, reasonCode);

  const TenantShiftWriteResult.ambiguous(String reasonCode)
    : this._(TenantShiftWriteKind.ambiguous, reasonCode);

  const TenantShiftWriteResult.unavailable()
    : this._(TenantShiftWriteKind.unavailable);

  final TenantShiftWriteKind kind;
  final String? reasonCode;
}

/// The narrow write boundary used by the shift lifecycle.
abstract interface class TenantShiftWriter {
  Future<TenantShiftWriteResult> openShift(TenantShiftOpenIntent intent);

  Future<TenantShiftWriteResult> closeShift(TenantShiftCloseIntent intent);
}

typedef TenantShiftOnlineCheck = Future<bool> Function();
typedef TenantShiftDocumentCreator =
    Future<void> Function(String path, Map<String, Object?> data);
typedef TenantShiftDocumentUpdater =
    Future<void> Function(String path, Map<String, Object?> data);

/// Firestore implementation of the shift write boundary.
///
/// The open write uses `set`, so reusing an existing shift ID is an update the
/// Rules deny rather than a silent overwrite. `startTime` and `endTime` are
/// always server timestamps, which the Rules require, so a device clock can
/// never decide when a shift began or ended.
final class FirebaseTenantShiftWriter implements TenantShiftWriter {
  FirebaseTenantShiftWriter({
    FirebaseFirestore? firestore,
    required TenantShiftOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(
         create: _firestoreCreator(firestore ?? FirebaseFirestore.instance),
         update: _firestoreUpdater(firestore ?? FirebaseFirestore.instance),
         isOnline: isOnline,
         writeTimeout: writeTimeout,
       );

  FirebaseTenantShiftWriter.forTesting({
    required TenantShiftDocumentCreator create,
    required TenantShiftDocumentUpdater update,
    required TenantShiftOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(
         create: create,
         update: update,
         isOnline: isOnline,
         writeTimeout: writeTimeout,
       );

  FirebaseTenantShiftWriter._({
    required TenantShiftDocumentCreator create,
    required TenantShiftDocumentUpdater update,
    required TenantShiftOnlineCheck isOnline,
    required Duration writeTimeout,
  }) : _create = create,
       _update = update,
       _isOnline = isOnline,
       _writeTimeout = writeTimeout {
    if (writeTimeout <= Duration.zero) {
      throw ArgumentError.value(writeTimeout, 'writeTimeout');
    }
  }

  static const Set<String> _rejectedCodes = <String>{
    'permission-denied',
    'unauthenticated',
    'invalid-argument',
    'not-found',
    'already-exists',
    'failed-precondition',
    'out-of-range',
  };

  final TenantShiftDocumentCreator _create;
  final TenantShiftDocumentUpdater _update;
  final TenantShiftOnlineCheck _isOnline;
  final Duration _writeTimeout;

  @override
  Future<TenantShiftWriteResult> openShift(TenantShiftOpenIntent intent) {
    _assertTenantScopedPath(intent.path, intent.tenantId, intent.shiftId);
    return _write(
      () => _create(intent.path, <String, Object?>{
        ...intent.documentData(),
        'startTime': FieldValue.serverTimestamp(),
        'openedAt': Timestamp.fromDate(intent.openedAt),
      }),
    );
  }

  @override
  Future<TenantShiftWriteResult> closeShift(TenantShiftCloseIntent intent) {
    _assertTenantScopedPath(intent.path, intent.tenantId, intent.shiftId);
    return _write(
      () => _update(intent.path, <String, Object?>{
        ...intent.updateData(),
        'endTime': FieldValue.serverTimestamp(),
        'closedAt': Timestamp.fromDate(intent.closedAt),
      }),
    );
  }

  Future<TenantShiftWriteResult> _write(Future<void> Function() action) async {
    if (!await _online()) return const TenantShiftWriteResult.unavailable();
    try {
      await action().timeout(_writeTimeout);
      return const TenantShiftWriteResult.committed();
    } on TimeoutException {
      return const TenantShiftWriteResult.ambiguous('write_timeout');
    } on FirebaseException catch (error) {
      return _rejectedCodes.contains(error.code)
          ? TenantShiftWriteResult.rejected(error.code)
          : TenantShiftWriteResult.ambiguous(error.code);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(error, stackTrace, boundary: 'shift.write');
      return const TenantShiftWriteResult.ambiguous('unknown_error');
    }
  }

  Future<bool> _online() async {
    try {
      return await _isOnline();
    } catch (_) {
      return false;
    }
  }

  static void _assertTenantScopedPath(
    String path,
    String tenantId,
    String shiftId,
  ) {
    if (TenantPaths(tenantId).shift(shiftId) != path) {
      throw const TenantShiftException('shift_path_escaped_tenant');
    }
  }

  static TenantShiftDocumentCreator _firestoreCreator(
    FirebaseFirestore firestore,
  ) =>
      (path, data) => firestore.doc(path).set(data);

  static TenantShiftDocumentUpdater _firestoreUpdater(
    FirebaseFirestore firestore,
  ) =>
      (path, data) => firestore.doc(path).update(data);
}

/// Counts one shift's sales on the server with a single aggregate query.
///
/// **One read per thousand sales rather than one per sale**, which is why this
/// is an aggregate and not a page walk: it runs on every close. Filtered to the
/// cashier as well as the shift because the Rules let a cashier query `sales`
/// only where every possible result is provably their own - and a shift is
/// only ever its cashier's, so the filter narrows nothing that belongs.
///
/// Always from the server. An aggregate cannot be answered from the cache, and
/// a figure the cache made up is exactly what the fallback exists to avoid.
final class FirebaseShiftServerSalesTotals implements ShiftServerSalesTotals {
  FirebaseShiftServerSalesTotals({
    FirebaseFirestore? firestore,
    Duration timeout = const Duration(seconds: 10),
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _timeout = timeout;

  final FirebaseFirestore _firestore;
  final Duration _timeout;

  @override
  Future<ShiftServerTotals?> read({
    required String tenantId,
    required String uid,
    required String shiftId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(TenantPaths(tenantId).sales)
          .where('shiftId', isEqualTo: shiftId)
          .where('soldById', isEqualTo: uid)
          .aggregate(count(), sum('totalMinor'), sum('creditOwedMinor'))
          .get(source: AggregateSource.server)
          .timeout(_timeout);
      final transactionCount = snapshot.count;
      final total = snapshot.getSum('totalMinor');
      // A sale paid in full has no `creditOwedMinor`, which a sum skips.
      final owed = snapshot.getSum('creditOwedMinor') ?? 0;
      if (transactionCount == null || transactionCount < 0 || total == null) {
        return null;
      }
      // Stored as whole minor units, so a sum that is not one is a record
      // this cannot vouch for.
      if (total < 0 || total != total.roundToDouble()) return null;
      if (owed < 0 || owed > total || owed != owed.roundToDouble()) {
        return null;
      }
      return ShiftServerTotals(
        transactionCount: transactionCount,
        totalMinor: total.toInt(),
        creditOwedMinor: owed.toInt(),
        repaidMinor: await _repaid(tenantId: tenantId, uid: uid, shiftId: shiftId),
      );
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'shift.server_totals_read',
      );
      return null;
    }
  }
}

extension on FirebaseShiftServerSalesTotals {
  /// What customers paid back into the shift, counted on the server, or null
  /// where that could not be read. Rules let a cashier read the payments they
  /// took, which is exactly what this filters to.
  Future<int?> _repaid({
    required String tenantId,
    required String uid,
    required String shiftId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(TenantPaths(tenantId).collectionPath(
            TenantCollection.customerPayments,
          ))
          .where('shiftId', isEqualTo: shiftId)
          .where('recordedBy', isEqualTo: uid)
          .aggregate(sum('amountMinor'))
          .get(source: AggregateSource.server)
          .timeout(_timeout);
      final repaid = snapshot.getSum('amountMinor') ?? 0;
      if (repaid < 0 || repaid != repaid.roundToDouble()) return null;
      return repaid.toInt();
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'shift.server_repaid_read',
      );
      return null;
    }
  }
}

String _requiredDocumentId(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String) {
    throw const TenantShiftException('invalid_shift_document');
  }
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw const TenantShiftException('invalid_shift_document');
  }
}

String _requiredDeviceId(Map<String, Object?> data) {
  final value = data['deviceId'];
  if (value is! String) {
    throw const TenantShiftException('invalid_shift_document');
  }
  try {
    return validateCheckoutDeviceId(value);
  } on ArgumentError {
    throw const TenantShiftException('invalid_shift_document');
  }
}

String _requiredBusinessDate(Map<String, Object?> data) {
  final value = data['businessDate'];
  if (value is! String) {
    throw const TenantShiftException('invalid_shift_document');
  }
  try {
    return validateCheckoutBusinessDate(value);
  } on ArgumentError {
    throw const TenantShiftException('invalid_shift_document');
  }
}

/// The earlier of a device's instant and the server's for one event.
///
/// A device may be offline when it opens or closes a shift, so its own time is
/// the one that happened - but a device clock running fast could claim a time
/// after the server received the write, which no event can be. Either alone is
/// used when the other is absent: a write still pending in the cache has no
/// server time yet.
DateTime? _earlier(DateTime? device, DateTime? server) {
  if (device == null) return server;
  if (server == null) return device;
  return device.isBefore(server) ? device : server;
}

/// [TenantShift.endedAt], which a device clock running slow must not put
/// before the shift began.
DateTime? _endedAt(Map<String, Object?> data) {
  final ended = _earlier(
    _optionalInstant(data, 'closedAt'),
    _optionalInstant(data, 'endTime'),
  );
  final started = _earlier(
    _optionalInstant(data, 'openedAt'),
    _optionalInstant(data, 'startTime'),
  );
  if (ended == null || started == null) return ended;
  return ended.isBefore(started) ? started : ended;
}

DateTime? _optionalInstant(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantShiftException('invalid_shift_document');
}

int? _optionalNonNegativeInteger(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is! int || value < 0 || value > maximumShiftCashMinor) {
    throw const TenantShiftException('invalid_shift_document');
  }
  return value;
}

/// Decodes the declared tender triple, which is written all together or not.
///
/// A document carrying some of the three is refused rather than read with the
/// missing ones as zero: that would report a figure nobody declared, on the
/// surface a difference is settled from.
ShiftTenderDeclaration? _optionalDeclaration(Map<String, Object?> data) {
  const fields = <String>[
    'declaredCashMinor',
    'declaredMpesaMinor',
    'declaredCardMinor',
  ];
  final present = fields.where((field) => data[field] != null).length;
  if (present == 0) return null;
  if (present != fields.length) {
    throw const TenantShiftException('invalid_shift_document');
  }
  final declaration = ShiftTenderDeclaration.tryParse(
    cash: _optionalNonNegativeInteger(data, fields[0])!,
    mpesa: _optionalNonNegativeInteger(data, fields[1])!,
    card: _optionalNonNegativeInteger(data, fields[2])!,
  );
  if (declaration == null) {
    throw const TenantShiftException('invalid_shift_document');
  }
  return declaration;
}

/// Reads a flag that is only ever written `true`, so `false` is a defect.
bool _optionalTrueFlag(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return false;
  if (value != true) {
    throw const TenantShiftException('invalid_shift_document');
  }
  return true;
}
