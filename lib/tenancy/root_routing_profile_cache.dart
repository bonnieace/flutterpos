import 'dart:convert';

import 'package:hive/hive.dart';

import 'tenant_bootstrap.dart';
import 'tenant_selection.dart';

/// The root routing projection last answered for one authenticated account.
final class CachedRootRoutingProfile {
  const CachedRootRoutingProfile({
    required this.profile,
    required this.cachedAt,
  });

  final RootRoutingProfile profile;
  final DateTime cachedAt;
}

abstract interface class RootRoutingProfileCache {
  Future<CachedRootRoutingProfile?> read(String uid);
  Future<void> write(String uid, RootRoutingProfile profile);
}

final class NullRootRoutingProfileCache implements RootRoutingProfileCache {
  const NullRootRoutingProfileCache();

  @override
  Future<CachedRootRoutingProfile?> read(String uid) async => null;

  @override
  Future<void> write(String uid, RootRoutingProfile profile) async {}
}

/// A forgiving, UID-bound cache stored beside tenant selection and directory.
final class HiveRootRoutingProfileCache implements RootRoutingProfileCache {
  const HiveRootRoutingProfileCache(this._box);

  static const int schemaVersion = 1;

  final Box<String> _box;

  @override
  Future<CachedRootRoutingProfile?> read(String uid) async {
    final String key;
    try {
      key = rootRoutingProfileStorageKey(uid);
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
      if (map['schemaVersion'] != schemaVersion || map['uid'] != uid.trim()) {
        return null;
      }
      final cachedAtMs = map['cachedAtMs'];
      final rawProfile = map['profile'];
      if (cachedAtMs is! int || rawProfile is! Map) return null;
      return CachedRootRoutingProfile(
        profile: RootRoutingProfile.fromJson(
          rawProfile.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          ),
        ),
        cachedAt: DateTime.fromMillisecondsSinceEpoch(cachedAtMs, isUtc: true),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String uid, RootRoutingProfile profile) async {
    await _box.put(
      rootRoutingProfileStorageKey(uid),
      jsonEncode(<String, Object?>{
        'schemaVersion': schemaVersion,
        'uid': uid.trim(),
        'cachedAtMs': DateTime.now().toUtc().millisecondsSinceEpoch,
        'profile': profile.toJson(),
      }),
    );
  }
}
