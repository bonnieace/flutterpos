import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import '../checkout/checkout_sale.dart';
import '../sales/sale_history.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_types.dart';
import 'return_history.dart';

/// One sale line and how much of it may still be returned.
final class TenantReturnableLine {
  const TenantReturnableLine._({
    required this.productId,
    required this.name,
    required this.soldQuantity,
    required this.alreadyReturnedQuantity,
  });

  final String productId;
  final String name;
  final int soldQuantity;

  /// Units already covered by a recorded return, verified **or** pending.
  final int alreadyReturnedQuantity;

  int get remainingQuantity => soldQuantity - alreadyReturnedQuantity;
}

/// What one immutable sale still has available to return.
///
/// The server bounds a restoration by the immutable sale minus every
/// **verified** return. This model deliberately subtracts pending returns as
/// well: two pending returns that each fit on their own can jointly exceed the
/// sale, and the second verification would then fail with the customer already
/// gone. The server's bound remains the authority; this one is tighter on
/// purpose and is never the only check.
final class TenantReturnableSale {
  TenantReturnableSale._({
    required this.saleId,
    required this.receiptNumber,
    required List<TenantReturnableLine> lines,
  }) : lines = List<TenantReturnableLine>.unmodifiable(lines);

  final String saleId;
  final String receiptNumber;
  final List<TenantReturnableLine> lines;

  Iterable<TenantReturnableLine> get returnable =>
      lines.where((line) => line.remainingQuantity > 0);

  bool get hasReturnableLines => returnable.isNotEmpty;
}

/// One requested line of a return that has not been written yet.
final class TenantReturnRequestLine {
  const TenantReturnRequestLine._({
    required this.productId,
    required this.quantity,
  });

  final String productId;
  final int quantity;
}

/// A validated create instruction for exactly one tenant return document.
///
/// Only [TenantReturnRequestRepository] can build one, so no caller can name an
/// arbitrary Firestore path. The server-owned `createdAt` is deliberately not
/// part of the data: the writer adds it, so the device clock cannot decide when
/// a return was recorded.
final class TenantReturnCreateIntent {
  const TenantReturnCreateIntent._({
    required this.path,
    required this.returnId,
    required this.tenantId,
    required this.saleId,
    required this.createdBy,
    required this.reason,
    required this.lines,
  });

  final String path;
  final String returnId;
  final String tenantId;
  final String saleId;
  final String createdBy;
  final String reason;
  final List<TenantReturnRequestLine> lines;

  int get requestedUnits =>
      lines.fold(0, (total, line) => total + line.quantity);

  /// Exactly the key set the create rule freezes, and nothing else.
  Map<String, Object?> documentData() => <String, Object?>{
    'returnId': returnId,
    'tenantId': tenantId,
    'saleId': saleId,
    'createdBy': createdBy,
    'status': TenantReturnStatus.pending.wireValue,
    'reason': reason,
    'itemsReturned': <Object?>[
      for (final line in lines)
        <String, Object?>{
          // The create contract requires `productId`. The read model also
          // tolerates the server's `itemId` alias; a write never uses it.
          'productId': line.productId,
          'quantity': line.quantity,
        },
    ],
  };
}

/// Guarded read/intent boundary for recording a return against one sale.
final class TenantReturnRequestRepository extends TenantReadRepository {
  TenantReturnRequestRepository({
    required super.session,
    required super.reader,
  });

