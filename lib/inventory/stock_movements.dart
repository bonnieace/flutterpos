import 'package:cloud_firestore/cloud_firestore.dart';

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_types.dart';
import 'stock_adjustment.dart';

/// Raised when a product or its stock ledger cannot be trusted for display.
final class TenantStockException implements Exception {
  const TenantStockException(this.code);

  final String code;

  @override
  String toString() => 'TenantStockException($code)';
}

/// What appended one entry to a product's stock ledger.
///
/// A server deploy may introduce a source this client does not model yet.
/// Failing the whole ledger closed on an unknown value would take a working
/// screen down for a change that is not evidence of anything wrong, so an
/// unmodelled source is carried verbatim as [other] and displayed as itself.
enum TenantStockMovementSource {
  /// A confirmed sale, recorded by nightly reconciliation. Always negative.
  sale('sale'),

  /// A verified return, recorded by `verifyReturnAndRestoreStock`.
  verifiedReturn('verified_return'),

  /// A manual `adjustStock` correction.
  manualAdjustment('manual_adjustment'),

  /// Any source this client does not model.
  other('');

  const TenantStockMovementSource(this.wireValue);

  final String wireValue;

  static TenantStockMovementSource parse(String value) {
    for (final source in values) {
      if (source != other && source.wireValue == value) return source;
    }
    return other;
  }
}

/// Strict read model for
/// `tenants/{tenantId}/products/{productId}/stock_movements/{movementId}`.
///
/// The ledger is written only by server code, so this decodes what it finds
/// rather than re-deriving it - but it still refuses a document that
/// contradicts its own path or its own arithmetic, because a screen used to
/// explain a stock figure must not present evidence that disagrees with itself.
final class TenantStockMovement {
  factory TenantStockMovement.fromDocument({
    required String path,
    required Map<String, Object?> data,
  }) {
    final segments = path.split('/');
    if (segments.length != 6 ||
        segments[0] != 'tenants' ||
        segments[2] != TenantCollection.products.segment ||
        segments[4] != TenantProductSubcollection.stockMovements.segment) {
      throw const TenantStockException('invalid_movement_path');
    }
    final String tenantId;
    final String productId;
    final String movementId;
    try {
      tenantId = validateTenantId(segments[1]);
      productId = validateTenantDocumentId(segments[3], fieldName: 'productId');
      movementId = validateTenantDocumentId(
        segments[5],
        fieldName: 'movementId',
      );
    } on ArgumentError {
      throw const TenantStockException('invalid_movement_path');
    }
    // Every writer repeats the identity encoded in the path.
    if (data['movementId'] != movementId ||
        data['tenantId'] != tenantId ||
        data['productId'] != productId) {
      throw const TenantStockException('movement_identity_mismatch');
    }

    final quantityDelta = _requiredInt(data, 'quantityDelta');
    if (quantityDelta == 0) {
      throw const TenantStockException('invalid_movement_delta');
    }
    // Only the writers that read the product inside their transaction record a
    // before and after. They are present or absent as a whole, and when present
    // they must add up.
    final previousQuantity = _optionalInt(data, 'previousQuantity');
    final quantityAfter = _optionalInt(data, 'quantityAfter');
    if ((previousQuantity == null) != (quantityAfter == null)) {
      throw const TenantStockException('incomplete_movement_quantities');
    }
    if (previousQuantity != null &&
        quantityAfter != previousQuantity + quantityDelta) {
      throw const TenantStockException('inconsistent_movement_quantities');
    }

    return TenantStockMovement._(
      id: movementId,
      tenantId: tenantId,
      productId: productId,
      source: TenantStockMovementSource.parse(
        _requiredString(data, 'sourceType'),
      ),
      sourceType: _requiredString(data, 'sourceType'),
      sourceId: _optionalString(data, 'sourceId'),
      adjustmentType: _optionalString(data, 'adjustmentType'),
      reason: _optionalString(data, 'reason'),
      actorUid: _optionalString(data, 'actorUid'),
      quantityDelta: quantityDelta,
      previousQuantity: previousQuantity,
      quantityAfter: quantityAfter,
      occurredAt: _optionalInstant(data, 'occurredAt'),
      recordedAt: _optionalInstant(data, 'recordedAt'),
    );
  }

  const TenantStockMovement._({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.source,
    required this.sourceType,
    required this.sourceId,
    required this.adjustmentType,
    required this.reason,
    required this.actorUid,
    required this.quantityDelta,
    required this.previousQuantity,
    required this.quantityAfter,
    required this.occurredAt,
    required this.recordedAt,
  });

  final String id;
  final String tenantId;
  final String productId;
  final TenantStockMovementSource source;

  /// The raw value, kept so an unmodelled source can be shown as itself.
  final String sourceType;

  /// The sale or return this movement came from, when it had one.
  final String? sourceId;

  /// The typed `adjustStock` reason category, present on manual adjustments.
  final String? adjustmentType;
  final String? reason;
  final String? actorUid;
  final int quantityDelta;

