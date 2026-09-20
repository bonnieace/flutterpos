import 'dart:async';

import 'package:hive/hive.dart';

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_paths.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import 'checkout_configuration.dart';
import 'checkout_catalog_local_sales.dart';
import 'checkout_outbox.dart';

/// Raised when the local catalog cache cannot be opened or written safely.
final class CheckoutCatalogCacheException implements Exception {
  const CheckoutCatalogCacheException(this.code);

  final String code;

  @override
  String toString() => 'CheckoutCatalogCacheException($code)';
}

typedef CheckoutCatalogCacheClock = DateTime Function();

/// One validated, UID- and tenant-scoped catalog snapshot.
///
/// Every entry was produced by the strict [TenantProduct]/[TenantCategory]
/// read models and re-validated against this exact tenant's paths on read, so
/// the cache can never widen what the guarded repository already accepted.
final class CheckoutCatalogSnapshot {
  CheckoutCatalogSnapshot._({
    required this.uid,
    required this.tenantId,
    required this.refreshedAt,
    required this.complete,
    required this.configuration,
    required List<TenantCategory> categories,
    required List<TenantProduct> products,
  }) : categories = List<TenantCategory>.unmodifiable(categories),
       products = List<TenantProduct>.unmodifiable(products),
       _productsById = <String, TenantProduct>{
         for (final product in products) product.id: product,
       },
       _categoriesById = <String, TenantCategory>{
         for (final category in categories) category.id: category,
       };

  /// Test and composition boundary for a snapshot that did not come from Hive.
  ///
  /// The entries still pass through the same strict [TenantProduct] and
  /// [TenantCategory] read models, so this widens who may build a snapshot
  /// without widening what a snapshot may contain.
  factory CheckoutCatalogSnapshot.forTesting({
    required String uid,
    required String tenantId,
    required TenantCheckoutConfiguration configuration,
    List<TenantCategory> categories = const <TenantCategory>[],
    List<TenantProduct> products = const <TenantProduct>[],
    DateTime? refreshedAt,
    bool complete = true,
  }) => CheckoutCatalogSnapshot._(
    uid: uid,
    tenantId: tenantId,
    refreshedAt: refreshedAt ?? DateTime.utc(2026, 7, 31),
    complete: complete,
    configuration: configuration,
    categories: categories,
    products: products,
  );

  final String uid;
  final String tenantId;
  final DateTime refreshedAt;

  /// Whether the refresh reached the end of both collections within bounds.
  final bool complete;

  /// The guarded tenant checkout configuration a draft must be priced with.
  final TenantCheckoutConfiguration configuration;

  final List<TenantCategory> categories;
  final List<TenantProduct> products;
  final Map<String, TenantProduct> _productsById;
  final Map<String, TenantCategory> _categoriesById;

  TenantProduct? productById(String productId) => _productsById[productId];

  TenantCategory? categoryById(String categoryId) =>
      _categoriesById[categoryId];

  bool ownsSession(TenantSession session) =>
      session.uid == uid && session.tenantId == tenantId;
}

/// Versioned encrypted Hive cache of one tenant's catalog for offline drafts.
///
/// The cache is derived data, never authorization. A malformed or foreign
/// record is reported as a miss so a draft fails closed instead of trusting
/// unvalidated local state.
/// The narrow read the checkout cart needs from the offline catalog.
///
/// The cart depends on this rather than on the encrypted box, so a surface that
/// only prices a sale cannot reach the cache's write, refresh, or eviction
/// behavior - and so it can be exercised without real disk I/O.
abstract interface class CheckoutCatalogSource {
  Future<CheckoutCatalogSnapshot?> read({
    required String uid,
    required String tenantId,
  });
}

final class HiveCheckoutCatalogCache implements CheckoutCatalogSource {
  HiveCheckoutCatalogCache._(this._box, this._clock, this._localSales);

  static const boxName = 'checkout-catalog-cache-v1';

