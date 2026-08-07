import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import '../checkout/checkout_draft.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';

/// The longest product or category name this surface writes.
///
/// Nothing on the server bounds it: `allow create` on `products` checks only
/// that `quantity is int`, and `categories` checks nothing at all. The bound is
/// therefore the client's, and it exists so a name cannot be pasted long enough
/// to make every catalog and receipt surface unreadable.
const int maximumCatalogNameLength = 120;

/// The longest stock-keeping unit this surface writes, bounded for the same
/// reason.
const int maximumCatalogSkuLength = 64;

/// The stock every product is created holding.
///
/// A create can name any integer the Firestore rule accepts, and this one
/// deliberately never does. Stock that appears without a `stock_movements`
/// entry has no recorded origin, and `adjustStock` already carries an
/// `opening_balance` type whose whole purpose is to put the first units in and
/// say where they came from. So a new product starts empty and its opening
/// stock is recorded, once, through the route that writes a ledger entry.
const int catalogOpeningQuantity = 0;

/// Raised when a catalog change is refused before anything is written.
final class TenantCatalogManagementException implements Exception {
  const TenantCatalogManagementException(this.code);

  final String code;

  @override
  String toString() => 'TenantCatalogManagementException($code)';
}

/// A validated instruction to create exactly one category document.
///
/// Only [TenantCatalogManagementRepository] can build one, so no caller can
/// name an arbitrary Firestore path. `createdAt` is deliberately not part of the
/// data: the writer adds a server timestamp, so a device clock never decides
/// when a business added a category.
final class TenantCategoryCreateIntent {
  const TenantCategoryCreateIntent._({
    required this.path,
    required this.tenantId,
    required this.categoryId,
    required this.name,
    required this.createdBy,
  });

  final String path;
  final String tenantId;
  final String categoryId;
  final String name;
  final String createdBy;

  /// Exactly the keys this client writes, and nothing else.
  ///
  /// `name` is all the strict read model reads. `createdBy` is provenance:
  /// nothing reads it, and [TenantCategory] ignores it, but it is the only
  /// record of who added the grouping every product is filed under.
  Map<String, Object?> documentData() => <String, Object?>{
    'name': name,
    'createdBy': createdBy,
  };
}

/// A validated instruction to create exactly one product document.
///
/// The key set is the one [TenantProduct] demands, in full. The rule on
/// `products` checks only `quantity is int`, so nothing on the server stops a
/// client writing a product the till cannot parse - and one unparseable product
/// makes the whole cached catalog a miss, which stops the business selling.
/// This intent is the only thing that prevents it.
final class TenantProductCreateIntent {
  const TenantProductCreateIntent._({
    required this.path,
    required this.tenantId,
    required this.productId,
    required this.name,
    required this.sku,
    required this.priceMinor,
    required this.categoryId,
    required this.categoryName,
    required this.createdBy,
  });

  final String path;
  final String tenantId;
  final String productId;
  final String name;
  final String sku;

  /// The price in exact integer minor units, as a sale line records it.
  final int priceMinor;

  /// The name of the category this product is filed under, carried for the
  /// confirmation only. It is never written: a product refers to its category
  /// by ID, so a renamed category does not have to be chased through products.
  final String categoryName;

  final String categoryId;
  final String createdBy;

  /// The stored major-unit price, derived from [priceMinor] rather than from
  /// what was typed, so the stored figure is exactly the one the till will
  /// convert back.
  double get price => priceMinor / 100;

  Map<String, Object?> documentData() => <String, Object?>{
    'name': name,
    'SKU': sku,
    'price': price,
    'quantity': catalogOpeningQuantity,
    'categoryId': categoryId,
    'createdBy': createdBy,
  };
}

/// A validated instruction to delete exactly one product document.
///
/// It carries what the product held at the moment it was read, because the
/// confirmation has to say what retiring does *not* do: it moves no stock,
/// writes no movement, and leaves every past sale line and ledger entry still
/// naming this ID.
final class TenantProductRetireIntent {
  const TenantProductRetireIntent._({
    required this.path,
    required this.tenantId,
    required this.productId,
    required this.name,
    required this.sku,
    required this.quantity,
  });

  final String path;
  final String tenantId;
  final String productId;
  final String name;
  final String sku;

  /// The stock the product was holding when it was read. Retiring does not
  /// change it, and no movement records its disappearance from the catalog.
  final int quantity;
}

typedef TenantCatalogRequestIdFactory = String Function();