  /// Every active member may record a **pending** return.
  ///
  /// Recording changes no stock. Restoration runs through
  /// `verifyReturnAndRestoreStock`, which is owner/admin/manager-only, so the
  /// two steps are a deliberate two-person control rather than one privilege.
  /// A customer returns to whoever is at the till, so a cashier may record a
  /// return against a colleague's sale; `createdBy` records who did.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
    TenantRole.cashier,
  ];

  /// Reads one return by exact document ID.
  ///
  /// This is how an ambiguous write is settled. A retry must never write again
  /// under a new ID: the intent's document ID is deterministic, so the only
  /// safe question after an uncertain attempt is whether that exact document
  /// now exists.
  Future<TenantReturn?> readReturn(String returnId) async {
    final String safeId;
    try {
      safeId = validateTenantDocumentId(returnId, fieldName: 'returnId');
    } on ArgumentError {
      throw const TenantReturnException('invalid_return_id');
    }
    final data = await readDocument(TenantCollection.returns, safeId);
    if (data == null) return null;
    final record = TenantReturn.fromDocument(
      path: paths.returnRecord(safeId),
      data: data,
    );
    if (record.tenantId != session.tenantId) {
      throw const TenantReturnException('cross_tenant_return');
    }
    return record;
  }

  /// Derives what [sale] still has available to return.
  ///
  /// [recorded] must be the complete set of returns against this sale. A page
  /// that has more behind it is refused: a partial list would overstate the
  /// remaining quantity, which is the one number this screen exists to state.
  TenantReturnableSale describeReturnable({
    required TenantSale sale,
    required TenantReturnPage recorded,
  }) {
    if (sale.tenantId != session.tenantId) {
      throw const TenantReturnException('cross_tenant_sale');
    }
    if (recorded.hasMore) {
      throw const TenantReturnException('incomplete_return_history');
    }
    final sold = <String, int>{};
    final names = <String, String>{};
    for (final line in sale.lines) {
      sold[line.productId] = line.quantity;
      names[line.productId] = line.name;
    }

    final returned = <String, int>{};
    for (final record in recorded.items) {
      if (record.saleId != sale.id) {
        throw const TenantReturnException('return_sale_mismatch');
      }
      for (final line in record.lines) {
        final soldQuantity = sold[line.productId];
        final total = (returned[line.productId] ?? 0) + line.quantity;
        // A recorded return naming a product the sale never sold, or covering
        // more than it sold, is evidence the sale cannot be reconciled against.
        // It is reported rather than quietly clamped to zero.
        if (soldQuantity == null || total > soldQuantity) {
          throw const TenantReturnException('return_exceeds_sale');
        }
        returned[line.productId] = total;
      }
    }

    return TenantReturnableSale._(
      saleId: sale.id,
      receiptNumber: sale.receiptNumber,
      lines: <TenantReturnableLine>[
        for (final line in sale.lines)
          TenantReturnableLine._(
            productId: line.productId,
            name: line.name,
            soldQuantity: line.quantity,
            alreadyReturnedQuantity: returned[line.productId] ?? 0,
          ),
      ],
    );
  }

  /// Builds the one create instruction [quantities] describes.
  ///
  /// [requestId] scopes the deterministic document ID. One confirmation intent
  /// keeps one request ID, so a retry addresses the same document and the
  /// create rule - which forbids every update - refuses the replay instead of
  /// recording the return twice.
  TenantReturnCreateIntent buildCreateIntent({
    required TenantReturnableSale returnable,
    required Map<String, int> quantities,
    required String reason,
    required String requestId,
  }) {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantReturnException('return_forbidden');
    }
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw const TenantReturnException('invalid_return_request_id');
    }
    final safeReason = _normalizedReason(reason);
    final remaining = <String, int>{
      for (final line in returnable.lines)
        line.productId: line.remainingQuantity,
    };

    final lines = <TenantReturnRequestLine>[];
    // A sale carries at most `maximumCheckoutSaleLines` lines and the create
    // rule checks exactly that many positions, so a return can never exceed it.
    for (final entry in quantities.entries) {
      final quantity = entry.value;
      if (quantity == 0) continue;
      final available = remaining[entry.key];
      if (available == null || quantity < 0) {
        throw const TenantReturnException('invalid_return_quantities');
      }
      if (quantity > available) {
        throw const TenantReturnException('return_exceeds_sale');
      }
      lines.add(
        TenantReturnRequestLine._(productId: entry.key, quantity: quantity),
      );
    }
    if (lines.isEmpty || lines.length > maximumCheckoutSaleLines) {
      throw const TenantReturnException('invalid_return_quantities');
    }
    lines.sort((left, right) => left.productId.compareTo(right.productId));

    final returnId = _deterministicReturnId(
      tenantId: session.tenantId,
      saleId: returnable.saleId,
      createdBy: session.uid,
      requestId: requestId,
    );
    return TenantReturnCreateIntent._(
      path: paths.returnRecord(returnId),
      returnId: returnId,
      tenantId: session.tenantId,
      saleId: returnable.saleId,
      createdBy: session.uid,
      reason: safeReason,
      lines: lines,
    );
  }
}

/// The outcome of one attempted return write.
enum TenantReturnWriteKind {
  /// Saved durably on this device and waiting for synchronization.
  queued,

  /// The server acknowledged the write.
  committed,

  /// The server refused the write; a canonical re-read decides what exists.
  rejected,

  /// The outcome is unknown; only a canonical re-read may settle it.
  ambiguous,

  /// No attempt was made because the device was offline.
  unavailable,
}

final class TenantReturnWriteResult {
  const TenantReturnWriteResult._(this.kind, [this.reasonCode]);

  const TenantReturnWriteResult.committed()
    : this._(TenantReturnWriteKind.committed);

