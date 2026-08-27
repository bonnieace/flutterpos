import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';

import '../checkout/checkout_draft.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_id.dart';
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

/// Normalizes product search text identically to the callable and migration.
String tenantProductSearchTerm(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The deterministic sort value stored beside every product.
String tenantProductSearchName(String name) => tenantProductSearchTerm(name);

/// Every searchable word/SKU prefix stored on one product.
///
/// Prefixes begin at two characters because the UI never searches sooner and
/// a one-character array value creates a very broad, expensive index entry.
List<String> tenantProductSearchPrefixes({
  required String name,
  required String sku,
}) {
  final prefixes = <String>{};
  final words = <String>{
    ...tenantProductSearchTerm(name).split(' '),
    tenantProductSearchTerm(sku),
  }..removeWhere((word) => word.length < 2);
  for (final word in words) {
    for (var length = 2; length <= word.length; length++) {
      prefixes.add(word.substring(0, length));
    }
  }
  final result = prefixes.toList()..sort();
  return List<String>.unmodifiable(result);
}

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

/// A validated rename that preserves the category document identity.
final class TenantCategoryRenameIntent {
  const TenantCategoryRenameIntent._({
    required this.path,
    required this.tenantId,
    required this.categoryId,
    required this.previousName,
    required this.name,
    required this.updatedBy,
  });

  final String path;
  final String tenantId;
  final String categoryId;
  final String previousName;
  final String name;
  final String updatedBy;

  Map<String, Object?> documentData() => <String, Object?>{
    'name': name,
    'updatedBy': updatedBy,
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
    required this.costMinor,
    required this.categoryId,
    required this.categoryName,
    required this.createdBy,
    this.imageUrl,
  });

  final String path;
  final String tenantId;
  final String productId;
  final String name;
  final String sku;

  /// The price in exact integer minor units, as a sale line records it.
  final int priceMinor;

  /// What one unit cost the business, in exact integer minor units, or null
  /// when it was left blank.
  ///
  /// Optional deliberately. A business that does not track cost must still be
  /// able to add a product, and a cost invented here — zero, or the price —
  /// would be a fabricated margin reported as fact. Blank means "not recorded",
  /// which is what the daily summary already counts and says.
  final int? costMinor;

  /// The name of the category this product is filed under, carried for the
  /// confirmation only. It is never written: a product refers to its category
  /// by ID, so a renamed category does not have to be chased through products.
  final String categoryName;

  final String categoryId;
  final String createdBy;
  final Uri? imageUrl;

  /// The stored major-unit price, derived from [priceMinor] rather than from
  /// what was typed, so the stored figure is exactly the one the till will
  /// convert back.
  double get price => priceMinor / 100;

  /// The stored major-unit cost, derived from [costMinor] for the same reason
  /// [price] is derived from [priceMinor].
  double? get cost => costMinor == null ? null : costMinor! / 100;

  Map<String, Object?> documentData() => <String, Object?>{
    'name': name,
    'SKU': sku,
    'price': price,
    // Omitted rather than written as null when it was left blank, so "never
    // recorded" and "recorded as nothing" stay distinguishable in the document.
    if (cost != null) 'cost': cost,
    'quantity': catalogOpeningQuantity,
    'categoryId': categoryId,
    'searchName': tenantProductSearchName(name),
    'searchPrefixes': tenantProductSearchPrefixes(name: name, sku: sku),
    if (imageUrl != null) 'image': imageUrl.toString(),
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

/// A descriptive field `updateProduct` may correct, with the exact key it reads.
///
/// `quantity` is deliberately absent and can never be added here: it belongs to
/// `adjustStock`, which writes a `stock_movements` entry, and the callable
/// refuses a payload that so much as mentions it.
enum TenantProductField {
  name('name', 'Name'),
  sku('sku', 'Code'),
  price('price', 'Unit price'),
  cost('cost', 'Unit cost'),
  categoryId('categoryId', 'Category'),
  image('image', 'Image');

  const TenantProductField(this.wireKey, this.label);

  /// The payload key, which is also what the response names in `changedFields`.
  final String wireKey;

  /// What the confirmation calls this field.
  final String label;

  /// Whether this field is money, and therefore behind [
  /// TenantCatalogManagementRepository.costRoles] rather than the operational
  /// three. The server's `MONETARY_PRODUCT_FIELDS`, field for field.
  bool get isMonetary => this == price || this == cost;

  static TenantProductField? fromWireKey(String value) {
    for (final field in values) {
      if (field.wireKey == value) return field;
    }
    return null;
  }
}

/// One field's correction, exactly as the confirmation states it.
///
/// Both sides are display strings rather than typed values on purpose: this
/// exists to be read by the person about to change a price, and a stored figure
/// the till cannot convert has no typed form to carry.
final class TenantProductFieldChange {
  const TenantProductFieldChange._({
    required this.field,
    required this.previous,
    required this.next,
  });

  final TenantProductField field;
  final String previous;
  final String next;

  @override
  String toString() => '${field.label}: was $previous, now $next';
}

/// A validated instruction to correct exactly one product, and nothing else.
///
/// Only [TenantCatalogManagementRepository] can build one, so no caller can name
/// an arbitrary product, business, or field. It carries **only the fields that
/// actually move**: the callable reads its permission tier from the fields a
/// payload names rather than from the resulting diff, so naming an unchanged
/// price would refuse a manager's name correction for a value nobody touched.
final class TenantProductUpdateIntent {
  const TenantProductUpdateIntent._({
    required this.tenantId,
    required this.productId,
    required this.requestId,
    required this.changes,
    required this.name,
    required this.sku,
    required this.priceMinor,
    required this.costMinor,
    required this.clearsCost,
    required this.categoryId,
    required this.categoryName,
    required this.imageUrl,
    required this.clearsImage,
  });

  final String tenantId;
  final String productId;

  /// The idempotency key. One correction keeps one request ID across a retry,
  /// so a genuine retry answers off the server's own record instead of reaching
  /// the refusal it keeps for a request that changes nothing.
  final String requestId;

  /// Every field that moves, with what it held and what it will hold.
  final List<TenantProductFieldChange> changes;

  final String? name;
  final String? sku;

  /// The corrected price in exact integer minor units, or null when the price
  /// is not being corrected.
  final int? priceMinor;

  /// The corrected cost in exact integer minor units, or null when the cost is
  /// either not being corrected or being cleared - [clearsCost] tells the two
  /// apart, because it is the one field where sending nothing and sending null
  /// mean different things.
  final int? costMinor;

  /// Whether this correction removes a recorded cost outright.
  final bool clearsCost;

  final String? categoryId;

  /// The name of the category being moved to, carried for the confirmation
  /// only. Null when the category is not being changed.
  final String? categoryName;
  final Uri? imageUrl;
  final bool clearsImage;

  /// The fields this payload names, which is what the server authorizes on.
  List<TenantProductField> get fields =>
      changes.map((change) => change.field).toList();

  /// Whether this correction changes money, and therefore needs an owner or an
  /// administrator rather than the operational three.
  bool get changesMoney => fields.any((field) => field.isMonetary);

  /// Exactly the keys this correction sends, and nothing else.
  ///
  /// A cleared cost is an explicit `null`, which is the only place in this app
  /// where null on the wire means "remove this" rather than "leave it alone".
  Map<String, Object?> payload() => <String, Object?>{
    'tenantId': tenantId,
    'productId': productId,
    'requestId': requestId,
    if (name != null) 'name': name,
    if (sku != null) 'sku': sku,
    // Sent as a major-unit amount derived from the minor units, never as what
    // was typed, so the figure the server converts back is the one confirmed.
    if (priceMinor != null) 'price': priceMinor! / 100,
    if (clearsCost) 'cost': null,
    if (costMinor != null) 'cost': costMinor! / 100,
    if (categoryId != null) 'categoryId': categoryId,
    if (imageUrl != null) 'image': imageUrl.toString(),
    if (clearsImage) 'image': null,
  };
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

  /// Recording what the business *paid* is narrower than recording what it
  /// charges, and deliberately matches the tier `updateProduct` puts a price
  /// behind.
  ///
  /// A buying price is the business's margin written down. Every active member
  /// can already read a product document — the till cannot price a sale
  /// otherwise — so this is a surface boundary, not a secrecy guarantee, and it
  /// is documented as one. What it does buy is that no manager is *shown* the
  /// margin, and that a client which sends a cost without the role is refused
  /// rather than quietly ignored.
  static const List<TenantRole> costRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  static bool canRecordCostInSession(TenantSession session) =>
      session.canAccess(allowedRoles: costRoles);

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
    final safeName = tenantCatalogNormalizedName(name, 'invalid_category_name');
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

  TenantCategoryRenameIntent buildCategoryRenameIntent({
    required TenantCategory category,
    required String name,
  }) {
    _requireCreateRole();
    final safeName = tenantCatalogNormalizedName(name, 'invalid_category_name');
    if (safeName == category.name) {
      throw const TenantCatalogManagementException('category_unchanged');
    }
    return TenantCategoryRenameIntent._(
      path: paths.category(category.id),
      tenantId: session.tenantId,
      categoryId: category.id,
      previousName: category.name,
      name: safeName,
      updatedBy: session.uid,
    );
  }

  /// Builds the one create instruction the typed product describes.
  ///
  /// [categories] is the set of categories this surface actually offered, so a
  /// product can only be filed under a grouping that was read from this same
  /// business in this same session. [price] is taken as typed, because the
  /// exact spelling is what decides whether the amount is recordable.
  /// [cost] is what the business paid for one unit, and it is the one field
  /// here that may be left blank: a business that does not track cost still has
  /// to be able to add a product.
  TenantProductCreateIntent buildProductIntent({
    required String name,
    required String sku,
    required String price,
    required String categoryId,
    required Iterable<TenantCategory> categories,
    required String requestId,
    String cost = '',
    Uri? imageUrl,
  }) {
    _requireCreateRole();
    _requireRequestId(requestId);
    final safeName = tenantCatalogNormalizedName(name, 'invalid_product_name');
    final safeSku = tenantCatalogNormalizedSku(sku);
    final priceMinor = tenantCatalogPriceMinorUnits(price);
    final int? costMinor;
    if (cost.trim().isEmpty) {
      costMinor = null;
    } else {
      // Refused rather than dropped, for the same reason `updateProduct`
      // refuses an unknown key: a caller must not be able to believe it
      // recorded a cost that was silently discarded.
      if (!canRecordCostInSession(session)) {
        throw const TenantCatalogManagementException('cost_forbidden');
      }
      costMinor = tenantCatalogPriceMinorUnits(
        cost,
        invalidCode: 'invalid_cost',
        unrepresentableCode: 'cost_not_representable',
      );
    }
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
      costMinor: costMinor,
      categoryId: category.id,
      categoryName: category.name,
      createdBy: session.uid,
      imageUrl: _validatedProductImage(imageUrl),
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

  /// Builds the one correction the typed edit form describes.
  ///
  /// [product] is a record this surface already read and decoded from this same
  /// business, so the correction can only ever address a product the operator
  /// was actually shown. [price] and [cost] are nullable because the form does
  /// not offer them to a manager: null means "this form never asked", which is
  /// different from an empty string, and different again from [clearCost].
  ///
  /// **Only fields that actually move are carried.** The callable reads its
  /// permission tier from the fields a payload names, so resending an unchanged
  /// price would refuse a manager's name correction over a value nobody touched
  /// - and a request that changes nothing at all is refused by the server as a
  /// caller defect, so it is refused here instead of costing a round trip and an
  /// idempotency record.
  TenantProductUpdateIntent buildUpdateIntent({
    required TenantProduct product,
    required String name,
    required String sku,
    required String categoryId,
    required Iterable<TenantCategory> categories,
    required String requestId,
    String? price,
    String? cost,
    bool clearCost = false,
    Uri? imageUrl,
    bool clearImage = false,
  }) {
    // The server's PRODUCT_UPDATE_ROLES are the same operational three that may
    // create, which is why the route guard's own list is reused here.
    _requireCreateRole();
    _requireRequestId(requestId);
    // A product decoded while another business was open can never be corrected
    // from this one, even though both paths would be well-formed.
    if (product.tenantId != session.tenantId) {
      throw const TenantCatalogManagementException('edit_forbidden');
    }
    final safeName = tenantCatalogNormalizedName(name, 'invalid_product_name');
    final safeSku = tenantCatalogNormalizedSku(sku);
    TenantCategory? category;
    for (final candidate in categories) {
      if (candidate.id == categoryId) {
        category = candidate;
        break;
      }
    }
    // A product may legitimately sit in a category this page did not read - the
    // categories are one bounded page and a business may hold more. Leaving it
    // where it is therefore needs no proof, while moving it to a grouping this
    // surface never offered is refused exactly as it is on the create form.
    if (category == null && categoryId != product.categoryId) {
      throw const TenantCatalogManagementException('unknown_category');
    }

    final changes = <TenantProductFieldChange>[];
    final String? nextName = safeName == product.name ? null : safeName;
    if (nextName != null) {
      changes.add(
        TenantProductFieldChange._(
          field: TenantProductField.name,
          previous: product.name,
          next: nextName,
        ),
      );
    }
    final String? nextSku = safeSku == product.sku ? null : safeSku;
    if (nextSku != null) {
      changes.add(
        TenantProductFieldChange._(
          field: TenantProductField.sku,
          previous: product.sku,
          next: nextSku,
        ),
      );
    }

    int? nextPriceMinor;
    if (price != null) {
      final priceMinor = tenantCatalogPriceMinorUnits(price);
      // A stored price the till cannot convert is a price that differs from
      // every representable figure, so retyping it is a real correction rather
      // than a no-op the server would refuse.
      final storedPriceMinor = checkoutMinorUnitsFromMajor(product.price);
      if (storedPriceMinor != priceMinor) {
        _requireMonetaryRole(TenantProductField.price);
        nextPriceMinor = priceMinor;
        changes.add(
          TenantProductFieldChange._(
            field: TenantProductField.price,
            previous: storedPriceMinor == null
                ? '${product.price} (unusable)'
                : tenantCatalogMajorUnits(storedPriceMinor),
            next: tenantCatalogMajorUnits(priceMinor),
          ),
        );
      }
    }

    int? nextCostMinor;
    var clearsCost = false;
    final storedCost = product.cost;
    final storedCostMinor = storedCost == null
        ? null
        : checkoutMinorUnitsFromMajor(storedCost);
    final String previousCost = storedCost == null
        ? 'not recorded'
        : storedCostMinor == null
        ? '$storedCost (unusable)'
        : tenantCatalogMajorUnits(storedCostMinor);
    if (clearCost) {
      _requireMonetaryRole(TenantProductField.cost);
      if (storedCost != null) {
        clearsCost = true;
        changes.add(
          TenantProductFieldChange._(
            field: TenantProductField.cost,
            previous: previousCost,
            next: 'not recorded',
          ),
        );
      }
    } else if (cost != null && cost.trim().isNotEmpty) {
      final costMinor = tenantCatalogPriceMinorUnits(
        cost,
        invalidCode: 'invalid_cost',
        unrepresentableCode: 'cost_not_representable',
      );
      if (storedCostMinor != costMinor) {
        _requireMonetaryRole(TenantProductField.cost);
        nextCostMinor = costMinor;
        changes.add(
          TenantProductFieldChange._(
            field: TenantProductField.cost,
            previous: previousCost,
            next: tenantCatalogMajorUnits(costMinor),
          ),
        );
      }
    }

    String? nextCategoryId;
    String? nextCategoryName;
    if (category != null && category.id != product.categoryId) {
      nextCategoryId = category.id;
      nextCategoryName = category.name;
      changes.add(
        TenantProductFieldChange._(
          field: TenantProductField.categoryId,
          // The grouping being left may be off this page, and its document ID
          // is not a name for it - see [tenantCategoryPhrase], which is the one
          // place this app decides what to call a category it cannot name.
          previous: tenantCategoryPhrase(
            product.categoryId,
            names: tenantCategoryNames(categories),
          ),
          next: nextCategoryName,
        ),
      );
    }

    Uri? nextImageUrl;
    var clearsImage = false;
    if (clearImage) {
      if (product.imageUrl != null) {
        clearsImage = true;
        changes.add(
          TenantProductFieldChange._(
            field: TenantProductField.image,
            previous: 'product image',
            next: 'no image',
          ),
        );
      }
    } else if (imageUrl != null) {
      final validated = _validatedProductImage(imageUrl)!;
      if (validated != product.imageUrl) {
        nextImageUrl = validated;
        changes.add(
          TenantProductFieldChange._(
            field: TenantProductField.image,
            previous: product.imageUrl == null ? 'no image' : 'product image',
            next: 'replacement image',
          ),
        );
      }
    }

    if (changes.isEmpty) {
      throw const TenantCatalogManagementException('product_unchanged');
    }
    return TenantProductUpdateIntent._(
      tenantId: session.tenantId,
      productId: product.id,
      requestId: requestId,
      changes: List<TenantProductFieldChange>.unmodifiable(changes),
      name: nextName,
      sku: nextSku,
      priceMinor: nextPriceMinor,
      costMinor: nextCostMinor,
      clearsCost: clearsCost,
      categoryId: nextCategoryId,
      categoryName: nextCategoryName,
      imageUrl: nextImageUrl,
      clearsImage: clearsImage,
    );
  }

  void _requireCreateRole() {
    if (!session.canAccess(allowedRoles: allowedRoles)) {
      throw const TenantCatalogManagementException('catalog_forbidden');
    }
  }

  /// Refuses a money change by a principal who may correct everything else.
  ///
  /// Refused rather than dropped, for the same reason the create form refuses a
  /// cost it may not record: a caller must never be able to believe it corrected
  /// a price that was silently discarded. The form does not offer either field
  /// to a manager, so this is the boundary behind the surface rather than the
  /// message anybody is expected to see.
  void _requireMonetaryRole(TenantProductField field) {
    if (canRecordCostInSession(session)) return;
    throw TenantCatalogManagementException(
      field == TenantProductField.price ? 'price_forbidden' : 'cost_forbidden',
    );
  }

  static void _requireRequestId(String requestId) =>
      requireTenantCatalogRequestId(requestId);
}

Uri? _validatedProductImage(Uri? imageUrl) {
  if (imageUrl == null) return null;
  if (imageUrl.scheme != 'https' || imageUrl.host.isEmpty) {
    throw const TenantCatalogManagementException('invalid_product_image');
  }
  return imageUrl;
}

/// Refuses an idempotency key the server's `requireRequestId` would refuse.
///
/// Shared with the bulk catalog paths rather than re-spelled there: a request ID
/// this client accepts and the server does not is a chunk of work that fails
/// after the operator has confirmed it, and two copies of one pattern is how the
/// two drift apart.
void requireTenantCatalogRequestId(String requestId) {
  if (!_requestIdPattern.hasMatch(requestId)) {
    throw const TenantCatalogManagementException('invalid_catalog_request_id');
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

  Future<TenantCatalogWriteResult> renameCategory(
    TenantCategoryRenameIntent intent,
  );

  Future<TenantCatalogWriteResult> retireProduct(
    TenantProductRetireIntent intent,
  );
}

typedef TenantCatalogOnlineCheck = Future<bool> Function();
typedef TenantCatalogDocumentCreator =
    Future<void> Function(String path, Map<String, Object?> data);
typedef TenantCatalogDocumentUpdater =
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
         update: _firestoreUpdater(firestore ?? FirebaseFirestore.instance),
         remove: _firestoreRemover(firestore ?? FirebaseFirestore.instance),
         isOnline: isOnline,
         writeTimeout: writeTimeout,
       );

  FirebaseTenantCatalogWriter.forTesting({
    required TenantCatalogDocumentCreator create,
    TenantCatalogDocumentUpdater? update,
    required TenantCatalogDocumentRemover remove,
    required TenantCatalogOnlineCheck isOnline,
    Duration writeTimeout = const Duration(seconds: 20),
  }) : this._(
         create: create,
         update: update ?? _unsupportedUpdate,
         remove: remove,
         isOnline: isOnline,
         writeTimeout: writeTimeout,
       );

  FirebaseTenantCatalogWriter._({
    required TenantCatalogDocumentCreator create,
    required TenantCatalogDocumentUpdater update,
    required TenantCatalogDocumentRemover remove,
    required TenantCatalogOnlineCheck isOnline,
    required Duration writeTimeout,
  }) : _create = create,
       _update = update,
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
  final TenantCatalogDocumentUpdater _update;
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
  Future<TenantCatalogWriteResult> renameCategory(
    TenantCategoryRenameIntent intent,
  ) {
    if (TenantPaths(intent.tenantId).category(intent.categoryId) !=
        intent.path) {
      throw const TenantCatalogManagementException(
        'catalog_path_escaped_tenant',
      );
    }
    return _write(
      () => _update(intent.path, <String, Object?>{
        ...intent.documentData(),
        'updatedAt': FieldValue.serverTimestamp(),
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

  static TenantCatalogDocumentUpdater _firestoreUpdater(
    FirebaseFirestore firestore,
  ) =>
      (path, data) => firestore.doc(path).update(data);

  static Future<void> _unsupportedUpdate(
    String path,
    Map<String, Object?> data,
  ) => Future<void>.error(
    UnsupportedError('Category rename is not configured.'),
  );

  static TenantCatalogDocumentRemover _firestoreRemover(
    FirebaseFirestore firestore,
  ) =>
      (path) => firestore.doc(path).delete();
}

/// Narrow callable boundary for `updateProduct`.
///
/// Correcting a product is the one catalog change that is **not** a Firestore
/// write, and it cannot become one: `allow update` on `products` permits a
/// strictly decreasing `quantity` with `hasOnly(['quantity', 'updatedAt'])` -
/// the checkout decrement - and widening it was considered and rejected, because
/// a rule-based edit records no actor, no previous value, and no reason. The
/// callable writes through the Admin SDK, so `firestore.rules` is untouched.
abstract interface class UpdateProductCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `updateProduct`.
final class FirebaseUpdateProductCallable implements UpdateProductCallable {
  FirebaseUpdateProductCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('updateProduct')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Why a correction did not change the product.
///
/// Each case is a distinct, actionable outcome. The codes and message fragments
/// are the ones `functions/src/operations/productUpdate.ts` and `products.ts`
/// raise; an unrecognised refusal degrades to [refused], which reports honestly
/// that nothing changed.
enum TenantProductUpdateFailure {
  /// The session may not correct products, or its membership ended.
  forbidden,

  /// A price needs an owner or an administrator. The form does not offer the
  /// field to anybody else, so this is reachable only if the role changed
  /// between the form opening and the correction being sent.
  priceForbidden,

  /// What a product costs needs an owner or an administrator, for the same
  /// reason and reachable the same way.
  costForbidden,

  /// The product no longer exists in this business.
  productMissing,

  /// The category named does not exist in this business.
  categoryMissing,

  /// The product already holds every value in the request. Refused locally
  /// first, so this means the product changed underneath the form.
  unchanged,

  /// The stored document holds a value no device can read, and the correction
  /// has to name every broken field in one request.
  productUnreadable,

  /// The stored document is broken in a way no callable can repair - a
  /// non-integer quantity, or an image that is not an HTTPS URL.
  needsOperator,

  /// This request ID already settled a different correction.
  duplicateRequest,

  /// The payload was refused as malformed, which means this client and the
  /// server disagree about what is acceptable.
  invalidRequest,

  /// The call was refused for a reason this client does not model.
  refused,

  /// The outcome is unknown; only a canonical re-read may settle it.
  ambiguous,
}

/// Raised when a correction did not complete.
final class TenantProductUpdateException implements Exception {
  const TenantProductUpdateException(this.failure);

  final TenantProductUpdateFailure failure;

  /// Whether the attempt may have corrected the product despite the failure.
  ///
  /// Only an unknown outcome may have landed. Every other case is proof that
  /// nothing changed, so only this one requires a canonical re-read before
  /// anything is retried.
  bool get mayHaveCommitted => failure == TenantProductUpdateFailure.ambiguous;

  @override
  String toString() => 'TenantProductUpdateException(${failure.name})';
}

/// Strictly decoded result from `updateProduct`.
///
/// The response is reconciled against the intent it was requested for: it must
/// name the same business and product, it must report the product holding
/// exactly the values that were asked for, and it must not claim to have moved a
/// field the request never named. Anything else is refused rather than
/// displayed, because this is the surface that states what a business now sells
/// and at what price.
final class TenantProductUpdateResult {
  const TenantProductUpdateResult._({
    required this.updateId,
    required this.productId,
    required this.changedFields,
    required this.name,
    required this.sku,
    required this.price,
    required this.priceMinor,
    required this.cost,
    required this.costMinor,
    required this.categoryId,
    required this.imageUrl,
  });

  factory TenantProductUpdateResult.fromCallable(
    Object? value, {
    required TenantProductUpdateIntent intent,
  }) {
    final data = _strictMap(value);
    if (data['tenantId'] != intent.tenantId) {
      throw const FormatException(
        'updateProduct answered for another business.',
      );
    }
    if (data['productId'] != intent.productId) {
      throw const FormatException(
        'updateProduct answered for another product.',
      );
    }
    final requested = intent.fields;
    final rawChanged = data['changedFields'];
    if (rawChanged is! List || rawChanged.isEmpty) {
      throw const FormatException('updateProduct returned no changed fields.');
    }
    final changedFields = <TenantProductField>[];
    for (final entry in rawChanged) {
      final field = entry is String
          ? TenantProductField.fromWireKey(entry)
          : null;
      // A response naming a field the request did not is describing a write
      // this correction never asked for, which is the one thing this boundary
      // exists to notice.
      if (field == null || !requested.contains(field)) {
        throw const FormatException(
          'updateProduct reported a field this correction did not name.',
        );
      }
      changedFields.add(field);
    }
    final name = _requiredString(data, 'name');
    final sku = _requiredString(data, 'sku');
    final categoryId = _requiredCategoryId(data);
    final imageUrl = _optionalCallableImage(data['image']);
    final price = data['price'];
    final priceMinor = data['priceMinor'];
    if (price is! num || priceMinor is! int) {
      throw const FormatException('updateProduct returned an invalid price.');
    }
    // Re-derived rather than trusted: a response whose own two figures for one
    // price disagree cannot describe the product the till will read.
    if (checkoutMinorUnitsFromMajor(price) != priceMinor) {
      throw const FormatException(
        'updateProduct returned inconsistent price figures.',
      );
    }
    final (cost, costMinor) = tenantCatalogOptionalMoney(
      data,
      'cost',
      'costMinor',
      source: 'updateProduct',
    );
    // Every field that was asked for must be what the product now holds, not
    // merely a value the server was willing to report.
    if (intent.name != null && name != intent.name) {
      throw const FormatException('updateProduct did not apply the name.');
    }
    if (intent.sku != null && sku != intent.sku) {
      throw const FormatException('updateProduct did not apply the code.');
    }
    if (intent.priceMinor != null && priceMinor != intent.priceMinor) {
      throw const FormatException('updateProduct did not apply the price.');
    }
    // The fifth field, reconcilable since the response began echoing it. Before
    // that a corrected cost appeared in `changedFields` with no value beside it,
    // so four of the five fields could be checked against the request and this
    // one could only be re-read.
    if (intent.costMinor != null && costMinor != intent.costMinor) {
      throw const FormatException('updateProduct did not apply the cost.');
    }
    if (intent.clearsCost && costMinor != null) {
      throw const FormatException('updateProduct did not clear the cost.');
    }
    if (intent.categoryId != null && categoryId != intent.categoryId) {
      throw const FormatException('updateProduct did not apply the category.');
    }
    if (intent.imageUrl != null && imageUrl != intent.imageUrl) {
      throw const FormatException('updateProduct did not apply the image.');
    }
    if (intent.clearsImage && imageUrl != null) {
      throw const FormatException('updateProduct did not clear the image.');
    }
    return TenantProductUpdateResult._(
      updateId: _requiredString(data, 'updateId'),
      productId: intent.productId,
      changedFields: List<TenantProductField>.unmodifiable(changedFields),
      name: name,
      sku: sku,
      price: price.toDouble(),
      priceMinor: priceMinor,
      cost: cost,
      costMinor: costMinor,
      categoryId: categoryId,
      imageUrl: imageUrl,
    );
  }

  /// The `audit_logs` entry recording the before and after of every field that
  /// moved. A price is money, and this is the record that answers "this was 450
  /// last week, who made it 45?".
  final String updateId;

  final String productId;

  /// Which fields actually moved, which can be fewer than the intent named:
  /// nothing is written for a field that already held the requested value.
  final List<TenantProductField> changedFields;

  final String name;
  final String sku;
  final double price;
  final int priceMinor;

  /// What one unit now costs the business, and null when none is recorded.
  ///
  /// Reconciled against the correction rather than merely reported: a cost that
  /// was corrected must come back holding the requested figure, and a cost that
  /// was cleared must come back null. Until the response echoed these two keys
  /// this surface confirmed a corrected cost by re-reading the catalog, which
  /// meant the one field a manager may not touch was also the one field the
  /// answer could not prove.
  final double? cost;
  final int? costMinor;

  final String categoryId;
  final Uri? imageUrl;
}

Uri? _optionalCallableImage(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('updateProduct returned an invalid image.');
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw const FormatException('updateProduct returned an invalid image.');
  }
  return uri;
}

/// Reads a money pair that may legitimately be absent, proving the two agree.
///
/// Both null or both present: a response naming one and not the other cannot
/// describe what a device will read, whichever half is missing. The major-unit
/// figure is re-derived through the till's own conversion for the same reason the
/// price is - two figures for one amount that disagree are not a value.
///
/// Shared with the bulk catalog decoders, which read the same pair out of a
/// per-row product rather than out of a single-product response.
(double?, int?) tenantCatalogOptionalMoney(
  Map<String, Object?> data,
  String majorKey,
  String minorKey, {
  required String source,
}) {
  final major = data[majorKey];
  final minor = data[minorKey];
  if (major == null && minor == null) return (null, null);
  if (major is! num || minor is! int) {
    throw FormatException('$source returned an invalid $majorKey.');
  }
  if (checkoutMinorUnitsFromMajor(major) != minor) {
    throw FormatException('$source returned inconsistent $majorKey figures.');
  }
  return (major.toDouble(), minor);
}

/// Session-bound gateway with no tenant input surface.
///
/// The business comes from one captured live session and the product from one
/// already-decoded catalog record, so no caller can name either.
final class TenantProductUpdateGateway {
  const TenantProductUpdateGateway({
    required TenantSession session,
    required UpdateProductCallable callable,
  }) : _session = session,
       _callable = callable;

  final TenantSession _session;
  final UpdateProductCallable _callable;

  /// Correcting a description is an operational act, matching the server's
  /// `PRODUCT_UPDATE_ROLES`. Money is narrower and is enforced when the intent
  /// is built.
  static bool canUpdateInSession(TenantSession session) => session.canAccess(
    allowedRoles: TenantCatalogManagementRepository.allowedRoles,
  );

  /// Submits [intent]; one intent keeps one request ID across a retry, so the
  /// server's own idempotency record settles a repeated attempt rather than
  /// auditing the same correction twice.
  Future<TenantProductUpdateResult> submit(
    TenantProductUpdateIntent intent,
  ) async {
    if (!canUpdateInSession(_session) || intent.tenantId != _session.tenantId) {
      throw const TenantProductUpdateException(
        TenantProductUpdateFailure.forbidden,
      );
    }
    final Object? response;
    try {
      response = await _callable.call(intent.payload());
    } on FirebaseFunctionsException catch (error) {
      throw TenantProductUpdateException(_classifyUpdate(error));
    } on TimeoutException {
      throw const TenantProductUpdateException(
        TenantProductUpdateFailure.ambiguous,
      );
    } catch (_) {
      throw const TenantProductUpdateException(
        TenantProductUpdateFailure.ambiguous,
      );
    }
    return TenantProductUpdateResult.fromCallable(response, intent: intent);
  }
}

/// Classifies a refusal from `updateProduct`.
///
/// The code decides the outcome. `permission-denied` and `failed-precondition`
/// each cover several distinct server conditions, so those are separated by the
/// exact wording `productUpdate.ts` and `products.ts` raise. If that wording ever
/// changes the case degrades to a broader failure in the same family, which
/// still reports truthfully that nothing changed - the classification only ever
/// words a message and never decides whether to retry.
TenantProductUpdateFailure _classifyUpdate(FirebaseFunctionsException error) {
  final message = error.message ?? '';
  return switch (error.code) {
    'permission-denied' when message.contains("product's price") =>
      TenantProductUpdateFailure.priceForbidden,
    'permission-denied' when message.contains('what a product costs') =>
      TenantProductUpdateFailure.costForbidden,
    'permission-denied' ||
    'unauthenticated' => TenantProductUpdateFailure.forbidden,
    'not-found' => TenantProductUpdateFailure.productMissing,
    'already-exists' => TenantProductUpdateFailure.duplicateRequest,
    'failed-precondition' when message.contains('category does not exist') =>
      TenantProductUpdateFailure.categoryMissing,
    'failed-precondition' when message.contains('already holds every value') =>
      TenantProductUpdateFailure.unchanged,
    'failed-precondition' when message.contains('operator') =>
      TenantProductUpdateFailure.needsOperator,
    'failed-precondition' => TenantProductUpdateFailure.productUnreadable,
    'invalid-argument' => TenantProductUpdateFailure.invalidRequest,
    'unavailable' ||
    'deadline-exceeded' ||
    'internal' ||
    'aborted' ||
    'unknown' => TenantProductUpdateFailure.ambiguous,
    _ => TenantProductUpdateFailure.refused,
  };
}

Map<String, Object?> _strictMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('updateProduct returned an invalid response.');
  }
  return <String, Object?>{
    for (final key in value.keys)
      if (key is String) key: value[key],
  };
}

String _requiredString(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw FormatException('updateProduct returned an invalid $field.');
  }
  return value;
}

String _requiredCategoryId(Map<String, Object?> data) {
  final value = _requiredString(data, 'categoryId');
  try {
    return validateTenantDocumentId(value, fieldName: 'categoryId');
  } on ArgumentError {
    throw const FormatException(
      'updateProduct returned an invalid categoryId.',
    );
  }
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
String tenantCatalogNormalizedName(String value, String code) {
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
String tenantCatalogNormalizedSku(String value) {
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
int tenantCatalogPriceMinorUnits(
  String value, {
  String invalidCode = 'invalid_price',
  String unrepresentableCode = 'price_not_representable',
}) {
  final text = value.trim();
  if (!_pricePattern.hasMatch(text)) {
    throw TenantCatalogManagementException(invalidCode);
  }
  final parts = text.split('.');
  final minorUnits =
      int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  if (checkoutMinorUnitsFromMajor(minorUnits / 100) != minorUnits) {
    throw TenantCatalogManagementException(unrepresentableCode);
  }
  return minorUnits;
}

/// Formats exact minor units the way every amount in this app is written.
String tenantCatalogMajorUnits(int minorUnits) =>
    (minorUnits / 100).toStringAsFixed(2);

final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _pricePattern = RegExp(r'^\d{1,12}(\.\d{1,2})?$');
final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