/// Guarded intent boundary for changing one business's catalog.
///
/// This is deliberately separate from [TenantCatalogRepository]: every active
/// member reads the catalog - a till cannot sell without it - while only
/// management may add to it and only an owner or administrator may retire from
/// it. Three different populations, so they do not share a boundary.
final class TenantCatalogManagementRepository extends TenantReadRepository {
  TenantCatalogManagementRepository({
    required super.session,
    required super.reader,
  });

  /// Adding a product or a category is an operational act, which is exactly
  /// what the Firestore rules for `products` and `categories` allow: create is
  /// owner, administrator, or manager.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
    TenantRole.manager,
  ];

  /// Retiring is narrower, and so is `allow delete` on `products`. A manager
  /// who mis-stocks the catalog can be corrected by adding; a manager who
  /// retires a product removes the only thing that can sell it.
  static const List<TenantRole> retireRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  static bool canRetireInSession(TenantSession session) =>
      session.canAccess(allowedRoles: retireRoles);

  /// Builds the one create instruction [name] describes.
  ///
  /// [requestId] scopes the deterministic document ID. One confirmation keeps
  /// one request ID, so a retry addresses the same document - and a `set` onto
  /// an existing category is an update the rule evaluates separately, never a
  /// second category with the same name.
  TenantCategoryCreateIntent buildCategoryIntent({
    required String name,
    required String requestId,
  }) {
    _requireCreateRole();
    _requireRequestId(requestId);
    final safeName = _normalizedName(name, 'invalid_category_name');
    final categoryId = _deterministicCatalogId(
      prefix: 'ct',
      operation: 'createTenantCategory',
      tenantId: session.tenantId,
      createdBy: session.uid,
      requestId: requestId,
    );
    return TenantCategoryCreateIntent._(
      path: paths.category(categoryId),
      tenantId: session.tenantId,
      categoryId: categoryId,
      name: safeName,
      createdBy: session.uid,
    );
  }

  /// Builds the one create instruction the typed product describes.
  ///
  /// [categories] is the set of categories this surface actually offered, so a
  /// product can only be filed under a grouping that was read from this same
  /// business in this same session. [price] is taken as typed, because the
  /// exact spelling is what decides whether the amount is recordable.
  TenantProductCreateIntent buildProductIntent({
    required String name,
    required String sku,
    required String price,
    required String categoryId,
    required Iterable<TenantCategory> categories,
    required String requestId,
  }) {
    _requireCreateRole();
    _requireRequestId(requestId);
    final safeName = _normalizedName(name, 'invalid_product_name');
    final safeSku = _normalizedSku(sku);
    final priceMinor = _priceMinorUnits(price);
    TenantCategory? category;
    for (final candidate in categories) {
      if (candidate.id == categoryId) {
        category = candidate;
        break;
      }
    }
    if (category == null) {
      throw const TenantCatalogManagementException('unknown_category');
    }
    final productId = _deterministicCatalogId(
      prefix: 'pd',
      operation: 'createTenantProduct',
      tenantId: session.tenantId,
      createdBy: session.uid,
      requestId: requestId,
    );
    return TenantProductCreateIntent._(
      path: paths.product(productId),
      tenantId: session.tenantId,
      productId: productId,
      name: safeName,
      sku: safeSku,
      priceMinor: priceMinor,
      categoryId: category.id,
      categoryName: category.name,
      createdBy: session.uid,
    );
  }

  /// Builds the one delete instruction [product] describes.
  ///
  /// There is no request ID and no derived ID: the document already exists and
  /// its path is the product's own, so a retry after an unknown outcome deletes
  /// the same document a second time - which is exactly nothing.
  TenantProductRetireIntent buildRetireIntent(TenantProduct product) {
    if (!canRetireInSession(session)) {
      throw const TenantCatalogManagementException('retire_forbidden');
    }
    // A product decoded while another business was open can never be retired
    // from this one, even though both paths would be well-formed.
    if (product.tenantId != session.tenantId) {
      throw const TenantCatalogManagementException('retire_forbidden');
    }
    return TenantProductRetireIntent._(
      path: paths.product(product.id),
      tenantId: session.tenantId,
      productId: product.id,
      name: product.name,
      sku: product.sku,
      quantity: product.quantity,
    );
  }

  void _requireCreateRole() {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantCatalogManagementException('catalog_forbidden');
    }
  }

  static void _requireRequestId(String requestId) {
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw const TenantCatalogManagementException(
        'invalid_catalog_request_id',
      );
    }
  }
}

/// The outcome of one attempted catalog write.
enum TenantCatalogWriteKind {
  /// The server acknowledged the write.
  committed,

  /// The server refused the write; a canonical re-read decides what exists.
  rejected,

