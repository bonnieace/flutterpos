/// The unfinished import on this device, held until every page has answered.
///
/// **An import is the one catalog change that cannot be repeated safely.** A
/// correction names the product it corrects; a create names nothing, so the
/// server's only defence against writing a product twice is the request ID it
/// was asked under. That key lived in a plan object built at preview time and
/// died with it, so a chain that stopped halfway could only be recovered by
/// previewing again - which built a new plan, minted new keys, and asked the
/// server to create four hundred products it had already created.
///
/// So the keys are written here first, and the recovery re-sends them rather
/// than rebuilding them. See [TenantProductImportAttempt] for what one holds and
/// why the sheet itself is deliberately not part of it.
///
/// **One attempt per person, per business.** Two people importing different
/// sheets into one business hold two attempts on two devices, and neither can
/// resume the other's: the server keys its idempotency record on the actor as
/// well as the request, so somebody else's key would answer nothing.
///
/// The box is encrypted with the same key every other durable store on this
/// device uses. A product list is not a secret, but what it and its opening
/// balances say about a shop is that shop's business alone.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../checkout/checkout_outbox.dart';
import '../tenancy/tenant_id.dart';
import 'bulk_catalog.dart';

/// Where an import that has not finished is kept.
abstract interface class TenantProductImportAttemptSource {
  /// The unfinished import for this session, or null when there is none.
  ///
  /// **Synchronous, because it is read during `build`.** Hive answers an open
  /// box from memory, and the surface that shows a recovery has to know whether
  /// to offer one before it draws anything - the same reason the image drafts
  /// and the stock-take drafts read this way.
  TenantProductImportAttempt? attemptFor({
    required String uid,
    required String tenantId,
  });

  /// Stores [attempt], replacing whatever this session last held.
  Future<void> save({
    required String uid,
    required TenantProductImportAttempt attempt,
  });

  /// Discards it, which is what finishing and abandoning both end with.
  Future<void> clear({required String uid, required String tenantId});
}

/// The storage key one session's unfinished import is held under.
String tenantProductImportAttemptKey({
  required String uid,
  required String tenantId,
}) {
  if (uid.isEmpty || uid.contains('/')) {
    throw ArgumentError.value(uid, 'uid', 'must be a plain identifier');
  }
  return 'product-import::$uid::${validateTenantId(tenantId)}';
}

final class HiveTenantProductImportAttempts extends ChangeNotifier
    implements TenantProductImportAttemptSource {
  HiveTenantProductImportAttempts._(this._box);

  static const String boxName = 'tenant-product-import-attempts-v1';

  final Box<dynamic> _box;

  static Future<HiveTenantProductImportAttempts> open({
    required CheckoutOutboxEncryptionKeyProvider keyProvider,
    HiveInterface? hive,
  }) async {
    final key = await keyProvider.loadOrCreateKey();
    if (key.length != HiveCheckoutOutbox.encryptionKeyBytes) {
      throw const TenantBulkCatalogException('attempt_unreadable');
    }
    final box = await (hive ?? Hive).openBox<dynamic>(
      boxName,
      encryptionCipher: HiveAesCipher(List<int>.from(key)),
      crashRecovery: false,
    );
    return HiveTenantProductImportAttempts._(box);
  }

  factory HiveTenantProductImportAttempts.fromBox(Box<dynamic> box) =>
      HiveTenantProductImportAttempts._(box);

  @override
  TenantProductImportAttempt? attemptFor({
    required String uid,
    required String tenantId,
  }) {
    final String key;
    try {
      key = tenantProductImportAttemptKey(uid: uid, tenantId: tenantId);
    } on ArgumentError {
      return null;
    }
    final raw = _box.get(key);
    if (raw is! Map) return null;
    try {
      return TenantProductImportAttempt.fromStorage(
        Map<Object?, Object?>.from(raw),
      );
    } on TenantBulkCatalogException {
      // **An attempt that cannot be read is discarded, not surfaced.** The only
      // thing it is for is re-sending a request field for field, and one that
      // cannot be read cannot do that - so offering it would offer a recovery
      // that fails every time it is pressed, and keeping it would say an import
      // is unfinished for ever.
      unawaited(_box.delete(key));
      return null;
    }
  }

  @override
  Future<void> save({
    required String uid,
    required TenantProductImportAttempt attempt,
  }) async {
    await _box.put(
      tenantProductImportAttemptKey(uid: uid, tenantId: attempt.tenantId),
      attempt.toStorage(),
    );
    notifyListeners();
  }

  @override
  Future<void> clear({required String uid, required String tenantId}) async {
    await _box.delete(
      tenantProductImportAttemptKey(uid: uid, tenantId: tenantId),
    );
    notifyListeners();
  }
}
