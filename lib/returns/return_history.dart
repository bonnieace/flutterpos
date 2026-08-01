import 'package:cloud_firestore/cloud_firestore.dart';

import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';

/// Raised when a canonical return document cannot be trusted for display.
final class TenantReturnException implements Exception {
  const TenantReturnException(this.code);

  final String code;

  @override
  String toString() => 'TenantReturnException($code)';
}

/// Where a return stands in the server's own verification guard.
///
/// `verifyReturnAndRestoreStock` verifies a return exactly once and only from
/// `pending`. It treats `verified`, `restored`, `verified == true`, and
/// `stockRestored == true` as equally terminal, so this surface reads the same
/// evidence rather than trusting one field.
enum TenantReturnStatus {
  pending('pending'),

  /// Stock has been restored. `restored` is the second spelling the server's
  /// guard already treats as terminal, so it is read as the same state.
  verified('verified');

  const TenantReturnStatus(this.wireValue);

  final String wireValue;
}

/// One returned product line, as `normalizeReturnStockLines` reads it.
///
/// The server accepts `itemId` as an alias for `productId`, so this model does
/// too: a document the server would restore stock from must be a document this
/// screen can name the products of.
final class TenantReturnLine {
  const TenantReturnLine._({
    required this.productId,
    required this.quantity,
    required this.productName,
  });

  final String productId;
  final int quantity;

  /// The name the returning device recorded, when it recorded one. Stock is
  /// restored by product ID; a name is only ever a label here.
  final String? productName;
}

/// The server-written evidence a verified return carries.
///
/// Every field is written by `verifyReturnAndRestoreStock` inside one
/// transaction, so - unlike the client-written instants on a sale or a shift -
/// none of them is ever legitimately absent once the return is verified.
final class TenantReturnVerification {
  const TenantReturnVerification._({
    required this.verifiedBy,
    required this.verifiedAt,
    required this.stockRestorationId,
  });

  final String verifiedBy;
  final DateTime verifiedAt;

  /// The immutable `return_verifications` record that restored the stock.
  final String stockRestorationId;
}