  /// Present only for a movement whose writer read the product first.
  final int? previousQuantity;
  final int? quantityAfter;

  final DateTime? occurredAt;
  final DateTime? recordedAt;

  bool get increasesStock => quantityDelta > 0;
}

/// One bounded page of a product's stock ledger.
final class TenantStockMovementPage {
  TenantStockMovementPage({
    required List<TenantStockMovement> items,
    required this.nextCursor,
    required this.hasMore,
  }) : items = List<TenantStockMovement>.unmodifiable(items);

  final List<TenantStockMovement> items;
  final String? nextCursor;
  final bool hasMore;
}

/// The recorded state of one product and one page of its stock ledger.
final class TenantProductStockView {
  const TenantProductStockView({
    required this.product,
    required this.movements,
  });

  /// Re-read from the canonical document on every page, so the quantity shown
  /// is always the one the server most recently recorded rather than a figure
  /// carried across a screen or derived from the ledger below it.
  final TenantProduct product;

  final TenantStockMovementPage movements;
}

/// Guarded read boundary over one product and its server-written stock ledger.
///
/// Every path is derived from the session's [TenantPaths] and the exact-child,
/// uniqueness, and ordering proofs of [TenantReadRepository] still apply.
final class TenantProductStockRepository extends TenantReadRepository {
  TenantProductStockRepository({
    required super.session,
    required TenantDataReader reader,
  }) : _collectionReader = reader,
       super(reader: reader);

  /// The ledger names damage, waste, and corrections beside every sale, which
  /// is management information in exactly the way the daily summary is. It is
  /// the same set of roles `adjustStock` itself enforces, so the surface that
  /// explains a stock figure and the surface that changes it agree.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  final TenantCollectionReader _collectionReader;

  /// Reads the product and its first ledger page for one guarded route.
  Future<TenantProductStockView> loadStock({
    required String productId,
    int pageSize = 20,
    String? cursor,
  }) async {
    _requireAuthorizedSession();
    final product = await readProduct(productId);
    return TenantProductStockView(
      product: product,
      movements: await loadMovements(
        productId: product.id,
        pageSize: pageSize,
        cursor: cursor,
      ),
    );
  }

  /// Reads one product by its exact canonical path.
  Future<TenantProduct> readProduct(String productId) async {
    _requireAuthorizedSession();
    final data = await readDocument(TenantCollection.products, productId);
    if (data == null) {
      throw const TenantStockException('product_unavailable');
    }
    final product = TenantProduct.fromDocument(
      path: paths.product(productId),
      data: data,
    );
    if (product.tenantId != session.tenantId) {
      throw const TenantStockException('cross_tenant_product');
    }
    return product;
  }

  /// Pages one product's stock ledger.
  ///
  /// The page is ordered by ascending document ID and is deliberately **not**
  /// presented as chronological: a movement ID is a digest for an adjustment
  /// and `sale_{saleId}` for a sale, so document order carries no time
  /// information at all. Each entry states its own recorded instants instead.
  /// Ascending order also keeps the page servable by Firestore's automatic
  /// index, since a descending key scan would need a filter and a composite
  /// index while buying nothing.
  Future<TenantStockMovementPage> loadMovements({
    required String productId,
    int pageSize = 20,
    String? cursor,
  }) async {
    _requireAuthorizedSession();
    final page = await readProductSubcollectionPage(
      TenantProductSubcollection.stockMovements,
      productId: productId,
      collectionReader: _collectionReader,
      pageSize: pageSize,
      cursor: cursor,
    );
    final items = <TenantStockMovement>[];
    for (final snapshot in page.items) {
      final movement = TenantStockMovement.fromDocument(
        path: snapshot.path,
        data: snapshot.data,
      );
      if (movement.tenantId != session.tenantId) {
        throw const TenantStockException('cross_tenant_movement');
      }
      if (movement.productId != productId) {
        throw const TenantStockException('foreign_product_movement');
      }
      items.add(movement);
    }
    return TenantStockMovementPage(
      items: items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  /// A cashier is refused before any query is issued, so a role that may not
  /// see the ledger never reaches the server at all.
  void _requireAuthorizedSession() {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantStockException('stock_ledger_forbidden');
    }
  }
}

String _requiredString(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw const TenantStockException('invalid_movement_document');
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantStockException('invalid_movement_document');
    }
  }
  return value;
}

String? _optionalString(Map<String, Object?> data, String field) =>
    data[field] == null ? null : _requiredString(data, field);

int _requiredInt(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int || value.abs() > maximumStockQuantityMagnitude) {
    throw const TenantStockException('invalid_movement_document');
  }
  return value;
}

int? _optionalInt(Map<String, Object?> data, String field) =>
    data[field] == null ? null : _requiredInt(data, field);

DateTime? _optionalInstant(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  throw const TenantStockException('invalid_movement_document');
}