  /// Version 2 adds the required tenant checkout configuration.
  ///
  /// A version 1 record is reported as a miss rather than migrated, so a draft
  /// can never be priced with a currency the tenant never published.
  static const schemaVersion = 2;
  static const encryptionKeyBytes = HiveCheckoutOutbox.encryptionKeyBytes;

  final Box<dynamic> _box;

  /// What this device has sold since this catalog was written, subtracted on
  /// read. Absent in a build that does not track it, which leaves every figure
  /// exactly as the stored snapshot recorded it.
  final CheckoutCatalogLocalSales? _localSales;

  /// The tally this cache subtracts, for whoever records into it.
  ///
  /// **Exposed so the pairing cannot drift.** A sale is recorded by the draft
  /// service and subtracted here; handing both the same object through the
  /// composition root twice is two chances to hand over two.
  CheckoutCatalogLocalSales? get localSales => _localSales;
  final CheckoutCatalogCacheClock _clock;

  static Future<HiveCheckoutCatalogCache> open({
    required CheckoutOutboxEncryptionKeyProvider keyProvider,
    HiveInterface? hive,
    CheckoutCatalogCacheClock? clock,
    CheckoutCatalogLocalSales? localSales,
  }) async {
    final key = await keyProvider.loadOrCreateKey();
    if (key.length != encryptionKeyBytes) {
      throw const CheckoutCatalogCacheException('invalid_encryption_key');
    }
    final box = await (hive ?? Hive).openBox<dynamic>(
      boxName,
      encryptionCipher: HiveAesCipher(List<int>.from(key)),
      crashRecovery: false,
    );
    return HiveCheckoutCatalogCache._(box, clock ?? _utcNow, localSales);
  }

  /// Test and composition boundary for an already encrypted Hive box.
  factory HiveCheckoutCatalogCache.fromBox(
    Box<dynamic> box, {
    CheckoutCatalogCacheClock? clock,
    CheckoutCatalogLocalSales? localSales,
  }) => HiveCheckoutCatalogCache._(box, clock ?? _utcNow, localSales);

  /// The stored quantity, less what this device has sold since it was stored.
  ///
  /// **Applied here rather than in the register**, so every surface reading
  /// this catalog gets one answer, and so the figure still passes through
  /// `TenantProduct`'s strict read model exactly as the stored one did.
  ///
  /// A non-integer is handed back untouched for that model to refuse - guessing
  /// at a malformed figure is how a cache starts widening what a repository
  /// already accepted. The result is allowed to go negative, because
  /// `-3 in stock` is a real state this till already states in words: it means
  /// more was sold than the books knew about, which is exactly what a person
  /// needs to see.
  Object? _quantityOnHand({
    required String uid,
    required String tenantId,
    required String productId,
    required Object? stored,
  }) {
    final sales = _localSales;
    if (sales == null || stored is! int) return stored;
    return stored -
        sales.soldFor(uid: uid, tenantId: tenantId, productId: productId);
  }

