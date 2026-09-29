import '../ui/money_text.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';

import '../checkout/checkout_draft.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_id.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import '../observability/app_telemetry.dart';

/// The longest product or category name this surface writes.
///
/// **A category's name is bounded here and nowhere else**: `allow create` on
/// `categories` checks nothing at all, and a category is still a document write.
/// A product's name now passes `createProduct`, which reads the resulting
/// document through the server's own `readSellableProduct` - so this is the
/// tighter of two bounds there rather than the only one. It exists so a name
/// cannot be pasted long enough to make every catalog and receipt surface
/// unreadable.
const int maximumCatalogNameLength = 120;

/// The longest stock-keeping unit this surface writes, bounded for the same
/// reason.
const int maximumCatalogSkuLength = 64;

/// The stock a product is created holding when the form was left blank.
///
/// **This used to be the only figure a create could carry, and the reason was a
/// capability rather than a policy.** Stock that appears with no
/// `stock_movements` entry has no recorded origin, and no device can write that
/// collection - so while creating a product was a Firestore `set`, zero was the
/// only number the client could also account for. `createProduct` writes the
/// product and its opening ledger entry in one transaction, so an opening
/// balance is now nameable here exactly as it has always been nameable in an
/// import. Blank still means none, which is the ordinary case.
const int catalogOpeningQuantity = 0;

/// The largest opening balance one created product may carry, matching the
/// server's `MAXIMUM_IMPORT_OPENING_STOCK` and the import surface's own
/// [maximumBulkOpeningQuantity].
///
/// One bound across the three, because a limit one create path enforces and
/// another does not would be a way in rather than a rule.
const int maximumCatalogOpeningQuantity = 1000000;

/// Reads an opening balance typed into the add-product form.
///
/// Blank is [catalogOpeningQuantity] rather than a refusal: most products are
/// added holding nothing, and an empty field is how somebody says so. Everything
/// else is refused rather than coerced - `int.tryParse` would read "12.5" as
/// null and "12abc" as null alike, and both are worth saying out loud, because a
/// quantity silently read as zero is stock the shopkeeper believes they recorded.
int tenantCatalogOpeningQuantity(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return catalogOpeningQuantity;
  final quantity = int.tryParse(trimmed);
  if (quantity == null ||
      quantity < 0 ||
      quantity > maximumCatalogOpeningQuantity) {
    throw const TenantCatalogManagementException('invalid_opening_quantity');
  }
  return quantity;
}

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

/// A validated instruction to create exactly one product.
///
/// The key set is the one [TenantProduct] demands, in full. It is no longer the
/// *only* thing standing between a device and an unparseable product: `allow
/// create` on `products` is now `if false`, and `createProduct` reads the
/// document it is sent through `readSellableProduct` before writing it. This
/// remains the first of those two checks, so a defect a person can fix is
/// reported on the form instead of costing a round trip and an idempotency
/// record - which is the same reason `TenantStockAdjustmentGateway.createIntent`
/// mirrors the server's own validation.
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
    required this.quantity,
    this.imageUrl,
    this.costType = TenantProductCostType.purchased,
  });

  final String path;
  final String tenantId;
  final String productId;
  final String name;
  final String sku;

  /// Bought in or made here. Not money, so every role that may create a
  /// product may set it.
  final TenantProductCostType costType;

  /// The units the business already holds, and zero for the ordinary case.
  ///
  /// **The one quantity a single-product payload in this app may carry.** It
  /// reaches the server through `createProduct`, which writes the opening
  /// `stock_adjustments` record and `stock_movements` entry in the same
  /// transaction as the product. No device can write either collection, which is
  /// why this could not be a figure at all while creating a product was a
  /// document write.
  final int quantity;

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
    'quantity': quantity,
    'categoryId': categoryId,
    'searchName': tenantProductSearchName(name),
    'searchPrefixes': tenantProductSearchPrefixes(name: name, sku: sku),
    if (imageUrl != null) 'image': imageUrl.toString(),
    'costType': costType.wireValue,
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
    required this.requestId,
    required this.retired,
  });

  final String path;
  final String tenantId;
  final String productId;
  final String name;
  final String sku;

  /// The stock the product was holding when it was read.
  ///
  /// **Retiring now clears it, and says where it went.** `setProductRetired`
  /// writes the `stock_movements` entry that accounts for these units in the
  /// same transaction as the flag, so a product retired holding seventeen ends
  /// at zero with a ledger entry rather than disappearing with the figure still
  /// on it. The figure here is what the form states before the operator agrees.
  final int quantity;

  /// One key per attempt, so a retry settles the first retirement rather than
  /// clearing the stock twice.
  ///
  /// **Minted per attempt and not derived from the product**, unlike a create's.
  /// A product may be retired, restored and retired again, and each retirement
  /// clears whatever it held at that moment - so they are separate operations
  /// and must not answer off one another's record.
  final String requestId;

  /// Whether this takes the product out of the catalog or puts it back.
  final bool retired;

  /// What the server is asked, which is also what the queue replays.
  Map<String, Object?> payload() => <String, Object?>{
    'tenantId': tenantId,
    'productId': productId,
    'requestId': requestId,
    'retired': retired,
  };
}

