import 'package:cloud_firestore/cloud_firestore.dart';

import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import 'stock_adjustment.dart';
import 'stock_movements.dart';

/// Strict read model for `tenants/{tenantId}/stock_adjustments/{adjustmentId}`.
///
/// `functions/src/operations/stock.ts` is the only writer and the only
/// authority on these field names. It records the correction once here, once as
/// a `stock_movements` entry below the product, and once in `audit_logs`, all
/// inside the transaction that changes the quantity. This decodes what it finds
/// but refuses a record that contradicts its own path or its own arithmetic: a
/// business-wide correction feed that listed evidence disagreeing with itself
/// would be worse than one that reports the problem.
final class TenantStockAdjustmentRecord {
  factory TenantStockAdjustmentRecord.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 4 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.stockAdjustments.segment) {
      throw const TenantStockException('invalid_adjustment_path');
    }
    final String tenantId;
    final String adjustmentId;
    try {
      tenantId = validateTenantId(segments[1]);
      adjustmentId = validateTenantDocumentId(
        segments[3],
        fieldName: 'adjustmentId',
      );
    } on ArgumentError {
      throw const TenantStockException('invalid_adjustment_path');
    }
    // Unlike the movement below the product, this record does not repeat its
    // own ID, so its path is the one authority on which adjustment it is. The
    // business it names must still agree with the path it was read from.
    if (data['tenantId'] != tenantId) {
      throw const TenantStockException('adjustment_identity_mismatch');
    }

    final quantityDelta = _requiredInt(data, 'quantityDelta');
    if (quantityDelta == 0) {
      throw const TenantStockException('invalid_adjustment_delta');
    }
    // `adjustStock` reads the product inside its own transaction, so every
    // adjustment records both figures and they must add up. Unlike a
    // reconciled sale movement, there is no shape here that legitimately omits
    // them, and a record that cannot explain its own change is not evidence.
    final previousQuantity = _requiredInt(data, 'previousQuantity');
    final quantityAfter = _requiredInt(data, 'quantityAfter');
    if (quantityAfter != previousQuantity + quantityDelta) {
      throw const TenantStockException('inconsistent_adjustment_quantities');
    }

    final adjustmentType = _requiredString(data, 'adjustmentType');
    return TenantStockAdjustmentRecord._(
      id: adjustmentId,
      tenantId: tenantId,
      productId: _requiredDocumentId(data, 'productId'),
      sourceType: _requiredString(data, 'sourceType'),
      adjustmentType: adjustmentType,
      type: _parseAdjustmentType(adjustmentType),
      reason: _requiredString(data, 'reason'),
      actorUid: _requiredDocumentId(data, 'actorUid'),
      requestId: _optionalString(data, 'requestId'),
      quantityDelta: quantityDelta,
      previousQuantity: previousQuantity,
      quantityAfter: quantityAfter,
      occurredAt: _optionalInstant(data, 'occurredAt'),
      recordedAt: _optionalInstant(data, 'createdAt'),
    );
  }

  const TenantStockAdjustmentRecord._({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.sourceType,
    required this.adjustmentType,
    required this.type,
    required this.reason,
    required this.actorUid,
    required this.requestId,
    required this.quantityDelta,
    required this.previousQuantity,
    required this.quantityAfter,
    required this.occurredAt,
    required this.recordedAt,
  });

  final String id;
  final String tenantId;
  final String productId;

  /// Always `manual_adjustment` today. It is decoded rather than required so a
  /// server that starts recording another kind of correction here is named
  /// honestly instead of taking the feed down.
  final String sourceType;

  /// The raw typed category, kept so an unmodelled one can be shown as itself.
  final String adjustmentType;

  /// The modelled category, or null when this client does not know it yet.
  final TenantStockAdjustmentType? type;

  final String reason;
  final String actorUid;

  /// The idempotency key the actor's attempt carried, when it is recorded.
  final String? requestId;

  final int quantityDelta;
  final int previousQuantity;
  final int quantityAfter;

  /// When the adjustment was made, by the clock of the device that made it -
  /// hours before [recordedAt] when that device was offline.
  final DateTime? occurredAt;

  /// The server instant this correction was committed.
  final DateTime? recordedAt;

  bool get increasesStock => quantityDelta > 0;
}

/// One bounded page of the business's manual stock corrections.
final class TenantStockAdjustmentRecordPage {
  TenantStockAdjustmentRecordPage({
    required List<TenantStockAdjustmentRecord> items,
    required this.nextCursor,
    required this.hasMore,
    required this.productId,
  }) : items = List<TenantStockAdjustmentRecord>.unmodifiable(items);

  final List<TenantStockAdjustmentRecord> items;
  final String? nextCursor;
  final bool hasMore;