  const TenantReturnWriteResult.queued() : this._(TenantReturnWriteKind.queued);

  const TenantReturnWriteResult.rejected(String reasonCode)
    : this._(TenantReturnWriteKind.rejected, reasonCode);

  const TenantReturnWriteResult.ambiguous(String reasonCode)
    : this._(TenantReturnWriteKind.ambiguous, reasonCode);

  const TenantReturnWriteResult.unavailable()
    : this._(TenantReturnWriteKind.unavailable);

  final TenantReturnWriteKind kind;
  final String? reasonCode;
}

/// The narrow write boundary used to record a return.
abstract interface class TenantReturnWriter {
  Future<TenantReturnWriteResult> recordReturn(TenantReturnCreateIntent intent);
}

typedef TenantReturnOnlineCheck = Future<bool> Function();
typedef TenantReturnDocumentCreator =
    Future<void> Function(String path, Map<String, Object?> data);

/// Firestore implementation of the return write boundary.
///
/// The write uses `set`, so reusing a deterministic return ID is an update the
/// Rules deny rather than a silent overwrite. `createdAt` is always a server
/// timestamp, which the create rule requires.
final class FirebaseTenantReturnWriter implements TenantReturnWriter {
  FirebaseTenantReturnWriter({
    FirebaseFirestore? firestore,
    required TenantReturnOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(
         create: _firestoreCreator(firestore ?? FirebaseFirestore.instance),
         isOnline: isOnline,
         writeTimeout: writeTimeout,
       );

  FirebaseTenantReturnWriter.forTesting({
    required TenantReturnDocumentCreator create,
    required TenantReturnOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(create: create, isOnline: isOnline, writeTimeout: writeTimeout);

  FirebaseTenantReturnWriter._({
    required TenantReturnDocumentCreator create,
    required TenantReturnOnlineCheck isOnline,
    required Duration writeTimeout,
  }) : _create = create,
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

  final TenantReturnDocumentCreator _create;
  final TenantReturnOnlineCheck _isOnline;
  final Duration _writeTimeout;

  @override
  Future<TenantReturnWriteResult> recordReturn(
    TenantReturnCreateIntent intent,
  ) async {
    if (TenantPaths(intent.tenantId).returnRecord(intent.returnId) !=
        intent.path) {
      throw const TenantReturnException('return_path_escaped_tenant');
    }
    if (!await _online()) return const TenantReturnWriteResult.unavailable();
    try {
      await _create(intent.path, <String, Object?>{
        ...intent.documentData(),
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(_writeTimeout);
      return const TenantReturnWriteResult.committed();
    } on TimeoutException {
      return const TenantReturnWriteResult.ambiguous('write_timeout');
    } on FirebaseException catch (error) {
      return _rejectedCodes.contains(error.code)
          ? TenantReturnWriteResult.rejected(error.code)
          : TenantReturnWriteResult.ambiguous(error.code);
    } catch (_) {
      return const TenantReturnWriteResult.ambiguous('unknown_error');
    }
  }

  Future<bool> _online() async {
    try {
      return await _isOnline();
    } catch (_) {
      return false;
    }
  }

  static TenantReturnDocumentCreator _firestoreCreator(
    FirebaseFirestore firestore,
  ) =>
      (path, data) => firestore.doc(path).set(data);
}

/// A fresh request ID for one confirmation intent.
///
/// The same value must be reused across a retry of that intent, and a new one
/// created only for a genuinely new return.
String secureTenantReturnRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'return-${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// Derives the return's document ID from the identity the request is scoped by.
///
/// This mirrors the server's `actorUid + operation + tenantId + requestId`
/// idempotency scoping, so a double submit addresses one document instead of
/// recording the same reversal twice.
String _deterministicReturnId({
  required String tenantId,
  required String saleId,
  required String createdBy,
  required String requestId,
}) {
  final digest = sha256.convert(
    utf8.encode(
      <String>[
        'recordTenantReturn',
        tenantId,
        saleId,
        createdBy,
        requestId,
      ].join(' '),
    ),
  );
  return 'rt_${digest.toString().substring(0, 40)}';
}

/// Collapses whitespace and bounds the audit reason the create rule requires.
String _normalizedReason(String value) {
  final reason = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (reason.length < minimumReturnReasonLength ||
      reason.length > maximumReturnReasonLength) {
    throw const TenantReturnException('invalid_return_reason');
  }
  for (final codeUnit in reason.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantReturnException('invalid_return_reason');
    }
  }
  return reason;
}

const int minimumReturnReasonLength = 3;
const int maximumReturnReasonLength = 500;

final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