/// Strict read model for `tenants/{tenantId}/returns/{returnId}`.
///
/// The field names are taken from `functions/src/operations/returns.ts` and
/// `domain.ts`, which are the only authority on this document: the verification
/// callable reads `tenantId`, `saleId`, `itemsReturned`, and the terminal-state
/// flags, and writes the verification evidence back. Nothing here is invented.
final class TenantReturn {
  factory TenantReturn.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.returns.segment) {
      throw const TenantReturnException('invalid_return_path');
    }
    final String tenantId;
    final String returnId;
    try {
      tenantId = validateTenantId(segments[1]);
      returnId = validateTenantDocumentId(segments[3], fieldName: 'returnId');
    } on ArgumentError {
      throw const TenantReturnException('invalid_return_path');
    }
    // The document repeats the business and the ID its own path encodes,
    // exactly as the create rule binds them. The verification callable will not
    // restore stock from a document whose tenant disagrees either.
    if (data['tenantId'] != tenantId || data['returnId'] != returnId) {
      throw const TenantReturnException('return_identity_mismatch');
    }

    return TenantReturn._(
      id: returnId,
      tenantId: tenantId,
      saleId: _requiredDocumentId(data, 'saleId'),
      createdBy: _requiredDocumentId(data, 'createdBy'),
      reason: _requiredReason(data),
      status: _requiredStatus(data),
      lines: _parseLines(data['itemsReturned']),
      verification: _verification(data),
      recordedAt: _optionalInstant(data, 'createdAt'),
    );
  }

  TenantReturn._({
    required this.id,
    required this.tenantId,
    required this.saleId,
    required this.createdBy,
    required this.reason,
    required this.status,
    required List<TenantReturnLine> lines,
    required this.verification,
    required this.recordedAt,
  }) : lines = List<TenantReturnLine>.unmodifiable(lines);

  final String id;
  final String tenantId;

  /// The immutable sale this return reverses.
  final String saleId;

  /// The cashier who recorded the return. Rules bind it on create.
  final String createdBy;

  /// The audit reason the create rule requires. A return without a recorded
  /// reason is not auditable, so it is not a document this surface accepts.
  final String reason;
  final TenantReturnStatus status;
  final List<TenantReturnLine> lines;

  /// Present exactly when [status] is verified.
  final TenantReturnVerification? verification;

  /// The server instant, absent only while a local create is still pending.
  final DateTime? recordedAt;

  bool get isVerified => status == TenantReturnStatus.verified;

  /// Total units this return covers, across its lines.
  int get returnedUnits =>
      lines.fold(0, (total, line) => total + line.quantity);

  /// Reads the terminal state from every field the server's guard consults.
  ///
  /// The callable refuses to verify a return when `status`, `verified`, or
  /// `stockRestored` is terminal, and refuses a `status` that is neither absent
  /// nor `pending`. A document whose flags disagree is therefore one the server
  /// would never verify, so listing it as awaiting verification would invite an
  /// action that cannot succeed. It is refused instead.
  static TenantReturnStatus _requiredStatus(Map<String, Object?> data) {
    final status = data['status'];
    final terminalStatus = status == 'verified' || status == 'restored';
    if (status != null && status != 'pending' && !terminalStatus) {
      throw const TenantReturnException('invalid_return_document');
    }
    final verified = _optionalFlag(data, 'verified');
    final stockRestored = _optionalFlag(data, 'stockRestored');
    final terminal = <bool>[terminalStatus, verified, stockRestored];
    if (terminal.contains(true) && terminal.contains(false)) {
      throw const TenantReturnException('inconsistent_return_state');
    }
    return terminal.contains(true)
        ? TenantReturnStatus.verified
        : TenantReturnStatus.pending;
  }

  /// A pending return carries no verification evidence, and a verified one
  /// carries all of it: the callable writes those fields in one transaction and
  /// the client can never write them at all.
  static TenantReturnVerification? _verification(Map<String, Object?> data) {
    final verified = _requiredStatus(data) == TenantReturnStatus.verified;
    final verifiedBy = data['verifiedBy'];
    final restorationId = data['stockRestorationId'];
    if (!verified) {
      if (verifiedBy != null ||
          restorationId != null ||
          data['verifiedAt'] != null ||
          data['stockRestoredAt'] != null) {
        throw const TenantReturnException('inconsistent_return_state');
      }
      return null;
    }
    return TenantReturnVerification._(
      verifiedBy: _requiredDocumentId(data, 'verifiedBy'),
      verifiedAt: _requiredInstant(data, 'verifiedAt'),
      stockRestorationId: _requiredDocumentId(data, 'stockRestorationId'),
    );
  }
}

/// One bounded page of returns, newest document ID first.
final class TenantReturnPage {
  TenantReturnPage({
    required List<TenantReturn> items,
    required this.nextCursor,
    required this.hasMore,
  }) : items = List<TenantReturn>.unmodifiable(items);

  final List<TenantReturn> items;
  final String? nextCursor;
  final bool hasMore;

  Iterable<TenantReturn> get pending =>
      items.where((record) => !record.isVerified);
  Iterable<TenantReturn> get verified =>
      items.where((record) => record.isVerified);
}

/// Guarded read boundary over the returns recorded against one sale.
///
/// Every path is derived from the session's [TenantPaths], and the exact-child,
/// uniqueness, and ordering proofs of [TenantReadRepository] still apply. A
/// return that names a different sale fails the page closed: the remaining
/// returnable quantity of a sale is computed from exactly these records, so a
/// foreign one would misstate it.
final class TenantReturnHistoryRepository extends TenantReadRepository {
  TenantReturnHistoryRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  final TenantCollectionReader _collectionReader;