  /// Returns the cached snapshot, or `null` for a miss.
  ///
  /// A stored record that no longer parses through the strict read models, or
  /// that names another UID, tenant, or document path, is treated as a miss.
  @override
  Future<CheckoutCatalogSnapshot?> read({
    required String uid,
    required String tenantId,
  }) async {
    final key = checkoutSessionStorageKey(uid: uid, tenantId: tenantId);
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      return _parseSnapshot(key, uid: uid, tenantId: tenantId, raw: raw);
    } catch (_) {
      return null;
    }
  }

  /// Replaces the cached snapshot for one exact UID and tenant.
  Future<CheckoutCatalogSnapshot> write({
    required String uid,
    required String tenantId,
    required TenantCheckoutConfiguration configuration,
    required List<TenantCategory> categories,
    required List<TenantProduct> products,
    required bool complete,
  }) async {
    final key = checkoutSessionStorageKey(uid: uid, tenantId: tenantId);
    final paths = TenantPaths(tenantId);
    final refreshedAt = _clock().toUtc();
    final categoryEntries = <Map<String, Object?>>[];
    final seenCategories = <String>{};
    for (final category in categories) {
      if (!seenCategories.add(category.id)) {
        throw const CheckoutCatalogCacheException('duplicate_cache_document');
      }
      categoryEntries.add(<String, Object?>{
        'path': paths.category(category.id),
        'name': category.name,
      });
    }
    final productEntries = <Map<String, Object?>>[];
    final seenProducts = <String>{};
    for (final product in products) {
      if (!seenProducts.add(product.id)) {
        throw const CheckoutCatalogCacheException('duplicate_cache_document');
      }
      productEntries.add(<String, Object?>{
        'path': paths.product(product.id),
        'name': product.name,
        'SKU': product.sku,
        'price': product.price,
        // Cached because the till stamps it onto a sale line while offline, and
        // an absent cost is a permanent "not recorded" on that line rather than
        // something a later sync fills in.
        if (product.cost != null) 'cost': product.cost,
        'quantity': product.quantity,
        'categoryId': product.categoryId,
        if (product.imageUrl != null) 'image': product.imageUrl.toString(),
      });
    }

    // **The tally is settled by the write, not by a timer.** This snapshot came
    // from the server, which has already counted every sale this device made
    // before it - so keeping the tally would subtract them a second time.
    _localSales?.clearFor(uid: uid, tenantId: tenantId);
    await _box.put(key, <String, Object?>{
      'schemaVersion': schemaVersion,
      'uid': uid,
      'tenantId': tenantId,
      'refreshedAtMs': refreshedAt.millisecondsSinceEpoch,
      'complete': complete,
      'configuration': configuration.toCacheEntry(),
      'categories': categoryEntries,
      'products': productEntries,
    });
    return CheckoutCatalogSnapshot._(
      uid: uid,
      tenantId: tenantId,
      refreshedAt: refreshedAt,
      complete: complete,
      configuration: configuration,
      categories: categories,
      products: products,
    );
  }

  Future<void> close() => _box.close();

  CheckoutCatalogSnapshot _parseSnapshot(
    String key, {
    required String uid,
    required String tenantId,
    required Object? raw,
  }) {
    if (raw is! Map) throw const FormatException();
    final map = Map<Object?, Object?>.from(raw);
    if (map['schemaVersion'] != schemaVersion) throw const FormatException();
    final storedUid = map['uid'];
    final storedTenantId = map['tenantId'];
    if (storedUid is! String || storedTenantId is! String) {
      throw const FormatException();
    }
    if (checkoutSessionStorageKey(uid: storedUid, tenantId: storedTenantId) !=
            key ||
        storedUid != uid ||
        storedTenantId != tenantId) {
      throw const FormatException();
    }
    final refreshedAtMs = map['refreshedAtMs'];
    if (refreshedAtMs is! int || refreshedAtMs < 0) {
      throw const FormatException();
    }
    final complete = map['complete'];
    if (complete is! bool) throw const FormatException();
    final configuration = TenantCheckoutConfiguration.fromMap(
      _stringKeyedMap(map['configuration']),
    );

    final paths = TenantPaths(tenantId);
    final categories = <TenantCategory>[];
    final seenCategories = <String>{};
    for (final entry in _entries(map['categories'])) {
      final category = TenantCategory.fromSnapshot(
        TenantQueryDocumentSnapshot(
          path: _entryPath(entry),
          data: <String, Object?>{'name': entry['name']},
        ),
      );
      if (paths.category(category.id) != entry['path'] ||
          !seenCategories.add(category.id)) {
        throw const FormatException();
      }
      categories.add(category);
    }

    final products = <TenantProduct>[];
    final seenProducts = <String>{};
    for (final entry in _entries(map['products'])) {
      final product = TenantProduct.fromSnapshot(
        TenantQueryDocumentSnapshot(
          path: _entryPath(entry),
          data: <String, Object?>{
            'name': entry['name'],
            'SKU': entry['SKU'],
            'price': entry['price'],
            if (entry['cost'] != null) 'cost': entry['cost'],
            'quantity': _quantityOnHand(
              uid: uid,
              tenantId: tenantId,
              productId: _entryPath(entry).split('/').last,
              stored: entry['quantity'],
            ),
            'categoryId': entry['categoryId'],
            if (entry['image'] != null) 'image': entry['image'],
          },
        ),
      );
      if (paths.product(product.id) != entry['path'] ||
          !seenProducts.add(product.id)) {
        throw const FormatException();
      }
      products.add(product);
    }

    return CheckoutCatalogSnapshot._(
      uid: uid,
      tenantId: tenantId,
      refreshedAt: DateTime.fromMillisecondsSinceEpoch(
        refreshedAtMs,
        isUtc: true,
      ),
      complete: complete,
      configuration: configuration,
      categories: categories,
      products: products,
    );
  }

  Map<String, Object?> _stringKeyedMap(Object? raw) {
    if (raw is! Map) throw const FormatException();
    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) throw const FormatException();
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  List<Map<Object?, Object?>> _entries(Object? raw) {
    if (raw is! List) throw const FormatException();
    return <Map<Object?, Object?>>[
      for (final entry in raw)
        if (entry is Map)
          Map<Object?, Object?>.from(entry)
        else
          throw const FormatException(),
    ];
  }

  String _entryPath(Map<Object?, Object?> entry) {
    final path = entry['path'];
    if (path is! String || path.isEmpty) throw const FormatException();
    return path;
  }
}