  /// The outcome is unknown; only a canonical re-read may settle it.
  ambiguous,

  /// No attempt was made because the device was offline.
  unavailable,
}

final class TenantCatalogWriteResult {
  const TenantCatalogWriteResult._(this.kind, [this.reasonCode]);

  const TenantCatalogWriteResult.committed()
    : this._(TenantCatalogWriteKind.committed);

  const TenantCatalogWriteResult.rejected(String reasonCode)
    : this._(TenantCatalogWriteKind.rejected, reasonCode);

  const TenantCatalogWriteResult.ambiguous(String reasonCode)
    : this._(TenantCatalogWriteKind.ambiguous, reasonCode);

  const TenantCatalogWriteResult.unavailable()
    : this._(TenantCatalogWriteKind.unavailable);

  final TenantCatalogWriteKind kind;
  final String? reasonCode;
}

/// The narrow write boundary used to change a catalog.
abstract interface class TenantCatalogWriter {
  Future<TenantCatalogWriteResult> createCategory(
    TenantCategoryCreateIntent intent,
  );

  Future<TenantCatalogWriteResult> createProduct(
    TenantProductCreateIntent intent,
  );

  Future<TenantCatalogWriteResult> retireProduct(
    TenantProductRetireIntent intent,
  );
}

typedef TenantCatalogOnlineCheck = Future<bool> Function();
typedef TenantCatalogDocumentCreator =
    Future<void> Function(String path, Map<String, Object?> data);
typedef TenantCatalogDocumentRemover = Future<void> Function(String path);