  /// Pages the returns recorded against one immutable sale.
  Future<TenantReturnPage> loadSaleReturns({
    required String saleId,
    int pageSize = 20,
    String? cursor,
  }) async {
    final String safeSaleId;
    try {
      safeSaleId = validateTenantDocumentId(saleId, fieldName: 'saleId');
    } on ArgumentError {
      throw const TenantReturnException('invalid_sale_id');
    }
    final page = await readCollectionPage(
      TenantCollection.returns,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      descending: true,
      equalityFilters: <String, Object?>{'saleId': safeSaleId},
    );

    final items = <TenantReturn>[];
    for (final snapshot in page.items) {
      final record = TenantReturn.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (record.tenantId != session.tenantId) {
        throw const TenantReturnException('cross_tenant_return');
      }
      // The query filters by sale, but a transport that ignored the filter must
      // never attach another sale's reversal to this one.
      if (record.saleId != safeSaleId) {
        throw const TenantReturnException('return_sale_mismatch');
      }
      items.add(record);
    }
    return TenantReturnPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }
}

/// Every line must name a product and a positive quantity, exactly as
/// `normalizeReturnStockLines` requires before it will restore anything.
List<TenantReturnLine> _parseLines(Object? raw) {
  if (raw is! List || raw.isEmpty || raw.length > maximumReturnLines) {
    throw const TenantReturnException('invalid_return_lines');
  }
  final lines = <TenantReturnLine>[];
  final productIds = <String>{};
  for (final entry in raw) {
    if (entry is! Map) {
      throw const TenantReturnException('invalid_return_lines');
    }
    final line = <String, Object?>{
      for (final key in entry.keys)
        if (key is String) key: entry[key],
    };
    // The server reads `productId ?? itemId`; so does this model, so the two
    // can never disagree about which product a line names.
    final productId = _requiredDocumentId(
      line,
      line['productId'] != null ? 'productId' : 'itemId',
    );
    if (!productIds.add(productId)) {
      throw const TenantReturnException('duplicate_return_line');
    }
    final quantity = line['quantity'];
    if (quantity is! int ||
        quantity < 1 ||
        quantity > maximumReturnLineQuantity) {
      throw const TenantReturnException('invalid_return_lines');
    }
    lines.add(
      TenantReturnLine._(
        productId: productId,
        quantity: quantity,
        productName: _optionalName(line['productName']),
      ),
    );
  }
  return lines;
}

String? _optionalName(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const TenantReturnException('invalid_return_lines');
  }
  final name = value.trim();
  if (name.isEmpty || name.length > 200) return null;
  for (final codeUnit in name.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) return null;
  }
  return name;
}

String _requiredReason(Map<String, Object?> data) {
  final value = data['reason'];
  if (value is! String) {
    throw const TenantReturnException('invalid_return_document');
  }
  final reason = value.trim();
  if (reason.length < 3 || reason.length > 500) {
    throw const TenantReturnException('invalid_return_document');
  }
  for (final codeUnit in reason.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantReturnException('invalid_return_document');
    }
  }
  return reason;
}

String _requiredDocumentId(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String) {
    throw const TenantReturnException('invalid_return_document');
  }
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw const TenantReturnException('invalid_return_document');
  }
}

bool _optionalFlag(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return false;
  if (value is! bool) {
    throw const TenantReturnException('invalid_return_document');
  }
  return value;
}

DateTime _requiredInstant(Map<String, Object?> data, String field) {
  final value = _optionalInstant(data, field);
  if (value == null) {
    throw const TenantReturnException('invalid_return_document');
  }
  return value;
}

DateTime? _optionalInstant(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantReturnException('invalid_return_document');
}

/// `MAX_RETURN_LINES` in `functions/src/operations/domain.ts`.
const int maximumReturnLines = 50;

/// `MAX_QUANTITY_DELTA` in `functions/src/operations/domain.ts`.
const int maximumReturnLineQuantity = 1000000;
