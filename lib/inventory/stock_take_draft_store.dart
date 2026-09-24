/// The count on this device, held until it is sent.
///
/// **Counting happens on the shop floor, and the shop floor has no signal.** So
/// every number typed is written here before anything else happens to it, and a
/// count survives the app being killed mid-aisle. That is not a nicety: a stock
/// take is an hour of somebody's attention, and losing it halfway is worse than
/// never having started.
///
/// **One draft per person, per business.** Two people counting different
/// categories on the same day hold two takes on two devices; this store never
/// merges counts, because a take belongs to whoever opened it and the server
/// refuses lines from anybody else.
///
/// The box is encrypted with the same key every other durable store on this
/// device uses. A count is not a secret, but what it implies about a shop's
/// stock is somebody's business alone.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../checkout/checkout_outbox.dart';
import '../tenancy/tenant_id.dart';
import 'stock_take.dart';

/// Where a count in progress is kept.
abstract interface class TenantStockTakeDraftSource {
  /// The count open for this session, or null when there is none.
  TenantStockTakeDraft? draftFor({
    required String uid,
    required String tenantId,
  });

  /// Stores [draft], replacing whatever this session last held.
  Future<void> save({required String uid, required TenantStockTakeDraft draft});

  /// Discards it, which is what submitting and abandoning both end with.
  Future<void> clear({required String uid, required String tenantId});
}

/// What this device knows about counts already handed in.
///
/// **Local, not server, and that is the point.** A count reaches the server
/// through the outbox, which may not drain for hours; asking the server whether
/// somebody has counted would ask a cashier to count twice every time the signal
/// was poor. The obligation is discharged the moment the pages are durable here.
abstract interface class TenantStockTakeObligationSource {
  /// The scope keys this person has already handed in for that business day.
  Set<String> satisfiedScopes({
    required String uid,
    required String tenantId,
    required String businessDate,
  });

  /// Records that they have.
  Future<void> markSatisfied({
    required String uid,
    required String tenantId,
    required String businessDate,
    required String scopeKey,
  });
}

/// The storage key one day's discharged obligations are held under.
String tenantStockTakeObligationKey({
  required String uid,
  required String tenantId,
  required String businessDate,
}) {
  if (uid.isEmpty || uid.contains('/')) {
    throw ArgumentError.value(uid, 'uid', 'must be a plain identifier');
  }
  return 'stock-take-done::$uid::${validateTenantId(tenantId)}::$businessDate';
}

/// The storage key one session's count is held under.
String tenantStockTakeDraftKey({
  required String uid,
  required String tenantId,
}) {
  if (uid.isEmpty || uid.contains('/')) {
    throw ArgumentError.value(uid, 'uid', 'must be a plain identifier');
  }
  return 'stock-take::$uid::${validateTenantId(tenantId)}';
}

DateTime _utcNow() => DateTime.now().toUtc();

final class HiveTenantStockTakeDrafts extends ChangeNotifier
    implements TenantStockTakeDraftSource, TenantStockTakeObligationSource {
  HiveTenantStockTakeDrafts._(this._box, this._clock);

  static const String boxName = 'tenant-stock-take-drafts-v1';

  final Box<dynamic> _box;
  final DateTime Function() _clock;

  static Future<HiveTenantStockTakeDrafts> open({
    required CheckoutOutboxEncryptionKeyProvider keyProvider,
    HiveInterface? hive,
    DateTime Function()? clock,
  }) async {
    final key = await keyProvider.loadOrCreateKey();
    if (key.length != HiveCheckoutOutbox.encryptionKeyBytes) {
      throw const TenantStockTakeException(
        TenantStockTakeFailure.draftUnreadable,
      );
    }
    final box = await (hive ?? Hive).openBox<dynamic>(
      boxName,
      encryptionCipher: HiveAesCipher(List<int>.from(key)),
      crashRecovery: false,
    );
    return HiveTenantStockTakeDrafts._(box, clock ?? _utcNow);
  }

  factory HiveTenantStockTakeDrafts.fromBox(
    Box<dynamic> box, {
    DateTime Function()? clock,
  }) => HiveTenantStockTakeDrafts._(box, clock ?? _utcNow);

  /// This device's clock, which is also what stamps each counted line.
  DateTime now() => _clock();

  @override
  TenantStockTakeDraft? draftFor({
    required String uid,
    required String tenantId,
  }) {
    final String key;
    try {
      key = tenantStockTakeDraftKey(uid: uid, tenantId: tenantId);
    } on ArgumentError {
      return null;
    }
    final raw = _box.get(key);
    if (raw is! Map) return null;
    try {
      return TenantStockTakeDraft.fromStorage(Map<Object?, Object?>.from(raw));
    } on TenantStockTakeException {
      // **A draft that cannot be read is discarded, not surfaced.** There is
      // nothing a person could do with a half-parsed count, and leaving it in
      // place would refuse every new take on this device for good.
      unawaited(_box.delete(key));
      return null;
    }
  }

  @override
  Future<void> save({
    required String uid,
    required TenantStockTakeDraft draft,
  }) async {
    await _box.put(
      tenantStockTakeDraftKey(uid: uid, tenantId: draft.tenantId),
      draft.toStorage(),
    );
    notifyListeners();
  }

  @override
  Future<void> clear({required String uid, required String tenantId}) async {
    await _box.delete(tenantStockTakeDraftKey(uid: uid, tenantId: tenantId));
    notifyListeners();
  }

  @override
  Set<String> satisfiedScopes({
    required String uid,
    required String tenantId,
    required String businessDate,
  }) {
    final String key;
    try {
      key = tenantStockTakeObligationKey(
        uid: uid,
        tenantId: tenantId,
        businessDate: businessDate,
      );
    } on ArgumentError {
      return const <String>{};
    }
    final raw = _box.get(key);
    if (raw is! List) return const <String>{};
    return <String>{
      for (final entry in raw)
        if (entry is String) entry,
    };
  }

  @override
  Future<void> markSatisfied({
    required String uid,
    required String tenantId,
    required String businessDate,
    required String scopeKey,
  }) async {
    final key = tenantStockTakeObligationKey(
      uid: uid,
      tenantId: tenantId,
      businessDate: businessDate,
    );
    // **Keyed by the business day, so it expires on its own.** Nothing prunes
    // these: a handful of short strings per counting day is not worth a sweep,
    // and a record of yesterday cannot satisfy today because today's key is a
    // different one.
    final satisfied = <String>{
      ...satisfiedScopes(
        uid: uid,
        tenantId: tenantId,
        businessDate: businessDate,
      ),
      scopeKey,
    };
    await _box.put(key, satisfied.toList());
    notifyListeners();
  }
}
