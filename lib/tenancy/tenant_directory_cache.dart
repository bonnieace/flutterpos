/// The device's own copy of what `listMyTenants` last returned.
///
/// **Why this exists.** `listMyTenants` is a Cloud Functions callable, and a
/// callable has no cache, no queue and no offline mode - it throws. It sits on
/// the mandatory startup path twice, so before this file a device with no
/// network could not open a business *even though* the sale path, the catalog,
/// the receipt counters and the shift state are all already on disk. The app
/// was offline-first everywhere except the door.
///
/// **It stores the projection, not a decision.** `resolveTenantSelection` is a
/// pure function over these memberships, so a cached list routes through
/// exactly the same precedence a live one does. Nothing here decides anything;
/// it only remembers what the server last said, so that the existing logic has
/// something to run on.
///
/// **Reading is deliberately forgiving and writing is not.** A cache that
/// cannot be parsed answers `null` - the same as never having one - because a
/// corrupt local file must never be the reason a till will not open. A cache
/// that cannot be *written* is likewise swallowed by the caller: failing a
/// successful sign-in over a bookkeeping write would be trading the thing that
/// worked for the thing that did not.
library;

import 'dart:convert';

import 'package:hive/hive.dart';

import 'tenant_membership.dart';
import 'tenant_selection.dart';

/// What a device remembers of one account's businesses.
final class CachedTenantDirectory {
  const CachedTenantDirectory({
    required this.memberships,
    required this.cachedAt,
  });

  final List<TenantMembership> memberships;

  /// When the server last answered. Carried so a surface can say *how* stale
  /// what it is showing happens to be, which §"offline truthfulness" asks for.
  final DateTime cachedAt;
}

abstract interface class TenantDirectoryCache {
  Future<CachedTenantDirectory?> read(String uid);
  Future<void> write(String uid, Iterable<TenantMembership> memberships);
}

/// A cache that never answers. The default where no store is composed in, so
/// every caller can hold a non-null cache and skip the null checks.
final class NullTenantDirectoryCache implements TenantDirectoryCache {
  const NullTenantDirectoryCache();

  @override
  Future<CachedTenantDirectory?> read(String uid) async => null;

  @override
  Future<void> write(
    String uid,
    Iterable<TenantMembership> memberships,
  ) async {}
}

/// The durable implementation, in the box the tenant selection already uses.
///
/// **The same box rather than a new one**, because these are two halves of one
/// fact and opening a second box would add another `await` to startup for no
/// gain. See [tenantDirectoryStorageKey].
final class HiveTenantDirectoryCache implements TenantDirectoryCache {
  const HiveTenantDirectoryCache(this._box);

  /// Bumped only when the stored shape changes. An unrecognised version reads
  /// as absent rather than as an error, so an upgrade can never strand a till.
  static const schemaVersion = 1;

  final Box<String> _box;

  @override
  Future<CachedTenantDirectory?> read(String uid) async {
    final String key;
    try {
      key = tenantDirectoryStorageKey(uid);
    } on ArgumentError {
      return null;
    }
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (map['schemaVersion'] != schemaVersion) return null;
      // The uid is stored as well as keyed on, so a box that somehow answered
      // the wrong key cannot hand one account another account's businesses.
      if (map['uid'] != uid.trim()) return null;
      final cachedAtMs = map['cachedAtMs'];
      final items = map['items'];
      if (cachedAtMs is! int || items is! List) return null;
      final memberships = <TenantMembership>[];
      for (final item in items) {
        if (item is! Map) return null;
        memberships.add(
          TenantMembership.fromJson(
            item.map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        );
      }
      return CachedTenantDirectory(
        memberships: List.unmodifiable(memberships),
        cachedAt: DateTime.fromMillisecondsSinceEpoch(cachedAtMs, isUtc: true),
      );
    } on FormatException {
      // Malformed JSON, or a membership the current code cannot read. Either
      // way this device has no usable memory of its businesses, which is
      // exactly what `null` means.
      return null;
    }
  }

  @override
  Future<void> write(String uid, Iterable<TenantMembership> memberships) async {
    final key = tenantDirectoryStorageKey(uid);
    await _box.put(
      key,
      jsonEncode(<String, Object?>{
        'schemaVersion': schemaVersion,
        'uid': uid.trim(),
        'cachedAtMs': DateTime.now().toUtc().millisecondsSinceEpoch,
        'items': <Object?>[
          for (final membership in memberships) membership.toJson(),
        ],
      }),
    );
  }
}