  /// The exact product this page was narrowed to, or null for the whole
  /// business. A surface states which one it is showing rather than implying
  /// that a filtered page is everything that was recorded.
  final String? productId;

  bool get isProductScoped => productId != null;
}

/// Guarded read boundary over one tenant's business-wide adjustment records.
///
/// Every path is derived from the session's [TenantPaths] and the exact-child,
/// uniqueness, page-size, and ordering proofs of [TenantReadRepository] still
/// apply. No caller can supply a collection path, an ordering, or a raw filter.
final class TenantStockAdjustmentFeedRepository extends TenantReadRepository {
  TenantStockAdjustmentFeedRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  /// The same roles `adjustStock` enforces and the per-product ledger reads.
  /// The surface that records a correction, the surface that explains one
  /// product's stock figure, and the surface that lists every correction in the
  /// business therefore agree about who may see them.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  final TenantCollectionReader _collectionReader;

  static bool canReadInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  /// Pages every manual correction recorded across the business.
  Future<TenantStockAdjustmentRecordPage> loadAdjustments({
    int pageSize = 20,
    String? cursor,
  }) => _load(pageSize: pageSize, cursor: cursor, productId: null);

  /// Pages the corrections recorded against one product.
  ///
  /// The filter is an exact `productId ==` equality on the same ascending key
  /// order, so it is served by Firestore's automatic single-field index and
  /// needs no composite index of its own.
  Future<TenantStockAdjustmentRecordPage> loadProductAdjustments({
    required String productId,
    int pageSize = 20,
    String? cursor,
  }) => _load(pageSize: pageSize, cursor: cursor, productId: productId);

  /// Reads one bounded page newest first, optionally narrowed to one product.
  ///
  /// **Ordered by `occurredAt` since 2026-09-25**, when the adjustment was
  /// made rather than when it reached the server - an adjustment made offline
  /// arrives hours later, and belongs where it happened.
  ///
  /// **Ordered by `createdAt` from 2026-09-14.** It used to be ordered by
  /// ascending document ID and said so, because an adjustment ID is `sa_` plus
  /// a digest of the actor, operation, tenant and request ID - an order
  /// carrying no time information whatever. The investigation this page exists
  /// for is *what was corrected most recently*, and answering it by reading
  /// every page and comparing instants by eye is not answering it.
  ///
  /// The product-filtered page needs a composite index; the unfiltered one is a
  /// single-field descending scan Firestore serves on its own. Both are in
  /// `firestore.indexes.json`.
  Future<TenantStockAdjustmentRecordPage> _load({
    required int pageSize,
    required String? cursor,
    required String? productId,
  }) async {
    if (!canReadInSession(session)) {
      throw const TenantStockException('stock_adjustments_forbidden');
    }
    final String? filteredProductId;
    try {
      filteredProductId = productId == null
          ? null
          : validateTenantDocumentId(productId, fieldName: 'productId');
    } on ArgumentError {
      throw const TenantStockException('invalid_product_filter');
    }
    final page = await readCollectionPage(
      TenantCollection.stockAdjustments,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
      descending: true,
      order: TenantCollectionOrder.occurredAt,
      equalityFilters: filteredProductId == null
          ? const <String, Object?>{}
          : <String, Object?>{'productId': filteredProductId},
    );
    final items = <TenantStockAdjustmentRecord>[];
    for (final snapshot in page.items) {
      final record = TenantStockAdjustmentRecord.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (record.tenantId != session.tenantId) {
        throw const TenantStockException('cross_tenant_adjustment');
      }
      // A filtered page that answers with another product's correction is a
      // broken boundary, not a row to skip past.
      if (filteredProductId != null && record.productId != filteredProductId) {
        throw const TenantStockException('foreign_product_adjustment');
      }
      items.add(record);
    }
    return TenantStockAdjustmentRecordPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      productId: filteredProductId,
    );
  }
}

TenantStockAdjustmentType? _parseAdjustmentType(String value) {
  for (final type in TenantStockAdjustmentType.values) {
    if (type.wireValue == value) return type;
  }
  return null;
}

String _requiredString(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw const TenantStockException('invalid_adjustment_document');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantStockException('invalid_adjustment_document');
    }
  }
  return value;
}

String? _optionalString(Map<String, Object?> data, String field) =>
    data[field] == null ? null : _requiredString(data, field);

String _requiredDocumentId(Map<String, Object?> data, String field) {
  final value = _requiredString(data, field);
  try {
    return validateTenantDocumentId(value, fieldName: field);
  } on ArgumentError {
    throw const TenantStockException('invalid_adjustment_document');
  }
}

int _requiredInt(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value.abs() > maximumStockQuantityMagnitude) {
    throw const TenantStockException('invalid_adjustment_document');
  }
  return value;
}

DateTime? _optionalInstant(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantStockException('invalid_adjustment_document');
}
