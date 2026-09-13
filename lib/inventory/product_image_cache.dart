/// The pictures this device has already downloaded, kept on disk.
///
/// **The gap this closes, which `TenantProductVisual` has recorded since it was
/// written.** `NetworkImage` is cached in memory and only in memory: a cold
/// start downloads every photograph in the catalog again, and a shop with no
/// signal draws a grid of initials over a catalog it is otherwise holding
/// offline in full. That note ends "recorded here rather than fixed here,
/// because a durable cache is a store with an eviction policy and a size
/// budget rather than a line in a widget". This is that store.
///
/// **Two boxes, and the reason is memory.** Hive keeps every value of an open
/// `Box` in RAM, which for a picture cache is the exact opposite of the point,
/// so the bytes live in a `LazyBox` that reads one entry at a time from disk.
/// What has to be resident is the index - a URL, a length and a timestamp per
/// picture - which is a few dozen bytes each and is what makes an eviction pass
/// possible without touching a single image.
///
/// **Not encrypted, unlike the draft box next door.** A draft is a photograph
/// that exists nowhere else yet; these are copies of objects already published
/// to Storage, whose download URLs this device holds in plain text in the
/// Firestore cache anyway. Encrypting them would buy nothing and would put an
/// AES pass on the path of every thumbnail the till draws.
///
/// **A failure here is always a miss.** Every entry point swallows its own
/// errors: a corrupt box, a full disk or a key that will not parse must draw
/// the picture from the network, never break the screen showing it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

/// What one cached picture is, apart from its bytes.
final class _CachedImageEntry {
  const _CachedImageEntry({
    required this.length,
    required this.usedAtMs,
    required this.url,
  });

  static _CachedImageEntry? fromStorage(Object? record) {
    if (record is! Map) return null;
    final length = record['length'];
    final usedAt = record['usedAtMs'];
    final url = record['url'];
    if (length is! int || usedAt is! int || url is! String) return null;
    if (length <= 0) return null;
    return _CachedImageEntry(length: length, usedAtMs: usedAt, url: url);
  }

  final int length;
  final int usedAtMs;
  final String url;

  Map<String, Object?> toStorage() => <String, Object?>{
    'length': length,
    'usedAtMs': usedAtMs,
    'url': url,
  };
}

/// The narrow read and write a picture needs, so a widget can depend on this
/// rather than on Hive.
abstract interface class TenantImageCache {
  /// The bytes held for [url], or null for a miss.
  Future<Uint8List?> read(Uri url);

  /// Keeps [bytes] against [url], evicting the least recently used pictures
  /// until the store is inside its budget again.
  Future<void> write(Uri url, Uint8List bytes);
}

final class HiveTenantImageCache implements TenantImageCache {
  HiveTenantImageCache._(
    this._bytes,
    this._index,
    this._budgetBytes,
    this._clock,
  );

  static const String bytesBoxName = 'tenant-image-bytes-v1';
  static const String indexBoxName = 'tenant-image-index-v1';

  /// How much of the phone this may use.
  ///
  /// **Forty-eight megabytes, against pictures bounded at about two hundred
  /// kilobytes** by `normalizeTenantImage` - so a couple of hundred products,
  /// which is more than the two thousand-product ceiling the catalog refresher
  /// works to but comfortably a whole shop's worth of what anybody actually
  /// looks at.
  static const int defaultBudgetBytes = 48 * 1024 * 1024;

  /// A picture larger than this is drawn but never kept: one of them would
  /// evict a quarter of the store.
  static const int maximumEntryBytes = 4 * 1024 * 1024;

  static Future<HiveTenantImageCache> open({
    HiveInterface? hive,
    int budgetBytes = defaultBudgetBytes,
    DateTime Function()? clock,
  }) async {
    final store = hive ?? Hive;
    final bytes = await store.openLazyBox<Uint8List>(
      bytesBoxName,
      crashRecovery: false,
    );
    final index = await store.openBox<dynamic>(
      indexBoxName,
      crashRecovery: false,
    );
    return HiveTenantImageCache._(bytes, index, budgetBytes, clock ?? _utcNow);
  }

  factory HiveTenantImageCache.fromBoxes({
    required LazyBox<Uint8List> bytes,
    required Box<dynamic> index,
    int budgetBytes = defaultBudgetBytes,
    DateTime Function()? clock,
  }) => HiveTenantImageCache._(bytes, index, budgetBytes, clock ?? _utcNow);

  final LazyBox<Uint8List> _bytes;
  final Box<dynamic> _index;
  final int _budgetBytes;
  final DateTime Function() _clock;

  @override
  Future<Uint8List?> read(Uri url) async {
    final key = _keyFor(url);
    try {
      final entry = _CachedImageEntry.fromStorage(_index.get(key));
      if (entry == null) return null;
      final bytes = await _bytes.get(key);
      if (bytes == null || bytes.isEmpty) {
        // The index and the bytes disagree, which is the one state a crash
        // between the two writes can leave. The index is what is wrong.
        await _forget(key);
        return null;
      }
      // **The touch is not awaited.** It is what makes eviction least-recently-
      // used rather than arbitrary, and nothing on the drawing path should wait
      // on a disk write to find out that it already has the picture.
      unawaited(
        _index.put(
          key,
          _CachedImageEntry(
            length: bytes.length,
            usedAtMs: _clock().millisecondsSinceEpoch,
            url: url.toString(),
          ).toStorage(),
        ),
      );
      return bytes;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(Uri url, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maximumEntryBytes) return;
    final key = _keyFor(url);
    try {
      await _bytes.put(key, bytes);
      await _index.put(
        key,
        _CachedImageEntry(
          length: bytes.length,
          usedAtMs: _clock().millisecondsSinceEpoch,
          url: url.toString(),
        ).toStorage(),
      );
      await _evictToBudget();
    } on Object {
      // A store that will not take a picture is a store that does not have it.
    }
  }

  /// Drops the least recently used pictures until the total is inside budget.
  Future<void> _evictToBudget() async {
    final entries = <String, _CachedImageEntry>{};
    var total = 0;
    for (final key in _index.keys) {
      if (key is! String) continue;
      final entry = _CachedImageEntry.fromStorage(_index.get(key));
      if (entry == null) {
        await _forget(key);
        continue;
      }
      entries[key] = entry;
      total += entry.length;
    }
    if (total <= _budgetBytes) return;
    final oldest = entries.keys.toList(growable: false)
      ..sort((a, b) => entries[a]!.usedAtMs.compareTo(entries[b]!.usedAtMs));
    for (final key in oldest) {
      if (total <= _budgetBytes) return;
      total -= entries[key]!.length;
      await _forget(key);
    }
  }

  Future<void> _forget(String key) async {
    try {
      await _bytes.delete(key);
      await _index.delete(key);
    } on Object {
      // Nothing to do about a delete that will not: the next pass tries again.
    }
  }

  /// The URL, hashed, because a Storage download URL is longer than Hive's own
  /// key limit and carries a token nobody needs written twice.
  static String _keyFor(Uri url) =>
      sha256.convert(utf8.encode(url.toString())).toString();
}

DateTime _utcNow() => DateTime.now().toUtc();