/// A descriptive field `updateProduct` may correct, with the exact key it reads.
///
/// `quantity` is deliberately absent and can never be added here: it belongs to
/// `adjustStock`, which writes a `stock_movements` entry, and the callable
/// refuses a payload that so much as mentions it.
enum TenantProductField {
  name('name', 'Name'),
  sku('sku', 'Code'),
  price('price', 'Selling price'),
  cost('cost', 'Buying price'),
  categoryId('categoryId', 'Category'),
  image('image', 'Image'),

  /// Bought in or made here. Descriptive, not money: see
  /// [TenantProductCostType].
  ///
  /// A noun like the others, and the form's own heading for it: the banner
  /// after a correction lists these, and *Corrected: bought in or made here*
  /// read as a question rather than as what changed.
  costType('costType', 'Where it comes from');

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
    this.costType,
  });

  final String tenantId;
  final String productId;

  /// The new cost type, or null when it is not being changed.
  final TenantProductCostType? costType;

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
    if (costType != null) 'costType': costType!.wireValue,
  };
}

typedef TenantCatalogRequestIdFactory = String Function();

/// Withdraws a queued catalog change, answering whether it was still there to
/// withdraw.
///
/// **False is a real answer, not a failure.** A change that has left this device
/// cannot be taken back by it, and the surface offering *Undo* has to be able
/// to say so instead of claiming a reversal that did not happen.
typedef TenantCatalogUndo =
    Future<bool> Function({
      required String tenantId,
      required String operationId,
    });

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
  /// [openingQuantity] is what the business already has on the shelf, and blank
  /// means none. It is the one figure no other single-product payload in this
  /// app may name: `createProduct` accepts it because the same transaction
  /// writes the `stock_movements` entry saying where those units came from, and
  /// nothing a device can write does.
  TenantProductCreateIntent buildProductIntent({
    required String name,
    required String sku,
    required String price,
    required String categoryId,
    required Iterable<TenantCategory> categories,
    required String requestId,
    String cost = '',
    String openingQuantity = '',
    Uri? imageUrl,
    TenantProductCostType costType = TenantProductCostType.purchased,
  }) {
    _requireCreateRole();
    _requireRequestId(requestId);
    final safeName = tenantCatalogNormalizedName(name, 'invalid_product_name');
    final safeSku = tenantCatalogNormalizedSku(sku);
    final priceMinor = tenantCatalogPriceMinorUnits(price);
    final quantity = tenantCatalogOpeningQuantity(openingQuantity);
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
      quantity: quantity,
      imageUrl: _validatedProductImage(imageUrl),
      costType: costType,
    );
  }

  /// Builds the one retirement - or restoration - [product] describes.
  ///
  /// **It carries a request ID now, and that is not ceremony.** This used to be
  /// a delete, where a retry after an unknown outcome deleted the same document
  /// a second time and that was exactly nothing. Retiring clears stock through
  /// the ledger, so a second attempt under a fresh key would write a second
  /// movement; one key per attempt is what makes the retry settle the first.
  TenantProductRetireIntent buildRetireIntent(
    TenantProduct product, {
    required String requestId,
    bool retired = true,
  }) {
    if (!canRetireInSession(session)) {
      throw const TenantCatalogManagementException('retire_forbidden');
    }
    // A product decoded while another business was open can never be retired
    // from this one, even though both paths would be well-formed.
    if (product.tenantId != session.tenantId) {
      throw const TenantCatalogManagementException('retire_forbidden');
    }
    _requireRequestId(requestId);
    return TenantProductRetireIntent._(
      path: paths.product(product.id),
      tenantId: session.tenantId,
      productId: product.id,
      name: product.name,
      sku: product.sku,
      quantity: product.quantity,
      requestId: requestId,
      retired: retired,
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
    TenantProductCostType? costType,
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

    TenantProductCostType? nextCostType;
    if (costType != null && costType != product.costType) {
      nextCostType = costType;
      changes.add(
        TenantProductFieldChange._(
          field: TenantProductField.costType,
          previous: product.costType.label,
          next: costType.label,
        ),
      );
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
      costType: nextCostType,
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

  /// The change is durable on this device and has not reached the server yet.
  ///
  /// **Not a lesser kind of success.** It is what a queued catalog write
  /// returns every time, online included: the record is in encrypted local
  /// storage, the overlay is already drawing it, and
  /// `TenantPendingMutationWorker` carries it from there. What it does not
  /// claim is a server acknowledgement, because none has been waited for -
  /// waiting for one is the whole cost this replaced.
  queued,

  /// The server refused the write; a canonical re-read decides what exists.
  rejected,

  /// The outcome is unknown; only a canonical re-read may settle it.
  ambiguous,

  /// No attempt was made because the device was offline.
  unavailable,
}

final class TenantCatalogWriteResult {
  const TenantCatalogWriteResult._(this.kind, [this.reasonCode])
    : operationId = null;

  const TenantCatalogWriteResult.committed()
    : this._(TenantCatalogWriteKind.committed);

  /// A durable local record, named so the caller can offer to withdraw it.
  ///
  /// [operationId] is how an *Undo* finds the record again. The writer derives
  /// it and the panel only carries it back, so no surface has to know how a
  /// queued catalog change is keyed.
  const TenantCatalogWriteResult.queued(this.operationId)
    : kind = TenantCatalogWriteKind.queued,
      reasonCode = null;

  const TenantCatalogWriteResult.rejected(String reasonCode)
    : this._(TenantCatalogWriteKind.rejected, reasonCode);

  const TenantCatalogWriteResult.ambiguous(String reasonCode)
    : this._(TenantCatalogWriteKind.ambiguous, reasonCode);

  const TenantCatalogWriteResult.unavailable()
    : this._(TenantCatalogWriteKind.unavailable);

  final TenantCatalogWriteKind kind;
  final String? reasonCode;

  /// Set only on [TenantCatalogWriteResult.queued]. See that constructor.
  final String? operationId;
}

/// The narrow write boundary used to change a catalog.
///
/// **There is no Firestore implementation of it, and there cannot be one now.**
/// All four of these are callables, for two reasons that meet here:
///
/// - a **product create** may carry an opening quantity, and a **retire** clears
///   one. The `stock_adjustments` record and `stock_movements` entry that account
///   for those units are server-write-only, so the product and its ledger entry
///   have to be written by one principal in one transaction.
/// - a **category create** and a **rename** must refuse a name another category
///   in this business already folds to, because two categories with one name
///   cannot be told apart when a spreadsheet names that category. Deciding that
///   means reading every other category in the collection inside the transaction
///   that writes, and a Firestore rule may read the document being written and
///   named documents - never a query.
///
/// So `firestore.rules` denies all four to every client, and
/// [QueuedTenantCatalogWriter] is the only implementation the app holds: it
/// writes the intent to encrypted local storage and the pending-mutation worker
/// carries it to the callable. None of this gave up offline - the outbox and its
/// overlay are what bought that, never the direct write.
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
    final result = await traceServerCall(
      'updateProduct',
      () => _functions.httpsCallable('updateProduct').call<Object?>(payload),
    );
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

  /// The correction could not be stored on this device, so it was never sent
  /// and nothing anywhere recorded it.
  ///
  /// The twin of `TenantStockAdjustmentFailure.notRecorded`, and it exists for
  /// the same reason: with a queue wired this is the only path a correction
  /// takes, so the branch with no failure story was the one every correction
  /// goes through.
  notRecorded,

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

  /// The correction as it will stand, projected from what the product holds and
  /// what this intent moves.
  ///
  /// **No server has seen it, and the result says so.** [queued] is what
  /// separates this from [TenantProductUpdateResult.fromCallable]: there is no
  /// `updateId`, because only the server issues one, and every figure here is
  /// this device's arithmetic rather than the server's answer. It is the truth
  /// about what the catalog now shows, which is what a notice needs to state.
  ///
  /// The consistency checks `fromCallable` performs have no counterpart and
  /// need none - it is checking a *response* against the request, and here
  /// there is no second party to disagree.
  factory TenantProductUpdateResult.queued({
    required TenantProductUpdateIntent intent,
    required TenantProduct previous,
  }) {
    // The price this correction leaves behind, in the units a sale line
    // records. A stored price no device can convert is the `productUnreadable`
    // case, which `buildUpdateIntent` already refuses before any of this - so
    // reaching it here means the product changed underneath the form, and
    // refusing again is the same answer for the same reason.
    final priceMinor =
        intent.priceMinor ?? checkoutMinorUnitsFromMajor(previous.price);
    if (priceMinor == null) {
      throw const TenantProductUpdateException(
        TenantProductUpdateFailure.productUnreadable,
      );
    }
    return TenantProductUpdateResult._(
      updateId: null,
      productId: intent.productId,
      changedFields: List<TenantProductField>.unmodifiable(intent.fields),
      name: intent.name ?? previous.name,
      sku: intent.sku ?? previous.sku,
      price: priceMinor / 100,
      priceMinor: priceMinor,
      cost: intent.clearsCost
          ? null
          : intent.costMinor == null
          ? previous.cost
          : intent.costMinor! / 100,
      costMinor: intent.clearsCost
          ? null
          : intent.costMinor ??
                (previous.cost == null
                    ? null
                    : checkoutMinorUnitsFromMajor(previous.cost!)),
      categoryId: intent.categoryId ?? previous.categoryId,
      imageUrl: intent.clearsImage
          ? null
          : intent.imageUrl ?? previous.imageUrl,
    );
  }

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
    if (intent.costType != null &&
        data['costType'] != intent.costType!.wireValue) {
      throw const FormatException(
        'updateProduct did not apply where the cost comes from.',
      );
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
  /// The server's own identifier for this correction, or null while the
  /// correction is still only on this device. A queued correction has no
  /// `updateId` because nothing has issued one yet, and inventing a local
  /// stand-in would put a number in an audit trail that names nothing.
  final String? updateId;

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
/// Where a correction is parked until this device can send it.
///
/// **A function rather than the queue itself**, so this file keeps its existing
/// import direction: `lib/inventory` depends on `lib/tenancy`, and the durable
/// store lives there. The composition root supplies a closure that enqueues and
/// asks the worker to run; nothing here knows what Hive is.
typedef TenantProductUpdateQueue =
    Future<void> Function({
      required String tenantId,
      required String productId,
      required String requestId,
      required Map<String, Object?> payload,
    });

final class TenantProductUpdateGateway {
  const TenantProductUpdateGateway({
    required TenantSession session,
    required UpdateProductCallable callable,
    TenantProductUpdateQueue? queue,
  }) : _session = session,
       _callable = callable,
       _queue = queue;

  final TenantSession _session;
  final UpdateProductCallable _callable;
  final TenantProductUpdateQueue? _queue;

  /// Correcting a description is an operational act, matching the server's
  /// `PRODUCT_UPDATE_ROLES`. Money is narrower and is enforced when the intent
  /// is built.
  static bool canUpdateInSession(TenantSession session) => session.canAccess(
    allowedRoles: TenantCatalogManagementRepository.allowedRoles,
  );

  /// Submits [intent]; one intent keeps one request ID across a retry, so the
  /// server's own idempotency record settles a repeated attempt rather than
  /// auditing the same correction twice.
  ///
  /// **With a queue wired, nothing here waits for the server.** The correction
  /// becomes a durable record, the overlay draws it over the product at once,
  /// and the worker carries it. The authorization check above still runs first
  /// and still refuses locally - queueing a correction this session may not
  /// make would only be a slower way to be told no.
  ///
  /// [previous] is what the product held when the form opened, and is required
  /// for the queued path because a result has to state the whole product rather
  /// than only the fields that moved.
  Future<TenantProductUpdateResult> submit(
    TenantProductUpdateIntent intent, {
    TenantProduct? previous,
  }) async {
    if (!canUpdateInSession(_session) || intent.tenantId != _session.tenantId) {
      throw const TenantProductUpdateException(
        TenantProductUpdateFailure.forbidden,
      );
    }
    final queue = _queue;
    if (queue != null && previous != null) {
      // Guarded for the reason the callable below is, and it was not until
      // 2026-09-13: parking a correction can fail, and an unguarded throw here
      // went straight past the panel's handlers and told the operator nothing.
      try {
        await queue(
          tenantId: intent.tenantId,
          productId: intent.productId,
          requestId: intent.requestId,
          payload: intent.payload(),
        );
      } catch (error) {
        // A key already holding different values is the same fact the server
        // states as `already-exists`, so it keeps that failure and its sentence
        // rather than acquiring a second wording for one situation.
        throw TenantProductUpdateException(
          '$error'.contains('operation_id_conflict')
              ? TenantProductUpdateFailure.duplicateRequest
              : TenantProductUpdateFailure.notRecorded,
        );
      }
      return TenantProductUpdateResult.queued(
        intent: intent,
        previous: previous,
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
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'inventory.product_update_request',
      );
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
String tenantCatalogMajorUnits(int minorUnits) => moneyTextOfMinor(minorUnits);

final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _pricePattern = RegExp(r'^\d{1,12}(\.\d{1,2})?$');
final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
