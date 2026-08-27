import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../checkout/checkout_receipt.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import 'shift_sales_ledger.dart';

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
      startedAt: _optionalInstant(data, 'startTime'),
      endedAt: _optionalInstant(data, 'endTime'),
      closingCashMinor: _optionalNonNegativeInteger(data, 'closingCashMinor'),
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
  });

  final String id;
  final String tenantId;
  final String staffId;
  final String deviceId;
  final String businessDate;
  final TenantShiftStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? closingCashMinor;

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
  });

  final String path;
  final String tenantId;
  final String shiftId;
  final String staffId;
  final String deviceId;
  final String businessDate;

  Map<String, Object?> documentData() => <String, Object?>{
    'shiftId': shiftId,
    'tenantId': tenantId,
    'staffId': staffId,
    'deviceId': deviceId,
    'businessDate': businessDate,
    'status': TenantShiftStatus.open.wireValue,
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
  });

  final String path;
  final String tenantId;
  final String shiftId;
  final int closingCashMinor;
  final int totalSalesMinor;
  final int transactionCount;

  Map<String, Object?> updateData() => <String, Object?>{
    'status': TenantShiftStatus.closed.wireValue,
    'closingCashMinor': closingCashMinor,
    // The major-unit mirror matches the money convention of the sale document
    // that reporting already aggregates. Minor units remain authoritative.
    'closingCash': closingCashMinor / 100,
    'totalSalesMinor': totalSalesMinor,
    'totalSales': totalSalesMinor / 100,
    'transactionCount': transactionCount,
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

  TenantShiftOpenIntent buildOpenIntent({
    required String shiftId,
    required String deviceId,
    required String businessDate,
  }) {
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
    );
  }

  TenantShiftCloseIntent buildCloseIntent({
    required TenantShift shift,
    required int closingCashMinor,
    required ShiftSalesSummary sales,
  }) {
    if (shift.tenantId != session.tenantId) {
      throw const TenantShiftException('cross_tenant_shift');
    }
    if (shift.staffId != session.uid) {
      throw const TenantShiftException('foreign_shift');
    }
    if (!shift.isOpen) {
      throw const TenantShiftException('shift_not_open');
    }
    if (closingCashMinor < 0 || closingCashMinor > maximumShiftCashMinor) {
      throw const TenantShiftException('invalid_closing_cash');
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
    );
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

/// The largest counted cash amount a close may record, in minor units.
const int maximumShiftCashMinor = 1000000000000;

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
    } catch (_) {
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