enum CheckoutCatalogRefreshKind {
  completed,
  noSelectedSession,
  alreadyRunning,
  sessionChanged,
  unavailable,

  /// The tenant published no usable `configuration/checkout` document.
  configurationUnavailable,
  storageUnavailable,
}

final class CheckoutCatalogRefreshResult {
  const CheckoutCatalogRefreshResult(
    this.kind, {
    this.categories = 0,
    this.products = 0,
    this.complete = false,
  });

  final CheckoutCatalogRefreshKind kind;
  final int categories;
  final int products;

  /// Whether both collections were fully read within the configured bounds.
  final bool complete;
}

/// Refreshes the offline catalog cache for the currently selected session.
///
/// Every page is read through the guarded [TenantCatalogRepository], so the
/// tenant path, page bound, ordering, duplicate, and cross-tenant checks in
/// that boundary apply unchanged. The captured UID, tenant, and epoch must
/// still own the result before anything is written locally.
final class CheckoutCatalogCacheRefresher {
  CheckoutCatalogCacheRefresher({
    required TenantSessionController sessionController,
    required HiveCheckoutCatalogCache cache,
    required TenantDataReader reader,
    int pageSize = 50,
    int maximumCategories = 500,
    int maximumProducts = 2000,
  }) : _sessionController = sessionController,
       _cache = cache,
       _reader = reader,
       _pageSize = pageSize,
       _maximumCategories = maximumCategories,
       _maximumProducts = maximumProducts {
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    if (maximumCategories < pageSize || maximumProducts < pageSize) {
      throw ArgumentError('Cache bounds must admit at least one page.');
    }
  }

  final TenantSessionController _sessionController;
  final HiveCheckoutCatalogCache _cache;
  final TenantDataReader _reader;
  final int _pageSize;
  final int _maximumCategories;
  final int _maximumProducts;
  bool _running = false;
  bool _rerunRequested = false;

  bool get isRunning => _running;