/// Firestore implementation of the catalog write boundary.
///
/// A create is a whole-document `set` rather than a merge, unlike checkout
/// configuration: this document is being brought into existence, the strict read
/// model requires every field it names, and merging onto a deterministic ID that
/// already exists would silently patch a product instead of refusing a replay.
/// `createdAt` is always a server timestamp.
final class FirebaseTenantCatalogWriter implements TenantCatalogWriter {
  FirebaseTenantCatalogWriter({
    FirebaseFirestore? firestore,
    required TenantCatalogOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(
         create: _firestoreCreator(firestore ?? FirebaseFirestore.instance),
         remove: _firestoreRemover(firestore ?? FirebaseFirestore.instance),
         isOnline: isOnline,
         writeTimeout: writeTimeout,
       );

  FirebaseTenantCatalogWriter.forTesting({
    required TenantCatalogDocumentCreator create,
    required TenantCatalogDocumentRemover remove,
    required TenantCatalogOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(
         create: create,
         remove: remove,
         isOnline: isOnline,
         writeTimeout: writeTimeout,
       );

  FirebaseTenantCatalogWriter._({
    required TenantCatalogDocumentCreator create,
    required TenantCatalogDocumentRemover remove,
    required TenantCatalogOnlineCheck isOnline,
    required Duration writeTimeout,
  }) : _create = create,
       _remove = remove,
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

  final TenantCatalogDocumentCreator _create;
  final TenantCatalogDocumentRemover _remove;
  final TenantCatalogOnlineCheck _isOnline;
  final Duration _writeTimeout;

  @override
  Future<TenantCatalogWriteResult> createCategory(
    TenantCategoryCreateIntent intent,
  ) {
    if (TenantPaths(intent.tenantId).category(intent.categoryId) !=
        intent.path) {
      throw const TenantCatalogManagementException(
        'catalog_path_escaped_tenant',
      );
    }
    return _write(
      () => _create(intent.path, <String, Object?>{
        ...intent.documentData(),
        'createdAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  @override
  Future<TenantCatalogWriteResult> createProduct(
    TenantProductCreateIntent intent,
  ) {
    _requireProductPath(intent.tenantId, intent.productId, intent.path);
    return _write(
      () => _create(intent.path, <String, Object?>{
        ...intent.documentData(),
        'createdAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  @override
  Future<TenantCatalogWriteResult> retireProduct(
    TenantProductRetireIntent intent,
  ) {
    _requireProductPath(intent.tenantId, intent.productId, intent.path);
    return _write(() => _remove(intent.path));
  }

  static void _requireProductPath(
    String tenantId,
    String productId,
    String path,
  ) {
    if (TenantPaths(tenantId).product(productId) != path) {
      throw const TenantCatalogManagementException(
        'catalog_path_escaped_tenant',
      );
    }
  }

  Future<TenantCatalogWriteResult> _write(
    Future<void> Function() attempt,
  ) async {
    if (!await _online()) {
      return const TenantCatalogWriteResult.unavailable();
    }
    try {
      await attempt().timeout(_writeTimeout);
      return const TenantCatalogWriteResult.committed();
    } on TimeoutException {
      return const TenantCatalogWriteResult.ambiguous('write_timeout');
    } on FirebaseException catch (error) {
      return _rejectedCodes.contains(error.code)
          ? TenantCatalogWriteResult.rejected(error.code)
          : TenantCatalogWriteResult.ambiguous(error.code);
    } catch (_) {
      return const TenantCatalogWriteResult.ambiguous('unknown_error');
    }
  }

  Future<bool> _online() async {
    try {
      return await _isOnline();
    } catch (_) {
      return false;
    }
  }

  static TenantCatalogDocumentCreator _firestoreCreator(
    FirebaseFirestore firestore,
  ) =>
      (path, data) => firestore.doc(path).set(data);

  static TenantCatalogDocumentRemover _firestoreRemover(
    FirebaseFirestore firestore,
  ) =>
      (path) => firestore.doc(path).delete();
}

/// A fresh request ID for one confirmed catalog create.
///
/// The same value must be reused across a retry of that create, and a new one
/// generated only for a genuinely different product or category.
String secureTenantCatalogRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'catalog-${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// Derives a catalog document ID from the identity the create is scoped by.
///
/// The ID is **not** a slug of the SKU, and that is a decision rather than a
/// convenience. It is permanent: `stock_movements` hangs below it, every past
/// sale line names it, and `daily_metrics` aggregates by it. A SKU is neither
/// unique - two products may legitimately carry one, which the till refuses to
/// resolve - nor correctable, because no client rule and no callable can change
/// a product's descriptive fields. Deriving the permanent identity from the one
/// field this app cannot fix would make a typo permanent in the ledger key too.
///
/// Scoping it by request ID mirrors the server's
/// `actorUid + operation + tenantId + requestId` idempotency, so a double
/// submit addresses one document instead of stocking the shelf twice.
String _deterministicCatalogId({
  required String prefix,
  required String operation,
  required String tenantId,
  required String createdBy,
  required String requestId,
}) {
  final digest = sha256.convert(
    utf8.encode(<String>[operation, tenantId, createdBy, requestId].join(' ')),
  );
  return '${prefix}_${digest.toString().substring(0, 40)}';
}

/// Collapses whitespace and bounds a name the strict read model must accept.
///
/// [TenantProduct] and [TenantCategory] both require a non-empty string that
/// equals its own trim and carries no control characters, so the value is
/// normalized into that shape here rather than being refused for a stray space.
String _normalizedName(String value, String code) {
  final name = value.trim().replaceAll(_whitespaceRun, ' ');
  if (name.isEmpty || name.length > maximumCatalogNameLength) {
    throw TenantCatalogManagementException(code);
  }
  for (final codeUnit in name.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw TenantCatalogManagementException(code);
    }
  }
  return name;
}

/// Bounds a stock-keeping unit and refuses whitespace anywhere inside it.
///
/// A SKU is what the till matches a scan against, exactly and case-folded. A
/// scanner cannot emit a space, so a code containing one could be typed but
/// never scanned - which is the one job the field has.
String _normalizedSku(String value) {
  final sku = value.trim();
  if (sku.isEmpty || sku.length > maximumCatalogSkuLength) {
    throw const TenantCatalogManagementException('invalid_sku');
  }
  for (final codeUnit in sku.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      throw const TenantCatalogManagementException('invalid_sku');
    }
  }
  if (_whitespaceRun.hasMatch(sku)) {
    throw const TenantCatalogManagementException('invalid_sku');
  }
  return sku;
}

/// Converts a typed price into the exact minor units a sale line records.
///
/// The spelling is bounded first: a plain decimal amount with at most two
/// places, because two places is all `unitPriceMinor` can hold. `1e3`, `0x10`,
/// a negative, and `1.005` are all refused as unusable rather than rounded.
///
/// The result is then proved by round-tripping through
/// [checkoutMinorUnitsFromMajor] - the same function the till and the cart use.
/// That is what makes it impossible for this surface to accept a price the till
/// would later refuse as `price_not_representable` with the customer waiting.
int _priceMinorUnits(String value) {
  final text = value.trim();
  if (!_pricePattern.hasMatch(text)) {
    throw const TenantCatalogManagementException('invalid_price');
  }
  final parts = text.split('.');
  final minorUnits =
      int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  if (checkoutMinorUnitsFromMajor(minorUnits / 100) != minorUnits) {
    throw const TenantCatalogManagementException('price_not_representable');
  }
  return minorUnits;
}

final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _pricePattern = RegExp(r'^\d{1,12}(\.\d{1,2})?$');
final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