  Future<CheckoutCatalogRefreshResult> refreshSelectedSession() async {
    if (_running) {
      _rerunRequested = true;
      return const CheckoutCatalogRefreshResult(
        CheckoutCatalogRefreshKind.alreadyRunning,
      );
    }
    final captured = _sessionController.session;
    if (captured == null || !captured.canAccess()) {
      return const CheckoutCatalogRefreshResult(
        CheckoutCatalogRefreshKind.noSelectedSession,
      );
    }

    _running = true;
    try {
      final repository = TenantCatalogRepository(
        session: captured,
        reader: _reader,
      );

      // Configuration is read first: without it no draft may be priced, so
      // paging the catalog would only waste a round trip.
      final TenantCheckoutConfiguration? configuration;
      try {
        configuration = await TenantCheckoutConfigurationRepository(
          session: captured,
          reader: _reader,
        ).load();
      } on TenantScopeViolation {
        return const CheckoutCatalogRefreshResult(
          CheckoutCatalogRefreshKind.unavailable,
        );
      } on FormatException {
        return const CheckoutCatalogRefreshResult(
          CheckoutCatalogRefreshKind.configurationUnavailable,
        );
      } catch (_) {
        return const CheckoutCatalogRefreshResult(
          CheckoutCatalogRefreshKind.unavailable,
        );
      }
      if (configuration == null) {
        return const CheckoutCatalogRefreshResult(
          CheckoutCatalogRefreshKind.configurationUnavailable,
        );
      }
      if (!_owns(captured)) return _sessionChanged();

      final categories = <TenantCategory>[];
      var categoriesComplete = false;
      String? cursor;
      while (categories.length < _maximumCategories) {
        final TenantCatalogPage<TenantCategory> page;
        try {
          page = await repository.loadCategories(
            pageSize: _pageSize,
            cursor: cursor,
          );
        } catch (_) {
          return const CheckoutCatalogRefreshResult(
            CheckoutCatalogRefreshKind.unavailable,
          );
        }
        if (!_owns(captured)) return _sessionChanged();
        categories.addAll(page.items);
        cursor = page.nextCursor;
        if (!page.hasMore || cursor == null) {
          categoriesComplete = true;
          break;
        }
      }

      final products = <TenantProduct>[];
      var productsComplete = false;
      cursor = null;
      while (products.length < _maximumProducts) {
        final TenantCatalogPage<TenantProduct> page;
        try {
          page = await repository.loadProducts(
            pageSize: _pageSize,
            cursor: cursor,
          );
        } catch (_) {
          return const CheckoutCatalogRefreshResult(
            CheckoutCatalogRefreshKind.unavailable,
          );
        }
        if (!_owns(captured)) return _sessionChanged();
        // **A retired product is not cached, so the till cannot sell it - with
        // or without a connection.** Filtered here rather than in the query on
        // purpose: this pass already reads every product to build the cache, so
        // dropping them costs nothing, while an equality filter on the server
        // would need a composite index beside the category and search filters
        // the catalog screen already uses.
        products.addAll(page.items.where((product) => !product.retired));
        cursor = page.nextCursor;
        if (!page.hasMore || cursor == null) {
          productsComplete = true;
          break;
        }
      }

      if (!_owns(captured)) return _sessionChanged();
      final complete = categoriesComplete && productsComplete;
      try {
        await _cache.write(
          uid: captured.uid,
          tenantId: captured.tenantId,
          configuration: configuration,
          categories: categories,
          products: products,
          complete: complete,
        );
      } catch (_) {
        return const CheckoutCatalogRefreshResult(
          CheckoutCatalogRefreshKind.storageUnavailable,
        );
      }
      return CheckoutCatalogRefreshResult(
        CheckoutCatalogRefreshKind.completed,
        categories: categories.length,
        products: products.length,
        complete: complete,
      );
    } finally {
      _running = false;
      if (_rerunRequested) {
        _rerunRequested = false;
        unawaited(
          Future<CheckoutCatalogRefreshResult>.microtask(
            refreshSelectedSession,
          ),
        );
      }
    }
  }

  bool _owns(TenantSession captured) {
    final current = _sessionController.session;
    return current != null &&
        current.uid == captured.uid &&
        current.tenantId == captured.tenantId &&
        current.epoch == captured.epoch;
  }

  CheckoutCatalogRefreshResult _sessionChanged() =>
      const CheckoutCatalogRefreshResult(
        CheckoutCatalogRefreshKind.sessionChanged,
      );
}

DateTime _utcNow() => DateTime.now().toUtc();
